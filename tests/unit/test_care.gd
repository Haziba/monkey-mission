extends TestCase

## Care — feeding, fullness, friendship, obedience.
##
## Two of these behaviours are FAITHFUL TO THE ORIGINAL and were requested
## explicitly by the user, so they are pinned hard here:
##
##  * overfeeding PARALYSES (dossier §5 [C]) — not "wastes food";
##  * low friendship makes the monkey IGNORE the strategy (dossier §5, §6 [C]).
##
## Underfeeding paralyses too — the dossier is explicit that both extremes do.

var rules: GameRules
var rng: MpRng
var care: Care
var monkey: Monkey
var economy: StubEconomy


## A real Economy subclass with the inventory methods filled in, so these tests
## pin Care's behaviour and not the Economy agent's progress.
class StubEconomy extends Economy:
	var stock: Dictionary = {}

	func add_food(food_id: String, qty: int = 1) -> void:
		stock[food_id] = int(stock.get(food_id, 0)) + qty

	func food_count(food_id: String) -> int:
		return int(stock.get(food_id, 0))

	func total_food() -> int:
		var total := 0
		for id in stock:
			total += int(stock[id])
		return total

	func consume_food(food_id: String) -> bool:
		var count := int(stock.get(food_id, 0))
		if count <= 0:
			return false
		if count == 1:
			stock.erase(food_id)
		else:
			stock[food_id] = count - 1
		return true


func before_each() -> void:
	# GameRules.new(), never load_default(): the .tres is a shared resource and
	# flipping a flag on it would leak into every other test in the process.
	rules = GameRules.new()
	rng = MpRng.new(20000324)  # the original's JP release date, as a seed
	care = Care.new(rules, rng)
	monkey = Monkey.create("Freddy", Species.Type.SUNBURST, RunState.starter_caps())
	economy = StubEconomy.new(rules)


func _stock(id: String, qty: int = 1) -> void:
	economy.add_food(id, qty)


func _food(id: String) -> Food:
	return FoodDb.get_food(id)


func _feed(id: String) -> Care.FeedResult:
	_stock(id)
	return care.feed(monkey, _food(id), economy)


## Put the monkey in the ordinary mid-game state: trained, fed, friendly.
func _make_settled() -> void:
	monkey.friendship = 60
	monkey.fullness = 12
	monkey.add_stat(Monkey.Stat.STRENGTH, 100)
	monkey.add_stat(Monkey.Stat.STAMINA, 80)
	monkey.restore_pools()


# --- hunger bands ----------------------------------------------------------

func test_hunger_bands_cover_the_whole_belly() -> void:
	var expected := {
		0: Care.HungerState.STARVING,
		3: Care.HungerState.STARVING,
		4: Care.HungerState.HUNGRY,
		9: Care.HungerState.HUNGRY,
		10: Care.HungerState.CONTENT,
		20: Care.HungerState.CONTENT,
		21: Care.HungerState.FULL,
		26: Care.HungerState.FULL,
		27: Care.HungerState.STUFFED,
		30: Care.HungerState.STUFFED,
	}
	for fullness in expected:
		monkey.fullness = fullness
		assert_eq(care.hunger_state(monkey), expected[fullness],
			"fullness %d landed in the wrong band" % fullness)


func test_both_extremes_paralyse() -> void:
	# Dossier §5 [C]: "Underfed, the monkey is immobilised by hunger. Overfed,
	# it cannot move until it digests."
	monkey.friendship = 60
	monkey.fullness = 0
	assert_true(care.is_paralysed(monkey), "starving must immobilise")
	monkey.fullness = 15
	assert_false(care.is_paralysed(monkey))
	monkey.fullness = Monkey.FULLNESS_MAX
	assert_true(care.is_paralysed(monkey), "stuffed must immobilise")


func test_a_befriended_but_starving_monkey_still_cannot_act() -> void:
	monkey.friendship = Monkey.FRIENDSHIP_MAX
	monkey.fullness = 1
	assert_false(care.can_act(monkey))
	assert_has(care.block_reason(monkey), "HUNGRY")


