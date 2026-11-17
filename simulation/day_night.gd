extends RefCounted
## B1-3 (B1_3_RESEARCH.md section 3): day and night. In the original every match has a weather object (DAT_00a38cc0,
## made by 0x498b10) whose clock bytes +0x2b5f7 (hour), +0x2b5f8 / +0x2b5f9 (two marks) decide "day" (0x499a00) and "night"
## (0x499a50). A match starts by day. Nothing advances the hour in a skirmish (the cycle flag +0x2b5f6 is only set by a
## saved game; the random weather of More Options, 0x49e360, is not reconstructed): day turns to night and back only by
## the spell record kind 4 (0x4ac0e0 case 4): the Undead Dark Citadel (amount 2 / 3), the Knights' Rites of Dawn (amount 0)
## and hero spells (B1-6). A record starts a transition (0x499970 to night, 0x4998e0 to day): four lighting levels a few
## ticks of the 50 ms panel timer apart (0x49b630 -> 0x49b070), and only its last tick switches the clock.
##
## Evidence: tests/day_night_fixtures.json (tools/emulate_day_night.py, Emulated): the two tests over every hour and mark
## pair, both transitions tick by tick (n = 2, 3), the combat getter 0x51bd10 with the weather object for every STATUS bit,
## the regeneration entry 0x51b820 and the palette levels 3 / 4 / 5. The kind-4 applier, the buttons and the computer's
## Rites of Dawn are Read.
##
## DELIBERATE MODERN CHANGE (the setting, DISPLAY_SETTINGS.md): Options > Gameplay "Day / Night: On / Off". On (default)
## is the original. Off removes the weather object's terms (as DAT_00a38cc0 = 0, the rebuild before B1-3): never night, no
## time-of-day combat terms, no Undead daytime rule; Dark Citadel and Rites of Dawn stay disabled (they test the clock).
## Stored in the [Modern] section of user://settings.cfg as "DayNight"; headless runs keep the default (on) unless the
## command line says `--day-night=off`.
##
## Provisional: the transition ticks follow the game clock in 50 ms steps (the original's panel timer is real time,
## SetTimer(1, 50), 50-62.5 ms per tick). The spell records' rain half (amounts 1 / 3 / 4 / 5 start rain, 0 / 2 stop it,
## REVIEW_BATCH3.md R2) is ported with B3-1 (apply_record).
##
## Setup rows (SKIRMISH_RESEARCH.md "Setup rows", tests/setup_rows_fixtures.json, Emulated): the weather roll 0x49e360,
## which runs in every match (More Options "Random Weather", 0x749c60 byte 0, only changes its chances and lets it start
## from a clear day), the weather message 0x1ff's applier 0x49e690, and the rain it starts: +0x2b5c0 (raining), +0x2b61c
## (storm), the drop target +0x2b5c4, count +0x2b5ea and floor +0x2b61e, the stop flag +0x2b5c6 (0x499aa0, the six setters
## 0x49bf10 .. 0x49c0a0, 0x49bd90 and the draw 0x49b6d0's count). Provisional: the draw runs once per 50 ms tick here (the
## original draws every frame of the view, 0x48fb80, which also runs 0x49b630); the message 0x1ff is applied at once (the
## original sends it through the lockstep queue 0x4b1170); the drops' positions (0x49b920 draws the game generator for
## each drop it places) are not simulated, so rain draws nothing from the match generator.

const GameSettings = preload("res://simulation/game_settings.gd")

const TICK_MS := 50                       # panel event 9 (SetTimer(hWnd, 1, 50), ENCOUNTERS_RESEARCH.md): 0x49b630
const HOURS := 24
const DAY_CLOCK := [1, 2, 0]              # 0x498b10 / 0x49b070 after a dawn: hour 1, marks 2 and 0
const NIGHT_CLOCK := [1, 0, 2]            # 0x49b070 after a dusk
const LEVELS := [0, 4, 5, 3]              # +0x2b5f2..+0x2b5f5 (0x498b10): the palette levels of a dusk, reversed for a dawn
const RECORD_STEPS := 3                   # 0x4ac0e0 case 4 calls 0x499970(3) / 0x4998e0(3): 13 ticks per level
const DARK_CITADEL_CRYSTAL := 100         # LAB_004d1300: crystal >= 100, message 0x1fe pays, then a kind-4 record
const RITES_CRYSTAL := 40                 # LAB_004d11b0: crystal >= 40
const RECORD_EFFECT := "EZ19"             # both records: effect +0x8d 'EZ19', kind +0x95 = 4

