extends RefCounted
## game_hud.gd's panel drawing (R-1 split of game_hud.gd, no behaviour change): the help popup, the round buttons'
## pictures, the panel ends, resources, army count and digits, the minimap and its alert box. The state stays on
## the panel (game_hud.gd); `hud` is the panel.

const HudScript = preload("res://hud/game_hud.gd")
var hud: HudScript

func _init(scene: HudScript) -> void:
	hud = scene

## P-1: the alert box 0x4dc850 blits into the map's info layer (minimap_ping.gd), from BM_INFOBOX (esibi.bmp; absent until
## the import includes it, then nothing is drawn; .local/p1-art/ui_x_esibi.png serves a worktree that has not imported it).
var _ping_texture: Texture2D

## F2 / F7: the skull ornament of Panel_1600.bmp reaches into the 128 x 128 map box (its lower left, rows 45..90 of the
## bitmap at x 500..547); the box's interior is pure black (0, 0, 0) in the bitmap. The original's map leaves the skull on
## top (its 1024x768 screenshot); here the bitmap's non-black pixels inside the box are drawn again over the map, so the
## map's fill and terrain stop at the frame. Presentation: the original's blit order is not traced.
var _ornament: Texture2D

## 0x405f20 (HelpLevel > 1, called from the cursor function 0x420390): a popup about the object under the cursor. Read:
## the call and its HelpLevel gate; the text's first line is the object's name (a hero: name, then level and class).
## Provisional: the lines after the name and the popup's place (here beside the cursor, font 5).
func help_lines(info: Dictionary) -> Array:
	if info.is_empty() or info.kind == "mine": return []
	var o = info.object
	if info.kind == "unit":
		var f = hud.main.combat.fighters.get(o.unit_id) if hud.main.combat != null else null
		var lines := [hud.display_name(String(o.type_id))]
		if f != null and String(f.get("name", "")) != "": lines = [String(f.name), hud.display_name(String(o.type_id))]   # a named unit
		if o.unit_id == hud.main.hero_unit_id and hud.main.hero_match != null and hud.main.hero_match.profile != null:
			lines = [String(hud.main.hero_match.profile.data.name), hud.game_text(25).replace("%d", str(int(hud.main.hero_match.profile.data.level))).replace("%s", hud.display_name(String(o.type_id)))]
		if f != null: lines.append("%s: %d / %d" % [hud.game_text(28), int(f.hp), int(f.max_hp)])
		return lines
	return [hud.display_name(String(o.original_type_id)), "%s: %d / %d" % [hud.game_text(28), int(o.hit_points), int(o.max_hit_points)]]

func draw_help_popup():
	if hud.dialog != "" or hud.settings == null or hud.settings.get_value("HelpLevel") < 2: return
	var lines := help_lines(hud.main.hover_info)
	var building = hud.main.selected_building()
	if building != null and hud.queue_hit(hud.to_virtual(hud.get_viewport().get_mouse_position()), building) == HudScript.HIT_REPEAT:
		lines = [hud.game_text(524).strip_edges(), hud.game_text(525).strip_edges()]   # 0x414940 id 0x36 (F10)
	if lines.is_empty(): return
	var width := 210.0
	var info: Dictionary = hud.canvas.font(5)
	if not info.is_empty() and info.font != null:
		for line in lines: width = maxf(width, info.font.get_string_size(String(line), HORIZONTAL_ALIGNMENT_LEFT, -1, info.size).x)
	var at := hud.to_virtual(hud.get_viewport().get_mouse_position()) + Vector2(24, 20)
	var box := Rect2(at, Vector2(width + 10, 8 + 18 * lines.size()))
	if box.end.y > hud.virtual_height(): box.position.y = at.y - 40 - box.size.y     # F10: help over the panel opens upward
	if box.end.x > hud.virtual_width() - hud.panel_x: box.position.x = hud.virtual_width() - hud.panel_x - box.size.x
	hud.draw_rect(box, Color(0, 0, 0, 0.6))
	for i in lines.size(): hud.text(String(lines[i]), 5, Rect2(box.position.x + 6, box.position.y + 4 + 18 * i, width, 18))

