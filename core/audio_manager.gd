extends Node
## The original sound layer (AUDIO_RESEARCH.md): a 16-channel mixer with the original priorities and stealing rule
## (0x4ca480), the sound tick counters (0x50ea10, one per 25 ms game update), the camera window and distance/pan tables
## (0x50ee90 / 0x50eef0 / 0x50ef50 / 0x50f020), unit voices (0x50c2e0 select, 0x50c530 order, 0x50c790 ready, ...),
## combat sounds, advisor speech (0x50f1b0), the terrain ambience stream (0x50e420), the low-health heartbeat (0x50e690)
## and the soundtrack (0x5101d0 / 0x510520). It only listens: the simulation emits signals, main.gd emits the player's
## select / order signals. One instance lives under the scene tree root so the music survives scene changes.
const Assets = preload("res://core/asset_store.gd")
const Rules = preload("res://simulation/audio_rules.gd")
const NODE_NAME := "WBC3Audio"
static var MANIFEST: String = Assets.path("audio_manifest.json")
const MOVEMENT_LOOPS := ["Walk", "Stomp", "Trot", "Flap", "Soar", "Splash", "Wagon", "Pad", "Fire", "Sparkles", "Clank", "Skeleton"]   # 0x50fbf0 -> 0xaefe3c
const MUSIC_CHECK_MS := 5000            # 0x510520
const SHARE_MATCH_RNG := true           # the variant draws are 0x458e70, the match generator (decision: kept)

var manifest: Dictionary = {}
var by_id: Dictionary = {}              # lower-case id -> manifest entry
var streams: Dictionary = {}            # id -> AudioStream
var players: Array = []                 # 16 AudioStreamPlayer, one bus each (panner)
var slots: Array = []                   # null or {"priority", "protected", "stream", "release", "id", "loop"}
var music: AudioStreamPlayer
var music_last := -1                    # 0x611052: last ambient track index
var music_mode := -1
var music_check_ms := 0
var intro_played := false               # 0x608460: the theme starts once, at the first main-menu entry
var enabled := true                     # 0x60c361: the sound system is on (off in headless runs: no audio device)
var effects_volume := 120               # 0x70d6c8 "OverallVolume": the options value (default 120, 0x453280; milestone 11-menus)
var music_setting := 3                  # 0x70d6b2 "MusicVolume" 0..4 (default 3, 0x453280); sample volume = setting << 5
## The player's sound options (simulation/game_settings.gd, milestone 11-menus), each read where the original reads it:
## CombatSounds 0x70d6c5 (0x50d300 attack hits), EnvironmentalSounds 0x70d6af (0x50e420 terrain), FootSteps 0x70d6b0
## (0x5205d0 movement loops), HeroHeartbeat 0x70d7d9 (0x50e690), UnitSpeech 0x70d6c6 (0x50be80: 0 never; 1 skips
## select/order voices when a 1..5 roll of the match generator is above 2), VictoryDefeatBuildup 0x70d7d8 (0x513e00:
## Victory/Defeat.wav before the advisor), SystemVoice 0x70d8dc (0x511c10: 0 -> SystemF, the female advisor).
var options := {"CombatSounds": 1, "EnvironmentalSounds": 1, "FootSteps": 1, "HeroHeartbeat": 1, "UnitSpeech": 2,
	"VictoryDefeatBuildup": 1, "SystemVoice": 0}
var volumes := PackedInt32Array()
var pans := PackedFloat32Array()
var play_log: Array = []                # recent plays (id, priority, volume, pan, channel) for the browser and tests
var refused := 0
var played_counts: Dictionary = {}       # id -> plays (written to .local/audio_log.json with `-- --audio-log`)

# Sound tick counters (0xb90fa0 + 0x188 / 0x18c / 0x190 / 0x194), advanced once per 25 ms game update.
var ack_counter := 0
var death_counter := 0
var speech_counter := 0
var ready_counter := 0
var speech_repeat_value := -1
var speech_played_step := {}          # speech id -> the age step (Rules.SPEECH_AGE_STEP_MS) it last played at (0xafd084)
var updates_done := 0

# Match binding.
var main: Node
var bound: Dictionary = {}              # signal source instance id -> true
var building_info: Dictionary = {}      # building id -> {"cell", "code"} (production erases a building before it reports the loss)
var last_variant: Dictionary = {}       # "select:<id>" / "order:<id>" -> last variant (+0x458 / +0x45a)
var movement_slots: Array = [null, null, null]   # 0xb90fa0 + 0xfc: three loops {"type", "unit", "distance", "channel"}
var fire_slots: Array = [null, null]             # 0x50db10: two Fire.wav loops {"building", "channel"} (EFFECTS_RESEARCH.md)
var terrain_channel := -1
var heartbeat := {"channel": -1, "level": -1, "last_hp": -1, "beat_ms": 0, "start_ms": 0, "fading": false, "playing": false}
var hero_level_seen := -1
# Parity pass 2: advisor triggers (AUDIO_RESEARCH.md "Parity pass 2").
var build_types: Dictionary = {}        # builder unit id -> the type of its pending build (for 0x524450's lane check)
var blocked_seen: Dictionary = {}       # building id -> population_blocked last tick (0x5776c0 command check)
var hero_kill_threshold := 0x31         # 0x611208: reset to 0x31 by 0x518850, +0x32 after each speech 0xe
var quest_seen := false                 # the local player had a quest last tick (0x43d350)
var quests_done_seen := 0               # 0x7494b6 of the local player last tick (0x43d560)
var stinger_played := false             # 0xafd338: one stinger per match
var speech_log: Array = []              # ids that played (tests)

