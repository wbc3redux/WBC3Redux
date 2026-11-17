extends SceneTree
## Native resolution captures with the real renderer (not part of -Check; DELIBERATE MODERN CHANGE, display.gd): a Knights
## match at several window sizes with the hero selected, the in-game options dialog and the options screen over the match, into
## .local/native_<w>x<h>_*.png. Copied profile and settings; run with a window:
##   Godot --path . --script res://tests/capture_native.gd -- --windowed
## Sizes larger than the desktop may be clamped by the system; the file names carry the size actually rendered.

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const DisplayConfig = preload("res://core/display.gd")
const SIZES := [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(1366, 768), Vector2i(3840, 2160)]

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://.local/native_%dx%d_%s.png" % [image.get_width(), image.get_height(), name])

func run():
	Settings.use_file("user://native-capture-settings.cfg")
	DisplayConfig.load_settings()
	DisplayConfig.overrides = {"WindowMode": DisplayConfig.WINDOWED}
	root.mode = Window.MODE_WINDOWED
	root.borderless = true
	root.position = Vector2i.ZERO
	root.size = SIZES[0]
	var directory := "user://native-capture-heroes"
	var store := Store.new(directory)
	store.save_profile(Profile.create("capture-native", "Sir Native"))
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-native"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, 0)
	scene.start_skirmish(setup, "capture-native", store, "capture-native-match")
	for i in 40: scene.simulation_step(1.0 / 30.0)
	for size in SIZES:
		root.size = size
		await process_frame
		scene.hud.select_hero()
		await shot("1_match")
		scene.hud.open_options()
		await shot("2_options")
		scene.hud.options_screen().click("PNL_GAMEOPTIONS/BUTT_CANCEL_STARTUP#0")
		for u in scene.units: u.selected = false
	DisplayConfig.display.BattlefieldView = 2
	root.size = Vector2i(3440, 1440)
	scene.apply_view_scale()
	await shot("3_ultrawide_view")
	DisplayConfig.display.BattlefieldView = 1
	root.size = SIZES[0]
	scene.apply_view_scale()
	scene.hud.open_options()
	await shot("4_options_over_match")
	scene.hud.options_screen().select_page(3)
	await shot("5_options_advanced")
	scene.hud.options_screen().click("PNL_GAMEOPTIONS/BUTT_CANCEL_STARTUP#0")
	scene.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute("user://native-capture-settings.cfg")
	quit()
