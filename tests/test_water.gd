extends SceneTree
## Milestone M-3 (MOVEMENT_RESEARCH.md "Water"): water (movement type 2) and amphibious (type 3) movement against the
## original code run under Unicorn on the six wave-3 maps (tests/water_fixtures.json, tools/emulate_water.py):
## 1. 0x42cc10 for types 0, 2 and 3 at extents 1 and 2 on every cell equals navigation.passable_extent;
## 2. the sector layers of 0x5090c0 (extents 1 and 2): per sector the regions in creation order with their seed
##    material (land and water regions, building regions 255) and per cell the region id;
## 3. whole move orders 0x42f650 + 0x42ff30 for types 0, 2 and 3 between land and water cells, segment for segment
##    (coast crossings, land units ordered onto water and water units onto land retargeted);
## 4. G1 (RM-4): a border cell of TER material 9 fails the cell check;
## 5. flyers (type 1) on the cave maps (tests/flight_fixtures.json): the cell check and whole orders around material 9.

const MapData = preload("res://core/map_data.gd")
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")

var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Water check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/water_fixtures.json"))
	check(fixtures.material_class.map(func(v): return int(v)) == Navigation.MATERIAL_CLASS, "material classes 0x603ed0")
	for t in 4:
		check(fixtures.admission[t].map(func(v): return int(v)) == Navigation.ADMISSION[t], "admission 0x603ee0 type %d" % t)
	for slug in fixtures.maps:
		map_checks(slug, fixtures.maps[slug])
	MapData.select(MapData.DEFAULT)
	border_material_nine()
	var flights: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/flight_fixtures.json"))
	for slug in flights.maps:
		flight_checks(slug, flights.maps[slug])
	MapData.select(MapData.DEFAULT)
	if failures > 0:
		printerr("Water checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Water checks passed: %d" % checks)
	quit()

# G1 (RANDOM_MAP_RESEARCH.md "RM-4", Emulated; tools/test_materials.py checks collision.py against the original on the
# cave scenarios): a border cell of TER material 9 carries nav material 9 with material 0's profile and fails 0x42cc10 for
# every type. No imported map has one yet (wave 5), so a passable border cell of Desert Sands gets it in a copy.
func border_material_nine():
	var collision := CollisionData.new()
	collision.data = collision.data.duplicate(true)
	var cell := Vector2i(-1, -1)
	for x in range(1, collision.width - 1):
		if collision.is_passable(Vector2i(x, 0)):
			cell = Vector2i(x, 0)
			break
	check(cell.x >= 0, "G1: a passable border cell on Desert Sands")
	collision.cell_data(cell).nav_material = 9
	check(bool(collision.cell_data(cell).profile_passable[0]), "G1: the profile stays material 0's")
	check(not collision.is_passable(cell), "G1: CollisionData.is_passable fails at border material 9")
	var nav := Navigation.new(collision)
	for mtype in [0, 3]:          # type 2 fails on this land cell anyway
		check(not nav.passable_extent(cell, 1, mtype), "G1: 0x42cc10 type %d fails at border material 9" % mtype)

