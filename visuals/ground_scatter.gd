extends Node2D
## Enhanced visuals ground scatter (ENHANCED_VISUALS.md): grass tufts on the grass plateaus, sparse dry tufts, scrub and
## pebbles on the sand. Presentation only, drawn just above the terrain (under every unit, building and the fog), so it
## can never hide anything the player needs to see.
## * Where: from the cell data (raw TER material, COLLISION_RESEARCH.md: 0 on the grass plateaus, 2 on the sand) and the
##   painted colour under each point (roads, rock, cliffs and rubble get nothing). Cells with a map building or feature
##   stay clear, and so do the cells of every building placed later (checked twice a second).
## * Look: generated here (no outside art), coloured from the map's own grass and sand tones, at twice world resolution
##   so it stays crisp at the larger interface scales. Thin separate blades with lit tips; pebbles lit from above.
## * Deterministic: one seed per cell, so clearing cells never reshuffles the rest.

const CELL := Vector2(32, 24)
const CHUNK := 16                          # cells per chunk side (512 x 384 world pixels)
const TILE := 24                           # world pixels per atlas tile
const RES := 2                             # atlas pixels per world pixel
const SUPER := 3                           # each tile is drawn at RES * SUPER, then downsampled (soft edges)
const TUFTS := [0, 1, 2, 3]                # row 0 (sways)
const DRY := [4, 5]
const SCRUB := [6]
const PEBBLES := [0, 1, 2]                 # row 1 (static)
const SHADOW := 3
const COLUMNS := 7

var main: Node
var atlas: ImageTexture
var terrain                               # main.gd's terrain_layer.gd (W1: the map's MAPH records, no baked image)
var chunks: Dictionary = {}                # Vector2i chunk -> Chunk
var cleared: Dictionary = {}               # Vector2i cell -> true
var known_buildings: Dictionary = {}
var next_check_ms := 0
var built := false

class Chunk extends Node2D:
	var items: Array = []                  # [position, column, row, tint, cell, mirrored, scale]
	var owner_scatter
	func _draw():
		owner_scatter.paint_chunk(self)

func build():
	if built: return
	built = true
	atlas = ImageTexture.create_from_image(make_atlas())
	terrain = main.terrain_layer
	var material := ShaderMaterial.new()
	material.shader = preload("res://visuals/scatter_sway.gdshader")
	for y in main.collision.height:
		for x in main.collision.width:
			scatter_cell(Vector2i(x, y))
	for key in chunks:
		var chunk: Chunk = chunks[key]
		chunk.items.sort_custom(func(a, b): return a[0].y < b[0].y)
		chunk.material = material
		chunk.z_index = -1 - preload("res://core/map_data.gd").depth_offset      # M-2: under the shifted world depths on tall maps (map_data.gd)
		chunk.z_as_relative = false
		add_child(chunk)

func chunk_of(cell: Vector2i) -> Chunk:
	var key := Vector2i(cell.x / CHUNK, cell.y / CHUNK)
	if not chunks.has(key):
		var chunk := Chunk.new()
		chunk.owner_scatter = self
		chunks[key] = chunk
	return chunks[key]

## Painted colour class at a world point: "grass", "sand" or "" (the same rule as terrain_detail.gdshader).
func ground(at: Vector2) -> Array:
	var c: Color = terrain.colour_at(Vector2(int(at.x), int(at.y)))
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	if c.g - c.r > 0.05 and c.g - c.b > 0.09: return ["grass", c]
	if c.r - c.b > 0.14 and lum > 0.45 and lum < 0.85: return ["sand", c]
	return ["", c]

func scatter_cell(cell: Vector2i):
	var data: Dictionary = main.collision.cell_data(cell)
	if data.is_empty() or not data.get("object_indices", []).is_empty(): return
	var material: int = int(data.raw[1])
	if material != 0 and material != 2: return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(cell) ^ 0x5eed
	var origin := Vector2(cell) * CELL
	for i in (2 if material == 0 else 1):
		var at := origin + Vector2(rng.randf() * CELL.x, rng.randf() * CELL.y)
		var g := ground(at)
		var roll := rng.randf()
		var column := -1
		var row := 0
		if g[0] == "grass" and material == 0:
			if roll < 0.4: column = TUFTS[rng.randi() % TUFTS.size()]
		elif g[0] == "sand" and material == 2:
			if roll < 0.035: column = DRY[rng.randi() % DRY.size()]
			elif roll < 0.05: column = SCRUB[0]
			elif roll < 0.10:
				column = PEBBLES[rng.randi() % PEBBLES.size()]
				row = 1
		if column < 0: continue
		# A little of the ground's own colour, so each piece sits in its patch of the painting.
		var tint: Color = Color.WHITE.lerp(g[1] * 1.5, 0.4 if row == 1 else 0.3)
		tint.a = 1.0
		var count := 1
		if row == 0 and TUFTS.has(column): count = 2 + rng.randi() % 3   # grass grows in small clumps
		for n in count:
			var spot := at + (Vector2(rng.randf_range(-7, 7), rng.randf_range(-4, 4)) if n > 0 else Vector2.ZERO)
			var piece: int = column if n == 0 else int(TUFTS[rng.randi() % TUFTS.size()])
			chunk_of(cell).items.append([spot, piece, row, tint, cell, rng.randf() < 0.5, rng.randf_range(0.8, 1.15)])

