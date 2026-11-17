extends RefCounted
## main.gd's mines, conversion and the computer player's bridge (R-1 split of main.gd, no behaviour change): mine and
## conversion orders, MatchConversion's callbacks, and the computer player's view of the world (ai_units, ai_move,
## ai_build, ai_site ...). The state stays on the scene (main.gd); `main` is the scene.

const MainScript = preload("res://battle/main.gd")
const Navigation = preload("res://battle/navigation.gd")
const AiSites = preload("res://simulation/ai_sites.gd")
const Placement = preload("res://simulation/placement.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

# ------------------------------------------------------------------ milestone 10b: mines and the computer player's world

## Right-click on a mine with units selected: the hero walks next to a mine it does not own and converts from there
## (a rebuild convenience from milestone 10b: the original converts only through the Convert button, below); Peasants
## enter a mine of their owner (0x524b00 / 0x524d10).
func mine_order(mine_id: int):
	var count := 0
	for unit in main.selected_units():
		if unit.owner_id != main.local_player: continue
		if can_convert(unit) and main.mines.owner_of(mine_id) != unit.owner_id: count += int(order_convert(unit, "mine", mine_id))
		elif not main.is_hero_unit(unit) and main.production.rules.can_mine(unit.type_id) and main.mines.owner_of(mine_id) == unit.owner_id: count += int(order_enter_mine(unit, mine_id))
	main.last_message = "%d units ordered to the mine." % count if count > 0 else "No selected unit can use this mine (heroes convert, builders such as Peasants or Smiths work owned mines)."

## Walk to the nearest free cell beside a footprint.
func _approach(unit, footprint: Array) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1 << 30
	for cell in footprint:
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var c: Vector2i = cell + d
			if c in footprint or not main.navigator.is_passable(c): continue
			var dist: int = Navigation.chebyshev(c, unit.cell)
			if dist < best_d:
				best_d = dist
				best = c
	return best

func _mine_approach(unit, mine_id: int) -> Vector2i:
	return _approach(unit, main.mines.mines[mine_id].cells)

func target_cells(kind: String, id: int) -> Array:
	if kind == "mine": return main.mines.mines[id].cells if main.mines.mines.has(id) else []
	var b = main.production.building(id)
	if b == null: return []
	var out: Array = []
	var r: Rect2i = b.cell_rect()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x): out.append(Vector2i(x, y))
	return out

func order_enter_mine(unit, mine_id: int) -> bool:
	var cell := _mine_approach(unit, mine_id)
	if cell.x < 0: return false
	main.combat.order_stop(unit.unit_id)
	unit.give_order({"kind": "move", "target": main.navigator.center(cell), "requested": main.navigator.center(cell), "group": 0, "speed": unit.base_speed, "individual": true}, "replace")
	if main.combat.fighters.has(unit.unit_id): main.combat.note_move(unit.unit_id, cell)   # the scripts see a player order
	main.mine_orders[unit.unit_id] = {"kind": "enter", "mine": mine_id, "cell": cell, "state": "walking"}
	return true

## Walk beside the target (a mine or a building), then convert where the unit stands. The computer player's conversion
## group does this (0x4f4940: a move to a cell within reach of the target, then 0x51cbb0(0) within 3 cells of that cell;
## the cell choice 0x4f8820 is not ported: the nearest free cell beside the footprint stands in, Provisional).
func order_convert(unit, kind: String, id: int) -> bool:
	var cell := _approach(unit, target_cells(kind, id))
	if cell.x < 0: return false
	cancel_conversion(unit)
	main.combat.order_stop(unit.unit_id)
	unit.give_order({"kind": "move", "target": main.navigator.center(cell), "requested": main.navigator.center(cell), "group": 0, "speed": unit.base_speed, "individual": true}, "replace")
	if main.combat.fighters.has(unit.unit_id): main.combat.note_move(unit.unit_id, cell)   # the scripts see a player order
	main.mine_orders[unit.unit_id] = {"kind": "convert", "target_kind": kind, "target": id, "cell": cell, "state": "walking"}
	return true

