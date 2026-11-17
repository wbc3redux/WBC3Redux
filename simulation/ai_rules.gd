extends RefCounted
## The computer player's self-contained formulas (milestone 10b, AI_RESEARCH.md). Every function here is Emulated: it mirrors
## a model of tools/test_ai.py that matches the original x86 on all cases of tests/ai_fixtures.json (tests/test_ai.gd).
## Difficulty (0x708fa4 + player * 0x2c, TXT_AI_LEVELS): 0 Passive, 1 Squire, 2 Knight, 3 Lord, 4 Prince, 5 Warlord,
## 6 Emperor, 7 Rampant.

const PASSIVE := 0
const RAMPANT := 7
const NAMES := ["Passive", "Squire", "Knight", "Lord", "Prince", "Warlord", "Emperor", "Rampant"]
# 0x4ffab0, default profile: per category bit, difficulty 1..6.
const CATEGORY_PCT := {1: [10, 30, 50, 90, 150, 210], 2: [10, 20, 40, 60, 100, 150], 4: [15, 35, 70, 140, 280, 560],
	8: [10, 35, 70, 140, 280, 560], 0x10: [10, 30, 60, 120, 240, 480], 0x20: [0, 35, 70, 140, 280, 560], 0x40: [10, 30, 60, 85, 120, 150]}
const PACING_DELAY := {1: 15000, 2: 10000, 3: 7000, 4: 5000, 5: 2500, 6: 1000}      # 0x4ff400, default 6000
const INCOME_CAP := {1: 20, 2: 30, 3: 40, 4: 70, 5: 100}                           # 0x4ffee0, Emperor none, default 35
const ENEMY_BASE_HUMAN := [0, -5, -5, 20, 40, 75, 250, 50]                          # 0x60f2e8 [my difficulty]
const ENEMY_BASE_COMPUTER := [0, 25, 15, -15, -30, -60, -125, -5]                   # 0x60f2f8 [their difficulty]
const PRICE_DISCOUNT := [0, 0, 0, 2, 5, 10, 20, 0]                                  # 0x40b6b0 with a living hero
const GROUP_SHARE := {1: 40, 2: 60, 3: 80, 4: 100, 5: 130, 6: 160}                  # 0x4f3520, default 50
const GROUP_MIN := [10, 4, 6, 7, 15, 6]                                             # default profile +0x20c8
const GROUP_MAX := [12, 5, 8, 10, 17, 9]                                            # default profile +0x20e0
const HUMAN_FOCUS := {1: 0, 2: 25, 3: 50, 4: 80, 5: 90, 6: 100}                     # 0x4f4e30
const FAST_RESEARCH := ["AADR", "AADU", "AADW", "AADB", "AADG", "AADC", "ATHX", "ATDX", "ATEX", "ATKX", "ATWX", "ATAX", "ATOX",
	"ATBX", "ATMX", "ATFX", "ATVX", "ATUX"]
# Read (AI_RESEARCH.md section 4), not emulated:
const DESIRED_FACTOR := {1: 40, 2: 60, 3: 100, 4: 140, 5: 180, 6: 250}              # 0x4fc9a0, other 120
const RESEARCH_TIME_PCT := {4: 90, 5: 80, 6: 70}                                    # 0x52e1d0 R/P time, other 100
const BUILDING_COMBAT := {1: -2, 2: 0, 3: 1, 4: 2, 5: 3, 6: 5}                      # 0x52ae70

static func tdiv(a: int, b: int) -> int:
	var q: int = absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q

static func s16(v: int) -> int:
	v = v & 0xffff
	return v - 0x10000 if v >= 0x8000 else v

static func s32(v: int) -> int:
	v = v & 0xffffffff
	return v - 0x100000000 if v >= 0x80000000 else v

## 0x4ffab0. `custom` = [units, research, b20, b40, switch] profile bytes, or null for the default profile.
static func category_pct(category: int, difficulty: int, custom = null) -> int:
	if custom != null and not (custom is Array and custom.is_empty()):
		var c: Array = custom
		match category:
			1: return int(c[0]) * 125 * 2 / 100
			2: return int(c[1]) * 75 * 2 / 100
			4: return int(c[0]) * 65 * 2 / 100
			8: return int(c[1])
			0x10: return int(c[4]) * 75 * 2 / 100
			0x20: return int(c[2])
			0x40: return int(c[3]) * 75 * 2 / 100
		return 0xffff
	if not CATEGORY_PCT.has(category): return 60
	if difficulty < 1 or difficulty > 6: return 0xffff
	return int(CATEGORY_PCT[category][difficulty - 1])

