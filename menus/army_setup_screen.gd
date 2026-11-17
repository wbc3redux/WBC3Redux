extends "res://core/ui_screen.gd"
## The army setup screen (skirmish setup session; SKIRMISH_RESEARCH.md "Army setup points"; Read unless noted): PNL_RETINUE
## (0xe9) opened by 0x440b40(1, budget) after the scenario has loaded (0x417730), when the setup's army points plus the
## handicap term are 1 or more. Rules in simulation/army_setup.gd.
## * 0x4417b0 (army mode, 0xa245e0 = 1): PNL_RETINUE at layer 2000; the race's offers (0x444980) in PNL_RETINUE_RECRUIT1..n
##   at 0x6092c8 / 0x6092e8 (the left boxes) and the hero's retinue in PNL_RETINUE_ARMY1..n at 0x609288 / 0x6092a8 (the
##   right boxes), layer 0x7e5. Headers 0xa8 [4] "Regular Troops" and [0] "Your Retinue", help lines 0xa4 [2], [3], the
##   centre plate "Army Setup Points" (0xab [2]), the build level line (0xae) and "spent / budget" ("%d / %d", or
##   "%d/%d" once either is 21 or more). An offer's box shows "Name" or "Name (count)"; its cost is formatted but an
##   empty string is written (0x442437 -> 0x442452), so no cost is shown; medals, the combat icon and its number are
##   moved off the screen.
## * 0x443890: a left click on an offer adds one when spent + cost <= budget; a right click takes one back; both play
##   NewClick. Okay (0x440e80 case 0x4b) answers only after 1 s and starts the match (0x4179f0 -> 0x4406b0 places the units).
## * S-2, deploying the retinue for points (callback 0x4427d0, disassembled): a left click on a retinue box (0xd7) toggles
##   0xa245d0[i]; the spent total 0xa245e8 grows or shrinks by 0x444940 (the type's cost + the medal term); a box that does not
##   fit is refused (0xa23ca0, set by 0x4417b0: deployed, or spent + cost <= budget). 0x4406b0 places them before the bought
##   units.
## * Not ported (Open): the unit picture (image subtype 25, drawn at run time: the rebuild shows the unit's 90 x 90
##   portrait, icon column 3), the information popup after a long hover (0x4431c0), the graveyard button in army mode
##   (0x440b10).

const Setup = preload("res://simulation/skirmish_setup.gd")
const Army = preload("res://simulation/army_setup.gd")
const ArtData = preload("res://core/art_data.gd")
const Store = preload("res://simulation/hero_store.gd")
const Rules = preload("res://simulation/hero_rules.gd")
const PANEL := "PNL_RETINUE"
const RECRUIT_ROWS := [Vector2i(93, 125), Vector2i(191, 125), Vector2i(289, 125), Vector2i(93, 245), Vector2i(191, 245),
	Vector2i(93, 365), Vector2i(191, 365), Vector2i(289, 365)]      # 0x6092c8 / 0x6092e8 (Data)
const RETINUE_ROWS := [Vector2i(417, 125), Vector2i(515, 125), Vector2i(613, 125), Vector2i(515, 245), Vector2i(613, 245),
	Vector2i(417, 365), Vector2i(515, 365), Vector2i(613, 365)]      # 0x609288 / 0x6092a8 (Data)
const HELP_SCREEN := 8                  # 0x440b40: 0x448870(8, 0) in army mode
const OKAY_DELAY_MS := 1000             # 0x440e80: Okay is ignored within 1000 ms of opening

## The loaded match scene, handed over by the loading screen (the original opens this screen after loading).
static var next_scene: PackedScene = null

var setup: Dictionary = {}
var budget := 0
var race := 0
var offered: Array = []
var counts: Array = []
var retinue: Array = []
var deployed: Array = []                # 0xa245d0
var opened_ms := 0
var finished := false

func _ready():
	setup_screen()
	fit_window(get_window())
	if "--self-test" in OS.get_cmdline_user_args():
		preload("res://simulation/game_settings.gd").use_file("user://army-setup-self-test-settings.cfg")
		mark_all_seen()
		call_deferred("self_test")
		return
	if "--capture" in OS.get_cmdline_user_args():
		mark_all_seen()
		call_deferred("capture")
		return
	var pending: Dictionary = Setup.pending
	begin(pending.get("setup", {}), String(pending.get("hero_id", "")))
	open_screen_help(HELP_SCREEN, false)

