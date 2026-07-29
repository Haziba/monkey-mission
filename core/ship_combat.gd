class_name ShipCombat
extends RefCounted

## Ship-vs-ship, real-time-with-pause.
##
## See docs/MISSION-ARCHITECTURE.md §10. A deliberate STRUCTURAL CLONE of
## `core/match_resolver.gd`: the same `advance(delta)` clock accumulating into
## fixed ticks, the same "return only the new events, duplicated" contract, the
## same `simulate_*` escape hatches for tests and a fast-forward button. That
## architecture is already proven and already covered by 46 tests, and design §3
## calls it "a gift here — FTL combat is the same shape".
##
## `MatchResolver` is untouched. It survives to become `BoardingCombat` for monkey
## melee in phase 6 (design §3), with its tests intact.
##
## WHAT COMPUTES WHAT
##
## `ShipCombat` sequences; it does not invent curves. Every derived quantity —
## evasion, shield recharge, weapon charge, damage, targeting — comes from `Ship`,
## fed by `Crew.station_performance()`. That keeps the balance knobs in one place
## and means a combat cannot disagree with the readouts the HUD is showing.
##
## The spirit stops time to give orders (design §7): `set_power` and `set_target`
## are the pause-time verbs.

## The sim's resolution. DIVERGENCE: [X]. Small enough that a 0.6s weapon-charge
## difference is visible, large enough that a 180-second fight is ~720 ticks
## rather than tens of thousands.
const TICK_SECONDS := 0.25

## Hard stop, so a mutually un-killable pairing cannot hang the game or a test.
## DIVERGENCE: [X]. Three minutes is far longer than a real engagement.
const MAX_SECONDS := 180.0

## Shots pop exactly one shield layer each, FTL's rule.
const SHIELD_POP_PER_HIT := 1

## DIVERGENCE: [X] — all of the following. Chosen so that an evenly matched pair
## resolves in 40..90 seconds and the losing side has time to notice and run.

## Chance a hull hit also knocks out a bar of the targeted system.
const SYSTEM_DAMAGE_CHANCE := 0.45
## Chance a hull hit starts a fire, and separately opens a breach.
const FIRE_CHANCE := 0.16
const BREACH_CHANCE := 0.10
## Chance a hull hit injures the monkey at the targeted station.
const CREW_HURT_CHANCE := 0.22
const CREW_HURT_MIN := 3
const CREW_HURT_MAX := 9

## A fire chews through the system it is in, and hurts whoever is sitting there.
const FIRE_SYSTEM_DAMAGE_PER_SECOND := 0.06
const FIRE_CREW_DAMAGE_PER_SECOND := 0.8
## A breach bleeds air: no system damage, but it wears the crew down.
const BREACH_CREW_DAMAGE_PER_SECOND := 0.5

## Station XP per second for simply being at a working post, plus one-off awards
## for the moments that actually teach something. Design §4: station XP accrues
## from DOING.
const XP_PER_SECOND_MANNED := 0.6
const XP_ON_SHOT_FIRED := 3.0
const XP_ON_SHOT_EVADED := 4.0
const XP_ON_SHIELD_ABSORBED := 3.5
const XP_ON_HIT_LANDED := 2.0

## Rewards, scaling with sector depth. DIVERGENCE: design §9 #4.
const SCRAP_REWARD_BASE := 22
const SCRAP_REWARD_PER_SECTOR := 9
const FUEL_REWARD_CHANCE := 0.55
const MISSILE_REWARD_CHANCE := 0.35

## Damage control, done by crew who are NOT at a station.
##
## THE PROBLEM THIS SOLVES: without repair, an engine hit is unrecoverable.
## `Ship.evasion` and `Ship.jump_charge_rate` both return 0.0 with engines
## offline, so a ship whose engines are shot out can neither dodge nor run, and the
## rest of the fight is a formality. FTL's answer is crew repair, and we already
## have the mechanism — `Crew.floaters()` is the unassigned crew.
##
## That makes it a real decision rather than a freebie. A voyage starts with 4 crew
## for 5 stations and NO floaters, so damage control costs you a manned station:
## pull the pilot off the helm to fix the engines, and lose your evasion while they
## work. Exactly the trade FTL asks you to make.
##
## DIVERGENCE: [X], all three. A bar back every ~8s and a fire out in ~4s at
## reference STRENGTH, so repair is meaningful but never outruns a sustained
## barrage.
const REPAIR_BARS_PER_SECOND := 0.12
const FIRE_FIGHT_PER_SECOND := 0.25
const SEAL_BREACH_PER_SECOND := 0.18

## The enemy AI retargets this often, in seconds. Fixed rather than random so a
## replay is identical.
const ENEMY_RETARGET_SECONDS := 6.0

## The enemy runs when its hull falls this low a fraction. DIVERGENCE: [X].
const ENEMY_FLEE_HULL_FRACTION := 0.22

enum Outcome { NONE, PLAYER_WON, PLAYER_DESTROYED, PLAYER_ESCAPED, ENEMY_ESCAPED, DRAW }

