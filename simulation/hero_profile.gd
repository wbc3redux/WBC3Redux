extends RefCounted
const Rules = preload("res://simulation/hero_rules.gd")
const SCHEMA_VERSION := 1
## The record's mode word +0x54 (FE-1, HERO_RESEARCH.md "FE-1"): 0 = normal, 1 = Ironman (Read: 0x527100, 0x4553f0,
## 0x5210b0 test `== 1`; the Customize list 0x54ee10 writes 0 or 1). Stored as the profile's "mode" string.
const MODE_NORMAL := "normal"
const MODE_IRONMAN := "ironman"
var data: Dictionary = {}

func is_ironman() -> bool:
	return String(data.get("mode", MODE_NORMAL)) == MODE_IRONMAN

## Record byte +0x10e6 ("Freeze Hero", PNL_HEROINFO's checkbox 0x1ad; Read: 0x527100, 0x4553f0 and the level-up check
## 0x4d60f0 area read its copy 0x70adb2): a frozen hero gains no XP and does not level. Kept in the profile's extensions.
func frozen() -> bool:
	return bool(data.get("extensions", {}).get("frozen", false))

## A new normal hero (0x54b040 -> 0x54bbd0): 0x54c000 clears the record, 0x54bee0(race) and 0x54bfe0(class) fill it
## (HeroRules.creation / race_identity, Emulated for every race x class). Items empty, hotkeys -1.
static func create(profile_id: String, hero_name: String, race: int = 0, klass: int = 0) -> RefCounted:
	var profile = load("res://simulation/hero_profile.gd").new()
	var created := Rules.creation(race, klass)
	# Knight / Warrior keeps milestone 6b's definition (the same emulated values plus the skill names).
	if race == 0 and klass == 0: created.skills = Rules.definitions().skills.duplicate(true)
	var identity := Rules.race_identity(race)
	profile.data = {"schema_version": SCHEMA_VERSION, "id": profile_id, "name": hero_name,
		"race_id": clampi(race, 0, Rules.RACES - 1), "class_id": clampi(klass, 0, Rules.CLASSES - 1), "mode": "normal",
		"original_type_id": identity.art,
		"portrait_id": int(identity.portrait), "level": 1, "xp": 0, "stats": created.stats,
		"skills": created.skills, "stat_points": 0, "skill_points": 0,
		"equipment": [{}, {}, {}, {}, {}, {}, {}], "backpack": [{}, {}, {}, {}],
		"stash": [{}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}, {}], "retinue": [], "graveyard": [],
		"history": {"battles_fought": 0, "battles_won": 0, "heroes_killed": 0, "enemies_killed": 0,
			"dragons_killed": 0, "titans_killed": 0, "quests_completed": 0, "spells_cast": 0,
			"games_by_race": empty_race_counters(), "wins_by_race": empty_race_counters()},
		"extensions": {}, "applied_results": []}
	profile.data["spell_hotkeys"] = [-1, -1, -1, -1, -1, -1, -1, -1]
	profile.data["voice_id"] = identity.voice
	return profile

## Record +0x7a (wins) and +0x9a (games), 16 shorts each, indexed by the race the hero's player plays (0x708f96 of the
## local slot: 0x4e2790 line 147302, the Continue handler 0x4549a7), not by the hero's own race (milestone 11b, Read).
static func empty_race_counters() -> Array:
	var out: Array = []
	out.resize(Rules.RACES)
	out.fill(0)
	return out

func snapshot() -> Dictionary:
	return data.duplicate(true)

