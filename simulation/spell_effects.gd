extends RefCounted
## The 0x1f7 spell record applier (SPELLS_RESEARCH.md; Emulated by tools/emulate_spells.py -> tests/spell_fixtures.json).
## A record built by one of the spell functions (spells.gd) runs through 0x4ac0e0 twice in the original: an area record
## (+3 != 0) goes to 0x4aa840 on the host, which gathers the targets, applies the immediate part of its kind, sends the
## create messages and re-broadcasts the record with +3 = 0; that copy runs the per-kind part on every machine. The
## rebuild is one machine, so `apply` runs both stages in order. B1-6 adds kinds here, one handler per kind.
##
## The world is the Spells object (spells.gd): objects in a row of the map grid, cells, hit points, unit mana, the hero
## pool, damage, spawning, missiles, mine reserves and the match generator.

const Rules = preload("res://simulation/combat_rules.gd")

const MAX_TARGETS := 24              # 0x4aa840: the gather stops after 24 targets (+0xd / +0x25 / +0xc9 / +0xf9 hold 24)
const DRAIN_MANA := 1                # Harpy 0x96
const HEAL := 2
const HEAL_CURE := 0x14              # Cure: heal, and clear poison / the +0x19e state
const SUMMON := 6                    # Fire Elemental, Summon Imp, Stonecall, Vampire bats
const MISSILES := 0x10               # Doomstones: one missile per target
const DAMAGE := 0x13                 # Ring of Fire: damage through the missile armour reduction 0x42bbf0
const RAISE := 0x15                  # Call the Dead: summon at corpse cells, the corpses near the caster go
const SWORDS := 0x27                 # G-2 Sword of Sirian (0x57a3b0): as RAISE; 0x4ada90 also gets its "dead sprites" flag (Read)
const FAMINE := 0x24                 # drain a random enemy mine
const STATUS_ONLY := 100             # Naga -1: no kind handler, only the record's status descriptors
## B1-6a (Necromancy, Runes; tests/hero_spell_fixtures.json): kind 0 has no handler either (the tail only: Vampirism,
## Stoneskin, Dig, Resist Magic, Resist Missile, Gem of Wisdom).
const SACRIFICE := 0x1b               # B4-1: the Dark Elves' Sacrifice: the targets die, a Daemon may rise (spells.apply_sacrifice)
const DAY_NIGHT := 4                # Darkstorm (and B1-3's Dark Citadel / Rites of Dawn): B1-3's DayNight.apply_record
const BUILDING := 7                  # Black Portal, Summon Guardian: message 0x1f9, a timed building
const SCAVENGE := 0x1c               # B1-3's Zombie scavenging: credit, then the remains within +0x99 go
const SALVAGE := 0x21                # B3-2: the Bronze Golem's Salvage: credit only (the debris stays)
const STRIP_FLESH := 0x25            # Strip Flesh: low-level enemy units become their owner's Skeletons
## 0x528280(0): types Strip Flesh never turns (sheep, cows, goats, people, camels, souls, turtles, seals).
const CRITTERS := ["ACSH", "ACCO", "ACGO", "ACPE", "ACCA", "ACSO", "ACTU", "ACSE"]
## B1-6b (Healing, Pyromancy, Ice, Poison; tests/hero_spell_b_fixtures.json, tools/emulate_hero_spells_b.py):
const ANTIDOTE := 3                  # Antidote: poison and disease cleared (0x4ac0e0 case 3, the cure half of 0x14)
const RESURRECT := 5                 # Resurrection: a dead unit's type stands again for the caster's owner (0x4aa840 case 5)
const AFFLICT := 0xd                 # Poison Cloud (amount 4 poison, 5 disease; 0..3 Illusion's fear statuses)
const SOUL_FLAME := 0x11             # experience + min(amount, +0x9b - experience) while below +0x9b (0x527100)
const BERSERK := 0x16                # Berserker: the berserk state 0x527720(amount)
const CALM := 0x1d                   # Calm: +0xba cleared and every status removed (0x577480)
const MANA_GATE := 0x1e              # Freeze Magic: 0x7494c4 = amount until now + +0x89 (no mana regeneration below 1)
const ROT := 0x26                    # Rot: poisoned units below the amount drop to max / 8 hit points
## B1-6c (Nature, Divination, Arcane; tests/hero_spell_c_fixtures.json, tools/emulate_hero_spells_c.py):
const BANISH := 0x17                 # Banish: summoned enemy units below the amount die unless their owner has PBIN
const PSYCHIC_BLAST := 0x28          # Psychic Blast: message 0x221 -> 0x527d10: status 0x46 (combat 1) for amount s
const STATUS_STUNNED := 0x46         # 0x51bd10 returns 1 while it is active (Read)
## B1-6d (Summoning, Illusion; tests/hero_spell_d_fixtures.json, tools/emulate_hero_spells_d.py):
const SHADOW := 0xc                  # Shadowform / Phantom Steed: 0x528570 (+0x1e4..+0x1e8: speed, armour, magic armour)
const INVISIBLE := 0xe               # Invisibility: 0x5285b0(1, until) (+0x1f1 / +0x1f4)
const TELEPORT := 0x12               # Blink / Home Portal: the host's reachable free cell (0x530a90), then the unit moves
const ILLUSIONS := 0x18              # Spectral Horde / Dragonfear: summons named "Illusion_Data_Only" (0x43c450, +0x1f0)
const MUTATE := 0x19                 # Mutate: low-level enemy units become animals of the neutral player 6
const TRANSFORM := 0x1a              # Transform: own units morph (0x4a91d0 -> message 0x1f4) into TRANSFORM_TYPES[+0x99]
## B1-6e (Alchemy, Chaos; tests/hero_spell_e_fixtures.json, tools/emulate_hero_spells_e.py):
const MORPH := 0x1f                  # the Morphs: +0x9b added to a stat (+0x99) of every living target, clamped
const INCREASE_CASTING := 0x20       # Increase Casting: the local player completes PSPR (0x436500 -> 0x438180)
const PLAGUE := 0x22                 # Chaos Plague: hit points x +0x99 / 100 (host), then disease (0x51c1b0 / 0x51c060)
const METEORS := 0x23                # B5-1: Couatl's Wrath: +0x99 meteors round the temple (spells.apply_meteors)
## Kind 0xd amounts 0..3 -> 0x528a40's argument (the fear bit of +0xba): Scare 0 -> 1, 1 -> 2 (flee), 2 -> 8, Awe 3 -> 4.
const FEAR_BITS := [1, 2, 8, 4]
## 0x60e58c (Read from the image; Emulated through 'transform seed n'): the 21 types +0x99 (0..20) picks.
const TRANSFORM_TYPES := ["AOSX", "AKIX", "AHIX", "AEIX", "AOIX", "ABIX", "AUJX", "AHMX", "AMIX", "AULX", "ADJX", "AUMX", "AHGW",
	"AKNX", "ABGX", "AMMX", "AHGR", "AEGX", "AWGX", "ADGX", "AGGX"]
