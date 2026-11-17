extends RefCounted
## Construction and unit production for the Knights slice (milestone 7), following the building update
## (vtable 0x5ead00 slot 0x52c250), production start 0x52e1d0, queue 0x43bc90, cancellation 0x52d8a0 /
## 0x52d7e0, builder commands 0x524450 / 0x5249f0 / 0x52f8a0, placement 0x435900 and creation 0x4a49e0.
## Rule provenance and open items: PRODUCTION_RESEARCH.md. Resources move through the milestone-6 Economy
## (spend at job/placement start, credit on refund); movement through the milestone-4 Navigation.
const Rules = preload("res://simulation/production_rules.gd")
const Building = preload("res://simulation/building_state.gd")
const Placement = preload("res://simulation/placement.gd")
const ResearchEffects = preload("res://simulation/research_effects.gd")
const RacePowers = preload("res://simulation/race_powers.gd")

signal building_placed(building_id: int)
signal building_completed(building_id: int)
signal building_destroyed(building_id: int)
signal building_upgraded(building_id: int, previous_type: String)
signal builder_hidden(builder_id: int) # emitted before the footprint is stamped (0x4a6f80 hides the builder first)
signal builder_released(builder_id: int, cell: Vector2i)
signal unit_ready(info: Dictionary) # info.unit_id is filled in by the handler that creates the unit
signal job_started(building_id: int, item: String)
signal job_finished(building_id: int, item: String)
signal research_completed(owner: int, item: String)
signal mercenary_completed(building_id: int, item: String)   # B2-1: POMA / POMB / POMC finished at a building (main.gd rolls the pool)
signal notice(text: String)
signal building_converted(building_id: int, previous_owner: int) # milestone 12: 0x4a6cc0 changed the owner

## Rebuild policy: the UI draws six order slots (0x4d6790 loop below 6): one running job and five queued.
## The enforcement point was not located (Open).
const QUEUE_LIMIT := 5
const DECAY_INTERVAL_MS := 250 # 0x52c4e5: unattended construction loses 1 hit point per 250 ms.
const MAX_COMMAND := 250 # 0x533dc0 caps the limit at 250.
const LANES = ["gold", "metal", "crystal", "stone"]

var rules: RefCounted
var economy: RefCounted
var navigator: RefCounted
var buildings: Dictionary = {} # id -> BuildingState
var units: Dictionary = {} # unit id -> {"type", "owner"}
var next_building_id := 1000
var last_update_ms := -1
var visibility = null # optional Visibility: the local player's placements need explored/visible cells (0x435900)
var local_player := 0
var hero_command := 0 # 0x5268c0 hero term of the command limit (hero derived stat 12); Open until a hero is bound.
var hero_commands: Dictionary = {} # owner -> 0x5268c0 term of that player's living hero (skirmish match); overrides hero_command
# Computer players (AI_RESEARCH.md section 4): owner -> difficulty 1..7. 0x52e1d0 starts their jobs without a stock check (the
# debit clamps at zero); 0x533dc0 adds 2 x difficulty to their command limit; ai_discounts (owner -> percent) is the 0x40b6b0
# discount while their hero lives, kept current by the AI controller.
var ai_players: Dictionary = {}
var ai_discounts: Dictionary = {}

## 0x526cf0 (Open, 0) plus the computer discount of 0x40b6b0.
func price_discount(owner: int) -> int:
	return discount + int(hero_discounts.get(owner, 0)) + int(ai_discounts.get(owner, 0))

## Milestone 11a: every player's race (0x708f96 + p * 0x2c; Knights when unset) and completed research (0x70ae40 + p * 200,
## at most 50 ids, 0x436500). The cost function, menus and dependency rows are looked up with the owner's race.
var races: Dictionary = {}               # owner -> race index 0..15
var research: Dictionary = {}            # owner -> Array of completed research ids, in completion order
var hero_alive: Dictionary = {}          # owner -> whether the owner's hero lives (slot gate H, hero price terms); true when unset
var hero_build_skill: Dictionary = {}    # owner -> hero skill 0x3f value (0x577520 +4): building time - n % while the hero lives
var hero_research_discount: Dictionary = {} # owner -> hero skill 0x25 + item stat 0x25 (0x577520 / 0x40c380): research price - n %
var hero_skill_ranks: Dictionary = {}     # owner -> {skill: rank} of 0x3d..0x41 (0x556b50) while the hero lives (REVIEW D4)
const RESEARCH_LIMIT := 50               # 0x436500 returns at 0x31 entries
const COMMAND_RESEARCH := [0, 5, 10, 15, 20, 25, 30, 35, 40, 50]   # 0x6115e0[level of PHDX / PSYX] (0x533dc0)
const HALF_COMMAND := ["AABA", "AKKX"]   # 0x533dc0: these count half each (rounded up as a group)
const ANIMALS := ["ACSH", "ACCO", "ACGO", "ACPE", "ACCA", "ACSO", "ACTU", "ACSE"]   # 0x528280(0): a quarter each

