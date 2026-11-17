extends "res://tests/test_ai_batch3.gd"
## B4-3 (BATCH4_RESEARCH.md section 4): the computer player of High Elves, Wood Elves and Dark Elves on the hero spells' stand-alone
## combat world:
## 1. the lists 0x4fcfa0 / 0x4fd060 / 0x4fd140 against tests/batch4_fixtures.json `lists` (E16);
## 2. the research choice 0x4fead0 against `research_choice` (E17);
## 3. the ability pass 0x500830 against `ai_abilities` (E22 / E23: 232 rows, units and buildings, computer and local owner);
## 4. the Elven Peasant branch of 0x4fe830 against `peasant` (E18: 72 rows);
## 5. the computer's merge 0x4f8290 against `ai_merge` (E20);
## 6. 0x4f5700's army offer against the review's `groups` (E24) and 0x4f7d80's availability rule against `recount` (R3);
## 7. no other race's list gains a producer-less entry beyond the known ones (decision 9).

const RacePowers = preload("res://simulation/race_powers.gd")

class ElfWorld extends AbilityWorld:
	var day_night = null
	var economy = null

class MergeWorld extends RefCounted:
	var production
	var economy
	var merged: Array = []
	func has_method_merge() -> bool: return true
	func merge_group(_owner: int, ids: Array) -> int:
		merged.append(ids.duplicate())
		return 99

class MergeAi extends RefCounted:
	var me := 1
	var world
	var units: Array = []
	var busy_ids: Array = []
	var member_ids: Array = []
	func my_units() -> Array: return units
	func busy(u) -> bool: return busy_ids.has(u.unit_id)
	func _member(id: int) -> bool: return member_ids.has(id)
	func now() -> int: return 0

class Node4 extends RefCounted:
	var unit_id := 0
	var type_id := "AEBX"

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch4_fixtures.json"))
	var review: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch4_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	lists(fixtures.lists)
	for race in fixtures.research_choice: research(int(race), fixtures.research_choice[race])
	for row in fixtures.ai_abilities:
		if row.has("building"): building_row_b4(row)
		else: ability_row_b4(row)
	peasant(fixtures.peasant)
	ai_merge(fixtures.ai_merge)
	groups(review.groups)
	recount(review.recount)
	producer_less()
	for code in ["AEGX", "ASSC", "AWJX", "AWKX", "AWNX", "AENX", "AEOX", "AEDX", "AKNX", "AKOX", "AKGX"]: check(Abilities.ai_flag(code), "%s has the scan flag (Army.cfg AI column)" % code)
	clear_world()
	if failures > 0:
		printerr("AI batch 4 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI batch 4 checks passed: %d checks over %d fixture cases (%d sweep rows with a broken hall chain not compared)" % [checks, fixture_cases, hole_cases])
	quit(0)

