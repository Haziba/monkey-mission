extends TestCase

## Ladder — the JSB rank climb. Dossier §7 phase 2.
##
## The four movement rules under test, all [C]:
##   beat higher  -> up one rung
##   beat lower   -> paid, but NO promotion (the guides do it purely for cash)
##   lose to lower -> down one rung
##   lose to higher -> nothing
##
## SIGN CONVENTION: rank 1 is the top, so the delta returned by apply_result and
## rank_delta_for is arithmetic on the rank NUMBER — negative means promoted.

var rules: GameRules
var rng: MpRng
var ladder: Ladder


func before_each() -> void:
	rules = GameRules.load_default()
	rng = MpRng.new(20000324)   # the original's JP release date, as a seed
	ladder = Ladder.new(rules, rng)


## A generation-1 starter trained to its ceiling. Dossier §3 [U]: caps average
## 134, and §8 [C] says a starter "will unfortunately never be rank 1".
func _maxed_starter() -> Monkey:
	var m := Monkey.create("Freddy", Species.Type.SUNBURST, RunState.starter_caps())
	for stat in Monkey.STATS:
		m.set_stat(stat, m.get_cap(stat))
	m.restore_pools()
	return m


func _untrained_starter() -> Monkey:
	return Monkey.create("Freddy", Species.Type.SUNBURST, RunState.starter_caps())


func _stat_total(m: Monkey) -> int:
	var total := 0
	for stat in Monkey.STATS:
		total += m.get_stat(stat)
	return total


# --- starting position -----------------------------------------------------

func test_a_run_starts_at_the_bottom_of_the_short_ladder() -> void:
	assert_eq(ladder.rank, Ladder.BOTTOM_RANK)
	assert_eq(Ladder.BOTTOM_RANK, 5, "the slice's ladder is rank 5 up to rank 1")
	assert_eq(Ladder.TOP_RANK, 1)
	assert_false(ladder.is_champion())


func test_rank_one_is_the_championship() -> void:
	ladder.rank = 1
	assert_true(ladder.is_champion())


# --- cadence ---------------------------------------------------------------

func test_the_cycle_is_four_days_long() -> void:
	# DIVERGENCE under test: 3 vs 4 vs 5 is a live contradiction (§14); the
	# walkthrough's own day log puts fights on 6, 10, 14, 18.
	assert_eq(Ladder.MATCH_CYCLE_DAYS, 4)
	for day in [5, 9, 13, 17]:
		assert_true(Ladder.is_offer_day(day), "Bill should call on day %d" % day)
	for day in [1, 4, 6, 7, 8, 10, 11, 12]:
		assert_false(Ladder.is_offer_day(day), "day %d is a free day" % day)


func test_the_fight_is_the_day_after_the_offer() -> void:
	for day in [6, 10, 14, 18]:
		assert_true(Ladder.is_match_day(day), "day %d is a fight day" % day)
	for day in [5, 7, 8, 9]:
		assert_false(Ladder.is_match_day(day))


func test_three_free_days_sit_between_two_fights() -> void:
	var free_days := 0
	for day in range(7, 10):     # the gap between fight day 6 and fight day 10
		if not Ladder.is_match_day(day):
			free_days += 1
	assert_eq(free_days, 3, "offer day, fight day, three free days (§2 best reading)")


func test_next_offer_day_walks_the_cycle() -> void:
	assert_eq(Ladder.next_offer_day(1), 5)
	assert_eq(Ladder.next_offer_day(4), 5)
	assert_eq(Ladder.next_offer_day(5), 9, "strictly after the day given")
	assert_eq(Ladder.next_offer_day(6), 9)
	assert_eq(Ladder.next_offer_day(9), 13)


# --- Bill's offer ----------------------------------------------------------

func test_bill_offers_exactly_three_candidates() -> void:
	var offers := ladder.offer_opponents(_maxed_starter(), 5)
	assert_eq(offers.size(), Ladder.OFFER_COUNT)
	assert_eq(Ladder.OFFER_COUNT, 3)
	for offer in offers:
		assert_not_null(offer.monkey)
		assert_ne(offer.trainer_name, "")


