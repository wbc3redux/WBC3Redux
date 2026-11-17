extends RefCounted
## Building placement validity, a port of the B/b branch of 0x435900 (emulated for every order cell of the
## Knights slice in tests/production_fixtures.json). Cells are (x, y); `order_cell` is the click cell,
## which 0x524450 shifts up to the footprint's top row before the check.
## Rule order: anchor bounds; whole bounding box inside the map; every solid footprint cell (mask bit
## clear) at the same TER height; none of materials 3, 5, 6, 7, 9; permission nonzero and the cell not
## occupied (0x42c8e0) except by the builder. The local-player fog/explored queries (0x480770/0x4806a0,
## 0x47f6a0/0x47f560) are only applied through the optional `visible` callable (fog is not modelled).

static func anchor(definition: Dictionary, order_cell: Vector2i) -> Vector2i:
	var height: int = definition.footprint[1]
	return Vector2i(order_cell.x - (((int(definition.footprint[0]) - 1)) >> 1), order_cell.y - ((height - 1) >> 1))

static func solid(definition: Dictionary, col: int, row: int) -> bool:
	return ((int(definition.mask_rows[row]) >> col) & 1) == 0

static func solid_cells(definition: Dictionary, left: int, top: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for row in range(int(definition.footprint[1])):
		for col in range(int(definition.footprint[0])):
			if solid(definition, col, row): out.append(Vector2i(left + col, top + row))
	return out

static func check(navigator: RefCounted, definition: Dictionary, order_cell: Vector2i, builder = null, visible: Callable = Callable()) -> Dictionary:
	var top: int = order_cell.y - ((int(definition.footprint[1]) - 1) >> 1)
	return check_top(navigator, definition, order_cell.x, top, builder, visible)

static func check_top(navigator: RefCounted, definition: Dictionary, cx: int, top: int, builder = null, visible: Callable = Callable()) -> Dictionary:
	var collision = navigator.collision
	var width: int = definition.footprint[0]
	var height: int = definition.footprint[1]
	var left: int = cx - ((width - 1) >> 1)
	var result := {"ok": false, "reason": "", "left": left, "top": top}
	if top <= 0 or left <= 0 or top >= collision.height - 1 or left >= collision.width - 1:
		result.reason = "anchor outside the map interior"
		return result
	var reference := -1
	for row in range(height):
		var y := top + row
		if y < 0 or y >= collision.height:
			result.reason = "footprint leaves the map"
			return result
		for col in range(width):
			var x := left + col
			if x < 0 or x >= collision.width:
				result.reason = "footprint leaves the map"
				return result
			if solid(definition, col, row):
				var level: int = int(collision.cell_data(Vector2i(x, y)).raw[0])
				if reference < 0: reference = level
				elif level != reference:
					result.reason = "terrain is not level"
					return result
	for row in range(height):
		for col in range(width):
			var cell := Vector2i(left + col, top + row)
			if solid(definition, col, row) and collision.inside(cell):
				var material: int = int(collision.cell_data(cell).raw[1])
				if material in [3, 5, 6, 7, 9]:
					result.reason = "terrain material %d cannot be built on" % material
					return result
	for row in range(height):
		for col in range(width):
			var cell := Vector2i(left + col, top + row)
			if not solid(definition, col, row) or not collision.inside(cell): continue
			if int(collision.cell_data(cell).raw[2]) == 0:
				result.reason = "terrain does not permit building"
				return result
			if blocked(navigator, cell, builder):
				result.reason = "cell is occupied"
				return result
			if visible.is_valid() and not visible.call(cell):
				result.reason = "cell is not visible"
				return result
	if bool(navigator.get("improved")) and seals(navigator, definition, left, top):
		result.reason = "this would wall in a building or its exit"
		return result
	result.ok = true
	return result

# DELIBERATE MODERN CHANGE (modern_rules.gd "Movement", COMPLAINTS_AND_FIXES.md F4): the original lets a building close
# the last gap between buildings and terrain, trapping the units its neighbours (or itself) train. A placement is refused
# when a free cell next to the new footprint ends up in a pocket of fewer than OPEN_AREA cells.
const OPEN_AREA := 300

static func seals(navigator: RefCounted, definition: Dictionary, left: int, top: int) -> bool:
	var footprint := {}
	for c in solid_cells(definition, left, top): footprint[c] = true
	# Fast path: with no blocked cell within two cells of the footprint nothing can be walled in.
	var width: int = definition.footprint[0]
	var height: int = definition.footprint[1]
	var near_block := false
	for y in range(top - 2, top + height + 2):
		for x in range(left - 2, left + width + 2):
			var c := Vector2i(x, y)
			if not footprint.has(c) and not navigator.enterable_static(c):
				near_block = true
				break
		if near_block: break
	if not near_block: return false
	var open := {}                                  # cells known to reach the open map
	for c in footprint:
		for step in navigator.SEARCH_ORDER:
			var start: Vector2i = c + step
			if footprint.has(start) or open.has(start) or not navigator.enterable_static(start): continue
			var seen := {start: true}
			var queue: Array[Vector2i] = [start]
			var reached_open := false
			while not queue.is_empty() and seen.size() < OPEN_AREA:
				var cell: Vector2i = queue.pop_back()
				for s in navigator.SEARCH_ORDER:
					var n: Vector2i = cell + s
					if seen.has(n) or footprint.has(n) or not navigator.enterable_static(n): continue
					if s.x != 0 and s.y != 0 and not (navigator.enterable_static(Vector2i(n.x, cell.y)) and not footprint.has(Vector2i(n.x, cell.y))) \
							and not (navigator.enterable_static(Vector2i(cell.x, n.y)) and not footprint.has(Vector2i(cell.x, n.y))):
						continue
					if open.has(n):
						reached_open = true
						break
					seen[n] = true
					queue.append(n)
				if reached_open: break
			if not reached_open and seen.size() < OPEN_AREA: return true
			open.merge(seen)
	return false

# 0x42c8e0 as called by 0x435900: blocked by the material-9 hard block or by an occupied cell,
# unless the occupant is the builder itself.
static func blocked(navigator: RefCounted, cell: Vector2i, builder = null) -> bool:
	var collision = navigator.collision
	if int(collision.cell_data(cell).raw[1]) == 9: return true
	if navigator.building_cells.has(cell): return true
	var c: Dictionary = collision.cell_data(cell)
	if c.has("object_indices") and not c.object_indices.is_empty(): return true
	var unit = navigator.occupants.get(cell)
	return unit != null and is_instance_valid(unit) and unit != builder
