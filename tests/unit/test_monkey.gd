extends TestCase

## Monkey: the five stats, the five hard caps, the star/capped state, the sex
## marker, hunger and friendship boundaries, and the save round trip.
##
## `tests/unit/test_monkey_stats.gd` covers the happy path. This file goes after
## the edges — zero and negative values, empty dictionaries, cap regression,
## boundary values on every threshold, and a JSON round trip that proves the
## enum-keyed Dictionaries survive being turned into String keys and back.
##
## Dossier §3 [C] is the tie-breaker throughout. THE NAMING TRAP: Strength is
## the health bar, Power is damage.

var monkey: Monkey


func before_each() -> void:
	monkey = Monkey.create("Freddy", Species.Type.SUNBURST, _caps(145, 119, 116, 145, 145))


func _caps(pow_: int, spd: int, know: int, strg: int, stm: int) -> Dictionary:
	return {
		Monkey.Stat.POWER: pow_,
		Monkey.Stat.SPEED: spd,
		Monkey.Stat.KNOWLEDGE: know,
		Monkey.Stat.STRENGTH: strg,
		Monkey.Stat.STAMINA: stm,
	}


# --- enum and table shape --------------------------------------------------

func test_stat_enum_ordering_is_pinned() -> void:
	# Other systems index STAT_LABELS and serialise these as ints. Renumbering
	# the enum would silently rewrite every save file and every stat card.
	assert_eq(int(Monkey.Stat.POWER), 0)
	assert_eq(int(Monkey.Stat.SPEED), 1)
	assert_eq(int(Monkey.Stat.KNOWLEDGE), 2)
	assert_eq(int(Monkey.Stat.STRENGTH), 3)
	assert_eq(int(Monkey.Stat.STAMINA), 4)
	assert_eq(int(Monkey.Sex.MALE), 0)
	assert_eq(int(Monkey.Sex.FEMALE), 1)


func test_stat_tables_are_all_the_same_length() -> void:
	assert_eq(Monkey.STATS.size(), 5)
	assert_eq(Monkey.STAT_KEYS.size(), 5)
	assert_eq(Monkey.STAT_LABELS.size(), 5)
	assert_eq(Monkey.SEX_MARKERS.size(), 2)
	for i in Monkey.STATS.size():
		assert_eq(int(Monkey.STATS[i]), i, "STATS must be in enum order")


func test_stat_keys_and_labels_round_trip_and_are_unique() -> void:
	var seen := {}
	for stat in Monkey.STATS:
		var key := Monkey.stat_key(stat)
		assert_false(seen.has(key), "duplicate stat key: %s" % key)
		seen[key] = true
		assert_eq(Monkey.stat_from_key(key), stat)
		assert_eq(Monkey.stat_label(stat), Monkey.STAT_LABELS[stat])


func test_stat_from_key_falls_back_on_an_unknown_key() -> void:
	# A corrupt save must not crash the loader.
	assert_eq(Monkey.stat_from_key("charisma"), Monkey.Stat.POWER)
	assert_eq(Monkey.stat_from_key(""), Monkey.Stat.POWER)


func test_threshold_constants_are_ordered_sanely() -> void:
	assert_true(Monkey.FULLNESS_STARVING < Monkey.FULLNESS_STUFFED)
	assert_true(Monkey.FULLNESS_STUFFED <= Monkey.FULLNESS_MAX)
	assert_true(Monkey.DIGEST_PER_SLOT > 0, "an overfed monkey must be able to digest")
	assert_true(Monkey.FRIENDSHIP_TRAIN_MIN < Monkey.FRIENDSHIP_OBEDIENT)
	assert_true(Monkey.FRIENDSHIP_OBEDIENT <= Monkey.FRIENDSHIP_MAX)


# --- construction ----------------------------------------------------------

