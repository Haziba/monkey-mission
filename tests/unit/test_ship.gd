extends TestCase

## core/ship.gd — the hardware. MISSION-ARCHITECTURE §5, plus §3 for the
## station tables and §13 for the resolved `[X]` slots.
##
## `Ship` is HARDWARE ONLY: it never imports `Crew`, takes no `MpRng`, and every
## crew-dependent quantity arrives as a performance `float`. That is what makes
## this file possible at all — nothing below constructs a monkey.
##
## The three things this file exists to protect:
##
##  1. **The station tables are one table read three ways** (§3). Station -> stat,
##     station -> training activity, and `Training.stat_for` must agree, or a
##     gunner bred for POWER quietly mans the wrong console. SHIELDS <- STRENGTH
##     is the inherited naming trap: STRENGTH is the health bar and there is no
##     separate HP stat.
##  2. **Damage kills capability, not the request.** `damage_system` must lower
##     `effective_power` and leave `power_in` alone, and must not hand reactor
##     capacity back for reallocation. Everything about the power model follows
##     from that one distinction, so it is pinned from several directions.
##  3. **An unmanned station still works.** A voyage starts with 4 crew and 5
##     stations (§4), so `performance == 0.0` is a normal state, not an edge case:
##     powered hardware must still produce a non-zero floor rather than zero or a
##     crash. The curves are therefore pinned as *properties* — monotonic in
##     performance, bounded, degraded when offline — not as magic numbers.

const SEED := 20000324
## Enough polls that a leaked RNG draw per call cannot coincidentally land back
## on the same stream position. Matches tests/unit/test_core_purity.gd.
const POLLS := 7
## Sampled performance values, covering unmanned (0.0) through fully manned.
const PERFS := [0.0, 0.25, 0.5, 0.75, 1.0]

var ship: Ship


func before_each() -> void:
	ship = Ship.make_starter()


# --- fixtures --------------------------------------------------------------

## A starter with every bar pulled back to the reactor, so a test can build the
## exact power layout it means to talk about instead of depending on whatever
## default `make_starter` happens to hand out.
func _drained() -> Ship:
	var s := Ship.make_starter()
	for station in Ship.STATIONS:
		s.deallocate(station, Ship.REACTOR_MAX)
	return s


## One station at full bars, everything else dark.
func _only(station: int, bars: int = Ship.SYSTEM_BARS_MAX) -> Ship:
	var s := _drained()
	s.allocate(station, bars)
	return s


## One station powered and then knocked completely out.
func _offlined(station: int) -> Ship:
	var s := _only(station)
	s.damage_system(station, Ship.SYSTEM_BARS_MAX)
	return s


## A ship carrying every kind of state a save has to survive.
func _battle_worn() -> Ship:
	var s := _drained()
	s.allocate(int(Ship.Station.PILOT), 2)
	s.allocate(int(Ship.Station.SHIELDS), 3)
	s.allocate(int(Ship.Station.WEAPONS), 3)
	s.damage_system(int(Ship.Station.SHIELDS), 1)
	s.take_hull_damage(7)
	s.start_fire(int(Ship.Station.WEAPONS))
	s.open_breach(int(Ship.Station.SENSORS))
	s.burn_fuel(3)
	s.spend_missile()
	return s


## Everything a save round trip or an immutability check has to reproduce.
func _snapshot(s: Ship) -> Dictionary:
	var requested := []
	var knocked_out := []
	var working := []
	var burning := []
	var holed := []
	for station in Ship.STATIONS:
		requested.append(s.power_in(station))
		knocked_out.append(int(s.damage.get(station, 0)))
		working.append(s.effective_power(station))
		burning.append(bool(s.fires.get(station, false)))
		holed.append(bool(s.breaches.get(station, false)))
	return {
		"hull": s.hull,
		"hull_max": s.hull_max,
		"reactor": s.reactor,
		"fuel": s.fuel,
		"missiles": s.missiles,
		"power_in": requested,
		"damage": knocked_out,
		"effective": working,
		"fires": burning,
		"breaches": holed,
	}


## Every read-only question on the ship, called `times` times.
func _poll(s: Ship, times: int) -> void:
	for _i in times:
		s.power_used()
		s.power_free()
		s.is_destroyed()
		s.has_hazard()
		s.shield_layers_max()
		for station in Ship.STATIONS:
			s.power_in(station)
			s.effective_power(station)
			s.max_bars(station)
			s.is_offline(station)
		for p in PERFS:
			var perf := float(p)
			s.shield_recharge_rate(perf)
			s.evasion(perf, perf)
			s.weapon_charge_rate(perf)
			s.weapon_damage(perf)
			s.targeting_bonus(perf)
			s.jump_charge_rate(perf)


## The reactor budget must balance after every single operation, whatever it was.
func _assert_budget_balances(s: Ship, context: String) -> void:
	assert_eq(s.power_used() + s.power_free(), s.reactor,
		"%s: power_used + power_free must always equal the reactor, or the UI can offer bars that do not exist" % context)
	assert_true(s.power_free() >= 0,
		"%s: power_free went negative, so the ship is drawing more than the reactor makes" % context)


## `curve` must never fall as performance rises: crew is a multiplier on top of
## hardware, so a better-manned station can never be worse.
func _assert_monotonic_in_performance(label: String, curve: Callable) -> void:
	var previous := -1.0
	for p in PERFS:
		var perf := float(p)
		var value := float(curve.call(perf))
		assert_true(value >= previous,
			"%s must never fall as crew performance rises (perf %s gave %s, previous gave %s)" % [
				label, perf, value, previous])
		previous = value


# --- the station tables, §3 -------------------------------------------------