static func pacing_delay(difficulty: int) -> int:
	return int(PACING_DELAY.get(difficulty, 6000))

## 0x4ffee0: level weight + workers, capped by difficulty.
static func income(lane: int, weight: int, workers: int, difficulty: int) -> int:
	if lane < 0 or lane > 3: return 0
	var total := weight + workers
	if difficulty == 6: return total
	return mini(total, int(INCOME_CAP.get(difficulty, 35)))

## 0x4fb330: lanes G, S, M, C; one blocks when its income metric is below 8 and the stock is below the price.
static func afford(stock: Array, cost: Array, mines: Array, difficulty: int) -> bool:
	for lane in [0, 3, 1, 2]:
		if income(lane, int(mines[lane][0]), int(mines[lane][1]), difficulty) < 8 and int(stock[lane]) < int(cost[lane]): return false
	return true

## 0x4f8600 over list entries [id, count, pending, timer, cooldown] (entries are changed in place: an unset cooldown
## becomes 50000). `owned_buildings` counts the player's buildings without walls and towers.
static func cooldown_gate(item: String, now: int, buildings: Array, units: Array, research: Array) -> bool:
	var total := 0
	for b in buildings:
		if not (String(b[0]).substr(1, 1) in ["R", "W"]): total += int(b[1]) + int(b[2])
	if total < 3: return true
	var list: Array = buildings if item.begins_with("B") else (units if item.begins_with("A") else (research if item[0] in ["R", "P"] else []))
	for e in list:
		if e[0] != item: continue
		if int(e[4]) == -1:
			if item.begins_with("B") and item.substr(1, 1) == "K": return false
			e[4] = 50000
			return true
		return s32(int(e[3]) + int(e[4])) < now
	return false

## 0x4fe300 for one category. `want` rows [id, priority, cost[4], categories]; the three dictionaries map id -> [timer,
## cooldown] for the building, unit and research lists and are updated in place (an id is looked up by its first letter:
## B buildings, A units, R/P research; "AAD?" research ids therefore find no unit entry); `mines` per lane [weight, workers].
static func pacing(category: int, difficulty: int, mines: Array, want: Array, buildings: Dictionary, units: Dictionary, research: Dictionary, custom = null):
	var rows: Array = want.filter(func(w): return int(w[3]) & category)
	var sums := [0, 0, 0, 0]
	for w in rows:
		for lane in 4:
			if s16(int(w[2][lane])) > 0: sums[lane] += s16(int(w[1]))
	var pct := s16(category_pct(category, difficulty, custom))
	for w in rows:
		var id: String = w[0]
		if id == "MR00": continue
		var priority: int = int(w[1])
		var slowest := 0
		if priority == 0: slowest = 10000 * 4000
		else:
			for lane in 4:
				var t := tdiv(int(w[2][lane]) * int(sums[lane]), tdiv(income(lane, int(mines[lane][0]), int(mines[lane][1]), difficulty) * pct, 100) * priority + 1)
				slowest = t if lane == 0 else maxi(slowest, t)
			slowest *= 4000
		var source: Dictionary = buildings if id[0] == "B" else (units if id[0] == "A" else research)
		if not source.has(id) or not (id[0] in ["B", "A", "P", "R"]): continue
		var entry: Array = source[id]
		if id[0] in ["B", "A"]:
			if int(entry[1]) == 0 or slowest < int(entry[1]): entry[1] = slowest
		else:
			if int(entry[1]) == 0 or slowest < int(entry[1]):
				if id in FAST_RESEARCH:
					match difficulty:
						1: pass
						2: slowest = slowest >> 1
						3: slowest = tdiv(slowest, 3)
						_: slowest = slowest >> 2
				entry[1] = slowest

