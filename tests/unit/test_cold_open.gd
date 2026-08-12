extends TestCase

## The cold open's running order and the preference that decides whether it
## plays at all. Everything else on that screen is painting.

const ColdOpen := preload("res://ui/screens/cold_open.gd")

## Beat indices, in the order they play. Named here so a reordering of the
## sequence fails loudly rather than silently renumbering.
const TRANSIT := 0
const ARRIVAL := 1
const BLOOM := 2
const MEMO := 3


func after_each() -> void:
	Prefs.clear()


func test_beats_run_in_order() -> void:
	assert_eq(ColdOpen.beat_at(0.0), TRANSIT, "opens on empty space")
	assert_eq(ColdOpen.beat_at(9.0), ARRIVAL, "the site resolves ahead")
	assert_eq(ColdOpen.beat_at(14.0), BLOOM, "the survey finds a living planet")
	assert_eq(ColdOpen.beat_at(19.0), MEMO, "and head office replies")


## Each beat owns its start instant, so no frame falls between two of them.
func test_boundaries_belong_to_the_beat_they_start() -> void:
	assert_eq(ColdOpen.beat_at(ColdOpen.ARRIVAL_AT), ARRIVAL)
	assert_eq(ColdOpen.beat_at(ColdOpen.BLOOM_AT), BLOOM)
	assert_eq(ColdOpen.beat_at(ColdOpen.MEMO_AT), MEMO)


func test_memo_is_terminal() -> void:
	assert_eq(ColdOpen.beat_at(600.0), MEMO, "the memo waits for the player")


## REBEL is offered on the second-to-last press: one click from the sun.
func test_rebel_appears_one_press_from_the_end() -> void:
	var presses_to_sun := int(ceil(1.0 / ColdOpen.PRESS_STEP))
	var at_reveal := int(ceil(ColdOpen.REBEL_AT / ColdOpen.PRESS_STEP))
	assert_eq(presses_to_sun - at_reveal, 1, "exactly one press left when REBEL shows")


func test_the_hint_thresholds_land_before_the_button() -> void:
	assert_true(ColdOpen.DOUBT_AT < ColdOpen.SAVED_AT, "doubt comes first")
	assert_true(ColdOpen.SAVED_AT < ColdOpen.PRECIOUS_AT, "then the plea")
	assert_true(ColdOpen.PRECIOUS_AT < ColdOpen.REBEL_AT, "and only then the button")


func test_router_can_reach_the_cold_open() -> void:
	var path: String = Router.SCENE_PATHS.get(Router.Screen.COLD_OPEN, "")
	assert_eq(path, "res://ui/screens/cold_open.tscn", "COLD_OPEN is mapped")
	assert_true(ResourceLoader.exists(path), "the scene exists on disk")


# --- the first-launch preference -------------------------------------------

func test_intro_is_unseen_on_a_fresh_install() -> void:
	Prefs.clear()
	assert_false(Prefs.intro_seen(), "a fresh install plays the intro")


func test_intro_seen_survives_a_reread() -> void:
	Prefs.clear()
	Prefs.set_intro_seen(true)
	assert_true(Prefs.intro_seen(), "and the app then opens on the title")


## Deleting a save must not make the player sit through the intro again — the
## whole reason prefs live outside the save file.
func test_clearing_the_save_does_not_clear_the_preference() -> void:
	Prefs.clear()
	Prefs.set_intro_seen(true)
	SaveGame.delete_save()
	assert_true(Prefs.intro_seen(), "prefs outlive the run")
