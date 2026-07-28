extends TestCase

## MatchResolver — the heart of the game. Dossier §6.
##
## The load-bearing assertion in this file is
## `test_the_intended_line_beats_straight_aggression`: the dossier is explicit
## that "stamina attrition is the game's real combat system" and that the
## intended line is defend round 1 to burn the opponent's Stamina, then
## Breathe-and-relax + attack in rounds 2 and 3. If straight aggression ever
## beats that line against an even opponent, the tuning is wrong.
##
## Care is a separate agent's system, so every test here injects a FakeCare
## double: these tests must not go red because obedience is still a stub, and
## they must not depend on anybody else's friendship curve.


## Test double for the one Care method MatchResolver uses.
class FakeCare extends Care:
	var obey_result: bool = true
	var obey_calls: int = 0

	func _init(p_rules: GameRules, p_rng: MpRng) -> void:
		super(p_rules, p_rng)

	func obedience_chance(_monkey: Monkey) -> float:
		return 1.0 if obey_result else 0.0

	func obeys(_monkey: Monkey) -> bool:
		obey_calls += 1
		return obey_result


var rules: GameRules
var care: FakeCare


func before_each() -> void:
	rules = GameRules.new()


# --- fixtures ----------------------------------------------------------------

func _monkey(p_name: String, power: int, speed: int, knowledge: int,
		strength: int, stamina: int) -> Monkey:
	var caps := {
		Monkey.Stat.POWER: power,
		Monkey.Stat.SPEED: speed,
		Monkey.Stat.KNOWLEDGE: knowledge,
		Monkey.Stat.STRENGTH: strength,
		Monkey.Stat.STAMINA: stamina,
	}
	var m := Monkey.create(p_name, Species.Type.SUNBURST, caps)
	for stat in Monkey.STATS:
		m.add_stat(stat, int(caps[stat]))
	m.friendship = Monkey.FRIENDSHIP_MAX
	m.restore_pools()
	return m


## Freddy's observed starter tuple (dossier §3 [U]) — the "even opponent".
func _even(p_name: String) -> Monkey:
	return _monkey(p_name, 145, 119, 116, 145, 145)


## Feather-fisted pair: no KO is possible, so every match goes the distance.
func _pillow(p_name: String) -> Monkey:
	return _monkey(p_name, 4, 100, 100, 400, 200)


func _resolver(seed_value: int) -> MatchResolver:
	var rng := MpRng.new(seed_value)
	care = FakeCare.new(rules, rng)
	return MatchResolver.new(rules, rng, care)


func _begin(seed_value: int, a: Monkey = null, b: Monkey = null) -> MatchResolver:
	var r := _resolver(seed_value)
	r.begin(a if a != null else _even("FREDDY"), b if b != null else _even("AGATHA"), 3)
	return r


## Play a whole match with one strategy per round and one corner action per
## break (pass -1 for no corner action).
func _play(seed_value: int, per_round: Array, corner: int,
		a: Monkey = null, b: Monkey = null) -> MatchResolver.MatchResult:
	var r := _begin(seed_value, a, b)
	for i in range(per_round.size()):
		if r.is_finished():
			break
		if i > 0 and corner >= 0:
			r.apply_corner_action(corner)
		r.set_strategy(per_round[i])
		r.simulate_round()
	return r.result()


func _win_rate(per_round: Array, corner: int, samples: int) -> float:
	var wins := 0
	for i in range(samples):
		var res := _play(1000 + i * 7, per_round, corner)
		if res.player_won:
			wins += 1
	return float(wins) / float(samples)


func _count_events(res: MatchResolver.MatchResult, kind: int) -> int:
	var total := 0
	for round_result in res.rounds:
		for e in round_result.events:
			if e.kind == kind:
				total += 1
	return total


# --- the contract ------------------------------------------------------------

