extends Node2D
## Enhanced visuals (ENHANCED_VISUALS.md): a deliberate modern change, presentation only. Nothing here reads or changes the
## simulation; it only looks at what the world already draws. Every part follows its row on the Options screen's Visuals
## tab (display.gd visual_rows) and is off while "Enhanced Visuals" is off; F9 in a match flips that master switch.
## * Soft shadows: the sheets' shadow band feathered and tinted in team_colour.gdshader (ArtData.set_soft_shadows).
## * Colour grade: a screen pass over the world only (below the HUD layer): warm light, cooler shade, a little saturation,
##   slow cloud shadows anchored to the map, and a light vignette on the world view.
## * Effect glow: light under the fog at the original fires, explosions and conversion flashes, and on each of those
##   frames an additive copy with a small halo (effect_boost.gdshader).
## * Fog edges: the fog overlay filtered between cells instead of one hard block per cell.
## * Camera: eased movement for the view's jumps and scrolling (Camera2D smoothing); jumps of more than two views snap.
## * Hover outline: a thin line around the unit or building under the cursor (hover_outline.gdshader).
## * Terrain: fine sand / grass detail over the painted panels (terrain_detail.gdshader) and ground scatter (ground_scatter.gd).
## * Dust and sand: puffs at the feet of walking ground units, and faint drifting sand over the view.
## * Combat effects: embers, sparks, smoke, debris, scorch marks, hit flashes, missile trails, death dust and corpse fades
##   (combat_fx.gd).
## * Weather: rain, snow, fog or a sandstorm over the world view, or the one matching the map (weather_fx.gd).

const DisplayConfig = preload("res://core/display.gd")
const ArtData = preload("res://core/art_data.gd")
const GRADE_LAYER := 2                    # above the world (layer 0), below the HUD (5)
const GLOW_Z := 3990                      # under the fog overlay (4000), so hidden effects stay hidden
const SAND_Z := 3980
const DUST_Z := 3970                      # over the units: the puffs rise around their feet
const DUST_INTERVAL_MS := 120
const DUST_LIFE_MS := 900
const GRADE_AMOUNT := [0.0, 0.6, 1.0]     # Colour Grade: Off / Subtle / Full
const GLOW_AMOUNT := [0.0, 0.65, 1.0]     # Effect Glow: Off / Subtle / Full
const CAMERA_SPEED := 9.0
const BOOSTED := ["EF", "EX", "EZ"]       # effect code prefixes that get the additive copy and halo

var main: Node
var enabled := false                      # the master switch, as last applied
var grade_on := false
var glow_level := 0
var fog_smooth := false
var camera_smooth := false
var highlight := false
var terrain_level := 0
var ambience := false
var grade_layer: CanvasLayer
var grade: ColorRect
var glow: Node2D
var dust: Node2D
var sand: Node2D
var outline: Sprite2D
var soft_dot: Texture2D
var glow_dot: Texture2D
var puffs: Array = []                     # [position, born ms, size, drift]
var next_dust: Dictionary = {}            # unit id -> ms of its next puff
var grains: Array = []                    # [position, speed, length, alpha]
var scatter: Node2D                       # ground_scatter.gd, built the first time plants are on in a match
var terrain: CanvasItem                   # main.gd's terrain layer (terrain_layer.gd): terrain_detail.gdshader while on
var terrain_material: ShaderMaterial
var boost_shader: Shader
var combat_fx: Node2D                     # combat_fx.gd
var weather_fx: Node                      # weather_fx.gd

class Layer extends Node2D:
	var paint: Callable
	func _draw():
		if paint.is_valid(): paint.call(self)

## The additive copy of one effect frame, a child of effects_layer.gd's sprite node (same depth, drawn after it).
class Boost extends Node2D:
	func _draw():
		var parent = get_parent()
		for r in parent.rects: draw_texture_rect_region(parent.tex, Rect2(r[1], r[0].size), r[0])

