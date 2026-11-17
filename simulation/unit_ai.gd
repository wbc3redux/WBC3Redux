extends RefCounted
## Unit attitude scripts (milestone 9): the original's nine built-in UnitAIV1 scripts (built in code by 0x506c40,
## decoded into unit_ai_scripts.json by tools/emulate_unit_ai.py), the executor 0x5070f0 with the rule test 0x507560,
## the conditions, the actions, the hit list 0x505b90 and flight 0x522f40. Evidence labels: ENCOUNTERS_RESEARCH.md.
## `decide` is the executor as a pure function (Emulated: every case of tests/unit_ai_fixtures.json "executor");
## the world part below drives Combat with it.
const Rules = preload("res://simulation/combat_rules.gd")
const PATH := "res://simulation/unit_ai_scripts.json"

# Script cadence (9-fix, REVIEW_ENCOUNTERS.md D1). 0x429ec0 counts its own calls modulo 10; it is called from the in-game
# panel's event 9, sent only by 0x4606a0 on WM_TIMER id 1, created by SetTimer(hWnd, 1, 0x32) (0x45a7b0): Read. Windows
# rounds the 50 ms to its timer tick (about 62.5 ms at 15.6 ms resolution); the game imports no timeBeginPeriod, but it keeps
# timeSetEvent(25 ms, resolution 10 ms) running from start-up (0x457190) to exit, which requests a finer system resolution,
# so the nominal 50 ms is the default. The real period on a given machine is Open (50 .. 62.5 ms per tick).
const UI_TIMER_MS := 50
const PASS_TICKS := 10                   # one script pass per 10 timer ticks: 500 ms nominal
const HIT_KEEP_MS := 4000                # 0x505c40: hit entries older than 4 s are dropped ...
const HIT_SWEEP_MS := 1000               # ... by a pass that runs at most once a second (Emulated)
const SEARCH_MIN := 12                   # 0x507790 / 0x508650: window r = max(12, attack range)
const FLEE_NEAR := 5                     # 0x508c10: window +-5 around the subject
const FLIGHT_HOP := 4                    # 0x522f40: two hops of four cells away from the threat (Emulated)
const STANDARD_SCRIPT := 6               # 0x5070f0: a leader-bound script whose leader is gone switches to script 6
const DEFAULT_SCRIPT := 2                # unit creation 0x519fd0: ARM +0xf6 (non-zero forced to 2 by 0x41b3d0); heroes 2
const NEUTRAL := 6
# 0x528280: hard-coded animal IDs (sheep, cow, goat, pig, camel, ACSO when asked with 0, turtle, ACSE).
const ANIMALS := ["ACSH", "ACCO", "ACGO", "ACPE", "ACCA", "ACSO", "ACTU", "ACSE"]

var data: Dictionary
var scripts: Array = []
## The Combat world, held weakly: Combat owns this object (`combat.ai`), so a strong reference back would be a
## RefCounted cycle and leak every world (REVIEW_ENCOUNTERS.md D7).
var _world: WeakRef
var combat:
	get: return _world.get_ref() if _world != null else null
	set(value): _world = weakref(value) if value != null else null
var hits: Array = []                      # [{"attacker", "victim", "t"}] in arrival order (0x23994 list)
var hit_sweep_ms := -1                    # 0x23998
var update_counter := 0                   # 0x74c590 low byte: timer ticks modulo 10
var next_tick_ms := UI_TIMER_MS           # due time of the next WM_TIMER tick on the game clock
var pass_now := false                     # a script pass ran in this game update (towers use the same pass)
var enabled := true                       # harness switch (the original always runs them)
var animal_idle := true
var actions_log: Array = []

static func load_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))

func _init(world = null, source: Dictionary = {}):
	combat = world
	data = source if not source.is_empty() else load_data()
	scripts = data.scripts

