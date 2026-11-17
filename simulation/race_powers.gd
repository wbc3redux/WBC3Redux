extends RefCounted
## B1-3 (B1_3_RESEARCH.md section 2): the batch-1 building powers (cell 8 of the building page, 0x4d2300 mode 5) and the
## unit powers of the control panel's unit row (0x4d3200) other than advancement (advancement.gd). Rules only; main.gd
## applies them to the world. Every finding is Read (decompile / disassembly), see the research document.

## ---- cell 8 of the building page (0x4d2300 case 5, the chain at decompile 137490-137590)
## Gravestone BAGR (0x4ce250: player race 2 or 8, the local player's, finished): icon 0xe, enabled while the command
## count is under the limit; 0x4ceee0 sends message 0x1f5 with AUIX at the gravestone's cell; 0x4a9230 plays EZ41 and
## Morph.wav there, removes the gravestone (0x40ada0) and creates a Skeleton with no experience of its own (0x4a49e0 adds
## the starting experience 0x557d90). No cost.
const GRAVESTONE := "BAGR"
const GRAVESTONE_RACES := [2, 8]
const GRAVESTONE_UNIT := "AUIX"
## Slavehorde (0x4d0190: BPDU, BAPR, BPCG): icon 0x14, enabled with PSLH and the count under the limit. LAB_004d0c50:
## n = min(10, limit - count) (nothing at n <= 0); at most once per 3 s (timeGetTime + 3000, stamped before the cost
## test); 25 gold each (message 0x1fe), else advisor message 0x11; n ABBX thralls (message 0xfa) at the building's
## spawn point (0x52df30), without a rally order.
const SLAVEHORDE_BUILDINGS := ["BPDU", "BAPR", "BPCG"]
const SLAVEHORDE_RESEARCH := "PSLH"
const THRALL := "ABBX"
const THRALL_GOLD := 25
const THRALL_MAX := 10
const SLAVEHORDE_MS := 3000
## Dark Citadel (0x4d05d0: BKU0-BKU4): icon 0x17, enabled with PDKC while it is not night (0x499a50). LAB_004d1300:
## crystal >= 100, else advisor 0x14; message 0x1fe (100 crystal), then a spell record kind 4, effect EZ19, amount 2
## (3 while raining, 0x49bb10) for the building's owner.
const DARK_CITADEL_BUILDINGS := ["BKU0", "BKU1", "BKU2", "BKU3", "BKU4"]
const DARK_CITADEL_RESEARCH := "PDKC"
## Rites of Dawn (0x4d04b0: BPCA, BPMT, BKL0-BKL4): icon 9, enabled with PROD while it is night or raining. LAB_004d11b0:
## crystal >= 40, else advisor 0x14; message 0x1fe (40 crystal), then a record kind 4, EZ19, amount 0.
const RITES_BUILDINGS := ["BPCA", "BPMT", "BKL0", "BKL1", "BKL2", "BKL3", "BKL4"]
const RITES_RESEARCH := "PROD"
const ICON := {"gravestone": 0xe, "slavehorde": 0x14, "dark_citadel": 0x17, "rites": 9, "brew": 0x16, "scavenge": 10}
## 0x414ef0: the tooltip's Game.txt line per icon (the first line; the price lines are drawn by the help popup).
const TIP_LINE := {0xe: 100, 0x14: 0x3f, 0x17: 0xd5, 9: 0x95, 0x16: 0x60, 10: 0xea,
	0x2e: 0x69, 0x2c: 0x6a, 0x2d: 0x6b, 0x2f: 0x6c, 0x30: 0x6d, 0x37: 0x197}

## ---- Dwarven Brew (Open 6 settled, Read)
## 0x528cd0: a unit can drink (+0x1f9) when it is not a hero and has STATUS 0x2 (Dwarf), or is AMIX / AMNX.
## 0x4d3200: the Brew button (icon 0x16, FUN_004cf7d0) shows when every selected unit can drink and the player has PDRU or
## is race 1; it is enabled with PDRU and gold >= 10 x the selection count. 0x4cf7d0 (PDRU needed) counts the drinkers;
## below 10 gold each: advisor 0x11; else message 0x202 and DwarvenBrew.wav (at most once per second).
## 0x5285d0(1) per unit: a drinker that is sober drinks when its owner has 10 gold or more, a human owner pays 10
## (0x43ed90; computer players drink free), drunk until now + 120 s (+0x1fc; 0x51c977 sobers it after), effect EZ38.
## Drunk: combat +4 (0x51bd10, after the time-of-day terms) and speed +4 (0x51c460).
const BREW_RESEARCH := "PDRU"
const BREW_GOLD := 10
const BREW_MS := 120000
const BREW_COMBAT := 4
const BREW_SPEED := 4
const DWARF := 1
const BREW_TYPES := ["AMIX", "AMNX"]

static func can_drink(type_id: String, flags: int, hero: bool) -> bool:
	return (not hero and (flags & 0x2) != 0) or type_id in BREW_TYPES

