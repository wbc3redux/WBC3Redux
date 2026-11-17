extends SceneTree
## S-3 (UI_RESEARCH.md "S-3"): the skirmish map list scrolls as the original's list and bar do (ui_canvas.gd, Read): range from
## the entries, the bar's five zones, arrows, page, thumb drag, wheel; then the last of the 23 maps is picked with a real press,
## Okay starts it, and the match runs on that map. Never touches user://heroes or the player's settings.

const MapData = preload("res://core/map_data.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const UiScreen = preload("res://core/ui_screen.gd")

const HERO := "test-list-knight"
const LIST := "PNL_SS/LB_SS_MAPS#0"
const BAR := "PNL_SS/SBAR_V156B#0"

var checks := 0
var failures := 0
var menu
var canvas
var list_item: Dictionary
var bar_item: Dictionary
var bar: Dictionary

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Map list check failed: ", label)

func _initialize():
	call_deferred("run")

## A mouse event through the viewport at a point in panel pixels.
func mouse(point: Vector2, button: int, down: bool):
	var at: Vector2 = menu.view.position + point * (menu.view.size / Vector2(800, 600))
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = at
	event.global_position = at
	menu.get_viewport().push_input(event)

func move(point: Vector2):
	var at: Vector2 = menu.view.position + point * (menu.view.size / Vector2(800, 600))
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	menu.get_viewport().push_input(event)

func on_bar(y: int) -> Vector2:
	return Vector2(bar_item.rect.position) + Vector2(16, y)

func on_list(y: int) -> Vector2:
	return Vector2(list_item.rect.position) + Vector2(20, y)

func set_value(value: int):
	bar.value = value
	canvas.bar_end_state(bar)

func run():
	var tag := Crypto.new().generate_random_bytes(8).hex_encode()
	var directory := "user://map-list-tests-" + tag
	var store = Store.new(directory)
	check(store.save_profile(Profile.create(HERO, "Sir Scroll")), "test profile saved")
	Settings.use_file("user://map-list-settings-%s.cfg" % tag)
	UiScreen.mark_all_seen()
	var main_scene := load("res://battle/main.tscn")      # main.gd compiled here: a first load on the loading screen's thread leaks at exit
	menu = load("res://menus/skirmish_menu.tscn").instantiate()
	menu.store = store
	root.add_child(menu)
	current_scene = menu
	await process_frame
	canvas = menu.canvas
	list_item = menu.item(LIST)
	bar_item = menu.item(BAR)
	bar = canvas.list_bars[BAR]
	range_checks()
	zone_checks()
	arrow_checks()
	page_checks()
	drag_checks()
	wheel_checks()
	await timer_checks()
	short_list_checks()
	var last: int = menu.map_entries.size() - 1
	await pick_and_start(last)
	MapData.select(MapData.DEFAULT)
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute(Setup.saved_options_path())
	DirAccess.remove_absolute(UiScreen.help_flags_path())
	DirAccess.remove_absolute("user://map-list-settings-%s.cfg" % tag)
	if failures > 0:
		printerr("Map list checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Map list checks passed: %d" % checks)
	quit()

# ------------------------------------------------------------------------------------------------ the bar's model
func range_checks():
	check(menu.map_entries.size() == 23 and canvas.list_lines(list_item).size() == 23, "23 entries in the list")
	check(canvas.list_bar_key(list_item) == BAR, "the element links the list to SBAR_V156B (0x4620d0)")
	check(int(bar.min) == 0 and int(bar.max) == 324 and int(bar.page) == 96 and int(bar.value) == 0, "0x461fe0: range 23 x 19 - 115 + 2, page 115 - 19")
	check(int(bar.state) == canvas.BAR_AT_MIN, "at the top the arrow shows its end state")
	check(canvas.list_rows(list_item).map(func(r): return r[0]) == [0, 1, 2, 3, 4, 5], "rows 0..5 reached at the top (0x461940)")
	check(canvas.list_rows(list_item).all(func(r): return canvas.list_row_fits(list_item, r[1], 5)), "all six fit")
	check(canvas.list_row_at(list_item, on_list(25)) == 1, "row under a point at the top")
	var raw := String(bar_item.element.raw).hex_decode()
	check(raw[0x64] == 0, "element +0x64 (0x45c1b0, element byte +0x24 of 0x462ec0) is clear: the original's keys pass this bar by")
	var before := int(bar.value)
	var key := InputEventKey.new()
	key.keycode = KEY_DOWN
	key.pressed = true
	menu.get_viewport().push_input(key)
	check(int(bar.value) == before, "the Down key does not scroll")

func zone_checks():
	set_value(0)
	var expected := {0: 0, 31: 0, 32: 2, 63: 2, 64: 3, 123: 3, 124: 4, 155: 4}
	for y in expected:
		check(canvas.bar_zone(bar_item, on_bar(y)) == expected[y], "0x4648c0 at the top: y %d is zone %d" % [y, expected[y]])
	set_value(162)
	# Thumb offset 60 * 162 / 325 = 29: the thumb covers rows 61..92.
	expected = {31: 0, 32: 1, 60: 1, 61: 2, 92: 2, 93: 3, 123: 3, 124: 4}
	for y in expected:
		check(canvas.bar_zone(bar_item, on_bar(y)) == expected[y], "0x4648c0 at 162: y %d is zone %d" % [y, expected[y]])
	check(canvas.bar_thumb(bar, bar_item) == 29, "the draw's thumb offset equals the hit test's")
	set_value(324)
	check(canvas.bar_thumb(bar, bar_item) == 60 and canvas.bar_zone(bar_item, on_bar(92)) == 2 and canvas.bar_zone(bar_item, on_bar(91)) == 1, "at the end the thumb sits above the bottom arrow")
	check(canvas.bar_zone(bar_item, Vector2(bar_item.rect.position) + Vector2(32, 40)) == -1, "outside the bar")
	set_value(0)

func arrow_checks():
	mouse(on_bar(10), MOUSE_BUTTON_LEFT, true)
	check(canvas.bar_held == "", "the top arrow at the top does not hold (0x45e610)")
	mouse(on_bar(10), MOUSE_BUTTON_LEFT, false)
	mouse(on_bar(140), MOUSE_BUTTON_LEFT, true)
	check(canvas.bar_held == BAR and int(bar.state) == canvas.BAR_DOWN_HELD and int(bar.value) == 0, "the press holds the bottom arrow; nothing moves before a tick")
	canvas.bar_tick()
	canvas.bar_tick()
	canvas.bar_tick()
	check(int(bar.value) == 15, "5 pixels a tick (0x4606a0, the bar has a list)")
	check(canvas.list_rows(list_item)[0] == [0, -14], "the list follows the bar, by pixels (0x4649f0, 0x461940)")
	move(on_bar(80))
	canvas.bar_tick()
	check(int(bar.value) == 15, "the arrow stops repeating when the mouse leaves it")
	move(on_bar(140))
	canvas.bar_tick()
	check(int(bar.value) == 20, "and goes on when it returns")
	mouse(on_bar(140), MOUSE_BUTTON_LEFT, false)
	check(canvas.bar_held == "" and int(bar.state) == canvas.BAR_NORMAL, "the release lets go (0x45eb70)")
	mouse(on_bar(10), MOUSE_BUTTON_LEFT, true)
	check(int(bar.state) == canvas.BAR_UP_HELD, "the top arrow holds")
	canvas.bar_tick()
	canvas.bar_tick()
	canvas.bar_tick()
	canvas.bar_tick()
	check(int(bar.value) == 0 and int(bar.state) == canvas.BAR_AT_MIN, "and runs to the top")
	mouse(on_bar(10), MOUSE_BUTTON_LEFT, false)

func page_checks():
	mouse(on_bar(100), MOUSE_BUTTON_LEFT, true)
	canvas.bar_tick()
	check(int(bar.value) == 96, "the track below the thumb pages by 96 (h - row height)")
	canvas.bar_tick()
	check(int(bar.value) == 192, "and repeats while the mouse is below the thumb")
	canvas.bar_tick()
	canvas.bar_tick()
	check(int(bar.value) == 324 or canvas.bar_zone(bar_item, on_bar(100)) != 3, "a page clamps, or the thumb has reached the mouse")
	mouse(on_bar(100), MOUSE_BUTTON_LEFT, false)
	set_value(300)
	mouse(on_bar(40), MOUSE_BUTTON_LEFT, true)
	canvas.bar_tick()
	check(int(bar.value) == 204, "the track above the thumb pages up")
	mouse(on_bar(40), MOUSE_BUTTON_LEFT, false)
	set_value(30)
	mouse(on_bar(100), MOUSE_BUTTON_LEFT, true)
	mouse(on_bar(100), MOUSE_BUTTON_LEFT, false)
	check(int(bar.value) == 30, "a press and release between two ticks moves nothing (the timer steps it)")
	set_value(0)

func drag_checks():
	mouse(on_bar(40), MOUSE_BUTTON_LEFT, true)
	check(canvas.bar_mode == 2, "the press takes the thumb")
	move(on_bar(70))
	check(int(bar.value) == 162, "0x45fa90: 325 * 30 / 60")
	canvas.bar_tick()
	check(int(bar.value) == 162, "a held thumb has no tick")
	move(on_bar(40))
	check(int(bar.value) == 0, "back to the press point, back to the start value")
	move(on_bar(400))
	check(int(bar.value) == 324, "clamped to the range")
	var ends: Array = canvas.list_rows(list_item)
	check(ends.map(func(r): return r[0]) == [17, 18, 19, 20, 21, 22] and ends[0][1] == 0, "the last six rows show")
	mouse(on_bar(400), MOUSE_BUTTON_LEFT, false)
	check(canvas.bar_held == "" and int(bar.state) == canvas.BAR_AT_MAX, "the release anywhere lets go; the bottom arrow shows its end state")
	check(canvas.list_row_at(list_item, on_list(100)) == 22, "the last row under the mouse")

func wheel_checks():
	set_value(0)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_DOWN, true)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_DOWN, false)
	check(int(bar.value) == 15, "the wheel over the list: 15 pixels a notch (0x461520)")
	mouse(on_bar(80), MOUSE_BUTTON_WHEEL_DOWN, true)
	mouse(on_bar(80), MOUSE_BUTTON_WHEEL_DOWN, false)
	check(int(bar.value) == 30, "the wheel over the bar")
	mouse(Vector2(700, 40), MOUSE_BUTTON_WHEEL_DOWN, true)
	mouse(Vector2(700, 40), MOUSE_BUTTON_WHEEL_DOWN, false)
	check(int(bar.value) == 30, "the wheel elsewhere does nothing")
	for i in 3:
		mouse(on_list(40), MOUSE_BUTTON_WHEEL_UP, true)
		mouse(on_list(40), MOUSE_BUTTON_WHEEL_UP, false)
	check(int(bar.value) == 0, "up again, no further than the top when the steps land on it")
	set_value(9)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_UP, true)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_UP, false)
	check(int(bar.value) == -6 and canvas.list_rows(list_item)[0] == [0, 7], "a notch does not clamp: the list rests 6 pixels past the top (0x461520)")
	check(canvas.list_row_at(list_item, on_list(3)) == 0 and canvas.bar_thumb(bar, bar_item) == 0, "row and thumb stay sound there")
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_UP, true)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_UP, false)
	check(int(bar.value) == -6, "and no further")
	set_value(0)

