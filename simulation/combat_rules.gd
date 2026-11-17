extends RefCounted
## Original combat numerics (milestone 8). Evidence labels and limits: COMBAT_RESEARCH.md.
## Emulated = tests/combat_fixtures.json from tools/emulate_combat.py (unmodified executable under Unicorn).
## Everything the executable derives from player upgrades, spells, status effects, items and hero skills is
## absent here (those inputs are zero in the emulation and not simulated yet).

const HeroEffects = preload("res://simulation/hero_effects.gd")
const DAMAGE_TYPES := 7           # armour/resist tables are indexed 0..6 by the attack's damage type (ARM +0x34)
const MELEE_HIT_FRAME := 6        # AHKX ANI slot 2 (+0x18): the f animation calls the hit handler at entry 6
const MELEE_FRAMES := 16          # AHKX ANI slot 2 frame count (entries 0..16)
const BASE_ATTACK_RATE := 10      # 0x51c6a0 with no haste/slow
const NEAR_HERO_COMBAT := 4       # 0x51bd10: unit flag +0x190 (own living hero within range) adds 4 (2 with flag 0x4)
# Resist/weak index (ARM +0x2a / +0x2c) -> damage types it marks (0x525c80 jump tables).
const RESIST_GROUPS := [[0], [1], [2], [3], [4], [5], [6], [0, 6, 5], [0, 6], [3, 1, 2], [0, 1, 2, 3, 4, 5, 6]]

static func tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

static func s16(value: int) -> int:
	value &= 0xffff
	return value - 0x10000 if value & 0x8000 else value

# --------------------------------------------------------------------------------- stat blocks
static func i16(bytes: PackedByteArray, offset: int) -> int:
	return s16(bytes[offset] | (bytes[offset + 1] << 8))

## ARM record (332 bytes, decrypted) -> unit combat block. Offsets are the ones the executable copies into the
## unit (0x43bfb0-style loader at 40110): combat +0x1e, speed +0x20, magic armour +0x22, hit points +0x24,
## armour +0x28, resist +0x2a, weak +0x2c, damage +0x32, damage type +0x34, range +0x36.
static func unit_stats(raw_hex: String) -> Dictionary:
	var b: PackedByteArray = raw_hex.hex_decode()
	return {"combat": i16(b, 0x1e), "speed": i16(b, 0x20), "mres": i16(b, 0x22), "max_hp": i16(b, 0x24),
		"armour": i16(b, 0x28), "res1": i16(b, 0x2a), "res2": i16(b, 0x2c), "dmg": i16(b, 0x32),
		"dtype": i16(b, 0x34), "range": i16(b, 0x36), "enc": 0, "building": false,
		# R-1: the words a promotion raises (0x40daa0) with the +0xae / +0xb0 consumers still Open (COMBAT_RESEARCH.md "R-1").
		"word_ae": i16(b, 0x5a), "word_b0": i16(b, 0x5c),
		# Milestone 13: ARM +0x100 attack layers (0x51da60: 0 none, 1 ground only, 2 air only, 3 both) and +5 movement type.
		"layers": i16(b, 0x100), "movement": b[5],
		# Missile launch offsets per facing, ARM +0x10c + 4 * facing (read by the unit sprite's 0x5364e0 / 0x536490).
		"launch": range(8).map(func(f): return [i16(b, 0x10c + 4 * f), i16(b, 0x10e + 4 * f)]) if b.size() >= 0x12c else []}

## BUI record (200 bytes) -> building combat block: combat +0x24, magic armour +0x28, hit points +0x2a, armour +0x2e.
static func building_stats(raw_hex: String) -> Dictionary:
	var b: PackedByteArray = raw_hex.hex_decode()
	return {"combat": i16(b, 0x24), "mres": i16(b, 0x28), "max_hp": i16(b, 0x2a), "armour": i16(b, 0x2e),
		"res1": -1, "res2": -1, "range": 0, "dmg": 0, "dtype": 0, "enc": 0, "building": true}