## B1-5 (Emulated, tools/emulate_ai_batch1.py -> tests/ai_batch1_fixtures.json): the Undead class 0x50b1a0 replaces the
## pacing (vtable +0x18 = 0x50b1f0 -> 0x50b2c0 per category) and differs from 0x4fe300 in three ways: in category 1 a tree
## type is priced by its whole chain from a Skeleton (`chain`, undead_chain over 0x40b6b0(type, 0, player)); every lane
## term is one higher; the dragon / titan division applies to the unit entries (FAST_UNITS, fourteen ids). After category 1,
## `advancement_flow` lets the tree's cooldowns flow down to the sources.
const FAST_UNITS := ["AADR", "AADU", "ATHX", "ATDX", "ATEX", "ATKX", "ATWX", "ATAX", "ATOX", "ATBX", "ATMX", "ATFX", "ATVX", "ATUX"]
const TREE := ["AUIX", "AUJX", "AUKX", "AUXX", "AULX", "AUMX", "AUAX"]
const CHAIN := [["AUKX", "AUIX"], ["AUJX", "AUIX"], ["AUXX", "AUKX"], ["AULX", "AUJX"], ["AUMX", "AUJX"], ["AUAX", "AULX"]]
const FLOW := [["AUAX", "AULX"], ["AULX", "AUJX"], ["AUMX", "AUJX"], ["AUXX", "AUKX"], ["AUJX", "AUIX"], ["AUKX", "AUIX"]]

## The cumulative prices 0x50b2c0 builds in category 1 from `prices` (type -> [G M C S] of 0x40b6b0(type, 0, player)).
static func undead_chain(prices: Dictionary) -> Dictionary:
	var out := {}
	for t in TREE: out[t] = (prices.get(t, [0, 0, 0, 0]) as Array).map(func(v): return int(v))
	for pair in CHAIN:
		var a: Array = out[pair[0]]
		var b: Array = out[pair[1]]
		for lane in 4: a[lane] = s16(int(a[lane]) + int(b[lane]))
	return out

static func pacing_undead(category: int, difficulty: int, mines: Array, want: Array, buildings: Dictionary, units: Dictionary, research: Dictionary, chain: Dictionary, custom = null):
	var rows: Array = want.filter(func(w): return int(w[3]) & category)
	var sums := [0, 0, 0, 0]
	for w in rows:
		for lane in 4:
			if s16(int(w[2][lane])) > 0: sums[lane] += s16(int(w[1]))
	var pct := s16(category_pct(category, difficulty, custom))
	for w in rows:
		var id: String = w[0]
		if id == "MR00": continue
		var priority: int = s16(int(w[1]))
		var price: Array = w[2]
		if category == 1 and id != "AUIX" and chain.has(id): price = chain[id]
		var slowest := 0
		for lane in 4:
			var t := tdiv(s16(int(price[lane])) * int(sums[lane]), tdiv(income(lane, int(mines[lane][0]), int(mines[lane][1]), difficulty) * pct, 100) * priority + 1)
			if priority == 0: t = 1000 if lane == 2 else 10000
			slowest = t + 1 if lane == 0 else maxi(slowest, t + 1)
		slowest = s32(slowest * 4000)
		var source: Dictionary = buildings if id[0] == "B" else (units if id[0] == "A" else research)
		if not source.has(id) or not (id[0] in ["B", "A", "P", "R"]): continue
		var entry: Array = source[id]
		if int(entry[1]) != 0 and not slowest < int(entry[1]): continue
		if id[0] == "A" and id in FAST_UNITS:
			match difficulty:
				1: pass
				2: slowest = slowest >> 1
				3: slowest = tdiv(slowest, 3)
				_: slowest = slowest >> 2
		entry[1] = slowest

## 0x50b2c0 after category 1: for each tree edge (target, source) whose two unit-list cooldowns are set (not -1), the
## source's becomes 3000000 / (3000000 / source + 3000000 / target) (each at least 1). A type missing from the unit list
## uses list entry 0 (0x50bdb0 leaves its index byte 0). `order` is the unit list order; `units` id -> [timer, cooldown].
static func advancement_flow(units: Dictionary, order: Array):
	if order.is_empty(): return
	for pair in FLOW:
		var a: Array = units[order[maxi(0, order.find(pair[0]))]]
		var b: Array = units[order[maxi(0, order.find(pair[1]))]]
		if int(a[1]) == -1 or int(b[1]) == -1: continue
		var total: int = tdiv(3000000, maxi(1, int(b[1]))) + tdiv(3000000, maxi(1, int(a[1])))
		b[1] = tdiv(3000000, maxi(1, total))

