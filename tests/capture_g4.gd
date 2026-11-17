extends SceneTree
## G-4 captures with the real renderer (not part of -Check): the critical-hit texts and art (Freeze, Mana Drain, XP
## Drained, Armor Reduced, Ignore Armor, Cleave, Assassinate) over units, and a garrisoned tower's view (title, rows,
## occupants' faces). Writes .local/g4_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_g4.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const Criticals = preload("res://simulation/criticals.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/g4_%s.png" % name)
	print("shot ", name)

func steps(scene, seconds: float):
	for i in int(seconds * 30.0): scene.simulation_step(1.0 / 30.0)

func run():
	root.size = Vector2i(1600, 900)
	Settings.use_file("user://g4-capture-settings.cfg")
	var store := Store.new("user://g4-capture-heroes")
	var profile = Profile.create("capture-g4", "c")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-g4"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-g4", store, "capture-g4")
	steps(scene, 1.0)
	if scene.visibility != null: scene.visibility.set("fog", false)
	scene.apply_fog_to_nodes()
	scene.refresh_fog_overlay()
	var hero = scene.unit_by_id(scene.hero_unit_id)
	scene.centre_view(hero.position)
	var c = scene.combat
	# 1. Texts and art over own units.
	var others: Array = []
	for d in [Vector2i(-5, 1), Vector2i(-2, 4), Vector2i(2, 4), Vector2i(5, 1), Vector2i(0, -4)]:
		var made: Dictionary = c.spells.spawn("AHKX", hero.cell + d, 0, 0, 0)
		if not made.is_empty(): others.append(c.fighters[int(made.id)])
	steps(scene, 0.1)
	print("units ", others.size())
	if others.size() >= 5:
		Criticals.freeze(c, others[0])
		others[1]["mana"] = 30
		others[1]["max_mana"] = 50
		others[1]["mana_ms"] = 0
		Criticals.mana_drain(c, others[1], 40)
		others[2].xp = 20
		Criticals.xp_drain(c, others[2], 10)
		Criticals.armour_reduced(c, others[3], 2)
		Criticals.ignore_armour(c, others[4], 1)
	steps(scene, 0.6)
	await shot("1_crit_texts")
	# 2. A Watch Tower with two occupants, selected: "Tower", five rows, two faces.
	var tower = scene.production.add_completed(0, "BWTC", hero.cell.x + 3, hero.cell.y - 5)
	steps(scene, 0.2)
	if tower != null and others.size() >= 2:
		for f in [others[0], others[1]]: scene.unit_commands.enter(int(tower.entity_id), int(f.id))
		hero.selected = false
		scene.pick_object(tower)
		scene.centre_view(tower.position)
		await shot("2_tower_view")
	quit()
