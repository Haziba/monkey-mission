extends TestCase

## core/voyage_state.gd — the disposable half of a playthrough.
##
## MISSION-ARCHITECTURE.md §6. `VoyageState` is what permadeath destroys: one
## ship, one crew, one sector chart, one purse. The bloodlines that outlive it are
## `StableState`'s job (phase 7) and deliberately absent here.
##
## The three things this file protects:
##
##  1. **A fresh voyage is playable and internally consistent.** Ship, crew,
##     chart, purse and systems all exist, and the crew is posted rather than
##     milling about.
##  2. **`Care` is SHARED between the crew and the feed screen.** One instance, so
##     "will this monkey work?" cannot be answered two different ways by the ship
##     and by the larder. A second `Care` would be a silent, awful bug.
##  3. **A reloaded voyage continues rather than replays.** The RNG stream
##     position is restored alongside the seed; restoring only the seed would make
##     every save-scum produce the same "random" sector.

const SEED := 20000324
const POLLS := 7


func _rules() -> GameRules:
	return GameRules.new()


func _fresh(seed_value: int = SEED) -> VoyageState:
	return VoyageState.new_voyage(_rules(), MpRng.new(seed_value))


# --- a fresh voyage is playable ------------------------------------------------

func test_a_fresh_voyage_has_every_part_it_needs() -> void:
	var state := _fresh()
	assert_not_null(state.rules, "a voyage without rules cannot answer any faithful question")
	assert_not_null(state.rng, "a voyage without an rng cannot be replayed from a seed")
	assert_not_null(state.ship, "there is no voyage without a ship")
	assert_not_null(state.crew, "there is no voyage without a crew")
	assert_not_null(state.voyage, "there is no voyage without a chart")
	assert_not_null(state.economy, "scrap and the larder have to live somewhere")
	assert_not_null(state.care, "feeding and availability need Care")
	assert_not_null(state.training, "beacon training needs Training")
	assert_false(state.is_over(), "a voyage must not begin already finished")


func test_a_fresh_voyage_starts_at_the_entry_beacon_of_sector_one() -> void:
	var state := _fresh()
	assert_eq(state.voyage.sector, 1, "a voyage opens in sector 1")
	assert_not_null(state.voyage.map, "sector 1 must have been generated")
	assert_eq(state.voyage.at, state.voyage.map.entry, "the ship starts at the chart's entry")
	assert_eq(state.voyage.jumps_taken, 0, "no jumps have been made yet")


func test_the_starting_crew_is_posted_and_leaves_one_station_empty() -> void:
	# Design §2.5: capacity 6, a voyage starts with 4, five stations. So a fresh
	# voyage has exactly one unmanned station and no spare bodies. This is the
	# design's stated opening condition, and it should fall out of the model
	# rather than being arranged.
	var state := _fresh()
	assert_eq(state.crew.size(), Crew.VOYAGE_START_SIZE,
		"a voyage starts with exactly VOYAGE_START_SIZE monkeys")
	assert_eq(state.crew.unmanned_stations().size(), Ship.STATIONS.size() - Crew.VOYAGE_START_SIZE,
		"four monkeys across five stations must leave exactly one console empty")
	assert_eq(state.crew.floaters().size(), 0,
		"and nobody spare, because auto_assign posts everyone it can")


func test_the_starting_crew_have_distinct_food_themed_names() -> void:
	var state := _fresh()
	var seen: Array[String] = []
	for member in state.crew.members:
		var monkey_name := member.monkey.monkey_name
		assert_true(monkey_name.strip_edges() != "", "every monkey must be named")
		assert_false(seen.has(monkey_name), "two crew must not share the name %s" % monkey_name)
		seen.append(monkey_name)


func test_the_starting_crew_must_still_be_won_over_with_food() -> void:
	# Dossier §5 [C]: befriending gates everything, Freddy included. A voyage
	# therefore opens with four monkeys at their posts and none of them yet
	# willing to work — the original's opening problem, restated in space. If this
	# ever passes trivially, the faithful rule has been softened.
	var state := _fresh()
	for member in state.crew.members:
		assert_false(member.monkey.is_befriended(),
			"%s must start unbefriended" % member.monkey.monkey_name)
		assert_false(state.crew.is_available(member),
			"%s must not work before it has been fed" % member.monkey.monkey_name)
	for station in Ship.STATIONS:
		assert_almost_eq(state.crew.station_performance(station), 0.0, 0.0001,
			"%s must read as unmanned until its monkey trusts the player" % Ship.station_label(station))


