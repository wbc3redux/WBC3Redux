extends SceneTree
## Group march timing on Desert Sands (not part of -Check): how long one group order takes to compute, and how smoothly a
## group of 25 walks (visible stops = a unit with an order standing still for more than 0.2 s), original against improved.
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")

func _initialize():
	call_deferred("run")

func run():
	var collision = CollisionData.new()
	for improved in [false, true]:
		var nav = Navigation.new(collision)
		nav.improved = improved
		var units: Array = []
		var start := Vector2i(14, 50)
		for i in 25:
			var cell: Vector2i = nav.free_cell_near(start + Vector2i((i % 5) * 2, (i / 5) * 2))
			var u = UnitAgent.new()
			u.navigator = nav
			u.unit_id = i
			u.position = nav.center(cell)
			u.sync_cell()
			units.append(u)
		var entries: Array = units.map(func(u): return {"id": u.unit_id, "cell": u.cell, "speed": u.base_speed, "extent": 1, "flying": false})
		var goal := Vector2i(60, 70)
		var t := Time.get_ticks_usec()
		var group: Dictionary = nav.march_orders(entries, goal, 4, true, 1) if improved else nav.group_orders(entries, goal, 4, true)
		var order_ms := (Time.get_ticks_usec() - t) / 1000.0
		for order in group.orders:
			var o := {"kind": "move", "target": nav.center(order.cell), "requested": nav.center(goal), "group": 1, "speed": order.speed, "individual": false}
			for key in ["cells", "marks", "march"]:
				if order.has(key): o[key] = order[key]
			units[int(order.id)].give_order(o, "replace")
		var stops := 0
		var stood := {}
		var last_cell := {}
		var moved_at := {}
		var first_frame_ms := 0.0
		var ticks := 0
		for tick in 20000:
			var busy := false
			var t2 := Time.get_ticks_usec()
			for u in units:
				u.advance(1.0 / 60.0)
				var idle_mid: bool = not u.in_step and not u.orders.is_empty()
				var still: int = int(stood.get(u.unit_id, 0)) + 1 if idle_mid else 0
				if still == 12: stops += 1
				stood[u.unit_id] = still
				if u.cell != last_cell.get(u.unit_id, u.cell): moved_at[u.unit_id] = tick
				last_cell[u.unit_id] = u.cell
				busy = busy or not u.orders.is_empty() or u.in_step
			if tick == 0: first_frame_ms = (Time.get_ticks_usec() - t2) / 1000.0    # the original plans every route here
			ticks = tick
			if not busy: break
		var arrivals: Array = moved_at.values()
		print("%s: order %.1f ms + first frame %.1f ms; arrival %.1f s (first %.1f s); %d visible stops (%.1f per unit)" % [
			"improved" if improved else "original", order_ms, first_frame_ms, ticks / 60.0, int(arrivals.min()) / 60.0, stops, stops / 25.0])
		for u in units:
			if not u.orders.is_empty(): print("    stuck u%d cell %s" % [u.unit_id, u.cell])
			u.free()
	quit(0)
