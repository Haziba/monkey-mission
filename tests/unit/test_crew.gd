extends TestCase

## Crew: the roster, the five station assignments, availability via `Care`, the
## two-axis leveling model and the food-themed name pool.
##
## MISSION-ARCHITECTURE §4 is the contract, §3 is the tie-breaker on the
## stat -> station map, §12 names this file as the home of "the 1:1 map,
## capacity 6 / start 4, floaters, availability via `Care`, two-axis leveling,
## the name pool".
##
## THE NAMING TRAP CARRIES OVER: STRENGTH is the health bar (Monkey §3 [C]), so
## SHIELDS is keyed to the same stat that a boarder's health is read from. There
## is no separate HP pool and this file must never invent one.
##
## THE OTHER TRAP, from §4's DIVERGENCE: `current_strength <= 0` INCAPACITATES.
## It does not kill. Death is only ever an explicit `kill()`.
##
## Everything here is pure core — no Node, no scene tree — and every MpRng is
## constructed with an explicit non-zero seed, because `MpRng.new(0)` seeds from
## the clock and a flaky test is worse than no test.

## Any non-zero value; pinned so a failure is reproducible.
const SEED := 20000324
## Enough polls that a single leaked RNG draw per call cannot coincidentally
## land the stream back where it started. Same figure test_core_purity.gd uses.
const POLLS := 7

## A deliberately hopeless stat, comfortably under every starter cap.
const LOW_STAT := 10
## A deliberately strong stat, still under the LOWEST starter cap (KNOWLEDGE 116)
## so `set_stat` never silently clamps a specialist back down.
const HIGH_STAT := 110

## Dossier §8 [C] / design §2.6, quoted in §4: the attested pool is exactly
## these nine, and they are food-themed by default.
const ATTESTED_NAMES: PackedStringArray = [
	"Freddy", "Agatha", "Lemon", "Betty", "Dragon", "Jimbo", "Tomato", "Cookie", "Pizza",
]

var rules: GameRules
var rng: MpRng
var care: Care
var crew: Crew


func before_each() -> void:
	rules = GameRules.new()
	rng = MpRng.new(SEED)
	# The SAME Care instance the crew reuses, so a test can ask Care directly and
	# prove the two agree rather than that they happen to compute the same thing.
	care = Care.new(rules, rng)
	crew = Crew.new(rules, rng, care)


# --- fixtures ---------------------------------------------------------------

## The stat -> station map from §3, written out independently of `Ship` so that a
## typo in `Ship.STATION_STAT` cannot make this file agree with itself and still
## be wrong. §3: "resolved, not open".
func _expected_station_stat() -> Dictionary:
	return {
		int(Ship.Station.PILOT): Monkey.Stat.SPEED,
		int(Ship.Station.ENGINES): Monkey.Stat.STAMINA,
		int(Ship.Station.WEAPONS): Monkey.Stat.POWER,
		int(Ship.Station.SHIELDS): Monkey.Stat.STRENGTH,
		int(Ship.Station.SENSORS): Monkey.Stat.KNOWLEDGE,
	}


func _keyed_stat(station: int) -> Monkey.Stat:
	return int(_expected_station_stat()[station]) as Monkey.Stat


## A real, fully-formed crew member's monkey.
##
## `RunState.make_starter` leaves friendship at 0 because day-1 Freddy has to be
## won over before he will do anything (dossier §5 [C]). A monkey that has been
## *recruited onto a ship* is past that, so friendship is maxed here — otherwise
## every availability fixture would be testing befriending instead of the thing
## it means to test.
func _monkey(name: String) -> Monkey:
	var monkey := RunState.make_starter()
	monkey.monkey_name = name
	monkey.friendship = Monkey.FRIENDSHIP_MAX
	monkey.fullness = RunState.STARTER_FULLNESS
	monkey.restore_pools()
	return monkey


## A monkey that is good at exactly one stat and hopeless at the other four.
## `restore_pools` runs last so the live health bar matches the new STRENGTH.
func _specialist(name: String, best: Monkey.Stat) -> Monkey:
	var monkey := _monkey(name)
	for stat in Monkey.STATS:
		monkey.set_stat(stat, LOW_STAT)
	monkey.set_stat(best, HIGH_STAT)
	monkey.restore_pools()
	return monkey


## A monkey whose keyed stat sits at its hard cap — the best a bloodline can do
## before breeding raises the ceiling.
func _capped_at(name: String, stat: Monkey.Stat) -> Monkey:
	var monkey := _monkey(name)
	monkey.set_stat(stat, monkey.get_cap(stat))
	monkey.restore_pools()
	return monkey


## An independently-built crew of station specialists, in station order.
## Two calls with the same `seed_value` and `count` are indistinguishable, which
## is what makes the auto_assign determinism test meaningful.
func _crew_of_specialists(seed_value: int, count: int) -> Crew:
	var own_rules := GameRules.new()
	var own_rng := MpRng.new(seed_value)
	var own_crew := Crew.new(own_rules, own_rng, Care.new(own_rules, own_rng))
	for i in count:
		var station: int = int(Ship.STATIONS[i % Ship.STATIONS.size()])
		own_crew.add(_specialist("Ace%d" % i, _keyed_stat(station)))
	return own_crew


## member name -> station, so two crews can be compared without comparing the
## Member objects themselves.
func _assignment_map(target: Crew) -> Dictionary:
	var out := {}
	for member in target.members:
		out[member.monkey.monkey_name] = member.station
	return out