static var _shared: Node = null

static func instance(tree: SceneTree) -> Node:
	if _shared != null and is_instance_valid(_shared) and not _shared.is_queued_for_deletion(): return _shared
	var existing := tree.root.get_node_or_null(NODE_NAME)
	if existing != null:
		_shared = existing
		return existing
	var node = load("res://core/audio_manager.gd").new()
	node.name = NODE_NAME
	tree.root.add_child.call_deferred(node)   # the root may be busy setting up the scene
	node.setup()
	_shared = node
	return node

func setup(path: String = MANIFEST) -> bool:
	if not manifest.is_empty(): return true
	enabled = DisplayServer.get_name() != "headless" and not "--no-sound" in OS.get_cmdline_user_args()   # `-- --no-sound`: the sound-off option
	if not FileAccess.file_exists(path):
		push_warning("Audio manifest missing; run launch.ps1 -ImportAssets.")
		return false
	manifest = JSON.parse_string(FileAccess.get_file_as_string(path))
	for e in manifest.entries: by_id[String(e.id).to_lower()] = e
	apply_settings(load("res://simulation/game_settings.gd").current())
	pans = Rules.pan_table()
	for i in Rules.CHANNELS:
		var bus := "WBC3 Sfx %d" % i
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.add_bus_effect(index, AudioEffectPanner.new())
		var p := AudioStreamPlayer.new()
		p.bus = bus
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		players.append(p)
		slots.append(null)
	music = AudioStreamPlayer.new()
	add_child(music)
	return true

## The panner effects belong to the AudioServer buses; remove them before exit or Godot reports them as leaked.
func _exit_tree():
	if "--audio-log" in OS.get_cmdline_user_args():
		var file := FileAccess.open("res://.local/audio_log.json", FileAccess.WRITE)
		if file != null: file.store_string(JSON.stringify({"enabled": enabled, "refused": refused, "played": played_counts, "last": play_log}, "  "))
	for p in players: p.stop()
	if music != null: music.stop()
	for i in range(AudioServer.bus_count - 1, 0, -1):
		if AudioServer.get_bus_name(i).begins_with("WBC3 Sfx "): AudioServer.remove_bus(i)

## The options screens call this after a change (and setup() at start): effects volume table, music volume, gates.
func apply_settings(settings) -> void:
	effects_volume = settings.get_value("OverallVolume")
	music_setting = settings.get_value("MusicVolume")
	for key in options: options[key] = settings.get_value(key)
	volumes = Rules.volume_table(effects_volume)
	if music != null and music.playing: music.volume_db = Rules.volume_db(mini(127, music_setting << 5))
	if int(options.EnvironmentalSounds) == 0 and terrain_channel >= 0:
		stop_channel(terrain_channel)
		terrain_channel = -1
	if int(options.HeroHeartbeat) == 0 and heartbeat.channel >= 0:
		stop_channel(heartbeat.channel)
		heartbeat.channel = -1
		heartbeat.playing = false

## 0x50be80 events 4/5 (select/order): UnitSpeech 0 never; 1 only when a 1..5 roll is at most 2.
func unit_speech_allows(selection_or_order: bool) -> bool:
	var level := int(options.UnitSpeech)
	if level <= 0: return false
	if selection_or_order and level == 1 and roll(5) > 2: return false
	return true

# ------------------------------------------------------------------------------------------------ streams and mixer
func has_sound(id: String) -> bool:
	return by_id.has(id.to_lower())

func stream(id: String) -> AudioStream:
	var key := id.to_lower()
	if streams.has(key): return streams[key]
	if not by_id.has(key): return null
	var entry: Dictionary = by_id[key]
	var bytes := Assets.bytes(String(entry.file))
	var s: AudioStream
	if String(entry.file).ends_with(".mp3"): s = AudioStreamMP3.load_from_buffer(bytes)
	else: s = AudioStreamWAV.load_from_buffer(bytes)
	streams[key] = s
	return s

## The mixer (0x4ca480 + 0x4c9e60 + 0x4c9d50 + 0x4ca390): allocate a slot by priority, set volume and pan, start.
## release: the slot is freed when the sample ends (0x4cb010); loops keep their slot until stopped.
func play(id: String, priority: int, volume: int, pan: float = 64.0, protected: bool = false, loop: bool = false, stream_slot: bool = false) -> int:
	if not enabled or players.is_empty() or not is_inside_tree(): return -1
	var s := stream(id)
	if s == null: return -1
	var channel := Rules.allocate(slots, priority)
	if channel < 0:
		refused += 1
		return -1
	stop_channel(channel)
	if loop:
		s = s.duplicate()
		if s is AudioStreamWAV:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = int(s.get_length() * s.mix_rate)
		elif s is AudioStreamMP3: s.loop = true
	slots[channel] = {"priority": priority, "protected": protected, "stream": stream_slot, "id": id, "loop": loop}
	var p: AudioStreamPlayer = players[channel]
	p.stream = s
	set_channel(channel, volume, pan)
	p.play()
	play_log.append({"id": id, "priority": priority, "volume": volume, "pan": pan, "channel": channel})
	played_counts[id] = int(played_counts.get(id, 0)) + 1
	if play_log.size() > 64: play_log.pop_front()
	return channel

