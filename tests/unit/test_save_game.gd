extends TestCase

## core/save_game.gd — one continuous save of a whole run (dossier §7 phase 6
## [C]: the post-game continues on the same save, there is no New Game+).
##
## Two things are being pinned here:
##  1. A full round trip is lossless — serialise -> restore and save -> load
##     both reproduce the run exactly.
##  2. A missing, truncated, non-JSON, wrong-version or structurally wrong save
##     degrades gracefully instead of crashing.


func before_each() -> void:
	SaveGame.delete_save()


func after_each() -> void:
	SaveGame.delete_save()


# --- fixtures --------------------------------------------------------------

func _make_run() -> RunState:
	var state := RunState.new()
	state.protagonist = RunState.Protagonist.SUMIRE
	state.phase = RunState.Phase.LADDER
	state.rules = GameRules.new()
	state.rng = MpRng.new(20000324)   # the JP release date, for a memorable seed
	# Burn some of the stream so the saved state is not the seed's start.
	state.rng.randf()
	state.rng.randi_range(0, 99)

	state.economy = Economy.new(state.rules)
	state.economy.money = 4321
	state.economy.add_food("banana", 3)
	state.economy.add_food("curry", 1)
	state.economy.add_junk("watch", 2)

	state.day_cycle = DayCycle.new()
	state.day_cycle.day = 7
	state.day_cycle.slot = DayCycle.Slot.PM

	state.ladder = Ladder.new(state.rules, state.rng)
	state.ladder.rank = 3

	state.care = Care.new(state.rules, state.rng)
	state.training = Training.new(state.rules, state.rng)
	state.breeding = Breeding.new(state.rules, state.rng)

	state.active_monkey = _make_monkey("Freddy", 2)
	state.roster.append(_make_retired_parent())

	var opponent := Ladder.Opponent.new()
	opponent.monkey = _make_monkey("Agatha", 1)
	opponent.rank = 2
	opponent.trainer_name = "Bill"
	opponent.purse = 2600
	opponent.is_above_player = true
	state.booked_opponent = opponent

	state.flags = {"seen_intro": true, "passed_pro_test": false}
	state.play_seconds = 1234.5
	return state


func _make_monkey(p_name: String, p_generation: int) -> Monkey:
	var caps := RunState.starter_caps()
	var monkey := Monkey.create(p_name, SpeciesDb.default_type(), caps, p_generation, Monkey.Sex.MALE)
	monkey.set_stat(Monkey.Stat.POWER, 74)
	monkey.set_stat(Monkey.Stat.SPEED, 65)
	monkey.set_stat(Monkey.Stat.KNOWLEDGE, 56)
	monkey.set_stat(Monkey.Stat.STRENGTH, 61)
	monkey.set_stat(Monkey.Stat.STAMINA, 83)
	monkey.friendship = 48
	monkey.fullness = 11
	monkey.restore_pools()
	monkey.current_strength = 30
	monkey.wins = 4
	monkey.losses = 1
	monkey.days_since_match = 2
	monkey.personal_bests = {
		Training.Activity.SKIPPING: 102,
		Training.Activity.SIT_UPS: 47,
	}
	return monkey


func _make_retired_parent() -> Monkey:
	var parent := _make_monkey("Lemon", 1)
	parent.retired = true
	parent.monkey_name = "Lemon"
	return parent


# --- round trip ------------------------------------------------------------

func test_serialise_restore_is_deeply_equal() -> void:
	var original := _make_run()
	var snapshot := SaveGame.serialise(original)
	var restored := SaveGame.restore(snapshot)
	assert_not_null(restored)
	assert_eq(_diff(SaveGame.serialise(restored), snapshot, "run"), "")


func test_a_full_file_round_trip_is_deeply_equal() -> void:
	var original := _make_run()
	assert_true(SaveGame.save(original))
	assert_true(SaveGame.has_save())

	var loaded := SaveGame.load_run()
	assert_not_null(loaded)
	assert_eq(_diff(SaveGame.serialise(loaded), SaveGame.serialise(original), "run"), "")