enum EventKind {
	COMBAT_START,
	WEAPON_CHARGED,
	SHOT_FIRED,
	SHOT_EVADED,
	SHIELD_ABSORBED,
	HULL_DAMAGED,
	SYSTEM_DAMAGED,
	FIRE_STARTED,
	BREACH_OPENED,
	CREW_HURT,
	SHIELD_RECHARGED,
	POWER_REROUTED,
	DISOBEYED,
	JUMP_CHARGED,
	TARGET_CHANGED,
	ENEMY_DESTROYED,
	PLAYER_DESTROYED,
	ESCAPED,
	COMBAT_END,
	# APPENDED, so nothing above is renumbered — see MISSION-ARCHITECTURE.md §0.
	SYSTEM_REPAIRED,
	FIRE_OUT,
}


class Combatant extends RefCounted:
	var ship: Ship = null
	var crew: Crew = null
	var is_player: bool = false

	## Intact shield layers, and progress toward the next one (0..1).
	var shield_layers: int = 0
	var shield_charge: float = 0.0
	## Progress toward the next shot (0..1).
	var weapon_charge: float = 0.0
	## Progress toward jumping out (0..1). Only climbs while `escaping`.
	var jump_charge: float = 0.0
	var escaping: bool = false
	## Ship.Station being aimed at.
	var target: int = Ship.Station.WEAPONS

	## What the monkey at `station` is worth right now. 0.0 when the post is empty
	## or its monkey cannot work — which is how `overfeeding_paralyses` and an
	## unbefriended crew reach a firefight.
	func performance(station: int) -> float:
		if crew == null:
			return 0.0
		return crew.station_performance(station)

	func name_text() -> String:
		return "YOUR SHIP" if is_player else "THE ENEMY"


class CombatEvent extends RefCounted:
	var kind: EventKind = EventKind.COMBAT_START
	var elapsed: float = 0.0
	## WHOSE SIDE THIS EVENT IS ABOUT — and read the next sentence, because the
	## name oversells it.
	##
	## For CAUSE events (SHOT_FIRED, WEAPON_CHARGED, POWER_REROUTED, TARGET_CHANGED,
	## DISOBEYED, ENEMY_DESTROYED) it is true when the PLAYER did it. For SUBJECT
	## events (HULL_DAMAGED, SHIELD_ABSORBED, SHOT_EVADED, SYSTEM_DAMAGED,
	## FIRE_STARTED, BREACH_OPENED, CREW_HURT) it is true when it happened TO the
	## player, i.e. the opposite side from whoever caused it.
	##
	## So a HUD must not colour uniformly by this flag: damage YOU deal arrives
	## flagged `false`. That is deliberate — a damage event is about the ship taking
	## it — but it is a trap, and it is pinned by
	## `test_hull_damage_is_attributed_to_the_ship_it_landed_on`.
	var by_player: bool = false
	var station: int = -1
	var amount: int = 0
	var text: String = ""


class CombatResult extends RefCounted:
	var outcome: Outcome = Outcome.NONE
	var events: Array[CombatEvent] = []
	var scrap_reward: int = 0
	var fuel_reward: int = 0
	var missiles_reward: int = 0
	var hull_lost: int = 0
	var elapsed: float = 0.0
	var summary: String = ""

	func player_won() -> bool:
		return outcome == Outcome.PLAYER_WON

	func player_survived() -> bool:
		return outcome != Outcome.PLAYER_DESTROYED


signal event_logged(event: CombatEvent)
signal combat_finished(result: CombatResult)

var player: Combatant = null
var enemy: Combatant = null
var elapsed: float = 0.0
var sector: int = 1

var _rules: GameRules
var _rng: MpRng
var _care: Care

var _finished: bool = false
var _outcome: Outcome = Outcome.NONE
var _result: CombatResult = null
var _tick_pool: float = 0.0
var _all_events: Array[CombatEvent] = []
var _new_events: Array[CombatEvent] = []
var _player_hull_at_start: int = 0
var _enemy_retarget_pool: float = 0.0


func _init(rules: GameRules, rng: MpRng, care: Care) -> void:
	_rules = rules
	_rng = rng
	_care = care


func begin(
		player_ship: Ship,
		player_crew: Crew,
		enemy_ship: Ship,
		enemy_crew: Crew,
		p_sector: int = 1) -> void:
	sector = maxi(1, p_sector)
	player = _make_combatant(player_ship, player_crew, true)
	enemy = _make_combatant(enemy_ship, enemy_crew, false)
	elapsed = 0.0
	_finished = false
	_outcome = Outcome.NONE
	_result = null
	_tick_pool = 0.0
	_enemy_retarget_pool = 0.0
	_all_events = []
	_new_events = []
	_player_hull_at_start = player_ship.hull if player_ship != null else 0
	_log(EventKind.COMBAT_START, true, -1, 0, "AN ENEMY SHIP DROPS OUT OF FTL.", false)