## 0x440b40(1, budget) + 0x444980 + 0x4417b0.
func begin(match_setup: Dictionary, hero_id: String):
	setup = match_setup
	budget = mini(int(setup.get("army_budget", 0)), Army.MAX_BUDGET)
	var local := int(setup.get("local", 0))
	race = int(Setup.resolve(setup).slots[local].race)
	offered = Army.offers(race)
	counts = []
	for code in offered: counts.append(0)
	retinue = []
	var profile = Store.new().load_profile(hero_id) if hero_id != "" else null
	if profile != null:
		var capacity := Rules.retinue_capacity(int(profile.data.stats[3]))
		retinue = profile.data.retinue.slice(0, mini(capacity, RETINUE_ROWS.size()))
	set_retinue(retinue)
	opened_ms = Time.get_ticks_msec()
	canvas.placements.clear()
	place(PANEL, Vector2i.ZERO, 2000)
	for i in mini(offered.size(), RECRUIT_ROWS.size()): place("PNL_RETINUE_RECRUIT%d" % (i + 1), RECRUIT_ROWS[i], 0x7e5)
	for i in retinue.size(): place("PNL_RETINUE_ARMY%d" % (i + 1), RETINUE_ROWS[i], 0x7e5)
	refresh()

func set_retinue(units: Array):
	retinue = units
	deployed = []
	for unit in retinue: deployed.append(false)

func spent() -> int:
	var total := 0
	for i in offered.size(): total += Army.cost(String(offered[i])) * int(counts[i])
	for i in retinue.size():
		if bool(deployed[i]): total += retinue_cost(i)
	return total

## 0x444940 for a retinue box.
func retinue_cost(index: int) -> int:
	return Army.retinue_cost(String(retinue[index].get("original_type_id", "")), int(retinue[index].get("medal_level", 0)))

## 0x4417b0: 0xa23ca0, a box can be clicked when deployed or when it fits.
func can_deploy(index: int) -> bool:
	return bool(deployed[index]) or spent() + retinue_cost(index) <= budget

## 0x4427d0 case 2, control 0xd7, army mode.
func toggle_retinue(index: int) -> bool:
	if index < 0 or index >= retinue.size() or not can_deploy(index): return false
	deployed[index] = not bool(deployed[index])
	refresh()
	return true

func retinue_index(item_key: String) -> int:
	if not item_key.begins_with("PNL_RETINUE_ARMY") or not item_key.contains("/BUTT_RETINUE_ARMY#"): return -1
	return int(item_key.trim_prefix("PNL_RETINUE_ARMY").get_slice("/", 0)) - 1

func refresh():
	var t := canvas.control_text
	var s := canvas.control_state
	t.clear()
	s.clear()
	var hidden := Vector2i(10000, 10000)                         # 0x45e410(.., 1000, 1000): moved off the screen
	t["%s/STR_LARGE332#0" % PANEL] = string_at(0xa8, 4)
	t["%s/STR_LARGE332#1" % PANEL] = string_at(0xa8, 0)
	var level := int(setup.get("options", {}).get("build_level", 5))
	t["%s/STR_SMALL_180#15" % PANEL] = string_at(0xae, 0) if level == 0 else string_at(0xae, 5) % level
	t["%s/STR_SMALL_180#16" % PANEL] = string_at(0xab, 2)
	for i in 3: t["%s/STR_MEDIUM200#%d" % [PANEL, i]] = ""
	t["%s/STR_MEDIUM500#0" % PANEL] = string_at(0xa4, 2)
	t["%s/STR_MEDIUM500#1" % PANEL] = string_at(0xa4, 3)
	var used := spent()
	t["%s/STR_LARGE200#0" % PANEL] = ("%d / %d" if used < 21 and budget < 21 else "%d/%d") % [used, budget]
	s["%s/BUTT_RETINUE_GRAVEYARD#0" % PANEL] = 3
	for i in offered.size():
		var panel := "PNL_RETINUE_RECRUIT%d" % (i + 1)
		var name := names_of(String(offered[i]))
		t["%s/STR_SMALL_180#0" % panel] = name if int(counts[i]) < 1 else "%s (%d)" % [name, int(counts[i])]
		hide_box_details(panel, hidden)
	for i in retinue.size():
		var panel := "PNL_RETINUE_ARMY%d" % (i + 1)
		var unit: Dictionary = retinue[i]
		t["%s/STR_SMALL_180#0" % panel] = String(unit.get("name", names_of(String(unit.get("original_type_id", "")))))
		s["%s/BUTT_RETINUE_ARMY#%d" % [panel, i]] = 2 if bool(deployed[i]) else (0 if can_deploy(i) else 3)
		s["%s/BUTT_RETINUE_ARMY_NAME#%d" % [panel, i]] = 3
		hide_box_details(panel, hidden)
	canvas.queue_redraw()
	overlay.queue_redraw()

