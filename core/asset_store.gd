extends RefCounted
## The imported game data (PACKAGING.md steps 1 and 4). The art, sound, maps and data that tools/import_assets.py converts
## from the player's own Warlords Battlecry III are never packed into an exported build, so the game reads them through
## here from one place, chosen once:
##   1. `--assets=<dir>`: a loose folder (after `--` or among the engine arguments),
##   2. `--data-pack=<file>`: a data pack, mounted (tests),
##   3. the WBC3_ASSETS environment variable: a loose folder,
##   4. a source run (editor, `godot --path`): this project's own assets/, as in development,
##   5. an exported build: wbc3-data.pck beside the executable (the installer's result), mounted at res://wbc3data/;
##      else <executable folder>/assets/ (a loose import, also what the prepare pass works on); else user://assets/.
## Every runtime reader of imported files goes through here.
## Textures: in a source run reading this project's own assets/, through Godot's import as before (unchanged behaviour and
## speed). Elsewhere they are decoded from PNG. The Godot importer's alpha border fix (process/fix_alpha_border; lossless,
## no mipmaps otherwise) costs ~10x the decode, so the installer runs `prepare()` once (`--prepare-assets`, display.gd):
## it applies Image.fix_alpha_edges to every imported PNG in place and writes prepared.json. In a folder without that
## marker the fix runs at load time instead (slow, same pixels). The fix is idempotent, so preparing twice is harmless.
## With `--pack` the prepare pass then writes the whole folder into one wbc3-data.pck and removes the loose files.
## Tests keep reading res://assets/ directly; they never ship.

const PREPARED := "prepared.json"
const PREPARED_VERSION := 1
const PACK_FILE := "wbc3-data.pck"
const PACK_ROOT := "res://wbc3data/"     # where a data pack's files appear once mounted

static var _root := ""
static var _source_import := false     # root is this project's own assets/ in a source run: use Godot's import
static var _prepared := -1             # prepared.json present: -1 not checked yet
static var _textures: Dictionary = {}
static var _fonts: Dictionary = {}

## Folder (or mounted pack root) holding the imported data, with a trailing slash.
static func root() -> String:
	if _root == "":
		_root = _resolve()
		_source_import = not OS.has_feature("template") and _root == _project_assets()
	return _root

## The data comes from a mounted data pack.
static func packed() -> bool:
	return root() == PACK_ROOT

## The folder's PNGs already carry the alpha border fix (prepare()).
static func prepared() -> bool:
	if _prepared < 0:
		var marker = json(PREPARED)
		_prepared = 1 if marker is Dictionary and int(marker.get("version", 0)) == PREPARED_VERSION else 0
	return _prepared == 1

## Path of an imported file, `relative` as written under assets/ (for example "maps/index.json"): absolute for a loose
## folder, res://wbc3data/... for a pack. FileAccess reads both.
static func path(relative: String) -> String:
	return root() + relative

static func exists(relative: String) -> bool:
	return FileAccess.file_exists(path(relative))

## True when the data holds an import (catalogue.json is written by every import).
static func imported() -> bool:
	return exists("catalogue.json")

static func text(relative: String) -> String:
	return FileAccess.get_file_as_string(path(relative))

static func bytes(relative: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path(relative))

## Parsed JSON of an imported file, or null when it is missing or unreadable.
static func json(relative: String) -> Variant:
	if not exists(relative): return null
	return JSON.parse_string(text(relative))

## An imported PNG as a texture, cached by relative path; null when the file is missing or does not decode.
static func texture(relative: String) -> Texture2D:
	if _textures.has(relative): return _textures[relative]
	var result: Texture2D = null
	var file := path(relative)
	if FileAccess.file_exists(file):
		if _source_import and ResourceLoader.exists("res://assets/" + relative):
			result = load("res://assets/" + relative)
		else:
			var image := Image.new()      # from the bytes: the same for a loose folder and a mounted pack
			if image.load_png_from_buffer(FileAccess.get_file_as_bytes(file)) == OK and not image.is_empty():
				if not prepared(): image.fix_alpha_edges()
				result = ImageTexture.create_from_image(image)
	_textures[relative] = result
	return result

## An imported TrueType font, cached; null when missing.
static func font(relative: String) -> Font:
	if _fonts.has(relative): return _fonts[relative]
	var result: Font = null
	if exists(relative):
		var f := FontFile.new()
		# The Godot importer's result for these fonts differs from a plain FontFile only here (probed on 4.7.2).
		f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
		f.data = bytes(relative)
		if not f.data.is_empty(): result = f
	_fonts[relative] = result
	return result

## Drops cached textures and fonts and resolves again (after a re-import, or a test switching folders). `new_root` is a
## loose folder, or PACK_ROOT after mount().
static func reset(new_root: String = "") -> void:
	_textures.clear()
	_fonts.clear()
	_prepared = -1
	_root = ""
	if new_root != "":
		_root = new_root if new_root == PACK_ROOT else _normalise(new_root)
		_source_import = false

## Mounts a data pack (wbc3-data.pck) so its files appear under PACK_ROOT; false when it cannot be read.
static func mount(pack_file: String) -> bool:
	return FileAccess.file_exists(pack_file) and ProjectSettings.load_resource_pack(pack_file, false)

