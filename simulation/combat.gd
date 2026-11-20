extends RefCounted
## Combat world controller (milestone 8): attack orders, approach, swing timing, melee and missile hits, death, XP.
## Milestone 9: the unit attitude scripts (unit_ai.gd) replace the provisional acquisition; towers shoot (0x52d0d0 /
## 0x52c250). Evidence labels and open items: COMBAT_RESEARCH.md, ENCOUNTERS_RESEARCH.md. Numeric rules live in
## combat_rules.gd (Emulated); this file is the state machine around them (Read, partly provisional).
const Rules = preload("res://simulation/combat_rules.gd")
const UnitAI = preload("res://simulation/unit_ai.gd")
const Rng = preload("res://simulation/combat_rng.gd")
const HeroRules = preload("res://simulation/hero_rules.gd")
const HeroEffects = preload("res://simulation/hero_effects.gd")
const Missiles = preload("res://simulation/missiles.gd")
const ResearchEffects = preload("res://simulation/research_effects.gd")
const RacePowers = preload("res://simulation/race_powers.gd")
const UnitRanks = preload("res://simulation/unit_ranks.gd")
const Advancement = preload("res://simulation/advancement.gd")
const Criticals = preload("res://simulation/criticals.gd")   # G-4: the critical-hit side effects

const UPDATE_MS := 25               # 0x456500: game updates run on a 25 ms periodic callback
const DEATH_ENTRY_MS := 100         # 0x5374a0: d slot, 100 ms per frame
const DEATH_FRAMES := 13            # AHKX d slot frame count
const CORPSE_MS := (DEATH_FRAMES + 1) * 50 + 30000   # last d entry: 30.7 s after the death starts
const SCAN_RADIUS_MIN := 12         # 0x5086f0: window r = max(12, range)
const TOWER_PERIOD_MS := [6000, 3000, 2400, 1900, 1600, 1400, 1200, 1000, 900, 800, 700, 600, 500, 450, 400, 350, 300]  # 0x6114bc
const HERO_AURA_CELLS := 20         # 0x532a20: the 20 x 20 distance table 0x44650 (filled by 0x5329a0); no source reaches it
const MISSILE_IDS := {"unit": "EMA0", "BWTD": "EMA0", "BWTE": "EMM0"}   # Army.cfg / Building.cfg shoot ids (0x40ac00, ART_RESEARCH.md)
const BURNING_MISSILE := "EMF1"     # B2-1: missile kind 1 (message 0x204 level 0 at the impact)
const PRIORITY_RANGE := 25          # 0x533c40: candidates farther than 25 cells score 0

signal damaged(kind: String, id: int, amount: int, attacker_id: int)
signal died(kind: String, id: int, killer_owner: int)
signal missile_launched(info: Dictionary)
signal missile_landed(info: Dictionary)
signal xp_awarded(owner: int, amount: int, reason: String)
signal swing_started(id: int, info: Dictionary)
signal hit_entry(id: int, swing: Dictionary)       # 0x523150 reached the hit entry (the sound layer plays 0x50d300 here)
signal notice(text: String)
signal berserk_changed(id: int, level: int, first: bool)   # B2-1: the state 0x527720 began (level >= 0) or ended (-1)
signal eaten(killer_id: int, cell: Vector2i)               # B2-1: 0x5210b0 Eating.wav and its effect (main.gd)
signal rank_gained(id: int, rank: int)                    # R-1: 0x527100 promoted a unit (main.gd: effects, sound, message)

var rng
var navigator
var production
var units: Array = []                  # unit id -> UnitAgent (main.units)
var teams: Array = [1, 2, 0, 0, 0, 0, 0]
var relations := PackedByteArray()      # optional 0x748915 table (49 bytes, [a + b * 7] != 0: allied); empty = derived from teams
var fighters: Dictionary = {}          # unit id -> state dictionary
var heroes: Dictionary = {}            # owner -> {"unit": id, "match": HeroMatch}
var missiles: Array = []               # simulation/missiles.gd states (0x5eafdc objects), advanced by 0x53fbc0 each update
var sprite_rect: Callable              # optional (kind, id) -> [x, y, w, h]: the drawn sprite rectangle (+0x58..+0x5e) for launch points
var pixel_test: Callable               # optional (building id, x, y) -> bool: opaque pixel of the building sheet (0x487c60)
var visibility                         # optional Visibility
var ai_players: Dictionary = {}        # owner -> true: no fog test for acquisition (0x70d6a4)
## 0x47f560 reads the machine's one fog object, whoever searches (Read, 0x5334f0): the neutral player 6 (never flagged in
## 0x70d6a4) therefore finds targets where the local player sees. The rebuild keeps a map per side, so a human searches
## its own; the neutral reads this player's (playtest 2026-11-10: with its own, never lit, lair and encampment guards
## did not fight back under fog).
var fog_viewer := 0
var now_ms := 0
var next_update_ms := 0
var auto_acquire := true:            # harness switch: the attitude scripts run (the original always runs them)
	set(value):
		auto_acquire = value
		if ai != null: ai.enabled = value
var ai                                 # UnitAI (attitude scripts, hit list, flight)
var towers: Dictionary = {}            # building id -> tower state (0x52d0d0 target, 0x52c250 shot timer)
const NO_LATENCY := [0, 0]
var ani: Dictionary = {}               # type id -> {"attack_frames", "hit_frame", "death_frames"} from ANI (encounters.json)
var game_mode := 0                     # match option: 0x748946 (3 = crit side effects off); skirmish value Open, image value 0
var kills := {0: 0, 1: 0}
var xp_log: Array = []
var building_bonus: Dictionary = {}     # owner -> 0x52ae70 combat term of a computer player's buildings (Read)
var pre_update: Callable                # the AI manager (0x505310), called before the scripts of each update
var last_killer := -1                 # killer unit id of the latest death, valid while `died` is emitted (match counters)
var improved := false                  # DELIBERATE MODERN CHANGE (modern_rules.gd "Movement"): spread_target_cell
var research = ResearchEffects.new()    # milestone 13: the owner's research terms of the unit getters (research_effects.gd)
var spells                             # B1-4: simulation/spells.gd (unit mana, casts, status effects); set by Spells.new
var lord_counter: Dictionary = {}      # B2-1: owner -> 0x70d622 (short): +2 AHEX, +1 ABEX at creation, the same off at death
var type_status: Callable              # R-1: type id -> Army.cfg STATUS (0x585970, main.gd status_flags); 0 without it

func _init(random, nav, production_world, unit_list: Array):
	rng = random
	navigator = nav
	production = production_world
	units = unit_list
	ai = UnitAI.new(self)

# ----------------------------------------------------------------------------------------- registration
func register(unit_id: int, owner: int, type_id: String, stats: Dictionary, is_hero: bool = false):
	var unit = units[unit_id]
	if not is_hero: stats["flags"] = Rules.live_status(type_id, int(stats.get("flags", 0)))   # G-1: 0x5273c0 (Emulated)
	# Script state (+0x130..+0x142, +0x270): the default attitude is ARM +0xf6 (2, Defensive, for every slice unit) and 2
	# for heroes (0x519fd0); the guard point is the cell where the script was assigned (0x506f10).
	var f := {"id": unit_id, "owner": owner, "type_id": type_id, "base": stats.duplicate(), "stats": stats.duplicate(), "hp": int(stats.max_hp), "max_hp": int(stats.max_hp),
		"order": null, "state": "idle", "swing": null, "death_ms": -1, "xp": 0, "rank": 0, "hero": is_hero,
		"kills": 0, "removed": false, "script": UnitAI.DEFAULT_SCRIPT, "leader": -1, "leader_flag": 0, "guard": unit.cell, "last_action": -1,
		"remembered": -1, "remembered_search": -1, "patrol": 0, "cur": null, "resume": null,
		"may_join": not preload("res://simulation/retinue_scan.gd").NEVER_JOIN.has(type_id)}   # +0xc2 (0x519ae0): may join a retinue
	fighters[unit_id] = f
	# B2-1 (R7, Read: 0x4a4560, 0x4a49e0): the Knight Lord adds 2 and the Warlord 1 to their owner's counter.
	if RacePowers.LORD_COUNTER.has(type_id): lord_counter[owner] = int(lord_counter.get(owner, 0)) + int(RacePowers.LORD_COUNTER[type_id])
	# B3-1 (E14, Read 0x43bfb0 decompile 40174): a Wolfrider created with PRAB carries the type class word 0x606 (rabies 6).
	if type_id == RacePowers.RABID and production != null and production.research_level(owner, RacePowers.RABIES_RESEARCH) != 0:
		f["rabies"] = RacePowers.RABIES_NEW
	_apply_research(f)
	if spells != null: spells.setup_unit(f)  # B1-4: unit mana from the Army.cfg MANA pair (0x528cd0)
	unit.owner_id = owner
	unit.hp = f.hp
	unit.max_hp = f.max_hp
	return f

## Milestone 13: the getters 0x51bd10 / 0x51c460 / 0x526b70 / 0x526310 / 0x5260a0 read the owner's upgrade table and research
## live, so a completion changes existing units at once (research_effects.gd). The fighter keeps its base block ("base").
func _apply_research(f):
	if production == null or not f.has("base"): return
	var list: Array = production.research.get(f.owner, [])
	f.stats = research.apply(f.base, String(f.type_id), list, production.race_of(f.owner), int(f.base.get("flags", 0)), bool(f.hero))
	if not f.hero and units.size() > f.id and units[f.id] != null: units[f.id].base_speed = int(f.stats.speed) + _brew(f, BREW_SPEED) + int(f.get("status_speed", 0))   # B1-6b: Spells.sync_speed

# B1-3 hooks (B1_3_RESEARCH.md): the weather object's terms (simulation/day_night.gd; null = none, as before B1-3) and the
# Dwarven Brew (+0x1f8 drunk: combat +4 in 0x51bd10, speed +4 in 0x51c460; main.gd drinks and sobers).
var day_night = null
const BREW_COMBAT := 4
const BREW_SPEED := 4

func _brew(f, amount: int) -> int:
	return amount if int(f.get("drunk_until", 0)) > 0 else 0

func refresh_brew(f):
	_apply_research(f)

## 0x51bd10's weather block on the block's raw combat (+0x92 = the fighter's base combat): the difference it makes.
func _time_of_day_term(f) -> int:
	if day_night == null or not day_night.enabled: return 0
	var raw := int(f.base.get("combat", 0))
	var shadow := HeroEffects.skill_effect(hero_block(f.owner), 0x36) if f.hero else 0
	return day_night.combat_value(raw, int(f.stats.get("flags", 0)), String(f.type_id), shadow) - raw

## Called when `owner` completes research (Production.research_completed).
func refresh_research(owner: int):
	for f in fighters.values():
		if f.owner == owner and not f.removed: _apply_research(f)
	# G-1: the sight counter 0x70d488 + 2p (PRA0-2, PDS0-1; Emulated completion table) read by the fog (Visibility.sight_bonus).
	if visibility != null and production != null: visibility.sight_bonus[owner] = research.sight_counter(production.research.get(owner, [])) + (int(spells.sight_spells.get(owner, 0)) if spells != null else 0)   # B1-6c: + True Sight

## A fighter's block replaced from outside (hero level-up, items): the new base, research terms applied again.
func set_base_stats(f, stats: Dictionary):
	f.base = stats.duplicate()
	_apply_research(f)

func bind_hero(owner: int, unit_id: int, hero_match):
	heroes[owner] = {"unit": unit_id, "match": hero_match}

func alive(f) -> bool:
	return f != null and f.state != "dying" and f.state != "corpse" and f.hp > 0

# ----------------------------------------------------------------------------------------- experience and rank (R-1)
## 0x527100 (Emulated: UnitRanks, tests/rank_fixtures.json). A hero's experience stays with _award / HeroMatch; a titan
## (+0x1cd) gains nothing. Every promotion raises the block for good (f.base and the live f.stats by the same words), and
## a gain with a promotion heals: the missing hit points, at most 100 (message 0x1fa). Returns the promotions.
func gain_experience(f, amount: int) -> int:
	if f == null: return 0
	if f.hero:
		f.xp = int(f.xp) + amount
		return 0
	if UnitRanks.is_titan(String(f.type_id)): return 0
	var block := _rank_block(f)
	var promotions: int = UnitRanks.gain(block, mini(amount, UnitRanks.MAX_XP))
	f.xp = int(block.xp)
	if promotions > 0:
		_store_rank_block(f, block)
		if alive(f): f.hp = UnitRanks.healed_points(int(f.hp), int(f.max_hp))
		if units.size() > f.id and units[f.id] != null:
			units[f.id].hp = maxi(0, int(f.hp))
			units[f.id].max_hp = f.max_hp
		rank_gained.emit(int(f.id), int(f.rank))
	return promotions

## A 0xfd unit (match start, army setup, the retinue: sender 0x4a5780, handler 0x4a4560; Emulated "fd_builder"): `rank`
## promotions without a gain, the experience 0x5fbc48[rank] outside a scenario (one rank short; a scenario keeps `xp`),
## then 0x527100 with the sender's training gain (UnitRanks.creation_gain), which may promote further.
func set_rank(f, rank: int, xp: int, gain: int = 0, scenario: bool = false):
	if f == null or f.hero or UnitRanks.is_titan(String(f.type_id)): return
	var block := _rank_block(f)
	for i in clampi(rank, 0, UnitRanks.MAX_RANK): UnitRanks.promote(block)
	_store_rank_block(f, block)
	f.xp = clampi(UnitRanks.creation_xp(rank, xp, scenario), 0, UnitRanks.MAX_XP)
	if gain > 0: gain_experience(f, gain)
	if units.size() > f.id and units[f.id] != null:
		units[f.id].hp = f.hp
		units[f.id].max_hp = f.max_hp

## 0x4a5780's +0x10 for a unit of `owner` by its research now (UnitRanks.creation_gain; 0x7495d8 is scenario data).
func creation_gain(owner: int, type_id: String) -> int:
	if production == null: return 0
	return UnitRanks.creation_gain(type_id, production.research_level(owner, RacePowers.TRAINING_RESEARCH) != 0,
		production.research_level(owner, "PLOX"), production.research_level(owner, "PORO") != 0)

func _rank_block(f) -> Dictionary:
	var b: Dictionary = f.base
	return {"rank": int(f.get("rank", 0)), "xp": int(f.xp), "combat": int(b.combat), "speed": int(b.speed), "mres": int(b.mres),
		"max_hp": int(f.max_hp), "hp": int(f.hp), "dmg": int(b.dmg), "armour": int(b.armour), "word_ae": int(b.get("word_ae", 0)),
		"word_b0": int(b.get("word_b0", 0))}