# ------------------------------------------------------------------ milestone 12: conversion (MatchConversion)
func setup_conversions():
	main.conversions = MatchConversion.new()
	var flags := {}
	for p in 7: flags[p] = p < 6 and bool(main.skirmish.slots[p].computer)
	main.conversions.setup(main.production, main.mines, main.catalogue_data, flags, func(a, b): return main.skirmish.is_allied(a, b))
	main.generals.clear()
	for row in main.catalogue_data.get("army_cfg", {}).get("armies", []):
		if bool(row.get("general_flag", false)): main.generals[String(row.code)] = true
	main.conversions.transferred.connect(main._on_converted)
	main.conversions.finished.connect(main._on_conversion_finished)
	main.conversions.keep_finished.connect(main._on_keep_conversion_finished)

## 0x520c90 order 7 done: event 0xf (CODEConversion) for the local player's unit.
func _on_conversion_finished(actor_id: int, owner: int, converted: Array):
	if owner != main.local_player: return
	if main.audio != null: main.audio.on_conversion_finished(actor_id)
	main.last_message = "Conversion complete: %d buildings converted." % converted.size()

## The Keep's completion (building update 0x52cf71): KeepConversion.wav for the local player.
func _on_keep_conversion_finished(_building_id: int, owner: int, converted: Array):
	if owner != main.local_player: return
	if main.audio != null: main.audio.on_keep_conversion()
	main.last_message = "Keep conversion complete: %d buildings converted." % converted.size()

## 0x4a6cc0's other effects: the results counters (0x518f40), the marker's team colour, the quest hook 0x43db30(2, ...)
## (quest type 3 is Open). Its conversion flash (0x58bf70 'EZ01' near the view) has no EZ01 sheet in this install's
## archives, so the original draws nothing either.
func _on_converted(id: int, previous: int, owner: int):
	var mine: bool = main.mines != null and main.mines.mines.has(id)
	if main.skirmish != null: main.skirmish.note_conversion(previous, owner, mine)
	if main.encounters != null and not mine: main.encounters.note_building_owner(id, owner)
	if main.building_nodes.has(id): main.building_nodes[id].refresh_sprites()
	if mine:   # the mine's map sprite takes the new owner's colour ramp (0x487f20)
		for object in main.map_objects:
			if object.is_building and int(object.get_meta("source_offset")) == int(main.mines.mines[id].get("source_offset", -1)):
				object.owner_player = owner
				object.apply_material()

## 0x523af0's inputs for a unit, from the match: the owner's hero (0x70adb4) alive, its power 0x526c80 (level / 2 + 8 +
## item type 4), the actor's radius 0x5267b0 (Charisma + 5 + item type 10), PHOC / PBRO research, the game mode.
func conversion_terms(unit) -> Dictionary:
	if main.conversions == null or unit == null or main.combat == null: return {"ok": false}
	var owner: int = unit.owner_id
	var hero_fighter = main.combat.fighters.get(int(main.combat.heroes[owner].unit)) if main.combat.heroes.has(owner) else null
	var hero_alive: bool = hero_fighter != null and main.combat.alive(hero_fighter) and int(hero_fighter.hp) > 0
	var bound = main.match_heroes.get(owner)
	var block: Dictionary = bound.block(int(hero_fighter.hp) if hero_fighter != null else 0) if bound != null and bound.profile != null else {}
	var kind := "hero" if main.is_hero_unit(unit) else ("general" if main.generals.has(unit.type_id) else "")
	return MatchConversion.actor_terms({"kind": kind, "code": unit.type_id, "hero_alive": hero_alive,
		"power": HeroEffects.conversion_power(block) if not block.is_empty() else 8,     # an unbound hero: level 1
		"radius": HeroEffects.conversion_radius(block) if not block.is_empty() else 11,  # ... Charisma 6
		"research": main.production.research_level(owner, "PHOC") > 0, "pbro": main.production.research_level(owner, "PBRO") > 0,
		"mode": int(main.combat.game_mode)})

func can_convert(unit) -> bool:
	return bool(conversion_terms(unit).get("ok", false))

