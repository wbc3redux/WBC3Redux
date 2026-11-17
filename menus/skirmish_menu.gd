extends "res://core/ui_screen.gd"
## Skirmish setup screen (milestone 10a, parity pass 2): the decoded PNL_SS panel (0xfd, opened at 0,0 layer 100 by
## 0x4e47e0) and one PNL_SIDESEL_SIDEn row per map side (0xa2 + n at 22, 201 + 31 n, layer 0x6e, 0x4f19f0). 1920x1080
## shows the 800x600 screen scaled to the height with black side bars (deliberate presentation change, UI_RESEARCH.md).
##
## Parity pass 2 (UI_RESEARCH.md "Parity pass 2"; Read unless noted):
## * Opening (0x4e47e0 -> 0x4e4000 -> 0x4f19c0 / 0x4f19f0(6)): six side rows, every slot Open; Okay is disabled until a
##   map is chosen in LB_SS_MAPS (0x4e0590 -> 0x4e7760 copies the side records and re-opens the rows for the map's sides);
##   the first visit shows the screen help 0x448870(10, 0). The list holds "Random Map" first and the imported maps
##   (MapData.index()).
## * Hand-test findings F5 / F6 (HAND_TEST_FINDINGS.md; UI_RESEARCH.md "Skirmish setup, F5 / F6"):
##   - Map list (LB_SS_MAPS): one entry per 19-pixel row in the list's own fonts, the chosen one in FO_MEDIUMLIGHT (white),
##     the rest FO_MEDIUMDARK, by name; the scroll bar SBAR_V156B scrolls it (S-3: ui_canvas set_list / list_input, Read).
##     The screen opens with "Random Map" chosen (0x4e4000 copies string 0x11f into 0xa49294 and opens the Random Map
##     panel 0xfe at (0x1e, 0x16): size / terrain / utilities / animals / resources, 0x4e3130, Read).
##   - Left pane (IM_STRATMAP_SIDESEL, bitmap 0x1ae): for a scenario, 0x4e7760 loads the scenario's stored preview into
##     the bitmap (0x41c0c0, when SCN header byte 0x14d is set, else HiddenMapStrat.bmp) and redraws (28, 18, 130, 130)
##     (Read); 0x14d is 1 on Desert Sands, The Hill, Bridges and Cavemen (0x456370, Emulated), so the rebuild shows the
##     imported SM24 preview (scenario_minimap.png). Before a map is chosen it is 128x128black.bmp (0x4e47e0, Read).
##     0x4e7760 also wraps the scenario's description into three 260-byte lines (0xa4939c / 0xa494a0 / 0xa495a4), but no
##     code in the executable reads them (absolute-address scan, Read): no description text is shown.
##   - Rows on opening (0x4f19f0, Read): the player button reads Open and is enabled (state 0); race (Random, from 0x10)
##     and resources (Average, 0x66 [2]) show their text and are disabled; the shield is disabled. In single player the
##     Ready toggle is disabled and ticked (0x45c6f0(.., 1)), and 0x4e4000 opens PNL_SS_COVERREADY (0x150, the 85 x 225
##     SSCoversReady.bmp) at (500, 160), layer 0x79: it covers the painted READY heading and the toggles (layer 0x6e + 10).
##   - Single player (0xa497f9 = 1, 0x4e4000, Read): the chat image IM_SS_MP_CHAT moves to (1000, 1000) and the chat edit
##     is disabled; both are left out. BUTT_SS_GAMESPEED is not on the original's screen (Data; game speed is a control of
##     the More Options panel 0x12f, 0x4e9570, Read), so it is left out and the Army Setup Points label shows.
## * Hover help (callback 0x4e5120, message 0x12): the three STR_MEDIUM500 lines (0x2f01 #0..2) show Okay "Let the War
##   begin!" (0xab [3]), Cancel "Return to the Main Menu" (0xab [4]), the resolution button (0xab [6], [7]), each option
##   button its name and description for the current value (0x4debb0: 0xb3/0xc4/0xc5 victory, 0xae build level, 0xaf map,
##   0xb0 vision, 0xb1 handicap, 0xb2 quests); leaving clears them (0x4df710). Hovering Okay or Cancel plays HighlightR.wav
##   (0x60f564, 0x50f900). The rebuild's own help lines (hero summary, "placeholder art", hints) are gone.
## * Option buttons open the original's lists at the mouse (0x4e5eee -> 0x45cfe0), and the callbacks store the choice:
##   victory (0x4dfec0: 0xac [0..7] + 0xad [0..3]; Capture the Flag only in multiplayer; Assassination and Pitched Battle
##   are left out when 0xa49184 is set, Open, treated as clear), build level (0x4dfe30: "No Building", "Keep Level 1..5";
##   victories 1, 4, 6 shift the list to Keep Level 1..), map (Exposed / Hidden), vision (No Fog / Fog of War / Line Of
##   Sight), handicap (On / Off), quests (On / Off). Effects in the match: vision and map as before; line of sight is
##   stored and passed to the fog object (visibility.line_of_sight_option); build level limits production (0x40c740 via
##   ProductionRules.options) and feeds the award (0x4553f0); handicap only changes army setup points, which are 0 in a
##   skirmish (no effect); quests feed the award and gate the quest sites (S-2); the victory options decide the match
##   (S-2, simulation/skirmish_victory.gd).
## * Game speed: 0x60c3ee starts at the options' GameSpeed (0x4e47e0) and the match starts at that speed (+1, 0x458dd0). The
##   setup's own speed button (0x4e5da2) is left out (F6, above); More Options has the same choice (S-2).
## * Row buttons (0x4eb4d0): the player button opens a list (0x4eb110): AI levels by the side record's AI value (0: Passive
##   .. Emperor; 7: Squire .. Rampant; else Squire .. Emperor), then Open and Closed; the local row's list starts with the
##   hero's name (choosing another entry gives up the seat: not ported, the seat is kept). The race button opens the 17-
##   entry race list (0xf, 0x68, Random), the resources button the five levels (0x66), both at the mouse x - 15. Send Map,
##   map size / players and resolution stay disabled (Open / out of scope).
##
## Skirmish setup session (SKIRMISH_RESEARCH.md "Army setup points" and "Setup screen, second pass"; Read unless noted):
## * Army Setup Points: the slider SBAR_H170 (0x1777, range 0..50, Data) under the painted label stores 0xa47a02 on every
##   change and writes the number into STR_MEDIUM30 (0x4e5120 -> 0x4e569b); it is enabled for the host / single player
##   (0x4e3130). The thumb drawing is an approximation (ui_canvas control_scroll, Open). On Okay a budget of 1 or more
##   (points + the handicap term, 0x417730) opens the army setup screen after loading (army_setup_screen.gd).
## * Shield (0x4eb4d0 case 0x7e): each click steps the row's team 0..3; IM_ICON_SHLDCLRS shows the colour column and
##   the team row (0x45e410(row, 0x5225, 0, colour * 25, team * 20)). Teams feed the relation table (0x4de740).
## * The options and the slider are the saved "Random Map Data" values when the screen opens (0x4e45c0 -> 0x450970) and
##   are saved on Okay (0x450760); choosing a map keeps them (0x4e7760 copies side records only).
## * Okay rolls the Random slots' races, 1d16 - 1 each (0x4e6af4, 0x60f0f0).
##
## RM-6 (RANDOM_MAP_RESEARCH.md "RM-6"; Read, the screenshot .local/reference/original_skirmish_setup_1024x768.png agrees):
## * "Random Map" ([0287]) is the first list entry and chosen on opening (0x4e4000). Panel 0xfe, PNL_SS_RANDOMMAP, sits at (0x1e,
##   0x16), layer 1000, over the black strategic map: five text buttons 0xe1..0xe5 with the settings (0x4e3130). Each opens its
##   list at the mouse (0x4e1390: lists 0xb4; 0xd8 + 0xfa; 0x159; 0xb6; 0xb7, each ending in "Random" 0x53 [0]); under I Am The
##   Greatest the panel ignores clicks. Choosing a scenario closes the panel (0x4e7760), choosing Random Map opens it again.
## * 0x4e7760's Random Map branch keeps the rows Open with no seat (0x60f198 = -1): the original screenshot's six Open rows. A
##   row's player list then starts with the hero's name (0x4eb4d0 case 0x80): taking it seats the hero there; the seat can
##   move or be given up (0x4eb110 itself is not disassembled: rebuild's reading). Okay needs a seat, two active slots and not
##   one team for all (0x4eacd0). The values are saved with the other "Random Map Data" on Okay and keep "Random".
##
## S-2 (SKIRMISH_RESEARCH.md "S-2"; Read, callbacks disassembled):
## * More Options (0x104 -> 0x4e9570): PNL_SS_ADVANCEDOPTIONS (0x12f) at layer 30000 over the setup: check rows 0x105 #0..6
##   (Random Weather, Resignation Kills Side, AI Resignation, temporary hero with its level slider 0x177b 4..50, I Am The
##   Greatest, Tough Starting Towers, No Hero Items) and the game speed button 0xf9 (0xd4). Okay (0x17b) keeps the working copy
##   0xa479b8 and saves it (0x450b80), Cancel (0x17c) drops it. Row 4 ticks rows 0, 1 and clears 2, 3 (0x4e9b33).
## * Rules (0x115 -> 0x4ea2d0): PNL_SS_GAMEMODS (0x132): rows 0x11d #0..6 (0xee [1..7]). No Heroes is disabled with a
##   temporary hero or under Assassination; with No Heroes the victory list has no Assassination or Pitched Battle (0x4dfec0).
## * Victory list side effects (0x4dfec0, 0x4e3c60 case 4): Setup.choose_victory; the build level button is disabled under
##   Pitched Battle, King of the Castle and Merchants, the slider under Pitched Battle and King of the Castle (0x4e3130),
##   the shields while 4..9 hold the teams.

