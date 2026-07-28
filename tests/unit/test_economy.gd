extends TestCase

## core/economy.gd — money, the food inventory, junk and match purses.
## Dossier §9: income is purses (scaling with opponent rank) plus junk sales;
## sell price is generally 50% of buy; "if food and money are both depleted, the
## game is over" is the original's only fail state, softened here to a bailout.

var rules: GameRules
var economy: Economy

var money_events: Array[int] = []
var inventory_events: Array = []
var bailout_events: Array[int] = []
var warning_count: int = 0


func before_each() -> void:
	rules = GameRules.new()
	economy = Economy.new(rules)
	money_events = []
	inventory_events = []
	bailout_events = []
	warning_count = 0
	economy.money_changed.connect(func(amount: int) -> void: money_events.append(amount))
	economy.inventory_changed.connect(
		func(food_id: String, count: int) -> void: inventory_events.append([food_id, count]))
	economy.bailout_granted.connect(func(amount: int) -> void: bailout_events.append(amount))
	economy.destitute_warning.connect(func() -> void: warning_count += 1)


# --- money -----------------------------------------------------------------

func test_starts_with_the_documented_purse_and_no_stock() -> void:
	assert_eq(economy.money, Economy.STARTING_MONEY)
	assert_eq(economy.inventory, {})
	assert_eq(economy.total_food(), 0)


func test_can_afford_is_inclusive_at_the_exact_price() -> void:
	economy.money = 100
	assert_true(economy.can_afford(100), "exactly enough is enough")
	assert_true(economy.can_afford(99))
	assert_false(economy.can_afford(101))
	assert_true(economy.can_afford(0))


func test_spend_takes_the_money_and_announces_it() -> void:
	assert_true(economy.spend(500))
	assert_eq(economy.money, Economy.STARTING_MONEY - 500)
	assert_eq(money_events, [Economy.STARTING_MONEY - 500])


func test_spend_more_than_you_have_changes_nothing() -> void:
	assert_false(economy.spend(Economy.STARTING_MONEY + 1))
	assert_eq(economy.money, Economy.STARTING_MONEY)
	assert_eq(money_events.size(), 0, "a refused spend must not emit money_changed")


func test_spend_to_exactly_zero_is_allowed() -> void:
	assert_true(economy.spend(Economy.STARTING_MONEY))
	assert_eq(economy.money, 0)


func test_spending_zero_or_a_negative_amount_never_mints_money() -> void:
	assert_true(economy.spend(0), "spending nothing trivially succeeds")
	assert_eq(economy.money, Economy.STARTING_MONEY)
	assert_false(economy.spend(-500), "a negative spend is rejected, not a windfall")
	assert_eq(economy.money, Economy.STARTING_MONEY)
	assert_eq(money_events.size(), 0)


func test_earn_ignores_zero_and_negative_amounts() -> void:
	economy.earn(0)
	economy.earn(-250)
	assert_eq(economy.money, Economy.STARTING_MONEY)
	assert_eq(money_events.size(), 0)
	economy.earn(250)
	assert_eq(economy.money, Economy.STARTING_MONEY + 250)


# --- food inventory --------------------------------------------------------

func test_buying_food_deducts_the_buy_price_and_stocks_it() -> void:
	var banana := FoodDb.get_food("banana")
	assert_true(economy.buy_food(banana, 3))
	assert_eq(economy.money, Economy.STARTING_MONEY - banana.buy_price * 3)
	assert_eq(economy.food_count("banana"), 3)
	assert_eq(economy.total_food(), 3)


func test_buying_what_you_cannot_afford_changes_nothing() -> void:
	var eel := FoodDb.get_food("eel")     # 1,200 — two do not fit in 1,500
	assert_false(economy.buy_food(eel, 2))
	assert_eq(economy.money, Economy.STARTING_MONEY)
	assert_eq(economy.food_count("eel"), 0)
	assert_eq(inventory_events.size(), 0)


func test_buying_rejects_a_null_food_and_a_non_positive_quantity() -> void:
	assert_false(economy.buy_food(null, 1))
	assert_false(economy.buy_food(FoodDb.get_food("banana"), 0))
	assert_false(economy.buy_food(FoodDb.get_food("banana"), -2))
	assert_eq(economy.money, Economy.STARTING_MONEY)


func test_selling_pays_the_fifty_percent_rate_from_the_food_table() -> void:
	var banana := FoodDb.get_food("banana")
	assert_eq(banana.sell_price, banana.buy_price / 2, "dossier §9 [C]: sell is 50% of buy")
	economy.add_food("banana", 2)
	economy.money = 0
	assert_true(economy.sell_food(banana, 2))
	assert_eq(economy.money, banana.sell_price * 2)
	assert_eq(economy.food_count("banana"), 0)


