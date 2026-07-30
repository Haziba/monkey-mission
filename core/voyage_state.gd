class_name VoyageState
extends RefCounted

## One expedition, and everything permadeath destroys.
##
## See docs/MISSION-ARCHITECTURE.md §6. This is half of the eventual split of
## `core/run_state.gd` (design §3): the disposable half. `StableState` — the
## persistent bloodlines that survive a lost ship — is phase 7.
##
## ADDITIVE FOR NOW. `RunState` is untouched and still owns the boxing-era run,
## so nothing here breaks the existing game or its tests. See the DECISION note in
## MISSION-ARCHITECTURE.md §2 for why the retirement is a separate, attended
## phase rather than something done overnight.
##
## Exists for the same reason `RunState` does: so core never touches the
## `GameState` autoload. A test builds one of these directly.

var rules: GameRules = null
var rng: MpRng = null

var ship: Ship = null
var crew: Crew = null
var voyage: Voyage = null

## Scrap and the larder. Design §5 repoints `Economy` rather than replacing it;
## `economy.scrap` and `economy.money` are the same integer (§11).
var economy: Economy = null

## Systems operating on the crew. `Care` is shared with `Crew`, deliberately — the
## same instance answers "will this monkey work?" for both the ship and the feed
## screen, so the two can never disagree.
var care: Care = null
var training: Training = null

## Voyage-scoped flags ("met_the_trader", "boss_seen"). Not the stable's.
var flags: Dictionary = {}

## Wall-clock seconds, for the save summary.
var play_seconds: float = 0.0


## Build a fresh voyage.
##
## `roster` is the crew the player fielded from the stable. Up to
## `Crew.VOYAGE_START_SIZE` are taken; passing an empty array generates that many
## fresh monkeys instead, which is what a first-ever voyage does before any
## breeding has happened.
static func new_voyage(
		p_rules: GameRules,
		p_rng: MpRng,
		roster: Array[Monkey] = []) -> VoyageState:
	var state := VoyageState.new()

	# Duplicated rather than shared, for the same reason `RunState.new_run` does
	# it: `GameRules.load_default()` hands back one cached resource instance, so
	# two voyages flipping a flag would otherwise see each other's changes.
	if p_rules != null:
		var copy := p_rules.duplicate() as GameRules
		state.rules = copy if copy != null else p_rules
	else:
		var defaults := GameRules.load_default()
		var copy := defaults.duplicate() as GameRules
		state.rules = copy if copy != null else defaults

	state.rng = p_rng if p_rng != null else MpRng.new(0)

	state.economy = Economy.new(state.rules)
	# Scaled by crew size, and this is not a nicety.
	#
	# `FoodDb.starting_inventory()` is 4 bananas — sized for the boxing game, which
	# had exactly ONE monkey. A voyage sails with `Crew.VOYAGE_START_SIZE` of them,
	# all unbefriended (dossier §5 [C]), and each needs roughly two bananas to cross
	# `Monkey.FRIENDSHIP_TRAIN_MIN`. So the unscaled larder could befriend ONE
	# crewman and left the other three refusing to work: four of five stations dead,
	# and a ship that loses its first serious fight through no fault of the player.
	#
	# Found by playing a voyage end to end, not by a unit test — see
	# docs/MORNING-REPORT.md §7.
	var pantry := FoodDb.starting_inventory()
	for food_id in pantry:
		state.economy.add_food(
			String(food_id), int(pantry[food_id]) * Crew.VOYAGE_START_SIZE)

	state.care = Care.new(state.rules, state.rng)
	state.training = Training.new(state.rules, state.rng)

	state.ship = Ship.make_starter()
	state.crew = Crew.new(state.rules, state.rng, state.care)

	var chosen := roster
	if chosen.is_empty():
		chosen = make_starting_crew(state.rng)
	for index in mini(chosen.size(), Crew.VOYAGE_START_SIZE):
		state.crew.add(chosen[index])
	state.crew.auto_assign()

	state.voyage = Voyage.new(state.rules, state.rng)
	state.voyage.begin(state.ship)

	state.flags = {}
	state.play_seconds = 0.0
	return state


