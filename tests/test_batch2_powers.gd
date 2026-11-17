extends "res://tests/test_hero_spells.gd"
## B2-1 (BATCH2_RESEARCH.md section 2): the race powers against tests/batch2_fixtures.json (`mercenaries`, `mysticism`) and
## tests/batch2_review_fixtures.json (`cells`, `state`, `tick`, `armour`, `reach`, `eating`, `fire`), on the hero spells'
## stand-alone combat world; the Read rules (trade cell, counter 0x70d622 and 0x40dc80, Training's rule, the hunters' scan)
## by their decompiled statements. The scene parts (buttons, trading, Farseeing) are in the three batch-2 world checks.

const RacePowers = preload("res://simulation/race_powers.gd")
const ProdRules = preload("res://simulation/production_rules.gd")
const SaveGame = preload("res://simulation/save_game.gd")
const WARLORD_START := 50000

var fixtures: Dictionary = {}
var review: Dictionary = {}

func run():
	fixtures = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch2_fixtures.json"))
	review = JSON.parse_string(FileAccess.get_file_as_string("res://tests/batch2_review_fixtures.json"))
	centre = open_ground()
	check(centre.x >= 0, "open ground for the batch 2 world")
	if centre.x >= 0:
		for part in ["cells", "state", "tick", "armour", "reach", "eating", "fire", "mercenaries", "mysticism", "trade", "counter", "hunting", "saved", "hero_spell"]:
			call(part)
	clear_world()
	if failures > 0:
		printerr("Batch 2 powers checks failed: %d of %d" % [failures, checks])
		quit(1)
		return
	print("Batch 2 powers checks passed: %d" % checks)
	quit(0)

func now_at(ms: int):
	world.ms = ms
	world.combat.next_update_ms = ms + 25
	world.combat.now_ms = ms

func step_to(ms: int):
	world.ms = ms
	world.combat.update(ms)

func fighter(id: int):
	return world.combat.fighters[id]

func unit_ref(id: int) -> Dictionary:
	return {"kind": "unit", "id": id}

## The fighter's berserk block in the fixtures' fields.
func view(f) -> Dictionary:
	var b = f.get("berserk")
	if b == null: return {"on": 0, "script": int(f.script)}
	return {"on": 1, "level": int(b.level), "drain": int(b.drain), "saved_script": int(b.saved_script), "next_tick": int(b.next_ms),
		"period": int(b.period), "end": int(b.until), "script": int(f.script)}

func same_state(got: Dictionary, want: Dictionary, label: String):
	if int(want.on) == 0:
		check(int(got.on) == 0, "%s: no state: %s" % [label, got])
		return
	for key in got:
		check(int(got[key]) == int(want[key]), "%s: %s %d, the original %d" % [label, key, int(got[key]), int(want[key])])

# ------------------------------------------------------------------------------------------------ the Berserker cell
func cells():
	for r in review.cells:
		var types: Array = String(r.selection).replace(" x3", "").split("+")
		var shown: bool = RacePowers.berserker_cell_shown(int(r.race), types, r.has("flagged"))
		check(shown == bool(r.shown), "cell shown for %s" % [r])
		var row: Array = r.cells.filter(func(c): return int(c[0]) == RacePowers.BERSERK_ICON)
		check((row.size() == 1) == shown, "the fixture's own cell list agrees for %s" % [r])
		if shown: check(bool(r.pfan) == (int(row[0][2]) != 0) and bool(r.enabled) == bool(r.pfan), "enabled with PFAN only: %s" % [r])

