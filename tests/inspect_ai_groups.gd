extends SceneTree
## Diagnostic: the computer players' groups holding a unit in a copy of a save.  -- --save= --heroes= --unit=
func _initialize(): call_deferred("run")
func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var id := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--unit="): id = int(arg.get_slice("=", 1))
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "": print("refused: " + error); quit(1); return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_process(false)
	print("improved armies: ", scene.improved_armies)
	for p in scene.ai_manager.players.size():
		var ai = scene.ai_manager.players[p]
		if ai == null or not "groups" in ai: continue
		for g in ai.groups:
			if g.members.has(id): print("player %d group: %s" % [p, str({"kind": g.kind, "state": g.get("state"), "hero": g.get("hero"), "fighting": g.get("fighting"), "members": g.members.size(), "target": g.get("target")}).left(300)])
		if ai.tasks.has("u%d" % id): print("player %d task: %s" % [p, str(ai.tasks["u%d" % id]).left(200)])
	quit(0)
