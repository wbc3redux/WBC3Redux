extends SceneTree
## RM-6 / RM-7 (RANDOM_MAP_RESEARCH.md "RM-7"): a Random Map from the setup screen's data to a result. For every size and a
## sample of terrains, side counts and seats, the setup goes through RandomMapMatch.prepare into a fresh main scene: the
## placed starts, towers, mines, quest sites, shops, lairs and animals are in the match, the match generator continues from
## the placement, and the match plays to a result. Then the settings' "Random" resolution order (S5), the first map after a
## launch, the failure path, a save's map rebuilt from its inputs, and one AI match through the real loading screen.
## Never touches user://heroes (a fresh test directory) or the player's settings.

const MapData = preload("res://core/map_data.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")

const HERO := "test-random-knight"
## [size setting, terrain, the seat, the other slots, temples, animal level, resources, quests]
const CASES := [[0, 1, 0, [1], 2, 1, 1, true], [1, 3, 2, [0, 4], 1, 2, 2, true], [2, 7, 0, [1, 2, 3], 3, 3, 0, false],
	[3, 0, 5, [0, 1, 2, 3, 4], 4, 4, 2, true], [1, 8, 1, [3], 3, 2, 1, true], [0, 6, 0, [1, 2], 0, 0, 1, true], [1, 4, 0, [2], 4, 1, 2, true]]

var checks := 0
var failures := 0
var directory := ""
var store

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Random map match check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var tag := Crypto.new().generate_random_bytes(8).hex_encode()
	directory = "user://random-match-tests-" + tag
	store = Store.new(directory)
	check(store.save_profile(Profile.create(HERO, "Sir Wanderer")), "test profile saved")
	Settings.use_file("user://random-match-settings-%s.cfg" % tag)
	await resolution_checks()
	await launch_checks()
	await failure_checks()
	await restore_checks()
	for c in CASES: await match_case(c)
	await loading_screen_checks()
	await failure_screen_checks()
	MapData.select(MapData.DEFAULT)
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(Setup.saved_options_path())
	DirAccess.remove_absolute("user://random-match-settings-%s.cfg" % tag)
	if failures > 0:
		printerr("Random map match checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Random map match checks passed: %d" % checks)
	quit()

## A setup as the screen hands it over: the seat, computers on `others`, the settings; `seat` -1: a computer takes the local slot
## (spectator).
func setup_for(size: int, terrain: int, seat: int, others: Array, temples := 0, critters := 1, resources := 1, quests := true) -> Dictionary:
	var setup := Setup.random_setup()
	var o: Dictionary = setup.options
	o.map_size = size
	o.terrain = terrain
	o.temples = temples
	o.critters = critters
	o.resource_level = resources
	o.quests = quests
	if seat >= 0:
		setup.local = seat
		setup.players[seat].kind = Setup.HUMAN
		setup.players[seat].hero_id = HERO
	else:
		setup.local = int(others[0])
	for i in others: Setup.set_kind(setup, int(i), Setup.COMPUTER, 2)
	Setup.roll_random_races(setup, func(sides): return (int(setup.local) * 3 + 5) % sides + 1)
	return setup

# ------------------------------------------------------------------------------------------------ S5, the words
func resolution_checks():
	var options: Dictionary = Setup.random_setup().options
	options.map_size = 4
	options.terrain = 10
	options.temples = 5
	options.critters = 5
	options.resource_level = 3
	var rm = RandomMap.new(0x1234)
	var twin = RandomMap.new(0x1234)
	var expected := {"temples": twin.roll(1, 5, -1), "terrain": twin.roll(1, 10, -1), "map_size": twin.roll(1, 4, -1),
		"critters": twin.roll(1, 5, -1), "resources": twin.roll(1, 3, -1)}
	var got := RandomMapMatch.resolve_settings(options, rm)
	check(got == expected and rm.state == twin.state, "every Random resolves in S5's order: utilities, terrain, size, animals, resources (%s)" % got)
	check(int(options.map_size) == 4 and int(options.terrain) == 10, "the options keep Random: what the saved settings hold")
	options.map_size = 1
	options.temples = 2
	var one = RandomMap.new(0x1234)
	var other = RandomMap.new(0x1234)
	var only: Dictionary = RandomMapMatch.resolve_settings(options, one)
	check(int(only.map_size) == 1 and int(only.temples) == 2 and int(only.terrain) == other.roll(1, 10, -1), "only the Random ones draw")
	options.terrain = 3
	options.critters = 2
	options.resource_level = 1
	var still = RandomMap.new(77)
	RandomMapMatch.resolve_settings(options, still)
	check(still.state == 77, "fixed settings draw nothing")
	var sides: Array = Setup.random_sides(setup_for(0, 0, 3, [1, 5]))
	check(sides.map(func(s): return int(s.slot)) == [1, 3, 5] and sides.all(func(s): return int(s.race) >= 0 and int(s.race) <= 15), "sides in slot order, Random races rolled")