static var setting := true
static var loaded_from := ""
static var override = null

## Clock (+0x2b5f7 hour, +0x2b5f8 mark A, +0x2b5f9 mark B) and transition state.
var enabled := true                       # the weather object exists (the setting's value at the match start)
var hour := 1
var mark_a := 2
var mark_b := 0
var mode := 0                             # +0x2b5f0: 0 none, 1 dusk (0x499970), 2 dawn (0x4998e0)
var step := 0                             # +0x2b5f1: the level index reached
var counter := 0                          # +0x2b5fc: ticks since the transition began
var step_ticks := 1                       # +0x2b5e8: (n * 18) / 4 ticks per level
var level := 0                            # *DAT_00a38b98: the palette lighting level the renderer draws with
var target := 0                           # +0x2b604: the level a transition ends on (3 night, 0 day)
var raining := false                      # +0x2b5c0 (0x49bb10): set by the weather roll's rain (setup rows)
var storm := false                        # +0x2b61c: lightning and thunder (presentation) and the state code 0x49e320
var rain_target := 0                      # +0x2b5c4: the drop count the rain moves to (300 at the start, else the setter's)
var drops := 0                            # +0x2b5ea
var rain_floor := 0                       # +0x2b61e: the count a stopping rain ends at
var rain_step := 0                        # +0x2b620: drops added / removed per draw
var stopping := false                     # +0x2b5c6 (0x49bd90)
var random_weather := false               # 0x749c60 byte 0: More Options "Random Weather"
var weather_timer_ms := 0                 # +0x1cd628: the roll is due at this + 100 000 (0x498b10 sets the creation time)
var clock_ms := 0                         # the game clock of the last tick (DAT_00a27db0 for the setters' timer writes)
var rng                                   # the match generator 0x458e70 (CombatRng; not saved, set again by main.gd)
var next_tick_ms := 0
var log: Array = []                       # [{"ms", "event"}] for the checks

signal changed(night: bool)               # the clock switched (the last tick of a transition)

# ------------------------------------------------------------------------------------------------ the setting
static func ensure_loaded():
	if loaded_from != GameSettings.file_path: load_setting()

static func load_setting():
	loaded_from = GameSettings.file_path
	setting = true
	var config := ConfigFile.new()
	if DisplayServer.get_name() != "headless" and config.load(loaded_from) == OK:
		setting = bool(config.get_value("Modern", "DayNight", true))
	override = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--day-night="): override = arg.get_slice("=", 1) != "off"

static func setting_on() -> bool:
	ensure_loaded()
	return bool(override) if override != null else setting

static func set_setting(on: bool):
	ensure_loaded()
	override = null
	setting = on

static func save_setting() -> bool:
	var config := ConfigFile.new()
	config.load(GameSettings.file_path)
	config.set_value("Modern", "DayNight", setting)
	return config.save(GameSettings.file_path) == OK

## The Gameplay row (options_screen.gd, BUTT_OPTIONS_DROPLIST #10, the original's style).
static func gameplay_row() -> Dictionary:
	return {"key": "DayNight", "modern": true, "label": "Day / Night: %s", "choices": [["On", true], ["Off", false]],
		"current": 0 if setting_on() else 1}

# ------------------------------------------------------------------------------------------------ the clock
func _init(on: bool = true):
	enabled = on

## 0x499a00: from the hour forward, mark A comes before mark B (false at mark B itself).
static func day_test(h: int, a: int, b: int) -> bool:
	if h == b: return false
	var x := h
	while true:
		if x == a: break
		x = (x + 1) % HOURS
		if x == b: break
	return x != b

## 0x499a50: from the hour forward, mark B comes before mark A (true when the hour is mark B).
static func night_test(h: int, a: int, b: int) -> bool:
	var x := h
	if x != b:
		while true:
			if x == a: break
			x = (x + 1) % HOURS
			if x == b: break
	return x != a

