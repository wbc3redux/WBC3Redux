extends SceneTree
## Fog-of-war parity (milestone 8-fix, REVIEW_COMBAT.md D2): replays the scenarios of tests/fog_fixtures.json
## (tools/emulate_fog.py: 0x5468e0 -> 0x546f00 -> 0x47de40 / 0x485d20 and 0x485c70 executed on Desert Sands) through
## simulation/visibility.gd and compares the visible, explored and armed layers after every game update.
const Visibility = preload("res://simulation/visibility.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
var checks := 0
var failures := 0

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fog_fixtures.json"))
	for scenario in fixtures.scenarios: _replay(scenario)
	_test_latency(fixtures)
	_test_cadence()
	if failures == 0: print("Fog checks passed: ", checks)
	else: printerr("Fog failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func _replay(s: Dictionary):
	var width: int = int(s.width)
	var height: int = int(s.height)
	var vis = Visibility.new(width, height)
	vis.ensure(0)
	var size := width * height
	var expected := {"visible": PackedByteArray(), "explored": PackedByteArray(), "armed": PackedByteArray()}
	for key in expected: expected[key].resize(size)
	expected.armed.fill(1)
	check(int(s.initial.armed) == size and int(s.initial.visible) == 0 and int(s.initial.explored) == 0, "%s: 0x47a940 arms every cell" % s.name)
	var sprites: Array = []
	for sp in s.sprites: sprites.append({"owner": int(sp.owner), "kind": int(sp.kind), "cell": Vector2i(int(sp.cell[0]), int(sp.cell[1])), "facing": 4})
	var steps_at := {}
	for key in s.moves:
		for step in s.moves[key]:
			var u := int(step[0])
			if not steps_at.has(u): steps_at[u] = []
			steps_at[u].append([int(key), Vector2i(int(step[1][0]), int(step[1][1]))])
	var events := {}
	for e in s.events: events[int(e.u)] = e
	var sweeps: Array = []
	var clears: Array = []
	var mismatch := -1
	var bui_offset: int = (int(s.bui_height) - 1) >> 1
	for u in int(s.updates):
		var sources: Array = []
		for sp in sprites:
			if sp.owner != 0: continue
			var sight: Vector2i = sp.cell + (Vector2i(0, bui_offset) if sp.kind == 3 else Vector2i.ZERO)
			sources.append({"player": 0, "cell": sight, "radius": Visibility.DEFAULT_RADIUS, "viewers": [0]})
		var before_counter: int = vis.counter
		var before_phase: int = vis.sprite_counter
		vis.update(sources, [0])
		if (before_phase + 1) % Visibility.SPRITE_PHASES == 0:
			if before_counter % Visibility.SWEEP_EVERY == 0: sweeps.append(u)
			if before_counter == Visibility.CLEAR_PHASE: clears.append(u)
		var due: Array = steps_at.get(u, [])
		due.sort_custom(func(a, b): return a[0] < b[0])
		for item in due:
			var sp: Dictionary = sprites[item[0]]
			var to: Vector2i = item[1]
			var direction: int = UnitAgent.direction_of(Vector2i(signi(to.x - sp.cell.x), signi(to.y - sp.cell.y)))
			vis.arm_step(sp.owner, sp.cell, to, direction != sp.facing)
			sp.facing = direction
			sp.cell = to
		if events.has(u):
			var e: Dictionary = events[u]
			for key in ["visible", "explored", "armed"]:
				for index in e.get(key + "_on", []): expected[key][int(index)] = 1
				for index in e.get(key + "_off", []): expected[key][int(index)] = 0
		var same: bool = vis.visible[0] == expected.visible and vis.explored[0] == expected.explored and vis.armed[0] == expected.armed
		checks += 1
		if not same and mismatch < 0:
			mismatch = u
			failures += 1
			push_error("%s: layers differ from the executable after update %d (%s)" % [s.name, u, _first_difference(vis, expected, width)])
	check(sweeps == _ints(s.sweeps), "%s: sweep updates %s want %s" % [s.name, sweeps.slice(0, 6), _ints(s.sweeps).slice(0, 6)])
	check(clears == _ints(s.clears), "%s: darken updates %s want %s" % [s.name, clears, s.clears])
	var counters: Array = s.counters
	check(int(counters[counters.size() - 1][1]) == vis.counter and int(counters[counters.size() - 1][0]) == vis.sprite_counter,
		"%s: counters 0xb90fa4/0xb90f9c end at %s, port %d/%d" % [s.name, counters[counters.size() - 1], vis.sprite_counter, vis.counter])

func _first_difference(vis, expected: Dictionary, width: int) -> String:
	for key in ["visible", "explored", "armed"]:
		var got: PackedByteArray = vis.get(key)[0]
		for i in got.size():
			if got[i] != expected[key][i]: return "%s at (%d, %d): port %d, original %d" % [key, i % width, i / width, got[i], expected[key][i]]
	return "?"

func _ints(values: Array) -> Array:
	var out: Array = []
	for v in values: out.append(int(v))
	return out

## Latencies measured on the original (geometric in/out of sight -> visible flag follows).
func _test_latency(fixtures: Dictionary):
	var by_name := {}
	for s in fixtures.scenarios: by_name[s.name] = s
	var toward: Array = by_name.viewer_walks_toward_and_away.latency["1"]
	check(toward.size() == 2 and int(toward[0].in_sight) == 1 and int(toward[0].latency_ms) > 0 and int(toward[0].latency_ms) <= 500,
		"viewer approaching: the enemy appears at the next sweep (<= 500 ms): %s" % [toward])
	check(toward.size() == 2 and int(toward[1].in_sight) == 0 and int(toward[1].latency_ms) > 500 and int(toward[1].latency_ms) <= 4000,
		"viewer leaving: the enemy disappears at the next darken (<= 4 s): %s" % [toward])
	var walker: Array = by_name.enemy_walks_in_and_out.latency["1"]
	check(walker.size() == 2 and int(walker[0].latency_ms) == 0 and int(walker[1].latency_ms) == 0,
		"an enemy walking through a stationary viewer's lit disc appears and disappears with its step: %s" % [walker])
	check(by_name.stationary.latency["2"].is_empty() and by_name.stationary_inside_armed_box.latency["2"].is_empty(), "stationary enemies keep their state")

## Port-only checks of the cadence and the arm box.
func _test_cadence():
	var vis = Visibility.new(40, 40)
	var src := [{"player": 0, "cell": Vector2i(20, 20), "radius": 10, "viewers": [0]}]
	var first := -1
	for u in 30:
		vis.update(src, [0])
		if first < 0 and vis.is_visible(0, Vector2i(20, 20)): first = u
	check(first == 3, "first sweep on the 4th update (0xb90fa4 wraps): %d" % first)
	check(vis.is_visible(0, Vector2i(27, 27)) and not vis.is_visible(0, Vector2i(28, 28)), "sight circle edge (trunc hypot <= 10)")
	var box = Visibility.new(80, 80)
	box.ensure(0)
	box.darken([0])
	box.arm(Vector2i(40, 40), 14)
	check(box.is_armed(0, Vector2i(21, 21)) and box.is_armed(0, Vector2i(58, 58)) and not box.is_armed(0, Vector2i(20, 40)) and not box.is_armed(0, Vector2i(59, 40)),
		"0x485c70 box [c - r - 5, c + r + 5)")
