extends "res://tests/test_ai_batch2.gd"
## B5-3 (BATCH5_RESEARCH.md section 4): the computer player of the Fey, Ssrathi and Plaguelords on the hero spells' stand-alone
## combat world:
## 1. the lists 0x4fcfa0 / 0x4fd060 / 0x4fd140 against tests/batch5_fixtures.json `lists` (E15);
## 2. the research choice 0x4fead0 against `research_choice` (E16);
## 3. the ability pass 0x500830 against `ai_abilities` (E17 / E18: 249 rows through the real dispatch, computer and local owner,
##    rolls 1 and 2): the spell reached, the mana left, the radius; the halls' and temples' rows: the power, its payment, Rites;
## 4. the scan flag +0x31 of the casters.

class StageWorld extends AbilityWorld:
	var day_night = null
	var economy = null

const DayNight = preload("res://simulation/day_night.gd")

## tools/emulate_batch5.py AI_SCENES: the caster's [hit points (-1 full), [mana, maximum]].
const CASTERS := {
	"scare weight 3": [-1, [40, 50]], "scare weight 2": [-1, [40, 50]], "scare weight 2 hurt": [39, [40, 50]], "scare weight 1 hurt": [39, [40, 50]],
	"scare undead": [-1, [40, 50]], "scare building": [-1, [40, 50]], "scare at 7": [-1, [40, 50]], "scare at 8": [-1, [40, 50]],
	"scare below mana": [-1, [39, 50]],
	"cloud AMIX and AHIX": [-1, [55, 60]], "cloud AMIX": [-1, [55, 60]], "cloud at 4": [-1, [55, 60]], "cloud at 5": [-1, [55, 60]],
	"cloud three AMIX, three AHIX": [-1, [55, 60]], "cloud weight 1 hurt": [39, [55, 60]], "cloud weight 2 hurt": [39, [55, 60]],
	"cloud below mana": [-1, [54, 60]], "eye early": [-1, [30, 60]], "eye at 10 min": [-1, [30, 60]], "eye after 10 min": [-1, [30, 60]],
	"eye below mana": [-1, [29, 60]],
	"cauterize two hurt": [-1, [30, 40]], "cauterize two hurt big": [-1, [30, 40]], "cauterize one hurt big": [-1, [30, 40]],
	"cauterize one hurt big, self hurt": [5, [30, 40]], "cauterize one hurt": [-1, [30, 40]], "cauterize self hurt": [5, [30, 40]],
	"cauterize unhurt": [-1, [30, 40]], "cauterize below mana": [-1, [29, 40]],
	"poison cloud weight 8": [-1, [25, 40]], "poison cloud weight 6": [-1, [25, 40]], "poison cloud weight 6 hurt": [39, [25, 40]],
	"poison cloud weight 1 hurt": [39, [25, 40]], "poison cloud below mana": [-1, [24, 40]],
	"naga": [-1, [40, 45]], "chameleon": [-1, [40, 40]], "chameleon with Blending": [-1, [40, 40]], "unicorn heal": [-1, [40, 40]],
	"archon none": [-1, [40, 40]], "zombie": [-1, []], "no case": [-1, []], "margin AGGX": [-1, [30, 60]]}
const CLOCKS := {"eye early": 50000, "eye at 10 min": 600000, "eye after 10 min": 600001}
## BUILDING_SCENES: [race, research, stock, the building's hit points].
const BUILDINGS := {
	"hall three AHIX": [15, ["PCN0"], [0, 0, 1000, 0], 500], "hall two AHIX": [15, ["PCN0"], [0, 0, 1000, 0], 500],
	"hall one ALDX": [15, ["PCN0"], [0, 0, 1000, 0], 500], "hall at 13": [15, ["PCN0"], [0, 0, 1000, 0], 500],
	"hall one, hurt": [15, ["PCN0"], [0, 0, 1000, 0], 99], "hall one, at 100": [15, ["PCN0"], [0, 0, 1000, 0], 100],
	"hall poor": [15, ["PCN0"], [0, 0, 999, 0], 500], "hall no research": [15, [], [0, 0, 1000, 0], 500],
	"hall level 4": [15, ["PCN0", "PCN1", "PCN2", "PCN3"], [0, 0, 1000, 0], 500], "hall none": [15, ["PCN0"], [0, 0, 1000, 0], 500],
	"temple three AHIX": [13, ["PCWR"], [750, 0, 0, 0], 500], "temple two AHIX": [13, ["PCWR"], [750, 0, 0, 0], 500],
	"temple one ALDX": [13, ["PCWR"], [750, 0, 0, 0], 500], "temple one AHIX, one ALDX": [13, ["PCWR"], [750, 0, 0, 0], 500],
	"temple one, hurt": [13, ["PCWR"], [750, 0, 0, 0], 99], "temple poor": [13, ["PCWR"], [749, 0, 0, 0], 500],
	"temple no research": [13, [], [750, 0, 0, 0], 500], "temple rites by night": [13, ["PROD"], [5000, 5000, 5000, 5000], 500],
	"temple rites by day": [13, ["PROD"], [5000, 5000, 5000, 5000], 500],
	"temple wrath and rites by night": [13, ["PCWR", "PROD"], [5000, 5000, 5000, 5000], 99],
	"hall rites by night": [15, ["PROD"], [5000, 5000, 5000, 5000], 500], "temple at 13": [13, ["PCWR"], [750, 0, 0, 0], 500]}
