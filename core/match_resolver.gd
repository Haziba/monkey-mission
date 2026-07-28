class_name MatchResolver
extends RefCounted

## A three-round match. Dossier §6 [C] throughout.
##
## "Real-time animation, turn-based input. The fight resolves itself; the
## player's entire agency is a strategy choice and one corner action per break."
##
##  * 3 rounds, 2 intermissions.
##  * No direct control during a round (this build adds a small tap effect —
##    GameRules.fight_interactivity = TAP_ENCOURAGE — and nothing more).
##  * Win by KO (opponent's STRENGTH depleted, because Strength IS the health
##    bar) or by judges' decision weighing downs, remaining Strength and
##    remaining Stamina.
##  * A monkey with insufficient friendship may ignore your instructions —
##    rolled once per round via Care.obeys().
##
## "Stamina attrition is the game's real combat system." DEFEND drains the
## attacking opponent's Stamina badly; the intended line is defend round 1, then
## Breathe-and-relax + attack in rounds 2 and 3.
##
## ARCHITECTURE: this class is a pure simulation stepped by `advance(delta)`.
## The UI drives the clock and plays back MatchEvents; it must never compute
## damage itself. `simulate_round()` runs a whole round at once for tests and
## for a fast-forward button.

const ROUNDS := 3

## DIVERGENCE: round length is [X]. The fight HUD in the dossier (§10) shows
## `1R : 27`, a counting-down seconds clock, but no source gives the start
## value. 60s is chosen as the boxing convention and because it leaves room for
## the documented "final 10 seconds of round 3" special-punch window.
const ROUND_SECONDS := 60.0
## Special punches fire ONLY in the last 10 seconds of round 3 (dossier §6 [C]).
const SPECIAL_WINDOW_SECONDS := 10.0

## Set before round 1 and re-settable at each intermission (dossier §6 [C]).
## The English labels are the original's, mistranslation included.
enum Strategy {
	ATTACK,    ## "HIT IT! HIT IT!" — heavy Stamina burn, leaves you open, scales with Power
	DEFEND,    ## "BEAT IT UP!"     — THIS MEANS DEFEND. Cheap, and drains the attacker's Stamina badly
	EVADE,     ## "KEEP MOVING"     — circle and jab, scales with Speed, not fully reliable
	BALANCED,  ## "KEEP YOUR BALANCE" — mixes all three; picks better with high Knowledge
}

## One only, irreversible — unlike Strategy you cannot change your mind.
enum CornerAction {
	BANDAGE,   ## restores Strength
	BREATHE,   ## "Breathe and relax" — restores Stamina
	WATER,     ## "Wipe it with water" — restores some of both
	ITEM,      ## e.g. Monk Max, a temporary Power booster
}

enum Outcome { WIN_KO, WIN_DECISION, LOSS_KO, LOSS_DECISION, DRAW }

enum EventKind {
	ROUND_START,
	PUNCH_LANDED,
	PUNCH_BLOCKED,
	PUNCH_DODGED,
	STAMINA_DRAIN,
	KNOCKDOWN,
	GET_UP,
	DISOBEYED,       ## the monkey ignored the strategy (friendship too low)
	TAP_ENCOURAGE,   ## the player tapped; small effect
	SPECIAL_PUNCH,
	ROUND_END,
	KO,
	DECISION,
}

const STRATEGY_LABELS: PackedStringArray = [
	"HIT IT! HIT IT!", "BEAT IT UP!", "KEEP MOVING", "KEEP YOUR BALANCE",
]
const CORNER_LABELS: PackedStringArray = [
	"BANDAGE", "BREATHE AND RELAX", "WIPE IT WITH WATER", "USE AN ITEM",
]

# --- tuning ------------------------------------------------------------------
#
# Dossier §6 [X]: "round length, damage/stamina coefficients, knockdown
# thresholds, and the judges' relative weights are all undocumented." Every
# number below is therefore a DIVERGENCE. They are tuned to satisfy the one
# thing the dossier IS explicit about (§6 [C]): "Stamina attrition is the game's
# real combat system", and the intended line — defend round 1 to burn the
# opponent's Stamina, then Breathe-and-relax + attack in rounds 2 and 3 — must
# actually beat straight aggression against an even opponent. That relationship
# is pinned by test_match_resolver.gd.
#
# Measured over 400 seeded matches between two monkeys on Freddy's observed
# starter tuple (Pow 145 / Spd 119 / Know 116 / Str 145 / Stm 145), each line
# taking BREATHE at both corners:
#
#   KEEP YOUR BALANCE x3                 0.69     (reads the fight; needs Knowledge)
#   DEFEND -> ATTACK -> ATTACK           0.59     <- the dossier's intended line
#   DEFEND x3 ("turtle")                 0.43
#   HIT IT! HIT IT! x3                   0.21     <- straight aggression
#   KEEP MOVING x3                       0.21
#
# Retune anything below and re-read those numbers before you commit.

## DIVERGENCE: the original resolves in real-time animation and no source gives
## a punch cadence. The round is diced into fixed exchanges so the simulation is
## reproducible under any `advance(delta)` step size; 3s gives 20 exchanges in a
## 60s round, which is a plausible boxing rate and enough samples for the
## attrition curve to read on the HUD gauges.
const EXCHANGE_SECONDS := 3.0

