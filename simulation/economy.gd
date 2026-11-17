extends RefCounted
## Executable-backed economy kernel; see ECONOMY_RESEARCH.md for integration gates.
## Resources always use original record order: gold, metal, crystal, stone.
const Entity = preload("res://simulation/entity_state.gd")
signal resources_changed(owner: int, before: Array, after: Array)
signal capacity_changed(owner: int, capacity: Array)
signal mine_changed(entity_id: int, reserve: int, exhausted: bool)

var entities: Dictionary = {}
var mines: Dictionary = {}
var stockpiles: Dictionary = {}
var capacities: Dictionary = {}
var pending: Dictionary = {}
var local_owner: int
var next_cycle_ms: int = 0
var last_update_ms: int = -1

func _init(player: int):
	local_owner = player

func add_player(player: int, initial: Array):
	assert(initial.size() == 4 and not stockpiles.has(player))
	for value in initial: assert(value >= 0)
	stockpiles[player] = initial.duplicate()
	capacities[player] = [1000, 1000, 1000, 1000]

func register_entity(entity: Entity) -> bool:
	if entities.has(entity.entity_id): return false
	entities[entity.entity_id] = entity
	return true

## base_rate is the resolved runtime +0x94/+0x96/+0x98/+0x9a value, NOT per second.
## Reserve and rate must come from original match initialization; no unlimited fallback.
func register_mine(entity: Entity, resource: int, base_rate: int, reserve: int) -> bool:
	if resource < 0 or resource > 3 or base_rate < 1 or reserve < 0: return false
	if entity.mine_level < 1 or entity.mine_level > 3: return false
	if not register_entity(entity): return false
	mines[entity.entity_id] = {"resource": resource, "rate": base_rate,
		"reserve": reserve, "exhausted": false}
	return true

func remove_entity(id: int):
	entities.erase(id)
	mines.erase(id)

func resources(player: int) -> Array:
	return stockpiles[player].duplicate()

func capacity(player: int) -> Array:
	return capacities[player].duplicate()

## 0x52aac0: maximum, not sum; 0x531f10 initializes all four lanes to 1000.
func refresh_capacity(player: int):
	var cap := 1000
	for entity in entities.values():
		if entity.owner != player: continue
		var code: String = entity.original_type_id
		if code.length() == 4 and code[1] == "K" and code[3] in ["0", "1", "2", "3", "4"]:
			cap = maxi(cap, 1000 + int(code[3]) * 500)
	var result := [cap, cap, cap, cap]
	if result != capacities[player]:
		capacities[player] = result
		capacity_changed.emit(player, result.duplicate())

## 0x43e9b0: only nonzero lanes are touched. Positive rewards can trim an
## already over-cap lane; merely lowering capacity does not touch stock.
func credit(player: int, amount: Array):
	assert(amount.size() == 4)
	var before := resources(player)
	for resource in range(4):
		assert(amount[resource] >= 0)
		if amount[resource] != 0:
			stockpiles[player][resource] = mini(before[resource] + amount[resource], capacities[player][resource])
	if before != stockpiles[player]:
		resources_changed.emit(player, before, resources(player))

## Atomic spending is an integration API, not a claim about queue billing/cancellation.
func try_spend(player: int, cost: Array) -> bool:
	if cost.size() != 4: return false
	for resource in range(4):
		if cost[resource] < 0 or cost[resource] > stockpiles[player][resource]: return false
	var before := resources(player)
	for resource in range(4): stockpiles[player][resource] -= cost[resource]
	if before != stockpiles[player]: resources_changed.emit(player, before, resources(player))
	return true

## 0x52e1d0 for a computer player: the job is charged without a stock check; each lane clamps at zero (Read).
func debit_clamped(player: int, cost: Array):
	var before := resources(player)
	for resource in range(4): stockpiles[player][resource] = maxi(0, stockpiles[player][resource] - int(cost[resource]))
	if before != stockpiles[player]: resources_changed.emit(player, before, resources(player))

