extends SceneTree
## Memory repro (not part of -Check): the hand test of 2026-11-01. 50 Swordsmen of player 0 in two groups of 25 get a new
## group move every 8 simulated seconds, improved rules, real scene, computers off. Prints memory every 30 s.
const Setup = preload("res://simulation/skirmish_setup.gd")

func _initialize():
	call_deferred("run")

func run():
	var minutes := 6.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="): minutes = float(arg.get_slice("=", 1))
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 3)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 3)
	scene.start_skirmish(setup, "", null, "memory")
	scene.ai_manager.dispose()
	scene.ai_manager = null
	var improved := not ("--original" in OS.get_cmdline_user_args())
	scene.navigator.improved = improved
	scene.combat.improved = improved
	var groups := [[], []]
	for i in 50:
		var cell: Vector2i = scene.navigator.free_cell_near(Vector2i(30 + (i % 10) * 2, 40 + (i / 10) * 2 + (12 if i >= 25 else 0)))
		var u = scene.add_unit("AHKX", cell, 0)
		scene.production.register_unit(u.unit_id, "AHKX", 0)
		groups[0 if i < 25 else 1].append(u)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var steps := roundi(minutes * 60.0 * 40.0)
	var start_mem := OS.get_static_memory_usage()
	var slowest_ms := 0.0
	var slowest_order_ms := 0.0
	for i in steps:
		if i % 320 == 0:                                   # every 8 s: a new move for each group
			for g in 2:
				for u in scene.units: u.selected = groups[g].has(u)
				var goal := Vector2i(rng.randi_range(15, 110), rng.randi_range(15, 110))
				var t := Time.get_ticks_usec()
				scene.issue_move(scene.navigator.center(goal))
				slowest_order_ms = maxf(slowest_order_ms, (Time.get_ticks_usec() - t) / 1000.0)
		var t2 := Time.get_ticks_usec()
		scene.simulation_step(0.025)
		slowest_ms = maxf(slowest_ms, (Time.get_ticks_usec() - t2) / 1000.0)
		if i % 1200 == 0:
			var marching := 0
			for m in scene.navigator.marches.values(): marching += m.size()
			print("t=%3ds static memory %d MB (+%d), marches %d (%d members), slowest order %.1f ms, slowest 25 ms step %.1f ms" % [i / 40,
				OS.get_static_memory_usage() / 1048576, (OS.get_static_memory_usage() - start_mem) / 1048576,
				scene.navigator.marches.size(), marching, slowest_order_ms, slowest_ms])
			slowest_ms = 0.0
			slowest_order_ms = 0.0
	for u in scene.units: u.selected = false
	print("Memory repro done")
	quit(0)
