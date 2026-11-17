extends SceneTree
## Map wave 5 (MAPS_RESEARCH.md "Wave 5"): the EFFH map effects against the executable.
## 1. simulation/map_effects.gd's emitter equals the original init 0x545760 and tick 0x545b90 run under Unicorn
##    (tests/particle_fixtures.json, tools/emulate_particles.py) step for step: timers, counts, emitter / force / velocity /
##    colour values, every particle and the generator state, for the five Assets/Particles definitions, including the
##    off-screen steps and the end of the temporary emitters;
## 2. the import: assets/particles.json equals the definitions the emulator read, and every map with EFFH records gets one
##    emitter per record at its pixel (Cavemen 2, Valley of the Dead 1, Volcanic Pit 10) that keeps releasing.

const MapEffects = preload("res://simulation/map_effects.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")
const MapData = preload("res://core/map_data.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Map effect check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/particle_fixtures.json"))
	for r in f.runs:
		run_checks(f, r)
	import_checks(f)
	if failures > 0:
		printerr("Map effect checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Map effect checks passed: %d" % checks)
	quit()

static func ints(a: Array) -> Array:
	return a.map(func(v): return int(v))

func state(em) -> Dictionary:
	var parts := []
	for i in em.used:
		var p: Array = em.particles[i]
		parts.append([0] if p[0] == 0 else p.duplicate())
	return {"emitter": em.emitter.duplicate(), "counts": [em.used, em.alive, em.released], "force": em.force.duplicate(),
		"velocity": em.velocity.duplicate(), "colour": em.colour.duplicate(),
		"timers": [em.age, em.next_release, em.next_force, em.next_move, em.last], "particles": parts, "rng": em.rng.state()}

func compare(label: String, em, expected: Dictionary) -> bool:
	var got := state(em)
	for key in ["emitter", "counts", "force", "velocity", "colour", "timers", "rng"]:
		if got[key] != ints(expected[key]):
			check(false, "%s %s: %s, expected %s" % [label, key, got[key], ints(expected[key])])
			return false
	var want: Array = expected.particles
	if got.particles.size() != want.size():
		check(false, "%s: %d slots, expected %d" % [label, got.particles.size(), want.size()])
		return false
	for i in want.size():
		if got.particles[i] != ints(want[i]):
			check(false, "%s particle %d: %s, expected %s" % [label, i, got.particles[i], ints(want[i])])
			return false
	return true

func run_checks(f: Dictionary, r: Dictionary):
	var d: Dictionary = f.definitions[r.id]
	var label := "%s from %d" % [r.id, int(r.start)]
	var em = MapEffects.Emitter.new(d, Vector2i(int(f.position[0]), int(f.position[1])), int(r.start),
		CombatRng.new(int(f.seed[0]), int(f.seed[1])), int(f.sheet))
	check(em.cell == Vector2i(int(r.placed.cell[0]), int(r.placed.cell[1])), "%s: cell %s (0x4939a0)" % [label, em.cell])
	var steps: Array = r.steps
	var ok := compare(label + " init", em, steps[0])
	var culled := range(int(f.culled[0]), int(f.culled[1]))
	var matched := 0
	for i in range(1, steps.size()):
		if not ok: break
		var s: Dictionary = steps[i]
		var alive: bool = em.tick(int(s.clock), not culled.has(i - 1))
		if alive != bool(int(s.alive)):
			check(false, "%s step %d: emitter kept %s, expected %s" % [label, i, alive, bool(int(s.alive))])
			ok = false
			break
		if not alive: matched += 1; break
		ok = compare("%s step %d" % [label, i], em, s)
		if ok: matched += 1
	check(ok, "%s: %d of %d ticks equal the executable" % [label, matched, steps.size() - 1])

const EFFH_MAPS := {"cavemen": 2, "valley-of-the-dead": 1, "volcanic-pit": 10}

func import_checks(f: Dictionary):
	var imported = JSON.parse_string(FileAccess.get_file_as_string("res://assets/particles.json")) if FileAccess.file_exists("res://assets/particles.json") else null
	check(imported is Dictionary, "assets/particles.json imported (run -ImportAssets)")
	if not imported is Dictionary: return
	var defs: Dictionary = imported.definitions
	check(defs.keys().size() == f.definitions.keys().size(), "assets/particles.json: %d definitions" % defs.size())
	for key in f.definitions:
		var a: Dictionary = f.definitions[key]
		var b: Dictionary = defs.get(key, {})
		var same := not b.is_empty()
		for field in a:
			if field == "source": continue
			if str(a[field]) != str(b.get(field)): same = false
		check(same, "assets/particles.json %s equals the emulator's definition" % key)
	for slug in EFFH_MAPS:
		var expected: int = EFFH_MAPS[slug]
		var path := "res://assets/maps/%s/map.json" % slug
		check(FileAccess.file_exists(path), "%s imported" % slug)
		if not FileAccess.file_exists(path): continue
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		var records: Array = m.get("effects", [])
		check(records.size() == expected, "%s: %d EFFH records" % [slug, records.size()])
		var effects = MapEffects.new(records, defs, 0)
		check(effects.emitters.size() == expected, "%s: %d emitters" % [slug, effects.emitters.size()])
		for i in effects.emitters.size():
			var p: Array = records[i].world_position
			check(effects.emitters[i].pixel == Vector2i(int(p[0]), int(p[1])), "%s emitter %d at its record's pixel" % [slug, i])
		for t in range(25, 5001, 25):
			effects.tick(t)
		var alive := 0
		for em in effects.emitters: alive += em.alive
		check(effects.emitters.size() == expected and alive > 0, "%s: emitters still releasing after 5 s (%d particles alive)" % [slug, alive])
