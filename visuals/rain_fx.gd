extends Node2D
## P-2 (EFFECTS_RESEARCH.md "P-2" item 5): the original's rain, storm flashes and rain sound for DayNight's simulated rain
## (day_night.gd: raining, storm, drops). Presentation only: it reads DayNight and never writes it; the drops and the flash
## draws use this layer's own generator (Deliberate: the original draws them from the match generator 0x458e70, which the
## rebuild's simulation does not do, so its stream is unchanged by rain either way).
## Read from the decompile:
## * 0x499aa0 (rain start, kind +0x2b5c1 = 0 from every setter): all 600 drop records marked landed; Rain.wav
##   ("SoundFX\WEATHER\Rain.wav", stream slot priority 0x3c) looped from volume 0; 0x49be40 sets its volume to
##   min(drops >> 4, 127) on each change, scaled by the effects volume 0x70d6c8 (0: 0, < 31: >> 2, < 91: >> 1, else full);
##   0x49b6d0 stops it when a stopping rain reaches its floor.
## * 0x49b6d0 per view draw: each of the `drops` records that landed (or left the view by 10 pixels) is placed again by
##   0x49b920 (kind 0): length L = 1d40, fall limit 4 L, a point in the view +- 10 pixels, fall 0, brightness shift s by
##   1d20: < 10 -> 3, < 17 -> 2, else 1. Then 0x49a790: every live drop falls 1d10 + 10 pixels, is drawn as L pixels
##   (x + fall / 2 + i / 2, y + fall + i), each pixel c + ((~c) >> s) per channel (towards white by 2^-s), and lands when
##   L + fall reaches its limit. 0x49bb20 restores the screen under the drops before the next draw.
## * 0x49b1d0 (per view draw, not while fog of war is on: it returns when 0x47f6a0 is set): with a storm, every third
##   call counts; after 1d(150 - drops / 4) + 12 counts a flash of 10 counts starts with Lightning<L|M|H><1d2>.wav (L
##   below 80 drops; M or 1 in 3 L below 150; else 1 in 6 L, 2 in 6 M, 3 in 6 H); each flash count sets the lighting level
##   to 2 when 1d800 < drops, else back to the clock's level.
## Provisional: the drops move once per 50 ms DayNight tick (the original moves them every view draw, whose rate is not
## fixed); the streak is drawn as a 1-pixel line; drops are drawn in world pixels over the fog overlay.
const DROP_RECORDS := 600
const LIGHTNING_LEVEL := 2

var main: Node
var rng := RandomNumberGenerator.new()
var records: Array = []                  # {x, y, length, limit, fall, shift, landed}
var raining_seen := false
var rain_channel := -1
var rain_volume := -1
var flash_counts := 0                    # DAT_00a38cbc
var flash_wait := -1                     # DAT_00a38cb0 (-1: not rolled yet, bit 0 of 0xa38cb4)
var flash_third := 0                     # DAT_00a38cb8
var flashing := false                    # +0x2b608
var flash_level := -1                    # the lighting level the flash draws with, -1 none
var next_tick_ms := 0

func _ready():
	z_index = 4002
	z_as_relative = false
	rng.seed = 0x49b920

func reset_records():
	records.clear()
	for i in DROP_RECORDS: records.append({"x": 0, "y": 0, "length": 0, "limit": 0, "fall": 0, "shift": 1, "landed": true})

## 1..n like 0x458e70(1, n, 0).
func roll(n: int) -> int:
	return rng.randi_range(1, maxi(1, n))

## 0x49b920 for kind 0 in a view of `view` (world pixels).
func place(d: Dictionary, view: Rect2):
	d.length = roll(0x28)
	d.limit = int(d.length) << 2
	d.x = roll(int(view.size.x) + 0x14) + int(view.position.x) - 10
	d.y = roll(int(view.size.y) + 0x14) + int(view.position.y) - 10
	d.fall = 0
	d.landed = false
	var r := roll(0x14)
	d.shift = 3 if r < 10 else (2 if r < 0x11 else 1)

## 0x49a790's move of one drop.
func fall(d: Dictionary):
	d.fall = (int(d.fall) + roll(10) + 10) & 0xff
	if int(d.limit) <= int(d.length) + int(d.fall): d.landed = true

