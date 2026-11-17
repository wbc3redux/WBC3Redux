extends SceneTree
## Diagnostic: plan one unit's route to a cell in a copy of a save and print why it fails.
##   -- --save=<path> --heroes=<dir> --unit=<id> --to=x,y
func _initialize(): call_deferred("run")
func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var id := -1
	var to := Vector2i(-1, -1)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--unit="): id = int(arg.get_slice("=", 1))
		if arg.begins_with("--to="): to = Vector2i(int(arg.get_slice("=", 1).get_slice(",", 0)), int(arg.get_slice("=", 1).get_slice(",", 1)))
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "": print("refused: " + error); quit(1); return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_process(false)
	var u = scene.unit_by_id(id)
	var nav = scene.navigator
	var route: Dictionary = nav.plan(u.position, nav.center(to), u.extent, u.movement_type)
	print("unit %d %s at %s extent %s movement %s flying %s -> %s: ok %s reason %s" % [id, u.type_id, u.cell, u.extent, u.movement_type, u.flying, to, route.ok, route.get("reason", "")])
	for dy in range(-2, 3):
		var line := ""
		for dx in range(-2, 3):
			var c: Vector2i = u.cell + Vector2i(dx, dy)
			var occ = nav.occupant(c, u)
			line += ("U" if occ != null else ("." if nav.enterable_static(c) else "#")) + " "
		print("  ", line)
	for e in [1, 2]:
		for goal in [u.cell + Vector2i(0, -3), u.cell + Vector2i(2, 1), to]:
			var r: Dictionary = nav.plan(u.position, nav.center(goal), e, u.movement_type)
			print("  extent %d -> %s: ok %s %s" % [e, goal, r.ok, r.get("reason", "")])
	var out: Vector2i = nav.free_cell_near(u.cell, u, u.extent, u.movement_type)
	print("  free cell for extent %d: %s, passable_extent here %s" % [u.extent, out, nav.passable_extent(u.cell, u.extent, u.movement_type)])
	if out.x >= 0:
		var st: Dictionary = nav.plan(u.position, nav.center(out), 1, u.movement_type)
		print("  step out at size 1: ok %s %s" % [st.ok, st.get("reason", "")])
	scene.simulation_step(0.025)
	print("after a step: orders %s last_error '%s'" % [u.orders.size(), u.last_error])
	quit(0)
