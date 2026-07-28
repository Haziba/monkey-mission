extends TestCase

## Unit tests for core/training.gd — dossier §3 (one activity per stat) and
## §4 (the rhythm minigame, personal records, sparring, shopping).
##
## Everything numeric in Training is a DIVERGENCE against dossier §14.10 ([X] —
## per-session gains and growth curves are undocumented), so these tests pin
## BEHAVIOUR rather than magic numbers wherever they can: caps hard-block,
## failure is two-sided, the shopping list only ever comes back part-filled.

var rules: GameRules
var rng: MpRng
var training: Training


func before_each() -> void:
	rules = GameRules.new()
	rng = MpRng.new(20000324)   # the original's JP release date, as a seed
	training = Training.new(rules, rng)


# --- helpers -----------------------------------------------------------------

func _caps(power: int, speed: int, knowledge: int, strength: int, stamina: int) -> Dictionary:
	return {
		Monkey.Stat.POWER: power,
		Monkey.Stat.SPEED: speed,
		Monkey.Stat.KNOWLEDGE: knowledge,
		Monkey.Stat.STRENGTH: strength,
		Monkey.Stat.STAMINA: stamina,
	}


## Freddy's observed gen-1 cap tuple (dossier §3 [U]).
func _freddy_caps() -> Dictionary:
	return _caps(145, 119, 116, 145, 145)


## A ready-to-train monkey: befriended, comfortably fed, nothing capped.
func _monkey(caps: Dictionary = {}) -> Monkey:
	var use_caps := caps if not caps.is_empty() else _freddy_caps()
	var m := Monkey.create("FREDDY", Species.Type.SUNBURST, use_caps)
	m.friendship = 50
	m.fullness = 15
	return m


func _score(perfect: int, early: int, late: int, reps: int = -1) -> RhythmScore:
	var s := RhythmScore.new()
	s.perfect = perfect
	s.early = early
	s.late = late
	s.reps = reps if reps != -1 else perfect + early + late
	s.duration_s = 30.0
	return s


func _economy() -> Economy:
	var e := Economy.new(rules)
	e.money = 5000
	return e


## Economy is being written by another agent in parallel. When its methods are
## still stubs, the money-moving half of shopping cannot be asserted — so probe
## once and assert the fallback path instead of reporting a false failure.
func _economy_live() -> bool:
	var e := Economy.new(rules)
	e.money = 10
	var spent: bool = e.spend(4)
	return spent and e.money == 6


# --- stat mapping (§3 [C]) ---------------------------------------------------

func test_activity_stat_mapping_matches_the_original() -> void:
	assert_eq(Training.stat_for(Training.Activity.PUNCHBAG), Monkey.Stat.POWER,
		"punchbag trains Power")
	assert_eq(Training.stat_for(Training.Activity.SKIPPING), Monkey.Stat.SPEED,
		"skipping rope trains Speed")
	assert_eq(Training.stat_for(Training.Activity.SIT_UPS), Monkey.Stat.STRENGTH,
		"sit-ups train Strength — which IS the health bar")
	assert_eq(Training.stat_for(Training.Activity.RUNNING), Monkey.Stat.STAMINA,
		"running trains Stamina")
	assert_eq(Training.stat_for(Training.Activity.SHOPPING), Monkey.Stat.KNOWLEDGE,
		"shopping errands train Knowledge")


func test_only_sparring_raises_all_five() -> void:
	for activity in Training.SLICE_ACTIVITIES:
		assert_false(Training.raises_all(activity),
			"%s must raise exactly one stat" % Training.display_name(activity))
	assert_true(Training.raises_all(Training.Activity.SPARRING),
		"sparring raises all five (§4 [C])")


func test_slice_activities_are_the_five_stat_trainers() -> void:
	assert_eq(Training.SLICE_ACTIVITIES.size(), 5)
	assert_not_has(Training.SLICE_ACTIVITIES, Training.Activity.SPARRING,
		"sparring is declared but out of slice scope")
	var seen := {}
	for activity in Training.SLICE_ACTIVITIES:
		seen[Training.stat_for(activity)] = true
	assert_eq(seen.size(), 5, "the five slice activities cover all five stats")


