extends Node2D
## Enhanced visuals combat effects (ENHANCED_VISUALS.md, round 2: plan rows 12, 13, 14, 22). Presentation only: it watches
## the state the simulation already keeps (combat.gd fighters, missiles, production buildings, effects_layer.gd effects)
## and never changes it. Driven by enhanced_visuals.gd, which passes the Combat Effects level (1 subtle, 2 full).
## * Fires (EF..): embers rising (additive) and grey smoke.
## * Explosions (EX..), when they appear: a spark burst, debris falling back to the ground, smoke, and a scorch mark
##   on the ground that fades over SCORCH_MS.
## * Hits: a short flash and a few sparks where a unit or building loses hit points.
## * Missiles: a fading trail behind every missile; glowing ones (their sheet is bright and coloured) also carry a glow.
## * Deaths: a dust burst at the unit's feet; the corpse fades out over its last CORPSE_FADE_MS instead of vanishing.
## Particles live on the effects clock (`clock`, advanced only while this runs), capped at MAX_PARTICLES.

const EffectsLayer = preload("res://visuals/effects_layer.gd")
const ADD_Z := 3992                      # under the fog overlay (4000)
const SMOKE_Z := 3975
const DECAL_Z := -1                       # on the ground, under every unit and building (and over the ground scatter)
const MAX_PARTICLES := 700
const MAX_DECALS := 30
const SCORCH_MS := 25000.0
const CORPSE_FADE_MS := 2500.0
const LEVEL_SCALE := [0.0, 0.6, 1.0]

var main: Node
var soft_dot: Texture2D
var level := 0
var clock := 0.0                          # ms
var add_parts: Array = []                 # [pos, vel, born, life, size0, size1, colour, gravity]
var smoke_parts: Array = []
var decals: Array = []                    # [pos, born, radius]
var add_layer: Node2D
var smoke_layer: Node2D
var decal_layer: Node2D
var seen_effects: Dictionary = {}         # effect node instance id -> true
var hp_seen: Dictionary = {}              # fighter id -> last hit points
var building_hp: Dictionary = {}          # building id -> last hit points
var dying_seen: Dictionary = {}           # fighter id -> true
var faded: Dictionary = {}                # unit id -> sprite we changed (restored when off)
var missile_style: Dictionary = {}        # missile sheet code -> [glows, colour]
var ember_due: Dictionary = {}            # effect node id -> clock of its next ember

class Layer extends Node2D:
	var paint: Callable
	func _draw():
		if paint.is_valid(): paint.call(self)

func _ready():
	add_layer = make_layer(ADD_Z, paint_add)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add_layer.material = add
	smoke_layer = make_layer(SMOKE_Z, paint_smoke)
	decal_layer = make_layer(DECAL_Z - preload("res://core/map_data.gd").depth_offset, paint_decals)   # M-2: below the shifted depths

func make_layer(z: int, paint: Callable) -> Node2D:
	var layer := Layer.new()
	layer.z_index = z
	layer.z_as_relative = false
	layer.paint = paint
	add_child(layer)
	return layer

func set_level(value: int):
	level = value
	visible = level > 0
	if level == 0:
		add_parts.clear()
		smoke_parts.clear()
		decals.clear()
		restore_corpses()

func scale_count(n: float) -> int:
	return maxi(1, roundi(n * LEVEL_SCALE[level]))

# ------------------------------------------------------------------------------------------------ per frame
func step(delta: float):
	if level == 0 or main == null: return
	clock += delta * 1000.0
	watch_effects()
	watch_fighters()
	watch_buildings()
	watch_missiles()
	advance(add_parts, delta)
	advance(smoke_parts, delta)
	decals = decals.filter(func(d): return clock - float(d[1]) < SCORCH_MS)
	add_layer.queue_redraw()
	smoke_layer.queue_redraw()
	decal_layer.queue_redraw()

func advance(list: Array, delta: float):
	var keep: Array = []
	for p in list:
		if clock - float(p[2]) >= float(p[3]): continue
		p[1] += Vector2(0, float(p[7])) * delta
		p[0] += p[1] * delta
		keep.append(p)
	list.assign(keep)

func emit(list: Array, pos: Vector2, vel: Vector2, life: float, size0: float, size1: float, colour: Color, gravity: float = 0.0):
	if add_parts.size() + smoke_parts.size() >= MAX_PARTICLES: return
	list.append([pos, vel, clock, life, size0, size1, colour, gravity])

func spark(pos: Vector2, colour: Color, speed: float = 90.0):
	var a := randf() * TAU
	emit(add_parts, pos, Vector2.from_angle(a) * randf_range(speed * 0.4, speed) + Vector2(0, -30), randf_range(250, 500), 3.0, 1.0, colour, 160.0)