func _make_combatant(ship: Ship, crew: Crew, is_player: bool) -> Combatant:
	var side := Combatant.new()
	side.ship = ship
	side.crew = crew
	side.is_player = is_player
	# Shields start FULL. Arriving at a fight with flat shields would make the
	# first shot land free, and nothing in the design asks for that.
	side.shield_layers = ship.shield_layers_max() if ship != null else 0
	side.shield_charge = 0.0
	side.weapon_charge = 0.0
	side.jump_charge = 0.0
	side.escaping = false
	side.target = Ship.Station.WEAPONS
	return side


# --- the clock ---------------------------------------------------------------

## Step the fight and return ONLY the events this call produced, duplicated so a
## caller holding the batch cannot have later events land in it. Exactly
## `MatchResolver.advance`'s contract.
##
## The UI calls this from `_process`; tests call it with big deltas.
## Returns ONLY the events these ticks produced, duplicated so a caller holding
## the batch cannot have later events land in it. Exactly `MatchResolver.advance`'s
## contract.
##
## Orders are deliberately NOT in here — see `_log` for why, and for what a HUD has
## to do instead.
func advance(delta: float) -> Array[CombatEvent]:
	if player == null or enemy == null:
		_new_events = []
		return [] as Array[CombatEvent]
	if _finished or delta <= 0.0:
		# Still hand back anything an order logged since the last call — a refused
		# order matters even on a tick that does not advance the clock.
		return _drain()

	_tick_pool += delta
	while _tick_pool >= TICK_SECONDS and not _finished:
		_tick_pool -= TICK_SECONDS
		_tick(TICK_SECONDS)
	return _drain()


func _drain() -> Array[CombatEvent]:
	var batch := _new_events.duplicate()
	_new_events = []
	return batch


func _tick(delta: float) -> void:
	elapsed += delta

	# Fixed order — player then enemy — so a replay from the same seed is
	# identical. Anything order-dependent must stay order-dependent the same way.
	_tick_side(player, enemy, delta)
	if not _finished:
		_tick_side(enemy, player, delta)
	if not _finished:
		_tick_repairs(player, delta)
	if not _finished:
		_tick_repairs(enemy, delta)
	if not _finished:
		_tick_hazards(player, delta)
	if not _finished:
		_tick_hazards(enemy, delta)
	if not _finished:
		_tick_enemy_ai(delta)
	if not _finished:
		_award_manning_xp(player, delta)

	if not _finished and elapsed >= MAX_SECONDS:
		_finish(Outcome.DRAW, "NEITHER SHIP CAN FINISH THE OTHER. THE ENEMY BREAKS OFF.")


func _tick_side(side: Combatant, foe: Combatant, delta: float) -> void:
	if side.ship == null:
		return
	_regenerate_shields(side, delta)
	_charge_jump(side, delta)
	if _finished:
		return
	_charge_weapon(side, foe, delta)


## Shield layers can never exceed what the hardware currently supports.
##
## THE BUG THIS FIXES: `set_power` clamped the player's layers when the player
## rerouted power OUT of shields, but nothing clamped them when the shield system
## was SHOT OUT. So knocking out a ship's shields left it still holding the layers
## those bars used to support — which made the single most valuable thing you can do
## to an enemy do very little. One rule, applied on the damage path and every tick,
## to both sides, rather than three places that each have to remember it.
func _clamp_shields(side: Combatant) -> void:
	if side == null or side.ship == null:
		return
	var maximum := side.ship.shield_layers_max()
	if side.shield_layers > maximum:
		side.shield_layers = maximum
		side.shield_charge = 0.0


func _regenerate_shields(side: Combatant, delta: float) -> void:
	_clamp_shields(side)
	var maximum := side.ship.shield_layers_max()
	if side.shield_layers >= maximum:
		# Cap the part-charge too, or a full shield would bank progress it could
		# then spend the instant a layer popped.
		side.shield_charge = 0.0
		return
	var rate := side.ship.shield_recharge_rate(side.performance(Ship.Station.SHIELDS))
	if rate <= 0.0:
		return
	side.shield_charge += rate * delta
	while side.shield_charge >= 1.0 and side.shield_layers < maximum:
		side.shield_charge -= 1.0
		side.shield_layers += 1
		_log(EventKind.SHIELD_RECHARGED, side.is_player, Ship.Station.SHIELDS,
			side.shield_layers, "%s SHIELDS BACK TO %d." % [side.name_text(), side.shield_layers])


func _charge_jump(side: Combatant, delta: float) -> void:
	if not side.escaping:
		return
	var rate := side.ship.jump_charge_rate(side.performance(Ship.Station.ENGINES))
	if rate <= 0.0:
		return
	side.jump_charge = minf(1.0, side.jump_charge + rate * delta)
	if side.jump_charge >= 1.0:
		_log(EventKind.JUMP_CHARGED, side.is_player, Ship.Station.ENGINES, 0,
			"%s JUMP DRIVE IS READY." % side.name_text())
		# ESCAPED was declared in EventKind and never logged, which left a UI with
		# no single event meaning "somebody left the fight".
		_log(EventKind.ESCAPED, side.is_player, Ship.Station.ENGINES, 0,
			"%s JUMPS OUT." % side.name_text())
		if side.is_player:
			_finish(Outcome.PLAYER_ESCAPED, "YOU JUMP CLEAR.")
		else:
			_finish(Outcome.ENEMY_ESCAPED, "THE ENEMY JUMPS AWAY.")


