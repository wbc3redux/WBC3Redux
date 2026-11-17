extends RefCounted
## Boundary for the future match controller. Never infers a battle outcome.
const Profile = preload("res://simulation/hero_profile.gd")
const Rules = preload("res://simulation/hero_rules.gd")
const Entity = preload("res://simulation/entity_state.gd")
const Effects = preload("res://simulation/hero_effects.gd")
const ProductionRules = preload("res://simulation/production_rules.gd")
signal profile_changed(profile_id: String)
var profile: Profile
var entity: Entity
var last_error := ""

func bind(saved: Profile, hero: Entity) -> bool:
	last_error = saved.validate()
	if not last_error.is_empty(): return false
	if hero.original_type_id != saved.data.original_type_id:
		last_error = "Hero entity type does not match the profile."
		return false
	profile = Profile.new()
	profile.data = saved.snapshot()
	entity = hero
	start_mana_potions()
	return true

func persistent_state() -> Dictionary:
	return {} if profile == null else profile.snapshot()

## Milestone 11: a computer player's hero (0x42a0d0) is a match-only record (never written to HeroData); its profile
## copy carries the record's class, stats, skills and items and skips the persistent-profile validation.
var computer := false

func bind_computer(record: Dictionary, hero: Entity, hero_name: String) -> bool:
	# 0x42a0d0 gives the record its race's hero type (AHHX, ADHX, ... ARHX; production_rules.gd HERO_TYPES).
	if hero.original_type_id != ProductionRules.hero_type(int(record.get("race", 0))):
		last_error = "Hero entity type does not match the record."
		return false
	# 0x42a0d0 runs 0x54be60 (0x54bee0: the race's portrait and voice, 0x54f1d0) on the record; its art is the race switch.
	profile = Profile.create("computer-hero", hero_name, int(record.get("race", 0)), int(record["class"]))
	var d: Dictionary = profile.data
	d.original_type_id = hero.original_type_id
	d.level = int(record.level)
	d.xp = int(record.xp)
	d.stats = record.stats.duplicate()
	d.skills = []
	for s in record.skills:
		if int(s[0]) != 0: d.skills.append({"id": int(s[0]), "unlock_level": int(s[1]), "rank": int(s[2])})
	d.equipment = record.equipment.map(func(id): return {} if int(id) <= 0 else {"item": int(id), "source": "computer"})
	d.backpack = record.backpack.map(func(id): return {} if int(id) <= 0 else {"item": int(id), "source": "computer"})
	d.history.battles_fought = int(record.get("battles_fought", 0))
	entity = hero
	computer = true
	start_mana_potions()
	return true

## B1-6e (SPELLS_RESEARCH.md "B1-6e"): match state of the player's hero block that the hero spells change.
## * potions: +0x184 (0x709344), 4 at the match start (0x54fd50 with its start flag, Read); Brew Potion adds the cast
##   level (0x5757f0, Emulated), 0x561d80 drinks one (Emulated).
## * school_bonus: 0x70d496 + 0x1a p, thirteen ranks 0x54fd50 adds to the school ranks before the item powers (Read; the
##   rise by 0x438180 Emulated: Increase Casting / PSPR / PARR).
## * item_factor / school_item_factor: 0x40c380 / 0x40c500 double their sums while the player's hero has effect 0x80
##   (Spellforge) and zero them while another player's hero has 0x7f (Disjunction; 0x40c380 skips allies of the player,
##   0x40c500 does not: Emulated, fixtures "item_powers"); Spells.step keeps them (HeroSpells.sync_item_factors).
var potions := 4
## B1-7: +0x182 (0x709342), the mana potions: 4 at the match start plus 0x556ea0(0x5f, 0x556b50(p, 0x5f, 1, 0), 1) when
## that is non-zero (0x54fd50 with its start flag, Read); 0x561c30 drinks one (Emulated, REVIEW_AI_SPELLS.md). Set when the hero is bound.
var mana_potions := -1
var school_bonus: Array = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var item_factor := 1
var school_item_factor := 1
## Setup rows: More Options "No Hero Items" (0x749c68, SKIRMISH_RESEARCH.md "Setup rows"): the block carries it so that
## HeroEffects' item terms (0x40c380, 0x40c500, the weapon of 0x526310) read 0. Set where the hero is bound (main.gd).
var no_items := false