func test_display_names_cover_every_activity() -> void:
	assert_eq(Training.ACTIVITY_LABELS.size(), Training.Activity.size())
	assert_eq(Training.display_name(Training.Activity.SIT_UPS), "SIT-UPS")
	assert_eq(Training.display_name(Training.Activity.SPARRING), "SPARRING")


# --- the rhythm window (§4 [C]) ----------------------------------------------

func test_target_window_is_exposed_with_both_edges() -> void:
	var window := Training.target_window()
	assert_has(window, "beat_interval")
	assert_has(window, "window")
	assert_has(window, "min_interval")
	assert_has(window, "max_interval")
	assert_true(float(window["window"]) > 0.0, "the window must have width")
	assert_true(float(window["min_interval"]) < float(window["beat_interval"]),
		"the fast edge sits below the beat")
	assert_true(float(window["max_interval"]) > float(window["beat_interval"]),
		"the slow edge sits above the beat")


func test_classify_interval_is_two_sided() -> void:
	var window := Training.target_window()
	var beat := float(window["beat_interval"])
	assert_eq(Training.classify_interval(beat), Training.TapVerdict.IN_WINDOW)
	assert_eq(Training.classify_interval(beat * 0.25), Training.TapVerdict.EARLY_CRAMP,
		"tapping too fast cramps the trainer")
	assert_eq(Training.classify_interval(beat * 4.0), Training.TapVerdict.LATE_BORED,
		"tapping too slowly loses the monkey's interest")
	assert_eq(Training.classify_interval(0.0), Training.TapVerdict.EARLY_CRAMP)


# --- rhythm multiplier -------------------------------------------------------

func test_rhythm_multiplier_rewards_a_clean_session() -> void:
	var perfect := Training.rhythm_multiplier(_score(20, 0, 0))
	assert_almost_eq(perfect, Training.RHYTHM_MAX_MULT, 0.0001,
		"an all-perfect session gets the maximum")


func test_rhythm_multiplier_punishes_both_directions() -> void:
	var clean := Training.rhythm_multiplier(_score(20, 0, 0))
	var all_early := Training.rhythm_multiplier(_score(0, 20, 0))
	var all_late := Training.rhythm_multiplier(_score(0, 0, 20))
	assert_true(all_early < clean, "too fast (cramp) must reduce the score")
	assert_true(all_late < clean, "too slow (lost interest) must reduce the score")
	var half_early := Training.rhythm_multiplier(_score(10, 10, 0))
	var half_late := Training.rhythm_multiplier(_score(10, 0, 10))
	assert_true(half_early < clean, "a partly-cramped session is worse than a clean one")
	assert_true(half_late < clean, "a partly-bored session is worse than a clean one")
	assert_almost_eq(half_early, half_late, 0.0001,
		"failure is two-sided and symmetric — neither side is the 'real' failure")


func test_rhythm_multiplier_degrades_monotonically() -> void:
	var last := 999.0
	for bad in [0, 5, 10, 15, 20]:
		var value := Training.rhythm_multiplier(_score(20 - bad, bad, 0))
		assert_true(value <= last, "more early taps must never score higher")
		last = value


func test_rhythm_multiplier_has_a_floor_and_never_goes_negative() -> void:
	var worst := Training.rhythm_multiplier(_score(0, 10, 10))
	assert_true(worst >= Training.RHYTHM_FLOOR, "a shambles still floors, not negatives")
	assert_true(worst > 0.0)


func test_rhythm_multiplier_needs_input() -> void:
	assert_eq(Training.rhythm_multiplier(_score(0, 0, 0, 0)), 0.0,
		"no taps at all is no session — the slice keeps input required")
	assert_eq(Training.rhythm_multiplier(null), 0.0, "a null score must not crash")


func test_rhythm_multiplier_halves_on_a_hunger_interrupt() -> void:
	var whole := _score(20, 0, 0)
	var cut := _score(20, 0, 0)
	cut.interrupted = true
	assert_almost_eq(Training.rhythm_multiplier(cut),
		Training.rhythm_multiplier(whole) * Training.INTERRUPT_MULT, 0.0001,
		"the hunger interrupt costs half the session")


# --- gating (§5 [C]: befriending gates everything; both hunger extremes stop it)

