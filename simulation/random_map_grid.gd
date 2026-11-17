extends RefCounted
## RM-4 (RANDOM_MAP_RESEARCH.md "RM-4"): the static collision grid of a generated map, in collision_data.gd's format
## (data.size_cells, data.cells, data.objects; width, height, inside, cell_data, is_passable, world_cell), so navigation.gd
## takes it unchanged: `Navigation.new(RandomMapGrid.new(layout))`. A GDScript twin of tools/collision.py's
## build_collision on the generated MAPH grid instead of an SCN manifest:
## * the TER decode and `sample_ter`: cell (x, y) reads MAPH record (x / 10, y / 10) of random_map.gd's grid (record
##   (x * 32 + y) * 16: code +0, quadrant +6) and the 4 bytes at 4 + (sx * 20 + sy) * 4 of that code's decrypted TER
##   record (random_map.json `tiles[code].ter`), sx = x % 10 + (q & 1) * 10, sy = y % 10 + (q >> 1) * 10: elevation,
##   material, permission, reserved. This is what 0x48f6b0 / 0x48f760 / 0x48f810 read (Read; Emulated equal, below);
## * the border and permission rules of 0x42de40 (Emulated, COLLISION_RESEARCH.md): interior cells nav material =
##   material, or 12 when the permission byte is 0; border cells keep 0; profile_passable[row] = cost row 0x603e68
##   [nav material] <= 100 (random_map.json `movement_cost_rows`). One addition (Emulated, G1 in RM-4): a border cell
##   whose TER material is 9 fails 0x42cc10 through the cell's +9 byte, which 0x42bf80 writes for every cell; there
##   `nav_material` is 9 (navigation.gd's material-9 test at the anchor) while the profile stays that of material 0
##   (no flags around it, as in the original). collision.py's SCN rule lacks this (note for map wave 4);
## * the feature footprints of the stamp 0x5302c0 (Emulated on Desert Sands): anchor cell = world pixels // (32, 24),
##   origin x - (w - 1) / 2, y; the cells whose mask bit is clear, unless the FEA bypass byte 58 is set
##   (random_map.json `feature_definitions`); only the first FEATURE_POOL features exist, 0x58bc70 having 1000 object
##   slots (Read).
## Exit gate (tests/test_random_map.gd): per cell 0x42cc10 extent 1 / extent 2, the occupied bit, the nav material array,
## the height and the extent-2 sector regions equal tests/random_map_check_fixtures.json (the original under Unicorn,
## tools/emulate_random_map.py --check).
##
## Open (A12): a MAPH record the pieces never write (code 0) would read tile-table entry 0 in the original, whose order is
## not known; no generated map has one inside the map (all 122 RM-2 cases, all RM-4 cases), so such a cell is material 0,
## permission 0 here.

const RandomMap = preload("res://simulation/random_map.gd")
const FEATURE_POOL := 1000

var data: Dictionary
var width: int
var height: int

## layout: random_map.gd's generate() result (size, maph, features); piece_data: random_map.json.
func _init(layout: Dictionary, piece_data: Dictionary = {}):
	var pieces: Dictionary = piece_data if not piece_data.is_empty() else RandomMap.load_data()
	width = int(layout.size)
	height = int(layout.size)
	data = build(layout.maph, layout.features, width, pieces)

func world_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 32.0), floori(point.y / 24.0))

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func cell_data(cell: Vector2i) -> Dictionary:
	return data.cells[cell.y * width + cell.x] if inside(cell) else {}

func is_passable(cell: Vector2i, profile: int = 0) -> bool:
	if not inside(cell):
		return false
	var c := cell_data(cell)
	return c.profile_passable[profile] and c.object_indices.is_empty() and int(c.nav_material) != 9

