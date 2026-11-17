extends RefCounted
## game_hud.gd's dialogs (R-1 split of game_hud.gd, no behaviour change): opening, placing and the mouse of the
## dialogs (game menu, options, message boxes), their drawing (production, market, diplomacy, spellbook, quest),
## the quest sheet and the load sheet. The state stays on the panel (game_hud.gd); `hud` is the panel.

const HudScript = preload("res://hud/game_hud.gd")
const Settings = preload("res://simulation/game_settings.gd")
const OptionsScreen = preload("res://menus/options_screen.gd")
const SaveGameFile = preload("res://simulation/save_game.gd")
var hud: HudScript

func _init(scene: HudScript) -> void:
	hud = scene

# ------------------------------------------------------------------------------------------------ dialogs
func open_dialog(kind: String):
	if hud.dialog == "inventory" and kind != "inventory": hud.main.close_inventory()   # 0x560a00 commits the ground row
	hud.dialog = kind
	hud.dialog_hover = -1
	hud.main.target_mode = 0
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()

func close_dialog():
	if hud.dialog == "load": close_load()            # S-1: the load sheet resumes the match it paused
	if hud.dialog == "inventory":
		hud.dialog = ""
		hud.main.close_inventory()
	hud.dialog = ""
	hud.dialog_hover = -1

func dialog_origin() -> Vector2:
	if hud.dialog == "attitude": return hud.attitude_rect.position
	var key: String = "box" if hud.dialog in ["resign", "quit", "victory"] else hud.dialog
	if not HudScript.DIALOG_AT.has(key): key = "box"
	return HudScript.dialog_place(HudScript.DIALOG_AT[key], int(HudScript.DIALOG_HEIGHT[key]), HudScript.PANEL_TOP + hud.oy())

## S-1 (0x566020 / 0x566160, Read): Load Game is enabled in a skirmish while the hero has a saved game (0x40d950; the
## rebuild also counts its autosave, a modern addition), Save Game in any skirmish; the rest always.
func menu_row_enabled(row: int) -> bool:
	if row == 0: return hud.main != null and hud.main.get("skirmish") != null and (hud.main.save_exists() or hud.main.save_exists(true))
	if row == 1: return hud.main != null and hud.main.get("skirmish") != null
	return true

func menu_row_at(local: Vector2) -> int:
	if local.x <= 0x3e or local.x >= 0x145: return -1
	for i in HudScript.MENU_ROW_TOP.size():
		if local.y > HudScript.MENU_ROW_TOP[i] and local.y < HudScript.MENU_ROW_TOP[i] + 0x1f: return i if menu_row_enabled(i) else -1
	return -1

## The cell under the point in the options dialog: rows at 92/154/212/273 (5 cells, 61 apart from x 67), 335 (3 cells).
func option_cell_at(local: Vector2) -> Vector2i:
	var tops := [92, 154, 212, 273, 335]
	for r in tops.size():
		var count: int = HudScript.OPTION_ROWS[r][2].size()
		var first := 67 if count == 5 else 128
		for c in count:
			if Rect2(first + 61 * c, tops[r], 0x3b, 0xf).grow(2).has_point(local): return Vector2i(r, c)
	return Vector2i(-1, -1)

func dialog_mouse(event: InputEventMouse, v: Vector2):
	var local := v - dialog_origin()
	if hud.dialog == "attitude":
		hud.attitude_mouse(event, local)
		return
	if hud.dialog in ["shop", "quest_offer"]:                # S-2: dialog 12 and the quest site dialog
		hud.site_dialog_mouse(event, local)
		return
	if hud.dialog == "inventory":
		hud.inventory_mouse(event, local)
		return
	if hud.dialog in ["diplomacy", "spellbook", "quest", "spell_choice"]:
		if event is InputEventMouseMotion:
			if hud.dialog == "diplomacy": hud.dialog_slot = hud.diplomacy_hit(local)
			elif hud.dialog == "spellbook": hud.spell_hover = hud.spell_row_at(local)
			elif hud.dialog == "spell_choice": hud.dialog_hover = hud.spell_choice_at(local)
			elif hud.dialog == "quest": hud.dialog_hover = HudScript.QUEST_HOVER_CLOSE if HudScript.QUEST_CLOSE.has_point(local) else -1
			return
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed): return
		match hud.dialog:
			"diplomacy": hud.diplomacy_press(hud.diplomacy_hit(local))
			"spellbook": hud.spellbook_press(local)
			"spell_choice": hud.spell_choice_press(local)
			"quest":
				if HudScript.QUEST_CLOSE.has_point(local):
					preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
					close_dialog()
		return
	if hud.dialog == "load":
		if event is InputEventMouseMotion:
			hud.dialog_hover = load_hit(local)
			return
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed): return
		match load_hit(local):
			HudScript.LOAD_BUTTON: load_press()
			HudScript.LOAD_CLOSE:
				preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
				close_dialog()
			HudScript.LOAD_SAVED: load_pick(0)
			HudScript.LOAD_AUTOSAVE: load_pick(1)
		return
	if hud.dialog in ["production", "construct", "market"]:
		if event is InputEventMouseMotion:
			hud.dialog_slot = hud.slot_at(local) if hud.dialog != "market" else hud.market_hit(local)
			return
		if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed): return
		if hud.dialog == "market":
			hud.market_press(hud.market_hit(local))
		elif Rect2(0x11d, 0x182, 30, 30).has_point(local):
			preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
			close_dialog()
		else:
			hud.press_item(hud.slot_at(local))
		return
	if event is InputEventMouseMotion:
		hud.dialog_hover = menu_row_at(local) if hud.dialog == "menu" else box_button_at(local)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed): return
	var close_x := 0xcb if hud.dialog == "options" else 0xb3
	if hud.dialog in ["menu", "options"] and Rect2(close_x, 0x171, 30, 30).has_point(local):
		preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
		close_dialog()
		return
	match hud.dialog:
		"menu": menu_press(menu_row_at(local))
		"options":
			var cell := option_cell_at(local)
			if cell.x >= 0: option_press(cell.x, cell.y)
		_: box_press(box_button_at(local))

