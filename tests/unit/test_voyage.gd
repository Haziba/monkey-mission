extends TestCase

## core/voyage.gd — the run loop. MISSION-ARCHITECTURE §6, with §7 for the map the
## voyage walks and §13 row 4 for the resolved fuel/threat pacing.
##
## DETERMINISM IS THE POINT OF THIS FILE. Every `MpRng` below is constructed with
## an explicit non-zero seed, because `MpRng.new(0)` seeds itself from the wall
## clock (core/rng.gd) and would turn the whole suite into a coin flip. Almost
## every invariant is checked across `SEEDS` rather than one lucky map, so what is
## pinned is a *property of the loop* and not a property of one graph.
##
## The four things this file exists to protect:
##
##  1. **An illegal jump is a no-op, not an approximation.** `jump_reason` is the
##     single source of truth (`can_jump_to` is defined as "the reason is empty"),
##     so the two can never disagree — and a refused jump must leave the beacon,
##     the fuel and the jump count byte-identical. A jump that half-happened is
##     the class of bug that desyncs a save.
##  2. **`check_end` reports, it does not decide.** A screen polls it on every
##     redraw. It must therefore end nothing, change nothing, and — per
##     tests/unit/test_core_purity.gd — consume no RNG. The priority order inside
##     it is load-bearing: HULL_LOST above everything, VICTORY above OVERTAKEN.
##  3. **Arriving at the boss is not beating it.** `boss_cleared` is the flag that
##     stops the final sector declaring VICTORY the moment the ship docks, which
##     would delete the boss fight from the game. Both directions are pinned.
##  4. **The threat's pacing is the pressure.** Grace, then one column per jump,
##     and `threat_holds` true for everything at or behind it. Every link in a
##     `SectorMap` goes strictly forward, so ground the threat has taken is gone.

## Eight pinned seeds. Any invariant worth having holds on all of them; a single
## seed only ever proves that a seed exists.
const SEEDS: Array[int] = [11, 101, 1337, 20000324, 424242, 777, 90210, 8675309]

## The default fixture's seed. 20000324 is the seed the rest of the suite uses.
const SEED := 20000324

## Enough polls that a leaked RNG draw per call cannot coincidentally land back on
## the same stream position. Matches tests/unit/test_core_purity.gd.
const POLLS := 7

## Guard on every walk helper, so a linking bug reports as a loud failure instead
## of hanging the headless runner forever.
const WALK_GUARD := 40

var rules: GameRules
var rng: MpRng
var ship: Ship
var crew: Crew
var voyage: Voyage


func before_each() -> void:
	_fixture(SEED)


# --- fixtures ----------------------------------------------------------------

## A begun voyage under an explicit seed.
##
## The construction ORDER is deliberate and must not be shuffled: the map is the
## first thing to draw from `rng`, so `voyage.map` is exactly what
## `SectorMap.generate(1, MpRng.new(seed_value))` produces, and a test can compare
## the two.
func _fixture(seed_value: int) -> void:
	rules = GameRules.new()
	rng = MpRng.new(seed_value)
	ship = Ship.make_starter()
	voyage = Voyage.new(rules, rng)
	voyage.begin(ship)
	crew = _fresh_crew()


func _fresh_crew() -> Crew:
	var made: Crew = Crew.new(rules, rng, Care.new(rules, rng))
	made.add(RunState.make_starter())
	return made


## Everything a refused operation has to leave untouched.
func _snapshot() -> Dictionary:
	return {
		"sector": voyage.sector,
		"at": voyage.at,
		"jumps_taken": voyage.jumps_taken,
		"threat_column": voyage.threat_column,
		"boss_cleared": voyage.boss_cleared,
		"ended": voyage.ended,
		"end_reason": int(voyage.end_reason),
		"fuel": ship.fuel,
		"map": voyage.map.to_dict() if voyage.map != null else {},
	}


func _assert_unchanged(before: Dictionary, context: String) -> void:
	var after := _snapshot()
	for key in before:
		assert_eq(after[key], before[key],
			"%s must change nothing at all, but \"%s\" moved — a half-applied jump is how a voyage desyncs from its save" % [
				context, key])


## Any beacon index that is NOT one jump away, so "no route there" can be tested
## without depending on which graph a seed happened to produce.
func _non_neighbour() -> int:
	var reachable: Array[int] = voyage.options()
	for index in voyage.map.size():
		if index != voyage.at and not reachable.has(index):
			return index
	fail("the fixture map has no non-neighbour at all, so jump legality cannot be tested on it")
	return -1


## Walk the greedy direct line entry -> boss. Every link goes forward exactly one
## column (§7 invariant 5), so any option is a legal step and the walk is a real
## route, not a contrivance. Returns the jumps spent.
func _walk_to_boss() -> int:
	var jumps := 0
	while not voyage.at_boss() and jumps < WALK_GUARD:
		var choices: Array[int] = voyage.options()
		if choices.is_empty():
			fail("a non-boss beacon offered no forward route, so the sector cannot be crossed at all")
			return jumps
		if not voyage.jump_to(int(choices[0]), ship):
			fail("a jump the map offered and the tank could pay for was refused, so the route is not walkable")
			return jumps
		jumps += 1
	assert_true(voyage.at_boss(),
		"a direct line from the entry must reach the boss — §7 invariant 4 promises the path exists")
	return jumps


## Cross sectors until the final one, clearing each boss on the way. Leaves the
## ship AT the final sector's boss, with `boss_cleared` still false.
func _reach_the_final_boss() -> void:
	var guard := 0
	while not voyage.is_final_sector() and guard < Voyage.SECTORS + 2:
		_walk_to_boss()
		voyage.clear_boss()
		assert_true(voyage.enter_next_sector(ship),
			"a cleared boss on a non-final sector must open the next one, or the voyage cannot reach its ending")
		guard += 1
	assert_true(voyage.is_final_sector(),
		"the voyage must be able to reach the final sector, or VICTORY is unreachable by play")
	_walk_to_boss()


func _kill_the_whole_crew() -> void:
	for member in crew.members:
		crew.kill(member)
	assert_true(crew.all_dead(), "fixture check: the crew must actually all be dead")


