extends SceneTree
const Entity = preload("res://simulation/entity_state.gd")
const Economy = preload("res://simulation/economy.gd")
const Conversion = preload("res://simulation/conversion.gd")
const Targets = preload("res://simulation/conversion_targets.gd")
var checks := 0
var failures := 0
var resource_events := 0
var ownership_events := 0
var candidates: Array = []

func check(condition: bool, label: String):
	checks += 1
	if not condition:
		failures += 1
		push_error(label)

func _init():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/economy_fixtures.json"))
	for case in fixtures.mine_cases:
		var economy := Economy.new(0)
		var initial := [0, 0, 0, 0]
		if case.full: initial.fill(1000)
		economy.add_player(0, initial)
		var entity := Entity.new(1, "BRG0", 0, Vector2(320, 240), 1, int(case.workers))
		check(economy.register_mine(entity, int(case.resource), int(case.rate), int(case.reserve)), "register mine")
		economy.mines[1].exhausted = case.exhausted
		check(economy._calculate(0) == case.income.map(func(value): return int(value)), "emulated income")
		check(economy.mines[1].reserve == int(case.remaining), "emulated reserve")
		check(economy.mines[1].rate == int(case.next_rate), "emulated depleted rate")
		check(economy.mines[1].exhausted == case.next_exhausted, "emulated exhausted flag")
	for level in range(5):
		var economy := Economy.new(0)
		economy.add_player(0, [0, 0, 0, 0])
		economy.register_entity(Entity.new(10, "BKH" + str(level), 0, Vector2.ZERO))
		economy.register_entity(Entity.new(11, "BKH0", 0, Vector2.ZERO))
		economy.refresh_capacity(0)
		check(economy.capacity(0) == fixtures.keep_capacities[level].map(func(value): return int(value)), "max Keep capacity")
	_test_economy()
	_test_conversion(fixtures)
	if failures == 0: print("Economy/conversion checks passed: ", checks)
	else: printerr("Economy/conversion failures: ", failures, " / ", checks)
	quit(0 if failures == 0 else 1)

func _test_economy():
	var economy := Economy.new(0)
	economy.add_player(0, [0, 0, 0, 0])
	economy.add_player(1, [0, 0, 0, 0])
	economy.resources_changed.connect(func(_owner, _before, _after): resource_events += 1)
	var mine := Entity.new(1, "BRG1", 0, Vector2.ZERO, 2, 1)
	mine.ownership_changed.connect(func(_id, _old, _new): ownership_events += 1)
	economy.register_mine(mine, 0, 2, 100)
	check(not economy.register_mine(mine, 0, 2, 100), "duplicate ID rejected")
	economy.update(0)
	check(economy.resources(0) == [0, 0, 0, 0], "local income delayed")
	check(economy.mines[1].reserve == 95, "batch depletes full amount")
	economy.update(249)
	check(economy.resources(0)[0] == 0, "no early installment")
	economy.update(1000)
	check(economy.resources(0)[0] == 1, "integer installment rounding")
	mine.owner = 1
	mine.owner = 1
	check(ownership_events == 1, "one notification per ownership transition")
	economy.update(4000)
	check(economy.resources(0)[0] == 5 and economy.resources(1)[0] == 0, "snapshot income survives ownership change, strict cycle boundary")
	economy.update(4001)
	check(economy.resources(1)[0] == 5, "new owner receives next cycle immediately")
	check(economy.mines[1].reserve == 90, "new owner reserve continues")
	economy.remove_entity(1)
	economy.update(8001)
	check(economy.resources(1)[0] == 5, "removed mine stops producing")
	var keep := Entity.new(2, "BKH4", 0, Vector2.ZERO)
	economy.register_entity(keep)
	economy.refresh_capacity(0)
	economy.credit(0, [4000, 4000, 4000, 4000])
	check(economy.resources(0) == [3000, 3000, 3000, 3000], "reward clips all four lanes")
	keep.owner = 1
	economy.refresh_capacity(0)
	check(economy.capacity(0) == [1000, 1000, 1000, 1000], "lost Keep recomputes cap")
	check(economy.resources(0)[0] == 3000, "cap loss does not eagerly destroy stock")
	economy.credit(0, [1, 0, 0, 0])
	check(economy.resources(0) == [1000, 3000, 3000, 3000], "original nonzero-lane overcap semantics")
	var before := economy.resources(0)
	check(not economy.try_spend(0, [1001, 1, 0, 0]), "insufficient spend rejected")
	check(economy.resources(0) == before, "failed spend atomic")
	check(not economy.try_spend(0, [-1, 0, 0, 0]), "negative debit rejected")
	check(economy.try_spend(0, [1000, 0, 0, 0]), "exact debit succeeds")
	var snapshot := economy.resources(0)
	snapshot[0] = 100
	check(economy.resources(0)[0] == 0, "resource snapshot isolated")
	check(resource_events > 0, "resource changes notified")
	# Sparse and frequent updates produce the same local installment total.
	for step in [25, 100, 250, 1000]:
		var other := Economy.new(0)
		other.add_player(0, [0, 0, 0, 0])
		other.register_mine(Entity.new(3, "BRC2", 0, Vector2.ZERO, 3, 8), 2, 4, 500)
		for now in range(0, 4001, step): other.update(now)
		check(other.resources(0) == [0, 0, 16, 0], "partition-independent distribution")

