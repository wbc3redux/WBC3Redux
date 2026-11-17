extends RefCounted
## game_hud.gd's site dialogs (R-1 split of game_hud.gd, no behaviour change): the victory status lines, quest offers,
## the shop, item power lines, box buttons and the hero's inventory sheet. The state stays on the panel
## (game_hud.gd); `hud` is the panel.

const HudScript = preload("res://hud/game_hud.gd")
var hud: HudScript

func _init(scene: HudScript) -> void:
	hud = scene

# ------------------------------------------------------------------------------------------------ S-2: victory, sites
## 0x44e5..: the Victory Conditions dialog names the setup's option and its description (0xac / 0xad, 0xc4 / 0xc5).
func victory_lines() -> Array:
	var strings: Dictionary = hud.canvas.layout.strings
	var option := 0
	if hud.main.skirmish != null: option = int(hud.main.skirmish.options.get("victory", 0))
	var names: Array = strings.get(str(0xac if option < 8 else 0xad), [])
	var lines: Array = strings.get(str(0xc4 if option < 8 else 0xc5), [])
	var index := option if option < 8 else option - 8
	var out: Array = [String(names[index]) if index < names.size() else "Standard Victory"]
	if option == 12: index = 6
	if index < lines.size(): out.append(String(lines[index]))
	if option == 9 or option == 0xb:
		var extra := 5 if option == 9 else 4
		if extra < lines.size() and String(lines[extra]).strip_edges() != "": out.append(String(lines[extra]))
	return out

## 0x497cd0 / 0x4980a0 in text: the countdown at the top of the view and the score rows (Provisional: the original draws them
## with the ERIX / ERNX sprites at places set by the view size).
func draw_victory_status():
	if hud.main.skirmish == null or hud.main.skirmish.over: return
	var left: int = hud.main.skirmish.timer_left_ms()
	if left > 0: hud.text("%02d:%02d" % [left / 60000, left / 1000 % 60], 5, Rect2(740, 8, 120, 20), HORIZONTAL_ALIGNMENT_CENTER)
	var now: int = Time.get_ticks_msec()
	if now >= hud.score_next_ms:                             # 0x429c20: every 1500 ms
		hud.score_next_ms = now + 1500
		hud.score_rows = hud.main.skirmish.score_rows()
	for p in hud.score_rows.size():
		if int(hud.score_rows[p]) >= 0: hud.text("P%d  %d" % [p + 1, int(hud.score_rows[p])], 5, Rect2(1480, 30 + 21 * p, 110, 20))

func open_quest_offer(view: Dictionary):
	hud.quest_offer = view
	hud.open_dialog("quest_offer")

func open_shop(building_id: int):
	hud.shop_building = building_id
	hud.shop_close_state = 0
	hud.shop_close_armed = false
	hud.shop_clicked = false
	hud.shop_check_ms = 0.0
	hud.open_dialog("shop")

## The place under `local` that holds a good (0x56e350 tests +0x144 + 2 * place), else -1.
func shop_hit(local: Vector2) -> int:
	var place := HudScript.shop_place_at(local)
	var goods: Array = hud.main.shop_goods(hud.shop_building)
	return place if place >= 0 and place < goods.size() and int(goods[place].good) != 0 else -1

## 0x56e8f0's two flag rows per place: too expensive (a resource below the price) and no room (a potion count of 9 or more).
func shop_flags() -> Array:
	var out: Array = []
	var goods: Array = hud.main.shop_goods(hud.shop_building)
	var have: Array = hud.main.economy.resources(hud.main.local_player) if hud.main.economy != null else [0, 0, 0, 0]
	var counts := [0, 0]
	if hud.main.hero_match != null: counts = [int(hud.main.hero_match.potions), int(hud.main.hero_match.mana_potion_count())]
	for i in goods.size():
		var price := int(goods[i].price)
		var short := false
		for lane in 4: short = short or int(have[lane]) < price
		out.append({"expensive": short, "no_room": i < 2 and int(counts[i]) >= 9})
	return out

func shop_close():
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	hud.close_dialog()