## Hero in-match block (0x54fd50, Warrior class 0): derived stats of the profile's base stats. The skill and item terms
## are not in this block: combat.gd combat_block adds them (HeroEffects, Emulated in milestone 11) and _drain adds the life
## drain (0x526f40: skill 0x35 + item power 0x3c + effect 0x3c; G-2 Emulated, tests/rule_gaps_fixtures.json "drain").
## stats = [Strength, Dexterity, Intelligence, Charisma].
static func hero_stats(stats: Array, level: int, derived: Callable) -> Dictionary:
	var max_hp: int = 240 + 4 * (level - 1) + int(derived.call(stats, 2, 1))
	return {"combat": int(derived.call(stats, 0, 1)), "speed": int(derived.call(stats, 4, 1)), "mres": int(derived.call(stats, 5, 1)),
		"max_hp": max_hp, "armour": 10 + int(derived.call(stats, 6, 1)), "res1": -1, "res2": -1,
		"dmg": int(derived.call(stats, 1, 1)) + 10, "dtype": 6, "range": 0, "enc": 0, "building": false, "hero": true}

# --------------------------------------------------------------------------------- arrow resistance (B1-6b)
## 0x527040 (Emulated: tests/hero_spell_b_fixtures.json "arrows", tools/emulate_hero_spells_b.py runs 0x5427e0 up to
## 0x542ab2): the unit types that resist missiles. AOIX also needs its owner's PNOP (0x70d5a7), ALBX its owner's PDEF
## (0x70d5ae; both from 0x437f70's research switch); a hero resists while its effect 0x52 (Resist Missile) is active.
const ARROW_RESISTANT := ["ADGX", "ADSX", "AUIX", "ARJX", "AUCX", "AADU"]

static func arrow_resistant(type_id: String, hero_resisting: bool, pnop: bool, pdef: bool) -> bool:
	if hero_resisting: return true
	if type_id in ARROW_RESISTANT: return true
	if type_id == "AOIX": return pnop
	if type_id == "ALBX": return pdef
	return false

## 0x5427e0 (disassembly 0x5429bc..0x542a4d; Emulated): after armour and the elevation factor, a positive missile damage of
## class +0x67a 0 or 0xb against a resisting unit becomes damage >> 4, at least 1 (class 0xb: 2), unless the shooter's
## owner has PHUN (0x70d5c3; a missile without a shooter, owner -1, is always resisted). Any other class keeps its damage.
static func arrow_damage(damage: int, missile_class: int, resisting: bool, shooter_phun: bool) -> int:
	if damage <= 0 or (missile_class != 0 and missile_class != 0xb) or not resisting or shooter_phun: return damage
	var least := 2 if missile_class == 0xb else 1
	return maxi(damage >> 4, least)

# --------------------------------------------------------------------------------- to-hit and damage
const FAULT_DAMAGE := -1
## Game-mode byte 0x748946 (set by the main-menu handler 0x41da80 to 0, 1, 2, 3 or 4 by button). Emulated: with 3 the
## swing attaches no crit side effect and dtype 0 crits keep armour; the draws are unchanged. A skirmish uses 0 (G-2,
## Read: SKIRMISH_RESEARCH.md, the Skirmish button 0x98 calls 0x41da80(1), whose case 1 stores 0), the rebuild's default.
const MODE_NO_CRIT_EFFECTS := 3
const EFFECT_BURN := 1                 # 0x42ace0: a critical melee hit of damage type 3 / 0xb; 0x51abe0 sends message 0x204 (B2-1)

## Guard for every lookup indexed by damage type (8-fix, Provisional). The original has no such check: 0x42bbf0 reads
## `table + dtype * 2` and the swing reads its local armour buffer the same way, so types 7+ or negative read neighbouring
## bytes (emulated: armour 0 with the harness's zeroed neighbours, crit effect still chosen by 0x42ba7c; 0x7fff reads
## unmapped memory). No ARM record has such a type (all 199 scanned: 0..6). The rebuild treats it like the divide fault:
## the swing or missile hit is dropped and no number is drawn.
static func valid_dtype(dtype: int) -> bool:
	return dtype >= 0 and dtype < DAMAGE_TYPES
## 0x51bd10(1) for a plain unit: combat - encumbrance, +4 near the owner's hero (+2 for STATUS bit 2, value 4: Read,
## decompile of 0x51bd10, playtest 2026-11-11), never below 1.
static func effective_combat(unit: Dictionary) -> int:
	# B1-6c (REVIEW_HERO_SPELLS_C.md D1, Emulated R1): an active 0x46 (Psychic Blast) is 0x51bd10's last test: exactly 1.
	if unit.get("stunned", false): return 1
	var value: int = int(unit.combat) - int(unit.get("enc", 0))
	if unit.get("near_hero", false): value += NEAR_HERO_COMBAT / 2 if (int(unit.get("flags", 0)) & 4) != 0 else NEAR_HERO_COMBAT
	return maxi(1, value)