const SPELL_NAMES := {"Chaos Plague": "Chaos Plague", "Couatl's Wrath": "Couatl's Wrath"}

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch5_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	# E20 / review V5 (decision 6): the original lists Ssrathi PCON twice (Building.cfg's two DEPENDENCIES rows), the port once; the
	# two entries always move together, so the original's list is compared with its second PCON taken out.
	var ss: Array = fixtures.lists["13"].research
	check(ss.count("PCON") == 2, "the original lists PCON twice")
	ss.remove_at(ss.rfind("PCON"))
	lists(fixtures.lists)
	for race in fixtures.research_choice: research(int(race), fixtures.research_choice[race])
	for row in fixtures.ai_abilities:
		if row.has("building"): building_row_b5(row)
		else: ability_row_b5(row)
	for code in ["AFGX", "AGGX", "ALMX", "AEDX", "AAAR", "ALGX"]: check(Abilities.ai_flag(code), "%s has the scan flag (Army.cfg AI column)" % code)
	clear_world()
	if failures > 0:
		printerr("AI batch 5 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI batch 5 checks passed: %d checks over %d fixture cases (%d sweep rows with a broken hall chain not compared)" % [checks, fixture_cases, hole_cases])
	quit(0)

func stage_for(row: Dictionary) -> FakeAi:
	new_world()
	var ai := FakeAi.new()
	var stage := StageWorld.new()
	stage.combat = world.combat
	stage.production = world.production
	stage.units = world.units
	stage.economy = world.economy
	ai.world = stage
	ai.face = int(row.roll)
	return ai

func ability_row_b5(row: Dictionary):
	fixture_cases += 1
	var ai := stage_for(row)
	var scene_name := String(row.scene)
	var c: Array = CASTERS.get(scene_name, [-1, []])
	if scene_name == "chameleon with Blending": world.production.research[OWNER] = ["PBLE"]
	now_at(int(CLOCKS.get(scene_name, 50000)))
	var id := unit(String(row.caster), Vector2i.ZERO, OWNER)
	var f = world.combat.fighters[id]
	if int(c[0]) >= 0:
		f.hp = int(c[0])
		world.units[id].hp = f.hp
	if not Array(c[1]).is_empty():
		f["mana"] = int(c[1][0])
		f["max_mana"] = int(c[1][1])
		f["mana_ms"] = 0
	set_command(OWNER, used(OWNER) + int(row.command[1]) - int(row.command[0]))
	var placed := 0
	for other in row.others:
		var code := String(other[0])
		var owner: int = OWNER if int(other[1]) == 1 else ENEMY
		if code[0] == "B":
			var b = world.production.buildings[building(code, Vector2i(int(other[2]), 0), owner, {})]
			b.max_hit_points = 500
			b.hit_points = int(other[3]) if other[3] != null else 500
		else:
			var other_id := unit(code, Vector2i(int(other[2]), placed % 2), owner)
			if other[3] != null:
				world.combat.fighters[other_id].hp = int(other[3])
				world.units[other_id].hp = int(other[3])
		placed += 1
	var abilities = Abilities.new(ai)
	var label := "%s, %s, roll %d" % [scene_name, "local" if row.local else "computer", int(row.roll)]
	abilities.helper(ai, f, bool(row.local))
	var got: Array = abilities.log.map(func(e): return String(e.cast))
	var want: Array = row.casts.map(func(x): return String(x.spell))
	check(got == want, "%s: port %s, original %s" % [label, got, want])
	check(int(f.get("mana", 0)) == int(row.mana_after), "%s: mana %d, original %d" % [label, int(f.get("mana", 0)), int(row.mana_after)])
	check(abilities._radius == int(row.radius), "%s: radius" % label)