func validate() -> String:
	if not json_value(data): return "Hero data must contain finite JSON values only."
	if data.get("schema_version") != SCHEMA_VERSION: return "Unsupported hero schema version."
	for key in ["id", "name", "mode", "original_type_id"]:
		if not data.get(key) is String or data[key].is_empty(): return "Missing hero " + key
	if not valid_id(data.id): return "Invalid profile ID."
	if data.name.length() > 19 or data.name.strip_edges().is_empty(): return "Hero names must contain 1–19 characters."
	if data.mode != MODE_NORMAL and data.mode != MODE_IRONMAN: return "Unknown hero mode."
	if not whole_number(data.get("race_id")) or data.race_id < 0 or data.race_id >= Rules.RACES: return "Invalid hero race."
	if not whole_number(data.get("class_id")) or data.class_id < 0 or data.class_id >= Rules.CLASSES: return "Invalid hero class."
	# Art, voice and portrait: the race's default (0x54bee0) or a choice of its Customize lists (0x6140f8 / 0x612ff0 /
	# 0x612178; the rebuild's creation screen writes the defaults, Customize is Open).
	var identity := Rules.race_identity(int(data.race_id))
	var choices := Rules.race_choices(int(data.race_id))
	if data.original_type_id != identity.art and not data.original_type_id in choices.art: return "Unsupported hero art for its race."
	if not data.get("voice_id") is String or (data.voice_id != identity.voice and not data.voice_id in choices.voices_english):
		return "Unsupported hero voice."
	for key in ["level", "xp", "stat_points", "skill_points", "portrait_id"]:
		if not whole_number(data.get(key)) or data[key] < 0: return "Invalid " + key
	if data.level < 1 or data.level > 999 or data.xp > 2147483647: return "Invalid progression range."
	if int(data.portrait_id) != int(identity.portrait) and not int(data.portrait_id) in choices.portraits.map(func(v): return int(v)):
		return "Unsupported portrait for the hero's race."
	if data.xp < Rules.xp_threshold(int(data.level)): return "XP is below the stored level."
	if not data.get("spell_hotkeys") is Array or data.spell_hotkeys.size() != 8: return "Invalid spell hotkeys."
	for spell in data.spell_hotkeys:
		if not whole_number(spell) or spell < -1 or spell > 32767: return "Invalid spell hotkey."
	if not data.get("stats") is Array or data.stats.size() != 4: return "Invalid statistics."
	for value in data.stats:
		# 0 is a real starting value (Dwarf Runemaster Dexterity 0, 0x54c0a0, Emulated).
		if not whole_number(value) or value < 0 or value > 32767: return "Invalid statistic value."
	var definitions: Array = Rules.creation(int(data.race_id), int(data.class_id)).skills
	if not data.get("skills") is Array or data.skills.size() != definitions.size(): return "Invalid skills."
	for i in range(definitions.size()):
		var skill = data.skills[i]
		if not skill is Dictionary or skill.get("id") != definitions[i].id or skill.get("unlock_level") != definitions[i].unlock_level:
			return "Skill identity or prerequisite changed."
		if not whole_number(skill.get("rank")) or skill.rank < 0 or skill.rank > 32767: return "Invalid skill rank."
	for pair in [["equipment", 7], ["backpack", 4], ["stash", 12]]:
		if not data.get(pair[0]) is Array or data[pair[0]].size() != pair[1]: return "Invalid " + pair[0]
		for item in data[pair[0]]:
			if not item is Dictionary: return "Invalid item record."
	for pair in [["retinue", 8], ["graveyard", 10], ["applied_results", 100000]]:
		if not data.get(pair[0]) is Array or data[pair[0]].size() > pair[1]: return "Invalid " + pair[0]
	var retinue_ids: Array = []
	for unit in data.retinue:
		if not unit is Dictionary or not unit.get("original_type_id") is String or unit.original_type_id.length() != 4:
			return "Invalid retinue identity."
		if not unit.get("id") is String or not valid_id(unit.id): return "Invalid rebuild retinue ID."
		if unit.id in retinue_ids: return "Duplicate rebuild retinue ID."
		retinue_ids.append(unit.id)
		if not whole_number(unit.get("xp")) or unit.xp < 0 or unit.xp > 20000: return "Invalid retinue experience."
		if not whole_number(unit.get("medal_level")) or unit.medal_level < 0 or unit.medal_level > 19: return "Invalid retinue medal level."
		if not unit.get("permanent_state") is Dictionary: return "Invalid retinue permanent state."
	for entry in data.graveyard:
		if not entry is Dictionary: return "Invalid graveyard record."
	for result in data.applied_results:
		if not result is String or not valid_id(result): return "Invalid applied result identity."
	if not data.get("history") is Dictionary or not data.get("extensions") is Dictionary: return "Invalid hero metadata."
	for key in ["battles_fought", "battles_won", "heroes_killed", "enemies_killed", "dragons_killed", "titans_killed", "quests_completed", "spells_cast"]:
		if not whole_number(data.history.get(key)) or data.history[key] < 0: return "Invalid history counter."
	# Milestone 11b: per-race counters (absent in profiles saved before it; begin() adds them).
	for key in ["games_by_race", "wins_by_race"]:
		if not data.history.has(key): continue
		if not data.history[key] is Array or data.history[key].size() != Rules.RACES: return "Invalid per-race counters."
		for value in data.history[key]:
			if not whole_number(value) or value < 0 or value > 32767: return "Invalid per-race counter."
	return ""

static func json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	if value == null or value is bool or value is String or value is int: return true
	if value is float: return is_finite(value)
	if value is Array:
		for child in value:
			if not json_value(child, depth + 1): return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not json_value(value[key], depth + 1): return false
		return true
	return false

static func whole_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floor(float(value))

static func valid_id(value: String) -> bool:
	if value.is_empty() or value == "selection" or value.length() > 80: return false
	for character in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

## UI/0x4d60f0 advances one level, then waits for point allocation.
func advance_level() -> bool:
	if data.level >= 999 or data.stat_points > 0 or data.skill_points > 0 or frozen(): return false
	if data.xp < Rules.xp_threshold(int(data.level) + 1): return false
	data.level += 1
	data.stat_points += 1
	data.skill_points += 1
	return true

func gain_xp(amount: int) -> bool:
	if amount < 0 or data.xp + amount > 2147483647: return false
	data.xp += amount
	advance_level()
	return true

func allocate_stat(index: int) -> bool:
	if index < 0 or index > 3 or data.stat_points < 1 or data.stats[index] >= 32767: return false
	data.stats[index] += 1
	data.stat_points -= 1
	return true

func allocate_skill(id: int) -> bool:
	if data.skill_points < 1: return false
	for skill in data.skills:
		if int(skill.id) != id: continue
		if data.level < skill.unlock_level or skill.rank >= 32767: return false
		skill.rank += 1
		data.skill_points -= 1
		return true
	return false
