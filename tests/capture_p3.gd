extends SceneTree
## P-3 captures with the real renderer (not part of -Check): the emitter effects (a soul's ESSP, the soul mana EMLE, the
## egg ECHE, Plague Cloud's ECHC, EBLS over its EZ21), the record texts (Spell Resisted, Critical: Stun with EZ10 / EZ63,
## Petrify, Recovering, Critical: Burn), the attack marker while Shift is held, a tower's Speed / Damage / Range rows.
## Writes .local/p3_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_p3.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/p3_%s.png" % name)
	print("shot ", name)

func steps(scene, seconds: float):
	for i in int(seconds * 30.0): scene.simulation_step(1.0 / 30.0)

func shift(on: bool):
	var e := InputEventKey.new()
	e.keycode = KEY_SHIFT
	e.physical_keycode = KEY_SHIFT
	e.pressed = on
	Input.parse_input_event(e)

func run():
	root.size = Vector2i(1600, 900)
	Settings.use_file("user://p3-capture-settings.cfg")
	var store := Store.new("user://p3-capture-heroes")
	var profile = Profile.create("capture-p3", "c")
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-p3"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-p3", store, "capture-p3")
	steps(scene, 1.0)
	if scene.visibility != null: scene.visibility.set("fog", false)
	scene.apply_fog_to_nodes()
	scene.refresh_fog_overlay()
	var hero = scene.unit_by_id(scene.hero_unit_id)
	scene.centre_view(hero.position)
	var fx = scene.effects
	var at := func(dx: int, dy: int) -> Vector2i: return hero.cell + Vector2i(dx, dy)
	# 1. Emitters: a soul (ESSP), the egg (ECHE), Plague Cloud (ECHC), EBLS over EZ21, the soul mana on the hero (EMLE).
	scene.combat.race_event.emit("soul", {"cell": at.call(-5, 0)})
	scene.combat.race_event.emit("egg", {"cell": at.call(-2, 3), "effect": "ECHE"})
	for code_cell in [["ECHC", at.call(3, 3)], ["EBLS", at.call(6, 0)], ["EARC", at.call(3, -3)]]:
		var c: Vector2i = code_cell[1]
		fx.spawn_effect(String(code_cell[0]), Vector2i(c.x * 32 + 16, c.y * 24 + 12), c.y, true)
	scene.combat.race_event.emit("soul_mana", {"id": hero.unit_id, "effect": "EMLE"})
	steps(scene, 0.2)
	print("emitters ", fx.bursts.emitters.size(), " bursts ", fx.bursts.bursts.size())
	await shot("1_emitters")
	steps(scene, 0.4)
	await shot("1b_emitters_later")
	# 2. Texts over units: Spell Resisted, Critical: Stun (EZ10 / EZ63), Petrify, Recovering, Critical: Burn.
	var others: Array = []
	for d in [Vector2i(-4, 2), Vector2i(0, 4), Vector2i(4, 2)]:
		var made: Dictionary = scene.combat.spells.spawn("AHKX", hero.cell + d, 0, 0, 0)
		if not made.is_empty(): others.append(scene.unit_by_id(int(made.id)))
	steps(scene, 0.1)
	print("own units ", others.size())
	fx._present_p3({"kind": 0x10}, {"resisted": [hero.unit_id]})
	if others.size() > 0: fx._present_p3({"kind": fx.STUN_KIND}, {"statuses": [{"id": others[0].unit_id, "status": {"until": int(scene.combat.now_ms) + 4000}}]})
	if others.size() > 1: fx.petrify_text(others[1].unit_id)
	scene.combat.spells.floated.emit({"id": hero.unit_id, "line": 0x47e, "value": 0, "colour": 1, "ms": 1000, "owner": 0, "local_only": true})
	if others.size() > 2: scene.combat.spells.berserk({"kind": "unit", "id": others[2].unit_id}, 0)
	steps(scene, 0.9)
	await shot("2_texts")
	# 3. The attack marker: the hero attacks an enemy unit; Shift held shows the square and the attack icon at the target.
	var spawned: Dictionary = scene.combat.spells.spawn("AHKX", hero.cell + Vector2i(7, -3), 1, 0, 0)
	steps(scene, 0.1)
	var enemy = scene.unit_by_id(int(spawned.id)) if not spawned.is_empty() else null
	if enemy != null:
		scene.centre_view((hero.position + enemy.position) * 0.5)
		hero.selected = true
		scene.pick_object(hero)
		var ok: bool = scene.combat.order_attack(hero.unit_id, "unit", enemy.unit_id)
		shift(true)
		for i in 6: await process_frame
		print("attack ", ok, " entries ", scene.order_layer.entries.map(func(e): return e.type))
		await shot("3_attack_marker")
		shift(false)
		scene.combat.order_stop(hero.unit_id)
	# 4. A tower's rows: an own Watch Tower beside the hero, selected.
	var tower = scene.production.add_completed(0, "BWTC", hero.cell.x + 3, hero.cell.y - 5)
	steps(scene, 0.2)
	if tower != null:
		hero.selected = false
		scene.pick_object(tower)
		scene.centre_view(tower.position)
		await shot("4_tower_rows")
	quit()