func test_at_least_one_candidate_outranks_the_player() -> void:
	# Dossier §7 [C]. True from every rung except the very top.
	for start_rank in [5, 4, 3, 2]:
		ladder.rank = start_rank
		var offers := ladder.offer_opponents(_maxed_starter(), 5)
		var above := 0
		for offer in offers:
			if offer.rank < start_rank:
				above += 1
				assert_true(offer.is_above_player,
					"is_above_player must agree with the rank number")
			else:
				assert_false(offer.is_above_player)
		assert_true(above >= 1, "no promotion candidate offered at rank %d" % start_rank)


func test_the_champion_still_gets_a_card_to_fight() -> void:
	# Nobody outranks rank 1; the offer must degrade rather than crash.
	ladder.rank = Ladder.TOP_RANK
	var offers := ladder.offer_opponents(_maxed_starter(), 21)
	assert_eq(offers.size(), Ladder.OFFER_COUNT)
	for offer in offers:
		assert_false(offer.is_above_player)
		assert_in_range(offer.rank, Ladder.TOP_RANK, Ladder.BOTTOM_RANK)


func test_the_three_candidates_are_distinct() -> void:
	var offers := ladder.offer_opponents(_maxed_starter(), 5)
	var ranks: Array[int] = []
	var names: Array[String] = []
	var trainers: Array[String] = []
	for offer in offers:
		assert_not_has(ranks, offer.rank, "two candidates on the same rung")
		assert_not_has(names, offer.monkey.monkey_name, "two candidates with one name")
		assert_not_has(trainers, offer.trainer_name, "one trainer in two corners")
		ranks.append(offer.rank)
		names.append(offer.monkey.monkey_name)
		trainers.append(offer.trainer_name)


func test_every_card_across_a_whole_run_is_internally_distinct() -> void:
	# The pools are small, so walk a full slice's worth of offer days from every
	# rung and make sure the "next unused" fallback never doubles up.
	var player := _maxed_starter()
	for start_rank in range(Ladder.TOP_RANK, Ladder.BOTTOM_RANK + 1):
		ladder.rank = start_rank
		for day in [5, 9, 13, 17, 21, 25, 29, 33]:
			var names: Array[String] = []
			var trainers: Array[String] = []
			for offer in ladder.offer_opponents(player, day):
				assert_not_has(names, offer.monkey.monkey_name,
					"duplicate name on rank %d day %d" % [start_rank, day])
				assert_not_has(trainers, offer.trainer_name,
					"duplicate trainer on rank %d day %d" % [start_rank, day])
				names.append(offer.monkey.monkey_name)
				trainers.append(offer.trainer_name)


func test_the_card_is_ordered_strongest_first() -> void:
	var offers := ladder.offer_opponents(_maxed_starter(), 5)
	for i in range(1, offers.size()):
		assert_true(offers[i - 1].rank <= offers[i].rank,
			"rank 1 is the top, so the card ascends by rank number")


func test_the_same_seed_and_day_offers_the_same_three() -> void:
	var player := _maxed_starter()
	var first := Ladder.new(rules, MpRng.new(7)).offer_opponents(player, 9)
	var second := Ladder.new(rules, MpRng.new(7)).offer_opponents(player, 9)
	assert_eq(first.size(), second.size())
	for i in first.size():
		assert_eq(first[i].rank, second[i].rank)
		assert_eq(first[i].monkey.monkey_name, second[i].monkey.monkey_name)
		assert_eq(first[i].trainer_name, second[i].trainer_name)
		assert_eq(_stat_total(first[i].monkey), _stat_total(second[i].monkey),
			"re-opening Bill's card must not re-roll the opponents")


func test_a_different_day_offers_a_different_card() -> void:
	var player := _maxed_starter()
	var monday := Ladder.new(rules, MpRng.new(7)).offer_opponents(player, 9)
	var friday := Ladder.new(rules, MpRng.new(7)).offer_opponents(player, 13)
	var identical := true
	for i in monday.size():
		if _stat_total(monday[i].monkey) != _stat_total(friday[i].monkey):
			identical = false
	assert_false(identical, "the card must not be frozen for the whole run")


func test_a_different_seed_offers_a_different_card() -> void:
	var player := _maxed_starter()
	var one := Ladder.new(rules, MpRng.new(7)).offer_opponents(player, 9)
	var two := Ladder.new(rules, MpRng.new(999_331)).offer_opponents(player, 9)
	var identical := true
	for i in one.size():
		if _stat_total(one[i].monkey) != _stat_total(two[i].monkey):
			identical = false
	assert_false(identical)


