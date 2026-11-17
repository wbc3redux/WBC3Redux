extends RefCounted
## The computer player's hero record, 0x42a0d0(out, player) (milestone 11-hero; Emulated: tests/hero_skill_fixtures.json
## "computer_heroes", 400 records from the unmodified executable with seeded generator state). Run by the hero placement
## 0x43b550 for a computer slot (0x70d6a4) before 0x54fd50 builds its hero.
##
## Skirmish path (0x748946 = 0; the campaign branches 0x5a1720 / 0x748946 == 2 are not taken):
## * level: the setup slot's level word (0xa498fc + p * 0x2a) when > 0; otherwise the highest level of the active human
##   heroes (at least 3), plus or minus 0..2 (two draws), scaled by the word the original reads 0x2c bytes past the
##   last player slot (0x7090d8: 1 -> / 3, 2 -> * 2 / 3; nothing writes it, so 0 = unscaled), at least 1; option bytes
##   0x749c63 (fixed level 0x749c64) and 0x749c66 (at least 100), 0xa479f6 == 10 (100).
## * race: setup word 0xa498f8 or the slot race; class: setup word 0xa49900 or a draw 0..27; creation 0x54c0a0/0x54c620
##   (simulation/hero_skills.json "knights_creation" for race 0).
## * XP = threshold(level) (1,000,000 at 999+), battles fought = 1d(level) + 2 * level.
## * stats: one point per level by a 1d10 table weighted 4/3/2/1 towards the class's best stats.
## * skills: entries with unlock below the level get 1d50 + unlock weights (+50 magic schools, +25 Assassin, Arcane 0),
##   sorted; the level - 1 points go down the list in 2d(span / 2) portions, the rest to the first.
## * backpack: 0..3 random items (0x43e340), equipment: 0..4 random items by icon row (the last one always item 2).
## The name comes from the NamingSets files (0x434e90, not ported): the rebuild uses "Computer <n>".

const Rules = preload("res://simulation/hero_rules.gd")
const Effects = preload("res://simulation/hero_effects.gd")
const MAGIC_SCHOOLS := [10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21]
const BACKPACK_COUNTS := [0, 0, 1, 1, 1, 1, 1, 2, 2, 3]       # 0x6084c8
const EQUIPMENT_COUNTS := [0, 1, 1, 1, 2, 2, 2, 3, 3, 4]      # 0x6084dc
const ROW_SLOT := {0: 2, 1: 2, 2: 1, 3: 1, 4: 3, 8: 3, 5: 4, 10: 4, 6: 0, 7: 0, 9: 6}

