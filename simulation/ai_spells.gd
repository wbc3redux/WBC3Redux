extends RefCounted
## B1-7 (AI_RESEARCH.md section 18): the computer hero's spell choice. Labels: Emulated = tests/ai_spell_fixtures.json
## (tools/emulate_ai_spells.py, the unmodified executable under Unicorn); Read = decompile / disassembly read only.
##
## * When: 0x5001d0 (the ability pass, simulation/ai_abilities.gd) walks the player's objects with the scan flag +0x31; a
##   hero has it (Army.cfg [HEROES] AI column "x" for all sixteen hero types) and 0x500830 hands a hero (+0xb4, vtable
##   +0x28 = 0) to 0x503c60, whose result ends the walk like any caster's.
## * The table 0x748700 + p * 0x4c (`table`): +0 enabled, +2 the mana threshold, twelve spell slots +4..+0x1a and their
##   timers +0x1c..+0x48. 0x502ed0 fills it once per match (the flag 0x7486fe, cleared by the match start 0x4179f0) for
##   every player in use, not eliminated, with a hero object: every timer = now, every slot -1; a computer player
##   (0x70d6a4) then assigns each listed spell its hero knows (0x503b50: the school's skill entry 10 + id / 10 has rank > 0
##   and id % 10 + 1 <= rank; the skill rank, not the school rank with items) to its slot, a later spell of the list
##   replacing an earlier one, and every assignment but Resist Fire's sets the enabled byte (moot: a hero knowing Resist
##   Fire knows Soul Flame and Cauterize too) (Emulated: fixtures "fill").
##   The local player's branch (0x40c6b0) never sets the enabled byte (dead in a match). Spells learned later are not added:
##   the slots are fixed at the first pass (Read: 0x7486fe has no other writer).
## * 0x503c60 per pass (Emulated: fixtures "choice"): nothing while the hero morphs (0x523dc0) or is deleted (+0x30). With
##   Quests on (0x70ae0d) a computer hero first looks for a quest building within 2 cells (0x5002e0 filter 6) and takes a
##   made-up quest there, rewarded at once (0x504490; Q-3, simulation/encounters.gd `computer_site` / `computer_visit`,
##   Emulated: tests/quest_ai_fixtures.json). The search skips player 6's buildings, so the neutral Mausoleum and Shrine
##   of every shipped map never answer. n = the weighted count
##   of living enemy units within 5 (stop 4). A computer hero drinks a healing potion (0x561d80) when it has one and
##   (n >= 3 and hp < max / 3) or (n >= 1 and hp < 50), then a mana potion (0x561c30) when it has one and (n >= 3 and pool <
##   max mana / 4) or (n >= 1 and hp < 50 and pool < max mana / 2). Without the enabled byte nothing else happens. Then:
##
## | Slot | When | Spells (fill order; the last known wins) | Timer after a cast |
## |---|---|---|---|
## | A +4 | n >= 4 | Banish, Spray Poison, Pillar of Fire, Ring of Ice, Call Lightning, Mutate, Chaos Plague, Ice Storm, Armageddon | 1 s (tried = done) |
## | B +6 | n >= 2, nothing tried | Poison Cloud, Entangle, Awe, Doomstones, Wildfire, Hand of Ice, Ring of Fire | 5 s (tried = done) |
## | C +8 | n >= 4, nothing done | Home Portal, Invisibility, Freeze, Resist Missile, Life Ward | 60 s; own effect running: its end |
## | D +0xa | n >= 2, nothing done | Immunity, Blink, Shadowform, Blessing, Ice Armor, Stoneskin | 60 s; own effect: its end |
## | I +0x14 | n < 2, or nothing done at n >= 2 | Major Healing, with 2+ weight of hurt (hp < max - 40) friendly units within 5 | 5 s |
## | J +0x16 | as I, nothing done | Cauterize, Gemberry, Heal Self, Heal Group, while the hero's hp < max - 20 | 5 s |
## | K +0x18 | as I, nothing done | Antidote, Cure, with a poisoned or diseased friendly unit within 5 | 5 s |
## | L +0x1a | nothing done | Resist Fire, with a living enemy unit of damage type 3 (fire) within 9 | 60 s; own effect: its end |
## | G +0x10 | pool >= threshold != 0, nothing done, command used <= limit - 4 | Stonecall, Call Shadow, Raise Wight, Fire Elemental, Summon Unicorn, Summon Treant, Guardian Naga, Soulharvest, Daemongate | 1 s (tried = done) |
## | H +0x12 | as G | Spectral Horde, Raise Skeleton, Summon Sprite, Summon Wasp, Summon Quasit, Summon Imp | 1 s (tried = done) |
## | E +0xc | pool >= threshold != 0, nothing done | Dig, Poison Gate, Firebreath, Morph Tower, Transform | 60 s; own effect: its end |
## | F +0xe | as E | Morph Speed, Gem of Wisdom, Venom Touch, Invigorate, Vampirism, Soul Flame, Charm, Invisibility | 60 s; own effect: its end |
##
##   Each slot also needs its timer below now and the cost 0x529fa0 within the pool; "tried = done": the slot ends the pass
##   whatever 0x5717e0 returned, the others only when it returned 1 (it returns 0 only without a living caster or without
##   the mana, which the slot already tested). "Own effect": an entry of the hero's +0xfc list whose +0x30 (the record's +6)
##   equals the spell id (0x5775a0) sets the timer to that entry's +0x24 (its end) instead of casting. When the pass cast
##   or the pool reached the threshold (or the threshold is negative), a new threshold 0x458e70(1, max - pool + 1, pool - 1)
##   (between the pool and the maximum) is drawn after the slots. The cast is 0x5717e0(hero, spell, 0), the human path:
##   `HeroSpells.cast_request` -> `Spells.order_cast` -> the dispatcher; targets are the builders' own gathers around the
##   hero, summons go to the rolled or portal cell of 0x570f80 (mode 8). No listed spell needs a placement or a dialog, and
##   the computer never casts the other 70 hero spells: no Divination or Arcane spell, no Transmute / Morph Resources /
##   Increase Casting / Create Item, none of the placement spells 11, 25, 42, 66, 76, 86 or the dialogs 28, 29, 49, 78.

