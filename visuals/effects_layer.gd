extends Node2D
## Missiles and effects with their original RL sheets (EFFECTS_RESEARCH.md sections 2-3). Presentation only: the flight
## itself is simulation/missiles.gd (driven by Combat); this layer draws what the original's draw methods draw.
## * Missile (vtable 0x5eafdc +0x14 = 0x53f6b0): the head at record [index] (row = the record's 16-way facing, column =
##   index % frames) and a trail of `trail` sprites at the previous records (columns frames + k); depth +0x34 =
##   0x53f640: the current record's cell row * 24 + 12.
## * Effect class (vtable 0x5eb038, init 0x53c870, step 0x53cc20, draw 0x53ca70, depth 0x53ca40): frame 0 from creation,
##   the next frame every interval (50 ms; 120 ms for EX01/EX02), looping or once (removed when the last frame is
##   reached or after frames * interval * 3); drawn with palette 0 when +0x149 is set; depth (cell row + 1) * 24.
## * Damage fires (0x52b180 -> 0x53bba0): fire i (EF0(1 + (fourcc + i) % 3)) at the building pixel + BUI +0x6a + 4 i,
##   cell row + BUI height - 1, lit when the hit points cross 3/4, 1/2, 1/4 of the maximum (not under construction).
## * Destruction (building sprite +0x28 = 0x53b960): EX01 at the building (cell row + 1) and EX02 at the three fire
##   points (cell row + height + 2), the EX02 start staggered 0 / 300 / 600 ms by the global counter 0xafd508.
## * Lair spawns (0x4a7200 -> 0x44ead0): EZ08 once at the new unit's cell; the lair boss carries EZ55 (0x4a49e0, loop).
## * Conversion (parity pass 3, 0x4a6cc0, Read): every converted building within the view + 4 cells gets EZ01 once at its
##   pixel position (+0x4c / +0x4e), depth cell row + 6 (0x535150(x, y + 6)), drawn with palette 0 (+0x149 = 1). EZ01 is
##   in Effects1.xcr (milestone 12 had missed it). The view test is not ported (off-screen flashes are simply not seen).
## * P-4 (EFFECTS_RESEARCH.md "P-4", fog_view.gd, Read): under fog an effect is drawn only while its sprite cell is lit
##   (0x53ca70: fog on and +0x76 clear -> nothing); a missile only once its cell was lit or when it was marked at creation
##   (+0x131: a local shooter or target, no shooter, the launch or target cell visible; the draw 0x53f6b0 keeps it);
##   particle bursts the same way (particle_bursts.gd lit_test). Everything stays under the fog overlay (z 4000).
## * P-1 (EFFECTS_RESEARCH.md "P-1"): the smoke bursts over a destroyed ordinary building (particle_bursts.gd), the
##   death remains EDTH / EDT1 / EDT2 a removed corpse leaves (0x5468e0), the floating texts (floating_text.gd).
const ArtData = preload("res://core/art_data.gd")
const ParticleBursts = preload("res://visuals/particle_bursts.gd")
const FloatingText = preload("res://hud/floating_text.gd")
const BuildingRubble = preload("res://battle/building_rubble.gd")
const FogView = preload("res://visuals/fog_view.gd")

const FIRE_FRACTIONS := [[3, 2], [1, 1], [1, 2]]     # max * 3 >> 2, max >> 1, max >> 2 (0x52b180)

var main: Node
var effects: Array = []                  # {code, pixel, depth, start, next, frame, once, end, node, follow, key}
var fire_state: Dictionary = {}          # building id -> {"hp", "fires": [effect or null] * 3, "info"}
var known: Dictionary = {}               # building id -> last seen geometry (for the destruction effects)
var missile_nodes: Array = []
var ex02_counter := 0                    # 0xafd508: (counter + 1) % 3 per EX02
var bound: Dictionary = {}
var burning: Dictionary = {}             # building id -> cell (for the fire sound, audio_manager.gd)
var bursts = ParticleBursts.new()        # P-1: 0x58c0d0 bursts (building smoke, the fizzle)
var texts = FloatingText.new()           # P-1: 0x53a010 floating texts
var death_codes: Dictionary = {}         # unit id -> its remains effect (unit +0x14c, set at creation)
var remains_done: Dictionary = {}        # unit id -> true once its removal was handled
var death_cycle := 0                     # 0xafd4f0: (counter + 1) % 3 per ARM +0xf4 == 1 unit
var diseased: Dictionary = {}            # fighter id -> true while its disease art was shown

## The two sub-layers are made with the layer; one that never entered the tree (a test) is freed with it.
func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		for node in [bursts, texts]:
			if is_instance_valid(node) and node.get_parent() == null: node.free()

class Sprite extends Node2D:
	var tex: Texture2D
	var rects: Array = []                # [[source Rect2, destination position]]
	func _draw():
		for r in rects: draw_texture_rect_region(tex, Rect2(r[1], r[0].size), r[0])

