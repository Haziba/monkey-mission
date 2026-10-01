class_name Training
extends RefCounted

## The training activities and their stat gains. Dossier §3 and §4.
##
## §3 [C], one training activity per stat:
##   POWER     <- Punchbag
##   SPEED     <- Skipping rope
##   KNOWLEDGE <- Shopping errands   (selected via "call monkey -> shopping")
##   STRENGTH  <- Sit-ups            (Strength is the HEALTH BAR)
##   STAMINA   <- Running
##
## §4 [C]: there are actually SIX activities — the commonly-repeated "five" drops
## SPARRING, which raises all five stats by a smaller amount and declares no
## winner. The brief scopes this slice to the five stat-training activities, so
## SPARRING is declared here (so nobody re-numbers the enum later) but is NOT in
## SLICE_ACTIVITIES and may be left unimplemented.
##
## Every session costs one half-day slot (§2 [C]). Feeding does not.
##
## [X] FLAGS for the implementing agent — dossier §14.10 says per-session stat
## gains, growth curves and the numeric difference between training tiers are
## all unknown. Every number in the gain formula needs a `# DIVERGENCE:` comment.

enum Activity {
	PUNCHBAG,   ## -> POWER
	SKIPPING,   ## -> SPEED
	SIT_UPS,    ## -> STRENGTH
	RUNNING,    ## -> STAMINA
	SHOPPING,   ## -> KNOWLEDGE (also the only route to new foods/items/books)
	SPARRING,   ## -> all five, smaller. OUT OF SLICE SCOPE.
}

## The five the vertical slice must ship. Order matches the in-game menu layout
## in dossier §4: SKIPPING / SIT-UPS / PUNCHBAG / RUNNING / (SPARRING).
const SLICE_ACTIVITIES: Array[int] = [
	Activity.SKIPPING,
	Activity.SIT_UPS,
	Activity.PUNCHBAG,
	Activity.RUNNING,
	Activity.SHOPPING,
]

## Mission reskin: the drone runs the drill; the monkey copies. Enum order and
## the stat->activity map are frozen (see stat_for()); only the labels move.
##   PUNCHBAG  -> THREAT RESPONSE   (POWER / WEAPONS)
##   SKIPPING  -> ZERO-G AGILITY    (SPEED / PILOT)
##   SIT-UPS   -> BANANA RATIONING  (STRENGTH-as-willpower / SHIELDS)
##   RUNNING   -> COMMS RELAY       (STAMINA / ENGINES)
##   SHOPPING  -> CONSOLE LITERACY  (KNOWLEDGE / SENSORS)
##   SPARRING  -> FULL DRILLS       (all five, out of slice)
const ACTIVITY_LABELS: PackedStringArray = [
	"THREAT RESPONSE", "ZERO-G AGILITY", "BANANA RATIONING",
	"COMMS RELAY", "CONSOLE LITERACY", "FULL DRILLS",
]

## How a single tap sat against the beat. Dossier §4 [C]: failure is two-sided —
## press too FAST and the trainer cramps, too SLOW and the monkey loses interest.
## Exposed so the minigame scene can colour its feedback without re-deriving the
## window. ADDITION to the frozen contract (nothing renamed or renumbered).
enum TapVerdict {
	EARLY_CRAMP,   ## interval shorter than the window — the trainer cramps
	IN_WINDOW,     ## on the beat
	LATE_BORED,    ## interval longer than the window — the monkey loses interest
}

# --- the rhythm window -------------------------------------------------------
#
# The UI draws this; core owns it so both sides agree on one number.

## DIVERGENCE: dossier §14.10 — the minigame's beat rate is [X]. No source gives
## a tempo, a tier length or a rep target. 0.6s (100bpm) is chosen because it is
## a comfortable thumb tempo on a phone and because the confirmed HUD countdown
## `[0:41]` over a ~45s session then implies a believable `[102]` rep counter
## (§10 [C] shows exactly those two boxes).
const BEAT_INTERVAL := 0.6
## Half-width of the acceptable window, in seconds. Matches the default in
## RhythmScore.from_taps so the two agree. DIVERGENCE: [X], chosen at +/-20% of
## the beat — tight enough that mashing fails, loose enough for a touchscreen.
const BEAT_WINDOW := 0.12

# --- gain curve --------------------------------------------------------------
#
# DIVERGENCE for the whole block: dossier §14.10 lists per-session stat gains,
# growth curves and the numeric difference between the training tiers
# (practice -> special -> continuous -> free -> total challenge -> advanced) as
# entirely undocumented [X]. The shape below is chosen to satisfy the two things
# the dossier DOES confirm: caps are hard and only breeding lifts them (§3 [C]),
# and watching the number climb is the core appeal (§4 [C]). So gains scale with
# the monkey's own cap — a gen-3 monkey with an 820 ceiling gains far more per
# session than Freddy's 145 — and taper as the stat approaches the star.

## Per-session gain at full headroom, as a fraction of the stat's cap.
## 0.10 puts a from-zero climb to a star at roughly 15 sessions per stat, i.e.
## about a week and a half of in-game half-days for one stat.
const BASE_GAIN_CAP_FRACTION := 0.10
## What survives of that rate when the stat is already touching its cap. The
## taper is deliberately shallow so the last few points are slow but not a wall.
const GAIN_LATE_FLOOR := 0.35
## A session never *requests* less than this, so a capped stat still reports
## was_capped instead of silently requesting zero.
const MIN_GAIN := 1
## SPARRING raises all five "by a smaller amount each" (§4 [C]). The amount is
## [X]; 0.4 of a dedicated session keeps single-stat training the better choice.
const SPARRING_FRACTION := 0.4
## A well-bonded monkey concentrates. DIVERGENCE: [X] — the dossier only says
## friendship gates training at all, never that it scales gains. Small on purpose.
const FRIENDSHIP_FOCUS_BONUS := 0.25

# --- rhythm multiplier -------------------------------------------------------
#
# DIVERGENCE: all [X]. The one hard constraint from §4 [C] is that failure is
# TWO-SIDED: too-early taps (cramp) and too-late taps (lost interest) must BOTH
# reduce the result. A curve that only punishes "too slow" is wrong.

