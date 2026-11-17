extends RefCounted
## One computer player (the AI class 0x4f7830; Knights use the base code, AI_RESEARCH.md). It reads the world (Production,
## Economy, Combat, the mines) and only issues orders through `world` (main.gd): build, produce, enter a mine, convert,
## move and attack. Labels per step are in AI_RESEARCH.md sections 12-13. Emulated formulas come from ai_rules.gd.
##
## Update order of 0x4fa120 (difficulty 1..6; Passive and Rampant do nothing here), REVIEW_SKIRMISH_AI.md section 4:
##   main enemy -> hero retreat -> base defence -> advance tasks -> recount -> mine census -> desired counts -> want list ->
##   army -> pacing and demand when the 15 s timer is 0 or has passed (strict) -> new tasks for idle objects.

const R = preload("res://simulation/ai_rules.gd")
const Rules = preload("res://simulation/production_rules.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")
const PACE_MS := 15000                   # +0x2298
## Milestone 11a: the same base class plays every race (0x504a30 makes one class per race; they share the base code
## except the Undead's pacing 0x50b1f0 at vtable +0x18, B1-5). Its lists come from the race's merged Building.cfg table
## (0x58e4034: [DEPENDENCIES] rows, then [PRODUCTION] rows): buildings = its 'B' rows except walls ('BW' not followed by
## 'T', 0x4fcfa0), units = its 'A' rows except animals ('AC', 0x4fd060) plus its hero, research = its P / R rows (0x4fd140),
## each in that order. Milestone 13 gave the Knights their full lists; B1-5 dropped the provisional roster limits of the
## Dwarves and the Swarm (settled: no option kept), so every race uses its full lists (Emulated: tests/ai_batch1_fixtures.json
## "lists", checked in tests/test_ai.gd).
const Advancement = preload("res://simulation/advancement.gd")
const Abilities = preload("res://simulation/ai_abilities.gd")
const UNDEAD := 2
const ELVEN_PEASANT := "AEBX"            # B4-3: the Wisp, Peasant of races 6, 7, 8 (E16 / E18)
const ANCIENT_WISP := "AEAX"
var race := 0
var abilities                            # 0x5001d0 / 0x500830 for this player (simulation/ai_abilities.gd)
var PEASANT := "AHBX"                    # +0x3ba8: 0x4fd060's Peasant (ability 50, ARM +0x24 < 81, +0x32 < 21, ground)
var HERO := "AHHX"                       # the computer hero's unit type (0x42a0d0 race switch)
var KEEPS: Array = ["BKK0", "BKK1"]      # the race's command building chain (BK?0, BK?1 ...) in the building list
var building_order: Array = ["BKK0", "BKK1", "BAGA", "BPFL"]
const DEFENCE_HOME := 30                 # 0x4fa380: hostiles within +-30 cells of home
const DEFENCE_REACH := 35                # ... attacked by idle units within 35 cells of them
const RETREAT_HP := 200                  # 0x4fc150
const REJOIN_HP := 250
const MINE_WORKERS := 8
const PEASANT_FREE := 2                  # 0x4fd940: the mine branch needs more than 2 Peasants not in mine order
const PEASANT_LIST := 4                  # ... and, for the Peasant type, list count + pending >= 4
const CONVERT_REACH := 3                 # 0x4f4940: a member that can convert does so within 3 cells of the target
const HERO_GROUP := 9                    # 0x4f5570 -> 0x4f33c0: a new group starts with type 9
const CONVERSION_GROUP := 7              # 0x4f6d90: a group with a converter (+0x31, 0x4f38a0) and fewer than 4 members
const CONVERSION_GROUPS := 3             # ... while fewer than 3 conversion groups exist

var me := 1
var difficulty := 3
var world                                # main.gd (orders and world queries)
var home := Vector2i(-1, -1)             # +0x2274/+0x2276: the start cell
var main_enemy := -1                     # +0x2308
var hate := [0, 0, 0, 0, 0, 0, 0]        # +0x230c (raised by damage to its buildings, add_hate; AI-4)
var unit_order: Array = ["AHBX", "AHKX", "AHMX", "AHHX"]   # the unit list's order (Building.cfg list of the race)
var units: Dictionary = {}               # list entries: id -> {priority, count, pending, timer, cooldown, available, trainable}
var buildings: Dictionary = {}           # id -> {count, pending, desired, timer, cooldown, available}
var want: Array = []                     # +0x228c [{id, priority, cost, categories, bonus, done}]; 0x40 / 1 nodes persist
var expansion = null                     # unused since AI-6 (0x4feba0 reads the want list's 0x10 node); kept for old saves
var building_stopped := false            # +0x2300: cleared each pass; set by a build task's first step or a failed site search
var tasks: Dictionary = {}               # object key ("u<id>" / "b<id>") -> {type, item, ...}
var research_level := 0                  # PIBX research level in the census (0x4fc280; milestone 13: the owner's level)
var research_order: Array = []           # +0x1358 research list (0x4fd140: the race's P / R rows in file order, at most 40)
var research: Dictionary = {}            # id -> {priority (+8, 50), timer, cooldown}
var mine_weights := [[0, 0], [0, 0], [0, 0], [0, 0]]   # per lane [level weight, workers] (the income inputs)
var mine_slots := [0, 0, 0, 0]
var demand_weights := [0, 0, 0, 0]       # +0x3bb6.. G M C S
var next_pace_ms := 0
var first_pass := true
var retreating := false
var groups: Array = []                   # army groups: {kind, members, launched, target_player, target, hero}
var group_cursor := 0
var log: Array = []
var stats := {"builds": 0, "jobs": 0, "mine_orders": 0, "conversions": 0, "launches": 0, "attacks": 0, "keep_conversions": 0, "advancements": 0}
var advanced: Dictionary = {}            # "source>target" -> units advanced (B1-5)
var monster_slots: Array = [{}, {}, {}]  # +0x22f4 / +0x22f8 / +0x22fc: 0x4fa990's targets {kind, id} (monster mode)

## AI-4: the slot's CustomAI profile (simulation/custom_ai.gd; {} = the defaults of 0x4f7560, which every file of the
## install leaves in place because 0x4f76d0 refuses them) and its file name (0xa49902 + slot * 0x2a -> +0x4888).
var profile: Dictionary = {}
var custom_ai := ""
const CustomAi = preload("res://simulation/custom_ai.gd")
const Danger = preload("res://simulation/ai_danger.gd")
var _danger = null

func _init(player: int, level: int, world_node, player_race: int = 0, custom_profile: Dictionary = {}):
	me = player
	difficulty = level
	world = world_node
	race = player_race
	profile = custom_profile
	_build_lists()
	for id in unit_order:
		units[id] = {"priority": 50, "count": 0, "pending": 0, "timer": 0, "cooldown": -1, "available": false, "trainable": false}
	for id in building_order:
		buildings[id] = {"count": 0, "pending": 0, "desired": -1, "timer": 0, "cooldown": -1, "available": false}
	for id in research_order:
		research[id] = {"priority": 50, "timer": 0, "cooldown": -1}
	# AI-4 (Read, 0x4ffa50 -> vtable +0x10 0x4fc700 / +0x14 0x4fc770): with a loaded profile whose +4 word is not -1, list
	# entry i takes the profile slot i's priority when enabled and -1 when not (by position, not by id; the hero is not
	# in the original's unit list).
	if not profile.is_empty():
		var listed: Array = unit_order.filter(func(id): return id != HERO)
		for i in listed.size(): units[listed[i]].priority = CustomAi.priority(profile, "units", i)
		for i in research_order.size(): research[research_order[i]].priority = CustomAi.priority(profile, "research", i)
	abilities = Abilities.new(self)

## 0x4ffab0's custom path (profile +0x20ba set): the five profile bytes, else null (the difficulty table).
func custom_pct():
	var c: Array = profile.get("category", [])
	return null if c.is_empty() else c

## 0x4fcfa0 / 0x4fd060 / 0x4fd140 over the race's merged table.
func _build_lists():
	var rules = world.production.rules
	var ids: Array = rules.dependency_ids(race)
	building_order = []
	unit_order = []
	KEEPS = []
	for id in ids:
		var code := String(id)
		if code[0] == "B" and not (code[1] == "W" and code[2] != "T") and not building_order.has(code):
			building_order.append(code)
			if code[1] == "K": KEEPS.append(code)
		elif code[0] == "A" and code[1] != "C" and not unit_order.has(code):
			unit_order.append(code)
			if rules.is_peasant_type(code): PEASANT = code
	HERO = rules.hero_type(race)
	unit_order.append(HERO)
	research_order = []
	for id in ids:
		var code := String(id)
		if Rules.is_research(code) and not research_order.has(code) and research_order.size() < 40: research_order.append(code)

func is_builder(u) -> bool:
	return u.type_id == HERO or world.production.rules.builder_power(u.type_id) > 0

## 0x4fe190: true once the Peasant's producer stands or is under way (its list count + pending), or when the first builder
## object of the player is a listed non-hero unit. While it is false the hero takes construction tasks (0x4fd940).
func hero_stops_building() -> bool:
	var producer: String = R.producer_of(PEASANT, world.production.rules.production_table(race))
	if producer != "" and buildings.has(producer) and int(buildings[producer].count) + int(buildings[producer].pending) != 0: return true
	for u in my_units():
		if u.type_id != HERO and world.production.rules.builder_power(u.type_id) > 0:
			return units.has(u.type_id)
		if u.type_id == HERO: return false
	return false

func dispose():
	world = null
	abilities = null

func now() -> int:
	return world.game_ms()

func roll(count: int, sides: int, bonus: int = 0) -> int:
	return world.combat.rng.roll(count, sides, bonus)

# ============================================================================================ 0x4fa120
func think(now_ms: int):
	if difficulty == R.RAMPANT:
		monster_think(now_ms)
		return
	if difficulty == R.PASSIVE: return
	if first_pass:
		first_pass = false
		home = world.skirmish.slots[me].start
	building_stopped = false                                 # +0x2300 = 0 (decompile 164741)
	refresh_cheats()
	choose_main_enemy()
	hero_retreat()
	base_defence()
	advance_tasks(now_ms)
	recount()
	research_level = _research_level("PIBX")             # 0x4fc280 reads the owner's PIBX level (milestone 13)
	mine_census()
	plan_outpost()                                       # AI-4: 0x4f8fa0 between the census and 0x4fc9a0
	desired_counts()
	build_want_list()
	army(now_ms)
	if next_pace_ms == 0 or next_pace_ms < now_ms:          # strict: a 15 s timer on 500 ms passes acts every 15.5 s
		next_pace_ms = now_ms + PACE_MS
		pace()
		keep_conversion()                                   # 0x4fbb90 follows the pacing call on the same timer
	give_tasks(now_ms)
	if abilities != null: abilities.tick(now_ms)            # 0x5001d0 follows 0x4f84a0(1) (B1-5)

## The cheats that depend on the match state: the 0x40b6b0 discount only while the hero lives.
func refresh_cheats():
	world.production.ai_discounts[me] = R.discount(difficulty) if hero_unit() != null else 0

# -------------------------------------------------------------------------------------------- queries
func my_units() -> Array:
	return world.ai_units(me)

func hero_unit():
	for u in my_units():
		if u.type_id == HERO: return u
	return null

func fighter(u):
	return world.combat.fighters.get(u.unit_id)

func busy(u) -> bool:
	return world.unit_busy(u) or tasks.has("u%d" % u.unit_id)

static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# -------------------------------------------------------------------------------------------- 0x4fa5b0 (Emulated)
func choose_main_enemy():
	var m = world.skirmish
	var players: Array = []
	var relations: Array = []
	for p in 7:
		var slot: Dictionary = m.slots[p] if p < m.slots.size() else {}
		players.append({"active": p < 6 and bool(slot.get("active", false)), "computer": bool(slot.get("computer", false)),
			"difficulty": int(slot.get("difficulty", 0)), "start": [int(slot.get("start", Vector2i.ZERO).x), int(slot.get("start", Vector2i.ZERO).y)],
			"eliminated": bool(m.eliminated[p]), "objects": world.owns_objects(p)})
		var row: Array = []
		for q in 7: row.append(m.is_allied(p, q))
		relations.append(row)
	main_enemy = R.main_enemy(me, players, relations, hate, [0, 0, 0, 0, 0, 0, 0], main_enemy)

## 0x4fa580 (Emulated, tests/ai4_fixtures.json "hate"): the counter of `player` grows by `amount` while it is below 10000.
## Its only caller is the building hit-point setter 0x52bd10 through the manager (AiManager.building_damaged, AI-4).
func add_hate(amount: int, player: int):
	if player < 0 or player >= hate.size(): return
	if int(hate[player]) < 10000: hate[player] = int(hate[player]) + amount

# -------------------------------------------------------------------------------------------- 0x4fc150 (Read; danger Emulated)
## AI-4: 0x4fc150 runs while the profile's +0x20c1 is set (default 1) and the hero lives (state != 8, hit points >= 1).
## Not retreating: below 200 hit points with danger 0x4fac00(hero, only_targeting) > 0 (a hostile object within the
## hero's window aims at it) the flag +0x1c is set; a hero in a group (its object node +0x10 != -1) leaves it (0x4f66d0)
## and walks home (0x51d6b0, player-level), a hero in no group only keeps the flag. Retreating: the flag clears when the
## hero has no order, or has 250 or more hit points with no danger, or its order is finished.
func hero_retreat():
	if not bool(profile.get("hero_retreats", true)): return
	var hero = hero_unit()
	if hero == null: return
	var f = fighter(hero)
	if f == null or not world.combat.alive(f): return
	if not retreating:
		if int(f.hp) < RETREAT_HP and danger(hero.unit_id, true) > 0:
			retreating = true
			if not _member(hero.unit_id): return
			tasks.erase("u%d" % hero.unit_id)
			_leave_groups(hero.unit_id)
			world.ai_move(hero, home)
		return
	if hero.orders.is_empty() or (int(f.hp) >= REJOIN_HP and danger(hero.unit_id, true) == 0): retreating = false

## 0x4fac00 for one of the player's units (simulation/ai_danger.gd).
func danger(unit_id: int, only_targeting: bool) -> int:
	if _danger == null: _danger = Danger.new(world)
	return _danger.danger_to_unit(me, unit_id, only_targeting)

