extends TestCase

## core/ship_combat.gd — ship-vs-ship, real-time-with-pause. MISSION-ARCHITECTURE
## §10, plus §4 (station XP), §5 (every derived curve lives on `Ship`), §12/§13.
##
## `ShipCombat` is a deliberate structural clone of `MatchResolver`, so this file
## is a deliberate structural clone of `tests/unit/test_match_resolver.gd`: the
## same `advance()` contract, the same determinism-under-a-seed tests, the same
## obedience-per-order tests. Where the two could disagree, the boxing sim is the
## precedent, because 46 green tests already depend on that shape.
##
## THE FIVE THINGS THIS FILE EXISTS TO PROTECT
##
##  1. **A watched fight and a fast-forwarded fight are THE SAME FIGHT.** The tick
##     accumulator is all that stands between "stepped at frame rate by the HUD"
##     and "resolved in one call by the skip button or a test". If it drifts, the
##     player and the simulation see different battles and no bug report is ever
##     reproducible again. `test_many_small_advances_are_the_same_fight_as_one_big_one`
##     is the single most valuable test in the file.
##  2. **Orders cost an obedience roll ONCE, when they are given.** Rolling per
##     tick would turn `disobedience_enabled` into a slot machine and would tie a
##     replay to how long the player left an order standing.
##  3. **Getting shot NEVER kills a monkey.** `Crew.kill()` is the only door out
##     (the DIVERGENCE note on `crew.gd`), and permadeath is the most expensive
##     thing in the game. A stray fire quietly ending a bloodline would be
##     unforgivable, so it is pinned from three directions.
##  4. **Reading the fight has no side effects.** The HUD calls `result()` every
##     frame. Only `apply_rewards()` may touch the purse or the stores.
##  5. **`ShipCombat` invents no curves.** Evasion, damage, charge rates and
##     shield capacity all come from `Ship`, fed by `Crew.station_performance()`.
##     So everything below pins *sequencing* and *invariants*, never the
##     coefficients — those belong to `tests/unit/test_ship.gd`.
##
## Fights are built from hand-allocated ships and hand-built crews rather than
## from `Ship.make_starter()`, because every interesting invariant is about a
## specific power layout. Player monkeys that need to work are given
## `Monkey.FRIENDSHIP_MAX`: `RunState.make_starter()` monkeys begin UNBEFRIENDED,
## every station then reads as unmanned, and a test that forgot would be quietly
## examining an inert ship.

## Pinned seeds. Every random outcome below is aggregated over all of them.
## `MpRng.new(0)` is never used anywhere in this file — it seeds from the wall
## clock and would make the suite flaky.
const SEEDS: Array[int] = [11, 1337, 4242, 20250728, 99991, 424242, 65537]

## A stat that reads as a fully-trained specialist: `Crew.PERFORMANCE_MAX` (3.0)
## is reached at 3 * `Crew.REFERENCE_STAT`, so 450 is "as good as a monkey gets".
const ACE_STAT := 450
## Everything the specialist is not good at. Non-zero so its Strength pool — the
## health bar, dossier §3 [C] — is not already empty when the fight starts.
const DUD_STAT := 50


## Test double for the one `Care` method `ShipCombat` uses, so obedience can be
## both COUNTED (proving the roll happens once per order and never per tick) and
## FORCED (proving a refusal is handled), without depending on the friendship
## curve. Modelled on `test_match_resolver.gd`'s FakeCare.
class CountingCare extends Care:
	var obey_calls: int = 0
	## When true every order is refused, whatever the monkey's friendship is.
	var force_refusal: bool = false

	func _init(p_rules: GameRules, p_rng: MpRng) -> void:
		super(p_rules, p_rng)

	func obeys(monkey: Monkey) -> bool:
		obey_calls += 1
		if force_refusal:
			return false
		return super(monkey)


var rules: GameRules
var rng: MpRng
var care: CountingCare


func before_each() -> void:
	# A fresh GameRules per test: `disobedience_enabled` gets flipped below and
	# `GameRules.load_default()` hands back one shared cached resource.
	rules = GameRules.new()


# --- fixtures ----------------------------------------------------------------
#
# `_combat()` must be called before any crew helper: the crews share its `MpRng`
# and its `Care`, which is what lets one seed replay a whole fight.

func _combat(seed_value: int) -> ShipCombat:
	rng = MpRng.new(seed_value)
	care = CountingCare.new(rules, rng)
	return ShipCombat.new(rules, rng, care)


## A ship with exactly the power layout asked for and nothing else, so a test
## talks about the hardware it means rather than whatever `make_starter` happened
## to allocate.
func _ship(bars: Dictionary, hull: int = Ship.HULL_MAX) -> Ship:
	var ship := Ship.new()
	ship.reactor = Ship.REACTOR_MAX
	ship.hull_max = maxi(1, hull)
	ship.hull = ship.hull_max
	for station in Ship.STATIONS:
		var want := int(bars.get(station, 0))
		if want > 0:
			ship.allocate(station, want)
	return ship


func _monkey(p_name: String, stat_values: Dictionary,
		friendship: int = Monkey.FRIENDSHIP_MAX) -> Monkey:
	var caps := {}
	for stat in Monkey.STATS:
		caps[stat] = maxi(1, int(stat_values.get(stat, DUD_STAT)))
	var monkey := Monkey.create(p_name, SpeciesDb.default_type(), caps)
	for stat in Monkey.STATS:
		monkey.set_stat(stat, int(caps[stat]))
	monkey.friendship = friendship
	# Care's CONTENT band. BOTH hunger extremes paralyse, and a paralysed monkey
	# reads as an empty seat (`Crew.effective_manning`).
	monkey.fullness = RunState.STARTER_FULLNESS
	monkey.restore_pools()
	return monkey


## A specialist for one station: maxed in that station's keyed stat, ordinary
## everywhere else. `Ship.station_stat` is the only place that mapping lives.
func _ace(station: int, friendship: int = Monkey.FRIENDSHIP_MAX) -> Monkey:
	var stat_values := {}
	for stat in Monkey.STATS:
		stat_values[stat] = DUD_STAT
	stat_values[Ship.station_stat(station)] = ACE_STAT
	return _monkey("ACE %s" % Ship.station_label(station), stat_values, friendship)


func _add_at(crew: Crew, station: int, monkey: Monkey) -> Crew.Member:
	var member := crew.add(monkey)
	crew.assign(member, station)
	return member


func _crew_at(station: int, monkey: Monkey) -> Crew:
	var crew := Crew.new(rules, rng, care)
	_add_at(crew, station, monkey)
	return crew


## A specialist at every one of the five posts.
func _ace_crew(friendship: int = Monkey.FRIENDSHIP_MAX) -> Crew:
	var crew := Crew.new(rules, rng, care)
	for station in Ship.STATIONS:
		_add_at(crew, station, _ace(station, friendship))
	return crew


## Five monkeys with a health bar of 6, so the smallest hit knocks one out. Used
## to pin "damage is never lethal" exactly where it is most likely to break.
func _glass_crew(friendship: int = Monkey.FRIENDSHIP_MAX) -> Crew:
	var crew := Crew.new(rules, rng, care)
	for station in Ship.STATIONS:
		var stat_values := {}
		for stat in Monkey.STATS:
			stat_values[stat] = DUD_STAT
		stat_values[Monkey.Stat.STRENGTH] = 6
		_add_at(crew, station, _monkey(
			"GLASS %s" % Ship.station_label(station), stat_values, friendship))
	return crew


## The player's four starter monkeys, auto-assigned. `befriended` is the switch
## between a crew that works and a crew that ignores you — dossier §5's gate.
func _starter_crew(befriended: bool) -> Crew:
	var crew := Crew.new(rules, rng, care)
	for index in Crew.VOYAGE_START_SIZE:
		var monkey := RunState.make_starter()
		monkey.monkey_name = "%s %d" % [RunState.STARTER_NAME, index + 1]
		if befriended:
			monkey.friendship = Monkey.FRIENDSHIP_MAX
		crew.add(monkey)
	crew.auto_assign()
	return crew


func _war_ship() -> Ship:
	return _ship({
		Ship.Station.WEAPONS: 4,
		Ship.Station.SHIELDS: 2,
		Ship.Station.ENGINES: 2,
		Ship.Station.PILOT: 1,
		Ship.Station.SENSORS: 1,
	})


## A decisive, symmetric engagement: four bars of weapons against two of shields,
## so shots outpace shield regeneration and somebody actually dies. Both sides
## get an ace at every post, so the only asymmetries are the fixed player-first
## tick order and the enemy's willingness to run.
func _brawl(seed_value: int) -> ShipCombat:
	var combat := _combat(seed_value)
	combat.begin(_war_ship(), _ace_crew(), _war_ship(), _ace_crew(), 2)
	return combat


## The player pounding a target that cannot shoot back and cannot die: the enemy
## keeps its engines (so it still jinks) and a hull far too deep to lose, so the
## log records nothing but shots, evades and hull damage. `enemy_pilot` and
## `player_sensors` are the two halves of the evasion contest, isolated.
func _range_practice(seed_value: int, enemy_pilot: bool, player_sensors: bool) -> ShipCombat:
	var combat := _combat(seed_value)
	var player_ship := _ship({
		Ship.Station.WEAPONS: 4,
		Ship.Station.SENSORS: 4 if player_sensors else 0,
	})
	var player_crew := _crew_at(Ship.Station.WEAPONS, _ace(Ship.Station.WEAPONS))
	if player_sensors:
		_add_at(player_crew, Ship.Station.SENSORS, _ace(Ship.Station.SENSORS))
	var enemy_ship := _ship({Ship.Station.ENGINES: 2}, 1000)
	var enemy_crew: Crew = null
	if enemy_pilot:
		enemy_crew = _crew_at(Ship.Station.PILOT, _ace(Ship.Station.PILOT))
	combat.begin(player_ship, player_crew, enemy_ship, enemy_crew)
	return combat


