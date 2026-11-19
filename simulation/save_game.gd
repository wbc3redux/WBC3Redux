extends RefCounted
## S-1 (SAVE_LOAD.md): in-match Save / Load of a skirmish. The rebuild's own format, not the original's binary save:
## one JSON document per save with a readable header and one Godot-binary blob per simulation module.
##
##   {"format": FORMAT, "version": VERSION, "saved_at": "...", "name": "...", "map": slug, "map_name": "...",
##    "random_map": {generation inputs, on a generated map only}, "match_id": "...", "hero_id": "...", "game_ms": n,
##    "players": [{"slot", "race", "kind"}...],
##    "modules": {"main": "<base64>", "combat": "<base64>", ...}, "checksums": {"main": "<sha-256 of the blob>", ...}}
##
## Each blob is Marshalls.variant_to_base64(state) of the Dictionary the module's save_state() returns (Godot's Variant
## binary encoding: ints, floats, Vector2 / Vector2i, packed arrays, typed arrays and int dictionary keys survive bit for
## bit, which JSON numbers would not). A state holds plain data only: objects are saved through Refs (shared objects
## such as EntityState / BuildingState / HeroMatch, by identity) or as unit / building ids. `capture` refuses objects,
## callables and signals (they are recorded in `errors`; the determinism suite fails on any).
##
## Writing follows hero_store.gd: a .tmp file, the previous save kept as .bak, then the rename. Reading refuses another
## format or an unknown version with a message (never a crash).

const FORMAT := "wbc3-rebuild-skirmish-save"
const VERSION := 1
const DIRECTORY := "user://saves"
const MAX_BYTES := 64 * 1024 * 1024
const AUTOSAVE_NAME := "autosave"

static var errors: Array = []            # capture problems of the latest save (object / callable fields)

## DELIBERATE MODERN CHANGE (COMPLAINTS_AND_FIXES.md F8): autosave every N minutes of game time and when the match is
## decided. The Gameplay tab's "Autosave" row (options_screen.gd) chooses N; 0 is off. Stored in the settings file's
## [Modern] section like the Day / Night row.
const AUTOSAVE_CHOICES := [["Every 5 min", 5], ["Every 10 min", 10], ["Every 15 min", 15], ["Off", 0]]
const AUTOSAVE_DEFAULT := 10
static var autosave_minutes := AUTOSAVE_DEFAULT
static var _autosave_loaded_from := ""

static func _settings_path() -> String:
	return preload("res://simulation/game_settings.gd").file_path

static func autosave_setting() -> int:
	if _autosave_loaded_from != _settings_path():
		_autosave_loaded_from = _settings_path()
		autosave_minutes = AUTOSAVE_DEFAULT
		var config := ConfigFile.new()
		if DisplayServer.get_name() != "headless" and config.load(_autosave_loaded_from) == OK:
			autosave_minutes = int(config.get_value("Modern", "Autosave", AUTOSAVE_DEFAULT))
	return autosave_minutes

static func set_autosave(minutes: int):
	autosave_setting()
	autosave_minutes = maxi(0, minutes)

static func save_autosave_setting() -> bool:
	var config := ConfigFile.new()
	config.load(_settings_path())
	config.set_value("Modern", "Autosave", autosave_minutes)
	return config.save(_settings_path()) == OK

## The Gameplay row (options_screen.gd, BUTT_OPTIONS_DROPLIST #11, the original's droplist style).
static func gameplay_row() -> Dictionary:
	var current := 3
	for i in AUTOSAVE_CHOICES.size():
		if int(AUTOSAVE_CHOICES[i][1]) == autosave_setting(): current = i
	return {"key": "Autosave", "modern": true, "label": "Autosave: %s", "choices": AUTOSAVE_CHOICES, "current": current}

## The script variables of `obj` (PROPERTY_USAGE_SCRIPT_VARIABLE, own and inherited) except `skip`, deep-copied.
## Statics and constants are not script variables; modules add those themselves.
static func capture(obj: Object, skip: Array = []) -> Dictionary:
	var out := {}
	for name in script_variables(obj):
		if name in skip: continue
		var value = obj.get(name)
		if pure(value):
			out[name] = copy(value)
			continue
		var bad := impure(value, "%s.%s" % [_label(obj), name])
		if bad != "":
			errors.append(bad)
			push_error("Save: " + bad)
			continue
		out[name] = copy(value)
	return out

## Performance (P-4): the names of an object's script variables, in get_property_list's order, kept per script (the list
## of a node holds every engine property too, and a save asks it for every unit and map object).
static var _script_variables: Dictionary = {}   # Script -> Array of names