static func script_name(index: int) -> String:
	return ["Cowardly", "Stand Ground", "Defensive", "Aggressive", "Rampant", "Scout", "Standard", "Guardian", "Magic Guardian"][index] if index >= 0 and index < 9 else "none"

static func is_animal(type_id: String, asking_zero: bool = true) -> bool:
	if type_id == "ACSO": return asking_zero
	return ANIMALS.has(type_id)

# ======================================================================================= pure executor (Emulated)
## One run of 0x5070f0 for one unit. state: {"order": "none"|"busy"|"ai"|"finished", "leader": "none"|"alive"|"dying"|
## "missing", "leader_flag": 0/1, "hero": bool}. evaluate(condition, subject_tag) returns the condition's result.
## Returns {"set_script": -1|6, "action": null|{name, type, subject, param}, "pop": bool, "calls": [...]}.
## `trace` false (the match, P-3): "calls" stays empty; the decision is the same.
static func decide(script: Dictionary, state: Dictionary, evaluate: Callable, trace: bool = true) -> Dictionary:
	var out := {"set_script": -1, "action": null, "pop": false, "calls": []}
	if int(script.uses_leader) != 0 and int(state.leader_flag) == 0 and state.leader != "none" and (state.leader == "missing" or state.leader == "dying"):
		out.set_script = STANDARD_SCRIPT
		return out
	var best := -1
	for i in range(10):
		var rule: Dictionary = script.rules[i]
		if int(rule.enabled) == 0: continue
		if not _rule_true(rule, state, evaluate, out.calls, trace): continue
		if best == -1 or int(rule.priority) > int(script.rules[best].priority): best = i
	var action: Dictionary
	if best == -1:
		if state.order == "busy" or state.order == "ai": return out           # an unfinished order keeps running
		if int(script.default.active) == 0:
			out.pop = state.order == "finished"
			return out
		action = script.default
	else:
		action = script.rules[best].action
	if int(action.active) == 0:
		out.pop = state.order == "finished"
		return out
	out.action = {"name": action.name, "type": int(action.type), "subject": subject_tag(int(action.subject), state), "param": int(action.param),
		"rule": best, "busy_ok": int(script.rules[best].busy_ok) if best >= 0 else 0}
	return out

## 0x507560: false when the rule may not interrupt (+0x75 == 0) and the unit runs an order it may not leave
## (order present, +0x1d unfinished, +0x1c not interruptible); every active condition must hold and have a subject;
## a rule without active conditions is false.
static func _rule_true(rule: Dictionary, state: Dictionary, evaluate: Callable, calls: Array, trace: bool = true) -> bool:
	if int(rule.busy_ok) == 0 and state.order == "busy": return false
	var result := false
	for c in rule.conditions:
		if int(c.active) == 0: continue
		var subject = subject_tag(int(c.subject), state)
		if subject == null: return false
		result = true
		var ok: bool = evaluate.call(c, subject)
		if trace: calls.append({"cond": c.name, "subject": subject, "flag": int(c.flag), "value": int(c.value), "expected": int(c.expected), "result": 1 if ok else 0})
		if not ok: return false
	return result

## Subject codes: 0 the unit itself, 1 its owner's living hero (0x70adb4), 2 its leader (+0x13e, found in the object
## registry even while dying); anything else is no subject.
static func subject_tag(code: int, state: Dictionary) -> Variant:
	match code:
		0: return "self"
		1: return "hero" if bool(state.hero) else null
		2: return "leader" if state.leader == "alive" or state.leader == "dying" else null
	return null

# ======================================================================================= world
func fighter_state(f) -> Dictionary:
	var order := "none"
	if f.cur != null:
		order = "finished" if f.cur.finished else ("ai" if f.cur.ai else "busy")
	var leader := "none"
	if int(f.leader) >= 0:
		var l = combat.fighters.get(int(f.leader))
		if l == null or l.removed: leader = "missing"
		elif not combat.alive(l): leader = "dying"
		else: leader = "alive"
	return {"order": order, "leader": leader, "leader_flag": int(f.leader_flag), "hero": hero_of(f.owner) != null}