## The block's new words on the fighter. The live block moves by the same differences, so a direct change to it stays
## (Morph, spells.gd) and the research terms keep their sum; the walking speed follows as in _apply_research.
func _store_rank_block(f, block: Dictionary):
	for key in ["combat", "speed", "mres", "dmg", "armour"]:
		var change: int = int(block[key]) - int(f.base[key])
		f.base[key] = int(block[key])
		f.stats[key] = int(f.stats[key]) + change
	f.base["word_ae"] = int(block.word_ae)
	f.base["word_b0"] = int(block.word_b0)
	f.base["max_hp"] = int(block.max_hp)
	f.stats["max_hp"] = int(block.max_hp)
	f.max_hp = int(block.max_hp)
	f.hp = int(block.hp)
	f.rank = int(block.rank)
	if units.size() > f.id and units[f.id] != null:
		units[f.id].base_speed = int(f.stats.speed) + _brew(f, BREW_SPEED) + int(f.get("status_speed", 0))

## 0x557d90(player, type, 1, 1, 0) with the living hero's effect 3 (Telepathy); `general` / `typed` / `research_term` are its
## other arguments (a summon's record takes (0, 1, 1)).
func starting_xp(owner: int, type_id: String, general: bool = true, typed: bool = true, research_term: bool = false) -> int:
	var status: int = int(type_status.call(type_id)) if type_status.is_valid() else 0
	var aura := 0
	if spells != null and heroes.has(owner):
		var hero = fighters.get(heroes[owner].unit)
		if hero != null: aura = spells.status_value(hero, spells.STATUS_TRAINING)
	var xp: int = Advancement.starting_xp(hero_block(owner), type_id, status, general, typed, aura)
	if research_term and production != null: xp += production.research_level(owner, "PGAX") * 20
	return xp

## 0x4a49e0's tail for message 0xfa: +0x10 when positive, then the starting experience unless the message's +0x3b is set
## (Resurrection, summons) or the unit is an animal (0x528280(0)).
func creation_experience(f, xp: int, start: bool = true):
	if f == null: return
	if xp > 0: gain_experience(f, xp)
	if start and not UnitAI.is_animal(String(f.type_id)):
		var s := starting_xp(int(f.owner), String(f.type_id))
		if s > 0: gain_experience(f, s)

func unit_cell(id: int) -> Vector2i:
	return units[id].cell

# ----------------------------------------------------------------------------------------- orders
## 0x51da60 (attack order, type 6). kind: "unit" or "building".
## ai_order: issued by a script (0x51a470 passes 1 as the order's +0x1c, so later rules may replace it); player orders
## block every rule without +0x75 until they end (0x507560).
## G-3: `speed` is the order's +0x1e: 0x531480 gives every player attack the selection's slowest 0x51c460(1) (from 50; -1
## when none is below 50), and 0x51c660 walks the approach at it (state 4, head order type 6); -1 = the unit's own speed.
## AI-9: `inserted` is the order's +0x1d (-1: the same as ai_order; the search attack 0x51a470 always sets it, the
## attacker / adjacent attacks 0x508e60's value); the walk steps move the guard point only for orders without it.
func order_attack(unit_id: int, target_kind: String, target_id: int, ai_order: bool = false, speed: int = -1, inserted: int = -1) -> bool:
	var f = fighters.get(unit_id)
	if not alive(f): return false
	if not _valid_target(f, target_kind, target_id): return false
	if int(f.stats.dmg) <= 0: return false     # 0x51da60 refuses units that cannot hurt (damage 0)
	# G-3 (Read, 0x51da60 with a head order): a script attack (+0x1d) is refused when the head is a player order (+0x1c 0)
	# and inserted before an attack-move (+0x1c 1). In the original the next queued order is the head as soon as the one
	# before it ends; the rebuild starts it on the next idle update, so an idle unit with queued orders answers as if it
	# were already current: a queued attack or plain move refuses the script attack, a queued attack-move lets it go first.
	if ai_order and f.order == null and (f.cur == null or bool(f.cur.get("finished", false))) and not f.get("queue", []).is_empty() \
			and units.size() > unit_id and units[unit_id] != null and units[unit_id].orders.is_empty():
		var head: Dictionary = f.queue[0]
		if head.kind == "attack" or not bool(head.get("move", {}).get("attack_move", false)): return false
	# 0x51da60 with +0x1d set (a script order) over an attack-move (+0x1c = 1) inserts the attack before it (0x406530), so
	# the walk resumes when the fight ends; a player attack replaces everything.
	if ai_order and is_attack_move(f.cur): f.resume = f.cur
	elif not ai_order:
		f.resume = null
		f.erase("queue")                      # G-2: a replacing player attack (command 3, mode 0) empties the chain
	f.order = {"kind": "attack", "target_kind": target_kind, "target_id": target_id, "planned_cell": Vector2i(-9999, -9999), "ai": ai_order, "speed": speed}
	f.cur = {"kind": "attack", "ai": ai_order, "finished": false, "goal": Vector2i(-1, -1),
		"inserted": ai_order if inserted < 0 else inserted != 0}
	if f.state != "swing": f.state = "approach"
	return true

## A player move order (the selection's right-click): it becomes the unit's current order for the scripts.
## `move` is the unit order; with "attack_move" it is the original's move with +0x1c = 1 (0x530870 flag 0: Attack mode on
## the ground, commands 0x1a / 0x37..0x3b): the attitude rules may act on the way (0x507560 only blocks +0x1c = 0 moves).
func note_move(unit_id: int, cell: Vector2i, move: Dictionary = {}):
	var f = fighters.get(unit_id)
	if f == null: return
	f.order = null
	f.resume = null
	if f.state == "approach": f.state = "idle"
	var attack_move := bool(move.get("attack_move", false))
	f.cur = {"kind": "move", "ai": attack_move, "finished": false, "goal": cell}
	if attack_move: f.cur["attack_move"] = move.duplicate()

static func is_attack_move(cur) -> bool:
	return cur != null and cur.has("attack_move") and not cur.finished

## The order inserted before an attack-move is done (the fight ended, or a script move arrived): the attack-move becomes
## current again and the unit re-plans its walk from where it stands.
func _resume_attack_move(f, unit):
	if f.get("resume") == null: return
	if f.cur != null and f.cur.kind == "move" and not f.cur.finished and (not unit.orders.is_empty() or unit.in_step): return
	var r: Dictionary = f.resume
	f.resume = null
	var move: Dictionary = r.attack_move.duplicate()
	for key in ["cells", "marks", "march"]: move.erase(key)
	unit.give_order(move, "replace")
	r.finished = false
	f.cur = r

func order_stop(unit_id: int):
	var f = fighters.get(unit_id)
	if f == null: return
	f.order = null
	f.cur = null
	f.resume = null
	f.erase("queue")                          # G-2: a replacing order or Stop empties the chain (0x406600)
	if f.state == "approach": f.state = "idle"

# ------------------------------------------------------------------------- G-2: queued player orders (Read)
## The original keeps one order chain per unit (+0xc8 head / +0xcc tail; 0x4064a0 appends, 0x406530 inserts, 0x406590
## unlinks). The rebuild splits it: the current attack is f.order, the current walk is unit.orders. `f.queue` holds the
## player orders behind them: {"kind": "attack", "target_kind", "target_id"} or {"kind": "move", "move", "cell"}.
## `busy_check` (main.gd) reports a unit whose current order lives outside combat (order 7, the conversion).
var busy_check: Callable

func _queue(f) -> Array:
	if not f.has("queue"): f["queue"] = []
	return f.queue

## True while the unit's chain is not empty: an attack, a walk, an attack-move to resume, a conversion or queued orders.
func chain_busy(unit_id: int) -> bool:
	var f = fighters.get(unit_id)
	if f == null: return false
	var unit = units[unit_id]
	if f.order != null or f.get("resume") != null or not unit.orders.is_empty() or not f.get("queue", []).is_empty(): return true
	return busy_check.is_valid() and bool(busy_check.call(unit_id))

## Command 0x16 (Shift + right-click on an enemy, 0x41f0b0 case 0x15 -> 0x531480 mode 2 -> 0x51da60 param 6 = 2): the attack
## is appended to the chain (0x4064a0); on an empty chain it starts at once. Returns false for a target 0x51da60 refuses.
func order_attack_append(unit_id: int, target_kind: String, target_id: int, speed: int = -1) -> bool:
	var f = fighters.get(unit_id)
	if not alive(f) or not _valid_target(f, target_kind, target_id) or int(f.stats.dmg) <= 0: return false
	if not chain_busy(unit_id): return order_attack(unit_id, target_kind, target_id, false, speed)
	_queue(f).append({"kind": "attack", "target_kind": target_kind, "target_id": target_id, "speed": speed})
	return true

## Command 0x17 (Alt + right-click, case 0x16 -> mode 1 -> 0x406530): the attack is inserted before the current order, which
## resumes when the attack ends (its walk is planned again from where the unit stands). A current attack-move resumes
## through f.resume as a script insertion does; a current attack or walk goes to the front of the queue.
func order_attack_insert(unit_id: int, target_kind: String, target_id: int, speed: int = -1) -> bool:
	var f = fighters.get(unit_id)
	if not alive(f) or not _valid_target(f, target_kind, target_id) or int(f.stats.dmg) <= 0: return false
	_defer_current(f, units[unit_id])
	var keep_resume = f.get("resume")
	var keep_queue: Array = _queue(f).duplicate()
	order_attack(unit_id, target_kind, target_id, false, speed)
	f.resume = keep_resume
	f["queue"] = keep_queue
	return true

## The current order steps back to the front of the queue (an insert in front of it, 0x406530).
func _defer_current(f, unit):
	var q := _queue(f)
	if f.order != null:
		q.push_front({"kind": "attack", "target_kind": f.order.target_kind, "target_id": f.order.target_id, "speed": int(f.order.get("speed", -1))})
		f.order = null
		if f.state == "approach": f.state = "idle"
		unit.stop()
		return
	if is_attack_move(f.cur):
		f.resume = f.cur                       # _resume_attack_move gives it back; later walks stay queued
		var rest: Array = unit.orders.slice(1)
		for i in range(rest.size() - 1, -1, -1): q.push_front(_queued_move(rest[i]))
		unit.stop()
		return
	var walks: Array = unit.orders.duplicate()
	for i in range(walks.size() - 1, -1, -1):
		if bool(walks[i].get("attack", false)): continue
		q.push_front(_queued_move(walks[i]))
	unit.stop()

static func _queued_move(o: Dictionary) -> Dictionary:
	var move: Dictionary = o.duplicate()
	for key in ["cells", "marks", "march"]: move.erase(key)
	return {"kind": "move", "move": move}

## A move behind queued orders (Shift + right-click while the chain holds an attack or queued orders): it waits its turn.
func queue_move(unit_id: int, move: Dictionary):
	var f = fighters.get(unit_id)
	if f == null: return
	_queue(f).append(_queued_move(move))

## An inserted move (Alt) in front of a current attack: the attack waits at the front of the queue.
func defer_attack(unit_id: int):
	var f = fighters.get(unit_id)
	if f == null or f.order == null: return
	_defer_current(f, units[unit_id])

## Shift+Esc (0x427fb0 -> 0x4296c0): every selected unit whose chain holds two or more orders loses the last (+0xcc,
## 0x406590). Returns true when one was removed.
func remove_last_order(unit_id: int) -> bool:
	var f = fighters.get(unit_id)
	if f == null: return false
	var unit = units[unit_id]
	var q: Array = f.get("queue", [])
	if not q.is_empty():
		q.pop_back()
		return true
	if f.order != null:
		if f.get("resume") != null:
			f.resume = null
			return true
		return false
	var walks: int = unit.orders.filter(func(o): return not bool(o.get("unwedge", false))).size()
	if walks >= 2:
		unit.orders.pop_back()
		return true
	return false

## The next queued order becomes current once the chain ahead of it is done (called by _update_active on an idle unit).
func _next_queued(f, unit) -> bool:
	var q: Array = f.get("queue", [])
	if q.is_empty() or not unit.orders.is_empty() or unit.in_step or f.get("resume") != null: return false
	if busy_check.is_valid() and bool(busy_check.call(int(f.id))): return false
	while not q.is_empty():
		var next: Dictionary = q.pop_front()
		if next.kind == "attack":
			if not _valid_target(f, next.target_kind, next.target_id): continue   # 0x51e670 drops a dead target
			var rest: Array = q.duplicate()
			order_attack(int(f.id), next.target_kind, next.target_id, false, int(next.get("speed", -1)))
			f["queue"] = rest
			return true
		var move: Dictionary = next.move
		unit.give_order(move, "append")
		note_move(int(f.id), Vector2i(navigator.collision.world_cell(move.target)) if navigator != null else Vector2i(-1, -1), move)
		return true
	return false

func _valid_target(f, target_kind: String, target_id: int) -> bool:
	if target_kind == "unit":
		var t = fighters.get(target_id)
		# B2-1 (R5): a hunter's animal is a target whoever owns it (0x5334f0's animal branch has no owner filter).
		if alive(t) and t.id != f.id and hunt_priority(f, t) > 0: return Rules.can_hit(f.stats, t.stats)
		return alive(t) and t.owner != f.owner and Rules.hostile(teams, f.owner, t.owner) and t.id != f.id and Rules.can_hit(f.stats, t.stats)
	if not Rules.can_hit(f.stats, {"building": true}): return false
	var b = production.building(target_id) if production != null else null
	return b != null and b.owner != f.owner and Rules.hostile(teams, f.owner, b.owner) and b.hit_points > 0

func target_alive(order: Dictionary) -> bool:
	if order.target_kind == "unit": return alive(fighters.get(order.target_id))
	var b = production.building(order.target_id) if production != null else null
	return b != null and b.hit_points > 0

# ----------------------------------------------------------------------------------------- stats
## 0x532a20 / 0x5332e0 (Read, playtest 2026-11-11 soak): each second the living hero units (+0xb4) of every side are the
## sources, each with the radius 0x5267b0 capped at 19 (Charisma + 5 + effect 10 + item powers 10 + 8 with PDKL, the
## conversion radius); a non-hero unit gets +0x190 when a source of its own side or an allied side (0x748915) lies under
## 20 cells on both axes and the distance table at (dx, dy) is below the radius. The table 0x44650 is built by 0x5329a0
## from float code read as the rounded-down straight-line distance (Provisional), as is the ten-pass hold (+0x192) the
## rebuild leaves out (the flag follows the test each second).
func near_hero(f) -> bool:
	if f.hero: return false
	var a := unit_cell(f.id)
	for side in heroes:
		if int(side) != int(f.owner) and Rules.hostile(teams, int(f.owner), int(side)): continue
		var hero = fighters.get(heroes[side].unit)
		if not alive(hero): continue
		var b := unit_cell(hero.id)
		var dx := absi(a.x - b.x)
		var dy := absi(a.y - b.y)
		if maxi(dx, dy) >= HERO_AURA_CELLS: continue
		if int(sqrt(float(dx * dx + dy * dy))) < hero_aura_radius(int(side), hero): return true
	return false

