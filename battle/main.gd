extends Node2D

const AnimationData = preload("res://core/animation_data.gd")
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Selection = preload("res://battle/selection.gd")
const AiSites = preload("res://simulation/ai_sites.gd")   # AI-7
const Benchmark = preload("res://devtools/movement_benchmark.gd")
const Economy = preload("res://simulation/economy.gd")
const Rules = preload("res://simulation/production_rules.gd")
const Production = preload("res://simulation/production.gd")
const Placement = preload("res://simulation/placement.gd")
const BuildingMarker = preload("res://battle/building_marker.gd")
const Combat = preload("res://simulation/combat.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")
const Missiles = preload("res://simulation/missiles.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const RetinueScan = preload("res://simulation/retinue_scan.gd")
const Visibility = preload("res://simulation/visibility.gd")
const HeroProfile = preload("res://simulation/hero_profile.gd")
const HeroMatch = preload("res://simulation/hero_match.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")
const Treasures = preload("res://simulation/treasures.gd")
const HeroAdvance = preload("res://menus/hero_advance.gd")
const EntityState = preload("res://simulation/entity_state.gd")
const Encounters = preload("res://simulation/encounters.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const SkirmishSetup = preload("res://simulation/skirmish_setup.gd")
const SkirmishMatch = preload("res://simulation/skirmish_match.gd")
const ArmySetup = preload("res://simulation/army_setup.gd")
const HeroStore = preload("res://simulation/hero_store.gd")
const UiCanvas = preload("res://core/ui_canvas.gd")
const AudioManager = preload("res://core/audio_manager.gd")
const MapData = preload("res://core/map_data.gd")
# R-1: main.gd's functions by area, in helper scripts that hold no state (README.md "Where things are").
const MainOrders = preload("res://battle/main_orders.gd")
const MainBuild = preload("res://battle/main_build.gd")
const MainCombat = preload("res://battle/main_combat.gd")
const MainCaptures = preload("res://battle/main_captures.gd")
const MainMatch = preload("res://battle/main_match.gd")
const MainHero = preload("res://battle/main_hero.gd")
const MainAi = preload("res://battle/main_ai.gd")
const MainPowers = preload("res://battle/main_powers.gd")
const MainSave = preload("res://battle/main_save.gd")
var _orders := MainOrders.new(self)
var _build := MainBuild.new(self)
var _combat := MainCombat.new(self)
var _captures := MainCaptures.new(self)
var _match := MainMatch.new(self)
var _hero := MainHero.new(self)
var _ai := MainAi.new(self)
var _powers := MainPowers.new(self)
var _save := MainSave.new(self)
# Player input for the sound layer (AUDIO_RESEARCH.md): the simulation does not see selections or order clicks.
signal units_selected(ids: Array)
signal units_ordered(ids: Array)
signal building_selected(id: int)
signal build_order(unit_id: int, accepted: bool)
var audio: Node
const SPAWN_CELLS = [Vector2i(12,64), Vector2i(13,64), Vector2i(14,64), Vector2i(12,66), Vector2i(13,66), Vector2i(14,66)]

var collision = CollisionData.new()
var navigator = Navigation.new(collision)
var units: Array = []
var map_objects: Array = []
var camera := Camera2D.new()
var collision_overlay := Sprite2D.new()
var drag_active := false
var suppress_release := false
var drag_start := Vector2.ZERO
var drag_end := Vector2.ZERO
var show_paths := true
var status := Label.new()
var instruction := Label.new()
var map: Dictionary
var terrain_layer: Node2D                 # terrain_layer.gd: the map's MAPH records
var command_number := 0
var simulation_time := 0.0
var last_requested := Vector2(-1, -1)
var last_message := "Ready. Six Swordsmen are a test fixture, not an original starting army."
var selection_layer = preload("res://hud/selection_overlay.gd").new()
# Milestone 7 (construction/production). The fixture below is a test harness, not the original start.
const FIXTURE_RESOURCES = [500, 500, 500, 500] # gold, metal, crystal, stone; match start values are unrecovered
var economy: RefCounted
var production: RefCounted
var building_nodes: Dictionary = {}
var selected_building_id := -1
var build_mode := ""
var rally_mode := false
var pending_builds: Dictionary = {} # unit id -> {"type", "cell"}
var production_status := Label.new()
# Milestone 8 (combat and visibility). Test harness state, not an original match setup.
var combat: RefCounted
var visibility: RefCounted
var combat_status := Label.new()
var fog_overlay := Sprite2D.new()
var fog_image: Image
var fog_next_ms := 0
var combat_seed := [0x1badb002, 0x2468ace0] # the skirmish seed is created by the setup screen and is not recovered
var hero_unit_id := -1
var hero_match: RefCounted
var local_player := 0
var attitude_index := 2
# Milestone 9 (encounters): neutral buildings, lair, quests and animals. Test harness state, not an original match setup.
var encounters: RefCounted
var catalogue_data: Dictionary
var treasures                            # Treasures: item piles on the map (milestone 11)
var treasure_units: Dictionary = {}       # unit id -> true: status 0x1a (drops a treasure item when it dies)
var encounter_data: Dictionary
var ai_data: Dictionary
var mausoleum_id := -1
var lair_id := -1
var layout_cache: Dictionary = {}
# Milestone 10a (skirmish match): the setup screen's match, its heroes and the results screen.
var skirmish: RefCounted                 # SkirmishMatch while a match runs (null in the fixtures)
var hero_store: RefCounted
var match_profiles: Dictionary = {}      # owner -> profile waiting for its hero unit
var match_heroes: Dictionary = {}        # owner -> HeroMatch
var no_hero_items := false               # setup rows: More Options "No Hero Items" (0x749c68), given to every bound hero
var match_status := Label.new()
var match_controls: HBoxContainer
var results_layer: CanvasLayer
var results_screen: Control              # results_screen.gd (PNL_VICTORYDEFEAT_NEW and the advanced results)
var end_box: Node2D                      # the EZDV / EZDD box after the stinger (parity pass 2)
var end_phase := ""                      # "" | "stinger" | "box" | "results"
var end_won := false
var results_tracking: Dictionary = {}    # parity pass 2: resources in / out and kills / razes by side for the advanced results
var after_results := "res://menus/hero_menu.tscn"
# Milestone 10b (computer player): the map's mines, unit orders on mines, and the AI.
const Mines = preload("res://simulation/mines.gd")
const MatchConversion = preload("res://simulation/match_conversion.gd")
const AiManager = preload("res://simulation/ai_manager.gd")
const CustomAi = preload("res://simulation/custom_ai.gd")
const AiPlayer = preload("res://simulation/ai_player.gd")
const AiRules = preload("res://simulation/ai_rules.gd")
const ArtData = preload("res://core/art_data.gd")
var mines: RefCounted
var conversions: RefCounted               # milestone 12: MatchConversion (heroes, generals, AAPH and Keeps convert buildings)
var ai_manager: RefCounted
var build_results: Dictionary = {}       # unit id -> "placed" / "failed" for the latest build walk
# Milestone 11-menus: normal play (a match started from the setup screen) shows the original control panel and dialogs
# (game_hud.gd) instead of the test harness rows; F11 shows the harness (debug key). time_scale is the game-speed clock
# factor (0x458dd0; 0 = paused), set by the HUD.
const GameHud = preload("res://hud/game_hud.gd")
var normal_play := false
var hud: Control
var harness_panel: Panel
var time_scale := 1.0
var scroll_by_hud := false
var mine_orders: Dictionary = {}         # unit id -> {"kind": "enter" / "convert", "mine", "cell", "state"}
var effects                               # effects_layer.gd: missiles, fires, explosions, spawn effects (EFFECTS_RESEARCH.md)
var map_effects                           # map_effects_layer.gd: the scenario's EFFH particle emitters (MAPS_RESEARCH.md "Wave 5")
var visuals                               # enhanced_visuals.gd: the optional modern presentation (ENHANCED_VISUALS.md)

# Parity pass 1 (UI_RESEARCH.md "Parity pass 1"): what the player does with mouse and keyboard during a match.
const CursorSet = preload("res://core/cursor_set.gd")
var cursor: Node                          # cursor_set.gd (normal play)
var target_mode := 0                      # 0x74b984: 0 none, 1 Move, 2 Attack, 4 Patrol, 5 Guard (0x425150 via the grid)
var patrol_points: Array = []             # 0x74bb90 / 0x74c412: Shift-clicked patrol points (at most 15)
var patrol_start := Vector2.ZERO          # 0x74c3e4: the head unit's position when Patrol was pressed
var last_click_object = null              # 0x74b980
var last_click_ms := -100000              # 0x608470 as time (8 ticks of 50 ms)
var control_groups := {}                  # 0..9 -> {"units": [ids] (at most 32), "building": id or -1} (0x425510)
var alerts: Array = []                    # 0x74c38c: up to 8 alert cells, newest first (0x425b90)
var alert_index := 0                      # 0x74c3d8
var minimap_ping = preload("res://hud/minimap_ping.gd").new()   # P-1: the strategic-map alert box (0x4dcf70 / 0x4dc850)
var alert_ms := 0                         # 0x74c3d4
var patrols := {}                         # unit id -> {"points": [Vector2], "next": int} (Provisional order behaviour)
var guards := {}                          # unit id -> {"kind", "id"} (Provisional order behaviour)
var home_cell := Vector2i(-1, -1)         # 0x708fa8: the local player's start (Home centres on it)
var ghost := Sprite2D.new()               # 0x4965d0: the building's sheet under the cursor in placement mode
var hover_info: Dictionary = {}           # the object under the cursor (0x4dd0c0 / 0x405f20), refreshed with the cursor
const UnitCommands = preload("res://simulation/unit_commands.gd")
const UnitRanks = preload("res://simulation/unit_ranks.gd")
var unit_commands = UnitCommands.new()    # wall drag, building repair, tower garrisons (simulation/unit_commands.gd)
var wall_drag = null                      # UnitCommands.WallDrag while the button is held in wall placement (0x74c421)

func _ready():
	audio = AudioManager.instance(get_tree())
	audio.attach(self)
	tree_exiting.connect(func(): audio.detach(self))
	units_selected.connect(audio.on_selected)
	units_ordered.connect(audio.on_ordered)
	building_selected.connect(audio.on_building_selected)
	build_order.connect(audio.on_build_order)
	# W1: the chosen map (MapData.current) is drawn from its MAPH records, not one baked image.
	terrain_layer = preload("res://visuals/terrain_layer.gd").new()
	terrain_layer.z_index = -2 - MapData.depth_offset    # M-2: below every world depth on tall maps (MapData.depth)
	add_child(terrain_layer)
	terrain_layer.setup()
	if not MapData.is_generated(): collision_overlay.texture = MapData.texture("collision_walk.png")   # RM-3: no overlay image
	collision_overlay.centered = false
	collision_overlay.z_index = -1 - MapData.depth_offset
	collision_overlay.scale = Vector2(32,24)
	collision_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_overlay.visible = false
	add_child(collision_overlay)
	effects = preload("res://visuals/effects_layer.gd").new()
	add_child(effects)
	map_effects = preload("res://visuals/map_effects_layer.gd").new()
	add_child(map_effects)
	map_effects.reset(0)
	map = MapData.map()
	var presentations: Dictionary = MapData.objects()
	for placement in presentations.placements:
		var object = preload("res://battle/map_object.gd").new()
		object.configure(placement, presentations.definitions[placement.code])
		add_child(object)
		map_objects.append(object)
	fog_overlay.centered = false
	fog_overlay.scale = Vector2(32, 24)
	fog_overlay.z_index = 4000
	fog_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(fog_overlay)
	BuildingMarker.harness = true
	UnitAgent.local_player = 0
	ghost.visible = false
	ghost.z_index = 3999
	ghost.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(ghost)
	add_child(camera)
	visuals = preload("res://visuals/enhanced_visuals.gd").new()
	visuals.main = self
	add_child(visuals)
	reset_fixture()
	var layer := CanvasLayer.new()
	add_child(layer)
	ui_layer = layer
	var panel := Panel.new()
	panel.size = Vector2(1280, 246)
	layer.add_child(panel)
	harness_panel = panel
	var box := VBoxContainer.new()
	box.position = Vector2(16, 8)
	panel.add_child(box)
	instruction.text = "DESERT SANDS / SELECTION & MOVEMENT\nClick / drag to select · Shift-click toggles · Right-click move · Shift appends · Alt prepends · Ctrl moves at individual speeds\nOriginal grid search, corner rule and cell-step timing (Medium, speed 8 = 464 ms/cell) ported from the executable; group formation slots and 8x8 sector routing follow the executable; selection-list order remains provisional."
	box.add_child(instruction)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	button(controls, "Select all [Ctrl+A]", select_all)
	button(controls, "Stop selected", stop_selected)
	button(controls, "Reset test fixture", reset_fixture)
	button(controls, "Home", center_selection)
	button(controls, "Paths", func(): show_paths = not show_paths; queue_redraw())
	button(controls, "Collision [O]", func(): collision_overlay.visible = not collision_overlay.visible)
	button(controls, "Route demo", route_demo)
	button(controls, "Benchmark report", write_benchmark)
	box.add_child(status)
	var build_controls := HBoxContainer.new()
	box.add_child(build_controls)
	button(build_controls, "Production fixture", spawn_production_fixture)
	# Production buttons carry the original 32 x 50 icons (ANI slot 8 column 1, as 0x4d7710 draws them).
	button(build_controls, "Build Garrison", func(): arm_build("BAGA"), "BAGA")
	button(build_controls, "Build Fletcher", func(): arm_build("BPFL"), "BPFL")
	button(build_controls, "Peasant", func(): queue_item("AHBX"), "AHBX")
	button(build_controls, "Swordsman", func(): queue_item("AHKX"), "AHKX")
	button(build_controls, "Squire", func(): queue_item("AHMX"), "AHMX")
	button(build_controls, "Upgrade Keep", func(): queue_item("BKK1"), "BKK1")
	button(build_controls, "Cancel job", cancel_job)
	button(build_controls, "Cancel all", cancel_all_jobs)
	button(build_controls, "Release builder", release_builder)
	button(build_controls, "Set rally", func(): rally_mode = true; last_message = "Click the map to set the rally point of the selected building (right-click cancels).")
	button(build_controls, "Repeat", toggle_repeat)
	button(build_controls, "+100 each (fixture)", func(): economy.credit(0, [100, 100, 100, 100]))
	box.add_child(production_status)
	# Milestone 11a: one generic row for every race (temporary presentation; the original command panel is not built): the
	# selected builder's construction row (CONSTRUCTION <letter>0 of the local player's race) or the selected building's
	# menu (PRODUCTION row of that race, with the slot gates of 0x40c990), each with its 0x40b6b0 price.
	race_controls = HBoxContainer.new()
	box.add_child(race_controls)
	var combat_controls := HBoxContainer.new()
	box.add_child(combat_controls)
	button(combat_controls, "Combat fixture", spawn_combat_fixture)
	button(combat_controls, "Attack nearest enemy", attack_nearest_selected)
	button(combat_controls, "Fog of war", func(): toggle_fog("fog"))
	button(combat_controls, "Shroud", func(): toggle_fog("shroud"))
	button(combat_controls, "Unit scripts", func(): combat.auto_acquire = not combat.auto_acquire; last_message = "Unit attitude scripts %s (harness switch; the original always runs them)." % ("on" if combat.auto_acquire else "off"))
	button(combat_controls, "Attitude [Ctrl+F]", toggle_attitude)
	button(combat_controls, "Clear enemies (test)", clear_enemies_test)
	var encounter_controls := HBoxContainer.new()
	box.add_child(encounter_controls)
	button(encounter_controls, "Encounters fixture", spawn_encounters_fixture)
	button(encounter_controls, "Quest: visit", quest_visit)
	button(encounter_controls, "Quest: accept", quest_accept)
	button(encounter_controls, "Quest: complete", quest_complete)
	button(encounter_controls, "Lair wave now (test)", lair_wave_test)
	button(encounter_controls, "Destroy Lair (test)", destroy_lair_test)
	box.add_child(combat_status)
	match_controls = HBoxContainer.new()
	box.add_child(match_controls)
	button(match_controls, "Skirmish setup...", func(): get_tree().change_scene_to_file("res://menus/skirmish_menu.tscn"))
	button(match_controls, "Quit match (defeat)", quit_match)
	button(match_controls, "Hero items", toggle_hero_items)
	match_controls.add_child(match_status)
	panel.size = Vector2(1280, 376)
	selection_layer.owner_scene = self
	layer.add_child(selection_layer)
	refresh_status()
	if "--capture-objects" in OS.get_cmdline_user_args(): call_deferred("capture_objects")
	if "--capture-movement" in OS.get_cmdline_user_args(): call_deferred("capture_preview")
	if "--capture-production" in OS.get_cmdline_user_args(): call_deferred("capture_production")
	if "--capture-combat" in OS.get_cmdline_user_args(): call_deferred("capture_combat")
	if "--capture-encounters" in OS.get_cmdline_user_args(): call_deferred("capture_encounters")
	if "--capture-skirmish" in OS.get_cmdline_user_args(): call_deferred("capture_skirmish")
	elif not pending_load.is_empty():          # S-1: a saved game chosen in the load sheet (open_saved_game)
		enable_normal_play()
		call_deferred("load_pending")
	elif not SkirmishSetup.pending.is_empty():
		var pending: Dictionary = SkirmishSetup.pending
		SkirmishSetup.pending = {}
		enable_normal_play()
		# UI gaps: a temporary hero comes from its scratch store (front_end.gd start_temporary_hero).
		call_deferred("start_skirmish", pending.setup, pending.hero_id, HeroStore.new(String(pending.store_dir)) if pending.has("store_dir") else null)

## Normal play (milestone 11-menus): the control panel, the dialogs and the original scrolling replace the harness rows.
func enable_normal_play():
	normal_play = true
	BuildingMarker.harness = false
	harness_panel.visible = false
	scroll_by_hud = true
	after_results = "res://menus/front_end.tscn"  # 0x440e80 / 0x454560: after the results (and the hero screens) the main menu
	preload("res://core/ui_screen.gd").fit_window(get_window())
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	hud = GameHud.new()
	hud.main = self
	hud_layer.add_child(hud)
	cursor = CursorSet.new()
	add_child(cursor)
	cursor.setup(hud.canvas.layout, 1.0)
	collision_overlay.visible = false
	get_viewport().size_changed.connect(apply_view_scale)
	var display_manager = preload("res://core/display.gd").node(get_tree())
	if display_manager != null: display_manager.changed.connect(apply_view_scale)
	apply_view_scale()

## Native resolution (DELIBERATE MODERN CHANGE, display.gd): world pixels, the panel and the cursor at the one shared
## scale of the window; the view keeps its centre and is clamped again.
func apply_view_scale():
	if hud == null: return
	var centre := view_centre()
	hud.update_geometry()
	camera.zoom = Vector2.ONE * hud.scale_factor
	if cursor != null: cursor.set_scale(hud.scale_factor)
	centre_view(centre)

func button(parent: Node, text: String, callback: Callable, icon_code: String = ""):
	var control := Button.new()
	control.text = text
	if icon_code != "":
		# Units: the 32 x 50 column 1; building icon sheets leave column 1 empty, so they show the 90 x 90 column 3
		# (which column the build menu draws for buildings is not traced: decision, EFFECTS_RESEARCH.md).
		control.icon = preload("res://core/art_data.gd").icon(icon_code, 3 if icon_code.begins_with("B") else 1)
		control.add_theme_constant_override("icon_max_width", 32)
	control.focus_mode = Control.FOCUS_NONE
	control.pressed.connect(callback)
	parent.add_child(control)

func reset_fixture():
	end_skirmish()
	for unit in units:
		remove_child(unit)
		unit.free()
	units.clear()
	for i in range(SPAWN_CELLS.size()):
		var unit = UnitAgent.new()
		unit.unit_id = i
		unit.position = navigator.center(SPAWN_CELLS[i])
		unit.navigator = navigator
		unit.selected = true
		add_child(unit)
		units.append(unit)
	simulation_time = 0.0
	last_requested = Vector2(-1,-1)
	camera.position = Vector2(640, 1560)
	camera.zoom = Vector2.ONE
	last_message = "Reset six-unit test fixture; source match initialization remains unverified."
	reset_production()

# Selection, mouse and keyboard orders (R-1: the functions are in main_orders.gd; these forward the ones called by name)
func selected_units() -> Array: return _orders.selected_units()
func own_selected() -> Array: return _orders.own_selected()
func selection_head(): return _orders.selection_head()
func head_is_own_unit() -> bool: return _orders.head_is_own_unit()
func select_all(): _orders.select_all()
func center_selection(): _orders.center_selection()
func stop_selected(): _orders.stop_selected()
func issue_move(requested: Vector2, append: bool = false, prepend: bool = false, individual: bool = false, extra: Dictionary = {}, only: Array = []) -> Dictionary: return _orders.issue_move(requested, append, prepend, individual, extra, only)
func route_demo(): _orders.route_demo()
func finish_selection(event: InputEventMouseButton): return _orders.finish_selection(event)
func set_building_selection(id: int): _orders.set_building_selection(id)
func pick_object(object, add_it: bool = false): _orders.pick_object(object, add_it)
func click_release(point: Vector2, mods: Dictionary): return _orders.click_release(point, mods)
func box_release(box: Rect2, mods: Dictionary): return _orders.box_release(box, mods)
func building_at(point: Vector2, own_only: bool): return _orders.building_at(point, own_only)
func hover_object(point: Vector2) -> Dictionary: return _orders.hover_object(point)
func cursor_context(screen: Vector2) -> Dictionary: return _orders.cursor_context(screen)
func can_garrison_into(unit, hovered: Dictionary) -> bool: return _orders.can_garrison_into(unit, hovered)
func update_cursor(): _orders.update_cursor()
func right_click(point: Vector2, mods: Dictionary): return _orders.right_click(point, mods)
func order_move(point: Vector2, mods: Dictionary, extra: Dictionary = {}): _orders.order_move(point, mods, extra)
func target_click(point: Vector2, mods: Dictionary): return _orders.target_click(point, mods)
func arm_target(mode: int): _orders.arm_target(mode)
func update_patrols(): _orders.update_patrols()
func wall_drag_input(event: InputEvent) -> bool: return _orders.wall_drag_input(event)
func wall_site_ok(type_id: String, cell: Vector2i) -> bool: return _orders.wall_site_ok(type_id, cell)
func finish_wall_drag(): _orders.finish_wall_drag()
func next_wall_segment(unit): _orders.next_wall_segment(unit)
func draw_wall_drag(): _orders.draw_wall_drag()
func resolve_garrison_orders(): return _orders.resolve_garrison_orders()
func unload_building(b, building_id: int = -1) -> int: return _orders.unload_building(b, building_id)
func repair_building(b) -> bool: return _orders.repair_building(b)
func assign_group(n: int): return _orders.assign_group(n)
func recall_group(n: int) -> bool: return _orders.recall_group(n)
func cycle_building(forward: bool, trains_only: bool) -> bool: return _orders.cycle_building(forward, trains_only)
func strategic_alert(cell: Vector2i, push: bool): _orders.strategic_alert(cell, push)
func push_alert(cell: Vector2i): _orders.push_alert(cell)
func alert_jump() -> bool: return _orders.alert_jump()
func select_nearest(of_type: bool, on_screen: bool) -> int: return _orders.select_nearest(of_type, on_screen)
func select_hero_key(add_it: bool) -> bool: return _orders.select_hero_key(add_it)
func centre_on_head() -> bool: return _orders.centre_on_head()

# ------------------------------------------------------------------------------------------------ view (0x4907d0)
## Height of the world view in window pixels: above the control panel in normal play (0x608476; the view's own height
## field 0x232c00 is not traced, Provisional).
func view_screen_size() -> Vector2:
	var size := get_viewport_rect().size
	if normal_play and hud != null:
		size.y -= 150.0 * float(hud.scale_factor)
		size.x -= 2.0 * float(hud.bars)          # the side bars past the battlefield width (display.gd)
	return size.max(Vector2.ONE)

## Window pixels left of the world view (the left bar).
func view_screen_left() -> float:
	return float(hud.bars) if normal_play and hud != null else 0.0

func view_world_size() -> Vector2:
	return view_screen_size() / camera.zoom

func view_top_left() -> Vector2:
	return camera.position - (get_viewport_rect().size / camera.zoom) / 2.0 + Vector2(view_screen_left(), 0) / camera.zoom

## 0x4907d0: the top-left is clamped to [0, map - view - 1] so the map always fills the view.
func set_view_top_left(top_left: Vector2):
	var view := view_world_size()
	var map_px := Vector2(collision.width * 32, collision.height * 24)
	top_left.x = clampf(top_left.x, 0.0, maxf(0.0, map_px.x - view.x - 1.0))
	top_left.y = clampf(top_left.y, 0.0, maxf(0.0, map_px.y - view.y - 1.0))
	camera.position = top_left + (get_viewport_rect().size / camera.zoom) / 2.0 - Vector2(view_screen_left(), 0) / camera.zoom

## 0x490850: the point at the centre of the world view (then clamped).
func centre_view(point: Vector2):
	set_view_top_left(point - view_world_size() / 2.0)

func view_centre() -> Vector2:
	return view_top_left() + view_world_size() / 2.0

## The view in world pixels (above the panel).
func view_rect() -> Rect2:
	return Rect2(view_top_left(), view_world_size())

# ------------------------------------------------------------------------------------------------ mouse (0x421190)
## Event modifier flags of the translator (0x45e610): 4 Ctrl, 8 Shift, 0x10 Alt.
static func mods_of(event: InputEventWithModifiers) -> Dictionary:
	return {"ctrl": event.ctrl_pressed, "shift": event.shift_pressed, "alt": event.alt_pressed}

func _input(event: InputEvent):
	if results_input(event):
		get_viewport().set_input_as_handled()
		return
	if wall_drag != null and wall_drag_input(event):
		get_viewport().set_input_as_handled()
		return
	# Releases must finish a map drag even when the pointer ends over a UI panel.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed and (drag_active or suppress_release):
		finish_selection(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_active:
		drag_end = event.position
		selection_layer.queue_redraw()

func _notification(what: int):
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		drag_active = false
		suppress_release = false
		selection_layer.queue_redraw()

func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		var world: Vector2 = get_canvas_transform().affine_inverse() * event.position
		var mods := mods_of(event)
		if event.button_index == MOUSE_BUTTON_LEFT and build_mode != "" and not rally_mode and UnitCommands.is_wall(build_mode):
			wall_drag = UnitCommands.WallDrag.new(build_mode, collision.world_cell(world))   # 0x422e49: the press cell, unsnapped
		elif event.button_index == MOUSE_BUTTON_LEFT and (build_mode != "" or rally_mode):
			map_click(world)
		elif event.button_index == MOUSE_BUTTON_RIGHT and (build_mode != "" or rally_mode):
			build_mode = ""
			rally_mode = false
			last_message = "Cancelled."
		elif target_mode != 0:
			target_click(world, mods)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			drag_start = event.position           # 0x4226dc
			drag_end = event.position
			drag_active = true
		elif not normal_play:                     # fixture harness right-click (milestone 2..12 tests)
			if mines != null and mines.mine_at(collision.world_cell(world)) >= 0:
				mine_order(mines.mine_at(collision.world_cell(world)))
			elif combat != null and enemy_at(world) != null:
				issue_attack(enemy_at(world))
			else:
				issue_move(world, event.shift_pressed, event.alt_pressed, event.ctrl_pressed)
			units_ordered.emit(selected_units().map(func(u): return u.unit_id))
		else:
			right_click(world, mods)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag_active:
		drag_end = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_HOME and not event.ctrl_pressed and not event.alt_pressed:
			# Home = internal key 0x108 (0x459c60): the view centres on the player's start (0x708fa8).
			if home_cell.x >= 0: centre_view(Vector2(home_cell) * Vector2(32, 24) + Vector2(16, 12))
			else: center_selection()
		elif not normal_play:                     # fixture-harness keys (not original)
			if event.keycode == KEY_F11 and harness_panel != null: harness_panel.visible = not harness_panel.visible
			elif event.keycode == KEY_O: collision_overlay.visible = not collision_overlay.visible
			elif event.keycode == KEY_ESCAPE: drag_active = false
			elif event.ctrl_pressed and event.keycode == KEY_A: select_all()
			elif event.ctrl_pressed and event.keycode == KEY_C: convert_selected(conversion_mode(event.shift_pressed, event.alt_pressed))
			elif event.ctrl_pressed and event.keycode == KEY_F and combat != null: toggle_attitude()
			elif event.ctrl_pressed and event.keycode == KEY_S:
				for unit in units:
					unit.selected = get_viewport_rect().has_point(get_canvas_transform() * unit.position)
					unit.queue_redraw()
	selection_layer.queue_redraw()
	refresh_status()
	queue_redraw()

## Performance (P-4): the scenario's features, sorted once per map. Most are single-frame scenery whose advance() only
## counts clock_ms: those are not stepped; their clock is the shared `still_clock_ms`, which gets the same additions from
## the same start (every placement starts at 0 together, and a loaded match restores equal values), so
## settle_object_clocks() writes them the very value their own count would have reached (before a save, or on request).
var _object_index := {}
var _objects_indexed := -1
var still_clock_ms := 0.0

func object_index() -> Dictionary:
	if _objects_indexed != map_objects.size():
		_objects_indexed = map_objects.size()
		var by_offset := {}
		for object in map_objects: by_offset[int(object.get_meta("source_offset"))] = object
		_object_index = {"by_offset": by_offset, "buildings": map_objects.filter(func(o): return o.is_building),
			"stepped": map_objects.filter(func(o): return not o.is_still()), "still": map_objects.filter(func(o): return o.is_still())}
		still_clock_ms = float(_object_index.still[0].clock_ms) if not _object_index.still.is_empty() else 0.0
	return _object_index

func settle_object_clocks():
	for object in object_index().still: object.clock_ms = still_clock_ms

## After a load: the restored clocks are the shared clock again.
func adopt_object_clocks():
	var still: Array = object_index().still
	if not still.is_empty(): still_clock_ms = float(still[0].clock_ms)

## P-4: the area units keep their sprite frame current in (unit_agent.gd step_sprite): the view at the camera's target and
## where it is drawn now (smooth camera), with a margin wider than the largest frame (708 pixels, EMDD).
func sprite_view_rect() -> Rect2:
	var size: Vector2 = get_viewport_rect().size / camera.zoom
	var rect := Rect2(camera.position - size / 2.0, size)
	if camera.is_inside_tree(): rect = rect.merge(Rect2(camera.get_screen_center_position() - size / 2.0, size))
	return rect.grow(768.0)

## Every drawn frame: units that came into view (the camera moved, the fog lifted) get their current frame.
func refresh_stale_sprites():
	var rect := sprite_view_rect()
	UnitAgent.view_rect = rect
	for unit in units:
		if unit._sprite_stale and unit.visible and rect.has_point(unit.position): unit.update_sprite()

func simulation_step(delta: float):
	var index := object_index()
	for object in index.stepped: object.advance(delta)
	still_clock_ms += delta * 1000.0
	preload("res://battle/map_object.gd").sync_states(map_objects, production, encounters, index) # ART: owner colour, rubble, Mausoleum rest
	UnitAgent.view_rect = sprite_view_rect()
	UnitAgent.cull = true
	for unit in units: unit.advance(delta)
	simulation_time += delta
	if combat != null: combat_step()
	update_race_powers()                    # B1-3: day / night ticks, brew timers, the lighting level
	if effects != null and combat != null: effects.sync(self)
	if map_effects != null: map_effects.step(game_ms())
	minimap_ping.tick(game_ms())
	if production != null:
		economy.update(game_ms())
		production.update(game_ms())
		resolve_pending_builds()
		unit_commands.update_repairs(production, game_ms())
		if not unit_commands.garrison_orders.is_empty(): resolve_garrison_orders()
		if not site_orders.is_empty(): resolve_site_orders()
		for node in building_nodes.values(): node.queue_redraw()
	if mines != null:
		resolve_mine_orders()
	if not patrols.is_empty() or not guards.is_empty(): update_patrols()
	if navigator.improved and combat != null and (not assaults.is_empty() or not attack_moves.is_empty()): update_modern_orders()
	if conversions != null: conversions.update(game_ms())
	if skirmish != null and not skirmish.over:
		skirmish.frame()
		refresh_hero_commands()
		skirmish.update(game_ms())
		update_autosave()                     # S-1 (F8, modern): every N minutes of game time in normal play

func _physics_process(delta: float):
	if skirmish != null and skirmish.over: return     # the match is decided; the results screen is up
	if time_scale > 0.0: simulation_step(delta * time_scale)
	refresh_status()
	queue_redraw()

func _process(delta: float):
	if not scroll_by_hud:
		var pan := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if pan != Vector2.ZERO: set_view_top_left(view_top_left() + pan * delta * 650 / camera.zoom.x)
	if drag_active: selection_layer.queue_redraw()
	update_cursor()
	update_ghost()
	update_order_marker()
	update_rain_fx()
	sync_treasure_sprites()
	refresh_stale_sprites()

## Parity pass 3: which unit shows the order marker (unit_agent.gd MARKER_SOURCE): the selection head when it is the local
## player's unit with a running conversion, while Shift / Alt is held or within 500 ms of the order (0x49c110 / 0x49c150).
var order_marker_until_ms := 0
var _marker_step_ms := 0
var order_layer: Node2D = null              # P-2: order_markers.gd

## P-2: 0x49c150 after a ground move or a rally order (the 500 ms show).
func arm_order_marker():
	order_marker_until_ms = Time.get_ticks_msec() + 500
	if order_layer != null: order_layer.arm(Time.get_ticks_msec())

func update_order_marker():
	var UnitAgent = preload("res://battle/unit_agent.gd")
	var now := Time.get_ticks_msec()
	if now >= _marker_step_ms:
		_marker_step_ms = now + 100
		UnitAgent.marker_phase = (UnitAgent.marker_phase + 1) & 15
	var shown := -1
	var units := selected_units()
	if not units.is_empty() and conversions != null:
		var head = units[0]
		var held := Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_ALT)
		if head.owner_id == local_player and not head.dying and conversions.converting(head.unit_id) and (held or now < order_marker_until_ms):
			shown = head.unit_id
	if shown != UnitAgent.marker_unit:
		var previous = unit_by_id(UnitAgent.marker_unit) if UnitAgent.marker_unit >= 0 else null
		if previous != null: previous.queue_redraw()
	UnitAgent.marker_unit = shown
	UnitAgent.marker_type = 7
	if shown >= 0: unit_by_id(shown).queue_redraw()
	# P-2: the move markers and lines of 0x49c240 (order_markers.gd).
	if order_layer == null:
		order_layer = preload("res://hud/order_markers.gd").new()
		order_layer.main = self
		add_child(order_layer)
	order_layer.refresh(now, normal_play and (Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_ALT)))
	# The conversion pose (unit_agent.gd convert_ms) follows order 7 for every unit, selected or not (self.units: the
	# local `units` above is the selection). Each 'c' cycle 0x536cc0 builds also starts EZ56 at the unit.
	if conversions != null:
		for unit in self.units:
			if unit == null or unit.removed: continue
			var on: bool = not unit.dying and conversions.converting(unit.unit_id)
			if on and unit.convert_ms < 0.0:
				unit.convert_ms = 0.0
				unit.convert_cycle = -1
			elif not on and unit.convert_ms >= 0.0: unit.convert_ms = -1.0
			if on and unit.convert_cycle != unit.convert_cycle_index():
				unit.convert_cycle = unit.convert_cycle_index()
				if effects != null and unit.visible:
					effects.spawn_effect("EZ56", Vector2i(int(unit.position.x), int(unit.position.y)), int(unit.cell.y), true)
	# Parity pass 4 (0x538660, Read): the selected unit's ring takes rank 8 (the yellow ring) for a hero, and an own unit
	# shows the first control group 0..9 that holds it (0x425470).
	var first_group := {}
	for g in range(9, -1, -1):
		if control_groups.has(g):
			for id in control_groups[g].units: first_group[int(id)] = g
	for unit in self.units:
		if unit == null or not unit.selected: continue
		var fm = combat.fighters.get(unit.unit_id) if combat != null else null
		unit.ring_rank = 8 if is_hero_unit(unit) else (mini(int(fm.get("rank", 0)), 8) if fm != null else 0)   # 0x53883d: min(+0x3c, 8)
		unit.mana_level = preload("res://battle/unit_agent.gd").mana_level_of(int(fm.get("mana", 0)), int(fm.get("max_mana", 0))) if fm != null else -1
		unit.group_digit = int(first_group.get(unit.unit_id, -1)) if unit.owner_id == local_player else -1
	# Buildings (0x53b014): the selected one, and the local player's conversion targets (+0x14a), get the ring.
	var marks: Dictionary = conversions.marked_buildings(local_player) if conversions != null else {}
	if conversions != null and preload("res://core/display.gd").setting_visuals_enhanced():
		marks.merge(conversions.keep_marked_buildings(local_player))     # modern: the Keep's targets too (match_conversion.gd)
	for id in building_nodes: building_nodes[id].set_marker(id == selected_building_id, marks.has(id))
	# Mines are their own entities (simulation/mines.gd), matched to their placement by the scenario record's offset.
	var mine_at := {}
	if mines != null:
		for id in mines.mines: mine_at[int(mines.mines[id].source_offset)] = id
	for object in object_index().buildings:
		var mine_id: int = int(mine_at.get(int(object.get_meta("source_offset")), -1))
		if mine_id >= 0: object.set_marker(mine_id == selected_mine_id, marks.has(mine_id), mines.mines[mine_id].entity)
		else: object.set_marker(object.link_id >= 0 and object.link_id == selected_building_id, object.link_id >= 0 and marks.has(object.link_id))

var race_controls: HBoxContainer
var _race_controls_key := ""

func refresh_race_controls():
	if race_controls == null or production == null: return
	var b = selected_building()
	var builder = selected_builder()
	var items: Array = []
	var mode := ""
	if b != null and int(b.owner) == local_player and not b.constructing:
		mode = "produce"
		items = production.menu_for(b).map(func(m): return String(m.id))
	elif builder != null and builder.owner_id == local_player:
		mode = "build"
		items = production.construction_menu(local_player)
	var key := "%s|%s|%s|%d" % [mode, ",".join(items), b.original_type_id if b != null else "", production.race_of(local_player)]
	if key == _race_controls_key: return
	_race_controls_key = key
	for child in race_controls.get_children(): child.queue_free()
	if mode == "": return
	var label := Label.new()
	label.text = ("%s builds:" % builder.type_id) if mode == "build" else ("%s:" % production.rules.definition(b.original_type_id).get("display_name", b.original_type_id))
	race_controls.add_child(label)
	for id in items:
		var price: Array = production.price_of(local_player, id)
		var name: String = String(production.rules.definition(id).get("display_name", id)) if not production.rules.definition(id).is_empty() else id
		var text := "%s %s" % [name, price_text(price)]
		if mode == "build": button(race_controls, text, func(): arm_build(id))
		else: button(race_controls, text, func(): queue_item(id))

static func price_text(price: Array) -> String:
	var parts: Array = []
	for lane in 4:
		if int(price[lane]) > 0: parts.append("%d%s" % [int(price[lane]), ["g", "m", "c", "s"][lane]])
	return "(" + " ".join(parts) + ")" if not parts.is_empty() else ""

func refresh_status():
	# P-4: the texts of the fixture harness panel, which normal play hides (enable_normal_play); nothing else reads them.
	if normal_play and harness_panel != null and not harness_panel.visible: return
	refresh_race_controls()
	var queued := 0
	for unit in units: queued += unit.orders.size()
	status.text = "%d selected · %d move orders · sim %.2fs · %s" % [selected_units().size(), queued, simulation_time, last_message]
	if production != null: production_status.text = production_text()
	if combat != null: combat_status.text = combat_text()
	match_status.text = match_text()

func _draw():
	if map.is_empty(): return
	draw_build_ghost()
	if wall_drag != null: draw_wall_drag()
	draw_rally_line()
	# Fixture-harness drawing only (parity pass 1): the move cross, routes and queued order numbers are debug look; the
	# original's order marker (0x49c240, the SelectionRings icons) is not shown on a plain move (Open: its trigger).
	if normal_play or harness_panel == null or not harness_panel.visible: return
	if last_requested.x >= 0:
		draw_line(last_requested-Vector2(8,0),last_requested+Vector2(8,0),Color("f5c76b"),2)
		draw_line(last_requested-Vector2(0,8),last_requested+Vector2(0,8),Color("f5c76b"),2)
	if not show_paths: return
	for unit in selected_units():
		var previous: Vector2 = unit.position
		for i in range(unit.waypoint + 1, unit.path.size()):
			var point: Vector2 = unit.path[i]
			draw_line(previous, point, Color(0.45,0.95,0.7,0.65), 1.5)
			previous = point
		for i in range(unit.orders.size()):
			var point: Vector2 = unit.orders[i].target
			draw_circle(point, 9, Color("86dfab"), false, 1.5)
			draw_string(ThemeDB.fallback_font, point+Vector2(10,5), str(i+1), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

## Playtest 2026-11-11: the rally point in normal play. 0x49d3b0 (Read): while the selection head is an own building
## with a rally point (0x52e6d0), the view keeps a line record of kind 4 from the building's point (0x52e060) to the rally
## cell; the drawer (0x49cd.., default case) colours it (8k, 8k, 0xbf + 8k) with the pulse k = 0..8..0 and puts a square
## of 2..10 pixels, growing with k, on the rally point. Provisional: the dash pattern (an 8-step cycle, here 6 on / 2 off)
## and the pulse speed (one step per 60 ms); the line starts at the footprint's centre.
func draw_rally_line():
	if not normal_play or production == null: return
	var b = selected_building()
	if b == null or int(b.owner) != local_player or b.rally.x < 0 or not selected_units().is_empty(): return
	var phase := int(Time.get_ticks_msec() / 60) % 16
	var k := phase if phase <= 8 else 16 - phase
	var colour := Color8(k * 8, k * 8, 0xbf + k * 8)
	var from := Vector2(b.cell_rect().get_center()) * Vector2(32, 24)
	var to: Vector2 = navigator.center(b.rally)
	var length := from.distance_to(to)
	var direction := (to - from) / maxf(1.0, length)
	var t := 0.0
	while t < length:
		draw_line(from + direction * t, from + direction * minf(t + 6.0, length), colour, 1.0)
		t += 8.0
	var half := float(1 + mini(k, 8) / 2)                 # sizes 2, 4, 6, 8, 10
	draw_rect(Rect2(to - Vector2(half, half), Vector2(half, half) * 2.0), colour, true)

# Fixture captures and the benchmark report (R-1: the functions are in main_captures.gd; these forward the ones called by name)
func write_benchmark(): _captures.write_benchmark()
func capture_preview(): await _captures.capture_preview()
func capture_objects(): await _captures.capture_objects()
func capture_production(): return await _captures.capture_production()
func capture_combat(): return await _captures.capture_combat()
func capture_encounters(): await _captures.capture_encounters()
func capture_skirmish(): return await _captures.capture_skirmish()

# Construction and production (R-1: the functions are in main_build.gd; these forward the ones called by name)
func reset_production(): _build.reset_production()
func make_production(): return _build.make_production()
func _register_player_tower(id: int): _build._register_player_tower(id)
func spawn_production_fixture(): _build.spawn_production_fixture()
func find_site(type_id: String, wanted: Vector2i) -> Vector2i: return _build.find_site(type_id, wanted)
func add_unit(type_id: String, cell: Vector2i, owner: int = 0): return _build.add_unit(type_id, cell, owner)
func add_marker(state: RefCounted): _build.add_marker(state)
func selected_building(): return _build.selected_building()
func select_building_at(point: Vector2): _build.select_building_at(point)
func arm_build(type_id: String): _build.arm_build(type_id)
func selected_builder(): return _build.selected_builder()
func is_builder(unit) -> bool: return _build.is_builder(unit)
func is_hero_unit(unit) -> bool: return _build.is_hero_unit(unit)
func map_click(point: Vector2): _build.map_click(point)
func start_build_walk(builder, type_id: String, cell: Vector2i) -> bool: return _build.start_build_walk(builder, type_id, cell)
func resolve_pending_builds(): _build.resolve_pending_builds()
func _on_builder_hidden(id: int): _build._on_builder_hidden(id)
func _on_builder_released(id: int, cell: Vector2i): _build._on_builder_released(id, cell)
func _on_building_placed(id: int): _build._on_building_placed(id)
func _on_building_destroyed(id: int): _build._on_building_destroyed(id)
func _on_unit_ready(info: Dictionary): _build._on_unit_ready(info)
func queue_item(item: String): _build.queue_item(item)
func cancel_job(): _build.cancel_job()
func cancel_all_jobs(): _build.cancel_all_jobs()
func release_builder(): _build.release_builder()
func toggle_repeat(): _build.toggle_repeat()
func production_text() -> String: return _build.production_text()
func update_ghost(): _build.update_ghost()
func draw_build_ghost(): _build.draw_build_ghost()

func game_ms() -> int:
	return int(round(simulation_time * 1000.0))

var selected_mine_id := -1                  # the selected mine (mines.gd id), -1 none

# Scripted walk-through of the production controls (same handlers as the buttons); writes numbered
# screenshots and a state log to .local/production_capture_*.png / .txt. Not part of the checks.
func advance_seconds(seconds: float):
	for i in range(roundi(seconds * 60.0)): simulation_step(1.0 / 60.0)

# Combat, visibility and the modern battle rules (R-1: the functions are in main_combat.gd; these forward the ones called by name)
func setup_combat(): return _combat.setup_combat()
func unit_combat_stats(type_id: String) -> Dictionary: return _combat.unit_combat_stats(type_id)
func unit_definition(type_id: String) -> Dictionary: return _combat.unit_definition(type_id)
func register_combatant(unit): _combat.register_combatant(unit)
func _on_research_completed(owner: int, item: String): _combat._on_research_completed(owner, item)
func status_flags(type_id: String) -> int: return _combat.status_flags(type_id)
func clear_units(): _combat.clear_units()
func spawn_combat_fixture(): _combat.spawn_combat_fixture()
func find_open_area(wanted: Vector2i, width: int, height: int) -> Vector2i: return _combat.find_open_area(wanted, width, height)
func attack_nearest_selected(): _combat.attack_nearest_selected()
func enemy_at(point: Vector2): return _combat.enemy_at(point)
func remove_last_orders() -> bool: return _combat.remove_last_orders()
func issue_attack(target: Dictionary, append: bool = false, prepend: bool = false) -> int: return _combat.issue_attack(target, append, prepend)
func apply_modern_rules(): _combat.apply_modern_rules()
func stage_cell(from: Vector2i, there: Vector2i, distance: int, degrees: float) -> Vector2i: return _combat.stage_cell(from, there, distance, degrees)
func march_units(group: Array, cell: Vector2i, extra: Dictionary = {}): _combat.march_units(group, cell, extra)
func issue_attack_move(point: Vector2, mods: Dictionary): _combat.issue_attack_move(point, mods)
func forget_modern_orders(ids: Array): return _combat.forget_modern_orders(ids)
func update_modern_orders(): return _combat.update_modern_orders()
func toggle_fog(which: String): _combat.toggle_fog(which)
func toggle_attitude(): _combat.toggle_attitude()
func clear_enemies_test(): _combat.clear_enemies_test()
func sight_sources(viewers = null) -> Array: return _combat.sight_sources(viewers)
func fog_players() -> Array: return _combat.fog_players()
func sharing_players(owner: int, viewers = null) -> Array: return _combat.sharing_players(owner, viewers)
func visibility_update(): _combat.visibility_update()
func visibility_force_sweep(): _combat.visibility_force_sweep()
func combat_step(): _combat.combat_step()
func apply_fog_to_nodes(): _combat.apply_fog_to_nodes()
func refresh_fog_overlay(): _combat.refresh_fog_overlay()
func _on_damaged(kind: String, id: int, amount: int, attacker: int): _combat._on_damaged(kind, id, amount, attacker)
func _on_died(kind: String, id: int, killer_owner: int): return _combat._on_died(kind, id, killer_owner)
func combat_text() -> String: return _combat.combat_text()

# ------------------------------------------------------------------------------------------------ modern battle rules
# DELIBERATE MODERN CHANGES (simulation/modern_rules.gd, COMPLAINTS_AND_FIXES.md). Each is skipped in the original mode.
var assaults: Array = []        # F3: {"ids", "target", "march", "issued_ms"}: a group marching to its staging cell
var attack_moves: Dictionary = {} # F3: unit id -> requested point of an attack-move (resumed after each fight)
var improved_armies := false    # F6: ai_player.gd gathers, stages, flanks and falls back
var improved_research := false  # F10: ai_player.gd's research node gives way after a minute and gains a waiting bonus
const STAGE_DISTANCE := 6       # staging cell: this many cells short of the target, on the side the group comes from
const STAGE_MIN_DISTANCE := 12  # closer groups attack at once
const STAGE_TIMEOUT_MS := 25000
const ATTACK_MOVE_SIGHT := 6

var _last_alert_ms := -100000               # kept for old saves (SAVED_FIELDS); no longer used

# Encounters, quests, the hero's items and site visits (R-1: the functions are in main_hero.gd; these forward the ones called by name)
func spawn_encounters_fixture(): _hero.spawn_encounters_fixture()
func hero_near_mausoleum() -> bool: return _hero.hero_near_mausoleum()
func quest_visit() -> Dictionary: return _hero.quest_visit()
func quest_accept(): _hero.quest_accept()
func quest_complete(): _hero.quest_complete()
func lair_wave_test(): _hero.lair_wave_test()
func destroy_lair_test(): _hero.destroy_lair_test()
func encounter_text() -> String: return _hero.encounter_text()
func toggle_hero_items(): _hero.toggle_hero_items()
func open_inventory(pile_id: int) -> bool: return _hero.open_inventory(pile_id)
func close_inventory(): _hero.close_inventory()
func inventory_slot(k: int) -> Dictionary: return _hero.inventory_slot(k)
func inventory_release(k: int) -> String: return _hero.inventory_release(k)
func inventory_tick(): return _hero.inventory_tick()
func sync_treasure_sprites(): _hero.sync_treasure_sprites()
func hero_item_move(from: int, to: int) -> bool: return _hero.hero_item_move(from, to)
func hero_item_drop(slot: int) -> bool: return _hero.hero_item_drop(slot)
func hero_item_take(pile_id: int, index: int) -> bool: return _hero.hero_item_take(pile_id, index)
func refresh_hero_unit(bound): _hero.refresh_hero_unit(bound)
func site_kind(hovered: Dictionary) -> String: return _hero.site_kind(hovered)
func order_site_visit(head, hovered: Dictionary, point: Vector2, mods: Dictionary) -> bool: return _hero.order_site_visit(head, hovered, point, mods)
func resolve_site_orders(): return _hero.resolve_site_orders()
func quest_site_accept(building_id: int) -> Dictionary: return _hero.quest_site_accept(building_id)
func shop_goods(building_id: int) -> Array: return _hero.shop_goods(building_id)
func shop_buy(building_id: int, place: int) -> bool: return _hero.shop_buy(building_id, place)

# Match start, end and results (R-1: the functions are in main_match.gd; these forward the ones called by name)
func start_skirmish(setup: Dictionary, hero_id: String, store = null, id: String = "") -> bool: return _match.start_skirmish(setup, hero_id, store, id)
func end_skirmish(): _match.end_skirmish()
func refresh_hero_commands(): _match.refresh_hero_commands()
func quit_match(): _match.quit_match()
func match_text() -> String: return _match.match_text()
func _on_match_ended(outcome: Dictionary): _match._on_match_ended(outcome)
func end_box_rect() -> Rect2: return _match.end_box_rect()
func results_data() -> Dictionary: return _match.results_data()
func _on_results_resources(owner: int, before: Array, after: Array): _match._on_results_resources(owner, before, after)
func _on_results_died(kind: String, id: int, killer_owner: int): _match._on_results_died(kind, id, killer_owner)
func run_retinue_scan(): return _match.run_retinue_scan()
func accept_results() -> bool: return _match.accept_results()
func results_input(event: InputEvent) -> bool: return _match.results_input(event)

class EndBox extends Node2D:
	## 0x574c90: the sheet, then Game.txt [0728] Victory (font 0x15) at +(0xa8, 0x15f) and [0730] / [0731] (font 2) at
	## +(0xa8, 400) / +(0xa8, 0x1a0); a defeat: [0729] at +(0xa8, 0x106), [0730] +0x137, [0731] +0x147. 0x46e3b0 draws
	## centred on x (as the main-menu floats, which pass the button centre).
	var main
	func _draw():
		if main == null: return
		var rect: Rect2 = main.end_box_rect()
		var canvas = main.results_screen.canvas
		var key := "X:EZDV" if main.end_won else "X:EZDD"
		var tex: Texture2D = canvas.texture(key)
		if tex != null: draw_texture_rect(tex, rect, false)
		var scale: float = rect.size.x / 360.0
		var lines: Array = [[728, 0x15, 0x15f], [730, 2, 400], [731, 2, 0x1a0]] if main.end_won else [[729, 0x15, 0x106], [730, 2, 0x137], [731, 2, 0x147]]
		for line in lines:
			var info: Dictionary = canvas.font(int(line[1]))
			if info.is_empty() or info.font == null: continue
			var text: String = String(canvas.layout.get("game_text", {}).get(str(line[0]), ""))
			var size := int(round(int(info.size) * scale))
			var width: float = info.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
			var at := rect.position + Vector2(0xa8 * scale - width / 2.0, (int(line[2]) + int(info.baseline)) * scale)
			if info.shadow: draw_string(info.font, at + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.BLACK)
			draw_string(info.font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, info.colour)

# ------------------------------------------------------------------ milestone 11: the hero's items in a match
# The inventory dialog 0x55e0e0 (vtable 0x5ea954; playtest 2026-11-11 replaced the temporary list). Read from the
# disassembly (the handlers are not in the decompile):
# * 17 slots (0x55eb50, table 0x6150f0): 0..6 the equipment, 7..10 the backpack (a working copy of the hero's eleven
#   slots 0x709250, copied back after every change: 0x55f1e5), 11..14 the ground (the pile the dialog was opened with,
#   record +0x3c, or none), 15 / 16 the healing / mana potion.
# * Release on a slot (0x55ecc0): 15 drinks a healing potion (0x561d80), 16 a mana potion (0x561c30); a drink closes the
#   dialog. A second release on the selected slot within 20 ticks of the first (0xbbf2c8 < 0x14) moves its item to the
#   first of slots 0..10 that is empty and takes it (0x55ec20). A release on another slot while one is selected swaps the
#   two when each item fits the other's slot. Otherwise a release on an item selects it.
# * Closing (0x55e710 -> 0x560a00): the ground row is compacted in order and becomes the pile's items; without a pile,
#   the items are put down at the hero (here with the 0x580d00 rule, Provisional); then the hero block is rebuilt
#   (0x4af820; 0x54fd50 keeps the damage taken).
# * 0x50d480 -> 0x53a1a0 (decompile): the local player's living hero next to a pile (cells x-1..x+1, y-1..y+1, row by
#   row) opens the dialog with that pile, unless another dialog is open (an open inventory is reopened with it) or the
#   last inventory click was less than 200 updates ago (0xb90fa0 +0x200). Provisional: the check runs when the hero
#   enters a cell (0x50d480's caller is a virtual not traced).
const SLOT_NAMES := ["Head", "Body", "Weapon", "Off hand", "Accessory", "Accessory", "Feet", "Backpack 1", "Backpack 2", "Backpack 3", "Backpack 4"]
const INVENTORY_DOUBLE_TICKS := 20               # 0xbbf2c8 < 0x14
const INVENTORY_REOPEN_TICKS := 200              # 0x53a1a0: 0xb90fa0 +0x200 > 200
var ui_layer: CanvasLayer
var inventory := {}                              # open dialog: {"pile", "ground": [4 dicts], "selected", "previous", "tick"}
var inventory_quiet_tick := INVENTORY_REOPEN_TICKS
var inventory_hero_cell := Vector2i(-1, -1)

## Playtest 2026-11-11: the piles on the map. 0x4a7870 (Read) gives each pile an 'IMAP' sprite (0x58bd20('IMAP', 0, 4, 1):
## Effects1.xcr IMAP, column 0 of row 4, the closed chest) placed on its cell (0x5350a0). Provisional: the sprite stands
## at the cell centre with the ANI pivot, depth by its row like a unit; the fog overlay hides it like any map object.
var treasure_sprites := {}                  # pile id -> Sprite2D

# Mines, conversion and the computer player's bridge (R-1: the functions are in main_ai.gd; these forward the ones called by name)
func mine_order(mine_id: int): _ai.mine_order(mine_id)
func order_enter_mine(unit, mine_id: int) -> bool: return _ai.order_enter_mine(unit, mine_id)
func order_convert(unit, kind: String, id: int) -> bool: return _ai.order_convert(unit, kind, id)
func setup_conversions(): return _ai.setup_conversions()
func _on_conversion_finished(actor_id: int, owner: int, converted: Array): _ai._on_conversion_finished(actor_id, owner, converted)
func _on_keep_conversion_finished(_building_id: int, owner: int, converted: Array): _ai._on_keep_conversion_finished(_building_id, owner, converted)
func _on_converted(id: int, previous: int, owner: int): _ai._on_converted(id, previous, owner)
func conversion_terms(unit) -> Dictionary: return _ai.conversion_terms(unit)
func can_convert(unit) -> bool: return _ai.can_convert(unit)
func convert_selected(mode: int = 0) -> bool: return _ai.convert_selected(mode)
func player_message(text: String): _ai.player_message(text)
func game_string(id: int, fallback: String) -> String: return _ai.game_string(id, fallback)
func order_convert_here(unit, mode: int = 0) -> bool: return _ai.order_convert_here(unit, mode)
func cancel_conversion(unit): _ai.cancel_conversion(unit)
func keep_convert(b = null) -> bool: return _ai.keep_convert(b)
func resolve_mine_orders(): _ai.resolve_mine_orders()
func _ai_building_damaged(b, amount: int, attacker_kind: String, attacker_id: int): _ai._ai_building_damaged(b, amount, attacker_kind, attacker_id)
func ai_units(owner: int) -> Array: return _ai.ai_units(owner)
func unit_by_id(id: int): return _ai.unit_by_id(id)
func unit_busy(unit) -> bool: return _ai.unit_busy(unit)
func build_state(unit) -> String: return _ai.build_state(unit)
func in_mine(unit) -> bool: return _ai.in_mine(unit)
func mine_order_failed(unit) -> bool: return _ai.mine_order_failed(unit)
func owns_objects(player: int) -> bool: return _ai.owns_objects(player)
func ai_move(unit, cell: Vector2i, speed: int = -1): _ai.ai_move(unit, cell, speed)
func ai_build(unit, type_id: String, cell: Vector2i) -> bool: return _ai.ai_build(unit, type_id, cell)
func ai_enter_mine(unit, mine_id: int) -> bool: return _ai.ai_enter_mine(unit, mine_id)
func ai_convert(unit, kind: String, id: int) -> bool: return _ai.ai_convert(unit, kind, id)
func ai_site(owner: int, type_id: String, home: Vector2i, builder) -> Vector2i: return _ai.ai_site(owner, type_id, home, builder)
func _clear_margin(definition: Dictionary, cell: Vector2i) -> bool: return _ai._clear_margin(definition, cell)
func ai_targets(player: int) -> Array: return _ai.ai_targets(player)
func ai_mine_targets(owner: int) -> Array: return _ai.ai_mine_targets(owner)
func converting(unit) -> bool: return _ai.converting(unit)
func ai_keep_has_mines(b, owner: int) -> bool: return _ai.ai_keep_has_mines(b, owner)
func unit_arm_0x1c(type_id: String) -> int: return _ai.unit_arm_0x1c(type_id)
func ai_summaries() -> Array: return _ai.ai_summaries()
func _on_side_cleanup(player: int): _ai._on_side_cleanup(player)
func _ai_pre_update(now_ms: int): _ai._ai_pre_update(now_ms)

var generals: Dictionary = {}            # Army.cfg general flag (+0x51; taken as the unit's +0x1cc, Provisional)

## 0x4ce590 reads Alt (mode 2) and Shift (mode 1) with GetKeyState; Shift is tested last and wins.
static func conversion_mode(shift: bool, alt: bool) -> int:
	if shift: return 1
	return 2 if alt else 0

var in_mine_units: Dictionary = {}       # unit id -> mine id
var failed_mine_orders: Dictionary = {}

# Pixel hits and the race powers (B1-3 .. B4-1) (R-1: the functions are in main_powers.gd; these forward the ones called by name)
func sprite_rect_for(kind: String, id: int): return _powers.sprite_rect_for(kind, id)
func building_pixel_hit(id, x: int, y: int) -> bool: return _powers.building_pixel_hit(id, x, y)
func setup_day_night(): _powers.setup_day_night()
func update_race_powers(): _powers.update_race_powers()
func update_rain_fx(): _powers.update_rain_fx()
func update_night_light(): _powers.update_night_light()
func play_at(sound: String, cell: Vector2i): _powers.play_at(sound, cell)
func advancement_buttons(selection: Array) -> Array: return _powers.advancement_buttons(selection)
func advance_selected(target: String) -> int: return _powers.advance_selected(target)
func morph_unit(unit, target: String, with_sound: bool = true): return _powers.morph_unit(unit, target, with_sound)
func remove_unit_quietly(unit): _powers.remove_unit_quietly(unit)
func command_free(owner: int) -> bool: return _powers.command_free(owner)
func raise_gravestone(b) -> int: return _powers.raise_gravestone(b)
func slavehorde(b) -> int: return _powers.slavehorde(b)
func weather_power(b, night: bool) -> bool: return _powers.weather_power(b, night)
func drinker(u) -> bool: return _powers.drinker(u)
func brew_selected() -> int: return _powers.brew_selected()
func drink(u) -> bool: return _powers.drink(u)
func scavenge(u, throttle: bool = true) -> Dictionary: return _powers.scavenge(u, throttle)
func _on_rank_gained(id: int, rank: int): _powers._on_rank_gained(id, rank)
func in_berserk_state(u) -> bool: return _powers.in_berserk_state(u)
func berserk_selected() -> int: return _powers.berserk_selected()
func _on_berserk_changed(id: int, level: int, first: bool): _powers._on_berserk_changed(id, level, first)
func _on_eaten(_killer_id: int, cell: Vector2i): _powers._on_eaten(_killer_id, cell)
func _on_mercenary_completed(building_id: int, item: String) -> int: return _powers._on_mercenary_completed(building_id, item)
func farseeing(): _powers.farseeing()
func brood(b) -> int: return _powers.brood(b)
func ancestral_spirit(b, tier: int) -> int: return _powers.ancestral_spirit(b, tier)
func stormcall(b) -> bool: return _powers.stormcall(b)
func _on_race_event(kind: String, info: Dictionary): _powers._on_race_event(kind, info)
func other_income(player: int) -> Dictionary: return _powers.other_income(player)
func merge_shown(selection: Array) -> bool: return _powers.merge_shown(selection)
func merge_enabled(owner: int) -> bool: return _powers.merge_enabled(owner)
func merge_selected() -> int: return _powers.merge_selected()
func merge_group(owner: int, ids: Array) -> int: return _powers.merge_group(owner, ids)
func sacrifice_shown(selection: Array) -> bool: return _powers.sacrifice_shown(selection)
func sacrifice_enabled(selection: Array) -> bool: return _powers.sacrifice_enabled(selection)
func sacrifice_selected() -> Dictionary: return _powers.sacrifice_selected()

# ------------------------------------------------------------------------------------------------ B1-3: race powers
## B1-3 (B1_3_RESEARCH.md): Undead advancement (simulation/advancement.gd), the batch-1 building and unit powers
## (simulation/race_powers.gd) and day / night (simulation/day_night.gd) applied to the match world.
const Advancement = preload("res://simulation/advancement.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const DayNight = preload("res://simulation/day_night.gd")
var day_night                             # DayNight (the weather object's clock); made with the combat world
var night_layer: CanvasLayer              # the palette lighting level over the world view (night_light.gdshader)
var night_rect: ColorRect
var slavehorde_ms := -100000              # 0xa4785c (timeGetTime of the last Slavehorde; game clock here, Provisional)
var scavenge_ms := -100000                # 0xa47850
var brew_sound_ms := -100000              # 0xa4784c
var scavenge_records: Array = []          # 0x578e10 records waiting for B1-4's kind-0x1c applier (Open)

## P-2: the original's rain and storm flashes for the simulated rain (rain_fx.gd), every frame.
var rain_layer: Node2D = null

## R-1: 0x527100's feedback for a promotion: EZ12 and EZ57 on the local player's units, GainedLevel.wav at most every 500 ms
## (both only in view in the original), and its text "Gained Level %d" (Game.txt [1109], the unit's rank + 1). The original
## floats the text over the sprite (0x53a010, P-1: effects_layer.gd); the message line keeps it too.
var rank_sound_ms := -100000

# ------------------------------------------------------------------------------------------------ B2-1: race batch 2
## BATCH2_RESEARCH.md section 2: the rules are simulation/race_powers.gd's; the berserk state is spells.gd's.
var berserk_art: Dictionary = {}          # unit id -> the looping effect EF04 of the state (+0x1e0, presentation only)

# ------------------------------------------------------------------------------------------------ B3-1: race batch 3
## BATCH3_RESEARCH.md section 2: the rules are simulation/race_powers.gd's; souls, the blast, stored animals, the Goblin and
## Petrify are combat.gd's; rain is day_night.gd's.
var brood_ms := -100000                   # 0xa47860 (game clock here, Provisional as Slavehorde's)
var spirit_i_ms := -100000                # 0xa47868 (Ancestral Spirit I)
var spirit_ii_ms := -100000               # 0xa47864 (Ancestral Spirit II)
var store_sound_ms := -100000             # the stored-animal sound, at most once a second

# ------------------------------------------------------------------------------------------------ B4-1: race batch 4
## BATCH4_RESEARCH.md section 2: the rules are simulation/race_powers.gd's; Holy Word, Elcor's Balm, the keys and the class-5 poison
## are spells.gd's; the death spawns and eggs combat.gd's; the income economy.gd's (other_income below).
var sacrifice_ms := -100000               # 0xa47848: the Sacrifice button's stamp (game clock, as Slavehorde's)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## In-match Save / Load of a skirmish (SAVE_LOAD.md; PARITY_BACKLOG.md #20, COMPLAINTS_AND_FIXES.md F8 / S1).
## The original (Read): one save per hero, "<save folder>\<hero name>.WB3" (0x40d950 tests it, 0x445c20 writes it,
## 0x446150 loads it); the game menu's Save (row 1) and Alt+S save at once with the message [0304] "game saved" or
## [0753] when a save was replaced ([0305] on failure); Load (row 0, only while a save exists) and Alt+L open the load
## sheet EMDL (0x564c20) with the save's picture and two lines, whose Load Game button loads it. The rebuild's format is
## its own (simulation/save_game.gd), one file per hero in user://saves, plus an autosave file (DELIBERATE MODERN
## CHANGE, F8). A load starts the same setup on a fresh scene (start_skirmish, so every signal and callback is wired as
## at a match start) and then replaces every module's state with the saved one.
const SaveGame = preload("res://simulation/save_game.gd")
const SkirmishVictory = preload("res://simulation/skirmish_victory.gd")
const SkirmishShops = preload("res://simulation/skirmish_shops.gd")
const RandomMapMatch = preload("res://simulation/random_map_match.gd")
const RANDOM_MAP_NAME := "Random Map"     # [0287]: the save header's map name for a random map (0x4482f0)
## main.gd's own match fields (the rest of its fields are nodes and presentation).
const SAVED_FIELDS := ["site_orders", "simulation_time", "command_number", "combat_seed", "hero_unit_id", "local_player", "attitude_index",
	"treasure_units", "mausoleum_id", "lair_id", "pending_builds", "selected_building_id", "results_tracking", "mine_orders",
	"build_results", "in_mine_units", "failed_mine_orders", "control_groups", "alerts", "alert_index", "alert_ms",
	"_last_alert_ms", "patrols", "guards", "home_cell", "assaults", "attack_moves", "improved_armies", "improved_research",
	"generals", "scavenge_records", "fog_next_ms", "slavehorde_ms", "brood_ms", "spirit_i_ms", "spirit_ii_ms", "sacrifice_ms", "scavenge_ms", "brew_sound_ms", "time_scale", "end_won",
	"order_marker_until_ms", "_marker_step_ms", "autosave_next_ms"]
## The order modules are saved and loaded in (units before navigation's occupants, economy before production's
## buildings, both before combat's heroes).
const SAVE_MODULES := ["main", "units", "navigation", "economy", "production", "combat", "visibility", "encounters", "treasures",
	"mines", "conversions", "ai", "skirmish", "day_night", "unit_commands", "map_objects"]
static var pending_load: Dictionary = {}  # {"document", "store_dir", "save_dir"}: loaded by the next main.tscn (_ready)
var match_setup: Dictionary = {}          # the setup this match was started with (a load starts it again)
var match_hero_id := ""
var restoring := false                    # start_skirmish for a load: the hero's start write is already done
var restore_profile = null                # the saved in-match hero copy, if the hero book no longer has the hero
var save_directory := SaveGame.default_directory()
var autosave_next_ms := -1                # game time of the next autosave (-1: from the setting at the next step)
var load_error := ""

# S-1 save / load (R-1: the functions are in main_save.gd; these forward the ones called by name)
func can_save() -> bool: return _save.can_save()
func save_document(thumbnail: PackedByteArray = PackedByteArray()) -> Dictionary: return _save.save_document(thumbnail)
func save_match(path: String, thumbnail: PackedByteArray = PackedByteArray()) -> String: return _save.save_match(path, thumbnail)
func load_match(document: Dictionary, store = null) -> String: return _save.load_match(document, store)
func restore_unit(state: Dictionary): return _save.restore_unit(state)
func quick_save(thumbnail: PackedByteArray = PackedByteArray()) -> Dictionary: return _save.quick_save(thumbnail)
func open_saved_game(path: String) -> String: return _save.open_saved_game(path)
func load_pending(): _save.load_pending()
func update_autosave(): _save.update_autosave()
func autosave(at_end: bool = false) -> String: return _save.autosave(at_end)

## The hero's save file (the original keeps one per hero) and the autosave beside it.
func save_path(autosave: bool = false) -> String:
	var hero := match_hero_id if match_hero_id != "" else "spectator"
	return SaveGame.path_for(hero + ("-" + SaveGame.AUTOSAVE_NAME if autosave else ""), save_directory)

func save_exists(autosave: bool = false) -> bool:
	return FileAccess.file_exists(save_path(autosave))

## S-2: the part the hero book shares (0x5536e0 Load Game, front_end.gd): the document is read and handed to the next main.tscn.
static func prepare_saved_game(path: String, store_dir: String, save_dir: String) -> String:
	var r := SaveGame.read(path)
	if not r.ok: return r.error
	var states: Dictionary = SaveGame.modules_of(r.document)
	if not states.get("main") is Dictionary or not states.get("refs") is Array: return "The save is damaged (no match data)."
	if MapData.is_generated(String(r.document.map)):        # RM-7: the map again from its generation inputs (SAVE_LOAD.md)
		var again: Dictionary = RandomMapMatch.restore(r.document.get("random_map", {}))
		if not bool(again.ok): return String(again.error)
		MapData.select_generated(again.bundle)
	else:
		MapData.select(String(r.document.map))
	pending_load = {"document": r.document, "store_dir": store_dir, "save_dir": save_dir}
	return ""

## 0x41c7d0 case 10 (a Titan of the slot's race at the start), 0x445810 (No Heroes: the race's unit of 0x60b5d8 and two of the
## first purchase entry, each from 0x4402d0's cell) and 0x41c7d0 case 0xc (a flag at each start, numbered 0x7494b4).
const TITAN_LETTERS := "HDUBMOEWKFAVPLRG"     # 0x41c7d0's switch on the race
const NO_HERO_UNITS := ["AHGX", "ADGX", "AUGX", "ABGX", "AMGX", "AOGX", "AEGX", "AWGX", "AKGX", "AFGX", "AAGX", "AVGX", "AHGR", "ALGX", "ARGX", "AGGX"]   # 0x60b5d8 (Data)

## The hero's object contexts of 0x421190 (Read, cursor 0xc in 0x420390): a quest site while Quests are on (commands 0x11,
## Shift 0x34, Alt 0x35 -> 0x51d030 -> order 0xb) and a shop (0x3e, 0x3f, 0x40 -> 0x51d1f0 -> order 0x13). Alt's insert is a
## replace here. The hero walks there; on arrival the order runs the visit 0x43d180 or the shop dialog 0x408580.
var site_orders: Dictionary = {}          # hero unit id -> {"building": id, "kind": "quest" | "shop"}
var site_visit: Dictionary = {}           # the last arrival's result (the dialogs and the checks read it)