## The crew a first voyage sails with, before the stable has anything in it.
##
## DIVERGENCE: [X]. Design §2.6 says the player names every monkey with a *Random*
## button available, and §6 says crews are assembled in the stable — neither of
## which exists yet. These four are drawn from the attested food-themed pool
## (`Crew.NAME_POOL`) so the placeholder reads like the real thing, and every one
## of them is renameable when the crew-select screen lands.
##
## They start UNBEFRIENDED, faithfully: dossier §5 [C] says every new monkey,
## Freddy included, must be won over with food first. So a fresh voyage opens with
## four monkeys posted to stations and none of them yet willing to work, which is
## the original's opening problem restated in space.
static func make_starting_crew(p_rng: MpRng) -> Array[Monkey]:
	var out: Array[Monkey] = []
	var used := PackedStringArray()
	for index in Crew.VOYAGE_START_SIZE:
		var monkey_name := Crew.random_name(p_rng, used)
		used.append(monkey_name)
		var species := SpeciesDb.all()[index % SpeciesDb.all().size()]
		var monkey := RunState.make_starter(species.type)
		monkey.monkey_name = monkey_name
		out.append(monkey)
	return out


func is_over() -> bool:
	return voyage == null or voyage.is_over()


## Drive the permadeath check. Returns the reason, `EndReason.NONE` while alive.
func settle() -> Voyage.EndReason:
	if voyage == null:
		return Voyage.EndReason.NONE
	return voyage.settle(ship, crew)


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: String, value: bool = true) -> void:
	flags[flag] = value


# --- serialisation -----------------------------------------------------------
#
# The voyage save is the DISPOSABLE layer (design §9 #12): losing it costs the
# expedition, never the bloodlines. `Stable` gets its own file in phase 7.

func to_dict() -> Dictionary:
	return {
		"rng_seed": rng.seed_value() if rng != null else 0,
		"rng_state": rng.state() if rng != null else 0,
		"ship": ship.to_dict() if ship != null else {},
		"crew": crew.to_dict() if crew != null else {},
		"voyage": voyage.to_dict() if voyage != null else {},
		"economy": economy.to_dict() if economy != null else {},
		"flags": flags.duplicate(),
		"play_seconds": play_seconds,
	}


static func from_dict(d: Dictionary) -> VoyageState:
	var state := VoyageState.new()

	var defaults := GameRules.load_default()
	var copy := defaults.duplicate() as GameRules
	state.rules = copy if copy != null else defaults

	state.rng = MpRng.new(int(d.get("rng_seed", 1)))
	# Restoring the STREAM POSITION as well as the seed is what makes a reloaded
	# voyage continue the same random sequence rather than replaying it.
	state.rng.set_state(int(d.get("rng_state", state.rng.state())))

	state.care = Care.new(state.rules, state.rng)
	state.training = Training.new(state.rules, state.rng)

	state.economy = Economy.new(state.rules)
	var economy_data: Variant = d.get("economy", {})
	if economy_data is Dictionary:
		state.economy.apply_dict(economy_data as Dictionary)

	state.ship = Ship.new()
	var ship_data: Variant = d.get("ship", {})
	if ship_data is Dictionary:
		state.ship.apply_dict(ship_data as Dictionary)

	state.crew = Crew.new(state.rules, state.rng, state.care)
	var crew_data: Variant = d.get("crew", {})
	if crew_data is Dictionary:
		state.crew.apply_dict(crew_data as Dictionary)

	state.voyage = Voyage.new(state.rules, state.rng)
	var voyage_data: Variant = d.get("voyage", {})
	if voyage_data is Dictionary:
		state.voyage.apply_dict(voyage_data as Dictionary)

	var raw_flags: Variant = d.get("flags", {})
	if raw_flags is Dictionary:
		state.flags = (raw_flags as Dictionary).duplicate()
	state.play_seconds = float(d.get("play_seconds", 0.0))
	return state