const NEUTRAL := 6                   # Mutate's animals belong to player 6 (0x5341a0(6), the 0xfa owner)
## 0x40f620 (Emulated through the missile constructor's arguments): the missile a spell record's +0x129 creates when it
## differs from the art itself (the art stays the missile's +0x13c). EMIS / EMAP Emulated; the rest of 0x40f620's table
## Read by REVIEW_HERO_SPELLS_B.md F6.
const SPELL_MISSILE_IDS := {"EMIS": "EDUM", "EMAP": "EMA0", "EMIF": "EDUM", "EMFP": "EMA2", "EMS0": "EMM3", "EMMF": "EMC1",
	"EMTF": "EMF0", "EMTM": "EMM0"}

## Fills record.targets (0x4aa840 head, Emulated): only when the radius +8 is set. The rows y - r .. y + r - 1 of the
## object grid are scanned (row y + r is not: the end is exclusive, clamped to the map height - 1), each object then
## needs dx^2 + dy^2 <= r^2 from the caster's cell. Filters: +0xa object kind (1 units only, 2 buildings only), +9
## alliance (1 allies only, 2 enemies only; allied = same owner or the relation table), +0xb 0 excludes the caster,
## +0xc hit points (1 dead only, 2 alive and hurt, 3 at full health, 4 alive), unit STATUS masks +0x135 (any bit
## needed) / +0x131 (no bit allowed).
static func gather(record: Dictionary, world) -> bool:
	var caster: Dictionary = world.object_of(String(record.caster_kind), int(record.caster))
	if caster.is_empty(): return false
	var r: int = int(record.radius)
	if r <= 0: return true
	var c: Vector2i = caster.cell
	var y_end: int = mini(c.y + r, world.map_size().y - 1)
	var out: Array = []
	var dead := int(record.b12) == 1                 # B1-6b: Resurrection looks for the dead (the rebuild's corpses)
	for y in range(maxi(0, c.y - r), y_end):
		if out.size() > MAX_TARGETS - 1: break
		for o in (world.row_objects(y, true) if dead else world.row_objects(y)):
			if not _accepts(record, o, caster, world): continue
			var d: Vector2i = o.cell - c
			if d.x * d.x + d.y * d.y > r * r: continue
			out.append(o)
			if out.size() > MAX_TARGETS - 1: break
	record.targets = out
	return true

