extends SceneTree
## Diagnostic (playtest 2026-11-11): three Liches selected and ordered (issue_attack) to attack a unit d cells away.
const Setup = preload("res://simulation/skirmish_setup.gd")
func _initialize():
	call_deferred("run")
func run():
	for improved in [false, true]:
		for d in [3, 5]:
			var scene = load("res://battle/main.tscn").instantiate()
			root.add_child(scene)
			await process_frame
			var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
			var setup := Setup.defaults(map)
			Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
			Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
			scene.start_skirmish(setup, "", null, "probe-ranged")
			scene.combat.ai_players.erase(0)
			if scene.ai_manager != null:
				for p in scene.ai_manager.players.size(): scene.ai_manager.players[p] = null
			scene.navigator.improved = improved
			var home: Vector2i = scene.skirmish.slots[0].start + Vector2i(6, 6)
			var liches: Array = []
			for k in 3: liches.append(scene.add_unit("AUMX", scene.navigator.free_cell_near(home + Vector2i(0, k)), 0))
			var foe = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(d, 1)), 1)
			scene.combat.fighters[foe.unit_id].script = 0
			var starts: Array = liches.map(func(u): return u.cell)
			var hits := {"n": 0, "first": -1}
			scene.combat.damaged.connect(func(kind, id, amount, attacker):
				if id == foe.unit_id:
					hits.n += 1
					if hits.first < 0: hits.first = scene.game_ms())
			for u in liches: u.selected = true
			var t0: int = scene.game_ms()
			scene.issue_attack({"kind": "unit", "id": foe.unit_id})
			for i in 240: scene.simulation_step(0.025)
			var moved: Array = []
			for k in 3: moved.append(maxi(absi(liches[k].cell.x - starts[k].x), absi(liches[k].cell.y - starts[k].y)))
			print("improved %s distance %d: hits %d, first after %d ms, cells moved %s, assaults %d, message '%s'" % [improved, d, hits.n,
				(hits.first - t0) if hits.first >= 0 else -1, moved, scene.assaults.size(), scene.last_message])
			scene.queue_free()
			await process_frame
	quit(0)