func _ready():
	z_as_relative = true
	add_child(bursts)
	add_child(texts)
	bursts.view_test = func(cell: Vector2i) -> bool: return in_view(cell, 4)   # P-3: 0x53cc20's view + 4 cells
	bursts.lit_test = func(cell: Vector2i) -> bool: return cell_lit(cell)      # P-4: a sprite's +0x76

## P-4: 0x47f560 for the local player with the drawing copy (fog_view.gd); no scene or no visibility: lit.
func cell_lit(cell: Vector2i) -> bool:
	if main == null or main.get("visibility") == null: return true
	return FogView.lit(main.visibility, int(main.local_player), cell)

## P-4: 0x53ca70's test for a kind 6 effect at its sprite cell (only fog hides it).
func effect_visible(e: Dictionary) -> bool:
	if main == null or main.get("visibility") == null: return true
	return FogView.effect_shown(main.visibility, int(main.local_player), FogView.sprite_cell(e.pixel, int(e.get("row", int(e.depth) / 24 - 1))))

func now() -> int:
	return int(main.combat.now_ms) if main != null and main.combat != null else 0

static func fourcc(code: String) -> int:
	var b := code.to_ascii_buffer()
	return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24) if b.size() >= 4 else 0

static func sheet(code: String) -> Dictionary:
	return ArtData.data().get("effects", {}).get(code, {})

func frame_rect(s: Dictionary, row: int, column: int) -> Rect2:
	var size: Array = s.frame_size
	return Rect2(column * int(size[0]), row * int(size[1]), int(size[0]), int(size[1]))

# --------------------------------------------------------------------------------------------- effects
## B1-6a: `until` > 0 loops the effect until that time (a spell status's art, 0x44e8f0 linked to the status entry by
## 0x577320); sheets with "godot_blend": "add" (blend mode 0x10, EPF0 / EPF1: 0x48f130 adds the colour) draw additively.
func spawn_effect(code: String, pixel: Vector2i, cell_row: int, once: bool, start_delay: int = 0, follow = null, until: int = 0) -> Dictionary:
	# P-3: 0x44ead0 / 0x44e8f0 look the code up in 0x40ebd0 first: an emitter code becomes its host effect (EDUM, not
	# drawn, or a sheet such as EZ21) that bursts particles (particle_bursts.gd emit_at).
	if ParticleBursts.EMITTERS.has(code):
		var host := String(ParticleBursts.EMITTER_HOSTS.get(code, "EDUM"))
		var hs := sheet(host)
		var frames := int(hs.get("frames", ParticleBursts.DUMMY_FRAMES)) if host != "EDUM" else ParticleBursts.DUMMY_FRAMES
		var interval := int(hs.get("interval_ms", 50)) if host != "EDUM" else ParticleBursts.DUMMY_INTERVAL_MS
		if host != "EDUM" and not hs.is_empty(): spawn_effect(host, pixel, cell_row, once, start_delay, follow, until)
		return bursts.emit_at(code, pixel, cell_row, now() + start_delay, once, until, follow, frames, interval)
	var s := sheet(code)
	if s.is_empty(): return {}
	var t := now()
	var interval := int(s.get("interval_ms", 50))
	var e := {"code": code, "pixel": pixel, "depth": (cell_row + 1) * 24, "row": cell_row, "frame": 0, "next": t + interval + start_delay, "interval": interval,
		"once": once, "end": t + int(s.frames) * interval * 3, "frames": int(s.frames), "follow": follow, "alive": true, "until": until}
	var node := Sprite.new()
	node.tex = ArtData.texture(s.texture)
	if String(s.get("godot_blend", "")) == "add": node.material = additive_material()
	add_child(node)
	e["node"] = node
	effects.append(e)
	_draw_effect(e)
	return e

static var _additive: CanvasItemMaterial
static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive

func remove_effect(e: Dictionary):
	if e.is_empty() or not e.alive: return
	e.alive = false
	if is_instance_valid(e.node): e.node.queue_free()

func _step_effects():
	var t := now()
	var keep: Array = []
	for e in effects:
		if not e.alive: continue
		if e.follow != null:
			var u = e.follow
			if not is_instance_valid(u) or u.dying or u.removed:
				remove_effect(e)
				continue
			e.pixel = Vector2i(int(u.position.x), int(u.position.y))
			e.depth = (u.cell.y + 1) * 24
			e.row = u.cell.y
		if int(e.get("until", 0)) > 0 and t > int(e.until):
			remove_effect(e)
			continue
		if e.frames > 1 and t > int(e.next):           # 0x53cc20: the next frame after the interval
			e.next = t + int(e.interval)
			if e.once:
				e.frame = int(e.frame) + 1
				if int(e.frame) == int(e.frames) or t > int(e.end):
					remove_effect(e)
					continue
			else:
				e.frame = (int(e.frame) + 1) % int(e.frames)
		elif e.once and e.frames <= 1 and t > int(e.end):
			remove_effect(e)
			continue
		_draw_effect(e)
		keep.append(e)
	effects = keep

