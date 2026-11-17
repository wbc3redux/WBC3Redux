extends RefCounted
## Fog of war and shroud (milestone 8, rewritten in 8-fix). Evidence: COMBAT_RESEARCH.md, fixtures tests/fog_fixtures.json.
## Emulated (tools/emulate_fog.py, Desert Sands): the fog object keeps per cell (0x47f560/0x4806a0) a visible byte (+0x297f1),
## an explored byte (+0x297f2) and an ARMED byte (+0x297f3). The initialiser 0x47a940 arms every cell. The sprite manager
## 0x5468e0 calls the fog update 0x546f00 when its counter 0xb90fa4 wraps modulo 4; 0x546f00 advances 0xb90f9c modulo 40,
## sweeps when it is a multiple of 5 (every 20 game updates, 500 ms) and darkens at 35 (once per 160 updates, 4 s).
## A sweep (0x47de40) lights, for every unit/building sprite of the viewing player and its allies, the ARMED cells of its
## sight disc (radius 10 + the player's sight bonus, tier-4 mask) and disarms them; the darken (0x485d20) turns every cell
## that is still armed dark and disarms it. Cells are armed (0x485c70) in the box [c - r - 5, c + r + 5) around a sprite:
## at each walk-step start (0x5377a0: old cell with r = bonus + 3 + 10 when the facing changes, then the new cell with
## r = bonus + 4 + 10; any owner), when a local sprite is placed (0x534f00, r = bonus + 3 + 10) and when a sprite is removed
## (0x5468e0 active list, r = bonus + 3 + 10). A stationary sprite's disc therefore stays lit; darkness only appears
## around cells that something moved near and nobody re-saw before the darken.
## Read, not executed: the caller arguments of 0x485c70 (the arm routine itself is emulated), the shroud-only update
## 0x546da0, the drawing copy +0x8e1f5 (0x47f110: lit when a neighbour is lit; used by 0x47f560 inside the viewport; ported for the drawing only, fog_view.gd, P-4).
## Line of sight (vision 2): 0x485720 by terrain and feature heights (Emulated, tests/line_of_sight_fixtures.json). Open: directional masks of other tiers,
## radius 15+ (the original's run table overflows its slot), building sight radius (0x52b8bd) and upgrades.
const Rules = preload("res://simulation/combat_rules.gd")
const SPRITE_PHASES := 4        # 0x5468e0: 0xb90fa4 & 3; the fog update runs when it wraps to 0
const FOG_PHASES := 40          # 0x546f00: 0xb90f9c modulo 40
const SWEEP_EVERY := 5          # sweep when 0xb90f9c % 5 == 0
const CLEAR_PHASE := 35         # darken at 0xb90f9c == 35
const SWEEP_UPDATES := SPRITE_PHASES * SWEEP_EVERY      # 20 game updates = 500 ms
const CYCLE_UPDATES := SPRITE_PHASES * FOG_PHASES       # 160 game updates = 4 s
const DEFAULT_RADIUS := 10      # sprite +0x8c (and +0x88), set by the sprite constructors
const ARM_MARGIN := 5           # 0x485c70 box: [c - reach - 5, c + reach + 5)
const STEP_REACH := 4           # 0x5377a0 at the new cell: bonus + 4 + radius
const TURN_REACH := 3           # 0x5377a0 on a facing change, 0x534f00 placement, 0x5468e0 removal: bonus + 3 + radius

var width := 128
var height := 128
var fog := true
var shroud := true
var explored: Dictionary = {}   # player -> PackedByteArray
var visible: Dictionary = {}    # player -> PackedByteArray
var armed: Dictionary = {}      # player -> PackedByteArray, the +0x297f3 byte (1 = reveal and darken may act on it)
var sprite_counter := 0         # 0x00b90fa4 & 3
var counter := 0                # 0x00b90f9c
var sight_bonus: Dictionary = {}   # player -> 0x70d488 entry (0 in the slice)
## Match option 0x70ae04 (options block copied from 0xa479e8 by 0x4de740, whose defaults branch sets 2). Values >= 2
## enable the terrain line-of-sight test 0x485720. The skirmish sets it from the setup's vision (main.gd).
var line_of_sight_option := 1                # the setup default (vision 1, Fog of War); the skirmish sets it
## 0x485ac0 per cell (index y * width + x): the TER height byte (cell +0) plus the height word +0x3e of the map feature on
## the cell (0x530420 by its FEA code). Empty: no heights (every line of sight is clear). set_heights fills it.
var heights := PackedInt32Array()
var dirty := true

func _init(map_width: int = 128, map_height: int = 128):
	width = map_width
	height = map_height

