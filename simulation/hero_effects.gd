extends RefCounted
## Hero skills and items in a match (milestone 11-hero). Ports of the original lookups and the hero terms of the unit
## methods; every function names its routine. Evidence (Emulated / Read / Open) in HERO_RESEARCH.md, "Milestone 11";
## fixtures in tests/hero_skill_fixtures.json (tools/emulate_hero_skills.py, unmodified executable under Unicorn).
##
## A hero "block" mirrors the per-player hero block 0x7091c0 + p * 0x194 that the routines read:
##   {"skills": [[id, unlock, rank], ...] (10 entries, id 0 = empty), "equipment": [11 item ids] (0..6 equipped,
##    7..10 backpack), "hero": bool (0x70adb4[p] holds a hero object), "hp": int (that object's hit points),
##    "stats": [S, D, I, C], "level", "class", "race", "conversion_radius" (+0x192)}
## Status effects (spells, the 0x577520 list), research (0x437f70) and the campaign terms (0x748946 == 2) are absent in
## the rebuild's skirmish and contribute 0.
##
## Setup rows (SKIRMISH_RESEARCH.md "Setup rows", Read; the flag's every reader found by a byte scan of the executable):
## More Options "No Hero Items" (0x749c68, block key "no_items") makes 0x40c380 (item_stat) and 0x40c500 (item_power)
## return 0 and 0x526310 skip the weapon's damage powers (attack). 0x556b50 (lookup) does not read the flag: an item's
## hero-skill powers (type 99) still raise skill ranks. 0x54fd50 skips its item school loop (item_power, 0 anyway);
## 0x529d20 (an equipped item's type 0x62 spell powers) is ported in spells.gd item_casts (it reads the flag too);
## 0x556ab0 (the hero sheet's item ranks) is ported in G-3 (`record_rank`, `sheet_combat`; HERO_RESEARCH.md "G-3").
const Assets = preload("res://core/asset_store.gd")

const ProductionRules = preload("res://simulation/production_rules.gd")
const Rules = preload("res://simulation/hero_rules.gd")
static var ITEMS_PATH: String = Assets.path("items.json")
const TABLES_PATH := "res://simulation/hero_skills.json"
const EQUIPPED := 7                 # slots 0..6 count for item powers (0x40c380 / 0x556b50 loop 7 slots)
const SLOTS := 11                   # 7 equipment + 4 backpack (record +0x1dc, 16 bytes each)
const TYPE_HERO_SKILL := 99
const KNIGHT_HERO_FLAGS := 0x12418001   # 0x5273c0: a hero's +0x1c0 by race (race 0)
const HERO_RACE_FLAGS := [0x12418001, 0x14418002, 0x18418004, 0x12418040, 0x14418080, 0x18418100, 0x12418008, 0x14418010,
	0x18418020, 0x12498000, 0x14418002, 0x12c18000, 0x14418001, 0x15418000, 0x18418400, 0x18418001]

static var _items: Dictionary = {}
static var _tables: Dictionary = {}

static func items_data() -> Dictionary:
	if _items.is_empty() and FileAccess.file_exists(ITEMS_PATH):
		_items = JSON.parse_string(FileAccess.get_file_as_string(ITEMS_PATH))
	return _items

static func tables() -> Dictionary:
	if _tables.is_empty():
		_tables = JSON.parse_string(FileAccess.get_file_as_string(TABLES_PATH))
	return _tables

static func item(id: int) -> Dictionary:
	var data := items_data()
	if data.is_empty() or id < 1 or id > int(data.count): return {}
	return data.items[id - 1]

static func item_name(id: int) -> String:
	var it := item(id)
	return String(it.get("name", "")) if not it.is_empty() else ""

static func skill_name(id: int) -> String:
	return String(items_data().get("skill_names", {}).get(str(id), "Skill %d" % id))

static func s16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v & 0x8000 else v

