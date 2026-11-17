extends RefCounted
## Original sheets for units, buildings and their team colours (assets/art.json, tools/art_data.py, ART_RESEARCH.md).
## Presentation only: nothing here feeds the simulation.
const Assets = preload("res://core/asset_store.gd")

const SHADER = preload("res://visuals/team_colour.gdshader")
# ANI slots (suffix table 0x60e054): 0 idle, 1 walk, 2 f (attack), 3 d (death), 4 a, 5 z (building construction /
# rubble), 6 c, 7 s.
const SLOT_BY_SUFFIX := {"": 0, "w": 1, "f": 2, "d": 3, "a": 4, "z": 5, "c": 6, "s": 7}
const NEUTRAL := 6

static var _data: Dictionary = {}
static var _textures: Dictionary = {}
static var _materials: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty() and Assets.exists("art.json"):
		_data = Assets.json("art.json")
	return _data

static func texture(name: String) -> Texture2D:
	if not _textures.has(name): _textures[name] = Assets.texture(name)
	return _textures[name]

static func has_unit(type_id: String) -> bool:
	return data().get("units", {}).has(type_id)

## The sheet record of `type_id` for ANI slot `slot`, or {} when the unit has no such sheet (ANI slot off or no art).
static func unit_sheet(type_id: String, slot: int) -> Dictionary:
	return data().get("units", {}).get(type_id, {}).get("sheets", {}).get(str(slot), {})

static func unit(type_id: String) -> Dictionary:
	return data().get("units", {}).get(type_id, {})

static func building(code: String) -> Dictionary:
	return data().get("buildings", {}).get(code, {})

static func building_sheet(code: String, slot: int) -> Dictionary:
	return building(code).get("sheets", {}).get(str(slot), {})

## Owner of a placed map building on the chosen map (map.json BLDH +0x64; art.json keeps Desert Sands' copy).
static func map_owner(source_offset: int) -> int:
	return preload("res://core/map_data.gd").building_owner(source_offset)

## Colour index of a player: the slot record's colour word (0x708f9a + player * 0x2c), which the map choice 0x4e7760
## copies from the scenario's start record (Desert Sands: slot 0 colour 1 blue, slot 1 colour 0 red; Data) and every
## draw passes to 0x487f20. `colours` is set by main.start_skirmish for the active slots; any other player (the fixture
## harness, the neutral slot 6 = grey ramp 6, whose writer is still Open) keeps colour = player.
static var colours: Dictionary = {}
static func player_colour(player: int) -> int:
	return int(colours.get(player, clampi(player, 0, 7)))

## The 15-step ramp of colour `colour` built by 0x494450 (565 values expanded like the sheet palettes).
static func ramp(colour: int) -> PackedColorArray:
	var out := PackedColorArray()
	var ramps: Array = data().get("team", {}).get("ramps", [])
	if colour < 0 or colour >= ramps.size(): return out
	for c in ramps[colour]: out.append(Color8(int(c[0]), int(c[1]), int(c[2])))
	return out

## Canvas material that recolours palette entries 224..238 of `sheet` to the owner's ramp (0x487f20 copies the ramp over
## those entries). One material per (mask, colour); `colour` < 0 leaves the sheet's own green entries.
## P-2: `fog` draws the sheet with palette 6 (team_colour.gdshader palette6, the building under fog, 0x53b2b7).
static func team_material(sheet: Dictionary, colour: int, fog: bool = false) -> ShaderMaterial:
	if sheet.is_empty() or not sheet.has("team_mask"): return null
	var key := "%s#%d%s" % [sheet.team_mask, colour, "#fog" if fog else ""]
	if _materials.has(key): return _materials[key]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("fog_palette", fog)
	material.set_shader_parameter("team_mask", texture(sheet.team_mask))
	var colours := ramp(colour)
	material.set_shader_parameter("team_enabled", colours.size() == 15)
	if colours.size() == 15: material.set_shader_parameter("ramp", colours)
	material.set_shader_parameter("soft_shadows", soft_shadows)
	_materials[key] = material
	return material