## Call once per original game update with absolute integer game milliseconds.
## Late updates catch up four-second calculation cycles; local distribution remains
## sixteen 250 ms installments relative to the current update (0x43e5b0).
func update(now_ms: int):
	assert(now_ms >= last_update_ms)
	last_update_ms = now_ms
	for player in pending.keys():
		var plan: Dictionary = pending[player]
		var amount := [0, 0, 0, 0]
		while plan.index < 16 and now_ms >= plan.start + (plan.index + 1) * 250:
			for resource in range(4):
				amount[resource] += int(plan.total[resource] * (plan.index + 1) / 16) - int(plan.total[resource] * plan.index / 16)
			plan.index += 1
		credit(player, amount)
	# Original deadline comparison is strict; zero is an uninitialized sentinel.
	if next_cycle_ms != 0 and now_ms <= next_cycle_ms: return
	var local_total := [0, 0, 0, 0]
	while next_cycle_ms == 0 or now_ms > next_cycle_ms:
		next_cycle_ms = (now_ms if next_cycle_ms == 0 else next_cycle_ms) + 4000
		for player in stockpiles:
			var total := _calculate(player)
			refresh_capacity(player)
			if player == local_owner:
				for resource in range(4): local_total[resource] += total[resource]
			else: credit(player, total)
	for resource in range(4):
		local_total[resource] = mini(local_total[resource], maxi(0, capacities[local_owner][resource] - stockpiles[local_owner][resource]))
	pending[local_owner] = {"start": now_ms, "index": 0, "total": local_total}

func _calculate(player: int) -> Array:
	var total := [0, 0, 0, 0]
	for id in mines:
		var entity: Entity = entities[id]
		if entity.owner != player: continue
		var mine: Dictionary = mines[id]
		var resource: int = mine.resource
		# 0x52aac0: base * 2 + garrison count; exhausted mines lose worker bonus.
		var amount: int = mine.rate * 2 + (0 if mine.exhausted else entity.worker_count)
		total[resource] += amount
		# Full stockpiles freeze depletion (old cap, sampled before recomputation).
		if stockpiles[player][resource] < capacities[player][resource]:
			mine.reserve = maxi(0, mine.reserve - (mine.rate * 2 + entity.worker_count))
			if mine.reserve == 0:
				mine.rate = 1
				mine.exhausted = true
			mine_changed.emit(id, mine.reserve, mine.exhausted)
	# B4-1 (BATCH4_RESEARCH.md E3, Emulated "income"): the rest of 0x531f10's vtable +0x34 walk: units (an Ancient Wisp + 4 crystal)
	# and the Magic Well (+ 2 gold, a gold producer below). other_income(player) -> {"income": [4], "producers": [4]}.
	var other: Dictionary = other_income.call(player) if other_income.is_valid() else {}
	if not other.is_empty():
		for resource in range(4): total[resource] += int(other.income[resource])
	# Milestone 13 (Read, 0x531f10): Income research. bonus = 0x6115c4[PIBX level] + 0x6115c4[PHLX level] (0, 1, 2, 4, 6,
	# 8, 10, 12); every lane with income gains bonus x the number of the player's resource buildings producing that lane.
	var bonus: int = INCOME_TABLE[mini(research_level.call(player, "PIBX"), 7)] + INCOME_TABLE[mini(research_level.call(player, "PHLX"), 7)] if research_level.is_valid() else 0
	if bonus != 0:
		var producers := [0, 0, 0, 0]
		for id in mines:
			if entities[id].owner == player: producers[int(mines[id].resource)] += 1
		if not other.is_empty():
			for resource in range(4): producers[resource] += int(other.producers[resource])
		for resource in range(4):
			if total[resource] != 0: total[resource] += bonus * producers[resource]
	return total

const INCOME_TABLE := [0, 1, 2, 4, 6, 8, 10, 12]       # 0x6115c4
var research_level: Callable                             # (player, id) -> 0x437f70 level; set by the match (Production)
var other_income: Callable                               # B4-1: (player) -> income from units and buildings (main.gd)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). Entities (mines, buildings) are shared objects: saved once by identity through
## the Refs table (production.buildings and mines.mines hold the same objects).
func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, ["entities", "research_level", "other_income"])
	s["entities"] = entities.keys().map(func(id): return [id, refs.ref(entities[id])])
	return s

func load_state(state: Dictionary, refs):
	preload("res://simulation/save_game.gd").restore(self, state, ["entities"])
	entities.clear()
	for pair in state.entities: entities[pair[0]] = refs.get_obj(int(pair[1]))
