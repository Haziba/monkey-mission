extends TestCase

## END-TO-END. A whole playthrough driven through the `GameState` facade with no
## UI at all — the regression net for everything the nine parallel agents had to
## agree on without seeing each other's work.
##
## Every other test file pins one system in isolation. This one pins the SEAMS:
## that `RunState.new_run` produces a run the rest of the code can actually use,
## that a half-day is spent exactly once per activity and never by feeding, that
## a match settles up into both the Economy and the Ladder, that breeding swaps
## the active monkey and files the parent, and that all of it survives a save.
##
## `GameState` is an autoload in the running game, but autoloads are NOT
## instantiated under `godot --headless --script` (verified), so each test builds
## its own instance of the same script. It is a plain Node that never touches the
## scene tree, which is exactly why that works — and is itself worth pinning.

const GameStateScript := preload("res://core/game_state.gd")

## Fixed so a failure is reproducible. The JP release date, as elsewhere.
const SEED := 20000324

var gs: Node = null


func before_each() -> void:
	# GameState autosaves on day rollover, on match settle-up and on birth, so
	# every test starts and ends with no save file of its own.
	SaveGame.delete_save()
	gs = GameStateScript.new()


func after_each() -> void:
	if gs != null:
		gs.free()          # Node, not RefCounted — nothing else will collect it.
		gs = null
	SaveGame.delete_save()


# --- helpers -----------------------------------------------------------------

func _start() -> void:
	gs.new_run(int(RunState.Protagonist.KENTA), SEED)


## Dossier §5 [C]: the documented fastest befriending is two bananas.
func _befriend() -> void:
	gs.feed("banana")
	gs.feed("banana")


## Feed until the monkey has room to work, without ever tipping it into the
## stuffed band — the guides' rule is to feed only when it cannot move, and
## overfeeding paralyses (FAITHFUL, §5 [C]).
func _top_up() -> void:
	var monkey: Monkey = gs.monkey()
	if monkey == null:
		return
	while monkey.fullness < Care.FULLNESS_HUNGRY_MAX:
		if gs.inventory().get("banana", 0) == 0:
			# Stand-in for the purses and shopping trips a real player lives on;
			# this test is about the seams, not the food economy.
			gs.run.economy.earn(1000)
			gs.buy_food("banana", 5)
		var before := monkey.fullness
		gs.feed("banana")
		if monkey.fullness <= before:
			return                       # refused — do not spin


func _train(activity: int, reps: int = 60) -> Training.Result:
	_top_up()
	return gs.do_training(activity, RhythmScore.average(reps))


## Spend both of today's half-days on training, landing on tomorrow morning.
func _play_a_day() -> void:
	_train(int(Training.Activity.PUNCHBAG))
	_train(int(Training.Activity.RUNNING))


## Settle a match with a chosen outcome. Goes through the real GameState path,
## so the purse and the rank move are computed by Economy and Ladder.
func _settle(outcome: MatchResolver.Outcome, opponent_rank: int) -> MatchResolver.MatchResult:
	var result := MatchResolver.MatchResult.new()
	result.outcome = outcome
	result.opponent_rank = opponent_rank
	result.player_won = outcome == MatchResolver.Outcome.WIN_KO \
		or outcome == MatchResolver.Outcome.WIN_DECISION
	gs.finish_match(result)
	return result


## Fixture: hand the monkey every ceiling it can reach. Capping all five through
## the training loop is exercised for real in
## `test_training_stops_dead_at_the_ceiling`; doing it five times over in every
## breeding test would only buy runtime.
func _max_out(monkey: Monkey) -> void:
	for stat in Monkey.STATS:
		monkey.set_stat(stat, monkey.get_cap(stat))


# --- the run starts ----------------------------------------------------------

func test_a_new_run_is_actually_usable() -> void:
	_start()
	assert_true(gs.has_run(), "new_run must produce a run — RunState.new_run was a stub")
	var monkey: Monkey = gs.monkey()
	assert_not_null(monkey, "a fresh run must have an active monkey")
	# Dossier §8 [C]: Freddy's name is fixed.
	assert_eq(monkey.monkey_name, "Freddy")
	assert_eq(monkey.generation, 1)
	assert_eq(gs.day(), 1)
	assert_eq(gs.slot(), int(DayCycle.Slot.AM))
	assert_eq(gs.rank(), Ladder.BOTTOM_RANK, "the slice's ladder starts at the bottom rung")
	assert_eq(gs.money(), Economy.STARTING_MONEY)
	# Every system the facade forwards into must be present, or the first UI
	# call into it crashes.
	for system in [gs.run.rules, gs.run.rng, gs.run.economy, gs.run.day_cycle,
			gs.run.ladder, gs.run.care, gs.run.training, gs.run.breeding]:
		assert_not_null(system, "new_run left a system null")


func test_the_starter_arrives_with_freddys_observed_ceilings() -> void:
	_start()
	var monkey: Monkey = gs.monkey()
	var expected := RunState.starter_caps()
	for stat in Monkey.STATS:
		assert_eq(monkey.get_cap(stat), int(expected[stat]),
			"cap for %s" % Monkey.stat_label(stat))
		assert_true(monkey.get_stat(stat) < monkey.get_cap(stat),
			"the starter must have room to train %s" % Monkey.stat_label(stat))