## DIVERGENCE: stamina economy is [X]. Costs are fractions of the fighter's own
## STAMINA stat, spent per exchange, so the model scales with generation.
## ATTACK is deliberately ~9x DEFEND: "heavy Stamina burn" vs "cheap on Stamina".
const UPKEEP_ATTACK := 0.028
const UPKEEP_DEFEND := 0.003
const UPKEEP_EVADE := 0.013
## Passive breathing. DEFEND's upkeep sits below it, so a blocking monkey slowly
## recovers — that is what makes round 1 DEFEND the setup for rounds 2 and 3.
const STAMINA_REGEN := 0.006

## DIVERGENCE: how often each stance throws a punch in an exchange. [X].
const THROW_ATTACK := 0.95
const THROW_DEFEND := 0.15   ## the occasional counter — DEFEND is not fully passive
const THROW_EVADE := 0.55    ## "circle and jab"

## DIVERGENCE: damage coefficients are [X]. Damage scales with POWER for ATTACK
## and with SPEED for EVADE (dossier §6 [C]). 0.026 x Power against a Strength
## bar of comparable size gives a fight that usually goes the distance but can
## end in a KO — matching "win by KO or by judge's decision" being both live.
const DAMAGE_ATTACK := 0.026   ## x POWER
const DAMAGE_EVADE := 0.017    ## x SPEED
const DAMAGE_COUNTER := 0.013  ## x POWER, the DEFEND counter-punch
## A punch that gets through a blocking stance still lands soft, but not THAT
## soft — at a lower value, blocking for three rounds stops being a trade-off
## and starts being an answer. [X].
const DEFEND_ABSORB := 0.85
const DAMAGE_VARIANCE := 0.15

## DIVERGENCE: block / dodge rates are [X]. Both scale with the DEFENDER's
## stamina effectiveness, which is the load-bearing detail: a knackered blocker
## stops blocking, so "always defend" is not a degenerate answer.
const BLOCK_ATTACK := 0.05     ## attacking "leaves you open"
const BLOCK_DEFEND := 0.55
const BLOCK_EVADE := 0.10
const BLOCK_MAX := 0.85
const DODGE_ATTACK := 0.05
const DODGE_DEFEND := 0.12
const DODGE_EVADE := 0.34      ## "not fully reliable — you still get hit sometimes"
const DODGE_MAX := 0.65
const DODGE_COST := 0.004      ## slipping a punch costs the dodger a little stamina

## THE CORE OF THE SYSTEM (dossier §6 [C]: DEFEND "drains the attacking
## opponent's Stamina badly"). Each blocked punch costs the ATTACKER this
## fraction of its own max stamina, scaled by the blocker's effectiveness.
## DIVERGENCE: the magnitude is [X]; 0.026 makes a full round of attacking into
## a fresh blocker cost roughly two thirds of the attacker's stamina, which is
## what turns round 1 into a trap for a monkey told to swing.
const BLOCK_DRAIN := 0.026

## DIVERGENCE: fatigue curve is [X]. A fighter at zero stamina still throws, but
## at a fifth of its effect, and takes 80% more damage. This is the multiplier
## that makes an emptied Stamina bar decisive rather than cosmetic.
const EFFECT_FLOOR := 0.20
const VULNERABILITY_AT_ZERO := 0.8

## DIVERGENCE: knockdown thresholds are [X]. Chance per landed punch, rising as
## the target's Strength and Stamina fall — nobody gets dropped at full health.
const KNOCKDOWN_BASE := 0.10
## DIVERGENCE: no source mentions a standing count. Three downs ends it, the
## boxing convention, so the `downs` the judges weigh also has a hard edge.
const KNOCKDOWN_LIMIT := 3
const DOWN_SECONDS := 6.0
const DOWN_STAMINA_COST := 0.07

## DIVERGENCE: judges' relative weights are [X]. The dossier only says the
## decision "weighs number of downs, remaining Strength and remaining Stamina"
## (§6 [C]). Strength outweighs Stamina 8:1 so that a fighter who blocked for
## three rounds does not out-point one who actually did damage — Stamina is the
## tiebreaker the dossier says it is, not the scorecard. A down is worth about a
## third of a full Strength bar.
const JUDGE_WEIGHT_DOWN := 40.0
const JUDGE_WEIGHT_STRENGTH := 120.0
const JUDGE_WEIGHT_STAMINA := 15.0

## DIVERGENCE: corner restore amounts are [X] — the dossier names the four
## actions and what they restore but no quantity. Fractions of the relevant max.
const CORNER_BANDAGE_STRENGTH := 0.25
const CORNER_BREATHE_STAMINA := 0.28
const CORNER_WATER_BOTH := 0.18
## "Monk Max, a temporary Power booster (HG101 calls it doping)" — §6 [C], no
## number given. DIVERGENCE: +25% damage for the rest of the match.
const CORNER_ITEM_POWER_BONUS := 0.25

