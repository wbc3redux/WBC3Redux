extends RefCounted
## RM-5 (RANDOM_MAP_RESEARCH.md "RM-5"): match-start placement on a generated map, 0x583960 from entry to its dead roll, on
## random_map.gd's layout (MAPH bytes, features) and random_map_grid.gd's grid. Equal, step for step, to
## tests/random_map_place_fixtures.json (tools/emulate_random_map.py --place, the original under Unicorn): every start,
## tile change, deleted feature, placement search with its answer, building, animal try, animal, both generators after
## every phase, and the occupancy grid before and after placement.
##
## The order (all Emulated unless marked): for each side in slot order the start 0x419440 (16-bit generator); for each
## side the start-area tiles, then its start-area features; a new grid (0x5319b0, 0x42c5d0, 0x42bef0, 0x42de30 with the
## tiles and features as they are now); towers 0x4183b0, mines 0x418df0, quest sites 0x418ce0, utilities 0x418ae0, animals
## and the dead roll (game generator 0x458e70).
## * Occupancy (R5-2): 0x42c8e0(x, y, 0, 1, 1, 0, 0) reads only the cell's +9 == 9 and +4 & 0x80: both arguments that would
##   reach a live object's vtable are 1, so no object is ever asked. At the starts the grid is the fresh one the
##   passed check left, so the test always answers free (the starts look at terrain only).
## * Objects do not exist yet (R5-3): 0x418700 only sends message 0x10f (0x4a50f0), and 0x4a5780 sends 0xfd, whose handlers
##   queue them on a list; what later placements see is the reservation 0x42d700: a building sets the occupied bit on
##   the 12 x 8 cells from (x - 6, y), an animal on the 2 x 2 from (x, y). The ground layer only, clipped to the map.
## * The search (R5-1) `_search` is 0x435320.
##
## The game generator's seed is the caller's (`settings.rng`, both words): B10 stays Open for the second word and the
## clock, see "RM-5". The 16-bit generator is random_map.gd's and runs on from the layout.
##
## Deliberate modern changes (labelled): a start whose candidate loop finds no acceptable cell hangs the original. The
## loop's state (generator state, 16-bit try counter) repeats after 65536 tries, so a start with none in 65536 tries can
## never get one: `place` stops there with ok = false. The same answer when no candidate of the 250 beats -30000 (every
## one within 25 cells of four earlier starts): the original then returns an uninitialised local. No fixture reaches either.
const Assets = preload("res://core/asset_store.gd")

const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapGrid = preload("res://simulation/random_map_grid.gd")
const RandomMapCheck = preload("res://simulation/random_map_check.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")

static var CATALOGUE_PATH: String = Assets.path("catalogue.json")
const START_CANDIDATES := 250              # 0x419440
const START_TRY_BOUND := 0x10000           # deliberate modern change (see the header)
const NEUTRAL := 6
const VICTORY_NO_TOWERS := 11              # 0x4183b0's gate on 0x70ae12
const TOWER_CODES := ["BWTC", "BWTD", "BWTU", "BWTB", "BWTR", "BWTO", "BWTM", "BWTW", "BWTK", "BWTF", "BWTA", "BWTV",
	"BWTH", "BWTL", "BWTE", "BWTG"]        # 0x4183b0, by race 0..15
const MINE_CODES := ["BRC2", "BRG2", "BRM2", "BRS2", "BRC1", "BRG1", "BRM1", "BRS1", "BRC0", "BRG0", "BRM0", "BRS0"]
const MINE_LEVELS := [0, 0, 1, 1, 2]       # 0x608348, row of MINE_CODES by roll(1, 5, -1)
const SITE_CODES := ["BMSH", "BZMA"]       # 0x418ce0, alternating
const UTILITY_CODES := ["BTCE", "BTIN", "BTDR", "BSFG", "BSFG", "BSFG", "BLHN", "BLGL", "BSBS", "BLBM", "BLGH", "BTCE",
	"BTIN", "BTDR", "BTEL", "BSFG", "BSFG"]  # 0x418ae0's 17 entries; the first BTEL lookup there is thrown away
const WIDE_TOWERS := ["BWTC", "BWTD", "BWMO", "BWTU", "BWTB", "BWTR", "BWTO", "BWTP", "BWTM", "BWTK", "BWTW", "BWTF",
	"BWTA", "BWTH", "BWTG", "BWTE", "BWTL", "BWTV"]   # 0x435320: margin 3 instead of 5