func hero_of(owner: int) -> Variant:
	if not combat.heroes.has(owner): return null
	var h = combat.fighters.get(combat.heroes[owner].unit)
	return h if combat.alive(h) else null

func subject_fighter(f, tag) -> Variant:
	match tag:
		"self": return f
		"hero": return hero_of(f.owner)
		"leader": return combat.fighters.get(int(f.leader))
	return null

## Called once per game update by Combat with the clock. A 50 ms UI timer tick is due when the clock reaches it
## (WM_TIMER messages do not queue up, so at most one tick per update); every 10th tick runs the scripts (local player and
## neutral in the original; the rebuild runs every owner, which is what each machine does for its own units) and the
## animal idle routine 0x532590 for the neutral player.
func on_update(now_ms: int = -1):
	pass_now = false
	if now_ms < 0: now_ms = combat.now_ms
	if now_ms < next_tick_ms: return
	next_tick_ms = now_ms + UI_TIMER_MS
	update_counter = (update_counter + 1) % PASS_TICKS
	if update_counter != 0 or not enabled: return
	pass_now = true
	_sweep_finished()
	var ids: Array = combat.fighters.keys()
	ids.sort()
	for id in ids:
		var f = combat.fighters[id]
		if not combat.alive(f) or int(f.script) < 0: continue
		if combat.units[id].inside_building: continue
		execute(f)
	if animal_idle:
		for id in ids:
			var f = combat.fighters[id]
			if combat.alive(f) and f.owner == NEUTRAL and is_animal(f.type_id, false): idle_animal(f)

## Order bookkeeping: a move is finished when the unit has no route left, an attack when Combat dropped it.
func _sweep_finished():
	for f in combat.fighters.values():
		if f.cur == null or f.cur.finished: continue
		if f.cur.kind == "attack" and f.order == null: f.cur.finished = true
		elif f.cur.kind == "move":
			var unit = combat.units[f.id]
			if unit.orders.is_empty() and not unit.in_step: f.cur.finished = true

func execute(f):
	var state := fighter_state(f)
	var result := decide(scripts[int(f.script)], state, func(c, tag): return evaluate(f, c, tag), false)
	if result.set_script >= 0:
		assign_script(f, result.set_script)
		return
	if result.pop and f.cur != null and f.cur.finished: f.cur = null
	if result.action == null: return
	var subject = subject_fighter(f, result.action.subject)
	run_action(f, result.action, subject)
	f.last_action = int(result.action.type)

func assign_script(f, index: int, leader: int = -1):
	f.script = index
	f.leader = leader
	f.leader_flag = 0
	f.guard = combat.unit_cell(f.id)          # 0x506f10: the guard point (+0x270) is the unit's cell

## The walk-step builders (0x5377a0 at 0x538573, 0x51c7d0 at 0x51c805; disassembly, AI-9) move the guard point (+0x270)
## to the new cell only while the head order (+0xc8) exists and its byte +0x1d is 0. +0x1d is the order's "inserted"
## flag (0x51d6b0's sixth / 0x51da60's fifth argument): the attitude scripts' orders set it (the search attack 0x51a470
## always, 0x51da60(t, -1, 2, 1, ...); Return to Post, Follow, Wander, the attacker and adjacent attacks with 0x508e60's
## value, 1 unless the rule has +0x75; a one-hop flight 0x522f40), player and computer-player orders do not. So a chase
## or a walk ordered by a script leaves the post where it was and Return to Post walks back to it (AI-9, Read).
func on_step(unit_id: int, to_cell: Vector2i):
	var f = combat.fighters.get(unit_id)
	if f != null and f.cur != null and not f.cur.finished and not bool(f.cur.get("inserted", false)): f.guard = to_cell

