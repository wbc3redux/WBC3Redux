extends RefCounted
## RM-4 (RANDOM_MAP_RESEARCH.md "RM-4"): the connectivity check 0x582310 runs after the layout (0x582a4b .. 0x582bcb, A11),
## for random_map.gd's `generate(terrain, size, check.callable())`. On the attempt's collision grid
## (random_map_grid.gd) and navigation.gd's sector layer and search, unchanged:
## * the corners (4, 4), (w-4, 4), (w-4, h-4), (4, h-4), each through 0x43b4c0(x, y, ..., 0, 1) = the free-cell finder
##   0x530a90 for movement type 0, extent 1: navigation.gd free_cell_near (Emulated);
## * the 12 ordered pairs, corner i outer, j inner, i != j, each 0x430e70(start, goal, 0, &n, 0, 0) on a fresh path
##   object 0x42dd80(0); the first failure fails the check (the original then deletes the features and lays the map
##   out again, 0x582d1d). 0x430e70 for a path without unit or target object is the extent-2 ground planner:
##   - start and goal within 1 .. size-2, start == goal passes;
##   - the start's extent-2 region (cell +0x1c, 0x42d140(x, y, 2)), none fails; the flood 0x509320 over the extent-2
##     layer (navigation layer(2), _layer_flood); the goal sector 0x50a8e0 (_layer_goal_sector), none fails;
##   - the target cell 0x432af0 (below), none fails; target == start passes;
##   - the region chain 0x430e00 from the target's region along the flood parents (its length, `chain`), then only
##     the FIRST segment 0x432810: chain count - 4 < 1 -> the target, else 0x432af0 at the sector centre of chain entry
##     count - 4; the extent-2 search 0x431440 to it with f <= 150 (navigation search, extent 2). Its result is the
##     pair's: later segments are never searched by the check.
## * 0x432af0(target, sector, region id): the region and its links are marked with the region stamp 0x430df0 (a
##   post-increment of 0x7bf678, which 0x42de40 resets to 0); a link is marked only when its material byte is 0xff or
##   cost row 1 of it is < 100 (true for every region material); the nearest (Chebyshev, strictly closer replaces, x
##   outer, y inner) cell of the 18 x 18 window from the sector's (x * 8 - 5, y * 8 - 5) inside 1 .. size-2 whose
##   extent-2 region carries the stamp and that passes 0x42cad0 (extent 2: navigation enterable_extent(cell, 2)).
##   Quirk kept: regions start with stamp 0, so the FIRST 0x432af0 call after the grid is built (stamp 0) accepts a cell
##   of any never-marked region in the window, not just the goal region and its links (Emulated: pair (0, 1)).
## Every pair's ok / target / chain / first-segment length equals tests/random_map_check_fixtures.json.

const Navigation = preload("res://battle/navigation.gd")
const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapGrid = preload("res://simulation/random_map_grid.gd")
const CORNER := 4
const EXTENT := 2
const SEGMENT_LIMIT := 150
const CHAIN_STEP := 4

## navigation.gd as is, without its extent-1 sector layer: the check reads only the extent-2 layer (built lazily by
## layer(2)) and the free-cell finder, which needs no regions. Saves the eager build (0.7 s on a 256 map); no other change.
class CheckNavigation extends Navigation:
	func build_sectors(_changed: Array = []):
		_layers.clear()

var data: Dictionary
var records: Array = []                    # one per check call (attempt): passed, corners, corner_found, pairs
var _stamp_counter := 0
var _stamps := PackedInt32Array()

func _init(piece_data: Dictionary = {}):
	data = piece_data if not piece_data.is_empty() else RandomMap.load_data()

func callable() -> Callable:
	return check

## The check of one attempt: random_map.gd's layout (size, maph, features) -> passed.
func check(layout: Dictionary) -> bool:
	var grid = RandomMapGrid.new(layout, data)
	var nav = CheckNavigation.new(grid)
	var record := run(nav, int(layout.size))
	record.goms = layout.goms.duplicate(true)
	record.features = layout.features.size()
	records.append(record)
	return bool(record.passed)