func set_channel(channel: int, volume: int, pan: float):
	if channel < 0 or channel >= players.size(): return
	players[channel].volume_db = Rules.volume_db(volume)
	var effect := AudioServer.get_bus_effect(AudioServer.get_bus_index(players[channel].bus), 0) as AudioEffectPanner
	if effect != null: effect.pan = Rules.panner(pan)

func stop_channel(channel: int):
	if channel < 0 or channel >= players.size(): return
	players[channel].stop()
	slots[channel] = null

func _on_finished(channel: int):
	if slots[channel] != null and not bool(slots[channel].loop): slots[channel] = null

func stop_all():
	for i in players.size(): stop_channel(i)
	movement_slots = [null, null, null]
	fire_slots = [null, null]
	terrain_channel = -1
	heartbeat.channel = -1
	heartbeat.playing = false

# ------------------------------------------------------------------------------------------------ positions
func camera_cell() -> Vector2i:
	if main == null: return Vector2i(64, 64)
	return main.collision.world_cell(main.camera.position)

## 0x50cbf0 / 0x50d300 / 0x50f0a0: the cell must be inside the camera window, and visible (or the camera cell is).
func audible(cell: Vector2i) -> bool:
	var cam := camera_cell()
	if not Rules.in_window(cam, cell): return false
	if main == null or main.visibility == null or not main.visibility.fog: return true
	var player: int = main.local_player
	return main.visibility.is_visible(player, cell) or main.visibility.is_visible(player, cam)

func distance_volume(cell: Vector2i) -> int:
	return volumes[Rules.distance_index(camera_cell(), cell)]

func effect_pan(cell: Vector2i) -> float:
	return pans[Rules.pan_index(camera_cell().x, cell.x)]

func voice_pan(cell: Vector2i) -> float:
	return pans[Rules.voice_pan_index(camera_cell().x, cell.x)]

## 0x50f0a0: a named effect at a cell (one-shot, priority 0x8c).
func positional(id: String, cell: Vector2i, priority: int = 140) -> int:
	if not audible(cell): return -1
	return play(id, priority, distance_volume(cell), effect_pan(cell))

# ------------------------------------------------------------------------------------------------ match binding
func attach(scene: Node):
	main = scene
	bound.clear()
	building_info.clear()
	last_variant.clear()
	updates_done = 0
	music_check_ms = 0
	hero_level_seen = -1
	heartbeat = {"channel": -1, "level": -1, "last_hp": -1, "beat_ms": 0, "start_ms": 0, "fading": false, "playing": false}
	ack_counter = 0
	death_counter = 0
	speech_counter = 0
	ready_counter = 0
	speech_played_step.clear()
	build_types.clear()
	blocked_seen.clear()
	hero_kill_threshold = 0x31
	quest_seen = false
	quests_done_seen = 0
	stinger_played = false
	speech_log.clear()

func detach(scene: Node):
	if main != scene: return
	main = null
	bound.clear()
	stop_all()

func _connect(source: Object, signal_name: String, callable: Callable):
	if source == null or not source.has_signal(signal_name) or source.is_connected(signal_name, callable): return
	source.connect(signal_name, callable)

func _bind_sources():
	if main == null: return
	for pair in [[main.combat, "combat"], [main.production, "production"], [main.skirmish, "skirmish"]]:
		if pair[0] == null or bound.has(pair[0].get_instance_id()): continue
		bound[pair[0].get_instance_id()] = true
		match pair[1]:
			"combat":
				_connect(pair[0], "swing_started", _on_swing_started)
				_connect(pair[0], "hit_entry", _on_hit_entry)
				_connect(pair[0], "died", _on_died)
				_connect(pair[0], "damaged", _on_damaged)
				_connect(pair[0], "missile_landed", _on_missile_landed)
			"production":
				_connect(pair[0], "unit_ready", _on_unit_ready)
				_connect(pair[0], "building_destroyed", func(id): _collapse_at_building(id))
				_connect(pair[0], "research_completed", _on_research_completed)
			"skirmish":
				_connect(pair[0], "ended", _on_match_ended)
				_connect(pair[0], "player_eliminated", _on_side_eliminated)
				start_terrain_ambience()
				stop_music()               # 0x4b1d40 stops the music when the match loads; the 5 s check starts a track

func unit(id: int):
	if main == null or id < 0 or id >= main.units.size(): return null
	return main.units[id]

func arm(code: String) -> Dictionary:
	return manifest.get("arm_sounds", {}).get(code, {})

## Milestone 11b: a hero speaks with its record's voice (+0x60: 0x54f1d0 at creation, e.g. the Empire hero APHX uses AXH2,
## the Swarm's ARHX uses AUHX), other units with their type's voices.
func voice_code(u) -> String:
	if main != null and "match_heroes" in main:
		for owner in main.match_heroes:
			var bound = main.match_heroes[owner]
			if bound != null and bound.entity != null and int(bound.entity.entity_id) == int(u.unit_id) and bound.profile != null:
				return String(bound.profile.data.get("voice_id", u.type_id))
	return String(u.type_id)

func voice_name(code: String, suffix: String) -> String:
	var group: String = manifest.get("voice_archives", {}).get(code, "")
	return "" if group == "" else "%s/%s%s" % [group, code, suffix]