## 0x4fbe80 around a cell (simulation/ai_danger.gd `strength_near`).
func strength_near(cell: Vector2i) -> int:
	if _danger == null: _danger = Danger.new(world)
	return _danger.strength_near(me, cell)

# -------------------------------------------------------------------------------------------- 0x4fbdf0 (AI-9, Read)
const HOME_MOVE_STRENGTH := 300          # 0x4fbdf0: 300 < 0x4fbe80(home)
const HOME_SAFE_STRENGTH := 50           # 0x4fc020: a candidate with 0x4fbe80 < 50
const HOME_MOVE_DRAWS := 20
const HOME_MOVE_MS := 5000               # 0x4fc020: global 0xa4e93c, one draw round per 5 s for all players

## 0x4fbdf0 (decompile 166178-166206): the profile (0x4f7460, always made for a computer slot) with +0x20c0 set (default
## 1) and a hostile strength 0x4fbe80(home) above 300: 0x4fc020 may give a new home, which is kept (+0x2274). Returns home.
func home_centre() -> Vector2i:
	if not bool(profile.get("home_moves", true)) or home.x < 0: return home
	if strength_near(home) <= HOME_MOVE_STRENGTH: return home
	var cell := home_move_cell()
	if cell.x != -1 and cell.y != -1: home = cell
	return home

## 0x4fc020 (decompile 166285-166337): at most once per 5 s over all players (the manager's clock word stands for the
## global 0xa4e93c; it is set when a round runs), up to 20 candidates x = 1d(W - 20) + 10, y = 1d(W - 20) + 10 (the map
## width 0x490960 for both, x drawn first); the first one farther (Chebyshev) than min((W - 10) >> 2, 30) from the main
## enemy's start (+0x2308; 0x708fa8 / 0x708fac) whose 0x4fbe80 is below 50. None: (-1, -1).
func home_move_cell() -> Vector2i:
	var manager = world.get("ai_manager") if world is Object else null
	var t := now()
	if manager != null and "home_move_ms" in manager:
		var last := int(manager.home_move_ms)
		if last != 0 and t < last + HOME_MOVE_MS: return Vector2i(-1, -1)
		manager.home_move_ms = t
	var width: int = int(world.collision.width)
	var enemy := Vector2i(-1000000, -1000000)               # Open: +0x2308 = -1 (no main enemy) reads past the table
	if main_enemy >= 0 and main_enemy < world.skirmish.slots.size(): enemy = world.skirmish.slots[main_enemy].start
	var limit: int = (width - 10) >> 2 if ((width - 10) & ~3) < 0x79 else 30
	for i in HOME_MOVE_DRAWS:
		var x := roll(1, width - 20, 10)
		var y := roll(1, width - 20, 10)
		var cell := Vector2i(x, y)
		if limit < cheb(cell, enemy) and strength_near(cell) < HOME_SAFE_STRENGTH:
			stats["home_moves"] = int(stats.get("home_moves", 0)) + 1
			return cell
	return Vector2i(-1, -1)

# -------------------------------------------------------------------------------------------- 0x4fa380 (Read)
## Player-level attack orders (0x51da60 with +0x1c = 0): the attitude scripts do not replace them (review D6).
func base_defence():
	var idle: Array = my_units().filter(func(u): return u.type_id != PEASANT and not busy(u) and fighter(u) != null and fighter(u).order == null and not _in_launched_group(u.unit_id))
	if idle.is_empty(): return
	for f in world.combat.fighters.values():
		if not world.combat.alive(f) or int(f.owner) == me or world.skirmish.is_allied(me, int(f.owner)) or int(f.owner) == 6: continue
		var c: Vector2i = world.combat.unit_cell(f.id)
		if absi(c.x - home.x) > DEFENCE_HOME or absi(c.y - home.y) > DEFENCE_HOME: continue
		if f.order == null or world.combat.object_owner(String(f.order.target_kind), int(f.order.target_id)) != me: continue
		for u in idle:
			if cheb(u.cell, c) <= DEFENCE_REACH: world.combat.order_attack(u.unit_id, "unit", f.id, false)

# -------------------------------------------------------------------------------------------- recount (vtable +0xc/+4/+8)
func recount():
	for id in units:
		units[id].count = 0
		units[id].pending = 0
	for id in buildings:
		buildings[id].count = 0
		buildings[id].pending = 0
	for u in my_units():
		if units.has(u.type_id): units[u.type_id].count += 1
	for b in world.production.buildings.values():
		if int(b.owner) != me or not buildings.has(b.original_type_id): continue
		# AI-7 (G5, Read, disassembly 0x4f8070-0x4f81f4): a site (+0xcc) counts nowhere itself; only its build task's pending
		# (0x4f9bd0, below) holds it, so a site whose builder's task ended can be ordered again.
		if not b.constructing: buildings[b.original_type_id].count += 1
		if units.has(b.job_item): units[b.job_item].pending += 1
		# AI-6 (Read, 0x4f9c80: a produce task that takes a building id adds 1 to that entry's pending +9): a hall upgrading
		# to BKE2 counts as a pending BKE2, so the tech step does not offer the same level to a second hall (the original's
		# Elves upgrade one hall of three; the port upgraded every hall at once).
		elif buildings.has(b.job_item): buildings[b.job_item].pending += 1
		# 0x40b350: a finished building of level d also counts as every lower level of its chain (BKK1 is a BKK0).
		if not b.constructing and Rules.level_digit(b.original_type_id) > 0:
			for id in buildings:
				if id != b.original_type_id and Rules.satisfies(b.original_type_id, id): buildings[id].count += 1
	for key in tasks:
		var t: Dictionary = tasks[key]
		if t.type == "build" and buildings.has(t.item): buildings[t.item].pending += 1     # placed or not (AI-7, G5)
	for id in units:
		units[id].available = world.production.missing_requirement(me, id) == ""     # 0x40b580 dependency test
		units[id].trainable = id != HERO and units[id].available and _producer_of(id) != null
		# 0x4f7d80 (Read, disassembly): a unit whose producer 0x4f7f20 is -1 (no [PRODUCTION] row) is available on its
		# requirement words alone. B4-3 (BATCH4_RESEARCH.md R3, Emulated review "recount"; decision 9): for every list entry (AEAX,
		# the Wood Elves' AAIM, the Undead tree) instead of B1-5's Undead-only exception.
		if id != HERO and not Abilities.produced(world.production.rules, race, id): units[id].trainable = units[id].available
	# AI-6 (Read, disassembly 0x4f8070-0x4f81f4): an entry's +0xc is set when its four requirement words pass 0x40b580 and
	# 0x4fcdd0 holds (an upgrade id only while a lower-level building is left to upgrade).
	for j in building_order.size():
		var id: String = building_order[j]
		buildings[id].available = world.production.missing_requirement(me, id) == "" and _room_for_level(j)

func _producer_of(item: String):
	for b in world.production.buildings.values():
		if int(b.owner) != me or b.constructing: continue
		for entry in world.production.menu_for(b):
			if entry.id == item: return b
	return null

# -------------------------------------------------------------------------------------------- 0x4fc280 (Emulated)
func mine_census():
	var lanes: Array = R.census_lanes(world.mines.census(me), research_level)
	for lane in 4:
		mine_weights[lane] = [int(lanes[lane][0]), int(lanes[lane][1])]
		mine_slots[lane] = int(lanes[lane][2])

func income_metric(lane: int) -> int:
	return R.income(lane, int(mine_weights[lane][0]), int(mine_weights[lane][1]), difficulty)

# -------------------------------------------------------------------------------------------- 0x4fc9a0 + 0x4fcc10 (Emulated)
## -1 = none wanted (BKK1 and BPFL train no listed unit). AI-4 (Read): the command-building term of 0x4fd7c0 (desired =
## count + max(0, current - limit + 10) / 5 for the last BK?0 of the list, +0x3b8e) is written before 0x4fc9a0 in the
## same pass (0x4fa120), and 0x4fc9a0 writes every entry (Emulated, review D8), so it never reaches a reader: not ported.
## AI-6 (Read, decompile 166796-166843): 0x4fc9a0 skips a building entry unless it is valid (+0x18) and has the menu flag
## +0x80 (0x4f7ba0: a level digit 1..9 or listed in the construction menus, `_menu_flags`); a skipped entry is -1 and its
## units' priorities stay out of the total. The port passed every entry (the taverns BTCE / BTDR / BTEL / BTIN, in no
## construction menu, diluted the total: High Elf BATG 8 instead of 12). The unit flag is the entry's +0xb, which 0x4f7d80
## sets only when the unit's producer stands (Emulated, review "recount": AEDX needs BATG): the port's `trainable`.
func desired_counts():
	var flags: Array = _menu_flags()
	var b_list: Array = []
	for j in building_order.size(): b_list.append([building_order[j], 1, 1 if bool(flags[j]) else 0])
	var u_list: Array = unit_order.map(func(id):
		var e: Dictionary = units.get(id, {"priority": 50, "trainable": true})
		return [id, int(e.priority), int(bool(e.get("trainable", e.get("available", false))))])
	var out: Array = R.desired_counts(difficulty, b_list, u_list, -1, world.production.rules.production_table(race))
	for i in b_list.size(): buildings[b_list[i][0]].desired = int(out[i])

# -------------------------------------------------------------------------------------------- 0x4ff3b0 want list (Read)
## 0x4fb400: returns the node (new or merged), null when the affordability gate refuses it. Both paths end in
## 0x4fafd0(id, 1), which for a unit sets its list timer (+0x14) to now - 600000: a newly wanted unit counts as last
## started ten minutes ago (milestone 11b; the building branch, timer = now, is not applied while the building nodes are
## rebuilt every pass: it would reset their gate timer each pass).
func want_insert(id: String, priority: int, category: int):
	# REVIEW D2: 0x4fe830 / 0x4fe9e0 / 0x4ff0d0 price with 0x40b6b0(id, -1, player): the owner's race, research and discount.
	var cost: Array = world.production.price_of(me, id) if world.production is Object and world.production.has_method("price_of") else world.production.rules.cost(id, world.production.price_discount(me))
	if not R.afford(world.economy.resources(me), cost, mine_weights, difficulty): return null    # 0x4fb330 (Emulated)
	for w in want:
		if w.id == id:
			w.priority += priority
			w.categories |= category
			_listed(id)
			return w
	var row := {"id": id, "priority": priority, "cost": cost, "categories": category, "bonus": 0, "done": false}
	var at := want.size()
	for i in want.size():
		if int(want[i].priority) < priority:
			at = i
			break
	want.insert(at, row)
	_listed(id)
	return row

## 0x4fafd0(id, 1): a unit's list timer becomes now - 600000; a building's or research's becomes now (REVIEW D3: applied
## since milestone 13, when the tech nodes persist).
## AI-5 (Emulated, tools/emulate_ai5.py "lists"): 0x4fafd0 dispatches on the id's first letter: 'A', 'B' and 'P' only. An
## 'R' research (the Elves' hall research RCIE, RANI, ...) keeps its timer: the tech step 0x4ff0d0 drops and relists such a
## node every pass, and a timer set at each listing kept it from ever passing the cooldown gate 0x4f8600.
func _listed(id: String):
	if units.has(id): units[id].timer = now() - 600000
	elif buildings.has(id): buildings[id].timer = now()
	elif research.has(id) and id.begins_with("P"): research[id].timer = now()

## 0x4faea0: unlinks the node, and only when one was found 0x4fafd0(id, 0) resets the cooldown of an 'A', 'B' or 'P' entry
## to -1 (AI-5, Emulated "lists"; the port reset only a unit's, and always).
func want_remove(id: String):
	for i in want.size():
		if want[i].id == id:
			want.remove_at(i)
			_unlisted(id)
			return

## 0x4fafd0(id, 0).
func _unlisted(id: String):
	if units.has(id): units[id].cooldown = -1
	elif buildings.has(id): buildings[id].cooldown = -1
	elif research.has(id) and id.begins_with("P"): research[id].cooldown = -1

func _node(id: String):
	for w in want:
		if w.id == id: return w
	return null

## 0x4faf30(category): the first node with that category bit.
func _node_with(category: int):
	for w in want:
		if int(w.categories) & category: return w
	return null

## The want list +0x228c is a persistent linked list in the original (milestone 11b for the 0x40 / 1 nodes; milestone 13
## for every category). The passes run in the builder order of 0x4ff3b0 (REVIEW D3): 0x40 Peasants (0x4fe830), 1 units
## (0x4fe9e0), 2 research (0x4fead0), 0x10 expansion (0x4feba0), 4 tech (0x4ff0d0); 0x20 (outpost) and 8 (research tech,
## 0x4fee60) are Open. A started building or research leaves the list (0x4f8750, `_started`).
func build_want_list():
	want = want.filter(func(w): return not w.done)
	# 0x40 Peasants (0x4fe830): an unavailable Peasant removes the listed node; otherwise the node is inserted once (the
	# affordability gate applies only then) and afterwards only its priority is set (0x4faf90), or it is removed when no
	# Peasant is wanted.
	var listed = _node_with(0x40)
	if listed != null and not units[PEASANT].trainable: want_remove(PEASANT)
	if units[PEASANT].trainable:
		var peasants: int = int(units[PEASANT].count) + int(units[PEASANT].pending)
		var open_slots := 0
		for lane in 4: open_slots += int(mine_slots[lane]) - int(mine_weights[lane][1])
		var demand := open_slots + 4 - peasants
		var priority := 0
		if PEASANT == ELVEN_PEASANT:
			# B4-3 (E18, Emulated "peasant"): the Elven branch ignores the mines: before AEAX is available 100 while count + pending
			# < 4 (else the node goes); after it always 100, and with more than 3 Wisps the merge 0x4f8290 runs (E20).
			var ancient: bool = units.has(ANCIENT_WISP) and units[ANCIENT_WISP].available
			priority = Abilities.elven_peasant_priority(peasants, ancient)
			if ancient and int(units[PEASANT].count) > 3 and abilities != null: abilities.merge_wisps(self)
		elif peasants < 4: priority = 100
		elif demand > 0: priority = mini(100, (demand >> 2) + 50)
		if priority > 0:
			if listed == null: want_insert(PEASANT, priority, 0x40)
			else: listed.priority = priority
		elif listed != null: want_remove(PEASANT)
	# 1 units (0x4fe9e0), every list entry: an unavailable unit loses its node; a listed one (the Peasant's included, whose
	# node 0x4fe830 made) gets bonus = entry +8 (0 for the base class: only race scripts such as 0x50bbd0 write it) +
	# max(0, now - its timer) >> 10; an unlisted one with priority > 0 (never the Peasant) is inserted with bonus +8 + 100.
	for id in unit_order:
		if id == HERO: continue
		var node = _node(id)
		if not units[id].trainable:
			if node != null: want_remove(id)
			continue
		if node == null:
			if id != PEASANT and int(units[id].priority) > 0:
				var added = want_insert(id, int(units[id].priority), 1)
				if added != null: added.bonus = 100
		else:
			node.bonus = maxi(0, now() - int(units[id].timer)) >> 10
	_want_research()
	_want_expansion()
	_want_outpost()
	_want_tech()