func test_the_starter_does_not_trust_you_yet() -> void:
	# Dossier §5 [C]: "Befriending gates everything. Every new monkey, Freddy
	# included, must be won over with food before it will train."
	_start()
	assert_false(gs.monkey().is_befriended())
	assert_false(gs.can_train(), "an unbefriended monkey must refuse to train")
	assert_ne(gs.block_reason(), "", "the refusal must come with a reason to show")


func test_a_run_starts_with_bananas_in_the_larder() -> void:
	_start()
	assert_true(gs.inventory().get("banana", 0) >= 2,
		"the documented two-banana befriending needs two bananas to exist")


# --- feeding and friendship --------------------------------------------------

func test_two_bananas_befriend_the_starter() -> void:
	_start()
	_befriend()
	assert_true(gs.monkey().is_befriended(),
		"dossier §5 [C] documents two bananas as the fastest path")
	assert_eq(gs.block_reason(), "")
	assert_true(gs.can_train())


func test_feeding_is_free_and_costs_no_half_day() -> void:
	# Dossier §2 [C]: "Feeding is free and does not consume a slot."
	_start()
	var day: int = gs.day()
	var slot: int = gs.slot()
	for _i in 3:
		gs.feed("banana")
	assert_eq(gs.day(), day, "feeding must not move the day")
	assert_eq(gs.slot(), slot, "feeding must not spend a half-day")


func test_feeding_emits_the_signals_the_screens_listen_for() -> void:
	_start()
	var fed_results: Array = []
	var fullness_events: Array = []
	var friendship_events: Array = []
	gs.monkey_fed.connect(func(r) -> void: fed_results.append(r))
	gs.fullness_changed.connect(func(v: int) -> void: fullness_events.append(v))
	gs.friendship_changed.connect(func(v: int) -> void: friendship_events.append(v))

	gs.feed("banana")
	assert_eq(fed_results.size(), 1, "monkey_fed must fire exactly once per feed")
	assert_not_null(fed_results[0])
	assert_ne(String(fed_results[0].message), "", "the UI needs a line to print")
	assert_false(fullness_events.is_empty(), "the fullness meter must be told")
	assert_false(friendship_events.is_empty(), "the friendship meter must be told")


func test_feeding_an_unknown_food_is_survivable() -> void:
	_start()
	assert_null(gs.feed("moon_cheese"), "an unknown id must not crash the facade")


func test_overfeeding_immobilises_the_monkey() -> void:
	# FAITHFUL, requested explicitly. Dossier §5 [C]: overfed, the monkey cannot
	# move until it digests. This must never be softened into "wastes food".
	_start()
	_befriend()
	gs.run.economy.earn(20000)
	gs.buy_food("bread", 12)
	var monkey: Monkey = gs.monkey()
	var guard := 0
	while not monkey.is_stuffed() and guard < 40:
		guard += 1
		gs.feed("bread")
	assert_true(monkey.is_stuffed(), "feeding past the top of the belly must stuff it")
	assert_false(gs.can_train(), "a stuffed monkey must not be able to train")
	assert_true(gs.block_reason().contains("DIGEST"),
		"the reason must say it is digesting, not that food was wasted")
	# And it must be a temporary state that digestion clears.
	var slots := 0
	while gs.block_reason() != "" and slots < 12:
		slots += 1
		gs.consume_slot()
	assert_eq(gs.block_reason(), "", "digestion must eventually free the monkey")


# --- the day cycle -----------------------------------------------------------

func test_a_training_session_spends_exactly_one_half_day() -> void:
	_start()
	_befriend()
	assert_eq(gs.slot(), int(DayCycle.Slot.AM))
	_train(int(Training.Activity.PUNCHBAG))
	assert_eq(gs.day(), 1, "the first session stays inside day 1")
	assert_eq(gs.slot(), int(DayCycle.Slot.PM), "AM -> PM")
	_train(int(Training.Activity.RUNNING))
	assert_eq(gs.day(), 2, "the second session rolls the day over")
	assert_eq(gs.slot(), int(DayCycle.Slot.AM))


func test_the_am_and_pm_slots_both_raise_their_own_stat() -> void:
	_start()
	_befriend()
	var monkey: Monkey = gs.monkey()
	var power_before := monkey.get_stat(Monkey.Stat.POWER)
	var stamina_before := monkey.get_stat(Monkey.Stat.STAMINA)

	var am := _train(int(Training.Activity.PUNCHBAG))
	assert_not_null(am, "the AM session must run")
	assert_eq(int(am.stat), int(Monkey.Stat.POWER), "punchbag trains Power")
	assert_true(am.gain_applied > 0, "a clean session must land a gain")

	var pm := _train(int(Training.Activity.RUNNING))
	assert_not_null(pm, "the PM session must run")
	assert_eq(int(pm.stat), int(Monkey.Stat.STAMINA), "running trains Stamina")

	assert_true(monkey.get_stat(Monkey.Stat.POWER) > power_before)
	assert_true(monkey.get_stat(Monkey.Stat.STAMINA) > stamina_before)


func test_a_day_rollover_announces_itself_once() -> void:
	_start()
	_befriend()
	var days_started: Array = []
	var slots: Array = []
	gs.day_started.connect(func(d: int) -> void: days_started.append(d))
	gs.day_advanced.connect(func(d: int, s: int) -> void: slots.append([d, s]))

	_play_a_day()
	assert_eq(days_started, [2], "exactly one day_started for one rollover")
	assert_eq(slots.size(), 2, "two activities, two slot moves")


