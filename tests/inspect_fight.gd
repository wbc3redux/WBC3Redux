extends SceneTree
## Diagnostic (not part of -Check): the local player's units around an enemy unit of a type in a copy of a save, over time.
##   Godot --headless --path . --script res://tests/inspect_fight.gd -- --save=<path> --heroes=<dir> [--near=TYPE] [--seconds=N]
func _initialize():
	call_deferred("run")
func row(scene, f) -> String:
	var u = scene.unit_by_id(int(f.id))
	var tgt = f.get("target")
	return "  %d %s st=%s cell=%s step=%s ord=%s order=%s target=%s script=%s hp=%d" % [int(f.id), f.type_id, f.state, u.cell, u.in_step,
		u.orders.map(func(o): return o.get("kind", "?")), str(f.order).left(90), str(tgt).left(40), f.get("script"), int(f.hp)]
func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var near := ""
	var seconds := 6
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--near="): near = arg.get_slice("=", 1)
		if arg.begins_with("--seconds="): seconds = int(arg.get_slice("=", 1))
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, heroes, "user://inspect-saves-run")
	if error != "":
		print("refused: " + error)
		quit(1)
		return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_process(false)
	var me: int = scene.local_player
	var foes: Array = scene.combat.fighters.values().filter(func(f): return scene.combat.alive(f) and int(f.owner) != me and (near == "" or String(f.type_id) == near))
	print("local %d; foes of type %s: %s" % [me, near, foes.map(func(f): return [int(f.id), f.type_id, int(f.owner), scene.unit_by_id(int(f.id)).cell])])
	if foes.is_empty():
		var types := {}
		for f in scene.combat.fighters.values(): if int(f.owner) != me and scene.combat.alive(f): types[f.type_id] = true
		print("enemy types: ", types.keys())
		quit(0)
		return
	var foe = foes[0]
	var at: Vector2i = scene.unit_by_id(int(foe.id)).cell
	for t in range(0, seconds + 1, 2):
		print("t=%d s foe hp %d state %s cell %s" % [t, int(foe.hp), foe.state, scene.unit_by_id(int(foe.id)).cell])
		for f in scene.combat.fighters.values():
			if int(f.owner) != me or not scene.combat.alive(f): continue
			var c: Vector2i = scene.unit_by_id(int(f.id)).cell
			if maxi(absi(c.x - at.x), absi(c.y - at.y)) <= 2: print(row(scene, f))
		for i in 80: scene.simulation_step(0.025)
	quit(0)
