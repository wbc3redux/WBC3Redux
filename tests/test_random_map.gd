extends SceneTree
## RM-4 (RANDOM_MAP_RESEARCH.md "RM-4"): random_map_grid.gd's grid cell for cell and random_map_check.gd's pass / fail,
## pairs and regenerated layouts against tests/random_map_check_fixtures.json (the original check under Unicorn).
## RM-2 (RANDOM_MAP_RESEARCH.md "RM-2"): simulation/random_map.gd against tests/random_map_fixtures.json
## (tools/emulate_random_map.py: the original 0x582310 under Unicorn). Every layout case and both failure replays byte for
## byte: piece grid, MAPH code and quadrant on the map, the distinct MAPH record bytes 7..15, records beyond the map,
## feature records, generator state after and attempts. Plus the generator carried across maps, the read-index quirk
## and the deliberate dead-end bound on a synthetic set where no piece fits.
const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapGrid = preload("res://simulation/random_map_grid.gd")
const RandomMapCheck = preload("res://simulation/random_map_check.gd")
var checks := 0
var failures := 0
var grid_cells := 0
var border_nine := 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/random_map_fixtures.json"))
	var data := RandomMap.load_data()
	check(not data.is_empty() and int(data.schema) == 1, "assets/random_map.json loads (run the importer)")
	if data.is_empty():
		_finish()
		return
	_test_data(data)
	var started := Time.get_ticks_msec()
	for c in fixtures.cases: _test_case(c, 0)
	for c in fixtures.failure_replays: _test_case(c, int(c.fail_checks))
	print("Random map: %d cases in %d ms" % [fixtures.cases.size() + fixtures.failure_replays.size(), Time.get_ticks_msec() - started])
	_test_carried_state(fixtures)
	_test_read_index(data)
	_test_dead_end(data)
	var check_fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/random_map_check_fixtures.json"))
	check(not data.feature_definitions.is_empty() and data.movement_cost_rows.size() == 4, "random_map.json has the RM-4 collision tables")
	started = Time.get_ticks_msec()
	for g in check_fixtures.grids: _test_grid(g, data)
	print("Random map: %d grids (%d cells, %d border cells of material 9) in %d ms" % [check_fixtures.grids.size(), grid_cells, border_nine, Time.get_ticks_msec() - started])
	check(border_nine > 0, "the grid fixtures cover border cells of material 9")
	started = Time.get_ticks_msec()
	for c in check_fixtures.cases: _test_checked_case(c, data)
	print("Random map: %d checked cases in %d ms" % [check_fixtures.cases.size(), Time.get_ticks_msec() - started])
	_finish()