# --------------------------------------------------------------------------------------- conditions
func evaluate(f, c: Dictionary, tag) -> bool:
	var s = subject_fighter(f, tag)
	if s == null: return false
	var expected := int(c.expected) != 0
	match c.name:
		"enemy_near": return enemy_near(f, s, int(c.flag) != 0, false) == expected
		"enemy_near_post": return enemy_near(f, s, int(c.flag) != 0, true) == expected
		"alive":
			if int(c.flag) != 0 and not in_leash(s, f): return false
			return combat.alive(s) == expected
		"attacking_building", "attacking_unit":
			if int(c.flag) != 0 and not in_leash(s, f): return false
			var o = s.order
			var hit: bool = o != null and o.target_kind == ("building" if c.name == "attacking_building" else "unit") and combat.target_alive(o) \
				and not combat.allied(f.owner, combat._order_target_owner(o))
			return hit == expected
		"hp_below":
			if int(c.flag) != 0 and not in_leash(s, f): return false
			return hp_below(int(s.hp), int(s.max_hp), int(c.value), expected)
		"was_hit":
			if int(c.flag) != 0 and not in_leash(s, f): return false
			return was_hit(s.id) == expected
		"enemy_adjacent":
			if int(c.flag) != 0 and not in_leash(s, f): return false
			return (adjacent_enemy(s) != null) == expected
		"distance_below":
			return distance_below(combat.unit_cell(f.id), combat.unit_cell(s.id), s == f, int(c.flag) != 0, f.guard, radius_of(f),
				map_size(), int(c.value), expected, in_leash(s, f) if int(c.flag) != 0 else true)
	return false

func radius_of(f) -> int:
	return int(scripts[int(f.script)].radius)

func map_size() -> Vector2i:
	return Vector2i(combat.navigator.collision.width, combat.navigator.collision.height)

## 0x507d60: hit points * 100 / maximum (C division) below the value.
static func hp_below(hp: int, max_hp: int, value: int, expected: bool) -> bool:
	var pct: int = Rules.s16(Rules.tdiv(hp * 100, maxi(1, max_hp)) if max_hp != 0 else 0)
	return (pct < value) == expected

## 0x507920: Chebyshev distance below the value; the unit itself always passes; with the flag the subject must be
## inside the unit's leash box (0x508d00).
static func distance_below(me: Vector2i, other: Vector2i, same: bool, flag: bool, guard: Vector2i, radius: int, size: Vector2i,
		value: int, expected: bool, leash_ok: bool = true) -> bool:
	if same: return true
	if flag and not leash_ok: return false
	var d := maxi(absi(other.x - me.x), absi(other.y - me.y))
	return (d < value) == expected

## 0x508d00: the subject's cell lies in the box guard +- radius (guard = the unit's guard point, or its cell when
## unset). The left/top edges are clamped at 0 and the right edge at width - 1; the bottom edge is set to height - 1
## whenever guard.y + radius is below it (the original compares the wrong way round; Emulated).
func in_leash(subject, f) -> bool:
	return leash_contains(combat.unit_cell(subject.id), f.guard, combat.unit_cell(f.id), radius_of(f), map_size(), subject == f)

static func leash_contains(cell: Vector2i, guard: Vector2i, own_cell: Vector2i, radius: int, size: Vector2i, same: bool = false) -> bool:
	if same: return true
	var g := guard if guard.x != -1 and guard.y != -1 else own_cell
	var x0 := maxi(0, g.x - radius)
	var y0 := maxi(0, g.y - radius)
	var x1 := mini(size.x - 1, g.x + radius)
	var y1 := g.y + radius
	if y1 < size.y - 1: y1 = size.y - 1
	return cell.x >= x0 and cell.x <= x1 and cell.y >= y0 and cell.y <= y1