func race_of(owner: int) -> int:
	return int(races.get(owner, Rules.KNIGHT))

func research_level(owner: int, id: String) -> int:
	return Rules.research_level(research.get(owner, []), id)

## The player state 0x40b6b0 reads, for Rules.price().
func price_context(owner: int, builder_type: String = "") -> Dictionary:
	var alive: bool = bool(hero_alive.get(owner, true))
	return {"race": race_of(owner), "research": research.get(owner, []), "discount": price_discount(owner), "builder": builder_type,
		"hero_alive": alive, "skill_3f": int(hero_build_skill.get(owner, 0)), "research_discount": int(hero_research_discount.get(owner, 0)),
		"skill_ranks": hero_skill_ranks.get(owner, {})}

## The slot gates of 0x40c990 that depend on the player (hero alive; lords: 0x70d61a, never set here, Open).
func menu_context(owner: int) -> Dictionary:
	return {"hero_alive": bool(hero_alive.get(owner, true)), "lord_built": false}

func menu_for(building) -> Array:
	return rules.menu(building.original_type_id, race_of(building.owner), menu_context(building.owner))

## CONSTRUCTION row <letter><row> of the owner's race: row 0 the buildings, row 1 towers and walls (milestone 13; 0x4fd940
## gives row 1 to non-hero builders).
func construction_menu(owner: int, row: int = 0) -> Array:
	return rules.construction_menu(race_of(owner), row, menu_context(owner))

func price_of(owner: int, item: String, builder_type: String = "") -> Array[int]:
	var out: Array[int] = []
	for v in rules.price(item, price_context(owner, builder_type)).cost: out.append(int(v))
	return out

func time_of(owner: int, item: String, builder_type: String = "") -> int:
	var seconds := int(rules.price(item, price_context(owner, builder_type)).seconds)
	# B5-1 (BATCH5_RESEARCH.md E11, decision 4): the Chameleon's construction list 0x525a70 halves the time with PCON; the placement
	# order carries the panel's time (0x524450, Read).
	if item.begins_with("B"): seconds = RacePowers.construction_seconds(seconds, builder_type, research_level(owner, RacePowers.CONSTRUCTION_RESEARCH) != 0)
	return seconds * 1000
var hero_discounts: Dictionary = {} # owner -> 0x526cf0 of the living hero (milestone 11: derived 13 + Merchant + items)
var hero_building_hp: Dictionary = {} # owner -> Engineer x20 (0x43bd50) added to buildings placed while the hero lives
var discount := 0 # 0x526cf0 hero price modifier; Open until a hero is bound.

func _init(production_rules: RefCounted, player_economy: RefCounted, nav: RefCounted):
	rules = production_rules
	economy = player_economy
	navigator = nav

# ---------------------------------------------------------------- queries

func building(id: int):
	return buildings.get(id)

## 0x40b580: a requirement holds when the owner has a completed building that counts as that ID.
func requirement_met(owner: int, required: String) -> bool:
	for b in buildings.values():
		if b.owner == owner and not b.constructing and Rules.satisfies(b.original_type_id, required):
			return true
	return false

## Requirements may name research (0x40b350 counts completed research like buildings).
func missing_requirement(owner: int, item: String) -> String:
	for required in rules.requirements(item, race_of(owner)):
		# B4-3 (BATCH4_RESEARCH.md R3, Emulated review "recount"; decompile 10873-10886): 0x40b580 passes every 'A' word (the
		# entry's +0x118 is the id's first byte): AEAX's AEBX requirement never holds it back.
		if required.begins_with("A"): continue
		if Rules.is_research(required):
			if research_level(owner, required) == 0: return required
		elif not requirement_met(owner, required): return required
	return ""

