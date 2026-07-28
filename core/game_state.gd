extends Node

## AUTOLOAD: `GameState`. **The only thing the UI is allowed to talk to.**
##
## Deliberately has no `class_name` — a global class would collide with the
## autoload singleton name. Reference it as `GameState` from anywhere.
##
## Layering, non-negotiable:
##   ui/  ->  GameState  ->  core/
## Screens read state from GameState and connect to the signals below. Screens
## must NEVER instantiate Care/Training/MatchResolver/Breeding directly, never
## mutate a Monkey's fields, and never compute a gain, a purse or a rank move.
## Core must never look at a node, a scene or the tree.
##
## THIS CLASS IS ORCHESTRATION ONLY. It owns no game rules: every number comes
## from core. Its two real jobs are (a) routing UI requests into the right core
## system and (b) guaranteeing each signal below fires exactly once, in a sane
## order.
##
## Signal policy, so nothing double-fires:
##  * GameState EMITS the signals that correspond to a method it drives
##    (training_finished, monkey_fed, match_started, bred, ...). The equivalent
##    signals on Training/Care/Breeding are left unconnected on purpose.
##  * GameState CONNECTS only to signals raised deep inside core where it could
##    not otherwise observe the change: Economy money/inventory/bailout, Care
##    friendship/paralysis, DayCycle, Ladder rank, and the live MatchResolver.

## Story-event ids emitted through `story_event`. Screens match on these rather
## than on a bare string literal.
const EVENT_BILL_OFFER := "bill_offer"

# --- lifecycle -------------------------------------------------------------
signal run_started()
signal run_loaded()
signal run_saved()
signal phase_changed(phase: int)               ## RunState.Phase
signal game_over(reason: String)               ## only when bankruptcy_game_over is true

# --- day cycle -------------------------------------------------------------
signal day_advanced(day: int, slot: int)       ## DayCycle.Slot as int
signal day_started(day: int)
signal story_event(event_id: String)           ## doorbell beats (Bill / Fred)

# --- the monkey ------------------------------------------------------------
signal active_monkey_changed(monkey: Monkey)
signal stats_changed(monkey: Monkey)
signal friendship_changed(value: int)
signal fullness_changed(value: int)
signal monkey_fed(result: Care.FeedResult)
signal paralysis_started(slots: int)
signal paralysis_ended()
signal monkey_retired(monkey: Monkey)          ## breeding_destroys_parent = false

# --- training --------------------------------------------------------------
signal training_started(activity: int)
## The monkey stopped watching and started copying. Reps count from here.
signal monkey_joined_in(activity: int)
## It drifted off task, or came back to it. A deserved scold costs it nothing.
signal monkey_focus_changed(distracted: bool)
## It just passed its own best for this exercise — the praise moment (§4 [C]).
signal record_beaten(reps: int)         ## Training.Activity
signal training_finished(result: Training.Result)
signal personal_best(activity: int, reps: int)

# --- economy ---------------------------------------------------------------
signal money_changed(amount: int)
signal inventory_changed(food_id: String, count: int)
signal destitute_warning()
signal bailout_granted(amount: int)
signal relief_granted(parcel: Dictionary)   ## emergency food; see _check_food_relief

# --- ladder and matches ----------------------------------------------------
signal opponents_offered(offers: Array)        ## Array[Ladder.Opponent]
signal opponent_booked(opponent: Ladder.Opponent)
signal match_started(opponent: Ladder.Opponent)
signal match_round_started(round_index: int)
signal match_event(event: MatchResolver.MatchEvent)
signal match_round_finished(result: MatchResolver.RoundResult)
signal match_intermission(round_index: int)
signal match_finished(result: MatchResolver.MatchResult)
signal rank_changed(old_rank: int, new_rank: int)
signal champion_reached()

# --- breeding --------------------------------------------------------------
signal breeding_offers(partners: Array)        ## Array[Breeding.Partner]
signal bred(result: Breeding.BreedResult)

## The live run. Null before new_run()/load_run().
var run: RunState = null

## The match currently in progress, or null. Owned here so the match screen can
## be rebuilt (or backgrounded) without losing the fight.
## The training session in progress, or null. Held here so a screen never has to
## own game state it might be popped away from mid-session.
var current_training: Training.Session = null
var current_match: MatchResolver = null