const ANIMAL_COUNTS := [0, 4, 9, 16, 24]   # 0x417280, the CritterLevel setting
const DEAD_ROLL := {64: 2, 128: 3, 192: 5, 256: 7}
## 0x584270's creature table, six per terrain type 0..9.
const ANIMALS := [
	"ACSH", "ACCO", "ACSH", "ACCO", "ACGO", "ACTU", "ACSH", "ACCO", "ACSH", "ACCO", "ACGO", "ACGO",
	"ACSH", "ACCO", "ACSH", "ACCO", "ACGO", "ACTU", "ACSH", "ACCO", "ACCA", "ACCA", "ACCA", "ACCA",
	"ACSH", "ACCO", "ACSH", "ACTU", "ACSH", "ACCO", "ACSH", "ACCO", "ACSH", "ACCA", "ACCA", "ACCA",
	"ACTU", "ACTU", "ACTU", "ACTU", "ACTU", "ACTU", "ACSH", "ACSE", "ACPE", "ACPE", "ACPE", "ACSE",
	"ACSH", "ACCO", "ACSH", "ACTU", "ACSE", "ACSE", "ACSH", "ACCO", "ACTU", "ACTU", "ACTU", "ACTU"]
## 0x583960's start-area pass: tile -> plain tile, for every big tile of the piece sets whose 12 edge words in
## Assets\Terrain\*.en are equal (world + 0x1a5010, +0x1a502a); the plain tile is T<c>X0 of the code's second letter,
## C -> K, U -> J. Generated from the installation, pinned by the fixtures' plain_tiles.
const PLAIN_TILES := {
	"TCF0": "TKX0", "TCF1": "TKX0", "TCF2": "TKX0", "TCF3": "TKX0", "TDF0": "TDX0", "TDF1": "TDX0", "TDF2": "TDX0",
	"TDF3": "TDX0", "TDF4": "TDX0", "TDF5": "TDX0", "TDF6": "TDX0", "TDF7": "TDX0", "TGF0": "TGX0", "TGF1": "TGX0",
	"TGF2": "TGX0", "TGF3": "TGX0", "TGF4": "TGX0", "TGF5": "TGX0", "TGF6": "TGX0", "TGF7": "TGX0", "THF0": "THX0",
	"THF1": "THX0", "THF2": "THX0", "THF3": "THX0", "THF4": "THX0", "THF5": "THX0", "THF6": "THX0", "TIF4": "TIX0",
	"TIF5": "TIX0", "TKF0": "TKX0", "TKF1": "TKX0", "TKF2": "TKX0", "TKF3": "TKX0", "TKF4": "TKX0", "TKF5": "TKX0",
	"TKF6": "TKX0", "TKF7": "TKX0", "TKF8": "TKX0", "TSF0": "TSX0", "TSF1": "TSX0", "TSF2": "TSX0", "TSF3": "TSX0",
	"TSF4": "TSX0", "TSF5": "TSX0", "TSF6": "TSX0", "TSF7": "TSX0", "TUF0": "TJX0", "TUF1": "TJX0", "TUF2": "TJX0",
	"TUF3": "TJX0", "TUF4": "TJX0", "TUF5": "TJX0", "TUF6": "TJX0", "TUF7": "TJX0"}

var generator                               # random_map.gd: the 16-bit generator
var data: Dictionary
var rng: CombatRng
var building_sizes := {}
var size := 0
var maph: PackedByteArray
var height := PackedByteArray()             # per cell, row-major, the world accessors 0x48f810 / 0x48f6b0 / 0x48f760
var material := PackedByteArray()
var permission := PackedByteArray()
var occupied := PackedByteArray()           # ground layer +4 & 0x80
var navigation = null
var log := {}
var _phase := {}
var _a := PackedByteArray()                 # 0x435320's two 70 x 70 work arrays
var _b := PackedByteArray()
static var _catalogue := {}
static var _footprints := {}

## generator: the random_map.gd object that made the layout (its state runs on). piece_data: random_map.json.
func _init(random_map, piece_data: Dictionary = {}):
	generator = random_map
	data = piece_data if not piece_data.is_empty() else random_map.data
	_a.resize(70 * 70)
	_b.resize(70 * 70)