## A sitting duck: no engines (so it never evades), no weapons (so it never
## answers) and whatever shields the caller asks for. Every shot therefore either
## pops a layer or bites hull, with no dice in the way.
func _duck(seed_value: int, enemy_shield_bars: int,
		enemy_hull: int = Ship.HULL_MAX) -> ShipCombat:
	var combat := _combat(seed_value)
	combat.begin(
		_ship({Ship.Station.WEAPONS: 4}),
		_crew_at(Ship.Station.WEAPONS, _ace(Ship.Station.WEAPONS)),
		_ship({Ship.Station.SHIELDS: enemy_shield_bars}, enemy_hull),
		null)
	return combat


## The mirror image: the enemy shoots, the player cannot dodge, block or answer.
func _firing_squad(seed_value: int, player_crew: Crew,
		player_hull: int = 20) -> ShipCombat:
	var combat := _combat(seed_value)
	combat.begin(
		_ship({}, player_hull),
		player_crew,
		_ship({Ship.Station.WEAPONS: 4}),
		_crew_at(Ship.Station.WEAPONS, _ace(Ship.Station.WEAPONS)))
	return combat


# --- readers -----------------------------------------------------------------

## The whole fight as a sequence of event kinds. Two fights from one seed must
## produce identical arrays; that is what "deterministic" means here.
func _kinds(combat: ShipCombat) -> Array[int]:
	var out: Array[int] = []
	for event in combat.events():
		out.append(int(event.kind))
	return out


func _count(combat: ShipCombat, kind: int) -> int:
	return combat.events_of_kind(kind).size()


func _sum_amounts(combat: ShipCombat, kind: int) -> int:
	var total := 0
	for event in combat.events_of_kind(kind):
		total += event.amount
	return total


## Everything about a generated opponent that a replay has to reproduce.
func _enemy_signature(pair: Array) -> String:
	var ship := pair[0] as Ship
	var crew := pair[1] as Crew
	var parts: Array[String] = ["%d/%d/%d" % [ship.hull, ship.hull_max, ship.reactor]]
	for station in Ship.STATIONS:
		parts.append("p%d=%d" % [station, ship.power_in(station)])
	for member in crew.members:
		var stats: Array[String] = []
		for stat in Monkey.STATS:
			stats.append(str(member.monkey.get_stat(stat)))
		parts.append("%s@%d[%s]" % [member.display_name(), member.station, ",".join(stats)])
	return "|".join(parts)


# --- begin() -----------------------------------------------------------------

func test_begin_starts_both_sides_shielded_uncharged_and_unfinished() -> void:
	var combat := _brawl(11)
	for side in [combat.player, combat.enemy]:
		assert_eq(side.shield_layers, side.ship.shield_layers_max(),
			"begin() must raise shields to full — arriving with a flat bubble would give the first shot a free hull hit, which nothing in §10 asks for")
		assert_almost_eq(side.shield_charge, 0.0, 0.0001,
			"no banked shield progress at the bell, or a full shield could spend it the instant a layer popped")
		assert_almost_eq(side.weapon_charge, 0.0, 0.0001,
			"both weapons start cold, so the opening seconds are the same for both sides")
		assert_almost_eq(side.jump_charge, 0.0, 0.0001, "nobody is running away yet")
		assert_false(side.escaping, "neither side is fleeing until something makes it flee")
		assert_eq(side.target, Ship.Station.WEAPONS,
			"both sides open by aiming at the other's weapons")
	assert_true(combat.player.is_player, "the player combatant must know it is the player")
	assert_false(combat.enemy.is_player, "the enemy combatant must not")
	assert_false(combat.is_finished(), "a fight is not over before it starts")
	assert_eq(combat.outcome(), ShipCombat.Outcome.NONE,
		"NONE is the only honest outcome before a shot is fired")
	assert_almost_eq(combat.elapsed, 0.0, 0.0001, "the clock starts at zero")
	assert_eq(combat.events().size(), 1,
		"exactly one event at the bell, so the HUD prints one opening line")
	assert_eq(combat.events()[0].kind, ShipCombat.EventKind.COMBAT_START,
		"and it is COMBAT_START (§10's event list opens with it)")
	assert_eq(combat.sector, 2, "the sector is remembered, because the reward scales on it")


func test_begin_resets_a_finished_fight_for_a_second_engagement() -> void:
	# A voyage fights many battles through one resolver instance in the worst
	# case, and a stale `_finished` would make the second one un-runnable.
	var combat := _brawl(11)
	combat.simulate()
	assert_true(combat.is_finished(), "the first engagement must actually end")
	combat.begin(_war_ship(), _ace_crew(), _war_ship(), _ace_crew(), 1)
	assert_false(combat.is_finished(), "begin() must clear `finished` or the second fight is dead on arrival")
	assert_eq(combat.outcome(), ShipCombat.Outcome.NONE, "and clear the old outcome")
	assert_almost_eq(combat.elapsed, 0.0, 0.0001, "and reset the clock")
	assert_eq(combat.events().size(), 1, "and throw away the previous fight's log")
	assert_eq(combat.result().outcome, ShipCombat.Outcome.NONE,
		"and drop the stale CombatResult, or the salvage screen would pay twice")


# --- the clock ---------------------------------------------------------------

func test_advance_returns_only_the_events_from_that_call() -> void:
	# Identical to MatchResolver.advance's contract, which the HUD's event feed
	# depends on: it appends what it is handed and must never see a duplicate.
	var combat := _brawl(1337)
	var streamed := 0
	while not combat.is_finished():
		streamed += combat.advance(ShipCombat.TICK_SECONDS * 4.0).size()
	# +1 for COMBAT_START, which is logged by begin() rather than by advance().
	assert_eq(combat.events().size(), streamed + 1,
		"every event must be handed out exactly once, or the combat log double-prints")
	assert_true(streamed > 5, "a decisive fight must produce real commentary (got %d)" % streamed)


func test_the_returned_batch_is_a_copy_the_caller_can_keep() -> void:
	var combat := _brawl(4242)
	var batch := combat.advance(8.0)
	var size_when_handed_over := batch.size()
	assert_true(size_when_handed_over > 0, "8 seconds of a decisive fight must produce events")
	combat.advance(20.0)
	assert_eq(batch.size(), size_when_handed_over,
		"a caller holding a batch must never see later events appear inside it — the array is duplicated on the way out")


func test_advance_with_zero_or_negative_delta_does_nothing() -> void:
	var combat := _duck(11, 1)
	var before := combat.events().size()
	for delta in [0.0, -0.25, -1000.0]:
		assert_true(combat.advance(float(delta)).is_empty(),
			"advance(%s) must produce no events — the HUD passes a raw frame delta and a paused or rewound clock must be inert" % str(delta))
	assert_almost_eq(combat.elapsed, 0.0, 0.0001, "and must not move the clock")
	assert_eq(combat.events().size(), before, "and must not log anything")
	assert_eq(combat.enemy.ship.hull, combat.enemy.ship.hull_max, "and must not hurt anybody")


func test_a_partial_tick_does_not_move_the_clock() -> void:
	# The accumulator is what makes a 60fps caller and a fast-forward agree; a
	# sub-tick call must bank time rather than simulate a fraction of a tick.
	var combat := _duck(1337, 0)
	assert_true(combat.advance(0.1).is_empty(), "0.1s is less than a tick, so nothing has happened yet")
	assert_true(combat.advance(0.1).is_empty(), "0.2s is still less than a tick")
	assert_almost_eq(combat.elapsed, 0.0, 0.0001,
		"two thirds of a tick must leave the clock alone, or elapsed drifts with the frame rate")
	combat.advance(0.1)
	assert_almost_eq(combat.elapsed, ShipCombat.TICK_SECONDS, 0.0001,
		"the third call crosses the tick boundary and exactly one tick runs")


func test_advance_after_the_fight_is_over_returns_nothing() -> void:
	var combat := _brawl(99991)
	combat.simulate()
	var events_at_the_end := combat.events().size()
	var clock_at_the_end := combat.elapsed
	for _i in 4:
		assert_true(combat.advance(30.0).is_empty(),
			"a finished fight must be inert — the HUD keeps calling advance() while the salvage screen animates in")
	assert_eq(combat.events().size(), events_at_the_end, "and must not log a thing")
	assert_almost_eq(combat.elapsed, clock_at_the_end, 0.0001, "and must not move the clock")


func test_many_small_advances_are_the_same_fight_as_one_big_one() -> void:
	# THE test in this file. The HUD steps the clock at frame rate; the skip
	# button and every test step it in lumps. Both must be the same battle, or
	# the player and the simulation disagree about what happened.
	#
	# The step is TICK_SECONDS / 4 = 0.0625, exactly representable in binary, so
	# 1200 additions accumulate no float error and the two runs cover exactly the
	# same 75 seconds.
	var step := ShipCombat.TICK_SECONDS / 4.0
	var steps := 1200
	for seed_value in SEEDS:
		var fine := _brawl(seed_value)
		var coarse := _brawl(seed_value)
		for _i in steps:
			fine.advance(step)
		coarse.advance(step * float(steps))
		assert_eq(_kinds(fine), _kinds(coarse),
			"seed %d: 1200 small steps and one big step must produce the same event stream, or the fast-forward button plays a different fight from the one the player would have watched" % seed_value)
		assert_eq(fine.outcome(), coarse.outcome(),
			"seed %d: and the same outcome" % seed_value)
		assert_eq(fine.is_finished(), coarse.is_finished(),
			"seed %d: and finish at the same moment" % seed_value)
		assert_almost_eq(fine.elapsed, coarse.elapsed, 0.0001,
			"seed %d: and agree on the clock" % seed_value)
		assert_eq(fine.player.ship.hull, coarse.player.ship.hull,
			"seed %d: and on the player's hull" % seed_value)
		assert_eq(fine.enemy.ship.hull, coarse.enemy.ship.hull,
			"seed %d: and on the enemy's hull" % seed_value)