## 0x507790 / 0x5079b0: test search (0x51a470 with test = 1) in the window around the subject (or the subject's guard
## point), r = max(12, subject range); with the flag the window is intersected with the unit's guard box (no map clamp).
func enemy_near(f, s, flag: bool, around_post: bool) -> bool:
	var rect := area_window(combat.unit_cell(s.id), s.guard if around_post else Vector2i(-1, -1), int(s.stats.range), flag,
		f.guard, combat.unit_cell(f.id), radius_of(f), around_post)
	return search(f, rect, true) != null

## [x0, x1, y0, y1] as passed to 0x51a470 (Emulated: "area" fixtures).
static func area_window(subject_cell: Vector2i, subject_guard: Vector2i, subject_range: int, flag: bool, guard: Vector2i, own_cell: Vector2i,
		radius: int, around_post: bool) -> Array:
	var r := maxi(SEARCH_MIN, subject_range)
	var c := subject_cell
	# 0x5079b0: the subject's guard point, or the unit's own cell when the subject has none (Emulated).
	if around_post: c = subject_guard if subject_guard.x != -1 and subject_guard.y != -1 else own_cell
	var rect := [c.x - r, c.x + r, c.y - r, c.y + r]
	if flag:
		var g := guard if guard.x != -1 and guard.y != -1 else own_cell
		rect[0] = maxi(rect[0], g.x - radius)
		rect[2] = maxi(rect[2], g.y - radius)
		rect[1] = mini(rect[1], g.x + radius)
		rect[3] = mini(rect[3], g.y + radius)
	return rect

func search(f, rect: Array, test: bool):
	if is_animal(f.type_id): return null                       # 0x51a470 starts with 0x528280(0): animals never search
	return combat.search_rect(f.owner, combat.unit_cell(f.id), rect, f.id)

## 0x505b90 when a unit survives damage (0x522860 path); 0x505c40 prunes on its own cadence.
func record_hit(attacker_kind: String, attacker_id: int, victim_id: int, now_ms: int):
	hits.append({"attacker_kind": attacker_kind, "attacker": attacker_id, "victim": victim_id, "t": now_ms})

func prune_hits(now_ms: int):
	if hit_sweep_ms != -1 and now_ms < hit_sweep_ms + HIT_SWEEP_MS: return
	hit_sweep_ms = now_ms
	var kept: Array = []
	for h in hits:
		if h.t >= now_ms - HIT_KEEP_MS: kept.append(h)
	hits = kept

func was_hit(victim_id: int) -> bool:
	prune_hits(combat.now_ms)
	for h in hits:
		if h.victim == victim_id: return true
	return false

## 0x508260 / 0x5085e0: the attacker of the subject: the entry whose attacker is the remembered one (+0x140) wins,
## otherwise the last entry with that victim.
func attacker_of(f, victim_id: int) -> Variant:
	prune_hits(combat.now_ms)
	var found = null
	for h in hits:
		if h.victim != victim_id: continue
		found = h
		if h.attacker_kind == "unit" and h.attacker == int(f.remembered): break
	return found

## Objects in the ring around a unit's cell (x outer, y inner, as 0x507e40 / 0x508300 scan; 1x1 footprints), each with its
## owner and whether its attack descriptor has damage (0x52e9e0 / ARM +0x32). The unit itself is skipped.
func adjacent_objects(s) -> Array:
	var out: Array = []
	var here: Vector2i = combat.unit_cell(s.id)
	for x in range(here.x - 1, here.x + 2):
		for y in range(here.y - 1, here.y + 2):
			var cell := Vector2i(x, y)
			if cell == here: continue
			var c = combat.candidate_for_owner(-1, s.id, cell, false)
			if c == null: continue
			c["armed"] = combat.object_damage(c.kind, c.id) > 0
			out.append(c)
	return out

## 0x507e40 (Read, disassembled): a neutral (player 6) object counts only when it can hurt; any other object when its owner
## is hostile to the subject's. Animals and the Mausoleum therefore never make the condition true.
func adjacent_enemy(s) -> Variant:
	for c in adjacent_objects(s):
		if c.owner == NEUTRAL:
			if c.armed: return c
		elif c.owner != s.owner and not combat.allied(c.owner, s.owner):
			return c
	return null

