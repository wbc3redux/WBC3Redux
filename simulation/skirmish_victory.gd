extends RefCounted
## S-2 (SKIRMISH_RESEARCH.md "S-2"): the victory options 1..12 of the skirmish setup, 0x41c7d0's event per option and the
## event conditions of 0x514670. **Emulated** (tools/emulate_victory.py -> tests/victory_fixtures.json, 1,500 random worlds);
## the option table, the event walker 0x516230 and the tie message 0x1d0 are **Read**.
##
## Every one of the 22 scenarios holds exactly one active event, event 0 = Standard Victory (side 6, condition 10; Data:
## EVSH chunks) and header byte 0x14c set, so 0x41c7d0 appends the option's event as event 1 and Standard Victory stays
## active beside it: 0x516230 runs event 0 first, then every event with the marker -10. On a Random Map the event table is
## empty, so the option's event becomes event 0 and replaces Standard Victory (`0x70d8e4 == 0` in 0x41c7d0, Read).
##
## Options 9 (Against the Horde), 10 (Battle of Titans) and 11 (Pitched Battle) install no event: they decide by Standard
## Victory and change the start instead (skirmish_setup.gd, main.gd).

const SIDES := 6
const STANDARD := 10                 # condition 10 (0x514670), option 0's record 0x513c30
const RAZE_ALL := 0xc
const KILL_ALL := 0xd
const ASSASSINATION := 0xe
const RAZE_FEST := 0xf
const SLUG_FEST := 0x10
const FORTRESS := 0x11
const KING := 0x12
const MERCHANTS := 0x13
const FLAGS := 0x1e
const TIE_EXTENSION_S := 300         # 0x514670 cases 0xf / 0x10 send 0x1d0 with 300; 0x4aecd0 adds it to the delay and restarts the timer
const KEEP_TOP_LEVEL := 4            # 0x514670 case 0x12: building +0x8a == 4, the BK?4 Keep ("first to build a 5th level Keep")
const HORDE := 9                     # Against the Horde: 0x4e3c60 case 4 sets slot 0 to team 1 and the others to team 2
const TITANS := 10                   # Battle of Titans: a Titan per slot (0x41c7d0), computer heroes at level 100 (0x42a0d0)
const PITCHED := 11                  # Pitched Battle: 50 army points (0x4de740), Rampant computers, no race towers
const CAPTURE_FLAG := 12
const FREE_FOR_ALL := [4, 5, 6, 7, 8]   # 0x4e3c60 case 4: team 0 and the shield disabled while chosen; 9 sets the Horde teams

## 0x41c7d0: option -> the event it installs. timer_s = the on-screen countdown (0x41df20(1, s), 0 none), delay_s = event
## +0x49e (0x70dd86), score = the score panel (0x41df40(1), 0x429c20). value = event +4 (Merchants' 2500).
const EVENTS := {
	1: {"condition": RAZE_ALL, "timer_s": 300, "delay_s": 300, "score": false},
	2: {"condition": KILL_ALL, "timer_s": 300, "delay_s": 300, "score": false},
	3: {"condition": ASSASSINATION, "timer_s": 0, "delay_s": 0, "score": false},
	4: {"condition": RAZE_FEST, "timer_s": 1800, "delay_s": 1800, "score": true},
	5: {"condition": SLUG_FEST, "timer_s": 1800, "delay_s": 1800, "score": true},
	6: {"condition": FORTRESS, "timer_s": 300, "delay_s": 300, "score": false},
	7: {"condition": KING, "timer_s": 0, "delay_s": 0, "score": true},
	8: {"condition": MERCHANTS, "timer_s": 0, "delay_s": 0, "score": true, "value": 2500},
	12: {"condition": FLAGS, "timer_s": 0, "delay_s": 0, "score": true},
}

static func event_for(option: int) -> Dictionary:
	return EVENTS.get(option, {}).duplicate()

## 0x429c20: the score panel's value per player while the option shows it; -1 hides a row (eliminated or empty slot).
static func scores(option: int, world: Dictionary) -> Array:
	var out: Array = []
	for p in SIDES:
		if not bool(world.active[p]) or bool(world.eliminated[p]):
			out.append(-1)
			continue
		match option:
			4: out.append(int(world.razed[p]))                   # 0x739cf2
			5: out.append(int(world.killed[p]))                  # 0x732eea
			7:                                                   # 0x5325d0: the highest Keep (fourth id character - '/')
				var best := 0
				for o in world.objects[p]:
					if o.kind == "building" and bool(o.get("keep", false)): best = maxi(best, int(o.level) + 1)
				out.append(best)
			8:                                                   # the lowest of the four resources
				var r: Array = world.resources[p]
				out.append(mini(mini(int(r[0]), int(r[1])), mini(int(r[2]), int(r[3]))))
			12:                                                  # flags held
				var n := 0
				for o in world.objects[p]:
					if o.kind == "building" and String(o.get("code", "")) == "BMFL": n += 1
				out.append(n)
			_: out.append(-1)
	return out