# --- simulate and determinism ------------------------------------------------

func test_simulate_always_terminates_with_a_terminal_outcome() -> void:
	for seed_value in SEEDS:
		var combat := _brawl(seed_value)
		var result := combat.simulate()
		assert_true(combat.is_finished(),
			"seed %d: simulate() must always come back finished — a voyage cannot survive a fight that never ends" % seed_value)
		assert_ne(result.outcome, ShipCombat.Outcome.NONE,
			"seed %d: NONE is not a terminal outcome; the salvage screen has nothing to say about it" % seed_value)
		assert_true(result.outcome in [
				ShipCombat.Outcome.PLAYER_WON, ShipCombat.Outcome.PLAYER_DESTROYED,
				ShipCombat.Outcome.PLAYER_ESCAPED, ShipCombat.Outcome.ENEMY_ESCAPED,
				ShipCombat.Outcome.DRAW],
			"seed %d: and it must be one of the five §10 outcomes" % seed_value)
		assert_in_range(result.elapsed, 0.0, ShipCombat.MAX_SECONDS + ShipCombat.TICK_SECONDS,
			"seed %d: the hard stop must hold, or a mutually un-killable pairing hangs the game" % seed_value)
		assert_ne(result.summary, "", "seed %d: every ending needs a line to print" % seed_value)
		assert_eq(result.events[-1].kind, ShipCombat.EventKind.COMBAT_END,
			"seed %d: COMBAT_END must be the last thing in the log" % seed_value)


func test_simulate_after_the_fight_is_a_no_op() -> void:
	var combat := _brawl(424242)
	var first := combat.simulate()
	var events_at_the_end := combat.events().size()
	var second := combat.simulate()
	assert_eq(second.outcome, first.outcome, "re-simulating must not re-decide the fight")
	assert_almost_eq(second.elapsed, first.elapsed, 0.0001, "nor extend it")
	assert_eq(combat.events().size(), events_at_the_end, "nor add to the log")


func test_the_same_seed_replays_the_fight_exactly() -> void:
	# Orders are issued identically in both runs, because `Care.obeys` always
	# draws from the stream: a replay is only identical if the ORDERS match too.
	for seed_value in SEEDS:
		var runs: Array[ShipCombat] = []
		for _i in 2:
			var combat := _brawl(seed_value)
			combat.set_target(Ship.Station.SHIELDS)
			combat.set_power(Ship.Station.SHIELDS, 4)
			combat.simulate()
			runs.append(combat)
		assert_eq(_kinds(runs[0]), _kinds(runs[1]),
			"seed %d: two resolvers with the same seed, ships, crews and orders must log the same kinds in the same order" % seed_value)
		assert_eq(runs[0].outcome(), runs[1].outcome(), "seed %d: and reach the same outcome" % seed_value)
		assert_eq(runs[0].result().scrap_reward, runs[1].result().scrap_reward,
			"seed %d: and pay the same salvage" % seed_value)
		assert_almost_eq(runs[0].elapsed, runs[1].elapsed, 0.0001,
			"seed %d: and take the same time" % seed_value)


func test_different_seeds_produce_different_fights() -> void:
	var signatures := {}
	for seed_value in SEEDS:
		var combat := _brawl(seed_value)
		combat.simulate()
		signatures[str(_kinds(combat))] = true
	assert_true(signatures.size() > 1,
		"the fight must not be seed-independent — %d pinned seeds produced %d distinct event streams" % [SEEDS.size(), signatures.size()])


func test_simulate_until_stops_on_the_predicate() -> void:
	var combat := _duck(11, 1)
	combat.simulate_until(func(c: ShipCombat) -> bool:
		return c.has_event(ShipCombat.EventKind.SHOT_FIRED))
	assert_true(combat.has_event(ShipCombat.EventKind.SHOT_FIRED),
		"simulate_until must run far enough for the predicate to fire")
	assert_false(combat.is_finished(),
		"and must stop there rather than resolving the whole fight — this is the 'advance to the first shot, then give an order' hook")
	assert_eq(_count(combat, ShipCombat.EventKind.SHOT_FIRED), 1,
		"it must break on the first tick where the predicate holds, not one shot later")


# --- shields ------------------------------------------------------------------

func test_a_shot_into_shields_pops_one_layer_and_spares_the_hull() -> void:
	# FTL's rule, and the reason a 2-bar shield is worth having: the layer is
	# spent, the hull is untouched, and nothing else about the ship changes.
	var combat := _duck(11, 2)
	assert_eq(combat.enemy.shield_layers, 1, "two bars is one layer (Ship.SHIELD_BARS_PER_LAYER)")
	combat.simulate_until(func(c: ShipCombat) -> bool:
		return c.has_event(ShipCombat.EventKind.SHOT_FIRED))
	assert_eq(_count(combat, ShipCombat.EventKind.SHIELD_ABSORBED), 1,
		"the shielded ship must log exactly one absorption for one shot")
	assert_eq(combat.enemy.shield_layers, 0,
		"SHIELD_POP_PER_HIT is one — a shot must not strip two layers")
	assert_eq(combat.enemy.ship.hull, combat.enemy.ship.hull_max,
		"and must do NO hull damage while a layer stood, or shields are decoration")
	assert_eq(_count(combat, ShipCombat.EventKind.HULL_DAMAGED), 0,
		"and must not log hull damage either")
	assert_eq(combat.enemy.ship.damage_in(Ship.Station.SHIELDS), 0,
		"an absorbed shot must not knock out systems — that is a hull-hit consequence")


func test_the_shot_after_the_bubble_drops_bites_the_hull() -> void:
	var combat := _duck(11, 2)
	combat.advance(ShipCombat.MAX_SECONDS)
	assert_true(_count(combat, ShipCombat.EventKind.HULL_DAMAGED) > 0,
		"once the layer is gone the shots must land, or a 1-layer shield is invulnerability")
	assert_true(combat.enemy.ship.hull < combat.enemy.ship.hull_max,
		"and the hull must actually fall")


func test_shields_recharge_toward_the_maximum_and_stop_there() -> void:
	var combat := _combat(1337)
	combat.begin(_ship({Ship.Station.SHIELDS: 4}), _ace_crew(), _ship({}), null)
	assert_eq(combat.player.ship.shield_layers_max(), 2, "four bars is two layers")
	combat.player.shield_layers = 0
	var highest := 0
	for _i in 200:
		combat.advance(ShipCombat.TICK_SECONDS)
		assert_in_range(combat.player.shield_layers, highest, combat.player.ship.shield_layers_max(),
			"shields must climb monotonically and never overshoot the layers the hardware can hold")
		highest = combat.player.shield_layers
	assert_eq(combat.player.shield_layers, 2,
		"a maxed shield monkey must get the bubble back to full inside 50 seconds")
	assert_almost_eq(combat.player.shield_charge, 0.0, 0.0001,
		"a full shield must bank no part-charge, or it would spend it the instant a layer popped")
	assert_eq(_count(combat, ShipCombat.EventKind.SHIELD_RECHARGED), 2,
		"one SHIELD_RECHARGED per layer regained, so the HUD can flash the right pip")


func test_unpowered_shields_hold_nothing_and_the_first_hit_bites_hull() -> void:
	var combat := _duck(4242, 0)
	assert_eq(combat.enemy.shield_layers, 0,
		"an unpowered shield system holds no layers — that is the cost of robbing it")
	combat.simulate_until(func(c: ShipCombat) -> bool:
		return c.has_event(ShipCombat.EventKind.SHOT_FIRED))
	assert_eq(_count(combat, ShipCombat.EventKind.SHIELD_ABSORBED), 0,
		"nothing can be absorbed by a system with no power")
	assert_eq(_count(combat, ShipCombat.EventKind.HULL_DAMAGED), 1,
		"so the very first shot must reach the hull")
	assert_true(combat.enemy.ship.hull < combat.enemy.ship.hull_max, "and take a bite out of it")


func test_a_knocked_out_shield_system_does_not_trickle_back() -> void:
	var combat := _combat(20250728)
	var ship := _ship({Ship.Station.SHIELDS: 4})
	ship.damage_system(Ship.Station.SHIELDS, Ship.SYSTEM_BARS_MAX)
	combat.begin(ship, _ace_crew(), _ship({}), null)
	assert_eq(combat.player.shield_layers, 0, "a system knocked flat holds nothing at the bell")
	combat.advance(60.0)
	assert_eq(combat.player.shield_layers, 0,
		"a dead shield system must not trickle back however good the monkey sitting at it is (Ship.shield_recharge_rate returns 0 when offline)")
	assert_eq(_count(combat, ShipCombat.EventKind.SHIELD_RECHARGED), 0,
		"and must log nothing that would tell the player otherwise")


func test_shield_layers_never_exceed_what_the_hardware_can_hold() -> void:
	# SUSPECTED CORE BUG — if this fails, `core/ship_combat.gd` is wrong, not the
	# test. `set_power` already clamps this ("Shields cannot hold more layers than
	# the new allocation supports", ship_combat.gd:502), but the DAMAGE path does
	# not: `_land_hit` and `_burn` both call `Ship.damage_system`, which lowers
	# `shield_layers_max()` without touching the layers already up. A fire in the
	# shields room while the bubble is up (the reachable case: fires burn on for
	# many seconds while shields regenerate) therefore leaves a ship showing a
	# shield layer its hardware cannot support, and `_regenerate_shields` then
	# early-returns forever because layers >= maximum.
	var combat := _combat(11)
	combat.begin(_ship({Ship.Station.SHIELDS: 4}), _ace_crew(), _ship({}), null)
	assert_eq(combat.player.shield_layers, 2, "two layers up, as begin() promises")
	combat.player.ship.damage_system(Ship.Station.SHIELDS, Ship.SYSTEM_BARS_MAX)
	combat.advance(ShipCombat.TICK_SECONDS * 8.0)
	assert_eq(combat.player.ship.shield_layers_max(), 0,
		"the hardware can hold nothing once every bar is knocked out")
	assert_in_range(combat.player.shield_layers, 0, combat.player.ship.shield_layers_max(),
		"a ship must never hold more shield layers than its hardware supports — the damage path needs the same clamp set_power already applies")


