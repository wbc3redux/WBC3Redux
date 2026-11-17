extends SceneTree
## Milestone 11-hero parity: HeroEffects / CombatRules against tests/hero_skill_fixtures.json (tools/emulate_hero_skills.py,
## the unmodified executable under Unicorn), plus the decoded item data against the emulated Power parser.
const Effects = preload("res://simulation/hero_effects.gd")
const CombatRules = preload("res://simulation/combat_rules.gd")
const CombatRng = preload("res://simulation/combat_rng.gd")
const ComputerHero = preload("res://simulation/computer_hero.gd")
var checks := 0
var failures := 0
var reported := {}

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		var key := label.get_slice(":", 0)
		reported[key] = int(reported.get(key, 0)) + 1
		if int(reported[key]) <= 5: printerr("Hero skill check failed: ", label)

func u16(v: int) -> int:
	return v & 0xffff

func block_of(skills: Array, equipment: Array, extra: Dictionary = {}) -> Dictionary:
	var b := {"skills": skills, "equipment": equipment, "hero": true, "hp": 100, "stats": [5, 5, 5, 5], "level": 1, "class": 0, "race": 0}
	b.merge(extra, true)
	return b

func _initialize():
	var f: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_skill_fixtures.json"))
	var data := Effects.items_data()
	check(int(data.get("count", 0)) == 225 and data.sets.size() == 8, "items: 225 items and 8 sets decoded")
	# 0x403a90: every Power element's type, data, level, chance.
	var by_item := 0
	for item in data.items:
		for p in item.powers:
			if String(p.type_name) == "": continue
			var row: Dictionary = f.powers[by_item]
			by_item += 1
			check(int(p.type) == int(row.result.type) and int(p.data) == int(row.result.data) and int(p.level) == int(row.result.level)
				and int(p.chance) == int(row.result.chance), "powers: item %s %s" % [item.name, row])
	for s in data.sets:
		var row: Dictionary = f.powers[by_item]
		by_item += 1
		check(int(s.power.type) == int(row.result.type) and int(s.power.data) == int(row.result.data) and int(s.power.level) == int(row.result.level), "powers: set %s" % s.name)
	# 0x55ec20
	for row in f.equip:
		for slot in range(11):
			check(Effects.equip_allowed(int(row.item), slot) == (int(row.slots[slot]) != 0), "equip: item %d slot %d" % [int(row.item), slot])
	# 0x556ea0
	for row in f.skill_terms:
		var values: Array = []
		for mode in [0, 1, 2]:
			for rank in [0, 1, 3, 10]: values.append(Effects.s16(Effects.skill_term(int(row[0]), rank, mode)))
		check(values == row.slice(1).map(func(v): return int(v)), "skill term: %d" % int(row[0]))
	# 0x556b50, 0x40c380, 0x40c500
	for row in f.lookups:
		var b := block_of(row.skills, row.equipment, {"hp": int(row.hp), "hero": bool(row.living)})
		for q in row.queries:
			check(u16(Effects.lookup(b, int(q[0]), int(q[1]), int(q[2]) != 0)) == int(q[3]), "lookup: %s skills %s items %s" % [q, row.skills, row.equipment])
		for stat in row.item_stats:
			check(Effects.item_stat(b, int(stat)) == int(row.item_stats[stat]), "item stat: %s %s" % [stat, row.equipment])
		for i in range(13):
			check(Effects.item_power(b, 99, 10 + i) == int(row.school_items[i]), "school item: %d %s" % [10 + i, row.equipment])
	# 0x54fd50
	for row in f.hero_init:
		var unit := Effects.hero_unit({"class": int(row.klass), "level": int(row.level), "stats": row.stats, "skills": row.skills, "equipment": row.equipment})
		for key in ["combat", "speed", "mres", "max_hp", "sight", "dmg", "dtype", "range", "armour"]:
			check(int(unit[key]) == int(row.unit[key]), "hero init: %s %s class %d" % [key, row.unit, int(row.klass)])
		check(int(unit.max_mana) == int(row.block.max_mana) and int(unit.mana) == int(row.block.mana), "hero init: mana %s" % row.block)
		check(unit.schools.map(func(v): return int(v)) == row.schools.map(func(v): return int(v)), "hero init: schools %s" % [row.schools])
	# Unit methods for hero units.
	for row in f.unit_terms:
		var b := block_of(row.skills, row.equipment, {"hp": int(row.hp), "hero": int(row.hp) > 0, "stats": row.stats, "race": int(row.race)})
		if not row.hero:
			check(int(row.command) == 0 and int(row.price) == 0, "unit terms: non-hero command/price 0")
			continue
		check(Effects.attack_rate(b) == int(row.rate), "unit terms: rate %s" % [row])
		check(Effects.command_value(b) == int(row.command), "unit terms: command %s" % [row])
		check(Effects.price_value(b) == int(row.price), "unit terms: price %s" % [row])
		check(Effects.effective_combat(int(row.unit_combat), b) == int(row.combat), "unit terms: combat %s" % [row])
		check(Effects.s16(int(b.get("conversion_radius", 0)) + Effects.item_stat(b, 10)) == int(row.term_5267b0), "unit terms: 0x5267b0 %s" % [row])
	# 0x42ace0 with hero attackers and targets.
	var rng = CombatRng.new()
	for row in f.swing:
		var att := attacker_block(row)
		var tgt := target_block(row)
		rng.seed_state(int(row.seed[0]), int(row.seed[1]))
		var result: Dictionary = CombatRules.swing(att, tgt, rng, int(row.distance))
		check(not result.has("fault") and int(result.damage) == int(row.result.damage) and int(result.effect) == int(row.result.effect)
			and int(result.param) == int(row.result.param), "swing: got %s want %s attacker %s skills %s items %s target %s skills %s items %s" % [
			result, row.result, row.attacker, row.attacker_skills, row.attacker_items, row.target, row.target_skills, row.target_items])
		check(rng.state() == row.result.state_after.map(func(v): return int(v)), "swing: generator state")
	ComputerHero.check_fixtures(f.computer_heroes, check)
	for key in reported: if int(reported[key]) > 5: printerr("  ... %d failures in %s" % [int(reported[key]), key])
	if failures == 0: print("Hero skill checks passed: ", checks)
	quit(0 if failures == 0 else 1)