const Abilities = preload("res://simulation/ai_abilities.gd")

## 0x502ed0's computer branch in code order: [spell, slot offset]. Resist Fire (first) does not set the enabled byte.
const FILL := [[0x35, 0x1a],
	[0x65, 0x06], [0x16, 0x06], [0x21, 0x06], [0x4b, 0x06], [0x62, 0x06], [0x50, 0x06], [0x36, 0x06],
	[0x12, 0x04], [0x6a, 0x04], [0x39, 0x04], [0x30, 0x04], [0x1a, 0x04], [0x26, 0x04], [99, 0x04], [0x59, 0x04], [0x3b, 0x04],
	[100, 0x0a], [0x0d, 0x0a], [0x1e, 0x0a], [2, 0x0a], [0x52, 0x0a], [0x46, 0x0a],
	[0x10, 0x08], [0x24, 0x08], [0x55, 0x08], [0x4d, 0x08], [8, 0x08],
	[0x5b, 0x0e], [0x47, 0x0e], [0x68, 0x0e], [5, 0x0e], [0x2c, 0x0e], [0x33, 0x0e], [0x3e, 0x0e], [0x24, 0x0e],
	[0x48, 0x0c], [0x69, 0x0c], [0x37, 0x0c], [0x5e, 0x0c], [0x27, 0x0c],
	[0x22, 0x12], [0x28, 0x12], [0x14, 0x12], [0x66, 0x12], [10, 0x12], [0x0e, 0x12],
	[0x4f, 0x10], [0x25, 0x10], [0x2b, 0x10], [0x3a, 0x10], [0x18, 0x10], [0x1b, 0x10], [0x6b, 0x10], [0x11, 0x10], [0x13, 0x10],
	[0x34, 0x16], [0x15, 0x16], [0, 0x16], [4, 0x16],
	[7, 0x14],
	[0x67, 0x18], [1, 0x18]]
