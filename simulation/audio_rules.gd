extends RefCounted
## Original sound rules (AUDIO_RESEARCH.md). Every function here is checked against tests/audio_fixtures.json, which
## tools/emulate_audio.py records by running the unmodified executable under Unicorn (Emulated).

const UPDATE_MS := 25          # the sound tick 0x50ea10 runs once per 25 ms game update (0x5468e0)
const WINDOW := 25             # positional sounds play only within |dx| < 25 and |dy| < 25 cells of the camera centre
const CHANNELS := 16           # 0x4c8fc0(16): DIG_MIXER_CHANNELS (8 with the low-quality flag 0xa27d61)
const ACK_COOLDOWN := 90       # 0xb90fa0+0x188 must exceed 90 updates (select, order, building select)
const DEATHBLOW_COOLDOWN := 30 # same counter, > 30
const DEATH_COOLDOWN := 30     # +0x18c > 30 (0x50edd0)
const SPEECH_COOLDOWN := 10    # +0x190 > 10 (0x50f1b0)
## Playtest 2026-11-12 ("your troops are under attack" without end): a speech asked in the no-repeat mode (ids 0, 1, 3,
## 5, 28) is refused by the selector 0x510f90 while its loaded sample's age word (0xafd084) is below 0x15; every pick
## resets the age to 0. The ages are raised by 0x511bd0, reached from the idle callback 0x458d20 on every 18th call
## (counter 0xa27d74); that callback runs from the window procedure's timer case (SetTimer 50 ms, 0x45a179), so one age
## step is 900 ms and a no-repeat speech returns after 21 steps, about 19 s (Read; the timer case is Provisional). A
## sample not yet loaded plays at once (the test reads only loaded samples).
const SPEECH_AGE_STEP_MS := 18 * 50
const SPEECH_NO_REPEAT_AGE := 0x15
static func speech_age_ok(last_step: int, step: int) -> bool:
	return last_step < 0 or step - last_step >= SPEECH_NO_REPEAT_AGE
const READY_COOLDOWN := 15     # +0x194 > 15 (0x50c790)
const PAN_K_800 := 25          # 0x50f020 for the 800 x 600 mode (30 / 35 / 40 at 1024 / 1280 / 1600)

# Priorities passed to the mixer (0x4ca480 second argument).
const PRIORITY := {"voice": 100, "work_voice": 130, "ambient_voice": 10, "deathblow": 30, "attack": 30, "death": 30,
	"missile": 10, "speech": 141, "ui": 20, "movement": 10, "fire": 70, "heartbeat": 140, "collapse": 141, "terrain": 60,
	"building_select": 100, "positional": 140}

## 0x50ee90: 25 volumes indexed by the distance in cells; entry 24 is silent.
static func volume_table(effects_volume: int) -> PackedInt32Array:
	# fild volume; fmul 1/127 (the float32 at 0x5ea564); fimul (125 - 5 i); __ftol truncates. The emulated results
	# match single-precision intermediates (127 gives 125, 120, ... not 124, 119, ...).
	var out := PackedInt32Array()
	var scale := _f32(float(effects_volume) * 0.007874015718698502)
	for i in 25:
		out.append(int(_f32(scale * float(125 - 5 * i))) if i < 24 else 0)
	return out

static func _f32(value: float) -> float:
	var a := PackedFloat32Array([value])
	return a[0]

## 0x50eef0: 50 pan values, 3 + alternating steps of 2 and 3 (3, 5, 8, 10, ... 125), clamped at 127.
static func pan_table() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var value := 0.0
	var step := 3.0
	for i in 50:
		value += step
		out.append(minf(value, 127.0))
		step = 2.0 if step == 3.0 else 3.0
	return out

## 0x50ef50: Chebyshev distance from the camera centre cell, clamped to 0..24.
static func distance_index(cam: Vector2i, cell: Vector2i) -> int:
	return clampi(maxi(absi(cam.x - cell.x), absi(cam.y - cell.y)), 0, 24)

## 0x50f020: effect pan index. k = 25 / 30 / 35 / 40 for the 800 / 1024 / 1280 / 1600 modes.
static func pan_index(cam_x: int, x: int, k: int = PAN_K_800) -> int:
	var i: int = absi(x - cam_x) if cam_x == k else (k - cam_x) + x
	return clampi(i, 0, 49)

## 0x50efa0: voice pan index (select / order / ready); a dead zone pulls the near-centre columns inwards.
static func voice_pan_index(cam_x: int, x: int) -> int:
	var i: int
	if cam_x == 25: i = 25 - x if x < 25 else x - 25
	else: i = x - cam_x + 25
	if i < 0: return 0
	if i > 49: return 49
	if i == 12: return 0
	if i == 36: return 49
	if i > 12 and i < 22: return i - 5
	if i > 29 and i < 36: return i + 5
	return i

## Variant thresholds of 0x50c2e0 (select) and 0x50c530 (order), for 2, 3 and 4 variants: variant k (highest first) is
## chosen when roll > threshold[k] and the previous variant was not k; otherwise 1, or 2 when the previous was 1.
const VARIANT_THRESHOLDS := {
	"select": {2: [55], 3: [40, 70], 4: [40, 60, 72]},
	"order": {2: [55], 3: [50, 90], 4: [45, 80, 92]},
}