func test_offering_does_not_disturb_the_shared_rng_stream() -> void:
	var before := rng.state()
	ladder.offer_opponents(_maxed_starter(), 5)
	ladder.offer_opponents(_maxed_starter(), 5)
	assert_eq(rng.state(), before,
		"the offer uses a (seed, day) sub-stream so a re-open costs no randomness")


func test_the_offer_signal_carries_the_card() -> void:
	# NOTE: GDScript lambdas capture locals BY VALUE, so a signal probe has to
	# mutate a container rather than rebind a variable.
	var seen: Array = []
	ladder.opponents_offered.connect(func(offers: Array) -> void: seen.append_array(offers))
	var returned := ladder.offer_opponents(_maxed_starter(), 5)
	assert_eq(seen.size(), returned.size())
	assert_eq(seen.size(), Ladder.OFFER_COUNT)
	for i in seen.size():
		assert_eq((seen[i] as Ladder.Opponent).rank, returned[i].rank)


func test_an_offer_survives_a_null_player() -> void:
	# Defensive: the UI can ask for a preview card before a monkey exists.
	var offers := ladder.offer_opponents(null, 5)
	assert_eq(offers.size(), Ladder.OFFER_COUNT)
	for offer in offers:
		assert_true(_stat_total(offer.monkey) > 0)


# --- opponent generation ---------------------------------------------------

func test_an_opponent_arrives_fully_trained() -> void:
	var op := ladder.generate_opponent(3, _maxed_starter())
	for stat in Monkey.STATS:
		assert_eq(op.monkey.get_stat(stat), op.monkey.get_cap(stat),
			"a ladder opponent is already at its ceiling")
	assert_eq(op.monkey.current_strength, op.monkey.max_strength())
	assert_eq(op.monkey.current_stamina, op.monkey.max_stamina())
	assert_true(op.monkey.is_befriended(), "an opponent never disobeys its own trainer")


func test_opponent_stats_climb_with_the_rank() -> void:
	var player := _maxed_starter()
	var totals: Array[int] = []
	for r in range(Ladder.BOTTOM_RANK, Ladder.TOP_RANK - 1, -1):
		totals.append(_stat_total(ladder.generate_opponent(r, player).monkey))
	for i in range(1, totals.size()):
		assert_true(totals[i] > totals[i - 1],
			"rank %d must be stronger than rank %d (%d vs %d)"
				% [Ladder.BOTTOM_RANK - i, Ladder.BOTTOM_RANK - i + 1, totals[i], totals[i - 1]])


func test_the_generational_wall_stands_where_the_dossier_says() -> void:
	# Dossier §8 [C]: "Your starter will unfortunately never be rank 1." A maxed
	# generation-1 monkey should out-stat the bottom rung and be nowhere near
	# the top one — that gap is exactly what breeding exists to close.
	var player := _maxed_starter()
	var mine := _stat_total(player)
	var bottom := _stat_total(ladder.generate_opponent(Ladder.BOTTOM_RANK, player).monkey)
	var top := _stat_total(ladder.generate_opponent(Ladder.TOP_RANK, player).monkey)
	assert_true(bottom < mine,
		"a maxed starter must be able to win at the bottom (%d vs %d)" % [mine, bottom])
	assert_true(top > mine * 1.5,
		"rank 1 must be out of a starter's reach (%d vs %d)" % [top, mine])


func test_an_opponent_is_never_degenerate() -> void:
	var player := _untrained_starter()
	for r in range(Ladder.TOP_RANK, Ladder.BOTTOM_RANK + 1):
		var op := ladder.generate_opponent(r, player)
		assert_eq(op.rank, r)
		for stat in Monkey.STATS:
			assert_true(op.monkey.get_stat(stat) > 0,
				"a zero stat would make the fight maths meaningless")
		assert_true(op.monkey.max_strength() > 0, "Strength is the health bar (§3 [C])")


func test_an_out_of_range_rank_is_clamped_onto_the_ladder() -> void:
	assert_eq(ladder.generate_opponent(-3, _maxed_starter()).rank, Ladder.TOP_RANK)
	assert_eq(ladder.generate_opponent(99, _maxed_starter()).rank, Ladder.BOTTOM_RANK)