## P-2: palette 6 of a sheet from its palette-0 colour (8-bit channels as imported, rle.c565): the shader's palette6.
static func palette6(c: Color) -> Color:
	var r5 := int(round(c.r * 31.0))
	var g6 := int(round(c.g * 63.0))
	var b5 := int(round(c.b * 31.0))
	var grey := (2 * r5 + g6 + 2 * b5) / 3
	var half := grey >> 1
	return Color8(half * 255 / 31, grey * 255 / 63, half * 255 / 31, int(round(c.a * 255.0)))

## Enhanced visuals (ENHANCED_VISUALS.md): the soft shadow pass of team_colour.gdshader for every cached material, and a
## shared material without team colour for map features (null while the pass is off: the original look).
static var soft_shadows := false
static var _plain: ShaderMaterial = null

static func set_soft_shadows(on: bool):
	soft_shadows = on
	for key in _materials: _materials[key].set_shader_parameter("soft_shadows", on)
	if _plain != null: _plain.set_shader_parameter("soft_shadows", on)

static func plain_material() -> ShaderMaterial:
	if not soft_shadows: return null
	if _plain == null:
		_plain = ShaderMaterial.new()
		_plain.shader = SHADER
		_plain.set_shader_parameter("soft_shadows", true)
	return _plain

static func frame_rect(sheet: Dictionary, row: int, column: int) -> Rect2:
	var size = sheet.frame_size
	return Rect2(column * size[0], row * size[1], size[0], size[1])

static func offset(sheet: Dictionary) -> Vector2:
	return Vector2(-sheet.pivot[0], -sheet.pivot[1])

## Walk entries per cell step (0x5377a0): ANI walk frames * ARM +0xf8 / +0xfa (orthogonal) or +0xfc / +0xfe (diagonal),
## truncated; 16 when that is below 1.
static func walk_entries(type_id: String, diagonal: bool) -> int:
	var sheet := unit_sheet(type_id, 1)
	var factors: Array = unit(type_id).get("step_factors_0xf8", [1, 1, 1, 1])
	if sheet.is_empty(): return 16
	var num: int = int(factors[2] if diagonal else factors[0])
	var den: int = maxi(1, int(factors[3] if diagonal else factors[1]))
	var n: int = int(sheet.frame_count) * num / den
	return n if n >= 1 else 16

## Icon of `code` (ANI slot 8 RL sheet, EFFECTS_RESEARCH.md section 4): column 0 portrait, 1/2 the 32 x 50 production
## icons, 3/4 the 90 x 90 portraits (4 under fog), 5 the small face. Null when the code has no imported icon.
static func icon(code: String, column: int = 1) -> AtlasTexture:
	var record: Dictionary = data().get("icons", {}).get(code, {})
	if record.is_empty(): return null
	var r: Array = record.regions.get(str(column), [])
	if r.size() != 4: return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture(record.texture)
	atlas.region = Rect2(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
	return atlas

## Hero item picture (BM_HERO_ITEMS, 0x5a64e0): column (stored icon column + 1) * 70, row slot type * 110, 70 x 110
## (70 x 70 for slot types 5, 6, 7, 9, 10). Which Items.xml fields hold the two values is Open.
static func item_icon(icon_column: int, slot_type: int) -> AtlasTexture:
	var record: Dictionary = data().get("ui_atlases", {}).get("items", {})
	if record.is_empty(): return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture(record.texture)
	var tall := 70 if slot_type in [5, 6, 7, 9, 10] else 110
	atlas.region = Rect2((icon_column + 1) * 70, slot_type * 110, 70, tall)
	return atlas

## A region of BM_SKILLICONS (SkillIcons.bmp, the in-game panel's small icons, e.g. 0x469ab0(0x141, x, y, w, h)).
static func skill_icon(region: Rect2i) -> AtlasTexture:
	var record: Dictionary = data().get("ui_atlases", {}).get("skillicons", {})
	if record.is_empty(): return null
	var atlas := AtlasTexture.new()
	atlas.atlas = texture(record.texture)
	atlas.region = Rect2(region)
	return atlas