## DIVERGENCE: BALANCED "picks better with high Knowledge" (§6 [C]) but no curve
## is documented. Soft saturating curve: a starter (Know ~116) reads the fight
## right about two thirds of the time, a late-generation monkey about four
## fifths, and a brainless one falls back to guessing.
const KNOWLEDGE_FLOOR := 0.40
const KNOWLEDGE_SPAN := 0.55
const KNOWLEDGE_REFERENCE := 150.0

## This build's addition, not the original's (§6 [C] says the original is pure
## spectate). Rate-limited so mashing is not a win button: one tap counts per
## TAP_COOLDOWN seconds of round clock, at most TAP_MAX_PER_ROUND per round, for
## at most a +6% effectiveness swing. Banked taps also shorten a get-up, which
## is where the single-source [U] claim ("mash A to help a knocked-down monkey
## back to its feet") is spent.
const TAP_COOLDOWN := 1.5
const TAP_MAX_PER_ROUND := 8
const TAP_BONUS_STEP := 0.01
const TAP_BONUS_MAX := 0.06
const TAP_GETUP_RELIEF := 0.5
const TAP_GETUP_RELIEF_MAX := 3.0


## Live state for one side of the ring.
class Fighter extends RefCounted:
	var monkey: Monkey = null
	var is_player: bool = false
	## The health bar. Dossier §3: Strength IS health.
	var strength: int = 0
	var stamina: int = 0
	var downs: int = 0
	var strategy: Strategy = Strategy.BALANCED
	## False when a disobedience roll failed this round; the monkey then picks
	## its own behaviour instead of the player's.
	var obeying: bool = true
	## Strategy actually being executed this round (== strategy when obeying).
	var acting_strategy: Strategy = Strategy.BALANCED
	## Temporary Power multiplier from an in-fight item (Monk Max doping).
	var power_bonus: float = 0.0


## One log line. The HUD's commentary box replaces the gauge strip to show it.
class MatchEvent extends RefCounted:
	var kind: EventKind = EventKind.ROUND_START
	var round_index: int = 1
	## Seconds remaining on the round clock when it fired (HUD shows `1R : 27`).
	var time_remaining: float = 0.0
	var by_player: bool = true
	var amount: int = 0
	var text: String = ""


class RoundResult extends RefCounted:
	var round_index: int = 1
	var events: Array[MatchEvent] = []
	var player_strength: int = 0
	var player_stamina: int = 0
	var opponent_strength: int = 0
	var opponent_stamina: int = 0
	var player_downs: int = 0
	var opponent_downs: int = 0
	var knockout: bool = false
	var player_won_ko: bool = false
	var player_obeyed: bool = true


class MatchResult extends RefCounted:
	var outcome: Outcome = Outcome.DRAW
	var rounds: Array[RoundResult] = []
	var purse: int = 0
	## +1 / 0 / -1, per the ladder rules in dossier §7.
	var rank_delta: int = 0
	var opponent_rank: int = 0
	var player_won: bool = false
	## Judges' scores when the match went to a decision.
	var player_score: int = 0
	var opponent_score: int = 0
	var summary: String = ""


signal round_started(round_index: int)
signal event_logged(event: MatchEvent)
signal round_finished(result: RoundResult)
signal intermission_started(round_index: int)
signal match_finished(result: MatchResult)

var player: Fighter = null
var opponent: Fighter = null
var round_index: int = 1
var time_remaining: float = ROUND_SECONDS
## The id passed to the last CornerAction.ITEM, for the UI's message box only —
## the item economy is out of scope for the vertical slice.
var last_item_id: String = ""

var _rules: GameRules
var _rng: MpRng
var _care: Care

var _opponent_rank: int = 0
var _round_active: bool = false
var _finished: bool = false
var _ko: bool = false
var _player_won_ko: bool = false
var _corner_used: bool = false
var _exchange_pool: float = 0.0
var _rounds: Array[RoundResult] = []
var _round_events: Array[MatchEvent] = []
var _new_events: Array[MatchEvent] = []
var _result: MatchResult = null

var _tap_credits: int = 0
var _tap_last_at: float = 0.0
## What the player's monkey actually did last round; -1 before round 1. The
## opposing corner reads it between rounds.
var _player_last_strategy: int = -1


func _init(rules: GameRules, rng: MpRng, care: Care) -> void:
	_rules = rules
	_rng = rng
	_care = care


## Set up both corners and reset the pools. `opponent_rank` sizes the purse.
##
## NOTE FOR THE UI / GameState: `MatchResult.purse` and `MatchResult.rank_delta`
## are left at 0 here on purpose. Both need the PLAYER's ladder rank, which the
## resolver is never told (`begin` only takes the opponent's). Fill them from
## `Economy.purse_for()` and `Ladder.rank_delta_for()` in `finish_match()`.
func begin(player_monkey: Monkey, opponent_monkey: Monkey, opponent_rank: int) -> void:
	player = _make_fighter(player_monkey, true)
	opponent = _make_fighter(opponent_monkey, false)
	_opponent_rank = opponent_rank
	round_index = 1
	time_remaining = ROUND_SECONDS
	_round_active = false
	_finished = false
	_ko = false
	_player_won_ko = false
	_corner_used = false
	_exchange_pool = 0.0
	_rounds = []
	_round_events = []
	_new_events = []
	_result = null
	_player_last_strategy = -1
	_reset_taps()


