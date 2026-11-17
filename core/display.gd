extends Node
## Display settings of the modern presentation (DELIBERATE MODERN CHANGE, not original behaviour; see DISPLAY_SETTINGS.md).
## The original offers 800x600 / 1024x768; the rebuild runs at the monitor's native resolution. The settings sit on the
## Options screen's fourth tab, Advanced (options_screen.gd, rows from advanced_rows()), and live in the same file as the
## original options (`[Display]` and `[Audio]` sections; `[Options]` stays the original's). Brightness is the original
## Gamma Correction option, which the rebuild now applies.
##
## Autoload "DisplayManager": applies the window settings at start (and the command-line overrides), owns the brightness
## layer, the background mute and Alt+Enter (windowed <-> borderless). Everything else reads the static helpers:
## * view_scale(window): the one scale shared by the world camera, the control panel, the in-game dialogs and the cursor.
##   Auto picks the smallest step whose world view (window / scale, minus the 150-row panel) is at most VIEW_HEIGHT rows,
##   so a higher resolution shows more map up to the cap and then gets sharper instead.
## * view_bars(window): black bars at the sides of the world view once the view is wider than the chosen battlefield cap.
## * menu_rect(window, base): where the 4:3 screens go; menu_filter() their filtering (Smooth / Sharp).
##
## Command line (after `--`): --windowed, --fullscreen (borderless), --exclusive, --window=WxH, --monitor=N, --scale=S,
## --view=original|widescreen|ultrawide. Overrides apply to this run only and are not saved.

const GameSettings = preload("res://simulation/game_settings.gd")

const WINDOWED := 0
const BORDERLESS := 1
const EXCLUSIVE := 2
const SCALE_STEPS := [1.0, 1.5, 2.0, 2.5, 3.0, 4.0]
const VIEW_HEIGHT := 1050.0                       # the original's 1600x1200 mode: 1200 - the 150-row panel
const VIEW_WIDTHS := [1600.0, 1920.0, 3200.0]     # Original (1600 mode), Widescreen, Ultrawide (2x the original)
const PANEL_ROWS := 150.0
const FRAME_CAPS := [0, 30, 60, 120, 144, 165, 240]
const WINDOW_SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160)]

const DISPLAY_DEFAULTS := {
	"WindowMode": BORDERLESS, "Monitor": -1, "WindowWidth": 0, "WindowHeight": 0, "InterfaceScale": 0.0,
	"BattlefieldView": 1, "MenuScaling": 0, "VSync": true, "FrameCap": 0, "ConfineMouse": true,
}
const AUDIO_DEFAULTS := {"MuteInBackground": true}
## Enhanced visuals (ENHANCED_VISUALS.md, DELIBERATE MODERN CHANGE): the Options screen's fifth tab, Visuals. "Enhanced"
## is the master switch (F9 in a match); every other row only counts while it is on. Levels: 0 off, 1 subtle, 2 full.
const VISUALS_DEFAULTS := {
	"Enhanced": false, "SoftShadows": true, "Grade": 1, "Glow": 1, "SmoothFog": true, "SmoothCamera": true,
	"Highlight": true, "Terrain": 2, "Ambience": true, "Combat": 1, "Weather": 0, "WeatherStrength": 1,
}
const WINDOW_KEYS := ["WindowMode", "Monitor", "WindowWidth", "WindowHeight"]

static var display := DISPLAY_DEFAULTS.duplicate()
static var audio := AUDIO_DEFAULTS.duplicate()
static var visuals := VISUALS_DEFAULTS.duplicate()
static var overrides := {}                        # command-line values for this run (not saved)
static var loaded_from := ""
static var window_applied := false

## Emitted after a setting changed (the scale, the view, the menu filter, the window): the screens place themselves again.
signal changed

var brightness_layer: CanvasLayer
var brightness_rect: ColorRect
var background_muted := false

# ------------------------------------------------------------------------------------------------ settings file
static func path() -> String:
	return GameSettings.file_path

static func ensure_loaded():
	if loaded_from != path(): load_settings()

static func load_settings():
	loaded_from = path()
	display = DISPLAY_DEFAULTS.duplicate()
	audio = AUDIO_DEFAULTS.duplicate()
	visuals = VISUALS_DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(loaded_from) != OK: return
	for key in DISPLAY_DEFAULTS: display[key] = typed(config.get_value("Display", key, DISPLAY_DEFAULTS[key]), DISPLAY_DEFAULTS[key])
	for key in AUDIO_DEFAULTS: audio[key] = typed(config.get_value("Audio", key, AUDIO_DEFAULTS[key]), AUDIO_DEFAULTS[key])
	for key in VISUALS_DEFAULTS: visuals[key] = typed(config.get_value("Visuals", key, VISUALS_DEFAULTS[key]), VISUALS_DEFAULTS[key])
	display.BattlefieldView = clampi(int(display.BattlefieldView), 0, VIEW_WIDTHS.size() - 1)