## 0x533dc0. Knights Peasants (AHBX) and animals (0x528280) count a quarter each, AABA / AKKX half each, each group
## rounded up; other units their ARM +0xc8 (0x526870); heroes count nothing. The research terms PHDX / PSYX add
## 0x6115e0[level] to the limit.
func population(owner: int) -> Dictionary:
	var peasants := 0
	var animals := 0
	var halves := 0
	var other := 0
	for unit in units.values():
		if unit.owner != owner: continue
		if unit.type == "AHBX": peasants += 1
		elif unit.type in HALF_COMMAND: halves += 1
		elif unit.type in ANIMALS: animals += 1
		else: other += int(rules.definition(unit.type).get("population", 0))
	var keep := 0
	var limit := 0
	for b in buildings.values():
		if b.owner != owner: continue
		if not b.constructing: limit += rules.army_limit(b.original_type_id)
		keep = maxi(keep, Rules.keep_level(b.original_type_id))
	limit += int(hero_commands.get(owner, hero_command)) + Rules.KEEP_COMMAND_TABLE[keep] - 2 + 2 * int(ai_players.get(owner, 0))
	limit += COMMAND_RESEARCH[mini(research_level(owner, "PHDX"), 9)] + COMMAND_RESEARCH[mini(research_level(owner, "PSYX"), 9)]
	return {"current": ((peasants + 3) >> 2) + ((animals + 3) >> 2) + other + ((halves + 1) >> 1), "maximum": mini(limit, MAX_COMMAND)}

func register_unit(unit_id: int, type_id: String, owner: int):
	units[unit_id] = {"type": type_id, "owner": owner}

func unregister_unit(unit_id: int):
	units.erase(unit_id)

# ---------------------------------------------------------------- building placement (0x524450 / 0x4a6f80)

## Builders: Peasant or hero. `order_cell` is the click cell.
func can_place(owner: int, type_id: String, order_cell: Vector2i, builder = null) -> Dictionary:
	if not construction_menu(owner).has(type_id) and not construction_menu(owner, 1).has(type_id):
		return {"ok": false, "reason": "%s is not in the builder's construction list" % type_id}
	var missing := missing_requirement(owner, type_id)
	if missing != "": return {"ok": false, "reason": "requires %s" % missing}
	var fog_filter := Callable()
	if visibility != null and owner == local_player: fog_filter = func(cell): return visibility.cell_allows(owner, cell)
	var result: Dictionary = Placement.check(navigator, rules.definition(type_id), order_cell, builder, fog_filter)
	if not result.ok: return result
	# AI-4 (Read, 0x524450 at 0x5246d0): a computer player's placement skips the stock test (the place message 0x10e goes
	# out at once); the debit then clamps at zero, as for its jobs (0x52e1d0).
	if ai_players.has(owner): return result
	var cost: Array[int] = price_of(owner, type_id)
	var stock: Array = economy.resources(owner)
	for lane in range(4):
		if cost[lane] > stock[lane]:
			result.ok = false
			result.reason = "insufficient %s" % LANES[lane]
			return result
	return result

## The parts of can_place that don't depend on the cell: the construction list, the requirements and the cost. When
## these fail, can_place fails on every cell, so a site search can stop before it starts (main.gd ai_site; the computer
## player otherwise scanned 831 cells each pass while short of gold).
func can_place_anywhere(owner: int, type_id: String) -> bool:
	if not construction_menu(owner).has(type_id) and not construction_menu(owner, 1).has(type_id): return false
	if missing_requirement(owner, type_id) != "": return false
	if ai_players.has(owner): return true                          # AI-4: 0x524450, no stock test for a computer
	var cost: Array[int] = price_of(owner, type_id)
	var stock: Array = economy.resources(owner)
	for lane in range(4):
		if cost[lane] > stock[lane]: return false
	return true

## The builder must stand within three cells of the site (0x51ea20 case for order type 5) and is
## hidden inside the building (0x4a6f80 -> unit virtual +0x70) until it is released or built.
func place_building(owner: int, type_id: String, order_cell: Vector2i, now_ms: int, builder_id: int, builder_type: String, builder_cell: Vector2i, builder = null) -> Dictionary:
	if absi(builder_cell.x - order_cell.x) > 3 or absi(builder_cell.y - order_cell.y) > 3:
		return {"ok": false, "reason": "builder is more than three cells from the site"}
	var check := can_place(owner, type_id, order_cell, builder)
	if not check.ok: return check
	var definition: Dictionary = rules.definition(type_id)
	var cost: Array[int] = price_of(owner, type_id)
	if ai_players.has(owner): economy.debit_clamped(owner, cost)    # AI-4: 0x524450 (computer), clamped debit
	elif not economy.try_spend(owner, cost): return {"ok": false, "reason": "insufficient resources"}
	var id := next_building_id
	next_building_id += 1
	var anchor_x: int = int(check.left) + ((int(definition.footprint[0]) - 1) >> 1)
	var b = Building.new(id, type_id, owner, Vector2(anchor_x * 32, int(check.top) * 24), definition, int(check.left), int(check.top))
	b.constructing = true
	b.hit_points = 1 # 0x4a6f80: +0x82 = 1
	b.max_hit_points += int(hero_building_hp.get(owner, 0))   # 0x43bd50: Engineer x20 while the owner's hero lives (milestone 11)
	if research_level(owner, "PENG") != 0: b.max_hit_points = (b.max_hit_points * 5) / 4   # G-1: 0x43bd50's PENG tail (Read)
	b.builder_id = builder_id
	b.builder_cell = builder_cell
	b.started_ms = now_ms
	b.finish_ms = now_ms + time_of(owner, type_id, builder_type)
	b.progress = 0
	buildings[id] = b
	builder_hidden.emit(builder_id)
	navigator.stamp_building(id, b.left, b.top, int(definition.footprint[0]), int(definition.footprint[1]), definition.mask_rows)
	building_placed.emit(id)
	return {"ok": true, "building": b, "cost": cost}