static func lightning_letter(drops: int, r3: int, r6: int) -> String:
	if drops < 0x50: return "L"
	if drops <= 0x95: return "L" if r3 == 1 else "M"
	if r6 == 1: return "L"
	return "M" if r6 == 2 or r6 == 3 else "H"

static func rain_sound_volume(drops: int, effects_volume: int) -> int:
	var v := mini(drops >> 4, 0x7f)
	if effects_volume == 0: return 0
	if effects_volume < 0x1f: return v >> 2
	if effects_volume < 0x5b: return v >> 1
	return v

func _audio():
	return main.get("audio") if main != null else null

func _sound_id(base: String) -> String:
	var audio = _audio()
	if audio == null: return ""
	for prefix in ["weather/", "sfx/"]:
		if audio.has_sound(prefix + base): return prefix + base
	return ""

## 0x49b1d0 (one call).
func lightning(day_night, fog_on: bool):
	if fog_on: return
	if not day_night.raining or not day_night.storm:
		flashing = false
		flash_level = -1
		return
	if flash_wait < 0: flash_wait = roll(0x96 - (int(day_night.drops) >> 2)) + 0xc
	flash_third = (flash_third + 1) % 3
	if flash_third != 0: return
	if flashing:
		flash_counts += 1
		if flash_counts != 10:
			flash_level = LIGHTNING_LEVEL if roll(800) < int(day_night.drops) else -1
			return
		flash_counts = 0
		flash_wait = roll(0x96 - (int(day_night.drops) >> 2)) + 0xc
		flashing = false
		flash_level = -1
		return
	flash_counts += 1
	if flash_counts != flash_wait: return
	flashing = true
	flash_counts = 0
	var letter := lightning_letter(int(day_night.drops), roll(3), roll(6))
	var id := _sound_id("Lightning%s%d" % [letter, roll(2)])
	var audio = _audio()
	if id != "" and audio != null: audio.play(id, 0x8c, 0x7f)

func _update_sound(day_night):
	var audio = _audio()
	if audio == null: return
	if not day_night.raining:
		if rain_channel >= 0: audio.stop_channel(rain_channel)
		rain_channel = -1
		rain_volume = -1
		return
	var v := rain_sound_volume(int(day_night.drops), int(audio.effects_volume))
	if rain_channel < 0:
		var id := _sound_id("Rain")
		if id == "": return
		rain_channel = audio.play(id, 0x3c, v, 64.0, false, true, true)
		rain_volume = v
	elif v != rain_volume:
		audio.set_channel(rain_channel, v, 64.0)
		rain_volume = v

## Every frame: one tick per 50 ms of the game clock (DayNight's own ticks).
func step(now_ms: int, day_night, view: Rect2, fog_on: bool):
	if day_night == null or not day_night.enabled:
		visible = false
		return
	if not raining_seen and day_night.raining: reset_records()
	raining_seen = day_night.raining
	_update_sound(day_night)
	if next_tick_ms == 0 or now_ms < next_tick_ms - 1000: next_tick_ms = now_ms
	var ticked := false
	while next_tick_ms <= now_ms:
		next_tick_ms += 50
		ticked = true
		lightning(day_night, fog_on)
		if not day_night.raining: continue
		if records.is_empty(): reset_records()
		var count := mini(int(day_night.drops), DROP_RECORDS)
		for i in count:
			var d: Dictionary = records[i]
			var out := int(d.y) + int(d.fall) >= view.end.y + 10 or int(d.x) + (int(d.fall) >> 1) >= view.end.x + 10 \
				or int(d.y) + int(d.fall) + int(d.length) < view.position.y - 10 or int(d.x) + ((int(d.length) + int(d.fall)) >> 1) < view.position.x - 10
			if bool(d.landed) or out: place(d, view)
			fall(d)
	visible = day_night.raining
	if ticked and visible: queue_redraw()

func _draw():
	if main == null or main.get("day_night") == null: return
	var count := mini(int(main.day_night.drops), records.size())
	for i in count:
		var d: Dictionary = records[i]
		if int(d.length) <= 0: continue
		var top := Vector2(int(d.x) + (int(d.fall) >> 1), int(d.y) + int(d.fall))
		var colour := Color(1, 1, 1, 1.0 / float(1 << int(d.shift)))
		draw_line(top, top + Vector2(int(d.length) >> 1, int(d.length)), colour, 1.0)
