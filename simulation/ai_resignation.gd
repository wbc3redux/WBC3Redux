extends RefCounted
## Setup rows (SKIRMISH_RESEARCH.md "Setup rows"): More Options "AI Resignation" (0x749c60 byte 2, registry AICanResign,
## on by default). At the end of a computer player's update 0x4fa120 (after its other steps and the ability pass
## 0x5001d0 / 0x4fffe0), for a slot that is not the local player and whose AI value is not 7 (the monster mode; AI value 0
## returns before), the test 0x4fc5a0(1) runs; when it says yes the player's objects are handed over (0x534340, as for an
## eliminated side) and message 0x21c follows (0x4af270: the side is out, "%s has resigned..." (Game.txt 404) on the
## message line, advisor speech 0xb when the side was the local player's enemy and another enemy is still in).
##
## 0x4fc5a0(1) (Emulated: tests/setup_rows_fixtures.json "resign", 1,500 random tables, tools/emulate_setup_rows.py):
## no when the player's hero object exists (0x70adb4, a corpse included), its population (0x709124) is above 5, its command
## limit (0x709108) above 15, or the victory option (0x70ae12) is not Standard Victory. Then the other slots 0..5 in
## order, active and not out: an enemy with more than 10 x the population or more than 2 x the limit -> yes at once; an
## ally that is a human, has its hero or is above 5 / 15 -> no at once; otherwise no.
##
## The hook lives in ai_manager.gd (after `think`), so ai_player.gd is unchanged. Provisional: the population and limit
## are read live (production.population, the values 0x533fb0 copies into 0x709124 / 0x709108); the side's name in the
## message is "Player n" (the original reads a five-byte entry at 0x748672 + 5 n, not traced).

const R = preload("res://simulation/ai_rules.gd")
const RESIGN_TEXT := 404                  # Game.txt [0404] "%s has resigned..."
const RESIGN_SPEECH := 0xb                # 0x4af270 -> 0x50f1b0(0xb)

## 0x4fc5a0(1) on plain data: `me`; per slot 0..5 arrays active, out, computer, hero, population, limit; allied[a][b];
## victory. Returns true when the player resigns.
static func should_resign(me: int, t: Dictionary) -> bool:
	if bool(t.hero[me]) or int(t.population[me]) > 5 or int(t.limit[me]) > 15 or int(t.victory) != 0: return false
	for i in 6:
		if i == me or not bool(t.active[i]) or bool(t.out[i]): continue
		if not bool(t.allied[i][me]):
			if int(t.population[i]) > int(t.population[me]) * 10 or int(t.limit[i]) > int(t.limit[me]) * 2: return true
		elif not bool(t.computer[i]) or bool(t.hero[i]) or int(t.population[i]) > 5 or int(t.limit[i]) > 15:
			return false
	return false

## The table of 0x4fc5a0's inputs from the match (SkirmishMatch) and the world (main.gd).
static func table(m, world) -> Dictionary:
	var t := {"active": [], "out": [], "computer": [], "hero": [], "population": [], "limit": [], "allied": [],
		"victory": int(m.options.get("victory", 0))}
	for i in 6:
		t.active.append(m.active(i))
		t.out.append(bool(m.eliminated[i]))
		t.computer.append(bool(m.slots[i].get("computer", false)) and bool(m.slots[i].get("active", false)))
		t.hero.append(hero_present(world.combat, i))
		var pop: Dictionary = world.production.population(i)
		t.population.append(int(pop.current))
		t.limit.append(int(pop.maximum))
		var row: Array = []
		for j in 6: row.append(m.is_allied(i, j))
		t.allied.append(row)
	return t

## 0x70adb4[p]: the hero object exists (set at creation, cleared by the object's removal 0x51a080; a corpse counts).
static func hero_present(combat, p: int) -> bool:
	if combat == null or not combat.heroes.has(p): return false
	var f = combat.fighters.get(combat.heroes[p].unit)
	return f != null and not f.removed

## The hook after a computer player's update (ai_manager.gd _pass). `ai` is the AiPlayer that just thought.
static func after_think(ai, m) -> bool:
	if ai == null or m == null or m.over or not ai.get("difficulty") is int: return false
	if not bool(m.options.get("ai_resign", true)): return false
	if ai.difficulty == R.PASSIVE or ai.difficulty == R.RAMPANT: return false     # AI value 0 returns early; 7 never tests
	var me: int = ai.me
	if me < 0 or me > 5 or me == m.local or bool(m.eliminated[me]): return false
	if not should_resign(me, table(m, ai.world)): return false
	resign(m, ai.world, me)
	return true

## 0x534340(me) then message 0x21c (0x4af270).
static func resign(m, world, me: int):
	m.cleanup.emit(me)                                   # 0x534340: units and buildings destroyed, ruins to player 6
	m.eliminated[me] = true                              # 0x748668
	m.log.append({"t": m.now_ms, "player": me, "resigned": true})
	var line := "%s has resigned..."
	if world != null and world.get("hud") != null and world.hud.has_method("game_text"):
		var text: String = world.hud.game_text(RESIGN_TEXT)
		if text != "": line = text
	line = line.replace("%s", "Player %d" % me)
	if world != null and world.has_method("player_message"): world.player_message(line)   # 0x499120: the message line
	else: m.notice.emit(line)
	var enemies := 0
	for i in 6:
		if i != m.local and m.active(i) and not bool(m.eliminated[i]) and not m.is_allied(m.local, i): enemies += 1
	if not m.is_allied(m.local, me) and enemies > 0 and world != null and world.get("audio") != null:
		world.audio.speech(RESIGN_SPEECH)
