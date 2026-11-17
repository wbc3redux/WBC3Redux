extends RefCounted
## The player's options (milestone 11-menus, UI_RESEARCH.md "Milestone 11"). The original keeps them in the options block
## 0x70d6ac (0x8d dwords) and the registry key "Software\Enlight\Warlords Battlecry III\Options"; the rebuild keeps the same
## values under the same names in its own file (user://settings.cfg, section [Options]). Never the registry.
##
## Evidence (Read): value names and fields from the registry loader 0x4521f0; defaults from 0x453280 (the branch for a CPU of
## 410 MHz or more, i.e. any current PC; this PC's registry holds the same values except HelpLevel 0 and TipOfTheDay 0:
## Data); option screen rows and labels from 0x410760 (Gameplay), 0x410af0 (Graphics), 0x4101e0 (Sound); the values each
## dropdown choice stores from the dropdown callbacks 0x40fd40..0x4101cb; the in-game options dialog 0x566c30 / 0x567b50.

const SECTION := "Options"
const DEFAULT_PATH := "user://settings.cfg"

## 0x453280 (CPU >= 0x19a MHz branch). Fields: 0x70d6ac.. (see UI_RESEARCH.md for the address of each).
const DEFAULTS := {
	"3DSound": 0, "EAXOn": 0, "EAXAvailable": 0, "EnvironmentalSounds": 1, "FootSteps": 1, "MusicVolume": 3,
	"SFXVolume": 127, "LightingEffects": 3, "Shadows": 1, "DetailHigh": 1, "AmbientAnimation": 1, "WaterAnimation": 1,
	"FloatingText": 1, "DefaultRes": 1, "GammaCorrection": 0, "Blood": 1, "HelpLevel": 2, "ScrollRate": 3, "Weather": 1,
	"CombatSounds": 1, "UnitSpeech": 2, "OverallVolume": 120, "GameSpeed": 2, "LowResRecommended": 0,
	"DefaultGroupMovement": 1, "TimesSkippedThroughIntro": 0, "CampaignDifficulty": 1, "ResolutionSelected": 1,
	"ParticleEffectLevel": 3, "Decals": 1, "MouseEffects": 1, "VictoryDefeatBuildup": 1, "HeroHeartbeat": 1,
	"SpacebarPauses": 0, "RightClickInterface": 1, "SystemVoice": 0, "TipOfTheDay": 1,
}
## Allowed range of each value the screens can change (dropdown callbacks 0x40fd40..0x4101cb).
const RANGES := {
	"HelpLevel": [0, 2], "ScrollRate": [1, 5], "GameSpeed": [0, 4], "DefaultGroupMovement": [0, 1], "SpacebarPauses": [0, 1],
	"RightClickInterface": [0, 1], "SystemVoice": [0, 1], "TipOfTheDay": [0, 1], "ResolutionSelected": [0, 3],
	"Shadows": [0, 1], "AmbientAnimation": [0, 1], "Blood": [0, 1], "GammaCorrection": [0, 4], "FloatingText": [0, 1],
	"ParticleEffectLevel": [0, 3], "Decals": [0, 1], "LightingEffects": [0, 3], "MouseEffects": [0, 1],
	"EnvironmentalSounds": [0, 1], "FootSteps": [0, 1], "OverallVolume": [0, 127], "MusicVolume": [0, 4],
	"CombatSounds": [0, 1], "UnitSpeech": [0, 2], "EAXOn": [0, 1], "VictoryDefeatBuildup": [0, 1], "HeroHeartbeat": [0, 1],
}
## 0x40fea0..0x40ff11: the SFX dropdown stores Off 0, Low 30, Medium 60, High 90, Full 120.
const SFX_LEVELS := [0, 30, 60, 90, 120]
## 0x458dd0: the match clock advances by real time x 1/2, 3/4, 1, 3/2, 2 for game speed 1..5 (0x60c3ee = GameSpeed + 1;
## 0 is the pause). The integer rounding per call (iVar >> 1, iVar * 3 >> 2) is applied per 25 ms step by the caller.
const SPEED_NUMERATOR := [0, 1, 3, 4, 6, 8]
const SPEED_DENOMINATOR := 4

static var file_path := DEFAULT_PATH
static var _current = null

var values: Dictionary = {}
var path := DEFAULT_PATH

static func current():
	if _current == null:
		_current = load("res://simulation/game_settings.gd").new()
		_current.load_from(file_path)
	return _current

## Tests and the self-tests point the settings at a copy (never the player's file) and drop the cached instance.
static func use_file(new_path: String):
	file_path = new_path
	_current = null

func _init():
	values = DEFAULTS.duplicate()

func load_from(source: String) -> bool:
	path = source
	values = DEFAULTS.duplicate()
	var config := ConfigFile.new()
	if config.load(source) != OK: return false
	for key in DEFAULTS:
		if config.has_section_key(SECTION, key):
			var value = config.get_value(SECTION, key)
			if value is int or value is float: values[key] = clamp_value(key, int(value))
	return true

func save() -> bool:
	var config := ConfigFile.new()
	config.load(path)                  # keep the modern [Display] / [Audio] sections (display.gd)
	for key in values: config.set_value(SECTION, key, int(values[key]))
	return config.save(path) == OK

static func clamp_value(key: String, value: int) -> int:
	if not RANGES.has(key): return value
	return clampi(value, int(RANGES[key][0]), int(RANGES[key][1]))

func get_value(key: String) -> int:
	return int(values.get(key, DEFAULTS.get(key, 0)))

func set_value(key: String, value: int):
	values[key] = clamp_value(key, value)