func _draw_effect(e: Dictionary):
	var s := sheet(e.code)
	var node: Sprite = e.node
	node.visible = effect_visible(e)                 # P-4: 0x53ca70 under fog
	node.z_index = preload("res://core/map_data.gd").depth(e.depth)
	node.rects = [[frame_rect(s, 0, int(e.frame)), Vector2(e.pixel) - Vector2(int(s.pivot[0]), int(s.pivot[1]))]]
	node.queue_redraw()

# --------------------------------------------------------------------------------------------- missiles
func _sync_missiles():
	var list: Array = main.combat.missiles if main.combat != null else []
	while missile_nodes.size() < list.size():
		var node := Sprite.new()
		add_child(node)
		missile_nodes.append(node)
	var marks := {}
	for i in missile_nodes.size():
		var node: Sprite = missile_nodes[i]
		node.visible = i < list.size()
		if not node.visible: continue
		var m: Dictionary = list[i]
		# P-4: drawn once marked (+0x131) or while its cell is lit; marked from then on (0x53f6b0 sets +0x131 when it draws).
		var key := missile_key(m)
		var marked: bool = bool(missile_marks[key]) if missile_marks.has(key) else missile_marked_at_creation(m)
		if not marked and cell_lit(missile_cell(m)): marked = true
		marks[key] = marked
		if not marked:
			node.visible = false
			continue
		# B1-6b: a spell missile draws its art (+0x13c); 0x40f620 may change its id. P-2: a meteor's +0x13c is EMTF, which
		# 0x40f620 turns into the sheet EMF0 (its id): 0x53f6b0 draws ANI +0x84, the EMF0 sheet, head and trail.
		var s := sheet(String(m.id) if bool(m.get("meteor", false)) else String(m.get("art", m.id)))
		if bool(m.get("meteor", false)): _meteor_step(m)
		if s.is_empty():
			node.visible = false
			continue
		node.tex = ArtData.texture(s.texture)
		node.material = additive_material() if String(s.get("godot_blend", "")) == "add" else null   # B1-6a: blend mode 0x10
		var pivot := Vector2(int(s.pivot[0]), int(s.pivot[1]))
		var records: Array = m.records
		var index: int = m.index
		var steps: int = m.steps
		var frames: int = maxi(1, int(m.frames))
		var rects: Array = []
		if index < steps:                                # 0x53f6b0: the head first, then the trail k = 0 .. trail - 1
			var head: Array = records[index]
			rects.append([frame_rect(s, int(head[6]) % int(s.rows), index % frames if frames > 1 else 0), Vector2(int(head[2]), int(head[3])) - pivot])
		for k in int(m.trail):
			var idx := index - 1 - k
			if idx >= 0 and idx < steps:
				var r: Array = records[idx]
				rects.append([frame_rect(s, int(r[6]) % int(s.rows), mini(frames + k, int(s.columns) - 1)), Vector2(int(r[2]), int(r[3])) - pivot])
		node.rects = rects
		var depth_record: Array = records[mini(index, records.size() - 1)]
		node.z_index = preload("res://core/map_data.gd").depth(int(depth_record[1]) * 24 + 12)                                     # 0x53f640
		node.queue_redraw()
	missile_marks = marks

## P-4: missiles keep their +0x131 mark here (the simulation's missile dictionaries are not written), keyed by what makes
## a missile distinct.
var missile_marks: Dictionary = {}
static func missile_key(m: Dictionary) -> String:
	var first: Array = m.records[0] if not m.get("records", []).is_empty() else [0, 0, 0, 0]
	return "%d:%s:%s:%s:%d:%d:%d:%d" % [int(m.get("launch_ms", 0)), str(m.get("from", Vector2i.ZERO)), str(m.get("aim", Vector2i.ZERO)),
		String(m.get("id", "")), int(m.get("attacker", -1)), int(m.get("target_id", -1)), int(first[2]), int(first[3])]

## The missile's sprite cell (+0x48 / +0x4a): its current record's cell.
static func missile_cell(m: Dictionary) -> Vector2i:
	var records: Array = m.get("records", [])
	if records.is_empty(): return Vector2i(-1, -1)
	var r: Array = records[clampi(int(m.get("index", 0)), 0, records.size() - 1)]
	return Vector2i(int(r[0]), int(r[1]))

## 0x53df60 / 0x53e960 + 0x541b80 (Read): the mark a new missile gets. A sky missile (the meteors, 0x58bea0 with +0x85a
## = 1: no shooter) always; a shot whose shooter or target belongs to the local player; with fog or shroud on, one whose
## launch cell (+0x144) or target cell (+0x140) is visible (0x47f560, the drawing copy).
func missile_marked_at_creation(m: Dictionary) -> bool:
	if main == null or main.get("visibility") == null: return true
	if bool(m.get("meteor", false)) or String(m.get("attacker_kind", "")) == "none": return true
	var local := int(main.local_player)
	if int(m.get("owner", -1)) == local: return true
	if target_owner(m) == local: return true
	var vis = main.visibility
	if not vis.fog and not vis.shroud: return true
	var from = m.get("from")
	var aim = m.get("aim")
	return (from is Vector2i and cell_lit(from)) or (aim is Vector2i and cell_lit(aim))

