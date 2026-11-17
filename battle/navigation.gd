extends RefCounted

# Port of the original grid search FUN_0042e180 and of the ground route planner 0x42f650/0x42ff30
# with its 8x8 sector layer (0x5090c0, 0x509320, 0x50a8e0, 0x430b80, 0x430e00). Both are verified
# against Unicorn emulation of the executable; see MOVEMENT_RESEARCH.md, tests/pathfinder_fixtures.json
# and tests/route_fixtures.json. Group orders follow 0x530870 / 0x530f80 / 0x40c770.
const SEARCH_ORDER = [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
const CAP_STATIC := 1999
const CAP_UNIT_AWARE := 3999
const DYNAMIC_BUILDING_BASE := 100000 # region owner token for buildings placed after map load.
const SEGMENT_LIMIT := 150 # 0x42ff30 searches each segment with f <= 0x96.
const CHAIN_STEP := 4 # 0x42ff30 targets chain entry count-4, then every fourth region.
# Formation 1 (the unit default, 0x519ae0; no other setter was found) from the table at 0x5fcc9c:
# row n-1 holds (dx, dy) pairs for slots 0..n-1 of an n-unit group, facing south (direction 4).
const FORMATION_1 = [
	[0, 0],
	[0, 0, 0, 2],
	[0, 0, 1, 2, -1, 2],
	[0, 0, 2, 0, -2, 0, 0, 2],
	[0, 0, 0, -2, 2, 0, -2, 0, 0, 2],
	[0, 0, 0, -2, 2, 0, -2, 0, 1, 2, -1, 2],
	[0, 0, 1, -2, -1, -2, 2, 0, -2, 0, 1, 2, -1, 2],
	[1, 0, -1, 0, 1, -2, -1, -2, 3, 0, -3, 0, 1, 2, -1, 2],
	[1, 0, -1, 0, 1, -2, -1, -2, 3, 0, -3, 0, 2, 2, -2, 2, 0, 2],
	[1, 0, -1, 0, 2, -2, -2, -2, 0, -2, 3, 0, -3, 0, 2, 2, -2, 2, 0, 2],
	[1, 1, -1, 1, 0, -1, 0, -3, -2, 3, -3, -1, 3, 1, -3, 1, 2, 3, 3, -1, 0, 3],
	[1, 1, -1, 1, 0, -1, 1, -3, 3, 1, -2, 3, -3, -1, -1, -3, -3, 1, 2, 3, 3, -1, 0, 3],
	[1, 1, -1, 1, 1, -1, -1, -1, 1, -3, -3, 1, 3, -1, 2, 3, -1, -3, -3, -1, -2, 3, 3, 1, 0, 3],
	[1, 1, -1, 1, 1, -1, -1, -1, 0, -3, 3, 1, -3, -1, -2, 3, 2, -3, -3, 1, 2, 3, 3, -1, -2, -3, 0, 3],
	[1, -1, -1, -1, 0, 1, 2, 1, -2, 1, 0, -3, 0, 3, 2, 3, 3, -2, -2, 3, -4, 0, 4, 2, -4, 2, -3, -2, 4, 0],
	[0, -1, 2, -1, -2, -1, 0, 1, 2, 1, -2, 1, 0, -3, 2, 3, -2, -3, -4, -1, 4, 1, -4, 1, -2, 3, 2, -3, 4, -1, 0, 3],
	[0, -1, 2, -1, -2, -1, 0, 1, 2, 1, -2, 1, 0, -3, 4, -1, -4, 1, 1, 3, 4, 1, -2, -3, -3, 3, 2, -3, -4, -1, 3, 3, -1, 3],
	[0, -1, 2, -1, -2, -1, 0, 1, 2, 1, -2, 1, 1, -3, -3, -3, -4, 1, 4, -1, 1, 3, -3, 3, 3, -3, 4, 1, -4, -1, 3, 3, -1, -3, -1, 3],
	[0, 0, 1, -2, -1, -2, 1, 2, -1, 2, 2, 0, -2, 0, 0, -4, -4, 0, 4, 0, 0, 4, -2, -4, 2, -4, 3, -2, -2, 4, 3, 2, -3, 2, -3, -2, 2, 4],
	[0, 0, 1, -2, -1, -2, 1, 2, -1, 2, 2, 0, -2, 0, 0, -4, 1, 4, 4, 0, -4, 0, 2, -4, -2, -4, -1, 4, 3, -2, -4, 2, 4, 2, -3, -2, 3, 4, -3, 4],
	[0, 0, 1, -2, -1, -2, 1, 2, -1, 2, 2, 0, -2, 0, 1, -4, 1, 4, 4, 0, -4, 0, 3, -4, -3, -4, -1, 4, 4, -2, -4, 2, 4, 2, -4, -2, 3, 4, -3, 4, -1, -4],
	[0, 0, 0, 2, 0, -2, 2, -2, 2, 0, -2, 0, 2, 2, -2, 2, -2, -2, 0, -4, 4, 0, -4, 0, 1, 4, -3, 4, 2, -4, -4, -2, 4, 2, 3, 4, -2, -4, 4, -2, -4, 2, -1, 4],
	[0, 0, 0, 2, 0, -2, 2, -2, 2, 0, -2, 0, 2, 2, -2, 2, -2, -2, -1, -4, 4, 0, -4, 0, 1, 4, -3, 4, 3, -4, -4, -2, 4, 2, 3, 4, -3, -4, 4, -2, -4, 2, -1, 4, 1, -4],
	[1, 0, -1, 0, 0, 2, 0, -2, 3, 0, -3, 0, 2, -2, -2, -2, 2, 2, -2, 2, 1, -4, 1, 4, -5, 0, 5, 0, 4, 2, -4, -2, -4, 2, 4, -2, -1, 4, -1, -4, 3, -4, 3, 4, -3, 4, -3, -4],
	[0, 0, 0, -2, 0, 2, 2, 0, -2, 0, 2, -2, -2, -2, 2, 2, -2, 2, 4, 0, -4, 0, 1, -4, 1, 4, 6, 0, -6, 0, -1, -4, -1, 4, 4, -2, -4, 2, -4, -2, 4, 2, 3, -4, 3, 4, -3, -4, -3, 4],
	[0, 0, 0, -2, 0, 2, 2, 0, -2, 0, 2, -2, -2, -2, 2, 2, -2, 2, 4, 0, -4, 0, 1, -4, 2, 4, 6, 0, -6, 0, -1, -4, -2, 4, 5, -2, -5, 2, -5, -2, 5, 2, 3, -4, 4, 4, -3, -4, -4, 4, 0, 4],
	[1, -1, -1, -1, 1, 1, -1, 1, 3, -1, -3, -1, 3, 1, -3, 1, 1, 3, -1, 3, 1, -3, -1, -3, 0, -5, 1, 5, -5, 1, 5, 1, -1, 5, 2, -5, -2, -5, 4, 3, -4, 3, 4, -3, -4, -3, 5, -1, -5, -1, 3, 5, -3, 5],
	[1, -1, -1, -1, 1, 1, -1, 1, 3, -1, -3, -1, 3, 1, -3, 1, 1, 3, -1, 3, 1, -3, -1, -3, 1, -5, 1, 5, -5, 1, 5, 1, -1, 5, 3, -5, -1, -5, 4, 3, -4, 3, 4, -3, -4, -3, 5, -1, -5, -1, 3, 5, -3, 5, -3, -5],
	[1, -1, -1, -1, 1, 1, -1, 1, 0, 3, 1, -3, -1, -3, 3, -1, -3, -1, 3, 1, -3, 1, 2, 3, -2, 3, 1, -5, -1, -5, 1, 5, -1, 5, 4, -3, -4, -3, 4, 3, -4, 3, 5, 1, -5, -1, 5, -1, -5, 1, 3, -5, 3, 5, -3, -5, -3, 5],
	[1, -1, -1, -1, 1, 1, -1, 1, 0, 3, 0, -3, -2, -3, 3, -1, -3, -1, 3, 1, -3, 1, 2, 3, -2, 3, 2, -3, -1, -5, 1, 5, -1, 5, 1, -5, -4, -3, 4, 3, -4, 3, 5, 1, -5, -1, 5, -1, -5, 1, 3, -5, 3, 5, -3, -5, -3, 5, 4, -3],
	[1, -1, -1, -1, 0, 1, -2, 1, 0, 3, 0, -3, -2, -3, 3, -1, -3, -1, 2, 1, -4, 1, 2, 3, -2, 3, 2, -3, 4, 1, 1, 5, -1, 5, 1, -5, -4, -3, -1, -5, -5, 3, 5, 3, -5, -1, 5, -1, -6, 1, 3, -5, 3, 5, -3, -5, -3, 5, 4, -3, 6, 1],
	[0, -1, -2, -1, 0, 1, -2, 1, 0, 3, 0, -3, -2, -3, 2, -1, -4, -1, 2, 1, -4, 1, 2, 3, -2, 3, 2, -3, 4, 1, 4, -1, -1, 5, 1, -5, -5, -3, -1, -5, -5, 3, 5, 3, 1, 5, 6, -1, -6, 1, 3, -5, 3, 5, -3, -5, -3, 5, 5, -3, 6, 1, -6, -1],
]
var collision: RefCounted
var occupants: Dictionary = {} # Vector2i -> unit; original cell +0x14 occupant for 1x1 footprints.
var building_cells: Dictionary = {} # Vector2i -> building id; cells stamped by 0x52a6b0 after map load.
# Performance (P-1): building id -> its cells in building_cells' own iteration order, so a scan of one building's cells
# visits them in the order a scan of the whole dictionary would (same nearest cell on ties). Rebuilt on first use after a
# change: stamp_building / unstamp_building / set_building_cell bump building_version, and a size change (a direct write
# or clear()) is caught too.
var building_version := 0
var _cells_by_building: Dictionary = {}
var _cells_index_version := -1
var _cells_index_size := -1
const NO_CELLS: Array = []

func cells_of_building(id: int) -> Array:
	if _cells_index_version != building_version or _cells_index_size != building_cells.size():
		_cells_by_building = {}
		for cell in building_cells:
			var owner_id: int = building_cells[cell]
			var list = _cells_by_building.get(owner_id)
			if list == null:
				list = []
				_cells_by_building[owner_id] = list
			list.append(cell)
		_cells_index_version = building_version
		_cells_index_size = building_cells.size()
	return _cells_by_building.get(id, NO_CELLS)

## A direct building cell write (encounters' lairs and static objects) that keeps the index current.
func set_building_cell(cell: Vector2i, id: int):
	building_cells[cell] = id
	building_version += 1
var next_detour_ms := 0 # Original 0x4308b0: one detour search per 100 ms, shared by all units.
# The clock that throttle reads: 0x4308b0 compares timeGetTime, one clock for every unit (Read). Each walker keeps its
# view of it (unit_agent.gd `clock_ms`, from this value when it first advances) and pushes it forward.
var clock_ms := 0.0
# Sector layer, extent 1: regions are 8-connected cells of one 8x8 sector (0x509f30/0x50a370).
var region_of := PackedInt32Array() # cell -> region index, -1 for none
var regions: Array[Dictionary] = [] # sector, id, rep (sector centre), building, links
var sector_regions: Dictionary = {} # Vector2i sector -> Array of region indices in creation order
var _stamp := PackedInt32Array()
var _parent := PackedInt32Array()
var _g := PackedInt32Array()
var _generation := 0

func _init(source: RefCounted):
	collision = source
	rebuild()

func rebuild():
	var count: int = collision.width * collision.height
	_stamp.resize(count)
	_stamp.fill(0)
	_parent.resize(count)
	_g.resize(count)
	_generation = 0
	build_sectors()

func center(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * 32 + 16, cell.y * 24 + 12)

# Border cells are never entered by the original search.
func enterable_static(cell: Vector2i) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < collision.width - 1 and cell.y < collision.height - 1 and is_passable(cell)

# Static map passability (0x42cc10, mode 0) plus buildings stamped since map load.
func is_passable(cell: Vector2i) -> bool:
	return collision.is_passable(cell) and not building_cells.has(cell)

# Cells that fail the mode-0 check only through building counters (0x42c2c0 +0x10) still pass
# 0x42cda0 and form their own regions per building occupant. On Desert Sands these are exactly the
# interior building cells (emulated grid audit). Returns the building's object index or -1.
# `mtype` 2 tests the water row instead of the land row (water regions, map wave 3).
func building_owner(cell: Vector2i, mtype: int = 0) -> int:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= collision.width - 1 or cell.y >= collision.height - 1:
		return -1
	var c: Dictionary = collision.cell_data(cell)
	if c.is_empty() or not c.profile_passable[0 if mtype == 0 else 2] or not collision.data.has("objects"):
		return -1
	if building_cells.has(cell) and c.object_indices.is_empty():
		return DYNAMIC_BUILDING_BASE + int(building_cells[cell])
	for index in c.object_indices:
		if collision.data.objects[int(index)].kind == "buildings":
			return int(index)
	return -1

func region(cell: Vector2i) -> int:
	return region_of[cell.y * collision.width + cell.x] if collision.inside(cell) else -1

var sector_builds := 0                   # profiling (tests/profile_sim.gd): calls and microseconds of build_sectors
var sector_build_us := 0

## `changed`: the cells whose passability changed since the last build (a building stamped or removed); empty = everything.
func build_sectors(changed: Array = []):
	var t0 := Time.get_ticks_usec()
	if changed.is_empty() or regions.is_empty() or region_of.size() != collision.width * collision.height: _build_sectors()
	else: _rebuild_sectors(changed)
	sector_builds += 1
	sector_build_us += Time.get_ticks_usec() - t0

func _build_sectors():
	_layers.clear()                      # the extent-2 layer is rebuilt on its next use
	_stale_layers.clear()
	_layer_cells.clear()
	var width: int = collision.width
	var height: int = collision.height
	region_of.resize(width * height)
	region_of.fill(-1)
	regions.clear()
	sector_regions.clear()
	for sx in range(((width - 1) >> 3) + 1):
		for sy in range(((height - 1) >> 3) + 1):
			var list: Array = []
			sector_regions[Vector2i(sx, sy)] = list
			_flood_sector(sx, sy, list)
	# 0x50a5c0: links in discovery order, scanning x outer, y inner, neighbours dx outer, dy inner.
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			var own: int = region_of[y * width + x]
			if own < 0: continue
			var links: PackedInt32Array = regions[own].links
			var grown := false
			for nx in range(x - 1, x + 2):
				for ny in range(y - 1, y + 2):
					var other: int = region_of[ny * width + nx]
					if other >= 0 and other != own and not links.has(other):
						links.append(other)
						grown = true
			if grown: regions[own].links = links
	_memo_land = PackedInt32Array()
	_memo_water = PackedInt32Array()

## 0x509f30 for one 8 x 8 sector (its regions never leave it): seeds in y-outer / x-inner order, each flooded over the
## sector's cells; new regions are appended to `regions` and `list` (the sector's cells must be -1 in region_of).
func _flood_sector(sx: int, sy: int, list: Array):
	var width: int = collision.width
	var height: int = collision.height
	var sector := Vector2i(sx, sy)
	for y in range(maxi(1, sy * 8), mini(sy * 8 + 8, height - 1)):
		for x in range(maxi(1, sx * 8), mini(sx * 8 + 8, width - 1)):
			var seed := Vector2i(x, y)
			if region(seed) >= 0:
				continue
			# 0x509f30: the seed's material class (0x603ed0) picks the region's type: land seeds type 0, water
			# seeds type 2; classes 2 and 3 seed nothing (Emulated, tests/water_fixtures.json).
			var material := material_of(seed)
			var cls: int = MATERIAL_CLASS[material] if material < MATERIAL_CLASS.size() else 2
			if cls >= 2:
				continue
			var rtype := 0 if cls == 0 else 2
			var owner := -1
			if not _sector_enterable(seed, rtype):
				owner = _sector_owner(seed, rtype)
				if owner < 0:
					continue
			var index := regions.size()
			regions.append({"sector": sector, "id": list.size(), "rep": Vector2i(sx * 8 + 4, sy * 8 + 4),
				"building": owner >= 0, "material": BUILDING_REGION if owner >= 0 else material,
				"links": PackedInt32Array(), "dist": -1, "parent": -1})
			list.append(index)
			region_of[y * width + x] = index
			var stack: Array[Vector2i] = [seed]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for nx in range(c.x - 1, c.x + 2):
					for ny in range(c.y - 1, c.y + 2):
						var n := Vector2i(nx, ny)
						if nx >> 3 != sx or ny >> 3 != sy or nx <= 0 or ny <= 0 or nx >= width - 1 or ny >= height - 1 or region_of[ny * width + nx] >= 0:
							continue
						if owner < 0:
							if not _sector_enterable(n, rtype): continue
						elif _sector_enterable(n, rtype) or _sector_owner(n, rtype) != owner:
							continue
						region_of[ny * width + nx] = index
						stack.append(n)

## Performance (P-2): build_sectors for a few changed cells. Regions never leave their sector, so only the sectors holding a
## changed cell are flooded again; the others keep their regions, renumbered in the sector order a full build uses. Links
## are found again for the regions of the changed sectors and their neighbours (the only ones whose neighbouring cells can
## have changed) in the full build's scan order, and remapped for every other region. The result equals _build_sectors
## (tests/test_sector_rebuild.gd compares the two after every stamp and removal).
func _rebuild_sectors(changed: Array):
	_retire_layers()                     # P-3: the extent-2 layer is rebuilt in part on its next use
	var width: int = collision.width
	var height: int = collision.height
	var sw := ((width - 1) >> 3) + 1
	var sh := ((height - 1) >> 3) + 1
	var dirty := PackedByteArray()
	dirty.resize(sw * sh)
	for cell in changed:
		if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height: dirty[(cell.x >> 3) * sh + (cell.y >> 3)] = 1
	var relink := PackedByteArray()                       # the changed sectors and their eight neighbours
	relink.resize(sw * sh)
	for sx in sw:
		for sy in sh:
			if dirty[sx * sh + sy] == 0: continue
			for ax in range(maxi(0, sx - 1), mini(sw, sx + 2)):
				for ay in range(maxi(0, sy - 1), mini(sh, sy + 2)): relink[ax * sh + ay] = 1
	var old_regions: Array = regions
	var old_sectors: Dictionary = sector_regions
	var remap := PackedInt32Array()
	remap.resize(old_regions.size())
	remap.fill(-1)
	regions = []
	sector_regions = {}
	for sx in sw:
		for sy in sh:
			var sector := Vector2i(sx, sy)
			var list: Array = []
			sector_regions[sector] = list
			var x0 := maxi(1, sx * 8)
			var x1 := mini(sx * 8 + 8, width - 1)
			var y0 := maxi(1, sy * 8)
			var y1 := mini(sy * 8 + 8, height - 1)
			if dirty[sx * sh + sy] == 0:
				for old_index in old_sectors.get(sector, []):
					remap[old_index] = regions.size()
					list.append(regions.size())
					regions.append(old_regions[old_index])
				for y in range(y0, y1):
					for x in range(x0, x1):
						var v: int = region_of[y * width + x]
						if v >= 0: region_of[y * width + x] = remap[v]
				continue
			for y in range(y0, y1):
				for x in range(x0, x1): region_of[y * width + x] = -1
			_flood_sector(sx, sy, list)
	for node in regions:
		node.dist = -1
		node.parent = -1
		var at: Vector2i = node.sector
		if relink[at.x * sh + at.y] != 0:
			node.links = PackedInt32Array()
			continue
		var mapped := PackedInt32Array()
		for other in node.links: mapped.append(remap[other])
		node.links = mapped
	# 0x50a5c0's scan (x outer, y inner, neighbours dx outer, dy inner) over the relinked sectors only: a region's links
	# come from its own cells, all in its sector, in the same relative order as the full scan.
	for sx in sw:
		for sy in sh:
			if relink[sx * sh + sy] == 0: continue
			for x in range(maxi(1, sx * 8), mini(sx * 8 + 8, width - 1)):
				for y in range(maxi(1, sy * 8), mini(sy * 8 + 8, height - 1)):
					var own: int = region_of[y * width + x]
					if own < 0: continue
					var own_links: PackedInt32Array = regions[own].links
					var grown := false
					for nx in range(x - 1, x + 2):
						for ny in range(y - 1, y + 2):
							var other: int = region_of[ny * width + nx]
							if other >= 0 and other != own and not own_links.has(other):
								own_links.append(other)
								grown = true
					if grown: regions[own].links = own_links
	_memo_land = PackedInt32Array()
	_memo_water = PackedInt32Array()

# Performance (P-2): build_sectors asks the same cell up to nine times; these memos answer enterable_extent(cell, 1, rtype) and
# building_owner(cell, rtype) once per cell per build (both are fixed while the build runs), so the regions come out the same.
# Per cell: bits 0-1 enterable (0 not asked, 1 no, 2 yes); the owner + 2 from bit 2 up (0 not asked). Members, not
# dictionary values: a packed array held twice would be copied on every write.
var _memo_land := PackedInt32Array()     # rtype 0
var _memo_water := PackedInt32Array()    # rtype 2

func _sector_memo(cell: Vector2i, rtype: int, owner: bool) -> int:
	var size: int = collision.width * collision.height
	var i: int = cell.y * collision.width + cell.x
	var v: int
	if rtype == 0:
		if _memo_land.size() != size:
			_memo_land.resize(size)
			_memo_land.fill(0)
		v = _memo_land[i]
	else:
		if _memo_water.size() != size:
			_memo_water.resize(size)
			_memo_water.fill(0)
		v = _memo_water[i]
	var changed := false
	if not owner and v & 3 == 0:
		v |= 2 if enterable_extent(cell, 1, rtype) else 1
		changed = true
	if owner and v >> 2 == 0:
		v |= (building_owner(cell, rtype) + 2) << 2
		changed = true
	if changed:
		if rtype == 0: _memo_land[i] = v
		else: _memo_water[i] = v
	return (v & 3) if not owner else (v >> 2) - 2

func _sector_enterable(cell: Vector2i, rtype: int) -> bool:
	return _sector_memo(cell, rtype, false) == 2

func _sector_owner(cell: Vector2i, rtype: int) -> int:
	return _sector_memo(cell, rtype, true)

# 0x509320: bucketed flood from the start region over links; cost 2 when the sector centres share
# x or y, else 3; four circular buckets; a region is closed when first discovered. A region is admitted when it is a
# building region or table 0x603ee0[type][class of its seed material] is set (type 0: land; 2: water; 3: both); a
# building region is reached but only expanded for type 1 (Read; M-3).
func flood_sectors(start_region: int, mtype: int = 0):
	_flood(regions, start_region, mtype)

static func _admitted(node: Dictionary, mtype: int) -> bool:
	if node.building: return true
	var material: int = int(node.get("material", 0))
	return material < MATERIAL_CLASS.size() and ADMISSION[mtype][MATERIAL_CLASS[material]] != 0

static func _flood(nodes: Array, start_region: int, mtype: int):
	for r in nodes:
		r.dist = -1
		r.parent = -1
	nodes[start_region].dist = 1
	var buckets := {0: [start_region]}
	var step := 0
	var empty := 0
	while empty < 4:
		var bucket: Array = buckets.get(step % 4, [])
		buckets.erase(step % 4)
		if bucket.is_empty():
			empty += 1
		else:
			empty = 0
			for index in bucket:
				var node: Dictionary = nodes[index]
				for other in node.links:
					var next: Dictionary = nodes[other]
					if next.dist != -1 or not _admitted(next, mtype): continue
					var cost := 2 if next.rep.x == node.rep.x or next.rep.y == node.rep.y else 3
					next.dist = cost + step
					next.parent = index
					if next.building and mtype != 1 and EXPAND_BUILDINGS_ONLY_FOR_FLYERS: continue
					var slot := (cost + step) % 4
					if not buckets.has(slot): buckets[slot] = []
					buckets[slot].append(other)
		step += 1

# 0x50a8e0: the goal's region when reached, else a spiral over sectors: the first reached region,
# then nine more spiral positions where a reached sector closer by (min/2 + max) replaces it.
func goal_sector(goal: Vector2i) -> Dictionary:
	var own := region(goal)
	if own >= 0 and regions[own].dist >= 0:
		return {"sector": regions[own].sector, "id": regions[own].id}
	var s := Vector2i(goal.x >> 3, goal.y >> 3)
	var best := Vector2i(-1, -1)
	var best_id := -1
	var after := -1
	var direction := 0
	var run := 1
	var steps := 0
	var visited := 0
	while visited < 500:
		if after >= 0:
			after += 1
			if after == 10: break
		if s.x >= 0 and s.y >= 0 and s.x < collision.width >> 3 and s.y < collision.height >> 3:
			visited += 1
			for index in sector_regions.get(s, []):
				var node: Dictionary = regions[index]
				if node.dist < 0: continue
				if after == -1:
					after = 0
					best = s
					best_id = node.id
				elif best != s:
					var candidate := _spread(absi(node.rep.x - goal.x), absi(node.rep.y - goal.y))
					var current := _spread(absi(best.x * 8 - goal.x + 4), absi(best.y * 8 - goal.y + 4))
					if candidate < current:
						best = s
						best_id = node.id
		match direction:
			0: s.x += 1
			1: s.y += 1
			2: s.x -= 1
			3: s.y -= 1
		steps += 1
		if steps == run:
			direction = (direction + 1) % 4
			steps = 0
			if direction == 0 or direction == 2: run += 1
	return {"sector": best, "id": best_id}

static func _spread(dx: int, dy: int) -> int:
	return (mini(dx, dy) >> 1) + maxi(dx, dy)

# 0x430b80: nearest cell (Chebyshev, first wins ties; x outer, y inner) to target within 5 cells of
# the sector that lies in the region or a linked region and passes 0x42cad0. Units do not count:
# its occupant filter 0x42d390 only collects objects whose kind is nonzero (buildings, features).
func sector_cell(target: Vector2i, sector: Vector2i, region_id: int, mtype: int = 0) -> Vector2i:
	var node := -1
	for index in sector_regions.get(sector, []):
		if regions[index].id == region_id:
			node = index
			break
	if node < 0: return Vector2i(-1, -1)
	var marked := {node: true}
	for other in regions[node].links: marked[other] = true
	var x0 := maxi(1, sector.x * 8 - 5)
	var y0 := maxi(1, sector.y * 8 - 5)
	var best := Vector2i(-1, -1)
	for x in range(x0, mini(x0 + 18, collision.width - 2) + 1):
		for y in range(y0, mini(y0 + 18, collision.height - 2) + 1):
			var cell := Vector2i(x, y)
			if not marked.has(region(cell)) or not enterable_extent(cell, 1, mtype): continue
			if best.x < 0 or chebyshev(target, cell) < chebyshev(target, best):
				best = cell
	return best

# Occupied bit +4 & 0x80 of the original cell (0x42c8e0): static objects, stamped buildings, units.
func cell_occupied(cell: Vector2i) -> bool:
	if not collision.inside(cell): return false
	if building_cells.has(cell) or occupant(cell) != null: return true
	var c: Dictionary = collision.cell_data(cell)
	return not c.is_empty() and c.has("object_indices") and not c.object_indices.is_empty()

# 0x52a6b0 (building stamp): every solid mask cell (clear bit) inside the map whose occupant slot
# +0x14 is still empty claims the cell for the building; the 0x509e10/0x5099c0 notifications then
# refresh the sector layer. The refresh is a full rebuild here; tests/production_fixtures.json
# compares whole routes with the original's incremental update.
func stamp_building(id: int, left: int, top: int, width: int, height: int, mask_rows: Array) -> Array[Vector2i]:
	var claimed: Array[Vector2i] = []
	for row in range(height):
		for col in range(width):
			if (int(mask_rows[row]) >> col) & 1: continue
			var cell := Vector2i(left + col, top + row)
			if not collision.inside(cell) or cell_occupied(cell): continue
			building_cells[cell] = id
			claimed.append(cell)
	building_version += 1
	if not claimed.is_empty(): build_sectors(claimed)
	return claimed

# Removal when a building dies (0x52a870 clears the occupied bit and counters; sector refresh).
func unstamp_building(id: int):
	var removed: Array = cells_of_building(id).duplicate()
	for cell in removed: building_cells.erase(cell)
	building_version += 1
	if not removed.is_empty(): build_sectors(removed)

func nav_cell_height(cell: Vector2i) -> int:
	var c: Dictionary = collision.cell_data(cell)
	return int(c.raw[0]) if not c.is_empty() and c.has("raw") else 0

# 0x530a90 (unit creation, message 0xfa): the origin when it is free, else a square spiral (arms
# 1,1,2,2,3,3... starting +x, +y, -x, -y) over at most 300 steps, scoring eligible cells by
# min + 2*(max + 4*|height difference|) of the Chebyshev offsets and keeping the first best one for
# eleven more steps after the first candidate. Eligibility stands in for 0x42cb70: interior, passable, no
# unit (the emulated finder, tests/production_fixtures.json, never accepts a map border cell).
func free_cell_near(origin: Vector2i, mover = null, extent: int = 1, mtype: int = 0) -> Vector2i:
	if extent > 1 or mtype != 0: return _free_cell_extent(origin, mover, extent, mtype)
	var width: int = collision.width
	var height: int = collision.height
	var inside := origin.x >= 0 and origin.y >= 0 and origin.x < width and origin.y < height
	var origin_height: int = nav_cell_height(origin) if inside else 0
	var blocked := not inside
	if inside:
		var c: Dictionary = collision.cell_data(origin)
		if not c.profile_passable[0]: blocked = true
		elif cell_occupied(origin) and occupant(origin, mover) == null: blocked = true # static or building
	if not blocked and occupant(origin, mover) == null and enterable_static(origin):
		return origin
	var cell := origin
	var direction := 0
	var arm := 1
	var walked := 0
	var total := 0
	var after := 0
	var found := false
	var best := 5000
	var chosen := Vector2i(-1, -1)
	while true:
		if after > 10: break
		if found: after += 1
		else: total += 1
		match direction:
			0: cell.x += 1
			1: cell.y += 1
			2: cell.x -= 1
			3: cell.y -= 1
		walked += 1
		if walked == arm:
			walked = 0
			direction = (direction + 1) % 4
			if direction == 0 or direction == 2: arm += 1
		total += 1
		if cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height:
			var other = occupant(cell, mover)
			var static_taken: bool = building_cells.has(cell) or not collision.cell_data(cell).object_indices.is_empty()
			if not static_taken and collision.cell_data(cell).profile_passable[0] and other == null and enterable_static(cell):
				var dx := absi(cell.x - origin.x)
				var dy := absi(cell.y - origin.y)
				var score := mini(dx, dy) + (maxi(dx, dy) + absi(nav_cell_height(cell) - origin_height) * 4) * 2
				if not found or score < best:
					found = true
					best = score
					chosen = cell
		if total >= 300: break
	return chosen

## 0x530a90 with the unit's extent (0x524b00 passes ARM +0x39): the same spiral and score; a cell is eligible when the
## extent's cell check passes and no other unit stands on its footprint (Read; the extent-1 finder is Emulated).
func _free_cell_extent(origin: Vector2i, mover, extent: int, mtype: int = 0) -> Vector2i:
	var eligible := func(c: Vector2i) -> bool: return enterable_extent(c, extent, mtype) and occupant_extent(c, extent, mover) == null
	if collision.inside(origin) and eligible.call(origin): return origin
	var origin_height: int = nav_cell_height(origin) if collision.inside(origin) else 0
	var cell := origin
	var direction := 0
	var arm := 1
	var walked := 0
	var total := 0
	var after := 0
	var found := false
	var best := 5000
	var chosen := Vector2i(-1, -1)
	while true:
		if after > 10: break
		if found: after += 1
		else: total += 1
		match direction:
			0: cell.x += 1
			1: cell.y += 1
			2: cell.x -= 1
			3: cell.y -= 1
		walked += 1
		if walked == arm:
			walked = 0
			direction = (direction + 1) % 4
			if direction == 0 or direction == 2: arm += 1
		total += 1
		if collision.inside(cell) and eligible.call(cell):
			var dx := absi(cell.x - origin.x)
			var dy := absi(cell.y - origin.y)
			var score := mini(dx, dy) + (maxi(dx, dy) + absi(nav_cell_height(cell) - origin_height) * 4) * 2
			if not found or score < best:
				found = true
				best = score
				chosen = cell
		if total >= 300: break
	return chosen

func occupant(cell: Vector2i, mover = null):
	var unit = occupants.get(cell)
	return null if unit == mover or not is_instance_valid(unit) else unit

## A unit claims every cell of its footprint (0x51bb80 clears them again: +0x14 = unit, +4 & 0x80); 1x1 units their cell.
## Flying units (movement type 1) hold the second grid layer instead (cell +0x1c, 0x42e180), so they never block ground
## units, buildings or each other's ground cells (milestone 13).
func occupy(unit, cell: Vector2i):
	if is_flying(unit):
		air_occupants[cell] = unit
		return
	var extent := unit_extent(unit)
	if extent <= 1:
		occupants[cell] = unit
		return
	for c in footprint(cell, extent):
		if collision.inside(c) and not occupants.has(c): occupants[c] = unit

func release(unit, cell: Vector2i):
	if is_flying(unit):
		if air_occupants.get(cell) == unit: air_occupants.erase(cell)
		return
	var extent := unit_extent(unit)
	if extent <= 1:
		if occupants.get(cell) == unit: occupants.erase(cell)
		return
	for c in footprint(cell, extent):
		if occupants.get(c) == unit: occupants.erase(c)

# ---------------------------------------------------------------- movement type 1 (flying, milestone 13)
# RACES_RESEARCH.md 2.1 (Emulated): 0x42e180 searches the second layer for type 1 only; on a map without material 9 every
# cell passes 0x42cc10 there, so a flight is the search's straight route: diagonal steps first, then straight ones (the
# five emulated type-1 routes of tests/races_fixtures.json). Map wave 5 (Emulated, tests/flight_fixtures.json): material 9
# stops flyers too, and a type-1 order is one unlimited 0x42e180 search (one segment, no sector chain), which goes round
# the cave walls. Flyers block only flyers (the layer's occupant).
var air_occupants: Dictionary = {}

static func is_flying(unit) -> bool:
	if unit == null or not is_instance_valid(unit): return false
	var f = unit.get("flying")
	return f != null and bool(f)

func air_occupant(cell: Vector2i, mover = null):
	var unit = air_occupants.get(cell)
	return null if unit == mover or not is_instance_valid(unit) else unit

## The emulated type-1 route shape from `start` (excluded) to `goal` (included).
static func flight_line(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := start
	while c != goal:
		c += Vector2i(signi(goal.x - c.x), signi(goal.y - c.y))
		out.append(c)
	return out

## A flight's cells from `start` to `goal`: 0x42f650 for type 1, one unlimited search on the air layer (map wave 5).
## A goal on material 9 is accepted like any search goal; what the original does with such an order is Open.
func flight_cells(start: Vector2i, goal: Vector2i) -> Dictionary:
	var result := search(start, goal, 0, false, null, 1, 1)
	return {"ok": result.ok, "segments": [result.cells] if result.ok and not result.cells.is_empty() else [], "reason": result.get("reason", "")}

func plan_flight(start: Vector2, requested: Vector2) -> Dictionary:
	var source_cell: Vector2i = collision.world_cell(start)
	var goal_cell: Vector2i = collision.world_cell(requested)
	goal_cell = Vector2i(clampi(goal_cell.x, 0, collision.width - 1), clampi(goal_cell.y, 0, collision.height - 1))
	var flight := flight_cells(source_cell, goal_cell)
	var cells: Array[Vector2i] = []
	for segment in flight.segments: cells.assign(segment)
	var path := PackedVector2Array([start])
	var length_px := 0.0
	for cell in cells:
		length_px += path[-1].distance_to(center(cell))
		path.append(center(cell))
	return {"ok": bool(flight.ok), "cells": cells, "segments": [cells] if not cells.is_empty() else [], "path": path, "length_px": length_px,
		"steps": cells.size(), "requested": requested, "target": center(goal_cell), "snapped": false}

## 0x530a90's spiral for a flyer: the first cell inside the map without a flyer (the air layer has no terrain test).
func free_air_cell_near(origin: Vector2i, mover = null) -> Vector2i:
	var c := origin
	var arm := 1
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var d := 0
	var steps := 0
	if collision.inside(c) and air_occupant(c, mover) == null: return c
	while steps < 300:
		for _repeat in 2:
			for _i in arm:
				c += dirs[d]
				steps += 1
				if collision.inside(c) and air_occupant(c, mover) == null: return c
			d = (d + 1) % 4
		arm += 1
	return Vector2i(-1, -1)

# ---------------------------------------------------------------- movement types 2 and 3 (water / amphibious, milestone M-3)
# MOVEMENT_RESEARCH.md "Water". 0x42ca40 maps types 0, 2 and 3 to the ground layer (cell +0x18), so water and amphibious
# units share the ground units' occupancy. Cell +8 holds one land flag and one water flag per extent: 0x42c130 / 0x42c070
# set them around a cell whose land (row 0) / water (row 2) cost at 0x603e68 is over 100, 0x42c380 sets both around a
# feature. 0x42cc10 (mode 0) passes type 0 without the land flag, type 2 without the water flag and type 3 unless both
# are set; material 9 at the anchor and building counters block every type (Emulated, tests/water_fixtures.json).
const MATERIAL_CLASS := [0, 0, 0, 1, 0, 1, 0, 0, 0, 3, 2, 0, 2]     # 0x603ed0 per nav material: 0 land, 1 water, 2/3 none
const ADMISSION := [[1, 0, 0, 0], [1, 1, 1, 0], [0, 1, 0, 0], [1, 1, 0, 0]] # 0x603ee0[type][class]: regions a type floods
const BUILDING_REGION := 255             # region +4 of a building region (0x509f30)
const EXPAND_BUILDINGS_ONLY_FOR_FLYERS := true
var _typed_static: Dictionary = {}       # extent -> PackedByteArray: 1 land flag, 2 map building counter, 4 water flag, 8 material 9

func material_of(cell: Vector2i) -> int:
	var c: Dictionary = collision.cell_data(cell)
	return int(c.get("nav_material", 0)) if not c.is_empty() else 12   # synthetic test grids have land only

## The cell's +9 byte is 9: 0x42bf80 writes the raw TER material into every cell (permission 0 and the border included), and
## 0x42cc10 / 0x42cda0 fail such an anchor for every movement type (G1, RM-4; map wave 5: on the cave maps 1,012
## material-9 cells of permission 0 carry nav material 12 and still stop flyers). `nav_material` 9 is collision.py's
## carrier for the border cells; synthetic grids without `raw` use it alone.
static func hard_block(c: Dictionary) -> bool:
	if int(c.get("nav_material", 0)) == 9: return true
	var r = c.get("raw")
	return r != null and r.size() > 1 and int(r[1]) == 9

func _typed_for(extent: int) -> PackedByteArray:
	if _typed_static.has(extent): return _typed_static[extent]
	var width: int = collision.width
	var height: int = collision.height
	var source := PackedByteArray()
	source.resize(width * height)
	for i in width * height:
		var c: Dictionary = collision.data.cells[i]
		var bits := 0
		if not c.profile_passable[0]: bits |= 1
		if c.profile_passable.size() < 3 or not c.profile_passable[2]: bits |= 4
		bits |= _object_bits(c, 5)
		source[i] = bits
	var out := PackedByteArray()
	out.resize(width * height)
	for y in height:
		for x in width:
			var bits := 0
			if extent <= 1:
				bits = source[y * width + x]
			else:
				for c in footprint(Vector2i(x, y), extent):
					if c.x >= 0 and c.y >= 0 and c.x < width and c.y < height: bits |= source[c.y * width + c.x]
			if hard_block(collision.data.cells[y * width + x]): bits |= 8
			out[y * width + x] = bits
	_typed_static[extent] = out
	return out

## 0x42cc10 (counters true) / 0x42cda0 (counters false) for movement types 2 and 3; `cell` must be inside the map.
func _typed_ok(cell: Vector2i, extent: int, mtype: int, counters: bool) -> bool:
	var bits: int = _typed_for(extent)[cell.y * collision.width + cell.x]
	if bits & 8: return false
	# Type 1 (the air layer): only material 9 at the anchor fails; terrain flags and the ground layer's building counters
	# do not (Emulated, tests/material_fixtures.json: the type-1 count is exactly the material-9 cells; map wave 5).
	if mtype == 1: return true
	if mtype == 2:
		if bits & 4: return false
	elif (bits & 5) == 5:
		return false
	if not counters: return true
	if bits & 2: return false
	if building_cells.is_empty(): return true
	if extent <= 1: return not building_cells.has(cell)
	for c in footprint(cell, extent):
		if building_cells.has(c): return false
	return true

## Movement type of a unit (ARM +5): 0 ground, 1 flying, 2 water, 3 amphibious.
static func unit_mtype(unit) -> int:
	if unit == null or not is_instance_valid(unit): return 0
	var t = unit.get("movement_type")
	return 0 if t == null else int(t)

static func unit_extent(unit) -> int:
	if unit == null or not is_instance_valid(unit): return 1
	var e = unit.get("extent")
	return 1 if e == null else maxi(1, int(e))

# ---------------------------------------------------------------- extents 2 and 3 (milestone 11a, RACES_RESEARCH.md)
# A unit of extent e (ARM +0x38/+0x39) standing on its anchor cell covers x from x - ((e-1) >> 1) to + e - 1 and y from
# y - e + 1 to y (0x51bb80). One blocker raises the extent-e flag / counter of exactly the anchors whose footprint contains
# it: terrain (row-0 cost > 100, 0x42c130), features (0x42c380) set the +8 bits, buildings the +6 / +7 counters
# (0x42c2c0). 0x42cc10 (extent e) fails on material 9 at the anchor, a flag or a counter; 0x42cda0 (the sector layer's
# check) ignores the counters. Emulated on every Desert Sands cell for extents 1..3 (tests/large_unit_fixtures.json).
var _extent_static: Dictionary = {}      # extent -> PackedByteArray per cell: 1 = flag / hard (0x42cda0 fails), 2 = map building counter
var _layers: Dictionary = {}             # extent -> sector layer (extent 2 only; built lazily, dropped on every stamp)

static func footprint(anchor: Vector2i, extent: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var x0 := anchor.x - ((extent - 1) >> 1)
	for dy in range(extent):
		for dx in range(extent):
			out.append(Vector2i(x0 + dx, anchor.y - extent + 1 + dy))
	return out

## A map building claims its cells first (cell +0x14); the feature stamp skips a claimed cell, so a feature sharing a cell
## with a building adds no flags there, only the building counter (2). Emulated: next-door (8, 31), BWTC with FPM7.
func _object_bits(c: Dictionary, feature_bits: int) -> int:
	var bits := 0
	for index in c.object_indices:
		if collision.data.objects[int(index)].kind == "buildings": return 2
		bits = feature_bits
	return bits

func _static_for(extent: int) -> PackedByteArray:
	if _extent_static.has(extent): return _extent_static[extent]
	var width: int = collision.width
	var height: int = collision.height
	var source := PackedByteArray()
	source.resize(width * height)
	for i in width * height:
		var c: Dictionary = collision.data.cells[i]
		var bits := 0
		if not c.profile_passable[0]: bits |= 1
		bits |= _object_bits(c, 1)
		source[i] = bits
	var out := PackedByteArray()
	out.resize(width * height)
	for y in height:
		for x in width:
			var bits := 0
			for c in footprint(Vector2i(x, y), extent):
				if c.x >= 0 and c.y >= 0 and c.x < width and c.y < height: bits |= source[c.y * width + c.x]
			if hard_block(collision.data.cells[y * width + x]): bits |= 1
			out[y * width + x] = bits
	_extent_static[extent] = out
	return out

## 0x42cda0 for `extent`: no material 9 at the anchor and no terrain / feature flag (building counters ignored).
func sector_passable(cell: Vector2i, extent: int, mtype: int = 0) -> bool:
	if not collision.inside(cell): return false
	if mtype != 0: return _typed_ok(cell, extent, mtype, false)
	return (_static_for(extent)[cell.y * collision.width + cell.x] & 1) == 0

## 0x42cc10 mode 0 for movement type `mtype` and `extent` (type 0 extent 1 is is_passable, unchanged).
func passable_extent(cell: Vector2i, extent: int, mtype: int = 0) -> bool:
	if mtype != 0: return collision.inside(cell) and _typed_ok(cell, extent, mtype, true)
	if extent <= 1: return is_passable(cell)
	if not collision.inside(cell): return false
	if _static_for(extent)[cell.y * collision.width + cell.x] != 0: return false
	if not building_cells.is_empty():
		for c in footprint(cell, extent):
			if building_cells.has(c): return false
	return true

func enterable_extent(cell: Vector2i, extent: int, mtype: int = 0) -> bool:
	if extent <= 1 and mtype == 0: return enterable_static(cell)
	return cell.x > 0 and cell.y > 0 and cell.x < collision.width - 1 and cell.y < collision.height - 1 and passable_extent(cell, extent, mtype)

## Unit-aware test of 0x42cf00 for `extent`: the counter low nibbles of the anchor, i.e. any other unit on a footprint cell.
func occupant_extent(cell: Vector2i, extent: int, mover = null):
	if extent <= 1: return occupant(cell, mover)
	for c in footprint(cell, extent):
		var u = occupant(c, mover)
		if u != null: return u
	return null

## Region owner token of a cell for the extent-2 layer: map building object index + 1, a stamped building's token, 0 none.
func _owner_token(cell: Vector2i, rtype: int = 0) -> int:
	var owner := building_owner(cell, rtype)
	if owner < 0: return 0
	return owner if owner >= DYNAMIC_BUILDING_BASE else owner + 1

## 0x509f30 / 0x50a370 / 0x50a5c0 for one extent layer. The original builds layers for extents 1 and 2 only (the loop
## counter stops after the second layer, Read; extent-3 routes fail under emulation). A seed passing 0x42cda0 opens a
## region; when it fails 0x42cc10 the region is a building region owned by the seed's occupant (+0x14) and grows only into
## cells that fail 0x42cc10, pass 0x42cda0 and have the same non-zero occupant; ordinary regions grow into cells passing
## 0x42cc10, both within the 8x8 sector.
func _build_layer(extent: int) -> Dictionary:
	var width: int = collision.width
	var height: int = collision.height
	_lb_region = PackedInt32Array()
	_lb_region.resize(width * height)
	_lb_region.fill(-1)
	var list_of := {}
	var nodes: Array = []
	for sx in range(((width - 1) >> 3) + 1):
		for sy in range(((height - 1) >> 3) + 1):
			var list: Array = []
			list_of[Vector2i(sx, sy)] = list
			_flood_layer_sector(extent, sx, sy, list, nodes)
	var region_of_e := _lb_region
	_lb_region = PackedInt32Array()
	for x in range(1, width - 1):
		for y in range(1, height - 1):
			var own: int = region_of_e[y * width + x]
			if own < 0: continue
			for nx in range(x - 1, x + 2):
				for ny in range(y - 1, y + 2):
					var other: int = region_of_e[ny * width + nx]
					if other >= 0 and other != own and not nodes[own].links.has(other):
						nodes[own].links.append(other)
	return {"extent": extent, "region_of": region_of_e, "regions": nodes, "sector_regions": list_of}

## One 8 x 8 sector of _build_layer: seeds in y-outer / x-inner order, regions appended to `nodes` and `list`, cells written
## to _lb_region (the sector's cells must be -1 there).
func _flood_layer_sector(extent: int, sx: int, sy: int, list: Array, nodes: Array):
	var width: int = collision.width
	var height: int = collision.height
	var sector := Vector2i(sx, sy)
	for y in range(maxi(1, sy * 8), mini(sy * 8 + 8, height - 1)):
		for x in range(maxi(1, sx * 8), mini(sx * 8 + 8, width - 1)):
			var seed := Vector2i(x, y)
			if _lb_region[y * width + x] >= 0: continue
			var material := material_of(seed)
			var cls: int = MATERIAL_CLASS[material] if material < MATERIAL_CLASS.size() else 2
			if cls >= 2: continue
			var rtype := 0 if cls == 0 else 2
			if not sector_passable(seed, extent, rtype): continue
			var building := not passable_extent(seed, extent, rtype)
			var owner := _owner_token(seed, rtype) if building else 0
			var index := nodes.size()
			nodes.append({"sector": sector, "id": list.size(), "rep": Vector2i(sx * 8 + 4, sy * 8 + 4),
				"building": building, "material": BUILDING_REGION if building else material,
				"links": PackedInt32Array(), "dist": -1, "parent": -1})
			list.append(index)
			_lb_region[y * width + x] = index
			if building and owner == 0: continue
			var stack: Array[Vector2i] = [seed]
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				for nx in range(c.x - 1, c.x + 2):
					for ny in range(c.y - 1, c.y + 2):
						if nx >> 3 != sx or ny >> 3 != sy or nx <= 0 or ny <= 0 or nx >= width - 1 or ny >= height - 1: continue
						if _lb_region[ny * width + nx] >= 0: continue
						var n := Vector2i(nx, ny)
						if building:
							if passable_extent(n, extent, rtype) or not sector_passable(n, extent, rtype) or _owner_token(n, rtype) != owner: continue
						elif not passable_extent(n, extent, rtype):
							continue
						_lb_region[ny * width + nx] = index
						stack.append(n)

func layer(extent: int) -> Dictionary:
	if not _layers.has(extent):
		var t0 := Time.get_ticks_usec()
		if _stale_layers.has(extent) and _layer_cells.has(extent): _layers[extent] = _rebuild_layer(extent, _stale_layers[extent], _layer_cells[extent])
		else: _layers[extent] = _build_layer(extent)
		_stale_layers.erase(extent)
		_layer_cells[extent] = building_cells.duplicate()
		layer_builds += 1
		layer_build_us += Time.get_ticks_usec() - t0
	return _layers[extent]

# Performance (P-3): a building stamp or removal used to drop the extent-2 layer, and the next large unit's route built it
# again over the whole map (200-550 ms on Forest Lakes). The dropped layer is now kept with the building cells it was built
# from; the next layer() floods again only the sectors whose cells can have changed and renumbers the rest, as
# _rebuild_sectors does. The result equals _build_layer (tests/test_sector_rebuild.gd compares them after every change).
# Between full builds only building_cells changes what the layer reads (_build_sectors drops these as it drops _layers).
var _stale_layers: Dictionary = {}       # extent -> the layer dropped by the last _rebuild_sectors
var _layer_cells: Dictionary = {}        # extent -> building_cells as they were when the layer was built
var _lb_region := PackedInt32Array()     # the cell map of the layer being built (a member: a packed argument copies on write)
var layer_builds := 0                    # profiling: layer() builds and their microseconds
var layer_build_us := 0

func _retire_layers():
	for extent in _layers: _stale_layers[extent] = _layers[extent]
	_layers.clear()

## _build_layer for `extent`, from `old`: the layer built while building_cells was `before`.
func _rebuild_layer(extent: int, old: Dictionary, before: Dictionary) -> Dictionary:
	var width: int = collision.width
	var height: int = collision.height
	var sw := ((width - 1) >> 3) + 1
	var sh := ((height - 1) >> 3) + 1
	# A cell's building entry decides 0x42cc10 for the anchors whose footprint holds it (x from c.x - lo to c.x + hi, y from
	# c.y to c.y + extent - 1; the cell itself is one of them) and the owner token of the cell itself.
	var hi := (extent - 1) >> 1
	var lo := extent - 1 - hi
	var changed: Array = []
	for c in building_cells:
		if not before.has(c) or before[c] != building_cells[c]: changed.append(c)
	for c in before:
		if not building_cells.has(c): changed.append(c)
	var dirty := PackedByteArray()
	dirty.resize(sw * sh)
	for c in changed:
		for ax in range(maxi(0, c.x - lo), mini(width, c.x + hi + 1)):
			for ay in range(maxi(0, c.y), mini(height, c.y + extent)): dirty[(ax >> 3) * sh + (ay >> 3)] = 1
	var relink := PackedByteArray()                       # the changed sectors and their eight neighbours
	relink.resize(sw * sh)
	for sx in sw:
		for sy in sh:
			if dirty[sx * sh + sy] == 0: continue
			for ax in range(maxi(0, sx - 1), mini(sw, sx + 2)):
				for ay in range(maxi(0, sy - 1), mini(sh, sy + 2)): relink[ax * sh + ay] = 1
	var old_regions: Array = old.regions
	var old_sectors: Dictionary = old.sector_regions
	var remap := PackedInt32Array()
	remap.resize(old_regions.size())
	remap.fill(-1)
	var nodes: Array = []
	var list_of := {}
	_lb_region = old.region_of
	for sx in sw:
		for sy in sh:
			var sector := Vector2i(sx, sy)
			var list: Array = []
			list_of[sector] = list
			var x0 := maxi(1, sx * 8)
			var x1 := mini(sx * 8 + 8, width - 1)
			var y0 := maxi(1, sy * 8)
			var y1 := mini(sy * 8 + 8, height - 1)
			if dirty[sx * sh + sy] == 0:
				for old_index in old_sectors.get(sector, []):
					remap[old_index] = nodes.size()
					list.append(nodes.size())
					nodes.append(old_regions[old_index])
				for y in range(y0, y1):
					for x in range(x0, x1):
						var v: int = _lb_region[y * width + x]
						if v >= 0: _lb_region[y * width + x] = remap[v]
				continue
			for y in range(y0, y1):
				for x in range(x0, x1): _lb_region[y * width + x] = -1
			_flood_layer_sector(extent, sx, sy, list, nodes)
	var region_of_e := _lb_region
	_lb_region = PackedInt32Array()
	for node in nodes:
		node.dist = -1
		node.parent = -1
		var at: Vector2i = node.sector
		if relink[at.x * sh + at.y] != 0:
			node.links = PackedInt32Array()
			continue
		var mapped := PackedInt32Array()
		for other in node.links: mapped.append(remap[other])
		node.links = mapped
	# The full build's link scan (x outer, y inner) over the relinked sectors only, as in _rebuild_sectors.
	for sx in sw:
		for sy in sh:
			if relink[sx * sh + sy] == 0: continue
			for x in range(maxi(1, sx * 8), mini(sx * 8 + 8, width - 1)):
				for y in range(maxi(1, sy * 8), mini(sy * 8 + 8, height - 1)):
					var own: int = region_of_e[y * width + x]
					if own < 0: continue
					for nx in range(x - 1, x + 2):
						for ny in range(y - 1, y + 2):
							var other: int = region_of_e[ny * width + nx]
							if other >= 0 and other != own and not nodes[own].links.has(other):
								nodes[own].links.append(other)
	return {"extent": extent, "region_of": region_of_e, "regions": nodes, "sector_regions": list_of}

func _layer_region(l: Dictionary, cell: Vector2i) -> int:
	return l.region_of[cell.y * collision.width + cell.x] if collision.inside(cell) else -1

func _layer_flood(l: Dictionary, start_region: int, mtype: int = 0):
	_flood(l.regions, start_region, mtype)

func _layer_goal_sector(l: Dictionary, goal: Vector2i) -> Dictionary:
	var nodes: Array = l.regions
	var own := _layer_region(l, goal)
	if own >= 0 and nodes[own].dist >= 0:
		return {"sector": nodes[own].sector, "id": nodes[own].id}
	var s := Vector2i(goal.x >> 3, goal.y >> 3)
	var best := Vector2i(-1, -1)
	var best_id := -1
	var after := -1
	var direction := 0
	var run := 1
	var steps := 0
	var visited := 0
	while visited < 500:
		if after >= 0:
			after += 1
			if after == 10: break
		if s.x >= 0 and s.y >= 0 and s.x < collision.width >> 3 and s.y < collision.height >> 3:
			visited += 1
			for index in l.sector_regions.get(s, []):
				var node: Dictionary = nodes[index]
				if node.dist < 0: continue
				if after == -1:
					after = 0
					best = s
					best_id = node.id
				elif best != s:
					var candidate := _spread(absi(node.rep.x - goal.x), absi(node.rep.y - goal.y))
					var current := _spread(absi(best.x * 8 - goal.x + 4), absi(best.y * 8 - goal.y + 4))
					if candidate < current:
						best = s
						best_id = node.id
		match direction:
			0: s.x += 1
			1: s.y += 1
			2: s.x -= 1
			3: s.y -= 1
		steps += 1
		if steps == run:
			direction = (direction + 1) % 4
			steps = 0
			if direction == 0 or direction == 2: run += 1
	return {"sector": best, "id": best_id}

## 0x430b80 with the extent: eligible cells (0x42cad0: no material 9, terrain gate 0x42c990 and the object filter 0x42d390
## over the footprint) are the cells passing the extent's cell check.
func _layer_sector_cell(l: Dictionary, target: Vector2i, sector: Vector2i, region_id: int, mtype: int = 0) -> Vector2i:
	var nodes: Array = l.regions
	var node := -1
	for index in l.sector_regions.get(sector, []):
		if nodes[index].id == region_id:
			node = index
			break
	if node < 0: return Vector2i(-1, -1)
	var marked := {node: true}
	for other in nodes[node].links: marked[other] = true
	var x0 := maxi(1, sector.x * 8 - 5)
	var y0 := maxi(1, sector.y * 8 - 5)
	var best := Vector2i(-1, -1)
	for x in range(x0, mini(x0 + 18, collision.width - 2) + 1):
		for y in range(y0, mini(y0 + 18, collision.height - 2) + 1):
			var cell := Vector2i(x, y)
			if not marked.has(_layer_region(l, cell)) or not enterable_extent(cell, int(l.extent), mtype): continue
			if best.x < 0 or chebyshev(target, cell) < chebyshev(target, best):
				best = cell
	return best

## route_cells for a large unit: the same planner over the extent's own sector layer and searches with the extent.
func _route_cells_extent(start: Vector2i, goal: Vector2i, extent: int, mtype: int = 0) -> Dictionary:
	if extent >= 3:
		return {"ok": false, "reason": "No sector layer for extent 3 (the original builds extents 1 and 2 only)"}
	var l := layer(extent)
	var nodes: Array = l.regions
	var start_region := _layer_region(l, start)
	if start_region < 0:
		return {"ok": false, "reason": "Start is not in a region"}
	_layer_flood(l, start_region, mtype)
	var found := _layer_goal_sector(l, goal)
	if found.sector.x < 0:
		return {"ok": false, "reason": "No reachable sector near the destination"}
	var target := _layer_sector_cell(l, goal, found.sector, found.id, mtype)
	if target.x < 0:
		return {"ok": false, "reason": "No eligible destination cell"}
	if target == start:
		return {"ok": true, "segments": [], "target": target}
	var chain: Array[int] = []
	var node := _layer_region(l, target)
	while node >= 0:
		chain.append(node)
		node = nodes[node].parent
	var remaining := chain.size()
	var here := start
	var segments: Array = []
	while true:
		var k := remaining - CHAIN_STEP
		var waypoint := target
		if k >= 1:
			var entry: Dictionary = nodes[chain[k]]
			waypoint = _layer_sector_cell(l, entry.rep, entry.sector, entry.id, mtype)
		if waypoint.x < 0:
			return {"ok": false, "reason": "No eligible segment cell", "segments": segments}
		var result := search(here, waypoint, SEGMENT_LIMIT, false, null, extent, mtype)
		if not result.ok:
			return {"ok": false, "reason": result.reason, "segments": segments}
		remaining = k if k >= 1 else 0
		segments.append(result.cells)
		if remaining == 0 or result.cells.is_empty():
			break
		here = result.cells[-1]
	return {"ok": true, "segments": segments, "target": target}

static func chebyshev(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))

# Mode 0 (unit_aware false) ignores units like 0x42cc10; mode 1 treats occupied cells as
# blocked like 0x42cf00. Unit cost per step, f = g + 2*Chebyshev, LIFO buckets, a cell is
# closed when first discovered, and the goal cell is always accepted.
func search(start: Vector2i, goal: Vector2i, limit: int = 0, unit_aware: bool = false, mover = null, extent: int = 1, mtype: int = 0) -> Dictionary:
	if start == goal:
		return {"ok": true, "cells": []}
	_generation += 1
	var width: int = collision.width
	var cap := CAP_UNIT_AWARE if unit_aware else CAP_STATIC
	var start_index := start.y * width + start.x
	_stamp[start_index] = _generation
	_g[start_index] = 0
	_parent[start_index] = -1
	var bucket := 2 * chebyshev(start, goal)
	var buckets := {bucket: [start]}
	var highest := bucket
	while limit == 0 or bucket <= limit:
		var entries: Array = buckets.get(bucket, [])
		for k in range(entries.size() - 1, -1, -1):
			var cell: Vector2i = entries[k]
			if cell == goal:
				return {"ok": true, "cells": _trace(cell, start)}
			var g: int = _g[cell.y * width + cell.x]
			for step in SEARCH_ORDER:
				var next: Vector2i = cell + step
				if next.x <= 0 or next.y <= 0 or next.x >= width - 1 or next.y >= collision.height - 1:
					continue
				var index: int = next.y * width + next.x
				if _stamp[index] == _generation:
					continue
				_stamp[index] = _generation
				if mtype == 1:   # G-3: the air layer's counters hold flyers only (0x42cf00 type 1; Emulated, flyer_detour_fixtures)
					if next != goal and (not _typed_ok(next, extent, mtype, true) or (unit_aware and air_occupant(next, mover) != null)):
						continue
				elif mtype != 0:
					if next != goal and (not _typed_ok(next, extent, mtype, true) or (unit_aware and occupant_extent(next, extent, mover) != null)):
						continue
				elif extent <= 1:
					if next != goal and (not is_passable(next) or (unit_aware and occupant(next, mover) != null)):
						continue
				elif next != goal and (not passable_extent(next, extent) or (unit_aware and occupant_extent(next, extent, mover) != null)):
					continue
				var f := g + 1 + 2 * chebyshev(next, goal)
				_g[index] = g + 1
				_parent[index] = cell.y * width + cell.x
				if not buckets.has(f): buckets[f] = []
				buckets[f].append(next)
				highest = maxi(highest, f)
		buckets.erase(bucket)
		bucket -= 1
		while not buckets.has(bucket):
			bucket += 1
			if bucket > highest:
				return {"ok": false, "cells": [], "reason": "No path"}
		if bucket > cap:
			return {"ok": false, "cells": [], "reason": "Search limit reached"}
	return {"ok": false, "cells": [], "reason": "Search limit reached"}

func _trace(cell: Vector2i, start: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var width: int = collision.width
	var index := cell.y * width + cell.x
	while index != start.y * width + start.x:
		result.push_front(Vector2i(index % width, index / width))
		index = _parent[index]
	return result

# 0x42f650 + 0x42ff30 for a ground move order without a target object. The goal is replaced by
# the 0x430b80 cell (blocked/unreachable goals land on the nearest eligible reached cell). The
# region chain runs goal -> start; each segment searches (f <= 150) to the cell of chain entry
# count-4, count-8, ... nearest that region's sector centre, and finally to the goal. Segments are
# computed up front: with static blockers this equals the original's lazy per-segment requests.
func route_cells(start: Vector2i, goal: Vector2i, extent: int = 1, mtype: int = 0) -> Dictionary:
	var width: int = collision.width
	var height: int = collision.height
	if start.x <= 0 or start.y <= 0 or start.x >= width - 1 or start.y >= height - 1 or goal.x <= 0 or goal.y <= 0 or goal.x >= width - 1 or goal.y >= height - 1:
		return {"ok": false, "reason": "Start or destination outside the map interior"}
	if start == goal:
		return {"ok": true, "segments": [], "target": goal}
	if improved: return route_cells_improved(start, goal, extent, mtype)
	if extent > 1: return _route_cells_extent(start, goal, extent, mtype)
	var start_region := region(start)
	if start_region < 0:
		return {"ok": false, "reason": "Start is not in a region"}
	flood_sectors(start_region, mtype)
	var found := goal_sector(goal)
	if found.sector.x < 0:
		return {"ok": false, "reason": "No reachable sector near the destination"}
	var target := sector_cell(goal, found.sector, found.id, mtype)
	if target.x < 0:
		return {"ok": false, "reason": "No eligible destination cell"}
	if target == start:
		return {"ok": true, "segments": [], "target": target}
	var chain: Array[int] = []
	var node := region(target)
	while node >= 0:
		chain.append(node)
		node = regions[node].parent
	var remaining := chain.size()
	var here := start
	var segments: Array = []
	while true:
		var k := remaining - CHAIN_STEP
		var waypoint := target
		if k >= 1:
			var entry: Dictionary = regions[chain[k]]
			waypoint = sector_cell(entry.rep, entry.sector, entry.id, mtype)
		if waypoint.x < 0:
			return {"ok": false, "reason": "No eligible segment cell", "segments": segments}
		var result := search(here, waypoint, SEGMENT_LIMIT, false, null, 1, mtype)
		if not result.ok:
			return {"ok": false, "reason": result.reason, "segments": segments}
		remaining = k if k >= 1 else 0
		segments.append(result.cells)
		if remaining == 0 or result.cells.is_empty():
			break
		here = result.cells[-1]
	return {"ok": true, "segments": segments, "target": target}

# Units travel cell centre to cell centre; target is the (possibly retargeted) goal cell centre.
func plan(start: Vector2, requested: Vector2, extent: int = 1, mtype: int = 0) -> Dictionary:
	var source_cell: Vector2i = collision.world_cell(start)
	var goal_cell: Vector2i = collision.world_cell(requested)
	var route := route_cells(source_cell, goal_cell, extent, mtype)
	if not route.ok:
		return {"ok": false, "reason": route.reason}
	var cells: Array[Vector2i] = []
	for segment in route.segments: cells.append_array(segment)
	var path := PackedVector2Array([start])
	var length_px := 0.0
	for cell in cells:
		length_px += path[-1].distance_to(center(cell))
		path.append(center(cell))
	return {"ok": true, "cells": cells, "segments": route.segments, "path": path, "length_px": length_px,
		"steps": cells.size(), "requested": requested, "target": center(route.target),
		"snapped": route.target != goal_cell}

# 0x40c770: new facing from centroid displacement, or -1 when Chebyshev < 5 or unchanged.
# 0 north, 1 north-west, 2 west, 3 south-west, 4 south, 5 south-east, 6 east, 7 north-east.
static func move_direction(delta: Vector2i, current: int) -> int:
	var ax := absi(delta.x)
	var ay := absi(delta.y)
	if maxi(ax, ay) < 5: return -1
	var half := ay >> 1
	var d: int
	if delta.x < 1:
		if delta.y < 1: d = 0 if ax < half else (2 if 2 * ay < ax else 1)
		else: d = 4 if ax < half else (3 if ax <= 2 * ay else 2)
	elif delta.y < 1:
		d = 0 if ax < half else (7 if ax <= 2 * ay else 6)
	else:
		d = 4 if ax < half else (6 if 2 * ay < ax else 5)
	return -1 if d == current else d

# 0x530f80 rotation of a south-facing table slot to the group's facing.
static func rotate_slot(offset: Vector2i, direction: int) -> Vector2i:
	var hx := offset.x >> 1
	var hy := offset.y >> 1
	match direction:
		4: return offset
		6: return Vector2i(offset.y, -offset.x)
		0: return Vector2i(-offset.x, -offset.y)
		2: return Vector2i(-offset.y, offset.x)
		5: return Vector2i(hy - hx, hy + hx)
		3: return Vector2i(-hy - hx, hy - hx)
		1: return Vector2i(hx - hy, -hy - hx)
		7: return Vector2i(hy + hx, hx - hy)
	return Vector2i.ZERO

# 0x530f80: slots go in table order to the unassigned unit with the highest rank_a (unit +0xa2),
# ties to the lowest rank_b (+0x92), then list order. Returns one goal cell per entry.
static func formation_slots(target: Vector2i, entries: Array, direction: int) -> Array[Vector2i]:
	var count := entries.size()
	var out: Array[Vector2i] = []
	out.resize(count)
	var taken := []
	taken.resize(count)
	taken.fill(false)
	var row: Array = FORMATION_1[count - 1]
	for slot in range(count):
		var pick := -1
		var best_a := -1
		var best_b := 1000
		for i in range(count):
			if taken[i]: continue
			var a: int = entries[i].get("rank_a", 0)
			var b: int = entries[i].get("rank_b", 0)
			if best_a < a or (a == best_a and b < best_b):
				pick = i
				best_a = a
				best_b = b
		taken[pick] = true
		out[pick] = target + rotate_slot(Vector2i(row[2 * slot], row[2 * slot + 1]), direction)
	return out

# 0x530870: one right-click on ground. entries (selection-list order): id, cell, speed, and
# optional rank_a/rank_b. The centroid of unit cells (C integer division) and the clicked cell
# pick a new facing (kept when the move is short); each unit gets its formation slot as its own
# goal, unchanged even when blocked or occupied (the route planner retargets). With slowest set the
# shared order speed is the minimum effective speed (start 50), else each unit keeps its own.
func group_orders(entries: Array, clicked: Vector2i, facing: int, slowest: bool) -> Dictionary:
	if entries.is_empty() or entries.size() > FORMATION_1.size():
		return {"ok": false, "orders": [], "facing": facing}
	var sum := Vector2i.ZERO
	var speed := 50
	for entry in entries:
		sum += entry.cell
		speed = mini(speed, int(entry.speed))
	var centroid := Vector2i(sum.x / entries.size(), sum.y / entries.size())
	var turned := move_direction(clicked - centroid, facing)
	if turned >= 0: facing = turned
	var cells := formation_slots(clicked, entries, facing)
	var orders: Array = []
	for i in range(entries.size()):
		orders.append({"id": entries[i].id, "cell": cells[i], "speed": speed if slowest and speed != 50 else int(entries[i].speed)})
	return {"ok": true, "orders": orders, "facing": facing, "centroid": centroid}

# ================================================================================================
# DELIBERATE MODERN CHANGES (simulation/modern_rules.gd "Movement", COMPLAINTS_AND_FIXES.md F1, F2, F5, F6). With
# `improved` false (the default) nothing below is used and every route, detour and group order is the original's.
# * F5: one A* search with octile costs (straight 2, diagonal 3), no squeezing diagonally between two blocked cells and
#   ties broken toward the goal, instead of the doubled-heuristic search in 150-limited segments (zigzags, failed orders).
#   The sector layer still retargets blocked and unreachable goals exactly as before.
# * F2: detours treat moving units as expensive cells instead of walls (units pick a parallel lane in a crowd).
# * F1: group marches (march_orders): one shared route; every member follows it at its slot offset, collapsing to the
#   route line where the offset cell is blocked (a column through a pass), and the members wait for each other.
var improved := false
var marches: Dictionary = {}           # march id -> {unit id: progress index along the shared route (negative while joining)}
const ASTAR_EXPANSIONS := 40000
const DETOUR_EXPANSIONS := 700
const LINK_EXPANSIONS := 300
const STRAIGHT_COST := 2
const DIAGONAL_COST := 3
const MOVING_UNIT_COST := 4
const MARCH_HOLD := 8               # a member this far ahead of the slowest one stops until it catches up
const MARCH_RADIUS := 6                # largest distance from the leader a member keeps on the way
const MARCH_BLEND := 8                 # route cells over which a member moves from its marching place to its slot
const JOIN_WINDOW := 16              # route cells searched for the place where a member joins the march
const MARCH_DONE := 1 << 20
var _closed := PackedInt32Array()

static func octile(a: Vector2i, b: Vector2i) -> int:
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
	return STRAIGHT_COST * maxi(dx, dy) + (DIAGONAL_COST - STRAIGHT_COST) * mini(dx, dy)

func _static_ok(cell: Vector2i, extent: int, mtype: int = 0) -> bool:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= collision.width - 1 or cell.y >= collision.height - 1: return false
	if mtype != 0: return _typed_ok(cell, extent, mtype, true)
	if extent <= 1: return _pass1[cell.y * collision.width + cell.x] == 1 and not building_cells.has(cell)
	return passable_extent(cell, extent)

## collision.is_passable per cell, cached for the A* search (buildings are checked separately, they change in a match).
var _pass1 := PackedByteArray()

func _ensure_pass1():
	var count: int = collision.width * collision.height
	if _pass1.size() == count: return
	_pass1.resize(count)
	for y in collision.height:
		for x in collision.width:
			_pass1[y * collision.width + x] = 1 if collision.is_passable(Vector2i(x, y)) else 0

## A* from start to goal (the goal is accepted even when blocked, like the original). unit_aware: idle units block,
## moving units cost MOVING_UNIT_COST more. Returns {"ok", "cells"} with the start excluded.
func astar(start: Vector2i, goal: Vector2i, unit_aware: bool = false, mover = null, extent: int = 1, max_expand: int = ASTAR_EXPANSIONS, mtype: int = 0) -> Dictionary:
	if start == goal: return {"ok": true, "cells": []}
	var width: int = collision.width
	_ensure_pass1()
	if _closed.size() != _stamp.size():
		_closed.resize(_stamp.size())
		_closed.fill(0)
	_generation += 1
	var start_index := start.y * width + start.x
	_stamp[start_index] = _generation
	_g[start_index] = 0
	_parent[start_index] = -1
	var heap := PackedInt64Array()
	_heap_push(heap, _key(octile(start, goal), 0, start_index))
	var expanded := 0
	while not heap.is_empty():
		var key := _heap_pop(heap)
		var index := int(key & 0xFFFFF)
		if _closed[index] == _generation: continue
		_closed[index] = _generation
		var cell := Vector2i(index % width, index / width)
		if cell == goal: return {"ok": true, "cells": _trace(cell, start)}
		expanded += 1
		if expanded > max_expand: return {"ok": false, "cells": [], "reason": "Search limit reached"}
		var g: int = _g[index]
		for step in SEARCH_ORDER:
			var next: Vector2i = cell + step
			if next.x <= 0 or next.y <= 0 or next.x >= width - 1 or next.y >= collision.height - 1: continue
			var next_index: int = next.y * width + next.x
			if _closed[next_index] == _generation: continue
			var cost := STRAIGHT_COST
			if step.x != 0 and step.y != 0:
				cost = DIAGONAL_COST
				# no squeezing between two blocked orthogonal cells (the original allows it)
				if not _static_ok(Vector2i(next.x, cell.y), extent, mtype) or not _static_ok(Vector2i(cell.x, next.y), extent, mtype): continue
			if next != goal:
				if mtype != 0:
					if not _typed_ok(next, extent, mtype, true): continue
				elif extent <= 1:
					if _pass1[next_index] == 0 or building_cells.has(next): continue
				elif not passable_extent(next, extent): continue
				if unit_aware:
					var other = occupant_extent(next, extent, mover)
					if other != null:
						if not (other.has_method("is_moving") and other.is_moving()): continue
						cost += MOVING_UNIT_COST
			var ng := g + cost
			if _stamp[next_index] == _generation and _g[next_index] <= ng: continue
			_stamp[next_index] = _generation
			_g[next_index] = ng
			_parent[next_index] = index
			_heap_push(heap, _key(ng + octile(next, goal), ng, next_index))
	return {"ok": false, "cells": [], "reason": "No path"}

static func _key(f: int, g: int, index: int) -> int:
	return (f << 40) | ((0xFFFFF - mini(g, 0xFFFFF)) << 20) | index

static func _heap_push(heap: PackedInt64Array, value: int):
	heap.append(value)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if heap[p] <= heap[i]: break
		var t := heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p

static func _heap_pop(heap: PackedInt64Array) -> int:
	var top := heap[0]
	var last := heap[heap.size() - 1]
	heap.resize(heap.size() - 1)
	if heap.is_empty(): return top
	heap[0] = last
	var i := 0
	var n := heap.size()
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < n and heap[l] < heap[m]: m = l
		if r < n and heap[r] < heap[m]: m = r
		if m == i: break
		var t := heap[m]
		heap[m] = heap[i]
		heap[i] = t
		i = m
	return top

## The goal cell the original planner would walk to (blocked or unreachable goals retargeted by the sector layer).
func route_target(start: Vector2i, goal: Vector2i, extent: int = 1, mtype: int = 0) -> Dictionary:
	if extent >= 3: return {"ok": false, "reason": "No sector layer for extent 3 (the original builds extents 1 and 2 only)"}
	if extent == 2:
		var l := layer(extent)
		var start_layer_region := _layer_region(l, start)
		if start_layer_region < 0: return {"ok": false, "reason": "Start is not in a region"}
		_layer_flood(l, start_layer_region, mtype)
		var layer_found := _layer_goal_sector(l, goal)
		if layer_found.sector.x < 0: return {"ok": false, "reason": "No reachable sector near the destination"}
		var layer_target := _layer_sector_cell(l, goal, layer_found.sector, layer_found.id, mtype)
		if layer_target.x < 0: return {"ok": false, "reason": "No eligible destination cell"}
		return {"ok": true, "target": layer_target}
	var start_region := region(start)
	if start_region < 0: return {"ok": false, "reason": "Start is not in a region"}
	flood_sectors(start_region, mtype)
	var found := goal_sector(goal)
	if found.sector.x < 0: return {"ok": false, "reason": "No reachable sector near the destination"}
	var target := sector_cell(goal, found.sector, found.id, mtype)
	if target.x < 0: return {"ok": false, "reason": "No eligible destination cell"}
	return {"ok": true, "target": target}

## F5/F6: one A* segment to the retargeted goal; when even that fails, the original segmented planner is tried before
## the order is given up (the original drops the order when one 150-limited segment fails).
func route_cells_improved(start: Vector2i, goal: Vector2i, extent: int = 1, mtype: int = 0) -> Dictionary:
	var t := route_target(start, goal, extent, mtype)
	if not t.ok: return t
	var target: Vector2i = t.target
	if target == start: return {"ok": true, "segments": [], "target": target}
	var found := astar(start, target, false, null, extent, ASTAR_EXPANSIONS, mtype)
	if found.ok: return {"ok": true, "segments": [found.cells], "target": target}
	improved = false
	var fallback := route_cells(start, goal, extent, mtype)
	improved = true
	return fallback

## F2: a detour around held cells (units standing still block, moving ones only cost more).
func detour_search(start: Vector2i, goal: Vector2i, mover, extent: int = 1, mtype: int = 0) -> Dictionary:
	return astar(start, goal, true, mover, extent, DETOUR_EXPANSIONS, mtype)

## F1: group march. Same facing, slots and speed as group_orders (0x530870); with two or more ground units each order
## also carries "cells" (its whole walk) and "marks" (the shared-route index each cell belongs to; joining cells count back from the join point)
## and the march id. On the way each member keeps its place relative to the leader and blends into its slot over the
## last MARCH_BLEND cells; unit_agent.gd holds a member that leads the slower quarter by more than MARCH_HOLD cells.
func march_orders(entries: Array, clicked: Vector2i, facing: int, slowest: bool, march_id: int) -> Dictionary:
	var group := group_orders(entries, clicked, facing, slowest)
	if not improved or not group.ok or entries.size() < 2: return group
	_ensure_pass1()
	var leader := 0
	var best := 1 << 30
	for i in entries.size():
		if entries[i].get("flying", false) or int(entries[i].get("mtype", 0)) != 0: continue
		var d := chebyshev(entries[i].cell, group.centroid)
		if d < best:
			best = d
			leader = i
	var extent := 1
	for entry in entries: extent = maxi(extent, int(entry.get("extent", 1)))
	var lead_cell: Vector2i = entries[leader].cell
	var shared_route := route_cells_improved(lead_cell, clicked, extent)
	if not shared_route.ok: return group
	var shared: Array[Vector2i] = [lead_cell]
	for segment in shared_route.segments: shared.append_array(segment)
	var members := {}
	for i in entries.size():
		if entries[i].get("flying", false) or int(entries[i].get("mtype", 0)) != 0: continue   # water / amphibious units walk alone
		var order: Dictionary = group.orders[i]
		var unit_extent := int(entries[i].get("extent", 1))
		# On the way each member keeps its place relative to the leader (stragglers pulled in to MARCH_RADIUS), so nobody
		# crosses the group at the start; the formation slots are taken at the destination (the tail below).
		var offset: Vector2i = entries[i].cell - lead_cell
		var spread := maxi(absi(offset.x), absi(offset.y))
		if spread > MARCH_RADIUS: offset = Vector2i(offset.x * MARCH_RADIUS / spread, offset.y * MARCH_RADIUS / spread)
		var walk: Array[Vector2i] = []
		var marks := PackedInt32Array()
		var here: Vector2i = entries[i].cell
		var ok := true
		# Join the route where this unit's slot is nearest to it (within the first JOIN_WINDOW cells), so units already
		# near their place do not cross the group to reach the slot beside the leader's starting cell.
		var first := 0
		var nearest := 1 << 20
		for k in mini(shared.size(), JOIN_WINDOW):
			var d := chebyshev(here, _march_slot(shared[k], offset, unit_extent))
			if d <= nearest:
				nearest = d
				first = k
		# Over the last MARCH_BLEND route cells the place slides from the marching offset to the formation slot.
		var slot_offset: Vector2i = order.cell - shared[-1]
		var blend_from := shared.size() - 1 - MARCH_BLEND
		for k in range(first, shared.size()):
			var place := offset
			if k > blend_from:
				var t := mini(k - blend_from, MARCH_BLEND)
				place = offset + Vector2i((slot_offset.x - offset.x) * t / MARCH_BLEND, (slot_offset.y - offset.y) * t / MARCH_BLEND)
			var want := _march_slot(shared[k], place, unit_extent)
			if want == here: continue
			if chebyshev(want, here) == 1 and _static_ok(want, unit_extent) and _corner_ok(here, want, unit_extent):
				walk.append(want)
				marks.append(k)
			else:
				var link := astar(here, want, false, null, unit_extent, ASTAR_EXPANSIONS if k == first else LINK_EXPANSIONS)
				if not link.ok:
					if k == first:
						ok = false
						break
					continue
				# Joining cells count as that many route cells before the join point (negative progress is fine).
				for j in link.cells.size():
					walk.append(link.cells[j])
					marks.append(k - (link.cells.size() - 1 - j) if k == first else k)
			if not walk.is_empty(): here = walk[-1]
		if not ok: continue
		# The slot as the original would retarget it; a free slot in a region the leader's flood reached needs no new flood.
		var slot: Vector2i = order.cell
		var final_target := {"ok": true, "target": slot}
		if unit_extent > 1 or not enterable_static(slot) or region(slot) < 0 or int(regions[region(slot)].dist) < 0:
			final_target = route_target(here, slot, unit_extent)
		if final_target.ok and final_target.target != here:
			var tail := astar(here, final_target.target, false, null, unit_extent, LINK_EXPANSIONS * 4)
			if tail.ok:
				for c in tail.cells:
					walk.append(c)
					marks.append(shared.size() - 1)
		# Collapsing to the route line and back can revisit cells: cut every loop so the walk never repeats a cell or
		# returns to the start (unit_agent.gd steps only to neighbouring cells).
		var clean: Array[Vector2i] = []
		var clean_marks := PackedInt32Array()
		var at := {entries[i].cell: -1}
		for j in walk.size():
			var c: Vector2i = walk[j]
			if at.has(c):
				var keep: int = at[c] + 1
				for dropped in range(keep, clean.size()): at.erase(clean[dropped])
				clean.resize(keep)
				var top := marks[j]
				if keep > 0: top = maxi(top, clean_marks[keep - 1])
				clean_marks.resize(keep)
				if keep > 0: clean_marks[keep - 1] = top
				continue
			at[c] = clean.size()
			clean.append(c)
			clean_marks.append(marks[j])
		walk = clean
		marks = clean_marks
		order["cells"] = walk
		order["marks"] = marks
		order["march"] = march_id
		members[int(order.id)] = (marks[0] - 1) if not marks.is_empty() else MARCH_DONE
	if members.size() >= 2:
		marches[march_id] = members
		group["march"] = march_id
	else:
		for order in group.orders:
			order.erase("cells")
			order.erase("marks")
			order.erase("march")
	return group

## A member's place beside route cell `at`: its slot offset, shrunk toward the route line where it does not fit (a pass
## narrows the formation), or the route cell itself.
func _march_slot(at: Vector2i, offset: Vector2i, extent: int) -> Vector2i:
	for part in [3, 2, 1]:
		var c: Vector2i = at + Vector2i(offset.x * part / 3, offset.y * part / 3)
		if _static_ok(c, extent): return c          # the cached passability (enterable_extent is much slower)
	return at

func _corner_ok(a: Vector2i, b: Vector2i, extent: int) -> bool:
	if a.x == b.x or a.y == b.y: return true
	return _static_ok(Vector2i(b.x, a.y), extent) and _static_ok(Vector2i(a.x, b.y), extent)

func march_report(march_id: int, unit_id: int, progress: int):
	if marches.has(march_id) and marches[march_id].has(unit_id): marches[march_id][unit_id] = progress

func march_leave(march_id: int, unit_id: int):
	if not marches.has(march_id): return
	marches[march_id].erase(unit_id)
	if marches[march_id].size() < 2: marches.erase(march_id)

## The pace of the march: the progress of the slower quarter of the other members still marching (MARCH_DONE when
## none). One member stuck behind something does not stop the whole group.
func march_min(march_id: int, unit_id: int) -> int:
	var progress: Array = []
	for id in marches.get(march_id, {}):
		if id != unit_id: progress.append(int(marches[march_id][id]))
	if progress.is_empty(): return MARCH_DONE
	progress.sort()
	return progress[progress.size() / 4]

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: occupancy by unit id (in insertion order), the building stamps, the region graph and the caches as
## they are (a cache built before a map building fell keeps its old cells, so it is saved rather than rebuilt). The
## search buffers (_stamp, _parent, _g, _closed) only hold entries of the running search and are not saved.
const _SAVE_SKIP := ["collision", "occupants", "air_occupants", "_stamp", "_parent", "_g", "_closed",
	"_cells_by_building", "_cells_index_version", "_cells_index_size", "_memo_land", "_memo_water", "sector_builds", "sector_build_us",
	"_stale_layers", "_layer_cells", "_lb_region", "layer_builds", "layer_build_us"]

func save_state(_refs = null) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)
	s["occupants"] = occupants.keys().map(func(c): return [c, int(occupants[c].unit_id)])
	s["air_occupants"] = air_occupants.keys().map(func(c): return [c, int(air_occupants[c].unit_id)])
	return s

func load_state(state: Dictionary, refs):
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP)
	_cells_index_version = -1                         # P-1's index is rebuilt from the loaded building_cells
	_stale_layers.clear()                             # P-3: a loaded layer is used as saved; the next one is built in full
	_layer_cells.clear()
	occupants.clear()
	for pair in state.occupants: occupants[pair[0]] = refs.unit(int(pair[1]))
	air_occupants.clear()
	for pair in state.air_occupants: air_occupants[pair[0]] = refs.unit(int(pair[1]))
	_stamp.fill(0)
	_closed.fill(0)