## Last set of offers handed to the UI, so book_opponent(index) means what the
## player just saw. Cleared once a fight is booked.
var _offers: Array = []
## Last set of dating-shop partners, indexed by preview_partner/breed_with.
var _partners: Array = []
## Cached rules for the pre-run screens (title, settings) where run is null.
var _default_rules: GameRules = null


func rules() -> GameRules:
	if run != null and run.rules != null:
		return run.rules
	if _default_rules == null:
		_default_rules = GameRules.load_default()
	return _default_rules


func has_run() -> bool:
	return run != null


func monkey() -> Monkey:
	return run.active_monkey if run != null else null


# --- lifecycle -------------------------------------------------------------

func new_run(protagonist: int, seed: int = 0) -> void:
	var fresh := RunState.new_run(protagonist as RunState.Protagonist, seed)
	if fresh == null:
		push_error("GameState.new_run: RunState.new_run returned null")
		return
	run = fresh
	current_match = null
	_offers = []
	_partners = []
	_wire_run()
	run_started.emit()
	active_monkey_changed.emit(run.active_monkey)
	_announce_run_state()


func load_run() -> bool:
	var loaded := SaveGame.load_run()
	if loaded == null:
		return false
	run = loaded
	current_match = null
	_offers = []
	_partners = []
	_wire_run()
	run_loaded.emit()
	active_monkey_changed.emit(run.active_monkey)
	_announce_run_state()
	return true


func save_run() -> bool:
	if run == null:
		return false
	if not SaveGame.save(run):
		return false
	run_saved.emit()
	return true


func has_save() -> bool:
	return SaveGame.has_save()


func set_phase(phase: int) -> void:
	if run == null:
		return
	run.phase = phase as RunState.Phase
	phase_changed.emit(phase)


## The monkey-select screen lets the player pick which of the five types Fred
## hands over. `ui/screens/monkey_select.gd` already calls this by name (it
## probes with `has_method` and falls back to a run flag), so it is implemented
## here rather than letting the choice be silently discarded.
##
## The starter is REBUILT, not mutated: a screen must never reach into a Monkey,
## and rebuilding is safe only while the monkey is still untouched. Refused once
## the run has moved past the prologue, so this can never wipe a trained monkey.
func set_starter_species(species_type: int) -> bool:
	if run == null or run.active_monkey == null:
		return false
	var monkey := run.active_monkey
	if monkey.generation != 1 or run.day_cycle.day != 1 \
			or monkey.friendship > 0 or monkey.wins > 0 or monkey.losses > 0:
		push_warning("GameState.set_starter_species: the starter is already in play")
		return false
	if species_type < 0 or species_type >= SpeciesDb.all().size():
		return false
	run.active_monkey = RunState.make_starter(species_type as Species.Type)
	run.set_flag("starter_species", true)
	active_monkey_changed.emit(run.active_monkey)
	stats_changed.emit(run.active_monkey)
	friendship_changed.emit(run.active_monkey.friendship)
	fullness_changed.emit(run.active_monkey.fullness)
	return true


## Core's own wording on whether it is time to breed (dossier §8 records two
## credible schools and settles neither). Exposed so the dating-shop screen can
## stop re-deriving it — flagged as a gap in `ui/screens/breeding_screen.gd`.
func breed_advice() -> String:
	if run == null or run.active_monkey == null:
		return "There is no monkey to pair."
	return run.breeding.breed_advice(run.active_monkey)


## True once every stat is starred — the point at which breeding is the only way
## forward (dossier §3 [C], §7 phase 3 [C]).
func can_breed() -> bool:
	if run == null or run.active_monkey == null:
		return false
	return run.breeding.can_breed(run.active_monkey)


# --- day cycle -------------------------------------------------------------

## Consume the current half-day slot: digestion, paralysis tick, overnight
## recovery, scheduled story events, the destitution check. Every activity that
## costs a slot must funnel through here so nothing double-counts.
##
## Overnight recovery and the destitution check hang off DayCycle.day_started
## (see _on_day_started) so that they land BEFORE the UI is told a new day
## began, whichever code path rolled the clock over.
func consume_slot() -> void:
	if run == null:
		return
	if run.active_monkey != null:
		run.care.digest_tick(run.active_monkey, 1)
		fullness_changed.emit(run.active_monkey.fullness)
	run.day_cycle.advance_slot()