## 0x4feba0, the expansion (AI-6, Read, decompile 168580-168668; replaces the port's "one node until its building is
## finished"): nothing happens while the first category-0x10 node is taken (+0x1e, 0x4fb0d0: a builder walks to its site);
## a listed 0x10 node stays while its entry is available (+0xc), else it goes. Then among the entries with desired != -1,
## available, count + pending != 0, the menu flag +0x80 and 0x4fcdd0 (an id with digit 1..9 only while the previous
## entry's count exceeds its own count + pending) and desired - have > 0, the lowest have x 128 / desired x (digit + 1, or
## 1) wins, ties to the larger shortfall, then the first; it is wanted at 90 (0x10), and 0x4faf60 gives a digit-1..9 node
## bonus 90. A taken node is removed at placement (0x4f9790 -> 0x4f8750), so the next expansion is chosen while the last
## one is still being built: the original's Elves raise Trees in parallel (13 by 378 s).
func _want_expansion():
	var first = _node_with(0x10)
	if first != null:
		if first.get("taken", false): return
		var entry = buildings.get(String(first.id))
		if entry != null and bool(entry.available): return
		want_remove(String(first.id))
	var flags: Array = _menu_flags()
	var best := ""
	var best_score := 0
	var best_short := 0
	for j in building_order.size():
		var id: String = building_order[j]
		var b: Dictionary = buildings[id]
		var have: int = int(b.count) + int(b.pending)
		if int(b.desired) == -1 or not b.available or have == 0 or not bool(flags[j]) or not _room_for_level(j): continue
		var shortfall: int = int(b.desired) - have
		if shortfall <= 0: continue
		var digit: int = (id.unicode_at(3) - 0x2f) if id.length() == 4 and id[3] >= "0" and id[3] <= "9" else 1
		var score: int = R.tdiv(have * 0x80, int(b.desired)) * digit
		if best == "" or score < best_score or (score == best_score and shortfall > best_short):
			best_score = score
			best_short = shortfall
			best = id
	if best == "": return
	want_insert(best, 90, 0x10)
	if _digit_1_9(best):
		var listed = _node(best)
		if listed != null: listed.bonus = 90

## 0x4fcdd0(j): true unless the entry's id ends in 1..9 and the previous entry's count minus its own pending and count is
## not above 0.
func _room_for_level(j: int) -> bool:
	var id: String = building_order[j]
	if j < 0 or not _digit_1_9(id): return true
	if j == 0: return false
	var b: Dictionary = buildings[id]
	return int(buildings[building_order[j - 1]].count) - int(b.pending) - int(b.count) > 0

## 0x4fead0 (Emulated, milestone M-1: ai_rules.research_pick): a category-2 node stays while its research is eligible
## and not done; otherwise it is removed and the first eligible, unresearched, unordered entry of the research list is
## wanted at its priority (+8, 50).
func _want_research():
	if world != null and world.get("improved_research") == true:
		_want_research_improved()
		return
	var node = _node_with(2)
	var entries: Array = []
	for id in research_order:
		var running := _research_running(id)
		entries.append({"id": id, "priority": int(research[id].priority), "have": _research_level(id) != 0,
			"ordered": running, "eligible": research_eligible(id) or running})
	var pick: Dictionary = R.research_pick(String(node.id) if node != null else "", entries)
	if pick.keep: return
	if String(pick.remove) != "": want_remove(String(pick.remove))
	if String(pick.offer) != "": want_insert(String(pick.offer), int(pick.priority), 2)

# DELIBERATE MODERN CHANGE (modern_rules.gd "Research", COMPLAINTS_AND_FIXES.md F10). In the original the category-2
# node stays on the first eligible research (Crusade I for the Knights) until it starts, and at the Keep it loses every
# pick to the Peasant (AI_RESEARCH.md section 15, Emulated), so the computer researches almost nothing. With the
# improved rules:
# * once the item may start (its pacing cooldown has run out; listing sets its timer, 0x4fafd0), the waiting node gains
#   a bonus of the waited ms >> 9 (the units' waiting bonus at twice the rate), so it soon outscores the unit a building
#   would otherwise train again;
# * a node gives way to the next eligible entry in list order after RESEARCH_PATIENCE_MS of being ready, or after
#   RESEARCH_PATIENCE_MS of being listed while it is still that long from ready, so one slow or busy building does not
#   hold every other building's research.
const RESEARCH_PATIENCE_MS := 90000

func _want_research_improved():
	var node = _node_with(2)
	var start := 0
	if node != null:
		var id := String(node.id)
		if research.has(id) and research_eligible(id):
			var cooldown: int = int(research[id].cooldown)
			var ready: int = int(research[id].timer) + (50000 if cooldown == -1 else cooldown)   # 0x4f8600: unset = 50 s
			var listed: int = int(node.get("listed_ms", now()))
			node.bonus = maxi(0, now() - maxi(listed, ready)) >> 9
			var stale: bool = now() - maxi(listed, ready) >= RESEARCH_PATIENCE_MS or (now() - listed >= RESEARCH_PATIENCE_MS and ready - now() > RESEARCH_PATIENCE_MS)
			if not stale: return
			start = research_order.find(id) + 1
		want_remove(id)
	for k in research_order.size():
		var id: String = research_order[(start + k) % research_order.size()]
		if node != null and id == String(node.id) and research_order.size() > 1: continue
		if research_eligible(id):
			var added = want_insert(id, int(research[id].priority), 2)
			if added != null: added.listed_ms = now()
			return

## The research entry's flags (+0xa researched, +0xb ordered, +0xc eligible; the recount 0x4f7f60 is Read only through
## AI_RESEARCH.md): eligible here = not researched, not running or queued, requirements met and offered by one of the
## player's finished buildings (Provisional reading of +0xc).
func _research_level(id: String) -> int:
	if world.production is Object and world.production.has_method("research_level"): return world.production.research_level(me, id)
	return 0

func research_eligible(id: String) -> bool:
	if not (world.production is Object and world.production.has_method("research_level")): return false   # test stubs
	if _research_level(id) != 0 or world.production.missing_requirement(me, id) != "": return false
	if _research_running(id): return false
	return _producer_of(id) != null

## +0xb (set by 0x4f9c80 when a produce task takes the item): here, the item runs or waits in one of the player's buildings.
func _research_running(id: String) -> bool:
	if not (world.production is Object and world.production.has_method("research_level")): return false
	for b in world.production.buildings.values():
		if int(b.owner) == me and (b.job_item == id or b.queue.has(id)): return true
	return false

## 0x4ff0d0, the tech step of every race (A-2: Emulated on captured soak state, tests/tech_step_fixtures.json; it replaced
## milestone 13's requirement trace for the Knights). A category-4 node is kept while it is a building whose entry is
## available with count 0, or a research 'P' that is eligible (+0xc: eligible or ordered) and not had (ai_rules.tech_keep);
## otherwise it is removed and the units are walked in the order +0x3ac6 (`_tech_walk`). For the unit at walk position k
## its needed pieces are the enabling matrix of 0x4fd1b0 / 0x4fd2f0 (`_needed_by`); ai_rules.tech_step picks the building
## (150, 220 for the Peasant's producer) or research (140), wanted at priority 100; 0x4faf60 then sets bonus 100 on the
## listed node of that id (research, or a building with level digit 1..9, 0x4fed30), also when the gate refused the new
## node but the id is listed in another category.
func _want_tech():
	var node = _node_with(4)
	if node != null:
		var id := String(node.id)
		var r = null
		if research.has(id): r = {"eligible": research_eligible(id) or _research_running(id), "had": _research_level(id) != 0}
		if R.tech_keep(id, buildings.get(id), r): return
		want_remove(id)
	var step: Dictionary = tech_choice()
	var offer := String(step.offer)
	if offer == "": return
	want_insert(offer, 100, 4)
	if research.has(offer) or _digit_1_9(offer):
		var listed = _node(offer)
		if listed != null: listed.bonus = 100

## The walk of 0x4ff0d0 over the current lists: {"offer", "stop"} (ai_rules.tech_step).
func tech_choice() -> Dictionary:
	var walk: Dictionary = _tech_walk()
	var flags: Array = _menu_flags()
	var b_rows: Array = []
	for j in building_order.size():
		var e: Dictionary = buildings[building_order[j]]
		b_rows.append({"id": building_order[j], "have": int(e.count) + int(e.pending), "available": bool(e.available), "flag": flags[j]})
	var r_rows: Array = []
	for id in research_order:
		r_rows.append({"id": id, "had": _research_level(id) != 0, "ordered": _research_running(id), "eligible": research_eligible(id)})
	return R.tech_step(walk.order, walk.needs, b_rows, r_rows, _producer_id(PEASANT))

## 0x4fed30: the fourth character is a digit 1..9.
static func _digit_1_9(id: String) -> bool:
	return id.length() == 4 and id[3] >= "1" and id[3] <= "9"

## The walk's inputs, static per player (0x4ffa50 orders the units once at setup; every priority is 50 here, see
## AI_RESEARCH.md section 17 Open): needs[i] = {"b": building list indexes, "r": research list indexes} of unit i (the
## hero is not in the original's unit list), the command buildings of 0x4fe7f0 and the order of 0x4ff5f0 + 0x4fc7e0
## (ai_rules.tech_order).
var _walk_cache: Dictionary = {}
func _tech_walk() -> Dictionary:
	if not _walk_cache.is_empty(): return _walk_cache
	var listed: Array = unit_order.filter(func(id): return id != HERO)
	var needs: Array = []
	for id in listed:
		var needed: Dictionary = _needed_by(id)
		var b: Array = []
		for j in building_order.size():
			if needed.has(building_order[j]): b.append(j)
		var r: Array = []
		for k in research_order.size():
			if needed.has(research_order[k]): r.append(k)
		needs.append({"b": b, "r": r})
	# 0x4fcfa0 writes every 'BK' building to +0x3ad0 + 4 x its fourth character, so +0x3b90..+0x3ba0 hold the last
	# BK?0..BK?4 of the building list.
	var command := {}
	for id in building_order:
		var code := String(id)
		if code[1] == "K" and code[3] >= "0" and code[3] <= "4": command[code[3]] = code
	var expensive: Array = building_order.map(func(id): return command.values().has(id))
	var priorities: Array = listed.map(func(id): return int(units[id].priority))
	var order: Dictionary = R.tech_order(listed.find(PEASANT), needs, _menu_flags(), expensive, priorities)
	_walk_cache = {"order": order.order, "by_cost": order.by_cost, "needs": needs, "units": listed, "expensive": expensive}
	return _walk_cache

## 0x4f7f20: the producer of an item (the first [PRODUCTION] row listing it, ai_rules.producer_of), the Undead's Skeleton
## from the Graveyard.
func _producer_id(id: String) -> String:
	if race == UNDEAD and id == "AUIX": return "BAGY"
	return R.producer_of(id, world.production.rules.production_table(race))

## 0x4f7ba0 +0x80 per building entry: a level digit 1..9, or listed in the construction menus +0x3bc0 / +0x3be4 (built by
## 0x4fce30 with the lists; Emulated with the port's menus as input, A-2).
var _flags_cache: Array = []
func _menu_flags() -> Array:
	if _flags_cache.is_empty():
		var menu: Array = []
		if world.production is Object and world.production.has_method("construction_menu"):   # (test stubs have none)
			menu = world.production.construction_menu(me, 0) + world.production.construction_menu(me, 1)
		for b in building_order: _flags_cache.append(_digit_1_9(b) or b in menu)
	return _flags_cache

## 0x4fd1b0 / 0x4fd2f0 (Read): the buildings and research a unit needs: its producer and requirement words, recursively
## (a research's producer too; a leveled building every level from its own down to 0); the Skeleton also needs the
## Gravestone; an advanced Undead type also needs its sources' pieces. Static data, computed once per unit type.
var _needed_cache: Dictionary = {}
func _needed_by(unit_id: String) -> Dictionary:
	if _needed_cache.has(unit_id): return _needed_cache[unit_id]
	var out := {}
	var seen := {}
	_mark(unit_id, out, seen)
	var sources: Dictionary = {"AUJX": ["AUIX"], "AUKX": ["AUIX"], "AUXX": ["AUKX", "AUIX"], "AULX": ["AUJX", "AUIX"],
		"AUMX": ["AUJX", "AUIX"], "AUAX": ["AULX", "AUJX", "AUIX"]}
	if race == UNDEAD and _producer_id(unit_id) == "":
		for s in sources.get(unit_id, []): _mark(String(s), out, seen)
	_needed_cache[unit_id] = out
	return out

func _requires(id: String) -> Array:
	return Array(world.production.rules.requirements(id, race))

func _mark(id: String, out: Dictionary, seen: Dictionary):
	if id == "" or seen.has(id) or seen.size() > 200: return
	seen[id] = true
	match id[0]:
		"A":
			if race == UNDEAD and id == "AUIX": _mark("BAGR", out, seen)
			_mark(_producer_id(id), out, seen)
			for r in _requires(id): _mark(String(r), out, seen)
		"B":
			var digit: int = int(id[3]) if id.length() == 4 and id[3] >= "0" and id[3] <= "9" else -1   # 0x4fd2f0: '0'..'9'
			if digit < 0:
				out[id] = true
				for r in _requires(id): _mark(String(r), out, seen)
			else:
				for d in range(digit, -1, -1):
					var level := id.substr(0, 3) + str(d)
					out[level] = true
					seen[level] = true
					for r in _requires(level): _mark(String(r), out, seen)
		"P", "R":
			out[id] = true
			for r in _requires(id): _mark(String(r), out, seen)
			_mark(_producer_id(id), out, seen)

