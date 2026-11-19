extends SceneTree
## Frame profile of a late-game match in a real window (not part of -Check; rendering is measured, unlike profile_sim.gd).
## A six-side computer match is stepped forward to --minutes of game time, then the match runs normally (60 simulation
## steps a second, VSync off, no frame cap) through a list of phases of --seconds each. Per phase: the frame time, the
## time inside main.gd's _physics_process and _process and the HUD's _process (called from here with a clock round them),
## the renderer's own CPU / GPU time, draw calls and memory. At the end, the cost of single presentation calls.
##   tools/run_guarded.ps1 -Windowed -QuitAfter 0 -Script res://tests/profile_frames.gd -UserArgs '--minutes=10'

const Setup = preload("res://simulation/skirmish_setup.gd")
const Settings = preload("res://simulation/game_settings.gd")
const MapData = preload("res://core/map_data.gd")
const DisplayConfig = preload("res://core/display.gd")

var scene
var measuring := false
var physics_us := PackedInt32Array()
var process_us := PackedInt32Array()
var hud_us := PackedInt32Array()
var frame_us := PackedInt32Array()
var render_cpu := PackedFloat32Array()
var render_gpu := PackedFloat32Array()
var draws := PackedInt32Array()
var steps_in_frame := 0
var steps_per_frame := PackedInt32Array()
var last_frame := 0
var drive := false                  # this script calls the scene's and the HUD's callbacks itself
var sim_on := true

func us() -> int:
	return Time.get_ticks_usec()

func _initialize():
	call_deferred("run")

func _physics_process(delta: float) -> bool:
	if drive and sim_on and scene != null:
		var t := us()
		scene._physics_process(delta)
		if measuring:
			physics_us.append(us() - t)
			steps_in_frame += 1
	return false

func _process(delta: float) -> bool:
	if drive and scene != null:
		var t := us()
		scene._process(delta)
		var mid := us()
		if scene.hud != null and scene.hud.visible: scene.hud._process(delta)
		var end := us()
		if measuring:
			process_us.append(mid - t)
			hud_us.append(end - mid)
			if last_frame > 0: frame_us.append(end - last_frame)
			steps_per_frame.append(steps_in_frame)
			steps_in_frame = 0
			var vp := root.get_viewport_rid()
			render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu())
			render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		last_frame = end
	return false

static func stats(values, scale: float = 1.0) -> String:
	var a: Array = Array(values)
	if a.is_empty(): return "-"
	a.sort()
	var sum := 0.0
	for v in a: sum += v
	return "mean %.2f  p50 %.2f  p95 %.2f  p99 %.2f  max %.2f" % [sum / a.size() * scale, a[a.size() / 2] * scale,
		a[int(a.size() * 0.95)] * scale, a[int(a.size() * 0.99)] * scale, a[-1] * scale]

static func mean(values) -> float:
	var sum := 0.0
	for v in values: sum += v
	return sum / maxi(1, values.size())

func phase(name: String, seconds: float):
	for i in 20: await process_frame                  # settle after the switch
	for a in [physics_us, process_us, hud_us, frame_us, render_cpu, render_gpu, draws, steps_per_frame]: a.clear()
	last_frame = 0
	steps_in_frame = 0
	measuring = true
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until: await process_frame
	measuring = false
	var visible_units := 0
	var view := Rect2(scene.view_top_left(), scene.view_world_size())
	for u in scene.units:
		if not u.removed and u.visible and view.has_point(u.position): visible_units += 1
	print("PHASE %s: %d frames in %.0f s (%.0f fps), units %d (%d in view)" % [name, frame_us.size(), seconds, frame_us.size() / seconds, scene.units.size(), visible_units])
	print("  frame ms          %s" % stats(frame_us, 0.001))
	print("  sim step ms       %s   (%d steps, %.2f per frame, most in one frame %d)" % [stats(physics_us, 0.001), physics_us.size(), mean(steps_per_frame), Array(steps_per_frame).max() if not steps_per_frame.is_empty() else 0])
	print("  main _process ms  %s" % stats(process_us, 0.001))
	print("  hud _process ms   %s" % stats(hud_us, 0.001))
	print("  render cpu ms     %s" % stats(render_cpu))
	print("  render gpu ms     %s" % stats(render_gpu))
	print("  draw calls        %s" % stats(draws))
	var sim_share := mean(physics_us) * physics_us.size() / maxf(1.0, mean(frame_us) * frame_us.size())
	print("  share of wall time: sim %.0f %%, main _process %.0f %%, hud _process %.0f %%, rest (drawing, engine) %.0f %%" % [sim_share * 100.0,
		mean(process_us) / maxf(1.0, mean(frame_us)) * 100.0, mean(hud_us) / maxf(1.0, mean(frame_us)) * 100.0,
		(1.0 - sim_share - (mean(process_us) + mean(hud_us)) / maxf(1.0, mean(frame_us))) * 100.0])