## ---- Zombie scavenging (R7, Read; the effect is Open for B1-4)
## 0x4d3200: a Zombie AUBX of a race-2 player gets icon 10 (LAB_004cfc30), enabled with PZOM; the ability hot key
## 0x426350 case 0x19 calls the same 0x4cfc90(unit): at most once per second (timeGetTime + 1000) 0x578e10(unit, level)
## with level = (rank + 1) / 5 + 1. 0x578e10 counts, within distance^2 < 37 of the Zombie (rows y - 7 .. y + 7), the
## death remains (object kind 6, EDTH / EDT1 / EDT2) and the destroyed buildings (kind 1, +0x38 == 3, owner record +0x30
## clear); each remain gives 0x458e70(1, 20) gold, each ruin 0x458e70(level, 20) of a lane chosen by 0x458e70(1, 6) (1-2
## gold, 3-4 metal, 5 stone, 6 crystal). The amounts go out as a spell record (kind 0x1c, effect EZ44, gold / metal /
## stone / crystal at +0x99..+0xa0) that the applier 0x4ac0e0 credits: that applier is B1-4's (Open here).
const SCAVENGER := "AUBX"
const SCAVENGE_RESEARCH := "PZOM"
const SCAVENGE_MS := 1000
const SCAVENGE_RADIUS2 := 0x25
const SCAVENGE_KIND := 0x1c
const SCAVENGE_EFFECT := "EZ44"

static func scavenge_level(rank: int) -> int:
	return (rank + 1) / 5 + 1

## 0x578e10's amounts: `remains` and `ruins` counted around the Zombie, `rng` a CombatRng (0x458e70). Returns
## [gold, metal, crystal, stone] in the rebuild's lane order.
static func scavenge_amounts(remains: int, ruins: int, level: int, rng) -> Array:
	var gold := 0
	var metal := 0
	var stone := 0
	var crystal := 0
	for i in remains: gold += rng.roll(1, 20)
	for i in ruins:
		match rng.roll(1, 6):
			1, 2: gold += rng.roll(level, 20)
			3, 4: metal += rng.roll(level, 20)
			5: stone += rng.roll(level, 20)
			6: crystal += rng.roll(level, 20)
	return [gold, metal, crystal, stone]

static func slavehorde_count(current: int, maximum: int) -> int:
	return mini(THRALL_MAX, maximum - current)

# ------------------------------------------------------------------------------------------------ B2-1: race batch 2
## BATCH2_RESEARCH.md section 2. Emulated rules are checked against tests/batch2_fixtures.json and
## tests/batch2_review_fixtures.json in tests/test_batch2_powers.gd.

## ---- Trade buildings (R1, Read): 0x4d07e0, cell 7 of the building page (callback 0x4d1090, icon 0x1d): the local player's
## finished building of these types, for its race or with PTRA; the cell is enabled with PTRA.
const TRADE_RESEARCH := "PTRA"
const TRADE_ICON := 0x1d
const TRADE_RACES := {"BPMA": 0, "BPQM": 12, "BPMI": 3, "BPTP": 1, "BPHS": 7, "BPTR": 10, "BPME": 6}

static func trade_cell_shown(type_id: String, race: int, has_trade: bool) -> bool:
	return TRADE_RACES.has(type_id) and (int(TRADE_RACES[type_id]) == race or has_trade)

## ---- Berserker button (R2, Emulated "cells"): 0x4d3200 LAB_004cf930, icon 0x32: every selected unit is a berserker type of
## the player's race and none has the state +0x1ce (berserk or burning); enabled with PFAN, no cost. The press sends message
## 0x204 with level 2 for the selection.
const BERSERK_RESEARCH := "PFAN"
const BERSERK_ICON := 0x32
const BERSERK_LEVEL := 2
const BERSERK_TYPES := {3: ["ABIX", "ABGX"], 4: ["AMIX", "AMNX"]}

static func berserker_cell_shown(race: int, types: Array, any_in_state: bool) -> bool:
	if types.is_empty() or any_in_state or not BERSERK_TYPES.has(race): return false
	return types.all(func(t): return BERSERK_TYPES[race].has(String(t)))

## ---- Foreign Mercenaries (E3, Emulated "mercenaries", "limit"): 0x4382d0: one roll 0x458e70(1, n, -1) = 0..n-1 of the pool,
## then one message 0xfa (no creation experience) with the building's rally point. No command test.
const MERCENARY_POOLS := {
	"POMA": ["AHFX", "AHMX", "ADIX", "ADMX", "AUJX", "AUKX", "ABCX", "ABIX", "AMIX", "AMNX", "AOIX", "AOCX", "AEMX", "AECX", "AWIX", "AWCX",
		"AKMX", "AKCX", "AFNX", "AFIX", "AAIX", "AVIX", "AAIM", "ASSC", "ARMX", "AGGZ", "AGPC", "ALIX"],
	"POMB": ["AHDX", "AHEX", "ADJX", "ADLX", "AULX", "AUXX", "ABEX", "ADOX", "AMJX", "AUMX", "AOJX", "AOMX", "AMMX", "AENX", "AEOX", "AWNX",
		"AWJX", "AKNX", "AKOX", "AEEX", "AAJX", "AADE", "AVJX", "ARCX", "AGFL", "AKJX", "ALMX"],
	"POMC": ["AHGX", "ADGX", "AUGX", "ABGX", "AMGX", "AOGX", "AFGX", "AAGX", "AVGX", "ARGX", "ALGX", "AGGX", "AEGX", "AWGX", "AKGX"]}