## Fixture/start helper: a finished building (no construction). Keeps register with the economy.
func add_completed(owner: int, type_id: String, left: int, top: int) -> Object:
	var definition: Dictionary = rules.definition(type_id)
	var id := next_building_id
	next_building_id += 1
	var anchor_x := left + ((int(definition.footprint[0]) - 1) >> 1)
	var b = Building.new(id, type_id, owner, Vector2(anchor_x * 32, top * 24), definition, left, top)
	b.completed_counted = true
	buildings[id] = b
	navigator.stamp_building(id, left, top, int(definition.footprint[0]), int(definition.footprint[1]), definition.mask_rows)
	_register_economy(b)
	return b

func _register_economy(b):
	if Rules.keep_level(b.original_type_id) > 0:
		economy.register_entity(b)
		economy.refresh_capacity(b.owner)

# ---------------------------------------------------------------- builders (0x5249f0 / 0x52f8a0)

## Joining unfinished construction works only while nobody is building (0x5249f0 needs +0xd4 == 0).
## The timeline is re-based so the stored percentage is kept (0x110 with flag 0).
func attach_builder(building_id: int, builder_id: int, builder_cell: Vector2i, now_ms: int) -> bool:
	var b = buildings.get(building_id)
	if b == null or not b.constructing or b.builder_id >= 0: return false
	var total: int = b.finish_ms - b.started_ms
	var remaining: int = total * (100 - b.progress) / 100
	b.finish_ms = now_ms + remaining
	b.started_ms = now_ms - total + remaining
	b.builder_id = builder_id
	b.builder_cell = builder_cell
	builder_hidden.emit(builder_id)
	b.construction_changed.emit(building_id)
	return true

## The Stop/Cancel button on unfinished construction (0x4d0aa0 -> 0x52f8a0): the builder comes out,
## progress freezes and the building decays until someone resumes it. No refund path was found.
func release_builder(building_id: int, now_ms: int) -> bool:
	var b = buildings.get(building_id)
	if b == null or not b.constructing or b.builder_id < 0: return false
	var builder: int = b.builder_id
	b.builder_id = -1
	b.decay_at_ms = now_ms + DECAY_INTERVAL_MS # 0x4a73c0: +0xe8 = now + 0xfa
	builder_released.emit(builder, navigator.free_cell_near(b.builder_cell))
	b.construction_changed.emit(building_id)
	return true

# ---------------------------------------------------------------- production queue (0x43bc90, 0x52e1d0)

## Click-time gate (0x5690b0 / 0x569200): item offered here, prerequisites met, affordable now. Research (0x569200 codes 2
## and 5): refused once completed, or while the same research (or a lord, AT?X) runs or waits in any of the player's
## buildings; a level digit d > 0 needs level d of the same P..X research first (0x5690b0).
func can_queue(building_id: int, item: String) -> Dictionary:
	var b = buildings.get(building_id)
	if b == null or b.constructing: return {"ok": false, "reason": "building is not finished"}
	# 0x4d2300 mode 5 disables the production page while the Keep converts (0x52fc00, Read). Whether the computer player
	# may queue there is Open (its repair pass 0x4fffe0 skips converting buildings); the same gate applies (Provisional).
	if b.keep_converting: return {"ok": false, "reason": "the Keep is converting"}
	var entry := {}
	for candidate in menu_for(b):
		if candidate.id == item: entry = candidate
	if entry.is_empty(): return {"ok": false, "reason": "%s is not produced by %s" % [item, b.original_type_id]}
	var lord: bool = item.length() == 4 and item[0] == "A" and item[1] == "T" and item[3] == "X"
	if Rules.is_research(item):
		if research_level(b.owner, item) != 0: return {"ok": false, "reason": "already researched"}
		if item[0] == "P" and item[3] >= "1" and item[3] <= "9" and research_level(b.owner, item.substr(0, 3) + "X") < int(item[3]):
			return {"ok": false, "reason": "requires %s" % (item.substr(0, 3) + str(int(item[3]) - 1))}
	if Rules.is_research(item) or lord:
		for other in buildings.values():
			if other.owner == b.owner and (other.job_item == item or other.queue.has(item)): return {"ok": false, "reason": "already ordered"}
	var missing := missing_requirement(b.owner, item)
	if missing != "": return {"ok": false, "reason": "requires %s" % missing}
	var cost: Array[int] = price_of(b.owner, item)
	var stock: Array = economy.resources(b.owner)
	for lane in range(4):
		if cost[lane] > stock[lane] and not ai_players.has(b.owner): return {"ok": false, "reason": "insufficient %s" % LANES[lane]}
	if item[0] == "B" and (b.job_item == item or b.queue.has(item)): return {"ok": false, "reason": "upgrade already ordered"} # 0x4d6790 code 5
	if b.has_job() and b.queue.size() >= QUEUE_LIMIT: return {"ok": false, "reason": "queue is full"}
	return {"ok": true, "reason": ""}

