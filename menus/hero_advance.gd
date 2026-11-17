extends Control
## The screens the results' Continue button opens for a persistent hero (milestone 11-hero, Read):
## * 0x4549bd: stat points left -> PNL_HEROLEVELUP_STATS (0x159, 0x552d90); else skill points -> PNL_HEROLEVELUP_SKILLS
##   (0x15a, 0x5522e0); else the retinue screen PNL_RETINUE (0xe9, 0x440b40(0, 0)).
## * Stats (callback 0x552e30, draw 0x552f60 / 0x552fe0): BUTT_LEVELUP (0x180) adds a pending point while points are left,
##   BUTT_LEVELDOWN (0x181) takes one back; OK (0x16f, 0x553320) adds the pending points to the stats, keeps the unspent
##   rest, writes the hero (0x44fef0) and opens the skill screen, or the retinue screen when no skill point is left.
## * Skills (0x552380 / 0x552610 / 0x552750): one row per record skill entry; + needs a point and level >= the entry's
##   unlock level; no rank cap; OK (0x552990) adds the ranks, keeps the rest, writes the hero, opens the retinue screen.
## * Retinue (0x440b40 with no recruit budget after a skirmish): slots at or above the Charisma capacity (0x40b130) are
##   cleared; OK returns to the hero book (0x448870(9, 0)). The recruit candidates are the end-of-battle scan's
##   (0x43f3e0, simulation/retinue_scan.gd; pending "candidates"). Read from the disassembly of the panel callbacks
##   0x4427d0 (retinue, PNL_RETINUE_ARMY1..8) and 0x443890 (recruits, PNL_RETINUE_RECRUIT1..8): a click on an occupied
##   slot or candidate picks it up, a second click on it puts it back; with a candidate held, a click on a slot puts the
##   candidate there (the slot's unit, if any, takes the candidate's place and can be swapped back); with a slot held, a
##   click on a candidate place swaps them (into an empty place: the unit leaves the retinue). A new member starts with
##   one battle. OK (0x4b) writes the hero. The rebuild keeps the retinue as a list, so an emptied slot closes up when the
##   hero is written (Provisional). Open: the right-click info popup (0x4431c0), the drag image.
## * Graveyard (button 0xd6 -> 0x440b10 + 0x54f260, Read): PNL_GRAVEYARD (0xfc) and PNL_GRAVEYARD_PART2 (0x154) over the
##   retinue screen, whose state is kept. 0x54f6f0 per grave g of the ten: an occupied grave's stone button 0xda[g] is
##   enabled, its name (0x2f2f), "Level %d" with rank + 1 (Game.txt [0280] 0, 0x2f30), "%d Battles" ([0280] 1, PART2
##   0x2f30) and its number (PART2 0x2f33); an empty one is blank and disabled; the title is [0280] 2. Hovering a stone
##   (message 0x12, 0x54f980) shows its name (0x2eef) and "Slain in the battle of %s." ([0169] 0) with the battle text, or
##   "Slain in a random battle." ([0038] 0) when the text is [0083] 0 ("Random"); hovering the full-screen catcher 0xdb
##   clears it. OK (0x4b, 0x54f690) returns to the retinue screen (0x440b20, 0x4417b0). Open: the unit picture and the
##   medal images 0x54fc00 draws; the eleventh stone (instance 10, never filled by the ten-grave loop) is kept disabled.
## Original 800x600 centre with shared decorative wings on matching backgrounds (MENU_ARTWORK.md).
const Assets = preload("res://core/asset_store.gd")

const UiCanvas = preload("res://core/ui_canvas.gd")
const Store = preload("res://simulation/hero_store.gd")
const Rules = preload("res://simulation/hero_rules.gd")
const Effects = preload("res://simulation/hero_effects.gd")
const BASE := Vector2i(800, 600)
const STATS := "PNL_HEROLEVELUP_STATS"
const SKILLS := "PNL_HEROLEVELUP_SKILLS"
const RETINUE := "PNL_RETINUE"
const GRAVEYARD := "PNL_GRAVEYARD"
const GRAVEYARD_PART2 := "PNL_GRAVEYARD_PART2"
const RETINUE_ROWS := [Vector2i(417, 125), Vector2i(515, 125), Vector2i(613, 125), Vector2i(515, 245), Vector2i(613, 245),
	Vector2i(417, 365), Vector2i(515, 365), Vector2i(613, 365)]      # 0x609288 / 0x6092a8: PNL_RETINUE_ARMY1..8
const RECRUIT_ROWS := [Vector2i(93, 125), Vector2i(191, 125), Vector2i(289, 125), Vector2i(93, 245), Vector2i(191, 245),
	Vector2i(93, 365), Vector2i(191, 365), Vector2i(289, 365)]       # 0x6092c8 / 0x6092e8: PNL_RETINUE_RECRUIT1..8

static var pending: Dictionary = {}     # {"hero_id", "store_dir", "next"} set by the results screen