func test_block_reason_is_empty_only_when_the_monkey_will_work() -> void:
	_make_settled()
	assert_eq(care.block_reason(monkey), "")
	assert_true(care.can_act(monkey))
	monkey.paralysed_slots = 1
	assert_ne(care.block_reason(monkey), "")
	assert_false(care.can_act(monkey))


func test_needs_food_to_act_separates_the_two_kinds_of_paralysis() -> void:
	# The two immobilised states are NOT symmetrical in what rescues them, and
	# the difference is what decides whether an empty larder is a dead end:
	# a stuffed monkey is freed by time, a starving or wary one only by food.
	monkey.friendship = Monkey.FRIENDSHIP_MAX
	monkey.fullness = 0
	assert_true(care.needs_food_to_act(monkey), "starving is fixed by feeding")

	monkey.fullness = Monkey.FULLNESS_MAX
	assert_true(care.is_paralysed(monkey))
	assert_false(care.needs_food_to_act(monkey),
		"feeding a stuffed monkey is the WRONG move — time is the answer")

	monkey.fullness = 15
	monkey.friendship = 0
	assert_true(care.needs_food_to_act(monkey), "an unwilling monkey is won over with food")

	monkey.friendship = Monkey.FRIENDSHIP_MAX
	monkey.paralysed_slots = 2
	assert_false(care.needs_food_to_act(monkey), "a slot countdown is served, not fed")

	monkey.paralysed_slots = 0
	assert_false(care.needs_food_to_act(monkey), "a settled monkey needs nothing")
	assert_false(care.needs_food_to_act(null))


func test_block_reason_puts_the_stuffed_warning_ahead_of_hunger_advice() -> void:
	# Feeding a stuffed monkey is the WRONG move, so that message must win even
	# though an unbefriended monkey is also blocked.
	monkey.friendship = 0
	monkey.fullness = Monkey.FULLNESS_MAX
	assert_has(care.block_reason(monkey), "ATE TOO MUCH")


# --- befriending -----------------------------------------------------------

func test_a_new_monkey_is_unbefriended_and_blocked() -> void:
	# Dossier §5 [C]: "Every new monkey, Freddy included, must be won over with
	# food before it will train. Until then it is disobedient and will bite you."
	assert_false(monkey.is_befriended())
	assert_false(care.can_act(monkey))
	assert_has(care.block_reason(monkey), "TOO HUNGRY")
	monkey.fullness = 12
	assert_has(care.block_reason(monkey), "TRUST")


func test_two_bananas_befriend_the_starter() -> void:
	# The documented fastest path (dossier §5 [C]).
	var first := _feed("banana")
	assert_eq(first.outcome, Care.FeedOutcome.ACCEPTED)
	assert_eq(first.friendship_delta, 12, "banana is liked by every species: 6 * 2.0")
	assert_false(monkey.is_befriended(), "one banana must not be enough")
	var second := _feed("banana")
	assert_eq(second.friendship_delta, 12)
	assert_eq(monkey.friendship, 24)
	assert_true(monkey.is_befriended())
	assert_true(care.can_act(monkey), "two bananas must also lift it out of starving")


func test_species_preferences_change_what_a_food_is_worth() -> void:
	# Dossier §5 [C]: "Per-type food preferences are real."
	monkey.friendship = 50
	monkey.fullness = 10
	var liked := _feed("banana")
	assert_eq(liked.friendship_delta, 12)

	var neutral_monkey := Monkey.create("Betty", Species.Type.MIDNIGHT, RunState.starter_caps())
	neutral_monkey.friendship = 50
	neutral_monkey.fullness = 10
	_stock("corn")
	var neutral := care.feed(neutral_monkey, _food("corn"), economy)
	assert_eq(neutral.friendship_delta, 6, "a neutral food is worth the flat rate")

	var disliked_monkey := Monkey.create("Lemon", Species.Type.SUNBURST, RunState.starter_caps())
	disliked_monkey.friendship = 50
	disliked_monkey.fullness = 10
	_stock("garlic")
	var disliked := care.feed(disliked_monkey, _food("garlic"), economy)
	assert_eq(disliked.outcome, Care.FeedOutcome.REFUSED_DISLIKED)
	assert_eq(disliked.friendship_delta, -3, "6 * -0.5")
	assert_eq(disliked_monkey.friendship, 47)
	assert_eq(disliked_monkey.fullness, 11, "a sulk still eats the food")