## The RNG state after every read-only question has been asked `times` times.
## Comparing two of these is the whole purity test: same seed, different poll
## count, and the stream must sit in exactly the same place.
func _state_after_polling(times: int) -> int:
	var probe_rng := MpRng.new(SEED)
	var probe_ship := Ship.make_starter()
	var probe := Voyage.new(rules, probe_rng)
	probe.begin(probe_ship)
	var probe_crew: Crew = Crew.new(rules, probe_rng, Care.new(rules, probe_rng))
	probe_crew.add(RunState.make_starter())
	for _i in times:
		probe.options()
		probe.current_beacon()
		probe.current_kind()
		probe.current_column()
		probe.at_boss()
		probe.is_final_sector()
		probe.threat_at_player()
		probe.threat_distance()
		probe.is_over()
		probe.was_won()
		probe.check_end(probe_ship, probe_crew)
		for index in probe.map.size():
			probe.can_jump_to(index, probe_ship)
			probe.jump_reason(index, probe_ship)
			probe.threat_holds(index)
	return probe_rng.state()


# --- begin(), §6 -------------------------------------------------------------

func test_begin_opens_sector_one_at_the_entry_beacon() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		assert_eq(voyage.sector, 1, "seed %d: a voyage always opens on sector 1" % seed_value)
		assert_not_null(voyage.map, "seed %d: begin must have generated a chart to fly" % seed_value)
		assert_eq(voyage.at, voyage.map.entry,
			"seed %d: the ship starts at the sector's single mouth, not an arbitrary beacon" % seed_value)
		assert_eq(voyage.current_column(), 0,
			"seed %d: the entry is column 0, so the whole sector still lies ahead" % seed_value)
		assert_eq(voyage.jumps_taken, 0, "seed %d: no jump has been made yet" % seed_value)
		assert_false(voyage.ended, "seed %d: a voyage cannot begin already over" % seed_value)
		assert_eq(int(voyage.end_reason), int(Voyage.EndReason.NONE),
			"seed %d: a fresh voyage has no ending recorded" % seed_value)
		assert_false(voyage.boss_cleared,
			"seed %d: no boss has been beaten at the moment of departure" % seed_value)
		assert_false(voyage.is_final_sector(),
			"seed %d: sector 1 of %d cannot be the last, or the voyage has no depth" % [seed_value, Voyage.SECTORS])
		assert_true(voyage.map.beacon(voyage.at).visited,
			"seed %d: the beacon the ship is sitting at must read as visited" % seed_value)


func test_begin_draws_its_map_from_the_injected_rng_and_nothing_else() -> void:
	# The map is the first draw from the stream, so it must equal the one
	# SectorMap.generate makes from the same seed. If begin ever reached for a
	# global randi() this is the assertion that catches it (§0: never).
	for seed_value in SEEDS:
		_fixture(seed_value)
		var expected: SectorMap = SectorMap.generate(1, MpRng.new(seed_value))
		# begin also arrives at the entry, which reveals its neighbours, so bring
		# the freshly generated map to the same state before comparing.
		expected.mark_visited(expected.entry)
		assert_eq(voyage.map.to_dict(), expected.to_dict(),
			"seed %d: begin's chart must come from the injected MpRng, so a voyage replays from its seed" % seed_value)


func test_begin_starts_the_threat_behind_the_entry_column() -> void:
	# The opening beacon must never be already lost. THREAT_START_COLUMN is behind
	# column 0 precisely so that check_end cannot say OVERTAKEN before the first
	# jump — a voyage that ends on departure is not a voyage.
	for seed_value in SEEDS:
		_fixture(seed_value)
		assert_eq(voyage.threat_column, Voyage.THREAT_START_COLUMN,
			"seed %d: the threat opens at THREAT_START_COLUMN" % seed_value)
		assert_true(voyage.threat_column < voyage.current_column(),
			"seed %d: the threat must start strictly behind the ship, or the entry beacon is already lost" % seed_value)
		assert_false(voyage.threat_holds(voyage.map.entry),
			"seed %d: the entry beacon must not be inside the threat at departure" % seed_value)
		assert_false(voyage.threat_at_player(),
			"seed %d: the ship cannot be overtaken before it has moved" % seed_value)
		assert_true(voyage.threat_distance() > 0,
			"seed %d: there must be clear space between the threat and the ship at departure" % seed_value)
		assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.NONE),
			"seed %d: a healthy voyage reports no ending on its first frame" % seed_value)


func test_begin_spends_none_of_the_ships_stores() -> void:
	assert_eq(ship.fuel, Ship.FUEL_START,
		"opening a sector must not cost fuel — only jumping does, or the tank is wrong before the first decision")
	assert_eq(ship.hull, ship.hull_max, "a voyage departs on a whole hull")


# --- jump legality, §6 -------------------------------------------------------

func test_options_are_exactly_the_current_beacons_links() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var links: Array[int] = voyage.map.beacon(voyage.at).links
		assert_eq(voyage.options(), links,
			"seed %d: options() is the current beacon's link list and nothing else — a route the map does not draw must not be flyable" % seed_value)
		assert_true(voyage.options().size() > 0,
			"seed %d: the entry must offer at least one route out, or the sector is a dead end" % seed_value)
		# A copy, not the live array: a screen holding options() must not be able
		# to edit the chart.
		var handed: Array[int] = voyage.options()
		handed.append(9999)
		assert_not_has(voyage.map.beacon(voyage.at).links, 9999,
			"seed %d: options() must hand back a copy, or a caller can rewrite the map by accident" % seed_value)


func test_every_option_lies_exactly_one_column_ahead() -> void:
	# §7 invariant 5, restated from the voyage's side: this is what makes the
	# threat a threat. If a link ever went sideways or back, ground the threat had
	# taken could be re-entered and the pressure would evaporate.
	for seed_value in SEEDS:
		_fixture(seed_value)
		var walked := 0
		while not voyage.at_boss() and walked < WALK_GUARD:
			var here := voyage.current_column()
			for index in voyage.options():
				assert_eq(voyage.map.beacon(index).column, here + 1,
					"seed %d: every jump must go forward exactly one column, so the threat can never be outrun backwards" % seed_value)
			voyage.jump_to(int(voyage.options()[0]), ship)
			walked += 1


func test_can_jump_to_a_neighbour_but_never_to_a_stranger() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		for index in voyage.options():
			assert_true(voyage.can_jump_to(index, ship),
				"seed %d: beacon %d is one jump away on a full tank, so it must be legal" % [seed_value, index])
		var stranger := _non_neighbour()
		assert_false(voyage.can_jump_to(stranger, ship),
			"seed %d: beacon %d is not linked from here, so it must be unreachable however much fuel there is" % [seed_value, stranger])
		assert_false(voyage.can_jump_to(voyage.at, ship),
			"seed %d: a beacon cannot jump to itself — that would burn fuel for nothing" % seed_value)