## What the consumers ask: false for both while the setting is off (no weather object).
func is_day() -> bool:
	return enabled and day_test(hour, mark_a, mark_b)

func is_night() -> bool:
	return enabled and night_test(hour, mark_a, mark_b)

## 0x499970(n): dusk. The first level now, the clock at the end (0x49b070).
func to_night(n: int = RECORD_STEPS):
	if not enabled: return
	step = 0
	step_ticks = maxi(1, (n * 18) / 4)
	mode = 1
	counter = 0
	level = LEVELS[0]
	target = 0
	weather_timer_ms = clock_ms               # 0x499970 ends with +0x1cd628 = DAT_00a27db0
	log.append({"event": "dusk"})

## 0x4998e0(n): dawn.
func to_day(n: int = RECORD_STEPS):
	if not enabled: return
	mode = 2
	step_ticks = maxi(1, (n * 18) / 4)
	counter = 0
	step = 0
	level = LEVELS[3]
	target = 3
	weather_timer_ms = clock_ms               # 0x4998e0 likewise
	log.append({"event": "dawn"})

## 0x49b630 without the hour cycle (+0x2b5f6 is never set in a skirmish): one panel tick. Setup rows: the panel event
## first runs the weather roll 0x49e360 (decompile 23205), the view's draw then the rain's count 0x49b6d0.
func tick():
	if rng != null: weather_roll(clock_ms)
	if mode != 0: _transition_tick()
	rain_frame()

## 0x49b070.
func _transition_tick():
	counter += 1
	var k: int = counter / step_ticks
	if k == step: return
	if k < 4:
		level = LEVELS[3 - k] if mode == 2 else LEVELS[k]
		target = level
		step = k
		return
	if mode == 2:
		hour = DAY_CLOCK[0]; mark_a = DAY_CLOCK[1]; mark_b = DAY_CLOCK[2]
	else:
		hour = NIGHT_CLOCK[0]; mark_a = NIGHT_CLOCK[1]; mark_b = NIGHT_CLOCK[2]
	var night := mode == 1
	mode = 0
	counter = 0
	log.append({"event": "night" if night else "day"})
	changed.emit(night)

## Advance the panel ticks to `now_ms` (game clock, Provisional).
func update(now_ms: int):
	if not enabled: return
	if next_tick_ms == 0: next_tick_ms = now_ms + TICK_MS
	while next_tick_ms <= now_ms:
		clock_ms = next_tick_ms
		tick()
		next_tick_ms += TICK_MS

## 0x4ac0e0 case 4 (Read): a weather record's amount. 0 / 1 / 4: dawn when it is night; 2 / 3 / 5: dusk when it is not
## night. B3-1 (REVIEW_BATCH3.md R2, Emulated: tests/batch3_review_fixtures.json "rain", "rain_end"): the one path of every kind-4
## record (Dark Citadel, Rites of Dawn, Stormcall and the spells). 0x4aa840 case 4 drops the record while a fade runs (+0x2b5f0,
## decompile 115160-115163): nothing happens. Then the rain: 0 / 2 stop it (0x49bd90: the stop flag, while raining); 1 / 3 start it
## unless it rains (0x49bf60: drops 30 towards 300, floor 0x50); 4 / 5 a storm unless it rains (0x49bf60 with 0x96, then 0x49c0a0:
## target 0x50, lightning). Rain has no natural end. Returns false when the record was dropped.
func apply_record(amount: int) -> bool:
	if not enabled: return false
	if mode != 0: return false
	match amount:
		0, 1, 4:
			if is_night(): to_day(RECORD_STEPS)
		2, 3, 5:
			if not is_night(): to_night(RECORD_STEPS)
	match amount:
		0, 2:
			if raining: stopping = true
		1, 3:
			if not raining: set_rain(0x50, false)
		4, 5:
			if not raining:
				set_rain(0x96, false)
				set_rain(0x50, true)
	return true

# ------------------------------------------------------------------------------------------------ setup rows: weather
## 0x49e320: the weather state code: 7 by night, + 1 while raining, + 4 instead when it storms as well (0, 1, 4, 7, 8, 11).
func state_code() -> int:
	var code := 7 if is_night() else 0
	if raining: code += 4 if storm else 1
	return code

