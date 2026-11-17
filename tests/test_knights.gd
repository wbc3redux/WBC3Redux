extends SceneTree
## Milestone 13 (PRODUCTION_RESEARCH.md, "Milestone 13"): the Knights faction against the emulated original
## (tests/knights_fixtures.json, tools/emulate_knights.py) and the data:
## * the research completion table 0x436500 shipped as simulation/research_effects.json equals the emulation, id by id;
## * ResearchEffects.apply reproduces the unit getters 0x526310 / 0x5260a0 / 0x51bd10 / 0x51c460 / 0x526b70 for every
##   Knights unit type and 16 research sets;
## * the whole Knights roster (CONSTRUCTION H0 / H1, every PRODUCTION slot, the dependency rows) has a definition or a
##   research price, its price equals the emulated 0x40b6b0 / 0x4391c0 results, and its tier is the Keep that unlocks it;
## * the swing multipliers, attack layers, flights, Income research, the Market trade and the Knight's Quest list.
const Rules = preload("res://simulation/production_rules.gd")
const ResearchEffects = preload("res://simulation/research_effects.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const Market = preload("res://simulation/market.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const KNIGHTS := ["BKK0", "BKK1", "BKK2", "BKK3", "BKK4", "BAGA", "BPSM", "BPSB", "BPFL", "BPMA", "BAV0", "BAV1", "BAV2", "BPSS",
	"BPCA", "BWTC", "BWG0", "BWG1", "BWG2", "BWRA"]
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 400 and not label.ends_with("Help.cfg name"): printerr("Knights check failed: ", label)

func load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func ints(a: Array) -> Array:
	return a.map(func(v): return int(v))

