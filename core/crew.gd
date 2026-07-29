class_name Crew
extends RefCounted

## The monkeys aboard: who is at which station, and how good they have got at it.
##
## See docs/MISSION-ARCHITECTURE.md §4. Derives from docs/monkey-mission-design.md
## §2.5 (capacity 6, a voyage starts with 4), §4 (the stat->station bridge and the
## two-axis leveling model) and §2.6 (naming).
##
## TWO THINGS THIS DELIBERATELY DOES NOT DO
##
## It does not store station XP on `Monkey`. In-run progress lives on `Member` and
## dies with the voyage, while the monkey's trained stats live on `Monkey` and
## survive in the stable. That split is the whole reason permadeath costs the
## player something without costing them their bloodline (design §4, §6).
##
## It does not reimplement availability. Whether a monkey will work is already
## answered, correctly and faithfully, by `Care` — including both hunger extremes
## and `overfeeding_paralyses`. `Crew` injects a `Care` and asks it, exactly as
## `MatchResolver` does.

## Design §2.5 and §9 #6, RESOLVED — not open, do not retune.
const CAPACITY := 6
const VOYAGE_START_SIZE := 4

## `Member.station` when the monkey is aboard but not at a post.
const UNASSIGNED := -1

## DIVERGENCE: design §9 #2 — the station XP curve is [X]. Five levels above
## zero, so a station reads as a 0..5 pip row in the HUD and matches the five-stat
## card the original already shows. FTL uses two skill steps per station; five
## gives the longer voyage something to climb.
const STATION_LEVEL_MAX := 5

## Cumulative XP required to be AT each level; index is the level itself, so
## XP_TO_LEVEL[0] is 0 and the array is STATION_LEVEL_MAX + 1 long.
##
## DIVERGENCE: design §9 #2. The steps widen (40 / 70 / 110 / 160 / 220) so the
## first level lands inside a single combat and the last needs a whole sector —
## early feedback, late aspiration.
const XP_TO_LEVEL: PackedInt32Array = [0, 40, 110, 220, 380, 600]

## Trained-stat points needed per level of ceiling.
##
## DIVERGENCE: design §9 #2 and #3 — how breeding caps translate into station
## ceilings is [X]. Resolved with no separate mechanism at all: the ceiling reads
## the TRAINED STAT, which is already bounded by the monkey's cap, which is
## already raised only by breeding. So the chain "breed for POWER -> higher
## Weapons ceiling -> a gunner who can reach level 5" falls out of the existing
## model without inventing a second one.
##
## 30 is chosen against the attested starter tuple: Freddy's POWER cap is 145
## (dossier §3 [U]), so even a perfectly trained UNBRED Freddy tops out at
## Weapons level 4 — 150 is the wall, and only breeding gets him through it.
## That makes the meta-progression visible on the very first voyage.
const STAT_PER_LEVEL := 30

## The stat value that reads as "fully trained" — a station manned by a monkey
## with this much of the keyed stat, at level 0, performs at exactly 1.0.
##
## DIVERGENCE: design §9 #1. 150.0 matches `MatchResolver.KNOWLEDGE_REFERENCE`,
## which the boxing sim already treats as a competent stat, so "100% manned"
## means the same number in both halves of the game.
const REFERENCE_STAT := 150.0

## What each station level adds to performance, as a fraction.
## DIVERGENCE: design §9 #1/#2. Five levels therefore add 60% at most, which
## keeps trained stats the dominant term and in-run XP the sweetener — the
## brief's "only the experience and levels depend on their training" read the
## other way round would make breeding pointless.
const LEVEL_BONUS := 0.12

## Performance is clamped here so a deeply bred late-game specialist cannot make
## the combat maths degenerate. DIVERGENCE: no source; a safety rail.
const PERFORMANCE_MAX := 3.0

## XP accrues at `XP_RATE_FLOOR + stat / REFERENCE_STAT * XP_RATE_SPAN`, so an
## untrained monkey still learns by doing, at half speed, and a fully trained one
## learns at 1.5x. DIVERGENCE: design §9 #2.
const XP_RATE_FLOOR := 0.5
const XP_RATE_SPAN := 1.0