func roll(sides: int) -> int:
	if SHARE_MATCH_RNG and main != null and main.combat != null: return int(main.combat.rng.roll(1, sides, 0))
	return randi_range(1, sides)

func is_local(u) -> bool:
	return u != null and main != null and int(u.owner_id) == int(main.local_player)

# ------------------------------------------------------------------------------------------------ the sound tick
func _physics_process(_delta: float):
	if main == null or not is_instance_valid(main):
		main = null
		return
	_bind_sources()
	if main.production != null:
		for id in main.production.buildings:
			if not building_info.has(id):
				var b = main.production.buildings[id]
				building_info[id] = {"cell": b.cell_rect().get_center(), "code": String(b.original_type_id)}
	var now: int = main.game_ms()
	var target := now / Rules.UPDATE_MS
	var steps: int = clampi(target - updates_done, 0, 400)
	updates_done = target
	ack_counter += steps
	death_counter += steps
	speech_counter += steps
	ready_counter += steps
	if steps > 0:
		_update_movement_loops()
		_update_fire_loops()
		_update_heartbeat(now)
		_check_hero_level()
		_check_advisor_state()
	if now + MUSIC_CHECK_MS < music_check_ms: music_check_ms = 0     # a new match restarted the clock
	if main.skirmish != null and not main.skirmish.over and now >= music_check_ms:
		music_check_ms = now + MUSIC_CHECK_MS
		if not music.playing: play_music(1)

# ------------------------------------------------------------------------------------------------ unit voices
## 0x50c2e0 / 0x50c530: the shared cooldown, then the variant draw; non-positional volume, voice pan.
func acknowledge(kind: String, unit_id: int):
	var u = unit(unit_id)
	if u == null or u.dying or not is_local(u) or ack_counter <= Rules.ACK_COOLDOWN: return
	if not unit_speech_allows(true): return
	ack_counter = 0
	var hero: bool = main.hero_unit_id == unit_id         # the local hero (any race's hero type)
	var count: int = 4 if hero else int(arm(u.type_id).get("voice_variants", 0))
	var key := "%s:%d" % [kind, unit_id]
	var r := roll(100)
	var choice: Array = Rules.choose_variant(kind, count, int(last_variant.get(key, 0)), r)
	last_variant[key] = choice[1]
	var id := voice_name(voice_code(u), "%s%d" % ["Select" if kind == "select" else "Order", choice[0]])
	play(id, Rules.PRIORITY.voice, effects_volume, voice_pan(u.cell))

func on_selected(ids: Array):
	for id in ids:
		if is_local(unit(id)):
			acknowledge("select", id)
			return

func on_ordered(ids: Array):
	play("sfx/NewClick", Rules.PRIORITY.ui, effects_volume, 64.0, true)   # 0x4ce960 replays the NewClick slot first
	for id in ids:
		if is_local(unit(id)):
			acknowledge("order", id)
			return

## 0x50d5c0: a selected building plays its own sound, or Build.wav while under construction (progress <= 89).
func on_building_selected(building_id: int):
	if main == null or main.production == null or ack_counter <= Rules.ACK_COOLDOWN: return
	var b = main.production.building(building_id)
	if b == null: return
	ack_counter = 0
	var cell: Vector2i = b.cell_rect().get_center()
	var own: bool = not b.constructing or b.progress > 89
	var id := ("sfx/" + Rules.building_sound(String(b.original_type_id))) if own else "sfx/Build"
	play(id, Rules.PRIORITY.building_select, effects_volume, voice_pan(cell))

## Event 0xd (build order accepted): the builder's Build voice; a hero answers with its Conversion line (+0x14).
## Event 0xe (placement refused, 0x524450): CantBuild. Priority 0x82.
func on_build_order(unit_id: int, accepted: bool):
	var u = unit(unit_id)
	if u == null or not is_local(u): return
	if accepted and main.get("pending_builds") != null and main.pending_builds.has(unit_id):
		build_types[unit_id] = String(main.pending_builds[unit_id].type)
	elif not accepted and build_types.has(unit_id):
		_resource_shortage(String(build_types[unit_id]), String(u.type_id))
	if not accepted: build_types.erase(unit_id)
	if not unit_speech_allows(false): return
	var hero: bool = main.hero_unit_id == unit_id
	var suffix := "CantBuild" if not accepted else ("Conversion" if hero else "Build")
	play(voice_name(voice_code(u), suffix), Rules.PRIORITY.work_voice, effects_volume, voice_pan(u.cell))

## 0x50c790 (event 6 from 0x4a49e0): a new unit of the local player says Ready (counter +0x194 > 15).
func _on_unit_ready(info: Dictionary):
	if main == null or int(info.get("owner", -1)) != int(main.local_player): return
	if ready_counter <= Rules.READY_COOLDOWN or not unit_speech_allows(false): return
	ready_counter = 0
	var cell: Vector2i = info.get("cell", camera_cell())
	play(voice_name(String(info.item), "Ready"), Rules.PRIORITY.voice, effects_volume, voice_pan(cell))

## Event 0xf (0x520c90): the local player's unit finished a conversion (order 7) and says its Conversion line, whether or not
## anything changed owner (main.gd calls this from MatchConversion.finished).
func on_conversion_finished(unit_id: int):
	var u = unit(unit_id)
	if u == null or not is_local(u) or not unit_speech_allows(false): return
	play(voice_name(voice_code(u), "Conversion"), Rules.PRIORITY.work_voice, effects_volume, voice_pan(u.cell))

