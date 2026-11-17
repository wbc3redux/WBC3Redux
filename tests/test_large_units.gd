extends SceneTree
## Milestone 11a: movement of 2x2 and 3x3 ground units (navigation.gd extents) against the emulated original on Desert Sands
## (tests/large_unit_fixtures.json, tools/emulate_large_units.py): the extent-e cell checks 0x42cc10 / 0x42cda0 on every
## cell, whole planned routes 0x42f650 / 0x42ff30 for extents 1..3, and the same after a Dwarven Citadel is stamped
## (0x52a6b0, counters +6 / +7); then footprint occupancy, unit-aware searches and the spawn finder for a 2x2 unit.
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		if failures < 30: printerr("Large unit check failed: ", label)

class Mover:
	extends RefCounted
	var extent := 2
	var moving := false
	func is_moving() -> bool: return moving

func _initialize():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/large_unit_fixtures.json"))
	var collision = CollisionData.new()
	var nav = Navigation.new(collision)
	_static_cells(nav, collision, fixtures)
	_routes(nav, fixtures.routes, "before")
	var c: Dictionary = fixtures.citadel
	var mask: Array = c.mask_rows
	nav.stamp_building(1, int(c.footprint_left), int(c.anchor[1]), int(c.footprint[0]), int(c.footprint[1]), mask)
	var wrong := 0
	for w in c.window:
		var cell := Vector2i(int(w[0]), int(w[1]))
		for e in 3:
			if nav.passable_extent(cell, e + 1) != (int(w[2 + e]) == 0): wrong += 1
	check(wrong == 0, "cells around the stamped Citadel for extents 1-3 (%d differ)" % wrong)
	_routes(nav, c.routes, "after the Citadel")
	_occupancy(collision)
	if failures == 0: print("Large unit checks passed: ", checks)
	else: printerr("Large unit checks failed: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)

func _static_cells(nav, collision, fixtures: Dictionary):
	for e in [1, 2, 3]:
		var expected: Dictionary = fixtures.static_blocked[str(e)]
		var blocked := {}
		for v in expected.cell_check: blocked[Vector2i(int(v[0]), int(v[1]))] = true
		var sector := {}
		for v in expected.sector_check: sector[Vector2i(int(v[0]), int(v[1]))] = true
		var wrong_cell := 0
		var wrong_sector := 0
		for y in collision.height:
			for x in collision.width:
				var cell := Vector2i(x, y)
				if nav.passable_extent(cell, e) == blocked.has(cell): wrong_cell += 1
				if nav.sector_passable(cell, e) == sector.has(cell): wrong_sector += 1
		check(wrong_cell == 0, "0x42cc10 extent %d on all cells (%d differ)" % [e, wrong_cell])
		check(wrong_sector == 0, "0x42cda0 extent %d on all cells (%d differ)" % [e, wrong_sector])

func _routes(nav, cases: Array, stage: String):
	for case in cases:
		var label := "%s extent %d %s" % [case.name, int(case.extent), stage]
		var found: Dictionary = nav.route_cells(Vector2i(int(case.start[0]), int(case.start[1])), Vector2i(int(case.goal[0]), int(case.goal[1])), int(case.extent))
		check(bool(found.ok) == bool(case.ok), "route outcome " + label)
		var expected: Array = []
		for segment in case.segments:
			if not segment.cells.is_empty(): expected.append(segment.cells)
		var mine: Array = []
		for segment in found.get("segments", []):
			if not segment.is_empty(): mine.append(segment)
		var same: bool = mine.size() == expected.size()
		for i in range(mini(mine.size(), expected.size())):
			if mine[i].size() != expected[i].size():
				same = false
				continue
			for j in range(mine[i].size()):
				if mine[i][j] != Vector2i(int(expected[i][j][0]), int(expected[i][j][1])): same = false
		check(same, "route cells " + label)

func _occupancy(collision):
	var nav = Navigation.new(collision)
	var big := Mover.new()
	var small := Mover.new()
	small.extent = 1
	var anchor := Vector2i(20, 64)
	nav.occupy(big, anchor)
	check(nav.occupant(Vector2i(20, 64)) == big and nav.occupant(Vector2i(21, 64)) == big and nav.occupant(Vector2i(20, 63)) == big and nav.occupant(Vector2i(21, 63)) == big, "a 2x2 unit holds x..x+1, y-1..y (0x51bb80)")
	check(nav.occupant(Vector2i(19, 64)) == null and nav.occupant(Vector2i(20, 65)) == null, "and nothing else")
	check(Navigation.footprint(Vector2i(10, 10), 3) == [Vector2i(9, 8), Vector2i(10, 8), Vector2i(11, 8), Vector2i(9, 9), Vector2i(10, 9), Vector2i(11, 9), Vector2i(9, 10), Vector2i(10, 10), Vector2i(11, 10)], "3x3 footprint centred in x, upward in y")
	# Another 2x2 unit cannot stand where its footprint overlaps; a 1x1 unit beside it can.
	check(nav.occupant_extent(Vector2i(19, 65), 2) == big and nav.occupant_extent(Vector2i(22, 64), 2) == null, "unit-aware extent test (0x42cf00)")
	var free: Vector2i = nav.free_cell_near(anchor, small, 2)
	check(free.x >= 0 and free != anchor and nav.occupant_extent(free, 2) == null and nav.enterable_extent(free, 2), "spawn finder keeps a 2x2 unit off the occupied footprint: %s" % free)
	var around: Dictionary = nav.search(Vector2i(16, 64), Vector2i(26, 64), 0, true, small, 2)
	var crossed := false
	for c in around.get("cells", []):
		if nav.occupant_extent(c, 2) == big: crossed = true
	check(around.ok and not crossed, "unit-aware 2x2 search goes around the parked unit")
	nav.release(big, anchor)
	check(nav.occupants.is_empty(), "release clears the footprint")
