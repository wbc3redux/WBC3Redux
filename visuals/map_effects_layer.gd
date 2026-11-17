extends Node2D
## Map wave 5 (MAPS_RESEARCH.md "Wave 5"): draws the scenario's EFFH particle emitters (simulation/map_effects.gd).
## Draw 0x5459f0 (Read): each live particle is frame `frame` of the definition's sheet (EPF0 for every shipped definition:
## additive, art.json "godot_blend") at the emitter pixel plus (x, y), translucency `alpha` (0x486d70, 0..15 of 16) and
## the colour channels r / g / b on or off (0x486d90). One node per emitter, sorted by the emitter's cell row.
## P-4 (Read, fog_view.gd): a map emitter is a kind 11 sprite (0x545760); the view draw collects it only when its cell is
## lit (0x547c00 +0x76) or it was drawn before (+0x131, which its draw 0x5459f0 sets): hidden until first seen, then kept.
const Assets = preload("res://core/asset_store.gd")
const MapEffects = preload("res://simulation/map_effects.gd")
const ArtData = preload("res://core/art_data.gd")
const MapData = preload("res://core/map_data.gd")
const FogView = preload("res://visuals/fog_view.gd")

var effects                      # MapEffects
var nodes: Array = []            # one EmitterNode per emitter

class EmitterNode extends Node2D:
	var emitter
	var seen := false                # P-4: +0x131, set once the emitter's cell was lit
	var sheet: Dictionary
	var texture: Texture2D

	func _draw():
		if texture == null: return
		var size: Array = sheet.frame_size
		var pivot := Vector2(int(sheet.pivot[0]), int(sheet.pivot[1]))
		for i in emitter.used:
			var p: Array = emitter.particles[i]
			if p[MapEffects.ALIVE] == 0: continue
			var frame: int = clampi(p[MapEffects.FRAME], 0, int(sheet.frames) - 1)
			var source := Rect2(frame * int(size[0]), 0, int(size[0]), int(size[1]))
			var at := Vector2(emitter.pixel + Vector2i(p[MapEffects.X], p[MapEffects.Y])) - pivot
			var tint := Color(p[MapEffects.RED], p[MapEffects.GREEN], p[MapEffects.BLUE], 1.0 - clampi(p[MapEffects.ALPHA], 0, 16) / 16.0)
			draw_texture_rect_region(texture, Rect2(at, source.size), source, tint)

## A new match world: one emitter per EFFH record of the selected map, created at `clock` (the match clock, ms).
func reset(clock: int):
	for n in nodes: n.queue_free()
	nodes.clear()
	var definitions := {}
	if Assets.exists("particles.json"):
		definitions = Assets.json("particles.json").definitions
	effects = MapEffects.new(MapData.map().get("effects", []), definitions, clock)
	for em in effects.emitters:
		var node := EmitterNode.new()
		node.emitter = em
		node.sheet = ArtData.data().get("effects", {}).get(String(em.d.graphic), {})
		if not node.sheet.is_empty():
			node.texture = ArtData.texture(node.sheet.texture)
			if String(node.sheet.get("godot_blend", "")) == "add":
				var material := CanvasItemMaterial.new()
				material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				node.material = material
		node.z_index = MapData.depth((em.cell.y + 1) * 24)
		add_child(node)
		nodes.append(node)

func step(clock: int):
	if effects == null: return
	effects.tick(clock)
	var scene = get_parent()
	var visibility = scene.get("visibility") if scene != null else null
	var player := int(scene.get("local_player")) if scene != null and scene.get("local_player") != null else 0
	for n in nodes:
		if not effects.emitters.has(n.emitter):
			n.visible = false
		else:
			if not n.seen: n.seen = FogView.lit(visibility, player, n.emitter.cell)     # P-4: 0x547c00 / 0x5459f0
			n.visible = n.seen
			if n.seen: n.queue_redraw()
