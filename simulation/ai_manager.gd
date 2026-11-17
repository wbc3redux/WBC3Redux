extends RefCounted
## The AI manager 0x504a30 / 0x505310 (milestone 10b, AI_RESEARCH.md section 2, Read): one AI per computer slot; on the 50 ms
## UI timer's 500 ms pass (0x429ec0, the same clock as UnitAI.UI_TIMER_MS x PASS_TICKS) it advances its round-robin slot over
## the 7 slots to the next AI and runs that player's update 0x4fa120 (skipped while the player is eliminated). The neutral
## slot always has an AI (see Neutral), so one computer opponent runs every second pass (1 s nominal). As in 0x429ec0 it
## runs before the attitude scripts: Combat calls it at the start of each game update (`Combat.pre_update`). 0x5095a0
## (every 4th call, the strength grid) is not run. AI-4 (Read): it rebuilds, at most every 3 s (timeGetTime), per 16 x 16
## cell block and per player i the strength of the objects hostile to i (the neutral column takes every object), unit
## (buf+4 + buf+8 + 0x51c460(1) + (vtable+0x5c(1) >> 2) + 0x51bd10(1)) >> 2 with buf = the attack descriptor of
## 0x526310, building (buf+8 >> 1) + (0x52ae00(1) >> 1) + buf+4 when buf+4 >= 1 (0x52e9e0 fills 6 bytes, so buf+8 is a
## stale stack word left by the previous object), then 0x509840 adds half of the neighbouring blocks. Its readers are the
## monster mode's strength term (0x4fa990 -> 0x509980) and the sector route search's danger limit and weight (0x509320, its callers not traced): with
## the stale word and the unported descriptor layout the values stay Open; the monster mode keeps 0 (term 70).

const UnitAI = preload("res://simulation/unit_ai.gd")
const AiResignation = preload("res://simulation/ai_resignation.gd")
var players: Array = [null, null, null, null, null, null, null]
var slot := -1                           # 0xa4ef54
var calls := 0                           # 0xa4ef58
var timer_ticks := 0
var next_tick_ms := UnitAI.UI_TIMER_MS
var passes := 0
## B1-7: the computer heroes' spell tables 0x748700 + p * 0x4c (simulation/ai_spells.gd), filled once per match by
## 0x502ed0 on the first ability pass of any computer player (0x7486fe).
var hero_spells_filled := false
## AI-9: 0xa4e93c, the game time of the last home-move draw round 0x4fc020 (one round per 5 s over all players; 0 = none).
var home_move_ms := 0
var hero_spell_tables: Dictionary = {}

func add(player) -> void:
	players[player.me] = player

## 0x504a30 always creates the neutral slot's AI (0x509040(6)); 0x505310 skips only empty slots, so slot 6 takes its
## round-robin turn and one computer opponent thinks every second pass (1 s). Its monster mode (0x4fa990 / 0x4fa850) is
## Open: the neutral entry does nothing on its turn.
class Neutral:
	var me := 6
	func think(_now_ms: int) -> void:
		pass
	func dispose() -> void:
		pass

func _init() -> void:
	players[6] = Neutral.new()

## AI-4 (Read, disassembly 0x52bf0b): the building hit-point setter 0x52bd10, when a building with hit points left loses
## some to an attacker whose owner is a computer player (0x70d6a4), calls 0x5055d0(building owner, damage, attacker
## owner): the building owner's AI, if any, raises its hate counter of the attacker's player (0x4fa580). A human's damage
## raises nothing. `damage` = max(0, old - new hit points).
func building_damaged(owner: int, damage: int, attacker_owner: int, attacker_is_computer: bool) -> void:
	if not attacker_is_computer or owner < 0 or owner >= players.size() or attacker_owner < 0: return
	var p = players[owner]
	if p != null and p.has_method("add_hate"): p.add_hate(maxi(0, damage), attacker_owner)

func update(now_ms: int, match) -> void:
	while next_tick_ms <= now_ms:
		var tick_ms := next_tick_ms
		next_tick_ms += UnitAI.UI_TIMER_MS
		timer_ticks += 1
		if timer_ticks < UnitAI.PASS_TICKS: continue
		timer_ticks = 0
		_pass(tick_ms, match)

func _pass(now_ms: int, match) -> void:
	calls += 1
	passes += 1
	for i in 7:
		slot = (slot + 1) % 7
		var p = players[slot]
		if p == null: continue
		if slot == 6 or not match.eliminated[slot]:
			p.think(now_ms)
			AiResignation.after_think(p, match)            # setup rows: 0x4fa120's last step, 0x4fc5a0 (AI Resignation)
		return

func dispose() -> void:
	for p in players:
		if p != null: p.dispose()
	players = [null, null, null, null, null, null, null]

## The per-player controller slot of SkirmishMatch.controllers: every computer player's slot drives the one shared manager
## (its own timer makes repeated calls at the same time harmless).
class Controller:
	var manager
	func _init(shared) -> void:
		manager = shared
	func update(now_ms: int, match) -> void:
		if manager != null: manager.update(now_ms, match)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the round-robin state and each computer player's state (the players themselves are made again by
## start_skirmish for the same setup; the neutral entry has no state).
func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, ["players"])
	s["players"] = players.map(func(p): return p.save_state(refs) if p != null and p.has_method("save_state") else null)
	return s

func load_state(state: Dictionary, refs) -> void:
	preload("res://simulation/save_game.gd").restore(self, state, ["players"])
	for i in mini(players.size(), state.players.size()):
		if players[i] != null and players[i].has_method("load_state") and state.players[i] != null:
			players[i].load_state(state.players[i], refs)