var layout: Dictionary
var viewport := SubViewport.new()
var canvas := UiCanvas.new()
var view := TextureRect.new()
var backdrop := preload("res://menus/menu_backdrop.gd").new()
var store
var profile
var screen := ""
var add: Array = []                     # pending points per stat / skill row
var left := 0
var next_scene := "res://menus/hero_menu.tscn"
var temporary := false                  # 0xb997e8 / 0xb98dc6: a temporary hero (front_end.gd start_temporary_hero)
var slots: Array = []                   # the retinue screen's working slots (8, {} = empty): 0x70a030 while it is open
var recruits: Array = []                # the 8 candidate places (0xa23ca8 / 0xa240f0), {} = empty
var held_slot := -1                     # 0x609278: the retinue slot picked up
var held_recruit := -1                  # 0x60927c: the candidate picked up
var grave_hover := -1                   # 0xb92524: the grave whose details are shown
var mouse_point := Vector2.ZERO         # 0x46c150: the cursor, for the held unit drawn at it (0x443d20)
## 0x443d20 / 0x444330 (Read): a box's picture, medals and Combat are drawn over the panels; MedalIcon.bmp (0x18b) holds the
## small medal (0, 0, 11 x 14) and the big one (10, 0, 16 x 15) at these offsets (0x609308 / 0x609314, 0x609320 / 0x609328).
const SMALL_MEDALS := [Vector2i(77, 1), Vector2i(77, 16), Vector2i(77, 31), Vector2i(77, 46), Vector2i(77, 61)]
const BIG_MEDALS := [Vector2i(65, 1), Vector2i(65, 16), Vector2i(65, 31)]
const HELD_OFFSET := Vector2i(0x2b, 0x2b)
var stat_names: Array = ["Strength", "Dexterity", "Intelligence", "Charisma"]   # Game.txt [0038]..[0041] (0x44f4a0(0x26..0x29))

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # a full-window STOP root would eat every click before _unhandled_input
	RenderingServer.set_default_clear_color(Color.BLACK)
	layout = Assets.json("ui_layout.json")
	canvas.setup(layout)
	canvas.overlay_text = draw_boxes                 # 0x443d20 / 0x444330: pictures, medals, Combat, the held unit
	viewport.size = BASE
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	canvas.resolution = BASE
	viewport.add_child(canvas)
	add_child(viewport)
	view.texture = viewport.get_texture()
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	view.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(backdrop)
	backdrop.bind(canvas, view)
	add_child(view)
	get_viewport().size_changed.connect(_place_view)
	var display_manager = preload("res://core/display.gd").node(get_tree())
	if display_manager != null: display_manager.changed.connect(_place_view)
	_place_view()
	if "--self-test" in OS.get_cmdline_user_args():
		call_deferred("self_test")
		return
	temporary = bool(pending.get("temporary", false))
	open(pending.get("hero_id", ""), Store.new(String(pending.get("store_dir", "user://heroes"))), String(pending.get("next", "res://menus/hero_menu.tscn")))

func _place_view():
	var rect: Rect2 = preload("res://core/display.gd").menu_rect(get_viewport_rect().size, Vector2(BASE))
	view.position = rect.position
	view.size = rect.size
	view.texture_filter = preload("res://core/display.gd").menu_filter()
	preload("res://core/display.gd").prepare_menu_viewport(viewport, view, BASE)
	backdrop.place(get_viewport_rect().size)

func open(hero_id: String, hero_store, after: String = "res://menus/hero_menu.tscn") -> bool:
	store = hero_store
	next_scene = after
	profile = store.load_profile(hero_id) if hero_id != "" else null
	if profile == null:
		get_tree().change_scene_to_file(next_scene)
		return false
	if temporary or int(profile.data.stat_points) > 0: show_stats()    # 0x552d90(1, level): the stats screen first
	elif int(profile.data.skill_points) > 0: show_skills()
	else: show_retinue()
	return true

func strings(section: int) -> Array:
	return layout.strings.get(str(section), [])

func _place(panel: String, offset: Vector2i = Vector2i.ZERO, layer: int = 0):
	canvas.placements.append({panel = canvas.panel_by_name(panel), offset = offset, layer = layer})

func show_stats():
	screen = STATS
	canvas.placements.clear()
	_place(STATS)
	add = [0, 0, 0, 0]
	left = int(profile.data.stat_points)
	refresh()

func show_skills():
	screen = SKILLS
	canvas.placements.clear()
	_place(SKILLS)
	add = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
	left = int(profile.data.skill_points)
	refresh()

func show_retinue():
	screen = RETINUE
	canvas.placements.clear()
	_place(RETINUE)
	var capacity := Rules.retinue_capacity(int(profile.data.stats[3]))
	slots = []
	for i in 8: slots.append(profile.data.retinue[i].duplicate(true) if i < capacity and i < profile.data.retinue.size() else {})
	recruits = []
	var offered: Array = pending.get("candidates", [])
	for k in 8: recruits.append(offered[k].duplicate(true) if k < offered.size() and offered[k] is Dictionary else {})
	held_slot = -1
	held_recruit = -1
	_place_retinue_rows()
	refresh()

