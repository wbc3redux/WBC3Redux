extends RefCounted
## RM-3 (RANDOM_MAP_RESEARCH.md "RM-3"): a generated Random Map as a playable map in memory. `generate` runs the layout with
## its connectivity check (random_map.gd, random_map_check.gd; retries stay inside that one call, the MAPH grid carries over
## between attempts) and the placement (random_map_place.gd, RM-5); `assemble` builds the five dictionaries map_data.gd
## otherwise reads from assets/maps/<slug>/, from the placement's result (its tiles and features changed):
## * "terrain": one draw per in-map MAPH record, as import_assets.terrain_layout builds terrain.json;
## * "collision": random_map_grid.gd's grid of the final tiles and surviving features, with the buildings' real footprints
##   (RM-7; the 12 x 8 reservations of the placement are not in it), collision_data.gd's format;
## * "map": the scenario manifest: starts (side records), buildings (BLDH-shaped) and armies (the animals);
## * "objects": a placement per feature and building, feature presentations from assets/feature_presentations.json, building
##   ones from art.json as map_object.gd's retype builds them (no imported map holds BWTK, BWTF, BWTV, BSFG, BSBS, BLGH);
## * "info": name "Random", size, players, materials, the ambience S7 reads for the terrain type.
## MapData.select_generated(bundle) makes it the current map; a fresh main scene then builds from it as from an imported map.
const Assets = preload("res://core/asset_store.gd")

const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapGrid = preload("res://simulation/random_map_grid.gd")
const RandomMapCheck = preload("res://simulation/random_map_check.gd")
const RandomMapPlace = preload("res://simulation/random_map_place.gd")
const ArtData = preload("res://core/art_data.gd")

static var PRESENTATIONS: String = Assets.path("feature_presentations.json")
## S7 (0x4de788, Read): Grasslands, Plains, Highlands, Jungle -> Plains; Desert, Outlands -> Desert; Snow -> Arctic. Lava,
## Caverns and Wetlands set nothing (the value the original keeps is Open): Plains here.
const AMBIENCE := ["Plains", "Plains", "Plains", "Desert", "Plains", "Desert", "Plains", "Arctic", "Plains", "Plains"]
const AMBIENCE_KIND := {"Plains": 0, "Desert": 2, "Arctic": 3}
const DEFAULT_RACES := [0, 1, 2, 14, 3, 5]      # `generate` without a setup: Knight, Dwarf, Undead, Swarm, Barbarian, Orc
const DEFAULT_WORDS := [0x000200f1, 0xb78d0945]  # `generate` without a setup: the single-player pair
const BUILDING_RECORD := 0x98                   # BLDH bytes the importer keeps
const LANES := {"G": 0, "M": 1, "C": 2, "S": 3} # mines.gd: +0x68 / +0x70 per lane
const MINIMAP := 128                            # the strategic map's pixels (SM24 is 128 x 128 in every scenario)
const SIDE_RECORD := 0x2c                       # SIDH bytes skirmish_setup.gd and the importer keep
const SIDE_LEVEL := 2                           # side record AI value (+0x10)
const SIDE_RESOURCES := 2                       # side record resources (+0xc)

static var _presentations := {}

static func presentations() -> Dictionary:
	if _presentations.is_empty():
		var text := FileAccess.get_file_as_string(PRESENTATIONS)
		var parsed = JSON.parse_string(text) if text != "" else null
		_presentations = parsed.definitions if parsed is Dictionary else {}
	return _presentations

## The map for `terrain` (0..9) and `size` cells with `sides` sides of DEFAULT_RACES: {"ok", "layout", "placed", "bundle"}.
## `generator` is a random_map.gd object: keep it between maps, its 16-bit state runs on (A2). ok is false when generate or
## the placement gives up. The match start goes through random_map_match.gd, which adds the setup's settings.
static func generate(terrain: int, size: int, sides: int, generator = null, settings: Dictionary = {}) -> Dictionary:
	var rm = generator if generator != null else RandomMap.new()
	var layout: Dictionary = rm.generate(terrain, size, RandomMapCheck.new(rm.data).callable())
	if not bool(layout.ok): return {"ok": false, "layout": layout, "bundle": {}}
	var list: Array = []
	for i in sides: list.append({"slot": i, "race": DEFAULT_RACES[i]})
	var chosen := {"rng": DEFAULT_WORDS}
	chosen.merge(settings, true)
	var placed: Dictionary = RandomMapPlace.new(rm).place(layout, list, chosen)
	if not bool(placed.ok): return {"ok": false, "layout": layout, "bundle": {}}
	return {"ok": true, "layout": layout, "placed": placed, "bundle": assemble(layout, placed, list, rm.data)}

