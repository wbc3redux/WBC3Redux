extends RefCounted
## game_hud.gd's round buttons (R-1 split of game_hud.gd, no behaviour change): the round buttons, the spellbook and
## diplomacy rows, the Attitude dialog, the hero's spells (costs, casts, hot keys, the choice dialog). The state
## stays on the panel (game_hud.gd); `hud` is the panel.
const Assets = preload("res://core/asset_store.gd")

const HudScript = preload("res://hud/game_hud.gd")
var hud: HudScript

func _init(scene: HudScript) -> void:
	hud = scene

# ------------------------------------------------------------------------------------------------ round buttons
func round_at(v: Vector2) -> String:
	for kind in HudScript.ROUND:
		var r: Rect2 = HudScript.ROUND[kind]
		if Rect2(r.position + Vector2(0, hud.oy()), r.size).has_point(v): return kind
	return ""

## 0x4d5d10 (release) and the KeyMap keys i / s / q / Alt+G / Alt+D. Returns false when nothing opens.
func press_round(kind: String) -> bool:
	match kind:
		"inventory":
			preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
			hud.main.toggle_hero_items()
		"spellbook":
			if not hero_knows_spells(): return false
			open_spellbook()
		"menu": hud.open_dialog("menu")
		"diplomacy":
			hud.diplomacy = {"amount": -1, "resource": -1, "player": -1, "sent": false}
			hud.open_dialog("diplomacy")
		"quest":
			if quest() == null:
				hud.show_message(hud.game_text(187))                     # Sorry.  No quests are currently available...
				return false
			hud.open_dialog("quest")
		_: return false
	return true

## 0x709300: the local hero's thirteen school levels (skills 10..22 plus item powers); empty without a living hero.
func hero_schools() -> Array:
	if hud.main.combat == null or hud.main.hero_unit_id < 0: return []
	var f = hud.main.combat.fighters.get(hud.main.hero_unit_id)
	if f == null or not hud.main.combat.alive(f): return []
	var own: Dictionary = hud.main.combat.hero_block(hud.main.local_player)
	return Array(preload("res://simulation/hero_effects.gd").hero_unit(own).schools) if not own.is_empty() else []

## 0x4cde10(hero, null): any school above 0.
func hero_knows_spells() -> bool:
	return hero_schools().any(func(level): return int(level) > 0)

func open_spellbook():
	var schools := hero_schools()
	if not HudScript.spell_known(schools, hud.spell_school * 10): step_school(1)
	hud.spell_hover = -1
	hud.spell_key_ms = Time.get_ticks_msec()          # 0x56f910 stamps param_1[0x51] once; the digits wait 150 ms after it
	hud.open_dialog("spellbook")

## 0x56fd80 arrows: the previous / next school with a known first spell, wrapping over the thirteen.
func step_school(step: int):
	var schools := hero_schools()
	for i in 13:
		hud.spell_school = posmod(hud.spell_school + step, 13)
		if HudScript.spell_known(schools, hud.spell_school * 10): return

func spell_row_at(local: Vector2) -> int:
	if local.x < 0x2d or local.x >= 0x10d or local.y < 100 or local.y >= 0x14a: return -1
	var row := int(local.y - 100) / 0x17
	return row if row < 10 else -1

func spellbook_press(local: Vector2) -> bool:
	var audio = preload("res://core/audio_manager.gd").instance(hud.get_tree())
	if Rect2(0x120, 0x17e, 30, 30).has_point(local): hud.close_dialog()
	elif Rect2(0x33, 0x14, 0x46, 0x3e).has_point(local): step_school(-1)
	elif Rect2(0x1df, 0x13, 0x46, 0x3e).has_point(local): step_school(1)
	else:
		var row := spell_row_at(local)
		if row < 0 or not spell_row_enabled(hud.spell_school * 10 + row): return false
		hud.close_dialog()
		cast_hero_spell(hud.spell_school * 10 + row)
	audio.click()
	return true

func spell_text(spell: int) -> Dictionary:
	var spells: Array = hud.canvas.layout.get("spells", {}).get("spells", [])
	return spells[spell] if spell >= 0 and spell < spells.size() else {"name": "", "desc": ""}