func test_can_jump_to_rejects_indices_that_are_not_on_the_map() -> void:
	# A bad index must be refused rather than crash or wrap: the UI computes these
	# from a click, and a stale click after a redraw is normal.
	for index in [-1, -99, voyage.map.size(), voyage.map.size() + 100]:
		assert_false(voyage.can_jump_to(int(index), ship),
			"index %s is off the map and must be refused, not resolved to some other beacon" % index)
		assert_ne(voyage.jump_reason(int(index), ship), "",
			"index %s is off the map, so jump_reason must name a cause" % index)


func test_can_jump_to_is_false_once_the_tank_cannot_pay_for_one_jump() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var target := int(voyage.options()[0])
		ship.fuel = Voyage.FUEL_PER_JUMP
		assert_true(voyage.can_jump_to(target, ship),
			"seed %d: exactly FUEL_PER_JUMP in the tank must still buy one jump — the boundary is inclusive" % seed_value)
		ship.fuel = Voyage.FUEL_PER_JUMP - 1
		assert_false(voyage.can_jump_to(target, ship),
			"seed %d: one unit short of FUEL_PER_JUMP must ground the ship" % seed_value)
		assert_has(voyage.jump_reason(target, ship), "FUEL",
			"seed %d: the refusal must tell the player it is fuel, not leave them guessing" % seed_value)


func test_jump_reason_is_empty_exactly_when_can_jump_to_is_true() -> void:
	# The contract's own wording: "" when legal. `can_jump_to` is DEFINED as the
	# reason being empty, so the danger is not disagreement but a legal jump that
	# still carries text, or an illegal one that carries none — either would make
	# the UI lie. Swept over every index and over both fuel states.
	for seed_value in SEEDS:
		_fixture(seed_value)
		for fuel in [Ship.FUEL_START, Voyage.FUEL_PER_JUMP, 0]:
			ship.fuel = int(fuel)
			for index in range(-2, voyage.map.size() + 2):
				var legal := voyage.can_jump_to(index, ship)
				var reason := voyage.jump_reason(index, ship)
				if legal:
					assert_eq(reason, "",
						"seed %d fuel %s: beacon %d is legal, so jump_reason must be empty" % [seed_value, fuel, index])
				else:
					assert_ne(reason, "",
						"seed %d fuel %s: beacon %d is illegal, so jump_reason must say why" % [seed_value, fuel, index])


func test_jump_reason_names_a_cause_for_every_way_a_jump_can_be_illegal() -> void:
	var chartless: Voyage = Voyage.new(rules, MpRng.new(SEED))
	assert_ne(chartless.jump_reason(0, ship), "",
		"a voyage that has never begun has no chart, and must say so rather than jump into nothing")
	assert_false(chartless.can_jump_to(0, ship),
		"a voyage that has never begun must refuse every jump")

	var target := int(voyage.options()[0])
	assert_ne(voyage.jump_reason(target, null), "",
		"a legal-looking jump with no ship must still be refused — nothing can fly")
	assert_false(voyage.can_jump_to(target, null),
		"can_jump_to must agree with jump_reason when the ship is missing")

	voyage.end(Voyage.EndReason.HULL_LOST)
	assert_ne(voyage.jump_reason(target, ship), "",
		"an ended voyage must refuse every jump and say the voyage is over")


# --- an illegal jump changes NOTHING -----------------------------------------

func test_an_illegal_jump_to_a_stranger_changes_nothing() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var stranger := _non_neighbour()
		var before := _snapshot()
		assert_false(voyage.jump_to(stranger, ship),
			"seed %d: a jump to an unlinked beacon must report failure" % seed_value)
		_assert_unchanged(before, "seed %d: a refused jump to an unlinked beacon" % seed_value)


func test_an_illegal_jump_with_a_dry_tank_changes_nothing() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var target := int(voyage.options()[0])
		ship.fuel = 0
		var before := _snapshot()
		assert_false(voyage.jump_to(target, ship),
			"seed %d: a jump with no fuel must report failure" % seed_value)
		_assert_unchanged(before, "seed %d: a refused jump on a dry tank" % seed_value)
		assert_eq(ship.fuel, 0,
			"seed %d: a refused jump must not drive the tank negative" % seed_value)


func test_an_illegal_jump_does_not_move_the_rng() -> void:
	# A refused jump is, from the run's point of view, a question that was asked
	# and answered. If it rolled anything, a player mis-clicking would desync the
	# rest of the voyage from its seed.
	var stranger := _non_neighbour()
	var before := rng.state()
	for _i in POLLS:
		voyage.jump_to(stranger, ship)
	assert_eq(rng.state(), before,
		"%d refused jumps must leave the RNG stream exactly where it was" % POLLS)


# --- a legal jump ------------------------------------------------------------

func test_a_legal_jump_burns_exactly_one_jumps_worth_of_fuel() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var fuel_before := ship.fuel
		assert_true(voyage.jump_to(int(voyage.options()[0]), ship),
			"seed %d: the first jump out of the entry must succeed on a full tank" % seed_value)
		assert_eq(ship.fuel, fuel_before - Voyage.FUEL_PER_JUMP,
			"seed %d: a jump costs exactly FUEL_PER_JUMP — no rounding, no discount" % seed_value)


func test_a_legal_jump_moves_the_ship_counts_itself_and_marks_the_beacon() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var target := int(voyage.options()[0])
		var was_at := voyage.at
		var jumps_before := voyage.jumps_taken
		assert_true(voyage.jump_to(target, ship), "seed %d: fixture check — the jump must be legal" % seed_value)
		assert_eq(voyage.at, target, "seed %d: a completed jump must actually move the ship" % seed_value)
		assert_ne(voyage.at, was_at, "seed %d: the ship cannot end a jump where it started" % seed_value)
		assert_eq(voyage.jumps_taken, jumps_before + 1,
			"seed %d: jumps_taken drives the threat's grace period, so it must count every jump exactly once" % seed_value)
		assert_true(voyage.map.beacon(target).visited,
			"seed %d: arriving must mark the beacon visited, or the map cannot draw where you have been" % seed_value)
		assert_eq(voyage.current_beacon().index, target,
			"seed %d: current_beacon must follow `at`" % seed_value)
		assert_eq(int(voyage.current_kind()), int(voyage.map.kind_of(target)),
			"seed %d: current_kind must report the kind of the beacon actually arrived at" % seed_value)