## The local player's Keep finished converting (building update 0x52cfb6): KeepConversion.wav through 0x4ca050 at the
## effects volume, centre pan, at most once per 1000 ms (0xafd4c0, timeGetTime). The priority 0x4ca050 uses is Open (UI).
var keep_conversion_ms := -1000000
func on_keep_conversion():
	var now := Time.get_ticks_msec()
	if now <= keep_conversion_ms + 1000: return
	keep_conversion_ms = now
	play("sfx/KeepConversion", Rules.PRIORITY.ui, effects_volume, 64.0)

# ------------------------------------------------------------------------------------------------ combat
## 0x42ace0: a deathblow (the x4 critical, code 0) makes the attacker shout (event 0xb, counter > 30, positional volume).
func _on_swing_started(id: int, info: Dictionary):
	var result: Dictionary = info.get("result", {})
	if int(result.get("code", -1)) != 0 or ack_counter <= Rules.DEATHBLOW_COOLDOWN or not unit_speech_allows(false): return
	var u = unit(id)
	if u == null or not audible(u.cell): return
	ack_counter = 0
	play(voice_name(voice_code(u), "Deathblow"), Rules.PRIORITY.deathblow, distance_volume(u.cell), effect_pan(u.cell))

## 0x50d300 from the hit entry 0x523150: Attack<class><variant>.
func _on_hit_entry(id: int, info: Dictionary):
	if int(options.CombatSounds) == 0: return
	var u = unit(id)
	if u == null or not audible(u.cell): return
	var target_kind := String(info.get("target_kind", "unit"))
	var target_code := ""
	var struck := 0
	if target_kind == "unit":
		var t = unit(int(info.get("target_id", -1)))
		if t != null:
			target_code = t.type_id
			struck = int(arm(t.type_id).get("struck_sound", 0))
	elif main.production != null and main.production.building(int(info.get("target_id", -1))) != null:
		target_code = String(main.production.building(int(info.target_id)).original_type_id)
	var id_name := Rules.attack_sound(u.type_id, int(arm(u.type_id).get("attack_sound", 0)), target_kind, struck, target_code)
	play("sfx/" + id_name, Rules.PRIORITY.attack, distance_volume(u.cell), effect_pan(u.cell))

## 0x5374a0 -> 0x50edd0: Death<n> (ARM +0x10a) with the distance volume, no window test, counter +0x18c > 30.
func _on_died(kind: String, id: int, _killer_owner: int):
	if kind == "building": return
	var u = unit(id)
	if u == null: return
	if main.hero_unit_id == id and speech(4): alert(u.cell)   # 0x5210b0: the local hero has fallen (P-1: + 0x4dcf70)
	var n := int(arm(u.type_id).get("death_sound", 0))
	if n <= 0 or death_counter <= Rules.DEATH_COOLDOWN: return
	death_counter = 0
	play("sfx/Death%d" % n, Rules.PRIORITY.death, distance_volume(u.cell), effect_pan(u.cell))

## 0x522860 (after 0x522af0 stored the new hit points; the unit survived): a unit of the local player outside the view.
## Not a hero: damage >= 2 from an enemy -> speech 1. The hero: below 50 hit points -> speech 5 (any damage, attacker or
## not), else damage >= 2 -> speech 3. A speech that plays also adds a strategic-map alert (0x4dcf70, P-1: alert()).
## 0x52b18x: a building of the local player hit by another player's unit, more than 10 cells outside the view, damage
## >= 2: speech 0 within 20 cells of home (0x749bae: the highest-level Keep, else the start cell), else 28.
func _on_damaged(kind: String, id: int, amount: int, attacker_id: int):
	if main == null: return
	if kind == "building":
		_building_damaged(id, amount, attacker_id)
		return
	if kind != "unit": return
	var u = unit(id)
	if u == null or not is_local(u) or u.dying: return
	var a = unit(attacker_id) if attacker_id >= 0 else null
	if a != null and in_view(u.cell, 0): return
	if a == null and in_view(u.cell, 0): return
	var hero: bool = main.combat != null and main.combat.fighters.has(id) and bool(main.combat.fighters[id].hero)
	if not hero:
		if amount < 2 or a == null or is_local(a): return
		if speech(1): alert(u.cell)
		return
	var hp: int = int(main.combat.fighters[id].hp)
	if hp <= 0: return
	if hp < 0x32:
		if speech(5): alert(u.cell)
	elif amount >= 2:
		if speech(3): alert(u.cell)

## P-1: 0x4dcf70(cell, 1) after a speech that played (0x522860, 0x52b180, 0x5210b0, Read): the strategic-map ping and an
## alert list entry (main.gd strategic_alert).
func alert(cell: Vector2i):
	if main != null and main.has_method("strategic_alert"): main.strategic_alert(cell, true)

## The view rectangle in cells (0x490880 / 0x4908c0 origin, 0x490940 / 0x490950 size), grown by `margin` cells.
func in_view(cell: Vector2i, margin: int) -> bool:
	if main == null or main.camera == null: return true
	var size: Vector2 = main.get_viewport_rect().size / main.camera.zoom
	var top_left: Vector2i = main.collision.world_cell(main.camera.position - size * 0.5)
	var bottom_right: Vector2i = main.collision.world_cell(main.camera.position + size * 0.5)
	return cell.x >= top_left.x - margin and cell.x <= bottom_right.x + margin and cell.y >= top_left.y - margin and cell.y <= bottom_right.y + margin