func test_a_fed_crew_starts_working() -> void:
	# The other half of the rule above: feeding is the thing that switches the ship
	# on, so this must actually be reachable.
	var state := _fresh()
	for member in state.crew.members:
		member.monkey.friendship = Monkey.FRIENDSHIP_MAX
	var working := 0
	for station in Ship.STATIONS:
		if state.crew.station_performance(station) > 0.0:
			working += 1
	assert_eq(working, Crew.VOYAGE_START_SIZE,
		"once befriended, every posted monkey must contribute at its station")


func test_the_larder_opens_stocked_so_the_crew_can_be_befriended_at_all() -> void:
	# Dossier §5 [C] documents the fastest befriending as two bananas. With an
	# unbefriended crew and an empty larder, a fresh voyage would be unwinnable
	# from the first frame.
	var state := _fresh()
	assert_true(state.economy.total_food() > 0, "a voyage must not open with an empty larder")
	assert_true(state.economy.food_count("banana") > 0,
		"bananas specifically, because they are the documented befriender")


func test_the_ship_opens_fuelled_and_whole() -> void:
	var state := _fresh()
	assert_eq(state.ship.hull, state.ship.hull_max, "a voyage opens with an undamaged hull")
	assert_true(state.ship.fuel >= Voyage.FUEL_PER_JUMP, "and with enough fuel to jump at least once")
	assert_false(state.ship.has_hazard(), "and with nothing on fire")
	assert_eq(state.ship.power_free(), 0,
		"make_starter spends the whole reactor, so the first real decision is what to rob")


# --- the shared Care instance --------------------------------------------------

func test_care_is_shared_between_the_state_and_the_crew() -> void:
	# THE BUG THIS EXISTS FOR: if VoyageState built one Care and Crew built
	# another, the ship and the feed screen would answer "can this monkey act?"
	# from two different objects. They would agree by luck for a while — both are
	# nearly stateless — and then diverge the moment either grows a cache.
	# Asserted behaviourally, since Crew's `_care` is private: a paralysis the
	# state's Care can see must be a paralysis the crew acts on.
	var state := _fresh()
	var member: Crew.Member = state.crew.members[0]
	member.monkey.friendship = Monkey.FRIENDSHIP_MAX
	var station := member.station
	assert_true(state.crew.station_performance(station) > 0.0,
		"fixture: a befriended monkey must be working before we paralyse it")

	# Overfeed it. `overfeeding_paralyses` is FAITHFUL and must reach the ship.
	member.monkey.fullness = Monkey.FULLNESS_MAX
	assert_true(state.care.is_paralysed(member.monkey),
		"the state's Care must see an overfed monkey as immobilised")
	assert_almost_eq(state.crew.station_performance(station), 0.0, 0.0001,
		"and the crew must agree, or the two are holding different Care instances")
	assert_true(state.crew.is_manned(station),
		"the monkey is still POSTED there — the crew sheet and the ship's output differ on purpose")


func test_an_overfed_monkey_is_immobilised_at_its_station_not_merely_wasteful() -> void:
	# design §10: never soften overfeeding to "wastes food".
	var state := _fresh()
	assert_true(state.rules.overfeeding_paralyses,
		"overfeeding_paralyses is FAITHFUL and must stay on")
	var member: Crew.Member = state.crew.members[0]
	member.monkey.friendship = Monkey.FRIENDSHIP_MAX
	member.monkey.fullness = Monkey.FULLNESS_MAX
	assert_false(state.crew.is_available(member), "a stuffed monkey cannot work")
	assert_true(state.crew.unavailable_reason(member).contains("CANNOT MOVE"),
		"and the player must be told why, in so many words")


# --- permadeath ----------------------------------------------------------------

func test_settle_reports_a_lost_hull() -> void:
	var state := _fresh()
	state.ship.take_hull_damage(state.ship.hull_max)
	assert_eq(state.settle(), Voyage.EndReason.HULL_LOST, "a destroyed hull must end the voyage")
	assert_true(state.is_over(), "and the voyage must know it is over")


