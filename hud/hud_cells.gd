extends RefCounted
## game_hud.gd's command cells (R-1 split of game_hud.gd, no behaviour change): the cells of the selection and of a
## building, the production / construction / market rows, conversion cells, the race-power cells of batches 1-5.
## The state stays on the panel (game_hud.gd); `hud` is the panel.

const HudScript = preload("res://hud/game_hud.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
var hud: HudScript

func _init(scene: HudScript) -> void:
	hud = scene

# ------------------------------------------------------------------------------------------------ command cells
func selected_own_units() -> Array:
	return hud.main.selected_units().filter(func(u): return u.owner_id == hud.main.local_player and not u.dying)

func icon_tip(icon: int) -> String:
	if hud.settings != null and hud.settings.get_value("HelpLevel") == 0: return ""
	return hud.game_text(int(HudScript.ICON_TIP[icon])).strip_edges() if HudScript.ICON_TIP.has(icon) else ""

## One cell: `id` is the icon id 0x4d2290 dispatches on (the build cells draw an 'i' sheet but answer to 0x1f / 0x21).
func make_cell(icon: int, enabled: bool, action = null, extra: Dictionary = {}) -> Dictionary:
	var c := {"icon": icon, "id": icon, "enabled": enabled, "tip": icon_tip(icon)}
	if action != null: c.action = action
	c.merge(extra, true)
	return c

func refresh_cells():
	hud.cells = []
	for i in 9: hud.cells.append({})
	var units := selected_own_units()
	var building = hud.main.selected_building()
	# Page 6 (0x4d2300 case 6): while a target mode waits for its click only Cancel (icon 0x10) is shown.
	if hud.main.target_mode != 0:
		hud.page = "target"
		hud.cells[0] = make_cell(0x10, true, func(): hud.main.target_mode = 0)
		return
	if hud.page == "formations" and units.size() > 1:
		# Page 7: formations 0x22..0x29 (0x4ce8d0 sets the leader's +0x104 to the cell and re-issues a move to the
		# leader; Read) and Cancel. Only formation table 1 is ported, so the choices are shown disabled (Provisional).
		for k in 8: hud.cells[k] = make_cell(0x22 + k, false, null, {"tip": icon_tip(0x12)})
		hud.cells[8] = make_cell(0x10, true, func(): hud.page = "units")
		return
	hud.page = "units"
	if not units.is_empty():
		var builder = hud.main.selected_builder()
		# 0x4d2300 mode 3 (one unit): 1, 2, 3, 4, 5, 0x15; mode 4 (several, 0x4d2fa0): Formations 0x12 replaces Move.
		hud.cells[0] = make_cell(1, true, func(): hud.main.stop_selected())
		if units.size() == 1: hud.cells[1] = make_cell(2, true, func(): hud.main.arm_target(1))
		else: hud.cells[1] = make_cell(0x12, true, func(): hud.page = "formations")
		hud.cells[2] = make_cell(3, true, func(): hud.main.arm_target(2))
		hud.cells[3] = make_cell(4, true, func(): hud.main.arm_target(4))
		hud.cells[4] = make_cell(5, true, func(): hud.main.arm_target(5))
		hud.cells[5] = make_cell(0x15, true, func(): hud.open_attitude())   # R-1: 0x4ce460 opens the dialog 0x559860 at the cursor
		# 0x4d3200 (Read), the bottom row in order: Convert (6), and for a single unit: a hero's Spellbook (icon 8, [0011],
		# 0x4ce630; enabled when the hero knows a spell, 0x4cde10: disabled for the original's level-1 Warrior), then a
		# builder's Build (0x1f, castle icon, 0x4ce710) and, for non-heroes, the towers and walls row (0x21, 0x4ce7f0).
		var next := add_convert_cell(units)
		if units.size() == 1:
			var hero: bool = hud.main.is_hero_unit(units[0])
			if hero and next < 9:
				hud.cells[next] = make_cell(8, units[0].unit_id == hud.main.hero_unit_id and hud.hero_knows_spells(), func(): hud.open_spellbook())
				next += 1
			if builder != null and next < 9:
				hud.cells[next] = make_cell(0x1f, true, func(): open_construction(hud.main.production.construction_menu(hud.main.local_player)))   # Build Buildings (b)
				next += 1
				if not hero and next < 9:
					hud.cells[next] = make_cell(0x21, true, func(): open_construction(hud.main.production.construction_menu(hud.main.local_player, 1)))
					next += 1
		race_unit_cells(units, next)            # B1-3: advancement, Zombie scavenging, Dwarven Brew
		return
	if building != null and building.owner == hud.main.local_player:
		var page_cells: Array = building_cells(building)
		for k in 9: hud.cells[k] = page_cells[k]

## 0x4d2290: the first enabled cell whose icon is `id` is pressed (the KeyMap keys and Esc go through it).
func press_icon(id: int) -> bool:
	refresh_cells()
	for k in hud.cells.size():
		var c: Dictionary = hud.cells[k]
		if not c.is_empty() and int(c.get("id", c.get("icon", -1))) == id and c.get("enabled", false):
			return press_cell(k)
	return false

## 0x4d2300 mode 5 for an own building: one entry per command cell (index = cell).
func building_cells(building) -> Array:
	var out: Array = []
	for i in 9: out.append({})
	var production = hud.main.production
	var menu: Array = production.menu_for(building)
	var id := String(building.original_type_id)
	# Cell 0 (0x4d0aa0): Stop releases the builder of unfinished construction, Cancel drops the jobs.
	if building.constructing: out[0] = make_cell(1, building.builder_id >= 0, func(): hud.main.release_builder())
	elif building.keep_converting: out[0] = make_cell(1, true, func(): hud.main.cancel_job())   # 0x52fbc0
	else: out[0] = make_cell(1, building.has_job(), func(): hud.main.cancel_all_jobs())
	if building.constructing: return out
	# Cell 4 (0x52b030 -> 0x4d1ea0, milestone 12): an own Keep's Convert.
	var convert = keep_convert_cell(building)
	if not convert.is_empty(): out[4] = convert
	# Cell 1 (0x52e730 -> 0x4d0940): the production dialog of a building with a menu.
	if not menu.is_empty(): out[1] = make_cell(7, true, func(): open_production(building), {"tip": display_name(id)})
	# Cell 2 (0x52e710 -> 0x4d0a50): the rally point of a building that trains units.
	if menu.any(func(m): return String(m.id).begins_with("A")):
		out[2] = make_cell(0x13, true, func(): hud.main.rally_mode = true)
	# Cell 5: Unload (icon 0x20, key o; 0x52dc40) while the tower holds units (the cell index is Provisional).
	if not hud.main.unit_commands.occupants(building.entity_id).is_empty(): out[5] = make_cell(0x20, true, func(): hud.main.unload_building(building))
	# Cell 6 (0x4d0b70): Repair while damaged (message 0x112, unit_commands.gd); disabled while a repair runs.
	# B3-1 (E3, Emulated "building_cells"): a local Orc player has no Repair cell ([0x708f96 + race] == 5, decompile 137467).
	if RacePowers.repair_cell_shown(production.race_of(hud.main.local_player), building.hit_points < building.max_hit_points):
		out[6] = make_cell(0x11, not hud.main.unit_commands.repairing(building.entity_id), func(): hud.main.repair_building(building))
	# Cell 7: trade (B2-1, 0x4d07e0, R1: the seven trade buildings, for their race or with Trade; enabled after Trade).
	var has_trade: bool = production.research_level(hud.main.local_player, RacePowers.TRADE_RESEARCH) != 0
	if RacePowers.trade_cell_shown(id, production.race_of(hud.main.local_player), has_trade):
		out[7] = {"icon": RacePowers.TRADE_ICON, "id": RacePowers.TRADE_ICON, "enabled": has_trade, "action": func(): open_market(), "tip": display_name(RacePowers.TRADE_RESEARCH)}
	# Cell 8: the building powers (0x4d0300 Cathedral / Holy Word, 0x4d0430 Shrine / Sword of Sirian).
	# B4-1 (E10 / E11, Emulated "building_cells"): Elcor's Balm (cell 7 at BPHE / BPHO) and Holy Word (cell 8 at BPCA / BPMT).
	if int(building.owner) == hud.main.local_player and hud.main.combat != null and hud.main.combat.spells != null:
		var p: int = hud.main.local_player
		var b4: Dictionary = RacePowers.b4_building_cells(id, production.race_of(p), func(code): return production.research_level(p, code) != 0)
		for index in b4:
			var c: Array = b4[index]
			var bid: int = building.entity_id
			var press: Callable = (func(): hud.main.combat.spells.elcor_balm(bid)) if String(c[2]) == "elcor" else (func(): hud.main.combat.spells.holy_word(bid))
			out[index] = make_cell(int(c[0]), bool(c[1]), press, {"tip": b4_tip(int(c[0]), display_name(RacePowers.ELCOR_RESEARCH if String(c[2]) == "elcor" else RacePowers.HOLY_RESEARCH))})
		# B5-1 (E3, Emulated "building_cells"): Chaos Plague (cell 8 at BKG0-4) and Couatl's Wrath (cell 8 at BKL0-4).
		var b5: Dictionary = RacePowers.b5_building_cells(id, production.race_of(p), func(code): return production.research_level(p, code) != 0)
		for index in b5:
			var c: Array = b5[index]
			var bid: int = building.entity_id
			var chaos := String(c[2]) == "chaos"
			var press: Callable = (func(): hud.main.combat.spells.chaos_plague(bid)) if chaos else (func(): hud.main.combat.spells.couatls_wrath(bid))
			out[index] = make_cell(int(c[0]), bool(c[1]), press, {"tip": b5_tip(int(c[0]), display_name(RacePowers.CHAOS_RESEARCH if chaos else RacePowers.WRATH_RESEARCH))})
	# G-2: 0x4d0430 shows the Shrine's cell for the Knights or with PSWS; 0x437f70 enables it with PSWS (LAB_004d1bc0).
	if id == "BPSS" and hud.main.combat != null and hud.main.combat.spells != null and (production.race_of(hud.main.local_player) == 0 or production.research_level(hud.main.local_player, "PSWS") != 0):
		out[8] = make_cell(0x60, production.research_level(hud.main.local_player, "PSWS") != 0, func(): hud.main.combat.spells.sword_of_sirian(building.entity_id), {"tip": display_name("PSWS")})
	var power := race_building_cell(building)    # B1-3: Gravestone, Slavehorde, Dark Citadel, Rites of Dawn (cell 7)
	if not power.is_empty(): out[7] = power
	# B3-1 (E3): Ancestral Spirit II in cell 8 of a local Dark Dwarf's Ancestral Hall.
	if int(building.owner) == hud.main.local_player:
		var spirit_ii := b3_cell(building, 8)
		if not spirit_ii.is_empty(): out[8] = spirit_ii
	# ---- B1-4 spells (SPELLS_RESEARCH.md S21, BATCH1 R10): the Dunekeep's Famine (LAB_004d1c60), cell index 7 (+0x114, icon +0xf4; B1-3 correction), icon 0x5f, with
	# PFAX; Spells.famine charges 500 crystal and throttles the cell to once per second.
	if id.begins_with("BKR") and hud.main.combat != null and hud.main.combat.spells != null and production.research_level(hud.main.local_player, "PFAX") != 0:
		out[7] = make_cell(0x5f, true, func(): hud.main.combat.spells.famine(building.entity_id), {"tip": display_name("PFA0")})
	# ---- end B1-4
	return out

## 0x4d0940: the production dialog lists the building's PRODUCTION row slot by slot (gated slots stay empty).
func open_production(building):
	hud.dialog_building = building.entity_id
	hud.dialog_items = []
	for i in 9: hud.dialog_items.append({})
	for m in hud.main.production.menu_for(building):
		var slot: int = int(m.slot)
		if slot >= 0 and slot < 9: hud.dialog_items[slot] = {"id": String(m.id), "kind": "produce"}
	hud.open_dialog("production")

## The builder's construction dialog (Provisional): the construction row(s) in order, nine slots.
func open_construction(rows: Array):
	hud.dialog_items = []
	for id in rows:
		if hud.dialog_items.size() < 9: hud.dialog_items.append({"id": String(id), "kind": "build"})
	while hud.dialog_items.size() < 9: hud.dialog_items.append({})
	hud.open_dialog("construct")

func open_market():
	hud.market = {"from": -1, "to": -1, "amount": -1}
	hud.open_dialog("market")

## 0x5690b0 / 0x569200: a slot is available when the item can be ordered now.
func item_enabled(entry: Dictionary) -> bool:
	if entry.is_empty(): return false
	var id := String(entry.id)
	if entry.kind == "produce": return hud.main.production.can_queue(hud.dialog_building, id).ok
	return hud.main.production.missing_requirement(hud.main.local_player, id) == "" and affordable(id)

func press_item(slot: int) -> bool:
	if slot < 0 or slot >= hud.dialog_items.size() or hud.dialog_items[slot].is_empty() or not item_enabled(hud.dialog_items[slot]): return false
	var entry: Dictionary = hud.dialog_items[slot]
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	if entry.kind == "produce":
		hud.main.selected_building_id = hud.dialog_building
		hud.main.queue_item(String(entry.id))
	else:
		hud.main.arm_build(String(entry.id))
		hud.close_dialog()
	return true

func slot_at(local: Vector2) -> int:
	for k in 9:
		if Rect2(HudScript.SLOT_ORIGIN + Vector2(HudScript.SLOT_STEP * (k % 4), HudScript.SLOT_STEP * (k / 4)), Vector2(HudScript.SLOT_STEP, HudScript.SLOT_STEP)).has_point(local): return k
	return -1

## 0x573010 hit areas of the trade dialog: give lane 0..3, get lane 4..7, amount 8..13, the Trade button 14, close 15.
func market_hit(local: Vector2) -> int:
	if Rect2(0xcc, 0x171, 30, 30).has_point(local): return 15
	if local.x >= 0x6c and local.x < 0x14c and local.y >= 0x14d and local.y < 0x165: return 14
	for r in 4:
		if local.y > HudScript.MARKET_ROWS[r] - 1 and local.y < HudScript.MARKET_ROWS[r + 1]:
			if local.x > HudScript.MARKET_FROM_X[0] - 1 and local.x < HudScript.MARKET_FROM_X[1] + 1: return r
			if local.x > HudScript.MARKET_TO_X[0] - 1 and local.x < HudScript.MARKET_TO_X[1] + 1: return 4 + r
	if local.x > HudScript.MARKET_AMOUNT_X[0] and local.x < HudScript.MARKET_AMOUNT_X[1]:
		for r in 6:
			if local.y > HudScript.MARKET_AMOUNT_ROWS[r] - 1 and local.y < HudScript.MARKET_AMOUNT_ROWS[r + 1]: return 8 + r
	return -1

func market_press(hit: int) -> bool:
	if hit < 0: return false
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	if hit == 15: hud.close_dialog()
	elif hit < 4: hud.market.from = hit
	elif hit < 8: hud.market.to = hit - 4
	elif hit < 14: hud.market.amount = hit - 8
	elif int(hud.market.from) >= 0 and int(hud.market.to) >= 0 and int(hud.market.amount) >= 0:
		var Market = preload("res://simulation/market.gd")
		var done: Array = Market.trade(hud.main.economy, hud.main.local_player, int(hud.market.from), int(hud.market.to), int(Market.AMOUNTS[int(hud.market.amount)]), int(hud.market.get("rate", Market.rate(0))))
		hud.main.last_message = "Traded %d for %d." % [int(done[0]), int(done[1])]
		if bool(hud.market.get("close", false)):                # B1-6e: 0x572a60 closes a spell's dialog (+0x165) after the trade
			hud.spell_trade_memory = {"from": int(hud.market.from), "to": int(hud.market.to), "amount": int(hud.market.amount)}   # 0x61b78c..
			hud.close_dialog()
	return true

# ------------------------------------------------------------------------------------------------ milestone 12: conversion
## 0x4d3200 mode 3: when a selected unit passes 0x523af0(0, 0) the first unit-specific cell (cell 6, before Build) is
## Convert, icon 6, handler 0x4ce590 (Alt / Shift give the modes 2 / 1). Returns the next free cell.
func add_convert_cell(units: Array) -> int:
	if hud.main.conversions == null or not units.any(func(u): return hud.main.can_convert(u)): return 6
	hud.cells[6] = {"icon": 6, "id": 6, "enabled": true, "tip": icon_tip(6),      # Convert (Ctrl+C)
		"action": func(): hud.main.convert_selected(hud.main.conversion_mode(Input.is_key_pressed(KEY_SHIFT), Input.is_key_pressed(KEY_ALT)))}
	return 7

## 0x4d2300 mode 5: an own Keep (0x52b030) shows Convert (icon 6, 0x4d1ea0 -> 0x52f9b0) in the original's cell 4, enabled
## without a job, construction or a running conversion (milestone 13: the building page follows mode 5, so the cell is the
## original's).
func keep_convert_cell(building) -> Dictionary:
	if hud.main.conversions == null or not MatchConversion.is_keep(String(building.original_type_id)): return {}
	return {"icon": 6, "id": 6, "enabled": not building.has_job() and not building.constructing and not building.keep_converting,
		"action": func(): hud.main.keep_convert(building), "tip": hud.game_text(5).get_slice(" (", 0)}

## 0x4d7710: "Converting" (Game.txt [0264], font 2), ProductionBar.bmp (0xbf, 36x36) whose top is covered black by
## 32 - percent * 32 / 100 rows, and "percent%" (0x46e3b0, centred). Unit: text (+0xb5, +0x2d), bar (+0x105, +0x23),
## cover (+0x107, +0x25), percent (+0x117, +0x31); Keep: (+0x10, +0x43), (+0x60, +0x39), (+0x62, +0x3b), (+0x72, +0x47).
## Offsets are Read. Parity pass 3: for a unit `origin` is the info area's corner + (0, 0x2c), the base of the label rows
## (0x4d7710: y = +0x2a + 0x2c), which puts "Converting" under Combat and Hits as in the original; the Keep's base is still
## the area's corner (Provisional).
func draw_converting(origin: Vector2, percent: int, unit: bool):
	var t: Vector2 = Vector2(0xb5, 0x2d) if unit else Vector2(0x10, 0x43)
	var bar: Vector2 = Vector2(0x105, 0x23) if unit else Vector2(0x60, 0x39)
	hud.text(hud.game_text(264), 2, Rect2(origin + t, Vector2(120, 16)))
	draw_production_bar(origin + bar, percent)

## ProductionBar.bmp (0xbf, 36 x 36) at `at`, its top covered black by 32 - percent * 32 / 100 rows from + 2, and
## "percent%" centred at + (0x12, 0xe) (0x46e3b0): the conversion block and the production queue (F9) share it.
func draw_production_bar(at: Vector2, percent: int):
	var sheet := hud.tex("ProductionBar.bmp")
	if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(at, Vector2(36, 36)), Rect2(0, 0, 36, 36))
	var cover := 32 - (percent * 32) / 100
	if cover > 0: hud.draw_rect(Rect2(at + Vector2(2, 2), Vector2(32, cover)), Color.BLACK)
	hud.text("%d%%" % percent, 2, Rect2(at + Vector2(18 - 30, 14), Vector2(60, 14)), HORIZONTAL_ALIGNMENT_CENTER)