func _charge_weapon(side: Combatant, foe: Combatant, delta: float) -> void:
	var rate := side.ship.weapon_charge_rate(side.performance(Ship.Station.WEAPONS))
	if rate <= 0.0:
		return
	side.weapon_charge += rate * delta
	while side.weapon_charge >= 1.0 and not _finished:
		side.weapon_charge -= 1.0
		_log(EventKind.WEAPON_CHARGED, side.is_player, Ship.Station.WEAPONS, 0,
			"%s WEAPON IS CHARGED." % side.name_text())
		_fire(side, foe)


# --- firing ------------------------------------------------------------------

func _fire(side: Combatant, foe: Combatant) -> void:
	var damage := side.ship.weapon_damage(side.performance(Ship.Station.WEAPONS))
	if damage <= 0:
		return
	_log(EventKind.SHOT_FIRED, side.is_player, side.target, damage,
		"%s FIRES AT THE %s." % [side.name_text(), Ship.station_label(side.target)])
	_award(side, Ship.Station.WEAPONS, XP_ON_SHOT_FIRED)

	# Evasion, less whatever the attacker's sensors can shave off it.
	var evade := foe.ship.evasion(
		foe.performance(Ship.Station.PILOT), foe.performance(Ship.Station.ENGINES))
	var targeting := side.ship.targeting_bonus(side.performance(Ship.Station.SENSORS))
	var effective := clampf(evade - targeting, 0.0, Ship.EVASION_MAX)

	if _rng.chance(effective):
		_log(EventKind.SHOT_EVADED, not side.is_player, -1, 0,
			"%s SLIPS THE SHOT." % foe.name_text())
		_award(foe, Ship.Station.PILOT, XP_ON_SHOT_EVADED)
		return

	_award(side, Ship.Station.SENSORS, XP_ON_HIT_LANDED)

	if foe.shield_layers > 0:
		foe.shield_layers = maxi(0, foe.shield_layers - SHIELD_POP_PER_HIT)
		_log(EventKind.SHIELD_ABSORBED, not side.is_player, Ship.Station.SHIELDS,
			foe.shield_layers,
			"%s SHIELDS HOLD. %d LEFT." % [foe.name_text(), foe.shield_layers])
		_award(foe, Ship.Station.SHIELDS, XP_ON_SHIELD_ABSORBED)
		return

	_land_hit(side, foe, damage)


func _land_hit(side: Combatant, foe: Combatant, damage: int) -> void:
	var applied := foe.ship.take_hull_damage(damage)
	_log(EventKind.HULL_DAMAGED, not side.is_player, -1, applied,
		"%s TAKES %d DAMAGE." % [foe.name_text(), applied])

	# One roll per consequence, always in this order, so the stream is stable.
	if _rng.chance(SYSTEM_DAMAGE_CHANCE):
		var bars := foe.ship.damage_system(side.target, 1)
		if bars > 0:
			_log(EventKind.SYSTEM_DAMAGED, not side.is_player, side.target, bars,
				"%s %s IS HIT." % [foe.name_text(), Ship.station_label(side.target)])
			# Immediately, not next tick: shooting out the shields must visibly
			# strip the layers they were holding up.
			_clamp_shields(foe)
	if _rng.chance(FIRE_CHANCE):
		if foe.ship.start_fire(side.target):
			_log(EventKind.FIRE_STARTED, not side.is_player, side.target, 0,
				"FIRE IN %s %s!" % [foe.name_text(), Ship.station_label(side.target)])
	if _rng.chance(BREACH_CHANCE):
		if foe.ship.open_breach(side.target):
			_log(EventKind.BREACH_OPENED, not side.is_player, side.target, 0,
				"HULL BREACH IN %s %s!" % [foe.name_text(), Ship.station_label(side.target)])
	if _rng.chance(CREW_HURT_CHANCE):
		_hurt_station_crew(foe, side.target, _rng.randi_range(CREW_HURT_MIN, CREW_HURT_MAX))

	if foe.ship.is_destroyed():
		if foe.is_player:
			_log(EventKind.PLAYER_DESTROYED, false, -1, 0, "YOUR HULL GIVES WAY.")
			_finish(Outcome.PLAYER_DESTROYED, "YOUR SHIP IS LOST.")
		else:
			_log(EventKind.ENEMY_DESTROYED, true, -1, 0, "THE ENEMY SHIP BREAKS APART.")
			_finish(Outcome.PLAYER_WON, "THE ENEMY IS DESTROYED.")


## Injure whoever is at a station. Uses `Crew.hurt`, which is deliberately never
## lethal — zero Strength is out cold, not dead (see the DIVERGENCE in crew.gd).
func _hurt_station_crew(side: Combatant, station: int, amount: int) -> void:
	if side.crew == null:
		return
	var member := side.crew.manning(station)
	if member == null:
		return
	var applied := side.crew.hurt(member, amount)
	if applied <= 0:
		return
	_log(EventKind.CREW_HURT, not side.is_player, station, applied,
		"%s IS HURT AT THE %s." % [member.display_name(), Ship.station_label(station)])