## Set the player's strategy. Legal before round 1 and during an intermission;
## it takes effect at the next `start_round()`, because the obedience roll and
## the monkey's own choice are both locked in at the bell.
func set_strategy(strategy: Strategy) -> void:
	if player == null:
		push_error("MatchResolver.set_strategy before begin()")
		return
	player.strategy = strategy
	if not _round_active:
		player.acting_strategy = strategy


## One corner action per intermission, irreversible. `item_id` only for ITEM.
func apply_corner_action(action: CornerAction, item_id: String = "") -> void:
	if player == null or _finished:
		return
	if _round_active:
		push_warning("MatchResolver: corner actions are only legal between rounds")
		return
	if _corner_used:
		push_warning("MatchResolver: the corner action is irreversible — one per break")
		return
	_corner_used = true
	_apply_corner(player, action, item_id)


## Begin the current round: rolls obedience, emits ROUND_START.
func start_round() -> void:
	if player == null or _finished or _round_active:
		return
	time_remaining = ROUND_SECONDS
	_exchange_pool = 0.0
	_round_events = []
	_new_events = []
	_reset_taps()
	_round_active = true

	# Dossier §5/§6 [C], GameRules.disobedience_enabled: "A monkey with
	# insufficient friendship may ignore your instructions." Rolled once per
	# round, as the architecture contract requires. Only the player's monkey is
	# rolled — the opponent's corner is not the player's relationship to manage.
	player.obeying = true
	player.acting_strategy = player.strategy
	if _rules != null and _rules.disobedience_enabled and _care != null:
		player.obeying = _care.obeys(player.monkey)
		if not player.obeying:
			player.acting_strategy = _own_idea(player.strategy)
			_log(EventKind.DISOBEYED, true, int(player.acting_strategy),
				"%s IGNORES YOU AND %s!" % [
					_name_of(player), _own_idea_text(player.acting_strategy)])

	opponent.obeying = true
	opponent.acting_strategy = _choose_opponent_strategy()

	_log(EventKind.ROUND_START, true, round_index, "ROUND %d!" % round_index)
	round_started.emit(round_index)


## Step the round clock by `delta` seconds and return the events generated.
## The UI calls this from _process; tests call it with big deltas.
func advance(delta: float) -> Array[MatchEvent]:
	_new_events = []
	if not _round_active or _finished or delta <= 0.0:
		return [] as Array[MatchEvent]
	time_remaining = maxf(0.0, time_remaining - delta)
	_exchange_pool += delta
	while _exchange_pool >= EXCHANGE_SECONDS and not _ko and not _finished:
		_exchange_pool -= EXCHANGE_SECONDS
		_resolve_exchange()
		if time_remaining <= 0.0:
			break
	if is_round_over():
		_exchange_pool = 0.0
	# Copied, so a caller holding the batch cannot be surprised by later events
	# landing in it (end_round() logs ROUND_END through the same path).
	return _new_events.duplicate()


## GameRules.fight_interactivity == TAP_ENCOURAGE only. A player tap during a
## live round gives a small effect (this build's addition, not the original's).
## Must be rate-limited so mashing is not a win button.
func register_tap() -> void:
	if _rules == null or _rules.fight_interactivity != GameRules.FightInteractivity.TAP_ENCOURAGE:
		return
	if not _round_active or _finished or _ko:
		return
	if _tap_credits >= TAP_MAX_PER_ROUND:
		return
	if _tap_last_at - time_remaining < TAP_COOLDOWN:
		return
	_tap_last_at = time_remaining
	_tap_credits += 1
	_log(EventKind.TAP_ENCOURAGE, true, _tap_credits,
		"THE CROWD ROARS FOR %s!" % _name_of(player))


func is_round_over() -> bool:
	return _finished or _ko or time_remaining <= 0.0


## Close the round, emit round_finished, and move to the intermission (or the
## end of the match after round 3 / a KO).
func end_round() -> RoundResult:
	if player == null:
		return RoundResult.new()
	# Idempotent: calling it twice must not push a phantom round onto the card.
	if not _round_active:
		return _rounds[-1] if not _rounds.is_empty() else RoundResult.new()
	var res := RoundResult.new()
	res.round_index = round_index
	res.events = _round_events.duplicate()
	res.player_strength = player.strength
	res.player_stamina = player.stamina
	res.opponent_strength = opponent.strength
	res.opponent_stamina = opponent.stamina
	res.player_downs = player.downs
	res.opponent_downs = opponent.downs
	res.knockout = _ko
	res.player_won_ko = _ko and _player_won_ko
	res.player_obeyed = player.obeying

	if _round_active:
		_log(EventKind.ROUND_END, true, round_index, "END OF ROUND %d." % round_index)
		res.events = _round_events.duplicate()
	_round_active = false
	_player_last_strategy = int(player.acting_strategy)
	_rounds.append(res)
	round_finished.emit(res)

	if _ko or round_index >= ROUNDS:
		_finish_match()
	else:
		round_index += 1
		time_remaining = ROUND_SECONDS
		_corner_used = false
		_opponent_corner_action()
		# The index is the round the corner break leads INTO, so it always
		# agrees with `self.round_index`.
		intermission_started.emit(round_index)
	return res


