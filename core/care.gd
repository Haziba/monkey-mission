class_name Care
extends RefCounted

## Feeding, fullness, friendship and the obedience check matches use.
## Dossier §5 [C] throughout.
##
## THE TWO FAITHFUL RULES LIVE HERE. Both were requested explicitly by the user
## and must not be softened:
##
##  * GameRules.overfeeding_paralyses — "Overfed, it cannot move until it
##    digests." The monkey is immobilised: it cannot train, spar, shop or fight.
##    This is NOT "wastes food".
##  * GameRules.disobedience_enabled — "An insufficiently bonded monkey may
##    ignore your strategy", at the original's full rate.
##
## Hunger is two-sided and BOTH extremes paralyse. The guides' rule is to feed
## only when the monkey cannot move, never when merely peckish.

enum HungerState {
	STARVING,   ## immobilised by hunger
	HUNGRY,
	CONTENT,
	FULL,
	STUFFED,    ## immobilised until digested
}

enum FeedOutcome {
	ACCEPTED,
	NO_STOCK,             ## not in the inventory
	REFUSED_DISLIKED,     ## eaten, but friendship drops (species dislike)
	CAUSED_PARALYSIS,     ## eaten and pushed the monkey into STUFFED
	BITE,                 ## unbefriended monkey bites instead of eating
}

## DIVERGENCE: friendship numbers are [X] in every source. These are chosen so
## the documented "fastest path: two bananas" (dossier §5 [C]) actually works:
## banana is a liked food for every species, 6 * 2.0 = 12 per feed, two feeds =
## 24, which clears Monkey.FRIENDSHIP_TRAIN_MIN (20).
const FRIENDSHIP_PER_FEED := 6
const FRIENDSHIP_PRAISE := 4
const FRIENDSHIP_SCOLD := -3
## Friendship decays slowly if the monkey is left starving. [X] — chosen.
const FRIENDSHIP_STARVING_PENALTY := -2

## Upper bound of the HUNGRY band; above it the monkey is CONTENT.
## DIVERGENCE: the original exposes hunger only as animation states (the monkey
## sits down and grabs its stomach), never as a number, so every band edge is
## [X]. These split Monkey's 0..30 belly into: 0-3 starving (paralysed), 4-9
## hungry (feed now), 10-20 content, 21-26 full (feeding again is risky),
## 27-30 stuffed (paralysed). That reproduces the guides' rule of feeding only
## when the monkey cannot move.
const FULLNESS_HUNGRY_MAX := 9
## Upper bound of the CONTENT band; above it the monkey is FULL.
const FULLNESS_CONTENT_MAX := 20

## Probability that a monkey with zero friendship still follows the strategy.
## DIVERGENCE: dossier §6 [C] confirms "a monkey with insufficient friendship
## may ignore your instructions", but the curve is [X] — no source gives a rate.
## A floor of 0.25 rising linearly to 1.0 at Monkey.FRIENDSHIP_OBEDIENT (70)
## makes an unbefriended monkey (friendship < 20) miss more than half its
## orders, which matches the guides treating befriending as a prerequisite for
## fighting at all, without making a low-friendship match unwinnable.
const OBEDIENCE_FLOOR := 0.25

## DIVERGENCE: §14.12 — whether Strength/Stamina regenerate overnight on their
## own, or only via food, is [X]. Chosen: they DO trickle back, at a quarter of
## the pool per night, because this build has no injury system and a slice that
## demands a shop trip after every match would spend most of its half-day slots
## on food. §6 [C] is honoured by the worn-out rule below: on the night after a
## match nothing regenerates at all and the monkey needs "a big recovery meal".
const OVERNIGHT_RECOVERY_FRACTION := 0.25


## One feeding. UI reads this to animate and to write the message box.
class FeedResult extends RefCounted:
	var outcome: FeedOutcome = FeedOutcome.ACCEPTED
	var food_id: String = ""
	var fullness_before: int = 0
	var fullness_after: int = 0
	var strength_restored: int = 0
	var stamina_restored: int = 0
	var friendship_delta: int = 0
	## Monkey.Stat -> int actually applied (0 where the stat was already capped;
	## dossier §3 [C]: "permanent-boost foods are wasted on a starred stat").
	var permanent_applied: Dictionary = {}
	## True when a permanent gain was thrown away against a capped stat.
	var permanent_wasted: bool = false
	## Half-day slots the monkey is now immobilised for.
	var paralysed_slots: int = 0
	var message: String = ""