## 0x558e20: the diplomacy hit under a dialog-relative point: 0..5 amount, 6..9 cart, 10 + p player, 16 Send, 17 close.
func diplomacy_hit(local: Vector2) -> int:
	if Rect2(0xcd, 0x171, 0x1e, 0x1e).has_point(local): return 17
	for k in 6:
		if local.x >= 0x4c and local.x <= 0x7a and local.y > 0x81 + 0x1b * k and local.y < 0x9c + 0x1b * k: return k
	for k in 4:
		if local.x > 0x92 and local.x < 199 and local.y > 0x79 + 0x2e * k and local.y < 0xa7 + 0x2e * k: return 6 + k
	for p in diplomacy_players():
		if local.x >= 0xe4 and local.x <= 0x16e and local.y > 0x6b + 0x23 * p and local.y < 0x8e + 0x23 * p: return 10 + p
	if local.x >= 0x5d and local.x <= 0x15a and local.y >= 0x151 and local.y <= 0x171: return 16
	return -1

## The players resources can go to: active, not the local player, not eliminated (0x708f94, 0x748668); 0x558e20 walks
## the first six player records (0x708f94 .. 0x70909b, 0x2c apart), one row each.
func diplomacy_players() -> Array:
	var out: Array = []
	var match_state = hud.main.skirmish
	for p in 6:
		if p == hud.main.local_player: continue
		if match_state != null and (not match_state.active(p) or bool(match_state.eliminated[p])): continue
		if match_state == null and (hud.main.economy == null or not hud.main.economy.stockpiles.has(p)): continue
		out.append(p)
	return out

func diplomacy_press(hit: int) -> bool:
	if hit < 0: return false
	preload("res://core/audio_manager.gd").instance(hud.get_tree()).click()
	if hit == 17:
		hud.close_dialog()
		return true
	if hit < 6: hud.diplomacy.amount = hit
	elif hit < 10: hud.diplomacy.resource = hit - 6
	elif hit < 16: hud.diplomacy.player = hit - 10
	else: send_resources()
	if hit < 16: hud.diplomacy.sent = false
	return true

## 0x559690: send the chosen amount of the chosen resource to the chosen player when the stock covers it.
func send_resources() -> bool:
	if int(hud.diplomacy.amount) < 0 or int(hud.diplomacy.resource) < 0 or int(hud.diplomacy.player) < 0: return false
	var cost := [0, 0, 0, 0]
	cost[HudScript.SEND_LANE[int(hud.diplomacy.resource)]] = int(HudScript.SEND_AMOUNTS[int(hud.diplomacy.amount)])
	if not hud.main.economy.try_spend(hud.main.local_player, cost): return false
	hud.main.economy.credit(int(hud.diplomacy.player), cost)
	hud.diplomacy = {"amount": -1, "resource": -1, "player": -1, "sent": true}
	return true

## A player's name for the diplomacy rows (Provisional): the setup name, else the race (the skirmish menu's race lists,
## TXT strings 0xf and 0x68).
func player_label(p: int) -> String:
	if hud.main.skirmish == null: return "Player %d" % (p + 1)
	var slot: Dictionary = hud.main.skirmish.slots[p]
	if String(slot.get("name", "")) != "": return String(slot.name)
	var race: int = hud.main.skirmish.race(p)
	var names: Array = hud.canvas.layout.strings.get(str(15 if race < 8 else 104), [])
	return String(names[race % 8]) if race >= 0 and race < 16 and race % 8 < names.size() else "Player %d" % (p + 1)

## 0x744db8 + player * 0x818: the local player's active quest, or null.
func quest():
	if hud.main.encounters == null: return null
	return hud.main.encounters.quests.get(hud.main.local_player)

func info_index(local: Vector2) -> int:
	var col := int((local.x - 6) / 42)
	var row := int((local.y - 6) / 46)
	if col < 0 or col >= 8 or row < 0 or row >= 3: return -1
	return row * 8 + col

func attitude_rows() -> Array:
	if hud.main == null or hud.main.combat == null: return []
	var rows: Array = hud.main.combat.ai.scripts.duplicate()
	rows.sort_custom(func(a, b): return String(a.name) < String(b.name))
	return rows

