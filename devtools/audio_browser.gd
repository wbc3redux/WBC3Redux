extends Control
## Audio browser (AUDIO_RESEARCH.md): every imported original sound by id. Filter by text or group, Enter / double-click
## plays through the original mixer rules (priority 100, full effects volume, centre pan), Space stops, M plays the
## selected music track on the music handle. `-- --self-test` decodes every entry and checks it against the manifest
## (no audio device needed: headless Godot uses the dummy driver).
const Assets = preload("res://core/asset_store.gd")
const AudioManager = preload("res://core/audio_manager.gd")
const Rules = preload("res://simulation/audio_rules.gd")

var audio: Node
var list := ItemList.new()
var filter := LineEdit.new()
var group := OptionButton.new()
var info := Label.new()
var ids: Array = []

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # a full-window STOP root would eat every click before _unhandled_input
	audio = AudioManager.instance(get_tree())
	audio.enabled = true             # the browser always plays (the headless self-test uses the dummy driver)
	var box := VBoxContainer.new()
	box.position = Vector2(16, 12)
	box.size = Vector2(1240, 690)
	add_child(box)
	var title := Label.new()
	title.text = "ORIGINAL AUDIO · %d entries from SoundFX.xcr, GameSpeech.xcr, Sides/*VoicesEn.xcr, SoundFX/Terrain, SoundFX/Weather, Music" % audio.manifest.get("entries", []).size()
	box.add_child(title)
	var row := HBoxContainer.new()
	box.add_child(row)
	filter.placeholder_text = "filter (e.g. AHKX, Attack0, System)"
	filter.custom_minimum_size = Vector2(320, 0)
	filter.text_changed.connect(func(_t): refresh())
	row.add_child(filter)
	group.add_item("all groups")
	var groups: Array = audio.manifest.get("counts", {}).get("groups", {}).keys()
	groups.sort()
	for g in groups: group.add_item(g)
	group.item_selected.connect(func(_i): refresh())
	row.add_child(group)
	for pair in [["Play [Enter]", play_selected], ["Stop [Space]", stop], ["Music [M]", play_music_selected]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(pair[1])
		row.add_child(b)
	list.custom_minimum_size = Vector2(1240, 560)
	list.item_selected.connect(func(_i): describe())
	list.item_activated.connect(func(_i): play_selected())
	box.add_child(list)
	box.add_child(info)
	refresh()
	if "--self-test" in OS.get_cmdline_user_args(): call_deferred("self_test")

func refresh():
	list.clear()
	ids.clear()
	var wanted := filter.text.to_lower()
	var g := "" if group.selected <= 0 else group.get_item_text(group.selected)
	for e in audio.manifest.get("entries", []):
		if g != "" and String(e.group) != g: continue
		if wanted != "" and String(e.id).to_lower().find(wanted) < 0: continue
		ids.append(String(e.id))
		list.add_item(String(e.id))
	info.text = "%d shown" % ids.size()

func selected_entry() -> Dictionary:
	var picked := list.get_selected_items()
	if picked.is_empty(): return {}
	return audio.by_id.get(String(ids[picked[0]]).to_lower(), {})

func describe():
	var e := selected_entry()
	if e.is_empty(): return
	var f: Dictionary = e.get("format", {})
	var source: Dictionary = e.source
	var where := "%s : %s @ 0x%x" % [source.archive, source.entry, int(source.offset)] if source.has("archive") else String(source.get("file", ""))
	if f.get("kind", "") == "mp3": info.text = "%s · MP3 · %d bytes · %s" % [e.id, int(e.bytes), where]
	else: info.text = "%s · %d Hz %d-bit %s · %d ms · %s" % [e.id, int(f.rate), int(f.bits), "stereo" if int(f.channels) == 2 else "mono", int(f.duration_ms), where]

func play_selected():
	var e := selected_entry()
	if e.is_empty(): return
	if String(e.group) == "music": play_music_selected()
	else: audio.play(String(e.id), Rules.PRIORITY.voice, audio.effects_volume)

func play_music_selected():
	var e := selected_entry()
	if e.is_empty() or String(e.group) != "music": return
	var s: AudioStream = audio.stream(String(e.id))
	audio.music.stream = s
	audio.music.volume_db = Rules.volume_db(mini(127, audio.music_setting << 5))
	audio.music.play()

func stop():
	audio.stop_all()
	audio.stop_music()

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo and not filter.has_focus():
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER: play_selected()
			KEY_SPACE: stop()
			KEY_M: play_music_selected()

## Decodes every entry, compares lengths with the manifest, exercises the mixer and the browser filter.
func self_test():
	var checks := 0
	var failures := 0
	var fail := func(text: String): push_error(text)
	var entries: Array = audio.manifest.get("entries", [])
	if entries.size() < 2000:
		fail.call("manifest has %d entries" % entries.size())
		failures += 1
	for e in entries:
		checks += 1
		var bytes := Assets.bytes(String(e.file))
		if bytes.size() != int(e.bytes):
			failures += 1
			fail.call("%s: %d bytes on disk, manifest %d" % [e.id, bytes.size(), int(e.bytes)])
			continue
		var s: AudioStream = audio.stream(String(e.id))
		if s == null:
			failures += 1
			fail.call("%s did not decode" % e.id)
			continue
		var f: Dictionary = e.get("format", {})
		if f.get("kind", "") == "mp3":
			if s.get_length() < 30.0:
				failures += 1
				fail.call("%s: MP3 length %.1f s" % [e.id, s.get_length()])
		else:
			var expected := float(f.frames) / float(f.rate)
			var wav := s as AudioStreamWAV
			var ok: bool = wav != null and absf(s.get_length() - expected) < 0.002 and wav.mix_rate == int(f.rate) \
				and wav.stereo == (int(f.channels) == 2) and wav.format == (AudioStreamWAV.FORMAT_8_BITS if int(f.bits) == 8 else AudioStreamWAV.FORMAT_16_BITS)
			if not ok:
				failures += 1
				fail.call("%s: decoded %.4f s (%s), manifest %.4f s %s" % [e.id, s.get_length(), wav, expected, f])
		audio.streams.erase(String(e.id).to_lower())    # keep memory flat while decoding ~250 MB
	# Mixer: 16 channels; a 17th sound of equal priority is refused, a higher priority steals the first unprotected slot.
	audio.stop_all()
	for i in Rules.CHANNELS:
		checks += 1
		if audio.play("sfx/Boom", 30, 127) != i: failures += 1; fail.call("channel %d not allocated in order" % i)
	checks += 3
	if audio.play("sfx/Boom", 30, 127) != -1: failures += 1; fail.call("equal priority stole a channel")
	if audio.play("sfx/Boom", 31, 127) != 0: failures += 1; fail.call("higher priority did not steal channel 0")
	if audio.play("sfx/NewClick", 20, 127, 64.0, true) != -1: failures += 1; fail.call("lower priority stole a channel")
	audio.stop_all()
	filter.text = "AHKXSelect"
	refresh()
	checks += 1
	if ids != ["voices/Knights/AHKXSelect1", "voices/Knights/AHKXSelect2"]: failures += 1; fail.call("filter AHKXSelect -> %s" % [ids])
	# Stopped playbacks are released by the audio thread; give it time before quitting (else they count as leaked).
	await get_tree().create_timer(0.3).timeout
	for i in 5: await get_tree().process_frame
	if failures == 0: print("Audio browser checks passed: %d" % checks)
	else: printerr("Audio browser failures: %d / %d" % [failures, checks])
	get_tree().quit(0 if failures == 0 else 1)
