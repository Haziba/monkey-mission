extends TestCase

## THE MISSING NET. Added by the verification pass.
##
## `test_ladder.gd` proves the ladder's opponents have bigger STAT TOTALS as you
## climb, and `test_integration.gd` proves a rank moves when a MatchResult is
## handed to it — but every one of those results is FABRICATED. Before this file
## nothing in the suite ever fought a real `MatchResolver` match against a real
## `Ladder` opponent, so the single most important claim in the whole brief —
## "a short ladder, rank 5 down to rank 1, that breeding is the only way to
## finish" — was unpinned. Stat totals could have been perfectly ordered while
## the fight maths made every rung unwinnable, or every rung a walkover, and the
## suite would still have gone green.
##
## Measured with 60 seeded matches per cell (see WIN RATES below), taking the
## dossier's intended line (§6 [C]: defend round 1 to burn the opponent's
## stamina, then attack) with BREATHE at both corners:
##
##     maxed gen 1   rank 5 0.90   rank 4 0.55   rank 3 0.33   rank 1 0.04
##     bred  gen 2   rank 5 0.96   rank 4 0.78   rank 3 0.54   rank 1 0.34
##
## which is exactly the sawtooth Ladder's own header promises: the starter takes
## the bottom rung, stalls at rank 4, and cannot reach the top (§8 [C], "your
## starter will unfortunately never be rank 1") until a new generation is bred.
##
## The thresholds below are deliberately loose — they pin the SHAPE, not the
## tuning, so retuning a damage coefficient does not fail this file unless it
## actually breaks the climb.

const SEED := 20000324
## Enough for the differences below to clear the noise, few enough to stay fast.
const SAMPLES := 60


func _rules() -> GameRules:
	return GameRules.new()


## One real match: real opponent from the real Ladder, real MatchResolver, the
## dossier's intended line.
func _fight(player: Monkey, rank: int, seed_value: int) -> bool:
	var rng := MpRng.new(seed_value)
	var rules := _rules()
	var ladder := Ladder.new(rules, rng)
	# Stand one rung below the opponent so it reads as the promotion candidate.
	ladder.rank = mini(rank + 1, Ladder.BOTTOM_RANK)
	var opponent := ladder.generate_opponent(rank, player)

	var fighter := Monkey.from_dict(player.to_dict())
	fighter.restore_pools()

	var resolver := MatchResolver.new(rules, rng, Care.new(rules, rng))
	resolver.begin(fighter, opponent.monkey, rank)
	var line := [MatchResolver.Strategy.DEFEND,
		MatchResolver.Strategy.ATTACK, MatchResolver.Strategy.ATTACK]
	for round_index in MatchResolver.ROUNDS:
		resolver.set_strategy(line[round_index])
		resolver.start_round()
		resolver.simulate_round()
		if resolver.is_finished():
			break
		if round_index < MatchResolver.ROUNDS - 1:
			resolver.apply_corner_action(MatchResolver.CornerAction.BREATHE)
	var result := resolver.result()
	return result != null and result.player_won


func _win_rate(player: Monkey, rank: int, seed_base: int) -> float:
	var wins := 0
	for i in SAMPLES:
		if _fight(player, rank, seed_base + i * 7919):
			wins += 1
	return float(wins) / float(SAMPLES)


func _maxed(source: Monkey) -> Monkey:
	var m := Monkey.from_dict(source.to_dict())
	for stat in Monkey.STATS:
		m.set_stat(stat, m.get_cap(stat))
	m.friendship = Monkey.FRIENDSHIP_MAX
	m.fullness = Care.FULLNESS_CONTENT_MAX
	m.restore_pools()
	return m