## 0x508300 (Read, disassembled): an armed neutral, or a hostile object that is the remembered attacker (+0x140), is taken at
## once; otherwise the last candidate of the scan (an unarmed neutral or another hostile object).
func adjacent_target(f) -> Variant:
	var last = null
	for c in adjacent_objects(f):
		if c.owner == NEUTRAL:
			last = c
			if c.armed: return c
		elif c.owner != f.owner and not combat.allied(c.owner, f.owner):
			last = c
			if c.kind == "unit" and c.id == int(f.remembered): return c
	return last

# --------------------------------------------------------------------------------------- actions
func run_action(f, action: Dictionary, subject):
	var interruptible: bool = int(action.busy_ok) == 0          # 0x508e60: orders from ordinary rules may be interrupted
	actions_log.append({"t": combat.now_ms, "unit": f.id, "action": action.name})
	match action.name:
		"attack_near", "attack_near_post":
			if subject == null: return
			var c: Vector2i = combat.unit_cell(subject.id)
			if action.name == "attack_near_post" and subject.guard.x != -1 and subject.guard.y != -1: c = subject.guard
			var r := maxi(SEARCH_MIN, int(subject.stats.range))
			attack_best(f, [c.x - r, c.x + r, c.y - r, c.y + r], false)
		"flee_near":
			if subject == null: return
			var c: Vector2i = combat.unit_cell(subject.id)
			attack_best(f, [c.x - FLEE_NEAR, c.x + FLEE_NEAR, c.y - FLEE_NEAR, c.y + FLEE_NEAR], true)
		"return_post":
			if f.guard.x == -1 or f.guard.y == -1: return
			# 0x508ba0 / 0x5081b0 / 0x508930 look at the order at +0xc8 whether or not it has finished (+0x1d): a finished
			# move to the same goal stays there (Defensive's default never pops it), so nothing new is issued.
			if f.cur != null and f.cur.kind == "move" and f.cur.goal == f.guard: return
			move(f, f.guard, interruptible)
		"follow":
			if subject == null or subject == f: return
			# 0x5081b0: keep a running move whose goal is within 5 cells of the subject (8 for a building subject).
			var target: Vector2i = combat.unit_cell(subject.id)
			if f.cur != null and f.cur.kind == "move" and Navigation_chebyshev(f.cur.goal, target) < 5: return
			move(f, target, interruptible)
		"attack_attacker":
			if subject == null: return
			var h = attacker_of(f, subject.id)
			if h == null:
				run_action(f, {"name": "follow", "busy_ok": action.busy_ok}, subject)
				return
			if h.attacker_kind == "unit":
				if f.order == null or f.order.target_id != h.attacker: combat.order_attack(f.id, "unit", h.attacker, true, -1, int(interruptible))
				f.remembered = h.attacker
		"flee":
			if subject == null: return
			if int(f.last_action) == 4 and f.cur != null and f.cur.finished: return       # 0x508e20(4)
			var h = attacker_of(f, subject.id)
			if h == null: return
			flee_from(f, combat.object_cell(h.attacker_kind, h.attacker), combat.object_owner(h.attacker_kind, h.attacker))
			f.remembered = h.attacker
		"attack_adjacent":
			var c = adjacent_target(f)
			if c != null and (f.order == null or f.order.target_id != c.id): combat.order_attack(f.id, c.kind, c.id, true, -1, int(interruptible))
		"wander":
			if int(f.last_action) == 7 and f.cur != null and f.cur.finished: return       # 0x508e20(7)
			wander(f, int(action.param) != 0, interruptible)
		"patrol_post":
			patrol(f, interruptible)
		"go_home":
			pass                                                  # start position of the owner (0x708fa8): no slice script uses it

static func Navigation_chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

