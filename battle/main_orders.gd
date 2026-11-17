extends RefCounted
## main.gd's selection, mouse and keyboard orders (R-1 split of main.gd, no behaviour change): the selection, clicks and
## boxes, the cursor's context, move / attack / patrol / guard orders, wall drag, garrisons, repair, control groups and
## alerts. The state stays on the scene (main.gd); `main` is the scene.

const MainScript = preload("res://battle/main.gd")
const Selection = preload("res://battle/selection.gd")
const Placement = preload("res://simulation/placement.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const UnitCommands = preload("res://simulation/unit_commands.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

func selected_units() -> Array:
	return main.units.filter(func(unit): return unit.selected)

## The selected units the local player commands (an enemy can be selected for information only, 0x421190 mask 0x9e03).
func own_selected() -> Array:
	return main.units.filter(func(unit): return unit.selected and unit.owner_id == main.local_player and not unit.dying)

## The selection head (0x531720): the first selected object; a selected building when no unit is selected.
func selection_head():
	for unit in main.units:
		if unit.selected: return unit
	return main.selected_building()

func head_is_own_unit() -> bool:
	var head = selection_head()
	return head != null and head is Node2D and head.get("unit_id") != null and int(head.owner_id) == main.local_player

## Fixture harness "Select all" (Ctrl+A in normal play is select_nearest, 0x427fb0 case 0x27).
func select_all():
	for unit in main.units:
		unit.selected = unit.owner_id == main.local_player or not main.normal_play
		unit.queue_redraw()

func center_selection():
	var selected := selected_units()
	if selected.is_empty(): selected = main.units
	var point := Vector2.ZERO
	for unit in selected: point += unit.position
	main.centre_view(point / selected.size())

func stop_selected():
	for unit in own_selected() if main.normal_play else selected_units():
		unit.stop()
		main.patrols.erase(unit.unit_id)
		main.guards.erase(unit.unit_id)
		if main.combat != null: main.combat.order_stop(unit.unit_id)
		main.cancel_conversion(unit)
	main.last_message = "Selected movement queues cleared."

# 0x530870: centroid of the selected units' current cells, facing, formation slots and the
# slowest-unit speed; each unit receives its own move order (0x51d6b0). Selection-list order and
# the leader field (+0x9e) are not recovered; the units array order and its first unit stand in.
func issue_move(requested: Vector2, append: bool = false, prepend: bool = false, individual: bool = false, extra: Dictionary = {}, only: Array = []) -> Dictionary:
	var selected: Array = only if not only.is_empty() else (own_selected() if main.normal_play else selected_units())
	if selected.is_empty():
		main.last_message = "No units selected."
		return {"assignments": [], "errors": [main.last_message]}
	var entries: Array = []
	for unit in selected:
		if not append and not prepend:
			main.patrols.erase(unit.unit_id)
			main.guards.erase(unit.unit_id)
		if not append and not prepend and main.combat != null: main.combat.order_stop(unit.unit_id)
		if not append and not prepend: main.cancel_conversion(unit)   # a replacing order clears order 7 / a queued 0xc
		unit.sync_cell()
		entries.append({"id":unit.unit_id, "cell":unit.cell, "speed":unit.base_speed, "extent":unit.extent, "flying":unit.flying, "mtype":unit.movement_type})
	var clicked: Vector2i = main.collision.world_cell(requested)
	if not extra.has("assault") and not extra.has("attack_move"): main.forget_modern_orders(selected.map(func(u): return u.unit_id))
	main.command_number += 1
	# Modern march (F1, navigation.gd): the same slots, facing and speed, plus one shared route the group keeps together on.
	var group: Dictionary = main.navigator.march_orders(entries, clicked, selected[0].facing, true, main.command_number) \
		if main.navigator.improved and not individual and not append and not prepend \
		else main.navigator.group_orders(entries, clicked, selected[0].facing, not individual)
	main.last_requested = requested
	var mode := "prepend" if prepend else ("append" if append else "replace")
	var assignments: Array = []
	var errors: Array = []
	for order in group.orders:
		var unit = main.units[order.id]
		unit.facing = group.facing
		var target: Vector2 = main.navigator.center(order.cell)
		var move := {"kind":"move", "target":target, "requested":requested, "group":main.command_number,
			"speed":order.speed, "individual":individual}
		for key in ["cells", "marks", "march"]:
			if order.has(key): move[key] = order[key]
		move.merge(extra, true)
		if main.combat != null and main.combat.fighters.has(order.id):   # G-2: the move's place in the unit's chain beside its attacks
			var f = main.combat.fighters[order.id]
			if append and (f.order != null or not f.get("queue", []).is_empty()):
				main.combat.queue_move(order.id, move)
				assignments.append({"id":order.id, "target":target, "cell":order.cell})
				continue
			if prepend: main.combat.defer_attack(order.id)
		unit.give_order(move, mode)
		if main.combat != null and main.combat.fighters.has(order.id): main.combat.note_move(order.id, order.cell, move)   # the scripts see a player order
		assignments.append({"id":order.id, "target":target, "cell":order.cell})
	if not group.ok: errors.append("Group of %d exceeds the 32-slot formation table" % selected.size())
	var speed_text := "individual speeds" if individual else "group speed %d" % int(group.orders[0].speed if not group.orders.is_empty() else 0)
	main.last_message = "%s: %d/%d units; %s; facing %d.%s" % [mode.capitalize(), assignments.size(), selected.size(), speed_text, group.facing, " " + "; ".join(errors) if not errors.is_empty() else ""]
	main.queue_redraw()
	return {"assignments": assignments, "errors": errors, "facing": group.facing}

func route_demo():
	main.reset_fixture()
	var start := main.navigator.center(Vector2i(6,51))
	# Fixture placement only: the six nearest free cells around the start, row by row.
	var free: Array[Vector2i] = []
	for radius in range(4):
		for y in range(51 - radius, 52 + radius):
			for x in range(6 - radius, 7 + radius):
				var cell := Vector2i(x, y)
				if not free.has(cell) and main.navigator.enterable_static(cell): free.append(cell)
	for i in range(MainScript.SPAWN_CELLS.size()):
		main.units[i].position = main.navigator.center(free[i])
		main.units[i].sync_cell()
	issue_move(main.navigator.center(Vector2i(21,51)))
	main.camera.position = Vector2(640, 1236)
	main.last_message = "Structure detour fixture: units route around the source mine mask with the ported original search and formation slots."

func finish_selection(event: InputEventMouseButton):
	if main.suppress_release:
		main.suppress_release = false
		return
	if not main.drag_active: return
	main.drag_active = false
	main.drag_end = event.position
	var mods := MainScript.mods_of(event)
	var canvas := main.get_canvas_transform()
	if Selection.is_box(main.drag_start, main.drag_end):
		box_release(Selection.world_box(main.drag_start, main.drag_end, canvas), mods)
	else:
		click_release(canvas.affine_inverse() * main.drag_end, mods)
	var picked: Array = (own_selected() if main.normal_play else selected_units()).map(func(u): return u.unit_id)
	if not picked.is_empty(): main.units_selected.emit(picked)
	main.selection_layer.queue_redraw()
	main.refresh_status()

func set_building_selection(id: int):
	main.selected_building_id = id
	main.selected_mine_id = -1
	for b in main.building_nodes: main.building_nodes[b].selected = b == id

## Select one object alone (command 1) or add a unit (command 0x13).
func pick_object(object, add_it: bool = false):
	if object == null: return
	if object is Node2D and object.get("unit_id") != null:
		set_building_selection(-1)
		if add_it: Selection.add(object)
		else: Selection.select_only(main.units, object)
	else:
		Selection.clear(main.units)
		set_building_selection(object.entity_id)
		main.building_selected.emit(object.entity_id)

## The own unit clicked again within 8 ticks (0x608470): the own units of its class in the view (0x531dd0).
func repeat_click(unit) -> bool:
	var now := Time.get_ticks_msec()
	if unit == main.last_click_object and now - main.last_click_ms < Selection.DOUBLE_TICKS * Selection.TICK_MS:
		main.last_click_ms = -100000                   # 0x608470 = 1000
		set_building_selection(-1)
		Selection.select_type_in(main.units, String(unit.type_id), main.view_rect(), main.local_player)
		return true
	main.last_click_object = unit
	main.last_click_ms = now
	return false

func click_release(point: Vector2, mods: Dictionary):
	if not main.normal_play:                           # fixture harness: every unit stays pickable (test fixtures, not original)
		var chosen = Selection.hit(main.units, point)
		if chosen != null: pick_object(chosen, mods.shift)
		else:
			Selection.clear(main.units)
			main.select_building_at(point)
			if main.selected_building_id >= 0: main.building_selected.emit(main.selected_building_id)
		return
	var own_unit = Selection.hit_where(main.units, point, func(u): return u.owner_id == main.local_player)
	if own_unit != null:
		if repeat_click(own_unit): return
		pick_object(own_unit, mods.shift and head_is_own_unit())
		return
	var b = building_at(point, true)
	if b != null:
		main.last_click_object = b
		main.last_click_ms = Time.get_ticks_msec()
		pick_object(b)
		return
	var other = Selection.hit_where(main.units, point, func(u): return u.owner_id != main.local_player and u.visible)
	if other == null: other = building_at(point, false)
	if other != null:
		main.last_click_ms = Time.get_ticks_msec()
		main.last_click_object = other
		pick_object(other)
		return
	# Playtest 2026-11-11: a mine is a building in the original (BLDH), so a click selects it and the info area shows its
	# reserve and workers (0x4d7710's resource-building branch, game_hud.gd draw_mine_info).
	var mine_cell: Vector2i = main.collision.world_cell(point)
	if main.mines != null and main.mines.mine_at(mine_cell) >= 0 and (main.visibility == null or main.visibility.is_explored(main.local_player, mine_cell)):
		Selection.clear(main.units)
		set_building_selection(-1)
		main.selected_mine_id = main.mines.mine_at(mine_cell)
		return
	Selection.clear(main.units)                       # command 5
	set_building_selection(-1)

func box_release(box: Rect2, mods: Dictionary):
	if not main.normal_play:
		_fixture_box(box, mods.shift)
		return
	var found := Selection.in_box(main.units, box, func(u): return u.owner_id == main.local_player)
	if found.size() == 1:
		if repeat_click(found[0]): return
		pick_object(found[0], mods.shift and head_is_own_unit())
		return
	var mode := 2 if mods.alt else (1 if mods.ctrl else 0)
	var adding: bool = mods.shift and head_is_own_unit()
	var picked := 0
	if adding: picked = Selection.add_box(main.units, box, main.local_player, mode)
	else:
		set_building_selection(-1)
		picked = Selection.select_box(main.units, box, main.local_player, mode)
	if picked > 0 or adding: return
	# 0x5319f0 with nothing own in the box: an own building (0x9102), else any other object (0x9603).
	var first: Vector2i = main.collision.world_cell(box.position)
	var cells := Rect2i(first, main.collision.world_cell(box.end) - first + Vector2i.ONE)
	if main.production != null:
		for id in main.production.buildings:
			var bb = main.production.buildings[id]
			if int(bb.owner) == main.local_player and bb.hit_points > 0 and bb.cell_rect().intersects(cells):
				pick_object(bb)
				return
	var others := Selection.in_box(main.units, box, func(u): return u.owner_id != main.local_player and u.visible)
	if not others.is_empty():
		pick_object(others[0])
		return
	if main.production != null:
		for id in main.production.buildings:
			var ob = main.production.buildings[id]
			if int(ob.owner) != main.local_player and ob.hit_points > 0 and ob.cell_rect().intersects(cells) and main.visibility.is_explored(main.local_player, ob.cell_rect().position):
				pick_object(ob)
				return

func _fixture_box(box: Rect2, additive: bool):
	for unit in main.units:
		var inside: bool = Selection.pickable(unit) and box.intersects(unit.hit_rect(), true)
		unit.selected = (unit.selected or inside) if additive else inside
		unit.queue_redraw()

## The building under a point (own, or another player's where explored). Footprint cells stand in for the original's
## sprite-pixel test (0x548360 vtable +0x44).
func building_at(point: Vector2, own_only: bool):
	if main.production == null: return null
	var cell: Vector2i = main.collision.world_cell(point)
	for id in main.production.buildings:
		var b = main.production.buildings[id]
		if b.hit_points <= 0 or not b.cell_rect().has_point(cell): continue
		if own_only and int(b.owner) != main.local_player: continue
		if not own_only and (int(b.owner) == main.local_player or (main.visibility != null and not main.visibility.is_explored(main.local_player, cell))): continue
		return b
	return null

## The object under a point for orders, the cursor and the hover info: {kind "unit" / "building" / "mine", object, own,
## allied, fogged}. Others' units only where visible (0x548360 masks 0x8000 / 0x10000), buildings where explored.
func hover_object(point: Vector2) -> Dictionary:
	var cell: Vector2i = main.collision.world_cell(point)
	if main.visibility != null and main.normal_play and not main.visibility.is_explored(main.local_player, cell): return {}   # bVar4 of 0x420390
	var u = Selection.hit_where(main.units, point, func(x): return x.owner_id == main.local_player or x.visible)
	if u != null:
		return {"kind": "unit", "object": u, "own": u.owner_id == main.local_player, "allied": false, "fogged": false}
	if main.production != null:
		for id in main.production.buildings:
			var b = main.production.buildings[id]
			if b.hit_points > 0 and b.cell_rect().has_point(cell):
				var fogged: bool = int(b.owner) != main.local_player and main.visibility != null and not main.visibility.is_visible(main.local_player, cell)
				return {"kind": "building", "object": b, "own": int(b.owner) == main.local_player, "allied": false, "fogged": fogged}
	if main.mines != null and main.mines.mine_at(cell) >= 0:
		var m: int = main.mines.mine_at(cell)
		return {"kind": "mine", "object": m, "own": main.mines.owner_of(m) == main.local_player, "allied": false, "fogged": false}
	return {}

## 0x420390 inputs for a window point.
func cursor_context(screen: Vector2) -> Dictionary:
	var ctx := {"mode": cursor_mode(), "dragging": main.drag_active and main.drag_start != main.drag_end}
	if main.hud != null and (main.hud.over_panel(main.hud.to_virtual(screen)) or main.hud.dialog != ""):
		ctx.panel = true
		ctx.pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		main.hover_info = {}
		return ctx
	var head = selection_head()
	if head != null:
		var is_unit: bool = head is Node2D and head.get("unit_id") != null
		var tower := false
		if not is_unit and main.production != null:
			# G-4: BUI damage > 0 (0x420390 reads 0x69778c); the definition key "attack" P-2 tested does not exist.
			tower = Selection.tower_head(String(main.production.rules.definition(String(head.original_type_id)).get("raw_hex", "")))
		ctx.head = "unit" if is_unit else ("tower" if tower else "building")
		ctx.head_own = int(head.owner_id if is_unit else head.owner) == main.local_player
		ctx.head_multi = own_selected().size() > 1
		ctx.head_hero = is_unit and head.unit_id == main.hero_unit_id
	var world: Vector2 = main.get_canvas_transform().affine_inverse() * screen
	main.hover_info = hover_object(world)
	if not main.hover_info.is_empty():
		ctx.hover = "unit" if main.hover_info.kind == "unit" else "building"
		ctx.hover_own = main.hover_info.own
		ctx.hover_fogged = main.hover_info.fogged
		if main.hover_info.kind == "unit": ctx.hover_flying = bool(main.hover_info.object.flying)
		if head != null and ctx.get("head", "") == "unit" and main.hover_info.own: ctx.hover_enter = can_enter(head, main.hover_info) or can_garrison_into(head, main.hover_info)
		# Q-2: 0x420390 gives cursor 0xc when the head is the player's hero and the hovered building is a quest site
		# (0x52ed90, Building.cfg searchable) with Quests on, or a shop (0x5877e0, Building.cfg +0x7f); the owner is not tested.
		if ctx.get("head_hero", false) and main.hover_info.kind == "building" and main.encounters != null:
			var code := String(main.hover_info.object.original_type_id)
			ctx.pickup = (main.encounters.quests_enabled and main.encounters.is_quest_site(code)) or main.encounters.is_shop(code)
	return ctx

## The target mode as 0x420390 reads it: build placement is mode 8, the rally click mode 7.
func cursor_mode() -> int:
	if main.build_mode != "": return 8
	if main.rally_mode: return 7
	return main.target_mode

## 0x523e10 / 0x523e70: the head unit can resume an unfinished own building (a builder) or enter an own mine (a miner).
func can_enter(unit, hovered: Dictionary) -> bool:
	if hovered.kind == "building":
		var b = hovered.object
		return b.constructing and b.builder_id < 0 and main.is_builder(unit)
	if hovered.kind == "mine":
		return main.mines != null and not main.is_hero_unit(unit) and main.production.rules.can_mine(unit.type_id) and main.mines.owner_of(int(hovered.object)) == unit.owner_id
	return false

## 0x52db10(1) + 0x51c240 for the cursor: the head could garrison the hovered own tower.
func can_garrison_into(unit, hovered: Dictionary) -> bool:
	if hovered.kind != "building" or not main.unit_commands.can_take(hovered.object, main.production.rules): return false
	return UnitCommands.can_garrison(unit.type_id, main.production.rules.definition(unit.type_id).get("footprint", []), main.is_builder(unit), main.is_hero_unit(unit), UnitAI.is_animal(unit.type_id, false))

func update_cursor():
	if main.cursor == null: return
	main.cursor.set_index(Selection.cursor_index(cursor_context(main.get_viewport().get_mouse_position())))

## Right-click contexts (0x421190 event 1 without the left button, mode 0), in the translator's order.
func right_click(point: Vector2, mods: Dictionary):
	var hovered := hover_object(point)
	var head = selection_head()
	var head_unit := head_is_own_unit()
	# An own building with production, unless the head is a builder that can resume it: select it and open the
	# production dialog (command 0x30 -> 0x4d0940).
	if hovered.get("kind", "") == "building" and hovered.own:
		var b = hovered.object
		var resumable: bool = head_unit and b.constructing and b.builder_id < 0 and main.is_builder(head)
		if not resumable and not b.constructing and not main.production.menu_for(b).is_empty():
			pick_object(b)
			if main.hud != null: main.hud.open_production(b)
			return
	# The head is an own building that trains units: its rally point (command 0xc).
	if head != null and not head_unit and not (head is Node2D) and int(head.owner) == main.local_player:
		if main.production.menu_for(head).any(func(m): return String(m.id).begins_with("A")):
			var cell: Vector2i = main.collision.world_cell(point)
			if hovered.get("kind", "") == "building" and hovered.own: cell = hovered.object.cell_rect().position
			main.production.set_rally(head.entity_id, cell)
			main.arm_order_marker()                    # P-2: 0x52e6b0 is followed by 0x49c150
		return
	if not head_unit: return
	var ids: Array = own_selected().map(func(u): return u.unit_id)
	if main.order_site_visit(head, hovered, point, mods):        # S-2: the hero's quest site and shop contexts
		main.units_ordered.emit(ids)
		return
	if hovered.is_empty() or hovered.allied:
		order_move(point, mods)
	elif hovered.kind == "mine":
		main.mine_order(int(hovered.object))           # milestone 12 convenience (labelled): enter or convert the mine
	elif hovered.own:
		if hovered.kind == "building" and can_enter(head, hovered):
			resume_building(hovered.object)
		elif hovered.kind == "building" and main.unit_commands.can_take(hovered.object, main.production.rules) and order_garrison(hovered.object, point, mods) > 0:
			pass                                  # 0x2a / 0x2b: garrison a tower (order 0x12); there is no repair context (Read)
		else:
			order_move(point, mods)
	elif main.combat != null:
		var target := {"kind": "unit", "id": hovered.object.unit_id} if hovered.kind == "unit" else {"kind": "building", "id": hovered.object.entity_id}
		main.issue_attack(target, mods.shift, mods.alt and not mods.shift)   # command 3 / Shift 0x16 append / Alt 0x17 insert (G-2)
	main.units_ordered.emit(ids)

## The ground move of 0x421190 with DefaultGroupMovement (0x70d7cd): Shift appends, Alt inserts, Ctrl flips the speed
## choice (commands 4 / 0x15 / 0x18 / 0x21 / 0x22 / 0x23 -> 0x530870).
func order_move(point: Vector2, mods: Dictionary, extra: Dictionary = {}):
	var slowest_default := true
	if main.hud != null and main.hud.settings != null: slowest_default = main.hud.settings.get_value("DefaultGroupMovement") != 0
	var individual: bool = slowest_default == bool(mods.ctrl)
	# G-3 (Read, disassembly 0x421afa.. / 0x421dd1.. / 0x42275e.. / 0x4228cd..): both modifiers held -> without Ctrl the
	# Alt command is written last (insert wins), with Ctrl the Shift command (append wins). The Attack-mode ground click
	# (0x1a / 0x37 / 0x38 / 0x39..0x3b) follows the same order.
	var alt_wins: bool = mods.alt and (not mods.shift or not mods.ctrl)
	issue_move(point, mods.shift and not alt_wins, alt_wins, individual, extra)
	main.arm_order_marker()                        # P-2: 0x530870 is followed by 0x49c150

## The builder walks back to an unfinished own site (0x5247b0 is the original's handler; the port re-enters the site).
func resume_building(b):
	var builder = main.selected_builder()
	if builder == null: return
	var at: Vector2i = b.cell_rect().position
	builder.give_order({"kind": "move", "target": main.navigator.center(at), "requested": main.navigator.center(at),
		"group": 0, "speed": builder.base_speed, "individual": true, "build": true}, "replace")
	main.pending_builds[builder.unit_id] = {"type": String(b.original_type_id), "cell": at, "resume": b.entity_id}

## A left or right click in a target mode (0x42271c: modes 1, 2, 4, 5 take either button).
func target_click(point: Vector2, mods: Dictionary):
	var hovered := hover_object(point)
	var ids: Array = own_selected().map(func(u): return u.unit_id)
	if ids.is_empty():
		main.target_mode = 0
		return
	match main.target_mode:
		1:                                        # Move: a click on an object does nothing
			if not hovered.is_empty(): return
			order_move(point, mods)
		2:                                        # Attack: any object (command 3), else attack-move (commands 0x39..)
			if not hovered.is_empty() and not hovered.own and hovered.kind != "mine" and main.combat != null:
				main.issue_attack({"kind": "unit", "id": hovered.object.unit_id} if hovered.kind == "unit" else {"kind": "building", "id": hovered.object.entity_id})
			elif hovered.is_empty() and main.navigator.improved and main.combat != null:
				main.issue_attack_move(point, mods)    # DELIBERATE MODERN CHANGE (F3): attack-move
			elif hovered.is_empty():
				# Attack-move (commands 0x1a / 0x37 / 0x38 / 0x39 / 0x3a / 0x3b -> 0x530870 flag 0): a move whose +0x1c = 1
				# lets the attitude scripts fight on the way; it resumes after each fight (combat.gd note_move).
				order_move(point, mods, {"attack_move": true})
			else: return
		4:                                        # Patrol: Shift adds a point (up to 15), else the patrol starts
			main.patrol_points.append(point)
			if mods.shift and main.patrol_points.size() < 15: return
			start_patrol([main.patrol_start] + main.patrol_points)
			main.patrol_points = []
		5:                                        # Guard: an object only (command 0x20 -> 0x51a3f0)
			if hovered.is_empty() or hovered.kind == "mine": return
			start_guard({"kind": hovered.kind, "id": hovered.object.unit_id if hovered.kind == "unit" else hovered.object.entity_id})
	main.target_mode = 0
	main.units_ordered.emit(ids)

## 0x425150: a target mode from a grid button; Patrol remembers the head unit's position.
func arm_target(mode: int):
	if own_selected().is_empty(): return
	main.target_mode = mode
	main.patrol_points = []
	if mode == 4: main.patrol_start = own_selected()[0].position

## Patrol (0x51d4c0 one unit / 0x534790 several): the points are Read; walking them in a loop is Provisional.
func start_patrol(points: Array):
	for unit in own_selected():
		main.patrols[unit.unit_id] = {"points": points.duplicate(), "next": 1}
		main.guards.erase(unit.unit_id)
		if main.combat != null: main.combat.order_stop(unit.unit_id)
		unit.stop()

## Guard (0x51a3f0 per selected unit): the target is Read; following it within 2 cells is Provisional.
func start_guard(target: Dictionary):
	for unit in own_selected():
		if target.kind == "unit" and int(target.id) == unit.unit_id: continue
		main.guards[unit.unit_id] = target
		main.patrols.erase(unit.unit_id)

func update_patrols():
	for id in main.patrols.keys():
		var unit = main.unit_by_id(id)
		if unit == null or unit.dying:
			main.patrols.erase(id)
			continue
		if not unit.orders.is_empty(): continue
		if main.combat != null and main.combat.fighters.has(id) and main.combat.fighters[id].get("order") != null: continue
		var p: Dictionary = main.patrols[id]
		var target: Vector2 = p.points[int(p.next) % p.points.size()]
		p.next = (int(p.next) + 1) % p.points.size()
		unit.give_order({"kind": "move", "target": main.navigator.center(main.collision.world_cell(target)), "requested": target, "group": 0,
			"speed": unit.base_speed, "individual": true}, "replace")
	for id in main.guards.keys():
		var unit = main.unit_by_id(id)
		var g: Dictionary = main.guards[id]
		var where = null
		if g.kind == "unit":
			var t = main.unit_by_id(int(g.id))
			if t != null and not t.dying: where = t.cell
		elif main.production != null and main.production.building(int(g.id)) != null and main.production.building(int(g.id)).hit_points > 0:
			where = main.production.building(int(g.id)).cell_rect().get_center()
		if unit == null or unit.dying or where == null:
			main.guards.erase(id)
			continue
		if unit.orders.is_empty() and maxi(absi(unit.cell.x - where.x), absi(unit.cell.y - where.y)) > 2:
			var goal: Vector2i = main.navigator.free_cell_near(where)
			unit.give_order({"kind": "move", "target": main.navigator.center(goal), "requested": main.navigator.center(goal),
				"group": 0, "speed": unit.base_speed, "individual": true}, "replace")

# ------------------------------------------------------------------------- wall drag, garrison, repair (unit_commands.gd)
## Wall placement drag (0x4212c8 / 0x42133c): while the button is held the cell under the cursor is offered to 0x429820;
## the release orders the selected builder to build the run (command 0x2d: segment 0 replaces its orders, the rest are
## appended). Right-click cancels.
func wall_drag_input(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var world: Vector2 = main.get_canvas_transform().affine_inverse() * event.position
		if main.wall_drag.add(main.collision.world_cell(world), Vector2i(main.collision.width, main.collision.height), main.wall_site_ok): main.queue_redraw()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		finish_wall_drag()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		main.wall_drag = null
		main.build_mode = ""
		main.last_message = "Cancelled."
		main.queue_redraw()
		return true
	return false

## 0x4352f0 for the armed type: the site test only (the price is paid when each segment is placed).
func wall_site_ok(type_id: String, cell: Vector2i) -> bool:
	return Placement.check(main.navigator, main.production.rules.definition(type_id), cell, main.selected_builder()).ok

func finish_wall_drag():
	var segments: Array = main.wall_drag.segments
	main.wall_drag = null
	main.build_mode = ""                               # 0x42135f / 0x421366: the drag flag and the placement mode end
	main.queue_redraw()
	var builder = main.selected_builder()
	if builder == null:
		main.last_message = "Select a Peasant or the hero first."
		return
	main.unit_commands.wall_queues[builder.unit_id] = segments.slice(1)
	if not main.start_build_walk(builder, String(segments[0].type), segments[0].cell): next_wall_segment(builder)
	main.last_message = "%s builds a wall of %d segments." % [builder.type_id, segments.size()]

## The next appended build order of a wall run (0x524230 mode 1) once the builder is free again; a site that fails is
## skipped as the original's failed build order is.
func next_wall_segment(unit):
	var queue: Array = main.unit_commands.wall_queues.get(unit.unit_id, [])
	while not queue.is_empty():
		var segment: Dictionary = queue.pop_front()
		if main.start_build_walk(unit, String(segment.type), segment.cell): break
	if queue.is_empty(): main.unit_commands.wall_queues.erase(unit.unit_id)

## The run so far, one footprint per segment (Provisional look: the original's per-segment ghost is not traced).
func draw_wall_drag():
	for segment in main.wall_drag.segments:
		var definition: Dictionary = main.production.rules.definition(String(segment.type))
		if definition.is_empty(): continue
		var check: Dictionary = Placement.check(main.navigator, definition, segment.cell, main.selected_builder())
		var color := Color(0.3, 0.9, 0.4, 0.45) if check.ok else Color(0.95, 0.3, 0.3, 0.45)
		for row in range(int(definition.footprint[1])):
			for col in range(int(definition.footprint[0])):
				if Placement.solid(definition, col, row): main.draw_rect(Rect2((check.left + col) * 32, (check.top + row) * 24, 32, 24), color)

## Commands 0x2a / 0x2b (0x5257b0 for each selected unit that passes 0x51c240): walk to a free cell near the clicked point
## (0x530a90); order 0x12 enters on arrival (resolve_garrison_orders). Shift appends (0x2b); Alt sends 0x2a as well.
func order_garrison(b, point: Vector2, mods: Dictionary) -> int:
	var count := 0
	var clicked: Vector2i = main.collision.world_cell(point)
	for unit in own_selected():
		var definition: Dictionary = main.production.rules.definition(unit.type_id)
		if not UnitCommands.can_garrison(unit.type_id, definition.get("footprint", []), main.is_builder(unit), main.is_hero_unit(unit), UnitAI.is_animal(unit.type_id, false)): continue
		unit.sync_cell()
		var goal: Vector2i = main.navigator.free_cell_near(clicked, unit, unit.extent, unit.movement_type)
		if goal.x < 0: continue
		if not mods.shift:
			main.patrols.erase(unit.unit_id)
			main.guards.erase(unit.unit_id)
			main.cancel_conversion(unit)
			main.forget_modern_orders([unit.unit_id])
			if main.combat != null: main.combat.order_stop(unit.unit_id)
		unit.give_order({"kind": "move", "target": main.navigator.center(goal), "requested": point, "group": 0, "speed": unit.base_speed,
			"individual": true, "garrison": b.entity_id}, "append" if mods.shift else "replace")
		if main.combat != null and main.combat.fighters.has(unit.unit_id): main.combat.note_move(unit.unit_id, goal)
		main.unit_commands.garrison_orders[unit.unit_id] = b.entity_id
		count += 1
	if count > 0: main.last_message = "%d units go to garrison the %s." % [count, main.production.rules.display_name(String(b.original_type_id))]
	return count

## Order 0x12 on arrival (0x525960 -> message 0x20a -> 0x52db50): the unit enters when the tower is still its owner's,
## has room and is within reach; it is hidden and leaves the grid (Garrison.wav). Another order drops the garrison order.
func resolve_garrison_orders():
	for id in main.unit_commands.garrison_orders.keys():
		var unit = main.unit_by_id(int(id))
		var building_id: int = main.unit_commands.garrison_orders[id]
		if unit == null or unit.dying or unit.removed or unit.inside_building:
			main.unit_commands.garrison_orders.erase(id)
			continue
		if not unit.orders.is_empty():
			if not unit.orders.any(func(o): return int(o.get("garrison", -1)) == building_id): main.unit_commands.garrison_orders.erase(id)
			continue
		if unit.in_step: continue
		main.unit_commands.garrison_orders.erase(id)
		unit.sync_cell()
		var b = main.production.building(building_id)
		if b == null or not main.unit_commands.can_enter_now(b, main.production.rules, unit.owner_id, unit.cell, b.cell_rect().get_center()): continue
		main.unit_commands.enter(building_id, unit.unit_id)
		if main.combat != null and main.combat.fighters.has(unit.unit_id): main.combat.fighters[unit.unit_id]["garrisoned"] = true   # R-1: +0x1c5 (0x52db89)
		main.navigator.release(unit, unit.cell)
		unit.inside_building = true
		unit.selected = false
		unit.visible = false
		unit.stop()
		if main.combat != null: main.combat.order_stop(unit.unit_id)
		if main.audio != null and unit.owner_id == main.local_player: main.audio.positional("sfx/Garrison", unit.cell)

## Unload (icon 0x20, key o; 0x52dc40 -> message 0x20b -> 0x52dd70): the occupants step out in slot order onto free cells
## near the tower's cell three rows down (the anchor row of the rebuild's footprint stands in for +0x4a: Provisional).
func unload_building(b, building_id: int = -1) -> int:
	if building_id < 0: building_id = b.entity_id
	var ids: Array = main.unit_commands.leave(building_id)
	for id in ids:
		var unit = main.unit_by_id(int(id))
		if unit == null: continue
		if main.combat != null and main.combat.fighters.has(unit.unit_id): main.combat.fighters[unit.unit_id]["garrisoned"] = false   # 0x52de1c
		var near: Vector2i = Vector2i(b.cell_rect().get_center().x, b.top + 3) if b != null else main.collision.world_cell(unit.position)
		var goal: Vector2i = main.navigator.free_cell_near(near, unit, unit.extent, unit.movement_type)
		unit.inside_building = false
		unit.visible = true
		if goal.x >= 0: unit.position = main.navigator.center(goal)
		unit.cell = Vector2i(-1, -1)
		unit.sync_cell()
		unit.advance(0)
	if not ids.is_empty() and main.audio != null and b != null and int(b.owner) == main.local_player: main.audio.positional("sfx/UnGarrison", b.cell_rect().get_center())
	return ids.size()

## Repair (icon 0x11, key e): message 0x112 for an own damaged building (unit_commands.gd start_repair).
func repair_building(b) -> bool:
	if b == null or int(b.owner) != main.local_player: return false
	var ok: bool = main.unit_commands.start_repair(b, main.game_ms())
	main.last_message = "Repairing the %s." % main.production.rules.display_name(String(b.original_type_id)) if ok else "Nothing to repair."
	return ok

# ------------------------------------------------------------------------------------------------ groups, cycling, alerts
## 0x425510 (Ctrl+n): up to 32 selected objects, only when the head is the player's.
func assign_group(n: int):
	var head = selection_head()
	if head == null: return
	var is_unit: bool = head is Node2D and head.get("unit_id") != null
	if int(head.owner_id if is_unit else head.owner) != main.local_player: return
	main.control_groups[n] = {"units": own_selected().slice(0, 32).map(func(u): return u.unit_id), "building": -1 if is_unit else head.entity_id}

func group_members(n: int) -> Array:
	if not main.control_groups.has(n): return []
	var out: Array = []
	for id in main.control_groups[n].units:
		var u = main.unit_by_id(int(id))
		if u != null and not u.dying and not u.removed: out.append(u)
	return out

## n (0x425700 / 0x4255f0): when the selection already is the group, centre on its head (0x490850); else select it.
func recall_group(n: int) -> bool:
	if not main.control_groups.has(n): return false
	var g: Dictionary = main.control_groups[n]
	var members := group_members(n)
	var b = main.production.building(int(g.building)) if main.production != null and int(g.building) >= 0 else null
	if b != null and b.hit_points <= 0: b = null
	if members.is_empty() and b == null:
		main.control_groups.erase(n)
		return false
	var same := false
	if b != null: same = main.selected_building_id == b.entity_id and selected_units().is_empty()
	else:
		var chosen := selected_units()
		same = not chosen.is_empty() and chosen.all(func(u): return members.has(u)) and members.all(func(u): return u.selected)
	if same:
		main.centre_view(members[0].position if b == null else Vector2(b.cell_rect().get_center()) * Vector2(32, 24))
		return true
	if b != null: pick_object(b)
	else:
		set_building_selection(-1)
		Selection.clear(main.units)
		for u in members: Selection.add(u)
		main.units_selected.emit(members.map(func(u): return u.unit_id))
	return true

## Tab / Shift+Tab (0x425920 / 0x425a50 with 0): the next / previous own building with production (0x52e730); with Ctrl
## only buildings that train units (0x52e710). Selects it and centres the view on it.
func cycle_building(forward: bool, trains_only: bool) -> bool:
	if main.production == null: return false
	var list: Array = []
	for id in main.production.buildings:
		var b = main.production.buildings[id]
		if int(b.owner) != main.local_player or b.hit_points <= 0 or b.constructing: continue
		var menu: Array = main.production.menu_for(b)
		if menu.is_empty() or (trains_only and not menu.any(func(m): return String(m.id).begins_with("A"))): continue
		list.append(b)
	if list.is_empty(): return false
	var at := -1
	for i in list.size():
		if list[i].entity_id == main.selected_building_id: at = i
	var next: int = ((at + (1 if forward else -1) + list.size()) % list.size()) if at >= 0 else (0 if forward else list.size() - 1)
	pick_object(list[next])
	main.centre_view(Vector2(list[next].cell_rect().get_center()) * Vector2(32, 24))
	return true

## 0x425b90: newest first, eight slots; the jump index restarts.
## P-1: 0x4dcf70(cell, push): the strategic-map ping (minimap_ping.gd) and, with `push`, the alert list. Callers:
## audio_manager.gd when an "under attack" speech plays, effects_layer.gd when an own building is completed.
func strategic_alert(cell: Vector2i, push: bool):
	if push: push_alert(cell)
	main.minimap_ping.ping(cell, main.collision.height if main.collision != null else 128, main.game_ms())

func push_alert(cell: Vector2i):
	main.alerts.push_front(cell)
	if main.alerts.size() > 8: main.alerts.resize(8)
	main.alert_index = 0
	main.alert_ms = 0

## The alert key (KeyMap line 58 PageUp, or Space when SpacebarPauses is off; 0x427fb0): within 2 s of the last press the
## next stored alert, else the newest.
func alert_jump() -> bool:
	var now := Time.get_ticks_msec()
	if main.alert_ms != 0 and now <= main.alert_ms + 2000:
		main.alert_index = (main.alert_index + 1) % 8
		if main.alert_index < main.alerts.size():
			main.centre_view(Vector2(main.alerts[main.alert_index]) * Vector2(32, 24) + Vector2(16, 12))
			main.alert_ms = now
			return true
	main.alert_index = 0
	main.alert_ms = now
	if main.alerts.is_empty(): return false
	main.centre_view(Vector2(main.alerts[0]) * Vector2(32, 24) + Vector2(16, 12))
	return true

## Ctrl+A / Z / S / T (0x427fb0 cases 0x27..0x2a -> 0x548ee0): the 32 own units nearest to the view centre; Z / T keep the
## head's type (the original compares against the new head, a quirk left Open); S / T only inside the view.
func select_nearest(of_type: bool, on_screen: bool) -> int:
	var type_id := ""
	if of_type:
		if not head_is_own_unit(): return 0
		type_id = String(selection_head().type_id)
	var centre: Vector2i = main.collision.world_cell(main.view_centre())
	var cells := Rect2i()
	if on_screen:
		var r := main.view_rect()
		var a: Vector2i = main.collision.world_cell(r.position) - Vector2i.ONE
		cells = Rect2i(a, main.collision.world_cell(r.end) - a + Vector2i.ONE)
	var count := Selection.select_nearest(main.units, main.local_player, centre, cells, type_id)
	if count > 0:
		set_building_selection(-1)
		main.units_selected.emit(own_selected().map(func(u): return u.unit_id))
	return count

## Ctrl+H (case 0xe) selects the hero; H (case 0xd) adds it when the head is a unit, else selects it.
func select_hero_key(add_it: bool) -> bool:
	var hero = main.unit_by_id(main.hero_unit_id) if main.hero_unit_id >= 0 else null
	if hero == null or hero.dying or hero.removed: return false
	pick_object(hero, add_it and head_is_own_unit())
	main.units_selected.emit([hero.unit_id])
	return true

## Backtick (KeyMap line 28, case 0x12): centre on the selection head.
func centre_on_head() -> bool:
	var head = selection_head()
	if head == null: return false
	if head is Node2D and head.get("unit_id") != null: main.centre_view(head.position)
	else: main.centre_view(Vector2(head.cell_rect().get_center()) * Vector2(32, 24))
	return true