## The hero block HeroEffects reads (0x7091c0 + p * 0x194), with the hero object's current hit points.
func block(hp: int = 1) -> Dictionary:
	if profile == null: return {}
	var b := Effects.block_from_profile(profile.data, true, hp)
	if item_factor != 1: b["item_factor"] = item_factor
	if school_item_factor != 1: b["school_item_factor"] = school_item_factor
	if school_bonus.any(func(v): return int(v) != 0): b["school_bonus"] = school_bonus.duplicate()
	if no_items: b["no_items"] = true
	return b

## 0x54fd50's start flag: called where the hero is bound (REVIEW_AI_SPELLS.md R3).
func start_mana_potions():
	var v := Effects.lookup(block(), 0x5f, 1, false)
	mana_potions = 4 + (Effects.s16(Effects.skill_term(0x5f, v, 1)) if v != 0 else 0)

func mana_potion_count() -> int:
	if mana_potions < 0: start_mana_potions()               # a hero bound without bind() / bind_computer() (test worlds)
	return mana_potions

## The record 0x54fd50 builds the hero unit from.
func record() -> Dictionary:
	var b := block()
	var r := {"class": int(profile.data.get("class_id", 0)), "level": int(profile.data.level), "stats": profile.data.stats,
		"skills": b.skills, "equipment": b.equipment}
	if no_items: r["no_items"] = true                     # setup rows: 0x54fd50 skips its item school loop (0x749c68)
	return r

## Inventory moves inside the match (messages 0x192 / 0x193 between the hero's eleven slots, 0x4a7e90): the item
## goes to `to` when 0x55ec20 accepts it there; an occupied target swaps when the displaced item fits the source.
## Slots 0..6 equipment, 7..10 backpack. The block refresh (0x54fd50) follows; saving happens with the results.
func move_item(from: int, to: int) -> bool:
	if profile == null or from == to or from < 0 or to < 0 or from > 10 or to > 10: return false
	var a: Dictionary = _slot(from)
	var b: Dictionary = _slot(to)
	if a.is_empty(): return false
	if not Effects.equip_allowed(int(a.item), to): return false
	if not b.is_empty() and not Effects.equip_allowed(int(b.item), from): return false
	_set_slot(to, a)
	_set_slot(from, b)
	profile_changed.emit(profile.data.id)
	return true

## The inventory dialog (main.gd, 0x55e0e0) writes a slot directly: its own fit test (0x55ec20) has run.
func set_slot(i: int, value: Dictionary):
	if profile == null or i < 0 or i > 10: return
	_set_slot(i, value)
	if not value.is_empty() and String(value.get("source", "")) == "ground" and i >= 7:
		match_items.append({"item": int(value.item), "source": "ground", "slot": i})
	profile_changed.emit(profile.data.id)

func _slot(i: int) -> Dictionary:
	return profile.data.equipment[i] if i < 7 else profile.data.backpack[i - 7]

func _set_slot(i: int, value: Dictionary):
	if i < 7: profile.data.equipment[i] = value
	else: profile.data.backpack[i - 7] = value

## Takes item `item_id` into the first empty backpack slot (picking up a treasure, the "Ground" list); -1 when full.
func take_item(item_id: int, source: String) -> int:
	if profile == null: return -1
	for i in range(profile.data.backpack.size()):
		if profile.data.backpack[i].is_empty():
			profile.data.backpack[i] = {"item": item_id, "source": source}
			match_items.append({"item": item_id, "source": source, "slot": 7 + i})
			profile_changed.emit(profile.data.id)
			return 7 + i
	return -1