## 0x443d20 (retinue) / 0x444330 (recruits), Read: the picture (the unit's 'i' sheet, the 90 x 90 frame the production
## dialog shows: Provisional for 0x487f20's mode 3) at (x + 2, y + 2), rank % 5 + 1 small and rank / 5 big medals (rank
## at most 19), the Combat icon (0x18c) at (x + 4, y + 0x4f) and the Combat in font 2 at (x + 0x16, y + 0x50). A held unit
## is drawn at the cursor - 0x2b instead of in its box.
func draw_boxes():
	if screen != RETINUE: return
	var capacity := Rules.retinue_capacity(int(profile.data.stats[3]))
	# 0x443d20 (Read; playtest 2026-11-12): a slot at or above the Charisma capacity, outside the army setup's budget mode
	# (0xa245e0, never set after a battle), gets RetinueTickCross.bmp (bitmap 400) frame x 0x84, 0x84 x 0x6d, the cross,
	# at the slot - (0x15, 10).
	var cross := canvas.texture("BM_RETINUE_TICK_CROSS")
	if cross != null:
		for i in range(capacity, 8):
			canvas.draw_texture_rect_region(cross, Rect2(RETINUE_ROWS[i] - Vector2i(0x15, 10), Vector2(0x84, 0x6d)), Rect2(0x84, 0, 0x84, 0x6d))
	for i in mini(capacity, slots.size()):
		if not slots[i].is_empty() and i != held_slot: _draw_box(slots[i], RETINUE_ROWS[i])
	for k in recruits.size():
		if not recruits[k].is_empty() and k != held_recruit: _draw_box(recruits[k], RECRUIT_ROWS[k])
	var held: Dictionary = slots[held_slot] if held_slot >= 0 else (recruits[held_recruit] if held_recruit >= 0 else {})
	if not held.is_empty(): _draw_box(held, Vector2i(mouse_point) - HELD_OFFSET)

func _draw_box(unit: Dictionary, at: Vector2i):
	var sheet := _icon(String(unit.get("original_type_id", "")))
	if sheet != null: canvas.draw_texture_rect_region(sheet, Rect2(at + Vector2i(2, 2), Vector2(90, 90)), Rect2(0, 190, 90, 90))
	var medals := canvas.texture("BM_RETINUE_MEDAL_ICON")
	var rank := mini(19, int(unit.get("medal_level", 0)))
	if medals != null:
		for b in rank / 5: canvas.draw_texture_rect_region(medals, Rect2(at + BIG_MEDALS[b], Vector2(16, 15)), Rect2(10, 0, 16, 15))
		for m in rank % 5 + 1: canvas.draw_texture_rect_region(medals, Rect2(at + SMALL_MEDALS[m], Vector2(11, 14)), Rect2(0, 0, 11, 14))
	var icon := canvas.texture("BM_RETINUE_COMBAT_ICON")
	if icon != null: canvas.draw_texture(icon, Vector2(at + Vector2i(4, 0x4f)))
	canvas.draw_text(str(int(unit.get("permanent_state", {}).get("combat", 0))), 2, Rect2i(at + Vector2i(0x16, 0x50), Vector2i(40, 14)), HORIZONTAL_ALIGNMENT_LEFT)

var _icons := {}
func _icon(code: String) -> Texture2D:
	if not _icons.has(code):
		var record: Dictionary = preload("res://core/art_data.gd").data().get("icons", {}).get(code, {})
		_icons[code] = Assets.texture(String(record.texture)) if record.has("texture") else null
	return _icons[code]

func _place_retinue_rows():
	var capacity := Rules.retinue_capacity(int(profile.data.stats[3]))
	for i in capacity: _place("PNL_RETINUE_ARMY%d" % (i + 1), RETINUE_ROWS[i], 0x7e5)
	for k in 8: _place("PNL_RETINUE_RECRUIT%d" % (k + 1), RECRUIT_ROWS[k], 0x7e5)

## 0xd6 -> 0x440b10 + 0x54f260: the graveyard over the retinue screen (its slots and candidates stay as they are).
func show_graveyard():
	screen = GRAVEYARD
	grave_hover = -1
	canvas.placements.clear()
	_place(GRAVEYARD, Vector2i.ZERO, 3000)
	_place(GRAVEYARD_PART2, Vector2i.ZERO, 3000)
	refresh()

## 0x54f3c0 OK: 0x54f690 closes it, 0x440b20 + 0x4417b0 show the retinue screen again.
func close_graveyard():
	screen = RETINUE
	canvas.placements.clear()
	_place(RETINUE)
	_place_retinue_rows()
	refresh()

## 0x54f3c0 message 0x12: a stone shows its grave (when occupied), the full-screen catcher clears it.
func grave_hovered(item_key: String):
	var control := item_key.get_slice("/", 1).get_slice("#", 0)
	if control == "BUTT_GY_BUTTON":
		var g := int(item_key.get_slice("#", 1))
		grave_hover = g if g < profile.data.graveyard.size() else -1
	elif control == "BUTT_GY_FULLSCREEN":
		grave_hover = -1
	else:
		return
	refresh()