func test_shopping_costs_a_slot_and_raises_knowledge() -> void:
	# Dossier §4 [C]: it is the MONKEY that goes shopping, Knowledge rises either
	# way, and it comes back with only part of the list.
	_start()
	_befriend()
	_top_up()
	var monkey: Monkey = gs.monkey()
	var knowledge_before := monkey.get_stat(Monkey.Stat.KNOWLEDGE)
	var result: Training.Result = gs.do_shopping({})
	assert_not_null(result, "free-choice shopping must run")
	assert_eq(gs.slot(), int(DayCycle.Slot.PM), "a shopping trip is a half-day")
	assert_true(monkey.get_stat(Monkey.Stat.KNOWLEDGE) > knowledge_before,
		"Knowledge rises either way")


func test_days_keep_advancing_over_a_long_stretch() -> void:
	_start()
	_befriend()
	for _i in 8:
		_play_a_day()
	assert_eq(gs.day(), 9, "eight played days land on day 9")
	assert_eq(gs.slot(), int(DayCycle.Slot.AM))


func test_bill_rings_the_doorbell_on_an_offer_day() -> void:
	# Dossier §7 phase 2 [C]. Ladder owns the cadence; GameState only announces.
	_start()
	_befriend()
	var events: Array = []
	gs.story_event.connect(func(id: String) -> void: events.append(id))
	while gs.day() < Ladder.FIRST_OFFER_DAY:
		_play_a_day()
	assert_has(events, GameState_event_bill_offer(),
		"Bill must ring the doorbell on the first offer day")


## The constant lives on the GameState script; read it without an autoload.
func GameState_event_bill_offer() -> String:
	return GameStateScript.EVENT_BILL_OFFER


# --- matches -----------------------------------------------------------------

func test_bill_offers_three_candidates_with_one_above_you() -> void:
	_start()
	_befriend()
	var offers: Array = gs.offered_opponents()
	assert_eq(offers.size(), Ladder.OFFER_COUNT, "Bill offers three")
	var above := 0
	for offer in offers:
		if offer.is_above_player:
			above += 1
		assert_not_null(offer.monkey, "every card needs a monkey to show")
		assert_true(offer.purse > 0, "every card needs a purse to show")
	assert_true(above >= 1, "at least one candidate must outrank the player")


func test_booking_an_opponent_sets_the_match_day_phase() -> void:
	_start()
	_befriend()
	var booked: Array = []
	gs.opponent_booked.connect(func(o) -> void: booked.append(o))
	gs.offered_opponents()
	gs.book_opponent(0)
	assert_eq(booked.size(), 1, "the home screen is told a fight is on")
	assert_not_null(gs.run.booked_opponent)
	assert_eq(int(gs.run.phase), int(RunState.Phase.MATCH_DAY))


func test_a_booked_match_can_be_fought_start_to_finish() -> void:
	# The full resolver path: GameState builds it, the UI would step it, and
	# GameState settles up afterwards.
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.monkey().restore_pools()
	gs.offered_opponents()
	gs.book_opponent(0)

	var events: Array = []
	var finished: Array = []
	gs.match_event.connect(func(e) -> void: events.append(e))
	gs.match_finished.connect(func(r) -> void: finished.append(r))

	var resolver: MatchResolver = gs.start_match()
	assert_not_null(resolver, "start_match must build a resolver")
	assert_not_null(resolver.player)
	assert_not_null(resolver.opponent)

	var result: MatchResolver.MatchResult = resolver.simulate_match(MatchResolver.Strategy.BALANCED)
	assert_not_null(result)
	# Dossier §6 [C]: three rounds — unless somebody goes down for good first,
	# because a KO ends the fight where it stands.
	assert_in_range(result.rounds.size(), 1, MatchResolver.ROUNDS,
		"a match runs at most three rounds")
	var by_ko := result.outcome == MatchResolver.Outcome.WIN_KO \
		or result.outcome == MatchResolver.Outcome.LOSS_KO
	if not by_ko:
		assert_eq(result.rounds.size(), MatchResolver.ROUNDS,
			"a fight that goes to the judges must have gone the full three rounds")
	assert_false(events.is_empty(), "the fight screen needs events to play back")
	assert_eq(finished.size(), 1, "match_finished must fire exactly once")

	gs.finish_match(result)
	assert_null(gs.current_match, "settling up must clear the live match")
	assert_null(gs.run.booked_opponent, "the booking is spent")


func test_starting_a_match_spends_the_half_day() -> void:
	_start()
	_befriend()
	gs.offered_opponents()
	gs.book_opponent(0)
	assert_eq(gs.slot(), int(DayCycle.Slot.AM))
	gs.start_match()
	assert_eq(gs.slot(), int(DayCycle.Slot.PM), "a match is an activity like any other")


func test_winning_pays_a_purse() -> void:
	_start()
	_befriend()
	var before: int = gs.money()
	var result := _settle(MatchResolver.Outcome.WIN_KO, gs.rank())
	assert_true(result.purse > 0, "a win must be worth something")
	assert_eq(gs.money(), before + result.purse, "the purse must reach the wallet")
	assert_eq(gs.monkey().wins, 1)


