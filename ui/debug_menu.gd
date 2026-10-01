class_name DebugMenu
extends CanvasLayer

## Global debug switches. Static so screens can read them without owning a
## reference to the menu, and so they survive the menu freeing itself in a
## release build (they stay at their default `false`).
static var show_colliders := false

## The jump menu — a debug-build-only button that goes straight to any screen.
##
## The prologue, the intro and the day loop all sit in a chain, and testing the
## far end of a chain by playing the near end is how a five-second check turns
## into a two-minute one. This exists so nobody has to catch bananas to look at
## the trap.
##
## It lives above the Router's own CanvasLayer (higher `layer`, set in
## `ui/main.tscn`) rather than inside a screen, so it is reachable from every
## screen without a single screen knowing it exists.
##
## **It deletes itself in an export build** (`OS.is_debug_build()`), so there is
## nothing to strip before shipping and no risk of a player finding it.

## Screens that need something in their params to be worth opening. Anything not
## listed opens with `{}`, which is what the Router hands a normal push anyway.
const JUMP_PARAMS: Dictionary = {
	Router.Screen.PROLOGUE_TRAP: {"bananas": 12, "new_game": true},
	Router.Screen.PROLOGUE_FORAGE: {"new_game": true},
	Router.Screen.INTRO: {"new_game": true},
	Router.Screen.TRAINING_SESSION: {"activity": 0},
	## The stable currently shows a single monkey; the screen synthesises one
	## if no run is behind it, so no seed count is needed.
	Router.Screen.STABLE: {},
}

## Screens that read the run the moment they open. Jumping to one without a run
## is a guaranteed crash on the first `GameState.monkey()`, so the menu seeds one
## first — but only when there is nothing to lose.
const NEEDS_RUN: Array[int] = [
	Router.Screen.HOME, Router.Screen.FEED, Router.Screen.TRAINING_SESSION,
	Router.Screen.MONKEY_SELECT, Router.Screen.OPPONENT_SELECT, Router.Screen.MATCH,
	Router.Screen.MATCH_RESULT, Router.Screen.BREEDING, Router.Screen.ROSTER,
	Router.Screen.DAY_END,
]

const TOGGLE_SIZE := Vector2(150.0, 76.0)
const COLUMNS := 4
## Shorter than Palette.TOUCH_MIN on purpose: this is a debug tool that never
## ships, and fitting every screen on one page without scrolling is worth more
## here than a thumb-sized target. Four columns, not five — five makes the widest
## label ("PROLOGUE FORAGE") push the grid wider than the screen.
const JUMP_BUTTON_H := 96.0

var _panel: PanelContainer = null
var _toggle: Button = null


func _ready() -> void:
	if not OS.is_debug_build():
		queue_free()
		return
	_build_toggle()
	_build_panel()


func _build_toggle() -> void:
	_toggle = Button.new()
	_toggle.text = "DEBUG"
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_toggle.offset_left = -TOGGLE_SIZE.x - 12.0
	_toggle.offset_top = 12.0
	_toggle.offset_right = -12.0
	_toggle.offset_bottom = 12.0 + TOGGLE_SIZE.y
	_toggle.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	# Deliberately faint. It sits on top of every screen in every screenshot, so
	# it must never be the thing your eye goes to.
	_toggle.modulate = Color(1.0, 1.0, 1.0, 0.45)
	_toggle.pressed.connect(_on_toggle)
	add_child(_toggle)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.visible = false
	add_child(_panel)

	var backdrop := ColorRect.new()
	backdrop.color = Color(Palette.BG, 0.92)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_child(backdrop)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Palette.MARGIN)
	_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Palette.GUTTER)
	margin.add_child(column)

	var title := Label.new()
	title.text = "JUMP TO SCREEN"
	title.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	title.add_theme_color_override("font_color", Palette.INK_LIGHT)
	column.add_child(title)

	var colliders := CheckBox.new()
	colliders.text = "SHOW COLLIDERS"
	colliders.button_pressed = DebugMenu.show_colliders
	colliders.focus_mode = Control.FOCUS_NONE
	colliders.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	colliders.add_theme_color_override("font_color", Palette.INK_LIGHT)
	colliders.toggled.connect(func(pressed: bool) -> void:
		DebugMenu.show_colliders = pressed
		Sfx.click())
	column.add_child(colliders)

	# Scrolled, not packed: the enum grows every time a screen is added, and a
	# menu that silently loses its last row the day someone appends to it is
	# worse than no menu.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", Palette.GUTTER)
	grid.add_theme_constant_override("v_separation", Palette.GUTTER)
	scroll.add_child(grid)
	# Driven off the enum rather than a hand-kept list, so a screen added later
	# turns up here on its own and nobody has to remember this file exists.
	#
	# Newest first. Screens are appended to the enum, and the screen you want to
	# jump to is nearly always the one being built — so reversing the enum puts it
	# at the top of the page instead of below the fold.
	var names: Array = Router.Screen.keys()
	names.reverse()
	for screen_name in names:
		grid.add_child(_jump_button(screen_name, int(Router.Screen[screen_name])))

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0.0, JUMP_BUTTON_H)
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(_on_toggle)
	column.add_child(close)


func _jump_button(screen_name: String, screen: int) -> Button:
	var button := Button.new()
	button.text = screen_name.replace("_", " ")
	button.custom_minimum_size = Vector2(0.0, JUMP_BUTTON_H)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	# A screen with no scene file lands on the placeholder. Say so on the button
	# rather than letting someone conclude the screen is broken.
	if not ResourceLoader.exists(String(Router.SCENE_PATHS.get(screen, ""))):
		button.text += "  (—)"
		button.modulate = Color(1.0, 1.0, 1.0, 0.45)
	button.pressed.connect(_jump.bind(screen))
	return button


func _on_toggle() -> void:
	_panel.visible = not _panel.visible
	Sfx.click()


## `reset_to` rather than `push`: this is a "start here" button, not a detour,
## and leaving the screen you jumped from underneath makes back do something
## nobody predicted.
func _jump(screen: int) -> void:
	_panel.visible = false
	if NEEDS_RUN.has(screen) and not GameState.has_run():
		GameState.new_run(RunState.Protagonist.KENTA)
	Router.reset_to(screen, JUMP_PARAMS.get(screen, {}))