## 0x47a940 for one player's map: nothing visible or explored, every cell armed.
func ensure(player: int):
	if explored.has(player): return
	explored[player] = PackedByteArray()
	explored[player].resize(width * height)
	visible[player] = PackedByteArray()
	visible[player].resize(width * height)
	armed[player] = PackedByteArray()
	armed[player].resize(width * height)
	armed[player].fill(1)

func bonus(player: int) -> int:
	return int(sight_bonus.get(player, 0))

## 0x47f560: can this player currently see the cell (fog on), has it explored it (shroud only), or everything (both off).
func is_visible(player: int, cell: Vector2i) -> bool:
	if not fog and not shroud: return true
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height: return false
	ensure(player)
	var index := cell.y * width + cell.x
	if fog: return visible[player][index] != 0
	return explored[player][index] != 0

## B1-6c (Read: 0x548xxx object picks with flag 0x10000, 0x51e6xx order targets, decompile 194184 / 217451 / 217685):
## a unit whose +0x1f1 byte is set (invisible; B1-6d: Illusion's Invisibility, spells.gd syncs `invisible` each step) is hidden from
## and unpickable by other players unless their living hero sees invisible (0x40dd10: effect / item power 0x43, See
## Invisible; spells.gd writes sees_invisible each step).
var invisible: Dictionary = {}       # unit id -> true (+0x1f1)
var sees_invisible: Dictionary = {}  # player -> bool (0x40dd10)

func unit_visible(player: int, unit_id: int, owner: int, cell: Vector2i) -> bool:
	if owner != player and invisible.has(unit_id) and not bool(sees_invisible.get(player, false)): return false
	return is_visible(player, cell)

## 0x4806a0: explored (shroud) query used by the placement check.
func is_explored(player: int, cell: Vector2i) -> bool:
	if not fog and not shroud: return true
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height: return false
	ensure(player)
	return explored[player][cell.y * width + cell.x] != 0

## 0x435900 for the local player, per solid footprint cell: shroud on -> the cell must be explored (0x480770/0x4806a0),
## fog on -> it must be visible now (0x47f6a0/0x47f560).
func cell_allows(player: int, cell: Vector2i) -> bool:
	if shroud and not is_explored(player, cell): return false
	if fog and not is_visible_now(player, cell): return false
	return true

func placement_allows(player: int, cells: Array) -> bool:
	for cell in cells:
		if not cell_allows(player, cell): return false
	return true