## inputs: {"player", "local", "active": [7], "computer": [7], "levels": [7] (the hero level of each human slot; the local
## slot reads its own profile), "level_override" (setup word, -1), "class_field" (-1), "fixed_level" (-1 = off),
## "at_least_100", "scaling_word" (0x7090d8, 0)}
static func create(rng, inputs: Dictionary) -> Dictionary:
	var p := int(inputs.player)
	# 0x54c000 clears the record and draws its four identity bytes (+0x181..+0x184) with 1d255 each.
	var identity := [rng.roll(1, 255, 0), rng.roll(1, 255, 0), rng.roll(1, 255, 0), rng.roll(1, 255, 0)]
	var level := 0
	var override := int(inputs.get("level_override", -1))
	if override > 0:
		level = override
	else:
		var best := 3
		for i in range(7):
			if not bool(inputs.active[i]) or bool(inputs.computer[i]): continue
			var lv := int(inputs.levels[i])
			if best <= lv: best = lv
		if int(inputs.get("fixed_level", -1)) >= 0:
			level = int(inputs.fixed_level)
		else:
			var up := Effects.s16(rng.roll(1, 2, -1)) == 0
			if up: level = best + Effects.s16(rng.roll(1, 3, -1))
			else: level = best - Effects.s16(rng.roll(1, 3, -1))
			match int(inputs.get("scaling_word", 0)):
				1: level = _tdiv(level, 3)
				2: level = _tdiv(level * 2, 3)
		level = maxi(level, 1)
	if bool(inputs.get("at_least_100", false)) and level <= 100: level = 100
	level = maxi(Effects.s16(level), 1)
	var klass := int(inputs.get("class_field", -1))
	if klass < 0: klass = Effects.s16(rng.roll(1, 28, -1))
	# Milestone 11a: the slot's race (0x708f96) selects the creation record (0x54c0a0 + 0x54c620, Emulated for every
	# race x class in simulation/hero_races.json); race 0 keeps hero_skills.json's Knights table (the two are equal).
	var race := clampi(int(inputs.get("race", 0)), 0, 15)
	var creation: Dictionary = Effects.tables().knights_creation[klass] if race == 0 else race_creation(race, klass)
	var stats: Array = creation.stats.map(func(v): return int(v))
	var skills: Array = []
	for s in creation.skills: skills.append([int(s[0]), int(s[1]), int(s[2])])
	while skills.size() < 10: skills.append([0, 0, 0])
	var xp := Rules.xp_threshold(level) if level < 999 else 1000000
	var battles := Effects.s16(rng.roll(1, level, 0)) + level * 2
	_distribute_stats(rng, stats, level)
	_distribute_skills(rng, skills, level)
	var backpack := [0, 0, 0, 0]
	var count: int = BACKPACK_COUNTS[Effects.s16(rng.roll(1, 10, -1))]
	var filled := 0
	for n in range(count):
		var flag: bool = Effects.s16(rng.roll(2, level + 2, 1)) >= 45
		rng.roll(1, 1000, 0)
		var id := random_treasure(rng, flag, true)
		if id in backpack.slice(0, filled): continue
		backpack[filled] = id
		filled += 1
	var equipment := [0, 0, 0, 0, 0, 0, 0]
	var special := false
	count = EQUIPMENT_COUNTS[Effects.s16(rng.roll(1, 10, -1))]
	for n in range(count):
		var r := Effects.s16(rng.roll(2, level * 4, 1))
		var with_sets: bool = Effects.s16(rng.roll(1, 2, -1)) != 0
		var id := random_item(rng, [true, true, r >= 45, r >= 70, with_sets])
		rng.roll(1, 100, 0)
		var picked := -1
		for pair in [[95, 8], [90, 9], [85, 15], [80, 7]]:
			if Effects.s16(rng.roll(1, 100, 0)) > int(pair[0]) and not special:
				picked = int(pair[1])
				break
		if picked >= 0:
			id = picked
			special = true
		if n == count - 1: id = 2
		var row := int(Effects.item(id).get("iconrow", -1))
		if ROW_SLOT.has(row): equipment[ROW_SLOT[row]] = id
	return {"identity": identity, "level": level, "xp": xp, "class": klass, "race": race, "stats": stats, "skills": skills, "battles_fought": battles,
		"equipment": equipment, "backpack": backpack}

static var _races: Dictionary = {}

## The creation record of `race` x `klass` from simulation/hero_races.json (tools/emulate_races.py).
static func race_creation(race: int, klass: int) -> Dictionary:
	if _races.is_empty(): _races = JSON.parse_string(FileAccess.get_file_as_string("res://simulation/hero_races.json"))
	return _races.creation[str(race)][klass]

static func _tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

## One point per level into the stats by a ten-entry table: the best stat x4, second x3, third x2, last x1 (insertion
## sort of 0x42a5fa..0x42a698, which also moves the compared values).
static func _distribute_stats(rng, stats: Array, level: int):
	var s := stats.map(func(v): return Effects.s16(int(v)))
	var o := [0, 1, 2, 3]
	for d in range(1, 4):
		var c := d
		while c > 0:
			var a: int = o[c]
			var b: int = o[c - 1]
			if int(s[a]) <= int(s[b]): break
			o[c] = b
			o[c - 1] = a
			var t = s[c]
			s[c] = s[c - 1]
			s[c - 1] = t
			c -= 1
	var weights := [o[0], o[0], o[0], o[0], o[1], o[1], o[1], o[2], o[2], o[3]]
	for i in range(level):
		var k: int = weights[Effects.s16(rng.roll(1, 10, -1))]
		stats[k] = int(stats[k]) + 1