## RM-7: a placed building's real footprint, stamped as the map loader stamps a BLDH record: anchor cell x - (w - 1) / 2, y,
## the cells whose mask bit is clear (tools/collision.py decode_footprint), clipped to the map. The object joins data.objects
## in the imported format, so encounters.gd, mines.gd and navigation.gd read it as a scenario's building.
func add_building(code: String, cell: Vector2i, footprint: Dictionary, world_position: Array) -> Dictionary:
	var w: int = int(footprint.size[0])
	var h: int = int(footprint.size[1])
	var masks: Array = footprint.get("masks", [])
	var origin := Vector2i(cell.x - (w - 1) / 2, cell.y)
	var index: int = data.objects.size()
	var occupied: Array = []
	var clipped: Array = []
	for ly in h:
		for lx in w:
			if ly < masks.size() and int(masks[ly]) & (1 << lx): continue
			var c := origin + Vector2i(lx, ly)
			if inside(c):
				occupied.append([c.x, c.y])
				data.cells[c.y * width + c.x].object_indices.append(index)
			else:
				clipped.append([c.x, c.y])
	var object := {"index": index, "kind": "buildings", "code": code, "source_offset": index, "world_position": world_position,
		"anchor_cell": [cell.x, cell.y], "origin_cell": [origin.x, origin.y], "size": [w, h], "bypass": false,
		"occupied_cells": occupied, "clipped_cells": clipped}
	data.objects.append(object)
	return object

static func build(maph: PackedByteArray, features: Array, size: int, pieces: Dictionary) -> Dictionary:
	var costs: Array = pieces.movement_cost_rows
	var ter := {}
	var cells: Array = []
	cells.resize(size * size)
	for y in size:
		for x in size:
			var at := ((x / 10) * RandomMap.GRID + y / 10) * RandomMap.RECORD
			var raw := [0, 0, 0, 0]
			if maph.decode_u32(at) != 0:
				var code := maph.slice(at, at + 4).get_string_from_ascii()
				if not ter.has(code): ter[code] = Marshalls.base64_to_raw(pieces.tiles[code].ter)
				var record: PackedByteArray = ter[code]
				var q: int = maph[at + 6]
				var sx := x % 10 + (q & 1) * 10
				var sy := y % 10 + (q >> 1) * 10
				var offset := 4 + (sx * 20 + sy) * 4
				raw = [record[offset], record[offset + 1], record[offset + 2], record[offset + 3]]
			var material: int = raw[1]
			var interior := x > 0 and y > 0 and x < size - 1 and y < size - 1
			var nav: int = (material if raw[2] != 0 else 12) if interior else 0
			var passable := []
			for row in costs: passable.append(int(row[nav]) <= 100)
			# The +9 byte (0x42bf80 writes the TER material to every cell, the border too) fails 0x42cc10 at an anchor of
			# material 9; on the border the 0x97f6f4 array (hence the cost profile) stays 0, so the field carries the 9.
			if not interior and material == 9: nav = 9
			cells[y * size + x] = {"raw": raw, "nav_material": nav, "profile_passable": passable,
				"terrain_build_gate": raw[2] != 0 and not (material in [3, 5, 6, 7, 9]), "object_indices": []}
	var objects: Array = []
	var definitions: Dictionary = pieces.feature_definitions
	for f in features.slice(0, FEATURE_POOL):
		var d: Dictionary = definitions[f[0]]
		var w: int = int(d.size[0])
		var h: int = int(d.size[1])
		var anchor := Vector2i(floori(int(f[4]) / 32.0), floori(int(f[5]) / 24.0))
		var origin := Vector2i(anchor.x - (w - 1) / 2, anchor.y)
		var index := objects.size()
		var occupied: Array = []
		if not bool(d.bypass):
			for ly in h:
				for lx in w:
					if int(d.masks[ly]) & (1 << lx): continue
					var c := origin + Vector2i(lx, ly)
					occupied.append(c)
					if c.x >= 0 and c.y >= 0 and c.x < size and c.y < size:
						cells[c.y * size + c.x].object_indices.append(index)
		objects.append({"index": index, "kind": "features", "code": f[0], "source_offset": index, "world_position": [int(f[4]), int(f[5])],
			"anchor_cell": [anchor.x, anchor.y], "origin_cell": [origin.x, origin.y], "size": [w, h],
			"bypass": bool(d.bypass), "occupied_cells": occupied})
	return {"schema": 1, "size_cells": [size, size], "cell_pixels": [32, 24], "storage": "row-major y*width+x",
		"cells": cells, "objects": objects, "movement_cost_rows": costs, "source": "random map (simulation/random_map_grid.gd)"}
