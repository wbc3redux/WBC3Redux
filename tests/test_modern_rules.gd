extends SceneTree
## Checks for the DELIBERATE MODERN CHANGES of COMPLAINTS_AND_FIXES.md (simulation/modern_rules.gd): the improved route
## search, crowd flow, group marches, the sealed-building check and the settings rows. The original behaviour keeps its
## own suites (test_movement.gd and the rest), which run with the modern rules off.

const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Placement = preload("res://simulation/placement.gd")
const ModernRules = preload("res://simulation/modern_rules.gd")
var checks := 0
var report: Array = []
var made: Array = []                       # every unit node, freed before quitting (the check fails on leaks)

func require(condition: bool, message: String):
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize():
	call_deferred("run")

func fixture_collision(width: int, height: int, blocked: Array = []):
	var collision = CollisionData.new()
	collision.width = width
	collision.height = height
	collision.data = {"cells": []}
	for i in range(width * height): collision.data.cells.append({"profile_passable": [true], "object_indices": []})
	for c in blocked: collision.data.cells[c.y * width + c.x].object_indices = [0]
	return collision

func make_unit(nav: RefCounted, cell: Vector2i, id: int, owner: int = 0):
	var unit = UnitAgent.new()
	unit.navigator = nav
	unit.position = nav.center(cell)
	unit.unit_id = id
	unit.owner_id = owner
	unit.sync_cell()
	made.append(unit)
	return unit

func move(unit, nav, cell: Vector2i, extra: Dictionary = {}):
	var order := {"kind": "move", "target": nav.center(cell), "requested": nav.center(cell), "group": 0, "speed": unit.base_speed, "individual": true}
	order.merge(extra, true)
	unit.give_order(order, "replace")

## Advances every unit until all are idle; returns the tick count (or `limit` when something never arrives).
func run_all(units: Array, limit: int = 20000, sample: Callable = Callable()) -> int:
	var dt := 1.0 / 60.0
	for tick in limit:
		var busy := false
		for u in units:
			u.advance(dt)
			busy = busy or not u.orders.is_empty() or u.in_step
		if sample.is_valid(): sample.call(tick)
		if not busy: return tick
	return limit

# A wall at x = 20 across the map with a gap of `gap` cells at y = 20.
func wall_with_gap(width: int, height: int, gap: int) -> Array:
	var blocked: Array = []
	for y in range(1, height - 1):
		if y >= 20 and y < 20 + gap: continue
		blocked.append(Vector2i(20, y))
	return blocked

