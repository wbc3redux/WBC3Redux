extends "res://tests/test_hero_spells.gd"
## B2-3 (BATCH2_RESEARCH.md section 7, AI_RESEARCH.md section 19): the computer player of Empire, Barbarians and Minotaurs on
## the hero spells' stand-alone combat world:
## 1. the lists 0x4fcfa0 / 0x4fd060 / 0x4fd140 against tests/batch2_fixtures.json `lists` (E1);
## 2. the research choice 0x4fead0 with the recount 0x4f7f60 against `research_choice` (E2: 60 named states and sweep cases
##    per race): the port's eligibility (`research_eligible`, on a real Production with the race's menus) and its pick;
## 3. the ability pass 0x500830 against tests/batch2_review_fixtures.json `abilities` (R14: 120 rows, real dispatch, computer
##    and local owner, rolls 1 and 2): the spell reached, its level, the mana left, the radius;
## 4. the scan flag +0x31 of the four casters (Army.cfg's AI column), and that the pass really reaches them through
##    `tick`-side `_try`; the Shaman's Berserker reaches friends through the real applier.

const AiPlayer = preload("res://simulation/ai_player.gd")
const R = preload("res://simulation/ai_rules.gd")
const Abilities = preload("res://simulation/ai_abilities.gd")

var fixture_cases := 0
var hole_cases := 0                      # sweep states with a hall chain the rules cannot reach (see research_case)
var shared_rules
var shared_nav

class FakeWorld:
	var production
	var economy
	var mines = null
	var skirmish = null

class FakeProduction:
	var rules
	var menus := [[], []]
	func construction_menu(_owner: int, row: int = 0) -> Array: return Array(menus[row])

## What 0x500830's helpers read of a match, on the stand-alone world.
class AbilityWorld extends RefCounted:
	var combat
	var production
	var units: Array
	var skirmish := NoAllies.new()
	var catalogue_data := {}
	func unit_by_id(id: int): return units[id]

class NoAllies extends RefCounted:
	func is_allied(_a: int, _b: int) -> bool: return false

## The scripted player: every 0x458e70 of the fixture row gives `face` (the harness's `force`).
class FakeAi extends RefCounted:
	var me := 1
	var world
	var face := 1
	func roll(_count: int, _sides: int, _bonus: int = 0) -> int: return face
	func now() -> int: return 0

