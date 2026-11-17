extends SceneTree
## G-4 (COMBAT_RESEARCH.md "G-4"): the critical-hit side effects (simulation/criticals.gd).
## 1. Fixtures (tools/emulate_criticals.py, the unmodified executable under Unicorn): the art kinds of 0x53f180, the
##    messages of the melee hit 0x51abe0 per effect, the handlers 0x527b30 / 0x527d10 / 0x527a00 / 0x527ed0 / 0x527ff0
##    (status entries, look, mana, the hero pool, experience, +0x20c), Cleave's record (0x5278a0) and the armour word of
##    0x5260a0 with +0x20c; B3-1's "missile_kinds" (0x523150) against Criticals.missile_kind.
## 2. A small combat world: each effect through the melee blow and the missile impact, the floated presentation events,
##    Ignore Armor's raw damage, Cleave's ring, Crystallize, Assassinate's gold, the draws of 0x523150.
## 3. The effects layer draws the extras of a floated event (art, bursts, the 1 s sound stamp).

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
const Criticals = preload("res://simulation/criticals.gd")
const Missiles = preload("res://simulation/missiles.gd")
const EffectsLayer = preload("res://visuals/effects_layer.gd")

var checks := 0
var failures := 0
var fx = null

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Critical check failed: ", label)

func _initialize():
	call_deferred("run")

func run():
	var f = JSON.parse_string(FileAccess.get_file_as_string("res://tests/criticals_fixtures.json"))
	check(f is Dictionary, "tests/criticals_fixtures.json (tools/emulate_criticals.py)")
	if f is Dictionary:
		art_kinds(f)
		melee_messages(f)
		handlers(f)
		cleave_record(f)
		armour_words(f)
	missile_kinds()
	draws()
	world_checks()
	layer_checks()
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	if world.has("host") and is_instance_valid(world.host): world.host.free()
	if failures > 0:
		printerr("Critical checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Critical checks passed: %d" % checks)
	quit(0)

# ------------------------------------------------------------------------------------------------ world helpers
var world: Dictionary = {}
var collision = CollisionData.new()
var floats: Array = []
var open := Vector2i(-1, -1)

func open_ground() -> Vector2i:
	for y in range(30, 110):
		for x in range(30, 100):
			var flat := true
			for dx in range(-6, 7):
				for dy in range(-4, 5):
					var c: Dictionary = collision.cell_data(Vector2i(x + dx, y + dy))
					if not c.profile_passable[0] or not c.object_indices.is_empty() or int(c.raw[0]) != int(collision.cell_data(Vector2i(x, y)).raw[0]): flat = false
			if flat: return Vector2i(x, y)
	return Vector2i(-1, -1)

class Host extends Node:
	var test
	var local_player := 0
	var selected_building_id := -1
	var economy = null
	var selection: Array = []
	func selected_units() -> Array: return selection
	func add_unit(type_id: String, cell: Vector2i, owner: int):
		return test.add_unit_node(type_id, cell, owner)

class FakeProfile extends RefCounted:
	var data := {"xp": 0}

class FakeMatch extends RefCounted:
	var computer := false
	var profile = FakeProfile.new()
	func block(_a = null, _b = null, _c = null) -> Dictionary: return {}

func new_world():
	for u in world.get("units", []):
		if is_instance_valid(u): u.free()
	if world.has("host") and is_instance_valid(world.host): world.host.free()
	var nav = Navigation.new(collision)
	var economy = Economy.new(0)
	economy.add_player(0, [500, 500, 500, 500])
	economy.add_player(1, [500, 500, 500, 500])
	var production = Production.new(ProductionRules.new(), economy, nav)
	production.players_in_match = [0, 1]
	var units: Array = []
	var combat = Combat.new(Rng.new(0x1badb002, 0x2468ace0), nav, production, units)
	combat.auto_acquire = false
	var host := Host.new()
	host.test = self
	host.economy = economy
	root.add_child(host)
	world = {"nav": nav, "production": production, "units": units, "combat": combat, "economy": economy, "host": host}
	world["spells"] = Spells.new(combat, host)
	for owner in 2: production.hero_commands[owner] = 40 - int(production.population(owner).maximum)
	combat.now_ms = 50000
	floats = []
	combat.spells.floated.connect(func(info): floats.append(info))