func smoke(pos: Vector2, shade: float, life: float = 2200.0):
	emit(smoke_parts, pos, Vector2(randf_range(-6, 6), randf_range(-24, -12)), life * randf_range(0.8, 1.2), 7.0, 22.0,
		Color(shade, shade * 0.97, shade * 0.93, 0.3))

# ------------------------------------------------------------------------------------------------ sources
## Fires keep giving embers and smoke; explosions burst once, when first seen, and leave a scorch mark.
func watch_effects():
	var effects = main.effects
	if effects == null: return
	var alive := {}
	for e in effects.effects:
		if not e.alive or not is_instance_valid(e.node) or not e.node.visible: continue
		var key: int = e.node.get_instance_id()
		alive[key] = true
		var code := String(e.code)
		var at := Vector2(e.pixel)
		if code.begins_with("EF"):
			if clock >= float(ember_due.get(key, 0.0)):
				ember_due[key] = clock + 260.0 / LEVEL_SCALE[level]
				emit(add_parts, at + Vector2(randf_range(-12, 12), randf_range(-36, -14)), Vector2(randf_range(-10, 10), randf_range(-60, -30)),
					randf_range(700, 1300), 2.5, 0.8, Color(1.0, 0.55, 0.15, 0.9))
				if randf() < 0.5: smoke(at + Vector2(randf_range(-8, 8), -40), 0.32)
		elif code.begins_with("EX") and not seen_effects.has(key):
			seen_effects[key] = true
			for i in scale_count(18): spark(at + Vector2(0, -16), Color(1.0, 0.7, 0.3, 1.0), 150.0)
			for i in scale_count(8):
				var a := randf_range(PI * 1.1, PI * 1.9)
				emit(smoke_parts, at + Vector2(0, -10), Vector2.from_angle(a) * randf_range(60, 130), randf_range(500, 800), 2.5, 2.0,
					Color(0.22, 0.18, 0.14, 0.9), 320.0)
			for i in scale_count(6): smoke(at + Vector2(randf_range(-14, 14), randf_range(-24, 0)), 0.4, 2800.0)
			decals.append([at, clock, randf_range(22, 30)])
			if decals.size() > MAX_DECALS: decals.pop_front()
	for key in seen_effects.keys():
		if not alive.has(key): seen_effects.erase(key)
	for key in ember_due.keys():
		if not alive.has(key): ember_due.erase(key)

## Hits (hit points went down) and deaths (state became dying); corpses fade at the end of their time.
func watch_fighters():
	var combat = main.combat
	if combat == null: return
	for id in combat.fighters:
		var f = combat.fighters[id]
		var unit = main.units[id] if id < main.units.size() else null
		if unit == null: continue
		var hp := int(f.hp)
		var before := int(hp_seen.get(id, hp))
		hp_seen[id] = hp
		var shown: bool = unit.is_visible_in_tree()
		if hp < before and shown and f.state != "dying" and f.state != "corpse":
			hit(unit.position + Vector2(randf_range(-4, 4), -20), Color(1.0, 0.85, 0.6, 1.0))
		if (f.state == "dying" or f.state == "corpse") and not dying_seen.has(id):
			dying_seen[id] = true
			if shown and not unit.flying:
				for i in scale_count(6): smoke(unit.position + Vector2(randf_range(-8, 8), randf_range(-3, 3)), 0.78, 1100.0)
		if f.state == "corpse" and not f.removed and unit.sprite != null:
			var left: float = float(combat.corpse_ms(f.type_id)) - float(combat.now_ms - int(f.death_ms))
			unit.sprite.self_modulate.a = clampf(left / CORPSE_FADE_MS, 0.0, 1.0)
			faded[id] = unit.sprite

func watch_buildings():
	var production = main.production
	if production == null: return
	for id in production.buildings:
		var b = production.buildings[id]
		var hp := int(b.hit_points)
		var before := int(building_hp.get(id, hp))
		building_hp[id] = hp
		if hp >= before or b.constructing: continue
		var node = main.building_nodes.get(id) if main.get("building_nodes") != null else null
		if node == null or not is_instance_valid(node) or not node.is_visible_in_tree(): continue
		var r: Rect2i = b.cell_rect()
		if not lit(Vector2(r.get_center().x * 32, r.get_center().y * 24)): continue   # P-4: a remembered building in the fog
		var at := Vector2(r.position.x * 32 + randf() * r.size.x * 32, r.position.y * 24 + randf() * r.size.y * 24 - 30)
		hit(at, Color(1.0, 0.75, 0.45, 1.0))
		for i in scale_count(3):
			emit(smoke_parts, at, Vector2(randf_range(-40, 40), randf_range(-70, -30)), randf_range(400, 700), 2.0, 1.5, Color(0.35, 0.3, 0.26, 0.9), 260.0)