func hide_box_details(panel: String, hidden: Vector2i):
	for m in 7: canvas.control_offset["%s/IM_RETINUE_MEDAL#%d" % [panel, m]] = hidden
	canvas.control_offset["%s/IM_RETINUE_ICON_COMBAT#0" % panel] = hidden
	canvas.control_text["%s/STR_SMALL24#0" % panel] = ""
	canvas.control_text["%s/STR_MEDIUM30#1" % panel] = ""

## 0x58a260: the unit's display name (the catalogue's names; Army.cfg / *.en).
var _names: Dictionary = {}
func names_of(code: String) -> String:
	if _names.is_empty():
		var catalogue: Dictionary = Assets.json("catalogue.json")
		for c in catalogue.units:
			var display = catalogue.units[c].get("display", {})
			_names[c] = String(display.get("name", c)) if display is Dictionary else c
	return String(_names.get(code, code))

# ------------------------------------------------------------------------------------------------ input
func help_id() -> int:
	return HELP_SCREEN

func _unhandled_input(event: InputEvent):
	# 0x443890 answers both buttons on release; the left button goes through the shared handler (NewClick + press).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed \
			and help_screen < 0 and not is_list_open():
		var entry := hit(to_native(event.position))
		var index := recruit_index(String(entry.get("key", "")))
		if index >= 0:
			audio().click()
			sell(index)
		return
	screen_input(event)

## The offer behind a key: box n's button is BUTT_RETINUE_ARMY instance n - 1 (0x443890 reads the index from it).
func recruit_index(item_key: String) -> int:
	if not item_key.begins_with("PNL_RETINUE_RECRUIT") or not item_key.contains("/BUTT_RETINUE_ARMY#"): return -1
	return int(item_key.trim_prefix("PNL_RETINUE_RECRUIT").get_slice("/", 0)) - 1

static func recruit_key(index: int) -> String:
	return "PNL_RETINUE_RECRUIT%d/BUTT_RETINUE_ARMY#%d" % [index + 1, index]

func press(item_key: String):
	if item_key == "%s/BUTT_OKAY_STARTUP#0" % PANEL:
		finish()
		return
	var index := recruit_index(item_key)
	if index >= 0: buy(index)
	elif retinue_index(item_key) >= 0: toggle_retinue(retinue_index(item_key))

## 0x443890 left click.
func buy(index: int) -> bool:
	if index < 0 or index >= offered.size(): return false
	if not Army.can_buy(spent(), budget, String(offered[index])): return false
	counts[index] = int(counts[index]) + 1
	refresh()
	return true

## 0x443890 right click.
func sell(index: int) -> bool:
	if index < 0 or index >= offered.size() or int(counts[index]) < 1: return false
	counts[index] = int(counts[index]) - 1
	refresh()
	return true

func bought() -> Dictionary:
	var out := {}
	for i in offered.size():
		if int(counts[i]) > 0: out[String(offered[i])] = int(counts[i])
	return out

