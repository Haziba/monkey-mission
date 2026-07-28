class_name GameScreen
extends Control

## Base class for every screen in `ui/screens/`. The Router instances these; it
## calls the three hooks below and nothing else.
##
## Rules for subclasses:
##  * Read state from the `GameState` autoload only. Never construct a Care,
##    Training, MatchResolver or Breeding yourself.
##  * Never mutate a Monkey, an Economy or a Ladder directly.
##  * Take every colour from `Palette`. Placeholder shapes only: ColorRect,
##    Panel, Label, Line2D, draw_*. No image files.
##  * Portrait 1080x1920 logical. Anything tappable is at least
##    Palette.TOUCH_MIN tall.

## Params the Router was given when this screen was pushed.
var enter_params: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)


## Called once, immediately after the Router adds this screen to the tree.
func on_enter(params: Dictionary) -> void:
	enter_params = params


## Called when a screen this one pushed pops back with a result.
func on_result(_result: Dictionary) -> void:
	pass


## Called just before this screen is removed.
func on_exit() -> void:
	pass


## Convenience: close this screen and hand a result to the one below.
func close(result: Dictionary = {}) -> void:
	Router.pop(result)
