extends RefCounted

const UnitAgent = preload("res://battle/unit_agent.gd")
# original_steps/turn_frames come from tools/emulate_pathfinder.py (original search, single segment).
const CASES = [
	{"id":"open_ground", "start":Vector2i(12,64), "goal":Vector2i(22,64), "original_steps":10, "original_turn_frames":0},
	{"id":"structure_detour", "start":Vector2i(6,51), "goal":Vector2i(21,51), "original_steps":15, "original_turn_frames":3},
	{"id":"terrain_detour", "start":Vector2i(45,31), "goal":Vector2i(62,31), "original_steps":17, "original_turn_frames":10}
]
const SPEEDS = [8, 10] # ARM base and the earlier UI reading 8+2.

static func run(navigator: RefCounted) -> Dictionary:
	var result := {"schema":2, "map":"Desert Sands", "fixture":"provisional test units, not original startup", "physics_hz":60,
		"game_speed":"Medium (clock x1)", "path_policy":"ported FUN_0042e180 search chained through the 8x8 sector layer (0x42f650/0x42ff30)", "cases":[],
		"original_reference":{"source":"executable analysis and emulation", "status":"runtime observations still required"}}
	for fixture in CASES:
		var start: Vector2 = navigator.center(fixture.start)
		var goal: Vector2 = navigator.center(fixture.goal)
		var route: Dictionary = navigator.plan(start, goal)
		var item := {"id":fixture.id,"start_cell":[fixture.start.x,fixture.start.y],"goal_cell":[fixture.goal.x,fixture.goal.y],"planned":route.ok}
		if route.ok:
			item.merge({"steps":route.steps,"path_length_px":route.length_px,"original_steps":fixture.original_steps})
			for speed in SPEEDS:
				var unit = UnitAgent.new()
				unit.navigator = navigator
				unit.position = start
				# Face the first step so it adds no turn, matching the emulated estimate.
				unit.direction = UnitAgent.direction_of(route.cells[0] - fixture.start)
				unit.give_order({"kind":"move","target":route.target,"speed":speed,"group":0},"replace")
				var ticks := 0
				while not unit.orders.is_empty() and ticks < 36000:
					unit.advance(1.0/60.0)
					ticks += 1
				var timing: Dictionary = UnitAgent.step_ms(speed)
				item["speed_%d" % speed] = {"active_travel_seconds":unit.moving_time,"arrival_tick_seconds":ticks/60.0,
					"distance_travelled_px":unit.distance_travelled,"completed":unit.orders.is_empty() and unit.last_error.is_empty(),
					"original_prediction_seconds":fixture.original_steps * UnitAgent.on_update(timing.step) / 1000.0,
					# Each turning step adds its turn frames, then ends on the next 25 ms update.
					"turn_allowance_seconds":fixture.original_turn_frames * (timing.frame + 25.0) / 1000.0}
				unit.free()
		else: item["reason"] = route.reason
		result.cases.append(item)
	return result
