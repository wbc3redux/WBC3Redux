extends Node
## Enhanced visuals weather (ENHANCED_VISUALS.md, round 3): a deliberate modern change, presentation only, off by default.
## Rain, snow, fog or a sandstorm drawn by weather.gdshader on its own canvas layer (above the colour grade, below the HUD).
## Nothing here reads the simulation or the terrain renderer: the view position, the zoom and the clock are all it needs,
## so it keeps working when the ground is drawn differently (per-tile maps). "Match Map" picks the weather from the map's
## name and terrain record names (for_map).

const LAYER := 3                          # above the grade (2), below the HUD (5)
const NONE := 0
const MATCH_MAP := 1
const RAIN := 2
const SNOW := 3
const FOG := 4
const SAND := 5
## Weather row value -> shader kind (0 none, 1 rain, 2 snow, 3 fog, 4 sandstorm).
const SHADER_KIND := {NONE: 0, RAIN: 1, SNOW: 2, FOG: 3, SAND: 4}
const STRENGTH := [0.0, 0.55, 1.0]        # Weather Strength: - / Light / Heavy
const NAMES := {NONE: "none", RAIN: "rain", SNOW: "snow", FOG: "fog", SAND: "sandstorm"}

var main: Node
var layer: CanvasLayer
var rect: ColorRect
var weather := NONE                       # the weather shown (never MATCH_MAP)

func _ready():
	layer = CanvasLayer.new()
	layer.layer = LAYER
	layer.visible = false
	add_child(layer)
	rect = ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = preload("res://visuals/weather.gdshader")
	rect.material = material
	layer.add_child(rect)

## The Weather row (NONE, MATCH_MAP or a weather) and the Weather Strength row (1 light, 2 heavy).
func set_weather(choice: int, level: int):
	weather = for_map(main.map if main != null and main.get("map") is Dictionary else {}) if choice == MATCH_MAP else choice
	if not SHADER_KIND.has(weather): weather = NONE
	layer.visible = weather != NONE
	var m: ShaderMaterial = rect.material
	m.set_shader_parameter("kind", SHADER_KIND[weather])
	m.set_shader_parameter("strength", STRENGTH[clampi(level, 1, 2)])

## "Match Map" (Provisional, a modern choice; the original has no weather): words in the scenario's name and in its
## terrain record names (map.json terrain_records, e.g. "Desert #1", "Plains #1") decide. Snow and ice -> snow; jungle,
## swamp, marsh -> rain; lava, caverns, volcanoes -> fog (a smoky haze); then by the ground most records name: desert or
## sand -> sandstorm, grass or plains with coast / water / river / lake records -> rain; anything else stays clear.
static func for_map(map: Dictionary) -> int:
	var words := String(map.get("source", "")).to_lower()
	var desert := 0
	var grass := 0
	var water := 0
	for r in map.get("terrain_records", []):
		var name := String(r.get("name", "")).to_lower()
		words += " " + name
		if name.contains("desert") or name.contains("sand"): desert += 1
		elif name.contains("plains") or name.contains("grass"): grass += 1
		if name.contains("coast") or name.contains("water") or name.contains("river") or name.contains("lake"): water += 1
	for w in ["snow", "winter", "ice", "frost"]:
		if words.contains(w): return SNOW
	for w in ["jungle", "swamp", "marsh"]:
		if words.contains(w): return RAIN
	for w in ["lava", "cavern", "volcan"]:
		if words.contains(w): return FOG
	if desert > 0 and desert >= grass: return SAND
	if grass > 0 and water > 0: return RAIN
	return NONE

## Called every frame while the enhanced visuals are on: the view and the clock.
func step(now: int, origin: Vector2, zoom: float):
	if not layer.visible or main == null: return
	var screen: Vector2 = get_viewport().get_visible_rect().size
	rect.size = screen
	var m: ShaderMaterial = rect.material
	m.set_shader_parameter("screen_px", screen)
	m.set_shader_parameter("view_px", main.view_screen_size())
	m.set_shader_parameter("view_left", main.view_screen_left() if main.has_method("view_screen_left") else 0.0)
	m.set_shader_parameter("view_origin", origin - Vector2(main.view_screen_left() if main.has_method("view_screen_left") else 0.0, 0.0) / zoom)
	m.set_shader_parameter("world_per_px", 1.0 / zoom)
	m.set_shader_parameter("time_s", (now % 3600000) / 1000.0)   # wrapped hourly: keeps float precision
