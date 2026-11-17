extends Control
const Effects = preload("res://simulation/hero_effects.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
var store := Store.new()
var heroes := ItemList.new()
var hero_name := LineEdit.new()
var status := Label.new()
var rows: Array = []

func _ready():
	preload("res://core/audio_manager.gd").instance(get_tree()).menu_entered()   # the theme starts at the first menu entry (0x41d2c0)
	var box := VBoxContainer.new()
	box.position = Vector2(32, 32)
	box.size = Vector2(760, 600)
	add_child(box)
	var heading := Label.new()
	heading.text = "SKIRMISH HEROES · Knights / Warrior"
	box.add_child(heading)
	var note := Label.new()
	note.text = "Rebuild profiles are saved under user://heroes/.\nSelect a hero, then open the skirmish setup (milestone 10a). XP, items and battles are written back after a match."
	box.add_child(note)
	heroes.custom_minimum_size = Vector2(700, 260)
	box.add_child(heroes)
	hero_name.placeholder_text = "Hero name (1–19 characters)"
	hero_name.max_length = 19
	box.add_child(hero_name)
	var create := Button.new()
	create.text = "Create Knight / Warrior"
	create.pressed.connect(create_hero)
	box.add_child(create)
	var select := Button.new()
	select.text = "Select hero for skirmish"
	select.pressed.connect(select_hero)
	box.add_child(select)
	var skirmish := Button.new()
	skirmish.text = "Skirmish setup..."
	skirmish.pressed.connect(func(): get_tree().change_scene_to_file("res://menus/skirmish_menu.tscn"))
	box.add_child(skirmish)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	refresh()

func refresh():
	heroes.clear()
	rows = store.list_profiles()
	for row in rows:
		if row.has("error"):
			heroes.add_item(row.id + " · " + row.error)
			continue
		var p = store.load_profile(row.id)
		var items: Array = p.data.backpack.filter(func(i): return not i.is_empty()).map(func(i): return int(i.get("item", -1)))
		var worn: Array = p.data.equipment.filter(func(i): return not i.is_empty()).map(func(i): return Effects.item_name(int(i.get("item", -1))))
		heroes.add_item("%s · level %d · %d XP · battles %d (won %d) · backpack %s · equipped %s · Knight / Warrior" % [row.name, row.level, int(p.data.xp),
			int(p.data.history.battles_fought), int(p.data.history.battles_won), str(items), ", ".join(worn) if not worn.is_empty() else "-"])
	var selected = store.selected_profile()
	status.text = "No hero selected." if selected == null else "Selected: " + selected.data.name
	if selected == null and not store.last_error.is_empty(): status.text = store.last_error

func create_hero():
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	var profile = Profile.create(id, hero_name.text)
	if not store.save_profile(profile):
		status.text = store.last_error
		return
	hero_name.clear()
	refresh()
	status.text = "Created " + profile.data.name + ". Select it from the list."

func select_hero():
	var selected := heroes.get_selected_items()
	if selected.is_empty():
		status.text = "Select a hero from the list."
		return
	if not store.select_profile(rows[selected[0]].id):
		status.text = store.last_error
		return
	refresh()