func test_selling_more_than_you_hold_changes_nothing() -> void:
	var banana := FoodDb.get_food("banana")
	economy.add_food("banana", 1)
	economy.money = 0
	assert_false(economy.sell_food(banana, 2))
	assert_eq(economy.money, 0)
	assert_eq(economy.food_count("banana"), 1)


func test_selling_from_an_empty_inventory_is_refused() -> void:
	assert_false(economy.sell_food(FoodDb.get_food("curry"), 1))
	assert_eq(economy.total_food(), 0)


func test_consuming_the_last_unit_removes_the_entry_entirely() -> void:
	economy.add_food("corn", 1)
	assert_true(economy.consume_food("corn"))
	assert_eq(economy.food_count("corn"), 0)
	assert_not_has(economy.inventory, "corn", "zero entries must be removed, not kept at 0")
	assert_false(economy.consume_food("corn"), "consuming from nothing fails")


func test_inventory_changed_reports_the_new_count_including_zero() -> void:
	economy.add_food("banana", 2)
	economy.consume_food("banana")
	economy.consume_food("banana")
	assert_eq(inventory_events, [["banana", 2], ["banana", 1], ["banana", 0]])


func test_add_food_ignores_empty_ids_and_non_positive_quantities() -> void:
	economy.add_food("", 5)
	economy.add_food("banana", 0)
	economy.add_food("banana", -3)
	assert_eq(economy.inventory, {})
	assert_eq(inventory_events.size(), 0)


func test_total_food_sums_every_stack() -> void:
	economy.add_food("banana", 4)
	economy.add_food("biscuit", 2)
	economy.add_food("corn", 2)
	assert_eq(economy.total_food(), 8, "matches FoodDb.starting_inventory()")


# --- junk ------------------------------------------------------------------

func test_junk_sells_at_the_dossier_price() -> void:
	economy.money = 0
	economy.add_junk("watch", 2)
	assert_eq(economy.sell_junk("watch", 2), 6000, "Watch is 3,000 in dossier §9")
	assert_eq(economy.money, 6000)
	assert_eq(economy.junk_count("watch"), 0)


func test_selling_more_junk_than_you_hold_sells_what_there_is() -> void:
	economy.money = 0
	economy.add_junk("paper", 1)
	assert_eq(economy.sell_junk("paper", 9), 10)
	assert_eq(economy.junk_count("paper"), 0)


func test_unknown_junk_is_never_silently_destroyed() -> void:
	economy.add_junk("moon_rock", 1)
	assert_eq(economy.sell_junk("moon_rock", 1), 0)
	assert_eq(economy.junk_count("moon_rock"), 1, "refuse the sale rather than delete it for 0")


func test_selling_junk_you_do_not_have_pays_nothing() -> void:
	assert_eq(economy.sell_junk("watch", 1), 0)
	assert_eq(economy.sell_junk("watch", 0), 0)
	assert_eq(economy.money, Economy.STARTING_MONEY)


# --- destitution and the bailout -------------------------------------------

func test_destitute_needs_both_no_food_and_no_money() -> void:
	economy.money = 0
	assert_true(economy.is_destitute())
	economy.add_food("biscuit", 1)
	assert_false(economy.is_destitute(), "food alone keeps you solvent")
	economy.consume_food("biscuit")
	economy.money = 1
	assert_false(economy.is_destitute(), "money alone keeps you solvent")


func test_check_bailout_does_nothing_while_solvent() -> void:
	assert_eq(economy.check_bailout(), 0)
	assert_eq(warning_count, 0)
	assert_eq(bailout_events.size(), 0)


func test_check_bailout_warns_then_pays_when_the_run_is_softened() -> void:
	assert_false(rules.bankruptcy_game_over, "this build ships the softened edge")
	economy.money = 0
	var granted := economy.check_bailout()
	assert_eq(granted, Economy.BAILOUT_AMOUNT)
	assert_eq(warning_count, 1, "the player is warned before being bailed out")
	assert_eq(bailout_events, [Economy.BAILOUT_AMOUNT])
	assert_eq(economy.money, Economy.BAILOUT_AMOUNT)
	assert_false(economy.is_destitute())


func test_the_relief_parcel_puts_real_food_in_the_larder() -> void:
	# The bailout pays MONEY, but money is not food: it is the monkey that goes
	# shopping (dossier §2 [C]), so a monkey too hungry to move cannot spend it.
	var relief_events: Array = []
	economy.relief_granted.connect(func(parcel: Dictionary) -> void: relief_events.append(parcel))
	assert_eq(economy.total_food(), 0)
	var delivered := economy.grant_relief_parcel()
	assert_false(delivered.is_empty(), "the parcel must contain something")
	assert_eq(delivered, Economy.RELIEF_PARCEL)
	assert_eq(relief_events, [delivered], "relief_granted fires once with what landed")
	for food_id in Economy.RELIEF_PARCEL:
		assert_eq(economy.food_count(String(food_id)), int(Economy.RELIEF_PARCEL[food_id]))
	assert_true(economy.total_food() > 0)