func now_at(ms: int):
	world.ms = ms
	world.combat.next_update_ms = ms + 25
	world.combat.now_ms = ms

func building_row_b5(row: Dictionary):
	fixture_cases += 1
	var ai := stage_for(row)
	var scene_name := String(row.scene)
	var s: Array = BUILDINGS[scene_name]
	world.production.races[OWNER] = int(s[0])
	world.production.research[OWNER] = Array(s[1]).duplicate()
	for lane in 4: world.economy.stockpiles[OWNER][lane] = int(s[2][lane])
	var stage = ai.world
	if scene_name.contains("night") or scene_name.contains("by day"):
		var dn := DayNight.new(true)
		if scene_name.contains("night"):
			dn.hour = dn.NIGHT_CLOCK[0]; dn.mark_a = dn.NIGHT_CLOCK[1]; dn.mark_b = dn.NIGHT_CLOCK[2]
		stage.day_night = dn
	var bid := building(String(row.building), Vector2i.ZERO, OWNER, {})
	var b = world.production.buildings[bid]
	b.max_hit_points = 500
	b.hit_points = int(s[3])
	world.combat.ai_players[OWNER] = true
	var i := 0
	for other in row.get("others", []) if row.has("others") else []:
		unit(String(other[0]), Vector2i(int(other[2]), i % 8), ENEMY)
		i += 1
	var others: Array = _scene_others(scene_name)
	if not row.has("others"):
		for o in others:
			unit(String(o[0]), Vector2i(int(o[1]), i % 8), ENEMY)
			i += 1
	now_at(50000)
	var casts: Array = []
	world.spells.cast_done.connect(func(info): casts.append(info))
	var before: Array = world.economy.stockpiles[OWNER].duplicate()
	var rites_before = stage.day_night.hour if stage.day_night != null else null
	var abilities = Abilities.new(ai)
	abilities._local = bool(row.local)
	var label := "%s, %s, roll %d" % [scene_name, "local" if row.local else "computer", int(row.roll)]
	var acted: bool = abilities._building(ai, b) if not bool(row.local) else false
	var want_power: Array = row.casts.filter(func(x): return SPELL_NAMES.has(String(x)))
	var got_power: Array = abilities.log.map(func(e): return String(e.cast)).filter(func(x): return SPELL_NAMES.has(x))
	if not bool(row.local):
		check(got_power == want_power, "%s: port %s, original %s" % [label, got_power, row.casts])
		var paid: Array = row.messages.filter(func(m): return m.message == "0x1fe")
		var spent := [int(before[0]) - int(world.economy.stockpiles[OWNER][0]), int(before[2]) - int(world.economy.stockpiles[OWNER][2])]
		var want_spent := [0, 0]
		if not paid.is_empty(): want_spent = [mini(int(before[0]), int(paid[0].payment.words[0])), mini(int(before[2]), int(paid[0].payment.words[3]))]
		check(spent == want_spent, "%s: paid %s, the original %s" % [label, spent, want_spent])
		var rites_want: bool = row.messages.any(func(m): return m.message == "0x1f7") and want_power.is_empty()
		var rites_got: bool = abilities.log.any(func(e): return String(e.cast) == "Rites of Dawn")
		check(rites_got == rites_want, "%s: Rites of Dawn %s, the original %s" % [label, rites_got, rites_want])
	else:
		check(row.casts.is_empty() and row.messages.is_empty(), "%s: the local player's hall / temple does nothing (0x500830)" % label)

## The enemies of BUILDING_SCENES (the rows do not list them): [type, gap].
func _scene_others(scene_name: String) -> Array:
	match scene_name:
		"hall three AHIX", "hall at 13", "hall poor", "hall no research", "hall level 4", "temple three AHIX", "temple poor", "temple no research", "temple at 13":
			var gap := 13 if scene_name.ends_with("at 13") else 12
			return [["AHIX", gap], ["AHIX", gap], ["AHIX", gap]]
		"hall two AHIX", "temple two AHIX": return [["AHIX", 12], ["AHIX", 12]]
		"hall one ALDX", "temple one ALDX": return [["ALDX", 12]]
		"temple one AHIX, one ALDX": return [["AHIX", 11], ["ALDX", 12]]
		"hall one, hurt", "hall one, at 100", "temple one, hurt", "temple wrath and rites by night": return [["ACSH", 5]]
	return []