## Everything that must be true of the roster/assignment views simultaneously.
##
## Only valid while every member is AVAILABLE: §4 says an unavailable member
## keeps its assignment and the station "reads as unmanned", which leaves it
## genuinely open whether `is_manned` follows `manning` or `effective_manning`.
## With a fully able crew both readings coincide, so this helper stays honest.
func _assert_roster_consistent(label: String) -> void:
	var held := {}
	for member in crew.members:
		if member.station == Crew.UNASSIGNED:
			continue
		assert_false(held.has(member.station),
			"%s: two members both hold station %d — a station is manned by at most one monkey"
				% [label, member.station])
		held[member.station] = member

	for station in Ship.STATIONS:
		var s := int(station)
		var holder: Crew.Member = crew.manning(s)
		if held.has(s):
			assert_eq(holder, held[s],
				"%s: manning(%d) must return the member whose .station says it is there" % [label, s])
			assert_true(crew.is_manned(s),
				"%s: is_manned(%d) must agree with manning(%d)" % [label, s, s])
			assert_not_has(crew.unmanned_stations(), s,
				"%s: station %d has a holder, so it cannot also be listed as unmanned" % [label, s])
		else:
			assert_null(holder,
				"%s: manning(%d) must be null when no member claims that station" % [label, s])
			assert_false(crew.is_manned(s),
				"%s: is_manned(%d) must be false when nobody claims it" % [label, s])
			assert_has(crew.unmanned_stations(), s,
				"%s: station %d has no holder, so it MUST be reported unmanned — a hidden gap in this list is a ship system silently running for free"
					% [label, s])

	for member in crew.members:
		if not member.alive:
			assert_not_has(crew.floaters(), member,
				"%s: a dead member is not a floater — you cannot reassign a corpse" % label)
		elif member.station == Crew.UNASSIGNED:
			assert_has(crew.floaters(), member,
				"%s: every living unassigned member must show up as a floater, or the UI cannot offer it to a station"
					% label)
		else:
			assert_not_has(crew.floaters(), member,
				"%s: a member at a station is not a floater" % label)

	assert_eq(crew.unmanned_stations().size() + held.size(), Ship.STATIONS.size(),
		"%s: manned + unmanned must account for every station exactly once" % label)


## The RNG must be in exactly the same place after `POLLS` calls as before them.
## See tests/unit/test_core_purity.gd for the real bug this pattern exists for.
func _assert_pure(label: String, body: Callable) -> void:
	var before := rng.state()
	for _i in POLLS:
		body.call()
	assert_eq(rng.state(), before,
		"%s is a read-only question but moved the shared RNG stream across %d polls — the run would desync every time the UI redrew"
			% [label, POLLS])


# --- the bridge: five stations, five stats, 1:1 -----------------------------

func test_the_station_stat_map_is_a_bijection_onto_the_five_monkey_stats() -> void:
	# §3: five stations, five stats, five training activities, one table. If this
	# stops being a bijection, some stat stops paying rent and some station reads
	# from a stat that another station also reads — the fusion's core claim.
	var expected := _expected_station_stat()
	assert_eq(Ship.STATIONS.size(), Monkey.STATS.size(),
		"the fusion is built on one station per stat; a mismatch means a stat no longer drives anything")
	var seen := {}
	for station in Ship.STATIONS:
		var s := int(station)
		var stat: int = int(Ship.STATION_STAT[s])
		assert_eq(stat, int(expected[s]),
			"station %s must be keyed to the stat §3 resolves it to" % Ship.STATION_LABELS[s])
		assert_false(seen.has(stat),
			"stat %s keys two stations — the map must be 1:1" % Monkey.STAT_LABELS[stat])
		seen[stat] = true
	assert_eq(seen.size(), Monkey.STATS.size(),
		"every one of the five stats must key exactly one station")

	# `UNASSIGNED` is stored in the same field as a Station, so it has to be a
	# value no station can ever take, or a floater reads as manning PILOT.
	assert_eq(Crew.UNASSIGNED, -1, "UNASSIGNED is serialised into saves; renumbering it rewrites every roster")
	assert_not_has(Ship.STATIONS, Crew.UNASSIGNED,
		"UNASSIGNED must not collide with a real station id")


# --- roster ----------------------------------------------------------------

func test_a_voyage_starts_one_monkey_short_of_a_full_bridge() -> void:
	# Design §2.5/§9 #6 RESOLVED: capacity 6, start 4. The numbers only matter
	# because of the arithmetic they create against five stations: a fresh voyage
	# ALWAYS has an unmanned station, and a full crew has exactly one spare body.
	# That is the stated starting condition, and it must be a supported state.
	assert_eq(Crew.CAPACITY, 6, "design §9 #6 resolves crew capacity to 6")
	assert_eq(Crew.VOYAGE_START_SIZE, 4, "design §9 #6 resolves the starting crew to 4")
	assert_eq(Ship.STATIONS.size(), 5, "design §9 #5 resolves the ship to five stations")
	assert_true(Crew.VOYAGE_START_SIZE < Crew.CAPACITY,
		"a voyage must start with room to recruit, or the crew can never grow")
	assert_eq(Ship.STATIONS.size() - Crew.VOYAGE_START_SIZE, 1,
		"exactly one station runs unmanned on day one — the design's stated opening tension")
	assert_eq(Crew.CAPACITY - Ship.STATIONS.size(), 1,
		"a full crew leaves at most one floater, so the sixth monkey is a spare and never a second gunner")


func test_add_fills_the_roster_up_to_capacity() -> void:
	for i in Crew.CAPACITY:
		var member: Crew.Member = crew.add(_monkey("Recruit%d" % i))
		assert_not_null(member, "recruit %d is within CAPACITY and must be accepted" % i)
		assert_eq(crew.size(), i + 1, "size() must count the member that was just added")
		assert_eq(member.monkey.monkey_name, "Recruit%d" % i,
			"the returned Member must wrap the monkey that was handed in")
		assert_eq(member.station, Crew.UNASSIGNED,
			"a new recruit starts as a floater — recruiting must never silently displace a working station")
		assert_true(member.alive, "a new recruit is alive")
		assert_eq(member.level_in(int(Ship.Station.WEAPONS)), 0,
			"in-run station levels start at zero: they are earned by DOING, and they died with the last crew")
	assert_false(crew.has_room(), "a crew of CAPACITY has no room left")


func test_the_seventh_recruit_is_refused_and_does_not_grow_the_roster() -> void:
	for i in Crew.CAPACITY:
		crew.add(_monkey("Recruit%d" % i))
	var overflow: Crew.Member = crew.add(_monkey("Seventh"))
	assert_null(overflow, "add() must return null at CAPACITY rather than a Member the crew does not hold")
	assert_eq(crew.size(), Crew.CAPACITY, "a refused recruit must not grow the roster")
	assert_eq(crew.members.size(), Crew.CAPACITY, "members must not gain a wrapper for a refused recruit")
	assert_null(crew.member_for(_monkey("Seventh")),
		"a refused recruit must not be findable afterwards")