func test_labels_keep_the_originals_mistranslation() -> void:
	# Dossier §6 [C] / §10 [C]: "BEAT IT UP!" means DEFEND. That is part of the
	# game's character, not a bug to fix.
	assert_eq(MatchResolver.strategy_label(MatchResolver.Strategy.DEFEND), "BEAT IT UP!")
	assert_eq(MatchResolver.strategy_label(MatchResolver.Strategy.ATTACK), "HIT IT! HIT IT!")
	assert_eq(MatchResolver.strategy_label(MatchResolver.Strategy.EVADE), "KEEP MOVING")
	assert_eq(MatchResolver.strategy_label(MatchResolver.Strategy.BALANCED), "KEEP YOUR BALANCE")
	assert_eq(MatchResolver.corner_label(MatchResolver.CornerAction.BREATHE), "BREATHE AND RELAX")
	assert_eq(MatchResolver.corner_label(MatchResolver.CornerAction.WATER), "WIPE IT WITH WATER")


func test_a_match_is_three_rounds_and_two_intermissions() -> void:
	var r := _begin(11, _pillow("FREDDY"), _pillow("AGATHA"))
	var intermissions: Array[int] = []
	r.intermission_started.connect(func(idx: int) -> void: intermissions.append(idx))
	var res := r.simulate_match(MatchResolver.Strategy.BALANCED)
	assert_eq(res.rounds.size(), MatchResolver.ROUNDS, "3 rounds (dossier §6 [C])")
	assert_eq(intermissions.size(), 2, "2 intermissions")
	assert_eq(intermissions, [2, 3] as Array[int],
		"the intermission index is the round it leads into")
	assert_true(r.is_finished())


func test_purse_and_rank_delta_are_left_for_the_ladder() -> void:
	# The resolver is never told the PLAYER's rank, so it cannot size a purse or
	# a rank move. GameState.finish_match() fills these in.
	var res := _play(3, [MatchResolver.Strategy.BALANCED], -1)
	assert_eq(res.opponent_rank, 3)
	assert_eq(res.purse, 0)
	assert_eq(res.rank_delta, 0)


# --- stamina attrition: the point of the whole system ------------------------

func test_the_intended_line_beats_straight_aggression() -> void:
	# Dossier §6 [C]: "Round 1 defend to burn the opponent's Stamina → round 2
	# 'Breathe and relax' + attack → round 3 'Breathe and relax' + attack.
	# Straight aggression from round 1 is reserved for clearly weaker opponents.
	# Stamina attrition is the game's real combat system."
	var samples := 160
	var intended := _win_rate([
		MatchResolver.Strategy.DEFEND,
		MatchResolver.Strategy.ATTACK,
		MatchResolver.Strategy.ATTACK,
	], MatchResolver.CornerAction.BREATHE, samples)
	# Same corner action, so only the strategy line differs.
	var aggression := _win_rate([
		MatchResolver.Strategy.ATTACK,
		MatchResolver.Strategy.ATTACK,
		MatchResolver.Strategy.ATTACK,
	], MatchResolver.CornerAction.BREATHE, samples)

	assert_true(intended > 0.5,
		"the intended line must be a winning line against an even opponent (got %.2f)" % intended)
	assert_true(intended > aggression + 0.10,
		"defend-then-attack must clearly beat straight aggression (%.2f vs %.2f)"
			% [intended, aggression])


func test_the_intended_line_also_beats_turtling() -> void:
	# The counterweight to the test above: if blocking were free, "defend every
	# round" would be the answer and the game would have no shape.
	var samples := 120
	var intended := _win_rate([
		MatchResolver.Strategy.DEFEND,
		MatchResolver.Strategy.ATTACK,
		MatchResolver.Strategy.ATTACK,
	], MatchResolver.CornerAction.BREATHE, samples)
	var turtle := _win_rate([
		MatchResolver.Strategy.DEFEND,
		MatchResolver.Strategy.DEFEND,
		MatchResolver.Strategy.DEFEND,
	], MatchResolver.CornerAction.BREATHE, samples)
	assert_true(intended > turtle,
		"defending forever must not out-perform the intended line (%.2f vs %.2f)"
			% [intended, turtle])


func test_a_generation_two_monkey_walks_through_a_starter() -> void:
	# The sawtooth curve in dossier §7/§8 only works if raised caps actually cash
	# out in the ring: "the child defeats the strong enemy the parent could not".
	var gen2 := _monkey("FREDDY II", 447, 405, 417, 445, 449)
	var wins := 0
	for i in range(60):
		if _play(1300 + i, [MatchResolver.Strategy.BALANCED, MatchResolver.Strategy.BALANCED,
				MatchResolver.Strategy.BALANCED], -1, gen2, _even("AGATHA")).player_won:
			wins += 1
	assert_true(float(wins) / 60.0 > 0.9,
		"a generation-2 monkey must dominate a starter (%d/60)" % wins)