static func load_building_sizes() -> Dictionary:
	if _catalogue.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
		if parsed is Dictionary:
			for code in parsed.buildings:
				var raw: String = parsed.buildings[code].raw_hex
				_catalogue[code] = [("0x" + raw.substr(0x3e * 2, 2)).hex_to_int(), ("0x" + raw.substr(0x3f * 2, 2)).hex_to_int()]
	return _catalogue

## RM-7: code -> the catalogue's footprint (size, masks), for the real stamps of the buildings.
static func load_footprints() -> Dictionary:
	if _footprints.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(CATALOGUE_PATH))
		if parsed is Dictionary:
			for code in parsed.buildings: _footprints[code] = parsed.buildings[code].footprint
	return _footprints

## layout: random_map.gd generate()'s result (not changed; `maph`, `tiles`, `features` of the result are the match's).
## sides: [{slot 0..5, race 0..15}] in slot order. settings: rng [first, second] (game generator words), temples 0..4,
## animals (count after 0x417280: ANIMAL_COUNTS), resources 0..2, quests, no_towers, victory (0x70ae12: 0x4183b0 places
## no towers at VICTORY_NO_TOWERS).
## Returns ok, starts ([{side_index, cell}]), buildings ([{code, owner, cell, cell_position, world_position, start_side},
## mines also level, resource, rate, stock]), armies ([{code, owner, cell, cell_position, world_position}]), features (the
## surviving [code, w1, w2, w3, x, y]), deleted (indices in layout.features), tile_changes, maph, tiles, grid
## (random_map_grid.gd's static grid of the final tiles and surviving features), occupied (with the reservations),
## rng_after, lcg_after, log (per phase, what the fixtures compare).
func place(layout: Dictionary, sides: Array, settings: Dictionary) -> Dictionary:
	size = int(layout.size)
	maph = layout.maph.duplicate()
	log = {"phases": {}}
	building_sizes = load_building_sizes()
	var words: Array = settings.get("rng", [0, 0])
	rng = CombatRng.new(int(words[0]), int(words[1]))
	var result := {"ok": false, "size": size}
	_read_world()
	var starts := {}                        # slot -> Vector2i
	for side in sides:
		var cell := _start(int(side.slot), sides, starts)
		if cell.x < 0: return result
		starts[int(side.slot)] = cell
	var features: Array = layout.features.slice(0, RandomMapGrid.FEATURE_POOL)
	var rows := _feature_rows(features)
	var deleted: Array = []
	var changes := {}
	for side in sides:
		var cell: Vector2i = starts[int(side.slot)]
		_clear_tiles(cell, changes)
		_clear_features(cell, rows, deleted)
	log.lcg_after_starts = generator.state
	log.deleted = deleted
	var gone := {}
	for i in deleted: gone[i] = true
	var left: Array = []
	for i in features.size():
		if not gone.has(i): left.append(features[i])
	var grid = RandomMapGrid.new({"size": size, "maph": maph, "features": left}, data)
	_read_world()
	_read_occupancy(grid)
	log.occupied_before_placement = _occupied_rle()
	var buildings: Array = []
	if not bool(settings.get("no_towers", false)): _towers(sides, starts, buildings, int(settings.get("victory", 0)))
	_mines(sides, starts, int(settings.get("resources", 1)), buildings)
	_sites(sides.size(), bool(settings.get("quests", true)), buildings)
	_utilities(int(settings.get("temples", 0)), buildings)
	var armies := _animals(grid, int(settings.get("animals", 0)), int(layout.terrain))
	rng.roll(1, DEAD_ROLL[size], -1)
	log.occupied_after = _occupied_rle()
	var start_list: Array = []
	for side in sides:
		var cell: Vector2i = starts[int(side.slot)]
		start_list.append({"side_index": int(side.slot), "cell": [cell.x, cell.y]})
	var change_list: Array = changes.values()
	change_list.sort_custom(func(p, q): return p[0] * 32 + p[1] < q[0] * 32 + q[1])
	result.merge({"ok": true, "starts": start_list, "buildings": buildings, "armies": armies, "features": left,
		"deleted": deleted, "tile_changes": change_list, "maph": maph, "tiles": _tiles_of(), "grid": grid,
		"rng_after": rng.state(), "lcg_after": generator.state, "log": log, "occupied": occupied}, true)
	return result

func _tiles_of() -> Array:
	var summary := {}
	generator._summarise(summary, maph, (size - 1) / 10 + 1)
	return summary.tiles