## Resist(+1)/weak(-1) flag array of the target (0x525c80): resist index first, weak index overwrites.
static func resist_flags(unit: Dictionary) -> Array:
	var flags := [0, 0, 0, 0, 0, 0, 0]
	var resist := int(unit.get("res1", -1))
	var weak := int(unit.get("res2", -1))
	if resist >= 0 and resist < RESIST_GROUPS.size():
		for t in RESIST_GROUPS[resist]: flags[t] = 1
	if weak >= 0 and weak < RESIST_GROUPS.size():
		for t in RESIST_GROUPS[weak]: flags[t] = -1
	return flags

## Armour by damage type (0x525c80 / 0x52e810): [armour, magic, magic, magic, 0, armour, armour].
## A unit block may carry its resolved table ("armour_table", milestone 11: the hero target's skill/item terms and the
## owner hero's Warding, HeroEffects.armour_table).
static func armour_table(unit: Dictionary) -> Array:
	if unit.has("armour_table"): return unit.armour_table
	var armour := int(unit.armour)
	var magic := int(unit.mres)
	return [armour, magic, magic, magic, 0, armour, armour]

## 0x42ace0 (melee swing, chosen when the attacker's range is 0 or 1): one 1..100 roll, then the damage.
## attacker: combat, dmg, dtype (0..6), range, enc, near_hero. target: the same plus res1/res2, "building".
## distance: Chebyshev cell distance (unit targets beyond 5 cells lose crit side effects only).
## Returns {damage, effect, param, code, roll}; {"fault": true} when the original divides by zero
## (both combat skills become 0 after the ranged >> 2).
## 0x42ace0, non-hero attacker against a unit (target STATUS +0x1c0), in the original's order (decompile 28563-28770).
## G-1: Emulated for every one of the 199 ARM types against every single STATUS bit, a hero target and the ACSH / ACCO
## types under every research flag the block reads (tests/combat_multiplier_fixtures.json, tools/emulate_combat.py
## --multipliers; RACE_DATA_RESEARCH.md). Attacker flags: "pgra" / "ppal" (Knight cavalry), "ptor" / "pfal" (Slayer /
## Doom Knight), "pdk_level" (PDK0-2 level, 0x437f70); target: "pcow" (its owner's PCOW 0x70d5b5), "hero".
## Each row: attacker types, target STATUS mask (any bit), factor.
const TYPE_MULTIPLIERS := [
	[["AAAR", "AHGX"], 0x8000000, 2],          # Archon, Inquisitor vs Evil
	[["AADE"], 0x2000000, 2],                  # Daemon vs Good
	[["ABGX"], 0xc0000000, 3],
	[["ADIX"], 0x38, 3],                       # Dwarf Infantry vs the elves
	[["AWIX", "AKIX"], 0x2, 3],
	[["AWCX"], 0x100, 3],
	[["APDX"], 0x20000000, 2],
	[["AHIX", "AHJX", "ADJX"], 0x20000, 3],   # Berserkers vs cavalry
]
static func unit_multiplier(attacker: Dictionary, target_flags: int, target: Dictionary = {}) -> int:
	if bool(attacker.get("hero", false)): return 1
	var type := String(attacker.get("type_id", ""))
	var m := 1
	if type in ["AHFX", "AHDX", "AHEX"]:
		if bool(attacker.get("pgra", false)) and (target_flags & 0x4) != 0: m *= 3
		elif bool(attacker.get("ppal", false)): m *= 2
	if type in ["AULX", "AUAX"]:
		if bool(attacker.get("pfal", false)) and (target_flags & 0x1) != 0: m *= 3
		elif bool(attacker.get("ptor", false)): m *= 2
	# Every type matches at most one rule, so the original's order cannot change the product.
	for row in TYPE_MULTIPLIERS:
		if type in row[0] and (target_flags & int(row[1])) != 0: m *= int(row[2])
	if type == "AOIX" and bool(target.get("pcow", false)) and (target_flags & 0x40000) != 0: m *= 2
	if type == "AKCX" and bool(target.get("hero", false)): m *= 3            # against a hero (+0xb4)
	if type == "AECX" and (target_flags & 0x1000) != 0: m *= int(attacker.get("pdk_level", 0)) + 1
	return m