## tools/emulate_batch4.py AI_SCENES: the caster's [hit points (0 = full), mana, maximum].
const SCENE_CASTER := {
	"volley weight 3": [0, 25, 50], "volley weight 2": [0, 25, 50], "volley weight 2 hurt": [39, 25, 50], "volley weight 1 hurt": [39, 25, 50],
	"volley weight 1 at 40": [40, 25, 50], "volley below mana": [0, 24, 50], "volley at 7": [0, 25, 50], "volley at 8": [0, 25, 50],
	"manticore volley": [0, 25, 50], "entangle weight 3": [0, 20, 50], "entangle weight 2": [0, 20, 50], "entangle weight 2 hurt": [39, 20, 50],
	"entangle weight 1 hurt": [39, 20, 50], "entangle building": [0, 20, 50], "ancient entangle": [0, 20, 50], "entangle below mana": [0, 19, 50],
	"druid lightning": [0, 50, 50], "druid darkness by day": [0, 50, 50], "druid darkness by night": [0, 50, 50],
	"ring weight 3 at 4": [0, 50, 50], "ring weight 3 at 5": [0, 50, 50], "ring weight 1 hurt": [39, 50, 50], "ring weight 2 hurt": [39, 50, 50],
	"ring below mana": [0, 49, 50], "ward friends": [0, 25, 50], "ward few friends": [0, 25, 50],
	"freeze weight 3": [0, 45, 50], "freeze below mana": [0, 44, 50], "freeze weight 1 hurt": [39, 45, 50], "ice hand": [0, 20, 50],
	"unicorn heal": [0, 40, 40], "unicorn cure none": [0, 30, 40],
	"pillar weight 2": [0, 35, 60], "pillar at 3": [0, 35, 60], "pillar weight 1": [0, 35, 60], "pillar weight 1 hurt": [49, 35, 60],
	"sorceror zombies": [0, 45, 60], "sorceror darkstorm by day": [0, 40, 60], "sorceror darkstorm by night": [0, 40, 60],
	"priestess": [0, 45, 50], "priestess below mana": [0, 44, 50], "blackguard": [0, 35, 40], "blackguard below mana": [0, 34, 40],
	"margin AKNX": [0, 45, 60], "margin AKOX": [0, 45, 50], "no case": [0, -1, -1]}

func ability_row_b4(row: Dictionary):
	fixture_cases += 1
	new_world()
	var ai := FakeAi.new()
	var stage := ElfWorld.new()
	stage.combat = world.combat
	stage.production = world.production
	stage.units = world.units
	stage.economy = world.economy
	ai.world = stage
	ai.face = int(row.roll)
	var scene_name := String(row.scene)
	if scene_name.contains("by day") or scene_name.contains("by night"):
		var dn := preload("res://simulation/day_night.gd").new(true)
		if scene_name.contains("night"):
			dn.hour = dn.NIGHT_CLOCK[0]; dn.mark_a = dn.NIGHT_CLOCK[1]; dn.mark_b = dn.NIGHT_CLOCK[2]
		stage.day_night = dn
	var c: Array = SCENE_CASTER.get(scene_name, [0, 50, 50])
	var id := unit(String(row.caster), Vector2i.ZERO, OWNER)
	var f = world.combat.fighters[id]
	if int(c[0]) > 0:
		f.hp = int(c[0])
		world.units[id].hp = f.hp
	if int(c[2]) >= 0:
		f["mana"] = int(c[1])
		f["max_mana"] = int(c[2])
		f["mana_ms"] = 0
	set_command(OWNER, used(OWNER) + int(row.command[1]) - int(row.command[0]))
	for other in row.others:
		var code := String(other[0])
		var owner: int = OWNER if int(other[1]) == 1 else ENEMY
		if code[0] == "B":
			var b = world.production.buildings[building(code, Vector2i(int(other[2]), 0), owner, {})]
			b.max_hit_points = 500
			b.hit_points = int(other[3]) if other[3] != null else 500
			continue
		var other_id := unit(code, Vector2i(int(other[2]), 0), owner)
		if other[3] != null:
			world.combat.fighters[other_id].hp = int(other[3])
			world.units[other_id].hp = int(other[3])
	var abilities = Abilities.new(ai)
	var label := "%s by %s, %s, roll %d" % [scene_name, row.caster, "local" if row.local else "computer", int(row.roll)]
	abilities.helper(ai, f, bool(row.local))
	var got: Array = abilities.log.map(func(e): return String(e.cast))
	var want: Array = row.casts.map(func(x): return String(x.spell))
	check(got == want, "%s: port %s, original %s" % [label, got, want])
	for x in row.casts: check(int(x.level) == abilities._level(f), "%s: level" % label)
	if int(c[2]) >= 0: check(int(f.get("mana", 0)) == int(row.mana_after), "%s: mana %d, original %d" % [label, int(f.get("mana", 0)), int(row.mana_after)])
	check(abilities._radius == int(row.radius), "%s: radius" % label)

