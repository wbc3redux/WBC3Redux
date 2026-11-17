extends RefCounted
## Map effects (EFFH records, map wave 5, MAPS_RESEARCH.md "Wave 5"): particle emitters placed by the scenario.
## Emulated against the executable (tests/particle_fixtures.json, tools/emulate_particles.py):
## * an EFFH record names an Assets/Particles/<id>.xml definition (assets/particles.json, 0x486010's fields) and a world
##   pixel; 0x4910e0 creates the emitter (0x58c220, vtable 0x5eb13c, init 0x545760) and it lives for the whole match
##   unless the definition is `temporary` (then it goes after `lifetime` ms);
## * tick 0x545b90: move every 25 ms, force every 50 ms, release every `interval` ms (`release` at a time, at most `max`
##   alive and `total` in all when set), particles die after `life` ms; Anim* elements interpolate between start and end;
## * draw 0x5459f0: each particle is frame `frame` of the definition's sheet at the emitter pixel plus (x, y), with
##   translucency `alpha` (0..15) and the colour channels r / g / b on or off.
## Purely visual: no damage, sound or unit code is reached. The original rolls the match generator 0x458e70 for every new
## particle and only while the emitter is on screen; the rebuild gives each emitter its own generator of the same kind
## (deliberate: a headless match must not depend on the camera; MAPS_RESEARCH.md "Wave 5").
const CombatRng = preload("res://simulation/combat_rng.gd")

## A particle: [alive, frame, alpha, r, g, b, x, y, vx, vy, pforce x, pforce y, age, sheet] (the 0x34-byte record).
enum { ALIVE, FRAME, ALPHA, RED, GREEN, BLUE, X, Y, VX, VY, PFX, PFY, AGE, SHEET }

