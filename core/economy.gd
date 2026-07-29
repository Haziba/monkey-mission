class_name Economy
extends RefCounted

## Money, the food inventory and match purses. Dossier §9.
##
## Income: match purses scaling with opponent rank, plus selling junk the monkey
## brings home. Outgoings: food and dating fees. Sell price is generally 50% of
## buy [C].
##
## RULE CHANGE FOR THIS BUILD: GameRules.bankruptcy_game_over = false.
## The original's ONLY documented fail state is "if food and money are both
## depleted, the game is over" (§9 [C]). Here that condition warns the player
## and grants a bailout instead. Honour the flag: if it is ever set true, the
## same condition must actually end the run — see check_bailout().
##
## [X] Purse amounts per rank are undocumented (§14.13) — the table below is a
## DIVERGENCE.

## DIVERGENCE: starting money is [X]. 1,500 is chosen to buy roughly a week of
## the cheap foods in FoodDb without covering a 1,200 permanent booster.
const STARTING_MONEY := 1500

## The bailout when bankruptcy_game_over is false. DIVERGENCE: no original
## equivalent exists at all — this replaces the game over.
const BAILOUT_AMOUNT := 800

## check_bailout() sentinel: the run is lost. Only ever returned when
## GameRules.bankruptcy_game_over is true, so the branch cannot be buried.
const BAILOUT_GAME_OVER := -1

## The emergency food parcel. DIVERGENCE: no original equivalent — like the
## bailout above, this only exists because GameRules.bankruptcy_game_over is
## false in this build, and money alone cannot save the player here: it is the
## MONKEY that goes shopping (§2 [C]), so a monkey immobilised by hunger cannot
## convert money into food. Bananas because §5 [C] makes them the documented
## befriending food and every species likes them.
const RELIEF_PARCEL := {"banana": 2}

## DIVERGENCE: purse amounts per rank are [X] (dossier §14.13). Only two things
## are confirmed (§7 [C]): a stronger opponent pays more, and Bill books every
## match free of charge so a purse is never negative. The shape below is chosen
## so that the slice's 5→1 ladder pays 800 at the bottom and 4,800 for a
## bottom-ranked monkey upsetting the champion, which sits in the same order of
## magnitude as the `INCOME ¥8000` figure on the dossier's stat card (§10).
const PURSE_BASE := 800
## Added per rank the opponent sits above the bottom of the ladder.
const PURSE_RANK_STEP := 600
## Added per rank the opponent sits above the PLAYER — the upset bonus that
## makes the promotion fight worth taking.
const PURSE_UPSET_BONUS := 400
## DIVERGENCE: a loss still pays. No source says it does, but no source says it
## does not, and with bankruptcy_game_over = false a zero-pay loss would just
## funnel the player into the bailout. 40% of the win purse.
const PURSE_LOSS_RATE := 0.4
## Mirrors Ladder.BOTTOM_RANK for the slice's short 5→1 ladder. Kept local so
## purse_for() stays a pure static with no cross-system dependency.
const PURSE_BOTTOM_RANK := 5

## Sellable junk the monkey brings home from free-choice shopping. Prices are
## verbatim from the dossier §9 table [C]. Ids are snake_case of the guide's
## English names.
const JUNK_PRICES := {
	"garbage": 1,
	"paper": 10,
	"toaster": 10,
	"tissue": 15,
	"shirt": 70,
	"letter": 120,
	"pants": 150,
	"glasses": 200,
	"sweater": 250,
	"book": 300,
	"cd": 400,
	"drain": 1000,
	"tape": 1200,
	"boiler": 1500,
	"chair": 1500,
	"bearclaw": 2500,
	"watch": 3000,
	"software": 4000,
}

signal money_changed(amount: int)
signal inventory_changed(food_id: String, count: int)
signal bailout_granted(amount: int)
signal destitute_warning()
## Emergency food. food id -> count actually delivered.
signal relief_granted(parcel: Dictionary)

var money: int = STARTING_MONEY

## Monkey Mission's name for the same purse (design §5, MISSION-ARCHITECTURE §11).
##
## An ALIAS, deliberately, not a rename. `Ladder`, `Breeding`, `Training.go_shopping`,
## the boxing screens and ~336 lines of green tests all say `money`, and renaming
## the field would break every one of them at once for no behavioural gain. This
## way voyage code can speak the fusion's vocabulary while the mutation is still
## in flight, and the eventual rename is a mechanical sweep with nothing riding
## on it.
##
## Reads and writes the SAME integer — there is no second balance to drift.
var scrap: int:
	get:
		return money
	set(value):
		money = value

## food id -> count. Zero-count entries must be removed, not kept.
var inventory: Dictionary = {}
## Sellable junk id -> count. Dossier §9 lists the junk table; the slice only
## needs it as a money trickle from free-choice shopping.
var junk: Dictionary = {}

var _rules: GameRules


func _init(rules: GameRules) -> void:
	_rules = rules


func can_afford(amount: int) -> bool:
	return money >= amount


## Returns false and changes nothing when the money is not there.
## A negative amount is rejected outright rather than quietly minting money.
func spend(amount: int) -> bool:
	if amount < 0:
		return false
	if amount == 0:
		return true
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true


## Negative or zero earnings are a no-op — losses go through spend().
func earn(amount: int) -> void:
	if amount <= 0:
		return
	money += amount
	money_changed.emit(money)


# --- the voyage vocabulary ---------------------------------------------------
#
# Straight forwards onto the three above, so scrap can never behave differently
# from money by accident. Present so that voyage and combat code never has to say
# "money", which is the word this game no longer uses.

func earn_scrap(amount: int) -> void:
	earn(amount)


func spend_scrap(amount: int) -> bool:
	return spend(amount)


