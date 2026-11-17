extends SceneTree
## P-1 captures with the real renderer (not part of -Check): a destroyed building's explosions and ESMR smoke, the death
## remains EDTH after a corpse's hold, floating texts (Gained Level, Spell Failed with its fizzle burst) and the
## strategic-map alert box. Writes .local/p1_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_p1.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/p1_%s.png" % name)
	print("shot ", name)

func steps(scene, seconds: float):
	for i in int(seconds * 30.0): scene.simulation_step(1.0 / 30.0)

func run():
	root.size = Vector2i(1600, 900)
	Settings.use_file("user://p1-capture-settings.cfg")
	var store := Store.new("user://p1-capture-heroes")
	var profile = Profile.create("capture-p1", "c")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-p1"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-p1", store, "capture-p1")
	steps(scene, 1.0)
	if scene.visibility != null: scene.visibility.set("fog", false)
	var hero = scene.unit_by_id(scene.hero_unit_id)
	# 1. A building destroyed: EX01 / EX02, then the ESMR smoke bursts (P-1).
	var target = null
	for b in scene.production.buildings.values():
		if int(b.owner) == 0 and not String(b.original_type_id).substr(1, 2) == "KK" and int(b.definition.footprint[0]) >= 3: target = b
	if target == null:
		for b in scene.production.buildings.values():
			if int(b.owner) == 0 and not String(b.original_type_id).substr(1, 2) == "KK": target = b
	if target != null:
		print("destroying ", target.original_type_id, " footprint ", target.definition.footprint)
		scene.centre_view(target.position)
		scene.combat.apply_damage("building", int(target.entity_id) if target.get("entity_id") != null else int(target.id), 100000, -1)
		steps(scene, 0.25)
		await shot("1_destroyed")
		steps(scene, 0.35)
		await shot("2_smoke")
		steps(scene, 0.5)
		await shot("2b_smoke_late")
		var parts := 0
		for b in scene.effects.bursts.bursts: parts += b.draws.size()
		print("particles drawn ", parts)
		print("bursts ", scene.effects.bursts.bursts.size(), " emitters ", scene.effects.bursts.emitters.size())
	# 2. Floating texts and the fizzle at the hero.
	scene.centre_view(hero.position)
	scene.combat.rank_gained.emit(hero.unit_id, 1)
	var f = scene.combat.fighters[hero.unit_id]
	f["cooldown_start"] = int(scene.combat.now_ms)
	scene.combat.spells.notice.emit("The spell failed")
	steps(scene, 0.2)
	await shot("3_texts")
	steps(scene, 0.6)
	await shot("4_texts_later")
	print("texts ", scene.effects.texts.texts.size())
	# 2b. An ESMR emitter on open ground beside the hero (no explosion over it).
	scene.effects.bursts.emit("ESMR", hero.cell + Vector2i(4, 0), scene.effects.now())
	steps(scene, 0.4)
	await shot("4b_smoke_open")
	# 3. The strategic-map alert box.
	scene.strategic_alert(Vector2i(hero.cell.x + 20, hero.cell.y - 10), true)
	steps(scene, 0.1)
	await shot("5_ping_early")
	steps(scene, 0.5)
	await shot("6_ping_held")
	# 4. A death's remains: an enemy Swordsman killed beside the hero, after the corpse hold (30.7 s).
	var victim = scene.add_unit("AHKX", scene.navigator.free_cell_near(hero.cell + Vector2i(2, 1)), 1)
	scene.combat.apply_damage("unit", victim.unit_id, 100000, -1)
	steps(scene, 32.0)
	scene.centre_view(victim.position)
	await shot("7_remains")
	var remains := 0
	for e in scene.effects.effects:
		if String(e.code).begins_with("EDT"): remains += 1
	print("remains effects ", remains, " code ", scene.effects.death_codes.get(victim.unit_id, "?"))
	quit()