# ------------------------------------------------------------------------------------------- blocks
## The block of a rebuild profile (0x54fd50 copies the record's skills and the eleven item slots).
static func block_from_profile(data: Dictionary, alive: bool = true, hp: int = 1) -> Dictionary:
	var skills: Array = []
	for skill in data.get("skills", []):
		if skill is Dictionary: skills.append([int(skill.id), int(skill.get("unlock_level", 0)), int(skill.rank)])
		else: skills.append([int(skill[0]), int(skill[1]), int(skill[2])])
	var equipment: Array = []
	for slot in data.get("equipment", []) + data.get("backpack", []):
		equipment.append(int(slot.get("item", 0)) if slot is Dictionary else int(slot))
	while equipment.size() < SLOTS: equipment.append(0)
	return {"skills": skills, "equipment": equipment, "hero": alive, "hp": hp, "stats": data.get("stats", [1, 1, 1, 1]),
		"level": int(data.get("level", 1)), "class": int(data.get("class_id", 0)), "race": int(data.get("race_id", 0)),
		"conversion_radius": int(data.get("stats", [0, 0, 0, 0])[3]) + 5}

## 0x556ea0(skill, value, mode): mode 2 -> the additive part (4 for Assassin), mode 0 -> value * multiplier, else both.
static func skill_term(skill: int, value: int, mode: int = 1) -> int:
	var add := 0
	var factor := 1
	match skill:
		1, 0x2a, 0x5d: factor = 3
		2, 5, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2b, 0x2c, 0x2e, 0x2f, 0x31, 0x55, 0x56, 0x5a, 0x5b, 0x60, 100: factor = 10
		3, 0x3c, 0x42: factor = 20
		6, 7, 0x17, 0x1b, 0x1c, 0x1d, 0x1e, 0x20, 0x2d, 0x30, 0x32, 0x36, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x53, 0x54, 0x59, 0x5c, 0x61, 0x62, 99: factor = 5
		0x19, 0x57, 0x58: factor = 4
		0x1a, 0x21, 0x22, 0x34, 0x5e, 0x1f, 0x3b: factor = 2
		0x33: add = 4
		_:
			if skill >= 0x43 and skill <= 0x52: factor = 2
	if mode == 2: return add
	var value_part := value * factor
	return value_part if mode == 0 else value_part + add

## 0x402e30(item, 99, skill): the first of the item's power_count powers with type 99 and data == skill gives its level.
static func item_skill_bonus(item_id: int, skill: int) -> int:
	var it := item(item_id)
	if it.is_empty(): return 0
	for i in range(mini(int(it.power_count), 3)):
		var p: Dictionary = it.powers[i]
		if int(p.type) == TYPE_HERO_SKILL and int(p.data) == skill: return int(p.level)
	return 0

## 0x556b50(player, skill, mode, need_living): rank of the skill entry (unsigned 16 bits), plus the hero-skill powers of the
## seven equipped items. mode 2: rank only; mode 0: items only; else the sum. Returned as the 16 bits callers read.
static func lookup(block: Dictionary, skill: int, mode: int = 1, need_living: bool = true) -> int:
	if block.is_empty(): return 0
	if need_living and (not bool(block.get("hero", false)) or s16(int(block.get("hp", 0))) < 1): return 0
	var rank := 0
	for entry in block.skills:
		if int(entry[0]) == skill:
			rank = int(entry[2]) & 0xffff
			break
	var items := 0
	for i in range(EQUIPPED):
		var id := int(block.equipment[i]) if i < block.equipment.size() else 0
		if s16(id) > 0: items += item_skill_bonus(id, skill)
	if mode == 2: return s16(rank)
	if mode == 0: return s16(items)
	return s16(rank + items)

## G-3: 0x556ab0(record, skill, mode), the hero sheet's version of 0x556b50 on the saved record (Read): the rank of the
## skill entry (+0xfc id, +0x102 rank) plus the hero-skill powers (type 99) of the seven equipped items (+0x1dc), the items
## skipped while "No Hero Items" (0x749c68) is set; mode 2 rank only, 0 items only, else both. No living-hero test.
static func record_rank(block: Dictionary, skill: int, mode: int = 1) -> int:
	if block.is_empty(): return 0
	var rank := 0
	for entry in block.skills:
		if int(entry[0]) == skill:
			rank = int(entry[2]) & 0xffff
			break
	var items := 0
	if not bool(block.get("no_items", false)):
		for i in range(EQUIPPED):
			var id := int(block.equipment[i]) if i < block.equipment.size() else 0
			if s16(id) > 0: items += item_skill_bonus(id, skill)
	if mode == 2: return rank
	if mode == 0: return items & 0xffff
	return rank + items