## 0x51a470 (test = 0): the best target in the rectangle; attack it with an interruptible order (0x51da60 mode 2,
## +0x1c = 1) or flee from it (0x522f40). Already attacking the best target: nothing changes.
func attack_best(f, rect: Array, flee: bool):
	var best = search(f, rect, false)
	if best == null:
		f.remembered_search = -1
		return
	if f.order != null and f.order.target_kind == best.kind and f.order.target_id == best.id: return
	f.remembered_search = best.id
	if flee: flee_from(f, best.cell, best.owner)
	else: combat.order_attack(f.id, best.kind, best.id, true)

func move(f, cell: Vector2i, interruptible: bool):
	var unit = combat.units[f.id]
	# 0x51d6b0 with +0x1d set over an attack-move (+0x1c = 1): the move is inserted before it, and only when the unit is
	# not at the goal already (the guard point walks with the unit, so Return to Post does nothing on the way).
	if combat.is_attack_move(f.cur):
		if cell == f.guard or cell == combat.unit_cell(f.id): return
		f.resume = f.cur
	var target: Vector2 = combat.navigator.center(cell)
	unit.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": unit.base_speed, "individual": true, "ai": interruptible}, "replace")
	f.order = null
	if f.state == "approach": f.state = "idle"
	f.cur = {"kind": "move", "ai": interruptible, "finished": false, "goal": cell, "inserted": interruptible}   # +0x1d (AI-9)

## 0x522f40 (Emulated on Desert Sands, "flight" fixtures): direction d from the threat to the unit (0x40a8f0); try the
## eight directions d, d+1, d-1, d+2, d-2, d+3, d-3, d+4 (0x611274) four cells away (0x603ef0); the first cell inside the
## map whose terrain the unit can enter and that is free (0x42c8e0) is a hop; two hops make the destination and the
## order may not be interrupted; when only the first hop is found the order is interruptible.
func flee_from(f, threat_cell: Vector2i, threat_owner: int):
	if threat_owner < 0 or combat.allied(threat_owner, f.owner): return
	var dest = flight_destination(combat.unit_cell(f.id), threat_cell, func(cell): return flight_cell_ok(cell))
	if dest == null: return
	move(f, dest.cell, dest.interruptible)

static func flight_destination(here: Vector2i, threat: Vector2i, cell_ok: Callable, offsets: Array = [0, 1, -1, 2, -2, 3, -3, 4]) -> Variant:
	var d := direction(threat, here)
	var current := here
	var hops := 0
	while true:
		var found := false
		for off in offsets:
			var dir: int = (int(off) + 8 + d) & 7
			var cand: Vector2i = current + STEP[dir] * FLIGHT_HOP
			if cell_ok.call(cand):
				current = cand
				found = true
				break
		if not found:
			if hops < 1: return null
			return {"cell": current, "interruptible": true}
		hops += 1
		if hops > 1: return {"cell": current, "interruptible": false}
	return null

const STEP := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]

func flight_cell_ok(cell: Vector2i) -> bool:
	var nav = combat.navigator
	return flight_cell_static(cell, nav.collision) and nav.is_passable(cell)

## The terrain/edge part of 0x522f40's test (cost 0x603e68 below 101 and 0x42c8e0): map border cells never pass.
static func flight_cell_static(cell: Vector2i, collision) -> bool:
	return cell.x >= 1 and cell.y >= 1 and cell.x <= collision.width - 2 and cell.y <= collision.height - 2 and collision.is_passable(cell)

## 0x40a8f0: direction (0 north, clockwise) from a to b, with the 2:1 slope test.
static func direction(a: Vector2i, b: Vector2i) -> int:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var ax := absi(dx)
	var ay := absi(dy)
	if dx == 0:
		if dy > 0: return 4
		return 0
	if dy == 0:
		if dx > 0: return 2
		return 6
	if dx > 0 and dy > 0:
		if ay * 2 < ax: return 2
		return 4 if ax * 2 < ay else 3
	if dx < 0:
		if dy > 0:
			if ay * 2 < ax: return 6
			return 5 if ay <= ax * 2 else 4
		if ay * 2 < ax: return 6
		return 7 if ay <= ax * 2 else 0
	if ay * 2 < ax: return 2
	return 1 if ay <= ax * 2 else 0

