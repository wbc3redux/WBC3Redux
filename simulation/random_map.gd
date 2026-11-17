extends RefCounted
## RM-2 (RANDOM_MAP_RESEARCH.md "RM-2"): the Random Map's layout stage 0x582310, from its entry to the connectivity check
## (0x582a4b), on the piece sets of assets/random_map.json (RM-1, tools/random_map_data.py). Reproduces all 122 cases
## of tests/random_map_fixtures.json (tools/emulate_random_map.py, the original x86 under Unicorn) byte for byte:
## piece grid, MAPH records (code, quadrant, TER bytes), records beyond the map, feature records, generator state, attempts.
##
## What is ported, with its label:
## * the 16-bit generator 0x582130 / 0x5820b0 (A1, Emulated): s = s * 0x6255 + 0x3619 mod 2^16; `state` is never seeded
##   in single player (A2, Read): 0 at launch and carried across random maps by keeping this object;
## * 0x582e10's set table (A4, Emulated) from the data file's terrain_types;
## * slot filling (A6, Emulated): the first slot roll(1, 5, 1) re-rolled below 2, or roll(1, 25, 1) re-rolled below 7 for
##   lava, cavern and water; every other slot roll(1, count, -1), 0 re-rolled, 1..6 too in the first row and column
##   for those three sets, a piece already rejected for the slot re-rolled, a piece whose left edge differs from the left
##   neighbour's right edge or whose top edge differs from the upper neighbour's bottom edge rejected;
## * the world's fill 0x48f210 (A9, Emulated): 0x48f8c0(x, y, TGX0) with tile, not cell, coordinates, so only records
##   (x / 10, y / 10) become TGX0 (record (0, 0) on 64 maps, up to (2, 2) on 256 maps; the pieces overwrite the rest);
## * the tile writes (A8, Emulated): rows outer, columns inner, 3 x 3 per piece; a code without a TER record (0x497c10
##   -1) does not advance the piece's read index; skip word 0 -> 0x48f8c0; big tiles (TER byte 0x647) write their
##   partner quadrants; writes stop only at the 32 x 32 grid, so records beyond the map are written too;
## * the MAPH record bytes of 0x48f8c0 (Read, the in-map bytes 7..15 Emulated): +0 code, +4 tile index, +6 quadrant,
##   +7 TER byte 0x645, +9 TER byte 0x646, +0xb TER byte 0x647, the rest 0. The tile index is this port's order (the
##   data file's sorted tile codes); the original's tile-table order is Open (A12) and nothing in the rebuild reads it;
## * the features (A10, Emulated): every FTRH whose code is in the feature registry and whose x / 10 + col * 30 < width
##   and y / 10 + row * 30 < height (pixels divided by 10 compared with cells: the original's bug, kept) is placed at
##   x + col * 960, y + row * 720 world pixels;
## * the failure path 0x582d1d (A11, Read; replays Emulated): a failed connectivity check deletes the features and lays
##   the map out again with the running generator; the MAPH grid is not cleared (Read), so a record the new layout
##   does not write keeps the failed attempt's tile. The check itself is RM-4: `generate` takes it as a Callable.
##
## Deliberate modern change (labelled, A7): the original's 2000-roll guard (0x5824db) compares a signed byte and never
## fires, so a slot where no piece fits loops forever. This port stops a slot after SLOT_DRAW_BOUND draws of the
## generator without a fitting piece. The bound is the generator's full period (Hull-Dobell: c odd, a - 1 divisible by 4),
## so it is exact: within one period every state, hence every pick, has come up once; a piece that fits and was not yet
## rejected is taken the first time it comes up and the rejected set only grows, so a slot that found nothing in one
## period finds nothing ever: the original would hang there. Every layout the original finishes is unchanged (all 122
## fixture cases). Past the bound the port does what the original does after a failed check: it abandons the attempt
## and lays the map out again with the running generator (counted in `attempts` and `dead_ends`); after MAX_DEAD_ENDS
## dead ends it returns ok = false. RM-4: a failed connectivity check also lays the map out again, which the original
## repeats without limit (Caverns needs up to ~30 layouts on a 128 map); this port stops after MAX_ATTEMPTS layouts in
## all (deliberate bound, far above every fixture case) with ok = false. Retry within one call, not with a new call: the
## MAPH grid carries over between attempts (R3), a new call starts from the world's fill.
const Assets = preload("res://core/asset_store.gd")