func test_a_starter_is_outclassed_by_a_generation_two_monkey() -> void:
	var gen2 := _monkey("AGATHA II", 447, 405, 417, 445, 449)
	var wins := 0
	for i in range(60):
		if _play(1400 + i, [MatchResolver.Strategy.DEFEND, MatchResolver.Strategy.ATTACK,
				MatchResolver.Strategy.ATTACK], MatchResolver.CornerAction.BREATHE,
				_even("FREDDY"), gen2).player_won:
			wins += 1
	assert_true(float(wins) / 60.0 < 0.2,
		"no strategy should rescue a hopelessly outgunned monkey (%d/60)" % wins)


func test_defending_drains_the_attackers_stamina_badly() -> void:
	# Dossier §6 [C]: DEFEND "drains the attacking opponent's Stamina badly".
	var drained := 0
	var traded := 0
	for i in range(40):
		var blocked := _begin(500 + i)
		blocked.set_strategy(MatchResolver.Strategy.DEFEND)
		blocked.start_round()
		blocked.opponent.acting_strategy = MatchResolver.Strategy.ATTACK
		while not blocked.is_round_over():
			blocked.advance(MatchResolver.EXCHANGE_SECONDS)
		drained += blocked.opponent.monkey.max_stamina() - blocked.opponent.stamina

		var slug := _begin(500 + i)
		slug.set_strategy(MatchResolver.Strategy.ATTACK)
		slug.start_round()
		slug.opponent.acting_strategy = MatchResolver.Strategy.ATTACK
		while not slug.is_round_over():
			slug.advance(MatchResolver.EXCHANGE_SECONDS)
		traded += slug.opponent.monkey.max_stamina() - slug.opponent.stamina

	assert_true(drained > traded,
		"attacking into a guard must cost more stamina than trading (%d vs %d)"
			% [drained, traded])


func test_defending_preserves_strength_and_stamina() -> void:
	var r := _begin(77)
	r.set_strategy(MatchResolver.Strategy.DEFEND)
	r.start_round()
	r.opponent.acting_strategy = MatchResolver.Strategy.ATTACK
	while not r.is_round_over():
		r.advance(MatchResolver.EXCHANGE_SECONDS)
	r.end_round()
	assert_true(r.player.stamina > r.opponent.stamina,
		"blocking is cheap on stamina (dossier §6 [C])")
	assert_true(r.player.strength > int(r.player.monkey.max_strength() * 0.6),
		"blocking preserves Strength")


func test_attacking_burns_more_stamina_than_evading_or_defending() -> void:
	var costs: Array[int] = []
	for strategy in [MatchResolver.Strategy.ATTACK, MatchResolver.Strategy.EVADE,
			MatchResolver.Strategy.DEFEND]:
		var r := _begin(21)
		r.set_strategy(strategy)
		r.start_round()
		r.opponent.acting_strategy = MatchResolver.Strategy.EVADE
		while not r.is_round_over():
			r.advance(MatchResolver.EXCHANGE_SECONDS)
		costs.append(r.player.monkey.max_stamina() - r.player.stamina)
	assert_true(costs[0] > costs[1], "ATTACK must cost more than EVADE (%s)" % str(costs))
	assert_true(costs[1] > costs[2], "EVADE must cost more than DEFEND (%s)" % str(costs))
	assert_true(costs[2] <= 0, "a blocking monkey recovers a little (%s)" % str(costs))