# -------------------------------------------------------------------------------------------- pacing (Emulated)
func pace():
	var rows: Array = want.map(func(w): return [w.id, int(w.priority), w.cost, int(w.categories)])
	var bmap := {}
	var umap := {}
	# 0x4fe250 walks the want list and clears the cooldown of each listed item first (milestone 11b: only those; the
	# others keep theirs).
	var listed := {}
	for w in want: listed[w.id] = true
	for id in buildings: bmap[id] = [int(buildings[id].timer), 0 if listed.has(id) else int(buildings[id].cooldown)]
	for id in units: umap[id] = [int(units[id].timer), 0 if listed.has(id) else int(units[id].cooldown)]
	var rmap := {}
	for id in research: rmap[id] = [int(research[id].timer), 0 if listed.has(id) else int(research[id].cooldown)]
	for category in [0x40, 0x20, 1, 2, 4, 8, 0x10]:
		if race == UNDEAD:
			# B1-5: the Undead class's pacing 0x50b1f0 -> 0x50b2c0 (Emulated): chain prices of the tree from
			# 0x40b6b0(type, 0, player), then the cooldowns flow down the tree.
			var chain := {}
			if category == 1:
				var prices := {}
				for t in R.TREE: prices[t] = world.production.price_of(me, t)
				chain = R.undead_chain(prices)
			R.pacing_undead(category, difficulty, mine_weights, rows, bmap, umap, rmap, chain, custom_pct())
			if category == 1: R.advancement_flow(umap, unit_order)
		else:
			R.pacing(category, difficulty, mine_weights, rows, bmap, umap, rmap, custom_pct())
	for id in bmap: buildings[id].cooldown = int(bmap[id][1])
	for id in umap: units[id].cooldown = int(umap[id][1])
	for id in rmap: research[id].cooldown = int(rmap[id][1])
	var arm := {}
	for id in units: arm[id] = int(world.unit_arm_0x1c(id))
	demand_weights = R.demand(rows, mine_weights, difficulty, arm)                         # 0x4fb100

## 0x4f8600 over the live lists (an unset cooldown becomes 50000 and passes, except a Keep).
func gate(item: String) -> bool:
	var b: Array = []
	for id in buildings: b.append([id, int(buildings[id].count), int(buildings[id].pending), int(buildings[id].timer), int(buildings[id].cooldown)])
	var u: Array = []
	for id in units: u.append([id, int(units[id].count), int(units[id].pending), int(units[id].timer), int(units[id].cooldown)])
	var r: Array = []
	for id in research: r.append([id, 0, 0, int(research[id].timer), int(research[id].cooldown)])
	var ok := R.cooldown_gate(item, now(), b, u, r)
	for e in b: buildings[e[0]].cooldown = e[4]
	for e in u: units[e[0]].cooldown = e[4]
	for e in r: research[e[0]].cooldown = e[4]
	return ok

## 0x4fd940 offers only nodes whose +0x1e is clear: not removed (`done`) and not taken by a builder (`taken`, AI-6).
func _want(id: String):
	for w in want:
		if w.id == id and not w.done and not w.get("taken", false): return w
	return null

## AI-6 (Read, 0x4f9bd0 / 0x4f9d60): a build task's first step marks its node taken (0x4fb070, +0x1e = 1); a task that
## ends before the placement clears it again (0x4fb0a0). The placement removes the node (0x4f8750, `_started`).
func _set_taken(id: String, taken: bool):
	for w in want:
		if w.id == id and not w.done:
			w.taken = taken
			return

## 0x4f8750: a started job sets the item's timer; a building's or research's node is removed (here: marked done, the
## building nodes are rebuilt next pass), a unit's node stays listed (milestone 11b).
func _started(id: String):
	if buildings.has(id): buildings[id].timer = now()
	if research.has(id): research[id].timer = now()
	if units.has(id):
		units[id].timer = now()
		return
	for w in want:
		if w.id == id and not w.done:
			w.done = true
			_unlisted(id)          # AI-5 (Emulated "lists"): the removal 0x4faea0 -> 0x4fafd0(id, 0), cooldown -1 for 'B' / 'P'
			break

# -------------------------------------------------------------------------------------------- tasks (0x4f84a0, Read)
func advance_tasks(now_ms: int):
	for key in tasks.keys():
		var t: Dictionary = tasks[key]
		match t.type:
			"build":
				var u = world.unit_by_id(int(t.unit))
				if u == null or u.removed or u.dying:
					if not t.get("placed", false): _set_taken(String(t.item), false)   # 0x4f9d60
					tasks.erase(key)
				elif t.get("placed", false):
					if not u.inside_building: tasks.erase(key)          # finished or released: the builder is free again
				elif world.build_state(u) == "placed":
					t.placed = true
					_started(String(t.item))                            # AI-6: 0x4f9790 state 2 -> 0x524450 -> 0x4f8750
				elif world.build_state(u) == "failed":
					_note_fail("walk", String(t.item))
					_set_taken(String(t.item), false)
					tasks.erase(key)
			"produce":
				var b = world.production.building(int(t.building))
				if b == null or (b.job_item == "" and not b.job_pending): tasks.erase(key)
			"mine":
				var u = world.unit_by_id(int(t.unit))
				if u == null or u.dying or u.removed or world.mine_order_failed(u): tasks.erase(key)

func give_tasks(now_ms: int):
	# Buildings: produce (0x4f8d00): units it trains and the next Keep level, on the want list and past the cooldown gate.
	for b in world.production.buildings.values():
		if int(b.owner) != me or b.constructing or b.has_job() or tasks.has("b%d" % b.entity_id): continue
		var best := ""
		var best_score := -1
		for entry in world.production.menu_for(b):
			var w = _want(entry.id)
			if w == null or not world.production.can_queue(b.entity_id, entry.id).ok or not gate(entry.id): continue
			var score: int = roll(1, 30) + int(w.bonus) + int(w.priority)
			if score > best_score:
				best_score = score
				best = entry.id
		if best != "" and world.production.enqueue(b.entity_id, best, now_ms).ok:
			tasks["b%d" % b.entity_id] = {"type": "produce", "item": best, "building": b.entity_id, "started": now_ms}
			_started(best)
			stats.jobs += 1
			_task_started(best)
	# Builders (0x4fd940): the best wanted, gated construction first; the hero builds only while no Keep exists or is under
	# way (0x4fe190); otherwise a Peasant goes to a mine (more than 2 Peasants not in mine order, list count + pending >= 4).
	var free_peasants := 0
	for u in my_units():
		if u.type_id == PEASANT and not (tasks.has("u%d" % u.unit_id) and tasks["u%d" % u.unit_id].type == "mine"): free_peasants += 1
	var hero_done: bool = hero_stops_building()
	for u in my_units():
		if not is_builder(u) or u.inside_building: continue
		# 0x4f84a0(1) gives a task to every object without an AI task, group members and marching units too (0x4fd940 then
		# asks 0x4fe190): a Dwarf hero in its group still comes back to build the Foundry. For the Knights 0x4fe190 is already
		# true when the hero joins its group, so their hero is unchanged.
		if u.type_id == HERO:
			if retreating or hero_done or tasks.has("u%d" % u.unit_id) or world.pending_builds.has(u.unit_id): continue
			if busy(u) and not _member(u.unit_id): continue
			_give_build(u, now_ms, world.production.construction_menu(me))
			continue
		# AI-8 (Read, 0x4f84a0(1) decompile 163157-163175, 0x4fbad0 -> 0x4f66d0 -> 0x4f3ae0 -> 0x4f36b0): every object
		# without an AI task is asked, group members too (Dwarven Peasants, Treants: 0x4f5700 groups builders past 49 hit
		# points); the task that 0x4fd940 chooses takes the unit out of its group before it runs (`_leave_for_task`), even
		# when 0x4f87c0 then fails. The Improved armies rules keep the AI-7 rule (a busy group member gets none).
		if busy(u):
			if _improved() or not _member(u.unit_id) or tasks.has("u%d" % u.unit_id) or world.pending_builds.has(u.unit_id) \
				or world.mine_orders.has(u.unit_id): continue
		# AI-4 (Read, 0x523e10 / 0x4fce30): a builder other than the hero offers both construction menus (+0x3bc0 and +0x3be4,
		# the race's menu rows 0 and 1, where the towers are); the hero only the first.
		if _give_build(u, now_ms, world.production.construction_menu(me) + world.production.construction_menu(me, 1)): continue
		# B4-3 (BATCH4_RESEARCH.md E4, Emulated "unit_task"; decompile 167863-167876): no mine choice for AEBX or a type 0x523e70 gives no
		# workers (AEAX, AWJX, AWKX, AAEG).
		if u.type_id == ELVEN_PEASANT or world.production.rules.mine_workers(u.type_id) <= 0: continue
		if free_peasants > PEASANT_FREE and int(units[PEASANT].count) + int(units[PEASANT].pending) >= PEASANT_LIST and _give_mine(u, now_ms):
			free_peasants -= 1
	_give_advancements(now_ms)

## B1-5 (Read, 0x4fd940 unit branch -> task type 3 0x4f8dc0 -> 0x4cf690): every unit without a task whose type advances
## (0x4fd8c0, Advancement.TREE) offers its targets; among the want-list nodes (in list order, not done) of those targets
## that pass the cooldown gate 0x4f8600, the highest 1d30 + bonus + priority wins (first on ties). 0x4cf690 then needs
## the stockpile to cover the node's price in every lane and sends message 500 for that one unit with the price
## 0x40b6b0(target, the unit's type, player), whose handler 0x4a8ff0 morphs the unit and charges it; 0x4f8750 stamps the
## target's timer (the node stays listed). No building is tested here: the targets' availability (their requirement
## words, `recount`) decides whether they are wanted at all. Group members advance too (0x4f84a0(1) asks every object).
func _give_advancements(now_ms: int):
	if race != UNDEAD: return
	for u in my_units():
		var targets: Array = Advancement.TREE.get(String(u.type_id), [])
		if targets.is_empty() or u.dying or u.removed or u.inside_building or tasks.has("u%d" % u.unit_id): continue
		var best = null
		var best_score := -1
		for w in want:
			if w.done or not (String(w.id) in targets) or not gate(String(w.id)): continue
			var score: int = roll(1, 30) + int(w.bonus) + int(w.priority)
			if best == null or best_score < score:
				best = w
				best_score = score
		if best == null: continue
		var target := String(best.id)
		var stock: Array = world.economy.resources(me)
		var covered := true
		for lane in 4: covered = covered and int(stock[lane]) >= int(best.cost[lane])
		_started(target)                                       # 0x4f8750 runs whether or not the message went out
		if not covered: continue
		var price: Array = world.production.price_of(me, target, String(u.type_id))
		var made = world.morph_unit(u, target, true)
		if made == null: continue
		world.economy.debit_clamped(me, price)
		stats.advancements = int(stats.get("advancements", 0)) + 1
		var key := "%s>%s" % [String(u.type_id), target]
		advanced[key] = int(advanced.get(key, 0)) + 1
		if log.size() < 400: log.append({"t": now_ms, "advance": key})

func _give_build(u, now_ms: int, menu: Array) -> bool:
	var best := ""
	var best_score := -1
	for id in menu:
		var w = _want(id)
		if w == null or not buildings.has(id) or not buildings[id].available or not gate(id): continue
		var score: int = roll(1, 30) + int(w.bonus) + int(w.priority)
		if score > best_score:
			best_score = score
			best = id
	if best == "": return false
	# 0x4fe060 runs inside 0x4fd940 as soon as the choice is a construction (decompile 167847-167852), before 0x4f87c0:
	# an outpost (a BWT? of the list, 0x4f8f40) is placed around the site +0x3ac0 of 0x4f8fa0, the rest around home
	# through 0x4fbdf0, which may move home first (AI-9, `home_centre`). The command chain's mine site 0x4fe0f0 is never
	# reached in a match (AI-9: its item words +0x3b90..+0x3ba0 are -1 from the constructor and have no writer).
	var centre: Vector2i = outpost_site if _outpost_types().has(best) and outpost_site.x >= 0 else home_centre()
	_leave_for_task(u)                                              # AI-8: 0x4fbad0 runs before 0x4f87c0
	# AI-6 (Read, 0x4f9790 case 0 / 0x4f9bd0, decompile 164192-164229, 164390; cleared by 0x4fa120 at 164741): one new
	# construction per pass. Once a build task has started (or a site search failed) this pass, a builder whose choice is a
	# construction gets no task at all (0x4f87c0 fails, the task is freed; the mine branch is not reached). AI-9 (Read,
	# 0x4fd940 decompile 167803-167862): the construction is chosen whenever a wanted node passes 0x4f8600, without a look
	# at +0x2300, so the original holds its other builders off the mines the same way.
	if building_stopped: return true
	building_stopped = true
	# AI-7: main.ai_site is the original's window search (simulation/ai_sites.gd); the task reserves the footprint
	# (0x4f9a10) until it ends.
	var site: Vector2i = world.ai_site(me, best, centre, u)
	if site.x < 0:                                                  # +0x2300: building stops for this pass
		_note_fail("site", best)
		return true
	if not world.ai_build(u, best, site):
		_note_fail("place", best)
		return true
	tasks["u%d" % u.unit_id] = {"type": "build", "item": best, "unit": u.unit_id, "cell": site, "started": now_ms,
		"reserved": AiSites.reserved_cells(world.production.rules.definition(best).footprint, site)}
	_set_taken(best, true)                                          # 0x4f9bd0 -> 0x4fb070; 0x4f8750 waits for the placement
	stats.builds += 1
	_task_started(best)
	return true

## AI-8 (Read, disassembly 0x4f85a8-0x4f85c1, 0x4fbad0, 0x4f36b0 at decompile 158737-158778): once 0x4fd940 has chosen a
## task, 0x4fbad0 (with the army object +4 present and the node's group +0x10 set) calls 0x4f66d0 -> 0x4f3ae0: 0x4f36b0
## frees the member's slot, sets the node's group to -1 and stops the unit's head order (0x520c90 + 0x406600; it also
## sets the unit's +0xd0, not traced), then 0x4f37f0 recounts. The unit is a free object again once the task ends and
## 0x4f5700 may group it anew. Faithful groups only (the Improved armies rules keep their 10b records).
func _leave_for_task(u):
	if _improved(): return
	for g in groups:
		if not g.has("slots") or not (int(u.unit_id) in g.slots): continue
		Groups.leave(g, int(u.unit_id))
		_stop(u)