## The attacker block as combat.gd builds it (HeroEffects terms resolved for a hero attacker).
func attacker_block(row: Dictionary) -> Dictionary:
	var a: Dictionary = row.attacker.duplicate()
	a["near_hero"] = false
	a["building"] = false
	if not row.attacker_hero: return a
	var b := block_of(row.attacker_skills, row.attacker_items, {"hp": int(a.hp), "hero": int(a.hp) > 0})
	var dmg := Effects.attack(int(a.dmg), int(a.dtype), b)
	a.dmg = dmg.dmg
	a.dtype = dmg.dtype
	a.combat = Effects.effective_combat(int(a.combat), b)
	a["crit_bonus"] = Effects.skill_effect(b, 0x21) + Effects.item_stat(b, 0x1b)
	a["ignore_armour"] = Effects.skill_effect(b, 0x2a)
	a["demolition"] = Effects.skill_effect(b, 0x2e)
	a["slayer_block"] = b
	a["assassin"] = Effects.skill_effect(b, 0x33) + Effects.item_stat(b, 0x22)
	a["hero"] = true
	return a

func target_block(row: Dictionary) -> Dictionary:
	var t: Dictionary = row.target.duplicate()
	if row.building:
		t["building"] = true
		t["res1"] = -1
		t["res2"] = -1
		t["range"] = 0
		return t
	t["building"] = false
	t["near_hero"] = false
	var own := block_of(row.target_skills, row.target_items, {"hp": 100, "hero": true}) if row.target_hero else {}
	var owner := block_of(row.target_skills, row.target_items, {"hp": 100, "hero": row.target_hero})
	if row.target_hero:
		t["hero"] = true
		t["hero_level"] = 1
		t.combat = Effects.effective_combat(int(t.combat), own)
	t["armour_table"] = Effects.armour_table(t, own, owner)
	return t