## The window's 50 ms timer drives the held arrow in a running scene.
func timer_checks():
	mouse(on_bar(140), MOUSE_BUTTON_LEFT, true)
	await create_timer(0.4).timeout
	check(int(bar.value) >= 10, "held in a running scene the arrow repeats on the timer (%d)" % int(bar.value))
	mouse(on_bar(140), MOUSE_BUTTON_LEFT, false)
	set_value(0)

## Every list goes through set_list: one that fits disables its bar, and the bar draws no thumb.
func short_list_checks():
	var names: Array = Array(canvas.list_lines(list_item))
	canvas.set_list(list_item, names.slice(0, 5), 0)
	check(int(bar.state) == canvas.BAR_DISABLED and int(bar.value) == 0, "five rows fit: the bar is disabled (0x4620d0, 0x461fe0 never enables it)")
	mouse(on_bar(140), MOUSE_BUTTON_LEFT, true)
	check(canvas.bar_held == "", "a disabled bar does not hold")
	mouse(on_bar(140), MOUSE_BUTTON_LEFT, false)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_DOWN, true)
	mouse(on_list(40), MOUSE_BUTTON_WHEEL_DOWN, false)
	check(int(bar.value) == 0, "nor does the wheel move it")
	canvas.set_list(list_item, names.slice(0, 7), 0)
	check(int(bar.max) == 133 - 115 + 2 and int(bar.state) == canvas.BAR_AT_MIN, "seven rows of 19 do not fit in 113: the bar comes on")
	canvas.set_list(list_item, names, menu.selected_map)
	check(int(bar.max) == 324, "the list restored")