# --- hazards -----------------------------------------------------------------

## Damage control. Every FLOATER — living, available, and not at a station — works
## on one job per tick, in a fixed priority order so a replay is identical:
## fires first (they keep doing damage), then breaches, then the worst-damaged
## system.
##
## Rate scales with the monkey's STRENGTH, faithfully: STRENGTH is the physical
## stat and the health bar (dossier §3), so the toughest monkey is also the best
## with a fire extinguisher. An unbefriended or paralysed floater does nothing —
## `Crew.is_available` carries both faithful rules, so an overfed monkey cannot be
## press-ganged into damage control either.
func _tick_repairs(side: Combatant, delta: float) -> void:
	if side.crew == null or side.ship == null:
		return
	for member in side.crew.floaters():
		if not side.crew.is_available(member):
			continue
		var effort := _labour_rate(member) * delta
		if effort <= 0.0:
			continue
		if _work_on_fire(side, member, effort):
			continue
		if _work_on_breach(side, member, effort):
			continue
		_work_on_damage(side, member, effort)


## How fast this monkey works, as a multiple of a reference-STRENGTH monkey.
func _labour_rate(member: Crew.Member) -> float:
	if member == null or member.monkey == null:
		return 0.0
	var strength := float(member.monkey.get_stat(Monkey.Stat.STRENGTH))
	return maxf(0.0, strength / Crew.REFERENCE_STAT)


var _repair_pool: Dictionary = {}


## Accumulate sub-1 progress, because a 0.12/second repair cannot show up on a
## 0.25s tick otherwise.
func _bank(key: String, amount: float, threshold: float) -> bool:
	var pool := float(_repair_pool.get(key, 0.0)) + amount
	if pool >= threshold:
		_repair_pool[key] = pool - threshold
		return true
	_repair_pool[key] = pool
	return false


func _side_key(side: Combatant) -> String:
	return "p" if side.is_player else "e"


func _work_on_fire(side: Combatant, member: Crew.Member, effort: float) -> bool:
	for station in Ship.STATIONS:
		if not side.ship.has_fire(station):
			continue
		var key := "fire:%s:%d" % [_side_key(side), station]
		if _bank(key, effort * FIRE_FIGHT_PER_SECOND, 1.0):
			if side.ship.extinguish(station):
				_log(EventKind.FIRE_OUT, side.is_player, station, 0,
					"%s PUTS OUT THE FIRE IN %s." % [
						member.display_name(), Ship.station_label(station)])
		return true
	return false


func _work_on_breach(side: Combatant, member: Crew.Member, effort: float) -> bool:
	for station in Ship.STATIONS:
		if not side.ship.has_breach(station):
			continue
		var key := "breach:%s:%d" % [_side_key(side), station]
		if _bank(key, effort * SEAL_BREACH_PER_SECOND, 1.0):
			if side.ship.seal(station):
				_log(EventKind.SYSTEM_REPAIRED, side.is_player, station, 0,
					"%s SEALS THE BREACH IN %s." % [
						member.display_name(), Ship.station_label(station)])
		return true
	return false


func _work_on_damage(side: Combatant, member: Crew.Member, effort: float) -> void:
	var worst := -1
	var worst_bars := 0
	for station in Ship.STATIONS:
		var bars := side.ship.damage_in(station)
		if bars > worst_bars:
			worst_bars = bars
			worst = station
	if worst < 0:
		return
	var key := "repair:%s:%d" % [_side_key(side), worst]
	if not _bank(key, effort * REPAIR_BARS_PER_SECOND, 1.0):
		return
	if side.ship.repair_system(worst, 1) > 0:
		_log(EventKind.SYSTEM_REPAIRED, side.is_player, worst, 1,
			"%s PATCHES UP %s." % [member.display_name(), Ship.station_label(worst)])
		# A repaired shield system can hold its layers again, but must not be
		# handed them back for free — it recharges them like anything else.
		_clamp_shields(side)


func _tick_hazards(side: Combatant, delta: float) -> void:
	if side.ship == null:
		return
	for station in Ship.STATIONS:
		if side.ship.has_fire(station):
			_burn(side, station, delta)
		if side.ship.has_breach(station):
			_bleed(side, station, delta)


## Fires are tracked as accumulating fractions on the combat, not on the ship —
## `Ship` stays a plain state bag and the sim owns the timing.
var _fire_pool: Dictionary = {}
var _breach_pool: Dictionary = {}


func _burn(side: Combatant, station: int, delta: float) -> void:
	var key := "%s:%d" % ["p" if side.is_player else "e", station]
	var pool := float(_fire_pool.get(key, 0.0)) + delta
	var system_damage := FIRE_SYSTEM_DAMAGE_PER_SECOND * pool
	if system_damage >= 1.0:
		pool = 0.0
		var bars := side.ship.damage_system(station, 1)
		if bars > 0:
			_log(EventKind.SYSTEM_DAMAGED, not side.is_player, station, bars,
				"THE FIRE EATS INTO %s %s." % [side.name_text(), Ship.station_label(station)])
	_fire_pool[key] = pool
	_hurt_over_time(side, station, FIRE_CREW_DAMAGE_PER_SECOND * delta, "fire")