## 0x5267b0 for a hero unit, capped at 19 by 0x5332e0.
func hero_aura_radius(side: int, hero) -> int:
	var research: Array = production.research.get(side, []) if production != null else []
	var extra: int = spells.status_value(hero, 10) if spells != null else 0
	return mini(19, HeroEffects.conversion_radius(hero_block(side), research) + extra)

func combat_block(f) -> Dictionary:
	var block: Dictionary = f.stats.duplicate()
	block.combat = int(block.combat) + _time_of_day_term(f) + _brew(f, BREW_COMBAT)   # B1-3 (0x51bd10)
	if spells != null: block.armour = int(block.armour) + spells.status_value(f, spells.STATUS_ARMOUR)   # B1-4: 0x5260a0 effect 0x18
	if spells != null: spells.apply_status_terms(f, block)   # B1-6b: effects 1 (combat), 6 (magic armour), 0x17 (attack)
	var cut := int(f.get("armour_cut", 0))                   # G-4: Armor Reduced, +0x20c (0x5260a0's last term, Emulated)
	if cut != 0: block.armour = int(block.armour) - cut
	block["near_hero"] = near_hero(f)
	block["building"] = false
	block["owner"] = f.owner
	block["type_id"] = String(f.type_id)
	if production != null:          # 0x42ace0 reads the PPAL / PGRA flags of the attacker's owner (milestone 13)
		var list: Array = production.research.get(f.owner, [])
		block["ppal"] = research.flag(list, ResearchEffects.PPAL_FLAG)
		block["pgra"] = research.flag(list, ResearchEffects.PGRA_FLAG)
		# G-1 (RACE_DATA_RESEARCH.md): the other races' swing flags, and a non-hero assassin's chance (0x526e70, with the rank).
		block["ptor"] = research.flag(list, ResearchEffects.PTOR_FLAG)
		block["pfal"] = research.flag(list, ResearchEffects.PFAL_FLAG)
		block["pcow"] = research.flag(list, ResearchEffects.PCOW_FLAG)
		block["pdk_level"] = production.research_level(f.owner, "PDKX")
		if not f.hero: block["assassin"] = ResearchEffects.assassin(String(f.type_id), list, int(f.get("rank", 0)))
	# Milestone 11 hero terms (HeroEffects; Emulated against 0x42ace0 / 0x525c80 / 0x526310 / 0x51bd10 / 0x526b70).
	var owner_block := hero_block(f.owner)
	var own := owner_block if f.hero and heroes.has(f.owner) and heroes[f.owner].unit == f.id else {}
	if not own.is_empty():
		var attack := HeroEffects.attack(int(block.dmg), int(block.dtype), own)
		block.dmg = attack.dmg
		block.dtype = attack.dtype
		block.combat = HeroEffects.effective_combat(int(block.combat), own) + int(block.get("enc", 0))
		block["crit_bonus"] = HeroEffects.skill_effect(own, 0x21) + HeroEffects.item_stat(own, 0x1b)
		block["ignore_armour"] = HeroEffects.skill_effect(own, 0x2a)
		block["demolition"] = HeroEffects.skill_effect(own, 0x2e)
		block["assassin"] = HeroEffects.skill_effect(own, 0x33) + HeroEffects.item_stat(own, 0x22)
		block["slayer_block"] = own
		block["hero"] = true
		block["hero_level"] = int(own.level)
	if not owner_block.is_empty(): block["armour_table"] = HeroEffects.armour_table(block, own, owner_block)
	elif cut != 0: block.armour = maxi(0, int(block.armour))   # G-4: the clamp at 0 comes after the cut (armour_value clamps the other way)
	# B3-1 (R11, Read: the lost getter 0x525ff4): AAFB with PDBT has fire armour + 50.
	if String(f.type_id) == RacePowers.PDBT_TYPE and production != null and production.research_level(f.owner, RacePowers.PDBT_RESEARCH) != 0:
		var table: Array = Rules.armour_table(block).duplicate()
		table[3] = int(table[3]) + RacePowers.PDBT_FIRE
		block["armour_table"] = table
	if spells != null: spells.add_resist_statuses(f, block)   # B1-6a: 0x525c80 effects 0x51 / 0x50 / 0x58 / 0x59
	return block

## B2-1 (R7, Read): 0x5269a0 for `owner`'s hero (the block's stats and items, effect 7, research, the counter 0x70d622, Leadership
## and the race's lord skill); 0x5268c0 is half of it.
func hero_command_value(owner: int, block: Dictionary, f) -> int:
	var command_block := block.duplicate()
	command_block.race = production.race_of(owner)           # 0x5269a0: the lord skill of the player's race (0x708f96)
	var value := HeroEffects.command_value(command_block, int(lord_counter.get(owner, 0)), production.research.get(owner, []))
	return value + (spells.status_value(f, spells.STATUS_MORALE) if spells != null and f != null else 0)

## B2-1 (R7, Read: 0x40dc80, decompile 12594): X of the attack time (0x537060): a living hero's 0x5269a0; else the table
## 0x6081e0[PMOX level] (0, 3, 6, 9) + the counter + 2 with POLI + 5 with PWRM. Owners above 6 have none.
func morale_value(owner: int) -> int:
	if owner > UnitAI.NEUTRAL or production == null: return 0
	var block := hero_block(owner)
	if not block.is_empty():
		var hero = fighters.get(heroes[owner].unit)
		if hero != null and int(hero.hp) > 0: return hero_command_value(owner, block, hero)
	var list: Array = production.research.get(owner, [])
	var value: int = [0, 3, 6, 9][mini(production.research_level(owner, "PMOX"), 3)] + int(lord_counter.get(owner, 0))
	if list.has("POLI"): value += 2
	if list.has("PWRM"): value += 5
	return value

## The hero block of `owner` (0x7091c0 + p * 0x194) while its hero object exists (0x70adb4), else {}.
func hero_block(owner: int) -> Dictionary:
	if not heroes.has(owner) or heroes[owner].match == null or heroes[owner].match.profile == null: return {}
	var hero = fighters.get(heroes[owner].unit)
	if hero == null or hero.removed: return {}
	return heroes[owner].match.block(int(hero.hp))

func building_block(b) -> Dictionary:
	var block := Rules.building_stats(b.definition.raw_hex)
	if spells != null and b.has_meta("morph"): block.combat = spells.building_stat(b, 0)   # B1-6e: Morph Tower (+0x68)
	block.combat += int(building_bonus.get(b.owner, 0))   # 0x52ae70: computer players' difficulty term
	block.combat += Rules.garrison_combat(garrison_terms(int(b.entity_id)))   # G-2: 0x52ae70(1)'s occupant terms
	return block

## G-2: the occupants of a tower as Rules.garrison_combat / garrison_rate read them (`garrison_of`: main.gd's
## unit_commands.occupants; empty without it).
var garrison_of: Callable

func garrison_terms(building_id: int) -> Array:
	var out: Array = []
	if not garrison_of.is_valid(): return out
	for id in garrison_of.call(building_id):
		var f = fighters.get(int(id))
		if f == null: continue
		out.append({"hero": bool(f.hero), "status": int(f.base.get("flags", 0)), "computer": ai_players.has(int(f.owner)), "id": int(id)})
	return out

func target_block(order_or_ref: Dictionary) -> Dictionary:
	if order_or_ref.target_kind == "unit": return combat_block(fighters[order_or_ref.target_id])
	return building_block(production.building(order_or_ref.target_id))

## 0x5326e0: smallest Chebyshev distance from the unit's cell to a cell the target occupies.
func distance_to(f, order: Dictionary) -> int:
	var here := unit_cell(f.id)
	if order.target_kind == "unit":
		var there := unit_cell(order.target_id)
		return maxi(absi(here.x - there.x), absi(here.y - there.y))
	var best := 1000
	for cell in _cells_of(int(order.target_id)):
		best = mini(best, maxi(absi(here.x - cell.x), absi(here.y - cell.y)))
	return best

## The cells of one building in building_cells' order (navigation.gd cells_of_building; a scan for stand-in navigators).
func _cells_of(id: int) -> Array:
	if navigator.has_method("cells_of_building"): return navigator.cells_of_building(id)
	var out: Array = []
	for cell in navigator.building_cells:
		if navigator.building_cells[cell] == id: out.append(cell)
	return out

## The approach goal: the original's nearest cell, or (modern rules) the attacker's own cell beside the target.
func approach_cell(f, order: Dictionary) -> Vector2i:
	if not improved or units[f.id].flying: return nearest_target_cell(f, order)
	# Re-chosen at most every SPREAD_MS (each choice scans the other attackers), or when the target moved.
	var target_at := nearest_target_cell(f, order)
	var memo: Dictionary = order.get("spread", {})
	if memo.get("target_at") == target_at and now_ms < int(memo.get("until", 0)): return memo.cell
	var cell := spread_target_cell(f, order)
	order["spread"] = {"cell": cell, "target_at": target_at, "until": now_ms + SPREAD_MS}
	return cell

const SPREAD_MS := 250

func nearest_target_cell(f, order: Dictionary) -> Vector2i:
	var here := unit_cell(f.id)
	if order.target_kind == "unit": return unit_cell(order.target_id)
	var best := Vector2i(-1, -1)
	var best_distance := 1000
	for cell in _cells_of(int(order.target_id)):
		var d := maxi(absi(here.x - cell.x), absi(here.y - cell.y))
		if d < best_distance:
			best_distance = d
			best = cell
	return best

# ----------------------------------------------------------------------------------------- simulation
## Advance to now (ms). The original runs its update every 25 ms; fighters are visited in unit id order (the
## original list order is Open).
func update(time_ms: int):
	while next_update_ms <= time_ms:
		now_ms = next_update_ms
		_step()
		next_update_ms += UPDATE_MS
	now_ms = time_ms

func _step():
	if pre_update.is_valid(): pre_update.call(now_ms)   # 0x429ec0: the AI manager runs before the attitude scripts
	ai.on_update(now_ms)
	_update_towers()
	var ids: Array = fighters.keys()
	ids.sort()
	for id in ids:
		var f = fighters[id]
		if f.removed: continue
		match f.state:
			"dying": _update_dying(f)
			"corpse": _update_dying(f)
			"swing": _update_swing(f)
			_: _update_active(f)
		if f.hero and f.state != "dying" and f.state != "corpse":
			_regenerate_hero(f)
			_regenerate_mana(f)
		elif not f.hero and int(f.get("regen_ms", 0)) != 0 and now_ms > int(f.regen_ms) and f.state != "dying" and f.state != "corpse":
			_regenerate_unit(f)                # R-1: 0x51c9a0..0x51ca73, the timer +0x164 once a hit armed it
		if bool(f.get("poisoned", false)): _poison(f)   # P-3: _poison's own first test, without the call
	if spells != null: spells.step()      # B1-4: unit mana, hero cooldowns, cast sequences, status expiry
	_update_missiles()
	for id in ids: _animate(fighters[id])

## Drives the unit sprite: the f slot (attack, 17 entries of attack_entry_ms, last shows frame 0) and the d slot
## (100 ms per frame, the last frame is held until the corpse is removed).
func _animate(f):
	var unit = units[f.id]
	if f.removed: return
	if f.state == "swing" and f.swing != null:
		var entry: int = maxi(1, f.swing.entry_ms)
		var frames: int = attack_frames(f.type_id)
		var i := mini(frames, Rules.attack_entry_at(now_ms - f.swing.start_ms, entry, f.swing.get("latency", NO_LATENCY)))
		# "sheet"/"frame" keep the Swordsman-sheet values; "slot"/"index"/"frames" let unit_agent.gd draw the unit's own
		# sheet (presentation only, ART_RESEARCH.md).
		unit.anim = {"sheet": "AHKXf.RLE", "row": unit.direction, "frame": (i if i < frames else 0) * Rules.MELEE_FRAMES / frames,
			"slot": 2, "index": i, "frames": frames}
	elif f.state == "dying" or f.state == "corpse":
		var frames: int = death_frames(f.type_id)
		var index := mini(frames - 1, (now_ms - f.death_ms) / DEATH_ENTRY_MS)
		unit.anim = {"sheet": "AHKXd.RLE", "row": unit.direction, "frame": index * DEATH_FRAMES / frames, "slot": 3, "index": index, "frames": frames}
	elif not unit.anim.is_empty() and f.get("cast") == null:   # B1-4: a cast sequence (spells.gd) draws slot 6 itself
		unit.anim = {}

func _update_active(f):
	var unit = units[f.id]
	if unit.inside_building: return
	if f.order == null:
		f.state = "idle"
		if f.resume != null: _resume_attack_move(f, unit)
		elif f.has("queue"): _next_queued(f, unit)   # G-2: the next order of the chain
		return
	var order: Dictionary = f.order
	if not target_alive(order) or (spells != null and spells.hidden_target(order)):   # B1-6d: 0x51e670 drops an invisible target
		f.order = null
		f.state = "idle"
		return
	var distance := distance_to(f, order)
	if Rules.in_attack_range(distance, order_range(f, order)):
		if unit.in_step:                         # finish the cell step first (the unit occupies the next cell already)
			# Playtest 2026-11-11: the attack replaces the walk (0x51da60), so nothing after this step is walked. A unit that
			# was walking kept its old route here and shot only once the route ended.
			if not unit.orders.is_empty(): unit.stop()
			return
		unit.stop()
		_start_swing(f, order, distance)
		return
	f.state = "approach"
	var goal := approach_cell(f, order)
	if goal != order.planned_cell or (unit.orders.is_empty() and not unit.in_step):
		order["planned_cell"] = goal
		var target: Vector2 = navigator.center(goal)
		var walk_speed: int = int(order.get("speed", -1))         # G-3: 0x51c660, the order's +0x1e when set
		unit.give_order({"kind": "move", "target": target, "requested": target, "group": 0, "speed": walk_speed if walk_speed >= 0 else unit.base_speed, "individual": true, "attack": true,
			"ai": bool(order.get("ai", false))}, "replace")

## B2-1 (R5, Emulated: fixtures "reach"): 0x51ea20 / 0x51f9b0 count a hunter's range as 0 against its animal, so a ranged
## hunter walks adjacent; the swing itself keeps the unit's own attack (no hit chance changes).
func order_range(f, order: Dictionary) -> int:
	if order.target_kind == "unit" and RacePowers.melee_prey(String(f.type_id), String(fighters[order.target_id].type_id)): return 0
	return int(f.stats.range)

