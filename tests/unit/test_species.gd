extends TestCase

## Species + SpeciesDb: the five monkey types, their placeholder colours, their
## food likes and dislikes, and their stat tendency.
##
## Dossier §8 [C]: "Five types, excluding bosses ... type is mechanically
## load-bearing, not cosmetic — it drives food preferences and item drop rates."
## §14.4 [X]: none of the five is named in any source, so the names here are
## acknowledged inventions. §5 [C] is the one confirmed preference rule: most
## monkeys like bananas, curry and ice milk; some dislike garlic, chicken and
## liver.
##
## Translation trap the dossier flags (§14): Japanese 「5種類」 refers to the five
## training minigames, NOT to five species. The two fives are unrelated.

# --- the table -------------------------------------------------------------

func test_type_enum_ordering_is_pinned() -> void:
	# species_type is serialised as an int in every save.
	assert_eq(int(Species.Type.SUNBURST), 0)
	assert_eq(int(Species.Type.MIDNIGHT), 1)
	assert_eq(int(Species.Type.EMERALD), 2)
	assert_eq(int(Species.Type.ASHEN), 3)
	assert_eq(int(Species.Type.CRIMSON), 4)
	assert_eq(Species.Type.values().size(), 5, "dossier §8 [C]: five types, excluding bosses")


func test_every_enum_type_has_a_row_and_the_row_agrees_with_its_key() -> void:
	for type in Species.Type.values():
		var species := SpeciesDb.get_species(type)
		assert_not_null(species, "no row for type %d" % type)
		assert_eq(species.type, type, "SpeciesDb keyed a row under the wrong type")
		assert_ne(species.display_name, "")


func test_all_returns_the_five_in_enum_order() -> void:
	var all := SpeciesDb.all()
	assert_eq(all.size(), 5)
	for i in all.size():
		assert_eq(int(all[i].type), i, "all() must be in enum order so a UI list is stable")


func test_all_hands_back_a_fresh_array_each_call() -> void:
	var first := SpeciesDb.all()
	first.clear()
	assert_eq(SpeciesDb.all().size(), 5, "a caller mutating the array must not empty the table")


func test_lookups_are_cached_and_stable() -> void:
	var a := SpeciesDb.get_species(Species.Type.MIDNIGHT)
	var b := SpeciesDb.get_species(Species.Type.MIDNIGHT)
	assert_true(a == b, "repeated lookups must return the same instance, not a rebuilt one")


func test_default_type_is_the_starter() -> void:
	# Dossier §7 phase 0 [C]: Fred hands over Freddy on day 1; §8 [C] his name is
	# fixed. The starter type is the one the intro screens will show.
	assert_eq(SpeciesDb.default_type(), Species.Type.SUNBURST)
	assert_not_null(SpeciesDb.get_species(SpeciesDb.default_type()))


func test_an_out_of_range_type_falls_back_instead_of_crashing() -> void:
	var bogus: Species.Type = 99 as Species.Type
	var species := SpeciesDb.get_species(bogus)
	assert_not_null(species, "a corrupt save must not take the game down")
	assert_eq(species.type, SpeciesDb.default_type())


# --- placeholder colours ---------------------------------------------------

func test_every_species_has_a_distinct_opaque_body_colour() -> void:
	# Art is placeholder shapes only, so colour is the ONLY thing separating the
	# five types on screen. Two types sharing a fill would be unreadable.
	var seen: Array[Color] = []
	for species in SpeciesDb.all():
		assert_almost_eq(species.body_color.a, 1.0, 0.001,
			"%s's body colour must be opaque" % species.display_name)
		for other in seen:
			var distance: float = absf(other.r - species.body_color.r) \
				+ absf(other.g - species.body_color.g) \
				+ absf(other.b - species.body_color.b)
			assert_true(distance > 0.3,
				"%s is too close to another type's colour" % species.display_name)
		seen.append(species.body_color)


func test_the_accent_is_darker_than_the_body() -> void:
	for species in SpeciesDb.all():
		assert_true(species.accent_color.get_luminance() < species.body_color.get_luminance(),
			"%s's accent must read as an outline/shadow against its body" % species.display_name)


# --- food preferences ------------------------------------------------------

func test_no_food_is_both_liked_and_disliked() -> void:
	for species in SpeciesDb.all():
		for food_id in species.liked_foods:
			assert_false(species.dislikes(food_id),
				"%s both likes and dislikes %s" % [species.display_name, food_id])


func test_every_type_has_at_least_one_like_and_one_dislike() -> void:
	# §8 [C]: type is mechanically load-bearing. A type with no preferences at
	# all would be cosmetic, which the dossier explicitly rules out.
	for species in SpeciesDb.all():
		assert_true(species.liked_foods.size() >= 1, "%s likes nothing" % species.display_name)
		assert_true(species.disliked_foods.size() >= 1, "%s dislikes nothing" % species.display_name)