static func typed(value, like):
	if like is bool: return bool(value)
	if like is float: return float(value)
	if like is int: return int(value)
	return value

## Writes the three sections, keeping every other section of the file (the original's [Options]).
static func save_settings() -> bool:
	var config := ConfigFile.new()
	config.load(path())
	for key in display: config.set_value("Display", key, display[key])
	for key in audio: config.set_value("Audio", key, audio[key])
	for key in visuals: config.set_value("Visuals", key, visuals[key])
	return config.save(path()) == OK

static func setting(key: String):
	ensure_loaded()
	if overrides.has(key): return overrides[key]
	return display.get(key, DISPLAY_DEFAULTS.get(key))

## `-- --windowed` etc. (see the header).
static func parse_overrides(args: PackedStringArray) -> Dictionary:
	var o := {}
	for a in args:
		if a == "--windowed": o.WindowMode = WINDOWED
		elif a == "--fullscreen": o.WindowMode = BORDERLESS
		elif a == "--exclusive": o.WindowMode = EXCLUSIVE
		elif a.begins_with("--window="):
			var parts := a.trim_prefix("--window=").to_lower().split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				o.WindowMode = WINDOWED
				o.WindowWidth = int(parts[0])
				o.WindowHeight = int(parts[1])
		elif a.begins_with("--monitor=") and a.trim_prefix("--monitor=").is_valid_int(): o.Monitor = int(a.trim_prefix("--monitor="))
		elif a.begins_with("--scale=") and a.trim_prefix("--scale=").is_valid_float(): o.InterfaceScale = float(a.trim_prefix("--scale="))
		elif a.begins_with("--view="):
			var i := ["original", "widescreen", "ultrawide"].find(a.trim_prefix("--view=").to_lower())
			if i >= 0: o.BattlefieldView = i
	return o

# ------------------------------------------------------------------------------------------------ shared geometry
## The shared scale for a window (see the header). A fixed interface scale wins over Auto.
static func view_scale(window: Vector2) -> float:
	var fixed := float(setting("InterfaceScale"))
	if fixed > 0.0: return fixed
	return auto_scale(window)

static func auto_scale(window: Vector2) -> float:
	for s in SCALE_STEPS:
		if window.y / s - PANEL_ROWS <= VIEW_HEIGHT: return s
	return SCALE_STEPS[-1]

## Width of each black bar beside the world view (window pixels): the view is at most the battlefield cap wide.
static func view_bars(window: Vector2, scale: float) -> float:
	var cap: float = VIEW_WIDTHS[clampi(int(setting("BattlefieldView")), 0, VIEW_WIDTHS.size() - 1)] * scale
	return maxf(0.0, floorf((window.x - cap) / 2.0))

## The 4:3 screens: fitted to the window and centred. Sharp uses the largest whole multiple when it fills at least 85%
## of the fitted height (pixel-exact art), else the fitted size; both use nearest filtering.
static func menu_rect(window: Vector2, base: Vector2) -> Rect2:
	var fit := minf(window.y / base.y, window.x / base.x)
	var scale := fit
	if int(setting("MenuScaling")) == 1:
		var whole := floorf(fit)
		if whole >= 1.0 and whole >= fit * 0.85: scale = whole
	var size := base * scale
	return Rect2(((window - size) / 2.0).floor(), size)

static func menu_filter() -> int:
	return CanvasItem.TEXTURE_FILTER_NEAREST if int(setting("MenuScaling")) == 1 else CanvasItem.TEXTURE_FILTER_LINEAR

## Render menus at their displayed pixel size while keeping XCI layout/input in the original coordinate space.
## SubViewport's logical-size stretch also rerasterizes TrueType glyphs at the output scale, including overlays.
## The old path is available only as a run-local comparison switch; no user setting or font resource is mutated.
static func prepare_menu_viewport(viewport: SubViewport, view: TextureRect, base: Vector2i):
	var legacy := "--legacy-menu-rendering" in OS.get_cmdline_user_args()
	viewport.size_2d_override = base
	viewport.size_2d_override_stretch = not legacy
	viewport.size = base if legacy else Vector2i(view.size.round()).max(Vector2i.ONE)
	viewport.oversampling = true
	viewport.oversampling_override = 1.0 if legacy else 0.0
	viewport.canvas_item_default_texture_filter = (Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		if int(setting("MenuScaling")) == 1 else Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR)