const Setup = preload("res://simulation/skirmish_setup.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const Army = preload("res://simulation/army_setup.gd")
const PLAYER_STRINGS := 103        # TXT_SIDESEL_PLAYER: Open, Closed, Computer AI
const AI_STRINGS := 214            # TXT_AI_LEVELS: AI: Passive .. AI: Rampant
const CustomAi = preload("res://simulation/custom_ai.gd")
const RESOURCE_STRINGS := 102      # TXT_SIDESEL_RESOURCES: Very Low .. Very High
const RACE_TABLE_LOW := 15         # TXT strings 0xf: Knight .. Wood Elf (races 0..7)
const RACE_TABLE_HIGH := 104       # 0x68: Dark Elf .. Plaguelord (races 8..15)
const RANDOM_STRINGS := 83         # 0x53 entry 0: Random (race 0x10)
const SS := "PNL_SS"
const HELP_LINE := "PNL_SS/STR_MEDIUM500#%d"
const MapData = preload("res://core/map_data.gd")
const Display = preload("res://core/display.gd")
## DELIBERATE MODERN CHANGE (user's request, 2026-11-10): the resolution button BUTT_SS_RES (0xab [6], [7]; always locked
## here, the rebuild renders at the display's own resolution) chooses the visuals instead: Legacy (the original's look) or
## Enhanced (ENHANCED_VISUALS.md), the same setting as Options > Visuals > Enhanced Visuals, saved with the settings.
const VISUALS_LABELS := ["Legacy Visuals", "Enhanced Visuals"]
const VISUALS_HELP := ["Visuals", "Legacy: the original game's look.", "Enhanced: the modern effects (Options, Visuals tab)."]
## W1: the imported maps (assets/maps/index.json, by name: Desert Sands and The Hill so far; map waves add the rest).
var map_entries: Array = sorted_maps()
## F5 / F6: controls the original keeps off the single-player screen (0x4e4000 / 0x4f19f0; see the header).
const HIDDEN_SS := ["IM_SS_MP_CHAT", "EDIT_SIDESEL_CHAT", "STR_SMALL500", "BUTT_SS_GAMESPEED"]
const PREVIEW := "X:scenario_preview:"
const RM := "PNL_SS_RANDOMMAP"     # 0xfe
const RM_LAYER := 1000             # 0x4e4000
const RM_OFFSET := Vector2i(0x1e, 0x16)
const RANDOM_MAP_TEXT := 287       # [0287] "Random Map", string 0x11f
## Button 0xe1..0xe5 -> its setting.
const RM_BUTTONS := {"BUTT_RM_SIZE": "map_size", "BUTT_RM_TERRAIN": "terrain", "BUTT_RM_ISLANDS": "temples",
	"BUTT_RM_CRITTERS": "critters", "BUTT_RM_RESOURCES": "resource_level"}

var store := Store.new()
var map: Dictionary
var setup: Dictionary
var hero = null
var message := ""
var map_selected := false
var selected_map := -1             # the chosen LB_SS_MAPS row (-1: none yet)
var game_speed := 2                # 0x60c3ee in the setup screen (0..4)
var help := ["", "", ""]           # STR_MEDIUM500 #0..2
var hovered_option := -1           # 0xa497f4: the option whose help is shown
var dragging_slider := false
var sub_panel := ""                # S-2: the open modal panel (PNL_SS_ADVANCEDOPTIONS / PNL_SS_GAMEMODS), "" none
var edit_options := {}             # S-2: the panel's working copy (0xa479b8 / 0xa49178)
var edit_speed := 2
const MORE_PANEL := "PNL_SS_ADVANCEDOPTIONS"
const RULES_PANEL := "PNL_SS_GAMEMODS"
const PANEL_LAYER := 30000         # 0x4e9570 / 0x4ea2d0
const CHECKED := 2                 # control_state of a ticked toggle (ui_canvas SELECTED)
## Rows of the panels in instance order: section and index of the row's text.
const MORE_ROWS := [[0xe9, 1], [0xe9, 2], [0xe9, 3], [0xe9, 4], [0xe9, 5], [0xec, 0], [0xec, 1]]

func _ready():
	setup_screen()
	audio().menu_entered()   # the theme starts at the first menu entry (0x41d2c0)
	fit_window(get_window())
	canvas.list_picked.connect(map_picked)
	map_entries[0].name = game_text(RANDOM_MAP_TEXT)
	map = MapData.map(String(map_entries[1].slug))                # the first imported map; a scenario replaces it when chosen
	if "--self-test" in OS.get_cmdline_user_args():
		store = Store.new("user://skirmish-menu-self-test")   # never the live hero book
		Settings.use_file("user://skirmish-menu-self-test-settings.cfg")
		DirAccess.remove_absolute(Setup.saved_options_path())
		mark_all_seen()
	hero = store.selected_profile()
	game_speed = Settings.current().get_value("GameSpeed")      # 0x4e47e0: 0x60c3ee = 0x70d6ca
	open_screen()
	open_screen_help(10, false)                                 # 0x4e47e0 -> 0x448870(10, 0)
	if Setup.start_error != "":                                 # RM-7: the loading screen came back
		message = Setup.start_error
		Setup.start_error = ""
		set_help([message])
	if "--self-test" in OS.get_cmdline_user_args(): call_deferred("self_test")
	elif "--capture" in OS.get_cmdline_user_args(): call_deferred("capture")

## 0x4e47e0 / 0x4e4000: PNL_SS and six open rows; "Random Map" chosen.
func open_screen():
	canvas.placements.clear()
	place_without(SS, Vector2i.ZERO, 100, HIDDEN_SS)
	place("PNL_SS_COVERREADY", Vector2i(500, 160), 0x79)            # 0x4e4000, single player: covers the Ready column
	var options: Dictionary = Setup.random_setup().options
	Setup.load_saved_options(options)                           # 0x4e45c0 -> 0x450970
	select_random_map(options)

## 0x4e4000 / 0x4e7760's Random Map branch: panel 0xfe, six Open rows, no seat.
func select_random_map(options: Dictionary):
	selected_map = 0
	map_selected = true
	setup = Setup.random_setup(options)
	place_rows(Setup.SLOTS)
	if canvas.placements.filter(func(p): return String(p.panel.get("name", "")) == RM).is_empty(): place(RM, RM_OFFSET, RM_LAYER)
	refresh()

func place_rows(count: int):
	canvas.placements = canvas.placements.filter(func(p): return not String(p.panel.get("name", "")).begins_with("PNL_SIDESEL_SIDE"))
	for i in count:
		place("PNL_SIDESEL_SIDE%d" % i, Vector2i(22, 201 + 31 * i), 0x6e)

## Places a copy of a panel without the named controls (the original moves or disables them in single player).
func place_without(panel: String, offset: Vector2i, layer: int, hidden: Array):
	var copy: Dictionary = canvas.panel_by_name(panel).duplicate()
	copy.controls = copy.controls.filter(func(c): return not String(c.name) in hidden)
	canvas.placements.append({panel = copy, offset = offset, layer = layer})

## "Random Map", then the imported scenarios by name (the original lists them alphabetically after it).
static func sorted_maps() -> Array:
	var maps: Array = MapData.index().duplicate()
	maps.sort_custom(func(a, b): return String(a.name).naturalnocasecmp_to(String(b.name)) < 0)
	return [{"slug": MapData.GENERATED, "name": "Random Map", "players": Setup.SLOTS}] + maps

## The chosen scenario's stored preview (SM24) for IM_STRATMAP_SIDESEL (0x4e7760 -> 0x41c0c0).
func preview_bitmap(slug: String) -> String:
	var name := PREVIEW + slug
	layout.exported_bitmaps[name] = {"file": "maps/%s/scenario_minimap.png" % slug}
	return name

## 0x4e0590 -> 0x4e7760: the map is chosen; its side records become the setup records and the rows are re-opened.
func select_map(index: int = 0) -> bool:
	if index < 0 or index >= map_entries.size(): return false
	var options: Dictionary = setup.options
	if index == 0:
		select_random_map(options)
		return true
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != RM)   # 0x4e7760: 0x4626f0(0xfe)
	# W1: the chosen map's data; main.tscn builds its terrain, collision and objects from MapData.current.
	MapData.select(String(map_entries[index].slug))
	map = MapData.map()
	selected_map = index
	setup = Setup.defaults(map)
	setup.options = options                                      # 0x4e7760 copies the side records, not the options
	place_rows(int(setup.sides))
	setup.players[0].kind = Setup.HUMAN
	if hero != null:
		setup.players[0].hero_id = hero.data.id
		setup.players[0].name = hero.data.name
	for i in range(1, int(setup.sides)): Setup.set_kind(setup, i, Setup.COMPUTER, Setup.KEEP_LEVEL)   # the map's level (0x4e7760)
	map_selected = true
	refresh()
	return true

## 4:3 content scaled to the 1080 height, centred (deliberate presentation change).
static func presentation_rect() -> Rect2:
	var scale := float(PRESENTATION.y) / BASE.y
	return Rect2(Vector2((PRESENTATION.x - BASE.x * scale) / 2.0, 0), Vector2(BASE.x * scale, PRESENTATION.y))

func key(panel: String, control: String, instance: int = 0) -> String:
	return "%s/%s#%d" % [panel, control, instance]

# ------------------------------------------------------------------------------------------------ labels
func victory_text(victory: int) -> String:
	return String(strings(0xac)[victory]) if victory < 8 else String(strings(0xad)[victory - 8])

func build_level_text(level: int) -> String:
	return String(strings(0xae)[0]) if level == 0 else String(strings(0xae)[5]) % level