func test_remove_frees_a_berth() -> void:
	var member: Crew.Member = crew.add(_monkey("Lemon"))
	crew.add(_monkey("Betty"))
	assert_true(crew.remove(member), "removing a held member reports success")
	assert_eq(crew.size(), 1, "remove() must shrink the roster")
	assert_null(crew.member_for(member.monkey), "a removed member is no longer findable")
	assert_false(crew.remove(member), "removing the same member twice must report failure, not corrupt the roster")
	assert_eq(crew.size(), 1, "the failed second remove must not shrink the roster again")
	assert_true(crew.has_room(), "a berth freed by remove() must be reusable")


func test_member_for_finds_the_wrapper_and_nothing_else() -> void:
	# The in-run station XP lives on the wrapper, never on the Monkey, so callers
	# holding only a Monkey need this lookup to be exact.
	var lemon := _monkey("Lemon")
	var betty := _monkey("Betty")
	var lemon_member: Crew.Member = crew.add(lemon)
	var betty_member: Crew.Member = crew.add(betty)
	assert_eq(crew.member_for(lemon), lemon_member, "member_for must return the wrapper for that exact monkey")
	assert_eq(crew.member_for(betty), betty_member, "member_for must not confuse two crew members")
	assert_ne(crew.member_for(lemon), betty_member, "member_for must not return an arbitrary wrapper")
	assert_null(crew.member_for(_monkey("Stranger")), "a monkey that is not aboard has no wrapper")


# --- assignment ------------------------------------------------------------

func test_assign_and_unassign_move_a_member_between_a_station_and_the_floaters() -> void:
	var pilot := int(Ship.Station.PILOT)
	var member: Crew.Member = crew.add(_specialist("Agatha", _keyed_stat(pilot)))
	assert_has(crew.floaters(), member, "an unassigned recruit is a floater")

	assert_true(crew.assign(member, pilot), "assigning a free member to a free station must succeed")
	assert_eq(member.station, pilot, "assign() must record the station on the member")
	assert_eq(crew.manning(pilot), member, "manning() must find the member just assigned")
	assert_true(crew.is_manned(pilot), "a station with an able holder is manned")
	_assert_roster_consistent("after assign")

	crew.unassign(member)
	assert_eq(member.station, Crew.UNASSIGNED, "unassign() must clear the member's station")
	assert_null(crew.manning(pilot), "an abandoned station reads as having nobody at it")
	_assert_roster_consistent("after unassign")


func test_assigning_over_an_incumbent_displaces_it() -> void:
	# §4: assign "displaces any current holder". The displaced monkey must land
	# somewhere real — a floater — and never be lost or left double-booked.
	var weapons := int(Ship.Station.WEAPONS)
	var incumbent: Crew.Member = crew.add(_monkey("Jimbo"))
	var usurper: Crew.Member = crew.add(_monkey("Dragon"))
	crew.assign(incumbent, weapons)

	assert_true(crew.assign(usurper, weapons), "assigning over an incumbent must succeed, not be refused")
	assert_eq(crew.manning(weapons), usurper, "the station must end up manned by the newcomer")
	assert_eq(incumbent.station, Crew.UNASSIGNED, "the displaced incumbent becomes a floater")
	assert_has(crew.floaters(), incumbent, "the displaced incumbent must be offerable to another station")
	assert_eq(crew.size(), 2, "displacement must not remove anybody from the crew")

	var holders := 0
	for member in crew.members:
		if member.station == weapons:
			holders += 1
	assert_eq(holders, 1, "exactly one member may hold a station after a displacement — two gunners double the ship's output")
	_assert_roster_consistent("after displacement")


func test_no_member_can_hold_two_stations() -> void:
	var weapons := int(Ship.Station.WEAPONS)
	var sensors := int(Ship.Station.SENSORS)
	var member: Crew.Member = crew.add(_monkey("Cookie"))
	crew.assign(member, weapons)
	crew.assign(member, sensors)

	assert_eq(member.station, sensors, "a re-assigned member holds only its newest station")
	assert_null(crew.manning(weapons), "the member's previous station must be vacated, not shared")
	assert_eq(crew.manning(sensors), member, "the member must be found at its new station")
	_assert_roster_consistent("after re-assignment")


func test_unmanned_stations_and_floaters_stay_consistent_through_a_reshuffle() -> void:
	# Every ship system reads its performance through these two views, so an
	# inconsistency here is a system running unmanned or running twice.
	var members: Array = []
	for i in Crew.CAPACITY:
		members.append(crew.add(_monkey("Recruit%d" % i)))
	_assert_roster_consistent("nobody assigned")
	assert_eq(crew.unmanned_stations().size(), Ship.STATIONS.size(), "with nobody assigned every station is unmanned")
	assert_eq(crew.floaters().size(), Crew.CAPACITY, "with nobody assigned everybody is a floater")

	for i in Ship.STATIONS.size():
		crew.assign(members[i], int(Ship.STATIONS[i]))
		_assert_roster_consistent("after assigning %d of %d" % [i + 1, Ship.STATIONS.size()])
	assert_eq(crew.unmanned_stations().size(), 0, "five members can cover all five stations")
	assert_eq(crew.floaters().size(), Crew.CAPACITY - Ship.STATIONS.size(),
		"the leftover crew are floaters, which is the spare body a full roster buys you")

	crew.unassign(members[0])
	_assert_roster_consistent("after vacating one station")
	assert_eq(crew.unmanned_stations().size(), 1, "vacating a station must reopen exactly one gap")


# --- auto_assign -----------------------------------------------------------

func test_auto_assign_puts_each_specialist_where_its_best_stat_pays() -> void:
	# Five monkeys, each hopeless except at one stat: the only sane assignment is
	# the identity one. This proves auto_assign reads the station map rather than
	# filling stations in enum order with whoever it saw first.
	for station in Ship.STATIONS:
		var s := int(station)
		crew.add(_specialist("Ace-%s" % Ship.STATION_LABELS[s], _keyed_stat(s)))
	crew.auto_assign()

	for station in Ship.STATIONS:
		var s := int(station)
		var holder: Crew.Member = crew.manning(s)
		assert_not_null(holder, "auto_assign must man station %s when a body is available" % Ship.STATION_LABELS[s])
		if holder != null:
			assert_eq(holder.monkey.monkey_name, "Ace-%s" % Ship.STATION_LABELS[s],
				"the %s specialist belongs at %s — that is what 'best-stat-first' means"
					% [Ship.STATION_LABELS[s], Ship.STATION_LABELS[s]])
	_assert_roster_consistent("after auto_assign of five specialists")


