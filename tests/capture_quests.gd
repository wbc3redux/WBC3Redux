extends SceneTree
## Q-2 captures with the real renderer (not part of -Check): the quest site dialog in offer mode, the q sheet of an
## accepted quest and a resource quest's sheet, into .local/quest_capture_*.png. Copied profile and settings; run with a
## window:   Godot --path . --script res://tests/capture_quests.gd

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/quest_capture_%s.png" % name)

func run():
	root.size = Vector2i(1920, 1080)
	Settings.use_file("user://quest-capture-settings.cfg")
	var directory := "user://quest-capture-heroes"
	var store := Store.new(directory)
	store.save_profile(Profile.create("capture-quest", "Sir Quest"))
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-quest"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	scene.start_skirmish(setup, "capture-quest", store, "capture-quest-match")
	for i in 30: scene.simulation_step(1.0 / 30.0)
	var site := -1
	for id in scene.encounters.givers: site = int(id)
	var records: Array = scene.encounters.quest_records("BZMA")
	var longest: Dictionary = records[0]
	var deliver: Dictionary = {}
	for r in records:
		if String(r.get("newq", "")).length() > String(longest.get("newq", "")).length(): longest = r
		if int(r.type) == 0 and deliver.is_empty(): deliver = r
	scene.hud.open_quest_offer({"building": site, "mode": "offer", "record": longest})
	scene.hud.dialog_hover = scene.hud.QUEST_HOVER_OKAY
	await shot("1_offer")
	scene.hud.close_dialog()
	scene.encounters.quests[scene.local_player] = {"record": longest, "building": site, "progress": 1, "deadline_ms": 0}
	print("quest opens: ", scene.hud.press_round("quest"))
	await shot("2_sheet")
	scene.hud.close_dialog()
	scene.encounters.quests[scene.local_player] = {"record": deliver, "building": site, "progress": 0, "deadline_ms": 0}
	scene.hud.press_round("quest")
	await shot("3_resource_sheet")
	scene.hud.close_dialog()
	scene.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute("user://quest-capture-settings.cfg")
	quit()