func refresh():
	var t := canvas.control_text
	var s := canvas.control_state
	t.clear()
	s.clear()
	var o: Dictionary = setup.options
	canvas.set_list(item(key(SS, "LB_SS_MAPS")), map_entries.map(func(e): return String(e.name)), selected_map)
	t[key(SS, "STR_SMALL_450")] = ""
	var random := Setup.is_random(setup)
	if random:
		for control in RM_BUTTONS: t[key(RM, control)] = random_text(RM_BUTTONS[control], int(o[RM_BUTTONS[control]]))
	if selected_map >= 0 and not random:
		canvas.bitmap_override_by_key[key(SS, "IM_STRATMAP_SIDESEL")] = preview_bitmap(String(map_entries[selected_map].slug))
	else:
		canvas.bitmap_override_by_key.erase(key(SS, "IM_STRATMAP_SIDESEL"))   # BM_STRATMAP_SAVE = 128x128black.bmp
	# 0x4de250 option labels: victory (0xac/0xad), building (0xae), map (0xaf), vision (0xb0), handicap (0xb1), quests (0xb2)
	t[key(SS, "BUTT_SS_BUTTON", 0)] = victory_text(int(o.victory))
	t[key(SS, "BUTT_SS_BUTTON", 1)] = build_level_text(int(o.build_level))
	t[key(SS, "BUTT_SS_BUTTON", 2)] = strings(0xaf)[2 if o.hidden_map else 0]
	t[key(SS, "BUTT_SS_BUTTON", 3)] = strings(0xb0)[[0, 2, 5][int(o.vision)]]
	t[key(SS, "BUTT_SS_BUTTON", 4)] = strings(0xb1)[0 if o.handicap else 3]
	t[key(SS, "BUTT_SS_BUTTON", 5)] = strings(0xb2)[0 if o.quests else 3]
	# 0x4e3130: the slider shows 0xa47a02 and STR_MEDIUM30 its number.
	t[key(SS, "STR_MEDIUM30")] = str(int(o.army_points))
	t[key(SS, "STR_MEDIUM332")] = ""
	canvas.control_scroll[key(SS, "SBAR_H170")] = float(o.army_points) / Army.MAX_SLIDER
	t[key(SS, "BUTT_SS_RES")] = VISUALS_LABELS[1 if bool(Display.setting_visuals_enhanced()) else 0]
	for c in ["BUTT_SS_SENDMAP", "BUTT_SS_MAPSIZE", "BUTT_SS_MAPPLAYERS"]:
		s[key(SS, c)] = 3
	var victory := int(o.victory)
	# 0x4e3130: the build level button and the points slider per victory; 0x4e3c60 ignores the options under the Greatest.
	if victory in [7, 8, 0xb]: s[key(SS, "BUTT_SS_BUTTON", 1)] = 3
	if victory in [7, 0xb]: s[key(SS, "SBAR_H170")] = 3
	if bool(o.greatest):
		for i in 6: s[key(SS, "BUTT_SS_BUTTON", i)] = 3
		s[key(SS, "SBAR_H170")] = 3
	for i in int(setup.sides):
		var p: Dictionary = setup.players[i]
		var panel := "PNL_SIDESEL_SIDE%d" % i
		if map_selected and i == int(setup.local):
			t[key(panel, "BUTT_SIDESEL_PLAYER")] = p.name if hero != null else ""
		elif int(p.kind) == Setup.COMPUTER:
			t[key(panel, "BUTT_SIDESEL_PLAYER")] = strings(AI_STRINGS)[int(p.difficulty)]
		else:
			t[key(panel, "BUTT_SIDESEL_PLAYER")] = strings(PLAYER_STRINGS)[{Setup.OPEN: 0, Setup.CLOSED: 1}.get(int(p.kind), 0)]
		var playing: bool = map_selected and (p.kind == Setup.HUMAN or p.kind == Setup.COMPUTER)
		# 0x4f19f0 / 0x4ef650: open rows show their race and resources, disabled; a closed row's are blank.
		var shown: bool = int(p.kind) != Setup.CLOSED
		t[key(panel, "BUTT_SIDESEL_RACE")] = race_name(int(p.race)) if shown else ""
		t[key(panel, "BUTT_SIDESEL_RESOURCES")] = String(strings(RESOURCE_STRINGS)[int(p.resources)]).strip_edges() if shown else ""
		if not playing:
			s[key(panel, "BUTT_SIDESEL_RACE")] = 3
			s[key(panel, "BUTT_SIDESEL_RESOURCES")] = 3
		if map_selected and i == int(setup.local) and hero == null: s[key(panel, "BUTT_SIDESEL_PLAYER")] = 3
		if not map_selected or Setup.teams_locked(setup) or bool(o.greatest) or (random and not playing): s[key(panel, "BUTT_SIDESEL_SHIELD")] = 3
		s[key(panel, "BUTT_SIDESEL_READY")] = 3                       # single player: disabled and ticked, under the cover
		t[key(panel, "BUTT_SIDESEL_SHIELD")] = ""
		canvas.control_offset[key(panel, "IM_ICON_SHLDCLRS")] = Vector2i(int(p.colour) * 25, int(p.team) * 20)
	for i in 3: t[HELP_LINE % i] = help[i]
	if hero == null or not map_selected or (random and not Setup.can_start_random(setup)): s[key(SS, "BUTT_OKAY_STARTUP")] = 3
	if sub_panel != "": refresh_sub_panel()
	canvas.queue_redraw()

# ------------------------------------------------------------------------------------------------ S-2: More Options, Rules
## 0x4e9570 / 0x4ea2d0: the panel over the setup, on a working copy.
func open_sub_panel(panel: String):
	sub_panel = panel
	edit_options = setup.options.duplicate(true)
	edit_speed = game_speed
	place(panel, Vector2i.ZERO, PANEL_LAYER)
	refresh()

func close_sub_panel():
	var closing := sub_panel
	sub_panel = ""
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != closing)
	for k in canvas.control_text.keys():
		if String(k).begins_with(closing + "/"): canvas.control_text.erase(k)
	refresh()

## More Options' Okay (0x17b): 0xa479b8 -> 0xa48ed0, saved (0x4ea040); the Greatest applies its preset (0x4ea050).
## Rules' Okay (0x17b): 0xa49178 -> 0xa47a05.
func accept_sub_panel():
	var was: bool = bool(setup.options.greatest)
	var keys: Array = Setup.MORE_OPTIONS + ["temp_hero_level"] if sub_panel == MORE_PANEL else Setup.RULES
	for k in keys: setup.options[k] = edit_options[k]
	if sub_panel == MORE_PANEL:
		game_speed = edit_speed
		Setup.save_more_options(setup.options)
		if bool(setup.options.greatest) != was:
			Setup.apply_greatest(setup, bool(setup.options.greatest))
			if Setup.is_random(setup) and int(setup.local) >= 0 and hero != null: seat_hero(int(setup.local))
	close_sub_panel()

func refresh_sub_panel():
	var t := canvas.control_text
	var s := canvas.control_state
	var o: Dictionary = edit_options
	if sub_panel == MORE_PANEL:
		t[key(sub_panel, "STR_PARCHLARGE_L400")] = string_at(0xe9, 0)
		for i in 6: t[key(sub_panel, "STR_MEDIUMDLG_300", i)] = ""
		for row in MORE_ROWS.size():
			var k := key(sub_panel, "BUTT_SS_OPTIONS_CHECKBOX", row)
			t[k] = string_at(int(MORE_ROWS[row][0]), int(MORE_ROWS[row][1]))
			s[k] = CHECKED if bool(o[Setup.MORE_OPTIONS[row]]) else 0
		t[key(sub_panel, "BUTT_SS_GAMESPEED")] = string_at(0xd4, edit_speed)
		var level_on: bool = bool(o.temp_hero)
		t[key(sub_panel, "STR_MEDIUMDLG_120")] = "%s %d" % [string_at(0xe9, 7), int(o.temp_hero_level)] if level_on else ""
		s[key(sub_panel, "SBAR_H170_2")] = 0 if level_on else 3
		canvas.control_scroll[key(sub_panel, "SBAR_H170_2")] = float(int(o.temp_hero_level) - Setup.TEMP_HERO_MIN) / (Setup.TEMP_HERO_MAX - Setup.TEMP_HERO_MIN)
		if bool(o.no_heroes): s[key(sub_panel, "BUTT_SS_OPTIONS_CHECKBOX", 3)] = 3     # 0x4e9570: 0xa49184
	else:
		t[key(sub_panel, "STR_PARCHLARGE_L400")] = string_at(0xee, 0)
		for row in Setup.RULES.size():
			var k := key(sub_panel, "BUTT_SS_GAMEMOD_CHECK", row)
			t[k] = string_at(0xee, row + 1)
			s[k] = CHECKED if bool(o[Setup.RULES[row]]) else 0
		# 0x4ea2d0: No Heroes with a temporary hero or under Assassination; the victories that need them.
		if bool(setup.options.temp_hero) or int(setup.options.victory) == 3: s[key(sub_panel, "BUTT_SS_GAMEMOD_CHECK", 6)] = 3

func press_sub_panel(control: String, instance: int):
	var o: Dictionary = edit_options
	match control:
		"BUTT_OKAY_160": accept_sub_panel()
		"BUTT_CANCEL_160": close_sub_panel()
		"BUTT_SS_OPTIONS_CHECKBOX":
			var row: String = Setup.MORE_OPTIONS[instance]
			o[row] = not bool(o[row])
			if row == "greatest" and bool(o.greatest): Setup.tick_greatest(o)
			refresh()
		"BUTT_SS_GAMEMOD_CHECK":
			var rule: String = Setup.RULES[instance]
			o[rule] = not bool(o[rule])
			refresh()
		"BUTT_SS_GAMESPEED":                                        # 0x4e3c60 case 0xe: the list of 0xd4
			open_list(range(5).map(func(i): return string_at(0xd4, i)), last_point, func(i):
				edit_speed = i
				refresh(), edit_speed)

func set_temp_level_at(x: float):
	var bar := item(key(MORE_PANEL, "SBAR_H170_2"))
	var span := float(bar.rect.size.x - canvas.SCROLL_THUMB)
	var fraction := clampf((x - bar.rect.position.x - canvas.SCROLL_THUMB / 2.0) / span, 0.0, 1.0)
	edit_options.temp_hero_level = roundi(lerpf(Setup.TEMP_HERO_MIN, Setup.TEMP_HERO_MAX, fraction))
	refresh()

## A modal panel takes every click (the layer 30000 callback, IM_SCREEN_BLACK under it).
func hit(point: Vector2) -> Dictionary:
	var entry: Dictionary = super.hit(point)
	if sub_panel != "" and String(entry.get("panel", "")) != sub_panel: return {}
	return entry

## A hero class's name (string sections 8..0xb, 0x54af80).
func class_name_of(klass: int) -> String:
	return String(strings(8 + klass / 8)[klass % 8])

## The race list's entry for a setup race (0x4eb4d0 case 0x7b; 0x4ed7e0 uses the same two tables).
func race_name(race: int) -> String:
	if race >= Setup.RANDOM_RACE: return String(strings(RANDOM_STRINGS)[0])
	return String(strings(RACE_TABLE_LOW if race < 8 else RACE_TABLE_HIGH)[race % 8])

# ------------------------------------------------------------------------------------------------ hover help
func set_help(lines: Array):
	for i in 3: help[i] = String(lines[i]) if i < lines.size() else ""
	for i in 3: canvas.control_text[HELP_LINE % i] = help[i]
	canvas.queue_redraw()

