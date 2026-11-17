extends "res://core/ui_screen.gd"
## The front end (milestone 11-menus, UI_RESEARCH.md "Milestone 11"): the original's start-up into the main menu, the
## options screen, the skirmish hero book and hero creation. Every screen is the decoded XCI panel the original opens.
##
## Flow (Read):
## * Start-up 0x457190: the intro video plays only while TimesSkippedThroughIntro < 2 (videos are out of scope: skipped),
##   then the main menu 0x41d2c0: the theme starts at the first entry (0x608460 -> 0x5101d0(0)); PNL_MAINMENU (0x135) at
##   (2000, 2000) layer 100; the version string 1.03 (0x608308) in STR_SMALL80.
## * Main menu buttons (callback 0x41d730, release table 0x41da60 -> 0x41da80): Skirmish 0x98 -> game mode 0 and the hero
##   book (0x41dd50 -> 0x5536e0(0,0,0,1)); Options 0x9b -> 0x411110; Quit 0x9d -> 0x45c0c0. Campaign 0x9e, Multiplayer
##   0x99, Tutorial 0x9a and Editor 0x9c are out of scope: visible and disabled (deliberate scope limit).
## * Hero book 0x5536e0: no hero -> hero creation (0x54b040); else PNL_SH (0x13c) layer -1000 with the selected hero's
##   page (0x554260: name, race 0xf/0x68, class 8..0xb, "Level: %d", Portrait%02d.bmp; Previous/Next disabled with one
##   hero). Buttons (0x553860 -> 0x553bc0): Okay -> the skirmish setup (0x553dd0 -> 0x4e47e0); New Hero -> creation;
##   Previous / Next flip; Cancel -> main menu; Load Game is disabled without a saved game (0x5563a0).
## * Delete (0x555a70) and More Info (0x550790), FE-1 (HERO_RESEARCH.md "FE-1", Read): neither opens the panels the earlier
##   notes named. PNL_DELETEHERO (art BM_DELETEHERO_BG, absent) and PNL_VIEWHERO are never opened by those functions; Delete
##   opens the generic PNL_OKAYCANCEL (0x1a) box of 0x4361c0 ("Delete Hero", "<6[1]> <6[2]>"), whose art is in this install;
##   Okay runs 0x555ae0: a hero with a password (+0x41) first asks PNL_PASSWORD (0x104, 0x555bc0), then the record leaves
##   the hero book (0x555550) and the book starts again at the first hero, or at creation when none is left. More Info
##   opens PNL_HEROINFO (0x1c, layer 14000): the name, race, class, level, XP, next level, six tab pages and the Freeze
##   Hero check box (art BM_HEROINFOBG is in this install).
## * Hero creation 0x54b040: PNL_CREATEHERO (0x13f) layer 4000 (milestone 11b, HERO_RESEARCH.md "Milestone 11b"). The
##   race droplist (0x148 #0, callback 0x54bb50 -> 0x54bee0) lists the 16 races of 0x61204c in index order; the class
##   droplist (0x148 #1, 0x54bb90 -> 0x54bfe0) lists the 28 classes sorted by name (0x54b0c8). The screen opens on
##   0x61204c[0] / 0x6120fc[0] = Knight / Warrior (0x54b770(1)); each choice recomputes the stats, skills, portrait, art and
##   voice (Emulated, HeroRules.creation / race_identity). Customize (0x16e -> 0x54e2a0) opens PNL_CUSTOMIZEHERO (below).
## * Customize 0x54e2a0 (UI_RESEARCH.md "Interface gaps", Read from the decompile and the disassembled callback 0x54e320):
##   PNL_CUSTOMIZEHERO (0x1b) at layer 10000 over the creation screen, editing the record being created in place. Texts
##   (0x54e850): title section 7 [0], labels Portrait / Avatar / Password (optional) / Voice Set / Mode (7 [1..5]); the
##   portrait Portrait%02d.bmp of +0x58; the voice droplist (0x148 #0) labelled with Names.cfg [VOICE_NAMEnnn] of +0x60;
##   the mode droplist (0x148 #1) labelled 0xea [0] Normal Mode or [3] Ironman Mode by +0x54, with the mode's two lines of
##   section 0xeb wrapped in font 5 to 200 pixels into STR_SMALL200 #0..#4. The arrows (0x3a left, 0x3b right): #0 steps
##   the portrait through the race's list 0x612178 (0x54ec90), #1 the avatar art through 0x6140f8 (0x54ed30); a value not
##   in the list goes to the list's first entry. The avatar is the art's walk sheet (ANI slot 1) facing 3, drawn at (500,
##   0xb4) (0x54efa0), one frame further per timer message (0x54f180). The voice list is the race's English voice list
##   (0x612ff0); a choice (0x54ee50) sets +0x60 and plays the voice's DeathBlow sample. The password edit (0xbcb) writes
##   +0x41 on every change. Okay (0x137) and Cancel (0x136) both just close the panel (0x54e300): the changes stay.
##   FE-1: the mode list (0x54ee10) is enabled: Normal Mode / Ironman Mode write +0x54 (the profile's "mode"), and the
##   rules are in simulation/hero_match.gd (double XP, deleted at death: HERO_RESEARCH.md "FE-1"). The password is kept in
##   the profile's extensions and is asked for by the hero book's Delete.
## * The temporary hero (setup option "temp_hero", 0x4e2660 -> 0x54b040(1, level), Read): Start opens the creation
##   screen in temporary mode instead of the match: Cancel disabled (0x54b620), Customize's mode locked (0x54e790). Okay
##   (0x54bbd0) marks the record temporary (+4), sets its level (+0x34) to the setup's level, XP to that level's threshold
##   and the next threshold above (0x409ef0), writes nothing to the hero book, and opens the stats screen with `level`
##   points (0x552d90(1, level)), then the skills screen with `level` points (0x5522e0(1, level)), whose Okay starts the
##   match (0x552990 -> 0x4e2790). Deliberate (labelled): the rebuild hands the hero to those screens and the match
##   through a scratch store (TEMP_DIR), never the hero book.
## * Options 0x411110: the shared options screen (options_screen.gd, also opened in a match); Okay and Cancel return
##   to the main menu.
##
## Parity pass 2 (UI_RESEARCH.md "Parity pass 2", Read):
## * Main-menu hover (callback 0x41d730, message 0x12 -> 0x405360 on the effect object 0x6566a0, font 0x1a, mode 2): the
##   hovered button's own label (TXT_STARTUP [k]) floats over it, centred at x 400 with its top at y 207 / 252 / 297 /
##   342 / 387 / 472 / 162 (Skirmish .. Quit, Campaign); for 0x5dc (1500) ms (0x405500, every timer tick) the letter
##   spacing grows from 0 to 0x14 (20) pixels (0x58f600 = the font's extra spacing) and the blend level from 9 to 15
##   (0x58f5b0); up to 12 at once. The blend level is not an opacity (Read, 2026-11-11, glyph blitter 0x592b70): pixels of
##   coverage n <= level are skipped and the rest drawn at (n - level + 2) / 16, so the rim goes first and the core fades
##   (menu_float.gdshader). The timer rate that steps 0x405500 (message 9) is not traced; the rebuild steps every frame.
## * Main-menu keys (message 5): F1 (0x10a) opens the screen help 0x448870(0, 1); Space (0x20) floats the debug text
##   "Test" (0x608464) at (400, 300). Enter / Esc do nothing on any front-end screen (see ui_screen.gd).
## * First visits (0x448870(n, 0)): main menu 0, hero book 1, hero creation 2; F1 on those screens shows them again.
## * Tip of the day (0x453e30, at the first main-menu entry when no screen help popped up and TipOfTheDay is on):
##   PNL_TIPOFTHEDAY (0x167) at layer 30000, title TXT_TIPOFTHEDAY [1], one tip of English/TipOfTheDay.xml (0x454110: a
##   roll 1..number) wrapped in font 0x17 to 0x118 pixels into five STR_PARCHSMALL_L400 lines, the checkbox 0x18c set to
##   the option; ticking it stores TipOfTheDay and saves the options (0x4540b0 -> 0x451b10); Done (0x176) closes it.
##   The roll's generator and the checkbox frame for "ticked" are Open (randi; state 2, as the option tabs).
## * Drop-down lists: the original's one-column list at the click point (0x45cfe0, ui_screen.gd).