func test_auto_assign_on_a_voyage_start_crew_leaves_exactly_one_station_unmanned() -> void:
	# The stated opening condition. Four monkeys cannot cover five stations, and
	# that must be a supported state rather than a crash or a phantom holder.
	for i in Crew.VOYAGE_START_SIZE:
		crew.add(_specialist("Ace%d" % i, _keyed_stat(int(Ship.STATIONS[i]))))
	crew.auto_assign()

	assert_eq(crew.unmanned_stations().size(), Ship.STATIONS.size() - Crew.VOYAGE_START_SIZE,
		"a starting crew of four must leave exactly one station unmanned")
	assert_eq(crew.floaters().size(), 0,
		"auto_assign must not bench a monkey while a station stands empty")
	_assert_roster_consistent("after auto_assign at voyage start")

	var unmanned: Array[int] = crew.unmanned_stations()
	for s in unmanned:
		assert_almost_eq(crew.station_performance(int(s)), 0.0, 0.0001,
			"the unmanned station must simply produce nothing — an unmanned ship system is legal, not an error")


func test_auto_assign_with_a_full_crew_mans_every_station_and_benches_the_spare() -> void:
	for i in Crew.CAPACITY:
		crew.add(_specialist("Ace%d" % i, _keyed_stat(int(Ship.STATIONS[i % Ship.STATIONS.size()]))))
	crew.auto_assign()

	assert_eq(crew.unmanned_stations().size(), 0, "six monkeys must cover five stations")
	assert_eq(crew.floaters().size(), Crew.CAPACITY - Ship.STATIONS.size(),
		"the surplus monkey waits as a floater rather than doubling up on a station")
	_assert_roster_consistent("after auto_assign of a full crew")


func test_auto_assign_is_deterministic_under_a_pinned_seed() -> void:
	# Two crews built identically from the same seed must reach the same bridge.
	# Without this a voyage cannot be replayed from its seed, and every save/load
	# would silently reshuffle the ship.
	var first := _crew_of_specialists(SEED, Crew.CAPACITY)
	var second := _crew_of_specialists(SEED, Crew.CAPACITY)
	first.auto_assign()
	second.auto_assign()

	var a := _assignment_map(first)
	var b := _assignment_map(second)
	assert_eq(a.size(), b.size(), "two identically-built crews must have the same roster")
	for name in a:
		assert_true(b.has(name), "member %s is missing from the second crew" % name)
		assert_eq(int(b.get(name, Crew.UNASSIGNED)), int(a[name]),
			"member %s landed at a different station in an identically-seeded crew — auto_assign is not deterministic"
				% name)
	assert_true(first.unmanned_stations().is_empty(),
		"fixture check: a full crew should have covered every station")


# --- availability, which reuses Care --------------------------------------

func test_a_fresh_member_is_available_and_has_no_reason_not_to_be() -> void:
	var member: Crew.Member = crew.add(_monkey("Betty"))
	assert_true(crew.is_available(member), "a fed, bonded, healthy, living monkey can work")
	assert_eq(crew.unavailable_reason(member), "",
		"unavailable_reason must be empty exactly when the member is available — the UI greys a button on the string")
	assert_false(crew.is_incapacitated(member), "a monkey at full Strength is not incapacitated")


func test_a_paralysed_member_is_unavailable_and_care_agrees() -> void:
	# FAITHFUL and requested twice: GameRules.overfeeding_paralyses immobilises
	# the monkey AT ITS STATION. Never "wastes food". Crew must reach this
	# through Care rather than reimplementing the rule. Both of Care's immobility
	# channels are covered, because Crew must not pick only one of them up.
	assert_true(rules.overfeeding_paralyses, "fixture check: the faithful flag must still be on by default")

	var overfed: Crew.Member = crew.add(_monkey("Pizza"))
	overfed.monkey.fullness = Monkey.FULLNESS_MAX
	assert_true(care.is_paralysed(overfed.monkey), "fixture check: Care must call an overfed monkey paralysed")
	assert_false(crew.is_available(overfed),
		"an overfed monkey cannot work — Crew must agree with the Care instance it was handed")
	assert_ne(crew.unavailable_reason(overfed), "", "an unavailable member must explain itself to the player")

	var frozen: Crew.Member = crew.add(_monkey("Tomato"))
	frozen.monkey.paralysed_slots = 2
	assert_true(care.is_paralysed(frozen.monkey), "fixture check: paralysed_slots is Care's other immobility channel")
	assert_false(crew.is_available(frozen), "a monkey immobilised by paralysed_slots cannot work its station")
	assert_ne(crew.unavailable_reason(frozen), "", "immobility must be explained to the player")


func test_a_starving_member_is_unavailable_and_care_agrees() -> void:
	# Hunger is two-sided and BOTH extremes paralyse (Care §5 [C]).
	var member: Crew.Member = crew.add(_monkey("Lemon"))
	member.monkey.fullness = 0
	assert_true(member.monkey.is_starving(), "fixture check: fullness 0 is starving")
	assert_true(care.is_paralysed(member.monkey), "fixture check: Care treats starvation as immobilising")
	assert_false(crew.is_available(member), "a starving monkey cannot work its station")
	assert_ne(crew.unavailable_reason(member), "", "starvation must be explained so the player knows to feed it")


func test_a_dead_or_incapacitated_member_is_unavailable() -> void:
	var dead: Crew.Member = crew.add(_monkey("Dragon"))
	var downed: Crew.Member = crew.add(_monkey("Cookie"))
	crew.kill(dead)
	crew.hurt(downed, downed.monkey.max_strength())

	assert_false(crew.is_available(dead), "a dead member cannot work")
	assert_ne(crew.unavailable_reason(dead), "", "death must be reported as a reason")
	assert_true(crew.is_incapacitated(downed), "current_strength <= 0 is incapacitated")
	assert_false(crew.is_available(downed), "an incapacitated member cannot work")
	assert_ne(crew.unavailable_reason(downed), "", "being knocked out must be reported as a reason")