## 0x440e80 case 0x4b: ignored for the first second; the units go to the match (0x4406b0).
func finish(now_ms: int = -1) -> bool:
	if now_ms < 0: now_ms = Time.get_ticks_msec()
	if finished or now_ms < opened_ms + OKAY_DELAY_MS: return false
	finished = true
	setup.army = bought()
	setup.army_retinue = []
	for i in retinue.size():
		if bool(deployed[i]): setup.army_retinue.append(retinue[i].duplicate(true))
	if not Setup.pending.is_empty(): Setup.pending.setup = setup
	if is_inside_tree() and not "--self-test" in OS.get_cmdline_user_args():
		var scene := next_scene
		next_scene = null
		if scene != null: get_tree().change_scene_to_packed(scene)
		else: get_tree().change_scene_to_file("res://battle/main.tscn")
	return true

# ------------------------------------------------------------------------------------------------ drawing
## The pictures (image subtype 25, not traced): the unit's 90 x 90 portrait at the box's picture control.
func draw_overlay(node: Node2D):
	for entry in canvas.items():
		if String(entry.control.name) != "IM_RETINUE_PICTURE_RECRUIT" and String(entry.control.name) != "IM_RETINUE_PICTURE_ARMY": continue
		var code := ""
		var index := recruit_index("%s/BUTT_RETINUE_ARMY#" % entry.panel)
		if index >= 0: code = String(offered[index])
		elif String(entry.panel).begins_with("PNL_RETINUE_ARMY"):
			var r := int(String(entry.panel).trim_prefix("PNL_RETINUE_ARMY")) - 1
			if r >= 0 and r < retinue.size(): code = String(retinue[r].get("original_type_id", ""))
		var picture: Texture2D = ArtData.icon(code, 3) if code != "" else null
		if picture != null: node.draw_texture_rect(picture, Rect2(entry.rect), false)
	super.draw_overlay(node)

# ------------------------------------------------------------------------------------------------ self-test
var failed := false
var checks := 0

func check(condition: bool, text: String):
	checks += 1
	if not condition and not failed:
		failed = true
		push_error("Army setup check failed: " + text)