## G-3: the totals of More Info's Combat page 0x551410 (Read, the disassembly for the quirks), from a profile's block
## (`block_from_profile`). 0x54a6f0 is HeroRules.derived on the record's stats (mode 1), 0x556ea0 `skill_term` (called also
## for rank 0, which adds only 0x33's part):
##   combat 0 + term(1); speed 4 + term(4); damage derived 1 (the in-match hero adds 10 more); life 0x550600(class, level,
##   rank 2, Strength) = 0x614604[class] x (level - 1) + 0x6145cc[class] + 3 x Strength + term(2) when the rank is not 0;
##   armor derived 6 and, 0x5504c0, vs piercing / slashing / crushing = derived 6 + term(0x1f) + term(0x17 / 0x1e / 0x20);
##   resistance derived 5 and, 0x550560, vs cold / fire / electricity = derived 5 + **the rank** of 0x1a (its term is
##   computed and dropped, an original quirk: 0x550584 leaves eax unused) + term(0x1c / 0x1b / 0x1d); magic resistance
##   term(0x19); merchant = derived 13 + the rank of 9 (no term) + the data of every type-0xb (discount) power of the
##   seven equipped items, read straight from the item table (no set powers, no hero or "No Hero Items" test).
static func sheet_combat(block: Dictionary) -> Dictionary:
	var stats: Array = block.get("stats", [1, 1, 1, 1])
	var t := tables()
	var klass := int(block.get("class", 0))
	var term := func(skill: int) -> int: return s16(skill_term(skill, s16(record_rank(block, skill, 1)), 1))
	var life_rank := s16(record_rank(block, 2, 1))
	var life := int(t.hp_per_level[klass]) * (int(block.get("level", 1)) - 1) + int(t.hp_base[klass]) + Rules.derived([stats[0], 0, 0, 0], 2, 1)
	if life_rank != 0: life += s16(skill_term(2, life_rank, 1))
	var armor := Rules.derived(stats, 6, 1)
	var plate: int = armor + term.call(0x1f)
	var resist := Rules.derived(stats, 5, 1)
	var ward: int = resist + s16(record_rank(block, 0x1a, 1))
	var merchant := Rules.derived(stats, 13, 1) + s16(record_rank(block, 9, 1))
	for i in range(EQUIPPED):
		var id := s16(int(block.equipment[i])) if i < block.equipment.size() else 0
		if id <= 0: continue
		var it := item(id)
		if it.is_empty(): continue
		for k in range(mini(int(it.power_count), 3)):
			if int(it.powers[k].type) == 0xb: merchant += int(it.powers[k].data)
	return {"combat": s16(Rules.derived(stats, 0, 1) + term.call(1)), "speed": s16(Rules.derived(stats, 4, 1) + term.call(4)),
		"life": s16(life), "damage": s16(Rules.derived(stats, 1, 1)), "armor": s16(armor),
		"vs_armor": [s16(plate + term.call(0x17)), s16(plate + term.call(0x1e)), s16(plate + term.call(0x20))],
		"resistance": s16(resist), "vs_resistance": [s16(ward + term.call(0x1c)), s16(ward + term.call(0x1b)), s16(ward + term.call(0x1d))],
		"magic_resistance": term.call(0x19), "merchant": merchant}

## A skill's term as callers compute it: 0x556b50(p, skill, 1, 1), and when non-zero 0x556ea0(skill, that, 1).
static func skill_effect(block: Dictionary, skill: int) -> int:
	var value := lookup(block, skill, 1, true)
	return s16(skill_term(skill, value, 1)) if value != 0 else 0