## 0x4fead0 (Emulated, tools/emulate_research.py, milestone M-1): the category-2 want builder over the research list in
## its order (0x4fd140: the race's [DEPENDENCIES] research rows in file order, the Knights' Crusade I first). `entries`:
## [{id, priority (+8), have (+0xa), ordered (+0xb), eligible (+0xc)}]; `listed` = the id of the first category-2 node or
## "". A listed node stays while its entry is not had and eligible (keep); otherwise it is removed and the first entry
## that is eligible, not had and not ordered is offered at its priority (the caller asks the affordability gate 0x4fb330,
## then 0x4fb400 inserts it). Eligible (0x4f7f60) holds no stock or job test, so an unaffordable or never-chosen item
## keeps its node and every later research waits behind it.
static func research_pick(listed: String, entries: Array) -> Dictionary:
	if listed != "":
		for e in entries:
			if String(e.id) == listed:
				if not bool(e.have) and bool(e.eligible): return {"keep": true, "remove": "", "offer": ""}
				break
	for e in entries:
		if bool(e.eligible) and not bool(e.have) and not bool(e.ordered):
			return {"keep": false, "remove": listed, "offer": String(e.id), "priority": int(e.priority)}
	return {"keep": false, "remove": listed, "offer": ""}

## 0x4fb100. `arm_0x1c` maps unit id -> ARM word +0x1c (20 when missing).
static func demand(want: Array, mines: Array, difficulty: int, arm_0x1c: Dictionary) -> Array:
	var weights := [0, 0, 0, 0]
	for w in want:
		var id: String = w[0]
		for lane in 4:
			var add := 0
			if id.begins_with("A"): add = tdiv(int(w[2][lane]) * int(w[1]), int(arm_0x1c.get(id, 20)))
			else: add = ((int(w[2][lane]) * int(w[1])) & 0xffffffff) >> 8
			weights[lane] = s16(weights[lane] + add)
	var top: int = weights.max()
	if top != 0:
		for lane in 4:
			weights[lane] = s16(tdiv(weights[lane] * 100, top))
			if income(lane, int(mines[lane][0]), int(mines[lane][1]), difficulty) < 4: weights[lane] = s16(weights[lane] + 105)
	return weights

## 0x4fa5b0. players[i] = {active, computer, difficulty, start [x, y], eliminated, objects}; relations[a][b] != 0 allied;
## hate (Array, changed in place); `roll` = the neutral slot's 1d(n) - 1 result. Returns the main enemy or -1.
static func main_enemy(me: int, players: Array, relations: Array, hate: Array, adjust: Array, previous: int, roll: int = 0) -> int:
	if me == 6:
		var alive: Array = []
		for p in 6:
			if players[p].active and not players[p].eliminated: alive.append(p)
		return alive[roll] if not alive.is_empty() else previous
	var mine: Dictionary = players[me]
	var best := -1
	var best_score := -1000
	for them in 6:
		var q: Dictionary = players[them]
		if them == me or not q.active or q.eliminated or relations[them][me] or not q.objects: continue
		if int(hate[them]) != 0: hate[them] = int(hate[them]) - (2 if them == previous and int(hate[them]) > 1 else 1)
		var base := 0
		var shift := 2
		if q.computer:
			base = ENEMY_BASE_COMPUTER[int(q.difficulty)]
			shift = {2: 3, 3: 4, 4: 5, 5: 6, 6: 8}.get(int(mine.difficulty), 2)
		else:
			base = ENEMY_BASE_HUMAN[int(mine.difficulty)]
		var distance: int = absi(int(q.start[1]) - int(mine.start[1])) + absi(int(q.start[0]) - int(mine.start[0]))
		var score: int = maxi(base + (int(hate[them]) >> shift) + int(adjust[them]) + (maxi(0, 300 - distance) >> 1), 1)
		if best_score < score:
			best = them
			best_score = score
	return best