func add_unit_node(type_id: String, cell: Vector2i, owner: int):
	var id := add_world_unit(type_id, cell, owner)
	return world.units[id]

func add_world_unit(type_id: String, cell: Vector2i, owner: int) -> int:
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
	world.combat.register(unit.unit_id, owner, type_id, CombatRules.unit_stats(world.production.rules.definition(type_id).raw_hex), false)
	world.combat.fighters[unit.unit_id].script = -1
	return unit.unit_id

func fighter(id: int):
	return world.combat.fighters[id]

func statuses_of(t) -> Array:
	var out: Array = []
	for s in t.get("statuses", []): out.append([int(s.kind), int(s.value), int(s.until), int(s.get("art", -1))])
	out.sort()
	return out

func lines() -> Array:
	return floats.map(func(i): return int(i.get("line", -1)))

# ------------------------------------------------------------------------------------------------ 1. fixtures
func art_kinds(f: Dictionary):
	var same := 0
	for row in f.art_kinds:
		if Criticals.art_kind(String(row.art)) == [int(row.kind), int(row.level)]: same += 1
		else: check(false, "0x53f180 %s: kind %d level %d, port %s" % [row.art, row.kind, row.level, Criticals.art_kind(String(row.art))])
	check(same == f.art_kinds.size() and same >= 32, "0x53f180: the art kinds of %d missile codes equal the executable's" % same)

func melee_messages(f: Dictionary):
	var same := 0
	for row in f.hits:
		var effect := int(row.effect)
		var sent: Array = row.messages.map(func(m): return String(m.message).hex_to_int())
		if effect == Criticals.PETRIFY or effect == Criticals.CRYSTALLIZE: continue   # missile kinds the swing never writes
		var want: Array = [int(Criticals.MELEE_MESSAGES[effect])] if Criticals.MELEE_MESSAGES.has(effect) else []
		if sent == want: same += 1
		else: check(false, "0x51abe0 effect %d killed %s: %s, port %s" % [effect, row.killed, sent, want])
		# The handler's level is the swing's parameter (33 here) for Stun, Mana Drain and Cleave; Freeze sends 0.
		if effect in [Criticals.STUN, Criticals.MANA_DRAIN, Criticals.CLEAVE]:
			check(int(row.messages[0].param) == 33, "0x51abe0 effect %d passes the swing's parameter" % effect)
		if effect == Criticals.FREEZE: check(int(row.messages[0].param) == 0, "0x51abe0 effect 6 sends level 0")
		if effect == Criticals.ASSASSINATE: check(int(row.messages[0].gold) == Criticals.REWARD, "0x51abe0 effect 4: 100 gold")
	check(same == 20, "0x51abe0: the messages of effects 0..11 (but 3 / 5) equal the executable's (%d of 20)" % same)

func handlers(f: Dictionary):
	for row in f.handlers:
		new_world()
		var id := add_world_unit("AHIX", open, 0)
		var t = fighter(id)
		var b: Dictionary = row.before
		t.hp = int(b.hp)
		t["statuses"] = []
		for e in b.effects: t.statuses.append({"kind": int(e[0]), "value": int(e[1]), "until": int(e[2]), "art": int(e[3])})
		if b.w132 != null: t["look"] = {"state": int(b.w132[0]), "until": int(b.w132[1])}
		t["mana"] = int(b.mana[0])
		t["max_mana"] = int(b.mana[1])
		t.xp = int(b.xp)
		t["armour_cut"] = int(b.w20c)
		if bool(row.hero):
			t.hero = true
			t.mana = int(b.pool)
			world.combat.heroes[0] = {"unit": id, "match": null}
		var c = world.combat
		var param := int(row.param)
		match String(row.message).hex_to_int():
			0x21e: Criticals.freeze(c, t)
			0x221: Criticals.stun(c, t, param)
			0x21f: Criticals.mana_drain(c, t, param)
			0x223: Criticals.xp_drain(c, t, param)
			0x224: Criticals.armour_reduced(c, t, param)
		var a: Dictionary = row.after
		var want_status: Array = a.effects.map(func(e): return [int(e[0]), int(e[1]), int(e[2]), int(e[3])])
		want_status.sort()
		var name := String(row.name)
		check(statuses_of(t) == want_status, "%s: the status list %s, port %s" % [name, want_status, statuses_of(t)])
		var want_look = null if a.w132 == null else [int(a.w132[0]), int(a.w132[1])]
		var look = t.get("look")
		var got_look = null if look == null else [int(look.state), int(look.until)]
		check(got_look == want_look, "%s: the look %s, port %s" % [name, want_look, got_look])
		if bool(row.hero): check(int(t.mana) == int(a.pool), "%s: the hero pool %d, port %d" % [name, a.pool, t.mana])
		else: check(int(t.mana) == int(a.mana[0]), "%s: mana %d, port %d" % [name, a.mana[0], t.mana])
		check(int(t.xp) == int(a.xp), "%s: experience %d, port %d" % [name, a.xp, t.xp])
		check(int(t.armour_cut) == int(a.w20c), "%s: +0x20c %d, port %d" % [name, a.w20c, t.armour_cut])
		# Every handler that acts draws its art (and floats its text); one that returns early draws nothing.
		check((not floats.is_empty()) == (not row.effects_drawn.is_empty()), "%s: presentation only when the handler acts" % name)

