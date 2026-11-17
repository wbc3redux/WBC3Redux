extends SceneTree
## W1 (CONTENT_EXPANSION_PLAN.md): the multi-map loader and map wave 1.
## 1. MapData: the imported list, Desert Sands' map data equal to the legacy top-level copy.
## 2. Terrain drawn from MAPH records: Desert Sands composes pixel-identical to the old baked assets/terrain.png and the
##    colour sampler agrees with it; The Hill has its own 169 draws.
## 3. The Hill smoke in the real scene: loaded from MapData.current, its four sides (Swarm, Fey, Dark Dwarf, Daemon) from
##    the side records, a match started with a human and three computer players: heroes at the four starts, mines,
##    towers swapped to their owners' races, features placed, routes between the starts on its grid, 20 s of play.
## 4. W2 (milestone M-1): the same match plays four sides to a result: fog maps for every side, slot colours 0..3, teams,
##    kill counters, sides eliminated one at a time (0x534340 cleanup), a computer group regroups when its target side is
##    out (0x4f6530), the human wins with a four-row results table; a second match on teams ends in an allied victory
##    while the ally still stands, with shared sight and no hostility between the allies.
## 5. Map wave 2 (milestone M-2): The Lion's Den (128, Undead / Swarm / Empire, materials 1 and 7) and Hills to Climb (the
##    first 256 map: 676 draws, 8192 x 6144): grids, terrain, objects, the material fixture (tests/material_fixtures.json,
##    0x42cc10 Emulated) against navigation for extents 1..3, sectors, fog and the view clamp at the map's size, routes
##    between the starts, and a human + computer match that plays to a result.
## 6. Map wave 3 (milestone M-3, water): Celestial Oasis, Next Door, Four Bridges, Bridges (128), Four Rivers and Valley of
##    the Dead (192) through the same checks, the cell check against tests/water_fixtures.json (0x42cc10 Emulated for
##    types 0, 2 and 3); Valley of the Dead's EFFH record imported as data; on Four Bridges an amphibious Naga (ALGX, type 3)
##    swims across the centre lake and a land unit ordered onto the water stops at the shore.
## 7. Map wave 3 part 2: Forest Lakes, Winter Wonderland (256) and Land of the Lost (192), six sides each, through the
##    same checks: a human and five computer players to a result.
## 8. Map wave 4, the remaining land maps: Circles, Dragon's Pyramid, Desert Crossing (256), Rumble in the Jungle and Lands
##    Divided (128), the cell check against tests/material_fixtures.json (0x42cc10 Emulated, extents 1..3).
## `-- --quick` (launch.ps1 -Quick): every map still loads and its grid, terrain, objects, cell check, sectors, sides, routes
## and match start are checked, but the maps of blocks 5-8 run 3 s of play instead of 20 s and are not played to a result;
## The Hill (blocks 3-4) still plays to a result. The full check (no -Quick) runs everything.
## Never touches user://heroes (a fresh test directory).