## 0x54f980's death line for a grave.
func slain_text(grave: Dictionary) -> String:
	var where := String(grave.get("text", ""))
	if where == String(strings(83)[0]): return String(strings(38)[0])
	return String(strings(169)[0]) % where

## 0x4427d0: a click on retinue slot `r`.
func click_slot(r: int) -> bool:
	if held_recruit >= 0:
		var joining: Dictionary = recruits[held_recruit]
		if not joining.has("id"):                   # a fresh candidate: +0 active, +1 0, battles 1 (0x442c5d..0x442cd6)
			joining["id"] = _new_member_id(String(joining.original_type_id))
			joining["battles"] = 1
		recruits[held_recruit] = slots[r]
		slots[r] = joining
	elif held_slot == r:
		pass
	elif held_slot >= 0:
		return true
	elif not slots[r].is_empty():
		held_slot = r
		refresh()
		return true
	held_slot = -1
	held_recruit = -1
	refresh()
	return true

## 0x443890: a click on candidate place `k`.
func click_recruit(k: int) -> bool:
	if held_slot >= 0:
		var leaving: Dictionary = slots[held_slot]
		var joining: Dictionary = recruits[k]
		if not joining.is_empty() and not joining.has("id"):
			joining["id"] = _new_member_id(String(joining.original_type_id))
			joining["battles"] = 1
		slots[held_slot] = joining
		recruits[k] = leaving
	elif held_recruit == k:
		pass
	elif held_recruit >= 0:
		return true
	elif not recruits[k].is_empty():
		held_recruit = k
		refresh()
		return true
	held_slot = -1
	held_recruit = -1
	refresh()
	return true

func _new_member_id(code: String) -> String:
	var taken := {}
	for unit in slots + recruits:
		if unit is Dictionary and unit.has("id"): taken[String(unit.id)] = true
	for unit in profile.data.retinue: taken[String(unit.id)] = true
	var stamp := int(Time.get_unix_time_from_system())
	var n := 1
	while taken.has("%s-%d-%d" % [code.to_lower(), stamp, n]): n += 1
	return "%s-%d-%d" % [code.to_lower(), stamp, n]

## Texts and button states of the open screen (0x552f60 / 0x552fe0, 0x552610 / 0x552750, 0x4417b0).
## Playtest 2026-11-12 (a Lichelord showed the Knight): IM_PORTRAIT on the stats and skills pages is the hero's
## Portrait%02d.bmp of +0x58, as on the hero book (0x554260); BM_PORTRAIT alone is the panel's default picture.
func _set_portrait():
	if profile == null: return
	var key := "X:Portrait%02d.bmp" % int(profile.data.get("portrait_id", 0))
	if layout.exported_bitmaps.has(key): canvas.bitmap_override["BM_PORTRAIT"] = key
	else: canvas.bitmap_override.erase("BM_PORTRAIT")