## 0x42ace0 (Emulated, the same sweep): the swing's 1..100 roll is drawn and then replaced by 10 for AOMX against an ACSH and
## ASCA against an ACCO (non-hero attacker, unit target).
static func forced_roll(attacker: Dictionary, target: Dictionary) -> int:
	if bool(attacker.get("hero", false)) or bool(target.get("building", false)): return 0
	var pair := [String(attacker.get("type_id", "")), String(target.get("type_id", ""))]
	return 10 if pair == ["AOMX", "ACSH"] or pair == ["ASCA", "ACCO"] else 0

## 0x5273c0 (Emulated for all 199 ARM types, tests/race_data_fixtures.json): the live STATUS of a non-hero unit is its
## Army.cfg STATUS plus fixed bits by type (titans 0x200 and their race bit, the DragonLiche Undead 0x4). Heroes take
## HeroEffects.HERO_RACE_FLAGS by the hero's race (0x5273c0's hero switch, Emulated for all 16).
const LIVE_STATUS_BITS := {"ATKX": 0x220, "ATEX": 0x208, "ATBX": 0x240, "AADU": 0x1004, "ATAX": 0x4200, "ATDX": 0x202,
	"ATFX": 0x80200, "ATGX": 0x800200, "ATHX": 0x201, "ATRX": 0x600, "ATOX": 0x300, "ATLX": 0x1000200, "ATMX": 0x280,
	"ATPX": 0x201, "ATUX": 0x204, "ATVX": 0x800200, "ATWX": 0x210}
static func live_status(type_id: String, army_bits: int) -> int:
	return army_bits | int(LIVE_STATUS_BITS.get(type_id, 0))

## 0x51b820, the poisoned branch (Read): a poisoned unit (+0x1a4, set by 0x51bfb0: first tick at now + magic armour * 128 +
## 500, cured 600 s later) loses 1 hit point per second, 2 while any active player has Melkor's Curse (PMCU), and never
## below max / 8 (then it waits another second). Day / night is not simulated, so the Undead daytime return before it never
## applies. `state`: hp, max_hp, poison_next_ms, poison_until_ms (mutated). Returns the hit points lost.
const POISON_MS := 600000
static func poison_start(state: Dictionary, now_ms: int, magic_armour: int):
	state["poisoned"] = true
	state["poison_next_ms"] = now_ms + magic_armour * 0x80 + 500
	state["poison_until_ms"] = now_ms + POISON_MS

static func poison_tick(state: Dictionary, now_ms: int, curse: bool) -> int:
	if not bool(state.get("poisoned", false)): return 0
	if int(state.poison_until_ms) < now_ms:
		state["poisoned"] = false
		return 0
	if int(state.hp) <= int(state.max_hp) >> 3:
		state["poison_next_ms"] = now_ms + 1000
		return 0
	if int(state.poison_next_ms) >= now_ms: return 0
	var loss := 2 if curse else 1
	state["hp"] = int(state.hp) - loss
	state["poison_next_ms"] = now_ms + 1000
	return loss

## 0x42ace0 against a building: the Battering Ram (ASBA) x10 (AAEE x4, ADGX x2), after Demolition.
static func building_multiplier(attacker: Dictionary) -> int:
	if bool(attacker.get("hero", false)): return 1
	match String(attacker.get("type_id", "")):
		"ASBA": return 10
		"AAEE": return 4
		"ADGX": return 2
	return 1

## 0x51da60 (Read): an attacker whose ARM +0x100 is 0 takes no attack order; 1 refuses a flying target (movement type
## 1), 2 refuses ground and water targets (types 0 and 2). Buildings can be attacked by any other value. Heroes: 3.
static func can_hit(attacker: Dictionary, target: Dictionary) -> bool:
	var layers := int(attacker.get("layers", 3))
	if layers == 0: return false
	if bool(target.get("building", false)): return true
	var movement := int(target.get("movement", 0))
	if layers == 1 and movement == 1: return false
	if layers == 2 and (movement == 0 or movement == 2): return false
	return true