static var DATA_PATH: String = Assets.path("random_map.json")
const SIZES := [64, 128, 192, 256]          # MapSize setting 0..3 -> cells (0x4e2893)
const BORDER_SETS := [4, 6, 8]              # lava, cavern, water
const SLOT := 30                            # cells per slot side
const SLOT_PIXELS := Vector2i(960, 720)     # 30 cells of 32 x 24 pixels
const GRID := 32                            # the world's 32 x 32 MAPH grid
const RECORD := 16                          # bytes per MAPH record
const MARKER := 0x7b
const SLOT_DRAW_BOUND := 0x10000            # deliberate modern change: the generator's period (see the header)
const MAX_DEAD_ENDS := 16                   # deliberate modern change: dead-end layouts per generate() call
const MAX_ATTEMPTS := 256                   # deliberate modern change: layouts per call, failed checks included

static var _cache := {}

var state := 0                              # 0x58e3ff8
var data: Dictionary
var _tile_index := {}                       # code -> this port's tile index (MAPH +4)
var _registry := {}

func _init(initial_state: int = 0, piece_data: Dictionary = {}):
	state = initial_state & 0xffff
	data = piece_data if not piece_data.is_empty() else load_data()
	var codes: Array = data.get("tiles", {}).keys()
	codes.sort()
	for i in codes.size(): _tile_index[codes[i]] = i
	for code in data.get("feature_registry", []): _registry[code] = true

static func load_data(path: String = DATA_PATH) -> Dictionary:
	if not _cache.has(path):
		var text := FileAccess.get_file_as_string(path)
		var parsed = JSON.parse_string(text) if text != "" else null
		_cache[path] = parsed if parsed is Dictionary else {}
	return _cache[path]

static func size_cells(size_setting: int) -> int:
	return SIZES[clampi(size_setting, 0, SIZES.size() - 1)]

## 0x582130: one step of the 16-bit generator.
func next_state() -> int:
	state = (state * 0x6255 + 0x3619) & 0xffff
	return state

## 0x5820b0(count, sides, bonus): `count` draws of (s * sides) / 0xffff + 1, clamped to 1..sides, plus bonus.
func roll(count: int, sides: int, bonus: int) -> int:
	var total := 0
	for i in count:
		var v: int = (next_state() * sides) / 0xffff + 1
		total += clampi(v, 1, sides)
	return total + bonus

