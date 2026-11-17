extends RefCounted
## Selection rules of the original (parity pass 1, UI_RESEARCH.md "Selection"). All Read unless marked.
##
## * Mouse translation (right-click interface, the default: 0x41e160 picks the translator at 0x421190; Ghidra did not
##   decompile it, it was read from the disassembly). Event flags: 1 left button, 4 Ctrl, 8 Shift, 0x10 Alt (0x45e610 remaps
##   the window's Shift 4 / Ctrl 8 / Alt 0x20). A left press starts the box (0x4226dc), any motion shows it (0x74c3fc); on
##   release a box needs more than 3 pixels in x or y (0x421409), otherwise it is a click.
## * Box with exactly one own unit (0x547da0 mask 0x1101), or a click on an own unit (0x548360 masks 0x1101, then 0x1102 own
##   buildings): the same object again within 8 timer ticks of 50 ms (0x608470) selects the own units of its selection class
##   in the view (command 0xf -> 0x531dd0, at most 32); otherwise it is selected alone (command 1), or added with Shift when
##   the selection head is a unit (command 0x13). A click on nothing own picks any visible object (mask 0x9e03: allied,
##   enemy, neutral) for information; a click on nothing deselects (command 5).
## * Other boxes (command 2 -> 0x5319f0): the selection is cleared, the player's own list is walked in order and every
##   alive, shown unit in the box is selected while its weight (+0xb2, at least 1) fits under 32; Ctrl keeps only ground units
##   (STATUS bit 21 clear, 0x5319f0 mode 1), Alt only flying ones (mode 2). Shift (head is a unit) adds instead (0x531c90:
##   up to 32 objects, mode 1 / 2 for Ctrl / Alt). When nothing own is in the box, an own building (0x9102) and then any
##   other object (0x9603) in it is selected alone.
## * 0x548360 single pick: among the sprites under the point, the one whose sprite centre is nearest by Chebyshev distance.
## Provisional: weight (see weight(); the writer of +0xb2 for units is not found; 0x4ddd30 sizes
## the panel frames 28x28 / 28x56 / 56x56 by weight < 2 / 2 / >= 4); the in-box test (unit vtable +0xc) uses the sprite box.

const CAP := 32
const DRAG_THRESHOLD := 3
const DOUBLE_TICKS := 8
const TICK_MS := 50

static func world_box(start: Vector2, finish: Vector2, canvas: Transform2D) -> Rect2:
	var screen := Rect2(start, finish - start).abs()
	var inverse := canvas.affine_inverse()
	var result := Rect2(inverse * screen.position, Vector2.ZERO)
	for corner in [screen.position + Vector2(screen.size.x, 0), screen.end, screen.position + Vector2(0, screen.size.y)]:
		result = result.expand(inverse * corner)
	return result

## 0x421409: more than 3 pixels in x or in y.
static func is_box(start: Vector2, finish: Vector2) -> bool:
	return absf(start.x - finish.x) > DRAG_THRESHOLD or absf(start.y - finish.y) > DRAG_THRESHOLD

## Parity pass 5 (still Provisional, the unit writer of +0xb2 is not found; 0x5355d0 writes the sprite's field of that
## offset): 4 for the 2x2 units; 2 for a unit whose 'i' sheet thumbnail (frame 5, the multi-selection list's picture) is
## taller than a 28 x 28 frame (cavalry and fliers: 22 x 47, made for the 28 x 56 frame of weight 2); else 1.
static func weight(unit) -> int:
	var e: int = int(unit.get("extent")) if unit.get("extent") != null else 1
	if e >= 2: return 4
	var type_id = unit.get("type_id")
	if type_id != null:
		var region: Array = preload("res://core/art_data.gd").data().get("icons", {}).get(String(type_id), {}).get("regions", {}).get("5", [])
		if region.size() == 4 and int(region[3]) > 28: return 2
	return 1

## Alive (+0x3c > 0) and shown (+0x30 == 0).
static func pickable(unit) -> bool:
	return not unit.dying and not unit.removed and unit.visible and not unit.inside_building and unit.hit_rect().size != Vector2.ZERO

static func own(unit, player: int) -> bool:
	return int(unit.owner_id) == player and pickable(unit)

## Box modes of 0x5319f0 / 0x531c90: 0 every unit, 1 ground units (bit 21 clear), 2 flying units (bit 21 set).
static func mode_ok(unit, mode: int) -> bool:
	var flying: bool = bool(unit.get("flying")) if unit.get("flying") != null else false
	return mode == 0 or (mode == 1 and not flying) or (mode == 2 and flying)

static func hit(units: Array, point: Vector2):
	return hit_where(units, point, func(_u): return true)

## 0x548360(.., 1): the hit sprite whose centre is nearest to the point (Chebyshev); ties keep the first.
static func hit_where(units: Array, point: Vector2, accept: Callable):
	var found = null
	var best := INF
	for unit in units:
		if not pickable(unit) or not accept.call(unit): continue
		var r: Rect2 = unit.hit_rect()
		if not r.has_point(point): continue
		var c := r.get_center()
		var d := maxf(absf(c.x - point.x), absf(c.y - point.y))
		if d < best:
			best = d
			found = unit
	return found

static func in_box(units: Array, box: Rect2, accept: Callable) -> Array:
	var out: Array = []
	for unit in units:
		if pickable(unit) and accept.call(unit) and box.intersects(unit.hit_rect(), true): out.append(unit)
	return out

static func clear(units: Array):
	for unit in units:
		if unit.selected:
			unit.selected = false
			unit.queue_redraw()