func self_test():
	var map: Dictionary = preload("res://core/map_data.gd").map()
	var test_setup := Setup.defaults(map)
	test_setup.players[0].kind = Setup.HUMAN
	Setup.set_race(test_setup, 0, 0)
	Setup.set_kind(test_setup, 1, Setup.COMPUTER)
	test_setup.army_budget = 10
	begin(test_setup, "")
	check(offered == ["AHBX", "AAEG", "AHKX", "AHMX", "AHFX", "AHDX", "AHEX"], "Knights offers (0x444980)")
	check(has_item(recruit_key(6)) and not has_item(recruit_key(7)), "one box per offer")
	check(item(recruit_key(3)).rect.position == Vector2i(93 + 2, 245 + 2), "box 4 at (93, 245) (0x6092c8)")
	check(canvas.control_text["PNL_RETINUE/STR_LARGE200#0"] == "0 / 10" and canvas.control_text["PNL_RETINUE/STR_SMALL_180#16"] == "Army Setup Points", "centre plate")
	check(canvas.control_text["PNL_RETINUE/STR_LARGE332#0"] == "Regular Troops" and canvas.control_text["PNL_RETINUE/STR_MEDIUM500#0"] == "Use Left Click to select units", "headers and help lines")
	check(canvas.control_text["PNL_RETINUE_RECRUIT5/STR_SMALL_180#0"] == "Knight", "unit name")
	check(click(recruit_key(4)) and canvas.control_text["PNL_RETINUE_RECRUIT5/STR_SMALL_180#0"] == "Knight (1)", "left click buys a Knight")
	check(canvas.control_text["PNL_RETINUE/STR_LARGE200#0"] == "3 / 10", "Knight costs 3 (ARM +0xca)")
	buy(0)
	buy(0)
	check(spent() == 5 and bought() == {"AHFX": 1, "AHBX": 2}, "Knight + 2 Peasants = 5 points")
	check(not buy(6) and spent() == 5, "a Knight Lord (6) does not fit with 5 of 10 spent")
	check(buy(5) and spent() == 9 and not buy(4), "Champion fits (9), another Knight does not")
	check(sell(5) and spent() == 5 and not sell(1), "right click takes one back; nothing to take back from an empty box")
	check(canvas.control_offset["PNL_RETINUE_RECRUIT1/IM_RETINUE_MEDAL#0"] == Vector2i(10000, 10000) and canvas.control_text["PNL_RETINUE_RECRUIT1/STR_MEDIUM30#1"] == "", "medals hidden, no cost text (0x442452)")
	# S-2: deploying the retinue for points (0x4427d0, 0x444940: cost + medal term).
	set_retinue([{"id": "r1", "original_type_id": "AHFX", "xp": 10, "medal_level": 9}, {"id": "r2", "original_type_id": "AHMX", "xp": 0, "medal_level": 0}])
	place("PNL_RETINUE_ARMY1", RETINUE_ROWS[0], 0x7e5)
	place("PNL_RETINUE_ARMY2", RETINUE_ROWS[1], 0x7e5)
	refresh()
	check(retinue_cost(0) == 6 and retinue_cost(1) == 2, "retinue cost = type cost + medal term (0x444940): %d %d" % [retinue_cost(0), retinue_cost(1)])
	check(not can_deploy(0) and can_deploy(1), "a box that does not fit is refused (5 of 10 spent)")
	check(not toggle_retinue(0) and click("PNL_RETINUE_ARMY2/BUTT_RETINUE_ARMY#1") and spent() == 7, "a click on a retinue box deploys it")
	check(toggle_retinue(1) and spent() == 5, "a second click takes it back (0xa245e8)")
	check(sell(0) and sell(0) and toggle_retinue(0) and spent() == 9 and sell(0) == false, "with the points free the unit deploys")
	check(not toggle_retinue(1), "no room for the second")
	check(toggle_retinue(0) and buy(0) and buy(0), "the Peasants are bought again")
	toggle_retinue(1)
	check(not finish(opened_ms + 500), "Okay ignored within the first second")
	check(finish(opened_ms + 1000) and setup.army == {"AHFX": 1, "AHBX": 2} and setup.army_retinue.size() == 1 and String(setup.army_retinue[0].id) == "r2", "Okay hands the units and the deployed retinue to the match")
	# 0x445200: the computer's purchase from the race table with the match generator.
	var Rng = preload("res://simulation/combat_rng.gd")
	var rng = Rng.new(12345, 6789)
	var units: Array = Army.computer_purchase(10, 0, 2, rng)
	check(units.size() >= 2 and units[0] == "AHBX", "the computer's first unit is the race's table entry 0 (Peasant)")
	check(Army.computer_purchase(0, 0, 2, rng).is_empty(), "no purchase below 1 point")
	var squire := Army.computer_purchase(1, 0, 1, rng)
	check(squire == ["AHBX"], "1 point: the first entry only")
	var cell: Vector2i = Army.placement_cell(Vector2i(12, 64), Vector2i(128, 128), rng)
	check(cell.x >= 8 and cell.x <= 17 and cell.y >= 60 and cell.y <= 69, "placement start + 1d10 - 5")
	check(Army.placement_cell(Vector2i(1, 127), Vector2i(128, 128), rng).x >= 5, "kept 5 cells inside")
	check(Army.human_budget(10, false, 3, [3]) == 10 and Army.human_budget(0, true, 1, [1]) == 0, "budget without handicap")
	check(Army.handicap_term(true, 2, [8]) == 7 and Army.handicap_term(true, 1, [40]) == 41 + 27 and Army.handicap_term(false, 1, [9]) == 0, "handicap table 0x603c9c")
	check(Army.human_budget(50, true, 1, [100]) == 100, "capped at 100 (0x440b40)")
	DirAccess.remove_absolute(help_flags_path())
	preload("res://simulation/game_settings.gd").use_file(preload("res://simulation/game_settings.gd").DEFAULT_PATH)
	if failed:
		get_tree().quit(1)
		return
	print("Army setup checks passed: %d" % checks)
	get_tree().quit()

func capture():
	var map: Dictionary = preload("res://core/map_data.gd").map()
	var test_setup := Setup.defaults(map)
	Setup.set_race(test_setup, 0, 0)
	test_setup.army_budget = 10
	begin(test_setup, "")
	buy(4)
	buy(0)
	buy(0)
	await capture_png("res://.local/army_setup.png")
	get_tree().quit()