# ----------------------------------------------------------------------------------------- the world accessors
## 0x48f810 / 0x48f6b0 / 0x48f760 through the MAPH record of (x, y); 0 for a negative coordinate, and cells past the map
## read the records the pieces wrote there. out: 0 elevation, 1 material, 2 permission.
func _terrain_byte(x: int, y: int, out: int) -> int:
	if x < 0 or y < 0: return 0
	var at := ((x / 10) * RandomMap.GRID + y / 10) * RandomMap.RECORD
	if maph.decode_u32(at) == 0: return 0
	var code := maph.slice(at, at + 4).get_string_from_ascii()
	var q: int = maph[at + 6]
	var sx := x % 10 + (q & 1) * 10
	var sy := y % 10 + (q >> 1) * 10
	return generator._ter(code)[4 + (sx * 20 + sy) * 4 + out]

func _read_world():
	var count := size * size
	height.resize(count)
	material.resize(count)
	permission.resize(count)
	# One tile at a time: a 256 map has 676 tiles and 65536 cells.
	for tx in (size - 1) / 10 + 1:
		for ty in (size - 1) / 10 + 1:
			var at := (tx * RandomMap.GRID + ty) * RandomMap.RECORD
			if maph.decode_u32(at) == 0: continue
			var ter: PackedByteArray = generator._ter(maph.slice(at, at + 4).get_string_from_ascii())
			var q: int = maph[at + 6]
			for sx in 10:
				var x := tx * 10 + sx
				if x >= size: break
				var column := (sx + (q & 1) * 10) * 20
				for sy in 10:
					var y := ty * 10 + sy
					if y >= size: break
					var offset := 4 + (column + sy + (q >> 1) * 10) * 4
					var cell := y * size + x
					height[cell] = ter[offset]
					material[cell] = ter[offset + 1]
					permission[cell] = ter[offset + 2]

func _read_occupancy(grid):
	occupied.resize(size * size)
	occupied.fill(0)
	var cells: Array = grid.data.cells
	for i in cells.size():
		if not cells[i].object_indices.is_empty(): occupied[i] = 1

## Per cell, row-major: bit 0 occupied, bit 1 cell +9 == 9 (0x42bf80 writes the material there): what 0x42c8e0 reads.
func _occupied_rle() -> Array:
	var out: Array = []
	var last := -1
	var run := 0
	for i in occupied.size():
		var v: int = occupied[i] | (2 if material[i] == 9 else 0)
		if v == last:
			run += 1
		else:
			if run > 0: out.append([last, run])
			last = v
			run = 1
	if run > 0: out.append([last, run])
	return out

func _reserve(x: int, y: int, w: int, h: int):            # 0x42d700
	for cy in range(maxi(y, 0), mini(y + h, size)):
		for cx in range(maxi(x, 0), mini(x + w, size)):
			occupied[cy * size + cx] = 1
			if navigation != null: navigation.building_cells[Vector2i(cx, cy)] = -1

# ------------------------------------------------------------------------------------------------ the starts
## 0x419440(p, 1): the best of 250 candidates; -1, -1 past the deliberate bound.
func _start(slot: int, sides: Array, starts: Dictionary) -> Vector2i:
	var best := -30000
	var chosen := Vector2i(-1, -1)
	for candidate in START_CANDIDATES:
		var tries := 0
		var x := 0
		var y := 0
		var bound := 0
		while true:
			bound += 1
			if bound > START_TRY_BOUND: return Vector2i(-1, -1)
			tries = ((tries + 1 + 0x8000) & 0xffff) - 0x8000    # the counter is a short
			x = generator.roll(1, size - 20, 10)
			y = generator.roll(1, size - 20, 10)
			var ok := true
			for c in [[x, y], [x + 8, y], [x, y + 8], [x - 8, y], [x, y - 8]]:
				if _terrain_byte(c[0], c[1], 1) in [3, 5, 6, 9, 10]: ok = false
			if tries < 500:
				var level := _terrain_byte(x, y, 0)
				for c in [[x + 7, y], [x, y + 7], [x - 7, y], [x, y - 7]]:
					if _terrain_byte(c[0], c[1], 0) != level: ok = false
			if tries < 250:
				var level := _terrain_byte(x, y, 0)
				var flat := true
				for c in [[x + 7, y + 7], [x - 7, y + 7], [x - 7, y - 7], [x + 7, y - 7]]:
					if _terrain_byte(c[0], c[1], 0) != level: flat = false
				if not flat: continue
			if ok: break
		var score: int = size >> 1
		if generator.roll(1, 100, 0) >= 20:
			score = absi((size >> 1) - y) + absi((size >> 1) - x)
		for side in sides:                 # sides are in slot order; only the earlier ones have a start
			var q: int = side.slot
			if q >= slot: break
			var d := absi(x - starts[q].x) + absi(y - starts[q].y)
			if d < 25: score -= 10000
			elif d < 50: score -= 1000
			elif d < 64: score -= 500
			elif d < 80: score += d
			else: score += (d >> 1) + d
		if best < score:
			best = score
			chosen = Vector2i(x, y)
	return chosen