func menu_press(row: int) -> bool:
	if row < 0 or not menu_row_enabled(row): return false
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	match row:
		0:                                                       # 0x565b4f: not once the match is decided (0x748914)
			if hud.main.skirmish.game_over or hud.main.skirmish.over: return true
			close_dialog()
			open_load()
		1:                                                       # 0x565bb6: the save at once, with its message
			if hud.main.skirmish.game_over or hud.main.skirmish.over: return true
			close_dialog()
			save_now()
		2:
			hud.toggle_pause()
			close_dialog()
		3: open_options()
		4: open_dialog("victory")
		5: open_dialog("resign")
		6: open_dialog("quit")
	return true

## The game menu's Options (and Alt+O): the main menu's options screen over the match, which pauses while it is open
## (DELIBERATE MODERN CHANGE, options_screen.gd; the original opens the in-game sheet EMDO, kept below but unused).
func open_options():
	if options_open(): return
	close_dialog()
	hud.options_paused = hud.speed != 0
	if hud.options_paused: hud.toggle_pause()
	hud.options_layer = CanvasLayer.new()
	hud.options_layer.layer = 40
	hud.main.add_child(hud.options_layer)
	var screen = OptionsScreen.new()
	screen.in_game = true
	screen.closed.connect(hud.close_options)
	if hud.main.has_method("apply_modern_rules"): screen.modern_changed.connect(hud.main.apply_modern_rules)
	hud.options_layer.add_child(screen)

func close_options(_saved: bool = false):
	if hud.options_layer != null: hud.options_layer.queue_free()
	hud.options_layer = null
	hud.settings = Settings.current()
	if hud.options_paused and hud.speed == 0: hud.toggle_pause()
	hud.options_paused = false

func options_open() -> bool:
	return hud.options_layer != null and is_instance_valid(hud.options_layer)

func options_screen():
	return hud.options_layer.get_child(0) if options_open() and hud.options_layer.get_child_count() > 0 else null

func option_press(row: int, column: int) -> bool:
	if row == 3: return false                                    # Gamma: N/A (0x158) in the rebuild
	var key: String = HudScript.OPTION_ROWS[row][0]
	hud.settings.set_value(key, int(HudScript.OPTION_ROWS[row][2][column]))
	hud.settings.save()
	if hud.speed == 0 and key == "OverallVolume": hud.volume_before_pause = hud.settings.get_value(key)
	else: preload("res://core/audio_manager.gd").instance(hud.get_tree()).apply_settings(hud.settings)
	return true

## Message box buttons (0x55d400): two buttons at x 0x67..0x11b / 0x136..0x1ea, y 0xde..0x100; one button 0xc9..0x17c.
func box_button_at(local: Vector2) -> int:
	if local.y <= 0xdd or local.y >= 0x101: return -1
	if hud.dialog == "victory": return 0 if local.x > 200 and local.x < 0x17d else -1
	if local.x > 0x66 and local.x < 0x11b: return 0
	if local.x > 0x135 and local.x < 0x1ea: return 1
	return -1