# ------------------------------------------------------------------------------------------------ A2, R5-10
## The original's prediction (A2): the first random map after a launch, with fixed settings, is always the same: the terrain,
## the features and (B1, same generator) the starts. The clock word changes only what the game generator places.
func launch_checks():
	RandomMapMatch.reset_session()
	var first_setup := setup_for(1, 1, 0, [1], 0, 1, 1)
	var first := RandomMapMatch.prepare(first_setup)
	check(bool(first.ok), "the first map")
	var clock_word: int = int(first.spec.rng[0])
	check(clock_word != RandomMapMatch.FIRST_WORD and int(first.spec.rng[1]) == RandomMapMatch.SECOND_WORD and int(first.spec.lcg) == 0, "first map: seed-0 layout, clock word, the image's second word (R5-10)")
	var layout_words: Array = first.layout.goms
	var second := RandomMapMatch.prepare(setup_for(1, 1, 0, [1], 0, 1, 1))
	check(int(second.spec.rng[0]) == RandomMapMatch.FIRST_WORD and int(second.spec.rng[1]) == int(first.spec.rng_after[1]), "later maps: the constant word, the second word runs on")
	check(int(second.spec.lcg) == int(first.placed.lcg_after) and second.layout.goms != layout_words, "the 16-bit generator runs on: a second map differs (A2)")
	RandomMapMatch.reset_session()
	var again := RandomMapMatch.prepare(setup_for(1, 1, 0, [1], 0, 1, 1))
	check(again.layout.goms == layout_words and again.placed.maph == first.placed.maph, "after a new launch the same terrain")
	check(again.placed.features == first.placed.features, "the same trees")
	check(again.placed.starts == first.placed.starts, "the same starts")
	check(first_setup.players[0].start == Vector2i(int(first.placed.starts[0].cell[0]), int(first.placed.starts[0].cell[1])) and int(first_setup.map_width) == 128, "the setup holds the starts and the size")
	check(first_setup.random_map == first.spec and String(first_setup.map) == "Random Map (Plains)", "the setup holds the map's inputs")
	RandomMapMatch.reset_session()

# ------------------------------------------------------------------------------------------------ ok = false
func failure_checks():
	var rm = RandomMap.new(5)
	var refused := func(_layout): return false
	var result := RandomMapMatch.prepare(setup_for(0, 1, 0, [1]), rm, 2, refused)
	check(not bool(result.ok) and String(result.error) == RandomMapMatch.FAILED, "layouts that never pass end in a message, not a hang")
	check(rm.state != 5, "the generator has moved on")
	var bad := RandomMapMatch.restore({})
	check(not bool(bad.ok) and String(bad.error).contains("damaged"), "a save without the map's inputs is refused")
	RandomMapMatch.reset_session()

# ------------------------------------------------------------------------------------------------ a save's map
func restore_checks():
	var setup := setup_for(0, 2, 0, [1, 2], 3, 2, 2)
	var made := RandomMapMatch.prepare(setup)
	check(bool(made.ok), "a map to save")
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(made.spec))
	var again := RandomMapMatch.restore(through_json)
	check(bool(again.ok) and again.placed.maph == made.placed.maph, "the same tiles from the inputs (through JSON)")
	check(again.placed.features == made.placed.features and again.placed.buildings == made.placed.buildings and again.placed.armies == made.placed.armies, "the same features, buildings and animals")
	check(again.placed.rng_after == made.placed.rng_after, "the same game words after the placement")
	check(RandomMapMatch.identity(through_json) == RandomMapMatch.identity(made.spec), "the identity survives JSON")
	var broken: Dictionary = through_json.duplicate(true)
	broken.size = 999
	check(not bool(RandomMapMatch.restore(broken).ok), "a spec outside the settings' ranges is refused")
	var bundle_a: Dictionary = made.bundle
	var bundle_b: Dictionary = again.bundle
	check(var_to_bytes(bundle_a.map) == var_to_bytes(bundle_b.map) and var_to_bytes(bundle_a.objects.placements) == var_to_bytes(bundle_b.objects.placements), "the same manifest and placements")
	check(var_to_bytes(bundle_a.collision.objects) == var_to_bytes(bundle_b.collision.objects), "the same collision objects")
	var other := RandomMapMatch.prepare(setup_for(0, 2, 0, [1, 2], 3, 2, 2))
	check(RandomMapMatch.identity(other.spec) != RandomMapMatch.identity(made.spec), "another map has another identity")
	RandomMapMatch.reset_session()

