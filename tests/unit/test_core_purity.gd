extends TestCase

## READ-ONLY QUESTIONS MUST NOT MOVE THE GAME ON.
##
## Added by the verification pass, after finding a real one.
##
## Every core system takes an injected `MpRng` so a run replays identically from
## its seed (see `core/rng.gd`). That guarantee holds only if the number of
## times the UI *asks a question* cannot change the stream. A screen calls these
## predicates to grey out a button, and it may call them once, or on every
## redraw, or twice because two panels both want to know — the run must not care.
##
## THE BUG THIS FILE WAS WRITTEN FOR: `Training.can_train()` was implemented as
## `_block_reason(monkey) == ""`, and `_block_reason` rolls `_rng.chance(0.5)` to
## choose between "BITES YOU" and "TURNS ITS BACK" for an unbefriended monkey.
## Seven extra `can_train()` calls moved the next `randf()` from 0.294003 to
## 0.574056 — a silent desync of the entire run, invisible to every existing
## test because none of them polled the predicate. Fixed by splitting the pure
## `Training._blocked()` out of the flavour text.
##
## Any new predicate on a core system belongs in `PURE_QUERIES` below.

const SEED := 20000324
## Enough calls that a single leaked draw per call cannot coincidentally land
## back on the same stream position.
const POLLS := 7


func _rules() -> GameRules:
	return GameRules.new()


## The RNG state after `body` has been run `times` times against a fresh system.
## Comparing two of these is the whole test: same seed, different poll counts,
## and the stream must be in exactly the same place.
func _state_after(times: int, body: Callable) -> int:
	var rng := MpRng.new(SEED)
	for _i in times:
		body.call(rng)
	return rng.state()


func _assert_pure(label: String, body: Callable) -> void:
	var untouched := _state_after(0, body)
	var polled := _state_after(POLLS, body)
	assert_eq(polled, untouched,
		"%s is a read-only question but consumed %d RNG draw(s)" % [label, POLLS])


func _starter(friendship: int, fullness: int) -> Monkey:
	var monkey := RunState.make_starter()
	monkey.friendship = friendship
	monkey.fullness = fullness
	return monkey


# --- the one that was actually broken -----------------------------------------

func test_asking_whether_an_unbefriended_monkey_can_train_is_free() -> void:
	# friendship 0 is the branch that rolled: "BITES YOU" vs "TURNS ITS BACK".
	var monkey := _starter(0, 12)
	assert_false(Training.new(_rules(), MpRng.new(SEED)).can_train(monkey),
		"fixture check: an unbefriended monkey must actually be blocked")
	_assert_pure("Training.can_train (unbefriended)", func(rng: MpRng) -> void:
		Training.new(_rules(), rng).can_train(monkey))


func test_asking_whether_a_ready_monkey_can_train_is_free() -> void:
	var monkey := _starter(Monkey.FRIENDSHIP_MAX, 12)
	assert_true(Training.new(_rules(), MpRng.new(SEED)).can_train(monkey),
		"fixture check: a fed, bonded monkey must actually be able to train")
	_assert_pure("Training.can_train (ready)", func(rng: MpRng) -> void:
		Training.new(_rules(), rng).can_train(monkey))


func test_every_blocked_state_is_free_to_ask_about() -> void:
	# One per branch of Training._blocked, so a future edit that reintroduces a
	# roll in any of them is caught wherever it lands.
	var cases := {
		"no monkey": null,
		"unbefriended": _starter(0, 12),
		"starving": _starter(Monkey.FRIENDSHIP_MAX, 0),
		"stuffed": _starter(Monkey.FRIENDSHIP_MAX, Monkey.FULLNESS_MAX),
	}
	var immobilised := _starter(Monkey.FRIENDSHIP_MAX, 12)
	immobilised.paralysed_slots = 2
	cases["immobilised"] = immobilised

	for label in cases:
		var monkey: Monkey = cases[label]
		_assert_pure("Training.can_train (%s)" % label, func(rng: MpRng) -> void:
			Training.new(_rules(), rng).can_train(monkey))


# --- the same guarantee for the rest of the read-only surface ------------------

