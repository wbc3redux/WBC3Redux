extends SceneTree
## Diagnostic: visible local units with an attack order that stand still (no step, no route) for over a second.
func _initialize(): call_deferred("run")
func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "": print("refused: " + error); quit(1); return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_process(false)
	var still := {}
	var reported := {}
	for i in 40 * 30:
		scene.simulation_step(0.025)
		for f in scene.combat.fighters.values():
			if f.removed or int(f.owner) != scene.local_player or f.order == null or f.state != "approach": 
				still.erase(int(f.id)); continue
			var u = scene.unit_by_id(int(f.id))
			if u.in_step or not u.orders.is_empty(): still.erase(int(f.id)); continue
			still[int(f.id)] = int(still.get(int(f.id), 0)) + 1
			if still[int(f.id)] == 40 and not reported.has(int(f.id)):
				reported[int(f.id)] = true
				var t = f.order
				var tc: Vector2i = scene.combat.nearest_target_cell(f, t)
				print("t=%.1f %d %s at %s idle-approach vs %s %d at %s, planned %s, spread %s" % [i * 0.025, int(f.id), f.type_id, u.cell, t.target_kind, int(t.target_id), tc, t.get("planned_cell"), t.get("spread", {}).get("cell", "-")])
	print("done, %d units stood still over 1 s while approaching" % reported.size())
	quit(0)
