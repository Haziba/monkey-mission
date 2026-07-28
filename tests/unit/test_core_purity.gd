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