## 0x55ccd0: type 4 (resign) button 1 resigns (defeat with results, 0x514450); type 5 (quit) button 1 exits to Windows
## (0x45c0c0: no results, only the start save is on disk); button 0 closes.
func box_press(button: int) -> bool:
	if button < 0: return false
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	var kind := hud.dialog
	close_dialog()
	if button == 1 and kind == "resign":
		hud.main.quit_match()
	elif button == 1 and kind == "quit":
		hud.quit_requested = true
		if DisplayServer.get_name() != "headless": hud.get_tree().quit()
	return true

func draw_dialog():
	var at := dialog_origin()
	match hud.dialog:
		"production", "construct": draw_production_dialog(at)
		"market": draw_market_dialog(at)
		"diplomacy": draw_diplomacy_dialog(at)
		"attitude": hud.draw_attitude_dialog(at)
		"spellbook": draw_spellbook_dialog(at)
		"spell_choice": hud.draw_spell_choice_dialog(at)
		"quest": draw_quest_dialog(at)
		"inventory": hud.draw_inventory_dialog(at)
		"shop": hud.draw_shop_dialog(at)
		"quest_offer": hud.draw_quest_offer(at)
		"load": draw_load_dialog(at)
		"menu":
			var sheet := hud.tex("EMDG")
			if sheet != null: hud.draw_texture(sheet, at)
			hud.text(hud.game_text(316), 1, Rect2(at.x, at.y + 0x20 - 22, 400, 30), HORIZONTAL_ALIGNMENT_CENTER)   # Game Menu
			for i in HudScript.MENU_ROW_TOP.size():
				var id: int = HudScript.MENU_ROW_TEXT[i]
				if id < 0: id = 318 if hud.speed == 0 else 317                # Resume Game / Pause Game
				var font := 5 if menu_row_enabled(i) else 7
				if i == hud.dialog_hover: font = 6
				hud.text(hud.game_text(id), font, Rect2(at.x, at.y + HudScript.MENU_ROW_TOP[i] + 9, 386, 24), HORIZONTAL_ALIGNMENT_CENTER)
			hud.draw_close(at + Vector2(0xb3, 0x171))
		"options":
			var sheet := hud.tex("EMDO")
			if sheet != null: hud.draw_texture(sheet, at)
			hud.text(hud.game_text(339), 1, Rect2(at.x, at.y + 0x19 - 22, 434, 30), HORIZONTAL_ALIGNMENT_CENTER)
			var label_y := [0x46, 0x84, 0xbe, 0xfb, 0x139]
			var tops := [92, 154, 212, 273, 335]
			for r in 5:
				hud.text(hud.game_text(HudScript.OPTION_LABELS[r]), 19, Rect2(at.x, at.y + label_y[r] - 14, 434, 20), HORIZONTAL_ALIGNMENT_CENTER)
				var values: Array = HudScript.OPTION_ROWS[r][2]
				var captions: Array = HudScript.OPTION_ROWS[r][1]
				var first := 67 if values.size() == 5 else 128
				var current: int = hud.settings.get_value(String(HudScript.OPTION_ROWS[r][0]))
				if String(HudScript.OPTION_ROWS[r][0]) == "OverallVolume": current = values[Settings.sfx_level(current)]
				for c in values.size():
					var box := Rect2(at + Vector2(first + 61 * c, tops[r]), Vector2(0x3b, 0xf))
					var caption: String = String(captions[c]) if captions[c] is String else hud.game_text(int(captions[c]))
					var font := 7 if r == 3 else (6 if int(values[c]) == current else 5)
					hud.text(caption, font, Rect2(box.position.x, box.position.y - 2, box.size.x, 16), HORIZONTAL_ALIGNMENT_CENTER)
					if int(values[c]) == current and r != 3: hud.draw_rect(box.grow(1), Color(1, 0.85, 0.4), false, 1.0)
			hud.draw_close(at + Vector2(0xcb, 0x171))
		_:
			var box := hud.tex("EMDM")
			var buttons := hud.tex("EMDE")
			if box != null: hud.draw_texture(box, at)
			var title: int = {"resign": 308, "quit": 321, "victory": 320}[hud.dialog]
			var lines: Array = {"resign": [313, 314], "quit": [383, 384], "victory": []}[hud.dialog]
			var victory_text: Array = hud.victory_lines() if hud.dialog == "victory" else []
			hud.text(hud.game_text(title), 1, Rect2(at.x, at.y + 0x3a - 22, 586, 30), HORIZONTAL_ALIGNMENT_CENTER)
			var ly := 0x82 if lines.size() == 2 else 0x78
			for i in victory_text.size():                    # S-2: 0x44e5.. the active option's name and description
				hud.text(String(victory_text[i]), 19, Rect2(at.x, at.y + 0x6e - 14 + 20 * i, 586, 20), HORIZONTAL_ALIGNMENT_CENTER)
			for i in lines.size():
				hud.text(hud.game_text(lines[i]), 19, Rect2(at.x, at.y + ly - 14 + 20 * i, 586, 20), HORIZONTAL_ALIGNMENT_CENTER)
			if hud.dialog == "victory":
				hud.draw_box_button(buttons, at + Vector2(0xc9, 0xdd), 0, hud.game_text(300), at + Vector2(0x125, 0xea))    # Okay
			else:
				hud.draw_box_button(buttons, at + Vector2(0x67, 0xdd), 0, hud.game_text(382), at + Vector2(0xc1, 0xea))     # No
				hud.draw_box_button(buttons, at + Vector2(0x136, 0xdd), 1, hud.game_text(381), at + Vector2(0x190, 0xea))   # Yes