func test_unavailable_reason_is_empty_exactly_when_available() -> void:
	# One member per cause, so a future edit that adds a cause without a reason
	# string (or a reason string without a cause) is caught wherever it lands.
	var cases: Array = []
	cases.append(crew.add(_monkey("Able")))
	var starving: Crew.Member = crew.add(_monkey("Starving"))
	starving.monkey.fullness = 0
	cases.append(starving)
	var stuffed: Crew.Member = crew.add(_monkey("Stuffed"))
	stuffed.monkey.fullness = Monkey.FULLNESS_MAX
	cases.append(stuffed)
	var frozen: Crew.Member = crew.add(_monkey("Frozen"))
	frozen.monkey.paralysed_slots = 3
	cases.append(frozen)
	var downed: Crew.Member = crew.add(_monkey("Downed"))
	crew.hurt(downed, 9999)
	cases.append(downed)
	var dead: Crew.Member = crew.add(_monkey("Dead"))
	crew.kill(dead)
	cases.append(dead)

	for member in cases:
		var reason := crew.unavailable_reason(member)
		var available := crew.is_available(member)
		assert_eq(reason.is_empty(), available,
			"%s: unavailable_reason must be \"\" exactly when is_available is true, or the UI shows an empty message box"
				% member.monkey.monkey_name)


func test_an_unavailable_member_keeps_its_station_but_stops_manning_it() -> void:
	# THE most important behaviour in this file. §4: "An unavailable member keeps
	# its assignment. The station simply reads as unmanned until it recovers,
	# which is the correct texture: you can see who *should* be there."
	var weapons := int(Ship.Station.WEAPONS)
	var gunner: Crew.Member = crew.add(_specialist("Jimbo", _keyed_stat(weapons)))
	assert_true(crew.assign(gunner, weapons), "fixture check: the gunner must actually be assigned")
	assert_true(crew.station_performance(weapons) > 0.0,
		"fixture check: an able gunner must produce output before we take it away")

	gunner.monkey.fullness = Monkey.FULLNESS_MAX
	assert_false(crew.is_available(gunner), "fixture check: overfeeding must have immobilised the gunner")
	assert_eq(crew.manning(weapons), gunner,
		"the paralysed gunner KEEPS its station so the player can see who should be there")
	assert_eq(gunner.station, weapons, "an unavailable member must not be silently unassigned")
	assert_not_has(crew.floaters(), gunner, "a paralysed member at a station is not back in the floater pool")
	assert_null(crew.effective_manning(weapons),
		"effective_manning must report nobody ABLE at the station, which is what ship systems read")
	assert_almost_eq(crew.station_performance(weapons), 0.0, 0.0001,
		"a paralysed gunner must contribute exactly nothing — this is where overfeeding_paralyses reaches the ship")

	gunner.monkey.fullness = RunState.STARTER_FULLNESS
	assert_true(crew.is_available(gunner), "digesting must restore availability without re-assigning anybody")
	assert_eq(crew.effective_manning(weapons), gunner, "the recovered gunner is effective again at the station it kept")
	assert_true(crew.station_performance(weapons) > 0.0, "the recovered gunner must produce output again")


# --- performance ----------------------------------------------------------

func test_an_unmanned_station_has_nobody_effective_and_produces_nothing() -> void:
	# A voyage always starts with one of these, so it is a supported state and not
	# an error: no holder, nobody effective, zero output.
	var member: Crew.Member = crew.add(_monkey("Betty"))
	for station in Ship.STATIONS:
		assert_almost_eq(crew.station_performance(int(station)), 0.0, 0.0001,
			"station %s has nobody at it and must produce nothing" % Ship.STATION_LABELS[int(station)])
		assert_null(crew.effective_manning(int(station)),
			"nobody is effective at unmanned station %s, however able the crew is"
				% Ship.STATION_LABELS[int(station)])

	crew.assign(member, int(Ship.Station.SHIELDS))
	assert_eq(crew.effective_manning(int(Ship.Station.SHIELDS)), member,
		"an able holder must be reported as effective")
	assert_null(crew.effective_manning(int(Ship.Station.SENSORS)),
		"manning one station must not make its holder effective at another")


func test_station_performance_rises_with_the_keyed_stat() -> void:
	var shields := int(Ship.Station.SHIELDS)
	var stat := _keyed_stat(shields)
	var weak: Crew.Member = crew.add(_specialist("Weak", Monkey.Stat.KNOWLEDGE))
	var strong: Crew.Member = crew.add(_capped_at("Strong", stat))

	crew.assign(weak, shields)
	var weak_perf := crew.station_performance(shields)
	crew.assign(strong, shields)
	var strong_perf := crew.station_performance(shields)

	assert_true(weak_perf > 0.0, "even a poor monkey at a station beats nobody at it")
	assert_true(strong_perf > weak_perf,
		"a better-trained %s monkey must raise Shields output — otherwise training and breeding buy nothing"
			% Monkey.STAT_LABELS[stat])


func test_performance_reads_the_station_map_rather_than_one_hardcoded_stat() -> void:
	# The cross-check that catches "everything secretly reads POWER". Each
	# specialist must be strongest at ITS OWN station and weaker at all others.
	for station in Ship.STATIONS:
		var s := int(station)
		var ace: Crew.Member = crew.add(_specialist("Ace-%s" % Ship.STATION_LABELS[s], _keyed_stat(s)))
		var home := crew.performance_of(ace, s)
		for other in Ship.STATIONS:
			var o := int(other)
			if o == s:
				continue
			assert_true(home > crew.performance_of(ace, o),
				"the %s specialist must outperform itself at %s when placed at %s — the stat->station map is not being read"
					% [Ship.STATION_LABELS[s], Ship.STATION_LABELS[o], Ship.STATION_LABELS[s]])


func test_a_monkey_at_the_reference_stat_reads_as_a_fully_manned_station() -> void:
	# §0's DIVERGENCE: REFERENCE_STAT = 150 exists so "a station reads as 100%
	# manned at the same number the boxing sim already calls competent". That
	# relationship between the constant and the performance scale is the contract;
	# the number on its own means nothing.
	var sensors := int(Ship.Station.SENSORS)
	var stat := _keyed_stat(sensors)
	var monkey := _monkey("Reference")
	monkey.set_cap(stat, int(Crew.REFERENCE_STAT))
	monkey.set_stat(stat, int(Crew.REFERENCE_STAT))
	monkey.restore_pools()
	var member: Crew.Member = crew.add(monkey)

	assert_eq(member.level_in(sensors), 0, "fixture check: an untrained station level must be 0")
	assert_almost_eq(crew.performance_of(member, sensors), 1.0, 0.05,
		"a monkey whose keyed stat equals REFERENCE_STAT mans the station at 100%, with no station level yet")


