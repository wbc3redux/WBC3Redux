extends SceneTree
## Map wave 2 (milestone M-2, MAPS_RESEARCH.md "Wave 2"): load time, memory and frame time per map (not part of -Check; with
## a window the GPU is measured too). For each map: main.tscn load, match start (human + computers on the side records'
## races), static memory after the start, the fog overlay rebuild, the time of the ground scatter build, 20 s of simulation,
## and frame times in normal play with the view at a start (fog and shroud off): enhanced visuals off, on (defaults: Detailed + Plants), and on
## with Terrain "Detailed" only (no scatter). VSync and the frame cap are off.
##   tools/run_guarded.ps1 -Script res://tests/bench_maps.gd -Windowed -QuitAfter 0 [-UserArgs --maps=hills-to-climb]

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const DisplayConfig = preload("res://core/display.gd")
const MapData = preload("res://core/map_data.gd")
const WARM := 20
const FRAMES := 150

var scene

func _initialize():
	call_deferred("run")

func measure(label: String) -> void:
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
	print("  %-22s cpu mean %6.2f ms  p95 %6.2f ms | gpu mean %6.2f ms  p95 %6.2f ms" % [label, mean(cpu), cpu[int(FRAMES * 0.95)], mean(gpu), gpu[int(FRAMES * 0.95)]])

static func mean(list: Array) -> float:
	var total := 0.0
	for v in list: total += float(v)
	return total / maxf(1.0, list.size())

static func mb(bytes: float) -> String:
	return "%.0f MB" % (bytes / 1048576.0)

func run():
	var slugs := ["desert-sands", "the-lions-den", "hills-to-climb"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--maps="): slugs = Array(arg.get_slice("=", 1).split(","))
	root.size = Vector2i(1920, 1009)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	Settings.use_file("user://maps-bench-settings.cfg")
	DisplayConfig.load_settings()
	var store := Store.new("user://maps-bench-heroes")
	store.save_profile(Profile.create("bench-knight", "b"))
	var windowed := DisplayServer.get_name() != "headless"
	for slug in slugs:
		MapData.select(slug)
		var base := Performance.get_monitor(Performance.MEMORY_STATIC)
		var t := Time.get_ticks_msec()
		scene = load("res://battle/main.tscn").instantiate()
		root.add_child(scene)
		await process_frame
		var loaded := Time.get_ticks_msec() - t
		scene.enable_normal_play()
		Engine.max_fps = 0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var setup := Setup.defaults(MapData.map())
		setup.players[0].kind = Setup.HUMAN
		setup.players[0].hero_id = "bench-knight"
		for i in range(1, int(setup.sides)): Setup.set_kind(setup, i, Setup.COMPUTER, Setup.KEEP_LEVEL)
		t = Time.get_ticks_msec()
		scene.start_skirmish(setup, "bench-knight", store, "bench-" + slug)
		var started := Time.get_ticks_msec() - t
		t = Time.get_ticks_usec()
		scene.refresh_fog_overlay()
		var fog_ms := (Time.get_ticks_usec() - t) / 1000.0
		# A fresh ground scatter (the match's own may already be built when plants are on at the start).
		var scatter = preload("res://visuals/ground_scatter.gd").new()
		scatter.main = scene
		t = Time.get_ticks_msec()
		scatter.build()
		var scatter_ms := Time.get_ticks_msec() - t
		var chunk_count: int = scatter.chunks.size()
		scatter.free()
		t = Time.get_ticks_msec()
		DisplayConfig.set_visual("Enhanced", false)
		scene.visuals.apply_settings()
		scene.advance_seconds(20.0)
		var sim_ms := Time.get_ticks_msec() - t
		print("%s (%d x %d): scene %d ms, match start %d ms, static memory %s (+%s), fog overlay %.1f ms, scatter build %d ms (%d chunks), 20 s simulated in %d ms" % [
			MapData.name_of(slug), scene.collision.width, scene.collision.height, loaded, started,
			mb(Performance.get_monitor(Performance.MEMORY_STATIC)), mb(Performance.get_monitor(Performance.MEMORY_STATIC) - base),
			fog_ms, scatter_ms, chunk_count, sim_ms])
		if windowed:
			# The whole view lit (fog and shroud off), so the frame times include the terrain, scatter and objects under it.
			if scene.visibility.fog: scene.toggle_fog("fog")
			if scene.visibility.shroud: scene.toggle_fog("shroud")
			RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
			scene.centre_view(scene.navigator.center(setup.players[0].start + Vector2i(12, 10)))
			await measure("enhanced off")
			DisplayConfig.set_visual("Enhanced", true)
			DisplayConfig.set_visual("Terrain", 1)
			scene.visuals.apply_settings()
			await measure("enhanced, Detailed")
			DisplayConfig.set_visual("Terrain", 2)
			scene.visuals.apply_settings()
			await measure("enhanced, Detailed+Plants")
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.local/bench_%s.png" % slug)
			# The last side's start (on Hills to Climb at y > 4600 px: world depths shifted by MapData.depth_offset).
			scene.centre_view(scene.navigator.center(setup.players[int(setup.sides) - 1].start))
			for i in 30: await process_frame
			root.get_texture().get_image().save_png("res://.local/bench_%s_last_start.png" % slug)
		scene.end_skirmish()
		scene.free()
		await process_frame
	print("Maps bench done: %d maps" % slugs.size())
	quit(0)