# --- evasion and targeting ----------------------------------------------------

func test_a_piloted_ship_evades_far_more_than_an_unpiloted_one() -> void:
	# Statistical, aggregated over all 7 pinned seeds — 21 shots per seed, 147
	# shots per arm, and the two arms fire at identical times because weapon
	# charge takes no dice at all.
	var shots := {}
	var evades := {}
	for piloted in [false, true]:
		shots[piloted] = 0
		evades[piloted] = 0
		for seed_value in SEEDS:
			var combat := _range_practice(seed_value, piloted, false)
			combat.simulate(60.0)
			shots[piloted] = int(shots[piloted]) + _count(combat, ShipCombat.EventKind.SHOT_FIRED)
			evades[piloted] = int(evades[piloted]) + _count(combat, ShipCombat.EventKind.SHOT_EVADED)
	assert_eq(int(shots[true]), int(shots[false]),
		"the defender's pilot must not change how often the attacker fires — evasion is a defensive roll, not a rate change (%d vs %d)" % [int(shots[true]), int(shots[false])])
	assert_true(int(evades[false]) > 0,
		"engine hardware alone must still jink a little, or an unpiloted ship is a coffin (%d of %d shots)" % [int(evades[false]), int(shots[false])])
	assert_true(int(evades[true]) > int(evades[false]) * 2,
		"a maxed pilot must slip dramatically more shots than an empty helm — SPEED is the reflex stat (%d vs %d of %d shots)" % [int(evades[true]), int(evades[false]), int(shots[true])])
	assert_true(int(evades[true]) < int(shots[true]),
		"and evasion must never be certainty (Ship.EVASION_MAX): %d of %d" % [int(evades[true]), int(shots[true])])


func test_sensors_targeting_cancels_the_defenders_evasion() -> void:
	# Same defender (a maxed pilot) in both arms; the only difference is whether
	# the ATTACKER has sensors powered and manned. 147 shots per arm.
	var blind_evades := 0
	var aimed_evades := 0
	for seed_value in SEEDS:
		var blind := _range_practice(seed_value, true, false)
		blind.simulate(60.0)
		blind_evades += _count(blind, ShipCombat.EventKind.SHOT_EVADED)
		var aimed := _range_practice(seed_value, true, true)
		aimed.simulate(60.0)
		aimed_evades += _count(aimed, ShipCombat.EventKind.SHOT_EVADED)
	assert_true(aimed_evades * 2 < blind_evades,
		"a manned sensors station must shave real evasion off the defender — KNOWLEDGE gating the good shot is the heir to the original's special punches (%d evades aimed vs %d blind)" % [aimed_evades, blind_evades])


func test_a_ship_with_no_engines_cannot_evade_at_all() -> void:
	var combat := _duck(65537, 0, 1000)
	combat.simulate(60.0)
	assert_true(_count(combat, ShipCombat.EventKind.SHOT_FIRED) > 0, "shots must have been fired")
	assert_eq(_count(combat, ShipCombat.EventKind.SHOT_EVADED), 0,
		"a pilot cannot dodge with nothing to dodge with — no engines means no evasion at all")
	assert_eq(_count(combat, ShipCombat.EventKind.HULL_DAMAGED),
		_count(combat, ShipCombat.EventKind.SHOT_FIRED),
		"so with no shields either, every single shot must land")


# --- hull, and the ways a fight ends ------------------------------------------

func test_hull_damage_accumulates_until_the_enemy_breaks_apart() -> void:
	var combat := _duck(11, 0, 40)
	var result := combat.simulate()
	assert_eq(result.outcome, ShipCombat.Outcome.PLAYER_WON,
		"killing the enemy must resolve as PLAYER_WON")
	assert_true(combat.has_event(ShipCombat.EventKind.ENEMY_DESTROYED),
		"and log ENEMY_DESTROYED so the HUD can play the explosion")
	assert_true(result.player_won(), "and read as a win")
	assert_true(result.player_survived(), "a winner is by definition alive")
	assert_eq(combat.enemy.ship.hull, 0, "the enemy's hull must be spent, not merely low")
	assert_true(combat.enemy.ship.is_destroyed(), "and the ship must agree it is destroyed")
	assert_eq(_sum_amounts(combat, ShipCombat.EventKind.HULL_DAMAGED), 40,
		"the logged damage must add up to exactly the hull that was lost — the events ARE the accounting, and take_hull_damage reports the clamped amount")
	assert_eq(combat.result().elapsed, combat.elapsed, "the result carries the clock it ended on")


func test_losing_the_hull_ends_the_fight_as_player_destroyed() -> void:
	var combat := _firing_squad(1337, _ace_crew())
	var result := combat.simulate()
	assert_eq(result.outcome, ShipCombat.Outcome.PLAYER_DESTROYED,
		"a player with no shields, no engines and no guns must die — permadeath needs a door")
	assert_true(combat.has_event(ShipCombat.EventKind.PLAYER_DESTROYED),
		"and PLAYER_DESTROYED must be logged, not merely inferred")
	assert_false(result.player_won(), "losing the ship is not winning")
	assert_false(result.player_survived(), "and it is the one outcome that is not survival")
	assert_eq(result.scrap_reward, 0, "a wreck earns nothing")
	assert_eq(result.hull_lost, 20, "and reports every point of hull it lost")


func test_two_unarmed_ships_end_in_a_draw_at_the_time_limit() -> void:
	var combat := _combat(4242)
	combat.begin(_ship({}), null, _ship({}), null)
	var result := combat.simulate()
	assert_eq(result.outcome, ShipCombat.Outcome.DRAW,
		"a mutually un-killable pairing must break off, not hang — MAX_SECONDS exists for exactly this")
	assert_almost_eq(result.elapsed, ShipCombat.MAX_SECONDS, 0.0001,
		"and it must break off at the documented hard stop")
	assert_eq(combat.events().size(), 2,
		"two harmless ships have nothing to say but hello and goodbye")
	assert_eq(result.scrap_reward, 0, "a draw pays nothing")
	assert_true(result.player_survived(), "but the player walks away")


func test_hull_lost_counts_only_the_players_own_damage() -> void:
	var combat := _range_practice(20250728, false, false)
	var result := combat.simulate(60.0)
	assert_true(_sum_amounts(combat, ShipCombat.EventKind.HULL_DAMAGED) > 0,
		"the enemy must have taken a beating for this test to mean anything")
	assert_eq(result.hull_lost, 0,
		"hull_lost is the PLAYER's bill — the repair screen must not charge them for the damage they dealt")


func test_hull_damage_is_attributed_to_the_ship_it_landed_on() -> void:
	# WART, pinned so the HUD can rely on it: `CombatEvent.by_player`'s docstring
	# says "true when the PLAYER caused it", but `_land_hit` logs HULL_DAMAGED
	# with `not side.is_player`, i.e. the ship the damage happened TO. So the
	# player's own successful hits arrive flagged `by_player == false`, while the
	# ENEMY_DESTROYED they cause arrives `true`. Colour the log by this flag
	# expecting "who did it" and every hit you land is painted as the enemy's.
	var combat := _duck(11, 0, 40)
	combat.simulate()
	for event in combat.events_of_kind(ShipCombat.EventKind.SHOT_FIRED):
		assert_true(event.by_player, "the player fired every shot in this fight")
	for event in combat.events_of_kind(ShipCombat.EventKind.HULL_DAMAGED):
		assert_false(event.by_player,
			"HULL_DAMAGED names the ship that TOOK the damage, not the ship that dealt it — the flag's own docstring says otherwise and the HUD must not believe it")
	for event in combat.events_of_kind(ShipCombat.EventKind.ENEMY_DESTROYED):
		assert_true(event.by_player, "but the kill itself is credited to the player")


# --- the crew ----------------------------------------------------------------

func test_being_shot_at_never_kills_a_monkey() -> void:
	# The hardest rule in the file. `Crew.hurt` is deliberately never lethal —
	# zero Strength is out cold, not dead — and only `Crew.kill()` ends a life.
	# A fire that quietly ended a bloodline would be unforgivable.
	var total_hurt := 0
	var knocked_out := 0
	for seed_value in SEEDS:
		var crew := _glass_crew()
		var combat := _firing_squad(seed_value, crew, 60)
		combat.simulate()
		total_hurt += _count(combat, ShipCombat.EventKind.CREW_HURT)
		for member in crew.members:
			assert_true(member.alive,
				"seed %d: %s died from being shot at — nothing in combat may kill a monkey, only Crew.kill() may" % [seed_value, member.display_name()])
			assert_true(member.monkey.current_strength >= 0,
				"seed %d: %s's health bar went negative" % [seed_value, member.display_name()])
			if crew.is_incapacitated(member):
				knocked_out += 1
		assert_false(crew.all_dead(),
			"seed %d: a shot-up crew must never read as wiped out — that is the permadeath trigger" % seed_value)
	assert_true(total_hurt > 0,
		"the sample must actually contain injuries or this test proves nothing (%d CREW_HURT events over %d seeds)" % [total_hurt, SEEDS.size()])
	assert_true(knocked_out > 0,
		"and a 6-Strength crew under fire must actually go down (out cold, still alive): %d knocked out" % knocked_out)


func test_hazards_wear_the_crew_down_without_killing_anybody() -> void:
	# Fires and breaches hurt fractionally per second and accumulate through
	# `_hurt_over_time`; the accumulator is what makes 0.8/second land at all on
	# a 0.25s tick, and it must not become a second, sneakier way to die.
	var burns := 0
	var holes := 0
	for seed_value in SEEDS:
		var crew := _glass_crew()
		var combat := _firing_squad(seed_value, crew, 200)
		combat.simulate()
		burns += _count(combat, ShipCombat.EventKind.FIRE_STARTED)
		holes += _count(combat, ShipCombat.EventKind.BREACH_OPENED)
		for member in crew.members:
			assert_true(member.alive,
				"seed %d: fire and vacuum must not kill %s either" % [seed_value, member.display_name()])
	assert_true(burns > 0, "the sample must contain fires (%d)" % burns)
	assert_true(holes > 0, "and breaches (%d)" % holes)


