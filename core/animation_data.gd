extends RefCounted
const Assets = preload("res://core/asset_store.gd")

static func metadata() -> Dictionary:
	return Assets.json("sprite_metadata.json")["sprites"]

static func frame_rect(meta: Dictionary, row: int, frame: int) -> Rect2:
	var size = meta.frame_size
	return Rect2(frame * size[0], row * size[1], size[0], size[1])

static func sprite_offset(meta: Dictionary) -> Vector2:
	return Vector2(-meta.pivot[0], -meta.pivot[1])

# Artwork rows: north first, clockwise; screen Y increases downwards.
static func direction_from_vector(vector: Vector2) -> int:
	return posmod(roundi(vector.angle() / (PI / 4)) + 2, 8)