# ------------------------------------------------------------------------------------------------ window
static func headless() -> bool:
	return DisplayServer.get_name() == "headless"

## VSync, frame cap and mouse confinement.
static func apply_runtime_settings():
	Engine.max_fps = int(setting("FrameCap"))
	if headless(): return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(setting("VSync")) else DisplayServer.VSYNC_DISABLED)
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED if bool(setting("ConfineMouse")) else Input.MOUSE_MODE_VISIBLE

## Window mode, monitor and size (then the runtime settings).
static func apply_window(window: Window):
	if window == null: return
	apply_runtime_settings()
	if headless(): return
	var monitor := int(setting("Monitor"))
	if monitor < 0 or monitor >= DisplayServer.get_screen_count(): monitor = window.current_screen
	var mode := int(setting("WindowMode"))
	if mode == WINDOWED:
		if window.mode != Window.MODE_WINDOWED: window.mode = Window.MODE_WINDOWED
		window.current_screen = monitor
		var usable: Rect2i = DisplayServer.screen_get_usable_rect(monitor)
		var size := Vector2i(int(setting("WindowWidth")), int(setting("WindowHeight")))
		if size.x <= 0 or size.y <= 0: size = Vector2i(Vector2(usable.size) * 0.8)
		var title := 40                                  # room for the title bar and frame
		size = size.min(usable.size - Vector2i(0, title)).max(Vector2i(640, 480))
		window.size = size
		window.position = usable.position + (usable.size - size) / 2 + Vector2i(0, title / 2)
	else:
		if window.mode == Window.MODE_WINDOWED: window.current_screen = monitor
		window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if mode == EXCLUSIVE else Window.MODE_FULLSCREEN

## Sizes offered in windowed mode: the common ones that fit the monitor, plus the monitor's own size.
static func window_sizes(monitor: int) -> Array:
	var native := DisplayServer.screen_get_size(monitor) if not headless() else Vector2i(1920, 1080)
	var list: Array = []
	for s in WINDOW_SIZES:
		if s.x <= native.x and s.y <= native.y: list.append(s)
	if not list.has(native): list.append(native)
	return list

# ------------------------------------------------------------------------------------------------ audio
func apply_audio():
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), background_muted)

func _notification(what: int):
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		ensure_loaded()
		background_muted = what == NOTIFICATION_APPLICATION_FOCUS_OUT and bool(audio.MuteInBackground)
		apply_audio()