func home_cell() -> Vector2i:
	var best := -1
	var cell: Vector2i = main.skirmish.slots[main.local_player].start if main.skirmish != null else Vector2i(-100, -100)
	if main.production == null: return cell
	for bid in main.production.buildings:
		var b = main.production.buildings[bid]
		var code := String(b.original_type_id)
		if int(b.owner) != int(main.local_player) or b.constructing or code.length() < 4 or code.substr(1, 2) != "KK": continue
		var level := code.unicode_at(3) - 0x30
		if level > best:
			best = level
			cell = b.cell_rect().position
	return cell

func _building_damaged(id: int, amount: int, attacker_id: int):
	if amount < 2 or attacker_id < 0 or main.production == null: return
	var b = main.production.building(id)
	var a = unit(attacker_id)
	if b == null or a == null or int(b.owner) != int(main.local_player) or is_local(a): return
	var cell: Vector2i = b.cell_rect().position
	if in_view(cell, 10): return
	if speech(Rules.building_attack_speech(cell, home_cell())):
		alert(Vector2i(int(b.position.x) / 32, int(b.position.y) / 24))   # P-1: 0x52b180 -> 0x4dcf70 at the sprite cell

## 0x524450: the placement on arrival lacked resources; each short lane speaks (crystal 0x14, metal 0x13, gold 0x11,
## stone 0x12, in that order; the 250 ms gate lets only the first through).
func _resource_shortage(type_id: String, builder_type: String):
	if main.production == null or main.economy == null: return
	var price: Array = main.production.price_of(main.local_player, type_id, builder_type)
	for id in Rules.resource_shortage_speech(price, main.economy.resources(main.local_player)): speech(id)

## 0x436500: the local player's research is complete -> speech 8; PSPR / PPAR go to 0x438180 (speech 9); POMA..POMC
## and the local PQKN return before it (no speech).
func _on_research_completed(owner: int, item: String):
	if main == null or owner != int(main.local_player): return
	var id := Rules.research_speech(item)
	if id >= 0: speech(id)

## 0x4addc0: another side is defeated while at least two sides remain -> speech 10 (allied) or 11 (enemy).
func _on_side_eliminated(player: int):
	if main == null or main.skirmish == null or player == int(main.local_player): return
	var remaining := 0
	for p in 6:
		if main.skirmish.active(p) and not main.skirmish.eliminated[p]: remaining += 1
	if remaining < 2: return
	speech(10 if main.skirmish.is_allied(main.local_player, player) else 11)

## Polled advisor states (one sound tick): the command check 0x5776c0 (speech 2, its repeat memory reset first by
## 0x50f190(2)), the hero's kill count 0x518a10 case 3 (speech 0xe above 0x611208, which then grows by 0x32), the quest
## taken 0x43d350 (0xf) and completed 0x43d560 (0x10).
func _check_advisor_state():
	if main.production != null:
		for bid in main.production.buildings:
			var b = main.production.buildings[bid]
			if int(b.owner) != int(main.local_player): continue
			var was: bool = bool(blocked_seen.get(bid, false))
			if b.population_blocked and not was:
				speech_repeat_value = -1                              # 0x50f190(2)
				speech(2, int(main.production.population(main.local_player).maximum))
			blocked_seen[bid] = b.population_blocked
	if main.skirmish != null:
		var p: int = main.local_player
		if int(main.skirmish.hero_kills[p]) > hero_kill_threshold:
			speech(0xe)
			hero_kill_threshold += 0x32
		var done := int(main.skirmish.quests_done[p])
		if done > quests_done_seen: speech(0x10)
		quests_done_seen = done
	if main.get("encounters") != null and main.encounters != null:
		var has := bool(main.encounters.quests.has(main.local_player))
		if has and not quest_seen: speech(0xf)
		quest_seen = has

## 0x5427e0 -> 0x50f3e0: Missile<n>.wav (keyed category 0x10) at priority 10 with the distance volume and effect pan
## of the missile's cell; no window test. n by id and target (simulation/missiles.gd IMPACT_SOUNDS).
func _on_missile_landed(info: Dictionary):
	if not bool(info.get("hit", false)) or int(info.get("impact_sound", -1)) < 0: return
	var cell: Vector2i = info.get("cell", Vector2i(-1, -1))
	if cell.x < 0: return
	play("sfx/Missile%d" % int(info.impact_sound), Rules.PRIORITY.missile, distance_volume(cell), effect_pan(cell))

## 0x53bba0 -> 0x50be80(1, 7) when a building's first fire lights; 0x50db10 keeps Fire.wav looping in two slots
## (priority 70, protected) for the nearest audible burning buildings (effects_layer.gd `burning`). Slot hand-over
## details of 0x50db10 are Read only; the rebuild keeps the two nearest.
func _update_fire_loops():
	var burning: Dictionary = main.effects.burning if main.get("effects") != null else {}
	var cam := camera_cell()
	var wanted: Array = []
	for id in burning:
		if audible(burning[id]): wanted.append([Rules.distance_index(cam, burning[id]), id])
	wanted.sort()
	wanted = wanted.slice(0, 2).map(func(w): return w[1])
	for i in 2:
		var s = fire_slots[i]
		if s == null: continue
		if not wanted.has(s.building):
			stop_channel(s.channel)
			fire_slots[i] = null
			continue
		var cell: Vector2i = burning[s.building]
		set_channel(s.channel, distance_volume(cell), effect_pan(cell))
		wanted.erase(s.building)
	for id in wanted:
		var free := fire_slots.find(null)
		if free < 0: break
		var cell: Vector2i = burning[id]
		var channel := play("sfx/Fire", Rules.PRIORITY.fire, distance_volume(cell), effect_pan(cell), true, true)
		if channel >= 0: fire_slots[free] = {"building": id, "channel": channel}

