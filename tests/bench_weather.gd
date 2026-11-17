extends SceneTree
## Frame time of the enhanced visuals weather in a big fight (not part of -Check; needs a window, the GPU is what is
## measured). A Knights vs Knights match on Desert Sands, 60 against 60 units fighting in view, the enhanced visuals on
## at their defaults; each weather at Heavy is measured right after a pass with the weather off, so the fight's own load
## changes little between the two. VSync and the frame cap are off. Prints mean / 95th percentile frame time (CPU wall
## clock between frames) and the GPU render time of the window's viewport; saves .local/weather_<kind>.png of each.
##   tools/run_guarded.ps1 -Script res://tests/bench_weather.gd -Windowed -QuitAfter 0

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const DisplayConfig = preload("res://core/display.gd")
const WeatherFx = preload("res://visuals/weather_fx.gd")
const WARM := 20
const FRAMES := 150

var scene

func _initialize():
	call_deferred("run")

func measure(label: String) -> Array:
	var rid := root.get_viewport_rid()
	for i in WARM: await process_frame
	var cpu: Array = []
	var gpu: Array = []
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		cpu.append((now - last) / 1000.0)
		last = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	cpu.sort()
	gpu.sort()
	var fighting := 0
	for u in scene.units:
		if not u.dying and not u.removed: fighting += 1
	var row := [label, mean(cpu), cpu[int(FRAMES * 0.95)], mean(gpu), gpu[int(FRAMES * 0.95)], fighting]
	print("%-10s cpu mean %6.2f ms  p95 %6.2f ms | gpu mean %6.2f ms  p95 %6.2f ms | units %d" % row)
	return row

static func mean(list: Array) -> float:
	var total := 0.0
	for v in list: total += float(v)
	return total / maxf(1.0, list.size())

func run():
	root.size = Vector2i(1920, 1009)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Settings.use_file("user://weather-bench-settings.cfg")
	DisplayConfig.load_settings()
	var store := Store.new("user://weather-bench-heroes")
	store.save_profile(Profile.create("bench-knight", "b"))
	scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "bench-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "bench-knight", store, "bench-weather")
	if scene.visibility.fog: scene.toggle_fog("fog")
	if scene.visibility.shroud: scene.toggle_fog("shroud")
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var centre := Vector2i(40, 80)
	for k in 120:
		var side := k % 2
		var cell := centre + Vector2i(k % 12 + (14 if side == 1 else 0), (k / 2) % 10)
		scene.add_unit(["AHKX", "AHBX", "AHMX"][k % 3], scene.navigator.free_cell_near(cell), side)
	scene.centre_view(scene.navigator.center(centre + Vector2i(13, 5)))
	# Each side marches on the other: the fight fills the view.
	for u in scene.units:
		u.selected = u.owner_id == 0
	scene.issue_move(scene.navigator.center(centre + Vector2i(20, 5)))
	DisplayConfig.set_visual("Enhanced", true)
	DisplayConfig.set_visual("WeatherStrength", 2)
	var results: Array = []
	for weather in [WeatherFx.RAIN, WeatherFx.SNOW, WeatherFx.FOG, WeatherFx.SAND]:
		DisplayConfig.set_visual("Weather", WeatherFx.NONE)
		scene.visuals.apply_settings()
		results.append(await measure("off"))
		DisplayConfig.set_visual("Weather", weather)
		scene.visuals.apply_settings()
		results.append(await measure(WeatherFx.NAMES[weather]))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/weather_%s.png" % WeatherFx.NAMES[weather])
	DisplayConfig.set_visual("Enhanced", false)
	scene.visuals.apply_settings()
	results.append(await measure("all off"))
	print("Weather bench done: %d passes" % results.size())
	scene.queue_free()
	quit(0)
