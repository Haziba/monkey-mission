class_name Ladder
extends RefCounted

## The JSB ladder. Dossier §7.
##
## [C] rules that must hold:
##  * Bill rings the doorbell and offers THREE candidates, at least one ranked
##    ABOVE the player.
##  * Stronger opponent = bigger purse.
##  * Beat a HIGHER-ranked monkey -> +1 rank.
##  * Lose to a LOWER-ranked monkey -> -1 rank.
##  * Beating a lower-ranked monkey pays but does NOT promote — the guides do it
##    purely for cash.
##  * One flat numbered ladder. NO weight classes, belts or divisions. This is
##    positive evidence, not a gap — do not add them.
##  * Rank 1 is the top.
##
## [X] The real rank count is unknown (§7, §14.2) — 14 is demonstrated, two blogs
## say "15 tiers", a Japanese player starts around 11. **What JSB stands for is
## also [X] — do not invent an expansion.**
##
## SCOPE: the brief cuts this to a SHORT ladder, rank 5 down to rank 1.

const TOP_RANK := 1
const BOTTOM_RANK := 5
## Dossier §7 [C]: three candidates, at least one above you.
const OFFER_COUNT := 3

## DIVERGENCE: match cadence is a documented contradiction (§2, §14) — Wikipedia
## and HG101 say every 3 days, the walkthrough's own day log shows a 4-day cycle
## (offer day, fight day, three free days), and the same guide's prose says 5.
## The dossier's own best reading is "three free days plus a match day", so 4.
const MATCH_CYCLE_DAYS := 4

## DIVERGENCE: the day of the FIRST offer is [X]. The tofu_bud walkthrough logs
## fights on days 6, 10, 14 and 18, and Bill offers the card the day before, so
## offers land on 5, 9, 13, 17. Day 6 doubling as the pro-qualification test
## (§7 phase 1 [C], "within 5 days") is consistent with that reading.
const FIRST_OFFER_DAY := 5

## DIVERGENCE: opponent stat scaling per rank is [X] — no source gives any
## ladder opponent's numbers (§14.5, §14.13). The curve below is chosen against
## the one hard datum we do have: Freddy's caps average 134 (§3 [U]), and the
## RetroAchievements set author states flatly that "your starter will never be
## rank 1" (§8 [C]). So a maxed generation-1 monkey must beat rank 5, be an even
## fight at rank 4, and lose badly from rank 3 up — which is exactly the
## sawtooth wall the breeding system exists to break (§7 phase 3 [C]).
const RANK_STAT_BASE := 90     ## target average stat at BOTTOM_RANK
const RANK_STAT_STEP := 55     ## added per rank climbed toward TOP_RANK

## DIVERGENCE: how closely opponents are matched to the player is [X]. A quarter
## weight keeps an under-trained player from being flattened at the bottom of
## the ladder without ever softening the top of it.
const PLAYER_MATCH_WEIGHT := 0.25

## DIVERGENCE: opponent stat spread is [X]. The dossier's breeding menu does
## confirm the game thinks in archetypes — `AVG / POWER / SPEED / SMART /
## STRONG / STM TYPE` (§8 [C]) — so each opponent either favours one stat or is
## an all-rounder, rather than every ladder monkey being a flat block.
const SPECIALIST_BONUS := 1.30
const SPECIALIST_MALUS := 0.92
const STAT_JITTER := 0.10

## DIVERGENCE: no source names ordinary ladder opponents (§14.5). These are the
## game's own documented default monkey names (§8 [C]: "Freddy, Agatha, Lemon,
## Betty, Dragon, Jimbo, Tomato, Cookie, Pizza") minus Freddy, whose name is
## fixed to the player's starter.
const OPPONENT_NAMES: PackedStringArray = [
	"AGATHA", "LEMON", "BETTY", "DRAGON", "JIMBO", "TOMATO", "COOKIE", "PIZZA",
]

## DIVERGENCE: no source names any ordinary trainer either (§14.5). Only Bill,
## Fred, Cain and "the Professor" are documented, and all four are story
## characters rather than ladder trainers. These are deliberately plain
## placeholders and are NOT presented as original game terms.
const TRAINER_NAMES: PackedStringArray = [
	"MR. OKA", "MS. HARA", "MR. TANI", "MS. KUDO", "MR. SAWA", "MS. NOMI",
]


## One offered opponent.
class Opponent extends RefCounted:
	var monkey: Monkey = null
	var rank: int = BOTTOM_RANK
	## [X] — no source names ordinary ladder opponents or their trainers
	## (§14.5). Generated names need a DIVERGENCE comment.
	var trainer_name: String = ""
	## What a win pays. Loss pays less; see Economy.purse_for.
	var purse: int = 0
	## True when this opponent outranks the player (the promotion candidate).
	var is_above_player: bool = false


signal rank_changed(old_rank: int, new_rank: int)
signal champion_reached()
signal opponents_offered(offers: Array)

## The player's current JSB rank. Starts at the bottom of the short ladder.
var rank: int = BOTTOM_RANK