func paint_chunk(chunk: Chunk):
	var src := Vector2(TILE, TILE) * RES
	for item in chunk.items:
		if cleared.has(item[4]): continue
		var at: Vector2 = item[0]
		var k: float = item[6]
		var piece: bool = item[2] == 0
		# Contact shadow up-left of the base (the sheets' shadows fall that way), then the piece on the point.
		var sw := TILE * (0.55 if piece else 0.4) * k
		chunk.draw_texture_rect_region(atlas, Rect2(at + Vector2(-sw * 0.8, -sw * 0.35), Vector2(sw, sw * 0.45)),
			Rect2(Vector2(SHADOW, 1) * src, src), Color(1, 1, 1, 0.35 if piece else 0.3))
		var size := Vector2(TILE, TILE) * k * (1.0 if piece else 0.5)
		var rect := Rect2(at - Vector2(size.x * 0.5, size.y - (1.0 if piece else size.y * 0.3)), size)
		if item[5]: rect = Rect2(rect.position + Vector2(rect.size.x, 0), Vector2(-rect.size.x, rect.size.y))   # mirrored
		chunk.draw_texture_rect_region(atlas, rect, Rect2(Vector2(int(item[1]), int(item[2])) * src, src), item[3])

## Cells under buildings placed during the match lose their scatter (rubble keeps the ground clear too).
func refresh_buildings():
	var now := Time.get_ticks_msec()
	if now < next_check_ms or main.get("building_nodes") == null: return
	next_check_ms = now + 500
	var dirty := {}
	for id in main.building_nodes:
		if known_buildings.has(id): continue
		known_buildings[id] = true
		var node = main.building_nodes[id]
		if node == null or not is_instance_valid(node) or node.building == null: continue
		var r: Rect2i = node.building.cell_rect().grow(1)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cleared[Vector2i(x, y)] = true
				dirty[Vector2i(x / CHUNK, y / CHUNK)] = true
	for key in dirty:
		if chunks.has(key): chunks[key].queue_redraw()

# ------------------------------------------------------------------------------------------------ the atlas
func make_atlas() -> Image:
	var px := TILE * RES
	var image := Image.create(COLUMNS * px, 2 * px, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20021031
	var lush := [Color(0.13, 0.20, 0.07), Color(0.36, 0.47, 0.19)]
	var dry := [Color(0.36, 0.30, 0.15), Color(0.86, 0.76, 0.48)]
	for k in TUFTS.size(): paste(image, tuft(rng, 11 + k * 3, 0.50 + 0.08 * k, lush), TUFTS[k], 0)
	for k in DRY.size(): paste(image, tuft(rng, 6 + k * 3, 0.45 + 0.1 * k, dry), DRY[k], 0)
	paste(image, scrub(rng), SCRUB[0], 0)
	for k in PEBBLES.size(): paste(image, pebble(rng, 0.55 + 0.15 * k), PEBBLES[k], 1)
	paste(image, blob(), SHADOW, 1)
	return image

func paste(atlas_image: Image, big: Image, column: int, row: int):
	var px := TILE * RES
	big.resize(px, px, Image.INTERPOLATE_CUBIC)
	atlas_image.blit_rect(big, Rect2i(0, 0, px, px), Vector2i(column, row) * px)

## A clear canvas whose transparent pixels carry `base` (no dark fringe when downsampling).
func canvas(base: Color) -> Image:
	var size := TILE * RES * SUPER
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(base.r, base.g, base.b, 0.0))
	return image

