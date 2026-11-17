extends SceneTree
## Milestone 10a: fixture parity (tests/skirmish_fixtures.json, tools/emulate_skirmish.py) and headless matches in the
## real scene: start, Standard Victory through a test hook that gives player 0 overwhelming force, the result writeback
## (exactly once) on a copied profile, an abandoned match, a quit and a defeat. Never touches user://heroes.

const Setup = preload("res://simulation/skirmish_setup.gd")
const ArmySetup = preload("res://simulation/army_setup.gd")
const Match = preload("res://simulation/skirmish_match.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Encounters = preload("res://simulation/encounters.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Skirmish check failed: ", label)

class FakeWorld:
	var fighters: Dictionary = {}
	var buildings: Dictionary = {}

class FakeBuilding:
	var owner := 0
	var original_type_id := ""
	var entity_id := 0

func _initialize():
	call_deferred("run")

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/skirmish_fixtures.json"))
	fixture_checks(fixtures)
	var directory := "user://skirmish-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	await match_checks(store)
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures > 0:
		printerr("Skirmish checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Skirmish checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ fixtures
func fixture_checks(fixtures: Dictionary):
	for row in fixtures.starting_resources:
		check(Setup.starting_resources(int(row.setting)) == row.lanes.map(func(v): return int(v)), "0x43e4d0 setting %d" % int(row.setting))
	check(int(fixtures.scn_header.byte_14b) == 1 and int(fixtures.scn_header.byte_14c) == 1, "Desert Sands header: heroes (0x748a97) and Standard Victory event (0x748a98)")
	for row in fixtures.short_match:
		check(HeroRules.short_match_bonus(bool(row.won), int(row.victory_option), int(row.build_level)) == int(row.xp), "0x4553f0 short match %s" % str(row))
		check(int(row.profile_xp_added) == int(row.xp), "short award reaches the profile XP")
	for row in fixtures.skill_terms:
		if int(row.skill) == 8: check(row.values.slice(4, 8).map(func(v): return int(v)) == [0, 1, 2, 5], "0x556ea0 Leadership x1")
		if int(row.skill) == 67: check(row.values.slice(4, 8).map(func(v): return int(v)) == [0, 2, 4, 10], "0x556ea0 Knight Lord x2")
	var catalogue: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalogue.json"))
	var divergent := 0
	for case in fixtures.standard_victory:
		var slots: Array = []
		for p in 7: slots.append({"active": bool(case.active[p]), "race": int(case.race[p]), "computer": false, "resources": 2, "difficulty": 0})
		var allied := PackedByteArray()
		for a in 7:
			for b in 7: allied.append(int(case.allied[a][b]))
		var m := Match.new({"slots": slots, "allied": allied, "local": int(case.local), "options": {}, "map_width": 128}, null, null, {})
		var world := FakeWorld.new()
		var next := 0
		for p in case.objects.size():
			for o in case.objects[p]:
				if o.kind == "unit":
					world.fighters[next] = {"owner": int(o.owner), "hero": bool(o.hero), "hp": int(o.hp), "state": "dying" if int(o.state) == 8 else "idle",
						"removed": false, "flag_30": bool(o.flag30), "list": p}
				else:
					var b := FakeBuilding.new()
					b.owner = int(o.owner)
					b.original_type_id = "ROW%d" % int(o.row)
					b.entity_id = next
					world.buildings[next] = b
				next += 1
		for r in 4: m.stop_defeat["ROW%d" % r] = case.rows[r].map(func(v): return v != 0)
		# Fixture objects sit in list p and keep their own owner field (the original tests them with the list's player).
		m.combat = world
		m.production = world
		for p in 7: m.eliminated[p] = bool(case.eliminated[p])
		var expected := 0
		var r: Dictionary = case.result
		if int(r.local_victory) != 0 or r.messages.any(func(x): return int(x.flag) == 1): expected = 1
		if int(r.local_defeat) != 0 or r.messages.any(func(x): return int(x.flag) == 0): expected = -1
		var got: int = m.evaluate_standard(int(case.side))
		if got != expected: divergent += 1
		check(got == expected, "0x514670 case 10 side %d local %d" % [int(case.side), int(case.local)])
		if int(case.side) == int(case.local) and expected < 0: check(int(r.game_over) == 1, "local defeat sets 0x748914")
	check(divergent == 0, "standard victory divergences: %d" % divergent)

# ------------------------------------------------------------------------------------------------ matches
func new_scene():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	return scene

func setup_for(profile_id: String) -> Dictionary:
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)   # milestone 11a: the map's races are the default; these matches are Knights
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = profile_id
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)       # Passive (AI: Passive): these matches test victory and writeback, not the AI
	return setup