func shop_mouse(event: InputEventMouse, local: Vector2):
	var inside := Rect2(Vector2.ZERO, HudScript.SHOP_SIZE).has_point(local)
	if event is InputEventMouseMotion:
		if hud.shop_clicked and not inside:                      # 0x56dde0: +0x135 and the cursor outside the dialog
			hud.close_dialog()
			return
		if HudScript.shop_close_hit(local):
			hud.shop_close_state = 2 if hud.shop_close_armed else 1
			hud.dialog_hover = -1
			return
		hud.shop_close_state = 0
		hud.dialog_hover = shop_hit(local)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT): return
	if event.pressed:                                        # 0x56dfc0
		if HudScript.shop_close_hit(local):
			hud.shop_close_armed = true
			hud.shop_close_state = 2
			return
		var place := shop_hit(local)
		if inside and place >= 0:
			hud.dialog_hover = place
			hud.shop_clicked = true
			hud.main.shop_buy(hud.shop_building, place)
		return
	if hud.shop_close_armed and HudScript.shop_close_hit(local):           # 0x56e0b0
		hud.shop_close_armed = false
		shop_close()
		return
	hud.shop_close_armed = false
	if hud.shop_close_state == 2: hud.shop_close_state = 0

## 0x56e2e0 (every 1000 ms): no living local hero, or the shop gone -> the dialog closes.
func shop_check():
	if hud.dialog != "shop" or hud.main == null: return
	var hero_alive: bool = hud.main.hero_unit_id >= 0 and hud.main.combat != null and hud.main.combat.alive(hud.main.combat.fighters.get(hud.main.hero_unit_id))
	var b = hud.main.production.building(hud.shop_building) if hud.main.production != null else null
	if not hero_alive or b == null or b.hit_points <= 0: hud.close_dialog()

func site_dialog_mouse(event: InputEventMouse, local: Vector2):
	if hud.dialog == "shop":
		shop_mouse(event, local)
		return
	if event is InputEventMouseMotion:
		hud.dialog_hover = hud.quest_hover_at(local)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed): return
	if hud.dialog == "quest_offer":
		var mode := String(hud.quest_offer.get("mode", ""))
		var hit := hud.quest_hover_at(local)
		if hit == HudScript.QUEST_HOVER_CLOSE:
			preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
			if mode == "complete": hud.quest_confirm()             # 0x56a840: closing a completion rewards too
			else: hud.close_dialog()
		elif hit == HudScript.QUEST_HOVER_OKAY or mode == "complete": hud.quest_confirm()

## 0x56a150 at a quest site (Q-2: draw_quest_sheet). In continue mode the counter is the player's active quest's.
func draw_quest_offer(at: Vector2):
	var mode := String(hud.quest_offer.get("mode", ""))
	var q = hud.quest()
	hud.draw_quest_sheet(at, mode, hud.quest_offer.get("record", {}), int(q.progress) if q != null and mode == "continue" else 0)

## Text centred on x (a 0x46e3b0 call at (x, y)).
func centred(s: String, font_number: int, x: float, y: float, width: float = 0x1c0):
	hud.text(s, font_number, Rect2(x - width / 2, y - (22 if font_number == 1 else 4), width, 30), HORIZONTAL_ALIGNMENT_CENTER)

func sparkle_counter() -> int:
	return int(Time.get_ticks_msec() / 25)