func test_cares_read_only_questions_are_free() -> void:
	var monkey := _starter(0, Monkey.FULLNESS_MAX)
	_assert_pure("Care.can_act", func(rng: MpRng) -> void:
		Care.new(_rules(), rng).can_act(monkey))
	_assert_pure("Care.is_paralysed", func(rng: MpRng) -> void:
		Care.new(_rules(), rng).is_paralysed(monkey))
	_assert_pure("Care.block_reason", func(rng: MpRng) -> void:
		Care.new(_rules(), rng).block_reason(monkey))
	_assert_pure("Care.hunger_state", func(rng: MpRng) -> void:
		Care.new(_rules(), rng).hunger_state(monkey))
	_assert_pure("Care.obedience_chance", func(rng: MpRng) -> void:
		Care.new(_rules(), rng).obedience_chance(monkey))
	_assert_pure("Care.slots_until_digested", func(rng: MpRng) -> void:
		Care.new(_rules(), rng).slots_until_digested(monkey))


func test_breedings_read_only_questions_are_free() -> void:
	var monkey := _starter(Monkey.FRIENDSHIP_MAX, 12)
	for stat in Monkey.STATS:
		monkey.set_stat(stat, monkey.get_cap(stat))
	_assert_pure("Breeding.can_breed", func(rng: MpRng) -> void:
		Breeding.new(_rules(), rng).can_breed(monkey))
	_assert_pure("Breeding.breed_advice", func(rng: MpRng) -> void:
		Breeding.new(_rules(), rng).breed_advice(monkey))


func test_the_ladders_read_only_questions_are_free() -> void:
	# `offer_opponents` already derives its own stream from (seed, day) so that
	# re-opening Bill's card shows the same three; this pins that it also leaves
	# the SHARED stream alone, which is what makes re-opening it free.
	var monkey := _starter(Monkey.FRIENDSHIP_MAX, 12)
	_assert_pure("Ladder.offer_opponents", func(rng: MpRng) -> void:
		Ladder.new(_rules(), rng).offer_opponents(monkey, 5))
	_assert_pure("Ladder.is_champion", func(rng: MpRng) -> void:
		Ladder.new(_rules(), rng).is_champion())


func test_the_facades_read_only_questions_are_free() -> void:
	# The layer the UI actually touches. A screen polling GameState must be as
	# free as polling core directly.
	var script: Script = load("res://core/game_state.gd")
	var probes: Array[Callable] = [
		func(gs: Node) -> void: gs.can_train(),
		func(gs: Node) -> void: gs.can_fight(),
		func(gs: Node) -> void: gs.can_breed(),
		func(gs: Node) -> void: gs.block_reason(),
		func(gs: Node) -> void: gs.breed_advice(),
		func(gs: Node) -> void: gs.money(),
		func(gs: Node) -> void: gs.rank(),
		func(gs: Node) -> void: gs.inventory(),
	]
	for index in probes.size():
		var probe: Callable = probes[index]
		var states: Array[int] = []
		for polls in [0, POLLS]:
			var gs: Node = script.new()
			gs.new_run(int(RunState.Protagonist.KENTA), SEED)
			for _i in polls:
				probe.call(gs)
			states.append(gs.run.rng.state())
			gs.free()
		assert_eq(states[1], states[0],
			"GameState read-only query #%d moved the run's RNG" % index)


# --- Monkey Mission: the same guarantee for the new systems --------------------
#
# docs/MISSION-ARCHITECTURE.md §12 requires every new predicate to land here.
# These are the ones a combat HUD will poll hardest — a power readout and five
# station performance figures, redrawn every frame — so a leaked draw in any of
# them would desync a voyage far faster than the original bug desynced a run.


func _crew_with(rng: MpRng, friendship: int, fullness: int) -> Crew:
	var rules := _rules()
	var crew := Crew.new(rules, rng, Care.new(rules, rng))
	var monkey := _starter(friendship, fullness)
	var member := crew.add(monkey)
	crew.assign(member, Ship.Station.WEAPONS)
	return crew


func test_ships_derived_curves_are_free() -> void:
	# Ship takes no MpRng at all, which is the strongest form of this guarantee:
	# it cannot consume a draw because it has nothing to draw from. Asserted
	# behaviourally anyway, so that adding an rng to Ship fails here immediately.
	var ship := Ship.make_starter()
	_assert_pure("Ship.evasion", func(_rng: MpRng) -> void: ship.evasion(1.0, 1.0))
	_assert_pure("Ship.shield_recharge_rate", func(_rng: MpRng) -> void:
		ship.shield_recharge_rate(1.0))
	_assert_pure("Ship.shield_layers_max", func(_rng: MpRng) -> void: ship.shield_layers_max())
	_assert_pure("Ship.weapon_charge_rate", func(_rng: MpRng) -> void:
		ship.weapon_charge_rate(1.0))
	_assert_pure("Ship.weapon_damage", func(_rng: MpRng) -> void: ship.weapon_damage(1.0))
	_assert_pure("Ship.targeting_bonus", func(_rng: MpRng) -> void: ship.targeting_bonus(1.0))
	_assert_pure("Ship.jump_charge_rate", func(_rng: MpRng) -> void: ship.jump_charge_rate(1.0))
	_assert_pure("Ship.effective_power", func(_rng: MpRng) -> void:
		ship.effective_power(Ship.Station.SHIELDS))
	_assert_pure("Ship.power_free", func(_rng: MpRng) -> void: ship.power_free())
	_assert_pure("Ship.is_offline", func(_rng: MpRng) -> void: ship.is_offline(Ship.Station.PILOT))
	_assert_pure("Ship.is_destroyed", func(_rng: MpRng) -> void: ship.is_destroyed())
	_assert_pure("Ship.has_hazard", func(_rng: MpRng) -> void: ship.has_hazard())