# --------------------------------------------------------------------------------------- the start areas
## 5 x 5 tiles from ((x - 30) / 10, (y - 30) / 10), both clamped at 0: a quadrant-0 tile of PLAIN_TILES becomes its
## plain tile as a 2 x 2 block. The loop reads records it has just written (they are plain by then).
func _clear_tiles(cell: Vector2i, changes: Dictionary):
	var x0: int = maxi(cell.x - 30, 0) / 10
	var y0: int = maxi(cell.y - 30, 0) / 10
	for ty in range(y0, y0 + 5):
		for tx in range(x0, x0 + 5):
			if tx >= 33 or ty >= 33: continue
			var at := (tx * RandomMap.GRID + ty) * RandomMap.RECORD
			if maph[at + 6] != 0: continue
			var code := maph.slice(at, at + 4).get_string_from_ascii()
			if not PLAIN_TILES.has(code): continue
			var plain: String = PLAIN_TILES[code]
			_write(tx, ty, plain, changes)
			if tx < 31:
				_write(tx + 1, ty, plain, changes)
				if ty + 1 < 32: _write(tx + 1, ty + 1, plain, changes)
			if ty + 1 < 32: _write(tx, ty + 1, plain, changes)

func _write(tx: int, ty: int, code: String, changes: Dictionary):
	generator._set_tile(maph, tx, ty, code)
	changes[Vector2i(tx, ty)] = [tx, ty, code, maph[(tx * RandomMap.GRID + ty) * RandomMap.RECORD + 6],
		RandomMap.record_tail_hex(maph, tx, ty)]

## The row lists of 0x5473b0, per anchor cell: x sorted, a later object goes before equal x, so the list per cell is
## newest first (here: the back of the array).
func _feature_rows(features: Array) -> Dictionary:
	var rows := {}
	for i in features.size():
		var f: Array = features[i]
		var anchor := Vector2i(int(f[4]) >> 5, clampi(int(int(f[5]) / 24), 0, size - 1))
		if not rows.has(anchor): rows[anchor] = []
		rows[anchor].append(i)
	return rows

## 40 x 40 cells from (x - 20, y - 20), clamped at 0 (the square shifts, it does not shrink), x outer: 0x547960 gives the
## first object anchored at each cell and only that one is deleted.
func _clear_features(cell: Vector2i, rows: Dictionary, deleted: Array):
	var x0 := maxi(cell.x - 20, 0)
	var y0 := maxi(cell.y - 20, 0)
	for x in range(x0, x0 + 40):
		if x >= size: continue
		for y in range(y0, y0 + 40):
			if y >= size: continue
			var at := Vector2i(x, y)
			if rows.has(at) and not rows[at].is_empty():
				deleted.append(rows[at].pop_back())

