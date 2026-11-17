extends SceneTree
## Diagnostic: every living unit of the local player in a copy of a save (id, type, cell, state, order kind).
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
	print("game ms ", scene.game_ms(), " local ", scene.local_player)
	if "--removed" in OS.get_cmdline_user_args():
		for f in scene.combat.fighters.values():
			var u = scene.unit_by_id(int(f.id))
			if f.removed and f.state != "corpse" and f.state != "dying":
				print("  REMOVED-LIVE %d %s owner %d state %s hp %d node visible %s removed %s dying %s inside %s in_mine %s" % [int(f.id), f.type_id, int(f.owner), f.state, int(f.hp), u.visible if u else "-", u.removed if u else "-", u.dying if u else "-", u.inside_building if u else "-", scene.in_mine_units.has(int(f.id))])
		quit(0)
		return
	for f in scene.combat.fighters.values():
		if int(f.owner) == scene.local_player and scene.combat.alive(f):
			print("  %d %s %s %s %s" % [int(f.id), f.type_id, scene.unit_by_id(int(f.id)).cell, f.state, str(f.order).left(60)])
	quit(0)