const NO_FLAG := 0x35
const SLOTS := [0x04, 0x06, 0x08, 0x0a, 0x0c, 0x0e, 0x10, 0x12, 0x14, 0x16, 0x18, 0x1a]
## slot offset -> its timer offset (+0x1c + 2 x (slot - 4))
static func timer_of(slot: int) -> int:
	return 0x1c + (slot - 4) * 2

const STEP_SHORT := 1000            # A, G, H
const STEP_MID := 5000              # B, I, J, K
const STEP_LONG := 60000            # C, D, E, F, L
const ENEMY_RADIUS := 5
const FIRE_RADIUS := 9
const FIRE_TYPE := 3                # unit +0xa0 (ARM +0x34, the damage type) == 3: 0x5002e0 filter 4

## A fresh table (0x502ed0's reset): enabled 0, threshold -1, every slot -1, every timer `now`.
static func empty_table(now_ms: int) -> Dictionary:
	var t := {"enabled": false, "threshold": -1, "slots": {}, "timers": {}}
	for s in SLOTS:
		t.slots[s] = -1
		t.timers[timer_of(s)] = now_ms
	return t

## 0x503b50(player, spell): the hero block's skill entry 10 + spell / 10 (first match; a rank of 0 or below ends the
## search) knows spell % 10 + 1 <= rank. `skills`: [[id, unlock, rank], ...] as the block holds them.
static func knows(skills: Array, spell: int) -> bool:
	var school := spell / 10
	if school < 0 or school > 12: return false
	for e in skills:
		if int(e[0]) != 10 + school: continue
		var rank := int(e[2])
		if rank <= 0: return false
		return spell % 10 + 1 <= rank
	return false

## 0x502ed0 for one computer player (the local player's 0x40c6b0 branch never sets the enabled byte and is not ported).
static func fill(skills: Array, now_ms: int) -> Dictionary:
	var t := empty_table(now_ms)
	for pair in FILL:
		if not knows(skills, int(pair[0])): continue
		t.slots[int(pair[1])] = int(pair[0])
		if int(pair[0]) != NO_FLAG: t.enabled = true
	return t

## The table as the fixtures hold it: {enabled, threshold, slots [12, SLOTS order], timers [12, the same order]}.
static func to_rows(t: Dictionary) -> Dictionary:
	return {"enabled": 1 if bool(t.enabled) else 0, "threshold": int(t.threshold), "slots": SLOTS.map(func(s): return int(t.slots[s])),
		"timers": SLOTS.map(func(s): return int(t.timers[timer_of(s)]))}

static func from_rows(r: Dictionary) -> Dictionary:
	var t := {"enabled": int(r.enabled) != 0, "threshold": int(r.threshold), "slots": {}, "timers": {}}
	for i in SLOTS.size():
		t.slots[SLOTS[i]] = int(r.slots[i])
		t.timers[timer_of(SLOTS[i])] = int(r.timers[i])
	return t