func test_losing_pays_less_than_winning() -> void:
	_start()
	_befriend()
	var opponent_rank: int = gs.rank()
	var win := Economy.purse_for(opponent_rank, gs.rank(), true)
	var loss := Economy.purse_for(opponent_rank, gs.rank(), false)
	assert_true(loss < win, "a loss must pay less than a win")
	var before: int = gs.money()
	_settle(MatchResolver.Outcome.LOSS_DECISION, opponent_rank)
	assert_eq(gs.money(), before + loss)
	assert_eq(gs.monkey().losses, 1)


func test_a_stronger_opponent_is_worth_a_bigger_purse() -> void:
	# Dossier §7 [C]. Rank 1 is the top, so a LOWER number is a stronger foe.
	_start()
	var strong := Economy.purse_for(1, Ladder.BOTTOM_RANK, true)
	var weak := Economy.purse_for(Ladder.BOTTOM_RANK, Ladder.BOTTOM_RANK, true)
	assert_true(strong > weak)


func test_beating_a_higher_rank_promotes_you() -> void:
	# Dossier §7 [C]: "Beat a higher-ranked monkey -> +1 rank."
	_start()
	_befriend()
	var moves: Array = []
	gs.rank_changed.connect(func(o: int, n: int) -> void: moves.append([o, n]))
	var before: int = gs.rank()
	_settle(MatchResolver.Outcome.WIN_KO, before - 1)
	assert_eq(gs.rank(), before - 1, "one rung up the ladder")
	assert_eq(moves.size(), 1, "the rank move must be announced once")


func test_beating_a_lower_rank_pays_but_does_not_promote() -> void:
	# Dossier §7 [C]: "the guides do it purely for cash."
	_start()
	_befriend()
	gs.run.ladder.rank = 3
	var money_before: int = gs.money()
	_settle(MatchResolver.Outcome.WIN_DECISION, 4)
	assert_eq(gs.rank(), 3, "beating someone below you must not promote")
	assert_true(gs.money() > money_before, "but it must still pay")


func test_losing_to_a_lower_rank_demotes_you() -> void:
	# Dossier §7 [C]: "Lose to a lower-ranked monkey -> -1 rank."
	_start()
	_befriend()
	gs.run.ladder.rank = 3
	_settle(MatchResolver.Outcome.LOSS_KO, 4)
	assert_eq(gs.rank(), 4, "one rung down")


func test_losing_to_someone_above_you_costs_nothing() -> void:
	_start()
	_befriend()
	gs.run.ladder.rank = 3
	_settle(MatchResolver.Outcome.LOSS_KO, 2)
	assert_eq(gs.rank(), 3, "losing to a better monkey is no disgrace")


func test_climbing_to_rank_one_makes_you_champion() -> void:
	_start()
	_befriend()
	var champion_calls: Array = []
	gs.champion_reached.connect(func() -> void: champion_calls.append(true))
	var guard := 0
	while gs.rank() > Ladder.TOP_RANK and guard < 20:
		guard += 1
		_settle(MatchResolver.Outcome.WIN_KO, gs.rank() - 1)
	assert_eq(gs.rank(), Ladder.TOP_RANK)
	assert_eq(champion_calls.size(), 1, "the champion beat fires once")
	assert_eq(int(gs.run.phase), int(RunState.Phase.CHAMPION))


# --- caps --------------------------------------------------------------------

func test_training_stops_dead_at_the_ceiling() -> void:
	# Dossier §3 [C]: caps are hard, a capped stat shows a star, and only
	# breeding raises it. GameRules.hard_stat_caps is true in this build.
	_start()
	_befriend()
	var monkey: Monkey = gs.monkey()
	var cap := monkey.get_cap(Monkey.Stat.POWER)
	var starred_reports := 0
	var guard := 0
	while not monkey.is_capped(Monkey.Stat.POWER) and guard < 400:
		guard += 1
		var result: Training.Result = _train(int(Training.Activity.PUNCHBAG))
		if result != null and result.starred_out:
			starred_reports += 1
	assert_true(monkey.is_capped(Monkey.Stat.POWER),
		"training must be able to reach the ceiling (gave up after %d sessions)" % guard)
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), cap, "and must stop exactly on it")
	assert_eq(starred_reports, 1, "starring out is announced once, not every session")

	# Past the ceiling, further sessions do nothing to the number.
	var after: Training.Result = _train(int(Training.Activity.PUNCHBAG))
	assert_not_null(after)
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), cap, "a starred stat never moves again")
	assert_true(after.was_capped, "and the session must say so")


func test_a_capped_monkey_is_ready_to_breed() -> void:
	_start()
	_befriend()
	assert_false(gs.can_breed(), "an untrained monkey has nothing to pass on yet")
	_max_out(gs.monkey())
	assert_true(gs.monkey().all_capped())
	assert_true(gs.can_breed(), "every stat starred is the signal to pair")


# --- breeding ----------------------------------------------------------------

func test_the_dating_shop_offers_partners_with_previews() -> void:
	_start()
	_befriend()
	_max_out(gs.monkey())
	var partners: Array = gs.breeding_partners()
	assert_false(partners.is_empty(), "the dating shop must have somebody in it")
	for i in partners.size():
		var preview: Breeding.Preview = gs.preview_partner(i)
		assert_not_null(preview, "every partner must preview")
		assert_eq(preview.arrows.size(), Monkey.STATS.size(),
			"the preview shows one arrow per stat")
		for stat in Monkey.STATS:
			assert_has([Breeding.Arrow.DOWN, Breeding.Arrow.FLAT, Breeding.Arrow.UP],
				int(preview.arrows[stat]), "arrows may point down — that is the point")