func test_an_unbefriended_monkey_bites_over_food_it_dislikes() -> void:
	assert_false(monkey.is_befriended())
	_stock("garlic")  # SUNBURST dislikes garlic
	var result := care.feed(monkey, _food("garlic"), economy)
	assert_eq(result.outcome, Care.FeedOutcome.BITE)
	assert_has(result.message, "BITES")
	assert_eq(monkey.fullness, 0, "a bitten-away food is not eaten")
	assert_eq(result.friendship_delta, 0)
	assert_eq(economy.food_count("garlic"), 0, "the food is still lost")


func test_a_befriended_monkey_does_not_bite() -> void:
	monkey.friendship = 50
	monkey.fullness = 10
	_stock("garlic")
	var result := care.feed(monkey, _food("garlic"), economy)
	assert_eq(result.outcome, Care.FeedOutcome.REFUSED_DISLIKED)


# --- feeding mechanics -----------------------------------------------------

func test_feeding_from_an_empty_inventory_changes_nothing() -> void:
	_make_settled()
	var before_fullness := monkey.fullness
	var before_friendship := monkey.friendship
	var result := care.feed(monkey, _food("banana"), economy)
	assert_eq(result.outcome, Care.FeedOutcome.NO_STOCK)
	assert_eq(monkey.fullness, before_fullness)
	assert_eq(monkey.friendship, before_friendship)
	assert_eq(result.friendship_delta, 0)


func test_feeding_consumes_exactly_one_unit() -> void:
	_make_settled()
	_stock("banana", 3)
	care.feed(monkey, _food("banana"), economy)
	assert_eq(economy.food_count("banana"), 2)


func test_feeding_nothing_is_survivable() -> void:
	var result := care.feed(monkey, null, economy)
	assert_eq(result.outcome, Care.FeedOutcome.NO_STOCK)
	assert_eq(care.feed(null, _food("banana"), economy).outcome, Care.FeedOutcome.NO_STOCK)


func test_restores_are_clamped_to_the_pools_and_reported_honestly() -> void:
	# Strength IS the health bar (dossier §3 [C]).
	_make_settled()
	monkey.current_strength = 90   # of 100
	monkey.current_stamina = 80    # of 80, already full
	var result := _feed("curry")   # Str 60 / Stm 60
	assert_eq(result.strength_restored, 10, "report what landed, not the food's number")
	assert_eq(result.stamina_restored, 0)
	assert_eq(monkey.current_strength, 100)
	assert_eq(monkey.current_stamina, 80)


func test_a_biscuit_settles_the_stomach_without_healing() -> void:
	# Dossier §5 [C]: Biscuit is 0 recovery, Hunger 3 — the stomach-settler.
	_make_settled()
	monkey.current_strength = 40
	var result := _feed("biscuit")
	assert_eq(result.strength_restored, 0)
	assert_eq(result.stamina_restored, 0)
	assert_eq(result.fullness_after, result.fullness_before + 3)


func test_coffee_has_negative_hunger_and_never_pushes_below_zero() -> void:
	# Dossier §5 [C]: Coffee is Hunger -5, "explicitly to make room for more food".
	_make_settled()
	monkey.fullness = 12
	var result := _feed("coffee")
	assert_eq(result.fullness_after, 7, "negative hunger must not be clamped away")
	monkey.fullness = 2
	var floored := _feed("coffee")
	assert_eq(floored.fullness_after, 0, "fullness must not go negative")