func test_unbefriended_monkey_will_not_train() -> void:
	var m := _monkey()
	m.friendship = Monkey.FRIENDSHIP_TRAIN_MIN - 1
	assert_false(training.can_train(m), "below the friendship floor it refuses")
	m.friendship = Monkey.FRIENDSHIP_TRAIN_MIN
	assert_true(training.can_train(m), "at the floor it will train")


func test_starving_monkey_will_not_train() -> void:
	var m := _monkey()
	m.fullness = Monkey.FULLNESS_STARVING
	assert_false(training.can_train(m), "immobilised by hunger (§5 [C])")


func test_stuffed_monkey_will_not_train_when_overfeeding_paralyses() -> void:
	var m := _monkey()
	m.fullness = Monkey.FULLNESS_STUFFED
	assert_true(rules.overfeeding_paralyses, "the flag is FAITHFUL and stays on")
	assert_false(training.can_train(m),
		"overfeeding immobilises until it digests — NOT 'wastes food'")


func test_stuffed_monkey_may_train_when_the_flag_is_off() -> void:
	rules.overfeeding_paralyses = false
	var m := _monkey()
	m.fullness = Monkey.FULLNESS_STUFFED
	assert_true(training.can_train(m), "the flag must be honoured, not hardcoded")


func test_paralysed_slots_block_training() -> void:
	var m := _monkey()
	m.paralysed_slots = 1
	assert_false(training.can_train(m))
	m.paralysed_slots = 0
	assert_true(training.can_train(m))


func test_null_monkey_is_handled() -> void:
	assert_false(training.can_train(null))
	var result := training.perform(null, Training.Activity.PUNCHBAG, RhythmScore.average(10))
	assert_true(result.blocked)
	assert_eq(result.gain_applied, 0)


func test_blocked_session_gains_nothing_and_explains_itself() -> void:
	var m := _monkey()
	m.friendship = 0
	var result := training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(30))
	assert_true(result.blocked)
	assert_eq(result.gain_applied, 0)
	assert_eq(result.gain_requested, 0)
	assert_eq(m.get_stat(Monkey.Stat.POWER), 0, "a blocked session must not touch the stat")
	assert_ne(result.message, "", "the UI needs a reason to print")


# --- a session ---------------------------------------------------------------

func test_perform_raises_only_the_mapped_stat() -> void:
	var m := _monkey()
	var result := training.perform(m, Training.Activity.SKIPPING, RhythmScore.average(40))
	assert_eq(result.stat, Monkey.Stat.SPEED)
	assert_true(result.gain_applied > 0, "a good session must move the needle")
	assert_eq(m.get_stat(Monkey.Stat.SPEED), result.gain_applied)
	assert_eq(m.get_stat(Monkey.Stat.POWER), 0, "no other stat may move")
	assert_eq(m.get_stat(Monkey.Stat.KNOWLEDGE), 0)
	assert_eq(m.get_stat(Monkey.Stat.STRENGTH), 0)
	assert_eq(m.get_stat(Monkey.Stat.STAMINA), 0)


func test_perform_without_input_gains_nothing() -> void:
	var m := _monkey()
	var result := training.perform(m, Training.Activity.PUNCHBAG, _score(0, 0, 0, 0))
	assert_false(result.blocked, "it is willing — it just was not shown how")
	assert_eq(result.gain_applied, 0)
	assert_eq(m.get_stat(Monkey.Stat.POWER), 0)


func test_perform_with_a_null_score_does_not_crash() -> void:
	var m := _monkey()
	var result := training.perform(m, Training.Activity.PUNCHBAG, null)
	assert_eq(result.gain_applied, 0)


func test_a_sloppy_session_gains_less_than_a_clean_one() -> void:
	var clean := _monkey()
	var sloppy := _monkey()
	var clean_result := training.perform(clean, Training.Activity.PUNCHBAG, _score(30, 0, 0))
	var sloppy_result := training.perform(sloppy, Training.Activity.PUNCHBAG, _score(6, 12, 12))
	assert_true(sloppy_result.gain_applied < clean_result.gain_applied,
		"the minigame has to matter")
	assert_true(sloppy_result.gain_applied >= 0)


# --- caps (§3 [C]: hard, and only breeding lifts them) -----------------------