static func _accepts(record: Dictionary, o: Dictionary, caster: Dictionary, world) -> bool:
	var kinds := int(record.b10)
	if o.kind == "unit" and kinds == 2: return false
	if o.kind == "building" and kinds == 1: return false
	var ally: bool = world.allied(int(o.owner), int(record.owner))   # RELATIONS[target + 7 x owner] (0x4aa840, REVIEW D5)
	if ally and int(record.b9) == 2: return false
	if not ally and int(record.b9) == 1: return false
	if o.kind == "unit":
		var status := int(o.get("status", 0))
		if int(record.d135) != 0 and status & int(record.d135) == 0: return false
		if int(record.d131) != 0 and status & int(record.d131) != 0: return false
	if int(record.b11) == 0 and o.kind == caster.kind and int(o.id) == int(caster.id): return false
	# B1-6b (decompile 4aa840, Emulated by Calm 'statuses'): kind 0x1d skips units with +0xba = 0 and no status entry.
	if int(record.kind) == CALM and o.kind == "unit" and not world.has_effects(o): return false
	# B1-6e (decompile 4aa840 at the 0x1f test; Emulated, fixtures 93 / 94): the Morphs skip a building whose BUI damage
	# (+0x38, 0x69778c) is below 1 and, for damage (+0x99 3), a unit whose damage +0x9e is below 1.
	if int(record.kind) == MORPH and not world.morph_target(o, int(record.amount)): return false
	var hp := int(o.hp)
	match int(record.b12):
		1: if hp > 0: return false
		2: if hp <= 0 or int(o.max_hp) <= hp: return false
		3: if hp < int(o.max_hp): return false
		4: if hp < 1: return false
	return true