func _ready():
	soft_dot = radial(32, [Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	glow_dot = radial(128, [Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.3), Color(1, 1, 1, 0)])
	boost_shader = preload("res://visuals/effect_boost.gdshader")
	grade_layer = CanvasLayer.new()
	grade_layer.layer = GRADE_LAYER
	add_child(grade_layer)
	grade = ColorRect.new()
	grade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://visuals/enhanced_grade.gdshader")
	grade.material = material
	grade_layer.add_child(grade)
	dust = make_layer(DUST_Z, paint_dust)
	sand = make_layer(SAND_Z, paint_sand)
	glow = make_layer(GLOW_Z, paint_glow)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	outline = Sprite2D.new()
	outline.region_enabled = true
	outline.centered = false
	outline.z_as_relative = false
	outline.visible = false
	var outline_material := ShaderMaterial.new()
	outline_material.shader = preload("res://visuals/hover_outline.gdshader")
	outline.material = outline_material
	add_child(outline)
	combat_fx = preload("res://visuals/combat_fx.gd").new()
	combat_fx.main = main
	combat_fx.soft_dot = soft_dot
	add_child(combat_fx)
	weather_fx = preload("res://visuals/weather_fx.gd").new()
	weather_fx.main = main
	add_child(weather_fx)
	scatter = preload("res://visuals/ground_scatter.gd").new()
	scatter.main = main
	add_child(scatter)
	terrain_material = ShaderMaterial.new()
	terrain_material.shader = preload("res://visuals/terrain_detail.gdshader")
	if main != null and "terrain_layer" in main: terrain = main.terrain_layer
	var manager := DisplayConfig.node(get_tree())
	if manager != null: manager.changed.connect(apply_settings)
	apply_settings()

func make_layer(z: int, paint: Callable) -> Node2D:
	var layer := Layer.new()
	layer.z_index = z
	layer.z_as_relative = false
	layer.paint = paint
	add_child(layer)
	return layer

static func radial(size: int, colours: Array) -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	gradient.colors = PackedColorArray(colours)
	var t := GradientTexture2D.new()
	t.gradient = gradient
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t

# ------------------------------------------------------------------------------------------------ settings
## Reads the Visuals rows (display.gd) and switches every part to match; called at start and after each Options change.
func apply_settings():
	enabled = bool(DisplayConfig.visual("Enhanced"))
	var shadows := bool(DisplayConfig.visual("SoftShadows"))
	if shadows != ArtData.soft_shadows:
		ArtData.set_soft_shadows(shadows)
		if main != null:
			for object in main.map_objects: object.apply_material()
	grade_on = int(DisplayConfig.visual("Grade")) > 0
	grade_layer.visible = grade_on
	(grade.material as ShaderMaterial).set_shader_parameter("amount", GRADE_AMOUNT[int(DisplayConfig.visual("Grade"))])
	glow_level = int(DisplayConfig.visual("Glow"))
	glow.visible = glow_level > 0
	if glow_level == 0: clear_boosts()
	fog_smooth = bool(DisplayConfig.visual("SmoothFog"))
	if main != null and main.get("fog_overlay") != null:
		main.fog_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR if fog_smooth else CanvasItem.TEXTURE_FILTER_NEAREST
	camera_smooth = bool(DisplayConfig.visual("SmoothCamera"))
	if main != null and main.get("camera") != null:
		main.camera.position_smoothing_speed = CAMERA_SPEED
		main.camera.position_smoothing_enabled = camera_smooth
		main.camera.reset_smoothing()
	highlight = bool(DisplayConfig.visual("Highlight"))
	outline.visible = false
	terrain_level = int(DisplayConfig.visual("Terrain"))
	if terrain != null: terrain.material = terrain_material if terrain_level >= 1 else null
	scatter.visible = terrain_level >= 2
	ambience = bool(DisplayConfig.visual("Ambience"))
	dust.visible = ambience
	sand.visible = ambience
	combat_fx.set_level(int(DisplayConfig.visual("Combat")))
	weather_fx.set_weather(int(DisplayConfig.visual("Weather")), int(DisplayConfig.visuals.WeatherStrength))
	puffs.clear()
	grains.clear()

## The master switch for this run only (captures and tests; not saved).
func set_enabled(on: bool):
	DisplayConfig.set_visual("Enhanced", on)
	apply_settings()

## F9: the master switch, saved like an Options change.
func toggle_enhanced():
	DisplayConfig.set_visual("Enhanced", not bool(DisplayConfig.visuals.Enhanced))
	DisplayConfig.save_settings()
	apply_settings()

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F9:
		toggle_enhanced()
		get_viewport().set_input_as_handled()

func _process(delta: float):
	if not enabled or main == null: return
	var now := Time.get_ticks_msec()
	var zoom: float = main.camera.zoom.x
	var origin: Vector2 = main.view_top_left()
	var view := Rect2(origin, main.view_screen_size() / zoom)
	if grade_on: update_grade(now, origin, zoom)
	weather_fx.step(now, origin, zoom)
	if camera_smooth and main.camera.get_screen_center_position().distance_to(main.camera.position) > view.size.length() * 2.0:
		main.camera.reset_smoothing()          # a jump across the map (Home, an alert far away) snaps instead of sliding
	if terrain_level >= 2 and main.collision != null:
		scatter.build()
		scatter.refresh_buildings()
	if ambience:
		step_dust(now, view)
		step_sand(view, delta)
		dust.queue_redraw()
		sand.queue_redraw()
	if glow_level > 0:
		update_boosts()
		glow.queue_redraw()
	update_outline()
	combat_fx.step(delta)

func update_grade(now: int, origin: Vector2, zoom: float):
	var screen: Vector2 = get_viewport().get_visible_rect().size
	grade.size = screen
	var m: ShaderMaterial = grade.material
	m.set_shader_parameter("screen_px", screen)
	m.set_shader_parameter("view_px", main.view_screen_size())
	m.set_shader_parameter("view_left", main.view_screen_left() if main.has_method("view_screen_left") else 0.0)
	m.set_shader_parameter("view_origin", origin)
	m.set_shader_parameter("world_per_px", 1.0 / zoom)
	m.set_shader_parameter("time_s", now / 1000.0)

# ------------------------------------------------------------------------------------------------ dust
func step_dust(now: int, view: Rect2):
	puffs = puffs.filter(func(p): return now - int(p[1]) < DUST_LIFE_MS)
	var area := view.grow(64)
	for u in main.units:
		if u.flying or u.dying or u.removed or u.inside_building or not u.in_step or not u.is_visible_in_tree(): continue
		if not area.has_point(u.position): continue
		if now < int(next_dust.get(u.unit_id, 0)): continue
		next_dust[u.unit_id] = now + DUST_INTERVAL_MS + randi() % 60
		var size := 9.0 * float(u.extent)
		puffs.append([u.position + Vector2(randf_range(-6, 6), randf_range(-2, 3)), now, size,
			Vector2(randf_range(-8, 8), randf_range(-10, -4))])

func paint_dust(layer: CanvasItem):
	var now := Time.get_ticks_msec()
	for p in puffs:
		var t: float = float(now - int(p[1])) / DUST_LIFE_MS
		var r: float = float(p[2]) * (0.6 + 1.6 * t)
		var at: Vector2 = p[0] + p[3] * t
		layer.draw_texture_rect(soft_dot, Rect2(at - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), false,
			Color(0.96, 0.89, 0.74, 0.42 * (1.0 - t) * (1.0 - t)))

# ------------------------------------------------------------------------------------------------ drifting sand
func step_sand(view: Rect2, delta: float):
	while grains.size() < 36:
		grains.append([view.position + Vector2(randf() * view.size.x, randf() * view.size.y),
			randf_range(60, 140), randf_range(14, 40), randf_range(0.04, 0.10)])
	for g in grains:
		g[0] += Vector2(1.0, 0.22) * float(g[1]) * delta
		if not view.grow(80).has_point(g[0]):   # re-enter from the upwind side
			g[0] = Vector2(view.position.x - randf() * 60, view.position.y + randf() * view.size.y)

func paint_sand(layer: CanvasItem):
	for g in grains:
		var d := Vector2(1.0, 0.22).normalized() * float(g[2])
		layer.draw_line(g[0], g[0] - d, Color(0.92, 0.82, 0.64, float(g[3])), 1.5, true)

# ------------------------------------------------------------------------------------------------ effect glow
## Light colour and radius by effect code (EFFECTS_RESEARCH.md): EF01..EF03 building fires, EX01/EX02 destruction,
## EZ01 conversion flash, EZ08 lair spawn.
static func glow_of(code: String) -> Array:
	if code.begins_with("EF"): return [Color(1.0, 0.55, 0.18), 80.0, true]
	if code.begins_with("EX"): return [Color(1.0, 0.62, 0.25), 130.0, false]
	if code == "EZ01": return [Color(1.0, 0.86, 0.45), 110.0, false]
	if code == "EZ08": return [Color(0.65, 0.75, 1.0), 90.0, false]
	return []

func paint_glow(layer: CanvasItem):
	var effects = main.effects if main != null else null
	if effects == null: return
	var t := Time.get_ticks_msec() / 1000.0
	for e in effects.effects:
		if not e.alive or not is_instance_valid(e.node) or not e.node.visible: continue
		var g := glow_of(String(e.code))
		if g.is_empty(): continue
		var strength: float = 0.42 * GLOW_AMOUNT[glow_level]
		var radius: float = g[1]
		if g[2]:   # fires flicker
			var seed := float(int(e.pixel.x) * 7 + int(e.pixel.y) * 13)
			strength *= 0.82 + 0.18 * sin(t * 9.0 + seed) * sin(t * 5.3 + seed * 0.5)
		else:      # one-shot effects fade over their frames
			strength *= 1.0 - float(e.frame) / maxf(1.0, float(e.frames))
		var at := Vector2(e.pixel) + Vector2(0, -14)
		layer.draw_texture_rect(glow_dot, Rect2(at - Vector2(radius, radius * 0.72), Vector2(radius * 2, radius * 1.44)),
			false, Color(g[0].r, g[0].g, g[0].b, strength))

## Every live fire / explosion / magic effect gets one Boost child; its material follows the frame shown.
func update_boosts():
	var effects = main.effects
	if effects == null: return
	for e in effects.effects:
		if not e.alive or not is_instance_valid(e.node): continue
		var code := String(e.code)
		if not BOOSTED.any(func(p): return code.begins_with(p)): continue
		var node = e.node
		var boost: Boost = node.get_meta("boost") if node.has_meta("boost") else null
		if boost == null:
			boost = Boost.new()
			var m := ShaderMaterial.new()
			m.shader = boost_shader
			boost.material = m
			node.add_child(boost)
			node.set_meta("boost", boost)
		if node.rects.is_empty() or node.tex == null: continue
		var size := Vector2(node.tex.get_size())
		var src: Rect2 = node.rects[0][0]
		var bm: ShaderMaterial = boost.material
		bm.set_shader_parameter("region", Vector4(src.position.x / size.x, src.position.y / size.y, src.size.x / size.x, src.size.y / size.y))
		bm.set_shader_parameter("sharp", 0.2 * GLOW_AMOUNT[glow_level])
		bm.set_shader_parameter("halo", 0.4 * GLOW_AMOUNT[glow_level])
		boost.queue_redraw()

func clear_boosts():
	if main == null or main.effects == null: return
	for e in main.effects.effects:
		if is_instance_valid(e.node) and e.node.has_meta("boost"):
			var boost = e.node.get_meta("boost")
			if is_instance_valid(boost): boost.queue_free()
			e.node.remove_meta("boost")

# ------------------------------------------------------------------------------------------------ hover outline
## The unit or building under the cursor (main.gd hover_info) gets a thin outline: own warm white, enemy red, others grey.
func update_outline():
	outline.visible = false
	if not highlight or main.get("hover_info") == null: return
	var info: Dictionary = main.hover_info
	if info.is_empty() or bool(info.get("fogged", false)): return
	var sprite: Sprite2D = null
	var owner_id := -1
	if info.kind == "unit" and is_instance_valid(info.object):
		var u = info.object
		if u.dying or u.removed or not u.is_visible_in_tree(): return
		sprite = u.sprite
		owner_id = int(u.owner_id)
	elif info.kind == "building":
		var node = main.building_nodes.get(info.object.entity_id) if main.get("building_nodes") != null else null
		if node == null or not is_instance_valid(node) or not node.is_visible_in_tree(): return
		sprite = node.base
		owner_id = int(info.object.owner)
	if sprite == null or sprite.texture == null or not sprite.is_visible_in_tree(): return
	outline.texture = sprite.texture
	outline.region_rect = sprite.region_rect
	outline.offset = sprite.offset
	outline.flip_h = sprite.flip_h
	outline.centered = sprite.centered
	outline.global_transform = sprite.global_transform
	outline.z_index = sprite.get_parent().z_index + 1 if sprite.get_parent() is CanvasItem else 4000
	var size := Vector2(sprite.texture.get_size())
	var r := sprite.region_rect
	var m: ShaderMaterial = outline.material
	m.set_shader_parameter("region", Vector4(r.position.x / size.x, r.position.y / size.y, r.size.x / size.x, r.size.y / size.y))
	var colour := Color(0.85, 0.85, 0.85, 0.55)
	if owner_id == int(main.local_player): colour = Color(1.0, 0.95, 0.75, 0.7)
	elif bool(info.get("own", false)) == false and owner_id >= 0 and owner_id < 6: colour = Color(1.0, 0.45, 0.38, 0.75)
	m.set_shader_parameter("line_colour", colour)
	outline.visible = true
