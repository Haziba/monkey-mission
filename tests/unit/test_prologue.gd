extends "res://tests/framework/ui_test_case.gd"

## The playable prologue — `prologue_forage.gd` and `prologue_trap.gd`.
##
## Two screens' worth of animation is not testable and should not be. What is
## testable is the handful of rules a player can actually lose to: where the fake
## perspective puts a tap target, and who is standing under the dish when it
## lands. Both are static functions on their screen for exactly that reason.
##
## The mount tests are here because the prologue is now on the NEW GAME route.
## A prologue that fails to instantiate is a game that cannot be started.

const FORAGE_SCENE := "res://ui/screens/prologue_forage.tscn"
const TRAP_SCENE := "res://ui/screens/prologue_trap.tscn"
## Preloaded rather than reached through a global class name — these screens have
## no `class_name`, and the statics have to be reachable without an editor run.
const ForageScript := preload("res://ui/screens/prologue_forage.gd")
const TrapScript := preload("res://ui/screens/prologue_trap.gd")

const SCREEN := Vector2(1920.0, 880.0)


# --- the flight's fake perspective -------------------------------------------

func test_depth_scale_is_full_size_at_the_camera_and_shrinks_with_depth() -> void:
	assert_almost_eq(ForageScript.depth_scale(0.0), 1.0, 0.0001,
		"the camera plane is the unit size")
	var previous := 1.0
	for step in 10:
		var s: float = ForageScript.depth_scale(float(step + 1) * 0.1)
		assert_true(s < previous, "depth %.1f did not shrink" % (float(step + 1) * 0.1))
		assert_true(s > 0.0, "scale must stay positive or sprites invert")
		previous = s


func test_everything_converges_on_the_vanishing_point() -> void:
	# A banana in the far left lane still spawns near the middle of the screen —
	# that convergence IS the illusion, and it is what makes a far banana a
	# smaller tap target than a near one.
	var far: Vector2 = ForageScript.project(1.0, -1.0, 0.0, SCREEN)
	var near: Vector2 = ForageScript.project(0.0, -1.0, 0.0, SCREEN)
	assert_true(absf(far.x - SCREEN.x * 0.5) < absf(near.x - SCREEN.x * 0.5),
		"the far point should sit closer to the centre line")
	assert_almost_eq(near.x, 0.0, 0.5, "lane -1 at the camera plane is the left edge")
	# Depth alone never moves anything off the horizon line.
	assert_almost_eq(far.y, near.y, 0.5, "world_y 0 is the horizon at every depth")


func test_the_ground_stays_below_the_horizon_at_every_depth() -> void:
	var horizon := SCREEN.y * ForageScript.HORIZON
	for step in 11:
		var at: Vector2 = ForageScript.project(float(step) * 0.1, 0.0, 0.52, SCREEN)
		assert_true(at.y > horizon, "the ground rose above the horizon at z=%.1f" % (step * 0.1))


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