## Diagnostics (soak dumps): failed site searches / placements by item.
func _note_fail(kind: String, item: String):
	var key := "%s:%s" % [kind, item]
	var fails: Dictionary = stats.get("build_fails", {})
	fails[key] = int(fails.get(key, 0)) + 1
	stats["build_fails"] = fails

## AI-7 (Read, 0x4f84a0(1), decompile 163162-163175): a new task that starts (0x4f87c0) takes its item's pending at once
## (0x4f9bd0 for a construction, 0x4f9c80 for a job) and the want list is built again (0x4ff3b0) before the next object.
func _task_started(item: String):
	if buildings.has(item): buildings[item].pending += 1
	elif units.has(item): units[item].pending += 1
	build_want_list()

## 0x4fd940 mine choice: demand weight of the lane / 4 + 1d30 + max(0, 20 - distance / 4) over owned mines with free slots.
func _give_mine(u, now_ms: int) -> bool:
	var best := -1
	var best_score := -1
	var pending := {}
	for key in tasks:
		if tasks[key].type == "mine": pending[int(tasks[key].mine)] = int(pending.get(int(tasks[key].mine), 0)) + 1
	for row in world.mines.census(me):
		if not row.owned or row.exhausted or int(row.workers) + int(pending.get(row.id, 0)) >= MINE_WORKERS: continue
		var score: int = int(demand_weights[row.lane]) / 4 + roll(1, 30) + maxi(0, 20 - cheb(u.cell, row.cell) / 4)
		if score > best_score:
			best_score = score
			best = row.id
	if best < 0:
		_note_fail("mine", "none")
		return false
	_leave_for_task(u)                                              # AI-8: 0x4fbad0 runs before 0x4f87c0
	if not world.ai_enter_mine(u, best):
		_note_fail("mine", "order")
		return false
	tasks["u%d" % u.unit_id] = {"type": "mine", "mine": best, "unit": u.unit_id, "started": now_ms}
	stats.mine_orders += 1
	_task_started("")
	return true

# ============================================================================================ outposts (AI-4)
## The original's towers: the "outpost" of AI_RESEARCH.md 3.2 (category 0x20) is a BWT? tower (Read, decompile
## 163751-163990, 168303-168400, 168686-168740, 169340-169430).
## * 0x4f8fa0 (every pass, after the census): the limit by difficulty is 3 / 7 / 13 (Lord, other) / 20 / 30 / 45. The towers
##   (0x4fe7c0: 'BWT?') of every active player allied with this one (0x748915[i + me * 7], itself included) are listed;
##   once this player's own reach the limit, or own plus the reserved sites of started outpost tasks (+0x3a98, 0x4f9400)
##   do, there is no site (+0x3ac0 = -1). Otherwise every own non-tower building scores: v = (max(0, +0x20c4 x k0,
##   +0x20c3 x k4, +0x20c5 x k1, +0x20c6 x k2) >> 6) with the profile bytes 100 / 70 / 70 / 40 and the type record of
##   0x4ff900 (k0 = level + 2 for BK?, k4 = level + 1 for BR?, 5 for B?T?, k1 = 3 when the race's production row trains an
##   'A' item, else k2 = 3 when it produces something); with near = the listed towers within 12 cells (Chebyshev, the
##   building's y moved by BUI +0x3e >> 1) and d = the nearest one's distance (1000 none): score = d / 4 + ((v - near) x 100 /
##   (v + 1)) x 4 when v >= 1 and the second term >= 1, else 0. The first best building's cell is the site.
## * 0x4fed50 (want list, after 0x10): a listed 0x20 node stays while its entry is available (+0xc); otherwise it goes.
##   With at least 3 owned buildings (count +8 of entries with the menu flag, not walls or mines) a tower type is drawn
##   (0x4f8f60: 1d n over the list's available 'BW' entries, 0x4fe700) and wanted at priority 90 when a site exists.
## * 0x4fe060: the builder places it around the site.
var outpost_site := Vector2i(-1, -1)          # +0x3ac0 / +0x3ac2
const OUTPOST_LIMIT := {1: 3, 2: 7, 4: 20, 5: 30, 6: 45}   # other 13
var _outpost_values := {}

func _outpost_types() -> Array:
	var out: Array = []
	for id in building_order:
		if String(id).substr(1, 1) == "W" and bool(buildings[id].available): out.append(id)
	return out

static func is_tower(id: String) -> bool:
	return id.length() == 4 and id[0] == "B" and id[1] == "W" and id[2] == "T"

## 0x4ff900's record of a building type for this player's race and the 0x4f8fa0 value before the >> 6.
func outpost_value(id: String) -> int:
	if _outpost_values.has(id): return int(_outpost_values[id])
	var k := [0, 0, 0, 0, 0]
	var row: Dictionary = world.production.rules.production_table(race).get(id, {})
	for slot in Array(row.get("slots", [])).slice(0, 9):
		var raw_id = slot.get("id") if slot is Dictionary else null
		var item := "" if raw_id == null else str(raw_id)
		if item == "": continue
		if item[0] == "A": k[1] = 3
		else: k[2] = 3
	var digit: int = id.unicode_at(3) if id.length() == 4 else 0
	if id.length() == 4:
		if id[1] == "K": k[0] = digit - 0x2e
		elif id[1] == "R": k[4] = digit - 0x2f
		elif id[1] == "T": k[4] = 5
		elif id[1] == "W" and id[2] == "T": k[3] = 3
	var w: Array = profile.get("outpost_weights", [100, 70, 70, 40])      # +0x20c4, +0x20c3, +0x20c5, +0x20c6
	var value := maxi(0, int(w[0]) * int(k[0]))
	value = maxi(value, int(w[1]) * int(k[4]))
	value = maxi(value, int(w[2]) * int(k[1]))
	value = maxi(value, int(w[3]) * int(k[2]))
	_outpost_values[id] = value
	return value

func plan_outpost():
	outpost_site = Vector2i(-1, -1)
	var limit: int = int(OUTPOST_LIMIT.get(difficulty, 13))
	var towers: Array = []
	var own := 0
	for p in 6:
		var slot: Dictionary = world.skirmish.slots[p] if p < world.skirmish.slots.size() else {}
		if not bool(slot.get("active", false)) or not world.combat.allied(p, me): continue
		for b in world.production.buildings.values():
			if int(b.owner) != p or not is_tower(String(b.original_type_id)): continue
			towers.append(Vector2i(int(b.left), int(b.top)))
			if p == me:
				own += 1
				if own >= limit: return
	for key in tasks:                                                # +0x3a98: sites of started outpost tasks
		var t: Dictionary = tasks[key]
		if t.type != "build" or t.get("placed", false) or not is_tower(String(t.item)): continue
		towers.append(Vector2i(t.cell))
		own += 1
		if own >= limit: return
	var best_score := 0
	var best := Vector2i(-1, -1)
	var objects: Array = []
	for b in world.production.buildings.values():
		if int(b.owner) == me: objects.append({"id": String(b.original_type_id), "cell": Vector2i(int(b.left), int(b.top))})
	for id in world.mines.mines:
		var m: Dictionary = world.mines.mines[id]
		if int(m.entity.owner) == me: objects.append({"id": String(m.code), "cell": Vector2i(m.anchor)})
	for o in objects:
		var id: String = o.id
		if is_tower(id): continue
		var value: int = outpost_value(id) >> 6
		var raw: PackedByteArray = String(world.production.rules.definition(id).get("raw_hex", "")).hex_decode()
		var c: Vector2i = o.cell
		var y: int = c.y + ((raw[0x3e] >> 1) if raw.size() > 0x3e else 0)
		var nearest := 1000
		var near := 0
		for t in towers:
			var d := maxi(absi(t.x - c.x), absi(t.y - y))
			nearest = mini(nearest, d)
			if d < 12: near += 1
		var score := 0
		if value >= 1:
			var term: int = R.tdiv((value - near) * 100, value + 1) * 4
			if term >= 1: score = (nearest >> 2) + term
		if best_score < score:
			best_score = score
			best = c
	outpost_site = best

func _want_outpost():
	var node = _node_with(0x20)
	if node != null:
		var entry = buildings.get(String(node.id))
		if entry != null and bool(entry.available): return
		want_remove(String(node.id))
	var flags: Array = _menu_flags()
	var owned := 0
	for j in building_order.size():
		var id := String(building_order[j])
		if flags[j] and id[1] != "W" and id[1] != "R": owned += int(buildings[id].count)
	if owned < 3: return
	var types := _outpost_types()
	if types.is_empty(): return
	var pick: String = types[roll(1, types.size()) - 1]                 # 0x4f8f60: 1d n
	if bool(buildings[pick].available) and outpost_site.x >= 0: want_insert(pick, 90, 0x20)

# ============================================================================================ army (0x4f5610)
func _in_launched_group(id: int) -> bool:
	for g in groups:
		if g.launched and id in g.members: return true
	return false

func _member(id: int) -> bool:
	for g in groups:
		if id in g.members: return true
	return false

func _leave_groups(id: int):
	for g in groups:
		if g.has("slots"): Groups.leave(g, id)
		else: g.members.erase(id)

## AI-7: the original's machine (simulation/ai_groups.gd, AI_RESEARCH.md section 23) unless the opt-in Improved armies
## rules are on; those keep the 10b grouping below, which they were built on.
func army(now_ms: int):
	if _improved():
		_army_10b(now_ms)
		return
	_army_faithful(now_ms)

## Each pass: drop dead members and empty groups; the hero, once the Keep exists, gets its own new group (0x4f59e0 ->
## 0x4f5570, type 9) which launches at once (0x4f3520); idle fighters recruit (Swordsmen into a Normal group, Squires
## into a Long Range group: the 10b stand-in, kept for the Improved armies rules only); launches use the Emulated
## threshold and human focus; one launched group's target is planned per pass (round robin, 0x4f6530).
func _army_10b(now_ms: int):
	for g in groups:
		if g.has("slots"): g.erase("slots")                 # a faithful record switched to the Improved rules: members stay
	var alive_ids := {}
	for u in my_units(): alive_ids[u.unit_id] = u
	for g in groups: g.members = g.members.filter(func(id): return alive_ids.has(id) and world.combat.alive(world.combat.fighters.get(id)))
	groups = groups.filter(func(g): return not g.members.is_empty() or not g.launched)
	var hero = hero_unit()
	var keep_stands := false
	for id in KEEPS: keep_stands = keep_stands or int(buildings[id].count) > 0
	if hero != null and keep_stands and not retreating and not _member(hero.unit_id) and not tasks.has("u%d" % hero.unit_id) and not world.unit_busy(hero):
		var g := {"kind": HERO_GROUP, "members": [hero.unit_id], "launched": false, "target_player": -1, "target": {}, "hero": true}
		groups.append(g)
	# 0x4f6d90: a group holding a converter with fewer than 4 members becomes a conversion group (at most 3); one that lost
	# its converter falls back to type 9.
	var conversion_groups := groups.filter(func(x): return int(x.kind) == CONVERSION_GROUP).size()
	for g in groups:
		var converters: int = g.members.filter(func(id): return world.unit_by_id(id) != null and world.can_convert(world.unit_by_id(id))).size()
		if int(g.kind) == CONVERSION_GROUP and converters == 0: g.kind = HERO_GROUP
		elif int(g.kind) != CONVERSION_GROUP and converters > 0 and g.members.size() < 4 and conversion_groups < CONVERSION_GROUPS:
			g.kind = CONVERSION_GROUP
			conversion_groups += 1
	for u in alive_ids.values():
		if not fights(u.type_id, u) or busy(u) or _member(u.unit_id): continue
		_recruiting(1 if (world.production.rules.status_bits(u.type_id) & Rules.MISSILE_BIT) != 0 else 0).members.append(u.unit_id)
	for g in groups:
		if g.launched: continue
		if _improved() and int(g.get("rest_until", 0)) > now_ms: continue
		if R.launches(int(g.kind), g.members.size(), bool(g.get("hero", false)), difficulty, profile.get("group_min", []) + profile.get("group_max", [])):   # 0x4f3520
			g.launched = true
			g.target_player = _launch_target()                                               # 0x4f4e30
			stats.launches += 1
			log.append({"t": now_ms, "launch": g.kind, "size": g.members.size(), "player": g.target_player})
			if _improved(): _on_launch_improved(g)
	if _improved(): _armies_improved(now_ms)
	var launched: Array = groups.filter(func(x): return x.launched)
	if launched.is_empty(): return
	group_cursor = (group_cursor + 1) % launched.size()
	if _improved() and launched[group_cursor].get("fighting", false): return   # fighting on the march (_engage_improved)
	_plan(launched[group_cursor])

# ============================================================================================ AI-7: 0x4f5610 faithful
const Groups = preload("res://simulation/ai_groups.gd")
const AiSites = preload("res://simulation/ai_sites.gd")
var _type_rows: Dictionary = {}                # unit type -> {layer, size, movement, strength} (ARM +0x100 / +0x39 / +5, D1)

func _type_row(type_id: String) -> Dictionary:
	if _type_rows.has(type_id): return _type_rows[type_id]
	var raw: PackedByteArray = String(world.production.rules.definition(type_id).get("raw_hex", "")).hex_decode()
	var row := {"layer": raw.decode_s16(0x100) if raw.size() >= 0x102 else 0, "size": int(raw[0x39]) if raw.size() > 0x39 else 1,
		"movement": int(raw[5]) if raw.size() > 5 else 0, "footprint": int(raw[0x38]) if raw.size() > 0x38 else 1,
		"strength": Danger.unit_strength(raw) if raw.size() > 0x40 else 0}
	_type_rows[type_id] = row
	return row