func target_owner(m: Dictionary) -> int:
	var id := int(m.get("target_id", -1))
	match String(m.get("target_kind", "")):
		"unit":
			var f = main.combat.fighters.get(id) if main.combat != null else null
			return int(f.owner) if f != null else -1
		"building":
			var b = main.production.building(id) if main.production != null else null
			return int(b.owner) if b != null else -1
	return -1

# --------------------------------------------------------------------------------------------- buildings
func _building_info(b) -> Dictionary:
	var raw: PackedByteArray = String(b.definition.get("raw_hex", "")).hex_decode()
	var cell := Vector2i(int(b.position.x) / 32, int(b.position.y) / 24)
	var offsets: Array = []
	for i in 3:
		offsets.append(Vector2i(_i16(raw, 0x6a + 4 * i), _i16(raw, 0x6c + 4 * i)) if raw.size() >= 0x78 else Vector2i.ZERO)
	return {"cell": cell, "pixel": Vector2i(cell.x * 32 + 16, cell.y * 24 + 12), "height": int(raw[63]) if raw.size() > 63 else 1,
		"offsets": offsets, "code": String(b.original_type_id), "max": int(b.max_hit_points), "raw": raw}

static func _i16(raw: PackedByteArray, o: int) -> int:
	var v := raw[o] | (raw[o + 1] << 8)
	return v - 0x10000 if v & 0x8000 else v

func _sync_buildings():
	var production = main.production
	if production == null: return
	var seen := {}
	for id in production.buildings:
		var b = production.buildings[id]
		seen[id] = true
		var info := _building_info(b)
		known[id] = info
		var state: Dictionary = fire_state.get(id, {"hp": int(b.hit_points), "fires": [{}, {}, {}]})
		fire_state[id] = state
		var hp := int(b.hit_points)
		var previous := int(state.hp)
		var max_hp := int(b.max_hit_points)
		for i in 3:
			var threshold: int = (max_hp * 3 >> 2) if i == 0 else (max_hp >> (i))
			var fire: Dictionary = state.fires[i]
			if fire.is_empty() and hp > 0 and threshold < previous and hp <= threshold and not b.constructing:
				if String(info.code) != "BAGR":
					var code := "EF0%d" % (1 + (fourcc(String(info.code)) + i) % 3)
					state.fires[i] = spawn_effect(code, info.pixel + info.offsets[i], info.cell.y + int(info.height) - 1, false)
			elif not fire.is_empty() and hp > threshold:        # healing puts the fire out (0x52e0b0, reverse order)
				remove_effect(fire)
				state.fires[i] = {}
		state.hp = hp
		if hp <= 0 and previous > 0: _destroyed(id)
		if not state.fires[0].is_empty() and hp > 0: burning[id] = info.cell
		else: burning.erase(id)
	for id in fire_state.keys():
		if not seen.has(id):
			if int(fire_state[id].hp) > 0: _destroyed(id)
			for fire in fire_state[id].fires: remove_effect(fire)
			fire_state.erase(id)
			burning.erase(id)

## 0x53b960: the building's fires go out (0x53bf10), EX01 at the building, EX02 at the three fire points.
func _destroyed(id: int):
	var info: Dictionary = known.get(id, {})
	if info.is_empty(): return
	if fire_state.has(id):
		for fire in fire_state[id].fires: remove_effect(fire)
		fire_state[id].fires = [{}, {}, {}]
		fire_state[id].hp = 0
	burning.erase(id)
	if String(info.code) == "BAGR": return
	spawn_effect("EX01", info.pixel, info.cell.y + 1, true)
	for i in 3:
		var delay := ex02_counter * 300
		ex02_counter = (ex02_counter + 1) % 3
		spawn_effect("EX02", info.pixel + info.offsets[i], info.cell.y + int(info.height) + 2, true, delay)
	# 0x52b3e0 (P-1): an ordinary building (0x52f980; not a treasure tower) is removed and leaves ESMR smoke emitters.
	if not BuildingRubble.leaves_rubble(String(info.code)):
		var raw: PackedByteArray = info.get("raw", PackedByteArray())
		var w: int = raw[62] if raw.size() > 63 else 1
		var h: int = raw[63] if raw.size() > 63 else 1
		bursts.destruction_smoke(info.cell, w, h, now())

