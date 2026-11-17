extends SceneTree
## P-2: navigation.gd's incremental sector rebuild (_rebuild_sectors, used when a building is stamped or removed) against the
## full build (_build_sectors). On several maps (land, water, caves, a 256 map) random buildings are stamped and removed;
## after every change the regions, their links, the cell map and the sector lists must equal a full build's exactly.
##   Godot --headless --path . --script res://tests/test_sector_rebuild.gd

const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const MapData = preload("res://core/map_data.gd")

var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		if failures <= 10: printerr("Sector rebuild check failed: " + label)

func snapshot(nav) -> Array:
	return [nav.region_of.duplicate(), var_to_str(nav.regions), var_to_str(nav.sector_regions)]

## P-3: the extent-2 layer rebuilt in part after stamps, removals and direct building-cell writes (set_building_cell, which
## drops no layer) equals a full _build_layer each time layer(2) rebuilds it; sometimes several changes pass between two
## asks, and the old layer carries leftover search state (dist / parent) as after a route search.
func check_layers(slug: String, rng: RandomNumberGenerator):
	var collision = CollisionData.new()
	var nav = Navigation.new(collision)
	nav.layer(2)
	var stamped: Array = []
	var asked := 0
	var partial := 0
	for i in 30:
		var roll := rng.randi_range(0, 7)
		if not stamped.is_empty() and roll <= 1:
			nav.unstamp_building(stamped.pop_at(rng.randi_range(0, stamped.size() - 1)))
		elif roll == 2:
			nav.set_building_cell(Vector2i(rng.randi_range(1, collision.width - 2), rng.randi_range(1, collision.height - 2)), 5000 + i)
		else:
			var w := rng.randi_range(1, 6)
			var h := rng.randi_range(1, 6)
			var mask: Array = []
			for r in h: mask.append(rng.randi_range(0, 3) if rng.randi_range(0, 4) == 0 else 0)
			if not nav.stamp_building(2000 + i, rng.randi_range(-2, collision.width - 3), rng.randi_range(-2, collision.height - 3), w, h, mask).is_empty():
				stamped.append(2000 + i)
		if rng.randi_range(0, 2) == 0: continue
		# A layer still cached (no stamp since it was built; set_building_cell drops none) is returned as it is, by the
		# old code too; a dropped one is rebuilt, and must equal the full build the old code made at this point.
		var stale: bool = nav._stale_layers.has(2)
		var got: Dictionary = nav.layer(2)
		asked += 1
		if not stale: continue
		partial += 1
		check(var_to_str(got) == var_to_str(nav._build_layer(2)), "%s layer change %d" % [slug, i])
		for node in got.regions:
			node.dist = rng.randi_range(-1, 50)
			node.parent = rng.randi_range(-1, 50)
	print("%s: extent-2 layer asked %d times, %d partial rebuilds" % [slug, asked, partial])

func run():
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5ec7
	for slug in ["desert-sands", "four-rivers", "cavemen", "the-lions-den", "hills-to-climb", "forest-lakes"]:
		MapData.select(slug)
		var collision = CollisionData.new()
		var nav = Navigation.new(collision)
		var stamped: Array = []
		var incremental := 0
		for i in 30:
			if not stamped.is_empty() and rng.randi_range(0, 3) == 0:
				var id: int = stamped.pop_at(rng.randi_range(0, stamped.size() - 1))
				nav.unstamp_building(id)
			else:
				var w := rng.randi_range(1, 6)
				var h := rng.randi_range(1, 6)
				var left := rng.randi_range(-2, collision.width - 3)
				var top := rng.randi_range(-2, collision.height - 3)
				var mask: Array = []
				for r in h: mask.append(rng.randi_range(0, 3) if rng.randi_range(0, 4) == 0 else 0)
				var id := 1000 + i
				if not nav.stamp_building(id, left, top, w, h, mask).is_empty(): stamped.append(id)
			var after := snapshot(nav)
			nav._build_sectors()
			var full := snapshot(nav)
			incremental += 1
			check(after[0] == full[0], "%s change %d: cell map" % [slug, i])
			check(after[1] == full[1], "%s change %d: regions and links" % [slug, i])
			check(after[2] == full[2], "%s change %d: sector lists" % [slug, i])
		# A building beside existing ones, on a sector edge (the neighbours' links): stamp over a sector corner.
		var corner := Vector2i(8 * 5 - 2, 8 * 5 - 2)
		nav.stamp_building(9999, corner.x, corner.y, 4, 4, [0, 0, 0, 0])
		var after := snapshot(nav)
		nav._build_sectors()
		check(after == snapshot(nav), "%s: sector-corner stamp" % slug)
		print("%s: %d changes, %d regions" % [slug, incremental + 1, nav.regions.size()])
		check_layers(slug, rng)
	if failures > 0:
		print("Sector rebuild checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Sector rebuild checks passed: %d" % checks)
	quit(0)