signal fed(result: FeedResult)
signal friendship_changed(value: int)
signal paralysis_started(slots: int)
signal paralysis_ended()

var _rules: GameRules
var _rng: MpRng


func _init(rules: GameRules, rng: MpRng) -> void:
	_rules = rules
	_rng = rng


## Feed one unit of `food` from `economy`'s inventory. Free — costs no half-day
## slot (dossier §2 [C]). Mutates the monkey and the inventory.
##
## `economy` may be null, in which case no stock is checked or consumed — that
## path exists for previews and tests, never for the real feed screen.
func feed(monkey: Monkey, food: Food, economy: Economy) -> FeedResult:
	var result := FeedResult.new()
	if monkey == null or food == null:
		result.outcome = FeedOutcome.NO_STOCK
		result.message = "THERE IS NOTHING TO FEED."
		fed.emit(result)
		return result

	result.food_id = food.id
	result.fullness_before = monkey.fullness
	result.fullness_after = monkey.fullness

	var was_paralysed := is_paralysed(monkey)
	var species := monkey.species()
	var name_text := _display_name(monkey)

	# Stock. One call, so a half-implemented Economy cannot double-consume.
	if economy != null and not economy.consume_food(food.id):
		result.outcome = FeedOutcome.NO_STOCK
		result.message = "YOU HAVE NO %s." % food.display_name.to_upper()
		fed.emit(result)
		return result

	# Dossier §5 [C]: "Until then it is disobedient and will bite you." Modelled
	# as: a monkey that has not been won over will not take food it dislikes at
	# all — it bites and the food is knocked away.
	# DIVERGENCE: whether a bite is a random roll or a reaction to the wrong
	# food is [X]. It is deterministic here so the documented "fastest path: two
	# bananas" stays reliable — a banana is liked by every species, so the
	# intended befriending route is never blocked by a dice roll.
	if not monkey.is_befriended() and species.dislikes(food.id):
		result.outcome = FeedOutcome.BITE
		result.message = "%s BITES YOU! IT WILL NOT TAKE %s FROM A STRANGER." % [
			name_text, food.display_name.to_upper()]
		fed.emit(result)
		return result

	# Fullness. Coffee's -5 is deliberate (dossier §5 [C]) and must survive:
	# feeding it to a stuffed monkey is the documented way to make room.
	result.fullness_after = clampi(monkey.fullness + food.hunger, 0, Monkey.FULLNESS_MAX)
	monkey.fullness = result.fullness_after

	# Pools. Strength IS the health bar (dossier §3 [C]); these heal, they do
	# not raise a stat. Report what actually landed, not the food's number.
	var max_str := monkey.max_strength()
	var str_before := clampi(monkey.current_strength, 0, max_str)
	monkey.current_strength = clampi(str_before + food.strength_restore, 0, max_str)
	result.strength_restored = monkey.current_strength - str_before

	var max_stm := monkey.max_stamina()
	var stm_before := clampi(monkey.current_stamina, 0, max_stm)
	monkey.current_stamina = clampi(stm_before + food.stamina_restore, 0, max_stm)
	result.stamina_restored = monkey.current_stamina - stm_before

	# Permanent boosters. Dossier §3 [C]: wasted on a starred stat.
	for stat_key in food.permanent_gains:
		var stat := int(stat_key)
		var amount := int(food.permanent_gains[stat_key])
		var applied := monkey.add_stat(stat, amount)
		result.permanent_applied[stat] = applied
		if applied < amount:
			result.permanent_wasted = true

	# Friendship. Dossier §5 [C]: "per-type food preferences are real."
	var delta := int(roundf(FRIENDSHIP_PER_FEED * species.friendship_multiplier_for(food.id)))
	result.friendship_delta = add_friendship(monkey, delta)

	var stuffed := monkey.is_stuffed() and _rules.overfeeding_paralyses
	if stuffed:
		# FAITHFUL, requested explicitly: overfeeding immobilises. Not "wastes
		# food" — is_paralysed() below reports it and every activity is gated.
		result.outcome = FeedOutcome.CAUSED_PARALYSIS
		result.paralysed_slots = slots_until_digested(monkey)
		result.message = "%s IS TOO FULL TO MOVE! IT MUST DIGEST." % name_text
	elif species.dislikes(food.id):
		result.outcome = FeedOutcome.REFUSED_DISLIKED
		result.message = "%s CHOKES THE %s DOWN AND SULKS." % [
			name_text, food.display_name.to_upper()]
	else:
		result.outcome = FeedOutcome.ACCEPTED
		result.message = "%s EATS THE %s." % [name_text, food.display_name.to_upper()]

	var now_paralysed := is_paralysed(monkey)
	if now_paralysed and not was_paralysed:
		paralysis_started.emit(result.paralysed_slots)
	elif was_paralysed and not now_paralysed:
		paralysis_ended.emit()

	fed.emit(result)
	return result