## Both stages of one record. Returns what happened (for tests, the HUD text and the sound layer).
static func apply(record: Dictionary, world) -> Dictionary:
	var result := {"kind": int(record.kind), "targets": [], "damage": [], "healed": [], "drained": [], "summoned": [],
		"missiles": [], "statuses": [], "famine": {}, "removed_corpses": [], "affected": [], "stripped": [], "resisted": [],
		"buildings": [], "credited": [], "looks": [], "resurrected": [], "afflicted": [], "experience": [], "berserk": [],
		"calmed": [], "rotted": [], "cured": [], "banished": [], "moved": [], "mutated": [], "transformed": [], "frightened": [],
		"morphed": []}
	# B4-1 (BATCH4_RESEARCH.md E7, Emulated "sacrifice_applied"): kind 0x1b has no caster object and lists its targets itself.
	if int(record.kind) == SACRIFICE:
		result.merge(world.apply_sacrifice(record), true)
		return result
	if not gather(record, world): return result
	var kind := int(record.kind)
	var targets: Array = record.get("targets", [])
	# B1-6d (Emulated, fixtures 39 'transform'): kind 0x1a caps +0x9b at 30 and the target count at +0x9b (0x4aa840).
	if kind == TRANSFORM:
		record.w9b = mini(int(record.w9b), 30)
		if targets.size() > int(record.w9b): targets = targets.slice(0, int(record.w9b))
		record.targets = targets
	# --- the host stage (0x4aa840 switch)
	match kind:
		HEAL, HEAL_CURE:
			# The new hit points min(hp + amount, max) per target, stored over +0x99 (the per-kind stage applies them).
			var to: Array = []
			for o in targets: to.append(mini(int(o.hp) + int(record.amount), int(o.max_hp)))
			record["heal_to"] = to
		DAMAGE:
			for o in targets:
				var block: Dictionary = world.armour_block(o)
				var dealt := Rules.armour_tail(int(record.amount), int(record.w9b), int(record.w9d), Rules.armour_table(block), Rules.resist_flags(block))
				# B1-6b (Emulated: Ring of Fire / Ring of Ice / Armageddon 'tough', B1-4 S5): a building takes the full amount (the
				# block its vtable +0x48 fills reduces nothing; Read for other building types than BKH0).
				if o.kind == "building": dealt = int(record.amount)
				if dealt == Rules.FAULT_DAMAGE: continue
				world.damage(o, dealt, record)
				result.damage.append({"kind": o.kind, "id": o.id, "amount": dealt})
		SUMMON, RAISE, ILLUSIONS, SWORDS:      # 0x4aa840 cases 6 / 0x15 / 0x18 / 0x27 share the summon loop (G-2, Read)
			result.summoned = _summon(record, world)
		TELEPORT:
			# B1-6d (Emulated, fixtures 13 / 16; 0x530a90 itself Read): per living unit target, the cell becomes the free
			# cell nearest the record's cell that the target can reach from its own cell (its movement type and extent).
			var cells: Array = record.get("cells", [])
			for i in targets.size():
				var o: Dictionary = targets[i]
				if o.kind != "unit" or int(o.hp) < 1 or i >= cells.size(): continue
				cells[i] = world.reachable_cell(o, cells[i])
			record.cells = cells
		MUTATE:
			# B1-6d (Emulated, fixtures 38 'mutate' / 'mixed'; decompile 4aa840 case 0x19): a living unit below the amount
			# (0x526d80), not a hero and not an animal (0x528280(0)), vanishes without remains (0x4a9890 -> 0x1fb) and an
			# animal of player 6 stands at the free cell nearest it (0x43b4c0 radius 1, message 0xfa): ACSH for an even target
			# index, ACPE for an odd one; a flyer (STATUS bits 30 / 31) ACCA / ACCO; STATUS bit 21 ACGO. Any other living unit
			# resists (0x222).
			for i in targets.size():
				var o: Dictionary = targets[i]
				if o.kind != "unit" or int(o.hp) < 1: continue
				var f = world.combat.fighters.get(int(o.id))
				if f == null: continue
				if world.unit_level(o) < int(record.amount) and not bool(o.hero) and not String(f.type_id) in CRITTERS:
					var status := int(o.get("status", 0))
					var odd := (i >> 1) != (i + 1) / 2
					var animal := "ACPE" if odd else "ACSH"
					if status & 0xc0000000: animal = "ACCO" if odd else "ACCA"
					if status >> 21 & 1: animal = "ACGO"
					var made: Dictionary = world.mutate(o, animal)
					if not made.is_empty(): result.mutated.append(made)
				else:
					result.resisted.append(o.id)
		TRANSFORM:
			# B1-6d (Emulated, fixtures 39; decompile 4aa840 case 0x1a): each living unit target (capped above), not an illusion
			# (+0x1f0), not an animal and not a hero, morphs at its cell into TRANSFORM_TYPES[+0x99] (0x4a91d0 -> message
			# 0x1f4 -> 0x4a8ff0). The +0x211 test has no rebuild state (Open).
			var amount := clampi(int(record.amount), 0, TRANSFORM_TYPES.size() - 1)
			for o in targets:
				if o.kind != "unit" or int(o.hp) < 1 or bool(o.hero): continue
				var f = world.combat.fighters.get(int(o.id))
				if f == null or bool(f.get("illusion", false)) or String(f.type_id) in CRITTERS: continue
				var made: Dictionary = world.transform(o, String(TRANSFORM_TYPES[amount]))
				if not made.is_empty(): result.transformed.append(made)
		PLAGUE:
			# B1-6e (Emulated, fixtures 99 'plague'; decompile 4aa840 case 0x22): each unit target's vtable +0x38 (0x522af0,
			# the hit-point setter) with +0x99 x hit points / 100 and the caster as the attacker: 0 kills.
			for o in targets:
				if o.kind != "unit" or int(o.hp) < 1: continue
				var to: int = (int(record.amount) * int(o.hp)) / 100
				# REVIEW_HERO_SPELLS_E.md D5 (Read): 0x522af0 then 0x522860 react as to a hit (the caster's drain, the AI's
				# attacker record, the kill): the loss goes through the damage path.
				world.damage(o, int(o.hp) - to, record)
				result.damage.append({"kind": o.kind, "id": o.id, "hp": to})
		MISSILES:
			record.w9f = world.roll(1, 100, 0)            # host roll into +0x9f, copied to the caster's +0x228 (Emulated, REVIEW D1)
		FAMINE:
			var mines: Array = world.famine_candidates(int(record.owner))
			if mines.is_empty(): return result                  # 0x4aa840 returns: nothing re-broadcast
			var pick: int = world.roll(1, mines.size(), -1)
			targets = [mines[pick]]
			record.targets = targets
		STRIP_FLESH:
			# B1-6a (Emulated, fixtures 'strip'): a living non-hero unit below the amount (0x526d80: rank, a hero's level),
			# not a critter (0x528280(0)), loses its flesh; any other unit resists (message 0x222).
			for o in targets:
				if o.kind != "unit" or int(o.hp) < 1: continue
				if world.unit_level(o) < int(record.amount) and not bool(o.hero) and not String(world.combat.fighters[int(o.id)].type_id) in CRITTERS:
					var made: Dictionary = world.strip_flesh(o, record)
					if not made.is_empty(): result.stripped.append(made)
				else:
					result.resisted.append(o.id)
		RESURRECT:
			# B1-6b (Emulated, fixtures 9 'dead'): per dead unit target (the gather's +0xc = 1), while the caster's owner has
			# command left (read as it stands: the created units arrive later as 0xfa), a new unit of the target's type for
			# the caster's owner at the free cell nearest the body (0x43b4c0), with the body's experience 0x526db0 (R-1); the
			# body stays. The +0x1f0 / +0x1ec tests on the body are Open (no rebuild state).
			var free: bool = world.command_free(int(record.owner))
			for o in targets:
				if o.kind != "unit" or int(o.hp) > 0: continue
				# B1-6d (Read, decompile 4aa840 case 5 / disassembly 0x4aae28): an illusion's body (+0x1f0) or a timed summon's
				# (+0x1ec) does not rise (B1-6b Open 7's body tests).
				var body = world.combat.fighters.get(int(o.id))
				if body != null and (bool(body.get("illusion", false)) or bool(body.get("timed", false))): continue
				if not free: break
				var made: Dictionary = world.resurrect(o, record)
				if not made.is_empty(): result.resurrected.append(made)
		ROT:
			# B1-6b (Emulated, fixtures 108 'poison'): a living unit below the amount (0x526d80) that is poisoned drops to
			# max / 8 hit points when above it; B1-6e (Emulated, tests/hero_spell_e_fixtures.json "rot"): a diseased one's
			# disease level +0x19d becomes max(0x51c460(1), 0x51bd10(1)) (0x529e30); a unit at or above the amount that is
			# poisoned or diseased resists (message 0x222).
			for o in targets:
				if o.kind != "unit" or int(o.hp) < 1: continue
				var f = world.combat.fighters.get(int(o.id))
				if f == null: continue
				var sick: bool = bool(f.get("poisoned", false)) or bool(f.get("diseased", false))
				if world.unit_level(o) < int(record.amount):
					if bool(f.get("poisoned", false)):
						var floor_hp := int(o.max_hp) / 8
						if floor_hp < int(o.hp):
							world.set_hp(o, floor_hp)
							result.rotted.append({"id": o.id, "hp": floor_hp})
					if bool(f.get("diseased", false)): world.rot_disease(f)
				elif sick:
					result.resisted.append(o.id)
		BANISH:
			# B1-6c (Emulated, fixtures 114 'banish' / 'banish pbin'; decompile 4aa840 case 0x17): a unit target whose owner
			# lacks PBIN (0x437f70) and whose level 0x526d80 is below the amount loses its hit points (vtable +0x38(0, caster));
			# any other unit target resists (message 0x222). The gather's +0x135 = 0x2000 keeps it to summoned units.
			for o in targets:
				if o.kind != "unit": continue
				if not world.has_research(int(o.owner), "PBIN") and world.unit_level(o) < int(record.amount):
					world.damage(o, int(o.hp), record)
					result.banished.append(o.id)
				else:
					result.resisted.append(o.id)
		PSYCHIC_BLAST:
			# B1-6c (Emulated, fixtures 119 incl. the 0x221 handler 0x4a9b40 -> 0x527d10; REVIEW_HERO_SPELLS_C.md R4 / D3):
			# each living unit target gets 0x46 = 10 for amount x 1000 ms (art 0); 0x5773b0 replaces an older entry of the same
			# kind and art (add_status), so a later, shorter blast shortens the stun (0x577560's lookup there is unused).
			for o in targets:
				if o.kind != "unit" or int(o.hp) < 1: continue
				var stun := {"kind": STATUS_STUNNED, "value": 10, "until": world.now() + int(record.amount) * 1000, "art": 0}
				if world.add_status(o, stun): result.statuses.append({"id": o.id, "status": stun})
		BUILDING:
			# B1-6a: message 0x1f9 (Emulated) -> 0x4a7200 (Read): the record's type at its cell for +0x89 ms.
			var cells: Array = record.get("cells", [])
			if not cells.is_empty():
				var made: Dictionary = world.create_spell_building(String(record.summon), cells[0], int(record.owner), int(record.d89))
				if not made.is_empty(): result.buildings.append(made)
	result.targets = targets.map(func(o): return {"kind": o.kind, "id": o.id, "owner": o.owner, "cell": o.cell})
	# --- the per-kind stage (0x4ac0e0 switch); `affected` is 0x4ac0e0's per-target flag array
	var affected: Array = []
	for o in targets: affected.append(int(record.b4) != 0)
	match kind:
		METEORS:
			# B5-1 (BATCH5_RESEARCH.md E5, Open 1; Emulated "abilities", tests/batch5_meteor_fixtures.json): the meteors at the
			# fixed offsets; the target list is not used.
			result.merge(world.apply_meteors(record), true)
		DRAIN_MANA:
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or int(o.hp) < 1: continue
				var taken: int = world.drain_mana(o, int(record.amount))
				if taken < 0: continue                            # a unit without mana (+0x20a < 1)
				affected[i] = true
				result.drained.append({"id": o.id, "amount": taken})
		HEAL, HEAL_CURE:
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty(): continue
				if int(o.hp) < int(o.max_hp): affected[i] = true
				var to: int = int(record.heal_to[i])
				# B1-6a (Emulated, Earthpower 'buildings'): a building's 0x52e0b0 ADDS the stored value to its hit points
				# (capped at the maximum); a unit's 0x526700 sets it.
				if o.kind == "building": to = mini(int(o.hp) + to, int(o.max_hp))
				if to != int(o.hp):
					var before := int(o.hp)                       # P-2: presentation only (the "Healing %d" float)
					world.set_hp(o, to)
					result.healed.append({"kind": o.kind, "id": o.id, "hp": to, "from": before})
				if kind == HEAL_CURE and o.kind == "unit" and world.cure(o): affected[i] = true
		ANTIDOTE:
			# B1-6b (Emulated, fixtures 103 'poison'): units that are poisoned or diseased are flagged and cured of both.
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit": continue
				if world.cure(o):
					affected[i] = true
					result.cured.append(o.id)
		AFFLICT:
			# B1-6b (Emulated, fixtures 101): living non-hero units; amount 4 poisons a unit that 0x51c130 allows, 5 diseases
			# one 0x51c1b0 allows; 0..3 (Illusion's fear statuses 0x528a40) are not this part's (Open).
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1 or bool(o.hero): continue
				match int(record.amount):
					0, 1, 2, 3:
						# B1-6d (Emulated, fixtures 31 / 33 'fear'): 0x528a40(FEAR_BITS[amount]) (Spells.frighten).
						if world.frighten(o, int(FEAR_BITS[int(record.amount)])):
							affected[i] = true
							result.frightened.append(o.id)
					4:
						if world.poison(o):
							affected[i] = true
							result.afflicted.append(o.id)
					5:
						if world.disease(o):
							affected[i] = true
							result.afflicted.append(o.id)
		SOUL_FLAME:
			# B1-6b (Emulated, fixtures 51 'ranks'): a living non-hero unit whose experience is below +0x9b gains
			# min(amount, +0x9b - experience) (0x527100 -> 0x40da20, with its promotions: Combat.gain_experience); only those
			# are flagged for the tail.
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1: continue
				var gained: int = world.add_experience(o, int(record.amount), int(record.w9b))
				if gained > 0:
					affected[i] = true
					result.experience.append({"id": o.id, "gained": gained})
		BERSERK:
			# B1-6b (Emulated, fixtures 56 'mixed'): every living target enters the berserk state 0x527720(amount) and is
			# flagged (the tail then adds combat 1 and speed 5).
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1: continue
				world.berserk(o, int(record.amount))
				affected[i] = true
				result.berserk.append(o.id)
		CALM:
			# B1-6b (Emulated, fixtures 83 'statuses'): living units of either side lose +0xba and every status effect; no
			# target is flagged.
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1: continue
				world.calm(o)
				result.calmed.append(o.id)
		SHADOW:
			# B1-6d (Emulated, fixtures 12 'cavalry', 30): 0x528570(now + +0x89, +0x9d, +0x99, +0x9b) on each living target:
			# +0x1e4 = 1, speed + +0x99 (+0x1e5), armour + +0x9d (+0x1e6), magic armour + +0x9b (+0x1e7) until +0x1e8.
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1: continue
				world.shadow(o, int(record.amount), int(record.w9d), int(record.w9b), world.now() + int(record.d89))
				affected[i] = true
		INVISIBLE:
			# B1-6d (Emulated, fixtures 36): 0x5285b0(1, now + +0x89) on each living target (+0x1f1 / +0x1f4).
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1: continue
				world.set_invisible(o, world.now() + int(record.d89))
				affected[i] = true
		TELEPORT:
			# B1-6d (Emulated, fixtures 13 / 16): a living target whose cell is inside the map (both words > 0) moves there
			# (0x493940, 0x51bb80(0), 0x5351d0; its order goes).
			var cells: Array = record.get("cells", [])
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1 or i >= cells.size(): continue
				var cell: Vector2i = cells[i]
				if cell.x <= 0 or cell.y <= 0: continue
				affected[i] = true
				world.teleport(o, cell)
				result.moved.append({"id": o.id, "cell": cell})
		MORPH:
			# B1-6e (Emulated, fixtures 90-94 'morph' / 'towers' under seeds; decompile 4ac0e0 case 0x1f): every living target
			# is flagged; a unit's +0x92 combat / +0x94 speed (1..99), +0x98 / +0x9c hit points / +0x9e damage (1..999), a
			# building's +0x68 / +0x6a (1..99), +0x6e / +0x82, +0x7c (1..999) gain +0x9b.
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or int(o.hp) < 1: continue
				affected[i] = true
				world.morph(o, int(record.amount), int(record.w9b))
				result.morphed.append({"kind": o.kind, "id": o.id, "stat": int(record.amount), "change": int(record.w9b)})
		INCREASE_CASTING:
			# B1-6e (Emulated, fixtures 97 under seeds and 'remote'): only the caster's own machine (the local player).
			result["school"] = world.increase_casting(int(record.owner))
		PLAGUE:
			# B1-6e (Emulated, fixtures 99): every living target is flagged; 0x51c1b0 allowing, 0x51c060(1) diseases it.
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or o.kind != "unit" or int(o.hp) < 1: continue
				affected[i] = true
				if world.disease(o): result.afflicted.append(o.id)
		MANA_GATE:
			world.set_mana_gate(int(record.amount), world.now() + int(record.d89))   # B1-6b: Freeze Magic (Emulated globals)
		DAY_NIGHT:
			world.day_night_record(int(record.amount))           # B1-6a: Darkstorm 3 (0x4ac0e0 case 4)
		SCAVENGE:
			# B1-6a (Emulated, fixtures "scavenge"): 0x43e9b0 credits +0x9b gold, +0x9d metal, +0x9f crystal, +0xa1 stone,
			# then 0x4ada90 removes the remains within +0x99 of the Zombie.
			var amounts := [int(record.w9b), int(record.w9d), int(record.w9f), int(record.get("wa1", 0))]
			world.credit(int(record.owner), amounts)
			result.credited = amounts
			result.removed_corpses = world.remove_corpses_around(int(record.caster), int(record.amount))
		SALVAGE:
			# B3-2 (E16a): 0x43e9b0 credits +0x9b gold, +0x9d metal, +0x9f stone, +0xa1 crystal (the lanes named by Salvage's message
			# lines 0x77..0x7a and its dice; the rebuild's lanes are gold, metal, crystal, stone). Nothing is removed.
			var amounts := [int(record.w9b), int(record.w9d), int(record.get("wa1", 0)), int(record.w9f)]
			world.credit(int(record.owner), amounts)
			result.credited = amounts
		MISSILES:
			for i in targets.size():
				var o: Dictionary = world.object_of(targets[i].kind, int(targets[i].id))
				if o.is_empty() or int(o.hp) < 1: continue
				affected[i] = true
				result.missiles.append(world.launch_spell_missile(record, o))
		DAMAGE, BANISH, PSYCHIC_BLAST:
			for i in targets.size(): affected[i] = true          # 0x4ac0e0 cases 0x13 / 0x17 / 0x28 flag every target
		RAISE:
			result.removed_corpses = world.remove_corpses_near(int(record.caster), int(record.w9f))
		SWORDS:
			# G-2 (Read): 0x4ac0e0 case 0x27 -> 0x4ada90(caster cell, +0x9f, 1, 1): the remains within +0x9f of the Shrine go; the
			# second flag (sprites of dead objects, the ruins) has no counterpart in the rebuild (Open, as the Zombie's ruins).
			result.removed_corpses = world.remove_corpses_at(world.object_of(String(record.caster_kind), int(record.caster)).get("cell", Vector2i(-1, -1)), int(record.w9f))
		FAMINE:
			var o: Dictionary = targets[0]
			var before: int = world.mine_reserve(int(o.id))
			if before > 1:
				var after := maxi(1, before - int(record.amount))
				world.set_mine_reserve(int(o.id), after)
				result.famine = {"mine": o.id, "owner": o.owner, "drained": before - after}
	# --- the common tail: status descriptors (+4 count, 24 bytes each from +0x55, until now + duration +0x89)
	var descriptors: Array = record.get("descriptors", [])
	for i in targets.size():
		if not affected[i]: continue
		result.affected.append({"kind": targets[i].kind, "id": targets[i].id})
		for d in descriptors:
			var status := {"kind": int(d[0]), "value": int(d[1]), "until": world.now() + int(record.d89), "art": int(record.b6)}
			if d.size() > 2: status["data"] = d.slice(2)   # B1-6b: the descriptor's other four words (0x17: damage, type, range)
			if world.add_status(targets[i], status): result.statuses.append({"id": targets[i].id, "status": status})
		# B1-6a: +0x97 >= 0 (Stoneskin 6, Resist Magic 7): the node's look +0x132 until now + +0x89 (Emulated values).
		if int(record.w97) >= 0 and world.has_method("set_look"):
			world.set_look(targets[i], int(record.w97), world.now() + int(record.d89))
			result.looks.append({"id": targets[i].id, "look": int(record.w97)})
	return result