## 0x402ea0: every item of the set is in one of the seven equipment slots (hero object present with hp >= 1).
static func set_complete(block: Dictionary, set_index: int) -> bool:
	if not bool(block.get("hero", false)) or s16(int(block.get("hp", 0))) < 1: return false
	var sets: Array = items_data().get("sets", [])
	if set_index < 0 or set_index >= sets.size(): return false
	for needed in sets[set_index].items:
		var found := false
		for i in range(EQUIPPED):
			if s16(int(block.equipment[i])) == int(needed): found = true
		if not found: return false
	return true

## 0x40c380(player, stat): the data of every equipped item power of that type, plus complete set powers. Needs the hero
## object with hit points above -1.
static func item_stat(block: Dictionary, stat: int) -> int:
	if block.is_empty() or not bool(block.get("hero", false)) or s16(int(block.get("hp", 0))) < 0: return 0
	if bool(block.get("no_items", false)): return 0          # setup rows: 0x749c68
	var total := 0
	for i in range(EQUIPPED):
		var id := s16(int(block.equipment[i]))
		if id <= 0: continue
		var it := item(id)
		if it.is_empty(): continue
		for p in it.powers:
			if int(p.type) == stat: total += int(p.data)
	var sets: Array = items_data().get("sets", [])
	for s in range(sets.size()):
		if set_complete(block, s) and int(sets[s].power.type) == stat: total += int(sets[s].power.data)
	# B1-6e (Emulated, tests/hero_spell_e_fixtures.json "item_powers"): x 2 under the hero's effect 0x80 (Spellforge), 0 under
	# a non-allied player's hero's 0x7f (Disjunction); HeroMatch.block carries the factor.
	return s16(s16(total) * int(block.get("item_factor", 1)))

## 0x40c500(player, type, data): the level of every equipped power (and complete set power) with that type and data;
## 0x54fd50 uses it for the hero-skill items of the thirteen magic schools.
static func item_power(block: Dictionary, type: int, data: int) -> int:
	if block.is_empty() or not bool(block.get("hero", false)) or s16(int(block.get("hp", 0))) < 0: return 0
	if bool(block.get("no_items", false)): return 0          # setup rows: 0x749c68
	var total := 0
	for i in range(EQUIPPED):
		var id := s16(int(block.equipment[i]))
		if id <= 0: continue
		var it := item(id)
		if it.is_empty(): continue
		for p in it.powers:
			if int(p.type) == type and int(p.data) == data: total += int(p.level)
	var sets: Array = items_data().get("sets", [])
	for s in range(sets.size()):
		var p: Dictionary = sets[s].power
		if set_complete(block, s) and int(p.type) == type and int(p.data) == data: total += int(p.level)
	# B1-6e (Emulated, fixtures "item_powers"): as 0x40c380, but 0x40c500's 0x7f test skips no ally (school_item_factor).
	return s16(s16(total) * int(block.get("school_item_factor", 1)))

## 0x55ec20(item record, slot): which equipment slot takes an item (by its icon row); backpack slots 7.. and empty
## records take anything.
static func equip_allowed(item_id: int, slot: int) -> bool:
	if s16(item_id) < 1 or slot > 6: return true
	var it := item(item_id)
	var row := int(it.get("iconrow", -1))
	match row:
		0, 1: return slot == 2
		2, 3: return slot == 1
		4, 8: return slot == 3
		5, 10: return slot == 4 or slot == 5
		6, 7: return slot == 0
		9: return slot == 6
	return false

