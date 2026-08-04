extends TestCase

## The splash screen's one piece of logic: which beat of the intro sequence a
## given elapsed time falls in. Everything else on that screen is painting.

const SplashScreen := preload("res://ui/screens/splash_screen.gd")


func test_beats_run_in_order() -> void:
	assert_eq(SplashScreen.beat_at(0.0), SplashScreen.Beat.SPACE, "opens on the starfield")
	assert_eq(SplashScreen.beat_at(1.5), SplashScreen.Beat.FLYBY, "ship crosses")
	assert_eq(SplashScreen.beat_at(2.2), SplashScreen.Beat.WIPE, "trail wipes")
	assert_eq(SplashScreen.beat_at(3.0), SplashScreen.Beat.TITLE, "title rests")


## Each beat owns its start instant, so no frame lands between two of them.
func test_boundaries_belong_to_the_beat_they_start() -> void:
	assert_eq(SplashScreen.beat_at(SplashScreen.FLYBY_AT), SplashScreen.Beat.FLYBY)
	assert_eq(SplashScreen.beat_at(SplashScreen.WIPE_AT), SplashScreen.Beat.WIPE)
	assert_eq(SplashScreen.beat_at(SplashScreen.REST_AT), SplashScreen.Beat.TITLE)


## Once at rest it stays at rest — the prompt waits for a tap however long.
func test_title_is_the_terminal_beat() -> void:
	assert_eq(SplashScreen.beat_at(600.0), SplashScreen.Beat.TITLE)


func test_router_can_reach_the_splash() -> void:
	var path: String = Router.SCENE_PATHS.get(Router.Screen.SPLASH, "")
	assert_eq(path, "res://ui/screens/splash_screen.tscn", "SPLASH is mapped")
	assert_true(ResourceLoader.exists(path), "the splash scene exists on disk")
