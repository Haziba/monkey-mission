class_name RunState
extends RefCounted

## Everything a single playthrough consists of, as pure data + owned systems.
##
## This exists so that core never has to touch the GameState autoload: tests
## build a RunState directly, and SaveGame serialises a RunState. The GameState
## autoload owns exactly one of these and is a thin signalling facade over it.

## Dossier §11 [C]: you play whichever sibling was NOT taken by the Saru Group.
## Not purely cosmetic in the original — the item drop table varies by
## protagonist — but the slice cuts items, so this is flavour here.
enum Protagonist { KENTA, SUMIRE }

## Where the run currently is, so the router and the save file agree.
enum Phase {
	INTRO,        ## Fred hands over Freddy (dossier §7 phase 0)
	BEFRIEND,     ## feed it until it will train
	LADDER,       ## the day cycle proper
	MATCH_DAY,    ## Bill's offer accepted, fight tomorrow
	BREEDING,     ## at the dating shop
	CHAMPION,     ## rank 1 reached — end of the slice
}

var protagonist: Protagonist = Protagonist.KENTA
var phase: Phase = Phase.INTRO

var rules: GameRules = null
var rng: MpRng = null

## The monkey currently in training. Never null after the intro.
var active_monkey: Monkey = null
## Retired parents, kept viewable because GameRules.breeding_destroys_parent is
## false. The original vanishes them (dossier §8 [C]).
var roster: Array[Monkey] = []

var day_cycle: DayCycle = null
var economy: Economy = null
var ladder: Ladder = null

## Systems. Stateless-ish helpers that operate on the data above.
var care: Care = null
var training: Training = null
var breeding: Breeding = null

## The opponent Bill booked for tomorrow, or null.
var booked_opponent: Ladder.Opponent = null

## Story/tutorial flags the UI checks, e.g. "seen_intro", "passed_pro_test".
var flags: Dictionary = {}

## Wall-clock seconds played, for the save slot summary.
var play_seconds: float = 0.0


## Freddy's name is fixed (dossier §8 [C]) and Fred hands him over on day 1
## (§7 phase 0 [C]).
const STARTER_NAME := "Freddy"

## DIVERGENCE: what the starter's STATS (as opposed to its caps) begin at is
## [X] — §3 gives Freddy's cap tuple but no source records his opening numbers,
## and the one attested stat card (§10, `POW 74 / SPD 65 / KNOW 56 / STRG 61 /
## STM 83`) belongs to a rank-13 monkey mid-run, not to a day-1 starter. 40% of
## each cap is chosen so Freddy reads as a real fighter rather than an empty
## husk, while still losing to the rank-5 ladder until he has been trained —
## `Ladder.RANK_STAT_BASE` puts the bottom rung at an average of 90 and 40% of
## Freddy's caps averages 54. Breeding's own babies start far lower
## (`Breeding.BABY_START_STAT`), which is correct: §8 [C] says the baby starts
## near zero and must be raised from scratch.
const STARTER_STAT_FRACTION := 0.40

## DIVERGENCE: the starter's opening fullness is [X]. 12 sits in Care's CONTENT
## band — not starving, not stuffed — so day 1 opens with a monkey that can be
## befriended immediately rather than one that is already immobilised.
const STARTER_FULLNESS := 12


