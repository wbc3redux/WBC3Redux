extends SceneTree

const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Selection = preload("res://battle/selection.gd")
const Benchmark = preload("res://devtools/movement_benchmark.gd")
var checks := 0

func require(condition: bool, message: String):
	checks += 1
	if not condition:
		push_error(message)
		quit(1)
		assert(condition, message)

func _initialize():
	call_deferred("run")

func fixture_collision(width: int, height: int):
	var collision = CollisionData.new()
	collision.width = width
	collision.height = height
	collision.data = {"cells": []}
	for i in range(width * height): collision.data.cells.append({"profile_passable":[true],"object_indices":[]})
	return collision

func make_unit(nav: RefCounted, position: Vector2, id: int = 0):
	var unit = UnitAgent.new()
	unit.navigator = nav
	unit.position = position
	unit.unit_id = id
	return unit

func validate_route(nav: RefCounted, route: Dictionary, start: Vector2):
	require(route.ok, "Route should be reachable")
	var previous: Vector2i = nav.collision.world_cell(start)
	for cell in route.cells:
		require(nav.chebyshev(previous, cell) == 1, "Route must move one cell per step")
		require(nav.enterable_static(cell), "Route enters a blocked or border cell")
		previous = cell

func run_until_idle(unit, dt: float = 1.0/60.0, limit: int = 20000) -> int:
	var ticks := 0
	while not unit.orders.is_empty() and ticks < limit:
		unit.advance(dt)
		ticks += 1
	return ticks

# Routes exported from the emulated original search (tools/emulate_pathfinder.py).
func fixture_parity():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/pathfinder_fixtures.json"))
	var placeholder := RefCounted.new()
	for case in fixtures.cases:
		var collision = fixture_collision(int(case.size[0]), int(case.size[1]))
		for c in case.blocked: collision.data.cells[int(c[1]) * collision.width + int(c[0])].object_indices = [0]
		var nav = Navigation.new(collision)
		for c in case.occupied: nav.occupy(placeholder, Vector2i(int(c[0]), int(c[1])))
		var found: Dictionary = nav.search(Vector2i(int(case.start[0]), int(case.start[1])), Vector2i(int(case.goal[0]), int(case.goal[1])),
			int(case.limit), bool(case.unit_aware))
		if case.path == null:
			require(not found.ok, "Search must fail where the original fails")
			continue
		require(found.ok and found.cells.size() == case.path.size(), "Search must match original route length")
		for i in range(case.path.size()):
			require(found.cells[i] == Vector2i(int(case.path[i][0]), int(case.path[i][1])), "Search must match original route cells")

# Whole ground orders and group rules exported from the emulated original
# (tools/emulate_pathfinder.py --routes): sector chaining, retargeting, facing and formation slots.
func route_parity(actual_nav: RefCounted):
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/route_fixtures.json"))
	var multi := 0
	for case in fixtures.cases:
		var nav: RefCounted = actual_nav
		if not case.has("map"):
			var collision = fixture_collision(int(case.size[0]), int(case.size[1]))
			for c in case.blocked: collision.data.cells[int(c[1]) * collision.width + int(c[0])].object_indices = [0]
			nav = Navigation.new(collision)
		var found: Dictionary = nav.route_cells(Vector2i(int(case.start[0]), int(case.start[1])), Vector2i(int(case.goal[0]), int(case.goal[1])))
		require(found.ok == bool(case.ok), "Route outcome must match the original: %s" % [case.get("name", case.start)])
		var expected: Array = []
		for segment in case.segments:
			if not segment.cells.is_empty(): expected.append(segment.cells)
		var mine: Array = []
		for segment in found.get("segments", []):
			if not segment.is_empty(): mine.append(segment)
		require(mine.size() == expected.size(), "Segment count must match the original: %s" % [case.get("name", case.start)])
		if mine.size() > 1: multi += 1
		for i in range(mini(mine.size(), expected.size())):
			require(mine[i].size() == expected[i].size(), "Segment length must match the original")
			for j in range(mine[i].size()):
				require(mine[i][j] == Vector2i(int(expected[i][j][0]), int(expected[i][j][1])), "Segment cells must match the original")
	require(multi >= 5, "Fixtures must include chained multi-segment routes")
	for row in fixtures.group.formation_1:
		var pairs: Array = fixtures.group.formation_1[row]
		var flat: Array = []
		for pair in pairs: flat.append_array([int(pair[0]), int(pair[1])])
		require(Navigation.FORMATION_1[int(row) - 1] == flat, "Formation table must match 0x5fcc9c")
	for d in fixtures.group.directions:
		require(Navigation.move_direction(Vector2i(int(d[0]), int(d[1])), int(d[2])) == int(d[3]), "Facing must match 0x40c770")
	for case in fixtures.group.slots:
		var entries: Array = []
		for u in case.units: entries.append({"rank_a": int(u[0]), "rank_b": int(u[1])})
		var cells: Array[Vector2i] = Navigation.formation_slots(Vector2i(int(case.target[0]), int(case.target[1])), entries, int(case.direction))
		for i in range(cells.size()):
			require(cells[i] == Vector2i(int(case.cells[i][0]), int(case.cells[i][1])), "Formation slots must match 0x530f80")