func cleave_record(f: Dictionary):
	for row in f.cleave:
		new_world()
		var t := add_world_unit("AHIX", open, 0)
		var a := add_world_unit("AHKX", open + Vector2i(1, 0), 1)
		var records: Array = []
		world.spells.cast_done.connect(func(info): records.append(info.record))
		var attacker = fighter(a) if int(row.attacker) >= 0 else null
		Criticals.cleave(world.combat, attacker, fighter(t), int(row.param))
		if row.messages.is_empty():
			check(records.is_empty(), "%s: no record without the attacker" % row.name)
			continue
		var want: Dictionary = row.messages[0]
		check(records.size() == 1, "%s: one record" % row.name)
		if records.is_empty(): continue
		var r: Dictionary = records[0]
		var same := true
		for key in ["area", "radius", "b4", "b6", "sound", "b9", "b10", "b11", "b12", "effect", "effect2", "kind", "w97", "amount", "w9b", "w9d", "w9f", "d131", "d135"]:
			if str(r.get(key)) != str(want.get(key)) and not (typeof(want.get(key)) == TYPE_FLOAT and int(r.get(key, -999)) == int(want.get(key))):
				same = false
				check(false, "%s: record %s = %s, port %s" % [row.name, key, want.get(key), r.get(key)])
		check(same, "%s: the record 0x5278a0 sends equals the executable's" % row.name)
		check(String(r.caster_kind) == "unit" and int(r.caster) == a and int(r.owner) == 1, "%s: the attacker is the record's caster" % row.name)

func armour_words(f: Dictionary):
	for row in f.armour:
		new_world()
		var id := add_world_unit(String(row.code), open, 0)
		var t = fighter(id)
		t.stats.armour = int(row.base)
		t["armour_cut"] = int(row.w20c)
		var block: Dictionary = world.combat.combat_block(t)
		check(int(CombatRules.armour_table(block)[0]) == int(row.words[0]), "0x5260a0 %s with +0x20c %d: armour %d, port %d" % [row.code, row.w20c, row.words[0], CombatRules.armour_table(block)[0]])

func missile_kinds():
	var b3 = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch3_fixtures.json"))
	check(b3 is Dictionary and b3.has("missile_kinds"), "tests/batch3_fixtures.json missile_kinds")
	if not (b3 is Dictionary): return
	var same := 0
	for row in b3.missile_kinds:
		var hit: bool = int(row.roll) < Criticals.KIND_CHANCE        # the harness forces every draw (both for type 0xb)
		var got := Criticals.missile_kind(String(row.unit), int(row.dtype), 20, hit, [0, 0])
		if got == [int(row.kind), int(row.level)]: same += 1
		else: check(false, "0x523150 %s type %d roll %d: %d / %d, port %s" % [row.unit, row.dtype, row.roll, row.kind, row.level, got])
	check(same == b3.missile_kinds.size(), "0x523150: %d shot kinds equal the executable's" % same)
	# The art's kind stays when the draw misses; the draw's kind replaces it when it hits.
	check(Criticals.missile_kind("AADW", 1, 30, false, Criticals.art_kind("EMF2")) == [Criticals.FREEZE, 5], "a miss keeps EMF2's Freeze")
	check(Criticals.missile_kind("AADB", 2, 30, false, Criticals.art_kind("EMF6")) == [Criticals.MANA_DRAIN, 40], "a miss keeps EMF6's Mana Drain")
	check(Criticals.missile_kind("AADC", 3, 30, true, Criticals.art_kind("EMF5")) == [Criticals.BURN, 0], "a hit replaces the art's kind")
	check(Criticals.missile_kind("ASCA", 6, 80, true, [0, 0]) == [Criticals.CLEAVE, 50] and Criticals.missile_kind("ASCA", 6, 37, true, [0, 0]) == [Criticals.CLEAVE, 37], "Cleave's level: the shot's damage, at most 50")
	check(Criticals.missile_kind("ATOX", 2, 30, false, [0, 0]) == [Criticals.PETRIFY, 0], "the petrifiers always kind 3")