func refresh():
	_set_portrait()
	var t := canvas.control_text
	var s := canvas.control_state
	t.clear()
	s.clear()
	var level := int(profile.data.level)
	if screen == STATS or screen == SKILLS:
		t["%s/STR_LARGE400#0" % screen] = String(strings(5)[4]) % level
		t["%s/STR_SMALL_450#0" % screen] = String(strings(5)[5 if screen == STATS else 6])
		t["%s/STR_SMALL_450#1" % screen] = String(strings(5)[7]) % left
		t["%s/STR_SMALL_450#2" % screen] = "%s %d" % [strings(6)[6], int(profile.data.xp)]
		t["%s/STR_SMALL_450#3" % screen] = "%s %d" % [strings(6)[7], Rules.xp_threshold(level + 1)]
	if screen == STATS:
		for i in 4:
			s["%s/BUTT_LEVELDOWN#%d" % [STATS, i]] = 3 if int(add[i]) < 1 else 0
			s["%s/BUTT_LEVELUP#%d" % [STATS, i]] = 3 if left < 1 else 0
			t["%s/STR_MEDIUM265#%d" % [STATS, i]] = str(int(profile.data.stats[i]) + int(add[i]))
			t["%s/STR_MEDIUM220#%d" % [STATS, i]] = stat_names[i]
	elif screen == SKILLS:
		for i in 10:
			var entry = profile.data.skills[i] if i < profile.data.skills.size() else null
			var exists: bool = entry != null and int(entry.id) != 0
			s["%s/BUTT_LEVELDOWN#%d" % [SKILLS, i]] = 3 if (not exists or int(add[i]) < 1) else 0
			s["%s/BUTT_LEVELUP#%d" % [SKILLS, i]] = 3 if (not exists or left < 1 or level < int(entry.unlock_level)) else 0
			if exists:
				t["%s/STR_MEDIUM200#%d" % [SKILLS, i]] = str(int(entry.rank) + int(add[i]))
				t["%s/STR_MEDIUM332#%d" % [SKILLS, i]] = Effects.skill_name(int(entry.id))
	elif screen == GRAVEYARD:
		var graves: Array = profile.data.graveyard
		t["%s/STR_PARCHLARGE_L500#0" % GRAVEYARD] = String(strings(280)[2])
		for g in 11:
			if g < graves.size() and g < 10:
				var grave: Dictionary = graves[g]
				t["%s/STR_PARCHMEDIUM_L250#%d" % [GRAVEYARD, g]] = _label(grave)
				t["%s/STR_PARCHSMALL_L250#%d" % [GRAVEYARD, g]] = String(strings(280)[0]) % (int(grave.get("medal_level", 0)) + 1)
				t["%s/STR_PARCHSMALL_L250#%d" % [GRAVEYARD_PART2, g]] = String(strings(280)[1]) % int(grave.get("battles", 0))
				t["%s/STR_PARCHMED_L100#%d" % [GRAVEYARD_PART2, g]] = str(g + 1)
			else:
				s["%s/BUTT_GY_BUTTON#%d" % [GRAVEYARD, g]] = 3
		if grave_hover >= 0 and grave_hover < graves.size():
			t["%s/STR_SMALL200#0" % GRAVEYARD] = _label(graves[grave_hover])
			t["%s/STR_SMALL500#1" % GRAVEYARD] = slain_text(graves[grave_hover])
	elif screen == RETINUE:
		t["%s/STR_LARGE332#0" % RETINUE] = String(strings(168)[1])
		t["%s/STR_LARGE332#1" % RETINUE] = String(strings(168)[0])
		t["%s/STR_SMALL_180#15" % RETINUE] = ""
		t["%s/STR_SMALL_180#16" % RETINUE] = ""
		for i in 3: t["%s/STR_MEDIUM200#%d" % [RETINUE, i]] = String(strings(168)[5 + i])
		t["%s/STR_MEDIUM500#0" % RETINUE] = String(strings(168)[2])
		t["%s/STR_MEDIUM500#1" % RETINUE] = String(strings(168)[3])
		# 0x4417b0 (Read): every box's medals (0x5326) and Combat icon (0x5325) go off the screen and its Combat label is
		# cleared (0x443d20 draws them); the name is centred (0x464c60 mode 1); empty boxes stay enabled (drop targets);
		# retinue slots past the Charisma capacity are disabled.
		canvas.control_hidden.clear()
		canvas.control_align.clear()
		var capacity := Rules.retinue_capacity(int(profile.data.stats[3]))
		for row in [["PNL_RETINUE_ARMY", slots], ["PNL_RETINUE_RECRUIT", recruits]]:
			for i in 8:
				var panel := "%s%d" % [row[0], i + 1]
				for m in 7: canvas.control_hidden["%s/IM_RETINUE_MEDAL#%d" % [panel, m]] = true
				canvas.control_hidden["%s/IM_RETINUE_ICON_COMBAT#0" % panel] = true
				canvas.control_align["%s/STR_SMALL_180#0" % panel] = HORIZONTAL_ALIGNMENT_CENTER
				t["%s/STR_SMALL24#0" % panel] = ""
				var unit: Dictionary = row[1][i] if i < row[1].size() else {}
				t["%s/STR_SMALL_180#0" % panel] = _label(unit) if not unit.is_empty() else ""
				t["%s/STR_MEDIUM30#1" % panel] = ""
				if row[0] == "PNL_RETINUE_ARMY" and i >= capacity: s["%s/BUTT_RETINUE_ARMY#0" % panel] = 3
	canvas.queue_redraw()

func _label(unit: Dictionary) -> String:
	var name := String(unit.get("name", ""))
	return name if name != "" else String(unit.original_type_id)

func hit(point: Vector2) -> Dictionary:
	var list := canvas.items()
	for i in range(list.size() - 1, -1, -1):
		var item: Dictionary = list[i]
		if not canvas.interactive(item) or item.control.name == "BUTT_HEROLEVELUP_PAD": continue
		if Rect2(item.rect).has_point(point) and canvas.state_of(item) != 3: return item
	return {}

func _unhandled_input(event: InputEvent):
	if not event is InputEventMouse: return
	var point: Vector2 = (event.position - view.position) * (Vector2(BASE) / view.size)
	var item := hit(point)
	mouse_point = point
	if event is InputEventMouseMotion:
		if held_slot >= 0 or held_recruit >= 0: canvas.queue_redraw()
		if item.get("key", "") != canvas.hovered.get("key", ""):
			canvas.hovered = item
			if screen == GRAVEYARD: grave_hovered(String(item.get("key", "")))
			canvas.queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		canvas.pressed = item if event.pressed else {}
		canvas.queue_redraw()
		if not event.pressed and not item.is_empty():
			preload("res://core/audio_manager.gd").instance(get_tree()).click()   # NewClick (0x60f558)
			press(item.key)

