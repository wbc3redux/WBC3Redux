extends RefCounted

var data: Dictionary
var width: int
var height: int

func _init():
	data = preload("res://core/map_data.gd").collision()      # the chosen map (W1; Desert Sands by default)
	width = int(data.size_cells[0])
	height = int(data.size_cells[1])

func world_cell(point: Vector2) -> Vector2i:
	return Vector2i(floori(point.x / 32.0), floori(point.y / 24.0))

func inside(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height

func cell_data(cell: Vector2i) -> Dictionary:
	return data.cells[cell.y * width + cell.x] if inside(cell) else {}

func is_passable(cell: Vector2i, profile: int = 0) -> bool:
	if not inside(cell):
		return false
	var c := cell_data(cell)
	# G1 (RM-4): a border cell of TER material 9 carries nav material 9 and fails 0x42cc10 (collision.py).
	return c.profile_passable[profile] and c.object_indices.is_empty() and int(c.get("nav_material", 0)) != 9

# Diagnostic point/straight-line probe, not recovered original navigation.
# Supercover includes both side cells at exact corners (conservative preview policy).
func trace_segment(start: Vector2, finish: Vector2) -> Dictionary:
	var cell := world_cell(start)
	var target := world_cell(finish)
	var visited: Array[Vector2i] = []
	var delta := finish - start
	var step := Vector2i(signi(int(signf(delta.x))), signi(int(signf(delta.y))))
	var t_delta := Vector2(INF, INF)
	var t_max := Vector2(INF, INF)
	if delta.x != 0:
		t_delta.x = 32.0 / absf(delta.x)
		var boundary := (cell.x + (1 if step.x > 0 else 0)) * 32.0
		t_max.x = (boundary - start.x) / delta.x
	if delta.y != 0:
		t_delta.y = 24.0 / absf(delta.y)
		var boundary := (cell.y + (1 if step.y > 0 else 0)) * 24.0
		t_max.y = (boundary - start.y) / delta.y
	for iteration in range(width * height * 3):
		visited.append(cell)
		if not is_passable(cell):
			return {"clear": false, "blocked_cell": cell, "visited": visited}
		if cell == target:
			return {"clear": true, "blocked_cell": Vector2i(-1, -1), "visited": visited}
		if is_equal_approx(t_max.x, t_max.y):
			for side in [cell + Vector2i(step.x, 0), cell + Vector2i(0, step.y)]:
				visited.append(side)
				if not is_passable(side):
					return {"clear": false, "blocked_cell": side, "visited": visited}
			cell += step
			t_max += t_delta
		elif t_max.x < t_max.y:
			cell.x += step.x
			t_max.x += t_delta.x
		else:
			cell.y += step.y
			t_max.y += t_delta.y
	return {"clear": false, "blocked_cell": cell, "visited": visited}