func test_evasion_scales_with_speed() -> void:
	# "Keep moving — circle and jab, scales with Speed. Not fully reliable."
	var quick_dodges := 0
	var slow_dodges := 0
	var quick_hits := 0
	var slow_hits := 0
	for i in range(30):
		for fast in [true, false]:
			var me := _monkey("FREDDY", 145, 500 if fast else 30, 116, 145, 145)
			var r := _begin(900 + i, me, _even("AGATHA"))
			r.set_strategy(MatchResolver.Strategy.EVADE)
			r.start_round()
			r.opponent.acting_strategy = MatchResolver.Strategy.ATTACK
			while not r.is_round_over():
				r.advance(MatchResolver.EXCHANGE_SECONDS)
			var res := r.end_round()
			for e in res.events:
				if e.kind == MatchResolver.EventKind.PUNCH_DODGED and not e.by_player:
					if fast:
						quick_dodges += 1
					else:
						slow_dodges += 1
				elif e.kind == MatchResolver.EventKind.PUNCH_LANDED and not e.by_player:
					if fast:
						quick_hits += 1
					else:
						slow_hits += 1
	assert_true(quick_dodges > slow_dodges,
		"a faster monkey slips more punches (%d vs %d)" % [quick_dodges, slow_dodges])
	assert_true(slow_hits > quick_hits,
		"evasion is imperfect but Speed must still matter (%d vs %d)" % [slow_hits, quick_hits])


func test_knowledge_improves_the_balanced_strategy() -> void:
	# "Keep your balance — mixes all three; the monkey picks per situation, and
	# picks *better* with high Knowledge" (dossier §6 [C]).
	var smart := 0
	var dim := 0
	for i in range(120):
		var clever := _monkey("FREDDY", 145, 119, 800, 145, 145)
		var dull := _monkey("FREDDY", 145, 119, 0, 145, 145)
		if _play(2000 + i * 3, [MatchResolver.Strategy.BALANCED,
				MatchResolver.Strategy.BALANCED, MatchResolver.Strategy.BALANCED],
				-1, clever, _even("AGATHA")).player_won:
			smart += 1
		if _play(2000 + i * 3, [MatchResolver.Strategy.BALANCED,
				MatchResolver.Strategy.BALANCED, MatchResolver.Strategy.BALANCED],
				-1, dull, _even("AGATHA")).player_won:
			dim += 1
	assert_true(smart > dim,
		"high Knowledge must read the fight better (%d wins vs %d)" % [smart, dim])


# --- winning -----------------------------------------------------------------

func test_win_by_ko_when_the_opponents_strength_is_depleted() -> void:
	# Dossier §3 [C]: Strength IS the health bar. Power is damage.
	var glass := _monkey("AGATHA", 10, 10, 10, 4, 145)
	var res := _play(5, [MatchResolver.Strategy.ATTACK], -1, _even("FREDDY"), glass)
	assert_eq(res.outcome, MatchResolver.Outcome.WIN_KO)
	assert_true(res.player_won)
	assert_eq(res.rounds.size(), 1, "a KO ends the match there and then")
	assert_true(_count_events(res, MatchResolver.EventKind.KO) >= 1)


func test_loss_by_ko_is_symmetric() -> void:
	var glass := _monkey("FREDDY", 10, 10, 10, 4, 145)
	var res := _play(5, [MatchResolver.Strategy.EVADE], -1, glass, _even("AGATHA"))
	assert_eq(res.outcome, MatchResolver.Outcome.LOSS_KO)
	assert_false(res.player_won)


func test_a_match_that_goes_the_distance_is_scored_by_the_judges() -> void:
	var res := _play(9, [MatchResolver.Strategy.BALANCED, MatchResolver.Strategy.BALANCED,
		MatchResolver.Strategy.BALANCED], -1, _pillow("FREDDY"), _pillow("AGATHA"))
	assert_true(res.outcome in [MatchResolver.Outcome.WIN_DECISION,
		MatchResolver.Outcome.LOSS_DECISION, MatchResolver.Outcome.DRAW])
	assert_true(res.player_score > 0)
	assert_true(res.opponent_score > 0)
	assert_ne(res.summary, "")


func test_the_judges_weigh_downs_strength_and_stamina() -> void:
	# Dossier §6 [C]: the decision weighs number of downs, remaining Strength and
	# remaining Stamina — nothing else.
	var r := _begin(4)
	r.player.strength = r.player.monkey.max_strength()
	r.player.stamina = r.player.monkey.max_stamina()
	r.opponent.strength = r.opponent.monkey.max_strength()
	r.opponent.stamina = r.opponent.monkey.max_stamina()
	assert_eq(r.judge_decision().outcome, MatchResolver.Outcome.DRAW,
		"identical cards must be a draw")

	r.opponent.strength = int(r.opponent.monkey.max_strength() * 0.4)
	assert_eq(r.judge_decision().outcome, MatchResolver.Outcome.WIN_DECISION,
		"remaining Strength must count")

	r.opponent.strength = r.opponent.monkey.max_strength()
	r.opponent.stamina = int(r.opponent.monkey.max_stamina() * 0.2)
	assert_eq(r.judge_decision().outcome, MatchResolver.Outcome.WIN_DECISION,
		"remaining Stamina must count")

	r.opponent.stamina = r.opponent.monkey.max_stamina()
	r.player.downs = 2
	assert_eq(r.judge_decision().outcome, MatchResolver.Outcome.LOSS_DECISION,
		"downs must count against the fighter who took them")


