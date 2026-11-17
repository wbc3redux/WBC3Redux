extends SceneTree
## Enhanced visuals prototype captures with the real renderer (not part of -Check): the same views of a Knights vs
## Knights match on Desert Sands with the enhanced visuals off and on, written to .local/visuals_<view>_<off|on>.png.
## Run with a window:
##   Godot --path . --script res://tests/capture_visuals.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

var scene

func _initialize():
	call_deferred("run")

func shot(name: String, cursor = null):
	# On first, after enough frames for the dust to build up; then off a few frames later (units keep walking). The view
	# is pinned before each image (the cursor at a window edge would scroll it).
	var top_left: Vector2 = scene.view_top_left()
	Input.warp_mouse(Vector2(root.size) * 0.5 if cursor == null else scene.get_canvas_transform() * cursor)
	for mode in [true, false]:
		scene.visuals.set_enabled(mode)
		for i in (24 if mode else 3): await process_frame
		scene.set_view_top_left(top_left)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.local/visuals_%s_%s.png" % [name, "on" if mode else "off"])
		if mode: print("visuals %s: %d dust puffs" % [name, scene.visuals.puffs.size()])

func run():
	root.size = Vector2i(1920, 1009)
	Settings.use_file("user://visuals-capture-settings.cfg")
	var store := Store.new("user://visuals-capture-heroes")
	var profile = Profile.create("capture-knight", "c")
	store.save_profile(profile)
	scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-knight", store, "capture-visuals")
	var hero = scene.unit_by_id(scene.hero_unit_id)
	# A small army walking past the base, so there are moving units, shadows and dust in the shot.
	var group: Array = [hero]
	for k in 8:
		var u = scene.add_unit(["AHBX", "AHKX", "AHMX"][k % 3], scene.navigator.free_cell_near(hero.cell + Vector2i(k % 4, 2 + k / 4)), 0)
		if u != null: group.append(u)
	for i in 30: scene.simulation_step(1.0 / 30.0)
	scene.centre_view(hero.position)
	# The cursor on the hero, for the hover outline.
	await shot("1_base", hero.position + Vector2(0, -20))
	for u in scene.units: u.selected = group.has(u)
	scene.issue_move(scene.navigator.center(hero.cell + Vector2i(14, 8)))
	for i in 25:
		scene.simulation_step(1.0 / 30.0)
		await process_frame
	scene.centre_view(hero.position)
	await shot("2_marching")
	# Fires and an explosion beside the towers, for the effect glows (effects_layer.gd's own sheets and timing).
	var at: Vector2 = hero.position + Vector2(260, -40)
	var row := int(at.y / 24.0)
	for k in 3: scene.effects.spawn_effect("EF0%d" % (k + 1), Vector2i(at + Vector2(k * 34 - 34, k * 6)), row, false)
	scene.effects.spawn_effect("EX01", Vector2i(at + Vector2(0, 90)), row + 4, true)
	for i in 6:
		scene.simulation_step(1.0 / 30.0)
		await process_frame
	await shot("3_fires")
	# A skirmish next to the group (round 2: hits, arrows, deaths): enemy Swordsmen 4 cells off, one nearly dead.
	var foes: Array = []
	for k in 6:
		var e = scene.add_unit("AHKX", scene.navigator.free_cell_near(hero.cell + Vector2i(5 + k % 3, 3 + k / 3)), 1)
		if e != null: foes.append(e)
	for i in 10: scene.simulation_step(1.0 / 30.0)
	if not foes.is_empty() and scene.combat.fighters.has(foes[0].unit_id): scene.combat.fighters[foes[0].unit_id].hp = 1
	scene.visuals.set_enabled(true)
	var fx = scene.visuals.combat_fx
	var counts := {"add": 0, "smoke": 0, "missiles": 0}
	for i in 150:
		scene.simulation_step(1.0 / 60.0)
		await process_frame
		counts.add = maxi(counts.add, fx.add_parts.size())
		counts.smoke = maxi(counts.smoke, fx.smoke_parts.size())
		counts.missiles = maxi(counts.missiles, scene.combat.missiles.size())
	print("combat fx: peak additive %d, peak smoke %d, peak missiles %d, deaths seen %d, decals %d, hit points watched %d" % [counts.add, counts.smoke,
		counts.missiles, fx.dying_seen.size(), fx.decals.size(), fx.hp_seen.size()])
	scene.centre_view(hero.position + Vector2(120, 60))
	await shot("7_battle")
	# Terrain views with the fog and shroud off: a grass plateau with its cliff edge, and the road crossing.
	if scene.visibility.fog: scene.toggle_fog("fog")
	if scene.visibility.shroud: scene.toggle_fog("shroud")
	scene.centre_view(Vector2(900, 620))
	await shot("4_plateau")
	scene.centre_view(Vector2(1500, 1450))
	await shot("5_road")
	# The Options screen's Visuals tab, over the match.
	scene.visuals.set_enabled(true)
	scene.hud.open_options()
	for i in 3: await process_frame
	var screen = scene.hud.options_layer.get_child(0)
	screen.select_page(4)
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/visuals_6_options_tab.png")
	scene.queue_free()
	quit(0)