## Prices of one slot (0x569450, parity pass 3, Read).
func draw_prices(cost: Array, slot: Vector2):
	var icons := hud.tex("ERIX")
	var digits := hud.tex("ERNX")
	if icons == null or digits == null: return
	var at := slot + Vector2(1, 0x45)
	for lane in HudScript.PRICE_ORDER:
		var value := clampi(int(cost[lane]), 0, 99999)
		if value <= 0: continue
		hud.draw_texture_rect_region(icons, Rect2(at, Vector2(60, 20)), Rect2(0, int(HudScript.PRICE_FRAME[lane]) * 20, 60, 20))
		var s := str(value)
		for k in s.length():
			hud.draw_texture_rect_region(digits, Rect2(at + Vector2(16 + 8 * k, 5), Vector2(7, 10)), Rect2(int(s[k]) * 7, 0, 7, 10))
		at.y -= 0x15

## 0x569450: the slot icons (enabled / greyed), each slot's price, the hovered item's name and Help.cfg lines, close.
func draw_production_dialog(at: Vector2):
	var sheet := hud.tex("EMDP")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, Vector2(0x262, 0x1c2)), Color(0.1, 0.08, 0.05, 0.92))
	var powerups := hud.tex("Powerups%s.bmp" % hud.powerup_sheet())
	var columns := hud.powerup_columns()
	for k in mini(9, hud.dialog_items.size()):
		var entry: Dictionary = hud.dialog_items[k]
		if entry.is_empty(): continue
		var id := String(entry.id)
		var pos: Vector2 = at + HudScript.SLOT_ORIGIN + Vector2(HudScript.SLOT_STEP * (k % 4), HudScript.SLOT_STEP * (k / 4))
		var enabled := hud.item_enabled(entry)
		var column := columns.find(id)
		if column >= 0 and powerups != null:
			hud.draw_texture_rect_region(powerups, Rect2(pos, Vector2(90, 90)), Rect2(column * 90, 0 if enabled else 90, 90, 90))
		elif hud.icon_sheet(id) != null:
			hud.draw_texture_rect_region(hud.icon_sheet(id), Rect2(pos, Vector2(90, 90)), Rect2(0, 190 if enabled else 280, 90, 90))
		else:
			hud.draw_rect(Rect2(pos, Vector2(90, 90)), Color(0.25, 0.25, 0.25))
			hud.text(hud.display_name(id), 5, Rect2(pos + Vector2(2, 30), Vector2(86, 20)), HORIZONTAL_ALIGNMENT_CENTER)
		if k == hud.dialog_slot: hud.draw_rect(Rect2(pos, Vector2(90, 90)), Color(1, 0.85, 0.4), false, 1.0)
		# 0x569450 skips the prices of a slot in state 4; the original's build dialog shows none on unavailable (greyed)
		# items (user's screenshot). Provisional: state 4 = a requirement is missing.
		if entry.kind == "produce" or hud.main.production.missing_requirement(hud.main.local_player, id) == "":
			draw_prices(hud.main.production.price_of(hud.main.local_player, id), pos)
	if hud.dialog_slot >= 0 and hud.dialog_slot < hud.dialog_items.size() and not hud.dialog_items[hud.dialog_slot].is_empty():
		var id := String(hud.dialog_items[hud.dialog_slot].id)
		var info: Dictionary = hud.main.production.rules.help(id)
		hud.text(hud.display_name(id), 5, Rect2(at.x + 0xd4, at.y + 0x116 - 4, HudScript.HELP_WRAP, 20))
		var lines := help_rows(String(info.get("desc", "")), String(info.get("requ", "")))
		var tops := [0x12b, 0x139, 0x147]
		for i in lines.size(): hud.text(String(lines[i]), 2, Rect2(at.x + 0xde, at.y + tops[i] - 4, HudScript.HELP_WRAP, 16))
	hud.draw_close(at + Vector2(0x11d, 0x182))