func test_higher_ranks_field_later_generations() -> void:
	var player := _maxed_starter()
	var bottom := ladder.generate_opponent(Ladder.BOTTOM_RANK, player).monkey.generation
	var top := ladder.generate_opponent(Ladder.TOP_RANK, player).monkey.generation
	assert_eq(bottom, 1)
	assert_true(top > bottom, "the sawtooth should be legible on the stat card")


func test_a_stronger_opponent_pays_a_bigger_purse() -> void:
	# Dossier §7 [C]: stronger opponent = bigger purse. The figures live in
	# Economy.purse_for, owned by another agent; skip while that is still a stub.
	var player := _maxed_starter()
	var bottom := ladder.generate_opponent(Ladder.BOTTOM_RANK, player)
	var top := ladder.generate_opponent(Ladder.TOP_RANK, player)
	if bottom.purse == 0 and top.purse == 0:
		return
	assert_true(top.purse > bottom.purse,
		"rank 1 must pay more than rank 5 (%d vs %d)" % [top.purse, bottom.purse])


# --- rank movement, the pure rule ------------------------------------------

func test_beating_a_higher_rank_promotes() -> void:
	assert_eq(Ladder.rank_delta_for(true, 5, 4), -1, "up one rung: 5 -> 4")
	assert_eq(Ladder.rank_delta_for(true, 5, 1), -1, "still only one rung, however big the upset")
	assert_eq(Ladder.rank_delta_for(true, 2, 1), -1)


func test_beating_a_lower_rank_pays_but_does_not_promote() -> void:
	# The single most-quoted ladder rule (§7 [C]) — the guides farm it for cash.
	assert_eq(Ladder.rank_delta_for(true, 4, 5), 0)
	assert_eq(Ladder.rank_delta_for(true, 1, 5), 0)


func test_beating_an_equal_rank_moves_nothing() -> void:
	assert_eq(Ladder.rank_delta_for(true, 3, 3), 0)


func test_losing_to_a_lower_rank_demotes() -> void:
	assert_eq(Ladder.rank_delta_for(false, 4, 5), 1, "down one rung: 4 -> 5")
	assert_eq(Ladder.rank_delta_for(false, 1, 3), 1)


func test_losing_to_a_higher_rank_costs_nothing() -> void:
	assert_eq(Ladder.rank_delta_for(false, 5, 4), 0)
	assert_eq(Ladder.rank_delta_for(false, 5, 1), 0)


func test_losing_to_an_equal_rank_costs_nothing() -> void:
	assert_eq(Ladder.rank_delta_for(false, 3, 3), 0)


func test_the_rule_never_walks_off_either_end_of_the_ladder() -> void:
	assert_eq(Ladder.rank_delta_for(false, Ladder.BOTTOM_RANK, Ladder.BOTTOM_RANK + 1), 0,
		"there is no rung below the bottom")
	assert_eq(Ladder.rank_delta_for(true, Ladder.TOP_RANK, Ladder.TOP_RANK - 1), 0,
		"there is no rung above the top")


func test_the_rule_is_pure() -> void:
	var before := ladder.rank
	Ladder.rank_delta_for(true, 5, 1)
	Ladder.rank_delta_for(false, 1, 5)
	assert_eq(ladder.rank, before, "the preview must not move the player")


# --- applying a result -----------------------------------------------------

func test_a_win_over_a_higher_rank_moves_the_player_up() -> void:
	var moves: Array = []
	ladder.rank_changed.connect(func(old_rank: int, new_rank: int) -> void:
		moves.append([old_rank, new_rank]))
	var delta := ladder.apply_result(MatchResolver.Outcome.WIN_KO, 4)
	assert_eq(delta, -1)
	assert_eq(ladder.rank, 4)
	assert_eq(moves, [[5, 4]])


func test_a_decision_win_counts_the_same_as_a_knockout() -> void:
	assert_eq(ladder.apply_result(MatchResolver.Outcome.WIN_DECISION, 4), -1)
	assert_eq(ladder.rank, 4)


func test_a_cash_fight_leaves_the_rank_alone_and_stays_quiet() -> void:
	ladder.rank = 3
	var moves: Array = []
	ladder.rank_changed.connect(func(o: int, n: int) -> void: moves.append([o, n]))
	assert_eq(ladder.apply_result(MatchResolver.Outcome.WIN_KO, 5), 0)
	assert_eq(ladder.rank, 3)
	assert_eq(moves.size(), 0, "rank_changed must not fire when nothing moved")