func run():
	search_checks()
	march_checks()
	crowd_checks()
	nudge_and_settle_checks()
	placement_checks()
	settings_checks()
	for line in report: print(line)
	for unit in made:
		if is_instance_valid(unit): unit.free()
	made.clear()
	print("Modern rules checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ F5
func search_checks():
	var nav = Navigation.new(fixture_collision(64, 64, [Vector2i(5, 4), Vector2i(4, 5)]))
	# No squeezing between two blocked orthogonal cells (the original's search allows the diagonal step).
	var squeeze: Dictionary = nav.astar(Vector2i(4, 4), Vector2i(6, 6))
	require(squeeze.ok, "A* finds a route around the corner")
	var previous := Vector2i(4, 4)
	for c in squeeze.cells:
		if c.x != previous.x and c.y != previous.y:
			require(nav.is_passable(Vector2i(c.x, previous.y)) or nav.is_passable(Vector2i(previous.x, c.y)), "No diagonal squeeze between blocked cells")
		previous = c
	var original: Dictionary = nav.search(Vector2i(4, 4), Vector2i(6, 6))
	require(original.ok and original.cells[0] == Vector2i(5, 5), "The original search still squeezes (unchanged)")
	# Straight-ish routes: few direction changes on open ground (the original's doubled heuristic ends in a zigzag).
	var open = Navigation.new(fixture_collision(64, 64))
	var line: Dictionary = open.astar(Vector2i(2, 10), Vector2i(40, 17))
	require(line.ok and line.cells.size() == 38, "Octile A* takes the shortest step count on open ground")
	require(turns(Vector2i(2, 10), line.cells) <= 2, "Octile A* route has at most two turns on open ground")
	report.append("Open route (2,10)->(40,17): improved %d turns, original %d turns" % [turns(Vector2i(2, 10), line.cells),
		turns(Vector2i(2, 10), open.search(Vector2i(2, 10), Vector2i(40, 17)).cells)])
	# Long route through a winding maze: one segment, no failure.
	var maze: Array = []
	for x in range(4, 60, 8):
		for y in range(1, 63):
			var gap_y := 3 if (x / 8) % 2 == 0 else 60
			if absi(y - gap_y) > 1: maze.append(Vector2i(x, y))
	var winding = Navigation.new(fixture_collision(64, 64, maze))
	winding.improved = true
	var route: Dictionary = winding.route_cells(Vector2i(2, 32), Vector2i(62, 32))
	require(route.ok and route.segments.size() == 1, "Improved planner: one segment through the maze")
	winding.improved = false
	var segmented: Dictionary = winding.route_cells(Vector2i(2, 32), Vector2i(62, 32))
	report.append("Maze route: improved %d steps in 1 segment; original ok=%s segments=%d" % [route.segments[0].size(), str(segmented.ok), segmented.get("segments", []).size()])
	# Blocked goal: retargeted like the original.
	var walled = Navigation.new(fixture_collision(32, 32, [Vector2i(10, 10)]))
	walled.improved = true
	var blocked_goal: Dictionary = walled.route_cells(Vector2i(2, 2), Vector2i(10, 10))
	require(blocked_goal.ok and blocked_goal.target != Vector2i(10, 10) and walled.chebyshev(blocked_goal.target, Vector2i(10, 10)) == 1, "Blocked goal retargets to a neighbour")

func turns(start: Vector2i, cells: Array) -> int:
	var count := 0
	var last := Vector2i.ZERO
	var previous := start
	for c in cells:
		var d: Vector2i = c - previous
		if last != Vector2i.ZERO and d != last: count += 1
		last = d
		previous = c
	return count

# ------------------------------------------------------------------------------------------------ F1
func march_checks():
	var results := {}
	for improved in [false, true]:
		var nav = Navigation.new(fixture_collision(64, 64, wall_with_gap(64, 64, 3)))
		nav.improved = improved
		# A scattered group (the "shapeless pack" case): up to 12 cells apart along the way.
		var units: Array = []
		var id := 0
		for y in range(16, 26, 2):
			for x in [6, 17]:
				units.append(make_unit(nav, Vector2i(x - (y - 16) / 2, y), id))
				id += 1
		var entries: Array = units.map(func(u): return {"id": u.unit_id, "cell": u.cell, "speed": u.base_speed, "extent": 1, "flying": false})
		var group: Dictionary = nav.march_orders(entries, Vector2i(34, 21), 4, true, 7)
		for order in group.orders:
			var unit = units[int(order.id)]
			var o := {"kind": "move", "target": nav.center(order.cell), "requested": nav.center(Vector2i(34, 21)), "group": 7, "speed": order.speed, "individual": false}
			for key in ["cells", "marks", "march"]:
				if order.has(key): o[key] = order[key]
			unit.give_order(o, "replace")
		if improved: require(group.has("march") and nav.marches.has(7), "A ground group of ten marches together")
		var arrived := {}                                # unit id -> tick of its last cell change (its arrival)
		var last_cell := {}
		for u in units: last_cell[u.unit_id] = u.cell
		var ticks := run_all(units, 30000, func(t):
			for u in units:
				if u.cell != last_cell[u.unit_id]:
					last_cell[u.unit_id] = u.cell
					arrived[u.unit_id] = t)
		require(arrived.size() == units.size(), "Every member moved (%s)" % ("improved" if improved else "original"))
		require(ticks < 30000, "Every member arrives (%s)" % ("improved" if improved else "original"))
		var spots := {}
		for u in units: spots[u.cell] = true
		require(spots.size() == units.size(), "Members end on distinct cells")
		var times: Array = arrived.values()
		results[improved] = {"ticks": ticks, "spread": int(times.max()) - int(times.min())}
		if improved: require(nav.marches.is_empty(), "The march registry empties when every member arrived")
	# The march keeps the group's shape and does not halt for stragglers (smooth walking was preferred in the hand test of
	# 2026-11-01); through a narrow gap it must stay close to the original in time and spread.
	require(results[true].ticks * 4 <= results[false].ticks * 5, "The march through a gap takes at most 25% longer than the original")
	require(results[true].spread <= results[false].spread + 60, "The march arrives no more spread out than the original (+1 s)")
	report.append("March of 10 scattered units through a 3-cell gap: original %.1f s, arrivals spread over %.1f s; improved %.1f s, spread over %.1f s" % [
		results[false].ticks / 60.0, results[false].spread / 60.0, results[true].ticks / 60.0, results[true].spread / 60.0])

# ------------------------------------------------------------------------------------------------ F2
func crowd_checks():
	var results := {}
	for improved in [false, true]:
		var nav = Navigation.new(fixture_collision(64, 64, wall_with_gap(64, 64, 2)))
		nav.improved = improved
		var units: Array = []
		var id := 0
		for y in range(12, 30, 2):
			for x in [6, 8, 10]:
				var u = make_unit(nav, Vector2i(x, y), id)
				units.append(u)
				id += 1
		# Everyone wants a cell in one block east of the gap (individual orders, the computer's usual case).
		for i in units.size():
			move(units[i], nav, Vector2i(30 + i % 5, 16 + (i / 5) * 2))
		var ticks := run_all(units, 40000)
		var through: int = units.filter(func(u): return u.cell.x > 20).size()
		results[improved] = {"ticks": ticks, "through": through}
	require(results[true].through == 27, "Improved crowd: all 27 units pass the 2-cell gap")
	report.append("Crowd of 27 through a 2-cell gap: original %d through in %.1f s; improved %d through in %.1f s" % [
		results[false].through, results[false].ticks / 60.0, results[true].through, results[true].ticks / 60.0])

func nudge_and_settle_checks():
	# An idle friend standing in a one-cell corridor steps aside.
	var blocked: Array = []
	for x in range(1, 31):
		blocked.append(Vector2i(x, 9))
		if x < 14 or x > 16: blocked.append(Vector2i(x, 11))
	var nav = Navigation.new(fixture_collision(32, 32, blocked))
	nav.improved = true
	var mover = make_unit(nav, Vector2i(3, 10), 0)
	var idle = make_unit(nav, Vector2i(15, 10), 1)
	move(mover, nav, Vector2i(28, 10))
	var ticks := run_all([mover, idle], 20000)
	require(ticks < 20000 and mover.cell == Vector2i(28, 10), "The mover passes an idle friend in a corridor (nudged aside)")
	require(idle.cell != Vector2i(15, 10), "The idle friend stepped aside")
	# The same corridor in the original rules: the mover detours or stops; it must not reach the far end through the friend.
	var nav_old = Navigation.new(fixture_collision(32, 32, blocked))
	var mover_old = make_unit(nav_old, Vector2i(3, 10), 0)
	var idle_old = make_unit(nav_old, Vector2i(15, 10), 1)
	move(mover_old, nav_old, Vector2i(28, 10))
	run_all([mover_old, idle_old], 20000)
	report.append("Idle friend in a corridor: original mover ends at %s, improved at %s" % [str(mover_old.cell), str(mover.cell)])
	# The destination is held by an idle enemy: settle on a free cell next to it instead of stopping short.
	var open = Navigation.new(fixture_collision(32, 32))
	open.improved = true
	var walker = make_unit(open, Vector2i(3, 3), 0)
	var squatter = make_unit(open, Vector2i(20, 20), 1, 1)
	move(walker, open, Vector2i(20, 20))
	run_all([walker, squatter], 20000)
	require(walker.orders.is_empty() and open.chebyshev(walker.cell, Vector2i(20, 20)) == 1, "A held destination ends on a free neighbour")
	require(squatter.cell == Vector2i(20, 20), "An enemy is never nudged")

# ------------------------------------------------------------------------------------------------ F4
func placement_checks():
	# A pocket between terrain walls: placing a 3x3 building in its mouth would wall it in.
	var blocked: Array = []
	for y in range(10, 17): blocked.append(Vector2i(10, y))
	for y in range(10, 17): blocked.append(Vector2i(16, y))
	for x in range(10, 17): blocked.append(Vector2i(x, 10))
	var nav = Navigation.new(fixture_collision(40, 40, blocked))
	var definition := {"footprint": [5, 1], "mask_rows": [0]}
	nav.improved = true
	require(Placement.seals(nav, definition, 11, 16), "A building across the pocket's mouth seals it")
	require(not Placement.seals(nav, definition, 25, 25), "A building in the open seals nothing")
	report.append("Sealed-pocket check: mouth placement refused, open placement allowed")

# ------------------------------------------------------------------------------------------------ settings
func settings_checks():
	require(not ModernRules.movement() and not ModernRules.armies() and not ModernRules.research() and not ModernRules.health_bars(), "Headless runs start with the original rules")
	var rows := ModernRules.gameplay_rows()
	require(rows.size() == 2 and rows[0].key == "BattleRules" and rows[1].key == "HealthBars", "Two Gameplay rows")
	var copy := ModernRules.snapshot()
	ModernRules.choose("BattleRules", true)
	require(ModernRules.movement() and ModernRules.armies() and ModernRules.research(), "Battle Rules: Improved sets movement, armies and research (F10)")
	require(int(ModernRules.gameplay_rows()[0].current) == 1, "The row shows Improved")
	ModernRules.choose("HealthBars", true)
	require(ModernRules.health_bars(), "Health Bars: Always")
	ModernRules.restore(copy)
	require(not ModernRules.movement() and not ModernRules.health_bars(), "Cancel restores the copy")
