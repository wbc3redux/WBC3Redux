extends SceneTree
## Diagnostic (playtest 2026-11-11): a ranged unit ordered to attack a target inside its range should shoot, not walk.
const Setup = preload("res://simulation/skirmish_setup.gd")
func _initialize():
	call_deferred("run")
func run():
	for code in ["AUMX", "AHAX"]:
		for d in [2, 4, 6, 7]:
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
			var home: Vector2i = scene.skirmish.slots[0].start + Vector2i(6, 6)
			var me = scene.add_unit(code, scene.navigator.free_cell_near(home), 0)
			var foe = scene.add_unit("AHKX", scene.navigator.free_cell_near(me.cell + Vector2i(d, 0)), 1)
			scene.combat.fighters[foe.unit_id].script = 0
			var start: Vector2i = me.cell
			var shots := {"n": 0}
			scene.combat.damaged.connect(func(kind, id, amount, attacker): if attacker == me.unit_id: shots.n += 1)
			var ok: bool = scene.combat.order_attack(me.unit_id, "unit", foe.unit_id, false)
			var moved_at := -1
			for i in 160:
				scene.simulation_step(0.025)
				if moved_at < 0 and me.cell != start: moved_at = i
			print("%s distance %d (range %d): order %s, hits %d, moved after %s steps, end distance %d" % [code, Navigation_dist(start, foe.cell), int(scene.combat.fighters[me.unit_id].stats.range),
				ok, shots.n, moved_at, Navigation_dist(me.cell, foe.cell)])
			scene.queue_free()
			await process_frame
	quit(0)
func Navigation_dist(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