func select_targets(owner: int, _cell: Vector2i, _radius: int) -> Array:
	return candidates.filter(func(entity): return entity.owner != owner)

func _test_conversion(fixtures: Dictionary):
	for case in fixtures.conversion_geometry:
		check(Targets.in_range(Vector2i(64, 64), Vector2i(case.anchor[0], case.anchor[1]),
			Vector2i(case.footprint[0], case.footprint[1]), 4) == case.found, "original area geometry parity")
	var registry := Targets.new()
	for id in range(12):
		var target := Entity.new(id, "BRG1", 6, Vector2(320 + id * 32, 240), 2)
		registry.register_target(target, Vector2i(6, 6), func(_owner, state): return state.entity_id != 1)
	var selected: Array = registry.select_targets(0, Vector2i(16, 10), 19)
	check(selected.size() == 8, "area limited to eight eligible buildings")
	check(selected[0].entity_id == 0 and selected[1].entity_id == 2, "scan order and lifecycle exclusion")
	registry.remove_target(0)
	check(registry.select_targets(0, Vector2i(16, 10), 19)[0].entity_id == 2, "removed conversion target excluded")
	for case in fixtures.conversion_completion:
		var converter := Conversion.new()
		var hero := Entity.new(1, "AHHX", 0, Vector2(320, 240))
		var mine := Entity.new(2, "BRG1", 6, Vector2(352, 240), 2)
		candidates = [mine]
		check(hero.cell() == Vector2i(10, 10), "existing coordinate convention")
		check(not converter.begin(hero, "peasant", 1, 4, 0, select_targets), "builder cannot convert")
		check(not converter.begin(hero, "keep", 1, 4, 0, select_targets), "unverified Keep timer not substituted")
		check(converter.begin(hero, "hero", 1, 4, 0, select_targets), "resolved unit profile accepted")
		converter.update(int(case.now))
		check((mine.owner == 0) == case.finished, "original strict completion parity")
	var converter := Conversion.new()
	var hero := Entity.new(1, "AHHX", 0, Vector2.ZERO)
	var first := Entity.new(2, "BRG1", 6, Vector2.ZERO, 2)
	var arrived := Entity.new(3, "BRM2", 6, Vector2.ZERO, 3)
	candidates = [first]
	converter.begin(hero, "hero", 20, 4, 0, select_targets)
	candidates = [arrived]
	converter.update(20001)
	check(first.owner == 6 and arrived.owner == 0, "completion reselects area instead of capturing initial targets")
	candidates = [first]
	converter.begin(hero, "hero", 20, 4, 21000, select_targets)
	converter.cancel(1)
	converter.update(50000)
	check(first.owner == 6, "cancelled conversion cannot capture")
	converter.begin(hero, "hero", 20, 4, 50001, select_targets)
	hero.owner = 1
	converter.update(80000)
	check(first.owner == 6 and converter.active.is_empty(), "actor ownership change invalidates job")
	candidates = []
	check(not converter.begin(hero, "hero", 20, 4, 90000, select_targets), "empty area does not start timer")
