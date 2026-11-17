extends SceneTree
## Diagnostic (not part of -Check): every field of one fighter in a copy of a save.
##   Godot --headless --path . --script res://tests/inspect_unit.gd -- --save=<path> --heroes=<dir> --unit=<id>
func _initialize():
	call_deferred("run")
func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var id := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--unit="): id = int(arg.get_slice("=", 1))
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "":
		print("refused: " + error)
		quit(1)
		return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_process(false)
	print("  map: %s random %s" % [scene.skirmish.resolved.get("map", scene.skirmish.resolved.get("map_slug", "?")), scene.skirmish.resolved.get("random_map", "?")])
	for k in scene.skirmish.resolved.keys(): print("  resolved.%s = %s" % [k, str(scene.skirmish.resolved[k]).left(120)])
	var f = scene.combat.fighters.get(id)
	for k in f.keys(): if k != "stats": print("  %s = %s" % [k, str(f[k]).left(160)])
	print("  stats = %s" % str(f.stats).left(400))
	var u = scene.unit_by_id(id)
	print("  node: type %s owner %s cell %s orders %s" % [u.type_id, u.owner_id, u.cell, u.orders])
	quit(0)
