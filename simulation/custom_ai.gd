extends RefCounted
## Milestone AI-4: the CustomAI personality files (AI_RESEARCH.md section "AI-4").
##
## * Listing (Read, the PNL_SELECTAIFILE fill in panel 0x157's callback at 0x4ee53c): every `*.ai` file of the CustomAI
##   folders (0x40e270: the install's folder, then the user folder) whose 0x38-byte header names the slot's race or -1
##   (header +0x34, filter 0x4eebe0). The first entry is game text 0x126 "None". An entry reads the localized name table
##   0x58a440 by the file's base name, else the header's name (+0x1e); the table's source is Open, the header name is used.
## * Loading (Emulated, tests/ai4_fixtures.json "loader", 0x4f7460 -> 0x4f76d0): the header must read 0x20f8, 0x30, 4, 4,
##   0x20b4 and "AIED_V1.0"; then the next 0x20f8 bytes are the profile itself. Otherwise the file is refused and the
##   profile keeps the defaults of 0x4f7560 (only the header's name is copied to +0x20f8). **Every one of the 14 files of
##   the install is refused**: they carry an older layout (0x18d8 / 0x1894), so a skirmish computer that selects one of
##   them plays with the defaults, as in the original.
## * Applying (Read, AI_RESEARCH.md AI-4): ai_player.gd reads the fields below from a loaded profile.

const HEADER_SIZE := 0x38
const PROFILE_SIZE := 0x20f8
const MAGIC := "AIED_V1.0"
const NONE_TEXT := 0x126                 # game text "None", the list's first entry
const NONE_LABEL := 0x216                # "Custom AI: None", the button text without a file
const USER_FOLDER := "user://CustomAI"

## The CustomAI folders in 0x40e390's order: the installation's (the nearest folder above the project holding
## "CustomAI", as credits_text.gd finds the install), then the user's.
static func folders() -> Array:
	var out: Array = []
	var dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	while dir.length() > 3:
		var candidate := dir.path_join("CustomAI")
		if DirAccess.dir_exists_absolute(candidate):
			out.append(candidate)
			break
		dir = dir.get_base_dir()
	out.append(ProjectSettings.globalize_path(USER_FOLDER))
	return out

## The 0x38-byte header of a file, or {} when it cannot be read: {words: [5], magic, name, race}.
static func header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var raw := f.get_buffer(HEADER_SIZE)
	f.close()
	if raw.size() < HEADER_SIZE: return {}
	return {"words": [raw.decode_u32(0), raw.decode_u32(4), raw.decode_u32(8), raw.decode_u32(0xc), raw.decode_u32(0x10)],
		"magic": _c_string(raw, 0x14, 10), "name": _c_string(raw, 0x1e, 0x16), "race": raw.decode_s32(0x34)}

static func _c_string(raw: PackedByteArray, at: int, length: int) -> String:
	var out := PackedByteArray()
	for i in length:
		if at + i >= raw.size() or raw[at + i] == 0: break
		out.append(raw[at + i])
	return out.get_string_from_ascii()

## The entries of the selection list for a slot of `race` (0x4eebe0: header race -1 or the slot's race), in folder order
## and, inside a folder, by file name (the directory walk 0x402ad0 returns NTFS order). [{file, path, label, race}]
static func list(race: int, paths: Array = []) -> Array:
	var out: Array = []
	for folder in (paths if not paths.is_empty() else folders()):
		var d := DirAccess.open(folder)
		if d == null: continue
		var names: Array = []
		for file in d.get_files():
			if file.get_extension().to_lower() == "ai": names.append(file)
		names.sort_custom(func(a, b): return a.to_lower() < b.to_lower())
		for file in names:
			var path := String(folder).path_join(file)
			var h := header(path)
			if h.is_empty(): continue
			if int(h.race) != -1 and int(h.race) != race: continue
			out.append({"file": file, "path": path, "label": String(h.name) if String(h.name) != "" else file.get_basename(), "race": int(h.race)})
	return out

## 0x40e390(name, 3, 0): the first folder that holds the file.
static func resolve(file: String) -> String:
	if file == "": return ""
	for folder in folders():
		var path := String(folder).path_join(file)
		if FileAccess.file_exists(path): return path
	return ""

## 0x4f76d0 on bytes: {"loaded": bool, "name": header name, "profile": fields or {} (refused)}.
static func parse(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < HEADER_SIZE: return {"loaded": false, "name": "", "profile": {}}
	var name := _c_string(bytes, 0x1e, 0x16)
	var ok := bytes.decode_u32(0) == PROFILE_SIZE and bytes.decode_u32(4) == 0x30 and bytes.decode_u32(8) == 4 \
		and bytes.decode_u32(0xc) == 4 and bytes.decode_u32(0x10) == 0x20b4 and _c_string(bytes, 0x14, 10) == MAGIC
	if not ok or bytes.size() < HEADER_SIZE + PROFILE_SIZE: return {"loaded": false, "name": name, "profile": {}}
	return {"loaded": true, "name": name, "profile": fields(bytes.slice(HEADER_SIZE, HEADER_SIZE + PROFILE_SIZE))}

static func load_file(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path): return {"loaded": false, "name": "", "profile": {}}
	return parse(FileAccess.get_file_as_bytes(path))

## The profile fields the computer player reads (offsets of the 0x210c-byte profile, 0x4f7560 defaults in brackets):
## +4 word (-1: every unit / research priority 50), unit slots +0xc + 8i (enabled, priority; 30), research slots
## +0xfc + 8i (40), +0x20b8.. the category percentages (0x4ffab0, used when +0x20ba is set), +0x20bc danger margin (50),
## +0x20bd conversion share (20), +0x20c1 hero retreat (1), group minimum / maximum sizes +0x20c8 / +0x20e0.
static func fields(raw: PackedByteArray) -> Dictionary:
	var units: Array = []
	for i in 30: units.append([raw[0xc + 8 * i], raw[0xd + 8 * i]])
	var research: Array = []
	for i in 40: research.append([raw[0xfc + 8 * i], raw[0xfd + 8 * i]])
	var mins: Array = []
	var maxs: Array = []
	for i in 6:
		mins.append(raw.decode_s32(0x20c8 + 4 * i))
		maxs.append(raw.decode_s32(0x20e0 + 4 * i))
	return {"word_4": raw.decode_s16(4), "units": units, "research": research,
		"category": [raw[0x20b8], raw[0x20b9], raw[0x20bb], raw[0x20be], raw[0x20ba]] if raw[0x20ba] != 0 else [],
		"danger_margin": raw[0x20bc], "conversion_share": raw[0x20bd], "slow_to_mines_any": raw[0x20c2] != 0, "hero_retreats": raw[0x20c1] != 0,
		"home_moves": raw[0x20c0] != 0,                  # AI-9: 0x4fbdf0's home move (0x4f7560 default 1)
		"group_min": mins, "group_max": maxs, "outpost_weights": [raw[0x20c4], raw[0x20c3], raw[0x20c5], raw[0x20c6]]}

## The priority a list entry gets from the profile (0x4fc700 units, 0x4fc770 research): 50 while the +4 word is -1,
## else the slot's priority when enabled and -1 when not. `index` is the entry's place in the AI's list.
static func priority(profile: Dictionary, kind: String, index: int) -> int:
	if profile.is_empty() or int(profile.word_4) == -1: return 50
	var slots: Array = profile.get(kind, [])
	if index < 0 or index >= slots.size(): return 50
	return int(slots[index][1]) if int(slots[index][0]) != 0 else -1