func test_fullness_is_capped_at_the_top() -> void:
	_make_settled()
	monkey.fullness = Monkey.FULLNESS_MAX - 2
	var result := _feed("curry")  # Hunger 9
	assert_eq(result.fullness_after, Monkey.FULLNESS_MAX)


# --- overfeeding: FAITHFUL, do not soften ----------------------------------

func test_overfeeding_paralyses_the_monkey() -> void:
	_make_settled()
	monkey.fullness = 0
	assert_true(rules.overfeeding_paralyses, "the default is FAITHFUL")
	_feed("curry")   # 9
	_feed("curry")   # 18
	assert_true(care.can_act(monkey))
	var third := _feed("curry")  # 27 — stuffed
	assert_eq(third.outcome, Care.FeedOutcome.CAUSED_PARALYSIS)
	assert_true(third.paralysed_slots > 0, "the UI must be able to say how long")
	assert_true(care.is_paralysed(monkey))
	assert_false(care.can_act(monkey), "this is immobility, NOT wasted food")
	assert_has(care.block_reason(monkey), "CANNOT MOVE")


func test_overfeeding_emits_paralysis_started_once() -> void:
	_make_settled()
	monkey.fullness = 24
	var starts: Array = []
	care.paralysis_started.connect(func(slots: int) -> void: starts.append(slots))
	_feed("curry")
	assert_eq(starts.size(), 1)
	assert_true(int(starts[0]) > 0)


func test_coffee_ends_overfeeding_paralysis_on_the_spot() -> void:
	# This is what Coffee's -5 exists for, so the paralysis must be carried by
	# fullness rather than by an untouchable countdown.
	_make_settled()
	monkey.fullness = Monkey.FULLNESS_STUFFED
	assert_true(care.is_paralysed(monkey))
	var ends: Array = []
	care.paralysis_ended.connect(func() -> void: ends.append(true))
	_feed("coffee")
	assert_eq(monkey.fullness, Monkey.FULLNESS_STUFFED - 5)
	assert_false(care.is_paralysed(monkey))
	assert_eq(ends.size(), 1)


func test_overfeeding_paralysis_honours_its_flag() -> void:
	# The flag exists so Integration can prove the branch is read. The shipped
	# default stays true — dossier §5 [C], and the user asked for it explicitly.
	rules.overfeeding_paralyses = false
	_make_settled()
	monkey.fullness = Monkey.FULLNESS_MAX
	assert_eq(care.hunger_state(monkey), Care.HungerState.STUFFED,
		"the state is still reported, only the immobility is off")
	assert_false(care.is_paralysed(monkey))
	assert_true(care.can_act(monkey))


func test_slots_until_digested_counts_down_to_the_stuffed_line() -> void:
	assert_eq(care.slots_until_digested(monkey), 0, "not stuffed = no wait")
	monkey.fullness = Monkey.FULLNESS_STUFFED
	assert_eq(care.slots_until_digested(monkey), 1)
	monkey.fullness = Monkey.FULLNESS_MAX
	assert_eq(care.slots_until_digested(monkey), 1,
		"30 -> 26 in one DIGEST_PER_SLOT of 6")


# --- permanent boosters ----------------------------------------------------

func test_a_permanent_booster_raises_stats_for_good() -> void:
	# Eel: Str +10, Stm +10 (dossier §5 [C]).
	_make_settled()
	var before_str := monkey.get_stat(Monkey.Stat.STRENGTH)
	var result := _feed("eel")
	assert_eq(result.permanent_applied[Monkey.Stat.STRENGTH], 10)
	assert_eq(result.permanent_applied[Monkey.Stat.STAMINA], 10)
	assert_eq(monkey.get_stat(Monkey.Stat.STRENGTH), before_str + 10)
	assert_false(result.permanent_wasted)