## 0x4f3520 / 0x4f7800: does a group of `kind` with `size` members launch? (Hero groups always, conversion at 1.)
static func launch_needed(kind: int, difficulty: int, sizes: Array = []) -> int:   # sizes: a CustomAI profile's min + max (AI-4)
	if kind == 7: return 1
	var minimum: int = (sizes if sizes.size() == 12 else GROUP_MIN + GROUP_MAX)[kind] if kind < 12 else 12   # kind 6 reads past the minimums (12)
	return tdiv(int(GROUP_SHARE.get(difficulty, 50)) * minimum, 100)

static func launches(kind: int, size: int, hero: bool, difficulty: int, sizes: Array = []) -> bool:
	return hero or size >= launch_needed(kind, difficulty, sizes)

## 0x4f4e30: the human focus threshold (default: the main enemy's index, as the original reads it).
static func human_focus(difficulty: int, main: int) -> int:
	return int(HUMAN_FOCUS.get(difficulty, main))

## 0x40b6b0 with a living hero of a computer player: p * 100 / (100 + d), at least 1 for a non-zero lane.
static func discount(difficulty: int) -> int:
	return PRICE_DISCOUNT[difficulty] if difficulty >= 0 and difficulty < 8 else 0

static func discounted(price: Array, difficulty: int) -> Array:
	var d := discount(difficulty)
	return price.map(func(v): return maxi(1, tdiv(int(v) * 100, d + 100)) if int(v) > 0 else int(v))

# ============================================================================== review upgrades (REVIEW_SKIRMISH_AI.md, Emulated)

## 0x4fc280 over the refreshed mine list (0x4fb680): rows {owned, exhausted, level, lane, workers}. Returns per lane
## [level weight, workers, slots]. Level weight = research + 2/4/8 (1 when exhausted); exhausted mines add no workers or
## slots; weights 4..8 then get 6 added.
static func census_lanes(rows: Array, research: int = 0) -> Array:
	var lanes := [[0, 0, 0], [0, 0, 0], [0, 0, 0], [0, 0, 0]]
	for n in rows:
		if not n.owned: continue
		var weight := 1
		if not n.exhausted:
			match int(n.level):
				1: weight = research + 2
				2: weight = research + 4
				3: weight = research + 8
		var lane: Array = lanes[int(n.lane)]
		lane[0] = (lane[0] + weight) & 0xff
		if not n.exhausted:
			lane[1] = (lane[1] + int(n.workers)) & 0xff
			lane[2] = (lane[2] + 8) & 0xff
	for lane in lanes:
		if lane[0] > 3 and lane[0] < 9: lane[0] += 6
	return lanes

## 0x587a30 as the emulated table holds it: the first building (in name order) whose nine production slots list the unit.
static func producer_of(unit: String, production: Dictionary) -> String:
	var names: Array = production.keys()
	names.sort()
	for name in names:
		var slots: Array = production[name].get("slots", [])
		for i in mini(9, slots.size()):
			if slots[i].get("id") == unit: return name
	return ""

## 0x4fcc10: chains of building ids ending in consecutive digits from '0' (BKK0, BKK1, ...) share their total.
static func _chain_adjust(ids: Array, values: Array) -> Array:
	var starts: Array = []
	var ends: Array = []
	var inside := false
	var last := -1
	var list: Array = ids.duplicate()
	list.append(null)
	for i in list.size():
		var name = list[i]
		if name == null:
			if inside: ends.append(i - 1)
			break
		var c: int = String(name).unicode_at(3)
		if inside:
			if not (c >= 48 and c <= 57):
				ends.append(i - 1)
				inside = false
				last = -1
				continue
			if c != last + 1:
				ends.append(i - 1)
				inside = false
			else:
				last = c
				continue
		if c == 48:
			starts.append(i)
			inside = true
			last = c
	var best_index := -1
	for k in mini(starts.size(), ends.size()):
		var s: int = starts[k]
		var e: int = ends[k]
		var best := 0
		var total := 0
		for j in range(s, e + 1):
			if values[j] != -1:
				if best <= values[j]:
					best = values[j]
					best_index = j
				total += values[j]
		if best_index != -1 and s <= e:
			for j in range(e, s - 1, -1):
				if j == best_index: values[j] = total
				elif values[j] != -1: values[j] = tdiv(values[j] * total, best)
		var previous := -1
		for j in range(e, s - 1, -1):
			var current: int = values[j]
			if previous != -1 and current < previous:
				values[j] = previous
				current = previous
			previous = current
	return values