## Every generation-2 monkey the dating shop can actually produce from a maxed
## starter, each raised to its new ceilings.
##
## All of them, not one: partner quality varies a lot (`Breeding` deliberately
## does not guarantee an improvement on every stat), so picking a single partner
## measures that partner rather than the mechanic. Averaging the shop is the
## claim that matters — whoever you pair with, you come out ahead.
func _generation_two_shop() -> Array[Monkey]:
	var rules := _rules()
	var parent := _maxed(RunState.make_starter())
	var partners := Breeding.new(rules, MpRng.new(SEED)).partners_for(parent, 10)
	assert_false(partners.is_empty(), "the dating shop must have somebody in it")
	var babies: Array[Monkey] = []
	for partner in partners:
		var economy := Economy.new(rules)
		economy.earn(999999)
		var result := Breeding.new(rules, MpRng.new(SEED)).breed(
			Monkey.from_dict(parent.to_dict()), partner, "Agatha", economy)
		assert_not_null(result, "breeding must return a result")
		assert_not_null(result.baby, "breeding must produce a baby")
		assert_eq(result.baby.generation, 2)
		babies.append(_maxed(result.baby))
	return babies


## Mean win rate at `rank` across the whole shop.
func _shop_win_rate(babies: Array[Monkey], rank: int, seed_base: int) -> float:
	var total := 0.0
	for baby in babies:
		total += _win_rate(baby, rank, seed_base)
	return total / float(babies.size())


# --- the climb ---------------------------------------------------------------

func test_a_maxed_starter_actually_beats_the_bottom_rung() -> void:
	# Not "has more stat points than" — actually wins the fight, most of the
	# time, playing the line the dossier describes.
	var rate := _win_rate(_maxed(RunState.make_starter()), Ladder.BOTTOM_RANK, 1000)
	assert_true(rate >= 0.6,
		"a trained starter must be able to climb off the bottom rung (won %.2f)" % rate)


func test_a_maxed_starter_cannot_take_the_championship() -> void:
	# Dossier §8 [C]: "your starter will unfortunately never be rank 1." If this
	# ever passes comfortably the breeding system has no reason to exist.
	var rate := _win_rate(_maxed(RunState.make_starter()), Ladder.TOP_RANK, 2000)
	assert_true(rate <= 0.25,
		"rank 1 must be out of a generation-1 monkey's reach (won %.2f)" % rate)


func test_the_ladder_gets_harder_the_higher_you_climb() -> void:
	var player := _maxed(RunState.make_starter())
	var bottom := _win_rate(player, Ladder.BOTTOM_RANK, 3000)
	var middle := _win_rate(player, 3, 3000)
	var top := _win_rate(player, Ladder.TOP_RANK, 3000)
	assert_true(bottom > middle,
		"rank 3 must be harder than rank 5 (%.2f vs %.2f)" % [middle, bottom])
	assert_true(middle > top,
		"rank 1 must be harder than rank 3 (%.2f vs %.2f)" % [top, middle])


func test_breeding_is_what_breaks_the_wall() -> void:
	# The whole point of generation 2 (§7 phase 3 [C]). Measured: parent 0.35 at
	# rank 3, the shop's babies 0.42 - 0.62, mean 0.52.
	var starter := _maxed(RunState.make_starter())
	var babies := _generation_two_shop()
	var parent_rate := _win_rate(starter, 3, 4000)
	var child_rate := _shop_win_rate(babies, 3, 4000)
	assert_true(child_rate > parent_rate + 0.05,
		"generation 2 must beat the wall its parent stalled on (%.2f vs %.2f)"
			% [child_rate, parent_rate])


func test_generation_two_gets_within_reach_of_the_crown() -> void:
	# Measured: parent 0.12 at rank 1, the shop's babies 0.18 - 0.45, mean 0.27.
	# Note the ladder rubber-bands (Ladder.PLAYER_MATCH_WEIGHT), so a generation
	# is worth less than its raw stat jump suggests — this pins that the
	# rubber-banding does not cancel breeding out altogether.
	var starter := _maxed(RunState.make_starter())
	var babies := _generation_two_shop()
	var parent_rate := _win_rate(starter, Ladder.TOP_RANK, 5000)
	var child_rate := _shop_win_rate(babies, Ladder.TOP_RANK, 5000)
	assert_true(child_rate > parent_rate + 0.05,
		"a bred monkey must have a real shot at the crown its parent did not (%.2f vs %.2f)"
			% [child_rate, parent_rate])