## Run a whole round at once: start_round + advance to the bell + end_round.
func simulate_round() -> RoundResult:
	if _finished:
		return _rounds[-1] if not _rounds.is_empty() else RoundResult.new()
	start_round()
	var guard := 0
	while not is_round_over() and guard < 10000:
		guard += 1
		advance(EXCHANGE_SECONDS)
	return end_round()


## Run the entire match with a fixed strategy and no corner actions. Test helper.
func simulate_match(strategy: Strategy) -> MatchResult:
	if player == null:
		push_error("MatchResolver.simulate_match before begin()")
		return MatchResult.new()
	set_strategy(strategy)
	while not _finished:
		set_strategy(strategy)
		simulate_round()
	return result()


func is_finished() -> bool:
	return _finished


func result() -> MatchResult:
	if _result == null:
		var empty := MatchResult.new()
		empty.opponent_rank = _opponent_rank
		empty.rounds = _rounds
		return empty
	return _result


## Judges' decision. Dossier §6 [C]: weighs number of downs, remaining Strength
## and remaining Stamina. The relative weights are [X] — see JUDGE_WEIGHT_*.
func judge_decision() -> MatchResult:
	var res := MatchResult.new()
	res.opponent_rank = _opponent_rank
	res.rounds = _rounds
	if player == null:
		return res
	res.player_score = _judge_score(player, opponent)
	res.opponent_score = _judge_score(opponent, player)
	if res.player_score > res.opponent_score:
		res.outcome = Outcome.WIN_DECISION
		res.player_won = true
		res.summary = "%s WINS ON THE JUDGES' CARDS, %d-%d." % [
			_name_of(player), res.player_score, res.opponent_score]
	elif res.player_score < res.opponent_score:
		res.outcome = Outcome.LOSS_DECISION
		res.summary = "%s TAKES THE DECISION, %d-%d." % [
			_name_of(opponent), res.opponent_score, res.player_score]
	else:
		res.outcome = Outcome.DRAW
		res.summary = "THE JUDGES CANNOT SEPARATE THEM. A DRAW, %d-%d." % [
			res.player_score, res.opponent_score]
	return res


static func strategy_label(strategy: Strategy) -> String:
	return STRATEGY_LABELS[strategy]


static func corner_label(action: CornerAction) -> String:
	return CORNER_LABELS[action]


# --- setup helpers -----------------------------------------------------------

func _make_fighter(m: Monkey, is_player: bool) -> Fighter:
	var f := Fighter.new()
	f.monkey = m
	f.is_player = is_player
	f.strength = maxi(0, m.max_strength()) if m != null else 0
	f.stamina = maxi(0, m.max_stamina()) if m != null else 0
	f.downs = 0
	f.strategy = Strategy.BALANCED
	f.acting_strategy = Strategy.BALANCED
	f.obeying = true
	f.power_bonus = 0.0
	return f


func _reset_taps() -> void:
	_tap_credits = 0
	# Seeded above the clock so the first tap of a round always counts.
	_tap_last_at = ROUND_SECONDS + TAP_COOLDOWN


# --- the round ---------------------------------------------------------------

func _resolve_exchange() -> void:
	if _finished or _ko or player == null:
		return
	# A fighter with no Strength stat at all is already beaten — guard before
	# anything divides by a max of zero.
	if player.strength <= 0 or opponent.strength <= 0:
		_declare_ko(opponent if player.strength <= 0 else player)
		return

	var p_strat := _exchange_strategy(player, opponent)
	var o_strat := _exchange_strategy(opponent, player)
	_upkeep(player, p_strat)
	_upkeep(opponent, o_strat)

	if _rng.chance(_throw_rate(p_strat)):
		_resolve_punch(player, opponent, p_strat, o_strat)
	if _ko or _finished:
		return
	if _rng.chance(_throw_rate(o_strat)):
		_resolve_punch(opponent, player, o_strat, p_strat)


## BALANCED is resolved per exchange; everything else executes as set.
func _exchange_strategy(f: Fighter, foe: Fighter) -> Strategy:
	if f.acting_strategy != Strategy.BALANCED:
		return f.acting_strategy
	return _balanced_pick(f, foe)


## "Mixes all three; the monkey picks per situation, and picks *better* with
## high Knowledge" — dossier §6 [C]. The read itself is fixed; Knowledge only
## decides how often the monkey actually follows it.
func _balanced_pick(f: Fighter, foe: Fighter) -> Strategy:
	# The read that a clever monkey makes, in priority order. It is the attrition
	# system stated as a policy: never feed a fresh guard, punish an empty tank,
	# and block whatever is being thrown at you.
	var correct := Strategy.EVADE
	if _stamina_frac(f) < 0.30:
		correct = Strategy.DEFEND
	elif _stamina_frac(foe) < 0.40:
		correct = Strategy.ATTACK
	elif foe.acting_strategy == Strategy.ATTACK:
		correct = Strategy.DEFEND
	elif foe.acting_strategy == Strategy.DEFEND:
		correct = Strategy.EVADE
	elif _strength_frac(f) < 0.35:
		correct = Strategy.EVADE
	elif _stamina_frac(f) > 0.60:
		correct = Strategy.ATTACK
	var knowledge := float(_stat(f, Monkey.Stat.KNOWLEDGE))
	var p := KNOWLEDGE_FLOOR + KNOWLEDGE_SPAN * (knowledge / (knowledge + KNOWLEDGE_REFERENCE))
	if _rng.chance(p):
		return correct
	return [Strategy.ATTACK, Strategy.DEFEND, Strategy.EVADE][_rng.randi_range(0, 2)] as Strategy