# ------------------------------------------------------------------------------------------------- the search
## 0x435320(code, x0, y0, w, h, hint, 0): the free spot in the window nearest (Chebyshev to the hint plus Chebyshev to the
## window's centre, the first best one, x outer, y inner). Packed as Vector2i; -1, -1 for none. Three per-cell passes on a
## 70 x 70 array (index dx * 70 + dy), then a column scan:
## 1. heights: per row, a run of equal height; a cell closing a run of `rw` or more gets +1 and the height;
## 2. materials: a run of cells outside 3, 5, 6, 7, 9; closing `rw` gets +2;
## 3. permission non-zero, 0x42c8e0 free, cell +0x25 zero (nothing writes it at match start); closing `rw` gets +4;
## 4. per column a run of `rh` cells with value 7 and one height: the spot is ((rw - 1) >> 1) - rw + dx + 1, the same in y.
## rw, rh = the building's size + 5, + 3 for the towers. A found cell is overwritten with 5 and does not end the run.
func _search(code: String, x0: int, y0: int, w: int, h: int, hint: Vector2i) -> Vector2i:
	var sized: Array = building_sizes[code]
	var margin := 3 if code in WIDE_TOWERS else 5
	var rw: int = int(sized[0]) + margin
	var rh: int = int(sized[1]) + margin
	_a.fill(0)
	_b.fill(0)
	for dy in h:
		var y := y0 + dy
		if y < 0 or y >= size: continue
		var run := 0
		var first := true
		var previous := 0
		for dx in w:
			var x := x0 + dx
			if x < 0:
				run = 0
			elif x < size:
				var v: int = height[y * size + x]
				if first:
					first = false
					run += 1
					previous = v
				elif previous == v:
					run += 1
					if rw <= run:
						_a[dx * 70 + dy] = previous
						_b[dx * 70 + dy] += 1
				else:
					run = 1
					previous = v
			else:
				run = 0
	for dy in h:
		var y := y0 + dy
		if y < 0 or y >= size: continue
		var run := 0
		for dx in w:
			var x := x0 + dx
			if x < 0 or x >= size:
				run = 0
				continue
			var m: int = material[y * size + x]
			if m == 3 or m == 5 or m == 6 or m == 7 or m == 9:
				run = 0
				continue
			run += 1
			if rw <= run: _b[dx * 70 + dy] += 2
	for dy in h:
		var y := y0 + dy
		if y < 0 or y >= size: continue
		var run := 0
		for dx in w:
			var x := x0 + dx
			if x < 0 or x >= size:
				run = 0
				continue
			var i := y * size + x
			if permission[i] == 0 or occupied[i] != 0 or material[i] == 9:   # 0x42c8e0's two tests
				run = 0
				continue
			run += 1
			if rw <= run: _b[dx * 70 + dy] += 4
	var centre := Vector2i(x0 + (w >> 1), y0 + (h >> 1))
	var found := Vector2i(-1, -1)
	var best := -1
	for dx in w:
		var run := 0
		var level := 0
		for dy in h:
			var at := dx * 70 + dy
			if _b[at] != 7:
				run = 0
				continue
			if run == 0:
				level = _a[at]
			elif _a[at] != level:
				run = 0
				level = _a[at]
			run += 1
			if rh <= run:
				_b[at] = 5
				var cx := ((rw - 1) >> 1) - rw + dx + 1 + x0
				var cy := ((rh - 1) >> 1) - rh + dy + 1 + y0
				var metric := maxi(absi(cy - hint.y), absi(cx - hint.x)) + maxi(absi(cy - centre.y), absi(cx - centre.x))
				if found.x == -1 or metric < best:
					found = Vector2i(cx, cy)
					best = metric
	return found

func _phase_begin(name: String):
	_phase = {"rng_in": rng.state(), "searches": [], "places": []}
	log.phases[name] = _phase

func _try(code: String, x0: int, y0: int, w: int, h: int, hint: Vector2i) -> Vector2i:
	var r := _search(code, x0, y0, w, h, hint)
	_phase.searches.append([code, x0, y0, w, h, hint.x, hint.y, r.x, r.y])
	return r

## 0x418700: the record the map loader's BLDH gives (code, owner, cell), and the reservation. `start_side`: flag 1, the
## side's start-of-game bonuses (0x749c64, 0x4a50f0's race swap is the same code here).
func _build(buildings: Array, code: String, owner: int, cell: Vector2i, flag: int):
	_phase.places.append([code, owner, cell.x, cell.y, flag])
	var record := {"code": code, "owner": owner, "cell": [cell.x, cell.y], "cell_position": [cell.x + 0.5, cell.y + 0.5],
		"world_position": [cell.x * 32 + 16, cell.y * 24 + 12], "start_side": flag != 0}
	if MINE_CODES.has(code):               # 0x418700's switch by table index; level, rate and stock as in BLDH records
		var digit := int(code.right(1))
		record.level = digit + 1
		record.resource = {"C": "Crystal", "G": "Gold", "M": "Metal", "S": "Stone"}[code.substr(2, 1)]
		record.rate = [1, 2, 4][digit]
		record.stock = [3000, 8000, 15000][digit]
	buildings.append(record)
	_reserve(cell.x - 6, cell.y, 12, 8)