## 0x51ea20 case 6 -> 0x51f9b0 state 6 -> 0x536e30: face the target, roll, build the message, play the f animation.
func _start_swing(f, order: Dictionary, distance: int):
	var unit = units[f.id]
	var here := unit_cell(f.id)
	var there := nearest_target_cell(f, order)
	var step := Vector2i(signi(there.x - here.x), signi(there.y - here.y))
	if step != Vector2i.ZERO: unit.direction = unit.direction_of(step)
	var started: Dictionary = Rules.attack_start(combat_block(f), target_block(order), rng, distance, game_mode)   # 0x536e30: message roll, then 0x42ace0
	var swing := {"start_ms": now_ms, "target_kind": order.target_kind, "target_id": order.target_id, "message_roll": int(started.message_roll),
		"distance": distance, "ranged": bool(started.ranged), "result": started, "hit_done": false}
	var frames := attack_frames(f.type_id)
	var own := hero_block(f.owner) if f.hero else {}
	var rate: int = HeroEffects.attack_rate(own) if not own.is_empty() else (Rules.BASE_ATTACK_RATE if f.hero else ResearchEffects.attack_rate(String(f.type_id)))   # 0x51c6a0
	if spells != null: rate = spells.attack_rate(f, rate)   # B1-6b: 0x51c6a0 effects 0x2e / 0x2f / 0x30 / 0x37; B1-6d: fear halves it
	if spells != null: spells.reveal(f)                     # B1-6d: the attack states (0x537060 / 0x5373a0 / 0x5374a0) end invisibility
	var entry := Rules.attack_entry_ms(f.hero, morale_value(f.owner), _hero_attack_stat(f), rate, frames)   # B2-1: X = 0x40dc80
	var latency := attack_latency(f.type_id)                         # Army.cfg's delayed first entries (0x528cd0 +0x214)
	swing["entry_ms"] = entry
	swing["latency"] = latency
	swing["hit_ms"] = now_ms + Rules.attack_entry_time(hit_frame(f.type_id), entry, latency)   # 0x5394a0: hit at the ANI slot 2 +0x18 entry
	swing["end_ms"] = now_ms + Rules.attack_entry_time(frames, entry, latency)
	f.swing = swing
	f.state = "swing"
	swing_started.emit(f.id, swing)

## ANI slot 2 frame count / +0x18 hit entry of every unit (simulation/attack_timing.json, Emulated by
## tools/emulate_attack_time.py); slot 3's frame count from the unit's own record (encounters.json); the Swordsman values
## (16 / 6 / 13) when a unit has no record (the animals and AAEY have no slot 2; 0x537060 builds them no attack animation).
func attack_frames(type_id: String) -> int:
	var row = Rules.attack_timing().get(type_id)
	if row != null: return int(row[0])
	return int(ani.get(type_id, {}).get("attack_frames", Rules.MELEE_FRAMES))

func hit_frame(type_id: String) -> int:
	var row = Rules.attack_timing().get(type_id)
	if row != null: return int(row[1])
	return int(ani.get(type_id, {}).get("hit_frame", Rules.MELEE_HIT_FRAME))

## Army.cfg LATENCY [frame, ms] of the type (0x528cd0 +0x214), NO_LATENCY for almost every unit.
func attack_latency(type_id: String) -> Array:
	var row = Rules.attack_timing().get(type_id)
	return NO_LATENCY if row == null else [int(row[2]), int(row[3])]

func death_frames(type_id: String) -> int:
	return int(ani.get(type_id, {}).get("death_frames", DEATH_FRAMES))

func corpse_ms(type_id: String) -> int:
	return (death_frames(type_id) + 1) * 50 + 30000                # 0x5374a0: last d entry, then 30 s

## 0x51b820 for a living hero (milestone 11, Read; the rate 0x51b460 is HeroEffects.regeneration_rate): at full hit points
## the timer resets; the first tick only arms it; later ticks heal ceil(1000 / rate) points and re-arm after that many
## rate periods. Ordinary units: _regenerate_unit.
func _regenerate_hero(f):
	if day_night != null and day_night.blocks_regeneration(int(f.stats.get("flags", 0))):   # B1-3: the Undead by day (0x51b820)
		f["regen_ms"] = now_ms + day_night.UNDEAD_PAUSE_MS
		return
	if spells != null and spells.disease_blocks_regeneration(f): return   # B1-6e: 0x51b820's disease branch
	if f.hp >= f.max_hp:
		f["regen_ms"] = 0
		return
	var own := hero_block(f.owner)
	if own.is_empty(): return
	var rate := HeroEffects.regeneration_rate(own)
	if rate < 1: return
	var due: int = int(f.get("regen_ms", 0))
	var step := rate
	if due != 0:
		if now_ms < due: return
		var heal := 1
		while step < 1000:
			step += rate
			heal += 1
		f.hp += heal
		units[f.id].hp = f.hp
	f["regen_ms"] = step + now_ms

## R-1 (Emulated: tests/rank_fixtures.json "regeneration", "ticks"): 0x51b820 for a non-hero. The damage reaction 0x522860
## runs it once (the arming tick); after that the update runs it whenever +0x164 has passed, until the unit is whole. By
## day the Undead wait 5 s; a poisoned or diseased unit waits a second at a time (the branches of the same routine, whose
## own damage stays with _poison and spells.gd); a garrisoned unit heals at twice the speed.
func _regenerate_unit(f):
	if day_night != null and day_night.blocks_regeneration(int(f.stats.get("flags", 0))):
		f["regen_ms"] = now_ms + day_night.UNDEAD_PAUSE_MS
		return
	if bool(f.get("poisoned", false)) or (spells != null and spells.disease_blocks_regeneration(f)):
		f["regen_ms"] = now_ms + UnitRanks.POISON_MS
		return
	if not f.has("regen_ms"): f["regen_ms"] = 0
	if UnitRanks.regen_tick(f, now_ms, regeneration_rate(f), bool(f.get("garrisoned", false))) > 0:
		units[f.id].hp = f.hp

## 0x51b460 for a non-hero: rank, PRGX level, the owner's living hero's skill 3 and effect 0x2c, AOMX, Undead.
func regeneration_rate(f) -> int:
	var level: int = production.research_level(f.owner, "PRGX") if production != null else 0
	var percent: int = int(UnitRanks.REGENERATION[clampi(level, 0, UnitRanks.REGENERATION.size() - 1)])
	percent += HeroEffects.skill_effect(hero_block(f.owner), 3)
	if spells != null: percent += spells.status_value(f, 0x2c)
	return UnitRanks.regeneration_rate(int(f.get("rank", 0)), String(f.type_id), int(f.stats.get("flags", 0)), percent)

## Parity pass 4: the hero's mana (HeroEffects.start_mana / mana_rate). The first update after the spawn sets the
## record values (0x4a4560); 0x51b6b0 then arms its timer (+0x18c) on the first tick and adds ceil(1000 / rate) points
## every that many rate periods while the mana is below the maximum (at the maximum the timer is left as it is).
## Computer slots shorten the rate by 0x611254[AI value]. Spells (the only spending) are not simulated.
func _regenerate_mana(f):
	var own := hero_block(f.owner)
	if own.is_empty(): return
	if not f.has("max_mana"):
		f["max_mana"] = int(HeroEffects.hero_unit(own).max_mana)
		f["mana"] = HeroEffects.start_mana(int(f.max_mana), int(own.get("level", 1)))
		f["mana_ms"] = 0
	if int(f.mana) >= int(f.max_mana): return
	if spells != null and not spells.mana_flowing(): return   # B1-6b: 0x51b6b0 while 0x7494c4 < 1 (Freeze Magic)
	var research: Array = production.research.get(f.owner, []) if production != null else []
	var rate: int = spells.hero_mana_rate(f, own, research) if spells != null else HeroEffects.mana_rate(own, research)   # B1-6c: + effect 0x21
	if ai_players.has(f.owner) and production != null:
		rate -= int(HeroEffects.MANA_COMPUTER[clampi(int(production.ai_players.get(f.owner, 0)), 0, 7)])
	if rate < 1: return
	var step := rate
	var gain := 1
	while step < 1000:
		step += rate
		gain += 1
	var due: int = int(f.mana_ms)
	if due == 0:
		f["mana_ms"] = step + now_ms
		return
	if now_ms < due: return
	f["mana"] = int(f.mana) + gain
	f["mana_ms"] = step + now_ms

func _hero_attack_stat(f) -> int:
	if not f.hero or not heroes.has(f.owner): return 0
	var m = heroes[f.owner].match
	return 0 if m.profile == null else HeroRules.derived(m.profile.data.stats, 16, 1)

func _update_swing(f):
	var swing: Dictionary = f.swing
	if not swing.hit_done and now_ms >= swing.hit_ms:
		swing.hit_done = true
		_hit(f, swing)
	if now_ms >= swing.end_ms:
		f.swing = null
		f.state = "approach" if f.order != null else "idle"

## 0x523150 state 2 at animation entry 6 (ANI +0x18). The target is looked up again by id; the original does not check
## the distance again, so a target that stepped away is still hit by a melee swing.
func _hit(f, swing: Dictionary):
	hit_entry.emit(f.id, swing)
	# B3-1 (E9, Emulated "firebomb" hit entry): the Firebomb dies at its hit entry on the host (vtable +0x38(0, 0, 0)); the target
	# takes no swing; its death runs the blast (_kill_unit). B5-1 (E7, Emulated "spore"): the Spore AGSP the same (lost code at 0x523253).
	if String(f.type_id) in RacePowers.BLAST_TYPES:
		apply_damage("unit", int(f.id), maxi(1, int(f.hp)), -1, "none")
		return
	if swing.target_kind == "unit" and not alive(fighters.get(swing.target_id)): return
	if swing.target_kind == "building" and not target_alive(swing):
		return
	if not swing.ranged:
		var result: Dictionary = swing.result
		if result.has("fault"): return
		var swept: Array = sweep_targets(f, swing.target_kind, int(swing.target_id))   # cells read before the blow lands
		_melee_blow(f, swing.target_kind, int(swing.target_id), result)
		for o in swept: _melee_blow(f, String(o.kind), int(o.id), result)
		return
	# Ranged: 0x523150 creates a missile (0x58bdd0 -> 0x53df60) aimed at the target sprite; the unit's accuracy is tested
	# against the roll stored with its attack (+0x228). Damage is resolved where the missile meets someone (0x5427e0).
	var shooter := {"kind": "unit", "owner": f.owner, "cell": unit_cell(f.id), "rect": _sprite_rect("unit", f.id),
		"launch_offset": _launch_offset(f), "combat": Rules.effective_combat(combat_block(f)), "roll": int(swing.message_roll),
		"flags_ba": 0, "high": bool(units[f.id].flying), "elevation": _elevation(unit_cell(f.id))}   # issue 11: a flyer shoots from the air
	var missile_id := String(f.stats.get("missile", MISSILE_IDS.unit))
	var damage := int(f.stats.dmg)
	# B3-1 (E10, Emulated "ammunition" shots): a shot of damage type 5 with a stored animal uses one: damage x 3, the animal's id.
	var stored := int(f.get("stored_animals", 0))
	if stored > 0 and int(f.stats.dtype) == RacePowers.STORED_DTYPE and RacePowers.STORERS.has(String(f.type_id)):
		f["stored_animals"] = stored - 1
		damage *= RacePowers.STORED_FACTOR
		missile_id = String(RacePowers.STORERS[String(f.type_id)])
	var m := Missiles.create(missile_id, shooter, _missile_target(swing.target_kind, swing.target_id), rng, now_ms, _map_size())
	m.merge({"attacker": f.id, "attacker_kind": "unit", "damage": damage, "dtype": int(f.stats.dtype),
		"target_kind": swing.target_kind, "target_id": swing.target_id, "launch_ms": now_ms, "from": shooter.cell, "to": m.aim})
	missiles.append(m)
	# 0x523150: one 1..100 draw after the missile exists (B3-1 E11, Emulated "missile_kinds": ATOX and AOXX write kind 3).
	# G-4 (disassembly 0x52351e..0x52355c): the draw comes before the type test, so the petrifiers draw too (B3-1 skipped
	# it); below 5 the kind of the damage type, else the art's kind 0x53f180 (Army.cfg's shoot id, Emulated "art_kinds").
	var art := String(f.stats.get("shoot", m.get("art", m.id)))
	var crit: Array = Criticals.missile_kind(String(f.type_id), int(f.stats.dtype), damage, Criticals.draw_kind(rng, int(f.stats.dtype)), Criticals.art_kind(art))
	m["kind"] = int(crit[0])
	m["level"] = int(crit[1])
	missile_launched.emit(m)

## 0x51ab00 -> 0x51abe0 on one object: the swing's stored damage, effect and parameter (+0x222 / +0x238 / +0x239, rolled once
## against the target at the swing's start); Venom, the contagion and the burn roll inside 0x51abe0 for each object.
func _melee_blow(f, kind: String, id: int, result: Dictionary):
	if kind == "unit" and not alive(fighters.get(id)): return
	if kind == "building" and not target_alive({"target_kind": kind, "target_id": id}): return
	# Playtest 2026-11-11: 0x51ab00 lets a hero's "cast spell" item powers roll before the blow (0x529d20, spells.item_casts).
	if spells != null and bool(f.hero): spells.item_casts(f, kind, id)
	# B1-6b / B1-6e (REVIEW_HERO_SPELLS_E.md D3): 0x51abe0 rolls Venom and the contagion before the damage lands.
	if spells != null and kind == "unit": spells.venom_hit(f, fighters.get(id))
	# B2-1 (R3, Emulated: fixtures "fire"): 0x51abe0 effect 1, a critical (x4 / x2) melee hit of damage type 3 or 0xb, sends
	# message 0x204 with the swing's parameter as the level: the target burns (0x527720(0)) unless the blow kills it.
	if spells != null and kind == "unit" and int(result.effect) == Rules.EFFECT_BURN:
		spells.berserk({"kind": "unit", "id": id}, int(result.param))
	Criticals.before_blow(self, f, kind, id, result)       # G-4: effect 4 (message 0x20f before the hit's own)
	apply_damage(kind, id, int(result.damage), f.id)
	Criticals.after_blow(self, f, kind, id, result)        # G-4: effects 6, 8, 9, 10, 11 (0x51abe0's switch, Emulated)