# --------------------------------------------------------------------------------------------- spawns
func _on_spawned(info: Dictionary):
	var id := int(info.get("unit", -1))
	if main == null or id < 0 or id >= main.units.size(): return
	var u = main.units[id]
	spawn_effect("EZ08", Vector2i(u.cell.x * 32 + 16, u.cell.y * 24 + 12), u.cell.y, true)
	if bool(info.get("boss", false)):
		spawn_effect("EZ55", Vector2i(int(u.position.x), int(u.position.y)), u.cell.y, false, 0, u)

func _on_converted(building_id: int, _previous_owner: int):
	if main == null or main.production == null: return
	var b = main.production.building(building_id)
	if b == null: return
	var info := _building_info(b)
	spawn_effect("EZ01", info.pixel, int(info.cell.y) + 6, true)

func sync(scene: Node):
	main = scene
	if main == null: return
	if main.encounters != null and not bound.has(main.encounters.get_instance_id()):
		bound[main.encounters.get_instance_id()] = true
		main.encounters.spawned.connect(_on_spawned)
	if main.production != null and not bound.has(main.production.get_instance_id()):
		bound[main.production.get_instance_id()] = true
		main.production.building_converted.connect(_on_converted)
	if main.production != null and not bound.has(-main.production.get_instance_id()):
		bound[-main.production.get_instance_id()] = true
		main.production.building_completed.connect(_on_completed)
	if main.combat != null and not bound.has(main.combat.get_instance_id()):
		bound[main.combat.get_instance_id()] = true
		main.combat.missile_landed.connect(_on_missile_landed)   # P-2: a meteor that struck an object on its last record
	var spells = main.combat.get("spells") if main.combat != null else null
	if spells != null and not bound.has(spells.get_instance_id()):
		bound[spells.get_instance_id()] = true
		spells.cast_done.connect(_on_cast_done)
		spells.notice.connect(_on_spell_notice)
		if spells.has_signal("floated"): spells.floated.connect(_on_floated)
	_sync_missiles()
	_sync_buildings()
	_sync_remains()
	_sync_disease()
	_step_effects()
	bursts.step(now())
	texts.step(now())

# --------------------------------------------------------------------------------------------- P-1: death remains
## The remains code of a unit type (unit creation, wbc3_decomp.c 209800, Read): ARM +0xf4 == 1 cycles EDT1, EDT2, EDTH
## by the global counter 0xafd4f0; 2..5 give EDTH; anything else none.
func remains_code(type_id: String) -> String:
	var units: Dictionary = main.catalogue_data.get("units", {}) if main != null and main.get("catalogue_data") is Dictionary else {}
	var raw: PackedByteArray = String(units.get(type_id, {}).get("raw_hex", "")).hex_decode()
	var kind := raw.decode_s16(0xf4) if raw.size() >= 0xf6 else 0
	if kind == 1:
		death_cycle = (death_cycle + 1) % 3
		return ["EDTH", "EDT1", "EDT2"][death_cycle]
	return "EDTH" if kind >= 2 and kind <= 5 else ""

## 0x5468e0 (Read, wbc3_decomp.c 216430): when a unit's object leaves the world (its corpse hold ended) and its remains
## code is set, the effect starts once at the unit pixel, cell row - 2 (at least 0), 10 s per frame (0x53c870).
## Corpses consumed early (Call the Dead, the Zombie) leave none (the original clears +0x14c for them).
func _sync_remains():
	if main.combat == null: return
	for u in main.units:
		var id: int = u.unit_id
		if not death_codes.has(id): death_codes[id] = remains_code(String(u.type_id))
		if not u.removed or remains_done.has(id): continue
		remains_done[id] = true
		var f = main.combat.fighters.get(id)
		if f == null or int(f.get("death_ms", -1)) < 0 or String(death_codes[id]) == "": continue
		if int(main.combat.now_ms) - int(f.death_ms) < int(main.combat.corpse_ms(String(u.type_id))): continue
		spawn_effect(String(death_codes[id]), Vector2i(int(u.position.x), int(u.position.y)), maxi(0, u.cell.y - 2), true)

## 0x51c060(1) (Read, wbc3_decomp.c 192493): a unit taking the disease gets EZ52 once (0x44e8f0, on the unit, only in
## view) and Disease.wav (P-2).
var disease_sound_ms := 0                # 0xafd474

func _sync_disease():
	for id in main.combat.fighters:
		var f = main.combat.fighters[id]
		var sick := bool(f.get("diseased", false))
		if sick and not diseased.has(id):
			diseased[id] = true
			# P-2 (decompile 192485-192493): Disease.wav goes with the art at most once a second (timeGetTime + 1000, the
			# stamp 0xafd474 is taken whether or not the art is shown), positional (0x44e8f0 -> 0x50f0a0).
			var sound := ""
			var real := Time.get_ticks_msec()
			if disease_sound_ms == 0 or disease_sound_ms < real:
				disease_sound_ms = real + 1000
				sound = "Disease.wav"
			var u = main.unit_by_id(int(id))
			if u != null and u.visible and in_view(u.cell):
				spawn_effect("EZ52", Vector2i(int(u.position.x), int(u.position.y)), u.cell.y, true, 0, u)
				if sound != "": _sound(sound, u.cell)
		elif not sick: diseased.erase(id)