## 0x4fc9a0 + 0x4fcc10. buildings [id, valid, enabled], units [id, priority, available]; `special` is the list index that
## also sets a building's availability flag. Returns the desired count per building, -1 = none wanted.
const SHARE_TO_BAGR := {"AUJX": "BAGR", "AUKX": "BAGR", "AUXX": "BAGR", "AUMX": "BAGR", "AULX": "BAGR", "AUAX": "BAGR"}
static func desired_counts(difficulty: int, buildings: Array, units: Array, special: int, production: Dictionary) -> Array:
	var factor: int = DESIRED_FACTOR.get(difficulty, 120)
	var values: Array = []
	var everything := 0
	var ids: Array = buildings.map(func(b): return String(b[0]))
	# Performance (P-1): each unit's producer once per call instead of once per building (the table does not change here).
	# B3-3 (BATCH3_RESEARCH.md R9, Read: decompile 166812): 0x4fc9a0 charges AUJX, AUKX, AUXX, AUMX, AULX and AUAX to BAGR for
	# every race (no race test) instead of 0x4f7f20's producer: the Dark Dwarves' Wraiths and Shadows add nothing to BPAH's share.
	var producers: Array = units.map(func(u): return SHARE_TO_BAGR.get(String(u[0]), producer_of(String(u[0]), production)))
	for b in buildings:
		if not bool(b[1]) or not bool(b[2]):
			values.append(-1)
			continue
		var flag := false
		var trained := 0
		var counted := 0
		for index in units.size():
			var u: Array = units[index]
			if int(u[1]) == -1 or producers[index] != String(b[0]): continue
			if bool(u[2]) or index == special: flag = true
			trained += int(u[1])
			if flag: counted += int(u[1])
		values.append(counted if counted >= 1 else -1)
		everything += trained
	values = _chain_adjust(ids, values)
	var out: Array = []
	for i in ids.size():
		if values[i] == -1: out.append(-1)
		else: out.append(s16(tdiv(values[i] * factor, everything * 10) + (2 if ids[i] in ["BKE0", "BKW0", "BKT0"] else 1)))
	return out

static func _s8(v: int) -> int:
	v = v & 0xff
	return v - 0x100 if v >= 0x80 else v

static func _cheb(a, b) -> int:
	return maxi(absi(int(a[0]) - int(b[0])), absi(int(a[1]) - int(b[1])))

## 0x4f5e90: a target's priority in the per-enemy list. c = {kind (1 building / 0 unit), code, cell, state, unfinished,
## value_0x92, flag (units: the enemy owns a building), home, demand [G M C S], me, players [{active, start}], relations}.
static func target_priority(c: Dictionary) -> int:
	if int(c.state) == 8: return 0
	var code: String = c.code
	if int(c.kind) == 1:
		if c.unfinished: return 0
		var k := code.substr(1, 1)
		var value := 0
		if k == "T": value = 150
		elif k == "L": return 1
		elif k == "R":
			var lane: int = {"G": 0, "M": 2, "S": 1, "C": 3}.get(code.substr(2, 1), int(c.flag))
			var shift: int = (code.unicode_at(3) - 0x30) & 0x1f
			var demand := {0: int(c.demand[0]), 1: int(c.demand[3]), 2: int(c.demand[1]), 3: int(c.demand[2])}
			value = ((int(demand[lane]) >> 1) << shift) + 10 if demand.has(lane) else (lane << shift) + 10
		elif code.substr(0, 1) == "B" and k == "M": value = 250 if code.substr(2, 2) == "FL" else 25
		elif k == "K": value = (_s8(code.unicode_at(3)) - 0x2f) * 40
		elif k == "W": value = 40 if code.substr(2, 1) == "T" else 10
		else: value = 25
		value += maxi(0, 500 - 2 * _cheb(c.cell, c.home))
		if k == "R":
			for p in c.players.size():
				var q: Dictionary = c.players[p]
				if not q.active or c.relations[int(c.me)][p]: continue
				var d := _cheb(q.start, c.cell)
				if d < 15: value -= 200
				elif d < 30: value -= 100
				elif d < 60: value -= 60
				elif d > 80: value += 40
		return s16(value)
	if int(c.kind) == 0 and not c.flag:
		var d := _cheb(c.cell, c.home)
		return (maxi(0, 256 - d) >> 3) + (int(c.value_0x92) >> 1) + 30
	return 0