func test_only_an_explicit_kill_ends_a_life() -> void:
	var combat := _duck(11, 0)
	var crew := _glass_crew()
	combat.player.crew = crew
	var member := crew.manning(Ship.Station.WEAPONS)
	assert_eq(crew.hurt(member, 999), 6, "hurt() applies only what the health bar had left")
	assert_true(member.alive, "and leaves the monkey alive at zero Strength — a KO, not a death")
	assert_true(crew.is_incapacitated(member), "but out cold, so its station reads as empty")
	assert_eq(combat.player.performance(Ship.Station.WEAPONS), 0.0,
		"an unconscious gunner contributes nothing, which is what makes damage matter at all")
	crew.kill(member)
	assert_false(member.alive, "Crew.kill() is the only door out")


# --- orders, and obedience ---------------------------------------------------

func test_an_order_to_an_unmanned_station_is_always_obeyed() -> void:
	# The hardware does as it is told even with the seat empty: there is nobody
	# there to disobey. Every monkey aboard here has friendship 0, so if the
	# order were routed through anyone at all it would usually be refused.
	var combat := _duck(11, 0)
	var crew := Crew.new(rules, rng, care)
	_add_at(crew, Ship.Station.PILOT, _ace(Ship.Station.PILOT, 0))
	combat.player.crew = crew
	assert_null(crew.manning(Ship.Station.SENSORS), "nobody is at the sensors console")
	for _i in 8:
		assert_true(combat.set_power(Ship.Station.SENSORS, 3),
			"an order to an empty station must always land")
	assert_eq(combat.player.ship.power_in(Ship.Station.SENSORS), 3, "and must actually take effect")
	assert_eq(_count(combat, ShipCombat.EventKind.DISOBEYED), 0,
		"and must never log DISOBEYED — there was nobody there to refuse")
	assert_eq(care.obey_calls, 0,
		"and must not even consume an obedience roll, or an empty seat would shift the RNG stream")


func test_a_friendship_zero_monkey_can_refuse_an_order() -> void:
	# FAITHFUL rule, dossier §5/§6 [C], requested explicitly by the user: an
	# insufficiently bonded monkey ignores you. Care.OBEDIENCE_FLOOR is 0.25 at
	# friendship 0, so across 7 seeds x 6 orders most orders should be refused.
	var refused := 0
	var obeyed := 0
	var disobeyed_events := 0
	for seed_value in SEEDS:
		var combat := _duck(seed_value, 0)
		combat.player.crew = _ace_crew(0)
		var before := combat.player.ship.power_in(Ship.Station.SHIELDS)
		for i in 6:
			if combat.set_power(Ship.Station.SHIELDS, 1 + (i % 4)):
				obeyed += 1
			else:
				refused += 1
		disobeyed_events += _count(combat, ShipCombat.EventKind.DISOBEYED)
		if refused > 0 and obeyed == 0:
			assert_eq(combat.player.ship.power_in(Ship.Station.SHIELDS), before,
				"seed %d: a refused order must change nothing at all" % seed_value)
	assert_true(refused > 0,
		"a friendship-0 crew must sometimes ignore you — softening this would break the one rule the user pinned twice (%d refusals of %d orders)" % [refused, refused + obeyed])
	assert_true(obeyed > 0,
		"but a 25%% floor is not zero: an unbefriended crew must not be a brick (%d obeyed)" % obeyed)
	assert_eq(disobeyed_events, refused,
		"every refusal must log exactly one DISOBEYED so the HUD can call it out (%d events for %d refusals)" % [disobeyed_events, refused])
	assert_eq(care.obey_calls, 6,
		"and exactly one roll per order was consumed on the last fight, refused or not")


func test_a_befriended_monkey_never_refuses() -> void:
	var combat := _duck(1337, 0)
	combat.player.crew = _ace_crew()
	for i in 20:
		assert_true(combat.set_power(Ship.Station.SHIELDS, 1 + (i % 4)),
			"a monkey at FRIENDSHIP_MAX is past Monkey.FRIENDSHIP_OBEDIENT and must obey every time")
	assert_eq(_count(combat, ShipCombat.EventKind.DISOBEYED), 0,
		"so nothing may be logged as ignored")
	assert_eq(care.obey_calls, 20, "one roll per order, still — even when it is certain to obey")


func test_disobedience_can_be_switched_off_entirely() -> void:
	rules.disobedience_enabled = false
	var combat := _duck(4242, 0)
	combat.player.crew = _ace_crew(0)
	for i in 12:
		assert_true(combat.set_power(Ship.Station.SHIELDS, 1 + (i % 4)),
			"with the rule off, even a friendship-0 monkey must obey (GameRules.disobedience_enabled)")
	assert_eq(_count(combat, ShipCombat.EventKind.DISOBEYED), 0, "and nothing may be logged")


func test_a_forced_refusal_changes_nothing_but_the_log() -> void:
	var combat := _duck(11, 0)
	combat.player.crew = _ace_crew()
	care.force_refusal = true
	var power_before := combat.player.ship.power_in(Ship.Station.WEAPONS)
	assert_false(combat.set_power(Ship.Station.WEAPONS, 1), "a refused order must report failure")
	assert_eq(combat.player.ship.power_in(Ship.Station.WEAPONS), power_before,
		"and must not move a single bar")
	combat.set_target(Ship.Station.ENGINES)
	assert_eq(combat.player.target, Ship.Station.WEAPONS, "a refused order must not re-aim the gun")
	combat.begin_escape()
	assert_false(combat.player.escaping,
		"and must not start the jump drive — a monkey that will not follow orders will not run either")
	assert_eq(_count(combat, ShipCombat.EventKind.DISOBEYED), 3,
		"one DISOBEYED per refused order: power, target and escape are three separate orders")


func test_no_orders_means_no_obedience_rolls_all_fight() -> void:
	# Obedience is rolled ONCE PER ORDER, never per tick. A whole fight with the
	# player's hands off the console must not produce a single roll, or
	# disobedience_enabled becomes a slot machine and a replay stops depending
	# only on the seed.
	for seed_value in SEEDS:
		var combat := _duck(seed_value, 0, 200)
		combat.player.crew = _ace_crew(0)
		combat.simulate()
		assert_true(combat.elapsed > 20.0,
			"seed %d: the fight must be long enough for a per-tick roll to show up" % seed_value)
		assert_eq(_count(combat, ShipCombat.EventKind.DISOBEYED), 0,
			"seed %d: a friendship-0 crew with no orders to disobey must produce no DISOBEYED events" % seed_value)
		assert_eq(care.obey_calls, 0,
			"seed %d: and Care must not be consulted at all — %d rolls in %.0f seconds means obedience is being rolled per tick" % [seed_value, care.obey_calls, combat.elapsed])


func test_set_power_can_never_overdraw_the_reactor() -> void:
	for seed_value in SEEDS:
		var combat := _brawl(seed_value)
		var ship := combat.player.ship
		# A barrage, including absurd figures and stations that do not exist.
		for station in Ship.STATIONS:
			combat.set_power(station, Ship.SYSTEM_BARS_MAX)
		combat.set_power(Ship.Station.WEAPONS, 999)
		combat.set_power(Ship.Station.SHIELDS, -50)
		combat.set_power(99, 4)
		combat.set_power(-3, 4)
		for station in Ship.STATIONS:
			combat.set_power(station, 4)
		assert_true(ship.power_used() <= ship.reactor,
			"seed %d: the ship must never draw more than its reactor makes (%d of %d)" % [seed_value, ship.power_used(), ship.reactor])
		assert_eq(ship.power_used() + ship.power_free(), ship.reactor,
			"seed %d: and the budget must still balance afterwards" % seed_value)
		for station in Ship.STATIONS:
			assert_in_range(ship.power_in(station), 0, Ship.SYSTEM_BARS_MAX,
				"seed %d: station %d must stay inside its own ceiling" % [seed_value, station])


func test_set_power_refuses_a_station_that_does_not_exist() -> void:
	var combat := _duck(11, 0)
	combat.player.crew = _ace_crew()
	var used_before := combat.player.ship.power_used()
	assert_false(combat.set_power(99, 2), "there is no sixth station (Ship.STATIONS is the whole map)")
	assert_false(combat.set_power(-1, 2), "nor a station below Pilot")
	assert_eq(combat.player.ship.power_used(), used_before, "and neither call may move any power")
	assert_eq(care.obey_calls, 0,
		"a nonsense order must be rejected before it costs an obedience roll")


func test_robbing_the_shields_drops_the_layers_they_can_no_longer_hold() -> void:
	var combat := _combat(1337)
	combat.begin(_ship({Ship.Station.SHIELDS: 4}), _ace_crew(), _ship({}), null)
	assert_eq(combat.player.shield_layers, 2, "two layers up to begin with")
	assert_true(combat.set_power(Ship.Station.SHIELDS, 2), "rob two bars back for something else")
	assert_eq(combat.player.shield_layers, 1,
		"the bubble must shrink to what the new allocation supports — a phantom layer would be a free hull hit")
	assert_true(combat.set_power(Ship.Station.SHIELDS, 0), "rob the rest")
	assert_eq(combat.player.shield_layers, 0, "and the bubble must be gone entirely")
	assert_eq(_count(combat, ShipCombat.EventKind.POWER_REROUTED), 2,
		"each reroute that actually moved a bar must be logged once")


