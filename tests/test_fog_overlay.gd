extends SceneTree
## P-3: main.gd refresh_fog_overlay builds the fog pixels with fill / find instead of a loop over every cell. On random fog
## maps (empty, full, sparse and dense, with shroud and fog on and off, 128 and 256 maps) its image must equal the pixels
## of the per-cell loop it replaced: alpha 255 unexplored (shroud), Color(0, 0, 0, 0.45).a8 not visible now (fog), else 0.
##   Godot --headless --path . --script res://tests/test_fog_overlay.gd

const Visibility = preload("res://simulation/visibility.gd")

var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		if failures <= 10: printerr("Fog overlay check failed: " + label)

## The loop main.gd used before P-3.
static func reference(vis, player: int) -> PackedByteArray:
	var count: int = vis.width * vis.height
	var explored: PackedByteArray = vis.explored[player]
	var seen: PackedByteArray = vis.visible[player]
	var dim := Color(0, 0, 0, 0.45).a8
	var pixels := PackedByteArray()
	pixels.resize(count * 4)
	for i in count:
		if vis.shroud and explored[i] == 0: pixels[i * 4 + 3] = 255
		elif vis.fog and seen[i] == 0: pixels[i * 4 + 3] = dim
	return pixels

func run():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xf06
	var scene = load("res://battle/main.gd").new()
	var case := 0
	for size in [128, 256]:
		for density in [0.0, 0.02, 0.3, 0.7, 1.0]:
			for flags in 4:
				var vis = Visibility.new(size, size)
				vis.shroud = flags & 1 != 0
				vis.fog = flags & 2 != 0
				vis.ensure(scene.local_player)
				var explored: PackedByteArray = vis.explored[scene.local_player]
				var seen: PackedByteArray = vis.visible[scene.local_player]
				for i in size * size:
					if rng.randf() < density:
						explored[i] = 1
						if rng.randf() < 0.5: seen[i] = 1
				vis.explored[scene.local_player] = explored
				vis.visible[scene.local_player] = seen
				scene.visibility = vis
				scene.refresh_fog_overlay()
				check(scene.fog_image.get_data() == reference(vis, scene.local_player), "case %d: size %d, density %.2f, flags %d" % [case, size, density, flags])
				check(scene.fog_overlay.texture != null and scene.fog_overlay.texture.get_size() == Vector2(size, size), "case %d: texture" % case)
				case += 1
	# Other byte values (not written by visibility.gd) take the per-cell loop.
	var odd = Visibility.new(128, 128)
	odd.ensure(scene.local_player)
	var bytes: PackedByteArray = odd.visible[scene.local_player]
	bytes[5] = 2
	odd.visible[scene.local_player] = bytes
	scene.visibility = odd
	scene.refresh_fog_overlay()
	check(scene.fog_image.get_data() == reference(odd, scene.local_player), "byte value 2")
	# main.gd's member nodes are made with the script (var x := Node.new()) and only freed with the scene tree.
	for prop in scene.get_property_list():
		var value = scene.get(prop.name)
		if value is Node and is_instance_valid(value) and value.get_parent() == null: value.free()
	scene.free()
	if failures > 0:
		print("Fog overlay checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Fog overlay checks passed: %d" % checks)
	quit(0)