func enqueue(building_id: int, item: String, now_ms: int) -> Dictionary:
	var gate := can_queue(building_id, item)
	if not gate.ok: return gate
	var b = buildings[building_id]
	if b.job_item == "" and not b.job_pending: # 0x43bc90: an idle building starts at once
		_start_job(b, item, now_ms)
	else:
		b.queue.append(item)
	b.production_changed.emit(building_id)
	return {"ok": true, "reason": ""}

## 0x52e1d0. Charges the stock at job start; an unaffordable item leaves the building pending (-1).
func _start_job(b, item: String, now_ms: int) -> bool:
	var found := false
	for candidate in menu_for(b):
		if candidate.id == item: found = true
	if not found: return false
	var cost: Array[int] = price_of(b.owner, item)
	if ai_players.has(b.owner): economy.debit_clamped(b.owner, cost)
	elif not economy.try_spend(b.owner, cost):
		b.job_pending = true
		b.job_item = ""
		b.job_progress = 0
		return false
	b.job_pending = false
	b.job_item = item
	b.job_cost = cost
	b.job_progress = 0
	b.job_start_ms = now_ms
	var ms := time_of(b.owner, item)
	# 0x52e1d0 (Read, AI_RESEARCH.md section 4): a computer player's research takes 90 / 80 / 70 % at Prince / Warlord /
	# Emperor (milestone 13; the slice had no research).
	if ai_players.has(b.owner) and Rules.is_research(item): ms = ms * int({4: 90, 5: 80, 6: 70}.get(int(ai_players[b.owner]), 100)) / 100
	b.job_end_ms = now_ms + ms
	b.population_blocked = false
	job_started.emit(b.entity_id, item)
	return true

## Loop at 0x52c5c5 / 0x52cbdc: pop the head when it starts, or when it fails without leaving the
## building pending; an unaffordable head stays queued.
func _start_next(b, now_ms: int):
	b.job_pending = false
	while not b.queue.is_empty():
		var started: bool = _start_job(b, b.queue[0], now_ms)
		if started or not b.job_pending: b.queue.pop_front()
		if started or b.job_pending: return
	b.job_pending = false

## 0x52d8a0: slot 0 cancels the running job with a refund and starts the next one; slot n > 0 drops the
## nth queued order (nothing was paid for it).
func cancel_slot(building_id: int, slot: int, now_ms: int) -> bool:
	var b = buildings.get(building_id)
	if b == null: return false
	if slot == 0:
		if not b.has_job(): return false
		if b.job_item != "": economy.credit(b.owner, b.job_cost)
		b.job_item = ""
		b.job_pending = false
		b.job_cost = [0, 0, 0, 0]
		_start_next(b, now_ms)
	else:
		if slot > b.queue.size(): return false
		b.queue.remove_at(slot - 1)
	b.production_changed.emit(building_id)
	return true

## 0x52d7e0 (Cancel button): refund the running job, drop every queued order.
func cancel_all(building_id: int) -> bool:
	var b = buildings.get(building_id)
	if b == null or not b.has_job(): return false
	b.queue.clear()
	if b.job_item != "": economy.credit(b.owner, b.job_cost)
	b.job_item = ""
	b.job_pending = false
	b.job_cost = [0, 0, 0, 0]
	b.production_changed.emit(building_id)
	return true