## Dossier §8 [C]: "Monkey names in play are player-assigned and food-themed by
## default (Freddy, Agatha, Lemon, Betty, Dragon, Jimbo, Tomato, Cookie, Pizza)."
## Those nine are attested. Design §2.6 makes this the *Random* button's pool.
##
## DIVERGENCE: the seven after Pizza are invented, in the same register, because
## a crew of six drawn from nine names repeats almost immediately. They are all
## plainly food, which is the documented convention. Freddy stays in the pool
## even though the starter's name is fixed (dossier §8 [C]) — the fixed name is a
## `RunState` concern, and nothing stops a later monkey being called Freddy too.
## Stored in mixed case and uppercased at display time, which is the convention
## the project already follows: `RunState.STARTER_NAME` is "Freddy", and
## `Monkey.name_line()` is what shouts it. Storing these pre-shouted would make
## the starter the only monkey in the game whose name was cased differently from
## every other.
const NAME_POOL: PackedStringArray = [
	"Freddy", "Agatha", "Lemon", "Betty", "Dragon", "Jimbo", "Tomato", "Cookie", "Pizza",
	"Waffle", "Pickle", "Mango", "Noodle", "Muffin", "Gherkin", "Custard",
]


## One monkey aboard, plus everything true of it only for this voyage.
class Member extends RefCounted:
	var monkey: Monkey = null
	## Ship.Station, or Crew.UNASSIGNED.
	var station: int = Crew.UNASSIGNED
	## Ship.Station -> float. Raw accumulated XP, NOT capped by the ceiling: a
	## monkey that trains its keyed stat mid-voyage should see the level it has
	## already earned unlock immediately, rather than having to re-earn it.
	var station_xp: Dictionary = {}
	var alive: bool = true
	## Reserved for phase 5+ (design §3 lists fatigue and morale). Nothing reads
	## it yet; it is declared so the save format does not change when it lands.
	var fatigue: float = 0.0

	func xp_in(p_station: int) -> float:
		return float(station_xp.get(p_station, 0.0))

	## The level actually in force: what the XP has earned, capped by what the
	## trained stat permits.
	func level_in(p_station: int) -> int:
		var earned := Crew.level_for_xp(xp_in(p_station))
		return mini(earned, ceiling_in(p_station))

	## The level the XP alone would give, ignoring the trained-stat ceiling.
	## Exposed so the UI can show "held back by training" honestly.
	func earned_level_in(p_station: int) -> int:
		return Crew.level_for_xp(xp_in(p_station))

	func ceiling_in(p_station: int) -> int:
		if monkey == null:
			return 0
		return Crew.ceiling_for_stat(monkey.get_stat(Ship.station_stat(p_station)))

	func display_name() -> String:
		if monkey == null:
			return "NOBODY"
		return monkey.monkey_name.to_upper()

	func to_dict() -> Dictionary:
		var xp := {}
		for key in station_xp:
			xp[int(key)] = float(station_xp[key])
		return {
			"station": station,
			"station_xp": xp,
			"alive": alive,
			"fatigue": fatigue,
			"monkey": monkey.to_dict() if monkey != null else {},
		}

	static func from_dict(d: Dictionary) -> Member:
		var member := Member.new()
		member.station = int(d.get("station", Crew.UNASSIGNED))
		member.alive = bool(d.get("alive", true))
		member.fatigue = float(d.get("fatigue", 0.0))
		var raw: Variant = d.get("station_xp", {})
		if raw is Dictionary:
			for key in (raw as Dictionary):
				member.station_xp[int(key)] = float((raw as Dictionary)[key])
		var monkey_data: Variant = d.get("monkey", {})
		if monkey_data is Dictionary and not (monkey_data as Dictionary).is_empty():
			member.monkey = Monkey.from_dict(monkey_data as Dictionary)
		return member


signal member_added(member: Member)
signal member_died(member: Member)
signal assigned(member: Member, station: int)
signal station_levelled(member: Member, station: int, level: int)

var members: Array[Member] = []

var _rules: GameRules
var _rng: MpRng
var _care: Care


func _init(rules: GameRules, rng: MpRng, care: Care) -> void:
	_rules = rules
	_rng = rng
	_care = care


# --- the level curve, shared with Member -------------------------------------