func test_a_walked_route_only_ever_gains_ground() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var previous := voyage.current_column()
		var steps := 0
		while not voyage.at_boss() and steps < WALK_GUARD:
			voyage.jump_to(int(voyage.options()[0]), ship)
			assert_eq(voyage.current_column(), previous + 1,
				"seed %d: each jump advances exactly one column, so progress and the threat measure in the same units" % seed_value)
			previous = voyage.current_column()
			steps += 1
		assert_eq(voyage.jumps_taken, steps,
			"seed %d: jumps_taken must equal the jumps actually made" % seed_value)


# --- threat pacing, §6 / §13 row 4 -------------------------------------------

func test_the_threat_holds_still_through_the_grace_jumps() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		for step in Voyage.THREAT_GRACE_JUMPS:
			voyage.jump_to(int(voyage.options()[0]), ship)
			assert_eq(voyage.threat_column, Voyage.THREAT_START_COLUMN,
				"seed %d: jump %d of the grace period must leave the threat where it started, so a sector opens calmly" % [
					seed_value, step + 1])
			assert_false(voyage.threat_at_player(),
				"seed %d: nobody can be overtaken during the grace period" % seed_value)


func test_the_threat_advances_one_step_per_jump_once_the_grace_is_spent() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		for _i in Voyage.THREAT_GRACE_JUMPS:
			voyage.jump_to(int(voyage.options()[0]), ship)
		var expected := Voyage.THREAT_START_COLUMN
		var extra := 0
		while not voyage.at_boss() and extra < WALK_GUARD:
			voyage.jump_to(int(voyage.options()[0]), ship)
			expected += Voyage.THREAT_COLUMNS_PER_JUMP
			extra += 1
			assert_eq(voyage.threat_column, expected,
				"seed %d: past the grace period every jump must move the threat exactly THREAT_COLUMNS_PER_JUMP" % seed_value)
		assert_true(extra > 0,
			"seed %d: the sector must be deeper than the grace period, or the threat never moves at all" % seed_value)


func test_each_sector_opens_with_its_own_threat_grace_period() -> void:
	# SUSPECTED CORE BUG — this test states the behaviour the contract describes,
	# not the behaviour core currently has.
	#
	# `THREAT_GRACE_JUMPS` is documented as "jumps of grace before the threat
	# starts moving at all, so A SECTOR opens calmly", and `_enter_sector` resets
	# `threat_column` to THREAT_START_COLUMN on every sector. But `jump_to` gates
	# the advance on `jumps_taken`, which is the VOYAGE total and is never reset —
	# so the grace is spent once, in sector 1, and sectors 2 and 3 open with the
	# threat moving from their very first jump. Observed clearance on a direct line
	# is 3 columns in sector 1 and 1 column in every sector after it.
	_walk_to_boss()
	voyage.clear_boss()
	assert_true(voyage.enter_next_sector(ship), "fixture check: sector 2 must open")
	assert_eq(voyage.threat_column, Voyage.THREAT_START_COLUMN,
		"a new sector resets the threat behind its entry column")
	for step in Voyage.THREAT_GRACE_JUMPS:
		voyage.jump_to(int(voyage.options()[0]), ship)
		assert_eq(voyage.threat_column, Voyage.THREAT_START_COLUMN,
			"jump %d of sector 2 is inside the grace period, so the threat must not have moved — the grace is per sector, which is what 'a sector opens calmly' means and what resetting threat_column per sector implies" % (step + 1))


func test_advance_threat_reports_its_new_column_and_closes_the_gap() -> void:
	var start := voyage.threat_column
	var distance := voyage.threat_distance()
	var returned := voyage.advance_threat()
	assert_eq(returned, start + Voyage.THREAT_COLUMNS_PER_JUMP,
		"advance_threat must return the column it moved to, so a caller need not re-read the field")
	assert_eq(voyage.threat_column, returned, "the returned column must be the recorded column")
	assert_eq(voyage.threat_distance(), distance - Voyage.THREAT_COLUMNS_PER_JUMP,
		"the clear space between threat and ship must shrink by exactly what the threat gained")
	voyage.advance_threat()
	assert_true(voyage.threat_distance() < distance - 1,
		"repeated advances must keep closing the gap — the threat is the voyage's clock")


func test_threat_distance_is_the_gap_between_the_ships_column_and_the_threat() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		for _i in 4:
			assert_eq(voyage.threat_distance(), voyage.current_column() - voyage.threat_column,
				"seed %d: threat_distance is a derived reading of two columns and must never drift from them" % seed_value)
			voyage.advance_threat()


func test_threat_holds_exactly_the_columns_at_or_behind_it() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		for _push in 3:
			for index in voyage.map.size():
				var column := voyage.map.beacon(index).column
				assert_eq(voyage.threat_holds(index), column <= voyage.threat_column,
					"seed %d: beacon %d sits in column %d against a threat at %d — 'at or behind' is the whole rule and an off-by-one loses or saves the player wrongly" % [
						seed_value, index, column, voyage.threat_column])
			voyage.advance_threat()


func test_threat_holds_is_false_for_a_beacon_that_does_not_exist() -> void:
	for _i in 10:
		voyage.advance_threat()
	assert_false(voyage.threat_holds(-1),
		"an index off the map is not consumed by the threat, however far the threat has come")
	assert_false(voyage.threat_holds(voyage.map.size()),
		"one past the last beacon is not a beacon and must not read as taken")


# --- every EndReason, §6 -----------------------------------------------------

func test_a_healthy_voyage_reports_no_ending() -> void:
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.NONE),
		"a whole hull, a living crew and a distant threat is not an ending")
	assert_false(voyage.is_over(), "check_end reporting NONE must leave the voyage running")
	assert_false(voyage.was_won(), "a voyage in progress has not been won")


func test_hull_lost_when_the_hull_is_gone() -> void:
	ship.take_hull_damage(ship.hull_max)
	assert_true(ship.is_destroyed(), "fixture check: the hull must actually be gone")
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.HULL_LOST),
		"a destroyed hull is HULL_LOST — the ship is what carries the voyage")


func test_crew_lost_when_every_member_is_dead() -> void:
	_kill_the_whole_crew()
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.CREW_LOST),
		"an intact ship with nobody left alive is CREW_LOST — permadeath is the point")