## 0x5087c0: a random cell, the whole map (1 .. size - 2) or the leash box (with the original's bottom-edge quirk).
func wander(f, leashed: bool, interruptible: bool):
	var size := map_size()
	var x0 := 1
	var y0 := 1
	var x1 := size.x - 2
	var y1 := size.y - 2
	if leashed:
		var g: Vector2i = f.guard if f.guard.x != -1 and f.guard.y != -1 else combat.unit_cell(f.id)
		var r := radius_of(f)
		x0 = maxi(0, g.x - r)
		y0 = maxi(0, g.y - r)
		x1 = mini(size.x - 1, g.x + r)
		y1 = g.y + r
		if y1 < size.y - 1: y1 = size.y - 1
	var x: int = combat.rng.roll(1, x1 - x0 + 1, x0 - 1)
	var y: int = combat.rng.roll(1, y1 - y0 + 1, y0 - 1)
	move(f, Vector2i(x, y), interruptible)

## 0x508930: walk the four corners of the guard box, advancing when within 5 cells of the current corner.
func patrol(f, interruptible: bool):
	var size := map_size()
	var g: Vector2i = f.guard if f.guard.x != -1 and f.guard.y != -1 else combat.unit_cell(f.id)
	var r := radius_of(f)
	var x0 := maxi(0, g.x - r)
	var y0 := maxi(0, g.y - r)
	var x1 := mini(size.x - 1, g.x + r)
	var y1 := g.y + r
	if y1 < size.y - 1: y1 = size.y - 1
	if f.patrol < 0 or f.patrol > 3: f.patrol = 0
	var corners := [Vector2i(x0, y0), Vector2i(x0, y1), Vector2i(x1, y1), Vector2i(x1, y0)]
	var here: Vector2i = combat.unit_cell(f.id)
	if Navigation_chebyshev(here, corners[f.patrol]) < 5: f.patrol = (f.patrol + 1) % 4
	var goal: Vector2i = corners[f.patrol]
	if f.cur != null and f.cur.kind == "move" and f.cur.goal == goal: return
	move(f, goal, interruptible)

## 0x51a230 for animals of the neutral player (Read): a first 1..100 roll lets a camel act on 87+, a turtle only on 100;
## then an idle animal walks to a random cell of the whole map on a second roll below 76 (a non-interruptible move).
## Otherwise the original rolls 1..200 once per object of every active player until one rolls 100 (draw count
## Provisional: the rebuild rolls once per fighter); a non-idle animal stops on a second roll of 1.
func idle_animal(f):
	var rng = combat.rng
	var first: int = rng.roll(1, 100, 0)
	match f.type_id:
		"ACSH": if first <= 0x4f: return
		"ACCA": if first <= 0x56: return
		"ACCO", "ACTU", "ACSE": if first <= 99: return
		"ACGO", "ACPE": if first <= 9: return
	var second: int = rng.roll(1, 100, 0)
	var unit = combat.units[f.id]
	var idle: bool = f.order == null and unit.orders.is_empty() and not unit.in_step
	if idle:
		if second < 0x4c:
			var size := map_size()
			var x: int = rng.roll(1, size.x - 2, 0)
			var y: int = rng.roll(1, size.y - 2, 0)
			move(f, Vector2i(x, y), false)
			return
		for other in combat.fighters.values():
			if rng.roll(1, 200, 0) == 100: return
		return
	if second - 2 < 0:
		unit.stop()
		f.cur = null

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The script table is data (unit_ai_scripts.json).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, ["data", "scripts", "_world", "combat"])

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state, ["data", "scripts", "_world", "combat"])