func test_there_are_exactly_five_stations_and_the_tables_all_cover_them() -> void:
	# Five systems, not eight: §3 and §13 resolve oxygen/medbay/doors out of
	# existence, so 5 is contractual and a sixth entry anywhere is a bug.
	assert_eq(Ship.STATIONS.size(), 5, "the ship is five systems, 1:1 with the five stations (§3, §13 row 5)")
	assert_eq(Ship.STATION_LABELS.size(), Ship.STATIONS.size(), "every station needs exactly one label")
	assert_eq(Ship.STATION_STAT.size(), Ship.STATIONS.size(), "STATION_STAT must be total over the stations")
	assert_eq(Ship.STATION_ACTIVITY.size(), Ship.STATIONS.size(), "STATION_ACTIVITY must be total over the stations")
	for station in Ship.STATIONS:
		assert_true(Ship.STATION_STAT.has(station), "station %d has no keyed stat" % station)
		assert_true(Ship.STATION_ACTIVITY.has(station), "station %d has no training activity" % station)
		assert_eq(Ship.station_label(station), Ship.STATION_LABELS[station],
			"station_label must read STATION_LABELS, not a second copy of the names")
	# Stations are serialised as ints and used to index STATION_LABELS.
	# Renumbering would silently rewrite every save and mislabel every console.
	assert_eq(int(Ship.Station.PILOT), 0, "PILOT is station 0")
	assert_eq(int(Ship.Station.ENGINES), 1, "ENGINES is station 1")
	assert_eq(int(Ship.Station.WEAPONS), 2, "WEAPONS is station 2")
	assert_eq(int(Ship.Station.SHIELDS), 3, "SHIELDS is station 3")
	assert_eq(int(Ship.Station.SENSORS), 4, "SENSORS is station 4")
	for i in Ship.STATIONS.size():
		assert_eq(int(Ship.STATIONS[i]), i, "STATIONS must be in enum order so it can index the tables")


func test_the_station_to_stat_map_is_the_resolved_one_from_the_design() -> void:
	# §3: the 1:1 mapping is resolved, not open. SHIELDS <- STRENGTH is the
	# inherited naming trap — STRENGTH is the health bar, POWER is damage — so
	# swapping these two would look plausible and break both halves of the game.
	assert_eq(Ship.station_stat(int(Ship.Station.PILOT)), Monkey.Stat.SPEED, "PILOT reads SPEED (evasion)")
	assert_eq(Ship.station_stat(int(Ship.Station.ENGINES)), Monkey.Stat.STAMINA, "ENGINES reads STAMINA (endurance)")
	assert_eq(Ship.station_stat(int(Ship.Station.WEAPONS)), Monkey.Stat.POWER, "WEAPONS reads POWER (damage)")
	assert_eq(Ship.station_stat(int(Ship.Station.SHIELDS)), Monkey.Stat.STRENGTH, "SHIELDS reads STRENGTH — the health bar stat, deliberately")
	assert_eq(Ship.station_stat(int(Ship.Station.SENSORS)), Monkey.Stat.KNOWLEDGE, "SENSORS reads KNOWLEDGE (targeting, insight)")


func test_no_two_stations_share_a_stat_and_every_stat_has_a_station() -> void:
	# If two stations read one stat, breeding for that stat would double-dip and
	# one of the five stats would have no console at all.
	var seen := {}
	for station in Ship.STATIONS:
		var stat: int = Ship.station_stat(station)
		assert_false(seen.has(stat),
			"stat %s is keyed by two stations, which breaks the 1:1 bridge" % Monkey.stat_label(stat))
		seen[stat] = station
	for stat in Monkey.STATS:
		assert_true(seen.has(int(stat)),
			"%s has no station, so training it could never reach the ship" % Monkey.stat_label(stat))


func test_station_for_stat_round_trips_in_both_directions() -> void:
	for station in Ship.STATIONS:
		assert_eq(Ship.station_for_stat(Ship.station_stat(station)), station,
			"station -> stat -> station must return the same console (%s)" % Ship.station_label(station))
	for stat in Monkey.STATS:
		assert_eq(Ship.station_stat(Ship.station_for_stat(stat)), int(stat),
			"stat -> station -> stat must return the same stat (%s)" % Monkey.stat_label(stat))


func test_station_activity_agrees_with_trainings_own_activity_to_stat_table() -> void:
	# The mutual-consistency check that matters: the activity a station is
	# trained by must raise the stat that station reads. Two independent tables
	# (Ship's and Training's) have to say the same thing or beacon training
	# silently improves the wrong console.
	# SPARRING raises all five and is out of slice scope; a station keyed to it
	# would make the station<->activity map non-injective.
	var seen := {}
	for station in Ship.STATIONS:
		var activity: int = Ship.station_activity(station)
		assert_eq(Training.stat_for(activity), Ship.station_stat(station),
			"%s is trained by %s, which must raise %s" % [
				Ship.station_label(station), Training.display_name(activity),
				Monkey.stat_label(Ship.station_stat(station))])
		assert_ne(activity, int(Training.Activity.SPARRING),
			"%s must not be keyed to SPARRING — it raises all five stats" % Ship.station_label(station))
		assert_has(Training.SLICE_ACTIVITIES, activity,
			"%s is trained by an activity outside SLICE_ACTIVITIES" % Ship.station_label(station))
		assert_false(seen.has(activity), "activity %d trains two stations" % activity)
		seen[activity] = true


# --- construction and the shape of the constants ----------------------------