## 0x4debb0(option): the option's name and description lines for its current value.
func option_help(option: int) -> Array:
	var o: Dictionary = setup.options
	match option:
		0:
			var v := int(o.victory)
			if v > 7:
				var lines := [string_at(0xb3, 0), string_at(0xc5, v - 8), ""]
				match v:
					0xb: lines[2] = string_at(0xc5, 4)
					0xc: lines = [string_at(0xb3, 0), string_at(0xc5, 6), string_at(0xc5, 7)]
					9: lines[2] = string_at(0xc5, 5)
					10: lines = [string_at(0xb3, 0), string_at(0xc5, 2), string_at(0xc4, 0)]
				return lines
			return [string_at(0xb3, 0), string_at(0xc4, v), ""]
		1:
			var level := int(o.build_level)
			if level != 0: return [string_at(0xae, 2), string_at(0xae, 3), string_at(0xae, 4) + " " + str(level)]
			return [string_at(0xae, 0), string_at(0xae, 1), ""]
		2:
			if bool(o.hidden_map): return [string_at(0xaf, 2), string_at(0xaf, 3), string_at(0xaf, 4)]
			return [string_at(0xaf, 0), string_at(0xaf, 1), ""]
		3:
			match int(o.vision):
				0: return [string_at(0xb0, 0), string_at(0xb0, 1), ""]
				1: return [string_at(0xb0, 2), string_at(0xb0, 3), string_at(0xb0, 4)]
			return [string_at(0xb0, 5), string_at(0xb0, 6), string_at(0xb0, 7)]
		4:
			if bool(o.handicap): return [string_at(0xb1, 0), string_at(0xb1, 1), string_at(0xb1, 2)]
			return [string_at(0xb1, 3), string_at(0xb1, 4), string_at(0xb1, 5)]
		5:
			if bool(o.quests): return [string_at(0xb2, 0), string_at(0xb2, 1), string_at(0xb2, 2)]
			return [string_at(0xb2, 3), string_at(0xb2, 4), string_at(0xb2, 5)]
	return []

func hovered_changed(entry: Dictionary) -> void:
	var control := String(entry.get("control", {}).get("name", ""))
	var panel := String(entry.get("panel", ""))
	if panel != SS:
		if hovered_option >= 0 or help != ["", "", ""]: clear_help()
		return
	match control:
		"BUTT_OKAY_STARTUP":
			set_help([string_at(0xab, 3)])
			audio().ui_sound("sfx/HighlightR")                       # 0x60f564 (0x50f900: HighlightR.wav)
		"BUTT_CANCEL_STARTUP":
			set_help([string_at(0xab, 4)])
			audio().ui_sound("sfx/HighlightR")
		"BUTT_SS_RES": set_help(VISUALS_HELP)
		"BUTT_SS_ADVANCED_OPTIONS": set_help([string_at(0xed, 0)])
		"BUTT_SS_GAMEMODS": set_help([string_at(0xed, 1)])
		"BUTT_SS_SENDMAP": set_help([string_at(0xd2, 0)])
		"BUTT_SS_BUTTON":
			hovered_option = int(entry.control.instance)
			set_help(option_help(hovered_option))
		_: clear_help()

## 0x4df710: the lines are cleared.
func clear_help():
	hovered_option = -1
	set_help([])

# ------------------------------------------------------------------------------------------------ buttons and lists
func help_id() -> int:
	return 10

func _unhandled_input(event: InputEvent):
	if sub_panel == "" and slider_input(event): return
	if custom_ai_input(event): return
	if sub_panel == MORE_PANEL and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and bool(edit_options.temp_hero):
		var bar := item(key(MORE_PANEL, "SBAR_H170_2"))
		if not bar.is_empty() and Rect2(bar.rect).has_point(to_native(event.position)):
			set_temp_level_at(to_native(event.position).x)
			return
	if sub_panel == "" and event is InputEventMouse and help_screen < 0 and not is_list_open():
		if canvas.list_input(event, to_native(event.position)): return
	screen_input(event)

## S-3: message 7 of the map list (0x45e610: the press chooses the row).
func map_picked(_list_key: String, row: int):
	audio().click()
	select_map(row)

## The Army Setup Points slider (0x1777): a press on it or a drag sets the value from the mouse x (the scrollbar's own
## arrow / page behaviour is not traced: Open).
func slider_input(event: InputEvent) -> bool:
	if help_screen >= 0 or is_list_open(): return false
	if int(canvas.control_state.get(key(SS, "SBAR_H170"), 0)) == 3: return false   # 0x4e3130: Pitched Battle, King of the Castle
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			var was := dragging_slider
			dragging_slider = false
			return was
		var bar := item(key(SS, "SBAR_H170"))
		if bar.is_empty() or not Rect2(bar.rect).has_point(to_native(event.position)): return false
		dragging_slider = true
	elif not (event is InputEventMouseMotion and dragging_slider):
		return false
	set_army_points_at(to_native(event.position).x)
	return true

func set_army_points_at(x: float):
	var bar := item(key(SS, "SBAR_H170"))
	var span := float(bar.rect.size.x - canvas.SCROLL_THUMB)
	var fraction := clampf((x - bar.rect.position.x - canvas.SCROLL_THUMB / 2.0) / span, 0.0, 1.0)
	set_army_points(roundi(fraction * Army.MAX_SLIDER))

func set_army_points(points: int):
	setup.options.army_points = clampi(points, 0, Army.MAX_SLIDER)   # 0x4e56a1: 0xa47a02 = the slider value
	refresh()

## Victory list entries (0x4e5eee case 0): 0xac [0..7], 0xad [0..3] (Capture the Flag only in multiplayer).
func victory_choices() -> Array:
	var out: Array = []
	for i in 8: out.append(i)
	for i in 4: out.append(8 + i)
	if bool(setup.options.no_heroes):                              # 0x4dfec0 / 0x4e5eee: 0xa49184
		out.erase(3)
		out.erase(0xb)
	return out

## Build level list (0x4e5eee case 1): six entries, Keep Level 1..5 shifted for victories 1, 4 and 6.
func build_level_labels() -> Array:
	var shifted := int(setup.options.victory) in [1, 4, 6]
	var out: Array = []
	for k in 6:
		if k == 0 and not shifted: out.append(string_at(0xae, 0))
		elif shifted and k == 5: continue
		else: out.append(String(string_at(0xae, 5)) % (k + 1 if shifted else k))
	return out

func open_option_list(option: int):
	var o: Dictionary = setup.options
	var at := last_point
	match option:
		0: open_list(victory_choices().map(func(v): return victory_text(v)), at, func(i): choose_option(0, i), victory_choices().find(int(o.victory)))
		1: open_list(build_level_labels(), at, func(i): choose_option(1, i))
		2: open_list([string_at(0xaf, 0), string_at(0xaf, 2)], at, func(i): choose_option(2, i), 1 if o.hidden_map else 0)
		3: open_list([string_at(0xb0, 0), string_at(0xb0, 2), string_at(0xb0, 5)], at, func(i): choose_option(3, i), int(o.vision))
		4: open_list([string_at(0xb1, 0), string_at(0xb1, 3)], at, func(i): choose_option(4, i), 0 if o.handicap else 1)
		5: open_list([string_at(0xb2, 0), string_at(0xb2, 3)], at, func(i): choose_option(5, i), 0 if o.quests else 1)

## The visuals choice (BUTT_SS_RES, deliberate): Options > Visuals > Enhanced Visuals, written to the settings file.
func choose_visuals(enhanced: bool):
	Display.set_visual("Enhanced", enhanced)
	Display.save_settings()
	refresh()
	set_help(VISUALS_HELP)

## The list callbacks (0x4dfec0 victory, 0x4dfe30 build level, 0x4dfda0 map, 0x4dfd40 vision, handicap, quests).
func choose_option(option: int, index: int):
	var o: Dictionary = setup.options
	match option:
		0:
			Setup.choose_victory(setup, int(victory_choices()[index]))   # 0x4dfec0, 0x4e3c60 case 4
		1: o.build_level = index + 1 if int(o.victory) in [1, 4, 6] else index
		2: o.hidden_map = index == 1
		3: o.vision = index
		4: o.handicap = index == 0
		5: o.quests = index == 0
	refresh()
	set_help(option_help(option))                              # 0x4e6694: 0x4debb0(instance) after the list

# ------------------------------------------------------------------------------------------------ RM-6: the Random Map panel
## 0x4e3130: a button's text for a setting's value; one past the list is "Random" (0x53 [0]).
func random_text(setting: String, value: int) -> String:
	var random: String = String(strings(RANDOM_STRINGS)[0])
	match setting:
		"map_size": return String(strings(0xb4)[value]) if value < 4 else random
		"terrain": return String(strings(0xd8)[value]) if value < 8 else (String(strings(0xfa)[value - 8]) if value < 10 else random)
		"temples":
			if value == 0: return string_at(0x159, 3)
			if value == 1: return string_at(0x159, 1)
			return String(string_at(0x159, 2)) % value if value <= 4 else random
		"critters": return String(strings(0xb6)[value]) if value < 5 else random
	return String(strings(0xb7)[value]) if value < 3 else random

## 0x4e1390's lists (Read, asm): the texts above, except the first utilities entry, 0x159 [0]; "Random" last.
func random_list(setting: String) -> Array:
	var count := int(Setup.SAVED_RANDOM[setting][1]) + 1
	var out: Array = []
	for value in count: out.append(random_text(setting, value))
	if setting == "temples": out[0] = string_at(0x159, 0)
	return out

func open_random_list(setting: String):
	if bool(setup.options.greatest): return                     # 0x4e1390: 0xa48ed6
	open_list(random_list(setting), last_point, func(i): set_random_option(setting, i), int(setup.options[setting]))

func set_random_option(setting: String, value: int):
	setup.options[setting] = value
	refresh()

func hero_listed(slot: int) -> bool:
	return hero != null and (slot == int(setup.local) or Setup.is_random(setup))

## Random Map: the hero takes the row; the row it left is Open again.
func seat_hero(slot: int):
	var old := int(setup.local)
	if old >= 0 and old != slot:
		Setup.set_kind(setup, old, Setup.OPEN)
		setup.players[old].hero_id = ""
		setup.players[old].name = ""
	setup.local = slot
	var p: Dictionary = setup.players[slot]
	p.kind = Setup.HUMAN
	p.hero_id = hero.data.id
	p.name = hero.data.name

## The player list of a row (0x4eb4d0 case 0x80): [entries], callback mapping in player_choice().
func player_labels(slot: int) -> Array:
	var p: Dictionary = setup.players[slot]
	var side_ai := int(p.get("side_ai", 2))
	var out: Array = []
	if hero_listed(slot): out.append(String(hero.data.name))   # 0x709ce8, the hero's name
	var first := 0 if side_ai == 0 else 1
	var count := 6 if side_ai != 0 and side_ai != 7 else 7
	for i in count: out.append(strings(AI_STRINGS)[first + i])
	out.append(strings(PLAYER_STRINGS)[0])
	out.append(strings(PLAYER_STRINGS)[1])
	return out

