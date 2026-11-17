extends "res://tests/test_ai_batch2.gd"
## B3-3 (BATCH3_RESEARCH.md section 4): the computer player of Orcs, Dark Dwarves and Daemons on the hero spells' stand-alone
## combat world:
## 1. the lists 0x4fcfa0 / 0x4fd060 / 0x4fd140 against tests/batch3_fixtures.json `lists` (E1);
## 2. the research choice 0x4fead0 against `research_choice` (E2: named states and sweep cases per race);
## 3. the ability pass 0x500830 against `ai_abilities` (E19: 152 rows, real dispatch, computer and local owner, rolls 1 and 2):
##    the spell reached, its level, the mana left, the radius;
## 4. R9: 0x4fc9a0 charges the Wraith and the Shadow to BAGR, so they add nothing to the Ancestral Hall's share;
## 5. the scan flag +0x31 of the casters.

class DayWorld extends AbilityWorld:
	var day_night = null

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch3_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	lists(fixtures.lists)
	for race in fixtures.research_choice: research(int(race), fixtures.research_choice[race])
	for row in fixtures.ai_abilities: ability_row_b3(row)
	share()
	for code in ["AONX", "AOKX", "AAJX", "AVGX", "AABX", "AAGX"]: check(Abilities.ai_flag(code), "%s has the scan flag (Army.cfg AI column)" % code)
	clear_world()
	if failures > 0:
		printerr("AI batch 3 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI batch 3 checks passed: %d checks over %d fixture cases (%d sweep rows with a broken hall chain not compared)" % [checks, fixture_cases, hole_cases])
	quit(0)

## The batch-3 sweep owns leveled buildings with gaps in other chains than the hall's too (BAE2 without BAE1, BAS2 without BAS0,
## BWL1 without BWL0): a match cannot, and the port's Rules.satisfies counts a higher level for a lower one. Any such gap marks
## the row as test_ai_batch2.gd's hall hole.
func hall_hole(owned: Array) -> bool:
	var chains := {}
	for code in owned:
		var s := String(code)
		if s.length() == 4 and s[3] >= "0" and s[3] <= "9":
			var key := s.substr(0, 3)
			if not chains.has(key): chains[key] = []
			chains[key].append(int(s.right(1)))
	for key in chains:
		var levels: Array = chains[key]
		if levels.size() != int(levels.max()) + 1: return true
	return false

## The caster of tools/emulate_batch3.py AI_SCENES: [hit points (0 = full), mana, maximum].
func caster_b3(scene_name: String) -> Array:
	var hp := 0
	if scene_name.ends_with(" hurt") and scene_name.begins_with("lightning") or scene_name == "banish small daemon hurt": hp = 30
	if scene_name == "lightning weight 1 at 39": hp = 39
	if scene_name == "lightning weight 1 at 40": hp = 40
	var mana := {"lightning below mana": [39, 50], "shaman berserker": [25, 50], "shaman berserker alone": [25, 50], "darkness below mana": [49, 50],
		"chief": [75, 80], "chief below mana": [74, 80], "iron golem": [35, 40], "iron golem below mana": [34, 40], "summoner": [100, 100],
		"summoner below mana": [99, 100], "banish below mana": [29, 100], "earthpower below mana": [39, 40]}
	var m: Array = mana.get(scene_name, [])
	if m.is_empty():
		if scene_name.begins_with("banish"): m = [30, 100]
		elif scene_name.begins_with("earthpower"): m = [40, 40]
		elif scene_name.begins_with("salvage"): m = [0, 0]
		elif scene_name.begins_with("margin"): m = {"AVGX": [100, 100], "AOKX": [75, 80], "AAJX": [35, 40], "AADE": [40, 40]}.get(scene_name.right(4), [200, 200])
		else: m = [50, 50]
	return [hp, int(m[0]), int(m[1])]

func ability_row_b3(row: Dictionary):
	fixture_cases += 1
	new_world()
	var ai := FakeAi.new()
	var stage := DayWorld.new()
	stage.combat = world.combat
	stage.production = world.production
	stage.units = world.units
	ai.world = stage
	ai.face = int(row.roll)
	var scene_name := String(row.scene)
	if scene_name.begins_with("darkness"):
		var dn := preload("res://simulation/day_night.gd").new(true)
		if scene_name.contains("night"):
			dn.hour = dn.NIGHT_CLOCK[0]; dn.mark_a = dn.NIGHT_CLOCK[1]; dn.mark_b = dn.NIGHT_CLOCK[2]
		stage.day_night = dn
	var c: Array = caster_b3(scene_name)
	var id := unit(String(row.caster), Vector2i.ZERO, OWNER)
	var f = world.combat.fighters[id]
	if int(c[0]) > 0:
		f.hp = int(c[0])
		world.units[id].hp = f.hp
	if int(c[2]) > 0 or String(row.caster) != "AAGX":
		f["mana"] = int(c[1])
		f["max_mana"] = int(c[2])
		f["mana_ms"] = 0
	set_command(OWNER, used(OWNER) + int(row.command[1]) - int(row.command[0]))
	for other in row.others:
		var code := String(other[0])
		if code[0] == "E":
			world.combat.debris.append(centre + Vector2i(int(other[1]), 0))
			continue
		var owner: int = OWNER if int(other[1]) == 1 else ENEMY
		if code[0] == "B":
			var b = world.production.buildings[building(code, Vector2i(int(other[2]), 0), owner, {})]
			b.max_hit_points = 500                               # the harness's maximum (0x52ae00 = 500)
			b.hit_points = int(other[3]) if other[3] != null else 500
			continue
		var other_id := unit(code, Vector2i(int(other[2]), 0), owner)
		if other[3] != null:
			world.combat.fighters[other_id].hp = int(other[3])
			world.units[other_id].hp = int(other[3])
	var abilities = Abilities.new(ai)
	var label := "%s, %s, roll %d" % [scene_name, "local" if row.local else "computer", int(row.roll)]
	abilities.helper(ai, f, bool(row.local))
	var got: Array = abilities.log.map(func(e): return String(e.cast))
	var want: Array = row.casts.map(func(x): return String(x.spell))
	# The harness records the batch-3 spells only: its AADE rows pay the 40 mana of Summon Imp with no entry (compared by mana).
	if String(row.caster) != "AADE": check(got == want, "%s: port %s, original %s" % [label, got, want])
	for x in row.casts: check(int(x.level) == abilities._level(f), "%s: level" % label)
	var mana: int = int(f.get("mana", 0))
	check(mana == int(row.mana_after), "%s: mana %d, original %d" % [label, mana, int(row.mana_after)])
	check(abilities._radius == int(row.radius), "%s: radius" % label)

## R9 (Read, decompile 166812): the Wraith's and the Shadow's priorities count for BAGR, not BPAH; another unit at BPAH still counts.
func share():
	var rules := ProductionRules.new()
	var table: Dictionary = rules.production_table(10)
	var buildings := [["BPAH", 1, 1], ["BAGU", 1, 1]]
	var with_spirits: Array = R.desired_counts(5, buildings, [["AUKX", 50, 1], ["AUXX", 50, 1], ["AABX", 50, 1]], -1, table)
	var without: Array = R.desired_counts(5, buildings, [["AABX", 50, 1]], -1, table)
	check(with_spirits == without, "the Wraith and the Shadow add nothing to the Ancestral Hall's share: %s / %s" % [with_spirits, without])
	check(R.SHARE_TO_BAGR.has("AUKX") and R.SHARE_TO_BAGR.has("AUXX") and R.SHARE_TO_BAGR.size() == 6, "the six types of 0x4fc9a0")