const ROLL_PERIOD_MS := 100000            # 0x49e360: due at +0x1cd628 + 100 000, then +0x1cd628 = now + 100 000
const CHANCES := [[15, 30, 18, 8], [12, 25, 20, 10]]   # the four chance draws (< value), Random Weather off / on
const KINDS := [2, 1, 0xff, 0xfe]
## 0x49e360's switch (Emulated, every state x kind): state code -> {kind: new code}; -1 = the last draw decides
## (<= 74 night, else rain). A new code equal to the old one sends nothing.
const ROLL_TABLE := {0: {1: 0, 2: 0, 0xff: -1, 0xfe: 13}, 1: {1: 0, 2: 0, 0xff: 2, 0xfe: 6}, 4: {1: 0, 2: 0, 0xff: 5, 0xfe: 6},
	7: {1: 0, 2: 0, 0xff: 8, 0xfe: 10}, 8: {1: 0, 2: 0, 0xff: 9, 0xfe: 10}, 11: {1: 8, 2: 1, 0xff: 12, 0xfe: 13}}

## 0x49e360(now) (Emulated): host only (the rebuild is the host). A clear day only rolls with Random Weather; otherwise up
## to four chance draws 1..100 and one more draw, all from the match generator; a changed code is message 0x1ff.
## Returns the new code sent, or -1.
func weather_roll(now_ms: int) -> int:
	if not enabled or now_ms < weather_timer_ms + ROLL_PERIOD_MS: return -1
	weather_timer_ms = now_ms + ROLL_PERIOD_MS
	var code := state_code()
	if code == 0 and not random_weather: return -1
	var chances: Array = CHANCES[1 if random_weather else 0]
	var kind := -1
	for i in 4:
		if int(rng.roll(1, 100, 0)) < int(chances[i]):
			kind = KINDS[i]
			break
	var last := int(rng.roll(1, 100, 0))
	if kind < 0 or not ROLL_TABLE.has(code): return -1
	var new_code: int = ROLL_TABLE[code][kind]
	if new_code < 0: new_code = 7 if last <= 74 else 1
	if new_code == code: return -1
	log.append({"event": "weather", "code": new_code, "ms": now_ms})
	apply_weather(new_code)
	return new_code

## The six rain setters of 0x49e690 (code % 7 = 1..6): drop level, storm.
const SETTERS := [[0, false], [0x50, false], [0x96, false], [0x200, false], [0x50, true], [0x96, true], [0x200, true]]

## 0x4a9a20 -> 0x49e690(code) (Emulated): codes 0..6 dawn when it is night, 7..13 dusk when it is not (0x4998e0 /
## 0x499970 with 3); then code % 7 = 0 stops the rain (0x49bd90), 1..6 a setter.
func apply_weather(code: int):
	if not enabled or code < 0 or code > 13: return
	if code >= 7:
		if not is_night(): to_night(RECORD_STEPS)
	elif is_night():
		to_day(RECORD_STEPS)
	var kind := code % 7
	if kind == 0:
		if raining: stopping = true
		return
	set_rain(int(SETTERS[kind][0]), bool(SETTERS[kind][1]))

## 0x49bf10 .. 0x49c0a0: dry -> 0x499aa0(0, level, 1) (drops 30 towards 300, the level is the floor); raining -> the level
## is the new target. Both set the storm flag and the roll's timer to now.
func set_rain(level: int, with_storm: bool):
	if not enabled: return
	if not raining:
		raining = true
		stopping = false
		rain_step = 1
		rain_floor = level
		rain_target = 300
		drops = 30
	else:
		rain_target = level
	storm = with_storm
	weather_timer_ms = clock_ms

## 0x49b6d0's drop count, once per draw: towards the target, or down to the floor when stopping; the rain ends there.
func rain_frame():
	if not raining: return
	if rain_target < rain_floor: rain_floor = rain_target
	var d := drops
	if not stopping and d < rain_target:
		drops = mini(d + rain_step, rain_target)
	elif (stopping or rain_target < d) and rain_floor < d:
		drops = d - rain_step
	if stopping and drops == rain_floor:
		raining = false
		log.append({"event": "rain over"})