## Build a fresh run: rules, rng, systems, starting money and food, and the
## starter monkey. Dossier §7 phase 0 [C]: Fred gives you Freddy, whose name is
## fixed, and Freddy's caps are the fixed tuple observed in the wild
## (Pow 145 / Spd 119 / Know 116 / Str 145 / Stm 145, §3 [U]).
##
## `seed_value` of 0 seeds MpRng from the clock; pass a non-zero value for a
## reproducible run (which is what the tests do).
static func new_run(p_protagonist: Protagonist, seed_value: int = 0) -> RunState:
	var state := RunState.new()
	state.protagonist = p_protagonist
	# The title screen routes a fresh run into the prologue; monkey-select moves
	# it on to BEFRIEND once the player has taken a monkey.
	state.phase = Phase.INTRO

	# Duplicated rather than shared: `GameRules.load_default()` hands back the
	# one cached resource instance behind `res://game_rules.tres`, so two runs
	# (or two tests) flipping a flag would otherwise see each other's changes.
	var defaults := GameRules.load_default()
	state.rules = defaults.duplicate() as GameRules
	if state.rules == null:
		state.rules = defaults

	state.rng = MpRng.new(seed_value)

	state.economy = Economy.new(state.rules)
	# Dossier §5 [C]: the documented fastest befriending is two bananas, so the
	# starting larder has to contain them.
	var pantry := FoodDb.starting_inventory()
	for food_id in pantry:
		state.economy.add_food(String(food_id), int(pantry[food_id]))

	state.day_cycle = DayCycle.new()
	state.ladder = Ladder.new(state.rules, state.rng)
	state.care = Care.new(state.rules, state.rng)
	state.training = Training.new(state.rules, state.rng)
	state.breeding = Breeding.new(state.rules, state.rng)

	state.active_monkey = make_starter()
	state.roster = []
	state.booked_opponent = null
	state.flags = {}
	state.play_seconds = 0.0
	return state


## The day-1 monkey. Split out so a test (and `GameState.set_starter_species`)
## can rebuild it without rebuilding the whole run.
static func make_starter(species_type: Species.Type = SpeciesDb.default_type()) -> Monkey:
	var monkey := Monkey.create(
		STARTER_NAME, species_type, starter_caps_for(species_type), 1, Monkey.Sex.MALE)
	for stat in Monkey.STATS:
		monkey.set_stat(stat, int(round(monkey.get_cap(stat) * STARTER_STAT_FRACTION)))
	# Dossier §5 [C]: "Befriending gates everything. Every new monkey, Freddy
	# included, must be won over with food before it will train. Until then it is
	# disobedient and will bite you." Friendship therefore starts at zero, below
	# Monkey.FRIENDSHIP_TRAIN_MIN.
	monkey.friendship = 0
	monkey.fullness = STARTER_FULLNESS
	monkey.restore_pools()
	return monkey


## Freddy's starting caps. Dossier §3 [U] — inferred from three players'
## RetroAchievements rich-presence data, byte-identical, documented nowhere.
static func starter_caps() -> Dictionary:
	return {
		Monkey.Stat.POWER: 145,
		Monkey.Stat.SPEED: 119,
		Monkey.Stat.KNOWLEDGE: 116,
		Monkey.Stat.STRENGTH: 145,
		Monkey.Stat.STAMINA: 145,
	}


## `starter_caps()` shaped by the chosen type's `Species.cap_bias`.
##
## Freddy is a fixed monkey of a fixed type in the original (§7 phase 0 [C]);
## the brief adds the type choice, and `Species.cap_bias` is documented in
## core as "multiplier applied to each starting cap". `ui/screens/monkey_select.gd`
## already SHOWS the player the biased tuple before they commit, so this is what
## makes that projection true — without it the screen advertised a difference
## between the five types that nothing ever applied, and every starter silently
## came out with the same ceilings.
##
## DIVERGENCE: the per-type bias itself is invented — §14.4 [X] says the types
## are not even named and §8 [C] only ties type to food preferences and drop
## rates. The default type (SUNBURST, Freddy's own) is biased 1.0 across the
## board, so the attested tuple in §3 [U] is reproduced exactly.
static func starter_caps_for(species_type: Species.Type) -> Dictionary:
	var base := starter_caps()
	var species := SpeciesDb.get_species(species_type)
	if species == null:
		return base
	var out := {}
	for stat in Monkey.STATS:
		out[stat] = maxi(1, int(round(float(base[stat]) * species.cap_bias_for(stat))))
	return out


func has_flag(flag: String) -> bool:
	return bool(flags.get(flag, false))


func set_flag(flag: String, value: bool = true) -> void:
	flags[flag] = value