## One pass of 0x514670 for event `event` (a copy of EVENTS' row with the live delay), side `side`.
## world: active, eliminated (7), allied (7 x 7), local, seconds, timer_running, objects (6 lists of {kind "unit" / "building",
## hp, resource, keep, level, code, flag}), heroes (7: hit points or null), resources (7 x 4), razed, killed (7), flags (count).
## Returns {"kind": "none" | "defeat" | "win" | "tie", "player": side}; a "win" of Capture the Flag names its player.
static func evaluate(world: Dictionary, event: Dictionary, side: int) -> Dictionary:
	var condition: int = int(event.condition)
	match condition:
		RAZE_ALL, KILL_ALL, RAZE_FEST, SLUG_FEST, FORTRESS:
			if int(world.seconds) < int(event.delay_s) or bool(world.timer_running): return _none()
	match condition:
		RAZE_ALL: return _last_side(world, side, _has_own_building, _has_any_building)
		KILL_ALL: return _last_side(world, side, _has_living_unit, _has_any_unit)
		ASSASSINATION: return _assassination(world, side)
		RAZE_FEST: return _most(world.razed, world, side)
		SLUG_FEST: return _most(world.killed, world, side)
		FORTRESS: return _last_side(world, side, _has_keep, _has_keep)
		KING: return _king(world, side)
		MERCHANTS: return _merchants(world, side, int(event.get("value", 2500)))
		FLAGS: return _flags(world)
	return _none()

static func _none() -> Dictionary:
	return {"kind": "none", "player": -1}

static func _allied(world: Dictionary, a: int, b: int) -> bool:
	return int(world.allied[a][b]) != 0

## Cases 0xc, 0xd, 0x11: the side is out when its own test fails; it wins when no active, non-eliminated, non-allied side
## passes the other test. The two tests differ on purpose (Emulated): an enemy's mine or dying unit still blocks the win.
static func _last_side(world: Dictionary, side: int, own: Callable, other: Callable) -> Dictionary:
	var won := true
	for i in SIDES:
		if not bool(world.active[i]) or bool(world.eliminated[i]): continue
		if i == side:
			if not bool(own.call(world.objects[i])): return {"kind": "defeat", "player": side}
		elif bool(other.call(world.objects[i])) and not _allied(world, side, i):
			won = false
	return {"kind": "win", "player": side} if won else _none()

static func _has_own_building(objects: Array) -> bool:          # 0x52b050: a building without a resource rate
	for o in objects:
		if o.kind == "building" and not bool(o.get("resource", false)): return true
	return false

static func _has_any_building(objects: Array) -> bool:
	for o in objects:
		if o.kind == "building": return true
	return false

static func _has_living_unit(objects: Array) -> bool:
	for o in objects:
		if o.kind == "unit" and int(o.hp) > 0: return true
	return false

static func _has_any_unit(objects: Array) -> bool:
	for o in objects:
		if o.kind == "unit": return true
	return false

static func _has_keep(objects: Array) -> bool:                  # 0x52b030: the second id character is 'K'
	for o in objects:
		if o.kind == "building" and bool(o.get("keep", false)): return true
	return false

## Case 0xe: the heroes of 0x70adb4.
static func _assassination(world: Dictionary, side: int) -> Dictionary:
	var won := true
	for i in SIDES:
		if not bool(world.active[i]) or bool(world.eliminated[i]): continue
		var hp = world.heroes[i]
		var living: bool = hp != null and int(hp) >= 1
		if i == side:
			if not living: return {"kind": "defeat", "player": side}
		elif living and not _allied(world, side, i):
			won = false
	return {"kind": "win", "player": side} if won else _none()

## Cases 0xf / 0x10: the first highest score among slots 0..5 not eliminated, a tie with any of the seven tables (empty slots
## and the neutral player included) extends the event by 300 s (message 0x1d0).
static func _most(table: Array, world: Dictionary, side: int) -> Dictionary:
	var leader := -1
	var best := -1
	for i in SIDES:
		if not bool(world.eliminated[i]) and int(table[i]) > best:
			leader = i
			best = int(table[i])
	if leader < 0: return {"kind": "defeat", "player": side}
	for i in 7:
		if i != leader and not bool(world.eliminated[i]) and int(table[i]) == best:
			return {"kind": "tie", "player": side}
	return {"kind": "win" if leader == side else "defeat", "player": side}

## Case 0x12: the first BK?4 Keep in list order decides; slots are not tested (an empty slot has an empty list).
static func _king(world: Dictionary, side: int) -> Dictionary:
	for owner in SIDES:
		for o in world.objects[owner]:
			if o.kind == "building" and bool(o.get("keep", false)) and int(o.level) == KEEP_TOP_LEVEL:
				return {"kind": "win" if owner == side else "defeat", "player": side}
	return _none()

## Case 0x13: the first slot with `value` of every resource wins; the others lose.
static func _merchants(world: Dictionary, side: int, value: int) -> Dictionary:
	for i in SIDES:
		var r: Array = world.resources[i]
		if int(r[0]) < value or int(r[1]) < value or int(r[2]) < value or int(r[3]) < value: continue
		return {"kind": "win" if i == side else "defeat", "player": side}
	return _none()

## Case 0x1e: slot i holds flag n when an active slot's team owns it (row i, column owner of 0x748915, or i itself); a slot
## holding all 0x7494b4 flags wins, the local player preferred; the side argument plays no part.
static func _flags(world: Dictionary) -> Dictionary:
	var count: int = int(world.flags)
	var held: Array = []
	for i in SIDES:
		var row: Array = []
		row.resize(6)
		row.fill(false)
		held.append(row)
	for owner in SIDES:
		if not bool(world.active[owner]): continue
		for o in world.objects[owner]:
			if o.kind != "building" or String(o.get("code", "")) != "BMFL": continue
			var n: int = int(o.get("flag", -1))
			if n < 0 or n >= 6: continue
			for i in SIDES:
				if bool(world.active[i]) and (owner == i or _allied(world, i, owner)): held[i][n] = true
	var winner := -1
	for i in SIDES:
		var all := true
		for n in count:
			if not bool(held[i][n]): all = false
		if not all: continue
		if i == int(world.local): winner = i
		elif winner < 0: winner = i
	return {"kind": "win", "player": winner} if winner >= 0 else _none()