func draw_shop_dialog(at: Vector2):
	var sheet := hud.tex("EMDK")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, HudScript.SHOP_SIZE), Color(0.1, 0.08, 0.05, 0.92))
	draw_close(at + HudScript.SHOP_CLOSE.position, hud.shop_close_state)
	centred(hud.game_text(0x465), 1, at.x + 0xda, at.y + 0x18)
	var goods: Array = hud.main.shop_goods(hud.shop_building)
	var flags := shop_flags()
	var portraits := hud.item_portraits()
	var rings: Texture2D = preload("res://battle/unit_agent.gd").rings_texture()
	var counter := sparkle_counter()
	for place in range(2, mini(4, goods.size())):
		var good := int(goods[place].good)
		if good <= 0: continue
		var item: Dictionary = preload("res://simulation/hero_effects.gd").item(good)
		var x: float = at.x + HudScript.SHOP_LEFT + HudScript.SHOP_STEP * place
		var drop := 0x14 if int(item.get("iconrow", 0)) in HudScript.SMALL_PICTURE_ROWS else 0
		if portraits != null: hud.draw_texture_rect_region(portraits, Rect2(x, at.y + HudScript.SHOP_TOP + drop, 70, 110), HudScript.item_cell(item))
		var phase := place if int(item.get("level", 0)) == 4 else 3 * place
		var spark := HudScript.sparkle_cell(int(item.get("level", 0)), counter + phase)
		if rings != null and spark.size.x > 0: hud.draw_texture_rect_region(rings, Rect2(x + 0xf, at.y + 0x64, 0x28, 0x2e), spark)
	if hud.dialog_hover >= 0 and hud.dialog_hover < goods.size() and int(goods[hud.dialog_hover].good) != 0 and rings != null:
		var red := bool(flags[hud.dialog_hover].expensive)
		hud.draw_texture_rect_region(rings, Rect2(at.x + HudScript.SHOP_LEFT + HudScript.SHOP_STEP * hud.dialog_hover, at.y + HudScript.SHOP_TOP, 0x46, 0x6e), Rect2(0x2d2, 0xdc if red else 0, 0x46, 0x6e))
	for place in goods.size():
		var label: Array = []
		if bool(flags[place].expensive): label = [0x46d, 0x46e]
		elif bool(flags[place].no_room): label = [0x46f, 0x470]
		for k in label.size(): centred(hud.game_text(label[k]), 20, at.x + 0x52 + HudScript.SHOP_STEP * place, at.y + [0x6c, 0x80][k], 0x5c)
	if hud.dialog_hover >= 0 and hud.dialog_hover < goods.size(): draw_shop_help(at, goods[hud.dialog_hover])
	centred(hud.game_text(0x466), 2, at.x + 0xd8, at.y + 0x151)

## The hovered place's text block of 0x56e8f0.
func draw_shop_help(at: Vector2, entry: Dictionary):
	var good := int(entry.good)
	var cx: float = at.x + 0xdb
	if good == 0:
		centred(hud.game_text(0x464), 5, cx, at.y + 0xe6)
		return
	if good < 0:
		var mana: bool = good == preload("res://simulation/skirmish_shops.gd").MANA_POTION
		var base := 0x46a if mana else 0x467
		centred(hud.game_text(base), 5, cx, at.y + 0xc8)
		centred(hud.game_text(base + 1), 2, cx, at.y + 0xe4)
		var lines := hud.wrapped(hud.game_text(base + 2), 2, 0x10e).slice(0, 3)
		for i in lines.size(): centred(String(lines[i]), 2, cx, at.y + 0xf5 + 18 * i)
		var have := 0
		if hud.main.hero_match != null: have = int(hud.main.hero_match.mana_potion_count()) if mana else int(hud.main.hero_match.potions)
		centred(hud.game_text(0x471).replace("%d", str(have)), 2, cx, at.y + 0xf5 + 18 * lines.size())
	else:
		var item: Dictionary = preload("res://simulation/hero_effects.gd").item(good)
		centred(String(item.get("name", "")), 5, cx, at.y + 0xc8)
		var powers: Array = item.get("powers", [])
		for i in mini(int(item.get("power_count", 0)), powers.size()):
			centred(item_power_line(powers[i]), 2, cx, at.y + 0xe4 + 18 * i)
	var price := int(entry.price)
	if price != 0:
		for x in HudScript.SHOP_PRICE_X: hud.text(str(price), 2, Rect2(at.x + x, at.y + 0x12c - 4, 60, 16))

func game_line(id: int, args: Array = []) -> String:
	return HudScript.c_format(hud.game_text(id), args)

