extends SceneTree
## Parity pass 4 captures with the real renderer (not part of -Check): a running conversion (the hero's yellow ring and
## mana strip, the red target rings, the portrait's bar numbers) and a mixed multi-selection (0x4d7710 case 1) at
## 1920x1009. Copied profile and settings; written to .local/parity4_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_parity4.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/parity4_%s.png" % name)

func run():
	root.size = Vector2i(1920, 1009)
	Settings.use_file("user://parity4-capture-settings.cfg")
	var store := Store.new("user://parity4-capture-heroes")
	var profile = Profile.create("capture-knight", "c")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-knight"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-knight", store, "capture-parity4")
	for i in 20: scene.simulation_step(1.0 / 30.0)
	var hero = scene.unit_by_id(scene.hero_unit_id)
	var nearest := -1
	var best := 1.0e9
	for id in scene.mines.mines:
		var d: float = Vector2(scene.mines.mines[id].anchor).distance_to(Vector2(hero.cell))
		if d < best:
			best = d
			nearest = id
	scene.order_convert(hero, "mine", nearest)
	for i in 1800:
		scene.simulation_step(1.0 / 30.0)
		if scene.conversions.converting(hero.unit_id): break
	for i in 150: scene.simulation_step(1.0 / 30.0)
	for u in scene.units: u.selected = u == hero
	scene.centre_view(hero.position)
	await shot("1_converting")
	# A mixed selection: the hero, Peasants, Swordsmen, a Knight and a Pegasus Knight (test hook spawns), one wounded.
	var group: Array = [hero]
	var types := ["AHBX", "AHBX", "AHBX", "AHKX", "AHKX", "AHMX", "AHFX"]
	for k in types.size():
		var u = scene.add_unit(types[k], scene.navigator.free_cell_near(hero.cell + Vector2i(2 + k % 4, 2 + k / 4)), 0)
		if u != null: group.append(u)
	for i in 5: scene.simulation_step(1.0 / 30.0)
	if group.size() > 2 and scene.combat.fighters.has(group[2].unit_id):
		var f = scene.combat.fighters[group[2].unit_id]
		f.hp = maxi(1, int(f.max_hp) / 3)
	for u in scene.units: u.selected = group.has(u)
	await shot("2_multi_selection")
	scene.queue_free()
	quit(0)
