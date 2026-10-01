extends "res://tests/framework/ui_test_case.gd"

## The playable prologue — `prologue_forage.gd` and `prologue_trap.gd`.
##
## Two screens' worth of animation is not testable and should not be. What is
## testable is the handful of rules a player can actually lose to: whether a
## drone touching a fruit box counts as a pickup, and who is standing under the
## dish when it lands. Both live on their screen as static functions for exactly
## that reason.
##
## The mount tests are here because the prologue is now on the NEW GAME route.
## A prologue that fails to instantiate is a game that cannot be started.

const FORAGE_SCENE := "res://ui/screens/prologue_forage.tscn"
const TRAP_SCENE := "res://ui/screens/prologue_trap.tscn"
## Preloaded rather than reached through a global class name — these screens have
## no `class_name`, and the statics have to be reachable without an editor run.
const ForageScript := preload("res://ui/screens/prologue_forage.gd")
const TrapScript := preload("res://ui/screens/prologue_trap.gd")


# --- the side-scrolling flight ----------------------------------------------

func test_axis_aligned_boxes_overlap_only_when_they_actually_touch() -> void:
	# The one rule a fruit pickup / branch hit rides on. Under both should
	# collide; separated on either axis should not.
	assert_true(ForageScript.rects_overlap(
		Vector2(100, 100), Vector2(20, 20),
		Vector2(110, 105), Vector2(20, 20)))
	assert_false(ForageScript.rects_overlap(
		Vector2(100, 100), Vector2(20, 20),
		Vector2(150, 100), Vector2(20, 20)))
	assert_false(ForageScript.rects_overlap(
		Vector2(100, 100), Vector2(20, 20),
		Vector2(100, 150), Vector2(20, 20)))


func test_boosting_burns_more_fuel_than_cruising() -> void:
	# The boost has to cost strictly more than moving the same second without
	# it, or the optimum play is to hold it down for the whole flight.
	assert_true(ForageScript.fuel_drain_for(true) > ForageScript.fuel_drain_for(false))


# --- the trap ----------------------------------------------------------------

func test_the_dish_catches_what_is_under_it_and_nothing_else() -> void:
	var half := TrapScript.DISH_HALF
	var xs := PackedFloat32Array([0.5, 0.5 + half * 0.5, 0.5 - half * 0.5, 0.5 + half * 2.0, 0.1])
	var hits: PackedInt32Array = TrapScript.caught_indices(0.5, half, xs)
	assert_eq(hits.size(), 3, "three monkeys were inside the footprint")
	assert_has(Array(hits), 0)
	assert_not_has(Array(hits), 3, "a monkey two footprints away is not caught")
	assert_not_has(Array(hits), 4, "a monkey across the clearing is not caught")


func test_the_dish_edge_is_the_boundary() -> void:
	# The rule is inclusive on purpose — the alternative is a player watching a
	# monkey they clearly dropped on walk away. "Exactly on the rim" is not a
	# claim worth pinning, though: positions arrive as float32 and the constant is
	# float64, so a hair either way is not a thing anyone can aim at.
	var half := TrapScript.DISH_HALF
	var inside: PackedInt32Array = TrapScript.caught_indices(
		0.5, half, PackedFloat32Array([0.5 + half * 0.999]))
	assert_eq(inside.size(), 1, "a hair inside the rim is caught")
	var outside: PackedInt32Array = TrapScript.caught_indices(
		0.5, half, PackedFloat32Array([0.5 + half * 1.001]))
	assert_eq(outside.size(), 0, "a hair outside the rim is not")


func test_a_bigger_pile_draws_a_bigger_troop_but_never_a_silly_one() -> void:
	assert_eq(TrapScript.wave_size(0), 2, "an empty pile still draws the curious")
	assert_true(TrapScript.wave_size(18) > TrapScript.wave_size(0),
		"a full larder should be worth more than an empty one")
	assert_eq(TrapScript.wave_size(9999), 4, "the troop is capped")


func test_the_trap_asks_for_the_crew_a_voyage_actually_starts_with() -> void:
	# Design §2.5: a voyage starts with four, capacity is six. If those move, the
	# prologue has to move with them or it hands the game the wrong roster.
	assert_eq(TrapScript.TARGET_CREW, 4)
	assert_eq(TrapScript.MAX_CREW, 6)


# --- the route ---------------------------------------------------------------

func test_both_prologue_screens_instantiate() -> void:
	for path in [FORAGE_SCENE, TRAP_SCENE]:
		var screen := mount(path) as Control
		assert_not_null(screen, "%s failed to mount" % path)
		if screen == null:
			continue
		assert_not_null(screen.get_node_or_null("Hint"), "%s has no hint label" % path)
		assert_not_null(screen.get_node_or_null("Banner"), "%s has no banner" % path)


func test_the_router_has_a_real_scene_for_each_prologue_screen() -> void:
	# The Router silently substitutes the placeholder for a missing scene, so a
	# typo'd path is invisible until a player hits it.
	for screen in [Router.Screen.PROLOGUE_FORAGE, Router.Screen.PROLOGUE_TRAP]:
		var path: String = Router.SCENE_PATHS.get(screen, "")
		assert_true(ResourceLoader.exists(path), "no scene at %s" % path)