func test_overtaken_when_the_threat_reaches_the_players_column() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var pushes := 0
		while not voyage.threat_at_player() and pushes < WALK_GUARD:
			voyage.advance_threat()
			pushes += 1
		assert_true(voyage.threat_holds(voyage.at),
			"seed %d: the threat must be able to reach the ship's own column" % seed_value)
		assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.OVERTAKEN),
			"seed %d: being inside the threat's column is OVERTAKEN, whatever the hull says" % seed_value)


func test_stranded_with_no_fuel_and_no_beacon_that_could_supply_it() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		# The entry is always SAFE (§7 step 5), so it cannot hand over fuel.
		assert_eq(int(voyage.map.kind_of(voyage.at)), int(SectorMap.NodeKind.SAFE),
			"seed %d: fixture check — the entry beacon is SAFE, so it is not a fuel source" % seed_value)
		ship.fuel = 0
		assert_false(voyage.options().is_empty(),
			"seed %d: fixture check — there are routes out, they just cannot be paid for" % seed_value)
		assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.STRANDED),
			"seed %d: routes you cannot pay for are no routes at all — that is STRANDED" % seed_value)
		ship.add_fuel(Voyage.FUEL_PER_JUMP)
		assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.NONE),
			"seed %d: one jump's fuel is enough to stop being stranded" % seed_value)


func test_parking_on_a_beacon_that_could_supply_fuel_is_not_yet_stranded() -> void:
	# STORE and DISTRESS are the two kinds that plausibly hand over fuel, so a dry
	# tank there is a reprieve rather than an ending. `at` is written directly
	# because reaching a specific KIND depends on the roll, and what is being
	# pinned is the stranding rule, not the walk.
	var tested := 0
	for seed_value in SEEDS:
		_fixture(seed_value)
		for index in voyage.map.size():
			var kind := int(voyage.map.kind_of(index))
			if kind != int(SectorMap.NodeKind.STORE) and kind != int(SectorMap.NodeKind.DISTRESS):
				continue
			voyage.at = index
			ship.fuel = 0
			assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.NONE),
				"seed %d: a dry tank on a %s beacon is not STRANDED — the beacon itself is the way out" % [
					seed_value, SectorMap.kind_label(voyage.map.kind_of(index))])
			tested += 1
			break
	assert_true(tested > 0,
		"no seed produced a STORE or DISTRESS beacon at all, so the stranding reprieve was never exercised")


func test_sitting_at_the_boss_with_a_dry_tank_is_an_ending_not_a_stranding() -> void:
	# The boss is the last column and has no forward links, so "nowhere to go"
	# describes it permanently. Reporting STRANDED there would rob the player of
	# the fight they walked the whole sector to reach.
	_walk_to_boss()
	ship.fuel = 0
	assert_true(voyage.options().is_empty(), "fixture check: the boss beacon has no forward routes")
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.NONE),
		"a dry tank at the boss must not read as STRANDED — the boss is a gate, not a dead end")


func test_arriving_at_the_final_boss_is_not_victory_until_it_is_cleared() -> void:
	# THE ASSERTION THIS FILE EXISTS FOR. Without `boss_cleared`, docking at the
	# final beacon would declare VICTORY and the last fight would never happen.
	_reach_the_final_boss()
	assert_true(voyage.at_boss(), "fixture check: the ship must be at the boss beacon")
	assert_true(voyage.is_final_sector(), "fixture check: this must be the final sector")
	assert_false(voyage.boss_cleared, "fixture check: arriving must not have cleared anything")
	assert_ne(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.VICTORY),
		"standing on the final boss beacon is not beating it — VICTORY here would delete the boss fight from the game")
	voyage.clear_boss()
	assert_true(voyage.boss_cleared, "clear_boss at the boss beacon must record the win")
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.VICTORY),
		"the final sector's boss, beaten, is VICTORY — that is the only way to win")


func test_clearing_the_boss_only_counts_while_standing_at_it() -> void:
	assert_false(voyage.at_boss(), "fixture check: the entry is not the boss")
	voyage.clear_boss()
	assert_false(voyage.boss_cleared,
		"clear_boss away from the boss beacon must do nothing, or a caller could win the sector from its mouth")


func test_clearing_a_non_final_boss_is_not_victory() -> void:
	_walk_to_boss()
	voyage.clear_boss()
	assert_true(voyage.boss_cleared, "fixture check: sector 1's boss must be cleared")
	assert_false(voyage.is_final_sector(), "fixture check: sector 1 is not the last")
	assert_ne(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.VICTORY),
		"beating sector 1's boss opens the next sector; VICTORY needs the FINAL one, or the voyage is one sector long")


func test_victory_outranks_overtaken() -> void:
	_reach_the_final_boss()
	voyage.clear_boss()
	var pushes := 0
	while not voyage.threat_at_player() and pushes < WALK_GUARD:
		voyage.advance_threat()
		pushes += 1
	assert_true(voyage.threat_at_player(), "fixture check: the threat must have reached the ship")
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.VICTORY),
		"having beaten the final boss it no longer matters that the menace arrived — VICTORY must outrank OVERTAKEN")


func test_permadeath_outranks_victory() -> void:
	# A ship that reaches the end with nobody alive has not won it. CREW_LOST is
	# checked above VICTORY on purpose.
	_reach_the_final_boss()
	voyage.clear_boss()
	_kill_the_whole_crew()
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.CREW_LOST),
		"the last monkey dying at the finish line is CREW_LOST, not VICTORY — permadeath is not negotiable")


func test_hull_lost_outranks_every_other_reason() -> void:
	# Every condition true at once. HULL_LOST must win, because the ship being
	# torn open is the most physical of the endings and the one the player watched
	# happen.
	_reach_the_final_boss()
	voyage.clear_boss()
	while not voyage.threat_at_player():
		voyage.advance_threat()
	_kill_the_whole_crew()
	ship.fuel = 0
	ship.take_hull_damage(ship.hull_max * 2)
	assert_true(ship.is_destroyed(), "fixture check: the hull must be gone")
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.HULL_LOST),
		"with victory, permadeath, the threat and a dry tank all true, HULL_LOST must be the reason reported")