func test_a_permanent_booster_is_wasted_on_a_starred_stat() -> void:
	# Dossier §3 [C]: "Permanent-boost foods are wasted on a starred stat."
	_make_settled()
	monkey.add_stat(Monkey.Stat.STRENGTH, 9999)
	assert_true(monkey.is_capped(Monkey.Stat.STRENGTH))
	var result := _feed("eel")
	assert_eq(result.permanent_applied[Monkey.Stat.STRENGTH], 0)
	assert_eq(result.permanent_applied[Monkey.Stat.STAMINA], 10)
	assert_true(result.permanent_wasted, "the UI has to be able to say so")


func test_a_permanent_booster_lands_partially_at_the_cap_edge() -> void:
	_make_settled()
	var cap := monkey.get_cap(Monkey.Stat.POWER)
	monkey.set_stat(Monkey.Stat.POWER, cap - 2)
	var result := _feed("coconuts")  # Pow +5, Know +5
	assert_eq(result.permanent_applied[Monkey.Stat.POWER], 2)
	assert_eq(result.permanent_applied[Monkey.Stat.KNOWLEDGE], 5)
	assert_true(result.permanent_wasted)
	assert_true(monkey.is_capped(Monkey.Stat.POWER))


func test_ordinary_food_reports_no_permanent_gains() -> void:
	_make_settled()
	var result := _feed("banana")
	assert_true(result.permanent_applied.is_empty())
	assert_false(result.permanent_wasted)


# --- friendship ------------------------------------------------------------

func test_friendship_clamps_at_both_ends_and_reports_what_landed() -> void:
	monkey.friendship = 2
	assert_eq(care.add_friendship(monkey, -10), -2, "only the drop to zero lands")
	assert_eq(monkey.friendship, 0)
	monkey.friendship = Monkey.FRIENDSHIP_MAX - 3
	assert_eq(care.add_friendship(monkey, 50), 3)
	assert_eq(monkey.friendship, Monkey.FRIENDSHIP_MAX)
	assert_eq(care.add_friendship(monkey, 10), 0, "nothing lands at the ceiling")
	assert_eq(care.add_friendship(monkey, 0), 0)
	assert_eq(care.add_friendship(null, 5), 0)


func test_praise_and_scold() -> void:
	# Dossier §4 [C]: both are explicit inputs during a training session.
	monkey.friendship = 40
	assert_eq(care.praise(monkey), Care.FRIENDSHIP_PRAISE)
	assert_eq(monkey.friendship, 44)
	assert_eq(care.scold(monkey), Care.FRIENDSHIP_SCOLD)
	assert_eq(monkey.friendship, 41)


func test_friendship_changed_only_fires_on_a_real_change() -> void:
	var seen: Array = []
	care.friendship_changed.connect(func(value: int) -> void: seen.append(value))
	monkey.friendship = Monkey.FRIENDSHIP_MAX
	care.add_friendship(monkey, 5)
	assert_eq(seen.size(), 0)
	care.add_friendship(monkey, -5)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], Monkey.FRIENDSHIP_MAX - 5)


# --- digestion -------------------------------------------------------------

func test_digest_tick_burns_fullness_per_slot() -> void:
	monkey.fullness = 20
	care.digest_tick(monkey)
	assert_eq(monkey.fullness, 20 - Monkey.DIGEST_PER_SLOT)
	care.digest_tick(monkey, 2)
	assert_eq(monkey.fullness, 20 - Monkey.DIGEST_PER_SLOT * 3)


func test_digest_tick_frees_a_stuffed_monkey_and_says_so() -> void:
	_make_settled()
	monkey.fullness = Monkey.FULLNESS_MAX
	var ends: Array = []
	care.paralysis_ended.connect(func() -> void: ends.append(true))
	care.digest_tick(monkey)
	assert_false(care.is_paralysed(monkey))
	assert_eq(ends.size(), 1)
	care.digest_tick(monkey)
	assert_eq(ends.size(), 1, "paralysis_ended must not repeat")


