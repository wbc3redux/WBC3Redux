extends SceneTree
## G-1 (ROADMAP.md lane R, RACE_DATA_RESEARCH.md): generic race data for all 16 races against the emulated original.
## * tests/race_data_fixtures.json (tools/emulate_race_data.py): the completion table 0x436500 for every race's research
##   equals simulation/research_effects.json; ResearchEffects reproduces the six stat getters and the four ability getters
##   for every race's roster after every research set; CombatRules.unit_stats reads the creation block 0x43bfb0 of all 199
##   ARM records; CombatRules.live_status equals 0x5273c0 for all 199 types and HERO_RACE_FLAGS for the 16 hero races;
## * tests/combat_multiplier_fixtures.json (tools/emulate_combat.py --multipliers): CombatRules.swing reproduces the attacker
##   type block of 0x42ace0 for every ARM type, single STATUS bit, hero / animal target and research flag;
## * the flag consumers (PTOR / PFAL / PCOW / PDKL, the PRA counter, PENG, PMCU) and the combat.gd hooks (drain, poison tick).
const Rules = preload("res://simulation/production_rules.gd")
const ResearchEffects = preload("res://simulation/research_effects.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const Combat = preload("res://simulation/combat.gd")
const Rng = preload("res://simulation/combat_rng.gd")
var checks := 0
var failures := 0

class FakeUnit:
	var cell := Vector2i(10, 10)
	var hp := 0
	var max_hp := 0
	var owner_id := -1
	var base_speed := 0

class FakeProduction:
	var research: Dictionary = {}
	func research_level(owner: int, id: String) -> int: return Rules.research_level(research.get(owner, []), id)
	func race_of(_owner: int) -> int: return 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 200: printerr("Race data check failed: ", label)

func load_json(path: String):
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func ints(a: Array) -> Array:
	return a.map(func(v): return int(v))

func _initialize():
	var catalogue: Dictionary = load_json("res://assets/catalogue.json")
	var fixtures: Dictionary = load_json("res://tests/race_data_fixtures.json")
	var army := {}
	for row in catalogue.army_cfg.armies:
		if not army.has(row.code): army[row.code] = int(row.status_fields.bits)
	var effects = ResearchEffects.new()
	_completion(effects, fixtures)
	_getters(effects, fixtures, catalogue, army)
	_abilities(fixtures)
	_arm_blocks(fixtures, catalogue)
	_live_status(fixtures, army)
	_multipliers(load_json("res://tests/combat_multiplier_fixtures.json"))
	_flags(effects)
	_hooks()
	if failures == 0: print("Race data checks passed: ", checks)
	else: printerr("Race data checks failed: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)

## Every race's research ids: the shipped table equals the emulated completion (upgrade bytes, flags, listing).
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
			if String(f[0]).hex_to_int() - 1 >= 0x70d57d: check(effects.flag([id], String(f[0]).hex_to_int() - 1), "flag %s %s" % [id, f[0]])
	check(seen == 257, "research ids emulated: %d" % seen)

## ResearchEffects.apply and the ability getters against 0x526310 / 0x5260a0 / 0x51bd10 / 0x51c460 / 0x526b70 / 0x51a020 /
## 0x526e70 / 0x526f40 / 0x526fe0 / 0x51c6a0, for every race, roster type and research set.
func _getters(effects, fixtures: Dictionary, catalogue: Dictionary, army: Dictionary):
	var cases := 0
	var mismatched := {}
	for race_name in fixtures.races:
		var r: Dictionary = fixtures.races[race_name]
		for c in r.unit_stats:
			var type := String(c.unit)
			var base: Dictionary = CombatRules.unit_stats(String(catalogue.units[type].raw_hex))
			var s: Dictionary = effects.apply(base, type, c.research, int(r.index), int(army.get(type, 0)), false)
			var got := {"attack": [int(s.dmg), int(s.dtype), int(s.range)], "armour": int(s.armour), "combat": int(s.combat),
				"speed": int(s.speed), "mres": int(s.mres), "sight": effects.radius_1b6(int(base.range), type, c.research),
				"poison": ResearchEffects.assassin(type, c.research, 0), "drain": ResearchEffects.drain(type, c.research),
				"wraith": ResearchEffects.kill_experience_term(type), "value_51c6a0": ResearchEffects.attack_rate(type)}
			var want := {"attack": ints(c.attack), "armour": int(c.armour[0]), "combat": int(c.combat), "speed": int(c.speed),
				"mres": int(c.mres), "sight": int(c.sight), "poison": int(c.poison), "drain": int(c.drain), "wraith": int(c.wraith),
				"value_51c6a0": int(c.value_51c6a0)}
			cases += 1
			for key in want:
				if got[key] != want[key]:
					var label := "%s %s %s %s: port %s, original %s" % [race_name, type, ",".join(c.research), key, got[key], want[key]]
					if not mismatched.has(key): mismatched[key] = 0
					mismatched[key] += 1
					check(false, label)
	check(cases == 9893, "getter cases: %d" % cases)
	if not mismatched.is_empty(): printerr("Race data getter mismatches by field: ", mismatched)

func _abilities(fixtures: Dictionary):
	for type in fixtures.ability_ranks:
		for rank in fixtures.ability_ranks[type]:
			var want: Dictionary = fixtures.ability_ranks[type][rank]
			check(ResearchEffects.assassin(type, [], int(rank)) == int(want.poison), "assassin %s rank %s" % [type, rank])
			check(ResearchEffects.drain(type, []) == int(want.drain), "drain %s" % type)
			check(ResearchEffects.kill_experience_term(type) == int(want.wraith), "kill experience term %s" % type)
			check(ResearchEffects.attack_rate(type) == int(want.value_51c6a0), "attack rate %s" % type)
	check(ResearchEffects.assassin("AKJX", ["PDAO", "PBLP"], 2) == 12, "Dark Elf assassin with PDAO and PBLP at rank 2")

## W4: the ARM combat block. 0x43bfb0 copies these ARM fields into the unit for every record and race.
func _arm_blocks(fixtures: Dictionary, catalogue: Dictionary):
	var n := 0
	for type in fixtures.arm_blocks:
		var want: Dictionary = fixtures.arm_blocks[type]
		var got: Dictionary = CombatRules.unit_stats(String(catalogue.units[type].raw_hex))
		for key in ["combat", "speed", "mres", "max_hp", "armour", "res1", "res2", "dmg", "dtype", "range"]:
			check(int(got[key]) == int(want[key]), "ARM block %s %s: port %d, 0x43bfb0 %d" % [type, key, int(got[key]), int(want[key])])
		check(int(want.hp) == int(want.max_hp), "%s starts at full hit points" % type)
		check(want.race_differs.is_empty(), "%s block is the same for every race" % type)
		n += 1
	check(n == 199, "ARM records: %d" % n)
	check(ints(ResearchEffects.PRAB_CREATED) == [int(fixtures.prab_aocx.word_ae), int(fixtures.prab_aocx.word_b0)], "PRAB AOCX words")

func _live_status(fixtures: Dictionary, army: Dictionary):
	for type in fixtures.live_status:
		var want := String(fixtures.live_status[type]).hex_to_int()
		check(CombatRules.live_status(type, int(army.get(type, 0))) == want, "0x5273c0 %s" % type)
	for race in fixtures.hero_status:
		check(HeroEffects.HERO_RACE_FLAGS[int(race)] == String(fixtures.hero_status[race]).hex_to_int(), "hero STATUS race %s" % race)

## 0x42ace0's attacker-type block: the same swing (fixed seed) for every attacker x flag set x target as the original.
func _multipliers(fixtures: Dictionary):
	var want := {}
	for row in fixtures.differing: want["%s|%s|%s" % [row.attacker, "+".join(row.flags), row.target]] = row
	var n := 0
	var differing := 0
	for type in fixtures.attackers:
		for flags in fixtures.flag_sets:
			var key_flags := "+".join(flags)
			for target in fixtures.targets:
				var expected: Dictionary = want.get("%s|%s|%s" % [type, key_flags, target], fixtures.neutral["%s|%s" % [key_flags, target]])
				var a := {"type_id": type, "owner": 0, "combat": 20, "dmg": 12, "dtype": 6, "range": 0, "armour": 0, "mres": 0, "enc": 0,
					"ppal": flags.has("PPAL"), "pgra": flags.has("PGRA"), "ptor": flags.has("PTOR"), "pfal": flags.has("PFAL"),
					"pdk_level": Rules.research_level(flags, "PDKX"), "assassin": ResearchEffects.assassin(type, [], 0)}
				var t := {"type_id": "AHKX", "owner": 1, "combat": 10, "dmg": 5, "dtype": 0, "range": 0, "armour": 0, "mres": 0, "enc": 0,
					"res1": -1, "res2": -1, "flags": 0, "pcow": flags.has("PCOW")}
				if target == "building": t = {"type_id": "BAGA", "owner": 1, "combat": 10, "mres": 0, "armour": 0, "building": true, "res1": -1, "res2": -1, "range": 0, "dmg": 0, "dtype": 0}
				elif String(target).begins_with("bit"): t.flags = 1 << int(String(target).substr(3))
				elif target == "hero": t["hero"] = true
				elif String(target).begins_with("type "): t.type_id = String(target).substr(5)
				var got: Dictionary = CombatRules.swing(a, t, Rng.new(int(fixtures.seed[0]), int(fixtures.seed[1])), 1)
				n += 1
				if want.has("%s|%s|%s" % [type, key_flags, target]): differing += 1
				check(int(got.damage) == int(expected.damage) and int(got.effect) == int(expected.effect),
					"swing %s %s vs %s: port %d/%d, original %d/%d" % [type, key_flags, target, int(got.damage), int(got.effect), int(expected.damage), int(expected.effect)])
	check(n == int(fixtures.cases) and differing == fixtures.differing.size(), "multiplier cases %d (%d differ from a Swordsman)" % [n, differing])

func _flags(effects):
	check(effects.flag(["PTOR"], ResearchEffects.PTOR_FLAG) and effects.flag(["PFAL"], ResearchEffects.PFAL_FLAG), "Torture / Fallen Knight flags")
	check(effects.flag(["PCOW"], ResearchEffects.PCOW_FLAG) and effects.flag(["PDKL"], ResearchEffects.PDKL_FLAG), "PCOW / Dark Lord flags")
	check(effects.sight_counter(["PRA0"]) == 2 and effects.sight_counter(["PRA0", "PRA1", "PRA2"]) == 4, "Eagle Eye counter +2 / +1 / +1")
	check(effects.sight_counter(["PDS0", "PDS1"]) == 4 and effects.sight_counter(["PWE0"]) == 0, "PDS0 / PDS1 counter")
	check(HeroEffects.conversion_radius({"conversion_radius": 6}, ["PDKL"]) == 14 and HeroEffects.conversion_radius({"conversion_radius": 15}, ["PDKL"]) == 19, "Dark Lord: conversion radius +8, cap 19")
	check(ResearchEffects.engineering_hit_points(400) == 500 and ResearchEffects.engineering_hit_points(1) == 1, "Engineering x125/100")
	var state := {"hp": 40, "max_hp": 40}
	CombatRules.poison_start(state, 0, 5)
	check(int(state.poison_next_ms) == 5 * 128 + 500 and int(state.poison_until_ms) == 600000, "poison start timers")
	check(CombatRules.poison_tick(state, 1140, false) == 0 and CombatRules.poison_tick(state, 1141, false) == 1 and int(state.hp) == 39, "first tick after magic armour * 128 + 500 ms")
	check(CombatRules.poison_tick(state, 2142, true) == 2 and int(state.hp) == 37, "Melkor's Curse doubles the tick")
	state.hp = 5
	check(CombatRules.poison_tick(state, 5000, false) == 0 and int(state.hp) == 5, "no tick at or below max / 8")
	check(CombatRules.poison_tick(state, 600001, false) == 0 and not bool(state.poisoned), "cured after 600 s")

## combat.gd hooks on a two-unit world: drain heals the Vampire, the swing block carries the race flags, poison ticks.
func _hooks():
	var production := FakeProduction.new()
	var combat = Combat.new(Rng.new(1, 2), null, production, [FakeUnit.new(), FakeUnit.new(), FakeUnit.new()])
	var vampire = combat.register(0, 0, "AUGX", {"combat": 5, "speed": 8, "mres": 0, "max_hp": 50, "armour": 0, "res1": -1, "res2": -1, "dmg": 10, "dtype": 6, "range": 0, "flags": 0})
	var knight = combat.register(1, 1, "AHKX", {"combat": 6, "speed": 8, "mres": 5, "max_hp": 40, "armour": 10, "res1": -1, "res2": -1, "dmg": 10, "dtype": 6, "range": 0, "flags": 0x1})
	var titan = combat.register(2, 1, "ATUX", {"combat": 6, "speed": 8, "mres": 5, "max_hp": 40, "armour": 10, "res1": -1, "res2": -1, "dmg": 10, "dtype": 6, "range": 0, "flags": 0x48448a00})
	check(int(titan.stats.flags) == 0x48448a04, "Lord Bane's live STATUS has the Undead bit")
	vampire.hp = 40
	combat.apply_damage("unit", 1, 5, 0)
	check(vampire.hp == 43 and knight.hp == 35, "Vampire drains 3 per hit")
	vampire.hp = 49
	combat.apply_damage("unit", 1, 5, 0)
	check(vampire.hp == 50, "drain stops at the maximum")
	production.research = {0: ["PTOR", "PFAL", "PDK0", "PDK1"], 1: ["PCOW"]}
	var block: Dictionary = combat.combat_block(vampire)
	check(bool(block.ptor) and bool(block.pfal) and int(block.pdk_level) == 2 and int(block.assassin) == 0, "swing flags in the combat block")
	check(bool(combat.combat_block(knight).pcow), "PCOW travels with the target's block")
	combat.set_poisoned(1, true)           # magic armour 5: first tick after 1140 ms
	combat.now_ms = 1141
	combat._poison(knight)
	check(knight.hp == 29, "a poisoned unit loses a hit point (%d)" % knight.hp)
	production.research[1] = ["PMCU"]
	combat.now_ms = 2142
	combat._poison(knight)
	check(knight.hp == 27, "Melkor's Curse (any player's): 2 per second (%d)" % knight.hp)