func test_breeding_produces_generation_two_and_retires_the_parent() -> void:
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.run.economy.earn(50000)
	var parent: Monkey = gs.monkey()
	var parent_name := parent.monkey_name

	var bred_results: Array = []
	var retired: Array = []
	var swapped: Array = []
	gs.bred.connect(func(r) -> void: bred_results.append(r))
	gs.monkey_retired.connect(func(m) -> void: retired.append(m))
	gs.active_monkey_changed.connect(func(m) -> void: swapped.append(m))

	gs.breeding_partners()
	var result: Breeding.BreedResult = gs.breed_with(0, "Tomato")
	assert_not_null(result)
	assert_not_null(result.baby, "a pairing must produce a baby")
	assert_eq(bred_results.size(), 1, "bred fires once")

	var baby: Monkey = gs.monkey()
	assert_eq(baby.monkey_name, "Tomato")
	assert_eq(baby.generation, 2, "the slice needs generation 2")
	assert_ne(baby, parent, "the baby must become the active monkey")
	assert_false(swapped.is_empty(), "the screens must be told the monkey changed")

	# RULE CHANGE: breeding_destroys_parent = false. The original vanishes the
	# parent (§8 [C]); here it retires to a roster you can still look at.
	assert_false(gs.rules().breeding_destroys_parent)
	assert_true(result.parent_retired)
	assert_false(result.parent_destroyed)
	assert_true(parent.retired, "the parent is marked retired")
	assert_eq(retired.size(), 1, "monkey_retired fires once")

	var roster: Array = gs.roster()
	assert_eq(roster.size(), 1, "the retired parent must be on the wall")
	assert_eq(roster[0].monkey_name, parent_name)
	assert_true(roster[0].all_capped(), "it retired with every ceiling reached")


func test_the_baby_inherits_the_ceiling_not_the_stats() -> void:
	# Dossier §8 [C]: "What is inherited is the ceiling, not the current stats."
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.run.economy.earn(50000)
	var parent_caps: Dictionary = gs.monkey().caps.duplicate()

	gs.breeding_partners()
	var result: Breeding.BreedResult = gs.breed_with(0, "Cookie")
	var baby: Monkey = gs.monkey()

	for stat in Monkey.STATS:
		assert_true(baby.get_stat(stat) <= Breeding.BABY_START_STAT,
			"the baby starts near zero on %s" % Monkey.stat_label(stat))
		assert_true(baby.get_cap(stat) > 0, "but it inherits a real ceiling")
		assert_has(result.cap_changes, stat, "every stat must report its cap move")
		var pair: Array = result.cap_changes[stat]
		assert_eq(int(pair[0]), int(parent_caps[stat]), "old cap is the parent's")
		assert_eq(int(pair[1]), baby.get_cap(stat), "new cap is the baby's")


func test_the_baby_has_to_be_won_over_all_over_again() -> void:
	# Dossier §8 [C]: the baby must be re-befriended with food.
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.run.economy.earn(50000)
	gs.breeding_partners()
	gs.breed_with(0, "Pizza")

	assert_eq(gs.monkey().friendship, 0, "a newborn trusts nobody")
	assert_false(gs.can_train(), "and will not train until it does")
	gs.buy_food("banana", 4)
	gs.feed("banana")
	gs.feed("banana")
	assert_true(gs.monkey().is_befriended(), "two bananas works on the baby too")
	assert_true(gs.can_train())


func test_breeding_charges_the_dating_fee() -> void:
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.run.economy.earn(50000)
	var partners: Array = gs.breeding_partners()
	var fee: int = partners[0].fee
	var before: int = gs.money()
	var result: Breeding.BreedResult = gs.breed_with(0, "Lemon")
	assert_eq(result.fee_paid, fee)
	assert_eq(gs.money(), before - fee, "the fee must actually leave the wallet")


# --- save and load -----------------------------------------------------------

func test_a_run_survives_save_quit_continue() -> void:
	_start()
	_befriend()
	_play_a_day()
	_train(int(Training.Activity.SKIPPING))
	gs.run.ladder.rank = 3

	var monkey: Monkey = gs.monkey()
	var expected := {
		"day": gs.day(),
		"slot": gs.slot(),
		"money": gs.money(),
		"rank": gs.rank(),
		"name": monkey.monkey_name,
		"friendship": monkey.friendship,
		"fullness": monkey.fullness,
		"generation": monkey.generation,
	}
	var expected_stats := {}
	for stat in Monkey.STATS:
		expected_stats[stat] = monkey.get_stat(stat)

	assert_true(gs.save_run(), "saving must succeed")
	assert_true(gs.has_save())

	# "Quit and come back": a brand new facade, loading from disk.
	gs.free()
	gs = GameStateScript.new()
	assert_true(gs.load_run(), "the save must load")

	var restored: Monkey = gs.monkey()
	assert_eq(gs.day(), expected["day"])
	assert_eq(gs.slot(), expected["slot"])
	assert_eq(gs.money(), expected["money"])
	assert_eq(gs.rank(), expected["rank"])
	assert_eq(restored.monkey_name, expected["name"])
	assert_eq(restored.friendship, expected["friendship"])
	assert_eq(restored.fullness, expected["fullness"])
	assert_eq(restored.generation, expected["generation"])
	for stat in Monkey.STATS:
		assert_eq(restored.get_stat(stat), int(expected_stats[stat]),
			"stat %s must survive the round trip" % Monkey.stat_label(stat))

	# And the loaded run must be LIVE, not a read-only snapshot: feeding, then
	# training, then the clock, all have to work off the restored systems.
	var day_before: int = gs.day()
	var slot_before: int = gs.slot()
	var power_before := restored.get_stat(Monkey.Stat.POWER)
	_top_up()
	assert_true(gs.can_train(), "a fed, restored monkey must be able to train")
	var session: Training.Result = _train(int(Training.Activity.PUNCHBAG))
	assert_not_null(session, "the restored run must run a session")
	assert_true(restored.get_stat(Monkey.Stat.POWER) > power_before,
		"and the gain must land on the restored monkey")
	assert_true(gs.day() != day_before or gs.slot() != slot_before,
		"and the restored clock must move")


