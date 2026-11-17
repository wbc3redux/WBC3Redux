extends RefCounted
## R-1: unit experience and rank (COMBAT_RESEARCH.md section "R-1"). Emulated against tests/rank_fixtures.json
## (tools/emulate_ranks.py, tests/test_ranks.gd): 0x527100 -> 0x40da20 -> 0x40daa0 for all 199 ARM types, 0x51b460 and 0x51b820.
##
## A unit's creation block starts with its rank (+0x3c, 0..19; the displayed medal count is the rank) and its experience
## (+0x40). Every promotion raises the block for good: the getters read the raised words, so research, near-hero and
## weather terms stack on top. `block` here is {rank, xp, combat, speed, mres, max_hp, hp, dmg, armour, word_ae, word_b0}.

const MAX_RANK := 19               # 0x40daa0: nothing above 0x13; 0x519ae0 clamps a block's rank to it as well
const MAX_XP := 20000              # 0x527100 caps one gain, 0x40da20 the total
const MAX_STAT := 0x32             # 0x40daa0: combat, speed and the +0xae low byte stop at 50 by promotion
const MAX_WORD_B0 := 0x13
## 0x5fbc50: experience of ranks 1..19.
const THRESHOLDS := [5, 10, 20, 40, 70, 110, 160, 220, 280, 350, 430, 520, 610, 700, 800, 900, 1100, 1300, 1500]
## 0x607d70 / 0x607ed0 / 0x608030: rows [low, high, value at rank 0, 1, .. 19]; the value of the first row that holds the
## word is added at the rank being reached. A word in no row keeps its value.
const COMBAT_ROWS := [
	[0, 4, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1],
	[5, 8, 0, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2],
	[9, 12, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2],
	[13, 16, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2],
	[17, 20, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2],
	[21, 24, 0, 0, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2],
	[25, 28, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2, 2],
	[29, 99, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 2, 2]]