const MapData = preload("res://core/map_data.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const TerrainLayer = preload("res://visuals/terrain_layer.gd")
const ArtData = preload("res://core/art_data.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const Navigation = preload("res://battle/navigation.gd")

const WAVE3 := ["celestial-oasis", "next-door", "four-bridges", "bridges", "four-rivers", "valley-of-the-dead"]
const WAVE3_PART2 := ["forest-lakes", "winter-wonderland", "land-of-the-lost"]   # six sides each
const WAVE4 := ["circles", "dragons-pyramid", "desert-crossing", "rumble-in-the-jungle", "lands-divided"]   # the remaining land maps
const WAVE5 := ["cavern-wars", "dwarven-tunnels", "cavemen", "volcanic-pit"]   # caverns and lava, the EFFH map effects
var checks := 0
var quick := OS.get_cmdline_user_args().has("--quick")
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Map check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	loader_checks()
	terrain_checks()
	await hill_checks()
	await wave2_checks("the-lions-den")
	await wave2_checks("hills-to-climb")
	for slug in WAVE3: await wave2_checks(slug)
	for slug in WAVE3_PART2: await wave2_checks(slug)
	for slug in WAVE4: await wave2_checks(slug)
	for slug in WAVE5: await wave2_checks(slug)
	MapData.select(MapData.DEFAULT)
	if failures > 0:
		printerr("Map checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Map checks passed: %d" % checks)
	quit()

func loader_checks():
	var index: Array = MapData.index()
	check(index.map(func(e): return e.slug) == ["bridges", "cavemen", "cavern-wars", "celestial-oasis", "circles", "desert-crossing", "desert-sands", "dragons-pyramid", "dwarven-tunnels", "forest-lakes", "four-bridges", "four-rivers", "hills-to-climb", "land-of-the-lost", "lands-divided", "next-door", "rumble-in-the-jungle", "the-hill", "the-lions-den", "valley-of-the-dead", "volcanic-pit", "winter-wonderland"], "imported maps by name: %s" % [index.map(func(e): return e.slug)])
	check(WAVE4.map(func(slug): return [MapData.size_cells(slug).x, int(MapData.info(slug).players)]) == [[256, 4], [256, 6], [256, 5], [128, 3], [128, 4]],
		"wave 4: Circles, Dragon's Pyramid, Desert Crossing 256; Rumble in the Jungle, Lands Divided 128")
	check(WAVE4.all(func(slug): return not MapData.info(slug).materials.has(3.0)), "wave 4: land maps (no water)")
	check(WAVE5.map(func(slug): return [MapData.size_cells(slug).x, int(MapData.info(slug).players)]) == [[128, 4], [192, 3], [256, 6], [128, 5]],
		"wave 5: Cavern Wars 128, Dwarven Tunnels 192, Cavemen 256, Volcanic Pit 128")
	check(WAVE5.all(func(slug): return MapData.info(slug).materials.has(4.0) and MapData.info(slug).materials.has(5.0)), "wave 5: materials 4 and 5 on every cave map")
	check(WAVE5.map(func(slug): return MapData.map(slug).get("effects", []).size()) == [0, 0, 2, 10], "wave 5: EFFH records (Cavemen 2, Volcanic Pit 10)")
	check(WAVE3_PART2.map(func(slug): return [MapData.size_cells(slug).x, int(MapData.info(slug).players)]) == [[256, 6], [256, 6], [192, 6]],
		"wave 3 part 2: Forest Lakes and Winter Wonderland 256, Land of the Lost 192, six sides each")
	check(range(6).map(func(i): return MapData.size_cells(WAVE3[i]).x) == [128, 128, 128, 128, 192, 192], "wave 3: four 128 maps, two 192 maps")
	check(WAVE3.all(func(slug): return MapData.info(slug).materials.has(3.0)), "wave 3: every map has water (material 3)")
	var effects: Array = MapData.map("valley-of-the-dead").get("effects", [])
	check(effects.size() == 1 and String(effects[0].name) == "EvilBrew" and Vector2i(int(effects[0].world_position[0]), int(effects[0].world_position[1])) == Vector2i(5778, 2876),
		"Valley of the Dead: one EFFH record (EvilBrew at 5778, 2876) imported as data")
	check(not MapData.map("four-rivers").has("effects"), "Four Rivers has no EFFH record")
	check(MapData.current == "desert-sands", "Desert Sands by default")
	check(FileAccess.get_file_as_string(MapData.path("map.json")) == FileAccess.get_file_as_string("res://assets/map.json"), "Desert Sands' map.json equals the legacy copy")
	check(FileAccess.get_file_as_string(MapData.path("collision.json")) == FileAccess.get_file_as_string("res://assets/collision.json"), "Desert Sands' collision.json equals the legacy copy")
	check(MapData.slug_of("The Hill") == "the-hill" and MapData.name_of("the-hill") == "The Hill", "names and slugs")
	check(MapData.size_cells("the-hill") == Vector2i(128, 128) and MapData.world_size("the-hill") == Vector2(4096, 3072), "The Hill is 128 x 128 (4096 x 3072 px)")
	var info: Dictionary = MapData.info("the-hill")
	check(int(info.players) == 4 and info.materials.map(func(m): return int(m)) == [0, 1, 2, 8], "The Hill: 4 players, Desert Sands' materials 0/1/2/8")
	check(MapData.size_cells("hills-to-climb") == Vector2i(256, 256) and MapData.world_size("hills-to-climb") == Vector2(8192, 6144), "Hills to Climb is 256 x 256 (8192 x 6144 px)")
	var den: Dictionary = MapData.info("the-lions-den")
	check(int(den.players) == 3 and den.materials.map(func(m): return int(m)) == [1, 7], "The Lion's Den: 3 players, materials 1 and 7")
	var hills: Dictionary = MapData.info("hills-to-climb")
	check(int(hills.players) == 4 and hills.materials.map(func(m): return int(m)) == [1, 2, 7], "Hills to Climb: 4 players, materials 1, 2 and 7")
	check(String(info.terrain_ambient.name) == "Desert" and String(MapData.info().terrain_ambient.name) == "Desert", "terrain ambience per map")
	check(MapData.building_owner(int(MapData.map().buildings[0].source_offset)) == int(MapData.map().buildings[0].get("owner", 6)), "owner by record offset")

func terrain_checks():
	var layer := TerrainLayer.new()
	layer.setup("desert-sands")
	check(layer.layout.draws.size() == 169 and layer.world_size == Vector2(4096, 3072) and layer.columns == 13, "Desert Sands: 169 draws, 13 columns")
	var composed := layer.compose()
	var baked := Image.new()
	baked.load_png_from_buffer(FileAccess.get_file_as_bytes("res://assets/terrain.png"))
	baked.convert(Image.FORMAT_RGB8)
	check(composed.get_size() == baked.get_size() and composed.get_data() == baked.get_data(), "Desert Sands draws pixel-identical to the baked terrain.png")
	var same := true
	for p in [Vector2(0, 0), Vector2(4095, 3071), Vector2(3871, 2900), Vector2(2048, 1536), Vector2(319, 239), Vector2(320, 240)]:
		if layer.colour_at(p) != baked.get_pixelv(Vector2i(p)): same = false
	check(same, "the colour sampler reads the same pixels")
	var last: Dictionary = layer.layout.draws[168]
	check(last.source_rect[2] == 256 and last.source_rect[3] == 192 and Vector2(last.destination[0], last.destination[1]) == Vector2(3840, 2880), "the last record is clipped to the map (256 x 192)")
	layer.setup("the-hill")
	check(layer.layout.draws.size() == 169 and layer.textures.size() == 27, "The Hill: 169 draws from its 27 tile bitmaps")
	check(layer.textures.values().all(func(t): return t != null), "every tile texture loads")
	layer.setup("hills-to-climb")
	check(layer.layout.draws.size() == 676 and layer.columns == 26 and layer.world_size == Vector2(8192, 6144), "Hills to Climb: 676 draws, 26 columns")
	check(layer.textures.values().all(func(t): return t != null), "Hills to Climb: every tile texture loads")
	var corner: Dictionary = layer.layout.draws[675]
	check(corner.source_rect[2] == 192 and corner.source_rect[3] == 144 and Vector2(corner.destination[0], corner.destination[1]) == Vector2(8000, 6000), "the last 256-map record is clipped (192 x 144 at 8000, 6000)")
	check(int(layer.draw_at(Vector2(8191, 6143)).index) == 675 and layer.colour_at(Vector2(8191, 6143)) != Color.BLACK, "the far corner samples its record")
	layer.setup("the-lions-den")
	check(layer.layout.draws.size() == 169, "The Lion's Den: 169 draws")
	layer.free()

func hill_checks():
	MapData.select("the-hill")
	var directory := "user://map-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = MapData.map()
	check(scene.collision.width == 128 and scene.collision.height == 128, "collision grid from The Hill")
	check(scene.terrain_layer.layout.draws.size() == 169 and scene.terrain_layer.world_size == Vector2(4096, 3072), "terrain layer from The Hill")
	check(scene.map_objects.size() == 38 + 71, "109 presentations (38 buildings, 71 features)")
	check(scene.map_objects.filter(func(o): return not o.is_building).size() == 71, "every feature placed")
	var setup := Setup.defaults(map)
	check(int(setup.sides) == 4, "four sides from the side records")
	check(range(4).map(func(i): return int(setup.players[i].race)) == [14, 9, 10, 11], "map races Swarm, Fey, Dark Dwarf, Daemon")
	check(range(4).map(func(i): return setup.players[i].start) == [Vector2i(7, 8), Vector2i(116, 9), Vector2i(113, 112), Vector2i(19, 117)], "starts")
	# Routes on its grid: every start reaches every other.
	var routes := true
	for a in 4:
		for b in 4:
			if a == b: continue
			var from: Vector2i = scene.navigator.free_cell_near(setup.players[a].start)
			var to: Vector2i = scene.navigator.free_cell_near(setup.players[b].start)
			if not scene.navigator.route_cells(from, to).ok: routes = false
	check(routes, "routes between all four starts")
	var profile = Profile.create("test-hill-knight", "Sir Hillock")
	check(store.save_profile(profile), "copied test profile saved")
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-hill-knight"
	for i in range(1, 4): Setup.set_kind(setup, i, Setup.COMPUTER, Setup.KEEP_LEVEL)
	check(scene.start_skirmish(setup, "test-hill-knight", store, "hill-match-1"), "The Hill match starts")
	var heroes := {}
	for unit in scene.units:
		if scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero: heroes[unit.owner_id] = unit
	check(heroes.size() == 4, "four heroes")
	var near := true
	for p in heroes:
		if Vector2(heroes[p].cell).distance_to(Vector2(setup.players[p].start)) > 4.0: near = false
	check(near, "each hero at its side's start")
	check(scene.production.races == {0: 14, 1: 9, 2: 10, 3: 11}, "player races (0x708f96)")
	var mine_codes: int = map.buildings.filter(func(r): return r.has("resource")).size()
	check(mine_codes == 28 and scene.mines.mines.size() == 28, "all 28 mines registered (%d)" % scene.mines.mines.size())
	check(scene.mines.mines.values().filter(func(m): return int(m.level) == 1).size() == 5, "five level-1 mines (BRC0, BRG0)")
	var towers: Array = scene.production.buildings.values().filter(func(b): return String(b.original_type_id).begins_with("BWT"))
	check(towers.size() == 8, "eight map towers adopted (%d)" % towers.size())
	var by_race := {14: "BWTE", 9: "BWTF", 10: "BWTA", 11: "BWTV"}
	check(towers.all(func(b): return String(b.original_type_id) == by_race[int(scene.production.races[int(b.owner)])]), "towers swapped to their owners' race (0x4a50f0)")
	check(scene.combat.towers.size() == 8, "every tower shoots")
	scene.advance_seconds(20.0)
	check(scene.skirmish != null and not scene.skirmish.over, "20 s of four-player play")
	check(scene.units.filter(func(u): return not u.removed and u.owner_id < 4).size() >= 4, "units alive")
	check(scene.terrain_layer.colour_at(Vector2(100, 100)) != Color.BLACK, "terrain sampled")
	w2_free_for_all(scene, setup)
	w2_teams(scene, map, store)
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)

## 0x534340 as the match applies it to an eliminated side, used here to take a side out of the match at once.
func take_out(scene, p: int):
	scene._on_side_cleanup(p)
	for unit in scene.units:
		if unit.owner_id == p and not unit.removed and scene.combat.fighters.has(unit.unit_id): scene.combat.apply_damage("unit", unit.unit_id, 100000, -1)

## Long enough for the hero's corpse to go (combat.CORPSE_MS, 30.7 s: until then 0x51a1c0 still counts the hero) and
## one more Standard Victory pass (every 54 timer ticks, 2.7 s nominal).
func run_checks(scene, seconds: float = 34.0):
	scene.advance_seconds(seconds)

func w2_free_for_all(scene, setup: Dictionary):
	var m = scene.skirmish
	check(scene.fog_players() == [0, 1, 2, 3], "fog maps for all four sides (%s)" % [scene.fog_players()])
	var lit := true
	for p in 4:
		if not scene.visibility.explored.has(p) or not scene.visibility.is_explored(p, setup.players[p].start): lit = false
	check(lit, "each side has explored its own start")
	check(not scene.visibility.is_explored(0, setup.players[2].start), "side 0 has not seen side 2's start")
	check(range(4).map(func(p): return ArtData.player_colour(p)) == range(4).map(func(p): return int(m.slots[p].colour)), "slot colours 0..3 from the side records")
	check(range(4).all(func(p): return ArtData.ramp(ArtData.player_colour(p)).size() == 15), "a 15-step ramp per slot colour")
	check(scene.combat.teams == [0, 0, 0, 0, 0, 0, 0], "free for all: every side on team 0")
	check(range(4).all(func(p): return scene.combat.kills.has(p)), "kill counters for all four sides")
	var hostile := true
	for a in 4:
		for b in 4:
			if a != b and not CombatRules.hostile(scene.combat.teams, a, b): hostile = false
	check(hostile, "every pair of sides is hostile")
	var ai = scene.ai_manager.players[1]
	ai.choose_main_enemy()
	check(ai.main_enemy in [0, 2, 3], "side 1 has a main enemy (%d)" % ai.main_enemy)
	take_out(scene, 3)
	run_checks(scene)
	check(m.eliminated[3] and not m.over, "side 3 out, the match goes on")
	ai.choose_main_enemy()
	check(ai.main_enemy in [0, 2], "side 1's main enemy is a side still in the match (%d)" % ai.main_enemy)
	var member := -1
	for u in ai.my_units():
		if scene.combat.fighters.has(u.unit_id): member = u.unit_id
	var group := {"kind": 0, "members": [member], "launched": true, "target_player": 3, "target": {}, "hero": false}
	ai._plan(group)
	check(int(group.target_player) in [0, 2], "a group sent at side 3 picks a side still in the match (0x4f6530: %d)" % int(group.target_player))
	take_out(scene, 2)
	run_checks(scene)
	check(m.eliminated[2] and not m.over, "side 2 out")
	take_out(scene, 1)
	run_checks(scene)
	check(m.over and bool(m.outcome.won), "the human wins against the last computer (%s)" % [m.outcome])
	var data: Dictionary = scene.results_data()
	check(data.players.size() == 4 and data.players.map(func(r): return int(r.colour)) == range(4).map(func(p): return int(m.slots[p].colour)), "the results list four sides, the local player first")

func w2_teams(scene, map: Dictionary, store):
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-hill-knight"
	for i in range(1, 4): Setup.set_kind(setup, i, Setup.COMPUTER, Setup.KEEP_LEVEL)
	for i in 4: setup.players[i].team = [1, 1, 2, 2][i]
	check(scene.start_skirmish(setup, "test-hill-knight", store, "hill-match-teams"), "The Hill match on teams starts")
	var m = scene.skirmish
	check(scene.combat.teams.slice(0, 4) == [1, 1, 2, 2], "teams from the setup (%s)" % [scene.combat.teams])
	check(not CombatRules.hostile(scene.combat.teams, 0, 1) and CombatRules.hostile(scene.combat.teams, 0, 2) and not CombatRules.hostile(scene.combat.teams, 2, 3), "allies are not hostile, the other team is")
	check(scene.sharing_players(1) == [0, 1] and scene.sharing_players(2) == [2, 3], "allies share sight")
	scene.advance_seconds(2.0)
	check(scene.visibility.is_explored(0, setup.players[1].start), "side 0 sees its ally's start")
	var ai = scene.ai_manager.players[1]
	ai.choose_main_enemy()
	check(ai.main_enemy in [2, 3], "the ally's main enemy is on the other team (%d)" % ai.main_enemy)
	take_out(scene, 2)
	run_checks(scene)
	check(m.eliminated[2] and not m.over, "side 2 out, its ally plays on")
	take_out(scene, 3)
	run_checks(scene)
	check(m.over and bool(m.outcome.won) and not m.eliminated[1], "allied victory: the human wins with side 1 still standing (%s)" % [m.outcome])
	check(scene.results_data().players.size() == 4, "four rows in the results")

## Map wave 2 (milestone M-2): one map in the real scene, then a match with a human and a computer per other side record
## that is played to a result (the other sides taken out by the 0x534340 cleanup, as in the W2 checks).
func wave2_checks(slug: String):
	MapData.select(slug)
	var name := MapData.name_of(slug)
	var directory := "user://map-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var started := Time.get_ticks_msec()
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	print("%s: scene ready in %d ms" % [name, Time.get_ticks_msec() - started])
	var map: Dictionary = MapData.map()
	var size: Vector2i = MapData.size_cells(slug)
	check(Vector2i(scene.collision.width, scene.collision.height) == size, "%s: collision grid %s" % [name, size])
	check(scene.terrain_layer.world_size == Vector2(size * Vector2i(32, 24)), "%s: terrain layer world size" % name)
	check(scene.terrain_layer.layout.draws.size() == ((size.x + 9) / 10) * ((size.y + 9) / 10), "%s: one draw per MAPH record" % name)
	check(scene.map_objects.size() == map.buildings.size() + map.features.size(), "%s: %d presentations" % [name, scene.map_objects.size()])
	# 0x42cc10 (Emulated, tests/material_fixtures.json) against navigation on every cell, extents 1..3, before any stamp.
	var materials: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/material_fixtures.json")).maps
	var water: Dictionary = {} if materials.has(slug) else JSON.parse_string(FileAccess.get_file_as_string("res://tests/water_fixtures.json")).maps[slug]
	for extent in ([1, 2, 3] if materials.has(slug) else [1, 2]):
		var hex: String = materials[slug].blocked_type0[str(extent)] if materials.has(slug) else water.blocked["type0_extent%d" % extent].bitmap
		var bits: PackedByteArray = hex.hex_decode()   # bit i % 8 of byte i / 8 = cell i
		var wrong := 0
		for y in size.y:
			for x in size.x:
				var i := y * size.x + x
				if scene.navigator.passable_extent(Vector2i(x, y), extent) == bool((bits[i >> 3] >> (i & 7)) & 1): wrong += 1
		check(wrong == 0, "%s: 0x42cc10 extent %d on all %d cells (%d differ)" % [name, extent, size.x * size.y, wrong])
	# The other movement types by count (the fixture keeps counts for types 1..3): flyers fail only on material 9 (wave 5).
	# Full mode only: nine scans of every cell per map; tests/test_water.gd compares the bitmaps of types 1, 2 and 3.
	if materials.has(slug) and not quick:
		for mtype in [1, 2, 3]:
			for extent in [1, 2, 3]:
				var blocked := 0
				for y in size.y:
					for x in size.x:
						if not scene.navigator.passable_extent(Vector2i(x, y), extent, mtype): blocked += 1
				var want := int(materials[slug].blocked_counts["type%d_extent%d" % [mtype, extent]])
				check(blocked == want, "%s: 0x42cc10 type %d extent %d blocks %d cells (original %d)" % [name, mtype, extent, blocked, want])
	# Sector layer (0x509f30, 8 x 8 cells): the regions reach the last sector column and row of the map.
	var last := Vector2i.ZERO
	for r in scene.navigator.regions:
		last = Vector2i(maxi(last.x, int(r.sector.x)), maxi(last.y, int(r.sector.y)))
	check(last == size / 8 - Vector2i.ONE, "%s: sectors up to %s" % [name, last])
	var setup := Setup.defaults(map)
	var sides := int(setup.sides)
	check(sides == int(MapData.info(slug).players) and sides == map.starts.size(), "%s: %d sides from the side records" % [name, sides])
	var routes := true
	for a in sides:
		for b in sides:
			if a == b: continue
			var from: Vector2i = scene.navigator.free_cell_near(setup.players[a].start)
			var to: Vector2i = scene.navigator.free_cell_near(setup.players[b].start)
			if not scene.navigator.route_cells(from, to).ok: routes = false
	check(routes, "%s: routes between all starts" % name)
	var profile = Profile.create("test-wave2-knight", "Sir Wanderer")
	check(store.save_profile(profile), "copied test profile saved")
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "test-wave2-knight"
	for i in range(1, sides): Setup.set_kind(setup, i, Setup.COMPUTER, Setup.KEEP_LEVEL)
	started = Time.get_ticks_msec()
	check(scene.start_skirmish(setup, "test-wave2-knight", store, slug + "-match"), "%s: match starts" % name)
	print("%s: match started in %d ms" % [name, Time.get_ticks_msec() - started])
	var races := {}
	for i in sides: races[i] = int(setup.players[i].race)
	check(scene.production.races == races, "%s: player races %s" % [name, races])
	var heroes := {}
	for unit in scene.units:
		if scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero: heroes[unit.owner_id] = unit
	check(heroes.size() == sides, "%s: a hero per side (%d)" % [name, heroes.size()])
	var near := true
	for p in heroes:
		if Vector2(heroes[p].cell).distance_to(Vector2(setup.players[p].start)) > 4.0: near = false
	check(near, "%s: each hero at its side's start" % name)
	check(scene.mines.mines.size() == map.buildings.filter(func(r): return r.has("resource")).size(), "%s: every mine registered (%d)" % [name, scene.mines.mines.size()])
	# Fog and sight at the map's size; the view clamp (0x4907d0) reaches the far corner and no further.
	check(scene.visibility.width == size.x and scene.visibility.height == size.y, "%s: fog maps %s" % [name, size])
	scene.refresh_fog_overlay()
	check(Vector2i(scene.fog_overlay.texture.get_size()) == size, "%s: fog overlay %s" % [name, size])
	scene.set_view_top_left(Vector2(100000, 100000))
	var far: Vector2 = scene.view_top_left() + scene.view_world_size()
	check(far.distance_to(Vector2(size * Vector2i(32, 24)) - Vector2.ONE) < 0.01, "%s: the view stops at the far corner (%s)" % [name, far])
	scene.set_view_top_left(Vector2(-500, -500))
	check(scene.view_top_left().distance_to(Vector2.ZERO) < 0.01, "%s: the view stops at the near corner" % name)
	# The strategic map (0x4d64a0, Read: cell = width * pixel / 128 on both axes): game_hud.gd's panel is 128 pixels, so
	# minimap_cells_per_pixel() (collision width / MAP_RECT width) is 2 on a 256 map. (A GameHud is not instanced here: its
	# UI canvas needs the scene's normal play.)
	var panel: Rect2 = preload("res://hud/game_hud.gd").MAP_RECT
	check(panel.size == Vector2(128, 128) and is_equal_approx(float(scene.collision.width) / panel.size.x, size.x / 128.0), "%s: strategic map %.1f cells per pixel" % [name, size.x / 128.0])
	started = Time.get_ticks_msec()
	var play := 3.0 if quick else 20.0
	scene.advance_seconds(play)
	print("%s: %d s of play in %d ms" % [name, play, Time.get_ticks_msec() - started])
	check(scene.skirmish != null and not scene.skirmish.over, "%s: %d s of play" % [name, play])
	var lit := true
	for p in sides:
		if not scene.visibility.is_explored(p, setup.players[p].start): lit = false
	check(lit, "%s: each side has explored its own start" % name)
	# The fog overlay (main.gd refresh_fog_overlay, rebuilt from the bytes in M-2) shades every cell by the old per-cell rule.
	scene.refresh_fog_overlay()
	var shade_ok := true
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			var shade := 0.0
			if scene.visibility.shroud and not scene.visibility.is_explored(0, cell): shade = 1.0
			elif scene.visibility.fog and not scene.visibility.is_visible_now(0, cell): shade = 0.45
			var px: Color = scene.fog_image.get_pixel(x, y)
			if px.a8 != Color(0, 0, 0, shade).a8 or px.r8 != 0 or px.g8 != 0 or px.b8 != 0: shade_ok = false
	check(shade_ok, "%s: fog overlay pixels by the per-cell rule" % name)
	if slug == "four-bridges": water_walk(scene)
	var m = scene.skirmish
	for p in (range(sides - 1, 0, -1) if not quick else []):
		take_out(scene, p)
		run_checks(scene)
		# The last computer side out ends the match (Standard Victory) instead of being marked eliminated.
		check(m.eliminated[p] or (p == 1 and m.over), "%s: side %d out (left: %s)" % [name, p, leftovers(scene, p)])
		if p > 1: check(not m.over, "%s: the match goes on after side %d" % [name, p])
	if not quick:
		check(m.over and bool(m.outcome.won), "%s: the human wins (%s)" % [name, m.outcome])
		check(scene.results_data().players.size() == sides, "%s: %d rows in the results" % [name, sides])
	scene.end_skirmish()
	scene.free()
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)