func test_the_relief_parcel_is_food_the_monkey_will_actually_take() -> void:
	# Dossier §5 [C]: every species likes bananas and none dislikes them, which
	# is why they are the documented befriending food. A parcel of something a
	# species dislikes could be BITTEN away by an unbefriended monkey (Care.feed)
	# and would not rescue the run at all.
	for food_id in Economy.RELIEF_PARCEL:
		var food := FoodDb.get_food(String(food_id))
		assert_not_null(food, "the parcel must ship a food that exists: %s" % food_id)
		assert_true(food.hunger > 0, "it has to actually fill the monkey up")
		for species in SpeciesDb.all():
			assert_false(species.dislikes(String(food_id)),
				"%s must not refuse the emergency parcel" % species.display_name)


func test_check_bailout_reports_the_loss_when_the_faithful_flag_is_flipped() -> void:
	rules.bankruptcy_game_over = true
	economy.money = 0
	var outcome := economy.check_bailout()
	assert_eq(outcome, Economy.BAILOUT_GAME_OVER, "the loss is reported upward, not buried")
	assert_eq(warning_count, 1)
	assert_eq(bailout_events.size(), 0, "no silent bailout when the fail state is live")
	assert_eq(economy.money, 0)


# --- purses ----------------------------------------------------------------

func test_a_stronger_opponent_always_pays_more() -> void:
	# Rank 1 is the top of the ladder, so a LOWER rank number is stronger.
	var previous := -1
	for opponent_rank in [5, 4, 3, 2, 1]:
		var purse := Economy.purse_for(opponent_rank, 5, true)
		assert_true(purse > previous, "rank %d must pay more than the rank below" % opponent_rank)
		previous = purse


func test_beating_someone_above_you_pays_an_upset_bonus() -> void:
	var upset := Economy.purse_for(3, 5, true)      # opponent two ranks above
	var level := Economy.purse_for(3, 3, true)      # same rank
	var beneath := Economy.purse_for(3, 1, true)    # opponent below the player
	assert_true(upset > level, "the promotion fight is worth taking")
	assert_eq(level, beneath, "no penalty for punching down — it simply pays the base")


func test_a_loss_still_pays_but_pays_less() -> void:
	var win := Economy.purse_for(1, 5, true)
	var loss := Economy.purse_for(1, 5, false)
	assert_true(loss < win)
	assert_true(loss > 0, "Bill books matches free of charge; a loss is never a debt")
	assert_eq(loss, int(roundf(float(win) * Economy.PURSE_LOSS_RATE)))


func test_purses_are_never_negative_and_survive_nonsense_ranks() -> void:
	assert_true(Economy.purse_for(0, 0, true) > 0)
	assert_true(Economy.purse_for(-5, -5, false) >= 0)
	assert_eq(Economy.purse_for(0, 5, true), Economy.purse_for(1, 5, true),
		"rank 0 clamps to the top rank")


# --- serialisation ---------------------------------------------------------

func test_to_dict_round_trips_through_apply_dict() -> void:
	economy.money = 987
	economy.add_food("banana", 3)
	economy.add_food("curry", 1)
	economy.add_junk("book", 2)
	var snapshot := economy.to_dict()

	var restored := Economy.new(rules)
	restored.apply_dict(snapshot)
	assert_eq(restored.money, 987)
	assert_eq(restored.food_count("banana"), 3)
	assert_eq(restored.food_count("curry"), 1)
	assert_eq(restored.junk_count("book"), 2)
	assert_eq(restored.to_dict(), snapshot)


func test_apply_dict_survives_the_json_float_coercion() -> void:
	# JSON gives every number back as a float; counts must land as ints and
	# non-positive entries must not sneak back in as zero stacks.
	var restored := Economy.new(rules)
	restored.apply_dict({
		"money": 250.0,
		"inventory": {"banana": 2.0, "corn": 0.0, "curry": -1.0},
		"junk": {"cd": 1.0},
	})
	assert_eq(restored.money, 250)
	assert_eq(restored.food_count("banana"), 2)
	assert_not_has(restored.inventory, "corn")
	assert_not_has(restored.inventory, "curry")
	assert_eq(restored.junk_count("cd"), 1)


func test_apply_dict_falls_back_cleanly_on_a_wrecked_dictionary() -> void:
	var restored := Economy.new(rules)
	restored.apply_dict({"inventory": "not a dictionary", "junk": 7})
	assert_eq(restored.money, Economy.STARTING_MONEY)
	assert_eq(restored.inventory, {})
	assert_eq(restored.junk, {})


func test_apply_dict_is_silent_so_a_restore_does_not_spam_the_ui() -> void:
	economy.apply_dict({"money": 42, "inventory": {"banana": 1}})
	assert_eq(money_events.size(), 0)
	assert_eq(inventory_events.size(), 0)