func test_every_end_reason_carries_player_facing_text_except_none() -> void:
	for reason in [Voyage.EndReason.VICTORY, Voyage.EndReason.HULL_LOST, Voyage.EndReason.CREW_LOST,
			Voyage.EndReason.STRANDED, Voyage.EndReason.OVERTAKEN]:
		assert_ne(Voyage.end_reason_text(reason), "",
			"reason %d must have something to show the player, or a voyage ends on a blank screen" % int(reason))
	assert_eq(Voyage.end_reason_text(Voyage.EndReason.NONE), "",
		"NONE is not an ending and must not announce itself")


# --- check_end is a PURE report ----------------------------------------------

func test_check_end_never_ends_the_voyage_however_often_it_is_called() -> void:
	ship.take_hull_damage(ship.hull_max)
	var before := _snapshot()
	for _i in POLLS:
		assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.HULL_LOST),
			"check_end must report the same reason every time it is asked")
		assert_false(voyage.ended,
			"check_end must REPORT the ending, never apply it — the caller decides when to look")
		assert_eq(int(voyage.end_reason), int(Voyage.EndReason.NONE),
			"check_end must not write end_reason")
	_assert_unchanged(before, "%d calls to check_end" % POLLS)


func test_every_read_only_question_on_the_voyage_is_free() -> void:
	# tests/unit/test_core_purity.gd's rule, applied here: a screen polls these on
	# every redraw, and a leaked draw would desync the run from its seed. The bug
	# this guards against is real — see that file's header.
	assert_eq(_state_after_polling(POLLS), _state_after_polling(0),
		"the voyage's read-only questions (options, can_jump_to, jump_reason, threat_holds, check_end and friends) consumed RNG draws across %d polls" % POLLS)


func test_check_end_survives_a_missing_ship_or_crew() -> void:
	# GameState builds these in stages, and a screen can ask before both exist.
	assert_eq(int(voyage.check_end(null, crew)), int(Voyage.EndReason.NONE),
		"a missing ship is not an ending — it is a caller that has not finished setting up")
	assert_eq(int(voyage.check_end(ship, null)), int(Voyage.EndReason.NONE),
		"a missing crew is not CREW_LOST — absent is not dead")
	assert_eq(int(voyage.check_end(null, null)), int(Voyage.EndReason.NONE),
		"neither present is still not an ending")


# --- end(), and life after it ------------------------------------------------

func test_end_is_idempotent_and_the_first_reason_wins() -> void:
	voyage.end(Voyage.EndReason.HULL_LOST)
	assert_true(voyage.ended, "end must actually end the voyage")
	assert_eq(int(voyage.end_reason), int(Voyage.EndReason.HULL_LOST), "the reason given must be recorded")
	voyage.end(Voyage.EndReason.CREW_LOST)
	assert_eq(int(voyage.end_reason), int(Voyage.EndReason.HULL_LOST),
		"the FIRST reason must stick — a caller polling check_end in a loop must not be able to overwrite the real cause of death")
	voyage.end(Voyage.EndReason.VICTORY)
	assert_eq(int(voyage.end_reason), int(Voyage.EndReason.HULL_LOST),
		"not even VICTORY may overwrite an ending already recorded")
	assert_false(voyage.was_won(), "a voyage that ended in HULL_LOST was not won")


func test_ending_with_no_reason_at_all_does_nothing() -> void:
	voyage.end(Voyage.EndReason.NONE)
	assert_false(voyage.ended, "NONE is not a reason to end anything")
	assert_eq(int(voyage.end_reason), int(Voyage.EndReason.NONE), "NONE must leave the record blank")


func test_settle_checks_and_ends_in_one_step() -> void:
	_kill_the_whole_crew()
	assert_eq(int(voyage.settle(ship, crew)), int(Voyage.EndReason.CREW_LOST),
		"settle must return the reason it found")
	assert_true(voyage.ended, "settle is the one that DOES end the voyage, unlike check_end")
	assert_eq(int(voyage.end_reason), int(Voyage.EndReason.CREW_LOST), "settle must record what it found")


func test_a_healthy_voyage_is_not_settled_by_being_asked() -> void:
	assert_eq(int(voyage.settle(ship, crew)), int(Voyage.EndReason.NONE),
		"settle on a healthy voyage reports NONE")
	assert_false(voyage.ended, "settle must not end a voyage that had no reason to end")


func test_once_ended_there_are_no_options_and_no_jump_succeeds() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		var target := int(voyage.options()[0])
		voyage.end(Voyage.EndReason.OVERTAKEN)
		assert_true(voyage.options().is_empty(),
			"seed %d: an ended voyage must offer no routes, or the map screen invites a jump into a finished run" % seed_value)
		assert_false(voyage.can_jump_to(target, ship),
			"seed %d: a route that was legal a moment ago must be refused once the voyage is over" % seed_value)
		var before := _snapshot()
		assert_false(voyage.jump_to(target, ship),
			"seed %d: jumping after the end must fail" % seed_value)
		_assert_unchanged(before, "seed %d: a jump attempted after the voyage ended" % seed_value)


func test_an_ended_voyage_cannot_open_another_sector() -> void:
	_walk_to_boss()
	voyage.clear_boss()
	voyage.end(Voyage.EndReason.HULL_LOST)
	var before := _snapshot()
	assert_false(voyage.enter_next_sector(ship),
		"a dead voyage must not sail on, however cleared the boss was")
	_assert_unchanged(before, "enter_next_sector on an ended voyage")


# --- enter_next_sector, §6 ---------------------------------------------------

func test_enter_next_sector_refuses_until_the_boss_is_actually_cleared() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		_walk_to_boss()
		assert_false(voyage.boss_cleared, "seed %d: fixture check — arriving clears nothing" % seed_value)
		var before := _snapshot()
		assert_false(voyage.enter_next_sector(ship),
			"seed %d: docking at the boss is not beating it, so the next sector must stay shut" % seed_value)
		_assert_unchanged(before, "seed %d: a refused enter_next_sector" % seed_value)


func test_enter_next_sector_refuses_away_from_the_boss() -> void:
	voyage.jump_to(int(voyage.options()[0]), ship)
	assert_false(voyage.at_boss(), "fixture check: one jump in is not the boss")
	voyage.boss_cleared = true
	var before := _snapshot()
	assert_false(voyage.enter_next_sector(ship),
		"the gate out of a sector is its boss beacon — a cleared flag elsewhere must not open it")
	_assert_unchanged(before, "enter_next_sector away from the boss")