## The melee sweep (BATCH3_RESEARCH.md E13, Emulated: tests/batch3_fixtures.json "sweep"; the loop 0x523998..0x523ad7 Read from
## the disassembly, 0x523150 is not in the decompile). After the swing at the target, these types and every titan (+0x1cd)
## swing at each object of another owner (allies too) in the 3 x 3 cells from the target's sprite cell towards +x, +y (the
## target is the corner), the ground layer (+0x18) and then the air layer (+0x1c), units and buildings (kinds 0 / 1); each
## object once (the target is the list's first entry). The sweep sits on the melee path only (range <= 0), so a ranged
## titan (Gornak ATOX, range 8) does not sweep. The original's 16-entry list cannot overflow 9 + 9 cells with one entry per
## cell and layer here: not ported (REVIEW_BATCH3.md section 7).
const SWEEPERS := ["AVDX", "AAEA", "AFGX", "AOGX", "AGHY", "AGPY", "AGCY", "AAJX"]

static func sweeps(type_id: String) -> bool:
	return type_id in SWEEPERS or UnitRanks.is_titan(type_id)

func sweep_targets(f, target_kind: String, target_id: int) -> Array:
	var out: Array = []
	if f == null or not sweeps(String(f.type_id)) or navigator == null: return out
	# 0x5236ac: the melee path needs the swing's range <= 0 (0 against a hunter's prey, as order_range).
	if order_range(f, {"target_kind": target_kind, "target_id": target_id}) > 0: return out
	var corner: Vector2i
	if target_kind == "unit":
		if not fighters.has(target_id): return out
		corner = unit_cell(target_id)
	else:
		var b = production.building(target_id) if production != null else null
		if b == null: return out
		corner = _building_sprite(b).cell
	var seen := {"%s:%d" % [target_kind, target_id]: true}
	var size := _map_size()
	for layer in 2:
		for i in 9:
			var cell := corner + Vector2i(i % 3, i / 3)
			if cell.x < 0 or cell.y < 0 or cell.x >= size.x or cell.y >= size.y: continue
			var o := _layer_object(cell, layer)
			if o.is_empty() or int(o.owner) == int(f.owner): continue
			var key := "%s:%d" % [o.kind, int(o.id)]
			if seen.has(key): continue
			seen[key] = true
			out.append(o)
	return out

## The object a cell holds on a layer (cell +0x14 of the +0x18 ground / +0x1c air arrays): a unit, else a building's cell.
func _layer_object(cell: Vector2i, layer: int) -> Dictionary:
	var unit = navigator.air_occupant(cell, null) if layer == 1 else navigator.occupant(cell, null)
	if unit != null and fighters.has(unit.unit_id):
		var g = fighters[unit.unit_id]
		return {"kind": "unit", "id": int(g.id), "owner": int(g.owner)}
	if layer == 0 and navigator.building_cells.has(cell) and production != null:
		var b = production.building(navigator.building_cells[cell])
		if b != null: return {"kind": "building", "id": int(b.entity_id), "owner": int(b.owner)}
	return {}

func _update_missiles():
	var world := MissileWorld.new(self)
	var remaining: Array = []
	for m in missiles:
		var before: int = m.impacts.size()
		var alive := Missiles.tick(m, now_ms, world)
		if bool(m.get("meteor", false)) and m.impacts.is_empty() and not bool(m.get("blasted", false)) and int(m.index) >= int(m.steps) - 1:
			m["blasted"] = true                                # B5-1: the meteor's ground blast on its last record
			_meteor_blast(m)
		if m.impacts.size() > before: _impact(m, m.impacts[-1])
		elif not alive and m.impacts.is_empty() and not m.get("reported", false):
			m["reported"] = true
			var info: Dictionary = m.duplicate()
			info["hit"] = false
			missile_landed.emit(info)
			_goblin_landing(m)
		if alive: remaining.append(m)
	missiles = remaining

## B5-1 (BATCH5_RESEARCH.md E5 / Open 1, Emulated: tests/batch5_meteor_fixtures.json): one Couatl's Wrath meteor (0x58bea0 ->
## 0x53e960) from `from` to `to`; no owner, no damage, no attacker. Returns the missile.
func launch_meteor(from: Vector2i, to: Vector2i) -> Dictionary:
	var m := Missiles.create_sky(from, to, now_ms, _map_size())
	m.merge({"attacker": -1, "attacker_kind": "none", "damage": 0, "dtype": 0, "target_kind": "none", "target_id": -1, "launch_ms": now_ms,
		"from": from, "to": m.aim, "meteor": true})
	missiles.append(m)
	missile_launched.emit(m)
	return m

## The step's ground blast (0x540cf3..0x540e3a, Emulated "flights"; on the host): every unit and building whose sprite cell lies in
## the box round the landing cell (rows from y - 4 clamped at 0, eight rows; columns x - 4 .. x + 4), of any owner, takes
## 0x42bbf0(150, 2, fire, its armour) through vtable +0x38 with no attacker.
func _meteor_blast(m: Dictionary):
	var c: Vector2i = m.aim
	var x0 := maxi(0, c.x + int(RacePowers.METEOR_BOX[0]))
	var y0 := maxi(0, c.y + int(RacePowers.METEOR_BOX[2]))
	var x1 := x0 + int(RacePowers.METEOR_BOX[1]) - int(RacePowers.METEOR_BOX[0])
	var y1 := y0 + int(RacePowers.METEOR_BOX[3]) - int(RacePowers.METEOR_BOX[2])
	var inside := func(p: Vector2i) -> bool: return p.x >= x0 and p.x <= x1 and p.y >= y0 and p.y <= y1
	race_event.emit("meteor_blast", {"cell": c})
	var hits: Array = []
	for f in fighters.values():
		if f.removed or not alive(f): continue
		var u = units[f.id]
		if u.inside_building or not inside.call(unit_cell(f.id)): continue
		hits.append(["unit", int(f.id), combat_block(f)])
	if production != null:
		for b in production.buildings.values():
			if int(b.hit_points) <= 0 or not inside.call(_building_sprite(b).cell): continue
			hits.append(["building", int(b.entity_id), building_block(b)])
	for h in hits:
		var block: Dictionary = h[2]
		var dealt := Rules.armour_tail(RacePowers.METEOR_BLAST, RacePowers.METEOR_BLAST_MODE, RacePowers.METEOR_BLAST_DTYPE, Rules.armour_table(block), Rules.resist_flags(block))
		if dealt == Rules.FAULT_DAMAGE: continue
		apply_damage(String(h[0]), int(h[1]), dealt, -1, "none")

## B3-1 (E12, Emulated "goblin"; 0x541e00 decompile 214114..): an AOSX missile's end: one 1..8 draw; on 1, with the shooter's owner
## under its command limit, the missile's cell empty and not on the map's first or last row or column: one live AOSX of that owner
## (message 0xfa, +0x3b = 0) on script 4 (Rampant). Open: the splash 0x541e00 deals before it (3/4 of the damage to the 8 cells
## round, 3/4 of that to the 12 next) is not ported (BATCH3_RESEARCH.md B3-1 "Deviations").
signal race_event(kind: String, info: Dictionary)        # B3-1: presentation of the batch-3 rules (main.gd: sounds, effects)

func _goblin_landing(m: Dictionary):
	if String(m.get("id", "")) != RacePowers.GOBLIN or bool(m.get("goblin_done", false)): return
	m["goblin_done"] = true
	var shooter = fighters.get(int(m.get("attacker", -1)))
	var owner: int = int(shooter.owner) if shooter != null else int(m.get("owner", -1))
	if int(rng.roll(1, 8, 0)) != 1 or owner < 0 or production == null or spells == null: return
	var pop: Dictionary = production.population(owner)
	if int(pop.current) >= int(pop.maximum): return
	var cell: Vector2i = m.get("cell", Vector2i(-1, -1))
	if not RacePowers.goblin_cell_ok(cell, _map_size()): return
	if navigator.occupant(cell, null) != null or navigator.building_cells.has(cell): return
	var made: Dictionary = spells.spawn(RacePowers.GOBLIN, cell, owner, 0, 0, {"start": true})
	if made.is_empty(): return
	var g = fighters.get(int(made.id))
	if g != null: g.script = RacePowers.GOBLIN_SCRIPT
	race_event.emit("goblin", {"id": int(made.id), "cell": cell})

## 0x5427e0 (Read): the object the flight met takes the shooter's damage, armour first (0x42bbf0), then the elevation
## table, then the arrow-versus-building divisor; nothing when the shooting unit has died since (+0x2a == 8).
func _impact(m: Dictionary, hit: Dictionary):
	var info: Dictionary = m.duplicate()
	info["hit"] = true
	info["struck_kind"] = hit.kind
	info["struck_id"] = hit.id
	info["impact_sound"] = Missiles.impact_sound(String(m.get("art", m.id)), hit.kind)   # P-3: keyed by +0x13c (sound only)
	if not m.has("kind"):                                   # G-4: a missile not made by a unit's shot keeps its art's kind (0x53f180)
		var ak: Array = Criticals.art_kind(String(m.get("art", m.id)))
		m["kind"] = int(ak[0])
		m["level"] = int(ak[1])
	if m.attacker_kind == "unit":
		var shooter = fighters.get(m.attacker)
		if shooter != null and (shooter.state == "dying" or shooter.state == "corpse"):
			info["hit"] = false
			info["shooter_dead"] = true
			missile_landed.emit(info)
			return
	var block: Dictionary
	var cell: Vector2i
	if hit.kind == "unit":
		block = combat_block(fighters[hit.id])
		cell = unit_cell(hit.id)
	else:
		var b = production.building(hit.id)
		block = building_block(b)
		cell = _building_sprite(b).cell
	var raw := Criticals.skips_armour(m, String(hit.kind))   # G-4: kind 10 on a unit skips 0x42bbf0 (0x5428cb, Read)
	var tail := func(damage: int, dtype: int) -> int:
		if raw: return Rules.s16(damage)
		return Rules.armour_tail(damage, 2, dtype, Rules.armour_table(block), Rules.resist_flags(block))
	var amount := Missiles.impact_damage(m, int(m.damage), int(m.dtype), hit.kind, _elevation(cell), tail, spells != null and spells.shooter_phun(m))   # B1-6c: PHUN
	if spells != null and hit.kind == "unit": amount = spells.missile_resisted(m, fighters[hit.id], amount)   # B1-6a: 0x527040
	if amount == Rules.FAULT_DAMAGE:
		info["hit"] = false
		info["fault"] = true
	else:
		info["damage"] = amount
		if amount > 0: apply_damage(hit.kind, hit.id, amount, m.attacker, m.get("attacker_kind", "unit"))
		# B2-1 (R3, Read: 0x5427e0 kind +0x67c = 1, which 0x53f180 sets for EMF1 with level +0x67d = 0): a unit struck burns.
		# G-4: kind 1 from the art (EMF1) or the shot's draw, with its level (+0x67d).
		if spells != null and hit.kind == "unit" and int(m.get("kind", 0)) == Criticals.BURN: spells.berserk({"kind": "unit", "id": int(hit.id)}, int(m.get("level", 0)))
		# B3-1 (R3, Emulated review "petrify"): kind 3 on a unit brought to 0 (Life Ward keeps it alive: no message 0x20e): the
		# shooter's owner gets 100 stone (0x43e9b0, clamped), EZ42 and Petrify.wav, and the body is gone (0x51a130).
		if hit.kind == "unit" and int(m.get("kind", 0)) == 3 and amount > 0:
			var t = fighters.get(int(hit.id))
			if t != null and t.state == "dying" and int(t.death_ms) == now_ms: _petrify(t, m)
		# G-4: kind 5 (Crystallize, the Celestial Dragon's EMF5) the same way: message 0x214, 100 crystal, no body.
		if hit.kind == "unit" and int(m.get("kind", 0)) == Criticals.CRYSTALLIZE and amount > 0 and spells != null:
			var t = fighters.get(int(hit.id))
			if t != null and t.state == "dying" and int(t.death_ms) == now_ms: Criticals.crystallize(self, t, fighters.get(int(m.attacker)) if String(m.get("attacker_kind", "unit")) == "unit" else null)
		Criticals.after_impact(self, m, hit)            # G-4: kinds 6, 8, 9, 10, 11, 12, 14 (0x5427e0's switch, Read)
	missile_landed.emit(info)
	_goblin_landing(m)

func _petrify(t, m: Dictionary):
	var shooter = fighters.get(int(m.attacker))
	if shooter == null: return
	t.removed = true                                       # no corpse: no d animation hold, Call the Dead finds nothing
	var unit = units[t.id]
	unit.visible = false
	unit.removed = true
	if spells != null: spells.credit(int(shooter.owner), [0, 0, 0, RacePowers.PETRIFY_STONE])
	race_event.emit("petrify", {"cell": unit.cell, "owner": int(shooter.owner), "shooter": int(shooter.id)})   # P-3: the text's object

## Map view for the flight step: units are the cell occupants (+0x14), stamped building cells belong to their building,
## static map objects without a building (features) are "other" occupants that end the probe without a hit.
class MissileWorld:
	var combat
	var width := 128
	var height := 128
	func _init(c):
		combat = c
		var size: Vector2i = c._map_size()
		width = size.x
		height = size.y
	func occupant(cell: Vector2i) -> Dictionary:
		var nav = combat.navigator
		var unit = nav.occupant(cell, null)
		if unit != null and combat.fighters.has(unit.unit_id):
			var f = combat.fighters[unit.unit_id]
			return {"kind": "unit", "id": f.id, "owner": f.owner, "hp": f.hp, "tall": false}
		if nav.building_cells.has(cell):
			var b = combat.production.building(nav.building_cells[cell]) if combat.production != null else null
			if b != null: return {"kind": "building", "id": b.entity_id, "owner": b.owner, "hp": b.hit_points}
		if nav.collision != null and nav.collision.inside(cell):
			var c: Dictionary = nav.collision.cell_data(cell)
			if not c.is_empty() and c.has("object_indices") and not c.object_indices.is_empty():
				return {"kind": "other", "id": -1, "owner": 6}
		return {}
	## Issue 11: the cell's flyer (the air array, cell +0x1c), which the flight step asks for at heights 2 and above. Before,
	## the world answered with the ground layer only, so no missile ever met a flying unit. Provisional: which heights
	## read which layer in 0x53fbc0 is not read; a flyer carries the "tall" bits (bit 21), which the hit test does read.
	func air_occupant(cell: Vector2i) -> Dictionary:
		var unit = combat.navigator.air_occupant(cell, null)
		if unit == null or not combat.fighters.has(unit.unit_id): return {}
		var f = combat.fighters[unit.unit_id]
		return {"kind": "unit", "id": f.id, "owner": f.owner, "hp": f.hp, "tall": true}
	func hard_block(cell: Vector2i) -> bool:
		var nav = combat.navigator
		if nav.collision == null or not nav.collision.inside(cell): return false
		var c: Dictionary = nav.collision.cell_data(cell)
		return not c.is_empty() and c.has("raw") and int(c.raw[1]) == 9        # TER byte +1, copied to cell +9 (0x42bf80)
	func allied(a: int, b: int) -> bool:
		return combat.allied(a, b)
	func building_pixel_hit(id, x: int, y: int) -> bool:
		if combat.pixel_test.is_valid(): return bool(combat.pixel_test.call(id, x, y))
		return true

