extends SceneTree
## RM-3 (RANDOM_MAP_RESEARCH.md "RM-3"): a generated Random Map as a playable map. For every size and a sample of terrains
## (all ten at 128) the bundle of simulation/random_map_bundle.gd goes through MapData.select_generated into a fresh
## main scene: terrain draws equal the final MAPH grid (the placement changed it), the scene's collision and navigation are
## the grid's, every feature and building has a presentation and at most FEATURE_POOL features exist, a match starts with a
## hero per side at the placed starts and runs a few seconds. Then the imported maps are unchanged: Desert Sands selects and
## reads from its files.
## Never touches user://heroes (a fresh test directory).

const MapData = preload("res://core/map_data.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapGrid = preload("res://simulation/random_map_grid.gd")
const Bundle = preload("res://simulation/random_map_bundle.gd")

## [terrain, size, sides, generator state]: every size on Plains, then the other terrains at 128.
const CASES := [[1, 64, 2, 0], [1, 128, 3, 0], [1, 192, 4, 0], [1, 256, 6, 0],
	[0, 128, 2, 11], [2, 128, 3, 22], [3, 128, 4, 33], [4, 128, 2, 44], [5, 128, 3, 55], [6, 128, 4, 66], [7, 128, 2, 77],
	[8, 128, 3, 88], [9, 128, 4, 99]]
const PLAY_SECONDS := 3.0

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Random map play check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var directory := "user://random-map-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	check(store.save_profile(Profile.create("test-random-knight", "Sir Wanderer")), "test profile saved")
	var data: Dictionary = RandomMap.load_data()
	for c in CASES:
		await case_checks(c, data, store)
	await imported_map_checks(store)
	if failures > 0:
		printerr("Random map play checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Random map play checks passed: %d" % checks)
	quit()

func case_checks(c: Array, data: Dictionary, store):
	var terrain := int(c[0])
	var size := int(c[1])
	var sides := int(c[2])
	var name := "%s %d (%d sides)" % [data.terrain_types[terrain].name, size, sides]
	var started := Time.get_ticks_msec()
	var result: Dictionary = Bundle.generate(terrain, size, sides, RandomMap.new(int(c[3]), data))
	check(bool(result.ok), "%s: generate passes its check in one call (%d attempts)" % [name, int(result.layout.attempts)])
	if not bool(result.ok): return
	var layout: Dictionary = result.layout
	var worked: Dictionary = result.placed
	var bundle: Dictionary = result.bundle
	print("%s: %d attempts, %d features, %d buildings, built in %d ms" % [name, int(layout.attempts), worked.features.size(), worked.buildings.size(), Time.get_ticks_msec() - started])
	MapData.select_generated(bundle)
	check(MapData.current == MapData.GENERATED and MapData.name_of() == "Random", "%s: selected" % name)
	check(MapData.size_cells() == Vector2i(size, size), "%s: size through MapData" % name)
	check(MapData.depth_offset == maxi(0, size * 24 - MapData.DEPTH_ROOM), "%s: depth offset of the size" % name)
	check(MapData.map() != null and MapData.map().starts.size() == sides, "%s: %d sides" % [name, sides])
	var copy: Dictionary = MapData.map()
	copy.starts.clear()
	check(MapData.map().starts.size() == sides, "%s: the manifest is a fresh copy per call" % name)
	draw_checks(name, bundle, worked, size)
	started = Time.get_ticks_msec()
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	print("%s: scene ready in %d ms" % [name, Time.get_ticks_msec() - started])
	var placed: int = worked.features.size() + worked.buildings.size()
	check(worked.features.size() <= RandomMapGrid.FEATURE_POOL, "%s: at most %d features" % [name, RandomMapGrid.FEATURE_POOL])
	check(Vector2i(scene.collision.width, scene.collision.height) == Vector2i(size, size), "%s: collision grid" % name)
	check(scene.collision.data == bundle.collision, "%s: the scene's collision is the generated grid" % name)
	check(scene.terrain_layer.world_size == Vector2(size * 32, size * 24), "%s: terrain world size" % name)
	check(scene.terrain_layer.textures.size() > 0 and scene.terrain_layer.textures.values().all(func(t): return t != null), "%s: every tile bitmap loads" % name)
	check(scene.map_objects.size() == placed and bundle.objects.placements.size() == placed, "%s: %d presentations" % [name, placed])
	check(scene.map_objects.all(func(o): return o.sheet != null), "%s: every sheet loads" % name)
	var blocked := 0
	for y in size:
		for x in size:
			var cell := Vector2i(x, y)
			if scene.navigator.passable_extent(cell, 1) != scene.collision.is_passable(cell): blocked += 1
	check(blocked == 0, "%s: navigation reads the grid (%d cells differ)" % [name, blocked])
	var setup := Setup.defaults(MapData.map())
	check(int(setup.sides) == sides, "%s: side records" % name)
	var routes := true
	for p in range(1, sides):
		# A building's real footprint may cover the start cell: the hero stands at the nearest free cell (0x43b4c0), B1 / RM-7.
		var a: Vector2i = scene.navigator.free_cell_near(setup.players[0].start)
		var b: Vector2i = scene.navigator.free_cell_near(setup.players[p].start)
		var route: Dictionary = scene.navigator.route_cells(a, b)
		if not bool(route.ok) or (not route.segments.is_empty() and route.segments[-1][-1] != b): routes = false
		if not scene.navigator.passable_extent(b, 1): routes = false
	check(routes, "%s: the cells at the starts are open and the first side can reach them" % name)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-random-knight"
	for i in range(1, sides): Setup.set_kind(setup, i, Setup.COMPUTER, Setup.KEEP_LEVEL)
	started = Time.get_ticks_msec()
	check(scene.start_skirmish(setup, "test-random-knight", store, "random-%d-%d" % [terrain, size]), "%s: match starts" % name)
	print("%s: match started in %d ms" % [name, Time.get_ticks_msec() - started])
	var heroes := {}
	for unit in scene.units:
		if scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero: heroes[unit.owner_id] = unit
	check(heroes.size() == sides, "%s: a hero per side (%d)" % [name, heroes.size()])
	check(scene.visibility.width == size and scene.visibility.height == size, "%s: fog at the size" % name)
	started = Time.get_ticks_msec()
	scene.advance_seconds(PLAY_SECONDS)
	print("%s: %d s of play in %d ms" % [name, int(PLAY_SECONDS), Time.get_ticks_msec() - started])
	check(scene.skirmish != null, "%s: the match runs" % name)
	scene.end_skirmish()
	root.remove_child(scene)
	scene.free()
	await process_frame

## The draw list against the MAPH records: code, quadrant crop, destination, clipping on the far edge.
func draw_checks(name: String, bundle: Dictionary, worked: Dictionary, size: int):
	var cols := (size + 9) / 10
	var draws: Array = bundle.terrain.draws
	check(draws.size() == cols * cols, "%s: one draw per record (%d)" % [name, draws.size()])
	var wrong := 0
	var maph: PackedByteArray = worked.maph
	for d in draws:
		var col: int = int(d.index) % cols
		var row: int = int(d.index) / cols
		var at := (col * RandomMap.GRID + row) * RandomMap.RECORD
		var q: int = maph[at + 6]
		var same: bool = maph.slice(at, at + 4).get_string_from_ascii() == d.code and d.destination == [col * 320, row * 240] \
			and d.source_rect[0] == (q & 1) * 320 and d.source_rect[1] == (q >> 1) * 240 \
			and d.destination[0] + d.source_rect[2] <= size * 32 and d.destination[1] + d.source_rect[3] <= size * 24
		if not same: wrong += 1
	check(wrong == 0, "%s: %d draws differ from the MAPH grid" % [name, wrong])

## Selecting an imported map afterwards reads its files again; a generated map changes nothing for it.
func imported_map_checks(store):
	MapData.select(MapData.DEFAULT)
	check(not MapData.is_generated(), "Desert Sands selects again")
	check(MapData.depth_offset == 0 and MapData.map().starts.size() == 2 and MapData.objects().placements.size() == 66, "Desert Sands reads its own files")
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.collision_overlay.texture != null, "Desert Sands keeps its collision overlay")
	root.remove_child(scene)
	scene.free()
	await process_frame