func affordable(item: String) -> bool:
	var cost: Array = hud.main.production.price_of(hud.main.local_player, item)
	var stock: Array = hud.main.economy.resources(hud.main.local_player)
	for i in 4:
		if int(stock[i]) < int(cost[i]): return false
	return true

func display_name(type_id: String) -> String:
	return hud.main.production.rules.display_name(type_id) if hud.main.production != null else type_id

func cell_rect(k: int) -> Rect2:
	return Rect2(HudScript.GRID + Vector2(8 + 43 * (k % 3), 8 + 43 * (k / 3) + hud.oy()), Vector2(38, 38))

func press_cell(k: int) -> bool:
	if k < 0 or k >= hud.cells.size(): return false
	var c: Dictionary = hud.cells[k]
	if c.is_empty() or not c.get("enabled", false) or not c.has("action"): return false
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	c.action.call()
	return true

func race_tip(icon: int, fallback: String = "") -> String:
	if hud.settings != null and hud.settings.get_value("HelpLevel") == 0: return ""
	var line: String = hud.game_text(int(RacePowers.TIP_LINE.get(icon, -1))).strip_edges() if RacePowers.TIP_LINE.has(icon) else ""
	return line if line != "" else fallback

func race_unit_cells(units: Array, next: int) -> int:
	if units.is_empty() or hud.main.production == null: return next
	var same := units.all(func(u): return String(u.type_id) == String(units[0].type_id))
	# B4-1 (E1, Emulated "unit_cells", review "merge_box"): the Wisp merge (icon 0xd), any race.
	if same and next < 9 and hud.main.merge_shown(units):
		hud.cells[next] = make_cell(RacePowers.MERGE_ICON, hud.main.merge_enabled(hud.main.local_player), func(): hud.main.merge_selected(),
			{"tip": b4_tip(RacePowers.MERGE_ICON, "Merge")})
		next += 1
	# B4-1 (E7 / E8): Sacrifice (icon 0x1a) comes first in the mixed row (mode 4) and after the casters' cells for one type.
	if not same: next = sacrifice_cell(units, next)
	if same:
		for b in hud.main.advancement_buttons(units):
			if next >= 9: return next
			var target := String(b.target)
			var cost: Array = b.cost
			var price := []
			for lane in 4:
				if int(cost[lane]) > 0: price.append("%d %s" % [int(cost[lane]) * units.size(), ["gold", "metal", "crystal", "stone"][lane]])
			hud.cells[next] = make_cell(int(b.icon), bool(b.enabled), func(): hud.main.advance_selected(target),
				{"tip": "%s (%s)" % [race_tip(int(b.icon), display_name(target)), ", ".join(price)], "target": target})
			next += 1
		next = ability_cells(units, next)
		next = sacrifice_cell(units, next)
		var zombie = units[0]
		if next < 9 and String(zombie.type_id) == RacePowers.SCAVENGER and hud.main.production.race_of(hud.main.local_player) == 2:
			hud.cells[next] = make_cell(RacePowers.ICON.scavenge, hud.main.production.research_level(hud.main.local_player, RacePowers.SCAVENGE_RESEARCH) != 0,
				func(): hud.main.scavenge(zombie), {"tip": race_tip(RacePowers.ICON.scavenge, "Scavenge")})
			next += 1
	if next < 9 and units.all(func(u): return hud.main.drinker(u)):
		var has_brew: bool = hud.main.production.research_level(hud.main.local_player, RacePowers.BREW_RESEARCH) != 0
		if has_brew or hud.main.production.race_of(hud.main.local_player) == RacePowers.DWARF:
			var gold := int(hud.main.economy.resources(hud.main.local_player)[0])
			hud.cells[next] = make_cell(RacePowers.ICON.brew, has_brew and gold >= RacePowers.BREW_GOLD * units.size(),
				func(): hud.main.brew_selected(), {"tip": race_tip(RacePowers.ICON.brew, "Dwarven Brew")})
			next += 1
	# B2-1 (R2): the Berserker button comes after the Brew in both paths of 0x4d3200.
	if next < 9 and RacePowers.berserker_cell_shown(hud.main.production.race_of(hud.main.local_player), units.map(func(u): return String(u.type_id)), units.any(func(u): return hud.main.in_berserk_state(u))):
		hud.cells[next] = make_cell(RacePowers.BERSERK_ICON, hud.main.production.research_level(hud.main.local_player, RacePowers.BERSERK_RESEARCH) != 0,
			func(): hud.main.berserk_selected(), {"tip": race_tip(RacePowers.BERSERK_ICON, "Berserker")})
		next += 1
	return next

