extends RefCounted
## main.gd's construction and production (R-1 split of main.gd, no behaviour change): the production modules, unit
## and building markers, building placement, build walks and pending builds, the production queue, the placement
## ghost. The state stays on the scene (main.gd); `main` is the scene.

const MainScript = preload("res://battle/main.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Economy = preload("res://simulation/economy.gd")
const Rules = preload("res://simulation/production_rules.gd")
const Production = preload("res://simulation/production.gd")
const Placement = preload("res://simulation/placement.gd")
const BuildingMarker = preload("res://battle/building_marker.gd")
const Encounters = preload("res://simulation/encounters.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

# ------------------------------------------------------------------ milestone 7: construction and production

func reset_production():
	for node in main.building_nodes.values(): node.queue_free()
	main.building_nodes.clear()
	if not main.navigator.building_cells.is_empty():
		main.navigator.building_cells.clear()
		main.navigator.build_sectors()
	main.economy = Economy.new(0)
	main.economy.add_player(0, MainScript.FIXTURE_RESOURCES.duplicate())
	make_production()
	main.economy.add_player(1, MainScript.FIXTURE_RESOURCES.duplicate())
	main.setup_combat()
	main.pending_builds.clear()
	main.build_mode = ""
	main.rally_mode = false

func make_production():
	main.production = Production.new(Rules.new(), main.economy, main.navigator)
	main.production.builder_hidden.connect(main._on_builder_hidden)
	main.production.builder_released.connect(main._on_builder_released)
	main.production.unit_ready.connect(main._on_unit_ready)
	main.production.mercenary_completed.connect(main._on_mercenary_completed)
	main.production.building_placed.connect(main._on_building_placed)
	main.production.building_destroyed.connect(main._on_building_destroyed)
	main.production.building_completed.connect(func(id): main.last_message = "%s completed." % main.production.building(id).definition.display_name)
	main.production.building_upgraded.connect(func(id, previous): main.last_message = "Keep upgraded: %s -> %s." % [previous, main.production.building(id).original_type_id])
	main.production.notice.connect(func(text): main.last_message = text)
	main.economy.research_level = func(player, id): return main.production.research_level(player, id)   # 0x531f10 Income research
	main.economy.other_income = func(player): return main.other_income(player)                        # B4-1 (E3): units and the Magic Well
	main.production.building_completed.connect(main._register_player_tower)

## Milestone 13: a completed building with an attack (BUI +0x38 > 0: the Knights' tower BWTC) shoots like the map towers
## of milestone 9 (0x52d0d0 / 0x52c250), from its footprint centre (the placement anchor, 0x524450).
func _register_player_tower(id: int):
	var b = main.production.building(id)
	if b == null or main.combat == null: return
	var w: int = int(b.definition.footprint[0])
	var h: int = int(b.definition.footprint[1])
	main.combat.register_tower(b, Vector2i(b.left + ((w - 1) >> 1), b.top + ((h - 1) >> 1)))

# Test harness only (button "Production fixture"): a finished Keep level 1 away from the six
# Swordsmen, one Peasant and one hero builder. The original match start is not recovered.
func spawn_production_fixture():
	if not main.production.buildings.is_empty(): return
	var site := find_site("BKK0", Vector2i(8, 50))
	var anchor: Vector2i = Placement.anchor(main.production.rules.definition("BKK0"), site)
	var keep = main.production.add_completed(0, "BKK0", anchor.x, anchor.y)
	add_marker(keep)
	main.selected_building_id = keep.entity_id
	for type_id in ["AHBX", "AHHX"]:
		var cell: Vector2i = main.navigator.free_cell_near(main.production.spawn_target(keep) + Vector2i(1 if type_id == "AHBX" else 3, 1))
		var unit = add_unit(type_id, cell)
		if type_id == "AHBX": main.production.register_unit(unit.unit_id, type_id, 0)

func find_site(type_id: String, wanted: Vector2i) -> Vector2i:
	var definition: Dictionary = main.production.rules.definition(type_id)
	for radius in range(0, 40):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var cell := wanted + Vector2i(dx, dy)
				if Placement.check(main.navigator, definition, cell).ok: return cell
	return wanted

func add_unit(type_id: String, cell: Vector2i, owner: int = 0):
	var unit = UnitAgent.new()
	unit.owner_id = owner
	unit.unit_id = main.units.size()
	unit.type_id = type_id
	unit.base_speed = int(main.unit_definition(type_id).base_speed)
	var fp = main.unit_definition(type_id).get("footprint", [1, 1])
	unit.extent = maxi(1, int(fp[0])) if fp is Array and not fp.is_empty() else 1
	unit.flying = int(main.unit_definition(type_id).get("movement_type", 0)) == 1
	if unit.flying: unit.extent = 1
	unit.movement_type = int(main.unit_definition(type_id).get("movement_type", 0))   # M-3: water / amphibious cell checks
	unit.position = main.navigator.center(cell)
	unit.navigator = main.navigator
	unit.modulate = {"AHBX": Color(1.0, 0.85, 0.5), "AHMX": Color(0.6, 0.85, 1.0), "AHHX": Color(1.0, 0.6, 0.6)}.get(type_id, Color.WHITE)
	if owner != 0: unit.modulate = Color(1.0, 0.72, 0.72)
	if owner == Encounters.NEUTRAL: unit.modulate = Color(0.95, 0.85, 0.55) if UnitAI.is_animal(type_id) else Color(0.75, 0.95, 0.6)
	main.add_child(unit)
	main.units.append(unit)
	unit.sync_cell()
	if main.combat != null: main.register_combatant(unit)
	return unit

func add_marker(state: RefCounted):
	var marker = BuildingMarker.new()
	marker.configure(state)
	main.add_child(marker)
	main.building_nodes[state.entity_id] = marker

func selected_building():
	return main.production.building(main.selected_building_id) if main.production != null else null

func select_building_at(point: Vector2):
	var cell: Vector2i = main.collision.world_cell(point)
	main.selected_building_id = -1
	for id in main.production.buildings:
		if main.production.buildings[id].cell_rect().has_point(cell): main.selected_building_id = id
	for id in main.building_nodes: main.building_nodes[id].selected = id == main.selected_building_id

func arm_build(type_id: String):
	main.build_mode = type_id
	main.rally_mode = false
	main.last_message = "Click a site for %s; the selected Peasant or hero walks there and builds (right-click cancels)." % type_id

func selected_builder():
	for unit in (main.own_selected() if main.normal_play else main.selected_units()):
		if is_builder(unit) and not unit.inside_building: return unit
	return null

## 0x523e10: heroes (power 10) and units whose ARM has an ability slot of id 50 build (milestone 11a: any race).
func is_builder(unit) -> bool:
	return is_hero_unit(unit) or main.production.rules.builder_power(unit.type_id) > 0

func is_hero_unit(unit) -> bool:
	return main.combat != null and main.combat.fighters.has(unit.unit_id) and bool(main.combat.fighters[unit.unit_id].hero)

func map_click(point: Vector2):
	var cell: Vector2i = main.collision.world_cell(point)
	if main.rally_mode:
		main.rally_mode = false
		var b = selected_building()
		if b != null:
			main.production.set_rally(b.entity_id, cell)
			main.last_message = "Rally point of %s set to %s." % [b.original_type_id, cell]
		return
	var type_id := main.build_mode
	main.build_mode = ""
	var builder = selected_builder()
	if builder == null:
		main.last_message = "Select a Peasant or the hero first."
		return
	start_build_walk(builder, type_id, cell)

## 0x524230 mode 0: the builder walks to the site and builds there on arrival (resolve_pending_builds).
func start_build_walk(builder, type_id: String, cell: Vector2i) -> bool:
	builder.sync_cell()
	var check: Dictionary = main.production.can_place(0, type_id, cell, builder)
	if not check.ok:
		main.last_message = "Cannot build %s there: %s." % [type_id, check.reason]
		main.build_order.emit(builder.unit_id, false)
		return false
	# Walk to the site; the builder stands on the footprint, which the original check allows (0x42c8e0).
	builder.give_order({"kind": "move", "target": main.navigator.center(cell), "requested": main.navigator.center(cell), "group": 0,
		"speed": builder.base_speed, "individual": true, "build": true}, "replace")
	if main.combat != null and main.combat.fighters.has(builder.unit_id): main.combat.note_move(builder.unit_id, cell)   # the scripts see a player order
	main.pending_builds[builder.unit_id] = {"type": type_id, "cell": cell}
	main.build_order.emit(builder.unit_id, true)
	main.last_message = "%s walks to %s to build %s." % [builder.type_id, cell, type_id]
	return true

func resolve_pending_builds():
	for id in main.pending_builds.keys():
		var unit = main.units[id]
		var job: Dictionary = main.pending_builds[id]
		# A builder killed on the way never arrives: 0x5210b0 stops it (orders cleared), which must not read as an arrival.
		if unit.dying or unit.removed:
			main.pending_builds.erase(id)
			main.build_results[id] = "failed"
			main.unit_commands.wall_queues.erase(id)
			continue
		if not unit.orders.is_empty():
			if not unit.orders[0].get("build", false):
				main.pending_builds.erase(id) # a new order replaced the walk
				main.build_results[id] = "failed"
				main.unit_commands.wall_queues.erase(id)   # and the wall segments appended behind it
			continue
		if unit.in_step: continue
		main.pending_builds.erase(id)
		unit.sync_cell()
		var result: Dictionary = main.production.place_building(unit.owner_id, job.type, job.cell, main.game_ms(), unit.unit_id, unit.type_id, unit.cell, unit)
		main.build_results[id] = "placed" if result.ok else "failed"
		if unit.owner_id == main.local_player:
			main.last_message = "Building started: %s." % job.type if result.ok else "Cannot build %s: %s." % [job.type, result.reason]
			if not result.ok: main.build_order.emit(unit.unit_id, false)   # 0x524450: the placement check failed at the site
		if not result.ok: main.next_wall_segment(unit)                 # the next appended build order runs

func _on_builder_hidden(id: int):
	var unit = main.units[id]
	main.navigator.release(unit, unit.cell)
	unit.inside_building = true
	unit.selected = false
	unit.visible = false
	unit.stop()
	main.pending_builds.erase(id)
	# 0x5284f0: a unit inside a building gets +0x30, which 0x51a1c0 rejects (it does not count for Standard Victory).
	if main.combat != null and main.combat.fighters.has(id): main.combat.fighters[id].flag_30 = true

func _on_builder_released(id: int, cell: Vector2i):
	var unit = main.units[id]
	unit.inside_building = false
	unit.visible = true
	if main.combat != null and main.combat.fighters.has(id): main.combat.fighters[id].flag_30 = false
	unit.position = main.navigator.center(cell)
	unit.cell = Vector2i(-1, -1)
	unit.sync_cell()
	unit.advance(0)
	main.next_wall_segment(unit)

## A started building is selected for the player who ordered it. The signal comes for every side: selecting whatever
## was placed put a computer player's new building in the local player's HUD each time one of its builders started one.
func _on_building_placed(id: int):
	var b = main.production.building(id)
	add_marker(b)
	if main.normal_play and int(b.owner) != main.local_player: return
	main.selected_building_id = id
	for key in main.building_nodes: main.building_nodes[key].selected = key == id

func _on_building_destroyed(id: int):
	if main.building_nodes.has(id):
		main.building_nodes[id].queue_free()
		main.building_nodes.erase(id)
	if main.selected_building_id == id: main.selected_building_id = -1
	main.last_message = "The unfinished building decayed and collapsed."

func _on_unit_ready(info: Dictionary):
	var unit = add_unit(info.item, info.cell, int(info.get("owner", 0)))
	info.unit_id = unit.unit_id
	# Milestone 13 / B2-1 / R-1 (Read, the training job 0x52c728, like 0x4a5780 for message 0xfd): a trained unit's message
	# carries 10 XP after Training (PTRN), the table 0x40b0e0[PLOX level], 5 for Knight cavalry after Order of the Rose (PORO).
	# The per-player term 0x7495d8 is scenario data (Open). A unit sent straight as message 0xfa (Slavehorde, Foreign
	# Mercenaries, "direct") has none of these. Then 0x4a49e0 adds the starting experience 0x557d90 to both (R-1).
	if main.combat != null and main.combat.fighters.has(unit.unit_id):
		var xp := 0
		if not info.get("direct", false): xp = main.combat.creation_gain(unit.owner_id, String(info.item))
		main.combat.creation_experience(main.combat.fighters[unit.unit_id], xp, not info.get("no_start", false))   # B3-1: +0x3b = 1 skips 0x557d90
	main.last_message = "%s created at %s." % [main.production.rules.definition(info.item).display_name, info.cell]
	if info.rally.x >= 0:
		var target: Vector2 = main.navigator.center(info.rally)
		unit.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": unit.base_speed, "individual": true}, "replace")
		# Playtest 2026-11-11: the rally move is the unit's current order like any move (0x530870), so the walk steps carry
		# its guard point along (unit_ai.on_step). Without it the guard point stayed at the spawn cell and the attitude
		# script walked the unit back after a step or two. Whether the original's rally move carries +0x1c is Open (0 here).
		if main.combat != null and main.combat.fighters.has(unit.unit_id): main.combat.note_move(unit.unit_id, info.rally)

func queue_item(item: String):
	var b = selected_building()
	if b == null:
		main.last_message = "Select a finished building first (click it)."
		return
	var result: Dictionary = main.production.enqueue(b.entity_id, item, main.game_ms())
	main.last_message = "%s queued at %s." % [item, b.original_type_id] if result.ok else "Cannot queue %s: %s." % [item, result.reason]

func cancel_job():
	var b = selected_building()
	# 0x4d0aa0: the Cancel button also stops a Keep conversion (0x52fbc0).
	if b != null and b.keep_converting and main.conversions != null:
		main.conversions.cancel_keep(b)
		main.last_message = "Conversion cancelled."
		return
	if b != null and main.production.cancel_slot(b.entity_id, 0, main.game_ms()): main.last_message = "Current job cancelled; its price is refunded."

func cancel_all_jobs():
	var b = selected_building()
	if b != null and main.production.cancel_all(b.entity_id): main.last_message = "All jobs cancelled; the running job is refunded."

func release_builder():
	var b = selected_building()
	if b != null and main.production.release_builder(b.entity_id, main.game_ms()): main.last_message = "Builder released; the building will decay until someone resumes it."

func toggle_repeat():
	var b = selected_building()
	if b != null:
		b.repeat = not b.repeat
		main.last_message = "Repeat production %s." % ("on" if b.repeat else "off")

func production_text() -> String:
	var stock: Array = main.economy.resources(0)
	var pop: Dictionary = main.production.population(0)
	var text := "Gold %d · Metal %d · Crystal %d · Stone %d (limit %d) · command %d/%d" % [stock[0], stock[1], stock[2], stock[3], main.economy.capacity(0)[0], pop.current, pop.maximum]
	var b = selected_building()
	if b != null:
		text += " · selected %s" % b.original_type_id
		if b.constructing: text += " (building %d%%, hp %d/%d)" % [b.progress, b.hit_points, b.max_hit_points]
		elif b.has_job(): text += " (%s %d%%, queued: %s)" % [b.job_item if b.job_item != "" else "pending", b.job_progress, ", ".join(b.queue)]
		if b.repeat: text += " · repeat"
	return text

## 0x4965d0 (placement modes 8 / 9): the building's own sheet under the cursor (Read for the call: it loads the sheet of
## the type's 4CC). The tint (valid / invalid) is Open: the rebuild draws it at 60 % and reddens an invalid site
## (Provisional); the footprint cells are drawn only in the fixture harness.
func update_ghost():
	if main.build_mode == "" or main.production == null:
		main.ghost.visible = false
		return
	var definition: Dictionary = main.production.rules.definition(main.build_mode)
	var record: Dictionary = preload("res://core/art_data.gd").building_sheet(main.build_mode, 0)
	if definition.is_empty() or record.is_empty():
		main.ghost.visible = false
		return
	var cell: Vector2i = main.collision.world_cell(main.get_global_mouse_position())
	var builder = selected_builder()
	var check: Dictionary = Placement.check(main.navigator, definition, cell, builder)
	var ok: bool = check.ok and main.production.can_place(main.local_player, main.build_mode, cell, builder).ok
	var width: int = definition.footprint[0]
	var ArtDataScript = preload("res://core/art_data.gd")
	main.ghost.visible = true
	main.ghost.centered = false
	main.ghost.region_enabled = true
	main.ghost.texture = ArtDataScript.texture(record.texture)
	main.ghost.region_rect = ArtDataScript.frame_rect(record, 0, 0)
	main.ghost.offset = ArtDataScript.offset(record)
	main.ghost.material = ArtDataScript.team_material(record, ArtDataScript.player_colour(main.local_player))
	main.ghost.position = Vector2((int(check.left) + ((width - 1) >> 1)) * 32 + 16, int(check.top) * 24 + 12)
	main.ghost.modulate = Color(1, 1, 1, 0.6) if ok else Color(1, 0.35, 0.35, 0.6)

func draw_build_ghost():
	if main.build_mode == "" or main.production == null or main.normal_play: return
	var definition: Dictionary = main.production.rules.definition(main.build_mode)
	var cell: Vector2i = main.collision.world_cell(main.get_global_mouse_position())
	var builder = selected_builder()
	var check: Dictionary = Placement.check(main.navigator, definition, cell, builder)
	var color := Color(0.3, 0.9, 0.4, 0.45) if check.ok and main.production.can_place(0, main.build_mode, cell, builder).ok else Color(0.95, 0.3, 0.3, 0.45)
	for row in range(int(definition.footprint[1])):
		for col in range(int(definition.footprint[0])):
			if Placement.solid(definition, col, row): main.draw_rect(Rect2((check.left + col) * 32, (check.top + row) * 24, 32, 24), color)

