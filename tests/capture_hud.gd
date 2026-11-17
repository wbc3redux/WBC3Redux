extends SceneTree
## HUD pass captures with the real renderer (not part of -Check): the control panel with the hero selected, the panel's
## round buttons and the dialogs they open, into .local/hud_capture_*.png. Copied profile and settings; run with a window:
##   Godot --path . --script res://tests/capture_hud.gd [-- --size=WxH]

const Setup = preload("res://simulation/skirmish_setup.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Settings = preload("res://simulation/game_settings.gd")

func _initialize():
	call_deferred("run")

func shot(name: String):
	for i in 3: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.local/hud_capture_%s.png" % name)

## UI gaps (UI_RESEARCH.md "Interface gaps"): the shop dialog 12 with an artifact and a set item, a potion at 9 (No Room)
## and an unaffordable item (red frame, Too Expensive); then the inventory with pictures, labels and potion counts.
func shop_and_inventory_shots(scene):
	if scene.encounters == null or scene.hero_unit_id < 0: return
	var hero = scene.units[scene.hero_unit_id]
	var shop: int = scene.encounters.place_site("BSFG", 6, scene.navigator.free_cell_near(hero.cell + Vector2i(6, 6)))
	scene.encounters.shops_ready = false
	scene.simulation_step(0.05)
	if not scene.encounters.shops.has(shop): return
	scene.encounters.shops[shop].items = [15, 80]          # Blackfire Axe (artifact), Helm of the Gods (set, row 7)
	scene.encounters.shops[shop].percent[0] = 100
	scene.economy.stockpiles[0] = [1500, 1500, 1500, 1500]
	scene.hero_match.potions = 9
	scene.hud.open_shop(shop)
	scene.hud.dialog_hover = 3
	await shot("3_shop_set_item")
	scene.hud.dialog_hover = 2
	await shot("3_shop_artifact")
	scene.hud.dialog_hover = 1
	await shot("3_shop_mana")
	scene.hud.close_dialog()
	scene.hero_match.receive_item(13, "capture")           # Ring of Health (row 5) and the shop's two items
	scene.hero_match.receive_item(15, "capture")
	scene.hero_match.receive_item(80, "capture")
	scene.open_inventory(-1)
	await shot("4_inventory_items")
	scene.close_inventory()

func run():
	var size := Vector2i(1920, 1080)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--size="): size = Vector2i(int(arg.get_slice("=", 1).get_slice("x", 0)), int(arg.get_slice("=", 1).get_slice("x", 1)))
	root.size = size
	Settings.use_file("user://hud-capture-settings.cfg")
	var directory := "user://hud-capture-heroes"
	var store := Store.new(directory)
	var profile = Profile.create("capture-hud", "WWWWWWWWWWWWWWWWWWW")
	for skill in profile.data.skills:
		if int(skill.id) == 21: skill.rank = 3                           # Divination: its first three spells
	store.save_profile(profile)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	var map: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map.json"))
	var setup := Setup.defaults(map)
	setup.players[0].kind = Setup.HUMAN
	setup.players[0].hero_id = "capture-hud"
	Setup.set_kind(setup, 1, Setup.COMPUTER, 0)
	scene.start_skirmish(setup, "capture-hud", store, "capture-hud-match")
	for i in 40: scene.simulation_step(1.0 / 30.0)
	scene.hud.select_hero()
	await shot("1_hero")
	if scene.encounters != null:
		var r: Dictionary = scene.encounters.quest_records()[0]
		scene.encounters.quests[scene.local_player] = {"record": r, "building": -1, "progress": 1, "deadline_ms": 0}
	for kind in ["menu", "diplomacy", "quest", "spellbook", "inventory"]:
		print("%s opens: %s" % [kind, scene.hud.press_round(kind)])
		if kind == "diplomacy":
			scene.hud.diplomacy_press(1)
			scene.hud.diplomacy_press(6)
			scene.hud.diplomacy_press(10 + scene.hud.diplomacy_players()[0])
		if kind == "spellbook": scene.hud.spell_hover = 1
		if kind == "inventory": print("inventory dialog ", scene.hud.dialog == "inventory")
		await shot("2_" + kind)
		scene.hud.close_dialog()
	await shop_and_inventory_shots(scene)
	scene.queue_free()
	await process_frame
	for filename in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	DirAccess.remove_absolute("user://hud-capture-settings.cfg")
	quit()