## 0x556fc0(skill, level).
func skill_line(skill: int, level: int) -> String:
	if level < 0: return "No bonus"
	var v: int = preload("res://simulation/hero_effects.gd").skill_term(skill, level, 1)
	if skill == 9:
		return game_line(0x26b, [0.0 if v == 0 else 100.0 - (100.0 / float(v * 2 + 100)) * 100.0])
	if skill >= 10 and skill <= 22:
		var circle := v % 10
		if circle == 0 and v > 0: circle = 10
		if v == 0: return hud.game_text(0x28e)
		if circle == 1: return game_line(0x28a, [1, (v + 9) / 10])
		if circle == 10: return game_line(0x28b, [10, (v + 9) / 10])
		return game_line(0x28c, [circle, (v + 9) / 10])
	var row: Array = HudScript.SKILL_TEXT.get(skill, [0x237, 1, 0])
	return game_line(int(row[0]), [v * int(row[1]) + int(row[2])])

## 0x403a90's line for one power dictionary of items.json.
func item_power_line(power: Dictionary) -> String:
	if String(power.get("text", "")) != "": return String(power.text)
	var kind := int(power.get("type", 0))
	var data := int(power.get("data", 0))
	if HudScript.POWER_TEXT.has(kind): return game_line(int(HudScript.POWER_TEXT[kind]), [data])
	match kind:
		0x2f: return game_line(0x1b5, [data * 10])
		0x37: return game_line(0x1b7, [data * 10])
		0x39: return hud.game_text(0x1d1)
		0x3a: return hud.game_text(0x1d2)
		0xb:
			var f := 0.0 if data == 0 else 100.0 - (100.0 / float(data * 2 + 100)) * 100.0
			return game_line(0x2b5, [-data, -f]) if data < 0 else game_line(0x2b4, [data, f])
		0x62: return game_line(0x1c6, [String(hud.spell_text(data).get("name", ""))]) + game_line(0x1d5, [int(power.get("chance", 0))])
		99:
			if data >= 10 and data <= 22: return game_line(0x1cd + data, [int(power.get("level", 0))])
			return skill_line(data, int(power.get("level", 0)))
	return ""

func draw_box_button(sheet: Texture2D, at: Vector2, index: int, caption: String, centre: Vector2):
	var frame := 1 if hud.dialog_hover == index else 0
	if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(at, Vector2(180, 36)), Rect2(0, 36 * frame, 180, 36))
	# Playtest 2026-11-10: the caption sat on the button's upper rope; it is centred between the ropes (sprite middle
	# at + 18; the 0x..ea centre words sit 5 pixels above it), measured on a render.
	hud.text(caption, 5, Rect2(centre.x - 90, centre.y - 5, 180, 20), HORIZONTAL_ALIGNMENT_CENTER)

func draw_close(at: Vector2, frame: int = 0):
	var sheet := hud.tex("EMDC")
	if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(at, Vector2(30, 30)), Rect2(0, 30 * frame, 30, 30))

func inventory_hit(local: Vector2) -> int:
	for k in HudScript.INVENTORY_SLOTS.size():
		var r: Rect2 = HudScript.INVENTORY_SLOTS[k]
		if local.x >= r.position.x and local.x <= r.end.x and local.y >= r.position.y and local.y <= r.end.y: return k
	return -1

func inventory_close_hit(local: Vector2) -> bool:
	return local.x >= HudScript.INVENTORY_CLOSE.position.x and local.x < HudScript.INVENTORY_CLOSE.end.x and local.y >= HudScript.INVENTORY_CLOSE.position.y and local.y < HudScript.INVENTORY_CLOSE.end.y

func inventory_mouse(event: InputEvent, local: Vector2):
	if event is InputEventMouseMotion:
		hud.dialog_hover = HudScript.INVENTORY_HOVER_CLOSE if inventory_close_hit(local) else inventory_hit(local)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT): return
	if event.pressed:
		hud.inventory_close_armed = inventory_close_hit(local)
		return
	if hud.inventory_close_armed and inventory_close_hit(local):
		hud.inventory_close_armed = false
		preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
		hud.close_dialog()
		return
	hud.inventory_close_armed = false
	hud.main.inventory_release(inventory_hit(local))