func memory(label: String):
	print("MEMORY %s: static %.0f MB, video %.0f MB, textures %.0f MB, objects %d, nodes %d" % [label,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])

func bench(label: String, call: Callable, times: int = 100):
	var t := us()
	for i in times: call.call()
	print("  %-34s %8.1f us a call" % [label, float(us() - t) / times])

## The local player's unit with the most shown units round it: where a player would be looking in a fight.
func busiest_point(any_owner: bool = false) -> Vector2:
	var best := Vector2.ZERO
	var best_count := -1
	var shown: Array = scene.units.filter(func(u): return not u.removed and u.visible and not u.inside_building)
	for u in shown:
		if not any_owner and u.owner_id != scene.local_player: continue
		var n := 0
		for o in shown:
			if absf(o.position.x - u.position.x) < 700.0 and absf(o.position.y - u.position.y) < 400.0: n += 1
		if n > best_count:
			best_count = n
			best = u.position
	return best

func run():
	var minutes := 10.0
	var seconds := 10.0
	var slug := "forest-lakes"
	var size := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
		if arg.begins_with("--seconds="): seconds = float(arg.get_slice("=", 1))
		if arg.begins_with("--map="): slug = arg.get_slice("=", 1)
		if arg.begins_with("--window="): size = Vector2i(int(arg.get_slice("=", 1).get_slice("x", 0)), int(arg.get_slice("=", 1).get_slice("x", 1)))
	Settings.use_file("user://profile-settings.cfg")
	DisplayConfig.set_visual("Enhanced", false)
	root.size = size
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	print("profile: window %s, renderer %s, adapter %s" % [root.size, RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])
	memory("before the match")
	MapData.select(slug)
	var t := us()
	scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var setup := Setup.defaults(MapData.map())
	var sides := int(setup.sides)
	var levels := [3, 6, 4, 5, 2, 2]
	for i in sides: Setup.set_kind(setup, i, Setup.COMPUTER, levels[i])
	if not scene.start_skirmish(setup, "", null, "profile"):
		printerr("profile: the match did not start")
		quit(1)
		return
	await process_frame
	await process_frame
	print("LOAD: scene and match start %.2f s (map %s, %d sides, races %s)" % [(us() - t) / 1000000.0, slug, sides, str(range(sides).map(func(i): return int(setup.players[i].race)))])
	memory("match started")
	# Forward to the late game: the same step the match runs, without waiting for real time (a frame drawn every 60 steps).
	scene.set_physics_process(false)
	scene.set_process(false)
	if scene.hud != null: scene.hud.set_process(false)
	var total := roundi(minutes * 3600.0)
	t = us()
	for i in total:
		scene.simulation_step(1.0 / 60.0)
		if i % 60 == 59: await process_frame
		if i % 7200 == 7199: print("forward: %d min of game time, %d units, %.0f s real" % [(i + 1) / 3600, scene.units.size(), (us() - t) / 1000000.0])
		if scene.skirmish != null and scene.skirmish.over: break
	print("FORWARD: %.1f game minutes in %.0f s real, %d units, %d buildings, %d map objects" % [scene.simulation_time / 60.0, (us() - t) / 1000000.0,
		scene.units.size(), scene.building_nodes.size(), scene.map_objects.size()])
	memory("late game")
	drive = true
	scene.centre_view(busiest_point())
	await phase("1 normal play, original look", seconds)
	sim_on = false
	await phase("2 simulation stopped (drawing only)", seconds)
	if scene.hud != null: scene.hud.visible = false
	await phase("3 simulation stopped, HUD hidden", seconds)
	if scene.hud != null: scene.hud.visible = true
	sim_on = true
	scene.visuals.set_enabled(true)
	await phase("4 normal play, Enhanced Visuals on (defaults)", seconds)
	sim_on = false
	await phase("5 Enhanced on, simulation stopped", seconds)
	DisplayConfig.set_visual("SoftShadows", false)
	scene.visuals.apply_settings()
	await phase("6 Enhanced on without soft shadows, simulation stopped", seconds)
	DisplayConfig.set_visual("SoftShadows", true)
	DisplayConfig.set_visual("Grade", 0)
	scene.visuals.apply_settings()
	await phase("7 Enhanced on without colour grade, simulation stopped", seconds)
	DisplayConfig.set_visual("Grade", 1)
	DisplayConfig.set_visual("Terrain", 0)
	scene.visuals.apply_settings()
	await phase("8 Enhanced on without terrain detail and plants, simulation stopped", seconds)
	scene.visuals.set_enabled(false)
	# Everything shown (fog and shroud off) at the busiest place: the heaviest view the match can give.
	scene.visibility.fog = false
	scene.visibility.shroud = false
	scene.visibility.dirty = true
	sim_on = true
	for i in 30: await process_frame
	scene.centre_view(busiest_point(true))
	await phase("9 normal play, fog and shroud off, busiest place on the map, original look", seconds)
	scene.visuals.set_enabled(true)
	await phase("10 the same, Enhanced on", seconds)
	sim_on = false
	await phase("11 the same, Enhanced on, simulation stopped", seconds)
	DisplayConfig.set_visual("SoftShadows", false)
	scene.visuals.apply_settings()
	await phase("12 the same without soft shadows, simulation stopped", seconds)
	DisplayConfig.set_visual("SoftShadows", true)
	scene.visuals.set_enabled(false)
	await phase("13 busiest place, original look, simulation stopped", seconds)
	for u in scene.units: u.selected = true
	await phase("14 the same with every unit selected (rings and strips)", seconds)
	for u in scene.units: u.selected = false
	memory("end")
	sim_on = false
	print("SINGLE CALLS (late game, %d units, %d buildings, %d map objects):" % [scene.units.size(), scene.building_nodes.size(), scene.map_objects.size()])
	bench("simulation_step", func(): scene.simulation_step(1.0 / 60.0), 120)
	var dt := 1.0 / 60.0
	bench("  map objects advance", func():
		for object in scene.object_index().stepped: object.advance(dt), 120)
	bench("  map objects sync_states", func(): preload("res://battle/map_object.gd").sync_states(scene.map_objects, scene.production, scene.encounters, scene.object_index()), 120)
	bench("  units advance", func():
		for unit in scene.units: unit.advance(dt)
		scene.simulation_time += dt, 120)
	bench("  combat_step", scene.combat_step, 120)        # the clock stands still after the first call: later calls run no update
	bench("  one combat update (25 ms)", func():
		scene.simulation_time += 0.025
		scene.combat_step(), 120)
	bench("  update_race_powers", scene.update_race_powers, 120)
	bench("  effects.sync", func(): scene.effects.sync(scene), 120)
	bench("  economy + production update", func():
		scene.economy.update(scene.game_ms())
		scene.production.update(scene.game_ms())
		scene.resolve_pending_builds(), 120)
	bench("  skirmish frame + update", func():
		scene.skirmish.frame()
		scene.refresh_hero_commands()
		scene.skirmish.update(scene.game_ms()), 120)
	bench("refresh_status", scene.refresh_status)
	bench("  production_text", scene.production_text)
	bench("  combat_text", scene.combat_text)
	bench("  match_text", scene.match_text)
	bench("buildings queue_redraw loop", func():
		for node in scene.building_nodes.values(): node.queue_redraw())
	bench("update_order_marker", scene.update_order_marker)
	bench("update_cursor", scene.update_cursor)
	bench("apply_fog_to_nodes", scene.apply_fog_to_nodes)
	bench("refresh_fog_overlay", scene.refresh_fog_overlay)
	bench("units update_sprite loop", func():
		for u in scene.units: u.update_sprite())
	bench("units queue_redraw loop", func():
		for u in scene.units: u.queue_redraw())
	if scene.hud != null:
		bench("hud refresh_cells", scene.hud.refresh_cells)
		bench("hud update_geometry", scene.hud.update_geometry)
	print("profile done")
	quit(0)