func _towards_centre(value: int) -> int:
	return -1 if (size >> 1) <= value else 1

func _clamp_cell(value: int) -> int:
	return mini(maxi(value, 6), size - 6)

# ------------------------------------------------------------------------------------------------- the phases
## 0x4183b0. The radius counter k runs on across the side's three towers: seven tries in all.
func _towers(sides: Array, starts: Dictionary, buildings: Array, victory: int):
	_phase_begin("towers")
	if victory == VICTORY_NO_TOWERS: return
	for side in sides:
		var slot: int = side.slot
		var start: Vector2i = starts[slot]
		var code: String = TOWER_CODES[int(side.race)]
		var k := 0
		for tower in 3:
			var going := k < 7
			k += 1
			while going:
				rng.roll(1, 2, 0)
				rng.roll(1, 2, 0)
				var a := rng.roll(1, k + 8, 0)
				var b := rng.roll(1, 3, 1)
				var x := _clamp_cell((a * (tower + 1) + b) * _towards_centre(start.x) + start.x)
				a = rng.roll(1, k + 8, 0)
				b = rng.roll(1, 3, 1)
				var y := _clamp_cell((a * (tower + 1) + b) * _towards_centre(start.y) + start.y)
				var r := _try(code, x - 12, y - 12, 24, 24, Vector2i(x, y))
				if r.x >= 0 and r.y >= 0:
					_build(buildings, code, slot, r, 1)
					break
				going = k < 7
				k += 1

## 0x418df0. The count: (resources + 1) * min(sides, 5), half again (truncated) for Low, then * 0.5 / 0.7 / 1.0 / 1.2 by
## size, truncated: doubles under the x87's 53-bit precision (R5-6). The start mines: 16 tries per side in all, the
## search's footprint cycling from a random entry, the mine built by the running type (crystal, gold, metal, stone).
## The spread: rook-style over a grid of `gap` cells; the search's footprint is entry `type + 2` of MINE_CODES (Read).
func _mines(sides: Array, starts: Dictionary, resources: int, buildings: Array):
	_phase_begin("mines")
	var n: int = (resources + 1) * mini(sides.size(), 5)
	if resources == 0: n += n / 2
	var factor: float = {1: 0.5, 2: 0.7, 3: 1.0, 4: 1.2}[size >> 6]
	n = int(n * factor)
	if n == 0: return
	for side in sides:
		var start: Vector2i = starts[int(side.slot)]
		var footprint := rng.roll(1, 4, -1)
		var type := 0
		var tries := 0
		while type < 4:
			var allowed := tries < 16
			tries += 1
			if allowed:
				var sign_x := 1 if rng.roll(1, 2, 0) == 1 else -1
				var sign_y := 1 if rng.roll(1, 2, 0) == 1 else -1
				var ring := tries * 2 + 6
				var x := _clamp_cell(rng.roll(2, ring, 0) * sign_x + start.x)
				var y := _clamp_cell(rng.roll(2, ring, 0) * sign_y + start.y)
				var r := _try(MINE_CODES[footprint], x - 12, y - 12, 24, 24, Vector2i(x, y))
				footprint = (footprint + 1) % 4
				if r.x < 0 or r.y < 0: continue
				_build(buildings, MINE_CODES[type], NEUTRAL, r, 0)
			type += 1
	var spread := [0, 0, 0, 0]              # the draw order is crystal, stone, gold, metal
	var k: int = n / 3
	if k > 0:
		spread[0] = rng.roll(1, k * 2 + 1, -1 - k)
		spread[3] = rng.roll(1, k * 2 + 1, -1 - k)
		spread[1] = rng.roll(1, k * 2 + 1, -1 - k)
		spread[2] = rng.roll(1, k * 2 + 1, -1 - k)
	for type in 4:
		var count: int = spread[type] + n
		if count <= 0: continue
		var gap: int = size / count
		var rows := PackedByteArray()
		var columns := PackedByteArray()
		rows.resize(maxi(count, 32))
		columns.resize(maxi(count, 32))
		rows.fill(0)
		columns.fill(0)
		for i in count:
			var row := _free_index(rows, count)
			if row < 0: break
			var column := _free_index(columns, count)
			if column < 0: break
			var ox := rng.roll(1, gap >> 1, -1)
			var oy := rng.roll(1, gap >> 1, -1)
			var x := mini(maxi(column * gap + (gap >> 2) + ox, 0), size - 1)
			var y := mini(maxi(row * gap + (gap >> 2) + oy, 0), size - 1)
			var r := _try(MINE_CODES[type + 2], x - 15, y - 15, 30, 30, Vector2i(x, y))
			if r.x != -1 and r.y != -1:
				var level: int = MINE_LEVELS[rng.roll(1, 5, -1)]
				_build(buildings, MINE_CODES[level * 4 + type], NEUTRAL, r, 0)
			columns[column] = 1
			rows[row] = 1