func test_gain_clamps_hard_at_the_cap() -> void:
	var m := _monkey(_caps(100, 100, 100, 100, 100))
	m.set_stat(Monkey.Stat.POWER, 98)
	var result := training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(50))
	assert_eq(m.get_stat(Monkey.Stat.POWER), 100, "training can never exceed the cap")
	assert_eq(result.gain_applied, 2, "only the headroom lands")
	assert_true(result.gain_requested > result.gain_applied)
	assert_true(result.was_capped, "the UI must be told the cap ate the gain")
	assert_true(result.starred_out, "this is the session that starred the stat")
	assert_true(m.is_capped(Monkey.Stat.POWER))


func test_starring_out_is_reported_once() -> void:
	var m := _monkey(_caps(30, 30, 30, 30, 30))
	m.set_stat(Monkey.Stat.POWER, 29)
	var first := training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(50))
	assert_true(first.starred_out)
	m.fullness = 15
	var second := training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(50))
	assert_false(second.starred_out, "the fanfare fires exactly once")
	assert_true(second.was_capped, "but the stat is still starred")
	assert_eq(second.gain_applied, 0, "a starred stat gains nothing from training")


func test_training_a_capped_stat_is_wasted_but_still_reported() -> void:
	var m := _monkey(_caps(50, 50, 50, 50, 50))
	m.set_stat(Monkey.Stat.STRENGTH, 50)
	var result := training.perform(m, Training.Activity.SIT_UPS, RhythmScore.average(60))
	assert_eq(result.gain_applied, 0)
	assert_true(result.gain_requested > 0, "the formula still asks, so the UI can say 'capped'")
	assert_true(result.was_capped)
	assert_eq(m.get_stat(Monkey.Stat.STRENGTH), 50)


func test_soft_caps_let_training_past_the_ceiling() -> void:
	rules.hard_stat_caps = false
	var m := _monkey(_caps(20, 20, 20, 20, 20))
	m.set_stat(Monkey.Stat.POWER, 20)
	var result := training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(40))
	assert_true(result.gain_applied > 0, "with the flag off the cap must not block")
	assert_true(m.get_stat(Monkey.Stat.POWER) > 20)


func test_a_zero_cap_stat_never_moves() -> void:
	var m := _monkey(_caps(0, 100, 100, 100, 100))
	var result := training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(40))
	assert_eq(result.gain_applied, 0)
	assert_eq(m.get_stat(Monkey.Stat.POWER), 0)
	assert_eq(training.base_gain(m, Training.Activity.PUNCHBAG), 0)


# --- the gain curve ----------------------------------------------------------

func test_base_gain_scales_with_the_monkeys_own_cap() -> void:
	var starter := _monkey(_freddy_caps())
	var late_gen := _monkey(_caps(820, 788, 760, 845, 788))
	late_gen.friendship = starter.friendship
	assert_true(training.base_gain(late_gen, Training.Activity.PUNCHBAG)
			> training.base_gain(starter, Training.Activity.PUNCHBAG),
		"a gen-3 ceiling must climb faster than Freddy's, or the sawtooth curve stalls")


func test_base_gain_tapers_towards_the_cap() -> void:
	var fresh := _monkey()
	var nearly := _monkey()
	nearly.set_stat(Monkey.Stat.POWER, 140)
	assert_true(training.base_gain(nearly, Training.Activity.PUNCHBAG)
			< training.base_gain(fresh, Training.Activity.PUNCHBAG),
		"the last few points come slower")
	assert_true(training.base_gain(nearly, Training.Activity.PUNCHBAG) >= Training.MIN_GAIN,
		"but never drops to nothing")


func test_a_fonder_monkey_concentrates_better() -> void:
	var cool := _monkey()
	cool.friendship = Monkey.FRIENDSHIP_TRAIN_MIN
	var devoted := _monkey()
	devoted.friendship = Monkey.FRIENDSHIP_MAX
	assert_true(training.base_gain(devoted, Training.Activity.PUNCHBAG)
			>= training.base_gain(cool, Training.Activity.PUNCHBAG))


func test_capping_a_stat_takes_a_sane_number_of_sessions() -> void:
	# Guards the tuning: a stat must be cappable inside a slice-length run, but
	# not in two sessions. Dossier §14.10 gives no numbers, so this is a range.
	var m := _monkey()
	var sessions := 0
	while not m.is_capped(Monkey.Stat.POWER) and sessions < 200:
		m.fullness = 15
		training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(50))
		sessions += 1
	assert_true(m.is_capped(Monkey.Stat.POWER), "a stat must actually be cappable")
	assert_in_range(sessions, 5, 40, "sessions to star out one stat")


