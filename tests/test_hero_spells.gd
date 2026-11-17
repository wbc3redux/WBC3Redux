extends SceneTree
## Hero spells B1-6a (SPELLS_RESEARCH.md section "B1-6a") against tests/hero_spell_fixtures.json
## (tools/emulate_hero_spells.py):
## 1. every builder of Necromancy (40-49) and Runes (70-79) at levels 1-4 equals the original record cast by a hero;
## 2. the applier on the fixture worlds: Vampirism's allies and status, Strip Flesh (stripped / resisting units), Ring of
##    Ice through armour, Earthpower on buildings (the adding heal), the summons and their command checks, the timed
##    buildings, Darkstorm, Gem of Wisdom, the status consumers (armour, magic armour, life drain, missiles, build time),
##    Zombie scavenging's credit (B1-3's queued records);
## 3. the cast path 0x5717e0: the cast level and chance 0x40aae0 over every fixture row, the level roll and targeting
##    under eight seeds (the order's level and cell, the generator state), the Black Portal bonus, the placement and the
##    two dialogs, hot keys; the C1 option (modern rules "Casting");
## 4. the real scene (main.tscn): an Undead hero and a Dwarven hero cast by human input (the book, F1..F8).
## A stand-alone combat world on the Desert Sands grid; never touches user://heroes.