var _rules: GameRules
var _rng: MpRng


func _init(rules: GameRules, rng: MpRng) -> void:
	_rules = rules
	_rng = rng


# --- cadence ---------------------------------------------------------------
# Additive helpers, NOT part of the frozen contract: the 4-day cycle expressed
# as predicates so GameState and DayCycle do not each re-derive it and drift.

## True on a day Bill rings the doorbell with three candidates.
static func is_offer_day(day: int) -> bool:
	return day >= FIRST_OFFER_DAY and (day - FIRST_OFFER_DAY) % MATCH_CYCLE_DAYS == 0


## True on a day a booked match is fought — always the day after an offer.
static func is_match_day(day: int) -> bool:
	return is_offer_day(day - 1)


## The next offer day strictly after `day`.
static func next_offer_day(day: int) -> int:
	if day < FIRST_OFFER_DAY:
		return FIRST_OFFER_DAY
	var elapsed := day - FIRST_OFFER_DAY
	return FIRST_OFFER_DAY + (elapsed / MATCH_CYCLE_DAYS + 1) * MATCH_CYCLE_DAYS


# --- offers ----------------------------------------------------------------

## Bill's offer: OFFER_COUNT candidates with at least one ranked above the
## player. Deterministic for a given (day, seed) so a re-open shows the same
## three.
func offer_opponents(player: Monkey, day: int) -> Array[Opponent]:
	# A private stream derived from (run seed, day) rather than the shared one:
	# re-opening Bill's card must not consume randomness and must not change
	# what is on offer.
	var stream := MpRng.new(_offer_seed(day))

	var above: Array[int] = []
	for r in range(TOP_RANK, rank):
		above.append(r)
	var at_or_below: Array[int] = []
	for r in range(maxi(rank, TOP_RANK), BOTTOM_RANK + 1):
		at_or_below.append(r)

	var chosen: Array[int] = []
	# Dossier §7 [C]: at least one candidate must outrank the player. Only a
	# champion has nobody above them.
	if not above.is_empty():
		chosen.append(_take(above, stream))

	var pool: Array[int] = []
	pool.append_array(above)
	pool.append_array(at_or_below)
	while chosen.size() < OFFER_COUNT and not pool.is_empty():
		chosen.append(_take(pool, stream))
	# Only reachable if the ladder is ever shortened below OFFER_COUNT ranks.
	while chosen.size() < OFFER_COUNT:
		chosen.append(clampi(rank, TOP_RANK, BOTTOM_RANK))

	# Strongest first — rank 1 is the top, so ascending rank number.
	chosen.sort()

	var used_names: Array[String] = []
	var used_trainers: Array[String] = []
	var offers: Array[Opponent] = []
	for r in chosen:
		offers.append(_build_opponent(r, player, stream, used_names, used_trainers))
	opponents_offered.emit(offers)
	return offers


## Build a single opponent scaled to `rank`, roughly matched to the player so
## the ladder is climbable but the generational wall still exists (§7 phase 3).
func generate_opponent(p_rank: int, player: Monkey) -> Opponent:
	var used_names: Array[String] = []
	var used_trainers: Array[String] = []
	return _build_opponent(p_rank, player, _rng, used_names, used_trainers)


# --- results ---------------------------------------------------------------

## Apply the ladder movement rules above. Returns the rank delta actually
## applied (+1 / 0 / -1) and emits rank_changed when it moved.
##
## SIGN CONVENTION, read this before using the return value: the delta is
## arithmetic on the rank NUMBER, so `new_rank == old_rank + delta`. Rank 1 is
## the top, therefore a PROMOTION returns -1 and a DEMOTION returns +1. The
## dossier's prose "+1 rank" means one rung up the ladder, not +1 on the
## counter. UI that wants to print "RANK UP" should read the rank_changed
## signal, which is unambiguous.
func apply_result(outcome: MatchResolver.Outcome, opponent_rank: int) -> int:
	# A draw settles nothing: you neither beat a higher rank nor lost to a
	# lower one.
	if outcome == MatchResolver.Outcome.DRAW:
		return 0
	var won := (outcome == MatchResolver.Outcome.WIN_KO
			or outcome == MatchResolver.Outcome.WIN_DECISION)
	var delta := rank_delta_for(won, rank, opponent_rank)
	if delta == 0:
		return 0
	var old_rank := rank
	rank = clampi(rank + delta, TOP_RANK, BOTTOM_RANK)
	var applied := rank - old_rank
	if applied != 0:
		rank_changed.emit(old_rank, rank)
		if is_champion():
			champion_reached.emit()
	return applied


## Rank movement without mutating anything — used to preview and by tests.
## Same sign convention as apply_result: negative means promoted.
static func rank_delta_for(won: bool, player_rank: int, opponent_rank: int) -> int:
	var here := clampi(player_rank, TOP_RANK, BOTTOM_RANK)
	var raw := 0
	if won:
		# Beat a HIGHER-ranked monkey (lower number) -> up one rung.
		# Beating a lower or equal rank pays but does not promote.
		if opponent_rank < here:
			raw = -1
	else:
		# Lose to a LOWER-ranked monkey (higher number) -> down one rung.
		# Losing to someone above you is no disgrace and costs nothing.
		if opponent_rank > here:
			raw = 1
	return clampi(here + raw, TOP_RANK, BOTTOM_RANK) - here