static func mercenary_type(item: String, rng) -> String:
	var pool: Array = MERCENARY_POOLS[item]
	return String(pool[rng.roll(1, pool.size(), -1)])

## ---- Training (R6, Read): the training job (0x52c728, and 0x4a5780 for its other callers) adds 10 experience with PTRN.
const TRAINING_RESEARCH := "PTRN"
const TRAINING_XP := 10

## ---- The counter 0x70d622 (R7, Read).
const LORD_COUNTER := {"AHEX": 2, "ABEX": 1}

## ---- Minotaurs eat animals (R4, Emulated "eating").
const EATER_STATUS := 0x80             # STATUS bit 7, the Minotaur race bit
const EAT_HP := 20
const EATING_SOUND := "Eating.wav"

## ---- Hunting (R5; the scan 0x5334f0 Read, the reach Emulated "reach").
const MINOTAUR := 4
const HUNTERS := ["AMIX", "ABHX", "AMGX", "AMMX", "AMNX", "ASCA", "AOMX", "AADE", "AVGX", "AVJX", "AVHX"]
const WOUNDED_PREY := ["ACSH", "ACCO", "ACCA", "ACPE", "ACSE", "ACTU"]
const SOUL_EATERS := ["AADE", "AVGX", "AVHX", "AVJX"]

## 0x5334f0's animal branch: the priority of `prey` for a hunter of `type_id` (0: not prey). A wounded AMIX takes
## WOUNDED_PREY, the other Minotaurs (and a Minotaur hero) also the goat, by min(200, (max - hp) >> 2) + 1; ASCA a cow and
## AOMX a sheep at 1; the soul eaters ACSO while the mana sevenths are below 7, by min(200, (7 - sevenths) x 4) + 1.
static func hunt_priority(type_id: String, minotaur_hero: bool, hp: int, max_hp: int, prey: String, sevenths: int) -> int:
	if type_id == "AMIX" or type_id == "AMNX" or type_id == "AMGX" or type_id == "AMMX" or minotaur_hero:
		if hp >= max_hp: return 0
		if WOUNDED_PREY.has(prey) or (prey == "ACGO" and type_id != "AMIX"): return mini(200, (max_hp - hp) >> 2) + 1
		return 0
	if type_id == "ASCA": return 1 if prey == "ACCO" else 0
	if type_id == "AOMX": return 1 if prey == "ACSH" else 0
	if SOUL_EATERS.has(type_id) and prey == "ACSO" and sevenths < 7: return mini(200, (7 - sevenths) * 4) + 1
	return 0

## 0x51b2c0: the mana level in sevenths of a unit (-1 without a mana maximum: the word 0xffff).
static func mana_sevenths(mana: int, max_mana: int) -> int:
	if max_mana < 1: return -1
	return clampi(mana * 7 / max_mana, 0, 7)

## 0x51ea20 / 0x51f9b0: the attacker's range counts as 0 against its animal (0x528280(1) for the Minotaurs: not ACSO).
static func melee_prey(type_id: String, prey: String) -> bool:
	match type_id:
		"AOMX": return prey == "ACSH"
		"ASCA": return prey == "ACCO"
		"AMIX", "AMNX", "AMMX", "ABHX": return prey in ["ACSH", "ACCO", "ACGO", "ACPE", "ACCA", "ACTU", "ACSE"]
	return SOUL_EATERS.has(type_id) and prey == "ACSO"

## ---- Farseeing (R8, Read): 0x436500: PFAR of the local player clears the fog flags (+0xf2bf9 / +0xf2bfa, map fog and hidden
## map) and marks every map object visible (0x547ba0); a computer's Farseeing changes nothing.
const FARSEEING := "PFAR"

# ------------------------------------------------------------------------------------------------ B3-1: race batch 3
## BATCH3_RESEARCH.md section 2 (Orc 5, Dark Dwarf 10, Daemon 11). Emulated rules are checked against tests/batch3_fixtures.json
## and tests/batch3_review_fixtures.json in tests/test_batch3_powers.gd; main.gd and combat.gd apply them to the world.

