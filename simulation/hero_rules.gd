extends RefCounted
## Original numeric rules; provenance and limits in HERO_RESEARCH.md.
static func definitions() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://simulation/hero_rules.json"))

# ------------------------------------------------------------------------------------------------ milestone 11b: creation
## PNL_CREATEHERO (0x54b040) for every race and class (HERO_RESEARCH.md "Milestone 11b"). Emulated by
## tools/emulate_hero_creation.py: 0x54bee0(race) gives level 1, XP 0, next 10, the race's portrait (0x54f230), hero art
## (0x54bee0's table) and voice (0x54f1d0, English) and runs 0x54c0a0 / 0x54c620, which give the stats and skills of
## (race, class) (simulation/hero_races.json, the 16 x 28 matrix). Every race offers every class (the droplists list all 16
## races and all 28 classes; no rejection in the creation code).
const RACES := 16
const CLASSES := 28
static var _creation: Dictionary = {}
static var _matrix: Dictionary = {}

static func creation_tables() -> Dictionary:
	if _creation.is_empty(): _creation = JSON.parse_string(FileAccess.get_file_as_string("res://simulation/hero_creation.json"))
	return _creation

## {stats: [4], skills: [{id, unlock_level, rank}]} of race x class (0x54c0a0 + 0x54c620).
static func creation(race: int, klass: int) -> Dictionary:
	if _matrix.is_empty(): _matrix = JSON.parse_string(FileAccess.get_file_as_string("res://simulation/hero_races.json"))
	var row: Dictionary = _matrix.creation[str(clampi(race, 0, RACES - 1))][clampi(klass, 0, CLASSES - 1)]
	var skills: Array = []
	for s in row.skills: skills.append({"id": int(s[0]), "unlock_level": int(s[1]), "rank": int(s[2])})
	return {"stats": row.stats.map(func(v): return int(v)), "skills": skills}

## The race's defaults written by 0x54bee0: {portrait, art, voice}.
static func race_identity(race: int) -> Dictionary:
	var d: Dictionary = creation_tables().defaults[str(clampi(race, 0, RACES - 1))]
	return {"portrait": int(d.portrait), "art": String(d.art), "voice": String(d.voice)}

## The Customize screen's lists of a race (0x612178 portraits, 0x612ff0 English voices, 0x6140f8 art): the values a saved
## record of that race may hold.
static func race_choices(race: int) -> Dictionary:
	return creation_tables().races[clampi(race, 0, RACES - 1)]

## The class droplist in display order (0x54b0c8 sorts 0x6120fc by name with 0x54afe0).
static func class_droplist() -> Array:
	return creation_tables().class_droplist.map(func(v): return int(v))

static func race_droplist() -> Array:
	return creation_tables().race_droplist.map(func(v): return int(v))

static func xp_threshold(level: int) -> int:
	if level < 1: return 0
	var table: Array = definitions().xp_thresholds
	return int(table[mini(level - 1, 50)]) + (maxi(0, level - 51) * 4000)

## 0x54a720. Stats order is Strength, Dexterity, Intelligence, Charisma.
static func derived(stats: Array, kind: int, mode: int = 1) -> int:
	var strength := int(stats[0])
	var dexterity := int(stats[1])
	var intelligence := int(stats[2])
	var charisma := int(stats[3])
	var base := 0
	var bonus := 0
	match kind:
		0: base = 4; bonus = strength
		1: base = 10; bonus = strength
		2: bonus = strength * 3
		3: bonus = strength / 3 + 1
		4: base = 8; bonus = (dexterity + 1) / 2
		5: bonus = dexterity
		6: bonus = dexterity / 2
		7: base = 50; bonus = -mini(dexterity, 40)
		8, 11: bonus = intelligence * 3
		9: bonus = intelligence / 10 + 2
		10: bonus = intelligence / 2
		12: bonus = charisma / 2
		13: base = -5; bonus = charisma
		14: bonus = mini(charisma / 4, 7) + 1
		15: base = 6; bonus = mini(charisma / 4, 13)
		16: bonus = mini(dexterity * 2 - 10, 60)
	if mode == 2: return base & 65535
	return bonus if mode == 0 else base + bonus

static func retinue_capacity(charisma: int) -> int:
	return derived([0, 0, 0, charisma], 14)

static func title_rank(category: int, value: int) -> int:
	var thresholds: Array = definitions().title_thresholds[category]
	for rank in range(1, 11):
		if value < int(thresholds[rank]): return rank - 1
	return 10