func draws():
	var rng = Rng.new(0x1badb002, 0x2468ace0)
	var twin = Rng.new(0x1badb002, 0x2468ace0)
	var hit: bool = Criticals.draw_kind(rng, 0)
	check(hit == (int(twin.roll(1, 100, 0)) < 5) and rng.roll(1, 1000, 0) == twin.roll(1, 1000, 0), "0x523150: one draw for a plain type")
	# Type 0xb: a second draw when the first misses.
	for seed in 40:
		var r1 = Rng.new(0x1000 + seed, 0x77 + seed)
		var r2 = Rng.new(0x1000 + seed, 0x77 + seed)
		var first: bool = int(r2.roll(1, 100, 0)) < 5
		var expected := first
		if not first: expected = int(r2.roll(1, 100, 0)) < 5
		var got: bool = Criticals.draw_kind(r1, 0xb)
		if got != expected or r1.roll(1, 1000, 0) != r2.roll(1, 1000, 0):
			check(false, "0x523150 type 0xb seed %d" % seed)
			return
	check(true, "0x523150: type 0xb draws again after a miss")

# ------------------------------------------------------------------------------------------------ 2. the world
func blow(attacker: int, target: int, effect: int, param: int, damage := 3):
	world.combat._melee_blow(fighter(attacker), "unit", target, {"damage": damage, "effect": effect, "param": param})

func shot(attacker: int, target: int, kind: int, level: int, damage := 20, dtype := 0) -> Dictionary:
	var c = world.combat
	var cell: Vector2i = c.unit_cell(attacker)
	var shooter := {"kind": "unit", "owner": int(fighter(attacker).owner), "cell": cell, "rect": [cell.x * 32, cell.y * 24, 32, 24],
		"launch_offset": Vector2i.ZERO, "combat": 10, "roll": 1, "flags_ba": 0, "high": false, "elevation": 0}
	var m: Dictionary = Missiles.create("EMA0", shooter, c._missile_target("unit", target), c.rng, c.now_ms, c._map_size())
	m.merge({"attacker": attacker, "attacker_kind": "unit", "damage": damage, "dtype": dtype, "target_kind": "unit", "target_id": target,
		"launch_ms": c.now_ms, "from": cell, "to": m.aim, "kind": kind, "level": level})
	var landed: Array = []
	c.missile_landed.connect(func(info): landed.append(info))
	c._impact(m, {"kind": "unit", "id": target})
	return landed[0] if not landed.is_empty() else {}