## The round buttons over the panel's own art: Panel_Menu.bmp's frame 1 under the cursor, 2 while pressed, and the
## button's tooltip on the tip line (left buttons from their own x, right buttons right-aligned like the grid's).
func draw_round_buttons(y: float):
	var sheet := hud.tex("Panel_Menu.bmp")
	for kind in HudScript.ROUND:
		if kind != hud.round_hover: continue
		var r: Rect2 = HudScript.ROUND[kind]
		var at := r.position + Vector2(0, y)
		var column := 2 if kind == hud.round_down and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) else 1
		if sheet != null: hud.draw_texture_rect_region(sheet, Rect2(at, r.size), Rect2(30 * column, 30 * int(HudScript.ROUND_ROW[kind]), 30, 30))
		if hud.dialog != "" or hud.settings == null or hud.settings.get_value("HelpLevel") == 0: continue
		var tip := hud.game_text(int(HudScript.ROUND_TIP[kind])).strip_edges()
		if kind in ["inventory", "spellbook"]: hud.text(tip, 5, Rect2(r.position.x, HudScript.GRID.y + y - 22, 434, 20))
		else: hud.text(tip, 5, Rect2(HudScript.GRID.x - 300, HudScript.GRID.y + y - 22, 434, 20), HORIZONTAL_ALIGNMENT_RIGHT)

## Past the bitmap's ends (window wider than 1600 virtual columns): its outer stone columns repeated (modern change).
func draw_panel_ends(panel: Texture2D, y: float):
	var top := HudScript.BITMAP_TOP + y
	var h := float(panel.get_height())
	var strip := float(HudScript.END_STRIP)
	var x := 0.0
	while x > -hud.panel_x:
		x -= strip
		hud.draw_texture_rect_region(panel, Rect2(x, top, strip, h), Rect2(HudScript.END_MARGIN, 0, strip, h))
	x = HudScript.VIRTUAL_W
	while x < hud.virtual_width() - hud.panel_x:
		hud.draw_texture_rect_region(panel, Rect2(x, top, strip, h), Rect2(HudScript.VIRTUAL_W - HudScript.END_MARGIN - strip, 0, strip, h))
		x += strip

## Left / right edge of the world view in panel coordinates (the top-row boxes keep to them).
func view_left() -> float:
	return hud.bars / hud.scale_factor - hud.panel_x

func view_right() -> float:
	return (hud.get_viewport_rect().size.x - hud.bars) / hud.scale_factor - hud.panel_x

func draw_resources():
	var icons := hud.tex("ERIX")
	var digits := hud.tex("ERNX")
	if icons == null or digits == null or hud.main.economy == null: return
	draw_army(icons, digits)
	var stock: Array = hud.main.economy.resources(hud.main.local_player)
	for i in 4:
		var at: Vector2 = HudScript.RESOURCE_BOX[i] + Vector2(view_right() - HudScript.VIRTUAL_W, 0)   # 1600-mode places from the right edge
		hud.draw_texture_rect_region(icons, Rect2(at, Vector2(50, 20)), Rect2(0, HudScript.RESOURCE_FRAME[i] * 20, 50, 20))
		var value := clampi(int(stock[HudScript.RESOURCE_LANE[i]]), 0, 99999)
		var s := str(value)
		var x := at.x + 0x21 + s.length() / 2
		for k in range(s.length() - 1, -1, -1):
			hud.draw_texture_rect_region(digits, Rect2(Vector2(x, at.y + 5), Vector2(7, 10)), Rect2(int(s[k]) * 7, 0, 7, 10))
			x -= 7

## 0x497140: the army counter (population / command limit of the local player, production.population = 0x533dc0).
func draw_army(icons: Texture2D, digits: Texture2D):
	if hud.main.production == null or hud.main.local_player < 0: return
	var pop: Dictionary = hud.main.production.population(hud.main.local_player)
	var box := HudScript.ARMY_BOX + Vector2(view_left(), 0)                     # from the world view's left edge
	hud.draw_texture_rect_region(icons, Rect2(box, Vector2(60, 20)), Rect2(0, 8 * 20, 60, 20))
	var current := str(clampi(int(pop.current), 0, 999))
	var limit := str(clampi(int(pop.maximum), 0, 999))
	draw_digits(digits, current, box.x + (current.length() * 7 >> 1) + 0xe, box.y + 5)
	hud.draw_texture_rect_region(digits, Rect2(Vector2(box.x + 0x1f, box.y + 5), Vector2(7, 10)), Rect2(10 * 7, 0, 7, 10))
	draw_digits(digits, limit, box.x + (limit.length() * 7 >> 1) + 0x2a, box.y + 5)