# ------------------------------------------------------------------------------------------------ 0x503c60
## The decision on one pass. `t` is the player's table (changed in place); `env` answers the world questions in the order
## the original asks them (the live world: `LiveEnv` below; the fixtures replay the emulator's answers):
##   env.local() -> bool (owner == 0x709100), env.morphing() -> bool, env.count(radius, relation, kinds, hp, extra, stop),
##   env.hp(), env.max_hp(), env.pool(), env.max_mana(), env.potions(), env.mana_potions(), env.drink(), env.drink_mana(),
##   env.cost(spell), env.effect_end(spell) -> int or null, env.cast(spell) -> bool, env.command() -> [used, limit],
##   env.roll(sides, bonus) -> int (0x458e70(1, sides, bonus)), env.now().
## Returns 0x503c60's result (true ends 0x5001d0's walk).
static func decide(t: Dictionary, env) -> bool:
	if env.morphing() or env.deleted(): return false        # 0x523dc0, +0x30 (0x5001d0 already skips a deleted hero)
	var local: bool = env.local()
	var now: int = env.now()
	# Q-3 (QUESTS_RESEARCH.md "Q-3", Emulated: tests/quest_ai_fixtures.json "site"): with Quests on (0x70ae0d) a computer
	# hero takes the first quest building 0x5002e0(x, y, 2, 6, 0, 2, 4, 6, 1) finds and is rewarded at once (0x504490);
	# that ends the pass. Environments without the quest questions (the B1-7 fixtures, run with Quests off) skip it.
	if not local and env.has_method("quests") and env.quests():
		var site: int = env.quest_site()
		if site >= 0:
			env.quest_visit(site)
			return true
	var n: int = env.count(ENEMY_RADIUS, Abilities.ENEMIES, Abilities.UNITS, Abilities.ALIVE, 0, 4)
	if not local:
		if env.potions() > 0:
			var hp: int = env.hp()
			if (n >= 3 and hp < CombatDiv.q(env.max_hp(), 3)) or (n >= 1 and hp < 50): env.drink()
		if env.mana_potions() > 0:
			if (n >= 3 and env.pool() < CombatDiv.q(env.max_mana(), 4)) or (n >= 1 and env.hp() < 50 and env.pool() < CombatDiv.q(env.max_mana(), 2)):
				env.drink_mana()
	if not bool(t.enabled): return false
	var done := false
	var low_path := n < 2
	if not low_path:
		if n >= 4: done = _try(t, env, 0x04, STEP_SHORT, true, false) or done
		if not done: done = _try(t, env, 0x06, STEP_MID, true, false) or done
		if n >= 4 and not done: done = _try(t, env, 0x08, STEP_LONG, false, true)
		var d := int(t.slots[0x0a])
		if d < 0 or done:
			low_path = not done
		else:
			if _try(t, env, 0x0a, STEP_LONG, false, true): done = true
			else: low_path = true
	if low_path and not done:
		done = _try(t, env, 0x14, STEP_MID, false, false, func(): return env.count(ENEMY_RADIUS, Abilities.FRIENDS, Abilities.UNITS, 2, 0, 2) >= 2)
		if not done: done = _try(t, env, 0x16, STEP_MID, false, false, func(): return env.hp() < env.max_hp() - 20)
		if not done: done = _try(t, env, 0x18, STEP_MID, false, false, func(): return env.count(ENEMY_RADIUS, Abilities.FRIENDS, Abilities.UNITS, Abilities.ALIVE, 2, 1) >= 1)
	# L: the count comes before the cost test here.
	if int(t.slots[0x1a]) >= 0 and not done and int(t.timers[timer_of(0x1a)]) < now:
		if env.count(FIRE_RADIUS, Abilities.ENEMIES, Abilities.UNITS, Abilities.ALIVE, 4, 1) >= 1:
			done = _try(t, env, 0x1a, STEP_LONG, false, true)
	var threshold := int(t.threshold)
	var pool: int = env.pool()
	var reroll := done or threshold <= pool or threshold < 0
	if threshold <= pool and threshold != 0 and not done:
		if not local:
			var command: Array = env.command()
			if int(command[0]) <= int(command[1]) - 4:
				done = _try(t, env, 0x10, STEP_SHORT, true, false)
				if not done: done = _try(t, env, 0x12, STEP_SHORT, true, false)
		if not done: done = _try(t, env, 0x0c, STEP_LONG, false, true)
		if not done: done = _try(t, env, 0x0e, STEP_LONG, false, true)
	if reroll:
		pool = env.pool()
		t.threshold = Sign.s16(env.roll(Sign.s16(int(env.max_mana()) - pool + 1), pool - 1))
	return done

## One slot: spell >= 0, its timer below now, the cost within the pool, the extra test, then (for `own_effect` slots) the
## hero's running effect of that spell, then 0x5717e0. `tried`: the slot counts as done whatever the cast returned.
static func _try(t: Dictionary, env, slot: int, step: int, tried: bool, own_effect: bool, extra: Callable = Callable()) -> bool:
	var spell := int(t.slots[slot])
	var timer := timer_of(slot)
	if spell < 0 or int(t.timers[timer]) >= env.now(): return false
	if env.cost(spell) > env.pool(): return false
	if extra.is_valid() and not bool(extra.call()): return false
	if own_effect:
		var end = env.effect_end(spell)
		if end != null:
			t.timers[timer] = int(end)
			return false
	if env.cast(spell):
		t.timers[timer] = env.now() + step
		return true
	return tried

