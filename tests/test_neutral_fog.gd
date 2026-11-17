extends SceneTree
## Playtest 2026-11-10 (Cavern Wars): the neutral Undead encampment did not fight back. Under fog of war the target search
## tested the neutral player's own fog map, which is never lit; 0x5334f0 reads the machine's one fog object (0x47f560),
## so a neutral guard finds targets where the local player sees (combat.gd fog_viewer). A neutral Skeleton with the
## Defensive script beside the player's Swordsman must attack it; with the fog viewer pointed at a side that sees
## nothing there, it must not (the fog test still applies).
##   Godot --headless --path . --script res://tests/test_neutral_fog.gd

const Setup = preload("res://simulation/skirmish_setup.gd")

var checks := 0
var failures := 0

func _initialize():
	call_deferred("run")

func check(ok: bool, label: String):
	checks += 1
	if not ok:
		failures += 1
		printerr("Neutral fog check failed: " + label)

func play(blind: bool) -> int:
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	Setup.set_kind(setup, 0, Setup.COMPUTER, 0)
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	scene.start_skirmish(setup, "", null, "neutral-fog")
	var c = scene.combat
	c.ai_players.erase(0)                                      # side 0 acts as the human: it keeps the fog test
	for p in scene.ai_manager.players.size(): if p < 6: scene.ai_manager.players[p] = null
	c.fog_viewer = 1 if blind else 0
	var home: Vector2i = scene.skirmish.slots[0].start
	var mine = scene.add_unit("AHKX", scene.navigator.free_cell_near(home + Vector2i(6, 0)), 0)
	var skeleton = scene.add_unit("AUIX", scene.navigator.free_cell_near(mine.cell + Vector2i(2, 0)), 6)
	c.ai.assign_script(c.fighters[skeleton.unit_id], 2)       # Defensive (the encampment's script)
	var hits := {"n": 0}
	c.damaged.connect(func(kind, id, amount, attacker): if kind == "unit" and id == mine.unit_id and attacker == skeleton.unit_id: hits.n += 1)
	for i in 40 * 8: scene.simulation_step(0.025)
	check(scene.visibility.fog, "fog of war is on")
	var n: int = hits.n
	scene.queue_free()
	await process_frame
	return n

func run():
	var sees: int = await play(false)
	check(sees > 0, "a neutral Defensive guard attacks the unit the local player sees (%d hits)" % sees)
	var blind: int = await play(true)
	check(blind == 0, "with a fog viewer that sees nothing there it finds no target (%d hits)" % blind)
	if failures > 0:
		print("Neutral fog checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Neutral fog checks passed: %d (%d hits, blind %d)" % [checks, sees, blind])
	quit(0)