## Spend a half-day slot doing nothing but waiting on the monkey.
##
## DIVERGENCE: [X]. Dossier §2 [C] says every ACTIVITY costs one half-day slot
## and that feeding is free, but no source records how the clock moves while the
## monkey is immobilised — and BOTH hunger extremes immobilise it (§5 [C]).
## Without this, the two faithful paralysis states are a dead end rather than a
## cost: a stuffed monkey refuses every slot-consuming action, so nothing ever
## calls digest_tick and it never digests; a starving monkey with an empty larder
## refuses them too, so `Economy.check_bailout()` (which only runs at the top of
## a day) can never fire and `bankruptcy_game_over = false` never gets to bail
## the player out. Resting is deliberately the WORST use of a slot — it trains
## nothing and earns nothing — so overfeeding still genuinely costs the player
## half a day, which is the faithful behaviour, not a softened one.
func rest() -> bool:
	if run == null:
		return false
	consume_slot()
	return true


func day() -> int:
	return run.day_cycle.day if run != null else 0


func slot() -> int:
	return int(run.day_cycle.slot) if run != null else 0


# --- care ------------------------------------------------------------------

## Free — costs no slot (dossier §2 [C]).
func feed(food_id: String) -> Care.FeedResult:
	if run == null or run.active_monkey == null:
		return null
	var food := FoodDb.get_food(food_id)
	if food == null:
		push_warning("GameState.feed: unknown food id \"%s\"" % food_id)
		return null
	var result := run.care.feed(run.active_monkey, food, run.economy)
	fullness_changed.emit(run.active_monkey.fullness)
	stats_changed.emit(run.active_monkey)
	monkey_fed.emit(result)
	return result


func praise() -> void:
	if run == null or run.active_monkey == null:
		return
	run.care.praise(run.active_monkey)


func scold() -> void:
	if run == null or run.active_monkey == null:
		return
	run.care.scold(run.active_monkey)


## "" when the monkey will act; otherwise the reason to show the player.
func block_reason() -> String:
	if run == null or run.active_monkey == null:
		return "No monkey."
	return run.care.block_reason(run.active_monkey)


# --- training --------------------------------------------------------------

func can_train() -> bool:
	if run == null or run.active_monkey == null:
		return false
	return run.training.can_train(run.active_monkey)


## Runs the session AND consumes the half-day slot.
## Open a training session: you demonstrate, the monkey watches, and it joins in
## when it is convinced (dossier §4 [C]). Returns null when it will not work at
## all. The half-day is NOT spent here — it is spent by `settle_training()`, so
## a session that cannot even start costs the player nothing.
func begin_training(activity: int) -> Training.Session:
	if run == null or run.active_monkey == null:
		return null
	if activity == Training.Activity.SHOPPING:
		return null
	if not can_train():
		return null
	current_training = run.training.begin_session(
		run.active_monkey, activity as Training.Activity)
	if current_training != null and current_training.finished():
		current_training = null
		return null
	training_started.emit(activity)
	return current_training


## One tap of the trainer's own exercise. Only counts while demonstrating.
func training_tap(interval: float) -> Training.TapVerdict:
	if current_training == null:
		return Training.TapVerdict.LATE_BORED
	var was_watching := not current_training.joined()
	var verdict := run.training.register_tap(current_training, interval)
	if was_watching and current_training.joined():
		monkey_joined_in.emit(current_training.activity)
	return verdict


func training_tick(delta: float) -> void:
	if current_training == null:
		return
	var distracted_before := current_training.distracted
	var reps_before := current_training.reps
	run.training.tick(current_training, delta)
	if current_training.distracted != distracted_before:
		monkey_focus_changed.emit(current_training.distracted)
	if current_training.beat_record_at >= 0 and reps_before < current_training.beat_record_at:
		record_beaten.emit(current_training.reps)


func training_praise() -> bool:
	if current_training == null:
		return false
	return run.training.praise_in_session(current_training)


func training_scold() -> bool:
	if current_training == null:
		return false
	return run.training.scold_in_session(current_training)


## Close the session and spend the half-day. A monkey that never joined in banks
## nothing, but the slot is gone either way — that is the cost of a monkey that
## does not trust you yet.
func settle_training() -> Training.Result:
	if current_training == null:
		return null
	var result := run.training.settle(current_training)
	current_training = null
	consume_slot()
	_report_session(result)
	return result