func test_create_copies_the_caps_dictionary() -> void:
	var caps := _caps(10, 10, 10, 10, 10)
	var a := Monkey.create("A", Species.Type.MIDNIGHT, caps)
	var b := Monkey.create("B", Species.Type.MIDNIGHT, caps)
	caps[Monkey.Stat.POWER] = 999
	assert_eq(a.get_cap(Monkey.Stat.POWER), 10, "create() must not alias the caller's caps")
	a.set_cap(Monkey.Stat.POWER, 500)
	assert_eq(b.get_cap(Monkey.Stat.POWER), 10, "two monkeys must not share one caps dict")
	a.add_stat(Monkey.Stat.SPEED, 5)
	assert_eq(b.get_stat(Monkey.Stat.SPEED), 0, "two monkeys must not share one stats dict")


func test_create_fills_missing_caps_with_zero() -> void:
	var partial := {Monkey.Stat.POWER: 50}
	var m := Monkey.create("Sparse", Species.Type.ASHEN, partial)
	assert_eq(m.get_cap(Monkey.Stat.POWER), 50)
	for stat in [Monkey.Stat.SPEED, Monkey.Stat.KNOWLEDGE, Monkey.Stat.STRENGTH, Monkey.Stat.STAMINA]:
		assert_eq(m.get_cap(stat), 0, "an unspecified cap defaults to 0, never to garbage")
		assert_eq(m.get_stat(stat), 0)


func test_create_records_generation_species_and_sex() -> void:
	var m := Monkey.create("Agatha", Species.Type.CRIMSON, _caps(1, 1, 1, 1, 1), 2, Monkey.Sex.FEMALE)
	assert_eq(m.generation, 2)
	assert_eq(m.species_type, Species.Type.CRIMSON)
	assert_eq(m.sex, Monkey.Sex.FEMALE)
	assert_false(m.retired)


func test_a_bare_monkey_never_crashes_on_lookup() -> void:
	var bare := Monkey.new()
	for stat in Monkey.STATS:
		assert_eq(bare.get_stat(stat), 0)
		assert_eq(bare.get_cap(stat), 0)
	assert_eq(bare.max_strength(), 0)
	assert_eq(bare.max_stamina(), 0)
	assert_false(bare.is_befriended())


# --- caps ------------------------------------------------------------------

func test_add_stat_returns_only_what_landed() -> void:
	assert_eq(monkey.add_stat(Monkey.Stat.SPEED, 100), 100)
	assert_eq(monkey.add_stat(Monkey.Stat.SPEED, 100), 19, "SPD cap is 119")
	assert_eq(monkey.add_stat(Monkey.Stat.SPEED, 100), 0, "a starred stat absorbs nothing")
	assert_eq(monkey.get_stat(Monkey.Stat.SPEED), 119)


func test_add_stat_of_zero_is_a_no_op() -> void:
	monkey.add_stat(Monkey.Stat.POWER, 30)
	assert_eq(monkey.add_stat(Monkey.Stat.POWER, 0), 0)
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), 30)


func test_add_stat_accepts_a_negative_amount_and_floors_at_zero() -> void:
	# Nothing in the slice drains a stat, but the Mixer tablets in the original
	# do (§9 [C], "Pow +30, Str -30"), so the primitive must behave.
	monkey.add_stat(Monkey.Stat.POWER, 40)
	assert_eq(monkey.add_stat(Monkey.Stat.POWER, -15), -15)
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), 25)
	assert_eq(monkey.add_stat(Monkey.Stat.POWER, -999), -25, "a stat can never go below zero")
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), 0)


func test_set_stat_clamps_to_the_cap_at_both_ends() -> void:
	monkey.set_stat(Monkey.Stat.KNOWLEDGE, 9999)
	assert_eq(monkey.get_stat(Monkey.Stat.KNOWLEDGE), 116)
	monkey.set_stat(Monkey.Stat.KNOWLEDGE, -50)
	assert_eq(monkey.get_stat(Monkey.Stat.KNOWLEDGE), 0)


func test_a_zero_cap_stat_can_never_be_raised() -> void:
	var m := Monkey.create("Zero", Species.Type.EMERALD, {})
	assert_eq(m.add_stat(Monkey.Stat.POWER, 500), 0)
	assert_eq(m.get_stat(Monkey.Stat.POWER), 0)
	assert_false(m.is_capped(Monkey.Stat.POWER),
		"a 0 cap reads as unfinished, not as starred: otherwise a blank monkey would show five stars")
	assert_false(m.all_capped())


