extends RefCounted
## main.gd's fixture captures (R-1 split of main.gd, no behaviour change): the --capture-* screenshot runs of the test
## fixtures (movement, objects, production, combat, encounters, skirmish) and the benchmark report. `main` is the scene.

const MainScript = preload("res://battle/main.gd")
const Navigation = preload("res://battle/navigation.gd")
const Benchmark = preload("res://devtools/movement_benchmark.gd")
const Visibility = preload("res://simulation/visibility.gd")
const HeroProfile = preload("res://simulation/hero_profile.gd")
const SkirmishSetup = preload("res://simulation/skirmish_setup.gd")
const HeroStore = preload("res://simulation/hero_store.gd")
const MapData = preload("res://core/map_data.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

func write_benchmark():
	var report: Dictionary = Benchmark.run(main.navigator)
	var file := FileAccess.open("res://.local/movement_benchmark.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	main.last_message = "Saved .local/movement_benchmark.json. Predictions from executable analysis; runtime observations still unmeasured."

func capture_preview():
	main.route_demo()
	main.collision_overlay.visible = true
	var seconds := 1.25
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-seconds="): seconds = float(arg.get_slice("=", 1))
	for i in range(roundi(seconds * 60)): main.simulation_step(1.0/60.0)
	main.set_physics_process(false)
	main.refresh_status()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://.local/movement_preview.png")
	main.get_tree().quit()

func capture_objects():
	main.camera.position = Vector2(2048,1536)
	main.camera.zoom = Vector2(0.28,0.28)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--object-focus="):
			var index := int(arg.get_slice("=",1))
			main.camera.position = main.map_objects[index].position + Vector2(0,80)
			main.camera.zoom = Vector2.ONE
	if "--overlap-fixture" in OS.get_cmdline_user_args():
		var object = main.map_objects[11]
		main.camera.position = object.position + Vector2(0,30)
		main.camera.zoom = Vector2(2,2)
		for i in range(main.units.size()):
			main.units[i].position = Vector2(object.position.x + (i % 3 - 1) * 26, object.z_index + (-24 if i < 3 else 12))
			main.units[i].selected = false
			main.units[i].advance(0)
	main.set_physics_process(false)
	main.show_paths = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://.local/objects_preview.png")
	main.get_tree().quit()

func capture_shot(name: String, log: Array):
	main.refresh_status()
	log.append("%s | t=%.1fs | %s | %s" % [name, main.simulation_time, main.production_text(), main.last_message])
	for node in main.building_nodes.values(): node.queue_redraw()
	main.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://.local/production_capture_%s.png" % name)

func capture_production():
	main.set_physics_process(false)
	var log: Array = []
	main.spawn_production_fixture()
	var keep = main.selected_building()
	main.camera.position = main.navigator.center(Vector2i(keep.left + 14, keep.top + 6))
	main.camera.zoom = Vector2(0.8, 0.8)
	var peasant = main.units.filter(func(u): return u.type_id == "AHBX")[0]
	var hero = main.units.filter(func(u): return u.type_id == "AHHX")[0]
	for u in main.units: u.selected = u == peasant
	await capture_shot("01_fixture", log)
	var site := main.find_site("BAGA", Vector2i(keep.left + 15, keep.top + 5))
	main.arm_build("BAGA")
	main.map_click(main.navigator.center(site))
	main.advance_seconds(0.5)
	log.append("order given: %s" % main.last_message)
	var waited := 0.0
	while not main.pending_builds.is_empty() and waited < 30.0:
		main.advance_seconds(0.25)
		waited += 0.25
	main.advance_seconds(2.0)
	await capture_shot("02_garrison_started", log)
	main.advance_seconds(14.0)
	await capture_shot("03_garrison_half", log)
	main.advance_seconds(14.5)
	await capture_shot("04_garrison_done", log)
	var garrison = main.production.buildings.values().filter(func(b): return b.original_type_id == "BAGA")[0]
	main.selected_building_id = garrison.entity_id
	main.queue_item("AHMX")
	main.queue_item("AHKX")
	main.queue_item("AHKX")
	main.production.set_rally(garrison.entity_id, Vector2i(garrison.left + 14, garrison.top + 8))
	await capture_shot("05_queued_with_rally", log)
	main.advance_seconds(21.0)
	await capture_shot("06_swordsman_walks_to_rally", log)
	main.cancel_job()
	await capture_shot("07_cancelled_current_job", log)
	main.selected_building_id = keep.entity_id
	main.queue_item("BKK1")
	main.queue_item("AHBX")
	await capture_shot("08_keep_upgrade_started", log)
	main.advance_seconds(61.0)
	await capture_shot("09_keep_level_two", log)
	for u in main.units: u.selected = u == hero
	var fletcher_site := main.find_site("BPFL", Vector2i(keep.left + 15, keep.top + 15))
	main.arm_build("BPFL")
	main.map_click(main.navigator.center(fletcher_site))
	waited = 0.0
	while not main.pending_builds.is_empty() and waited < 40.0:
		main.advance_seconds(0.25)
		waited += 0.25
	main.advance_seconds(3.0)
	await capture_shot("10_hero_builds_fletcher", log)
	main.release_builder()
	await capture_shot("11_builder_released_decaying", log)
	var file := FileAccess.open("res://.local/production_capture.txt", FileAccess.WRITE)
	file.store_string("
".join(log) + "
")
	file.close()
	main.get_tree().quit()

# Scripted walk-through of the combat fixture (same handlers as the buttons): numbered screenshots and a log in
# .local/combat_capture_*.png / .txt. Not part of the checks.
func capture_combat():
	main.set_physics_process(false)
	var log: Array = []
	main.spawn_combat_fixture()
	var layout := main.layout_cache
	var by_cell := func(cell: Vector2i):
		for unit in main.units:
			if unit.cell == cell: return unit
		return null
	for unit in main.units: unit.selected = false
	var duel_a = by_cell.call(layout.duel + Vector2i(-2, 0))
	var squire = by_cell.call(layout.ranged + Vector2i(-4, 0))
	var hero = main.units.filter(func(u): return u.type_id == "AHHX")[0]
	var hidden = by_cell.call(layout.watch + Vector2i(22, 6))
	duel_a.selected = true
	main.attack_nearest_selected()
	duel_a.selected = false
	squire.selected = true
	main.attack_nearest_selected()
	squire.selected = false
	for unit in main.units:
		if unit.owner_id == 0 and unit.type_id != "AHMX" and unit.position.distance_to(main.navigator.center(layout.hero)) < 300: unit.selected = true
	main.attack_nearest_selected()
	for unit in main.units: unit.selected = false
	for unit in main.units:
		if unit.owner_id == 0 and unit.position.distance_to(main.navigator.center(layout.siege)) < 300: unit.selected = true
	var garrison_id: int = main.production.buildings.keys()[0]
	main.issue_attack({"kind": "building", "id": garrison_id})
	for unit in main.units: unit.selected = false
	main.camera.zoom = Vector2(1.4, 1.4)
	main.camera.position = main.navigator.center(layout.duel)
	await capture_combat_shot("01_duel_start", log)
	main.advance_seconds(0.9)
	main.camera.position = main.navigator.center(layout.duel)
	await capture_combat_shot("02_duel_first_swings", log)
	main.camera.position = main.navigator.center(layout.ranged)
	main.advance_seconds(0.3)
	await capture_combat_shot("03_squire_missile", log)
	main.advance_seconds(4.0)
	main.camera.position = main.navigator.center(layout.hero)
	await capture_combat_shot("04_hero_fight", log)
	main.camera.position = main.navigator.center(layout.siege)
	await capture_combat_shot("05_siege", log)
	main.advance_seconds(12.0)
	main.camera.position = main.navigator.center(layout.duel)
	await capture_combat_shot("06_duel_after_16s", log)
	main.camera.position = main.navigator.center(layout.watch)
	await capture_combat_shot("07_watch_fog", log)
	main.advance_seconds(6.0)
	main.camera.position = main.navigator.center(layout.watch)
	await capture_combat_shot("08_watch_acquired", log)
	main.advance_seconds(60.0)
	main.camera.position = main.navigator.center(layout.hero)
	await capture_combat_shot("09_hero_fight_after_80s", log)
	var xp_before_siege := int(main.hero_match.profile.data.xp)
	var waited := 0
	while main.production.building(garrison_id) != null and waited < 600:
		main.advance_seconds(1.0)
		waited += 1
	log.append("garrison destroyed: %s at t=%.1fs; hero xp %d -> %d (level %d)" % [main.production.building(garrison_id) == null, main.simulation_time,
		xp_before_siege, int(main.hero_match.profile.data.xp), int(main.hero_match.profile.data.level)])
	# Fog latency (8-fix): a fresh Swordsman walks to 6 cells from the hidden opponent, waits, and walks back; the log lists when the
	# opponent's cell enters/leaves the scout's sight disc and when the opponent is drawn/hidden (sampled every 25 ms).
	main.combat.auto_acquire = false
	var start_cell: Vector2i = main.find_open_area(hidden.cell + Vector2i(-22, 0), 1, 1)
	var scout = main.add_unit("AHKX", start_cell, 0)
	var walk_to := func(cell: Vector2i):
		var target: Vector2 = main.navigator.center(cell)
		scout.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": scout.base_speed, "individual": true}, "replace")
	var watch_fog := func(seconds: float):
		var in_sight_before := false
		var drawn_before: bool = hidden.visible
		var since := -1.0
		for i in roundi(seconds / 0.025):
			main.advance_seconds(0.025)
			var d: Vector2i = hidden.cell - scout.cell
			var in_sight := int(sqrt(float(d.x * d.x + d.y * d.y))) <= Visibility.DEFAULT_RADIUS
			if in_sight != in_sight_before:
				log.append("fog t=%.3fs opponent %s the scout's disc (scout %s)" % [main.simulation_time, "enters" if in_sight else "leaves", scout.cell])
				since = main.simulation_time
				in_sight_before = in_sight
			if hidden.visible != drawn_before:
				log.append("fog t=%.3fs opponent %s, %.0f ms after the disc change" % [main.simulation_time, "drawn" if hidden.visible else "hidden", (main.simulation_time - since) * 1000.0])
				drawn_before = hidden.visible
	walk_to.call(hidden.cell + Vector2i(-6, 0))
	watch_fog.call(14.0)
	main.camera.position = main.navigator.center(hidden.cell)
	await capture_combat_shot("10_fog_scout_near", log)
	walk_to.call(start_cell)
	watch_fog.call(14.0)
	await capture_combat_shot("11_fog_scout_gone", log)
	for f in main.combat.fighters.values():
		log.append("fighter %d %s owner %d %s hp %d/%d cell %s order %s orders %d visible %s" % [f.id, f.type_id, f.owner, f.state, f.hp, f.max_hp, main.units[f.id].cell,
			"-" if f.order == null else str(f.order.target_kind) + str(f.order.target_id), main.units[f.id].orders.size(), main.units[f.id].visible])
	var file := FileAccess.open("res://.local/combat_capture.txt", FileAccess.WRITE)
	file.store_string("\n".join(log) + "\n")
	file.close()
	main.get_tree().quit()

func capture_combat_shot(name: String, log: Array):
	main.refresh_status()
	log.append("%s | t=%.1fs | %s | %s" % [name, main.simulation_time, main.combat_text(), main.last_message])
	main.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://.local/combat_capture_%s.png" % name)

# Scripted walk-through of the Encounters fixture (same handlers as the buttons): numbered screenshots and a log in
# .local/encounters_capture_*.png / .txt. Not part of the checks.
func capture_encounters():
	main.set_physics_process(false)
	var log: Array = []
	main.spawn_encounters_fixture()
	var hero = main.units[main.hero_unit_id]
	await capture_encounter_shot("01_fixture", log)
	# Walk the hero next to the Mausoleum and use the quest buttons.
	var goal := Vector2i(-1, -1)
	var best := 1000
	for cell in main.navigator.building_cells:
		if main.navigator.building_cells[cell] != main.mausoleum_id: continue
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var next: Vector2i = cell + d
			if main.navigator.is_passable(next) and Navigation.chebyshev(next, hero.cell) < best:
				best = Navigation.chebyshev(next, hero.cell)
				goal = next
	for unit in main.units: unit.selected = unit == hero
	main.issue_move(main.navigator.center(goal))
	var waited := 0.0
	while not main.hero_near_mausoleum() and waited < 60.0:
		main.advance_seconds(0.5)
		waited += 0.5
	var visit := main.quest_visit()
	log.append("visit: %s" % [visit.get("mode", "")])
	if visit.get("mode", "") in ["unsupported", "offer", "instant"] and int(visit.record.type) != 0:
		var giver: Dictionary = main.encounters.givers[main.mausoleum_id]
		giver.record = main.encounters.quest_records()[7]           # harness: show a completable resource quest as well
		giver.picked = true                                    # keep it through the next visit (as if accepted elsewhere)
		log.append("harness: Mausoleum record set to 7 (Fair Trade) for the completion shot")
	main.quest_complete()
	main.camera.position = hero.position
	await capture_encounter_shot("02_mausoleum_quest", log)
	# West: the group stands beside its own Dwarven Towers (no shots). East: the enemy's Swarm Towers shoot the group there.
	main.advance_seconds(8.0)
	main.camera.position = main.navigator.center(Vector2i(28, 63))
	await capture_encounter_shot("03_own_west_towers_quiet", log)
	main.camera.position = main.navigator.center(Vector2i(98, 63))
	await capture_encounter_shot("03b_enemy_east_towers_fire", log)
	# Gnoll Lair: force a wave, let the Gnolls meet the southern group, then destroy the lair.
	main.lair_wave_test()
	main.advance_seconds(3.0)
	main.camera.position = main.navigator.center(Vector2i(58, 44))
	await capture_encounter_shot("04_gnoll_wave", log)
	main.advance_seconds(15.0)
	await capture_encounter_shot("05_gnolls_fight", log)
	main.destroy_lair_test()
	main.advance_seconds(1.0)
	await capture_encounter_shot("06_lair_destroyed_boss", log)
	main.camera.position = main.navigator.center(Vector2i(91, 12))
	main.advance_seconds(20.0)
	await capture_encounter_shot("07_animals_north_east", log)
	var file := FileAccess.open("res://.local/encounters_capture.txt", FileAccess.WRITE)
	file.store_string("\n".join(log) + "\n")
	file.close()
	main.get_tree().quit()

func capture_encounter_shot(name: String, log: Array):
	main.refresh_status()
	log.append("%s | t=%.1fs | %s | %s" % [name, main.simulation_time, main.combat_text(), main.last_message])
	main.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://.local/encounters_capture_%s.png" % name)

# Scripted walk-through with the real renderer (same handlers as the buttons): a match from the setup defaults with a
# copied test hero, the start, a test hook that gives player 0 overwhelming force, the victory and the results screen.
# Screenshots and a log in .local/skirmish_capture_*.png / .txt. Not part of the checks; never touches user://heroes.
func capture_skirmish():
	main.set_physics_process(false)
	var log: Array = []
	var store = HeroStore.new("user://skirmish-capture-heroes")
	var profile = HeroProfile.create("capture-knight", "Sir Capture")
	store.save_profile(profile)
	var map_data: Dictionary = MapData.map()
	var setup := SkirmishSetup.defaults(map_data)
	for i in 2: SkirmishSetup.set_race(setup, i, SkirmishSetup.KNIGHT)   # the capture walks the Knights match of 10a
	setup.players[0].kind = SkirmishSetup.HUMAN
	setup.players[0].hero_id = profile.data.id
	SkirmishSetup.set_kind(setup, 1, SkirmishSetup.COMPUTER)
	main.start_skirmish(setup, profile.data.id, store, "capture-match")
	log.append("start: resources %s, command %s, heroes %s" % [main.economy.resources(0), main.production.population(0), main.match_heroes.keys()])
	main.advance_seconds(0.6)                                   # the first fog sweep runs 500 ms into the match
	await capture_match_shot("01_start_west", log)
	main.advance_seconds(3.0)
	main.camera.position = main.units.filter(func(u): return u.type_id == "AHHX" and u.owner_id == 1)[0].position
	await capture_match_shot("02_opponent_start_east", log)
	# Test hook: overwhelming force next to the opponent's hero.
	var enemy_hero = main.units.filter(func(u): return u.type_id == "AHHX" and u.owner_id == 1)[0]
	for i in 40: main.add_unit("AHKX", main.navigator.free_cell_near(enemy_hero.cell + Vector2i(-3 - i / 8, (i % 8) - 4)), 0)
	for unit in main.units: unit.selected = unit.owner_id == 0 and unit.type_id == "AHKX"
	main.issue_attack({"kind": "unit", "id": enemy_hero.unit_id})
	var waited := 0.0
	while not main.skirmish.over and waited < 240.0:
		main.advance_seconds(0.5)
		waited += 0.5
		if waited == 6.0: await capture_match_shot("03_attack", log)
	log.append("outcome %s after %.1f s; log %s" % [main.skirmish.outcome, main.simulation_time, main.skirmish.log])
	await capture_match_shot("04_results_before_continue", log)
	main.accept_results()
	log.append("hero after writeback: level %d xp %d battles %d won %d" % [int(main.hero_match.profile.data.level), int(main.hero_match.profile.data.xp),
		int(main.hero_match.profile.data.history.battles_fought), int(main.hero_match.profile.data.history.battles_won)])
	await capture_match_shot("05_results_saved", log)
	var file := FileAccess.open("res://.local/skirmish_capture.txt", FileAccess.WRITE)
	file.store_string("\n".join(log) + "\n")
	file.close()
	for filename in DirAccess.get_files_at("user://skirmish-capture-heroes"): DirAccess.remove_absolute("user://skirmish-capture-heroes".path_join(filename))
	main.get_tree().quit()

func capture_match_shot(name: String, log: Array):
	main.refresh_status()
	log.append("%s | t=%.1fs | %s | %s | %s" % [name, main.simulation_time, main.production_text(), main.match_text(), main.last_message])
	main.queue_redraw()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png("res://.local/skirmish_capture_%s.png" % name)