## layout: random_map.gd's generate(); placed: random_map_place.gd's place() on it; sides: [{slot, race}].
static func assemble(layout: Dictionary, placed: Dictionary, sides: Array, data: Dictionary) -> Dictionary:
	var size := int(layout.size)
	var terrain := int(layout.terrain)
	var name: String = String(data.terrain_types[terrain].name)
	var grid = placed.grid
	var draws := terrain_draws(placed.maph, size, data)
	var features: Array = placed.features
	var records: Array = []
	var placements: Array = []
	var definitions := {}
	var known := presentations()
	for i in features.size():
		var f: Array = features[i]
		var code := String(f[0])
		var record := {"code": code, "kind": "features", "source_offset": i, "world_position": [int(f[4]), int(f[5])], "raw_hex": ""}
		records.append(record)
		placements.append(record)
		definitions[code] = known[code]
	var buildings := building_records(placed.buildings, grid, placements, definitions)
	var materials := {}
	for c in grid.data.cells: materials[int(c.raw[1])] = true
	var material_list: Array = materials.keys()
	material_list.sort()
	var ambience: String = AMBIENCE[terrain]
	var cols := (size + 9) / 10
	return {
		"terrain": {"schema": 1, "world_size": [size * 32, size * 24], "draws": draws, "evidence": "RM-3: import_assets.terrain_layout on the generated MAPH grid"},
		"collision": grid.data,
		"objects": {"schema": 1, "definitions": definitions, "placements": placements, "presentation": "standing slot 0"},
		"map": {"source": "Random Map (%s)" % name, "size_cells": [size, size], "players": sides.size(), "buildings": buildings, "armies": placed.armies,
			"features": records, "starts": side_records(placed.starts, sides),
			"terrain_records": draws.map(func(d): return {"index": d.index, "code": d.code})},
		"info": {"schema": 1, "name": "Random", "slug": "random", "source": "Random Map", "players": sides.size(), "size_cells": [size, size],
			"terrain_type": terrain, "terrain_name": name, "materials": material_list, "records": cols * cols,
			"terrain_ambient": {"name": ambience, "kind": AMBIENCE_KIND[ambience], "counts": [0, 0, 0, 0, 0, 0, 0, 0]}},
	}

## The placed buildings as a scenario's: the BLDH-shaped record mines.gd and MapData.building_owner read, the collision
## object with the real footprint (stamped at creation, R5-3) and a presentation. source_offset is the object index.
static func building_records(placed: Array, grid, placements: Array, definitions: Dictionary) -> Array:
	var footprints := RandomMapPlace.load_footprints()
	var out: Array = []
	for b in placed:
		var code: String = b.code
		var cell := Vector2i(int(b.cell[0]), int(b.cell[1]))
		var object: Dictionary = grid.add_building(code, cell, footprints[code], b.world_position)
		var raw := bldh_record(b)
		var record := {"code": code, "owner": int(b.owner), "cell_position": b.cell_position, "world_position": b.world_position,
			"source_offset": object.source_offset, "raw_hex": raw.hex_encode(), "name": String(ArtData.building(code).get("name", code)),
			"start_side": bool(b.get("start_side", false))}   # setup rows: 0x418700 flag 1 (encounters.adopt_map_buildings)
		if b.has("resource"):
			record.level = int(b.level)
			record.resource = b.resource
		out.append(record)
		placements.append({"code": code, "kind": "buildings", "source_offset": object.source_offset, "world_position": b.world_position, "raw_hex": record.raw_hex})
		if not definitions.has(code): definitions[code] = building_definition(code)
	return out

## A BLDH record's fields the rebuild reads (Data, Desert Sands: +0 code, +0x10 / +0x14 world position, +0x64 owner, +0x66
## level, +0x68 stock and +0x70 rate per lane; 0x418700's values for a mine, R5-11).
static func bldh_record(b: Dictionary) -> PackedByteArray:
	var raw := PackedByteArray()
	raw.resize(BUILDING_RECORD)
	var code: String = b.code
	for i in code.length(): raw[i] = code.unicode_at(i)
	raw.encode_s32(0x10, int(b.world_position[0]))
	raw.encode_s32(0x14, int(b.world_position[1]))
	raw.encode_s16(0x64, int(b.owner))
	if b.has("resource"):
		var lane: int = LANES[code.substr(2, 1)]
		raw.encode_s16(0x66, int(b.level))
		raw.encode_s16(0x68 + lane * 2, int(b.stock))
		raw.encode_s16(0x70 + lane * 2, int(b.rate))
	return raw