# ------------------------------------------------------------------------------------------------ the state
func state():
	for r in review.state:
		new_world()
		var id := unit("AMIX", Vector2i(0, 0), OWNER)
		var f = fighter(id)
		now_at(int(r.get("now", WARLORD_START)))
		f.script = int(r.get("script", 2))
		if r.case == "fresh":
			world.spells.berserk(unit_ref(id), int(r.level))
			same_state(view(f), r.after, "fresh level %d" % int(r.level))
		else:
			world.spells.berserk(unit_ref(id), int(r.first))
			same_state(view(f), r.middle, "first level %d" % int(r.first))
			now_at(52000)
			world.spells.berserk(unit_ref(id), int(r.second))
			same_state(view(f), r.after, "level %d over %d" % [int(r.second), int(r.first)])
	# 0x527720 returns for a dead unit (fixtures "berserk": scenario "dead unit").
	new_world()
	var id := unit("AMIX", Vector2i(0, 0), OWNER)
	var f = fighter(id)
	f.hp = 0
	f.state = "corpse"
	world.spells.berserk(unit_ref(id), 2)
	check(f.get("berserk") == null, "a dead unit takes no state")
	# fixtures "berserk" (0x4a9aa0 per unit): levels already on stay when the new level is not below them.
	for row in fixtures.berserk:
		if row.scenario != "already berserk": continue
		new_world()
		for i in row.units.size():
			var uid := unit(String(row.units[i]), Vector2i(i, 0), OWNER)
			now_at(WARLORD_START)
			world.spells.berserk(unit_ref(uid), int(row.preset[i]))
			var before: int = int(fighter(uid).berserk.level)
			world.spells.berserk(unit_ref(uid), 2)
			check(int(fighter(uid).berserk.level) == before, "level %d stays under level 2" % before)

func tick():
	for r in review.tick:
		if not bool(r.host): continue                     # the rebuild is the host
		new_world()
		var id := unit(String(r.unit), Vector2i(0, 0), OWNER)
		var f = fighter(id)
		f.script = 2
		f.hp = int(r.start.hp)
		f.max_hp = maxi(int(f.max_hp), int(f.hp))
		world.units[id].hp = f.hp
		f["regen_ms"] = 1 << 40   # R-1: the harness keeps message 0x138 (0x522860 arms the regeneration), so the fixture has no healing
		now_at(WARLORD_START)
		world.spells.berserk(unit_ref(id), int(r.level))
		for s in r.samples:
			step_to(WARLORD_START + int(s.t))
			if s.get("on", 0) != 1: continue
			check(maxi(0, int(f.hp)) == int(s.hp), "%s level %d at %d ms: hp %d, the original %d" % [r.unit, int(r.level), int(s.t), int(f.hp), int(s.hp)])
		var length: int = int(world.spells.BERSERK_STATES[int(r.level)][1])
		step_to(WARLORD_START + length + 1000)
		if r.stop != null:
			check(f.get("berserk") == null and int(f.script) == 2, "%s level %d: the script is back at the end" % [r.unit, int(r.level)])
			check(int(f.hp) == int(r.final.hp), "%s level %d: final hp %d, the original %d" % [r.unit, int(r.level), int(f.hp), int(r.final.hp)])
		else:
			check(int(f.hp) == 0 and not world.combat.alive(f), "%s level %d: drained to death" % [r.unit, int(r.level)])
			check(int(f.xp) == 0 and int(world.combat.kills.get(1, 0)) == 0 and int(world.combat.kills.get(0, 0)) == 0, "no killer, no kill")

func armour():
	new_world()
	var id := unit("AMIX", Vector2i(0, 0), OWNER)
	var f = fighter(id)
	var base: Array = CombatRules.armour_table(world.combat.combat_block(f)).duplicate()
	var base_combat: int = int(world.combat.combat_block(f).combat)
	var base_speed: int = int(world.spells.speed_term(f))
	var want0: Dictionary = review.armour[0]
	for r in review.armour.slice(1):
		new_world()
		id = unit("AMIX", Vector2i(0, 0), OWNER)
		f = fighter(id)
		world.spells.berserk(unit_ref(id), int(r.level))
		var block: Dictionary = world.combat.combat_block(f)
		var table: Array = CombatRules.armour_table(block)
		for i in 7:
			check(int(table[i]) - int(base[i]) == int(r.armour[i]) - int(want0.armour[i]), "level %d armour word %d" % [int(r.level), i])
		check(int(block.combat) - base_combat == int(r.combat) - int(want0.combat), "level %d combat" % int(r.level))
		check(int(world.spells.speed_term(f)) - base_speed == int(r.speed) - int(want0.speed), "level %d speed" % int(r.level))

