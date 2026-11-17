extends RefCounted
## The match random generator: 0x458ef0 (two 32-bit words, end-around-carry sum, high 16 bits returned)
## behind 0x458e70 (sum of dice). Emulated against the executable (tests/combat_fixtures.json, "rng").
## The match seeds only the first word (0x458f90 from the game setup, 0x4e0360); the second keeps its
## static value. A skirmish seed is created by the setup screen and is not recovered, so the rebuild takes
## both words from the caller.
var first := 0   # 0x60c3f0
var second := 0  # 0x60c3f4
var calls := 0

func _init(seed_first: int = 0, seed_second: int = 0):
	seed_state(seed_first, seed_second)

func seed_state(seed_first: int, seed_second: int):
	first = seed_first & 0xffffffff
	second = seed_second & 0xffffffff
	calls = 0

## 0x458ef0
func next_raw() -> int:
	var sum := (second + first) & 0xffffffff
	if sum < first or sum < second: sum = (sum + 1) & 0xffffffff
	second = first
	first = sum
	return sum >> 16

## 0x458e70(count, sides, bonus): `count` dice of 1..sides plus bonus. Each die is
## (raw * sides) / 0xffff + 1, at least 1 and at most sides. count < 1 returns the bonus without a draw.
func roll(count: int, sides: int, bonus: int = 0) -> int:
	if count < 1: return bonus
	var total := 0
	for i in count:
		var value: int = (next_raw() * sides) / 0xffff + 1
		if value == 0: value = 1
		if value > sides: value = sides
		total += value
		calls += 1
	return total + bonus

func state() -> Array:
	return [first, second]

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd).
func save_state(_refs = null) -> Dictionary:
	return preload("res://simulation/save_game.gd").capture(self)

func load_state(state: Dictionary, _refs = null):
	preload("res://simulation/save_game.gd").restore(self, state)
