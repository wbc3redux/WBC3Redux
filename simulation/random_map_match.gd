extends RefCounted
## RM-7 (RANDOM_MAP_RESEARCH.md "RM-7"): a Random Map from the setup screen's data to a playable bundle, what 0x4e2790 ->
## 0x417280 -> 0x582180 and 0x4179f0 -> 0x583960 do at match start: every "Random" setting is resolved with the 16-bit
## generator (S5), the layout is generated with its connectivity check, the sides are placed on the same generator object,
## and random_map_bundle.gd assembles the result. `prepare` runs on the loading screen's worker thread and touches no
## scene; the caller makes the bundle current (MapData.select_generated) on the main thread.
##
## The 16-bit generator (Read, A2): 0 at launch, never seeded in single player, it runs on across random maps: `session`.
##
## The game generator's seed: DECISION, labelled. R5-10 (Read) reads as far as: 0x4de740 writes the first word 0x000200f1 at
## every match start, the first 0x5820b0 of the process overwrites it with time() (flag 0x61b960), and the second word runs
## on from the image's 0xb78d0945; what draws between 0x4de740 and 0x583960, and on earlier matches, is not traced (Open). The
## rebuild follows that reading and no more: the first map after launch takes the clock as its first word, every later one
## 0x000200f1; the second word starts at the image's value and continues from the previous random map's `rng_after`, which
## leaves out the draws of the match played on it. The match generator continues from `rng_after` (main.gd combat_seed).
##
## Saves keep `spec`, the map's generation inputs: `restore` rebuilds the same map byte for byte (the layout depends only on
## the 16-bit state and the settings, the placement also on the two words).
##
## DELIBERATE MODERN CHANGE (labelled): the original hangs where a start finds no cell and repeats failed layouts without
## limit. `build` tries LAYOUT_TRIES layouts of 256 attempts each with the running generator; past that the match does not
## start and the setup screen shows why (`prepare` returns ok = false).

const RandomMap = preload("res://simulation/random_map.gd")
const RandomMapCheck = preload("res://simulation/random_map_check.gd")
const RandomMapPlace = preload("res://simulation/random_map_place.gd")
const Bundle = preload("res://simulation/random_map_bundle.gd")
const Setup = preload("res://simulation/skirmish_setup.gd")

const FIRST_WORD := 0x000200f1            # 0x60f0ec in single player
const SECOND_WORD := 0xb78d0945           # the image's second word
const LAYOUT_TRIES := 4
const FAILED := "The random map could not be generated. Try other settings."

static var generator = null               # random_map.gd: the session's 16-bit generator (0 at launch)
static var second_word := SECOND_WORD
static var clock_due := true              # the first map after launch

static func session():
	if generator == null: generator = RandomMap.new()
	return generator

## A new launch, for the checks.
static func reset_session():
	generator = null
	second_word = SECOND_WORD
	clock_due = true

## The two words of the next map (see the header).
static func next_words() -> Array:
	var first: int = (int(Time.get_unix_time_from_system()) & 0xffffffff) if clock_due else FIRST_WORD
	clock_due = false
	return [first, second_word]

## S5, 0x4e27ec..0x4e28de (Read, asm): utilities, terrain, size, animals, resources, each roll(1, N, -1) only where the
## setting is its "Random" value. The options keep "Random": what the saved settings hold (0x450760 runs on Okay, before).
static func resolve_settings(options: Dictionary, rm) -> Dictionary:
	var out := {"temples": int(options.temples), "terrain": int(options.terrain), "map_size": int(options.map_size),
		"critters": int(options.critters), "resources": int(options.resource_level)}
	if out.temples == Setup.SAVED_RANDOM.temples[1]: out.temples = rm.roll(1, 5, -1)
	if out.terrain == Setup.SAVED_RANDOM.terrain[1]: out.terrain = rm.roll(1, 10, -1)
	if out.map_size == Setup.SAVED_RANDOM.map_size[1]: out.map_size = rm.roll(1, 4, -1)
	if out.critters == Setup.SAVED_RANDOM.critters[1]: out.critters = rm.roll(1, 5, -1)
	if out.resources == Setup.SAVED_RANDOM.resource_level[1]: out.resources = rm.roll(1, 3, -1)
	return out

## The generation inputs of one map, resolved. `lcg` (the 16-bit state the kept layout started from) and the results are
## added by `build`.
static func spec_of(setup: Dictionary, rm, words: Array) -> Dictionary:
	var options: Dictionary = setup.options
	var settled := resolve_settings(options, rm)
	return {"schema": 1, "terrain": settled.terrain, "size": RandomMap.size_cells(settled.map_size), "temples": settled.temples,
		"critters": settled.critters, "resources": settled.resources, "quests": bool(options.quests),
		"no_towers": bool(options.get("no_starting_towers", false)), "victory": int(options.victory),
		"sides": Setup.random_sides(setup), "rng": words.duplicate()}

