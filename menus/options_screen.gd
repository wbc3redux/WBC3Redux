extends "res://core/ui_screen.gd"
## The options screen (0x411110, milestone 11-menus; UI_RESEARCH.md "Milestone 11"), shared by the main menu and the
## match. PNL_GAMEOPTIONS (0x119) at layer 20000; ten droplists per tab (0x410760 / 0x410af0 / 0x4101e0); Okay saves
## (0x414160) and closes, Cancel restores the copy taken on entry (0x74a3d0) and closes; Credits (0x4069e0, R-1) opens
## PNL_WBC3CREDITS at layer 50000 with the lines of credits_text.gd until its Okay (0x4b -> 0x406ac0).
## Hover help on Okay / Cancel / Credits: TXT_OPTIONS_HELP_NEW1 on the message line.
##
## DELIBERATE MODERN CHANGES (display.gd, DISPLAY_SETTINGS.md):
## * A fourth tab, Advanced: the original's three radio buttons (BUTT_GAMEOPTIONS_OPTION, x 200 / 360 / 510) move to
##   x 130 / 280 / 430 and a copy of the radio at x 580 opens the display settings (display.gd advanced_rows), shown in
##   the same droplist rows. Window mode, monitor and size apply when chosen; the message line asks to keep them with
##   Okay and they revert after REVERT_SECONDS, or on Cancel.
## * A fifth tab, Visuals (ENHANCED_VISUALS.md): a second copy of the radio; the five radios sit at TAB_X. Its rows are
##   display.gd visual_rows (the enhanced visuals switches), applied when chosen and saved with Okay. It has twelve rows:
##   two more droplists (VISUAL_EXTRA_Y, one per column) below the original ten, and the processor / memory / version
##   lines under them are left empty on this tab.
## * Graphics: the Resolution row reads "Resolution: Native" and opens the Advanced tab; Gamma Correction is applied
##   (display.gd brightness).
## * In a match the screen opens over the paused match (game_hud.gd), with the match dimmed around it.
## * Gameplay rows 8 and 9 (empty in the original) hold "Battle Rules" and "Health Bars" (modern_rules.gd).
## * B1-3: a third modern Gameplay row, "Day / Night: On / Off" (simulation/day_night.gd), as an extra droplist (instance
##   10) under the left column at VISUAL_EXTRA_Y like the Visuals tab's; the processor / memory / version lines under it
##   are left empty on this tab too.
## * S-1 (COMPLAINTS_AND_FIXES.md F8): a fourth, "Autosave: Every 5 / 10 / 15 min / Off" (simulation/save_game.gd, default
##   every 10 minutes), the extra droplist under the right column (instance 11).
##
## Use: add an instance to the tree; `in_game` before adding; `closed` is emitted after Okay or Cancel.