static func swing(attacker: Dictionary, target: Dictionary, rng, distance: int = 0, game_mode: int = 0) -> Dictionary:
	if not valid_dtype(int(attacker.dtype)): return {"fault": true, "reason": "damage type"}
	var a_skill := effective_combat(attacker)
	if int(attacker.range) > 0: a_skill = a_skill >> 2
	var d_skill: int
	var is_building: bool = target.get("building", false)
	if is_building:
		d_skill = int(target.combat)
	else:
		d_skill = effective_combat(target)
		if int(target.range) > 0: d_skill = d_skill >> 2
	if a_skill + d_skill == 0: return {"fault": true}
	var hit := tdiv(a_skill * 100, d_skill + a_skill)
	var crit4 := maxi(1, tdiv(hit, 12))
	# Milestone 11 (Emulated, tests/hero_skill_fixtures.json): a hero attacker's crit bonus (Weaponmaster x2 + "critical
	# hit" items, [esp+0x44]) widens the x2 band.
	var crit2 := maxi(2, tdiv(hit, 6)) + int(attacker.get("crit_bonus", 0))
	# G-1 (Emulated, BATCH1_RESEARCH.md 2.2): a non-hero Khazrimi Guard ADLX doubles the x2-band bound (add ebx, ebx at 0x42b827).
	if String(attacker.get("type_id", "")) == "ADLX" and not bool(attacker.get("hero", false)): crit2 *= 2
	var roll: int = rng.roll(1, 100, 0)
	if forced_roll(attacker, target) != 0: roll = forced_roll(attacker, target)
	var dtype := int(attacker.dtype)
	var damage := s16(int(attacker.dmg))
	# The attacker-type multipliers of 0x42ace0 before the hero terms (milestone 13; G-1: every race, Emulated).
	if not is_building: damage = s16(damage * unit_multiplier(attacker, int(target.get("flags", 0)), target))
	# Hero attacker: the slayer skills by the target's STATUS flags (+0x1c0); Demolition against buildings.
	if is_building: damage = s16(s16(damage + int(attacker.get("demolition", 0))) * building_multiplier(attacker))
	elif attacker.has("slayer_block"): damage = s16(damage + HeroEffects.slayer_bonus(attacker.slayer_block, int(target.get("flags", 0))))
	var code := 4
	if roll <= crit4:
		code = 0
		damage = s16(damage * 4)
	elif roll <= crit2:
		code = 1
		damage = s16(damage * 2)
	elif roll <= hit:
		code = 2
	elif roll <= hit * 2:
		code = 3
		damage = tdiv(damage, 2)
	else:
		code = 4
		damage = 1
	if not is_building and distance > 5: code = 4
	var effect := 0
	var param := 0
	var armour_ignored := false
	# Assassin (0x526e70 for a hero attacker: Assassin + 4 + "assassin" items; minus half the target hero's level, at least 1;
	# 0 against the same owner, an animal or a missed swing; [esp+0x38] roll at or below it): damage 5000 and effect 4 (no crit
	# effect), still reduced by armour below.
	var assassin := int(attacker.get("assassin", 0))
	if assassin != 0 and not is_building:
		if target.get("hero", false): assassin = maxi(1, assassin - tdiv(int(target.get("hero_level", 1)), 2))
		if int(attacker.get("owner", -1)) == int(target.get("owner", -2)) or target.get("animal", false) or code == 4: assassin = 0
	if not is_building and roll <= assassin:
		damage = 5000
		effect = 4
	elif not is_building and code <= 1 and game_mode != MODE_NO_CRIT_EFFECTS:
		match dtype:
			3, 11: effect = 1
			1: effect = 6
			2: effect = 9; param = 0x28
			4: effect = 7
			0: effect = 10; armour_ignored = true
			5: effect = 8; param = 5
			6: effect = 11; param = 0x32 if damage > 0x32 else (damage & 0xff)
	# Ignore Armor (x10, [esp+0x48]) lowers the armour (not below 0) and the resist reduction (50 - 5 per point, [esp+0x4c]).
	var ignore := int(attacker.get("ignore_armour", 0))
	var resist_cut := mini(50, 5 * ignore)
	var armour: int = 0 if armour_ignored else maxi(0, int(armour_table(target)[dtype]) - ignore)
	var reduced: int
	if armour >= 4 * damage: reduced = tdiv(damage, 5)
	elif armour >= 3 * damage: reduced = (damage + (3 if damage < 0 else 0)) >> 2
	elif armour >= 2 * damage: reduced = tdiv(damage, 3)
	elif armour >= damage: reduced = tdiv(damage, 2)
	else: reduced = tdiv(armour, 2) - armour + damage
	reduced = s16(reduced)
	var flag := int(resist_flags(target)[dtype])
	if flag == 1: reduced = s16(reduced - tdiv((50 - resist_cut) * reduced, 100))
	elif flag == -1: reduced = s16(reduced + tdiv(reduced, 2))
	return {"damage": maxi(1, reduced), "effect": effect, "param": param, "code": code, "roll": roll}

