extends RefCounted
## Geometry/order port of 0x5489e0. Lifecycle eligibility is a match-owned callback:
## alive/completed, convertible type, garrison resistance, diplomacy and flags.
## No inference from a visible sprite or a neutral owner alone.
const Entity = preload("res://simulation/entity_state.gd")
var targets: Dictionary = {}
var next_order := 0

func register_target(entity: Entity, footprint: Vector2i, eligible: Callable) -> bool:
	if targets.has(entity.entity_id) or footprint.x < 1 or footprint.y < 1 or not eligible.is_valid():
		return false
	targets[entity.entity_id] = {"entity": entity, "footprint": footprint, "eligible": eligible,
		"order": next_order}
	next_order += 1
	return true

func remove_target(entity_id: int):
	targets.erase(entity_id)

## Original conversion uses BUI width/height, not sparse collision-mask cells.
static func in_range(origin: Vector2i, anchor: Vector2i, footprint: Vector2i, radius: int) -> bool:
	var nearest_x := anchor.x
	var half_width: int = footprint.x >> 1
	if anchor.x < origin.x: nearest_x = mini(origin.x, anchor.x + half_width)
	else: nearest_x = maxi(origin.x, anchor.x - half_width)
	var nearest_y := anchor.y
	if nearest_y < origin.y: nearest_y = mini(origin.y, nearest_y + footprint.y)
	var delta := origin - Vector2i(nearest_x, nearest_y)
	return delta.x * delta.x + delta.y * delta.y <= radius * radius

func select_targets(owner: int, origin: Vector2i, radius: int) -> Array:
	return select_from(targets.values(), owner, origin, radius, func(o, e): return targets[e.entity_id].eligible.call(o, e))

## Milestone 12: the same scan over records {entity, footprint, order} supplied by the match (mines and buildings), with
## one eligibility test for all of them.
static func select_from(records: Array, owner: int, origin: Vector2i, radius: int, eligible: Callable) -> Array:
	var ordered: Array = records.duplicate()
	# Original map rows scan south to north; each row is ordered by increasing X.
	# Equal anchors retain registration order; original equal-anchor tie order Open.
	ordered.sort_custom(func(a, b):
		var ac: Vector2i = a.entity.cell()
		var bc: Vector2i = b.entity.cell()
		if ac == bc: return a.order < b.order
		return ac.y > bc.y if ac.y != bc.y else ac.x < bc.x)
	var result: Array = []
	for record in ordered:
		var entity = record.entity
		if entity.owner == owner or not eligible.call(owner, entity): continue
		if in_range(origin, entity.cell(), record.footprint, radius):
			result.append(entity)
			if result.size() == 8: break
	return result