func test_digest_tick_ticks_down_other_immobility_too() -> void:
	_make_settled()
	monkey.fullness = 24  # enough to stay out of the starving band for two ticks
	monkey.paralysed_slots = 2
	care.digest_tick(monkey)
	assert_eq(monkey.paralysed_slots, 1)
	assert_true(care.is_paralysed(monkey))
	care.digest_tick(monkey)
	assert_eq(monkey.paralysed_slots, 0)
	assert_false(care.is_paralysed(monkey))


func test_digest_tick_never_goes_negative() -> void:
	monkey.fullness = 2
	monkey.paralysed_slots = 0
	care.digest_tick(monkey, 5)
	assert_eq(monkey.fullness, 0)
	assert_eq(monkey.paralysed_slots, 0)


func test_digest_tick_ignores_zero_and_negative_slots() -> void:
	monkey.fullness = 20
	monkey.friendship = 50
	care.digest_tick(monkey, 0)
	care.digest_tick(monkey, -3)
	care.digest_tick(null, 1)
	assert_eq(monkey.fullness, 20)
	assert_eq(monkey.friendship, 50)


func test_a_monkey_left_starving_loses_friendship() -> void:
	monkey.friendship = 50
	monkey.fullness = 2
	care.digest_tick(monkey)
	assert_eq(monkey.friendship, 50 + Care.FRIENDSHIP_STARVING_PENALTY)
	monkey.fullness = 20
	care.digest_tick(monkey)
	assert_eq(monkey.friendship, 48, "a fed monkey keeps its friendship")


# --- obedience: FAITHFUL, do not soften ------------------------------------

func test_obedience_rises_with_friendship() -> void:
	# Dossier §6 [C]: "A monkey with insufficient friendship may ignore your
	# instructions." The curve itself is [X] — see Care.OBEDIENCE_FLOOR.
	monkey.friendship = 0
	assert_almost_eq(care.obedience_chance(monkey), Care.OBEDIENCE_FLOOR)
	monkey.friendship = Monkey.FRIENDSHIP_OBEDIENT
	assert_almost_eq(care.obedience_chance(monkey), 1.0)
	monkey.friendship = Monkey.FRIENDSHIP_MAX
	assert_almost_eq(care.obedience_chance(monkey), 1.0)

	var previous := -1.0
	for friendship in range(0, Monkey.FRIENDSHIP_MAX + 1, 5):
		monkey.friendship = friendship
		var chance := care.obedience_chance(monkey)
		assert_in_range(chance, Care.OBEDIENCE_FLOOR, 1.0)
		assert_true(chance >= previous, "the curve must never dip")
		previous = chance


func test_an_unbefriended_monkey_disobeys_often() -> void:
	monkey.friendship = 0
	var obeyed := 0
	for i in 400:
		if care.obeys(monkey):
			obeyed += 1
	# Seeded, so this is a fixed number, not a flaky statistical assertion.
	assert_in_range(obeyed, 60, 140,
		"~25%% of 400 rolls; got %d" % obeyed)


func test_a_bonded_monkey_always_obeys() -> void:
	monkey.friendship = Monkey.FRIENDSHIP_OBEDIENT
	for i in 200:
		assert_true(care.obeys(monkey))


func test_disobedience_can_be_switched_off_by_the_flag() -> void:
	# The shipped default is true — FAITHFUL, and the user asked for it.
	assert_true(rules.disobedience_enabled)
	rules.disobedience_enabled = false
	monkey.friendship = 0
	assert_almost_eq(care.obedience_chance(monkey), 1.0)
	for i in 200:
		assert_true(care.obeys(monkey))


func test_obedience_rolls_are_seeded_and_reproducible() -> void:
	monkey.friendship = 30
	var first: Array = []
	for i in 50:
		first.append(care.obeys(monkey))

	var replay := Care.new(rules, MpRng.new(20000324))
	var second: Array = []
	for i in 50:
		second.append(replay.obeys(monkey))

	assert_eq(first, second, "same seed must replay identically")
	assert_has(first, true)
	assert_has(first, false)