func do_training(activity: int, score: RhythmScore) -> Training.Result:
	if run == null or run.active_monkey == null:
		return null
	if activity == Training.Activity.SHOPPING:
		return do_shopping({})
	if not can_train():
		return null
	training_started.emit(activity)
	var result := run.training.perform(run.active_monkey, activity as Training.Activity, score)
	consume_slot()
	_report_session(result)
	return result


## Runs the shopping trip AND consumes the half-day slot. Empty wish list means
## free-choice shopping (dossier §4 [C]: the only route to new food types).
func do_shopping(wish_list: Dictionary) -> Training.Result:
	if run == null or run.active_monkey == null:
		return null
	if not can_train():
		return null
	training_started.emit(Training.Activity.SHOPPING)
	var result := run.training.go_shopping(run.active_monkey, run.economy, wish_list)
	consume_slot()
	_report_session(result)
	return result


# --- economy ---------------------------------------------------------------

func money() -> int:
	return run.economy.money if run != null else 0


func inventory() -> Dictionary:
	return run.economy.inventory.duplicate() if run != null else {}


func buy_food(food_id: String, qty: int = 1) -> bool:
	if run == null:
		return false
	var food := FoodDb.get_food(food_id)
	if food == null:
		return false
	return run.economy.buy_food(food, qty)


func sell_food(food_id: String, qty: int = 1) -> bool:
	if run == null:
		return false
	var food := FoodDb.get_food(food_id)
	if food == null:
		return false
	return run.economy.sell_food(food, qty)


# --- ladder and matches ----------------------------------------------------

func rank() -> int:
	return run.ladder.rank if run != null else 0


## Bill's three candidates, at least one ranked above the player.
func offered_opponents() -> Array:
	if run == null or run.active_monkey == null:
		return []
	_offers = run.ladder.offer_opponents(run.active_monkey, run.day_cycle.day)
	opponents_offered.emit(_offers)
	return _offers


## Accept one of the offers; the fight happens tomorrow (dossier §7 [C]).
func book_opponent(index: int) -> void:
	if run == null:
		return
	if _offers.is_empty():
		offered_opponents()
	if index < 0 or index >= _offers.size():
		push_warning("GameState.book_opponent: index %d out of range" % index)
		return
	run.booked_opponent = _offers[index]
	_offers = []
	set_phase(RunState.Phase.MATCH_DAY)
	opponent_booked.emit(run.booked_opponent)


## True when the booked fight can actually be answered. Dossier §5 [C]: both
## hunger extremes immobilise the monkey — "underfed, the monkey is immobilised
## by hunger; overfed, it cannot move until it digests" — and an unbefriended
## monkey obeys nothing at all. A monkey that cannot train cannot box either, so
## the same gate Training uses guards the ring. GameRules.overfeeding_paralyses
## is FAITHFUL at the user's explicit request; it is not "wastes food", so it has
## to bite here too.
func can_fight() -> bool:
	if run == null or run.active_monkey == null:
		return false
	return run.care.can_act(run.active_monkey)


## Create `current_match` and emit match_started. Consumes the half-day slot.
## Returns null when the monkey cannot answer the bell — read `block_reason()`.
func start_match() -> MatchResolver:
	if run == null or run.active_monkey == null or run.booked_opponent == null:
		return null
	if not can_fight():
		return null
	var opponent: Ladder.Opponent = run.booked_opponent
	var resolver := MatchResolver.new(rules(), run.rng, run.care)
	resolver.round_started.connect(func(index: int) -> void: match_round_started.emit(index))
	resolver.event_logged.connect(func(event: MatchResolver.MatchEvent) -> void: match_event.emit(event))
	resolver.round_finished.connect(
		func(result: MatchResolver.RoundResult) -> void: match_round_finished.emit(result))
	resolver.intermission_started.connect(func(index: int) -> void: match_intermission.emit(index))
	resolver.match_finished.connect(
		func(result: MatchResolver.MatchResult) -> void: match_finished.emit(result))
	resolver.begin(run.active_monkey, opponent.monkey, opponent.rank)
	current_match = resolver
	consume_slot()
	match_started.emit(opponent)
	return resolver


func set_strategy(strategy: int) -> void:
	if current_match == null:
		return
	current_match.set_strategy(strategy as MatchResolver.Strategy)


func corner_action(action: int, item_id: String = "") -> void:
	if current_match == null:
		return
	current_match.apply_corner_action(action as MatchResolver.CornerAction, item_id)