func is_visible_now(player: int, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height: return false
	ensure(player)
	return visible[player][cell.y * width + cell.x] != 0

func is_armed(player: int, cell: Vector2i) -> bool:
	if cell.x < 0 or cell.y < 0 or cell.x >= width or cell.y >= height: return false
	ensure(player)
	return armed[player][cell.y * width + cell.x] != 0

## Sight cell of a building sprite (0x546f00): the sprite row plus (BUI +0x3f - 1) >> 1. The sprite's own cell is taken
## as the placement anchor (column left + (w - 1) >> 1, top row); that link is Read-provisional.
static func building_sight_cell(left: int, top: int, footprint_width: int, footprint_height: int) -> Vector2i:
	return Vector2i(left + ((footprint_width - 1) >> 1), top + ((footprint_height - 1) >> 1))

## One game update (25 ms), the part 0x5468e0 does before it updates the sprites. sources: [{"player", "cell", "radius",
## "viewers"}] for every unit/building sprite; viewers: players whose maps are maintained. Returns true when a cell changed.
## Step starts that happen during the same update arm afterwards (arm_step), as in the original.
func update(sources: Array, viewers: Array) -> bool:
	for player in viewers: ensure(player)
	var changed := false
	sprite_counter = (sprite_counter + 1) % SPRITE_PHASES
	if sprite_counter == 0 and (fog or shroud):
		if counter % SWEEP_EVERY == 0:
			if sweep(sources, viewers): changed = true
			if fog and counter == CLEAR_PHASE and darken(viewers): changed = true
		counter = (counter + 1) % FOG_PHASES
	if changed: dirty = true
	return changed

## True when the next update() sweeps (W2: the caller builds the sight sources only then).
func sweep_due() -> bool:
	return (fog or shroud) and (sprite_counter + 1) % SPRITE_PHASES == 0 and counter % SWEEP_EVERY == 0

## 0x546f00 sweep (0x47de40 per sprite) for each viewing player. With fog off and shroud on the original runs 0x546da0
## instead (same cadence, explores the disc, no darken; Read, not emulated).
func sweep(sources: Array, viewers: Array) -> bool:
	var changed := false
	for player in viewers:
		ensure(player)
		for source in sources:
			if not source.get("viewers", [source.player]).has(player): continue
			if _reveal(player, source.cell, int(source.radius) + bonus(int(source.player)), int(source.get("extra", 0))): changed = true
	if changed: dirty = true
	return changed

## 0x485d20 over the whole map: every cell still armed goes dark and is disarmed.
func darken(viewers: Array) -> bool:
	var changed := false
	for player in viewers:
		ensure(player)
		var seen: PackedByteArray = visible[player]
		var marks: PackedByteArray = armed[player]
		for index in width * height:
			if marks[index] == 0: continue
			marks[index] = 0
			if seen[index] != 0:
				seen[index] = 0
				changed = true
	if changed: dirty = true
	return changed

## 0x485c70: arm the box [c - reach - 5, c + reach + 5) in the maps of `players` (all maintained maps when empty: the
## original has one fog object per machine and its step callers do not test the owner).
func arm(cell: Vector2i, reach: int, players: Array = []):
	if not fog and not shroud: return
	var targets: Array = players if not players.is_empty() else armed.keys()
	var x0 := maxi(0, cell.x - reach - ARM_MARGIN)
	var x1 := mini(width, cell.x + reach + ARM_MARGIN)
	var y0 := maxi(0, cell.y - reach - ARM_MARGIN)
	var y1 := mini(height, cell.y + reach + ARM_MARGIN)
	for player in targets:
		ensure(player)
		var marks: PackedByteArray = armed[player]
		for y in range(y0, y1):
			var row := y * width
			for x in range(x0, x1): marks[row + x] = 1

## 0x5377a0 at a step start of any unit owned by `owner`: arm around the old cell when the facing changes, then around
## the new cell.
func arm_step(owner: int, from_cell: Vector2i, to_cell: Vector2i, turned: bool, radius: int = DEFAULT_RADIUS):
	if turned: arm(from_cell, bonus(owner) + TURN_REACH + radius)
	arm(to_cell, bonus(owner) + STEP_REACH + radius)

## 0x534f00 (sprite placed on the map, local player's sprites only) and 0x5468e0 (sprite removed, any owner).
func arm_placed(owner: int, cell: Vector2i, radius: int = DEFAULT_RADIUS):
	arm(cell, bonus(owner) + TURN_REACH + radius, [owner])

func arm_removed(owner: int, cell: Vector2i, radius: int = DEFAULT_RADIUS):
	arm(cell, bonus(owner) + TURN_REACH + radius)

## 0x47de40 with the tier-4 mask: armed cells inside the disc become visible and explored and are disarmed, when the line
## of sight 0x485720 is clear (always while option 0x70ae04 < 2). A blocked cell stays armed (and goes dark at the darken).
## `extra`: the sprite's eye term (0x546f00: 6 for buildings and STATUS 0x200000 flyers, else 0).
func _reveal(player: int, centre: Vector2i, radius: int, extra: int = 0) -> bool:
	var changed := false
	var seen: PackedByteArray = visible[player]
	var known: PackedByteArray = explored[player]
	var marks: PackedByteArray = armed[player]
	for dx in range(-radius, radius + 1):
		var x := centre.x + dx
		if x < 0 or x >= width: continue
		for dy in range(-radius, radius + 1):
			var y := centre.y + dy
			if y < 0 or y >= height: continue
			if not Rules.sight_covers(dx, dy, radius): continue
			var index := y * width + x
			if not fog:
				if known[index] == 0:
					known[index] = 1
					changed = true
				continue
			if marks[index] == 0: continue
			if line_of_sight_option >= 2 and not line_of_sight(Vector2i(x, y), centre, extra): continue
			if seen[index] == 0 or known[index] == 0: changed = true
			seen[index] = 1
			known[index] = 1
			marks[index] = 0
	return changed

# ------------------------------------------------------------------------------------------------ line of sight (vision 2)
## Read: 0x485720, 0x485a50, 0x485ac0, 0x485860, 0x530420 (decompile 90272-90470, 204895-204935); 0x546f00 for the eye term.
const LOS_WINDOW := 61                  # 0x485860: rays to every cell of a 61 x 61 window around the viewer (cell 30, 30)
const LOS_CENTRE := 30
const EYE_MAX := 7
static var _rays: Dictionary = {}       # (dx + 30) * 61 + (dy + 30) -> PackedInt32Array of window cells (x, y pairs)

## 0x530420: a map feature's sight height (+0x3e) by the second and third letters of its FEA code.
static func feature_height(code: String) -> int:
	if code.length() < 3: return 0
	var a := code[1]
	var b := code[2]
	if a == "P":
		if b == "B" or b == "W": return 6
		if b == "M" or b == "P": return 5
		return 0
	if a == "R": return 4 if b == "B" else 0
	if a == "S" and (b == "H" or b == "A"): return 5
	return 0

## 0x485ac0 for every cell of `collision` (collision_data.gd): the height byte +0 and the feature on the cell. The world
## grid keeps one object per cell; with overlapping footprints the rebuild takes the last feature listed (placement order:
## a later placement overwrites the grid word, Provisional). Features with the occupancy bypass (FEA byte 58) are not on
## the grid.
func set_heights(collision) -> void:
	heights = PackedInt32Array()
	if collision == null or collision.data.is_empty() or not collision.data.has("cells"): return
	var cells: Array = collision.data.cells
	var objects: Array = collision.data.get("objects", [])
	heights.resize(width * height)
	for i in mini(cells.size(), width * height):
		var c: Dictionary = cells[i]
		var raw = c.get("raw")
		var h: int = int(raw[0]) if raw != null and raw.size() > 0 else 0
		var feature := 0
		for index in c.get("object_indices", []):
			var o: Dictionary = objects[int(index)] if int(index) < objects.size() else {}
			if String(o.get("kind", "")) != "features" or bool(o.get("bypass", false)): continue
			feature = feature_height(String(o.get("code", "")))
		heights[i] = h + feature

func height_at(cell: Vector2i) -> int:
	if heights.is_empty(): return 0
	return heights[cell.y * width + cell.x]

## 0x485860: the cells a ray crosses from the viewer's pixel centre (976, 732 in the window: cell 30, 30) to the target
## cell's centre, stepping one pixel along the major axis (cells 32 x 24 pixels); the first entry is the viewer's cell,
## the last the target's. Built on first use and kept (the original builds all 3,720 at the fog object's creation).
static func ray(dx: int, dy: int) -> PackedInt32Array:
	var key := (dx + LOS_CENTRE) * LOS_WINDOW + (dy + LOS_CENTRE)
	if _rays.has(key): return _rays[key]
	var out := PackedInt32Array()
	var a := dx + LOS_CENTRE
	var ty := (dy + LOS_CENTRE) * 24 + 12
	var tx := a * 32 + 16
	var x := 0x3d0
	var y := 0x2dc
	var last_x := 0
	var last_y := 0
	var guard := 0
	while (x != tx or y != ty) and guard < 4096:
		guard += 1
		var cx := x >> 5
		var cy := y / 24
		if cx != last_x or cy != last_y:
			out.append(cx)
			out.append(cy)
			last_x = cx
			last_y = cy
		var ady := absi(ty - 0x2dc)
		var adx := absi(a * 32 - 0x3c0)
		if ady < adx:
			x += (a * 32 - 0x3c0) / adx
			if ty != 0x2dc: y = ((x - 0x3d0) * (ty - 0x2dc)) / (a * 32 - 0x3c0) + 0x2dc
		else:
			y += (ty - 0x2dc) / ady
			if tx != 0x3d0: x = ((y - 0x2dc) * (a * 32 - 0x3c0)) / (ty - 0x2dc) + 0x3d0
	_rays[key] = out
	return out

## 0x485720 (target, viewer, eye term): the eye is the viewer's height + 2 + extra (at most 7); every ray cell before the
## target (the viewer's own included) must lie at or below the straight line from the eye to the target's height
## (0x485a50, integer division toward zero); a ray cell off the map blocks. Outside the 61 x 61 window: clear (the
## original's table has no entry there; sight radii stay far inside it).
func line_of_sight(target: Vector2i, viewer: Vector2i, extra: int = 0) -> bool:
	if line_of_sight_option < 2 or heights.is_empty(): return true
	if target == viewer: return true
	var dx := target.x - viewer.x
	var dy := target.y - viewer.y
	if absi(dx) > LOS_CENTRE or absi(dy) > LOS_CENTRE: return true
	var cells := ray(dx, dy)
	var count := cells.size() / 2
	var eye := mini(height_at(viewer) + 2 + extra, EYE_MAX)
	var goal := height_at(target)
	for i in range(1, count):
		var cx: int = cells[(i - 1) * 2] - LOS_CENTRE + viewer.x
		var cy: int = cells[(i - 1) * 2 + 1] - LOS_CENTRE + viewer.y
		if cx < 0 or cy < 0 or cx >= width or cy >= height: return false
		if height_at(Vector2i(cx, cy)) > ((goal - eye) * i) / count + eye: return false
	return true

## Test/fixture helper: run a full darken cycle of updates (160).
func settle(sources: Array, viewers: Array):
	for i in CYCLE_UPDATES: update(sources, viewers)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self)

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state)