static func script_variables(obj: Object) -> Array:
	var script = obj.get_script()
	if script != null and _script_variables.has(script): return _script_variables[script]
	var names: Array = []
	for p in obj.get_property_list():
		if int(p.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE: names.append(String(p.name))
	if script != null: _script_variables[script] = names
	return names

## Performance (P-4): `impure(value, path) == ""` without building the path text of every element; capture asks
## `impure` for the message only when this is false.
static func pure(value) -> bool:
	match typeof(value):
		TYPE_OBJECT:
			return value == null
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_ARRAY:
			for item in value:
				if not pure(item): return false
		TYPE_DICTIONARY:
			for k in value:
				if not pure(k) or not pure(value[k]): return false
	return true

## Only the named fields of `obj` (main.gd's match fields among its scene nodes), deep-copied and checked like capture.
static func fields(obj: Object, names: Array) -> Dictionary:
	var out := {}
	for name in names:
		var value = obj.get(name)
		var bad := impure(value, "%s.%s" % [_label(obj), name])
		if bad != "":
			errors.append(bad)
			push_error("Save: " + bad)
			continue
		out[name] = copy(value)
	return out

## Writes the fields of `state` back into `obj`. Arrays and dictionaries already held by `obj` are refilled in place, so
## a container another module shares by reference (main.units with combat.units, skirmish.eliminated with encounters)
## stays shared, as start_skirmish wired it. Keys starting with "@" are meta entries of the module, not fields.
static func restore(obj: Object, state: Dictionary, skip: Array = []):
	for name in state:
		if String(name).begins_with("@") or name in skip: continue
		if not (name in obj):
			push_warning("Load: %s has no field %s (save from another build)" % [_label(obj), name])
			continue
		put(obj, name, state[name])

static func put(obj: Object, name: String, value):
	var current = obj.get(name)
	if current is Array and value is Array and current.get_typed_builtin() == value.get_typed_builtin() and current.get_typed_class_name() == value.get_typed_class_name():
		current.assign(copy(value))
	elif current is Dictionary and value is Dictionary and current.is_typed() == value.is_typed():
		current.clear()
		current.merge(copy(value))
	else:
		obj.set(name, copy(value))

static func copy(value):
	if value is Array or value is Dictionary: return value.duplicate(true)
	return value

## The path of the first object, callable, signal or RID inside `value`, "" when it is plain data.
static func impure(value, path: String) -> String:
	match typeof(value):
		TYPE_OBJECT:
			return "" if value == null else path + " holds an object (" + _label(value) + ")"
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return path + " holds a " + type_string(typeof(value))
		TYPE_ARRAY:
			for i in value.size():
				var bad := impure(value[i], "%s[%d]" % [path, i])
				if bad != "": return bad
		TYPE_DICTIONARY:
			for k in value:
				var bad := impure(k, path + "{key}")
				if bad != "": return bad
				bad = impure(value[k], "%s[%s]" % [path, str(k)])
				if bad != "": return bad
	return ""

static func _label(obj) -> String:
	if obj == null: return "null"
	var script = obj.get_script()
	if script != null and script.resource_path != "": return script.resource_path.get_file().get_basename()
	return obj.get_class()

## Shared objects by identity. Saving: ref(obj) stores the object's own save_state(refs) once and returns its index
## (-1 for null). Loading: get_obj(index) makes the object once (its script, "@ctor" arguments) and fills it with
## load_state(state, refs). Unit nodes are not shared objects: they go by unit id (scene.units).
class Refs:
	var table: Array = []                # saved: [{"script": path, "state": {...}}]
	var _index: Dictionary = {}          # instance id -> index (saving)
	var _made: Dictionary = {}           # index -> instance (loading)
	var scene                            # main.gd while loading (units by id)

	func ref(obj) -> int:
		if obj == null: return -1
		var key: int = obj.get_instance_id()
		if _index.has(key): return int(_index[key])
		var i := table.size()
		_index[key] = i
		table.append({})                 # reserved first: a state that refers back to this object finds its index
		table[i] = {"script": obj.get_script().resource_path, "state": obj.save_state(self)}
		return i

	func get_obj(i: int):
		if i < 0 or i >= table.size(): return null
		if _made.has(i): return _made[i]
		var entry: Dictionary = table[i]
		var script: Script = load(String(entry.script))
		var args: Array = entry.state.get("@ctor", [])
		var obj = script.callv("new", args)
		_made[i] = obj
		obj.load_state(entry.state, self)
		return obj

	func unit(id: int):
		return scene.units[id] if scene != null and id >= 0 and id < scene.units.size() else null

# ------------------------------------------------------------------------------------------------ files
## The player's saves; headless runs (the checks, soaks and captures) use their own folder so they never add a save, an
## autosave or a Load Game row to the player's.
static func default_directory() -> String:
	return DIRECTORY + "-headless" if DisplayServer.get_name() == "headless" else DIRECTORY

static func path_for(name: String, directory: String = DIRECTORY) -> String:
	return directory.path_join(sanitize(name) + ".wbcsave")

static func sanitize(name: String) -> String:
	var out := ""
	for ch in name.strip_edges():
		out += ch if (ch.is_valid_identifier() or ch in "0123456789-_ ") else "_"
	out = out.strip_edges().replace(" ", "_")
	return out.substr(0, 40) if out != "" else "save"

static func encode(state) -> String:
	return Marshalls.variant_to_base64(state, false)

## The checksum entry of each blob (check_document refuses a blob that does not match: a damaged file is never decoded).
static func checksums(modules: Dictionary) -> Dictionary:
	var out := {}
	for key in modules: out[key] = String(modules[key]).sha256_text()
	return out

static func decode(text: String):
	return Marshalls.base64_to_variant(text, false)

## Atomic write (hero_store.gd): .tmp, the previous file kept as .bak, rename. Returns "" or the error message.
static func write(path: String, document: Dictionary) -> String:
	finish_pending()
	return _write(path, document)

## Performance (P-4): the timed autosave's checksums, JSON text and file write on a worker thread (about 90 ms of an
## autosave late in a six-side match). `document` holds only plain data that nobody else keeps (the modules are
## already encoded text); its "checksums" entry is filled here. One write at a time: every other reader or writer of
## save files calls finish_pending() first (write, read, list, remove; main_match.gd when the match ends).
static var _pending := -1                  # WorkerThreadPool task id

static func write_async(path: String, document: Dictionary):
	finish_pending()
	_pending = WorkerThreadPool.add_task(_write_task.bind(path, document), false, "autosave")

static func _write_task(path: String, document: Dictionary):
	document["checksums"] = checksums(document.modules)
	var error := _write(path, document)
	if error != "": push_warning("Autosave failed: " + error)

static func finish_pending():
	if _pending == -1: return
	var task := _pending
	_pending = -1
	WorkerThreadPool.wait_for_task_completion(task)

static func _write(path: String, document: Dictionary) -> String:
	var text := JSON.stringify(document, "\t", false)
	if text.to_utf8_buffer().size() > MAX_BYTES: return "The save is too large."
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK: return "Cannot create the save folder: " + error_string(error)
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return "Cannot open the save file: " + error_string(FileAccess.get_open_error())
	file.store_string(text)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return "Cannot write the save: " + error_string(error)
	if FileAccess.file_exists(path):
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK: return "Cannot keep the previous save: " + error_string(error)
		DirAccess.remove_absolute(path)
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK: return "Cannot replace the save: " + error_string(error)
	return ""

## {"ok": bool, "error": message, "document": {...}}. Another format, an unknown version or a damaged file is refused.
static func read(path: String) -> Dictionary:
	finish_pending()
	if not FileAccess.file_exists(path): return {"ok": false, "error": "The save file is missing."}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {"ok": false, "error": "Cannot read the save: " + error_string(FileAccess.get_open_error())}
	if file.get_length() > MAX_BYTES:
		file.close()
		return {"ok": false, "error": "The save is too large."}
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary: return {"ok": false, "error": "The save is damaged (not a save document)."}
	return check_document(json.data)

static func check_document(document: Dictionary) -> Dictionary:
	if document.get("format") != FORMAT: return {"ok": false, "error": "This file is not a skirmish save of this game."}
	var version = document.get("version")
	if not (version is float or version is int) or int(version) != VERSION:
		return {"ok": false, "error": "This save was made by another version of the game (save version %s, this game reads %d)." % [str(version), VERSION]}
	if not document.get("modules") is Dictionary or not document.get("map") is String:
		return {"ok": false, "error": "The save is damaged (no match data)."}
	if document.map == preload("res://core/map_data.gd").GENERATED and not document.get("random_map") is Dictionary:   # RM-7
		return {"ok": false, "error": "The save is damaged (no random map data)."}
	var sums = document.get("checksums")
	if not sums is Dictionary: return {"ok": false, "error": "The save is damaged (no checksums)."}
	for key in document.modules:
		if not document.modules[key] is String or String(sums.get(key, "")) != String(document.modules[key]).sha256_text():
			return {"ok": false, "error": "The save is damaged (module %s)." % key}
	return {"ok": true, "error": "", "document": document}

## The module states of a checked document, decoded ({} entries for blobs that do not decode).
static func modules_of(document: Dictionary) -> Dictionary:
	var out := {}
	for key in document.modules: out[key] = decode(String(document.modules[key]))
	return out

## Saves in `directory`, newest first: [{"name", "path", "saved_at", "map_name", "game_ms", "error"}].
static func list(directory: String = DIRECTORY) -> Array:
	var out: Array = []
	var folder := DirAccess.open(directory)
	if folder == null: return out
	for filename in folder.get_files():
		if not filename.ends_with(".wbcsave"): continue
		var path := directory.path_join(filename)
		var r := read(path)
		var row := {"name": filename.trim_suffix(".wbcsave"), "path": path, "saved_at": "", "map_name": "", "game_ms": 0,
			"error": r.error, "modified": FileAccess.get_modified_time(path)}
		if r.ok:
			row.name = String(r.document.get("name", row.name))
			row.saved_at = String(r.document.get("saved_at", ""))
			row.map_name = String(r.document.get("map_name", ""))
			row.game_ms = int(r.document.get("game_ms", 0))
		out.append(row)
	out.sort_custom(func(a, b): return int(a.modified) > int(b.modified))
	return out

static func remove(path: String) -> bool:
	finish_pending()
	return DirAccess.remove_absolute(path) == OK
