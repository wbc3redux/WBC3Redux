extends SceneTree
## Milestone 11-menus: the in-game interface of normal play in the real scene (main.tscn + game_hud.gd) on a copied
## profile and a copied settings file: the panel art, the command cells, game speed and pause (0x458dd0 / 0x429590), the
## game menu, the options dialog (persisted), resign and quit, scrolling, the strategic map and the harness debug key.
## Never touches user://heroes or user://settings.cfg.

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

const ArtData = preload("res://core/art_data.gd")
const AgentScript = preload("res://battle/unit_agent.gd")
const HudScript = preload("res://hud/game_hud.gd")
const DisplayConfig = preload("res://core/display.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Game HUD check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var settings_file := "user://game-hud-test-settings.cfg"
	DirAccess.remove_absolute(settings_file)
	Settings.use_file(settings_file)
	speed_rules()
	var directory := "user://game-hud-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	var profile = Profile.create("hud-knight", "Sir Panel")
	check(store.save_profile(profile), "copied test profile saved")
	root.size = Vector2i(1920, 1080)       # the normal-play window (headless defaults to 64x64)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "hud-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, 0)          # Knights vs Knights (the map's default races are Dwarf / The Swarm)
	scene.save_directory = directory                 # S-1: the match's saves and autosaves stay in the test folder
	check(scene.start_skirmish(setup, "hud-knight", store, "hud-match-1"), "match starts")
	await process_frame
	var hud = scene.hud
	check(hud != null and scene.normal_play and not scene.harness_panel.visible, "normal play: HUD shown, harness hidden")
	check(scene.after_results == "res://menus/front_end.tscn", "after the results: the main menu (0x440e80 / 0x454560)")
	for name in ["Panel_1600.bmp", "Panel_Buttons.bmp", "Panel_Icons.bmp", "Panel_Bars.bmp", "Panel_HeroDead.bmp", "ERIX", "ERNX", "EMDG", "EMDO", "EMDM", "EMDE", "EMDC", "Portrait00.bmp", "AHHXi", "BKK0i"]:
		check(hud.tex(name) != null, "panel art " + name)
	check(hud.tex("Panel_1600.bmp").get_size() == Vector2(1600, 189), "Panel_1600.bmp 1600x189")
	check(hud.cell_rect(4).position == Vector2(1049 + 8 + 43, 753 + 8 + 43 + hud.oy()), "command cell 4 at grid + 8 + 43 (0x4dcdf0)")
	# Selection -> command cells (0x4d2300 mode 3 icons).
	var hero = null
	for u in scene.units:
		if u.type_id == "AHHX" and u.owner_id == 0: hero = u
	hud.select_hero()
	check(hero != null and hero.selected and scene.view_rect().has_point(hero.position), "hero portrait selects and centres the hero")
	parity_checks(scene, hud, hero)
	pass3_checks(scene, hud, hero)
	pass4_checks(scene, hero)
	hud_pass_checks(scene, hud)
	q2_checks(scene, hud, hero)
	ui_gaps_checks(scene, hud)
	hud.select_hero()
	hud.refresh_cells()
	check(hud.cells.slice(0, 6).map(func(c): return int(c.get("icon", -1))) == [1, 2, 3, 4, 5, 21], "unit command icons 1, 2, 3, 4, 5, 21")
	# Milestone 12 (0x4d3200): a unit that passes 0x523af0 gets Convert (icon 6) in cell 6, before Build.
	check(int(hud.cells[6].get("icon", -1)) == 6 and hud.cells[6].enabled, "the hero gets the Convert cell (icon 6)")
	check(int(hud.cells[7].get("icon", -1)) == 8 and not hud.cells[7].enabled, "parity pass 4: the hero's Spellbook (icon 8, disabled without spells) after Convert (0x4d3200)")
	check(int(hud.cells[8].get("icon", -1)) == 0x1f and hud.cells[8].enabled, "parity pass 4: Build is the castle icon 0x1f in the last cell")
	var converting: bool = scene.convert_selected()
	check(converting or hud.message == scene.game_string(65, "?"), "Convert either starts or shows Game.txt [0065] on the message line")
	scene.player_message(scene.game_string(65, "?"))
	check(hud.message == "There is nothing here to convert...", "an original message reaches the control panel's message line")
	if converting: scene.cancel_conversion(hero)
	# Milestone 13: the build cell opens the construction dialog (the production dialog layout of 0x568290, row H0).
	check(hud.press_cell(8) and hud.dialog == "construct", "build cell opens the construction dialog")
	var keep: int = hud.dialog_items.map(func(c): return c.get("id", "")).find("BKK0")
	check(keep == 0 and hud.item_enabled(hud.dialog_items[keep]), "Keep is offered and affordable (300 each)")
	check(hud.dialog_items.map(func(c): return c.get("id", "")) == ["BKK0", "BAGA", "BPSM", "BPSB", "BPFL", "BPMA", "BAV0", "BPSS", "BPCA"], "the nine H0 buildings in order")
	check(hud.slot_at(Vector2(0x5f + 0x6b * 2 + 5, 0x3a + 0x6b + 5)) == 6, "slot hit areas of 0x568ff0 (four columns)")
	check(hud.press_item(keep) and scene.build_mode == "BKK0" and hud.dialog == "", "Keep arms the build placement")
	scene.build_mode = ""
	hud.refresh_cells()
	check(hud.press_cell(2) and scene.target_mode == 2, "Attack arms a target click (0x425150 mode 2)")
	hud.refresh_cells()
	check(int(hud.cells[0].get("icon", -1)) == 0x10 and hud.cells.slice(1).all(func(c): return c.is_empty()), "target page 6: only Cancel (icon 0x10)")
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	check(hud.handle_key(esc) and scene.target_mode == 0, "Esc presses Cancel (0x4d2290(1) then 0x10)")
	hud.refresh_cells()
	check(hud.press_cell(3) and scene.target_mode == 4, "Patrol arms mode 4")
	scene.target_mode = 0
	# Game speed and pause.
	check(hud.speed == 3 and is_equal_approx(scene.time_scale, 1.0), "match speed = GameSpeed + 1 (Medium)")
	hud.change_speed(1)
	check(hud.speed == 4 and is_equal_approx(scene.time_scale, 1.5), "'=': Fast, clock x 3/2")
	hud.change_speed(5)
	check(hud.speed == 5 and is_equal_approx(scene.time_scale, 2.0), "capped at Very Fast")
	hud.change_speed(-1)
	var audio = preload("res://core/audio_manager.gd").instance(self)
	var volume: int = audio.effects_volume
	hud.toggle_pause()
	check(hud.speed == 0 and scene.time_scale == 0.0 and audio.effects_volume == 0, "pause: clock and effects stop (0x429590)")
	var before: float = scene.simulation_time
	scene._physics_process(1.0 / 60.0)
	check(scene.simulation_time == before, "the simulation does not advance while paused")
	hud.change_speed(1)
	check(hud.speed == 0, "speed keys do nothing while paused")
	hud.toggle_pause()
	check(hud.speed == 4 and audio.effects_volume == volume, "resume restores speed and volume")
	scene._physics_process(1.0 / 60.0)
	check(is_equal_approx(scene.simulation_time - before, 1.5 / 60.0), "Fast advances 1.5x")
	# Keys (KeyMap.txt -> 0x427fb0).
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_G
	key.alt_pressed = true
	check(hud.handle_key(key) and hud.dialog == "menu", "Alt+G opens the game menu")
	# Game menu rows.
	check(not hud.menu_row_enabled(0) and hud.menu_row_enabled(1), "S-1: Load Game greyed (this hero has no saved game), Save Game enabled")
	check(hud.menu_row_at(Vector2(200, 0x54 + 10)) == -1 and hud.menu_row_at(Vector2(200, 0x9e + 10)) == 2, "row hit test (0x566020)")
	check(hud.menu_press(2) and hud.speed == 0 and hud.dialog == "", "Pause Game row pauses and closes")
	hud.toggle_pause()
	hud.open_dialog("menu")
	# Modern change: the game menu's Options opens the main menu's options screen over the paused match.
	var speed_before: int = hud.speed
	check(hud.menu_press(3) and hud.options_open() and hud.dialog == "" and hud.speed == 0, "Options row opens the options screen and pauses")
	await process_frame
	var options = hud.options_screen()
	check(options != null and options.in_game and options.has_item("PNL_GAMEOPTIONS/BUTT_GAMEOPTIONS_OPTION#3"), "the same screen as the main menu, with the Advanced tab")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(root.size) / 2.0
	var selected_before: Array = scene.selected_units()
	hud._input(click)
	check(scene.selected_units() == selected_before, "the control panel and the world get no input while it is open")
	check(options.click("PNL_GAMEOPTIONS/BUTT_CANCEL_STARTUP#0") and not hud.options_open() and hud.speed == speed_before, "Cancel closes it and resumes the match")
	hud.speed = 0
	hud.speed_before_pause = speed_before
	hud.open_options()
	await process_frame
	hud.options_screen().click("PNL_GAMEOPTIONS/BUTT_OKAY_STARTUP#0")
	check(not hud.options_open() and hud.speed == 0, "a match paused before stays paused")
	hud.toggle_pause()
	# The original in-game sheet (EMDO, 0x566c30) is kept for reference; it is no longer opened.
	hud.open_dialog("options")
	check(hud.option_cell_at(Vector2(67 + 61 * 4 + 5, 92 + 5)) == Vector2i(0, 4), "options cell hit test")
	check(hud.option_press(0, 4) and Settings.current().get_value("ScrollRate") == 5, "Scroll Rate V Fast")
	var reread = Settings.new()
	check(reread.load_from(settings_file) and reread.get_value("ScrollRate") == 5, "in-game options persist")
	check(hud.option_press(1, 1) and audio.effects_volume == 30, "SFX Low = 30, applied to the mixer")
	check(not hud.option_press(3, 2), "gamma is N/A")
	key.keycode = KEY_ESCAPE
	key.alt_pressed = false
	check(hud.handle_key(key) and hud.dialog == "", "Esc closes the dialog")
	# Scrolling and the strategic map.
	scene.centre_view(Vector2(1600, 1500))
	var at: Vector2 = scene.view_top_left()
	hud.scroll_by(Vector2(Settings.current().get_value("ScrollRate"), 0))
	check(scene.view_top_left() == at + Vector2(5 * 32, 0), "one 50 ms tick scrolls ScrollRate cells")
	hud.minimap_jump(Vector2(420 + 60, 756 + 40 + hud.oy()))
	check(scene.view_centre().distance_to(Vector2(60 * 32 + 16, 40 * 24 + 12)) < 0.01, "strategic map click centres the view on the cell")
	# 0x4907d0: the top-left stays inside [0, map - view - 1].
	hud.scroll_by(Vector2(-500, -500))
	check(scene.view_top_left() == Vector2.ZERO, "the view stops at the map's top-left corner")
	hud.scroll_by(Vector2(500, 500))
	var view: Vector2 = scene.view_world_size()
	check(scene.view_top_left().distance_to(Vector2(4096, 3072) - view - Vector2.ONE) < 0.01, "and at map - view - 1 (no black margin)")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	var zoom: Vector2 = scene.camera.zoom
	scene._unhandled_input(wheel)
	check(scene.camera.zoom == zoom and zoom == Vector2.ONE * hud.scale_factor, "no wheel zoom; the shared view scale (display.gd)")
	await native_resolution_checks(scene, hud)
	# Debug keys are fixture-only.
	key.keycode = KEY_F11
	scene._unhandled_input(key)
	check(not scene.harness_panel.visible, "F11 does nothing in normal play")
	key.keycode = KEY_O
	scene._unhandled_input(key)
	check(not scene.collision_overlay.visible, "O does nothing in normal play")
	# Quit dialog: No closes, Yes exits to Windows (headless: flagged only).
	hud.open_dialog("quit")
	check(hud.box_button_at(Vector2(150, 230)) == 0 and hud.box_button_at(Vector2(400, 230)) == 1, "message box buttons (0x55d400)")
	check(hud.box_press(0) and hud.dialog == "" and not hud.quit_requested, "No closes")
	hud.open_dialog("quit")
	check(hud.box_press(1) and hud.quit_requested and not scene.skirmish.over, "Yes exits (no results)")
	# Milestone 13: the building page (0x4d2300 mode 5) and the production dialog (0x568290); the Market's trade dialog.
	var keep_b = null
	for b in scene.production.buildings.values():
		if b.owner == scene.local_player and b.original_type_id == "BKK0" and not b.constructing: keep_b = b
	if keep_b == null and hero != null:              # the match starts with the hero only: place a finished Keep near it
		for dy in range(-12, 13, 3):
			if keep_b != null: break
			for dx in range(-12, 13, 3):
				var site: Vector2i = hero.cell + Vector2i(dx, dy)
				var placed: Dictionary = scene.production.can_place(scene.local_player, "BKK0", site)
				if placed.ok:
					keep_b = scene.production.add_completed(scene.local_player, "BKK0", int(placed.left), int(placed.top))
					break
	check(keep_b != null, "a finished Keep for the building page")
	if keep_b != null:
		for u in scene.units: u.selected = false
		scene.selected_building_id = keep_b.entity_id
		hud.refresh_cells()
		check(int(hud.cells[1].get("icon", -1)) == 7 and int(hud.cells[2].get("icon", -1)) == 19 and int(hud.cells[0].get("icon", -1)) == 1, "Keep page: Cancel 1, Production 7, Rally 19")
		# Issue 2: one rally line, the order-marker layer's entry (0x49d3b0 type 4); main.gd draws none of its own.
		var rally_before: Vector2i = keep_b.rally
		keep_b.rally = keep_b.cell_rect().position + Vector2i(6, 6)
		scene.update_order_marker()
		scene.arm_order_marker()
		scene.order_layer.refresh(Time.get_ticks_msec(), false)
		var rally_entries: Array = scene.order_layer.entries
		check(rally_entries.size() == 1 and int(rally_entries[0].type) == 4 and not bool(rally_entries[0].hidden),
			"issue 2: a selected own building with a rally point gives one line entry (%s)" % [rally_entries])
		check(not scene.has_method("draw_rally_line"), "issue 2: main.gd has no second rally line drawer")
		scene.order_layer.refresh(Time.get_ticks_msec() + 1000, false)
		check(scene.order_layer.entries.is_empty(), "issue 2: the line goes after the 500 ms show (0x49c150)")
		keep_b.rally = rally_before
		check(hud.press_cell(1) and hud.dialog == "production", "Production opens the production dialog")
		check(hud.dialog_items[0].get("id", "") == "BKK1" and hud.dialog_items[1].get("id", "") == "AHBX" and hud.dialog_items[4].get("id", "") == "PCR0", "Keep slots: upgrade 0, Peasant 1, Crusade 4 (PRODUCTION row order)")
		var before_jobs: bool = keep_b.has_job()
		check(hud.press_item(1) and keep_b.has_job() and not before_jobs, "a Peasant is ordered from the dialog")
		hud.close_dialog()
		finding_checks(scene, hud, keep_b)
	scene.production.research[scene.local_player] = ["PTRA"]
	var stock: Array = scene.economy.resources(scene.local_player)
	hud.open_market()
	hud.market_press(0)
	hud.market_press(4 + 1)
	hud.market_press(8)
	var gold_before: int = int(stock[0])
	hud.market_press(14)
	var after: Array = scene.economy.resources(scene.local_player)
	check(int(after[0]) == gold_before - mini(50, gold_before) and hud.dialog == "market", "trade 50 gold for metal at 50 %")
	hud.close_dialog()
	scene.production.research[scene.local_player] = []
	# Resign: a defeat with results (0x55ccd0 case 4).
	hud.open_dialog("resign")
	check(hud.box_press(1), "Yes resigns")
	for i in 20:
		scene._physics_process(1.0 / 60.0)
		if scene.skirmish.over: break
	check(scene.skirmish.over and not scene.skirmish.outcome.won and scene.results_layer != null and scene.results_layer.visible, "resign: defeat and the results screen")
	scene.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(settings_file)
	Settings.use_file(Settings.DEFAULT_PATH)
	if failures > 0:
		printerr("Game HUD checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Game HUD checks passed: %d" % checks)
	quit(0)

## Hand-test findings F7 (= F2), F8, F9 and F10 (HAND_TEST_FINDINGS.md): the skull over the strategic map, the production
## dialog's help rows, the info area's queue view and the Continuous Production box. `keep` has a Peasant running.
func finding_checks(scene, hud, keep):
	# F7: the ornament layer is transparent inside the box and keeps the skull's pixels (bitmap (540, 53) -> (120, 8)).
	var ornament: Texture2D = hud.minimap_ornament()
	check(ornament != null and ornament.get_size() == Vector2(128, 128), "F7: the map box's ornament layer is 128 x 128")
	if ornament != null:
		var image := ornament.get_image()
		check(image.get_pixel(10, 100).a == 0.0 and image.get_pixel(64, 64).a == 0.0, "F7: the box's black interior is transparent")
		check(image.get_pixel(120, 8).a == 1.0 and image.get_pixel(127, 25).a == 1.0, "F7: the skull's lower left is kept over the map")
	# F8: the description wraps in font 2 to 0x10c pixels and the rows stay inside the dialog's description box.
	var desc := "Increases army limit by 5 if it is your highest level Keep"
	var rows: Array = hud.help_rows(desc, "Requires: Nothing")
	var font: Dictionary = hud.canvas.font(2)
	var widest := 0.0
	for r in rows: widest = maxf(widest, font.font.get_string_size(String(r), HORIZONTAL_ALIGNMENT_LEFT, -1, font.size).x)
	check(rows.size() <= 3 and widest <= 0x10c, "F8: help rows are at most three, each within 0x10c pixels")
	check(String(rows[0]) != desc or rows[1] == "Requires: Nothing", "F8: a one-line description leaves row 2 to the requirements")
	var long_rows: Array = hud.help_rows(desc + " " + desc + " " + desc + " " + desc, "Requires: Nothing")
	check(long_rows.size() == 3 and not long_rows.has("Requires: Nothing"), "F8: three description lines fill every row (0x40aec0)")
	var two: Array = hud.help_rows("Word " .repeat(40).strip_edges().substr(0, 70), "Requires: A Keep and a very long list of other things")
	check(two.size() == 3 and two[2] == "Requires: A Keep and a very long list of other things", "F8: two description lines leave row 3 to the requirements as they are")
	var slot_right: int = hud.SLOT_ORIGIN.x + 3 * hud.SLOT_STEP + 90
	check(0xde + hud.HELP_WRAP <= slot_right and 0x116 - 4 >= hud.SLOT_ORIGIN.y + 2 * hud.SLOT_STEP, "F8: the text starts below the box's top and ends before its right frame")
	# F9: an own building with a job shows the queue view: six slots at most, "+ n" past five.
	check(hud.queue_view(keep), "F9: the Keep with a job shows the queue view")
	scene.economy.credit(scene.local_player, [5000, 0, 0, 0])
	for i in 6: scene.production.enqueue(keep.entity_id, "AHBX", scene.game_ms())
	check(keep.queue.size() == 5 and HudScript.queue_slots(keep).size() == 6 and HudScript.queue_more(keep) == 0, "F9: running job + five queued = six slots and '+ 0' (0x4db09b)")
	keep.queue.append("AHBX")
	keep.queue.append("AHBX")
	check(HudScript.queue_slots(keep).size() == 6 and HudScript.queue_more(keep) == 2, "F9: seven queued orders still draw six slots and '+ 2'")
	keep.queue.resize(5)
	var y: float = hud.oy()
	var slot3 := Vector2(hud.QUEUE_SLOT_X[3] + 10, hud.QUEUE_SLOT_Y + y + 10)
	check(hud.queue_hit(slot3, keep) == hud.HIT_SLOT + 3, "F9: a click on slot 3 hits order 3 (0x4d6790)")
	hud.panel_click(slot3)
	check(keep.queue.size() == 4, "F9: clicking a queued order cancels it (0x52d8a0)")
	check(hud.queue_hit(Vector2(1000, hud.QUEUE_SLOT_Y + y + 10), keep) == -1, "F9: no hit past the last drawn slot")
	# F10: the Continuous Production box flips the repeat flag; the Keep then keeps making Peasants.
	keep.queue.clear()
	var box: Vector2 = hud.REPEAT_BOX + Vector2(40, 7 + y)
	check(hud.queue_hit(box, keep) == hud.HIT_REPEAT, "F10: the label is inside the box's 0x80 x 0xe hit area")
	check(hud.game_text(523) == "Continuous Production", "F10: the box's label is Game.txt [0523]")
	check(not keep.repeat, "F10: repeat starts off")
	hud.panel_click(box)
	check(keep.repeat, "F10: a click sets the repeat flag (+0x190)")
	var peasants := func() -> int: return scene.units.filter(func(u): return u.type_id == "AHBX" and u.owner_id == scene.local_player and not u.removed).size()
	var before: int = peasants.call()
	var seconds: float = scene.production.time_of(scene.local_player, "AHBX") / 1000.0 + 0.1
	for i in 3:
		scene.simulation_time += seconds
		scene.production.update(scene.game_ms())
	check(peasants.call() >= before + 3 and keep.job_item == "AHBX", "F10: with repeat on the Keep makes Peasant after Peasant (0x52cb04)")
	hud.panel_click(box)
	check(not keep.repeat, "F10: a second click clears it")
	scene.simulation_time += seconds
	scene.production.update(scene.game_ms())
	check(not keep.has_job(), "F10: with repeat off the last order is the last Peasant")

## Parity pass 3 (UI_RESEARCH.md "Parity pass 3"): the resource boxes and army counter, the dialog place, the build
## Native resolution (DELIBERATE MODERN CHANGE, display.gd): the shared scale, the bars, the centred panel, the view.
func native_resolution_checks(scene, hud):
	check(DisplayConfig.auto_scale(Vector2(1920, 1080)) == 1.0 and DisplayConfig.auto_scale(Vector2(1366, 768)) == 1.0, "auto scale 1 up to 1080 rows")
	check(DisplayConfig.auto_scale(Vector2(2560, 1440)) == 1.5 and DisplayConfig.auto_scale(Vector2(3840, 2160)) == 2.0, "auto scale 1.5 at 1440, 2 at 2160")
	check(DisplayConfig.view_bars(Vector2(1920, 1080), 1.0) == 0.0, "no bars at 1920 wide (widescreen cap)")
	check(DisplayConfig.view_bars(Vector2(3440, 1440), 1.5) == 280.0, "3440x1440: 280-pixel bars at the widescreen cap")
	check(DisplayConfig.menu_rect(Vector2(1920, 1080), Vector2(800, 600)) == Rect2(240, 0, 1440, 1080), "4:3 screens fitted to 1080")
	for size in [Vector2i(2560, 1440), Vector2i(1366, 768), Vector2i(3440, 1440), Vector2i(1920, 1080)]:
		root.size = size
		await process_frame
		var s: float = hud.scale_factor
		check(scene.camera.zoom == Vector2.ONE * s, "%s: camera at the shared scale %s" % [size, s])
		check(is_equal_approx(hud.to_virtual(Vector2(hud.panel_x * s, 0) + hud.GRID * s + Vector2(0, hud.oy() * s)).x, hud.GRID.x), "%s: panel points map back" % size)
		check(hud.over_panel(hud.to_virtual(Vector2(size.x / 2.0, size.y - 10))) and not hud.over_panel(hud.to_virtual(Vector2(size.x / 2.0, 10))), "%s: panel at the bottom" % size)
		var view: Vector2 = scene.view_world_size()
		check(view.y <= DisplayConfig.VIEW_HEIGHT + 0.5 and view.x <= DisplayConfig.VIEW_WIDTHS[1] + 0.5, "%s: world view %s inside the cap" % [size, view])
		scene.set_view_top_left(Vector2(9999, 9999))
		check(scene.view_rect().end.distance_to(Vector2(4096, 3072) - Vector2.ONE) < 0.01, "%s: view clamped at the map's corner" % size)

## dialog's art and prices, the unit info rows, the conversion block and the order marker, the map towers' art.
func pass3_checks(scene, hud, hero):
	check(hud.RESOURCE_BOX == [Vector2(1375, 5), Vector2(1430, 5), Vector2(1485, 5), Vector2(1540, 5)], "resource boxes at the 1600 table 0x60e2a8")
	check(hud.ARMY_BOX == Vector2(5, 5) and hud.tex("ERIX").get_size() == Vector2(60, 320), "army counter box ERIX frame 8 at (5, 5)")
	var pop: Dictionary = scene.production.population(scene.local_player)
	check(int(pop.current) == 0 and int(pop.maximum) > 0, "army counter values 0 / limit at the start: %s" % pop)
	# Dialogs: inside the view above the panel for 1009- and 1080-high windows (the user's desktop is 1920x1009).
	for window_h in [1009.0, 1080.0, 1200.0]:
		var view_h: float = hud.PANEL_TOP + (window_h / DisplayConfig.view_scale(Vector2(1920, window_h)) - 900.0)
		for key in ["production", "menu", "options", "box", "market"]:
			var at: Vector2 = HudScript.dialog_place(hud.DIALOG_AT[key], int(hud.DIALOG_HEIGHT[key]), view_h)
			check(at.y >= 0.0 and at.y + float(hud.DIALOG_HEIGHT[key]) <= view_h + 0.5, "%s dialog inside the view at %d: %s" % [key, window_h, at])
	check(HudScript.dialog_place(Vector2(880, 290), 450, 1050.0) == Vector2(880, 290), "the 1600x1200 place is kept on a 1050-high view")
	# The build dialog's cells: every Knights construction item and a Dwarf building have their 'i' picture.
	for id in scene.production.construction_menu(scene.local_player) + ["BKD0", "BAAR", "BWTC"]:
		check(hud.icon_sheet(String(id)) != null, "build dialog picture for " + String(id))
	check(HudScript.PRICE_FRAME == [4, 6, 7, 5] and HudScript.PRICE_ORDER == [2, 3, 1, 0], "prices: ERIX frames per lane, crystal first (0x569450)")
	check(HudScript.bonus_text(20, 20) == "20" and HudScript.bonus_text(20, 23) == "20 +3" and HudScript.bonus_text(20, 18) == "20 -2", "0x4ddeb0 formats")
	# The hero's conversion: the block sits under Combat / Hits (base = top + 0x2c) and the marker shows over the hero.
	for u in scene.units: u.selected = u == hero
	check(scene.convert_selected(0) or true, "convert order given (nothing in reach is allowed)")
	if scene.conversions.converting(hero.unit_id):
		scene.order_marker_until_ms = 0      # P-2: an earlier move of this test armed the 500 ms show (0x49c150), now ported
		scene.update_order_marker()
		check(AgentScript.marker_unit == -1, "parity pass 4: no marker after Convert without Shift / Alt (0x49c150 follows moves only)")
		scene.order_marker_until_ms = Time.get_ticks_msec() + 500     # as after a right-click move (0x530870 -> 0x49c150)
		scene.update_order_marker()
		check(AgentScript.marker_unit == hero.unit_id and AgentScript.marker_type == 7, "the conversion marker shows while the 500 ms window runs (0x49c240)")
		scene.order_marker_until_ms = 0
		scene.cancel_conversion(hero)
	check([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15].map(func(p): return AgentScript.marker_row(p)) == [0, 0, 0, 1, 2, 2, 1, 0, 0, 0, 1, 2, 2, 1, 0, 0], "marker rows by phase (0x49c240)")
	# Map towers drawn as the Knight Tower after the race swap; their art and the Knights roster's are imported.
	var drawn := []
	for o in scene.map_objects:
		if o.is_building and o.code.begins_with("BWT"): drawn.append(o.code)
	check(drawn == ["BWTC", "BWTC", "BWTC", "BWTC"], "map tower placements drawn as Knight Towers: %s" % [drawn])
	for code in ["BWTC", "BPSM", "BPCA", "BKK4", "BWG0"]:
		check(not ArtData.building_sheet(code, 0).is_empty(), "world art for " + code)
	for code in ["AHFX", "AHEX", "AAPE", "AADR"]:
		check(ArtData.has_unit(code), "world art for " + code)
	check(not ArtData.data().effects.get("EZ01", {}).is_empty(), "EZ01 conversion flash imported")

## Parity pass 4: the world ring tables (0x611b0c.., 0x538660 / 0x53b014) and the inputs main.gd sets.
func pass4_checks(scene, hero):
	check(AgentScript.ring_source(0, true, 8) == Rect2(330, 408, 44, 33) and AgentScript.ring_source(1, true, 8) == Rect2(330, 441, 65, 49), "hero rings: rank 8 = the yellow rings")
	check(AgentScript.ring_source(0, true, 0) == Rect2(0, 0, 44, 33) and AgentScript.ring_source(0, false, 8) == Rect2(218, 0, 44, 33), "own green / other red, no rank on red rings")
	check(AgentScript.ring_source(2, true, 8) == Rect2(0, 82, 97, 73) and AgentScript.ring_source(5, false) == Rect2(422, 228, 300, 228), "rank only for sizes 0 / 1; size 5 the big rings")
	var words: Dictionary = AgentScript.ring_words(ArtData.unit_sheet("AHHX", 0))
	check(int(words.size) == 0 and words.offset == Vector2(20, 15), "AHHX slot 0: ring size word +0x14 = 0, offset words +0x10 / +0x12 = (20, 15): %s" % words)
	check(int(AgentScript.ring_words(ArtData.building_sheet("BKK0", 0)).size) == 5, "the Keep's ring is size 5")
	check(AgentScript.mana_level_of(0, 0) == -1 and AgentScript.mana_level_of(1, 20) == 0 and AgentScript.mana_level_of(20, 20) == 7 and AgentScript.mana_level_of(30, 20) == 7, "0x51b2c0 mana levels")
	for u in scene.units: u.selected = u == hero
	scene.update_order_marker()
	check(hero.ring_rank == 8, "the selected hero takes rank 8 (+0xb4)")
	scene.assign_group(3)
	scene.update_order_marker()
	check(hero.group_digit == 3, "the hero in group 3 shows digit 3 (0x425470, SkillIcons 0x141)")
	scene.control_groups.erase(3)
	for u in scene.units: u.selected = false
	scene.update_order_marker()

## 0x458dd0 integer rules and the option tables.
func speed_rules():
	check(Settings.scaled_ms(25, 1) == 12 and Settings.scaled_ms(25, 2) == 18 and Settings.scaled_ms(25, 3) == 25, "1/2, 3/4 (truncated), 1")
	check(Settings.scaled_ms(25, 4) == 37 and Settings.scaled_ms(25, 5) == 50 and Settings.scaled_ms(25, 0) == 0, "3/2, 2, paused")
	check([0, 1, 30, 31, 60, 61, 90, 91, 120].map(func(v): return Settings.sfx_level(v)) == [0, 1, 1, 2, 2, 3, 3, 4, 4], "SFX label thresholds (0x4101e0)")
	var s = Settings.new()
	check(s.get_value("GameSpeed") == 2 and s.get_value("ScrollRate") == 3 and s.get_value("OverallVolume") == 120 and s.get_value("MusicVolume") == 3, "defaults (0x453280)")
	s.set_value("ScrollRate", 9)
	check(s.get_value("ScrollRate") == 5, "values are clamped to the dropdown range")
	for page in 3:
		check(Settings.page_rows(page).size() == 10, "ten droplists on page %d" % page)

## Parity pass 1 (UI_RESEARCH.md "Parity pass 1"): cursors, selection rules, keys, groups, grid dispatch, target modes.
func parity_checks(scene, hud, hero):
	const Selection = preload("res://battle/selection.gd")
	const UnitAgent = preload("res://battle/unit_agent.gd")
	# --- the cursor records and 0x46c9b0 frame timing
	var cur = scene.cursor
	check(cur != null and cur.records.size() == 16 and cur.sheet != null, "16 cursor records and Cursors.bmp loaded")
	cur.set_index(7)
	var t0: int = cur.deadline - 1000
	check(cur.frame == 0 and cur.frame_rect() == Rect2i(128, 0, 32, 32) and cur.hotspot() == Vector2i(16, 16), "CURS_FIGHT frame 0 (128, 0), hotspot 16,16")
	cur.advance(t0 + 999)
	check(cur.frame == 0, "frame 0 holds 1000 ms")
	cur.advance(t0 + 1000)
	check(cur.frame == 1 and cur.frame_rect().position == Vector2i(160, 0), "then frame 1 (50 ms)")
	cur.set_index(1)
	cur.advance(t0 + 100000)
	check(cur.index == 1 and cur.frame == 0 and cur.deadline == -1, "CURS_ARROW: delay 0 holds")
	cur.set_index(99)
	check(cur.index == 1, "an index without a record is ignored (0x46c190)")
	# --- the cursor context function 0x420390 / 0x41ee80
	var own_unit := {"head": "unit", "head_own": true}
	var cases := [
		[{"panel": true}, 2, "panel: pointer"], [{"panel": true, "pressed": true}, 3, "panel pressed"],
		[{"mode": 1}, 8, "Move mode: walk"], [{"mode": 2}, 7, "Attack mode: fight"], [{"mode": 4}, 9, "Patrol mode"],
		[{"mode": 5}, 14, "Guard mode"], [{"mode": 7}, 6, "rally mode: select"], [{"mode": 8}, 1, "placement: arrow"],
		[{"dragging": true}, 1, "box drag: arrow"], [{}, 1, "nothing selected: arrow"],
		[own_unit, 8, "own unit over ground: walk"],
		[own_unit.merged({"hover": "unit"}), 7, "own unit over an enemy: fight"],
		[own_unit.merged({"hover": "unit", "hover_allied": true}), 6, "over an ally: select"],
		[own_unit.merged({"hover": "unit", "hover_own": true}), 6, "over an own unit: select"],
		[own_unit.merged({"hover": "building", "hover_own": true, "hover_enter": true}), 13, "builder over an unfinished own site: resume"],
		[own_unit.merged({"hover": "unit", "hover_flying": true, "hits_air": false}), 6, "cannot hit a flyer: select"],
		[own_unit.merged({"hover": "building", "hover_fogged": true}), 7, "remembered enemy building in fog: fight"],
		[{"head": "building", "head_own": true, "hover": "unit"}, 6, "building head over an enemy: select"],
		[{"head": "tower", "head_own": true, "hover": "unit"}, 7, "tower head over an enemy: fight"],
		[{"head": "unit", "head_own": false}, 1, "enemy selected: arrow"],
		[own_unit.merged({"head_hero": true, "pickup": true}), 12, "hero over a pickup: ruin cursor"]]
	for c in cases: check(Selection.cursor_index(c[0]) == c[1], "cursor: " + c[2])
	# G-4: a "tower" head is a building with BUI damage (+0x38) above 0 (0x420390 reads 0x69778c).
	var cat: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalogue.json")).get("buildings", {})
	if cat.has("BWTA") and cat.has("BKH0"):
		check(Selection.tower_head(String(cat.BWTA.raw_hex)) and not Selection.tower_head(String(cat.BKH0.raw_hex)), "G-4: BWTA is a tower head (BUI damage 35), the Keep BKH0 is not")
	check(not Selection.tower_head(""), "G-4: no record, no tower head")
	# G-4: the tower view's fifth row (Range) ends inside the info panel at 1600 x 900 (title 10 px above the name row).
	var last_row_bottom: float = HudScript.BUILDING_NAME_AT.y - 0xa + 0x14 + 0x12 * 4 - 4 + 16
	check(last_row_bottom <= HudScript.INFO.end.y - 8, "G-4: the Range row ends %d px above the info area's bottom" % int(HudScript.INFO.end.y - last_row_bottom))
	# --- 0x5319f0 / 0x531c90 on loose units (not in the scene)
	var loose: Array = []
	for i in 40:
		var u = UnitAgent.new()
		u.unit_id = 1000 + i
		u.position = Vector2(100 + 50 * (i % 10), 100 + 70 * (i / 10))
		u.cell = Vector2i(3 + i % 10, 4 + i / 10)
		loose.append(u)
	var everything := Rect2(0, 0, 2000, 2000)
	check(Selection.select_box(loose, everything, 0) == 32 and Selection.selected_count(loose) == 32, "a box selects at most 32 own units")
	check(loose[0].selected and loose[31].selected and not loose[32].selected, "in the own list's order")
	loose[39].owner_id = 1
	Selection.clear(loose)
	for i in 30: loose[i].selected = true
	check(Selection.add_box(loose, everything, 0) == 2 and Selection.selected_count(loose) == 32, "Shift adds while fewer than 32 are selected")
	check(not loose[39].selected, "an enemy unit is never box selected")
	for i in 9: loose[i].extent = 2
	check(Selection.select_box(loose, everything, 0) == 32 and Selection.selected_count(loose) == 8, "weight 4 per 2x2 unit: 8 fit under 32")
	for i in 9: loose[i].extent = 1
	loose[5].flying = true
	Selection.select_box(loose, Rect2(0, 0, 2000, 110), 0, 2)
	check(Selection.selected_count(loose) == 1 and loose[5].selected, "Alt box: flying units only (mode 2)")
	Selection.select_box(loose, Rect2(0, 0, 2000, 110), 0, 1)
	check(Selection.selected_count(loose) == 9 and not loose[5].selected, "Ctrl box: ground units only (mode 1)")
	check(not Selection.is_box(Vector2(10, 10), Vector2(13, 13)) and Selection.is_box(Vector2(10, 10), Vector2(14, 10)), "a box needs more than 3 px (0x421409)")
	var near := Selection.select_nearest(loose, 0, Vector2i(3, 4), Rect2i())
	check(near == 32 and loose[0].selected and not loose[38].selected, "Ctrl+A: the 32 own units nearest the view centre (0x548ee0)")
	check(Selection.select_type_in(loose, "AHKX", everything, 0) == 32, "same-class selection is capped at 32 (0x531dd0)")
	for u in loose: u.free()
	# --- scene selection: clicks, own-only box, enemy for information only
	var helper_cell: Vector2i = scene.navigator.free_cell_near(hero.cell + Vector2i(3, 0))
	var helper = scene.add_unit("AHKX", helper_cell, 0)
	var foe_cell: Vector2i = scene.navigator.free_cell_near(hero.cell + Vector2i(0, 4))
	var foe = scene.add_unit("AHKX", foe_cell, 1)
	foe.visible = true
	scene.visibility_force_sweep()          # the cells around the hero become explored (hover_object reads them)
	foe.visible = true
	var none := {"ctrl": false, "shift": false, "alt": false}
	scene.last_click_object = null
	scene.click_release(hero.position, none)
	check(hero.selected and scene.own_selected().size() == 1, "a click selects the own unit")
	scene.click_release(helper.position, none.merged({"shift": true}, true))
	check(hero.selected and helper.selected, "Shift-click adds (command 0x13)")
	scene.click_release(foe.position, none)
	check(foe.selected and not hero.selected and scene.own_selected().is_empty(), "a click on an enemy selects it for information")
	var queued: int = foe.orders.size()
	scene.issue_move(foe.position + Vector2(64, 0))
	check(foe.orders.size() == queued, "an enemy selected for information takes no orders")
	scene.box_release(Rect2(hero.position - Vector2(300, 300), Vector2(600, 600)), none)
	check(hero.selected and helper.selected and not foe.selected, "a box selects own units only")
	scene.last_click_object = null
	scene.click_release(helper.position, none)
	scene.click_release(helper.position, none)
	check(helper.selected and not hero.selected, "a second click within 8 ticks selects the same class in the view")
	# --- grid dispatch by icon id (0x4d2290) and the KeyMap keys
	scene.pick_object(hero)
	var k := InputEventKey.new()
	k.pressed = true
	for pair in [[KEY_V, 1], [KEY_A, 2], [KEY_P, 4], [KEY_G, 5]]:
		k.keycode = pair[0]
		check(hud.handle_key(k) and scene.target_mode == pair[1], "key %s presses its grid icon (mode %d)" % [OS.get_keycode_string(pair[0]), pair[1]])
		scene.target_mode = 0
	check(hud.icon_tip(5) == "Guard (g)" and hud.icon_tip(0x15) == "Attitude", "tooltips by icon (0x414ef0): Guard [0141], Attitude [0071]")
	Selection.add(helper)
	hud.refresh_cells()
	check(int(hud.cells[1].get("icon", -1)) == 0x12, "several units: Formations replaces Move (0x4d2300 mode 4)")
	check(not hud.press_icon(2), "v does nothing for a group (no Move cell)")
	k.keycode = KEY_F
	check(hud.handle_key(k) and hud.page == "formations", "f opens the formations page")
	hud.refresh_cells()
	check(int(hud.cells[0].icon) == 0x22 and int(hud.cells[8].icon) == 0x10, "formations 0x22..0x29 and Cancel")
	check(hud.press_icon(0x10) and hud.page == "units", "Cancel returns")
	k.keycode = KEY_KP_7
	check(hud.handle_key(k) and scene.own_selected().all(func(u): return u.orders.is_empty()), "numpad 7 presses cell 0 (Stop)")
	# --- control groups (0x425510 / 0x425700 / 0x4255f0)
	k.keycode = KEY_3
	k.ctrl_pressed = true
	hud.handle_key(k)
	k.ctrl_pressed = false
	scene.pick_object(foe)
	hud.handle_key(k)
	check(hero.selected and helper.selected and not foe.selected, "3 recalls the group stored by Ctrl+3")
	scene.centre_view(Vector2(3000, 2500))
	hud.handle_key(k)
	check(hero.selected and helper.selected and scene.view_rect().has_point(hero.position), "3 again centres on the group")
	# --- Ctrl+A own only, Ctrl+H, backtick, Home
	k.keycode = KEY_A
	k.ctrl_pressed = true
	hud.handle_key(k)
	check(not foe.selected and hero.selected, "Ctrl+A selects own units only")
	k.keycode = KEY_H
	hud.handle_key(k)
	check(hero.selected and scene.own_selected().size() == 1, "Ctrl+H selects the hero")
	k.ctrl_pressed = false
	scene.centre_view(Vector2(3000, 2500))
	k.keycode = KEY_QUOTELEFT
	check(hud.handle_key(k) and scene.view_rect().has_point(hero.position), "` centres on the selection head")
	# --- Tab cycles production buildings; alerts
	check(not scene.cycle_building(true, false) or scene.selected_building() != null, "Tab selects a production building when there is one")
	scene.pick_object(hero)
	scene.alerts = []
	scene.push_alert(Vector2i(10, 10))
	scene.push_alert(Vector2i(100, 100))
	check(scene.alert_jump() and scene.view_rect().has_point(Vector2(100 * 32 + 16, 100 * 24 + 12)), "alert key: the newest alert")
	check(scene.alert_jump() and scene.view_rect().has_point(Vector2(10 * 32 + 16, 10 * 24 + 12)), "again within 2 s: the next")
	# --- Patrol and Guard
	scene.arm_target(4)
	scene.target_click(hero.position + Vector2(200, 0), none.merged({"shift": true}, true))
	check(scene.target_mode == 4 and scene.patrol_points.size() == 1, "Shift-click adds a patrol point")
	scene.target_click(hero.position + Vector2(200, 100), none)
	check(scene.target_mode == 0 and scene.patrols.has(hero.unit_id) and scene.patrols[hero.unit_id].points.size() == 3, "the patrol: start + 2 points")
	scene.arm_target(5)
	scene.target_click(hero.position + Vector2(-300, -200), none)
	check(scene.target_mode == 5, "Guard ignores a ground click")
	scene.target_click(helper.position, none)
	check(scene.target_mode == 0 and scene.guards.get(hero.unit_id, {}).get("id", -1) == helper.unit_id and not scene.patrols.has(hero.unit_id), "Guard takes the clicked unit")
	scene.target_mode = 0
	scene.stop_selected()
	check(not scene.guards.has(hero.unit_id), "Stop clears guard and patrol")
	# --- right-click on ground moves; Alt+H cycles the help level
	scene.right_click(hero.position + Vector2(96, 0), none)
	check(not hero.orders.is_empty(), "right-click on ground moves the selection")
	var help: int = hud.settings.get_value("HelpLevel")
	k.keycode = KEY_H
	k.alt_pressed = true
	hud.handle_key(k)
	k.alt_pressed = false
	check(hud.settings.get_value("HelpLevel") == (help + 1) % 3 and hud.message == hud.game_text(67 + (help + 1) % 3), "Alt+H cycles Popup Help with its message")
	hud.settings.set_value("HelpLevel", 0)
	check(hud.icon_tip(1) == "", "no tooltips at HelpLevel 0")
	hud.settings.set_value("HelpLevel", help)
	check(UnitAgent.health_row(100, 100) == 0 and UnitAgent.health_row(0, 100) == 15 and UnitAgent.health_row(50, 100) == 8, "health strip rows (0x4d7710)")
	hero.stop()
	for u in [helper, foe]:
		u.selected = false
		var fu = scene.combat.fighters.get(u.unit_id)
		if fu != null: scene.combat.apply_damage("unit", u.unit_id, int(fu.hp) + 1, -1)
	scene.pick_object(hero)

## HUD pass (UI_RESEARCH.md "HUD pass"): the round buttons (0x4d6620 / 0x4d6790, released 0x4d5d10), Diplomacy (0x558810:
## hit areas 0x558e20, Send 0x559690), the spellbook rule (0x40c6b0 / 0x4cde10), the quest key, the inventory toggle and
## the info area's text width.
func hud_pass_checks(scene, hud):
	for kind in hud.ROUND:
		var r: Rect2 = hud.ROUND[kind]
		check(hud.round_at(r.get_center() + Vector2(0, hud.oy())) == kind, "round button hit: " + kind)
	check(hud.round_at(Vector2(800, 100)) == "", "no round button in the view")
	for name in ["EMDA", "ESHD", "EMDS", "EMDQ", "Panel_Menu.bmp"]: check(hud.tex(name) != null, "HUD pass art " + name)
	# A press and a release over the Game Menu skull open the menu (the release acts, 0x4d5d10).
	var panel_x: float = float(hud.get("panel_x")) if "panel_x" in hud else 0.0      # a centred panel (native resolution)
	var at: Vector2 = (hud.ROUND.menu.get_center() + Vector2(panel_x, hud.oy())) * hud.scale_factor
	check(hud.round_at(hud.to_virtual(at)) == "menu", "the screen point maps back to the Game Menu button")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = at
	click.pressed = true
	hud._input(click)
	check(hud.dialog == "" and hud.round_down == "menu", "the press arms the Game Menu button")
	click.pressed = false
	hud._input(click)
	check(hud.dialog == "menu" and hud.round_down == "", "the release opens the Game Menu (0x29 -> 0x4d3080)")
	hud.close_dialog()
	# Diplomacy: Alt+D, the hit areas and Send.
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_D
	key.alt_pressed = true
	check(hud.handle_key(key) and hud.dialog == "diplomacy", "Alt+D opens Diplomacy")
	check(hud.diplomacy_players() == [1], "Diplomacy lists the other active player")
	check(hud.diplomacy_hit(Vector2(0x60, 0x81 + 0x1b + 10)) == 1 and hud.diplomacy_hit(Vector2(0xa0, 0x79 + 10)) == 6, "amount 100 and the gold cart (0x558e20)")
	check(hud.diplomacy_hit(Vector2(0x100, 0x6b + 0x23 + 10)) == 11 and hud.diplomacy_hit(Vector2(0x100, 0x6b + 10)) == -1, "player 1's row; the local player's row is empty")
	check(hud.diplomacy_hit(Vector2(0x100, 0x160)) == 16 and hud.diplomacy_hit(Vector2(0xd0, 0x175)) == 17, "Send and close")
	var mine: Array = scene.economy.resources(0)
	var theirs: Array = scene.economy.resources(1)
	check(not hud.send_resources(), "Send needs an amount, a resource and a player")
	hud.diplomacy_press(1)
	hud.diplomacy_press(6)
	hud.diplomacy_press(11)
	check(hud.diplomacy_press(16) and bool(hud.diplomacy.sent) and int(hud.diplomacy.amount) == -1, "Send clears the choices and reports Resources Sent")
	check(int(scene.economy.resources(0)[0]) == int(mine[0]) - 100, "100 gold leave the sender")
	check(int(scene.economy.resources(1)[0]) == mini(int(theirs[0]) + 100, int(scene.economy.capacity(1)[0])), "the receiver gets them (capped)")
	hud.diplomacy_press(5)
	hud.diplomacy_press(9)
	hud.diplomacy_press(11)
	var crystal: int = int(scene.economy.resources(0)[2])
	check(crystal >= 500 or not hud.send_resources(), "500 crystal cannot be sent without the stock")
	hud.close_dialog()
	# Spellbook: school level L knows the school's first L spells; the default Knight Warrior knows none.
	var levels := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0]
	check(HudScript.spell_known(levels, 112) and not HudScript.spell_known(levels, 113) and not HudScript.spell_known(levels, 0), "0x40c6b0: Divination 3 knows spells 110..112")
	check(not hud.hero_knows_spells() and not hud.press_round("spellbook") and hud.dialog == "", "no spellbook without a known spell (0x4cde10)")
	var names: Array = hud.canvas.layout.get("spells", {}).get("spells", [])
	check(names.size() == 130 and String(names[0].name) == "Heal Self", "Spells.txt: 130 spells, Heal Self first")
	# Quest (q): a message without a quest, the dialog with one.
	key.alt_pressed = false
	key.keycode = KEY_Q
	scene.encounters.quests.erase(0)
	check(hud.handle_key(key) and hud.dialog == "" and hud.message == hud.game_text(187), "q without a quest: Game.txt [0187]")
	scene.encounters.quests[0] = {"record": scene.encounters.quest_records()[0], "building": -1, "progress": 0, "deadline_ms": 0}
	check(hud.handle_key(key) and hud.dialog == "quest", "q opens the current quest")
	hud.close_dialog()
	scene.encounters.quests.erase(0)
	# Inventory (0x55e0e0): with a hero the first press opens the dialog, the second closes it.
	var has_hero: bool = scene.hero_match != null and scene.hero_match.profile != null
	check(hud.press_round("inventory") and (hud.dialog == "inventory") == has_hero, "Inventory opens the inventory dialog when there is a hero")
	check(hud.press_round("inventory") and hud.dialog == "" and scene.inventory.is_empty(), "a second press closes it")
	# Info area text ends before the panel's right horn and skull.
	check(HudScript.info_right_edge(1066.0 - 300.0) < 982.0 and HudScript.info_right_edge(1120.0 - 300.0) <= 1019.0, "info text ends before the horn")
	check(hud.fitted("WWWWWWWWWWWWWWWWWWW", 5, 120.0).ends_with("..."), "a long name is cut with ...")