func test_enter_next_sector_refuels_regenerates_and_resets_the_threat() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		_walk_to_boss()
		voyage.clear_boss()
		var old_map := voyage.map.to_dict()
		var fuel_before := ship.fuel
		var jumps_before := voyage.jumps_taken
		assert_true(voyage.enter_next_sector(ship),
			"seed %d: a cleared boss on a non-final sector must open the next one" % seed_value)
		assert_eq(voyage.sector, 2, "seed %d: clearing sector 1 puts the voyage in sector 2" % seed_value)
		assert_eq(ship.fuel, fuel_before + Voyage.SECTOR_CLEAR_FUEL,
			"seed %d: a cleared sector pays SECTOR_CLEAR_FUEL, or fuel spent early makes the last sector arithmetically unreachable" % seed_value)
		assert_ne(voyage.map.to_dict(), old_map,
			"seed %d: a new sector must be a NEW graph, not the old one walked again" % seed_value)
		assert_eq(voyage.map.sector, 2,
			"seed %d: the new map must know its own depth, since kind weights drift with it (§7 invariant 8)" % seed_value)
		assert_eq(voyage.at, voyage.map.entry,
			"seed %d: a new sector starts at its own entry beacon" % seed_value)
		assert_eq(voyage.current_column(), 0, "seed %d: the new entry is column 0" % seed_value)
		assert_false(voyage.boss_cleared,
			"seed %d: boss_cleared must reset, or sector 2 would be already beaten on arrival" % seed_value)
		assert_eq(voyage.threat_column, Voyage.THREAT_START_COLUMN,
			"seed %d: the threat resets behind the new entry, or the sector opens already lost" % seed_value)
		assert_false(voyage.threat_at_player(),
			"seed %d: a fresh sector cannot open with the ship already overtaken" % seed_value)
		assert_eq(voyage.jumps_taken, jumps_before,
			"seed %d: crossing a sector boundary is not itself a jump" % seed_value)


func test_enter_next_sector_refuses_on_the_final_sector() -> void:
	_reach_the_final_boss()
	voyage.clear_boss()
	assert_eq(voyage.sector, Voyage.SECTORS, "fixture check: the voyage must be on its last sector")
	var before := _snapshot()
	assert_false(voyage.enter_next_sector(ship),
		"there is nothing past the final sector — clearing its boss is VICTORY, not another jump")
	_assert_unchanged(before, "enter_next_sector on the final sector")
	assert_eq(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.VICTORY),
		"the final boss cleared must report VICTORY rather than silently stall the voyage")


# --- fuel arithmetic, §7 / §13 row 4 -----------------------------------------

func test_a_direct_line_through_a_sector_is_affordable_on_the_starter_tank() -> void:
	# ship.gd's FUEL_START comment and §7's own DIVERGENCE both claim a direct line
	# through a sector always makes it. Pinned across seeds, because "affordable"
	# must not depend on which graph came out.
	for seed_value in SEEDS:
		_fixture(seed_value)
		var spent := _walk_to_boss()
		assert_true(spent * Voyage.FUEL_PER_JUMP <= Ship.FUEL_START,
			"seed %d: a direct line cost %d fuel against a starter tank of %d — the contract promises it always makes it" % [
				seed_value, spent * Voyage.FUEL_PER_JUMP, Ship.FUEL_START])
		assert_true(ship.fuel > 0,
			"seed %d: the ship must reach the first boss with fuel to spare" % seed_value)
		assert_ne(int(voyage.check_end(ship, crew)), int(Voyage.EndReason.STRANDED),
			"seed %d: a player who flew straight must not be stranded at the first boss" % seed_value)


func test_every_route_through_a_sector_costs_exactly_the_same_fuel() -> void:
	# SUSPECTED CONTRACT ERROR, pinned as an observation rather than an aspiration.
	#
	# Links go forward exactly one column and there are COLUMNS columns, so EVERY
	# route from entry to boss is exactly COLUMNS - 1 jumps. Route choice therefore
	# cannot change what a sector costs, and the DIVERGENCE comments on
	# Ship.FUEL_START and SectorMap.COLUMNS — "a player who wanders greedily will
	# run dry before the boss", "a greedy detour through every beacon does not
	# [make it]" — describe a trade-off the geometry makes impossible.
	for seed_value in SEEDS:
		_fixture(seed_value)
		var direct := _walk_to_boss()
		assert_eq(direct, SectorMap.COLUMNS - 1,
			"seed %d: a sector is exactly COLUMNS - 1 jumps deep whichever way you fly it" % seed_value)
	# The whole voyage, before a single refuel, costs less than the starter tank.
	var worst_case := Voyage.SECTORS * (SectorMap.COLUMNS - 1) * Voyage.FUEL_PER_JUMP
	assert_true(worst_case <= Ship.FUEL_START,
		"the deepest possible voyage costs %d fuel against a starter tank of %d and %d more per sector cleared, so fuel cannot bind and STRANDED is unreachable by play" % [
			worst_case, Ship.FUEL_START, Voyage.SECTOR_CLEAR_FUEL])


func test_the_whole_voyage_is_walkable_end_to_end_under_every_seed() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		_reach_the_final_boss()
		voyage.clear_boss()
		assert_eq(int(voyage.settle(ship, crew)), int(Voyage.EndReason.VICTORY),
			"seed %d: a voyage flown straight through with nothing shooting back must be winnable" % seed_value)
		assert_true(voyage.was_won(), "seed %d: a VICTORY must read as won" % seed_value)
		assert_true(voyage.is_over(), "seed %d: a won voyage is over" % seed_value)
		assert_eq(voyage.jumps_taken, Voyage.SECTORS * (SectorMap.COLUMNS - 1),
			"seed %d: the shortest complete voyage is SECTORS x (COLUMNS - 1) jumps" % seed_value)


# --- serialisation, §6 -------------------------------------------------------

