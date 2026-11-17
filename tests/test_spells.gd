extends SceneTree
## Spell framework B1-4 (SPELLS_RESEARCH.md) against tests/spell_fixtures.json (tools/emulate_spells.py) and the
## dispatcher rows of tests/batch1_review_fixtures.json:
## 1. every record builder of BATCH1_RESEARCH.md 2.3 at levels 1-4 equals the original record;
## 2. the applier on the fixture scenarios: Ring of Fire's radius edges and damage through armour, the Harpy's drain,
##    Cure, Doomstones' missiles, the Naga's armour status and its expiry, summons and the command checks, Call the Dead,
##    Famine on mines;
## 3. unit mana (0x528cd0 / 0x51b580) and its regeneration; the cost 0x529fa0 and the dispatcher 0x5777a0 (payer, pool,
##    cooldown); the cast order 9 -> slot 6 -> event 7; the ability hot keys and the Dunekeep's Famine;
## 4. the real scene (main.tscn): main.gd's hook creates the framework and its key node, and an F key event reaches it.
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
const Entity = preload("res://simulation/entity_state.gd")

var checks := 0
var failures := 0
var fixtures: Dictionary = {}
var review: Dictionary = {}
var collision = CollisionData.new()
var world: Dictionary = {}
var centre := Vector2i(-1, -1)

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Spell check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/spell_fixtures.json"))
	review = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch1_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the spell world")
	if centre.x >= 0:
		tables()
		records()
		area_and_damage()
		drain_heal_missiles_status()
		summons()
		call_the_dead()
		famine()
		unit_mana()
		dispatcher()
		cast_order()
		hot_keys()
	clear_world()
	await scene_hook()
	if failures > 0:
		printerr("Spell checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Spell checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ the world
class Host extends Node:
	var test
	var local_player := 0
	var selected_building_id := -1
	var mines = null
	var economy = null
	var selection: Array = []
	func selected_units() -> Array: return selection
	func add_unit(type_id: String, cell: Vector2i, owner: int):
		return test.add_unit_node(type_id, cell, owner)

class FakeMines extends RefCounted:
	var mines: Dictionary = {}
	func owner_of(id: int) -> int: return int(mines[id].entity.owner) if mines.has(id) else -1

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

func new_world(computer: Array = []):
	clear_world()
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	for p in 2: economy.add_player(p, [5000, 5000, 5000, 5000])
	var production = Production.new(ProductionRules.new(), economy, nav)
	production.players_in_match = [0, 1]
	var units: Array = []
	var combat = Combat.new(Rng.new(0x1badb002, 0x2468ace0), nav, production, units)
	combat.auto_acquire = false
	for p in computer: combat.ai_players[p] = true
	var host := Host.new()
	host.test = self
	host.economy = economy
	host.mines = FakeMines.new()
	root.add_child(host)
	world = {"nav": nav, "production": production, "units": units, "combat": combat, "ms": 0, "host": host, "economy": economy}
	world["spells"] = Spells.new(combat, host)
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
	f.script = -1                                           # passive: no attitude script acts in these checks
	return unit

## Army.cfg STATUS of the type (catalogue.json), as main.gd status_flags.
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
	if extra.has("mana"):
		f["mana"] = int(extra.mana[0])
		f["max_mana"] = int(extra.mana[1])
		f["mana_ms"] = 0
	return id

## The command limit of `owner` set to `maximum` (production.population; the hero term stands in).
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

func fixture_case(name: String, scenario: String, level: int) -> Dictionary:
	for c in fixtures.abilities[name].cases:
		if c.scenario == scenario and int(c.level) == level: return c
	return {}

func fixture_record(name: String, scenario: String, level: int) -> Dictionary:
	for m in fixture_case(name, scenario, level).get("built", []):
		if m.message == "0x1f7": return m
	return {}

func resolved(name: String, scenario: String, level: int) -> Dictionary:
	var c := fixture_case(name, scenario, level)
	for m in c.applied[0].sent:
		if m.message == "0x1f7": return m
	return {}

static func text(s) -> String:
	return String(s).replace(char(0xFFFD), "")   # Godot 4.7 stores a NUL as U+FFFD (char(0) itself logs a Unicode error)

# ------------------------------------------------------------------------------------------------ 1. tables, records
func tables():
	var t := Spells.load_table()
	check(int(t.cost[47]) == 30 and int(t.cost[75]) == 16 and int(t.cost[79]) == 50, "cost table 0x61b3b0 (Call the Dead 30, Doomstones 16, Stonecall 50)")
	var keys := ""
	for c in [2, 4, 11, 21, 27, 28, 29, 38, 41, 42, 47]: keys += char(int(t.keys[c]))
	check(keys == "FMUIDSBSENC", "ability keys from 0x425bf0: %s" % keys)
	var built: Array = Spells.CASE_BUILDERS.keys() + Spells.HERO_CASE_BUILDERS.keys()
	check(t.cases.size() >= 15 and built.all(func(c): return t.cases.has(str(c))), "every 0x426350 case with a builder has its table row (%d rows, %d builders)" % [t.cases.size(), built.size()])

const BUILT := {"Ring of Fire": ["_ring_of_fire", "ARGX"], "Harpy 0x96": ["_harpy", "AAHA"], "Cure": ["_cure", "AAAR"],
	"Doomstones": ["_doomstones", "ADOX"], "Naga -1": ["_naga", "ALGX"], "Fire Elemental": ["_fire_elemental", "ARGX"],
	"Summon Imp": ["_summon_imp", "AADE"], "Stonecall": ["_stonecall", "ADOX"], "Vampire bats": ["_bats", "AUGX"],
	"Call the Dead": ["_call_the_dead", "AUMX"]}
const FIELDS := ["area", "radius", "b4", "b6", "sound", "b9", "b10", "b11", "b12", "kind", "w97", "amount", "w9b", "w9d", "w9f", "d89", "d131", "d135"]

func records():
	for name in BUILT:
		for level in [1, 2, 3, 4]:
			new_world()
			var caster := unit(String(BUILT[name][1]), Vector2i.ZERO, 1, {"mana": [200, 200]})
			var want := fixture_record(name, "empty", level)
			var cell: Vector2i = world.combat.unit_cell(caster)
			var got: Dictionary = world.spells.call(String(BUILT[name][0]), {"kind": "unit", "id": caster}, level, {"x": cell.x, "y": cell.y})
			check(not got.is_empty(), "%s level %d: a record" % [name, level])
			if got.is_empty(): continue
			var diff: Array = []
			for k in FIELDS:
				if int(got[k]) != int(want[k]): diff.append("%s %s != %s" % [k, got[k], want[k]])
			if text(got.effect) != text(want.effect): diff.append("effect %s != %s" % [got.effect, text(want.effect)])
			if text(got.effect2) != text(want.effect2): diff.append("effect2 %s != %s" % [got.effect2, text(want.effect2)])
			if int(got.kind) in [SpellEffects.SUMMON, SpellEffects.RAISE, SpellEffects.MISSILES] and text(got.summon) != text(want.summon):
				diff.append("summon %s != %s" % [got.summon, text(want.summon)])
			if int(got.kind) == SpellEffects.SUMMON and got.cells.size() != int(want.amount): diff.append("cells")
			check(diff.is_empty(), "%s level %d equals the original record: %s" % [name, level, diff])
	# Famine from a Dunekeep (a building caster).
	for level in [1, 2, 3, 4]:
		new_world()
		var b = world.production.add_completed(1, "BKR0", centre.x, centre.y)
		var got: Dictionary = world.spells._famine({"kind": "building", "id": b.entity_id}, level)
		var want := fixture_record("Famine", "empty", level)
		check(int(got.amount) == int(want.amount) and int(got.kind) == int(want.kind) and text(got.effect) == text(want.effect) and int(got.sound) == int(want.sound),
			"Famine level %d: kind %d, amount %d (%s)" % [level, int(got.kind), int(got.amount), want.amount])

# ------------------------------------------------------------------------------------------------ 2. the applier
const EDGE := [[0, -8], [0, 8], [-8, 0], [8, 0], [0, -6], [0, 6], [6, 0], [-6, 0], [4, 4], [5, 4], [7, 7],
	[0, -10], [0, 10], [10, 0], [-10, 0], [6, 6], [2, -9], [-5, 5]]

## The fixture's 'edges' world: enemy Liches (hp 5, mana 30 / 50) at the offsets, own Swordsmen (hp 5) one cell east.
func edges_world(caster_type: String) -> Dictionary:
	new_world()
	var caster := unit(caster_type, Vector2i.ZERO, 1, {"mana": [200, 200]})
	var enemies := {}
	var own := {}
	for o in EDGE:
		enemies[unit("AUMX", Vector2i(o[0], o[1]), 0, {"hp": 5, "mana": [30, 50]})] = Vector2i(o[0], o[1])
	for o in EDGE:
		own[unit("AHKX", Vector2i(o[0] + 1, o[1]), 1, {"hp": 5})] = Vector2i(o[0] + 1, o[1])
	return {"caster": caster, "enemies": enemies, "own": own}

func offsets_of(result: Dictionary, ids: Dictionary) -> Array:
	var out: Array = []
	for t in result.targets:
		if ids.has(int(t.id)): out.append(ids[int(t.id)])
	out.sort()
	return out

func fixture_offsets(name: String, scenario: String) -> Array:
	var c := fixture_case(name, scenario, 1)
	var r := resolved(name, scenario, 1)
	var out: Array = []
	var origin := Vector2i(40, 40)
	for i in r.target_ids.size():
		var cell := Vector2i(int(r.cells[i][0]), int(r.cells[i][1]))
		out.append(cell - origin)
	out.sort()
	return out

func area_and_damage():
	for name in ["Ring of Fire", "Harpy 0x96", "Cure", "Doomstones", "Naga -1"]:
		var w := edges_world(String(BUILT[name][1]))
		var info: Dictionary = world.spells.cast_record(String(BUILT[name][0]), {"kind": "unit", "id": w.caster}, 1)
		var got: Array = offsets_of(info.result, w.enemies) + offsets_of(info.result, w.own) + ([Vector2i.ZERO] if info.result.targets.any(func(t): return int(t.id) == w.caster) else [])
		got.sort()
		check(got == fixture_offsets(name, "edges"), "%s: the targets of the radius-edge world equal the original's (%s vs %s)" % [name, got, fixture_offsets(name, "edges")])
	# Damage through armour (0x42bbf0 mode +0x9b, type +0x9d) on targets that survive it.
	for level in [1, 4]:
		new_world()
		var caster := unit("ARGX", Vector2i.ZERO, 1)
		var ids := {}
		var types := ["AHKX", "ADLX", "AAEE", "AUIX", "AHFX"]
		for i in types.size(): ids[unit(types[i], Vector2i(i, 2), 0, {"hp": 1000})] = types[i]
		ids[unit("AUGX", Vector2i(-3, 0), 0, {"hp": 1000})] = "AUGX"
		world.spells.cast_record("_ring_of_fire", {"kind": "unit", "id": caster}, level)
		var c := fixture_case("Ring of Fire", "tough", level)
		var want := {}
		for k in c.before:
			if c.before[k].code != "BKH0": want[c.before[k].code] = int(c.before[k].hp) - int(c.after[k].hp)
		var diff: Array = []
		for id in ids:
			var lost: int = 1000 - int(world.combat.fighters[id].hp)
			if lost != int(want.get(ids[id], -1)): diff.append("%s %d != %d" % [ids[id], lost, int(want.get(ids[id], -1))])
		check(diff.is_empty(), "Ring of Fire level %d: damage through armour equals the original %s" % [level, diff])

func drain_heal_missiles_status():
	# Harpy: enemy casters drained to 0 (30 mana, amount 50); a unit without mana is skipped.
	var w := edges_world("AAHA")
	world.spells.cast_record("_harpy", {"kind": "unit", "id": w.caster}, 1)
	var drained := 0
	for id in w.enemies: if int(world.combat.fighters[id].mana) == 0: drained += 1
	check(drained == int(resolved("Harpy 0x96", "edges", 1).targets), "Harpy: every enemy in range drained to 0 (%d)" % drained)
	# Cure: own Swordsmen in range 5 -> 15 (level 1) / 40 (level 4: amount 40, max 40).
	for level in [1, 4]:
		w = edges_world("AAAR")
		world.spells.cast_record("_cure", {"kind": "unit", "id": w.caster}, level)
		var healed: Array = []
		for id in w.own: if int(world.combat.fighters[id].hp) > 5: healed.append(int(world.combat.fighters[id].hp))
		var c := fixture_case("Cure", "edges", level)
		var want: Array = []
		for k in c.after: if c.before[k].hp != c.after[k].hp: want.append(int(c.after[k].hp))
		healed.sort()
		want.sort()
		check(healed == want, "Cure level %d heals as the original %s vs %s" % [level, healed, want])
	# Doomstones: one EMC0 missile per enemy in range, damage 20 x level + 10, type 5.
	w = edges_world("ADOX")
	var before: int = world.combat.missiles.size()
	var info: Dictionary = world.spells.cast_record("_doomstones", {"kind": "unit", "id": w.caster}, 4)
	var missile_calls := 0
	for st in fixture_case("Doomstones", "edges", 4).applied:
		for call in st.get("calls", []): if call.call == "missile": missile_calls += 1
	check(world.combat.missiles.size() - before == missile_calls and info.result.missiles.all(func(m): return int(m.damage) == 90 and int(m.dtype) == 5),
		"Doomstones level 4: %d missiles of 90 (original %d)" % [world.combat.missiles.size() - before, missile_calls])
	# Naga: armour +10 (status 0x18) on allies in range for 30 s x level, then gone.
	w = edges_world("ALGX")
	var some_own: int = w.own.keys()[4]
	var armour_before := int(world.combat.combat_block(world.combat.fighters[some_own]).armour)
	world.spells.cast_record("_naga", {"kind": "unit", "id": w.caster}, 1)
	var armour_after := int(world.combat.combat_block(world.combat.fighters[some_own]).armour)
	check(armour_after == armour_before + 10, "Naga: armour +10 on an ally in range (%d -> %d)" % [armour_before, armour_after])
	run_world(30050)
	check(int(world.combat.combat_block(world.combat.fighters[some_own]).armour) == armour_before, "Naga level 1: the armour status ends after 30 s")

func summons():
	for name in ["Fire Elemental", "Summon Imp", "Stonecall", "Vampire bats"]:
		for scenario in ["empty", "command full", "command one left"]:
			new_world()
			var caster := unit(String(BUILT[name][1]), Vector2i.ZERO, 1, {"mana": [200, 200]})
			var now_used := used(1)
			match scenario:
				"empty": set_command(1, now_used + 40)
				"command full": set_command(1, now_used)
				"command one left": set_command(1, now_used + 1)
			var cell: Vector2i = world.combat.unit_cell(caster)
			var units_before: int = world.units.size()
			world.spells.cast_record(String(BUILT[name][0]), {"kind": "unit", "id": caster}, 2, {"x": cell.x, "y": cell.y})
			var made: int = world.units.size() - units_before
			var want := 0
			var c := fixture_case(name, scenario, 2)
			for st in c.get("applied", []): for m in st.sent: if m.message == "0xfa": want += 1
			check(made == want, "%s, %s: %d summoned (original %d)" % [name, scenario, made, want])
			if made > 0:
				var f = world.combat.fighters[world.units.size() - 1]
				var r := fixture_record(name, "empty", 2)
				check(int(f.owner) == 1 and int(f.xp) == int(r.w9b) and String(f.type_id) == text(r.summon), "%s: the summon is the caster's %s with %d XP" % [name, f.type_id, int(f.xp)])

func call_the_dead():
	for scenario in ["corpses", "corpses, command full"]:
		new_world()
		var caster := unit("AUMX", Vector2i.ZERO, 1, {"mana": [200, 200]})
		var corpse_ids: Array = []
		for o in [[1, 0], [3, 2], [-2, 5], [9, 9], [0, -4]]:
			var id := unit("AHKX", Vector2i(o[0], o[1]), 0)
			var f = world.combat.fighters[id]
			f.hp = 0
			f.state = "corpse"
			f.death_ms = 0
			corpse_ids.append(id)
		if scenario.ends_with("full"): set_command(1, used(1))
		var units_before: int = world.units.size()
		var info: Dictionary = world.spells.cast_record("_call_the_dead", {"kind": "unit", "id": caster}, 1)
		var want: Dictionary = fixture_record("Call the Dead", scenario, 1)
		if want.is_empty():
			check(not info.cast and world.units.size() == units_before, "Call the Dead, command full: nothing sent (0x5776c0 with one point)")
			continue
		check(world.units.size() - units_before == int(want.amount), "Call the Dead raises %d Skeletons (original %d)" % [world.units.size() - units_before, int(want.amount)])
		check(info.result.removed_corpses.size() == int(want.amount), "the corpses within the radius go (%d)" % info.result.removed_corpses.size())

func famine():
	for level in [1, 4]:
		for scenario in ["mines", "one mine"]:
			new_world()
			var dunekeep = world.production.add_completed(1, "BKR0", centre.x, centre.y)
			var specs := [["BRGO", 0, 0, 8000], ["BRCR", 0, 2, 1500], ["BRSI", 1, 3, 9000], ["BRME", 0, 1, 3000]]
			if scenario == "one mine": specs = specs.slice(0, 1)
			var ids: Array = []
			for i in specs.size():
				var s: Array = specs[i]
				var e := Entity.new(900 + i, String(s[0]), int(s[1]), Vector2(0, 0), 2)
				world.economy.register_mine(e, int(s[2]), 2, int(s[3]))
				world.host.mines.mines[900 + i] = {"entity": e, "anchor": centre + Vector2i(20 + 4 * i, 20), "code": String(s[0])}
				ids.append(900 + i)
			world.combat.rng.seed_state(12345, 678)            # the emulation's generator state (emulate_spells.SEED)
			world.spells.cast_record("_famine", {"kind": "building", "id": dunekeep.entity_id}, level)
			var c := fixture_case("Famine", scenario, level)
			var want := {}
			for k in c.before:
				if c.before[k].has("reserve") and c.before[k].reserve != c.after[k].reserve:
					want[String(c.before[k].code)] = [int(c.before[k].reserve.reduce(func(a, b): return a + b)), int(c.after[k].reserve.reduce(func(a, b): return a + b))]
			var got := {}
			for i in ids.size():
				var reserve := int(world.economy.mines[ids[i]].reserve)
				if reserve != int(specs[i][3]): got[String(specs[i][0])] = [int(specs[i][3]), reserve]
			if scenario == "one mine":
				check(got == want, "Famine level %d, one mine: %s (original %s)" % [level, got, want])
			else:
				# The pick is 0x458e70(1, n, -1) over the candidates in the players' object-list order, which is not
				# recovered (the emulation's synthetic lists run newest first): one enemy mine, drained the same way.
				var drop := func(pair): return maxi(1, int(pair[0]) - 2000 * level) == int(pair[1])
				check(got.size() == 1 and want.size() == 1 and not got.has("BRSI") and drop.call(got.values()[0]) and drop.call(want.values()[0]),
					"Famine level %d, mines: one enemy mine drained %s (original %s)" % [level, got, want])
	# The Dunekeep button: 500 crystal, at most once per second.
	new_world()
	var keep = world.production.add_completed(1, "BKR0", centre.x, centre.y)
	world.production.research[1] = ["PFA0"]
	check(world.spells.famine(keep.entity_id), "Famine button: cast with Famine I")
	check(int(world.economy.resources(1)[2]) == 4500, "Famine costs 500 crystal")
	check(not world.spells.famine(keep.entity_id), "the button waits one second")
	run_world(1050)
	check(world.spells.famine(keep.entity_id), "after a second the button works again")

# ------------------------------------------------------------------------------------------------ 3. mana and casting
func unit_mana():
	var rows := {}
	for r in fixtures.unit_mana: rows["%s %s %d %d" % [r.unit, "+".join(r.research), int(r.rank), int(r.computer)]] = r
	for code in ["ARGX", "AAHA", "AAAR", "AADE", "ADOX", "AUGX", "ALGX", "AUMX", "AUBX"]:
		for computer in [0, 1]:
			for research in [[], ["PMR0"], ["PMR0", "PMR1", "PMR2"]]:
				new_world([1] if computer else [])
				world.production.research[1] = research.duplicate()
				var id := unit(code, Vector2i.ZERO, 1)
				var f = world.combat.fighters[id]
				var want: Dictionary = rows["%s %s 0 %d" % [code, "+".join(research), computer]]
				var interval: int = world.spells.unit_mana_interval(f)
				check(int(f.get("mana", 0)) == int(want.mana) and int(f.get("max_mana", 0)) == int(want.max_mana) and interval == int(want.interval),
					"%s computer %d %s: mana %s / %s, interval %d (original %s / %s, %s)" % [code, computer, research, f.get("mana", 0), f.get("max_mana", 0), interval, want.mana, want.max_mana, want.interval])
	# Regeneration: armed on the first tick, +1 every interval while below the maximum.
	new_world()
	var liche := unit("AUMX", Vector2i.ZERO, 1)
	var f = world.combat.fighters[liche]
	var start := int(f.mana)
	run_world(3000 + 25)
	check(int(f.mana) == start + 1, "a Liche gains 1 mana per 3 s (%d -> %d)" % [start, int(f.mana)])
	f.mana = int(f.max_mana)
	f.mana_ms = 0
	run_world(9000)
	check(int(f.mana) == int(f.max_mana), "no gain above the maximum")

func dispatcher():
	for row in review.mana.dispatch_5777a0:
		new_world()
		var hero_id := unit("AUMX", Vector2i(-5, 0), 1)
		var hero = world.combat.fighters[hero_id]
		hero.hero = true
		world.combat.bind_hero(1, hero_id, null)
		hero["mana"] = 100
		var caster: Dictionary
		if row.caster == "building":
			caster = {"kind": "building", "id": world.production.add_completed(1, "BAGY", centre.x + 6, centre.y + 6).entity_id}
		else:
			var id := hero_id if String(row.caster).begins_with("hero") else unit("AUMX", Vector2i.ZERO, 1)
			caster = {"kind": "unit", "id": id}
			if row.caster == "hero_busy":
				hero["cooldown_until"] = 49000
				hero["cooldown_start"] = 1
		var result: Dictionary = world.spells.dispatch(caster, int(row.spell), int(row.level), {}, bool(row.pay))
		var cooldown := 0
		if String(row.caster).begins_with("hero") and row.caster != "hero_busy":
			cooldown = int(hero.cooldown_until) - int(hero.cooldown_start)
		var want_cooldown := int(row.cooldown_until) - int(row.cooldown_start) if row.caster == "hero" else 0
		check(int(hero.mana) == int(row.pool_after) and cooldown == want_cooldown and bool(result.cast) == (int(row.spell_called) == 1),
			"dispatch %s pay %s level %d: pool %d (%d), cooldown %d (%d), cast %s (%d)" % [row.caster, row.pay, row.level, int(hero.mana), int(row.pool_after), cooldown, want_cooldown, result.cast, int(row.spell_called)])
	# 0x529fa0 on a unit with a mana-cost status (effect 0x24): table x max(25, 100 - effect) / 100.
	new_world()
	var id := unit("AUMX", Vector2i.ZERO, 1)
	var f = world.combat.fighters[id]
	for row in review.mana.cost_529fa0:
		if bool(row.hero) or int(row.item_power24) != 0: continue
		f["statuses"] = [] if row.effect24 == null else [{"kind": 0x24, "value": int(row.effect24), "until": 1 << 40}]
		var diff: Array = []
		for spell in [47, 49, 54, 129, 3]:
			if world.spells.cost(f, spell) != int(row["spell%d" % spell][1]): diff.append(spell)
		check(diff.is_empty(), "0x529fa0 with effect 0x24 = %s: %s" % [row.effect24, diff])

func cast_order():
	new_world()
	var hero_id := unit("AHHX", Vector2i.ZERO, 1)
	var hero = world.combat.fighters[hero_id]
	hero.hero = true
	world.combat.bind_hero(1, hero_id, null)
	hero["mana"] = 100
	check(world.spells.order_cast(hero_id, Spells.CURE, 1), "order 9: the hero takes the cast order")
	run_world(25)
	check(int(hero.mana) == 100 - int(Spells.load_table().cost[Spells.CURE]) and int(hero.get("cooldown_until", 0)) != 0, "event 7 at slot 6 entry +0x18 (0): Cure paid from the pool (%d)" % int(hero.mana))
	check(int(world.units[hero_id].anim.get("slot", -1)) == 6, "the cast plays ANI slot 6")
	var until := int(hero.cooldown_until)
	check(until - int(hero.cooldown_start) == (maxi(5, 8) * 2 + (5 + 50) * 2) * 10, "Cure's cooldown (max(5, 8) x 2 + 110) x 10 ms")
	var busy: Dictionary = world.spells.dispatch({"kind": "unit", "id": hero_id}, Spells.CURE, 1)
	check(busy.get("reason", "") == "cooldown" and int(hero.mana) == 100 - 8, "a hero with a running cooldown casts nothing and pays nothing")
	run_world(until - int(world.ms) + 50)
	check(int(hero.get("cooldown_until", 0)) == 0, "the cooldown clears when due (0x51c6a0)")
	run_world(37 * 100 + 200)
	check(hero.get("cast") == null and world.units[hero_id].anim.is_empty(), "the state 6 sequence ends after the slot's frames")
	check(not world.spells.order_cast(hero_id, Spells.NAGA, 1), "a negative spell id is no cast order (0x523150 treats it as event 2)")

func hot_keys():
	new_world()
	var liche := unit("AUMX", Vector2i.ZERO, 0, {"mana": [44, 50]})
	world.host.selection = [world.units[liche]]
	for o in [[1, 0], [3, 2]]:
		var id := unit("AHKX", Vector2i(o[0], o[1]), 1)
		world.combat.fighters[id].hp = 0
		world.combat.fighters[id].state = "corpse"
	var units_before: int = world.units.size()
	check(not world.spells.hot_key(KEY_C, 0), "C with 44 mana: no Call the Dead (needs 45)")
	world.combat.fighters[liche].mana = 50
	check(world.spells.hot_key(KEY_C, 0), "C casts Call the Dead")
	check(int(world.combat.fighters[liche].mana) == 5 and world.units.size() - units_before == 2, "45 unit mana paid, two Skeletons raised")
	# S: Stonecall (case 0x1c) is tried before the Naga's case 0x26; a Runelord with 100 mana and command.
	new_world()
	var runelord := unit("ADOX", Vector2i.ZERO, 0, {"mana": [100, 100]})
	world.host.selection = [world.units[runelord]]
	set_command(0, used(0) + 10)
	units_before = world.units.size()
	check(world.spells.hot_key(KEY_S, 0) and String(world.combat.fighters[world.units.size() - 1].type_id) == "AAEE", "S: a Runelord calls an Earth Elemental")
	check(world.units.size() - units_before == 1 and int(world.combat.fighters[runelord].mana) == 0, "Stonecall pays 100")
	world.combat.fighters[runelord].mana = 40
	check(world.spells.hot_key(KEY_D, 0), "D: Doomstones with 40 mana")
	# N: Famine from a selected Dunekeep with PFAX.
	world.production.research[0] = ["PFA0", "PFA1"]
	var keep = world.production.add_completed(0, "BKR0", centre.x + 10, centre.y + 10)
	world.host.selected_building_id = keep.entity_id
	var crystal := int(world.economy.resources(0)[2])
	world.spells.hot_key(KEY_N, 0)
	check(int(world.economy.resources(0)[2]) == crystal - 500, "N: Famine from the selected Dunekeep for 500 crystal (case 0x2a then returns 0)")
	world.host.selected_building_id = -1
	world.spells.hot_key(KEY_N, 0)
	check(int(world.economy.resources(0)[2]) == crystal - 1000, "N without a selection: any own Dunekeep (0x427e30(type, 1))")

# ------------------------------------------------------------------------------------------------ 4. the scene
func scene_hook():
	var scene = load("res://battle/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.combat != null and scene.combat.spells != null, "main.gd setup_combat creates the spell framework")
	var keys = scene.get_node_or_null("SpellKeys")
	check(keys != null, "the SpellKeys node is the scene's child")
	if keys != null and scene.hud != null:
		check(keys.get_index() > scene.hud.get_parent().get_index(), "the SpellKeys node comes after the HUD layer (its _input runs first)")
	if scene.combat != null and scene.combat.spells != null and keys != null:
		var cell: Vector2i = scene.navigator.free_cell_near(Vector2i(20, 64))
		var priest = scene.add_unit("ARGX", cell, scene.local_player)
		var f = scene.combat.fighters[priest.unit_id]
		f.mana = 60
		for u in scene.units: u.selected = false
		priest.selected = true
		var event := InputEventKey.new()
		event.keycode = KEY_F
		event.pressed = true
		keys._input(event)
		check(int(f.mana) == 20, "F in the scene: the selected Scorpionpriest casts Ring of Fire (60 -> %d mana)" % int(f.mana))
	scene.free()