# ------------------------------------------------------------------------------------------------ hunting
func reach():
	new_world()
	var seen := {}
	for r in review.reach:
		var key := "%s %s" % [r.attacker, r.target]
		if not seen.has(key):
			var a := unit(String(r.attacker), Vector2i(-4, 2 * seen.size()), OWNER)
			var t := unit(String(r.target), Vector2i(4, 2 * seen.size()), ENEMY)
			seen[key] = world.combat.order_range(fighter(a), {"target_kind": "unit", "target_id": t}) + 1
		check(int(seen[key]) == int(r.reach), "%s: reach %d, the original %d" % [key, int(seen[key]), int(r.reach)])
		check(CombatRules.in_attack_range(int(r.gap), int(seen[key]) - 1) == (r.outcome == "attack"), "%s at %d: %s" % [key, int(r.gap), r.outcome])

## tools/emulate_batch2_review.py eating(): the same order, with the status override and the stale row by position.
func eating():
	var rows: Array = review.eating
	for i in rows.size():
		var r: Dictionary = rows[i]
		if not bool(r.host): continue
		new_world()
		var v := unit(String(r.victim), Vector2i(1, 0), 6)
		var k := unit(String(r.killer), Vector2i(0, 0), OWNER)
		var kf = fighter(k)
		if r.killer == "AHIX" and r.has("hp_after"): kf.stats["flags"] = int(kf.stats.get("flags", 0)) | 0x80      # the status=0x80 row
		if r.has("messages") and not r.has("hp_after") and r.killer == "AMIX" and r.victim == "ACSH" and int(r.hp) == 30: kf.stats["flags"] = 0   # status=0
		var maximum: int = int(kf.max_hp)
		kf.hp = int(r.hp)
		world.units[k].hp = kf.hp
		if int(r.poison): world.combat.set_poisoned(k, true)
		if int(r.disease): world.spells.set_disease(kf)
		world.combat.apply_damage("unit", v, 100000, k)
		if r.has("hp_after"):
			check(int(kf.hp) == int(r.hp_after), "%s kills %s at hp %d: %d, the original %d" % [r.killer, r.victim, int(r.hp), int(kf.hp), int(r.hp_after)])
			check(not bool(kf.get("poisoned", false)) and not bool(kf.get("diseased", false)), "cured")
			check(int(kf.hp) <= maximum, "at most the maximum")
		else:
			check(int(kf.hp) == int(r.hp), "%s kills %s: no meal" % [r.killer, r.victim])