func test_preferences_are_not_all_identical() -> void:
	var signatures := {}
	for species in SpeciesDb.all():
		var liked := Array(species.liked_foods)
		liked.sort()
		var disliked := Array(species.disliked_foods)
		disliked.sort()
		signatures[str(liked) + "|" + str(disliked)] = true
	assert_true(signatures.size() >= 4,
		"the five types must not share one preference list — type drives food choice (§8 [C])")


func test_bananas_are_the_universal_befriending_food() -> void:
	# Dossier §5 [C]: the documented fastest path to befriending is two bananas.
	# That has to work whichever type the player is holding.
	for species in SpeciesDb.all():
		assert_true(species.likes("banana"), "%s must like bananas" % species.display_name)
		assert_false(species.dislikes("banana"))


func test_the_documented_dislikes_are_the_ones_used() -> void:
	# Dossier §5 [C]: "some dislike garlic, chicken and liver." Nothing outside
	# that trio, plus ice milk as the one acknowledged extra, should appear.
	var allowed := ["garlic", "chicken", "liver", "ice_milk"]
	for species in SpeciesDb.all():
		for food_id in species.disliked_foods:
			assert_has(allowed, food_id,
				"%s dislikes %s, which no source lists as a disliked food" % [species.display_name, food_id])


func test_liked_and_disliked_ids_all_exist_in_the_food_table() -> void:
	for species in SpeciesDb.all():
		for food_id in species.liked_foods:
			assert_true(FoodDb.has_food(food_id),
				"%s likes unknown food '%s'" % [species.display_name, food_id])
		for food_id in species.disliked_foods:
			assert_true(FoodDb.has_food(food_id),
				"%s dislikes unknown food '%s'" % [species.display_name, food_id])


func test_friendship_multiplier_ranks_liked_over_neutral_over_disliked() -> void:
	var crimson := SpeciesDb.get_species(Species.Type.CRIMSON)
	assert_almost_eq(crimson.friendship_multiplier_for("curry"), 2.0)
	assert_almost_eq(crimson.friendship_multiplier_for("bread"), 1.0)
	assert_almost_eq(crimson.friendship_multiplier_for("garlic"), -0.5, 0.0001,
		"a disliked food must cost friendship, not merely give none")


func test_friendship_multiplier_is_neutral_for_junk_ids() -> void:
	var species := SpeciesDb.get_species(Species.Type.ASHEN)
	assert_almost_eq(species.friendship_multiplier_for(""), 1.0)
	assert_almost_eq(species.friendship_multiplier_for("moon_rocks"), 1.0)
	assert_false(species.likes(""))
	assert_false(species.dislikes(""))


func test_two_liked_feeds_clear_the_befriending_threshold() -> void:
	# The tuning target from the dossier (§5 [C]) is "two bananas". Care applies
	# its per-feed friendship through this multiplier, so the multiplier has to
	# be big enough that two liked feeds cross Monkey.FRIENDSHIP_TRAIN_MIN at a
	# plausible base rate. Kept local rather than importing Care's constant so
	# this file stays independent of another system's parse state.
	var base_per_feed := 6
	var species := SpeciesDb.get_species(SpeciesDb.default_type())
	var gained := int(base_per_feed * species.friendship_multiplier_for("banana")) * 2
	assert_true(gained >= Monkey.FRIENDSHIP_TRAIN_MIN,
		"two bananas must befriend a starter: got %d, need %d" % [gained, Monkey.FRIENDSHIP_TRAIN_MIN])


# --- stat tendency ---------------------------------------------------------

func test_cap_bias_covers_all_five_stats_and_stays_positive() -> void:
	for species in SpeciesDb.all():
		for stat in Monkey.STATS:
			var bias := species.cap_bias_for(stat)
			assert_in_range(bias, 0.5, 1.5,
				"%s's %s bias is out of band" % [species.display_name, Monkey.stat_key(stat)])


func test_cap_bias_defaults_to_neutral_for_an_unknown_key() -> void:
	var blank := Species.new()
	assert_almost_eq(blank.cap_bias_for(Monkey.Stat.POWER), 1.0)
	assert_almost_eq(SpeciesDb.get_species(Species.Type.CRIMSON).cap_bias_for(99), 1.0)


func test_no_type_is_strictly_better_than_another() -> void:
	# Choosing a type should be a trade-off, not a right answer.
	for species in SpeciesDb.all():
		var total := 0.0
		for stat in Monkey.STATS:
			total += species.cap_bias_for(stat)
		assert_in_range(total, 4.9, 5.2,
			"%s's total bias (%.2f) makes it strictly better or worse than the rest"
				% [species.display_name, total])


