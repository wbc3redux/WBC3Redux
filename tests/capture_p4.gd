extends SceneTree
## P-4 captures with the real renderer (not part of -Check): a fogged area (explored, not visible) right of the hero with
## an enemy caster's spell art and emitter bursts there, a burning enemy Watch Tower, an enemy missile flying enemy-on-enemy
## through the fog, an enemy missile at the local hero (marked: drawn) and a Couatl meteor (a sky missile: drawn), first
## with fog on, then the same moment with fog off. Writes .local/p4_*.png. Run with a window:
##   Godot --path . --script res://tests/capture_p4.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")
const ParticleBursts = preload("res://visuals/particle_bursts.gd")

var scene
var region: Rect2i

func _initialize():
	call_deferred("run")

func shot(name: String):
	scene.process_mode = Node.PROCESS_MODE_DISABLED     # no game update between the state printed and the picture
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/p4_%s.png" % name)
	scene.process_mode = Node.PROCESS_MODE_INHERIT
	print("shot ", name)

## Keeps the region fogged: explored, not visible (the sweep only lights the local discs, but be sure).
func fog_region():
	var v = scene.visibility
	v.fog = true
	v.shroud = true
	v.ensure(0)
	for y in range(region.position.y, region.end.y):
		for x in range(region.position.x, region.end.x):
			if x < 0 or y < 0 or x >= v.width or y >= v.height: continue
			v.visible[0][y * v.width + x] = 0
			v.explored[0][y * v.width + x] = 1
	scene.apply_fog_to_nodes()
	scene.refresh_fog_overlay()

func steps(seconds: float):
	for i in int(seconds * 30.0):
		scene.simulation_step(1.0 / 30.0)
		fog_region()

func run():
	root.size = Vector2i(1600, 900)
	Settings.use_file("user://p4-capture-settings.cfg")
	var store := Store.new("user://p4-capture-heroes")
	var profile = Profile.create("capture-p4", "c")
	store.save_profile(profile)
	scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-p4"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	for i in 2: Setup.set_race(setup, i, Setup.KNIGHT)
	scene.start_skirmish(setup, "capture-p4", store, "capture-p4")
	var hero = scene.unit_by_id(scene.hero_unit_id)
	region = Rect2i(hero.cell + Vector2i(17, -10), Vector2i(20, 20))
	steps(0.5)
	var fx = scene.effects
	var c0: Vector2i = hero.cell + Vector2i(25, 0)
	scene.centre_view(Vector2((hero.cell.x + 17) * 32, hero.cell.y * 24))
	# The enemy caster in the fog: an enemy unit with spell art (EZ10 looping on it, EZ02 once), an emitter (ECHC) and a
	# fizzle burst at it; an enemy Watch Tower set burning; a missile enemy-on-enemy through the fog, one at the hero.
	var made: Dictionary = scene.combat.spells.spawn("AHKX", c0, 1, 0, 0)
	var caster = scene.unit_by_id(int(made.id)) if not made.is_empty() else null
	var victim_made: Dictionary = scene.combat.spells.spawn("AHKX", c0 + Vector2i(4, 5), 1, 0, 0)
	var tower = scene.production.add_completed(1, "BWTC", c0.x - 3, c0.y - 6)
	steps(0.2)
	if caster != null:
		var px := Vector2i(int(caster.position.x), int(caster.position.y))
		fx.spawn_effect("EZ10", px, caster.cell.y, false, 0, caster, int(scene.combat.now_ms) + 8000)
		fx.spawn_effect("EZ02", px, caster.cell.y, false)
		fx.spawn_effect("ECHC", px, caster.cell.y, false, 0, caster, int(scene.combat.now_ms) + 8000)
		fx.bursts.burst(ParticleBursts.FIZZLE, px, caster.cell.y + 1, fx.now())
	if tower != null: tower.hit_points = int(tower.max_hit_points) / 5
	var rng = scene.combat.rng
	var shooter := {"kind": "unit", "owner": 1, "cell": c0 + Vector2i(-2, -6), "rect": [(c0.x - 2) * 32, (c0.y - 6) * 24, 32, 24],
		"launch_offset": Vector2i.ZERO, "combat": 100, "roll": 1, "flags_ba": 0, "high": false, "elevation": 0}
	if not victim_made.is_empty():
		var m: Dictionary = scene.combat.Missiles.create("EMF0", shooter, scene.combat._missile_target("unit", int(victim_made.id)), rng, scene.combat.now_ms, scene.combat._map_size())
		m.merge({"attacker": -1, "attacker_kind": "unit", "damage": 0, "dtype": 0, "target_kind": "unit", "target_id": int(victim_made.id),
			"launch_ms": scene.combat.now_ms, "from": shooter.cell, "to": m.aim, "owner": 1})
		scene.combat.missiles.append(m)
	var at_hero: Dictionary = scene.combat.Missiles.create("EMF0", shooter.merged({"cell": c0 + Vector2i(-2, 6), "rect": [(c0.x - 2) * 32, (c0.y + 6) * 24, 32, 24]}, true),
		scene.combat._missile_target("unit", int(hero.unit_id)), rng, scene.combat.now_ms, scene.combat._map_size())
	at_hero.merge({"attacker": -1, "attacker_kind": "unit", "damage": 0, "dtype": 0, "target_kind": "unit", "target_id": int(hero.unit_id),
		"launch_ms": scene.combat.now_ms, "from": c0 + Vector2i(-2, 6), "to": at_hero.aim, "owner": 1})
	scene.combat.missiles.append(at_hero)
	scene.combat.launch_meteor(c0 + Vector2i(2, -8), c0 + Vector2i(-4, 7))
	steps(0.35)
	var shown := func(): return {"effects": fx.effects.filter(func(e): return e.alive and e.node.visible).map(func(e): return e.code),
		"bursts drawn": fx.bursts.bursts.filter(func(b): return b.has("node") and b.node.visible).size(), "bursts": fx.bursts.bursts.size(),
		"emitters": fx.bursts.emitters.size(), "missiles drawn": fx.missile_nodes.filter(func(n): return n.visible).size(),
		"missiles": scene.combat.missiles.size(), "fires": fx.burning.size()}
	print("fog on: ", shown.call())
	await shot("1_fog_on")
	# The same moment with fog of war off: everything shows.
	scene.visibility.fog = false
	scene.visibility.shroud = false
	scene.apply_fog_to_nodes()
	scene.refresh_fog_overlay()
	for i in 2: scene.simulation_step(1.0 / 30.0)
	print("fog off: ", shown.call())
	await shot("2_fog_off")
	quit()