## 0x50e000: a destroyed building falls (Falling0/1 by a 0..1 draw; EggDestroy for BMEG), priority 0x8d.
func _collapse_at_building(building_id: int):
	if main == null or not building_info.has(building_id): return
	var info: Dictionary = building_info[building_id]
	building_info.erase(building_id)
	collapse(info.cell, info.code)

func collapse(cell: Vector2i, code: String):
	if not audible(cell): return
	var index := roll(2) - 1
	var id := "sfx/EggDestroy" if code == "BMEG" else "sfx/Falling%d" % index
	play(id, 141, distance_volume(cell), effect_pan(cell))

# ------------------------------------------------------------------------------------------------ speech, ambience
## 0x50f1b0 -> System<n> / SystemF<n> (GameSpeech.xcr, priority 0x8d, protected). The male set is used (decision).
func speech(id: int, repeat_value: int = 0) -> bool:
	var gate: Dictionary = Rules.speech_gate(id, speech_counter, speech_repeat_value, repeat_value)
	speech_counter = gate.counter
	speech_repeat_value = gate.repeat_value
	if not gate.play: return false
	var step: int = (main.game_ms() if main != null else Time.get_ticks_msec()) / Rules.SPEECH_AGE_STEP_MS
	if gate.no_repeat and not Rules.speech_age_ok(int(speech_played_step.get(id, -1)), step): return false
	speech_played_step[id] = step
	speech_log.append(id)
	var prefix := "speech/SystemF" if int(options.SystemVoice) == 0 else "speech/System"   # 0x511c10 (0xa27d7a = 0)
	return play(prefix + str(id), Rules.PRIORITY.speech, effects_volume, 64.0, true) >= 0

## 0x50e420: SoundFX\Terrain\<kind>.wav streamed in a loop at priority 0x3c (Desert Sands: Desert). W1: the kind is the
## chosen map's (map_info.json, same rule as the manifest's Desert Sands value).
func start_terrain_ambience():
	if terrain_channel >= 0: stop_channel(terrain_channel)
	terrain_channel = -1
	if int(options.EnvironmentalSounds) == 0: return
	var ambient: Dictionary = preload("res://core/map_data.gd").info().get("terrain_ambient", manifest.get("terrain_ambient", {}))
	var name: String = ambient.get("name", "Plains")
	terrain_channel = play("terrain/" + name, Rules.PRIORITY.terrain, effects_volume, 64.0, false, true, true)

## The match end is driven by main.gd (parity pass 2): stinger() at the decision, end_box() when the stinger ends,
## results_opened() with the results screen. The decision itself stops no sound (0x4addc0 / 0x513e00).
func _on_match_ended(_outcome: Dictionary):
	pass

## 0x513e00 / 0x513c80: once per match (0xafd338) and at most once a second (0xafd344), Victory.wav / Defeat.wav at volume
## 0x7f when VictoryDefeatBuildup is on and the effects volume is above 0; returns its length in seconds, or -1 when no
## stinger plays (option off, volume 0, sound off or the play refused: the callback then runs at once).
func stinger(won: bool) -> float:
	if stinger_played: return -1.0
	stinger_played = true
	if int(options.VictoryDefeatBuildup) == 0 or effects_volume < 1: return -1.0
	var id := "sfx/Victory" if won else "sfx/Defeat"
	if play(id, 140, 127) < 0: return -1.0
	var s := stream(id)
	return s.get_length() if s != null else -1.0

## 0x513eb0 / 0x513d30 (the stinger's completion callback): the end box opens and the advisor says 12 (won) / 13.
func end_box(won: bool):
	speech(12 if won else 13)

## 0x41c520 -> 0x454560: the world is torn down (every sound stops: 0x50ff40, Open in detail) and the results theme plays.
func results_opened(won: bool):
	stop_all()
	play_music(2 if won else 3)

## UI one-shots loaded by 0x50f900 / 0x50f5d0 (Highlight*, Fade, StatPop ...): priority 0x14, protected, effects volume.
func ui_sound(id: String):
	play(id, Rules.PRIORITY.ui, effects_volume, 64.0, true)

