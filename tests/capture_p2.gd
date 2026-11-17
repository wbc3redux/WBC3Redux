extends SceneTree
## P-2 captures with the real renderer (not part of -Check): a building under fog with palette 6, the order marker after
## a move and the lines while Shift is held, the pending job's picture, Couatl's Wrath meteors (flight and landing), the
## Firebomb blast, rain with a storm flash, the Mana Potion / Healing floats. Writes .local/p2_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_p2.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/p2_%s.png" % name)
	print("shot ", name)

func steps(scene, seconds: float):
	for i in int(seconds * 30.0): scene.simulation_step(1.0 / 30.0)

func shift(on: bool):
	var e := InputEventKey.new()
	e.keycode = KEY_SHIFT
	e.physical_keycode = KEY_SHIFT
	e.pressed = on
	Input.parse_input_event(e)

func run():
	root.size = Vector2i(1600, 900)
	Settings.use_file("user://p2-capture-settings.cfg")
	var store := Store.new("user://p2-capture-heroes")
	var profile = Profile.create("capture-p2", "c")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-p2"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-p2", store, "capture-p2")
	steps(scene, 1.0)
	var hero = scene.unit_by_id(scene.hero_unit_id)
	# 1. Palette 6: the enemy keep explored but not visible, and an own building beside the hero for comparison.
	var keep = null
	for b in scene.production.buildings.values():
		if int(b.owner) == 1 and keep == null: keep = b
	if keep != null and scene.visibility != null:
		var v = scene.visibility
		v.ensure(0)
		for y in range(keep.top - 6, keep.top + 8):
			for x in range(keep.left - 8, keep.left + 10):
				if x >= 0 and y >= 0 and x < v.width and y < v.height:
					v.explored[0][y * v.width + x] = 1
					v.visible[0][y * v.width + x] = 0
		scene.apply_fog_to_nodes()
		scene.refresh_fog_overlay()
		scene.centre_view(keep.position)
		var node = scene.building_nodes.get(keep.entity_id)
		print("keep ", keep.original_type_id, " fogged ", node.fogged if node != null else "?")
		await shot("1_fog_palette")
		v.fog = false
		scene.apply_fog_to_nodes()
		scene.refresh_fog_overlay()
		await shot("1b_fog_off")
		v.fog = true
	if scene.visibility != null: scene.visibility.set("fog", false)
	scene.apply_fog_to_nodes()
	scene.refresh_fog_overlay()
	# 2. The order marker: a move, then the lines while Shift is held.
	scene.centre_view(hero.position)
	hero.selected = true
	scene.order_move(hero.position + Vector2(160, 72), {"shift": false, "alt": false, "ctrl": false})
	await shot("2_move_marker")
	scene.order_move(hero.position + Vector2(260, -48), {"shift": true, "alt": false, "ctrl": false})
	shift(true)
	for i in 6: await process_frame
	print("order entries ", scene.order_layer.entries.size(), " held ", scene.order_layer.held)
	await shot("2b_shift_lines")
	shift(false)
	# 3. The pending job's picture: an own building with a pending job, selected.
	var site = null
	for b in scene.production.buildings.values():
		if int(b.owner) == 0 and not b.constructing and not scene.production.menu_for(b).is_empty(): site = b
	if site != null:
		hero.selected = false
		site.job_item = ""
		site.job_pending = true
		scene.pick_object(site)
		await shot("3_pending_job")
		site.job_pending = false
	# 4. Couatl's Wrath meteors round a point beside the hero, then the landing.
	var centre: Vector2i = hero.cell + Vector2i(6, 0)
	for o in [Vector2i(-3, -2), Vector2i(3, -2), Vector2i(0, 3)]:
		scene.combat.launch_meteor(centre, centre + o)
	steps(scene, 0.25)
	await shot("4_meteor_flight")
	var landed := false
	for i in 120:
		scene.simulation_step(1.0 / 30.0)
		if scene.combat.missiles.all(func(m): return int(m.index) >= int(m.steps) - 1):
			landed = true
			break
	steps(scene, 0.1)
	print("meteors landed ", landed, " bursts ", scene.effects.bursts.bursts.size())
	await shot("5_meteor_landing")
	# 5. The Firebomb blast's bursts.
	scene.combat.race_event.emit("blast", {"cell": hero.cell + Vector2i(-4, 1)})
	steps(scene, 0.2)
	await shot("6_blast")
	# 6. Floats: Mana Potion and Healing over the hero.
	var f = scene.combat.fighters[hero.unit_id]
	f["mana"] = 0
	scene.combat.spells.floated.emit({"id": hero.unit_id, "line": 0x45f, "value": 15, "colour": 3, "ms": 1000})
	scene.effects._on_cast_done({"result": {"healed": [{"kind": "unit", "id": hero.unit_id, "hp": 120, "from": 100}]}})
	steps(scene, 0.8)
	await shot("7_floats")
	# 7. Rain with a storm (fog off, so the flashes run).
	scene.day_night.set_rain(0x96, true)
	for i in 60: scene.simulation_step(1.0 / 30.0)
	for i in 4: await process_frame
	print("raining ", scene.day_night.raining, " drops ", scene.day_night.drops)
	await shot("8_rain")
	var flashed := false
	for i in 900:
		scene.simulation_step(1.0 / 30.0)
		await process_frame
		if scene.rain_layer != null and int(scene.rain_layer.flash_level) >= 0:
			flashed = true
			break
	print("flash ", flashed)
	await shot("9_storm_flash")
	quit()
