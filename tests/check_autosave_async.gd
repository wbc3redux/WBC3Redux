extends SceneTree
## P-4 check (not part of -Check): the timed autosave written on a worker thread (main_save.gd autosave_async,
## save_game.gd write_async) holds the same modules and checksums as a save document made at the same moment, and loads.
##   Godot --headless --path . --script res://tests/check_autosave_async.gd
const Setup = preload("res://simulation/skirmish_setup.gd")
const Settings = preload("res://simulation/game_settings.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const MapData = preload("res://core/map_data.gd")

var checks := 0
var failed := 0

func check(ok: bool, what: String):
	checks += 1
	if not ok:
		failed += 1
		printerr("FAILED: " + what)

func _initialize():
	call_deferred("run")

func run():
	Settings.use_file("user://autosave-async-settings.cfg")
	MapData.select("forest-lakes")
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var setup := Setup.defaults(MapData.map())
	for i in int(setup.sides): Setup.set_kind(setup, i, Setup.COMPUTER, 6)
	check(scene.start_skirmish(setup, "", null, "autosave-async"), "the match starts")
	scene.set_physics_process(false)
	scene.save_directory = "user://autosave-async"
	for i in 40 * 90: scene.simulation_step(0.025)
	var path: String = scene.save_path(true)
	if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	var before: Dictionary = scene._save.save_document()
	check(SaveGame.errors.is_empty(), "the document has no capture errors")
	var t := Time.get_ticks_usec()
	scene._save.autosave_async()
	var main_ms := (Time.get_ticks_usec() - t) / 1000.0
	check(SaveGame._pending != -1, "a write is pending after autosave_async")
	var r: Dictionary = SaveGame.read(path)                  # waits for the pending write
	check(SaveGame._pending == -1, "read waited for the write")
	check(bool(r.ok), "the autosave reads back: " + String(r.get("error", "")))
	if r.ok:
		check(r.document.modules.keys() == before.modules.keys(), "the same modules in the same order")
		var same := true
		for key in before.modules: same = same and String(r.document.modules.get(key, "")) == String(before.modules[key])
		check(same, "every module's data is the same as the direct document's")
		check(r.document.checksums == before.checksums, "the same checksums")
		check(int(r.document.game_ms) == int(before.game_ms), "the same game time")
	# A second autosave keeps the first as .bak, and a direct save after an async one waits for it.
	scene._save.autosave_async()
	check(scene._save.autosave() == "", "a direct autosave right after an async one succeeds")
	check(FileAccess.file_exists(path + ".bak"), "the previous autosave is kept as .bak")
	check(bool(SaveGame.read(path).ok), "the last autosave reads back")
	scene.end_skirmish()
	scene.free()
	if failed == 0: print("Autosave async checks passed: %d (main thread part %.0f ms)" % [checks, main_ms])
	quit(1 if failed > 0 else 0)
