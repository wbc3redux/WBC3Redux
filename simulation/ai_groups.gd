extends RefCounted
## Milestone AI-7 (AI_RESEARCH.md section 23): the computer player's army groups, the original's recruit and group machine
## 0x4f5610 as pure functions over plain records. Emulated against tests/ai7_fixtures.json (tools/emulate_ai7.py):
## the assignment 0x4f5700 with the group choice 0x4f59e0, a new group 0x4f5570 / 0x4f33c0, joining 0x4f3470, the
## recount 0x4f37f0 (leader 0x4f3c50, strength 0x4f3d40, centre 0x4f3650, converters 0x4f38a0, long range 0x4f38f0,
## speed 0x4f3830, layers 0x4f3950), "full" 0x4f4bd0, "has a hero" 0x4f4d00, the launch check 0x4f3520 / 0x4f3640 /
## 0x4f4e30, the retyping 0x4f6d90; the march state 0x4f3b00 and its spread 0x4f3da0; one member's look-around 0x4f3e70.
## Read (not run): the per-member orders 0x4f42a0 / 0x4f4320 / 0x4f4390 / 0x4f4460 / 0x4f4530 / 0x4f4690 / 0x4f47c0 /
## 0x4f4a90 / 0x4f4b40 / 0x4f4d50 (they issue orders; ai_player.gd carries them out on the port's world).
##
## A group: {slot, kind (+0, type), slots (32 member ids, -1 free), data (32 x {level, obj, alevel, atarget, move}),
## members (the ids of the occupied slots, kept for the rest of the port), mode (+0xe: 0 none, 1 Recruit, 2 Attack /
## Convert), state (+0xf: 0 Initialising, 1 Moving to Target, 2 Performing Main Action, 3 Finished, 4 Regrouping),
## target ({} or {kind, id}; +0x10), launched (+0x3a), target_player (+0x44), leader (+0x28, -1), centre (+0x24),
## strength (+0x2c), ranged (+0x30), converters (+0x31), min_speed (+0x36), layer (+0x38), cell_0x3c}.
## Types (0x4f4f70's debug names): 0 Normal, 1 Long Range, 2 Mine Killer, 3 Kick Butt, 4 Large, 5 Generals, 6 (weak
## units, unnamed), 7 Conversion, 9 new.
##
## A unit record: {id, cell (Vector2i), hp (0x51c3e0), max_hp, speed (0x51c460(1)), dmg / range (0x526310(1)), converts
## (0x523af0(0, 0)), strength (0x5055f0, the AI-4 D1 table), layer (ARM +0x100), size (ARM +0x39), hero (+0xb4), general
## (+0x1cc), dying (state 8), hidden (+0x30), entering (an order 0x12)}.
##
## ctx: {difficulty, words (the profile words +0x20c8.. read by 0x4f7800: six minimums, six maximums, then +0x20f8..,
## the name field, 0 for the default profile), units (id -> record), roll (Callable(count, sides) -> int, 0x458e70),
## players (0x4f4e30: six {active, computer, eliminated, allied}), main_enemy, retreating}.

const SLOTS := 32
const GROUPS := 100
const SHARE := {1: 40, 2: 60, 3: 80, 4: 100, 5: 130, 6: 160}       # 0x4f3520 / 0x4f4bd0, default 50
const FOCUS := {1: 0, 2: 25, 3: 50, 4: 80, 5: 90, 6: 100}          # 0x4f4e30
const RETYPE_STEP := {3: 1, 4: 2, 5: 3, 6: 4}                      # 0x4f6d90 sVar4, default 0
const MINE_KILLER_STEP := {1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 6: 5}     # 0x4f6d90 at 0x4f70d0 (default: never below the roll)
const NEW := 9
const CONVERSION := 7
const WEAK := 6