## Forwarded from the match screen while a round is live.
func tap_encourage() -> void:
	if current_match == null:
		return
	if rules().fight_interactivity == GameRules.FightInteractivity.NONE:
		return
	current_match.register_tap()


## Applies the purse and the rank move, clears current_match.
##
## This is the ONLY place a match touches the economy or the ladder — the
## resolver simulates, GameState settles up.
func finish_match(result: MatchResolver.MatchResult) -> void:
	if run == null or result == null:
		return
	var opponent_rank := result.opponent_rank
	if opponent_rank <= 0 and run.booked_opponent != null:
		opponent_rank = run.booked_opponent.rank
		result.opponent_rank = opponent_rank
	var player_rank := run.ladder.rank

	result.rank_delta = run.ladder.apply_result(result.outcome, opponent_rank)
	result.purse = Economy.purse_for(opponent_rank, player_rank, result.player_won)
	run.economy.earn(result.purse)

	var m := run.active_monkey
	if m != null:
		if result.player_won:
			m.wins += 1
		else:
			m.losses += 1
		m.days_since_match = 0
		stats_changed.emit(m)

	run.booked_opponent = null
	current_match = null
	set_phase(RunState.Phase.CHAMPION if run.ladder.is_champion() else RunState.Phase.LADDER)
	_autosave()


# --- breeding --------------------------------------------------------------

func breeding_partners() -> Array:
	if run == null or run.active_monkey == null:
		return []
	_partners = run.breeding.partners_for(run.active_monkey, run.day_cycle.day)
	breeding_offers.emit(_partners)
	return _partners


func preview_partner(index: int) -> Breeding.Preview:
	if run == null or run.active_monkey == null:
		return null
	if _partners.is_empty():
		breeding_partners()
	if index < 0 or index >= _partners.size():
		return null
	return run.breeding.preview(run.active_monkey, _partners[index])


## Breeds, retires the parent into the roster (breeding_destroys_parent = false)
## and swaps the active monkey for the baby.
func breed_with(index: int, baby_name: String) -> Breeding.BreedResult:
	if run == null or run.active_monkey == null:
		return null
	if _partners.is_empty():
		breeding_partners()
	if index < 0 or index >= _partners.size():
		return null
	var parent := run.active_monkey
	var result := run.breeding.breed(parent, _partners[index], baby_name, run.economy)
	if result == null or result.baby == null:
		return result
	# The flag lives in GameRules and Breeding decides; GameState only files the
	# parent where the flag says it belongs.
	if result.parent_retired and not result.parent_destroyed:
		if not run.roster.has(parent):
			run.roster.append(parent)
		monkey_retired.emit(parent)
	run.active_monkey = result.baby
	# Dossier §2 [C] core loop: after breeding you "re-climb the ladder from the
	# bottom", and §7 phase 3 [C] calls that sawtooth the game's defining
	# structural decision. `Breeding._breed_message()` already tells the player
	# the baby "must re-enter the ladder at the bottom" — this is what makes that
	# sentence true. Any fight Bill had booked belongs to the retired parent.
	run.ladder.reset_to_bottom()
	run.booked_opponent = null
	_offers = []
	_partners = []
	# Back on the ladder from the bottom, whatever the parent had reached — a
	# booked MATCH_DAY or a CHAMPION flag would both be the retired monkey's.
	set_phase(RunState.Phase.LADDER)
	active_monkey_changed.emit(result.baby)
	stats_changed.emit(result.baby)
	friendship_changed.emit(result.baby.friendship)
	fullness_changed.emit(result.baby.fullness)
	bred.emit(result)
	# A new generation is the least recoverable step in the game; commit it.
	_autosave()
	return result


func roster() -> Array:
	return run.roster.duplicate() if run != null else []


# --- internals -------------------------------------------------------------

func _wire_run() -> void:
	if run == null:
		return
	run.economy.money_changed.connect(func(amount: int) -> void: money_changed.emit(amount))
	run.economy.inventory_changed.connect(
		func(food_id: String, count: int) -> void: inventory_changed.emit(food_id, count))
	run.economy.destitute_warning.connect(func() -> void: destitute_warning.emit())
	run.economy.bailout_granted.connect(func(amount: int) -> void: bailout_granted.emit(amount))
	run.economy.relief_granted.connect(func(parcel: Dictionary) -> void: relief_granted.emit(parcel))

	run.care.friendship_changed.connect(func(value: int) -> void: friendship_changed.emit(value))
	run.care.paralysis_started.connect(func(slots: int) -> void: paralysis_started.emit(slots))
	run.care.paralysis_ended.connect(func() -> void: paralysis_ended.emit())

	run.day_cycle.slot_advanced.connect(_on_slot_advanced)
	run.day_cycle.day_started.connect(_on_day_started)
	run.day_cycle.event_due.connect(_on_event_due)

	run.ladder.rank_changed.connect(func(old_rank: int, new_rank: int) -> void:
		rank_changed.emit(old_rank, new_rank))
	run.ladder.champion_reached.connect(func() -> void: champion_reached.emit())


