extends Node2D
## P-1 (EFFECTS_RESEARCH.md "P-1"): the floating text 0x53a010 over a unit or building. Presentation only.
## * 0x53a010(text, colour, duration) (Read, wbc3_decomp.c 211362): nothing unless the option byte 0x70d8df is set (not in
##   the rebuild's options: taken as on), the object's cell is inside the view and the object is visible. Colours: 2 stays
##   2 (red) for a hostile object and becomes 1 (green) for an own or allied one; 1, 3 and 4 become 2 for a hostile object.
##   Each object has two text slots (+0x450 / +0x454): with a slot started less than 500 ms ago the new text starts
##   500 ms late; with both slots busy the text is dropped.
## * 0x5349b0 (Read): font 0x25 + colour (Font.ini 37..41 FO_TINYMSG_STANDARD / GOOD / BAD / MAGIC / LEVEL), x = sprite x -
##   +0x96, y = sprite y - +0x98 - 40, fixed at creation; a text starting within 300 ms of the previous one (any object)
##   and less than 40 px from its height starts 250 ms later, 30 px below it. End = start + 1500 + duration.
## * 0x534ae0 / 0x534b70 (Read): drawn from its start, centred on x, rising 25 px over its life; in the last 1500 ms the
##   translucency rises 0..15 (0x58f5b0); removed at the end.
const Assets = preload("res://core/asset_store.gd")
const MapData = preload("res://core/map_data.gd")

const COLOUR_FONTS := {0: 37, 1: 38, 2: 39, 3: 40, 4: 41}
const FADE_MS := 1500
const RISE := 25
const LATE_MS := 500
const CHAIN_MS := 300
const CHAIN_DY := 40
const TEXT_Z := 3998                      # over the world sprites, under the fog overlay (4000)

var texts: Array = []                     # {text, font, x, y0, y, start, end, key, alpha}
var last_start := -100000                 # 0xafd4d8
var last_y := -100000                     # 0xafd4e0
var nodes: Array = []

static var _fonts := {}
static var _layout_fonts := {}

class TextNode extends Node2D:
	var entry: Dictionary
	func _draw():
		var info: Dictionary = entry.get("font_info", {})
		if info.is_empty() or info.font == null: return
		var alpha: float = entry.get("alpha", 1.0)
		var width := float(info.font.get_string_size(entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(info.size)).x)
		var at := Vector2(int(entry.x) - width * 0.5, int(entry.y) + int(info.baseline))
		if info.shadow: draw_string(info.font, at + Vector2(1, 1), entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(info.size), Color(0, 0, 0, alpha))
		var c: Color = info.colour
		c.a = alpha
		draw_string(info.font, at, entry.text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(info.size), c)

func _ready():
	z_as_relative = false
	z_index = TEXT_Z

static func font_info(number: int) -> Dictionary:
	if _layout_fonts.is_empty() and Assets.exists("ui_layout.json"):
		var data = Assets.json("ui_layout.json")
		if data is Dictionary: _layout_fonts = data.get("fonts", {})
	var key := str(number)
	if not _fonts.has(key):
		var info: Dictionary = _layout_fonts.get(key, {})
		if info.is_empty(): return {}
		var font = Assets.font("ui_font_%s.ttf" % String(info.file).get_basename())
		if font == null: font = ThemeDB.fallback_font
		_fonts[key] = {"font": font, "size": int(info.size), "baseline": int(info.baseline),
			"colour": Color8(int(info.colour[0]), int(info.colour[1]), int(info.colour[2])), "shadow": info.style == "DropShadow"}
	return _fonts[key]

## The colour rule of 0x53a010 for an object of a friendly (own or allied) or hostile owner.
static func colour_for(colour: int, friendly: bool) -> int:
	if colour == 2: return 1 if friendly else 2
	if colour == 1 or colour == 3 or colour == 4: return colour if friendly else 2
	return colour if friendly else 2

## 0x53a010 + 0x5349b0. `key`: the object (its two slots); `pixel`: the sprite's drawn top-left anchor (+0x4c - +0x96,
## +0x4e - +0x98). Returns the entry or {} when not shown.
func show_text(key, text: String, colour: int, duration: int, pixel: Vector2, friendly: bool, now: int, in_view: bool = true) -> Dictionary:
	if text == "" or not in_view: return {}
	colour = colour_for(colour, friendly)
	var late := false
	var busy := 0
	for t in texts:
		if t.key != key: continue
		busy += 1
		if int(t.start) + LATE_MS > now: late = true
	if busy >= 2: return {}
	var start := now + (LATE_MS if late else 0)
	var x := int(pixel.x)
	var y := int(pixel.y) - 40
	if absi(start - last_start) < CHAIN_MS and absi(y - last_y) < CHAIN_DY:
		start += 250
		y = last_y + 30
	var entry := {"text": text, "font": int(COLOUR_FONTS.get(colour, 37)), "x": x, "y0": y, "y": y, "start": start,
		"end": start + FADE_MS + duration, "key": key, "alpha": 1.0, "colour": colour}
	last_start = start
	last_y = y
	entry["font_info"] = font_info(int(entry.font))
	var node := TextNode.new()
	node.entry = entry
	node.visible = false
	add_child(node)
	entry["node"] = node
	texts.append(entry)
	return entry

## 0x534ae0: position and fade at `now`; false once the text ended.
static func advance(t: Dictionary, now: int) -> bool:
	if now < int(t.start): return true
	if now >= int(t.end): return false
	t.y = (int(t.start) - now) * RISE / (int(t.end) - int(t.start)) + int(t.y0)
	var level := 0
	if now > int(t.end) - FADE_MS: level = ((now - int(t.end)) + FADE_MS) * 15 / FADE_MS
	t.alpha = 1.0 - level / 16.0
	return true

func step(now: int):
	var keep: Array = []
	for t in texts:
		if advance(t, now):
			var node: TextNode = t.node
			node.visible = now >= int(t.start)
			node.queue_redraw()
			keep.append(t)
		elif is_instance_valid(t.node):
			t.node.queue_free()
	texts = keep

func clear():
	for t in texts:
		if is_instance_valid(t.node): t.node.queue_free()
	texts.clear()
	last_start = -100000
	last_y = -100000
