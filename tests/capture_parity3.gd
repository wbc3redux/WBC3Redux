extends SceneTree
## Parity pass 3 captures with the real renderer (not part of -Check), for a side-by-side look with the original's
## screenshots: the match start of a Knights vs Knights skirmish on Desert Sands at 1920x1009 (army counter, resource
## boxes, Knight Towers, the hero), the build dialog, and a running conversion (info rows, the order marker). Copied
## profile and settings; written to .local/parity3_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_parity3.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/parity3_%s.png" % name)

func run():
	root.size = Vector2i(1920, 1009)
	Settings.use_file("user://parity3-capture-settings.cfg")
	var store := Store.new("user://parity3-capture-heroes")
	var profile = Profile.create("capture-knight", "c")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-knight", store, "capture-parity3")
	for i in 20: scene.simulation_step(1.0 / 30.0)
	var hero = scene.unit_by_id(scene.hero_unit_id)
	scene.centre_view(hero.position + Vector2(160, 0))
	for u in scene.units: u.selected = false
	await shot("1_start")
	scene.hud.select_hero()
	scene.centre_view(hero.position + Vector2(160, 0))
	scene.hud.press_icon(0x1f)
	await shot("2_build_dialog")
	scene.hud.close_dialog()
	# A neutral mine next to the hero (test hook) so the Convert order finds something in reach.
	var nearest := -1
	var best := 1.0e9
	for id in scene.mines.mines:
		var d: float = Vector2(scene.mines.mines[id].anchor).distance_to(Vector2(hero.cell))
		if d < best:
			best = d
			nearest = id
	scene.order_convert(hero, "mine", nearest)
	for i in 1800:
		scene.simulation_step(1.0 / 30.0)
		if scene.conversions.converting(hero.unit_id): break
	for i in 150: scene.simulation_step(1.0 / 30.0)
	for u in scene.units: u.selected = u == hero
	scene.centre_view(hero.position)
	scene.order_marker_until_ms = Time.get_ticks_msec() + 5000
	await shot("3_converting")
	scene.queue_free()
	quit(0)