## Removes the item in slot `i` (dropping it on the ground) and returns its id, 0 when empty.
func drop_slot(i: int) -> int:
	if profile == null or i < 0 or i > 10: return 0
	var item: Dictionary = _slot(i)
	if item.is_empty(): return 0
	_set_slot(i, {})
	profile_changed.emit(profile.data.id)
	return int(item.item)

## Caller supplies already resolved original XP awards (0x527100).
## This does not award XP for elapsed time, conversion, or guessed kill categories.
## B1-7 (AI_RESEARCH.md section 18, Read): 0x527100 adds a hero's XP to its player's block (+0x24) for every player, but
## only the local player's hero levels up in a match (0x4d60f0 and the level messages 0x4af820 / 0x4af8d0 act on
## 0x709100 alone): a computer hero keeps the level and skills 0x42a0d0 gave it.
func award_xp(amount: int) -> bool:
	if profile == null: return false
	if computer:
		if amount < 0 or profile.data.xp + amount > 2147483647: return false
		profile.data.xp += amount
		return true
	# FE-1 (Read, 0x527100): the local hero's award is skipped while it is frozen (0x70adb2) and doubled in Ironman mode
	# (the mode word 0x709d20 == 1: the profile's gain, 0x709d04, takes twice the award).
	if amount >= 0 and profile.frozen(): return true
	if amount >= 0 and profile.is_ironman(): amount *= 2
	if not profile.gain_xp(amount): return false
	profile_changed.emit(profile.data.id)
	return true

## Items won during the match (milestone 9: quest rewards 0x580d00). An item goes to the first empty backpack slot of
## the in-match copy as {"item": original item id, "source": ...}; with a full backpack it is refused (the original's
## placement for that case is Open). Item stat effects are not applied: the item code is not traced. Milestone 10 passes
## inventory_changes() to finish().
var match_items: Array = []

func receive_item(item_id: int, source: String) -> bool:
	if profile == null: return false
	for i in range(profile.data.backpack.size()):
		if profile.data.backpack[i].is_empty():
			profile.data.backpack[i] = {"item": item_id, "source": source}
			match_items.append({"item": item_id, "source": source, "slot": i})
			profile_changed.emit(profile.data.id)
			return true
	last_error = "Backpack full."
	return false

func inventory_changes() -> Dictionary:
	return {} if profile == null else {"equipment": profile.data.equipment.duplicate(true), "backpack": profile.data.backpack.duplicate(true)}

## FE-1: an Ironman hero's record was deleted at its death (hero_died, 0x522260); finish() then writes nothing.
var deleted := false
var save_directory := ""            # where the hero's saved games live; "" = SaveGame.default_directory()

## The hero's saved games (its save and its autosave: the files the hero book's Load Game reads) which go with it.
func saved_game_files() -> Array:
	var save_game = preload("res://simulation/save_game.gd")
	var directory := save_directory if save_directory != "" else save_game.default_directory()
	var id := String(profile.data.id)
	return [save_game.path_for(id, directory), save_game.path_for(id + "-" + save_game.AUTOSAVE_NAME, directory)]

## Normal hero death loses backpack slots 7..10; equipment and stash survive.
## Original writes immediately. Commit the copy only after a successful save.
func hero_died(store) -> bool:
	if profile == null: return false
	if computer:
		profile.data.backpack = [{}, {}, {}, {}]
		return true
	if profile.is_ironman():
		# FE-1 (Read): the local player's hero dies with the mode word 0x709d20 == 1 -> 0x522260 at once: the hero's
		# saved game and its record in the hero book are deleted; the match goes on with the in-match copy.
		if not store.delete_profile(String(profile.data.id), saved_game_files()):
			last_error = store.last_error
			return false
		deleted = true
		profile.data.backpack = [{}, {}, {}, {}]
		profile_changed.emit(profile.data.id)
		return true
	var candidate := Profile.new()
	candidate.data = profile.snapshot()
	candidate.data.backpack = [{}, {}, {}, {}]
	if not store.save_profile(candidate):
		last_error = store.last_error
		return false
	profile = candidate
	profile_changed.emit(profile.data.id)
	return true