## generate, then place on the same object (RM-5). `check` replaces the connectivity check (the failure test).
static func build(spec: Dictionary, rm, tries: int = LAYOUT_TRIES, check: Callable = Callable()) -> Dictionary:
	var settings := {"rng": spec.rng, "temples": int(spec.temples), "animals": RandomMapPlace.ANIMAL_COUNTS[int(spec.critters)],
		"resources": int(spec.resources), "quests": bool(spec.quests), "no_towers": bool(spec.no_towers), "victory": int(spec.victory)}
	for attempt in tries:
		var lcg: int = rm.state
		var layout: Dictionary = rm.generate(int(spec.terrain), int(spec.size), check if check.is_valid() else RandomMapCheck.new(rm.data).callable())
		if not bool(layout.ok): continue
		var placed: Dictionary = RandomMapPlace.new(rm).place(layout, spec.sides, settings)
		if not bool(placed.ok): continue
		var kept: Dictionary = spec.duplicate(true)
		kept.lcg = lcg
		kept.rng_after = placed.rng_after
		var bundle: Dictionary = Bundle.assemble(layout, placed, spec.sides, rm.data)
		bundle.spec = kept
		return {"ok": true, "spec": kept, "layout": layout, "placed": placed, "bundle": bundle}
	return {"ok": false, "error": FAILED}

## The whole match start for `setup` (a copy of the screen's, Setup.pending): on success the setup holds the starts and
## the spec, and `bundle` is ready for MapData.select_generated.
static func prepare(setup: Dictionary, rm = null, tries: int = LAYOUT_TRIES, check: Callable = Callable()) -> Dictionary:
	var generator_now = rm if rm != null else session()
	var spec := spec_of(setup, generator_now, next_words())
	var built := build(spec, generator_now, tries, check)
	if not bool(built.ok): return built
	second_word = int(built.spec.rng_after[1])
	setup.random_map = built.spec
	setup.map = String(built.bundle.map.source)
	setup.map_width = int(built.spec.size)
	for start in built.placed.starts:
		setup.players[int(start.side_index)].start = Vector2i(int(start.cell[0]), int(start.cell[1]))
	return built

## A save's map again: `spec` as saved (numbers may be JSON floats). {"ok", "bundle"} or {"ok": false, "error"}.
static func restore(spec: Dictionary) -> Dictionary:
	var clean = normal(spec)
	if not valid(clean): return {"ok": false, "error": "The save is damaged (no random map data)."}
	var built := build(clean, RandomMap.new(int(clean.lcg)), 1)
	if not bool(built.ok): return {"ok": false, "error": "The saved random map could not be built again."}
	return built

## The header is not under the save's checksums: a spec is checked before it drives the generator.
static func valid(s) -> bool:
	if not s is Dictionary: return false
	for key in ["lcg", "rng", "sides", "size", "terrain", "temples", "critters", "resources", "quests", "no_towers", "victory"]:
		if not s.has(key): return false
	if not s.sides is Array or s.sides.is_empty() or not s.rng is Array or s.rng.size() != 2: return false
	for side in s.sides:
		if not side is Dictionary or not side.has("slot") or not side.has("race"): return false
		if int(side.slot) < 0 or int(side.slot) >= Setup.SLOTS or int(side.race) < 0 or int(side.race) >= RandomMapPlace.TOWER_CODES.size(): return false
	return RandomMap.SIZES.has(int(s.size)) and int(s.terrain) >= 0 and int(s.terrain) < 10 and int(s.temples) >= 0 and int(s.temples) <= 4 \
		and int(s.critters) >= 0 and int(s.critters) < RandomMapPlace.ANIMAL_COUNTS.size() and int(s.resources) >= 0 and int(s.resources) <= 2

## JSON gives every number as a float; a spec holds only integers, booleans and containers of them.
static func normal(value):
	if value is float: return int(value)
	if value is Array: return value.map(func(v): return normal(v))
	if value is Dictionary:
		var out := {}
		for key in value: out[key] = normal(value[key])
		return out
	return value

## The map's identity: every input that decides it.
static func identity(spec: Dictionary) -> String:
	var s = normal(spec)
	if s.is_empty(): return ""
	return "%s" % [[s.get("terrain"), s.get("size"), s.get("temples"), s.get("critters"), s.get("resources"), s.get("quests"),
		s.get("no_towers"), s.get("victory"), s.get("lcg"), s.get("rng"), s.get("sides", []).map(func(side): return [side.slot, side.race])]]