func test_crews_read_only_questions_are_free() -> void:
	# The interesting case is an UNAVAILABLE member: `is_available` delegates to
	# Care, and Care.block_reason once rolled a die to pick its flavour text. A
	# station-performance readout must not inherit that.
	var cases := {
		"ready": [Monkey.FRIENDSHIP_MAX, 12],
		"unbefriended": [0, 12],
		"starving": [Monkey.FRIENDSHIP_MAX, 0],
		"stuffed": [Monkey.FRIENDSHIP_MAX, Monkey.FULLNESS_MAX],
	}
	for label in cases:
		var setup: Array = cases[label]
		var friendship := int(setup[0])
		var fullness := int(setup[1])
		_assert_pure("Crew.station_performance (%s)" % label, func(rng: MpRng) -> void:
			_crew_with(rng, friendship, fullness).station_performance(Ship.Station.WEAPONS))
		_assert_pure("Crew.is_available (%s)" % label, func(rng: MpRng) -> void:
			var crew := _crew_with(rng, friendship, fullness)
			crew.is_available(crew.members[0]))
		_assert_pure("Crew.unavailable_reason (%s)" % label, func(rng: MpRng) -> void:
			var crew := _crew_with(rng, friendship, fullness)
			crew.unavailable_reason(crew.members[0]))
		_assert_pure("Crew.effective_manning (%s)" % label, func(rng: MpRng) -> void:
			_crew_with(rng, friendship, fullness).effective_manning(Ship.Station.WEAPONS))


func test_crews_progress_queries_are_free() -> void:
	_assert_pure("Crew.level_ceiling", func(rng: MpRng) -> void:
		var crew := _crew_with(rng, Monkey.FRIENDSHIP_MAX, 12)
		crew.level_ceiling(crew.members[0], Ship.Station.WEAPONS))
	_assert_pure("Crew.xp_rate", func(rng: MpRng) -> void:
		var crew := _crew_with(rng, Monkey.FRIENDSHIP_MAX, 12)
		crew.xp_rate(crew.members[0], Ship.Station.WEAPONS))
	_assert_pure("Crew.level_of", func(rng: MpRng) -> void:
		var crew := _crew_with(rng, Monkey.FRIENDSHIP_MAX, 12)
		crew.level_of(crew.members[0], Ship.Station.WEAPONS))
	_assert_pure("Crew.performance_of", func(rng: MpRng) -> void:
		var crew := _crew_with(rng, Monkey.FRIENDSHIP_MAX, 12)
		crew.performance_of(crew.members[0], Ship.Station.PILOT))
	_assert_pure("Crew.is_incapacitated", func(rng: MpRng) -> void:
		var crew := _crew_with(rng, Monkey.FRIENDSHIP_MAX, 12)
		crew.is_incapacitated(crew.members[0]))
	_assert_pure("Crew.unmanned_stations", func(rng: MpRng) -> void:
		_crew_with(rng, Monkey.FRIENDSHIP_MAX, 12).unmanned_stations())
	_assert_pure("Crew.all_dead", func(rng: MpRng) -> void:
		_crew_with(rng, Monkey.FRIENDSHIP_MAX, 12).all_dead())


func test_auto_assign_does_not_touch_the_rng() -> void:
	# auto_assign MUTATES, so it is not a predicate — but it is documented as
	# deterministic and RNG-free, and a voyage rebuilding its crew layout must not
	# be able to shift the stream. Pinned here because this is where anyone would
	# look for it.
	_assert_pure("Crew.auto_assign", func(rng: MpRng) -> void:
		var rules := _rules()
		var crew := Crew.new(rules, rng, Care.new(rules, rng))
		for _i in 4:
			crew.add(RunState.make_starter())
		crew.auto_assign())
