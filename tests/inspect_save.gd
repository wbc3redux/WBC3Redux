extends SceneTree
## Diagnostic (not part of -Check): loads a copy of a save and lists, around the local player's army, every object that is
## not the local player's: owner, type, state, attitude script, order, hit points; then lets the match run --seconds with
## the local army attacking the nearest of them, and reports who hit whom.
##   Godot --headless --path . --script res://tests/inspect_save.gd -- --save=<path> --heroes=user://inspect-heroes [--seconds=20]

func _initialize():
	call_deferred("run")

func run():
	var path := ""
	var heroes := "user://inspect-heroes"
	var seconds := 20.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--save="): path = arg.get_slice("=", 1)
		if arg.begins_with("--heroes="): heroes = arg.get_slice("=", 1)
		if arg.begins_with("--seconds="): seconds = float(arg.get_slice("=", 1))
	var Main = load("res://battle/main.gd")
	var error: String = Main.prepare_saved_game(path, heroes, "user://inspect-saves")
	if error != "":
		print("inspect: refused: " + error)
		quit(1)
		return
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	for i in 5: await process_frame
	scene.set_physics_process(false)
	scene.set_process(false)
	var c = scene.combat
	var me: int = scene.local_player
	print("inspect: map %s, local player %d, time %d ms" % [scene.skirmish.slots.size(), me, scene.game_ms()])
	var army: Array = []
	for f in c.fighters.values():
		if int(f.owner) == me and c.alive(f): army.append(f)
	var centre := Vector2i.ZERO
	for f in army: centre += c.unit_cell(int(f.id))
	centre /= maxi(1, army.size())
	print("inspect: %d own units around %s" % [army.size(), centre])
	var others: Array = []
	for f in c.fighters.values():
		if int(f.owner) == me or not c.alive(f): continue
		var cell: Vector2i = c.unit_cell(int(f.id))
		if maxi(absi(cell.x - centre.x), absi(cell.y - centre.y)) > 25: continue
		others.append(f)
		print("  unit %d %s owner %d cell %s state %s script %d order %s hp %d/%d dmg %d allied %s" % [int(f.id), f.type_id, int(f.owner), cell, f.state,
			int(f.get("script", -1)), str(f.order), int(f.hp), int(f.max_hp), int(f.stats.dmg), scene.skirmish.is_allied(me, int(f.owner))])
	for b in scene.production.buildings.values():
		var at: Vector2i = b.cell_rect().position
		if int(b.owner) == me or maxi(absi(at.x - centre.x), absi(at.y - centre.y)) > 25: continue
		print("  building %d %s owner %d at %s hp %d" % [int(b.entity_id), b.original_type_id, int(b.owner), at, int(b.hit_points)])
	var hits := {}
	c.damaged.connect(func(kind, id, amount, attacker):
		if not c.fighters.has(attacker): return
		var key := "%d->%s" % [int(c.fighters[attacker].owner), str(int(c.fighters[id].owner)) if kind == "unit" and c.fighters.has(id) else kind]
		hits[key] = int(hits.get(key, 0)) + 1)
	if not others.is_empty():
		for f in army:
			var best = null
			var best_d := 999
			for o in others:
				var d: int = maxi(absi(c.unit_cell(int(o.id)).x - c.unit_cell(int(f.id)).x), absi(c.unit_cell(int(o.id)).y - c.unit_cell(int(f.id)).y))
				if d < best_d and not scene.skirmish.is_allied(me, int(o.owner)):
					best_d = d
					best = o
			if best != null: c.order_attack(int(f.id), "unit", int(best.id), false)
	for i in roundi(seconds * 40.0): scene.simulation_step(0.025)
	print("inspect: after %.0f s hits (attacker owner -> victim owner): %s" % [seconds, hits])
	for o in others:
		print("  unit %d %s owner %d state %s order %s hp %d script %d" % [int(o.id), o.type_id, int(o.owner), o.state, str(o.order), int(o.hp), int(o.get("script", -1))])
	quit(0)
