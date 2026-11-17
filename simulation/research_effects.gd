extends RefCounted
## Research effects (milestone 13, PRODUCTION_RESEARCH.md "Milestone 13"). Completion 0x436500 adds per-player, per-unit-type
## upgrade bytes through 0x438760 (table 0x70b3b8: combat, unused, speed, damage, range, resistance) and sets per-player
## flags; the unit getters read them live, so an upgrade applies at once to existing and new units of the type (the
## sight refresh 0x438cf0 is the only explicit walk). The completion table is code, so the rebuild ships its emulated
## result (simulation/research_effects.json, tools/emulate_knights.py, like research_prices.json); the getters' research
## terms below are ports of 0x526310, 0x5260a0, 0x51bd10, 0x51c460 and 0x526b70, Emulated on every Knights unit type
## for 16 research sets (tests/knights_fixtures.json, tests/test_knights.gd).
const Rules = preload("res://simulation/production_rules.gd")
const EFFECTS_PATH := "res://simulation/research_effects.json"
## 0x438760 stat numbers: 0 combat (0x51bd10), 1 written but never read, 2 speed (0x51c460), 3 damage and 4 range
## (0x526310; 4 also the radius +0x1b6 of 0x51a020, consumer Open), 5 magic armour (0x526b70).
enum { COMBAT, UNUSED, SPEED, DAMAGE, RANGE, RESISTANCE }
## 0x5260a0: armour by research level (PAR0/PAR1 1/2, PFPA 4 for the Knight cavalry, ...).
const ARMOUR_STEPS := [0, 5, 10, 15, 20]
const KNIGHT_CAVALRY := ["AHFX", "AHDX", "AHEX"]
## 0x526310: ranged units that keep their damage type under PFLA (fire arrows).
const NO_FIRE_ARROWS := ["ADNX", "ABIX", "ASSC"]
const FIRE := 11
const PPAL_FLAG := 0x70d57d       # 0x436500: PPAL sets 0x70d57d[player], PGRA 0x70d584[player] (read by the swing 0x42ace0)
const PGRA_FLAG := 0x70d584

static var _cache: Dictionary = {}
var effects: Dictionary

static func load_effects() -> Dictionary:
	if _cache.is_empty() and FileAccess.file_exists(EFFECTS_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EFFECTS_PATH))
		if parsed is Dictionary: _cache = parsed.get("effects", {})
	return _cache

func _init(source: Dictionary = {}):
	effects = source if not source.is_empty() else load_effects()

## 0x436500: whether a completed id joins the player's list (PQKN only after three quest choices, PSPR/PARR/POMx never).
func listed(id: String) -> bool:
	return bool(effects.get(id, {}).get("listed", true))

## The six upgrade bytes of `type_id` after the research in `list` (0x438760 mode 0 adds; bytes wrap at 256).
func upgrades(list: Array, type_id: String) -> Array:
	var out := [0, 0, 0, 0, 0, 0]
	for id in list:
		var row = effects.get(String(id), {}).get("upgrades", {}).get(type_id)
		if row == null: continue
		for s in 6: out[s] = (int(out[s]) + int(row[s])) & 0xff
	return out

## Flag addresses (player 0's address) set by the list's research (0x70d57d PPAL, 0x70d584 PGRA, ...).
func flag(list: Array, address: int) -> bool:
	for id in list:
		for f in effects.get(String(id), {}).get("flags", []):
			# The emulation ran for player 1: the flag byte is one above player 0's address.
			if String(f[0]).hex_to_int() - 1 == address: return true
	return false

## 0x5260a0(1) research part: PMIT +15, else PANT +10, else the level of PARX (then PINX, PPAX, Minotaur PSHX for STATUS
## bit 7, PMAG 1), raised to 2 for AWJX/AWKX with PIRB and to 4 for the Knight cavalry with PFPA; +5 per level. Applies to
## heroes too (no +0xb4 test).
static func armour_bonus(list: Array, type_id: String, race: int, status: int) -> int:
	if list.has("PMIT"): return 15
	if list.has("PANT"): return 10
	var level := Rules.research_level(list, "PARX")
	if level == 0: level = Rules.research_level(list, "PINX")
	if level == 0: level = Rules.research_level(list, "PPAX")
	if level == 0 and race == 4 and (status & 0x80) != 0: level = Rules.research_level(list, "PSHX")
	if level == 0 and list.has("PMAG"): level = 1
	if level < 2 and type_id in ["AWJX", "AWKX"] and list.has("PIRB"): level = 2
	if level < 4 and type_id in KNIGHT_CAVALRY and list.has("PFPA"): level = 4
	return int(ARMOUR_STEPS[level]) if level >= 1 and level <= 4 else 0

## The research terms of a non-hero unit's stats (CombatRules.unit_stats keys), as the getters add them: combat (0x51bd10),
## speed (0x51c460), magic armour (0x526b70), damage / range / fire arrows (0x526310), armour (0x5260a0). Heroes (+0xb4)
## take only the armour term. Returns a new dictionary.
func apply(base: Dictionary, type_id: String, list: Array, race: int, status: int, hero: bool) -> Dictionary:
	var s := base.duplicate()
	s.armour = maxi(0, int(base.armour) + armour_bonus(list, type_id, race, status))
	# G-1 (Emulated): 0x526b70(1) adds 3 per PREX level (Dark Elf PRE0-2) for every unit, heroes too.
	s.mres = _s16(int(base.mres) + 3 * Rules.research_level(list, "PREX"))
	if hero or list.is_empty(): return s
	var up := upgrades(list, type_id)
	s.combat = _s16(int(base.combat) + int(up[COMBAT]))
	s.speed = _s16(int(base.speed) + int(up[SPEED]))
	s.mres = _s16(int(s.mres) + int(up[RESISTANCE]))
	s.dmg = _s16(int(base.dmg) + int(up[DAMAGE]))
	if int(base.range) > 0:
		s.range = _s16(int(base.range) + int(up[RANGE]))
		if int(base.dtype) == 0 and not (type_id in NO_FIRE_ARROWS) and list.has("PFLA"): s.dtype = FIRE
	if type_id == "AEXX" and list.has("PFFI"): s.dtype = 3
	return s