func hit(at: Vector2, colour: Color):
	emit(add_parts, at, Vector2.ZERO, 140.0, 10.0, 16.0, Color(colour.r, colour.g, colour.b, 0.55))
	for i in scale_count(4): spark(at, colour, 70.0)

## Every missile leaves a trail; glowing ones also carry a light (style from their sheet's colours, once per code).
func watch_missiles():
	var combat = main.combat
	if combat == null: return
	var marks: Dictionary = main.effects.missile_marks if main.get("effects") != null else {}
	for m in combat.missiles:
		if not m.alive: continue
		if not bool(marks.get(EffectsLayer.missile_key(m), true)): continue   # P-4: a missile the original does not draw
		var steps: int = m.steps
		var index: int = mini(int(m.index), steps - 1)
		if index < 0: continue
		var r: Array = m.records[index]
		var at := Vector2(int(r[2]), int(r[3]))
		var style: Array = style_of(String(m.get("art", m.id)))
		if style[0]:
			emit(add_parts, at, Vector2(randf_range(-6, 6), randf_range(-6, 6)), 380.0, 6.0, 2.0, Color(style[1].r, style[1].g, style[1].b, 0.6))
			emit(add_parts, at, Vector2.ZERO, 40.0, 18.0, 18.0, Color(style[1].r, style[1].g, style[1].b, 0.35))
		elif randf() < 0.6 * LEVEL_SCALE[level]:
			emit(smoke_parts, at, Vector2.ZERO, 260.0, 2.0, 1.0, Color(0.95, 0.93, 0.88, 0.35))

func style_of(code: String) -> Array:
	if missile_style.has(code): return missile_style[code]
	var style := [false, Color.WHITE]
	var sheet: Dictionary = preload("res://visuals/effects_layer.gd").sheet(code)
	if not sheet.is_empty():
		var image: Image = preload("res://core/art_data.gd").texture(sheet.texture).get_image()
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for y in range(0, image.get_height(), 2):
			for x in range(0, image.get_width(), 2):
				var c := image.get_pixel(x, y)
				if c.a < 0.5: continue
				sum += c
				n += 1
		if n > 0:
			var avg := Color(sum.r / n, sum.g / n, sum.b / n)
			var sat: float = maxf(avg.r, maxf(avg.g, avg.b)) - minf(avg.r, minf(avg.g, avg.b))
			style = [avg.v > 0.45 and sat > 0.2, Color.from_hsv(avg.h, minf(1.0, avg.s * 1.2), 1.0)]
	missile_style[code] = style
	return style

func restore_corpses():
	for id in faded:
		if is_instance_valid(faded[id]): faded[id].self_modulate.a = 1.0
	faded.clear()

# ------------------------------------------------------------------------------------------------ drawing
## P-4: the modern particles must not show what the original hides in the fog: a particle over a cell that is not lit for
## the local player (fog_view.gd, the drawing copy) is not painted.
func lit(at: Vector2) -> bool:
	if main == null or main.get("effects") == null: return true
	return main.effects.cell_lit(Vector2i(floori(at.x / 32.0), floori(at.y / 24.0)))

func paint_particles(layer: CanvasItem, list: Array):
	for p in list:
		if not lit(p[0]): continue
		var t: float = (clock - float(p[2])) / float(p[3])
		var size: float = lerpf(float(p[4]), float(p[5]), t)
		var c: Color = p[6]
		var fade := (1.0 - t) * minf(1.0, t * 6.0 + 0.4)
		layer.draw_texture_rect(soft_dot, Rect2(p[0] - Vector2(size, size), Vector2(size, size) * 2.0), false, Color(c.r, c.g, c.b, c.a * fade))

func paint_add(layer: CanvasItem):
	paint_particles(layer, add_parts)

func paint_smoke(layer: CanvasItem):
	paint_particles(layer, smoke_parts)

func paint_decals(layer: CanvasItem):
	for d in decals:
		var t: float = (clock - float(d[1])) / SCORCH_MS
		var r: float = d[2]
		layer.draw_texture_rect(soft_dot, Rect2(d[0] - Vector2(r, r * 0.6), Vector2(r * 2, r * 1.2)), false, Color(0.08, 0.06, 0.05, 0.55 * (1.0 - t)))