func help_rows(desc: String, requ: String) -> Array:
	var lines := hud.wrapped(desc, 2, HudScript.HELP_WRAP).slice(0, 3)
	if lines.is_empty(): lines = [""]
	if lines.size() == 1: lines.append_array(hud.wrapped(requ, 2, HudScript.HELP_WRAP).slice(0, 2))
	elif lines.size() == 2: lines.append(requ)
	return lines

## 0x5723a0 / 0x572590: the four resources to give and to get, six amounts, the Trade button and the rate.
func draw_market_dialog(at: Vector2):
	var sheet := hud.tex("EMDX")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, Vector2(0x1c2, 0x1af)), Color(0.1, 0.08, 0.05, 0.92))
	var Market = preload("res://simulation/market.gd")
	hud.text("%s (%d%%)" % [String(hud.market.get("title", hud.display_name("PTRA"))), int(hud.market.get("rate", Market.rate(0)))], 1, Rect2(at.x, at.y + 0x20 - 22, 0x1c2, 30), HORIZONTAL_ALIGNMENT_CENTER)
	var names := ["Gold", "Metal", "Stone", "Crystal"]
	for r in 4:
		var row := Rect2(at.x + HudScript.MARKET_FROM_X[0], at.y + HudScript.MARKET_ROWS[r], HudScript.MARKET_FROM_X[1] - HudScript.MARKET_FROM_X[0], HudScript.MARKET_ROWS[r + 1] - HudScript.MARKET_ROWS[r])
		hud.text(names[r], 6 if int(hud.market.from) == r else 5, Rect2(row.position + Vector2(0, 14), row.size), HORIZONTAL_ALIGNMENT_CENTER)
		if int(hud.market.from) == r: hud.draw_rect(row, Color(1, 0.85, 0.4), false, 1.0)
		var to := Rect2(at.x + HudScript.MARKET_TO_X[0], at.y + HudScript.MARKET_ROWS[r], HudScript.MARKET_TO_X[1] - HudScript.MARKET_TO_X[0], HudScript.MARKET_ROWS[r + 1] - HudScript.MARKET_ROWS[r])
		hud.text(names[r], 6 if int(hud.market.to) == r else 5, Rect2(to.position + Vector2(0, 14), to.size), HORIZONTAL_ALIGNMENT_CENTER)
		if int(hud.market.to) == r: hud.draw_rect(to, Color(1, 0.85, 0.4), false, 1.0)
	for r in 6:
		var row := Rect2(at.x + HudScript.MARKET_AMOUNT_X[0], at.y + HudScript.MARKET_AMOUNT_ROWS[r], HudScript.MARKET_AMOUNT_X[1] - HudScript.MARKET_AMOUNT_X[0], HudScript.MARKET_AMOUNT_ROWS[r + 1] - HudScript.MARKET_AMOUNT_ROWS[r])
		hud.text(str(int(Market.AMOUNTS[r])), 6 if int(hud.market.amount) == r else 5, Rect2(row.position + Vector2(0, 4), row.size), HORIZONTAL_ALIGNMENT_CENTER)
	var ready: bool = int(hud.market.from) >= 0 and int(hud.market.to) >= 0 and int(hud.market.amount) >= 0
	hud.text(hud.display_name("PTRA"), 5 if ready else 7, Rect2(at.x + 0x6c, at.y + 0x14d, 0xe0, 0x18), HORIZONTAL_ALIGNMENT_CENTER)
	hud.draw_close(at + Vector2(0xcc, 0x171))

## 0x558810 (drawing Provisional, see the header): amounts, carts, the other players' gems and names, Send, close.
func draw_diplomacy_dialog(at: Vector2):
	var sheet := hud.tex("EMDA")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, Vector2(0x1c2, 0x1af)), Color(0.1, 0.08, 0.05, 0.92))
	var gold := Color(1, 0.85, 0.4)
	hud.text(hud.game_text(295), 1, Rect2(at.x, at.y + 0x20 - 22 + 20, 0x1c2, 30), HORIZONTAL_ALIGNMENT_CENTER)   # Diplomacy
	if int(hud.diplomacy.amount) >= 0: hud.draw_rect(Rect2(at + Vector2(0x4c, 0x81 + 0x1b * int(hud.diplomacy.amount)), Vector2(0x2e, 0x1b)), gold, false, 1.0)
	if int(hud.diplomacy.resource) >= 0: hud.draw_rect(Rect2(at + Vector2(0x93, 0x79 + 0x2e * int(hud.diplomacy.resource)), Vector2(0x33, 0x2e)), gold, false, 1.0)
	var gems := hud.tex("ESHD")
	for p in hud.diplomacy_players():
		var row := at + Vector2(0xe4, 0x6b + 0x23 * p)
		var colour: int = preload("res://core/art_data.gd").player_colour(p)
		if gems != null and colour >= 0 and colour < 7:
			hud.draw_texture_rect_region(gems, Rect2(row + Vector2(5, 7), Vector2(25, 20)), Rect2(25 * colour, 0, 25, 20))
		var font := 6 if int(hud.diplomacy.player) == p or hud.dialog_slot == 10 + p else 5
		hud.text(hud.fitted(hud.player_label(p), font, 0x8a - 34), font, Rect2(row + Vector2(34, 10), Vector2(0x8a - 34, 18)))
		if int(hud.diplomacy.player) == p: hud.draw_rect(Rect2(row, Vector2(0x8a, 0x23)), gold, false, 1.0)
	var ready: bool = int(hud.diplomacy.amount) >= 0 and int(hud.diplomacy.resource) >= 0 and int(hud.diplomacy.player) >= 0
	var caption := hud.game_text(299) if bool(hud.diplomacy.sent) else hud.game_text(296)        # Resources Sent / Resources
	hud.text(caption, 6 if ready and hud.dialog_slot == 16 else (5 if ready or bool(hud.diplomacy.sent) else 7), Rect2(at.x + 0x5d, at.y + 0x151 + 6, 0xfd, 20), HORIZONTAL_ALIGNMENT_CENTER)
	hud.draw_close(at + Vector2(0xcd, 0x171))

