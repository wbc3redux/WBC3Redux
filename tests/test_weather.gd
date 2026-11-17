extends SceneTree
## Enhanced visuals round 3 (ENHANCED_VISUALS.md): the weather rows on the Options screen's Visuals tab, the "Match Map"
## choice, and the weather layer in the real scene (main.tscn). Uses a copied settings file; never touches
## user://settings.cfg.

const Settings = preload("res://simulation/game_settings.gd")
const DisplayConfig = preload("res://core/display.gd")
const WeatherFx = preload("res://visuals/weather_fx.gd")
const OptionsScreen = preload("res://menus/options_screen.gd")
const DayNight = preload("res://simulation/day_night.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Weather check failed: ", label)

func _initialize():
	call_deferred("run")

func row_of(key: String) -> Dictionary:
	for r in DisplayConfig.visual_rows():
		if r.key == key: return r
	return {}

func run():
	var settings_file := "user://weather-test-settings.cfg"
	DirAccess.remove_absolute(settings_file)
	Settings.use_file(settings_file)
	DisplayConfig.load_settings()
	# Rows: twelve, weather off by default, strength disabled while the weather is off, everything while Enhanced is off.
	var rows: Array = DisplayConfig.visual_rows()
	check(rows.size() == 12 and rows[10].key == "Weather" and rows[11].key == "WeatherStrength", "twelve Visuals rows, weather last")
	check(int(DisplayConfig.visuals.Weather) == 0 and int(DisplayConfig.visuals.WeatherStrength) == 1, "defaults: weather Off, strength Light")
	check(rows[10].disabled and rows[11].disabled, "weather rows disabled while Enhanced Visuals is off")
	DisplayConfig.set_visual("Enhanced", true)
	check(not row_of("Weather").disabled and row_of("WeatherStrength").disabled, "strength disabled while the weather is off")
	DisplayConfig.set_visual("Weather", WeatherFx.RAIN)
	check(not row_of("WeatherStrength").disabled and DisplayConfig.row_text(row_of("Weather")) == "Weather: Rain", "rain row text")
	DisplayConfig.set_visual("Enhanced", false)
	check(int(DisplayConfig.visual("Weather")) == 0, "no weather while Enhanced Visuals is off")
	DisplayConfig.set_visual("Weather", 0)

	# Match Map.
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	check(WeatherFx.for_map(map) == WeatherFx.SAND, "Desert Sands -> sandstorm")
	check(WeatherFx.for_map({"source": "Scenario/Winter Wonderland.SCN"}) == WeatherFx.SNOW, "Winter Wonderland -> snow")
	check(WeatherFx.for_map({"source": "Scenario/Rumble in the Jungle.SCN"}) == WeatherFx.RAIN, "jungle -> rain")
	check(WeatherFx.for_map({"source": "Scenario/Cavern Wars.SCN"}) == WeatherFx.FOG, "caverns -> fog")
	check(WeatherFx.for_map({"terrain_records": [{"name": "Plains #1"}, {"name": "Coast Top"}]}) == WeatherFx.RAIN, "grass with coast -> rain")
	check(WeatherFx.for_map({"terrain_records": [{"name": "Plains #1"}]}) == WeatherFx.NONE, "plain grass stays clear")
	check(WeatherFx.for_map({}) == WeatherFx.NONE, "no map: clear")

	# The layer in the real scene.
	root.size = Vector2i(1920, 1080)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var fx = scene.visuals.weather_fx
	check(fx != null and not fx.layer.visible, "weather layer hidden by default")
	DisplayConfig.set_visual("Weather", WeatherFx.RAIN)
	scene.visuals.set_enabled(true)
	var m: ShaderMaterial = fx.rect.material
	check(fx.layer.visible and int(m.get_shader_parameter("kind")) == 1 and is_equal_approx(float(m.get_shader_parameter("strength")), 0.55), "rain, light")
	for i in 3: await process_frame
	check(fx.rect.size == Vector2(root.size), "covers the window")
	check(float(m.get_shader_parameter("time_s")) > 0.0, "clock follows")
	var origin: Vector2 = m.get_shader_parameter("view_origin")
	scene.set_view_top_left(scene.view_top_left() + Vector2(320, 240))
	await process_frame
	await process_frame
	check((Vector2(m.get_shader_parameter("view_origin")) - origin).distance_to(Vector2(320, 240)) < 1.0, "anchored to the world: follows the view")
	DisplayConfig.set_visual("Weather", WeatherFx.MATCH_MAP)
	DisplayConfig.set_visual("WeatherStrength", 2)
	scene.visuals.apply_settings()
	check(fx.weather == WeatherFx.SAND and int(m.get_shader_parameter("kind")) == 4 and is_equal_approx(float(m.get_shader_parameter("strength")), 1.0), "Match Map on Desert Sands: heavy sandstorm")
	for choice in [WeatherFx.SNOW, WeatherFx.FOG]:
		DisplayConfig.set_visual("Weather", choice)
		scene.visuals.apply_settings()
		check(fx.layer.visible and int(m.get_shader_parameter("kind")) == WeatherFx.SHADER_KIND[choice], "%s shown" % WeatherFx.NAMES[choice])
		await process_frame
	scene.visuals.set_enabled(false)
	check(not fx.layer.visible, "hidden with the master switch off")
	scene.queue_free()
	await process_frame

	# The Options screen: two more droplists on the Visuals tab only; choosing stores the value; Cancel restores it.
	DisplayConfig.set_visual("Enhanced", true)
	DisplayConfig.set_visual("Weather", 0)
	DisplayConfig.save_settings()
	var screen = OptionsScreen.new()
	root.add_child(screen)
	await process_frame
	var extra := "PNL_GAMEOPTIONS/BUTT_OPTIONS_DROPLIST#10"
	# B1-3: the Gameplay tab's extra droplist #10 is Day / Night (B1_3_RESEARCH.md section 5); S-1 added #11, Autosave
	# (SAVE_LOAD.md), under the right column.
	check(String(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 11), "")).begins_with("Autosave: "), "S-1: row 11 on the Gameplay tab is Autosave")
	check(String(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 10), "")).begins_with("Day / Night: "), "row 10 on the Gameplay tab is Day / Night")
	screen.select_page(OptionsScreen.VISUALS)
	check(screen.has_item(extra) and screen.has_item("PNL_GAMEOPTIONS/BUTT_OPTIONS_DROPLIST#11"), "droplists 10 and 11 on the Visuals tab")
	check(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 10), "") == "Weather: Off", "row 10 label")
	check(String(screen.canvas.control_text.get(screen.opt_key("STR_MEDIUM200", 0), "")) == "", "processor line empty on the Visuals tab")
	check(int(screen.canvas.control_state.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 11), 0)) == 3, "strength disabled while off")
	var a: Rect2 = Rect2(screen.item(extra).rect)
	var b: Rect2 = Rect2(screen.item("PNL_GAMEOPTIONS/BUTT_OPTIONS_DROPLIST#4").rect)
	check(a.position.x == b.position.x and a.position.y - b.position.y == 35, "row 10 under row 4, 35 apart")
	check(screen.click(extra) and screen.drop_row == 10, "row 10 opens its list")
	screen.choose(10, 3)
	check(int(DisplayConfig.visuals.Weather) == WeatherFx.SNOW and screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 10), "") == "Weather: Snow", "snow chosen")
	screen.select_page(0)
	check(String(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 11), "")).begins_with("Autosave: ") and String(screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 10), "")).begins_with("Day / Night: "), "back to the Gameplay rows")
	screen.choose(10, 1)
	check(not DayNight.setting_on() and screen.canvas.control_text.get(screen.opt_key("BUTT_OPTIONS_DROPLIST", 10), "") == "Day / Night: Off", "B1-3: Day / Night: Off chosen")
	screen.click("PNL_GAMEOPTIONS/BUTT_CANCEL_STARTUP#0")
	check(int(DisplayConfig.visuals.Weather) == 0, "Cancel restores the weather")
	check(DayNight.setting_on(), "Cancel restores Day / Night: On")
	await process_frame
	DirAccess.remove_absolute(settings_file)
	if failures == 0: print("Weather checks passed: %d" % checks)
	else: printerr("Weather checks failed: %d of %d" % [failures, checks])
	quit(0 if failures == 0 else 1)
