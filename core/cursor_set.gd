extends Node
## The original mouse cursors (parity pass 1, UI_RESEARCH.md "Cursors").
##
## Read: the cursor is software drawn. 0x46c190(n) stores index n in the graphics object (+0x78) when cursor slot n has
## frames (+0x50 > 0); slot n is the n-th 0x11c record of War4Gfx.xcg (0x466970 reads them into slots 1..count, so the index
## equals the record id: 1 CURS_ARROW, 2 POINTER, 3 POINTERDOWN, 4 POINTERUP, 5 WAIT, 6 SELECT, 7 FIGHT, 8 WALK, 9 PATROL,
## 10 SPELL, 11 BLANK, 12 RUIN, 13 RESUMEBUILDING, 14 GUARD, 15 ARROWSWORD, 16 ARROWBOOK). The draw (0x46c9b0): a new index
## restarts at frame 0; otherwise the frame advances (mod the frame count) when the deadline is reached, the deadline being
## the frame's delay (record +0x64 + 12 k) after the switch, or never when that delay is 0; the frame is the record's
## (x, y) cell of BM_CURSORS (Cursors.bmp, magenta key) of the record's size, drawn with its top-left at the mouse position
## minus the hotspot (+0x54, +0x58).
## Presentation (deliberate, labelled): the frame is handed to the operating system cursor (Input.set_custom_mouse_cursor),
## scaled by the shared view scale (display.gd, native resolution: DELIBERATE MODERN CHANGE), instead of being blitted into the back buffer; the image, hotspot and timing are the original's.
const Assets = preload("res://core/asset_store.gd")

var records := {}            # id -> {"size": Vector2i, "hotspot": Vector2i, "frames": [[x, y, delay], ...]}
var sheet: Image
var index := 1               # 0x78
var frame := 0               # 0x70
var deadline := -1           # 0x84: ms, -1 = hold
var scale_factor := 1.0
var _textures := {}
var _applied := ""

## A new scale drops the scaled frames (the window or the interface scale changed).
func set_scale(scale: float):
	if is_equal_approx(scale, scale_factor): return
	scale_factor = scale
	_textures.clear()
	_applied = ""
	apply()

func setup(layout: Dictionary, scale: float = 1.0):
	scale_factor = scale
	records = load_records(layout)
	var extra: Dictionary = layout.get("extra_bitmaps", {})
	if extra.has("Cursors.bmp"):
		var texture: Texture2D = Assets.texture(String(extra["Cursors.bmp"].file))
		if texture != null: sheet = texture.get_image()
	apply()

static func load_records(layout: Dictionary) -> Dictionary:
	var out := {}
	for c in layout.get("xcg", {}).get("cursors", []):
		out[int(c.id)] = {"name": String(c.name), "size": Vector2i(int(c.size[0]), int(c.size[1])),
			"hotspot": Vector2i(int(c.hotspot[0]), int(c.hotspot[1])), "frames": c.frames}
	return out

## 0x46c190: ignored when the slot has no frames.
func set_index(n: int):
	if not records.has(n) or (records[n].frames as Array).is_empty() or n == index: return
	index = n
	frame = 0
	_start_frame(Time.get_ticks_msec())
	apply()

func _start_frame(now: int):
	var delay := int(records[index].frames[frame][2]) if records.has(index) else 0
	deadline = now + delay if delay > 0 else -1

## 0x46c9b0's frame step, given the time in ms.
func advance(now: int):
	if deadline < 0 or now < deadline or not records.has(index): return
	frame = (frame + 1) % (records[index].frames as Array).size()
	_start_frame(now)
	apply()

func _process(_delta: float):
	advance(Time.get_ticks_msec())

## The region of Cursors.bmp the current frame shows (sheet pixels).
func frame_rect() -> Rect2i:
	if not records.has(index): return Rect2i()
	var r: Dictionary = records[index]
	var f: Array = r.frames[frame]
	return Rect2i(Vector2i(int(f[0]), int(f[1])), r.size)

func hotspot() -> Vector2i:
	return records[index].hotspot if records.has(index) else Vector2i.ZERO

func apply():
	if sheet == null or not records.has(index) or DisplayServer.get_name() == "headless": return
	var key := "%d:%d" % [index, frame]
	if key == _applied: return
	_applied = key
	if not _textures.has(key):
		var rect := frame_rect()
		if rect.size.x <= 0 or rect.size.y <= 0: return
		var image := sheet.get_region(rect)
		image.convert(Image.FORMAT_RGBA8)
		var size := Vector2i(roundi(rect.size.x * scale_factor), roundi(rect.size.y * scale_factor))
		image.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
		_textures[key] = ImageTexture.create_from_image(image)
	Input.set_custom_mouse_cursor(_textures[key], Input.CURSOR_ARROW, Vector2(hotspot()) * scale_factor)
