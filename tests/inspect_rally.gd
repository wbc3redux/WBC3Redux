extends SceneTree
## Diagnostic: in a copy of a save, the local player's buildings with a rally point, and where their next units go.
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
	var me: int = scene.local_player
	for id in scene.production.buildings:
		var b = scene.production.buildings[id]
		if int(b.owner) == me and b.rally.x >= 0:
			for c in scene.production.menu_for(b):
				var r: Dictionary = scene.production.enqueue(id, String(c.id), scene.game_ms())
				print("  enqueue %s: %s" % [c.id, r])
				if r.ok: break
			print("building %d %s rally %s queue %s spawn %s" % [id, b.original_type_id, b.rally, b.queue.map(func(j): return j.get("item", j)), scene.production.spawn_target(b)])
	var watched := {}
	scene.production.unit_ready.connect(func(info):
		if int(info.owner) == me: watched[int(info.unit_id)] = info)
	for i in 40 * 120:
		scene.simulation_step(0.025)
		if i % 200 == 0:
			for uid in watched:
				var u = scene.unit_by_id(uid)
				var f = scene.combat.fighters.get(uid)
				print("t=%d unit %d %s from %s rally %s: cell %s orders %s step %s state %s order %s script %s" % [i / 40, uid, watched[uid].item, watched[uid].cell, watched[uid].rally, u.cell, u.orders.map(func(o): return [o.get("kind"), o.get("target")]), u.in_step, f.state if f else "-", str(f.order).left(50) if f else "-", f.get("script") if f else "-"])
	quit(0)
