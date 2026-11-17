extends RefCounted
const Profile = preload("res://simulation/hero_profile.gd")
var directory: String
var last_error := ""

func _init(save_directory: String = "user://heroes"):
	directory = save_directory

func save_profile(profile: Profile) -> bool:
	last_error = profile.validate()
	if not last_error.is_empty(): return false
	var serialized := JSON.stringify(profile.snapshot(), "\t", true)
	if serialized.to_utf8_buffer().size() > 4194304: return _fail("Hero save is too large.")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK: return _fail("Cannot create hero save directory: " + error_string(error))
	var path := directory.path_join(profile.data.id + ".json")
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null: return _fail("Cannot open temporary hero save: " + error_string(FileAccess.get_open_error()))
	file.store_string(serialized)
	file.flush()
	error = file.get_error()
	file.close()
	if error != OK: return _fail("Cannot write hero save: " + error_string(error))
	# Keep last valid state if replacement fails; never overwrite a corrupt/unknown save.
	if FileAccess.file_exists(path):
		if load_profile(profile.data.id) == null: return false
		error = DirAccess.copy_absolute(path, path + ".bak")
		if error != OK: return _fail("Cannot preserve previous hero save: " + error_string(error))
	error = DirAccess.rename_absolute(temporary, path)
	if error != OK: return _fail("Cannot replace hero save: " + error_string(error))
	return true

func load_profile(id: String) -> Profile:
	last_error = ""
	if not Profile.valid_id(id):
		_fail("Invalid hero ID.")
		return null
	var file := FileAccess.open(directory.path_join(id + ".json"), FileAccess.READ)
	if file == null:
		_fail("Cannot read hero: " + error_string(FileAccess.get_open_error()))
		return null
	if file.get_length() > 4194304:
		file.close()
		_fail("Hero save is too large.")
		return null
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	file.close()
	if error != OK or not json.data is Dictionary:
		_fail("Invalid hero JSON.")
		return null
	var profile := Profile.new()
	profile.data = json.data
	last_error = profile.validate()
	if not last_error.is_empty(): return null
	if profile.data.id != id:
		_fail("Hero ID does not match its save file.")
		return null
	return profile

func list_profiles() -> Array:
	var result: Array = []
	var folder := DirAccess.open(directory)
	if folder == null: return result
	var names := folder.get_files()
	names.sort()
	for filename in names:
		if not filename.ends_with(".json") or filename == "selection.json": continue
		var profile := load_profile(filename.trim_suffix(".json"))
		if profile == null: result.append({"id": filename.trim_suffix(".json"), "error": last_error})
		else: result.append({"id": profile.data.id, "name": profile.data.name, "level": int(profile.data.level)})
	return result

## The hero book's Delete (0x555a70 -> 0x555ae0 -> 0x555550) and an Ironman hero's death (0x522260, 0x455d60, Read): the
## record leaves the hero book (the original removes it from the HeroData pack and deletes the hero's own files). Here:
## the rebuild's own profile file, its backup and temporary copy, and the selection when it names this hero. Never touches
## the original game's HeroData folder (this store's directory is the rebuild's). `extra_files` are further paths to remove
## (the hero's saved games, which the original deletes with it). Returns false when a file could not be removed.
func delete_profile(id: String, extra_files: Array = []) -> bool:
	last_error = ""
	if not Profile.valid_id(id): return _fail("Invalid hero ID.")
	var ok := true
	for path in [directory.path_join(id + ".json"), directory.path_join(id + ".json.bak"), directory.path_join(id + ".json.tmp")] + extra_files:
		if not FileAccess.file_exists(String(path)): continue
		var error := DirAccess.remove_absolute(String(path))
		if error != OK:
			ok = false
			last_error = "Cannot delete hero file: " + error_string(error)
	var selection := directory.path_join("selection.json")
	if FileAccess.file_exists(selection):
		var value = JSON.parse_string(FileAccess.get_file_as_string(selection))
		if value is Dictionary and String(value.get("id", "")) == id: DirAccess.remove_absolute(selection)
	return ok

func select_profile(id: String) -> bool:
	if load_profile(id) == null: return false
	var file := FileAccess.open(directory.path_join("selection.json"), FileAccess.WRITE)
	if file == null: return _fail("Cannot save hero selection.")
	file.store_string(JSON.stringify({"schema_version": 1, "id": id}))
	file.close()
	return true

func selected_profile() -> Profile:
	if not FileAccess.file_exists(directory.path_join("selection.json")): return null
	var value = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("selection.json")))
	if not value is Dictionary or value.get("schema_version") != 1 or not value.get("id") is String:
		_fail("Invalid hero selection.")
		return null
	return load_profile(value.id)

func _fail(message: String) -> bool:
	last_error = message
	return false