# --------------------------------------------------------------------------------------------- P-1: floating texts
func in_view(cell: Vector2i, margin: int = 0) -> bool:
	if main == null or not main.has_method("view_top_left") or main.get("camera") == null: return true
	var top: Vector2 = main.view_top_left() - Vector2(margin * 32, margin * 24)
	var size: Vector2 = main.view_world_size() + Vector2(margin * 64, margin * 48)
	var p := Vector2(cell.x * 32, cell.y * 24)
	return p.x >= top.x - 31 and p.y >= top.y - 23 and p.x < top.x + size.x and p.y < top.y + size.y

func friendly(owner: int) -> bool:
	var local := int(main.local_player)
	if owner == local: return true
	return main.combat != null and main.combat.has_method("allied") and main.combat.allied(owner, local)

## 0x53a010 over a unit: `colour` 1 good, 2 bad, 3 magic, 4 level.
func float_over_unit(u, text: String, colour: int, duration: int = 1000) -> Dictionary:
	if u == null or not u.visible or u.removed: return {}
	return texts.show_text("u%d" % int(u.unit_id), text, colour, duration, u.position, friendly(int(u.owner_id)), now(), in_view(u.cell))

## 0x5777a0 (Read): every cast at level >= 1 by a unit floats "Spell Cast (Level %d)" (Game.txt [1111], colour 3).
func _on_cast_done(info: Dictionary):
	# P-2: 0x526700 (decompile 198918-198933) floats Game.txt [0x461] "Healing %d" with the value asked for less the old hit
	# points (before the cap), colour 1, 1000 ms, over every unit a heal record sets.
	var result = info.get("result")
	if result is Dictionary:
		for h in result.get("healed", []):
			if String(h.get("kind", "")) != "unit" or not h.has("from"): continue
			var gain := int(h.hp) - int(h.from)
			if gain != 0: float_over_unit(main.unit_by_id(int(h.id)), format_line(0x461, "Healing %d", gain), 1, 1000)
		_present_p3(info.get("record", {}), result)
	var caster = info.get("caster")
	if not (caster is Dictionary) or int(info.get("level", 0)) < 1 or not caster.has("id"): return
	if typeof(info.get("spell")) != TYPE_INT: return
	float_over_unit(main.unit_by_id(int(caster.id)), "Spell Cast (Level %d)" % int(info.level), 3)

## 0x5777a0 (Read, 245752): a cast at level < 1 fizzles: the burst 0x58c0d0(12, EPA5, ...) at the caster's sprite and
## "Spell Failed" (Game.txt [1110], colour 2). spells.gd only says "The spell failed"; the caster is the hero whose
## cast timer started this instant.
func _on_spell_notice(text: String):
	if text != "The spell failed" or main.combat == null: return
	for f in main.combat.fighters.values():
		if not bool(f.get("hero", false)) or int(f.get("cooldown_start", -1)) != int(main.combat.now_ms): continue
		var u = main.unit_by_id(int(f.id))
		if u == null: continue
		bursts.burst(ParticleBursts.FIZZLE, Vector2i(int(u.position.x), int(u.position.y)), u.cell.y + 1, now())
		float_over_unit(u, "Spell Failed", 2)

## Game.txt line `line` (0x44f4a0) formatted with `value`, or `fallback`.
func format_line(line: int, fallback: String, value: int) -> String:
	var pattern := fallback
	if main != null and main.has_method("game_string"): pattern = String(main.game_string(line, fallback))
	if pattern.contains("%+d"): return pattern.replace("%+d", ("+%d" % value) if value >= 0 else str(value))
	return pattern % value if pattern.contains("%d") else pattern

const FLOAT_FALLBACKS := {0x47e: "Recovering from spellcasting", 0x459: "Critical: Ignore Armor", 0x45a: "Critical: Cleave",
	0x45b: "Critical: Stun", 0x45c: "Critical: Freeze", 0x45e: "Critical: Mana Drain", 0x360: "%d XP Drained", 0x35f: "Armor Reduced",
	0x47a: "Assassinate: +100 Gold", 0x47c: "Crystallize: +100 Crystal"}