## Milestone 12: 0x4a6cc0 (message 0x143), the production side of a conversion, in the original order. The garrison /
## worker count +0xca becomes 0; the building joins the new owner's list (+0xc, +0x88); the dependency counters follow
## the owner (0x40b290 / 0x40b170: requirement_met and the command limit read the owner every time); a running job is
## cancelled by 0x52d7e0 *after* the owner changed, so its refund goes to the new owner and the queued orders are dropped;
## a Keep conversion stops (0x52fbc0, MatchConversion); repeat (+0x190) and the rally point (0x52e6b0(-1, -1)) clear.
## The Keep's resource capacity moves with it (0x52aac0 aggregates by owner).
func convert_building(building_id: int, owner: int) -> bool:
	var b = buildings.get(building_id)
	if b == null or int(b.owner) == owner: return false
	var previous: int = b.owner
	b.worker_count = 0
	b.owner = owner
	if b.has_job(): cancel_all(building_id)
	b.repeat = false
	b.rally = Vector2i(-1, -1)
	if economy.entities.has(building_id):
		for p in [previous, owner]:
			if economy.capacities.has(p): economy.refresh_capacity(p)
	b.production_changed.emit(building_id)
	building_converted.emit(building_id, previous)
	return true

func set_rally(building_id: int, cell: Vector2i):
	var b = buildings.get(building_id)
	if b != null: b.rally = cell # 0x52e6b0

# ---------------------------------------------------------------- spawn point (0x52df30)

## Target cell for a new unit: the footprint's bottom centre, moved half a footprint toward a rally
## point more than three cells away on that axis; kept only when its TER height equals the base's.
func spawn_target(b) -> Vector2i:
	var width: int = b.definition.footprint[0]
	var height: int = b.definition.footprint[1]
	var cx: int = b.left + ((width - 1) >> 1)
	var base := Vector2i(cx, b.top - (height >> 2) + height)
	if b.rally.x < 0 or b.rally.y < 0: return base
	var out := base
	if b.rally.x > cx + 3: out.x = cx + (width >> 1)
	elif b.rally.x < cx - 3: out.x = cx - (width >> 1)
	else: out.x = cx
	if b.rally.y > base.y + 3: out.y = base.y + (height >> 1)
	elif b.rally.y < base.y - 3: out.y = base.y - (height >> 1)
	else: out.y = base.y
	if navigator.nav_cell_height(base) != navigator.nav_cell_height(out): return base
	return out

# ---------------------------------------------------------------- update (building vtable +0x2c)

func update(now_ms: int):
	assert(now_ms >= last_update_ms)
	last_update_ms = now_ms
	for id in buildings.keys():
		var b = buildings.get(id)
		if b == null: continue
		if b.constructing: _update_construction(b, now_ms)
		else: _update_production(b, now_ms)

func _update_construction(b, now_ms: int):
	if b.builder_id >= 0:
		if b.progress >= 100:
			_complete(b, now_ms) # message 0x111 -> 0x4a6f30 -> 0x52bfd0
			return
		var total: int = b.finish_ms - b.started_ms
		var before: int = b.progress
		var percent: int = 100 if total <= 0 else (now_ms - b.started_ms) * 100 / total
		b.progress = clampi(percent, 1, 100)
		var gain: int = (b.progress * b.max_hit_points) / 100 - (before * b.max_hit_points) / 100
		b.hit_points = mini(b.hit_points + gain, b.max_hit_points)
		if before != b.progress: b.construction_changed.emit(b.entity_id)
	elif now_ms >= b.decay_at_ms:
		b.hit_points -= 1
		b.decay_at_ms = now_ms + DECAY_INTERVAL_MS
		if b.hit_points <= 0: _destroy(b)
		else: b.construction_changed.emit(b.entity_id)

func _complete(b, now_ms: int):
	b.constructing = false
	b.hit_points = mini(b.hit_points, b.max_hit_points)
	b.progress = 100
	b.completed_counted = true
	var builder: int = b.builder_id
	b.builder_id = -1
	if b.has_job() and b.job_paused: # 0x52bfd0 rebases a paused job
		var total: int = b.job_end_ms - b.job_start_ms
		b.job_start_ms = now_ms - (b.job_progress * total) / 100
		b.job_end_ms = ((100 - b.job_progress) * total) / 100 + now_ms
		b.job_paused = false
	_register_economy(b)
	if builder >= 0: builder_released.emit(builder, navigator.free_cell_near(b.builder_cell))
	building_completed.emit(b.entity_id)

## Death of unfinished construction (no refund; 0x52b3e0 releases the builder at the footprint centre).
func _destroy(b):
	var builder: int = b.builder_id
	b.builder_id = -1
	navigator.unstamp_building(b.entity_id)
	economy.remove_entity(b.entity_id)
	buildings.erase(b.entity_id)
	if builder >= 0:
		var width: int = b.definition.footprint[0]
		var height: int = b.definition.footprint[1]
		builder_released.emit(builder, navigator.free_cell_near(Vector2i(b.left + ((width - 1) >> 1), b.top + (height >> 1))))
	building_destroyed.emit(b.entity_id)