func hunger_state(monkey: Monkey) -> HungerState:
	if monkey == null:
		return HungerState.CONTENT
	if monkey.fullness <= Monkey.FULLNESS_STARVING:
		return HungerState.STARVING
	if monkey.fullness >= Monkey.FULLNESS_STUFFED:
		return HungerState.STUFFED
	if monkey.fullness <= FULLNESS_HUNGRY_MAX:
		return HungerState.HUNGRY
	if monkey.fullness <= FULLNESS_CONTENT_MAX:
		return HungerState.CONTENT
	return HungerState.FULL


## True while the monkey cannot act — starving, stuffed, or serving out
## paralysed_slots. Training, sparring, shopping and matches must all check it.
##
## Overfeeding paralysis is carried by `fullness` rather than by a countdown on
## Monkey.paralysed_slots, deliberately: dossier §5 [C] says the monkey "cannot
## move until it digests", and Coffee (Hunger -5) exists "explicitly to make
## room for more food". Feeding Coffee therefore ends the paralysis on the spot,
## which a slot countdown would have blocked. Monkey.paralysed_slots stays as
## the channel for immobility from other sources.
func is_paralysed(monkey: Monkey) -> bool:
	if monkey == null:
		return false
	if monkey.paralysed_slots > 0:
		return true
	if monkey.is_starving():
		return true
	return monkey.is_stuffed() and _rules.overfeeding_paralyses


## True when the monkey will accept instructions at all (befriended, not
## paralysed). The UI uses `block_reason()` for the message box.
func can_act(monkey: Monkey) -> bool:
	if monkey == null:
		return false
	return monkey.is_befriended() and not is_paralysed(monkey)


## Player-facing reason the monkey will not act, or "" when it will.
##
## Ordered so the advice is always correct: the stuffed cases come first
## because feeding is the WRONG move there, and only then the two cases that
## are fixed by food.
func block_reason(monkey: Monkey) -> String:
	if monkey == null:
		return "THERE IS NO MONKEY."
	var name_text := _display_name(monkey)
	if monkey.is_stuffed() and _rules.overfeeding_paralyses:
		return "%s ATE TOO MUCH AND CANNOT MOVE. WAIT FOR IT TO DIGEST." % name_text
	if monkey.paralysed_slots > 0:
		return "%s CANNOT MOVE YET." % name_text
	if monkey.is_starving():
		return "%s IS TOO HUNGRY TO MOVE. FEED IT!" % name_text
	if not monkey.is_befriended():
		return "%s DOES NOT TRUST YOU YET AND BITES. FEED IT!" % name_text
	return ""


## True when the ONLY thing standing between this monkey and acting is FOOD.
##
## Added by the Verification agent to close a dead end. Both hunger extremes
## immobilise (§5 [C]), but they are not symmetrical in what rescues them:
## a stuffed monkey is freed by time (digestion) or by Coffee, whereas a
## starving or unbefriended one can ONLY be freed by feeding it. If the larder
## is empty at that moment there is no move left in the game — the monkey does
## the shopping (§2 [C]) and it cannot move. `GameState` uses this to decide
## when to send the emergency parcel; nothing here softens the paralysis itself.
func needs_food_to_act(monkey: Monkey) -> bool:
	if monkey == null:
		return false
	# Time, not food, is the answer to these two — feeding is the WRONG move.
	if monkey.is_stuffed() and _rules != null and _rules.overfeeding_paralyses:
		return false
	if monkey.paralysed_slots > 0:
		return false
	return monkey.is_starving() or not monkey.is_befriended()


## Half-day slots of digestion still needed before the monkey can move again.
## 0 when it is not stuffed. Informational — the UI shows it, nothing gates on
## it (`is_paralysed` reads fullness directly).
func slots_until_digested(monkey: Monkey) -> int:
	if monkey == null or not monkey.is_stuffed():
		return 0
	var excess := monkey.fullness - (Monkey.FULLNESS_STUFFED - 1)
	return int(ceilf(float(excess) / float(Monkey.DIGEST_PER_SLOT)))