## The standing presentation of a building, the fields map_object.gd reads (its retype builds the same from art.json).
static func building_definition(code: String) -> Dictionary:
	var sheet: Dictionary = ArtData.building_sheet(code, 0)
	var info: Dictionary = ArtData.building(code)
	var interval := int(info.get("standing_interval_ms", 100))
	return {"texture": sheet.texture, "frame_size": sheet.frame_size, "pivot": sheet.pivot,
		"frames": int(sheet.get("sheet_columns", sheet.frame_count)), "interval_ms": interval, "first_interval_ms": interval,
		"depth_offset": int(info.get("depth_offset", 0))}

## One draw per in-map record, row-major (record i at ((i % cols) * 320, (i // cols) * 240)), cropped to the quadrant and
## clipped to the map. A record no piece wrote cannot occur inside the map (A12), so a missing code stops with a clear error.
static func terrain_draws(maph: PackedByteArray, size: int, data: Dictionary) -> Array:
	var cols := (size + 9) / 10
	var world := Vector2i(size * 32, size * 24)
	var draws: Array = []
	for row in cols:
		for col in cols:
			var at := (col * RandomMap.GRID + row) * RandomMap.RECORD
			var code := maph.slice(at, at + 4).get_string_from_ascii()
			var q: int = maph[at + 6]
			if not data.tiles.has(code):
				push_error("Random map: no tile %s at record (%d, %d)" % [code, col, row])
				continue
			var destination := Vector2i(col * 320, row * 240)
			draws.append({"index": row * cols + col, "code": code, "texture": "terrain/%s.png" % code,
				"source_rect": [(q & 1) * 320, (q >> 1) * 240, mini(320, world.x - destination.x), mini(240, world.y - destination.y)],
				"destination": [destination.x, destination.y]})
	return draws

## The side records in the SIDH layout skirmish_setup.gd reads, at the placed starts (B1).
static func side_records(starts: Array, sides: Array) -> Array:
	var races := {}
	for side in sides: races[int(side.slot)] = int(side.race)
	var out: Array = []
	for start in starts:
		var slot := int(start.side_index)
		var raw := PackedByteArray()
		raw.resize(SIDE_RECORD)
		raw.encode_s16(2, races[slot])
		raw.encode_s16(6, slot)
		raw.encode_s16(0xc, SIDE_RESOURCES)
		raw.encode_s16(0x10, SIDE_LEVEL)
		raw.encode_s32(0x14, int(start.cell[0]))
		raw.encode_s32(0x18, int(start.cell[1]))
		out.append({"cell": start.cell.duplicate(), "raw_hex": raw.hex_encode(), "side_index": slot})
	return out

## The strategic map of a generated map: the rebuild's own composition from the terrain bitmaps, MINIMAP square (the HUD
## scales it as a scenario's SM24). How the original draws it for a random map is not traced (Open). No trees, no shading.
## null without a renderer (headless).
static func minimap_image(draws: Array, size: int):
	var out := Image.create(MINIMAP, MINIMAP, false, Image.FORMAT_RGBA8)
	var scale := float(MINIMAP) / float(size * 32)
	var w := ceili(320.0 * scale)
	var h := ceili(240.0 * MINIMAP / float(size * 24))
	var cropped := {}
	for d in draws:
		var key := "%s/%d/%d" % [d.code, d.source_rect[0], d.source_rect[1]]
		if not cropped.has(key):
			var texture: Texture2D = Assets.texture(String(d.texture))
			var image: Image = texture.get_image() if texture != null else null
			if image == null or image.is_empty(): return null
			image.convert(Image.FORMAT_RGBA8)
			var part := image.get_region(Rect2i(int(d.source_rect[0]), int(d.source_rect[1]), 320, 240))
			part.resize(w, h, Image.INTERPOLATE_BILINEAR)
			cropped[key] = part
		var at := Vector2i(floori(d.destination[0] * scale), floori(d.destination[1] * MINIMAP / float(size * 24)))
		out.blit_rect(cropped[key], Rect2i(0, 0, w, h), at)
	return out