## Highest level whose cumulative threshold `xp` has reached.
static func level_for_xp(xp: float) -> int:
	var level := 0
	for candidate in range(1, XP_TO_LEVEL.size()):
		if xp >= float(XP_TO_LEVEL[candidate]):
			level = candidate
		else:
			break
	return level


## The ceiling a trained stat permits. This is where breeding reaches the ship.
static func ceiling_for_stat(stat_value: int) -> int:
	return clampi(stat_value / STAT_PER_LEVEL, 0, STATION_LEVEL_MAX)


static func xp_for_level(level: int) -> int:
	return XP_TO_LEVEL[clampi(level, 0, XP_TO_LEVEL.size() - 1)]


# --- roster ------------------------------------------------------------------

func size() -> int:
	return members.size()


func living() -> Array[Member]:
	var out: Array[Member] = []
	for member in members:
		if member.alive:
			out.append(member)
	return out


func has_room() -> bool:
	return members.size() < CAPACITY


## Bring a monkey aboard. Returns the new Member, or null when the ship is full
## (design §2.5: capacity is 6, hard).
func add(monkey: Monkey) -> Member:
	if monkey == null or not has_room():
		return null
	var member := Member.new()
	member.monkey = monkey
	member.station = UNASSIGNED
	for station in Ship.STATIONS:
		member.station_xp[station] = 0.0
	members.append(member)
	member_added.emit(member)
	return member


func remove(member: Member) -> bool:
	var index := members.find(member)
	if index < 0:
		return false
	members.remove_at(index)
	return true


func member_for(monkey: Monkey) -> Member:
	for member in members:
		if member.monkey == monkey:
			return member
	return null


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for member in members:
		out.append(member.display_name())
	return out


# --- assignment --------------------------------------------------------------

## Put a member at a station, displacing whoever was there (the incumbent becomes
## a floater). A member may hold at most one station, and a station at most one
## member — both directions are enforced here rather than trusted.
##
## Assigning an unavailable member is legal on purpose: you can post a monkey that
## is currently digesting, and the station comes to life when it does.
func assign(member: Member, station: int) -> bool:
	if member == null or not member.alive:
		return false
	if not members.has(member):
		return false
	if not Ship.STATIONS.has(station):
		return false
	var incumbent := manning(station)
	if incumbent == member:
		return true
	if incumbent != null:
		incumbent.station = UNASSIGNED
	member.station = station
	assigned.emit(member, station)
	return true


func unassign(member: Member) -> void:
	if member != null:
		member.station = UNASSIGNED


## The member posted to a station, available or not. Null when nobody is.
func manning(station: int) -> Member:
	for member in members:
		if member.alive and member.station == station:
			return member
	return null


func is_manned(station: int) -> bool:
	return manning(station) != null


func unmanned_stations() -> Array[int]:
	var out: Array[int] = []
	for station in Ship.STATIONS:
		if not is_manned(station):
			out.append(station)
	return out


## Living crew with no post. Design §2.5 expects one of these on a fresh voyage
## (4 crew, 5 stations means 4 posted and 0 spare; a 5th recruit is the first
## floater, a 6th the second).
func floaters() -> Array[Member]:
	var out: Array[Member] = []
	for member in members:
		if member.alive and member.station == UNASSIGNED:
			out.append(member)
	return out


## Post everyone where their best stat pays, deterministically and without
## touching the RNG. Greedy over every (member, station) pair by the keyed stat,
## with index tie-breaks so two identical crews always come out identical.
func auto_assign() -> void:
	for member in members:
		member.station = UNASSIGNED

	var pairs: Array = []
	for member_index in members.size():
		var member: Member = members[member_index]
		if not member.alive:
			continue
		for station in Ship.STATIONS:
			pairs.append({
				"member_index": member_index,
				"station": station,
				"stat": member.monkey.get_stat(Ship.station_stat(station)) if member.monkey != null else 0,
			})

	pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["stat"]) != int(b["stat"]):
			return int(a["stat"]) > int(b["stat"])
		if int(a["member_index"]) != int(b["member_index"]):
			return int(a["member_index"]) < int(b["member_index"])
		return int(a["station"]) < int(b["station"]))

	var taken_stations: Array[int] = []
	var posted: Array[int] = []
	for pair in pairs:
		var station := int(pair["station"])
		var member_index := int(pair["member_index"])
		if taken_stations.has(station) or posted.has(member_index):
			continue
		taken_stations.append(station)
		posted.append(member_index)
		members[member_index].station = station
		assigned.emit(members[member_index], station)