func test_downs_are_recorded_and_never_exceed_the_limit() -> void:
	var seen_a_down := false
	for i in range(40):
		var res := _play(700 + i, [MatchResolver.Strategy.ATTACK,
			MatchResolver.Strategy.ATTACK, MatchResolver.Strategy.ATTACK], -1)
		for round_result in res.rounds:
			assert_in_range(round_result.player_downs, 0, MatchResolver.KNOCKDOWN_LIMIT)
			assert_in_range(round_result.opponent_downs, 0, MatchResolver.KNOCKDOWN_LIMIT)
			if round_result.player_downs + round_result.opponent_downs > 0:
				seen_a_down = true
	assert_true(seen_a_down, "a slugfest between even monkeys must produce knockdowns")


# --- determinism -------------------------------------------------------------

func test_the_same_seed_replays_identically() -> void:
	var line := [MatchResolver.Strategy.DEFEND, MatchResolver.Strategy.ATTACK,
		MatchResolver.Strategy.BALANCED]
	var a := _play(4242, line, MatchResolver.CornerAction.BREATHE)
	var b := _play(4242, line, MatchResolver.CornerAction.BREATHE)
	assert_eq(a.outcome, b.outcome)
	assert_eq(a.player_score, b.player_score)
	assert_eq(a.opponent_score, b.opponent_score)
	assert_eq(a.rounds.size(), b.rounds.size())
	for i in range(a.rounds.size()):
		assert_eq(a.rounds[i].player_strength, b.rounds[i].player_strength)
		assert_eq(a.rounds[i].opponent_stamina, b.rounds[i].opponent_stamina)
		assert_eq(a.rounds[i].events.size(), b.rounds[i].events.size())
		for j in range(a.rounds[i].events.size()):
			assert_eq(a.rounds[i].events[j].text, b.rounds[i].events[j].text)


func test_different_seeds_produce_different_fights() -> void:
	var line := [MatchResolver.Strategy.BALANCED, MatchResolver.Strategy.BALANCED,
		MatchResolver.Strategy.BALANCED]
	var scores: Dictionary = {}
	for i in range(20):
		scores[_play(31 + i, line, -1).player_score] = true
	assert_true(scores.size() > 1, "the fight must not be seed-independent")


func test_step_size_does_not_change_the_outcome() -> void:
	# The UI steps the clock at frame rate; the fast-forward button steps it in
	# whole exchanges. Both must produce the same fight for a given seed.
	var fine := _begin(808)
	fine.set_strategy(MatchResolver.Strategy.ATTACK)
	fine.start_round()
	while not fine.is_round_over():
		fine.advance(0.5)
	var fine_round := fine.end_round()

	var coarse := _begin(808)
	coarse.set_strategy(MatchResolver.Strategy.ATTACK)
	coarse.start_round()
	while not coarse.is_round_over():
		coarse.advance(MatchResolver.EXCHANGE_SECONDS)
	var coarse_round := coarse.end_round()

	assert_eq(fine_round.player_strength, coarse_round.player_strength)
	assert_eq(fine_round.opponent_strength, coarse_round.opponent_strength)
	assert_eq(fine_round.events.size(), coarse_round.events.size())


# --- obedience (FAITHFUL rule, GameRules.disobedience_enabled) ---------------

func test_a_low_friendship_monkey_ignores_the_strategy() -> void:
	# Dossier §5/§6 [C], requested explicitly by the user. Do not soften.
	var r := _begin(6)
	care.obey_result = false
	r.set_strategy(MatchResolver.Strategy.DEFEND)
	r.start_round()
	assert_false(r.player.obeying)
	assert_ne(r.player.acting_strategy, MatchResolver.Strategy.DEFEND,
		"an ignoring monkey must not execute the order it ignored")
	var res := r.end_round()
	assert_false(res.player_obeyed)
	var disobeyed := 0
	for e in res.events:
		if e.kind == MatchResolver.EventKind.DISOBEYED:
			disobeyed += 1
	assert_eq(disobeyed, 1, "one DISOBEYED event, so the UI can call it out")