func test_set_target_moves_the_aim_once_and_logs_it() -> void:
	var combat := _duck(4242, 0)
	combat.player.crew = _ace_crew()
	combat.set_target(Ship.Station.ENGINES)
	assert_eq(combat.player.target, Ship.Station.ENGINES, "the gun must follow the order")
	assert_eq(_count(combat, ShipCombat.EventKind.TARGET_CHANGED), 1, "and say so once")
	combat.set_target(Ship.Station.ENGINES)
	assert_eq(_count(combat, ShipCombat.EventKind.TARGET_CHANGED), 1,
		"re-ordering the same target must not spam the log")
	combat.set_target(99)
	assert_eq(combat.player.target, Ship.Station.ENGINES, "and a nonsense station must not move the aim")
	combat.advance(20.0)
	for event in combat.events_of_kind(ShipCombat.EventKind.SHOT_FIRED):
		assert_eq(event.station, Ship.Station.ENGINES,
			"every subsequent shot must be logged against the station the player chose")


func test_order_events_reach_the_log_even_though_advance_never_returns_them() -> void:
	# `advance` returns "only the events this call produced", and an order is not
	# produced by a call to advance. So a HUD that feeds its combat log purely
	# from advance()'s return value will never show POWER_REROUTED or DISOBEYED:
	# it has to use the `event_logged` signal or `events()`. Pinned because it is
	# a real trap, not because it is wrong.
	var combat := _duck(11, 0)
	combat.player.crew = _ace_crew()
	combat.set_power(Ship.Station.SHIELDS, 2)
	assert_eq(_count(combat, ShipCombat.EventKind.POWER_REROUTED), 1,
		"the order must be in the fight's own log")
	var returned := combat.advance(ShipCombat.TICK_SECONDS)
	for event in returned:
		assert_ne(event.kind, ShipCombat.EventKind.POWER_REROUTED,
			"but advance() must not hand back an event it did not produce, or the log double-prints it")


func test_orders_are_refused_once_the_fight_is_over() -> void:
	var combat := _duck(1337, 0, 40)
	combat.player.crew = _ace_crew()
	combat.simulate()
	var events_at_the_end := combat.events().size()
	var target_at_the_end := combat.player.target
	assert_false(combat.set_power(Ship.Station.SHIELDS, 4),
		"there is nothing left to reroute power for")
	combat.set_target(Ship.Station.PILOT)
	assert_eq(combat.player.target, target_at_the_end, "nor anything left to aim at")
	combat.begin_escape()
	assert_false(combat.player.escaping, "nor anywhere left to run to")
	assert_eq(combat.events().size(), events_at_the_end, "and none of it may reach the log")
	assert_eq(care.obey_calls, 0,
		"nor consume an obedience roll after the end — that would shift the stream for the NEXT fight")


# --- running away -------------------------------------------------------------

func test_the_jump_drive_only_charges_while_escaping() -> void:
	var combat := _combat(11)
	combat.begin(_ship({Ship.Station.ENGINES: 4}), null, _ship({}), null)
	combat.advance(20.0)
	assert_almost_eq(combat.player.jump_charge, 0.0, 0.0001,
		"a ship that has not decided to run must bank no jump charge, or every fight would end by accident")
	assert_eq(_count(combat, ShipCombat.EventKind.JUMP_CHARGED), 0, "and log nothing")
	combat.begin_escape()
	assert_true(combat.player.escaping, "begin_escape() is the order that starts the clock")
	combat.advance(ShipCombat.TICK_SECONDS * 4.0)
	assert_true(combat.player.jump_charge > 0.0, "and only then does the drive spin up")
	assert_false(combat.is_finished(), "one second is not a whole jump")


func test_a_full_jump_charge_ends_the_fight_as_player_escaped() -> void:
	var combat := _combat(1337)
	combat.begin(_ship({Ship.Station.ENGINES: 4}), null, _ship({}), null)
	combat.begin_escape()
	var result := combat.simulate()
	assert_eq(result.outcome, ShipCombat.Outcome.PLAYER_ESCAPED,
		"reaching a full charge must end the fight as an escape — this is the escape hatch that makes a losing fight survivable")
	assert_true(combat.has_event(ShipCombat.EventKind.JUMP_CHARGED),
		"and log the moment the drive came ready")
	assert_almost_eq(combat.player.jump_charge, 1.0, 0.0001, "the charge caps at exactly full")
	assert_true(result.player_survived(), "escaping is survival")
	assert_false(result.player_won(), "but it is not a win")
	assert_eq(result.scrap_reward, 0, "and it pays nothing — escaping with your life is its own reward")


func test_a_ship_with_dead_engines_can_never_escape() -> void:
	var combat := _combat(4242)
	combat.begin(_ship({}), null, _ship({}), null)
	combat.begin_escape()
	assert_true(combat.player.escaping, "the order is accepted — the crew tries")
	var result := combat.simulate()
	assert_almost_eq(combat.player.jump_charge, 0.0, 0.0001,
		"but with no engines the drive never charges at all (Ship.jump_charge_rate returns 0 when offline)")
	assert_ne(result.outcome, ShipCombat.Outcome.PLAYER_ESCAPED,
		"so escape must be impossible — losing the engines is what makes a fight a trap")
	assert_eq(result.outcome, ShipCombat.Outcome.DRAW,
		"and with nobody able to hurt anybody the engagement is simply broken off")


func test_a_badly_hurt_enemy_runs_for_it() -> void:
	# Driven there by damaging the enemy hull directly, which is exactly what
	# `_land_hit` does; nobody can shoot in this fight, so the flee decision is
	# the only thing being observed.
	var combat := _combat(20250728)
	combat.begin(_ship({}), null, _ship({Ship.Station.ENGINES: 2}, 100), null)
	combat.advance(2.0)
	assert_false(combat.enemy.escaping, "a healthy enemy has no reason to run")
	combat.enemy.ship.take_hull_damage(80)
	var fraction := float(combat.enemy.ship.hull) / float(combat.enemy.ship.hull_max)
	assert_true(fraction <= ShipCombat.ENEMY_FLEE_HULL_FRACTION,
		"the setup must actually push the enemy under the flee threshold (%.2f)" % fraction)
	var result := combat.simulate()
	assert_true(combat.enemy.escaping, "an enemy this badly hurt must decide to run")
	assert_eq(result.outcome, ShipCombat.Outcome.ENEMY_ESCAPED,
		"and getting away must resolve as ENEMY_ESCAPED, not as a win")
	assert_false(result.player_won(), "a runner denies the player the kill")
	assert_eq(result.scrap_reward, 0, "and the salvage with it")
	assert_true(result.player_survived(), "but the player is fine")


func test_a_healthy_enemy_stands_and_fights() -> void:
	var combat := _combat(99991)
	combat.begin(_ship({}), null, _ship({Ship.Station.ENGINES: 2}, 100), null)
	var result := combat.simulate()
	assert_false(combat.enemy.escaping,
		"an undamaged enemy must never flee, or no fight would ever be winnable")
	assert_eq(result.outcome, ShipCombat.Outcome.DRAW, "so the engagement runs out the clock instead")


# --- salvage -----------------------------------------------------------------

func test_only_a_kill_pays_scrap() -> void:
	var won := _duck(11, 0, 40)
	var win_result := won.simulate()
	assert_eq(win_result.outcome, ShipCombat.Outcome.PLAYER_WON, "the setup must be a win")
	assert_eq(win_result.scrap_reward,
		ShipCombat.SCRAP_REWARD_BASE + ShipCombat.SCRAP_REWARD_PER_SECTOR * 0,
		"a sector-1 kill pays the base rate")
	assert_in_range(win_result.fuel_reward, 0, 3, "fuel is a chance, and a small one")
	assert_in_range(win_result.missiles_reward, 0, 2, "so are missiles")

	for setup in ["loss", "draw", "escape"]:
		var combat: ShipCombat = null
		match setup:
			"loss":
				combat = _firing_squad(1337, _ace_crew())
			"draw":
				combat = _combat(4242)
				combat.begin(_ship({}), null, _ship({}), null)
			_:
				combat = _combat(4242)
				combat.begin(_ship({Ship.Station.ENGINES: 4}), null, _ship({}), null)
				combat.begin_escape()
		var result := combat.simulate()
		assert_eq(result.scrap_reward, 0,
			"%s: only a kill pays scrap (§10) — got %d" % [setup, result.scrap_reward])
		assert_eq(result.fuel_reward, 0, "%s: and nothing else either" % setup)
		assert_eq(result.missiles_reward, 0, "%s: no missiles from a fight you did not win" % setup)


func test_the_scrap_reward_scales_with_the_sector() -> void:
	var shallow := _duck(11, 0, 40)
	shallow.simulate()
	var deep := _combat(11)
	deep.begin(_ship({Ship.Station.WEAPONS: 4}),
		_crew_at(Ship.Station.WEAPONS, _ace(Ship.Station.WEAPONS)),
		_ship({}, 40), null, 4)
	deep.simulate()
	assert_eq(deep.result().outcome, ShipCombat.Outcome.PLAYER_WON, "both fights must be wins")
	assert_true(deep.result().scrap_reward > shallow.result().scrap_reward,
		"deeper sectors must pay better or there is no reason to press on (%d in sector 4 vs %d in sector 1)"
			% [deep.result().scrap_reward, shallow.result().scrap_reward])
	assert_eq(deep.result().scrap_reward,
		ShipCombat.SCRAP_REWARD_BASE + ShipCombat.SCRAP_REWARD_PER_SECTOR * 3,
		"and the scaling must be the documented one, three sectors deep")


func test_apply_rewards_credits_the_purse_and_the_stores() -> void:
	var combat := _duck(1337, 0, 40)
	var ship := combat.player.ship
	var economy := Economy.new(rules)
	var scrap_before := economy.scrap
	var fuel_before := ship.fuel
	var missiles_before := ship.missiles
	var result := combat.simulate()
	assert_eq(economy.scrap, scrap_before,
		"finishing the fight must not touch the purse — apply_rewards() is a separate, deliberate step")
	combat.apply_rewards(economy, ship)
	assert_eq(economy.scrap, scrap_before + result.scrap_reward,
		"apply_rewards must credit exactly the scrap the result promised")
	assert_eq(economy.money, economy.scrap, "and scrap and money must remain one purse (§11)")
	assert_eq(ship.fuel, fuel_before + result.fuel_reward, "and the fuel it promised")
	assert_eq(ship.missiles, missiles_before + result.missiles_reward, "and the missiles")