# --- availability, delegated to Care -----------------------------------------
#
# PURE: no RNG. `Care.can_act` and `Care.block_reason` are themselves pinned as
# RNG-free by tests/unit/test_core_purity.gd, which is what makes these safe for
# a screen to poll on every redraw.

## True when this member will actually work right now.
##
## `Care.can_act` carries the faithful rules: an unbefriended monkey refuses, a
## starving one cannot move, and an overfed one is immobilised until it digests
## (`overfeeding_paralyses`, FAITHFUL — design §10 says never soften it). In space
## that means the station reads as unmanned while the monkey sits there digesting,
## which is exactly the texture the design asks for.
func is_available(member: Member) -> bool:
	if member == null or member.monkey == null or not member.alive:
		return false
	if is_incapacitated(member):
		return false
	if _care == null:
		return true
	return _care.can_act(member.monkey)


## Player-facing reason a member will not work, "" when it will. Guaranteed to be
## empty exactly when `is_available` is true.
func unavailable_reason(member: Member) -> String:
	if member == null or member.monkey == null:
		return "THERE IS NOBODY THERE."
	if not member.alive:
		return "%s IS GONE." % member.display_name()
	if is_incapacitated(member):
		return "%s IS OUT COLD." % member.display_name()
	if _care == null:
		return ""
	return _care.block_reason(member.monkey)


## The member at a station who is actually working. Null when the post is empty
## OR when its holder cannot act — the caller usually wants this one, not
## `manning`, which reports the assignment regardless.
func effective_manning(station: int) -> Member:
	var member := manning(station)
	if member == null or not is_available(member):
		return null
	return member


# --- performance -------------------------------------------------------------

## What ship systems consume. 0.0 when the station is empty or its monkey cannot
## work; roughly 1.0 for a fully trained monkey at level 0.
func station_performance(station: int) -> float:
	var member := effective_manning(station)
	if member == null:
		return 0.0
	return performance_of(member, station)


## What this member would contribute at this station, ignoring availability.
## Reads the station's KEYED stat, so posting a gunner to the helm really does
## give you a bad pilot.
func performance_of(member: Member, station: int) -> float:
	if member == null or member.monkey == null:
		return 0.0
	var stat_value := member.monkey.get_stat(Ship.station_stat(station))
	var base := float(stat_value) / REFERENCE_STAT
	var level := member.level_in(station)
	return minf(base * (1.0 + float(level) * LEVEL_BONUS), PERFORMANCE_MAX)


func level_ceiling(member: Member, station: int) -> int:
	if member == null:
		return 0
	return member.ceiling_in(station)


func level_of(member: Member, station: int) -> int:
	if member == null:
		return 0
	return member.level_in(station)


## XP multiplier for doing the job. Trained monkeys learn faster as well as
## higher — design §4: trained stats set "the ceiling and rate".
func xp_rate(member: Member, station: int) -> float:
	if member == null or member.monkey == null:
		return 0.0
	var stat_value := member.monkey.get_stat(Ship.station_stat(station))
	return XP_RATE_FLOOR + float(stat_value) / REFERENCE_STAT * XP_RATE_SPAN


# --- progress ----------------------------------------------------------------

## Bank XP for doing the job, scaled by `xp_rate`. Returns the level now in force.
##
## Raw XP is stored uncapped while the LEVEL is capped by the trained stat, so
## training a stat mid-voyage can unlock a level the monkey has already earned by
## fighting. That is the two axes meeting, and it is the moment the player should
## feel the fusion working.
func award_xp(member: Member, station: int, amount: float) -> int:
	if member == null or not member.alive or amount <= 0.0:
		return level_of(member, station)
	if not Ship.STATIONS.has(station):
		return level_of(member, station)
	var before := member.level_in(station)
	var gained := amount * xp_rate(member, station)
	member.station_xp[station] = member.xp_in(station) + gained
	var after := member.level_in(station)
	if after != before:
		station_levelled.emit(member, station, after)
	return after


