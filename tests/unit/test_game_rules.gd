extends TestCase

## Contract test for the six GameRules flags. These defaults were chosen by the
## user ("faithful with softened edges", with two explicit faithful exceptions).
## If this test goes red, someone has changed the design — not the code.

var rules: GameRules


func before_each() -> void:
	rules = GameRules.new()


func test_softened_edges_defaults() -> void:
	assert_false(rules.breeding_destroys_parent,
		"the parent must RETIRE to a roster, not vanish")
	assert_false(rules.bankruptcy_game_over,
		"running out of food and money must warn and bail out, not end the run")
	assert_eq(rules.fight_interactivity, GameRules.FightInteractivity.TAP_ENCOURAGE,
		"the player may tap during a round for a small effect")


func test_faithful_defaults_the_user_asked_for() -> void:
	assert_true(rules.hard_stat_caps,
		"caps hard-block training; breeding is the only way past them")
	assert_true(rules.disobedience_enabled,
		"FAITHFUL: low friendship means the monkey ignores your strategy")
	assert_true(rules.overfeeding_paralyses,
		"FAITHFUL: overfeeding immobilises until digested — never 'wastes food'")


func test_project_resource_matches_the_defaults() -> void:
	var loaded := GameRules.load_default()
	assert_not_null(loaded, "res://game_rules.tres should load")
	assert_eq(loaded.to_dict(), rules.to_dict(),
		"game_rules.tres has drifted from the coded defaults")


func test_round_trips_through_a_dictionary() -> void:
	var copy := GameRules.new()
	copy.breeding_destroys_parent = true
	copy.fight_interactivity = GameRules.FightInteractivity.NONE
	var restored := GameRules.new()
	restored.apply_dict(copy.to_dict())
	assert_true(restored.breeding_destroys_parent)
	assert_eq(restored.fight_interactivity, GameRules.FightInteractivity.NONE)
