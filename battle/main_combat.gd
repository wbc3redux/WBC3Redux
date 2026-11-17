extends RefCounted
## main.gd's combat and visibility (R-1 split of main.gd, no behaviour change): the combat set-up, unit stats and
## heroes, attack orders, the modern battle rules, fog and its drawing on nodes, deaths. The state stays on the scene
## (main.gd); `main` is the scene.
const Assets = preload("res://core/asset_store.gd")

const MainScript = preload("res://battle/main.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Rules = preload("res://simulation/production_rules.gd")
const Placement = preload("res://simulation/placement.gd")
const Combat = preload("res://simulation/combat.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")
const Missiles = preload("res://simulation/missiles.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const FogView = preload("res://visuals/fog_view.gd")
const Visibility = preload("res://simulation/visibility.gd")
const HeroProfile = preload("res://simulation/hero_profile.gd")
const HeroMatch = preload("res://simulation/hero_match.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")
const Treasures = preload("res://simulation/treasures.gd")
const EntityState = preload("res://simulation/entity_state.gd")
const Encounters = preload("res://simulation/encounters.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const SkirmishSetup = preload("res://simulation/skirmish_setup.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const DayNight = preload("res://simulation/day_night.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

## B2-1 (R3): Army.cfg's shoot id. Only EMF1 is taken: its impact burns; the rebuild draws every other unit's shot as EMA0.
var _burning_shooters: Dictionary = {}
var _shoot_codes: Dictionary = {}           # unit code -> Army.cfg shoot effect code (filled with _burning_shooters)

## Unit +0x1c0 (0x5273c0): the Army.cfg STATUS bits of the type's first row (0x585970), read by the hero slayer skills.
var _status_flags: Dictionary = {}

# ------------------------------------------------------------------ milestone 8: combat and visibility

func setup_combat():
	var seeds: Array = main.combat_seed
	main.combat = Combat.new(CombatRng.new(seeds[0], seeds[1]), main.navigator, main.production, main.units)
	preload("res://simulation/spells.gd").new(main.combat, main)   # B1-4 spell framework: sets combat.spells, adds the ability keys
	main.combat.sprite_rect = main.sprite_rect_for            # launch points and the building pixel test of the missiles (presentation data)
	main.combat.pixel_test = main.building_pixel_hit
	if main.effects != null: main.effects.clear()
	main.visibility = Visibility.new(main.collision.width, main.collision.height)
	main.visibility.set_heights(main.collision)               # vision 2: 0x485ac0's heights for the line of sight 0x485720
	main.visibility.fog = false # off in the movement/production scenes; the combat fixture and the buttons turn it on
	main.visibility.shroud = false
	main.combat.visibility = main.visibility
	main.production.visibility = main.visibility
	main.combat.damaged.connect(main._on_damaged)
	main.combat.died.connect(main._on_died)
	main.combat.berserk_changed.connect(main._on_berserk_changed)
	main.combat.eaten.connect(main._on_eaten)
	main.combat.race_event.connect(main._on_race_event)           # B3-1: stored animals, souls, blast, Goblin, Petrify
	main.combat.rank_gained.connect(main._on_rank_gained)
	main.combat.type_status = main.status_flags
	main.combat.busy_check = func(id: int) -> bool: return main.mine_orders.get(id, {}).get("kind", "") == "convert"   # G-2: order 7 heads the chain
	main.combat.garrison_of = func(id: int) -> Array: return main.unit_commands.occupants(id) if main.unit_commands != null else []   # G-2: tower terms
	main.treasures = Treasures.new()
	main.inventory = {}                               # a new world: the old dialog's working copy is gone
	main.treasures.map_size = Vector2i(main.collision.width, main.collision.height)
	main.treasure_units.clear()
	main.combat.notice.connect(func(text): main.last_message = text)
	main.production.research_completed.connect(main._on_research_completed)
	if main.catalogue_data.is_empty(): main.catalogue_data = Encounters.load_json(Assets.path("catalogue.json"))
	if main.encounter_data.is_empty(): main.encounter_data = Encounters.load_json(Assets.path("encounters.json"))
	if main.ai_data.is_empty(): main.ai_data = UnitAI.load_data()
	if main.encounters != null:
		main.encounters.restore_static()
		main.encounters.dispose()
	main.encounters = Encounters.new(main.combat, main.production, main.economy, main.collision, main.catalogue_data, main.encounter_data, main.ai_data)
	main.encounters.treasures = main.treasures
	# 0x404cf0 -> 0x4a49e0: the lair boss carries status 0x1a (drops one treasure item when it dies).
	main.encounters.spawned.connect(func(info): if info.get("boss", false) and int(info.get("unit", -1)) >= 0: main.treasure_units[int(info.unit)] = true)
	main.encounters.spawn_unit = func(type_id, cell, owner, xp):
		var made = main.add_unit(type_id, cell, owner)
		main.combat.creation_experience(main.combat.fighters.get(made.unit_id), xp)     # +0x10 of message 0xfa, then 0x557d90 (R-1)
		return made.unit_id
	# Q-3: a computer hero's quest (0x504490) completes without a message for the local player.
	main.encounters.quest_event.connect(func(text, info): if int(info.get("player", main.local_player)) == main.local_player: main.last_message = text)
	# Q-1: 0x43d560 cleared this player's quest because another hero completed it at the same giver: line 0xbc (188).
	main.encounters.quest_lost.connect(func(player, _record):
		if player == main.local_player and main.hud != null: main.hud.show_message(main.hud.game_text(188)))
	main.mausoleum_id = -1
	main.lair_id = -1
	main.fog_next_ms = 0
	main.hero_unit_id = -1
	main.hero_match = null
	main.no_hero_items = false
	for unit in main.units: register_combatant(unit)
	main.setup_day_night()                       # B1-3: the weather object's clock (0x498b10 starts every match by day)
	refresh_fog_overlay()

func unit_combat_stats(type_id: String) -> Dictionary:
	var stats: Dictionary = CombatRules.unit_stats(unit_definition(type_id).raw_hex)
	if burning_shooter(type_id): stats["missile"] = main.combat.BURNING_MISSILE   # B2-1: EMF1 (AADR, AGFL)
	else:
		# Playtest 2026-11-12: Army.cfg's shoot id when 0x53f180 is ported for it and its art is imported (the Liche's EMF0);
		# otherwise the arrow EMA0 as before.
		var shoot := String(_shoot_codes.get(type_id, ""))
		if Missiles.TYPES.has(shoot) and not preload("res://core/art_data.gd").data().get("effects", {}).get(shoot, {}).is_empty(): stats["missile"] = shoot
		elif shoot == RacePowers.GOBLIN: stats["missile"] = shoot   # B3-1 (E12): the Gobshooter's Goblin (drawn as the arrow, Open 2)
	if String(_shoot_codes.get(type_id, "")) != "": stats["shoot"] = String(_shoot_codes[type_id])   # G-4: 0x53f180's art kinds
	return stats

func burning_shooter(type_id: String) -> bool:
	if _burning_shooters.is_empty():
		if main.catalogue_data.is_empty(): main.catalogue_data = Encounters.load_json(Assets.path("catalogue.json"))
		_burning_shooters["__loaded"] = true
		for row in main.catalogue_data.get("army_cfg", {}).get("armies", []):
			var shoot = row.get("shoot")
			if shoot is Dictionary: _shoot_codes[String(row.code)] = String(shoot.get("effect_code", ""))
			if shoot is Dictionary and String(shoot.get("effect_code", "")) == main.combat.BURNING_MISSILE: _burning_shooters[String(row.code)] = true
	return _burning_shooters.has(type_id)

## Knights from production.json; any other unit (Gnolls, animals, quest rewards) from its ARM record in catalogue.json.
func unit_definition(type_id: String) -> Dictionary:
	var definition: Dictionary = main.production.rules.definition(type_id)
	if not definition.is_empty(): return definition
	if main.catalogue_data.is_empty(): main.catalogue_data = Encounters.load_json(Assets.path("catalogue.json"))
	if main.encounters != null: return main.encounters.unit_definition(type_id)
	var r = main.catalogue_data.units.get(type_id, {})
	return {"raw_hex": r.raw_hex, "base_speed": CombatRules.i16(String(r.raw_hex).hex_decode(), 0x20)}

## The hero of `unit`'s owner. In a match each player's profile waits in match_profiles until its hero unit exists (0x43b550
## binds the record when it creates the hero); the fixtures keep their single local test hero.
func ensure_hero(unit):
	if main.match_profiles.has(unit.owner_id):
		var bound = HeroMatch.new()
		bound.no_items = main.no_hero_items          # setup rows: 0x749c68, before 0x54fd50 builds the hero
		var saved = main.match_profiles[unit.owner_id]
		var entity = EntityState.new(unit.unit_id, unit.type_id, unit.owner_id, unit.position)
		# A computer slot's hero is the 0x42a0d0 record (milestone 11), a match-only profile copy.
		var ok: bool = bound.bind_computer(saved, entity, "Computer %d" % unit.owner_id) if saved is Dictionary else bound.bind(saved, entity)
		if not ok:
			push_error("Hero binding failed: " + bound.last_error)
		main.match_profiles.erase(unit.owner_id)
		main.match_heroes[unit.owner_id] = bound
		if unit.owner_id == main.local_player:
			main.hero_match = bound
			main.hero_unit_id = unit.unit_id
		return bound
	if main.match_heroes.has(unit.owner_id): return main.match_heroes[unit.owner_id]
	if main.hero_match != null: return main.hero_match
	var profile = HeroProfile.create("combat-fixture", "Sir Fixture")
	main.hero_match = HeroMatch.new()
	main.hero_match.bind(profile, EntityState.new(unit.unit_id, "AHHX", 0, unit.position))
	main.hero_unit_id = unit.unit_id
	return main.hero_match

func register_combatant(unit):
	var stats: Dictionary
	var is_hero: bool = Rules.is_hero_type(unit.type_id) and (unit.owner_id == main.local_player or main.match_profiles.has(unit.owner_id))
	var bound = null
	if is_hero:
		bound = ensure_hero(unit)
		# 0x54fd50 with the record's class, skills and items (milestone 11, Emulated); the hero walks at its own
		# speed (0x51c460: block speed + item terms) instead of the ARM AHHX base 6.
		stats = HeroEffects.hero_unit(bound.record())
		stats["flags"] = HeroEffects.HERO_RACE_FLAGS[clampi(int(bound.profile.data.get("race_id", 0)), 0, 15)]
		unit.base_speed = HeroEffects.movement_speed(int(stats.speed), bound.block())
	else:
		stats = unit_combat_stats(unit.type_id)
		stats["flags"] = status_flags(unit.type_id)
	var fighter = main.combat.register(unit.unit_id, unit.owner_id, unit.type_id, stats, is_hero)
	unit.order_step = func(id, to_cell): main.combat.ai.on_step(id, to_cell)
	# Fog arming: 0x534f00 when the sprite is placed (its owner's map), 0x5377a0 at every step start (every map).
	unit.sight_step = func(owner, from_cell, to_cell, turned): main.visibility.arm_step(owner, from_cell, to_cell, turned)
	main.visibility.arm_placed(unit.owner_id, unit.cell)
	if is_hero: main.combat.bind_hero(unit.owner_id, unit.unit_id, bound)

## Milestone 13: a completed research changes the owner's units at once (the getters read the upgrade table live) and,
## for the local player, the menus (0x436500 ends with 0x4dc6c0 / 0x50f1b0 for the local player).
func _on_research_completed(owner: int, item: String):
	if main.combat != null: main.combat.refresh_research(owner)
	if item == RacePowers.FARSEEING and owner == main.local_player: main.farseeing()   # B2-1 (R8)
	if owner == main.local_player: main.last_message = "%s completed." % main.production.rules.display_name(item)

func status_flags(type_id: String) -> int:
	if _status_flags.is_empty():
		if main.catalogue_data.is_empty(): main.catalogue_data = Encounters.load_json(Assets.path("catalogue.json"))
		for row in main.catalogue_data.get("army_cfg", {}).get("armies", []):
			if not _status_flags.has(row.code): _status_flags[row.code] = int(row.status_fields.bits)
	return int(_status_flags.get(type_id, 0))

func clear_units():
	for unit in main.units:
		main.remove_child(unit)
		unit.free()
	main.units.clear()

# Test harness (button "Combat fixture"): controlled encounters, player 0 (plain) against player 1 (red rings),
# no AI and no victory conditions. Positions are chosen on open ground; nothing here is an original match start.
func spawn_combat_fixture():
	main.reset_fixture()
	clear_units()
	for id in main.building_nodes.keys(): main.building_nodes[id].queue_free()
	main.building_nodes.clear()
	setup_combat()
	main.visibility.fog = true
	main.visibility.shroud = true
	var layout := combat_layout()
	main.layout_cache = layout
	# A. Swordsman duel, B. Squire (missiles) against a Swordsman, C. hero and two Swordsmen against Swordsmen and a Peasant,
	# D. three Swordsmen against an opponent Garrison, E. idle Swordsmen with a visible and a hidden opponent (acquisition, fog).
	var duel_a = main.add_unit("AHKX", layout.duel + Vector2i(-2, 0), 0)
	main.add_unit("AHKX", layout.duel + Vector2i(2, 0), 1)
	main.add_unit("AHMX", layout.ranged + Vector2i(-4, 0), 0)
	main.add_unit("AHKX", layout.ranged + Vector2i(3, 0), 1)
	main.add_unit("AHHX", layout.hero + Vector2i(-3, 0), 0)
	main.add_unit("AHKX", layout.hero + Vector2i(-3, -2), 0)
	main.add_unit("AHKX", layout.hero + Vector2i(-3, 2), 0)
	main.add_unit("AHKX", layout.hero + Vector2i(3, -2), 1)
	main.add_unit("AHKX", layout.hero + Vector2i(3, 0), 1)
	main.add_unit("AHBX", layout.hero + Vector2i(3, 2), 1)
	for i in 3: main.add_unit("AHKX", layout.siege + Vector2i(-6, i * 2 - 2), 0)
	var anchor: Vector2i = Placement.anchor(main.production.rules.definition("BAGA"), layout.siege + Vector2i(4, 0))
	var garrison = main.production.add_completed(1, "BAGA", anchor.x, anchor.y)
	main.add_marker(garrison)
	for i in 3: main.add_unit("AHKX", layout.watch + Vector2i(-2, i * 2 - 2), 0)
	main.add_unit("AHKX", layout.watch + Vector2i(7, 0), 1)       # inside the sight radius of 10: seen at once
	main.add_unit("AHKX", layout.watch + Vector2i(22, 6), 1)      # outside every sight circle: hidden by the fog
	for unit in main.units: unit.selected = unit == duel_a
	visibility_force_sweep()
	main.camera.position = main.navigator.center(layout.duel)
	main.camera.zoom = Vector2.ONE
	main.last_message = "Combat fixture: duel (here), Squire vs Swordsman, hero fight, siege of a Garrison, idle watch with fog. Select units, right-click an enemy to attack."

## Open 15 x 9 areas for each encounter, searched outwards from preferred cells.
func combat_layout() -> Dictionary:
	var wanted := {"duel": Vector2i(30, 76), "ranged": Vector2i(30, 96), "hero": Vector2i(62, 76), "siege": Vector2i(62, 100), "watch": Vector2i(94, 80)}
	var result := {}
	for key in wanted:
		result[key] = find_open_area(wanted[key], 15, 9)
	return result

func find_open_area(wanted: Vector2i, width: int, height: int) -> Vector2i:
	for radius in range(0, 60):
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius: continue
				var centre := wanted + Vector2i(dx, dy)
				var ok := true
				for y in range(centre.y - height / 2, centre.y + height / 2 + 1):
					for x in range(centre.x - width / 2, centre.x + width / 2 + 1):
						var cell := Vector2i(x, y)
						if not main.navigator.enterable_static(cell) or main.navigator.occupant(cell) != null or main.navigator.building_cells.has(cell):
							ok = false
							break
					if not ok: break
				if ok: return centre
	return wanted

func attack_nearest_selected():
	var count := 0
	for unit in main.selected_units():
		var best = nearest_enemy_target(unit)
		if best != null and main.combat.order_attack(unit.unit_id, best.kind, best.id): count += 1
	main.last_message = "%d units ordered to attack the nearest visible enemy." % count

func nearest_enemy_target(unit):
	var here: Vector2i = unit.cell
	var best = null
	var best_distance := 100000
	for f in main.combat.fighters.values():
		if f.owner == unit.owner_id or not main.combat.alive(f) or not main.units[f.id].visible: continue
		var there: Vector2i = main.units[f.id].cell
		var d := maxi(absi(here.x - there.x), absi(here.y - there.y))
		if d < best_distance:
			best_distance = d
			best = {"kind": "unit", "id": f.id}
	for b in main.production.buildings.values():
		if b.owner == unit.owner_id or b.hit_points <= 0 or not main.visibility.is_explored(unit.owner_id, Vector2i(b.left, b.top)): continue
		var d := maxi(absi(here.x - b.left), absi(here.y - b.top))
		if d < best_distance:
			best_distance = d
			best = {"kind": "building", "id": b.entity_id}
	return best

func enemy_at(point: Vector2):
	for unit in main.units:
		if unit.owner_id != main.local_player and unit.visible and not unit.dying and unit.hit_rect().has_point(point):
			return {"kind": "unit", "id": unit.unit_id}
	var cell: Vector2i = main.collision.world_cell(point)
	for id in main.production.buildings:
		var b = main.production.buildings[id]
		if b.owner != main.local_player and b.cell_rect().has_point(cell) and main.visibility.is_explored(main.local_player, cell):
			return {"kind": "building", "id": id}
	return null

## Shift+Esc (0x4296c0): every selected unit (type 0) whose chain has a tail other than its head drops the tail (0x406590).
func remove_last_orders() -> bool:
	if main.combat == null: return false
	var removed := false
	for unit in main.own_selected():
		if main.combat.remove_last_order(unit.unit_id): removed = true
	if removed: main.queue_redraw()
	return removed

func issue_attack(target: Dictionary, append: bool = false, prepend: bool = false) -> int:
	var attackers: Array = main.own_selected() if main.normal_play else main.selected_units()
	# G-3: 0x531480 (flag 1 from every 0x41f0b0 attack command): the slowest 0x51c460(1) of the selection, from 50, becomes
	# every attack order's speed (+0x1e); none below 50 -> -1 (each its own). Read; COMBAT_RESEARCH.md "G-3" 2.
	var group_speed := 50
	for unit in attackers: group_speed = mini(group_speed, int(unit.base_speed))
	if group_speed == 50: group_speed = -1
	if append or prepend:                     # G-2: commands 0x16 (Shift, append) / 0x17 (Alt, insert), 0x41f0b0 (Read)
		var queued := 0
		for unit in attackers:
			if prepend: main.cancel_conversion(unit)   # 0x523dc0 / 0x529a10: only the insert ends a running order 7
			var ok: bool = main.combat.order_attack_insert(unit.unit_id, target.kind, target.id, group_speed) if prepend \
				else main.combat.order_attack_append(unit.unit_id, target.kind, target.id, group_speed)
			if ok: queued += 1
		main.last_message = "%d units %s an attack on the %s." % [queued, "insert" if prepend else "queue", target.kind]
		return queued
	forget_modern_orders(attackers.map(func(u): return u.unit_id))
	if main.navigator.improved and stage_assault(attackers, target): return 0
	var count := 0
	for unit in (main.own_selected() if main.normal_play else main.selected_units()):
		main.patrols.erase(unit.unit_id)
		main.guards.erase(unit.unit_id)
		main.cancel_conversion(unit)
		if main.combat.order_attack(unit.unit_id, target.kind, target.id, false, group_speed): count += 1
	main.last_message = "%d units attack the %s." % [count, target.kind]
	return count

## Reads modern_rules.gd into the running match (called on start and when the Options screen changes a modern row).
func apply_modern_rules():
	var ModernRules = preload("res://simulation/modern_rules.gd")
	main.navigator.improved = ModernRules.movement()
	if main.combat != null: main.combat.improved = ModernRules.movement()
	main.improved_armies = ModernRules.armies()
	main.improved_research = ModernRules.research()
	UnitAgent.always_health = ModernRules.health_bars()
	if main.day_night != null and main.day_night.enabled != DayNight.setting_on():    # B1-3: the Day / Night row, at once
		main.day_night.enabled = DayNight.setting_on()
		main.update_night_light()
	for unit in main.units:
		if unit != null and is_instance_valid(unit): unit.queue_redraw()
	if not main.navigator.improved:
		main.assaults.clear()
		main.attack_moves.clear()

func target_cell_of(target: Dictionary) -> Vector2i:
	if target.kind == "unit":
		var u = main.unit_by_id(int(target.id))
		return u.cell if u != null else Vector2i(-1, -1)
	var b = main.production.building(int(target.id)) if main.production != null else null
	return b.cell_rect().get_center() if b != null else Vector2i(-1, -1)

## F3: a group far from its target first marches (F1) to a staging cell short of it, then everyone attacks together.
## Returns false when the attack should simply be ordered (one unit, or the group is already close).
func stage_assault(group: Array, target: Dictionary) -> bool:
	var fighters: Array = group.filter(func(u): return main.combat.fighters.has(u.unit_id) and not u.flying)
	if fighters.size() < 2: return false
	var there := target_cell_of(target)
	if there.x < 0: return false
	var sum := Vector2i.ZERO
	for u in fighters: sum += u.cell
	var centroid := Vector2i(sum.x / fighters.size(), sum.y / fighters.size())
	var d := main.navigator.chebyshev(centroid, there)
	if d < MainScript.STAGE_MIN_DISTANCE: return false
	var stage := stage_cell(centroid, there, MainScript.STAGE_DISTANCE, 0.0)
	for u in fighters:
		main.patrols.erase(u.unit_id)
		main.guards.erase(u.unit_id)
		main.cancel_conversion(u)
		main.attack_moves.erase(u.unit_id)
	march_units(fighters, stage, {"assault": true})
	main.assaults.append({"ids": fighters.map(func(u): return u.unit_id), "target": target, "issued_ms": main.game_ms()})
	main.last_message = "%d units gather short of the %s, then attack together." % [fighters.size(), target.kind]
	return true

## A free cell `distance` cells from `there`, toward `from` turned by `degrees` (flanking groups use +-50).
func stage_cell(from: Vector2i, there: Vector2i, distance: int, degrees: float) -> Vector2i:
	var away := Vector2(from - there)
	if away == Vector2.ZERO: away = Vector2(0, 1)
	away = away.normalized().rotated(deg_to_rad(degrees)) * distance
	var cell := there + Vector2i(roundi(away.x), roundi(away.y))
	cell = Vector2i(clampi(cell.x, 1, main.collision.width - 2), clampi(cell.y, 1, main.collision.height - 2))
	var free: Vector2i = main.navigator.free_cell_near(cell)
	return free if free.x >= 0 else cell

## F1 march of any units (the computer's groups use it too); the harness message line is left as it was.
func march_units(group: Array, cell: Vector2i, extra: Dictionary = {}):
	if group.is_empty(): return
	var keep := main.last_message
	main.issue_move(main.navigator.center(cell), false, false, false, extra, group)
	main.last_message = keep

## F3: attack-move. The group marches; on the way each unit attacks the nearest enemy it meets, then walks on.
func issue_attack_move(point: Vector2, mods: Dictionary):
	var group: Array = main.own_selected() if main.normal_play else main.selected_units()
	var slowest_default := true
	if main.hud != null and main.hud.settings != null: slowest_default = main.hud.settings.get_value("DefaultGroupMovement") != 0
	main.issue_move(point, false, false, slowest_default == bool(mods.ctrl), {"attack_move": true})
	for u in group: main.attack_moves[u.unit_id] = point
	main.last_message = "Attack-move: %d units." % group.size()

## A new player order takes units out of a staged assault or an attack-move.
func forget_modern_orders(ids: Array):
	for id in ids: main.attack_moves.erase(id)
	for assault in main.assaults: assault.ids = assault.ids.filter(func(id): return not ids.has(id))

func update_modern_orders():
	var now := main.game_ms()
	for assault in main.assaults.duplicate():
		var members: Array = assault.ids.map(func(id): return main.unit_by_id(int(id))).filter(func(u): return u != null and not u.dying)
		if members.is_empty() or not main.combat.target_alive({"target_kind": assault.target.kind, "target_id": assault.target.id}):
			main.assaults.erase(assault)
			continue
		var arrived := members.all(func(u): return u.orders.is_empty() and not u.in_step)
		var hit := members.any(func(u): return main.combat.ai.was_hit(u.unit_id))
		var still_staging := members.any(func(u): return not u.orders.is_empty() and u.orders[0].get("assault", false))
		if arrived or hit or not still_staging or now - int(assault.issued_ms) > MainScript.STAGE_TIMEOUT_MS:
			main.assaults.erase(assault)
			for u in members: main.combat.order_attack(u.unit_id, assault.target.kind, assault.target.id)
	if main.attack_moves.is_empty() or main.combat == null: return
	for id in main.attack_moves.keys():
		var u = main.unit_by_id(int(id))
		if u == null or u.dying:
			main.attack_moves.erase(id)
			continue
		var f = main.combat.fighters.get(int(id))
		if f == null: continue
		if f.get("order") != null: continue                     # fighting
		var goal: Vector2 = main.attack_moves[id]
		if main.navigator.chebyshev(u.cell, main.collision.world_cell(goal)) <= 2 and u.orders.is_empty():
			main.attack_moves.erase(id)
			continue
		var best = nearest_enemy_target(u)
		if best != null and main.navigator.chebyshev(u.cell, target_cell_of(best)) <= MainScript.ATTACK_MOVE_SIGHT:
			main.combat.order_attack(u.unit_id, best.kind, best.id)
		elif u.orders.is_empty() and not u.in_step:
			var cell: Vector2i = main.navigator.free_cell_near(main.collision.world_cell(goal), u, u.extent, u.movement_type)
			if cell.x >= 0:
				u.give_order({"kind": "move", "target": main.navigator.center(cell), "requested": goal, "group": 0, "speed": u.base_speed, "individual": true}, "replace")

func toggle_fog(which: String):
	if which == "fog": main.visibility.fog = not main.visibility.fog
	else: main.visibility.shroud = not main.visibility.shroud
	main.visibility.dirty = true
	apply_fog_to_nodes()
	refresh_fog_overlay()
	main.last_message = "Fog of war %s, shroud %s." % ["on" if main.visibility.fog else "off", "on" if main.visibility.shroud else "off"]

## The attitude command (0x534070, key Ctrl+F): the selected units get the next built-in script and their guard point
## becomes their cell (0x506f10). The order here cycles the five menu attitudes plus Standard.
func toggle_attitude():
	var cycle := [0, 1, 2, 6, 3, 4]
	main.attitude_index = cycle[(cycle.find(main.attitude_index) + 1) % cycle.size()]
	var count := 0
	for unit in main.selected_units():
		var f = main.combat.fighters.get(unit.unit_id)
		if f == null or f.owner != main.local_player: continue
		main.combat.ai.assign_script(f, main.attitude_index)
		count += 1
	main.last_message = "%d units now %s (original built-in attitude script %d)." % [count, UnitAI.script_name(main.attitude_index), main.attitude_index]

func clear_enemies_test():
	for f in main.combat.fighters.values():
		if f.owner != main.local_player and main.combat.alive(f): main.combat.apply_damage("unit", f.id, f.hp + 1, -1)

func sight_sources(viewers = null) -> Array:
	if viewers == null: viewers = fog_players()
	var sources: Array = []
	var shared := {}
	for p in 7: shared[p] = sharing_players(p, viewers)
	for f in main.combat.fighters.values():
		var unit = main.units[f.id]
		if f.state == "dying" or f.state == "corpse" or unit.inside_building or unit.removed: continue
		# 0x546f00: the line-of-sight eye term is 6 for STATUS 0x200000 (flyers) and buildings, 0 for other units.
		sources.append({"player": f.owner, "cell": unit.cell, "radius": Visibility.DEFAULT_RADIUS, "viewers": shared.get(int(f.owner), []),
			"extra": 6 if int(f.stats.get("flags", 0)) & 0x200000 else 0})
	for b in main.production.buildings.values():
		sources.append({"player": b.owner, "cell": Visibility.building_sight_cell(b.left, b.top, int(b.definition.footprint[0]), int(b.definition.footprint[1])),
			"radius": Visibility.DEFAULT_RADIUS, "viewers": shared.get(int(b.owner), []), "extra": 6})
	# Playtest 2026-11-11: the map's mines are building sprites in the original (BLDH records), so 0x546f00 counts an owned
	# mine like any building (sprite kind 3 with a player object: x +0x48, y +0x4a + (height - 1) >> 1, eye term 6). Read.
	if main.mines != null:
		for id in main.mines.mines:
			var m: Dictionary = main.mines.mines[id]
			var owner := int(m.entity.owner)
			if owner < 0 or owner >= 6: continue
			sources.append({"player": owner, "cell": m.entity.cell() + Vector2i(0, (int(m.footprint.y) - 1) >> 1),
				"radius": Visibility.DEFAULT_RADIUS, "viewers": shared.get(owner, []), "extra": 6})
	return sources

## W2: the players whose fog maps are kept: every active side of the skirmish (0..5), the fixture harness's 0 and 1.
func fog_players() -> Array:
	if main.skirmish != null: return SkirmishSetup.active_players(main.skirmish.resolved).filter(func(p): return p < 6)
	return [0, 1]

## The viewers of `owner`'s sprites: the owner and its allies (0x47de40 lights the sprites of the viewing player and its
## allies; allied = the 0x748915 table of the match, teams in the fixture harness).
func sharing_players(owner: int, viewers = null) -> Array:
	if viewers == null: viewers = fog_players()
	var players: Array = []
	for p in viewers:
		if p == owner or (owner >= 0 and owner < 6 and main.combat.allied(p, owner)): players.append(p)
	return players

## The sources are built only for the updates that sweep (1 in 20); the others only advance the counters.
func visibility_update():
	var viewers := fog_players()
	main.visibility.update(sight_sources(viewers) if main.visibility.sweep_due() else [], viewers)

## Harness convenience: show the fixture's first sweep at once instead of on the 4th game update (75 ms later).
func visibility_force_sweep():
	main.visibility.sweep(sight_sources(), fog_players())
	apply_fog_to_nodes()
	refresh_fog_overlay()

func combat_step():
	var now := main.game_ms()
	main.combat.update(now)
	if main.encounters != null: main.encounters.update(now)
	var moved := false
	while main.fog_next_ms <= now:
		visibility_update()
		main.inventory_tick()                      # 0x55e0e0 / 0x53a1a0 counters, one per game update
		main.fog_next_ms += Combat.UPDATE_MS
		moved = true
	if moved:
		apply_fog_to_nodes()
		if main.visibility.dirty: refresh_fog_overlay()

func apply_fog_to_nodes():
	for unit in main.units:
		if unit.removed:
			unit.visible = false
		elif unit.owner_id != main.local_player:
			unit.visible = main.visibility.unit_visible(main.local_player, unit.unit_id, unit.owner_id, unit.cell)   # B1-6c: +0x1f1
	for id in main.building_nodes:
		var b = main.production.building(id)
		if b != null and b.owner != main.local_player:
			main.building_nodes[id].visible = main.visibility.is_explored(main.local_player, Vector2i(b.left, b.top))
		# P-2: palette 6 while fog is on and the sprite cell is not visible (0x53b2b7, any owner). P-4: 0x47f560 reads the
		# drawing copy inside the view (fog_view.gd, presentation only).
		main.building_nodes[id].set_fogged(main.visibility.fog and not FogView.lit(main.visibility, main.local_player, main.building_nodes[id].sprite_cell()))
	for object in main.map_objects:
		if object.is_building: object.set_fogged(main.visibility.fog and not FogView.lit(main.visibility, main.local_player, Vector2i(int(object.position.x) / 32, int(object.position.y) / 24)))

## M-2: built from the visibility bytes in one pass (set_pixel per cell took 33 ms on a 256 map, twice a second); the same
## pixels as before: alpha 255 unexplored (shroud), Color(0, 0, 0, 0.45).a8 not visible now (fog), 0 otherwise.
func refresh_fog_overlay():
	main.visibility.dirty = false
	var width: int = main.visibility.width
	var height: int = main.visibility.height
	var count := width * height
	main.visibility.ensure(main.local_player)
	var explored: PackedByteArray = main.visibility.explored[main.local_player]
	var seen: PackedByteArray = main.visibility.visible[main.local_player]
	var dim := Color(0, 0, 0, 0.45).a8
	var pixels := PackedByteArray()
	# P-3: with 0 / 1 bytes (what visibility.gd writes) every pixel starts as the fog's alpha word (fill) and only the visible
	# and the unexplored cells are visited (find); the same pixels as the loop below, which stays for other bytes.
	if explored.count(0) + explored.count(1) == count and seen.count(0) + seen.count(1) == count:
		var words := PackedInt32Array()
		words.resize(count)
		words.fill(dim << 24 if main.visibility.fog else 0)            # RGBA8 little-endian: the alpha is the top byte
		if main.visibility.fog:
			var i := seen.find(1)
			while i >= 0:
				words[i] = 0
				i = seen.find(1, i + 1)
		if main.visibility.shroud:
			var i := explored.find(0)
			while i >= 0:
				words[i] = -16777216                                # 0xff000000
				i = explored.find(0, i + 1)
		pixels = words.to_byte_array()
	else:
		pixels.resize(count * 4)
		for i in count:
			if main.visibility.shroud and explored[i] == 0: pixels[i * 4 + 3] = 255
			elif main.visibility.fog and seen[i] == 0: pixels[i * 4 + 3] = dim
	if main.fog_image == null or main.fog_image.get_width() != width or main.fog_image.get_height() != height:
		main.fog_image = Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	else:
		main.fog_image.set_data(width, height, false, Image.FORMAT_RGBA8, pixels)
	main.fog_overlay.texture = ImageTexture.create_from_image(main.fog_image)

func _on_damaged(kind: String, id: int, amount: int, attacker: int):
	main.last_message = "%s %d takes %d damage." % [kind, id, amount]
	# Alerts (0x4dcf70 with 1 -> 0x425b90): P-1 found the trigger (Read): the attack code pushes an alert exactly when its
	# "under attack" speech plays (0x522860, 0x52b180, 0x5210b0), so audio_manager.gd calls strategic_alert() there.

func _on_died(kind: String, id: int, killer_owner: int):
	if kind == "building":
		if main.building_nodes.has(id):
			main.building_nodes[id].queue_free()
			main.building_nodes.erase(id)
		main.last_message = "Building %d destroyed." % id
		if not main.unit_commands.occupants(id).is_empty(): main.unload_building(main.production.building(id), id)   # Provisional: the occupants step out
	else:
		main.production.unregister_unit(id)
		main.last_message = "Unit %d died." % id
		# 0x5210b0 -> 0x528300 -> message 0x198 (0x4a87f0): a dying hero's backpack items, or one random treasure item for
		# a unit with status 0x1a (the lair boss), are dropped at the death cell (milestone 11); 0x4a8f50 then clears the
		# backpack and saves the local hero at once.
		var cell: Vector2i = main.units[id].cell
		if main.treasure_units.has(id):
			main.treasure_units.erase(id)
			main.treasures.drop(ComputerHero.random_treasure(main.combat.rng, true, true), cell, "lair boss")
		for owner in main.match_heroes:
			var bound = main.match_heroes[owner]
			if bound.entity == null or bound.entity.entity_id != id: continue
			main.treasures.drop_all(bound.profile.data.backpack.map(func(slot): return int(slot.get("item", 0))), cell, "hero %d" % owner)
			if bound.computer: bound.hero_died(null)
		if main.skirmish != null and id == main.hero_unit_id and main.hero_match != null and main.hero_store != null:
			if not main.hero_match.hero_died(main.hero_store): push_error("Hero death save failed: " + main.hero_match.last_error)
			main.last_message = "Your hero has fallen. The backpack items fall to the ground; the hero does not return in this battle."

func combat_text() -> String:
	var mine := 0
	var theirs := 0
	for f in main.combat.fighters.values():
		if not main.combat.alive(f): continue
		if f.owner == main.local_player: mine += 1
		else: theirs += 1
	var text := "Combat: %d own / %d other alive · kills %d · fog %s shroud %s · scripts %s" % [mine, theirs, int(main.combat.kills.get(main.local_player, 0)),
		"on" if main.visibility.fog else "off", "on" if main.visibility.shroud else "off", "on" if main.combat.auto_acquire else "off"]
	if main.hero_match != null and main.hero_match.profile != null:
		text += " · hero level %d xp %d" % [int(main.hero_match.profile.data.level), int(main.hero_match.profile.data.xp)]
	var picked := main.selected_units()
	if picked.size() == 1:
		var f = main.combat.fighters.get(picked[0].unit_id)
		if f != null: text += " · %s hp %d/%d %s, %s" % [f.type_id, f.hp, f.max_hp, f.state, UnitAI.script_name(int(f.script))]
	text += main.encounter_text()
	return text