## 0x4eb110: index -> computer level / Open / Closed (the local row's own name keeps the seat).
func player_choice(slot: int, index: int):
	var p: Dictionary = setup.players[slot]
	var side_ai := int(p.get("side_ai", 2))
	if Setup.is_random(setup) and hero != null:                   # RM-6: the first entry is the hero's seat
		if index == 0:
			seat_hero(slot)
			refresh()
			return
		index -= 1
		if slot == int(setup.local):
			setup.local = -1
			p.hero_id = ""
			p.name = ""
	elif slot == int(setup.local):
		refresh()                                                 # giving up the seat is not ported (Open)
		return
	var count := 6 if side_ai != 0 and side_ai != 7 else 7
	var first := 0 if side_ai == 0 else 1
	if index < count: Setup.set_kind(setup, slot, Setup.COMPUTER, first + index)
	elif index == count:
		Setup.set_kind(setup, slot, Setup.OPEN)
		p.difficulty = 1
	else:
		Setup.set_kind(setup, slot, Setup.CLOSED)
		p.difficulty = 1
	refresh()

# ------------------------------------------------------------------------------------------------ AI-4 CustomAI
## The original (Read): a computer row's panel callback (0x4f2c90 .. 0x4f3119, one per row) answers message 0xf with
## 0x4f2d50, which opens PNL_VIEWHERO (0x157, 0x4edd00) for that computer; its button BUTT_HERODATAAI_AIFILE shows the
## file's name or "Custom AI: None" (game text 0x216) and opens PNL_SELECTAIFILE (0x151): "None" (0x126) and the CustomAI
## files for the row's race (simulation/custom_ai.gd). Which mouse action sends message 0xf to the row is not traced
## (Open): the rebuild opens the list straight from a right-click on a computer row (PROVISIONAL trigger and
## presentation: the PNL_VIEWHERO step is skipped). The choice is the setup record's name (+0xa), cleared by a race change.
func custom_ai_input(event: InputEvent) -> bool:
	if sub_panel != "" or help_screen >= 0 or is_list_open(): return false
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT): return false
	var e := hit(to_native(event.position))
	if e.is_empty() or not String(e.key).begins_with("PNL_SIDESEL_SIDE"): return false
	var slot := int(String(e.key).get_slice("/", 0).trim_prefix("PNL_SIDESEL_SIDE"))
	if slot < 0 or slot >= setup.players.size() or int(setup.players[slot].kind) != Setup.COMPUTER: return false
	open_custom_ai(slot, to_native(event.position))
	return true

func custom_ai_entries(slot: int) -> Array:
	return CustomAi.list(int(setup.players[slot].race))

func open_custom_ai(slot: int, at: Vector2):
	var entries := custom_ai_entries(slot)
	var labels: Array = [game_text(CustomAi.NONE_TEXT)]
	var current := 0
	for i in entries.size():
		labels.append(String(entries[i].label))
		if String(entries[i].file) == String(setup.players[slot].get("custom_ai", "")): current = i + 1
	open_list(labels, at, func(i): choose_custom_ai(slot, "" if i <= 0 or i > entries.size() else String(entries[i - 1].file)), current)

func choose_custom_ai(slot: int, file: String):
	Setup.set_custom_ai(setup, slot, file)
	message = game_text(CustomAi.NONE_LABEL) if file == "" else "Custom AI: " + file.get_basename()
	refresh()

func race_labels() -> Array:
	var out: Array = []
	for r in Setup.RACE_CHOICES: out.append(race_name(r))
	return out

func press(item_key: String):
	var parts := item_key.split("/")
	var panel := parts[0]
	var control := parts[1].get_slice("#", 0)
	var instance := int(parts[1].get_slice("#", 1))
	message = ""
	if sub_panel != "":
		if panel == sub_panel: press_sub_panel(control, instance)
		return
	if panel == SS:
		match control:
			"BUTT_SS_ADVANCED_OPTIONS": open_sub_panel(MORE_PANEL)
			"BUTT_SS_GAMEMODS": open_sub_panel(RULES_PANEL)
			"BUTT_OKAY_STARTUP": start()
			"BUTT_CANCEL_STARTUP": get_tree().change_scene_to_file("res://menus/front_end.tscn")   # 0x4e6ca4 -> 0x41d2c0: the main menu
			"BUTT_SS_BUTTON": open_option_list(instance)
			"BUTT_SS_RES":
				open_list(VISUALS_LABELS, last_point, func(i): choose_visuals(i == 1), 1 if bool(Display.setting_visuals_enhanced()) else 0)
		return
	if panel == RM:
		open_random_list(RM_BUTTONS[control])
		return
	if not panel.begins_with("PNL_SIDESEL_SIDE"): return
	var slot := int(panel.trim_prefix("PNL_SIDESEL_SIDE"))
	var p: Dictionary = setup.players[slot]
	var at := last_point - Vector2(15, 0)                          # 0x4eb4d0: param_4 - 0xf
	match control:
		"BUTT_SIDESEL_SHIELD":                                     # 0x4eb4d0 case 0x7e
			Setup.next_team(setup, slot)
			refresh()
		"BUTT_SIDESEL_PLAYER":
			open_list(player_labels(slot), at, func(i): player_choice(slot, i))
		"BUTT_SIDESEL_RESOURCES":
			open_list(range(5).map(func(r): return String(strings(RESOURCE_STRINGS)[r]).strip_edges()), at,
				func(i): set_resources(slot, i), int(p.resources))
		# Race list (0x4eb4d0 case 0x7b, 17 entries; callback 0x4eb030 stores the race and clears the CustomAI name). The
		# local row and computer rows (kind 2, the host branch at line 155101) have it; open and closed rows have none. The
		# slot's race is independent of the hero's (HERO_RESEARCH.md "Milestone 11b").
		"BUTT_SIDESEL_RACE":
			open_list(race_labels(), at, func(i): set_race(slot, i), int(p.race))

func set_resources(slot: int, level: int):
	setup.players[slot].resources = level
	refresh()

func set_race(slot: int, race: int):
	Setup.set_race(setup, slot, race)
	refresh()

func start() -> bool:
	if hero == null or not map_selected:
		refresh()
		return false
	var startable: bool = Setup.can_start_random(setup) if Setup.is_random(setup) else Setup.active_players(Setup.resolve(setup)).size() >= 2
	if not startable:
		refresh()
		return false
	var rng := RandomNumberGenerator.new()
	Setup.roll_random_races(setup, func(sides): return rng.randi_range(1, sides))   # 0x4e6af4 (the menu generator: Open)
	Setup.save_options(setup.options)                              # 0x450760
	var handed := setup.duplicate(true)
	handed.options.game_speed = game_speed                         # 0x60c3ee carries into the match
	# 0x417730: the human's army budget; the setup levels 0xa479c8 hold the human heroes' levels (one human here).
	var level := int(hero.data.level)
	var temp: bool = bool(setup.options.get("temp_hero", false))
	if temp: level = int(setup.options.get("temp_hero_level", 10))   # 0x4e2660: every slot's level 0xa479c8 = the setting
	handed.army_budget = Army.human_budget(int(setup.options.army_points), bool(setup.options.handicap), level, [level])
	if temp:                                                       # 0x4e2660 -> 0x54b040(1, level): create the hero first
		var FrontEnd = load("res://menus/front_end.gd")
		FrontEnd.temp_request = {"setup": handed, "level": level}
		FrontEnd.start_screen = "temp"
		get_tree().change_scene_to_file("res://menus/front_end.tscn")
		return true
	Setup.pending = {"setup": handed, "hero_id": hero.data.id}
	get_tree().change_scene_to_file("res://menus/loading_screen.tscn")   # PNL_PROGRESSHT while main.tscn loads; RM-7: and the map generates
	return true

# ------------------------------------------------------------------------------------------------ self-test
var failed := false
var checks := 0

func check(condition: bool, text: String):
	checks += 1
	if not condition and not failed:
		failed = true
		push_error("Skirmish setup check failed: " + text)

