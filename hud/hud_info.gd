extends RefCounted
## game_hud.gd's info area (R-1 split of game_hud.gd, no behaviour change): the hero's portrait and bars, the quest
## timer, unit, building, tower and mine information, garrison faces, the production queue, the selection list and
## the cell grid. The state stays on the panel (game_hud.gd); `hud` is the panel.
const Assets = preload("res://core/asset_store.gd")

const HudScript = preload("res://hud/game_hud.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
var hud: HudScript

func _init(scene: HudScript) -> void:
	hud = scene

func team_colour(ramps: Array, owner: int) -> Color:
	var colour: int = preload("res://core/art_data.gd").player_colour(owner) if owner >= 0 else -1
	if colour < 0 or colour >= ramps.size(): return Color(0.85, 0.8, 0.55)
	var c: Array = ramps[colour][14]
	return Color8(mini(255, int(c[0]) * 2), mini(255, int(c[1]) * 2), mini(255, int(c[2]) * 2))   # the ramp's brightest step

func draw_hero(y: float):
	var rect := Rect2(HudScript.PORTRAIT.position + Vector2(0, y), HudScript.PORTRAIT.size)
	var hero = hud.main.unit_by_id(hud.main.hero_unit_id) if hud.main.hero_unit_id >= 0 else null
	var f = hud.main.combat.fighters.get(hud.main.hero_unit_id) if hud.main.combat != null and hud.main.hero_unit_id >= 0 else null
	var alive: bool = hero != null and f != null and hud.main.combat.alive(f)
	var portrait: Texture2D = null
	if hud.main.hero_match != null and hud.main.hero_match.profile != null:
		portrait = hud.tex("Portrait%02d.bmp" % int(hud.main.hero_match.profile.data.portrait_id))
	if not alive: portrait = hud.tex("Panel_HeroDead.bmp")
	if portrait != null: hud.draw_texture_rect(portrait, rect, false)
	var bars := hud.tex("Panel_Bars.bmp")
	if bars == null: return
	var hp_fraction := float(f.hp) / maxf(1.0, float(f.max_hp)) if alive else 0.0
	var xp_fraction := 0.0
	if hud.main.hero_match != null and hud.main.hero_match.profile != null:
		var level := int(hud.main.hero_match.profile.data.level)
		var low := float(preload("res://simulation/hero_rules.gd").xp_threshold(level))
		var high := float(preload("res://simulation/hero_rules.gd").xp_threshold(level + 1))
		xp_fraction = clampf((float(hud.main.hero_match.profile.data.xp) - low) / maxf(1.0, high - low), 0.0, 1.0)
	# Parity pass 4 (0x4d7710, Read): fills are width * value / maximum in integers; the mana bar shows the record's
	# mana (0x70931c / 0x70931a, combat.gd _regenerate_mana).
	var mana: int = int(f.get("mana", 0)) if alive else 0
	var max_mana: int = int(f.get("max_mana", 0)) if alive else 0
	var rows := [[0, 11, hp_fraction], [22, 11, float(mana) / maxf(1.0, float(max_mana))], [44, 4, xp_fraction]]   # health, mana, XP
	for i in 3:
		var r: Rect2 = HudScript.BARS[i]
		var at := Vector2(r.position.x, r.position.y + y)
		hud.draw_texture_rect_region(bars, Rect2(at, r.size), Rect2(0, rows[i][0] + rows[i][1], 98, rows[i][1]))
		var w: int = clampi(int(98.0 * float(rows[i][2]) + 0.000001), 0, 98)
		if i == 0 and alive: w = clampi(98 * int(f.hp) / maxi(1, int(f.max_hp)), 0, 98)
		if i == 1: w = clampi(98 * mana / maxi(1, max_mana), 0, 98)
		if w > 0: hud.draw_texture_rect_region(bars, Rect2(at, Vector2(w, r.size.y)), Rect2(0, rows[i][0], w, rows[i][1]))
	if alive:
		var thousands: int = (int(f.hp) / 1000) % 10
		draw_bar_number(int(f.hp), thousands, Vector2(HudScript.BARS[0].position.x, HudScript.BARS[0].position.y + y))
		draw_bar_number(mana, thousands, Vector2(HudScript.BARS[1].position.x, HudScript.BARS[1].position.y + y))   # the original reuses life's thousands digit
	else:
		# A dead hero (0x4d7710): both bars empty, each with SkillIcons' small 0 (0xa0, 0x21, 5 x 7) at +4 / +3.
		var digits: Texture2D = preload("res://battle/unit_agent.gd").digits_texture()
		if digits != null:
			for i in 2: hud.draw_texture_rect_region(digits, Rect2(Vector2(HudScript.BARS[i].position.x + 4, HudScript.BARS[i].position.y + y + 3), Vector2(5, 7)), Rect2(0xa0, 0x21, 5, 7))
	# The frame piece BM_OVERHERO (Panel_OverHero.bmp, 24 x 42) over the portrait's left edge, alive or dead (0x4d7710).
	var over := hud.tex("Panel_OverHero.bmp")
	if over != null: hud.draw_texture(over, rect.position - Vector2(2, 0))
	draw_quest_timer(rect.position)

## 0x4d7710 (Read, decompile 141291..141318): while the local player holds a quest (0x744db8), the portrait shows the quest
## goblet (SkillIcons 0x104, 0x13, 18 x 21) at +2, +0x4c and the seconds left (deadline 0x744dbc - now, at least 0) in the
## orange digits (0xb8 + 6 d, 0x19, 6 x 8): n = 3 / 2 / 1 digits by the hundreds and tens (thousands are not shown),
## drawn right to left from x + (3 n + 9) * 2, y + 0x53.
func draw_quest_timer(at: Vector2):
	var q = hud.quest()
	var sheet: Texture2D = preload("res://battle/unit_agent.gd").digits_texture()
	if q == null or sheet == null or hud.main.combat == null: return
	hud.draw_texture_rect_region(sheet, Rect2(at + Vector2(2, 0x4c), Vector2(0x12, 0x15)), Rect2(0x104, 0x13, 0x12, 0x15))
	for d in HudScript.quest_timer_digits(int(q.deadline_ms), int(hud.main.combat.now_ms)):
		hud.draw_texture_rect_region(sheet, Rect2(at + Vector2(d.x, 0x53), Vector2(6, 8)), Rect2(0xb8 + 6 * int(d.digit), 0x19, 6, 8))

## 0x4d7710: a bar's value in SkillIcons.bmp digits (bitmap 0x141, digit d at (0xb8 + 6 d, 0x10), 6 x 9), drawn right to left
## from x + 6 n - 2, y + 1; n = 4 when the thousands digit is set, else 3 / 2 / 1 by the hundreds and tens digits.
func draw_bar_number(value: int, thousands: int, at: Vector2):
	var sheet: Texture2D = preload("res://battle/unit_agent.gd").digits_texture()
	if sheet == null: return
	var digits := [value % 10, (value / 10) % 10, (value / 100) % 10, thousands]
	var n := 4 if thousands != 0 else (3 if digits[2] != 0 else (2 if digits[1] != 0 else 1))
	var x := 6 * n - 2
	for k in n:
		hud.draw_texture_rect_region(sheet, Rect2(at + Vector2(x, 1), Vector2(6, 9)), Rect2(0xb8 + 6 * int(digits[k]), 0x10, 6, 9))
		x -= 6

## The 'i' sheet of a unit or building: the UI export of the Knights roster, else the art import's slot 8 sheet (every
## race the art import covers; parity pass 3: the Dwarf build dialog showed grey boxes with names).
func icon_sheet(type_id: String) -> Texture2D:
	var t := hud.tex(type_id + "i")
	if t != null: return t
	var key := "icon:" + type_id
	if not hud.textures.has(key):
		var record: Dictionary = preload("res://core/art_data.gd").data().get("icons", {}).get(type_id, {})
		hud.textures[key] = Assets.texture(String(record.texture)) if record.has("texture") else null
	return hud.textures[key]

func draw_info(y: float):
	var area := Rect2(HudScript.INFO.position + Vector2(0, y), HudScript.INFO.size)
	var units: Array = hud.main.selected_units()
	var building = hud.main.selected_building()
	# 0x4dd0c0 (1280 and 1600 modes, 0x74c40f): the info area follows the object under the cursor. Provisional: shown only
	# while nothing is selected (the panel flag +0x138 that enables it is not traced).
	var mine_id: int = int(hud.main.get("selected_mine_id")) if units.is_empty() and building == null and hud.main.get("selected_mine_id") != null else -1
	if units.is_empty() and building == null and mine_id < 0 and not hud.main.hover_info.is_empty():
		if hud.main.hover_info.kind == "unit": units = [hud.main.hover_info.object]
		elif hud.main.hover_info.kind == "mine": mine_id = int(hud.main.hover_info.object)
		else: building = hud.main.hover_info.object
	if mine_id >= 0 and hud.main.mines != null and hud.main.mines.mines.has(mine_id):
		draw_mine_info(mine_id, area, y)
	elif units.is_empty() and building != null and queue_view(building):
		draw_queue(building, y)
	elif units.size() == 1 or (units.is_empty() and building != null):
		var type_id: String = units[0].type_id if not units.is_empty() else String(building.original_type_id)
		var sheet := icon_sheet(type_id)
		var centre := HudScript.INFO_ICON_CENTRE + Vector2(0, y)
		if sheet != null:
			# HUD pass: the part of the picture outside the area is cut off (the source rectangle follows the cut, so the
			# picture is not squeezed into the area).
			var size := 144.0 if not HudScript.ProductionRules_is_building(type_id) else 140.0
			var whole := Rect2(centre - Vector2(size, size) / 2.0, Vector2(size, size))
			var shown := whole.intersection(area)
			if shown.has_area(): hud.draw_texture_rect_region(sheet, shown, Rect2(shown.position - whole.position, shown.size))
		if not units.is_empty():
			draw_unit_info(units[0], area)
		else:
			draw_building_rows(building, y)
		if hud.main.conversions != null and units.is_empty():
			var percent: int = hud.main.conversions.keep_progress(building, hud.main.game_ms())
			if percent > 0: hud.draw_converting(area.position, percent, false)
	elif units.size() > 1:
		draw_selection_list(units, y)

func draw_mine_info(mine_id: int, area: Rect2, y: float):
	var m: Dictionary = hud.main.mines.mines[mine_id]
	var code := String(m.code)
	var sheet := icon_sheet(code)
	if sheet != null:
		var whole := Rect2(HudScript.INFO_ICON_CENTRE + Vector2(0, y) - Vector2(70, 70), Vector2(140, 140))
		var shown := whole.intersection(area)
		if shown.has_area(): hud.draw_texture_rect_region(sheet, shown, Rect2(shown.position - whole.position, shown.size))
	var at := HudScript.BUILDING_NAME_AT + Vector2(0, y)
	var width := minf(0xa8, HudScript.info_right_edge(at.y - 4 - y) - at.x)
	hud.text(hud.fitted(hud.display_name(code), 5, width), 5, Rect2(at.x, at.y - 4, width, 0x14))
	var mine_state: Dictionary = hud.main.economy.mines.get(mine_id, {}) if hud.main.economy != null else {}
	var reserve: int = int(mine_state.get("reserve", 0))
	var line: String = hud.game_text(272).strip_edges()
	if reserve > 0: line = "%s: %d" % [hud.game_text(int(HudScript.MINE_LANE_TEXT[int(m.lane)])).strip_edges(), reserve]
	var row := at + Vector2(0x18, 0x2e)
	var row_width := HudScript.info_right_edge(row.y - 4 - y) - row.x
	hud.text(hud.fitted(line, 2, row_width), 2, Rect2(row.x, row.y - 4, row_width, 16))
	var icons: Texture2D = preload("res://battle/unit_agent.gd").digits_texture()
	var worker_at := Vector2(HudScript.INFO.position.x + 0xf, 1056 - HudScript.Y_SHIFT + 0x23 + 0xc + y)
	if icons != null: hud.draw_texture_rect_region(icons, Rect2(worker_at, Vector2(16, 16)), Rect2(0xca, 0x7d, 16, 16))
	hud.text(str(int(m.entity.worker_count)), 2, Rect2(HudScript.INFO.position.x + 0x17 - 8, worker_at.y + 0x14 - 4, 16, 16), HORIZONTAL_ALIGNMENT_CENTER)

func draw_building_rows(building, y: float):
	var at := HudScript.BUILDING_NAME_AT + Vector2(0, y)
	var width := minf(0xa8, HudScript.info_right_edge(at.y - 4 - y) - at.x)
	# P-3 (Read, 0x4da8fe..0x4da949): the tower view needs 0x52db10(0) (a garrison capacity, Building.cfg's digit) and the
	# local player's building (+0xc == 0x709100). P-2 tested a definition key "attack" that does not exist: never shown.
	# G-4: the tower view draws its own title instead of the name (below), so the test comes first.
	if not building.constructing and hud.main != null and hud.main.combat != null and hud.main.production != null \
			and int(building.owner) == int(hud.main.local_player) \
			and int(hud.main.production.rules.definition(String(building.original_type_id)).get("garrison", 0)) > 0:
		draw_tower_rows(building, at, y)
		return
	hud.text(hud.fitted(hud.display_name(String(building.original_type_id)), 5, width), 5, Rect2(at.x, at.y - 4, width, 0x14))
	var rows := ["%d / %d" % [int(building.hit_points), int(building.max_hit_points)]]
	if building.constructing: rows.append("%d%%" % int(building.progress))
	elif building.job_item != "": rows.append("%s %d%%" % [hud.display_name(building.job_item), int(building.job_progress)])
	for i in rows.size():
		var row := at + Vector2(0x24, 0x1a + 0x12 * i)
		var row_width := HudScript.info_right_edge(row.y - 4 - y) - row.x
		hud.text(hud.fitted(String(rows[i]), 2, row_width), 2, Rect2(row.x, row.y - 4, row_width, 16))

func draw_tower_rows(building, at: Vector2, y: float):
	var title := at - Vector2(0, 0xa)
	hud.text(hud.fitted(hud.game_text(HudScript.TOWER_TITLE_LINE), 5, minf(0xa8, HudScript.info_right_edge(title.y - 4 - y) - title.x)), 5, Rect2(title.x, title.y - 4, 0xa8, 0x14))
	draw_garrison_faces(building, y)
	var block: Dictionary = hud.main.combat.building_block(building)
	var base := int(CombatRules.building_stats(building.definition.raw_hex).combat)
	if hud.main.combat.spells != null and building.has_meta("morph"): base = int(hud.main.combat.spells.building_stat(building, 0))
	var t := tower_terms(building)
	var rows := [[258, HudScript.bonus_text(base, int(block.combat))], [259, "%d / %d" % [int(building.hit_points), int(building.max_hit_points)]],
		[260, HudScript.bonus_text(int(t.rate), int(t.rate) + int(t.rate_bonus))], [261, HudScript.bonus_text(int(t.damage), int(t.damage) + int(t.damage_bonus))],
		[755, HudScript.bonus_text(int(t.range), int(t.range) + int(t.range_bonus))]]
	for i in rows.size():
		var row := Vector2(at.x, title.y + 0x14 + 0x12 * i)      # 0x4daaab: the first row 0x14 below the title
		hud.text(hud.game_text(int(rows[i][0])), 2, Rect2(HudScript.TOWER_LABEL_RIGHT - 80, row.y - 4, 80, 16), HORIZONTAL_ALIGNMENT_RIGHT)
		var vx := HudScript.TOWER_VALUE_X
		var row_width := HudScript.info_right_edge(row.y - 4 - y) - vx
		hud.text(hud.fitted(String(rows[i][1]), 2, row_width), 2, Rect2(vx, row.y - 4, row_width, 16))
		if i == 3:
			var icons := hud.tex("DamageIcons.bmp")
			var info: Dictionary = hud.canvas.font(2)
			if icons != null and not info.is_empty() and info.font != null:
				var width := int(info.font.get_string_size(String(rows[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x)
				hud.draw_texture_rect_region(icons, Rect2(vx + 4 + width, row.y - 4 - 2, 24, 20), Rect2(24 * int(t.dtype), 0, 24, 20))

func draw_garrison_faces(building, y: float):
	var rings: Texture2D = preload("res://battle/unit_agent.gd").rings_texture()
	var shown := 0
	for o in (hud.main.combat.garrison_terms(int(building.entity_id)) if hud.main != null and hud.main.combat != null else []):
		if shown >= 4: return
		var u = hud.main.unit_by_id(int(o.id))
		var f = hud.main.combat.fighters.get(int(o.id))
		if u == null or f == null: continue
		var at := HudScript.GARRISON_FACES + Vector2(29 * (shown & 1), 29 * (shown >> 1) + y)
		var w: int = preload("res://battle/selection.gd").weight(u)
		var half: int = preload("res://battle/unit_agent.gd").health_row(int(f.hp), int(f.max_hp)) >> 1
		var v: int = HudScript.list_frame(hud.main.is_hero_unit(u), int(f.get("rank", 0)))
		var source: Rect2
		if w >= 4: source = Rect2(((half >> 2) + 3 + 2 * v) * 56, (half & 3) * 56 + 0x1eb, 56, 56)
		elif w == 2: source = Rect2(((half >> 2) + 2 + 2 * v) * 28, (half & 3) * 56 + 0x1eb, 28, 56)
		else: source = Rect2(28 * v, half * 28 + 0x1eb, 28, 28)
		if rings != null: hud.draw_texture_rect_region(rings, Rect2(at, source.size), source)
		var icon: Dictionary = preload("res://core/art_data.gd").data().get("icons", {}).get(String(u.type_id), {})
		var region: Array = icon.get("regions", {}).get("5", [])
		if region.size() == 4:
			hud.draw_texture_rect_region(preload("res://core/art_data.gd").texture(String(icon.texture)), Rect2(at + Vector2(3, 3), Vector2(region[2], region[3])),
				Rect2(region[0], region[1], region[2], region[3]))
		shown += 1

## 0x52b0c0 / 0x52e9e0 for a tower: {"rate", "rate_bonus", "damage", "damage_bonus", "range", "range_bonus", "dtype"}.
func tower_terms(building) -> Dictionary:
	var raw: PackedByteArray = String(building.definition.raw_hex).hex_decode()
	var spells = hud.main.combat.spells if hud.main != null and hud.main.combat != null else null
	var morph: bool = spells != null and building.has_meta("morph")
	var out := {"rate": int(spells.building_stat(building, 1)) if morph else CombatRules.i16(raw, 0x26),
		"damage": int(spells.building_stat(building, 3)) if morph else CombatRules.i16(raw, 0x38),
		"range": CombatRules.i16(raw, 0x3c), "dtype": CombatRules.i16(raw, 0x3a), "damage_bonus": 0, "range_bonus": 0}
	var terms: Array = hud.main.combat.garrison_terms(int(building.entity_id)) if hud.main != null and hud.main.combat != null else []
	out["rate_bonus"] = CombatRules.garrison_rate(terms)
	var best := -10
	for o in terms:
		if bool(o.hero):
			out.damage_bonus += 20
			out.range_bonus += 2
		elif (int(o.status) >> 18) & 1:
			out.damage_bonus += 20 if (int(o.status) >> 15) & 1 else 10
			out.range_bonus += 1
		if not (int(o.status) >> 18) & 1: continue     # the panel's own loop (0x4dacbb): any occupant with bit 18
		var f = hud.main.combat.fighters.get(int(o.id))
		if f == null: continue
		var c := int(f.get("base", f.stats).get("combat", f.stats.combat))
		if c > best:
			best = c
			out.dtype = int(f.stats.dtype)
	return out

func queue_view(building) -> bool:
	return building != null and building.owner == hud.main.local_player and building.has_job()

## The local player's race (0x709100 -> the player record's race, as 0x439050 and 0x4d6e00 read it).
func local_race() -> int:
	if hud.main == null or hud.main.get("production") == null: return 0
	return int(hud.main.production.races.get(hud.main.local_player, 0))

func powerup_columns() -> Array:
	return HudScript.POWERUPS.get(local_race(), [])

func powerup_sheet() -> String:
	return String(HudScript.POWERUP_SHEETS[clampi(local_race(), 0, 15)])

func draw_queue(building, y: float):
	var strip := hud.tex("ProductionSlots.bmp")
	if strip != null: hud.draw_texture(strip, HudScript.QUEUE_STRIP + Vector2(0, y))
	var small := hud.tex("Powerups%s_Small.bmp" % powerup_sheet())
	var columns := powerup_columns()
	var ids := HudScript.queue_slots(building)
	for k in ids.size():
		var id := String(ids[k])
		var at := Vector2(HudScript.QUEUE_SLOT_X[k], HudScript.QUEUE_SLOT_Y + y)
		if id == "":                                             # P-2: the pending job's picture (bitmap 0x66)
			var rings: Texture2D = preload("res://battle/unit_agent.gd").rings_texture()
			if rings != null:
				hud.draw_texture_rect_region(rings, Rect2(at, HudScript.QUEUE_SLOT), Rect2(HudScript.PENDING_SOURCE + Vector2(32 * HudScript.pending_frame(Time.get_ticks_msec()), 0), HudScript.QUEUE_SLOT))
			continue
		if id.begins_with("A"):
			var sheet := icon_sheet(id)
			if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(at, HudScript.QUEUE_SLOT), Rect2(Vector2(0, 144), HudScript.QUEUE_SLOT))
		elif small != null and columns.has(id):
			hud.draw_texture_rect_region(small, Rect2(at, HudScript.QUEUE_SLOT), Rect2(Vector2(32 * columns.find(id), 0), HudScript.QUEUE_SLOT))
	var more := HudScript.queue_more(building)
	if more >= 0: hud.text("+ %d" % more, 5, Rect2(HudScript.QUEUE_MORE + Vector2(0, y - 4), Vector2(60, 20)))
	var box := HudScript.REPEAT_BOX + Vector2(0, y)
	hud.draw_rect(Rect2(box + Vector2(0.5, 0.5), Vector2(11, 11)), Color8(200, 200, 200), false, 1.0)
	if building.repeat: hud.draw_rect(Rect2(box + Vector2(2, 2), Vector2(8, 8)), Color8(180, 180, 180))
	hud.text(hud.game_text(523), 2, Rect2(box + Vector2(0xe, 1 - 4), Vector2(160, 16)))
	hud.draw_production_bar(HudScript.QUEUE_BAR + Vector2(0, y), int(building.job_progress))

## The queue view's control under a panel point: HIT_REPEAT, HIT_SLOT + k, or -1 (0x4d6790 mode 5).
func queue_hit(v: Vector2, building) -> int:
	if not queue_view(building): return -1
	var y := hud.oy()
	if Rect2(HudScript.REPEAT_BOX + Vector2(0, y), HudScript.REPEAT_HIT + Vector2.ONE).has_point(v): return HudScript.HIT_REPEAT
	for k in HudScript.queue_slots(building).size():
		if Rect2(Vector2(HudScript.QUEUE_SLOT_X[k], HudScript.QUEUE_SLOT_Y + y), HudScript.QUEUE_SLOT + Vector2.ONE).has_point(v): return HudScript.HIT_SLOT + k
	return -1

func queue_press(hit: int, building) -> bool:
	if hit == HudScript.HIT_REPEAT:
		building.repeat = not building.repeat                    # 0x4d54c0: flips +0x190 at once
		return true
	if hit >= HudScript.HIT_SLOT and hit < HudScript.HIT_SLOT + 6:
		return hud.main.production.cancel_slot(building.entity_id, hit - HudScript.HIT_SLOT, hud.main.game_ms())   # 0x52d8a0
	return false

func draw_selection_list(units: Array, y: float):
	var rings: Texture2D = preload("res://battle/unit_agent.gd").rings_texture()
	var used := {}
	var slot := 0
	for bucket in [4, 2, 1]:
		for u in units:
			var w: int = preload("res://battle/selection.gd").weight(u)
			if (bucket == 4 and w != 4) or (bucket == 2 and w != 2) or (bucket == 1 and w >= 2): continue
			while slot < 32 and used.has(slot): slot += 1
			if slot >= 32: return
			var f = hud.main.combat.fighters.get(u.unit_id) if hud.main.combat != null else null
			var row: int = preload("res://battle/unit_agent.gd").health_row(int(f.hp), int(f.max_hp)) if f != null else 0
			var v: int = HudScript.list_frame(hud.main.is_hero_unit(u), int(f.get("rank", 0)) if f != null else 0)
			var half := row >> 1
			var source: Rect2
			if bucket == 4: source = Rect2(((half >> 2) + 3 + 2 * v) * 56, (half & 3) * 56 + 0x1eb, 56, 56)
			elif bucket == 2: source = Rect2(((half >> 2) + 2 + 2 * v) * 28, (half & 3) * 56 + 0x1eb, 28, 56)
			else: source = Rect2(28 * v, half * 28 + 0x1eb, 28, 28)
			var at := Vector2(HudScript.LIST_ORIGIN.x + HudScript.LIST_STEP * (slot % 8), HudScript.PANEL_TOP + y + HudScript.LIST_ORIGIN.y + HudScript.LIST_STEP * (slot / 8))
			if rings != null: hud.draw_texture_rect_region(rings, Rect2(at, source.size), source)
			var icon: Dictionary = preload("res://core/art_data.gd").data().get("icons", {}).get(String(u.type_id), {})
			var region: Array = icon.get("regions", {}).get("5", [])
			if region.size() == 4:
				hud.draw_texture_rect_region(preload("res://core/art_data.gd").texture(String(icon.texture)), Rect2(at + Vector2(3, 3), Vector2(region[2], region[3])),
					Rect2(region[0], region[1], region[2], region[3]))
			used[slot] = true
			if bucket == 4:
				for extra in [1, 8, 9]: used[slot + extra] = true
				slot += 2
			else:
				if bucket == 2: used[slot + 8] = true
				slot += 1

## 0x4d7710, one unit (parity pass 3, Read; the original's conversion screenshot at 1024x768 matches): the name (a hero:
## its record's name) in font 5 at (+0x91, +0x12); from base y = top + 0x2c the labels Game.txt [0258] Combat:, [0259]
## Hits: and, unless the unit converts, [0260] Speed:, [0261] Damage:, [0262] Armor:, [0263] Resistance: right-aligned at
## +0xd5, 0x0e apart, their values at +0xe0. Combat and Speed print base and effective values through 0x4ddeb0 ("%d", or
## "%d +%d" / "%d %d" for a bonus / malus); Hits "%d / %d". A converting unit shows the conversion block at the same base
## instead of the last four lines (labels and values in font 2). Provisional: Damage / Armor / Resistance
## printed as plain numbers (their getters, vtable +0x50 / +0x4c, were not followed; "-" when the unit has no attack).
func draw_unit_info(u, area: Rect2):
	var f = hud.main.combat.fighters.get(u.unit_id) if hud.main.combat != null else null
	var name := hud.display_name(String(u.type_id))
	# A named unit (a quest group member, encounters.gd / naming_sets.gd) shows its name. Provisional: the original's
	# unit branch of 0x4d7710 is not traced for this; the message 0xfa carries the name into the unit.
	if f != null and String(f.get("name", "")) != "": name = String(f.name)
	if u.unit_id == hud.main.hero_unit_id and hud.main.hero_match != null and hud.main.hero_match.profile != null:
		name = String(hud.main.hero_match.profile.data.name)
	var x := area.position.x
	var top := area.position.y
	var name_width := HudScript.info_right_edge(top + 0x12 - 4 - hud.oy()) - x - 0x91
	hud.text(hud.fitted(name, 5, name_width), 5, Rect2(x + 0x91, top + 0x12 - 4, name_width, 18))
	var base := top + 0x2c
	var percent := 0
	if hud.main.conversions != null: percent = hud.main.conversions.unit_progress(u.unit_id, hud.main.game_ms())
	if f == null: return
	var block: Dictionary = hud.main.combat.combat_block(f)
	# Playtest 2026-11-11: 0x4d7710 prints 0x51bd10(0) / (1) and 0x51c460(0) / (1), so the hero's aura (+4 Combat, +2
	# speed near the owner's living hero) shows as "8 +2" (MOVEMENT_RESEARCH.md); before, both rows left it out.
	# P-2 (COMBAT_RESEARCH.md G-3 section 4, Read): 0x51bd10(0) is the raw word +0x92 (the fighter's base combat, ranks and
	# Morph included, no research term), so the base of the row is f.base.combat, not the researched f.stats.combat.
	var rows := [[258, HudScript.bonus_text(HudScript.raw_combat(f), CombatRules.effective_combat(block))], [259, "%d / %d" % [int(f.hp), int(f.max_hp)]]]
	if percent <= 0:
		rows.append([260, HudScript.bonus_text(int(f.stats.speed), int(u.base_speed) if not bool(f.hero) else int(block.get("speed", f.stats.speed)))])
		rows.append([261, str(int(block.dmg)) if int(block.dmg) > 0 else "-"])
		rows.append([262, str(int(block.armour))])
		rows.append([263, str(maxi(0, int(block.get("res1", 0))))])
	for i in rows.size():
		var y := base + 0x0e * i - 4
		hud.text(hud.game_text(int(rows[i][0])), 2, Rect2(x + 0xd5 - 120, y, 120, 16), HORIZONTAL_ALIGNMENT_RIGHT)
		hud.text(String(rows[i][1]), 2, Rect2(x + 0xe0, y, 110, 16))
	# Parity pass 4 (0x4d7710, Read): after the Damage value its damage type's icon (DamageIcons.bmp, bitmap 0x189,
	# 24 x 20 at x 0x60eb4c[type] = 24 type; type 0xb shows 3) at value x + width + 0xf (value x + 0x4d when width + 4
	# > 0x42), y = base + 0x25 - 0x2a + the Damage row.
	if percent <= 0 and int(block.dmg) > 0:
		var icons := hud.tex("DamageIcons.bmp")
		var info: Dictionary = hud.canvas.font(2)
		if icons != null and not info.is_empty() and info.font != null:
			var width := int(info.font.get_string_size(str(int(block.dmg)), HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x)
			var kind: int = int(block.get("dtype", 0))
			if kind == 0xb: kind = 3
			var ix: float = x + 0xe0 + (0x4d if width + 4 > 0x42 else width + 0xf)
			if kind >= 0 and kind < 7: hud.draw_texture_rect_region(icons, Rect2(ix, base + 0x25, 24, 20), Rect2(24 * kind, 0, 24, 20))
	# Non-heroes (+0xb4 clear) that are not animals (0x528280) and not flag 0x1cd: the level (0x526d80, at most 19) and
	# "%ld xp" (Game.txt [0265], 0x526db0) centred at x + 0x19, y + 0x5c (+0x50 from level 5), and the rank medals of
	# SkillIcons.bmp: level / 5 large (0x2d + 0x1d n, 0x8e, 29 x 16) at (x + 10, y + 0x5f) when above 0, level % 5 small
	# (0x2d + 0x1d n, 0x9e) at (x + 10, y + 0x6f).
	if u.unit_id != hud.main.hero_unit_id and not hud.main.is_hero_unit(u) and not preload("res://simulation/unit_ai.gd").is_animal(String(u.type_id)) and not preload("res://simulation/unit_ranks.gd").is_titan(String(u.type_id)):
		var medals: Array = HudScript.rank_medals(int(f.get("rank", 0)))
		var xp_text := hud.game_text(265).replace("%ld", str(int(f.get("xp", 0))))
		hud.text(xp_text, 2, Rect2(x + 0x19 - 60, top + (0x50 if int(medals[0]) > 0 else 0x5c) - 4, 120, 16), HORIZONTAL_ALIGNMENT_CENTER)
		var digits: Texture2D = preload("res://battle/unit_agent.gd").digits_texture()
		if digits != null:
			if int(medals[0]) > 0: hud.draw_texture_rect_region(digits, Rect2(x + 10, top + 0x5f, 0x1d, 0x10), Rect2(int(medals[0]) * 0x1d + 0x2d, 0x8e, 0x1d, 0x10))
			hud.draw_texture_rect_region(digits, Rect2(x + 10, top + 0x6f, 0x1d, 0x10), Rect2(int(medals[1]) * 0x1d + 0x2d, 0x9e, 0x1d, 0x10))
	if percent > 0: hud.draw_converting(Vector2(x, base), percent, true)

func draw_grid(y: float):
	var buttons := hud.tex("Panel_Buttons.bmp")
	var icons := hud.tex("Panel_Icons.bmp")
	if buttons != null: hud.draw_texture_rect_region(buttons, Rect2(HudScript.GRID + Vector2(0, y), Vector2(134, 134)), Rect2(0, 0, 134, 134))
	for k in 9:
		var c: Dictionary = hud.cells[k] if k < hud.cells.size() else {}
		var r := hud.cell_rect(k)
		if c.is_empty():
			# 0x4dcdf0: an empty cell restores its frame from the second row of Panel_Buttons.
			if buttons != null: hud.draw_texture_rect_region(buttons, r, Rect2(8 + 43 * (k % 3), 0x8e + 43 * (k / 3), 38, 38))
			continue
		var pressed := k == hud.hovered_cell and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and bool(c.get("enabled", false))
		if c.has("icon") and icons != null:
			var row := 0 if c.get("enabled", false) else 64
			if pressed: row = 32
			hud.draw_texture_rect_region(icons, Rect2(r.position, Vector2(32, 32)), Rect2((int(c.icon) - 1) * 32, row, 32, 32))
		elif c.has("sheet"):
			var sheet := icon_sheet(String(c.sheet))
			var source_y := 190 if c.get("enabled", false) else 280      # the 'i' sheet's 90x90 icon and its grey copy
			if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(r.position + Vector2(1, 1), Vector2(36, 36)), Rect2(0, source_y, 90, 90))
		if k == hud.hovered_cell and String(c.get("tip", "")) != "":
			hud.text(String(c.tip), 5, Rect2(HudScript.GRID.x - 300, HudScript.GRID.y + y - 22, 434, 20), HORIZONTAL_ALIGNMENT_RIGHT)