class Emitter:
	var d: Dictionary            # the particle definition (assets/particles.json)
	var pixel: Vector2i          # +0x4c / +0x4e
	var cell: Vector2i           # +0x48 / +0x4a (0x4939a0)
	var sheet := 0               # +0x194
	var rng
	var emitter := [0, 0, 0, 0]  # +0x13c x, y, varx, vary
	var force := [0, 0]          # +0x158
	var velocity := [0, 0, 0, 0] # +0x160 x, y, varx, vary
	var colour := [0, 0, 0]      # +0x170 (AnimGraphics on the emitter; not drawn)
	var used := 0                # +0x14c slots in use (high-water mark)
	var alive := 0               # +0x14e
	var released := 0            # +0x150
	var age := 0                 # +0x180
	var next_release := 0        # +0x184
	var next_force := 50         # +0x188
	var next_move := 25          # +0x18c
	var last := 0                # +0x190
	var particles: Array = []    # `max` slots

	## 0x545760: `clock` is the time the emitter is created; it ends in the first tick.
	func _init(definition: Dictionary, world: Vector2i, clock: int, generator, sheet_index: int = 0):
		d = definition
		pixel = world
		cell = Vector2i(_trunc_div(world.x, 32), _trunc_div(world.y, 24))
		sheet = sheet_index
		rng = generator
		emitter = [int(d.emitter_x), int(d.emitter_y), int(d.emitter_varx), int(d.emitter_vary)]
		force = [int(d.force_x), int(d.force_y)]
		velocity = [int(d.velocity_x), int(d.velocity_y), int(d.velocity_varx), int(d.velocity_vary)]
		last = clock
		for i in int(d.max):
			particles.append([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
		tick(clock)

	static func _trunc_div(a: int, b: int) -> int:
		return a / b if a >= 0 else -((-a) / b)

	static func _lerp(base: int, target: int, now: int, start: int, finish: int) -> int:
		return (target - base) * (now - start) / (finish - start) + base

	static func _int16(v: int) -> int:
		v &= 0xffff
		return v - 0x10000 if v >= 0x8000 else v

	## A spread roll: 0x458e70(1, 2v + 1, -1 - v), the result taken as a 16-bit value.
	func _spread(v: int) -> int:
		return _int16(rng.roll(1, _int16(2 * v + 1), -1 - v))

	## 0x545b90. `visible`: the emitter's cell is inside the view (the original skips everything after the timers when it
	## is not). Returns false when a temporary emitter is over.
	func tick(clock: int, visible: bool = true) -> bool:
		var delta := clock - last
		age += delta
		last = clock
		var move := age >= next_move
		if move: next_move = age + 25
		var forced := age >= next_force
		if forced: next_force = age + 50
		var release := false
		if age >= next_release and (int(d.total) == 0 or released < int(d.total)):
			release = true
			next_release = age + int(d.interval)
		if int(d.temporary) != 0 and age > int(d.lifetime):
			return false
		if not visible:
			return true
		var t := clock
		var s: int
		var e: int
		e = int(d.anim_velocity_end)
		s = int(d.anim_velocity_start)
		if e != 0 and move and t > s and t <= e:
			velocity = [_lerp(int(d.velocity_x), int(d.anim_velocity_x), t, s, e), _lerp(int(d.velocity_y), int(d.anim_velocity_y), t, s, e),
				_lerp(int(d.velocity_varx), int(d.anim_velocity_varx), t, s, e), _lerp(int(d.velocity_vary), int(d.anim_velocity_vary), t, s, e)]
		e = int(d.anim_force_end)
		s = int(d.anim_force_start)
		if forced and e != 0 and t > s and t <= e:
			force = [_lerp(int(d.force_x), int(d.anim_force_x), t, s, e), _lerp(int(d.force_y), int(d.anim_force_y), t, s, e)]
		e = int(d.anim_emitter_end)
		s = int(d.anim_emitter_start)
		if e != 0 and t > s and t <= e:
			emitter = [_lerp(int(d.emitter_x), int(d.anim_emitter_x), t, s, e), _lerp(int(d.emitter_y), int(d.anim_emitter_y), t, s, e),
				_lerp(int(d.emitter_varx), int(d.anim_emitter_varx), t, s, e), _lerp(int(d.emitter_vary), int(d.anim_emitter_vary), t, s, e)]
		e = int(d.anim_end)
		s = int(d.anim_start)
		if e != 0 and t > s and t <= e:
			colour = [_lerp(int(d.red), int(d.anim_red), t, s, e), _lerp(int(d.green), int(d.anim_green), t, s, e),
				_lerp(int(d.blue), int(d.anim_blue), t, s, e)]
		for i in used:
			var p: Array = particles[i]
			if p[ALIVE] == 0: continue
			p[AGE] += delta
			if p[AGE] > int(d.life):
				p[ALIVE] = 0
				alive -= 1
		var ps := int(d.anim_pforce_start)
		var pe := int(d.anim_pforce_end)
		for i in used:
			var p: Array = particles[i]
			if p[ALIVE] == 0: continue
			var a: int = p[AGE]
			if e != 0 and a > s and a <= e:
				p[FRAME] = int(d.frame) + _int16((int(d.anim_frame) - int(d.frame)) * (a - s) / (e - s))
				p[ALPHA] = ((int(d.anim_alpha) - int(d.alpha)) * (a - s) / (e - s) & 0xff) + (int(d.alpha) & 0xff)
			if forced:
				if pe != 0 and a > ps and a <= pe:
					p[PFX] = _lerp(int(d.pforce_x), int(d.anim_pforce_x), a, ps, pe)
					p[PFY] = _lerp(int(d.pforce_y), int(d.anim_pforce_y), a, ps, pe)
				p[VX] += force[0] + p[PFX]
				p[VY] += force[1] + p[PFY]
			if move:
				p[X] += p[VX]
				p[Y] += p[VY]
		var maximum := int(d.max)
		if release and alive < maximum and (int(d.total) == 0 or released < int(d.total)):
			var count: int = mini(int(d.release), maximum - alive)
			for n in count:
				var slot := -1
				for c in maximum:
					if particles[c][ALIVE] == 0:
						slot = c
						break
				used = maxi(used, slot + 1)
				if slot < 0: continue
				var p: Array = particles[slot]
				p[ALIVE] = 1
				p[ALPHA] = int(d.alpha)
				p[RED] = int(_int16(rng.roll(1, 100, 0)) < int(d.red))
				p[GREEN] = int(_int16(rng.roll(1, 100, 0)) < int(d.green))
				p[BLUE] = int(_int16(rng.roll(1, 100, 0)) < int(d.blue))
				p[AGE] = 0
				p[X] = emitter[0] + _spread(_int16(emitter[2]))
				p[Y] = emitter[1] + _spread(_int16(emitter[3]))
				p[SHEET] = sheet
				p[PFX] = int(d.pforce_x)
				p[PFY] = int(d.pforce_y)
				p[VX] = velocity[0] + _spread(_int16(velocity[2]))
				p[VY] = velocity[1] + _spread(_int16(velocity[3]))
				p[FRAME] = int(d.frame)
				alive += 1
				released += 1
		return true

## The match's emitters: one per EFFH record whose id names a definition (0x486980 skips unknown ids).
var emitters: Array = []

func _init(effects: Array, definitions: Dictionary, clock: int, seed_first: int = 0x1badb002, seed_second: int = 0x2468ace0):
	for i in effects.size():
		var r: Dictionary = effects[i]
		var d: Dictionary = definitions.get(String(r.name), {})
		if d.is_empty(): continue
		var p: Array = r.world_position
		# Each emitter gets its own generator, seeded apart so neighbouring emitters do not move in step.
		emitters.append(Emitter.new(d, Vector2i(int(p[0]), int(p[1])), clock, CombatRng.new(seed_first + i, seed_second)))

func tick(clock: int):
	var keep: Array = []
	for em in emitters:
		if em.tick(clock): keep.append(em)
	emitters = keep