## 0x536e30: the attack-start routine. The message roll (1..100, 7 bits) is drawn first; attackers with range <= 1
## then call the melee swing 0x42ace0 (second draw) and send its damage in a 10-bit field; ranged attackers send their raw
## damage and effect 0 (the damage is resolved by the missile). Emulated against the real routine ("attack_start").
static func attack_start(attacker: Dictionary, target: Dictionary, rng, distance: int = 0, game_mode: int = 0) -> Dictionary:
	var message_roll: int = rng.roll(1, 100, 0)
	if int(attacker.range) > 1:
		return {"message_roll": message_roll, "damage": int(attacker.dmg) & 0x3ff, "effect": 0, "param": 0, "ranged": true}
	var result: Dictionary = swing(attacker, target, rng, distance, game_mode)
	if result.has("fault"): return {"message_roll": message_roll, "fault": true, "ranged": false}
	return {"message_roll": message_roll, "damage": int(result.damage) & 0x3ff, "effect": int(result.effect), "param": int(result.param),
		"ranged": false, "code": int(result.code), "roll": int(result.roll)}

## 0x42bbf0: armour/resist reduction applied by a missile at impact (mode 0 x4, 1 x2, 2 plain, 3 half, 4 one).
## Returns FAULT_DAMAGE for a damage type outside 0..6 (see valid_dtype); the caller drops that hit.
static func armour_tail(damage: int, mode: int, dtype: int, armour: Array, flags: Array) -> int:
	if not valid_dtype(dtype): return FAULT_DAMAGE
	var d: int = s16(damage)
	match mode:
		0: d = d << 2
		1: d = d << 1
		3: d = d >> 1
		4: d = 1
	var flag := int(flags[dtype])
	if flag == 1: d += -tdiv(d, 2)
	elif flag == -1: d += tdiv(d, 2)
	var a := int(armour[dtype])
	if a < d * 4:
		if a < d * 3:
			if a < d * 2:
				if d <= a: d = tdiv(d, 2)
				else: d += tdiv(a, 2) - a
			else:
				d = tdiv(d, 3) + 2 * (d >> 31)
		else:
			d = (d + ((d >> 31) & 3)) >> 2
	else:
		d = tdiv(d, 5)
	if d < 2: return 1
	return s16(d)

# --------------------------------------------------------------------------------- timing
static var _attack_timing: Dictionary = {}

## 0x537060: ms per f-animation entry. base = max(500, (150 - X) * 10) for ordinary units (X = 0x40dc80, 0 without
## upgrades), (100 - derived attack speed) * 10 for the hero; rate is 0x51c6a0 (10 plain).
static func attack_entry_ms(is_hero: bool, player_x: int, hero_attack_stat: int, rate: int = BASE_ATTACK_RATE, frames: int = MELEE_FRAMES) -> int:
	var base: int
	if is_hero: base = (100 - hero_attack_stat) * 10
	else: base = maxi(500, (150 - player_x) * 10)
	return ((base * 10) / rate) / frames

## simulation/attack_timing.json: type id -> [ANI slot 2 frames, hit entry, latency frame, latency ms].
static func attack_timing() -> Dictionary:
	if _attack_timing.is_empty():
		_attack_timing = JSON.parse_string(FileAccess.get_file_as_string("res://simulation/attack_timing.json")).units
	return _attack_timing

