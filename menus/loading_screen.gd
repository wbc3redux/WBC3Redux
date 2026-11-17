extends "res://core/ui_screen.gd"
## The loading screen between the skirmish setup and the match (milestone 11-menus): PNL_PROGRESSHT (0x116), whose
## background is NewLoadingScreen.bmp (BM_PROGRESSHT_BG) and whose bar BM_PROGRESSHT_PROGRESS holds 11 frames
## (1 %, 10 % .. 100 %). The original shows it while 0x4e2790 -> 0x417730 loads the scenario.
##
## Parity pass 2 (UI_RESEARCH.md "Parity pass 2", Read):
## * 0x43c630 opens the panel at layer 2000, writes TXT_LOADING [0] ("Creating Lighting Tables") into STR_SMALLDLG_300 and
##   clears both STR_SMALL700 lines; the shields and names (IM_ICON_SHLDCLRS, STR_SMALL120, STR_SMALL24) are moved off
##   screen outside multiplayer (0x45e410(.., 4000, 4000)).
## * 0x43c970 picks one entry of English/History.xml (a roll 1..number; the file says number="52" although it holds 63
##   entries, so 52..62 never show), writes its Title into STR_MEDIUMPARCH_700 and its paragraphs, word-wrapped, into the 26
##   lines STR_PARCHSMALLMED_250 #0..25 (#0..11 the left page, #12..25 the right one): a blank line after each paragraph,
##   nothing after line 25, and when the whole text is exactly 13 lines line 11 is skipped. The wrap call's arguments are
##   lost in the decompile: the rebuild wraps to the label's 250 pixels in its own font (Open), and the roll's generator is
##   Open (randi).
## * 0x43ce60(percent): the bar frame is percent / 10 (0x87 rows each) and STR_SMALLDLG_300 shows TXT_LOADING [percent / 10]
##   for 0..7 and TXT_LOADING2 [percent / 10 - 8] for 8..10 ("Filling Cache", "Calculating Particle Effects", "Done!").
##   Which load stage reports which percent is not traced: the rebuild steps with Godot's threaded load of main.tscn.
## * RM-7: a Random Map is generated here, after main.tscn is loaded and before it is instanced (main.gd builds from the
##   current map): 0x582180 opens PNL_RM_GENWORLD (0x123, layer 0x8235) with strings 0x121 [0], [1] over this screen and
##   pumps messages while it works (0x582170). The rebuild works on a thread, so the window stays alive; if the map cannot be
##   made the setup screen comes back with the reason (simulation/random_map_match.gd).

const TARGET := "res://battle/main.tscn"
const PANEL := "PNL_PROGRESSHT"
const HISTORY_LINES := 26
const HISTORY_LABEL := "STR_PARCHSMALLMED_250"
const GENERATING := "PNL_RM_GENWORLD"
const GENERATING_LAYER := 0x8235
const Setup = preload("res://simulation/skirmish_setup.gd")
const MapData = preload("res://core/map_data.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")

var progress := 0.0
var map_name := "Desert Sands"
var requested := false
var done := false
var min_frames := 2          # the screen is drawn at least once before the scene switch
var history_index := -1
var worker: Thread = null    # RM-7: the map generation
var made := {}               # its result (read after the thread has ended)
var loaded_scene: PackedScene = null

func _ready():
	setup_screen()
	place(PANEL, Vector2i.ZERO, 2000)
	map_name = "Random" if random_map_due() else MapData.name_of()      # the chosen map (W1)
	for control in ["STR_SMALL24", "STR_SMALL120", "IM_ICON_SHLDCLRS"]:
		for i in 6: canvas.control_text["%s/%s#%d" % [PANEL, control, i]] = ""
	hide_multiplayer_rows()
	show_history()
	refresh()
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("self_test")
		return
	requested = ResourceLoader.load_threaded_request(TARGET) == OK

## RM-7: the setup handed over is a Random Map's and its map is not made yet.
func random_map_due() -> bool:
	var setup: Dictionary = Setup.pending.get("setup", {})
	return not setup.is_empty() and Setup.is_random(setup) and setup.random_map.is_empty()