static func _distribute_skills(rng, skills: Array, level: int):
	var order: Array = []
	var span: Array = []
	var start: Array = []
	var weight: Array = []
	for i in range(10):
		var e: Array = skills[i]
		if int(e[0]) == 0 or level <= int(e[1]): continue
		order.append(i)
		span.append(level - int(e[1]) + 1)
		start.append(int(e[2]))
		var w := Effects.s16(rng.roll(1, 50, 0) + int(e[1]))
		var id := int(e[0])
		if id in MAGIC_SCHOOLS: w += 50
		if id == 0x33: w += 25
		if id == 0x16: w = 0
		weight.append(Effects.s16(w))
	for d in range(1, order.size()):
		var c := d
		while c > 0 and int(weight[c]) > int(weight[c - 1]):
			for arr in [order, span, start, weight]:
				var t = arr[c]
				arr[c] = arr[c - 1]
				arr[c - 1] = t
			c -= 1
	var points := level - 1
	for j in range(order.size()):
		var a: int = mini(int(span[j]), points) if int(span[j]) >= points else int(span[j])
		var r := Effects.s16(rng.roll(2, a >> 1 if a >= 0 else -((-a) >> 1), 0))
		points -= r
		skills[order[j]][2] = Effects.s16(int(start[j]) + r)
	if points > 0 and not order.is_empty():
		skills[order[0]][2] = Effects.s16(int(skills[order[0]][2]) + points)

## 0x402f90(minor, lesser, greater, artifact, set): a rarity-weighted draw (1d total) among the items whose level is
## allowed; item 1 when nothing qualifies.
static func random_item(rng, allowed: Array) -> int:
	var data := Effects.items_data()
	var ids: Array = []
	var cumulative: Array = []
	var total := 0
	for it in data.get("items", []):
		var rarity := Effects.s16(int(it.rarity))
		var lv := int(it.level)
		if rarity <= 0 or lv < 1 or lv > 5 or not bool(allowed[lv - 1]): continue
		total += rarity
		cumulative.append(total)
		ids.append(int(it.index))
	var r: int = rng.roll(1, total, 0)
	for i in range(ids.size()):
		if cumulative[i] >= r: return int(ids[i]) if int(ids[i]) != 0 else 1
	return 1

## 0x43e340 -> 0x43e260(out, greater, artifact_chance): two 1d200 draws for an artifact/set item (0x43e410 ->
## 0x402f90(0, 0, 0, 1, 1)), else a minor/lesser (and greater/artifact with the flag) item.
static func random_treasure(rng, flag: bool, special_allowed: bool) -> int:
	if Effects.s16(rng.roll(1, 200, 0)) < 2 and special_allowed: return random_item(rng, [false, false, false, true, true])
	if Effects.s16(rng.roll(1, 200, 0)) < 2 and flag and special_allowed: return random_item(rng, [false, false, false, true, true])
	return random_item(rng, [true, true, flag, flag, false])

## Parity against the emulated records.
static func check_fixtures(cases: Array, check: Callable):
	var Rng = load("res://simulation/combat_rng.gd")
	var rng = Rng.new()
	for c in cases:
		var levels := [0, 0, 0, 0, 0, 0, 0]
		for k in c.humans: levels[int(k)] = int(c.humans[k])
		var inputs := {"player": int(c.player), "local": 0, "active": c.active.map(func(v): return int(v) != 0),
			"computer": c.computer.map(func(v): return int(v) != 0), "levels": levels,
			"level_override": int(c.override) if c.override else -1, "class_field": int(c.class_field),
			"fixed_level": int(c.fixed_level) if c.fixed_level is float or c.fixed_level is int else -1}
		if c.fixed_level is bool: inputs.fixed_level = -1
		rng.seed_state(int(c.seed[0]), int(c.seed[1]))
		var made := create(rng, inputs)
		var r: Dictionary = c.record
		var label := "computer hero: seed %s" % [c.seed]
		check.call(int(made.level) == int(r.level) and int(made.xp) == int(r.xp) and int(made.class) == int(r.klass), label + " level/xp/class %s vs %d %d %d" % [[made.level, made.xp, made.class], int(r.level), int(r.xp), int(r.klass)])
		check.call(made.stats == r.stats.map(func(v): return int(v)), label + " stats %s vs %s" % [made.stats, r.stats])
		var skills: Array = r.skills.map(func(s): return [int(s[0]), int(s[1]), int(s[2])])
		check.call(made.skills == skills, label + " skills %s vs %s" % [made.skills, skills])
		var items: Array = r.items.map(func(i): return int(i[0]))
		check.call(made.equipment == items.slice(0, 7) and made.backpack == items.slice(7, 11), label + " items %s %s vs %s" % [made.equipment, made.backpack, items])
		check.call(rng.state() == c.state_after.map(func(v): return int(v)), label + " generator state")
