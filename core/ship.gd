class_name Ship
extends RefCounted

## The ship: hull, reactor power, the five systems, damage, fires and breaches.
##
## See docs/MISSION-ARCHITECTURE.md §5. Derives from docs/monkey-mission-design.md
## §2.5 (one ship, five stations) and §5 (resources).
##
## HARDWARE ONLY. Ship never imports Crew. Everything the crew affects is
## expressed as a method taking a `performance` float in roughly 0..2, which
## `Crew.station_performance()` supplies. That is what lets the two be tested
## independently, and it is what stops a dependency cycle between them.
##
## DIVERGENCE: design §3 lists oxygen, medbay and doors among the ship's systems,
## and then §9 #5 resolves the ship to "five fixed systems/stations (Pilot,
## Engines, Weapons, Shields, Sensors)". The later, explicit resolution wins:
## systems and stations are the same five things, 1:1, which is precisely what
## keeps the stat->station map clean (§4). Oxygen, medbay, doors and crew room
## movement are out of scope and deliberately not modelled here.

## The five manned systems. Design §4 [RESOLVED] — do not add a sixth without
## breaking the 1:1 stat map, which is the spine of the whole fusion.
enum Station { PILOT, ENGINES, WEAPONS, SHIELDS, SENSORS }

const STATIONS: Array[int] = [
	Station.PILOT, Station.ENGINES, Station.WEAPONS, Station.SHIELDS, Station.SENSORS,
]

const STATION_LABELS: PackedStringArray = ["PILOT", "ENGINES", "WEAPONS", "SHIELDS", "SENSORS"]

## The bridge. Design §4, and the single most important contract in the fusion —
## the equivalent of the original's "STRENGTH is the health bar".
##
## SHIELDS <- STRENGTH is the one debatable pairing (design §4 argues it against
## STAMINA and wins on the grounds that STRENGTH already reads as the defensive
## stat and is what bandaging restores). If Shields ever wants to feel like
## sustain rather than toughness, this is the line to swap.
const STATION_STAT: Dictionary = {
	Station.PILOT: Monkey.Stat.SPEED,
	Station.ENGINES: Monkey.Stat.STAMINA,
	Station.WEAPONS: Monkey.Stat.POWER,
	Station.SHIELDS: Monkey.Stat.STRENGTH,
	Station.SENSORS: Monkey.Stat.KNOWLEDGE,
}

## Which training minigame raises the stat a station reads. The other half of the
## bridge: this is how "train a monkey for Weapons" is a thing the player can do.
const STATION_ACTIVITY: Dictionary = {
	Station.PILOT: Training.Activity.SKIPPING,
	Station.ENGINES: Training.Activity.RUNNING,
	Station.WEAPONS: Training.Activity.PUNCHBAG,
	Station.SHIELDS: Training.Activity.SIT_UPS,
	Station.SENSORS: Training.Activity.SHOPPING,
}

## DIVERGENCE: design §9 #4 — hull size is [X]. 30 is chosen so that the weapon
## damage below (2..4 a shot) needs a sustained engagement to kill, while the
## sector-boss fight can plausibly end a voyage. FTL's own hull is 30.
const HULL_MAX := 30

## DIVERGENCE: design §9 #11 — the power-allocation model is [X]. Resolved as
## "free like FTL, bounded by the reactor": the player may move bars anywhere,
## and the constraint is total reactor output, not a crew stat. Constraining
## allocation by a stat as well would double-charge the player for a weak crew,
## who is already paying through `station_performance`.
##
## 8 bars against 5 systems is deliberately not enough to run everything at full
## tilt, which is what makes allocation a decision rather than a formality.
const REACTOR_START := 8
const REACTOR_MAX := 16

## DIVERGENCE: [X]. Four bars per system matches FTL and gives the derived curves
## below a clean 0..1 fraction to work with.
const SYSTEM_BARS_MAX := 4

