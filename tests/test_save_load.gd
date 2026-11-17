extends SceneTree
## S-1 (SAVE_LOAD.md): in-match Save / Load.
## 1. Determinism: a match runs N seconds, is saved (through the file: atomic write, read, version check), runs M more
##    seconds; a fresh scene loads the save and runs the same M seconds; every module's state must be equal bit for bit
##    (the per-module blobs of save_game.gd). The save made right after the load must equal the save that was loaded.
##    Desert Sands Knights vs Knights; a four-side The Hill with the batch-1 races (Undead, Dwarves, Swarm) and hero
##    spells cast; Four Bridges (water: an amphibious Naga swimming at the save); a generated Random Map (RM-7: the load
##    rebuilds the map from the save's generation inputs).
## 2. The format: an unknown version, another format and a damaged file are refused with a message (never a crash); the
##    previous save is kept as .bak; nothing in a save is an object or a callable.
## 3. Normal play: the game menu's Save / Load rows, Alt+S (message [0304], then [0753]), Alt+L opens the load sheet, its
##    Load Game loads the save in a new scene (the map is the save's); autosave on its own schedule and at the end.
## Never touches user://heroes or user://saves (test directories, removed at the end).

const MapData = preload("res://core/map_data.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const Settings = preload("res://simulation/game_settings.gd")
const UnitAgentScript = preload("res://battle/unit_agent.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")

var checks := 0
var failures := 0
var directory := ""
var store
var save_dir := ""
var quick := OS.get_cmdline_user_args().has("--quick")

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Save/load check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var tag := Crypto.new().generate_random_bytes(6).hex_encode()
	directory = "user://save-tests-heroes-" + tag
	save_dir = "user://save-tests-saves-" + tag
	store = Store.new(directory)
	var profile = Profile.create("save-test-hero", "Sir Saveall")
	check(store.save_profile(profile), "test hero saved")
	Settings.use_file("user://save-tests-settings-%s.cfg" % tag)
	var only := ""                       # development: `-- --only=hill` runs one block
	for arg in OS.get_cmdline_user_args(): if arg.begins_with("--only="): only = arg.get_slice("=", 1)
	if only == "" or only == "desert": await desert_sands()
	if only == "" or only == "hill": await the_hill()
	if only == "" or only == "water": await four_bridges()
	if only == "" or only == "random": await random_map()
	if only == "" or only == "format": await format_checks()
	if only == "" or only == "options": await options_checks()
	if only == "" or only == "menu": await menu_checks()
	MapData.select(MapData.DEFAULT)
	for dir in [directory, save_dir]:
		for filename in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(filename))
		DirAccess.remove_absolute(dir)
	DirAccess.remove_absolute("user://save-tests-settings-%s.cfg" % tag)
	if failures > 0:
		printerr("Save/load checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Save/load checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ helpers
func new_scene(slug: String):
	MapData.select(slug)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	return scene

func drop_scene(scene):
	if scene == null or not is_instance_valid(scene): return
	scene.end_skirmish()
	root.remove_child(scene)
	scene.free()

func advance(scene, seconds: float):
	for i in roundi(seconds * 60.0):
		if scene.skirmish != null and scene.skirmish.over: return
		scene.simulation_step(1.0 / 60.0)

func modules(scene) -> Dictionary:
	return scene.save_document().modules

## The first differences between two decoded states (path: a / b), at most `limit`.
func differences(a, b, path: String, out: Array, limit: int = 6):
	if out.size() >= limit: return
	if typeof(a) != typeof(b):
		out.append("%s: %s / %s (types %s / %s)" % [path, str(a).left(80), str(b).left(80), type_string(typeof(a)), type_string(typeof(b))])
		return
	match typeof(a):
		TYPE_DICTIONARY:
			if a.is_typed() != b.is_typed() or a.get_typed_key_builtin() != b.get_typed_key_builtin() or a.get_typed_value_builtin() != b.get_typed_value_builtin():
				out.append("%s: dictionary typing differs" % path)
				return
			if a.keys() != b.keys():
				var only_a: Array = a.keys().filter(func(k): return not b.has(k))
				var only_b: Array = b.keys().filter(func(k): return not a.has(k))
				out.append("%s: keys differ (only first %s, only second %s%s)" % [path, str(only_a.slice(0, 5)), str(only_b.slice(0, 5)),
					", order" if only_a.is_empty() and only_b.is_empty() else ""])
				return
			for k in a: differences(a[k], b[k], "%s.%s" % [path, str(k)], out, limit)
		TYPE_ARRAY:
			if a.get_typed_builtin() != b.get_typed_builtin() or a.get_typed_class_name() != b.get_typed_class_name():
				out.append("%s: array typing %d / %d" % [path, a.get_typed_builtin(), b.get_typed_builtin()])
				return
			if a.size() != b.size():
				out.append("%s: sizes %d / %d" % [path, a.size(), b.size()])
				return
			for i in a.size(): differences(a[i], b[i], "%s[%d]" % [path, i], out, limit)
		_:
			if var_to_bytes(a) != var_to_bytes(b): out.append("%s: %s / %s" % [path, str(a).left(80), str(b).left(80)])

## Equal module blobs (bit for bit); the differing paths are printed when they are not.
func same_modules(a: Dictionary, b: Dictionary, label: String) -> bool:
	var ok := a.keys() == b.keys()
	var bad: Array = []
	for key in a:
		if not b.has(key) or String(a[key]) == String(b[key]): continue
		ok = false
		var diffs: Array = []
		differences(SaveGame.decode(String(a[key])), SaveGame.decode(String(b[key])), key, diffs)
		bad.append(key)
		for d in diffs: printerr("  %s: %s" % [label, d])
	check(ok, "%s: every module equal bit for bit (differ: %s)" % [label, str(bad)])
	return ok

func setup_on(slug: String, races: Array, levels: Array) -> Dictionary:
	var map: Dictionary = MapData.map(slug)
	var setup := Setup.defaults(map)
	for i in races.size():
		Setup.set_race(setup, i, int(races[i]))
		if i == 0:
			setup.players[0].kind = Setup.HUMAN
			setup.players[0].hero_id = "save-test-hero"
		else: Setup.set_kind(setup, i, Setup.COMPUTER, int(levels[i]))
	for i in range(races.size(), int(setup.sides)): setup.players[i].kind = Setup.CLOSED
	return setup

## The determinism run of one match: `prepare` runs once on the first scene before the save (orders, casts).
func determinism(label: String, slug: String, setup: Dictionary, before_s: float, after_s: float, prepare: Callable = Callable(),
		in_flight: bool = false) -> Dictionary:
	for arg in OS.get_cmdline_user_args():             # development: `-- --scale=3` runs longer matches
		if arg.begins_with("--scale="):
			before_s *= float(arg.get_slice("=", 1))
			after_s *= float(arg.get_slice("=", 1))
	var scene = await new_scene(slug)
	check(scene.start_skirmish(setup, "save-test-hero", store, "save-test-" + slug), "%s: the match starts" % label)
	advance(scene, before_s)
	if prepare.is_valid(): prepare.call(scene)
	advance(scene, 1.5)
	if OS.get_cmdline_user_args().has("--aliases"): report_aliases(scene, label)
	if in_flight:                         # the save is made with a missile in the air
		for i in 1800:
			if not scene.combat.missiles.is_empty(): break
			scene.simulation_step(1.0 / 60.0)
		check(not scene.combat.missiles.is_empty(), "%s: a missile is in flight at the save" % label)
	check(scene.can_save(), "%s: the match can be saved" % label)
	print("%s: at the save %d missiles in flight, %d swings, %d casts running" % [label, scene.combat.missiles.size(),
		scene.combat.fighters.values().filter(func(f): return f.get("swing") != null).size(),
		scene.combat.fighters.values().filter(func(f): return f.get("cast") != null).size()])
	var path: String = SaveGame.path_for("determinism-" + slug, save_dir)
	var error: String = scene.save_match(path)
	check(error == "" and SaveGame.errors.is_empty(), "%s: saved (%s %s)" % [label, error, str(SaveGame.errors.slice(0, 3))])
	var read := SaveGame.read(path)
	check(read.ok, "%s: the save reads back (%s)" % [label, read.get("error", "")])
	var size := FileAccess.get_file_as_bytes(path).size()
	print("%s: save of %d KB at %d ms, %d units, %d buildings" % [label, size / 1024, scene.game_ms(), scene.units.size(), scene.production.buildings.size()])
	var saved_modules: Dictionary = read.document.modules if read.ok else {}
	# The first scene's own state at the save, taken again: saving changes nothing.
	same_modules(saved_modules, modules(scene), label + " (a second save of the same moment)")
	# Checkpoints every second of the run: a difference is reported at the first second it shows.
	var marks: Array = []
	for s in roundi(after_s):
		advance(scene, 1.0)
		marks.append(modules(scene))
	var first: Dictionary = modules(scene)
	var moved: Array = first.keys().filter(func(k): return String(first[k]) != String(saved_modules.get(k, "")))
	check(moved.has("units") and moved.has("combat") and moved.has("ai") and moved.has("economy"), "%s: the run changes the match (%s)" % [label, str(moved)])
	var first_ms: int = scene.game_ms()
	var stats := {"units": scene.units.size(), "buildings": scene.production.buildings.size(), "missiles": scene.combat.missiles.size()}
	drop_scene(scene)
	if MapData.is_generated(slug):                      # RM-7: the load's own path rebuilds the map from the document
		var prepared: String = load("res://battle/main.gd").prepare_saved_game(path, directory, save_dir)
		check(prepared == "", "%s: the map is rebuilt from the save (%s)" % [label, prepared])
		load("res://battle/main.gd").pending_load = {}
	var loaded = await new_scene(slug)
	var load_error: String = loaded.load_match(read.document, store) if read.ok else "unread"
	check(load_error == "", "%s: loads into a fresh scene (%s)" % [label, load_error])
	same_modules(saved_modules, modules(loaded), label + " (save right after the load)")
	for s in roundi(after_s):
		advance(loaded, 1.0)
		var now: Dictionary = modules(loaded)
		var bad: Array = now.keys().filter(func(k): return String(now[k]) != String(marks[s].get(k, "")))
		if not bad.is_empty():
			printerr("%s: first difference %d s after the load in %s" % [label, s + 1, str(bad)])
			same_modules(marks[s], now, label + " (first difference, %d s)" % (s + 1))
			advance(loaded, after_s - s - 1)
			break
	check(loaded.game_ms() == first_ms, "%s: the same clock after the run (%d / %d ms)" % [label, loaded.game_ms(), first_ms])
	same_modules(first, modules(loaded), label + " (%.0f s after the load)" % after_s)
	print("%s: %d units, %d buildings, %d missiles in flight after the run" % [label, stats.units, stats.buildings, stats.missiles])
	drop_scene(loaded)
	return stats

## Fights across the save: units of `a` next to a tower of another side (tower missiles) and a melee of `a` against `b`
## in the open (swings, deaths, corpses, XP, the attitude scripts' targets).
func fights(scene, a: int, b: int, middle: Vector2i):
	for t in scene.production.buildings.values():
		if String(t.original_type_id).begins_with("BWT") and int(t.owner) != a and int(t.owner) < 6:
			for i in 3: scene.add_unit("AHKX", scene.navigator.free_cell_near(Vector2i(t.left, t.top) + Vector2i(-3 - i, 3)), a)
			break
	for i in 4:
		scene.add_unit("AHKX", scene.navigator.free_cell_near(middle + Vector2i(i, 0)), a)
		scene.add_unit("AHMX", scene.navigator.free_cell_near(middle + Vector2i(i, 2)), b)
		scene.add_unit("ADMX", scene.navigator.free_cell_near(middle + Vector2i(i, 6)), b)    # Dwarf Crossbows: missiles

## Development probe (`-- --aliases`): containers (arrays, dictionaries) reachable from two places of the live match state
## at once. A save copies each place on its own, so such sharing must be restored by the module that relies on it.
func live_roots(scene) -> Dictionary:
	var roots := {"units": scene.units, "navigation": scene.navigator, "economy": scene.economy, "production": scene.production,
		"combat": scene.combat, "unit_ai": scene.combat.ai, "spells": scene.combat.spells, "hero_spells": scene.combat.spells.hero_spells,
		"visibility": scene.visibility, "encounters": scene.encounters, "treasures": scene.treasures, "mines": scene.mines,
		"conversions": scene.conversions, "conversion": scene.conversions.conversion, "skirmish": scene.skirmish,
		"day_night": scene.day_night, "unit_commands": scene.unit_commands}
	for name in scene.SAVED_FIELDS: roots["main." + name] = scene.get(name)
	for p in scene.ai_manager.players:
		if p != null and p.has_method("save_state"):
			roots["ai%d" % p.me] = p
			roots["ai%d.abilities" % p.me] = p.abilities
	for id in scene.production.buildings: roots["building%d" % id] = scene.production.buildings[id]
	return roots

func collect(value, path: String, found: Array, depth: int, seen_objects: Dictionary):
	if depth > 12: return
	if value is Object:
		if value == null or seen_objects.has(value.get_instance_id()) or value is Node and not value.has_method("save_state") and not (value is UnitAgentScript): return
		seen_objects[value.get_instance_id()] = true
		for prop in value.get_property_list():
			if int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				var v = value.get(prop.name)
				if v is Object and not (v is UnitAgentScript): continue     # other modules: their own roots
				collect(v, path + "." + prop.name, found, depth + 1, seen_objects)
		return
	if value is Dictionary:
		found.append([value, path])
		for k in value: collect(value[k], "%s[%s]" % [path, str(k)], found, depth + 1, seen_objects)
	elif value is Array:
		found.append([value, path])
		for i in value.size(): collect(value[i], "%s[%d]" % [path, i], found, depth + 1, seen_objects)

func report_aliases(scene, label: String):
	var found: Array = []
	var seen := {}
	var roots := live_roots(scene)
	for name in roots: collect(roots[name], name, found, 0, seen)
	var by_hash := {}
	for entry in found:
		var h: int = entry[0].hash()
		if not by_hash.has(h): by_hash[h] = []
		by_hash[h].append(entry)
	var shown := 0
	for h in by_hash:
		var group: Array = by_hash[h]
		if group.size() < 2 or group.size() > 40: continue
		for i in group.size():
			for j in range(i + 1, group.size()):
				if is_same(group[i][0], group[j][0]) and shown < 400 and not (group[i][1] + group[j][1]).contains("[launch]") and not (group[i][1] + group[j][1]).contains("mask_rows") and not (group[i][1] + group[j][1]).contains("[schools]"):
					print("ALIAS %s: %s == %s" % [label, group[i][1], group[j][1]])
					shown += 1

# ------------------------------------------------------------------------------------------------ 1. determinism
func desert_sands():
	var setup := setup_on("desert-sands", [Setup.KNIGHT, Setup.KNIGHT], [0, 6])
	await determinism("Desert Sands Knights vs Knights", "desert-sands", setup, 45.0 if quick else 90.0, 30.0, func(scene):
		var hero = scene.units[scene.hero_unit_id]
		scene.issue_move(scene.navigator.center(hero.cell + Vector2i(9, -4)), false, false, true, {}, [hero])
		fights(scene, 0, 1, Vector2i(64, 60))
		for i in 60: scene.simulation_step(1.0 / 60.0)
		print("Desert Sands: %d missiles in flight, %d swings before the save" % [scene.combat.missiles.size(),
			scene.combat.fighters.values().filter(func(f): return f.get("swing") != null).size()]), true)

func the_hill():
	# Undead (2) human, Dwarves (1), Swarm (14) and Knights (0) computers; the hero gets Runes and casts.
	var setup := setup_on("the-hill", [2, 1, 14, 0], [0, 6, 6, 5])
	await determinism("The Hill four sides (batch 1, spells)", "the-hill", setup, 40.0 if quick else 75.0, 30.0, func(scene):
		var hero_id: int = scene.hero_unit_id
		var f = scene.combat.fighters[hero_id]
		scene.hero_match.profile.data.skills = [{"id": 17, "unlock_level": 1, "rank": 40}, {"id": 14, "unlock_level": 1, "rank": 40}]
		f.mana = 500
		f["max_mana"] = 500
		f.cooldown_until = 0
		var hs = scene.combat.spells.hero_spells
		var first: Dictionary = hs.cast_request(hero_id, 70)                       # Stoneskin (Runes 0, self)
		check(not first.is_empty(), "The Hill: the hero's first cast is requested (%s)" % str(first).left(80))
		for i in 30: scene.simulation_step(1.0 / 60.0)
		f.cooldown_until = 0
		hs.cast_request(hero_id, 73)                                              # Resist Magic (Runes 3, self)
		fights(scene, 1, 2, Vector2i(64, 64))
		var casts := 0
		for p in 4:
			var ai = scene.ai_manager.players[p] if p > 0 else null
			if ai != null and ai.abilities != null: casts += (ai.abilities.casts as Dictionary).size()
		print("The Hill: computer ability kinds used before the save: %d" % casts), true)

func four_bridges():
	var setup := setup_on("four-bridges", [Setup.KNIGHT, 1], [0, 6])
	await determinism("Four Bridges (water)", "four-bridges", setup, 30.0 if quick else 60.0, 25.0, func(scene):
		var naga = scene.add_unit("ALGX", scene.navigator.free_cell_near(Vector2i(50, 66), null, 1, 3), 0)
		scene.issue_move(scene.navigator.center(Vector2i(68, 66)), false, false, true, {}, [naga])
		for i in 240: scene.simulation_step(1.0 / 60.0)
		check(naga.movement_type == 3 and naga.is_moving(), "Four Bridges: the Naga is on its way across the lake at the save"))

# ------------------------------------------------------------------------------------------------ 2. the format
## RM-7: a generated map, from the setup screen's data: the save holds the map's inputs, the load makes it again.
func random_map():
	RandomMapMatch.reset_session()
	var setup := Setup.random_setup()
	var o: Dictionary = setup.options
	o.map_size = 1
	o.terrain = 1
	o.temples = 3
	o.critters = 3
	o.resource_level = 1
	setup.local = 0
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "save-test-hero"
	Setup.set_race(setup, 0, Setup.KNIGHT)
	Setup.set_race(setup, 1, 1)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 6)
	var made := RandomMapMatch.prepare(setup)
	check(bool(made.ok), "Random Map: generated")
	if not bool(made.ok): return
	MapData.select_generated(made.bundle)
	await determinism("Random Map Plains 128", MapData.GENERATED, setup, 30.0 if quick else 60.0, 25.0, func(scene):
		var hero = scene.units[scene.hero_unit_id]
		scene.issue_move(scene.navigator.center(hero.cell + Vector2i(9, 4)), false, false, true, {}, [hero])
		fights(scene, 0, 1, Vector2i(64, 64))
		for i in 60: scene.simulation_step(1.0 / 60.0)
		print("Random Map: %d missiles in flight, %d swings before the save" % [scene.combat.missiles.size(),
			scene.combat.fighters.values().filter(func(f): return f.get("swing") != null).size()]), true)
	# The document carries the inputs; a scene on another generated map refuses it.
	var read := SaveGame.read(SaveGame.path_for("determinism-" + MapData.GENERATED, save_dir))
	check(read.ok and read.document.get("random_map") is Dictionary and String(read.document.map_name) == "Random Map" and String(read.document.line_1).ends_with(" - Random Map"), "the header: the map's inputs, [0287] as its name")
	var other := RandomMapMatch.prepare(setup.duplicate(true))
	MapData.select_generated(other.bundle)
	var scene = await new_scene(MapData.GENERATED)
	check(String(scene.load_match(read.document, store)).begins_with("The save belongs to another map"), "another generated map is another map")
	drop_scene(scene)
	var damaged: Dictionary = read.document.duplicate(true)
	damaged.erase("random_map")
	check(not SaveGame.check_document(damaged).ok, "a generated map's save without its inputs is refused")
	RandomMapMatch.reset_session()

