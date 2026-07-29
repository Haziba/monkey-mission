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
	## True when the PLAYER caused it. A shot the enemy fired at you is
	## `by_player == false`, and the hull damage it does is also false.
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
	_log(EventKind.COMBAT_START, true, -1, 0, "AN ENEMY SHIP DROPS OUT OF FTL.")


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
func advance(delta: float) -> Array[CombatEvent]:
	_new_events = []
	if _finished or delta <= 0.0 or player == null or enemy == null:
		return [] as Array[CombatEvent]

	_tick_pool += delta
	while _tick_pool >= TICK_SECONDS and not _finished:
		_tick_pool -= TICK_SECONDS
		_tick(TICK_SECONDS)
	return _new_events.duplicate()


func _tick(delta: float) -> void:
	elapsed += delta

	# Fixed order — player then enemy — so a replay from the same seed is
	# identical. Anything order-dependent must stay order-dependent the same way.
	_tick_side(player, enemy, delta)
	if not _finished:
		_tick_side(enemy, player, delta)
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
	if not _order_obeyed(station):
		return false
	var before := player.ship.power_in(station)
	var reached := player.ship.set_power(station, bars)
	var after := player.ship.power_in(station)
	if after != before:
		_log(EventKind.POWER_REROUTED, true, station, after,
			"%s POWER SET TO %d." % [Ship.station_label(station), after])
		# Shields cannot hold more layers than the new allocation supports.
		player.shield_layers = mini(player.shield_layers, player.ship.shield_layers_max())
	return reached


func set_target(station: int) -> void:
	if _finished or player == null:
		return
	if not Ship.STATIONS.has(station):
		return
	if not _order_obeyed(Ship.Station.WEAPONS):
		return
	if player.target == station:
		return
	player.target = station
	_log(EventKind.TARGET_CHANGED, true, station, 0,
		"TARGETING THE ENEMY %s." % Ship.station_label(station))


## Start charging the jump drive to run away.
func begin_escape() -> void:
	if _finished or player == null:
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
		"%s IGNORES YOU." % member.display_name())
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
func apply_rewards(economy: Economy, ship: Ship) -> void:
	if _result == null:
		return
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


func _log(kind: EventKind, by_player: bool, station: int, amount: int, text: String) -> CombatEvent:
	var event := CombatEvent.new()
	event.kind = kind
	event.elapsed = elapsed
	event.by_player = by_player
	event.station = station
	event.amount = amount
	event.text = text
	_all_events.append(event)
	_new_events.append(event)
	event_logged.emit(event)
	return event