# ------------------------------------------------------------------------------------------- the hero unit (0x54fd50)
## 0x54fd50 for a living hero: the block's derived combat values and the unit fields. record = {class, level, stats,
## skills, equipment}. Returns the unit block (CombatRules keys) plus "mana", "max_mana", "schools", "sight".
static func hero_unit(record: Dictionary) -> Dictionary:
	var block := record.duplicate()
	block["hero"] = true
	block["hp"] = 1
	var t := tables()
	var klass := int(record.get("class", 0))
	var stats: Array = record.stats
	var level := int(record.level)
	var schools: Array = []
	schools.resize(13)
	schools.fill(0)
	for entry in block.skills:
		var sid := int(entry[0])
		if sid >= 10 and sid <= 22 and int(entry[2]) != 0: schools[sid - 10] = s16(int(entry[2]))
	# B1-6e (Read, 0x54fd50 at 0x54ffdf): the match's school bonus 0x70d496 (Increase Casting, PSPR / PARR) before the items.
	var bonus: Array = block.get("school_bonus", [])
	for i in mini(bonus.size(), 13): schools[i] = s16(int(schools[i]) + int(bonus[i]))
	for sid in range(10, 23):
		schools[sid - 10] = s16(int(schools[sid - 10]) + item_power(block, TYPE_HERO_SKILL, sid))
	var lore := lookup(block, 5, 1, true)
	var max_mana := s16(int(t.mana[klass]) + Rules.derived(stats, 8, 1) + (skill_term(5, lore, 1) if lore != 0 else 0))
	var combat := s16(Rules.derived(stats, 0, 1) + skill_effect(block, 1))
	var speed := s16(Rules.derived(stats, 4, 1) + skill_effect(block, 4))
	var armour := s16(int(t.armour[klass]) + Rules.derived(stats, 6, 1) + skill_effect(block, 0x1f))
	var max_hp := s16(int(t.hp_per_level[klass]) * (level - 1) + int(t.hp_base[klass]) + Rules.derived(stats, 2, 1) + skill_effect(block, 2))
	return {"combat": combat, "speed": speed, "mres": s16(Rules.derived(stats, 5, 1)), "max_hp": max_hp, "armour": armour,
		"res1": -1, "res2": -1, "dmg": s16(Rules.derived(stats, 1, 1) + 10), "dtype": 6, "range": 0, "enc": 0, "building": false,
		"hero": true, "sight": 8, "max_mana": max_mana, "mana": max_mana / 10, "schools": schools}

# ------------------------------------------------------------------------------------------- unit methods (hero terms)
## 0x51c6a0 for a hero unit without status effects: 10 + speed attack + 0x2e - slow attack - 0x30 item powers, at least 1.
static func attack_rate(block: Dictionary) -> int:
	var rate := 10 + item_stat(block, 0x2f) + item_stat(block, 0x2e) - item_stat(block, 0x37) - item_stat(block, 0x30)
	return maxi(1, s16(rate))

## 0x51bd10(1) for a hero unit: unit combat - encumbrance + "combat" item powers, at least 1 (the near-hero bonus never
## applies to the hero itself).
static func effective_combat(unit_combat: int, block: Dictionary, encumbrance: int = 0) -> int:
	return maxi(1, s16(unit_combat - encumbrance + item_stat(block, 1)))

## 0x5269a0 for a hero unit: derived 12 + "morale" items + 0x70d622 + Leadership + the race's lord skill; 0x5268c0 halves it.
## Milestone 13 (Read, 0x5269a0): research adds 0x6112e8[PMOX level] (0, 3, 6, 9), POLI (Order of the Lion) +2 and PWRM +5;
## `research` is the owner's completed list.
static func command_value(block: Dictionary, counter_70d622: int = 0, research: Array = []) -> int:
	var value := Rules.derived(block.stats, 0xc, 1) + item_stat(block, 7) + counter_70d622
	value += [0, 3, 6, 9][mini(ProductionRules.research_level(research, "PMOX"), 3)]
	if research.has("POLI"): value += 2
	if research.has("PWRM"): value += 5
	value += s16(skill_term(8, lookup(block, 8, 1, true), 1))
	var lord := race_lord_skill(int(block.get("race", 0)))
	if lord > 0: value += s16(skill_term(lord, lookup(block, lord, 1, true), 1))
	return s16(value)

## 0x5269a0's switch on the player's race: 0..12 -> skills 0x43..0x4f, 13 -> 0x52, 14 -> 0x51, 15 -> 0x50.
static func race_lord_skill(race: int) -> int:
	if race >= 0 and race <= 12: return 0x43 + race
	match race:
		13: return 0x52
		14: return 0x51
		15: return 0x50
	return 0

## 0x526cf0 for a hero unit: derived 13 + Merchant (x1) + "discount" items; costs are cost * 100 / (value + 100).
static func price_value(block: Dictionary) -> int:
	return s16(Rules.derived(block.stats, 0xd, 1) + skill_effect(block, 9) + item_stat(block, 0xb))