func test_obedience_is_rolled_once_per_round() -> void:
	var r := _begin(6, _pillow("FREDDY"), _pillow("AGATHA"))
	r.simulate_match(MatchResolver.Strategy.ATTACK)
	assert_eq(care.obey_calls, MatchResolver.ROUNDS,
		"Care must be consulted once per round and no more")


func test_obedience_is_not_rolled_when_the_rule_is_off() -> void:
	rules.disobedience_enabled = false
	var r := _begin(6, _pillow("FREDDY"), _pillow("AGATHA"))
	care.obey_result = false
	r.simulate_match(MatchResolver.Strategy.ATTACK)
	assert_eq(care.obey_calls, 0)
	assert_true(r.player.obeying)
	assert_eq(r.player.acting_strategy, MatchResolver.Strategy.ATTACK)


func test_a_missing_care_never_crashes_the_ring() -> void:
	var rng := MpRng.new(12)
	var r := MatchResolver.new(rules, rng, null)
	r.begin(_even("FREDDY"), _even("AGATHA"), 2)
	var res := r.simulate_match(MatchResolver.Strategy.BALANCED)
	assert_true(r.is_finished())
	assert_true(res.rounds.size() >= 1)


# --- strategy and the corner -------------------------------------------------

func test_strategy_changes_apply_at_the_next_bell() -> void:
	var r := _begin(15)
	r.set_strategy(MatchResolver.Strategy.DEFEND)
	r.start_round()
	assert_eq(r.player.acting_strategy, MatchResolver.Strategy.DEFEND)
	r.set_strategy(MatchResolver.Strategy.ATTACK)
	assert_eq(r.player.acting_strategy, MatchResolver.Strategy.DEFEND,
		"you cannot re-order the monkey mid-round; the bell locks it in")
	r.advance(MatchResolver.ROUND_SECONDS)
	r.end_round()
	r.start_round()
	assert_eq(r.player.acting_strategy, MatchResolver.Strategy.ATTACK)


func test_corner_actions_restore_the_right_pools() -> void:
	for action in [MatchResolver.CornerAction.BANDAGE, MatchResolver.CornerAction.BREATHE,
			MatchResolver.CornerAction.WATER]:
		var r := _begin(19)
		r.player.strength = 20
		r.player.stamina = 20
		r.apply_corner_action(action)
		match action:
			MatchResolver.CornerAction.BANDAGE:
				assert_true(r.player.strength > 20, "bandage restores Strength")
				assert_eq(r.player.stamina, 20, "bandage does not touch Stamina")
			MatchResolver.CornerAction.BREATHE:
				assert_true(r.player.stamina > 20, "breathe and relax restores Stamina")
				assert_eq(r.player.strength, 20, "breathing does not heal a cut")
			MatchResolver.CornerAction.WATER:
				assert_true(r.player.strength > 20, "water restores some of both")
				assert_true(r.player.stamina > 20, "water restores some of both")


func test_the_corner_action_is_irreversible() -> void:
	# Dossier §6 [C]: one only, and unlike Strategy you cannot change your mind.
	var r := _begin(23)
	r.player.strength = 20
	r.player.stamina = 20
	r.apply_corner_action(MatchResolver.CornerAction.BANDAGE)
	var after_bandage := r.player.strength
	r.apply_corner_action(MatchResolver.CornerAction.BREATHE)
	assert_eq(r.player.stamina, 20, "a second corner action in one break must be refused")
	assert_eq(r.player.strength, after_bandage)


func test_a_corner_action_is_refused_during_a_live_round() -> void:
	var r := _begin(24)
	r.start_round()
	r.player.stamina = 10
	r.apply_corner_action(MatchResolver.CornerAction.BREATHE)
	assert_eq(r.player.stamina, 10, "there is no corner while the round is live")