# --- sparring (§4 [C], out of slice scope but real) --------------------------

func test_sparring_raises_all_five_by_a_smaller_amount() -> void:
	var sparred := _monkey()
	var punched := _monkey()
	var spar_result := training.perform(sparred, Training.Activity.SPARRING,
		RhythmScore.average(40))
	var punch_result := training.perform(punched, Training.Activity.PUNCHBAG,
		RhythmScore.average(40))
	for stat in Monkey.STATS:
		assert_true(sparred.get_stat(stat) > 0, "sparring raises every stat")
	assert_true(sparred.get_stat(Monkey.Stat.POWER) < punched.get_stat(Monkey.Stat.POWER),
		"but by less than a dedicated punchbag session")
	assert_true(spar_result.gain_applied > 0)
	assert_true(punch_result.gain_applied > 0)


# --- personal records (§4 [C]) -----------------------------------------------

func test_personal_best_is_set_and_then_defended() -> void:
	var m := _monkey()
	var first := training.perform(m, Training.Activity.RUNNING, RhythmScore.average(100))
	assert_true(first.new_personal_best, "the first real session is always a record")
	assert_eq(training.personal_best(m, Training.Activity.RUNNING), 100)
	assert_has(first.message, "RECORD")

	m.fullness = 15
	var worse := training.perform(m, Training.Activity.RUNNING, RhythmScore.average(60))
	assert_false(worse.new_personal_best)
	assert_eq(training.personal_best(m, Training.Activity.RUNNING), 100,
		"a weaker session must not lower the record")

	m.fullness = 15
	var better := training.perform(m, Training.Activity.RUNNING, RhythmScore.average(101))
	assert_true(better.new_personal_best)
	assert_eq(training.personal_best(m, Training.Activity.RUNNING), 101)


func test_personal_bests_are_per_activity() -> void:
	var m := _monkey()
	training.perform(m, Training.Activity.RUNNING, RhythmScore.average(80))
	m.fullness = 15
	var skip := training.perform(m, Training.Activity.SKIPPING, RhythmScore.average(20))
	assert_true(skip.new_personal_best, "skipping keeps its own record")
	assert_eq(training.personal_best(m, Training.Activity.RUNNING), 80)
	assert_eq(training.personal_best(m, Training.Activity.SKIPPING), 20)
	assert_eq(training.personal_best(m, Training.Activity.PUNCHBAG), 0,
		"an activity never done has no record")


func test_zero_and_negative_reps_never_become_a_record() -> void:
	var m := _monkey()
	var odd := _score(10, 0, 0, -5)
	var result := training.perform(m, Training.Activity.PUNCHBAG, odd)
	assert_eq(result.reps, 0, "negative reps are clamped away")
	assert_false(result.new_personal_best)
	assert_eq(training.personal_best(m, Training.Activity.PUNCHBAG), 0)


# --- praise, scold, friendship ----------------------------------------------

func test_praise_and_scold_move_friendship() -> void:
	var m := _monkey()
	m.friendship = 50
	var up := training.praise(m)
	assert_eq(up, Care.FRIENDSHIP_PRAISE)
	assert_eq(m.friendship, 50 + Care.FRIENDSHIP_PRAISE)
	var down := training.scold(m)
	assert_eq(down, Care.FRIENDSHIP_SCOLD)
	assert_eq(m.friendship, 50 + Care.FRIENDSHIP_PRAISE + Care.FRIENDSHIP_SCOLD)


func test_friendship_clamps_at_both_ends() -> void:
	var m := _monkey()
	m.friendship = Monkey.FRIENDSHIP_MAX
	assert_eq(training.praise(m), 0, "praise at the ceiling lands nothing")
	assert_eq(m.friendship, Monkey.FRIENDSHIP_MAX)
	m.friendship = 0
	assert_eq(training.scold(m), 0, "friendship never goes negative")
	assert_eq(m.friendship, 0)
	assert_eq(training.praise(null), 0, "a null monkey must not crash")