const Settings = preload("res://simulation/game_settings.gd")
const ModernRules = preload("res://simulation/modern_rules.gd")
const DayNight = preload("res://simulation/day_night.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const GAMEPLAY := 0

const OPTIONS := "PNL_GAMEOPTIONS"
const CREDITS := "PNL_WBC3CREDITS"
const CreditsText = preload("res://menus/credits_text.gd")
const VERSION := "1.03"                     # 0x608308
const ADVANCED := 3
const VISUALS := 4
const TAB_X := [130, 247, 360, 466, 582]   # modern change: five tabs in the banner (the original three at 200 / 360 / 510)
const REVERT_SECONDS := 15.0
const VISUAL_EXTRA_Y := 389                # the sixth droplist row of the Visuals tab (the original rows are 35 apart)

signal closed(saved: bool)
signal modern_changed                       # a Gameplay modern row (modern_rules.gd) changed: the match applies it at once

var in_game := false
var settings
var settings_copy: Dictionary = {}
var display_copy: Dictionary = {}
var modern_copy: Dictionary = {}
var day_night_copy := true
var autosave_copy := SaveGame.AUTOSAVE_DEFAULT
var page := 0
var start_page := 0                         # the tab open() shows first (front_end.gd first start: ADVANCED)
var drop_row := -1                          # the droplist instance whose list is open (0x45cfe0), or -1
var message := ""
var window_before: Dictionary = {}          # the window group before an unconfirmed change ({} = nothing to revert)
var revert_left := 0.0
var shade: ColorRect

func _ready():
	if in_game:
		shade = ColorRect.new()
		shade.color = Color(0, 0, 0, 0.6)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE        # sized by place_view
		add_child(shade)
	setup_screen()
	if in_game: RenderingServer.set_default_clear_color(Color.BLACK)
	settings = Settings.current()
	open()

## The 800x600 screen as ui_screen places it; in a match the shade covers the whole window around it.
func place_view():
	super()
	if shade != null:
		shade.position = -global_position
		shade.size = get_viewport_rect().size

func open():
	canvas.placements.clear()
	canvas.control_text.clear()
	canvas.control_state.clear()
	settings_copy = settings.snapshot()                            # 0x411110: copy of 0x70d6ac into 0x74a3d0
	display_copy = DisplayConfig.snapshot()
	modern_copy = ModernRules.snapshot()
	DayNight.ensure_loaded()
	day_night_copy = DayNight.setting
	autosave_copy = SaveGame.autosave_setting()
	page = start_page
	canvas.placements.append({panel = panel_with_tabs(), offset = Vector2i.ZERO, layer = 20000})
	refresh()

## PNL_GAMEOPTIONS with the radio row moved left and a fourth and fifth radio (modern change); on the Visuals tab two
## more droplists (instances 10 and 11) under the two columns.
func panel_with_tabs() -> Dictionary:
	var panel: Dictionary = canvas.panel_by_name(OPTIONS).duplicate(true)
	var radio: Dictionary = {}
	for control in panel.controls:
		if control.name == "BUTT_GAMEOPTIONS_OPTION":
			control.position = [TAB_X[int(control.instance)], control.position[1]]
			radio = control
	for extra in [ADVANCED, VISUALS]:
		var copy: Dictionary = radio.duplicate(true)
		copy.instance = extra
		copy.position = [TAB_X[extra], radio.position[1]]
		panel.controls.append(copy)
	if page == VISUALS or page == GAMEPLAY:
		var columns: Array = []
		for control in panel.controls:
			if control.name == "BUTT_OPTIONS_DROPLIST" and int(control.instance) in [4, 9]: columns.append(control)
		for control in columns:
			var copy: Dictionary = control.duplicate(true)
			copy.instance = 10 if int(control.instance) == 4 else 11
			copy.position = [control.position[0], VISUAL_EXTRA_Y]
			panel.controls.append(copy)
	return panel

## The modern tabs (Advanced, Visuals) use display.gd rows; the first three the original's.
func modern_page() -> bool:
	return page >= ADVANCED

func opt_key(control: String, instance: int = 0) -> String:
	return "%s/%s#%d" % [OPTIONS, control, instance]

# ------------------------------------------------------------------------------------------------ rows
## The rows of the current tab: the original's (game_settings.gd page_rows) or the Advanced ones (display.gd).
func rows() -> Array:
	if page == VISUALS: return DisplayConfig.visual_rows()
	if page == ADVANCED: return DisplayConfig.advanced_rows(get_window())
	var list := Settings.page_rows(page)
	if page == 0: list = list.slice(0, 8) + ModernRules.gameplay_rows() + [DayNight.gameplay_row(), SaveGame.gameplay_row()]   # modern change: rows 8..11
	return list

## A row of the modern tabs (Advanced, Visuals) or a modern row (modern_rules.gd) is shown like an Advanced one.
func is_plain(row: Dictionary) -> bool:
	return modern_page() or row.get("modern", false)

func refresh():
	var t := canvas.control_text
	var s := canvas.control_state
	t.clear()
	s.clear()
	t[opt_key("STR_LARGE750")] = string_at(0, 3)                                         # "Options" (0x464cc0(0, 3))
	for i in TAB_X.size():
		var tab_name: String = {ADVANCED: "Advanced", VISUALS: "Visuals"}.get(i, "")
		t[opt_key("BUTT_GAMEOPTIONS_OPTION", i)] = tab_name if tab_name != "" else string_at(0x103, i)   # Gameplay, Graphics, Sound
		s[opt_key("BUTT_GAMEOPTIONS_OPTION", i)] = 2 if i == page else 0                  # the selected radio (0x45c740 group 9)
	if page != VISUALS and page != GAMEPLAY:                                              # the extra droplist row sits there
		t[opt_key("STR_MEDIUM200", 0)] = string_at(0x104, 4) % OS.get_processor_name().left(20)
		t[opt_key("STR_MEDIUM200", 1)] = string_at(0x104, 5) % int(OS.get_memory_info().get("physical", 0) / 1048576)
		t[opt_key("STR_MEDIUM200", 2)] = string_at(0x104, 6) % VERSION
	t[opt_key("STR_MEDIUM500")] = message
	var list := rows()
	for i in list.size():
		t[opt_key("BUTT_OPTIONS_DROPLIST", i)] = row_label(list[i])
		if String(list[i].key) == "" or list[i].get("disabled", false): s[opt_key("BUTT_OPTIONS_DROPLIST", i)] = 3
	canvas.queue_redraw()

## The button text of one droplist row (0x410760 / 0x410af0 / 0x4101e0; Advanced: display.gd).
func row_label(row: Dictionary) -> String:
	if is_plain(row): return "" if String(row.key) == "" else DisplayConfig.row_text(row)
	var row_key := String(row.key)
	if row_key == "": return ""
	if row_key == "Soundtrack":
		return String(audio().manifest.get("soundtrack", {}).get("title", "Soundtrack: Battlecry III"))
	if row_key == "EAXOn": return String(string_at(0x10c, 6)).replace("%s", string_at(0x109, 5))
	if row_key == "ResolutionSelected": return String(string_at(0x10a, 0)).replace("%s", "Native")   # modern change
	var text := choice_text(row.choices[settings.choice_index(row)])
	if row.has("format"): return String(string_at(int(row.format[0]), int(row.format[1]))).replace("%s", text)
	return text

func choice_text(choice: Array) -> String:
	if modern_page(): return String(choice[0])
	if choice[0] is String and choice[0] == "game": return game_text(int(choice[1]))
	return String(string_at(int(choice[0]), int(choice[1]))).strip_edges()

func drop_labels() -> Array:
	if drop_row < 0: return []
	if is_list_open(): return list_labels
	var row: Dictionary = rows()[drop_row]
	if is_plain(row): return row.choices.map(func(c): return String(c[0]))
	return row.choices.map(func(c): return choice_text(c))

func open_drop(row: int):
	var list := rows()
	if String(list[row].key) == "" or list[row].choices.is_empty() or list[row].get("disabled", false): return
	if page != ADVANCED and String(list[row].key) == "ResolutionSelected":
		select_page(ADVANCED)                                       # modern change: native resolution lives there
		return
	drop_row = row
	var current: int = int(list[row].current) if is_plain(list[row]) else settings.choice_index(list[row])
	open_list(drop_labels(), list_point(opt_key("BUTT_OPTIONS_DROPLIST", row)), func(i): choose(row, i), current)

## A dropdown choice: the callback stores the value (0x40fd40..0x4101cb) and the page is redrawn; sound values apply at
## once (the music callback 0x40ff20 calls 0x510420 directly; the effects volume is read where it is used).
func choose(row: int, choice: int):
	var list := rows()
	drop_row = -1
	close_list()
	if page == ADVANCED:
		choose_advanced(list[row], choice)
	elif page == VISUALS:
		DisplayConfig.set_visual(String(list[row].key), list[row].choices[choice][1])
		apply_settings()
	elif list[row].get("modern", false):
		if String(list[row].key) == "DayNight": DayNight.set_setting(bool(list[row].choices[choice][1]))
		elif String(list[row].key) == "Autosave": SaveGame.set_autosave(int(list[row].choices[choice][1]))
		else: ModernRules.choose(String(list[row].key), bool(list[row].choices[choice][1]))
		modern_changed.emit()
	else:
		settings.set_value(String(list[row].key), int(list[row].choices[choice][2]))
		apply_settings()
	refresh()

func choose_advanced(row: Dictionary, choice: int):
	var before := DisplayConfig.window_snapshot()
	if DisplayConfig.set_choice(String(row.key), row.choices[choice][1]):
		if window_before.is_empty(): window_before = before
		revert_left = REVERT_SECONDS
		DisplayConfig.apply_window(get_window())
		update_revert_message()
	apply_settings()

func apply_settings():
	audio().apply_settings(settings)
	var manager := DisplayConfig.node(get_tree())
	if manager != null: manager.apply_runtime()

func select_page(new_page: int):
	page = new_page
	drop_row = -1
	close_list()
	canvas.placements[0].panel = panel_with_tabs()                  # the Visuals tab's two extra droplists come and go
	refresh()

# ------------------------------------------------------------------------------------------------ window revert
func update_revert_message():
	message = "Okay keeps this display mode - reverting in %d s" % ceili(maxf(revert_left, 0.0))
	canvas.control_text[opt_key("STR_MEDIUM500")] = message
	canvas.queue_redraw()

## Puts the window group back (the timer ran out, or Cancel).
func revert_window():
	if window_before.is_empty(): return
	DisplayConfig.restore_window(window_before)
	window_before = {}
	DisplayConfig.apply_window(get_window())
	message = ""
	apply_settings()
	refresh()

## 0x4069e0: the credits over the options; the list comes from the installation. Nothing opens without it.
var credit_lines: Array = []
var credit_state: Dictionary = {}
var credit_ms := 0.0

func open_credits() -> bool:
	credit_lines = CreditsText.read_lines(CreditsText.installed_path())
	if credit_lines.is_empty(): return false
	credit_state = CreditsText.new_state()
	credit_ms = 0.0
	place(CREDITS, Vector2i.ZERO, 50000)
	canvas.overlay_text = draw_credits
	canvas.queue_redraw()
	return true

func close_credits():
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != CREDITS)
	canvas.overlay_text = Callable()
	credit_lines = []
	canvas.queue_redraw()