## ---- The building page 0x4d2300 mode 5 (E3, Emulated "building_cells"). Cell 7: Brood at BAS0-2 for any race (PBRD); Ancestral
## Spirit I at BPAH for local race 10 (PAS0); Stormcall at BWL0 / BWL1 for local race 11 (PSCL, enabled while it is not raining).
## Cell 8: Ancestral Spirit II (PAS1). Every cell needs the local owner and a finished building. Cell 6 (Repair) does not exist
## for a local Orc player ([0x708f96 + race] == 5, decompile 137467).
const BROOD_BUILDINGS := ["BAS0", "BAS1", "BAS2"]
const BROOD_RESEARCH := "PBRD"
const SPIRIT_HALL := "BPAH"
const SPIRIT_RACE := 10
const STORMCALL_BUILDINGS := ["BWL0", "BWL1"]
const STORMCALL_RACE := 11
const STORMCALL_RESEARCH := "PSCL"
const NO_REPAIR_RACE := 5
const B3_ICON := {"brood": 0x44, "stormcall": 0x47, "spirit_i": 0x49, "spirit_ii": 0x4a}
## 0x414ef0 (Read, decompile 16307..): the first tooltip line of the four icons (the price lines are the help popup's).
const B3_TIP_LINE := {0x44: 0x1a1, 0x47: 0x1a4, 0x49: 0x1a7, 0x4a: 0x1aa}

## Cells 7 and 8 of the batch-3 buildings for the local player's own finished building: {cell: [icon, enabled, power, tier]};
## `researched` is a Callable(code) -> bool. Cell 6: repair_cell_shown.
static func b3_building_cells(type_id: String, local_race: int, researched: Callable, raining: bool) -> Dictionary:
	if type_id in BROOD_BUILDINGS: return {7: [B3_ICON.brood, researched.call(BROOD_RESEARCH), "brood", 0]}
	if type_id == SPIRIT_HALL and local_race == SPIRIT_RACE:
		return {7: [B3_ICON.spirit_i, researched.call(SPIRITS[1].research), "spirit", 1], 8: [B3_ICON.spirit_ii, researched.call(SPIRITS[2].research), "spirit", 2]}
	if type_id in STORMCALL_BUILDINGS and local_race == STORMCALL_RACE:
		return {7: [B3_ICON.stormcall, researched.call(STORMCALL_RESEARCH) and not raining, "stormcall", 0]}
	return {}

static func repair_cell_shown(local_race: int, hurt: bool) -> bool:
	return hurt and local_race != NO_REPAIR_RACE

## E4 (Emulated "powers.brood", review "cooldown"): 0x4d0e50: n = min(8, limit - used), nothing at n <= 0; at most once per 3 s
## (stamped before the price test; a press 3000 ms after the last is still refused, 3010 passes); 30 gold each or advisor
## message 0x11; message 0x1fe, then n AVBX (message 0xfa) at the spawn point 0x52df30, no rally, effect or start-experience flag.
const BROOD_UNIT := "AVBX"
const BROOD_GOLD := 30
const BROOD_MAX := 8
const BROOD_MS := 3000

static func brood_count(current: int, maximum: int) -> int:
	return mini(BROOD_MAX, maximum - current)

## E5 (Emulated "powers.spirit_i / spirit_ii"): 0x4d1680 / 0x4d1460: n = min(1, limit - used); once per 1 s each; 125 / 250 crystal
## or advisor 0x14; message 0x1fe, then one AUKX / AUXX with +0x3b = 1 (no start experience 0x4a49e0; Poison Gate applies).
const SPIRITS := {1: {"research": "PAS0", "unit": "AUKX", "crystal": 125, "icon": 0x49}, 2: {"research": "PAS1", "unit": "AUXX", "crystal": 250, "icon": 0x4a}}
const SPIRIT_MS := 1000

## E6 / R2 (Emulated "powers.stormcall", review "rain", "rain_end"): 0x4d18a0: crystal >= 80 or advisor 0x14; message 0x1fe (80
## crystal); a record kind 4, EZ19, amount 4, or 5 by night (0x499a50). No throttle.
const STORMCALL_CRYSTAL := 80

static func stormcall_amount(night: bool) -> int:
	return 5 if night else 4

## ---- Souls (E7 / E8, Emulated "souls"): 0x5210b0. A Succubus AVIX that kills a unit of another, non-allied owner creates one soul
## (message 0xfa): owner 6, ACSO, the victim's cell, effect ESSP, lifetime 120 s; an animal victim (a soul too) only on 1d100 < 20.
## ACSO killed by AADE / AVGX (non-hero): mana + min(25, max - current) (0x52a020), effect EMLE, nothing at a full pool; AVJX: +20
## experience (0x527100); a hero of those types (AVHX): the hero's pool + min(25, room), no effect.
const SUCCUBUS := "AVIX"
const SOUL := "ACSO"
const SOUL_OWNER := 6
const SOUL_LIFETIME_MS := 120000
const SOUL_EFFECT := "ESSP"
const SOUL_ANIMAL_CHANCE := 20
const SOUL_MANA := 25
const SOUL_MANA_EFFECT := "EMLE"
const REAPER := "AVJX"
const REAPER_XP := 20
const SOUL_FEEDERS := ["AADE", "AVGX", "AVHX", "AVJX"]

static func soul_mana(mana: int, max_mana: int) -> int:
	return mini(SOUL_MANA, max_mana - mana)

