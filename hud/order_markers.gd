extends Node2D
## P-2 (EFFECTS_RESEARCH.md "P-2" item 2): the order markers of the selected head's move orders, Read from the decompile
## (0x49c110, 0x49c150, 0x49c190, 0x49c240, 0x49d3b0, 0x49d8c0). Presentation only: it reads the selection, the units'
## order lists and the rally points, and changes nothing.
## * Shown while Shift or Alt is held (0x41e320 -> 0x49c110: on a change the list is emptied and the phase reset) and for
##   500 ms after a ground move (commands 3 / 0x36..0x3a -> 0x530870, the Move / Stand buttons 0x4ce960 / 0x4ce9f0) or a
##   rally order (command 0xb -> 0x52e6b0), each followed by 0x49c150 (ignored while Shift / Alt is held).
## * The list (0x49d3b0, rebuilt every draw): an own building head with a rally point: one entry from the building to the
##   rally cell, its line drawn; one own unit: its current order from the sprite rectangle's centre, its line hidden during
##   the 500 ms show, then (only while held) every queued order from the previous entry's target with its line; several
##   units: every selected unit's orders, lines hidden. At most 49 entries. Order kinds 3 / 4 / 0xb / 0x13 (moves) give
##   entry type 4 with the target at the order cell's centre (0x493940).
## * The draw (0x49c240): the line is a dot every 8 pixels along the major axis (minor axis by an 8 x |minor| / (|major|
##   + 8) accumulator), pure green (0x7e0) with its four neighbours half green; the dot whose index (mod 8) equals the
##   phase (mod 8) has its neighbours full green and the four pixels at distance 2 half green. Then at the target a 1-pixel
##   outline square (0x46ea70) of size 2 / 4 / 6 / 8 / 10 by t = phase (16 - phase above 8): t 0 -> 2, 1 / 8 -> 4,
##   2 / 7 -> 6, 3 / 6 -> 8, 4 / 5 -> 10, colour (8t, 8t + 0xbf, 8t) for type 4 (5: (0, 0x80, 16t + 0x7f), 6: (16t +
##   0x7f, 0, 0), 7 / 0x11: (0, 16t + 0x7f, 16t + 0x7f)). The phase steps every 100 ms (main.gd update_order_marker).
## P-3: attack orders (6) give the square and the attack icon at the target's sprite centre, a conversion (7) the cyan
## square at the unit (its icon stays unit_agent.gd's); combat's queued orders (f.queue) join the list. Open: the repair
## icon (0x11: the rebuild's repair is a building message, no unit order), the build entry (5, the ghost sheet), the
## patrol-point list (0x425270 / 0x425290).
const SHOW_MS := 500                     # 0x49c150: timeGetTime() + 500
const MAX_ENTRIES := 49                  # 0x49d3b0: the list stops at 0x31
const LINE_GREEN := Color8(0, 255, 0)    # 0x7e0 (565)
const HALF_GREEN := Color(0, 1, 0, 0.5)  # (r >> 1, (g + 0x3f) >> 1, b >> 1) per pixel: half the pixel, half green

var main: Node
var armed := false                       # +0x1a306c
var until_ms := 0                        # +0x1a3068
var held := false                        # +0x1a2636
var entries: Array = []                  # [{"type", "start": Vector2i, "target": Vector2i, "hidden": bool}]

func _ready():
	z_index = 4001                       # over the fog overlay (4000): a screen-space draw in the original (Provisional)
	z_as_relative = false

## 0x49c150 after an order: a 500 ms show, unless Shift / Alt holds the list already.
func arm(now_ms: int):
	if held: return
	armed = true
	until_ms = now_ms + SHOW_MS
	_reset_phase()

static func _reset_phase():
	preload("res://battle/unit_agent.gd").marker_phase = 0

## 0x41e320 -> 0x49c110(state).
func set_held(on: bool):
	if on == held: return
	held = on
	if on:
		armed = false
		entries.clear()
		_reset_phase()

## t of 0x49c240 from the phase 0..15.
static func triangle(phase: int) -> int:
	return 16 - phase if phase > 8 else phase

## The square of 0x49c240: [offset, size] (the outline starts `offset` pixels up and left of the target).
static func square(t: int) -> Array:
	if t == 0: return [1, 2]
	if t == 1 or t == 8: return [2, 4]
	if t == 2 or t == 7: return [3, 6]
	if t == 3 or t == 6: return [4, 8]
	return [5, 10]