func test_settle_reports_a_lost_crew() -> void:
	var state := _fresh()
	for member in state.crew.members:
		state.crew.kill(member)
	assert_eq(state.settle(), Voyage.EndReason.CREW_LOST, "losing the last monkey must end the voyage")
	assert_true(state.is_over(), "and the voyage must know it is over")


func test_an_incapacitated_crew_is_not_a_dead_crew() -> void:
	# The DIVERGENCE in crew.gd: zero Strength is out cold, not dead. A voyage
	# whose crew are all unconscious is in serious trouble but has not ended, and
	# must not report CREW_LOST.
	var state := _fresh()
	for member in state.crew.members:
		state.crew.hurt(member, member.monkey.max_strength() + 50)
		assert_true(state.crew.is_incapacitated(member), "fixture: the monkey must be out cold")
		assert_true(member.alive, "damage alone must never kill")
	assert_false(state.crew.all_dead(), "an unconscious crew is not a dead crew")
	assert_ne(state.settle(), Voyage.EndReason.CREW_LOST,
		"knocking the crew out must not be reported as permadeath")


func test_a_fresh_voyage_is_not_already_over() -> void:
	var state := _fresh()
	assert_eq(state.settle(), Voyage.EndReason.NONE,
		"nothing about a starting position may read as an ending")
	assert_false(state.is_over(), "and the voyage must still be live")


# --- flags ---------------------------------------------------------------------

func test_flags_default_to_false_and_round_trip() -> void:
	var state := _fresh()
	assert_false(state.has_flag("met_the_trader"), "an unset flag reads false")
	state.set_flag("met_the_trader")
	assert_true(state.has_flag("met_the_trader"), "a set flag reads true")
	state.set_flag("met_the_trader", false)
	assert_false(state.has_flag("met_the_trader"), "a flag can be cleared")


# --- determinism and serialisation ---------------------------------------------

func test_the_same_seed_builds_the_same_voyage() -> void:
	var first := _fresh(4242)
	var second := _fresh(4242)
	assert_eq(first.voyage.map.to_dict(), second.voyage.map.to_dict(),
		"one seed must always produce one chart, or nothing is reproducible")
	assert_eq(first.crew.names(), second.crew.names(),
		"and the same crew, names included")


func test_different_seeds_build_different_voyages() -> void:
	# Guards the opposite failure: a generator that ignores its rng would pass
	# every determinism test above and still be broken.
	var charts: Array[String] = []
	for seed_value in [11, 2222, 33333, 444444]:
		charts.append(JSON.stringify(_fresh(int(seed_value)).voyage.map.to_dict()))
	var distinct: Array[String] = []
	for chart in charts:
		if not distinct.has(chart):
			distinct.append(chart)
	assert_true(distinct.size() > 1,
		"four seeds producing one identical chart means the rng is not being consulted")


func test_a_voyage_survives_a_serialisation_round_trip() -> void:
	var state := _fresh(777)
	# Move it away from its starting position so the round trip has something to
	# get wrong.
	var options := state.voyage.options()
	assert_false(options.is_empty(), "fixture: the entry beacon must lead somewhere")
	state.voyage.jump_to(int(options[0]), state.ship)
	state.ship.take_hull_damage(5)
	state.ship.damage_system(int(Ship.Station.SHIELDS), 1)
	state.economy.scrap = 321
	state.set_flag("met_the_trader")

	var restored := VoyageState.from_dict(state.to_dict())
	assert_eq(restored.voyage.sector, state.voyage.sector, "the sector must survive")
	assert_eq(restored.voyage.at, state.voyage.at, "the ship's position must survive")
	assert_eq(restored.voyage.jumps_taken, state.voyage.jumps_taken, "the jump count must survive")
	assert_eq(restored.voyage.map.to_dict(), state.voyage.map.to_dict(), "the whole chart must survive")
	assert_eq(restored.ship.hull, state.ship.hull, "hull damage must survive")
	assert_eq(restored.ship.fuel, state.ship.fuel, "fuel must survive")
	assert_eq(restored.ship.effective_power(int(Ship.Station.SHIELDS)),
		state.ship.effective_power(int(Ship.Station.SHIELDS)), "system damage must survive")
	assert_eq(restored.economy.scrap, 321, "the purse must survive")
	assert_true(restored.has_flag("met_the_trader"), "flags must survive")
	assert_eq(restored.crew.size(), state.crew.size(), "the crew must survive")