func test_each_type_leans_a_different_way() -> void:
	var tendencies := {}
	var balanced := 0
	for species in SpeciesDb.all():
		var stat := species.tendency_stat()
		if stat < 0:
			balanced += 1
			assert_eq(species.tendency_label(), "BALANCED")
		else:
			assert_has(Monkey.STATS, stat)
			assert_eq(species.tendency_label(), Monkey.stat_label(stat))
			assert_false(tendencies.has(stat),
				"%s duplicates another type's tendency" % species.display_name)
			tendencies[stat] = species.display_name
	assert_eq(balanced, 1, "exactly one type should read as balanced")
	assert_eq(tendencies.size(), 4, "the other four should each lean a different way")


func test_the_starter_type_is_the_balanced_one() -> void:
	# Freddy's fixed caps (145/119/116/145/145, §3 [U]) are the reference tuple,
	# so his type must not skew them.
	var starter := SpeciesDb.get_species(SpeciesDb.default_type())
	assert_eq(starter.tendency_stat(), -1)
	for stat in Monkey.STATS:
		assert_almost_eq(starter.cap_bias_for(stat), 1.0)


func test_tendency_stat_reads_the_bias_table() -> void:
	var custom := Species.new()
	custom.cap_bias = {
		Monkey.Stat.POWER: 1.0,
		Monkey.Stat.SPEED: 1.0,
		Monkey.Stat.KNOWLEDGE: 1.4,
		Monkey.Stat.STRENGTH: 1.0,
		Monkey.Stat.STAMINA: 1.0,
	}
	assert_eq(custom.tendency_stat(), Monkey.Stat.KNOWLEDGE)
	assert_eq(custom.tendency_label(), "KNOW")


func test_a_tie_reads_as_balanced_rather_than_picking_arbitrarily() -> void:
	var custom := Species.new()
	custom.cap_bias = {Monkey.Stat.POWER: 1.2, Monkey.Stat.SPEED: 1.2}
	assert_eq(custom.tendency_stat(), -1, "two equal leaders is not a tendency")
	assert_eq(custom.tendency_label(), "BALANCED")


func test_a_species_with_no_bias_at_all_is_balanced() -> void:
	assert_eq(Species.new().tendency_stat(), -1)


# --- determinism -----------------------------------------------------------

func test_picking_a_species_with_a_seeded_rng_is_reproducible() -> void:
	# All randomness in core goes through an injected MpRng so a run replays
	# identically. Species selection is the simplest thing to pin that with.
	var first: Array[int] = []
	var second: Array[int] = []
	var rng_a := MpRng.new(20000324)
	var rng_b := MpRng.new(20000324)
	for i in 20:
		first.append(int((rng_a.pick(SpeciesDb.all()) as Species).type))
		second.append(int((rng_b.pick(SpeciesDb.all()) as Species).type))
	assert_eq(first, second, "the same seed must produce the same sequence of types")
	var distinct := {}
	for type in first:
		distinct[type] = true
	assert_true(distinct.size() >= 3, "20 picks should not collapse onto one or two types")


func test_a_different_seed_gives_a_different_sequence() -> void:
	var a: Array[int] = []
	var b: Array[int] = []
	var rng_a := MpRng.new(1)
	var rng_b := MpRng.new(2)
	for i in 20:
		a.append(int((rng_a.pick(SpeciesDb.all()) as Species).type))
		b.append(int((rng_b.pick(SpeciesDb.all()) as Species).type))
	assert_ne(a, b)


# --- the type choice has to mean something -----------------------------------
#
# Added by the Verification agent. `ui/screens/monkey_select.gd` shows the player
# a per-type starter cap tuple before they commit, but `RunState.make_starter()`
# used the unbiased table, so every type came out with identical ceilings and the
# screen was advertising a mechanic that did not exist.

func test_the_starter_type_actually_shapes_its_ceilings() -> void:
	var base := RunState.starter_caps()
	# Freddy's own type reproduces the attested tuple exactly (§3 [U]).
	var default_caps := RunState.starter_caps_for(SpeciesDb.default_type())
	for stat in Monkey.STATS:
		assert_eq(int(default_caps[stat]), int(base[stat]),
			"the default type must not move Freddy's observed cap for %s"
				% Monkey.stat_label(stat))

	# A biased type must differ somewhere, and the built monkey must agree with
	# the table the select screen prints.
	var crimson := RunState.starter_caps_for(Species.Type.CRIMSON)
	var differs := false
	for stat in Monkey.STATS:
		if int(crimson[stat]) != int(base[stat]):
			differs = true
	assert_true(differs, "a biased type must produce different ceilings")

	for species in SpeciesDb.all():
		var monkey := RunState.make_starter(species.type)
		var expected := RunState.starter_caps_for(species.type)
		for stat in Monkey.STATS:
			assert_eq(monkey.get_cap(stat), int(expected[stat]),
				"%s starter cap for %s" % [species.display_name, Monkey.stat_label(stat)])
			assert_true(monkey.get_cap(stat) > 0, "no starter cap may be zero")