func disc(image: Image, centre: Vector2, radius: float, colour: Color):
	var r := int(ceil(radius))
	for y in range(int(centre.y) - r, int(centre.y) + r + 1):
		for x in range(int(centre.x) - r, int(centre.x) + r + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height(): continue
			if Vector2(x + 0.5, y + 0.5).distance_to(centre) <= radius: image.set_pixel(x, y, colour)

## Thin blades from a common root, each from the dark base colour to a lit tip (blades leaning right catch more light).
func tuft(rng: RandomNumberGenerator, blades: int, height: float, palette: Array) -> Image:
	var image := canvas(palette[0])
	var s := float(image.get_width())
	var root := Vector2(s * 0.5, s - 2.0)
	for b in blades:
		var lean := rng.randf_range(-0.55, 0.55)
		var h := s * height * rng.randf_range(0.55, 1.0)
		var curl := (rng.randf_range(-0.2, 0.2) + lean * 0.4) * h
		var base := root + Vector2(rng.randf_range(-s * 0.1, s * 0.1), 0)
		var lit := 0.85 + (0.25 if lean > 0.1 else 0.0) + rng.randf_range(-0.1, 0.1)
		var steps := 60
		for i in steps + 1:
			var t := float(i) / steps
			var p := base + Vector2(lean * h * 0.35 * t + curl * t * t, -h * t)
			var colour: Color = palette[0].lerp(palette[1] * lit, pow(t, 0.7))
			colour.a = 1.0
			disc(image, p, lerpf(s * 0.022, s * 0.007, t), colour)
	return image

func scrub(rng: RandomNumberGenerator) -> Image:
	var bark := Color(0.30, 0.25, 0.19)
	var image := canvas(bark)
	var s := float(image.get_width())
	var stack := []
	for k in 4: stack.append([Vector2(s * 0.5 + rng.randf_range(-4, 4), s - 3.0), -PI / 2 + rng.randf_range(-0.9, 0.9), s * 0.2, 2])
	var leaves := []
	while not stack.is_empty():
		var twig: Array = stack.pop_back()
		var from: Vector2 = twig[0]
		var to: Vector2 = from + Vector2.from_angle(twig[1]) * float(twig[2])
		for i in 31:
			var t := i / 30.0
			var c := bark.lerp(Color(0.55, 0.50, 0.42), t * 0.6)
			disc(image, from.lerp(to, t), lerpf(s * 0.016, s * 0.008, t) * (0.7 + 0.15 * float(twig[3])), c)
		if int(twig[3]) > 0:
			for k in 2 + rng.randi() % 2:
				stack.append([to, float(twig[1]) + rng.randf_range(-0.7, 0.7), float(twig[2]) * 0.7, int(twig[3]) - 1])
		else:
			leaves.append(to)
	for p in leaves:   # small grey-green leaf clusters, lit from above
		for k in 3: disc(image, p + Vector2(rng.randf_range(-4, 4), rng.randf_range(-4, 3)), s * 0.03, Color(0.44, 0.52, 0.33).lerp(Color(0.70, 0.76, 0.55), rng.randf()))
	return image

func pebble(rng: RandomNumberGenerator, size: float) -> Image:
	var image := canvas(Color(0.5, 0.47, 0.42))
	var s := float(image.get_width())
	var centre := Vector2(s * 0.5, s * 0.6)
	var radius := Vector2(s * 0.42 * size, s * 0.3 * size)
	var light := Vector3(0.35, -0.6, 0.72).normalized()   # from above, a little to the right: reads as a raised stone
	var wobble := rng.randf_range(0.0, TAU)
	for y in image.get_height():
		for x in image.get_width():
			var d := (Vector2(x + 0.5, y + 0.5) - centre) / radius
			var edge := 1.0 + 0.08 * sin(atan2(d.y, d.x) * 3.0 + wobble)
			if d.length() > edge: continue
			var n := Vector3(d.x, d.y, sqrt(maxf(0.0, 1.0 - minf(1.0, d.length_squared())))).normalized()
			var v := 0.5 + 0.55 * maxf(0.0, n.dot(light))
			image.set_pixel(x, y, Color(v * 0.80, v * 0.75, v * 0.67))
	return image

func blob() -> Image:
	var image := canvas(Color(0.06, 0.05, 0.08))
	var s := float(image.get_width())
	for y in image.get_height():
		for x in image.get_width():
			var d := (Vector2(x + 0.5, y + 0.5) - Vector2(s, s) * 0.5) / (s * 0.5)
			var a := clampf(1.0 - d.length(), 0.0, 1.0)
			image.set_pixel(x, y, Color(0.06, 0.05, 0.08, a * a * 0.8))
	return image