## Up to 1000 draws for an unused index; -1 stops the type (0x419300 region).
func _free_index(used: PackedByteArray, count: int) -> int:
	for attempt in 1000:
		var index := rng.roll(1, count, -1)
		if used[index] == 0: return index
	return -1

## 0x418ce0, only with Quests on: sides + roll(1, 3, -2), at least 1.
func _sites(sides: int, quests: bool, buildings: Array):
	_phase_begin("quest_sites")
	if not quests: return
	var count := maxi(sides + rng.roll(1, 3, -2), 1)
	for i in count:
		var x := rng.roll(1, size - 12, 6)
		var y := rng.roll(1, size - 12, 6)
		var code: String = SITE_CODES[i & 1]
		var r := _try(code, x - 20, y - 20, 40, 40, Vector2i(x, y))
		if r.x >= 0 and r.y >= 0: _build(buildings, code, NEUTRAL, r, 0)

## 0x418ae0(n): per site one type, up to 258 cells; the answer must lie on the map (x, y <= width).
func _utilities(count: int, buildings: Array):
	_phase_begin("utilities")
	for i in count:
		var code: String = UTILITY_CODES[rng.roll(1, 17, -1)]
		for attempt in 258:
			var x := rng.roll(2, size / 2, 0)
			var y := rng.roll(2, size / 2, 0)
			var r := _try(code, x - 20, y - 20, 40, 40, Vector2i(x, y))
			if r.x >= 0 and r.y >= 0 and r.x <= size and r.y <= size:
				_build(buildings, code, NEUTRAL, r, 0)
				break

## 0x583e4e .. 0x5840c4. Twenty-one tries per animal, but the 21st can only fail: past 20 a valid cell ends the tries
## without an animal. Nearest free cell 0x43b4c0 (navigation.gd free_cell_near), rejected when two or more of the cells
## at +-8 on the axes are water; 0 for a negative coordinate.
func _animals(grid, animals: int, terrain: int) -> Array:
	var phase := {"rng_in": rng.state(), "tries": [], "placed": []}
	log.phases.animals = phase
	var armies: Array = []
	if animals == 0: return armies
	var count := animals + rng.roll(1, 5, -3)
	match size:
		128: count = count * 3 / 2
		192: count = count * 2
		256: count = count * 5 / 2
	if count <= 0: return armies
	navigation = RandomMapCheck.CheckNavigation.new(grid)
	for i in occupied.size():              # the reservations so far
		if occupied[i] != 0 and grid.data.cells[i].object_indices.is_empty():
			navigation.building_cells[Vector2i(i % size, i / size)] = -1
	for i in count:
		for attempt in 21:
			var x := rng.roll(1, size - 4, 2)
			var y := rng.roll(1, size - 4, 2)
			var c: Vector2i = navigation.free_cell_near(Vector2i(x, y), null, 1, 0)
			var found := c.x != -1 and c.y != -1
			phase.tries.append([x, y, c.x, c.y, 1 if found else 0])
			if not found: continue
			var water := 0
			for at in [[c.x + 8, c.y], [c.x, c.y + 8], [c.x - 8, c.y], [c.x, c.y - 8]]:
				if _terrain_byte(at[0], at[1], 1) == 3: water += 1
			if water >= 2: continue
			if attempt < 20:
				var code: String = ANIMALS[terrain * 6 + rng.roll(1, 6, -1)]
				armies.append({"code": code, "owner": NEUTRAL, "cell": [c.x, c.y], "cell_position": [c.x + 0.5, c.y + 0.5],
					"world_position": [c.x * 32 + 16, c.y * 24 + 12]})
				phase.placed.append([code, c.x, c.y])
				_reserve(c.x, c.y, 2, 2)
			break
	navigation = null
	return armies