# -------------------------------------------------------------------------------------------- tech step (A-2, Emulated)
## The tech walk's unit order +0x3ac6 (tests/tech_step_fixtures.json, tools/emulate_tech_step.py). `needs[i]` = {"b": building
## list indexes, "r": research list indexes} that unit i needs (the enabling matrix of 0x4fd1b0 / 0x4fd2f0); `flags[j]` =
## building j's +0x80 (0x4f7ba0: level digit 1..9 or in a construction menu); `expensive[j]` = building j is one of the
## command buildings +0x3b90..+0x3ba0 (0x4fe7f0: the last BK?0..BK?4 of each level in the building list); `priorities[i]`
## = unit +6. 0x4ff5f0 (+0x3b02): the Peasant first, then the other units by ascending prerequisite cost (each needed
## building 1, a command building 10, each needed research 1; first index on ties); a unit that needs a building whose
## +0x80 is 0 is left out. 0x4fc7e0 (+0x3ac6): the same list stably sorted by descending priority (priority -1 left out).
static func tech_order(peasant: int, needs: Array, flags: Array, expensive: Array, priorities: Array) -> Dictionary:
	var n := mini(needs.size(), 30)
	var score: Array = []
	for i in n:
		var s := 0
		if i == peasant: s = 1
		else:
			for j in flags.size():
				if not (j in needs[i].b): continue
				if not bool(flags[j]):
					s = -1
					break
				s += 10 if bool(expensive[j]) else 1
			if s != -1: s += needs[i].r.size()
		score.append(s)
	var by_cost: Array = [peasant]
	var picked := {peasant: true}
	while by_cost.size() < n:
		var best := -1
		for i in n:
			if int(score[i]) == -1 or picked.has(i): continue
			if best == -1 or int(score[i]) < int(score[best]): best = i
		if best == -1: break
		picked[best] = true
		by_cost.append(best)
	var by_priority: Array = []
	var taken := {}
	while by_priority.size() < by_cost.size():
		var best := -1
		for i in by_cost:
			if int(priorities[i]) == -1 or taken.has(i): continue
			if best == -1 or int(priorities[best]) < int(priorities[i]): best = i
		if best == -1: break
		taken[best] = true
		by_priority.append(best)
	return {"by_cost": by_cost, "order": by_priority}

## 0x4ff0d0 after its node test: walks `order` (unit indexes, +0x3ac6). For the unit at walk position k: a needed building
## with no count and no pending is missing only when building k's +0x80 flag is set (sic: the walk position indexes the
## building list); an available one is a candidate scoring 150, 220 for the Peasant's producer (first wins ties). A needed
## research neither had nor ordered is missing; an eligible one is a candidate at 140 (never above a building). Returns
## {"offer": building or research id ("" none), "stop": the unit index stored at +0x3bb4, -1 at the end of the list}: a
## candidate ends the walk, so does a unit with something missing and no candidate; otherwise the walk goes on.
## buildings[j] = {id, have (count + pending), available, flag}; research[r] = {id, had, ordered, eligible}.
static func tech_step(order: Array, needs: Array, buildings: Array, research: Array, peasant_producer: String) -> Dictionary:
	for k in mini(order.size(), 30):
		var i: int = order[k]
		var missing := false
		var best := ""
		var best_score := -1
		var flag_k: bool = k < buildings.size() and bool(buildings[k].flag)
		for j in buildings.size():
			if not (j in needs[i].b) or int(buildings[j].have) != 0 or not flag_k: continue
			missing = true
			if not bool(buildings[j].available): continue
			var s := 220 if String(buildings[j].id) == peasant_producer else 150
			if best == "" or best_score < s:
				best = String(buildings[j].id)
				best_score = s
		for r in research.size():
			if not (r in needs[i].r) or bool(research[r].had) or bool(research[r].ordered): continue
			missing = true
			if bool(research[r].eligible) and (best == "" or best_score < 140):
				best = String(research[r].id)
				best_score = 140
		if best != "": return {"offer": best, "stop": i}
		if missing: return {"offer": "", "stop": i}
	return {"offer": "", "stop": -1}