func hunting():
	# 0x5334f0's animal branch: the own sheep of a wounded Minotaur, its priority, the unwounded and the fog.
	new_world()
	var combat = world.combat
	var a := unit("AMIX", Vector2i(0, 0), OWNER)
	var s := unit("ACSH", Vector2i(3, 0), OWNER)
	var f = fighter(a)
	var rect := [centre.x - 12, centre.x + 12, centre.y - 12, centre.y + 12]
	check(combat.search_rect(OWNER, centre, rect, a) == null, "an unhurt Minotaur does not hunt")
	f.hp = int(f.max_hp) - 40
	var got = combat.search_rect(OWNER, centre, rect, a)
	check(got != null and got.kind == "unit" and int(got.id) == s, "a wounded Minotaur finds its own sheep")
	check(got != null and int(got.hunt) == (40 >> 2) + 1, "priority (max - hp) >> 2 + 1")
	check(combat.order_attack(a, "unit", s, true), "and takes the attack order on its own sheep")
	check(not combat.order_attack(unit("AHIX", Vector2i(0, 3), OWNER), "unit", s, true), "another unit cannot attack the sheep")
	var other = combat.search_rect(0, centre, rect, unit("AHIX", Vector2i(0, 5), 0))
	check(other == null or int(other.id) != s, "nobody else searches animals")
	check(RacePowers.hunt_priority("AMIX", false, 10, 2000, "ACSH", 0) == 201, "the priority stops at 201")
	check(RacePowers.hunt_priority("AMIX", false, 10, 20, "ACGO", 0) == 0, "AMIX leaves goats")
	check(RacePowers.hunt_priority("AMNX", false, 10, 20, "ACGO", 0) == 3, "AMNX takes goats")
	check(RacePowers.hunt_priority("ABHX", true, 10, 20, "ACGO", 0) == 3, "a Minotaur hero takes goats")
	check(RacePowers.hunt_priority("ABHX", false, 10, 20, "ACGO", 0) == 0, "not an ABHX of another hero race")
	# The hero's own race decides, not the slot's (0x7091fc).
	new_world()
	var h := hero("ABHX", {}, OWNER)
	world.combat.heroes[OWNER].match.profile.data["race_id"] = 4
	fighter(h).hp = int(fighter(h).max_hp) - 20
	var goat := unit("ACGO", Vector2i(2, 0), 6)
	check(world.combat.hunt_priority(fighter(h), fighter(goat)) > 0, "a Minotaur hero hunts goats")
	world.combat.heroes[OWNER].match.profile.data["race_id"] = 1
	check(world.combat.hunt_priority(fighter(h), fighter(goat)) == 0, "an ABHX hero of another race does not")
	check(RacePowers.hunt_priority("AOMX", false, 20, 20, "ACSH", 0) == 1 and RacePowers.hunt_priority("ASCA", false, 20, 20, "ACCO", 0) == 1, "ASCA / AOMX at 1")
	check(RacePowers.hunt_priority("AADE", false, 20, 20, "ACSO", 6) == 5 and RacePowers.hunt_priority("AADE", false, 20, 20, "ACSO", 7) == 0, "low mana takes ACSO")
	check(not RacePowers.melee_prey("AMNX", "ACSO") and RacePowers.melee_prey("AMNX", "ACSH") and RacePowers.melee_prey("ABHX", "ACTU"), "reach pairs")
	# The swing itself stays the unit's own: at 4 cells (inside its natural reach 5) an Axe Thrower still walks; beside the
	# sheep it throws (0x536e30: a ranged start), so no hit chance or melee swing comes in.
	new_world()
	var thrower := unit("AMNX", Vector2i(-4, 0), OWNER)
	var near := unit("AMNX", Vector2i(-1, 0), OWNER)
	var sheep := unit("ACSH", Vector2i(0, 0), OWNER)
	var enemy := unit("AHIX", Vector2i(-4, 4), ENEMY)
	for id in [thrower, near]:
		fighter(id).hp = int(fighter(id).max_hp) - 20
		check(world.combat.order_attack(id, "unit", sheep, true), "the Axe Thrower orders the attack")
	check(world.combat.order_attack(thrower, "unit", sheep, true), "again")
	step_to(25)
	check(fighter(thrower).state == "approach", "at 4 cells it walks: %s" % fighter(thrower).state)
	check(fighter(near).state == "swing" and bool(fighter(near).swing.ranged), "beside the sheep it throws: %s" % fighter(near).state)
	check(world.combat.order_attack(thrower, "unit", enemy, true), "the same thrower at an enemy")
	step_to(50)
	check(fighter(thrower).state == "swing", "at 4 cells it throws at an enemy")

# ------------------------------------------------------------------------------------------------ fire
func fire():
	var want := {0: 10, 1: 6, 2: 9, 3: 1, 4: 7, 5: 8, 6: 11}
	for r in review.fire.swing:
		if int(r.dtype) > 6: continue
		var att := {"combat": 30, "dmg": 12, "dtype": int(r.dtype), "range": 1, "armour": 0, "mres": 0, "owner": 0, "type_id": "AHKX"}
		var tgt := {"combat": 5, "dmg": 5, "dtype": 0, "range": 1, "armour": 0, "mres": 0, "owner": 1, "type_id": "AHKX"}
		var got: Dictionary = CombatRules.swing(att, tgt, Rng.new(int(r.seed[0]), int(r.seed[1])))
		check(int(got.effect) == int(r.effect) and int(got.effect) == int(want[int(r.dtype)]), "type %d crit effect: %d" % [int(r.dtype), int(got.effect)])
	# A fire crit through _hit burns the target (level 0), replacing level 2; the fixture's sender row gives level = param.
	for r in review.fire.sender:
		new_world()
		var a := unit("AHKX", Vector2i(0, 0), ENEMY)
		var t := unit("AMIX", Vector2i(1, 0), OWNER)
		var tf = fighter(t)
		tf.script = 2
		tf.hp = 80
		now_at(WARLORD_START)
		var swing := {"target_kind": "unit", "target_id": t, "ranged": false, "result": {"damage": 5, "effect": int(r.effect), "param": int(r.level)}, "hit_done": false}
		world.combat._hit(fighter(a), swing)
		var sends: bool = r.messages.has("0x204")
		check((tf.get("berserk") != null) == sends, "effect %d: message 0x204 %s" % [int(r.effect), sends])
		if sends: check(int(tf.berserk.level) == int(r.level) and int(tf.hp) == 75, "level %d, the hit lands" % int(r.level))
	new_world()
	var a := unit("AHKX", Vector2i(0, 0), ENEMY)
	var t := unit("AMIX", Vector2i(1, 0), OWNER)
	var tf = fighter(t)
	tf.script = 2
	now_at(WARLORD_START)
	world.spells.berserk(unit_ref(t), 2)
	world.combat._hit(fighter(a), {"target_kind": "unit", "target_id": t, "ranged": false, "result": {"damage": 1, "effect": 1, "param": 0}, "hit_done": false})
	check(int(tf.berserk.level) == 0 and int(tf.berserk.saved_script) == 4 and int(tf.script) == 4, "burning replaces level 2; the saved script is then Rampant")
	step_to(WARLORD_START + 16000)
	check(tf.get("berserk") == null and int(tf.script) == 4, "after the burn the unit stays Rampant (quirk of the original)")
	# EMF1's impact (R3): a missile of kind 1.
	new_world()
	var shooter := unit("AHKX", Vector2i(0, 0), ENEMY)
	t = unit("AMIX", Vector2i(3, 0), OWNER)
	var m := {"id": "EMF1", "attacker": shooter, "attacker_kind": "unit", "damage": 5, "dtype": 3, "impacts": [], "shooter_elevation": 0, "flags": 0, "mode": 2}
	world.combat._impact(m, {"kind": "unit", "id": t})
	check(fighter(t).get("berserk") != null and int(fighter(t).berserk.level) == 0, "an EMF1 hit burns the unit")

