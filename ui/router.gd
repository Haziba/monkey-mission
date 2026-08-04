extends Node

## AUTOLOAD: `Router`. The scene router — the one place screens are created and
## destroyed. Implemented (not a stub): later agents add scenes and enum entries
## and otherwise leave this alone.
##
## Screens live in `ui/screens/` and extend `ui/screens/screen.gd`. They are
## instanced into a CanvasLayer this autoload owns, so `ui/main.tscn` stays
## empty and no screen has to know about any other screen.
##
## Contract for a screen:
##   * `func on_enter(params: Dictionary) -> void`  — called after it is added
##   * `func on_result(result: Dictionary) -> void` — called when a screen it
##     pushed pops back with a result
##   * `func on_exit() -> void`                     — called before removal
##   * `func on_back_requested() -> bool`           — OPTIONAL. Return true to
##     swallow the hardware back button (a live match, a confirm prompt already
##     open). Omit it and back simply pops.
##
## Navigation:
##   Router.push(Router.Screen.MATCH, {"opponent_index": 1})
##   Router.pop({"won": true})
##   Router.replace(Router.Screen.HOME)
##
## A screen whose scene file does not exist yet falls back to
## `ui/screens/placeholder_screen.tscn` and prints a warning, so parallel agents
## never crash each other's builds with a missing dependency.

enum Screen {
	TITLE,
	INTRO,
	MONKEY_SELECT,
	HOME,
	FEED,
	TRAINING_SELECT,
	TRAINING_SESSION,
	STAT_CARD,
	SHOP,
	OPPONENT_SELECT,
	MATCH,
	MATCH_RESULT,
	BREEDING,
	ROSTER,
	SETTINGS,
	## Appended by the Integration agent. `ui/screens/day_end.gd` was written as
	## a real screen but had no enum entry, so nothing could route to it. Added
	## at the END so no existing value is renumbered.
	DAY_END,
	## The Monkey Mission intro sequence — the app's first frame, ahead of TITLE.
	SPLASH,
}

## Reconciled by the Integration agent: several entries named a `*_screen.tscn`
## that no agent ever wrote, while the screen itself shipped under a different
## name. Those now point at the file that actually exists, so the Router stops
## silently substituting the placeholder for screens the game needs.
##
##   TRAINING_SESSION  ->  training_screen.tscn   (the rhythm minigame)
##   MATCH_RESULT      ->  day_end.tscn           (the post-match / end-of-day beat)
##   DAY_END           ->  day_end.tscn           (same screen, different entry point)
##
## TRAINING_SELECT, STAT_CARD, SHOP and SETTINGS have no scene and nothing in
## the slice routes to them; they keep their declared paths and fall through to
## the placeholder, which is the documented behaviour.
const SCENE_PATHS: Dictionary = {
	Screen.TITLE: "res://ui/screens/title_screen.tscn",
	Screen.INTRO: "res://ui/screens/intro_screen.tscn",
	Screen.MONKEY_SELECT: "res://ui/screens/monkey_select_screen.tscn",
	Screen.HOME: "res://ui/screens/home_screen.tscn",
	Screen.FEED: "res://ui/screens/feed_screen.tscn",
	Screen.TRAINING_SELECT: "res://ui/screens/training_select_screen.tscn",
	Screen.TRAINING_SESSION: "res://ui/screens/training_screen.tscn",
	Screen.STAT_CARD: "res://ui/screens/stat_card_screen.tscn",
	Screen.SHOP: "res://ui/screens/shop_screen.tscn",
	Screen.OPPONENT_SELECT: "res://ui/screens/opponent_select_screen.tscn",
	Screen.MATCH: "res://ui/screens/match_screen.tscn",
	Screen.MATCH_RESULT: "res://ui/screens/day_end.tscn",
	Screen.BREEDING: "res://ui/screens/breeding_screen.tscn",
	Screen.ROSTER: "res://ui/screens/roster_screen.tscn",
	Screen.SETTINGS: "res://ui/screens/settings_screen.tscn",
	Screen.DAY_END: "res://ui/screens/day_end.tscn",
	Screen.SPLASH: "res://ui/screens/splash_screen.tscn",
}

const PLACEHOLDER_SCENE := "res://ui/screens/placeholder_screen.tscn"

## The Android hardware back button and the desktop Escape key, declared in
## project.godot. Handled here because it is the stack that knows what "back"
## means; a screen can still veto with `on_back_requested()`.
const BACK_ACTION := "mp_back"

signal screen_pushed(screen: int)
signal screen_popped(screen: int)
signal screen_changed(screen: int)

## Set false to suspend hardware-back navigation entirely (a cutscene, a match).
## Prefer `on_back_requested()` on the screen itself — this is the blunt tool.
var back_enabled: bool = true

var _layer: CanvasLayer = null
## Array of { "screen": int, "node": Node, "params": Dictionary }
var _stack: Array[Dictionary] = []


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "ScreenLayer"
	add_child(_layer)