## The unit records ai_groups.gd reads (its header), for this player's living units.
func _group_ctx() -> Dictionary:
	var recs := {}
	var c = world.combat
	for u in my_units():
		var f = c.fighters.get(u.unit_id)
		if f == null: continue
		var t := _type_row(String(u.type_id))
		recs[int(u.unit_id)] = {"id": int(u.unit_id), "code": String(u.type_id), "cell": u.cell, "hp": int(f.hp), "max_hp": int(f.max_hp),
			"speed": int(f.stats.speed), "dmg": int(f.stats.dmg), "range": int(f.stats.get("range", 0)), "converts": world.can_convert(u),
			"strength": int(t.strength), "layer": int(t.layer), "size": int(t.size), "hero": u.type_id == HERO,
			"general": bool(world.get("generals").has(String(u.type_id))) if world.get("generals") is Dictionary else false,
			"dying": bool(u.dying) or not c.alive(f), "hidden": bool(u.inside_building) or world.in_mine(u),
			"entering": world.mine_orders.has(u.unit_id)}
	var players: Array = []
	for p in 6:
		var slot: Dictionary = world.skirmish.slots[p]
		players.append({"active": bool(slot.active), "computer": bool(slot.computer), "eliminated": bool(world.skirmish.eliminated[p]),
			"allied": p == me or world.skirmish.is_allied(me, p)})
	var words: Array = Groups.default_words()
	var sizes: Array = profile.get("group_min", []) + profile.get("group_max", [])
	if sizes.size() == 12:
		for i in 12: words[i] = int(sizes[i])
	return {"difficulty": difficulty, "words": words, "units": recs, "roll": roll, "players": players, "main_enemy": main_enemy,
		"retreating": retreating}

## 0x4f5610: every group's update 0x4f39f0 (empty groups go), the cursor group's (and every hero or idle group's) target
## 0x4f6530, the assignment 0x4f5700, the retyping 0x4f6d90 and every group's launch check 0x4f3520.
func _army_faithful(now_ms: int):
	for g in groups.duplicate():
		if not g.has("slots"): _faithful_record(g)
	var ctx := _group_ctx()
	var before := {}
	for g in groups: before[int(g.slot)] = bool(g.launched)
	var scene := {}
	for g in groups.duplicate():
		if not _update_group(g, ctx, scene): groups.erase(g)
	if not groups.is_empty():
		var tries := 0
		while Groups.by_slot(groups, group_cursor) == null and tries < Groups.GROUPS:
			group_cursor = (group_cursor + 1) % Groups.GROUPS
			tries += 1
		if tries < Groups.GROUPS:
			for g in groups.duplicate():
				if int(g.slot) != group_cursor and not Groups.has_hero(g, ctx) and int(g.mode) != 0: continue
				if bool(g.launched): _plan_faithful(g)
			group_cursor = (group_cursor + 1) % Groups.GROUPS
	_recruit(ctx)
	Groups.pass_tail(groups, ctx)
	for g in groups:
		if bool(g.launched) and not bool(before.get(int(g.slot), false)):
			stats.launches += 1
			log.append({"t": now_ms, "launch": g.kind, "size": Groups.count(g), "player": g.target_player})

## An old (10b) group record becomes a faithful one: its members in slots 0.., its type, launch and target kept.
func _faithful_record(g: Dictionary):
	var taken := {}
	for other in groups: if other.has("slot"): taken[int(other.slot)] = true
	var slot := 0
	while taken.has(slot): slot += 1
	var rec := Groups.new_record(slot)
	var k := 0
	for id in g.members:
		if k < Groups.SLOTS:
			rec.slots[k] = int(id)
			k += 1
	rec.kind = int(g.kind)
	rec.launched = bool(g.launched)
	rec.target_player = int(g.target_player)
	rec.target = g.target
	rec.mode = 2 if not g.target.is_empty() else 1
	g.clear()
	g.merge(rec)
	Groups.sync(g)

## 0x4f39f0: members gone or dying leave; near the command limit (used > limit - 4) a group at home launches; the march
## state 0x4f3b00; the members' orders 0x4f42a0. An empty group is removed (returns false).
func _update_group(g: Dictionary, ctx: Dictionary, scene: Dictionary) -> bool:
	if Groups.count(g) == 0:
		for id in g.slots.duplicate(): if int(id) != -1: Groups.leave(g, int(id))
		return false
	Groups.drop_dead(g, ctx)
	var pop: Dictionary = world.production.population(me)
	if int(pop.maximum) - 4 < int(pop.current) and not bool(g.launched): Groups.launch(g, ctx)
	Groups.march(g, _target_info(g), ctx)
	_group_orders(g, ctx, scene)
	return true

## The group's target object as 0x4f3b00 tests it: gone ({}), dying, allied, a destroyed building (+0x115).
func _target_info(g: Dictionary) -> Dictionary:
	if g.target.is_empty(): return {}
	var c = world.combat
	if String(g.target.kind) == "unit":
		var f = c.fighters.get(int(g.target.id))
		var u = world.unit_by_id(int(g.target.id))
		if f == null or u == null or u.removed: return {}
		return {"cell": c.unit_cell(int(f.id)), "dying": not c.alive(f) or u.dying, "allied": world.skirmish.is_allied(me, int(f.owner)) or int(f.owner) == me}
	if String(g.target.kind) == "building":
		var b = world.production.building(int(g.target.id))
		if b == null: return {}
		return {"cell": Vector2i(b.left, b.top), "dying": false, "allied": world.skirmish.is_allied(me, int(b.owner)) or int(b.owner) == me,
			"flag_0x115": int(b.hit_points) <= 0}
	if String(g.target.kind) == "mine":
		var row = null
		for r in world.mines.census(me):
			if int(r.id) == int(g.target.id): row = r
		if row == null or bool(row.owned): return {}
		return {"cell": row.cell, "dying": false, "allied": false}
	return {}

## 0x4f6530 for one launched group: a new attacked player when its own is eliminated (0x4f4e30), then 0x4f66f0's choice;
## no target: mode 0; a different target (or mode 0): Attack mode, state Initialising.
func _plan_faithful(g: Dictionary):
	if int(g.target_player) >= 0 and int(g.target_player) < 6 and world.skirmish.eliminated[int(g.target_player)]:
		g.target_player = _launch_target()
	var best := _best_target(g)
	if best.is_empty():
		g.mode = 0
		g.state = 0
		g.target = {}
		return
	var same: bool = not g.target.is_empty() and String(g.target.kind) == String(best.kind) and int(g.target.id) == int(best.id)
	if int(g.mode) == 0 or not same:
		g.mode = 2
		g.state = 0
		g.target = {"kind": best.kind, "id": int(best.id), "code": String(best.get("code", ""))}

## The hostile objects of the map rows for 0x4f3e70, built once per pass: row y -> objects in x order.
func _scene_rows(scene: Dictionary) -> Dictionary:
	if scene.has("rows"): return scene.rows
	var rows := {}
	var c = world.combat
	for f in c.fighters.values():
		var owner := int(f.owner)
		if owner == me or world.skirmish.is_allied(me, owner): continue
		var u = world.unit_by_id(int(f.id))
		if u == null or u.removed or u.inside_building: continue
		var aims := false
		if f.order != null:
			var o := int(c.object_owner(String(f.order.target_kind), int(f.order.target_id)))
			aims = o >= 0 and (o == me or world.skirmish.is_allied(me, o))
		var mv := int(_type_row(String(f.type_id)).movement)
		_row_add(rows, {"ref": "unit:%d" % int(f.id), "kind": "unit", "id": int(f.id), "cell": c.unit_cell(int(f.id)), "owner": owner,
			"allied": false, "dying": not c.alive(f) or u.dying, "ground": mv == 0 or mv == 3, "aims_at_ally": aims})
	for b in world.production.buildings.values():
		var owner := int(b.owner)
		if owner == me or world.skirmish.is_allied(me, owner) or int(b.hit_points) <= 0: continue
		var code := String(b.original_type_id)
		var tower = c.towers.get(b.entity_id)
		var cfg := _building_cfg(code)
		# 0x4f3e70 passes over BMFL, ?T?? / ?R??, income buildings (0x52b050), searchable sites (0x52ed90 -> Building.cfg
		# +0x7a) and shops (0x5877e0, +0x7f); lairs (+0x1a2 = Building.cfg +0x7e, set by the constructor at decompile
		# 201357) only for Kick Butt groups.
		_row_add(rows, {"ref": "building:%d" % int(b.entity_id), "kind": "building", "id": int(b.entity_id), "cell": Vector2i(b.left, b.top),
			"owner": owner, "allied": false, "skip": code == "BMFL" or (code.length() > 1 and (code[1] == "T" or code[1] == "R")) \
				or bool(cfg.get("searchable", false)) or bool(cfg.get("shop", false)),
			"flag_0x1a2": bool(cfg.get("lair", false)), "armed": tower != null and int(tower.get("damage", 0)) >= 1, "code": code})
	for y in rows: rows[y].sort_custom(func(a, b): return a.cell.x < b.cell.x)
	scene.rows = rows
	return rows

var _cfg_rows: Dictionary = {}
func _building_cfg(code: String) -> Dictionary:
	if _cfg_rows.is_empty():
		for row in world.production.rules.catalogue.get("building_cfg", {}).get("buildings", []): _cfg_rows[String(row.code)] = row
		_cfg_rows["-"] = {}
	return _cfg_rows.get(code, {})

static func _row_add(rows: Dictionary, o: Dictionary):
	var y: int = o.cell.y
	if not rows.has(y): rows[y] = []
	rows[y].append(o)

## 0x4f42a0: every member looks around (0x4f3e70); the highest level decides: 0 the mode / state orders (0x4f4320),
## 1 / 2 one object for all (0x4f4390 / 0x4f4460), 3 each the find of the nearest member that found one (0x4f4530).
func _group_orders(g: Dictionary, ctx: Dictionary, scene: Dictionary):
	var rows := _scene_rows(scene)
	var w: int = world.collision.width
	var h: int = world.collision.height
	var top := 0
	for k in Groups.SLOTS:
		if int(g.slots[k]) == -1: continue
		top = maxi(top, Groups.look(g, k, rows, w, h, ctx))
	match top:
		0: _mode_orders(g, ctx)
		1, 2:
			var pick = Groups.common_target(g, top)
			var obj := _ref_object(pick)
			if obj.is_empty(): return
			for k in Groups.SLOTS:
				if int(g.slots[k]) == -1: continue
				g.data[k].alevel = top
				g.data[k].atarget = pick
				_attack(int(g.slots[k]), obj, g.data[k])
		3:
			for k in Groups.SLOTS:
				var id := int(g.slots[k])
				var u = ctx.units.get(id)
				if id == -1 or u == null: continue
				var near := -1
				var best := 1000
				for j in Groups.SLOTS:
					var other = ctx.units.get(int(g.slots[j]))
					if int(g.slots[j]) == -1 or int(g.data[j].level) != 3 or other == null: continue
					var d := cheb(u.cell, other.cell)
					if d < best or near == -1:
						near = j
						best = d
				if near != -1: _attack(id, _ref_object(g.data[near].obj), g.data[k])

func _ref_object(ref) -> Dictionary:
	if ref == null: return {}
	var parts := String(ref).split(":")
	return {"kind": parts[0], "id": int(parts[1])} if parts.size() == 2 else {}

## 0x51da60 (player level, as the 10b port): a member not already attacking the object attacks it.
func _attack(id: int, obj: Dictionary, data: Dictionary):
	if obj.is_empty() or tasks.has("u%d" % id): return
	var f = world.combat.fighters.get(id)
	if f == null: return
	if f.order != null and String(f.order.target_kind) == String(obj.kind) and int(f.order.target_id) == int(obj.id): return
	if world.combat.order_attack(id, String(obj.kind), int(obj.id), false):
		stats.attacks += 1
		data.move = null

func _has_order(u) -> bool:
	var f = world.combat.fighters.get(u.unit_id)
	return not u.orders.is_empty() or (f != null and f.order != null)

func _attacking(u) -> bool:
	var f = world.combat.fighters.get(u.unit_id)
	return f != null and f.order != null

## 0x520c90 + 0x406600: the head order goes.
func _stop(u):
	u.stop()
	world.combat.order_stop(u.unit_id)

## 0x51d6b0 at the group's slowest speed (+0x36).
func _walk(u, cell: Vector2i, g: Dictionary, data: Dictionary):
	world.ai_move(u, cell, int(g.min_speed))
	data.move = cell

## 0x4f4d50: a member more than 4 cells from the centre walks there unless it already walks to within 4 of it.
func _follow(u, g: Dictionary, data: Dictionary):
	if cheb(u.cell, g.centre) <= 4: return
	if not u.orders.is_empty() and data.move != null and cheb(data.move, g.centre) < 5: return
	_walk(u, g.centre, g, data)

## 0x4f4320 per member: mode 0 / 1 (no target, Recruit) and state 0: the leader stops, the others gather (0x4f4b40);
## state 1: members past 10 cells gather, the others and the leader walk to the target (0x4f4690); state 2: attack or
## convert (0x4f47c0); state 4: the leader stops its walk, members walking elsewhere gather (0x4f4a90).
func _mode_orders(g: Dictionary, ctx: Dictionary):
	var info := _target_info(g)
	for k in Groups.SLOTS:
		var id := int(g.slots[k])
		if id == -1 or tasks.has("u%d" % id): continue
		var u = world.unit_by_id(id)
		if u == null or u.removed or u.dying or not ctx.units.has(id): continue
		var data: Dictionary = g.data[k]
		var leader: bool = id == int(g.leader)
		var mode := int(g.mode)
		var state := int(g.state) if mode == 2 else 0
		match state:
			0:
				if leader:
					if _has_order(u): _stop(u)
				else: _follow(u, g, data)
			1:
				if info.is_empty(): continue
				if not leader and cheb(u.cell, g.centre) > 10:
					_follow(u, g, data)
					continue
				var cell: Vector2i = info.cell
				if u.orders.is_empty() or data.move != cell: _walk(u, cell, g, data)
			2:
				if g.target.is_empty(): continue
				var code := String(g.target.get("code", ""))
				var convertible: bool = int(g.kind) == Groups.CONVERSION and (String(g.target.kind) == "mine" or (String(g.target.kind) == "building" and code.length() > 1 and code[1] == "T"))
				if convertible:
					if leader and world.can_convert(u):
						if not world.converting(u) and world.ai_convert(u, String(g.target.kind), int(g.target.id)): stats.conversions += 1
					else: _follow(u, g, data)
					continue
				if String(g.target.kind) == "mine": continue
				_attack(id, {"kind": String(g.target.kind), "id": int(g.target.id)}, data)
			4:
				if not _has_order(u) or _attacking(u): continue
				if leader: _stop(u)
				else: _follow(u, g, data)

