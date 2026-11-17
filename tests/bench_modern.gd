extends SceneTree
## Timing of the original and the improved route planners on Desert Sands (not part of -Check).
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")

func _initialize():
	var nav = Navigation.new(CollisionData.new())
	var pairs: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	while pairs.size() < 60:
		var a := Vector2i(rng.randi_range(2, 125), rng.randi_range(2, 125))
		var b := Vector2i(rng.randi_range(2, 125), rng.randi_range(2, 125))
		if nav.enterable_static(a) and nav.enterable_static(b): pairs.append([a, b])
	for improved in [false, true]:
		nav.improved = improved
		var t := Time.get_ticks_usec()
		var ok := 0
		var steps := 0
		for p in pairs:
			var r: Dictionary = nav.route_cells(p[0], p[1])
			if r.ok:
				ok += 1
				for s in r.segments: steps += s.size()
		print("%s: %d routes ok of %d, %d steps, %.2f ms per route" % ["improved" if improved else "original", ok, pairs.size(), steps, (Time.get_ticks_usec() - t) / 1000.0 / pairs.size()])
	var t2 := Time.get_ticks_usec()
	for p in pairs: nav.route_target(p[0], p[1])
	print("route_target alone: %.2f ms" % ((Time.get_ticks_usec() - t2) / 1000.0 / pairs.size()))
	quit(0)
