extends SceneTree
## Vision option 2: visibility.gd's line of sight against the original (tests/line_of_sight_fixtures.json from
## tools/emulate_line_of_sight.py: 0x485860's ray table and 0x485720 on 40 random height maps), plus the feature heights of
## 0x530420 and the option gate.
##   Godot --headless --path . --script res://tests/test_line_of_sight.gd

const Visibility = preload("res://simulation/visibility.gd")

var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		if failures <= 12: printerr("Line of sight check failed: " + label)

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/line_of_sight_fixtures.json"))
	# 1. The ray table (0x485860). Rays of more than 31 cells overflow their 0x7c-byte slot in the original (its test then
	# reads its own count word and the next slot); sight radii never reach them (Read), so they are not compared.
	var compared := 0
	var long_rays := 0
	for key in fixtures.rays:
		var expected: Array = fixtures.rays[key]
		if expected.size() / 2 > 31:
			long_rays += 1
			continue
		var dx := int(String(key).get_slice(",", 0))
		var dy := int(String(key).get_slice(",", 1))
		var mine: Array = Array(Visibility.ray(dx, dy))
		compared += 1
		# 0x485720 reads the count and the entries before the target's (entry count - 1); in a 31-cell ray that last entry
		# is the slot's own count word (+0x78), so it is not compared.
		var read := (expected.size() / 2 - 1) * 2
		check(mine.size() == expected.size() and mine.slice(0, read) == expected.slice(0, read).map(func(v): return int(v)), "ray %s: %s vs %s" % [key, mine, expected])
	check(compared > 1800, "the rays within 31 cells compared (%d, %d long)" % [compared, long_rays])
	# 2. 0x485720 on the emulated height maps.
	var size: Array = fixtures.size
	var rows := 0
	for case in fixtures.cases:
		var v := Visibility.new(int(size[0]), int(size[1]))
		v.line_of_sight_option = 2
		v.heights.resize(int(size[0]) * int(size[1]))
		for y in int(size[1]):
			for x in int(size[0]): v.heights[y * int(size[0]) + x] = int(case.heights[y][x])
		for r in case.rows:
			var target := Vector2i(int(r.target[0]), int(r.target[1]))
			var viewer := Vector2i(int(r.viewer[0]), int(r.viewer[1]))
			rows += 1
			check(v.line_of_sight(target, viewer, int(r.extra)) == bool(r.visible), "0x485720 %s from %s extra %d: %s" % [target, viewer, int(r.extra), r.visible])
	# 3. The gate: below option 2 every line is clear; 0x530420's feature heights.
	var flat := Visibility.new(8, 8)
	flat.heights.resize(64)
	flat.heights[3 * 8 + 3] = 7
	flat.line_of_sight_option = 1
	check(flat.line_of_sight(Vector2i(5, 3), Vector2i(1, 3)), "option 1: no line-of-sight test")
	flat.line_of_sight_option = 2
	check(not flat.line_of_sight(Vector2i(5, 3), Vector2i(1, 3)), "option 2: a height-7 cell between blocks")
	check(flat.line_of_sight(Vector2i(5, 3), Vector2i(1, 3), 6) == false, "eye capped at 7 still blocked by 7 > the line")
	check(Visibility.feature_height("FPB7") == 6 and Visibility.feature_height("FPW1") == 6 and Visibility.feature_height("FPM0") == 5
		and Visibility.feature_height("FPP2") == 5 and Visibility.feature_height("FSH0") == 5 and Visibility.feature_height("FSA1") == 5
		and Visibility.feature_height("FRB0") == 4 and Visibility.feature_height("FRD0") == 0 and Visibility.feature_height("FDP1") == 0,
		"0x530420 feature heights")
	if failures > 0:
		print("Line of sight checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Line of sight checks passed: %d (%d rays, %d emulated tests)" % [checks, compared, rows])
	quit(0)