func start_generation():
	var panel: Dictionary = canvas.panel_by_name(GENERATING).duplicate()
	panel.controls = panel.controls.filter(func(c): return String(c.name) != "IM_GENERATING_ANIM")   # its bitmap is not imported (Open)
	canvas.placements.append({panel = panel, offset = Vector2i.ZERO, layer = GENERATING_LAYER})
	canvas.control_text["%s/STR_LARGE750#0" % GENERATING] = string_at(0x121, 0)
	canvas.control_text["%s/STR_MEDIUMDLG_300#0" % GENERATING] = string_at(0x121, 1)
	canvas.queue_redraw()
	var setup: Dictionary = Setup.pending.setup
	worker = Thread.new()
	worker.start(func(): made = RandomMapMatch.prepare(setup))

## The worker's end. The bundle becomes current here, on the main thread. Returns false when the setup screen comes back.
func finish_generation() -> bool:
	worker.wait_to_finish()
	worker = null
	if not bool(made.get("ok", false)):
		Setup.pending = {}
		Setup.start_error = String(made.get("error", RandomMapMatch.FAILED))
		get_tree().change_scene_to_file("res://menus/skirmish_menu.tscn")
		return false
	MapData.select_generated(made.bundle)
	made = {}
	return true

func _exit_tree():
	if worker != null: worker.wait_to_finish()

## 0x43c630 outside multiplayer: the six shield / name / percent rows and the MP box are moved to (4000, 4000).
func hide_multiplayer_rows():
	var hidden := ["IM_ICON_SHLDCLRS", "STR_SMALL120", "STR_SMALL24", "IM_PROGRESSHT_MP"]
	var panel: Dictionary = canvas.panel_by_name(PANEL)
	var kept := panel.duplicate(true)
	kept.controls = panel.controls.filter(func(c): return not String(c.name) in hidden)
	for p in canvas.placements:
		if p.panel.get("name", "") == PANEL: p.panel = kept

## Frame of the bar for a fraction 0..1: 0 below 10 %, then one frame per 10 %.
static func bar_frame(fraction: float) -> int:
	return clampi(int(fraction * 100.0) / 10, 0, 10)

## 0x43ce60: the status line for a percent value.
func status_text(percent: int) -> String:
	var step := clampi(percent / 10, 0, 10)
	return string_at(0xc2, step) if step < 8 else string_at(0xc3, step - 8)

## 0x43c970's line placement for wrapped paragraphs: returns the 26 lines.
static func history_page(paragraph_lines: Array) -> Array:
	var total := 0
	for lines in paragraph_lines: total += lines.size() + 1
	total -= 1
	var out: Array = []
	out.resize(HISTORY_LINES)
	out.fill("")
	var index := 0
	for lines in paragraph_lines:
		for k in lines.size():
			if total == 13 and index == 11: index = 12
			if index < HISTORY_LINES: out[index] = String(lines[k])
			index += 1
			if k < lines.size() - 1 and index == HISTORY_LINES: return out
		if total == 13 and index == 11: index = 12
		index += 1                                       # the blank line after the paragraph
	return out

func show_history(index: int = -1):
	var entries: Array = layout.get("history", [])
	var count: int = mini(int(layout.get("history_number", entries.size())), entries.size())
	if count <= 0: return
	history_index = index if index >= 0 else randi_range(1, count) - 1
	var entry: Dictionary = entries[history_index]
	canvas.control_text["%s/STR_MEDIUMPARCH_700#0" % PANEL] = String(entry.title)
	var label := item("%s/%s#0" % [PANEL, HISTORY_LABEL])
	var font_number := int(label.element.get("font", 0)) if not label.is_empty() else 0
	var width := float(label.rect.size.x) if not label.is_empty() else 250.0
	var wrapped: Array = []
	for paragraph in entry.paragraphs: wrapped.append(wrap_text(String(paragraph), font_number, width))
	var page := history_page(wrapped)
	for i in HISTORY_LINES: canvas.control_text["%s/%s#%d" % [PANEL, HISTORY_LABEL, i]] = page[i]

func refresh():
	var percent := int(progress * 100.0)
	canvas.control_text["%s/STR_SMALLDLG_300#0" % PANEL] = status_text(percent)
	canvas.control_text["%s/STR_SMALL700#0" % PANEL] = ""
	canvas.control_text["%s/STR_SMALL700#1" % PANEL] = ""
	canvas.control_frame["%s/IM_PROGRESSHT_PROGRESS#0" % PANEL] = bar_frame(progress)
	canvas.queue_redraw()