## Q-2 (QUESTS_RESEARCH.md "Q-2"): the quest dialog of 0x56a150 as 0x56aff0 draws it, its hit areas (0x56a840) and Enter
## (0x56abe0), and cursor 0xc over a quest site (0x420390).
func q2_checks(scene, hud, hero):
	var portrait: Texture2D = hud.tex("quest_DWF0")
	check(portrait != null and portrait.get_size() == Vector2(128, 160), "Q-2: Quest.xcr portrait DWF0 imported at 128 x 160")
	check(hud.tex("EMDE") != null and hud.tex("EMDE").get_size() == Vector2(180, 144), "Q-2: the Okay button sheet EMDE (four 36-row frames)")
	var words := []
	for i in 120: words.append("word%d" % (i % 10))
	var lines: Array = hud.quest_lines(" ".join(words), 0x13)
	check(lines.size() == 13, "Q-2: a long text fills the thirteen line slots")
	var placed := true
	for n in lines.size():
		var want_x := 0xd9 if n < 9 else 0x46
		placed = placed and int(lines[n].y) == 72 + 20 * n and (int(lines[n].x) == want_x or (n == 9 and int(lines[n].x) == 0xd9))
	check(placed, "Q-2: lines 0..8 at x 0xd9, 9..12 at x 0x46, y 72 + 20 n (table 0x6152a8 / 0x6152dc)")
	var short: Array = hud.quest_lines("one two three", 0x13)
	check(short.size() == 1 and String(short[0].text) == "one two three" and int(short[0].x) == 0xd9 and int(short[0].y) == 72, "Q-2: a short text is one line at (0xd9, 72)")
	# The site dialog: hit areas and modes.
	var site: int = -1
	for id in scene.encounters.givers: site = int(id)
	check(site >= 0, "Q-2: the map has a quest site")
	var record: Dictionary = scene.encounters.quest_records("BZMA")[0]
	hud.open_quest_offer({"building": site, "mode": "offer", "record": record})
	check(hud.quest_hover_at(Vector2(0x4f + 5, 0x159 + 5)) == hud.QUEST_HOVER_CLOSE, "Q-2: close at (0x4f, 0x159)")
	check(hud.quest_hover_at(Vector2(0x9c + 5, 0x155 + 5)) == hud.QUEST_HOVER_OKAY and hud.quest_hover_at(Vector2(0x14f, 0x178)) == hud.QUEST_HOVER_OKAY, "Q-2: Okay spans (0x9c..0x14f, 0x155..0x178)")
	check(hud.quest_hover_at(Vector2(0x150, 0x179)) == -1 and hud.quest_hover_at(Vector2(0x9b, 0x160)) == -1, "Q-2: outside Okay")
	hud.quest_offer.mode = "continue"
	check(hud.quest_hover_at(Vector2(0x9c + 5, 0x155 + 5)) == -1, "Q-2: no Okay in continue mode")
	var enter := InputEventKey.new()
	enter.pressed = true
	enter.keycode = KEY_ENTER
	check(hud.handle_key(enter) and hud.dialog == "", "Q-2: Enter closes the continue dialog (0x56abe0)")
	# Type 0: the progress figure is the stockpile of the record's resource (0x56aff0's switch on the letter).
	var deliver := {"type": 0, "target": "G", "count": 500}
	check(hud.quest_progress_value(deliver, 7) == int(scene.economy.resources(scene.local_player)[0]), "Q-2: type 0 shows the gold in the stockpile")
	check(hud.quest_progress_value({"type": 1}, 7) == 7, "Q-2: other types show the quest's counter")
	# Cursor 0xc: the hero selected over the quest site (searchable, Quests on); another head or Quests off give no 0xc.
	var shrine: int = scene.encounters.place_site("BMSH", 6, scene.navigator.free_cell_near(hero.cell + Vector2i(4, -6)))
	var b = scene.production.building(shrine)
	check(b != null, "Q-2: a Shrine placed near the hero (explored) for the cursor check")
	if b != null and hero != null:
		hud.select_hero()
		scene.centre_view(b.position)
		var screen: Vector2 = scene.get_canvas_transform() * b.position
		var ctx: Dictionary = scene.cursor_context(screen)
		check(bool(ctx.get("pickup", false)) and preload("res://battle/selection.gd").cursor_index(ctx) == 12, "Q-2: the hero over a quest site: cursor 0xc (0x420390) %s" % [ctx])
		scene.encounters.quests_enabled = false
		ctx = scene.cursor_context(screen)
		check(not bool(ctx.get("pickup", false)), "Q-2: Quests off: no cursor 0xc over the quest site")
		scene.encounters.quests_enabled = true
		scene.centre_view(hero.position)

