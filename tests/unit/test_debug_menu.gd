extends "res://tests/framework/ui_test_case.gd"

## The debug jump menu (`ui/debug_menu.gd`).
##
## Not gameplay, so not much to pin — but two things here rot silently. The menu
## is only useful if `ui/main.tscn` actually instances it, and its two lookup
## tables name Router screens by enum value, which a renumbering would quietly
## repoint at the wrong screen.

const MAIN_SCENE := "res://ui/main.tscn"
const DebugMenuScript := preload("res://ui/debug_menu.gd")


func _menu() -> CanvasLayer:
	var menu := DebugMenuScript.new() as CanvasLayer
	tree().root.add_child(menu)
	_mounted.append(menu)
	# The suite runs inside `_initialize()`, before the SceneTree is running, so
	# NOTIFICATION_READY is not delivered on its own (see UiTestCase).
	_force_ready(menu)
	return menu


func test_main_actually_instances_the_menu_above_the_router() -> void:
	# A debug menu nothing puts in the tree is a debug menu nobody has.
	#
	# Instantiated but deliberately NOT mounted: `main.gd::_ready` calls
	# `Router.reset_to`, and the Router autoload has no CanvasLayer of its own
	# this early, so mounting it here would crash on a null parent. Structure is
	# all this test needs.
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	var node := main.get_node_or_null("DebugMenu") as CanvasLayer
	# Read everything out BEFORE freeing: a freed Object compares equal to null in
	# GDScript, so asserting on `node` afterwards would always report "missing".
	var found := node != null
	var script: Variant = node.get_script() if found else null
	# The Router's own CanvasLayer is layer 0, so anything above it wins.
	var layer := node.layer if found else 0
	main.free()  # never entered the tree, so free rather than queue_free
	assert_true(found, "ui/main.tscn has no DebugMenu node")
	assert_eq(script, DebugMenuScript, "the DebugMenu node has the wrong script")
	assert_true(layer > 0, "the menu must sit above the Router's screen layer")


func test_every_screen_gets_a_button() -> void:
	var buttons := buttons_under(_menu())
	# One per screen, plus the DEBUG toggle, the SHOW COLLIDERS checkbox, and CLOSE.
	assert_eq(buttons.size(), Router.Screen.size() + 3,
		"expected a jump button for every Router.Screen entry")


func test_the_newest_screens_come_first() -> void:
	# Screens are appended to the enum, and the one you want is nearly always the
	# one being built — so the ordering is deliberate, not incidental.
	var buttons := buttons_under(_menu())
	var labels: Array[String] = []
	for button in buttons:
		labels.append((button as Button).text)
	var last_screen: String = String(Router.Screen.keys().back()).replace("_", " ")
	assert_has(labels, last_screen, "the last enum entry should have a button")
	assert_true(labels.find(last_screen) < labels.find("TITLE"),
		"the newest screen should be listed before the oldest")


func test_both_lookup_tables_name_real_screens() -> void:
	var values := Router.Screen.values()
	for screen in DebugMenuScript.JUMP_PARAMS.keys():
		assert_has(values, screen, "JUMP_PARAMS names a screen value that does not exist")
	for screen in DebugMenuScript.NEEDS_RUN:
		assert_has(values, screen, "NEEDS_RUN names a screen value that does not exist")


func test_the_trap_is_reachable_without_playing_the_flight() -> void:
	# The reason this menu exists: skip the banana run, land in the trap with a
	# pile already worth turning up for.
	var params: Dictionary = DebugMenuScript.JUMP_PARAMS.get(Router.Screen.PROLOGUE_TRAP, {})
	assert_true(int(params.get("bananas", 0)) > 0,
		"jumping to the trap should arrive with bananas, or the pile is empty")