class CombatDiv:
	## C's signed division (truncation toward zero), as the original's idiv / sar sequences.
	static func q(a: int, b: int) -> int:
		var r: int = absi(a) / absi(b)
		return r if (a >= 0) == (b >= 0) else -r

class Sign:
	static func s16(v: int) -> int:
		v &= 0xffff
		return v - 0x10000 if v >= 0x8000 else v

# ------------------------------------------------------------------------------------------------ the live world
## The rebuild's answers for one computer hero (`ai`: the AiPlayer, `f`: the hero fighter).
class LiveEnv:
	var ai
	var f
	var abilities
	var drinks: Array = []
	var casts: Array = []
	func _init(ai_player, fighter, ability_tick):
		ai = ai_player
		f = fighter
		abilities = ability_tick
	func _spells():
		return ai.world.combat.spells
	func _match():
		var c = ai.world.combat
		return c.heroes[int(f.owner)].match if c.heroes.has(int(f.owner)) else null
	func local() -> bool:
		return int(f.owner) == int(ai.world.production.local_player)
	func morphing() -> bool:
		return false                     # 0x523dc0: +0x168 (an advancing unit's morph); a hero never advances
	func deleted() -> bool:
		return bool(f.removed)
	func now() -> int:
		return ai.now()
	func count(radius: int, relation: int, kinds: int, hp: int, extra: int, stop: int) -> int:
		return abilities.count(ai, ai.world.combat.unit_cell(int(f.id)), radius, relation, kinds, hp, extra, stop)
	func hp() -> int:
		return int(f.hp)
	func max_hp() -> int:
		return int(f.max_hp)
	func pool() -> int:
		return int(f.get("mana", 0))
	func max_mana() -> int:
		return int(f.get("max_mana", 0))
	func potions() -> int:
		var m = _match()
		return int(m.potions) if m != null else 0
	func mana_potions() -> int:
		var m = _match()
		return m.mana_potion_count() if m != null else 0
	func drink():
		drinks.append("healing")
		_spells().hero_spells.drink_potion(int(f.owner))
	func drink_mana():
		drinks.append("mana")
		_spells().hero_spells.drink_mana_potion(int(f.owner))
	func cost(spell: int) -> int:
		return int(_spells().cost(f, spell))
	func effect_end(spell: int):
		for s in f.get("statuses", []):
			if int(s.get("art", -1)) == spell: return int(s.until)
		return null
	## 0x5717e0's result: 0 only without a living caster or without the mana (HeroSpells.cast_request's "no caster" /
	## "mana"); a refused command check, a failed level roll or a pending cast still return 1.
	func cast(spell: int) -> bool:
		var r: Dictionary = _spells().hero_spells.cast_request(int(f.id), spell)
		casts.append({"spell": spell, "result": r})
		return String(r.get("reason", "")) not in ["no caster", "mana", "not built yet"]
	func command() -> Array:
		var pop: Dictionary = ai.world.production.population(int(f.owner))
		return [int(pop.current), int(pop.maximum)]
	func roll(sides: int, bonus: int) -> int:
		return ai.roll(1, sides, bonus)
	## Q-3: 0x70ae0d, the Quests option (the encounters' offer gate).
	func _encounters():
		return ai.world.get("encounters") if ai.world is Object else null
	func quests() -> bool:
		var e = _encounters()
		return e != null and bool(e.quests_enabled)
	func quest_site() -> int:
		return _encounters().computer_site(ai.world.combat.unit_cell(int(f.id)), now())
	var visits: Array = []
	func quest_visit(building_id: int):
		var reward: Dictionary = _encounters().computer_visit(int(f.owner), building_id, func(c, s, b): return ai.roll(c, s, b),
			_match(), ai.world.combat.unit_cell(int(f.id)))
		visits.append({"building": building_id, "reward": reward})