func open_attitude():
	var v: Vector2 = hud.get_local_mouse_position() / hud.scale_factor if hud.scale_factor != 0 else Vector2.ZERO
	hud.attitude_rect = HudScript.attitude_place(v, attitude_rows().size(), Vector2(hud.get_viewport_rect().size) / hud.scale_factor)
	hud.attitude_pressed = false
	hud.open_dialog("attitude")

## 0x559d20: the row at a point of the panel, -1 outside the list.
func attitude_row_at(local: Vector2) -> int:
	if local.x < 0 or local.x >= hud.attitude_rect.size.x or local.y < HudScript.ATTITUDE_TOP: return -1
	var row := int((local.y - HudScript.ATTITUDE_TOP) / HudScript.ATTITUDE_ROW)
	return row if row < attitude_rows().size() else -1

## 0x534070: the selected units take the script, their guard point their cell (0x506f10).
func assign_attitude(index: int) -> int:
	var count := 0
	for u in hud.main.selected_units():
		var f = hud.main.combat.fighters.get(u.unit_id)
		if f == null or f.owner != hud.main.local_player: continue
		hud.main.combat.ai.assign_script(f, index)
		count += 1
	if count > 0 and bool(hud.main.combat.ai.scripts[index].get("uses_leader", 0)): hud.main.arm_target(5)
	return count

## 0x534140: the script of the selected units, -1 when they differ.
func selection_attitude() -> int:
	var script := -1
	for u in hud.main.selected_units():
		var f = hud.main.combat.fighters.get(u.unit_id)
		if f == null: continue
		if script >= 0 and int(f.script) != script: return -1
		script = int(f.script)
	return script

func attitude_mouse(event: InputEventMouse, local: Vector2):
	if event is InputEventMouseMotion:
		hud.dialog_hover = attitude_row_at(local)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT): return
	if event.pressed:
		hud.attitude_pressed = true
		var row := attitude_row_at(local)
		if row >= 0: assign_attitude(int(attitude_rows()[row].index))
	elif hud.attitude_pressed:
		hud.close_dialog()

func draw_attitude_dialog(at: Vector2):
	var rows: Array = attitude_rows()
	var sheet := hud.tex("EMDB")
	var bands := int(hud.attitude_rect.size.y) >> 4
	for i in bands:
		var frame := 2
		if i == 0: frame = 0
		elif i == 1: frame = 1
		elif i == bands - 2: frame = 3
		elif i == bands - 1: frame = 4
		if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(at + Vector2(0, i * 16), Vector2(HudScript.ATTITUDE_WIDTH, 16)), Rect2(0, frame * 16, HudScript.ATTITUDE_WIDTH, 16))
		else: hud.draw_rect(Rect2(at + Vector2(0, i * 16), Vector2(HudScript.ATTITUDE_WIDTH, 16)), Color(0.1, 0.08, 0.05))
	var current := selection_attitude()
	var icons: Texture2D = preload("res://battle/unit_agent.gd").digits_texture()
	for row in rows.size():
		var script: Dictionary = rows[row]
		var y: float = at.y + HudScript.ATTITUDE_TOP + row * HudScript.ATTITUDE_ROW
		if int(script.index) == current: hud.draw_rect(Rect2(at.x + 10, y, 0xaf, 0x10), Color(0.2, 0.2, 0.2, 0.5))
		if row == hud.dialog_hover: hud.draw_rect(Rect2(at.x + 9, y - 1, 0xae, HudScript.ATTITUDE_ROW), Color(1, 1, 1, 0.25), false, 1.0)
		if icons != null: hud.draw_texture_rect_region(icons, Rect2(at.x + 10, y, 16, 16), Rect2((int(script.id) + 5) * 16, 0x28, 16, 16))
		hud.text(hud.game_text(int(script.name_string)), 5, Rect2(at.x + 0x20, y - 4, 0x90, 18))
	if hud.dialog_hover >= 0 and hud.dialog_hover < rows.size():
		hud.text(hud.game_text(int(rows[hud.dialog_hover].name_string) + 1), 2, Rect2(at.x + 0xc0, at.y + HudScript.ATTITUDE_TOP, HudScript.ATTITUDE_WIDTH - 0xcc, 90))

func hero_spell_world():
	return hud.main.combat.spells.hero_spells if hud.main.combat != null and hud.main.combat.spells != null else null