func _initialize():
	var rules = Rules.new()
	var fixtures: Dictionary = load_json("res://tests/knights_fixtures.json")
	var effects = ResearchEffects.new()
	_completion(effects, fixtures)
	_getters(rules, effects, fixtures)
	_roster(rules)
	_multipliers()
	_flight()
	_income()
	_market()
	if failures == 0: print("Knights checks passed: ", checks)
	else: printerr("Knights checks failed: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)

## The shipped table equals the emulated completions (upgrade bytes per type, flags, listing) for every research id.
func _completion(effects, fixtures: Dictionary):
	var seen := 0
	for id in fixtures.completion:
		var row: Dictionary = fixtures.completion[id]
		if row.has("error"): continue
		seen += 1
		for type in row.upgrades:
			check(ints(effects.upgrades([id], type)) == ints(row.upgrades[type]), "upgrades %s %s" % [id, type])
		check(effects.listed(id) == bool(row.listed), "listed %s" % id)
		for f in row.flags:
			check(effects.flag([id], String(f[0]).hex_to_int() - 1), "flag %s %s" % [id, f[0]])
	check(seen > 250, "every research id emulated (%d)" % seen)
	# Spot values read from Help.cfg and the decompile, confirmed by the emulation.
	check(ints(effects.upgrades(["PWAR"], "AHFX")) == [2, 0, 0, 0, 0, 0], "Warhorse: +2 combat for the Knight")
	check(ints(effects.upgrades(["POPE"], "AHEX")) == [0, 0, 3, 0, 0, 0], "Order of the Pegasus: +3 speed (Help.cfg says +2)")
	check(ints(effects.upgrades(["PWE0", "PWE1"], "AHKX")) == [0, 0, 0, 10, 0, 0], "Weaponsmith I+II: +10 melee damage")
	check(ints(effects.upgrades(["PWE0"], "AHMX")) == [0, 0, 0, 0, 0, 0], "Weaponsmith skips missile units")
	check(ints(effects.upgrades(["PBOW"], "AHMX")) == [0, 0, 0, 0, 2, 0], "Bowyer: +2 range")
	check(effects.flag(["PPAL"], ResearchEffects.PPAL_FLAG) and effects.flag(["PGRA"], ResearchEffects.PGRA_FLAG), "Paladin / Grand Paladin flags")
	check(not effects.listed("PQKN"), "Knight's Quest is not listed without three choices")

## ResearchEffects.apply against the getters, for every case of the fixture.
func _getters(rules, effects, fixtures: Dictionary):
	for c in fixtures.unit_stats:
		var type := String(c.unit)
		var base: Dictionary = CombatRules.unit_stats(String(rules.definition(type).raw_hex))
		var s: Dictionary = effects.apply(base, type, c.research, Rules.KNIGHT, rules.status_bits(type), false)
		var label := "%s %s" % [type, ",".join(c.research)]
		check([int(s.dmg), int(s.dtype), int(s.range)] == ints(c.attack), label + " attack block (0x526310)")
		check(int(s.armour) == int(c.armour[0]), label + " armour (0x5260a0)")
		check(int(s.combat) == int(c.combat), label + " combat (0x51bd10)")
		check(int(s.speed) == int(c.speed), label + " speed (0x51c460)")
		check(int(s.mres) == int(c.mres), label + " magic armour (0x526b70)")
	check(fixtures.unit_stats.size() == 16 * 16, "16 types x 16 research sets")

## Every Knights item reachable from the construction rows and the production rows of the Knights buildings.
func _roster(rules):
	var race := Rules.KNIGHT
	var prices: Dictionary = load_json("res://tests/races_fixtures.json")
	var emulated := {}
	for row in prices.cost_0x40b6b0:
		if int(row.race) == race: emulated[String(row.item)] = row
	var items := {}
	for row in [rules.construction_menu(race, 0), rules.construction_menu(race, 1)]:
		for id in row: items[id] = true
	check(rules.construction_menu(race, 0) == ["BKK0", "BAGA", "BPSM", "BPSB", "BPFL", "BPMA", "BAV0", "BPSS", "BPCA"], "construction row H0")
	check(rules.construction_menu(race, 1) == ["BWTC", "BWG0", "BWG1", "BWG2", "BWRA"], "construction row H1 (towers, walls)")
	for b in KNIGHTS:
		items[b] = true
		for slot in rules.production_slots(b, race):
			if slot.id != null: items[String(slot.id)] = true
	var units := 0
	var research := 0
	for id in items:
		var p: Dictionary = rules.price(id, {"race": race})
		check(bool(p.ok), "%s has a price" % id)
		if Rules.is_research(id):
			research += 1
			check(rules.research_prices.has(id), "%s in the 0x4391c0 table" % id)
			check(rules.display_name(id) != id, "%s has a Help.cfg name" % id)
		else:
			check(not rules.definition(id).is_empty(), "%s has a definition" % id)
			if id.begins_with("A"): units += 1
		if emulated.has(id):
			check(ints(p.cost) == ints(emulated[id].cost) and int(p.seconds) == int(emulated[id].seconds), "%s price equals 0x40b6b0" % id)
	check(units == 16, "Knights units trained by Knights buildings: %d" % units)
	check(research == 31, "Knights research items: %d" % research)
	# Tiers: the Keep level each unit's producer and dependencies need.
	check(rules.requirements("AHGX", race) == ["BKK4"] and rules.requirements("ATHX", race) == ["BKK4"], "Inquisitor / Sirian need Keep level 5")
	check(rules.requirements("BPCA", race) == ["BKK3"] and rules.requirements("BPSS", race) == ["BKK2"], "Cathedral L4, Shrine L3")
	check(rules.requirements("AHEX", race) == ["BPSS", "BPSM"] and rules.requirements("ASBA", race) == ["PORA"], "Knight Lord, Battering Ram")
	check(rules.menu("BKK4", race).map(func(m): return m.id) == ["AHBX", "PCR0", "PCR1", "PCR2", "PCR3", "PCR4"], "Keep level 5 menu")
	check(rules.menu("BPCA", race, {"lord_built": false}).map(func(m): return m.id).has("ATHX"), "the Sirian is the Cathedral's lord slot")

## 0x42ace0: Knight cavalry x2 (PPAL), x3 against Undead (PGRA); Archon / Inquisitor x2 against Evil; Ram x10 on buildings.
func _multipliers():
	check(CombatRules.unit_multiplier({"type_id": "AHFX", "ppal": true}, 0) == 2, "Paladin doubles the Knight")
	check(CombatRules.unit_multiplier({"type_id": "AHEX", "ppal": true, "pgra": true}, 0x4) == 3, "Grand Paladin triples against Undead")
	check(CombatRules.unit_multiplier({"type_id": "AHDX", "ppal": true, "pgra": true}, 0) == 2, "Grand Paladin: x2 against others")
	check(CombatRules.unit_multiplier({"type_id": "AHKX", "ppal": true}, 0x4) == 1, "Swordsmen gain nothing")
	check(CombatRules.unit_multiplier({"type_id": "AHFX", "ppal": true, "hero": true}, 0) == 1, "heroes take no type multiplier")
	check(CombatRules.unit_multiplier({"type_id": "AHGX"}, 0x8000000) == 2 and CombatRules.unit_multiplier({"type_id": "AAAR"}, 0x2000000) == 1, "Inquisitor / Archon x2 against Evil only")
	check(CombatRules.building_multiplier({"type_id": "ASBA"}) == 10 and CombatRules.building_multiplier({"type_id": "AHKX"}) == 1, "Battering Ram x10 on buildings")
	# 0x51da60 attack layers (ARM +0x100) against movement types (ARM +5).
	var rules = Rules.new()
	var stats := func(id): return CombatRules.unit_stats(String(rules.definition(id).raw_hex))
	check(not CombatRules.can_hit(stats.call("AHKX"), stats.call("AAPE")), "Swordsman cannot hit the Pegasus")
	check(CombatRules.can_hit(stats.call("AHMX"), stats.call("AAPE")), "Squire hits the Pegasus")
	check(not CombatRules.can_hit(stats.call("AAEG"), stats.call("AHKX")) and CombatRules.can_hit(stats.call("AAEG"), stats.call("AAPE")), "Eagle attacks flyers only")
	check(CombatRules.can_hit(stats.call("AAEG"), stats.call("AHLX")), "the Eagle treats the type-3 Dancing Sword as a flyer target")
	check(CombatRules.can_hit(stats.call("AAEG"), {"building": true}), "air-only attackers hit buildings")

## Flights equal the emulated movement-type-1 routes (0x42e180 on the second layer, races_fixtures.json).
func _flight():
	var fixtures: Dictionary = load_json("res://tests/races_fixtures.json")
	var n := 0
	for r in fixtures.routes:
		if int(r.movement_type) != 1 or int(r.extent) != 1: continue
		var line := Navigation.flight_line(Vector2i(int(r.start[0]), int(r.start[1])), Vector2i(int(r.goal[0]), int(r.goal[1])))
		var cells: Array = r.cells.map(func(c): return Vector2i(int(c[0]), int(c[1])))
		check(line == cells, "flight %s" % r.name)
		n += 1
	check(n == 5, "five emulated flights")

## 0x531f10: Income research adds 0x6115c4[level] per producing mine of a lane with income.
func _income():
	var e = Economy.new(0)
	e.add_player(0, [0, 0, 0, 0])
	var level := {"PIBX": 0}
	e.research_level = func(_p, id): return int(level.get(id, 0))
	check(Economy.INCOME_TABLE == [0, 1, 2, 4, 6, 8, 10, 12], "0x6115c4")
	var Entity = preload("res://simulation/entity_state.gd")
	for i in 2:
		var m = Entity.new(100 + i, "BRGX", 0, Vector2.ZERO, 2)
		e.register_mine(m, 0, 2, 8000)
	var plain: Array = e._calculate(0)
	level.PIBX = 3
	var richer: Array = e._calculate(0)
	check(int(richer[0]) == int(plain[0]) + 4 * 2 and int(richer[1]) == 0, "Income III: +4 gold per producing gold mine, nothing for empty lanes")

## 0x5735e0 / 0x573750: half value at rate 50, capped by the stockpile limit; the stock bounds the amount sold.
func _market():
	check(Market.rate(0) == 50 and Market.rate(60) == 90, "trade rate 50, at most 90")
	check(Market.sale([500, 0, 0, 0], [1000, 1000, 1000, 1000], 0, 1, 200, 50) == 200, "sell 200 gold")
	check(Market.sale([150, 0, 0, 0], [1000, 1000, 1000, 1000], 0, 1, 200, 50) == 150, "stock bounds the sale")
	check(Market.sale([500, 980, 0, 0], [1000, 1000, 1000, 1000], 0, 1, 200, 50) == 40, "the limit of the bought lane bounds the sale")
	var e = Economy.new(0)
	e.add_player(0, [400, 0, 0, 0])
	var done: Array = Market.trade(e, 0, 0, 2, 300, 50)            # gold -> stone (dialog lane 2 = economy lane 3)
	check(done == [300, 150] and ints(e.resources(0)) == [100, 0, 0, 150], "trade 300 gold for 150 stone")