## ---- The Firebomb AASX (E9, Emulated "firebomb"): at its hit entry it dies on the host (no swing); every death runs the blast
## 0x529a40: its own attack damage (ARM 40 + 10 per PAF level) through 0x42bbf0(damage, 2, 3, armour) on the 8 cells round it, half
## on the next 12 (the ring without corners), units and buildings of every owner but its own, ground layer only.
const FIREBOMB := "AASX"
const BLAST_TYPES := ["AASX", "AGSP"]
const BLAST_NEAR := [[0, -1], [1, -1], [1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1]]     # 0x611330
const BLAST_FAR := [[-1, -2], [0, -2], [1, -2], [2, -1], [2, 0], [2, 1], [1, 2], [0, 2], [-1, 2], [-2, 1], [-2, 0], [-2, -1]]   # 0x611370
const BLAST_MODE := 2
const BLAST_DTYPE := 3

## ---- Stored animals (E10, Emulated "ammunition"): AOMX killing ACSH, ASCA killing ACCO within 20 cells on both axes: +0x106 + 1
## (GettingSheep.wav / GettingCow.wav, at most once per second). A ranged shot of damage type 5 with one stored uses it: damage x 3,
## the missile is the animal's id.
const STORERS := {"AOMX": "ACSH", "ASCA": "ACCO"}
const STORE_REACH := 20
const STORE_SOUNDS := {"ACSH": "GettingSheep.wav", "ACCO": "GettingCow.wav"}
const STORED_DTYPE := 5
const STORED_FACTOR := 3

static func stores(killer: String, victim: String, gap: Vector2i) -> bool:
	return STORERS.get(killer, "") == victim and absi(gap.x) <= STORE_REACH and absi(gap.y) <= STORE_REACH

## ---- The Gobshooter's Goblin (E12, Emulated "goblin"): an AOSX missile, after its impact, 0x541e00: on 1d8 = 1, with room in the
## shooter owner's command, an empty landing cell not on the map's first or last row / column: one AOSX on script 4 (Rampant).
const GOBLIN := "AOSX"
const GOBLIN_SCRIPT := 4

static func goblin_cell_ok(cell: Vector2i, size: Vector2i) -> bool:
	return cell.x > 0 and cell.y > 0 and cell.x < size.x - 1 and cell.y < size.y - 1

## ---- Rabies PRAB (E14, Emulated "rabies", review "immunity"): a Wolfrider AOCX gets the type class word 0x606 when created with
## PRAB (0x43bfb0), 0x605 when it existed at the research (0x438ca0): class 6 = disease on a melee hit, strength the low byte.
## 0x51abe0: chance max(1, (strength + 0x70d630 - magic armour' + 10) x 5).
const RABID := "AOCX"
const RABIES_RESEARCH := "PRAB"
const RABIES_NEW := 6
const RABIES_EXISTING := 5

static func rabies_chance(strength: int, plague: int, magic_armour: int) -> int:
	return maxi(1, (strength + plague - magic_armour + 10) * 5)

## ---- PDBT (R11, Read: the lost armour getter 0x525ff4): AAFB with PDBT: fire armour + 50.
const PDBT_TYPE := "AAFB"
const PDBT_RESEARCH := "PDBT"
const PDBT_FIRE := 50

## ---- Petrify (E11 / R3, Emulated "missile_kinds", review "petrify"): ATOX and AOXX missiles are always kind 3 (no 1..100 draw); a
## unit they bring to 0 hit points (not under effect 0x3e) is petrified: EZ42, Petrify.wav, the shooter's owner gets 100 stone
## (clamped), no corpse. Needs a live shooter. The other shooters' 4 % kinds stay with the Knights' crits (decision 4).
const PETRIFIERS := ["ATOX", "AOXX"]
const PETRIFY_STONE := 100
const PETRIFY_EFFECT := "EZ42"
const PETRIFY_SOUND := "Petrify.wav"

# ------------------------------------------------------------------------------------------------ B4-1: race batch 4
## BATCH4_RESEARCH.md section 2 (High Elf 6, Wood Elf 7, Dark Elf 8). Emulated rules are checked against tests/batch4_fixtures.json
## and tests/batch4_review_fixtures.json in tests/test_batch4_powers.gd; main.gd, combat.gd and spells.gd apply them to the world.

## ---- The Wisp merge (E1 / E2, Emulated "powers.merge", "merge_task", review "merge_box"). The cell 0x4cea80 (icon 0xd) shows when
## every selected object is a Wisp AEBX, at least 4, whose cells span at most 30 in x and in y (0x4ce120: max - min < 0x1f), for any
## race; enabled with PWSP and crystal >= the price of 0x40b6b0(AEAX, AEBX) (100). The press makes n // 4 groups of four in selection
## order; a group that cannot pay stays as it is. The first Wisp of a paid group leads (+0x108..+0x114 the four ids, +0x106 = 0, order
## 10 at its own cell); 0x5205d0 case 10 then removes each listed Wisp that still exists (message 0x1fb) and sends one AEAX at the
## order's cell with EZ13 (no rally, no start flags); a leader whose +0x106 is set does nothing.
const WISP := "AEBX"
const ANCIENT_WISP := "AEAX"
const MERGE_RESEARCH := "PWSP"
const MERGE_ICON := 0xd
const MERGE_GROUP := 4
const MERGE_SPAN := 30
const MERGE_EFFECT := "EZ13"