func test_the_reactor_can_never_fully_power_every_station() -> void:
	# The whole point of the power model (§13 row 11: free like FTL, capped by
	# REACTOR_START and SYSTEM_BARS_MAX) is that bars are scarce and the player
	# must choose. If the reactor could fill all five systems, allocation would
	# be a no-op screen.
	assert_true(Ship.REACTOR_START < Ship.STATIONS.size() * Ship.SYSTEM_BARS_MAX,
		"REACTOR_START must be short of 5 x SYSTEM_BARS_MAX or power allocation is a meaningless choice")
	assert_true(Ship.REACTOR_START <= Ship.REACTOR_MAX, "the starting reactor cannot exceed the reactor ceiling")
	assert_true(Ship.SYSTEM_BARS_MAX >= Ship.SHIELD_BARS_PER_LAYER,
		"a system must be able to hold at least one shield layer's worth of bars")
	assert_true(Ship.HULL_MAX > 0 and Ship.FUEL_START > 0 and Ship.MISSILES_START > 0,
		"a starter with no hull, no fuel or no missiles cannot begin a voyage")


func test_make_starter_is_a_flyable_undamaged_ship() -> void:
	assert_eq(ship.hull, ship.hull_max, "a voyage starts on a whole hull")
	assert_eq(ship.hull_max, Ship.HULL_MAX, "the starter's hull ceiling is the contract's HULL_MAX")
	assert_eq(ship.reactor, Ship.REACTOR_START, "the starter's reactor is REACTOR_START (§13 row 11)")
	assert_eq(ship.fuel, Ship.FUEL_START, "the starter carries FUEL_START jumps' worth of fuel (§13 row 4)")
	assert_eq(ship.missiles, Ship.MISSILES_START, "the starter carries MISSILES_START missiles")
	assert_false(ship.is_destroyed(), "a starter must not begin the voyage destroyed")
	assert_false(ship.has_hazard(), "a starter must not begin the voyage on fire or holed")
	for station in Ship.STATIONS:
		assert_eq(int(ship.damage.get(station, 0)), 0, "no station starts damaged")
		assert_false(ship.is_offline(station) and ship.power_in(station) > 0,
			"a powered station cannot start offline")
	_assert_budget_balances(ship, "make_starter")


func test_a_bare_ship_is_internally_consistent() -> void:
	# `Ship.new()` takes no arguments and must still answer every query without
	# crashing — UI code and `apply_dict` both start from one.
	var bare := Ship.new()
	_assert_budget_balances(bare, "Ship.new()")
	for station in Ship.STATIONS:
		assert_true(bare.power_in(station) >= 0, "a fresh ship cannot have negative bars requested")
		assert_in_range(bare.effective_power(station), 0, bare.max_bars(station),
			"effective_power must sit inside [0, max_bars] even before anything is allocated")


# --- power allocation, §5 ---------------------------------------------------

func test_allocate_moves_bars_from_free_to_used() -> void:
	var s := _drained()
	var free_before := s.power_free()
	assert_true(s.allocate(int(Ship.Station.WEAPONS), 2), "2 bars out of an empty reactor must be affordable")
	assert_eq(s.power_in(int(Ship.Station.WEAPONS)), 2, "allocate must record the request it accepted")
	assert_eq(s.power_used(), 2, "used power is the sum of the requests")
	assert_eq(s.power_free(), free_before - 2, "allocated bars must leave the free pool")
	_assert_budget_balances(s, "after allocate")


func test_the_reactor_budget_balances_through_a_whole_sequence() -> void:
	var s := _drained()
	s.allocate(int(Ship.Station.SHIELDS), 4)
	_assert_budget_balances(s, "shields up")
	s.allocate(int(Ship.Station.ENGINES), 3)
	_assert_budget_balances(s, "engines up")
	s.allocate(int(Ship.Station.PILOT), 4)   # must be refused: only 1 bar free
	_assert_budget_balances(s, "after a refused allocation")
	s.damage_system(int(Ship.Station.SHIELDS), 2)
	_assert_budget_balances(s, "after damage")
	s.deallocate(int(Ship.Station.ENGINES), 2)
	_assert_budget_balances(s, "after deallocate")
	s.repair_system(int(Ship.Station.SHIELDS), 2)
	_assert_budget_balances(s, "after repair")


func test_allocate_fails_when_the_free_pool_is_short() -> void:
	var s := _drained()
	s.allocate(int(Ship.Station.PILOT), 4)
	s.allocate(int(Ship.Station.ENGINES), 4)
	assert_eq(s.power_free(), 0,
		"the fixture must have committed the whole reactor — 8 bars is REACTOR_START and the reason a 5th station runs dark")
	assert_false(s.allocate(int(Ship.Station.WEAPONS), 1),
		"a single bar must be refused when the reactor has nothing free, even though the station itself has room")
	assert_eq(s.power_in(int(Ship.Station.WEAPONS)), 0,
		"a refused allocation must be all-or-nothing — no partial bars may land")
	s.deallocate(int(Ship.Station.PILOT), 1)
	assert_false(s.allocate(int(Ship.Station.WEAPONS), 2),
		"a request larger than the free pool must be refused outright, not clamped down to what fits")
	assert_eq(s.power_in(int(Ship.Station.WEAPONS)), 0, "a partially affordable request must land no bars at all")
	_assert_budget_balances(s, "after a short request")


func test_allocate_refuses_to_push_a_station_past_system_bars_max() -> void:
	var s := _drained()
	assert_true(s.allocate(int(Ship.Station.SENSORS), Ship.SYSTEM_BARS_MAX),
		"a station must accept bars right up to SYSTEM_BARS_MAX")
	assert_false(s.allocate(int(Ship.Station.SENSORS), 1),
		"a full station must refuse a further bar even when the reactor has spare")
	assert_eq(s.power_in(int(Ship.Station.SENSORS)), Ship.SYSTEM_BARS_MAX,
		"a refused over-allocation must leave the existing request untouched")
	assert_true(s.power_free() > 0, "the reactor still had spare bars, so shortage was not the reason")

	var fresh := _drained()
	assert_false(fresh.allocate(int(Ship.Station.SENSORS), Ship.SYSTEM_BARS_MAX + 1),
		"a single oversized request must be refused outright")
	assert_eq(fresh.power_in(int(Ship.Station.SENSORS)), 0,
		"an oversized request must not land partially")


