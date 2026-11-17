extends SceneTree
## Milestone 11a (RACES_RESEARCH.md, "Milestone 11a"): the catalogue-driven production rules of every race against the
## emulated original (tests/races_fixtures.json, tools/emulate_races.py): the cost function 0x40b6b0 for every race's
## production / construction / research items and the research-gated cases, the research price table 0x4391c0, the hero
## creation matrix; plus the Knights definitions against milestone 7's production.json and the race tables.
const Rules = preload("res://simulation/production_rules.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 40: printerr("Race rules check failed: ", label)

func load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func ints(a: Array) -> Array:
	return a.map(func(v): return int(v))

func _initialize():
	var rules = Rules.new()
	var fixtures: Dictionary = load_json("res://tests/races_fixtures.json")
	_knights_identical(rules)
	_cost_matrix(rules, fixtures)
	_research(rules, fixtures)
	_tables(rules)
	_hero_matrix(fixtures)
	if failures == 0: print("Race rules checks passed: ", checks)
	else: printerr("Race rules checks failed: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)

## Every Knights definition milestone 7 read from production.json is rebuilt identically from catalogue.json.
func _knights_identical(rules):
	var production: Dictionary = load_json("res://assets/production.json")
	for code in production.definitions:
		var old: Dictionary = production.definitions[code]
		var now: Dictionary = rules.definition(code)
		for key in old:
			var a = old[key]
			var b = now.get(key)
			if a is Array: check(b is Array and ints(a) == ints(b), "Knights %s %s" % [code, key])
			elif a is Dictionary: check(b is Dictionary and JSON.stringify(a, "", true) == JSON.stringify(b, "", true), "Knights %s %s" % [code, key])
			elif a is float or a is int: check(int(a) == int(b), "Knights %s %s" % [code, key])
			else: check(str(a) == str(b), "Knights %s %s (%s / %s)" % [code, key, a, b])
	for building in production.production:
		var old: Dictionary = production.production[building]
		var slots: Array = rules.production_slots(building, Rules.KNIGHT)
		check(slots.size() == old.slots.size(), "Knights PRODUCTION row " + building)
		for i in mini(slots.size(), old.slots.size()):
			check(str(slots[i].kind) == str(old.slots[i].kind) and slots[i].id == old.slots[i].id, "Knights slot %s %d" % [building, i])
		check(rules.requirements(building, Rules.KNIGHT) == old.requires.filter(func(r): return r != null), "Knights requirements " + building)
	for id in production.unit_dependencies:
		check(rules.requirements(id, Rules.KNIGHT) == production.unit_dependencies[id].requires.filter(func(r): return r != null), "Knights dependencies " + id)
	var h0: Array = production.construction.H0.filter(func(s): return s.id != null).map(func(s): return s.id)
	check(rules.construction_menu(Rules.KNIGHT) == h0, "Knights H0 construction row")

## 0x40b6b0 for player 0 of every race over that race's PRODUCTION and CONSTRUCTION items (no hero, no research, builder -1).
func _cost_matrix(rules, fixtures: Dictionary):
	var wrong := 0
	for c in fixtures.cost_0x40b6b0:
		var got: Dictionary = rules.price(String(c.item), {"race": int(c.race)})
		var ok: bool = bool(got.ok) == bool(c.ok) and ints(got.cost) == ints(c.cost) and int(got.seconds) == int(c.seconds)
		if not ok:
			wrong += 1
			if wrong < 10: printerr("  0x40b6b0 race %d %s: %s %d s, original %s %d s" % [int(c.race), c.item, got.cost, int(got.seconds), c.cost, int(c.seconds)])
		check(ok, "0x40b6b0 race %d %s" % [int(c.race), c.item])
	check(fixtures.cost_0x40b6b0.size() == 1069, "1,069 emulated cost cases")
	# Research-gated branches, each with and without the research in the player's completed list (0x70ae40).
	for c in fixtures.cost_research_cases:
		var without: Dictionary = rules.price(String(c.item), {"race": int(c.race), "research": []})
		var with: Dictionary = rules.price(String(c.item), {"race": int(c.race), "research": [String(c.research)]})
		check(ints(without.cost) == ints(c.without.cost) and int(without.seconds) == int(c.without.seconds), "%s without %s" % [c.item, c.research])
		check(ints(with.cost) == ints(c.with_research.cost) and int(with.seconds) == int(c.with_research.seconds), "%s with %s: %s %d" % [c.item, c.research, with.cost, int(with.seconds)])
	# Milestone 7's signature keeps working: discount and builder speed.
	check(rules.cost("AHMX", 100) == [30, 0, 0, 0] and rules.cost("AHKX", 5000) == [0, 1, 0, 0], "discount keeps at least 1")
	check(rules.time_ms("BAAR", "ADBX") == 21000 and rules.time_ms("BAAR", "AHBX") == 30000, "Dwarven Smith builds 30 s buildings in 21 s (power 13)")
	check(rules.time_ms("BAAR", "ADBX", {"research": ["PENG"]}) == 16000, "PENG takes another quarter off (21 -> 16 s)")

## The research price table 0x4391c0 shipped as simulation/research_prices.json equals the emulated table.
func _research(rules, fixtures: Dictionary):
	var listed := 0
	for r in fixtures.research_0x4391c0:
		if bool(r.untouched): continue
		listed += 1
		var got: Dictionary = rules.price(String(r.id), {"race": 0})
		var row: Dictionary = rules.research_prices.get(String(r.id), {})
		check(ints(row.get("cost", [])) == ints(r.cost) and int(row.get("seconds", -1)) == int(r.seconds), "research table " + String(r.id))
		if rules.rule(String(r.id), 0).is_empty():
			check(ints(got.cost) == ints(r.cost) and int(got.seconds) == int(r.seconds), "research price without RULES " + String(r.id))
	check(listed == 258 and rules.research_prices.size() == 258, "258 research ids")
	# 0x437f70 levels: P..X returns the highest level present.
	check(Rules.research_level(["PFM0"], "PFMX") == 1 and Rules.research_level(["PFM0", "PFM2"], "PFMX") == 3 and Rules.research_level([], "PFMX") == 0, "P..X research levels")
	check(Rules.research_level(["PENG"], "PENG") == 1 and Rules.research_level(["PENG"], "PSPP") == 0, "plain research ids")

## Building.cfg lookups per race: Dwarves.
func _tables(rules):
	var dwarf := Rules.DWARF
	check(rules.construction_menu(dwarf) == ["BKD0", "BAAR", "BPFO", "BPWS", "BPTP", "BWMO", "BPBR", "BAV0", "BPCL"], "Dwarf D0 construction row")
	check(rules.menu("BKD0", dwarf).map(func(m): return m.id) == ["BKD1", "PMSG"], "Citadel level 1 menu: upgrade and research only")
	check(rules.menu("BPFO", dwarf).map(func(m): return m.id) == ["ADBX", "ASBA", "ASCA", "ADNX", "PWE0", "PWE1", "PAR0", "PAR1", "PMIT"], "Foundry trains the Smith and the siege engines")
	check(rules.menu("BAAR", dwarf).map(func(m): return m.id) == ["ADSX", "ADIX", "ADMX", "ADJX", "ADLX"], "Armory menu")
	check(rules.menu("BAV0", dwarf).map(func(m): return m.id) == ["AAEG", "BAV1"] and rules.menu("BAV0", Rules.KNIGHT).map(func(m): return m.id) == ["AAEG", "BAV1"], "shared building rows per race")
	check(rules.requirements("BAAR", dwarf) == ["BKD0"] and rules.requirements("BPWS", dwarf) == ["BKD1"], "Dwarf building requirements")
	check(rules.requirements("ADIX", dwarf) == ["BPFO"] and rules.requirements("ADMX", dwarf) == ["BPWS"] and rules.requirements("ASBA", dwarf) == ["BPCL"], "Dwarf unit dependencies")
	check(rules.requirements("ASBA", Rules.KNIGHT) == ["PORA"], "the same unit has other dependencies for another race")
	check(rules.army_limit("BKD0") == 2 and rules.army_limit("BWMO") == 1, "Dwarf army limits")
	check(Rules.keep_level("BKD0") == 1 and Rules.keep_level("BKD1") == 2 and Rules.keep_level("BAAR") == 0, "Citadel levels")
	check(rules.is_peasant_type("ADBX") and rules.is_peasant_type("AHBX") and not rules.is_peasant_type("ADIX"), "0x4fd060 Peasant test")
	check(rules.builder_power("ADBX") == 13 and rules.builder_power("AHBX") == 10 and rules.builder_power("ADIX") == 0 and rules.builder_power("AHHX", true) == 10, "0x523e10 builder power")
	check(rules.can_mine("ADBX") and rules.can_mine("AHBX") and not rules.can_mine("AEBX") and not rules.can_mine("ADHX", true), "0x523e70 mine workers")
	check(rules.definition("ADNX").footprint == [2, 2] and int(rules.definition("ADNX").population) == 4, "the Ballista is 2x2 and costs 4 command")
	var ids: Array = rules.dependency_ids(dwarf)
	check(ids.slice(0, 3) == ["ADBX", "ADSX", "ADIX"] and ids.has("BKD0") and ids.find("BKD0") > ids.find("PSIE"), "merged dependency order (0x585ca0)")
	# 0x40c990 slot gates.
	check(rules.menu("BKD4", dwarf).map(func(m): return m.id).has("ATDX"), "lord slot (L) offered while no lord exists")
	check(not rules.menu("BKD4", dwarf, {"lord_built": true}).map(func(m): return m.id).has("ATDX"), "lord slot refused once built")
	var saved: int = rules.options.build_level
	rules.options.build_level = 2
	check(not rules.menu("BKD1", dwarf).map(func(m): return m.id).has("BKD2") and rules.menu("BKD0", dwarf).map(func(m): return m.id).has("BKD1"), "BuildLevel 2 hides digit 2")
	rules.options.build_level = saved

## The hero creation matrix shipped as simulation/hero_races.json equals the emulated one; race 0 equals hero_skills.json.
func _hero_matrix(fixtures: Dictionary):
	var table: Dictionary = load_json("res://simulation/hero_races.json")
	var skills: Dictionary = load_json("res://simulation/hero_skills.json")
	for h in fixtures.hero_creation:
		var row: Dictionary = table.creation[str(int(h.race))][int(h.class_id)]
		check(ints(row.stats) == ints(h.stats) and JSON.stringify(row.skills) == JSON.stringify(h.skills), "hero creation %d/%d" % [int(h.race), int(h.class_id)])
	for k in 28:
		var a: Dictionary = table.creation["0"][k]
		var b: Dictionary = skills.knights_creation[k]
		check(ints(a.stats) == ints(b.stats), "Knight creation class %d equals hero_skills.json" % k)