## 0x5267b0 for a hero unit: conversion radius = block +0x192 (Charisma + 5 from the match start) + "command" item
## powers (type 10), +8 with 0x70d5a0 (PDKL Dark Lord, G-1: pass the owner's research list); the conversion routine
## 0x523af0 caps it at 19.
static func conversion_radius(block: Dictionary, research: Array = []) -> int:
	var dark_lord := 8 if research.has("PDKL") else 0
	return mini(s16(int(block.get("conversion_radius", 0)) + item_stat(block, 10) + dark_lord), 19)

## 0x526c80 for a hero unit: conversion power = level / 2 + 8 + item powers of type 4 (no Items.xml name maps to 4).
static func conversion_power(block: Dictionary) -> int:
	return s16(int(block.level) / 2 + 8 + item_stat(block, 4))

## 0x51c460(1) hero terms: unit speed - encumbrance + "speed" (5) + 0x2e - "slow" (0x38) - 0x30 item powers.
static func movement_speed(unit_speed: int, block: Dictionary, encumbrance: int = 0) -> int:
	return maxi(1, s16(unit_speed - encumbrance + item_stat(block, 5) + item_stat(block, 0x2e) - item_stat(block, 0x38) - item_stat(block, 0x30)))

## Parity pass 4: the hero's mana lives in its record (0x70931c current, 0x70931a maximum; 0x51b2c0 reads them for a
## hero). 0x4a4560 sets the maximum at the spawn (0x550660: the class table + derived 8 + Lore, the unit block's
## max_mana) and the current value to min(maximum, record word +0x14 = the level; 0x409ef0 is its XP threshold), so a
## level-1 hero starts with 1 (the unit block's max / 10 of 0x54fd50 is the unit field +0x208, not shown for heroes).
static func start_mana(max_mana: int, level: int) -> int:
	return mini(max_mana, level)

## 0x51b580 for a living hero (Read): the mana interval 20000 / derived 9 * 100 / (0x611220[PMRX level] + Meditation's
## term (skill 6, 0x556b50 / 0x556ea0) + "mana regen" item powers 0x21 (0x40c380)); the aura nodes 0x577520(0x21) are
## Open (0). 0x51b6b0 then adds ceil(1000 / rate) points every that many rate periods while the mana is below its maximum.
const MANA_RESEARCH := [100, 150, 200, 300, 400, 500, 600, 700, 800, 0]   # 0x611220
const MANA_COMPUTER := [0, 0, 0, 20, 30, 40, 60, 40]                     # 0x611254[slot AI value]: subtracted for computers
static func mana_rate(block: Dictionary, research: Array = []) -> int:
	var interval: int = 20000 / maxi(1, Rules.derived(block.stats, 9, 1))
	var percent: int = MANA_RESEARCH[mini(ProductionRules.research_level(research, "PMRX"), 9)] + skill_effect(block, 6) + item_stat(block, 0x21)
	if percent == 0: return 0
	return CombatRulesShim.tdiv(interval * 100, percent)

## 0x51b460 for a living hero: the regeneration interval in ms per point of 1000 (0x51b820 heals ceil(1000 / rate) hit
## points every that many ms): 20000 / derived 3 (Strength / 3 + 1) * 100 / (100 + Regeneration x20 + "life regen").
static func regeneration_rate(block: Dictionary) -> int:
	var interval: int = 20000 / maxi(1, Rules.derived(block.stats, 3, 1))
	var percent: int = 100 + skill_effect(block, 3) + item_stat(block, 0x2c)
	if percent == 0: return 0
	return CombatRulesShim.tdiv(interval * 100, percent)

# ------------------------------------------------------------------------------------------- armour (0x5260a0 / 0x526b70 / 0x525c80)
## Magic armour 0x526b70(1): unit +0x96 + (hero: "resistance" items) + the owner's living hero's Warding x10. owner_block
## is the block of the unit's owner (Warding protects every unit of that player).
static func magic_armour(mres: int, is_hero: bool, own_block: Dictionary, owner_block: Dictionary) -> int:
	var value := mres
	if is_hero: value += item_stat(own_block, 6)
	value += skill_effect(owner_block, 0x18)
	return s16(value)

