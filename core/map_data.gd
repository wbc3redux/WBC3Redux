extends RefCounted
## The chosen scenario's imported data (W1 of CONTENT_EXPANSION_PLAN.md). tools/import_assets.py writes every map in its
## MAPS list to assets/maps/<slug>/ (map.json, map_info.json, terrain.json, collision.json, map_objects.json,
## scenario_minimap.png, collision overlays) and the list to assets/maps/index.json. Every reader of the map goes through
## here instead of res://assets/map.json (which stays as Desert Sands' legacy copy for older tests and tools).
##
## `current` is chosen before main.tscn is instanced (the skirmish menu sets it with the map list); main.gd builds its
## collision, terrain, objects and fog from it at load, so a different map needs a fresh main scene.
## RM-3: `select_generated` makes a generated Random Map current (simulation/random_map_bundle.gd): the same dictionaries,
## held in memory under the slug GENERATED instead of read from files. It has no image files: main.gd hands the HUD a composed
## strategic map (RM-7), the collision overlay stays empty; `is_generated` tells their readers.
const Assets = preload("res://core/asset_store.gd")

const DEFAULT := "desert-sands"
static var ROOT: String = Assets.path("maps/")
const GENERATED := "random"
const GENERATED_FILES := {"map.json": "map", "map_info.json": "info", "terrain.json": "terrain",
	"map_objects.json": "objects", "collision.json": "collision"}

static var current := DEFAULT
static var _owners: Dictionary = {}      # slug -> {source_offset: owner} (BLDH +0x64)
static var generated: Dictionary = {}    # the generated map's bundle (random_map_bundle.gd)
## M-2: the original's draw order key is the world y (plus per-object biases), which reaches 6144 on a 256 map, but a Godot
## canvas item's z is limited to +-4096 (RenderingServer.CANVAS_ITEM_Z_MAX). On maps taller than DEPTH_ROOM pixels every
## world depth is shifted down by this offset (and the ground layers with it), so the order is unchanged and the fixed
## overlays above 3900 (dust, smoke, glow, fog) stay on top. 0 on 128 maps: Desert Sands and The Hill draw as before.
const DEPTH_ROOM := 3584
static var depth_offset := 0

static func select(slug: String) -> void:
	current = slug if slug != "" else DEFAULT
	depth_offset = maxi(0, int(world_size(current).y) - DEPTH_ROOM)

## RM-3: a generated map's bundle becomes the current map.
static func select_generated(bundle: Dictionary) -> void:
	generated = bundle
	_owners.erase(GENERATED)
	select(GENERATED)

static func is_generated(slug: String = "") -> bool:
	return (slug if slug != "" else current) == GENERATED

## The canvas z of a world depth key (a world y): MapData.depth_offset below it on tall maps.
static func depth(y) -> int:
	return int(y) - depth_offset

static func path(file: String, slug: String = "") -> String:
	return ROOT + (slug if slug != "" else current) + "/" + file

## An image of the map (scenario_minimap.png, collision overlays) through the asset store, null when missing.
static func texture(file: String, slug: String = "") -> Texture2D:
	return Assets.texture("maps/" + (slug if slug != "" else current) + "/" + file)

static func _json(file: String, slug: String) -> Dictionary:
	if is_generated(slug):
		var key: String = GENERATED_FILES[file]
		if not generated.has(key):
			push_error("No generated map selected (MapData.select_generated)")
			return {}
		# The manifest and the info are fresh copies, as from a file; the grid and the draws are large and only read.
		return generated[key].duplicate(true) if key == "map" or key == "info" else generated[key]
	var text := FileAccess.get_file_as_string(path(file, slug))
	if text == "":
		push_error("Map data missing: " + path(file, slug) + " (run launch.ps1 -ImportAssets)")
		return {}
	return JSON.parse_string(text)

## The scenario manifest (starts, buildings, armies, features, terrain records), a fresh copy per call.
static func map(slug: String = "") -> Dictionary:
	return _json("map.json", slug)

## Name, size, players, terrain ambience and materials of the map.
static func info(slug: String = "") -> Dictionary:
	return _json("map_info.json", slug)

## One draw per MAPH record (terrain_layer.gd).
static func terrain(slug: String = "") -> Dictionary:
	return _json("terrain.json", slug)

static func objects(slug: String = "") -> Dictionary:
	return _json("map_objects.json", slug)

static func collision(slug: String = "") -> Dictionary:
	return _json("collision.json", slug)

## Every imported map ([{slug, name, players, size_cells}], by name), for the skirmish menu.
static func index() -> Array:
	var text := FileAccess.get_file_as_string(ROOT + "index.json")
	if text == "": return [{"slug": DEFAULT, "name": "Desert Sands", "players": 2, "size_cells": [128, 128]}]
	return JSON.parse_string(text).maps

static func slug_of(name: String) -> String:
	for entry in index():
		if String(entry.name) == name: return String(entry.slug)
	return ""

static func name_of(slug: String = "") -> String:
	var s := slug if slug != "" else current
	if is_generated(s): return String(generated.get("info", {}).get("name", "Random"))
	for entry in index():
		if String(entry.slug) == s: return String(entry.name)
	return s

static func size_cells(slug: String = "") -> Vector2i:
	var size: Array = info(slug).get("size_cells", [128, 128])
	return Vector2i(int(size[0]), int(size[1]))

## The map in world pixels (32 x 24 per cell; 4096 x 3072 for a 128 map).
static func world_size(slug: String = "") -> Vector2:
	return Vector2(size_cells(slug) * Vector2i(32, 24))

## Owner word of a placed building (BLDH +0x64, read by 0x4910e0), by its SCN record offset; 6 (neutral) if unknown.
static func building_owner(source_offset: int, slug: String = "") -> int:
	var s := slug if slug != "" else current
	if not _owners.has(s):
		var owners := {}
		for r in map(s).get("buildings", []): owners[int(r.source_offset)] = int(r.get("owner", 6))
		_owners[s] = owners
	return int(_owners[s].get(source_offset, 6))