func _process(_delta: float):
	if worker != null:
		if worker.is_alive() or not finish_generation(): return
		enter_match()
		return
	if not requested or done: return
	var status_progress := []
	var status := ResourceLoader.load_threaded_get_status(TARGET, status_progress)
	if not status_progress.is_empty(): progress = maxf(progress, float(status_progress[0]))
	refresh()
	min_frames -= 1
	if status == ResourceLoader.THREAD_LOAD_LOADED and min_frames <= 0:
		done = true
		progress = 1.0
		refresh()
		loaded_scene = ResourceLoader.load_threaded_get(TARGET)
		if random_map_due(): start_generation()
		else: enter_match()
	elif status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		done = true
		if random_map_due():
			loaded_scene = load(TARGET)
			start_generation()
		else:
			get_tree().change_scene_to_file(TARGET)

func enter_match():
	# 0x417730: with an army budget of 1 or more the army setup screen (0x440b40) opens after loading, then the match.
	if int(Setup.pending.get("setup", {}).get("army_budget", 0)) >= 1:
		preload("res://menus/army_setup_screen.gd").next_scene = loaded_scene
		get_tree().change_scene_to_file("res://menus/army_setup_screen.tscn")
	else:
		get_tree().change_scene_to_packed(loaded_scene)

var checks := 0
var failed := false

func check(condition: bool, text: String):
	checks += 1
	if not condition and not failed:
		failed = true
		push_error("Loading screen check failed: " + text)

func self_test():
	check(has_item("%s/IM_PROGRESSHT_BG#0" % PANEL) and has_item("%s/IM_PROGRESSHT_PROGRESS#0" % PANEL), "PNL_PROGRESSHT placed")
	check(not has_item("%s/IM_ICON_SHLDCLRS#0" % PANEL) and not has_item("%s/IM_PROGRESSHT_MP#0" % PANEL), "multiplayer rows off screen (0x43c630)")
	check(string_at(0x121, 0) == "Generating random map" and string_at(0x121, 1) == "Please wait...", "the generation panel's lines (0x582180)")
	check(bar_frame(0.0) == 0 and bar_frame(0.09) == 0 and bar_frame(0.1) == 1 and bar_frame(0.55) == 5 and bar_frame(1.0) == 10, "bar frames")
	var tex: Texture2D = canvas.texture("BM_PROGRESSHT_PROGRESS")
	check(tex != null and tex.get_height() / 135 == 11, "11 bar frames of 135 rows")
	check(status_text(0) == "Creating Lighting Tables" and status_text(79) == "Initializing 3D Sounds" and status_text(80) == "Filling Cache" and status_text(100) == "Done!", "status lines (TXT_LOADING / TXT_LOADING2)")
	check(canvas.control_text["%s/STR_SMALLDLG_300#0" % PANEL] == "Creating Lighting Tables", "the first status line")
	check(int(layout.get("history_number", 0)) == 52 and layout.history.size() == 63, "History.xml: number 52 of 63 entries")
	check(history_index >= 0 and history_index < 52, "a history entry from the first 52")
	show_history(0)
	check(canvas.control_text["%s/STR_MEDIUMPARCH_700#0" % PANEL] == "The Sundering", "entry 0's title on the book")
	var first_line: String = canvas.control_text["%s/%s#0" % [PANEL, HISTORY_LABEL]]
	check(first_line != "" and String(layout.history[0].paragraphs[0]).begins_with(first_line), "the first paragraph starts the left page")
	# Placement rules: a blank line after each paragraph, the 13-line skip of line 11, nothing past line 25.
	var page := history_page([["a", "b"], ["c"]])
	check(page[0] == "a" and page[1] == "b" and page[2] == "" and page[3] == "c", "a blank line between paragraphs")
	var thirteen := history_page([["1", "2", "3", "4", "5", "6"], ["7", "8", "9", "10", "11", "12"]])
	check(thirteen[10] == "10" and thirteen[11] == "" and thirteen[12] == "11" and thirteen[13] == "12", "13 lines: line 11 skipped")
	var long: Array = []
	for i in 40: long.append(str(i))
	check(history_page([long])[25] == "25", "26 lines at most")
	if not failed: print("Loading screen checks passed: %d" % checks)
	get_tree().quit(1 if failed else 0)