func _bleed(side: Combatant, station: int, delta: float) -> void:
	_hurt_over_time(side, station, BREACH_CREW_DAMAGE_PER_SECOND * delta, "breach")


var _crew_damage_pool: Dictionary = {}


## Accumulate sub-1 damage so a 0.8/second fire actually hurts on a 0.25s tick.
func _hurt_over_time(side: Combatant, station: int, amount: float, source: String) -> void:
	if side.crew == null or amount <= 0.0:
		return
	var key := "%s:%d:%s" % ["p" if side.is_player else "e", station, source]
	var pool := float(_crew_damage_pool.get(key, 0.0)) + amount
	if pool >= 1.0:
		var whole := int(floorf(pool))
		pool -= float(whole)
		_hurt_station_crew(side, station, whole)
	_crew_damage_pool[key] = pool


# --- the enemy -----------------------------------------------------------------

func _tick_enemy_ai(delta: float) -> void:
	# `begin`/`_make_combatant` tolerate a null Ship (some tests fight crewless or
	# shipless sides), so guard rather than dereference — a runtime error raised in
	# here would unwind the tick and still be reported as a PASS.
	if enemy == null or enemy.ship == null or player == null or player.ship == null:
		return
	_enemy_retarget_pool += delta
	if _enemy_retarget_pool >= ENEMY_RETARGET_SECONDS:
		_enemy_retarget_pool -= ENEMY_RETARGET_SECONDS
		# Aim at whatever is currently working best against it. Deterministic —
		# no roll — so a replay is identical.
		enemy.target = _best_enemy_target()
	if not enemy.escaping and enemy.ship.hull_max > 0:
		var fraction := float(enemy.ship.hull) / float(enemy.ship.hull_max)
		if fraction <= ENEMY_FLEE_HULL_FRACTION:
			enemy.escaping = true


## The player system the enemy most wants gone: whichever of Weapons and Shields
## is still doing the most for them.
func _best_enemy_target() -> int:
	var weapons := player.ship.effective_power(Ship.Station.WEAPONS)
	var shields := player.ship.effective_power(Ship.Station.SHIELDS)
	if shields > weapons:
		return Ship.Station.SHIELDS
	if weapons > 0:
		return Ship.Station.WEAPONS
	return Ship.Station.ENGINES


# --- orders — the pause-time verbs -------------------------------------------

## Reroute power. Design §7: the spirit stops time to issue orders.
##
## Obedience is rolled ONCE PER ORDER, never per tick. Rolling per tick would turn
## `disobedience_enabled` into a slot machine and would make a replay depend on
## how long the player left the order standing.
func set_power(station: int, bars: int) -> bool:
	if _finished or player == null or player.ship == null:
		return false
	if not Ship.STATIONS.has(station):
		return false

	# A NO-OP ORDER MUST NOT COST AN OBEDIENCE ROLL. Checked before `_order_obeyed`
	# deliberately, and this ordering is load-bearing.
	#
	# THE BUG THIS FIXES: the obedience roll came first, so asking for the
	# allocation a system already had still consumed an RNG draw. `VoyageState`
	# shares one `MpRng` between combat, `Care` and `SectorMap.generate`, which
	# meant the layout of the NEXT sector depended on how many times the player
	# re-clicked a power slider. Measured at exactly one leaked draw per redundant
	# order: 0 no-op pairs gave 45 total draws, 7 pairs gave 59.
	#
	# This is the same class of bug as the one tests/unit/test_core_purity.gd was
	# written for, arriving through a different door: there it was a read-only
	# predicate that rolled, here it is a write that changes nothing but rolls.
	var before := player.ship.power_in(station)
	var target := clampi(bars, 0, player.ship.max_bars(station))
	if target == before:
		return target == bars

	if not _order_obeyed(station):
		return false
	var reached := player.ship.set_power(station, bars)
	var after := player.ship.power_in(station)
	if after != before:
		_log(EventKind.POWER_REROUTED, true, station, after,
			"%s POWER SET TO %d." % [Ship.station_label(station), after], false)
		# Shields cannot hold more layers than the new allocation supports.
		_clamp_shields(player)
	return reached


func set_target(station: int) -> void:
	if _finished or player == null:
		return
	if not Ship.STATIONS.has(station):
		return
	# Before the obedience roll, for the same reason as `set_power`: re-selecting
	# the target already selected must be free, or the random stream depends on how
	# many times the player tapped the same button.
	if player.target == station:
		return
	if not _order_obeyed(Ship.Station.WEAPONS):
		return
	player.target = station
	_log(EventKind.TARGET_CHANGED, true, station, 0,
		"TARGETING THE ENEMY %s." % Ship.station_label(station), false)


## Start charging the jump drive to run away.
func begin_escape() -> void:
	if _finished or player == null:
		return
	# Already running: a second order is a no-op and must not roll. Same reasoning
	# as `set_power`.
	if player.escaping:
		return
	if not _order_obeyed(Ship.Station.ENGINES):
		return
	player.escaping = true


