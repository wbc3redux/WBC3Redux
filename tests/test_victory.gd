extends SceneTree
## S-2: the victory options 1..12 against tests/victory_fixtures.json (tools/emulate_victory.py) and each deciding a headless
## match in the real scene; the setup's side effects, More Options and Rules reaching the match and persisting; the quest
## gate; the hero's quest site and shop contexts; retinue units placed; the hero book's Load Game. Never touches user://heroes.

const Setup = preload("res://simulation/skirmish_setup.gd")
const Victory = preload("res://simulation/skirmish_victory.gd")
const Shops = preload("res://simulation/skirmish_shops.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const MapData = preload("res://core/map_data.gd")
const Main = preload("res://battle/main.gd")
const FrontEnd = preload("res://menus/front_end.gd")

var checks := 0
var failures := 0
var store
var directory := ""

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Victory check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	fixture_checks()
	setup_checks()
	directory = "user://victory-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(directory)
	store = Store.new(directory)
	var profile = Profile.create("test-knight", "Sir Test")
	check(store.save_profile(profile), "copied test profile saved")
	Settings.use_file(directory.path_join("settings.cfg"))
	persist_checks()
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	option_checks(scene)
	rule_checks(scene)
	site_checks(scene)
	await hero_book_checks(scene)
	Settings.use_file(Settings.DEFAULT_PATH)
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures > 0:
		printerr("Victory checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Victory checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ fixtures
func fixture_checks():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/victory_fixtures.json"))
	var divergent := 0
	var decided := {}
	for case in fixtures.conditions:
		var objects: Array = []
		for p in 6:
			var list: Array = []
			for o in case.objects[p]:
				if o.kind == "unit":
					list.append({"kind": "unit", "hp": int(o.hp)})
				else:
					var code := String(o.code)
					list.append({"kind": "building", "resource": bool(o.resource), "code": code, "keep": code[1] == "K", "level": int(o.level),
						"flag": case.flag_names.find(String(o.name))})
			objects.append(list)
		var world := {"active": case.active, "eliminated": case.eliminated, "allied": case.allied, "local": int(case.local), "seconds": int(case.seconds),
			"timer_running": bool(case.timer_running), "objects": objects, "heroes": case.heroes, "resources": case.resources,
			"razed": case.razed, "killed": case.killed, "flags": int(case.flags)}
		var event := {"condition": int(case.condition), "delay_s": int(case.delay), "value": 2500}
		var side := int(case.side)
		var got: Dictionary = Victory.evaluate(world, event, side)
		var r: Dictionary = case.result
		var messages: Array = r.messages
		var expected := "none"
		var player := -1
		if int(r.local_victory) != 0:
			expected = "win"
			player = int(case.local)
		elif int(r.local_defeat) != 0:
			expected = "defeat"
			player = int(case.local)
		for m in messages:
			if int(m.kind) == 0x1c2:
				expected = "win" if int(m.flag) == 1 else "defeat"
				player = int(m.player)
			elif int(m.kind) == 0x1d0:
				expected = "tie"
				player = side
		var same: bool = String(got.kind) == expected and (expected == "none" or int(got.player) == player)
		if not same:
			divergent += 1
			if divergent < 6: printerr("condition %x side %d local %d: got %s, expected %s %d" % [int(case.condition), side, int(case.local), got, expected, player])
		if expected != "none": decided[int(case.condition)] = true
	check(divergent == 0, "0x514670 conditions 0xc..0x13, 0x1e: %d divergences of %d" % [divergent, fixtures.conditions.size()])
	check(decided.size() == 9, "every condition decided in the fixtures: %s" % [decided.keys()])
	for tie in fixtures.conditions:
		for m in tie.result.messages:
			if int(m.kind) == 0x1d0: check(int(m.amount) == Victory.TIE_EXTENSION_S, "the tie message carries 300 s")

# ------------------------------------------------------------------------------------------------ setup
func desert() -> Dictionary:
	MapData.select("desert-sands")
	return MapData.map()

func new_setup() -> Dictionary:
	var setup := Setup.defaults(desert())
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	return setup

func setup_checks():
	check(Victory.event_for(0).is_empty() and Victory.event_for(9).is_empty() and Victory.event_for(10).is_empty() and Victory.event_for(11).is_empty(), "0x41c7d0: options 0, 9, 10, 11 install no event")
	check(int(Victory.event_for(1).condition) == 0xc and int(Victory.event_for(4).delay_s) == 1800 and int(Victory.event_for(8).value) == 2500 and int(Victory.event_for(12).condition) == 0x1e, "0x41c7d0's option table")
	var setup := new_setup()
	setup.players[0].team = 2
	setup.players[1].team = 2
	Setup.choose_victory(setup, 5)
	check(Setup.teams_locked(setup) and int(setup.players[0].team) == 0 and int(setup.players[1].team) == 0, "Slug Fest: free for all (0x4e3c60 case 4)")
	Setup.choose_victory(setup, 9)
	check(int(setup.players[0].team) == 1 and int(setup.players[1].team) == 2, "Against the Horde: slot 0 team 1, the rest team 2")
	Setup.choose_victory(setup, 0)
	check(not Setup.teams_locked(setup) and int(setup.players[0].team) == 2 and int(setup.players[1].team) == 2, "the teams come back")
	setup.options.army_points = 7
	setup.options.build_level = 3
	Setup.choose_victory(setup, 0xb)
	check(int(setup.options.army_points) == 50 and int(setup.options.build_level) == 0, "Pitched Battle: 50 points, No Building (0x4dfec0)")
	check(int(Setup.resolve(setup).slots[1].difficulty) == 0, "a Passive computer stays Passive under Pitched Battle (0x4eaca0)")
	Setup.choose_victory(setup, 7)
	check(int(setup.options.army_points) == 7 and int(setup.options.build_level) == 5, "King of the Castle: Keep Level 5, the points come back")
	Setup.choose_victory(setup, 0)
	check(int(setup.options.build_level) == 3, "the build level comes back")
	setup.options.no_titans = true
	setup.options.no_heroes = true
	Setup.choose_victory(setup, 10)
	check(not bool(setup.options.no_titans) and not bool(setup.options.no_heroes), "Battle of Titans clears No Titans and No Heroes")
	Setup.choose_victory(setup, 0)
	check(bool(setup.options.no_titans) and bool(setup.options.no_heroes), "and restores them")

func persist_checks():
	var options: Dictionary = Setup.defaults(desert()).options
	check(not bool(options.random_weather) and bool(options.resign_kills) and bool(options.ai_resign) and int(options.temp_hero_level) == 10, "More Options defaults 0x10100, level 10")
	options.quests = false
	options.vision = 0
	options.random_weather = true
	options.resign_kills = false
	options.no_hero_items = true
	options.temp_hero_level = 33
	options.no_dragons = true
	check(Setup.save_options(options) and Setup.save_more_options(options), "options saved")
	var again: Dictionary = Setup.defaults(desert()).options
	Setup.load_saved_options(again)
	check(not bool(again.quests) and int(again.vision) == 0 and bool(again.random_weather) and not bool(again.resign_kills) and bool(again.no_hero_items)
		and int(again.temp_hero_level) == 33, "saved options reload (0x450970, 0x450d00)")
	check(not bool(again.no_dragons), "Rules are not saved: the setup clears them (0x4e45c0)")
	DirAccess.remove_absolute(Setup.saved_options_path())

# ------------------------------------------------------------------------------------------------ the options in a match
func start(scene, option: int, edit: Callable = Callable()):
	var setup := new_setup()
	Setup.choose_victory(setup, option)
	if edit.is_valid(): edit.call(setup)
	check(scene.start_skirmish(setup, "test-knight", store, "victory-%d-%d" % [option, randi()]), "option %d starts" % option)
	return scene.skirmish

func step(scene, seconds: float):
	for i in roundi(seconds * 60.0):
		if scene.skirmish.over: return
		scene.simulation_step(1.0 / 60.0)

func hero_unit(scene, owner: int):
	for unit in scene.units:
		if unit.owner_id == owner and scene.is_hero_unit(unit): return unit
	return null

func raze(scene, owner: int):
	for b in scene.production.buildings.values().duplicate():
		if int(b.owner) == owner: scene.combat.apply_damage("building", b.entity_id, b.hit_points + 1, -1)

func kill_units(scene, owner: int):
	for f in scene.combat.fighters.values():
		if int(f.owner) == owner and scene.combat.alive(f): scene.combat.apply_damage("unit", f.id, 1000000, -1)

func past(m, seconds: int):
	m.started_ms = m.now_ms - seconds * 1000

func option_checks(scene):
	# Raze All Buildings: nothing before 300 s; the enemy's hero still stands when its buildings are gone.
	var m = await_start(scene, 1)
	raze(scene, 1)
	step(scene, 3.0)
	check(not m.over, "Raze All Buildings: no decision before 300 s")
	check(m.timer_running() and m.timer_left_ms() > 290000, "the countdown runs")
	scene.encounters.place_site("BKK0", 0, scene.navigator.free_cell_near(Vector2i(20, 60)))
	past(m, 301)
	step(scene, 3.0)
	check(m.over and bool(m.outcome.won) and String(m.outcome.reason) == "victory_option", "Raze All Buildings: the side without buildings is out")
	# Raze All: the local side without buildings loses at the first check past the delay.
	m = await_start(scene, 1)
	past(m, 301)
	raze(scene, 0)
	step(scene, 3.0)
	check(m.over and not bool(m.outcome.won), "Raze All Buildings: the local side without buildings is defeated")
	# Kill All Units: the towers do not save the side.
	m = await_start(scene, 2)
	kill_units(scene, 1)
	past(m, 301)
	step(scene, 6.0)
	check(m.eliminated[1], "Kill All Units: the side without living units is out (0x4addc0), the win comes at the next pass")
	check(m.over and bool(m.outcome.won), "Kill All Units decides with towers standing")
	# Assassination: the enemy hero's death decides at once, not after the corpse.
	m = await_start(scene, 3)
	var theirs = hero_unit(scene, 1)
	scene.combat.apply_damage("unit", theirs.unit_id, 100000, -1)
	step(scene, 3.0)
	check(m.over and bool(m.outcome.won) and float(m.outcome.elapsed_ms) < 5000.0, "Assassination: the enemy hero's death wins")
	m = await_start(scene, 3)
	scene.combat.apply_damage("unit", scene.hero_unit_id, 100000, -1)
	step(scene, 3.0)
	check(m.over and not bool(m.outcome.won), "Assassination: the own hero's death loses")
	# Raze Fest: a tie extends by 300 s, then the most buildings win.
	m = await_start(scene, 4)
	past(m, 1801)
	step(scene, 3.0)
	check(not m.over and int(m.victory_event.delay_s) == 2100 and m.timer_running(), "Raze Fest: a tie adds 300 s and restarts the timer (0x4aecd0)")
	m.stats[0].buildings_destroyed = 2
	m.stats[1].buildings_destroyed = 1
	past(m, 2110)
	step(scene, 3.0)
	check(m.over and bool(m.outcome.won), "Raze Fest: the most buildings win")
	# Slug Fest: the enemy leads.
	m = await_start(scene, 5)
	m.stats[1].troops_killed = 4
	past(m, 1801)
	step(scene, 3.0)
	check(m.over and not bool(m.outcome.won), "Slug Fest: the side with the fewest kills loses")
	# Fortress: the side without a Keep is out after 300 s.
	m = await_start(scene, 6)
	scene.encounters.place_site("BKK0", 0, scene.navigator.free_cell_near(Vector2i(20, 60)))
	past(m, 301)
	step(scene, 3.0)
	check(m.over and bool(m.outcome.won), "Fortress: the only Keep wins")
	# King of the Castle: the first level 5 Keep.
	m = await_start(scene, 7)
	check(m.score_rows().size() == 6 and int(m.score_rows()[0]) == 0, "King of the Castle shows the score panel")
	scene.encounters.place_site("BKK4", 1, scene.navigator.free_cell_near(Vector2i(100, 60)))
	step(scene, 3.0)
	check(m.over and not bool(m.outcome.won), "King of the Castle: the enemy's level 5 Keep loses the match")
	# Merchants: 2500 of each.
	m = await_start(scene, 8)
	scene.economy.stockpiles[0] = [2500, 2500, 2500, 2500]
	step(scene, 3.0)
	check(m.over and bool(m.outcome.won), "Merchants: 2500 of each resource wins")
	# Against the Horde: teams, Standard Victory decides.
	m = await_start(scene, 9)
	check(int(m.slots[0].team) == 1 and int(m.slots[1].team) == 2 and m.victory_event.is_empty(), "Against the Horde: teams, no event")
	# Battle of Titans: a Titan each, computer heroes at level 100, no more Titans; Standard Victory decides.
	m = await_start(scene, 10)
	var titans: Array = scene.units.filter(func(u): return String(u.type_id) == "ATHX")
	check(titans.size() == 2 and bool(scene.production.rules.options.no_lords), "Battle of Titans: a Titan per side (0x41c7d0), the Titan gate closed")
	check(int(scene.match_heroes[1].profile.data.level) == 100, "Battle of Titans: the computer hero is level 100 (0x42a0d0)")
	kill_units(scene, 1)
	raze(scene, 1)
	step(scene, 34.0)
	check(m.over and bool(m.outcome.won), "Battle of Titans: decided by Standard Victory")
	# Pitched Battle: No Building, 50 points, Rampant computers.
	m = await_start(scene, 11, func(setup): Setup.set_kind(setup, 1, Setup.COMPUTER, 2))
	check(int(m.options.army_points) == 50 and int(m.options.build_level) == 0 and int(m.slots[1].difficulty) == 7, "Pitched Battle reaches the match")
	check(int(scene.production.rules.options.build_level) == 0, "Pitched Battle: no building")
	# Capture the Flag: a flag at each start, all of them held wins.
	m = await_start(scene, 12)
	check(m.flag_ids.size() == 2, "Capture the Flag: a flag per side (0x41c7d0 case 0xc)")
	for id in m.flag_ids: scene.production.building(int(id)).owner = 0
	step(scene, 3.0)
	check(m.over and bool(m.outcome.won), "Capture the Flag: every flag held wins")

func await_start(scene, option: int, edit: Callable = Callable()):
	return start(scene, option, edit)

# ------------------------------------------------------------------------------------------------ Rules, More Options
func rule_checks(scene):
	var m = start(scene, 0, func(setup):
		setup.options.no_dragons = true
		setup.options.no_eyries = true
		setup.options.no_titans = true
		setup.options.no_towers = true
		setup.options.no_walls = true
		setup.options.tough_towers = true
		setup.options.quests = false)
	var gates: Dictionary = scene.production.rules.options
	check(bool(gates.no_dragons) and bool(gates.no_fliers) and bool(gates.no_lords) and bool(gates.no_towers) and bool(gates.no_walls), "Rules reach the production gates 0x40c990")
	check(not scene.encounters.quests_enabled, "Quests Off reaches the match (0x70ae0d)")
	var tower = null
	for b in scene.production.buildings.values():
		if String(b.original_type_id) == "BWTC": tower = b
	var plain: Dictionary = scene.encounters.catalogue_record("buildings", "BWTC")
	check(tower != null and int(tower.definition.hit_points) >= int(plain.decoded.hit_points) * 3 / 2, "Tough Towers: x 3 / 2 hit points (0x41a8c0)")
	check(int(scene.combat.towers[tower.entity_id].damage) == scene.encounters.Rules.i16(String(plain.raw_hex).hex_decode(), 0x38) * 3, "Tough Towers: x 3 damage")
	# No Heroes: three units instead (0x445810), none of them a hero.
	m = start(scene, 0, func(setup): setup.options.no_heroes = true)
	check(scene.hero_unit_id == -1 and scene.units.all(func(u): return not scene.is_hero_unit(u)), "No Heroes: no hero is created")
	check(scene.units.filter(func(u): return u.owner_id == 0).size() == 3, "No Heroes: three starting units for the side")
	# A temporary hero: computer heroes at its level, nothing written, no saves.
	var before: int = int(store.load_profile("test-knight").data.history.battles_fought)
	m = start(scene, 0, func(setup):
		setup.options.temp_hero = true
		setup.options.temp_hero_level = 12)
	check(int(store.load_profile("test-knight").data.history.battles_fought) == before and not scene.can_save(), "temporary hero: no start save, no saving (0x4e2790, 0x427fb0)")
	check(int(scene.match_heroes[1].profile.data.level) == 12, "temporary hero: the computer's level (0x42a0d0)")
	# Vision 2 (Line of Sight) arms the terrain test 0x485720 with the map's heights.
	m = start(scene, 0, func(setup): setup.options.vision = 2)
	check(scene.visibility.fog and scene.visibility.line_of_sight_option == 2 and not scene.visibility.heights.is_empty(), "Line of Sight reaches the fog (0x485720 with the map's heights)")
	# The retinue deployed on the army screen is placed.
	m = start(scene, 0, func(setup): setup.army_retinue = [{"id": "r1", "original_type_id": "AHKX", "xp": 40, "medal_level": 2}])
	var swordsmen: Array = scene.units.filter(func(u): return String(u.type_id) == "AHKX" and u.owner_id == 0)
	# R-1 (REVIEW_R1.md D1): the 0xfd block carries the rank and the experience 0x5fbc48[rank] outside a scenario, not the stored xp.
	var placed = scene.combat.fighters[swordsmen[0].unit_id] if swordsmen.size() == 1 else {}
	check(swordsmen.size() == 1 and int(placed.get("rank", 0)) == 2
		and int(placed.get("xp", -1)) == preload("res://simulation/unit_ranks.gd").creation_xp(2, 40, false),
		"the deployed retinue unit is placed with its rank (0x4406b0, 0x4a5780)")
	retinue_scan(scene)

## Playtest 2026-11-11: the end-of-battle scan 0x43f3e0 in a match. Two members deployed; r1 is promoted and lives, r2
## dies (r1's set_rank promotes on top of its deployed rank 2); a trained Swordsman reaches rank 2 and becomes a candidate (with the Knights' general for hire). The result
## writes r1's rank, one battle each, r2's grave, and hands the candidates to the retinue screen.
func retinue_scan(scene):
	var hero = store.load_profile("test-knight")
	hero.data.retinue = [{"id": "r1", "original_type_id": "AHKX", "xp": 10, "medal_level": 2, "battles": 2, "permanent_state": {}},
		{"id": "r2", "original_type_id": "AHMX", "xp": 10, "medal_level": 2, "battles": 1, "name": "Archer Ann", "permanent_state": {}}]
	hero.data.graveyard = []
	check(store.save_profile(hero), "retinue scan: the hero's retinue saved")
	var m = start(scene, 0, func(setup): setup.army_retinue = hero.data.retinue.duplicate(true))
	var by_member := {}
	for key in m.retinue_units: by_member[String(m.retinue_units[key])] = int(key)
	check(by_member.has("r1") and by_member.has("r2"), "retinue scan: both members are tracked as deployed (+0x1c8 / +0x1ca)")
	if not (by_member.has("r1") and by_member.has("r2")): return
	var r1 = scene.combat.fighters[by_member.r1]
	scene.combat.set_rank(r1, 4, 40)
	scene.combat.apply_damage("unit", by_member.r2, 1000000, -1)
	var home: Vector2i = scene.skirmish.slots[0].start
	var veteran = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(3, 3)), 0)
	scene.combat.set_rank(scene.combat.fighters[veteran.unit_id], 2, 10)
	var green = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(4, 3)), 0)
	scene.combat.set_rank(scene.combat.fighters[green.unit_id], 1, 5)
	m.over = true
	m.outcome = {"won": true, "reason": "standard", "ended_ms": m.now_ms, "elapsed_ms": m.now_ms, "short": false}
	scene.run_retinue_scan()
	var result: Dictionary = m.retinue_result
	check(not result.is_empty() and result.retinue.size() == 1 and String(result.retinue[0].id) == "r1" and int(r1.rank) > 2
		and int(result.retinue[0].medal_level) == int(r1.rank) and int(result.retinue[0].xp) == int(r1.xp)
		and int(result.retinue[0].battles) == 3, "retinue scan: r1 writes back its new rank and experience and counts a battle (%s)" % [result.get("retinue")])
	check(result.graveyard.size() == 1 and String(result.graveyard[0].name) == "Archer Ann" and int(result.graveyard[0].battles) == 2, "retinue scan: r2 goes to the graveyard")
	var types: Array = result.candidates.map(func(c): return String(c.original_type_id))
	check(types.count("AHKX") == 1 and types.size() == 2 and preload("res://simulation/retinue_scan.gd").OFFERS.slice(1, 11).has(types[1]),
		"retinue scan: the rank-2 Swordsman is a candidate (not the rank-1 one), then a Knights general for hire (%s)" % [types])
	check(m.apply_result(store, scene.hero_match), "retinue scan: the result is written")
	var saved = store.load_profile("test-knight")
	check(saved.data.retinue.size() == 1 and int(saved.data.retinue[0].medal_level) == int(r1.rank) and saved.data.graveyard.size() == 1, "retinue scan: the hero file carries the survivor and the grave")
	saved.data.retinue = []
	saved.data.graveyard = []
	store.save_profile(saved)

