class_name Monkey
extends Resource

## A single monkey: the five stats, their hard caps, species, name, friendship,
## fullness, generation and sex. Pure data plus clamping — no scene tree.
##
## Dossier §3 [C]. THE NAMING TRAP: **Strength is the health bar, Power is
## damage.** There is no separate health stat. Corner bandaging restores
## Strength. Do not add HP.
##
## Caps are hard: "Training cannot exceed it; only breeding raises it." A capped
## stat shows a star in the UI (`POW 500*`). Permanent-boost foods are wasted on
## a starred stat. Honoured via GameRules.hard_stat_caps.

enum Stat { POWER, SPEED, KNOWLEDGE, STRENGTH, STAMINA }

## Dossier §8 [U]: the stat card shows a sex marker — `NAME: MAX(ML)` — but no
## source discusses how it interacts with breeding (§14.16 [X]).
enum Sex { MALE, FEMALE }

const STATS: Array[Stat] = [Stat.POWER, Stat.SPEED, Stat.KNOWLEDGE, Stat.STRENGTH, Stat.STAMINA]
const STAT_KEYS: PackedStringArray = ["power", "speed", "knowledge", "strength", "stamina"]
const STAT_LABELS: PackedStringArray = ["POW", "SPD", "KNOW", "STRG", "STM"]

## Stat-card sex marker, indexed by Sex. Dossier §8 [U] confirms the card reads
## `NAME: MAX(ML)`.
## DIVERGENCE: only the male marker `(ML)` is attested in a screenshot; the
## female abbreviation is [X]. "FM" is chosen as the obvious two-letter partner
## to "ML" in the same style. §14.16 also flags that whether sex affects
## breeding at all is unknown — this is a display marker and nothing more.
const SEX_MARKERS: PackedStringArray = ["ML", "FM"]

const FRIENDSHIP_MAX := 100
## Below this the monkey refuses to train and may bite (dossier §5 [C]).
## DIVERGENCE: the numeric threshold is [X]; 20 is chosen so the documented
## "fastest path: two bananas" befriending actually lands in one morning.
const FRIENDSHIP_TRAIN_MIN := 20
const DISCIPLINE_MAX := 100
## Below this the monkey may ignore an in-fight strategy (dossier §6 [C]).
## DIVERGENCE: the original's exact obedience curve is [X]. See core/care.gd.
const FRIENDSHIP_OBEDIENT := 70

## DIVERGENCE: the original's fullness scale is [X]. 30 is chosen because the
## documented food Hunger values run 0..25 (Steak 25, Bacon 15, Banana 3), so a
## 30-point belly makes Steak a near-full meal and a Banana a snack — which
## reproduces the guides' rule of "feed only when it cannot move".
const FULLNESS_MAX := 30
## At or below this the monkey is immobilised by hunger (dossier §5 [C]).
const FULLNESS_STARVING := 3
## At or above this the monkey is immobilised until it digests (dossier §5 [C],
## GameRules.overfeeding_paralyses — FAITHFUL, do not soften).
const FULLNESS_STUFFED := 27
## Fullness burned off per half-day slot. DIVERGENCE: digestion rate is [X].
const DIGEST_PER_SLOT := 6

@export var monkey_name: String = ""
@export var species_type: Species.Type = Species.Type.SUNBURST
@export var sex: Sex = Sex.MALE
## 1 for the starter, +1 per breeding step.
@export var generation: int = 1

## Stat -> int. Always clamped to `caps` when hard_stat_caps is on.
@export var stats: Dictionary = {}
## Stat -> int. Raised only by breeding.
@export var caps: Dictionary = {}