# ------------------------------------------------------------------------------------------------ the exit gate
func pick_and_start(last: int):
	check(not canvas.list_rows(list_item).any(func(r): return r[0] == last), "the last map is out of reach at the top")
	check(canvas.list_row_at(list_item, on_list(100)) == 5, "a press at the bottom of the list is row 5")
	mouse(on_bar(40), MOUSE_BUTTON_LEFT, true)
	move(on_bar(400))
	mouse(on_bar(400), MOUSE_BUTTON_LEFT, false)
	check(int(bar.value) == 324, "dragged to the end")
	var name := String(menu.map_entries[last].name)
	var slug := String(menu.map_entries[last].slug)
	mouse(on_list(100), MOUSE_BUTTON_LEFT, true)
	check(menu.selected_map == last and int(canvas.control_list[LIST]) == last, "the press picks the last map, %s" % name)
	mouse(on_list(100), MOUSE_BUTTON_LEFT, false)
	check(MapData.current == slug and menu.map_selected, "its data is current")
	check(int(bar.value) == 324, "refreshing the screen keeps the scroll")
	menu.hero = menu.store.selected_profile()
	if menu.hero == null: menu.hero = menu.store.load_profile(HERO)
	menu.select_map(last)
	check(menu.hero != null and menu.enabled("PNL_SS/BUTT_OKAY_STARTUP#0"), "Okay enabled for %s" % name)
	check(menu.real_click("PNL_SS/BUTT_OKAY_STARTUP#0"), "Okay pressed")
	check(not Setup.pending.is_empty() and String(Setup.pending.setup.map) == String(MapData.map().get("source", Setup.pending.setup.map)), "Okay hands the setup over (0x4e2790)")
	# The hand-over stays with the test: main.gd would read the live hero book, the test's hero is in its own directory.
	var handed: Dictionary = Setup.pending.setup
	var hero_id: String = Setup.pending.hero_id
	var store = menu.store
	Setup.pending = {}
	var waited := 0
	while waited < 6000 and not (current_scene != null and current_scene.has_method("start_skirmish")):
		await process_frame
		waited += 1
	var scene = current_scene
	check(scene != null and scene.has_method("start_skirmish"), "the loading screen reaches main.tscn (%d frames)" % waited)
	if scene == null or not scene.has_method("start_skirmish"): return
	handed.army_budget = 0                     # the army screen has its own suite
	check(scene.start_skirmish(handed, hero_id, store, "map-list-test"), "the match starts on the handed setup")
	check(MapData.current == slug and Setup.pending.is_empty(), "on %s, the hand-over taken" % name)
	check(scene.units.filter(func(u): return u.owner_id < 6).size() >= 2, "the sides' heroes are there")
	scene.advance_seconds(3.0)
	check(not scene.skirmish.over, "the match runs")
	scene.end_skirmish()
	unload_current_scene()
	await process_frame
	await process_frame