## DIVERGENCE: design §9 #4 — fuel pacing is [X].
##
## KNOWN GAP, do not trust the number. This was chosen on the reasoning that "a
## player who wanders greedily will run dry before the boss, while a direct line
## always makes it". That reasoning is FALSE as the map currently generates: every
## link in a `SectorMap` advances exactly one column, so EVERY route from entry to
## boss is exactly `SectorMap.COLUMNS - 1` = 5 jumps. There is no such thing as a
## greedy detour, route choice costs no fuel whatsoever, and
## `Voyage.EndReason.STRANDED` is unreachable by play — 3 sectors x 5 jumps is 15
## against 16 starting fuel, before either `Voyage.SECTOR_CLEAR_FUEL` payout.
##
## Lowering this number does NOT fix it: with consumption fixed at 5 per sector,
## fuel can only ever be a pass/fail threshold, never a decision. The fix is
## route-length VARIATION — lateral links within a column, so a diversion to a
## store costs a jump and lets the threat close. That is the top item in
## docs/MORNING-REPORT.md §9 and it is deliberately not being done unattended,
## because it changes an invariant that ~80 tests assert.
##
## Left at 16 meanwhile because it is safely slack: the voyage is completable and
## nothing softlocks. Fuel is currently decorative, and honestly labelled as such.
const FUEL_START := 16
const MISSILES_START := 8

## FTL's shield rule: two power bars per layer.
const SHIELD_BARS_PER_LAYER := 2

# --- derived-curve coefficients ----------------------------------------------
#
# Every constant below is DIVERGENCE: design §9 #1 marks the stat->station
# coefficients [X] wholesale. The shape chosen throughout is
#
#     hardware_fraction * BASE * (1.0 + performance * CREW_GAIN)
#
# so that POWER ALONE GIVES A FLOOR and crew is a multiplier on top. That is
# required, not stylistic: a voyage starts with 4 crew for 5 stations (design
# §2.5), so an unmanned station must degrade rather than fail. Design §2.5 says
# the fifth station runs "unmanned or weak early" — weak, not dead.

## Shield layers per second at full power with nobody manning it.
const SHIELD_RECHARGE_BASE := 0.22
const SHIELD_RECHARGE_CREW_GAIN := 0.60

## Evasion from engine hardware alone, per powered bar.
const EVASION_PER_ENGINE_BAR := 0.05
const EVASION_PILOT_WEIGHT := 0.18
const EVASION_ENGINE_WEIGHT := 0.07
## Evasion never reaches certainty. Dossier §6 [C] makes the same point about the
## boxing EVADE strategy — "not fully reliable, you still get hit".
const EVASION_MAX := 0.80

## Weapon charge, as a fraction of a full charge per second.
const WEAPON_CHARGE_BASE := 0.14
const WEAPON_CHARGE_CREW_GAIN := 0.50

## Damage per shot. Hardware floor plus a crew contribution, so a trained gunner
## roughly doubles the hurt — POWER is the damage stat, faithfully (dossier §3).
const WEAPON_DAMAGE_BASE := 2
const WEAPON_DAMAGE_CREW := 2.0

## Targeting shaves the defender's evasion. The heir to KNOWLEDGE gating special
## punches (dossier §4 [C], design §4).
const TARGETING_PER_BAR := 0.02
const TARGETING_CREW_WEIGHT := 0.25
const TARGETING_MAX := 0.60

## Jump-drive charge, as a fraction per second.
const JUMP_CHARGE_BASE := 0.10
const JUMP_CHARGE_CREW_GAIN := 0.55

var hull: int = HULL_MAX
var hull_max: int = HULL_MAX
var reactor: int = REACTOR_START
var fuel: int = FUEL_START
var missiles: int = MISSILES_START

## Station -> int. Bars the player has ASKED for. Survives damage on purpose:
## repairing a system restores its output without the player re-allocating.
var power: Dictionary = {}
## Station -> int. Bars knocked out. Reduces capability, never the request.
var damage: Dictionary = {}
var fires: Dictionary = {}
var breaches: Dictionary = {}

signal hull_changed(hull: int)
signal system_damaged(station: int, bars: int)
signal system_repaired(station: int, bars: int)
signal power_changed(station: int, bars: int)
signal fire_started(station: int)
signal breach_opened(station: int)
signal destroyed()


func _init() -> void:
	for station in STATIONS:
		power[station] = 0
		damage[station] = 0
		fires[station] = false
		breaches[station] = false