func test_lowering_a_cap_drags_the_stat_down_with_it() -> void:
	# Dossier §8 [C]: caps can REGRESS across a breeding step. If a baby ever
	# inherits a lower ceiling the stat must follow it down, not float above.
	monkey.add_stat(Monkey.Stat.STRENGTH, 145)
	assert_true(monkey.is_capped(Monkey.Stat.STRENGTH))
	monkey.set_cap(Monkey.Stat.STRENGTH, 90)
	assert_eq(monkey.get_stat(Monkey.Stat.STRENGTH), 90)
	assert_true(monkey.is_capped(Monkey.Stat.STRENGTH))


func test_raising_a_cap_reopens_training_without_granting_stats() -> void:
	# Dossier §3 [C]: "Training cannot exceed it; only breeding raises it."
	monkey.add_stat(Monkey.Stat.POWER, 999)
	assert_true(monkey.is_capped(Monkey.Stat.POWER))
	monkey.set_cap(Monkey.Stat.POWER, 204)
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), 145, "a new ceiling is not free stats")
	assert_false(monkey.is_capped(Monkey.Stat.POWER))
	assert_eq(monkey.add_stat(Monkey.Stat.POWER, 100), 59)


func test_set_cap_never_goes_negative() -> void:
	monkey.set_cap(Monkey.Stat.STAMINA, -40)
	assert_eq(monkey.get_cap(Monkey.Stat.STAMINA), 0)
	assert_eq(monkey.get_stat(Monkey.Stat.STAMINA), 0)


func test_all_capped_needs_every_one_of_the_five() -> void:
	for stat in Monkey.STATS:
		monkey.add_stat(stat, 9999)
	assert_true(monkey.all_capped())
	monkey.set_cap(Monkey.Stat.KNOWLEDGE, 200)
	assert_false(monkey.all_capped(), "one un-starred stat is enough to block the breed prompt")


# --- the health bar --------------------------------------------------------

func test_strength_is_the_health_bar_and_there_is_no_hp_stat() -> void:
	# Dossier §3 [C]. Corner bandaging restores Strength; nothing else is HP.
	monkey.add_stat(Monkey.Stat.STRENGTH, 100)
	monkey.add_stat(Monkey.Stat.STAMINA, 80)
	assert_eq(monkey.max_strength(), monkey.get_stat(Monkey.Stat.STRENGTH))
	assert_eq(monkey.max_stamina(), monkey.get_stat(Monkey.Stat.STAMINA))
	monkey.restore_pools()
	assert_eq(monkey.current_strength, 100)
	assert_eq(monkey.current_stamina, 80)


func test_restore_pools_follows_a_stat_gain() -> void:
	monkey.add_stat(Monkey.Stat.STRENGTH, 50)
	monkey.restore_pools()
	assert_eq(monkey.current_strength, 50)
	monkey.current_strength = 4
	monkey.add_stat(Monkey.Stat.STRENGTH, 20)
	assert_eq(monkey.current_strength, 4, "training must not silently heal the health bar")
	monkey.restore_pools()
	assert_eq(monkey.current_strength, 70)


# --- friendship and hunger -------------------------------------------------

func test_befriending_threshold_is_exact() -> void:
	# Dossier §5 [C]: befriending gates everything; every new monkey must be won
	# over with food before it will train.
	monkey.friendship = Monkey.FRIENDSHIP_TRAIN_MIN - 1
	assert_false(monkey.is_befriended())
	monkey.friendship = Monkey.FRIENDSHIP_TRAIN_MIN
	assert_true(monkey.is_befriended(), "the threshold itself counts as befriended")


func test_hunger_paralyses_at_both_ends_on_the_boundary() -> void:
	# Dossier §5 [C]: "Hunger is two-sided and both extremes paralyse."
	# GameRules.overfeeding_paralyses is FAITHFUL and must not be softened.
	monkey.fullness = Monkey.FULLNESS_STARVING
	assert_true(monkey.is_starving(), "the starving threshold itself is immobilising")
	monkey.fullness = Monkey.FULLNESS_STARVING + 1
	assert_false(monkey.is_starving())
	monkey.fullness = Monkey.FULLNESS_STUFFED - 1
	assert_false(monkey.is_stuffed())
	monkey.fullness = Monkey.FULLNESS_STUFFED
	assert_true(monkey.is_stuffed(), "the stuffed threshold itself is immobilising")