## 0x537060's entry times with Army.cfg's latency (0x528cd0 +0x214 = time << 16 | frame, Emulated, tools/emulate_attack_time.py):
## entries 1..frame - 1 each come `time` ms later than the even spacing. `latency` is [frame, ms]; [0, 0] without one.
static func attack_entry_time(i: int, entry_ms: int, latency: Array = [0, 0]) -> int:
	return i * entry_ms + int(latency[1]) * mini(i, maxi(int(latency[0]) - 1, 0))

## The entry in progress `elapsed` ms into the sequence (the sprite's frame): the inverse of attack_entry_time.
static func attack_entry_at(elapsed: int, entry_ms: int, latency: Array = [0, 0]) -> int:
	var delayed := maxi(int(latency[0]) - 1, 0)
	var slow := entry_ms + int(latency[1])
	if elapsed < delayed * slow: return elapsed / maxi(1, slow)
	return delayed + (elapsed - delayed * slow) / maxi(1, entry_ms)

## Milliseconds after the swing starts when the hit handler runs (entry MELEE_HIT_FRAME is due).
static func hit_delay_ms(entry_ms: int) -> int:
	return MELEE_HIT_FRAME * entry_ms

static func swing_duration_ms(entry_ms: int) -> int:
	return MELEE_FRAMES * entry_ms

## Attack range test of the order executor 0x51ea20 (case 6): the unit may swing when
## dist <= range + 1 and dist >= the minimum range of long-range types. Melee: dist <= 1.
static func in_attack_range(distance: int, range_value: int) -> bool:
	return distance <= range_value + 1

# --------------------------------------------------------------------------------- relations and sight
## 0x748915[b + a * 7] (match setup 0x4dea..): 1 for self and same non-zero team, 0 for everyone else, including
## the neutral slot 6. Hostile = 0.
static func hostile(teams: Array, a: int, b: int) -> bool:
	if a == b: return false
	if a == 6 or b == 6: return true
	var team_a := int(teams[a])
	return team_a == 0 or team_a != int(teams[b])

## Sight mask of the full-circle tier (sprite +0x94 = 4): a cell is lit when trunc(hypot(dx, dy)) <= radius.
## Emulated for radius 6..14 against 0x47e500 (identical for all eight facings).
static func sight_covers(dx: int, dy: int, radius: int) -> bool:
	return int(sqrt(float(dx * dx + dy * dy))) <= radius

## G-2 (Emulated: tests/rule_gaps_fixtures.json "garrison", 0x52ae70 / 0x52b0c0 with 0x5877a0 stubbed to "takes a
## garrison"): each occupant of a tower ({"hero", "status" (Army.cfg STATUS), "computer" (0x70d6a4 of its owner)}).
## Combat (0x52ae70(1), added to +0x68 and the difficulty term): a hero +6; STATUS bit 18 (0x40000, the shooters) 0;
## bit 15 (0x8000) +6 (+7 for a computer's unit); else +3 (+4).
static func garrison_combat(occupants: Array) -> int:
	var total := 0
	for o in occupants:
		if bool(o.hero): total += 6
		elif (int(o.status) >> 18) & 1: continue
		elif (int(o.status) >> 15) & 1: total += 7 if bool(o.computer) else 6
		else: total += 4 if bool(o.computer) else 3
	return total

## The rate level (0x52b0c0(1), added to +0x6a; 0x52b150 takes 0x6114bc[min(16, level)] after every shot): a hero +2;
## bit 18 0; bit 15 +2; else +1.
static func garrison_rate(occupants: Array) -> int:
	var total := 0
	for o in occupants:
		if bool(o.hero): total += 2
		elif (int(o.status) >> 18) & 1: continue
		elif (int(o.status) >> 15) & 1: total += 2
		else: total += 1
	return total

## 0x40ac00 for a building's shot descriptor (Read): damage type 0xb -> EMA2; the Building.cfg row's missile when the
## descriptor's type is the row's (0x5876a0; the rebuild has the rows' missiles as `building_missile` for the tower's own
## type); else by type: 3 EMF0, 4 EMM0, 2 EMM2, 1 EMIS, 6 EMM3, other EMA0.
static func building_missile_for(dtype: int, own_dtype: int, building_missile: String) -> String:
	if dtype == 0xb: return "EMA2"
	if dtype == own_dtype and building_missile != "": return building_missile
	match dtype:
		3: return "EMF0"
		4: return "EMM0"
		2: return "EMM2"
		1: return "EMIS"
		6: return "EMM3"
	return "EMA0"