static func select_only(units: Array, chosen):
	for unit in units:
		var want: bool = unit == chosen
		if unit.selected != want:
			unit.selected = want
			unit.queue_redraw()

static func add(chosen):
	if chosen != null and not chosen.selected:
		chosen.selected = true
		chosen.queue_redraw()

static func selected_count(units: Array) -> int:
	return units.filter(func(u): return u.selected).size()

## 0x5319f0: replace the selection with the own units in the box (weight cap 32). Returns the selected weight.
static func select_box(units: Array, box: Rect2, player: int, mode: int = 0) -> int:
	clear(units)
	var total := 0
	for unit in units:
		if total > CAP - 1: break
		if not own(unit, player) or not mode_ok(unit, mode): continue
		if weight(unit) + total > CAP: continue
		if box.intersects(unit.hit_rect(), true):
			add(unit)
			total += weight(unit)
	return total

## 0x531c90: with nothing selected as 0x5319f0; otherwise add own units in the box while fewer than 32 are selected.
static func add_box(units: Array, box: Rect2, player: int, mode: int = 0) -> int:
	var existing := selected_count(units)
	if existing < 1: return select_box(units, box, player, mode)
	if existing >= CAP: return 0
	var added := 0
	var found := in_box(units, box, func(u): return own(u, player) and mode_ok(u, mode)).slice(0, CAP)
	for unit in found:
		if added + existing > CAP - 1: break
		if not unit.selected:
			add(unit)
			added += 1
	return added

## 0x531dd0: the own units of a selection class (the rebuild uses the type) inside a world rectangle, at most 32.
static func select_type_in(units: Array, type_id: String, rect: Rect2, player: int) -> int:
	clear(units)
	var count := 0
	for unit in units:
		if count >= CAP: break
		if own(unit, player) and String(unit.type_id) == type_id and rect.intersects(unit.hit_rect(), true):
			add(unit)
			count += 1
	return count

## 0x548ee0 (Ctrl+A / Z / S / T): the up to 32 own units nearest (Manhattan, in cells) to `centre` inside the cell
## rectangle `cells` (an empty rectangle means the whole map), optionally of one type; replaces the selection.
static func select_nearest(units: Array, player: int, centre: Vector2i, cells: Rect2i, type_id: String = "") -> int:
	var candidates: Array = []
	for unit in units:
		if not own(unit, player): continue
		if type_id != "" and String(unit.type_id) != type_id: continue
		if cells.size != Vector2i.ZERO and not cells.has_point(unit.cell): continue
		candidates.append(unit)
	candidates.sort_custom(func(a, b):
		var da: int = absi(a.cell.x - centre.x) + absi(a.cell.y - centre.y)
		var db: int = absi(b.cell.x - centre.x) + absi(b.cell.y - centre.y)
		return da < db)
	candidates = candidates.slice(0, CAP)
	if candidates.is_empty(): return 0
	clear(units)
	for unit in candidates: add(unit)
	return candidates.size()

## G-4 (Read, 0x420390 bVar6, decompile 24452-24455): the head is a "tower" when it is a building (vtable +0x28 == 1)
## whose BUI damage is above 0: the word 0x69778c + its type index (+0xc8) x 200, the Building.cfg row's +0x38.
static func tower_head(raw_hex: String) -> bool:
	var raw := raw_hex.hex_decode()
	return raw.size() >= 0x3a and raw.decode_s16(0x38) > 0

## 0x420390 (world) with the panel part of 0x41ee80: the cursor index for a context.
## ctx: panel, pressed (a button held over the panel), mode (target mode 0x74b984), dragging (a box is showing),
## head ("", "unit", "building", "tower": the selection head and whether it is a building with an attack), head_own,
## head_multi (more than one selected), head_hero, hits_air / hits_ground (the head unit's 0x6e4018 abilities),
## hover ("", "unit", "building"), hover_own, hover_allied, hover_fogged (a remembered building under fog),
## hover_flying, hover_enter (the head can enter, resume, repair or heal it: 0x523e10 / 0x523e70 / 0x51c240 / 0x528280),
## pickup (the hero over an item pile or a quest site: 0x52ed90 / 0x5877e0).
static func cursor_index(ctx: Dictionary) -> int:
	if ctx.get("panel", false): return 3 if ctx.get("pressed", false) else 2
	match int(ctx.get("mode", 0)):
		1: return 8
		2: return 7
		4: return 9
		5, 10: return 14
		7: return 6
		8: return 1
	if ctx.get("dragging", false): return 1
	var head: String = ctx.get("head", "")
	if head != "" and ctx.get("head_hero", false) and ctx.get("head_own", false) and ctx.get("pickup", false): return 12
	if head != "" and not ctx.get("head_own", false): return 1
	var unit_head := head == "unit"
	var tower := head == "tower"
	var hover: String = ctx.get("hover", "")
	if hover != "" and not ctx.get("hover_own", false):
		var against := 6 if ctx.get("hover_allied", false) else 7
		if ctx.get("hover_fogged", false):
			if unit_head or tower: return against
		else:
			if not unit_head and not tower: return 6
			if not ctx.get("head_multi", false) and hover == "unit":
				if unit_head:
					var flying: bool = ctx.get("hover_flying", false)
					if flying and not ctx.get("hits_air", true): return 6
					if not flying and not ctx.get("hits_ground", true): return 6
				elif tower: return 7
			return against
	if hover != "" and ctx.get("hover_own", false):
		if unit_head and ctx.get("hover_enter", false): return 13
		return 6
	return 8 if unit_head else 1