# Two units that each wait for the other's cell (the Hills to Climb Smith deadlock, MOVEMENT_RESEARCH.md "Head-on").
# Each tick advances both units by one 60 Hz step; returns the simulated seconds until both are idle or `limit` s.
func run_pair(a, b, limit: float) -> float:
	var t := 0.0
	while t < limit and not (a.orders.is_empty() and b.orders.is_empty()):
		a.advance(1.0 / 60.0)
		b.advance(1.0 / 60.0)
		t += 1.0 / 60.0
	return t

func head_on():
	# 1. A sealed one-cell corridor (row 3, x 1..14): the two meet halfway, every detour (0x4308b0, f <= 90 around units)
	# fails, and the 100th failure in a row ends each order on its last segment (0x430340 returns 0): both stand.
	var corridor = fixture_collision(16, 7)
	for y in range(7):
		for x in range(16):
			if y != 3: corridor.data.cells[y * 16 + x].object_indices = [0]
	var nav = Navigation.new(corridor)
	var a = make_unit(nav, nav.center(Vector2i(3, 3)), 1)
	var b = make_unit(nav, nav.center(Vector2i(12, 3)), 2)
	a.sync_cell(); b.sync_cell()
	a.give_order({"kind": "move", "target": nav.center(Vector2i(12, 3)), "speed": 8}, "replace")
	b.give_order({"kind": "move", "target": nav.center(Vector2i(3, 3)), "speed": 8}, "replace")
	var t := run_pair(a, b, 120.0)
	require(a.orders.is_empty() and b.orders.is_empty(), "Head-on in a corridor: both orders end (100 failed detours), t=%.2f" % t)
	require(t > 12.5 and t < 20.0, "Head-on in a corridor: the give-up takes 100 detour cycles of 5 updates (%.2f s)" % t)
	require(nav.chebyshev(a.cell, b.cell) == 1 and not a.in_step and not b.in_step, "Head-on in a corridor: the two stand next to each other")
	require(nav.occupant(a.cell) == a and nav.occupant(b.cell) == b, "Head-on in a corridor: each keeps its own cell")
	# The way is free once one of them is sent elsewhere.
	b.give_order({"kind": "move", "target": nav.center(Vector2i(13, 3)), "speed": 8}, "replace")
	a.give_order({"kind": "move", "target": nav.center(Vector2i(12, 3)), "speed": 8}, "replace")
	run_pair(a, b, 30.0)
	require(a.cell == Vector2i(12, 3) and b.cell == Vector2i(13, 3), "After the give-up a new order walks on")
	a.free(); b.free()
	# 2. Crossed goals on open ground: after one step each, A's goal is the cell B stands on and B's goal is A's cell, and
	# both are walking (path state 1 / 2, so neither is solid, 0x51f8d0). A's detour to its goal succeeds (the goal cell
	# is accepted, 0x42e180) and it keeps waiting for its ally; B's detour in the same update finds the shared 100 ms clock
	# taken and fails, so B's order ends after 100 failures and B stands where it is.
	var open = fixture_collision(16, 16)
	var open_nav = Navigation.new(open)
	a = make_unit(open_nav, open_nav.center(Vector2i(5, 5)), 1)
	b = make_unit(open_nav, open_nav.center(Vector2i(8, 5)), 2)
	a.sync_cell(); b.sync_cell()
	a.direction = 2
	b.direction = 6
	a.give_order({"kind": "move", "target": open_nav.center(Vector2i(7, 5)), "speed": 8}, "replace")
	b.give_order({"kind": "move", "target": open_nav.center(Vector2i(6, 5)), "speed": 8}, "replace")
	var ticks := 0
	while ticks < 60 * 60 and not b.orders.is_empty():
		a.advance(1.0 / 60.0)
		b.advance(1.0 / 60.0)
		ticks += 1
	require(b.orders.is_empty() and b.cell == Vector2i(7, 5), "Shared goal: the throttled unit gives up and stands (%d ticks)" % ticks)
	require(ticks > 12 * 60 and ticks < 20 * 60, "Shared goal: the give-up takes about 12.5 s (%d ticks)" % ticks)
	require(not a.orders.is_empty() and a.waiting and a.cell == Vector2i(6, 5), "Shared goal: the other waits for its ally (0x42d090)")
	# The standing unit is sent away (the computer gives its builder a new task): the waiting one walks onto its goal.
	b.give_order({"kind": "move", "target": open_nav.center(Vector2i(9, 9)), "speed": 8}, "replace")
	run_pair(a, b, 30.0)
	require(a.cell == Vector2i(7, 5) and b.cell == Vector2i(9, 9) and a.orders.is_empty(), "Shared goal: the waiting unit arrives once the cell is free")
	a.free(); b.free()
	require(nav.occupants.is_empty() and open_nav.occupants.is_empty(), "Head-on units release their cells")