func test_apply_rewards_is_a_no_op_after_a_loss() -> void:
	var combat := _firing_squad(4242, _ace_crew())
	var economy := Economy.new(rules)
	var scrap_before := economy.scrap
	var fuel_before := combat.player.ship.fuel
	combat.simulate()
	combat.apply_rewards(economy, combat.player.ship)
	assert_eq(economy.scrap, scrap_before, "a wreck must not pay out")
	assert_eq(combat.player.ship.fuel, fuel_before, "nor top up the tank")
	combat.apply_rewards(null, null)
	assert_eq(economy.scrap, scrap_before, "and a null economy or ship must not crash the salvage step")


func test_reading_the_result_has_no_side_effects() -> void:
	# The HUD polls result() every frame. If it consumed RNG, moved the clock or
	# credited anything, the fight would depend on how often it was looked at.
	var combat := _duck(11, 1, 200)
	var economy := Economy.new(rules)
	# Captured, NOT assumed to be zero: a fresh Economy opens with
	# Economy.STARTING_MONEY in it. What matters is that reading the fight moves
	# the purse by nothing, not what the purse happened to start at.
	var scrap_at_rest := economy.scrap
	combat.advance(6.0)
	assert_false(combat.is_finished(),
		"fixture check: the fight must still be live, or 'reading mid-fight' is not what is being tested")
	var rng_state := rng.state()
	var events_before := combat.events().size()
	var clock_before := combat.elapsed
	for _i in 10:
		var peek := combat.result()
		assert_not_null(peek, "result() must always hand back something safe to read mid-fight")
		assert_eq(peek.outcome, ShipCombat.Outcome.NONE, "and must not invent an outcome early")
		assert_eq(peek.scrap_reward, 0, "nor an unearned reward")
	assert_eq(rng.state(), rng_state, "reading the result must consume no randomness")
	assert_eq(combat.events().size(), events_before, "nor log anything")
	assert_almost_eq(combat.elapsed, clock_before, 0.0001, "nor move the clock")
	assert_eq(economy.scrap, scrap_at_rest, "nor touch the purse")

	combat.simulate()
	var settled := combat.result()
	var settled_state := rng.state()
	for _i in 10:
		assert_eq(combat.result().outcome, settled.outcome, "and after the end it must stay settled")
	assert_eq(rng.state(), settled_state, "still consuming no randomness")
	assert_eq(economy.scrap, scrap_at_rest,
		"and still paying nobody until apply_rewards() is called")


# --- the opponent generator ---------------------------------------------------

func test_make_enemy_scales_with_the_sector() -> void:
	var shallow := ShipCombat.make_enemy(1, MpRng.new(11), rules)
	var deep := ShipCombat.make_enemy(3, MpRng.new(11), rules)
	var shallow_ship := shallow[0] as Ship
	var deep_ship := deep[0] as Ship
	assert_true(deep_ship.hull_max > shallow_ship.hull_max,
		"a sector-3 raider must be tougher than a sector-1 one or the run has no arc (%d vs %d)"
			% [deep_ship.hull_max, shallow_ship.hull_max])
	assert_eq(deep_ship.hull, deep_ship.hull_max, "and must arrive undamaged")
	assert_true(deep_ship.reactor >= shallow_ship.reactor, "and no worse powered")
	assert_true(shallow_ship.hull_max < Ship.HULL_MAX,
		"and the first enemy must be weaker than the player's own starter hull (%d vs %d) — a first fight has to be survivable while the crew is still being won over"
			% [shallow_ship.hull_max, Ship.HULL_MAX])
	var deep_crew := deep[1] as Crew
	var shallow_crew := shallow[1] as Crew
	assert_true(deep_crew.station_performance(deep_crew.members[0].station)
			> shallow_crew.station_performance(shallow_crew.members[0].station),
		"and its crew must be better at the job, not just its hull thicker")


func test_make_enemy_crews_are_befriended_and_fed_so_their_stations_work() -> void:
	# Befriending gates everything (dossier §5 [C]) — including for the other
	# side. An unbefriended enemy crew would read as unmanned and every fight
	# would be a walkover against an inert ship.
	for seed_value in SEEDS:
		# A Care of our own, because `make_enemy` builds (and keeps) its own.
		var judge := Care.new(rules, MpRng.new(seed_value))
		var pair := ShipCombat.make_enemy(2, MpRng.new(seed_value), rules)
		var ship := pair[0] as Ship
		var crew := pair[1] as Crew
		assert_eq(crew.size(), ShipCombat.ENEMY_CREW_SIZE,
			"seed %d: an enemy crew is a fixed size" % seed_value)
		assert_true(ship.power_used() <= ship.reactor,
			"seed %d: and it must never be generated drawing more than its reactor makes" % seed_value)
		var working := 0
		for station in Ship.STATIONS:
			if crew.station_performance(station) > 0.0:
				working += 1
		assert_true(working > 0,
			"seed %d: at least one enemy station must actually be working, or the fight is against a ghost ship" % seed_value)
		assert_eq(crew.floaters().size(), 0,
			"seed %d: every raider must be posted somewhere — auto_assign is called for a reason" % seed_value)
		for member in crew.members:
			assert_eq(member.monkey.friendship, Monkey.FRIENDSHIP_MAX,
				"seed %d: %s must trust its own captain" % [seed_value, member.display_name()])
			assert_true(judge.can_act(member.monkey),
				"seed %d: %s must be fed enough to work — both hunger extremes paralyse" % [seed_value, member.display_name()])
			assert_true(member.monkey.current_strength > 0,
				"seed %d: %s must arrive with a health bar" % [seed_value, member.display_name()])


func test_make_enemy_is_deterministic_for_a_pinned_seed() -> void:
	for seed_value in SEEDS:
		var first := ShipCombat.make_enemy(3, MpRng.new(seed_value), rules)
		var second := ShipCombat.make_enemy(3, MpRng.new(seed_value), rules)
		assert_eq(_enemy_signature(first), _enemy_signature(second),
			"seed %d: the same seed must generate the same raider, hull, power layout, stats and postings — a save file resumes a fight from the seed alone" % seed_value)
	var other := ShipCombat.make_enemy(3, MpRng.new(777001), rules)
	assert_ne(_enemy_signature(other), _enemy_signature(ShipCombat.make_enemy(3, MpRng.new(11), rules)),
		"and a different seed must generate a different raider, or every fight in a sector is the same fight")


func test_make_enemy_survives_a_nonsense_sector_and_a_missing_rules() -> void:
	var zero := ShipCombat.make_enemy(0, MpRng.new(11), rules)
	var negative := ShipCombat.make_enemy(-9, MpRng.new(11), rules)
	var one := ShipCombat.make_enemy(1, MpRng.new(11), rules)
	assert_eq(_enemy_signature(zero), _enemy_signature(one),
		"sector 0 must be clamped to sector 1 rather than generating a hull of nothing")
	assert_eq(_enemy_signature(negative), _enemy_signature(one), "and so must a negative sector")
	# The recorded AMENDMENT to §10: `rules` was added because a Crew needs a
	# Care, which needs a GameRules. The two-argument form must still work.
	var defaulted := ShipCombat.make_enemy(2, MpRng.new(11))
	assert_not_null(defaulted[0] as Ship, "the two-argument form must still produce a ship")
	assert_eq((defaulted[1] as Crew).size(), ShipCombat.ENEMY_CREW_SIZE,
		"and a crew, with its own default GameRules")


# --- station XP (design §4: it accrues from DOING) ----------------------------

func test_the_players_crew_learns_from_the_fight() -> void:
	var combat := _combat(11)
	var crew := _ace_crew()
	combat.begin(_war_ship(), crew, _ship({}, 400), null, 1)
	combat.simulate()
	var gunner := crew.manning(Ship.Station.WEAPONS)
	assert_true(gunner.xp_in(Ship.Station.WEAPONS) > 0.0,
		"the monkey firing the gun must earn Weapons XP — station XP accrues from doing (§4)")
	assert_true(gunner.level_in(Ship.Station.WEAPONS) > 0,
		"and a whole fight at the console must be worth at least one level (%.1f XP)"
			% gunner.xp_in(Ship.Station.WEAPONS))
	var pilot := crew.manning(Ship.Station.PILOT)
	assert_true(pilot.xp_in(Ship.Station.PILOT) > 0.0,
		"and simply being at a working post must pay too (XP_PER_SECOND_MANNED)")
	assert_almost_eq(gunner.xp_in(Ship.Station.PILOT), 0.0, 0.0001,
		"but XP must go to the station the monkey is actually sitting at, not spill sideways")
	for member in crew.members:
		for station in Ship.STATIONS:
			assert_true(member.level_in(station) <= member.ceiling_in(station),
				"%s's level at station %d must never pass the ceiling its trained stat permits — that chain is the whole of the breeding meta"
					% [member.display_name(), station])


func test_the_enemys_station_xp_is_thrown_away() -> void:
	# The enemy crew is deleted when the fight ends, so any XP spent on it is
	# wasted work — and `_award` says so explicitly.
	var combat := _combat(1337)
	var enemy_crew := _ace_crew()
	combat.begin(_war_ship(), _ace_crew(), _war_ship(), enemy_crew, 2)
	combat.simulate()
	for member in enemy_crew.members:
		for station in Ship.STATIONS:
			assert_almost_eq(member.xp_in(station), 0.0, 0.0001,
				"the enemy's %s must earn nothing at station %d — only the player's crew levels up"
					% [member.display_name(), station])