## tools/emulate_batch4.py BUILDING_SCENES: [race, research, crystal, others (code, friend, gap, hp) x n, hero hp].
const BUILDING_SCENES := {
	"healer friends": [6, ["PELC"], 400, 3, true, null], "healer few": [6, ["PELC"], 400, 2, true, null],
	"healer unhurt": [6, ["PELC"], 400, 3, false, null], "healer poor": [6, ["PELC"], 399, 3, true, null],
	"healer no research": [6, [], 400, 3, true, null], "healer hero hurt": [6, ["PELC"], 400, 0, true, 5],
	"healer hero whole": [6, ["PELC"], 400, 0, true, 1000], "orb friends": [7, ["PELC"], 400, 3, true, null],
	"moon three evil": [6, ["PHOL"], 200, 3, "AUIX", 12], "moon two evil": [6, ["PHOL"], 200, 2, "AUIX", 12],
	"moon evil at 13": [6, ["PHOL"], 200, 3, "AUIX", 13], "moon good": [6, ["PHOL"], 200, 1, "AMIX", 12],
	"moon poor": [6, ["PHOL"], 199, 3, "AUIX", 12], "moon no research": [6, [], 200, 3, "AUIX", 12], "moon none": [6, ["PHOL"], 200, 0, "AUIX", 12]}

func building_row_b4(row: Dictionary):
	fixture_cases += 1
	new_world()
	var s: Array = BUILDING_SCENES[String(row.scene)]
	var ai := FakeAi.new()
	var stage := ElfWorld.new()
	stage.combat = world.combat
	stage.production = world.production
	stage.units = world.units
	stage.economy = world.economy
	ai.world = stage
	ai.face = int(row.roll)
	world.combat.ai_players[OWNER] = true
	world.production.races[OWNER] = int(s[0])
	world.production.research[OWNER] = Array(s[1]).duplicate()
	world.economy.stockpiles[OWNER] = [0, 0, int(s[2]), 0]
	var bid := building(String(row.building), Vector2i.ZERO, OWNER, {})
	var b = world.production.buildings[bid]
	b.max_hit_points = 500
	b.hit_points = 500
	var moon := String(row.scene).begins_with("moon")
	for i in int(s[3]):
		if moon:
			unit(String(s[4]), Vector2i(int(s[5]), i % 8), ENEMY)
		else:
			var u := unit("AMIX", Vector2i(30, i % 8), OWNER)
			if bool(s[4]):
				world.combat.fighters[u].hp = 5
				world.units[u].hp = 5
	if s[5] != null and not moon:
		var h := hero("AEHX", {}, OWNER, Vector2i(40, 40))
		var hf = world.combat.fighters[h]
		hf.max_hp = maxi(int(hf.max_hp), 1000)
		hf.hp = int(s[5])
	var abilities = Abilities.new(ai)
	abilities._building(ai, b)
	var got: Array = abilities.log.map(func(e): return String(e.cast))
	check(got == row.casts, "%s, roll %d: port %s, original %s" % [row.scene, int(row.roll), got, row.casts])
	if String(row.building) == "BPHE" and not got.is_empty():
		check(int(world.economy.stockpiles[OWNER][2]) == int(s[2]) - 300, "%s: a computer's Balm pays 300" % row.scene)

func peasant(rows: Array):
	for r in rows:
		fixture_cases += 1
		var got := Abilities.elven_peasant_priority(int(r.count) + int(r.pending), int(r.ancient_available) == 1)
		check(got == int(r.priority), "race %d %d + %d Wisps, AEAX %d, slots %d: %d, the original %d" % [int(r.race), int(r.count), int(r.pending), int(r.ancient_available), int(r.slots), got, int(r.priority)])