## 0x4f5700: every listed unit without an AI task and without a group: up to the profile's share (+0x20bd, 20 %) of the
## units go into own mines with room (0x4f71e0 / 0x4f72e0, Read), the others are offered to 0x4f59e0 (ai_groups.gd).
func _recruit(ctx: Dictionary):
	var grouped := {}
	for g in groups:
		for id in g.slots: if int(id) != -1: grouped[int(id)] = int(g.slot)
	var counted := 0
	var in_mine := 0
	var entering := 0
	for u in my_units():
		if world.in_mine(u) or u.inside_building:
			in_mine += 1
			counted += 1
		elif world.mine_orders.has(u.unit_id):
			entering += 1
			counted += 1
		elif world.production.rules.builder_power(u.type_id) == 0 and int(_type_row(String(u.type_id)).movement) == 0:
			counted += 1
	var free_mines: Array = []
	var room := 0
	for row in world.mines.census(me):
		if not bool(row.owned) or int(row.workers) >= 4: continue
		free_mines.append(row)
		room += 4 - int(row.workers)
	var allowed: int = mini(maxi(int(profile.get("conversion_share", 20)) * counted / 100 - (in_mine + entering), 0), room)
	var keep_stands := false
	for id in KEEPS: keep_stands = keep_stands or int(buildings[id].count) > 0
	for u in my_units():
		if tasks.has("u%d" % u.unit_id) or not ctx.units.has(int(u.unit_id)): continue
		var rec: Dictionary = ctx.units[int(u.unit_id)]
		if u.type_id == HERO:
			if retreating or not keep_stands: continue                 # the 10b reading (Provisional): the hero joins once a Keep stands
		elif not fights(u.type_id, u): continue
		if grouped.has(int(u.unit_id)): continue
		if allowed > 0 and u.type_id != HERO and not bool(rec.hidden) and not bool(rec.entering) and _mine_worthy(u, rec) and _send_to_mine(u, free_mines):
			allowed -= 1
			continue
		if bool(rec.hidden) or bool(rec.entering): continue
		var s := Groups.recruit_one(groups, rec, ctx)
		if s >= 0: grouped[int(u.unit_id)] = s

## 0x51c240 (Read) with 0x4f5700's own terms: a unit of extent 1 that is no builder and no animal, slow (speed < 3) unless
## the profile's +0x20c2 is set.
func _mine_worthy(u, rec: Dictionary) -> bool:
	if not bool(profile.get("slow_to_mines_any", false)) and int(rec.speed) >= 3: return false
	if int(_type_row(String(u.type_id)).footprint) > 1 or world.production.rules.builder_power(u.type_id) != 0: return false
	return not UnitAI.is_animal(String(u.type_id)) and String(u.type_id) != "AAEY"

## 0x4f72e0: the own mine with room nearest home plus 1d200; the unit is sent in (0x5257b0, player level).
func _send_to_mine(u, free_mines: Array) -> bool:
	var pick = null
	var best := 0
	for row in free_mines:
		var score := cheb(home, row.cell) + roll(1, 200)
		if pick == null or score < best:
			pick = row
			best = score
	return pick != null and world.ai_enter_mine(u, int(pick.id))

## B4-3 (BATCH4_RESEARCH.md E24, Emulated review "groups"; decision 7): 0x4f5700 asks every own unit without a task (the caller's
## busy test): not the hero, and a builder only when its maximum hit points exceed 49 (Treants, Ancient Wisps, Dwarven Smiths).
func fights(type_id: String, u = null) -> bool:
	if type_id == HERO: return false
	var f = world.combat.fighters.get(u.unit_id) if u != null and world.combat != null else null
	var max_hp: int = int(f.max_hp) if f != null else 0
	return Abilities.joins_army(world.production.rules.builder_power(type_id), max_hp)

func _recruiting(kind: int) -> Dictionary:
	for g in groups:
		if not g.launched and int(g.kind) == kind and not g.get("hero", false): return g
	var g := {"kind": kind, "members": [], "launched": false, "target_player": -1, "target": {}, "hero": false}
	groups.append(g)
	return g

## 0x4f4e30 (Emulated in ai_rules): the main enemy, unless 1d100 <= the human focus picks a human (highest 1d100).
func _launch_target() -> int:
	if roll(1, 100) > R.human_focus(difficulty, main_enemy): return main_enemy
	var best := 0
	var target := -1
	for p in 6:
		var slot: Dictionary = world.skirmish.slots[p]
		if p == me or not slot.active or slot.computer or world.skirmish.eliminated[p] or world.skirmish.is_allied(me, p): continue
		var r := roll(1, 100)
		if best < r:
			best = r
			target = p
	return main_enemy if target == -1 else target

## 0x4f66f0 target scoring (Read) over the target list of 0x4f6160 with priorities 0x4f5e90 (Emulated): priority + 700 +
## modifiers - Chebyshev(group, target) + 2d100 (+500 instead for the current target). Modifiers: towers (?WT?) +200 for
## Long Range, +100 otherwise, other targets +50. Mines are taken only by the hero's group, whose hero converts them
## (0x4f4940, within 3 cells); neutral mines are offered to it as well (Provisional: which list holds them is Open).
## Milestone 12 (Read 0x4f66f0 / 0x4f47c0): the hero's group is a conversion group (type 7): mines score +100 without
## workers and -200 with workers, any other target -200 (no tower or +50 terms); its converter converts a mine or a
## building whose second type letter is T (0x4f47c0: 0x52b050 or 'T') and attacks anything else; the 0x532640 scan at the
## end converts every eligible building around it, enemy buildings included.
func _plan(g: Dictionary):
	# Improved Armies: a group answering hits (_engage_improved) keeps fighting; its plan resumes when the fight is over.
	if _improved() and g.get("fighting", false): return
	# W2 (0x4f6530, Read): a launched group whose target player (+0x44) is eliminated (0x748668) chooses again through
	# 0x4f4e30 (main enemy or a human by the focus roll), so in a 3-6 player match it moves on to the next side.
	if g.target_player >= 0 and g.target_player < 6 and world.skirmish.eliminated[int(g.target_player)]:
		g.target_player = _launch_target()
		g.target = {}
	if g.target_player < 0: return
	var best := _best_target(g)
	if best.is_empty(): return
	g.target = {"kind": best.kind, "id": int(best.id)}
	if _improved() and _stage_improved(g, best, _centre(g)): return
	_order_group(g, best)

func _centre(g: Dictionary) -> Vector2i:
	var centre := Vector2i.ZERO
	var count := 0
	for id in g.members:
		centre += world.combat.unit_cell(id)
		count += 1
	return centre / count if count > 0 else centre

## 0x4f66f0's choice for a launched group (the 10b scoring above); {} when nothing scores. The faithful machine (AI-7)
## measures from the group's centre (+0x24, its leader's cell), the 10b one from the members' mean.
func _best_target(g: Dictionary) -> Dictionary:
	if g.has("slots") and int(g.kind) == Groups.CONVERSION: return _conversion_target(g)
	if int(g.target_player) < 0: return {}
	var centre := Vector2i.ZERO
	var count := 0
	for id in g.members:
		centre += world.combat.unit_cell(id)
		count += 1
	if count == 0: return {}
	centre /= count
	if g.has("slots") and int(g.leader) != -1: centre = g.centre
	var hero_group: bool = g.get("hero", false)
	var players: Array = []
	var relations: Array = []
	for p in 6: players.append({"active": bool(world.skirmish.slots[p].active), "start": [world.skirmish.slots[p].start.x, world.skirmish.slots[p].start.y]})
	for a in 7:
		var row: Array = []
		for b in 7: row.append(world.skirmish.is_allied(a, b))
		relations.append(row)
	var candidates: Array = world.ai_targets(int(g.target_player))
	var has_building := candidates.any(func(c): return c.kind == "building")
	if hero_group: candidates += world.ai_mine_targets(me)
	var best := {}
	var best_score := -1000000000
	for candidate in candidates:
		var is_mine: bool = candidate.kind == "mine"
		if is_mine and not hero_group: continue
		var priority := R.target_priority({"kind": 0 if candidate.kind == "unit" else 1, "code": String(candidate.code),
			"cell": [candidate.cell.x, candidate.cell.y], "state": 8 if candidate.get("dying", false) else 0,
			"unfinished": bool(candidate.get("unfinished", false)), "value_0x92": int(candidate.get("value_0x92", 0)),
			"flag": has_building if candidate.kind == "unit" else 0, "home": [home.x, home.y], "demand": demand_weights,
			"me": me, "players": players, "relations": relations})
		if priority <= 0: continue
		var current: bool = not g.target.is_empty() and g.target.kind == candidate.kind and int(g.target.id) == int(candidate.id)
		var modifier := 50
		if String(candidate.code).substr(1, 2) == "WT": modifier = 200 if int(g.kind) == 1 else 100
		if int(g.kind) == CONVERSION_GROUP:
			modifier = (100 if int(candidate.get("workers", 0)) == 0 else -200) if is_mine else -200
		var score: int = priority + 700 + modifier - cheb(centre, candidate.cell) + (500 if current else roll(2, 100))
		if score > best_score:
			best_score = score
			best = candidate
	return best

## AI-11 (AI_RESEARCH.md section 27, Read: decompile 161525-161602, 161605-161705, 161758-161937). A conversion group
## (type 7) does not choose among its target player's objects: 0x4f6530 passes list 7 to 0x4f66f0, and 0x4f6340 fills
## list 7 with every building on the map whose type is 'B?T?' / 'B?R?' (mines) or BMFL, not rubble (+0x115), owned by a
## player not allied with the computer (the neutral player 6 included), with 0x4f5e90(object, 1) > 0; each entry keeps
## its cell, 0x4fac00(object, 0) and a convertible flag of 1. No fog, shroud or "seen" test anywhere in 0x4f6110 /
## 0x4f6160 / 0x4f6340 / 0x4f5e90 / 0x4f66f0. Score: priority + 700, +100 when the entry's danger is 0 else -200,
## -400 x the groups (of the first ten slots) whose target is the entry unless it is this group's own, - Chebyshev from
## the group's centre, + 500 for its current target in a mode other than 0, else + 2d100. The original rebuilds the list
## every 15 s (+0x5940) and stores the cell, priority and danger then; the port scores the live objects (Open: stale
## entries). The leader-cell terms of 0x4f66f0 (0x42d140 / 0x50b0f0, the object's +0x2c) are not ported (Open, the
## strength grid 0x5095a0). Exhausted mines are left out as in `ai_mine_targets` (Open).
func _conversion_target(g: Dictionary) -> Dictionary:
	if _danger == null: _danger = Danger.new(world)
	var centre: Vector2i = g.centre if int(g.leader) != -1 else home
	var players: Array = []
	for p in 6: players.append({"active": bool(world.skirmish.slots[p].active), "start": [world.skirmish.slots[p].start.x, world.skirmish.slots[p].start.y]})
	var relations: Array = []
	for a in 7:
		var row: Array = []
		for b in 7: row.append(world.skirmish.is_allied(a, b))
		relations.append(row)
	var entries: Array = []
	for b in world.production.buildings.values():
		var owner := int(b.owner)
		if owner == me or world.skirmish.is_allied(me, owner) or int(b.hit_points) <= 0: continue
		var code := String(b.original_type_id)
		if code.length() < 4 or code[0] != "B" or not (code[1] == "T" or code[1] == "R" or code == "BMFL"): continue
		entries.append({"kind": "building", "id": int(b.entity_id), "cell": Vector2i(b.left, b.top), "code": code, "owner": owner})
	for row in world.mines.census(me):
		if bool(row.owned) or bool(row.exhausted): continue
		var m: Dictionary = world.mines.mines[row.id]
		var owner := int(m.entity.owner)
		if owner >= 0 and owner < 7 and owner != 6 and world.skirmish.is_allied(me, owner): continue
		entries.append({"kind": "mine", "id": int(row.id), "cell": row.cell, "code": String(m.code), "owner": owner, "workers": int(row.workers)})
	var targeted := {}
	for other in groups:
		if not other.has("slot") or int(other.slot) >= 10 or other.target.is_empty(): continue
		var key := "%s:%d" % [String(other.target.kind), int(other.target.id)]
		targeted[key] = int(targeted.get(key, 0)) + 1
	var best := {}
	var best_score := 0
	var found := false
	for e in entries:
		var priority := R.target_priority({"kind": 1, "code": String(e.code), "cell": [e.cell.x, e.cell.y], "state": 0, "unfinished": false,
			"value_0x92": 0, "flag": true, "home": [home.x, home.y], "demand": demand_weights, "me": me, "players": players, "relations": relations})
		if priority <= 0: continue
		var own: bool = not g.target.is_empty() and String(g.target.kind) == String(e.kind) and int(g.target.id) == int(e.id)
		var score: int = priority + 700
		score += 100 if _danger.danger_to_building(me, String(e.kind), int(e.id), e.cell, String(e.code)) == 0 else -200
		var key := "%s:%d" % [String(e.kind), int(e.id)]
		if int(targeted.get(key, 0)) != 0 and not own: score -= 400 * int(targeted[key])
		score -= cheb(centre, e.cell)
		score += 500 if (int(g.mode) != 0 and own) else roll(2, 100)
		if not found or score > best_score:
			found = true
			best_score = score
			best = e
	return best

func _order_group(g: Dictionary, best: Dictionary):
	for id in g.members:
		var u = world.unit_by_id(id)
		if tasks.has("u%d" % id): continue                      # a member with a construction task follows the task
		var convertible: bool = best.kind == "mine" or (best.kind == "building" and String(best.code).length() > 1 and String(best.code)[1] == "T")
		if int(g.kind) == CONVERSION_GROUP and convertible and u != null and world.can_convert(u):
			if not world.converting(u) and world.ai_convert(u, String(best.kind), int(best.id)): stats.conversions += 1
			continue
		if best.kind == "mine": continue
		var f = world.combat.fighters.get(id)
		if f == null: continue
		if f.order == null or f.order.target_kind != best.kind or int(f.order.target_id) != int(best.id):
			if world.combat.order_attack(id, best.kind, int(best.id), false): stats.attacks += 1   # player-level (D6)