## The callbacks 0x552e30 / 0x552380 / 0x440e80 for one released button. Returns false when the button is disabled.
func press(item_key: String) -> bool:
	if int(canvas.control_state.get(item_key, 0)) == 3: return false
	var control := item_key.get_slice("/", 1).get_slice("#", 0)
	var i := int(item_key.get_slice("#", 1))
	match control:
		"BUTT_LEVELUP":
			add[i] = int(add[i]) + 1
			left -= 1
		"BUTT_LEVELDOWN":
			add[i] = int(add[i]) - 1
			left += 1
		"BUTT_OKAY_180":
			return commit()
		"BUTT_OKAY_STARTUP":
			if screen == GRAVEYARD:
				close_graveyard()
				return true
			return finish_retinue()
		"BUTT_RETINUE_GRAVEYARD":
			show_graveyard()
			return true
		"BUTT_RETINUE_ARMY":
			var panel := item_key.get_slice("/", 0)
			if panel.begins_with("PNL_RETINUE_ARMY"): return click_slot(int(panel.trim_prefix("PNL_RETINUE_ARMY")) - 1)
			if panel.begins_with("PNL_RETINUE_RECRUIT"): return click_recruit(int(panel.trim_prefix("PNL_RETINUE_RECRUIT")) - 1)
			return false
		_:
			return false
	refresh()
	return true

## 0x553320 / 0x552990: apply, keep the unspent points, write the hero, open the next screen.
func commit() -> bool:
	var candidate = profile.get_script().new()
	candidate.data = profile.snapshot()
	if screen == STATS:
		for i in 4: candidate.data.stats[i] = int(candidate.data.stats[i]) + int(add[i])
		candidate.data.stat_points = left
	else:
		for i in range(mini(10, candidate.data.skills.size())): candidate.data.skills[i].rank = int(candidate.data.skills[i].rank) + int(add[i])
		candidate.data.skill_points = left
	if not store.save_profile(candidate):
		push_error("Hero advance save failed: " + store.last_error)
		return false
	profile = candidate
	if temporary:                       # 0x553320 -> 0x5522e0(1, level); 0x552990 -> 0x4e2790 (the match), no retinue
		if screen == STATS: show_skills()
		else:
			screen = ""
			if not "--self-test" in OS.get_cmdline_user_args(): get_tree().change_scene_to_file(next_scene)
		return true
	if screen == STATS and int(profile.data.skill_points) > 0: show_skills()
	else: show_retinue()
	return true

## 0x440b40 / 0x440e80: slots beyond the Charisma capacity are cleared; OK writes the hero (the slots as chosen) and
## returns to the hero book.
func finish_retinue() -> bool:
	var chosen: Array = slots.filter(func(unit): return not unit.is_empty())
	if chosen != profile.data.retinue:
		var candidate = profile.get_script().new()
		candidate.data = profile.snapshot()
		candidate.data.retinue = chosen.duplicate(true)
		if not store.save_profile(candidate):
			push_error("Hero advance save failed: " + store.last_error)
			return false
		profile = candidate
	screen = ""
	if not "--self-test" in OS.get_cmdline_user_args(): get_tree().change_scene_to_file(next_scene)
	return true

# ------------------------------------------------------------------------------------------------- self-test
var checks := 0
var failed := false

func check(condition: bool, text: String):
	checks += 1
	if not condition and not failed:
		failed = true
		push_error("Hero advance check failed: " + text)