func test_a_loss_to_a_lower_rank_moves_the_player_down() -> void:
	ladder.rank = 3
	assert_eq(ladder.apply_result(MatchResolver.Outcome.LOSS_KO, 5), 1)
	assert_eq(ladder.rank, 4)
	assert_eq(ladder.apply_result(MatchResolver.Outcome.LOSS_DECISION, 5), 1)
	assert_eq(ladder.rank, 5)


func test_a_loss_to_a_higher_rank_is_no_disgrace() -> void:
	ladder.rank = 3
	assert_eq(ladder.apply_result(MatchResolver.Outcome.LOSS_KO, 1), 0)
	assert_eq(ladder.rank, 3)


func test_a_draw_settles_nothing_either_way() -> void:
	ladder.rank = 3
	assert_eq(ladder.apply_result(MatchResolver.Outcome.DRAW, 1), 0)
	assert_eq(ladder.rank, 3)
	assert_eq(ladder.apply_result(MatchResolver.Outcome.DRAW, 5), 0)
	assert_eq(ladder.rank, 3)


func test_the_bottom_of_the_ladder_is_a_floor() -> void:
	assert_eq(ladder.rank, Ladder.BOTTOM_RANK)
	# There is no rank 6 to be beaten by, but a mis-booked opponent must not
	# push the player off the end.
	assert_eq(ladder.apply_result(MatchResolver.Outcome.LOSS_KO, 9), 0)
	assert_eq(ladder.rank, Ladder.BOTTOM_RANK)


func test_the_top_of_the_ladder_is_a_ceiling() -> void:
	ladder.rank = Ladder.TOP_RANK
	assert_eq(ladder.apply_result(MatchResolver.Outcome.WIN_KO, 0), 0)
	assert_eq(ladder.rank, Ladder.TOP_RANK)


func test_climbing_the_whole_short_ladder_crowns_a_champion() -> void:
	var crowned: Array = []
	ladder.champion_reached.connect(func() -> void: crowned.append(true))
	for opponent_rank in [4, 3, 2, 1]:
		assert_eq(ladder.apply_result(MatchResolver.Outcome.WIN_KO, opponent_rank), -1)
	assert_eq(ladder.rank, Ladder.TOP_RANK)
	assert_true(ladder.is_champion())
	assert_eq(crowned.size(), 1, "the championship fires exactly once")


func test_the_championship_does_not_re_fire_on_a_cash_defence() -> void:
	var crowned: Array = []
	ladder.rank = Ladder.TOP_RANK
	ladder.champion_reached.connect(func() -> void: crowned.append(true))
	ladder.apply_result(MatchResolver.Outcome.WIN_KO, 3)
	assert_eq(crowned.size(), 0)


func test_a_slip_after_the_crown_can_be_re_climbed() -> void:
	ladder.rank = Ladder.TOP_RANK
	assert_eq(ladder.apply_result(MatchResolver.Outcome.LOSS_DECISION, 3), 1)
	assert_eq(ladder.rank, 2)
	assert_false(ladder.is_champion())
	assert_eq(ladder.apply_result(MatchResolver.Outcome.WIN_KO, 1), -1)
	assert_true(ladder.is_champion())


# --- serialisation ---------------------------------------------------------

func test_dict_round_trip_preserves_the_rank() -> void:
	ladder.apply_result(MatchResolver.Outcome.WIN_KO, 4)
	var restored := Ladder.new(rules, MpRng.new(1))
	restored.apply_dict(ladder.to_dict())
	assert_eq(restored.rank, ladder.rank)
	assert_eq(restored.rank, 4)


func test_apply_dict_survives_an_empty_dictionary() -> void:
	ladder.rank = 2
	ladder.apply_dict({})
	assert_eq(ladder.rank, Ladder.BOTTOM_RANK)


func test_apply_dict_clamps_a_rank_off_the_ladder() -> void:
	ladder.apply_dict({"rank": 0})
	assert_eq(ladder.rank, Ladder.TOP_RANK)
	ladder.apply_dict({"rank": 999})
	assert_eq(ladder.rank, Ladder.BOTTOM_RANK)


func test_serialised_rank_is_a_plain_int() -> void:
	assert_eq(typeof(ladder.to_dict()["rank"]), TYPE_INT)