const ProductionRules = preload("res://simulation/production_rules.gd")
const CollisionData = preload("res://core/collision_data.gd")
const Navigation = preload("res://battle/navigation.gd")
const Economy = preload("res://simulation/economy.gd")
const Production = preload("res://simulation/production.gd")
const UnitAgent = preload("res://battle/unit_agent.gd")
const Combat = preload("res://simulation/combat.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const Spells = preload("res://simulation/spells.gd")
const SpellEffects = preload("res://simulation/spell_effects.gd")
const HeroSpells = preload("res://simulation/hero_spells.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const HeroMatch = preload("res://simulation/hero_match.gd")
const ModernRules = preload("res://simulation/modern_rules.gd")
const Placement = preload("res://simulation/placement.gd")
const Settings = preload("res://simulation/game_settings.gd")

var checks := 0
var failures := 0
var fx: Dictionary = {}
var collision = CollisionData.new()
var world: Dictionary = {}
var centre := Vector2i(-1, -1)
const OWNER := 1
const ENEMY := 0
const TARGET := Vector2i(5, 6)            # the fixture's target cell (45, 46) from the caster at (40, 40)

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Hero spell check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	fx = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_spell_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the hero spell world")
	if centre.x >= 0:
		records()
		applier()
		statuses()
		scavenging()
		chance()
		cast_path()
		dialogs_and_hotkeys()
		pending_survives()
		pause_option()
	clear_world()
	await scene_casts()
	if failures > 0:
		printerr("Hero spell checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Hero spell checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ the world
class Host extends Node:
	var test
	var local_player := 1
	var hero_unit_id := -1
	var selected_building_id := -1
	var mines = null
	var economy = null
	var day_night = null
	var treasures = null
	var visibility = null               # B1-6c: True Sight / See Invisible (tests/test_hero_spells_c.gd sets one)
	var start_cells: Dictionary = {}    # B1-6d: Home Portal's start location per player (Spells.start_cell)
	var scavenge_records: Array = []
	var selection: Array = []
	var markers: Array = []
	func selected_units() -> Array: return selection
	func add_unit(type_id: String, cell: Vector2i, owner: int):
		return test.add_unit_node(type_id, cell, owner)
	func add_marker(b): markers.append(b.entity_id)

class FakeDayNight extends RefCounted:
	var records: Array = []
	func apply_record(amount: int): records.append(amount)

class FakeTreasures extends RefCounted:
	var drops: Array = []
	func drop(item: int, cell: Vector2i, source: String = "") -> int:
		drops.append({"item": item, "cell": cell, "source": source})
		return drops.size()

func open_ground() -> Vector2i:
	for y in range(30, 110):
		for x in range(30, 100):
			var flat := true
			for dx in range(-12, 13):
				for dy in range(-12, 13):
					var c: Dictionary = collision.cell_data(Vector2i(x + dx, y + dy))
					if not c.profile_passable[0] or not c.object_indices.is_empty(): flat = false
					if not flat: break
				if not flat: break
			if flat: return Vector2i(x, y)
	return Vector2i(-1, -1)

func clear_world():
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	if world.has("host") and is_instance_valid(world.host): world.host.free()
	world = {}

func new_world():
	clear_world()
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	for p in 2: economy.add_player(p, [5000, 5000, 5000, 5000])
	var production = Production.new(ProductionRules.new(), economy, nav)
	production.players_in_match = [0, 1]
	var units: Array = []
	var combat = Combat.new(Rng.new(0x1badb002, 0x2468ace0), nav, production, units)
	combat.auto_acquire = false
	var host := Host.new()
	host.test = self
	host.economy = economy
	host.day_night = FakeDayNight.new()
	host.treasures = FakeTreasures.new()
	root.add_child(host)
	world = {"nav": nav, "production": production, "units": units, "combat": combat, "ms": 0, "host": host, "economy": economy}
	world["spells"] = Spells.new(combat, host)
	world["hs"] = world.spells.hero_spells
	set_command(0, 40)
	set_command(1, 40)

func add_unit_node(type_id: String, cell: Vector2i, owner: int):
	var unit = UnitAgent.new()
	unit.unit_id = world.units.size()
	unit.type_id = type_id
	unit.owner_id = owner
	unit.base_speed = int(world.production.rules.definition(type_id).base_speed)
	unit.navigator = world.nav
	unit.position = world.nav.center(cell)
	root.add_child(unit)
	world.units.append(unit)
	unit.sync_cell()
	var stats := CombatRules.unit_stats(world.production.rules.definition(type_id).raw_hex)
	stats["flags"] = status_bits(type_id)
	var f = world.combat.register(unit.unit_id, owner, type_id, stats, false)
	f.script = -1
	return unit

var _status: Dictionary = {}
func status_bits(type_id: String) -> int:
	if _status.is_empty():
		var cat = JSON.parse_string(FileAccess.get_file_as_string("res://assets/catalogue.json"))
		for row in cat.army_cfg.armies:
			if not _status.has(row.code): _status[row.code] = int(row.status_fields.bits)
	return int(_status.get(type_id, 0))

func unit(type_id: String, offset: Vector2i, owner: int, extra: Dictionary = {}) -> int:
	var id: int = add_unit_node(type_id, centre + offset, owner).unit_id
	world.production.register_unit(id, type_id, owner)
	var f = world.combat.fighters[id]
	if extra.has("hp"):
		f.hp = int(extra.hp)
		f.max_hp = maxi(int(f.max_hp), int(extra.hp))
		world.units[id].hp = f.hp
	if extra.has("rank"): f["rank"] = int(extra.rank)
	return id

## A hero of `owner` with the fixture's stats (S 7, D 5, I 8, C 4: radius C + 5 = 9) and school ranks {school: rank}
## (skills 10 + school), the pool 200, bound as the player's hero.
func hero(type_id: String, ranks: Dictionary, owner: int = OWNER, offset := Vector2i.ZERO, stats := [7, 5, 8, 4], extra_skills := []) -> int:
	var id := unit(type_id, offset, owner)
	var f = world.combat.fighters[id]
	f.hero = true
	var profile = Profile.create("test-hero-%d" % owner, "Test hero", 2 if type_id == "AUHX" else 1, 0)
	profile.data.stats = stats.duplicate()
	var skills: Array = []
	for school in ranks: skills.append({"id": 10 + int(school), "unlock_level": 1, "rank": int(ranks[school])})
	for s in extra_skills: skills.append(s)
	profile.data.skills = skills
	var m = HeroMatch.new()
	m.profile = profile
	world.combat.bind_hero(owner, id, m)
	f["mana"] = 200
	f["max_mana"] = 200
	f["mana_ms"] = 0
	world.host.hero_unit_id = id
	return id

func set_command(owner: int, maximum: int):
	var p = world.production
	p.hero_commands[owner] = 0
	var base: int = int(p.population(owner).maximum)
	p.hero_commands[owner] = maximum - base

func used(owner: int) -> int:
	return int(world.production.population(owner).current)

func run_world(limit_ms: int, watch: Callable = Callable()):
	var end: int = int(world.ms) + limit_ms
	while int(world.ms) < end:
		world.ms = int(world.ms) + 25
		world.combat.update(int(world.ms))
		if watch.is_valid() and watch.call(): return

static func text(s) -> String:
	return String(s).replace(char(0xFFFD), "")   # Godot 4.7 stores a NUL as U+FFFD (char(0) itself logs a Unicode error)

func cases(spell: int) -> Array:
	return fx.spells[str(spell)].cases

func fixture_case(spell: int, scenario: String, level: int, choice: int = 0) -> Dictionary:
	for c in cases(spell):
		if c.scenario == scenario and int(c.level) == level and int(c.get("choice", 0)) == choice: return c
	return {}

func record_of(c: Dictionary) -> Dictionary:
	for m in c.get("built", []):
		if m.message == "0x1f7": return m
	return {}

func resolved_of(c: Dictionary) -> Dictionary:
	for st in c.get("applied", []):
		if st.stage == "area":
			for m in st.sent:
				if m.message == "0x1f7": return m
	return {}

## The emulator's worlds (tools/emulate_hero_spells.py world_for) as [kind, code, side, offset, extra].
func fixture_world(scenario: String) -> Array:
	match scenario:
		"mixed":
			return [["unit", "AHKX", "enemy", Vector2i(2, 0), {}], ["unit", "AHKX", "enemy", Vector2i(3, 2), {"hp": 5}],
				["unit", "AHIX", "enemy", Vector2i(-2, 3), {}], ["unit", "ACSH", "enemy", Vector2i(1, -3), {}],
				["unit", "AHFX", "enemy", Vector2i(4, -1), {}], ["unit", "AUIX", "own", Vector2i(-1, 1), {"hp": 5}],
				["unit", "AUJX", "own", Vector2i(1, 2), {}], ["building", "BKH0", "enemy", Vector2i(5, -3), {}],
				["building", "BKD0", "own", Vector2i(-5, -3), {"hp": 100}], ["unit", "AHKX", "enemy", Vector2i(20, 0), {}]]
		"strip":
			return [["unit", "AHIX", "enemy", Vector2i(2, 0), {"rank": 0}], ["unit", "AHIX", "enemy", Vector2i(3, 0), {"rank": 2}],
				["unit", "AHIX", "enemy", Vector2i(4, 0), {"rank": 4}], ["unit", "AHKX", "enemy", Vector2i(2, 2), {}],
				["unit", "AHFX", "enemy", Vector2i(3, 2), {}], ["unit", "ACSH", "enemy", Vector2i(-2, 0), {}],
				["unit", "AHLX", "enemy", Vector2i(-3, 0), {}], ["unit", "ADIX", "enemy", Vector2i(0, 3), {}],
				["unit", "AUIX", "own", Vector2i(0, -2), {}], ["unit", "AHBX", "enemy", Vector2i(1, -4), {}]]
		"buildings":
			return [["building", "BKD0", "own", Vector2i(0, -9), {"hp": 50}], ["building", "BKD0", "own", Vector2i(9, 0), {"hp": 50}],
				["building", "BKD0", "own", Vector2i(0, 14), {"hp": 50}], ["building", "BKD0", "own", Vector2i(-14, 0), {"hp": 50}],
				["building", "BKD0", "own", Vector2i(-6, 6), {}], ["building", "BKH0", "enemy", Vector2i(6, -6), {"hp": 50}],
				["unit", "AUIX", "own", Vector2i(1, 0), {"hp": 5}]]
		"tough":
			var out: Array = []
			var types := ["AHKX", "ADLX", "AAEE", "AUIX", "AHFX"]
			for i in types.size(): out.append(["unit", types[i], "enemy", Vector2i(i, 2), {"hp": 1000}])
			return out
	return []

## Builds the world; returns {fixture id (str) -> object {"kind", "id", "offset"}} with the hero as id 1.
func build_world(scenario: String, hero_type: String) -> Dictionary:
	new_world()
	var ids := {"1": {"kind": "unit", "id": hero(hero_type, {}), "offset": Vector2i.ZERO}}
	var list := fixture_world(scenario)
	for i in list.size():
		var e: Array = list[i]
		var owner := OWNER if e[2] == "own" else ENEMY
		var off: Vector2i = e[3]
		if e[0] == "unit":
			ids[str(i + 2)] = {"kind": "unit", "id": unit(String(e[1]), off, owner, e[4]), "offset": off}
		else:
			ids[str(i + 2)] = {"kind": "building", "id": building(String(e[1]), off, owner, e[4]), "offset": off}
	if scenario == "command full": set_command(OWNER, used(OWNER))
	elif scenario == "command one left": set_command(OWNER, used(OWNER) + 1)
	return ids

## A finished building whose map cell (the sprite cell, the original's node +0x48 / +0x4a) is centre + offset.
func building(code: String, offset: Vector2i, owner: int, extra: Dictionary) -> int:
	var definition: Dictionary = world.production.rules.definition(code)
	var cell := centre + offset
	# add_completed's sprite cell is (left + (width - 1) / 2, top).
	var b = world.production.add_completed(owner, code, cell.x - ((int(definition.footprint[0]) - 1) >> 1), cell.y)
	if extra.has("hp"): b.hit_points = int(extra.hp)
	return int(b.entity_id)

func caster_dict(id: int) -> Dictionary:
	return {"kind": "unit", "id": id}

func hero_type(spell: int) -> String:
	return "AUHX" if spell < 70 else "ADHX"

func target_for(spell: int, choice: int = 0) -> Dictionary:
	var cell := centre + TARGET
	var t := {"x": cell.x, "y": cell.y, "id": -1, "extra": choice}
	return t

# ------------------------------------------------------------------------------------------------ 1. records
const FIELDS := ["area", "radius", "b4", "b6", "sound", "b9", "b10", "b11", "b12", "kind", "w97", "amount", "w9b", "w9d", "w9f",
	"d85", "d89", "d131", "d135"]

func builder_record(spell: int, caster: int, level: int, target: Dictionary) -> Dictionary:
	if world.hs.has_builder(spell): return world.hs.build(spell, caster_dict(caster), level, target)
	return world.spells.call(String(Spells.BUILDERS[spell]), caster_dict(caster), level, target)

func compare_record(got: Dictionary, want: Dictionary) -> Array:
	var diff: Array = []
	if got.is_empty() != want.is_empty():
		return ["record %s, original %s" % ["none" if got.is_empty() else "built", "none" if want.is_empty() else "built"]]
	if got.is_empty(): return diff
	for k in FIELDS:
		if int(got.get(k, 0)) != int(want[k]): diff.append("%s %s != %s" % [k, got.get(k, 0), want[k]])
	for k in ["effect", "effect2"]:
		if text(got[k]) != text(want[k]): diff.append("%s %s != %s" % [k, got[k], text(want[k])])
	if int(want.kind) in [SpellEffects.SUMMON, SpellEffects.BUILDING, SpellEffects.MISSILES, SpellEffects.RAISE] and text(got.summon) != text(want.summon):
		diff.append("summon %s != %s" % [got.summon, text(want.summon)])
	var descriptors: Array = got.get("descriptors", [])
	var want_d: Array = want.get("descriptors", [])
	if descriptors.size() != want_d.size(): diff.append("descriptors %s != %s" % [descriptors, want_d])
	else:
		for i in descriptors.size():
			if int(descriptors[i][0]) != int(want_d[i][0]) or int(descriptors[i][1]) != int(want_d[i][1]): diff.append("descriptor %d" % i)
	if int(want.targets) != got.get("targets", []).size(): diff.append("pre-filled targets %d != %d" % [got.get("targets", []).size(), int(want.targets)])
	# Cells: the summons' count of cells at the target, the buildings' cell, relative to the caster.
	if int(want.kind) == SpellEffects.SUMMON:
		if got.cells.size() != int(want.amount): diff.append("cells %d != %d" % [got.cells.size(), int(want.amount)])
		elif not got.cells.is_empty() and Vector2i(got.cells[0]) - centre != Vector2i(int(want.cells[0][0]), int(want.cells[0][1])) - Vector2i(40, 40):
			diff.append("cell %s" % [Vector2i(got.cells[0]) - centre])
	if int(want.kind) == SpellEffects.BUILDING:
		if got.cells.is_empty() or Vector2i(got.cells[0]) - centre != Vector2i(int(want.cell0[0]), int(want.cell0[1])) - Vector2i(40, 40): diff.append("building cell")
	return diff

func records():
	var count := 0
	for spell in [40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 70, 71, 72, 73, 74, 75, 76, 77, 79]:
		for level in [1, 2, 3, 4]:
			for choice in ([0, 1, 2, 3] if spell == 49 else [0]):
				var c := fixture_case(spell, "empty", level, choice)
				build_world("empty", hero_type(spell))
				var h: int = world.host.hero_unit_id
				var got := builder_record(spell, h, level, target_for(spell, choice))
				var diff := compare_record(got, record_of(c))
				if spell == 71: check(int(world.hs.gem.get(OWNER, 0)) == int(c.gem), "Gem of Wisdom level %d: 0x70d54c = %d (original %d)" % [level, int(world.hs.gem.get(OWNER, 0)), int(c.gem)])
				check(diff.is_empty(), "%s level %d%s equals the original record: %s" % [fx.spells[str(spell)].name, level, " choice %d" % choice if spell == 49 else "", diff])
				count += 1
	# The command checks of the summons (0x5776c0 for the summoned type): nothing with the command full.
	for spell in [40, 41, 43, 49, 79]:
		var c := fixture_case(spell, "command full", 2)
		build_world("command full", hero_type(spell))
		var got := builder_record(spell, world.host.hero_unit_id, 2, target_for(spell))
		check(got.is_empty() == record_of(c).is_empty(), "%s with the command full: %s (original %s)" % [fx.spells[str(spell)].name, "nothing" if got.is_empty() else "a record", "nothing" if record_of(c).is_empty() else "a record"])
	check(count == 88, "88 records compared (%d)" % count)

# ------------------------------------------------------------------------------------------------ 2. the applier
func offsets(list: Array, ids: Dictionary) -> Array:
	var by_id := {}
	for k in ids: by_id["%s:%d" % [ids[k].kind, int(ids[k].id)]] = ids[k].offset
	var out: Array = []
	for t in list:
		var key := "%s:%d" % [t.kind, int(t.id)]
		if by_id.has(key): out.append(by_id[key])
	out.sort()
	return out

func fixture_offsets(target_ids: Array, ids: Dictionary) -> Array:
	var out: Array = []
	for t in target_ids:
		if ids.has(str(int(t))): out.append(ids[str(int(t))].offset)
	out.sort()
	return out

func cast_in(scenario: String, spell: int, level: int, choice: int = 0) -> Dictionary:
	var ids := build_world(scenario, hero_type(spell))
	var h: int = world.host.hero_unit_id
	var record := builder_record(spell, h, level, target_for(spell, choice))
	var info: Dictionary = world.spells.cast_built(record, caster_dict(h), level, spell)
	return {"ids": ids, "info": info, "hero": h}

func applier():
	# Vampirism, mixed: the hero and the two own units (STATUS 0x44000 excluded), each with effect 0x3c = level + 1.
	for level in [1, 3]:
		var r := cast_in("mixed", 44, level)
		var c := fixture_case(44, "mixed", level)
		check(offsets(r.info.result.targets, r.ids) == fixture_offsets(resolved_of(c).target_ids, r.ids), "Vampirism level %d: the original's targets %s" % [level, offsets(r.info.result.targets, r.ids)])
		var want := 0
		for k in c.after: if c.after[k].has("effects"): want += 1
		var got := 0
		for t in r.info.result.targets:
			if world.spells.status_value(world.combat.fighters[int(t.id)], 0x3c) == level + 1: got += 1
		check(got == want, "Vampirism level %d: %d units carry effect 0x3c = %d (original %d)" % [level, got, level + 1, want])
	# Strip Flesh: the units below level + 1 become their owner's Skeletons, the others resist (0x222).
	for level in [1, 4]:
		var r := cast_in("strip", 46, level)
		var c := fixture_case(46, "strip", level)
		var stripped: Array = []
		var resisted: Array = []
		for st in c.applied:
			for m in st.sent:
				if m.message == "0x1fb": stripped.append(int(m.target))
				elif m.message == "0x222": resisted.append(int(m.target))
		var got_stripped: Array = []
		for s in r.info.result.stripped: got_stripped.append({"kind": "unit", "id": int(s.from)})
		var got_resisted: Array = []
		for id in r.info.result.resisted: got_resisted.append({"kind": "unit", "id": int(id)})
		check(offsets(got_stripped, r.ids) == fixture_offsets(stripped, r.ids), "Strip Flesh level %d: stripped %s (original %s)" % [level, offsets(got_stripped, r.ids), fixture_offsets(stripped, r.ids)])
		check(offsets(got_resisted, r.ids) == fixture_offsets(resisted, r.ids), "Strip Flesh level %d: resisted %s (original %s)" % [level, offsets(got_resisted, r.ids), fixture_offsets(resisted, r.ids)])
		check(r.info.result.stripped.all(func(s): return String(s.type) == "AUIX" and int(s.owner) == ENEMY), "Strip Flesh: each new Skeleton belongs to the stripped unit's owner")
		check(r.info.result.stripped.all(func(s): return bool(world.combat.fighters[int(s.from)].removed)), "Strip Flesh: the stripped units leave no remains")
	# Ring of Ice through armour (mode 2, type 1).
	for level in [1, 4]:
		var r := cast_in("tough", 48, level)
		var c := fixture_case(48, "tough", level)
		var diff: Array = []
		for k in r.ids:
			if k == "1" or r.ids[k].kind != "unit": continue
			var lost: int = 1000 - int(world.combat.fighters[int(r.ids[k].id)].hp)
			var want: int = int(c.before[k].hp) - int(c.after[k].hp)
			if lost != want: diff.append("%s %d != %d" % [c.before[k].code, lost, want])
		check(diff.is_empty(), "Ring of Ice level %d: damage through armour equals the original %s" % [level, diff])
	# Earthpower on own hurt buildings in vtable +0x64(level - 1): the building's 0x52e0b0 adds the stored heal.
	for level in [1, 2, 3]:
		var r := cast_in("buildings", 73, level)
		var c := fixture_case(73, "buildings", level)
		var diff: Array = []
		for k in r.ids:
			if r.ids[k].kind != "building": continue
			var b = world.production.building(int(r.ids[k].id))
			if int(b.hit_points) != int(c.after[k].hp): diff.append("%s %d != %d" % [r.ids[k].offset, int(b.hit_points), int(c.after[k].hp)])
		check(diff.is_empty(), "Earthpower level %d: building hit points equal the original's %s" % [level, diff])
	# Summons: counts, owners, experience.
	for spell in [40, 41, 43, 49, 79]:
		var r := cast_in("empty", spell, 2)
		var want := 0
		for st in fixture_case(spell, "empty", 2).applied:
			for m in st.sent: if m.message == "0xfa": want += 1
		check(r.info.result.summoned.size() == want, "%s level 2: %d summoned (original %d)" % [fx.spells[str(spell)].name, r.info.result.summoned.size(), want])
	# Timed buildings: Black Portal and Summon Guardian at the placement cell, gone after the duration (0x52cd77).
	for spell in [42, 76]:
		for level in [1, 3]:
			var r := cast_in("empty", spell, level)
			var c := fixture_case(spell, "empty", level)
			var want: Dictionary = {}
			for st in c.applied:
				for m in st.sent: if m.message == "0x1f9": want = m
			var made: Array = r.info.result.buildings
			check(made.size() == 1 and not want.is_empty() and String(made[0].type) == text(want.type) and Vector2i(made[0].cell) - centre == Vector2i(int(want.cell[0]), int(want.cell[1])) - Vector2i(40, 40),
				"%s level %d: a %s at the cell (original %s)" % [fx.spells[str(spell)].name, level, made[0].type if not made.is_empty() else "-", text(want.get("type", ""))])
			if made.is_empty(): continue
			var b = world.production.building(int(made[0].id))
			check(b != null and int(b.owner) == OWNER and not b.constructing and int(b.hit_points) == int(b.max_hit_points), "the building is finished and the caster's")
			check(int(made[0].until) - int(world.combat.now_ms) == int(want.duration), "lifetime %d ms (original %d)" % [int(made[0].until) - int(world.combat.now_ms), int(want.duration)])
			run_world(int(want.duration) + 100)
			var after = world.production.building(int(made[0].id))
			check(after == null or int(after.hit_points) <= 0, "%s level %d: removed once its time passed" % [fx.spells[str(spell)].name, level])
	# Darkstorm: kind 4 amount 3 to B1-3's day / night.
	var d := cast_in("empty", 45, 1)
	check(world.host.day_night.records == [3], "Darkstorm: DayNight.apply_record(3) (dusk and rain) %s" % [world.host.day_night.records])

# ------------------------------------------------------------------------------------------------ status consumers
func statuses():
	# Stoneskin: armour + 10 (0x5260a0 effect 0x18) for 60 s x level, look 6; Resist Magic: the armour table's word 4.
	var r := cast_in("empty", 70, 1)
	var f = world.combat.fighters[r.hero]
	check(world.spells.status_value(f, 0x18) == 10 and int(f.get("look", {}).get("state", -1)) == 6, "Stoneskin: effect 0x18 = 10 and look 6 on the caster")
	r = cast_in("empty", 74, 2)
	f = world.combat.fighters[r.hero]
	var block: Dictionary = world.combat.combat_block(f)
	world.spells.combat.fighters[r.hero].statuses = []
	var plain: Dictionary = world.combat.combat_block(f)
	check(int(CombatRules.armour_table(block)[4]) - int(CombatRules.armour_table(plain)[4]) == 50, "Resist Magic level 2: magic armour (word 4) + 50 (0x525c80 effect 0x51)")
	# Resist Missile: a hero's missile damage / 16 (0x527040 / 0x5427e0).
	r = cast_in("empty", 77, 1)
	f = world.combat.fighters[r.hero]
	check(world.spells.missile_resisted({"dtype": 0}, f, 40) == 2 and world.spells.missile_resisted({"dtype": 0}, f, 8) == 1 and world.spells.missile_resisted({"dtype": 3}, f, 40) == 40,
		"Resist Missile: piercing missiles 40 -> 2, 8 -> 1; fire untouched")
	# Vampirism: the drain term 0x526f40 (effect 0x3c) heals the attacker.
	r = cast_in("mixed", 44, 2)
	var skeleton: int = int(r.ids["7"].id)
	var sf = world.combat.fighters[skeleton]
	check(world.spells.drain_terms(sf) == 3, "Vampirism level 2: the Skeleton drains 3 (effect 0x3c)")
	var victim: int = int(r.ids["2"].id)
	sf.hp = 1
	world.combat._drain(sf, world.combat.fighters[victim])
	check(int(sf.hp) == 4, "a hit heals the drain (1 -> %d)" % int(sf.hp))
	# Dig: the hero's effect 0x3f shortens building time (0x40b6b0 via production.hero_build_skill).
	r = cast_in("empty", 72, 1)
	var before: int = world.production.time_of(OWNER, "BKD1")
	world.combat.update(25)
	check(int(world.production.hero_build_skill.get(OWNER, 0)) == 20, "Dig level 1: hero_build_skill 20 while the effect lasts")
	var after: int = world.production.time_of(OWNER, "BKD1")
	check(after < before or before == 0, "Dig: building time %d -> %d" % [before, after])

func scavenging():
	# B1-3's queued records through the applier (kind 0x1c): gold credited, the remains within 7 removed.
	for row in fx.scavenge:
		if row.layout == "none" or row.seed[0] != 12345: continue
		new_world()
		var zombie := unit("AUBX", Vector2i.ZERO, OWNER)
		var corpse_ids := {}
		for o in row.corpses:
			var id := unit("AHKX", Vector2i(int(o[0]), int(o[1])), ENEMY)
			var f = world.combat.fighters[id]
			f.hp = 0
			f.state = "corpse"
			f.death_ms = 0
			corpse_ids[id] = Vector2i(int(o[0]), int(o[1]))
		var rec := {}
		for m in row.built: if m.message == "0x1f7": rec = m
		world.economy.stockpiles[OWNER] = [100, 100, 100, 100]        # under the capacity (0x43e9b0 caps as credit does)
		var gold_before: int = int(world.economy.resources(OWNER)[0])
		world.host.scavenge_records.append({"kind": 0x1c, "effect": "EZ44", "owner": OWNER, "unit": zombie, "amounts": [int(rec.w9b), 0, 0, 0], "remains": row.corpses.size()})
		world.combat.update(25)
		check(world.host.scavenge_records.is_empty() and int(world.economy.resources(OWNER)[0]) - gold_before == int(row.stock[0]) - 100,
			"scavenging (%s): %d gold credited (original %d)" % [row.layout, int(world.economy.resources(OWNER)[0]) - gold_before, int(row.stock[0]) - 100])
		var gone: Array = []
		for id in corpse_ids:
			var f = world.combat.fighters[id]
			if int(world.combat.now_ms) - int(f.death_ms) >= world.combat.corpse_ms(String(f.type_id)): gone.append(corpse_ids[id])
		gone.sort()
		var want: Array = []
		for o in row.removed: want.append(Vector2i(int(o[0]), int(o[1])))
		want.sort()
		check(gone == want, "scavenging (%s): the remains removed %s (original %s)" % [row.layout, gone, want])

# ------------------------------------------------------------------------------------------------ 3. the cast path
func chance():
	var diff := 0
	var first := ""
	var built := ""
	for row in fx.chance:
		var v: Dictionary = row.variant
		if JSON.stringify(v) != built:                     # one world per variant
			built = JSON.stringify(v)
			new_world()
			var stats := [7, 5, int(v.get("intelligence", 8)), 4]
			var extra: Array = [{"id": 7, "unlock_level": 1, "rank": int(v.ritual)}] if v.has("ritual") else []
			if not v.has("no_hero"):
				var h := hero("AUHX", {}, OWNER, Vector2i.ZERO, stats, extra)
				if v.has("dead"):
					world.combat.fighters[h].hp = 0
			if v.has("computer"): world.combat.ai_players[OWNER] = true
			if v.has("gem"): world.hs.gem[OWNER] = int(v.gem)
			world.spells.cheat = v.has("cheat")
		var got: Dictionary = world.hs.cast_level(OWNER, int(row.rank), int(row.spell))
		var ok := bool(got.ok) == (int(row.known) != 0) and int(got.level) == int(row.level) and int(got.chance) == int(row.chance)
		if not ok:
			diff += 1
			if first == "": first = "%s rank %d spell %d: %s vs %s" % [v, int(row.rank), int(row.spell), got, row]
	check(diff == 0, "0x40aae0: %d rows equal the original (%d differ; %s)" % [fx.chance.size() - diff, diff, first])

func cast_path():
	var diff: Array = []
	var compared := 0
	for row in fx.cast_path:
		var spell := int(row.spell)
		var ids := build_world(String(row.scenario) if row.scenario in ["command full"] else "empty", hero_type(spell))
		var h: int = world.host.hero_unit_id
		var school := spell / 10
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 10 + school, "unlock_level": 1, "rank": int(row.rank)}]
		world.combat.fighters[h].mana = int(row.pool)
		if row.scenario == "portal":
			building("BMBP", Vector2i(3, 3), OWNER, {})
		world.combat.rng.seed_state(int(row.seed[0]), int(row.seed[1]))
		var result: Dictionary = world.hs.cast_request(h, spell)
		var sent: Dictionary = {}
		for m in row.sent: if m.message == "0x118": sent = m
		var label := "%s %d (%s, seed %s)" % [row.label, spell, row.scenario, row.seed[0]]
		var f = world.combat.fighters[h]
		var rng: Array = [world.combat.rng.first, world.combat.rng.second]
		var want_rng: Array = [int(row.rng_after[0]), int(row.rng_after[1])]
		if row.scenario == "portal":
			# The portal's cell is stamped in the rebuild (free_cell_near moves off it); the level bonus and the draws count.
			var ok_portal: bool = f.get("cast") != null and int(f.cast.level) == int(sent.level) and rng == want_rng
			if not ok_portal: diff.append(label)
			compared += 1
			continue
		if not sent.is_empty():
			var c = f.get("cast")
			var ok: bool = c != null and int(c.level) == int(sent.level) and rng == want_rng
			if ok and int(sent.target[3]) != 0:
				var cell: Vector2i = Vector2i(int(c.target.x), int(c.target.y)) - world.combat.unit_cell(h)
				ok = cell == Vector2i(int(sent.target[3]), int(sent.target[4])) - Vector2i(40, 40)
			if not ok: diff.append("%s: order %s (original level %d, %s)" % [label, c, int(sent.level), sent.target])
		elif row.pending != null:
			var p: Dictionary = world.hs.pending
			var mode: String = {7: "place", 11: "champion", 13: "rune"}.get(int(row.pending.target[0]) if int(row.pending.target[0]) >= 0 else (11 if spell == 49 else 13), "")
			if int(row.pending.target[0]) == 8: mode = ""         # mode 8 left the pending block behind but sent nothing (command full)
			var ok: bool = rng == want_rng and (mode == "" or (String(p.get("mode", "")) == mode and int(p.level) == int(row.pending.level)))
			if mode == "" and bool(result.get("cast", false)): ok = false
			if not ok: diff.append("%s: pending %s (original %s)" % [label, p, row.pending])
		else:
			if bool(result.get("cast", false)) or f.get("cast") != null or rng != want_rng: diff.append("%s: cast %s (original: nothing)" % [label, result])
		compared += 1
	check(diff.is_empty(), "0x5717e0: %d of %d cast-path cases equal the original %s" % [compared - diff.size(), compared, diff.slice(0, 4)])
	# The order goes through order 9 and the dispatcher: Stoneskin applied at the event, the pool paid, Gem cleared.
	build_world("empty", "ADHX")
	var h: int = world.host.hero_unit_id
	world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 17, "unlock_level": 1, "rank": 15}]
	world.hs.gem[OWNER] = 30
	world.combat.rng.seed_state(12345, 678)
	world.hs.cast_request(h, 70)
	run_world(3000, func(): return world.combat.fighters[h].get("cast") == null)
	var f = world.combat.fighters[h]
	check(world.spells.status_value(f, 0x18) == 10 and int(f.mana) == 200 - int(world.spells.cost(f, 70)) and int(world.hs.gem.get(OWNER, 0)) == 0,
		"order 9 -> event 7 -> 0x5777a0: Stoneskin on the hero, %d mana paid, the Gem bonus cleared" % (200 - int(f.mana)))