static func tdiv(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

static func default_words() -> Array:
	return [10, 4, 6, 7, 15, 6, 12, 5, 8, 10, 17, 9, 0, 0, 0, 0, 0, 0, 0, 0]

static func _word(ctx: Dictionary, index: int) -> int:
	var w: Array = ctx.get("words", default_words())
	return int(w[index]) if index >= 0 and index < w.size() else 0

static func _share(ctx: Dictionary) -> int:
	return int(SHARE.get(int(ctx.difficulty), 50))

# ------------------------------------------------------------------------------------------------ group records
static func new_record(slot: int) -> Dictionary:
	var slots: Array = []
	var data: Array = []
	for i in SLOTS:
		slots.append(-1)
		data.append(_slot_data())
	return {"slot": slot, "kind": NEW, "slots": slots, "data": data, "members": [], "mode": 1, "state": 0, "target": {},
		"launched": false, "target_player": 0, "leader": -1, "centre": Vector2i(-1, -1), "strength": 0, "ranged": 0,
		"converters": 0, "min_speed": -1, "layer": 0, "cell_0x3c": Vector2i(-1, -1), "hero": false}

static func _slot_data() -> Dictionary:
	return {"level": 0, "obj": null, "alevel": 0, "atarget": null, "move": null}

static func sync(g: Dictionary):
	var out: Array = []
	for id in g.slots:
		if int(id) != -1: out.append(int(id))
	g.members = out

static func count(g: Dictionary) -> int:
	var n := 0
	for id in g.slots: if int(id) != -1: n += 1
	return n

static func by_slot(groups: Array, slot: int):
	for g in groups:
		if int(g.slot) == slot: return g
	return null

## 0x4f5570: the first free of the 100 slots gets a new type-9 group (0x4f33c0), or -1 when all are taken.
static func new_group(groups: Array) -> int:
	if groups.size() >= GROUPS: return -1
	var taken := {}
	for g in groups: taken[int(g.slot)] = true
	for s in GROUPS:
		if not taken.has(s):
			var g := new_record(s)
			var at := 0
			while at < groups.size() and int(groups[at].slot) < s: at += 1
			groups.insert(at, g)
			return s
	return -1

## 0x4f4d00: a member with the hero flag (+0xb4).
static func has_hero(g: Dictionary, ctx: Dictionary) -> bool:
	for id in g.slots:
		if int(id) == -1: continue
		var u = ctx.units.get(int(id))
		if u != null and bool(u.get("hero", false)): return true
	return false

## 0x4f3470 + 0x4f37a0: the first free slot; the first member sets the layer (1 or 3 -> 1, 2 -> 2).
static func join(g: Dictionary, id: int, ctx: Dictionary):
	if count(g) == SLOTS: return
	var at: int = g.slots.find(-1)
	if at < 0: return
	g.slots[at] = id
	g.data[at] = _slot_data()
	if count(g) == 1:
		var u = ctx.units.get(id)
		var layer: int = int(u.get("layer", 0)) if u != null else 0
		if layer == 1 or layer == 3: g.layer = 1
		elif layer == 2: g.layer = 2
	drop_dead(g, ctx)

## 0x4f37a0: members that are gone or dying (state 8) leave (0x4f36b0), then 0x4f37f0.
static func drop_dead(g: Dictionary, ctx: Dictionary):
	for i in SLOTS:
		var id := int(g.slots[i])
		if id == -1: continue
		var u = ctx.units.get(id)
		if u == null or bool(u.get("dying", false)): leave(g, id)
	recount(g, ctx)

## 0x4f36b0: the slot is freed; the last member out clears the launch.
static func leave(g: Dictionary, id: int):
	var at := -1
	for i in SLOTS:
		if int(g.slots[i]) == id:
			at = i
			break
	if at >= 0:
		g.slots[at] = -1
		g.data[at] = _slot_data()
	if count(g) == 0: g.launched = false
	sync(g)

## 0x4f37f0: leader, strength, centre, converters, long-range members, slowest speed, layer sums.
static func recount(g: Dictionary, ctx: Dictionary):
	sync(g)
	var leader := -1
	var best := 0
	var converter := false
	var strength := 0
	g.converters = 0
	g.ranged = 0
	var slowest := 50
	var hero_leader := -1
	for id in g.slots:
		if int(id) == -1: continue
		var u = ctx.units.get(int(id))
		if u == null: continue
		strength += int(u.strength)
		if bool(u.converts): g.converters = int(g.converters) + 1
		if int(u.range) > 12: g.ranged = int(g.ranged) + 1
		if int(u.speed) < slowest: slowest = int(u.speed)
		if hero_leader != -1: continue
		if bool(u.get("hero", false)):
			hero_leader = int(id)
			continue
		if bool(u.converts):
			if not converter:
				converter = true
				leader = int(id)
		elif not converter and best < int(u.strength):
			leader = int(id)
			best = int(u.strength)
	g.leader = hero_leader if hero_leader != -1 else leader
	g.strength = strength
	g.min_speed = -1 if slowest == 50 else slowest
	var lead = ctx.units.get(int(g.leader)) if int(g.leader) != -1 else null
	g.centre = lead.cell if lead != null else Vector2i(-1, -1)
	g.hero = has_hero(g, ctx)

## 0x4f4bd0: the group takes nobody more (a hero's group past 15, a conversion group past 2, else the maximum by type
## (9: 10; 0x4f7800's word) times the difficulty share, at most 30).
static func full(g: Dictionary, ctx: Dictionary) -> bool:
	var n := count(g)
	if has_hero(g, ctx): return n > 15
	if int(g.kind) == CONVERSION: return n > 2
	var maximum: int = 10 if int(g.kind) == NEW else _word(ctx, 6 + int(g.kind))
	return mini(tdiv(_share(ctx) * maximum, 100), 30) <= n

## 0x4f3640: launched, and the attacked player (0x4f4e30).
static func launch(g: Dictionary, ctx: Dictionary):
	g.launched = true
	g.target_player = target_player(ctx)

## 0x4f4e30: the main enemy unless 1d100 <= the focus; then the highest 1d100 among the active humans not allied.
static func target_player(ctx: Dictionary) -> int:
	var main := int(ctx.main_enemy)
	var focus: int = int(FOCUS.get(int(ctx.difficulty), main))
	if focus < int(ctx.roll.call(1, 100)): return main
	var best := 0
	var pick := -1
	var players: Array = ctx.get("players", [])
	for p in players.size():
		var q: Dictionary = players[p]
		if not bool(q.active) or bool(q.computer) or bool(q.eliminated) or bool(q.allied): continue
		var r := int(ctx.roll.call(1, 100))
		if best < r:
			best = r
			pick = p
	return main if pick == -1 else pick

## 0x4f3520: a group that is not launched launches with a hero, else at the type's minimum times the share (a conversion
## group at 1); one that stays at home is in Recruit mode.
static func launch_check(g: Dictionary, ctx: Dictionary):
	if bool(g.launched): return
	var go := has_hero(g, ctx)
	if not go:
		var minimum := 1
		if int(g.kind) != CONVERSION: minimum = tdiv(_share(ctx) * _word(ctx, int(g.kind)), 100)
		go = count(g) >= minimum
	if go: launch(g, ctx)
	if not bool(g.launched): g.mode = 1

## 0x4f5dd0(group layer, unit layer): a unit of layer 1 or 3 joins a layer-1 group, 2 a layer-2 group, others any.
static func layer_match(group_layer: int, unit_layer: int) -> bool:
	if unit_layer == 1 or unit_layer == 3: return group_layer == 1
	if unit_layer == 2: return group_layer == 2
	return true

static func _weak(u: Dictionary) -> bool:
	return int(u.hp) < 70 if int(u.range) < 4 else int(u.dmg) < 20

## 0x4f59e0: the slot of the group the unit joins (a new one when none takes it), or -1.
static func choose(groups: Array, u: Dictionary, ctx: Dictionary) -> int:
	if bool(u.get("hidden", false)) or bool(u.get("entering", false)) or String(u.get("code", "")) == "AFSP": return -1
	var conversions := 0             # disassembly 0x4f5b20: [esp + 0x5c] is the type-7 count (Ghidra shows local_24[5])
	for g in groups: if int(g.kind) == CONVERSION: conversions += 1
	var ranged_byte := ((int(u.range) >> 4) & 0xff) != 0
	if bool(u.get("hero", false)): return new_group(groups)
	if bool(u.converts) and conversions < 3: return new_group(groups)
	var best := -1
	var best_slot := -1
	for g in groups.duplicate():
		var score := 500
		if full(g, ctx):
			if not bool(g.launched): launch(g, ctx)
			continue
		var kind := int(g.kind)
		var hp := int(u.hp)
		var gate := true
		match kind:
			7: gate = int(u.speed) > 2
			1: gate = not ranged_byte or int(g.ranged) < 2
			5: gate = bool(u.get("general", false))
			3: gate = hp > 99
			0, 2: gate = not ranged_byte
		if kind == 7 and gate and int(u.speed) < 8: score = 450
		if not gate: continue
		if kind == WEAK:
			if not _weak(u): continue
		elif kind != CONVERSION and _weak(u): continue
		if int(g.ranged) == 0:
			if int(g.converters) != 0 and int(u.speed) <= 3: continue
		elif bool(u.converts): continue
		if hp > 99 and kind != 3 and kind != 5: score -= 50
		if int(g.mode) == 1: score += 50
		if not layer_match(int(g.layer), int(u.get("layer", 0))): continue
		var d := cheb(u.cell, g.centre)
		var hero := has_hero(g, ctx)
		if ((not bool(g.launched) or d < 21) and d < 101) or hero:
			if hero:
				if count(g) > 4 and int(ctx.roll.call(1, 8)) < 8: continue
				score += 200
			if best < score:
				best = score
				best_slot = int(g.slot)
	if best_slot == -1: best_slot = new_group(groups)
	return best_slot

## 0x4f6d90: the retyping of all groups.
static func retype(groups: Array, ctx: Dictionary):
	var step: int = int(RETYPE_STEP.get(int(ctx.difficulty), 0))
	var counts := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	for g in groups:
		if int(g.kind) == 1 and int(g.ranged) == 0: g.kind = NEW
		elif int(g.kind) == CONVERSION and int(g.converters) == 0: g.kind = NEW
		if int(g.kind) != NEW: counts[int(g.kind)] += 1
	if counts[7] < 3:
		for g in groups:
			if counts[7] > 2: break
			if int(g.kind) != CONVERSION and int(g.converters) != 0 and count(g) < 4:
				if int(g.kind) != NEW: counts[int(g.kind)] -= 1
				g.kind = CONVERSION
				counts[7] += 1
	if counts[1] < 2:
		for g in groups:
			if counts[1] > 1: break
			if int(g.kind) == NEW and int(g.ranged) != 0:
				g.kind = 1
				counts[1] += 1
	if counts[0] > 0 and counts[5] < 1:
		for g in groups:
			if int(g.kind) != NEW or count(g) != 1: continue
			var u = _first(g, ctx)
			if u is Dictionary and bool(u.get("general", false)):
				g.kind = 5
				break
	if step != 0:
		for g in groups:
			if int(g.kind) != NEW or count(g) != 1: continue
			var u = _first(g, ctx)
			if u is Dictionary and int(u.hp) > 99 and int(ctx.roll.call(1, 10)) <= step:
				g.kind = 3
				break
	for g in groups:
		if int(g.kind) != NEW or count(g) != 1: continue
		var u = _first(g, ctx)
		if u is Dictionary and _weak(u):
			g.kind = WEAK
			counts[6] += 1
	for g in groups:
		if int(g.kind) == NEW:
			if int(ctx.roll.call(1, 10)) <= step: g.kind = 4
			break
	for g in groups:
		if int(g.kind) == NEW and count(g) >= 3:
			var threshold: int = int(MINE_KILLER_STEP.get(int(ctx.difficulty), 1 << 30))
			var r := int(ctx.roll.call(1, 10))
			g.kind = 0 if threshold < r or counts[2] > 2 else 2
			return

## The first occupied slot's unit; false when that unit is gone (the loops then stop at it), null when the group is empty.
static func _first(g: Dictionary, ctx: Dictionary):
	for id in g.slots:
		if int(id) == -1: continue
		var u = ctx.units.get(int(id))
		return u if u != null else false
	return null

## 0x4f5700's group part for one listed unit without a group (node +0x10 = -1): choose, join, recount, retype, launch
## check. Returns the slot joined or -1.
static func recruit_one(groups: Array, u: Dictionary, ctx: Dictionary) -> int:
	var s := choose(groups, u, ctx)
	if s < 0: return -1
	var g = by_slot(groups, s)
	if g == null: return -1
	join(g, int(u.id), ctx)
	recount(g, ctx)
	retype(groups, ctx)
	launch_check(g, ctx)
	return s

## 0x4f5610's tail: after 0x4f5700, 0x4f6d90 once and 0x4f3520 for every group.
static func pass_tail(groups: Array, ctx: Dictionary):
	retype(groups, ctx)
	for g in groups: launch_check(g, ctx)

# ------------------------------------------------------------------------------------------------ the march (0x4f3b00)
## 0x4f3da0: the farthest member of extent below 2 within 25 cells of the centre; 0 when more than three are larger.
static func spread(g: Dictionary, ctx: Dictionary) -> int:
	var far := 0
	var large := 0
	for id in g.slots:
		if int(id) == -1: continue
		var u = ctx.units.get(int(id))
		if u == null: continue
		if int(u.get("size", 1)) < 2:
			var d := cheb(u.cell, g.centre)
			if far < d and d < 25: far = d
		else:
			large += 1
	return far if large <= 3 else 0

## 0x4f3b00 in Attack mode. `target`: {} when the target object is gone, else {cell, dying, allied, flag_0x115}.
static func march(g: Dictionary, target: Dictionary, ctx: Dictionary):
	if int(g.mode) == 0 or int(g.mode) == 1: return
	if target.is_empty() or bool(target.get("dying", false)) or bool(target.get("allied", false)) or bool(target.get("flag_0x115", false)):
		g.mode = 0
		g.target = {}
		return
	var d := cheb(g.centre, target.cell)
	if int(g.state) == 0:
		if d < 20:
			g.state = 2
			g.cell_0x3c = Vector2i(-1, -1)
		else:
			g.state = 1
	if int(g.state) != 4 and int(g.kind) != CONVERSION and d < 40 and spread(g, ctx) > 20:
		g.state = 4
		return
	match int(g.state):
		1:
			if d < 20:
				g.state = 2
				g.cell_0x3c = Vector2i(-1, -1)
		4:
			if spread(g, ctx) < 10: g.state = 2 if d < 20 else 1

# ------------------------------------------------------------------------------------------------ the look-around (0x4f3e70)
## 0x4f3e70 for the member in slot k. `rows`: map row y -> objects in the row's list order, each {ref, cell, kind ("unit" /
## "building"), owner, allied (with this player), dying, ground / flying (units: ARM +5 in {0, 3}), skip (a building the
## original passes over: income 0x52b050, BMFL, second letter T or R, 0x52ed90, 0x5877e0), flag_0x1a2, armed (building
## damage +0x7c >= 1), aims_at_ally (its head order is an attack (6) on an object allied with this player)}. The rows walk
## stops at the first object past the window (they are kept in x order in the game). Returns the level 0..3 and stores
## level / object in the slot's data.
static func look(g: Dictionary, k: int, rows: Dictionary, width: int, height: int, ctx: Dictionary) -> int:
	var id := int(g.slots[k])
	var u = ctx.units.get(id)
	var data: Dictionary = g.data[k]
	if u == null:
		return 0
	var c: Vector2i = u.cell
	var x0 := maxi(0, c.x - 14)
	var x1 := mini(width - 1, c.x + 14)
	var y0 := maxi(0, c.y - 14)
	var y1 := mini(height - 1, c.y + 14)
	var hero := has_hero(g, ctx)
	var member_layer := int(u.get("layer", 0))
	var level := 0
	var best_ref = null
	var best := 0
	for y in range(y0, y1 + 1):
		for o in rows.get(y, []):
			var ox: int = o.cell.x
			if ox < x0: continue
			if ox > x1: break
			if bool(o.allied): continue
			var unit: bool = o.kind == "unit"
			if unit and int(o.owner) == 6: continue
			if bool(o.get("dying", false)): continue
			var ground := true
			var flying := true
			if unit:
				ground = bool(o.ground)
				flying = not ground
			else:
				if bool(o.get("skip", false)): continue
				if bool(o.get("flag_0x1a2", false)) and int(g.kind) != 3: continue
			if member_layer == 1 and not ground: continue
			if member_layer == 2 and not flying: continue
			var score := (500 - cheb(c, o.cell)) * 2
			if data.obj != null and o.ref == data.obj: score += 1
			var lv := 1
			if unit:
				if bool(o.get("aims_at_ally", false)):
					lv = 3
					score += 2000
				elif hero:
					continue
			elif bool(o.get("armed", false)):
				lv = 2
				score += 1000
			level = maxi(level, lv)
			if best < score or best_ref == null:
				best_ref = o.ref
				best = score
	if best_ref != null and level != 0:
		data.level = level
		data.obj = best_ref
		return level
	data.level = 0
	data.obj = null
	return 0

## 0x4f4390 / 0x4f4460: the object every member attacks at level 1 / 2 (the first slot's, unless a later slot of that
## level already attacks its own find).
static func common_target(g: Dictionary, level: int):
	var pick = null
	var found := false
	for k in SLOTS:
		if int(g.slots[k]) == -1: continue
		var d: Dictionary = g.data[k]
		if int(d.level) != level: continue
		if not found:
			pick = d.obj
			found = true
		elif int(d.alevel) == level and d.atarget == d.obj:
			pick = d.obj
	return pick