## Bring the UI up to date after a run is created or loaded.
func _announce_run_state() -> void:
	if run == null:
		return
	phase_changed.emit(int(run.phase))
	money_changed.emit(run.economy.money)
	day_advanced.emit(run.day_cycle.day, int(run.day_cycle.slot))
	if run.active_monkey != null:
		stats_changed.emit(run.active_monkey)
		friendship_changed.emit(run.active_monkey.friendship)
		fullness_changed.emit(run.active_monkey.fullness)


func _on_slot_advanced(p_day: int, p_slot: int) -> void:
	day_advanced.emit(p_day, int(p_slot))


## Start-of-day upkeep. Runs before the UI hears about the new day.
func _on_day_started(p_day: int) -> void:
	if run != null:
		if run.active_monkey != null:
			run.care.apply_overnight_recovery(run.active_monkey)
			stats_changed.emit(run.active_monkey)
		var bailout := run.economy.check_bailout()
		if bailout == Economy.BAILOUT_GAME_OVER:
			# Only reachable with GameRules.bankruptcy_game_over = true. This
			# build ships that flag false, so the player gets the bailout above
			# instead — but the losing branch stays wired, not buried.
			game_over.emit("Out of food and money.")
		# STRICTLY AFTER the bailout: the parcel puts food in the larder, which
		# would otherwise clear `Economy.is_destitute()` before the check that
		# owns the documented fail state (§9 [C]) ever got to see it.
		_check_food_relief()
		# Dossier §7 phase 2 [C]: "Bill rings the doorbell and asks you to pick
		# tomorrow's opponent from three candidates." Ladder owns the cadence
		# (the 4-day reading of the §14 contradiction); this only announces it.
		if run.booked_opponent == null and Ladder.is_offer_day(p_day):
			story_event.emit(EVENT_BILL_OFFER)
	day_started.emit(p_day)
	# A day boundary is the natural commit point: one continuous save, and the
	# player never loses more than the half-day they are standing in.
	_autosave()


## Emergency food, checked at the top of each day alongside the bailout.
##
## Added by the Verification agent to close the second half of the paralysis
## dead end. REST moves the clock, which frees a STUFFED monkey by digestion —
## but a STARVING or unbefriended one can only be freed by feeding it, and it is
## the MONKEY that goes shopping (§2 [C]), so with an empty larder no amount of
## money and no amount of resting can reach food. `Economy.check_bailout()` does
## not cover it either: its condition is money AND food both gone (§9 [C]), so a
## player with cash and an empty larder was simply stuck for ever.
##
## DIVERGENCE: no original equivalent. It exists only because
## GameRules.bankruptcy_game_over is false in this build, which promises that
## running dry is survivable. Deliberately the smallest parcel that unblocks the
## monkey, and only when there is genuinely nothing else left to try.
func _check_food_relief() -> void:
	if run == null or run.active_monkey == null:
		return
	if run.economy.total_food() > 0:
		return
	if not run.care.needs_food_to_act(run.active_monkey):
		return
	run.economy.grant_relief_parcel()


## Best-effort save. Never blocks or reports upward — a failed autosave must not
## interrupt play, and the player can still save explicitly from the title.
func _autosave() -> void:
	if run == null:
		return
	if not SaveGame.save(run):
		push_warning("GameState: autosave failed")


func _on_event_due(event_id: String, _p_day: int, _p_slot: int) -> void:
	story_event.emit(event_id)


func _report_session(result: Training.Result) -> void:
	if result == null:
		return
	if run != null and run.active_monkey != null:
		stats_changed.emit(run.active_monkey)
		fullness_changed.emit(run.active_monkey.fullness)
	if result.new_personal_best:
		personal_best.emit(int(result.activity), result.reps)
	training_finished.emit(result)