## 0x50ea10 loops: three movement loops; a moving unit takes the loop of its movement sound when it is more than five
## cells closer than the current holder (0x50cbf0), or a free slot. Priority 10, protected, distance volume each tick.
func _update_movement_loops():
	var cam := camera_cell()
	var best: Dictionary = {}
	for u in (main.units if int(options.FootSteps) != 0 else []):
		if u.dying or u.removed or not u.visible or not u.walking or not audible(u.cell): continue
		var type: int = 0 if (main.hero_unit_id == u.unit_id) else int(arm(u.type_id).get("movement_sound", 0))
		if type < 0 or type >= MOVEMENT_LOOPS.size(): continue
		var d := Rules.distance_index(cam, u.cell)
		if not best.has(type) or d < int(best[type].distance): best[type] = {"unit": u.unit_id, "distance": d, "cell": u.cell}
	for i in 3:
		var s = movement_slots[i]
		if s == null: continue
		if not best.has(s.type):
			stop_channel(s.channel)
			movement_slots[i] = null
			continue
		var candidate: Dictionary = best[s.type]
		if candidate.unit != s.unit and int(candidate.distance) < int(s.distance) - 5: s.unit = candidate.unit
		s.distance = candidate.distance if candidate.unit == s.unit else s.distance
		var holder = unit(s.unit)
		if holder != null:
			s.distance = Rules.distance_index(cam, holder.cell)
			set_channel(s.channel, volumes[s.distance], effect_pan(holder.cell))
		best.erase(s.type)
	for type in best:
		var free := movement_slots.find(null)
		if free < 0: break
		var c: Dictionary = best[type]
		var channel := play("sfx/" + MOVEMENT_LOOPS[type], Rules.PRIORITY.movement, volumes[c.distance], effect_pan(c.cell), true, true)
		if channel >= 0: movement_slots[free] = {"type": type, "unit": c.unit, "distance": c.distance, "channel": channel}

## 0x50e690: the local hero's heartbeat. Ten levels (i + 1) * max/11; levels 0..4 beat fast. Level i beats every
## 300 + 70 i ms at volume 125 - 10 i; after 5 s without new damage each beat is 5 quieter until silent.
func _update_heartbeat(now: int):
	if main.hero_unit_id < 0 or main.combat == null or int(options.HeroHeartbeat) == 0: return
	var f = main.combat.fighters.get(main.hero_unit_id)
	if f == null or not main.combat.alive(f):
		if heartbeat.channel >= 0: stop_channel(heartbeat.channel)
		heartbeat.channel = -1
		heartbeat.playing = false
		return
	var hp: int = int(f.hp)
	var top: int = int(f.max_hp)
	var level := -1
	for i in 10:
		if hp < (i + 1) * (top / 11):
			level = i
			break
	var changed: bool = absi(hp - int(heartbeat.last_hp)) >= 2 or heartbeat.level < 0
	if heartbeat.playing and not changed:
		heartbeat.last_hp = hp
		if now < int(heartbeat.beat_ms) + 300 + 70 * int(heartbeat.level): return
		var volume: int = 125 - 10 * int(heartbeat.level)
		if heartbeat.fading:
			heartbeat.volume = int(heartbeat.get("volume", volume)) - 5
			if heartbeat.volume < 1:
				heartbeat.playing = false
				return
			volume = heartbeat.volume
		heartbeat.channel = play("sfx/HeartBeatFast" if heartbeat.level < 5 else "sfx/HeartBeatSlow", Rules.PRIORITY.heartbeat, volume, 64.0, true)
		heartbeat.beat_ms = now
		if now - int(heartbeat.start_ms) >= 5001: heartbeat.fading = true
		return
	if hp >= int(heartbeat.last_hp) and not heartbeat.playing:
		heartbeat.last_hp = hp
		return
	heartbeat.last_hp = hp
	if level < 0:
		heartbeat.playing = false
		return
	heartbeat.level = level
	heartbeat.volume = 125 - 10 * level
	heartbeat.channel = play("sfx/HeartBeatFast" if level < 5 else "sfx/HeartBeatSlow", Rules.PRIORITY.heartbeat, heartbeat.volume, 64.0, true)
	heartbeat.start_ms = now
	heartbeat.beat_ms = now
	heartbeat.fading = false
	heartbeat.playing = true

## 0x4d60f0: the local hero gains a level -> HeroLevelUp.wav at volume 0x7f.
func _check_hero_level():
	if main.hero_match == null or main.hero_match.profile == null: return
	var level := int(main.hero_match.profile.data.level)
	if hero_level_seen >= 0 and level > hero_level_seen: play("sfx/HeroLevelUp", 140, 127)
	hero_level_seen = level

# ------------------------------------------------------------------------------------------------ music
## 0x5101d0: 0 intro, 1 a random ambient track (never the previous one when there are two or more), 2 victory, 3 defeat.
## One sample handle outside the 16 mixer slots; it is not looped (0x510520 starts the next ambient track).
func play_music(mode: int) -> bool:
	if not enabled or music == null or manifest.is_empty(): return false
	if not is_inside_tree():                 # created this frame; the root adds it at the end of the frame
		play_music.call_deferred(mode)
		return true
	var track: Dictionary = manifest.soundtrack
	var name: String
	match mode:
		0: name = track.intro
		2: name = track.victory
		3: name = track.defeat
		_:
			var count: int = track.ambient.size()
			if count == 0: return false
			var pick := roll(count) - 1                     # 0x458e70(1, Tracks, -1), redrawn while equal to the last
			while count > 1 and pick == music_last: pick = roll(count) - 1
			music_last = pick
			name = track.ambient[pick]
	var s := stream("music/" + name)
	if s == null: return false
	music.stream = s
	music.volume_db = Rules.volume_db(mini(127, music_setting << 5))
	music.play()
	music_mode = mode
	return true

func stop_music():
	if music != null: music.stop()
	music_mode = -1

## The first entry of the menus (0x41d2c0, one-shot 0x608460) starts the theme.
func menu_entered():
	if intro_played: return
	intro_played = true
	play_music(0)

## NewClick (0x60f558) for the original UI screens.
func click():
	play("sfx/NewClick", Rules.PRIORITY.ui, effects_volume, 64.0, true)