## 0x4ce120: the selection's types and cells.
static func merge_box(types: Array, cells: Array) -> bool:
	if types.size() < MERGE_GROUP or types.any(func(t): return String(t) != WISP): return false
	var lo: Vector2i = cells[0]
	var hi: Vector2i = cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return hi.x - lo.x <= MERGE_SPAN and hi.y - lo.y <= MERGE_SPAN

## The press: how many groups of four pay with `crystal` at `price` each (selection order, groups that cannot pay stay).
static func merge_groups(count: int, crystal: int, price: int, researched: bool) -> int:
	if not researched: return 0
	var groups := 0
	for g in count / MERGE_GROUP:
		if crystal < price: continue
		crystal -= price
		groups += 1
	return groups

## ---- Income from units and a building (E3, Emulated "income"): the vtable +0x34 walk of 0x531f10 (4000 ms cycle). Each Ancient
## Wisp + 4 crystal and each AFNX + 2 gold (0x5299d0, unconditional; a unit is no producer); each finished Magic Well BPMW + 2 gold
## (the lost tail of 0x52aac0, not with +0x115 set or in state 8), counted as a gold producer for the PIBX / PHLX bonus.
const UNIT_INCOME := {"AEAX": [0, 0, 4, 0], "AFNX": [2, 0, 0, 0]}
const WELL := "BPMW"
const WELL_INCOME := [2, 0, 0, 0]

## The cycle's other income of one player: its living units' types and its finished Wells -> {"income", "producers"} (economy.gd).
static func income_of(unit_types: Array, wells: int) -> Dictionary:
	var income := [0, 0, 0, 0]
	var producers := [0, 0, 0, 0]
	for t in unit_types:
		var row = UNIT_INCOME.get(String(t))
		if row != null:
			for lane in 4: income[lane] += int(row[lane])
	for lane in 4:
		income[lane] += int(WELL_INCOME[lane]) * wells
		if int(WELL_INCOME[lane]) != 0: producers[lane] += wells
	return {"income": income, "producers": producers}

## ---- Elcor's Balm PELC (E10, R8, Emulated "powers.elcor", "building_cells", review "keys"). Cell 7, icon 0x18 (0x4d1e10) at BPHE /
## BPHO, shown for local races 6, 7 or with PELC, enabled with PELC, finished buildings. Once per 1 s (0xa47880, stamped first);
## crystal >= 400 or advisor 0x14; 0x4d2030: message 0x1fe (400, 300 for a computer), then 0x57b9d0(building, 1): a record kind 0x14,
## amount 0x40dd50(owner, 100), radius 0xff, friends, hurt only (b12 2), EZ11. The Q key (case 0x14): PELC, the key building BPHE then
## BPHO (keys.building), crystal < 400: advisor 0x14, else 0x4d2030; no throttle.
const ELCOR_RESEARCH := "PELC"
const ELCOR_BUILDINGS := ["BPHE", "BPHO"]
const ELCOR_RACES := [6, 7]
const ELCOR_ICON := 0x18
const ELCOR_CRYSTAL := 400
const ELCOR_COMPUTER_CRYSTAL := 300
const ELCOR_MS := 1000

## ---- Holy Word PHOL (E11, R8, Emulated "powers.holy", review "keys"). Cell 8, icon 0x33 (0x4d1a00) at BPCA / BPMT, shown for local
## races 0, 6 or with PHOL, enabled with PHOL, finished buildings. Once per 1 s (0xa4786c); crystal >= 200 or advisor 0x14; 0x5002a0:
## no press without an enemy unit with STATUS 0x8000000 (evil) within 14 cells (a refused cue, nothing paid); 0x4d1ef0: 200 crystal,
## a record kind 0x10 (a missile per target), EMM2, amount 50, radius 15, damage type 4, sound 9, +0x135 = 0x8000000, enemy units.
## The O key (case 0x13): PHOL, the key building BPCA, no evil test, no throttle.
const HOLY_RESEARCH := "PHOL"
const HOLY_BUILDINGS := ["BPCA", "BPMT"]
const HOLY_RACES := [0, 6]
const HOLY_ICON := 0x33
const HOLY_CRYSTAL := 200
const HOLY_MS := 1000
const HOLY_REACH := 14
const EVIL := 0x8000000

## The two cells of a local player's own finished building: {cell: [icon, enabled, power]}.
static func b4_building_cells(type_id: String, local_race: int, researched: Callable) -> Dictionary:
	if type_id in ELCOR_BUILDINGS and (local_race in ELCOR_RACES or researched.call(ELCOR_RESEARCH)):
		return {7: [ELCOR_ICON, researched.call(ELCOR_RESEARCH), "elcor"]}
	if type_id in HOLY_BUILDINGS and (local_race in HOLY_RACES or researched.call(HOLY_RESEARCH)):
		return {8: [HOLY_ICON, researched.call(HOLY_RESEARCH), "holy"]}
	return {}