func _update_production(b, now_ms: int):
	if b.job_pending:
		_start_next(b, now_ms) # 0x52c5ae: retry the head of the queue
		return
	if b.job_item == "": return
	if now_ms >= b.job_end_ms and not b.job_paused:
		_finish_job(b, now_ms)
	elif not b.job_paused:
		var total: int = b.job_end_ms - b.job_start_ms
		b.job_progress = clampi((now_ms - b.job_start_ms) * 100 / total, 0, 100)

func _finish_job(b, now_ms: int):
	var item: String = b.job_item
	if item[0] == "A":
		var cost: int = int(rules.definition(item).get("population", 0))
		var pop := population(b.owner)
		if pop.current + cost > pop.maximum: # 0x52c6ec / 0x5348b0: wait until the limit allows it
			if not b.population_blocked:
				b.population_blocked = true
				notice.emit("More buildings are needed to command more units")
			return
		b.population_blocked = false
		_spawn(b, item)
	elif item[0] == "B":
		_upgrade(b, item)
	elif Rules.is_research(item):
		# B2-1: 0x436500 -> 0x4382d0 (E3); at the 50-item limit 0x436500 returns first.
		if complete_research(b.owner, item) and item in ["POMA", "POMB", "POMC"]: mercenary_completed.emit(b.entity_id, item)
	b.job_item = ""
	b.job_cost = [0, 0, 0, 0]
	job_finished.emit(b.entity_id, item)
	if b.repeat and item[0] == "A" and missing_requirement(b.owner, item) == "": # 0x52cb04
		b.queue.append(item)
	_start_next(b, now_ms)
	b.production_changed.emit(b.entity_id)

func _spawn(b, item: String):
	var target := spawn_target(b)
	# 0x4a49e0 -> 0x530a90 with the new unit's extent (0x524b00 passes ARM +0x39): a 2x2 unit needs a 2x2 place.
	var extent: int = maxi(1, int(rules.definition(item).get("footprint", [1, 1])[0]))
	var mtype: int = int(rules.definition(item).get("movement_type", 0))
	var cell: Vector2i = navigator.free_cell_near(target, null, extent, mtype if mtype != 1 else 0)   # 0x530a90 checks with the unit's type (M-3)
	if mtype == 1: cell = navigator.free_air_cell_near(target)   # flyers (milestone 13)
	if cell.x < 0: return # 0x4a49e0 creates nothing when no cell is found; the cost is already spent
	var info := {"building": b.entity_id, "item": item, "owner": b.owner, "cell": cell, "rally": b.rally, "unit_id": -1}
	unit_ready.emit(info)
	if int(info.unit_id) >= 0: register_unit(int(info.unit_id), item, b.owner)

## B1-3: message 0xfa from a building power (Slavehorde's thralls, LAB_004d0c50): a unit of `item` for `owner` at the
## free cell nearest `target` (0x4a49e0 -> 0x530a90), without a rally order (B2-1: `rally` for a Foreign Mercenary). "direct":
## message 0xfa sent as it is, without the creation terms of 0x4a5780. Returns the unit id or -1.
func spawn_unit(owner: int, item: String, target: Vector2i, building_id: int = -1, rally: Vector2i = Vector2i(-1, -1), extra := {}) -> int:
	var extent: int = maxi(1, int(rules.definition(item).get("footprint", [1, 1])[0]))
	var mtype: int = int(rules.definition(item).get("movement_type", 0))
	var cell: Vector2i = navigator.free_cell_near(target, null, extent, mtype if mtype != 1 else 0)
	if mtype == 1: cell = navigator.free_air_cell_near(target)
	if cell.x < 0: return -1
	var info := {"building": building_id, "item": item, "owner": owner, "cell": cell, "rally": rally, "unit_id": -1, "direct": true}
	info.merge(extra, true)                   # B3-1: "no_start" = message 0xfa with +0x3b = 1 (Ancestral Spirit, E5)
	unit_ready.emit(info)
	if int(info.unit_id) >= 0: register_unit(int(info.unit_id), item, owner)
	return int(info.unit_id)

## 0x436500: a completed research joins the owner's list (at most 50; never twice; PSPR, PARR, POMA, POMB, POMC are
## not listed; PQKN only once three Knight's Quest choices are stored). Its unit-table and flag effects are read from the
## list by research_effects.gd (Emulated); the per-item side effects run from `research_completed` (B2-1: PFAR in main.gd,
## PLI0 / PLI1 in spells.gd, POMA..C through `mercenary_completed`); those of the races to come are Open.
func complete_research(owner: int, item: String) -> bool:
	var list: Array = research.get(owner, [])
	if list.size() > RESEARCH_LIMIT - 1 or research_level(owner, item) != 0: return false
	if item == "PQKN" and owner == local_player and not ai_players.has(owner): _quest_choice(owner)   # 0x438de0 (local player only)
	var listed: bool = not (item in ["PSPR", "PARR", "POMA", "POMB", "POMC"])
	if item == "PQKN": listed = quests.get(owner, []).size() >= 3
	if listed:
		list.append(item)
		research[owner] = list
	if item == "PENG": _engineering(owner)
	research_completed.emit(owner, item)
	return true