## How often a stance throws a punch in one exchange.
func _throw_rate(strategy: Strategy) -> float:
	match strategy:
		Strategy.ATTACK:
			return THROW_ATTACK
		Strategy.DEFEND:
			return THROW_DEFEND
		Strategy.EVADE:
			return THROW_EVADE
		_:
			return THROW_EVADE


func _upkeep(f: Fighter, strategy: Strategy) -> void:
	var maxs := _max_stamina(f)
	if maxs <= 0:
		f.stamina = 0
		return
	var cost := UPKEEP_EVADE
	match strategy:
		Strategy.ATTACK:
			cost = UPKEEP_ATTACK
		Strategy.DEFEND:
			cost = UPKEEP_DEFEND
		Strategy.EVADE:
			cost = UPKEEP_EVADE
		_:
			cost = UPKEEP_EVADE
	var delta := (cost - STAMINA_REGEN) * float(maxs)
	f.stamina = clampi(f.stamina - int(round(delta)), 0, maxs)


func _resolve_punch(att: Fighter, def: Fighter, sa: Strategy, sd: Strategy) -> void:
	var by_player := att.is_player

	# Dodge first: a slipped punch never becomes a block.
	if _rng.chance(_dodge_chance(def, att, sd)):
		_spend_stamina(def, DODGE_COST)
		_log(EventKind.PUNCH_DODGED, by_player, 0,
			"%s SLIPS IT!" % _name_of(def))
		return

	# Blocked. THIS is the attrition engine: DEFEND "drains the attacking
	# opponent's Stamina badly" (dossier §6 [C]).
	if _rng.chance(_block_chance(def, sd)):
		var drain := int(round(BLOCK_DRAIN * float(_max_stamina(att)) * _effectiveness(def)))
		if drain > 0:
			att.stamina = maxi(0, att.stamina - drain)
		_log(EventKind.PUNCH_BLOCKED, by_player, drain,
			"%s WALLS IT OFF!" % _name_of(def))
		if drain > 0:
			_log(EventKind.STAMINA_DRAIN, by_player, drain,
				"%s IS BURNING ENERGY ON THE GUARD!" % _name_of(att))
		return

	var damage := _punch_damage(att, def, sa, sd)
	if damage <= 0:
		_log(EventKind.PUNCH_BLOCKED, by_player, 0, "%s SMOTHERS IT." % _name_of(def))
		return
	def.strength = maxi(0, def.strength - damage)
	_log(EventKind.PUNCH_LANDED, by_player, damage,
		"%s CONNECTS! (-%d)" % [_name_of(att), damage])

	if def.strength <= 0:
		_declare_ko(att)
		return
	if _rng.chance(_knockdown_chance(def)):
		_knock_down(def, att)


func _punch_damage(att: Fighter, def: Fighter, sa: Strategy, sd: Strategy) -> int:
	var base := 0.0
	match sa:
		Strategy.ATTACK:
			base = DAMAGE_ATTACK * float(_stat(att, Monkey.Stat.POWER))
		Strategy.EVADE:
			base = DAMAGE_EVADE * float(_stat(att, Monkey.Stat.SPEED))
		Strategy.DEFEND:
			base = DAMAGE_COUNTER * float(_stat(att, Monkey.Stat.POWER))
		_:
			base = DAMAGE_EVADE * float(_stat(att, Monkey.Stat.SPEED))
	var value := base
	value *= _effectiveness(att)
	value *= 1.0 + att.power_bonus
	value *= _vulnerability(def)
	if sd == Strategy.DEFEND:
		value *= DEFEND_ABSORB
	value *= _rng.randf_range(1.0 - DAMAGE_VARIANCE, 1.0 + DAMAGE_VARIANCE)
	return maxi(0, int(round(value)))


func _knock_down(f: Fighter, by: Fighter) -> void:
	f.downs += 1
	_spend_stamina(f, DOWN_STAMINA_COST)
	_log(EventKind.KNOCKDOWN, by.is_player, f.downs,
		"%s IS DOWN! (%d)" % [_name_of(f), f.downs])
	if f.downs >= KNOCKDOWN_LIMIT:
		_declare_ko(by)
		return
	var lost := DOWN_SECONDS
	if f.is_player:
		lost -= minf(float(_tap_credits) * TAP_GETUP_RELIEF, TAP_GETUP_RELIEF_MAX)
	time_remaining = maxf(0.0, time_remaining - maxf(0.0, lost))
	_log(EventKind.GET_UP, f.is_player, int(round(lost)),
		"%s IS BACK UP!" % _name_of(f))