func self_test():
	check(mouse_filter == Control.MOUSE_FILTER_IGNORE, "the root passes mouse events to _unhandled_input")
	# Opening: Random Map chosen, six open rows, nobody seated, Okay disabled, no rebuild-only lines.
	check(map_selected and selected_map == 0 and Setup.is_random(setup) and int(setup.sides) == 6 and int(setup.local) == -1 and has_item("PNL_SIDESEL_SIDE5/BUTT_SIDESEL_PLAYER#0"), "Random Map chosen, six rows (0x4e4000, 0x4f19f0(6))")
	check(canvas.control_text["PNL_SIDESEL_SIDE3/BUTT_SIDESEL_PLAYER#0"] == "Open" and not enabled("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_RACE#0"), "rows read Open, race disabled")
	check(not enabled("PNL_SS/BUTT_OKAY_STARTUP#0"), "Okay disabled until a side is seated (0x4e7760, 0x4eacd0)")
	check(help == ["", "", ""] and canvas.control_text["PNL_SS/STR_SMALL_450#0"] == "", "no rebuild-only text lines")
	# F6: the opening rows (0x4f19f0): player button enabled, race Random and resources Average shown but disabled.
	for i in 6:
		var row := "PNL_SIDESEL_SIDE%d/" % i
		check(enabled(row + "BUTT_SIDESEL_PLAYER#0") and canvas.control_text[row + "BUTT_SIDESEL_RACE#0"] == "Random"
			and canvas.control_text[row + "BUTT_SIDESEL_RESOURCES#0"] == "Average" and not enabled(row + "BUTT_SIDESEL_RESOURCES#0")
			and not enabled(row + "BUTT_SIDESEL_SHIELD#0"), "opening row %d: Open (enabled), Random, Average (0x4f19f0)" % i)
	# F6: single player leaves out the Ready column, the chat and the speed button (0x4e4000; original screenshot).
	var cover := item("PNL_SS_COVERREADY/IM_SS_COVERREADY#0")
	var toggle := item("PNL_SIDESEL_SIDE5/BUTT_SIDESEL_READY#0")
	check(not cover.is_empty() and cover.rect == Rect2i(500, 160, 85, 225) and int(cover.z) > int(toggle.z)
		and Rect2(cover.rect).encloses(Rect2(toggle.rect)) and not enabled("PNL_SIDESEL_SIDE5/BUTT_SIDESEL_READY#0"), "the Ready cover (0x150 at 500, 160) hides the toggles")
	check(not has_item("PNL_SS/IM_SS_MP_CHAT#0") and not has_item("PNL_SS/EDIT_SIDESEL_CHAT#0") and not has_item("PNL_SS/BUTT_SS_GAMESPEED#0"), "no chat or game speed")
	check(has_item("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_RACE#0") and has_item("PNL_SS/SBAR_H170#0") and has_item("PNL_SS/BUTT_SS_RES#0"), "the rest of the panels stay")
	# Deliberate: the resolution button chooses Legacy / Enhanced visuals (Options > Visuals > Enhanced Visuals).
	var was_enhanced := bool(Display.setting_visuals_enhanced())
	check(enabled("PNL_SS/BUTT_SS_RES#0") and canvas.control_text["PNL_SS/BUTT_SS_RES#0"] == VISUALS_LABELS[1 if was_enhanced else 0], "the visuals button is enabled and shows the setting")
	press("PNL_SS/BUTT_SS_RES#0")
	check(is_list_open() and list_labels == VISUALS_LABELS, "the visuals list: Legacy, Enhanced")
	close_list()
	choose_visuals(not was_enhanced)
	check(bool(Display.setting_visuals_enhanced()) == (not was_enhanced) and canvas.control_text["PNL_SS/BUTT_SS_RES#0"] == VISUALS_LABELS[0 if was_enhanced else 1], "choosing switches Enhanced Visuals")
	choose_visuals(was_enhanced)
	# Playtest 2026-11-10: a list entry over another option button; the press chooses the entry and its release must not
	# press the button underneath (ui_screen.gd swallow_release).
	var under: Vector2 = Rect2(item(key(SS, "BUTT_SS_BUTTON", 0)).rect).get_center()
	var visual_row := 1 if was_enhanced else 0
	open_list(VISUALS_LABELS, under - Vector2(5, LIST_ROW * visual_row + 3), func(i): choose_visuals(i == 1), visual_row)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = view.position + under * (view.size / Vector2(BASE))
		_unhandled_input(click)
	check(not is_list_open() and bool(Display.setting_visuals_enhanced()) == was_enhanced, "a list entry over the Victory button: the release opens nothing underneath")
	press("PNL_SIDESEL_SIDE2/BUTT_SIDESEL_PLAYER#0")
	check(is_list_open() and list_labels[0] == "AI: Squire" and list_labels[list_labels.size() - 1] == "Closed", "a row's player list opens before the map is chosen")
	close_list()
	# F5: the map list in the list's fonts, Random Map first, then every imported scenario by name.
	var names: Array = canvas.control_text["PNL_SS/LB_SS_MAPS#0"].split("\n")
	var expected: Array = MapData.index().map(func(e): return String(e.name))
	expected.sort_custom(func(a, b): return a.naturalnocasecmp_to(b) < 0)
	expected.push_front("Random Map")
	check(names == expected and names[0] == "Random Map" and names.has("Desert Sands") and names.has("The Hill") and names.size() == 23, "the map list: Random Map, then the imported scenarios by name")
	check(int(canvas.control_list["PNL_SS/LB_SS_MAPS#0"]) == 0 and not canvas.bitmap_override_by_key.has("PNL_SS/IM_STRATMAP_SIDESEL#0"), "Random Map chosen, the black strategic map under its panel")
	random_map_checks()
	var lb := item("PNL_SS/LB_SS_MAPS#0")
	check(canvas.list_row_height(lb.element) == 19 and canvas.font_number(String(lb.element.fonts[1])) == 6, "19-pixel rows, FO_MEDIUMLIGHT for the chosen entry")
	check(canvas.list_row_at(lb, Vector2(lb.rect.position) + Vector2(20, 19 + 5)) == 1 and canvas.list_row_at(lb, Vector2(lb.rect.position) + Vector2(20, 19 * (names.size() + 1))) == -1, "a click picks the 19-pixel row; below the entries nothing")   # M-2: below the last imported map
	var bar_entry: Dictionary = canvas.list_bars["PNL_SS/SBAR_V156B#0"]
	check(int(bar_entry.value) == 0 and int(bar_entry.max) == 23 * 19 - 115 + 2 and int(bar_entry.page) == 115 - 19 and int(bar_entry.state) == canvas.BAR_AT_MIN, "the bar's range from the 23 entries (0x461fe0), the thumb at the top")
	# Choosing the map (0x4e7760) with a real press on a list row; tests/test_map_list.gd scrolls to the rows further down.
	var list_rect_px := Rect2(item("PNL_SS/LB_SS_MAPS#0").rect)
	var desert_row: int = names.find("Desert Sands")
	var click_at := InputEventMouseButton.new()
	click_at.button_index = MOUSE_BUTTON_LEFT
	click_at.pressed = true
	click_at.position = view.position + (list_rect_px.position + Vector2(20, 8)) * (view.size / Vector2(BASE))
	_unhandled_input(click_at)
	check(map_selected and selected_map == 0 and Setup.is_random(setup), "a press on the first row keeps %s" % names[0])
	select_map(desert_row)
	check(map_selected and String(map_entries[selected_map].name) == "Desert Sands" and int(setup.sides) == 2 and not has_item("PNL_SIDESEL_SIDE2/BUTT_SIDESEL_PLAYER#0"),
		"choosing Desert Sands re-opens its two rows (%s, %d sides)" % [String(map_entries[selected_map].name) if selected_map >= 0 else "none", int(setup.sides)])
	check(int(canvas.control_list["PNL_SS/LB_SS_MAPS#0"]) == desert_row and has_item("PNL_SS_COVERREADY/IM_SS_COVERREADY#0"), "Desert Sands chosen (white); the Ready cover stays")
	check(not has_item(RM + "/BUTT_RM_SIZE#0") and not Setup.is_random(setup), "a scenario closes the Random Map panel (0x4e7760)")
	var preview := String(canvas.bitmap_override_by_key.get("PNL_SS/IM_STRATMAP_SIDESEL#0", ""))
	var preview_texture := canvas.texture(preview)
	check(preview_texture != null and preview_texture.get_size() == Vector2(128, 128) and String(layout.exported_bitmaps[preview].file) == "maps/desert-sands/scenario_minimap.png", "the left pane shows the scenario's preview (0x4e7760 -> 0x41c0c0)")
	var items := canvas.items()
	var row1: Dictionary = items.filter(func(i): return i.key == "PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0")[0]
	check(row1.rect.position == Vector2i(22 + 3, 201 + 31), "side row 1 at (22, 232) (0x4f19f0)")
	check(setup.players[0].start == Vector2i(12, 64) and setup.players[1].start == Vector2i(113, 64), "Desert Sands sides")
	check(int(setup.players[0].map_race) == 1 and int(setup.players[1].map_race) == 14, "map side races (Dwarf, Swarm) read from the side records")
	check(int(setup.players[0].resources) == 2 and int(setup.players[1].difficulty) == 2, "side record resources 2 and the map's AI level (Knight)")
	check(canvas.control_text["PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0"] == "AI: Knight", "computer label")
	check(canvas.control_text["PNL_SIDESEL_SIDE0/BUTT_SIDESEL_RACE#0"] == "Dwarf" and canvas.control_text["PNL_SIDESEL_SIDE1/BUTT_SIDESEL_RACE#0"] == "The Swarm", "race labels from the race list")
	# Race list (17 entries) instead of a cycle.
	last_point = Vector2(300, 240)
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_RACE#0")
	check(is_list_open() and list_labels.size() == 17 and list_labels[0] == "Knight" and list_labels[16] == "Random" and list_hover == 14, "the race list (0xf, 0x68, Random) marks The Swarm")
	check(is_equal_approx(list_rect.position.x, 285.0) and is_equal_approx(list_rect.position.y, 240.0), "the list opens at the mouse x - 15")
	choose_list(0)
	check(int(setup.players[1].race) == 0 and canvas.control_text["PNL_SIDESEL_SIDE1/BUTT_SIDESEL_RACE#0"] == "Knight", "Knight chosen for the computer")
	press("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_RACE#0")
	choose_list(0)
	check(int(setup.players[0].race) == 0 and Setup.resolve(setup).slots[0].race == 0, "local race choice reaches the player table")
	# Resources list.
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_RESOURCES#0")
	check(list_labels == ["Very Low", "Low", "Average", "High", "Very High"], "resources list (0x66)")
	choose_list(3)
	check(int(setup.players[1].resources) == 3 and canvas.control_text["PNL_SIDESEL_SIDE1/BUTT_SIDESEL_RESOURCES#0"] == "High", "resources High")
	# Player list for a computer row (side AI 2): Squire .. Emperor, Open, Closed (0x4eb110).
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0")
	check(list_labels.size() == 8 and list_labels[0] == "AI: Squire" and list_labels[5] == "AI: Emperor" and list_labels[6] == "Open" and list_labels[7] == "Closed", "player list of a side with AI value 2")
	choose_list(2)
	check(int(setup.players[1].kind) == Setup.COMPUTER and int(setup.players[1].difficulty) == 3 and canvas.control_text["PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0"] == "AI: Lord", "index 2 = AI: Lord")
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0")
	choose_list(7)
	check(int(setup.players[1].kind) == Setup.CLOSED and not enabled("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_RESOURCES#0") and Setup.active_players(Setup.resolve(setup)) == [0], "Closed: inactive, resources disabled")
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0")
	choose_list(6)
	check(int(setup.players[1].kind) == Setup.OPEN, "Open")
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_PLAYER#0")
	choose_list(1)
	check(int(setup.players[1].kind) == Setup.COMPUTER and int(setup.players[1].difficulty) == 2, "back to AI: Knight")
	# Option lists and their effects.
	check(canvas.control_text["PNL_SS/BUTT_SS_BUTTON#0"] == "Standard Victory" and canvas.control_text["PNL_SS/BUTT_SS_BUTTON#3"] == "Fog of War", "option labels")
	for i in 6: check(enabled("PNL_SS/BUTT_SS_BUTTON#%d" % i), "option button %d enabled" % i)
	press("PNL_SS/BUTT_SS_BUTTON#0")
	check(list_labels.size() == 12 and list_labels[0] == "Standard Victory" and list_labels[11] == "Pitched Battle", "victory list: 12 entries without Capture the Flag")
	choose_list(1)
	check(int(setup.options.victory) == 1 and int(setup.options.build_level) == 5, "Raze All Buildings stored")
	press("PNL_SS/BUTT_SS_BUTTON#1")
	check(list_labels.size() == 5 and list_labels[0] == "Keep Level 1", "victory 1 shifts the build list to Keep Level 1..5")
	choose_list(0)
	check(int(setup.options.build_level) == 1, "Keep Level 1")
	press("PNL_SS/BUTT_SS_BUTTON#0")
	choose_list(0)
	press("PNL_SS/BUTT_SS_BUTTON#1")
	check(list_labels.size() == 6 and list_labels[0] == "No Building" and list_labels[5] == "Keep Level 5", "build list: No Building, Keep Level 1..5")
	choose_list(0)
	check(int(setup.options.build_level) == 0 and canvas.control_text["PNL_SS/BUTT_SS_BUTTON#1"] == "No Building", "No Building")
	check(int(Setup.resolve(setup).slots[1].difficulty) == 7, "BuildLevel 0 makes the computer Rampant (0x4de740)")
	press("PNL_SS/BUTT_SS_BUTTON#1")
	choose_list(5)
	press("PNL_SS/BUTT_SS_BUTTON#3")
	check(list_labels == ["No Fog Of War", "Fog of War", "Line Of Sight"], "vision list")
	choose_list(0)
	check(int(setup.options.vision) == 0 and help[0] == "No Fog Of War" and help[1] == "Fog Of War is turned off", "vision stored, its help lines shown")
	press("PNL_SS/BUTT_SS_BUTTON#3")
	choose_list(1)
	press("PNL_SS/BUTT_SS_BUTTON#2")
	choose_list(0)
	check(not bool(setup.options.hidden_map), "Exposed Map")
	press("PNL_SS/BUTT_SS_BUTTON#2")
	choose_list(1)
	press("PNL_SS/BUTT_SS_BUTTON#4")
	choose_list(0)
	check(bool(setup.options.handicap) and canvas.control_text["PNL_SS/BUTT_SS_BUTTON#4"] == "Handicapping On", "handicap on")
	press("PNL_SS/BUTT_SS_BUTTON#5")
	choose_list(1)
	check(not bool(setup.options.quests) and canvas.control_text["PNL_SS/BUTT_SS_BUTTON#5"] == "Quests Off", "quests off")
	# Hover help (0x4e5120 / 0x4debb0 / 0x4df710).
	hovered_changed(item("PNL_SS/BUTT_OKAY_STARTUP#0"))
	check(help[0] == "Let the War begin!" and help[1] == "", "Okay hover line")
	hovered_changed(item("PNL_SS/BUTT_SS_BUTTON#0"))
	check(help == ["Victory Conditions", "Player must destroy all enemy units and buildings.", ""], "victory hover lines")
	hovered_changed({})
	check(help == ["", "", ""], "leaving clears the lines")
	# S-2: More Options and Rules, the victory list's side effects.
	check(enabled("PNL_SS/BUTT_SS_ADVANCED_OPTIONS#0") and enabled("PNL_SS/BUTT_SS_GAMEMODS#0"), "More Options and Rules enabled")
	press("PNL_SS/BUTT_SS_ADVANCED_OPTIONS#0")
	check(sub_panel == MORE_PANEL and canvas.control_text["PNL_SS_ADVANCEDOPTIONS/BUTT_SS_OPTIONS_CHECKBOX#0"] == "Random Weather" and canvas.control_text["PNL_SS_ADVANCEDOPTIONS/BUTT_SS_OPTIONS_CHECKBOX#6"] == "No Hero Items", "More Options rows (0xe9, 0xec)")
	check(hit(Vector2(item("PNL_SS/BUTT_OKAY_STARTUP#0").rect.position) + Vector2(4, 4)).is_empty(), "the panel is modal")
	check(int(canvas.control_state["PNL_SS_ADVANCEDOPTIONS/BUTT_SS_OPTIONS_CHECKBOX#1"]) == CHECKED and int(canvas.control_state["PNL_SS_ADVANCEDOPTIONS/SBAR_H170_2#0"]) == 3, "Resignation Kills Side ticked by default; no hero level without a temporary hero")
	press("PNL_SS_ADVANCEDOPTIONS/BUTT_SS_OPTIONS_CHECKBOX#6")
	press("PNL_SS_ADVANCEDOPTIONS/BUTT_SS_OPTIONS_CHECKBOX#3")
	check(int(canvas.control_state["PNL_SS_ADVANCEDOPTIONS/SBAR_H170_2#0"]) == 0 and String(canvas.control_text["PNL_SS_ADVANCEDOPTIONS/STR_MEDIUMDLG_120#0"]).ends_with(" 10"), "the temporary hero shows its level")
	press("PNL_SS_ADVANCEDOPTIONS/BUTT_CANCEL_160#0")
	check(sub_panel == "" and not bool(setup.options.no_hero_items) and not has_item("PNL_SS_ADVANCEDOPTIONS/BUTT_OKAY_160#0"), "Cancel drops the working copy")
	press("PNL_SS/BUTT_SS_ADVANCED_OPTIONS#0")
	press("PNL_SS_ADVANCEDOPTIONS/BUTT_SS_OPTIONS_CHECKBOX#6")
	press("PNL_SS_ADVANCEDOPTIONS/BUTT_OKAY_160#0")
	check(bool(setup.options.no_hero_items), "Okay keeps it (0x4ea040)")
	press("PNL_SS/BUTT_SS_GAMEMODS#0")
	check(sub_panel == RULES_PANEL and canvas.control_text["PNL_SS_GAMEMODS/BUTT_SS_GAMEMOD_CHECK#0"] == "No Dragons" and canvas.control_text["PNL_SS_GAMEMODS/BUTT_SS_GAMEMOD_CHECK#6"] == "No Heroes", "Rules rows (0xee)")
	press("PNL_SS_GAMEMODS/BUTT_SS_GAMEMOD_CHECK#6")
	press("PNL_SS_GAMEMODS/BUTT_OKAY_160#0")
	press("PNL_SS/BUTT_SS_BUTTON#0")
	check(bool(setup.options.no_heroes) and list_labels.size() == 10 and not "Assassination" in list_labels and not "Pitched Battle" in list_labels, "No Heroes leaves Assassination and Pitched Battle out (0x4dfec0)")
	close_list()
	setup.options.no_heroes = false
	setup.options.no_hero_items = false
	press("PNL_SS/BUTT_SS_BUTTON#0")
	choose_list(11)
	check(int(setup.options.victory) == 0xb and int(setup.options.army_points) == 50 and not enabled("PNL_SS/BUTT_SS_BUTTON#1"), "Pitched Battle: 50 points, the build level button off (0x4e3130)")
	press("PNL_SS/BUTT_SS_BUTTON#0")
	choose_list(5)
	check(not enabled("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_SHIELD#0"), "Slug Fest takes the shields (0x4e3c60 case 4)")
	press("PNL_SS/BUTT_SS_BUTTON#0")
	choose_list(0)
	check(int(setup.options.army_points) == 0 and int(setup.options.build_level) == 5 and enabled("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_SHIELD#0"), "Standard Victory gives them back")
	# Skirmish setup session: the Army Setup Points slider (0x1777), the shield (0x7e), saved options, Random races.
	var bar := item("PNL_SS/SBAR_H170#0")
	check(bar.rect == Rect2i(590, 422, 170, 32) and canvas.control_text["PNL_SS/STR_MEDIUM30#0"] == "0", "slider at (590, 422), value 0 (code default)")
	set_army_points_at(bar.rect.end.x + 20)
	check(int(setup.options.army_points) == 50 and canvas.control_text["PNL_SS/STR_MEDIUM30#0"] == "50", "slider end = 50 (range 0..50)")
	set_army_points_at(bar.rect.position.x)
	check(int(setup.options.army_points) == 0, "slider start = 0")
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = view.position + (Vector2(bar.rect.position) + Vector2(15 + 28, 16)) * (view.size / Vector2(BASE))
	_unhandled_input(press_event)
	press_event.pressed = false
	_unhandled_input(press_event)
	check(int(setup.options.army_points) == 10 and is_equal_approx(float(canvas.control_scroll["PNL_SS/SBAR_H170#0"]), 0.2), "a click on the slider sets 10")
	check(enabled("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_SHIELD#0") and canvas.control_offset["PNL_SIDESEL_SIDE1/IM_ICON_SHLDCLRS#0"] == Vector2i(0, 0), "shield: slot 1 colour 0 (red), team 0")
	press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_SHIELD#0")
	check(int(setup.players[1].team) == 1 and canvas.control_offset["PNL_SIDESEL_SIDE1/IM_ICON_SHLDCLRS#0"] == Vector2i(0, 20), "the shield steps the team (0x4eb4d0 case 0x7e)")
	press("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_SHIELD#0")
	check(canvas.control_offset["PNL_SIDESEL_SIDE0/IM_ICON_SHLDCLRS#0"] == Vector2i(25, 20) and Setup.resolve(setup).allied[1] == 1, "same team: allied (0x748915)")
	for i in 3: press("PNL_SIDESEL_SIDE1/BUTT_SIDESEL_SHIELD#0")
	check(int(setup.players[1].team) == 0 and Setup.resolve(setup).allied[1] == 0, "team wraps 3 -> 0")
	press("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_SHIELD#0")
	for i in 2: press("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_SHIELD#0")
	select_map(desert_row)
	check(int(setup.options.army_points) == 10 and int(setup.options.vision) == 1, "choosing the map keeps the options (0x4e7760)")
	check(Setup.save_options(setup.options), "options saved (0x450760)")
	var reloaded: Dictionary = Setup.defaults(map).options
	Setup.load_saved_options(reloaded)
	check(int(reloaded.army_points) == 10 and not bool(reloaded.quests) and bool(reloaded.handicap), "saved Random Map Data reloads (0x450970)")
	Setup.set_race(setup, 1, Setup.RANDOM_RACE)
	check(int(Setup.resolve(setup).slots[1].race) == 1, "an unrolled Random slot takes 0x60f0f0's static entry (slot 1 -> 1)")
	Setup.roll_random_races(setup, func(sides): return sides)
	check(int(Setup.resolve(setup).slots[1].race) == 15, "Okay's roll 1d16 - 1 (0x4e6af4)")
	# Game speed: the options' GameSpeed (0x4e47e0); the speed button is left out, so Esc presses nothing (0x4631d0).
	check(game_speed == int(Settings.current().get_value("GameSpeed")) and hotkey_buttons(0x1b).is_empty(), "speed from the options, no Esc button")
	# The Hill (W1): its four sides, its preview.
	var hill := map_entries.map(func(e): return String(e.name)).find("The Hill")
	check(select_map(hill) and int(setup.sides) == 4 and has_item("PNL_SIDESEL_SIDE3/BUTT_SIDESEL_PLAYER#0") and not has_item("PNL_SIDESEL_SIDE4/BUTT_SIDESEL_PLAYER#0"), "The Hill: four rows")
	check(int(canvas.control_list["PNL_SS/LB_SS_MAPS#0"]) == hill and String(canvas.bitmap_override_by_key["PNL_SS/IM_STRATMAP_SIDESEL#0"]).ends_with("the-hill"), "The Hill chosen, its preview shown")
	for i in 4:
		var row := "PNL_SIDESEL_SIDE%d/" % i
		check(canvas.control_text[row + "BUTT_SIDESEL_RACE#0"] != "" and canvas.control_text[row + "BUTT_SIDESEL_RESOURCES#0"] != "", "The Hill row %d shows race and resources" % i)
	check(handle_key(KEY_F1) and help_screen == 10, "F1 shows the setup help (0x4e52cb)")
	close_screen_help()
	check(not hit(Vector2(400, 300)).has("key") or hit(Vector2(400, 300)).control.name != "BUTT_SS_FULLSCREEN", "fullscreen hotspot ignored")
	check(presentation_rect() == Rect2(240, 0, 1440, 1080), "1080p presentation")
	check(select_map(0) and has_item(RM + "/BUTT_RM_SIZE#0") and int(setup.sides) == 6 and int(setup.options.army_points) == 10, "Random Map again: its panel, six rows, the options kept")
	check(not canvas.bitmap_override_by_key.has("PNL_SS/IM_STRATMAP_SIDESEL#0"), "the scenario's preview leaves")
	check(hero == null and not enabled("PNL_SS/BUTT_OKAY_STARTUP#0"), "start disabled without a hero")
	check(not start(), "no start without a hero")
	DirAccess.remove_absolute(help_flags_path())
	DirAccess.remove_absolute(Setup.saved_options_path())
	DirAccess.remove_absolute("user://skirmish-menu-self-test-settings.cfg")
	Settings.use_file(Settings.DEFAULT_PATH)
	if failed:
		get_tree().quit(1)
		return
	print("Skirmish setup checks passed: %d" % checks)
	get_tree().quit()