func snapshot() -> Dictionary:
	return values.duplicate()

func restore(copy: Dictionary):
	values = copy.duplicate()

## 0x4101e0 thresholds of the SFX label: Off (0), Low (< 31), Medium (< 61), High (< 91), Full.
static func sfx_level(volume: int) -> int:
	if volume == 0: return 0
	if volume < 0x1f: return 1
	if volume < 0x3d: return 2
	if volume < 0x5b: return 3
	return 4

## Game-clock milliseconds for real milliseconds at match speed `speed` (0x60c3ee: 0 paused, 1..5).
static func scaled_ms(real_ms: int, speed: int) -> int:
	match speed:
		1: return real_ms >> 1
		2: return (real_ms * 3) >> 2
		3: return real_ms
		4: return (real_ms >> 1) + real_ms
		5: return real_ms * 2
	return 0

# ------------------------------------------------------------------------------------------------ option screen rows
## One row per droplist (BUTT_OPTIONS_DROPLIST #0..9) of each page. "key" is the value, "choices" the dropdown list in its
## order with the value each choice stores, "label" builds the button text from the XCI strings (layout.strings) and
## Game.txt (game_text). An empty key is an empty, disabled row.
static func page_rows(page: int) -> Array:
	match page:
		0: return [   # Gameplay, 0x410760
			{"key": "HelpLevel", "choices": [[0x107, 2, 0], [0x107, 1, 1], [0x107, 0, 2]]},
			{"key": "ScrollRate", "format": [0x107, 3], "choices": [[0x108, 0, 1], [0x108, 1, 2], [0x108, 2, 3], [0x108, 3, 4], [0x108, 4, 5]]},
			{"key": "GameSpeed", "format": [0x107, 4], "choices": [[0x108, 0, 0], [0x108, 1, 1], [0x108, 2, 2], [0x108, 3, 3], [0x108, 4, 4]]},
			{"key": "DefaultGroupMovement", "choices": [[0x107, 5, 1], [0x107, 6, 0]]},
			{"key": "SpacebarPauses", "choices": [[0x112, 0, 1], [0x112, 1, 0]]},
			{"key": "RightClickInterface", "choices": [[0x112, 2, 1], [0x112, 3, 0]]},
			{"key": "SystemVoice", "choices": [["game", 751, 0], ["game", 752, 1]]},
			{"key": "TipOfTheDay", "choices": [[0x138, 2, 1], [0x138, 3, 0]]},
			{"key": ""}, {"key": ""}]
		1: return [   # Graphics, 0x410af0
			{"key": "ResolutionSelected", "format": [0x10a, 0], "choices": [[0xab, 0, 0], [0xab, 1, 1], [0x102, 0, 2], [0x102, 1, 3]]},
			{"key": "Shadows", "format": [0x10a, 1], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "AmbientAnimation", "format": [0x10a, 2], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "Blood", "format": [0x10a, 3], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "GammaCorrection", "format": [0x10a, 4], "choices": [[0x10e, 0, 0], [0x10e, 1, 1], [0x10e, 2, 2], [0x10e, 3, 3], [0x10e, 4, 4]]},
			{"key": "FloatingText", "choices": [[0x15a, 0, 1], [0x15a, 1, 0]]},
			{"key": "ParticleEffectLevel", "format": [0x10a, 6], "choices": [[0x108, 5, 0], [0x10e, 5, 1], [0x10e, 6, 2], [0x10e, 7, 3]]},
			{"key": "Decals", "format": [0x10a, 7], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "LightingEffects", "format": [0x10b, 0], "choices": [[0x108, 5, 0], [0x10e, 5, 1], [0x10e, 6, 2], [0x10e, 7, 3]]},
			{"key": "MouseEffects", "choices": [[0x10b, 1, 1], [0x10b, 2, 0]]}]
		_: return [   # Sound, 0x4101e0
			{"key": "EnvironmentalSounds", "format": [0x10c, 1], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "FootSteps", "format": [0x10c, 2], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "OverallVolume", "format": [0x10c, 3], "choices": [[0x109, 0, 0], [0x109, 1, 30], [0x109, 2, 60], [0x109, 3, 90], [0x109, 4, 120]]},
			{"key": "MusicVolume", "format": [0x10c, 4], "choices": [[0x109, 0, 0], [0x109, 1, 1], [0x109, 2, 2], [0x109, 3, 3], [0x109, 4, 4]]},
			{"key": "CombatSounds", "format": [0x10c, 5], "choices": [[0x108, 6, 1], [0x108, 5, 0]]},
			{"key": "UnitSpeech", "choices": [[0x10d, 0, 0], [0x10d, 1, 1], [0x10d, 2, 2]]},
			{"key": "EAXOn", "format": [0x10c, 6], "disabled": true, "choices": []},   # no EAX provider (0x74a808 = 0): "N/A", disabled
			{"key": "VictoryDefeatBuildup", "choices": [[0x10d, 3, 1], [0x10d, 4, 0]]},
			{"key": "HeroHeartbeat", "choices": [[0x10d, 5, 1], [0x10d, 6, 0]]},
			{"key": "Soundtrack", "disabled": true, "choices": []}]   # the soundtrack list (Music/*.ini): one soundtrack

## Index of the choice that shows the current value (SFX by its threshold).
func choice_index(row: Dictionary) -> int:
	var key := String(row.key)
	var value := get_value(key)
	if key == "OverallVolume": return sfx_level(value)
	var choices: Array = row.choices
	for i in choices.size():
		if int(choices[i][2]) == value: return i
	return 0