func _map_size() -> Vector2i:
	if navigator != null and navigator.collision != null: return Vector2i(int(navigator.collision.width), int(navigator.collision.height))
	return Vector2i(128, 128)

func _elevation(cell: Vector2i) -> int:
	if navigator == null or navigator.collision == null or not navigator.collision.inside(cell): return 0
	return navigator.nav_cell_height(cell)                # 0x48f810: TER cell byte 0 (the nav height)

## The building sprite's cell and pixel (+0x48 / +0x4c): the anchor cell (centre column, anchor row) and its centre.
func _building_sprite(b) -> Dictionary:
	var cell := Vector2i(int(b.position.x) / 32, int(b.position.y) / 24)
	return {"cell": cell, "pixel": Vector2i(cell.x * 32 + 16, cell.y * 24 + 12)}

func _sprite_rect(kind: String, id: int) -> Array:
	if sprite_rect.is_valid():
		var r = sprite_rect.call(kind, id)
		if r is Array and r.size() == 4: return r
	if kind == "unit":
		var p: Vector2 = units[id].position
		return [int(p.x) - 44, int(p.y) - 45, 88, 66]
	var b = production.building(id)
	var px: Vector2i = _building_sprite(b).pixel
	return [px.x - 64, px.y - 96, 128, 128]

## ARM +0x10c + 4 * facing (unit sprite vtable 0x5eae8c +0x3c/+0x40); heroes (+0xb4) use the rectangle centre.
func _launch_offset(f) -> Vector2i:
	if f.hero: return Vector2i.ZERO
	var table: Array = f.stats.get("launch", [])
	if table.size() != 8: return Vector2i.ZERO
	var facing: int = units[f.id].direction
	return Vector2i(int(table[facing][0]), int(table[facing][1]))

## Target sprite fields 0x53df60 reads: cell +0x48, pixel +0x4c - +0x96, walking (+0x38 == 1), facing +0x40, speed
## 0x51c460(1) (+2 near the owner's living hero, unit +0x190), flying bit 21, elevation.
func _missile_target(kind: String, id: int) -> Dictionary:
	if kind == "unit":
		var t = fighters[id]
		var u = units[id]
		var speed := int(t.stats.get("speed", 8)) - int(t.stats.get("enc", 0)) + (2 if near_hero(t) else 0)
		return {"kind": "unit", "cell": unit_cell(id), "pixel": Vector2i(int(u.position.x), int(u.position.y)), "moving": bool(u.in_step),
			"facing": int(u.direction), "speed": speed, "high": bool(u.flying), "elevation": _elevation(unit_cell(id))}   # issue 11: bit 21
	var b = production.building(id)
	var sprite := _building_sprite(b)
	return {"kind": "building", "cell": sprite.cell, "pixel": sprite.pixel, "moving": false, "facing": 0, "speed": 0, "high": false,
		"elevation": _elevation(sprite.cell)}

# ----------------------------------------------------------------------------------------- damage and death
signal building_hit(id: int, attacker_kind: String, attacker_id: int)
var hate_hook := Callable()                # AI-4: set by main.gd for a skirmish with computer players

func apply_damage(kind: String, id: int, amount: int, attacker_id: int, attacker_kind: String = "unit"):
	if kind == "unit":
		var t = fighters.get(id)
		if not alive(t): return
		if spells != null: spells.reveal(t)                 # B1-6d: 0x522af0 (0x522b2c) ends invisibility (+0x1f1)
		t.hp = t.hp - amount                                # 0x522af0: the new hit points are stored, then 0x522860 reacts
		units[id].hp = maxi(0, t.hp)
		damaged.emit("unit", id, amount, attacker_id)
		if attacker_kind == "unit": _drain(fighters.get(attacker_id), t)
		if t.hp <= 0 and spells != null and spells.life_ward(t): return   # B1-6b: 0x522860 effect 0x3e (Life Ward)
		if t.hp <= 0:
			t.hp = 0
			_kill_unit(t, attacker_id if attacker_kind == "unit" else -1)
		else:
			if attacker_id >= 0: ai.record_hit(attacker_kind, attacker_id, id, now_ms)   # 0x505b90(attacker, victim) when the unit survives
			if not t.hero and int(t.get("regen_ms", 0)) == 0: _regenerate_unit(t)   # R-1: 0x522860 -> 0x51b820 arms the timer
		return
	var b = production.building(id)
	if b == null or b.hit_points <= 0: return
	b.hit_points -= amount                                   # 0x52bd10 stores the new building hit points
	if hate_hook.is_valid(): hate_hook.call(b, amount, attacker_kind, attacker_id)   # AI-4: 0x52bd10 -> 0x5055d0 (hate)
	damaged.emit("building", id, amount, attacker_id)
	building_hit.emit(id, attacker_kind, attacker_id)
	if b.hit_points <= 0:
		b.hit_points = 0
		_kill_building(b, attacker_id)

## G-1 (Read, 0x522860 -> 0x5227e0): a unit attacker other than the victim with a life drain (0x526f40, ResearchEffects.drain;
## a hero's skill 0x35 / item 0x3c terms through spells.drain_terms, G-2 Emulated) heals by it up to its maximum, before the
## victim's death check.
func _drain(attacker, victim):
	if attacker == null or attacker == victim or attacker.removed or attacker.hp <= 0 or production == null: return
	if attacker.hero and spells == null: return
	var amount := 0 if attacker.hero else ResearchEffects.drain(String(attacker.type_id), production.research.get(attacker.owner, []))
	if spells != null: amount += spells.drain_terms(attacker)   # B1-6a: 0x526f40 hero skill 0x35 / item 0x3c, effect 0x3c
	if amount == 0 or attacker.hp >= int(attacker.max_hp): return
	attacker.hp = mini(int(attacker.max_hp), attacker.hp + amount)
	units[attacker.id].hp = attacker.hp

## G-1 (Read, 0x51bfb0 / 0x51b820, CombatRules.poison_start / poison_tick): poisons or cures a unit. The original poisons by
## missile hits (EMAP / EMFP, 0x5427e0) and spell kind 4 (0x4ac0e0); neither source is ported yet (Open).
func set_poisoned(unit_id: int, on: bool):
	var f = fighters.get(unit_id)
	if not alive(f): return
	if on:
		var was := bool(f.get("poisoned", false))
		Rules.poison_start(f, now_ms, int(f.stats.mres))
		# 0x51bfb0 arms +0x164 for every unit on a new poisoning (REVIEW_R1.md D3, Read): the unit regenerates after the cure.
		if not was: f["regen_ms"] = int(f.poison_next_ms)
	else: f["poisoned"] = false

func _poison(f):
	if not bool(f.get("poisoned", false)) or not alive(f): return
	var curse := false
	if production != null:
		for owner in production.research:
			if production.research_level(int(owner), "PMCU") != 0: curse = true
	if Rules.poison_tick(f, now_ms, curse) > 0:
		units[f.id].hp = maxi(0, f.hp)

## 0x5210b0: state 8, occupancy released, selection cleared, XP awarded, d animation, removal 30.7 s later.
func _kill_unit(t, killer_id: int):
	t.state = "dying"
	t.death_ms = now_ms
	t.order = null
	t.swing = null
	var unit = units[t.id]
	unit.stop()
	navigator.release(unit, unit.cell)
	unit.dying = true
	unit.selected = false
	unit.hp = 0
	var killer = fighters.get(killer_id)
	var killer_owner: int = killer.owner if killer != null else -1
	# B2-1 (R7, Read: 0x5210b0): the counter follows the unit's current owner; nothing handles conversion.
	if RacePowers.LORD_COUNTER.has(t.type_id): lord_counter[t.owner] = int(lord_counter.get(t.owner, 0)) - int(RacePowers.LORD_COUNTER[t.type_id])
	_eat(killer, t)
	if t.has("berserk"):                                 # 0x5210b0 at 0x521d39 clears the state
		t.erase("berserk")
		berserk_changed.emit(int(t.id), -1, false)
	# 0x5210b0 gates every XP award on the victim not being an animal (0x528280(0)) and on a different owner.
	var animal := UnitAI.is_animal(t.type_id)
	# 0x5210b0 at 0x52161c-0x52163b (Read, disassembled): a unit killer that 0x526fe0 accepts takes the victim's own XP
	# (0x526db0: unit +0x40, or the victim owner's profile XP for a hero), before and outside the gates below. 0x526fe0:
	# non-hero AUKX / AUXX, or a non-zero 0x577520(0x19) (an item or skill lookup, Open; 0 here).
	# B1-6c: 0x526fe0 with spells: any unit with effect 0x19 (Mind Leech) too, heroes included.
	var leech: bool = (spells.mind_leech(killer) != 0) if spells != null and killer != null else (killer != null and not killer.hero and (killer.type_id == "AUKX" or killer.type_id == "AUXX"))
	if killer != null and killer.id != t.id and leech:
		var drained: int = int(t.xp)
		if t.hero and heroes.has(t.owner) and heroes[t.owner].match.profile != null: drained = int(heroes[t.owner].match.profile.data.xp)
		gain_experience(killer, drained)
		xp_log.append({"owner": killer.owner, "unit": killer.id, "amount": drained, "reason": "victim xp (0x526db0)"})
	if killer != null:
		killer.kills += 1
		kills[killer.owner] = int(kills.get(killer.owner, 0)) + 1
		if not animal and killer.owner != t.owner:
			# Milestone 13 (Read, 0x5210b0 at decompile 196179-196230): the killer's owner's PCRX level is added to the
			# killer's award; a Knight cavalry killer of a type on its owner's Knight's Quest list (0x70d634, PQKN) adds 25,
			# 50 with POGL. The hero's own award is unchanged.
			var crusade := 0
			if production != null:
				crusade = production.research_level(killer.owner, "PCRX")
				if not t.hero and killer.type_id in ["AHFX", "AHDX", "AHEX"] and production.quests.get(killer.owner, []).has(t.type_id):
					crusade += 50 if production.research_level(killer.owner, "POGL") != 0 else 25
			if t.hero: _award(killer, maxi(5, _hero_level(t.owner) + 1), "enemy hero", crusade)
			else: _award(killer, 1, "unit", crusade)
			if spells != null: spells.mana_leech(killer)   # B1-6c: 0x526de0 (Mana Leech, the AHGB sage)
	last_killer = killer_id
	died.emit("unit", t.id, killer_owner)
	if heroes.has(t.owner) and heroes[t.owner].unit == t.id:
		notice.emit("The hero of player %d has fallen." % t.owner)
	_batch3_death(t, killer)
	_batch4_death(t, killer)

## B4-1: the batch-4 parts of 0x5210b0 (BATCH4_RESEARCH.md E5 / E6, Emulated "death", "eggs", review "death_full"): the Ancient
## Treant's two Treants and the Priestess's six Spiders (no command check), the Queen Spider's egg.
func _batch4_death(t, killer):
	if spells == null: return
	var cell: Vector2i = units[t.id].cell
	var victim := String(t.type_id)
	if RacePowers.DEATH_SPAWNS.has(victim):
		var row: Array = RacePowers.DEATH_SPAWNS[victim]
		for i in int(row[1]):
			var made: Dictionary = spells.spawn(String(row[0]), cell, int(t.owner), 0, 0, {"start": true})
			if not made.is_empty() and String(row[2]) != "": race_event.emit("spawned", {"id": int(made.id), "effect": String(row[2]), "cell": made.cell})
	if killer != null and killer.id != t.id and String(killer.type_id) == RacePowers.QUEEN and int(killer.owner) != int(t.owner) and not allied(int(killer.owner), int(t.owner)):
		var egg: Dictionary = spells.create_spell_building(RacePowers.EGG, cell, int(killer.owner), RacePowers.EGG_MS)
		if not egg.is_empty(): race_event.emit("egg", {"id": int(egg.id), "cell": cell, "effect": RacePowers.EGG_EFFECT})

## E6's end (the lost tail of 0x52c250 at 0x52ce9e): past its end the egg hatches min(4, limit - used) Spiders with ESSP at its cell,
## then 0x40ada0 removes it at once (unlinked and destroyed, no death path: Read).
func hatch_egg(b):
	var owner: int = int(b.owner)
	var cell: Vector2i = _building_sprite(b).cell
	var pop: Dictionary = production.population(owner)
	for i in RacePowers.hatch_count(int(pop.current), int(pop.maximum)):
		var made: Dictionary = spells.spawn(RacePowers.HATCH_UNIT, cell, owner, 0, 0, {"start": true})
		if not made.is_empty(): race_event.emit("spawned", {"id": int(made.id), "effect": RacePowers.HATCH_EFFECT, "cell": made.cell})
	towers.erase(int(b.entity_id))
	production._destroy(b)

## B3-1: the batch-3 parts of 0x5210b0 (BATCH3_RESEARCH.md E7..E10, Emulated): stored animals, souls and their rewards, the blast.
func _batch3_death(t, killer):
	var cell: Vector2i = units[t.id].cell
	var victim := String(t.type_id)
	if killer != null and killer.id != t.id:
		var ktype := String(killer.type_id)
		# E10 ("ammunition" kills): AOMX / ACSH, ASCA / ACCO within 20 cells on both axes.
		if RacePowers.stores(ktype, victim, unit_cell(killer.id) - cell):
			killer["stored_animals"] = int(killer.get("stored_animals", 0)) + 1
			race_event.emit("stored", {"id": int(killer.id), "sound": String(RacePowers.STORE_SOUNDS[victim]), "cell": cell})
		# E7 ("souls"): a Succubus kill of another, non-allied owner's unit; an animal (a soul too) only on 1d100 < 20.
		if ktype == RacePowers.SUCCUBUS and int(killer.owner) != int(t.owner) and not allied(int(killer.owner), int(t.owner)) and spells != null:
			if not UnitAI.is_animal(victim) or int(rng.roll(1, 100, 0)) < RacePowers.SOUL_ANIMAL_CHANCE:
				var soul: Dictionary = spells.spawn(RacePowers.SOUL, cell, RacePowers.SOUL_OWNER, 0, 0, {"lifetime": RacePowers.SOUL_LIFETIME_MS})
				if not soul.is_empty(): race_event.emit("soul", {"id": int(soul.id), "cell": cell})
		# E8 (196386-196421): the soul eaters' reward.
		if victim == RacePowers.SOUL and RacePowers.SOUL_FEEDERS.has(ktype):
			if killer.hero:
				var gain := RacePowers.soul_mana(int(killer.get("mana", 0)), int(killer.get("max_mana", 0)))
				if gain > 0: killer["mana"] = int(killer.mana) + gain
			elif ktype == RacePowers.REAPER:
				gain_experience(killer, RacePowers.REAPER_XP)
			else:
				var gain := RacePowers.soul_mana(int(killer.get("mana", 0)), int(killer.get("max_mana", 0)))
				if gain > 0:
					killer["mana"] = int(killer.mana) + gain
					race_event.emit("soul_mana", {"id": int(killer.id), "effect": RacePowers.SOUL_MANA_EFFECT})
	# E9 ("firebomb" ring): every death of AASX / AGSP blasts the cells round it (0x529a40), the attacker the dead bomb.
	if RacePowers.BLAST_TYPES.has(victim): _blast(t, cell)