## Award to whoever is working that station. No-op when nobody is.
func award_station_xp(station: int, amount: float) -> int:
	var member := effective_manning(station)
	if member == null:
		return 0
	return award_xp(member, station, amount)


# --- health, through Monkey's existing pools ---------------------------------
#
# STRENGTH is the health bar (dossier §3 [C]) and there is no separate HP stat.
# `current_strength` is the live pool; `max_strength()` is the STRENGTH stat.

## Returns the damage actually applied.
func hurt(member: Member, amount: int) -> int:
	if member == null or member.monkey == null or amount <= 0:
		return 0
	var before := member.monkey.current_strength
	member.monkey.current_strength = maxi(0, before - amount)
	return before - member.monkey.current_strength


func heal(member: Member, amount: int) -> int:
	if member == null or member.monkey == null or amount <= 0:
		return 0
	var before := member.monkey.current_strength
	member.monkey.current_strength = clampi(
		before + amount, 0, member.monkey.max_strength())
	return member.monkey.current_strength - before


## Out cold, not dead. See the DIVERGENCE note on `kill`.
func is_incapacitated(member: Member) -> bool:
	if member == null or member.monkey == null:
		return true
	return member.monkey.current_strength <= 0


## DIVERGENCE: nothing in the dossier or the design doc makes damage lethal, and
## in boxing zero Strength is a KO the monkey gets up from afterwards. Death is
## therefore never automatic — it is this explicit call, reserved for genuinely
## lethal events (vacuum, fire, a lost boarding fight). Two things fall out of
## that, both wanted: the boxing sim can be re-homed as boarding melee in phase 6
## without quietly becoming fatal, and `Monkey` keeps dossier §14.11's promise
## that there is no injury, illness, ageing or lifespan system.
func kill(member: Member) -> void:
	if member == null or not member.alive:
		return
	member.alive = false
	member.station = UNASSIGNED
	if member.monkey != null:
		member.monkey.current_strength = 0
	member_died.emit(member)


## Permadeath condition (design §5): the voyage ends when the last monkey dies.
func all_dead() -> bool:
	return living().is_empty()


# --- naming ------------------------------------------------------------------

## The *Random* button (design §2.6). Deterministic under a pinned seed, and it
## will not hand back a name already in `avoid`, so a crew of six cannot contain
## two Pizzas. Falls back to a numbered variant when every name is taken, because
## returning "" would leave the player with an unnamed monkey.
static func random_name(rng: MpRng, avoid: PackedStringArray = PackedStringArray()) -> String:
	var upper_avoid: Array[String] = []
	for name_text in avoid:
		upper_avoid.append(String(name_text).to_upper())

	var candidates: Array = []
	for name_text in NAME_POOL:
		if not upper_avoid.has(String(name_text).to_upper()):
			candidates.append(String(name_text))
	if not candidates.is_empty():
		return String(rng.pick(candidates))

	var base := String(rng.pick(_pool_as_array()))
	var suffix := 2
	while upper_avoid.has(("%s %d" % [base, suffix]).to_upper()):
		suffix += 1
	return "%s %d" % [base, suffix]


static func _pool_as_array() -> Array:
	var out: Array = []
	for name_text in NAME_POOL:
		out.append(String(name_text))
	return out


# --- serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var out: Array = []
	for member in members:
		out.append(member.to_dict())
	return {"members": out}


## Rebuild the crew.
##
## Two modes, because the crew's monkeys have two possible owners. During a
## voyage the crew owns them outright and they round-trip through the embedded
## `monkey` dict. Once `Stable` lands (phase 7) the persistent roster owns them
## and the crew only references them — pass that roster and members bind to it by
## index instead, so a monkey is not duplicated between the two save layers.
func apply_dict(d: Dictionary, roster: Array[Monkey] = []) -> void:
	members.clear()
	var raw: Variant = d.get("members", [])
	if not (raw is Array):
		return
	var index := 0
	for entry in (raw as Array):
		if not (entry is Dictionary):
			index += 1
			continue
		var member := Member.from_dict(entry as Dictionary)
		if not roster.is_empty():
			var roster_index := int((entry as Dictionary).get("roster_index", index))
			if roster_index >= 0 and roster_index < roster.size():
				member.monkey = roster[roster_index]
		if member.monkey != null:
			members.append(member)
		index += 1