# ------------------------------------------------------------------------------------------------ Foreign Mercenaries, Mysticism
class ForcedRoll extends RefCounted:
	var value := 0
	func roll(_count: int, _sides: int, _bonus: int) -> int: return value

func mercenaries():
	for item in ["POMA", "POMB", "POMC"]:
		var data: Dictionary = fixtures.mercenaries[item]
		var pool: Array = RacePowers.MERCENARY_POOLS[item]
		check(pool.size() == int(data.sides), "%s: %d entries" % [item, pool.size()])
		var roll := ForcedRoll.new()
		for r in data.forced:
			roll.value = int(r.roll)
			check(RacePowers.mercenary_type(item, roll) == String(r.messages[0].type), "%s roll %d" % [item, int(r.roll)])
			check(int(r.messages[0].rank) == 0 and r.messages.size() == 1, "one unit of rank 0")
		var seed: Array = data.draw_seed
		var rng = Rng.new(int(seed[0]), int(seed[1]))
		for r in data.drawn:
			var type: String = String(r if r is String else r.get("type", ""))
			check(RacePowers.mercenary_type(item, rng) == type, "%s drawn %s" % [item, type])

func mysticism():
	new_world()
	var rows: Array = fixtures.mysticism.units
	var ids: Array = []
	for i in rows.size():
		var r: Dictionary = rows[i]
		var id := unit(String(r.unit), Vector2i(i * 2, 0), int(r.owner))
		var f = fighter(id)
		f.hero = bool(r.hero)
		f["mana"] = int(r.before[0])
		f["max_mana"] = int(r.before[1])
		ids.append(id)
	world.production.research_completed.emit(1, "PLI0")
	for i in rows.size():
		var f = fighter(int(ids[i]))
		check([int(f.mana), int(f.max_mana)] == [int(rows[i].after[0]), int(rows[i].after[1])], "%s: %d / %d" % [rows[i].unit, int(f.mana), int(f.max_mana)])
	world.production.research_completed.emit(1, "PLI2")
	check(int(fighter(int(ids[0])).max_mana) == int(rows[0].after[1]), "PLI2 is no Mysticism step")

# ------------------------------------------------------------------------------------------------ Read rules
func trade():
	for id in RacePowers.TRADE_RACES:
		var race: int = int(RacePowers.TRADE_RACES[id])
		check(RacePowers.trade_cell_shown(id, race, false), "%s for its race before Trade" % id)
		check(not RacePowers.trade_cell_shown(id, (race + 1) % 16, false), "%s not for another race" % id)
		check(RacePowers.trade_cell_shown(id, (race + 1) % 16, true), "%s for another race with Trade" % id)
	check(not RacePowers.trade_cell_shown("BPBS", 0, true), "other buildings have none")