func test_station_xp_cannot_lift_a_monkey_past_its_ceiling() -> void:
	# The two axes meeting: raw XP is banked uncapped, but the LEVEL in force is
	# capped by the trained stat, which only breeding can lift. A gunner with
	# POWER 10 may fight all day and stay a level-0 gunner.
	var combat := _combat(4242)
	var stat_values := {}
	for stat in Monkey.STATS:
		stat_values[stat] = DUD_STAT
	stat_values[Monkey.Stat.POWER] = 10
	var crew := _crew_at(Ship.Station.WEAPONS, _monkey("DUD GUNNER", stat_values))
	combat.begin(_ship({Ship.Station.WEAPONS: 4}), crew, _ship({}, 1000), null)
	combat.simulate()
	var member := crew.manning(Ship.Station.WEAPONS)
	assert_eq(member.ceiling_in(Ship.Station.WEAPONS), 0,
		"POWER 10 is below Crew.STAT_PER_LEVEL, so this monkey's Weapons ceiling is zero")
	assert_true(member.earned_level_in(Ship.Station.WEAPONS) > 0,
		"it must have earned a level by fighting (%.1f raw XP) or this test proves nothing"
			% member.xp_in(Ship.Station.WEAPONS))
	assert_eq(member.level_in(Ship.Station.WEAPONS), 0,
		"but the level in force must stay at the ceiling its training permits — otherwise in-run XP would replace breeding")
	assert_almost_eq(combat.player.performance(Ship.Station.WEAPONS),
		10.0 / Crew.REFERENCE_STAT, 0.0001,
		"and the station must still perform at the raw stat, with no level bonus")


# --- the first fight of a voyage, end to end ---------------------------------

func test_a_recharging_shield_layer_can_always_be_punched_through() -> void:
	# REGRESSION GUARD, and the most important balance invariant in ship combat:
	# if a shield layer comes back faster than the attacker can charge a shot,
	# every shot is absorbed by the same layer, no hull is ever touched and every
	# fight in the game is a 180-second draw. `Ship.SHIELD_RECHARGE_BASE` carries
	# the same warning; this is that warning expressed as behaviour rather than as
	# a comparison of two constants, so it also catches the case where crew
	# multipliers, not the bases, invert the relationship.
	#
	# Deliberately the worst realistic case: a two-bar weapon and a merely
	# starter-grade gunner against two bars of shield with a MAXED shield monkey.
	for seed_value in SEEDS:
		var combat := _combat(seed_value)
		var gunner_stats := {}
		for stat in Monkey.STATS:
			gunner_stats[stat] = DUD_STAT
		gunner_stats[Monkey.Stat.POWER] = 58
		var crew := _crew_at(Ship.Station.WEAPONS, _monkey("STARTER GUNNER", gunner_stats))
		combat.begin(_ship({Ship.Station.WEAPONS: 2}), crew,
			_ship({Ship.Station.SHIELDS: 2}, 40),
			_crew_at(Ship.Station.SHIELDS, _ace(Ship.Station.SHIELDS)))
		var result := combat.simulate()
		assert_true(_count(combat, ShipCombat.EventKind.SHIELD_ABSORBED) > 0,
			"seed %d: the shield must do its job at least once, or this test is not measuring anything" % seed_value)
		assert_true(_count(combat, ShipCombat.EventKind.HULL_DAMAGED) > 0,
			"seed %d: a weapon MUST out-cycle a regenerating shield layer — if it cannot, a one-layer bubble is literal invulnerability and every fight is a draw" % seed_value)
		assert_eq(result.outcome, ShipCombat.Outcome.PLAYER_WON,
			"seed %d: and the damage must accumulate to a kill inside the time limit (%.0fs of %.0f)"
				% [seed_value, result.elapsed, ShipCombat.MAX_SECONDS])


func test_the_first_fight_of_a_voyage_is_winnable() -> void:
	# `make_enemy`'s DIVERGENCE note promises a sector-1 raider deliberately
	# weaker than the player's starter, "so a first fight is winnable". Verified
	# end to end, hands off the console: starter ship, starter crew, no orders.
	var wins := 0
	var decided := 0
	var hull_hits := 0
	for seed_value in SEEDS:
		var combat := _combat(seed_value)
		var pair := ShipCombat.make_enemy(1, rng, rules)
		combat.begin(Ship.make_starter(), _starter_crew(true), pair[0] as Ship, pair[1] as Crew, 1)
		var result := combat.simulate()
		assert_ne(result.outcome, ShipCombat.Outcome.NONE,
			"seed %d: the opening fight of a voyage must reach a real outcome" % seed_value)
		hull_hits += _count(combat, ShipCombat.EventKind.HULL_DAMAGED)
		if result.outcome != ShipCombat.Outcome.DRAW:
			decided += 1
		if result.player_won():
			wins += 1
	assert_true(hull_hits > 0,
		"shots must reach hulls in the game's first engagement (%d hits over %d seeds)" % [hull_hits, SEEDS.size()])
	assert_true(decided >= SEEDS.size() / 2,
		"most first fights must actually be decided rather than timing out (%d of %d)" % [decided, SEEDS.size()])
	assert_true(wins > 0,
		"and the first fight must be winnable with the starter's own ship and crew (%d wins of %d) — if this goes to zero the opening of the game is unwinnable" % [wins, SEEDS.size()])


func test_befriending_the_crew_changes_the_first_fight() -> void:
	# Dossier §5 [C], in space: befriending gates everything. An unbefriended
	# crew mans nothing (`Crew.effective_manning` reads an unavailable monkey as
	# an empty seat) AND ignores orders, so the same ship in the same fight must
	# do measurably worse.
	var wins := {}
	var refusals := {}
	for befriended in [false, true]:
		wins[befriended] = 0
		refusals[befriended] = 0
		for seed_value in SEEDS:
			var combat := _combat(seed_value)
			var pair := ShipCombat.make_enemy(1, rng, rules)
			combat.begin(Ship.make_starter(), _starter_crew(befriended),
				pair[0] as Ship, pair[1] as Crew, 1)
			# The FTL decision `Ship.make_starter` exists to force: the opening
			# allocation spends the whole reactor, so more gun means less of
			# something else.
			combat.set_power(Ship.Station.SHIELDS, 0)
			combat.set_power(Ship.Station.PILOT, 0)
			combat.set_power(Ship.Station.SENSORS, 0)
			combat.set_power(Ship.Station.WEAPONS, Ship.SYSTEM_BARS_MAX)
			var result := combat.simulate()
			refusals[befriended] = int(refusals[befriended]) + _count(combat, ShipCombat.EventKind.DISOBEYED)
			if result.player_won():
				wins[befriended] = int(wins[befriended]) + 1
	assert_eq(int(refusals[true]), 0,
		"a crew at FRIENDSHIP_MAX must carry out the reroute every time (%d refusals)" % int(refusals[true]))
	assert_true(int(refusals[false]) > 0,
		"an unbefriended crew must ignore the order often enough to matter — this is the rule the user pinned twice (%d refusals over %d fights)" % [int(refusals[false]), SEEDS.size()])
	assert_true(int(wins[true]) > int(wins[false]),
		"and winning the crew over must visibly change the outcome, not just the flavour text (%d wins befriended vs %d unbefriended)" % [int(wins[true]), int(wins[false])])


# --- edges -------------------------------------------------------------------

func test_a_crewless_ship_still_fights_to_a_finish() -> void:
	# Power alone gives a floor (§10): a voyage starts with 4 crew for 5 stations
	# and an empty seat must degrade the ship, not break the sim.
	for seed_value in SEEDS:
		var combat := _combat(seed_value)
		combat.begin(_war_ship(), null, _war_ship(), null, 1)
		var result := combat.simulate()
		assert_true(combat.is_finished(),
			"seed %d: two unmanned ships must still resolve a fight" % seed_value)
		assert_ne(result.outcome, ShipCombat.Outcome.NONE,
			"seed %d: and reach a real outcome" % seed_value)
		assert_true(combat.has_event(ShipCombat.EventKind.SHOT_FIRED),
			"seed %d: unmanned weapons must still fire, at the hardware's own rate" % seed_value)
		assert_true(combat.set_power(Ship.Station.WEAPONS, 1) or combat.is_finished(),
			"seed %d: and an order aboard a crewless ship has nobody to refuse it" % seed_value)


func test_a_missing_care_never_crashes_the_fight() -> void:
	var lone_rng := MpRng.new(65537)
	var combat := ShipCombat.new(rules, lone_rng, null)
	care = CountingCare.new(rules, lone_rng)
	rng = lone_rng
	combat.begin(_war_ship(), _ace_crew(0), _war_ship(), _ace_crew(0), 1)
	assert_true(combat.set_power(Ship.Station.WEAPONS, 4),
		"with no Care to ask, orders must go through rather than crash — the same stance MatchResolver takes")
	var result := combat.simulate()
	assert_true(combat.is_finished(), "and the fight must still resolve")
	assert_ne(result.outcome, ShipCombat.Outcome.NONE, "with a real outcome")


func test_every_event_carries_commentary_and_a_sane_clock() -> void:
	for seed_value in SEEDS:
		var combat := _brawl(seed_value)
		combat.simulate()
		var previous := -1.0
		for event in combat.events():
			assert_ne(event.text, "",
				"seed %d: every event must carry a line the HUD can print" % seed_value)
			assert_in_range(event.elapsed, 0.0, ShipCombat.MAX_SECONDS,
				"seed %d: and a timestamp inside the fight" % seed_value)
			assert_true(event.elapsed >= previous,
				"seed %d: and the log must never go backwards in time, or a replay plays out of order" % seed_value)
			previous = event.elapsed
			assert_in_range(event.station, -1, Ship.STATIONS.size() - 1,
				"seed %d: and either a real station or -1 for 'the whole ship'" % seed_value)
			assert_true(event.amount >= 0,
				"seed %d: and a non-negative amount, since the HUD prints it raw" % seed_value)