# --- two-axis leveling: trained stat is the ceiling, XP is the climb -------

func test_the_level_ceiling_arithmetic_ties_the_three_constants_together() -> void:
	# STAT_PER_LEVEL * STATION_LEVEL_MAX == REFERENCE_STAT is the whole two-axis
	# model in one line: the trained stat that fully mans a station is exactly the
	# trained stat that unlocks the top station level. Breeding is what raises it.
	assert_true(Crew.STATION_LEVEL_MAX > 0, "there must be somewhere to climb to")
	assert_true(Crew.STAT_PER_LEVEL > 0, "a level must cost trained stat, or the ceiling is free")
	assert_eq(Crew.STAT_PER_LEVEL * Crew.STATION_LEVEL_MAX, int(Crew.REFERENCE_STAT),
		"the stat that fully mans a station must also be the stat that unlocks the last level, or the two axes drift apart")


func test_level_ceiling_rises_with_the_trained_stat() -> void:
	var weapons := int(Ship.Station.WEAPONS)
	var stat := _keyed_stat(weapons)
	var runt: Crew.Member = crew.add(_specialist("Runt", Monkey.Stat.KNOWLEDGE))
	var bred: Crew.Member = crew.add(_capped_at("Bred", stat))

	var low := crew.level_ceiling(runt, weapons)
	var high := crew.level_ceiling(bred, weapons)
	assert_in_range(low, 0, Crew.STATION_LEVEL_MAX, "a level ceiling must stay inside the level range")
	assert_in_range(high, 0, Crew.STATION_LEVEL_MAX, "a level ceiling must stay inside the level range")
	assert_true(high > low,
		"the trained %s stat sets the ceiling — a bred gunner must be allowed further than a runt" % Monkey.STAT_LABELS[stat])

	var maxed := _monkey("Maxed")
	maxed.set_cap(stat, int(Crew.REFERENCE_STAT))
	maxed.set_stat(stat, int(Crew.REFERENCE_STAT))
	var maxed_member: Crew.Member = crew.add(maxed)
	assert_eq(crew.level_ceiling(maxed_member, weapons), Crew.STATION_LEVEL_MAX,
		"a monkey at REFERENCE_STAT must be allowed the top station level, or the meta-progression has no payoff")


func test_award_xp_climbs_the_level_but_never_past_the_ceiling() -> void:
	var weapons := int(Ship.Station.WEAPONS)
	var bred: Crew.Member = crew.add(_capped_at("Bred", _keyed_stat(weapons)))
	var ceiling := crew.level_ceiling(bred, weapons)
	assert_true(ceiling > 0, "fixture check: a cap-trained gunner must have somewhere to climb")

	var level := crew.award_xp(bred, weapons, 1000000.0)
	assert_eq(level, bred.level_in(weapons), "award_xp must return the level it just produced")
	assert_true(level > 0, "XP earned by doing must actually raise the station level")
	assert_eq(level, ceiling, "an absurd amount of XP must saturate exactly at the ceiling, never above it")

	for _i in 5:
		crew.award_xp(bred, weapons, 1000000.0)
	assert_eq(bred.level_in(weapons), ceiling, "repeated XP awards must not creep past the ceiling")


func test_a_poorly_trained_monkey_can_never_reach_the_top_station_level() -> void:
	# The entire point of the ceiling, and the meta-progression hook: no amount of
	# in-run combat substitutes for a bloodline. If this fails, breeding is
	# pointless and the stable layer has nothing to sell.
	var weapons := int(Ship.Station.WEAPONS)
	var runt: Crew.Member = crew.add(_specialist("Runt", Monkey.Stat.KNOWLEDGE))
	var ceiling := crew.level_ceiling(runt, weapons)
	assert_true(ceiling < Crew.STATION_LEVEL_MAX,
		"a monkey with a near-zero POWER stat must not be allowed the top Weapons level")

	for _i in 20:
		crew.award_xp(runt, weapons, 1000000.0)
	assert_true(runt.level_in(weapons) <= ceiling, "the runt's level must respect its own ceiling")
	assert_true(runt.level_in(weapons) < Crew.STATION_LEVEL_MAX,
		"grinding must never buy what only breeding can: the runt must stay below STATION_LEVEL_MAX")


func test_station_xp_is_earned_per_station() -> void:
	# XP is earned by DOING a specific job. Gunnery experience must not make a
	# monkey a better pilot, or the five stations collapse into one stat.
	var weapons := int(Ship.Station.WEAPONS)
	var pilot := int(Ship.Station.PILOT)
	var member: Crew.Member = crew.add(_capped_at("Jimbo", _keyed_stat(weapons)))
	crew.award_xp(member, weapons, 1000000.0)

	assert_true(member.xp_in(weapons) > 0.0, "Weapons XP must be recorded against Weapons")
	assert_true(member.level_in(weapons) > 0, "fixture check: the Weapons level must have risen")
	assert_almost_eq(member.xp_in(pilot), 0.0, 0.0001, "earning Weapons XP must not credit the Pilot station")
	assert_eq(member.level_in(pilot), 0, "earning Weapons XP must not raise the Pilot level")


func test_xp_rate_rises_with_the_trained_stat() -> void:
	# §13 #2: the trained stat sets the RATE as well as the ceiling — "rate
	# 0.5 + stat/150". XP_RATE_FLOOR is what a completely untrained monkey still
	# earns, so it can never be zero: a bad crew must still improve, only slower.
	var engines := int(Ship.Station.ENGINES)
	var stat := _keyed_stat(engines)
	var runt: Crew.Member = crew.add(_specialist("Runt", Monkey.Stat.KNOWLEDGE))
	var bred: Crew.Member = crew.add(_capped_at("Bred", stat))

	assert_true(crew.xp_rate(runt, engines) >= Crew.XP_RATE_FLOOR,
		"even an untrained monkey earns at least the floor rate, or it can never get started")
	assert_true(crew.xp_rate(bred, engines) > crew.xp_rate(runt, engines),
		"a better-trained %s stat must earn station XP faster" % Monkey.STAT_LABELS[stat])

	var maxed := _monkey("Maxed")
	maxed.set_cap(stat, int(Crew.REFERENCE_STAT))
	maxed.set_stat(stat, int(Crew.REFERENCE_STAT))
	var maxed_member: Crew.Member = crew.add(maxed)
	assert_almost_eq(crew.xp_rate(maxed_member, engines), Crew.XP_RATE_FLOOR + Crew.XP_RATE_SPAN, 0.001,
		"at REFERENCE_STAT the rate must be exactly floor + span — the three constants define one curve, not three numbers")