func self_test():
	check(mouse_filter == Control.MOUSE_FILTER_IGNORE, "the root passes mouse events to _unhandled_input")
	var directory := "user://hero-advance-self-test"
	var test_store = Store.new(directory)
	var Profile = load("res://simulation/hero_profile.gd")
	var hero = Profile.create("advance-test", "Sir Advance")
	hero.data.level = 3
	hero.data.xp = 60
	hero.data.stat_points = 2
	hero.data.skill_points = 2
	hero.data.retinue = []
	check(test_store.save_profile(hero), "test hero saved")
	check(open("advance-test", test_store, "res://menus/hero_menu.tscn") and screen == STATS, "stat points open the stats screen first (0x4549bd)")
	var keys := canvas.items().map(func(item): return item.key)
	check(keys.has("PNL_HEROLEVELUP_STATS/BUTT_LEVELUP#3") and keys.has("PNL_HEROLEVELUP_STATS/BUTT_OKAY_180#0"), "decoded panel 0x159 placed")
	check(canvas.control_text["PNL_HEROLEVELUP_STATS/STR_LARGE400#0"] == "Level: 3" and canvas.control_text["PNL_HEROLEVELUP_STATS/STR_SMALL_450#1"] == "Points Left: 2", "level and points texts (0x552fe0)")
	check(canvas.control_state["PNL_HEROLEVELUP_STATS/BUTT_LEVELDOWN#0"] == 3, "minus disabled without a pending point (0x552f60)")
	check(press("PNL_HEROLEVELUP_STATS/BUTT_LEVELUP#0") and press("PNL_HEROLEVELUP_STATS/BUTT_LEVELUP#0"), "two Strength points")
	check(canvas.control_state["PNL_HEROLEVELUP_STATS/BUTT_LEVELUP#1"] == 3 and not press("PNL_HEROLEVELUP_STATS/BUTT_LEVELUP#1"), "plus disabled with no point left")
	check(press("PNL_HEROLEVELUP_STATS/BUTT_LEVELDOWN#0") and left == 1 and canvas.control_text["PNL_HEROLEVELUP_STATS/STR_MEDIUM265#0"] == "8", "minus returns a point")
	check(press("PNL_HEROLEVELUP_STATS/BUTT_OKAY_180#0") and screen == SKILLS, "OK keeps the unspent point and opens the skill screen (0x553320)")
	var stored = test_store.load_profile("advance-test")
	check(stored.data.stats.map(func(v): return int(v)) == [8, 4, 3, 6] and int(stored.data.stat_points) == 1, "stats written at once with the unspent point kept")
	check(canvas.control_text["PNL_HEROLEVELUP_SKILLS/STR_MEDIUM332#0"] == "Weaponmaster" and canvas.control_text["PNL_HEROLEVELUP_SKILLS/STR_MEDIUM200#1"] == "3", "skill rows: names [0759 + id] and ranks (0x552750)")
	check(canvas.control_state["PNL_HEROLEVELUP_SKILLS/BUTT_LEVELUP#5"] == 3, "Regeneration (unlock 5) locked at level 3 (0x552610)")
	check(canvas.control_state["PNL_HEROLEVELUP_SKILLS/BUTT_LEVELUP#9"] == 3 and canvas.control_state["PNL_HEROLEVELUP_SKILLS/BUTT_LEVELDOWN#9"] == 3, "empty tenth row disabled")
	check(press("PNL_HEROLEVELUP_SKILLS/BUTT_LEVELUP#1") and press("PNL_HEROLEVELUP_SKILLS/BUTT_LEVELUP#4"), "Ferocity and Constitution")
	check(press("PNL_HEROLEVELUP_SKILLS/BUTT_OKAY_180#0") and screen == RETINUE, "OK opens the retinue screen (0x552990)")
	stored = test_store.load_profile("advance-test")
	check(int(stored.data.skills[1].rank) == 4 and int(stored.data.skills[4].rank) == 1 and int(stored.data.skill_points) == 0, "ranks written")
	check(canvas.control_text["PNL_RETINUE/STR_LARGE332#1"] == "Your Retinue" and canvas.control_text["PNL_RETINUE/STR_MEDIUM500#0"].begins_with("Select units"), "retinue texts (0x4417b0)")
	# Capacity: Charisma 6 -> 2 slots; a third member is cleared when the screen closes.
	stored.data.retinue = [{"id": "r1", "original_type_id": "AHKX", "xp": 10, "medal_level": 2, "permanent_state": {}},
		{"id": "r2", "original_type_id": "AHKX", "xp": 10, "medal_level": 2, "permanent_state": {}},
		{"id": "r3", "original_type_id": "AHMX", "xp": 10, "medal_level": 2, "permanent_state": {}}]
	check(test_store.save_profile(stored), "retinue fixture saved")
	profile = test_store.load_profile("advance-test")
	show_retinue()
	check(canvas.items().any(func(item): return item.panel == "PNL_RETINUE_ARMY2") and not canvas.items().any(func(item): return item.panel == "PNL_RETINUE_ARMY3"), "rows up to the capacity")
	check(press("PNL_RETINUE/BUTT_OKAY_STARTUP#0") and test_store.load_profile("advance-test").data.retinue.size() == 2, "slots beyond the capacity cleared (0x440b40)")
	# Recruits (0x443890 / 0x4427d0): pick a candidate, click a full slot: it joins and the member takes its place.
	profile = test_store.load_profile("advance-test")
	pending = {"candidates": [{"original_type_id": "AHMX", "xp": 12, "medal_level": 2, "name": "Bowman Bob", "permanent_state": {"combat": 9}}]}
	show_retinue()
	check(canvas.items().any(func(item): return item.panel == "PNL_RETINUE_RECRUIT8") and canvas.control_text.get("PNL_RETINUE_RECRUIT1/STR_SMALL_180#0", "") == "Bowman Bob", "eight recruit places, the candidate's name")
	check(press("PNL_RETINUE_RECRUIT1/BUTT_RETINUE_ARMY#0") and held_recruit == 0, "a click picks the candidate up")
	check(press("PNL_RETINUE_ARMY2/BUTT_RETINUE_ARMY#0") and held_recruit == -1 and String(slots[1].get("name", "")) == "Bowman Bob" and String(recruits[0].get("id", "")) == "r2",
		"a click on a slot puts it there; the member takes the candidate's place")
	check(int(slots[1].get("battles", 0)) == 1 and Profile.valid_id(String(slots[1].get("id", ""))), "the new member: one battle, an id")
	check(press("PNL_RETINUE/BUTT_OKAY_STARTUP#0"), "OK writes the hero")
	var after: Array = test_store.load_profile("advance-test").data.retinue
	check(after.size() == 2 and String(after[0].id) == "r1" and String(after[1].name) == "Bowman Bob", "the hero keeps r1 and the recruit")
	# A member dropped on an empty candidate place leaves the retinue.
	profile = test_store.load_profile("advance-test")
	pending = {"candidates": []}
	show_retinue()
	check(press("PNL_RETINUE_ARMY1/BUTT_RETINUE_ARMY#0") and held_slot == 0 and press("PNL_RETINUE_RECRUIT3/BUTT_RETINUE_ARMY#0") and slots[0].is_empty(), "a member dropped on an empty place leaves")
	check(press("PNL_RETINUE/BUTT_OKAY_STARTUP#0") and test_store.load_profile("advance-test").data.retinue.size() == 1, "and is gone from the hero")
	pending = {}
	# The graveyard (0x54f260 / 0x54f6f0 / 0x54f980): two graves, then back to the retinue screen as it was.
	var with_graves = test_store.load_profile("advance-test")
	with_graves.data.graveyard = [{"original_type_id": "AHKX", "name": "Sir Fallen", "xp": 40, "medal_level": 4, "battles": 6, "text": "Desert Sands", "age": 2, "permanent_state": {}},
		{"original_type_id": "AHMX", "name": "", "xp": 5, "medal_level": 1, "battles": 1, "text": "Random", "age": 1, "permanent_state": {}}]
	check(test_store.save_profile(with_graves), "graveyard fixture saved")
	profile = test_store.load_profile("advance-test")
	show_retinue()
	check(press("PNL_RETINUE/BUTT_RETINUE_GRAVEYARD#0") and screen == GRAVEYARD, "the graveyard button opens the graveyard (0xd6 -> 0x54f260)")
	var gt := canvas.control_text
	check(gt.get("PNL_GRAVEYARD/STR_PARCHLARGE_L500#0", "") == "Graveyard" and gt.get("PNL_GRAVEYARD/STR_PARCHMEDIUM_L250#0", "") == "Sir Fallen"
		and gt.get("PNL_GRAVEYARD/STR_PARCHSMALL_L250#0", "") == "Level 5" and gt.get("PNL_GRAVEYARD_PART2/STR_PARCHSMALL_L250#0", "") == "6 Battles"
		and gt.get("PNL_GRAVEYARD_PART2/STR_PARCHMED_L100#1", "") == "2", "a grave's name, Level rank + 1, battles and number (0x54f6f0, [0280])")
	check(int(canvas.control_state.get("PNL_GRAVEYARD/BUTT_GY_BUTTON#2", 0)) == 3 and int(canvas.control_state.get("PNL_GRAVEYARD/BUTT_GY_BUTTON#10", 0)) == 3, "empty stones are disabled")
	grave_hovered("PNL_GRAVEYARD/BUTT_GY_BUTTON#0")
	check(canvas.control_text.get("PNL_GRAVEYARD/STR_SMALL200#0", "") == "Sir Fallen" and canvas.control_text.get("PNL_GRAVEYARD/STR_SMALL500#1", "") == "Slain in the battle of Desert Sands.",
		"hovering a stone shows the grave ([0169] with the battle text, 0x54f980)")
	grave_hovered("PNL_GRAVEYARD/BUTT_GY_BUTTON#1")
	check(canvas.control_text.get("PNL_GRAVEYARD/STR_SMALL500#1", "") == "Slain in a random battle.", "a random map's grave ([0038])")
	grave_hovered("PNL_GRAVEYARD/BUTT_GY_FULLSCREEN#0")
	check(canvas.control_text.get("PNL_GRAVEYARD/STR_SMALL200#0", "") == "", "the full-screen catcher clears the details (0xdb)")
	var held_before := held_recruit
	check(press("PNL_GRAVEYARD/BUTT_OKAY_STARTUP#0") and screen == RETINUE and held_recruit == held_before
		and canvas.items().any(func(item): return item.panel == "PNL_RETINUE_RECRUIT1"), "OK returns to the retinue screen as it was (0x54f690, 0x440b20)")
	check(press("PNL_RETINUE/BUTT_OKAY_STARTUP#0"), "the retinue screen still closes")
	# UI gaps: a temporary hero (0x552d90(1, level) -> 0x5522e0(1, level) -> 0x4e2790): stats, then skills, then the match.
	var temp = Profile.create("temp-test", "Temp Advance")
	temp.data.level = 7
	temp.data.xp = Rules.xp_threshold(7)
	temp.data.stat_points = 7
	temp.data.skill_points = 7
	check(test_store.save_profile(temp), "temporary hero fixture saved")
	temporary = true
	check(open("temp-test", test_store, "res://menus/loading_screen.tscn") and screen == STATS and left == 7, "a temporary hero opens the stats screen with level points")
	check(press("PNL_HEROLEVELUP_STATS/BUTT_OKAY_180#0") and screen == SKILLS and left == 7, "its OK opens the skills screen with level points")
	check(press("PNL_HEROLEVELUP_SKILLS/BUTT_LEVELUP#1") and press("PNL_HEROLEVELUP_SKILLS/BUTT_OKAY_180#0") and screen == "", "the skills OK goes on to the match (no retinue screen)")
	check(int(test_store.load_profile("temp-test").data.skills[1].rank) == int(temp.data.skills[1].rank) + 1, "the temporary record carries the chosen rank")
	temporary = false
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if not failed: print("Hero advance checks passed: %d" % checks)
	get_tree().quit(1 if failed else 0)