## RM-6: the panel, its lists, the saved values, the seat.
func random_map_checks():
	var size := item(RM + "/BUTT_RM_SIZE#0")
	check(size.rect.position == RM_OFFSET + Vector2i(0, 14) and size.rect.size == Vector2i(128, 19) and int(size.z) > int(item("PNL_SS/IM_STRATMAP_SIDESEL#0").z), "panel 0xfe at (0x1e, 0x16) over the strategic map")
	var text := func(control): return String(canvas.control_text[RM + "/" + control + "#0"])
	check([text.call("BUTT_RM_SIZE"), text.call("BUTT_RM_TERRAIN"), text.call("BUTT_RM_ISLANDS"), text.call("BUTT_RM_CRITTERS"), text.call("BUTT_RM_RESOURCES")]
		== ["Large", "Grasslands", "No Utilities", "Few Animals", "Med Resources"], "the screenshot's defaults (0x450970)")
	check(Setup.save_options(setup.options), "defaults saved")
	last_point = Vector2(100, 60)
	press(RM + "/BUTT_RM_SIZE#0")
	check(list_labels == ["Small", "Medium", "Large", "X-Large", "Random"] and list_hover == 2, "the size list (0xb4, Random)")
	choose_list(4)
	check(int(setup.options.map_size) == 4 and text.call("BUTT_RM_SIZE") == "Random", "size Random: value 4")
	press(RM + "/BUTT_RM_TERRAIN#0")
	check(list_labels == ["Grasslands", "Plains", "Highlands", "Desert", "Lava", "Outlands", "Caverns", "Snow", "Wetlands", "Jungle", "Random"], "the terrain list (0xd8, 0xfa, Random)")
	choose_list(8)
	check(int(setup.options.terrain) == 8 and text.call("BUTT_RM_TERRAIN") == "Wetlands", "terrain 8: Wetlands")
	press(RM + "/BUTT_RM_ISLANDS#0")
	check(list_labels == ["No Utilities (Lairs, Shops and Temples)", "1 Utility", "2 Utilities", "3 Utilities", "4 Utilities", "Random"], "the utilities list (0x159, Random)")
	choose_list(3)
	check(int(setup.options.temples) == 3 and text.call("BUTT_RM_ISLANDS") == "3 Utilities", "3 Utilities")
	press(RM + "/BUTT_RM_ISLANDS#0")
	choose_list(1)
	check(text.call("BUTT_RM_ISLANDS") == "1 Utility", "1 Utility")
	press(RM + "/BUTT_RM_CRITTERS#0")
	check(list_labels == ["No Animals", "Few Animals", "Some Animals", "More Animals", "Lots of Animals", "Random"] and list_hover == 1, "the animals list (0xb6, Random)")
	choose_list(5)
	press(RM + "/BUTT_RM_RESOURCES#0")
	check(list_labels == ["Low Resources", "Med Resources", "High Resources", "Random"], "the resources list (0xb7, Random)")
	choose_list(2)
	check(int(setup.options.critters) == 5 and text.call("BUTT_RM_CRITTERS") == "Random" and text.call("BUTT_RM_RESOURCES") == "High Resources", "animals and resources stored")
	# Saved with the other values on Okay, "Random" kept (0x450760 runs before 0x4e2790 resolves it).
	var chosen: Dictionary = setup.options.duplicate(true)
	check(Setup.save_options(chosen), "the settings save")
	var read: Dictionary = Setup.random_setup().options
	Setup.load_saved_options(read)
	check(int(read.map_size) == 4 and int(read.terrain) == 8 and int(read.temples) == 1 and int(read.critters) == 5 and int(read.resource_level) == 2, "the settings reload (0x450970)")
	var saved := ConfigFile.new()
	check(saved.load(Setup.saved_options_path()) == OK and int(saved.get_value(Setup.SAVED_SECTION, "MapSize")) == 4 and int(saved.get_value(Setup.SAVED_SECTION, "CritterLevel")) == 5
		and int(saved.get_value(Setup.SAVED_SECTION, "NoStartingTowers")) == 0, "registry names MapSize, CritterLevel, NoStartingTowers")
	# A choice carries over a scenario and back: the block is not the scenario's.
	select_map(1)
	select_map(0)
	check(text.call("BUTT_RM_TERRAIN") == "Wetlands", "the panel keeps its values across a scenario")
	# Under the Greatest the panel ignores clicks (0x4e1390).
	setup.options.greatest = true
	press(RM + "/BUTT_RM_SIZE#0")
	check(not is_list_open(), "I Am The Greatest locks the panel")
	setup.options.greatest = false
	# The seat (0x4eb4d0 case 0x80): any row's list starts with the hero's name; a seat and a computer enable Okay.
	var real_hero = hero
	hero = {"data": {"id": "menu-test", "name": "Sir Test", "level": 1}}
	refresh()
	check(not enabled("PNL_SS/BUTT_OKAY_STARTUP#0"), "no seat, no Okay")
	press("PNL_SIDESEL_SIDE2/BUTT_SIDESEL_PLAYER#0")
	check(list_labels[0] == "Sir Test" and list_labels[1] == "AI: Squire", "the hero's name heads a row's list")
	choose_list(0)
	check(int(setup.local) == 2 and int(setup.players[2].kind) == Setup.HUMAN and canvas.control_text["PNL_SIDESEL_SIDE2/BUTT_SIDESEL_PLAYER#0"] == "Sir Test", "the hero takes row 2")
	check(not enabled("PNL_SS/BUTT_OKAY_STARTUP#0") and enabled("PNL_SIDESEL_SIDE2/BUTT_SIDESEL_RACE#0"), "one side is not enough (0x4eacd0); the seated row's race list opens")
	press("PNL_SIDESEL_SIDE0/BUTT_SIDESEL_PLAYER#0")
	choose_list(2)
	check(int(setup.players[0].kind) == Setup.COMPUTER and int(setup.players[0].difficulty) == 2 and enabled("PNL_SS/BUTT_OKAY_STARTUP#0"), "a computer row: Okay enabled")
	check(Setup.random_sides(setup).map(func(s): return int(s.slot)) == [0, 2], "the sides in slot order, a hole between them")
	setup.players[0].team = 1
	setup.players[2].team = 1
	check(not Setup.can_start_random(setup), "one team for all: no Okay (0x4eacd0)")
	setup.players[0].team = 0
	setup.players[2].team = 0
	press("PNL_SIDESEL_SIDE4/BUTT_SIDESEL_PLAYER#0")
	choose_list(0)
	check(int(setup.local) == 4 and int(setup.players[2].kind) == Setup.OPEN, "the seat moves, the row left is Open")
	press("PNL_SIDESEL_SIDE4/BUTT_SIDESEL_PLAYER#0")
	choose_list(list_labels.size() - 2)
	check(int(setup.local) == -1 and int(setup.players[4].kind) == Setup.OPEN and not enabled("PNL_SS/BUTT_OKAY_STARTUP#0"), "the seat can be given up")
	hero = real_hero
	setup.options.greatest = true                               # More Options' Okay without a hero
	edit_options = setup.options.duplicate(true)
	edit_options.greatest = true
	setup.options.greatest = false
	sub_panel = MORE_PANEL
	accept_sub_panel()
	check(int(setup.local) == 0 and int(setup.players[3].kind) == Setup.COMPUTER and int(setup.players[4].kind) == Setup.CLOSED, "the Greatest on Random Map: seat 0, three computers, two closed (0x4e7760)")
	setup.options.greatest = false
	Setup.apply_greatest(setup, false)
	check(int(setup.local) == -1, "and back")
	select_random_map(setup.options)
	refresh()

func capture():
	close_screen_help()
	await capture_png("res://.local/skirmish_setup_open.png")      # F5 / F6: the opening state
	last_point = Vector2(100, 60)
	press(RM + "/BUTT_RM_ISLANDS#0")
	await capture_png("res://.local/skirmish_random_list.png")     # RM-6
	close_list()
	select_map(1)
	hovered_changed(item("PNL_SS/BUTT_SS_BUTTON#0"))
	await capture_png("res://.local/skirmish_setup.png")
	clear_help()
	open_sub_panel(MORE_PANEL)
	edit_options.temp_hero = true
	refresh()
	await capture_png("res://.local/skirmish_more_options.png")    # S-2
	close_sub_panel()
	open_sub_panel(RULES_PANEL)
	await capture_png("res://.local/skirmish_rules.png")
	get_tree().quit()