## The square's colour (0x46eb20's r, g, b) by entry type.
static func square_colour(type: int, t: int) -> Color:
	match type:
		5: return Color8(0, 0x80, t * 16 + 0x7f)
		6: return Color8(t * 16 + 0x7f, 0, 0)
		7, 0x11: return Color8(0, t * 16 + 0x7f, t * 16 + 0x7f)
	return Color8(t * 8, t * 8 + 0xbf, t * 8)

## The dots of 0x49c240's line from `start` to `target` (world pixels; the original clips them to the view).
static func dots(start: Vector2i, target: Vector2i) -> Array:
	var dx := target.x - start.x
	var dy := target.y - start.y
	var out: Array = []
	if dx == 0 and dy == 0: return out
	var ax := absi(dx)
	var ay := absi(dy)
	if ax < ay:
		var step := 8 if dy >= 1 else -8
		var count := dy / step + 1
		var side := 0 if dx == 0 else (1 if dx >= 1 else -1)
		var x := start.x
		var y := start.y
		var acc := 0
		for i in count:
			out.append(Vector2i(x, y))
			acc += ax * 8
			while acc >= ay + 8:
				acc -= ay + 8
				x += side
			y += step
	else:
		var step := 8 if dx >= 1 else -8
		var count := dx / step + 1
		var side := 0 if dy == 0 else (1 if dy >= 1 else -1)
		var x := start.x
		var y := start.y
		var acc := 0
		for i in count:
			out.append(Vector2i(x, y))
			acc += ay * 8
			while acc >= ax + 8:
				acc -= ax + 8
				y += side
			x += step
	return out

static func cell_centre(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 32 + 16, cell.y * 24 + 12)

## The sprite rectangle's centre of a unit node (+0x58 + w / 2, +0x5a + h / 2).
static func sprite_centre(u) -> Vector2i:
	var s = u.get("sprite")
	if s is Sprite2D and s.texture != null:
		var size: Vector2 = s.region_rect.size if s.region_enabled else s.texture.get_size()
		var top_left: Vector2 = u.position + s.position + s.offset - (size * 0.5 if s.centered else Vector2.ZERO)
		return Vector2i(top_left + size * 0.5)
	return Vector2i(u.position)

## 0x49d8c0 for one rebuild order: a move-like order gives a type-4 entry to its cell's centre; P-3: an attack (order 6
## with a target) a type-6 entry to the target's sprite rectangle centre (+0x58 + w / 2, +0x5a + h / 2); a conversion
## (orders 7 / 0xc) a type-7 entry at the start point itself; anything else nothing.
func _entry(order: Dictionary, start: Vector2i, hidden: bool) -> Dictionary:
	match String(order.get("kind", "")):
		"attack":
			var at = _target_centre(String(order.get("target_kind", "")), int(order.get("target_id", -1)))
			if at == null: return {}
			return {"type": 6, "start": start, "target": at, "hidden": hidden}
		"convert":
			return {"type": 7, "start": start, "target": start, "hidden": hidden}
		"move":
			var cell: Vector2i
			if order.has("target"):
				cell = main.collision.world_cell(order.target) if main != null and main.get("collision") != null else Vector2i(order.target / Vector2(32, 24))
			elif order.has("cell"): cell = order.cell
			else: return {}
			return {"type": 4, "start": start, "target": cell_centre(cell), "hidden": hidden}
	return {}

## The sprite rectangle centre of an attack target, or null when it is gone.
func _target_centre(kind: String, id: int):
	if main == null: return null
	if kind == "unit":
		var u = main.unit_by_id(id)
		if u == null or u.dying or u.removed: return null
		return sprite_centre(u)
	if kind == "building" and main.get("production") != null:
		var b = main.production.building(id)
		if b == null: return null
		var r: Rect2 = b.cell_rect() if b.has_method("cell_rect") else Rect2(Vector2(b.position) / Vector2(32, 24), Vector2.ONE)
		var c := r.get_center()
		return Vector2i(int(c.x * 32), int(c.y * 24))
	return null