## Map wave 5 (tests/flight_fixtures.json, tools/emulate_flight.py): flyers (type 1) fail 0x42cc10 only on material 9, and
## the original routes them around the cave walls with the same order machinery (0x42f650 + 0x42ff30) as the other types.
func flight_checks(slug: String, f: Dictionary):
	var started := Time.get_ticks_msec()
	MapData.select(slug)
	var collision := CollisionData.new()
	var nav := Navigation.new(collision)
	var width: int = collision.width
	var height: int = collision.height
	for key in f.blocked:
		var extent := int(key.split("_extent")[1])
		var bitmap := hex_bytes(f.blocked[key].bitmap)
		var diff := 0
		for y in height:
			for x in width:
				if (not nav.passable_extent(Vector2i(x, y), extent, 1)) != bit(bitmap, y * width + x): diff += 1
		check(diff == 0, "%s 0x42cc10 type 1 extent %d: %d differences" % [slug, extent, diff])
	var same_count := 0
	var walls := 0
	for r in f.routes:
		var start := Vector2i(int(r.start[0]), int(r.start[1]))
		var goal := Vector2i(int(r.goal[0]), int(r.goal[1]))
		var route: Dictionary = nav.flight_cells(start, goal)
		var mine: Array = []
		for segment in route.get("segments", []):
			mine.append(segment.map(func(c): return [c.x, c.y]))
		var theirs: Array = r.segments.map(func(s): return s.cells.map(func(c): return [int(c[0]), int(c[1])]))
		if theirs.size() == 1 and theirs[0].is_empty(): theirs = []
		var same: bool = bool(route.ok) == bool(r.ok) and mine == theirs
		check(same, "%s type 1 %s -> %s%s: ours %s %s, original %s %s" % [slug, start, goal, " (across a wall)" if r.crosses_wall else "",
			route.ok, mine.map(func(s): return s.size()), r.ok, theirs.map(func(s): return s.size())])
		if same: same_count += 1
		if bool(r.crosses_wall): walls += 1
	print("%s: %d / %d flights match (%d across a wall), %d ms" % [slug, same_count, f.routes.size(), walls, Time.get_ticks_msec() - started])

static func bit(data: PackedByteArray, i: int) -> bool:
	return (data[i >> 3] >> (i & 7)) & 1 == 1

func map_checks(slug: String, f: Dictionary):
	var started := Time.get_ticks_msec()
	MapData.select(slug)
	var collision := CollisionData.new()
	var nav := Navigation.new(collision)
	var width: int = collision.width
	var height: int = collision.height
	check(Vector2i(width, height) == Vector2i(int(f.size_cells[0]), int(f.size_cells[1])), "%s size" % slug)
	# 1. the cell check per type and extent
	for key in f.blocked:
		var parts: PackedStringArray = key.replace("type", "").split("_extent")
		var mtype := int(parts[0])
		var extent := int(parts[1])
		var bitmap := hex_bytes(f.blocked[key].bitmap)
		var diff := 0
		var first := Vector2i(-1, -1)
		for y in height:
			for x in width:
				var blocked := not nav.passable_extent(Vector2i(x, y), extent, mtype)
				if blocked != bit(bitmap, y * width + x):
					diff += 1
					if first.x < 0: first = Vector2i(x, y)
		check(diff == 0, "%s 0x42cc10 type %d extent %d: %d differences (first %s)" % [slug, mtype, extent, diff, first])
	# 2. sector layers
	for index in 2:
		var expected: Dictionary = f.layers[index]
		var nodes: Array
		var region_of: PackedInt32Array
		var by_sector: Dictionary
		if index == 0:
			nodes = nav.regions
			region_of = nav.region_of
			by_sector = nav.sector_regions
		else:
			var l: Dictionary = nav.layer(2)
			nodes = l.regions
			region_of = l.region_of
			by_sector = l.sector_regions
		var sector_diff := 0
		var first_sector := ""
		var stride := width >> 3
		for s in expected.sectors.size():
			var sector := Vector2i(s % stride, s / stride)
			var mine: Array = []
			for r in by_sector.get(sector, []):
				mine.append([int(nodes[r].id), int(nodes[r].get("material", 0))])
			var theirs: Array = expected.sectors[s].map(func(e): return [int(e[0]), int(e[1])])
			if mine != theirs:
				sector_diff += 1
				if first_sector == "": first_sector = "%s ours %s original %s" % [sector, mine, theirs]
		check(sector_diff == 0, "%s layer %d: %d sectors differ (%s)" % [slug, index + 1, sector_diff, first_sector])
		var cells := hex_bytes(expected.cells)
		var cell_diff := 0
		var first_cell := Vector2i(-1, -1)
		for i in width * height:
			var r: int = region_of[i]
			var id: int = 0xff if r < 0 else int(nodes[r].id)
			if id != int(cells[i]):
				cell_diff += 1
				if first_cell.x < 0: first_cell = Vector2i(i % width, i / width)
		check(cell_diff == 0, "%s layer %d: %d cells in another region (first %s)" % [slug, index + 1, cell_diff, first_cell])
	# 3. whole orders
	var counts := {0: 0, 2: 0, 3: 0}
	var crossings := 0
	for r in f.routes:
		var mtype := int(r.type)
		var start := Vector2i(int(r.start[0]), int(r.start[1]))
		var goal := Vector2i(int(r.goal[0]), int(r.goal[1]))
		var route: Dictionary = nav.route_cells(start, goal, 1, mtype)
		var mine: Array = []
		for segment in route.get("segments", []):
			mine.append(segment.map(func(c): return [c.x, c.y]))
		var theirs: Array = r.segments.map(func(s): return s.cells.map(func(c): return [int(c[0]), int(c[1])]))
		# A goal (or retargeted goal) equal to the start: the original returns one empty segment, the port none (no step either way).
		if theirs.size() == 1 and theirs[0].is_empty(): theirs = []
		var same: bool = bool(route.ok) == bool(r.ok) and mine == theirs
		check(same, "%s type %d %s -> %s: ours %s %s, original %s %s" % [slug, mtype, start, goal, route.ok,
			mine.map(func(s): return s.size()), r.ok, theirs.map(func(s): return s.size())])
		if same: counts[mtype] += 1
		var case_name := String(r.get("name", ""))
		if (case_name.contains("bridge") and mtype != 2) or (case_name == "west_to_east_bank" and mtype == 0):
			var last: Array = theirs[-1][-1] if not theirs.is_empty() and not theirs[-1].is_empty() else []
			check(bool(r.ok) and last == [goal.x, goal.y], "%s %s type %d reaches the far bank over the bridge deck" % [slug, r.name, mtype])
		if mtype == 3 and r.ok:
			var kinds := {}
			for s in theirs:
				for c in s: kinds[nav.passable_extent(Vector2i(c[0], c[1]), 1, 0)] = true
			if kinds.size() == 2: crossings += 1
	check(crossings > 0, "%s: amphibious orders cross the coast (%d)" % [slug, crossings])
	if slug == "four-bridges": group_checks(nav)
	print("%s: %d / %d / %d orders of types 0 / 2 / 3 match, %d amphibious coast crossings, %d ms" % [slug, counts[0], counts[2],
		counts[3], crossings, Time.get_ticks_msec() - started])