# ============================================================================================ modern armies
# DELIBERATE MODERN CHANGES (modern_rules.gd "Armies", COMPLAINTS_AND_FIXES.md F6). The original launches each group on
# its own as soon as it is big enough and sends it straight at its target, so the computer attacks in small waves that
# arrive one unit at a time and never flank. With the improved rules:
# * a newly launched group joins a launched group with the same target player that has not reached its target yet;
# * a group far from its target first marches (navigation.gd F1) to a staging cell short of it and attacks once gathered
#   (or when hit, or after STAGE_TIMEOUT_MS); a group of FLANK_SIZE or more splits into two halves that stage on either side;
# * a group that has lost most of its strength falls back home and recruits again.
const STAGE_DISTANCE := 8
const STAGE_MIN_DISTANCE := 14
const STAGE_TIMEOUT_MS := 20000
const FLANK_SIZE := 10
const FLANK_DEGREES := 50.0
const RETREAT_SHARE := 35                  # percent of the launch strength
const REST_MS := 30000                     # a group that fell back recruits this long before it may launch again

func _improved() -> bool:
	return world != null and bool(world.get("improved_armies"))

func _strength(g: Dictionary) -> int:
	var total := 0
	for id in g.members:
		var f = world.combat.fighters.get(id)
		if f != null and world.combat.alive(f): total += int(f.hp)
	return total

func _on_launch_improved(g: Dictionary):
	if not g.get("hero", false) and int(g.kind) != CONVERSION_GROUP:
		for other in groups:
			if other == g or not other.launched or other.get("hero", false) or int(other.kind) == CONVERSION_GROUP: continue
			if int(other.target_player) != int(g.target_player) or other.get("engaged", false): continue
			other.members.append_array(g.members)
			other.launch_strength = int(other.get("launch_strength", 0)) + _strength(g)
			other.erase("stage")
			g.members = []
			return
	g.launch_strength = _strength(g)

func _armies_improved(now_ms: int):
	for g in groups:
		if not g.launched or g.members.is_empty(): continue
		# fall back when beaten
		if not g.get("hero", false) and int(g.get("launch_strength", 0)) > 0 and _strength(g) * 100 < int(g.launch_strength) * RETREAT_SHARE:
			var back: Array = g.members.map(func(id): return world.unit_by_id(id)).filter(func(u): return u != null)
			for u in back: world.combat.order_stop(u.unit_id)
			world.march_units(back, world.stage_cell(home, home, 0, 0.0))
			g.launched = false
			g.target = {}
			g.erase("stage")
			g.erase("engaged")
			g.erase("engaged_key")
			g.launch_strength = 0
			g.rest_until = now_ms + REST_MS
			continue
		if _engage_improved(g): continue
		if not g.has("stage"): continue
		var stage: Dictionary = g.stage
		var members: Array = g.members.map(func(id): return world.unit_by_id(id)).filter(func(u): return u != null and not u.dying)
		var gathered := members.all(func(u): return u.orders.is_empty() and not u.in_step)
		var hit := members.any(func(u): return world.combat.ai.was_hit(u.unit_id))
		if gathered or hit or now_ms - int(stage.since) > STAGE_TIMEOUT_MS:
			g.erase("stage")
			g.engaged = true
			if not g.target.is_empty(): _order_group(g, {"kind": g.target.kind, "id": g.target.id, "code": stage.get("code", "")})

## Playtest 2026-11-10 (DELIBERATE MODERN CHANGE, Armies): the original's army orders are player-level (REVIEW_SKIRMISH_AI
## D6), so a marching group walks past enemies and does not even answer units that hit it. With the improved rules each
## member fights the unit that hit it (within FIGHT_BACK_REACH) or the nearest hostile unit within ENGAGE_RADIUS; once no
## member has one, the group goes on to its target (straight at it: the staging is dropped).
## Playtest 2026-11-11: a conversion group (a general on its way to a building) only answers the unit that hits it (it
## does not look for enemies within ENGAGE_RADIUS) and then goes back to converting through the ordinary update; before,
## it was skipped and an Orc general stood among the Wights hitting it.
const ENGAGE_RADIUS := 6
const FIGHT_BACK_REACH := 12

func _engage_improved(g: Dictionary) -> bool:
	if g.get("hero", false): return false
	var converters := int(g.kind) == CONVERSION_GROUP
	var c = world.combat
	var members: Array = []
	for id in g.members:
		var f = c.fighters.get(id)
		if f != null and c.alive(f) and not tasks.has("u%d" % int(id)): members.append(f)
	if members.is_empty(): return false
	var hostile: Array = []
	for f in c.fighters.values():
		var owner := int(f.owner)
		if owner == me or owner >= 6 or not c.alive(f) or world.skirmish.is_allied(me, owner) or f.has("invisible_until"): continue
		var u = world.unit_by_id(int(f.id))
		if u == null or u.inside_building: continue
		hostile.append(f)
	var fighting := false
	for m in members:
		var here: Vector2i = c.unit_cell(int(m.id))
		var best = null
		var best_d := ENGAGE_RADIUS + 1
		var hit = c.ai.attacker_of(m, int(m.id))
		if hit != null and hit.attacker_kind == "unit" and c.fighters.has(int(hit.attacker)):
			var a = c.fighters[int(hit.attacker)]
			var owner := int(a.owner)
			if c.alive(a) and owner != me and owner < 6 and not world.skirmish.is_allied(me, owner) and cheb(here, c.unit_cell(int(a.id))) <= FIGHT_BACK_REACH:
				best = a
		if best == null and not converters:
			for h in hostile:
				var d := cheb(here, c.unit_cell(int(h.id)))
				if d < best_d:
					best_d = d
					best = h
		if best == null: continue
		fighting = true
		if m.order == null or String(m.order.get("target_kind", "")) != "unit" or int(m.order.get("target_id", -1)) != int(best.id):
			if c.order_attack(int(m.id), "unit", int(best.id), false): stats.attacks += 1
	if fighting:
		g.fighting = true
		return true
	if g.get("fighting", false):
		g.erase("fighting")
		g.erase("stage")
		g.engaged = true
		if not converters and not g.target.is_empty(): _order_group(g, {"kind": g.target.kind, "id": g.target.id, "code": ""})
	return false

## Returns true while the group is (or starts) marching to its staging cell.
func _stage_improved(g: Dictionary, best: Dictionary, centre: Vector2i) -> bool:
	if g.get("hero", false) or int(g.kind) == CONVERSION_GROUP or best.kind == "mine": return false
	var key := "%s:%d" % [best.kind, int(best.id)]
	if g.has("stage"): return true                             # keep marching; the release attacks g.target
	if g.get("engaged_key", "") == key: return false
	var members: Array = g.members.map(func(id): return world.unit_by_id(id)).filter(func(u): return u != null and not u.dying and not tasks.has("u%d" % u.unit_id))
	if members.size() < 2 or cheb(centre, best.cell) < STAGE_MIN_DISTANCE: return false
	g.engaged_key = key
	g.stage = {"key": key, "since": now(), "code": String(best.get("code", ""))}
	if members.size() >= FLANK_SIZE:
		var half := members.size() / 2
		world.march_units(members.slice(0, half), world.stage_cell(centre, best.cell, STAGE_DISTANCE, FLANK_DEGREES))
		world.march_units(members.slice(half), world.stage_cell(centre, best.cell, STAGE_DISTANCE, -FLANK_DEGREES))
	else:
		world.march_units(members, world.stage_cell(centre, best.cell, STAGE_DISTANCE, 0.0))
	return true

# ============================================================================================ 0x4fbb90
## Milestone 12 (Read): with no living unit that may convert (0x523af0(0, 0): the hero, a general, AAPH), every Keep of the
## computer player's building list (second type letter K) for which 0x4fbc60 holds (no non-unit order at the head of its
## list; mines of other owners within 32 cells, level digits adding up to more than 0) and that is not converting already
## (0x52fc00) cancels its job (0x52d7e0) and starts a Keep conversion (0x52f9b0: 32 cells, 120 s for a computer player).
## This is the "hero revival" of AI_RESEARCH.md 5.5; no hero is revived in skirmish.
func keep_conversion():
	for u in world.units:            # the object list: a dying hero counts until its corpse is removed
		if u.owner_id == me and not u.removed and world.can_convert(u): return
	for b in world.production.buildings.values():
		if int(b.owner) != me or not MatchConversion.is_keep(String(b.original_type_id)) or b.keep_converting: continue
		if not world.ai_keep_has_mines(b, me): continue
		if b.has_job(): world.production.cancel_all(b.entity_id)
		if world.keep_convert(b):
			stats.keep_conversions += 1
			log.append({"t": now(), "keep_conversion": b.entity_id})

# ============================================================================================ monster mode
## SKIRMISH_RESEARCH.md "Victory options and the computer player". 0x4fa120 for a Rampant player (difficulty 7; Pitched
## Battle and No Building make every computer Rampant, 0x4eaca0 / 0x4de740): the economy (base points, census, desired
## counts, the want list) and the army (0x4f5610) are skipped, 0x4fa990 picks three targets among the main enemy's objects
## after the hero's retreat, and 0x4fa850 sends every idle unit at one of them after the abilities; no resign check (Read,
## the order; the two routines Emulated: tests/monster_ai_fixtures.json). 0x4f9f80, 0x4fe180, 0x4f8fa0 and the repairs
## 0x4fffe0 are not ported here either (as in the normal branch).
func monster_think(now_ms: int):
	if first_pass:
		first_pass = false
		home = world.skirmish.slots[me].start
	building_stopped = false
	refresh_cheats()
	choose_main_enemy()
	hero_retreat()
	monster_choose_targets()
	base_defence()
	advance_tasks(now_ms)
	recount()
	if next_pace_ms == 0 or next_pace_ms < now_ms:
		next_pace_ms = now_ms + PACE_MS
		pace()
		keep_conversion()
	give_tasks(now_ms)
	if abilities != null: abilities.tick(now_ms)
	monster_attack()

## The main enemy's object list in the shape of AiRules.monster_score: its units (dead or inside a building: state 8;
## +0x30 = flag_30), its buildings (no hit points left: state 8) and the mines it owns. The original walks the list
## 0xafd4cc + 4 + player * 4; the port's order (units, buildings, mines) decides ties (Open).
func monster_objects(p: int) -> Array:
	var out: Array = []
	if p < 0: return out
	for f in world.combat.fighters.values():
		if int(f.owner) != p: continue
		var u = world.unit_by_id(int(f.id))
		if u == null or u.removed: continue
		out.append({"kind": 0, "target": "unit", "id": int(f.id), "code": String(f.type_id), "cell": world.combat.unit_cell(f.id),
			"state": 8 if not world.combat.alive(f) or u.dying or u.inside_building else 0, "hidden": bool(f.get("flag_30", false)),
			"movement": int(f.stats.get("movement", 0))})
	for b in world.production.buildings.values():
		if int(b.owner) != p: continue
		out.append({"kind": 1, "target": "building", "id": int(b.entity_id), "code": String(b.original_type_id),
			"cell": Vector2i(b.left, b.top), "state": 8 if b.hit_points <= 0 else 0})
	for id in world.mines.mines:
		var m: Dictionary = world.mines.mines[id]
		if int(m.entity.owner) != p: continue
		out.append({"kind": 1, "target": "mine", "id": int(id), "code": String(m.code), "cell": m.anchor, "state": 0})
	return out

## 0x4fa990 (Emulated). The strength term reads the 0x5095a0 grid's block 0 for every object (see AiRules.monster_score);
## the grid is not ported (Open), so it is taken as 0 (term 70): one constant for the whole pass, the choice is the same.
func monster_choose_targets():
	var objects := monster_objects(main_enemy)
	var option := int(world.skirmish.options.get("victory", 0))
	var picks: Array = R.monster_targets(objects, main_enemy, [home.x, home.y], int(world.collision.height), option, 0)
	for slot in R.MONSTER_SLOTS:
		var i: int = picks[slot]
		monster_slots[slot] = {} if i < 0 else {"kind": String(objects[i].target), "id": int(objects[i].id)}

## 0x4fa850 (Emulated): every idle unit (state 3: alive, no order, not busy, not inside a building) is sent with the
## player-level attack order 0x51da60(target, -1, 0...) at slot 0 or 1 by its ARM +0x100 layers. A mine target is a valid
## order in the original (0x51da60 accepts any kind-1 object); the port's combat has no mine targets, so it is refused.
func monster_attack():
	var has0: bool = not monster_slots[0].is_empty()
	var has1: bool = not monster_slots[1].is_empty()
	if not has0 and not has1: return
	for u in my_units():
		var f = fighter(u)
		if f == null or not world.combat.alive(f) or f.order != null or u.inside_building or world.unit_busy(u): continue
		var slot := R.monster_attack_slot(int(f.stats.get("layers", 3)), has0, has1, func(): return roll(1, 2, -1))
		if slot < 0: continue
		var t: Dictionary = monster_slots[slot]
		if world.combat.order_attack(u.unit_id, String(t.kind), int(t.id), false): stats.attacks += 1

# ============================================================================================ summary
func summary() -> Dictionary:
	var counts := {}
	for u in my_units(): counts[u.type_id] = int(counts.get(u.type_id, 0)) + 1
	var built := {}
	for b in world.production.buildings.values():
		if int(b.owner) == me:
			var key: String = b.original_type_id + ("*" if b.constructing else "")
			built[key] = int(built.get(key, 0)) + 1
	var mine_count := 0
	var workers := 0
	for row in world.mines.census(me):
		if row.owned:
			mine_count += 1
			workers += int(row.workers)
	return {"player": me, "difficulty": R.NAMES[difficulty], "units": counts, "buildings": built, "resources": world.economy.resources(me),
		"mines": mine_count, "workers": workers, "groups": groups.map(func(g): return [g.kind, g.members.size(), g.launched]),
		"main_enemy": main_enemy, "hero": hero_unit() != null, "kills": int(world.combat.kills.get(me, 0)), "stats": stats.duplicate(),
		"race": race, "casts": abilities.casts.duplicate() if abilities != null else {}, "advanced": advanced.duplicate(),
		"hero_casts": abilities.hero_casts.duplicate() if abilities != null else {},
		"hero_drinks": abilities.hero_drinks.duplicate() if abilities != null else {}}

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the player's lists, tasks, groups and timers (the caches too: they decide the next pass), with its
## abilities; the world link is the scene's.
func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, ["world", "abilities", "_danger", "_type_rows", "_cfg_rows"])
	s["abilities"] = abilities.save_state(refs) if abilities != null else {}
	return s

func load_state(state: Dictionary, refs) -> void:
	preload("res://simulation/save_game.gd").restore(self, state, ["world", "abilities", "_danger", "_type_rows", "_cfg_rows"])
	if abilities != null and not state.abilities.is_empty(): abilities.load_state(state.abilities, refs)