func test_the_crew_survives_a_round_trip_with_stations_and_station_xp() -> void:
	# The in-run progress is the part permadeath is supposed to destroy, so it had
	# better be the part a legitimate reload preserves.
	var state := _fresh(999)
	var member: Crew.Member = state.crew.members[0]
	member.monkey.friendship = Monkey.FRIENDSHIP_MAX
	var station := member.station
	member.monkey.set_stat(Ship.station_stat(station), 120)
	state.crew.award_xp(member, station, 200.0)
	var expected_xp := member.xp_in(station)
	var expected_level := member.level_in(station)
	assert_true(expected_xp > 0.0, "fixture: the member must actually have banked xp")

	var restored := VoyageState.from_dict(state.to_dict())
	var restored_member: Crew.Member = restored.crew.members[0]
	assert_eq(restored_member.station, station, "the posting must survive")
	assert_almost_eq(restored_member.xp_in(station), expected_xp, 0.001, "station xp must survive")
	assert_eq(restored_member.level_in(station), expected_level, "and so must the level it bought")
	assert_eq(restored_member.monkey.monkey_name, member.monkey.monkey_name, "as must the monkey")


func test_a_reloaded_voyage_continues_the_stream_rather_than_replaying_it() -> void:
	# THE SAVE-SCUM BUG THIS PREVENTS: restoring only the SEED would rewind the
	# random stream to the start, so reloading would deal the same "random"
	# outcomes every time. The stream POSITION has to come back too.
	var state := _fresh(31337)
	for _i in 12:
		state.rng.randf()
	var expected_next := state.rng.state()

	var restored := VoyageState.from_dict(state.to_dict())
	assert_eq(restored.rng.state(), expected_next,
		"a restored voyage must resume the rng where it left off, not rewind to the seed")
	assert_eq(restored.rng.seed_value(), state.rng.seed_value(), "and remember which seed it came from")


func test_restoring_a_wrecked_dictionary_yields_something_usable() -> void:
	# A truncated or hand-edited save must not produce a half-built object that
	# crashes three screens later.
	var restored := VoyageState.from_dict({})
	assert_not_null(restored.ship, "a wrecked save must still yield a ship")
	assert_not_null(restored.crew, "and a crew object, even if empty")
	assert_not_null(restored.voyage, "and a voyage object")
	assert_not_null(restored.economy, "and a purse")
	assert_not_null(restored.care, "and Care, or nothing can be asked about the monkeys")
	assert_eq(restored.crew.size(), 0, "with no crew, rather than inventing one")


# --- rules isolation ----------------------------------------------------------

func test_two_voyages_do_not_share_a_rules_object() -> void:
	# The same trap RunState.new_run documents: GameRules.load_default() hands back
	# one cached resource, so without duplication two voyages flipping a flag would
	# see each other's changes — and in tests, one test would poison the next.
	var first := _fresh(1)
	var second := _fresh(2)
	assert_ne(first.rules, second.rules, "each voyage needs its own rules instance")
	first.rules.disobedience_enabled = false
	assert_true(second.rules.disobedience_enabled,
		"flipping one voyage's rules must not reach into another's")


func test_the_faithful_rules_are_on_by_default() -> void:
	# design §10: the user asked for these twice. A voyage that quietly ships with
	# them off is the failure this catches.
	var state := _fresh()
	assert_true(state.rules.disobedience_enabled,
		"disobedience_enabled is FAITHFUL and must survive the mutation")
	assert_true(state.rules.overfeeding_paralyses,
		"overfeeding_paralyses is FAITHFUL and must survive the mutation")


# --- purity -------------------------------------------------------------------

func test_asking_whether_the_voyage_is_over_is_free() -> void:
	# A screen will poll this every frame. tests/unit/test_core_purity.gd explains
	# why a leaked draw here would be so hard to find.
	var state := _fresh()
	var before := state.rng.state()
	for _i in POLLS:
		state.is_over()
		state.voyage.check_end(state.ship, state.crew)
		state.voyage.options()
		state.has_flag("anything")
	assert_eq(state.rng.state(), before,
		"read-only voyage questions must not move the rng, or polling desyncs the run")