## The Convert button / Ctrl+C (0x4ce590): the first selected hero converts, else the first selected unit 0x523af0 accepts;
## only one unit converts.
func convert_selected(mode: int = 0) -> bool:
	if main.conversions == null: return false
	var chosen = null
	for unit in main.selected_units():
		if unit.owner_id == main.local_player and not unit.dying and main.is_hero_unit(unit):
			chosen = unit
			break
	if chosen == null:
		for unit in main.selected_units():
			if unit.owner_id == main.local_player and not unit.dying and can_convert(unit):
				chosen = unit
				break
	if chosen == null: return false
	return order_convert_here(chosen, mode)

## An original Game.txt message for the local player: the control panel's message line (0x44f4a0 -> 0x499120) as well as
## the harness status.
func player_message(text: String):
	main.last_message = text
	if main.hud != null and main.hud.has_method("show_message"): main.hud.show_message(text)

func game_string(id: int, fallback: String) -> String:
	var text: String = main.hud.game_text(id) if main.hud != null else ""
	return text if text != "" else fallback

## 0x51cbb0(mode) for one unit: 0 converts where it stands and drops its other orders; 1 queues the conversion after the
## current orders (order 0xc, started by 0x51de00 -> 0x51cbb0(2) when the queue reaches it); 2 converts now and keeps the
## orders for afterwards (0x406530 puts order 7 in front of them). Nothing in range: the local player sees Game.txt [0065].
func order_convert_here(unit, mode: int = 0) -> bool:
	if main.conversions == null or not can_convert(unit): return false
	if main.conversions.converting(unit.unit_id): return mode != 2       # order 7 already current
	if mode == 1 and (not unit.orders.is_empty() or unit.in_step):
		main.mine_orders[unit.unit_id] = {"kind": "convert", "state": "queued"}
		return true
	unit.sync_cell()
	var finish: int = main.conversions.begin_unit(unit.unit_id, unit.owner_id, unit.cell, conversion_terms(unit), main.game_ms(),
		"hero" if main.is_hero_unit(unit) else ("phoenix" if unit.type_id == "AAPH" else "general"))
	if finish < 0:
		if unit.owner_id == main.local_player: player_message(game_string(MatchConversion.NOTHING_TEXT, "There is nothing here to convert..."))
		return false
	var resume: Array = unit.orders.duplicate() if mode == 2 else []
	unit.stop()
	var f = main.combat.fighters.get(unit.unit_id)
	var marker := {"kind": "convert", "ai": false, "finished": false, "goal": unit.cell}
	if f != null:
		f.order = null
		f.cur = marker                            # a player order the attitude scripts leave running
	main.mine_orders[unit.unit_id] = {"kind": "convert", "state": "converting", "resume": resume, "cur": marker}
	# Parity pass 4: no 500 ms marker here. 0x49c150 is called only after right-click moves (0x530870, 0x41f0b0) and the
	# rally order (0x52e6b0), not by Convert (0x4ce590), so the conversion icon shows only while Shift / Alt is held.
	if unit.owner_id == main.local_player: main.last_message = "Converting (%d s)." % ((finish - main.game_ms()) / 1000)
	return true

## Any other order ends order 7 (0x520c90 with the finish not reached converts nothing).
func cancel_conversion(unit):
	if main.conversions == null or unit == null: return
	var job: Dictionary = main.mine_orders.get(unit.unit_id, {})
	if job.get("kind", "") != "convert": return
	main.conversions.cancel(unit.unit_id)
	if job.has("cur"): job.cur.finished = true
	main.mine_orders.erase(unit.unit_id)

## The Keep's Convert button (0x4d1ea0 -> 0x52f9b0, when 0x52fc00 reports no conversion).
func keep_convert(b = null) -> bool:
	if b == null: b = main.selected_building()
	if b == null or main.conversions == null or not MatchConversion.is_keep(String(b.original_type_id)): return false
	var finish: int = main.conversions.begin_keep(b, main.game_ms())
	if finish < 0:
		if int(b.owner) == main.local_player and not b.constructing and not b.has_job() and not b.keep_converting:
			player_message(game_string(MatchConversion.NOTHING_TEXT, "There is nothing here to convert..."))
		return false
	if int(b.owner) == main.local_player: main.last_message = "The Keep is converting (%d s)." % ((finish - main.game_ms()) / 1000)
	return true

