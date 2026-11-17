extends "res://core/ui_screen.gd"
## The results screens after a skirmish (milestone 10a / 11-menus, parity pass 2), hosted by main.gd's results layer.
##
## Main page (0x454560 -> 0x454b70, Read): PNL_VICTORYDEFEAT_NEW (0x143) at layer 2000; the theme plays (mode 2 won, 3
## lost); the first visit shows the screen help 0x448870(0xe, 0); F1 shows it again. Texts: six counters, the hero's name,
## Victory / Defeat (STR_STATISTICS [4] / [5]), the XP and level lines; VictoryBG / DefeatBG. Hovering Continue (0x4b) or
## Advanced Results (0x175) plays HighlightR.wav (0x60f564) and writes STR_RESULTS_HELP [7] / [6] into control 0x2eee,
## which this panel does not have (nothing shows). Continue -> main.gd (hero screens, main menu).
##
## Advanced results (BUTT_ADVANCEDRESULTS 0x175 -> 0x449ce0, Read): PNL_RESULTS_MAIN (0x144) at layer 30000 with the title
## TXT_RESULTS [1] "Combat Results" and the players' names in STR_PARCHSMALL_L150 #0..5 (the local player first, then the
## other active players in slot order); four pages opened at layer 30001 by the tab buttons 0x14a..0x14d, the tab bar's
## frame showing the page (0x45e410(0x144, 0x53bd, 0, 0, page * 70)):
## * Hero (0x145, 0x44acc0): bars kills (record +0x162), spells cast (+0x166), XP (+0, the local hero's 0x709e18), level
##   (+0x10), games played (+0x14) as the text of control 0x2f34 and two status icons: the skull when the hero died, the
##   medal when it gained a level (IM_RESULTS_STATUS / IM_RESULTS_LEVEL, BM_RESULTS_STATUS frames x 0 / x 24).
## * Resources (0x146, 0x44b0d0): per player an In row (gold, metal, stone, crystal, total) and an Out row (0x518b90
##   counters 0x744c7c.. / 0x744c8c..); when gold or stone Out exceeds In, Out is shown as In - In / 100 x (1..5).
## * Units (0x147, 0x44b430): produced 0x732ee8, lost 0x732eec, total kills 0x732eea, kills by side (the local player's
##   kills of each other side; "-" on the local row).
## * Buildings (0x148, 0x44b630): built 0x739cf0 - converted, lost 0x739cf4, total razed 0x739cf2, converted 0x744d78,
##   razed by side.
## Each value is a bar in the player's colour (bitmaps 0x247 red, 0x244 blue, 0x245 green, 0x246 purple, 0x243 black,
## 0x248 yellow by slot colour) with the number as its text; the bars grow over the first timer ticks (0x44a890: +15 %
## to 60, +5 % to 90, then +1 %). Done (0x176) returns to the main page; F1 shows screen help 0xd (first visit too).
## R-1 (Read): how full a bar ends: 0x44b8e0 gives each cell a percent of its column's highest value (0x44bfa0): the value
## equal to the highest, or a highest of 0, is 100. Resources share the top of the In and Out columns (0x44bfd0). The kills
## and razes by side are percents of the local player's total (the first row, read without its search). Each tick moves a
## bar by the growth step and stops at its percent (0x4636a0), so all bars rise alike. The bar text's font is the control's
## own FO_SMALL (xci). Open: the timer period (50 ms), the hover lines of the tabs (STR_RESULTS_HELP [2..5] in string order).

const MAIN := "PNL_VICTORYDEFEAT_NEW"
const ADV := "PNL_RESULTS_MAIN"
const PAGES := ["PNL_RESULTS_HERO", "PNL_RESULTS_RESOURCES", "PNL_RESULTS_UNITS", "PNL_RESULTS_BUILDINGS"]
const TABS := ["BUTT_RESULTS_HERO", "BUTT_RESULTS_RESOURCES", "BUTT_RESULTS_UNITS", "BUTT_RESULTS_BUILDINGS"]
const ROWS := ["PB_ONE", "PB_TWO", "PB_THREE", "PB_FOUR", "PB_FIVE", "PB_SIX"]
## Slot colour -> bar bitmap (0x449ce0 switch: 0x247 red, 0x244 blue, 0x245 green, 0x246 purple, 0x243 black, 0x248 yellow).
const BAR_BITMAPS := ["BM_RESULTS_BARONE", "BM_RESULTS_BARTWO", "BM_RESULTS_BARTHREE", "BM_RESULTS_BARFOUR", "BM_RESULTS_BARFIVE", "BM_RESULTS_BARSIX"]
const TICK_MS := 50

var data: Dictionary = {}                 # filled by main.gd: see main.gd results_data()
var on_continue := Callable()
var screen := MAIN
var page := 0
var grow := 0                             # 0x a25170: the bars' growth in percent (0..100)
var tick_accum := 0.0