func test_the_roster_survives_a_save() -> void:
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.run.economy.earn(50000)
	gs.breeding_partners()
	gs.breed_with(0, "Dragon")
	var parent_name: String = gs.roster()[0].monkey_name

	gs.save_run()
	gs.free()
	gs = GameStateScript.new()
	gs.load_run()

	var roster: Array = gs.roster()
	assert_eq(roster.size(), 1, "a retired parent must still be on the wall after a reload")
	assert_eq(roster[0].monkey_name, parent_name)
	assert_true(roster[0].retired)
	assert_eq(gs.monkey().generation, 2, "and the baby is still the active monkey")


func test_the_title_screen_can_summarise_a_save_without_loading_it() -> void:
	_start()
	_befriend()
	_play_a_day()
	gs.save_run()
	var info := SaveGame.peek()
	assert_true(bool(info["exists"]))
	assert_eq(int(info["day"]), gs.day())
	assert_eq(String(info["monkey_name"]), gs.monkey().monkey_name)
	assert_eq(int(info["rank"]), gs.rank())


func test_loading_with_no_save_fails_quietly() -> void:
	SaveGame.delete_save()
	assert_false(gs.has_save())
	assert_false(gs.load_run(), "no save must be a clean false, not a crash")
	assert_false(gs.has_run())


func test_the_day_rollover_autosaves() -> void:
	_start()
	_befriend()
	assert_false(gs.has_save(), "nothing is written before the first day ends")
	_play_a_day()
	assert_true(gs.has_save(), "a finished day must be committed")
	assert_eq(int(SaveGame.peek()["day"]), gs.day())


# --- destitution -------------------------------------------------------------

func test_running_out_of_everything_grants_a_bailout_instead_of_a_game_over() -> void:
	# RULE CHANGE: bankruptcy_game_over = false. The original's only documented
	# fail state (§9 [C]) becomes a warning and a hand-out here.
	_start()
	_befriend()
	assert_false(gs.rules().bankruptcy_game_over)
	var bailouts: Array = []
	var overs: Array = []
	gs.bailout_granted.connect(func(a: int) -> void: bailouts.append(a))
	gs.game_over.connect(func(r: String) -> void: overs.append(r))

	gs.run.economy.money = 0
	gs.run.economy.inventory.clear()
	assert_true(gs.run.economy.is_destitute())
	# The check runs at the top of a day, inside consume_slot's rollover.
	gs.consume_slot()
	gs.consume_slot()

	assert_false(bailouts.is_empty(), "the player must be bailed out")
	assert_true(overs.is_empty(), "and must NOT be shown a game over")
	assert_true(gs.money() > 0)


# --- the whole slice ---------------------------------------------------------

func test_the_whole_slice_plays_through() -> void:
	## Title -> new run -> befriend -> train both slots -> days pass -> a match
	## -> rank moves and the purse is paid -> caps -> breed -> generation 2 with
	## the parent on the wall -> save and reload. Every arrow in the brief, in
	## one pass, in order.
	_start()
	assert_true(gs.has_run())

	# Befriend.
	_befriend()
	assert_true(gs.monkey().is_befriended())
	gs.set_phase(int(RunState.Phase.LADDER))

	# Three days of training, two activities each.
	for _day in 3:
		_play_a_day()
	assert_eq(gs.day(), 4)

	# A match: Bill's card, a booking, the fight, the settle-up.
	gs.run.ladder.rank = 4
	_max_out(gs.monkey())
	gs.monkey().restore_pools()
	# Three days of training leave the monkey hungry, and §5 [C] is explicit that
	# an underfed monkey is immobilised — it cannot answer the bell any more than
	# it can train. Feed it before the fight, as a player has to.
	_top_up()
	var offers: Array = gs.offered_opponents()
	assert_eq(offers.size(), Ladder.OFFER_COUNT)
	gs.book_opponent(0)
	var resolver: MatchResolver = gs.start_match()
	assert_not_null(resolver)
	var outcome: MatchResolver.MatchResult = resolver.simulate_match(MatchResolver.Strategy.DEFEND)
	var money_before: int = gs.money()
	gs.finish_match(outcome)
	assert_true(gs.money() >= money_before, "a fought match always pays something")
	assert_eq(gs.monkey().wins + gs.monkey().losses, 1, "the record must be written")

	# Capped out, so the only way forward is a new generation (§7 phase 3 [C]).
	_max_out(gs.monkey())
	assert_true(gs.can_breed())
	gs.run.economy.earn(50000)
	var parent_name: String = gs.monkey().monkey_name
	gs.breeding_partners()
	var birth: Breeding.BreedResult = gs.breed_with(0, "Agatha")
	assert_not_null(birth.baby)
	assert_eq(gs.monkey().monkey_name, "Agatha")
	assert_eq(gs.monkey().generation, 2)
	assert_eq(gs.roster().size(), 1)
	assert_eq(gs.roster()[0].monkey_name, parent_name)

	# The baby is a stranger again, and has to be raised from scratch.
	assert_false(gs.can_train())
	gs.buy_food("banana", 6)
	_befriend()
	assert_true(gs.can_train())
	_play_a_day()

	# And the whole thing survives being put down and picked up again.
	assert_true(gs.save_run())
	var day_before: int = gs.day()
	gs.free()
	gs = GameStateScript.new()
	assert_true(gs.load_run())
	assert_eq(gs.day(), day_before)
	assert_eq(gs.monkey().monkey_name, "Agatha")
	assert_eq(gs.monkey().generation, 2)
	assert_eq(gs.roster().size(), 1)
	# Playable, not just readable: feed the reloaded baby and put it to work.
	_top_up()
	assert_true(gs.can_train(), "the reloaded run must still be playable")
	assert_not_null(_train(int(Training.Activity.SIT_UPS)),
		"and must still run a training session")