func test_deallocate_clamps_at_zero_instead_of_underflowing() -> void:
	var s := _only(int(Ship.Station.PILOT), 2)
	s.deallocate(int(Ship.Station.PILOT), 99)
	assert_eq(s.power_in(int(Ship.Station.PILOT)), 0,
		"deallocating more than was allocated must clamp to zero, never go negative")
	assert_eq(s.power_used(), 0, "the over-deallocation must not credit the reactor with bars it never lent")
	assert_eq(s.power_free(), s.reactor, "every bar is back in the pool")
	_assert_budget_balances(s, "after over-deallocation")


func test_a_nonsense_bar_count_cannot_corrupt_the_power_budget() -> void:
	# Whether these are refused or clamped is the implementation's business; what
	# must never happen is a negative request or a reactor that stops balancing,
	# because every downstream reading of power_free trusts it.
	var s := _only(int(Ship.Station.WEAPONS), 2)
	s.allocate(int(Ship.Station.WEAPONS), -3)
	assert_true(s.power_in(int(Ship.Station.WEAPONS)) >= 0, "a negative allocation must not create negative bars")
	_assert_budget_balances(s, "after a negative allocate")
	s.deallocate(int(Ship.Station.WEAPONS), -3)
	assert_true(s.power_in(int(Ship.Station.WEAPONS)) >= 0, "a negative deallocation must not create negative bars")
	assert_in_range(s.power_in(int(Ship.Station.WEAPONS)), 0, Ship.SYSTEM_BARS_MAX,
		"a negative deallocation must not be a backdoor past SYSTEM_BARS_MAX")
	_assert_budget_balances(s, "after a negative deallocate")


# --- damage and repair, §5 --------------------------------------------------

func test_damage_reduces_effective_power_but_never_the_request() -> void:
	# THE HEART OF THE MODEL. The request is what the player asked for and it
	# survives being shot; the capability is what the hardware can still deliver.
	# Collapsing the two would make repair unable to know where to return to.
	var s := _only(int(Ship.Station.SHIELDS))
	assert_eq(s.effective_power(int(Ship.Station.SHIELDS)), Ship.SYSTEM_BARS_MAX,
		"an undamaged, fully powered station delivers every bar it was given")
	s.damage_system(int(Ship.Station.SHIELDS), 2)
	assert_eq(s.power_in(int(Ship.Station.SHIELDS)), Ship.SYSTEM_BARS_MAX,
		"damage must NOT reduce power_in — the player's request survives the hit")
	assert_eq(s.effective_power(int(Ship.Station.SHIELDS)), Ship.SYSTEM_BARS_MAX - 2,
		"damage must reduce effective_power by the bars knocked out")
	assert_eq(int(s.damage.get(int(Ship.Station.SHIELDS), 0)), 2, "the damage table records the knocked-out bars")


func test_damage_does_not_hand_reactor_capacity_back() -> void:
	# If a damaged system released its bars, being shot would become a free
	# reroute — and the surviving request plus the reallocation would together
	# over-commit the reactor.
	var s := _drained()
	s.allocate(int(Ship.Station.WEAPONS), 4)
	var used_before := s.power_used()
	var free_before := s.power_free()
	s.damage_system(int(Ship.Station.WEAPONS), 3)
	assert_eq(s.power_used(), used_before, "damage must not release the reactor bars the request still holds")
	assert_eq(s.power_free(), free_before, "being shot is not a source of free power")
	_assert_budget_balances(s, "after damage")


func test_repair_restores_capability_up_to_the_surviving_request() -> void:
	# Damage eats CAPACITY (max_bars - damage), and the request is then capped by
	# what capacity survives — it does not subtract from the request directly.
	# With 3 bars requested of a possible 4, the first point of damage lands on
	# the unallocated headroom and costs nothing: capacity 3, request 3, output 3.
	# The second point bites, leaving capacity 2. Repairing one restores capacity
	# to 3, and the request was never lowered, so all 3 come back at once.
	#
	# This is FTL's own rule, and it is the reason `power_in` and `effective_power`
	# are separate: unpowered headroom is a damage buffer. See the distinguishing
	# case pinned in test_unallocated_headroom_absorbs_damage_before_output_does.
	var s := _only(int(Ship.Station.ENGINES), 3)
	s.damage_system(int(Ship.Station.ENGINES), 2)
	assert_eq(s.effective_power(int(Ship.Station.ENGINES)), 2,
		"two damage against a 4-capacity system leaves capacity 2, which caps a request of 3")
	s.repair_system(int(Ship.Station.ENGINES), 1)
	assert_eq(s.effective_power(int(Ship.Station.ENGINES)), 3,
		"repairing to capacity 3 restores the whole surviving request, which was never reduced")
	s.repair_system(int(Ship.Station.ENGINES), 99)
	assert_eq(s.effective_power(int(Ship.Station.ENGINES)), 3,
		"over-repair must restore the original request and stop there, not exceed it")
	assert_eq(s.power_in(int(Ship.Station.ENGINES)), 3, "repair must not alter the request either")
	assert_eq(int(s.damage.get(int(Ship.Station.ENGINES), 0)), 0, "a fully repaired system carries no damage")