func test_a_fresh_corner_action_is_available_each_break() -> void:
	var r := _begin(25, _pillow("FREDDY"), _pillow("AGATHA"))
	r.set_strategy(MatchResolver.Strategy.BALANCED)
	r.simulate_round()
	r.player.stamina = 10
	r.apply_corner_action(MatchResolver.CornerAction.BREATHE)
	var after_first := r.player.stamina
	assert_true(after_first > 10)
	r.simulate_round()
	r.player.stamina = 10
	r.apply_corner_action(MatchResolver.CornerAction.BREATHE)
	assert_true(r.player.stamina > 10, "the second intermission gets its own action")


func test_the_item_corner_action_dopes_the_power() -> void:
	var r := _begin(26)
	assert_almost_eq(r.player.power_bonus, 0.0)
	r.apply_corner_action(MatchResolver.CornerAction.ITEM, "monk_max")
	assert_true(r.player.power_bonus > 0.0, "Monk Max is a temporary Power booster (§6 [C])")
	assert_eq(r.last_item_id, "monk_max")


# --- tap encourage (this build's addition) -----------------------------------

func test_taps_are_rate_limited_so_mashing_is_not_a_win_button() -> void:
	var r := _begin(31)
	r.start_round()
	for i in range(50):
		r.register_tap()
	var events := r.advance(0.0)
	var accepted := 0
	for e in r.end_round().events:
		if e.kind == MatchResolver.EventKind.TAP_ENCOURAGE:
			accepted += 1
	assert_eq(accepted, 1, "50 mashes inside one cooldown must count once")
	assert_eq(events.size(), 0, "advance(0) generates nothing")


func test_taps_are_capped_per_round() -> void:
	var r := _begin(32)
	r.start_round()
	for i in range(60):
		r.register_tap()
		r.advance(MatchResolver.TAP_COOLDOWN + 0.01)
		if r.is_round_over():
			break
	var accepted := 0
	for e in r.end_round().events:
		if e.kind == MatchResolver.EventKind.TAP_ENCOURAGE:
			accepted += 1
	assert_in_range(accepted, 1, MatchResolver.TAP_MAX_PER_ROUND)


func test_taps_are_ignored_when_interactivity_is_none() -> void:
	rules.fight_interactivity = GameRules.FightInteractivity.NONE
	var r := _begin(33)
	r.start_round()
	for i in range(10):
		r.register_tap()
		r.advance(MatchResolver.TAP_COOLDOWN + 0.01)
	var accepted := 0
	for e in r.end_round().events:
		if e.kind == MatchResolver.EventKind.TAP_ENCOURAGE:
			accepted += 1
	assert_eq(accepted, 0, "the original is pure spectate; NONE must honour that")


func test_taps_outside_a_live_round_do_nothing() -> void:
	var r := _begin(34)
	r.register_tap()
	assert_eq(r.advance(1.0).size(), 0)
	r.start_round()
	r.register_tap()
	var res := r.end_round()
	var accepted := 0
	for e in res.events:
		if e.kind == MatchResolver.EventKind.TAP_ENCOURAGE:
			accepted += 1
	assert_eq(accepted, 1, "only the in-round tap counts")


# --- the event log -----------------------------------------------------------

func test_the_round_log_is_replayable() -> void:
	var r := _begin(41)
	var streamed: Array = []
	r.event_logged.connect(func(e: MatchResolver.MatchEvent) -> void: streamed.append(e))
	r.set_strategy(MatchResolver.Strategy.ATTACK)
	var res := r.simulate_round()
	assert_true(res.events.size() > 2, "a round must produce commentary")
	assert_eq(res.events[0].kind, MatchResolver.EventKind.ROUND_START)
	assert_eq(res.events[-1].kind, MatchResolver.EventKind.ROUND_END)
	assert_eq(streamed.size(), res.events.size(), "every event is also signalled live")
	for e in res.events:
		assert_eq(e.round_index, 1)
		assert_in_range(e.time_remaining, 0.0, MatchResolver.ROUND_SECONDS)
		assert_ne(e.text, "", "every event carries commentary the HUD can print")


func test_advance_returns_only_the_newly_generated_events() -> void:
	var r := _begin(43)
	r.set_strategy(MatchResolver.Strategy.ATTACK)
	r.start_round()
	var total := 0
	while not r.is_round_over():
		total += r.advance(MatchResolver.EXCHANGE_SECONDS).size()
	var res := r.end_round()
	# +2 for ROUND_START and ROUND_END, which are logged outside advance().
	assert_eq(res.events.size(), total + 2)


