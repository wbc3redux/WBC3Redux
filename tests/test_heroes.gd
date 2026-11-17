extends SceneTree
const Rules = preload("res://simulation/hero_rules.gd")
const Profile = preload("res://simulation/hero_profile.gd")
const Store = preload("res://simulation/hero_store.gd")
const Match = preload("res://simulation/hero_match.gd")
const Entity = preload("res://simulation/entity_state.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String):
	checks += 1
	if not value:
		failures += 1
		printerr("Hero check failed: ", label)

## FE-1: Ironman and Freeze Hero (HERO_RESEARCH.md "FE-1", Read): the mode word 0x709d20 == 1 doubles live XP awards
## (0x527100) and a won battle's result (0x4553f0), deletes the record when the local hero dies (0x522260) and pays
## nothing for a dead hero (0x455d60); Freeze Hero (0x70adb2) stops XP and levelling; Delete (0x555550) removes the record.
func ironman_checks(fixtures: Dictionary, directory: String):
	# The fixtures' won contexts all have a dead hero (their xp is the Emulated value); a living hero's win is the same
	# context with hero_died off (the 3/4 factor is the only difference: Emulated), and a loss comes from a lost row.
	var won_row: Dictionary = {}
	var lost_row: Dictionary = {}
	for row in fixtures.result_bonuses:
		var c: Dictionary = row.context
		if c.no_award or int(row.xp) <= 0: continue
		if c.won and won_row.is_empty(): won_row = row
		if not c.won and not c.hero_died and lost_row.is_empty(): lost_row = row
	check(not won_row.is_empty() and not lost_row.is_empty(), "fixture contexts for a win and a defeat with a living hero")
	won_row = {"context": won_row.context.duplicate(true)}
	won_row.context["hero_died"] = false
	won_row["xp"] = Rules.result_bonus(won_row.context)
	check(int(won_row.xp) > 0, "a living hero's win pays something")
	var won_ctx: Dictionary = won_row.context.duplicate(true)
	var lost_ctx: Dictionary = lost_row.context.duplicate(true)
	won_ctx["ironman"] = true
	lost_ctx["ironman"] = true
	check(Rules.result_bonus(won_ctx) == 2 * int(won_row.xp), "Ironman doubles a win's result")
	check(Rules.result_bonus(lost_ctx) == int(lost_row.xp), "an Ironman defeat with a living hero pays the normal amount")
	var dead_ctx: Dictionary = won_ctx.duplicate(true)
	dead_ctx["hero_died"] = true
	check(Rules.result_bonus(dead_ctx) == 0, "a dead Ironman hero pays nothing")
	var frozen_ctx: Dictionary = won_row.context.duplicate(true)
	frozen_ctx["frozen"] = true
	check(Rules.result_bonus(frozen_ctx) == 0 and Rules.result_bonus(won_row.context) == int(won_row.xp), "a frozen hero pays nothing; the context key defaults off")
	check(Rules.short_match_bonus(true, 0, 3) == 1 and Rules.short_match_bonus(true, 0, 3, true) == 2 and Rules.short_match_bonus(true, 0xb, 3, true) == 10
		and Rules.short_match_bonus(false, 0xb, 3, true) == 3 and Rules.short_match_bonus(true, 0, 3, true, true) == 0, "the short-match branch: double on a win, 0 when dead")
	# The profile.
	var hero = Profile.create("iron", "Iron Test")
	hero.data.mode = Profile.MODE_IRONMAN
	check(hero.validate().is_empty() and hero.is_ironman() and not Profile.create("plain", "Plain").is_ironman(), "an Ironman profile validates")
	hero.data.mode = "bronzeman"
	check(not hero.validate().is_empty(), "an unknown mode is refused")
	hero.data.mode = Profile.MODE_IRONMAN
	var store := Store.new(directory.path_join("ironman"))
	var saves := directory.path_join("ironman-saves")
	DirAccess.make_dir_recursive_absolute(saves)
	check(store.save_profile(hero) and store.select_profile("iron"), "the Ironman hero is saved and selected")
	var session := Match.new()
	session.save_directory = saves
	check(session.bind(hero, Entity.new(11, "AHHX", 0, Vector2.ZERO)) and session.begin(store, "iron-match") , "Ironman match starts")
	check(session.award_xp(3) and int(session.profile.data.xp) == int(hero.data.xp) + 6, "a live award of 3 is doubled (0x527100)")
	session.profile.data.extensions["frozen"] = true
	var before := int(session.profile.data.xp)
	check(session.award_xp(5) and int(session.profile.data.xp) == before, "a frozen hero gains nothing")
	check(not session.profile.advance_level(), "and does not level")
	session.profile.data.extensions["frozen"] = false
	for path in session.saved_game_files(): FileAccess.open(path, FileAccess.WRITE).store_string("save")
	check(FileAccess.file_exists(session.saved_game_files()[0]), "the hero has a saved game")
	check(session.hero_died(store) and session.deleted, "the hero dies: " + session.last_error)
	check(store.load_profile("iron") == null and not FileAccess.file_exists(directory.path_join("ironman").path_join("iron.json")), "the record is gone at once")
	check(not FileAccess.file_exists(session.saved_game_files()[0]) and not FileAccess.file_exists(session.saved_game_files()[1]), "and so are its saved games")
	check(store.selected_profile() == null, "the selection is cleared")
	var dead_result: Dictionary = won_row.context.duplicate(true)
	dead_result["hero_died"] = true
	check(session.finish(store, "iron-result", dead_result) and store.load_profile("iron") == null and not FileAccess.file_exists(directory.path_join("ironman").path_join("iron.json")), "the result writes nothing: the hero stays deleted")
	# An Ironman hero that survives: the result is doubled and written.
	var survivor = Profile.create("iron2", "Iron Two")
	survivor.data.mode = Profile.MODE_IRONMAN
	check(store.save_profile(survivor), "a second Ironman hero")
	var second := Match.new()
	check(second.bind(survivor, Entity.new(12, "AHHX", 0, Vector2.ZERO)) and second.begin(store, "iron2-match"), "its match starts")
	var live_context: Dictionary = won_row.context.duplicate(true)
	check(second.finish(store, "iron2-result", live_context, {}, true), "a won result: " + second.last_error)
	var written = store.load_profile("iron2")
	check(written != null and int(written.data.xp) == int(survivor.data.xp) + 2 * int(won_row.xp) and int(written.data.history.battles_won) == 1, "the win paid double and was written")
	# Delete (the hero book): the record, its backup and the selection.
	check(store.save_profile(survivor) and FileAccess.file_exists(directory.path_join("ironman").path_join("iron2.json.bak")), "a backup exists after a second save")
	check(store.select_profile("iron2") and store.delete_profile("iron2") and store.load_profile("iron2") == null, "delete_profile removes the record")
	check(not FileAccess.file_exists(directory.path_join("ironman").path_join("iron2.json.bak")) and store.selected_profile() == null, "its backup and the selection too")
	check(store.delete_profile("never-existed") and not store.delete_profile("../escape"), "deleting a missing hero is harmless; an unsafe id is refused")
	# A normal hero is untouched by death except the backpack.
	var normal = Profile.create("norm", "Norm")
	check(store.save_profile(normal), "a normal hero")
	var normal_match := Match.new()
	check(normal_match.bind(normal, Entity.new(13, "AHHX", 0, Vector2.ZERO)) and normal_match.hero_died(store) and not normal_match.deleted and store.load_profile("norm") != null, "a normal hero's death keeps the record")
	check(normal_match.award_xp(3) and int(normal_match.profile.data.xp) == int(normal.data.xp) + 3, "and its awards are not doubled")
	for filename in DirAccess.open(directory.path_join("ironman")).get_files(): DirAccess.remove_absolute(directory.path_join("ironman").path_join(filename))
	DirAccess.remove_absolute(directory.path_join("ironman"))
	for filename in DirAccess.open(saves).get_files(): DirAccess.remove_absolute(saves.path_join(filename))
	DirAccess.remove_absolute(saves)

func _initialize():
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/hero_fixtures.json"))
	for i in range(fixtures.thresholds.size()):
		check(Rules.xp_threshold(i + 1) == int(fixtures.thresholds[i]), "original threshold " + str(i + 1))
	for row in fixtures.derived:
		check(Rules.derived(row.stats, int(row.kind), int(row.mode)) == int(row.value), "original derived " + str(row))
	for row in fixtures.result_bonuses:
		check(Rules.result_bonus(row.context) == int(row.xp), "original result " + str(row.context))
	for row in fixtures.title_ranks:
		check(Rules.title_rank(int(row.category), int(row.value)) == int(row.rank), "original title tier")
	for row in fixtures.result_progression:
		var count := Rules.result_levels(int(row.level), int(row.xp))
		check(count == int(row.gained), "original queued levels")
		check(int(row.level) + count == int(row.final_level), "original accepted level")
		check(int(row.stat_points) + count == int(row.final_stat_points) and int(row.skill_points) + count == int(row.final_skill_points), "original result points")
	var profile = Profile.create("parity", "Sir Test")
	check(profile.validate().is_empty(), "created profile valid")
	for i in range(4): check(int(profile.data.stats[i]) == int(fixtures.creation.starting_stats[i]), "original starting stat")
	check(profile.data.skills == fixtures.creation.skills, "original skills")
	check(profile.gain_xp(50) and profile.data.level == 2, "one pending level")
	check(not profile.advance_level(), "allocation gates next level")
	check(not profile.allocate_skill(21), "unlock level enforced")
	check(profile.allocate_stat(0), "allocate stat")
	check(profile.allocate_skill(1) and profile.data.level == 2, "allocation does not bypass results level limit")
	check(profile.advance_level() and profile.data.level == 3, "next live update after allocation")
	check(not Profile.valid_id("../escape") and not Profile.valid_id("selection"), "safe profile IDs")
	var directory := "user://hero-tests-" + Crypto.new().generate_random_bytes(8).hex_encode()
	var store := Store.new(directory)
	check(store.save_profile(profile), "first save " + store.last_error)
	check(store.save_profile(profile), "replace save " + store.last_error)
	var loaded = store.load_profile("parity")
	check(loaded != null and loaded.snapshot() == JSON.parse_string(JSON.stringify(profile.snapshot())), "roundtrip")
	check(store.select_profile("parity") and store.selected_profile() != null, "selection")
	check(store.list_profiles().size() == 1, "selection excluded from hero list")
	var session := Match.new()
	check(not session.bind(profile, Entity.new(10, "ASWX", 0, Vector2.ZERO)), "reject wrong entity type")
	check(session.bind(profile, Entity.new(10, "AHHX", 0, Vector2(32,24))), "bind M6 entity")
	check(session.entity.entity_id == 10 and session.entity.position == Vector2(32,24), "preserve match identity")
	check(session.award_xp(3), "resolved match award")
	check(profile.data.xp == 50, "match isolates original profile")
	session.profile.data.backpack[0] = {"id": 1}
	session.profile.data.equipment[0] = {"id": 2}
	session.profile.data.retinue = [{"id": "veteran", "original_type_id": "ASWX", "xp": 110, "medal_level": 6, "name": "Veteran", "permanent_state": {"level": 6}}]
	check(session.hero_died(store), "death saves")
	check(session.profile.data.backpack[0].is_empty() and session.profile.data.equipment[0].id == 2, "death inventory rule")
	var context: Dictionary = fixtures.result_bonuses[0].context.duplicate(true)
	check(session.finish(store, "battle-1", context), "completed result saves " + session.last_error)
	var xp: int = session.profile.data.xp
	check(session.finish(store, "battle-1", context) and session.profile.data.xp == xp, "result idempotent")
	check(store.load_profile("parity").data.retinue[0].xp == 110, "retinue XP preserved")
	var survivor: Dictionary = session.profile.data.retinue[0].duplicate(true)
	survivor.xp = 116
	check(session.finish(store, "battle-survivor", context, {"retinue_updates": [survivor]}), "resolved survivor result")
	check(store.load_profile("parity").data.retinue[0].xp == 116, "retinue XP written back")
	check(not session.finish(store, "battle-2", context, {"retinue": []}), "unrecovered selection rejected")
	var future := FileAccess.open(directory.path_join("future.json"), FileAccess.WRITE)
	future.store_string('{"schema_version":999}')
	future.close()
	check(store.load_profile("future") == null, "future schema rejected")
	var corrupt := Profile.create("future", "Future")
	check(not store.save_profile(corrupt), "unknown save not overwritten")
	ironman_checks(fixtures, directory)
	var files := DirAccess.open(directory).get_files()
	for filename in files: DirAccess.remove_absolute(directory.path_join(filename))
	DirAccess.remove_absolute(directory)
	if failures == 0: print("Hero checks passed: ", checks)
	quit(0 if failures == 0 else 1)