## Match start (0x4e2790, Read): battles fought (+0x14c) is counted and the hero record is written to HeroData before
## the battle, so an abandoned or crashed match still counts as fought. Milestone 11b: the games counter of the race the
## player plays (+0x9a + 0x708f96[local] * 2, line 147302; `slot_race` -1 = not counted) goes up with it. Applies once
## per match id.
func begin(store, match_id: String, slot_race: int = -1) -> bool:
	last_error = ""
	if computer: return true
	if profile == null or not Profile.valid_id(match_id + "-start"):
		last_error = "Missing hero or match identity."
		return false
	if (match_id + "-start") in profile.data.applied_results: return true
	var candidate := Profile.new()
	candidate.data = profile.snapshot()
	candidate.data.history.battles_fought += 1
	if slot_race >= 0 and slot_race < Rules.RACES:
		_race_counters(candidate.data)
		candidate.data.history.games_by_race[slot_race] = mini(32767, int(candidate.data.history.games_by_race[slot_race]) + 1)
	candidate.data.applied_results.append(match_id + "-start")
	if not store.save_profile(candidate):
		last_error = store.last_error
		return false
	profile = candidate
	profile_changed.emit(profile.data.id)
	return true

## Explicit completed normal-skirmish boundary, not a quit handler.
## Item and retinue changes must already have gone through their original
## gameplay/selection rules. Omission preserves existing records.
## `counted_at_start`: begin() already counted the battle (the match controller's path, 0x4e2790).
func finish(store, result_id: String, context: Dictionary, changes: Dictionary = {}, counted_at_start: bool = false) -> bool:
	last_error = ""
	if profile == null or not Profile.valid_id(result_id):
		last_error = "Missing hero or result identity."
		return false
	if result_id in profile.data.applied_results: return true
	# FE-1 (Read, 0x4553f0 -> 0x455d60): an Ironman hero that is dead at the end is deleted from the hero book and the
	# result pays 0 XP; nothing is written. (The record is normally gone already: hero_died deleted it at the death.)
	if profile.is_ironman() and (deleted or bool(context.get("hero_died", false))):
		if not deleted and not store.delete_profile(String(profile.data.id), saved_game_files()):
			last_error = store.last_error
			return false
		deleted = true
		profile.data.applied_results.append(result_id)
		profile_changed.emit(profile.data.id)
		return true
	# A result already in the stored file (a second session, or a reload) is never applied again.
	var stored = store.load_profile(profile.data.id)
	if stored != null and result_id in stored.data.applied_results:
		last_error = "Result already applied to the saved hero."
		return false
	for key in changes:
		if key not in ["equipment", "backpack", "stash", "retinue_updates", "retinue_scan"]:
			last_error = "Unsupported result change; retinue selection is not yet recovered."
			return false
		if key == "retinue_scan":
			continue
		if not changes[key] is Array:
			last_error = "Result inventory and retinue changes must be arrays."
			return false
	var candidate := Profile.new()
	candidate.data = profile.snapshot()
	for key in changes:
		if key != "retinue_updates" and key != "retinue_scan": candidate.data[key] = changes[key].duplicate(true)
	# Playtest 2026-11-11: the end-of-battle scan 0x43f3e0 (simulation/retinue_scan.gd): the survivors' ranks and
	# experience, the battles, the dead to the graveyard. Only the retinue's own members may change; types stay.
	if changes.has("retinue_scan"):
		var scanned = changes.retinue_scan
		if not scanned is Dictionary or not scanned.get("retinue") is Array or not scanned.get("graveyard") is Array 				or scanned.retinue.size() > 8 or scanned.graveyard.size() > 10:
			last_error = "Invalid retinue scan."
			return false
		var before := {}
		for unit in candidate.data.retinue: before[String(unit.id)] = String(unit.original_type_id)
		for unit in scanned.retinue:
			if not unit is Dictionary or not before.has(String(unit.get("id", ""))) or before[String(unit.id)] != String(unit.get("original_type_id", "")):
				last_error = "The retinue scan may only update the retinue's own members."
				return false
		candidate.data.retinue = scanned.retinue.duplicate(true)
		candidate.data.graveyard = scanned.graveyard.duplicate(true)
	# retinue_updates: existing survivors only (the older path; the match uses retinue_scan). New members join on the
	# retinue screen (hero_advance.gd, 0x4427d0 / 0x443890), which saves the hero itself.
	if changes.has("retinue_updates"):
		if not changes.retinue_updates is Array:
			last_error = "Invalid retinue updates."
			return false
		var seen: Array = []
		for update in changes.retinue_updates:
			if not update is Dictionary or update.get("id") in seen:
				last_error = "Invalid or duplicate retinue update."
				return false
			var found := false
			for i in range(candidate.data.retinue.size()):
				var previous: Dictionary = candidate.data.retinue[i]
				if update.get("id") != previous.id: continue
				if update.get("original_type_id") != previous.original_type_id:
					last_error = "Retinue update changed unit type."
					return false
				candidate.data.retinue[i] = update.duplicate(true)
				seen.append(update.id)
				found = true
				break
			if not found:
				last_error = "New retinue selection is not yet recovered."
				return false
	if context.hero_died: candidate.data.backpack = [{}, {}, {}, {}]
	var resolved := context.duplicate(true)
	resolved.hero_level = candidate.data.level
	resolved["ironman"] = candidate.is_ironman()                  # FE-1: the mode word (a double win award)
	resolved["frozen"] = candidate.frozen()                       # FE-1: Freeze Hero (0x70adb2): no award
	# 0x4553f0: a match shorter than 300 s (0x41c510) pays the short award instead of the ordinary branch.
	var bonus := Rules.result_bonus(resolved)
	if context.get("short_match", false):
		bonus = 0 if candidate.frozen() else Rules.short_match_bonus(bool(context.won), int(context.get("victory_option", 0)), int(context.unit_setup), candidate.is_ironman(), bool(context.get("hero_died", false)))
	if bonus < 0 or candidate.data.xp + bonus > 2147483647:
		last_error = "Invalid XP award."
		return false
	candidate.data.xp += bonus
	var levels := 0 if candidate.frozen() else Rules.result_levels(int(candidate.data.level), int(candidate.data.xp))
	candidate.data.level += levels
	candidate.data.stat_points += levels
	candidate.data.skill_points += levels
	if not counted_at_start: candidate.data.history.battles_fought += 1
	if context.won: candidate.data.history.battles_won += 1
	# Continue (0x4549a7): a victory also counts for the race the player played (+0x7a + 0x708f96[local] * 2).
	var slot_race := int(context.get("slot_race", -1))
	if context.won and slot_race >= 0 and slot_race < Rules.RACES:
		_race_counters(candidate.data)
		candidate.data.history.wins_by_race[slot_race] = mini(32767, int(candidate.data.history.wins_by_race[slot_race]) + 1)
	candidate.data.applied_results.append(result_id)
	if not store.save_profile(candidate):
		last_error = store.last_error
		return false
	profile = candidate
	profile_changed.emit(profile.data.id)
	return true

## Profiles saved before milestone 11b have no per-race counters: they start at 0.
static func _race_counters(data: Dictionary):
	for key in ["games_by_race", "wins_by_race"]:
		if not data.history.has(key) or not data.history[key] is Array or data.history[key].size() != Rules.RACES:
			data.history[key] = Profile.empty_race_counters()

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The in-match profile copy (with the match's XP, items and potions), its entity.
func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, ["profile", "entity"])
	s["profile"] = profile.data.duplicate(true) if profile != null else null
	s["entity"] = refs.ref(entity)
	return s

func load_state(state: Dictionary, refs):
	preload("res://simulation/save_game.gd").restore(self, state, ["profile", "entity"])
	profile = null
	if state.profile != null:
		profile = Profile.new()
		profile.data = state.profile.duplicate(true)
	entity = refs.get_obj(int(state.entity))