## 0x56f910 (drawing Provisional): the page's school name, its ten spells (known in ink, unknown greyed, the hovered one
## red), the hovered spell's name and description on the right page, close.
func draw_spellbook_dialog(at: Vector2):
	var sheet := hud.tex("EMDS")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, Vector2(0x265, 0x1bd)), Color(0.3, 0.25, 0.18, 0.95))
	var data: Dictionary = hud.canvas.layout.get("spells", {})
	var schools := hud.hero_schools()
	var school_names: Array = data.get("schools", [])
	if hud.spell_school < school_names.size():
		hud.text(String(school_names[hud.spell_school]), 22, Rect2(at.x + 0x2d, at.y + 0x46 - 4, 0xe0, 28), HORIZONTAL_ALIGNMENT_CENTER)
	for k in 10:
		var spell := hud.spell_school * 10 + k
		var row := Rect2(at.x + 0x2d, at.y + 100 + 0x17 * k, 0xe0, 0x17)
		if k == hud.spell_hover: hud.draw_rect(row, Color(0.55, 0.1, 0.05, 0.18))
		var known := HudScript.spell_known(schools, spell) and hud.spell_affordable(spell)
		hud.text(hud.fitted(String(hud.spell_text(spell).name), 23, row.size.x - 8), 23, Rect2(row.position + Vector2(8, 0), row.size - Vector2(8, 0)), HORIZONTAL_ALIGNMENT_LEFT, 1.0 if known else 0.4)
	if hud.spell_hover >= 0:
		var spell := hud.spell_school * 10 + hud.spell_hover
		var right := Rect2(at.x + 0x14a, at.y + 0x46 - 4, 0xf0, 28)
		hud.text(hud.fitted(String(hud.spell_text(spell).name), 22, right.size.x), 22, right, HORIZONTAL_ALIGNMENT_CENTER)
		var lines := hud.wrapped(String(hud.spell_text(spell).desc), 23, 0xf0)
		for i in lines.size(): hud.text(String(lines[i]), 23, Rect2(at.x + 0x14a, at.y + 100 + 0x17 * i, 0xf0, 0x17), HORIZONTAL_ALIGNMENT_CENTER)
	hud.draw_close(at + Vector2(0x120, 0x17e))

## 0x56a150 mode 5: the active quest (q). Drawn by draw_quest_sheet like the site dialog.
func draw_quest_dialog(at: Vector2):
	var q = hud.quest()
	if q == null:
		draw_quest_sheet(at, "sheet", {}, 0)
		return
	draw_quest_sheet(at, "sheet", q.record, int(q.progress))

## 0x44ef60 over the slots: each line takes the words that fit its slot's width.
func quest_lines(s: String, font_number: int) -> Array:
	var info: Dictionary = hud.canvas.font(font_number)
	var width_of := func(t: String) -> float:
		if info.is_empty() or info.font == null: return t.length() * 7.0
		return info.font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x
	var out: Array = []
	var words: PackedStringArray = s.split(" ", false)
	var i := 0
	while i < words.size() and out.size() < HudScript.QUEST_LINE_X.size():
		var limit: float = HudScript.QUEST_LINE_W[out.size()]
		var line := words[i]
		i += 1
		while i < words.size() and width_of.call(line + " " + words[i]) <= limit:
			line += " " + words[i]
			i += 1
		var n := out.size()
		var x: int = HudScript.QUEST_LINE_X[n]
		if n == 9 and width_of.call(line) <= 0x8e: x = 0xd9
		out.append({"text": line, "x": x, "y": HudScript.QUEST_LINE_Y0 + HudScript.QUEST_LINE_STEP * n})
	return out