func world_checks():
	open = open_ground()
	check(open.x >= 0, "open ground for the world checks")
	if open.x < 0: return
	var c
	# Freeze (melee effect 6, damage type 1): 0x30 = 6 for 8 s, slower, the text and EZ64.
	new_world()
	c = world.combat
	var a := add_world_unit("AHKX", open, 1)
	var t := add_world_unit("AHKX", open + Vector2i(1, 0), 0)
	blow(a, t, Criticals.FREEZE, 0)
	check(statuses_of(fighter(t)) == [[0x30, 6, 58000, 0]], "melee Freeze: 0x30 = 6 until now + 8000 (%s)" % [statuses_of(fighter(t))])
	check(world.spells.status_value(fighter(t), 0x30) == 6, "Freeze counts in the speed and attack-rate terms (status 0x30)")
	check(lines() == [0x45c] and int(floats[0].colour) == 0 and String(floats[0].effects[0].code) == "EZ64" and String(floats[0].sound) == "IceCrit.wav", "Critical: Freeze, EZ64, IceCrit.wav")
	# Stun (effect 8, type 5): 0x46 for level x 1000 ms and combat 1.
	new_world()
	c = world.combat
	a = add_world_unit("AHKX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(1, 0), 0)
	blow(a, t, Criticals.STUN, 5)
	check(statuses_of(fighter(t)) == [[0x46, 10, 55000, 0]], "melee Stun 5: 0x46 = 10 until now + 5000")
	check(CombatRules.effective_combat(c.combat_block(fighter(t))) == 1, "a stunned unit fights at combat 1")
	check(lines() == [0x45b] and floats[0].effects.size() == 2 and bool(floats[0].effects[0].follow), "Critical: Stun with EZ10 (following) and EZ63")
	# Mana Drain (effect 9, type 2) on a unit with mana.
	new_world()
	c = world.combat
	a = add_world_unit("AHKX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(1, 0), 0)
	fighter(t)["mana"] = 25
	fighter(t)["max_mana"] = 100
	blow(a, t, Criticals.MANA_DRAIN, 40)
	check(int(fighter(t).mana) == 0 and lines() == [0x45e], "melee Mana Drain 40 of 25: 0 left, Critical: Mana Drain")
	floats.clear()
	blow(a, t, Criticals.MANA_DRAIN, 40)
	check(floats.is_empty(), "Mana Drain on a unit without mana: nothing")
	# Ignore Armor (effect 10): the swing already ignored the armour; the impact shows EZ06 and the text in view.
	floats.clear()
	blow(a, t, Criticals.IGNORE_ARMOUR, 0)
	check(lines() == [0x459] and bool(floats[0].get("text_view", false)) and String(floats[0].sound) == "PiercingCrit.wav", "Critical: Ignore Armor (in view), EZ06, PiercingCrit.wav")
	# Effect 7 (damage type 4) does nothing.
	floats.clear()
	var hp_before := int(fighter(t).hp)
	blow(a, t, Criticals.NONE_7, 0)
	check(floats.is_empty() and int(fighter(t).hp) == hp_before - 3 and statuses_of(fighter(t)).is_empty(), "effect 7: the damage alone")
	# Cleave (effect 11, type 6): a kind 0x13 ring of radius 2 around the attacker, enemies only.
	new_world()
	c = world.combat
	a = add_world_unit("AHKX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(1, 0), 0)
	var near := add_world_unit("AHKX", open + Vector2i(0, -2), 0)   # row y + 2 is outside the gather (exclusive end)
	var far := add_world_unit("AHKX", open + Vector2i(3, 0), 0)
	var own := add_world_unit("AHKX", open + Vector2i(-1, 0), 1)
	var hp := {}
	for id in [t, near, far, own, a]: hp[id] = int(fighter(id).hp)
	var dealt := CombatRules.armour_tail(30, 2, 6, CombatRules.armour_table(c.combat_block(fighter(near))), CombatRules.resist_flags(c.combat_block(fighter(near))))
	blow(a, t, Criticals.CLEAVE, 30)
	check(int(fighter(near).hp) == int(hp[near]) - dealt, "Cleave: an enemy within 2 of the attacker takes 0x42bbf0(30, 2, type 6) = %d" % dealt)
	check(int(fighter(t).hp) == int(hp[t]) - 3 - dealt, "Cleave: the target takes the blow and the ring")
	check(int(fighter(far).hp) == int(hp[far]) and int(fighter(own).hp) == int(hp[own]) and int(fighter(a).hp) == int(hp[a]), "Cleave: not beyond 2, not the attacker's side")
	check(lines().has(0x45a) and int(floats[lines().find(0x45a)].id) == t, "Critical: Cleave over the target")
	# Assassinate (effect 4): 100 gold to the attacker's owner before the blow, the text over a non-hero attacker.
	new_world()
	c = world.combat
	a = add_world_unit("AHKX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(1, 0), 0)
	var gold_before := int(world.economy.resources(1)[0])
	blow(a, t, Criticals.ASSASSINATE, 0, 5000)
	check(int(world.economy.resources(1)[0]) == mini(gold_before + 100, int(world.economy.capacity(1)[0])) and int(world.economy.resources(1)[0]) > gold_before, "Assassinate: +100 gold")
	check(lines() == [0x47a] and int(floats[0].id) == a and int(floats[0].colour) == 1 and String(floats[0].effects[0].code) == "EZ43", "Assassinate: +100 Gold over the attacker, EZ43 at the target")
	check(not c.alive(fighter(t)), "the 5000 damage kills")
	# Missiles: Ignore Armor's raw damage (kind 10 skips 0x42bbf0).
	new_world()
	c = world.combat
	a = add_world_unit("AHMX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(4, 0), 0)
	var t2 := add_world_unit("AHKX", open + Vector2i(4, 2), 0)
	check(int(CombatRules.armour_table(c.combat_block(fighter(t)))[0]) > 0, "the Knight has armour")
	var plain := shot(a, t2, 0, 0)
	var raw := shot(a, t, Criticals.IGNORE_ARMOUR, 0)
	check(int(raw.get("damage", -1)) == 20 and int(plain.get("damage", -1)) < 20, "kind 10: the shot's full damage (%s), not the armoured %s" % [raw.get("damage"), plain.get("damage")])
	check(lines() == [0x459], "kind 10: Critical: Ignore Armor")
	# XP Drained (kind 12, EMF4) and Armor Reduced (kind 14, EMF3).
	floats.clear()
	for id in [t, t2]: fighter(id).hp = 1000
	fighter(t).xp = 25
	shot(a, t, Criticals.XP_DRAIN, 10)
	check(int(fighter(t).xp) == 15 and lines() == [0x360] and int(floats[0].value) == 10 and int(floats[0].colour) == 2, "kind 12: 10 XP Drained (colour 2)")
	floats.clear()
	var armour_before := int(CombatRules.armour_table(c.combat_block(fighter(t)))[0])
	shot(a, t, Criticals.ARMOUR_REDUCED, 2)
	shot(a, t, Criticals.ARMOUR_REDUCED, 2)
	check(int(fighter(t).armour_cut) == 4 and int(CombatRules.armour_table(c.combat_block(fighter(t)))[0]) == maxi(0, armour_before - 4), "kind 14 twice: armour - 4 for good")
	check(lines() == [0x35f, 0x35f], "kind 14: Armor Reduced")
	# A local hero loses XP from the profile; another player's hero keeps it.
	var hm := FakeMatch.new()
	hm.profile.data.xp = 7
	fighter(t2).hero = true
	c.heroes[0] = {"unit": t2, "match": hm}
	shot(a, t2, Criticals.XP_DRAIN, 10)
	check(int(hm.profile.data.xp) == 0, "kind 12 on the local hero: the profile's experience, clamped at 0")
	hm.computer = true
	hm.profile.data.xp = 50
	shot(a, t2, Criticals.XP_DRAIN, 10)
	check(int(hm.profile.data.xp) == 50, "kind 12 on a computer's hero: kept")
	# Freeze, Stun, Mana Drain and Cleave from the shot, Burn with its level.
	new_world()
	c = world.combat
	a = add_world_unit("AHMX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(4, 0), 0)
	near = add_world_unit("AHKX", open + Vector2i(1, 1), 0)
	fighter(t).hp = 1000
	shot(a, t, Criticals.FREEZE, 5)
	check(world.spells.status_value(fighter(t), 0x30) == 6, "kind 6: Freeze")
	shot(a, t, Criticals.STUN, 5)
	check(world.spells.status_value(fighter(t), 0x46) == 10, "kind 8: Stun")
	fighter(t)["mana"] = 60
	fighter(t)["max_mana"] = 100
	shot(a, t, Criticals.MANA_DRAIN, 40)
	check(int(fighter(t).mana) == 20, "kind 9: Mana Drain 40")
	var near_hp := int(fighter(near).hp)
	shot(a, t, Criticals.CLEAVE, 30)
	check(int(fighter(near).hp) < near_hp, "kind 11: Cleave around the shooter")
	shot(a, t, Criticals.BURN, 0)
	check(fighter(t).get("berserk") != null and int(fighter(t).berserk.level) == 0, "kind 1: Burn at the shot's level")
	# Crystallize (kind 5, EMF5): a unit the shot kills leaves no body; 100 crystal for the shooter's owner.
	new_world()
	c = world.combat
	a = add_world_unit("AHMX", open, 1)
	t = add_world_unit("AHKX", open + Vector2i(4, 0), 0)
	fighter(t).hp = 3
	world.units[t].hp = 3
	var crystal_before := int(world.economy.resources(1)[2])
	shot(a, t, Criticals.CRYSTALLIZE, 10)
	check(bool(fighter(t).removed) and not world.units[t].visible, "kind 5: the body is gone")
	check(int(world.economy.resources(1)[2]) == mini(crystal_before + 100, int(world.economy.capacity(1)[2])) and int(world.economy.resources(1)[2]) > crystal_before, "kind 5: +100 crystal")
	check(lines().has(0x47c) and int(floats[lines().find(0x47c)].id) == a, "Crystallize: +100 Crystal over the shooter")
	# Kind 5 on a unit that survives: nothing.
	t2 = add_world_unit("AHKX", open + Vector2i(4, 2), 0)
	floats.clear()
	shot(a, t2, Criticals.CRYSTALLIZE, 10)
	check(not bool(fighter(t2).removed) and floats.is_empty(), "kind 5 on a survivor: nothing")
	# Game mode 3 keeps every crit effect out of the swing (combat_rules.gd; the draws unchanged).
	var rng = Rng.new(0x1234, 0x5678)
	var res: Dictionary = CombatRules.swing({"combat": 60, "dmg": 10, "dtype": 2, "range": 0}, {"combat": 1, "range": 0, "armour": 0, "mres": 0}, rng, 1, 3)
	check(int(res.effect) == 0, "game mode 3: no effect byte")

# ------------------------------------------------------------------------------------------------ 3. the effects layer
class FakeUnit extends Node2D:
	var unit_id := 7
	var owner_id := 0
	var cell := Vector2i(10, 10)
	var dying := false
	var removed := false
	var orders: Array = []

class FakeScene extends Node:
	var catalogue_data := {}
	var local_player := 0
	var combat = null
	var units: Dictionary = {}
	var played: Array = []
	func unit_by_id(id: int): return units.get(id)
	func play_at(sound: String, cell: Vector2i): played.append([sound, cell])
	func game_string(_id: int, fallback: String) -> String: return fallback

func layer_checks():
	fx = EffectsLayer.new()
	var scene := FakeScene.new()
	fx.main = scene
	root.add_child(fx)
	root.add_child(scene)
	var u := FakeUnit.new()
	u.position = Vector2(336, 252)
	scene.units[7] = u
	root.add_child(u)
	fx._on_floated({"id": 7, "line": 0x45c, "value": 0, "colour": 0, "ms": 1000, "effects": [{"code": "EZ64", "on": 7, "once": true, "depth": 2}],
		"sound": "IceCrit.wav", "sound_on": 7, "sound_view": true})
	check(fx.texts.texts.size() == 1 and String(fx.texts.texts[0].text) == "Critical: Freeze" and fx.effects.size() == 1 and String(fx.effects[0].code) == "EZ64", "the layer: Critical: Freeze with EZ64")
	check(scene.played == [["IceCrit.wav", Vector2i(10, 10)]], "the layer: IceCrit.wav at the unit")
	fx.texts.clear()
	fx._on_floated({"id": 7, "line": 0x360, "value": 10, "colour": 2, "ms": 1000})
	check(String(fx.texts.texts[0].text) == "10 XP Drained", "the layer: %d XP Drained")
	fx.texts.clear()
	scene.played.clear()
	for i in 2:
		fx._on_floated({"id": -1, "line": 0x47a, "colour": 1, "ms": 1000, "effects": [{"code": "EZ43", "on": 7, "once": true, "depth": 2}],
			"sound": "Assassination.wav", "sound_on": 7, "sound_cooldown": "assassination"})
	check(fx.texts.texts.is_empty() and scene.played.size() == 1, "the layer: no text for id -1; Assassination.wav once a second")
	var bursts_before: int = fx.bursts.bursts.size() + fx.bursts.emitters.size()
	fx._on_floated({"id": 7, "line": 0x47c, "colour": 1, "ms": 1000, "bursts": [{"burst": Criticals.CRYSTAL_BURST, "pixel": Vector2i(336, 252), "row": 10}],
		"sound": "Crystallize.wav", "sound_cell": Vector2i(10, 10), "sound_cooldown": "crystallize", "local_party": [1, 2]})
	check(String(fx.texts.texts[0].text) == "Crystallize: +100 Crystal", "the layer: Crystallize: +100 Crystal")
	check(scene.played.size() == 1, "the layer: Crystallize.wav only when the local player is a party")
	check(fx.bursts.bursts.size() + fx.bursts.emitters.size() == bursts_before + 1, "the layer: the crystal burst")
	fx.clear()
	fx.free()
	u.free()
	scene.free()