## Whether the monkey responsible for an order actually follows it.
##
## `Care.obeys` carries the FAITHFUL `disobedience_enabled` rule (dossier §6 [C]):
## a low-friendship monkey ignores you. Design §2 is explicit that this is BETTER
## tension in a firefight than it was in a boxing ring — do not soften it.
##
## An unmanned station has nobody to disobey, so the order goes through: the
## hardware does as it is told even with the seat empty.
func _order_obeyed(station: int) -> bool:
	if player.crew == null or _care == null:
		return true
	var member := player.crew.manning(station)
	if member == null:
		return true
	if _care.obeys(member.monkey):
		return true
	_log(EventKind.DISOBEYED, true, station, 0,
		"%s IGNORES YOU." % member.display_name(), false)
	return false


# --- crew progress -----------------------------------------------------------

func _award_manning_xp(side: Combatant, delta: float) -> void:
	if side.crew == null:
		return
	for station in Ship.STATIONS:
		side.crew.award_station_xp(station, XP_PER_SECOND_MANNED * delta)


## One-off award for a notable moment. Only the player's crew levels up — the
## enemy's is thrown away when the fight ends.
func _award(side: Combatant, station: int, amount: float) -> void:
	if not side.is_player or side.crew == null:
		return
	side.crew.award_station_xp(station, amount)


# --- finishing ---------------------------------------------------------------

func _finish(outcome: Outcome, summary: String) -> void:
	if _finished:
		return
	_finished = true
	_outcome = outcome

	var built := CombatResult.new()
	built.outcome = outcome
	built.elapsed = elapsed
	built.summary = summary
	built.hull_lost = maxi(0, _player_hull_at_start - (player.ship.hull if player.ship != null else 0))

	# Only a kill pays. Escaping with your life is its own reward.
	if outcome == Outcome.PLAYER_WON:
		built.scrap_reward = SCRAP_REWARD_BASE + SCRAP_REWARD_PER_SECTOR * (sector - 1)
		if _rng.chance(FUEL_REWARD_CHANCE):
			built.fuel_reward = _rng.randi_range(1, 3)
		if _rng.chance(MISSILE_REWARD_CHANCE):
			built.missiles_reward = _rng.randi_range(1, 2)

	_log(EventKind.COMBAT_END, outcome == Outcome.PLAYER_WON, -1, 0, summary)
	built.events = _all_events.duplicate()
	_result = built
	combat_finished.emit(built)


func is_finished() -> bool:
	return _finished


func outcome() -> Outcome:
	return _outcome


func result() -> CombatResult:
	if _result == null:
		var empty := CombatResult.new()
		empty.events = _all_events.duplicate()
		empty.elapsed = elapsed
		return empty
	return _result


## Pay the rewards into a voyage. Kept separate from `_finish` so a test can
## inspect a result without it having side effects, and so the UI decides when the
## salvage screen actually credits it.
## Idempotent: the salvage is paid at most once, however many times this is
## called. Without the guard, re-entering a salvage screen (or a UI that calls it
## on both `combat_finished` and screen-enter) would credit the scrap, fuel and
## missiles again — free money for a double tap.
var _rewards_paid: bool = false


func apply_rewards(economy: Economy, ship: Ship) -> void:
	if _result == null or _rewards_paid:
		return
	_rewards_paid = true
	if economy != null and _result.scrap_reward > 0:
		economy.earn_scrap(_result.scrap_reward)
	if ship != null:
		if _result.fuel_reward > 0:
			ship.add_fuel(_result.fuel_reward)
		if _result.missiles_reward > 0:
			ship.add_missiles(_result.missiles_reward)


# --- test and fast-forward hooks ---------------------------------------------

## Run the whole fight with no orders. Mirrors `MatchResolver.simulate_match`.
func simulate(max_seconds: float = MAX_SECONDS) -> CombatResult:
	if player == null or enemy == null:
		push_error("ShipCombat.simulate before begin()")
		return CombatResult.new()
	var guard := 0
	var limit := int(max_seconds / TICK_SECONDS) + 8
	while not _finished and guard < limit:
		guard += 1
		advance(TICK_SECONDS)
	if not _finished:
		_finish(Outcome.DRAW, "THE ENGAGEMENT IS BROKEN OFF.")
	return result()


## Step until `predicate` returns true, or the fight ends. The predicate receives
## this resolver. Useful for "advance to the first shot, then give an order".
func simulate_until(predicate: Callable, max_seconds: float = MAX_SECONDS) -> CombatResult:
	if player == null or enemy == null:
		push_error("ShipCombat.simulate_until before begin()")
		return CombatResult.new()
	var guard := 0
	var limit := int(max_seconds / TICK_SECONDS) + 8
	while not _finished and guard < limit:
		if bool(predicate.call(self)):
			break
		guard += 1
		advance(TICK_SECONDS)
	return result()


## Events logged so far, whole fight. PURE.
func events() -> Array[CombatEvent]:
	return _all_events.duplicate()


