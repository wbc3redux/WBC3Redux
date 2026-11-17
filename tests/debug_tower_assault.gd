extends SceneTree
## Repro (not part of -Check): 16 Swordsmen of player 0 are ordered at once to attack player 1's map tower in the real
## scene with the improved rules; prints who swings, who waits, where, and what each one is heading for.
const Setup = preload("res://simulation/skirmish_setup.gd")

func _initialize():
	call_deferred("run")

func run():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 3)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 3)
	scene.start_skirmish(setup, "", null, "repro")
	scene.ai_manager.dispose()
	scene.ai_manager = null
	var improved := not ("--original" in OS.get_cmdline_user_args())
	scene.navigator.improved = improved
	scene.combat.improved = improved
	var tower = null
	for b in scene.production.buildings.values():
		print("building %d owner %d %s %s" % [b.entity_id, int(b.owner), b.original_type_id, b.cell_rect()])
		if int(b.owner) != 0 and String(b.original_type_id).substr(1, 2) == "WT" and tower == null: tower = b
	var rect: Rect2i = tower.cell_rect()
	print("tower %d at %s cells %s" % [tower.entity_id, rect, scene.navigator.building_cells.keys().filter(func(c): return scene.navigator.building_cells[c] == tower.entity_id)])
	var distance := 16
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--distance="): distance = int(arg.get_slice("=", 1))
	var origin := Vector2i(rect.position.x - distance, rect.position.y)
	var army: Array = []
	for i in 16:
		var cell: Vector2i = scene.navigator.free_cell_near(origin + Vector2i(i % 4, (i / 4) * 2))
		var u = scene.add_unit("AHKX", cell, 0)
		scene.production.register_unit(u.unit_id, "AHKX", 0)
		army.append(u)
	for u in scene.units: u.selected = army.has(u)
	scene.issue_attack({"kind": "building", "id": tower.entity_id})
	print(scene.last_message)
	for second in 40:
		for k in 40: scene.simulation_step(0.025)
		if second % 5 != 4: continue
		var swinging := 0
		var lines: Array = []
		for u in army:
			var f = scene.combat.fighters.get(u.unit_id)
			if f == null or not scene.combat.alive(f): continue
			if f.state == "swing": swinging += 1
			var planned = f.order.get("planned_cell") if f.order != null else null
			lines.append("  u%d %s cell %s state %s planned %s orders %d moving %s waits %d" % [u.unit_id, u.type_id, u.cell, f.state, planned, u.orders.size(), u.is_moving(), u.waits])
		print("t=%ds swinging %d of %d alive, assaults %d" % [second + 1, swinging, lines.size(), scene.assaults.size()])
		if second == 14 or second == 39:
			for l in lines: print(l)
	for u in army: u.selected = false
	quit(0)