func test_a_station_level_raises_performance_without_replacing_training() -> void:
	var weapons := int(Ship.Station.WEAPONS)
	var member: Crew.Member = crew.add(_capped_at("Bred", _keyed_stat(weapons)))
	crew.assign(member, weapons)
	var untrained := crew.station_performance(weapons)
	assert_true(crew.level_ceiling(member, weapons) > 0, "fixture check: this gunner must be able to level")

	crew.award_xp(member, weapons, 1000000.0)
	var levelled := crew.station_performance(weapons)
	assert_true(levelled > untrained,
		"station levels must feed performance, otherwise in-run XP is a number with no consequence")
	assert_true(levelled < untrained * 2.0,
		"levels are a bonus on top of the trained stat, not a replacement for it — LEVEL_BONUS * STATION_LEVEL_MAX must stay under 100%")


func test_award_station_xp_credits_whoever_mans_the_station() -> void:
	var weapons := int(Ship.Station.WEAPONS)
	var sensors := int(Ship.Station.SENSORS)
	var member: Crew.Member = crew.add(_capped_at("Jimbo", _keyed_stat(weapons)))
	crew.assign(member, weapons)

	var level := crew.award_station_xp(weapons, 1000000.0)
	assert_eq(level, member.level_in(weapons),
		"award_station_xp must credit the member actually at the station and report its new level")
	assert_true(level > 0, "combat at a manned station must move that member's level")
	assert_eq(crew.award_station_xp(sensors, 1000000.0), 0,
		"awarding XP to an unmanned station must be a harmless no-op, not a crash — an unmanned station is a legal state")
	assert_eq(member.level_in(sensors), 0, "XP for an unmanned station must not leak to another member's other station")


# --- health, through Monkey's existing pools -------------------------------

func test_hurt_returns_what_it_actually_applied_and_clamps_at_zero() -> void:
	var member: Crew.Member = crew.add(_monkey("Betty"))
	var pool := member.monkey.max_strength()
	assert_true(pool > 10, "fixture check: the starter's STRENGTH must be a real health bar")

	assert_eq(crew.hurt(member, 10), 10, "an absorbable hit applies in full")
	assert_eq(member.monkey.current_strength, pool - 10, "damage must come out of current_strength, the health bar")
	assert_eq(crew.hurt(member, 100000), pool - 10,
		"an overkill hit must report only the damage that landed, which is what the UI prints")
	assert_eq(member.monkey.current_strength, 0, "the health bar clamps at 0, never negative")
	assert_eq(crew.hurt(member, 5), 0, "hitting an already-downed member applies nothing")


func test_hurt_down_to_zero_incapacitates_but_never_kills() -> void:
	# §4's DIVERGENCE, and a load-bearing one: zero Strength is a KO, exactly as
	# it is in the boxing sim. If damage killed, reusing MatchResolver as boarding
	# melee in phase 6 would quietly become lethal.
	var member: Crew.Member = crew.add(_monkey("Freddy"))
	crew.hurt(member, 100000)

	assert_eq(member.monkey.current_strength, 0, "fixture check: the member must be at zero Strength")
	assert_true(crew.is_incapacitated(member), "current_strength <= 0 is incapacitated")
	assert_true(member.alive, "damage must NEVER kill — only an explicit kill() does")
	assert_false(crew.all_dead(), "an incapacitated crew is down, not dead: the voyage is not over")
	assert_has(crew.living(), member, "an incapacitated member is still living and can be healed back up")


func test_heal_is_bounded_by_max_strength() -> void:
	var member: Crew.Member = crew.add(_monkey("Betty"))
	var pool := member.monkey.max_strength()
	crew.hurt(member, 100000)

	assert_eq(crew.heal(member, 100000), pool,
		"heal must report what it actually restored — STRENGTH is the ceiling of its own health bar")
	assert_eq(member.monkey.current_strength, pool, "healing must not push the health bar above max_strength")
	assert_eq(crew.heal(member, 50), 0, "healing a full member restores nothing")
	assert_false(crew.is_incapacitated(member), "a healed member is back on its feet")


func test_kill_is_the_only_way_to_die_and_all_dead_needs_everybody() -> void:
	var first: Crew.Member = crew.add(_monkey("Dragon"))
	var second: Crew.Member = crew.add(_monkey("Cookie"))
	crew.assign(first, int(Ship.Station.PILOT))

	assert_false(crew.all_dead(), "a fresh crew is not dead")
	crew.kill(first)
	assert_false(first.alive, "kill() must actually kill")
	assert_not_has(crew.living(), first, "living() must exclude the dead")
	assert_has(crew.living(), second, "living() must still include the survivor")
	assert_false(crew.all_dead(), "all_dead must stay false while any member lives — permadeath needs the WHOLE crew")

	crew.kill(second)
	assert_true(crew.all_dead(), "all_dead must be true once every member is dead")
	assert_eq(crew.living().size(), 0, "no member survives an all-dead crew")
	assert_eq(crew.size(), 2, "the dead stay on the roster — the voyage summary has to name them")


# --- naming ---------------------------------------------------------------

