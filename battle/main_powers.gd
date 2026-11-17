extends RefCounted
## main.gd's race powers (R-1 split of main.gd, no behaviour change): sprite pixel hits for the effects, day / night,
## rain and night light, advancement, building and unit powers of batches 1-4 (Gravestone, Slavehorde, Brew,
## Berserk, Brood, Ancestral Spirit, Stormcall, merge, Sacrifice ...). The state stays on the scene (main.gd).

const MainScript = preload("res://battle/main.gd")
const ArtData = preload("res://core/art_data.gd")
const UnitRanks = preload("res://simulation/unit_ranks.gd")
const Advancement = preload("res://simulation/advancement.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const DayNight = preload("res://simulation/day_night.gd")
var main: MainScript

func _init(scene: MainScript) -> void:
	main = scene

var _pixel_images: Dictionary = {}
var _flash_drawn := -1

# ------------------------------------------------------------------ milestone 11: missiles and effects (EFFECTS_RESEARCH.md)
## Sprite rectangle +0x58..+0x5e of a shooter: a unit at its hit entry shows its f sheet (ANI slot 2); a building its
## standing sheet. Position minus the ANI pivot, frame size.
func sprite_rect_for(kind: String, id: int):
	if kind == "unit":
		if id < 0 or id >= main.units.size(): return null
		var u = main.units[id]
		var sheet: Dictionary = ArtData.unit_sheet(u.art_type, 2)
		if sheet.is_empty(): sheet = ArtData.unit_sheet(u.art_type, 0)
		if sheet.is_empty(): return null
		return [int(u.position.x) - int(sheet.pivot[0]), int(u.position.y) - int(sheet.pivot[1]), int(sheet.frame_size[0]), int(sheet.frame_size[1])]
	var b = main.production.building(id) if main.production != null else null
	if b == null: return null
	var sheet := building_sheet_of(b)
	if sheet.is_empty(): return null
	var cell := Vector2i(int(b.position.x) / 32, int(b.position.y) / 24)
	return [cell.x * 32 + 16 - int(sheet.pivot[0]), cell.y * 24 + 12 - int(sheet.pivot[1]), int(sheet.frame_size[0]), int(sheet.frame_size[1])]

func building_sheet_of(b) -> Dictionary:
	var code := String(b.original_type_id)
	if b.constructing:
		var z: Dictionary = ArtData.building_sheet(code, 5)
		if not z.is_empty(): return z
	return ArtData.building_sheet(code, 0)

## 0x487c60 (building sprite +0x44): the missile's pixel must fall on an opaque, non-shadow pixel of the drawn frame.
func building_pixel_hit(id, x: int, y: int) -> bool:
	var b = main.production.building(int(id)) if main.production != null else null
	if b == null: return true
	var sheet := building_sheet_of(b)
	var rect = sprite_rect_for("building", int(id))
	if sheet.is_empty() or rect == null: return true
	var column := 0
	if b.constructing: column = 2 if b.progress >= 67 else (1 if b.progress >= 34 else 0)
	var lx: int = x - int(rect[0])
	var ly: int = y - int(rect[1])
	if lx < 0 or ly < 0 or lx >= int(rect[2]) or ly >= int(rect[3]): return false
	if not _pixel_images.has(sheet.texture):
		var tex: Texture2D = ArtData.texture(sheet.texture)
		_pixel_images[sheet.texture] = tex.get_image() if tex != null else null
	var image: Image = _pixel_images[sheet.texture]
	if image == null: return true
	var px := column * int(rect[2]) + lx
	if px >= image.get_width() or ly >= image.get_height(): return false
	return image.get_pixel(px, ly).a >= 0.999

func setup_day_night():
	main.day_night = DayNight.new(DayNight.setting_on())
	if main.combat != null: main.combat.day_night = main.day_night
	if main.combat != null: main.day_night.rng = main.combat.rng      # setup rows: the weather roll 0x49e360 draws the match generator
	main.slavehorde_ms = -100000
	main.brood_ms = -100000                                     # B3-1
	main.spirit_i_ms = -100000
	main.spirit_ii_ms = -100000
	main.scavenge_ms = -100000
	main.scavenge_records.clear()
	update_night_light()

## Each simulation step: the 50 ms clock ticks, the brew timers and the world's lighting level.
func update_race_powers():
	if main.day_night != null: main.day_night.update(main.game_ms())
	if main.combat != null: update_brew()
	update_night_light()

func update_rain_fx():
	if main.day_night == null: return
	if main.rain_layer == null:
		if not main.day_night.raining: return
		main.rain_layer = preload("res://visuals/rain_fx.gd").new()
		main.rain_layer.main = main
		main.add_child(main.rain_layer)
	main.rain_layer.step(main.game_ms(), main.day_night, Rect2(main.view_top_left(), main.view_world_size()), main.visibility != null and main.visibility.fog)
	if int(main.rain_layer.flash_level) != _flash_drawn:
		_flash_drawn = int(main.rain_layer.flash_level)
		update_night_light()

## The lighting level the renderer draws with (0x495c30 reads *DAT_00a38b98): only drawn while it is not 0.
func update_night_light():
	var lit: int = int(main.day_night.level) if main.day_night != null and main.day_night.enabled else 0
	if main.rain_layer != null and int(main.rain_layer.flash_level) >= 0: lit = int(main.rain_layer.flash_level)   # P-2: a storm flash
	if lit == 0:
		if main.night_layer != null: main.night_layer.visible = false
		return
	if main.night_layer == null:
		main.night_layer = CanvasLayer.new()
		main.night_layer.layer = 1                 # above the world, below the colour grade (2), the weather (3) and the HUD (5)
		main.add_child(main.night_layer)
		main.night_rect = ColorRect.new()
		main.night_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var material := ShaderMaterial.new()
		material.shader = preload("res://visuals/night_light.gdshader")
		main.night_rect.material = material
		main.night_layer.add_child(main.night_rect)
	main.night_layer.visible = true
	main.night_rect.size = main.get_viewport_rect().size
	(main.night_rect.material as ShaderMaterial).set_shader_parameter("level", lit)

func unit_pixel(cell: Vector2i) -> Vector2i:
	return Vector2i(cell.x * 32 + 16, cell.y * 24 + 12)

func play_at(sound: String, cell: Vector2i):
	if main.audio != null: main.audio.positional("sfx/" + sound.get_basename(), cell)

# ---------------------------------------------------------------- advancement (0x4d3200 / 0x4cef90 / 0x4a8ff0)
## The advancement buttons for the local player's selection: all one type, no hero (0x4d3200 bVar4), race 2.
func advancement_buttons(selection: Array) -> Array:
	if main.production == null or selection.is_empty() or main.production.race_of(main.local_player) != Advancement.UNDEAD: return []
	var source := String(selection[0].type_id)
	for u in selection:
		if String(u.type_id) != source or main.is_hero_unit(u): return []
	var stock: Array = main.economy.resources(main.local_player)
	var p := main.local_player
	return Advancement.buttons(source, selection.size(), func(code): return main.production.requirement_met(p, code),
		func(target): return main.production.price_of(p, target), stock)

## A press (LAB_004cf4b0 ...): price 0x40b6b0(target, source, player), then the order 0x4cef90 and its messages.
func advance_selected(target: String) -> int:
	var selection: Array = main.own_selected()
	var cost: Array = main.production.price_of(main.local_player, target)
	var listed: Array = selection.map(func(u): return {"id": u.unit_id, "type": String(u.type_id), "removed": u.dying or u.removed})
	var messages: Array = Advancement.order(listed, target, cost, main.economy.resources(main.local_player))
	var made := 0
	for m in messages:
		for i in m.units.size():
			var u = main.unit_by_id(int(m.units[i]))
			if u != null and morph_unit(u, target, i == 0) != null: made += 1
		main.economy.debit_clamped(main.local_player, m.cost)      # 0x4a8ff0 / 0x4a9400 end with 0x43eb80(player, the message's costs)
	if made > 0: main.last_message = "%d advanced to %s." % [made, main.production.rules.display_name(target)]
	return made

## 0x4a8ff0 / 0x4a9400 for one unit: EZ41 (Morph.wav with the first unit of a message), the old unit removed without a
## death (0x51a130(1)), the new one created at its cell (0x4a49e0) with max(old experience, starting experience) (Open 1),
## selected again when the old one was, and its place in the control groups (0x4254c0).
func morph_unit(unit, target: String, with_sound: bool = true):
	if unit == null or unit.dying or unit.removed: return null
	var cell: Vector2i = unit.cell
	var owner: int = unit.owner_id
	var was_selected: bool = unit.selected
	var f = main.combat.fighters.get(unit.unit_id) if main.combat != null else null
	var old_xp: int = int(f.xp) if f != null else 0
	if main.effects != null: main.effects.spawn_effect(Advancement.EFFECT, unit_pixel(cell), cell.y, true)
	if with_sound: play_at(Advancement.SOUND, cell)
	remove_unit_quietly(unit)
	var made = main.add_unit(target, cell, owner)
	main.production.register_unit(made.unit_id, target, owner)
	if main.combat != null and main.combat.fighters.has(made.unit_id):
		main.combat.gain_experience(main.combat.fighters[made.unit_id], Advancement.morphed_xp(old_xp, main.combat.starting_xp(owner, target)))
	if was_selected and owner == main.local_player: made.selected = true
	for n in main.control_groups:
		var ids: Array = main.control_groups[n].units
		var at := ids.find(unit.unit_id)
		if at >= 0: ids[at] = made.unit_id
	return made

## 0x51a130(1): off the map, out of the selection and the population, no corpse and no experience.
func remove_unit_quietly(unit):
	unit.stop()
	unit.selected = false
	main.navigator.release(unit, unit.cell)
	unit.visible = false
	unit.removed = true
	unit.dying = true
	if main.combat != null and main.combat.fighters.has(unit.unit_id):
		var f = main.combat.fighters[unit.unit_id]
		f.removed = true
		f.order = null
		f.swing = null
	if main.production != null: main.production.unregister_unit(unit.unit_id)
	main.patrols.erase(unit.unit_id)
	main.guards.erase(unit.unit_id)

# ---------------------------------------------------------------- building powers (cell 8)
func command_free(owner: int) -> bool:
	var pop: Dictionary = main.production.population(owner)
	return int(pop.current) < int(pop.maximum)

## 0x4ceee0 -> message 0x1f5 -> 0x4a9230: the gravestone becomes a Skeleton.
func raise_gravestone(b) -> int:
	if b == null or String(b.original_type_id) != RacePowers.GRAVESTONE or b.constructing: return -1
	if not command_free(int(b.owner)): return -1
	var cell: Vector2i = Vector2i(b.left, b.top)
	var owner: int = int(b.owner)
	if main.effects != null: main.effects.spawn_effect(Advancement.EFFECT, unit_pixel(cell), cell.y, true)
	play_at(Advancement.SOUND, cell)
	main.production._destroy(b)                               # 0x40ada0: the gravestone is removed (no rubble, no death)
	var free: Vector2i = main.navigator.free_cell_near(cell)
	if free.x < 0: return -1
	var made = main.add_unit(RacePowers.GRAVESTONE_UNIT, free, owner)
	main.production.register_unit(made.unit_id, RacePowers.GRAVESTONE_UNIT, owner)
	if main.combat != null: main.combat.creation_experience(main.combat.fighters.get(made.unit_id), 0)
	main.last_message = "The gravestone rises as a Skeleton."
	return made.unit_id

## LAB_004d0c50: Slavehorde. Returns the thralls made.
func slavehorde(b) -> int:
	if b == null: return 0
	var owner: int = int(b.owner)
	var pop: Dictionary = main.production.population(owner)
	var n := RacePowers.slavehorde_count(int(pop.current), int(pop.maximum))
	if n <= 0: return 0
	var now := main.game_ms()
	if main.slavehorde_ms > -100000 and now <= main.slavehorde_ms + RacePowers.SLAVEHORDE_MS: return 0
	main.slavehorde_ms = now                                    # stamped before the cost test
	if int(main.economy.resources(owner)[0]) < RacePowers.THRALL_GOLD * n:
		if main.audio != null and owner == main.local_player: main.audio.speech(0x11)
		return 0
	var target: Vector2i = main.production.spawn_target(b)
	if target.x < 0: return 0
	main.economy.debit_clamped(owner, [RacePowers.THRALL_GOLD * n, 0, 0, 0])   # message 0x1fe
	var made := 0
	for i in n:                                            # message 0xfa per thrall, no rally order
		if main.production.spawn_unit(owner, RacePowers.THRALL, target, b.entity_id) >= 0: made += 1
	main.last_message = "Slavehorde: %d thralls for %d gold." % [made, RacePowers.THRALL_GOLD * n]
	return made

## LAB_004d1300 (Dark Citadel) and LAB_004d11b0 (Rites of Dawn): pay the crystal, then the kind-4 record.
func weather_power(b, night: bool) -> bool:
	if b == null or main.day_night == null: return false
	var owner: int = int(b.owner)
	var crystal: int = DayNight.DARK_CITADEL_CRYSTAL if night else DayNight.RITES_CRYSTAL
	if int(main.economy.resources(owner)[2]) < crystal:
		if main.audio != null and owner == main.local_player: main.audio.speech(0x14)
		return false
	main.economy.debit_clamped(owner, [0, 0, crystal, 0])
	main.day_night.apply_record((3 if main.day_night.raining else 2) if night else 0)
	main.last_message = "%s." % ("Dark Citadel: night falls" if night else "Rites of Dawn: day breaks")
	return true

# ---------------------------------------------------------------- unit powers (Brew, Zombie scavenging)
func drinker(u) -> bool:
	return RacePowers.can_drink(String(u.type_id), main.status_flags(String(u.type_id)), main.is_hero_unit(u))

## 0x4cf7d0 -> message 0x202 -> 0x5285d0(1) per unit.
func brew_selected() -> int:
	if main.production.research_level(main.local_player, RacePowers.BREW_RESEARCH) == 0: return 0
	var drinkers: Array = main.own_selected().filter(func(u): return drinker(u))
	if drinkers.is_empty(): return 0
	if int(main.economy.resources(main.local_player)[0]) < RacePowers.BREW_GOLD * drinkers.size():
		if main.audio != null: main.audio.speech(0x11)
		return 0
	var drunk := 0
	for u in drinkers:
		if drink(u): drunk += 1
	if drunk > 0 and main.game_ms() > main.brew_sound_ms + 1000:
		main.brew_sound_ms = main.game_ms()
		play_at("DwarvenBrew.wav", drinkers[0].cell)
	return drunk

func drink(u) -> bool:
	var f = main.combat.fighters.get(u.unit_id) if main.combat != null else null
	if f == null or int(f.get("drunk_until", 0)) > 0 or not drinker(u): return false
	if int(main.economy.resources(u.owner_id)[0]) <= 9: return false
	if not main.combat.ai_players.has(u.owner_id): main.economy.debit_clamped(u.owner_id, [RacePowers.BREW_GOLD, 0, 0, 0])
	f["drunk_until"] = main.combat.now_ms + RacePowers.BREW_MS
	main.combat.refresh_brew(f)
	if main.effects != null: main.effects.spawn_effect("EZ38", unit_pixel(u.cell), u.cell.y, false, 0, u)
	return true

## 0x51c977: sober once the 120 s are over.
func update_brew():
	for f in main.combat.fighters.values():
		if int(f.get("drunk_until", 0)) > 0 and main.combat.now_ms > int(f.drunk_until):
			f["drunk_until"] = 0
			main.combat.refresh_brew(f)

## LAB_004cfc30 -> 0x4cfc90 -> 0x578e10: the Zombie's scavenging record (its effect is B1-4's applier, Open).
## B1-5: the computer's Zombie (0x502ba0) calls 0x578e10 directly, without 0x4cfc90's once-per-second throttle
## (`throttle` false).
func scavenge(u, throttle: bool = true) -> Dictionary:
	if u == null or String(u.type_id) != RacePowers.SCAVENGER: return {}
	if main.production.research_level(u.owner_id, RacePowers.SCAVENGE_RESEARCH) == 0: return {}
	var now := main.game_ms()
	if throttle:
		if main.scavenge_ms > -100000 and now < main.scavenge_ms: return {}
		main.scavenge_ms = now + RacePowers.SCAVENGE_MS
	var remains := 0
	for f in main.combat.fighters.values():                     # death remains (EDTH): corpses in state "corpse" (Provisional)
		if f.state != "corpse" or f.removed: continue
		var c: Vector2i = main.units[f.id].cell
		var d: Vector2i = c - u.cell
		if absi(d.y) <= 7 and d.x * d.x + d.y * d.y < RacePowers.SCAVENGE_RADIUS2: remains += 1
	var level := RacePowers.scavenge_level(int(main.combat.fighters[u.unit_id].get("rank", 0)))
	var amounts: Array = RacePowers.scavenge_amounts(remains, 0, level, main.combat.rng)   # ruins Open
	var record := {"kind": RacePowers.SCAVENGE_KIND, "effect": RacePowers.SCAVENGE_EFFECT, "owner": u.owner_id, "unit": u.unit_id,
		"amounts": amounts, "remains": remains}
	main.scavenge_records.append(record)
	return record

func _on_rank_gained(id: int, rank: int):
	var u = main.unit_by_id(id)
	if u == null or u.owner_id != main.local_player: return
	for code in UnitRanks.LEVEL_EFFECTS:
		if main.effects != null: main.effects.spawn_effect(code, unit_pixel(u.cell), u.cell.y, true, 0, u)
	var now := Time.get_ticks_msec()
	if now - main.rank_sound_ms >= UnitRanks.LEVEL_SOUND_MS:
		main.rank_sound_ms = now
		play_at("GainedLevel", u.cell)
	main.last_message = "Gained Level %d" % (rank + 1)
	if main.effects != null: main.effects.float_over_unit(u, "Gained Level %d" % (rank + 1), 4)   # P-1: 0x53a010 (colour 4, 1000 ms)

func in_berserk_state(u) -> bool:
	var f = main.combat.fighters.get(u.unit_id) if main.combat != null else null
	return f != null and f.get("berserk") != null

## LAB_004cf930 -> message 0x204 (level 2) -> 0x4a9aa0 -> 0x527720 per unit. No cost. Returns the units in the state.
func berserk_selected() -> int:
	if main.combat == null or main.combat.spells == null: return 0
	var made := 0
	for u in main.own_selected():
		main.combat.spells.berserk({"kind": "unit", "id": int(u.unit_id)}, RacePowers.BERSERK_LEVEL)
		if in_berserk_state(u): made += 1
	return made

## 0x527720's art on a first entry (EF04 on the unit until the state ends, EZ50 once); the sound 0x44edb0 is not ported.
func _on_berserk_changed(id: int, level: int, first: bool):
	var u = main.unit_by_id(id)
	if main.effects == null: return
	if level == 0 and u != null: main.effects.float_over_unit(u, main.game_string(0x45d, "Critical: Burn"), 0)   # P-3: 0x527720(0), Read
	if level < 0:
		if main.berserk_art.has(id): main.effects.remove_effect(main.berserk_art[id])
		main.berserk_art.erase(id)
	elif first and u != null and u.visible:
		main.berserk_art[id] = main.effects.spawn_effect("EF04", unit_pixel(u.cell), u.cell.y, false, 0, u)
		main.effects.spawn_effect("EZ50", unit_pixel(u.cell), u.cell.y, true)

## 0x5210b0: Eating.wav at the victim (R4) and its 0x58c0d0 burst (P-1, particle_bursts.gd EATING).
func _on_eaten(_killer_id: int, cell: Vector2i):
	play_at(RacePowers.EATING_SOUND, cell)
	if main.effects != null: main.effects.bursts.burst(preload("res://visuals/particle_bursts.gd").EATING, unit_pixel(cell), cell.y, main.effects.now())

## 0x4382d0 (E3): one unit of the pool at the building, no command test, with the building's rally point. Returns its id.
func _on_mercenary_completed(building_id: int, item: String) -> int:
	var b = main.production.building(building_id)
	if b == null or main.combat == null: return -1
	var type := RacePowers.mercenary_type(item, main.combat.rng)
	return main.production.spawn_unit(int(b.owner), type, main.production.spawn_target(b), building_id, b.rally)

## R8 (Read): 0x436500 for the local player: the fog and the hidden map go (0x547ba0 marks every object visible, then a redraw).
func farseeing():
	if main.visibility == null: return
	main.visibility.fog = false
	main.visibility.shroud = false
	main.visibility.dirty = true

## 0x4d0e50: Brood. Returns the Quasits made.
func brood(b) -> int:
	if b == null: return 0
	var owner: int = int(b.owner)
	var pop: Dictionary = main.production.population(owner)
	var n := RacePowers.brood_count(int(pop.current), int(pop.maximum))
	if n <= 0: return 0
	var now := main.game_ms()
	if main.brood_ms > -100000 and now <= main.brood_ms + RacePowers.BROOD_MS: return 0
	main.brood_ms = now                                         # stamped before the price test
	if int(main.economy.resources(owner)[0]) < RacePowers.BROOD_GOLD * n:
		if main.audio != null and owner == main.local_player: main.audio.speech(0x11)
		return 0
	var target: Vector2i = main.production.spawn_target(b)
	if target.x < 0: return 0
	main.economy.debit_clamped(owner, [RacePowers.BROOD_GOLD * n, 0, 0, 0])      # message 0x1fe
	var made := 0
	for i in n:                                            # message 0xfa per Quasit, no rally order
		if main.production.spawn_unit(owner, RacePowers.BROOD_UNIT, target, b.entity_id) >= 0: made += 1
	main.last_message = "Brood: %d Quasits for %d gold." % [made, RacePowers.BROOD_GOLD * n]
	return made

## 0x4d1680 (tier 1) / 0x4d1460 (tier 2): Ancestral Spirit. Returns the unit's id or -1.
func ancestral_spirit(b, tier: int) -> int:
	if b == null or not RacePowers.SPIRITS.has(tier): return -1
	var spirit: Dictionary = RacePowers.SPIRITS[tier]
	var owner: int = int(b.owner)
	var pop: Dictionary = main.production.population(owner)
	if mini(1, int(pop.maximum) - int(pop.current)) <= 0: return -1
	var now := main.game_ms()
	var stamp: int = main.spirit_i_ms if tier == 1 else main.spirit_ii_ms
	if stamp > -100000 and now <= stamp + RacePowers.SPIRIT_MS: return -1
	if tier == 1: main.spirit_i_ms = now
	else: main.spirit_ii_ms = now
	if int(main.economy.resources(owner)[2]) < int(spirit.crystal):
		if main.audio != null and owner == main.local_player: main.audio.speech(0x14)
		return -1
	var target: Vector2i = main.production.spawn_target(b)
	if target.x < 0: return -1
	main.economy.debit_clamped(owner, [0, 0, int(spirit.crystal), 0])
	var id: int = main.production.spawn_unit(owner, String(spirit.unit), target, b.entity_id, Vector2i(-1, -1), {"no_start": true})
	if id >= 0: main.last_message = "Ancestral Spirit: a %s for %d crystal." % [main.production.rules.display_name(String(spirit.unit)), int(spirit.crystal)]
	return id

## 0x4d18a0: Stormcall: 80 crystal, then the kind-4 record 4 (5 by night) through DayNight.apply_record, which drops it during a
## fade (the crystal is paid all the same, REVIEW_BATCH3.md R2).
func stormcall(b) -> bool:
	if b == null or main.day_night == null: return false
	var owner: int = int(b.owner)
	if int(main.economy.resources(owner)[2]) < RacePowers.STORMCALL_CRYSTAL:
		if main.audio != null and owner == main.local_player: main.audio.speech(0x14)
		return false
	main.economy.debit_clamped(owner, [0, 0, RacePowers.STORMCALL_CRYSTAL, 0])
	main.day_night.apply_record(RacePowers.stormcall_amount(main.day_night.is_night()))
	main.last_message = "Stormcall."
	return true

## Presentation of combat.gd's batch-3 events.
func _on_race_event(kind: String, info: Dictionary):
	var cell: Vector2i = info.get("cell", Vector2i(-1, -1))
	match kind:
		"stored":
			if main.game_ms() > main.store_sound_ms + 1000:
				main.store_sound_ms = main.game_ms()
				play_at(String(info.sound), cell)
		"petrify":
			if main.effects != null: main.effects.spawn_effect(RacePowers.PETRIFY_EFFECT, unit_pixel(cell), cell.y, true)
			play_at(RacePowers.PETRIFY_SOUND, cell)
			if main.effects != null and info.has("shooter"): main.effects.petrify_text(int(info.shooter))   # P-3: 0x4a9c90's text
		"soul":
			if main.effects != null: main.effects.spawn_effect(RacePowers.SOUL_EFFECT, unit_pixel(cell), cell.y, true)   # P-3: ESSP is an emitter (0x40ebd0)
		"soul_mana":
			var u = main.unit_by_id(int(info.id))
			if u != null and main.effects != null: main.effects.spawn_effect(String(info.effect), unit_pixel(u.cell), u.cell.y, true, 0, u)
		"spawned", "egg":                                      # B4-1: the death spawns' EZ08, the hatch's ESSP, the egg's ECHE
			if main.effects != null: main.effects.spawn_effect(String(info.effect), unit_pixel(cell), cell.y, true)   # the egg's sound 26: Open
		"meteor_blast":                                        # P-2: the meteor's landing (effects_layer.gd meteor_landing)
			if main.effects != null: main.effects.meteor_landing(cell)
		"blast":                                               # P-2: the Firebomb / Spore bursts (0x529a40)
			if main.effects != null: main.effects.blast(cell)

## 0x531f10's walk of units and buildings for one player (E3): {"income": lanes, "producers": lanes}.
func other_income(player: int) -> Dictionary:
	var types: Array = []
	if main.combat != null:
		for f in main.combat.fighters.values():
			if int(f.owner) == player and not f.removed and main.combat.alive(f) and RacePowers.UNIT_INCOME.has(String(f.type_id)): types.append(String(f.type_id))
	var wells := 0
	for b in main.production.buildings.values():
		if int(b.owner) == player and String(b.original_type_id) == RacePowers.WELL and not b.constructing and int(b.hit_points) > 0: wells += 1
	return RacePowers.income_of(types, wells)

## 0x4ce120 for the current selection (the merge cell is shown).
func merge_shown(selection: Array) -> bool:
	return RacePowers.merge_box(selection.map(func(u): return String(u.type_id)), selection.map(func(u): return u.cell))

## The merge cell's state: PWSP and the price of one Ancient Wisp (0x40b6b0(AEAX, AEBX)).
func merge_enabled(owner: int) -> bool:
	if main.production.research_level(owner, RacePowers.MERGE_RESEARCH) == 0: return false
	return _affordable(owner, main.production.price_of(owner, RacePowers.ANCIENT_WISP, RacePowers.WISP))

func _affordable(owner: int, price: Array) -> bool:
	var stock: Array = main.economy.resources(owner)
	for lane in 4:
		if int(stock[lane]) < int(price[lane]): return false
	return true

## 0x4cea80 (E1): groups of four in selection order; each group that can pay the price pays it (0x43ee50) and merges. Returns the
## Ancient Wisps made.
func merge_selected() -> int:
	var selection: Array = main.own_selected()
	if not merge_shown(selection) or main.production.research_level(main.local_player, RacePowers.MERGE_RESEARCH) == 0: return 0
	var made := 0
	for g in selection.size() / RacePowers.MERGE_GROUP:
		var group: Array = selection.slice(g * RacePowers.MERGE_GROUP, (g + 1) * RacePowers.MERGE_GROUP)
		var price: Array = main.production.price_of(main.local_player, RacePowers.ANCIENT_WISP, RacePowers.WISP)
		if not main.economy.try_spend(main.local_player, price): continue
		if merge_group(main.local_player, group.map(func(u): return int(u.unit_id))) >= 0: made += 1
	if made > 0: main.last_message = "%d Ancient Wisp%s." % [made, "" if made == 1 else "s"]
	return made

## E1 / E2: the leader (the first id) is ordered to its own cell (order 10), so 0x5205d0 case 10 runs at its first task check: every
## listed Wisp that still exists is removed (message 0x1fb) and one AEAX stands at the order's cell with EZ13 (no rally, start
## experience). The rebuild runs it at once (Read: the leader is already on its order cell). Returns the Ancient Wisp's id or -1.
func merge_group(owner: int, ids: Array) -> int:
	var leader = main.combat.fighters.get(int(ids[0])) if not ids.is_empty() else null
	if leader == null or bool(leader.get("merged", false)): return -1
	var cell: Vector2i = main.combat.unit_cell(int(leader.id))
	for id in ids:
		var u = main.unit_by_id(int(id))
		var f = main.combat.fighters.get(int(id))
		if u == null or f == null or f.removed or not main.combat.alive(f): continue
		f["merged"] = true                                     # +0x106 = 1
		remove_unit_quietly(u)
	var made: Dictionary = main.combat.spells.spawn(RacePowers.ANCIENT_WISP, cell, owner, 0, 0, {"start": true}) if main.combat.spells != null else {}
	if made.is_empty(): return -1
	if main.effects != null: main.effects.spawn_effect(RacePowers.MERGE_EFFECT, unit_pixel(made.cell), made.cell.y, true)
	return int(made.id)

## 0x4ce210 for the selection (every unit passes): the Sacrifice cell is shown for local race 8 or with PSAC.
func sacrifice_shown(selection: Array) -> bool:
	if selection.is_empty() or main.combat == null: return false
	if main.production.race_of(main.local_player) != RacePowers.SACRIFICE_RACE and main.production.research_level(main.local_player, RacePowers.SACRIFICE_RESEARCH) == 0: return false
	return selection.all(func(u): return main.combat.fighters.has(u.unit_id) and RacePowers.sacrificable(int(main.combat.fighters[u.unit_id].base.get("flags", 0)), main.is_hero_unit(u)))

func sacrifice_enabled(selection: Array) -> bool:
	return main.production.research_level(main.local_player, RacePowers.SACRIFICE_RESEARCH) != 0 and int(main.economy.resources(main.local_player)[2]) >= RacePowers.SACRIFICE_CRYSTAL * selection.size()

## 0x4ced00 (E7): 3 s between presses (stamped first), one 1d100, 5 crystal each (message 0x1fe, no stock test), the record kind
## 0x1b applied at once. Returns the record's result.
func sacrifice_selected() -> Dictionary:
	var selection: Array = main.own_selected()
	if not sacrifice_shown(selection) or not sacrifice_enabled(selection): return {}
	var now := main.game_ms()
	if main.sacrifice_ms > -100000 and now < main.sacrifice_ms + RacePowers.SACRIFICE_MS: return {}
	main.sacrifice_ms = now
	var dice: int = main.combat.rng.roll(1, 100, 0)
	main.economy.debit_clamped(main.local_player, [0, 0, RacePowers.SACRIFICE_CRYSTAL * selection.size(), 0])
	var record: Dictionary = main.combat.spells.sacrifice_record(main.local_player, selection.map(func(u): return int(u.unit_id)), dice)
	var result: Dictionary = preload("res://simulation/spell_effects.gd").apply(record, main.combat.spells)
	if not Dictionary(result.get("daemon", {})).is_empty() and main.effects != null:
		var d: Dictionary = result.daemon
		main.effects.spawn_effect(RacePowers.SACRIFICE_EFFECT, unit_pixel(d.cell), d.cell.y, true)
	main.last_message = "Sacrifice: %d units%s." % [selection.size(), ", a Daemon rises" if not Dictionary(result.get("daemon", {})).is_empty() else ""]
	return result