## 0x582310(terrain) for a size_cells x size_cells map. `check` is the connectivity check (RM-4): called with the
## layout (the returned keys) after the features; false regenerates like 0x582d1d. Without it the check passes.
## Returns ok, attempts, dead_ends, lcg_after, cols, rows, goms ([row][col]), maph (32 x 32 x 16 bytes, record
## (x * 32 + y) * 16 as in the world), tiles ([y][x] = [code, quadrant] on the map, "" for an empty record),
## tiles_outside_map, features ([code, w1, w2, w3, x, y], world pixels).
func generate(terrain: int, size: int, check: Callable = Callable()) -> Dictionary:
	var types: Array = data.terrain_types
	var entry: Dictionary = types[terrain] if terrain >= 0 and terrain < types.size() else types[0]   # 0x582e10 default
	var pieces: Array = data.sets[entry.set].pieces
	var count: int = int(entry.count)
	var border: bool = terrain in BORDER_SETS
	var maph := PackedByteArray()
	maph.resize(GRID * GRID * RECORD)
	var tiles := (size - 1) / 10 + 1
	for y in tiles:                                        # 0x48f210's fill: 0x48f8c0 divides by 10 again
		for x in tiles: _set_tile(maph, x / 10, y / 10, data.fill_tile)
	var result := {"ok": false, "terrain": terrain, "size": size, "attempts": 0, "dead_ends": 0}
	while int(result.attempts) < MAX_ATTEMPTS:
		result.attempts = int(result.attempts) + 1
		var layout := _layout(pieces, count, border, size)
		if layout.is_empty():
			result.dead_ends = int(result.dead_ends) + 1
			if int(result.dead_ends) >= MAX_DEAD_ENDS: break
			continue
		var cols: int = layout.cols
		var rows: int = layout.rows
		var chosen: Array = layout.chosen
		for r in rows:
			for c in cols: _write_piece(maph, chosen[r][c], c * 3, r * 3)
		result.cols = cols
		result.rows = rows
		result.goms = layout.goms
		result.features = _features(chosen, cols, rows, size)
		result.maph = maph
		_summarise(result, maph, tiles)
		if check.is_valid() and not bool(check.call(result)): continue
		result.ok = true
		break
	result.lcg_after = state
	return result

## One layout (0x582366 .. 0x582628): the piece per slot, or {} when a slot reaches SLOT_DRAW_BOUND.
func _layout(pieces: Array, count: int, border: bool, size: int) -> Dictionary:
	var picked := {}                                       # Vector2i(col, row) -> [index, piece]
	var first := 0
	var h: Dictionary
	var draws := 0
	while true:                                            # the first slot (0x582366)
		while true:
			if draws >= SLOT_DRAW_BOUND: return {}
			draws += 1
			if border:
				first = roll(1, 25, 1)
				if first < 7: continue
			else:
				first = roll(1, 5, 1)
			if first >= 2: break
		h = _piece(pieces, first)
		if not h.is_empty() and int(h.marker) == MARKER: break
	picked[Vector2i(0, 0)] = [first, h]
	var col := 1
	var row := 0
	var row_pixels := 0
	var cols := 0
	while true:                                            # one slot (0x58241c)
		var edge := not (col != 0 and row_pixels != 0)
		var tried := {}
		var pick := 0
		draws = 0
		while true:
			while true:
				# Deliberate modern change: one generator period without a fitting piece; the original hangs here.
				if draws >= SLOT_DRAW_BOUND: return {}
				pick = roll(1, count, -1)
				draws += 1
				if edge and (pick < 7 if border else pick == 0): continue
				if tried.has(pick): continue
				break
			if pick < 1: continue
			h = _piece(pieces, pick)
			if h.is_empty() or int(h.marker) != MARKER: continue
			var left_ok: bool = col < 1 or int(h.edges[3]) == int(picked[Vector2i(col - 1, row)][1].edges[1])
			var top_ok: bool = row_pixels < 1 or int(h.edges[0]) == int(picked[Vector2i(col, row - 1)][1].edges[2])
			if left_ok and top_ok: break
			tried[pick] = true
		picked[Vector2i(col, row)] = [pick, h]
		col += 1
		if size <= col * SLOT:
			cols = col
			col = 0
			row += 1
			row_pixels += SLOT
		if size <= row_pixels: break
	var chosen := []
	var goms := []
	for r in row:
		var pieces_row := []
		var index_row := []
		for c in cols:
			index_row.append(picked[Vector2i(c, r)][0])
			pieces_row.append(picked[Vector2i(c, r)][1])
		chosen.append(pieces_row)
		goms.append(index_row)
	return {"cols": cols, "rows": row, "chosen": chosen, "goms": goms}

func _piece(pieces: Array, index: int) -> Dictionary:
	return pieces[index] if index >= 0 and index < pieces.size() and pieces[index] is Dictionary else {}