var float_sound_ms := {}                 # G-4: the 1 s stamps of Assassination.wav (0xa391a0) and Crystallize.wav (0xafd490)
## P-2: spells.gd's `floated` (the mana potion 0x561c30; P-3: Recovering, the local hero only).
## G-4 (simulation/criticals.gd): optional "effects" [{code, on (unit id), once, depth, follow, until}], "bursts"
## [{burst, pixel, row}], "sound" with "sound_on" (unit id) or "sound_cell", "sound_view" (only when the cell is in view),
## "sound_cooldown" (one real second per key), "local_party" (only when the local player is one of the owners), and
## "text_view" (the text only when the unit is in view). "id" -1: no text.
func _on_floated(info: Dictionary):
	if bool(info.get("local_only", false)) and int(info.get("owner", -1)) != int(main.local_player): return
	var fallback := "Mana Potion %+d" if int(info.get("line", 0)) == 0x45f else String(FLOAT_FALLBACKS.get(int(info.get("line", 0)), "%d"))
	var over = main.unit_by_id(int(info.get("id", -1))) if int(info.get("id", -1)) >= 0 else null
	if over != null and (not bool(info.get("text_view", false)) or in_view(over.cell)):
		float_over_unit(over, format_line(int(info.get("line", 0)), fallback, int(info.get("value", 0))), int(info.get("colour", 1)), int(info.get("ms", 1000)))
	_float_extras(info)

func _float_extras(info: Dictionary):
	for e in info.get("effects", []):
		var u = main.unit_by_id(int(e.get("on", -1)))
		if u == null or not u.visible: continue
		var pixel := Vector2i(int(u.position.x), int(u.position.y))
		if bool(e.get("follow", false)): spawn_effect(String(e.code), pixel, u.cell.y + int(e.get("depth", 0)), false, 0, u, int(e.get("until", now())))
		else: spawn_effect(String(e.code), pixel, u.cell.y + int(e.get("depth", 0)), bool(e.get("once", true)))
	for b in info.get("bursts", []): bursts.burst(b.burst, b.pixel, int(b.row), now())
	var sound := String(info.get("sound", ""))
	if sound == "": return
	var cell = info.get("sound_cell")
	if info.has("sound_on"):
		var su = main.unit_by_id(int(info.sound_on))
		cell = su.cell if su != null else null
	if not (cell is Vector2i): return
	if bool(info.get("sound_view", false)) and not in_view(cell): return
	if info.has("local_party") and not Array(info.local_party).has(int(main.local_player)): return
	var key := String(info.get("sound_cooldown", ""))
	if key != "":
		var real := Time.get_ticks_msec()
		if int(float_sound_ms.get(key, 0)) != 0 and int(float_sound_ms[key]) + 1000 >= real: return
		float_sound_ms[key] = real
	_sound(sound, cell)

## 0x52bfd0 (Read): an own building completed pings the strategic map (no alert list entry).
func _on_completed(id: int):
	var b = main.production.building(id) if main.production != null else null
	if b == null or int(b.owner) != int(main.local_player) or not main.has_method("strategic_alert"): return
	main.strategic_alert(Vector2i(int(b.position.x) / 32, int(b.position.y) / 24), false)

# --------------------------------------------------------------------------------------------- P-2: meteors, blasts
## Couatl's Wrath (EFFECTS_RESEARCH.md "P-2" item 4, Read):
## * the cast (0x4ac0e0 case 0x23, decompile 116672): STEZ47.wav and STEZ27.wav at the temple's cell (0x50f0a0), once per
##   cast, before the meteors;
## * the flight: 0x40f620('EMTF') gives +0x835 = 1 and the block +0x836 (count 15, EPA1, groups (2, 2), row 1, pattern 2,
##   frame mode 10, alpha mode 2, no respawn, size 3, period 1000 steps, offsets 0, depth row + 1, no light); the step
##   0x53fbc0 (0x53fc10..0x53fd57) counts +0x858 from 1000, so one burst at the first step at the missile's pixel, only
##   when its cell is within the view + 4;
## * the last record (0x540b10..0x540beb, +0x13c == EMTF): EZ06 once at the cell (0x44ead0, only in view), STEZ47.wav
##   (0x50f0a0), a light (0x44edb0: the Lighting Effects option's light object, not ported) and the burst (5, EPA1,
##   groups (1, 8), row 0, pattern 1, frame mode 4, alpha mode 1) at the cell's centre, depth the cell row.
## The Firebomb / Spore blast (0x529a40 with param 3 = 0, decompile 200985): two bursts at the dead unit's sprite,
## (8, EPA1, (1, 1), row 1, pattern 1, frame mode 4, alpha 1, size 1) and (6, EPA6, (1, 1), row 3, pattern 0, frame mode
## 1, alpha 2, size 1).
const METEOR_TRAIL := [15, 2, 2, 2, 1, 2, 10, 2, 0, 3]
const METEOR_LANDING := [5, 2, 1, 8, 0, 1, 4, 1, 0, 0]
const BLAST_BURSTS := [[8, 2, 1, 1, 1, 1, 4, 1, 0, 1], [6, 0x40, 1, 1, 3, 0, 1, 2, 0, 1]]
var meteors_seen: Dictionary = {}        # meteor key -> "trail" once its first-step burst ran
var _cast_sound_key := ""

static func meteor_key(m: Dictionary) -> String:
	return "%d:%s:%s" % [int(m.get("launch_ms", 0)), str(m.get("from", Vector2i.ZERO)), str(m.get("aim", Vector2i.ZERO))]

