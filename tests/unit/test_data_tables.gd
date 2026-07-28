extends TestCase

## The species and food tables are DATA, not stubs — they ship complete, and
## these tests pin the dossier-confirmed numbers so a later tuning pass cannot
## quietly rewrite the source material.


func test_five_species_exist() -> void:
	var all := SpeciesDb.all()
	assert_eq(all.size(), 5, "dossier §8 [C]: five types, excluding bosses")
	var names := {}
	for species in all:
		assert_ne(species.display_name, "", "every species needs a name")
		assert_false(names.has(species.display_name), "species names must be unique")
		names[species.display_name] = true


func test_every_species_likes_bananas_and_none_dislikes_them() -> void:
	# Dossier §5 [C]: "Most monkeys like bananas, curry, ice milk and expensive
	# food; some dislike garlic, chicken and liver."
	for species in SpeciesDb.all():
		assert_true(species.likes("banana"),
			"%s should like bananas — the documented befriending food" % species.display_name)
		assert_false(species.dislikes("banana"))


func test_species_preferences_only_reference_real_foods() -> void:
	for species in SpeciesDb.all():
		for food_id in species.liked_foods:
			assert_true(FoodDb.has_food(food_id), "unknown liked food: %s" % food_id)
		for food_id in species.disliked_foods:
			assert_true(FoodDb.has_food(food_id), "unknown disliked food: %s" % food_id)


func test_friendship_multiplier_ranks_liked_over_neutral_over_disliked() -> void:
	var crimson := SpeciesDb.get_species(Species.Type.CRIMSON)
	assert_true(crimson.friendship_multiplier_for("banana") > 1.0)
	assert_almost_eq(crimson.friendship_multiplier_for("bread"), 1.0)
	assert_true(crimson.friendship_multiplier_for("garlic") < 0.0,
		"a disliked food should cost friendship, not merely give none")


func test_food_table_matches_the_supergus2_numbers() -> void:
	var banana := FoodDb.get_food("banana")
	assert_not_null(banana)
	assert_eq(banana.buy_price, 100)
	assert_eq(banana.sell_price, 50)
	assert_eq(banana.strength_restore, 15)
	assert_eq(banana.stamina_restore, 15)
	assert_eq(banana.hunger, 3)

	var curry := FoodDb.get_food("curry")
	assert_eq(curry.strength_restore, 60)
	assert_eq(curry.stamina_restore, 60)
	assert_eq(curry.hunger, 9)


func test_coffee_has_negative_hunger() -> void:
	# Dossier §5 [C]: Coffee is Hunger -5, explicitly to make room for more food.
	assert_eq(FoodDb.get_food("coffee").hunger, -5,
		"coffee's negative hunger is a documented mechanic, not a data error")


func test_permanent_boosters_are_flagged() -> void:
	var eel := FoodDb.get_food("eel")
	assert_true(eel.is_permanent_booster())
	assert_eq(int(eel.permanent_gains[Monkey.Stat.STRENGTH]), 10)
	assert_eq(int(eel.permanent_gains[Monkey.Stat.STAMINA]), 10)

	var coconuts := FoodDb.get_food("coconuts")
	assert_eq(int(coconuts.permanent_gains[Monkey.Stat.POWER]), 5)
	assert_eq(int(coconuts.permanent_gains[Monkey.Stat.KNOWLEDGE]), 5)

	assert_false(FoodDb.get_food("banana").is_permanent_booster())


func test_sell_price_never_exceeds_buy_price() -> void:
	# Dossier §9 [C]: sell is generally 50% of buy. The guide's Peas row breaks
	# this and the dossier calls it a typo — no such row may exist here.
	for food in FoodDb.all():
		assert_true(food.sell_price <= food.buy_price,
			"%s sells for more than it costs" % food.id)


func test_starting_inventory_can_befriend_a_monkey() -> void:
	var start := FoodDb.starting_inventory()
	assert_true(int(start.get("banana", 0)) >= 2,
		"dossier §5 [C]: the documented fastest befriending is two bananas")