## 0x455b40 queues at most four levels; acceptance at 0x4549c7 adds
## that count to the hero level before opening the point allocation UI.
static func result_levels(level: int, xp: int) -> int:
	var count := 0
	for ahead in range(1, 5):
		if level + ahead > 999 or xp < xp_threshold(level + ahead): break
		count += 1
	return count

## Ordinary skirmish branch of 0x4553f0. Context is explicit resolved match
## state, never inferred from the map name or the selected hero's level.
static func result_bonus(context: Dictionary) -> int:
	var p: int = context.player
	# Original setup/ally/enemy scans cover the six player slots, excluding
	# the seventh neutral slot even though its result loop visits that slot.
	var players: Array = context.players.slice(0, 6)
	var maximum_human_setup := 0
	for slot in players:
		if slot.active and not slot.ai: maximum_human_setup = maxi(maximum_human_setup, int(slot.setup_points))
	var team_weight := 1
	for i in range(players.size()):
		if i == p or not players[i].active or not context.allied[p][i]: continue
		team_weight += 2 if not players[i].ai or int(players[i].difficulty) == 4 else (3 if int(players[i].difficulty) == 5 else (4 if int(players[i].difficulty) == 6 else 1))
	var amount := 0
	match int(context.map_size):
		128: amount = 5
		192: amount = 10
		256: amount = 15
	amount += (80 if team_weight == 1 else 40) if context.won else 4
	amount += mini(int(context.quests), 5) * 10
	amount += (int(context.hero_enemy_kills) / 10) * 2 if int(context.hero_enemy_kills) < 250 else 100
	var losses_table := [0, 5, 8, 10, 15, 20, 20, 25, 25, 30, 30, 30, 30, 30, 40, 40, 40, 40, 40, 50, 50]
	amount += losses_table[mini(int(context.troops_lost) / 50, 20)] * 5
	var enemy_bonus := 0
	for i in range(players.size()):
		if not players[i].active: continue
		if players[i].eliminated or (context.won and not context.allied[p][i] and i != p): amount += 10
		if not context.won or context.allied[p][i] or i == p: continue
		if not players[i].ai: enemy_bonus += 5
		else:
			var adjustment := 0
			match int(players[i].setup_points) - maximum_human_setup:
				-4: adjustment = -5
				-3: adjustment = -3
				-2: adjustment = -2
				-1: adjustment = -1
				3, 4: adjustment = 1
			match adjustment - 3 + int(players[i].difficulty):
				0: enemy_bonus += 10
				1: enemy_bonus += 20
				2: enemy_bonus += 40
				3: enemy_bonus += 80
				_: enemy_bonus += 5
	amount += enemy_bonus / team_weight + int(context.enemy_heroes_killed) * 10
	# Original visibility branches operate on the two resolved enabled flags.
	if context.visibility_object:
		var percent := 80
		if context.visibility_a and context.visibility_b: percent = 110
		elif context.visibility_b: percent = 90
		elif context.visibility_a: percent = 100
		amount = (amount * percent) / 100
	var setup := clampi(int(context.unit_setup), 0, 5)
	amount = amount >> 3 if setup == 0 else ((setup + 5) * amount) / 10
	if context.won and context.special_victory_bonus: amount += 100
	if context.hero_died: amount = (amount * 3) / 4
	amount = ironman_result(amount, bool(context.won), bool(context.hero_died), bool(context.get("ironman", false)))
	if int(context.hero_level) >= 999 or context.no_award or bool(context.get("frozen", false)): return 0
	return amount

## 0x4553f0, the local player's Ironman branch (Read, FE-1; mode word 0x709d20 == 1), after the amount is final: a hero
## that is dead pays nothing (and the record is deleted: 0x455d60); a won battle pays double. Defeat with a living hero
## pays the normal amount. Context keys "ironman" and "frozen" default to false (a frozen hero pays 0: 0x4553f0 start).
static func ironman_result(amount: int, won: bool, hero_died: bool, ironman: bool) -> int:
	if not ironman: return amount
	if hero_died: return 0
	return amount * 2 if won else amount

## 0x4553f0 with 0x41c510 true (match time below 300 s; Emulated, tests/skirmish_fixtures.json): a win pays 1, a defeat
## 0; with victory option 11 (Pitched Battle) or BuildLevel (0x70ae16) below 1 a win pays 5 and a defeat 3.
static func short_match_bonus(won: bool, victory_option: int, build_level: int, ironman: bool = false, hero_died: bool = false) -> int:
	var special := victory_option == 0xb or build_level < 1
	var amount := (5 if special else 1) if won else (3 if special else 0)
	return ironman_result(amount, won, hero_died, ironman)       # the same Ironman branch (0x455504..0x455580)