## B1-7 (REVIEW_AI_SPELLS.md R1, the deliberate fix F11): a computer hero's cast leaves the local player's open placement
## alone, a mode-0 spell (Ring of Ice 48) and a mode-8 summon (Raise Wight 43); the placement then completes for the
## local hero. Another local request still replaces it.
func pending_survives():
	build_world("empty", "AUHX")
	world.production.local_player = OWNER
	var h: int = world.host.hero_unit_id
	world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 14, "unlock_level": 1, "rank": 15}]
	var computer := hero("AUHX", {4: 15}, ENEMY, Vector2i(12, 0))
	world.host.hero_unit_id = h
	check(String(world.hs.cast_request(h, 42).get("pending", "")) == "place", "the local placement waits")
	var before: Dictionary = world.hs.pending.duplicate()
	for spell in [48, 43]:
		var r: Dictionary = world.hs.cast_request(computer, spell)
		check(bool(r.get("cast", false)), "the computer hero's spell %d is ordered (%s)" % [spell, r])
		check(world.hs.pending == before, "the computer hero's spell %d leaves the local placement alone" % spell)
	var placed: Dictionary = world.hs.place(centre + Vector2i(5, 3))
	check(bool(placed.get("cast", false)) and int(placed.get("spell", -1)) == 42, "the placement completes with the local hero's spell (%s)" % placed)
	world.production.local_player = 0