## B1-7 (found in the Four Rivers soak): a blocked unit whose only free rejoin cell is the one it stands on. The detour
## search from a cell to itself succeeds with no cells, and nothing of the route is left after the rejoin cell; the
## spliced route was empty and recheck_step read cells[0]. Now that detour counts as a failed one.
func detour_to_own_cell():
	var collision = fixture_collision(8, 8)
	var nav = Navigation.new(collision)
	var unit = make_unit(nav, nav.center(Vector2i(3, 3)), 1)
	var blocker = make_unit(nav, nav.center(Vector2i(4, 3)), 2)
	unit.sync_cell(); blocker.sync_cell()
	var route: Array[Vector2i] = [Vector2i(4, 3), Vector2i(3, 3)]
	unit.cells = route
	unit.waypoint = 0
	unit.segments = []
	unit.clock_ms = 1000.0
	nav.next_detour_ms = 0
	var stepped: bool = unit.blocked_step(true)
	require(not stepped and not unit.cells.is_empty() and unit.waiting, "Detour onto the unit's own cell: no empty route, the unit waits")
	unit.free()
	blocker.free()

func run():
	detour_to_own_cell()
	head_on()
	fixture_parity()
	var collision = fixture_collision(12,10)
	# Wall with one opening forces a real detour.
	for y in range(8): collision.data.cells[y*12+5].object_indices = [0]
	var nav = Navigation.new(collision)
	var start: Vector2 = nav.center(Vector2i(2,2))
	var goal: Vector2 = nav.center(Vector2i(9,2))
	require(not collision.trace_segment(start,goal).clear, "Fixture line must be blocked")
	var route: Dictionary = nav.plan(start,goal)
	validate_route(nav,route,start)
	require(route.length_px > start.distance_to(goal), "Detour must be longer than direct line")
	require(not nav.plan(start,Vector2(-1,20)).ok, "Outside target must fail")
	var blocked: Dictionary = nav.plan(start,nav.center(Vector2i(5,2)))
	require(blocked.ok and blocked.snapped, "Blocked target should resolve to reachable free endpoint")
	# Barrier closure tests component rejection instead of repeated full-map searches.
	for y in range(8,10): collision.data.cells[y*12+5].object_indices = [0]
	nav.rebuild()
	# 0x50a8e0/0x430b80: an unreached goal is replaced by the nearest eligible reached cell.
	var cut: Dictionary = nav.plan(start,goal)
	require(cut.ok and cut.snapped and collision.world_cell(cut.target).x < 5, "Disconnected destination retargets to the reachable side")
	# The original only tests the destination cell: diagonal squeezes between touching blockers pass.
	var corner = fixture_collision(6,6)
	corner.data.cells[2*6+3].object_indices = [0]
	corner.data.cells[3*6+2].object_indices = [0]
	var corner_nav = Navigation.new(corner)
	var squeeze: Dictionary = corner_nav.plan(corner_nav.center(Vector2i(2,2)),corner_nav.center(Vector2i(3,3)))
	require(squeeze.ok and squeeze.cells == [Vector2i(3,3)], "Diagonal corner squeeze must be allowed")
	require(not corner_nav.plan(corner_nav.center(Vector2i(2,2)),corner_nav.center(Vector2i(0,2))).ok, "Border goals are rejected (0x42f650)")
	var open = fixture_collision(16,16)
	var open_nav = Navigation.new(open)
	var unit = make_unit(open_nav,open_nav.center(Vector2i(1,1)))
	unit.give_order({"kind":"move","target":open_nav.center(Vector2i(4,1)),"speed":8},"replace")
	unit.give_order({"kind":"move","target":open_nav.center(Vector2i(7,1)),"speed":8},"append")
	require(unit.orders.size()==2, "Shift equivalent must append")
	unit.give_order({"kind":"move","target":open_nav.center(Vector2i(1,4)),"speed":8},"prepend")
	require(unit.orders.size()==3 and unit.orders[0].target==open_nav.center(Vector2i(1,4)) and unit.orders[1].target==open_nav.center(Vector2i(4,1)), "Alt equivalent must preserve interrupted order")
	run_until_idle(unit)
	require(unit.orders.is_empty() and unit.position.distance_to(open_nav.center(Vector2i(7,1)))<0.001 and unit.completed_orders==3, "Queue must execute in order and finish")
	unit.give_order({"kind":"move","target":open_nav.center(Vector2i(9,1)),"speed":8},"replace")
	unit.give_order({"kind":"move","target":open_nav.center(Vector2i(1,1)),"speed":8},"replace")
	require(unit.orders.size()==1 and unit.orders[0].target==open_nav.center(Vector2i(1,1)), "Plain move must replace")
	unit.stop()
	require(unit.orders.is_empty() and unit.path.is_empty(), "Stop must clear queue/path")
	unit.free()
	# Cell-step timing from table 0x61178c over 16 walk frames, independent of the step rate.
	require(UnitAgent.step_ms(8).step == 464 and UnitAgent.step_ms(10).step == 416, "Step durations must follow the original table")
	require(UnitAgent.step_ms(99).step == UnitAgent.step_ms(30).step, "Speed index is clamped to 30")
	for dt in [1.0/30.0,1.0/60.0,1.0/144.0]:
		var moving = make_unit(open_nav,open_nav.center(Vector2i(1,1)))
		moving.direction = 2
		moving.give_order({"kind":"move","target":open_nav.center(Vector2i(11,1)),"speed":8},"replace")
		run_until_idle(moving, dt)
		require(moving.position.distance_to(open_nav.center(Vector2i(11,1)))<0.001,"Travel must reach exact endpoint")
		require(absf(moving.moving_time-4.75)<0.0001,"Ten horizontal cells at speed 8 must take 4.75 s (464 ms on the 25 ms update: 475)")
		moving.free()
	var diagonal = make_unit(open_nav,open_nav.center(Vector2i(1,1)))
	diagonal.direction = 3
	diagonal.give_order({"kind":"move","target":open_nav.center(Vector2i(4,4)),"speed":10},"replace")
	run_until_idle(diagonal)
	require(absf(diagonal.moving_time-3*0.425)<0.0001,"Diagonal steps take the same time as orthogonal ones (416 -> 425 ms, Measured)")
	diagonal.free()
	var turning = make_unit(open_nav,open_nav.center(Vector2i(1,1)))
	turning.direction = 0
	turning.give_order({"kind":"move","target":open_nav.center(Vector2i(2,1)),"speed":8},"replace")
	run_until_idle(turning)
	require(absf(turning.moving_time-0.575)<0.0001,"A 90 degree turn adds three 29 ms frames (464 + 87 = 551, on the update: 575)")
	turning.free()
	# Crowd rules: a stationary unit on the final cell stops the mover; mid-route it is detoured.
	var crowd = fixture_collision(16,16)
	var crowd_nav = Navigation.new(crowd)
	var idle = make_unit(crowd_nav,crowd_nav.center(Vector2i(8,5)),1)
	idle.sync_cell()
	var mover = make_unit(crowd_nav,crowd_nav.center(Vector2i(2,5)),2)
	mover.direction = 2
	mover.give_order({"kind":"move","target":crowd_nav.center(Vector2i(8,5)),"speed":8},"replace")
	run_until_idle(mover)
	require(mover.cell == Vector2i(7,5) and mover.orders.is_empty(), "Final cell held by an idle unit: stop adjacent")
	mover.position = crowd_nav.center(Vector2i(2,5))
	mover.give_order({"kind":"move","target":crowd_nav.center(Vector2i(13,5)),"speed":8},"replace")
	run_until_idle(mover)
	require(mover.cell == Vector2i(13,5) and mover.orders.is_empty(), "Idle unit mid-route must be detoured around")
	require(idle.cell == Vector2i(8,5) and crowd_nav.occupant(Vector2i(8,5)) == idle, "Occupancy must stay with the idle unit")
	idle.free(); mover.free()
	require(crowd_nav.occupants.is_empty(), "Freed units must release their cells")
	# 0x530870: six units moving east by >= 5 cells face east (6) and take formation-1 slots.
	var entries: Array = []
	for i in range(6): entries.append({"id":i,"cell":Vector2i(i+1,1),"speed":8 + i})
	var group: Dictionary = open_nav.group_orders(entries,Vector2i(14,6),0,true)
	require(group.ok and group.facing == 6 and group.centroid == Vector2i(3,1), "Group facing follows the centroid displacement")
	var expected_slots := [Vector2i(14,6),Vector2i(12,6),Vector2i(14,4),Vector2i(14,8),Vector2i(16,5),Vector2i(16,7)]
	for i in range(6):
		require(group.orders[i].cell == expected_slots[i] and group.orders[i].speed == 8, "Slots and slowest speed follow 0x530f80/0x530870")
	var short_move: Dictionary = open_nav.group_orders(entries,Vector2i(5,3),6,false)
	require(short_move.facing == 6 and short_move.orders[5].speed == 13, "Short moves keep facing; Ctrl keeps own speeds")
	var a=make_unit(open_nav,Vector2(100,100))
	var b=make_unit(open_nav,Vector2(200,200))
	var selection_units: Array = [a,b]
	for scale in [0.25,1.0,2.5]:
		var canvas := Transform2D(0,Vector2(scale,scale),0,Vector2(250,-80))
		var first := canvas*Vector2(60,40)
		var last := canvas*Vector2(140,140)
		for endpoints in [[first,last],[last,first],[Vector2(first.x,last.y),Vector2(last.x,first.y)],[Vector2(last.x,first.y),Vector2(first.x,last.y)]]:
			Selection.select_box(selection_units,Selection.world_box(endpoints[0],endpoints[1],canvas),0)
			require(a.selected and not b.selected,"Drag must work in all directions under camera transforms")
	# Parity pass 1 (0x421190): Shift-click adds (command 0x13); a toggle is not in the original's translator.
	Selection.add(Selection.hit(selection_units,b.position))
	require(a.selected and b.selected,"Shift-click adds")
	Selection.add(Selection.hit(selection_units,a.position))
	require(a.selected and b.selected,"Shift-click on a selected unit keeps it")
	require(Selection.hit(selection_units,Vector2(450,450)) == null,"Empty click hits nothing")
	Selection.clear(selection_units)
	require(not a.selected and not b.selected,"Empty click clears selection (command 5)")
	a.free();b.free()
	var actual = CollisionData.new()
	var actual_nav = Navigation.new(actual)
	route_parity(actual_nav)
	# Routes produced by the emulated original search on the same imported blockers.
	var expected := {
		"open_ground": [[13,64],[14,64],[15,64],[16,64],[17,64],[18,64],[19,64],[20,64],[21,64],[22,64]],
		"structure_detour": [[7,50],[8,49],[9,48],[10,47],[11,47],[12,47],[13,47],[14,47],[15,48],[16,49],[17,50],[18,51],[19,51],[20,51],[21,51]],
		"terrain_detour": [[46,30],[47,29],[48,28],[49,27],[50,27],[51,27],[52,27],[53,27],[54,27],[55,28],[56,29],[57,29],[58,29],[59,30],[60,31],[61,30],[62,31]]}
	for case in Benchmark.CASES:
		var from: Vector2=actual_nav.center(case.start)
		var actual_route: Dictionary=actual_nav.plan(from,actual_nav.center(case.goal))
		validate_route(actual_nav,actual_route,from)
		var route_cells: Array = []
		for c in actual_route.cells: route_cells.append([c.x,c.y])
		require(route_cells == expected[case.id], "Real-map route must match the emulated original: " + case.id)
	var scene=load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	scene.set_physics_process(false)
	scene.set_process(false)
	# Exercise the actual controller's input handlers, including release over HUD.
	var canvas: Transform2D = scene.get_canvas_transform()
	var drag_from: Vector2 = canvas * (scene.units[0].position - Vector2(30,55))
	var drag_to: Vector2 = canvas * (scene.units[0].position + Vector2(25,18))
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = drag_from
	scene._unhandled_input(press)
	require(scene.drag_active, "Map press must begin selection")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = drag_to
	scene._input(release)
	require(not scene.drag_active and scene.units[0].selected, "Global release must finish selection")
	scene._unhandled_input(press)
	scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	require(not scene.drag_active, "Focus loss must cancel drag")
	scene.select_all()
	scene.units[0].base_speed=6
	var command: Dictionary=scene.issue_move(actual_nav.center(Vector2i(24,64)))
	require(command.assignments.size()==6,"Main controller must command the whole selected group")
	for member in scene.units: require(member.orders[0].speed==6,"Normal group speed must use slowest member")
	scene.issue_move(actual_nav.center(Vector2i(25,64)),false,false,true)
	for member in scene.units: require(member.orders[0].speed==member.base_speed,"Ctrl must use individual speeds")
	scene.issue_move(actual_nav.center(Vector2i(27,64)),true)
	for member in scene.units: require(member.orders.size()==2,"Controller must append queued commands")
	scene.issue_move(actual_nav.center(Vector2i(23,64)),false,true)
	for member in scene.units: require(member.orders.size()==3,"Controller must prepend and preserve queue")
	scene.stop_selected()
	for member in scene.units: require(member.orders.is_empty(),"Controller stop must clear all selected units")
	root.remove_child(scene)
	scene.free()
	var report: Dictionary=Benchmark.run(actual_nav)
	for case in report.cases:
		require(case.planned and case.steps == case.original_steps,"Actual map benchmark must plan the original step count")
		for speed in Benchmark.SPEEDS:
			var timed: Dictionary = case["speed_%d" % speed]
			require(timed.completed and timed.active_travel_seconds >= timed.original_prediction_seconds - 0.0001 and timed.active_travel_seconds <= timed.original_prediction_seconds + timed.turn_allowance_seconds + 0.0001,"Benchmark travel must equal the original timing model")
	var file := FileAccess.open("res://.local/movement_benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	print("Movement checks passed: %d assertions; original-search and whole-route parity, step timing, crowd rules, selection, queues and formation slots" % checks)
	quit()
