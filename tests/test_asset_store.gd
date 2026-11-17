extends SceneTree
## PACKAGING.md step 1: asset_store.gd reads the imported data from one absolute folder, so an exported build can find the
## player's import outside the .pck. Checks: a source run resolves to this project's assets/; textures, fonts, JSON and
## bytes load from there and match the Godot-imported versions in size; a copy of a few files in another folder is read
## from that folder alone after reset(); prepare() bakes exactly Image.fix_alpha_edges into the copies and marks the
## folder; a missing folder gives null / false without errors; no game script outside
## tests/ still names res://assets/ (asset_store.gd's own source-run fallback excepted).
##   Godot --headless --path . --script res://tests/test_asset_store.gd

const Assets = preload("res://core/asset_store.gd")
const SAMPLE_TEXTURES := ["ui_bm_BM_SKILLICONS.png", "ui_x_SelectionRings.png", "terrain/TAA0.png", "maps/desert-sands/collision_walk.png"]
const SAMPLE_FONT := "ui_font_MainFont.ttf"

var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		if failures <= 10: printerr("Asset store check failed: " + label)

func run():
	Assets.reset()
	check(Assets.root() == ProjectSettings.globalize_path("res://assets/").replace("\\", "/"), "source run root: " + Assets.root())
	check(Assets.imported(), "assets/catalogue.json present")
	check(Assets.json("catalogue.json") is Dictionary, "catalogue parses")
	check(Assets.json("no_such_file.json") == null, "missing JSON is null")
	for name in SAMPLE_TEXTURES:
		var t := Assets.texture(name)
		var imported: Texture2D = load("res://assets/" + name)
		check(t != null and imported != null and t.get_size() == imported.get_size(), "texture " + name)
		check(Assets.texture(name) == t, "texture cache " + name)
		check(t is CompressedTexture2D, "source run uses Godot's import: " + name)
	var font := Assets.font(SAMPLE_FONT)
	check(font != null and font.get_string_size("Battlecry", HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x > 0, "font " + SAMPLE_FONT)
	check(Assets.bytes("terrain/TAA0.png").size() == FileAccess.get_file_as_bytes("res://assets/terrain/TAA0.png").size(), "bytes")
	check(MapData().texture("collision_walk.png", "desert-sands") != null, "map texture through MapData")

	# A separate folder with a few files only: everything comes from there after reset().
	var other := ProjectSettings.globalize_path("res://.local/asset-store-test/")
	DirAccess.make_dir_recursive_absolute(other + "terrain")
	DirAccess.remove_absolute(other + Assets.PREPARED)
	for name in ["catalogue.json", "terrain/TAA0.png", SAMPLE_FONT, "ui_x_SelectionRings.png"]:
		var bytes := FileAccess.get_file_as_bytes("res://assets/" + name)
		var f := FileAccess.open(other + name, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
	Assets.reset(other)
	check(Assets.root() == other.replace("\\", "/"), "reset root")
	check(Assets.imported() and Assets.texture("terrain/TAA0.png") != null and Assets.font(SAMPLE_FONT) != null, "copied files load")
	check(Assets.texture("ui_bm_BM_SKILLICONS.png") == null and not Assets.exists("art.json"), "files not copied are absent")
	check(not Assets.prepared() and Assets.texture("terrain/TAA0.png") is ImageTexture, "unprepared copy decodes PNGs")
	var expected := {}
	for name in ["terrain/TAA0.png", "ui_x_SelectionRings.png"]:
		var image := Image.load_from_file(other + name)
		image.fix_alpha_edges()
		expected[name] = image
	var calls := [0]
	check(Assets.prepare(func(_d, _t): calls[0] += 1) == 2, "prepare counts two PNGs")
	check(calls[0] >= 1 and Assets.prepared(), "prepare reports progress and writes the marker")
	for name in expected:
		var baked := Image.load_from_file(other + name)
		check(baked.get_size() == expected[name].get_size() and baked.get_data() == expected[name].get_data(), "prepared pixels equal fix_alpha_edges: " + name)
	check(Assets.prepare() == 2, "prepare again")
	check(Image.load_from_file(other + "ui_x_SelectionRings.png").get_data() == expected["ui_x_SelectionRings.png"].get_data(), "prepare is idempotent")

	# The installer's data pack: the prepared folder into one .pck, the loose folder removed, the pack mounted.
	var pack_file := ProjectSettings.globalize_path("res://.local/asset-store-test.pck")
	var catalogue_text := Assets.text("catalogue.json")
	var font_bytes := Assets.bytes(SAMPLE_FONT)
	var calls_pack := [0]
	check(Assets.pack(pack_file, func(_d, _t): calls_pack[0] += 1) == 5, "pack writes the five files (four copies and prepared.json)")
	check(calls_pack[0] >= 1 and FileAccess.file_exists(pack_file) and not FileAccess.file_exists(pack_file + ".tmp"), "pack reports progress, no .tmp left")
	check(Assets.remove_loose() and not DirAccess.dir_exists_absolute(other), "loose folder removed after packing")
	check(Assets.mount(pack_file), "pack mounts")
	Assets.reset(Assets.PACK_ROOT)
	check(Assets.packed() and Assets.imported() and Assets.prepared(), "mounted pack: imported and prepared")
	check(Assets.text("catalogue.json") == catalogue_text and Assets.bytes(SAMPLE_FONT) == font_bytes, "pack bytes equal the folder's")
	for name in expected:
		var t := Assets.texture(name)
		check(t is ImageTexture and t.get_size() == Vector2(expected[name].get_size()), "texture from the pack: " + name)
	check(Assets.font(SAMPLE_FONT) != null and Assets.texture("ui_bm_BM_SKILLICONS.png") == null, "font from the pack; absent files stay absent")
	check(Assets.pack(pack_file + "2") == -1 and not Assets.remove_loose(), "a mounted pack is never packed or removed")
	DirAccess.remove_absolute(pack_file)

	Assets.reset(other + "missing")
	check(not Assets.imported() and Assets.texture("terrain/TAA0.png") == null and Assets.font(SAMPLE_FONT) == null, "missing folder")
	Assets.reset()

	# No runtime script reads res://assets/ directly any more.
	for file in game_scripts("res://"):
		if file == "res://core/asset_store.gd": continue
		var text := FileAccess.get_file_as_string(file)
		for line in text.split("\n"):
			if line.contains("res://assets") and not line.strip_edges().begins_with("#"):
				check(false, "%s still names res://assets: %s" % [file, line.strip_edges()])
	checks += 1

	if failures > 0:
		print("Asset store checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Asset store checks passed: %d" % checks)
	quit(0)

func MapData():
	return load("res://core/map_data.gd")

func game_scripts(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"): out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		if d.begins_with(".") or d in ["tests", "tools", "assets", "addons"]: continue
		out.append_array(game_scripts(dir.path_join(d)))
	return out