# ------------------------------------------------------------------------------------------------ consumers
## 0x51bd10 (Emulated with the weather object, day_night_fixtures.json "combat"): the time-of-day and weather terms added
## to a unit's raw combat (+0x92) before the clamp at 1; the result is what replaces the raw combat. `shadow_strength` is a
## hero's skill 0x36 term (0x556b50 / 0x556ea0; heroes only, by night).
func combat_value(raw: int, flags: int, type_id: String, shadow_strength: int = 0) -> int:
	if not enabled: return raw
	var term := 0
	var value := raw
	if is_day():
		if (flags & 0x8) != 0 or (flags & 0x1000000) != 0: term = 1
	elif is_night():
		if (flags & 0x100) != 0 or (flags & 0x4) != 0: term = 2
		elif (flags & 0x20) != 0: term = 1
		elif (flags & 0x41) != 0: term = -1
		if type_id == "AUXX": term += 5
		value += shadow_strength
	if not raining:
		if (flags & 0x80010) != 0: term += 1
	elif (flags & 0x2) != 0:
		term -= 1
	elif (flags & 0x800004) != 0:
		term += 1
	return maxi(1, term + value)

## 0x51b820 (Emulated): by day a unit with STATUS 0x4 (Undead) does not regenerate; its timer is set 5 s ahead.
const UNDEAD_PAUSE_MS := 5000
func blocks_regeneration(flags: int) -> bool:
	return is_day() and (flags & 0x4) != 0

# ------------------------------------------------------------------------------------------------ the palette levels
## The palette builder's lighting levels (0x495xxx, 565 branch; Emulated: day_night_fixtures.json "palette"): every
## palette entry of the terrain and the sprites has eight levels, and the renderer (0x495c30) draws with level
## *DAT_00a38b98. Day is level 0 (the colours as they are); a dusk steps through 4, 5 and 3 (night), a dawn back.
## Level 3 = 0x48b010(5) + 0x48a930(3): five eighths of the brightness, red less by 3/32, blue raised by 3/16 of what is
## missing to full. night_light.gdshader applies the same integer operations to the world view (main.gd).
static func scale_down(x: int, n: int) -> int:          # 0x48b010 cases 5..7: x - x * (8 - n) / 8 per field
	match n:
		5: return (x - (((x & 0xf800) * 3 >> 3) & 0xf800) - (((x & 0x7e0) * 3 >> 3) & 0x7e0) - ((x & 0x1f) * 3 >> 3)) & 0xffff
		6:
			var u := x >> 2
			return (x - (u & 0x3800) - (u & 0x1e0) - (u & 7)) & 0xffff
		7:
			var u := x >> 3
			return (x - (u & 0x1800) - (u & 0xe0) - (u & 3)) & 0xffff
	return x

static func blue_shift(x: int, n: int) -> int:          # 0x48a930 cases 2 / 3
	match n:
		2: return (x + (((-x) >> 3) & 3) - ((x >> 4) & 0x800)) & 0xffff
		3: return ((((-x) & 0x1f) * 3 >> 4) - (((x & 0xf800) * 3 >> 5) & 0xf800) + x) & 0xffff
	return x

static func red_shift(x: int, n: int) -> int:           # 0x48a330 cases 2 / 3
	match n:
		2: return ((((-x) >> 4) & 0x800) - ((x >> 4) & 0x60) - ((x >> 4) & 1) + x) & 0xffff
		3:
			var r := (((-x) & 0xf800) * 3 >> 5) & 0xf800
			var g := ((x & 0x7e0) * 3 >> 5) & 0x7e0
			var b := (x & 0x1f) * 3 >> 5
			return (r - g - b + x) & 0xffff
	return x

## A 565 colour at a lighting level (0 and the levels the clock never uses return it unchanged).
static func light(colour: int, at_level: int) -> int:
	match at_level:
		3: return blue_shift(scale_down(colour, 5), 3)
		4: return red_shift(scale_down(colour, 7), 3)
		5: return blue_shift(red_shift(scale_down(colour, 6), 2), 2)
	return colour

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self, ["rng"])

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state, ["rng"])