func _finish():
	if failures == 0: print("Random map checks passed: ", checks)
	else: printerr("Random map failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func _test_data(data: Dictionary):
	var pieces := 0
	for key in data.sets: pieces += data.sets[key].pieces.size()
	check(pieces == 647 and data.sets.size() == 11, "647 pieces in 11 sets")
	check(data.terrain_types.size() == 10, "ten terrain types")
	check(data.missing_tiles_used.is_empty(), "every tile of the used sets has a TER record")
	for t in data.terrain_types:
		check(data.sets[t.set].pieces.size() == int(t.count), "set %s holds its count" % t.set)

func _test_case(c: Dictionary, fail_checks: int):
	var label := "seed %d terrain %d size %d fails %d" % [int(c.seed), int(c.terrain), int(c.size), fail_checks]
	var rm = RandomMap.new(int(c.seed))
	var remaining := [fail_checks]
	var check_fn := func(_layout: Dictionary) -> bool:
		if remaining[0] > 0:
			remaining[0] -= 1
			return false
		return true
	var got: Dictionary = rm.generate(int(c.terrain), int(c.size), check_fn)
	check(bool(got.ok), label + ": finished")
	if not bool(got.ok): return
	check(int(got.attempts) == int(c.attempts), label + ": attempts %d, expected %d" % [got.attempts, c.attempts])
	check(int(got.lcg_after) == int(c.lcg_after), label + ": generator %d, expected %d" % [got.lcg_after, c.lcg_after])
	check(int(got.cols) == int(c.cols) and int(got.rows) == int(c.rows), label + ": slots")
	check(_ints(got.goms) == _ints(c.goms), label + ": piece grid")
	check(_tiles(got.tiles) == _tiles(c.tiles), label + ": MAPH code and quadrant")
	check(int(got.tiles_outside_map) == int(c.tiles_outside_map), label + ": records beyond the map %d, expected %d" % [got.tiles_outside_map, c.tiles_outside_map])
	var tails := {}
	for x in RandomMap.GRID:
		for y in RandomMap.GRID:
			if got.maph.decode_u32((x * RandomMap.GRID + y) * RandomMap.RECORD) != 0:
				tails[RandomMap.record_tail_hex(got.maph, x, y)] = true
	var tail_list: Array = tails.keys()
	tail_list.sort()
	check(tail_list == Array(c.maph_extra), label + ": MAPH bytes 7..15 %s, expected %s" % [tail_list, c.maph_extra])
	check(_features(got.features) == _features(c.features), label + ": features (%d, expected %d)" % [got.features.size(), c.features.size()])

func _ints(grid: Array) -> Array:
	var out := []
	for row in grid:
		var line := []
		for v in row: line.append(int(v))
		out.append(line)
	return out

func _tiles(grid: Array) -> Array:
	var out := []
	for row in grid:
		for t in row: out.append("%s/%d" % [t[0], int(t[1])])
	return out

func _features(list: Array) -> Array:
	var out := []
	for f in list: out.append("%s %d %d %d %d %d" % [f[0], int(f[1]), int(f[2]), int(f[3]), int(f[4]), int(f[5])])
	return out

## A2: the state is never seeded; the second map of a session starts where the first left the generator.
func _test_carried_state(fixtures: Dictionary):
	var first: Dictionary = fixtures.cases[0]
	var rm = RandomMap.new(int(first.seed))
	var a: Dictionary = rm.generate(int(first.terrain), int(first.size))
	var b: Dictionary = rm.generate(1, 128)
	var fresh = RandomMap.new(int(a.lcg_after))
	var c: Dictionary = fresh.generate(1, 128)
	check(_ints(b.goms) == _ints(c.goms) and int(b.lcg_after) == int(c.lcg_after), "the generator runs on across random maps")
	check(_ints(a.goms) != _ints(b.goms), "the second map of a session differs from the first")
	check(RandomMap.new().state == 0, "the generator is 0 at launch")

## A8: a code without a TER record does not advance the read index, so the rest of the piece repeats it (writes nothing).
func _test_read_index(data: Dictionary):
	var rm = RandomMap.new(0, data)
	var maph := PackedByteArray()
	maph.resize(RandomMap.GRID * RandomMap.GRID * RandomMap.RECORD)
	var piece := {"tiles": ["TGX0", "ZZZZ", "TGX1", "TGX1", "TGX1", "TGX1", "TGX1", "TGX1", "TGX1"], "skip": [0, 0, 0, 0, 0, 0, 0, 0, 0]}
	rm._write_piece(maph, piece, 0, 0)
	var written := 0
	for x in 3:
		for y in 3:
			if maph.decode_u32((x * RandomMap.GRID + y) * RandomMap.RECORD) != 0: written += 1
	check(written == 1, "an unknown code stops the piece's read index (%d records written)" % written)

static func _unrle(runs: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for run in runs:
		for k in int(run[1]): out.append(int(run[0]))
	return out

## RM-4: the port's grid of the case's first attempt against the original's (0x42bd50 grid, 0x5302c0 stamps, 0x42de30)
## cell for cell: 0x42cc10 extent 1 and 2, the occupied bit, the nav material array 0x97f6f4, the height 0x48f810 and the
## extent-2 sector region (sector index * 256 + region id).
func _test_grid(g: Dictionary, data: Dictionary):
	var label := "grid seed %d terrain %d size %d" % [int(g.seed), int(g.terrain), int(g.size)]
	var rm = RandomMap.new(int(g.seed), data)
	var probe := [{}]
	var first := func(layout: Dictionary) -> bool:
		probe[0] = layout.duplicate()
		return true
	rm.generate(int(g.terrain), int(g.size), first)
	var layout: Dictionary = probe[0]
	var grid = RandomMapGrid.new(layout, data)
	var nav = RandomMapCheck.CheckNavigation.new(grid)      # navigation.gd without its unused extent-1 layer
	var size := int(g.size)
	var l: Dictionary = nav.layer(2)
	var bits := _unrle(g.cells)
	var materials := _unrle(g.nav_material)
	var heights := _unrle(g.height)
	var regions := _unrle(g.regions_extent2)
	check(bits.size() == size * size and regions.size() == size * size, label + ": fixture cells")
	var bad := {"bits": 0, "material": 0, "height": 0, "region": 0}
	var first_bad := {}
	for y in size:
		for x in size:
			var i := y * size + x
			var cell := Vector2i(x, y)
			var c: Dictionary = grid.cell_data(cell)
			var mine := (1 if nav.passable_extent(cell, 1) else 0) | (2 if nav.passable_extent(cell, 2) else 0) | (4 if not c.object_indices.is_empty() else 0)
			var r: int = l.region_of[i]
			var key := -1 if r < 0 else (int(l.regions[r].sector.y) * (size >> 3) + int(l.regions[r].sector.x)) * 256 + int(l.regions[r].id)
			# The 0x97f6f4 array: border cells 0; the port's field carries the +9 byte's material 9 there (random_map_grid.gd).
			var border := x == 0 or y == 0 or x == size - 1 or y == size - 1
			var array_value := 0 if border else int(c.nav_material)
			if border and int(c.raw[1]) == 9:
				border_nine += 1
				check(int(c.nav_material) == 9 and (bits[i] & 3) == 0, label + ": border material 9 at (%d, %d)" % [x, y])
			for item in [["bits", mine, bits[i]], ["material", array_value, materials[i]], ["height", int(c.raw[0]), heights[i]], ["region", key, regions[i]]]:
				if item[1] != item[2]:
					bad[item[0]] += 1
					if not first_bad.has(item[0]): first_bad[item[0]] = "%s (%d, %d): port %d, original %d" % [item[0], x, y, item[1], item[2]]
	for k in bad:
		check(bad[k] == 0, label + ": %d cells differ in %s, first %s" % [bad[k], k, first_bad.get(k, "")])
	grid_cells += size * size

## RM-4: random_map.gd with the ported check against the original's run (check deciding every attempt): attempts, final
## generator state and layout, and per attempt the corners, every pair's ok / target / chain / first segment and pass.
func _test_checked_case(c: Dictionary, data: Dictionary):
	var label := "checked seed %d terrain %d size %d" % [int(c.seed), int(c.terrain), int(c.size)]
	var rm = RandomMap.new(int(c.seed), data)
	var checker = RandomMapCheck.new(data)
	var got: Dictionary = rm.generate(int(c.terrain), int(c.size), checker.callable())
	check(bool(got.ok) == bool(c.passed), label + ": passed %s, expected %s" % [got.ok, c.passed])
	check(int(got.attempts) == int(c.attempts), label + ": attempts %d, expected %d" % [got.attempts, c.attempts])
	check(int(got.lcg_after) == int(c.lcg_after), label + ": generator %d, expected %d" % [got.lcg_after, c.lcg_after])
	check(_ints(got.goms) == _ints(c.goms) and _tiles(got.tiles) == _tiles(c.tiles), label + ": final layout")
	check(int(got.features.size()) == int(c.feature_count), label + ": features")
	check(checker.records.size() == c.checks.size(), label + ": %d checks, expected %d" % [checker.records.size(), c.checks.size()])
	for k in mini(checker.records.size(), c.checks.size()):
		var mine: Dictionary = checker.records[k]
		var theirs: Dictionary = c.checks[k]
		var at := label + " attempt %d" % (k + 1)
		check(_ints(mine.goms) == _ints(theirs.goms), at + ": layout")
		check(_ints(mine.corners) == _ints(theirs.corners) and mine.corner_found == theirs.corner_found,
			at + ": corners %s, expected %s" % [mine.corners, theirs.corners])
		check(bool(mine.passed) == bool(theirs.passed), at + ": passed %s, expected %s" % [mine.passed, theirs.passed])
		check(mine.pairs.size() == theirs.pairs.size(), at + ": %d pairs, expected %d" % [mine.pairs.size(), theirs.pairs.size()])
		for n in mini(mine.pairs.size(), theirs.pairs.size()):
			var p: Dictionary = mine.pairs[n]
			var q: Dictionary = theirs.pairs[n]
			var same: bool = _ints([p.pair, p.start, p.goal, p.target]) == _ints([q.pair, q.start, q.goal, q.target]) \
				and bool(p.ok) == bool(q.ok) and int(p.chain) == int(q.chain) \
				and (not bool(q.ok) or int(p.first_segment) == int(q.first_segment))
			check(same, at + " pair %s: port %s, original %s" % [q.pair, p, q])

## A7, deliberate modern change: a slot where no piece fits stops after one generator period; every attempt dead-ends
## here, so generate() returns ok = false after MAX_DEAD_ENDS layouts instead of hanging like the original.
func _test_dead_end(data: Dictionary):
	var synthetic := data.duplicate()
	var pieces := []
	for i in 8:
		pieces.append({"marker": RandomMap.MARKER, "tiles": ["TGX0", "TGX0", "TGX0", "TGX0", "TGX0", "TGX0", "TGX0", "TGX0", "TGX0"],
			"skip": [0, 0, 0, 0, 0, 0, 0, 0, 0], "edges": [3, 1, 4, 2], "features": []})
	synthetic.sets = {"stuck": {"name": "stuck", "pieces": pieces}}
	synthetic.terrain_types = [{"terrain": 0, "set": "stuck", "count": 8}]
	var rm = RandomMap.new(0, synthetic)
	var started := Time.get_ticks_msec()
	var got: Dictionary = rm.generate(0, 64)
	check(not bool(got.ok) and int(got.dead_ends) == RandomMap.MAX_DEAD_ENDS and int(got.attempts) == RandomMap.MAX_DEAD_ENDS,
		"a dead-end slot stops at the bound (ok %s, dead ends %d)" % [got.ok, got.dead_ends])
	print("Random map: dead-end bound, %d attempts in %d ms" % [got.attempts, Time.get_ticks_msec() - started])