func dialogs_and_hotkeys():
	# Black Portal: the placement waits; a click inside the radius orders the cast, outside is refused.
	build_world("empty", "AUHX")
	var h: int = world.host.hero_unit_id
	world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 14, "unlock_level": 1, "rank": 15}]
	world.combat.rng.seed_state(12345, 678)
	var r: Dictionary = world.hs.cast_request(h, 42)
	check(String(r.get("pending", "")) == "place" and String(world.hs.pending.type) == "BMBP" and int(world.hs.pending.radius) == 9, "Black Portal: placement of a BMBP within 9 (0x425150 mode 9)")
	check(not bool(world.hs.place(centre + Vector2i(15, 0)).get("cast", false)) and not world.hs.pending.is_empty(), "a click 15 cells away is refused")
	var placed: Dictionary = world.hs.place(centre + Vector2i(5, 3))
	check(bool(placed.get("cast", false)) and world.hs.pending.is_empty(), "a click 5 cells away orders the cast")
	run_world(3000, func(): return world.combat.fighters[h].get("cast") == null)
	var portal := false
	for id in world.production.buildings: if String(world.production.buildings[id].original_type_id) == "BMBP": portal = true
	check(portal, "the Black Portal stands after the cast")
	# Raise Skeleton next to the portal: + 1 level.
	world.combat.rng.seed_state(12345, 678)
	world.combat.fighters[h].cooldown_until = 0
	world.hs.cast_request(h, 40)
	check(world.combat.fighters[h].get("cast") != null and int(world.combat.fighters[h].cast.level) == 3, "Raise Skeleton near the Black Portal: level 2 + 1 (0x570f80)")
	# Raise Champion: the four champions; the pick goes to the target's +0xc.
	build_world("empty", "AUHX")
	h = world.host.hero_unit_id
	world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 14, "unlock_level": 1, "rank": 25}]
	world.combat.rng.seed_state(12345, 678)
	r = world.hs.cast_request(h, 49)
	check(String(r.get("pending", "")) == "champion" and world.hs.pending.choices == HeroSpells.CHAMPIONS, "Raise Champion opens the champion dialog (AUXX AUMX AUGX AUAX)")
	world.hs.choose(1)
	run_world(3000, func(): return world.combat.fighters[h].get("cast") == null)
	var liche := false
	for f in world.combat.fighters.values(): if String(f.type_id) == "AUMX" and int(f.owner) == OWNER: liche = true
	check(liche, "the pick 1 raises a Liche")
	# Rune Item: the four items of the level; the pick is dropped at the hero.
	for row in fx.rune_item:
		if int(row.choice) != 0: continue
		check(HeroSpells.rune_items(int(row.level)) == row.items.map(func(v): return int(v)), "Rune Item level %d: items %s (original %s)" % [int(row.level), HeroSpells.rune_items(int(row.level)), row.items])
	build_world("empty", "ADHX")
	h = world.host.hero_unit_id
	world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 17, "unlock_level": 1, "rank": 29}]
	world.combat.rng.seed_state(12345, 678)
	r = world.hs.cast_request(h, 78)
	check(String(r.get("pending", "")) == "rune" and world.hs.pending.choices.size() == 4, "Rune Item opens the item dialog")
	var rolled := int(world.hs.pending.level)
	world.hs.choose(3)
	run_world(3000, func(): return world.combat.fighters[h].get("cast") == null)
	var drops: Array = world.host.treasures.drops
	check(rolled < 1 or (drops.size() == 1 and int(drops[0].item) == HeroSpells.rune_items(rolled)[3] and Vector2i(drops[0].cell) == world.combat.unit_cell(h)),
		"Rune Item at the rolled level %d, pick 3: %s dropped at the hero" % [rolled, drops])
	# Hot keys: F1..F8 slots, a spell in one slot at a time, written to the profile.
	world.hs.assign_hotkey(OWNER, 0, 70)
	world.hs.assign_hotkey(OWNER, 2, 70)
	var slots: Array = world.hs.hotkey_slots(OWNER)
	check(int(slots[0]) == -1 and int(slots[2]) == 70 and world.combat.heroes[OWNER].match.profile.data.spell_hotkeys == slots, "0x4258a0: the spell moves to slot 3 and the profile keeps the slots")
	world.combat.fighters[h].cooldown_until = 0
	world.combat.rng.seed_state(12345, 678)
	var hk: Dictionary = world.hs.hotkey(OWNER, 2, h, OWNER)
	check(bool(hk.get("cast", false)), "F3 casts the slot's Stoneskin")
	check(not bool(world.hs.hotkey(OWNER, 5, h, OWNER).get("cast", false)), "an empty slot casts nothing")