func test_unallocated_headroom_absorbs_damage_before_output_does() -> void:
	# THE DISTINGUISHING CASE for the whole damage model, pinned on its own because
	# every other damage test here runs a station at full bars, where
	# "capacity minus damage" and "request minus damage" agree and the choice is
	# invisible. It only shows up when a system is running below its ceiling.
	#
	# The rule: damage removes CAPACITY from the top. Bars you never powered are
	# hit first and cost you nothing. Running a system below its ceiling is
	# therefore a real defensive choice, not just wasted potential — and a shot
	# into a half-powered system is partly absorbed.
	var s := _drained()
	s.allocate(int(Ship.Station.SHIELDS), 2)
	assert_eq(s.effective_power(int(Ship.Station.SHIELDS)), 2, "fixture: 2 of a possible 4 bars")

	var slack := Ship.SYSTEM_BARS_MAX - 2
	for absorbed in slack:
		s.damage_system(int(Ship.Station.SHIELDS), 1)
		assert_eq(s.effective_power(int(Ship.Station.SHIELDS)), 2,
			"damage %d of %d must land on unpowered headroom and cost no output" % [absorbed + 1, slack])

	s.damage_system(int(Ship.Station.SHIELDS), 1)
	assert_eq(s.effective_power(int(Ship.Station.SHIELDS)), 1,
		"once the headroom is gone, further damage finally costs output")
	assert_eq(s.power_in(int(Ship.Station.SHIELDS)), 2,
		"and the request is still untouched throughout, so repair knows where to return to")


func test_effective_power_stays_inside_zero_and_max_bars_under_abuse() -> void:
	var dark := _drained()
	for station in Ship.STATIONS:
		assert_true(dark.effective_power(station) <= dark.power_in(station),
			"an unpowered %s cannot deliver bars nobody allocated" % Ship.station_label(station))
	for station in Ship.STATIONS:
		var s := _only(station)
		s.damage_system(station, Ship.REACTOR_MAX * 4)
		assert_eq(s.effective_power(station), 0,
			"overkill damage must clamp effective_power at zero for %s, never go negative" % Ship.station_label(station))
		assert_in_range(s.effective_power(station), 0, s.max_bars(station),
			"effective_power must sit inside [0, max_bars] for %s" % Ship.station_label(station))
		assert_in_range(s.max_bars(station), 0, Ship.SYSTEM_BARS_MAX,
			"max_bars can never exceed SYSTEM_BARS_MAX for %s" % Ship.station_label(station))
		s.repair_system(station, Ship.REACTOR_MAX * 4)
		assert_eq(s.effective_power(station), Ship.SYSTEM_BARS_MAX,
			"overkill damage followed by overkill repair must return %s exactly to its request" % Ship.station_label(station))


func test_is_offline_tracks_a_fully_knocked_out_system() -> void:
	var s := _only(int(Ship.Station.WEAPONS))
	assert_false(s.is_offline(int(Ship.Station.WEAPONS)), "a powered, undamaged system is online")
	s.damage_system(int(Ship.Station.WEAPONS), Ship.SYSTEM_BARS_MAX - 1)
	assert_false(s.is_offline(int(Ship.Station.WEAPONS)),
		"a system with one bar left is crippled, not offline — the difference is whether it can act at all")
	s.damage_system(int(Ship.Station.WEAPONS), 1)
	assert_true(s.is_offline(int(Ship.Station.WEAPONS)), "a system with no working bars is offline")
	s.repair_system(int(Ship.Station.WEAPONS), 1)
	assert_false(s.is_offline(int(Ship.Station.WEAPONS)), "one repaired bar brings a system back")


func test_hull_damage_clamps_at_zero_and_destroys_the_ship() -> void:
	assert_false(ship.is_destroyed(), "a whole hull is not a destroyed ship")
	ship.take_hull_damage(ship.hull_max - 1)
	assert_eq(ship.hull, 1, "hull loss is subtractive")
	assert_false(ship.is_destroyed(), "one point of hull is still a live ship — permadeath must not fire early")
	ship.take_hull_damage(999)
	assert_eq(ship.hull, 0, "hull must clamp at zero, never go negative and read as a huge repair bill")
	assert_true(ship.is_destroyed(), "hull at zero is a destroyed ship")


func test_repair_hull_clamps_at_hull_max() -> void:
	var s := Ship.make_starter()
	s.take_hull_damage(10)
	s.repair_hull(4)
	assert_eq(s.hull, s.hull_max - 6, "repair adds to the hull")
	s.repair_hull(999)
	assert_eq(s.hull, s.hull_max, "repair must clamp at hull_max — no free hull upgrades from a repair station")
	assert_false(s.is_destroyed(), "a fully repaired hull is not destroyed")


func test_destroyed_fires_once_when_the_hull_reaches_zero() -> void:
	var destroyed_count := {"n": 0}
	var hull_reports: Array[int] = []
	ship.destroyed.connect(func() -> void: destroyed_count["n"] += 1)
	ship.hull_changed.connect(func(hull: int) -> void: hull_reports.append(hull))
	ship.take_hull_damage(5)
	assert_eq(destroyed_count["n"], 0, "a survivable hit must not announce destruction")
	assert_eq(hull_reports.size(), 1, "hull_changed must report each hull change once")
	assert_eq(hull_reports[0], ship.hull, "hull_changed must carry the hull the ship actually has")
	ship.take_hull_damage(999)
	assert_eq(destroyed_count["n"], 1,
		"destroyed must fire exactly once — the voyage's end-of-run handler is not idempotent")


# --- hazards, §5 ------------------------------------------------------------