func test_the_restored_run_carries_every_field_the_ui_reads() -> void:
	var original := _make_run()
	var restored := SaveGame.restore(SaveGame.serialise(original))
	assert_not_null(restored)
	assert_eq(int(restored.protagonist), int(RunState.Protagonist.SUMIRE))
	assert_eq(int(restored.phase), int(RunState.Phase.LADDER))
	assert_eq(restored.day_cycle.day, 7)
	assert_eq(int(restored.day_cycle.slot), int(DayCycle.Slot.PM))
	assert_eq(restored.ladder.rank, 3)
	assert_eq(restored.economy.money, 4321)
	assert_eq(restored.economy.food_count("banana"), 3)
	assert_eq(restored.economy.junk_count("watch"), 2)
	assert_eq(restored.active_monkey.monkey_name, "Freddy")
	assert_eq(restored.active_monkey.generation, 2)
	assert_eq(restored.active_monkey.get_stat(Monkey.Stat.POWER), 74)
	assert_eq(restored.active_monkey.get_cap(Monkey.Stat.POWER), 145)
	assert_eq(restored.active_monkey.friendship, 48)
	assert_eq(restored.active_monkey.current_strength, 30)
	assert_eq(restored.active_monkey.wins, 4)
	assert_true(restored.has_flag("seen_intro"))
	assert_false(restored.has_flag("passed_pro_test"))
	assert_almost_eq(restored.play_seconds, 1234.5)


func test_the_retired_roster_survives_because_the_parent_is_not_destroyed() -> void:
	# GameRules.breeding_destroys_parent = false: the parent retires to a
	# viewable roster instead of vanishing, so the save must carry it.
	var original := _make_run()
	var restored := SaveGame.restore(SaveGame.serialise(original))
	assert_eq(restored.roster.size(), 1)
	assert_eq(restored.roster[0].monkey_name, "Lemon")
	assert_true(restored.roster[0].retired)


func test_the_booked_opponent_survives_a_save_between_offer_and_fight() -> void:
	# Bill offers today and the fight is tomorrow (dossier §7 [C]), so a save in
	# between must remember who was booked.
	var original := _make_run()
	var restored := SaveGame.restore(SaveGame.serialise(original))
	assert_not_null(restored.booked_opponent)
	assert_eq(restored.booked_opponent.rank, 2)
	assert_eq(restored.booked_opponent.trainer_name, "Bill")
	assert_eq(restored.booked_opponent.monkey.monkey_name, "Agatha")
	assert_true(restored.booked_opponent.is_above_player)


func test_the_random_stream_resumes_where_it_left_off() -> void:
	var original := _make_run()
	var restored := SaveGame.restore(SaveGame.serialise(original))
	assert_eq(restored.rng.seed_value(), original.rng.seed_value())
	assert_eq(restored.rng.state(), original.rng.state())
	assert_almost_eq(restored.rng.randf(), original.rng.randf(),
		0.0, "a reloaded run continues the same deterministic sequence")


func test_the_rules_flags_travel_with_the_save() -> void:
	var original := _make_run()
	original.rules.bankruptcy_game_over = true
	original.rules.disobedience_enabled = true
	original.rules.overfeeding_paralyses = true
	var restored := SaveGame.restore(SaveGame.serialise(original))
	assert_true(restored.rules.bankruptcy_game_over)
	assert_true(restored.rules.disobedience_enabled, "faithful rule must not be lost")
	assert_true(restored.rules.overfeeding_paralyses, "faithful rule must not be lost")


func test_the_restored_run_has_live_systems_wired_to_its_own_rules() -> void:
	var restored := SaveGame.restore(SaveGame.serialise(_make_run()))
	assert_not_null(restored.care)
	assert_not_null(restored.training)
	assert_not_null(restored.breeding)
	assert_not_null(restored.economy)
	assert_not_null(restored.ladder)
	assert_not_null(restored.day_cycle)


func test_a_run_with_no_monkey_and_no_extras_round_trips() -> void:
	var bare := RunState.new()
	bare.rules = GameRules.new()
	bare.rng = MpRng.new(7)
	bare.economy = Economy.new(bare.rules)
	bare.day_cycle = DayCycle.new()
	bare.ladder = Ladder.new(bare.rules, bare.rng)
	var restored := SaveGame.restore(SaveGame.serialise(bare))
	assert_not_null(restored)
	assert_null(restored.active_monkey)
	assert_null(restored.booked_opponent)
	assert_eq(restored.roster.size(), 0)
	assert_eq(restored.economy.total_food(), 0)


# --- peek ------------------------------------------------------------------

func test_peek_reports_no_save_before_anything_is_written() -> void:
	assert_false(SaveGame.has_save())
	assert_eq(SaveGame.peek(), {"exists": false})