## UI gaps (UI_RESEARCH.md "Interface gaps"): the shop dialog 12 (0x56dc00 / 0x56e8f0 / 0x56dfc0 / 0x56e0b0 / 0x56dde0,
## Read from the disassembly), the item picture cells, the power lines of 0x403a90 / 0x556fc0 and the m key (0x561c30).
func ui_gaps_checks(scene, hud):
	if scene.hero_unit_id < 0 or scene.encounters == null:
		check(false, "UI gaps: the match has a hero")
		return
	var hero = scene.units[scene.hero_unit_id]
	var shop: int = scene.encounters.place_site("BSFG", 6, scene.navigator.free_cell_near(hero.cell + Vector2i(6, 6)))
	scene.encounters.shops_ready = false
	scene.simulation_step(0.05)
	check(scene.encounters.shops.has(shop), "UI gaps: a shop placed and stocked")
	if not scene.encounters.shops.has(shop): return
	var stock: Dictionary = scene.encounters.shops[shop]
	stock.items = [15, 0]                                     # Blackfire Axe (artifact, value 105) and a sold place
	stock.percent[0] = 100
	scene.economy.stockpiles[0] = [1000, 1000, 1000, 1000]
	scene.hero_match.potions = 9
	hud.open_shop(shop)
	check(hud.dialog == "shop" and hud.dialog_origin().x == 1000.0, "UI gaps: the shop at x 1000 (0x56dc00, 1600 mode)")
	check(hud.shop_hit(Vector2(0x30, 0x50)) == 0 and hud.shop_hit(Vector2(0x143, 0x50)) == -1 and hud.shop_hit(Vector2(0xe8, 0x50)) == 2, "UI gaps: a place counts only while it holds a good (0x56e350)")
	check(hud.shop_hit(Vector2(0x30, 0x43)) == -1 and hud.shop_hit(Vector2(0x30, 0x9e)) == 0 and hud.shop_hit(Vector2(0x8a, 0x50)) == -1, "UI gaps: the place edges")
	var flags: Array = hud.shop_flags()
	check(bool(flags[0].no_room) and not bool(flags[1].no_room) and bool(flags[2].expensive) and not bool(flags[0].expensive), "UI gaps: 9 potions: No Room; 1050 > 1000: Too Expensive (0x56e8f0)")
	# A press on a place buys at once (0x56dfc0); the release does nothing more.
	var mana: int = scene.hero_match.mana_potion_count()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	hud.shop_mouse(press, Vector2(0x8c + 10, 0x50))
	check(scene.hero_match.mana_potion_count() == mana + 1 and hud.shop_clicked and hud.dialog_hover == 1, "UI gaps: the press buys the mana potion (0x56dfc0 -> 0x56e420)")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	hud.shop_mouse(release, Vector2(0x8c + 10, 0x50))
	check(scene.hero_match.mana_potion_count() == mana + 1 and hud.dialog == "shop", "UI gaps: the release buys nothing more and the dialog stays")
	# The close button: armed by the press, closes on the release (0x56dfc0 / 0x56e0b0).
	hud.shop_mouse(press, Vector2(0xcd + 5, 0x171 + 5))
	check(hud.shop_close_armed and hud.shop_close_state == 2 and hud.dialog == "shop", "UI gaps: the close press arms it (frame 2)")
	hud.shop_mouse(release, Vector2(0x10, 0x10))
	check(not hud.shop_close_armed and hud.dialog == "shop", "UI gaps: released elsewhere it does not close")
	# Once a place was pressed, leaving the dialog closes it (0x56dde0, +0x135).
	var motion := InputEventMouseMotion.new()
	hud.shop_mouse(motion, Vector2(0x20, 0x50))
	check(hud.dialog == "shop" and hud.dialog_hover == -1, "UI gaps: moving inside keeps it open")
	hud.shop_mouse(motion, Vector2(-5, 0x50))
	check(hud.dialog == "", "UI gaps: after a click, leaving the dialog closes it (0x56dde0)")
	hud.open_shop(shop)
	hud.shop_mouse(motion, Vector2(-5, 0x50))
	check(hud.dialog == "shop", "UI gaps: without a click, leaving does not close it")
	hud.shop_mouse(press, Vector2(0xcd + 5, 0x171 + 5))
	hud.shop_mouse(release, Vector2(0xcd + 5, 0x171 + 5))
	check(hud.dialog == "", "UI gaps: press and release on close: closed")
	# Item pictures and sparkles.
	var axe: Dictionary = preload("res://simulation/hero_effects.gd").item(15)
	check(hud.item_cell(axe) == Rect2((int(axe.iconcol) + 1) * 70, int(axe.iconrow) * 110, 70, 110), "UI gaps: IDLG column iconcol + 1 (0x487f20(IDLG, row, col + 1))")
	check(hud.sparkle_cell(4, 3) == Rect2(0x188 + 0x28 * 3, 0x29d, 0x28, 0x2e) and hud.sparkle_cell(5, 6) == Rect2(0x274 + 0x50, 0x1e0 + 0x2e, 0x28, 0x2e) and hud.sparkle_cell(1, 0).size.x == 0, "UI gaps: artifact / set sparkle frames (SelectionRings.bmp)")
	# Power lines (0x403a90) and skill lines (0x556fc0).
	check(hud.c_format("%+d Armor", [20]) == "+20 Armor" and hud.c_format("%+d%% Spellcasting", [-5]) == "-5% Spellcasting" and hud.c_format("+%0.2f%% Discount", [5.6603]) == "+5.66% Discount", "UI gaps: Game.txt formats")
	check(hud.item_power_line({"type": 0x18, "data": 20, "text": ""}) == "+20 Armor" and hud.item_power_line({"type": 0x2f, "data": 3, "text": ""}) == "Fast Attack Speed (+30%)", "UI gaps: power lines [0452], [0437] x 10")
	check(hud.item_power_line({"type": 0x39, "data": 0, "text": ""}) == "Immunity to Disease" and hud.item_power_line({"type": 0xd, "data": 0, "text": ""}) == "", "UI gaps: immunity line; type 0xd none")
	check(hud.item_power_line({"type": 0xb, "data": 3, "text": ""}) == "+3 Merchant skill (5.66% Discount)", "UI gaps: the Merchant line (100 - 100 / 106 x 100)")
	check(hud.item_power_line({"type": 99, "data": 11, "level": 2, "text": ""}) == "+2 Summoning Magic", "UI gaps: a school skill power [0461 + skill]")
	check(hud.item_power_line({"type": 99, "data": 1, "level": 2, "text": ""}) == "+6 to Combat Skill", "UI gaps: Ferocity 2 through 0x556fc0 (x3: +6 [0593])")
	check(hud.item_power_line({"type": 0x62, "data": 0, "chance": 10, "text": ""}) == "Casts Heal Self (10% chance per hit)", "UI gaps: Cast Spell with its chance")
	check(hud.item_power_line({"type": 1, "data": 2, "text": "Own words"}) == "Own words", "UI gaps: a Power element's own text wins")
	# The m key: one mana potion (KeyMap line 60 -> 0x561c30).
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_M
	var before: int = scene.hero_match.mana_potion_count()
	var f = scene.combat.fighters.get(scene.hero_unit_id)
	if f != null: f["mana"] = 0
	check(hud.handle_key(key) and scene.hero_match.mana_potion_count() == before - 1, "UI gaps: m drinks a mana potion (0x561c30)")
	key.shift_pressed = true
	check(not hud.handle_key(key) and scene.hero_match.mana_potion_count() == before - 1, "UI gaps: M (Drain Mana) is not the potion key")
	scene.hero_match.potions = 4