const SPEED_ROWS := [
	[0, 4, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 1],
	[5, 8, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1],
	[9, 12, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
	[13, 16, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1],
	[17, 20, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 0, 1, 0, 1, 0, 1],
	[21, 24, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
	[25, 28, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1],
	[29, 99, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]]
const HIT_POINT_ROWS := [
	[0, 30, 0, 5, 5, 5, 5, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[31, 50, 0, 5, 5, 5, 10, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[51, 70, 0, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[71, 90, 0, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[91, 120, 0, 10, 10, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[121, 160, 0, 10, 10, 10, 10, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[161, 220, 0, 10, 10, 10, 10, 10, 10, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20, 20],
	[221, 999, 0, 10, 10, 10, 10, 10, 10, 15, 15, 15, 15, 15, 15, 15, 15, 20, 20, 20, 20, 20]]
## 0x607d5c through 0x40b0e0: the experience of a new unit by its owner's PLOX level (0 below, the last value above 9).
const TRAINING_XP := [0, 5, 10, 20, 30, 40, 50, 60, 80, 100]
## 0x5fbc48: the experience the 0xfd sender 0x4a5780 writes for a unit of rank 0..20 outside a scenario (0x74b958 clear;
## Emulated, tests/rank_review_fixtures.json "fd_builder"). It is one rank short of THRESHOLDS: a rank-3 unit arrives
## with 10. Rank -1 reads the word before the table (20).
const CREATION_XP := [-1, 0, 5, 10, 20, 40, 70, 110, 160, 220, 280, 350, 430, 520, 610, 700, 800, 900, 1100, 1300, 1500]
const CREATION_XP_BEFORE := 20
## 0x4a5780: Knight cavalry gain 5 more with Order of the Rose (PORO); Training (PTRN) adds 10.
const ROSE_CAVALRY := ["AHFX", "AHDX", "AHEX"]
const ROSE_XP := 5
const TRAINED_XP := 10
## 0x61120c: the regeneration percent by PRGX level (0x51b460).
const REGENERATION := [100, 150, 200, 300, 400, 500, 600, 700]
const REGEN_MS := 250              # 0x51b460: (40 - rank) x 250 ms per hit point before the percent
const REGEN_RANKS := 40
const FAST_REGEN := "AOMX"         # 0x51b460: a quarter of the time
const RANK_HEAL := 100             # 0x527100: a promotion heals at most this much (message 0x1fa)
const UNDEAD_STATUS := 0x4
const POISON_MS := 1000
const DISEASE_MS := 1000
## 0x527100's effects for the local player's units in view, and its sound (0x50f0a0, 500 ms apart).
const LEVEL_EFFECTS := ["EZ12", "EZ57"]
const LEVEL_SOUND := "sfx/GainedLevel"
const LEVEL_SOUND_MS := 500

static func _s16(v: int) -> int:
	v &= 0xffff
	return v - 0x10000 if v >= 0x8000 else v

static func _table_term(rows: Array, value: int, rank: int) -> int:
	for row in rows:
		if int(row[0]) <= value and value <= int(row[1]): return int(row[rank + 2])
	return 0

## 0x519ae0's flag +0x1cd: ids A T ? X. A titan gains no experience (0x527100), shows no rank (0x4d7710) and is immune to
## poison and disease (0x51c130, 0x51c1b0).
static func is_titan(type_id: String) -> bool:
	return type_id.length() == 4 and type_id[1] == "T" and type_id[3] == "X"

## 0x40daa0: one promotion. Below rank 19 the rank rises and the words grow by the rank just reached: combat and speed by
## their tables (read from the word as it stands), hit points by their table, the current ones too, damage 2 (3 from rank 5,
## 4 from 10, 5 from 15), magic armour and armour 1 (2 from rank 5, 3 from 12); a set low byte of +0xae and a set +0xb0 grow
## by 1. Combat, speed and the low byte stop at 50 (the low byte's test is signed), +0xb0 at 19.
static func promote(block: Dictionary):
	if int(block.rank) >= MAX_RANK: return
	var rank := int(block.rank) + 1
	block.rank = rank
	block.combat = int(block.combat) + _table_term(COMBAT_ROWS, int(block.combat), rank)
	block.speed = int(block.speed) + _table_term(SPEED_ROWS, int(block.speed), rank)
	var hp_term := _table_term(HIT_POINT_ROWS, int(block.max_hp), rank)
	block.max_hp = int(block.max_hp) + hp_term
	block.hp = int(block.hp) + hp_term
	block.dmg = int(block.dmg) + 2 + (1 if rank > 4 else 0) + (1 if rank > 9 else 0) + (1 if rank > 14 else 0)
	var guard := 1 + (1 if rank > 4 else 0) + (1 if rank > 11 else 0)
	block.mres = int(block.mres) + guard
	block.armour = int(block.armour) + guard
	var word := int(block.word_ae) & 0xffff
	if (word & 0xff) != 0: word = (word & 0xff00) | ((word + 1) & 0xff)
	if int(block.word_b0) != 0: block.word_b0 = int(block.word_b0) + 1
	if int(block.combat) > MAX_STAT: block.combat = MAX_STAT
	if int(block.speed) > MAX_STAT: block.speed = MAX_STAT
	if _s16(word << 8) > 0x3200: word = (word & 0xff00) | MAX_STAT
	block.word_ae = _s16(word)
	if int(block.word_b0) > MAX_WORD_B0: block.word_b0 = MAX_WORD_B0

## 0x40da20: the experience and how many promotions it brings (each 0x40daa0). Returns the promotions.
static func gain(block: Dictionary, amount: int) -> int:
	var xp := clampi(int(block.xp) + amount, 0, MAX_XP)
	block.xp = xp
	var rank := int(block.rank)
	var count := 0
	for i in THRESHOLDS.size():
		if i == rank and int(THRESHOLDS[i]) <= xp:
			count += 1
			rank += 1
		elif rank <= i:
			break
	for i in count: promote(block)
	return count

## 0x4a5780 (Emulated "fd_builder"): the experience a 0xfd unit block carries: kept in a scenario, else 0x5fbc48[rank].
static func creation_xp(rank: int, xp: int, scenario: bool) -> int:
	if scenario: return xp
	if rank < 0: return CREATION_XP_BEFORE
	return int(CREATION_XP[mini(rank, CREATION_XP.size() - 1)])

## 0x4a5780's +0x10 (Emulated "fd_builder"), which the handler 0x4a4560 passes to 0x527100: PTRN 10, 0x40b0e0[PLOX level],
## PORO 5 for Knight cavalry, and the per-player term 0x7495d8 only when the block's experience is 0 (scenario data, Open;
## 0 in skirmish). The training job 0x52c728 and main.gd _on_unit_ready add the same terms.
static func creation_gain(type_id: String, trained: bool, plox: int, rose: bool, block_xp: int = 0, term: int = 0) -> int:
	var amount := TRAINED_XP if trained else 0
	amount += int(TRAINING_XP[clampi(plox, 0, TRAINING_XP.size() - 1)])
	if rose and type_id in ROSE_CAVALRY: amount += ROSE_XP
	if block_xp == 0: amount += term
	return amount

## 0x527100's heal after a promotion: the missing hit points, at most 100, as the sent target of message 0x1fa.
static func healed_points(hp: int, maximum: int) -> int:
	return mini(maximum, hp + mini(maximum - hp, RANK_HEAL)) if hp < maximum else hp

## 0x51b460 (without a hero: the interval is a hero's own in HeroEffects): ms per 1000 of a hit point's time, 0 never.
## `percent` is the sum of 0x61120c[PRGX level], the owner's living hero's skill 3 and effect 0x2c.
static func regeneration_rate(rank: int, type_id: String, status: int, percent: int) -> int:
	if percent == 0: return 0
	var rate: int = ((REGEN_RANKS - rank) * REGEN_MS * 100) / percent
	if type_id == FAST_REGEN: rate >>= 2
	if status & UNDEAD_STATUS: rate >>= 1
	return rate

## 0x51b820 for a non-hero. `state` holds hp, max_hp, regen_ms (+0x164), poisoned / diseased are the caller's; returns the
## hit points healed. `garrisoned` halves the rate (+0x1c5). The first tick arms the timer, later due ones heal
## ceil(1000 / rate), and at full hit points the timer stops.
static func regen_tick(state: Dictionary, now_ms: int, rate: int, garrisoned: bool) -> int:
	if int(state.hp) >= int(state.max_hp):
		state.regen_ms = 0
		return 0
	if rate < 1: return 0
	var step := (rate >> 1) if garrisoned else rate
	if step < 1: return 0
	var total := step
	var heal := 0
	var due := int(state.regen_ms)
	if due != 0:
		if now_ms < due: return 0
		heal = 1
		while total < 1000:
			total += step
			heal += 1
		state.hp = int(state.hp) + heal
	state.regen_ms = total + now_ms
	return heal