func advance(scene, seconds: float):
	for i in roundi(seconds * 60.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(1.0 / 60.0)

func hero_of(scene, owner: int):
	for unit in scene.units:
		if unit.type_id == "AHHX" and unit.owner_id == owner: return unit
	return null

func match_checks(store):
	var profile = Profile.create("test-knight", "Sir Test")
	check(store.save_profile(profile), "copied test profile saved")
	var scene = await new_scene()
	# ---- start
	check(scene.start_skirmish(setup_for("test-knight"), "test-knight", store, "test-match-1"), "match starts")
	var m = scene.skirmish
	check(m != null and Setup.active_players(m.resolved) == [0, 1], "two active players")
	check(scene.economy.resources(0) == [300, 300, 300, 300] and scene.economy.resources(1) == [300, 300, 300, 300], "Average resources = 300 (0x43e4d0 setting 2)")
	var mine = hero_of(scene, 0)
	var theirs = hero_of(scene, 1)
	check(mine != null and theirs != null, "both heroes spawned")
	check(mine.cell == scene.navigator.free_cell_near(Vector2i(12, 64), mine) or mine.cell.distance_to(Vector2(12, 64)) <= 2, "local hero at the west start (0x43b4c0)")
	check(theirs.cell.distance_to(Vector2(113, 64)) <= 2, "computer hero at the east start")
	check(scene.combat.fighters[mine.unit_id].hero and scene.combat.fighters[theirs.unit_id].hero, "both heroes carry the hero flag")
	var towers := {}
	for b in scene.production.buildings.values():
		towers[b.original_type_id + str(b.owner)] = int(towers.get(b.original_type_id + str(b.owner), 0)) + 1
	# Parity pass 3 (0x4a50f0): the map's Dwarven and Swarm Towers become their Knights owners' Knight Towers (BWTC).
	check(towers.get("BWTC0", 0) == 2 and towers.get("BWTC1", 0) == 2 and towers.get("BLGL6", 0) == 1 and towers.get("BZMA6", 0) == 1, "map towers take their owner's race, encounters neutral: %s" % towers)
	var level_terms := Encounters.tower_level_terms(int(profile.data.level))
	for b in scene.production.buildings.values():
		if String(b.original_type_id) == "BWTC":
			check(int(b.max_hit_points) == 320 + int(level_terms.hit_points) and int(b.hit_points) == int(b.max_hit_points), "Knight Tower hit points 320 + 10 x hero level (0x4a50f0)")
			var raw: PackedByteArray = String(b.definition.raw_hex).hex_decode()
			check(int(scene.combat.towers[b.entity_id].damage) == (raw[0x38] | (raw[0x39] << 8)) + int(level_terms.damage), "Knight Tower damage BUI +0x38 + level / 4")
	var units_0: Array = scene.units.filter(func(u): return u.owner_id == 0)
	check(units_0.size() == 1, "player 0 starts with its hero only (0 army setup points)")
	# 0x533dc0 + 0x52eae0: every completed own building adds its Building.cfg A column, the map's two Dwarven Towers too (2 each).
	var expected_command: int = Match.command_term(profile.data) + scene.production.rules.KEEP_COMMAND_TABLE[0] - 2 + tower_limit(scene, 0)
	check(scene.production.population(0).maximum == expected_command, "command limit with the hero term %d" % expected_command)
	check(Match.command_term(profile.data) == (HeroRules.derived(profile.data.stats, 0xc, 1) + 1 + 2) / 2, "0x5268c0 term: derived 12, Leadership 1, Knight Lord 1 x2")
	check(scene.visibility.fog and scene.visibility.shroud and scene.combat.game_mode == 0, "fog of war, hidden map, game mode 0")
	var stored = store.load_profile("test-knight")
	check(stored.data.history.battles_fought == 1 and "test-match-1-start" in stored.data.applied_results, "battle counted and saved at the start (0x4e2790)")
	# ---- cadence: the first Standard Victory pass is at 54 x 50 ms
	advance(scene, 2.65)
	check(m.log.is_empty() and m.check_counter == 2, "no decision before the first pass")
	advance(scene, 0.1)
	check(m.check_counter == 0 and not m.over, "first pass at 2.7 s, nobody out")
	# ---- test hook: overwhelming force next to the computer hero
	for i in 40: scene.add_unit("AHKX", scene.navigator.free_cell_near(theirs.cell + Vector2i(-3 - i / 8, (i % 8) - 4)), 0)
	for unit in scene.units: unit.selected = unit.owner_id == 0 and unit.type_id == "AHKX"
	scene.issue_attack({"kind": "unit", "id": theirs.unit_id})
	m.started_ms = -400000          # test hook: count the match as longer than 300 s so the ordinary award branch runs
	var waited := 0.0
	while not m.over and waited < 240.0:
		advance(scene, 1.0)
		waited += 1.0
	check(m.over and m.outcome.won and m.outcome.reason == "standard", "Standard Victory: %s" % m.outcome)
	check(not scene.combat.alive(scene.combat.fighters[theirs.unit_id]), "the computer hero is dead")
	check(scene.combat.fighters[theirs.unit_id].removed, "decided only after the hero's corpse is gone (hero flag counts until then)")
	check(m.enemy_heroes_killed[0] == 1 and m.stats[0].troops_killed >= 1, "kill counters")
	var before := int(scene.hero_match.profile.data.xp)
	var context: Dictionary = m.result_context(0, int(scene.hero_match.profile.data.level))
	check(not context.short_match and context.visibility_a and context.visibility_b and context.map_size == 128, "result context")
	var bonus := HeroRules.result_bonus(context)
	check(bonus > 0, "ordinary award %d" % bonus)
	# ---- parity pass 2: the end flow (0x4addc0 -> stinger -> 0x513eb0 box -> click -> 0x454560 results)
	check(scene.end_phase == "box" and scene.results_layer.visible and scene.end_box.visible and not scene.results_screen.visible, "no stinger without sound: the EZDV box at once, over the view")
	check(not scene.results_layer.get_node("Back").visible, "the view stays visible under the box")
	check(12 in scene.audio.speech_log, "the advisor's victory line (0x513eb0 -> 0x50f1b0(0xc))")
	var key_event := InputEventKey.new()
	key_event.keycode = KEY_ESCAPE
	key_event.pressed = true
	check(scene.results_input(key_event) and scene.end_phase == "box", "keys do not leave the box")
	var box_click := InputEventMouseButton.new()
	box_click.button_index = MOUSE_BUTTON_LEFT
	box_click.pressed = true
	box_click.position = scene.end_box_rect().get_center()
	check(scene.results_input(box_click) and scene.end_phase == "results" and scene.results_screen.visible, "a click on the box opens the results (0x574650)")
	var rs = scene.results_screen
	check(rs.canvas.control_text["PNL_VICTORYDEFEAT_NEW/STR_PARCHLARGE_500#0"] == "Victory" and rs.enabled("PNL_VICTORYDEFEAT_NEW/BUTT_ADVANCEDRESULTS#0"), "the Victory page with Advanced Results enabled")
	check(rs.click("PNL_VICTORYDEFEAT_NEW/BUTT_ADVANCEDRESULTS#0") and rs.screen == rs.ADV and rs.has_item("PNL_RESULTS_HERO/PB_ONE#0"), "Advanced Results opens PNL_RESULTS_MAIN with the hero page (0x449ce0)")
	check(rs.canvas.control_text["PNL_RESULTS_MAIN/STR_PARCHLARGE_L500#0"] == "Combat Results" and rs.data.players.size() == 2, "title and two players")
	check(rs.canvas.control_text["PNL_RESULTS_MAIN/STR_PARCHSMALL_L150#0"] == "Sir Test", "the local player's row first")
	check(rs.canvas.control_text["PNL_RESULTS_HERO/PB_ONE#0"] == str(m.hero_kills[0]) and rs.canvas.control_offset["PNL_RESULTS_HERO/IM_RESULTS_STATUS#1"] == Vector2i(0, 0), "hero kills; the computer hero's skull")
	check(rs.canvas.control_fill["PNL_RESULTS_HERO/PB_THREE#0"] < 0.0, "empty rows hidden")
	check(rs.grow_step(0) == 15 and rs.grow_step(60) == 75 and rs.grow_step(61) == 66 and rs.grow_step(91) == 92 and rs.grow_step(100) == 100, "bar growth +15 / +5 / +1 (0x44a890)")
	check(rs.click("PNL_RESULTS_MAIN/BUTT_RESULTS_UNITS#0") and rs.page == 2 and rs.canvas.control_frame["PNL_RESULTS_MAIN/IM_RESULTS_TABBAR#0"] == 2, "Units tab: the tab bar frame 2")
	check(rs.canvas.control_text["PNL_RESULTS_UNITS/PB_ONE#0"] == str(m.stats[0].troops_built) and rs.canvas.control_text["PNL_RESULTS_UNITS/PB_ONE#3"] == "-", "units produced; '-' in the local row's kills-by-side cell")
	check(int(rs.canvas.control_text["PNL_RESULTS_UNITS/PB_TWO#3"]) == int(scene.results_tracking[0].kills.get(1, 0)) and int(scene.results_tracking[0].kills.get(1, 0)) >= 1, "kills of side 1 by the local player")
	check(rs.click("PNL_RESULTS_MAIN/BUTT_RESULTS_RESOURCES#0") and rs.page == 1 and int(rs.canvas.control_text["PNL_RESULTS_RESOURCES/PB_ONE#9"]) >= 0, "Resources tab: in and out rows")
	check(rs.click("PNL_RESULTS_MAIN/BUTT_DONE_180#0") and rs.screen == rs.MAIN, "Done returns to the Victory page")
	# ---- writeback, exactly once

	scene.simulation_step(0.5)    # the scene stops on its own (physics) but a direct step must not change the result
	check(scene.accept_results(), "results accepted")
	stored = store.load_profile("test-knight")
	check(int(stored.data.xp) == before + bonus, "XP written: %d + %d" % [before, bonus])
	check(int(stored.data.level) == 1 + HeroRules.result_levels(1, before + bonus), "levels from the result queue")
	check(stored.data.history.battles_fought == 1 and stored.data.history.battles_won == 1, "battle counted once, win counted")
	check("test-match-1" in stored.data.applied_results, "result id stored")
	check(scene.accept_results(), "second accept is a no-op")
	check(int(store.load_profile("test-knight").data.xp) == before + bonus, "applies once (same session)")
	var other = load("res://simulation/hero_match.gd").new()
	other.bind(store.load_profile("test-knight"), load("res://simulation/entity_state.gd").new(1, "AHHX", 0, Vector2.ZERO))
	other.profile.data.applied_results.erase("test-match-1")     # a stale copy that has not seen the result
	check(not other.finish(store, "test-match-1", context, {}, true), "a stale copy cannot apply the result again")
	check(int(store.load_profile("test-knight").data.xp) == before + bonus, "stored XP unchanged after the stale attempt")
	var after_win = store.load_profile("test-knight")
	# ---- abandoned match: only the start save remains
	check(scene.start_skirmish(setup_for("test-knight"), "test-knight", store, "test-match-2"), "second match starts")
	advance(scene, 5.0)
	scene.end_skirmish()
	stored = store.load_profile("test-knight")
	check(stored.data.history.battles_fought == 2 and int(stored.data.xp) == int(after_win.data.xp), "abandoned: counted as fought, nothing else")
	# ---- quit: a defeat with the short award (0 XP under 300 s)
	check(scene.start_skirmish(setup_for("test-knight"), "test-knight", store, "test-match-3"), "third match starts")
	advance(scene, 3.0)
	# ---- parity pass 2: advisor triggers (AUDIO_RESEARCH.md "Parity pass 2"), called the way the signals call them
	var sound = scene.audio
	sound._bind_sources()                                    # the sound tick binds the match's signals
	sound.speech_log.clear()
	sound.speech_counter = 11
	sound._on_research_completed(0, "PHLX")
	check(sound.speech_log == [8], "research complete -> speech 8 (0x436500)")
	sound._on_research_completed(1, "PHLX")
	check(sound.speech_log == [8], "another player's research is silent")
	var my_hero = hero_of(scene, 0)
	var foe = hero_of(scene, 1)
	scene.camera.position = foe.position                     # the local hero is off screen
	sound.speech_counter = 11
	scene.combat.apply_damage("unit", my_hero.unit_id, 3, foe.unit_id)
	check(sound.speech_log.back() == 3, "own hero hit off screen (>= 50 hp) -> speech 3 (0x522860)")
	scene.combat.fighters[my_hero.unit_id].hp = 40
	scene.combat.apply_damage("unit", my_hero.unit_id, 1, -1)
	check(sound.speech_log.back() == 5, "own hero below 50 hp, any damage -> speech 5")
	scene.camera.position = my_hero.position
	var count_before: int = sound.speech_log.size()
	sound.speech_counter = 11
	scene.combat.apply_damage("unit", my_hero.unit_id, 3, foe.unit_id)
	check(sound.speech_log.size() == count_before, "on screen: no advisor line")
	scene.combat.fighters[my_hero.unit_id].hp = scene.combat.fighters[my_hero.unit_id].max_hp
	scene.quit_match()
	check(not scene.skirmish.over, "the quit waits 11 main-loop frames (0x514480)")
	for i in 11: scene.simulation_step(1.0 / 60.0)
	check(scene.skirmish.over and not scene.skirmish.outcome.won and scene.skirmish.outcome.reason == "quit", "quit ends as a defeat")
	check(scene.accept_results(), "quit results accepted")
	stored = store.load_profile("test-knight")
	check(stored.data.history.battles_won == 1 and int(stored.data.xp) == int(after_win.data.xp) and "test-match-3" in stored.data.applied_results, "quit: no win, 0 XP")
	# ---- defeat: the hero carries a quest item, dies, and the side has nothing left
	check(scene.start_skirmish(setup_for("test-knight"), "test-knight", store, "test-match-4"), "fourth match starts")
	check(scene.hero_match.receive_item(12, "test"), "item in the backpack")
	var own = hero_of(scene, 0)
	scene.combat.apply_damage("unit", own.unit_id, scene.combat.fighters[own.unit_id].hp + 1, -1)
	stored = store.load_profile("test-knight")
	check(stored.data.backpack == [{}, {}, {}, {}], "hero death: backpack lost and saved at once")
	check(scene.skirmish.hero_dead[0], "hero dead flag (0x709340)")
	scene.simulation_step(1.0 / 60.0)
	check(scene.production.population(0).maximum == scene.production.rules.KEEP_COMMAND_TABLE[0] - 2 + tower_limit(scene, 0), "dead hero gives no command term")
	# Parity pass 3: Knight Towers count for a Knights side (Building.cfg side flag), so the side is out only without them.
	advance(scene, 35.0)
	check(not scene.skirmish.over, "the own Knight Towers keep the Knights side in the match")
	destroy_towers(scene, 0)
	waited = 0.0
	while not scene.skirmish.over and waited < 60.0:
		advance(scene, 1.0)
		waited += 1.0
	check(scene.skirmish.over and not scene.skirmish.outcome.won and scene.skirmish.eliminated[0], "defeat after the hero's corpse is removed")
	check(scene.skirmish.outcome.ended_ms >= 30700, "not before the corpse is gone")
	check(scene.accept_results(), "defeat results accepted")
	stored = store.load_profile("test-knight")
	check(stored.data.history.battles_fought == 4 and stored.data.history.battles_won == 1, "four battles, one win")
	# ---- D1/D2: units in a mine (state 8, 0x51a130) or inside a building (+0x30, 0x5284f0) do not keep a side alive
	check(scene.start_skirmish(setup_for("test-knight"), "test-knight", store, "test-match-5"), "fifth match starts")
	own = hero_of(scene, 0)
	var mine_id := -1
	var best := 1000
	for id in scene.mines.mines:
		var d: int = Vector2(scene.mines.mines[id].anchor).distance_to(Vector2(own.cell))
		if d < best:
			best = d
			mine_id = id
	scene.mines.mines[mine_id].entity.owner = 0                 # test hook: the mine is already player 0's
	var worker = scene.add_unit("AHBX", scene.navigator.free_cell_near(own.cell + Vector2i(1, 1)), 0)
	var builder = scene.add_unit("AHBX", scene.navigator.free_cell_near(own.cell + Vector2i(2, 1)), 0)
	check(scene.order_enter_mine(worker, mine_id), "worker sent to the mine")
	waited = 0.0
	while not scene.in_mine(worker) and waited < 60.0:
		advance(scene, 0.5)
		waited += 0.5
	check(scene.in_mine(worker) and scene.mines.worker_count(mine_id) == 1, "the worker entered the mine")
	check(not scene.combat.alive(scene.combat.fighters[worker.unit_id]), "a worker in a mine is out of play (state 8)")
	scene._on_builder_hidden(builder.unit_id)                     # stands in for a builder inside an unfinished building
	check(scene.combat.fighters[builder.unit_id].flag_30, "a unit inside a building carries +0x30")
	scene.combat.apply_damage("unit", own.unit_id, scene.combat.fighters[own.unit_id].hp + 1, -1)
	destroy_towers(scene, 0)                                      # parity pass 3: Knight Towers count for the Knights side
	waited = 0.0
	while not scene.skirmish.over and waited < 60.0:
		advance(scene, 1.0)
		waited += 1.0
	check(scene.skirmish.over and not scene.skirmish.outcome.won, "a side with units only in a mine or inside a building loses")
	scene.end_skirmish()
	# ---- Army setup points (0x4406b0): the human's units from the army screen and the computer's purchase (0x445200)
	var army_setup := setup_for("test-knight")
	army_setup.options.army_points = 10
	Setup.set_kind(army_setup, 1, Setup.COMPUTER, 2)
	army_setup.army = {"AHFX": 1, "AHBX": 2}
	check(scene.start_skirmish(army_setup, "test-knight", store, "test-match-6"), "sixth match starts with army points")
	var by_owner := {0: [], 1: []}
	for unit in scene.units:
		if unit == null or not by_owner.has(unit.owner_id) or unit.type_id == "AHHX": continue
		by_owner[unit.owner_id].append(unit)
	var mine_types: Array = by_owner[0].map(func(u): return u.type_id)
	mine_types.sort()
	check(mine_types == ["AHBX", "AHBX", "AHFX"], "the bought Knight and two Peasants are placed")
	check(by_owner[0].all(func(u): return Vector2(u.cell).distance_to(Vector2(12, 64)) <= 12.0), "near the start (start + 1d10 - 5)")
	check(by_owner[1].size() >= 2 and by_owner[1][0].type_id == "AHBX", "the computer bought from the Knights table, a Peasant first")
	var computer_points := 0
	for u in by_owner[1]: computer_points += ArmySetup.cost(u.type_id)
	check(computer_points >= 5 and computer_points <= 14, "the computer's purchase is about its 10 points")
	scene.end_skirmish()
	scene.free()

func destroy_towers(scene, p: int):
	for b in scene.production.buildings.values().duplicate():
		if int(b.owner) == p and String(b.original_type_id).begins_with("BWT"): scene.combat.apply_damage("building", b.entity_id, int(b.hit_points) + 1, -1)

## The A column of the completed buildings `p` owns at the start (the map's towers).
func tower_limit(scene, p: int) -> int:
	var total := 0
	for b in scene.production.buildings.values():
		if int(b.owner) == p and not b.constructing: total += scene.production.rules.army_limit(b.original_type_id)
	return total