## 0x4aa840 cases 6 / 0x15 (Emulated): for every cell of the record (count +0x99, cells +0xc9 / +0xf9), another player
## may take the summon first: players 0..5 other than the caster's, active, not eliminated, with a living hero and free
## command, each draw 1..100 and the first draw <= its hero's effect 0x28 + item power 0x28 takes it. Then the loop ends
## when the new owner's command is full (the counts are read as they stand: the created units arrive later as message
## 0xfa, so one cast can exceed the limit), the cell goes through the free-cell finder 0x43b4c0 (radius +0x9d) and the
## unit is created with +0x9b as its experience.
static func _summon(record: Dictionary, world) -> Array:
	var out: Array = []
	var cells: Array = record.get("cells", [])
	# owner -> command free when the cast was applied; B1-6b: shared by the records of one cast (Call of Kargoth's two
	# records both see the counts as they stood, Emulated 'command one left': 16 units at 39 of 40)
	var free: Dictionary = record.get("free_cache", {})
	var eligible := {}                               # thief candidate -> eligible when the cast was applied
	for i in mini(int(record.amount), cells.size()):
		var owner := int(record.owner)
		for p in 6:
			if p == int(record.owner): continue
			if not eligible.has(p): eligible[p] = world.summon_thief_eligible(p)   # counts as they stand (REVIEW D10)
			if not eligible[p]: continue
			if world.roll(1, 100, 0) <= world.summon_steal_chance(p):
				owner = p
				break
		if not free.has(owner): free[owner] = world.command_free(owner)
		if not free[owner]: break
		# B1-6d (Emulated, fixtures 15 / 34 / 35): the 0xfa lifetime +0x33 = the record's +0x89 (0x4a49e0 -> +0x1ec: the unit
		# dies once now passes it, 0x51c7d0); kind 0x18 names the unit "Illusion_Data_Only" (0x43c450's stats, +0x1f0).
		var extra := {"lifetime": int(record.get("d89", 0)) if int(record.kind) != RAISE else 0, "illusion": int(record.kind) == ILLUSIONS}
		var made: Dictionary = world.spawn(String(record.summon), cells[i], owner, int(record.w9b), int(record.w9d), extra)
		if not made.is_empty(): out.append(made)
	return out