func can_afford_scrap(amount: int) -> bool:
	return can_afford(amount)


func buy_food(food: Food, qty: int = 1) -> bool:
	if food == null or qty <= 0:
		return false
	if not spend(food.buy_price * qty):
		return false
	add_food(food.id, qty)
	return true


## Sell price is generally 50% of buy (dossier §9 [C]); the exact figure per
## food comes from the supergus2 table baked into FoodDb.
func sell_food(food: Food, qty: int = 1) -> bool:
	if food == null or qty <= 0:
		return false
	if food_count(food.id) < qty:
		return false
	_set_food_count(food.id, food_count(food.id) - qty)
	earn(food.sell_price * qty)
	return true


func add_food(food_id: String, qty: int = 1) -> void:
	if food_id == "" or qty <= 0:
		return
	_set_food_count(food_id, food_count(food_id) + qty)


## Remove one unit. Returns false when there is none.
func consume_food(food_id: String) -> bool:
	var have := food_count(food_id)
	if have <= 0:
		return false
	_set_food_count(food_id, have - 1)
	return true


func food_count(food_id: String) -> int:
	return int(inventory.get(food_id, 0))


func total_food() -> int:
	var total := 0
	for count in inventory.values():
		total += int(count)
	return total


func add_junk(junk_id: String, qty: int = 1) -> void:
	if junk_id == "" or qty <= 0:
		return
	junk[junk_id] = junk_count(junk_id) + qty


func junk_count(junk_id: String) -> int:
	return int(junk.get(junk_id, 0))


## Sell junk from the §9 table. Returns the money earned (0 when nothing sold).
## An unknown id is worth nothing, so it is NOT removed — deleting a player's
## item for zero money would be a worse bug than refusing the sale.
func sell_junk(junk_id: String, qty: int = 1) -> int:
	if qty <= 0:
		return 0
	var price := int(JUNK_PRICES.get(junk_id, 0))
	if price <= 0:
		return 0
	var have := junk_count(junk_id)
	if have <= 0:
		return 0
	var sold := mini(qty, have)
	var remaining := have - sold
	if remaining > 0:
		junk[junk_id] = remaining
	else:
		junk.erase(junk_id)
	var takings := price * sold
	earn(takings)
	return takings


## The original's fail condition: no food AND no money (dossier §9 [C]).
func is_destitute() -> bool:
	return money <= 0 and total_food() <= 0


## Called at the top of each day.
##
## Returns 0 when nothing happened.
## Returns BAILOUT_AMOUNT (and grants it) when destitute and
## GameRules.bankruptcy_game_over is false — this build's softened edge.
## Returns BAILOUT_GAME_OVER (-1) when destitute and the flag is TRUE: the
## caller must end the run. The loss is reported upward, never silently paid.
func check_bailout() -> int:
	if not is_destitute():
		return 0
	destitute_warning.emit()
	if _rules != null and _rules.bankruptcy_game_over:
		return BAILOUT_GAME_OVER
	earn(BAILOUT_AMOUNT)
	bailout_granted.emit(BAILOUT_AMOUNT)
	return BAILOUT_AMOUNT


## Put RELIEF_PARCEL in the larder and announce it. Returns what was delivered.
##
## The CALLER decides when this is warranted (GameState checks that the larder
## is empty and that only food can free the monkey) — Economy only knows about
## stock, so putting the condition here would make it guess at the monkey.
func grant_relief_parcel() -> Dictionary:
	var delivered := {}
	for food_id in RELIEF_PARCEL:
		var qty := int(RELIEF_PARCEL[food_id])
		if qty <= 0:
			continue
		add_food(String(food_id), qty)
		delivered[String(food_id)] = qty
	if not delivered.is_empty():
		relief_granted.emit(delivered)
	return delivered


## Purse for fighting an opponent at `opponent_rank` while the player sits at
## `player_rank`. Rank 1 is the top of the ladder, so a LOWER opponent_rank is
## a stronger opponent and a bigger purse (dossier §7 [C]).
## Exact figures are [X] (§14.13) — see the PURSE_* constants above.
static func purse_for(opponent_rank: int, player_rank: int, won: bool) -> int:
	var opponent := maxi(1, opponent_rank)
	var player := maxi(1, player_rank)
	var purse := PURSE_BASE + PURSE_RANK_STEP * maxi(0, PURSE_BOTTOM_RANK - opponent)
	# Positive when the opponent outranks the player (lower number = higher rank).
	var gap := player - opponent
	if gap > 0:
		purse += PURSE_UPSET_BONUS * gap
	if not won:
		purse = int(roundf(float(purse) * PURSE_LOSS_RATE))
	return maxi(0, purse)


func to_dict() -> Dictionary:
	return {
		"money": money,
		"inventory": inventory.duplicate(),
		"junk": junk.duplicate(),
	}


## Restores state without emitting — SaveGame rebuilds the whole run and
## GameState announces it once, rather than firing a change signal per key.
func apply_dict(d: Dictionary) -> void:
	money = int(d.get("money", STARTING_MONEY))
	inventory = _read_counts(d.get("inventory", {}))
	junk = _read_counts(d.get("junk", {}))


# --- internals -------------------------------------------------------------

func _set_food_count(food_id: String, count: int) -> void:
	if count > 0:
		inventory[food_id] = count
	else:
		inventory.erase(food_id)
		count = 0
	inventory_changed.emit(food_id, count)


## JSON turns every number into a float, so counts are coerced back to int and
## non-positive entries are dropped to keep the "no zero entries" invariant.
static func _read_counts(source: Variant) -> Dictionary:
	var out := {}
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for key in (source as Dictionary):
		var count := int((source as Dictionary)[key])
		if count > 0:
			out[String(key)] = count
	return out