func resolve_mine_orders():
	for id in main.mine_orders.keys():
		var unit = main.units[id]
		var job: Dictionary = main.mine_orders[id]
		if unit.dying or unit.removed:
			if main.conversions != null: main.conversions.cancel(id)
			main.mine_orders.erase(id)
			continue
		var f = main.combat.fighters.get(id)
		if job.state == "converting":
			if main.conversions == null or not main.conversions.converting(id):
				# finished (0x520c90): the orders that waited behind order 7 resume
				job.cur.finished = true
				main.mine_orders.erase(id)
				for order in job.resume: unit.give_order(order, "append")
				continue
			# Another order (or any movement) ends the conversion.
			if not unit.orders.is_empty() or unit.in_step or (f != null and (f.order != null or not is_same(f.cur, job.cur))):
				cancel_conversion(unit)
			continue
		if not unit.orders.is_empty() or unit.in_step: continue
		unit.sync_cell()
		if job.kind == "enter":
			if _near_mine(unit.cell, job.mine) and main.mines.enter(job.mine, id, unit.owner_id, main.production.rules.mine_workers(unit.type_id)):
				main.navigator.release(unit, unit.cell)
				unit.inside_building = true
				unit.selected = false
				unit.visible = false
				# 0x4a74f0 -> 0x51a130(0): the worker leaves play in state 8; it no longer counts for victory or can be
				# targeted (REVIEW_SKIRMISH_AI.md D1). Nor for the population: 0x533dc0 (Read) skips state 8, so the
				# command count drops (playtest 2026-11-11: twenty Peasants in mines kept a beaten computer at
				# population 6, above AI Resignation's 5, and the match never ended).
				unit.removed = true
				main.production.unregister_unit(id)
				if main.combat.fighters.has(id):
					main.combat.fighters[id].state = "corpse"
					main.combat.fighters[id].removed = true
				job.state = "inside"
				main.mine_orders.erase(id)
				main.in_mine_units[id] = job.mine
			else:
				job.state = "failed"
				main.failed_mine_orders[id] = true
				main.mine_orders.erase(id)
		else:
			# the walk to the target, or a queued order 0xc, has been reached: convert where the unit stands (a walk that
			# ended more than 2 cells from its goal was redirected and converts nothing)
			main.mine_orders.erase(id)
			if (job.has("cell") and Navigation.chebyshev(unit.cell, job.cell) > 2) or not order_convert_here(unit, 2):
				main.failed_mine_orders[id] = true

func _near_mine(cell: Vector2i, mine_id: int) -> bool:
	for c in main.mines.mines[mine_id].cells:
		if Navigation.chebyshev(c, cell) <= 2: return true
	return false

# ---- the computer player's view of the world (AiPlayer calls these; they only read state or issue the orders above)
## AI-4: 0x52bd10's hate call (AiManager.building_damaged): the attacker's owner and whether it is a computer (0x70d6a4).
func _ai_building_damaged(b, amount: int, attacker_kind: String, attacker_id: int):
	if main.ai_manager == null or main.skirmish == null: return
	var owner := int(main.combat.object_owner(attacker_kind, attacker_id)) if attacker_id >= 0 else -1
	if owner < 0 or owner >= main.skirmish.slots.size(): return
	main.ai_manager.building_damaged(int(b.owner), amount, owner, bool(main.skirmish.slots[owner].get("computer", false)))

func ai_units(owner: int) -> Array:
	return main.units.filter(func(u): return u.owner_id == owner and not u.removed and not u.dying)

func unit_by_id(id: int):
	return main.units[id] if id >= 0 and id < main.units.size() else null

func unit_busy(unit) -> bool:
	return not unit.orders.is_empty() or unit.in_step or main.pending_builds.has(unit.unit_id) or main.mine_orders.has(unit.unit_id) \
		or (main.combat.fighters.has(unit.unit_id) and main.combat.fighters[unit.unit_id].order != null)

func build_state(unit) -> String:
	if main.pending_builds.has(unit.unit_id): return "pending"
	return String(main.build_results.get(unit.unit_id, "pending"))

func in_mine(unit) -> bool:
	return main.in_mine_units.has(unit.unit_id)

func mine_order_failed(unit) -> bool:
	return main.failed_mine_orders.erase(unit.unit_id)

