extends RefCounted
## Army setup points (skirmish setup session; SKIRMISH_RESEARCH.md "Army setup points"; Read unless noted). Tables in
## army_setup.json (tools/army_setup_data.py): the human's offers per race (0x444980), the computer's purchase table
## 0x6095d8 (Data), the unit costs ARM +0xca (Data) and the retinue medal terms 0x6095b0 (Data).
##
## * The setup's slider SBAR_H170 stores 0..50 points (0xa47a02; element range 0..50, Data); the skirmish saves it as
##   ArmyPoints with the other "Random Map Data" values on Okay (0x450760) unless the victory is Pitched Battle.
## * 0x417730: the human's budget = points + the handicap term (handicap on and the local hero's level below the highest
##   setup level 0xa479c8: 0x603c9c[difference - 1], + 3 per level beyond 30); with a budget below 1 the match starts
##   at once (0x4179f0), else the army setup screen opens (0x440b40(1, budget)), which caps the budget at 100.
## * The screen (0x4417b0, callback 0x443890): left click on an offer adds one when spent + cost <= budget, right click
##   takes one back; Okay starts the match. 0x4406b0 then runs 0x445200 for every computer slot and places the human's
##   units, each at 0x4402d0's cell (start + 1d10 - 5 per axis, kept 5 cells inside the map) through the free-cell finder
##   0x43b4c0, after the heroes (0x43b550).
## * 0x445200 (computer): nothing below 1 point; p = points - 1 (halved, rounded up, for AI value 1 = Squire); the race's
##   first table entry always; then while p > 0: n = min(p, 8), r = 1d4 - 1, the up to four entries at
##   race * 128 + (n - 1) * 16 + r * 4, p -= n; at most 49 units. The computer does not use the handicap term.

const DATA_PATH := "res://simulation/army_setup.json"
const MAX_SLIDER := 50                 # SBAR_H170 range_max (Data)
const MAX_BUDGET := 100                # 0x440b40
const MAX_COMPUTER_UNITS := 49         # 0x445200: the list stops after 0x31 entries
const SQUIRE := 1                      # AI value 1 halves the computer's points
## 0x603c9c: the handicap term per level difference 1..30 (shorts, Data).
const HANDICAP := [1, 2, 3, 4, 5, 7, 9, 10, 12, 14, 15, 17, 19, 20, 22, 24, 26, 28, 30, 31, 32, 33, 34, 35, 36, 37, 38,
	39, 40, 41]

static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	return _data

## 0x444980: the unit types offered to a race (6..8 entries).
static func offers(race: int) -> Array:
	var all: Array = data().offers
	return all[race] if race >= 0 and race < all.size() else []

## ARM record +0xca.
static func cost(code: String) -> int:
	return int(data().cost.get(code, 0))

## 0x444940: a retinue unit's cost = its type's cost + the medal term.
static func retinue_cost(code: String, medal: int) -> int:
	var medals: Array = data().medal
	return cost(code) + int(medals[clampi(medal, 0, medals.size() - 1)])

## 0x417730: the handicap term for the local hero (0 unless handicap is on and another setup level is higher).
static func handicap_term(handicap: bool, local_level: int, setup_levels: Array) -> int:
	var highest := 0
	for level in setup_levels: highest = maxi(highest, int(level))
	if not handicap or local_level >= highest: return 0
	var difference := highest - local_level
	var extra := 0
	var index := difference - 1
	if index > 29:
		index = 29
		extra = (difference - 30) * 3
	return int(HANDICAP[index]) + extra

## 0x417730 + 0x440b40: the human's budget on the army setup screen (0 = the screen is skipped).
static func human_budget(points: int, handicap: bool, local_level: int, setup_levels: Array) -> int:
	var total := points + handicap_term(handicap, local_level, setup_levels)
	return 0 if total < 1 else mini(total, MAX_BUDGET)

## 0x443890 left click: whether one more of `code` fits.
static func can_buy(spent: int, budget: int, code: String) -> bool:
	return spent + cost(code) <= budget

static func spent(counts: Dictionary) -> int:
	var total := 0
	for code in counts: total += cost(code) * int(counts[code])
	return total

## 0x445200: the computer's units. `rng` is the match generator (CombatRng: roll(count, sides, bonus)).
static func computer_purchase(points: int, race: int, ai_value: int, rng) -> Array:
	if points < 1 or race < 0 or race >= 16: return []
	var table: Array = data().computer[race]
	var p := points - 1
	if ai_value == SQUIRE: p = (p + 1) / 2
	var out: Array = [String(table[0])]
	while p > 0:
		var n := mini(p, 8)
		var r: int = rng.roll(1, 4, -1)
		for k in 4:
			var code := String(table[(n - 1) * 16 + r * 4 + k])
			if code == "": continue
			out.append(code)
			if out.size() > MAX_COMPUTER_UNITS:
				p = 0
				break
		p -= n
	return out

## 0x4402d0: the cell a bought unit is placed from (the free-cell finder runs on it).
static func placement_cell(start: Vector2i, map_size: Vector2i, rng) -> Vector2i:
	var x: int = start.x + rng.roll(1, 10, -5)
	var y: int = start.y + rng.roll(1, 10, -5)
	x = map_size.x - 5 if x > map_size.x - 5 else maxi(x, 5)
	y = map_size.y - 5 if y > map_size.y - 5 else maxi(y, 5)
	return Vector2i(x, y)