## 0x414ef0 (Read, decompile of 0x414ef0 cases 0xd / 0x18 / 0x1a / 0x33): the first tooltip line of the four icons.
const B4_TIP_LINE := {0xd: 0x92, 0x18: 0x9c, 0x1a: 0x7b, 0x33: 0x98}

## ---- Sacrifice PSAC (E7 / E8, Emulated "powers.sacrifice", "sacrifice_applied", "sacrifice_units", "unit_cells"). Cell icon 0x1a
## (0x4ced00) in the unit row, shown for local race 8 or with PSAC when every selected object passes 0x4ce210 (STATUS 0x10000, not 4,
## not 0x2000, no hero, +0x211 = 0); enabled with PSAC and crystal >= 5 x n. The press: 3 s between presses (0xa47848, stamped
## first); one 1d100; message 0x1fe (5 x n crystal, no stock test); a record kind 0x1b with up to n targets, AADE, EZ08, +0x9b = 1 when
## the roll <= 4 x n. Applied (0x4aa840 case 0x1b): every target dies (message 0x138) and with +0x9b = 1 one AADE stands on a free cell
## by the first target, EZ08.
const SACRIFICE_RESEARCH := "PSAC"
const SACRIFICE_RACE := 8
const SACRIFICE_ICON := 0x1a
const SACRIFICE_CRYSTAL := 5
const SACRIFICE_CHANCE := 4
const SACRIFICE_MS := 3000
const SACRIFICE_KIND := 0x1b
const SACRIFICE_DAEMON := "AADE"
const SACRIFICE_EFFECT := "EZ08"

static func sacrificable(status: int, hero: bool) -> bool:
	return status & 0x10000 != 0 and status & 4 == 0 and status & 0x2000 == 0 and not hero

static func sacrifice_daemon(roll: int, count: int) -> bool:
	return roll <= SACRIFICE_CHANCE * count

## ---- Death spawns (E5, Emulated "death", review "death_full"): 0x5210b0 on the owner's machine: an Ancient Treant leaves two Treants
## at its cell (no effect), a Spider Priestess six Spiders (EZ08); no command check.
const DEATH_SPAWNS := {"AWKX": ["AWJX", 2, ""], "AKOX": ["AKKX", 6, "EZ08"]}

## ---- Queen Spider eggs (E6, Emulated "death", "eggs"): a Queen AKLX killing a unit of another, non-allied owner (animals count) lays
## a record kind 7: BMEG at the victim's cell for 40 s, ECHE, sound 26, the killer's owner. Past its end the egg's tick hatches min(4,
## limit - used) AKKX at its cell with ESSP, then the egg is removed (0x40ada0, Read).
const QUEEN := "AKLX"
const EGG := "BMEG"
const EGG_MS := 40000
const EGG_EFFECT := "ECHE"
const EGG_SOUND := 26
const HATCH_UNIT := "AKKX"
const HATCH_MAX := 4
const HATCH_EFFECT := "ESSP"

static func hatch_count(used: int, limit: int) -> int:
	return maxi(0, mini(HATCH_MAX, limit - used))

## ---- Type-class poison (E9, Emulated "poison"; disassembly 0x51ac22..0x51acdb): the attacker's class word +0xae (ARM +0x5a) with
## high byte 5, or effect 0x7d (Venom Touch), poisons on a melee hit a target 0x51c130 allows when 1..100 <= max(1, (strength - magic
## armour' + 10) x 5); strength the word's low byte, 10 with effect 0x7d. 0x51c130 refuses a target whose own word has high byte 5.
const POISON_CLASS := 5

static func class_byte(word: int) -> int:
	return (word >> 8) & 0xff

static func poison_chance(strength: int, magic_armour: int) -> int:
	return maxi(1, (strength - magic_armour + 10) * 5)

# ------------------------------------------------------------------------------------------------ B5-1: race batch 5
## BATCH5_RESEARCH.md section 2 and section 11 (Fey 9, Ssrathi 13, Plaguelord 15).
## ---- Chaos Plague PCN0-4 (E3 / E4 / E6, Emulated "building_cells", "powers.chaos", "powers.keys", "powers.payers", review "advisor",
## "key_loop"). Cell 8, icon 0x54 (LAB_004d1ae0) at BKG0-4, shown for local race 15 or with PCN0 (0x4d0390), enabled with PCN0, own
## finished buildings. The press: once per 1 s (0xa47870, stamped first); crystal >= 1000, else advisor 0x14; an enemy living unit
## within 14 cells (0x5007f0 -> 0x5002e0), else the refused cue and nothing paid; then 0x4d20b0: message 0x1fe (1000 crystal, no stock
## test: the computer's payer too) and 0x5771f0(hall, level = the PCN items held): kind 0x22, radius 28 (a building caster), amount
## max(5, 53 - 3 x level). The C key (case 0x22): PCN0, crystal >= 1000 (advisor 0x14), the key building BKG4 .. BKG0 (0x427e30),
## the cast without paying, no throttle, no enemy test, unfinished halls too; returns 0 (decision 1: the original's free key).
const CHAOS_RESEARCH := "PCN0"
const CHAOS_LEVELS := ["PCN0", "PCN1", "PCN2", "PCN3", "PCN4"]
const CHAOS_HALLS := ["BKG4", "BKG3", "BKG2", "BKG1", "BKG0"]
const CHAOS_RACE := 15
const CHAOS_ICON := 0x54
const CHAOS_CRYSTAL := 1000
const CHAOS_MS := 1000
const CHAOS_REACH := 14