## The ship a voyage begins with. DIVERGENCE: the opening allocation is [X].
## Shields/Engines/Weapons take two bars each and Pilot/Sensors one, which spends
## the whole reactor. Starting with nothing spare means the first real decision of
## a combat is what to rob, which is the FTL texture we want.
static func make_starter() -> Ship:
	var ship := Ship.new()
	ship.allocate(Station.SHIELDS, 2)
	ship.allocate(Station.ENGINES, 2)
	ship.allocate(Station.WEAPONS, 2)
	ship.allocate(Station.PILOT, 1)
	ship.allocate(Station.SENSORS, 1)
	return ship


# --- the bridge --------------------------------------------------------------

static func station_stat(station: int) -> Monkey.Stat:
	return STATION_STAT.get(station, Monkey.Stat.POWER)


static func station_activity(station: int) -> Training.Activity:
	return STATION_ACTIVITY.get(station, Training.Activity.PUNCHBAG)


## The inverse of `station_stat`. Returns -1 for a stat with no station, which
## cannot happen today (the map is total and 1:1) but would if a sixth stat were
## ever added — better a caller sees -1 than silently gets the pilot's seat.
static func station_for_stat(stat: int) -> int:
	for station in STATIONS:
		if int(STATION_STAT[station]) == int(stat):
			return station
	return -1


static func station_label(station: int) -> String:
	if station < 0 or station >= STATION_LABELS.size():
		return "UNKNOWN"
	return STATION_LABELS[station]


# --- power -------------------------------------------------------------------

func max_bars(_station: int) -> int:
	return SYSTEM_BARS_MAX


func power_in(station: int) -> int:
	return int(power.get(station, 0))


func damage_in(station: int) -> int:
	return int(damage.get(station, 0))


## Bars actually doing work: the request, capped by what damage has left intact.
##
## The distinction between this and `power_in` is the heart of the damage model.
## A knocked-out bar costs you output immediately and gives it back the moment
## the system is repaired, without the player having to notice and re-allocate
## mid-fight.
func effective_power(station: int) -> int:
	var capacity := maxi(0, max_bars(station) - damage_in(station))
	return clampi(mini(power_in(station), capacity), 0, max_bars(station))


func power_used() -> int:
	var total := 0
	for station in STATIONS:
		total += power_in(station)
	return total


func power_free() -> int:
	return maxi(0, reactor - power_used())


## Move `bars` into a system. False (and no change at all) when the reactor
## cannot cover it or the system is already at its own ceiling.
func allocate(station: int, bars: int) -> bool:
	if bars <= 0 or not power.has(station):
		return false
	if bars > power_free():
		return false
	if power_in(station) + bars > max_bars(station):
		return false
	power[station] = power_in(station) + bars
	power_changed.emit(station, power_in(station))
	return true


## Pull `bars` back out. Clamps rather than underflowing, so a caller that asks
## for more than is there simply empties the system.
func deallocate(station: int, bars: int) -> void:
	if bars <= 0 or not power.has(station):
		return
	power[station] = maxi(0, power_in(station) - bars)
	power_changed.emit(station, power_in(station))


## Set a system's allocation outright, honouring both ceilings. Returns whether
## the requested figure was reached exactly.
func set_power(station: int, bars: int) -> bool:
	if not power.has(station):
		return false
	var target := clampi(bars, 0, max_bars(station))
	var current := power_in(station)
	if target == current:
		return target == bars
	if target < current:
		deallocate(station, current - target)
		return target == bars
	var granted := mini(target - current, power_free())
	if granted > 0:
		power[station] = current + granted
		power_changed.emit(station, power_in(station))
	return power_in(station) == bars


func is_offline(station: int) -> bool:
	return effective_power(station) <= 0


# --- damage ------------------------------------------------------------------