const Store = preload("res://simulation/hero_store.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Rules = preload("res://simulation/hero_rules.gd")
const Effects = preload("res://simulation/hero_effects.gd")
const Settings = preload("res://simulation/game_settings.gd")
const OptionsScreen = preload("res://menus/options_screen.gd")
const SaveGame = preload("res://simulation/save_game.gd")

const MAIN := "PNL_MAINMENU"
const OPTIONS := "PNL_GAMEOPTIONS"
const BOOK := "PNL_SH"
const CREATE := "PNL_CREATEHERO"
const CUSTOMIZE := "PNL_CUSTOMIZEHERO"
const OKAYCANCEL := "PNL_OKAYCANCEL"       # 0x1a: the generic box 0x4361c0 (Delete's confirmation)
const PASSWORD := "PNL_PASSWORD"            # 0x104: 0x555bc0 (Delete of a hero with a password)
const HEROINFO := "PNL_HEROINFO"            # 0x1c: More Info 0x550790
const INFO_TAB_X := 99                      # PAD_HEROINFOTABS (99, 238), six tabs of 100 pixels: 0x5508a7 = (x - 99) / 100
const INFO_PAGE := Vector2(99, 0x106)       # 0x550d10: the page is drawn at (99, 0x106)
const INFO_SEPARATOR := "    "              # 0x614c2c, between the two effects of one line (0x550e10)
const MODE_NORMAL := 0
const MODE_IRONMAN := 1                      # +0x54 (the list has these two entries)
const AVATAR_AT := Vector2(500, 0xb4)       # 0x54efa0
const AVATAR_FACING := 3                    # 0x487f20(art, 1, 0, 3, frame, ...)
const AVATAR_TICK_MS := 100                 # Provisional: the panel's timer message rate is not traced
const PASSWORD_LENGTH := 5                  # EDIT_PASSWORD max_length
const TEMP_DIR := "user://temporary-hero"   # deliberate: the temporary hero's scratch store (not the hero book)
const TEMP_ID := "temporary-hero"
const TIP := "PNL_TIPOFTHEDAY"
const VERSION := "1.03"                     # 0x608308
const MAX_NAME := 19                        # hero_profile.gd (the original edit control holds 19 characters)
## 0x41d730 message 0x12: label index (TXT_STARTUP) and the float's top y per main-menu button (x 400).
const FLOAT_BUTTONS := {"BUTT_MM_SINGLEPLAYER": [0, 207], "BUTT_MM_MULTIPLAYER": [1, 252], "BUTT_MM_TUTORIAL": [2, 297],
	"BUTT_MM_OPTIONS": [3, 342], "BUTT_MM_EDITOR": [4, 387], "BUTT_MM_QUIT": [5, 472], "BUTT_MM_CAMPAIGN": [6, 162]}
const FLOAT_FONT := 0x1a
const FLOAT_MS := 0x5dc
const FLOAT_SPACING := 0x14
const FLOAT_SLOTS := 12
const TIP_FONT := 0x17
const TIP_WRAP := 0x118

## Where the other scenes return: "main" (default), "book" (the -Skirmish switch, setup Cancel is the main menu).
static var start_screen := "main"
## 0x41d2c0: the tip of the day only follows the first main-menu entry of a session (one-shot 0x608460).
static var session_first_menu := true
## The temporary hero request from the skirmish setup's Start (0x4e2660): {"level", "setup"}.
static var temp_request: Dictionary = {}

var screen := ""
var store := Store.new()
var settings
var options: Node = null                    # the open options screen (options_screen.gd)
var heroes: Array = []                      # [{id, name}] in list order
var hero_index := 0
var hero_name := ""
var message := ""
var drop_row := -1                          # the droplist instance whose list is open (0x45cfe0), or -1
var create_race := 0                        # PNL_CREATEHERO choices (0x54b770(1): 0x61204c[0], 0x6120fc[0])
var create_class := 0
var create_portrait := 0                    # the record being created: +0x58 portrait, +0x5c art, +0x60 voice, +0x41 password
var create_art := ""
var create_voice := ""
var create_password := ""
var create_mode := MODE_NORMAL              # +0x54 of the record being created (Customize's mode list)
var popup := ""                             # the modal dialog over the hero book: "delete", "password" or "info"
var popup_password := ""                    # PNL_PASSWORD's edit text
var info_tab := 0                           # 0xb98990: the open More Info page
var avatar_frame := 0                      # 0xb92522
var temporary := false                      # 0xb92518: the creation screen makes a temporary hero
var temp_dir := TEMP_DIR
var avatar_ms := 0
var self_test_mode := false
var floats: Array = []                      # 0x405360 slots: {"text", "y", "start_ms"}
var tip_open := false
var tip_index := -1
var clock_ms := -1                          # tests drive the float clock; -1 = real time
var float_layer := FloatLayer.new()         # the floats on their own layer: the blend-level shader (menu_float.gdshader)

class FloatLayer extends Node2D:
	var owner_screen
	func _draw():
		if owner_screen != null: owner_screen.draw_floats(self)

## WBC3 Redux (PACKAGING.md "Name"): a red ink stamp over the lower right of the title's "III", main menu only. Our own
## drawing in the original 800x600 coordinates, with the game's imported heading font; nothing of the original art is
## changed.
class TitleStamp extends Node2D:
	const CENTRE := Vector2(598, 112)
	const SIZE := Vector2(118, 36)
	const ANGLE := -0.16                 # radians, about -9 degrees
	const INK := Color(0.74, 0.11, 0.07, 0.93)
	const SHADOW := Color(0, 0, 0, 0.45)
	const TEXT := "REDUX"
	const FONT_SIZE := 25
	const SPACING := 3.0
	var font: Font
	func _draw():
		if font == null: return
		for pass_index in 2:                  # a soft shadow first, then the ink
			var colour := SHADOW if pass_index == 0 else INK
			var shift := Vector2(1.5, 1.5) if pass_index == 0 else Vector2.ZERO
			draw_set_transform(CENTRE + shift, ANGLE)
			var outer := Rect2(-SIZE / 2, SIZE)
			draw_rect(outer, colour, false, 3.0)
			draw_rect(outer.grow(-5), colour, false, 1.2)
			var widths: Array = []
			var total := 0.0
			for ch in TEXT:
				var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
				widths.append(w)
				total += w
			total += SPACING * (TEXT.length() - 1)
			var x := -total / 2
			var baseline := font.get_ascent(FONT_SIZE) / 2 - font.get_descent(FONT_SIZE) / 2 + 1
			for i in TEXT.length():
				for dx in [0.0, 0.7]:          # drawn twice, a hair apart: heavier ink
					draw_string(font, Vector2(x + dx, baseline), TEXT[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
				x += widths[i] + SPACING
		draw_set_transform(Vector2.ZERO)

var title_stamp := TitleStamp.new()

var drop_rect: Rect2:
	get: return list_rect

func _ready():
	if "--prepare-assets" in OS.get_cmdline_user_args():   # display.gd prepares the data folder and quits
		for node in [viewport, canvas, view, backdrop, overlay, float_layer, title_stamp]:   # member nodes, only parented in _ready
			if is_instance_valid(node) and node.get_parent() == null: node.free()
		queue_free()
		return
	if not Assets.imported():   # PACKAGING.md step 3: no import in the data folder (the menus need its art and fonts)
		show_missing_data()
		return
	self_test_mode = "--self-test" in OS.get_cmdline_user_args()
	if self_test_mode:
		Settings.use_file("user://front-end-self-test-settings.cfg")
		store = Store.new("user://front-end-self-test-heroes")
	setup_screen()
	float_layer.owner_screen = self
	float_layer.z_index = 19                   # above the panels, below the list and the screen help
	var float_material := ShaderMaterial.new()
	float_material.shader = preload("res://visuals/menu_float.gdshader")
	float_layer.material = float_material
	viewport.add_child(float_layer)
	title_stamp.font = Assets.font("ui_font_MainFont.ttf")
	title_stamp.z_index = 18                  # above the panels, below the floats and the screen help
	title_stamp.visible = false
	viewport.add_child(title_stamp)
	settings = Settings.current()
	if not self_test_mode: fit_window(get_window())
	if "--hero-book" in OS.get_cmdline_user_args(): start_screen = "book"
	if self_test_mode:
		call_deferred("self_test")
		return
	if "--capture" in OS.get_cmdline_user_args():
		call_deferred("capture")
		return
	for arg in OS.get_cmdline_user_args():
		# PACKAGING.md step 3: straight to the match scene on one map (the scene's own test set-up), to time a map load
		# in an exported build, where Godot refuses --scene.
		if String(arg).begins_with("--open-map="):
			preload("res://core/map_data.gd").select(String(arg).trim_prefix("--open-map="))
			get_tree().change_scene_to_file.call_deferred("res://battle/main.tscn")
			return
	var first := start_screen
	start_screen = "main"
	if first == "book": open_hero_book()
	elif first == "temp" and not temp_request.is_empty(): open_create(true)
	elif first_start(): open_options(OptionsScreen.ADVANCED)
	else: open_main()

# ------------------------------------------------------------------------------------------------ installed game
const FIRST_START_MARKER := "user://first_start_done"

## PACKAGING.md step 3: an installed game opens the options screen (display mode, resolution, visuals) once, at its
## first start, before the main menu; the marker keeps it to once. Source runs only with -- --first-run (testing).
static func first_start() -> bool:
	var forced := "--first-run" in OS.get_cmdline_user_args()
	if not forced and (not OS.has_feature("template") or FileAccess.file_exists(FIRST_START_MARKER)): return false
	var f := FileAccess.open(FIRST_START_MARKER, FileAccess.WRITE)
	if f != null: f.store_string(Time.get_datetime_string_from_system() + "\n")
	return true

## The data folder holds no import: a plain message instead of the menus (their art and fonts are in the import).
func show_missing_data():
	for node in [viewport, canvas, view, backdrop, overlay, float_layer, title_stamp]:   # member nodes, only parented in setup
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	set_process(false)                 # the menu's frame and input handlers use the freed nodes
	set_process_unhandled_input(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color(0.06, 0.05, 0.04)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.add_theme_constant_override("separation", 24)
	add_child(box)
	var text := Label.new()
	text.name = "MissingData"
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 20)
	text.text = ("The game data has not been imported yet.\n\n"
		+ "This game uses the art, sound and maps of your own copy of Warlords Battlecry III.\n"
		+ "Run \"Re-import game data\" from the Start menu and choose your Warlords Battlecry III folder.\n\n"
		+ "Looked in: " + Assets.root())
	box.add_child(text)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(160, 40)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	quit.grab_focus.call_deferred()

# ------------------------------------------------------------------------------------------------ screens
func reset_canvas():
	title_stamp.visible = false
	canvas.placements.clear()
	canvas.control_text.clear()
	canvas.control_state.clear()
	canvas.bitmap_override.clear()
	canvas.hovered = {}
	canvas.pressed = {}
	drop_row = -1
	close_list()
	close_screen_help()
	tip_open = false
	popup = ""
	floats.clear()
	float_layer.queue_redraw()                 # playtest 2026-11-12: the last float frame stayed on the next screen
	message = ""

## 0x41d2c0: the main menu. The theme starts at the first entry of the session.
func open_main():
	reset_canvas()
	screen = MAIN
	title_stamp.visible = true
	audio().menu_entered()
	place(MAIN, Vector2i(2000, 2000), 100)
	for control in ["BUTT_MM_CAMPAIGN", "BUTT_MM_MULTIPLAYER", "BUTT_MM_TUTORIAL", "BUTT_MM_EDITOR"]:
		canvas.control_state["%s/%s#0" % [MAIN, control]] = 3      # out of scope (deliberate): visible, disabled
	canvas.control_text["%s/STR_SMALL80#0" % MAIN] = VERSION
	canvas.queue_redraw()
	# 0x41d2c0: the screen help on the first visit, else (first entry of the session only) the tip of the day.
	var first := session_first_menu
	session_first_menu = false
	if not open_screen_help(0, false) and first: open_tip()

## 0x453e30: the tip of the day over the main menu (only when the TipOfTheDay option is on).
func open_tip(index: int = -1) -> bool:
	if int(settings.get_value("TipOfTheDay")) == 0: return false
	var tips: Array = layout.get("tips", [])
	var count: int = mini(int(layout.get("tips_number", tips.size())), tips.size())
	if count <= 0: return false
	tip_index = index if index >= 0 else randi_range(1, count) - 1     # 0x454110: 0x458e70(1, number, -1) (generator Open)
	place(TIP, Vector2i.ZERO, 30000)
	var lines := wrap_text(String(tips[tip_index]), TIP_FONT, TIP_WRAP, 5)
	for i in 5: canvas.control_text["%s/STR_PARCHSMALL_L400#%d" % [TIP, i]] = String(lines[i]) if i < lines.size() else ""
	canvas.control_text["%s/STR_LARGE400#0" % TIP] = string_at(0x138, 1)        # "Tip of the day"
	refresh_tip_check()
	tip_open = true
	canvas.queue_redraw()
	return true

func refresh_tip_check():
	canvas.control_state["%s/BUTT_TIPOFTHEDAY#0" % TIP] = 2 if int(settings.get_value("TipOfTheDay")) != 0 else 0   # ticked: Open

func close_tip():
	tip_open = false
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != TIP)
	for key in canvas.control_text.keys():
		if String(key).begins_with(TIP + "/"): canvas.control_text.erase(key)
	canvas.queue_redraw()

## 0x411110: the options screen over the (cleared) main menu; Okay / Cancel return to the main menu. `start_page`: the
## first tab (the first start of an installed game opens the display settings, OptionsScreen.ADVANCED).
func open_options(start_page := 0):
	reset_canvas()
	screen = OPTIONS
	options = OptionsScreen.new()
	options.start_page = start_page
	options.closed.connect(func(_saved):
		options = null
		settings = Settings.current()
		open_main())
	add_child(options)

func open_hero_book():
	heroes = []
	for row in store.list_profiles():
		if not row.has("error"): heroes.append({"id": row.id, "name": row.name})
	if heroes.is_empty():                                         # 0x5536e0: no hero -> creation (0x54b040(0, -1))
		open_create()
		return
	reset_canvas()
	screen = BOOK
	place(BOOK, Vector2i.ZERO, -1000)
	var selected = store.selected_profile()
	hero_index = 0
	if selected != null:
		for i in heroes.size():
			if heroes[i].id == selected.data.id: hero_index = i
	refresh_book()
	open_screen_help(1, false)                                     # 0x5536e0 -> 0x448870(1, 0)

func open_create(temp: bool = false):
	reset_canvas()
	screen = CREATE
	temporary = temp
	hero_name = ""
	create_race = int(Rules.race_droplist()[0])                    # 0x54b770(1): 0x54bee0(0x61204c[0])
	create_class = 0                                               # ... and 0x54bfe0(0x6120fc[0]) = Warrior
	reset_identity()
	create_password = ""
	create_mode = MODE_NORMAL
	place(CREATE, Vector2i.ZERO, 4000)
	refresh_create()
	open_screen_help(2, false)                                     # 0x54b040 -> 0x448870(2, 0)

# ------------------------------------------------------------------------------------------------ texts and states
func refresh_book():
	var t := canvas.control_text
	var s := canvas.control_state
	t["%s/STR_LARGE750#0" % BOOK] = string_at(2, 0)                  # "Select a Hero" (0x554140)
	var profile = store.load_profile(heroes[hero_index].id) if not heroes.is_empty() else null
	if profile != null:
		t["%s/STR_MEDIUM_LARGE_240#0" % BOOK] = String(profile.data.name)
		t["%s/STR_SMALL220#0" % BOOK] = race_text(int(profile.data.race_id))          # sections 0xf / 0x68 (0x554260)
		t["%s/STR_SMALL220#1" % BOOK] = class_text(int(profile.data.class_id))        # sections 8..0xb
		t["%s/STR_SMALL220#2" % BOOK] = string_at(5, 4) % int(profile.data.level)     # "Level: %d"
		canvas.bitmap_override["BM_PORTRAIT"] = portrait_key(int(profile.data.portrait_id))
	var one := heroes.size() <= 1
	s["%s/BUTT_PREVIOUS#0" % BOOK] = 3 if one else 0
	s["%s/BUTT_NEXT#0" % BOOK] = 3 if one else 0
	s["%s/BUTT_LOADGAME_200#0" % BOOK] = 0 if hero_save() != "" else 3   # S-2: 0x5563a0, the hero's saved game (or its autosave)
	s["%s/BUTT_DELETE_200#0" % BOOK] = 0 if profile != null else 3     # FE-1: 0x555a70 (PNL_OKAYCANCEL)
	s["%s/BUTT_MOREINFO_200#0" % BOOK] = 0 if profile != null else 3   # FE-1: 0x550790 (PNL_HEROINFO)
	canvas.queue_redraw()

## S-2 (SAVE_LOAD.md open item 1): the selected hero's save file, the one the match saves to (main.gd save_path), else its
## autosave; "" when it has neither.
var save_directory := SaveGame.default_directory()

static func save_of(hero_id: String, directory: String) -> String:
	for path in [SaveGame.path_for(hero_id, directory), SaveGame.path_for(hero_id + "-" + SaveGame.AUTOSAVE_NAME, directory)]:
		if FileAccess.file_exists(path): return path
	return ""

func hero_save() -> String:
	return "" if heroes.is_empty() else save_of(String(heroes[hero_index].id), save_directory)

## 0x553bc0 case 4: Load Game opens the hero's saved game; a refused save stays on the book with its message.
func load_hero_game() -> String:
	var path := hero_save()
	if path == "": return "No saved game."
	var error: String = load("res://battle/main.gd").prepare_saved_game(path, String(store.directory), save_directory)
	if error == "" and not self_test_mode: get_tree().change_scene_to_file("res://battle/main.tscn")
	return error

## A race's name: string section 0xf (races 0..7) or 0x68 (8..15) (0x54b770, 0x554260, 0x4eb4d0).
func race_text(race: int) -> String:
	return string_at(0xf if race < 8 else 0x68, race % 8)

## A class's name: string sections 8, 9, 0xa, 0xb, eight per section (0x54af80).
func class_text(klass: int) -> String:
	return string_at(8 + klass / 8, klass % 8)

func portrait_key(id: int) -> String:
	var key := "X:Portrait%02d.bmp" % id                              # "Portrait%02d.bmp" (0x554260, 0x4d6e00)
	return key if layout.exported_bitmaps.has(key) else "BM_PORTRAIT"

func refresh_create():
	var t := canvas.control_text
	var s := canvas.control_state
	var created := Rules.creation(create_race, create_class)
	t["%s/STR_LARGE750#0" % CREATE] = message if message != "" else string_at(3, 0)   # "Create New Hero"
	for i in 3: t["%s/STR_MEDIUM120#%d" % [CREATE, i]] = string_at(3, 2 + i)           # Name, Race, Class
	t["%s/EDIT_NAME#0" % CREATE] = hero_name + ("_" if int(Time.get_ticks_msec() / 500) % 2 == 0 else "")
	t["%s/BUTT_OPTIONS_DROPLIST#0" % CREATE] = race_text(create_race)                   # 0x54b770: the race's name
	t["%s/BUTT_OPTIONS_DROPLIST#1" % CREATE] = class_text(create_class)                 # ... and the class's
	s["%s/BUTT_CUSTOMIZE#0" % CREATE] = 0                                               # 0x16e -> 0x54e2a0 (PNL 0x1b)
	var stats: Array = created.stats
	for i in 4: t["%s/STR_SMALL120#%d" % [CREATE, i]] = string_at(5, i) % int(stats[i])
	canvas.bitmap_override["BM_PORTRAIT"] = portrait_key(create_portrait)              # Portrait%02d.bmp of +0x58
	s["%s/BUTT_OKAY_STARTUP#0" % CREATE] = 3 if hero_name.strip_edges().is_empty() else 0
	s["%s/BUTT_CANCEL_STARTUP#0" % CREATE] = 3 if temporary else 0             # 0x54b620: no Cancel for a temporary hero
	canvas.queue_redraw()

## 0x54bee0 writes the race's portrait, art and voice (Customize choices go with a race change).
func reset_identity():
	var identity := Rules.race_identity(create_race)
	create_portrait = int(identity.portrait)
	create_art = String(identity.art)
	create_voice = String(identity.voice)
	avatar_frame = 0

# ------------------------------------------------------------------------------------------------ Delete, More Info (FE-1)
## The hero's saved games (the files Load Game reads), which go with the record (0x555550 deletes the hero's own files).
static func save_files_of(hero_id: String, directory: String) -> Array:
	return [SaveGame.path_for(hero_id, directory), SaveGame.path_for(hero_id + "-" + SaveGame.AUTOSAVE_NAME, directory)]

func popup_panel() -> String:
	match popup:
		"delete": return OKAYCANCEL
		"password": return PASSWORD
		"info": return HEROINFO
	return ""

func close_popup():
	var panel := popup_panel()
	popup = ""
	if panel == "": return
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != panel)
	for table in [canvas.control_text, canvas.control_state, canvas.control_align]:
		for key in table.keys():
			if String(key).begins_with(panel + "/"): table.erase(key)
	canvas.queue_redraw()
	overlay.queue_redraw()

func selected_hero_id() -> String:
	return "" if heroes.is_empty() else String(heroes[hero_index].id)

## Delete (0x139 -> 0x555a70): the generic box 0x4361c0 (PNL_OKAYCANCEL, layer 12000): title 6 [0], the text "%s %s" of
## 6 [1] and 6 [2] wrapped in font 5 to 0x17c pixels into four lines (0x44f770), centred (0x436370).
func open_delete() -> bool:
	if heroes.is_empty() or popup != "": return false
	popup = "delete"
	place(OKAYCANCEL, Vector2i.ZERO, 12000)
	var t := canvas.control_text
	t["%s/STR_LARGE400#0" % OKAYCANCEL] = string_at(6, 0)
	canvas.control_align["%s/STR_LARGE400#0" % OKAYCANCEL] = HORIZONTAL_ALIGNMENT_CENTER
	var lines := wrap_text(string_at(6, 1) + " " + string_at(6, 2), 5, 0x17c, 4)
	for i in 4:
		t["%s/STR_MEDIUM500#%d" % [OKAYCANCEL, i]] = String(lines[i]) if i < lines.size() else ""
		canvas.control_align["%s/STR_MEDIUM500#%d" % [OKAYCANCEL, i]] = HORIZONTAL_ALIGNMENT_CENTER
	canvas.queue_redraw()
	return true

func press_popup(panel: String, control: String) -> void:
	if panel != popup_panel(): return
	match popup:
		"delete":
			match control:
				"BUTT_CANCEL_180": close_popup()                                 # 0x4362f0: 0x170 -> callback(0)
				"BUTT_OKAY_180": confirm_delete()                                # 0x16f -> callback(1) = 0x555ad0 -> 0x555ae0
		"password":
			match control:
				"BUTT_CANCEL_180": close_popup()                                 # 0x555d20 msg 2, 0x170: the panel closes
				"BUTT_OKAY_180": check_delete_password()                         # 0x16f
		"info":
			match control:
				"BUTT_OKAY_200": close_popup()                                   # 0x137 -> 0x5507f0
				"PAD_HEROINFOTABS":                                              # 0x174: tab = (x - 99) / 100 (0x5508a7)
					info_tab = clampi((int(last_point.x) - INFO_TAB_X) / 100, 0, 5)
					overlay.queue_redraw()
				"BUTT_FREEZEHERO": toggle_freeze()                                # 0x1ad

## 0x555ae0: the box closes; a hero with a password (+0x41) asks for it first (0x555bc0(1, 0)), else 0x555550 deletes it.
func confirm_delete() -> void:
	close_popup()
	var profile = store.load_profile(selected_hero_id())
	if profile != null and String(profile.data.extensions.get("password", "")) != "":
		open_password()
	else:
		delete_selected()

func open_password() -> void:
	popup = "password"
	popup_password = ""
	place(PASSWORD, Vector2i.ZERO, 5000)                                       # 0x4620d0(0x104, 0x4b0, 1000, 5000)
	canvas.control_text["%s/STR_PARCHLARGE_L400#0" % PASSWORD] = string_at(0x8e, 4)   # "Enter password"
	canvas.control_align["%s/STR_PARCHLARGE_L400#0" % PASSWORD] = HORIZONTAL_ALIGNMENT_CENTER
	refresh_password()

func refresh_password() -> void:
	if popup != "password": return
	canvas.control_text["%s/EDIT_PASSWORD#0" % PASSWORD] = popup_password + "_"
	canvas.queue_redraw()

## 0x555d20 (Enter or Okay): the typed text against the hero's password; equal -> the panel closes and the hero is deleted
## (0x555550); different -> the panel stays. G-3 (HERO_RESEARCH.md "G-3"): 0x5dc0b0 is the C runtime's _stricmp in the C
## locale, so case does not matter ('A'..'Z' only; Emulated, tests/password_compare_fixtures.json); both keys first play
## NewClick (0x60f558, the Okay button's own click), a mismatch then Error.wav (0x60f5d8 = 0x4ca480(0x15, 0x14, 0, 1)).
func check_delete_password() -> bool:
	var profile = store.load_profile(selected_hero_id())
	var stored := "" if profile == null else String(profile.data.extensions.get("password", ""))
	if stricmp(popup_password, stored) != 0:
		audio().ui_sound("sfx/Error")
		return false
	close_popup()
	delete_selected()
	return true

## 0x5dc0b0 (_stricmp, C locale): 'A'..'Z' fold to lower case, bytes compare unsigned; the sign of the difference.
static func stricmp(a: String, b: String) -> int:
	var i := 0
	while true:
		var p: int = a.unicode_at(i) if i < a.length() else 0       # the rebuild's text: one code point per byte (Latin-1)
		var q: int = b.unicode_at(i) if i < b.length() else 0
		if p >= 0x41 and p <= 0x5a: p += 0x20
		if q >= 0x41 and q <= 0x5a: q += 0x20
		if p != q: return -1 if p < q else 1
		if p == 0: return 0
		i += 1
	return 0

## 0x555550: the record leaves the hero book; the book starts again at the first hero (0x554140) or, when none is left, at
## hero creation (0x554120 -> 0x54b040(0, -1)).
func delete_selected() -> bool:
	var id := selected_hero_id()
	if id == "": return false
	if not store.delete_profile(id, save_files_of(id, save_directory)):
		message = store.last_error
		return false
	heroes = []
	for row in store.list_profiles():
		if not row.has("error"): heroes.append({"id": row.id, "name": row.name})
	hero_index = 0
	if heroes.is_empty():
		open_create()
	else:
		refresh_book()
	return true

## More Info (0x139's neighbour 0x13a -> 0x550790): PNL_HEROINFO at layer 14000 over the book, opening on the Stats page.
var info_profile = null

func open_info() -> bool:
	if heroes.is_empty() or popup != "": return false
	info_profile = store.load_profile(selected_hero_id())
	if info_profile == null: return false
	popup = "info"
	info_tab = 0
	place(HEROINFO, Vector2i.ZERO, 14000)
	refresh_info()
	return true

## 0x5509c0(1): the name (0x2eec), labels 6 [3..7] right-aligned (0x464c60 mode 2) and the values: race, class, level
## ("%d"), XP ("%ld") and the next level's threshold (0x409ef0(level + 1)); the check box 0x1ad shows +0x10e6.
func refresh_info() -> void:
	var data: Dictionary = info_profile.data
	var t := canvas.control_text
	t["%s/STR_LARGE400#0" % HEROINFO] = String(data.name)
	var values := [race_text(int(data.race_id)), class_text(int(data.class_id)), "%d" % int(data.level), "%d" % int(data.xp),
		"%d" % Rules.xp_threshold(int(data.level) + 1)]
	for i in 5:
		t["%s/STR_MEDIUM120#%d" % [HEROINFO, i]] = string_at(6, 3 + i)
		canvas.control_align["%s/STR_MEDIUM120#%d" % [HEROINFO, i]] = HORIZONTAL_ALIGNMENT_RIGHT
		t["%s/STR_MEDIUM200#%d" % [HEROINFO, i]] = String(values[i])
	canvas.bitmap_override["BM_PORTRAIT"] = portrait_key(int(data.portrait_id))
	canvas.control_state["%s/BUTT_FREEZEHERO#0" % HEROINFO] = 2 if info_profile.frozen() else 0
	canvas.queue_redraw()
	overlay.queue_redraw()

## 0x550810 message 0x10 on 0x1ad: the check box's state goes to the record (+0x10e6) and the hero is written (0x44fef0).
func toggle_freeze() -> void:
	info_profile.data.extensions["frozen"] = not info_profile.frozen()
	if not store.save_profile(info_profile): message = store.last_error
	refresh_info()

## The effect line pairs of the Stats page (0x54ace0 -> 0x54a8d0, texts [0679]..[0695], effects 0x54a720 mode 0).
## Strength: combat, damage / life, regeneration; Dexterity: move speed (with the attack time 1.0 - 0.01 x kind 16),
## resistance / armor, conversion; Intelligence: mana, regeneration / spellcasting, initial troop XP; Charisma: morale,
## merchant skill / command radius, retinue slots (Read: the pairing follows the string slots param_3..param_6 of 0x54a8d0).
func stat_effects(stats: Array, which: int) -> Array:
	match which:
		0: return [game_text(679) % Rules.derived(stats, 0, 0), game_text(680) % Rules.derived(stats, 1, 0),
			game_text(681) % Rules.derived(stats, 2, 0), game_text(682) % Rules.derived(stats, 3, 0)]
		1: return [game_text(683) % [Rules.derived(stats, 4, 0), 1.0 - float(Rules.derived(stats, 16, 0)) * 0.01],
			game_text(684) % Rules.derived(stats, 5, 0), game_text(685) % Rules.derived(stats, 6, 0), game_text(686) % Rules.derived(stats, 7, 0)]
		2: return [game_text(687) % Rules.derived(stats, 8, 0), game_text(688) % Rules.derived(stats, 9, 0),
			game_text(689) % Rules.derived(stats, 11, 0), game_text(690) % Rules.derived(stats, 10, 0)]
	var skill: int = Rules.derived(stats, 13, 1)                      # merchant skill: -5 + Charisma
	var percent := 0.0 if skill == 0 else 100.0 - 100.0 / float(skill + 100) * 100.0
	var merchant := game_text(693) % [-skill, -percent] if skill < 0 else game_text(692) % [skill, percent]
	return [game_text(691) % Rules.derived(stats, 12, 0), merchant, game_text(694) % Rules.derived(stats, 15, 1),
		game_text(695) % Rules.derived(stats, 14, 1)]

## 0x550d10: the tab names 0x12 [0..5] (font 5, centred on x 0x95 + 100 i at y 0xf3), a line under the open tab, and the
## page at (99, 0x106). Stats, Combat, Skills, Titles, Retinue and Items follow 0x550e10, 0x551410 (G-3), 0x551b20,
## 0x551cf0, 0x552000 and 0x5521b0.
## G-3 (HERO_RESEARCH.md "G-3"): 0x46e350 / 0x46e3b0 / 0x46e380 draw left / centred / right of x (0x46d440 mode 0 / 1 / 2).
func info_text(node: Node2D, text: String, font_number: int, x: float, y: float, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	match align:
		HORIZONTAL_ALIGNMENT_CENTER: overlay_text(node, text, font_number, Vector2(x - 200, y), null, 400.0, align)
		HORIZONTAL_ALIGNMENT_RIGHT: overlay_text(node, text, font_number, Vector2(x - 400, y), null, 400.0, align)
		_: overlay_text(node, text, font_number, Vector2(x, y))

const TITLE_PICTURE_X := [648, 648, 648, 648, 648, 648, 698, 698, 698, 698, 698]   # 0x614be4 by title rank
const TITLE_PICTURE_Y := [573, 589, 605, 621, 637, 653, 573, 589, 605, 621, 367]   # 0x614bfc
const ITEM_ROW_SLOTS := [0, 1, 6, 2, 3, 4, 5, 7, 8, 9, 10]                        # 0x614c14: Items page row -> record slot
var _title_sheet: Texture2D = null

## 0x469860(0x66 = BM_SELECTIONRINGS, sx, sy, 50, 16, 0, x, y): the title rank's picture (SelectionRings.bmp).
func draw_title_picture(node: Node2D, rank: int, at: Vector2) -> void:
	if _title_sheet == null:
		var extra: Dictionary = layout.get("extra_bitmaps", {})
		if extra.has("SelectionRings.bmp"): _title_sheet = Assets.texture(String(extra["SelectionRings.bmp"].file))
	if _title_sheet == null: return
	node.draw_texture_rect_region(_title_sheet, Rect2(at, Vector2(50, 16)), Rect2(TITLE_PICTURE_X[rank], TITLE_PICTURE_Y[rank], 50, 16))

## 0x551410: the Combat page (Read). Labels 0x133 / 0x134, values from HeroEffects.sheet_combat (0x556ab0 resolver).
func draw_combat_page(node: Node2D, data: Dictionary, x: float, y: float) -> void:
	var s: Dictionary = Effects.sheet_combat(Effects.block_from_profile(data))
	var left := [["combat", 0, 0x14], ["speed", 1, 0x3c], ["life", 2, 100], ["damage", 3, 0x8c]]
	for row in left:
		info_text(node, string_at(0x133, row[1]), 5, x + 10, y + row[2])
		info_text(node, "%d" % int(s[row[0]]), 5, x + 0x6e, y + row[2])
	info_text(node, string_at(0x133, 4), 5, x + 0xdc, y + 0x14)
	info_text(node, "%d" % int(s.armor), 5, x + 0x140, y + 0x14)
	info_text(node, string_at(0x133, 5), 5, x + 0x1ae, y + 0x14)
	info_text(node, "%d" % int(s.resistance), 5, x + 0x212, y + 0x14)
	for k in 3:
		info_text(node, string_at(0x134, k), 0x14, x + 0xe6, y + 0x32 + 0x14 * k)
		info_text(node, "%d" % int(s.vs_armor[k]), 0x14, x + 0x14a, y + 0x32 + 0x14 * k)
		info_text(node, string_at(0x134, 3 + k), 0x14, x + 0x1b8, y + 0x32 + 0x14 * k)
		info_text(node, "%d" % int(s.vs_resistance[k]), 0x14, x + 0x21c, y + 0x32 + 0x14 * k)
	info_text(node, string_at(0x133, 6), 5, x + 0x104, y + 0x87)
	info_text(node, "%d" % int(s.magic_resistance), 5, x + 0x1a4, y + 0x87)
	info_text(node, merchant_line(int(s.merchant)), 0x14, x + 300, y + 0xa5, HORIZONTAL_ALIGNMENT_CENTER)

var _unit_rules = null

## The Retinue page's type column (0x58a230: the unit type table's name); the rebuild's unit definition name.
func unit_type_name(type_id: String) -> String:
	if _unit_rules == null: _unit_rules = preload("res://simulation/production_rules.gd").new()
	return String(_unit_rules.display_name(type_id))

## Game.txt [0861] / [0862] with the skill and 100 - 100 / (skill + 100) x 100 (0 for 0), as 0x551410 and 0x54a8d0 write it.
func merchant_line(skill: int) -> String:
	var percent := 0.0 if skill == 0 else 100.0 - 100.0 / float(skill + 100) * 100.0
	return game_text(861) % [-skill, -percent] if skill < 0 else game_text(862) % [skill, percent]

func draw_info(node: Node2D) -> void:
	if info_profile == null: return
	var data: Dictionary = info_profile.data
	for i in 6:
		overlay_text(node, string_at(0x12, i), 5, Vector2(INFO_TAB_X + 100 * i, 0xf3), null, 100.0, HORIZONTAL_ALIGNMENT_CENTER)
	var line_x := 0x65 + 100 * info_tab
	node.draw_line(Vector2(line_x, 0x105), Vector2(line_x + 0x61, 0x105), Color(0.9, 0.8, 0.55), 1.0)
	var x := INFO_PAGE.x
	var y := INFO_PAGE.y
	match info_tab:
		0:
			for i in 4:
				var top := y + 0x14 + 40 * i
				overlay_text(node, string_at(0x82, i), 5, Vector2(x + 10, top))
				overlay_text(node, "%d" % int(data.stats[i]), 5, Vector2(x + 0x73, top))
				var effects := stat_effects(data.stats, i)
				overlay_text(node, effects[0] + INFO_SEPARATOR + effects[1], 0x14, Vector2(x + 0xa0, top - 8))
				overlay_text(node, effects[2] + INFO_SEPARATOR + effects[3], 0x14, Vector2(x + 0xa0, top + 8))
		1:
			draw_combat_page(node, data, x, y)
		2:
			var top := 10
			for k in mini(8, data.skills.size()):
				var skill: Dictionary = data.skills[k]
				if int(data.level) < int(skill.unlock_level):                    # 0x551b20: "Available at level %d" (0x133 [7])
					top = 15
					overlay_text(node, Effects.skill_name(int(skill.id)), 7, Vector2(x + 10, y + top + 15 * k))
					overlay_text(node, string_at(0x133, 7) % int(skill.unlock_level), 0x14, Vector2(x + 200, y + top + 15 * k))
				else:
					overlay_text(node, Effects.skill_name(int(skill.id)), 5, Vector2(x + 10, y + top + 15 * k))
					overlay_text(node, "%d" % int(skill.rank), 5, Vector2(x + 0x96, y + top + 15 * k))
		3:
			var counters: Array = ["battles_fought", "battles_won", "heroes_killed", "enemies_killed", "dragons_killed", "titans_killed",
				"quests_completed", "spells_cast"]
			var total := 0
			for k in 8:                                                          # 0x551cf0: label, count (x + 200), 0x11 per row
				var value := int(data.history.get(counters[k], 0))
				var rank: int = Rules.title_rank(k, value)                          # 0x551fc0 (table 0x614a84)
				total += rank
				overlay_text(node, string_at(0x135, k), 5, Vector2(x + 10, y + 10 + 17 * k))
				overlay_text(node, "%d" % value, 5, Vector2(x + 200, y + 10 + 17 * k))
				# G-3: the title's name, Game.txt [0935 + rank + 10 k] ("-" for rank 0), and its picture.
				info_text(node, game_text(935 + rank + 10 * k) if rank >= 1 else "-", 0x14, x + 0x15e, y + 10 + 17 * k - 2)
				draw_title_picture(node, rank, Vector2(x + 0x127, y + 10 + 17 * k))
			# G-3: the total row at fixed x: 0x134 [6] "Overall Ranking" right of 0x15e, the sum of the ranks at 400, its name
			# Game.txt [1016 + sum] at 0x1c2.
			info_text(node, string_at(0x134, 6), 5, 0x15e, y + 0xa3, HORIZONTAL_ALIGNMENT_RIGHT)
			info_text(node, "%d" % total, 5, 400, y + 0xa3)
			info_text(node, game_text(0x3f8 + total), 0x14, 0x1c2, y + 0xa1)
		4:
			for k in 8:                                                          # 0x552000: name, "Level %d", battles
				var top := y + 10 + 17 * k
				if k >= data.retinue.size():
					# G-3: an unused slot shows 0x136 [0] "Empty", or [1] "N/A" past the Charisma capacity (0x40b130 = derived 14).
					overlay_text(node, string_at(0x136, 1 if Rules.retinue_capacity(int(data.stats[3])) <= k else 0), 5, Vector2(x + 10, top))
					continue
				var unit: Dictionary = data.retinue[k]
				var type_name := unit_type_name(String(unit.original_type_id))
				overlay_text(node, String(unit.get("name", "")) if String(unit.get("name", "")) != "" else type_name, 5, Vector2(x + 10, top))
				overlay_text(node, type_name, 5, Vector2(x + 0x96, top))         # G-3: the type's name (0x58a230(+0x39c))
				overlay_text(node, string_at(0x118, 0) % (int(unit.get("medal_level", 0)) + 1), 0x14, Vector2(x + 300, top))
				var battles := int(unit.get("battles", 0))
				overlay_text(node, string_at(0x118, 3) % 1 if battles == 1 else string_at(0x118, 1) % battles, 0x14, Vector2(x + 400, top))
		5:
			for i in 11:                                                         # 0x5521b0: equipment left, backpack right
				# G-3: row i shows record slot 0x614c14[i] (Feet, slot 6, is the third row); labels 0x137 [0..7] right of the
				# column (the backpack's only on its first row); an empty slot "-" and a plain item in font 0x14 at +8, a set
				# item (+0x27a, set index + 1) in font 0x2a at +12.
				var slot: int = ITEM_ROW_SLOTS[i]
				var item: Dictionary = data.equipment[slot] if slot < 7 else data.backpack[slot - 7]
				var row := i if i < 7 else i - 7
				var column := x + 100 if i < 7 else x + 400
				if i < 8: info_text(node, string_at(0x137, mini(i, 7)), 5, column, y + 10 + 17 * row, HORIZONTAL_ALIGNMENT_RIGHT)
				var id := int(item.get("item", 0))
				var in_set := id > 0 and int(Effects.item(id).get("set", 0)) >= 1
				overlay_text(node, Effects.item_name(id) if id > 0 else "-", 0x2a if in_set else 0x14, Vector2(column + 10, y + (12 if in_set else 8) + 17 * row))

# ------------------------------------------------------------------------------------------------ Customize (0x54e2a0)
func open_customize():
	screen = CUSTOMIZE
	drop_row = -1
	close_list()
	# The panel's IM_SCREEN_BLACK (an overlay image, which ui_canvas.gd does not draw) hides the creation screen: the
	# rebuild takes the creation panel away while Customize is open.
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != CREATE)
	place(CUSTOMIZE, Vector2i.ZERO, 10000)                         # 0x4620d0(0x1b, 0, 0, 10000)
	avatar_frame = 0
	avatar_ms = Time.get_ticks_msec()
	refresh_customize()
	open_screen_help(3, false)                                     # 0x54e2a0 -> 0x448870(3, 0)

## 0x54e300 (Okay and Cancel alike): the panel goes, the creation screen shows the record as it now is.
func close_customize():
	canvas.placements = canvas.placements.filter(func(p): return String(p.panel.get("name", "")) != CUSTOMIZE)
	for key in canvas.control_text.keys():
		if String(key).begins_with(CUSTOMIZE + "/"): canvas.control_text.erase(key)
	drop_row = -1
	close_list()
	place(CREATE, Vector2i.ZERO, 4000)
	screen = CREATE
	refresh_create()

## Names.cfg [VOICE_NAMEnnn] of a voice code (0x58a410 of its index in the 20 codes of 0x612598).
const VOICE_CODES := ["AHHX", "ADHX", "AUHX", "AMHX", "ABHX", "AOHX", "AEHX", "AWHX", "AKHX", "AFHX", "AAHX", "AVHX",
	"AXH0", "AXH1", "AXH2", "AXH3", "AXH4", "AXH5", "AXH6", "AXH7"]
const VOICE_NAMES := ["Noble Male", "Angry Dwarf", "Evil Warrior", "Barbaric Male", "Violent Male", "Crazed Male",
	"Cold Female", "Efficient Female", "Violent Female", "Flamboyant Male", "Clever Dwarf", "Daemonic Male", "Stern Male",
	"Arrogant Dwarf", "Serious Female", "Knightly Male", "Evil Female", "Corrupt Male", "Female Warrior", "Brutal Male"]

static func voice_label(code: String) -> String:
	var i := VOICE_CODES.find(code)
	return VOICE_NAMES[i] if i >= 0 else code

func refresh_customize():
	var t := canvas.control_text
	var s := canvas.control_state
	t["%s/STR_LARGE400#0" % CUSTOMIZE] = string_at(7, 0)                           # Customize Your Hero
	for i in 5: t["%s/STR_MEDIUM220#%d" % [CUSTOMIZE, i]] = string_at(7, 1 + i)     # Portrait .. Mode
	var ironman := create_mode == MODE_IRONMAN
	var lines := wrap_text(string_at(0xeb, 6 if ironman else 0) + " " + string_at(0xeb, 7 if ironman else 1), 5, 200, 5)  # "%s %s" of 0xeb [0, 1] / [6, 7]
	for i in 5: t["%s/STR_SMALL200#%d" % [CUSTOMIZE, i]] = String(lines[i]) if i < lines.size() else ""
	t["%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE] = string_at(0xea, 3 if ironman else 0)   # Ironman Mode / Normal Mode by +0x54
	t["%s/BUTT_OPTIONS_DROPLIST#0" % CUSTOMIZE] = voice_label(create_voice)
	t["%s/EDIT_PASSWORD#0" % CUSTOMIZE] = create_password + ("_" if int(Time.get_ticks_msec() / 500) % 2 == 0 else "")
	s["%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE] = 3 if temporary else 0              # 0x54e790: locked for a temporary hero (+4)
	canvas.bitmap_override["BM_PORTRAIT"] = portrait_key(create_portrait)
	canvas.queue_redraw()

## 0x54ec90 (portraits, 0x612178) / 0x54ed30 (art, 0x6140f8): the next or previous entry of the race's list; a value not
## in the list goes to its first entry.
static func step_choice(list: Array, current, step: int):
	if list.is_empty(): return current
	var i := list.find(current)
	if i < 0: return list[0]
	return list[posmod(i + step, list.size())]

func step_portrait(step: int):
	var list: Array = Rules.race_choices(create_race).portraits.map(func(v): return int(v))
	create_portrait = int(step_choice(list, create_portrait, step))
	refresh_customize()

func step_avatar(step: int):
	var before := create_art
	create_art = String(step_choice(Rules.race_choices(create_race).art, create_art, step))
	if create_art != before: avatar_frame = 0                      # 0x54ef80: a new sprite starts at frame 0
	refresh_customize()

## 0x54e4b0: the voice list is the race's English list (0x612ff0), labelled by 0x58a410; 0x54ee50 takes the choice.
func open_voice_drop():
	drop_row = 0
	var list: Array = Rules.race_choices(create_race).voices_english
	open_list(list.map(func(c): return voice_label(String(c))), list_point("%s/BUTT_OPTIONS_DROPLIST#0" % CUSTOMIZE),
		func(i): choose_voice(i), list.find(create_voice))

## The mode list (0x148 #1): Normal Mode / Ironman Mode (0xea [0], [3]); 0x54ee10 writes the choice to +0x54 (FE-1).
func open_mode_drop():
	drop_row = 1
	open_list([string_at(0xea, 0), string_at(0xea, 3)], list_point("%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE),
		func(i): choose_mode(i), create_mode)

func choose_mode(choice: int):
	drop_row = -1
	close_list()
	if choice < 0 or choice > 1 or temporary: return
	create_mode = choice
	refresh_customize()

func choose_voice(choice: int):
	var list: Array = Rules.race_choices(create_race).voices_english
	drop_row = -1
	close_list()
	if choice < 0 or choice >= list.size(): return
	create_voice = String(list[choice])
	var a = audio()
	if a != null and a.has_method("voice_name"):
		var sample: String = a.voice_name(create_voice, "DeathBlow")                # 0x61259c: "<code>DeathBlow.wav"
		if sample != "": a.play(sample, 150, 127)
	refresh_customize()

## The avatar (0x54efa0): the art's ANI slot 1 sheet, facing 3, frame avatar_frame, its pivot at (500, 0xb4).
func draw_avatar(node: Node2D):
	var sheet: Dictionary = preload("res://core/art_data.gd").unit_sheet(create_art, 1)
	if sheet.is_empty(): return
	var tex: Texture2D = preload("res://core/art_data.gd").texture(String(sheet.texture))
	if tex == null: return
	var frame := avatar_frame % maxi(1, int(sheet.frame_count))
	var source: Rect2 = preload("res://core/art_data.gd").frame_rect(sheet, AVATAR_FACING, frame)
	node.draw_texture_rect_region(tex, Rect2(AVATAR_AT + preload("res://core/art_data.gd").offset(sheet), source.size), source)

func drop_labels() -> Array:
	if drop_row < 0: return []
	if is_list_open(): return list_labels
	if screen == CREATE:
		if drop_row == 0: return Rules.race_droplist().map(func(r): return race_text(int(r)))
		return Rules.class_droplist().map(func(c): return class_text(int(c)))
	return []

# ------------------------------------------------------------------------------------------------ buttons
func press(key: String) -> void:
	var panel := key.get_slice("/", 0)
	var control := key.get_slice("/", 1).get_slice("#", 0)
	var instance := int(key.get_slice("#", 1))
	if tip_open:
		if panel != TIP: return
		match control:
			"BUTT_DONE_180": close_tip()                                     # 0x4540b0 msg 2
			"BUTT_TIPOFTHEDAY":                                             # msg 0x10: store the box and save (0x451b10)
				settings.set_value("TipOfTheDay", 0 if int(settings.get_value("TipOfTheDay")) != 0 else 1)
				settings.save()
				refresh_tip_check()
		return
	if popup != "":
		press_popup(panel, control)
		return
	match screen:
		MAIN:
			match control:
				"BUTT_MM_SINGLEPLAYER": open_hero_book()                       # 0x41da80(1): game mode 0, hero book
				"BUTT_MM_OPTIONS": open_options()                              # 0x41da80(6) -> 0x411110
				"BUTT_MM_QUIT":                                                 # 0x41da80(3) -> 0x45c0c0
					if not self_test_mode: get_tree().quit()
		BOOK:
			match control:
				"BUTT_OKAY_STARTUP": choose_hero()
				"BUTT_CANCEL_STARTUP": open_main()                              # 0x553bc0 case 5
				"BUTT_NEWHERO_200": open_create()                                # case 1 -> 0x54b040
				"BUTT_LOADGAME_200": load_hero_game()                            # case 4
				"BUTT_DELETE_200": open_delete()                                 # 0x139 -> 0x555a70
				"BUTT_MOREINFO_200": open_info()                                 # 0x13a -> 0x550790
				"BUTT_PREVIOUS":                                                 # case 2
					hero_index = (hero_index - 1 + heroes.size()) % heroes.size()
					refresh_book()
				"BUTT_NEXT":                                                     # case 3
					hero_index = (hero_index + 1) % heroes.size()
					refresh_book()
		CUSTOMIZE:
			match control:
				"BUTT_LEFT_20":                                                 # 0x3a: 0x54ec90(-1) / 0x54ed30(-1)
					if instance == 0: step_portrait(-1)
					else: step_avatar(-1)
				"BUTT_RIGHT_20":                                                # 0x3b: (+1)
					if instance == 0: step_portrait(1)
					else: step_avatar(1)
				"BUTT_OPTIONS_DROPLIST":
					if instance == 0: open_voice_drop()
					else: open_mode_drop()
				"BUTT_OKAY_200", "BUTT_CANCEL_200": close_customize()           # 0x137 / 0x136 -> 0x54e300
		CREATE:
			match control:
				"BUTT_CUSTOMIZE": open_customize()                              # 0x16e -> 0x54e2a0
				"BUTT_OPTIONS_DROPLIST": open_create_drop(instance)
				"BUTT_OKAY_STARTUP": create_hero()
				"BUTT_CANCEL_STARTUP":
					if temporary: return
					if store.list_profiles().filter(func(r): return not r.has("error")).is_empty(): open_main()
					else: open_hero_book()

## PNL_CREATEHERO's race (instance 0) or class (instance 1) droplist (0x54b3ea: the 0x148 button opens the list).
func open_create_drop(instance: int):
	drop_row = instance
	var list: Array = Rules.race_droplist() if instance == 0 else Rules.class_droplist()
	var labels: Array = list.map(func(r): return race_text(int(r))) if instance == 0 else list.map(func(c): return class_text(int(c)))
	open_list(labels, list_point("%s/BUTT_OPTIONS_DROPLIST#%d" % [CREATE, instance]), func(i): choose_create(instance, i),
		list.find(create_race if instance == 0 else create_class))

## The list index under `point` inside the open list, or -1 (0x45cfe0: one column of 20-pixel rows).
func drop_index(point: Vector2) -> int:
	return list_index(point)

## A droplist choice on the creation screen (the list's callback): 0x54bb50 -> 0x54bee0(race) or 0x54bb90 -> 0x54bfe0(class), then the
## screen refresh 0x54b770(0).
func choose_create(instance: int, choice: int):
	if instance == 0:
		create_race = int(Rules.race_droplist()[choice])
		reset_identity()                                            # 0x54bee0: the race's portrait, art and voice
	else: create_class = int(Rules.class_droplist()[choice])
	drop_row = -1
	close_list()
	refresh_create()

## 0x553dd0: the selected hero becomes the player's hero, then the skirmish setup (0x4e47e0).
func choose_hero() -> bool:
	if heroes.is_empty() or not store.select_profile(heroes[hero_index].id):
		return false
	if not self_test_mode: get_tree().change_scene_to_file("res://menus/skirmish_menu.tscn")
	return true

func create_hero() -> bool:
	var name := hero_name.strip_edges()
	if name.is_empty(): return false
	for row in store.list_profiles():
		if not row.has("error") and String(row.name).to_lower() == name.to_lower():
			message = string_at(3, 5)                                   # "Hero Already Exists!" (PNL_HCRE_INVALIDHERO texts)
			refresh_create()
			return false
	var id := TEMP_ID if temporary else Crypto.new().generate_random_bytes(16).hex_encode()
	var profile = Profile.create(id, name, create_race, create_class)
	profile.data.portrait_id = create_portrait                      # Customize's choices (0x54e2a0) on the record
	profile.data.original_type_id = create_art
	profile.data.voice_id = create_voice
	if create_password != "": profile.data.extensions["password"] = create_password   # +0x41 (asked by the hero book's Delete)
	if create_mode == MODE_IRONMAN and not temporary: profile.data.mode = Profile.MODE_IRONMAN   # +0x54 = 1
	if temporary: return start_temporary_hero(profile)
	if not store.save_profile(profile):
		message = store.last_error
		refresh_create()
		return false
	store.select_profile(id)
	open_hero_book()
	return true

## 0x54bbd0 for a temporary hero: level and XP of the setup's level, `level` stat and skill points, then the stats
## screen (hero_advance.gd in its temporary mode) and from its skills screen the match.
func start_temporary_hero(profile) -> bool:
	var level := int(temp_request.get("level", 10))
	profile.data.level = level
	profile.data.xp = Rules.xp_threshold(level)                      # 0x709d04 = 0x409ef0(level)
	profile.data.stat_points = level                                 # 0x552d90(1, level): b997e4 = level
	profile.data.skill_points = level                                # 0x5522e0(1, level)
	profile.data.extensions["temporary"] = true                      # +4
	var scratch := Store.new(temp_dir)
	for row in scratch.list_profiles():
		if String(row.get("id", "")) != "": DirAccess.remove_absolute(temp_dir.path_join(String(row.id) + ".json"))
	if not scratch.save_profile(profile):
		message = scratch.last_error
		refresh_create()
		return false
	var setup: Dictionary = temp_request.get("setup", {})
	preload("res://simulation/skirmish_setup.gd").pending = {"setup": setup, "hero_id": TEMP_ID, "store_dir": temp_dir}
	preload("res://menus/hero_advance.gd").pending = {"hero_id": TEMP_ID, "store_dir": temp_dir, "next": "res://menus/loading_screen.tscn",
		"temporary": true}
	temp_request = {}
	temporary = false
	if not self_test_mode: get_tree().change_scene_to_file("res://menus/hero_advance.tscn")
	return true

# ------------------------------------------------------------------------------------------------ input
func _unhandled_input(event: InputEvent):
	if options != null: return                                    # the options screen is modal
	if popup == "password" and help_screen < 0 and event is InputEventKey and event.pressed:
		if event.keycode == KEY_BACKSPACE:                          # the password edit (0xbcb) has the keyboard focus
			popup_password = popup_password.left(maxi(0, popup_password.length() - 1))
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:   # 0x555d20: message 0xf with key 0xd
			audio().click()                                             # G-3: NewClick (0x60f558) before the compare
			check_delete_password()
			return
		elif event.unicode >= 32 and popup_password.length() < PASSWORD_LENGTH:
			popup_password += char(event.unicode)
		refresh_password()
		return
	if screen == CUSTOMIZE and help_screen < 0 and not is_list_open() and event is InputEventKey and event.pressed:
		if original_code(event) == KEY_F1:                          # 0x54e320 msg 5 / 0xf: F1 -> 0x448870(3, 1)
			handle_key(KEY_F1)
			return
		if event.keycode == KEY_BACKSPACE:                           # the password edit (0xbcb) has the keyboard focus
			create_password = create_password.left(maxi(0, create_password.length() - 1))
		elif event.unicode >= 32 and create_password.length() < PASSWORD_LENGTH:
			create_password += char(event.unicode)
		refresh_customize()
		return
	if screen == CREATE and help_screen < 0 and not is_list_open() and event is InputEventKey and event.pressed:
		if original_code(event) == KEY_F1:                          # 0x54b200 msg 0xf: F1 -> 0x448870(2, 1)
			handle_key(KEY_F1)
			return
		if event.keycode == KEY_BACKSPACE:                           # the name edit control has the keyboard focus
			hero_name = hero_name.left(maxi(0, hero_name.length() - 1))
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			create_hero()
			return
		elif event.unicode >= 32 and hero_name.length() < MAX_NAME:
			hero_name += char(event.unicode)
		message = ""
		refresh_create()
		return
	var was_open := is_list_open()
	screen_input(event)
	if was_open and not is_list_open(): drop_row = -1

func help_id() -> int:
	match screen:
		MAIN: return 0
		BOOK: return 1
		CREATE: return 2
		CUSTOMIZE: return 3
	return -1

## Main-menu callback message 5 (0x41d9d0): Space floats "Test" at (400, 300) (F1 is handled by handle_key).
func key_code(code: int) -> bool:
	if popup == "info" and code == 0x1b:                              # 0x550790's callback, message 5 key 0x1b: close
		close_popup()
		return true
	if screen == MAIN and code == 0x20 and not tip_open:
		add_float("Test", 300)
		return true
	return false

## The tip of the day is modal: only its own buttons answer while it is open (0x4633a0 after the panel opens).
func hit(point: Vector2) -> Dictionary:
	var modal := TIP if tip_open else popup_panel()      # FE-1: the hero book's dialogs are modal too
	if modal == "": return super.hit(point)
	var list := canvas.items()
	for i in range(list.size() - 1, -1, -1):
		var entry: Dictionary = list[i]
		if entry.panel != modal or not canvas.interactive(entry): continue
		if Rect2(entry.rect).has_point(point) and canvas.state_of(entry) != 3: return entry
	return {}

func hovered_changed(entry: Dictionary) -> void:
	if screen == MAIN:
		var control_name := String(entry.get("control", {}).get("name", ""))
		if FLOAT_BUTTONS.has(control_name) and not tip_open:         # 0x41d730 msg 0x12 -> 0x405360
			add_float(string_at(0, int(FLOAT_BUTTONS[control_name][0])), int(FLOAT_BUTTONS[control_name][1]))
		return

func now_ms() -> int:
	return clock_ms if clock_ms >= 0 else Time.get_ticks_msec()

## 0x405360 (mode 2): a new slot for each call while one of the 12 is free.
func add_float(text: String, y: int):
	if floats.size() >= FLOAT_SLOTS: return
	floats.append({"text": text, "y": y, "start_ms": now_ms()})
	float_layer.queue_redraw()

## 0x405500: spacing = 20 x elapsed / 1500, blend level = 9 + elapsed x 6 / 1500 (0..15); the slot ends after 1500 ms.
static func float_state(elapsed: int) -> Dictionary:
	return {"spacing": FLOAT_SPACING * elapsed / FLOAT_MS, "level": clampi(elapsed * 6 / FLOAT_MS + 9, 0, 15), "done": elapsed >= FLOAT_MS}

func update_floats():
	var now := now_ms()
	floats = floats.filter(func(f): return not float_state(now - int(f.start_ms)).done)
	float_layer.queue_redraw()

func draw_overlay(node: Node2D):
	if screen == CUSTOMIZE: draw_avatar(node)
	if popup == "info": draw_info(node)
	super.draw_overlay(node)

## 0x405580 per slot: the text in font 0x1a with the slot's extra spacing (0x58f600) and blend level (0x58f5b0). The level
## rides in the colour's alpha (level / 15) for menu_float.gdshader, which applies the blitter's rule per pixel
## (Read, 0x592b70; replaces the earlier uniform opacity 1 - level / 16, which stacked into a heavy smear on repeated hovers).
func draw_floats(node: Node2D):
	# The floats are drawn by the main menu's own draw case (0x458614 -> 0x405330), so no other screen shows them.
	if screen != MAIN: return
	var info: Dictionary = canvas.font(FLOAT_FONT)
	if not info.is_empty() and info.font != null:
		var now := now_ms()
		for f in floats:
			var state := float_state(now - int(f.start_ms))
			if state.done: continue
			var text: String = f.text
			var widths: Array = []
			var total := 0.0
			for ch in text:
				var w: float = info.font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x
				widths.append(w)
				total += w
			total += state.spacing * maxi(0, text.length() - 1)
			var x := 400.0 - total / 2.0
			var colour: Color = info.colour
			colour.a = float(state.level) / 15.0                             # the level for the shader, not an opacity
			for i in text.length():
				node.draw_string(info.font, Vector2(x, int(f.y) + int(info.baseline)), text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, info.size, colour)
				x += float(widths[i]) + state.spacing

func _process(_delta: float):
	if screen == CREATE: refresh_create()        # the edit caret blinks
	if screen == CUSTOMIZE:
		var now := Time.get_ticks_msec()
		if now - avatar_ms >= AVATAR_TICK_MS:      # 0x54f180 on the timer message
			avatar_ms = now
			avatar_frame += 1
			var sheet: Dictionary = preload("res://core/art_data.gd").unit_sheet(create_art, 1)
			if avatar_frame >= int(sheet.get("frame_count", 1)): avatar_frame = 0
			overlay.queue_redraw()
		refresh_customize()
	if not floats.is_empty():
		if screen != MAIN: floats.clear()     # left the main menu without reset_canvas (e.g. a dialog screen)
		update_floats()

# ------------------------------------------------------------------------------------------------ self-test
var checks := 0
var failed := false

func check(condition: bool, text: String):
	checks += 1
	if not condition and not failed:
		failed = true
		push_error("Front end check failed: " + text)

func clean_dir(path: String):
	if not DirAccess.dir_exists_absolute(path): return
	for filename in DirAccess.get_files_at(path): DirAccess.remove_absolute(path.path_join(filename))
	DirAccess.remove_absolute(path)

## UI gaps: Customize (0x54e2a0, PNL 0x1b) on the Knight creation screen.
func customize_checks():
	check(click("%s/BUTT_CUSTOMIZE#0" % CREATE) and screen == CUSTOMIZE, "Customize opens PNL_CUSTOMIZEHERO (0x16e -> 0x54e2a0)")
	close_screen_help()
	var t := canvas.control_text
	check(t["%s/STR_LARGE400#0" % CUSTOMIZE] == "Customize Your Hero" and t["%s/STR_MEDIUM220#0" % CUSTOMIZE] == "Portrait" and t["%s/STR_MEDIUM220#4" % CUSTOMIZE] == "Mode", "Customize texts (section 7)")
	check(t["%s/BUTT_OPTIONS_DROPLIST#0" % CUSTOMIZE] == "Noble Male" and t["%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE] == "Normal Mode", "voice label (Names.cfg VOICE_NAME000) and mode label (0xea [0])")
	check(String(t["%s/STR_SMALL200#0" % CUSTOMIZE]).begins_with("You gain normal XP"), "the mode's lines (section 0xeb, wrapped)")
	# FE-1: the mode list (0x54ee10) is enabled; the choice writes +0x54 and re-labels the panel (0xea [0] / [3], 0xeb).
	check(enabled("%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE) and create_mode == MODE_NORMAL, "the mode list is enabled (FE-1), on Normal Mode")
	check(click("%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE) and drop_row == 1 and drop_labels() == ["Normal Mode", "Ironman Mode"], "the mode list: Normal Mode, Ironman Mode")
	choose_mode(1)
	check(create_mode == MODE_IRONMAN and t["%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE] == "Ironman Mode" and String(t["%s/STR_SMALL200#0" % CUSTOMIZE]).begins_with("You gain double XP"), "Ironman chosen: label and the mode's lines (0xeb [6], [7])")
	check(" ".join([t["%s/STR_SMALL200#0" % CUSTOMIZE], t["%s/STR_SMALL200#1" % CUSTOMIZE], t["%s/STR_SMALL200#2" % CUSTOMIZE], t["%s/STR_SMALL200#3" % CUSTOMIZE], t["%s/STR_SMALL200#4" % CUSTOMIZE]]).strip_edges().ends_with("it is permanent."), "the Ironman text is whole")
	check(click("%s/BUTT_RIGHT_20#0" % CUSTOMIZE) and create_portrait == 21, "right arrow: the next portrait of the Knight list (0x54ec90(1): 0 -> 21)")
	check(click("%s/BUTT_LEFT_20#0" % CUSTOMIZE) and click("%s/BUTT_LEFT_20#0" % CUSTOMIZE) and create_portrait == 46, "left twice: back to 0, then the list's last (46)")
	check(canvas.bitmap_override.get("BM_PORTRAIT", "") == portrait_key(46), "the portrait shows Portrait46")
	check(step_choice([3, 5], 9, 1) == 3, "a value not in the list goes to the list's first entry")
	check(click("%s/BUTT_RIGHT_20#1" % CUSTOMIZE) and create_art == "AFHX" and avatar_frame == 0, "right arrow #1: the next avatar (0x54ed30: AHHX -> AFHX)")
	check(click("%s/BUTT_OPTIONS_DROPLIST#0" % CUSTOMIZE) and drop_labels() == ["Noble Male", "Knightly Male", "Flamboyant Male", "Cold Female", "Efficient Female", "Stern Male", "Serious Female"], "voice list: the Knight English voices (0x612ff0)")
	choose_voice(1)
	check(create_voice == "AXH3" and canvas.control_text["%s/BUTT_OPTIONS_DROPLIST#0" % CUSTOMIZE] == "Knightly Male", "a voice choice sets +0x60 (0x54ee50)")
	for ch in ["a", "b", "c", "d", "e", "f"]:
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = ch.unicode_at(0)
		_unhandled_input(key)
	check(create_password == "abcde", "the password edit keeps 5 characters")
	for i in 3:
		var back := InputEventKey.new()
		back.pressed = true
		back.keycode = KEY_BACKSPACE
		_unhandled_input(back)
	check(create_password == "ab", "Backspace edits it")
	check(click("%s/BUTT_CANCEL_200#0" % CUSTOMIZE) and screen == CREATE and create_portrait == 46 and create_art == "AFHX", "Cancel closes the panel and keeps the changes (0x54e300)")
	check(canvas.bitmap_override.get("BM_PORTRAIT", "") == portrait_key(46), "the creation screen shows the chosen portrait")

## G-3: More Info's Combat page totals (0x551410 with the 0x556ab0 resolver), the Titles and Items pages (Read).
func sheet_checks():
	var b := {"stats": [10, 12, 8, 6], "class": 0, "level": 3, "equipment": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"skills": [[1, 0, 2], [4, 0, 1], [2, 0, 3], [0x1f, 0, 2], [0x17, 0, 1], [0x1a, 0, 2], [0x1b, 0, 1], [0x19, 0, 2], [9, 0, 3]]}
	var s: Dictionary = Effects.sheet_combat(b)
	check(int(s.combat) == 20 and int(s.speed) == 15 and int(s.damage) == 20, "Combat page: combat 4 + S + 3 x rank, speed 8 + (D + 1) / 2 + rank, damage 10 + S (%s)" % s)
	check(int(s.life) == 4 * 2 + 240 + 30 + 30, "life 0x550600: 4 x (level - 1) + 240 + 3 S + 10 x rank (%d)" % int(s.life))
	check(int(s.armor) == 6 and s.vs_armor == [15, 10, 10], "armor D / 2; vs piercing / slashing / crushing + 2 x rank 0x1f + the type's term (%s)" % [s.vs_armor])
	check(int(s.resistance) == 12 and s.vs_resistance == [14, 19, 14], "resistance D; vs cold / fire / electricity + the raw rank of 0x1a (quirk) + the type's term (%s)" % [s.vs_resistance])
	check(int(s.magic_resistance) == 8 and int(s.merchant) == 1 + 3, "magic resistance 4 x rank 0x19; merchant -5 + C + the raw rank of 9")
	check(merchant_line(4).begins_with("Total Merchant Skill: +4") and merchant_line(-2).begins_with("Total Merchant Skill: -2"), "the merchant line, Game.txt [0862] / [0861]")
	var discount := -1
	var skilled := -1
	for it in Effects.items_data().get("items", []):
		for k in mini(int(it.power_count), 3):
			if int(it.powers[k].type) == 0xb and discount < 0: discount = int(it.index)
			if int(it.powers[k].type) == 99 and int(it.powers[k].level) > 0 and skilled < 0: skilled = int(it.index)
	if discount > 0:
		var d := b.duplicate(true)
		d.equipment[0] = discount
		var extra := 0
		for k in mini(int(Effects.item(discount).power_count), 3):
			if int(Effects.item(discount).powers[k].type) == 0xb: extra += int(Effects.item(discount).powers[k].data)
		check(int(Effects.sheet_combat(d).merchant) == 4 + extra, "an equipped discount item adds its data to the merchant total")
		d.equipment[0] = 0
		d.equipment[7] = discount
		check(int(Effects.sheet_combat(d).merchant) == 4, "a backpack item does not count")
	if skilled > 0:
		var power: Dictionary = Effects.item(skilled).powers.filter(func(p): return int(p.type) == 99)[0]
		var e := b.duplicate(true)
		e.equipment[1] = skilled
		check(Effects.record_rank(e, int(power.data), 1) == Effects.record_rank(b, int(power.data), 1) + int(power.level) and Effects.record_rank(e, int(power.data), 2) == Effects.record_rank(b, int(power.data), 2), "0x556ab0: an equipped item's hero-skill power adds to the rank (mode 1), not to mode 2")
		e["no_items"] = true
		check(Effects.record_rank(e, int(power.data), 1) == Effects.record_rank(b, int(power.data), 1), "0x556ab0 skips the items under No Hero Items (0x749c68)")
	check(game_text(935 + 1) == "Warrior" and game_text(935 + 10) == "Legendary Warlord" and game_text(0x3f8) == "Thrall", "Titles: rank names Game.txt [0935 + rank + 10 x row], totals [1016 + sum]")
	check(string_at(0x134, 6) == "Overall Ranking" and string_at(0x137, 2) == "Feet:" and ITEM_ROW_SLOTS[2] == 6, "the total label 0x134 [6]; the Items page's third row is Feet, record slot 6 (0x614c14)")
	check(string_at(0x136, 0) == "Empty" and string_at(0x136, 1) == "N/A", "Retinue: unused slots read Empty, N/A past the capacity (0x136)")

## UI gaps: the temporary hero (0x4e2660 -> 0x54b040(1, level) -> 0x54bbd0).
## FE-1: the hero book's More Info (0x550790) and Delete (0x555a70) on the three heroes the earlier checks made (Lady Menu
## is the Ironman hero with the password "ab").
func book_function_checks():
	check(screen == BOOK and heroes.size() == 3, "the book lists the three test heroes")
	for i in heroes.size():
		if String(heroes[i].name) == "Lady Menu": hero_index = i
	refresh_book()
	var lady_id := selected_hero_id()
	# More Info: PNL_HEROINFO over the book.
	check(click("%s/BUTT_MOREINFO_200#0" % BOOK) and popup == "info" and has_item("%s/BUTT_OKAY_200#0" % HEROINFO), "More Info opens PNL_HEROINFO (0x550790)")
	var t := canvas.control_text
	check(t["%s/STR_LARGE400#0" % HEROINFO] == "Lady Menu" and t["%s/STR_MEDIUM120#0" % HEROINFO] == "Race:" and t["%s/STR_MEDIUM120#4" % HEROINFO] == "Next Level At:", "the name and the labels of section 6 [3..7]")
	check(t["%s/STR_MEDIUM200#0" % HEROINFO] == "Knight" and t["%s/STR_MEDIUM200#1" % HEROINFO] == "Warrior" and t["%s/STR_MEDIUM200#2" % HEROINFO] == "1" and t["%s/STR_MEDIUM200#3" % HEROINFO] == "0" and t["%s/STR_MEDIUM200#4" % HEROINFO] == str(Rules.xp_threshold(2)), "race, class, level, XP and the next level's threshold (0x5509c0)")
	check(canvas.bitmap_override.get("BM_PORTRAIT", "") == portrait_key(46), "the hero's portrait")
	check(hit(Rect2(item("%s/BUTT_DELETE_200#0" % BOOK).rect).get_center()).is_empty(), "the book's buttons are blocked while the panel is open (modal)")
	check(not click("%s/BUTT_DELETE_200#0" % BOOK) or popup == "info", "Delete cannot open over More Info")
	check(info_tab == 0 and string_at(0x12, 0) == "Stats" and string_at(0x12, 5) == "Items", "the pages are Stats .. Items (section 0x12)")
	last_point = Vector2(99 + 250, 250)
	check(click("%s/PAD_HEROINFOTABS#0" % HEROINFO) and info_tab == 2, "a click on the tab strip picks the tab by (x - 99) / 100 (0x5508a7)")
	last_point = Vector2(99 + 599, 250)
	click("%s/PAD_HEROINFOTABS#0" % HEROINFO)
	check(info_tab == 5, "the sixth tab")
	check(stat_effects([10, 10, 10, 10], 0) == ["+10 Combat", "+10 Damage", "+30 Life", "+4 Life Regeneration per 20 sec."], "Strength's effects (0x54a8d0 case 0 with 0x54a720 kinds 0..3)")
	check(stat_effects([10, 10, 10, 10], 1)[0] == "+5 Move Speed (0.90 sec. Attack Speed)" and stat_effects([10, 10, 10, 10], 1)[3] == "-10 seconds to Conversion", "Dexterity's effects")
	check(stat_effects([10, 10, 10, 10], 2)[0] == "+30 Mana" and stat_effects([10, 10, 10, 10], 3)[1].begins_with("+5 Merchant skill (4.76% Discount)") and stat_effects([10, 10, 10, 10], 3)[3] == "+3 Retinue Slots", "Intelligence and Charisma effects")
	check(stat_effects([10, 10, 10, 0], 3)[1].begins_with("-5 Merchant skill (") and "Extra cost" in stat_effects([10, 10, 10, 0], 3)[1], "a negative merchant skill reads as extra cost")
	sheet_checks()
	for tab in 6:
		info_tab = tab
		overlay.queue_redraw()
		await get_tree().process_frame                                 # every page draws in the overlay's own _draw without error
	check(click("%s/BUTT_FREEZEHERO#0" % HEROINFO) and store.load_profile(lady_id).frozen() and canvas.control_state["%s/BUTT_FREEZEHERO#0" % HEROINFO] == 2, "Freeze Hero writes the record (0x1ad -> +0x10e6, saved)")
	check(click("%s/BUTT_FREEZEHERO#0" % HEROINFO) and not store.load_profile(lady_id).frozen(), "and unticks")
	check(handle_key(0x1b) and popup == "" and not has_item("%s/BUTT_OKAY_200#0" % HEROINFO), "Esc closes the panel (0x550810 message 5, key 0x1b)")
	check(click("%s/BUTT_MOREINFO_200#0" % BOOK) and click("%s/BUTT_OKAY_200#0" % HEROINFO) and popup == "", "Okay closes it too")
	# Delete: the generic box, then the password for a hero that has one, then the record goes.
	var saves := "user://front-end-self-test-saves-delete"
	DirAccess.make_dir_recursive_absolute(saves)
	save_directory = saves
	for path in save_files_of(lady_id, saves): FileAccess.open(path, FileAccess.WRITE).store_string("save")
	check(click("%s/BUTT_DELETE_200#0" % BOOK) and popup == "delete", "Delete opens PNL_OKAYCANCEL (0x555a70 -> 0x4361c0)")
	check(t["%s/STR_LARGE400#0" % OKAYCANCEL] == "Delete Hero", "title: section 6 [0]")
	var body := " ".join([t["%s/STR_MEDIUM500#0" % OKAYCANCEL], t["%s/STR_MEDIUM500#1" % OKAYCANCEL], t["%s/STR_MEDIUM500#2" % OKAYCANCEL], t["%s/STR_MEDIUM500#3" % OKAYCANCEL]]).strip_edges()
	check(body == "This will permanently remove the hero from your computer. Are you sure you want to do this?", "text: 6 [1] and 6 [2] joined by a space (0x614518)")
	check(click("%s/BUTT_CANCEL_180#0" % OKAYCANCEL) and popup == "" and heroes.size() == 3 and store.load_profile(lady_id) != null, "Cancel keeps the hero")
	check(click("%s/BUTT_DELETE_200#0" % BOOK) and click("%s/BUTT_OKAY_180#0" % OKAYCANCEL) and popup == "password", "Okay: a hero with a password asks for it (0x555ae0 -> 0x555bc0)")
	check(t["%s/STR_PARCHLARGE_L400#0" % PASSWORD] == "Enter password", "the panel's text (section 0x8e [4])")
	for ch in ["x", "y"]:
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = ch.unicode_at(0)
		_unhandled_input(key)
	check(popup_password == "xy" and t["%s/EDIT_PASSWORD#0" % PASSWORD] == "xy_", "typing fills the edit")
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	_unhandled_input(enter)
	check(popup == "password" and store.load_profile(lady_id) != null, "a wrong password leaves the hero and the panel (0x555d20)")
	for i in 2:
		var back := InputEventKey.new()
		back.pressed = true
		back.keycode = KEY_BACKSPACE
		_unhandled_input(back)
	# G-3: 0x5dc0b0 is _stricmp (Emulated, tests/password_compare_fixtures.json): "AB" opens the password "ab".
	var pw = JSON.parse_string(FileAccess.get_file_as_string("res://tests/password_compare_fixtures.json"))
	var pw_bad := 0
	for c in (pw.cases if pw is Dictionary else []):
		if stricmp(String(c.a), String(c.b)) != int(c.sign): pw_bad += 1
	check(pw is Dictionary and pw.cases.size() >= 50 and pw_bad == 0, "the password compare equals the emulated 0x5dc0b0 (%d differ)" % pw_bad)
	check(audio().has_sound("sfx/Error"), "Error.wav, the wrong-password sound (0x60f5d8)")
	for ch in ["A", "B"]:
		var key := InputEventKey.new()
		key.pressed = true
		key.unicode = ch.unicode_at(0)
		_unhandled_input(key)
	check(click("%s/BUTT_OKAY_180#0" % PASSWORD) and popup == "" and store.load_profile(lady_id) == null, "the right password in other case deletes the record (0x555550, _stricmp)")
	check(not FileAccess.file_exists(save_files_of(lady_id, saves)[0]) and not FileAccess.file_exists(save_files_of(lady_id, saves)[1]), "and the hero's saved games")
	check(FileAccess.file_exists(store.directory.path_join(lady_id + ".json.bak")) == false, "its backup copy too")
	check(screen == BOOK and heroes.size() == 2 and hero_index == 0 and not heroes.any(func(h): return h.id == lady_id), "the book starts again at the first hero (DAT_00bbad4c = 0)")
	check(store.selected_profile() == null or store.selected_profile().data.id != lady_id, "the selection no longer names the deleted hero")
	DirAccess.remove_absolute(saves)
	save_directory = SaveGame.default_directory()
	# No password: the box's Okay deletes at once.
	var plain := selected_hero_id()
	check(click("%s/BUTT_DELETE_200#0" % BOOK) and click("%s/BUTT_OKAY_180#0" % OKAYCANCEL) and popup == "" and store.load_profile(plain) == null and heroes.size() == 1, "a hero without a password is deleted by the box's Okay")
	check(not enabled("%s/BUTT_NEXT#0" % BOOK) and canvas.control_text["%s/STR_MEDIUM_LARGE_240#0" % BOOK] != "", "one hero left: Previous / Next disabled again")
	# Put two heroes back for the rest of the checks (the remaining one stays).
	for name in ["Restored One", "Restored Two"]:
		var restored = Profile.create(Crypto.new().generate_random_bytes(16).hex_encode(), name)
		store.save_profile(restored)
	open_hero_book()
	close_screen_help()

## The last hero's deletion starts hero creation (0x555550 -> 0x554120 -> 0x54b040(0, -1)).
func delete_all_checks():
	open_hero_book()
	close_screen_help()
	var count := heroes.size()
	check(count == 3, "three heroes before the last checks")
	for i in count:
		check(click("%s/BUTT_DELETE_200#0" % BOOK) and click("%s/BUTT_OKAY_180#0" % OKAYCANCEL), "delete hero %d" % (i + 1))
		if screen == CREATE: close_screen_help()
	check(screen == CREATE and store.list_profiles().is_empty(), "no hero left: hero creation opens (0x554120)")

func temporary_hero_checks():
	temp_dir = "user://front-end-self-test-temp"
	clean_dir(temp_dir)
	var book_size := store.list_profiles().size()
	temp_request = {"level": 7, "setup": {"marker": true}}
	open_create(true)
	close_screen_help()
	check(screen == CREATE and not enabled("%s/BUTT_CANCEL_STARTUP#0" % CREATE), "a temporary hero's creation screen has no Cancel (0x54b620)")
	check(click("%s/BUTT_CUSTOMIZE#0" % CREATE) and screen == CUSTOMIZE and not enabled("%s/BUTT_OPTIONS_DROPLIST#1" % CUSTOMIZE), "a temporary hero's Customize locks the mode list (0x54e790)")
	close_screen_help()
	check(click("%s/BUTT_OKAY_200#0" % CUSTOMIZE) and screen == CREATE and create_mode == MODE_NORMAL, "and closes back to creation in Normal Mode")
	hero_name = "Temp Hero"
	refresh_create()
	check(create_hero(), "Okay makes the temporary hero")
	var temp = Store.new(temp_dir).load_profile(TEMP_ID)
	check(temp != null and int(temp.data.level) == 7 and int(temp.data.xp) == Rules.xp_threshold(7) and int(temp.data.stat_points) == 7 and int(temp.data.skill_points) == 7 and bool(temp.data.extensions.get("temporary", false)), "level 7, its XP threshold, 7 stat and 7 skill points (0x54bbd0, 0x552d90(1, 7))")
	check(store.list_profiles().size() == book_size, "nothing is written to the hero book")
	var pending_setup: Dictionary = preload("res://simulation/skirmish_setup.gd").pending
	check(String(pending_setup.get("hero_id", "")) == TEMP_ID and String(pending_setup.get("store_dir", "")) == temp_dir and bool(pending_setup.setup.get("marker", false)), "the match is handed the setup and the scratch store")
	check(bool(preload("res://menus/hero_advance.gd").pending.get("temporary", false)) and String(preload("res://menus/hero_advance.gd").pending.next) == "res://menus/loading_screen.tscn", "then the stats / skills screens, then the loading screen")
	preload("res://simulation/skirmish_setup.gd").pending = {}
	preload("res://menus/hero_advance.gd").pending = {}
	clean_dir(temp_dir)
	temp_dir = TEMP_DIR
	open_hero_book()
	close_screen_help()

func self_test():
	check(mouse_filter == Control.MOUSE_FILTER_IGNORE, "the root passes mouse events to _unhandled_input (headless runs skip GUI routing)")
	clean_dir("user://front-end-self-test-heroes")
	DirAccess.remove_absolute("user://front-end-self-test-settings.cfg")
	Settings.use_file("user://front-end-self-test-settings.cfg")
	DirAccess.remove_absolute(help_flags_path())
	settings = Settings.current()
	store = Store.new("user://front-end-self-test-heroes")
	# Parity pass 2: the first main-menu visit shows the screen help (0x448870(0, 0)), not the tip; a click closes it.
	session_first_menu = true
	open_main()
	check(help_screen == 0 and help_boxes.size() == 5 and not tip_open, "first visit: screen help 0 with its five lines (ScreenHelp.txt SCREEN00)")
	check(help_boxes[0].heading and help_boxes[0].target == Vector2.ZERO and help_boxes[0].rect.position == Vector2(0xd0, 0x96), "the heading box at (208, 150)")
	check(help_boxes[0].rect.size.x == 0x177 and help_boxes[1].rect.position.y > help_boxes[0].rect.end.y - 1, "box width 375, boxes stacked")
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	screen_input(press_event)
	check(help_screen < 0, "a click closes the screen help")
	open_main()
	check(help_screen < 0 and not tip_open, "the second visit shows neither (help seen; tip only after the first entry)")
	check(handle_key(KEY_F1) and help_screen == 0, "F1 shows the main-menu help again (0x41d9d0: 0x10a -> 0x448870(0, 1))")
	handle_key(0x1b)
	check(help_screen < 0, "a key closes it too (modal)")
	# The tip of the day (0x453e30) and its checkbox.
	session_first_menu = true
	open_main()
	check(tip_open and tip_index >= 0 and tip_index < int(layout.get("tips_number", 0)), "first entry of a session: the tip of the day")
	check(canvas.control_text["%s/STR_LARGE400#0" % TIP] == "Tip of the day" and canvas.control_text["%s/STR_PARCHSMALL_L400#0" % TIP] != "", "tip title and first line")
	check(not hit(Rect2(item("%s/BUTT_MM_OPTIONS#0" % MAIN).rect).get_center()).has("key") or hit(Rect2(item("%s/BUTT_MM_OPTIONS#0" % MAIN).rect).get_center()).panel == TIP, "the tip is modal")
	close_tip()
	open_tip(3)
	var tip_text: String = layout.tips[3]
	check(canvas.control_text["%s/STR_PARCHSMALL_L400#0" % TIP] != "" and tip_text.begins_with(String(canvas.control_text["%s/STR_PARCHSMALL_L400#0" % TIP])), "tip 3 wrapped into the lines")
	check(click("%s/BUTT_TIPOFTHEDAY#0" % TIP) and settings.get_value("TipOfTheDay") == 0 and FileAccess.file_exists("user://front-end-self-test-settings.cfg"), "unticking stores TipOfTheDay 0 and saves (0x4540b0)")
	check(click("%s/BUTT_DONE_180#0" % TIP) and not tip_open, "Done closes the tip")
	check(not open_tip(), "no tip while the option is off")
	settings.set_value("TipOfTheDay", 1)
	settings.save()
	# The main-menu hover float (0x405360 / 0x405500).
	clock_ms = 1000
	hovered_changed(item("%s/BUTT_MM_SINGLEPLAYER#0" % MAIN))
	check(floats.size() == 1 and floats[0].text == "Skirmish" and floats[0].y == 207, "hovering Skirmish floats its label at y 207")
	check(float_state(0).spacing == 0 and float_state(0).level == 9 and float_state(750).spacing == 10 and float_state(750).level == 12 and float_state(1499).level == 14, "spacing 0..20 and level 9..15 over 1500 ms")
	hovered_changed(item("%s/BUTT_MM_QUIT#0" % MAIN))
	check(floats.size() == 2 and floats[1].y == 472, "Quit floats at y 472 (mode 2: a second slot)")
	for i in 20: add_float("x", 0)
	check(floats.size() == FLOAT_SLOTS, "at most 12 slots")
	clock_ms = 2600
	update_floats()
	check(floats.is_empty(), "the floats end after 1500 ms")
	check(handle_key(0x20) and floats.size() == 1 and floats[0].text == "Test" and floats[0].y == 300, "Space floats 'Test' at (400, 300)")
	# Playtest 2026-11-12: a float still running when the main menu is left must not stay on the next screen.
	var main_screen := screen
	screen = OPTIONS
	_process(0.0)
	check(floats.is_empty(), "leaving the main menu drops its floats (the main menu's draw case 0x458614 alone draws them)")
	screen = main_screen
	clock_ms = -1
	floats.clear()
	check(not handle_key(0xd) and screen == MAIN, "Enter does nothing on the main menu")
	for c in ["BUTT_MM_CAMPAIGN", "BUTT_MM_SINGLEPLAYER", "BUTT_MM_MULTIPLAYER", "BUTT_MM_TUTORIAL", "BUTT_MM_OPTIONS", "BUTT_MM_EDITOR", "BUTT_MM_QUIT"]:
		check(has_item("%s/%s#0" % [MAIN, c]), "main menu control " + c)
	check(canvas.text_of(item("%s/BUTT_MM_SINGLEPLAYER#0" % MAIN).element.label) == "Skirmish", "Skirmish label (TXT_STARTUP)")
	check(not enabled("%s/BUTT_MM_CAMPAIGN#0" % MAIN) and not enabled("%s/BUTT_MM_MULTIPLAYER#0" % MAIN) and not enabled("%s/BUTT_MM_EDITOR#0" % MAIN), "out-of-scope entries disabled")
	check(item("%s/BUTT_MM_SINGLEPLAYER#0" % MAIN).rect.position == Vector2i(200, 195), "main menu centred at 800x600 (2000,2000 sentinel)")
	check(canvas.control_text["%s/STR_SMALL80#0" % MAIN] == "1.03", "version string")
	# A real click through the window (the root must not swallow mouse events before _unhandled_input).
	check(real_click("%s/BUTT_MM_OPTIONS#0" % MAIN) and screen == OPTIONS and options != null, "a mouse click on Options opens it")
	check(not options.handle_key(KEY_F1) and options.help_screen < 0, "the options screen has no F1 help (0x411590 handles no key)")
	check(options.real_click("%s/BUTT_CANCEL_STARTUP#0" % OPTIONS) and screen == MAIN and options == null, "a mouse click on Cancel returns")
	# Options: tabs, labels from the defaults, a dropdown change, Cancel restores, Okay persists.
	check(click("%s/BUTT_MM_OPTIONS#0" % MAIN) and screen == OPTIONS, "Options opens PNL_GAMEOPTIONS")
	var o = options
	await get_tree().process_frame
	var text: Dictionary = o.canvas.control_text
	check(text["%s/BUTT_OPTIONS_DROPLIST#2" % OPTIONS] == "Game Speed: Medium", "game speed label (default 2)")
	check(text["%s/BUTT_OPTIONS_DROPLIST#1" % OPTIONS] == "Scrollrate: Medium", "scroll rate label (default 3)")
	check(text["%s/BUTT_OPTIONS_DROPLIST#0" % OPTIONS] == "Popup Help: All", "help level label (default 2)")
	check(text["%s/BUTT_OPTIONS_DROPLIST#6" % OPTIONS] == "System Voice: Female", "advisor label (default 0, Game.txt 751)")
	# DELIBERATE MODERN CHANGE (modern_rules.gd): the original's empty rows 8 and 9 hold Battle Rules and Health Bars.
	check(o.enabled("%s/BUTT_OPTIONS_DROPLIST#8" % OPTIONS) and text["%s/BUTT_OPTIONS_DROPLIST#8" % OPTIONS] == "Battle Rules: Original", "row 8: Battle Rules (default Original)")
	check(text["%s/BUTT_OPTIONS_DROPLIST#9" % OPTIONS] == "Health Bars: Selected", "row 9: Health Bars (default Selected)")
	o.open_drop(2)
	check(o.drop_labels() == ["Very Slow", "Slow", "Medium", "Fast", "Very Fast"], "game speed choices")
	check(o.list_rect.size.y == 5 * LIST_ROW and is_equal_approx(o.list_rect.size.x, o.drop_labels().map(func(l): return o.text_width(l, LIST_FONT)).max() + 20.0), "one column of 20-pixel rows, widest entry + 20 (0x45cfe0)")
	check(o.list_rect.end.x <= 795.5 and o.list_rect.end.y <= 595.5, "the list ends inside x 795 / y 595")
	o.choose(2, 3)
	check(settings.get_value("GameSpeed") == 3 and text["%s/BUTT_OPTIONS_DROPLIST#2" % OPTIONS] == "Game Speed: Fast", "choice stored")
	# Modern change: five tabs, the fourth (Advanced) with the display rows (Resolution leads there), the fifth Visuals.
	var tabs: Array = [0, 1, 2, 3, 4].map(func(i): return o.item("%s/BUTT_GAMEOPTIONS_OPTION#%d" % [OPTIONS, i]))
	check(tabs.all(func(t): return not t.is_empty()) and tabs.map(func(t): return t.rect.position.x) == [130, 247, 360, 466, 582], "five tabs at x 130 / 247 / 360 / 466 / 582 (modern change)")
	check(text["%s/BUTT_GAMEOPTIONS_OPTION#3" % OPTIONS] == "Advanced" and text["%s/BUTT_GAMEOPTIONS_OPTION#4" % OPTIONS] == "Visuals", "the fourth tab reads Advanced, the fifth Visuals")
	check(o.click("%s/BUTT_GAMEOPTIONS_OPTION#4" % OPTIONS) and o.page == 4, "Visuals tab")
	check(text["%s/BUTT_OPTIONS_DROPLIST#0" % OPTIONS] == "Enhanced Visuals: Off" and not o.enabled("%s/BUTT_OPTIONS_DROPLIST#1" % OPTIONS), "enhanced visuals off by default; the other rows wait for it")
	o.open_drop(0)
	o.choose(0, 1)
	check(bool(DisplayConfig.visual("Enhanced")) and o.enabled("%s/BUTT_OPTIONS_DROPLIST#3" % OPTIONS) and text["%s/BUTT_OPTIONS_DROPLIST#3" % OPTIONS] == "Effect Glow: Subtle", "switching it on enables the rows")
	o.open_drop(0)
	o.choose(0, 0)
	check(o.click("%s/BUTT_GAMEOPTIONS_OPTION#1" % OPTIONS) and o.page == 1, "Graphics tab")
	check(text["%s/BUTT_OPTIONS_DROPLIST#0" % OPTIONS] == "Resolution: Native", "the resolution row reads Native")
	check(o.click("%s/BUTT_OPTIONS_DROPLIST#0" % OPTIONS) and o.page == 3 and not o.is_list_open(), "it opens the Advanced tab")
	check(text["%s/BUTT_OPTIONS_DROPLIST#0" % OPTIONS] == "Window Mode: Borderless" and text["%s/BUTT_OPTIONS_DROPLIST#4" % OPTIONS] == "Battlefield View: Widescreen", "Advanced labels from the defaults")
	check(not o.enabled("%s/BUTT_OPTIONS_DROPLIST#2" % OPTIONS), "window size disabled outside windowed mode")
	o.open_drop(4)
	check(o.drop_labels() == ["Original", "Widescreen", "Ultrawide"], "battlefield view choices")
	o.choose(4, 0)
	check(int(DisplayConfig.setting("BattlefieldView")) == 0 and text["%s/BUTT_OPTIONS_DROPLIST#4" % OPTIONS] == "Battlefield View: Original", "an Advanced choice applies at once")
	o.open_drop(0)
	o.choose(0, 0)
	check(int(DisplayConfig.setting("WindowMode")) == 0 and not o.window_before.is_empty() and String(text["%s/STR_MEDIUM500#0" % OPTIONS]).begins_with("Okay keeps"), "a window change asks to be kept")
	o._process(16.0)
	check(int(DisplayConfig.setting("WindowMode")) == 1 and o.window_before.is_empty(), "and reverts after 15 s")
	check(o.click("%s/BUTT_GAMEOPTIONS_OPTION#2" % OPTIONS) and o.page == 2, "Sound tab")
	check(text["%s/BUTT_OPTIONS_DROPLIST#2" % OPTIONS] == "SFX: Full" and text["%s/BUTT_OPTIONS_DROPLIST#3" % OPTIONS] == "Music: High", "sound labels (120 / 3)")
	o.choose(2, 2)
	check(settings.get_value("OverallVolume") == 60, "SFX Medium stores 60 (0x40fed4)")
	var sound = audio()
	check(sound.effects_volume == 60, "the mixer follows the SFX option at once")
	o.choose(8, 1)
	check(settings.get_value("HeroHeartbeat") == 0 and int(sound.options.HeroHeartbeat) == 0, "heartbeat option off")
	check(o.click("%s/BUTT_CANCEL_STARTUP#0" % OPTIONS) and screen == MAIN, "Cancel returns to the main menu")
	check(settings.get_value("GameSpeed") == 2 and settings.get_value("OverallVolume") == 120 and sound.effects_volume == 120, "Cancel restores the entry copy")
	check(int(DisplayConfig.setting("BattlefieldView")) == 1, "Cancel restores the display settings too")
	check(not bool(DisplayConfig.visuals.Enhanced), "and the visuals settings")
	click("%s/BUTT_MM_OPTIONS#0" % MAIN)
	o = options
	o.click("%s/BUTT_GAMEOPTIONS_OPTION#0" % OPTIONS)
	o.open_drop(1)
	o.choose(1, 4)
	check(o.click("%s/BUTT_OKAY_STARTUP#0" % OPTIONS) and screen == MAIN, "Okay returns to the main menu")
	var reread = Settings.new()
	check(reread.load_from("user://front-end-self-test-settings.cfg") and reread.get_value("ScrollRate") == 5 and reread.get_value("GameSpeed") == 2, "Okay persists the options")
	Settings.use_file("user://front-end-self-test-settings.cfg")
	check(Settings.current().get_value("ScrollRate") == 5, "a new session reads the saved file")
	settings = Settings.current()
	# Hero book: no hero -> creation; create; book page; select -> setup (scene change suppressed in the self-test).
	check(click("%s/BUTT_MM_SINGLEPLAYER#0" % MAIN) and screen == CREATE, "Skirmish without a hero opens hero creation (0x5536e0)")
	check(help_screen == 2, "first visit of hero creation: screen help 2")
	close_screen_help()
	check(not enabled("%s/BUTT_OKAY_STARTUP#0" % CREATE), "Okay needs a name")
	check(canvas.control_text["%s/STR_MEDIUM120#0" % CREATE] == "Name" and canvas.control_text["%s/BUTT_OPTIONS_DROPLIST#0" % CREATE] == "Knight", "creation texts")
	hero_name = "Sir Menu"
	refresh_create()
	check(click("%s/BUTT_OKAY_STARTUP#0" % CREATE) and screen == BOOK, "creating a hero opens the book")
	check(help_screen == 1, "first visit of the hero book: screen help 1")
	close_screen_help()
	check(canvas.control_text["%s/STR_MEDIUM_LARGE_240#0" % BOOK] == "Sir Menu" and canvas.control_text["%s/STR_SMALL220#2" % BOOK] == "Level: 1", "book page (0x554260)")
	check(canvas.control_text["%s/STR_SMALL220#0" % BOOK] == "Knight" and canvas.control_text["%s/STR_SMALL220#1" % BOOK] == "Warrior", "race and class lines")
	check(canvas.bitmap_override.get("BM_PORTRAIT", "").begins_with("X:Portrait"), "hero portrait (Portrait%02d.bmp)")
	check(not enabled("%s/BUTT_NEXT#0" % BOOK) and not enabled("%s/BUTT_LOADGAME_200#0" % BOOK), "one hero: Previous/Next and Load Game disabled")
	# S-2: the hero's save enables Load Game (0x5563a0); a damaged file is refused and stays on the book.
	save_directory = "user://front-end-self-test-saves"
	DirAccess.make_dir_recursive_absolute(save_directory)
	var damaged := SaveGame.path_for(String(heroes[hero_index].id), save_directory)
	FileAccess.open(damaged, FileAccess.WRITE).store_string("not a save")
	refresh_book()
	check(enabled("%s/BUTT_LOADGAME_200#0" % BOOK), "Load Game enabled with a saved game")
	check(load_hero_game() != "" and screen == BOOK, "a damaged save is refused")
	DirAccess.remove_absolute(damaged)
	DirAccess.remove_absolute(save_directory)
	save_directory = SaveGame.default_directory()
	refresh_book()
	check(enabled("%s/BUTT_DELETE_200#0" % BOOK) and enabled("%s/BUTT_MOREINFO_200#0" % BOOK), "Delete and More Info are enabled (FE-1)")
	check(layout.exported_bitmaps.has("BM_DIALOGSMALL") and layout.exported_bitmaps.has("BM_HEROINFOBG") and layout.exported_bitmaps.has("BM_BG_BONE584X292"), "the art of the dialogs the original opens is in this install (PNL_OKAYCANCEL, PNL_HEROINFO, PNL_PASSWORD)")
	check(not handle_key(0x1b) and screen == BOOK, "Esc does nothing in the hero book")
	check(click("%s/BUTT_NEWHERO_200#0" % BOOK) and screen == CREATE, "New Hero")
	check(help_screen < 0, "the creation help shows only once")
	hero_name = "sir menu"
	refresh_create()
	check(not create_hero() and canvas.control_text["%s/STR_LARGE750#0" % CREATE] == "Hero Already Exists!", "duplicate names refused")
	# Milestone 11b: the race and class droplists (0x54bb50 / 0x54bb90).
	check(create_race == 0 and create_class == 0 and canvas.control_text["%s/BUTT_OPTIONS_DROPLIST#1" % CREATE] == "Warrior", "the screen opens on Knight / Warrior (0x54b770(1))")
	check(enabled("%s/BUTT_OPTIONS_DROPLIST#0" % CREATE) and enabled("%s/BUTT_OPTIONS_DROPLIST#1" % CREATE) and enabled("%s/BUTT_CUSTOMIZE#0" % CREATE), "race and class droplists and Customize enabled")
	check(click("%s/BUTT_OPTIONS_DROPLIST#0" % CREATE) and drop_row == 0 and drop_labels().size() == 16 and drop_labels()[1] == "Dwarf" and drop_labels()[15] == "Plaguelord", "race list: the 16 races (0x61204c)")
	check(drop_index(drop_rect.position + Vector2(5, LIST_ROW + 5)) == 1, "the list hit test")
	choose_create(0, 1)
	check(drop_row < 0 and not is_list_open() and create_race == 1 and canvas.control_text["%s/BUTT_OPTIONS_DROPLIST#0" % CREATE] == "Dwarf", "Dwarf chosen")
	check(canvas.bitmap_override.get("BM_PORTRAIT", "") == portrait_key(1), "the Dwarf portrait (0x54f230: Portrait01)")
	check(click("%s/BUTT_OPTIONS_DROPLIST#1" % CREATE) and drop_labels().size() == 28 and drop_labels()[0] == "Alchemist" and drop_labels()[27] == "Warrior", "class list sorted by name (0x54b0c8)")
	check(list_rect.size.y == 28 * LIST_ROW and list_rect.position.y >= 0 and list_rect.end.y <= 595.5, "the 28 classes in one column, moved up to fit")
	choose_create(1, Rules.class_droplist().find(15))
	var rune := Rules.creation(1, 15)
	check(create_class == 15 and canvas.control_text["%s/BUTT_OPTIONS_DROPLIST#1" % CREATE] == "Runemaster", "Runemaster chosen")
	check(canvas.control_text["%s/STR_SMALL120#0" % CREATE] == string_at(5, 0) % int(rune.stats[0]) and canvas.control_text["%s/STR_SMALL120#3" % CREATE] == string_at(5, 3) % int(rune.stats[3]), "Dwarf Runemaster stats (0x54c0a0)")
	hero_name = "Thane Menu"
	check(create_hero() and screen == BOOK, "a Dwarf Runemaster created")
	var thane = store.selected_profile()
	check(thane != null and int(thane.data.race_id) == 1 and int(thane.data.class_id) == 15 and thane.data.original_type_id == "ADHX" and thane.data.voice_id == "ADHX" and int(thane.data.portrait_id) == 1 and thane.data.stats.map(func(v): return int(v)) == rune.stats, "the saved record: race, class, art, voice, portrait, stats")
	check(canvas.control_text["%s/STR_SMALL220#0" % BOOK] == "Dwarf" and canvas.control_text["%s/STR_SMALL220#1" % BOOK] == "Runemaster", "book page race and class (sections 0xf / 9)")
	check(click("%s/BUTT_NEWHERO_200#0" % BOOK) and screen == CREATE and create_race == 0, "New Hero opens on Knight again")
	customize_checks()
	hero_name = "Lady Menu"
	check(create_hero() and heroes.size() == 3 and enabled("%s/BUTT_NEXT#0" % BOOK), "third hero; Next enabled")
	var lady = store.selected_profile()
	check(lady != null and int(lady.data.portrait_id) == 46 and lady.data.original_type_id == "AFHX" and lady.data.voice_id == "AXH3" and String(lady.data.extensions.get("password", "")) == "ab", "Customize's portrait, avatar, voice and password are on the saved record")
	check(lady != null and lady.data.mode == Profile.MODE_IRONMAN and lady.validate() == "", "the Ironman choice is on the saved record (+0x54 = 1) and the record validates")
	temporary_hero_checks()
	await book_function_checks()
	var first: String = canvas.control_text["%s/STR_MEDIUM_LARGE_240#0" % BOOK]
	click("%s/BUTT_NEXT#0" % BOOK)
	check(canvas.control_text["%s/STR_MEDIUM_LARGE_240#0" % BOOK] != first, "Next flips the page")
	check(click("%s/BUTT_OKAY_STARTUP#0" % BOOK) and store.selected_profile() != null and store.selected_profile().data.name == canvas.control_text["%s/STR_MEDIUM_LARGE_240#0" % BOOK], "Okay selects the hero")
	check(click("%s/BUTT_CANCEL_STARTUP#0" % BOOK) and screen == MAIN, "book Cancel returns to the main menu")
	delete_all_checks()
	check(presentation_ok(), "1080p pillarbox")
	clean_dir("user://front-end-self-test-heroes")
	DirAccess.remove_absolute(help_flags_path())
	DirAccess.remove_absolute("user://front-end-self-test-settings.cfg")
	Settings.use_file(Settings.DEFAULT_PATH)
	if not failed: print("Front end checks passed: %d" % checks)
	get_tree().quit(1 if failed else 0)

func presentation_ok() -> bool:
	var window := Vector2(PRESENTATION)
	var scale := minf(window.y / BASE.y, window.x / BASE.x)
	return is_equal_approx(scale, 1.8) and is_equal_approx((window.x - BASE.x * scale) / 2.0, 240.0)

# ------------------------------------------------------------------------------------------------ captures
## `-- --capture`: each front-end screen with the real renderer into .local/menu_capture_*.png (copied profile folder).
func capture():
	Settings.use_file("user://menu-capture-settings.cfg")
	settings = Settings.current()
	store = Store.new("user://menu-capture-heroes")
	DirAccess.remove_absolute(help_flags_path())
	session_first_menu = true
	open_main()
	await capture_png("res://.local/menu_capture_00_main_help.png")
	close_screen_help()
	open_tip(0)
	await capture_png("res://.local/menu_capture_00_tip.png")
	close_tip()
	hovered_changed(item("%s/BUTT_MM_SINGLEPLAYER#0" % MAIN))
	clock_ms = Time.get_ticks_msec() + 600
	floats[0].start_ms = Time.get_ticks_msec()
	await capture_png("res://.local/menu_capture_01_main.png")
	clock_ms = -1
	floats.clear()
	open_options()
	await capture_png("res://.local/menu_capture_02_options_gameplay.png")
	options.select_page(2)
	options.open_drop(2)
	await capture_png("res://.local/menu_capture_03_options_sound_drop.png")
	options.close_list()
	options.select_page(1)
	await capture_png("res://.local/menu_capture_04_options_graphics.png")
	options.select_page(3)
	await capture_png("res://.local/menu_capture_04b_options_advanced.png")
	options.open_drop(4)
	await capture_png("res://.local/menu_capture_04c_options_advanced_drop.png")
	options.close_list()
	options.click("%s/BUTT_CANCEL_STARTUP#0" % OPTIONS)
	open_create()
	close_screen_help()
	hero_name = "Sir Capture"
	refresh_create()
	await capture_png("res://.local/menu_capture_05_create_hero.png")
	open_customize()
	close_screen_help()
	step_portrait(1)
	create_password = "ab"
	refresh_customize()
	await capture_png("res://.local/menu_capture_05b_customize.png")
	close_customize()
	create_hero()
	close_screen_help()
	await capture_png("res://.local/menu_capture_06_hero_book.png")
	if open_info():                                                # G-3: the More Info pages (Combat, Titles, Retinue, Items)
		for tab in [1, 3, 4, 5]:
			info_tab = tab
			overlay.queue_redraw()
			await capture_png("res://.local/menu_capture_07_info_%d.png" % tab)
		close_popup()
	clean_dir("user://menu-capture-heroes")
	DirAccess.remove_absolute(help_flags_path())
	DirAccess.remove_absolute("user://menu-capture-settings.cfg")
	get_tree().quit()
