extends RefCounted
## Milestone AI-7 (AI_RESEARCH.md section 23): the computer player's building sites in a match.
## * 0x4f9480 (Emulated for its window order, .local probe under Unicorn, AI_RESEARCH.md 23): up to 225 windows of 50 x 50
##   cells; their centres are the start plus one of nine outer offsets (0, +-180) and one of 25 inner offsets (0, +-40,
##   +-80) in the order below; a centre must lie strictly inside the map (0 < c < size - 1); the window starts 25 cells up
##   and left of it (at least 0). The first window with a spot wins.
## * 0x435320 (Emulated by RM-5, simulation/random_map_place.gd `_search`, on generated maps): the spot of a (w + 5) x
##   (h + 5) block (towers + 3) of one terrain height, no material 3 / 5 / 6 / 7 / 9, a non-zero permission byte, cells
##   free for the builder (0x42c8e0 with the builder: Placement.blocked) and not reserved (cell +0x25), nearest to the hint
##   plus the window's centre (Chebyshev). Here on the match grid (collision raw bytes 0 / 1 / 2) with the reservations.
## * The reservation (Read, 0x4f9a10 / 0x4f9af0, decompile 164281-164369): a build task that found its site marks the
##   building's BUI +0x3e x +0x3f cells around it (from x - (w - 1) / 2, y - (h - 1) / 2) until the task ends, so two
##   builders never get overlapping sites. No route test: the original does not check that the builder can reach the
##   spot (0x4f9790 state 2 ends the task when the walk ends elsewhere; the next search may find the same spot).

const Placement = preload("res://simulation/placement.gd")
const WIDE_TOWERS := ["BWTC", "BWTD", "BWMO", "BWTU", "BWTB", "BWTR", "BWTO", "BWTP", "BWTM", "BWTK", "BWTW", "BWTF",
	"BWTA", "BWTH", "BWTG", "BWTE", "BWTL", "BWTV"]
const OUTER := [Vector2i(0, 0), Vector2i(-180, 0), Vector2i(180, 0), Vector2i(0, -180), Vector2i(0, 180), Vector2i(-180, -180),
	Vector2i(-180, 180), Vector2i(180, -180), Vector2i(180, 180)]
const INNER := [Vector2i(0, 0), Vector2i(-40, 0), Vector2i(40, 0), Vector2i(0, -40), Vector2i(0, 40), Vector2i(-40, -40),
	Vector2i(-40, 40), Vector2i(40, -40), Vector2i(40, 40), Vector2i(-80, 0), Vector2i(80, 0), Vector2i(0, -80), Vector2i(0, 80),
	Vector2i(80, -40), Vector2i(80, 40), Vector2i(-80, -40), Vector2i(-80, 40), Vector2i(40, -80), Vector2i(40, 80), Vector2i(-40, -80),
	Vector2i(-40, 80), Vector2i(-80, -80), Vector2i(-80, 80), Vector2i(80, -80), Vector2i(80, 80)]
const WINDOW := 50

## The footprint cells 0x4f9a10 reserves for a site.
static func reserved_cells(footprint: Array, site: Vector2i) -> Array:
	var w: int = int(footprint[0])
	var h: int = int(footprint[1])
	var out: Array = []
	for row in h:
		for col in w:
			out.append(Vector2i(site.x - ((w - 1) >> 1) + col, site.y - ((h - 1) >> 1) + row))
	return out

## 0x4f9480: the first spot over the windows around `start` (the hint is the start too, as 0x4f9790 passes it).
static func find(navigator, code: String, footprint: Array, start: Vector2i, builder, reserved: Dictionary, units_block := true) -> Vector2i:
	var collision = navigator.collision
	for outer in OUTER:
		for inner in INNER:
			var c: Vector2i = start + outer + inner
			if c.x <= 0 or c.x >= collision.width - 1 or c.y <= 0 or c.y >= collision.height - 1: continue
			var spot := search(navigator, code, footprint, maxi(0, c.x - 25), maxi(0, c.y - 25), WINDOW, WINDOW, start, builder, reserved, units_block)
			if spot.x != -1 and spot.y != -1: return spot
	return Vector2i(-1, -1)