func _ready():
	setup_screen()

func open_main():
	screen = MAIN
	canvas.placements.clear()
	canvas.control_text.clear()
	canvas.control_state.clear()
	canvas.control_frame.clear()
	canvas.control_fill.clear()
	canvas.control_offset.clear()
	place(MAIN, Vector2i.ZERO, 2000)
	fill_main()
	open_screen_help(0xe, false)              # 0x454560 -> 0x448870(0xe, 0)

func fill_main():
	var won: bool = bool(data.get("won", false))
	var t := canvas.control_text
	canvas.bitmap_override = {} if won else {"BM_VICTORYBACKGROUND": "BM_VICTORYDEFEAT_BG"}
	var labels: Array = strings(0x117)
	var values: Array = data.get("counters", [0, 0, 0, 0, 0, 0])
	for i in 6:
		t["%s/STR_PARCHSMALL_L150#%d" % [MAIN, i]] = str(values[i])
		t["%s/STR_PARCHSMALL_L250#%d" % [MAIN, i]] = labels[i]
	t["%s/STR_PARCHLARGE_L500#0" % MAIN] = String(data.get("hero_name", ""))
	t["%s/STR_PARCHLARGE_500#0" % MAIN] = string_at(0x17, 4 if won else 5)
	t["%s/STR_PARCHMED_L700#0" % MAIN] = String(labels[6]) % int(data.get("xp", 0))
	var levels := int(data.get("levels", 0))
	t["%s/STR_PARCHMED_L700#1" % MAIN] = labels[7] if levels == 1 else (string_at(0x14a, 7) % levels if levels > 1 else "")
	t["%s/STR_SMALL700#0" % MAIN] = "Saved to the hero." if bool(data.get("saved", false)) else ""
	# 0x454b70 (Read; playtest 2026-11-12: "ined 1 level." under the Advanced Results button): every text control is
	# centred (0x464c60 mode 1) before its text is set: the counters 0x2f2e / 0x2f30, the name 0x2f31, Victory 0x2f2c, the
	# XP and level lines 0x2f32 #0 / #1 and 0x2f03. Left-aligned, the level line started under the button (0, 500).
	canvas.control_align.clear()
	for key in t:
		if String(key).begins_with(MAIN + "/"): canvas.control_align[key] = HORIZONTAL_ALIGNMENT_CENTER
	canvas.queue_redraw()

func refresh():
	if screen == MAIN: fill_main()
	else: fill_page()

# ------------------------------------------------------------------------------------------------ advanced results
func open_advanced(to_page: int = 0):
	screen = ADV
	canvas.control_align.clear()
	canvas.placements.clear()
	canvas.control_text.clear()
	canvas.control_state.clear()
	canvas.bitmap_override = {}
	place(ADV, Vector2i.ZERO, 30000)
	place(PAGES[to_page], Vector2i.ZERO, 30001)
	page = to_page
	grow = 0
	fill_page()
	open_screen_help(0xd, false)              # 0x449ce0 -> 0x448870(0xd, 0)

func set_page(to_page: int):
	canvas.placements = canvas.placements.filter(func(p): return not String(p.panel.get("name", "")) in PAGES)
	place(PAGES[to_page], Vector2i.ZERO, 30001)
	page = to_page
	grow = 0
	fill_page()

## The columns of one page for one player row: [values], and the text of the level label on the hero page.
func page_values(row: Dictionary, which: int) -> Array:
	match which:
		0: return [row.kills, row.spells, row.xp, row.level]
		1:
			var gin: Array = row.res_in
			var gout: Array = row.res_out
			return [gin[0], gin[1], gin[3], gin[2], gin[0] + gin[1] + gin[2] + gin[3],
				gout[0], gout[1], gout[3], gout[2], gout[0] + gout[1] + gout[2] + gout[3]]
		2: return [row.produced, row.lost, row.total_kills, row.kills_by_side]
		3: return [row.built, row.buildings_lost, row.razed, row.converted, row.razed_by_side]
	return []