func draw_credits():
	for line in CreditsText.lay_out(credit_lines, credit_state):
		canvas.draw_text(String(line.text), int(line.font), Rect2i(int(line.x), int(line.y) - 4, 400, 24), HORIZONTAL_ALIGNMENT_LEFT)

func _process(delta: float):
	if not credit_lines.is_empty():
		credit_ms += delta * 1000.0
		while credit_ms >= CreditsText.TICK_MS:
			credit_ms -= CreditsText.TICK_MS
			CreditsText.tick(credit_state)
		canvas.queue_redraw()
	if window_before.is_empty(): return
	revert_left -= delta
	if revert_left <= 0.0: revert_window()
	else: update_revert_message()

# ------------------------------------------------------------------------------------------------ buttons
func press(button_key: String) -> void:
	var control := button_key.get_slice("/", 1).get_slice("#", 0)
	var instance := int(button_key.get_slice("#", 1))
	if button_key.begins_with(CREDITS + "/"):
		if control == "BUTT_OKAY_STARTUP": close_credits()             # 0x406aaa: control 0x4b -> 0x406ac0
		return
	match control:
		"BUTT_CREDITS_200": open_credits()
		"BUTT_GAMEOPTIONS_OPTION": select_page(instance)               # msg 0x11: the radio group changed the page
		"BUTT_OPTIONS_DROPLIST": open_drop(instance)
		"BUTT_OKAY_STARTUP":                                           # 0x411670: save (0x414160(1)) and return
			window_before = {}
			settings.save()
			DisplayConfig.save_settings()
			ModernRules.save_settings()
			DayNight.save_setting()
			SaveGame.save_autosave_setting()
			finish(true)
		"BUTT_CANCEL_STARTUP":                                         # 0x41170d: restore the copy and return
			revert_window()
			settings.restore(settings_copy)
			DisplayConfig.restore(display_copy)
			ModernRules.restore(modern_copy)
			DayNight.set_setting(day_night_copy)
			SaveGame.set_autosave(autosave_copy)
			modern_changed.emit()
			apply_settings()
			finish(false)

func finish(saved: bool):
	close_list()
	closed.emit(saved)
	queue_free()

## Hover help (TXT_OPTIONS_HELP_NEW1 [0..2]) on the message line, unless a display change waits for Okay.
func hovered_changed(entry: Dictionary) -> void:
	if not window_before.is_empty(): return
	var control := String(entry.get("control", {}).get("name", ""))
	var help := {"BUTT_OKAY_STARTUP": 0, "BUTT_CANCEL_STARTUP": 1, "BUTT_CREDITS_200": 2}
	message = string_at(0x104, help[control]) if help.has(control) else ""
	canvas.control_text[opt_key("STR_MEDIUM500")] = message

## A modal screen: every event stops here (the main menu or the match behind gets none).
func _unhandled_input(event: InputEvent):
	var was_open := is_list_open()
	screen_input(event)
	if was_open and not is_list_open(): drop_row = -1
	get_viewport().set_input_as_handled()