func sacrifice_cell(units: Array, next: int) -> int:
	if next >= 9 or not hud.main.sacrifice_shown(units): return next
	hud.cells[next] = make_cell(RacePowers.SACRIFICE_ICON, hud.main.sacrifice_enabled(units), func(): hud.main.sacrifice_selected(),
		{"tip": b4_tip(RacePowers.SACRIFICE_ICON, "Sacrifice")})
	return next + 1

## B2-2 (BATCH2_RESEARCH.md R11): the casters' ability cells of 0x4d3200, when the selection has one type; a press is the case's
## hot key (0x426350): the first selected caster with the mana pays and casts.
func ability_cells(units: Array, next: int) -> int:
	var spells = hud.main.combat.spells if hud.main.combat != null else null
	if spells == null: return next
	for row in spells.unit_row_for(String(units[0].type_id), hud.main.local_player):   # B3-2: Earthpower only for a local race 10
		if next >= 9: return next
		var index := int(row[0])
		var tip := hud.game_text(int(row[4])).strip_edges() if hud.settings == null or hud.settings.get_value("HelpLevel") != 0 else ""
		hud.cells[next] = make_cell(int(row[1]), spells.unit_row_enabled(row, units), func(): spells.ability(index, hud.main.local_player), {"tip": tip})
		next += 1
	return next