func spell_affordable(spell: int) -> bool:
	if hud.main.combat == null or hud.main.combat.spells == null: return false
	var sp = hud.main.combat.spells
	if sp.cheat: return true
	var f = hud.main.combat.fighters.get(hud.main.hero_unit_id)
	if f == null: return false
	return sp.cost(f, spell) <= sp.hero_pool(hud.main.local_player)

func spell_row_enabled(spell: int) -> bool:
	var cheat: bool = hud.main.combat != null and hud.main.combat.spells != null and hud.main.combat.spells.cheat
	return (cheat or HudScript.spell_known(hero_schools(), spell)) and spell_affordable(spell)

## 0x5717e0 for the local hero; a placement or a dialog waits for the player.
func cast_hero_spell(spell: int) -> Dictionary:
	var hs = hero_spell_world()
	if hs == null or hud.main.hero_unit_id < 0: return {"cast": false, "reason": "no hero"}
	return spell_request_shown(spell, hs.cast_request(hud.main.hero_unit_id, spell))

## 0x5717e0 opens the placement or the dialog itself, whoever asked (the book, its digits, the hot keys: REVIEW_HERO_SPELLS
## D1): the HUD side of a cast request's result.
func spell_request_shown(spell: int, result: Dictionary) -> Dictionary:
	match String(result.get("pending", "")):
		"place": hud.show_message("%s: choose a place" % spell_text(spell).name)   # Provisional prompt (the cursor 0x425150 is not drawn)
		"champion", "rune", "weather", "elemental": hud.open_dialog("spell_choice")   # B1-6c: modes 9 / 10
	if String(result.get("reason", "")) == "not built yet": hud.show_message("%s is not in this build yet" % spell_text(spell).name)
	return result

func open_spell_trade(rate: int, title: String, close: bool):
	hud.market = {"from": int(hud.spell_trade_memory.from), "to": int(hud.spell_trade_memory.to), "amount": int(hud.spell_trade_memory.amount),
		"rate": rate, "title": title, "close": close}
	hud.open_dialog("market")

## The h key (0x561d80): the local hero drinks a healing potion (HeroSpells.drink_potion).
## KeyMap.txt line 22 "h Healing Potion" -> 0x427fb0 case 0xc; line 60 "m Mana Potion" -> case 0x32 (0x561c30). The
## original has no other potion control on the panel: besides these keys only the inventory's two potion slots
## (0x55ecc0) and the computer hero (0x503c60) call the two drinks (every E8 call in the image, Read).
func drink_hero_potion() -> bool:
	var hs = hero_spell_world()
	if hs != null: hs.drink_potion(hud.main.local_player)
	return true

## The m key (0x561c30): the local hero drinks a mana potion (HeroSpells.drink_mana_potion).
func drink_hero_mana_potion() -> bool:
	var hs = hero_spell_world()
	if hs != null: hs.drink_mana_potion(hud.main.local_player)
	return true

func spellbook_key(event: InputEventKey) -> bool:
	if event.keycode >= KEY_F1 and event.keycode <= KEY_F8:
		if hud.spell_hover < 0: return true
		var spell := hud.spell_school * 10 + hud.spell_hover
		if not HudScript.spell_known(hero_schools(), spell): return true
		var hs = hero_spell_world()
		if hs != null: hs.assign_hotkey(hud.main.local_player, int(event.keycode - KEY_F1), spell)
		return true
	if event.keycode >= KEY_0 and event.keycode <= KEY_9 and not event.ctrl_pressed:
		var now := Time.get_ticks_msec()
		if now < hud.spell_key_ms + 150: return true
		var row := 9 if event.keycode == KEY_0 else int(event.keycode - KEY_1)
		var spell := hud.spell_school * 10 + row
		if HudScript.spell_known(hero_schools(), spell):
			hud.close_dialog()
			cast_hero_spell(spell)
		return true
	return false

func spell_hotkey_slot(spell: int) -> int:
	var hs = hero_spell_world()
	if hs == null: return -1
	return hs.hotkey_slots(hud.main.local_player).find(spell)