## 0x435320 on the match grid (random_map_place.gd `_search` with the match's occupancy and reservations).
## `units_block` = false (diagnostics only, AI-9): standing units do not block.
## Performance (P-4): a map's three raw bytes per cell (level, material, permission) never change in a match, so they
## are read once per cell array into packed arrays instead of through cell_data() for every cell of every window (up
## to 225 windows of 2,500 cells a search; a search that finds no room took 60-100 ms).
static var _static_cells = null           # the collision.data.cells array the bytes were read from
static var _static_levels := PackedByteArray()
static var _static_materials := PackedByteArray()
static var _static_permissions := PackedByteArray()

static func _read_static(collision):
	var cells: Array = collision.data.cells
	if _static_cells != null and is_same(_static_cells, cells) and _static_levels.size() == cells.size(): return
	_static_cells = cells
	_static_levels.resize(cells.size())
	_static_materials.resize(cells.size())
	_static_permissions.resize(cells.size())
	for i in cells.size():
		var raw = cells[i].raw
		_static_levels[i] = int(raw[0])
		_static_materials[i] = int(raw[1])
		_static_permissions[i] = 1 if int(raw[2]) != 0 else 0

static func search(navigator, code: String, footprint: Array, x0: int, y0: int, w: int, h: int, hint: Vector2i, builder, reserved: Dictionary, units_block := true) -> Vector2i:
	var collision = navigator.collision
	var width: int = collision.width
	var height: int = collision.height
	_read_static(collision)
	var cells: Array = collision.data.cells
	var building_cells: Dictionary = navigator.building_cells
	var occupants: Dictionary = navigator.occupants
	var margin := 3 if code in WIDE_TOWERS else 5
	var rw: int = int(footprint[0]) + margin
	var rh: int = int(footprint[1]) + margin
	var levels := PackedByteArray()
	var flags := PackedByteArray()
	levels.resize(w * h)
	flags.resize(w * h)
	for dy in h:
		var y := y0 + dy
		if y < 0 or y >= height: continue
		var run := 0
		var first := true
		var previous := 0
		var run2 := 0
		var run3 := 0
		for dx in w:
			var x := x0 + dx
			if x < 0 or x >= width:
				run = 0
				run2 = 0
				run3 = 0
				continue
			var cell := Vector2i(x, y)
			var index := y * width + x
			var v: int = _static_levels[index]
			var at := dx * h + dy
			if first:
				first = false
				run += 1
				previous = v
			elif previous == v:
				run += 1
				if rw <= run:
					levels[at] = previous
					flags[at] += 1
			else:
				run = 1
				previous = v
			var m: int = _static_materials[index]
			if m == 3 or m == 5 or m == 6 or m == 7 or m == 9: run2 = 0
			else:
				run2 += 1
				if rw <= run2: flags[at] += 2
			# Placement.blocked / _blocked_static written out: material 9, a building cell, a map object on the cell, and
			# (units_block) another unit standing on it; then the reservations.
			var taken := _static_permissions[index] == 0 or m == 9 or building_cells.has(cell)
			if not taken:
				var c: Dictionary = cells[index]
				taken = c.has("object_indices") and not c.object_indices.is_empty()
			if not taken and units_block:
				var unit = occupants.get(cell)
				taken = unit != null and is_instance_valid(unit) and unit != builder
			if taken or reserved.has(cell): run3 = 0
			else:
				run3 += 1
				if rw <= run3: flags[at] += 4
	var centre := Vector2i(x0 + (w >> 1), y0 + (h >> 1))
	var found := Vector2i(-1, -1)
	var best := -1
	for dx in w:
		var run := 0
		var level := 0
		for dy in h:
			var at := dx * h + dy
			if flags[at] != 7:
				run = 0
				continue
			if run == 0:
				level = levels[at]
			elif levels[at] != level:
				run = 0
				level = levels[at]
			run += 1
			if rh <= run:
				flags[at] = 5
				var cx := ((rw - 1) >> 1) - rw + dx + 1 + x0
				var cy := ((rh - 1) >> 1) - rh + dy + 1 + y0
				var metric := maxi(absi(cy - hint.y), absi(cx - hint.x)) + maxi(absi(cy - centre.y), absi(cx - centre.x))
				if found.x == -1 or metric < best:
					found = Vector2i(cx, cy)
					best = metric
	return found

static func _blocked_static(navigator, cell: Vector2i) -> bool:
	var collision = navigator.collision
	if int(collision.cell_data(cell).raw[1]) == 9: return true
	if navigator.building_cells.has(cell): return true
	var c: Dictionary = collision.cell_data(cell)
	return c.has("object_indices") and not c.object_indices.is_empty()