## Applies the alpha border fix to every PNG under the data folder, in place, on all cores, then writes prepared.json.
## `progress` (optional) is called on the calling thread with (done, total). Returns the number of PNGs, or -1 when a
## file could not be read or written (no marker is written then, so the game keeps fixing at load time).
static func prepare(progress: Callable = Callable()) -> int:
	var files := _files(root(), [".png"])
	var state := {done = 0, failed = 0, mutex = Mutex.new()}
	var work := func(i: int):
		var image := Image.load_from_file(files[i])
		var ok := image != null and not image.is_empty()
		if ok:
			image.fix_alpha_edges()
			ok = image.save_png(files[i]) == OK
		state.mutex.lock()
		state.done += 1
		if not ok: state.failed += 1
		state.mutex.unlock()
	var task := WorkerThreadPool.add_group_task(work, files.size(), -1, true, "prepare assets")
	while not WorkerThreadPool.is_group_task_completed(task):
		if progress.is_valid():
			state.mutex.lock()
			var done: int = state.done
			state.mutex.unlock()
			progress.call(done, files.size())
		OS.delay_msec(250)
	WorkerThreadPool.wait_for_group_task_completion(task)
	if progress.is_valid(): progress.call(files.size(), files.size())
	if state.failed > 0: return -1
	var f := FileAccess.open(path(PREPARED), FileAccess.WRITE)
	if f == null: return -1
	f.store_string(JSON.stringify({version = PREPARED_VERSION, pngs = files.size(), engine = Engine.get_version_info().string}))
	f.close()
	_prepared = -1
	_textures.clear()
	return files.size()

## Writes every file of the (loose, prepared) data folder into one data pack at `pack_file`: first to a .tmp beside
## it, replaced only when complete. `progress` gets (done, total) while files are added. Returns the number of files,
## or -1. Never from a mounted pack or this project's own assets/.
static func pack(pack_file: String, progress: Callable = Callable()) -> int:
	if packed() or root() == _project_assets(): return -1
	var files := _files(root(), [])
	var temp := pack_file + ".tmp"
	var packer := PCKPacker.new()
	if packer.pck_start(temp) != OK: return -1
	var total := 0
	for i in files.size():
		var relative := files[i].trim_prefix(root())
		if packer.add_file(PACK_ROOT + relative, files[i]) != OK: return -1
		total += FileAccess.get_size(files[i])
		if progress.is_valid() and i % 200 == 0: progress.call(i, files.size())
	if packer.flush(false) != OK: return -1
	if progress.is_valid(): progress.call(files.size(), files.size())
	if FileAccess.get_size(temp) < total: return -1                 # every byte is in the pack
	if FileAccess.file_exists(pack_file) and DirAccess.remove_absolute(pack_file) != OK: return -1
	if DirAccess.rename_absolute(temp, pack_file) != OK: return -1
	return files.size()

## Deletes the loose data folder after pack(): its files, then its folders. Refuses this project's own assets/.
static func remove_loose() -> bool:
	var dir := root()
	if packed() or dir == _project_assets() or not FileAccess.file_exists(dir + PREPARED): return false
	for file in _files(dir, []):
		if DirAccess.remove_absolute(file) != OK: return false
	var folders := _folders(dir)
	folders.reverse()                    # deepest first
	for folder in folders: DirAccess.remove_absolute(folder)
	return DirAccess.remove_absolute(dir.trim_suffix("/")) == OK

## Every file under `dir` (absolute paths), recursively; `suffixes` limits them (lower case), [] for all. Godot's
## .import sidecars never belong to the data.
static func _files(dir: String, suffixes: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for f in DirAccess.get_files_at(dir):
		var lower := f.to_lower()
		if lower.ends_with(".import"): continue
		if suffixes.is_empty() or suffixes.any(func(s): return lower.ends_with(s)): out.append(dir + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir + d + "/", suffixes))
	return out

static func _folders(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(dir):
		out.append(dir + d)
		out.append_array(_folders(dir + d + "/"))
	return out

static func _project_assets() -> String:
	return _normalise(ProjectSettings.globalize_path("res://assets/"))

static func _resolve() -> String:
	var args := OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in args:
		if String(arg).begins_with("--assets="): return _normalise(String(arg).trim_prefix("--assets="))
	for arg in args:
		if String(arg).begins_with("--data-pack=") and mount(String(arg).trim_prefix("--data-pack=")): return PACK_ROOT
	var env := OS.get_environment("WBC3_ASSETS")
	if env != "": return _normalise(env)
	if not OS.has_feature("template"):
		return _project_assets()
	var exe_dir := OS.get_executable_path().get_base_dir()
	# The prepare pass works on the loose folder (also when an older pack is still there, during a re-import).
	if not "--prepare-assets" in args and mount(exe_dir.path_join(PACK_FILE)): return PACK_ROOT
	var beside := exe_dir.path_join("assets")
	if DirAccess.dir_exists_absolute(beside): return _normalise(beside)
	return _normalise(OS.get_user_data_dir().path_join("assets"))

static func _normalise(dir: String) -> String:
	var d := dir.replace("\\", "/")
	return d if d.ends_with("/") else d + "/"