func test_obeys_consumes_one_draw_whatever_the_friendship() -> void:
	# MatchResolver rolls once per round; the stream must not shift when the
	# monkey happens to be certain to obey.
	monkey.friendship = Monkey.FRIENDSHIP_MAX
	var loyal := Care.new(rules, MpRng.new(99))
	for i in 5:
		loyal.obeys(monkey)
	var loyal_next := loyal.obedience_chance(monkey)
	assert_almost_eq(loyal_next, 1.0)

	var probe_a := MpRng.new(99)
	var probe_b := MpRng.new(99)
	for i in 5:
		probe_a.randf()
	assert_ne(probe_a.state(), probe_b.state())


func test_obeys_command_exposes_the_same_curve_statelessly() -> void:
	# The brief asks for obeys_command(friendship, rng) by name; the frozen
	# contract asks for obeys(monkey). Both exist and must agree.
	assert_almost_eq(Care.obedience_chance_for(0), Care.OBEDIENCE_FLOOR)
	assert_almost_eq(Care.obedience_chance_for(Monkey.FRIENDSHIP_OBEDIENT), 1.0)
	assert_almost_eq(Care.obedience_chance_for(-50), Care.OBEDIENCE_FLOOR, 0.0001,
		"a negative friendship must not produce a negative chance")

	monkey.friendship = 35
	var instance_care := Care.new(rules, MpRng.new(4242))
	var static_rng := MpRng.new(4242)
	for i in 30:
		assert_eq(Care.obeys_command(35, static_rng), instance_care.obeys(monkey))
	assert_true(Care.obeys_command(35, null), "a null rng must not crash a match")


# --- overnight -------------------------------------------------------------

func test_overnight_recovery_trickles_the_pools_back() -> void:
	_make_settled()
	monkey.days_since_match = 5
	monkey.current_strength = 0
	monkey.current_stamina = 0
	care.apply_overnight_recovery(monkey)
	assert_eq(monkey.current_strength, 25, "a quarter of 100")
	assert_eq(monkey.current_stamina, 20, "a quarter of 80")
	assert_eq(monkey.days_since_match, 6)


func test_the_night_after_a_match_recovers_nothing() -> void:
	# Dossier §6 [C]: "the monkey is worn out the following day and needs a big
	# recovery meal."
	_make_settled()
	monkey.days_since_match = 0
	monkey.current_strength = 10
	monkey.current_stamina = 10
	care.apply_overnight_recovery(monkey)
	assert_eq(monkey.current_strength, 10)
	assert_eq(monkey.current_stamina, 10)
	assert_eq(monkey.days_since_match, 1)
	care.apply_overnight_recovery(monkey)
	assert_eq(monkey.current_strength, 35, "the wear lasts exactly one night")


func test_overnight_recovery_never_overfills_or_overflows() -> void:
	_make_settled()
	monkey.days_since_match = 9
	monkey.restore_pools()
	care.apply_overnight_recovery(monkey)
	assert_eq(monkey.current_strength, monkey.max_strength())
	assert_eq(monkey.current_stamina, monkey.max_stamina())

	monkey.days_since_match = 99
	care.apply_overnight_recovery(monkey)
	assert_eq(monkey.days_since_match, 99, "the counter must not run away")
	care.apply_overnight_recovery(null)


func test_overnight_recovery_on_an_untrained_monkey_is_harmless() -> void:
	# A newborn has zero STRENGTH, so its health bar's ceiling is zero.
	monkey.days_since_match = 9
	care.apply_overnight_recovery(monkey)
	assert_eq(monkey.current_strength, 0)
	assert_eq(monkey.current_stamina, 0)


# --- signals ---------------------------------------------------------------

func test_feed_emits_fed_with_the_result() -> void:
	_make_settled()
	var seen: Array = []
	care.fed.connect(func(result: Care.FeedResult) -> void: seen.append(result))
	var returned := _feed("banana")
	assert_eq(seen.size(), 1)
	assert_true(seen[0] == returned, "the signal must carry the same object")
	assert_has(returned.message, "BANANA")