## One right-click for a mixed selection (0x530870, Read): the slots come from the formation table (Emulated, 0x530f80) and
## each unit plans its own order with its own type, so on the Four Bridges centre lake the land unit stops at the shore,
## the water and amphibious units enter the lake.
func group_checks(nav: RefCounted):
	var entries := [{"id": 0, "cell": Vector2i(50, 68), "speed": 8, "mtype": 0}, {"id": 1, "cell": Vector2i(51, 69), "speed": 8, "mtype": 3},
		{"id": 2, "cell": Vector2i(68, 66), "speed": 8, "mtype": 2}]
	var clicked := Vector2i(64, 66)
	var group: Dictionary = nav.group_orders(entries, clicked, 4, true)
	check(group.ok and group.orders.size() == 3, "mixed group: three orders")
	var ends := []
	for i in 3:
		var order: Dictionary = group.orders[i]
		var route: Dictionary = nav.route_cells(entries[i].cell, order.cell, 1, int(entries[i].mtype))
		var cells: Array = []
		for s in route.get("segments", []): cells.append_array(s)
		ends.append(cells[-1] if not cells.is_empty() else entries[i].cell)
		check(route.ok, "mixed group: unit %d (type %d) has a route to its slot %s" % [i, entries[i].mtype, order.cell])
	check(nav.passable_extent(ends[0], 1, 0) and not nav.passable_extent(ends[0], 1, 2), "mixed group: the land unit stops on land (%s)" % ends[0])
	check(nav.passable_extent(ends[1], 1, 2), "mixed group: the amphibious unit ends in the lake (%s)" % ends[1])
	check(nav.passable_extent(ends[2], 1, 2), "mixed group: the water unit ends in the lake (%s)" % ends[2])

static func hex_bytes(text: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(text.length() / 2)
	for i in out.size():
		out[i] = text.substr(i * 2, 2).hex_to_int()
	return out