## 0x5260a0(1): armour +0xa4 + (hero) "armor" items, at least 0 after the +0x20c reduction (0 here).
static func armour_value(armour: int, is_hero: bool, block: Dictionary) -> int:
	var value := armour + (item_stat(block, 0x18) if is_hero else 0)
	return maxi(0, s16(value))

## 0x525c80(1): the seven-entry armour table by damage type, with the hero target's skill and item terms.
static func armour_table(unit: Dictionary, own_block: Dictionary, owner_block: Dictionary) -> Array:
	var is_hero := bool(unit.get("hero", false)) and not own_block.is_empty()
	var a := armour_value(int(unit.armour), is_hero, own_block)
	var m := magic_armour(int(unit.mres), is_hero, own_block, owner_block)
	var t := [a, m, m, m, 0, a, a]
	if not is_hero: return t
	var b := own_block
	t[3] = s16(int(t[3]) + item_stat(b, 0x50))
	t[1] = s16(int(t[1]) + item_stat(b, 0x58))
	t[4] = s16(int(t[4]) + item_stat(b, 0x51))
	t[2] = s16(int(t[2]) + item_stat(b, 0x59))
	t[0] = s16(int(t[0]) + skill_effect(b, 0x17))
	t[5] = s16(int(t[5]) + skill_effect(b, 0x20))
	t[6] = s16(int(t[6]) + skill_effect(b, 0x1e))
	t[3] = s16(int(t[3]) + skill_effect(b, 0x1b))
	t[1] = s16(int(t[1]) + skill_effect(b, 0x1c))
	t[2] = s16(int(t[2]) + skill_effect(b, 0x1d))
	t[4] = s16(int(t[4]) + skill_effect(b, 0x19))
	var elemental := skill_effect(b, 0x1a)
	for i in [3, 1, 2]: t[i] = s16(int(t[i]) + elemental)
	return t

# ------------------------------------------------------------------------------------------- the hero's attack (0x526310)
## 0x526310(1) hero terms: damage + item type 0x17 + Mighty Blow x2 + the weapon's (slot 2) damage powers, which also set
## the damage type: piercing 0, ice 1, electricity 2, fire 3, magic 4, crushing 5, slashing 6.
static func attack(dmg: int, dtype: int, block: Dictionary) -> Dictionary:
	var bonus := item_stat(block, 0x17) + skill_effect(block, 0x22)
	var weapon := s16(int(block.equipment[2])) if block.equipment.size() > 2 else 0
	if bool(block.get("no_items", false)): weapon = 0         # setup rows: 0x5265c2 tests 0x749c68 before the weapon slot
	if weapon > 0:
		var it := item(weapon)
		for p in it.get("powers", []):
			var kind := int(p.type)
			var to: int = {0x5b: 6, 0x5c: 5, 0x5a: 0, 0x5d: 3, 0x5e: 1, 0x5f: 2, 0x60: 4}.get(kind, -1)
			if to >= 0:
				bonus += int(p.data)
				dtype = to
	return {"dmg": s16(dmg + bonus), "dtype": dtype}

## 0x42ace0 hero-attacker terms against a unit target with STATUS flags (+0x1c0): the slayer skills add their term to the
## damage before the roll bands. Against buildings Demolition adds its term.
const SLAYERS := [[0x27, 0x2], [0x28, 0x38], [0x23, 0x1], [0x25, 0x1000], [0x29, 0x100], [0x24, 0x4], [0x26, 0x800000],
	[0x2b, 0x2000000], [0x2c, 0x8000000], [0x31, 0x80], [0x30, 0x800], [0x2f, 0x1000000], [0x32, 0x20000000]]

static func slayer_bonus(block: Dictionary, target_flags: int) -> int:
	var total := 0
	for pair in SLAYERS:
		if target_flags & int(pair[1]) == 0: continue
		total += skill_effect(block, int(pair[0]))
	return total

class CombatRulesShim:
	static func tdiv(a: int, b: int) -> int:
		var q: int = absi(a) / absi(b)
		return q if (a >= 0) == (b >= 0) else -q