func test_a_good_session_warms_the_monkey_and_a_bad_one_cools_it() -> void:
	var good := _monkey()
	good.friendship = 50
	var good_result := training.perform(good, Training.Activity.PUNCHBAG, _score(30, 0, 0))
	assert_true(good_result.friendship_delta > 0)
	assert_true(good.friendship > 50)

	var bad := _monkey()
	bad.friendship = 50
	# Enough reps to avoid a personal-best consolation, all of them mistimed.
	var bad_result := training.perform(bad, Training.Activity.PUNCHBAG, _score(1, 15, 15, 0))
	assert_true(bad_result.friendship_delta < 0, "it chatters and loses focus (§4 [C])")
	assert_true(bad.friendship < 50)


# --- hunger and the interrupt (§4 [C]) ---------------------------------------

func test_a_session_costs_fullness() -> void:
	var m := _monkey()
	m.fullness = 15
	var result := training.perform(m, Training.Activity.RUNNING, RhythmScore.average(30))
	assert_eq(result.fullness_cost, Training.TRAINING_FULLNESS_COST)
	assert_eq(m.fullness, 15 - Training.TRAINING_FULLNESS_COST)
	assert_false(result.hunger_interrupt)


func test_running_out_of_food_mid_session_interrupts_it() -> void:
	var m := _monkey()
	m.fullness = Monkey.FULLNESS_STARVING + 1   # one session from empty
	var result := training.perform(m, Training.Activity.RUNNING, RhythmScore.average(30))
	assert_true(result.hunger_interrupt,
		"it sits down and grabs its stomach mid-set (§4 [C])")
	assert_true(m.is_starving())
	assert_has(result.message, "STOMACH")

	var full := _monkey()
	full.fullness = 20
	var whole := training.perform(full, Training.Activity.RUNNING, RhythmScore.average(30))
	assert_true(result.gain_applied < whole.gain_applied,
		"an interrupted session must be worth less")


func test_fullness_cost_never_goes_below_zero() -> void:
	# The lowest fullness a monkey can start a session at is one point above
	# starving — below that it is immobilised and never gets this far.
	var m := _monkey()
	m.fullness = Monkey.FULLNESS_STARVING + 1
	var before := m.fullness
	var result := training.perform(m, Training.Activity.RUNNING, RhythmScore.average(30))
	assert_false(result.blocked)
	assert_true(m.fullness >= 0, "fullness floors at zero")
	assert_true(result.fullness_cost <= before,
		"the reported cost is what was actually burned, never more")


# --- determinism -------------------------------------------------------------

func test_the_same_seed_produces_the_same_run() -> void:
	var first := _run_scripted_session(4242)
	var second := _run_scripted_session(4242)
	var different := _run_scripted_session(99)
	assert_eq(first, second, "a pinned seed must reproduce exactly")
	assert_true(first.size() > 0)
	# The shopping half is the only randomised part; it must actually vary.
	assert_ne(first, different, "a different seed should produce a different trip")


func _run_scripted_session(seed_value: int) -> Array:
	var local_rng := MpRng.new(seed_value)
	var local := Training.new(rules, local_rng)
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, 40)
	var log_lines := []
	for _i in 3:
		m.fullness = 20
		var trained := local.perform(m, Training.Activity.PUNCHBAG, _score(12, 3, 3))
		log_lines.append(trained.gain_applied)
		var plan := local.plan_shopping(m, {}, 3000)
		log_lines.append(str(plan))
	return log_lines


# --- shopping (§4 [C]) -------------------------------------------------------

func test_a_wish_list_only_ever_comes_back_part_filled() -> void:
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, m.get_cap(Monkey.Stat.KNOWLEDGE))   # as smart as it gets
	var plan := training.plan_shopping(m, {"banana": 9, "bread": 9}, 100000)
	var haul: Dictionary = plan["haul"]
	assert_true(int(haul.get("banana", 0)) > 0, "it does bring something back")
	assert_true(int(haul.get("banana", 0)) < 9,
		"'It returns with only part of the list' is confirmed behaviour")
	assert_true(int(haul.get("bread", 0)) < 9)