func test_starting_and_extinguishing_a_fire_is_idempotent() -> void:
	var station := int(Ship.Station.ENGINES)
	assert_false(ship.has_hazard(), "no hazards to begin with")
	assert_true(ship.start_fire(station), "the first fire in a room must report that something changed")
	assert_true(bool(ship.fires.get(station, false)), "the fires table must reflect the new fire")
	assert_true(ship.has_hazard(), "a burning room is a hazard")
	assert_false(ship.start_fire(station), "a second fire in the same room changes nothing and must say so")
	assert_true(bool(ship.fires.get(station, false)), "the room is still on fire")
	assert_true(ship.extinguish(station), "putting the fire out must report the change")
	assert_false(bool(ship.fires.get(station, false)), "the fire is out")
	assert_false(ship.extinguish(station), "extinguishing a room that is not burning changes nothing")
	assert_false(ship.has_hazard(), "with the fire out there are no hazards left")


func test_opening_and_sealing_a_breach_is_idempotent_and_independent_of_fire() -> void:
	var breached := int(Ship.Station.SENSORS)
	var burning := int(Ship.Station.WEAPONS)
	assert_true(ship.open_breach(breached), "the first breach in a room must report the change")
	assert_true(bool(ship.breaches.get(breached, false)), "the breaches table must reflect the hole")
	assert_false(ship.open_breach(breached), "a second breach in the same room changes nothing")
	assert_false(bool(ship.fires.get(breached, false)), "a breach is not a fire")
	ship.start_fire(burning)
	assert_true(ship.seal(breached), "sealing must report the change")
	assert_true(ship.has_hazard(), "the fire in another room is still a hazard after the breach is sealed")
	assert_false(ship.seal(breached), "sealing a sealed room changes nothing")
	ship.extinguish(burning)
	assert_false(ship.has_hazard(), "with nothing burning and nothing holed there are no hazards")


func test_hazard_signals_only_fire_on_a_real_change() -> void:
	var fires_started: Array[int] = []
	var breaches_opened: Array[int] = []
	ship.fire_started.connect(func(station: int) -> void: fires_started.append(station))
	ship.breach_opened.connect(func(station: int) -> void: breaches_opened.append(station))
	ship.start_fire(int(Ship.Station.PILOT))
	ship.start_fire(int(Ship.Station.PILOT))
	ship.open_breach(int(Ship.Station.PILOT))
	ship.open_breach(int(Ship.Station.PILOT))
	assert_eq(fires_started.size(), 1, "a re-lit fire must not re-announce itself — the UI would double up its alarms")
	assert_eq(breaches_opened.size(), 1, "a re-opened breach must not re-announce itself")
	assert_eq(fires_started[0], int(Ship.Station.PILOT), "the signal must carry the room that caught fire")


# --- stores, §5 and §13 row 4 ----------------------------------------------

func test_fuel_is_spent_one_jump_at_a_time_and_can_be_topped_up() -> void:
	var before := ship.fuel
	assert_true(ship.burn_fuel(), "a fuelled ship must be able to jump")
	assert_eq(ship.fuel, before - 1, "the default jump costs exactly one fuel (§13 row 4)")
	ship.add_fuel(3)
	assert_eq(ship.fuel, before + 2, "salvaged fuel must actually arrive in the tank")
	assert_true(ship.burn_fuel(), "a refuelled ship can jump again")


func test_burn_fuel_refuses_at_zero_and_reports_it() -> void:
	ship.burn_fuel(ship.fuel)
	assert_eq(ship.fuel, 0, "the fixture must have emptied the tank")
	assert_false(ship.burn_fuel(), "a ship with no fuel must refuse to jump rather than go into debt")
	assert_eq(ship.fuel, 0, "a refused burn must not leave negative fuel — stranded is a state, not an error")


func test_spend_missile_refuses_at_zero() -> void:
	var before := ship.missiles
	assert_true(ship.spend_missile(), "a stocked ship can fire a missile")
	assert_eq(ship.missiles, before - 1, "a missile launch consumes exactly one missile")
	for _i in ship.missiles:
		ship.spend_missile()
	assert_eq(ship.missiles, 0, "the fixture must have emptied the magazine")
	assert_false(ship.spend_missile(), "an empty magazine must refuse rather than fire a missile that does not exist")
	assert_eq(ship.missiles, 0, "a refused launch must not leave negative missiles")


# --- the derived curves, §5 and §10 ---------------------------------------
#
# These are pinned as PROPERTIES, not numbers: the coefficients are DIVERGENCE
# choices and are expected to be tuned, but the shape of each curve is the
# contract. §10: "An unmanned station still works at its hardware level. Power
# alone gives a floor; crew is a multiplier on top" — a voyage starts with 4
# crew for 5 stations, so the unmanned case is normal play.

func test_shield_layers_come_from_bars_and_vanish_without_power() -> void:
	var dark := _drained()
	assert_eq(dark.shield_layers_max(), 0, "unpowered shields hold no layers")
	var full := _only(int(Ship.Station.SHIELDS))
	assert_eq(full.shield_layers_max(), Ship.SYSTEM_BARS_MAX / Ship.SHIELD_BARS_PER_LAYER,
		"SHIELD_BARS_PER_LAYER is the exchange rate between bars and layers, so a full system is exactly that many layers")
	var half := _only(int(Ship.Station.SHIELDS), Ship.SHIELD_BARS_PER_LAYER)
	assert_true(half.shield_layers_max() >= 1, "one layer's worth of bars must buy one layer")
	assert_true(half.shield_layers_max() <= full.shield_layers_max(),
		"layers must never fall as bars rise")
	assert_eq(_offlined(int(Ship.Station.SHIELDS)).shield_layers_max(), 0,
		"a shield system shot offline holds no layers however much power was requested")