@export var friendship: int = 0
## しつけ — how well-drilled the monkey is, 0..DISCIPLINE_MAX.
##
## The JP back cover promises 「しつけ次第で、いろんな性格のサルが育つぞ！」 —
## "depending on how you discipline it, monkeys of all sorts of personalities
## will grow" — and the guides document praise and scold as real inputs
## (dossier §4 [C]). Nothing records what discipline actually DRIVES, so:
##
## DIVERGENCE: [X]. Here it is the second axis of training alongside friendship.
## Friendship decides whether the monkey will work with you at all; discipline
## decides how quickly it stops watching and joins in. A beloved but scatty
## monkey needs a long demonstration every time; a well-drilled one starts
## almost at once, which is the dossier's "eventually requiring no prompting".
@export var discipline: int = 0
@export var fullness: int = 0

## Live pools used inside a match and by hunger. `current_strength` is the
## health bar; its ceiling is the STRENGTH stat. Same shape for stamina.
@export var current_strength: int = 0
@export var current_stamina: int = 0

## Remaining half-day slots of forced immobility (overfeeding / exhaustion).
@export var paralysed_slots: int = 0

## Set when the monkey has been bred from and moved to the roster
## (GameRules.breeding_destroys_parent = false).
@export var retired: bool = false

@export var wins: int = 0
@export var losses: int = 0

## Training.Activity -> best rep count. Dossier §4 [C]: 自己最高回数, the
## personal record the Japanese playerbase describes as the core appeal.
@export var personal_bests: Dictionary = {}

## Dossier §6 [C]: the monkey is worn out the day after a match.
@export var days_since_match: int = 99


static func create(
		p_name: String,
		p_species: Species.Type,
		p_caps: Dictionary,
		p_generation: int = 1,
		p_sex: Sex = Sex.MALE) -> Monkey:
	var m := Monkey.new()
	m.monkey_name = p_name
	m.species_type = p_species
	m.generation = p_generation
	m.sex = p_sex
	m.caps = p_caps.duplicate()
	for stat in STATS:
		m.stats[stat] = 0
		if not m.caps.has(stat):
			m.caps[stat] = 0
	m.current_strength = 0
	m.current_stamina = 0
	return m


func get_stat(stat: Stat) -> int:
	return int(stats.get(stat, 0))


func get_cap(stat: Stat) -> int:
	return int(caps.get(stat, 0))


func set_stat(stat: Stat, value: int) -> void:
	stats[stat] = clampi(value, 0, get_cap(stat))


func set_cap(stat: Stat, value: int) -> void:
	caps[stat] = maxi(0, value)
	stats[stat] = mini(get_stat(stat), get_cap(stat))


## Add to a stat, clamping at the cap. Returns the amount ACTUALLY applied,
## which is what the UI should report ("+3, capped").
func add_stat(stat: Stat, amount: int) -> int:
	var before := get_stat(stat)
	set_stat(stat, before + amount)
	return get_stat(stat) - before


func is_capped(stat: Stat) -> bool:
	return get_cap(stat) > 0 and get_stat(stat) >= get_cap(stat)


func all_capped() -> bool:
	for stat in STATS:
		if not is_capped(stat):
			return false
	return true


## The health bar's ceiling. Dossier §3 [C]: Strength IS the health bar.
func max_strength() -> int:
	return get_stat(Stat.STRENGTH)


func max_stamina() -> int:
	return get_stat(Stat.STAMINA)


## Refill the live pools — used when starting a match and after a big meal.
func restore_pools() -> void:
	current_strength = max_strength()
	current_stamina = max_stamina()


func species() -> Species:
	return SpeciesDb.get_species(species_type)


func is_befriended() -> bool:
	return friendship >= FRIENDSHIP_TRAIN_MIN


func is_starving() -> bool:
	return fullness <= FULLNESS_STARVING


func is_stuffed() -> bool:
	return fullness >= FULLNESS_STUFFED


## Stat card line, e.g. "POW  74*" — the star marks a capped stat (dossier §3).
func stat_line(stat: Stat) -> String:
	return "%-4s %d%s" % [STAT_LABELS[stat], get_stat(stat), "*" if is_capped(stat) else ""]


## "ML" / "FM" — the marker the original's stat card prints after the name.
func sex_marker() -> String:
	return SEX_MARKERS[clampi(int(sex), 0, SEX_MARKERS.size() - 1)]