## Cell 7 of 0x4d2300 mode 5 for the batch-1 powers (an own, finished building).
func race_building_cell(building) -> Dictionary:
	var id := String(building.original_type_id)
	var p: int = hud.main.local_player
	var production = hud.main.production
	if int(building.owner) != p: return {}
	if id in RacePowers.SLAVEHORDE_BUILDINGS:
		return make_cell(RacePowers.ICON.slavehorde, production.research_level(p, RacePowers.SLAVEHORDE_RESEARCH) != 0 and hud.main.command_free(p),
			func(): hud.main.slavehorde(building), {"tip": race_tip(RacePowers.ICON.slavehorde, "Slavehorde")})
	if id == RacePowers.GRAVESTONE and production.race_of(p) in RacePowers.GRAVESTONE_RACES:
		return make_cell(RacePowers.ICON.gravestone, hud.main.command_free(p), func(): hud.main.raise_gravestone(building),
			{"tip": race_tip(RacePowers.ICON.gravestone, "Raise Skeleton")})
	var dn = hud.main.day_night
	if id in RacePowers.RITES_BUILDINGS:
		var open: bool = dn != null and (dn.is_night() or dn.raining)
		return make_cell(RacePowers.ICON.rites, production.research_level(p, RacePowers.RITES_RESEARCH) != 0 and open,
			func(): hud.main.weather_power(building, false), {"tip": race_tip(RacePowers.ICON.rites, "Rites of Dawn")})
	if id in RacePowers.DARK_CITADEL_BUILDINGS:
		var day_now: bool = dn != null and dn.enabled and not dn.is_night()
		return make_cell(RacePowers.ICON.dark_citadel, production.research_level(p, RacePowers.DARK_CITADEL_RESEARCH) != 0 and day_now,
			func(): hud.main.weather_power(building, true), {"tip": race_tip(RacePowers.ICON.dark_citadel, "Dark Citadel")})
	# B3-1 (E3, Emulated "building_cells"): Brood (any race), Ancestral Spirit I (local race 10), Stormcall (local race 11, not raining).
	return b3_cell(building, 7)