func format_checks():
	var scene = await new_scene("desert-sands")
	check(not scene.can_save(), "no match: nothing to save")
	scene.start_skirmish(setup_on("desert-sands", [Setup.KNIGHT, Setup.KNIGHT], [0, 2]), "save-test-hero", store, "save-test-format")
	advance(scene, 5.0)
	var doc: Dictionary = scene.save_document()
	check(SaveGame.errors.is_empty(), "plain data only: %s" % str(SaveGame.errors.slice(0, 3)))
	check(doc.format == SaveGame.FORMAT and int(doc.version) == SaveGame.VERSION and doc.map == "desert-sands" and doc.hero_id == "save-test-hero",
		"header: format, version, map, hero")
	check(Array(doc.modules.keys()) == scene.SAVE_MODULES + ["refs"], "one blob per module (%s)" % str(doc.modules.keys()))
	var path: String = SaveGame.path_for("format", save_dir)
	check(SaveGame.write(path, doc) == "" and not FileAccess.file_exists(path + ".bak"), "first write: no backup yet")
	check(SaveGame.write(path, doc) == "" and FileAccess.file_exists(path + ".bak") and not FileAccess.file_exists(path + ".tmp"),
		"second write keeps the previous save as .bak, no .tmp left")
	check(SaveGame.read(path + ".bak").ok, "the backup is a valid save")
	var future := doc.duplicate()
	future.version = SaveGame.VERSION + 98
	var future_path: String = SaveGame.path_for("future", save_dir)
	SaveGame.write(future_path, future)
	var r := SaveGame.read(future_path)
	check(not r.ok and String(r.error).contains("another version"), "an unknown version is refused: %s" % r.error)
	check(scene.load_match(future) != "" and scene.skirmish != null and not scene.skirmish.over, "load_match refuses it and the match goes on")
	check(scene.open_saved_game(future_path) != "" and scene.pending_load.is_empty(), "the load sheet refuses it (no scene change)")
	var other := doc.duplicate()
	other.format = "something-else"
	check(not SaveGame.check_document(other).ok, "another format is refused")
	var junk := FileAccess.open(SaveGame.path_for("junk", save_dir), FileAccess.WRITE)
	junk.store_string("{ not json")
	junk.close()
	check(not SaveGame.read(SaveGame.path_for("junk", save_dir)).ok, "a damaged file is refused")
	var broken := doc.duplicate(true)
	broken.modules.combat = "AAAA"
	check(scene.load_match(broken).contains("damaged"), "a damaged module blob is refused before it is decoded: %s" % scene.load_match(broken))
	var unsummed := doc.duplicate(true)
	unsummed.erase("checksums")
	check(not SaveGame.check_document(unsummed).ok, "a save without checksums is refused")
	var wrong_map := doc.duplicate(true)
	wrong_map.map = "the-hill"
	check(scene.load_match(wrong_map).contains("another map"), "a save of another map needs its own scene (open_saved_game)")
	check(SaveGame.list(save_dir).size() >= 3, "saves listed (%d)" % SaveGame.list(save_dir).size())
	drop_scene(scene)