func counter():
	new_world()
	var combat = world.combat
	var lord := unit("AHEX", Vector2i(0, 0), OWNER)
	var warlord := unit("ABEX", Vector2i(2, 0), OWNER)
	check(int(combat.lord_counter.get(OWNER, 0)) == 3, "AHEX + 2, ABEX + 1")
	check(combat.morale_value(OWNER) == 3, "0x40dc80 without a hero: the counter")
	world.production.research[OWNER] = ["PMO0", "PMO1", "POLI", "PWRM"]
	check(combat.morale_value(OWNER) == 6 + 3 + 2 + 5, "0x40dc80: PMOX table, counter, POLI, PWRM")
	world.production.research[OWNER] = []
	check(combat.morale_value(6) == 0 and combat.morale_value(7) == 0, "the neutral player 0; none above it")
	fighter(lord).owner = ENEMY                      # a conversion moves the unit, not the counter
	combat.apply_damage("unit", lord, 100000, -1)
	check(int(combat.lord_counter.get(OWNER, 0)) == 3 and int(combat.lord_counter.get(ENEMY, 0)) == -2, "the death follows the current owner (0x5210b0)")
	combat.apply_damage("unit", warlord, 100000, -1)
	check(int(combat.lord_counter.get(OWNER, 0)) == 2, "ABEX - 1")
	# A living hero: 0x5269a0 with the counter; the attack time shrinks with it (0x537060, floor 500).
	new_world()
	combat = world.combat
	var h := hero("AUHX", {}, OWNER)
	var block: Dictionary = combat.hero_block(OWNER)
	var plain: int = combat.morale_value(OWNER)
	check(plain == combat.hero_command_value(OWNER, block, fighter(h)), "a living hero's 0x5269a0")
	unit("AHEX", Vector2i(3, 0), OWNER)
	check(combat.morale_value(OWNER) == plain + 2, "the Knight Lord adds 2 to the hero's value")
	world.spells.add_status(unit_ref(h), {"kind": 7, "value": 4, "until": 10000000, "art": 0})
	check(combat.morale_value(OWNER) == plain + 6, "effect 7 (0x5269a0)")
	combat.apply_damage("unit", h, 100000, -1)
	check(combat.morale_value(OWNER) == 2, "a dead hero: the 0x40dc80 table branch")
	check(CombatRules.attack_entry_ms(false, 30, 0, 10, 16) == (1200 * 10 / 10) / 16, "X shortens the attack entries")

## S-1: the new state is plain data in the combat module's capture.
func saved():
	new_world()
	var id := unit("AHEX", Vector2i(0, 0), OWNER)
	fighter(id).script = 2
	now_at(WARLORD_START)
	world.spells.berserk(unit_ref(id), 2)
	var s: Dictionary = SaveGame.capture(world.combat, world.combat._SAVE_SKIP)
	check(int(s.lord_counter[OWNER]) == 2, "the counter is in the save")
	check(int(s.fighters[id].berserk.saved_script) == 2 and int(s.fighters[id].berserk.until) == WARLORD_START + 180000, "the state is in the save")
	world.combat.apply_damage("unit", id, 100000, -1)
	check(fighter(id).get("berserk") == null, "death clears the state (0x521d39)")

## The hero spell reaches the whole state: hero 56's record kind 0x16 amount 2 through the applier.
func hero_spell():
	new_world()
	var h := hero("AUHX", {5: 1}, OWNER)
	var ally := unit("AMIX", Vector2i(2, 0), OWNER)
	var f = fighter(ally)
	f.script = 2
	now_at(WARLORD_START)
	var record: Dictionary = world.hs._berserker({"id": h, "kind": "unit", "owner": OWNER, "cell": centre, "unit_cell": centre}, 1)
	world.spells.berserk(unit_ref(ally), int(record.amount))
	check(int(f.berserk.level) == 2 and int(f.script) == 4, "Berserker (56): level 2, Rampant")
	check(int(f.berserk.until) == WARLORD_START + 180000, "for 180 s")
	step_to(WARLORD_START + 3000)
	check(int(f.hp) == int(f.max_hp) - 3, "at 1 hit point per second")