## 0x4ff0d0's node test: a listed category-4 node stays while it is a building ('B') whose entry is available with count 0,
## or a research 'P' whose entry is eligible (+0xc) and not had (+0xa); an 'R' node or any other is removed.
static func tech_keep(id: String, building, research_entry) -> bool:
	if id.begins_with("B"): return building != null and bool(building.available) and int(building.count) == 0
	if id.begins_with("P"): return research_entry != null and bool(research_entry.eligible) and not bool(research_entry.had)
	return false

# -------------------------------------------------------------------------------------------- monster mode (victory options)
## SKIRMISH_RESEARCH.md "Victory options and the computer player". Rampant (7) computer slots and the neutral slot 6 run
## 0x4fa120's monster branch; Pitched Battle (option 11) and No Building make every computer slot with a non-zero level
## Rampant (0x4eaca0 / 0x4de740). **Emulated** (tools/emulate_monster_ai.py -> tests/monster_ai_fixtures.json).
const CAPTURE_THE_FLAG := 12             # 0x70ae12 == 0xc: the only victory-option test inside the computer player's choices
const MONSTER_SLOTS := 3                 # +0x22f4 / +0x22f8 / +0x22fc

## 0x4fa990: the score of one object of the main enemy's list for target slot `slot` (0 ground units, 1 movement type 1,
## 2 movement type 2; buildings fit every slot), or null when it does not qualify. o = {kind (0 unit, 1 building, other),
## code, cell [x, y], state (8 = leaving play), hidden (+0x30), sprite (+0x24 set), movement (ARM +5)}.
## Unit 300; building 150, a wall (B W, third letter not T, 0x4fe790) 0, under Capture the Flag a BMFL flag -500; plus
## (map height - Chebyshev(home, cell)) >> 1 plus max(0, 70 - strength). `strength` is 0x509980's value for the AI's own
## player: the code shifts the cell right by 4 twice (0x4fab0a and 0x509991), so on every map up to 256 cells it reads
## block 0 of the 0x5095a0 grid for every object: the same term for the whole pass (Emulated).
static func monster_score(o: Dictionary, slot: int, home, height: int, option: int, strength: int):
	if not bool(o.get("sprite", true)) or int(o.get("state", 0)) == 8 or bool(o.get("hidden", false)): return null
	var base := 0
	var code := String(o.get("code", ""))
	match int(o.kind):
		0:
			var m := int(o.get("movement", 0))
			var fits: bool = (m != 1 and m != 2) if slot == 0 else (m == slot)
			if not fits: return null
			base = 300
		1:
			base = 0 if code.length() >= 3 and code[0] == "B" and code[1] == "W" and code[2] != "T" else 150
			if code == "BMFL" and option == CAPTURE_THE_FLAG: base = -500
	var d := _cheb(o.cell, home)
	return base + ((height - d) >> 1) + maxi(0, 70 - strength)

## 0x4fa990: the three target slots as indexes into `objects` (the main enemy's list, in list order), -1 for none. The
## first strictly highest score above -1 wins. main_enemy < 0 (+0x2308 == -1) clears all three.
static func monster_targets(objects: Array, main_enemy: int, home, height: int, option: int, strength: int) -> Array:
	var out: Array = [-1, -1, -1]
	if main_enemy < 0: return out
	for slot in MONSTER_SLOTS:
		var best := -1
		for i in objects.size():
			var s = monster_score(objects[i], slot, home, height, option, strength)
			if s != null and int(s) > best:
				best = int(s)
				out[slot] = i
	return out

## 0x4fa850: the target slot an idle unit (kind 0, state 3) of the Rampant player attacks, -1 for none. Nothing at all
## while slots 0 and 1 are both empty. Layers (ARM +0x100) 3: slot 0 or 1 by 1d2 - 1 (0x458e70(1, 2, -1)) when both are
## set, else the set one; 1 (ground only): slot 0; any other (2 air only, 0 none): slot 1. `die` returns the 1d2 - 1 roll.
static func monster_attack_slot(layers: int, has0: bool, has1: bool, die: Callable) -> int:
	if not has0 and not has1: return -1
	if layers == 3:
		if has0 and has1: return int(die.call())
		return 0 if has0 else 1
	if layers == 1: return 0 if has0 else -1
	return 1 if has1 else -1