func test_advance_before_the_bell_does_nothing() -> void:
	var r := _begin(44)
	assert_eq(r.advance(10.0).size(), 0)
	assert_almost_eq(r.time_remaining, MatchResolver.ROUND_SECONDS)


func test_the_round_clock_counts_down_from_the_round_length() -> void:
	var r := _begin(45)
	r.start_round()
	assert_almost_eq(r.time_remaining, MatchResolver.ROUND_SECONDS)
	r.advance(12.0)
	assert_almost_eq(r.time_remaining, MatchResolver.ROUND_SECONDS - 12.0)
	r.advance(1000.0)
	assert_almost_eq(r.time_remaining, 0.0)
	assert_true(r.is_round_over())


# --- edges -------------------------------------------------------------------

func test_a_monkey_with_no_stats_at_all_does_not_crash() -> void:
	var nobody := _monkey("NOBODY", 0, 0, 0, 0, 0)
	var res := _play(51, [MatchResolver.Strategy.ATTACK, MatchResolver.Strategy.ATTACK,
		MatchResolver.Strategy.ATTACK], -1, nobody, _even("AGATHA"))
	assert_true(res.outcome == MatchResolver.Outcome.LOSS_KO,
		"a monkey with no Strength has no health bar to defend")
	assert_false(res.player_won)


func test_two_empty_monkeys_still_terminate() -> void:
	var res := _play(52, [MatchResolver.Strategy.BALANCED], -1,
		_monkey("A", 0, 0, 0, 0, 0), _monkey("B", 0, 0, 0, 0, 0))
	assert_true(res.rounds.size() >= 1, "the match must resolve rather than hang")


func test_null_monkeys_are_survivable() -> void:
	var r := _resolver(53)
	r.begin(null, null, 1)
	r.simulate_match(MatchResolver.Strategy.ATTACK)
	assert_true(r.is_finished(), "a malformed booking must not hang the ring")


func test_negative_pools_are_clamped_at_zero() -> void:
	var r := _begin(54)
	r.player.strength = -50
	r.player.stamina = -50
	var res := r.judge_decision()
	assert_in_range(res.player_score, 0, 1000)
	r.start_round()
	r.advance(MatchResolver.ROUND_SECONDS)
	assert_true(r.player.strength <= 0)
	assert_true(r.opponent.strength >= 0, "nobody's health bar may go under zero")


func test_simulate_round_after_the_match_is_a_no_op() -> void:
	var r := _begin(55, _pillow("FREDDY"), _pillow("AGATHA"))
	r.simulate_match(MatchResolver.Strategy.BALANCED)
	var before := r.result().player_score
	r.simulate_round()
	r.simulate_round()
	assert_eq(r.result().rounds.size(), MatchResolver.ROUNDS)
	assert_eq(r.result().player_score, before)


func test_end_round_twice_does_not_add_a_phantom_round() -> void:
	var r := _begin(56, _pillow("FREDDY"), _pillow("AGATHA"))
	r.set_strategy(MatchResolver.Strategy.BALANCED)
	r.simulate_round()
	r.end_round()
	r.end_round()
	assert_eq(r.result().rounds.size(), 1)


func test_the_result_is_empty_but_safe_before_the_final_bell() -> void:
	var r := _begin(57)
	var res := r.result()
	assert_not_null(res)
	assert_eq(res.opponent_rank, 3)
	assert_false(res.player_won)
	assert_false(r.is_finished())


func test_the_beating_is_written_back_to_the_monkey() -> void:
	# Care.apply_overnight_recovery() and the "worn out the following day" rule
	# (§6 [C]) both read the live pools, so the resolver must leave them honest.
	var freddy := _even("FREDDY")
	var r := _resolver(58)
	r.begin(freddy, _even("AGATHA"), 3)
	r.simulate_match(MatchResolver.Strategy.ATTACK)
	assert_eq(freddy.current_strength, r.player.strength)
	assert_eq(freddy.current_stamina, r.player.stamina)
	assert_eq(freddy.days_since_match, 0)
	assert_eq(freddy.wins, 0, "the win/loss record belongs to GameState.finish_match()")
	assert_eq(freddy.losses, 0)