func test_to_dict_and_apply_dict_round_trip_every_field_and_the_map() -> void:
	for seed_value in SEEDS:
		_fixture(seed_value)
		_walk_to_boss()
		voyage.clear_boss()
		voyage.enter_next_sector(ship)
		voyage.jump_to(int(voyage.options()[0]), ship)
		voyage.advance_threat()

		var saved := voyage.to_dict()
		# A different seed on the restored voyage, so nothing can be reproduced by
		# accident: everything below must come out of the dictionary.
		var restored: Voyage = Voyage.new(rules, MpRng.new(seed_value + 7))
		restored.apply_dict(saved)

		assert_eq(restored.sector, voyage.sector, "seed %d: sector must survive a save" % seed_value)
		assert_eq(restored.at, voyage.at, "seed %d: the beacon the ship is at must survive a save" % seed_value)
		assert_eq(restored.jumps_taken, voyage.jumps_taken,
			"seed %d: jumps_taken must survive — it gates the threat's grace period" % seed_value)
		assert_eq(restored.threat_column, voyage.threat_column,
			"seed %d: the threat's column must survive, or a reload gives the pursuit back" % seed_value)
		assert_eq(restored.boss_cleared, voyage.boss_cleared,
			"seed %d: boss_cleared must survive, or a reload replays or skips the boss fight" % seed_value)
		assert_eq(restored.ended, voyage.ended, "seed %d: whether the voyage is over must survive" % seed_value)
		assert_eq(int(restored.end_reason), int(voyage.end_reason),
			"seed %d: the recorded ending must survive" % seed_value)
		assert_not_null(restored.map, "seed %d: a restored voyage needs its chart" % seed_value)
		assert_eq(restored.map.to_dict(), voyage.map.to_dict(),
			"seed %d: the map must round trip exactly — links, kinds, visited flags and all — or a reload redraws a different sector" % seed_value)
		assert_eq(restored.to_dict(), saved,
			"seed %d: to_dict -> apply_dict -> to_dict must be a fixed point" % seed_value)


func test_an_ended_voyage_round_trips_as_ended_for_the_same_reason() -> void:
	voyage.jump_to(int(voyage.options()[0]), ship)
	voyage.end(Voyage.EndReason.OVERTAKEN)
	var restored: Voyage = Voyage.new(rules, MpRng.new(SEED + 1))
	restored.apply_dict(voyage.to_dict())
	assert_true(restored.ended, "a loaded save of a finished voyage must still be finished")
	assert_eq(int(restored.end_reason), int(Voyage.EndReason.OVERTAKEN),
		"the cause of death must survive a save, or the end screen lies about what killed the run")
	assert_true(restored.options().is_empty(), "a restored dead voyage must offer no routes")


func test_apply_dict_on_an_empty_dictionary_leaves_a_safe_voyage() -> void:
	# Save files are read from disk and may be truncated or from an older build.
	var restored: Voyage = Voyage.new(rules, MpRng.new(SEED))
	restored.apply_dict({})
	assert_eq(restored.sector, 1, "a blank save must default to sector 1, not sector 0")
	assert_null(restored.map, "a blank save has no chart, and must say so rather than invent one")
	assert_true(restored.options().is_empty(), "a chartless voyage offers no routes")
	assert_false(restored.can_jump_to(0, ship), "a chartless voyage must refuse every jump")
	assert_eq(int(restored.check_end(ship, crew)), int(Voyage.EndReason.NONE),
		"a chartless voyage must not report an ending it cannot have reached")


func test_apply_dict_keeps_the_sector_inside_the_voyages_depth() -> void:
	var restored: Voyage = Voyage.new(rules, MpRng.new(SEED))
	restored.apply_dict({"sector": Voyage.SECTORS + 9, "at": -4, "jumps_taken": -3})
	assert_in_range(restored.sector, 1, Voyage.SECTORS,
		"a corrupt sector must be clamped into [1, SECTORS], or is_final_sector and the kind weights both go wrong")
	assert_true(restored.at >= 0, "a negative beacon index must be clamped, not passed on to the map")
	assert_true(restored.jumps_taken >= 0, "a negative jump count would hand the threat grace it never earned")


func test_two_voyages_on_the_same_seed_are_the_same_voyage() -> void:
	# The determinism guarantee the whole file rests on, stated outright.
	for seed_value in SEEDS:
		_fixture(seed_value)
		_walk_to_boss()
		var first := voyage.to_dict()
		var first_fuel := ship.fuel
		_fixture(seed_value)
		_walk_to_boss()
		assert_eq(voyage.to_dict(), first,
			"seed %d: the same seed and the same choices must produce a byte-identical voyage" % seed_value)
		assert_eq(ship.fuel, first_fuel,
			"seed %d: the same route must burn the same fuel" % seed_value)


func test_the_per_sector_jump_counter_survives_a_round_trip() -> void:
	# Added alongside the fix for the bug the test above found. The per-sector
	# grace period is gated on `jumps_this_sector`, so if that field did not
	# survive a save, reloading mid-sector would silently hand the player a fresh
	# grace period — or, worse, reloading in sector 2 would restore a counter of 0
	# and pause the threat that had already started moving.
	_walk_to_boss()
	var expected := voyage.jumps_this_sector
	assert_true(expected > 0,
		"fixture check: the walk must have made at least one jump, or this round trip proves nothing")

	var restored := Voyage.new(rules, MpRng.new(SEED))
	restored.apply_dict(voyage.to_dict())
	assert_eq(restored.jumps_this_sector, expected,
		"jumps_this_sector must survive a save, or the threat's grace period resets on reload")
	assert_eq(restored.jumps_taken, voyage.jumps_taken,
		"and the voyage odometer must survive alongside it")


func test_the_two_jump_counters_diverge_across_a_sector_boundary() -> void:
	# The whole point of having two counters. If a refactor ever collapses them
	# back into one, this is what says so.
	_walk_to_boss()
	var before_total := voyage.jumps_taken
	assert_eq(voyage.jumps_this_sector, before_total,
		"within sector 1 the two counters must agree, since no sector boundary has been crossed")

	voyage.clear_boss()
	assert_true(voyage.enter_next_sector(ship), "fixture check: sector 2 must open")
	assert_eq(voyage.jumps_this_sector, 0, "entering a sector must reset the per-sector counter")
	assert_eq(voyage.jumps_taken, before_total,
		"but must NOT reset the voyage odometer, which is a running total")

	voyage.jump_to(int(voyage.options()[0]), ship)
	assert_eq(voyage.jumps_this_sector, 1, "the per-sector counter counts from the sector's start")
	assert_eq(voyage.jumps_taken, before_total + 1, "the odometer keeps climbing")


func test_different_seeds_produce_different_voyages() -> void:
	# The other half of determinism: pinned seeds must not all collapse onto one
	# map, or every invariant above would be checked eight times against one graph.
	var charts: Array[String] = []
	for seed_value in SEEDS:
		_fixture(seed_value)
		var key := JSON.stringify(voyage.map.to_dict())
		assert_not_has(charts, key,
			"seed %d generated a chart identical to an earlier seed's, so the seed sweep is not actually sweeping anything" % seed_value)
		charts.append(key)