# --- immobility must not be a dead end ---------------------------------------
#
# Added by the Verification agent. GameRules.overfeeding_paralyses is FAITHFUL at
# the user's explicit request (§5 [C]: "Overfed, it cannot move until it
# digests"), and GameRules.bankruptcy_game_over is false, which is supposed to
# warn and bail out rather than end the run. Both of those only work if the clock
# can still move while the monkey cannot.

func test_overfeeding_paralyses_and_blocks_every_activity() -> void:
	_start()
	_befriend()
	var monkey: Monkey = gs.monkey()
	monkey.fullness = Monkey.FULLNESS_STUFFED
	assert_true(gs.run.care.is_paralysed(monkey), "stuffed must mean paralysed")
	assert_false(gs.can_train(), "a stuffed monkey must not train")
	assert_null(gs.do_training(int(Training.Activity.PUNCHBAG), RhythmScore.average(60)),
		"a stuffed monkey must not be able to run a session")
	assert_null(gs.do_shopping({}), "a stuffed monkey must not go shopping")
	assert_false(gs.can_fight(), "a stuffed monkey must not be able to fight")


func test_a_paralysed_monkey_cannot_answer_the_bell() -> void:
	# §5 [C]: both hunger extremes immobilise. Overfeeding is FAITHFUL here, so
	# it has to bite in the ring too, not only in the gym.
	_start()
	_befriend()
	gs.offered_opponents()
	gs.book_opponent(0)
	assert_not_null(gs.run.booked_opponent, "a fight must be booked for this to mean anything")
	var monkey: Monkey = gs.monkey()
	monkey.fullness = Monkey.FULLNESS_STUFFED
	assert_null(gs.start_match(), "an overfed monkey must not be allowed to fight")
	assert_null(gs.current_match)
	monkey.fullness = Monkey.FULLNESS_STARVING
	assert_null(gs.start_match(), "a starving monkey must not be allowed to fight either")
	# Fed back into the workable band, the fight goes ahead.
	monkey.fullness = Care.FULLNESS_CONTENT_MAX
	assert_not_null(gs.start_match(), "a monkey that can move must be able to box")


func test_resting_moves_the_clock_when_the_monkey_cannot() -> void:
	# Without this the two faithful paralysis states are a softlock: every other
	# slot-consuming action refuses, so digest_tick never runs.
	_start()
	_befriend()
	var monkey: Monkey = gs.monkey()
	monkey.fullness = Monkey.FULLNESS_MAX
	assert_true(gs.run.care.is_paralysed(monkey))
	var slot_before: int = gs.run.day_cycle.total_slots_elapsed()
	assert_true(gs.rest(), "resting must be available while the monkey cannot act")
	assert_eq(gs.run.day_cycle.total_slots_elapsed(), slot_before + 1,
		"a rest costs exactly one half-day slot")
	assert_true(monkey.fullness < Monkey.FULLNESS_MAX, "and the monkey digests")
	var guard := 0
	while gs.run.care.is_paralysed(monkey) and guard < 20:
		guard += 1
		gs.rest()
	assert_false(gs.run.care.is_paralysed(monkey),
		"overfeeding must wear off once the clock moves")


func test_a_destitute_starving_run_still_reaches_its_bailout() -> void:
	# Dossier §9 [C] is the original's only fail state; this build softens it to
	# a warning plus a bailout (bankruptcy_game_over = false). That promise is
	# empty if the run can dead-end before the day rollover that grants it.
	_start()
	_befriend()
	var monkey: Monkey = gs.monkey()
	gs.run.economy.inventory = {}
	gs.run.economy.money = 0
	monkey.fullness = 0
	assert_true(gs.run.economy.is_destitute())
	assert_false(gs.can_train(), "a starving monkey will not work")
	var warned := [false]
	var bailed := [0]
	gs.destitute_warning.connect(func() -> void: warned[0] = true)
	gs.bailout_granted.connect(func(amount: int) -> void: bailed[0] = amount)
	var over := [false]
	gs.game_over.connect(func(_reason: String) -> void: over[0] = true)
	# Two rests carry the run over the day boundary, where the check lives.
	gs.rest()
	gs.rest()
	assert_true(warned[0], "the player must be warned")
	assert_eq(bailed[0], Economy.BAILOUT_AMOUNT, "and bailed out")
	assert_false(over[0], "bankruptcy_game_over is false — the run must not end")
	assert_true(gs.money() > 0, "and must be able to buy food again")