func run(nav, size: int) -> Dictionary:
	_stamp_counter = 0                     # 0x42de40: DAT_007bf678 = 0
	var l: Dictionary = nav.layer(EXTENT)
	_stamps.resize(l.regions.size())
	_stamps.fill(0)                        # new regions carry stamp 0
	var xs := [CORNER, size - CORNER, size - CORNER, CORNER]
	var ys := [CORNER, CORNER, size - CORNER, size - CORNER]
	var corners := []
	var found := []
	for i in 4:
		var c: Vector2i = nav.free_cell_near(Vector2i(xs[i], ys[i]), null, 1, 0)
		corners.append([c.x, c.y])
		found.append(c.x != -1 and c.y != -1)
	var pairs := []
	var passed := true
	for i in 4:
		for j in 4:
			if i == j: continue
			var a := Vector2i(corners[i][0], corners[i][1])
			var b := Vector2i(corners[j][0], corners[j][1])
			var p := route_exists(nav, l, a, b, size)
			p.pair = [i, j]
			pairs.append(p)
			if not bool(p.ok):
				passed = false
				break
		if not passed: break
	return {"passed": passed, "corners": corners, "corner_found": found, "pairs": pairs}

## 0x430e70 for a ground path without unit or target object: ok, target (path +0x2a), chain (+0x1644), first_segment.
func route_exists(nav, l: Dictionary, a: Vector2i, b: Vector2i, size: int) -> Dictionary:
	var out := {"start": [a.x, a.y], "goal": [b.x, b.y], "ok": false, "target": [0, 0], "chain": 0, "first_segment": 0}
	if b.x < 1 or b.y < 1 or b.x >= size - 1 or b.y >= size - 1 or a.x < 1 or a.y < 1 or a.x >= size - 1 or a.y >= size - 1:
		return out
	out.target = [b.x, b.y]
	if a == b:
		out.ok = true
		return out
	var start_region: int = nav._layer_region(l, a)
	if start_region < 0: return out
	nav._layer_flood(l, start_region, 0)
	var goal: Dictionary = nav._layer_goal_sector(l, b)
	if goal.sector.x < 0: return out
	var target := cell_in_region(nav, l, b, goal.sector, int(goal.id), size)
	if target.x < 0: return out
	if target == a:
		out.ok = true
		return out
	out.target = [target.x, target.y]
	var chain: Array[int] = []
	var node: int = nav._layer_region(l, target)
	while node >= 0:
		chain.append(node)
		node = int(l.regions[node].parent)
	out.chain = chain.size()
	if chain.is_empty(): return out
	var k := chain.size() - CHAIN_STEP
	var waypoint := target
	if k >= 1:
		var entry: Dictionary = l.regions[chain[k]]
		waypoint = cell_in_region(nav, l, entry.rep, entry.sector, int(entry.id), size)
		if waypoint.x < 0: return out
	var result: Dictionary = nav.search(a, waypoint, SEGMENT_LIMIT, false, null, EXTENT)
	if bool(result.ok):
		out.ok = true
		out.first_segment = result.cells.size()
	return out

## 0x432af0: the nearest eligible cell to `target` around `sector` in the stamped regions (see the header).
func cell_in_region(nav, l: Dictionary, target: Vector2i, sector: Vector2i, region_id: int, size: int) -> Vector2i:
	var node := -1
	for index in l.sector_regions.get(sector, []):
		if int(l.regions[index].id) == region_id:
			node = index
			break
	if node < 0: return Vector2i(-1, -1)
	var stamp := _stamp_counter
	_stamp_counter += 1
	_stamps[node] = stamp
	for other in l.regions[node].links: _stamps[other] = stamp
	var x0 := maxi(1, sector.x * 8 - 5)
	var y0 := maxi(1, sector.y * 8 - 5)
	var x1 := mini(x0 + 18, size - 2)
	var y1 := mini(y0 + 18, size - 2)
	var best := Vector2i(-1, -1)
	var best_distance := 0
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			var cell := Vector2i(x, y)
			var region: int = nav._layer_region(l, cell)
			if region < 0 or _stamps[region] != stamp or not nav.enterable_extent(cell, EXTENT): continue
			var distance := maxi(absi(target.x - x), absi(target.y - y))
			if best.x < 0 or distance < best_distance:
				best = cell
				best_distance = distance
	return best