## P-3: a unit's order chain in the original's order (0x49d3b0 walks +0x48 then the linked orders): the current attack
## (combat's f.order) or the conversion or the current walk (unit.orders), then combat's queued orders (f.queue).
func chain(u) -> Array:
	var out: Array = []
	var f = main.combat.fighters.get(int(u.unit_id)) if main != null and main.get("combat") != null else null
	if f != null and f.get("order") != null and String(f.order.get("kind", "")) == "attack" and not bool(f.order.get("ai", false)):
		out.append(f.order)
	elif main != null and main.get("conversions") != null and main.conversions.converting(int(u.unit_id)):
		out.append({"kind": "convert"})
	else:
		out.append_array(u.orders)
	if f != null: out.append_array(f.get("queue", []))
	return out

## 0x49d3b0: the list for the current selection.
func build_list() -> Array:
	var out: Array = []
	if main == null: return out
	var head = main.selection_head()
	if head == null: return out
	var local: int = int(main.local_player)
	if not (head is Node2D):                                  # a building
		if int(head.owner) != local or head.get("rally") == null or head.rally.x < 0: return out
		var b_cell := Vector2i(int(head.position.x) / 32, int(head.position.y) / 24)
		out.append({"type": 4, "start": cell_centre(b_cell), "target": cell_centre(head.rally), "hidden": false})
		return out
	if int(head.owner_id) != local: return out
	var units: Array = main.own_selected()
	if units.size() <= 1:
		var u = head
		var orders := chain(u)
		if orders.is_empty(): return out
		var first := _entry(orders[0], sprite_centre(u), armed)
		if first.is_empty(): return out
		out.append(first)
		if armed: return out
		for i in range(1, orders.size()):
			if out.size() >= MAX_ENTRIES: break
			var e := _entry(orders[i], out[-1].target, false)
			if not e.is_empty(): out.append(e)
		return out
	for u in units:
		var start := sprite_centre(u)
		for order in chain(u):
			if out.size() >= MAX_ENTRIES: return out
			var e := _entry(order, start, true)
			if e.is_empty(): continue
			out.append(e)
			start = e.target
	return out

## Every frame (main.gd update_order_marker): the hold state, the show's end, the list.
func refresh(now_ms: int, shift_or_alt: bool):
	set_held(shift_or_alt)
	if armed and until_ms <= now_ms:
		armed = false
		until_ms = 0
	entries = build_list() if held or armed else []
	visible = not entries.is_empty()
	queue_redraw()

func _plus(at: Vector2, colour: Color, reach: int):
	for d in [Vector2(0, -reach), Vector2(0, reach), Vector2(reach, 0), Vector2(-reach, 0)]:
		draw_rect(Rect2(at + d, Vector2.ONE), colour)

func _draw():
	var phase: int = preload("res://battle/unit_agent.gd").marker_phase
	var t := triangle(phase)
	for e in entries:
		if not bool(e.hidden):
			var k := 0
			for p in dots(e.start, e.target):
				var at := Vector2(p)
				draw_rect(Rect2(at, Vector2.ONE), LINE_GREEN)
				if k == (phase & 7):
					_plus(at, LINE_GREEN, 1)
					_plus(at, HALF_GREEN, 2)
				else:
					_plus(at, HALF_GREEN, 1)
				k = (k + 1) & 7
		var sq := square(t)
		var size := float(sq[1])
		var corner := Vector2(e.target) - Vector2(sq[0], sq[0])
		draw_rect(Rect2(corner + Vector2(0.5, 0.5), Vector2(size - 1, size - 1)), square_colour(int(e.type), t), false, 1.0)
		# P-3: 0x49c240's tail: types 6 / 0x11 draw SelectionRings.bmp (bitmap 0x66) 32 x 32 at (0x188 / 0x1c8, 0x1eb + 32
		# row) over the square, 16 px up and left of the target; type 7's icon is unit_agent.gd's (marker_unit).
		var icon := icon_source(int(e.type), phase)
		var rings: Texture2D = preload("res://battle/unit_agent.gd").rings_texture() if icon.size.x > 0 else null
		if rings != null: draw_texture_rect_region(rings, Rect2(Vector2(e.target) - Vector2(16, 16), icon.size), icon)

## The icon rectangle of an entry type (6 attack, 0x11 repair) at the phase, or an empty one.
static func icon_source(type: int, phase: int) -> Rect2:
	var x: int = {6: 0x188, 0x11: 0x1c8}.get(type, -1)
	if x < 0: return Rect2()
	return Rect2(x, 0x1eb + 32 * preload("res://battle/unit_agent.gd").marker_row(phase), 32, 32)