## Multiplier for a session where nothing landed in the window.
const RHYTHM_MIN_MULT := 0.2
## Multiplier for a flawless session. Above 1.0 so good play is a real reward.
const RHYTHM_MAX_MULT := 1.5
## Extra penalty weight for early taps — the trainer cramps.
const CRAMP_WEIGHT := 0.5
## Extra penalty weight for late taps — the monkey loses interest.
const BOREDOM_WEIGHT := 0.5
## Applied when the session was cut short by the hunger interrupt (§4 [C]).
const INTERRUPT_MULT := 0.5
## Absolute floor. Even a shambles is not literally worthless.
const RHYTHM_FLOOR := 0.1

# --- session upkeep ----------------------------------------------------------

## Fullness burned by one physical session, ON TOP of the baseline digestion
## Care.digest_tick applies per half-day slot. DIVERGENCE: [X]; small so that
## training alone cannot starve a fed monkey inside one slot.
const TRAINING_FULLNESS_COST := 2
## Shopping is a walk, not a workout.
const SHOPPING_FULLNESS_COST := 1
## Accuracy at or above this leaves the monkey pleased with itself.
## --- session pacing -------------------------------------------------------
##
## DIVERGENCE: every number below is [X]. No source gives a session length, an
## interest rate, or a rep rate. These are tuned so that an unfriendly, undrilled
## monkey usually never joins in at all, a middling one joins around halfway and
## banks a modest count, and a maxed-out one joins almost immediately — which is
## the dossier's "eventually requiring no prompting for it to begin".

## Wall-clock length of one session, in seconds.
const SESSION_SECONDS := 30.0

## Interest added by one perfectly-timed tap, before the friendship and
## discipline multiplier. At the floor multiplier that is far more taps than a
## session has room for, which is what makes an unfriendly monkey a wasted slot.
const INTEREST_PER_GOOD_TAP := 0.055
## An off-beat tap still shows willing, but barely.
const INTEREST_PER_POOR_TAP := 0.012
## Interest bleeds away while you are not tapping, so stopping loses ground.
const INTEREST_DECAY_PER_SECOND := 0.02

## Friendship and discipline both scale how fast interest builds. Friendship
## decides whether it cares about you; discipline decides whether it knows what
## is expected. Neither alone is enough.
const INTEREST_FRIENDSHIP_WEIGHT := 0.6
const INTEREST_DISCIPLINE_WEIGHT := 0.4
## Multiplier at zero friendship and zero discipline, and at both maxed.
const INTEREST_MULT_MIN := 0.35
const INTEREST_MULT_MAX := 2.6

## Reps the monkey performs per second once it is working, at zero relevant
## stat, and the bonus at a maxed one. A fitter monkey simply does more.
const REPS_PER_SECOND_BASE := 1.6
const REPS_PER_SECOND_AT_CAP := 3.4

## Chance per second that a working monkey drifts off and needs a scold.
## Discipline suppresses it, which is the clearest thing discipline buys.
const DISTRACT_CHANCE_PER_SECOND := 0.10
const DISTRACT_DISCIPLINE_RELIEF := 0.85
## Reps per second while distracted, as a fraction of the normal rate.
const DISTRACTED_REP_FRACTION := 0.25

## An inexperienced monkey burns out mid-set. Per-second chance the working
## monkey trips and sits down, ending the session early with a sad message.
## Curve: chance = TRIP_CHANCE_PER_SECOND * (1 - fitness) ** 2. A fully-trained
## monkey (fitness = 1, stat = cap) never trips; a fresh one (fitness = 0) has
## the base rate and rarely lasts the session. DIVERGENCE: dossier §14.11 says
## "no injury, illness, ageing or lifespan system" — this is a session-ending
## fatigue event, not a lasting harm, so it stays inside the boundary.
const TRIP_CHANCE_PER_SECOND := 0.10
## Grace period after joining in: no trip check until the monkey has warmed up
## for this many seconds. Stops it giving up before it's even started.
const TRIP_GRACE_SECONDS := 3.0
## Friendship cost of a trip. Small — it's disappointment, not a betrayal.
const TRIP_FRIENDSHIP_COST := -1

## Discipline moves, dossier §4 [C]: praise a record, scold the chattering.
## Getting it right teaches; getting it wrong confuses and costs friendship.
const DISCIPLINE_PER_GOOD_SCOLD := 4
const DISCIPLINE_PER_GOOD_PRAISE := 3
const DISCIPLINE_PER_BAD_CALL := -3
const FRIENDSHIP_PER_BAD_SCOLD := -2
const FRIENDSHIP_PER_GOOD_PRAISE := 1
## Praise stops meaning anything if it never stops.
const MAX_REWARDED_PRAISES := 3

const GOOD_SESSION_ACCURACY := 0.75
## Accuracy below this and it got bored and chattery (§4 [C]: "scold when it
## chatters and loses focus").
const POOR_SESSION_ACCURACY := 0.35

# --- shopping ----------------------------------------------------------------
#
# §4 [C]: the monkey goes shopping, not the player; it comes back with only PART
# of the list; Knowledge rises either way; free-choice shopping is the ONLY
# route to new food types and items, at the cost of money wasted on junk.