func _declare_ko(winner: Fighter) -> void:
	if _ko or _finished:
		return
	_ko = true
	_player_won_ko = winner.is_player
	_log(EventKind.KO, winner.is_player, 0,
		"KNOCKOUT! %s WINS IT!" % _name_of(winner))


# --- opponent AI -------------------------------------------------------------

## The CPU corner. DIVERGENCE: no source describes the opponent AI at all.
##
## Round 1 is deliberately mixed rather than always-aggressive: that is what
## makes leading with ATTACK a gamble and leading with DEFEND the safe play,
## which is the shape the dossier describes (§6 [C]: "straight aggression from
## round 1 is reserved for clearly weaker opponents"). From round 2 the corner
## reads what your monkey did LAST round — so it stops feeding a guard, and
## turtling for three rounds is not a free win. It reads correctly as often as
## its own Knowledge allows, exactly like BALANCED does.
func _choose_opponent_strategy() -> Strategy:
	if round_index <= 1 or _player_last_strategy < 0:
		return _weighted_strategy([0.50, 0.25, 0.25])
	var read := Strategy.EVADE
	if _stamina_frac(opponent) < 0.30:
		read = Strategy.DEFEND
	elif _stamina_frac(player) < 0.40:
		read = Strategy.ATTACK
	elif _player_last_strategy == Strategy.ATTACK:
		read = Strategy.DEFEND
	elif _player_last_strategy == Strategy.DEFEND:
		read = Strategy.EVADE
	elif _strength_frac(opponent) < 0.30:
		read = Strategy.EVADE
	elif _stamina_frac(opponent) > 0.60:
		read = Strategy.ATTACK
	var knowledge := float(_stat(opponent, Monkey.Stat.KNOWLEDGE))
	var p := KNOWLEDGE_FLOOR + KNOWLEDGE_SPAN * (knowledge / (knowledge + KNOWLEDGE_REFERENCE))
	if _rng.chance(p):
		return read
	return _weighted_strategy([0.50, 0.25, 0.25])


## Weights are [ATTACK, DEFEND, EVADE].
func _weighted_strategy(weights: Array) -> Strategy:
	var roll := _rng.randf()
	if roll < float(weights[0]):
		return Strategy.ATTACK
	if roll < float(weights[0]) + float(weights[1]):
		return Strategy.DEFEND
	return Strategy.EVADE


func _opponent_corner_action() -> void:
	if opponent == null:
		return
	var stm := _stamina_frac(opponent)
	var strg := _strength_frac(opponent)
	if stm < 0.6 and stm <= strg:
		_apply_corner(opponent, CornerAction.BREATHE)
	elif strg < 0.6:
		_apply_corner(opponent, CornerAction.BANDAGE)
	else:
		_apply_corner(opponent, CornerAction.WATER)


# --- corner ------------------------------------------------------------------

func _apply_corner(f: Fighter, action: CornerAction, item_id: String = "") -> void:
	var max_str := _max_strength(f)
	var max_stm := _max_stamina(f)
	match action:
		CornerAction.BANDAGE:
			f.strength = clampi(f.strength + int(round(CORNER_BANDAGE_STRENGTH * float(max_str))), 0, max_str)
		CornerAction.BREATHE:
			f.stamina = clampi(f.stamina + int(round(CORNER_BREATHE_STAMINA * float(max_stm))), 0, max_stm)
		CornerAction.WATER:
			f.strength = clampi(f.strength + int(round(CORNER_WATER_BOTH * float(max_str))), 0, max_str)
			f.stamina = clampi(f.stamina + int(round(CORNER_WATER_BOTH * float(max_stm))), 0, max_stm)
		CornerAction.ITEM:
			# Out of scope: the item economy. Any item behaves as Monk Max here.
			# DIVERGENCE: item ids are not modelled in the vertical slice, so the
			# id is only recorded for the UI's message box.
			f.power_bonus += CORNER_ITEM_POWER_BONUS
			last_item_id = item_id


# --- scoring -----------------------------------------------------------------

func _judge_score(f: Fighter, foe: Fighter) -> int:
	var score := JUDGE_WEIGHT_DOWN * float(foe.downs)
	score += JUDGE_WEIGHT_STRENGTH * _strength_frac(f)
	score += JUDGE_WEIGHT_STAMINA * _stamina_frac(f)
	return int(round(score))


func _finish_match() -> void:
	if _finished:
		return
	_finished = true
	_round_active = false
	var res := judge_decision()
	if _ko:
		res.outcome = Outcome.WIN_KO if _player_won_ko else Outcome.LOSS_KO
		res.player_won = _player_won_ko
		res.summary = "%s WINS BY KNOCKOUT." % [
			_name_of(player) if _player_won_ko else _name_of(opponent)]
	else:
		_log(EventKind.DECISION, res.player_won, res.player_score, res.summary)
		if not _rounds.is_empty():
			_rounds[-1].events = _round_events.duplicate()
	_result = res
	_write_back()
	match_finished.emit(res)