## G-1 (Read, 0x438c20(p, 125), ResearchEffects.ENGINEERING_EXEMPT): the owner's buildings gain 25 % maximum and current hit
## points. The 0x52b050 exemption (words +0x94..+0x9a set: a resource building's output rates; G-2, Read) is the mines,
## which are not in `buildings` (simulation/mines.gd), so nothing more is needed here.
func _engineering(owner: int):
	for b in buildings.values():
		if b.owner != owner or String(b.original_type_id) in ResearchEffects.ENGINEERING_EXEMPT: continue
		b.max_hit_points = ResearchEffects.engineering_hit_points(b.max_hit_points)
		b.hit_points = ResearchEffects.engineering_hit_points(b.hit_points)

## Knight's Quest (PQKN): up to four chosen creature types per player (0x70d634 + 16p); a Knight cavalry kill of one gives
## +25 XP, +50 with POGL (0x5210b0). The choice list (0x438d40, Read): the table at 0x608938 in order, an entry of race -1
## always, an entry of race r once for every active other player of race r, at most four.
var quests: Dictionary = {}               # owner -> Array of chosen unit types
var players_in_match: Array = []          # active player slots (0x708f94), for the quest list; empty = owners of buildings
const QUEST_TABLE := [["AUGX", 2], ["AKGX", 8], ["AOGX", 5], ["AVGX", 11], ["ARGX", 14], ["AGGX", 15], ["AUAX", 2], ["AKOX", 8],
	["AOJX", 5], ["AVDX", 11], ["ARCX", 14], ["AGPY", 15], ["AUMX", 2], ["AKNX", 8], ["AGCY", 15], ["AGHY", 15],
	["AAEE", -1], ["AAEF", -1], ["AAEA", -1], ["AAEW", -1]]

func quest_candidates(owner: int) -> Array:
	var present: Array = players_in_match.duplicate()
	if present.is_empty():
		for b in buildings.values(): if not present.has(b.owner): present.append(b.owner)
	var out: Array = []
	for entry in QUEST_TABLE:
		if out.size() > 3: break
		if int(entry[1]) < 0:
			out.append(String(entry[0]))
			continue
		for p in present:
			if out.size() > 3: break
			if int(p) != owner and race_of(int(p)) == int(entry[1]): out.append(String(entry[0]))
	return out

## 0x438de0 opens a dialog of the candidates (those already chosen greyed) and stores the pick in the next free slot.
## Decision (labelled): the rebuild has no such dialog yet and picks the first candidate not chosen.
func _quest_choice(owner: int):
	var chosen: Array = quests.get(owner, [])
	if chosen.size() >= 4: return
	for id in quest_candidates(owner):
		if not chosen.has(id):
			chosen.append(id)
			quests[owner] = chosen
			notice.emit("Knight's Quest: %s." % rules.display_name(id))
			return

## 0x4a4f60: Keep level + 1, +100 maximum and current hit points, the object becomes the new type.
func _upgrade(b, item: String):
	var previous: String = b.original_type_id
	b.original_type_id = item
	b.definition = rules.definition(item)
	b.level += 1
	b.max_hit_points += 100
	b.hit_points += 100
	_register_economy(b)
	economy.refresh_capacity(b.owner)
	building_upgraded.emit(b.entity_id, previous)

# ------------------------------------------------------------------------------------------------ S-1 save / load
## SAVE_LOAD.md: the module's match state as plain data (simulation/save_game.gd). Buildings are shared objects
## (economy.entities holds the same ones), saved by identity through the Refs table in their insertion order; the
## rules' match options (build level, the no-dragons ... switches) are saved with them.
const _SAVE_SKIP := ["rules", "economy", "navigator", "visibility", "buildings"]

func save_state(refs) -> Dictionary:
	var s := preload("res://simulation/save_game.gd").capture(self, _SAVE_SKIP)
	s["buildings"] = buildings.keys().map(func(id): return [id, refs.ref(buildings[id])])
	s["rules_options"] = rules.options.duplicate(true)
	return s

func load_state(state: Dictionary, refs):
	preload("res://simulation/save_game.gd").restore(self, state, _SAVE_SKIP + ["rules_options"])
	buildings.clear()
	for pair in state.buildings: buildings[pair[0]] = refs.get_obj(int(pair[1]))
	rules.options.clear()
	rules.options.merge(state.rules_options.duplicate(true))