## Fill rate of a wish list for a monkey with zero Knowledge, and for one at its
## Knowledge cap. DIVERGENCE: [X]. Never reaches 1.0 — "returns with only part
## of the list" is confirmed behaviour, not a failure mode.
const SHOP_MIN_FILL := 0.30
const SHOP_MAX_FILL := 0.90
## A free-choosing monkey will not spend more than this share of the wallet.
## DIVERGENCE: no original figure [X]; a guard rail so one bad trip cannot
## trigger the destitution path on its own.
const SHOP_FREE_BUDGET_FRACTION := 0.5
## Items a free-choice trip comes home with, before junk.
const FREE_CHOICE_MIN_ITEMS := 2
const FREE_CHOICE_MAX_ITEMS := 5
## Chance per junk slot that a free-choosing monkey wastes money on rubbish,
## before the Knowledge discount below. DIVERGENCE: [X]; §3 [C] only says
## Knowledge "raises rare-item find rate", so here it also cuts junk.
const JUNK_CHANCE := 0.55
const JUNK_KNOWLEDGE_DISCOUNT := 0.6
const MAX_JUNK_PER_TRIP := 2
## What the monkey pays for a piece of junk. DIVERGENCE: the dossier's §9 junk
## table lists SELL values only (Garbage 1 ... Software 4,000); the buy side is
## [X]. This range makes junk a real but survivable waste of money.
const JUNK_COST_MIN := 40
const JUNK_COST_MAX := 160
## Junk ids, lower-cased from the dossier §9 sellable-junk table [C]. Economy
## owns the sell prices; Training only names the thing that came home.
const JUNK_IDS: PackedStringArray = [
	"garbage", "paper", "toaster", "tissue", "shirt", "letter", "pants", "glasses",
]
## Knowledge gain multiplier for a free-choice trip versus a dictated list —
## deciding for itself teaches the monkey more. DIVERGENCE: [X].
const SHOP_FREE_CHOICE_BONUS := 1.2


## The outcome of one session. UI reads this and animates; it does not compute.
## A single training session, modelled as the original describes it: the trainer
## does the exercise, the monkey watches, and at some point it takes an interest
## and joins in. Only then do reps count.
##
## Dossier §4 [C]: "The monkeys learn to train by copying the actions of the main
## character whose motions are controlled by a rhythmic pressing of the A button"
## and "over time, a monkey will learn to imitate these actions for a longer
## period eventually requiring no prompting for it to begin."
##
## So the demonstration is the interactive part and the monkey's own work is not.
## HG101 calls the hands-off stretch the game's weakest idea; it is kept because
## it is what the original does, and because the rep counter climbing on its own
## is the thing Japanese players describe as the appeal (§4 [C]).
##
## Pure logic: no timers, no nodes. The UI drives it with `register_tap()` and
## `tick()` and reads the state back.
class Session extends RefCounted:
	enum State {
		## You are doing the exercise. The monkey is watching. No reps yet.
		DEMONSTRATING,
		## It has joined in and now works on its own. Reps accrue. Nothing for
		## the player to do but watch, praise and scold.
		WORKING,
		ENDED,
	}

	var state: State = State.DEMONSTRATING
	var activity: Activity = Activity.PUNCHBAG
	var monkey: Monkey = null
	## 0.0 to 1.0. Fills while you demonstrate well; the monkey joins at 1.0.
	var interest: float = 0.0
	## Reps the MONKEY has done. The trainer's own taps never count.
	var reps: int = 0
	var time_left: float = 0.0
	## Seconds spent demonstrating before it joined; 0 while it never has.
	var time_to_join: float = 0.0
	var elapsed: float = 0.0
	## Quality of the demonstration, 0..1, from the tap verdicts so far.
	var demo_accuracy: float = 0.0
	## Set when the monkey is drifting and a scold would be deserved.
	var distracted: bool = false
	## Set when the monkey has given up mid-session — an inexperienced one that
	## couldn't sustain the drill. The UI reads this to show the sad ending.
	var tripped: bool = false
	## Rep count at which the previous best was passed, so the UI can celebrate
	## the moment rather than only the summary.
	var beat_record_at: int = -1

	var _good_taps: int = 0
	var _early_taps: int = 0
	var _late_taps: int = 0
	var _total_taps: int = 0
	var _rep_carry: float = 0.0
	var _distract_carry: float = 0.0
	var _trip_carry: float = 0.0
	var _praises: int = 0
	var _scolds: int = 0
	var _discipline_delta: int = 0
	var _friendship_delta: int = 0
	var _rng: MpRng = null

	## Recorded explicitly rather than inferred from `state`: `settle()` moves the
	## session to ENDED before it decides what to bank, and "not DEMONSTRATING"
	## would read as joined for every session that simply ran out of time.
	var _joined: bool = false

	func joined() -> bool:
		return _joined

	func working() -> bool:
		return state == State.WORKING

	func finished() -> bool:
		return state == State.ENDED


class Result extends RefCounted:
	var activity: Activity = Activity.PUNCHBAG
	var stat: Monkey.Stat = Monkey.Stat.POWER
	## What the formula wanted to add.
	var gain_requested: int = 0
	## What actually landed after cap clamping. UI shows this.
	var gain_applied: int = 0
	## True when the cap ate some or all of the gain (show the star, dossier §3).
	var was_capped: bool = false
	## ADDITION to the contract: true only on the session that PUSHED the stat to
	## its ceiling, so the UI can fire the star-out fanfare exactly once.
	var starred_out: bool = false
	## Reps performed; feeds the personal record.
	var reps: int = 0
	## True when this beat the monkey's previous best (praise opportunity).
	var new_personal_best: bool = false
	var friendship_delta: int = 0
	## Net discipline change from praise and scold during the session.
	var discipline_delta: int = 0
	var fullness_cost: int = 0
	## The session stopped because the monkey got hungry (dossier §4 [C]).
	var hunger_interrupt: bool = false
	## Only for SHOPPING: food ids the monkey came home with, and money spent.
	var shopping_haul: Dictionary = {}
	var money_spent: int = 0
	## ADDITION: junk id -> qty the monkey wasted money on (SHOPPING, free choice).
	var junk_haul: Dictionary = {}
	## ADDITION: true when the monkey would not train at all (unbefriended,
	## starving, stuffed). `message` carries the player-facing reason.
	var blocked: bool = false
	## Human-readable line for the message box.
	var message: String = ""


signal session_finished(result: Result)

var _rules: GameRules
var _rng: MpRng


func _init(rules: GameRules, rng: MpRng) -> void:
	_rules = rules
	_rng = rng


## Which stat an activity raises. SPARRING returns POWER but raises all five;
## callers must special-case it via `raises_all()`.
static func stat_for(activity: Activity) -> Monkey.Stat:
	match activity:
		Activity.PUNCHBAG:
			return Monkey.Stat.POWER
		Activity.SKIPPING:
			return Monkey.Stat.SPEED
		Activity.SIT_UPS:
			return Monkey.Stat.STRENGTH
		Activity.RUNNING:
			return Monkey.Stat.STAMINA
		Activity.SHOPPING:
			return Monkey.Stat.KNOWLEDGE
		_:
			return Monkey.Stat.POWER