func test_peek_summarises_without_loading_the_run() -> void:
	SaveGame.save(_make_run())
	var summary := SaveGame.peek()
	assert_true(summary.get("exists", false))
	assert_eq(summary.get("day"), 7)
	assert_eq(summary.get("monkey_name"), "Freddy")
	assert_eq(summary.get("rank"), 3)
	assert_eq(summary.get("generation"), 2)
	assert_eq(summary.get("version"), SaveGame.SAVE_VERSION)


# --- failure modes ---------------------------------------------------------

func test_loading_with_no_save_returns_null_rather_than_crashing() -> void:
	assert_false(SaveGame.has_save())
	assert_null(SaveGame.load_run())


func test_a_corrupt_save_fails_gracefully() -> void:
	_write_raw("this is not JSON {{{ ~~~ ")
	assert_true(SaveGame.has_save(), "the file exists — it is just unreadable")
	assert_null(SaveGame.load_run())
	assert_eq(SaveGame.peek(), {"exists": false})


func test_a_truncated_save_fails_gracefully() -> void:
	var text := JSON.stringify(SaveGame.serialise(_make_run()))
	_write_raw(text.substr(0, text.length() / 2))
	assert_null(SaveGame.load_run())
	assert_eq(SaveGame.peek(), {"exists": false})


func test_valid_json_that_is_not_an_object_fails_gracefully() -> void:
	_write_raw("[1, 2, 3]")
	assert_null(SaveGame.load_run())
	assert_eq(SaveGame.peek(), {"exists": false})


func test_an_empty_or_versionless_payload_is_refused() -> void:
	assert_null(SaveGame.restore({}))
	assert_null(SaveGame.restore({"day_cycle": {"day": 4}}))


func test_a_future_save_version_is_refused_rather_than_misread() -> void:
	var snapshot := SaveGame.serialise(_make_run())
	snapshot["version"] = SaveGame.SAVE_VERSION + 1
	assert_null(SaveGame.restore(snapshot))


func test_structurally_wrong_sections_degrade_to_defaults() -> void:
	var wrecked := {
		"version": SaveGame.SAVE_VERSION,
		"protagonist": "nonsense",
		"rules": "nonsense",
		"economy": "nonsense",
		"day_cycle": 5,
		"ladder": [],
		"roster": "nonsense",
		"active_monkey": [],
		"booked_opponent": 0,
		"flags": 3,
		"play_seconds": "nonsense",
	}
	var restored := SaveGame.restore(wrecked)
	assert_not_null(restored, "a structurally wrong save degrades, it does not crash")
	assert_eq(restored.economy.money, Economy.STARTING_MONEY)
	assert_eq(restored.day_cycle.day, 1)
	assert_null(restored.active_monkey)
	assert_null(restored.booked_opponent)
	assert_eq(restored.roster.size(), 0)
	assert_eq(restored.flags, {})


func test_saving_a_null_run_is_refused() -> void:
	assert_false(SaveGame.save(null))
	assert_false(SaveGame.has_save())


func test_delete_save_removes_the_file_and_is_honest_when_there_is_none() -> void:
	assert_false(SaveGame.delete_save(), "nothing to delete")
	SaveGame.save(_make_run())
	assert_true(SaveGame.has_save())
	assert_true(SaveGame.delete_save())
	assert_false(SaveGame.has_save())


func test_saving_twice_overwrites_rather_than_appends() -> void:
	var state := _make_run()
	SaveGame.save(state)
	state.day_cycle.day = 19
	state.economy.money = 10
	assert_true(SaveGame.save(state))
	var loaded := SaveGame.load_run()
	assert_not_null(loaded)
	assert_eq(loaded.day_cycle.day, 19)
	assert_eq(loaded.economy.money, 10)


# --- helpers ---------------------------------------------------------------