# ------------------------------------------------------------------------------------------------ the match
func match_case(c: Array):
	var others: Array = c[3]
	var seat: int = c[2]
	var setup := setup_for(c[0], c[1], seat, others, c[4], c[5], c[6], c[7])
	var made := RandomMapMatch.prepare(setup)
	var label := "%s %d, seat %d + %d" % [made.layout.get("terrain", -1) if made.ok else -1, int(made.spec.size) if made.ok else 0, seat, others.size()]
	check(bool(made.ok), "%s: generated" % label)
	if not bool(made.ok): return
	MapData.select_generated(made.bundle)
	var placed: Dictionary = made.placed
	var count := func(prefixes: Array): return placed.buildings.filter(func(b): return prefixes.any(func(p): return String(b.code).begins_with(p))).size()
	var size := int(made.spec.size)
	check(MapData.size_cells() == Vector2i(size, size) and MapData.info().name == "Random", "%s: the bundle is current" % label)
	check(MapData.map().starts.size() == others.size() + 1 and MapData.info().terrain_ambient.name == RandomMapMatch.Bundle.AMBIENCE[int(c[1])], "%s: starts, ambience (S7)" % label)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.start_skirmish(setup, HERO, store, "random-match-%d-%d" % [int(c[0]), int(c[1])]), "%s: the match starts" % label)
	check(scene.local_player == seat and int(scene.skirmish.resolved.scenario_events) == 0, "%s: the seat plays; no scenario events (0x41c7d0)" % label)
	check(scene.combat_seed == placed.rng_after, "%s: the match generator continues from the placement" % label)
	check(Setup.active_players(scene.skirmish.resolved).size() == others.size() + 1, "%s: every side active" % label)
	var heroes := {}
	for unit in scene.units:
		if scene.combat.fighters.has(unit.unit_id) and scene.combat.fighters[unit.unit_id].hero:
			heroes[unit.owner_id] = unit
	check(heroes.size() == others.size() + 1, "%s: a hero per side" % label)
	for start in placed.starts:
		var hero = heroes.get(int(start.side_index))
		var at := Vector2i(int(start.cell[0]), int(start.cell[1]))
		check(hero != null and (Vector2(hero.cell) - Vector2(at)).length() < 12.0, "%s: side %d's hero at its start %s" % [label, int(start.side_index), at])
	# The buildings as a scenario's (RM-3 "What RM-5 must know"), through the same code: towers, lairs, quest sites, shops, mines.
	var towers: Array = scene.production.buildings.values().filter(func(b): return String(b.original_type_id).begins_with("BWT"))
	check(towers.size() == count.call(["BWT"]) and towers.all(func(b): return int(b.owner) < 6), "%s: %d towers adopted, owned by sides" % [label, towers.size()])
	check(scene.mines.mines.size() == count.call(["BR"]), "%s: %d mines registered" % [label, scene.mines.mines.size()])
	var sites: int = count.call(["BMSH", "BZMA"])
	check(scene.encounters.givers.size() == sites and (bool(c[7]) or sites == 0), "%s: %d quest sites give quests" % [label, sites])
	# adopt_map_buildings takes every lair code (S-3; 0x404b70).
	var lairs: int = count.call(["BLBM", "BLHN", "BLGL", "BLGH", "BSBS", "BSAL"])
	check(scene.encounters.lairs.size() == lairs, "%s: %d lairs spawn" % [label, lairs])
	var neutral: int = scene.units.filter(func(u): return u.owner_id == 6).size()
	check(neutral == placed.armies.size(), "%s: %d animals (%d placed)" % [label, neutral, placed.armies.size()])
	scene.advance_seconds(3.0)
	var shops: int = count.call(["BSFG"])
	check(scene.encounters.shops.size() == shops, "%s: %d shops stocked through S-2's adoption" % [label, shops])
	print("%s: %d buildings (%d towers, %d mines, %d sites, %d lairs, %d shops), %d animals" % [label, placed.buildings.size(), towers.size(), scene.mines.mines.size(), sites, lairs, shops, neutral])
	# Plays to a result: the computers go out as in tests/test_maps.gd, the hero's side wins.
	var m = scene.skirmish
	for p in others:
		scene._on_side_cleanup(int(p))
		for unit in scene.units:
			if unit.owner_id == int(p) and not unit.removed and scene.combat.fighters.has(unit.unit_id):
				scene.combat.apply_damage("unit", unit.unit_id, 100000, -1)
	scene.advance_seconds(34.0)
	if not m.over: print("%s: still counting after the cleanup: %s" % [label, still_counting(scene, others)])
	check(m.over and bool(m.outcome.won), "%s: the human wins (%s)" % [label, m.outcome])
	check(scene.results_data().players.size() == others.size() + 1, "%s: the results list every side" % label)
	scene.end_skirmish()
	root.remove_child(scene)
	scene.free()
	await process_frame