static func raises_all(activity: Activity) -> bool:
	return activity == Activity.SPARRING


static func display_name(activity: Activity) -> String:
	return ACTIVITY_LABELS[activity]


# --- the rhythm window -------------------------------------------------------

## The beat the UI must draw and the monkey copies. Keys:
##   beat_interval — seconds between prompts
##   window        — half-width of the acceptable band
##   min_interval  — tap faster than this and the trainer CRAMPS
##   max_interval  — tap slower than this and the monkey LOSES INTEREST
## ADDITION to the contract: the brief asks for the target window to be exposed
## so the UI can draw it, and both edges must be visible for the two-sided
## failure of dossier §4 [C] to be legible.
static func target_window() -> Dictionary:
	return {
		"beat_interval": BEAT_INTERVAL,
		"window": BEAT_WINDOW,
		"min_interval": BEAT_INTERVAL - BEAT_WINDOW,
		"max_interval": BEAT_INTERVAL + BEAT_WINDOW,
	}


## Where one inter-tap interval sits against the window.
static func classify_interval(interval: float) -> TapVerdict:
	if interval < BEAT_INTERVAL - BEAT_WINDOW:
		return TapVerdict.EARLY_CRAMP
	if interval > BEAT_INTERVAL + BEAT_WINDOW:
		return TapVerdict.LATE_BORED
	return TapVerdict.IN_WINDOW


# --- gating ------------------------------------------------------------------

## Can this monkey train at all right now? False when it is unbefriended,
## starving, stuffed (overfeeding paralysis) or otherwise immobilised.
##
## The hunger half of the question is Care's concern, but Training must not
## construct a Care (it is handed neither one nor the Monkey's owner), so it asks
## the same questions of the Monkey's own predicates. Keep the two in step.
func can_train(monkey: Monkey) -> bool:
	return _blocked(monkey) == Block.NOT_BLOCKED


## Why the monkey will not train. Ordered exactly as `_block_reason` reports it.
enum Block { NOT_BLOCKED, NO_MONKEY, UNBEFRIENDED, STARVING, STUFFED, IMMOBILISED }


## PURE. Asking whether a monkey can train must never move the game on, so the
## predicate is separated from the flavour text.
##
## It used to be the other way round — `can_train()` returned
## `_block_reason(monkey) == ""`, and `_block_reason` rolls `_rng.chance(0.5)`
## to pick between "BITES YOU" and "TURNS ITS BACK" for an unbefriended monkey.
## That made a read-only question consume a draw from the RUN'S SHARED stream:
## verified that seven extra `can_train()` calls on an unbefriended monkey
## changed the next `randf()` from 0.294003 to 0.574056. A screen greying out
## its TRAIN button, or simply being redrawn a different number of times, would
## have silently desynced the whole run from its seed — which also breaks
## `test_the_same_seed_produces_the_same_run` in spirit, since that test never
## polls the predicate. Only `_block_reason` rolls now, and only when it is
## actually about to show the player a line of text.
func _blocked(monkey: Monkey) -> Block:
	if monkey == null:
		return Block.NO_MONKEY
	# Dossier §5 [C]: befriending gates everything. Until it is won over with
	# food the monkey is disobedient and will bite you.
	if not monkey.is_befriended():
		return Block.UNBEFRIENDED
	# Both hunger extremes immobilise (§5 [C]).
	if monkey.is_starving():
		return Block.STARVING
	if monkey.is_stuffed() and (_rules == null or _rules.overfeeding_paralyses):
		return Block.STUFFED
	if monkey.paralysed_slots > 0:
		return Block.IMMOBILISED
	return Block.NOT_BLOCKED


## Player-facing reason the monkey will not train, or "" when it will.
## NOT pure — the unbefriended line is picked at random. Call it only when the
## text is actually going to be shown; use `can_train()` to ask the question.
func _block_reason(monkey: Monkey) -> String:
	match _blocked(monkey):
		Block.NO_MONKEY:
			return "THERE IS NO MONKEY!"
		Block.UNBEFRIENDED:
			if _rng != null and _rng.chance(0.5):
				return "%s BITES YOU! IT DOESN'T TRUST YOU YET." % monkey.monkey_name
			return "%s TURNS ITS BACK ON YOU." % monkey.monkey_name
		Block.STARVING:
			return "%s IS TOO HUNGRY TO MOVE!" % monkey.monkey_name
		Block.STUFFED:
			return "%s IS TOO FULL TO MOVE. IT MUST DIGEST!" % monkey.monkey_name
		Block.IMMOBILISED:
			return "%s CANNOT MOVE YET!" % monkey.monkey_name
	return ""


# --- a session ---------------------------------------------------------------

## Run one session. Consumes no slot itself — the caller (GameState) advances
## the DayCycle. Applies the gain to `monkey`, clamped at the cap when
## GameRules.hard_stat_caps is on.
## Open a session. Returns null when the monkey will not work at all — an
## unbefriended, starving or stuffed one (§5 [C], both hunger extremes
## immobilise). The caller has already spent nothing at this point.
func begin_session(monkey: Monkey, activity: Activity) -> Session:
	if monkey == null or activity == Activity.SHOPPING:
		return null
	var session := Session.new()
	session.monkey = monkey
	session.activity = activity
	session.time_left = SESSION_SECONDS
	session._rng = _rng
	if _block_reason(monkey) != "":
		session.state = Session.State.ENDED
	return session


## How fast this monkey warms up. Friendship and discipline both count, and
## neither on its own gets you near the top.
func interest_multiplier(monkey: Monkey) -> float:
	if monkey == null:
		return INTEREST_MULT_MIN
	var friendly := float(monkey.friendship) / float(Monkey.FRIENDSHIP_MAX)
	var drilled := float(monkey.discipline) / float(Monkey.DISCIPLINE_MAX)
	var blend := INTEREST_FRIENDSHIP_WEIGHT * friendly + INTEREST_DISCIPLINE_WEIGHT * drilled
	return lerpf(INTEREST_MULT_MIN, INTEREST_MULT_MAX, clampf(blend, 0.0, 1.0))