# ------------------------------------------------------------------------------------------------ brightness
const BRIGHTNESS_SHADER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_nearest;
uniform float gamma = 1.0;
void fragment() {
	COLOR = vec4(pow(texture(screen, SCREEN_UV).rgb, vec3(1.0 / gamma)), 1.0);
}
"""

## The original Gamma Correction option (One .. Five, strings 0x10e) as a gamma of 1.0 .. 1.4 over the whole screen.
static func brightness() -> float:
	return 1.0 + 0.1 * float(GameSettings.current().get_value("GammaCorrection"))

func apply_brightness():
	var value := brightness()
	if brightness_layer == null:
		brightness_layer = CanvasLayer.new()
		brightness_layer.layer = 128
		brightness_rect = ColorRect.new()
		brightness_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		brightness_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		var material := ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = BRIGHTNESS_SHADER
		material.shader = shader
		brightness_rect.material = material
		brightness_layer.add_child(brightness_rect)
		add_child(brightness_layer)
	brightness_layer.visible = not is_equal_approx(value, 1.0) and not headless()
	(brightness_rect.material as ShaderMaterial).set_shader_parameter("gamma", value)

# ------------------------------------------------------------------------------------------------ autoload
func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	if "--prepare-assets" in OS.get_cmdline_user_args():     # PACKAGING.md: the installer's one-time pass, then quit
		_prepare_assets_and_quit.call_deferred()
		return
	overrides = parse_overrides(OS.get_cmdline_user_args())
	ensure_loaded()
	apply_all()

## PACKAGING.md: `-- --prepare-assets [--assets=<dir>] [--pack[=<file>]]` bakes the alpha border fix into the imported
## PNGs (asset_store.gd); with --pack it then writes the folder into one data pack (default wbc3-data.pck beside the
## executable) and removes the loose folder. Prints progress lines for the installer ("prepare d/t", "pack d/t") and
## quits with 0 on success. The front end frees itself in this mode.
func _prepare_assets_and_quit():
	var Assets = preload("res://core/asset_store.gd")
	var count: int = Assets.prepare(func(done, total): print("prepare %d/%d" % [done, total]))
	if count < 0:
		print("Preparing assets failed in " + Assets.root())
		get_tree().quit(1)
		return
	print("Prepared assets: %d PNGs in %s" % [count, Assets.root()])
	var target := ""
	for arg in OS.get_cmdline_user_args():
		if arg == "--pack": target = OS.get_executable_path().get_base_dir().path_join(Assets.PACK_FILE)
		elif String(arg).begins_with("--pack="): target = String(arg).trim_prefix("--pack=")
	if target != "":
		var files: int = Assets.pack(target, func(done, total): print("pack %d/%d" % [done, total]))
		if files < 0:
			print("Packing the game data failed: " + target)
			get_tree().quit(1)
			return
		if not Assets.remove_loose():
			print("Packed %d files into %s, but the loose folder %s could not be removed" % [files, target, Assets.root()])
			get_tree().quit(1)
			return
		print("Packed %d files into %s; loose folder removed" % [files, target])
	get_tree().quit(0)

## Alt+Enter: windowed <-> borderless fullscreen (saved).
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and event.alt_pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()

func toggle_fullscreen():
	overrides.erase("WindowMode")
	display.WindowMode = BORDERLESS if int(setting("WindowMode")) == WINDOWED else WINDOWED
	save_settings()
	apply_window(get_window())
	changed.emit()

func apply_all():
	apply_window(get_window())
	window_applied = true
	apply_brightness()
	apply_audio()

## After an option changed on the Options screen: runtime settings, brightness, then everyone re-places.
func apply_runtime():
	apply_runtime_settings()
	apply_brightness()
	changed.emit()

## The node of the autoload (null when a script runs without it, e.g. a bare test scene).
static func node(tree: SceneTree) -> Node:
	return tree.root.get_node_or_null("DisplayManager") if tree != null else null

# ------------------------------------------------------------------------------------------------ Advanced tab rows
const MODE_NAMES := ["Windowed", "Borderless", "Fullscreen"]
const SCALE_VALUES := [0.0, 1.0, 1.5, 2.0, 2.5, 3.0]
const VIEW_NAMES := ["Original", "Widescreen", "Ultrawide"]

## The ten rows of the Options screen's Advanced tab: "key", "label" (the button text, "%s" for the current choice),
## "choices" [[text, value], ...], "current" (index), "disabled".
static func advanced_rows(window: Window) -> Array:
	ensure_loaded()
	var screens := 1 if headless() else DisplayServer.get_screen_count()
	var monitor := int(setting("Monitor"))
	if monitor < 0 or monitor >= screens: monitor = 0 if headless() or window == null else window.current_screen
	var monitors: Array = []
	for i in screens: monitors.append(["Monitor %d" % (i + 1), i])
	var size_now := Vector2i(int(setting("WindowWidth")), int(setting("WindowHeight")))
	var sizes: Array = [["Automatic", Vector2i.ZERO]]
	for size in window_sizes(monitor): sizes.append(["%dx%d" % [size.x, size.y], size])
	if size_now.x > 0 and not sizes.any(func(c): return c[1] == size_now): sizes.append(["%dx%d" % [size_now.x, size_now.y], size_now])
	var modes: Array = []
	for i in MODE_NAMES.size(): modes.append([MODE_NAMES[i], i])
	var views: Array = []
	for i in VIEW_NAMES.size(): views.append([VIEW_NAMES[i], i])
	var rows := [
		row("WindowMode", "Window Mode: %s", modes, int(setting("WindowMode"))),
		row("Monitor", "Monitor: %s", monitors, monitor),
		row("WindowSize", "Window Size: %s", sizes, size_now if size_now.x > 0 else Vector2i.ZERO),
		row("InterfaceScale", "Interface Scale: %s", SCALE_VALUES.map(func(v): return ["Auto" if v == 0.0 else "%sx" % str(v), v]), float(setting("InterfaceScale"))),
		row("BattlefieldView", "Battlefield View: %s", views, int(setting("BattlefieldView"))),
		row("MenuScaling", "Menu Scaling: %s", [["Smooth", 0], ["Sharp", 1]], int(setting("MenuScaling"))),
		row("VSync", "VSync: %s", [["On", true], ["Off", false]], bool(setting("VSync"))),
		row("FrameCap", "Frame Limit: %s", FRAME_CAPS.map(func(v): return ["Unlimited" if v == 0 else str(v), v]), int(setting("FrameCap"))),
		row("ConfineMouse", "Mouse: %s", [["Kept in Window", true], ["Free", false]], bool(setting("ConfineMouse"))),
		row("MuteInBackground", "Background Sound: %s", [["Muted", true], ["Playing", false]], bool(audio.MuteInBackground)),
	]
	rows[2].disabled = int(setting("WindowMode")) != WINDOWED
	return rows

static func row(key: String, label: String, choices: Array, value) -> Dictionary:
	var current := 0
	for i in choices.size():
		if choices[i][1] == value: current = i
	return {"key": key, "label": label, "choices": choices, "current": current, "disabled": false}

## The button text of a row: its label with the current choice.
static func row_text(r: Dictionary) -> String:
	return String(r.label).replace("%s", String(r.choices[int(r.current)][0]))

## Stores an Advanced choice (dropping a command-line override of it). Returns true for the window group, which the
## caller applies with apply_window and may revert.
static func set_choice(key: String, value) -> bool:
	if key == "MuteInBackground":
		audio.MuteInBackground = value
		return false
	if key == "WindowSize":
		for k in ["WindowWidth", "WindowHeight"]: overrides.erase(k)
		display.WindowWidth = value.x
		display.WindowHeight = value.y
		return true
	overrides.erase(key)
	display[key] = value
	return key in WINDOW_KEYS

# ------------------------------------------------------------------------------------------------ Visuals tab rows
## The twelve rows of the Visuals tab (same shape as advanced_rows; options_screen.gd adds droplists 10 and 11 for them).
static func visual_rows() -> Array:
	ensure_loaded()
	var on_off := [["Off", false], ["On", true]]
	var levels := [["Off", 0], ["Subtle", 1], ["Full", 2]]
	var rows := [
		row("Enhanced", "Enhanced Visuals: %s", on_off, bool(visuals.Enhanced)),
		row("SoftShadows", "Shadows: %s", [["Original", false], ["Soft", true]], bool(visuals.SoftShadows)),
		row("Grade", "Colour Grade: %s", levels, int(visuals.Grade)),
		row("Glow", "Effect Glow: %s", levels, int(visuals.Glow)),
		row("SmoothFog", "Fog Edges: %s", [["Blocky", false], ["Smooth", true]], bool(visuals.SmoothFog)),
		row("SmoothCamera", "Camera: %s", [["Instant", false], ["Smooth", true]], bool(visuals.SmoothCamera)),
		row("Highlight", "Hover Outline: %s", on_off, bool(visuals.Highlight)),
		row("Terrain", "Terrain: %s", [["Original", 0], ["Detailed", 1], ["Detailed + Plants", 2]], int(visuals.Terrain)),
		row("Ambience", "Dust and Sand: %s", on_off, bool(visuals.Ambience)),
		row("Combat", "Combat Effects: %s", levels, int(visuals.Combat)),
		row("Weather", "Weather: %s", [["Off", 0], ["Match Map", 1], ["Rain", 2], ["Snow", 3], ["Fog", 4], ["Sandstorm", 5]],
			int(visuals.Weather)),
		row("WeatherStrength", "Weather Strength: %s", [["Light", 1], ["Heavy", 2]], int(visuals.WeatherStrength)),
	]
	for i in range(1, rows.size()): rows[i].disabled = rows[i].disabled or not bool(visuals.Enhanced)
	rows[11].disabled = rows[11].disabled or int(visuals.Weather) == 0
	return rows

## The Enhanced Visuals switch as stored (the skirmish screen's visuals button reads it).
static func setting_visuals_enhanced() -> bool:
	ensure_loaded()
	return bool(visuals.Enhanced)

static func set_visual(key: String, value):
	ensure_loaded()
	visuals[key] = value

## The value a visuals feature uses now: its row while Enhanced is on, else off (false / 0).
static func visual(key: String):
	ensure_loaded()
	if not bool(visuals.Enhanced): return false if VISUALS_DEFAULTS[key] is bool else 0
	return visuals[key]

## The window group's current values (Cancel and the 15 s revert put them back).
static func window_snapshot() -> Dictionary:
	var out := {}
	for key in WINDOW_KEYS: out[key] = setting(key)
	return out

static func restore_window(snapshot: Dictionary):
	for key in snapshot:
		overrides.erase(key)
		display[key] = snapshot[key]

## Every Display and Audio value (the Options screen's Cancel restores them).
static func snapshot() -> Dictionary:
	return {"display": display.duplicate(), "audio": audio.duplicate(), "visuals": visuals.duplicate()}

static func restore(copy: Dictionary):
	display = copy.display.duplicate()
	audio = copy.audio.duplicate()
	visuals = copy.get("visuals", visuals).duplicate()