func pause_option():
	for keep in [false, true]:
		build_world("empty", "AUHX")
		var h: int = world.host.hero_unit_id
		world.combat.heroes[OWNER].match.profile.data.skills = [{"id": 14, "unlock_level": 1, "rank": 15}]
		world.combat.rng.seed_state(12345, 678)
		world.hs.cast_request(h, 42)
		world.spells.pause_changed(true, keep)
		check(world.hs.pending.is_empty() != keep, "C1 %s: a pause %s the pending placement" % ["on" if keep else "off", "keeps" if keep else "drops"])
	var saved := ModernRules.snapshot()
	ModernRules.choose("BattleRules", true)
	check(ModernRules.casting(), "Battle Rules: Improved turns Casting on")
	ModernRules.restore(saved)
	check(not ModernRules.DEFAULTS.Casting, "Casting is off by default (the original rules)")

# ------------------------------------------------------------------------------------------------ 4. the real scene
func scene_casts():
	Settings.use_file("user://hero-spells-test-settings.cfg")   # the HUD's settings on a copy (never the user's)
	root.size = Vector2i(1920, 1080)
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	scene.enable_normal_play()
	await process_frame
	var ok: bool = scene.combat != null and scene.combat.spells != null and scene.combat.spells.hero_spells != null
	check(ok, "main.gd's spell framework carries the hero spells")
	if not ok:
		scene.free()
		return
	var hs = scene.combat.spells.hero_spells
	var keys = scene.get_node_or_null("SpellKeys")
	# An Undead hero (Necromancy rank 40) and a Dwarven hero (Runes rank 40) of the local player in turn: every spell of
	# the two schools by human input (the book's row; the placement click; the dialog pick), then the order's dispatch.
	var cast_ok := 0
	var tried := 0
	var f = null
	var hero_id := -1
	var profile = null
	for school in [4, 7]:
		var hero_type := "AUHX" if school == 4 else "ADHX"
		var cell: Vector2i = scene.navigator.free_cell_near(Vector2i(24 if school == 4 else 30, 60))
		var unit = scene.add_unit(hero_type, cell, scene.local_player)
		hero_id = unit.unit_id
		f = scene.combat.fighters[hero_id]
		f.hero = true
		f["max_mana"] = 500
		f["mana_ms"] = 0
		profile = Profile.create("scene-hero-%d" % school, "Scene hero", 2 if school == 4 else 1, 0)
		profile.data.skills = [{"id": 10 + school, "unlock_level": 1, "rank": 40}]
		var m = HeroMatch.new()
		m.profile = profile
		scene.combat.bind_hero(scene.local_player, hero_id, m)
		scene.hero_unit_id = hero_id
		scene.production.hero_commands[scene.local_player] = 40     # command room for the summons (no Keep in the fixture scene)
		check(scene.hud.hero_knows_spells(), "the HUD sees the %s hero's school" % hero_type)
		for k in 10:
			var spell: int = school * 10 + k
			if spell == 47: continue                          # Call the Dead needs remains (records() covers its builder)
			f.mana = 500
			f.cooldown_until = 0
			f.cast = null
			scene.combat.rng.seed_state(0x9e3779b9, 0x7f4a7c15)
			hs.cancel_pending()
			scene.hud.spell_school = school
			scene.hud.open_dialog("spellbook")
			var row_y: float = 100 + 0x17 * k + 5
			var local := Vector2(0x40, row_y)
			check(scene.hud.spell_row_enabled(spell), "%s is enabled in the book" % scene.hud.spell_text(spell).name)
			scene.hud.spellbook_press(local)
			tried += 1
			if String(hs.pending.get("mode", "")) == "place":
				for d in [Vector2i(4, 0), Vector2i(-4, 0), Vector2i(0, 4), Vector2i(0, -4), Vector2i(3, 3)]:
					if hs.place(scene.combat.unit_cell(hero_id) + d).get("cast", false): break
			elif scene.hud.dialog == "spell_choice":
				scene.hud.choose_spell_option(0)
			var paid_before: int = int(f.mana)
			for i in 200:
				if f.get("cast") == null: break
				scene.combat.update(int(scene.combat.now_ms) + 25)
			if int(f.mana) < paid_before or f.get("cast") == null and int(f.mana) < 500: cast_ok += 1
			else: printerr("not cast: ", spell, " pending ", hs.pending, " dialog ", scene.hud.dialog)
			scene.hud.close_dialog()
	check(cast_ok == tried, "the scene's hero cast %d of %d Necromancy and Runes spells from the book" % [cast_ok, tried])
	# F1 with a hot key slot: Stoneskin by the key.
	profile.data.skills = [{"id": 17, "unlock_level": 1, "rank": 40}]
	hs.assign_hotkey(scene.local_player, 0, 70)
	f.mana = 500
	f.cooldown_until = 0
	f.cast = null
	if f.has("statuses"): f.statuses = []
	var event := InputEventKey.new()
	event.keycode = KEY_F1
	event.pressed = true
	keys._input(event)
	for i in 200:
		if f.get("cast") == null: break
		scene.combat.update(int(scene.combat.now_ms) + 25)
	check(scene.combat.spells.status_value(f, 0x18) == 10, "F1 in the scene: the hero's Stoneskin by its hot key")
	# REVIEW_HERO_SPELLS D1: a hot key opens the dialog / placement as the book does (0x5717e0 opens them itself).
	hs.assign_hotkey(scene.local_player, 1, 78)
	f.cooldown_until = 0
	f.cast = null
	scene.hud.close_dialog()
	var f2 := InputEventKey.new()
	f2.keycode = KEY_F2
	f2.pressed = true
	keys._input(f2)
	check(scene.hud.dialog == "spell_choice" and String(hs.pending.get("mode", "")) == "rune", "F2 with Rune Item opens the item dialog")
	scene.hud.choose_spell_option(-1)
	scene.free()