## The progress figure 0x56aff0 prints: the stockpile of the record's resource for type 0, else the quest's counter.
func quest_progress_value(r: Dictionary, progress: int) -> int:
	if int(r.get("type", -1)) != 0: return progress
	var lane: int = {"G": 0, "M": 1, "C": 2, "S": 3}.get(String(r.get("target", "")).to_upper(), -1)
	if lane < 0 or hud.main.economy == null: return 0
	return int(hud.main.economy.resources(hud.main.local_player)[lane])

func quest_button_frame(index: int) -> int:
	if hud.dialog_hover != index: return 0
	return 2 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 1

func draw_quest_sheet(at: Vector2, mode: String, r: Dictionary, progress: int):
	var sheet := hud.tex("EMDQ")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, Vector2(0x1ae, 0x1a1)), Color(0.1, 0.08, 0.05, 0.92))
	hud.draw_close(at + HudScript.QUEST_CLOSE.position, quest_button_frame(HudScript.QUEST_HOVER_CLOSE))
	if r.is_empty(): return
	var portrait := hud.tex("quest_" + String(r.get("portrait", "")).to_upper())
	if portrait != null: hud.draw_texture_rect(portrait, Rect2(at + Vector2(0x4e, 0x4b), Vector2(0x80, 0xa0)), false)
	hud.text(String(r.get("name", "")), 0x18, Rect2(at.x + 0xd5 - 200, at.y + 0x1c, 400, 30), HORIZONTAL_ALIGNMENT_CENTER)
	var key: String = HudScript.QUEST_TEXT_KEYS.get(mode, "newq")
	for line in quest_lines(String(r.get(key, "")), 0x13):
		hud.text(String(line.text), 0x13, Rect2(at.x + int(line.x), at.y + int(line.y), 300, 20))
	if int(r.get("type", -1)) == 4: return
	if mode in ["continue", "sheet"]:
		var shown := hud.game_text(325) % [quest_progress_value(r, progress), int(r.get("count", 0))]
		hud.text(shown, 0x13, Rect2(at.x + 0xd8 - 150, at.y + 0x13d, 300, 20), HORIZONTAL_ALIGNMENT_CENTER)
	if mode in ["offer", "instant"]:
		var frame := quest_button_frame(HudScript.QUEST_HOVER_OKAY)
		var buttons := hud.tex("EMDE")
		if buttons != null: hud.draw_texture_rect_region(buttons, Rect2(at + HudScript.QUEST_OKAY.position, HudScript.QUEST_OKAY.size), Rect2(0, 36 * frame, 180, 36))
		hud.text(hud.game_text(326), 5, Rect2(at.x + 0xf6 - 90, at.y + (0x162 if frame == 2 else 0x161), 180, 20), HORIZONTAL_ALIGNMENT_CENTER)

## 0x56a840 / 0x56abe0 for the site dialog: Okay (modes 0 and 3) accepts and, for instant, rewards; in complete mode any
## click and the close button reward (0x43d560); Enter acts as Okay in every mode; Esc closes without anything.
func quest_hover_at(local: Vector2) -> int:
	if HudScript.QUEST_CLOSE.has_point(local): return HudScript.QUEST_HOVER_CLOSE
	if HudScript.QUEST_OKAY.has_point(local) and String(hud.quest_offer.get("mode", "")) in ["offer", "instant"] and hud.dialog == "quest_offer": return HudScript.QUEST_HOVER_OKAY
	return -1

func quest_confirm():
	var mode := String(hud.quest_offer.get("mode", ""))
	if hud.dialog == "quest_offer" and mode in ["offer", "instant", "complete"]: hud.main.quest_site_accept(int(hud.quest_offer.building))
	close_dialog()

func open_load():
	hud.load_choice = 0 if hud.main.save_exists() else 1
	hud.load_paused = hud.speed != 0
	if hud.load_paused: hud.toggle_pause()
	open_dialog("load")
	load_pick(hud.load_choice)

func load_pick(choice: int):
	hud.load_choice = clampi(choice, 0, 1)
	var path: String = hud.main.save_path(hud.load_choice == 1)
	hud.load_view = {"path": path, "line_1": "", "line_2": "", "game_ms": -1, "error": ""}
	hud.load_picture = null
	if not FileAccess.file_exists(path):
		hud.load_view.error = "No saved game."
		return
	var r: Dictionary = SaveGameFile.read(path)
	if not r.ok:
		hud.load_view.error = String(r.error)
		hud.load_view.line_1 = String(r.error)
		return
	var doc: Dictionary = r.document
	hud.load_view.line_1 = String(doc.get("line_1", doc.get("name", "")))
	hud.load_view.line_2 = String(doc.get("line_2", doc.get("saved_at", "")))
	hud.load_view.game_ms = int(doc.get("game_ms", 0))
	if doc.has("thumbnail"):
		var image := Image.new()
		if image.load_png_from_buffer(Marshalls.base64_to_raw(String(doc.thumbnail))) == OK: hud.load_picture = ImageTexture.create_from_image(image)