## ERNX digits right to left, the last digit at `x`.
func draw_digits(digits: Texture2D, s: String, x: float, y: float):
	for k in range(s.length() - 1, -1, -1):
		hud.draw_texture_rect_region(digits, Rect2(Vector2(x, y), Vector2(7, 10)), Rect2(int(s[k]) * 7, 0, 7, 10))
		x -= 7

func draw_minimap(y: float):
	var rect := Rect2(HudScript.MAP_RECT.position + Vector2(0, y), HudScript.MAP_RECT.size)
	var terrain := hud.minimap_texture()
	hud.draw_rect(rect, Color.BLACK)
	if terrain != null: hud.draw_texture_rect(terrain, rect, false)
	var ramps: Array = HudScript.ArtTeams.ramps()
	var k := minimap_cells_per_pixel()
	for b in hud.main.production.buildings.values() if hud.main.production != null else []:
		var r: Rect2i = b.cell_rect()
		if b.owner != hud.main.local_player and hud.main.visibility != null and not hud.main.visibility.is_explored(hud.main.local_player, r.position): continue
		hud.draw_rect(Rect2(rect.position + Vector2(r.position) / k, Vector2(r.size) / k), hud.team_colour(ramps, b.owner))
	for u in hud.main.units:
		if u.dying or u.removed or not u.visible: continue
		if u.owner_id != hud.main.local_player and hud.main.visibility != null and not hud.main.visibility.is_visible(hud.main.local_player, u.cell): continue
		hud.draw_rect(Rect2(rect.position + Vector2(u.cell) / k - Vector2(0.5, 0.5), Vector2(2, 2)), hud.team_colour(ramps, u.owner_id))
	if hud.main.fog_overlay != null and hud.main.fog_overlay.visible and hud.main.fog_overlay.texture != null:
		hud.draw_texture_rect(hud.main.fog_overlay.texture, rect, false)
	var view_size: Vector2 = hud.main.view_world_size()
	var top_left: Vector2 = hud.main.view_top_left() / Vector2(32, 24) / k
	hud.draw_rect(Rect2(rect.position + top_left, view_size / Vector2(32, 24) / k).intersection(rect), Color(1, 1, 1, 0.9), false, 1.0)
	draw_minimap_ping(rect)
	var ornament := minimap_ornament()
	if ornament != null: hud.draw_texture(ornament, rect.position)

func draw_minimap_ping(rect: Rect2):
	var ping = hud.main.get("minimap_ping")
	if ping == null or ping.frame() < 0: return
	if _ping_texture == null:
		_ping_texture = hud.tex("esibi.bmp")
		if _ping_texture == null and FileAccess.file_exists("res://.local/p1-art/ui_x_esibi.png"):
			_ping_texture = ImageTexture.create_from_image(Image.load_from_file(ProjectSettings.globalize_path("res://.local/p1-art/ui_x_esibi.png")))
		if _ping_texture == null: return
	var source: Rect2i = ping.source_rect()
	hud.draw_texture_rect_region(_ping_texture, Rect2(rect.position + Vector2(ping.box.position), Vector2(source.size)), Rect2(source))

func minimap_ornament() -> Texture2D:
	if _ornament == null:
		var panel := hud.tex("Panel_1600.bmp")
		if panel == null: return null
		var image := panel.get_image().get_region(Rect2i(Vector2i(HudScript.MAP_RECT.position - Vector2(0, HudScript.BITMAP_TOP)), Vector2i(HudScript.MAP_RECT.size)))
		image.convert(Image.FORMAT_RGBA8)
		for y in image.get_height():
			for x in image.get_width():
				var c := image.get_pixel(x, y)
				if c.r8 == 0 and c.g8 == 0 and c.b8 == 0: image.set_pixel(x, y, Color(0, 0, 0, 0))
		_ornament = ImageTexture.create_from_image(image)
	return _ornament

## W1: map cells per strategic-map pixel. The panel and every scenario's SM24 are 128 x 128, so 1 on a 128 map; the
## original's mapping on 192 / 256 maps (0x4d64a0) is not traced (Open): the rebuild scales evenly.
func minimap_cells_per_pixel() -> float:
	return float(hud.main.collision.width) / HudScript.MAP_RECT.size.x if hud.main != null and hud.main.collision != null else 1.0

## A strategic-map point (panel-local pixels) as a map cell, clamped to the map.
func minimap_cell(local: Vector2) -> Vector2:
	var k := minimap_cells_per_pixel()
	var limit := HudScript.MAP_RECT.size * k - Vector2.ONE
	return Vector2(clampf(local.x * k, 0, limit.x), clampf(local.y * k, 0, limit.y))