## One tap of the trainer's own exercise. Only meaningful while demonstrating —
## once the monkey has joined in it is working to its own rhythm, not yours.
func register_tap(session: Session, interval: float) -> TapVerdict:
	var verdict := classify_interval(interval)
	if session == null or session.state != Session.State.DEMONSTRATING:
		return verdict
	session._total_taps += 1
	if verdict == TapVerdict.IN_WINDOW:
		session._good_taps += 1
		session.interest += INTEREST_PER_GOOD_TAP * interest_multiplier(session.monkey)
	else:
		# A cramped or bored tap is not nothing, but it is close to it.
		if verdict == TapVerdict.EARLY_CRAMP:
			session._early_taps += 1
		else:
			session._late_taps += 1
		session.interest += INTEREST_PER_POOR_TAP * interest_multiplier(session.monkey)
	session.demo_accuracy = float(session._good_taps) / float(maxi(1, session._total_taps))
	if session.interest >= 1.0:
		session.interest = 1.0
		session.state = Session.State.WORKING
		session._joined = true
		session.time_to_join = session.elapsed
	return verdict


## Advance the clock. The UI calls this every frame; tests call it in slices.
func tick(session: Session, delta: float) -> void:
	if session == null or session.state == Session.State.ENDED or delta <= 0.0:
		return
	delta = minf(delta, session.time_left)
	session.elapsed += delta
	session.time_left -= delta

	if session.state == Session.State.DEMONSTRATING:
		# Stop tapping and it cools off. Standing still loses ground.
		session.interest = maxf(0.0, session.interest - INTEREST_DECAY_PER_SECOND * delta)
	else:
		_tick_working(session, delta)

	if session.time_left <= 0.0:
		session.state = Session.State.ENDED


func _tick_working(session: Session, delta: float) -> void:
	var monkey := session.monkey
	# Drift on and off task. Discipline is what buys attention.
	var drilled := float(monkey.discipline) / float(Monkey.DISCIPLINE_MAX)
	var drift_chance := DISTRACT_CHANCE_PER_SECOND * (1.0 - DISTRACT_DISCIPLINE_RELIEF * drilled)
	session._distract_carry += delta
	while session._distract_carry >= 1.0:
		session._distract_carry -= 1.0
		if session.distracted:
			# Left alone it drifts back on its own eventually; a scold is faster
			# and teaches it something.
			session.distracted = not session._rng.chance(0.5)
		else:
			session.distracted = session._rng.chance(drift_chance)

	var rate := _rep_rate(session)
	if session.distracted:
		rate *= DISTRACTED_REP_FRACTION
	session._rep_carry += rate * delta
	while session._rep_carry >= 1.0:
		session._rep_carry -= 1.0
		session.reps += 1
		var best := personal_best(monkey, session.activity)
		if best > 0 and session.reps == best + 1 and session.beat_record_at < 0:
			session.beat_record_at = session.reps

	# Endurance check: an inexperienced monkey trips and sits down. Fitter
	# monkeys never do — the (1 - fitness)^2 curve zeros out at cap.
	var since_join := session.elapsed - session.time_to_join
	if since_join >= TRIP_GRACE_SECONDS:
		session._trip_carry += delta
		while session._trip_carry >= 1.0:
			session._trip_carry -= 1.0
			var stat := stat_for(session.activity)
			var cap := maxi(1, monkey.get_cap(stat))
			var fitness := clampf(float(monkey.get_stat(stat)) / float(cap), 0.0, 1.0)
			var lack := 1.0 - fitness
			var chance := TRIP_CHANCE_PER_SECOND * lack * lack
			if session._rng != null and session._rng.chance(chance):
				session.tripped = true
				session.state = Session.State.ENDED
				return


func _rep_rate(session: Session) -> float:
	var monkey := session.monkey
	var stat := stat_for(session.activity)
	var cap := maxi(1, monkey.get_cap(stat))
	var fitness := clampf(float(monkey.get_stat(stat)) / float(cap), 0.0, 1.0)
	return lerpf(REPS_PER_SECOND_BASE, REPS_PER_SECOND_AT_CAP, fitness)


## Praise. Dossier §4 [C]: "Praise your monkey when they do something good like
## make a record training." Praise for nothing teaches nothing.
func praise_in_session(session: Session) -> bool:
	if session == null or not session.working():
		return false
	var deserved := session.beat_record_at >= 0 and not session.distracted
	session._praises += 1
	if deserved and session._praises <= MAX_REWARDED_PRAISES:
		session._discipline_delta += DISCIPLINE_PER_GOOD_PRAISE
		session._friendship_delta += FRIENDSHIP_PER_GOOD_PRAISE
		return true
	session._discipline_delta += DISCIPLINE_PER_BAD_CALL
	return false


## Scold. Dossier §4 [C]: "You should get angry at your monkey when they are
## chattering around when they are supposed to be training." Scolding a monkey
## that is working costs you friendship, which is exactly the trap.
func scold_in_session(session: Session) -> bool:
	if session == null or not session.working():
		return false
	session._scolds += 1
	if session.distracted:
		session.distracted = false
		session._discipline_delta += DISCIPLINE_PER_GOOD_SCOLD
		return true
	session._discipline_delta += DISCIPLINE_PER_BAD_CALL
	session._friendship_delta += FRIENDSHIP_PER_BAD_SCOLD
	return false