## The stat card's name row: `NAME: FREDDY(ML)` (dossier §8 [U], §10 [C]).
func name_line() -> String:
	return "NAME: %s(%s)" % [monkey_name.to_upper(), sex_marker()]


static func stat_key(stat: Stat) -> String:
	return STAT_KEYS[stat]


static func stat_from_key(key: String) -> Stat:
	var index := STAT_KEYS.find(key)
	return STATS[index] if index >= 0 else Stat.POWER


static func stat_label(stat: Stat) -> String:
	return STAT_LABELS[stat]


# --- serialisation ---------------------------------------------------------
#
# Every enum is written as an int, and every enum-keyed Dictionary has int keys,
# per the save contract in docs/ARCHITECTURE.md §15. JSON turns Dictionary keys
# into Strings on the way back, so `from_dict` reads every key through `int()`
# and tolerates both shapes.

func to_dict() -> Dictionary:
	return {
		"monkey_name": monkey_name,
		"species_type": int(species_type),
		"sex": int(sex),
		"generation": generation,
		"stats": _int_keyed(stats),
		"caps": _int_keyed(caps),
		"friendship": friendship,
		"discipline": discipline,
		"fullness": fullness,
		"current_strength": current_strength,
		"current_stamina": current_stamina,
		"paralysed_slots": paralysed_slots,
		"retired": retired,
		"wins": wins,
		"losses": losses,
		"personal_bests": _int_keyed(personal_bests),
		"days_since_match": days_since_match,
	}


## Rebuild a monkey from `to_dict` output. Missing keys fall back to the
## defaults a freshly created monkey would have, so a save written by an older
## build still loads.
static func from_dict(d: Dictionary) -> Monkey:
	var m := Monkey.new()
	m.monkey_name = String(d.get("monkey_name", ""))
	m.species_type = int(d.get("species_type", Species.Type.SUNBURST)) as Species.Type
	m.sex = int(d.get("sex", Sex.MALE)) as Sex
	m.generation = maxi(1, int(d.get("generation", 1)))

	# Caps first: `set_stat` clamps against them, so a corrupt save can never
	# restore a monkey above its own ceiling.
	var raw_caps := _int_keyed(d.get("caps", {}))
	var raw_stats := _int_keyed(d.get("stats", {}))
	for stat in STATS:
		m.set_cap(stat, int(raw_caps.get(stat, 0)))
	for stat in STATS:
		m.set_stat(stat, int(raw_stats.get(stat, 0)))

	m.friendship = clampi(int(d.get("friendship", 0)), 0, FRIENDSHIP_MAX)
	# Defaults to 0 for saves written before discipline existed, which is simply
	# an undrilled monkey — no migration needed.
	m.discipline = clampi(int(d.get("discipline", 0)), 0, DISCIPLINE_MAX)
	m.fullness = clampi(int(d.get("fullness", 0)), 0, FULLNESS_MAX)
	m.current_strength = clampi(int(d.get("current_strength", 0)), 0, m.max_strength())
	m.current_stamina = clampi(int(d.get("current_stamina", 0)), 0, m.max_stamina())
	m.paralysed_slots = maxi(0, int(d.get("paralysed_slots", 0)))
	m.retired = bool(d.get("retired", false))
	m.wins = maxi(0, int(d.get("wins", 0)))
	m.losses = maxi(0, int(d.get("losses", 0)))
	m.personal_bests = _int_keyed(d.get("personal_bests", {}))
	m.days_since_match = maxi(0, int(d.get("days_since_match", 99)))
	return m


## Copy a Dictionary with every key coerced to int and every value to int.
## Handles the String keys JSON hands back ("0" -> 0).
static func _int_keyed(source: Variant) -> Dictionary:
	var out := {}
	if source is Dictionary:
		for key in (source as Dictionary):
			out[int(key)] = int((source as Dictionary)[key])
	return out