## The 3 x 3 tile writes of one piece at tile (x0, y0): 0x497c10 must find the code before the read index advances.
func _write_piece(maph: PackedByteArray, piece: Dictionary, x0: int, y0: int):
	var codes: Array = piece.tiles
	var skip: Array = piece.skip
	var i := 0
	for ty in 3:
		for tx in 3:
			var code: String = codes[i]
			if _tile_index.has(code):
				if int(skip[i]) == 0: _set_tile(maph, x0 + tx, y0 + ty, code)
				i += 1

## 0x48f8c0 in tile coordinates: the record and, for a big tile (TER byte 0x647), its partner quadrants inside the grid.
func _set_tile(maph: PackedByteArray, x: int, y: int, code: String):
	if x < 0 or y < 0: return
	var ter: PackedByteArray = _ter(code)
	var shape: int = ter[0x647]
	_record(maph, x, y, code, 0, ter)
	if shape == 0: return
	if shape == 2:
		if x + 1 < GRID: _record(maph, x + 1, y, code, 1, ter)
	elif shape == 3:
		if y + 1 < GRID: _record(maph, x, y + 1, code, 2, ter)
	else:
		if x + 1 < GRID: _record(maph, x + 1, y, code, 1, ter)
		if y + 1 < GRID: _record(maph, x, y + 1, code, 2, ter)
		if x + 1 < GRID and y + 1 < GRID: _record(maph, x + 1, y + 1, code, 3, ter)

var _ter_cache := {}
func _ter(code: String) -> PackedByteArray:
	if not _ter_cache.has(code): _ter_cache[code] = Marshalls.base64_to_raw(data.tiles[code].ter)
	return _ter_cache[code]

func _record(maph: PackedByteArray, x: int, y: int, code: String, quadrant: int, ter: PackedByteArray):
	if x >= GRID or y >= GRID: return
	var at := (x * GRID + y) * RECORD
	var ascii := code.to_ascii_buffer()
	for k in 4: maph[at + k] = ascii[k]
	maph.encode_u16(at + 4, int(_tile_index[code]))
	maph[at + 6] = quadrant
	maph[at + 7] = ter[0x645]
	maph[at + 8] = 0
	maph[at + 9] = ter[0x646]
	maph[at + 0xb] = ter[0x647]
	maph.encode_u32(at + 0xc, 0)                       # +0xa is never written (stays 0 in the zeroed world)

## The feature loop (0x5828a0 .. 0x582a4b): registry codes inside the pixel / 10 bound, in world pixels.
func _features(chosen: Array, cols: int, rows: int, size: int) -> Array:
	var out := []
	for r in rows:
		for c in cols:
			for f in chosen[r][c].features:
				if not _registry.has(f[0]): continue
				var x: int = int(f[4])
				var y: int = int(f[5])
				if x / 10 + c * SLOT < size and y / 10 + r * SLOT < size:
					out.append([f[0], int(f[1]), int(f[2]), int(f[3]), x + c * SLOT_PIXELS.x, y + r * SLOT_PIXELS.y])
	return out

func _summarise(result: Dictionary, maph: PackedByteArray, tiles: int):
	var grid := []
	var outside := 0
	for y in GRID:
		var line := []
		for x in GRID:
			var at := (x * GRID + y) * RECORD
			var empty := maph.decode_u32(at) == 0
			if x < tiles and y < tiles:
				line.append(["" if empty else maph.slice(at, at + 4).get_string_from_ascii(), maph[at + 6]])
			elif not empty:
				outside += 1
		if y < tiles: grid.append(line)
	result.tiles = grid
	result.tiles_outside_map = outside

## Bytes 7..15 of a record, as hex (the fixture's maph_extra lists the distinct values among the non-empty records).
static func record_tail_hex(maph: PackedByteArray, x: int, y: int) -> String:
	var at := (x * GRID + y) * RECORD
	return maph.slice(at + 7, at + RECORD).hex_encode()
