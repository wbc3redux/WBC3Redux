extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	assert(scene.map_objects.size() == 66)
	var count := 1
	for object in scene.map_objects:
		assert(object.z_index == int(object.position.y) + int(object.definition.depth_offset))
		assert(object.sheet.get_size() == Vector2(object.definition.frame_size[0] * object.definition.frames, object.definition.frame_size[1]))
		# A ground unit crosses the object's depth plane independently of the sprite pivot.
		var unit = scene.units[0]
		unit.position = Vector2(object.position.x, object.z_index - 2)
		unit.advance(0)
		assert(unit.z_index < object.z_index)
		unit.position.y += 2
		unit.advance(0)
		assert(unit.z_index > object.z_index)
		count += 4
		if int(object.definition.frames) > 1:
			object.advance(0.150)
			assert(object.frame == 0)
			object.advance(0.001)
			assert(object.frame == 1)
			object.advance(1.0)
			assert(object.frame == 2) # One original update, not accumulated catch-up.
			for i in range(6): object.advance(0.151)
			assert(object.frame == 0)
			count += 4
	print("Object checks passed: %d; 66 source placements, geometry, depth and tower deadlines" % count)
	quit()