func events_of_kind(kind: EventKind) -> Array[CombatEvent]:
	var out: Array[CombatEvent] = []
	for event in _all_events:
		if event.kind == kind:
			out.append(event)
	return out


func has_event(kind: EventKind) -> bool:
	for event in _all_events:
		if event.kind == kind:
			return true
	return false


# --- an opponent -------------------------------------------------------------

## Build an enemy scaled to the sector. Returns `[Ship, Crew]`.
##
## AMENDMENT to MISSION-ARCHITECTURE §10, recorded per §0: the contract wrote this
## as `make_enemy(sector, rng)`, but a `Crew` needs a `Care`, which needs a
## `GameRules`. Passing rules in is the only honest way to build one; it defaults
## to a fresh `GameRules` so a test can still call it with two arguments.
static func make_enemy(p_sector: int, rng: MpRng, rules: GameRules = null) -> Array:
	var use_rules := rules if rules != null else GameRules.new()
	var depth := maxi(1, p_sector)

	var ship := Ship.new()
	# DIVERGENCE: design §9 #4. A sector-1 enemy is deliberately weaker than the
	# player's starter (hull 30, reactor 8) so a first fight is winnable while the
	# crew is still unbefriended and half the stations read as empty.
	ship.hull_max = ENEMY_HULL_BASE + ENEMY_HULL_PER_SECTOR * (depth - 1)
	ship.hull = ship.hull_max
	ship.reactor = mini(Ship.REACTOR_MAX, ENEMY_REACTOR_BASE + (depth - 1))
	ship.fuel = 0
	ship.missiles = 0
	# Spend the reactor on the three systems that matter in a fight, weapons first.
	var order: Array[int] = [
		Ship.Station.WEAPONS, Ship.Station.SHIELDS, Ship.Station.ENGINES,
		Ship.Station.PILOT, Ship.Station.SENSORS,
	]
	var remaining := ship.reactor
	for station in order:
		var want := mini(2, remaining)
		if want <= 0:
			break
		if ship.allocate(station, want):
			remaining -= want

	var care := Care.new(use_rules, rng)
	var crew := Crew.new(use_rules, rng, care)
	var stat_target := ENEMY_STAT_BASE + ENEMY_STAT_PER_SECTOR * (depth - 1)
	for index in ENEMY_CREW_SIZE:
		var caps := {}
		for stat in Monkey.STATS:
			caps[stat] = stat_target * 2
		var monkey := Monkey.create("RAIDER %d" % (index + 1), SpeciesDb.default_type(), caps)
		for stat in Monkey.STATS:
			monkey.set_stat(stat, int(rng.spread(
				float(stat_target), float(stat_target) * ENEMY_STAT_JITTER,
				1.0, float(stat_target * 2))))
		# An enemy crew trusts its OWN captain, so they must be befriended and fed
		# or their stations would read as unmanned and the fight would be a
		# walkover. Befriending gates everything (dossier §5 [C]) — including for
		# the other side.
		monkey.friendship = Monkey.FRIENDSHIP_MAX
		monkey.fullness = ENEMY_FULLNESS
		monkey.restore_pools()
		crew.add(monkey)
	crew.auto_assign()
	return [ship, crew]


## DIVERGENCE: design §9 #4 — enemy scaling is [X], all of these.
const ENEMY_HULL_BASE := 18
const ENEMY_HULL_PER_SECTOR := 8
const ENEMY_REACTOR_BASE := 6
const ENEMY_STAT_BASE := 55
const ENEMY_STAT_PER_SECTOR := 28
const ENEMY_STAT_JITTER := 0.18
const ENEMY_CREW_SIZE := 3
const ENEMY_FULLNESS := 12


static func kind_label(kind: EventKind) -> String:
	return String(EventKind.keys()[clampi(int(kind), 0, EventKind.keys().size() - 1)])


## `batch` controls whether this event joins the pending batch that the next
## `advance()` hands back. ONE SOURCE OF TRUTH PER EVENT: anything logged OUTSIDE a
## tick passes false, so a caller cannot receive it twice.
##
## That covers COMBAT_START (logged by `begin`) and every order — POWER_REROUTED,
## TARGET_CHANGED, DISOBEYED — which are logged between frames by `set_power`,
## `set_target` and `begin_escape`.
##
## THE TRAP, and it is a real one: `advance()` therefore never hands back a refused
## order. A HUD that renders only `advance()`'s return value will show the player
## nothing when a monkey ignores them. Orders must be read from the `event_logged`
## signal or from `events()`. The alternative — batching them — would make a UI
## that listens to BOTH sources double-print every line, which is worse. Pinned by
## `test_advance_returns_only_the_events_from_that_call`.
func _log(kind: EventKind, by_player: bool, station: int, amount: int, text: String,
		batch: bool = true) -> CombatEvent:
	var event := CombatEvent.new()
	event.kind = kind
	event.elapsed = elapsed
	event.by_player = by_player
	event.station = station
	event.amount = amount
	event.text = text
	_all_events.append(event)
	if batch:
		_new_events.append(event)
	event_logged.emit(event)
	return event