var debris: Array = []                    # B3-2: Vector2i cells of the destroyed buildings' debris nodes (Salvage)

func debris_cells() -> Array:
	return debris

func _blast(t, cell: Vector2i):
	var damage := int(combat_block(t).dmg)
	race_event.emit("blast", {"cell": cell})
	var size := _map_size()
	for ring in 2:
		var offsets: Array = RacePowers.BLAST_NEAR if ring == 0 else RacePowers.BLAST_FAR
		var amount := damage if ring == 0 else damage / 2
		for o in offsets:
			var c := cell + Vector2i(int(o[0]), int(o[1]))
			if c.x < 0 or c.y < 0 or c.x >= size.x or c.y >= size.y: continue
			var obj := _layer_object(c, 0)
			if obj.is_empty() or int(obj.owner) == int(t.owner): continue
			var block: Dictionary = combat_block(fighters[obj.id]) if obj.kind == "unit" else building_block(production.building(obj.id))
			if obj.kind == "unit" and not alive(fighters[obj.id]): continue
			var dealt := Rules.armour_tail(amount, RacePowers.BLAST_MODE, RacePowers.BLAST_DTYPE, Rules.armour_table(block), Rules.resist_flags(block))
			if dealt == Rules.FAULT_DAMAGE: continue
			apply_damage(String(obj.kind), int(obj.id), dealt, int(t.id))

## B2-1 (R4, Emulated: fixtures "eating"): 0x5210b0 for an animal (0x528280(1): not ACSO) killed by a unit with STATUS bit
## 0x80 (the rule is the bit: AMIX, AMNX, AMMX, AMGX and the Minotaur hero): Eating.wav and its effect, then on the host, when
## the killer is hurt, poisoned or diseased, message 0x1fc: hit points min(max, hp + 20); its handler 0x4a98f0 always cures
## poison and disease. The stamp test of the handler never refuses here (one machine, no stale message).
func _eat(killer, victim):
	if killer == null or not UnitAI.is_animal(String(victim.type_id), false): return
	if int(killer.stats.get("flags", 0)) & RacePowers.EATER_STATUS == 0: return
	eaten.emit(int(killer.id), unit_cell(victim.id))
	if not alive(killer): return
	var poisoned := bool(killer.get("poisoned", false))
	var diseased := bool(killer.get("diseased", false))
	if int(killer.hp) >= int(killer.max_hp) and not poisoned and not diseased: return
	killer.hp = mini(int(killer.max_hp), int(killer.hp) + RacePowers.EAT_HP)
	units[killer.id].hp = killer.hp
	if poisoned: set_poisoned(int(killer.id), false)
	if diseased and spells != null: spells._end_disease(killer)

func _kill_building(b, killer_id: int):
	var killer = fighters.get(killer_id)
	if killer != null:
		killer.kills += 1
		_award(killer, 4 if int(Rules.i16(b.definition.raw_hex.hex_decode(), 0x38)) > 0 else 3, "building")
	var owner: int = b.owner
	var id: int = b.entity_id
	towers.erase(id)
	# B3-2 (R6 / E16a): the destroyed building's debris node (kind 6, EDB0-2 by the row word 0x6977ea, decompile 211708) that
	# Salvage reads. Provisional: every destroyed building leaves one at its sprite cell for the rest of the match (the row word's
	# field and the node's lifetime are Open).
	debris.append(_building_sprite(b).cell)
	production._destroy(b)
	last_killer = killer_id
	died.emit("building", id, killer.owner if killer != null else -1)
	for f in fighters.values():
		if f.order != null and f.order.target_kind == "building" and f.order.target_id == id:
			f.order = null

## 0x527100 on the killer, then on the owner's living hero when the hero is not the killer. Ordinary unit victims
## (0x5210b0 at 0x52190e/0x521945): killer PCRX count + 1, hero 1. Enemy hero victims (0x521730/0x52176a): max(5, level + 1)
## to both. Buildings (0x52b3e0 at 0x52b5c3-0x52b60a): 3, or 4 when BUI +0x38 > 0, to both (the same pushed value).
func _award(killer, amount: int, reason: String, research_bonus: int = 0):
	gain_experience(killer, amount + research_bonus)
	xp_log.append({"owner": killer.owner, "unit": killer.id, "amount": amount + research_bonus, "reason": reason})
	xp_awarded.emit(killer.owner, amount + research_bonus, reason)
	if heroes.has(killer.owner):
		var hero_fighter = fighters.get(heroes[killer.owner].unit)
		if alive(hero_fighter):
			var hero_amount := 1 if (reason == "unit" and not killer.hero) else (amount + research_bonus if killer.hero else amount)
			heroes[killer.owner].match.award_xp(hero_amount)
			xp_log.append({"owner": killer.owner, "hero": true, "amount": hero_amount, "reason": reason})

func _hero_level(owner: int) -> int:
	if not heroes.has(owner) or heroes[owner].match.profile == null: return 1
	return int(heroes[owner].match.profile.data.level)

func _update_dying(f):
	var elapsed: int = now_ms - int(f.death_ms)
	if f.state == "dying" and elapsed >= death_frames(f.type_id) * DEATH_ENTRY_MS: f.state = "corpse"
	if elapsed >= corpse_ms(f.type_id):
		f.removed = true
		var unit = units[f.id]
		unit.visible = false
		unit.removed = true
		if visibility != null: visibility.arm_removed(f.owner, unit.cell)   # 0x5468e0: a removed sprite arms its surroundings (Read)


# ----------------------------------------------------------------------------------------- acquisition
## 0x5334f0 over the window of 0x5086f0: every hostile, living, visible unit or building in [x-r, x+r] x [y-r, y+r];
## the highest 0x533c40 score wins and the first candidate of equal score keeps it (scan order y outer, x inner).
func acquire(f) -> Variant:
	var here := unit_cell(f.id)
	var radius := maxi(SCAN_RADIUS_MIN, int(f.stats.range))
	return search_rect(f.owner, here, [here.x - radius, here.x + radius, here.y - radius, here.y + radius], f.id)

## 0x5334f0(owner, x0, x1, y0, y1, searcher): rect = [x0, x1, y0, y1] (an empty rectangle finds nothing); `from_cell`
## is the searcher's cell for the 0x533c40 distance.
func search_rect(owner: int, from_cell: Vector2i, rect: Array, self_id: int) -> Variant:
	var t0 := Time.get_ticks_usec()
	var found = _search_rect(owner, from_cell, rect, self_id)
	search_calls += 1
	search_us += Time.get_ticks_usec() - t0
	return found

var search_calls := 0                    # profiling (tests/profile_sim.gd, P-3): search_rect calls and microseconds
var search_us := 0

func _search_rect(owner: int, from_cell: Vector2i, rect: Array, self_id: int) -> Variant:
	var best = null
	var best_score := 0
	# Performance (P-1, same result, same scan order): a cell holding no ground unit, flyer or building has no candidate,
	# so it is skipped by three look-ups instead of the candidate call; the window is clamped to the map for the same reason.
	var ground = navigator.get("occupants")
	var air = navigator.get("air_occupants")
	var stamped = navigator.get("building_cells")
	var quick: bool = ground is Dictionary and air is Dictionary and stamped is Dictionary
	var x0 := int(rect[0])
	var x1 := int(rect[1])
	var y0 := int(rect[2])
	var y1 := int(rect[3])
	if quick:
		x0 = maxi(x0, 0)
		y0 = maxi(y0, 0)
		x1 = mini(x1, navigator.collision.width - 1)
		y1 = mini(y1, navigator.collision.height - 1)
		# Performance (P-3): the same scan with typed dictionaries (a typed has() skips the dynamic method look-up of
		# an untyped value; most cells of the window are empty).
		var on_ground: Dictionary = ground
		var in_air: Dictionary = air
		var buildings: Dictionary = stamped
		var no_flyers := in_air.is_empty()                # nothing below changes the three dictionaries
		# A cell holding only a building cell can be a candidate only at the cell candidate_for_owner would accept: the
		# building's nearest cell to from_cell, and only for a living building it may target. That cell is found once per
		# building and search; every other cell of the building returns null there too (same tests, same order of results).
		var gate := {}                                     # building_cells value -> the one cell that may be a candidate
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var cell := Vector2i(x, y)
				if not on_ground.has(cell) and (no_flyers or not in_air.has(cell)):
					if not buildings.has(cell): continue
					if production == null: continue
					if from_cell.x >= 0:
						var key = buildings[cell]
						var only = gate.get(key)
						if only == null:
							only = _building_gate(owner, from_cell, key)
							gate[key] = only
						if only != cell: continue
				var candidate = candidate_for_owner(owner, self_id, cell, true, from_cell)
				if candidate == null: continue
				var score: int = int(candidate.hunt) if candidate.has("hunt") else _score(owner, from_cell, candidate)
				if score > 0 and (best == null or score > best_score):
					best = candidate
					best_score = score
		return best
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var cell := Vector2i(x, y)
			if quick and not ground.has(cell) and not air.has(cell) and not stamped.has(cell): continue
			var candidate = candidate_for_owner(owner, self_id, cell, true, from_cell)
			if candidate == null: continue
			var score: int = int(candidate.hunt) if candidate.has("hunt") else _score(owner, from_cell, candidate)
			if score > 0 and (best == null or score > best_score):
				best = candidate
				best_score = score
	return best

## search_rect's building gate (P-3): the cell where candidate_for_owner can return the building production.building(key)
## for this searcher (its nearest cell to from_cell), or NO_CELL when its building tests fail for every cell (no such
## building, no hit points, own, not hostile or neutral: the same tests in the same order).
const NO_CELL := Vector2i(-99999, -99999)

func _building_gate(owner: int, from_cell: Vector2i, key) -> Vector2i:
	var b = production.building(key)
	if b == null or b.hit_points <= 0: return NO_CELL
	var who: int = b.owner
	if owner >= 0 and (who == owner or not Rules.hostile(teams, owner, who)): return NO_CELL
	if owner >= 0 and who == UnitAI.NEUTRAL: return NO_CELL
	return nearest_target_cell_from(from_cell, b.entity_id)

func _candidate_at(f, cell: Vector2i) -> Variant:
	return candidate_for_owner(f.owner, f.id, cell, true, unit_cell(f.id))

## owner -1: every object, without the hostility and fog tests (the adjacency scans 0x507e40 / 0x508300 test owners themselves).
func candidate_for_owner(owner: int, self_id: int, cell: Vector2i, fog_test: bool = true, from_cell: Vector2i = Vector2i(-1, -1)) -> Variant:
	if not navigator.collision.inside(cell): return null
	var occupant = navigator.occupant(cell, null)
	# Milestone 13: a flyer on the cell's air layer is a candidate when the cell has no ground unit and the searcher can hit
	# flyers (0x51da60). Which layer 0x5334f0 scans first is Open (Read only for the ground layer).
	if occupant == null and navigator.has_method("air_occupant"):
		var flyer = navigator.air_occupant(cell, null)
		var searcher = fighters.get(self_id)
		if flyer != null and fighters.has(flyer.unit_id) and (searcher == null or Rules.can_hit(searcher.stats, fighters[flyer.unit_id].stats)): occupant = flyer
	var kind := ""
	var id := -1
	var who := -1
	if occupant != null and fighters.has(occupant.unit_id):
		var t = fighters[occupant.unit_id]
		if not alive(t) or t.id == self_id: return null
		var searcher_f = fighters.get(self_id)
		if owner >= 0 and searcher_f != null and not Rules.can_hit(searcher_f.stats, t.stats): return null   # 0x51da60 layers
		kind = "unit"
		id = t.id
		who = t.owner
		if units[t.id].inside_building: return null
		# B2-1 (R5, the scan Read: 0x5334f0): the animal branch of a hunter: no owner, relation or fog test, and its own
		# priority (taken by search_rect instead of 0x533c40).
		if owner >= 0 and searcher_f != null and UnitAI.is_animal(t.type_id):
			var hunt := hunt_priority(searcher_f, t)
			return {"kind": kind, "id": id, "owner": who, "cell": cell, "hunt": hunt} if hunt > 0 else null
	elif production != null and navigator.building_cells.has(cell):
		var b = production.building(navigator.building_cells[cell])
		if b == null or b.hit_points <= 0: return null
		kind = "building"
		id = b.entity_id
		who = b.owner
	else:
		return null
	if owner >= 0 and (who == owner or not Rules.hostile(teams, owner, who)): return null
	# 0x5334f0 (Read, 9-fix): a search candidate is a non-animal unit (0x528280(0) == 0) or a building whose owner is not the
	# neutral player 6. Animals, the lair and the Mausoleum are never acquired by a search (they can still be ordered as targets).
	if owner >= 0 and kind == "unit" and UnitAI.is_animal(fighters[id].type_id): return null
	if owner >= 0 and kind == "unit" and spells != null and spells.unsearchable(id): return null   # B1-6d: 0x5334f0 skips +0x1f1
	if owner >= 0 and kind == "building" and who == UnitAI.NEUTRAL: return null
	if owner >= 0 and fog_test and visibility != null and not ai_players.has(owner) \
			and not visibility.is_visible(fog_viewer if owner == UnitAI.NEUTRAL else owner, cell): return null
	if kind == "building":
		var anchor := from_cell if from_cell.x >= 0 else cell
		if cell != nearest_target_cell_from(anchor, id): return null   # score each building once (its nearest cell)
	return {"kind": kind, "id": id, "owner": who, "cell": cell}

## B2-1 (R5): the priority of 0x5334f0's animal branch for this searcher and animal (0 = no prey).
func hunt_priority(f, prey) -> int:
	var type := String(f.type_id)
	if not RacePowers.HUNTERS.has(type): return 0
	# The hero's own race 0x7091fc, not the slot's race (decompile 207772).
	return RacePowers.hunt_priority(type, bool(f.hero) and int(hero_block(int(f.owner)).get("race", -1)) == RacePowers.MINOTAUR,
		int(f.hp), int(f.max_hp), String(prey.type_id), RacePowers.mana_sevenths(int(f.get("mana", 0)), int(f.get("max_mana", 0))))