## Cell 7 / 8 of RacePowers.b3_building_cells for the local player's own building ({} when it has none).
func b3_cell(building, index: int) -> Dictionary:
	var p: int = hud.main.local_player
	var dn = hud.main.day_night
	var cells: Dictionary = RacePowers.b3_building_cells(String(building.original_type_id), hud.main.production.race_of(p),
		func(code): return hud.main.production.research_level(p, code) != 0, dn != null and dn.raining)
	if not cells.has(index): return {}
	var c: Array = cells[index]
	var icon: int = int(c[0])
	var action: Callable
	match String(c[2]):
		"brood": action = func(): hud.main.brood(building)
		"spirit": action = func(): hud.main.ancestral_spirit(building, int(c[3]))
		_: action = func(): hud.main.stormcall(building)
	var names := {"brood": "Brood", "spirit": "Ancestral Spirit " + ("I" if int(c[3]) == 1 else "II"), "stormcall": "Stormcall"}
	return make_cell(icon, bool(c[1]), action, {"tip": b3_tip(icon, String(names[String(c[2])]))})

## B4-1: 0x414ef0 for the batch-4 icons (RacePowers.B4_TIP_LINE).
func b4_tip(icon: int, fallback: String) -> String:
	if hud.settings != null and hud.settings.get_value("HelpLevel") == 0: return ""
	var line: String = hud.game_text(int(RacePowers.B4_TIP_LINE[icon])).strip_edges() if RacePowers.B4_TIP_LINE.has(icon) else ""
	return line if line != "" else fallback

## B5-1: 0x414ef0 for the batch-5 icons (RacePowers.B5_TIP_LINE).
func b5_tip(icon: int, fallback: String) -> String:
	if hud.settings != null and hud.settings.get_value("HelpLevel") == 0: return ""
	var line: String = hud.game_text(int(RacePowers.B5_TIP_LINE[icon])).strip_edges() if RacePowers.B5_TIP_LINE.has(icon) else ""
	return line if line != "" else fallback

## 0x414ef0 for the batch-3 icons (RacePowers.B3_TIP_LINE).
func b3_tip(icon: int, fallback: String) -> String:
	if hud.settings != null and hud.settings.get_value("HelpLevel") == 0: return ""
	var line: String = hud.game_text(int(RacePowers.B3_TIP_LINE.get(icon, -1))).strip_edges() if RacePowers.B3_TIP_LINE.has(icon) else ""
	return line if line != "" else fallback