## The live pools belong to the monkey once the bell has gone — Care's
## `apply_overnight_recovery()` and the "worn out the following day" rule
## (§6 [C]) both read them. Wins/losses are deliberately NOT touched here: the
## ladder and GameState.finish_match() own the record so it cannot double-count.
func _write_back() -> void:
	if player != null and player.monkey != null:
		player.monkey.current_strength = maxi(0, player.strength)
		player.monkey.current_stamina = maxi(0, player.stamina)
		player.monkey.days_since_match = 0
	if opponent != null and opponent.monkey != null:
		opponent.monkey.current_strength = maxi(0, opponent.strength)
		opponent.monkey.current_stamina = maxi(0, opponent.stamina)


# --- maths -------------------------------------------------------------------

func _stat(f: Fighter, stat: Monkey.Stat) -> int:
	if f == null or f.monkey == null:
		return 0
	return maxi(0, f.monkey.get_stat(stat))


func _max_strength(f: Fighter) -> int:
	return _stat(f, Monkey.Stat.STRENGTH)


func _max_stamina(f: Fighter) -> int:
	return _stat(f, Monkey.Stat.STAMINA)


func _strength_frac(f: Fighter) -> float:
	var m := _max_strength(f)
	if m <= 0:
		return 0.0
	return clampf(float(f.strength) / float(m), 0.0, 1.0)


func _stamina_frac(f: Fighter) -> float:
	var m := _max_stamina(f)
	if m <= 0:
		return 0.0
	return clampf(float(f.stamina) / float(m), 0.0, 1.0)


## How much of itself a fighter can still put behind anything it does.
func _effectiveness(f: Fighter) -> float:
	var e := EFFECT_FLOOR + (1.0 - EFFECT_FLOOR) * _stamina_frac(f)
	if f.is_player:
		e += minf(float(_tap_credits) * TAP_BONUS_STEP, TAP_BONUS_MAX)
	return e


## A tired fighter eats punches.
func _vulnerability(f: Fighter) -> float:
	return 1.0 + VULNERABILITY_AT_ZERO * (1.0 - _stamina_frac(f))


func _block_chance(def: Fighter, sd: Strategy) -> float:
	var base := BLOCK_EVADE
	match sd:
		Strategy.ATTACK:
			base = BLOCK_ATTACK
		Strategy.DEFEND:
			base = BLOCK_DEFEND
		Strategy.EVADE:
			base = BLOCK_EVADE
		_:
			base = BLOCK_EVADE
	return clampf(base * _effectiveness(def), 0.0, BLOCK_MAX)


func _dodge_chance(def: Fighter, att: Fighter, sd: Strategy) -> float:
	var base := DODGE_EVADE
	match sd:
		Strategy.ATTACK:
			base = DODGE_ATTACK
		Strategy.DEFEND:
			base = DODGE_DEFEND
		Strategy.EVADE:
			base = DODGE_EVADE
		_:
			base = DODGE_EVADE
	# "Keep moving" scales with Speed (dossier §6 [C]) — relative to the
	# attacker's, so speed is a contest rather than a flat number.
	var ds := float(_stat(def, Monkey.Stat.SPEED))
	var as_ := float(_stat(att, Monkey.Stat.SPEED))
	var ratio := 1.0
	if ds + as_ > 0.0:
		ratio = 2.0 * ds / (ds + as_)
	return clampf(base * ratio * _effectiveness(def), 0.0, DODGE_MAX)


func _knockdown_chance(def: Fighter) -> float:
	var hurt := 1.0 - _strength_frac(def)
	var tired := 0.5 + 0.5 * (1.0 - _stamina_frac(def))
	return clampf(KNOCKDOWN_BASE * hurt * tired, 0.0, 0.5)


func _spend_stamina(f: Fighter, fraction: float) -> void:
	var maxs := _max_stamina(f)
	if maxs <= 0:
		return
	f.stamina = maxi(0, f.stamina - int(round(fraction * float(maxs))))


# --- text --------------------------------------------------------------------

## The disobedient monkey picks something that is NOT what you asked for.
func _own_idea(asked: Strategy) -> Strategy:
	var options: Array[Strategy] = []
	for s in [Strategy.ATTACK, Strategy.DEFEND, Strategy.EVADE, Strategy.BALANCED]:
		if s != asked:
			options.append(s)
	return options[_rng.randi_range(0, options.size() - 1)]


func _own_idea_text(strategy: Strategy) -> String:
	match strategy:
		Strategy.ATTACK:
			return "SWINGS WILDLY"
		Strategy.DEFEND:
			return "COVERS UP"
		Strategy.EVADE:
			return "DANCES AWAY"
		_:
			return "DOES ITS OWN THING"


func _name_of(f: Fighter) -> String:
	if f == null:
		return "?"
	if f.monkey != null and f.monkey.monkey_name != "":
		return f.monkey.monkey_name.to_upper()
	return "YOUR MONKEY" if f.is_player else "THE CHALLENGER"


func _log(kind: EventKind, by_player: bool, amount: int, text: String) -> MatchEvent:
	var e := MatchEvent.new()
	e.kind = kind
	e.round_index = round_index
	e.time_remaining = time_remaining
	e.by_player = by_player
	e.amount = amount
	e.text = text
	_round_events.append(e)
	_new_events.append(e)
	event_logged.emit(e)
	return e