## Send the player back to the bottom rung. Dossier §2 [C], the core loop:
##
##     BREED -> parent monkey is destroyed, baby inherits higher caps
##       -> re-befriend baby with food
##       -> 5 days -> pro qualification test
##       -> **re-climb the ladder from the bottom**
##
## and §7 phase 3 [C]: "each new generation starts weak and re-climbs ranks it
## has already beaten". Called once, from GameState.breed_with(). Emits
## rank_changed so the HUD follows.
func reset_to_bottom() -> int:
	var old_rank := rank
	if old_rank == BOTTOM_RANK:
		return 0
	rank = BOTTOM_RANK
	rank_changed.emit(old_rank, rank)
	return rank - old_rank


func is_champion() -> bool:
	return rank <= TOP_RANK


func to_dict() -> Dictionary:
	return {"rank": rank}


func apply_dict(d: Dictionary) -> void:
	rank = clampi(int(d.get("rank", BOTTOM_RANK)), TOP_RANK, BOTTOM_RANK)


# --- internals -------------------------------------------------------------

func _offer_seed(day: int) -> int:
	var base := 0
	if _rng != null:
		base = _rng.seed_value()
	# `| 1` keeps it non-zero, which MpRng reads as "seed from the clock".
	return int(hash("%d/offer/%d" % [base, day])) | 1


func _take(from: Array[int], stream: MpRng) -> int:
	var index := stream.randi_range(0, from.size() - 1)
	var value := from[index]
	from.remove_at(index)
	return value


func _build_opponent(
		p_rank: int,
		player: Monkey,
		stream: MpRng,
		used_names: Array[String],
		used_trainers: Array[String]) -> Opponent:
	var op := Opponent.new()
	op.rank = clampi(p_rank, TOP_RANK, BOTTOM_RANK)
	op.is_above_player = op.rank < rank

	var target := float(RANK_STAT_BASE + (BOTTOM_RANK - op.rank) * RANK_STAT_STEP)
	# -1 means an all-rounder; otherwise the index of the favoured stat.
	var specialism := stream.randi_range(-1, Monkey.STATS.size() - 1)

	var caps := {}
	for stat in Monkey.STATS:
		var mid := target
		if player != null:
			mid = target * (1.0 - PLAYER_MATCH_WEIGHT) \
					+ float(player.get_stat(stat)) * PLAYER_MATCH_WEIGHT
		if specialism >= 0:
			mid *= SPECIALIST_BONUS if stat == specialism else SPECIALIST_MALUS
		mid = maxf(mid, 1.0)
		var value := stream.spread(mid, mid * STAT_JITTER, mid * 0.6, mid * 1.4)
		caps[stat] = maxi(1, int(roundf(value)))

	var monkey_name := _pick_unique(OPPONENT_NAMES, stream, used_names)
	used_names.append(monkey_name)

	var all_species := SpeciesDb.all()
	var species_type: Species.Type = all_species[
			stream.randi_range(0, all_species.size() - 1)].type
	var sex: Monkey.Sex = Monkey.Sex.MALE
	if stream.chance(0.5):
		sex = Monkey.Sex.FEMALE

	var m := Monkey.create(monkey_name, species_type, caps, _generation_for(op.rank), sex)
	# A ladder opponent arrives fully trained: its stats sit ON its caps.
	for stat in Monkey.STATS:
		m.set_stat(stat, m.get_cap(stat))
	m.friendship = Monkey.FRIENDSHIP_MAX
	m.fullness = int(Monkey.FULLNESS_MAX / 2)
	m.restore_pools()
	op.monkey = m

	op.trainer_name = _pick_unique(TRAINER_NAMES, stream, used_trainers)
	used_trainers.append(op.trainer_name)
	# Dossier §7 [C]: stronger opponent = bigger purse. The figures themselves
	# are [X] (§14.13) and belong to Economy, which owns the money.
	op.purse = Economy.purse_for(op.rank, rank, true)
	return op


## DIVERGENCE: whether ladder opponents are bred monkeys at all is [X]. Tying
## generation to rank makes the sawtooth legible — the rank you cannot beat is
## visibly a later generation than yours (§7 phase 3 [C]).
func _generation_for(p_rank: int) -> int:
	return 1 + int((BOTTOM_RANK - clampi(p_rank, TOP_RANK, BOTTOM_RANK)) / 2)


## Pick from `pool`, walking forward from a random start until an unused entry
## turns up — three fighters on one card must not share a name or a trainer.
func _pick_unique(pool: PackedStringArray, stream: MpRng, used: Array[String]) -> String:
	var start := stream.randi_range(0, pool.size() - 1)
	for offset in pool.size():
		var candidate := String(pool[(start + offset) % pool.size()])
		if not (candidate in used):
			return candidate
	return String(pool[start])
