extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	var menu = preload("res://menus/hero_menu.tscn").instantiate()
	var directory := "user://hero-menu-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	menu.store.directory = directory
	root.add_child(menu)
	await process_frame
	menu.hero_name.text = "UI Knight"
	menu.create_hero()
	if menu.rows.size() != 1:
		printerr("Hero menu creation failed: ", menu.status.text)
		quit(1)
		return
	menu.heroes.select(0)
	menu.select_hero()
	var profile = menu.store.selected_profile()
	if profile == null or profile.data.name != "UI Knight":
		printerr("Hero menu selection failed: ", menu.status.text)
		quit(1)
		return
	menu.refresh()
	if menu.heroes.item_count != 1 or not "UI Knight" in menu.status.text:
		printerr("Hero menu refresh failed.")
		quit(1)
		return
	# FE-1: an Ironman profile (Customize's mode list) is a valid, listed hero, and a deleted one leaves the list.
	var iron = preload("res://simulation/hero_profile.gd").create("iron-ui", "UI Ironman")
	iron.data.mode = "ironman"
	if not menu.store.save_profile(iron):
		printerr("Hero menu Ironman profile refused: ", menu.store.last_error)
		quit(1)
		return
	menu.refresh()
	if menu.rows.size() != 2 or menu.rows.any(func(r): return r.has("error")):
		printerr("Hero menu does not list the Ironman profile.")
		quit(1)
		return
	if not menu.store.delete_profile("iron-ui"):
		printerr("Hero menu delete failed: ", menu.store.last_error)
		quit(1)
		return
	menu.refresh()
	if menu.rows.size() != 1 or menu.heroes.item_count != 1:
		printerr("Hero menu still lists the deleted profile.")
		quit(1)
		return
	for filename in DirAccess.open(directory).get_files():
		DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	print("Hero menu checks passed: create, list, select, refresh, Ironman, delete")
	quit(0)