func test_a_content_belly_is_neither_extreme() -> void:
	for value in range(Monkey.FULLNESS_STARVING + 1, Monkey.FULLNESS_STUFFED):
		monkey.fullness = value
		assert_false(monkey.is_starving() or monkey.is_stuffed(),
			"fullness %d should leave the monkey mobile" % value)


# --- presentation ----------------------------------------------------------

func test_stat_line_matches_the_stat_card_layout() -> void:
	# Dossier §10 [C]: `POW  74` / `KNOW 56` — a four-column label then the value.
	monkey.add_stat(Monkey.Stat.POWER, 74)
	assert_eq(monkey.stat_line(Monkey.Stat.POWER), "POW  74")
	monkey.add_stat(Monkey.Stat.KNOWLEDGE, 56)
	assert_eq(monkey.stat_line(Monkey.Stat.KNOWLEDGE), "KNOW 56")


func test_stat_line_stars_only_the_capped_stat() -> void:
	monkey.add_stat(Monkey.Stat.SPEED, 9999)
	assert_eq(monkey.stat_line(Monkey.Stat.SPEED), "SPD  119*")
	assert_not_has(monkey.stat_line(Monkey.Stat.POWER), "*")


func test_sex_marker_is_printed_on_the_name_row() -> void:
	# Dossier §8 [U]: the stat card reads `NAME: MAX(ML)`.
	assert_eq(monkey.sex_marker(), "ML")
	assert_eq(monkey.name_line(), "NAME: FREDDY(ML)")
	var her := Monkey.create("Agatha", Species.Type.CRIMSON, {}, 1, Monkey.Sex.FEMALE)
	assert_eq(her.sex_marker(), "FM")
	assert_eq(her.name_line(), "NAME: AGATHA(FM)")


func test_species_lookup_resolves_for_every_type() -> void:
	for type in Species.Type.values():
		var m := Monkey.create("X", type, {})
		assert_not_null(m.species())
		assert_eq(m.species().type, type)


# --- serialisation ---------------------------------------------------------

func _fully_populated() -> Monkey:
	var m := Monkey.create("Tomato", Species.Type.EMERALD, _caps(204, 130, 130, 185, 162), 2, Monkey.Sex.FEMALE)
	m.add_stat(Monkey.Stat.POWER, 90)
	m.add_stat(Monkey.Stat.SPEED, 130)
	m.add_stat(Monkey.Stat.KNOWLEDGE, 41)
	m.add_stat(Monkey.Stat.STRENGTH, 120)
	m.add_stat(Monkey.Stat.STAMINA, 77)
	m.friendship = 64
	m.fullness = 11
	m.restore_pools()
	m.current_strength = 55
	m.current_stamina = 12
	m.paralysed_slots = 2
	m.retired = true
	m.wins = 3
	m.losses = 1
	m.personal_bests = {0: 102, 3: 44}
	m.days_since_match = 1
	return m


func _assert_same(actual: Monkey, expected: Monkey) -> void:
	assert_eq(actual.monkey_name, expected.monkey_name)
	assert_eq(actual.species_type, expected.species_type)
	assert_eq(actual.sex, expected.sex)
	assert_eq(actual.generation, expected.generation)
	for stat in Monkey.STATS:
		assert_eq(actual.get_stat(stat), expected.get_stat(stat),
			"stat %s" % Monkey.stat_key(stat))
		assert_eq(actual.get_cap(stat), expected.get_cap(stat),
			"cap %s" % Monkey.stat_key(stat))
	assert_eq(actual.friendship, expected.friendship)
	assert_eq(actual.fullness, expected.fullness)
	assert_eq(actual.current_strength, expected.current_strength)
	assert_eq(actual.current_stamina, expected.current_stamina)
	assert_eq(actual.paralysed_slots, expected.paralysed_slots)
	assert_eq(actual.retired, expected.retired)
	assert_eq(actual.wins, expected.wins)
	assert_eq(actual.losses, expected.losses)
	assert_eq(actual.days_since_match, expected.days_since_match)
	assert_eq(actual.personal_bests.size(), expected.personal_bests.size())
	for key in expected.personal_bests:
		assert_eq(int(actual.personal_bests.get(int(key), -1)), int(expected.personal_bests[key]),
			"personal best for activity %s" % key)


