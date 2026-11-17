extends RefCounted
## DELIBERATE MODERN CHANGES (COMPLAINTS_AND_FIXES.md): fixes for the long-standing community complaints about unit
## movement, the computer's armies and readability. The original behaviour stays the default and keeps every parity
## check; "Improved" is chosen on the Options screen's Gameplay tab (its two empty rows 8 and 9, in the original style).
## Stored in the `[Modern]` section of user://settings.cfg; `[Options]` stays the original's.
##
## Keys:
## * Movement  - formation march, crowd flow, staged group attacks, cleaner routes, sealed-building check (F1-F5)
## * Armies    - computer groups gather and attack together, flank and fall back (F6), and fight back on the march
## * Research  - the computer's research no longer waits behind Crusade I (F10, AI_RESEARCH.md section 15)
## * HealthBars - health strips on every visible unit, not only the selected ones (F9)
## * Casting   - a pause keeps the hero's cast orders, the placement cursor and the spell dialogs (C1 / F7, B1-6a)
## The Gameplay row "Battle Rules" sets Movement, Armies, Research and Casting together; tests and the command line can set
## them apart (`-- --movement=improved`, `--armies=improved`, `--research=improved`, `--casting=improved`,
## `--health-bars=always`).

const GameSettings = preload("res://simulation/game_settings.gd")
const DEFAULTS := {"Movement": false, "Armies": false, "Research": false, "HealthBars": false, "Casting": false}

static var values := DEFAULTS.duplicate()
static var overrides := {}
static var loaded_from := ""

static func ensure_loaded():
	if loaded_from != GameSettings.file_path: load_settings()

static func load_settings():
	loaded_from = GameSettings.file_path
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	# Headless runs (the checks and soaks) keep the original rules unless a test or the command line asks otherwise.
	if DisplayServer.get_name() != "headless" and config.load(loaded_from) == OK:
		for key in DEFAULTS: values[key] = bool(config.get_value("Modern", key, DEFAULTS[key]))
	overrides = parse_overrides(OS.get_cmdline_user_args())

static func save_settings() -> bool:
	var config := ConfigFile.new()
	config.load(GameSettings.file_path)
	for key in values: config.set_value("Modern", key, values[key])
	return config.save(GameSettings.file_path) == OK

static func parse_overrides(args: PackedStringArray) -> Dictionary:
	var o := {}
	for arg in args:
		if arg.begins_with("--movement="): o.Movement = arg.get_slice("=", 1) == "improved"
		elif arg.begins_with("--armies="): o.Armies = arg.get_slice("=", 1) == "improved"
		elif arg.begins_with("--research="): o.Research = arg.get_slice("=", 1) == "improved"
		elif arg.begins_with("--casting="): o.Casting = arg.get_slice("=", 1) == "improved"
		elif arg.begins_with("--health-bars="): o.HealthBars = arg.get_slice("=", 1) == "always"
	return o

static func get_value(key: String) -> bool:
	ensure_loaded()
	return bool(overrides.get(key, values.get(key, false)))

static func set_value(key: String, value: bool):
	ensure_loaded()
	overrides.erase(key)
	values[key] = value

static func movement() -> bool: return get_value("Movement")
static func armies() -> bool: return get_value("Armies")
static func research() -> bool: return get_value("Research")
static func health_bars() -> bool: return get_value("HealthBars")
static func casting() -> bool: return get_value("Casting")

static func snapshot() -> Dictionary:
	ensure_loaded()
	return values.duplicate()

static func restore(copy: Dictionary):
	values = copy.duplicate()

## The two Gameplay rows (BUTT_OPTIONS_DROPLIST #8 and #9): "modern" marks them for options_screen.gd.
static func gameplay_rows() -> Array:
	var improved := movement() and armies()
	return [
		{"key": "BattleRules", "modern": true, "label": "Battle Rules: %s", "choices": [["Original", false], ["Improved", true]],
			"current": 1 if improved else 0},
		{"key": "HealthBars", "modern": true, "label": "Health Bars: %s", "choices": [["Selected", false], ["Always", true]],
			"current": 1 if health_bars() else 0},
	]

static func choose(key: String, value: bool):
	if key == "BattleRules":
		set_value("Movement", value)
		set_value("Armies", value)
		set_value("Research", value)
		set_value("Casting", value)
	else:
		set_value(key, value)