## ---- Couatl's Wrath PCWR (E3 / E5 / E6, Emulated as above and "abilities", tests/batch5_meteor_fixtures.json). Cell 8, icon 0x5b
## (LAB_004d1d70) at BKL0-4 for local race 13 only (0x4d0550), enabled with PCWR. Once per 1 s (0xa4787c); gold >= 750 or advisor 0x11;
## no enemy test; 0x4d2190: message 0x1fe (750 gold), 0x57a1e0(temple, 1): kind 0x23, amount 5 + level, radius 11 + level. The W key
## (case 0x24): PCWR, gold >= 750, BKL4 .. BKL0, free, returns 0.
const WRATH_RESEARCH := "PCWR"
const WRATH_TEMPLES := ["BKL4", "BKL3", "BKL2", "BKL1", "BKL0"]
const WRATH_RACE := 13
const WRATH_ICON := 0x5b
const WRATH_GOLD := 750
const WRATH_MS := 1000
const WRATH_KIND := 0x23
## The applier 0x4ac0e0 case 0x23 (decompile 116664-116711): `amount` missiles EMTF (0x40f620 -> EMF0) from the temple's cell to the
## temple's cell + these offsets of table 0x608190 (in order; an x or y past 0 .. the map's width / height is skipped), STEZ47 / STEZ27.
const METEOR_OFFSETS := [[-5, 5], [-3, -11], [7, 4], [1, -4], [-6, 12], [11, -8], [1, -12], [-11, -4], [2, 8], [4, -3]]
## tools/emulate_batch5_meteor.py (Emulated, Open 1 settled): the missile 0x53e960 has no owner (+0x164 = -1: every owner is hostile)
## and no damage (+0x678 = 0, class 0); its path (0x541120 flag 0x100, the high arc) ends at the landing cell with height 1. A living
## unit or building in the probe block there takes the impact 0x5427e0 (0x42bbf0(0) = 1). With nothing struck, the step's ground blast
## (0x540cf3.., host only): every unit and building whose sprite cell lies in x - 4 .. x + 4, y - 4 .. y + 3 of the landing cell
## (clamped at 0), of every owner (the temple's own too), takes 0x42bbf0(150, mode 2, class 3 fire, its armour) with no attacker.
const METEOR_ID := "EMF0"
const METEOR_ART := "EMTF"
const METEOR_BLAST := 150
const METEOR_BLAST_MODE := 2
const METEOR_BLAST_DTYPE := 3
const METEOR_BOX := [-4, 4, -4, 3]          # x from, x to, y from, y to (inclusive)

## Cell 8 of a local player's own finished hall / temple: {8: [icon, enabled, power]}.
static func b5_building_cells(type_id: String, local_race: int, researched: Callable) -> Dictionary:
	if type_id in CHAOS_HALLS and (local_race == CHAOS_RACE or researched.call(CHAOS_RESEARCH)):
		return {8: [CHAOS_ICON, researched.call(CHAOS_RESEARCH), "chaos"]}
	if type_id in WRATH_TEMPLES and local_race == WRATH_RACE:
		return {8: [WRATH_ICON, researched.call(WRATH_RESEARCH), "wrath"]}
	return {}

## 0x437f70 for PCN: the number of Contagion levels held (PCN0 .. PCN4 in turn).
static func chaos_level(researched: Callable) -> int:
	var level := 0
	for code in CHAOS_LEVELS:
		if not researched.call(code): break
		level += 1
	return level

## 0x414ef0 (Read, decompile 16935 / 16992): the first tooltip line of the two icons.
const B5_TIP_LINE := {0x54: 0x36c, 0x5b: 0x371}

## ---- Type-class disease (E9, decision 3, Emulated "class_hits", "immunity"): the class word's high byte 6 (Ghoul AGPC 0x608, Slime
## AGSL 0x607, Zombie AUBX 0x605, and batch 3's rabid Wolfrider 0x606 / 0x605) diseases on a melee hit, strength the low byte; 0x51c1b0
## refuses a target of class 6 too. One rule for every race (the Undead Zombie included).
const DISEASE_CLASS := 6

## ---- Construction PCON (E11, Emulated "build_list", review "panel"; Read 0x524450 decompile 197933): the Chameleon's construction
## list 0x525a70 halves each entry's time (sar 1) when its owner has PCON, any race; the panel keeps that time and the placement
## order (message 0x10e) carries it x 1000, so the placed building takes it (decision 4).
const CONSTRUCTION_RESEARCH := "PCON"
const CONSTRUCTION_BUILDER := "ALBX"

static func construction_seconds(seconds: int, builder: String, researched: bool) -> int:
	return seconds >> 1 if builder == CONSTRUCTION_BUILDER and researched else seconds