extends RefCounted
## main.gd's in-match Save / Load (R-1 split of main.gd, no behaviour change; SAVE_LOAD.md): the save document, the
## module states, load and restore, quick save, autosave. The saved fields stay on the scene (main.gd SAVED_FIELDS).

const MainScript = preload("res://battle/main.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const HeroProfile = preload("res://simulation/hero_profile.gd")
const SkirmishSetup = preload("res://simulation/skirmish_setup.gd")
const HeroStore = preload("res://simulation/hero_store.gd")
const MapData = preload("res://core/map_data.gd")
const ArtData = preload("res://core/art_data.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

func can_save() -> bool:
	if main.skirmish != null and bool(main.skirmish.options.get("temp_hero", false)): return false   # S-2: 0x427fb0 case 0x13
	return main.skirmish != null and not main.skirmish.over and not main.skirmish.game_over and not main.match_setup.is_empty()

## The whole match as one document (simulation/save_game.gd). `thumbnail` is a PNG of the view (the original keeps a
## 242 x 173 picture of the screen centre in the save's header, 0x4482f0).
## `with_checksums` false (the timed autosave): the "checksums" entry is left empty for SaveGame.write_async to fill.
func save_document(thumbnail: PackedByteArray = PackedByteArray(), with_checksums: bool = true) -> Dictionary:
	SaveGame.errors.clear()
	var refs := SaveGame.Refs.new()
	var states := {}
	for key in MainScript.SAVE_MODULES: states[key] = module_state(key, refs)
	var modules := {}
	for key in states: modules[key] = SaveGame.encode(states[key])
	modules["refs"] = SaveGame.encode(refs.table)               # every shared object, saved once (written last)
	var hero_name := String(main.hero_match.profile.data.name) if main.hero_match != null and main.hero_match.profile != null else "Spectator"
	var resolved: Dictionary = main.skirmish.resolved
	var players: Array = []
	for p in SkirmishSetup.active_players(resolved):
		players.append({"slot": p, "race": int(resolved.slots[p].race), "computer": bool(resolved.slots[p].computer)})
	var map_name: String = MainScript.RANDOM_MAP_NAME if MapData.is_generated() else MapData.name_of()
	var doc := {"format": SaveGame.FORMAT, "version": SaveGame.VERSION, "saved_at": Time.get_datetime_string_from_system(false, true),
		"line_1": "%s - %s" % [hero_name, map_name],
		"line_2": Time.get_datetime_string_from_system(false, true),
		"name": "%s - %s" % [hero_name, map_name], "map": MapData.current, "map_name": map_name,
		"match_id": main.skirmish.match_id, "hero_id": main.match_hero_id, "game_ms": main.game_ms(), "players": players,
		"engine": Engine.get_version_info().string, "modules": modules, "checksums": SaveGame.checksums(modules) if with_checksums else {}}
	if not thumbnail.is_empty(): doc["thumbnail"] = Marshalls.raw_to_base64(thumbnail)
	if MapData.is_generated() and not main.match_setup.get("random_map", {}).is_empty(): doc["random_map"] = main.match_setup.random_map.duplicate(true)   # RM-7
	return doc

func module_state(key: String, refs) -> Dictionary:
	match key:
		"main": return main_state(refs)
		"units": return {"units": main.units.map(func(u): return u.save_state(refs))}
		"navigation": return main.navigator.save_state(refs)
		"economy": return main.economy.save_state(refs)
		"production": return main.production.save_state(refs)
		"combat": return main.combat.save_state(refs)
		"visibility": return main.visibility.save_state(refs)
		"encounters": return main.encounters.save_state(refs)
		"treasures": return main.treasures.save_state(refs)
		"mines": return main.mines.save_state(refs) if main.mines != null else {}
		"conversions": return main.conversions.save_state(refs) if main.conversions != null else {}
		"ai": return main.ai_manager.save_state(refs) if main.ai_manager != null else {}
		"skirmish": return main.skirmish.save_state(refs)
		"day_night": return main.day_night.save_state(refs) if main.day_night != null else {}
		"unit_commands": return main.unit_commands.save_state(refs)
		"map_objects":
			main.settle_object_clocks()                # P-4: the still features' shared clock
			return {"objects": main.map_objects.map(func(o): return o.save_state(refs))}
	return {}

## main.gd's fields, the statics the simulation reads (the walk-phase counter, the local player of the unit draw, the
## slot colours), the setup, the hero links and the building markers.
func main_state(refs) -> Dictionary:
	var s: Dictionary = SaveGame.fields(main, MainScript.SAVED_FIELDS)
	s["setup"] = main.match_setup.duplicate(true)
	s["hero_id"] = main.match_hero_id
	s["statics"] = {"phase_counter": UnitAgent.phase_counter, "unit_local_player": UnitAgent.local_player,
		"colours": ArtData.colours.duplicate(), "marker_unit": UnitAgent.marker_unit, "marker_type": UnitAgent.marker_type,
		"marker_phase": UnitAgent.marker_phase}
	s["hero_match"] = refs.ref(main.hero_match)
	var bound := {}
	for owner in main.match_heroes: bound[owner] = refs.ref(main.match_heroes[owner])
	s["match_heroes"] = bound
	var waiting := {}
	for owner in main.match_profiles:
		var saved = main.match_profiles[owner]
		waiting[owner] = {"record": saved.duplicate(true)} if saved is Dictionary else {"profile": saved.data.duplicate(true)}
	s["match_profiles"] = waiting
	s["markers"] = main.building_nodes.keys()
	# A conversion's marker order is the same dictionary as the fighter's current order (order_convert_here): the
	# fighter's copy is the one kept on load.
	s["shared_cur"] = main.mine_orders.keys().filter(func(id): return main.mine_orders[id].has("cur") and main.combat.fighters.has(id) and is_same(main.mine_orders[id].cur, main.combat.fighters[id].cur))
	s["hud_speed"] = int(main.hud.speed) if main.hud != null else 3
	return s

## Writes the match to `path` (atomic, .bak kept). Returns "" or the error.
func save_match(path: String, thumbnail: PackedByteArray = PackedByteArray()) -> String:
	if not can_save(): return "No match to save."
	var doc := save_document(thumbnail)
	if not SaveGame.errors.is_empty(): return "The match could not be saved (%s)." % SaveGame.errors[0]
	return SaveGame.write(path, doc)

## Loads a checked document into this scene: the saved map must be the scene's map (a load from the game menu changes
## the scene first, open_saved_game). Returns "" or the error; a refused save leaves the scene as it was.
func load_match(document: Dictionary, store = null) -> String:
	var checked := SaveGame.check_document(document)
	if not checked.ok: return checked.error
	if String(document.map) != MapData.current: return "The save belongs to another map (%s)." % String(document.get("map_name", document.map))
	# RM-7: every generated map shares the slug; its generation inputs tell them apart.
	if MapData.is_generated() and RandomMapMatch.identity(document.get("random_map", {})) != RandomMapMatch.identity(MapData.generated.get("spec", {})):
		return "The save belongs to another map (%s)." % String(document.get("map_name", document.map))
	var states: Dictionary = SaveGame.modules_of(document)
	for key in MainScript.SAVE_MODULES + ["refs"]:
		if not states.get(key) is Dictionary and not (key == "refs" and states.get(key) is Array):
			return "The save is damaged (module %s)." % key
	var m: Dictionary = states.main
	var refs := SaveGame.Refs.new()
	refs.table = states.refs
	refs.scene = main
	# The saved in-match hero copy stands in when the hero book no longer has the hero.
	var hero_ref := int(m.get("hero_match", -1))
	main.restore_profile = null
	if hero_ref >= 0 and refs.table[hero_ref].state.get("profile") != null:
		main.restore_profile = HeroProfile.new()
		main.restore_profile.data = refs.table[hero_ref].state.profile.duplicate(true)
	main.restoring = true
	var ok := main.start_skirmish(m.setup, String(m.hero_id), store if store != null else main.hero_store, String(states.skirmish.get("match_id", "")))
	main.restoring = false
	main.restore_profile = null
	if not ok: return "The saved match could not be started again: " + main.last_message
	restore_states(states, refs)
	return ""

## Replaces every module's state with the saved one (SAVE_MODULES order). Nothing here runs the simulation.
func restore_states(states: Dictionary, refs):
	var m: Dictionary = states.main
	SaveGame.restore(main, m, ["setup", "hero_id", "statics", "hero_match", "match_heroes", "match_profiles", "markers", "hud_speed", "shared_cur"])
	UnitAgent.phase_counter = int(m.statics.phase_counter)
	UnitAgent.local_player = int(m.statics.unit_local_player)
	UnitAgent.marker_unit = int(m.statics.marker_unit)
	UnitAgent.marker_type = int(m.statics.marker_type)
	UnitAgent.marker_phase = int(m.statics.marker_phase)
	ArtData.colours.clear()
	ArtData.colours.merge(m.statics.colours)
	if main.effects != null: main.effects.clear()
	main.clear_units()
	for state in states.units.units: restore_unit(state)
	main.navigator.load_state(states.navigation, refs)
	main.economy.load_state(states.economy, refs)
	main.production.load_state(states.production, refs)
	for key in main.building_nodes.keys(): main.building_nodes[key].free()
	main.building_nodes.clear()
	for id in m.markers:
		if main.production.building(int(id)) != null: main.add_marker(main.production.building(int(id)))
	for key in main.building_nodes: main.building_nodes[key].selected = key == main.selected_building_id
	main.combat.load_state(states.combat, refs)
	for id in m.get("shared_cur", []):
		if main.mine_orders.has(id) and main.combat.fighters.has(id): main.mine_orders[id].cur = main.combat.fighters[id].cur
	main.visibility.load_state(states.visibility, refs)
	main.encounters.load_state(states.encounters, refs)
	main.treasures.load_state(states.treasures, refs)
	if main.mines != null and not states.mines.is_empty(): main.mines.load_state(states.mines, refs)
	# Saves from before the population fix kept mine workers registered (see resolve_mine_orders): they left play.
	if main.mines != null:
		for mine_id in main.mines.workers:
			for worker in main.mines.workers[mine_id]: main.production.unregister_unit(int(worker))
	if main.conversions != null and not states.conversions.is_empty(): main.conversions.load_state(states.conversions, refs)
	if main.ai_manager != null and not states.ai.is_empty(): main.ai_manager.load_state(states.ai, refs)
	main.skirmish.load_state(states.skirmish, refs)
	if main.day_night != null and not states.day_night.is_empty(): main.day_night.load_state(states.day_night, refs)
	main.unit_commands.load_state(states.unit_commands, refs)
	main.hero_match = refs.get_obj(int(m.hero_match))
	main.match_heroes.clear()
	for owner in m.match_heroes: main.match_heroes[owner] = refs.get_obj(int(m.match_heroes[owner]))
	main.match_profiles.clear()
	for owner in m.match_profiles:
		var w: Dictionary = m.match_profiles[owner]
		if w.has("record"): main.match_profiles[owner] = w.record.duplicate(true)
		else:
			var p = HeroProfile.new()
			p.data = w.profile.duplicate(true)
			main.match_profiles[owner] = p
	var objects: Array = states.map_objects.objects
	for i in mini(objects.size(), main.map_objects.size()): main.map_objects[i].load_state(objects[i], main.production, main.encounters)
	main.adopt_object_clocks()
	# Presentation only from here: the modern rules follow the current options as at a match start (they were the same
	# when the save was made unless the player changed them since), the view, the fog drawing and the speed.
	main.apply_modern_rules()
	if main.hud != null:
		main.hud.speed = int(m.get("hud_speed", 3))
		main.hud.apply_speed()
	if main.hero_unit_id >= 0 and main.hero_unit_id < main.units.size(): main.centre_view(main.units[main.hero_unit_id].position)
	main.apply_fog_to_nodes()
	main.refresh_fog_overlay()
	for unit in main.units: unit.update_sprite()
	if main.skirmish.over:                                       # an end-of-match autosave opens on its end box again
		main.restoring = true
		main._on_match_ended(main.skirmish.outcome)
		main.restoring = false
	main.last_message = "Game loaded."

## A unit node from its saved state (add_unit without its side effects: no fighter, occupancy or fog arming; those come
## from the saved modules).
func restore_unit(state: Dictionary):
	var unit = UnitAgent.new()
	unit.type_id = String(state.type_id)
	unit.load_state(state)
	unit.navigator = main.navigator
	if state.has("@modulate"): unit.modulate = state["@modulate"]
	main.add_child(unit)
	main.units.append(unit)
	if main.combat != null:
		unit.order_step = func(id, to_cell): main.combat.ai.on_step(id, to_cell)
		unit.sight_step = func(owner, from_cell, to_cell, turned): main.visibility.arm_step(owner, from_cell, to_cell, turned)
	return unit

## Game menu Save / Alt+S (0x565bb6 / 0x427fb0 case 0x13): saves at once and returns the message line's text
## ([0304] game saved, [0753] a save was replaced, [0305] failed).
func quick_save(thumbnail: PackedByteArray = PackedByteArray()) -> Dictionary:
	var existed := main.save_exists()
	var error := save_match(main.save_path(), thumbnail)
	if error != "": push_warning("Save failed: " + error)
	return {"ok": error == "", "error": error, "text_id": (753 if existed else 304) if error == "" else 305}

## The load sheet's Load Game (0x565140 -> 0x446150): the saved map needs a fresh scene, so the scene is changed and
## the new main.tscn loads the document in _ready. Returns "" or the reason the save was refused.
func open_saved_game(path: String) -> String:
	var error := MainScript.prepare_saved_game(path, String(main.hero_store.directory) if main.hero_store != null and "directory" in main.hero_store else "user://heroes", main.save_directory)
	if error == "": main.get_tree().change_scene_to_file("res://battle/main.tscn")
	return error

## _ready of a scene opened for a load.
func load_pending():
	var pending: Dictionary = MainScript.pending_load
	MainScript.pending_load = {}
	main.save_directory = String(pending.get("save_dir", SaveGame.default_directory()))
	var error := load_match(pending.document, HeroStore.new(String(pending.get("store_dir", "user://heroes"))))
	if error != "":
		main.last_message = error
		push_warning("Load failed: " + error)
		if main.hud != null: main.hud.show_message(error)
		main.get_tree().change_scene_to_file("res://menus/front_end.tscn")
	elif main.hud != null: main.hud.show_message("Game loaded.")     # the rebuild's line (the original's message after a load is Open)

## DELIBERATE MODERN CHANGE (F8): the autosave every N minutes of game time (Gameplay tab "Autosave") and when the match
## is decided. Only in normal play (the checks call autosave() themselves).
func update_autosave():
	if not main.normal_play or not can_save(): return
	var minutes := SaveGame.autosave_setting()
	if minutes <= 0: return
	if main.autosave_next_ms < 0:
		main.autosave_next_ms = main.game_ms() + minutes * 60000
		return
	if main.game_ms() >= main.autosave_next_ms:
		main.autosave_next_ms = main.game_ms() + minutes * 60000
		autosave_async()

## P-4: the timed autosave: the state is captured and encoded here, the checksums, the JSON text and the file are done on
## a worker thread (SaveGame.write_async), so the match stops for less.
func autosave_async():
	if main.skirmish == null or main.match_setup.is_empty() or not can_save(): return
	if main.hero_match != null and main.hero_match.deleted: return
	var doc := save_document(PackedByteArray(), false)
	if not SaveGame.errors.is_empty():
		push_warning("Autosave failed: " + String(SaveGame.errors[0]))
		return
	SaveGame.write_async(main.save_path(true), doc)

func autosave(at_end: bool = false) -> String:
	if main.skirmish == null or main.match_setup.is_empty() or (not at_end and not can_save()): return "No match to save."
	# FE-1: an Ironman hero that died was deleted with its saved games (0x522260); no autosave brings them back.
	if main.hero_match != null and main.hero_match.deleted: return "The hero is gone."
	var doc := save_document()
	if not SaveGame.errors.is_empty(): return SaveGame.errors[0]
	var error := SaveGame.write(main.save_path(true), doc)
	if error != "": push_warning("Autosave failed: " + error)
	return error