## Close the session and bank it. A monkey that never joined in gets nothing —
## the half-day is spent regardless, which is the cost of a monkey that does not
## trust you yet.
func settle(session: Session) -> Result:
	if session == null:
		return null
	session.state = Session.State.ENDED
	var monkey := session.monkey

	if not session.joined():
		var refused := Result.new()
		refused.activity = session.activity
		refused.stat = stat_for(session.activity)
		refused.message = "%s WATCHED THE DRONE, BUT NEVER JOINED IN." % monkey.monkey_name.to_upper()
		_apply_session_deltas(session, refused)
		session_finished.emit(refused)
		return refused

	# The demonstration's quality carries into the gain: a scrappy demo still
	# convinces the monkey eventually, it just wastes session time doing it.
	var score := RhythmScore.new()
	score.reps = session.reps
	score.perfect = session._good_taps
	score.early = session._early_taps
	score.late = session._late_taps
	score.duration_s = session.elapsed
	var result := perform(monkey, session.activity, score)
	if session.tripped:
		# Trip is a session-ending fatigue event, not a stat penalty — the reps
		# earned still count. The player-facing consequence is a sad message
		# and a small trust hit for pushing an inexperienced monkey too hard.
		session._friendship_delta += TRIP_FRIENDSHIP_COST
		result.message = "%s TRIPPED! IT SITS DOWN AND LOOKS SAD." \
			% monkey.monkey_name.to_upper()
	_apply_session_deltas(session, result)
	return result


func _apply_session_deltas(session: Session, result: Result) -> void:
	var monkey := session.monkey
	if session._discipline_delta != 0:
		monkey.discipline = clampi(
			monkey.discipline + session._discipline_delta, 0, Monkey.DISCIPLINE_MAX)
	if session._friendship_delta != 0:
		monkey.friendship = clampi(
			monkey.friendship + session._friendship_delta, 0, Monkey.FRIENDSHIP_MAX)
		result.friendship_delta += session._friendship_delta
	result.discipline_delta = session._discipline_delta


func perform(monkey: Monkey, activity: Activity, score: RhythmScore) -> Result:
	var result := Result.new()
	result.activity = activity
	result.stat = stat_for(activity)

	if activity == Activity.SHOPPING:
		# Shopping needs an Economy; it has its own entry point.
		result.blocked = true
		result.message = "SHOPPING GOES THROUGH go_shopping()."
		session_finished.emit(result)
		return result

	var blocked := _block_reason(monkey)
	if blocked != "":
		result.blocked = true
		result.message = blocked
		session_finished.emit(result)
		return result

	# Dossier §4 [C] notes the original eventually lets the monkey continue with
	# no input at all, which HG101 flags as a design flaw. This slice keeps input
	# required: no taps, no session.
	if score == null or not score.is_valid():
		result.message = "%s WAITS FOR THE DRONE TO DEMONSTRATE." % monkey.monkey_name
		session_finished.emit(result)
		return result

	result.reps = maxi(0, score.reps)

	# Fullness first, so a session that empties the belly reports the interrupt.
	var cost := TRAINING_FULLNESS_COST
	result.fullness_cost = mini(cost, monkey.fullness)
	monkey.fullness = maxi(0, monkey.fullness - cost)
	result.hunger_interrupt = score.interrupted or monkey.is_starving()

	var multiplier := rhythm_multiplier(score)
	if result.hunger_interrupt and not score.interrupted:
		# The hunger interrupt costs the same as a cut-short session (§4 [C]:
		# the monkey sits down and grabs its stomach mid-set).
		multiplier *= INTERRUPT_MULT

	var base := base_gain(monkey, activity)
	var requested := maxi(0, int(roundf(float(base) * multiplier)))
	result.gain_requested = requested

	var hard_caps := _rules == null or _rules.hard_stat_caps
	if raises_all(activity):
		# SPARRING: all five, smaller each (§4 [C]). Out of slice scope but
		# implemented so the enum is not a lie.
		var applied_total := 0
		for stat in Monkey.STATS:
			var was_capped_before := monkey.is_capped(stat)
			applied_total += _apply_gain(monkey, stat, requested)
			if hard_caps and monkey.is_capped(stat):
				result.was_capped = true
				if not was_capped_before:
					result.starred_out = true
		result.gain_requested = requested * Monkey.STATS.size()
		result.gain_applied = applied_total
	else:
		var stat: Monkey.Stat = result.stat
		var capped_before := monkey.is_capped(stat)
		result.gain_applied = _apply_gain(monkey, stat, requested)
		result.was_capped = (result.gain_applied < result.gain_requested) \
			or (hard_caps and monkey.is_capped(stat))
		result.starred_out = hard_caps and monkey.is_capped(stat) and not capped_before

	result.new_personal_best = _record_reps(monkey, activity, result.reps)
	result.friendship_delta = _session_friendship(monkey, score.accuracy(), result)
	result.message = _session_message(monkey, activity, result)
	session_finished.emit(result)
	return result


## Base gain before rhythm and cap effects, for `activity` on `monkey`.
## [X] dossier §14.10 — no documented curve. See the DIVERGENCE block above.
func base_gain(monkey: Monkey, activity: Activity) -> int:
	if monkey == null:
		return 0
	if raises_all(activity):
		var total := 0.0
		for stat in Monkey.STATS:
			total += float(_stat_gain(monkey, stat))
		return maxi(0, int(roundf(total / float(Monkey.STATS.size()) * SPARRING_FRACTION)))
	return _stat_gain(monkey, stat_for(activity))


## The per-session gain for one stat, before the rhythm multiplier.
func _stat_gain(monkey: Monkey, stat: Monkey.Stat) -> int:
	var cap := monkey.get_cap(stat)
	if cap <= 0:
		return 0
	var current := monkey.get_stat(stat)
	var headroom := clampf(float(cap - current) / float(cap), 0.0, 1.0)
	var taper := GAIN_LATE_FLOOR + (1.0 - GAIN_LATE_FLOOR) * headroom
	var focus := 1.0 + FRIENDSHIP_FOCUS_BONUS \
		* clampf(float(monkey.friendship) / float(Monkey.FRIENDSHIP_MAX), 0.0, 1.0)
	var rate := float(cap) * BASE_GAIN_CAP_FRACTION * taper * focus
	return maxi(MIN_GAIN, int(roundf(rate)))


## Write the gain into the monkey. Honours GameRules.hard_stat_caps: with hard
## caps (this build's default, §3 [C]) the cap clamps; with the flag off the
## stat is written past its ceiling, which Monkey.add_stat would never allow.
func _apply_gain(monkey: Monkey, stat: Monkey.Stat, amount: int) -> int:
	if amount <= 0:
		return 0
	if monkey.get_cap(stat) <= 0:
		return 0
	if _rules != null and not _rules.hard_stat_caps:
		monkey.stats[stat] = monkey.get_stat(stat) + amount
		return amount
	return monkey.add_stat(stat, amount)