func test_to_dict_writes_enum_keys_as_ints() -> void:
	# docs/ARCHITECTURE.md §15: all enums serialise as ints, and enum-keyed
	# Dictionary keys must be written as ints.
	var d := monkey.to_dict()
	assert_eq(typeof(d["species_type"]), TYPE_INT)
	assert_eq(typeof(d["sex"]), TYPE_INT)
	for key in (d["caps"] as Dictionary):
		assert_eq(typeof(key), TYPE_INT, "cap key %s is not an int" % key)
	for key in (d["stats"] as Dictionary):
		assert_eq(typeof(key), TYPE_INT, "stat key %s is not an int" % key)


func test_round_trip_preserves_everything() -> void:
	var original := _fully_populated()
	var restored := Monkey.from_dict(original.to_dict())
	assert_not_null(restored)
	_assert_same(restored, original)


func test_round_trip_survives_json_string_keys() -> void:
	# JSON turns every Dictionary key into a String. from_dict must read them
	# back through int(), or every stat silently resets to zero on load.
	var original := _fully_populated()
	var text := JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "the dict must be JSON-encodable")
	var restored := Monkey.from_dict(parsed)
	_assert_same(restored, original)


func test_to_dict_snapshots_rather_than_aliases() -> void:
	var d := monkey.to_dict()
	monkey.add_stat(Monkey.Stat.POWER, 100)
	assert_eq(int((d["stats"] as Dictionary)[Monkey.Stat.POWER]), 0,
		"a saved dict must not keep changing after the save")


func test_from_dict_of_an_empty_dictionary_yields_a_blank_monkey() -> void:
	var m := Monkey.from_dict({})
	assert_not_null(m, "a truncated save must not return null and crash the loader")
	assert_eq(m.monkey_name, "")
	assert_eq(m.generation, 1)
	for stat in Monkey.STATS:
		assert_eq(m.get_stat(stat), 0)
		assert_eq(m.get_cap(stat), 0)
	assert_false(m.retired)


func test_from_dict_clamps_a_corrupt_save() -> void:
	var d := monkey.to_dict()
	(d["caps"] as Dictionary)[Monkey.Stat.POWER] = 100
	(d["stats"] as Dictionary)[Monkey.Stat.POWER] = 9999
	(d["stats"] as Dictionary)[Monkey.Stat.SPEED] = -20
	d["friendship"] = 5000
	d["fullness"] = -3
	d["paralysed_slots"] = -1
	d["generation"] = 0
	var m := Monkey.from_dict(d)
	assert_eq(m.get_stat(Monkey.Stat.POWER), 100, "no stat may load above its own cap")
	assert_eq(m.get_stat(Monkey.Stat.SPEED), 0)
	assert_eq(m.friendship, Monkey.FRIENDSHIP_MAX)
	assert_eq(m.fullness, 0)
	assert_eq(m.paralysed_slots, 0)
	assert_eq(m.generation, 1, "generation 1 is the floor — the starter")


func test_from_dict_clamps_the_live_pools_to_the_stats() -> void:
	var d := monkey.to_dict()
	(d["caps"] as Dictionary)[Monkey.Stat.STRENGTH] = 80
	(d["stats"] as Dictionary)[Monkey.Stat.STRENGTH] = 80
	d["current_strength"] = 4000
	d["current_stamina"] = -10
	var m := Monkey.from_dict(d)
	assert_eq(m.current_strength, 80, "the health bar cannot load above max_strength()")
	assert_eq(m.current_stamina, 0)


func test_round_trip_of_a_retired_parent() -> void:
	# GameRules.breeding_destroys_parent = false: the parent retires to a
	# viewable roster, so retired monkeys must survive a save/load.
	monkey.retired = true
	monkey.wins = 7
	monkey.losses = 2
	var restored := Monkey.from_dict(monkey.to_dict())
	assert_true(restored.retired)
	assert_eq(restored.wins, 7)
	assert_eq(restored.losses, 2)