func test_a_dim_monkey_brings_back_less_than_a_clever_one() -> void:
	var dim := _monkey()
	var clever := _monkey()
	clever.set_stat(Monkey.Stat.KNOWLEDGE, clever.get_cap(Monkey.Stat.KNOWLEDGE))
	var dim_haul: Dictionary = training.plan_shopping(dim, {"banana": 9}, 100000)["haul"]
	var clever_haul: Dictionary = training.plan_shopping(clever, {"banana": 9}, 100000)["haul"]
	assert_true(int(clever_haul.get("banana", 0)) > int(dim_haul.get("banana", 0)),
		"Knowledge is what makes the monkey a competent shopper")


func test_shopping_never_spends_money_it_does_not_have() -> void:
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, m.get_cap(Monkey.Stat.KNOWLEDGE))
	var budget := 250   # two bananas' worth
	var plan := training.plan_shopping(m, {"banana": 9}, budget)
	assert_true(int(plan["cost"]) <= budget, "the wallet is a hard limit")
	assert_eq(int(plan["haul"].get("banana", 0)), 2)


func test_shopping_with_no_money_brings_nothing_home() -> void:
	var m := _monkey()
	var plan := training.plan_shopping(m, {"banana": 9}, 0)
	assert_true(plan["haul"].is_empty())
	assert_eq(int(plan["cost"]), 0)


func test_shopping_ignores_foods_that_do_not_exist() -> void:
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, m.get_cap(Monkey.Stat.KNOWLEDGE))
	var plan := training.plan_shopping(m, {"peanuts": 9, "banana": 9}, 100000)
	assert_not_has(plan["haul"], "peanuts",
		"Peanuts are deliberately not in the slice's shop")
	assert_has(plan["haul"], "banana")


func test_shopping_ignores_zero_and_negative_quantities() -> void:
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, m.get_cap(Monkey.Stat.KNOWLEDGE))
	var plan := training.plan_shopping(m, {"banana": 0, "corn": -4}, 100000)
	assert_true(plan["haul"].is_empty())
	assert_eq(int(plan["cost"]), 0)


func test_free_choice_brings_home_things_that_were_never_asked_for() -> void:
	var m := _monkey()
	var found := {}
	for _i in 30:
		var plan := training.plan_shopping(m, {}, 4000)
		for id in plan["haul"]:
			found[id] = true
	assert_true(found.size() >= 3,
		"free choice is the only route to new food types (§4 [C])")
	assert_not_has(found, "garlic",
		"a Sunburst dislikes garlic and would not choose it")


func test_free_choice_wastes_money_on_junk() -> void:
	var m := _monkey()
	var junk_trips := 0
	for _i in 30:
		var plan := training.plan_shopping(m, {}, 4000)
		if not plan["junk"].is_empty():
			junk_trips += 1
	assert_true(junk_trips > 0, "'the monkey wastes money on junk' is confirmed (§4 [C])")
	assert_true(junk_trips < 30, "but not on every single trip")


func test_a_clever_monkey_wastes_less() -> void:
	var dim := _monkey()
	var clever := _monkey()
	clever.set_stat(Monkey.Stat.KNOWLEDGE, clever.get_cap(Monkey.Stat.KNOWLEDGE))
	var dim_junk := 0
	var clever_junk := 0
	for _i in 60:
		if not training.plan_shopping(dim, {}, 4000)["junk"].is_empty():
			dim_junk += 1
		if not training.plan_shopping(clever, {}, 4000)["junk"].is_empty():
			clever_junk += 1
	assert_true(clever_junk < dim_junk,
		"Knowledge improves what comes home (§3 [C]: it raises the rare-find rate)")


func test_free_choice_keeps_a_reserve() -> void:
	var m := _monkey()
	for _i in 20:
		var plan := training.plan_shopping(m, {}, 1000)
		assert_true(int(plan["cost"]) <= 500,
			"a free-choosing monkey must not empty the wallet in one trip")


# --- shopping through the Economy --------------------------------------------

func test_shopping_raises_knowledge_either_way() -> void:
	var m := _monkey()
	var result := training.go_shopping(m, _economy(), {"banana": 4})
	assert_eq(result.activity, Training.Activity.SHOPPING)
	assert_eq(result.stat, Monkey.Stat.KNOWLEDGE)
	assert_true(result.gain_applied > 0, "Knowledge rises either way (§4 [C])")
	assert_eq(m.get_stat(Monkey.Stat.KNOWLEDGE), result.gain_applied)