## What still counts for the computers under Standard Victory (skirmish_match.gd counts_for), for a failure's message.
func still_counting(scene, others: Array) -> Array:
	var m = scene.skirmish
	var out := []
	for p in others:
		for f in scene.combat.fighters.values():
			if int(f.get("list", f.owner)) == int(p) and not f.removed and (f.hero or int(f.hp) >= 1):
				out.append("side %d unit %s hp %d state %s eliminated %s" % [int(p), f.type_id, int(f.hp), f.state, m.eliminated[int(p)]])
		for b in scene.production.buildings.values():
			if int(b.owner) == int(p):
				out.append("side %d building %s hp %d constructing %s counts %s" % [int(p), b.original_type_id, int(b.hit_points), b.constructing, m.stop_defeat.get(b.original_type_id, [])])
	return out

# ------------------------------------------------------------------------------------------------ the real start path
## Okay's hand-over: the loading screen makes the map on its thread, main.tscn starts from Setup.pending. An AI match: no hero.
func loading_screen_checks():
	RandomMapMatch.reset_session()
	var setup := setup_for(0, 7, -1, [0, 3], 1, 1, 1)
	setup.options.game_speed = 2
	Setup.pending = {"setup": setup, "hero_id": ""}
	change_scene_to_file("res://menus/loading_screen.tscn")
	var waited := 0
	while waited < 6000 and not (current_scene != null and current_scene.has_method("start_skirmish") and current_scene.skirmish != null):
		await process_frame
		waited += 1
	var scene = current_scene
	check(scene != null and scene.has_method("start_skirmish") and scene.skirmish != null, "the loading screen reaches the match (%d frames)" % waited)
	if scene == null or not scene.has_method("start_skirmish"): return
	check(MapData.is_generated() and MapData.size_cells() == Vector2i(64, 64) and Setup.pending.is_empty(), "the generated map is current, the hand-over taken")
	check(scene.normal_play and scene.units.filter(func(u): return u.owner_id < 6).size() >= 2, "normal play with both heroes")
	scene.advance_seconds(5.0)
	check(not scene.skirmish.over, "the match runs")
	scene.end_skirmish()
	unload_current_scene()
	await process_frame
	await process_frame

## `ok = false` at the loading screen: back to the setup screen, which says why.
func failure_screen_checks():
	Setup.pending = {"setup": setup_for(0, 1, 0, [1]), "hero_id": HERO}
	change_scene_to_file("res://menus/loading_screen.tscn")
	await process_frame
	await process_frame
	var screen = current_scene
	check(screen != null and screen.random_map_due(), "a Random Map's setup is due for generation")
	if screen == null: return
	screen.requested = false
	screen.loaded_scene = ResourceLoader.load_threaded_get(screen.TARGET)   # the screen's own load, taken over
	screen.worker = Thread.new()
	screen.worker.start(func(): pass)
	screen.made = {"ok": false, "error": RandomMapMatch.FAILED}
	var waited := 0
	while waited < 600 and current_scene == screen:
		await process_frame
		waited += 1
	check(Setup.pending.is_empty() and current_scene != null and current_scene.has_method("select_random_map"), "the setup screen comes back")
	if current_scene != null and current_scene.has_method("select_random_map"):
		check(String(current_scene.help[0]) == RandomMapMatch.FAILED and Setup.start_error == "", "it shows why")
	unload_current_scene()
	await process_frame