func ai_merge(rows: Array):
	for r in rows:
		fixture_cases += 1
		new_world()
		var w := MergeWorld.new()
		w.production = world.production
		w.economy = world.economy
		var ai := MergeAi.new()
		ai.world = w
		if String(r.case) != "no research": world.production.research[OWNER] = [RacePowers.MERGE_RESEARCH]
		world.economy.stockpiles[OWNER] = [0, 0, int(r.crystal), 0]
		for i in int(r.wisps):
			var n := Node4.new()
			n.unit_id = i
			ai.units.append(n)
		if String(r.case) == "moving": ai.busy_ids = [0]
		if String(r.case) == "in a group": ai.member_ids = [0]
		var abilities = Abilities.new(ai)
		var merged: bool = abilities.merge_wisps(ai)
		var joined: bool = not r.lead_members.is_empty() and r.lead_members.all(func(m): return m != null and String(m) != "")
		check(merged == joined, "%s: merged %s, the original %s" % [r.case, merged, joined])
		check(int(world.economy.stockpiles[OWNER][2]) == int(r.stock_after), "%s: %d crystal left, the original %d" % [r.case, int(world.economy.stockpiles[OWNER][2]), int(r.stock_after)])

func groups(rows: Array):
	var rules := ProductionRules.new()
	for r in rows:
		if r.get("error") != null or r.task: continue
		fixture_cases += 1
		for i in r.units.size():
			var code := String(r.units[i])
			var max_hp: int = int(r.max_hp_read[i])
			var offered: bool = r.offered.has(code) if r.units.size() > 1 else not r.offered.is_empty()
			check(int(rules.builder_power(code)) == int(r.builder_power[i]), "%s: builder power %d" % [code, int(r.builder_power[i])])
			check(Abilities.joins_army(int(r.builder_power[i]), max_hp) == offered, "%s (max %d, power %d): offered %s" % [code, max_hp, int(r.builder_power[i]), offered])

func recount(rows: Array):
	var rules := ProductionRules.new()
	for r in rows:
		fixture_cases += 1
		check(not Abilities.produced(rules, int(r.race), "AEAX") and r.aeax_producers.is_empty(), "race %d: AEAX has no [PRODUCTION] row" % int(r.race))
		check(Abilities.produced(rules, int(r.race), String(r.unit)) == not r.unit_producers.is_empty(), "race %d: %s's producers %s" % [int(r.race), r.unit, r.unit_producers])
		var have: Array = r.have
		var aeax_available := have.has("PWSP")
		check(aeax_available == (int(r.available.AEAX) == 1), "race %d with %s: AEAX available %d" % [int(r.race), have, int(r.available.AEAX)])

## Decision 9: the general rule adds a trainable node only for list entries without a [PRODUCTION] row; these are the known ones.
func producer_less():
	var rules := ProductionRules.new()
	var world_stub := FakeWorld.new()
	world_stub.production = FakeProduction.new()
	world_stub.production.rules = rules
	var found := {}
	for race in 16:
		var ai = AiPlayer.new(1, 3, world_stub, race)
		var hero_id: String = rules.hero_type(race)
		for id in ai.unit_order:
			if id != hero_id and not Abilities.produced(rules, race, id): found["%d:%s" % [race, id]] = true
		ai.dispose()
	print("producer-less list entries: %s" % [found.keys()])
	for race in [6, 7, 8]: check(found.has("%d:AEAX" % race), "race %d: AEAX is producer-less" % race)
	check(found.has("7:AAIM"), "the Wood Elves' AAIM is producer-less")
	# Known 2026-11-13: the Undead tree (B1-5's exception before), the Barbarians' AAAG (a node now listed and never trained, as the
	# Wood Elves' AAIM: the original's rule) and the Elves' AEAX. A new entry here is a list change to look at.
	var known := ["2:AUKX", "2:AUJX", "2:AUXX", "2:AULX", "2:AUMX", "2:AUAX", "3:AAAG", "6:AEAX", "7:AAIM", "7:AEAX", "8:AEAX"]
	check(found.keys().all(func(k): return known.has(k)) and found.size() == known.size(), "the producer-less list entries are the known eleven: %s" % [found.keys()])