# ------------------------------------------------------------------------------------------------ sites
func click_on(scene, b):
	var cell: Vector2i = b.cell_rect().position
	scene.right_click(scene.navigator.center(cell), {"shift": false, "alt": false, "ctrl": false})

func select_hero(scene):
	for unit in scene.units: unit.selected = unit.unit_id == scene.hero_unit_id

func walk(scene):
	for i in 3600:
		if scene.site_orders.is_empty(): return
		scene.simulation_step(1.0 / 60.0)

func site_checks(scene):
	# The Quests gate: the context is off and the visit answers nothing.
	var m = start(scene, 0, func(setup): setup.options.quests = false)
	var mausoleum: int = scene.mausoleum_id
	select_hero(scene)
	var site = scene.production.building(mausoleum)
	scene.units[scene.hero_unit_id].position = scene.navigator.center(scene.navigator.free_cell_near(site.cell_rect().position + Vector2i(-2, 3)))
	scene.units[scene.hero_unit_id].sync_cell()
	check(scene.site_kind({"kind": "building", "object": site}) == "", "Quests Off: no quest context (0x421190)")
	check(scene.encounters.visit(0, mausoleum).mode == "none", "Quests Off: no offer (0x70ae0d)")
	# Quests On: right click, the hero walks there, the offer follows.
	m = start(scene, 0)
	mausoleum = scene.mausoleum_id
	select_hero(scene)
	site = scene.production.building(mausoleum)
	var hero = scene.units[scene.hero_unit_id]
	var near: Vector2i = scene.navigator.free_cell_near(site.cell_rect().position + Vector2i(-2, 3))
	scene.navigator.release(hero, hero.cell)
	hero.position = scene.navigator.center(near)
	hero.sync_cell()
	scene.navigator.occupy(hero, hero.cell) if scene.navigator.has_method("occupy") else null
	click_on(scene, site)
	check(scene.site_orders.has(hero.unit_id), "right click on the Mausoleum: order 0xb")
	walk(scene)
	check(scene.site_orders.is_empty() and String(scene.site_visit.get("mode", "")) in ["offer", "instant", "unsupported", "continue", "complete"], "the hero arrives: 0x43d180 (%s)" % [scene.site_visit])
	# The Shrine is a quest site with its own records.
	var shrine: int = scene.encounters.place_site("BMSH", 6, scene.navigator.free_cell_near(Vector2i(40, 60)))
	check(scene.encounters.givers.has(shrine) and scene.encounters.quest_records("BMSH").size() > 0, "BMSH: Quest.xcr Bmsh.dat, a quest site")
	var v: Dictionary = scene.encounters.visit(0, shrine)
	check(v.mode != "none" and String(v.get("record", {}).get("cmpl", "")) != "", "the Shrine offers its own quest (%s)" % [v.get("mode", "")])
	# A shop: stocked once, right click, dialog 12, buying.
	var shop: int = scene.encounters.place_site("BSFG", 6, scene.navigator.free_cell_near(Vector2i(24, 60)))
	scene.encounters.shops_ready = false
	step(scene, 0.1)
	check(scene.encounters.shops.has(shop) and scene.encounters.shops[shop].percent.all(func(p): return int(p) >= 90 and int(p) <= 110), "the shop is stocked (0x408450)")
	var stock: Dictionary = scene.encounters.shops[shop]
	stock.percent[0] = 100
	stock.items[0] = 2
	stock.items[1] = 2
	var building = scene.production.building(shop)
	select_hero(scene)
	click_on(scene, building)
	check(scene.site_orders.has(hero.unit_id) and String(scene.site_orders[hero.unit_id].kind) == "shop", "right click on the shop: order 0x13")
	walk(scene)
	check(String(scene.site_visit.get("mode", "")) == "shop", "the hero arrives: dialog 12 (0x408580)")
	# Issue 1: a visit whose walk ends somewhere else opens nothing. The hero starts 14 cells away and is stopped on the way.
	var away: Vector2i = scene.navigator.free_cell_near(building.cell_rect().position + Vector2i(14, 0))
	scene.navigator.release(hero, hero.cell)
	hero.position = scene.navigator.center(away)
	hero.sync_cell()
	scene.navigator.occupy(hero, hero.cell) if scene.navigator.has_method("occupy") else null
	scene.site_visit = {}
	select_hero(scene)
	click_on(scene, building)
	check(scene.site_orders.has(hero.unit_id) and scene.site_orders[hero.unit_id].get("goal") is Vector2i, "the visit keeps the cell the hero was sent to")
	step(scene, 0.5)
	scene.stop_selected()
	walk(scene)
	step(scene, 0.5)
	check(scene.site_orders.is_empty() and scene.site_visit.is_empty(), "issue 1: a stopped hero's visit is dropped, no dialog (%s, hero %s)" % [scene.site_visit, hero.cell])
	check(not scene._hero.arrived_at_site(hero, {"building": shop, "kind": "shop", "goal": building.cell_rect().position}, building), "issue 1: not arrived %d cells away" % 14)
	click_on(scene, building)
	walk(scene)
	check(String(scene.site_visit.get("mode", "")) == "shop", "issue 1: the visit still opens the shop when the hero walks there")
	var goods: Array = scene.shop_goods(shop)
	check(goods.size() == 4 and int(goods[0].price) == 500 and int(goods[2].price) == 700, "prices: 500 for a potion, value x 10 for an item (0x56e860)")
	check(not scene.shop_buy(shop, 0), "300 of each does not pay for a potion")
	scene.economy.stockpiles[0] = [1000, 1000, 1000, 1000]
	var potions: int = int(scene.hero_match.potions)
	check(scene.shop_buy(shop, 0) and int(scene.hero_match.potions) == potions + 1 and scene.economy.resources(0) == [500, 500, 500, 500], "a potion: paid in all four resources (0x56e420)")
	var mana: int = scene.hero_match.mana_potion_count()
	scene.economy.stockpiles[0] = [1000, 1000, 1000, 1000]
	check(scene.shop_buy(shop, 1) and scene.hero_match.mana_potion_count() == mana + 1, "a mana potion")
	scene.economy.stockpiles[0] = [1000, 1000, 1000, 1000]
	scene.hero_match.potions = 9
	check(not scene.shop_buy(shop, 0), "above 8 potions nothing is sold")
	check(scene.shop_buy(shop, 2) and int(stock.items[0]) == 0 and scene.hero_match.profile.data.backpack.any(func(s): return int(s.get("item", 0)) == 2), "an item goes to the backpack and leaves the stock")
	check(not scene.shop_buy(shop, 2), "an empty place sells nothing")
	Shops.offended(scene.encounters.shops, shop, 0)
	check(int(stock.percent[0]) == 150, "attacking a shop raises the attacker's prices (0x408360)")

# ------------------------------------------------------------------------------------------------ hero book
func hero_book_checks(scene):
	var m = start(scene, 2)
	scene.save_directory = directory
	var path: String = scene.save_path()
	check(scene.save_match(path) == "", "a saved game for the hero book")
	var saved_event: int = int(m.victory_event.delay_s)
	m.victory_event.delay_s = 999
	check(FrontEnd.save_of("test-knight", directory) == path, "the hero book finds the hero's save (0x5563a0)")
	check(FrontEnd.save_of("nobody", directory) == "", "a hero without a save has nothing to load")
	check(Main.prepare_saved_game(path, directory, directory) == "" and not Main.pending_load.is_empty(), "Load Game accepts it (0x553bc0 case 4)")
	close(scene)
	await process_frame
	var loaded = load("res://battle/main.tscn").instantiate()
	root.add_child(loaded)
	for i in 30: await process_frame
	check(loaded.skirmish != null and loaded.hero_unit_id >= 0 and int(loaded.skirmish.victory_event.delay_s) == saved_event, "the saved match opens with its victory option")
	close(loaded)
	await process_frame

func close(scene):
	scene.end_skirmish()
	if scene.encounters != null: scene.encounters.dispose()
	scene.free()