func load_hit(local: Vector2) -> int:
	if local.x >= 0x84 and local.x <= 0x104 and local.y >= 0x13e and local.y <= 0x15f: return HudScript.LOAD_BUTTON
	if Rect2(0xb6, 0x171, 30, 30).has_point(local): return HudScript.LOAD_CLOSE
	if local.y >= 0x125 and local.y <= 0x137:
		if local.x >= 0x30 and local.x < 0xc4: return HudScript.LOAD_SAVED
		if local.x >= 0xc4 and local.x < 0x158: return HudScript.LOAD_AUTOSAVE
	return -1

## Load Game: the shown save opens in a new scene (main.gd open_saved_game); a refused save stays on the sheet with its
## message (an unknown version, a damaged file).
func load_press() -> bool:
	if hud.load_view.get("error", "") != "" or not FileAccess.file_exists(String(hud.load_view.get("path", ""))):
		hud.show_message(String(hud.load_view.get("error", "No saved game.")))
		return false
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	var error: String = hud.main.open_saved_game(String(hud.load_view.path))
	if error != "":
		hud.load_view.error = error
		hud.show_message(error)
		return false
	hud.load_paused = false
	close_dialog()
	return true

func close_load():
	if hud.load_paused and hud.speed == 0: hud.toggle_pause()
	hud.load_paused = false

## The quick save with its message. The picture is taken after one drawn frame without the menu (headless: none).
func save_now():
	var picture := PackedByteArray()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var image: Image = hud.get_viewport().get_texture().get_image()
		if image != null and not image.is_empty():
			var side := mini(image.get_width(), image.get_height() * HudScript.LOAD_PICTURE.x / HudScript.LOAD_PICTURE.y)
			var crop := Rect2i((image.get_width() - side) / 2, 0, side, side * HudScript.LOAD_PICTURE.y / HudScript.LOAD_PICTURE.x)
			image = image.get_region(crop)
			image.resize(HudScript.LOAD_PICTURE.x, HudScript.LOAD_PICTURE.y, Image.INTERPOLATE_BILINEAR)
			picture = image.save_png_to_buffer()
	var r: Dictionary = hud.main.quick_save(picture)
	hud.show_message(hud.game_text(int(r.text_id)))

func draw_load_dialog(at: Vector2):
	var sheet := hud.tex("EMDL")
	if sheet != null: hud.draw_texture(sheet, at)
	hud.text(hud.game_text(306), 1, Rect2(at.x + 0xc1 - 193, at.y + 0x19 - 22, 386, 30), HORIZONTAL_ALIGNMENT_CENTER)   # Load Game
	if hud.load_picture != null: hud.draw_texture_rect(hud.load_picture, Rect2(at + Vector2(0x4b, 0x49), Vector2(HudScript.LOAD_PICTURE)), false)
	hud.text(hud.fitted(String(hud.load_view.get("line_1", "")), 2, 380), 2, Rect2(at.x + 0xc4 - 193, at.y + 0x105 - 14, 386, 20), HORIZONTAL_ALIGNMENT_CENTER)
	hud.text(hud.fitted(String(hud.load_view.get("line_2", "")), 2, 380), 2, Rect2(at.x + 0xc4 - 193, at.y + 0x119 - 14, 386, 20), HORIZONTAL_ALIGNMENT_CENTER)
	var choices := [["Saved game", hud.main.save_exists(), HudScript.LOAD_SAVED, 0x7a], ["Autosave", hud.main.save_exists(true), HudScript.LOAD_AUTOSAVE, 0x10e]]
	for i in 2:
		var c: Array = choices[i]
		var font := 7 if not c[1] else (6 if i == hud.load_choice or hud.dialog_hover == c[2] else 5)
		hud.text(String(c[0]), font, Rect2(at.x + int(c[3]) - 70, at.y + 0x12d - 14, 140, 20), HORIZONTAL_ALIGNMENT_CENTER)
	var ready: bool = String(hud.load_view.get("error", "")) == ""
	hud.text(hud.game_text(306), (6 if hud.dialog_hover == HudScript.LOAD_BUTTON else 5) if ready else 7, Rect2(at.x + 0xc4 - 193, at.y + 0x149 - 14, 386, 20), HORIZONTAL_ALIGNMENT_CENTER)
	hud.draw_close(at + Vector2(0xb6, 0x171))

