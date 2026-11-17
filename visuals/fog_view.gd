extends RefCounted
## P-4 (EFFECTS_RESEARCH.md "P-4"): which world sprites the original draws under fog of war and shroud. Presentation only:
## it reads simulation/visibility.gd's bytes and never writes them; nothing here feeds back into the simulation.
## * 0x47f560 (Read, wbc3_decomp.c 86690): neither fog (+0xf2bf9) nor shroud (+0xf2bfa) -> true; fog on -> the visible
##   byte, inside the viewport from the drawing copy +0x8e1f5; shroud only -> the explored byte (inside the viewport its
##   drawing copy +0x8e1f6; that copy is not ported, the explored byte stands in).
## * The drawing copy (Read: 0x47ee70 -> 0x47ef70 / 0x47efd0 / 0x47f040 / 0x47f0a0 / 0x47f110 / 0x47f210 / 0x47f320 /
##   0x47f440, refreshed per dirty 3 x 3 block by 0x47aab0 in the view draw 0x48fb80): the map is cut into blocks of
##   3 x 3 cells; the centre cell copies its visible byte, every border cell is lit when it or its neighbour across the
##   block border is visible (a corner: the 2 x 2 cells round the block corner). So a cell c with c.x % 3 == 0 also looks
##   at x - 1, with c.x % 3 == 2 at x + 1, the same for y, and a corner at the diagonal too. Not ported: the map-edge quirk
##   (blocks in row / column 0 leave some border cells unwritten, so they never count as lit; the map's outer ring).
## * 0x547c00 (Read, 217257; every fourth view draw, whole map): every sprite of kind != 2 gets +0x76 = 0x47f560(its cell
##   +0x48 / +0x4a) (buildings test four cells); when it is lit, +0x131 = 1 for good. 0x534c40 starts +0x76 at 0 when fog
##   or shroud is on.
## * 0x547530 (Read, 217064): the view draw collects only sprites with +0x76 or +0x131 set.
## * Kind 6 effects, draw 0x53ca70 (Read, disassembly 0x53ca95..0x53caa9): with fog on and +0x76 clear, not drawn
##   (every time; +0x131 does not help). Their step 0x53cc20 bursts an emitter's particles only while +0x76 is set.
## * Kind 8 particle bursts (0x5434a0, draw 0x544330: no own test), kind 9 missiles (0x53df60 / 0x53e960, draw 0x53f6b0
##   sets +0x131 when it draws), kind 11 map emitters (0x545760, draw 0x5459f0 sets +0x131): drawn once their cell was lit
##   at a 0x547c00 pass, from then on even in the fog. A missile is marked at creation when its shooter or its target
##   belongs to the local player, when it has no shooter (+0x85a: spell and sky missiles), or (0x541b80, fog or shroud
##   on) when its launch or its target cell is visible.
## * The view draw order 0x48fb80 (Read, 95466-95540): terrain 0x494720, the fog 0x47ee00 (fog on), the sprites 0x547530,
##   the floating texts 0x549610, the shroud 0x480000 (shroud on), then the order markers 0x49c190 and the rain 0x49b6d0.
##   The fog is under the sprites (it does not hide them: the tests above do); the shroud covers sprites and texts.
##   The rebuild keeps one overlay (main.gd fog_overlay, z 4000) over the world sprites: its 0.45 dimming stands in for the
##   terrain fog (Deliberate, P-2), its opaque shroud is the original's; everything drawn into the world must stay under it.
const OVERLAY_Z := 4000

## 0x47f560 for `player` with the drawing copy (the viewport case; outside the view nobody sees the difference).
static func lit(visibility, player: int, cell: Vector2i) -> bool:
	if visibility == null: return true
	if not visibility.fog and not visibility.shroud: return true
	if cell.x < 0 or cell.y < 0 or cell.x >= visibility.width or cell.y >= visibility.height: return false
	visibility.ensure(player)
	if not visibility.fog: return visibility.explored[player][cell.y * visibility.width + cell.x] != 0
	return drawn_visible(visibility.visible[player], visibility.width, visibility.height, cell)

## The drawing copy +0x8e1f5 of one cell from the visible bytes (index y * width + x): the cell, its neighbour across the
## 3 x 3 block border in x and in y, and the diagonal one at a block corner.
static func drawn_visible(seen: PackedByteArray, width: int, height: int, cell: Vector2i) -> bool:
	var dx := -1 if cell.x % 3 == 0 else (1 if cell.x % 3 == 2 else 0)
	var dy := -1 if cell.y % 3 == 0 else (1 if cell.y % 3 == 2 else 0)
	if _seen(seen, width, height, cell.x, cell.y): return true
	if dx != 0 and _seen(seen, width, height, cell.x + dx, cell.y): return true
	if dy != 0 and _seen(seen, width, height, cell.x, cell.y + dy): return true
	return dx != 0 and dy != 0 and _seen(seen, width, height, cell.x + dx, cell.y + dy)

static func _seen(seen: PackedByteArray, width: int, height: int, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height: return false
	var i := y * width + x
	return i < seen.size() and seen[i] != 0

## 0x53ca70: is a kind 6 effect (an effects_layer.gd effect) drawn at `cell`? Only fog hides it (shroud only: drawn, and
## the shroud covers it).
static func effect_shown(visibility, player: int, cell: Vector2i) -> bool:
	if visibility == null or not visibility.fog: return true
	return lit(visibility, player, cell)

## The sprite cell of an effect, a burst or a map emitter: +0x48 from the pixel (x >> 5, Provisional: the sprite's cell
## column), +0x4a the depth row the rebuild already keeps (0x53ca40 / 0x5439c0 read the same field).
static func sprite_cell(pixel: Vector2i, cell_row: int) -> Vector2i:
	return Vector2i(int(pixel.x) >> 5, cell_row)