func test_shield_recharge_rate_has_a_powered_floor_and_rises_with_crew() -> void:
	var s := _only(int(Ship.Station.SHIELDS))
	assert_true(s.shield_recharge_rate(0.0) > 0.0,
		"powered shields must recharge even with nobody at the station — one of five stations is unmanned all voyage")
	assert_true(s.shield_recharge_rate(1.0) > s.shield_recharge_rate(0.0),
		"a manned shield station must recharge strictly faster, or crew is decoration")
	_assert_monotonic_in_performance("shield_recharge_rate", func(p: float) -> float: return s.shield_recharge_rate(p))
	assert_almost_eq(_offlined(int(Ship.Station.SHIELDS)).shield_recharge_rate(1.0), 0.0, 0.0001,
		"offline shields do not recharge no matter who is standing there")


func test_evasion_is_a_probability_that_never_reaches_certainty() -> void:
	var s := _drained()
	s.allocate(int(Ship.Station.PILOT), Ship.SYSTEM_BARS_MAX)
	s.allocate(int(Ship.Station.ENGINES), Ship.SYSTEM_BARS_MAX)
	for p in PERFS:
		var perf := float(p)
		var value := s.evasion(perf, perf)
		assert_in_range(value, 0.0, 1.0, "evasion is a probability and must stay inside [0, 1] (perf %s)" % perf)
	assert_true(s.evasion(1.0, 1.0) < 1.0,
		"a perfectly crewed ship must still be hittable — total evasion would make combat unloseable")
	# And it stays a probability once the helm and engines have been shot out.
	var healthy := s.evasion(1.0, 1.0)
	s.damage_system(int(Ship.Station.PILOT), Ship.SYSTEM_BARS_MAX)
	s.damage_system(int(Ship.Station.ENGINES), Ship.SYSTEM_BARS_MAX)
	assert_true(s.evasion(1.0, 1.0) < healthy,
		"a ship with helm and engines offline must be easier to hit, whatever the crew are doing")
	assert_in_range(s.evasion(1.0, 1.0), 0.0, 1.0, "evasion stays a probability even with everything broken")


func test_evasion_rises_with_the_pilot_with_the_engines_and_with_power() -> void:
	var s := _drained()
	s.allocate(int(Ship.Station.PILOT), Ship.SYSTEM_BARS_MAX)
	s.allocate(int(Ship.Station.ENGINES), Ship.SYSTEM_BARS_MAX)
	_assert_monotonic_in_performance("evasion (pilot axis)", func(p: float) -> float: return s.evasion(p, 0.5))
	_assert_monotonic_in_performance("evasion (engines axis)", func(p: float) -> float: return s.evasion(0.5, p))
	assert_true(s.evasion(1.0, 1.0) > s.evasion(0.0, 0.0),
		"crewing both stations must beat crewing neither")
	assert_true(s.evasion(0.0, 0.0) > 0.0,
		"powered engines and helm must dodge something even unmanned — power alone is a floor (§10)")
	var dark := _drained()
	assert_true(s.evasion(0.5, 0.5) > dark.evasion(0.5, 0.5),
		"the same crew must dodge better with the engines powered than with them dark")


func test_weapon_charge_rate_has_a_powered_floor_and_rises_with_the_gunner() -> void:
	var s := _only(int(Ship.Station.WEAPONS))
	assert_true(s.weapon_charge_rate(0.0) > 0.0,
		"a powered but unmanned gun must still charge, or an early voyage could never shoot back")
	assert_true(s.weapon_charge_rate(1.0) > s.weapon_charge_rate(0.0), "a gunner must charge the gun strictly faster")
	_assert_monotonic_in_performance("weapon_charge_rate", func(p: float) -> float: return s.weapon_charge_rate(p))
	assert_almost_eq(_offlined(int(Ship.Station.WEAPONS)).weapon_charge_rate(1.0), 0.0, 0.0001,
		"an offline weapons system cannot charge at all")


func test_weapon_damage_is_at_least_one_when_powered_and_never_falls_with_crew() -> void:
	var s := _only(int(Ship.Station.WEAPONS))
	assert_true(s.weapon_damage(0.0) >= 1,
		"a powered gun must do at least one point of damage unmanned — a zero would make an unmanned gun pointless")
	assert_true(s.weapon_damage(1.0) >= s.weapon_damage(0.0), "a gunner must never reduce the gun's damage")
	_assert_monotonic_in_performance("weapon_damage", func(p: float) -> float: return float(s.weapon_damage(p)))
	assert_eq(_offlined(int(Ship.Station.WEAPONS)).weapon_damage(1.0), 0,
		"an offline weapons system deals no damage")
	var dark := _drained()
	assert_eq(dark.weapon_damage(1.0), 0, "an unpowered gun deals no damage however good the gunner")


func test_targeting_bonus_is_non_negative_monotonic_and_dies_with_sensors() -> void:
	var s := _only(int(Ship.Station.SENSORS))
	for p in PERFS:
		var perf := float(p)
		assert_true(s.targeting_bonus(perf) >= 0.0,
			"a targeting bonus must never be a penalty (perf %s)" % perf)
	_assert_monotonic_in_performance("targeting_bonus", func(p: float) -> float: return s.targeting_bonus(p))
	assert_true(s.targeting_bonus(1.0) > s.targeting_bonus(0.0),
		"a monkey reading the sensors must actually improve targeting — this is KNOWLEDGE's route to the ship")
	assert_almost_eq(_offlined(int(Ship.Station.SENSORS)).targeting_bonus(1.0), 0.0, 0.0001,
		"offline sensors give no targeting bonus")