## M-3 in the real scene: units with movement types 3 and 0 ordered from the west bank to the centre lake of Four Bridges.
## The amphibious Naga walks to the shore and swims (its route has land and water cells, every step passes its own cell
## check); the Swordsman's goal in the lake is retargeted to the nearest land cell (0x430b80) and it stops there.
func water_walk(scene):
	var naga = scene.add_unit("ALGX", scene.navigator.free_cell_near(Vector2i(50, 66), null, 1, 3), 0)
	var knight = scene.add_unit("AHKX", scene.navigator.free_cell_near(Vector2i(50, 69)), 0)
	check(naga.movement_type == 3 and knight.movement_type == 0, "Naga (ALGX) is amphibious, the Swordsman a ground unit")
	var lake := Vector2i(68, 66)
	check(scene.navigator.passable_extent(lake, 1, 2) and not scene.navigator.passable_extent(lake, 1, 0), "the goal is lake water")
	var visited := {}
	for unit in [naga, knight]: scene.issue_move(scene.navigator.center(lake), false, false, true, {}, [unit])   # as a right-click
	var steps_ok := true
	for i in 200:
		scene.advance_seconds(0.25)
		visited[naga.cell] = true
		if not scene.navigator.passable_extent(naga.cell, 1, 3) or not scene.navigator.passable_extent(knight.cell, 1, 0): steps_ok = false
		if naga.orders.is_empty() and knight.orders.is_empty(): break
	var swam := visited.keys().filter(func(c): return not scene.navigator.passable_extent(c, 1, 0)).size()
	check(naga.cell == lake, "the Naga reaches the lake cell (%s)" % naga.cell)
	check(swam > 0 and visited.keys().size() > swam, "the Naga walked land and swam water (%d water cells of %d)" % [swam, visited.size()])
	check(steps_ok, "every cell stood on passes the unit's own cell check")
	check(knight.orders.is_empty() and scene.navigator.passable_extent(knight.cell, 1, 0) and Navigation.chebyshev(knight.cell, lake) <= 8,
		"the Swordsman stops on land at the shore (%s)" % knight.cell)

## What still counts for a side (diagnostics for a side that does not drop out).
func leftovers(scene, p: int) -> Array:
	var out := []
	for u in scene.units:
		if u.owner_id == p and not u.removed: out.append("unit %d %s dying %s" % [u.unit_id, u.get("unit_type"), u.dying])
	for b in scene.production.buildings.values():
		if int(b.owner) == p: out.append("building %s" % b.original_type_id)
	return out
