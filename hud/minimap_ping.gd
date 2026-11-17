extends RefCounted
## P-1 (EFFECTS_RESEARCH.md "P-1"): the strategic-map alert 0x4dcf70 and its drawing in 0x4dc850. Presentation only.
## * 0x4dcf70(cell x, y, push) (Read, wbc3_decomp.c 143865): with `push` the cell also goes to the alert list (0x425b90,
##   main.gd push_alert, the alert key). The cell becomes a strategic-map point (x 2 on a 64 map, x 2/3 on 192, / 2 on 256)
##   and, unless a ping is running (0xa4797a), a 64 x 64 box centred on it, clipped to the 128 x 128 map, starts.
## * 0x4dc850 (Read, 143732; called by the 25 ms game update 0x458bb0): per update the counter +0xb8 rises; at 1..16 frame
##   counter of BM_INFOBOX (XCG 0x6d, esibi.bmp: 18 frames of 64 x 64, a red square shrinking) is blitted into the map's
##   info layer (0x6e) at the box; the last frame stays until 100, when frame 17 (empty) clears it and the ping ends.
## Callers that push (Read): the speech-gated alerts of 0x522860 (an own unit hurt out of view), 0x52b180 (an own building
## hurt), 0x5210b0 (a hero fell, speech 4 / 6 / 0x19), 0x520c90 (a conversion); without push: 0x52bfd0 (an own building
## completed).
const FRAME := 64
const LAST_FRAME := 16
const END_COUNT := 100
const TICK_MS := 25
const MAP := 128

var active := false                       # 0xa4797a
var counter := 0                          # +0xb8
var box := Rect2i()                       # destination (+0xc0, +0xbc) and size (+0xd0, +0xcc)
var source := Vector2i()                  # clip offset into the frame (+0xc8, +0xc4)
var next_ms := 0

## The map point of a cell (0x4dcf70's scaling by map size 0x490990; other sizes unchanged).
static func map_point(cell: Vector2i, map_height: int) -> Vector2i:
	match map_height:
		0x40: return cell * 2
		0xc0: return Vector2i(cell.x * 2 / 3, cell.y * 2 / 3)
		0x100: return Vector2i(cell.x >> 1, cell.y >> 1)
	return cell

## 0x4dcf70 without the alert list part. Returns whether a new ping started.
func ping(cell: Vector2i, map_height: int, now: int) -> bool:
	if active: return false
	var p := map_point(cell, map_height)
	active = true
	counter = 0
	next_ms = now + TICK_MS
	var dx := p.x - 32
	var dy := p.y - 32
	box.position = Vector2i(maxi(dx, 0), maxi(dy, 0))
	if dx < 0:
		source.x = -dx
		box.size.x = p.x + 32
	elif p.x + 32 < MAP:
		source.x = 0
		box.size.x = FRAME
	else:
		source.x = 0
		box.size.x = MAP - dx
	if dy < 0:
		source.y = -dy
		box.size.y = p.y + 32
	elif p.y + 32 <= 0x7f:
		source.y = 0
		box.size.y = FRAME
	else:
		source.y = 0
		box.size.y = MAP - dy
	return true

## 0x4dc850's part: one count per 25 ms game update.
func tick(now: int):
	while active and now >= next_ms:
		next_ms += TICK_MS
		counter += 1
		if counter == END_COUNT:
			counter = 0
			active = false

## The frame on show (-1: none): counts 1..16 blit that frame, it stays until the end.
func frame() -> int:
	if not active or counter < 1: return -1
	return mini(counter, LAST_FRAME)

## The source rectangle in esibi.bmp of the frame on show.
func source_rect() -> Rect2i:
	return Rect2i(Vector2i(frame() * FRAME + source.x, source.y), box.size)

func reset():
	active = false
	counter = 0
