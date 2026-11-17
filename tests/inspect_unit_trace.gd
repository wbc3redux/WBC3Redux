extends SceneTree
## Diagnostic: one unit's order, current order and conversion state over time in a copy of a save.
##   -- --save= --heroes= --unit= [--seconds=3]
func _initialize(): call_deferred("run")
func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var id := -1
	var seconds := 3.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--unit="): id = int(arg.get_slice("=", 1))
		if arg.begins_with("--seconds="): seconds = float(arg.get_slice("=", 1))
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "": print("refused: " + error); quit(1); return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_process(false)
	var f = scene.combat.fighters[id]
	var u = scene.unit_by_id(id)
	for i in int(seconds * 40):
		scene.simulation_step(0.025)
		if i % 10 == 0:
			var hit = scene.combat.ai.attacker_of(f, id)
			print("t=%.2f state %s order %s cur %s converting %s orders %d hit %s" % [i * 0.025, f.state, str(f.order).left(70), str(f.cur).left(60),
				scene.converting(u) if scene.has_method("converting") else "?", u.orders.size(), str(hit).left(60)])
	quit(0)