func fill_page():
	var t := canvas.control_text
	var players: Array = data.get("players", [])
	t["%s/STR_PARCHLARGE_L500#0" % ADV] = string_at(0x119, 1)                    # "Combat Results"
	t["%s/STR_MEDIUM700#0" % ADV] = ""
	canvas.control_frame["%s/IM_RESULTS_TABBAR#0" % ADV] = page               # 0x45e410(0x144, 0x53bd, 0, 0, page * 70)
	for i in 6:
		t["%s/STR_PARCHSMALL_L150#%d" % [ADV, i]] = String(players[i].name) if i < players.size() else ""
	var panel: String = PAGES[page]
	var columns: int = [4, 10, 4, 5][page]
	var maxima: Array = []
	for c in columns:
		var top := 0
		for r in players: top = maxi(top, int(page_values(r, page)[c]))
		maxima.append(top)
	for i in 6:
		for c in columns:
			var key := "%s/%s#%d" % [panel, ROWS[i], c]
			if i >= players.size():
				t[key] = ""
				canvas.control_fill[key] = -1.0                                # 0x251 (magenta, missing): hidden
				continue
			var row: Dictionary = players[i]
			var local_cell: bool = (page == 2 and c == 3 and i == 0) or (page == 3 and c == 4 and i == 0)
			var value := int(page_values(row, page)[c])
			t[key] = "-" if local_cell else str(value)                     # 0x463700(.., &DAT_0060b820 "-") on the local row
			canvas.bitmap_override_by_key[key] = BAR_BITMAPS[int(row.colour) % 6]
			canvas.control_fill[key] = 0.0 if local_cell else mini(grow, bar_target(page, c, value, maxima, players)) / 100.0
		if page == 0:
			t["%s/STR_PARCHMED_L35#%d" % [panel, i]] = str(int(players[i].games)) if i < players.size() else ""   # 0x2f34: +0x14
			# BM_RESULTS_STATUS: x 0 skull (the hero died), x 24 medal (gained a level); (100, 100) = off the image.
			canvas.control_offset["%s/IM_RESULTS_STATUS#%d" % [panel, i]] = Vector2i(0, 0) if i < players.size() and bool(players[i].hero_dead) else Vector2i(100, 100)
			canvas.control_offset["%s/IM_RESULTS_LEVEL#%d" % [panel, i]] = Vector2i(24, 0) if i < players.size() and bool(players[i].levelled) else Vector2i(100, 100)
	canvas.queue_redraw()

## 0x44bfa0: a value as a percent of `top` (100 when they are equal or `top` is 0).
static func bar_percent(value: int, top: int) -> int:
	if value == top or top == 0: return 100
	var percent: int = (absi(value) * 100 / absi(top)) * (1 if (value >= 0) == (top >= 0) else -1)
	return clampi(percent, 0, 100)

## 0x44b8e0: the percent a cell ends at (`maxima` of the page's columns; the Resources' In and Out columns share the higher).
static func bar_target(which: int, column: int, value: int, maxima: Array, players: Array) -> int:
	match which:
		1:
			var pair := column % 5
			return bar_percent(value, maxi(int(maxima[pair]), int(maxima[pair + 5])))
		2:
			if column == 3: return bar_percent(value, int(players[0].total_kills))
		3:
			if column == 4: return bar_percent(value, int(players[0].razed))
	return bar_percent(value, int(maxima[column]))

## 0x44a890 (each timer tick): +15 % while up to 60, +5 % up to 90, then +1 %, until 100.
static func grow_step(current: int) -> int:
	if current >= 100: return 100
	var step := 15
	if current > 0x3c: step = 5
	if current > 0x5a: step = 1
	return mini(100, current + step)

func _process(delta: float):
	if screen != ADV or grow >= 100: return
	tick_accum += delta * 1000.0
	while tick_accum >= TICK_MS and grow < 100:
		tick_accum -= TICK_MS
		grow = grow_step(grow)
	fill_page()

# ------------------------------------------------------------------------------------------------ input
func help_id() -> int:
	return 0xe if screen == MAIN else 0xd

func press(key: String) -> void:
	var control := key.get_slice("/", 1).get_slice("#", 0)
	if screen == MAIN:
		match control:
			"BUTT_OKAY_STARTUP":
				if on_continue.is_valid(): on_continue.call()
			"BUTT_ADVANCEDRESULTS": open_advanced(0)
		return
	match control:
		"BUTT_DONE_180": open_main()
		_:
			if TABS.has(control): set_page(TABS.find(control))

func hovered_changed(entry: Dictionary) -> void:
	var control := String(entry.get("control", {}).get("name", ""))
	if screen == MAIN:
		if control in ["BUTT_OKAY_STARTUP", "BUTT_ADVANCEDRESULTS"]: audio().ui_sound("sfx/HighlightR")   # 0x60f564
		return
	var help := ""
	match control:
		"BUTT_DONE_180": help = string_at(0x10f, 0 if bool(data.get("won", false)) else 1)
		"BUTT_RESULTS_HERO": help = string_at(0x10f, 2)
		"BUTT_RESULTS_BUILDINGS": help = string_at(0x10f, 3)
		"BUTT_RESULTS_UNITS": help = string_at(0x10f, 4)
		"BUTT_RESULTS_RESOURCES": help = string_at(0x10f, 5)
	canvas.control_text["%s/STR_MEDIUM700#0" % ADV] = help
	canvas.queue_redraw()