func _sound(name: String, cell: Vector2i):
	if main != null and main.has_method("play_at"): main.play_at(name, cell)

## Called for each meteor the missile list holds (the cast sounds on the first sight of a volley, the first-step burst).
func _meteor_step(m: Dictionary):
	var key := meteor_key(m)
	var volley := "%d:%s" % [int(m.get("launch_ms", 0)), str(m.get("from", Vector2i.ZERO))]
	if volley != _cast_sound_key:
		_cast_sound_key = volley
		_sound("STEZ47.wav", m.from)
		_sound("STEZ27.wav", m.from)
	if meteors_seen.has(key) or int(m.index) < 1: return
	# P-4 (Read, 0x53fc10..0x53fc3e): the counter +0x858 only runs while the missile's +0x76 is set, so the one burst comes
	# at the first step on which its cell is lit (the first step when nothing hides it), at its pixel then.
	var r: Array = m.records[clampi(int(m.index) - 1, 0, m.records.size() - 1)]
	var cell := Vector2i(int(r[0]), int(r[1]))
	if not cell_lit(cell): return
	meteors_seen[key] = "trail"
	if in_view(cell): bursts.burst(METEOR_TRAIL, Vector2i(int(r[2]), int(r[3])), cell.y + 1, now())

## The meteor's last record (combat.gd race_event "meteor_blast", or a meteor that struck an object there).
func meteor_landing(cell: Vector2i):
	var pixel := Vector2i(cell.x * 32 + 16, cell.y * 24 + 12)
	if in_view(cell): spawn_effect("EZ06", pixel, cell.y, true)
	_sound("STEZ47.wav", cell)
	bursts.burst(METEOR_LANDING, pixel, cell.y, now())

## The Firebomb / Spore death blast (combat.gd race_event "blast").
func blast(cell: Vector2i):
	var pixel := Vector2i(cell.x * 32 + 16, cell.y * 24 + 12)
	for p in BLAST_BURSTS: bursts.burst(p, pixel, cell.y, now())

func _on_missile_landed(info: Dictionary):
	if bool(info.get("meteor", false)) and bool(info.get("hit", false)): meteor_landing(info.get("aim", Vector2i.ZERO))

# --------------------------------------------------------------------------------------------- P-3: record consequences
## EFFECTS_RESEARCH.md "P-3" (Read):
## * Spell Resisted: 0x4aa840 sends message 0x222 at its four refusals (Mutate, the strip of Transform, a disease the
##   target refuses, Banish), the result's "resisted" ids; 0x4afa00 -> 0x539fb0 floats Game.txt [0x458] colour 4, 1000 ms.
## * Psychic Blast: message 0x221 per target -> 0x4a9b40 -> 0x527d10(amount): EZ10 looping on the unit while the stun
##   status lasts (0x44e8f0(unit, EZ10, 0, loop), linked by 0x577320), "Critical: Stun" ([0x45b], colour 0), EZ63 once
##   (0x44e8f0(unit, EZ63, 1, once, depth + 2)) and CrushCrit.wav when the unit's cell is inside the view (0x4ca050 with
##   the distance volume 0x50f020: Provisional, the rebuild's positional sound stands in).
const STUN_KIND := 0x28                  # SpellEffects.PSYCHIC_BLAST
func _present_p3(record, result: Dictionary):
	for id in result.get("resisted", []):
		float_over_unit(main.unit_by_id(int(id)), format_line(0x458, "Spell Resisted", 0), 4, 1000)
	if not (record is Dictionary) or int(record.get("kind", -1)) != STUN_KIND: return
	for s in result.get("statuses", []):
		var u = main.unit_by_id(int(s.get("id", -1)))
		if u == null or not u.visible: continue
		var pixel := Vector2i(int(u.position.x), int(u.position.y))
		spawn_effect("EZ10", pixel, u.cell.y, false, 0, u, int(s.get("status", {}).get("until", now())))
		float_over_unit(u, format_line(0x45b, "Critical: Stun", 0), 0, 1000)
		spawn_effect("EZ63", pixel, u.cell.y + 2, true)
		if in_view(u.cell): _sound("CrushCrit.wav", u.cell)

## P-3: Petrify (message 0x20e -> 0x4a9c90, Read): over the shooter (a unit) "Petrify: +100 Stone" ([0x47b], colour 1,
## 1000 ms) after the credit.
func petrify_text(shooter_id: int):
	float_over_unit(main.unit_by_id(shooter_id), format_line(0x47b, "Petrify: +100 Stone", 0), 1, 1000)

## Drops every effect (a new scene world replaces the old one).
func clear():
	for e in effects: remove_effect(e)
	effects.clear()
	fire_state.clear()
	known.clear()
	burning.clear()
	bursts.clear()
	texts.clear()
	death_codes.clear()
	remains_done.clear()
	diseased.clear()
	meteors_seen.clear()
	missile_marks.clear()
	_cast_sound_key = ""