func draw_inventory_dialog(at: Vector2):
	var sheet := hud.tex("EMDD")
	if sheet != null: hud.draw_texture(sheet, at)
	else: hud.draw_rect(Rect2(at, Vector2(708, 345)), Color(0.08, 0.06, 0.05, 0.9))
	var portraits := hud.item_portraits()
	var selected: int = int(hud.main.inventory.get("selected", -1)) if hud.main.inventory is Dictionary else -1
	for k in 15:
		var r: Rect2 = HudScript.INVENTORY_SLOTS[k]
		var slot: Dictionary = hud.main.inventory_slot(k)
		if not slot.is_empty() and portraits != null:
			var item: Dictionary = preload("res://simulation/hero_effects.gd").item(int(slot.item))
			if not item.is_empty():
				# 0x55fb90: IDLG column iconcol + 1; in a 110-high slot rows 5, 6, 7, 9, 10 sit 0x14 lower (Read).
				var drop := 0x14 if r.size.y > 70 and int(item.get("iconrow", 0)) in HudScript.SMALL_PICTURE_ROWS else 0
				var cell := HudScript.item_cell(item)
				hud.draw_texture_rect_region(portraits, Rect2(at + r.position + Vector2(0, drop), Vector2(70, r.size.y - drop)),
					Rect2(cell.position, Vector2(70, r.size.y - drop)))
				var level := int(item.get("level", 0))
				var spark := HudScript.sparkle_cell(level, sparkle_counter() + (k if level == 4 else 3 * k))
				var rings: Texture2D = preload("res://battle/unit_agent.gd").rings_texture()
				if rings != null and spark.size.x > 0:
					hud.draw_texture_rect_region(rings, Rect2(at + r.position + Vector2(0xf, (0x20 if k >= 11 else drop + 0xc)), Vector2(0x28, 0x2e)), spark)
		if k == selected: hud.draw_rect(Rect2(at + r.position, r.size).grow(-1), Color(1, 0.9, 0.55), false, 2.0)
	# 0x55fb90 (Read): "Backpack" [0871] and "Ground" [0870] in font 5 centred at (0x21c, 7) / (0x21c, 0xa2); the healing
	# and mana potion counts ("%d", 0x60b72c) in font 5 from (0x41, 0x3d) / (0x147, 0x3d).
	centred(hud.game_text(0x367), 5, at.x + 0x21c, at.y + 7, 300)
	centred(hud.game_text(0x366), 5, at.x + 0x21c, at.y + 0xa2, 300)
	if hud.main.hero_match != null:
		var counts := [int(hud.main.hero_match.potions), int(hud.main.hero_match.mana_potion_count())]
		for i in 2: hud.text(str(counts[i]), 5, Rect2(at.x + [0x41, 0x147][i], at.y + 0x3d - 4, 60, 20))
	var close_frame := 0
	if hud.dialog_hover == HudScript.INVENTORY_HOVER_CLOSE: close_frame = 2 if hud.inventory_close_armed else 1
	draw_close(at + HudScript.INVENTORY_CLOSE.position, close_frame)
	draw_inventory_help(at)

func draw_inventory_help(at: Vector2):
	if hud.settings != null and hud.settings.get_value("HelpLevel") == 0: return
	if hud.dialog_hover < 0 or hud.dialog_hover >= 15: return
	var slot: Dictionary = hud.main.inventory_slot(hud.dialog_hover)
	if slot.is_empty(): return
	var item: Dictionary = preload("res://simulation/hero_effects.gd").item(int(slot.item))
	if item.is_empty(): return
	var lines: Array = [String(item.get("name", ""))]
	lines.append_array(hud.wrapped(String(item.get("description", "")), 5, 300))
	var r: Rect2 = HudScript.INVENTORY_SLOTS[hud.dialog_hover]
	var box := Rect2(at + r.position + Vector2(r.size.x + 6, 0), Vector2(312, 8 + 18 * lines.size()))
	if box.end.x > hud.virtual_width() - hud.panel_x: box.position.x = at.x + r.position.x - box.size.x - 6
	hud.draw_rect(box, Color(0, 0, 0, 0.75))
	for i in lines.size(): hud.text(String(lines[i]), 5, Rect2(box.position.x + 6, box.position.y + 4 + 18 * i, 300, 18))