# ----------------------------------------------------------------------------------- G-1: every race (RACE_DATA_RESEARCH.md)
## The getters above, Emulated for every race's roster and research sets (tests/race_data_fixtures.json,
## tools/emulate_race_data.py, tests/test_races_data.gd), and the per-type ability getters of a non-hero unit (heroes take
## their skill and item terms, HeroEffects). Spell auras (0x577520) are not simulated and add nothing here.
const ASSASSINS := ["AKJX", "AMJX", "AAWA"]
## 0x526e70: a non-hero assassin's chance (the swing's 5000-damage roll, 0x42b9b1; CombatRules "assassin"): 4, 7 with PDAO,
## +3 with PBLP, plus the rank (0x526d80). 0 for every other type. (BATCH1_RESEARCH.md R11 called it poison strength.)
static func assassin(type_id: String, list: Array, rank: int) -> int:
	if not (type_id in ASSASSINS): return 0
	var value := 7 if list.has("PDAO") else 4
	if list.has("PBLP"): value += 3
	return value + rank

## 0x526f40: life drain of a non-hero attacker (consumer 0x522860: each hit heals the attacker by it, up to its maximum,
## message 0x1fa): the Vampire AUGX 3, the Bat AABA 2 with Vampire Bats (PVAM).
static func drain(type_id: String, list: Array) -> int:
	if type_id == "AUGX": return 3
	if type_id == "AABA" and list.has("PVAM"): return 2
	return 0

## 0x526fe0: 1 for the Wraith AUKX and the Shadow AUXX (consumer 0x5210b0: a kill by such a unit gives it experience
## 0x527100(0x526db0) again; Read). G-2: the award is ported in combat.gd's death handler (spells.mind_leech, before
## the other kill awards and outside their gates); this getter stays as the table's own copy.
static func kill_experience_term(type_id: String) -> int:
	return 1 if type_id == "AUKX" or type_id == "AUXX" else 0

## 0x51c6a0 for a non-hero unit without haste / slow effects (+0xba, 0x577520): the attack rate 10, +5 for AFJX, ABDX, ARIX,
## AAIM, +10 AFIX, -3 AAIX, -2 AAJX (consumer 0x537060, CombatRules.attack_entry_ms).
static func attack_rate(type_id: String) -> int:
	var rate := 10
	if type_id in ["AFJX", "ABDX", "ARIX", "AAIM"]: rate += 5
	match type_id:
		"AFIX": rate += 10
		"AAIX": rate -= 3
		"AAJX": rate -= 2
	return maxi(1, rate)

## 0x51a020: unit +0x1b6 = max(8, unit range (ARM +0x36, before research) + 1 + the range upgrade byte). Consumer Open.
func radius_1b6(base_range: int, type_id: String, list: Array) -> int:
	return maxi(8, base_range + 1 + int(upgrades(list, type_id)[RANGE]))

## The sight counter 0x70d488 + 2p (Visibility.sight_bonus): the sum of what the list's research adds to it (PRA0 +2,
## PRA1 +1, PRA2 +1, PDS0 +2, PDS1 +2; the emulation ran for player 1, whose word is 0x70d48a).
func sight_counter(list: Array) -> int:
	var total := 0
	for id in list:
		for f in effects.get(String(id), {}).get("flags", []):
			if String(f[0]).hex_to_int() == SIGHT_COUNTER + 2: total += int(f[1])
	return total
const SIGHT_COUNTER := 0x70d488

## Research flags the swing reads (0x42ace0): PTOR 0x70d592 / PFAL 0x70d599 (Slayer and Doom Knights), PCOW 0x70d5b5 (the
## target owner's: AOIX x2 against STATUS bit 18), PDKL 0x70d5a0 (0x5267b0: hero conversion radius +8).
const PTOR_FLAG := 0x70d592
const PFAL_FLAG := 0x70d599
const PCOW_FLAG := 0x70d5b5
const PDKL_FLAG := 0x70d5a0

## PENG (Read): 0x436500 calls 0x438c20(p, 125): every building of the player except the treasure buildings BTCE / BTIN /
## BTDR / BTEL (0x52fc50) and those with a non-zero word +0x94..+0x9a (0x52b050; G-2, Read: the four output rates G M C S
## of a resource building, which 0x52aac0 / 0x52c160 read, so the mines; the rebuild keeps them in mines.gd, outside
## Production.buildings, so they are exempt by construction) gets maximum and current
## hit points * 125 / 100; a building created later gets its block's hit points * 5 / 4 (0x43be.. tail, truncated).
const ENGINEERING_EXEMPT := ["BTCE", "BTIN", "BTDR", "BTEL"]
static func engineering_hit_points(value: int) -> int:
	return _s16(_tdiv(value * 125, 100))

## PRAB (Read, 0x436500): every Orc AOCX of the player gets unit words +0xae = 0x605, +0xb0 = 1 (0x438ca0); one created
## later gets 0x606 / 1 from 0x43bfb0 (Emulated). The words are ARM +0x5a / +0x5c; their consumer is Open.
const PRAB_EXISTING := [0x605, 1]
const PRAB_CREATED := [0x606, 1]

static func _tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

static func _s16(v: int) -> int:
	v = v & 0xffff
	return v - 0x10000 if v >= 0x8000 else v