## Hardware back / Escape. Never pops the last screen — backing out of the title
## into an empty stack would leave a blank app.
func _unhandled_input(event: InputEvent) -> void:
	if not back_enabled:
		return
	if not InputMap.has_action(BACK_ACTION):
		return
	if not event.is_action_pressed(BACK_ACTION):
		return
	var top := current_node()
	if top != null and top.has_method("on_back_requested"):
		if bool(top.call("on_back_requested")):
			get_viewport().set_input_as_handled()
			return
	if depth() <= 1:
		return
	get_viewport().set_input_as_handled()
	pop()


## Add a screen on top of the current one. The one below stays instanced but is
## hidden and stops processing.
func push(screen: Screen, params: Dictionary = {}) -> Node:
	var node := _instantiate(screen)
	if node == null:
		return null
	if not _stack.is_empty():
		_set_active(_stack.back()["node"], false)
	_layer.add_child(node)
	_stack.append({"screen": int(screen), "node": node, "params": params})
	if node.has_method("on_enter"):
		node.call("on_enter", params)
	screen_pushed.emit(int(screen))
	screen_changed.emit(int(screen))
	return node


## Pop the top screen and hand `result` to the one underneath.
##
## Never pops the LAST screen. `GameScreen.close()` routes through here, so a
## screen that ends up at the root of the stack (a match resumed straight from a
## loaded save, a `_fail()` on the bottom screen) would otherwise leave the app
## on an empty CanvasLayer — a black screen with no input and no way back. The
## hardware-back path already refused to do this; the public entry point did not.
## Use `replace()` or `reset_to()` to change what the root screen is.
func pop(result: Dictionary = {}) -> void:
	if _stack.is_empty():
		push_warning("Router.pop on an empty stack")
		return
	if _stack.size() <= 1:
		push_warning("Router.pop refused: %s is the last screen on the stack"
			% _stack.back()["screen"])
		return
	var top: Dictionary = _stack.pop_back()
	_dismiss(top)
	screen_popped.emit(int(top["screen"]))
	if _stack.is_empty():
		return
	var below: Dictionary = _stack.back()
	_set_active(below["node"], true)
	if below["node"].has_method("on_result"):
		below["node"].call("on_result", result)
	screen_changed.emit(int(below["screen"]))


## Replace the top screen (same stack depth).
func replace(screen: Screen, params: Dictionary = {}) -> Node:
	if not _stack.is_empty():
		_dismiss(_stack.pop_back())
	return push(screen, params)


## Clear the whole stack and start again at `screen`. Used for title -> run and
## for returning to the title from a game over.
func reset_to(screen: Screen, params: Dictionary = {}) -> Node:
	while not _stack.is_empty():
		_dismiss(_stack.pop_back())
	return push(screen, params)


## Pop until `screen` is on top. No-op when it is not in the stack.
func pop_to(screen: Screen, result: Dictionary = {}) -> void:
	var found := false
	for entry in _stack:
		if int(entry["screen"]) == int(screen):
			found = true
			break
	if not found:
		push_warning("Router.pop_to: %s is not on the stack" % screen)
		return
	while _stack.size() > 1 and int(_stack.back()["screen"]) != int(screen):
		pop(result)


func current() -> int:
	if _stack.is_empty():
		return -1
	return int(_stack.back()["screen"])


func current_node() -> Node:
	if _stack.is_empty():
		return null
	return _stack.back()["node"]


func depth() -> int:
	return _stack.size()


## True when `screen` is anywhere on the stack, not only on top.
func is_open(screen: Screen) -> bool:
	for entry in _stack:
		if int(entry["screen"]) == int(screen):
			return true
	return false


func _instantiate(screen: Screen) -> Node:
	var path: String = SCENE_PATHS.get(screen, "")
	if path != "" and not ResourceLoader.exists(path):
		# Tolerate the one name drift that keeps happening while screens are
		# written in parallel: `foo_screen.tscn` declared, `foo.tscn` on disk.
		# Warn rather than resolve silently — the file should still be renamed.
		var alias := path.replace("_screen.tscn", ".tscn")
		if alias != path and ResourceLoader.exists(alias):
			push_warning("Router: %s is missing; using %s instead. Rename it." % [path, alias])
			path = alias
	if path == "" or not ResourceLoader.exists(path):
		push_warning("Router: no scene for %s (%s) — using the placeholder" % [screen, path])
		path = PLACEHOLDER_SCENE
		if not ResourceLoader.exists(path):
			push_error("Router: placeholder scene missing at %s" % PLACEHOLDER_SCENE)
			return null
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("Router: failed to load %s" % path)
		return null
	var node := packed.instantiate()
	node.set_meta("router_screen", int(screen))
	return node


## Tear one stack entry down. `on_exit` runs while the node is still in the
## tree; the node then leaves the tree IMMEDIATELY rather than at the end of the
## frame, so a replace/reset never shows the outgoing screen under the incoming
## one for a frame.
func _dismiss(entry: Dictionary) -> void:
	var node: Node = entry.get("node", null)
	if node == null or not is_instance_valid(node):
		return
	if node.has_method("on_exit"):
		node.call("on_exit")
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	node.queue_free()


func _set_active(node: Node, active: bool) -> void:
	if node == null:
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = active
	node.set_process(active)
	node.set_process_input(active)
	node.set_process_unhandled_input(active)