func test_a_starving_monkey_with_money_but_no_food_is_not_a_dead_end() -> void:
	# The bailout only covers "food AND money both depleted" (dossier §9 [C]).
	# A player with cash and an empty larder is NOT destitute, so nothing paid
	# out — and money cannot become food on its own, because it is the MONKEY
	# that goes shopping (§2 [C]) and a starving monkey will not go.
	_start()
	_befriend()
	var monkey: Monkey = gs.monkey()
	gs.run.economy.inventory = {}
	gs.run.economy.money = 5000
	monkey.fullness = 0
	assert_false(gs.run.economy.is_destitute(), "money in the pocket is not destitution")
	assert_false(gs.can_train(), "and yet nothing can be done")
	assert_null(gs.do_shopping({}), "the monkey cannot be sent to fix it")

	var parcels: Array = []
	gs.relief_granted.connect(func(parcel: Dictionary) -> void: parcels.append(parcel))
	# Two rests carry the run over the day boundary, where the check lives.
	gs.rest()
	gs.rest()
	assert_eq(parcels.size(), 1, "core must post the emergency parcel exactly once")
	assert_true(gs.run.economy.total_food() > 0, "there must be food to feed")

	# And the food actually gets the monkey moving again.
	var food_id := String(gs.inventory().keys()[0])
	while gs.run.care.needs_food_to_act(monkey) and gs.run.economy.food_count(food_id) > 0:
		gs.feed(food_id)
	assert_eq(gs.block_reason(), "", "the parcel has to be enough to unblock it")
	assert_true(gs.can_train())


func test_the_relief_parcel_does_not_pre_empt_the_bailout() -> void:
	# Order matters: the parcel puts food in the larder, which would clear
	# Economy.is_destitute() before the check that owns the documented fail
	# state (§9 [C]) ever saw it, and the bailout would silently stop firing.
	_start()
	_befriend()
	gs.monkey().fullness = 0
	gs.run.economy.inventory = {}
	gs.run.economy.money = 0
	var warned := [0]
	var bailed := [0]
	var parcels := [0]
	gs.destitute_warning.connect(func() -> void: warned[0] += 1)
	gs.bailout_granted.connect(func(_a: int) -> void: bailed[0] += 1)
	gs.relief_granted.connect(func(_p: Dictionary) -> void: parcels[0] += 1)
	gs.rest()
	gs.rest()
	assert_eq(warned[0], 1, "the warning still fires")
	assert_eq(bailed[0], 1, "and so does the bailout")
	assert_eq(parcels[0], 1, "and the parcel lands as well")


func test_the_relief_parcel_stays_away_while_there_is_any_food_left() -> void:
	_start()
	_befriend()
	gs.monkey().fullness = 0
	gs.run.economy.inventory = {"biscuit": 1}
	var parcels := [0]
	gs.relief_granted.connect(func(_p: Dictionary) -> void: parcels[0] += 1)
	gs.rest()
	gs.rest()
	assert_eq(parcels[0], 0, "one biscuit is still a move the player can make")


func test_a_stuffed_monkey_is_never_sent_a_parcel() -> void:
	# Feeding is the wrong answer to overfeeding — posting food would be advice
	# that makes the situation worse, and overfeeding_paralyses is FAITHFUL.
	_start()
	_befriend()
	gs.monkey().fullness = Monkey.FULLNESS_MAX
	gs.run.economy.inventory = {}
	var parcels := [0]
	gs.relief_granted.connect(func(_p: Dictionary) -> void: parcels[0] += 1)
	gs.rest()
	gs.rest()
	assert_eq(parcels[0], 0, "a stuffed monkey needs time, not food")


# --- the generational sawtooth ------------------------------------------------

func test_breeding_sends_the_new_generation_back_to_the_bottom() -> void:
	# Dossier §2 [C] core loop: "BREED ... -> re-climb the ladder from the
	# bottom", and §7 phase 3 [C] calls that sawtooth the game's defining
	# structural decision. Breeding's own message already promises it.
	_start()
	_befriend()
	_max_out(gs.monkey())
	gs.run.economy.earn(50000)
	gs.run.ladder.rank = Ladder.TOP_RANK + 1
	gs.offered_opponents()
	gs.book_opponent(0)
	var moves: Array = []
	gs.rank_changed.connect(func(o: int, n: int) -> void: moves.append([o, n]))
	gs.breeding_partners()
	var result: Breeding.BreedResult = gs.breed_with(0, "Betty")
	assert_not_null(result.baby)
	assert_eq(gs.rank(), Ladder.BOTTOM_RANK,
		"the baby re-enters the ladder at the bottom, as the birth message says")
	assert_eq(moves.size(), 1, "the rank move must be announced once")
	assert_null(gs.run.booked_opponent,
		"a fight booked for the retired parent must not carry over")
	assert_eq(gs.run.phase, RunState.Phase.LADDER)