func test_shopping_raises_knowledge_even_with_no_economy_at_all() -> void:
	var m := _monkey()
	var result := training.go_shopping(m, null, {})
	assert_true(result.gain_applied > 0)
	assert_true(result.shopping_haul.is_empty())
	assert_eq(result.money_spent, 0)


func test_shopping_costs_fullness_but_less_than_a_workout() -> void:
	var m := _monkey()
	m.fullness = 15
	var result := training.go_shopping(m, _economy(), {"banana": 4})
	assert_eq(result.fullness_cost, Training.SHOPPING_FULLNESS_COST)
	assert_true(Training.SHOPPING_FULLNESS_COST < Training.TRAINING_FULLNESS_COST)
	assert_eq(m.fullness, 15 - Training.SHOPPING_FULLNESS_COST)


func test_an_unbefriended_monkey_will_not_go_shopping() -> void:
	var m := _monkey()
	m.friendship = 0
	var result := training.go_shopping(m, _economy(), {"banana": 4})
	assert_true(result.blocked)
	assert_eq(result.gain_applied, 0)
	assert_eq(result.money_spent, 0)
	assert_eq(m.get_stat(Monkey.Stat.KNOWLEDGE), 0)


func test_a_stuffed_monkey_will_not_go_shopping() -> void:
	var m := _monkey()
	m.fullness = Monkey.FULLNESS_STUFFED
	var result := training.go_shopping(m, _economy(), {})
	assert_true(result.blocked, "paralysis blocks shopping too, not just training")


func test_perform_refuses_to_handle_shopping() -> void:
	var m := _monkey()
	var result := training.perform(m, Training.Activity.SHOPPING, RhythmScore.average(10))
	assert_true(result.blocked, "shopping needs an Economy; it has its own entry point")
	assert_eq(m.get_stat(Monkey.Stat.KNOWLEDGE), 0)


func test_shopping_moves_money_and_stock() -> void:
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, m.get_cap(Monkey.Stat.KNOWLEDGE))
	var economy := _economy()
	var before := economy.money
	var result := training.go_shopping(m, economy, {"banana": 9})
	if _economy_live():
		assert_true(result.money_spent > 0, "the trip cost something")
		assert_eq(economy.money, before - result.money_spent, "and the wallet paid for it")
		assert_true(int(result.shopping_haul.get("banana", 0)) > 0)
		assert_eq(economy.food_count("banana"), int(result.shopping_haul["banana"]),
			"what came home is in the inventory")
	else:
		# Economy is still stubbed by its own agent: spend() refuses, so the
		# monkey comes home empty-handed. Knowledge must still rise.
		assert_eq(result.money_spent, 0)
		assert_true(result.shopping_haul.is_empty())
		assert_true(result.gain_applied > 0)


func test_shopping_sets_a_personal_best_for_items_carried() -> void:
	var m := _monkey()
	m.set_stat(Monkey.Stat.KNOWLEDGE, m.get_cap(Monkey.Stat.KNOWLEDGE))
	if not _economy_live():
		return   # nothing comes home while Economy is a stub
	var result := training.go_shopping(m, _economy(), {"banana": 9})
	assert_true(result.reps > 0, "items carried home are the shopping 'reps'")
	assert_true(result.new_personal_best)
	assert_eq(training.personal_best(m, Training.Activity.SHOPPING), result.reps)


func test_shopping_can_star_out_knowledge() -> void:
	var m := _monkey(_caps(145, 119, 20, 145, 145))
	m.set_stat(Monkey.Stat.KNOWLEDGE, 19)
	var result := training.go_shopping(m, _economy(), {"banana": 2})
	assert_true(m.is_capped(Monkey.Stat.KNOWLEDGE))
	assert_true(result.was_capped)
	assert_true(result.starred_out)


# --- signals -----------------------------------------------------------------

func test_session_finished_fires_for_training_and_shopping() -> void:
	var seen: Array[Training.Result] = []
	training.session_finished.connect(func(result: Training.Result) -> void:
		seen.append(result))
	var m := _monkey()
	training.perform(m, Training.Activity.PUNCHBAG, RhythmScore.average(20))
	training.go_shopping(m, _economy(), {})
	assert_eq(seen.size(), 2, "the UI listens on this signal")
	assert_eq(seen[0].activity, Training.Activity.PUNCHBAG)
	assert_eq(seen[1].activity, Training.Activity.SHOPPING)