## Multiplier applied to base_gain from the minigame performance.
## Two-sided failure: too-early taps (cramp) and too-late taps (lost interest)
## must BOTH reduce it. Dossier §4 [C].
static func rhythm_multiplier(score: RhythmScore) -> float:
	if score == null:
		return 0.0
	var total := score.perfect + score.early + score.late
	if total <= 0:
		# No taps at all is no session — the slice keeps input required (§4).
		return 0.0
	var accuracy := score.accuracy()
	var early_share := float(score.early) / float(total)
	var late_share := float(score.late) / float(total)
	var multiplier := RHYTHM_MIN_MULT + (RHYTHM_MAX_MULT - RHYTHM_MIN_MULT) * accuracy
	multiplier *= 1.0 - CRAMP_WEIGHT * early_share     # the trainer cramps
	multiplier *= 1.0 - BOREDOM_WEIGHT * late_share    # the monkey loses interest
	if score.interrupted:
		multiplier *= INTERRUPT_MULT
	return maxf(RHYTHM_FLOOR, multiplier)


# --- praise, scold and records -----------------------------------------------

## Praise after a personal record or a good shopping trip. Dossier §4 [C].
## Returns the friendship that ACTUALLY landed (0 when already at the ceiling),
## matching Monkey.add_stat's convention. The constant lives in Care so the two
## paths cannot drift apart.
func praise(monkey: Monkey) -> int:
	return _add_friendship(monkey, Care.FRIENDSHIP_PRAISE)


## Scold when it chatters and loses focus. Dossier §4 [C].
func scold(monkey: Monkey) -> int:
	return _add_friendship(monkey, Care.FRIENDSHIP_SCOLD)


func _add_friendship(monkey: Monkey, delta: int) -> int:
	if monkey == null:
		return 0
	var before := monkey.friendship
	monkey.friendship = clampi(before + delta, 0, Monkey.FRIENDSHIP_MAX)
	return monkey.friendship - before


## Personal record (自己最高回数, §4 [C]) — "watching the number climb is
## described by Japanese players as the core appeal", so it is tracked per
## activity and reported on every session.
func _record_reps(monkey: Monkey, activity: Activity, reps: int) -> bool:
	if reps <= 0:
		return false
	var best := int(monkey.personal_bests.get(activity, 0))
	if reps <= best:
		return false
	monkey.personal_bests[activity] = reps
	return true


## Best rep count for an activity, 0 when it has never been done.
func personal_best(monkey: Monkey, activity: Activity) -> int:
	if monkey == null:
		return 0
	return int(monkey.personal_bests.get(activity, 0))


func _session_friendship(monkey: Monkey, accuracy: float, result: Result) -> int:
	# DIVERGENCE: [X]. Praise and scold are the documented explicit inputs (§4
	# [C]); this is only the automatic drift a session causes on its own, kept to
	# one point so the player's own praise/scold stays the bigger lever.
	var delta := 0
	if result.new_personal_best or accuracy >= GOOD_SESSION_ACCURACY:
		delta = 1
	elif accuracy < POOR_SESSION_ACCURACY:
		delta = -1
	if result.hunger_interrupt:
		delta -= 1
	return _add_friendship(monkey, delta)


func _session_message(monkey: Monkey, activity: Activity, result: Result) -> String:
	var who := monkey.monkey_name
	# The interrupt outranks the record: dossier §4 [C] — the monkey stops, sits
	# down and grabs its stomach, and the player has to feed it in place. That is
	# the actionable line. `new_personal_best` is still set for the UI's fanfare.
	if result.hunger_interrupt:
		return "%s SITS DOWN AND HOLDS ITS STOMACH." % who
	if result.new_personal_best:
		return "%s SET A NEW RECORD! %d REPS!" % [who, result.reps]
	if result.starred_out:
		return "%s HAS MAXED OUT %s!" % [who, Monkey.stat_label(result.stat)]
	if result.was_capped and result.gain_applied <= 0:
		return "%s IS ALREADY THE BEST IT CAN BE AT %s." % [who, display_name(activity)]
	if result.gain_applied <= 0:
		return "%s DIDN'T GET THE RHYTHM." % who
	return "%s DID %d REPS OF %s." % [who, result.reps, display_name(activity)]


# --- shopping ----------------------------------------------------------------