## The Gameplay tab's modern Autosave row (#11): every 10 minutes by default, chosen like the other rows, Cancel restores.
func options_checks():
	var screen = preload("res://menus/options_screen.gd").new()
	root.add_child(screen)
	await process_frame
	check(SaveGame.autosave_setting() == 10, "autosave every 10 minutes by default")
	check(String(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 11), "")) == "Autosave: Every 10 min", "Gameplay row 11: Autosave")
	check(screen.has_item("PNL_GAMEOPTIONS/BUTT_OPTIONS_DROPLIST#11"), "its droplist under the right column")
	screen.choose(11, 3)
	check(SaveGame.autosave_setting() == 0 and String(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 11), "")) == "Autosave: Off", "Off chosen")
	screen.click("PNL_GAMEOPTIONS/BUTT_CANCEL_STARTUP#0")
	check(SaveGame.autosave_setting() == 10, "Cancel restores every 10 minutes")
	if is_instance_valid(screen): screen.free()

# ------------------------------------------------------------------------------------------------ 3. normal play
func key(code: int, alt: bool = false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.alt_pressed = alt
	e.pressed = true
	return e

func menu_checks():
	root.size = Vector2i(1920, 1080)
	var scene = await new_scene("desert-sands")
	scene.enable_normal_play()
	await process_frame
	scene.save_directory = save_dir
	check(scene.start_skirmish(setup_on("desert-sands", [Setup.KNIGHT, Setup.KNIGHT], [0, 2]), "save-test-hero", store, "save-test-menu"), "normal play match starts")
	advance(scene, 4.0)
	var hud = scene.hud
	check(not scene.save_exists(), "no save of this hero yet")
	check(hud.menu_row_enabled(1) and not hud.menu_row_enabled(0), "game menu: Save Game enabled, Load Game greyed without a save (0x566160)")
	hud.open_dialog("menu")
	check(hud.menu_press(1), "the menu's Save Game row")
	for i in 3: await process_frame
	check(scene.save_exists() and hud.message == hud.game_text(304), "saved at once, message [0304] '%s'" % hud.message)
	check(hud.dialog == "", "the menu closes")
	check(hud.handle_key(key(KEY_S, true)), "Alt+S")
	for i in 3: await process_frame
	check(hud.message == hud.game_text(753), "Alt+S over a save: message [0753] '%s'" % hud.message)
	check(hud.menu_row_enabled(0), "Load Game enabled once a save exists")
	check(hud.handle_key(key(KEY_L, true)) and hud.dialog == "load", "Alt+L opens the load sheet (0x564c20)")
	check(String(hud.load_view.get("line_1", "")).contains("Sir Saveall") and String(hud.load_view.get("line_1", "")).contains("Desert Sands"),
		"the sheet's first line: hero - map (%s)" % hud.load_view.get("line_1", ""))
	# A modern autosave of the same match, then the sheet's toggle between the saved game and the autosave.
	advance(scene, 3.0)
	check(scene.autosave() == "" and scene.save_exists(true), "autosave written beside the hero's save")
	hud.close_dialog()
	hud.open_dialog("load")
	hud.load_pick(1)
	check(hud.load_choice == 1 and int(hud.load_view.get("game_ms", -1)) > 4000, "the sheet shows the autosave (%d ms)" % int(hud.load_view.get("game_ms", -1)))
	hud.load_pick(0)
	var saved_ms: int = int(hud.load_view.get("game_ms", -1))
	# Autosave on its own schedule (game time) in normal play.
	SaveGame.set_autosave(5)
	scene.autosave_next_ms = scene.game_ms() + 100
	DirAccess.remove_absolute(scene.save_path(true))
	advance(scene, 0.5)
	check(scene.save_exists(true) and scene.autosave_next_ms > scene.game_ms() + 4 * 60000, "the autosave follows its schedule (next in 5 min)")
	# Load Game: the new scene (the save's map) loads it.
	var old_id: int = scene.get_instance_id()
	check(hud.load_press(), "Load Game on the sheet")
	var loaded = null
	for i in 10:
		await process_frame
		if current_scene != null and current_scene.get_instance_id() != old_id and current_scene.get("skirmish") != null:
			loaded = current_scene
			break
	check(loaded != null, "the saved game opens in a new scene")
	if loaded != null:
		# The new scene plays on its own physics frames while the test waits for it: at or just after the saved moment.
		check(loaded.game_ms() >= saved_ms and loaded.game_ms() < saved_ms + 1000 and loaded.normal_play and loaded.hud != null,
			"at the saved moment (%d / %d ms), in normal play" % [loaded.game_ms(), saved_ms])
		check(loaded.save_directory == save_dir, "the new scene saves where the old one did")
		# The match goes on and saves again; a save at the end opens on its end box again.
		advance(loaded, 2.0)
		loaded.skirmish.quit()
		for i in 20: loaded.simulation_step(1.0 / 60.0)
		check(loaded.skirmish.over and loaded.save_exists(true), "the match ended (quit) and the autosave was written at the end")
		check(not loaded.can_save(), "no Save once the match is decided (0x748914)")
	SaveGame.set_autosave(SaveGame.AUTOSAVE_DEFAULT)
	if is_instance_valid(scene) and scene.is_inside_tree(): drop_scene(scene)
	if loaded != null:
		loaded.end_skirmish()
		current_scene = null
		root.remove_child(loaded)
		loaded.free()