## Burn off fullness and tick down paralysis. Called once per half-day slot.
func digest_tick(monkey: Monkey, slots: int = 1) -> void:
	if monkey == null or slots <= 0:
		return
	var was_paralysed := is_paralysed(monkey)
	monkey.fullness = clampi(monkey.fullness - Monkey.DIGEST_PER_SLOT * slots, 0, Monkey.FULLNESS_MAX)
	monkey.paralysed_slots = maxi(0, monkey.paralysed_slots - slots)
	# Left hungry, the monkey sours on you. Dossier §5 [C] confirms hunger is
	# the pressure that drives feeding; the size of the penalty is [X].
	if monkey.is_starving():
		add_friendship(monkey, FRIENDSHIP_STARVING_PENALTY)
	if was_paralysed and not is_paralysed(monkey):
		paralysis_ended.emit()


## Dossier §4 [C]: praise after a record or a good shopping trip.
## Returns the friendship that ACTUALLY landed after clamping, matching the
## convention of Monkey.add_stat.
func praise(monkey: Monkey) -> int:
	return add_friendship(monkey, FRIENDSHIP_PRAISE)


## Dossier §4 [C]: scold when it chatters and loses focus.
func scold(monkey: Monkey) -> int:
	return add_friendship(monkey, FRIENDSHIP_SCOLD)


## Returns the delta that actually landed (0 at either clamp edge).
func add_friendship(monkey: Monkey, delta: int) -> int:
	if monkey == null or delta == 0:
		return 0
	var before := monkey.friendship
	monkey.friendship = clampi(before + delta, 0, Monkey.FRIENDSHIP_MAX)
	var applied := monkey.friendship - before
	if applied != 0:
		friendship_changed.emit(monkey.friendship)
	return applied


## Probability 0.0..1.0 that the monkey OBEYS the strategy this round.
## Dossier §6 [C]: "A monkey with insufficient friendship may ignore your
## instructions." See OBEDIENCE_FLOOR for the DIVERGENCE on the curve.
## Returns 1.0 when GameRules.disobedience_enabled is false.
func obedience_chance(monkey: Monkey) -> float:
	if monkey == null:
		return 1.0
	if _rules != null and not _rules.disobedience_enabled:
		return 1.0
	return obedience_chance_for(monkey.friendship)


## The raw friendship -> obedience curve, with no GameRules flag applied.
static func obedience_chance_for(friendship: int) -> float:
	var f := clampi(friendship, 0, Monkey.FRIENDSHIP_MAX)
	if f >= Monkey.FRIENDSHIP_OBEDIENT:
		return 1.0
	return OBEDIENCE_FLOOR + (1.0 - OBEDIENCE_FLOOR) * (float(f) / float(Monkey.FRIENDSHIP_OBEDIENT))


## Rolls obedience_chance. MatchResolver calls this once per round.
## Always consumes exactly one RNG draw, including when it is certain to obey,
## so a match replays identically whatever the monkey's friendship is.
func obeys(monkey: Monkey) -> bool:
	if _rng == null:
		return true
	return _rng.chance(obedience_chance(monkey))


## Stateless form of the same roll, for callers that hold a friendship value
## rather than a Monkey. Ignores GameRules — prefer `obeys()` inside the game.
static func obeys_command(friendship: int, rng: MpRng) -> bool:
	if rng == null:
		return true
	return rng.chance(obedience_chance_for(friendship))


## Post-match wear. Dossier §6 [C]: "the monkey is worn out the following day and
## needs a big recovery meal." See OVERNIGHT_RECOVERY_FRACTION for the [X].
##
## This is also the single place `days_since_match` ages — call it once per day,
## from GameState's day rollover, and nowhere else.
func apply_overnight_recovery(monkey: Monkey) -> void:
	if monkey == null:
		return
	var worn_out := monkey.days_since_match <= 0
	if not worn_out:
		var max_str := monkey.max_strength()
		var max_stm := monkey.max_stamina()
		var str_step := int(ceilf(max_str * OVERNIGHT_RECOVERY_FRACTION))
		var stm_step := int(ceilf(max_stm * OVERNIGHT_RECOVERY_FRACTION))
		monkey.current_strength = clampi(monkey.current_strength + str_step, 0, max_str)
		monkey.current_stamina = clampi(monkey.current_stamina + stm_step, 0, max_stm)
	monkey.days_since_match = mini(monkey.days_since_match + 1, 99)


func _display_name(monkey: Monkey) -> String:
	if monkey == null or monkey.monkey_name.is_empty():
		return "THE MONKEY"
	return monkey.monkey_name.to_upper()
