extends Node2D
var owner_scene: Node

func _draw():
	if owner_scene != null and owner_scene.drag_active:
		var box := Rect2(owner_scene.drag_start, owner_scene.drag_end - owner_scene.drag_start).abs()
		draw_rect(box, Color(0.3,0.9,0.65,0.12))
		draw_rect(box, Color(0.5,1,0.7), false, 1)