func test_the_name_pool_holds_the_attested_food_themed_names() -> void:
	# Dossier §8 [C] via §4: the pool starts as exactly these nine, and anything
	# added is food-themed and DIVERGENCE-commented.
	assert_true(Crew.NAME_POOL.size() > 0, "an empty pool makes the Random button dead")

	# Folded to lower case on purpose. The original's UI prints names in caps and
	# `Monkey.name_line()` upper-cases them itself, so the CASING stored in the
	# pool is a display detail. What §4 pins is that the nine attested names
	# survive at all — that is the part a future edit could quietly lose.
	var pool_folded := {}
	for entry in Crew.NAME_POOL:
		pool_folded[String(entry).to_lower()] = true
	for name in ATTESTED_NAMES:
		assert_has(pool_folded, String(name).to_lower(),
			"the attested name %s must survive in NAME_POOL — the nine are sourced, not invented" % name)

	assert_eq(pool_folded.size(), Crew.NAME_POOL.size(),
		"NAME_POOL must not list the same name twice, or `avoid` cannot keep a crew unique")
	assert_true(Crew.NAME_POOL.size() >= ATTESTED_NAMES.size(),
		"the pool may grow with food-themed additions but must never shrink below the attested nine")
	assert_true(Crew.NAME_POOL.size() >= Crew.CAPACITY,
		"the pool must be able to name a full crew of %d without repeating itself" % Crew.CAPACITY)


func test_random_name_is_deterministic_under_a_pinned_seed() -> void:
	var first := Crew.random_name(MpRng.new(SEED))
	var second := Crew.random_name(MpRng.new(SEED))
	assert_eq(first, second, "the Random button must replay identically from a pinned seed like everything else")
	assert_false(first.is_empty(), "random_name must never hand back an empty name")
	assert_has(Crew.NAME_POOL, first, "a randomly drawn name must come from the pool")
	assert_ne(Crew.random_name(MpRng.new(SEED + 1)), "",
		"a different seed must still produce a usable name")


func test_random_name_respects_the_avoid_list() -> void:
	# A crew of six must not contain two Pizzas. The survivor is taken from the
	# pool itself rather than hardcoded, so this stays a test of `avoid` rather
	# than a test of how the pool happens to be spelled or ordered.
	var survivor := String(Crew.NAME_POOL[Crew.NAME_POOL.size() - 1])
	var avoid := PackedStringArray()
	for name in Crew.NAME_POOL:
		if String(name) != survivor:
			avoid.append(String(name))
	assert_eq(Crew.random_name(MpRng.new(SEED), avoid), survivor,
		"with only one pool name left unavoided, random_name must return that name")

	var used := PackedStringArray()
	var name_rng := MpRng.new(SEED)
	for i in Crew.CAPACITY:
		var drawn := Crew.random_name(name_rng, used)
		assert_false(drawn.is_empty(), "draw %d must produce a name for a crew of CAPACITY" % i)
		assert_not_has(used, drawn, "random_name must not repeat a name already on the avoid list")
		used.append(drawn)

	# The dead end: `avoid` covers the whole pool. Returning "" or crashing would
	# leave the recruit screen with an unnameable monkey.
	var all_avoided := Crew.NAME_POOL.duplicate()
	var fallback := Crew.random_name(MpRng.new(SEED), all_avoided)
	assert_false(fallback.is_empty(),
		"an exhausted pool must fall back to SOME name — an unnameable recruit is a stuck screen")

	var over_avoided := Crew.NAME_POOL.duplicate()
	for i in Crew.CAPACITY:
		over_avoided.append("Ghost%d" % i)
	assert_false(Crew.random_name(MpRng.new(SEED), over_avoided).is_empty(),
		"avoiding more names than the pool contains must still yield a name")


# --- purity: read-only questions must not move the run --------------------

func test_the_availability_questions_never_move_the_rng() -> void:
	# ARCHITECTURE §0: every new can_*/is_*/*_reason/performance must consume zero
	# RNG draws. Care.obeys() rolls, and availability sits one call away from it,
	# so this is exactly the shape of the bug test_core_purity.gd was written for.
	var able: Crew.Member = crew.add(_monkey("Able"))
	crew.assign(able, int(Ship.Station.SHIELDS))
	var stuffed: Crew.Member = crew.add(_monkey("Stuffed"))
	stuffed.monkey.fullness = Monkey.FULLNESS_MAX
	var downed: Crew.Member = crew.add(_monkey("Downed"))
	crew.hurt(downed, 100000)

	_assert_pure("Crew.is_available (able)", func() -> void:
		crew.is_available(able))
	_assert_pure("Crew.is_available (paralysed)", func() -> void:
		crew.is_available(stuffed))
	_assert_pure("Crew.is_available (incapacitated)", func() -> void:
		crew.is_available(downed))
	_assert_pure("Crew.unavailable_reason (able)", func() -> void:
		crew.unavailable_reason(able))
	_assert_pure("Crew.unavailable_reason (paralysed)", func() -> void:
		crew.unavailable_reason(stuffed))
	_assert_pure("Crew.is_incapacitated", func() -> void:
		crew.is_incapacitated(downed))


func test_the_manning_questions_never_move_the_rng() -> void:
	var shields := int(Ship.Station.SHIELDS)
	var sensors := int(Ship.Station.SENSORS)
	var able: Crew.Member = crew.add(_monkey("Able"))
	crew.assign(able, shields)
	var frozen: Crew.Member = crew.add(_monkey("Frozen"))
	frozen.monkey.paralysed_slots = 2
	crew.assign(frozen, sensors)

	_assert_pure("Crew.manning (manned)", func() -> void:
		crew.manning(shields))
	_assert_pure("Crew.manning (unmanned)", func() -> void:
		crew.manning(int(Ship.Station.PILOT)))
	_assert_pure("Crew.effective_manning (able)", func() -> void:
		crew.effective_manning(shields))
	_assert_pure("Crew.effective_manning (holder cannot act)", func() -> void:
		crew.effective_manning(sensors))


func test_the_performance_and_leveling_questions_never_move_the_rng() -> void:
	var weapons := int(Ship.Station.WEAPONS)
	var member: Crew.Member = crew.add(_capped_at("Bred", _keyed_stat(weapons)))
	crew.assign(member, weapons)

	_assert_pure("Crew.station_performance (manned)", func() -> void:
		crew.station_performance(weapons))
	_assert_pure("Crew.station_performance (unmanned)", func() -> void:
		crew.station_performance(int(Ship.Station.PILOT)))
	_assert_pure("Crew.performance_of", func() -> void:
		crew.performance_of(member, weapons))
	_assert_pure("Crew.level_ceiling", func() -> void:
		crew.level_ceiling(member, weapons))
	_assert_pure("Crew.xp_rate", func() -> void:
		crew.xp_rate(member, weapons))