## SHOPPING only. `wish_list` maps food id -> requested qty; pass an empty
## dictionary for free-choice shopping. Dossier §4 [C]: the monkey returns with
## only part of the list, Knowledge rises either way, and FREE-CHOICE shopping
## is the only route to new food types and items — at the cost of wasted money.
##
## (The nine special-punch books are also free-choice-only finds [C], but the
## brief cuts special punches from the slice, so nothing here drops one.)
func go_shopping(monkey: Monkey, economy: Economy, wish_list: Dictionary) -> Result:
	var result := Result.new()
	result.activity = Activity.SHOPPING
	result.stat = Monkey.Stat.KNOWLEDGE

	var blocked := _block_reason(monkey)
	if blocked != "":
		result.blocked = true
		result.message = blocked
		session_finished.emit(result)
		return result

	var free_choice := wish_list == null or wish_list.is_empty()
	var budget := 0
	if economy != null:
		budget = maxi(0, economy.money)
	var plan := plan_shopping(monkey, wish_list if wish_list != null else {}, budget)
	var cost := int(plan.get("cost", 0))
	var haul: Dictionary = plan.get("haul", {})
	var junk: Dictionary = plan.get("junk", {})

	if economy != null and cost > 0:
		if economy.spend(cost):
			result.money_spent = cost
			for id in haul:
				economy.add_food(String(id), int(haul[id]))
			for id in junk:
				economy.add_junk(String(id), int(junk[id]))
		else:
			# Could not pay: it comes home with nothing. Knowledge still rises —
			# §4 [C] says Knowledge rises either way.
			haul = {}
			junk = {}
	result.shopping_haul = haul
	result.junk_haul = junk

	var items := 0
	for id in haul:
		items += int(haul[id])
	for id in junk:
		items += int(junk[id])
	result.reps = items

	# Fullness: a walk to the shops, not a workout.
	result.fullness_cost = mini(SHOPPING_FULLNESS_COST, monkey.fullness)
	monkey.fullness = maxi(0, monkey.fullness - SHOPPING_FULLNESS_COST)
	result.hunger_interrupt = monkey.is_starving()

	var multiplier := SHOP_FREE_CHOICE_BONUS if free_choice else 1.0
	if result.hunger_interrupt:
		multiplier *= INTERRUPT_MULT
	var base := base_gain(monkey, Activity.SHOPPING)
	result.gain_requested = int(roundf(float(base) * multiplier))

	var hard_caps := _rules == null or _rules.hard_stat_caps
	var capped_before := monkey.is_capped(Monkey.Stat.KNOWLEDGE)
	result.gain_applied = _apply_gain(monkey, Monkey.Stat.KNOWLEDGE, result.gain_requested)
	result.was_capped = (result.gain_applied < result.gain_requested) \
		or (hard_caps and monkey.is_capped(Monkey.Stat.KNOWLEDGE))
	result.starred_out = hard_caps and monkey.is_capped(Monkey.Stat.KNOWLEDGE) \
		and not capped_before

	result.new_personal_best = _record_reps(monkey, Activity.SHOPPING, result.reps)
	result.friendship_delta = _add_friendship(monkey, 1 if items > 0 else 0)
	result.message = _shopping_message(monkey, result, free_choice)
	session_finished.emit(result)
	return result


## Pure planner for a shopping trip: what the monkey would come home with and
## what it would cost, without touching the Economy. ADDITION to the contract —
## it exists so the trip can be unit-tested deterministically and so go_shopping
## has exactly one place where money is decided.
## Returns {"haul": {food_id: qty}, "junk": {junk_id: qty}, "cost": int}.
func plan_shopping(monkey: Monkey, wish_list: Dictionary, budget: int) -> Dictionary:
	var haul := {}
	var junk := {}
	var cost := 0
	if monkey == null or budget <= 0:
		return {"haul": haul, "junk": junk, "cost": cost}

	var smart := _smartness(monkey)

	if wish_list != null and not wish_list.is_empty():
		# Dictated list. §4 [C]: "It returns with only part of the list."
		var fill := SHOP_MIN_FILL + (SHOP_MAX_FILL - SHOP_MIN_FILL) * smart
		var ids := wish_list.keys()
		ids.sort()   # deterministic order regardless of how the caller built it
		for key in ids:
			var id := String(key)
			var food := FoodDb.get_food(id)
			if food == null:
				continue
			var want := maxi(0, int(wish_list[key]))
			if want <= 0:
				continue
			var got := int(roundf(float(want) * fill))
			if want > 1:
				got = mini(got, want - 1)   # never the whole list
			got = clampi(got, 0, want)
			for _i in got:
				if cost + food.buy_price > budget:
					break
				cost += food.buy_price
				haul[id] = int(haul.get(id, 0)) + 1
		return {"haul": haul, "junk": junk, "cost": cost}

	# Free choice. §4 [C]: the only route to new food types and items, and it
	# wastes money on junk.
	var spendable := int(float(budget) * SHOP_FREE_BUDGET_FRACTION)
	var options := _free_choice_options(monkey)
	if not options.is_empty():
		var picks := _rng.randi_range(FREE_CHOICE_MIN_ITEMS, FREE_CHOICE_MAX_ITEMS) \
			if _rng != null else FREE_CHOICE_MIN_ITEMS
		for _i in picks:
			var food: Food = _rng.pick(options) if _rng != null else options[0]
			if food == null:
				continue
			if cost + food.buy_price > spendable:
				continue
			cost += food.buy_price
			haul[food.id] = int(haul.get(food.id, 0)) + 1

	var junk_chance := JUNK_CHANCE * (1.0 - JUNK_KNOWLEDGE_DISCOUNT * smart)
	for _i in MAX_JUNK_PER_TRIP:
		if _rng == null or not _rng.chance(junk_chance):
			break
		var price := _rng.randi_range(JUNK_COST_MIN, JUNK_COST_MAX)
		if cost + price > spendable:
			break
		var id := String(_rng.pick(Array(JUNK_IDS)))
		cost += price
		junk[id] = int(junk.get(id, 0)) + 1

	return {"haul": haul, "junk": junk, "cost": cost}


## Everything a free-choosing monkey might come home with, liked foods weighted
## double. Species preference is confirmed to be load-bearing (§8 [C]).
func _free_choice_options(monkey: Monkey) -> Array:
	var options := []
	var species := monkey.species()
	for food in FoodDb.all():
		if species != null and species.dislikes(food.id):
			continue
		options.append(food)
		if species != null and species.likes(food.id):
			options.append(food)
	return options


## 0.0 .. 1.0 — how clever this monkey is RELATIVE TO ITS OWN CEILING. Absolute
## Knowledge is meaningless across generations (§3 [C]: gen-1 caps sit near 116,
## late-generation ones near 800), so shopping competence is measured against
## the cap the monkey was born with.
func _smartness(monkey: Monkey) -> float:
	var cap := monkey.get_cap(Monkey.Stat.KNOWLEDGE)
	if cap <= 0:
		return 0.0
	return clampf(float(monkey.get_stat(Monkey.Stat.KNOWLEDGE)) / float(cap), 0.0, 1.0)


func _shopping_message(monkey: Monkey, result: Result, free_choice: bool) -> String:
	var who := monkey.monkey_name
	if result.shopping_haul.is_empty() and result.junk_haul.is_empty():
		return "%s CAME HOME EMPTY-HANDED." % who
	if not result.junk_haul.is_empty():
		return "%s BOUGHT SOME RUBBISH TOO." % who
	if free_choice:
		return "%s CHOSE THE SHOPPING ITSELF!" % who
	return "%s BROUGHT BACK PART OF THE LIST." % who