## DELIBERATE MODERN CHANGE (modern_rules.gd "Movement", COMPLAINTS_AND_FIXES.md F3): each melee attacker of the same
## owner heads for its own cell next to the target (a free one, nearest first, kept while it stays usable) instead of
## all of them queueing for the one nearest cell. Ranged units and the swing's facing keep the original's choice.
func spread_target_cell(f, order: Dictionary) -> Vector2i:
	var here := unit_cell(f.id)
	var plain := nearest_target_cell(f, order)
	if int(f.stats.get("range", 0)) > 0 or plain.x < 0: return plain     # in_attack_range: melee range 0 = adjacent
	var taken := {}
	for other in fighters.values():
		if other.id == f.id or other.owner != f.owner or other.get("order") == null: continue
		if other.order.get("target_id") != order.target_id or other.order.get("target_kind") != order.target_kind: continue
		taken[other.order.get("planned_cell", Vector2i(-9999, -9999))] = true
		taken[unit_cell(other.id)] = true
	var ring: Array[Vector2i] = []
	if order.target_kind == "unit":
		for step in navigator.SEARCH_ORDER: ring.append(plain + step)
	else:
		var own := {}
		for cell in _cells_of(int(order.target_id)): own[cell] = true
		for cell in own:
			for step in navigator.SEARCH_ORDER:
				var c: Vector2i = cell + step
				if not own.has(c) and not ring.has(c): ring.append(c)
	var previous: Vector2i = order.get("planned_cell", Vector2i(-9999, -9999))
	var best := Vector2i(-1, -1)
	var best_d := 1 << 20
	# Playtest 2026-11-11: a 2 x 2 attacker only takes a cell it fits (the planner accepts any goal cell, so a giant sent
	# into a one-cell gap was wedged there and could never plan a route again).
	var mover = units[f.id]
	var size: int = int(mover.extent)
	for c in ring:
		if taken.has(c) or not navigator.enterable_static(c): continue
		if size > 1 and not navigator.passable_extent(c, size, int(mover.movement_type)): continue
		var holder = navigator.occupant(c, units[f.id])
		if holder != null and not holder.is_moving(): continue
		if c == previous: return c
		if c == here: return c
		var d := maxi(absi(here.x - c.x), absi(here.y - c.y))
		if d < best_d:
			best_d = d
			best = c
	return best if best.x >= 0 else plain

func nearest_target_cell_for(f, building_id: int) -> Vector2i:
	return nearest_target_cell(f, {"target_kind": "building", "target_id": building_id})

func nearest_target_cell_from(here: Vector2i, building_id: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_distance := 1000
	for cell in _cells_of(building_id):
		var d := maxi(absi(here.x - cell.x), absi(here.y - cell.y))
		if d < best_distance:
			best_distance = d
			best = cell
	return best

## 0x533c40, in the original's order: buildings whose ID is B+R (mines), B+L (lairs) or B+S score 0; farther than 25
## cells scores 0; base 0x32 + max(0, 11 - distance). A unit candidate without a current target (0x51aab0 == 0) keeps the
## base. With a target: 0x50 + max(0, 11 - distance) when the target's owner is allied to the searcher (0x748915[searcher +
## target owner * 7]); then -0x28 when the candidate cannot attack (attack descriptor damage < 1). A building candidate
## with a current target (0x52a410: a tower's remembered target) gains 0x1e when that target belongs to the searcher's
## owner, and loses 0x28 when its attack descriptor has no damage (Read). The building distance uses its nearest
## footprint cell (the original uses the building object's cell; Provisional).
func _priority(f, candidate: Dictionary) -> int:
	return _score(f.owner, unit_cell(f.id), candidate)

func _score(owner: int, here: Vector2i, candidate: Dictionary) -> int:
	if candidate.kind == "building":
		var code: String = production.building(candidate.id).original_type_id
		if code.length() >= 2 and code[0] == "B" and (code[1] == "R" or code[1] == "L" or code[1] == "S"): return 0
	var d := maxi(absi(here.x - candidate.cell.x), absi(here.y - candidate.cell.y))
	if d > PRIORITY_RANGE: return 0
	var near_bonus := maxi(0, 0xb - d)
	var score := 0x32 + near_bonus
	if candidate.kind != "unit":
		var tower = towers.get(candidate.id)
		if tower != null and tower.target_kind != "":
			if object_owner(tower.target_kind, tower.target_id) == owner: score += 0x1e
			if int(tower.damage) < 1: score -= 0x28
		return score
	var t = fighters[candidate.id]
	var victim_owner := _order_target_owner(t.order)
	if victim_owner < 0: return score
	if allied(owner, victim_owner): score = 0x50 + near_bonus
	if int(t.stats.dmg) < 1: score -= 0x28
	return score

## Owner of the object an order targets, or -1 when there is no order or the target no longer exists (0x51aab0 == 0).
func _order_target_owner(order) -> int:
	if order == null or not order.has("target_kind"): return -1
	return object_owner(order.target_kind, order.target_id)

func object_owner(kind: String, id: int) -> int:
	if kind == "unit":
		var victim = fighters.get(id)
		return -1 if victim == null else int(victim.owner)
	var b = production.building(id) if production != null else null
	return -1 if b == null else int(b.owner)

## Damage of the object's attack descriptor: ARM +0x32 for a unit (vtable +0x50), BUI +0x38 for a tower (0x52e9e0), else 0.
func object_damage(kind: String, id: int) -> int:
	if kind == "unit":
		var f = fighters.get(id)
		return 0 if f == null else int(f.stats.dmg)
	return int(towers[id].damage) if towers.has(id) else 0

func object_cell(kind: String, id: int) -> Vector2i:
	if kind == "unit": return unit_cell(id)
	var tower = towers.get(id)
	if tower != null: return tower.center
	var b = production.building(id) if production != null else null
	return Vector2i(-1, -1) if b == null else Vector2i(b.left + ((int(b.definition.footprint[0]) - 1) >> 1), b.top + ((int(b.definition.footprint[1]) - 1) >> 1))

## 0x748915[a + b * 7] != 0.
func allied(a: int, b: int) -> bool:
	if relations.size() == 49: return relations[a + b * 7] != 0
	return not Rules.hostile(teams, a, b)

# ----------------------------------------------------------------------------------------- towers
## A building with an attack (+0x7c = BUI +0x38 > 0) shoots: damage BUI +0x38, damage type +0x3a, range +0x3c (attack
## descriptor 0x52e9e0), period 0x6114bc[min(16, BUI +0x26)] (0x52b150). G-2: the garrison's terms (combat, rate, a
## shooter's damage type and missile) are in building_block, tower_period and _tower_shot.
## `terms` (parity pass 3): a scenario tower's level terms from 0x4a50f0 (Encounters.tower_level_terms).
func register_tower(b, center: Vector2i, terms: Dictionary = {}) -> bool:
	var raw: PackedByteArray = b.definition.raw_hex.hex_decode()
	var damage := Rules.i16(raw, 0x38)
	if damage <= 0: return false
	damage += int(terms.get("damage", 0))
	towers[b.entity_id] = {"id": b.entity_id, "center": center, "damage": damage, "dtype": Rules.i16(raw, 0x3a), "range": Rules.i16(raw, 0x3c),
		"period": TOWER_PERIOD_MS[mini(16, maxi(0, Rules.i16(raw, 0x26) + int(terms.get("period", 0))))], "target_kind": "", "target_id": -1, "next_ms": 0, "ordered": false, "shots": 0,
		"combat_term": int(terms.get("combat", 0)), "level": Rules.i16(raw, 0x26) + int(terms.get("period", 0))}
	return true

## 0x52d0d0 on the attitude-script tick (0x532530 calls it for buildings of the same players): with no player-ordered
## target, search centre +- range with the tower as searcher; a new best target replaces the remembered one; nothing
## found clears it and resets the shot timer (+0x140 = 0).
func tower_acquire(tower: Dictionary):
	var b = production.building(tower.id)
	if b == null or b.hit_points <= 0: return
	if tower.ordered:
		if _target_alive(tower.target_kind, tower.target_id): return
		tower.ordered = false
		tower.target_kind = ""
		tower.target_id = -1
	var c: Vector2i = tower.center
	var r: int = tower.range
	var best = search_rect(b.owner, c, [c.x - r, c.x + r, c.y - r, c.y + r], -1)
	if best == null:
		tower.target_kind = ""
		tower.target_id = -1
		tower.next_ms = 0
		return
	tower.target_kind = best.kind
	tower.target_id = best.id

func _target_alive(kind: String, id: int) -> bool:
	if kind == "": return false
	return target_alive({"target_kind": kind, "target_id": id})

## 0x52c250 (finished building, every game update): with a target, shoot when the timer is due (0 shoots at once and
## starts the timer from now; otherwise the next shot is the previous due time + period).
func _update_towers():
	if ai.pass_now:                      # 0x532530 calls 0x52d0d0 for buildings in the same script pass (Read)
		for id in towers: tower_acquire(towers[id])
	for id in towers:
		var tower: Dictionary = towers[id]
		if tower.target_kind == "": continue
		if int(tower.next_ms) == 0:
			_tower_shot(tower)
			tower.next_ms = now_ms + tower_period(tower)
		elif now_ms >= int(tower.next_ms):
			_tower_shot(tower)
			tower.next_ms = int(tower.next_ms) + tower_period(tower)

## G-2 (Emulated): 0x52c250 calls 0x52b150 after every shot: 0x6114bc[min(16, +0x6a + the occupants' rate terms)].
func tower_period(tower: Dictionary) -> int:
	var terms := garrison_terms(int(tower.id))
	if terms.is_empty() or not tower.has("level"): return int(tower.period)
	return TOWER_PERIOD_MS[mini(16, maxi(0, int(tower.level) + Rules.garrison_rate(terms)))]

## 0x52d600 -> message 0x137 -> 0x52d2f0: the target must still exist and live (a player-ordered target must also be
## within range); one 1..100 draw for the message; the missile (Building.cfg id: Dwarven EMA0, Swarm EMM0) leaves from
## BUI +0x76 + 4 * direction and draws its own accuracy roll (0x52d9b0 against 1d100) when it is created.
func _tower_shot(tower: Dictionary):
	if not _target_alive(tower.target_kind, tower.target_id): return
	var to := object_cell(tower.target_kind, tower.target_id)
	if tower.target_kind == "building": to = nearest_target_cell_from(tower.center, tower.target_id)
	if tower.ordered and maxi(absi(to.x - tower.center.x), absi(to.y - tower.center.y)) > int(tower.range): return
	rng.roll(1, 100, 0)
	var b = production.building(tower.id)
	var sprite := _building_sprite(b)
	var target := _missile_target(tower.target_kind, tower.target_id)
	var raw: PackedByteArray = String(b.definition.raw_hex).hex_decode()
	var dir := Missiles.direction(sprite.cell, target.cell)
	var shooter := {"kind": "building", "owner": b.owner, "cell": sprite.cell, "rect": _sprite_rect("building", tower.id),
		"launch_offset": Vector2i(Rules.i16(raw, 0x76 + 4 * dir), Rules.i16(raw, 0x78 + 4 * dir)),
		"combat": int(building_block(b).combat) + int(tower.get("combat_term", 0)), "high": true, "elevation": _elevation(sprite.cell)}
	var missile_id := String(MISSILE_IDS.get(String(b.original_type_id), "EMA0"))
	var dtype := int(tower.dtype)
	# G-2 (Read, 0x52d2f0): the occupant with STATUS bit 18 (a shooter) and the highest 0x51bd10(0) (above -10, the first
	# of equals) lends its damage type (+0x67a) and its missile (0x40ac00 on its descriptor, EMF1 -> EMF0); the damage
	# (+0x678) and the range stay the tower's.
	var best = null
	var best_combat := -10
	for o in garrison_terms(int(tower.id)):
		if not (int(o.status) >> 18) & 1: continue
		# G-3 (Read, 0x51bd10): argument 0 returns the unit's raw +0x92 at once (no research, hero, item, weather or brew
		# terms, which only arguments 1 / 2 add): the fighter's base combat, not the effective one.
		var c := int(fighters[o.id].get("base", fighters[o.id].stats).get("combat", fighters[o.id].stats.combat))
		if c > best_combat:
			best_combat = c
			best = fighters[o.id]
	if best != null:
		dtype = int(best.stats.dtype)
		missile_id = Rules.building_missile_for(dtype, int(tower.dtype), String(MISSILE_IDS.get(String(b.original_type_id), "")))
		if missile_id == BURNING_MISSILE: missile_id = "EMF0"
	var m := Missiles.create(missile_id, shooter, target, rng, now_ms, _map_size())
	m.merge({"attacker": tower.id, "attacker_kind": "building", "damage": int(tower.damage), "dtype": dtype,
		"target_kind": tower.target_kind, "target_id": tower.target_id, "launch_ms": now_ms, "from": sprite.cell, "to": m.aim})
	missiles.append(m)
	tower.shots += 1
	missile_launched.emit(m)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). The world links (navigator, production,
## units, visibility, day / night, callables) are the scene's and stay; the generator, the attitude scripts and the
## spells are saved with the combat world. A hero entry's HeroMatch goes through the Refs table (main.match_heroes holds
## the same object).
const _SAVE_SKIP := ["rng", "navigator", "production", "units", "sprite_rect", "pixel_test", "visibility", "ai", "research",
	"spells", "day_night", "pre_update", "hate_hook", "ani", "heroes", "type_status", "search_calls", "search_us", "busy_check", "garrison_of"]


func save_state(refs) -> Dictionary:
	var SG = preload("res://simulation/save_game.gd")
	var s: Dictionary = SG.capture(self, _SAVE_SKIP)
	s["rng"] = rng.save_state()
	var bound := {}
	for owner in heroes:
		var entry := {}
		for k in heroes[owner]: entry[k] = refs.ref(heroes[owner][k]) if k == "match" else SG.copy(heroes[owner][k])
		bound[owner] = entry
	s["heroes"] = bound
	s["ai"] = ai.save_state(refs)
	s["spells"] = spells.save_state(refs) if spells != null else {}
	return s

func load_state(state: Dictionary, refs):
	var SG = preload("res://simulation/save_game.gd")
	SG.restore(self, state, _SAVE_SKIP)
	rng.load_state(state.rng)
	heroes.clear()
	for owner in state.heroes:
		var entry := {}
		for k in state.heroes[owner]: entry[k] = refs.get_obj(int(state.heroes[owner][k])) if k == "match" else SG.copy(state.heroes[owner][k])
		heroes[owner] = entry
	ai.load_state(state.ai, refs)
	if spells != null and not state.spells.is_empty(): spells.load_state(state.spells, refs)
