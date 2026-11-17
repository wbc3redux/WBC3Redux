extends Node2D
## The map's ground (decided 2026-11-01, CONTENT_EXPANSION_PLAN.md 4.2): one textured quad per MAPH record, drawn from the
## terrain-set bitmaps the importer writes once for every map (assets/terrain/<CODE>.png) by the map's draw list
## (assets/maps/<slug>/terrain.json: record i at ((i % cols) * 320, (i // cols) * 240), cols = ceil(width / 10), crop
## ((q & 1) * 320, (q >> 1) * 240), 0x4937d0 / 0x494862). Replaces the single baked terrain.png sprite: Desert Sands
## composes pixel-identical to it (importer gate, tests/test_map_data.gd). At the whole-step view scales above 1x the
## linear filter clamps at each record's edge instead of blending into the next record (a one-pixel seam difference
## against one big texture, presentation only).
const Assets = preload("res://core/asset_store.gd")

const MapData = preload("res://core/map_data.gd")

var layout: Dictionary
var world_size := Vector2.ZERO
var columns := 1
var textures: Dictionary = {}    # code -> Texture2D
var images: Dictionary = {}      # code -> Image (colour sampling, loaded on demand)

func setup(slug: String = "") -> void:
	layout = MapData.terrain(slug)
	world_size = Vector2(layout.world_size[0], layout.world_size[1])
	columns = ceili(world_size.x / 320.0)
	textures.clear()
	images.clear()
	for d in layout.draws:
		if not textures.has(d.code): textures[d.code] = Assets.texture(String(d.texture))
	queue_redraw()

func _draw():
	for d in layout.get("draws", []):
		var s: Array = d.source_rect
		draw_texture_rect_region(textures[d.code], Rect2(d.destination[0], d.destination[1], s[2], s[3]), Rect2(s[0], s[1], s[2], s[3]))

## The draw covering a world point (clamped to the map).
func draw_at(world: Vector2) -> Dictionary:
	var p := world.clamp(Vector2.ZERO, world_size - Vector2.ONE)
	var index := int(p.y / 240.0) * columns + int(p.x / 320.0)
	return layout.draws[index] if index < layout.draws.size() else {}

func tile_image(code: String) -> Image:
	if not images.has(code):
		var image := Image.new()      # the PNG bytes (an imported texture keeps no CPU copy under the headless renderer)
		image.load_png_from_buffer(Assets.bytes("terrain/" + code + ".png"))
		image.convert(Image.FORMAT_RGB8)
		images[code] = image
	return images[code]

## The painted colour at a world point (ground scatter picks its pieces by it).
func colour_at(world: Vector2) -> Color:
	var d := draw_at(world)
	if d.is_empty(): return Color.BLACK
	var p := Vector2i(world.clamp(Vector2.ZERO, world_size - Vector2.ONE))
	var s: Array = d.source_rect
	return tile_image(String(d.code)).get_pixel(int(s[0]) + p.x - int(d.destination[0]), int(s[1]) + p.y - int(d.destination[1]))

## The whole map as one image from the draw list (checks only: the game never builds it).
func compose() -> Image:
	var image := Image.create(int(world_size.x), int(world_size.y), false, Image.FORMAT_RGB8)
	for d in layout.draws:
		var s: Array = d.source_rect
		image.blit_rect(tile_image(String(d.code)), Rect2i(s[0], s[1], s[2], s[3]), Vector2i(d.destination[0], d.destination[1]))
	return image