## Returns [variant, new_last]. count: ARM +0x106 (4 for heroes, +0x211). roll: 0x458e70(1, 100, 0) of the match RNG.
static func choose_variant(kind: String, count: int, last: int, roll: int) -> Array:
	if count <= 0: return [0, last]
	if count == 1: return [1, last]
	var thresholds: Array = VARIANT_THRESHOLDS[kind][mini(count, 4)]
	for k in range(thresholds.size() + 1, 1, -1):
		if roll > int(thresholds[k - 2]) and last != k:
			return [k, k]
	var variant := 1 if last != 1 else 2
	return [variant, variant]

## 0x50f1b0: advisor speech gate. Returns {"play", "no_repeat", "counter", "repeat_value"}.
## Ids 3, 4, 5, 6, 10, 11, 12, 13, 25 bypass the cooldown; id 2 plays once per distinct repeat_value (the player's
## 0x709108 word); ids 0, 1, 3, 5, 28 ask the selector for its no-repeat mode.
const SPEECH_FORCED := [3, 4, 5, 6, 10, 11, 12, 13, 25]
const SPEECH_NO_REPEAT := [0, 1, 3, 5, 28]
static func speech_gate(id: int, counter: int, last_repeat_value: int, repeat_value: int) -> Dictionary:
	if id in SPEECH_FORCED: counter = 11
	var out := {"play": false, "no_repeat": false, "counter": counter, "repeat_value": last_repeat_value}
	if counter <= SPEECH_COOLDOWN: return out
	out.counter = 0
	if id == 2:
		if last_repeat_value == repeat_value: return out
		out.repeat_value = repeat_value
	out.play = true
	out.no_repeat = id in SPEECH_NO_REPEAT
	return out

## Parity pass 2 (AUDIO_RESEARCH.md): 0x52b18x / 0x4af38x: a building attacked within 20 cells (exclusive) of home speaks
## 0 ("base under attack"), elsewhere 28.
static func building_attack_speech(cell: Vector2i, home: Vector2i) -> int:
	if home.x - 0x14 < cell.x and cell.x < home.x + 0x14 and home.y - 0x14 < cell.y and cell.y < home.y + 0x14: return 0
	return 0x1c

## 0x524450: price lanes (gold, metal, crystal, stone) above the stock speak in the order crystal 0x14, metal 0x13,
## gold 0x11, stone 0x12.
static func resource_shortage_speech(price: Array, stock: Array) -> Array:
	var out: Array = []
	if int(stock[2]) < int(price[2]): out.append(0x14)
	if int(stock[1]) < int(price[1]): out.append(0x13)
	if int(stock[0]) < int(price[0]): out.append(0x11)
	if int(stock[3]) < int(price[3]): out.append(0x12)
	return out

## 0x436500: research complete -> speech 8, except PSPR / PPAR (0x438180: speech 9) and POMA / POMB / POMC / PQKN
## (handled before the speech: none).
static func research_speech(item: String) -> int:
	if item in ["PSPR", "PPAR"]: return 9
	if item in ["POMA", "POMB", "POMC", "PQKN"]: return -1
	return 8

## 0x4ca480: first free slot; otherwise the first slot (by index) that is neither protected nor a stream and whose
## priority is lower than the new one. slots: Array of null (free) or {"priority", "protected", "stream"}. -1: refused.
static func allocate(slots: Array, priority: int) -> int:
	for i in slots.size():
		if slots[i] == null: return i
	for i in slots.size():
		var s: Dictionary = slots[i]
		if not bool(s.get("protected", false)) and not bool(s.get("stream", false)) and int(s.priority) < priority:
			return i
	return -1

## In the positional window of the camera (strict, as 0x50cbf0 / 0x50d300 / 0x50f0a0 test it).
static func in_window(cam: Vector2i, cell: Vector2i) -> bool:
	return cam.x - WINDOW < cell.x and cell.x < cam.x + WINDOW and cam.y - WINDOW < cell.y and cell.y < cam.y + WINDOW

## 0x511c10 category 0: a building's own sound is its code with a level digit replaced by X (BKK0 -> BKKX), except
## for codes whose second letter is W unless the third is L (walls and gates keep the digit).
static func building_sound(code: String) -> String:
	if code.length() < 4: return code
	var c := code.substr(0, 4)
	if c[3] in ["0", "1", "2", "3", "4"] and (c[1] != "W" or c[2] == "L"): c = c.substr(0, 3) + "X"
	return c

## 0x50d300 / 0x524050 / 0x524090: Attack<class><variant>. class = ARM +0xd0 - 1 (0 when < 1; 14 for AGFX);
## variant only for classes 0..2: the target's ARM +0x108, or 3 for a building (5 for EDB1). AGFX: variant 1.
static func attack_sound(attacker_code: String, attacker_attack: int, target_kind: String, target_struck: int, target_code: String) -> String:
	var cls := 14 if attacker_code == "AGFX" else (0 if attacker_attack < 1 else attacker_attack - 1)
	var variant := 0
	if cls < 3:
		if target_kind == "building": variant = 5 if target_code == "EDB1" else 3
		else: variant = target_struck
	elif cls == 14:
		variant = 1
	return "Attack%d%d" % [cls, variant]       # "Attack" + itoa(class) + itoa(variant): Attack01, Attack70, Attack141

## Volume 0..127 (Miles linear) to decibels for Godot. Decision: Miles' 0..127 scale treated as linear amplitude.
static func volume_db(volume: int) -> float:
	if volume <= 0: return -80.0
	return linear_to_db(clampf(float(volume) / 127.0, 0.0, 1.0))

## Miles pan 0..127 (64 centre) to an AudioEffectPanner value -1..1.
static func panner(pan: float) -> float:
	return clampf((pan - 64.0) / 64.0, -1.0, 1.0)