## The choice dialog (0x55bc90 with DAT_0061b538 = AUXX AUMX AUGX AUAX for Raise Champion, the four items of 0x5720b0
## for Rune Item): the box, the spell's name and four icons; a click picks, the close button or Esc cancels.
func spell_choice_rects(at: Vector2) -> Array:
	var out: Array = []
	var hs = hero_spell_world()
	var size := Vector2(70, 110) if hs != null and String(hs.pending.get("mode", "")) == "rune" else Vector2(90, 90)
	var left := at.x + (586 - (4 * size.x + 3 * 20)) / 2
	for i in 4: out.append(Rect2(left + i * (size.x + 20), at.y + 0x60, size.x, size.y))
	return out

func spell_choice_at(local: Vector2) -> int:
	var rects := spell_choice_rects(Vector2.ZERO)
	for i in rects.size():
		if rects[i].has_point(local): return i
	return -1

func spell_choice_press(local: Vector2):
	if Rect2(0x125, 0x10e, 30, 30).has_point(local):
		choose_spell_option(-1)
		return
	var i := spell_choice_at(local)
	if i >= 0: choose_spell_option(i)

func choose_spell_option(i: int):
	hud.close_dialog()
	var hs = hero_spell_world()
	if hs != null: hs.choose(i)

func draw_spell_choice_dialog(at: Vector2):
	var hs = hero_spell_world()
	var box := hud.tex("EMDM")
	if box != null: hud.draw_texture(box, at)
	if hs == null or hs.pending.is_empty(): return
	hud.text(String(spell_text(int(hs.pending.spell)).name), 1, Rect2(at.x, at.y + 0x3a - 22, 586, 30), HORIZONTAL_ALIGNMENT_CENTER)
	var rects := spell_choice_rects(at)
	var choices: Array = hs.pending.get("choices", [])
	for i in mini(4, choices.size()):
		var r: Rect2 = rects[i]
		if String(hs.pending.mode) == "rune":
			var item: Dictionary = preload("res://simulation/hero_effects.gd").item(int(choices[i]))
			var sheet := item_portraits()
			if sheet != null and not item.is_empty():
				hud.draw_texture_rect_region(sheet, r, HudScript.item_cell(item))
			if i == hud.dialog_hover: hud.text(String(item.get("name", "")), 19, Rect2(at.x, at.y + 0xd8, 586, 20), HORIZONTAL_ALIGNMENT_CENTER)
		elif String(hs.pending.mode) == "weather":
			# B1-6c: Change Weather's four EWTH icons (0x55bc90 with EWTH x 4; which frame each shows is Open: Provisional
			# labels after the kind 4 amounts 0..3, B1-3's DayNight.apply_record).
			hud.draw_rect(r, Color(0.1, 0.1, 0.15, 0.6))
			hud.text(HudScript.WEATHER_LABELS[i], 19, r, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			var sheet := hud.icon_sheet(String(choices[i]))
			if sheet != null: hud.draw_texture_rect_region(sheet, r, Rect2(0, 190, 90, 90))
			if i == hud.dialog_hover: hud.text(hud.display_name(String(choices[i])), 19, Rect2(at.x, at.y + 0xd8, 586, 20), HORIZONTAL_ALIGNMENT_CENTER)
		if i == hud.dialog_hover: hud.draw_rect(r.grow(2), Color(1, 0.85, 0.4), false, 1.0)
	hud.draw_close(at + Vector2(0x125, 0x10e))

## The item portraits IDLG (70 x 110 cells; art.json effects "IDLG").
func item_portraits() -> Texture2D:
	if not hud.textures.has("IDLG"):
		var record: Dictionary = preload("res://core/art_data.gd").data().get("effects", {}).get("IDLG", {})
		hud.textures["IDLG"] = Assets.texture(String(record.texture)) if record.has("texture") else null
	return hud.textures["IDLG"]

## C1 (DELIBERATE MODERN CHANGE, modern_rules.gd "Casting", off by default): spells.gd pause_changed.
func spell_pause_hook(paused: bool):
	if hud.main.combat == null or hud.main.combat.spells == null: return
	var keep: bool = preload("res://simulation/modern_rules.gd").casting()
	if not paused and keep: return
	if not keep and hud.dialog == "spell_choice": hud.close_dialog()
	hud.main.combat.spells.pause_changed(paused, keep)