## test_hero_spells.gd's world without reloading the rules and the grid for each of the 600 cases.
func new_world():
	clear_world()
	if shared_rules == null:
		shared_rules = ProductionRules.new()
		shared_nav = Navigation.new(collision)
	var economy = Economy.new(0)
	for p in 2: economy.add_player(p, [5000, 5000, 5000, 5000])
	var production = Production.new(shared_rules, economy, shared_nav)
	production.players_in_match = [0, 1]
	var units: Array = []
	var combat = Combat.new(Rng.new(0x1badb002, 0x2468ace0), shared_nav, production, units)
	combat.auto_acquire = false
	var host := Host.new()
	host.test = self
	host.economy = economy
	host.day_night = FakeDayNight.new()
	host.treasures = FakeTreasures.new()
	root.add_child(host)
	world = {"nav": shared_nav, "production": production, "units": units, "combat": combat, "ms": 0, "host": host, "economy": economy}
	world["spells"] = Spells.new(combat, host)
	world["hs"] = world.spells.hero_spells
	set_command(0, 40)
	set_command(1, 40)

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch2_fixtures.json"))
	var review: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch2_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground")
	lists(fixtures.lists)
	for race in fixtures.research_choice: research(int(race), fixtures.research_choice[race])
	for row in review.abilities: ability_row(row)
	scan_flags()
	berserker_applies()
	clear_world()
	if failures > 0:
		printerr("AI batch 2 checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("AI batch 2 checks passed: %d checks over %d fixture cases (%d sweep rows with a broken hall chain not compared)" % [checks, fixture_cases, hole_cases])
	quit(0)

# ------------------------------------------------------------------------------------------------ 1. E1
func lists(rows: Dictionary):
	var world_stub := FakeWorld.new()
	world_stub.production = FakeProduction.new()
	world_stub.production.rules = ProductionRules.new()
	for race in rows:
		fixture_cases += 1
		var l: Dictionary = rows[race]
		var ai = AiPlayer.new(1, 3, world_stub, int(race))
		var hero_id: String = world_stub.production.rules.hero_type(int(race))
		check(ai.building_order == l.buildings, "race %s buildings %s, original %s" % [race, ai.building_order, l.buildings])
		check(ai.unit_order == l.units + [hero_id], "race %s units %s, original %s + the hero" % [race, ai.unit_order, l.units])
		check(ai.research_order == l.research, "race %s research %s, original %s" % [race, ai.research_order, l.research])
		check(ai.PEASANT == String(l.peasant), "race %s Peasant %s, original %s" % [race, ai.PEASANT, l.peasant])
		ai.dispose()

# ------------------------------------------------------------------------------------------------ 2. E2
func research(race: int, block: Dictionary):
	var rules := ProductionRules.new()
	for c in block.named + block.sweep:
		fixture_cases += 1
		research_case(race, rules, c)

func research_case(race: int, rules, c: Dictionary):
	new_world()
	var production = world.production
	production.races[1] = race
	var cell := Vector2i(20, 20)
	for code in c.owned:
		production.add_completed(1, String(code), cell.x, cell.y)
		cell.x += 12
		if cell.x > 150:
			cell = Vector2i(20, cell.y + 12)
	production.research[1] = Array(c.researched).duplicate()
	var stub := FakeWorld.new()
	stub.production = production
	stub.economy = world.economy
	var ai = AiPlayer.new(1, int(c.difficulty), stub, race)
	var listed := ""
	for w in c.want_before:
		if int(w[2]) & 2:
			listed = String(w[0])
			break
	var entries: Array = []
	for e in c.entries:
		var id := String(e[0])
		var had := int(e[2]) != 0
		var ordered: bool = c.ordered.has(id)
		var eligible := int(e[4]) != 0
		if not had and not ordered:
			var port: bool = ai.research_eligible(id)
			# The random sweep owns e.g. BKP3 without BKP2. A match cannot (each level comes from the one before), and the
			# port's Rules.satisfies counts a higher level for a lower one: only those rows may differ, that way round.
			if port and not eligible and hall_hole(c.owned): hole_cases += 1
			else: check(port == eligible, "race %d %s eligible in %s (researched %s): original %s" % [race, id, c.owned, c.researched, eligible])
		entries.append({"id": id, "priority": int(e[1]), "have": had, "ordered": ordered, "eligible": eligible})
	var pick: Dictionary = R.research_pick(listed, entries)
	var after := ""
	for w in c.want_after:
		if int(w[2]) & 2:
			after = String(w[0])
			break
	var expected := listed if pick.keep else ""
	if not pick.keep and String(pick.offer) != "":
		var cost: Array = rules.research_prices.get(String(pick.offer), {}).get("cost", [0, 0, 0, 0])      # the harness's table
		if R.afford(c.stock.map(func(v): return int(v)), cost.map(func(v): return int(v)), c.mines.map(func(l): return [int(l[0]), int(l[1])]), int(c.difficulty)): expected = String(pick.offer)
	check(after == expected, "race %d choice: listed %s, port %s, original %s (%s)" % [race, listed, expected, after, c.get("state", "sweep")])
	ai.dispose()

## Whether the owned hall levels have a gap below the highest one.
func hall_hole(owned: Array) -> bool:
	var top := -1
	var levels := 0
	for code in owned:
		if String(code).begins_with("BK"):
			top = maxi(top, int(String(code).right(1)))
			levels += 1
	return levels != top + 1

# ------------------------------------------------------------------------------------------------ 3. R14
func ability_row(row: Dictionary):
	fixture_cases += 1
	new_world()
	var ai := FakeAi.new()
	var stage := AbilityWorld.new()
	stage.combat = world.combat
	stage.production = world.production
	stage.units = world.units
	ai.world = stage
	ai.face = int(row.roll)
	var scene_row := caster_row(String(row.scene))
	var id := unit(String(row.caster), Vector2i.ZERO, OWNER)
	var f = world.combat.fighters[id]
	var hp_given: int = int(scene_row[0])
	if hp_given > 0:
		f.hp = hp_given
		world.units[id].hp = hp_given
	f["mana"] = int(scene_row[1])
	f["max_mana"] = int(scene_row[2])
	f["mana_ms"] = 0
	for other in row.others:
		var code := String(other[0])
		var owner: int = OWNER if int(other[1]) == 1 else ENEMY
		if code[0] == "B":
			var b = world.production.buildings[building(code, Vector2i(int(other[2]), 0), owner, {})]
			# The harness's building object has no stats block, so 0x5002e0 saw it as weight 1 (the row's 500 is the
			# harness's hit points, not the maximum 0x52ae00 returned there): the same weight here.
			b.max_hit_points = 31
			b.hit_points = 31
			continue
		var other_id := unit(code, Vector2i(int(other[2]), 0), owner)
		var o = world.combat.fighters[other_id]
		o.hp = int(other[4])
		world.units[other_id].hp = o.hp
		if code in ["AHGW"]:                                     # the rows 'mana' / 'low': (50, 50) / (19, 50)
			o["mana"] = 19 if String(row.scene).contains("19 mana") else 50
			o["max_mana"] = 50
			o["mana_ms"] = 0
	var abilities = Abilities.new(ai)
	var label := "%s, %s, roll %d" % [row.scene, "local" if row.local else "computer", int(row.roll)]
	abilities.helper(ai, f, bool(row.local))
	var got: Array = abilities.log.map(func(e): return String(e.cast))
	var want: Array = row.casts.map(func(c): return "Drain" if String(c.spell) == "Drain 0x96" else String(c.spell))
	check(got == want, "%s: port %s, original %s" % [label, got, want])
	for c in row.casts: check(int(c.level) == abilities._level(f), "%s: level" % label)
	for e in abilities.log: check(bool(e.applied), "%s: the record applied" % label)
	# The drain's own transfer is applied here and queued in the harness (the record is not run through 0x4ac0e0 in `abilities`).
	var mana: int = int(f.mana)
	if not got.has("Drain"): check(mana == int(row.mana_after), "%s: mana %d, original %d" % [label, mana, int(row.mana_after)])
	else: check(mana >= int(row.mana_after), "%s: paid (%d, %d)" % [label, mana, int(row.mana_after)])
	check(abilities._radius == int(row.radius), "%s: radius" % label)

## The caster rows of tools/emulate_batch2_review.py ABILITY_SCENES: (hit points, 0 = full; mana; maximum).
func caster_row(scene_name: String) -> Array:
	if scene_name == "heal self only": return [30, 50, 50]
	if scene_name == "heal below mana 40": return [0, 39, 50]
	if scene_name in ["ice enemy weight 2 hurt", "ring weight 1 hurt"]: return [30, 50, 50]
	if scene_name.begins_with("resist fire"): return [0, 39, 50]
	if scene_name in ["pillar building hurt", "pillar weight 1 hurt"]: return [30, 35, 45]
	if scene_name.begins_with("pillar"): return [0, 35, 45]
	if scene_name.begins_with("berserker"): return [0, 30, 45]
	return [0, 50, 50]

# ------------------------------------------------------------------------------------------------ 4. the scan
func scan_flags():
	for code in ["AHGW", "AHGR", "AHGB", "AMMX"]:
		check(Abilities.ai_flag(code), "%s has the scan flag (Army.cfg AI column)" % code)

## The Shaman's cast goes through the real record: friends within r0 get the berserk state, the caster does not (E4).
func berserker_applies():
	new_world()
	var ai := FakeAi.new()
	var stage := AbilityWorld.new()
	stage.combat = world.combat
	stage.production = world.production
	stage.units = world.units
	ai.world = stage
	var shaman := unit("AMMX", Vector2i.ZERO, OWNER)
	var f = world.combat.fighters[shaman]
	f["mana"] = 30
	f["max_mana"] = 45
	f["mana_ms"] = 0
	var friend := unit("AMIX", Vector2i(3, 0), OWNER)
	unit("AMIX", Vector2i(5, 0), ENEMY)
	unit("AMIX", Vector2i(6, 0), ENEMY)
	var abilities = Abilities.new(ai)
	check(abilities.helper(ai, f), "the Shaman casts Berserker")
	check(world.combat.fighters[friend].get("berserk") != null, "the friend is berserk")
	check(f.get("berserk") == null, "the caster is not")
	check(int(f.mana) == 5, "25 mana paid")
	# Saved state: the next pass and the casts survive a save and load; the transient pass fields do not matter.
	var saved: Dictionary = abilities.save_state()
	var loaded = Abilities.new(ai)
	loaded.load_state(saved)
	check(int(loaded.casts.get("Berserker", 0)) == 1, "the casts are saved")