func test_jump_charge_never_strands_a_ship_with_powered_but_unmanned_engines() -> void:
	var s := _only(int(Ship.Station.ENGINES))
	assert_true(s.jump_charge_rate(0.0) > 0.0,
		"powered engines must charge a jump unmanned — with 4 crew and 5 stations, otherwise a voyage could deadlock")
	assert_true(s.jump_charge_rate(1.0) > s.jump_charge_rate(0.0), "an engineer must charge the jump strictly faster")
	_assert_monotonic_in_performance("jump_charge_rate", func(p: float) -> float: return s.jump_charge_rate(p))
	assert_almost_eq(_offlined(int(Ship.Station.ENGINES)).jump_charge_rate(1.0), 0.0, 0.0001,
		"engines shot offline cannot charge a jump")


func test_every_curve_answers_sanely_on_a_completely_dark_ship() -> void:
	# The state after a reactor hit, and the state `Ship.new()` may start in.
	# Nothing here may crash, go negative, or return a NaN-ish surprise.
	var dark := _drained()
	assert_eq(dark.shield_layers_max(), 0, "no power, no shield layers")
	assert_true(dark.shield_recharge_rate(1.0) >= 0.0, "shield recharge on a dark ship is not negative")
	assert_in_range(dark.evasion(1.0, 1.0), 0.0, 1.0, "evasion on a dark ship is still a probability")
	assert_true(dark.weapon_charge_rate(1.0) >= 0.0, "weapon charge on a dark ship is not negative")
	assert_true(dark.weapon_damage(1.0) >= 0, "weapon damage on a dark ship is not negative")
	assert_true(dark.targeting_bonus(1.0) >= 0.0, "targeting bonus on a dark ship is not negative")
	assert_true(dark.jump_charge_rate(1.0) >= 0.0, "jump charge on a dark ship is not negative")


# --- serialisation, §5 ----------------------------------------------------

func test_to_dict_apply_dict_round_trips_the_whole_ship() -> void:
	var original := _battle_worn()
	var expected := _snapshot(original)
	var restored := Ship.new()
	restored.apply_dict(original.to_dict())
	assert_eq(JSON.stringify(_snapshot(restored)), JSON.stringify(expected),
		"a save round trip must reproduce hull, reactor, fuel, missiles, power, damage, fires and breaches exactly")
	_assert_budget_balances(restored, "restored ship")
	# And loading into a ship that has already been flown must overwrite it, not
	# merge — otherwise the old ship's fires keep burning in the loaded one.
	var starter := Ship.make_starter()
	var starter_state := JSON.stringify(_snapshot(starter))
	original.apply_dict(starter.to_dict())
	assert_eq(JSON.stringify(_snapshot(original)), starter_state,
		"apply_dict must replace the ship's state wholesale, not merge into whatever was already there")


func test_a_round_trip_survives_being_squeezed_through_json() -> void:
	# The project's save contract (ARCHITECTURE §15) writes enum-keyed
	# Dictionaries with int keys, and JSON hands them back as Strings with float
	# values. `Monkey.from_dict` already tolerates both shapes; so must this, or
	# every station's power and damage silently reset on load.
	var original := _battle_worn()
	var expected := _snapshot(original)
	var text := JSON.stringify(original.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_true(parsed is Dictionary, "to_dict must be JSON-serialisable — it is written straight to the save file")
	var restored := Ship.new()
	restored.apply_dict(parsed as Dictionary)
	assert_eq(JSON.stringify(_snapshot(restored)), JSON.stringify(expected),
		"a ship reloaded from JSON text must be identical — String keys and float ints must both be tolerated")


# --- purity, §0 and §12 ---------------------------------------------------

func test_ship_holds_no_rng_and_no_method_takes_one() -> void:
	# Structural, because it is the strongest form available: `Ship.new()` takes
	# no arguments and there is nowhere for a random source to live. A ship that
	# rolled dice inside a query would desync a voyage every time the UI redrew.
	var s := Ship.new()
	var offenders: Array[String] = []
	for property in s.get_property_list():
		var property_name := String((property as Dictionary).get("name", ""))
		if property_name.to_lower().contains("rng") or property_name.to_lower().contains("random"):
			offenders.append("property %s" % property_name)
	for method in s.get_method_list():
		var method_dict := method as Dictionary
		for arg in (method_dict.get("args", []) as Array):
			var arg_name := String((arg as Dictionary).get("name", ""))
			if arg_name.to_lower().contains("rng") or arg_name.to_lower().contains("random"):
				offenders.append("%s(%s)" % [method_dict.get("name", "?"), arg_name])
	assert_true(offenders.is_empty(),
		"Ship is hardware only and must never hold or accept an MpRng, but found: %s" % [offenders])


func test_no_ship_query_consumes_randomness() -> void:
	# Two halves. First: the injected stream a voyage replays from is untouched,
	# because Ship is never given one.
	var reference := MpRng.new(SEED)
	var live := MpRng.new(SEED)
	var expected := reference.randf()
	_poll(_battle_worn(), POLLS)
	assert_almost_eq(live.randf(), expected, 0.0000001,
		"polling the ship's queries must leave the voyage's RNG stream exactly where it was")
	# Second: no query reached for the global generator behind core's back, which
	# is the failure MpRng exists to prevent and which no seed can protect from.
	seed(SEED)
	var baseline := randi()
	seed(SEED)
	_poll(_battle_worn(), POLLS)
	assert_eq(randi(), baseline,
		"a ship query called the global randi() — core must go through MpRng, and read-only questions must roll nothing")


func test_asking_the_ship_questions_never_changes_the_ship() -> void:
	var s := _battle_worn()
	var before := JSON.stringify(_snapshot(s))
	_poll(s, POLLS)
	assert_eq(JSON.stringify(_snapshot(s)), before,
		"every is_*/power_*/rate query must be read-only — the UI polls them on every redraw")