## Returns the damage actually taken, after clamping at zero hull.
func take_hull_damage(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := hull
	hull = clampi(hull - amount, 0, hull_max)
	var applied := before - hull
	if applied != 0:
		hull_changed.emit(hull)
	if hull <= 0:
		destroyed.emit()
	return applied


func repair_hull(amount: int) -> int:
	if amount <= 0:
		return 0
	var before := hull
	hull = clampi(hull + amount, 0, hull_max)
	var applied := hull - before
	if applied != 0:
		hull_changed.emit(hull)
	return applied


## Knock out bars of a system. Returns the bars actually knocked out.
func damage_system(station: int, bars: int) -> int:
	if bars <= 0 or not damage.has(station):
		return 0
	var before := damage_in(station)
	damage[station] = clampi(before + bars, 0, max_bars(station))
	var applied := damage_in(station) - before
	if applied > 0:
		system_damaged.emit(station, damage_in(station))
	return applied


func repair_system(station: int, bars: int) -> int:
	if bars <= 0 or not damage.has(station):
		return 0
	var before := damage_in(station)
	damage[station] = clampi(before - bars, 0, max_bars(station))
	var applied := before - damage_in(station)
	if applied > 0:
		system_repaired.emit(station, damage_in(station))
	return applied


func is_destroyed() -> bool:
	return hull <= 0


# --- hazards -----------------------------------------------------------------
#
# Fires and breaches are booleans per station rather than a spreading grid. A
# room-by-room fire sim needs crew movement, doors and oxygen, all of which §5
# puts out of scope. What survives is the part that matters to combat: a hazard
# suppresses the station until it is dealt with.

func start_fire(station: int) -> bool:
	if not fires.has(station) or bool(fires[station]):
		return false
	fires[station] = true
	fire_started.emit(station)
	return true


func extinguish(station: int) -> bool:
	if not fires.has(station) or not bool(fires[station]):
		return false
	fires[station] = false
	return true


func open_breach(station: int) -> bool:
	if not breaches.has(station) or bool(breaches[station]):
		return false
	breaches[station] = true
	breach_opened.emit(station)
	return true


func seal(station: int) -> bool:
	if not breaches.has(station) or not bool(breaches[station]):
		return false
	breaches[station] = false
	return true


func has_fire(station: int) -> bool:
	return bool(fires.get(station, false))


func has_breach(station: int) -> bool:
	return bool(breaches.get(station, false))


func has_hazard() -> bool:
	for station in STATIONS:
		if has_fire(station) or has_breach(station):
			return true
	return false


# --- stores ------------------------------------------------------------------

func burn_fuel(amount: int = 1) -> bool:
	if amount <= 0 or fuel < amount:
		return false
	fuel -= amount
	return true


func add_fuel(amount: int) -> void:
	if amount > 0:
		fuel += amount


func spend_missile() -> bool:
	if missiles <= 0:
		return false
	missiles -= 1
	return true


func add_missiles(amount: int) -> void:
	if amount > 0:
		missiles += amount


# --- derived quantities ------------------------------------------------------
#
# All PURE: no RNG, no mutation, no side effects. Ship takes no MpRng at all, by
# construction, which is the strongest available guarantee that asking these
# questions cannot move a run's random stream (tests/unit/test_core_purity.gd).
#
# `performance` is what Crew.station_performance() returns: 0.0 for an unmanned
# or unavailable station, ~1.0 for a fully trained monkey at level 0, up to
# roughly 2.0 for a bred and levelled specialist.

## Shield layers the hardware can hold. Two powered bars per layer, FTL's rule.
func shield_layers_max() -> int:
	return effective_power(Station.SHIELDS) / SHIELD_BARS_PER_LAYER


## Layers per second. Zero when shields are unpowered or knocked out — a dead
## system does not trickle back, however good the monkey sitting at it is.
func shield_recharge_rate(shields_perf: float) -> float:
	if is_offline(Station.SHIELDS):
		return 0.0
	var fraction := float(effective_power(Station.SHIELDS)) / float(max_bars(Station.SHIELDS))
	return fraction * SHIELD_RECHARGE_BASE * (1.0 + maxf(0.0, shields_perf) * SHIELD_RECHARGE_CREW_GAIN)


## Chance in 0..EVASION_MAX that an incoming shot misses entirely.
##
## Engine hardware provides the floor, so an unpiloted ship still jinks a little;
## the pilot is the larger multiplier, because dodging is a reflex and SPEED is
## the reflex stat.
func evasion(pilot_perf: float, engines_perf: float) -> float:
	if is_offline(Station.ENGINES):
		# No engines, no evasion. A pilot cannot dodge with nothing to dodge with.
		return 0.0
	var hardware := float(effective_power(Station.ENGINES)) * EVASION_PER_ENGINE_BAR
	var crewed := maxf(0.0, pilot_perf) * EVASION_PILOT_WEIGHT
	crewed += maxf(0.0, engines_perf) * EVASION_ENGINE_WEIGHT
	return clampf(hardware + crewed, 0.0, EVASION_MAX)


## Fraction of a full weapon charge gained per second.
func weapon_charge_rate(weapons_perf: float) -> float:
	if is_offline(Station.WEAPONS):
		return 0.0
	var fraction := float(effective_power(Station.WEAPONS)) / float(max_bars(Station.WEAPONS))
	return fraction * WEAPON_CHARGE_BASE * (1.0 + maxf(0.0, weapons_perf) * WEAPON_CHARGE_CREW_GAIN)


## Hull damage one shot does. 0 when the weapon cannot fire at all.
func weapon_damage(weapons_perf: float) -> int:
	if is_offline(Station.WEAPONS):
		return 0
	return WEAPON_DAMAGE_BASE + int(round(maxf(0.0, weapons_perf) * WEAPON_DAMAGE_CREW))


## How much of the defender's evasion this ship's targeting cancels out.
func targeting_bonus(sensors_perf: float) -> float:
	if is_offline(Station.SENSORS):
		return 0.0
	var hardware := float(effective_power(Station.SENSORS)) * TARGETING_PER_BAR
	return clampf(hardware + maxf(0.0, sensors_perf) * TARGETING_CREW_WEIGHT, 0.0, TARGETING_MAX)


## Fraction of the jump drive charged per second. This is the escape hatch: a
## losing fight is survivable if the engines hold long enough to charge out.
func jump_charge_rate(engines_perf: float) -> float:
	if is_offline(Station.ENGINES):
		return 0.0
	var fraction := float(effective_power(Station.ENGINES)) / float(max_bars(Station.ENGINES))
	return fraction * JUMP_CHARGE_BASE * (1.0 + maxf(0.0, engines_perf) * JUMP_CHARGE_CREW_GAIN)


# --- serialisation -----------------------------------------------------------
#
# Enum-keyed dictionaries are written with int keys and read back through int(),
# per the save contract in docs/ARCHITECTURE.md §15 — JSON turns every key into a
# String on the way home.

func to_dict() -> Dictionary:
	return {
		"hull": hull,
		"hull_max": hull_max,
		"reactor": reactor,
		"fuel": fuel,
		"missiles": missiles,
		"power": _int_keyed(power),
		"damage": _int_keyed(damage),
		"fires": _int_keyed_bool(fires),
		"breaches": _int_keyed_bool(breaches),
	}


func apply_dict(d: Dictionary) -> void:
	hull_max = maxi(1, int(d.get("hull_max", HULL_MAX)))
	hull = clampi(int(d.get("hull", hull_max)), 0, hull_max)
	reactor = clampi(int(d.get("reactor", REACTOR_START)), 0, REACTOR_MAX)
	fuel = maxi(0, int(d.get("fuel", FUEL_START)))
	missiles = maxi(0, int(d.get("missiles", MISSILES_START)))
	var raw_power := _int_keyed(d.get("power", {}))
	var raw_damage := _int_keyed(d.get("damage", {}))
	var raw_fires := _int_keyed_bool(d.get("fires", {}))
	var raw_breaches := _int_keyed_bool(d.get("breaches", {}))
	for station in STATIONS:
		power[station] = clampi(int(raw_power.get(station, 0)), 0, max_bars(station))
		damage[station] = clampi(int(raw_damage.get(station, 0)), 0, max_bars(station))
		fires[station] = bool(raw_fires.get(station, false))
		breaches[station] = bool(raw_breaches.get(station, false))


static func from_dict(d: Dictionary) -> Ship:
	var ship := Ship.new()
	ship.apply_dict(d)
	return ship


static func _int_keyed(source: Variant) -> Dictionary:
	var out := {}
	if source is Dictionary:
		for key in (source as Dictionary):
			out[int(key)] = int((source as Dictionary)[key])
	return out


static func _int_keyed_bool(source: Variant) -> Dictionary:
	var out := {}
	if source is Dictionary:
		for key in (source as Dictionary):
			out[int(key)] = bool((source as Dictionary)[key])
	return out
