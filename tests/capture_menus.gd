extends SceneTree
## Milestone 11-menus captures with the real renderer (not part of -Check): the loading screen, the in-game control
## panel with a selection, the build page, the game menu, the options dialog, the resign box and the results screen of a
## resigned match, into .local/menu_capture_1*.png. Copied profile and settings; run with a window:
##   Godot --path . --script res://tests/capture_menus.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/menu_capture_%s.png" % name)

func run():
	root.size = Vector2i(1920, 1080)
	Settings.use_file("user://menu-capture-settings.cfg")
	var loading = load("res://menus/loading_screen.tscn").instantiate()
	loading.set_process(false)
	root.add_child(loading)
	loading.progress = 0.4
	loading.refresh()
	await shot("10_loading")
	loading.queue_free()
	var directory := "user://menu-capture-heroes-2"
	var store := Store.new(directory)
	var profile = Profile.create("capture-panel", "Sir Capture")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-panel"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	scene.start_skirmish(setup, "capture-panel", store, "capture-panel-match")
	for i in 40: scene.simulation_step(1.0 / 30.0)
	scene.hud.select_hero()
	await shot("11_hud_hero")
	scene.hud.page = "build"
	await shot("12_hud_build_page")
	scene.hud.page = "units"
	for u in scene.units: u.selected = false
	scene.hud.open_dialog("menu")
	await shot("13_game_menu")
	scene.hud.open_dialog("options")
	await shot("14_options_dialog")
	scene.hud.open_dialog("resign")
	await shot("15_resign_box")
	scene.hud.box_press(1)
	for i in 20: scene._physics_process(1.0 / 60.0)
	await shot("16_results")
	scene.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute("user://menu-capture-settings.cfg")
	quit()