func owns_objects(player: int) -> bool:
	for unit in main.units:
		if unit.owner_id == player and not unit.removed and not unit.dying: return true
	for b in main.production.buildings.values():
		if b.owner == player: return true
	return false

func hostile_near(owner: int, cell: Vector2i, reach: int) -> bool:
	for f in main.combat.fighters.values():
		if f.owner == owner or f.owner == 6 or main.skirmish.is_allied(owner, int(f.owner)) or not main.combat.alive(f): continue
		if Navigation.chebyshev(main.combat.unit_cell(f.id), cell) <= reach: return true
	return false

func ai_move(unit, cell: Vector2i, speed: int = -1):   # AI-7: `speed` = a group's slowest member (0x51d6b0's third argument)
	var target: Vector2 = main.navigator.center(main.navigator.free_cell_near(cell))
	var walk: int = unit.base_speed if speed < 0 else mini(speed, unit.base_speed)
	unit.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": walk, "individual": true}, "replace")
	if main.combat.fighters.has(unit.unit_id): main.combat.note_move(unit.unit_id, main.collision.world_cell(target))

func ai_build(unit, type_id: String, cell: Vector2i) -> bool:
	unit.sync_cell()
	if not main.production.can_place(unit.owner_id, type_id, cell, unit).ok: return false
	main.build_results.erase(unit.unit_id)
	unit.give_order({"kind": "move", "target": main.navigator.center(cell), "requested": main.navigator.center(cell), "group": 0,
		"speed": unit.base_speed, "individual": true, "build": true}, "replace")
	if main.combat.fighters.has(unit.unit_id): main.combat.note_move(unit.unit_id, cell)
	main.pending_builds[unit.unit_id] = {"type": type_id, "cell": cell}
	return true

func ai_enter_mine(unit, mine_id: int) -> bool:
	return order_enter_mine(unit, mine_id)

func ai_convert(unit, kind: String, id: int) -> bool:
	return order_convert(unit, kind, id)

## AI-7: the original's site search (simulation/ai_sites.gd: the windows 0x4f9480, the spot 0x435320, the reserved cells
## of the computer players' running build tasks, 0x4f9a10). Production then still has to accept the spot (Provisional:
## the original places a computer's building without any test, AI-4 O2).
func ai_site(owner: int, type_id: String, home: Vector2i, builder) -> Vector2i:
	if not main.production.can_place_anywhere(owner, type_id): return Vector2i(-1, -1)   # same result, without the scan
	var definition: Dictionary = main.production.rules.definition(type_id)
	var reserved := {}
	if main.ai_manager != null:
		for ai in main.ai_manager.players:
			if ai == null or not ("tasks" in ai): continue
			for t in ai.tasks.values():
				for c in t.get("reserved", []): reserved[c] = true
	var spot: Vector2i = AiSites.find(main.navigator, type_id, definition.footprint, home, builder, reserved)
	if spot.x < 0 or not main.production.can_place(owner, type_id, spot, builder).ok: return Vector2i(-1, -1)
	return spot

## The rings stand-in the port used before AI-7 (kept for comparisons; not called).
func ai_site_rings(owner: int, type_id: String, home: Vector2i, builder) -> Vector2i:
	if not main.production.can_place_anywhere(owner, type_id): return Vector2i(-1, -1)
	var definition: Dictionary = main.production.rules.definition(type_id)
	for radius in range(4, 36, 2):
		for dy in range(-radius, radius + 1, 2):
			for dx in range(-radius, radius + 1, 2):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var cell := home + Vector2i(dx, dy)
				if cell.x < 2 or cell.y < 2 or cell.x > main.collision.width - 3 or cell.y > main.collision.height - 3: continue
				if not Placement.check(main.navigator, definition, cell, builder).ok: continue
				if not _clear_margin(definition, cell): continue
				if main.production.can_place(owner, type_id, cell, builder).ok: return cell
	return Vector2i(-1, -1)

func _clear_margin(definition: Dictionary, cell: Vector2i) -> bool:
	var anchor: Vector2i = Placement.anchor(definition, cell)
	for y in range(anchor.y - 2, anchor.y + int(definition.footprint[1]) + 2):
		for x in range(anchor.x - 2, anchor.x + int(definition.footprint[0]) + 2):
			var c := Vector2i(x, y)
			if main.navigator.building_cells.has(c) or main.mines.mine_at(c) >= 0: return false
	return true