func _write_raw(text: String) -> void:
	var file := FileAccess.open(SaveGame.SAVE_PATH, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Recursive diff so a round-trip failure names the exact key that drifted.
## Returns "" when the two values are deeply equal.
func _diff(actual: Variant, expected: Variant, path: String) -> String:
	if typeof(expected) == TYPE_DICTIONARY:
		if typeof(actual) != TYPE_DICTIONARY:
			return "%s: expected a Dictionary, got %s" % [path, type_string(typeof(actual))]
		var expected_dict := expected as Dictionary
		var actual_dict := actual as Dictionary
		for key in expected_dict:
			if not actual_dict.has(key):
				return "%s.%s: missing" % [path, str(key)]
			var nested := _diff(actual_dict[key], expected_dict[key], "%s.%s" % [path, str(key)])
			if nested != "":
				return nested
		for key in actual_dict:
			if not expected_dict.has(key):
				return "%s.%s: unexpected extra key" % [path, str(key)]
		return ""
	if typeof(expected) == TYPE_ARRAY:
		if typeof(actual) != TYPE_ARRAY:
			return "%s: expected an Array, got %s" % [path, type_string(typeof(actual))]
		var expected_array := expected as Array
		var actual_array := actual as Array
		if expected_array.size() != actual_array.size():
			return "%s: expected %d entries, got %d" % [path, expected_array.size(), actual_array.size()]
		for i in expected_array.size():
			var nested := _diff(actual_array[i], expected_array[i], "%s[%d]" % [path, i])
			if nested != "":
				return nested
		return ""
	if typeof(expected) == TYPE_FLOAT or typeof(actual) == TYPE_FLOAT:
		if is_equal_approx(float(actual), float(expected)):
			return ""
		return "%s: expected %s, got %s" % [path, str(expected), str(actual)]
	if actual == expected:
		return ""
	return "%s: expected %s, got %s" % [path, str(expected), str(actual)]


# --- atomic write ----------------------------------------------------------
#
# `save()` writes to a scratch file and renames it over the real one. Opening
# the save directly for WRITE truncates it before the new bytes land, so a
# process killed in that window — the realistic case being the OS reaping a
# backgrounded app on a phone — leaves a half-written file and the player loses
# the entire run rather than the last few minutes.

func test_saving_leaves_no_scratch_file_behind() -> void:
	assert_true(SaveGame.save(_make_run()), "the save should succeed")
	assert_true(SaveGame.has_save(), "the real save file should exist")
	assert_false(FileAccess.file_exists(SaveGame.TEMP_PATH),
		"the scratch file should have been renamed away, not left lying around")


func test_the_previous_save_survives_until_the_new_one_is_complete() -> void:
	# The property that matters: at no point does SAVE_PATH hold a partial file.
	# Directly observing the mid-write instant is not possible in-process, so this
	# asserts the mechanism instead — the bytes are built somewhere else first,
	# and the scratch path is never the path the game reads from.
	assert_ne(SaveGame.TEMP_PATH, SaveGame.SAVE_PATH,
		"the scratch file must not be the file the game loads")
	var first := _make_run()
	first.economy.earn(4321)
	assert_true(SaveGame.save(first))
	var before := FileAccess.get_file_as_string(SaveGame.SAVE_PATH)
	assert_true(before.length() > 0, "the first save should have written something")

	var second := _make_run()
	second.economy.earn(8765)
	assert_true(SaveGame.save(second))
	var after := FileAccess.get_file_as_string(SaveGame.SAVE_PATH)
	assert_ne(after, before, "the second save should have replaced the first")
	var reloaded := SaveGame.load_run()
	assert_not_null(reloaded, "and the replacement must be a complete, loadable file")


func test_a_leftover_scratch_file_does_not_break_the_next_save() -> void:
	# What a killed write leaves behind. The next save must overwrite it rather
	# than refuse, and the loaded run must be the new one.
	var junk := FileAccess.open(SaveGame.TEMP_PATH, FileAccess.WRITE)
	assert_not_null(junk, "could not stage a leftover scratch file")
	if junk != null:
		junk.store_string("{ this is half a save")
		junk.close()

	var run := _make_run()
	run.economy.earn(999)
	assert_true(SaveGame.save(run), "a leftover scratch file should not block a save")
	assert_false(FileAccess.file_exists(SaveGame.TEMP_PATH),
		"the leftover should have been consumed by the rename")
	var reloaded := SaveGame.load_run()
	assert_not_null(reloaded, "the save written over a leftover should load")


func test_a_leftover_scratch_file_is_never_mistaken_for_a_save() -> void:
	var junk := FileAccess.open(SaveGame.TEMP_PATH, FileAccess.WRITE)
	if junk != null:
		junk.store_string("{ this is half a save")
		junk.close()
	assert_false(SaveGame.has_save(),
		"a scratch file alone is not a save — CONTINUE must stay unavailable")
	assert_null(SaveGame.load_run(), "and there is nothing to load")


func test_deleting_a_save_clears_the_scratch_file_too() -> void:
	assert_true(SaveGame.save(_make_run()))
	var junk := FileAccess.open(SaveGame.TEMP_PATH, FileAccess.WRITE)
	if junk != null:
		junk.store_string("leftover")
		junk.close()
	SaveGame.delete_save()
	assert_false(FileAccess.file_exists(SaveGame.TEMP_PATH),
		"a leftover scratch file should not outlive the save it belonged to")
	assert_false(SaveGame.has_save())