## Objects of `player` an army group may target: living units and buildings (mines are only for Mine Killer groups).
func ai_targets(player: int) -> Array:
	var out: Array = []
	for f in main.combat.fighters.values():
		if int(f.owner) != player or not main.combat.alive(f) or main.units[f.id].inside_building: continue
		out.append({"kind": "unit", "id": f.id, "cell": main.combat.unit_cell(f.id), "code": f.type_id, "dying": false, "value_0x92": 0})
	for b in main.production.buildings.values():
		if b.owner != player or b.hit_points <= 0: continue
		# AI-11 (AI_RESEARCH.md section 27): 0x4f5e90 drops a building whose +0x115 is set, and +0x115 is the rubble flag
		# (0x52b3e0 sets it on destruction; ECONOMY_RESEARCH.md 0x52da90, Emulated), not "unfinished" (+0xcc): a site under
		# construction scores like a finished building. Rubble has no hit points here and is already left out above.
		out.append({"kind": "building", "id": b.entity_id, "cell": Vector2i(b.left, b.top), "code": b.original_type_id, "unfinished": false})
	return out

## Mines a computer player's hero group may take (not its own; conversion by the group member, 0x4f4940).
func ai_mine_targets(owner: int) -> Array:
	var out: Array = []
	for row in main.mines.census(owner):
		if row.owned or row.exhausted: continue
		out.append({"kind": "mine", "id": row.id, "cell": row.cell, "code": main.mines.mines[row.id].code, "workers": int(row.workers)})
	return out

func converting(unit) -> bool:
	return (main.conversions != null and main.conversions.converting(unit.unit_id)) or (main.mine_orders.has(unit.unit_id) and main.mine_orders[unit.unit_id].kind == "convert")

## 0x4fbc60 for the computer player's Keep: no non-unit order at the head of its list, and the level digits of the mines
## not owned by `owner` whose anchors lie within 32 cells (dx^2 + dy^2 < 0x401) of the Keep's anchor add up to more than 0.
func ai_keep_has_mines(b, owner: int) -> bool:
	var head: String = String(b.job_item) if String(b.job_item) != "" else (String(b.queue[0]) if not b.queue.is_empty() else "")
	if head != "" and head[0] != "A": return false
	var at: Vector2i = b.cell()
	var total := 0
	for id in main.mines.mines:
		var m: Dictionary = main.mines.mines[id]
		if int(m.entity.owner) == owner: continue
		var d: Vector2i = m.entity.cell() - at
		if absi(d.x) <= 32 and absi(d.y) <= 32 and d.x * d.x + d.y * d.y < 0x401: total += String(m.code).unicode_at(3) - 0x30
	return total > 0

## ARM word +0x1c of a unit type (the 0x4fb100 divisor; production time in seconds), 20 when unknown.
func unit_arm_0x1c(type_id: String) -> int:
	var definition := main.unit_definition(type_id)
	if definition.is_empty() or not definition.has("raw_hex"): return 20
	return CombatRules.i16(String(definition.raw_hex).hex_decode(), 0x1c)

func ai_summaries() -> Array:
	if main.ai_manager == null: return []
	return main.ai_manager.players.filter(func(p): return p != null and p.has_method("summary")).map(func(p): return p.summary())

## 0x534340 for an eliminated side: units and buildings with hit points get message 0x1fb (destroyed here), buildings at 0
## hit points go to the neutral player 6 (message 0x104).
func _on_side_cleanup(player: int):
	for f in main.combat.fighters.values():
		if int(f.owner) == player and main.combat.alive(f): main.combat.apply_damage("unit", f.id, int(f.hp) + 1, -1)
	for b in main.production.buildings.values().duplicate():
		if b.owner != player: continue
		if b.hit_points > 0: main.combat.apply_damage("building", b.entity_id, b.hit_points + 1, -1)
		else: b.owner = 6

func _ai_pre_update(now_ms: int):
	if main.ai_manager != null and main.skirmish != null and not main.skirmish.over: main.ai_manager.update(now_ms, main.skirmish)

