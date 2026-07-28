extends GameScreen

## The title screen — the app's entry point and the only place the player can
## start or resume a run.
##
## Layout follows the original's title (dossier §10 [C] and
## docs/reference/screens-kog/001.png): a near-white field, a chunky outlined
## wordmark sitting on a yellow blob, a red boxing glove with an orange
## starburst behind it, and a checkerboard band across the footer — the
## "chunky checkerboard field" the dossier calls a recurring UI motif.
##
## ART IS PLACEHOLDER SHAPES. The wordmark is two Labels with a thick font
## outline; the blob, glove, starburst and checkerboard are draw_circle /
## draw_rect / draw_colored_polygon calls in `_draw`. Nothing here is traced
## from the original and there are no image files.
##
## Everything it does to the run goes through the GameState autoload:
##   NEW GAME  -> GameState.new_run() -> GameState.save_run() -> Router
##   CONTINUE  -> GameState.has_save() / GameState.load_run() -> Router
##
## The one direct core call is `SaveGame.peek()`, used to draw the save summary
## under CONTINUE. GameState exposes `has_save()` but no peek; peek is a pure
## read of the save header and computes no rule, so reading it here does not put
## game logic in the UI. If GameState grows a `save_summary()` later, switch.

# --- geometry, all fractions so the art survives an `expand` aspect ---------
## Centre of the logo band, as a fraction of screen HEIGHT.
const LOGO_CY := 0.2275
## Everything else is a fraction of screen WIDTH, so the wordmark keeps its
## proportions when the viewport gets taller on a 20:9 phone.
const OUTLINE_W := 0.009

## The yellow blob, as overlapping circles: (dx, dy, radius), all × width,
## measured from the logo centre. Two rows — one behind each half of the
## wordmark — plus a fat circle in the middle to fill the waist.
const BLOB: Array[Vector3] = [
	Vector3(-0.300, -0.052, 0.108),
	Vector3(-0.105, -0.068, 0.120),
	Vector3(0.095, -0.060, 0.116),
	Vector3(0.272, -0.040, 0.098),
	Vector3(-0.275, 0.058, 0.110),
	Vector3(-0.080, 0.072, 0.124),
	Vector3(0.120, 0.066, 0.118),
	Vector3(0.295, 0.046, 0.100),
	Vector3(0.000, 0.005, 0.150),
]

const WORDMARK_TOP_DY := -0.085
const WORDMARK_BOTTOM_DY := 0.090
const WORDMARK_TOP_SIZE := 0.157
const WORDMARK_BOTTOM_SIZE := 0.150
const WORDMARK_BOX := 0.24

const GLOVE_DX := 0.300
const GLOVE_DY := -0.135
const GLOVE_R := 0.085
const BURST_DX := 0.315
const BURST_DY := -0.155
const BURST_OUTER := 0.148
const BURST_INNER := 0.094
const BURST_POINTS := 11

const CHECKER_TOP := 0.875
const CHECKER_CELL := 0.05
const CHECKER_ROWS := 2

## Dossier §11 [C]: the choice is the TRAINER (Kenta or Sumire), not the monkey —
## the "pick a male or female monkey" claim that circulates is wrong. That choice
## belongs to the intro, so the title seeds a run with the default and hands the
## intro `new_game: true` so it can call GameState.new_run again with whichever
## sibling the player picks. new_run is idempotent: it rebuilds the whole run.
const DEFAULT_PROTAGONIST := RunState.Protagonist.KENTA

@onready var _wordmark_top: Label = $WordmarkTop
@onready var _wordmark_bottom: Label = $WordmarkBottom
@onready var _subtitle: Label = $Subtitle
@onready var _new_game: Button = $Menu/NewGame
@onready var _continue: Button = $Menu/Continue
@onready var _save_info: Label = $Menu/SaveInfo
@onready var _settings: Button = $Menu/Settings
@onready var _status: Label = $Menu/Status
@onready var _footer: Label = $Footer
@onready var _confirm: Control = $Confirm
@onready var _confirm_dim: ColorRect = $Confirm/Dim
@onready var _confirm_cancel: Button = $Confirm/Box/Rows/Buttons/Cancel
@onready var _confirm_overwrite: Button = $Confirm/Box/Rows/Buttons/Overwrite


func _ready() -> void:
	super()
	_apply_palette()
	resized.connect(_relayout)
	_relayout()
	_new_game.pressed.connect(_on_new_game_pressed)
	_continue.pressed.connect(_on_continue_pressed)
	_settings.pressed.connect(_on_settings_pressed)
	_confirm_cancel.pressed.connect(_on_confirm_cancelled)
	_confirm_overwrite.pressed.connect(_on_confirm_accepted)


func on_enter(params: Dictionary) -> void:
	super(params)
	_set_confirm_visible(false)
	_status.visible = false
	_refresh_save_state()
	_new_game.grab_focus()


## Hardware back / Escape, offered by the Router. Only meaningful while the
## overwrite prompt is up; at the root of the stack, back does nothing.
func on_back_requested() -> bool:
	if _confirm.visible:
		Sfx.cancel()
		_set_confirm_visible(false)
		return true
	return false


# --- painting --------------------------------------------------------------

## Colours are applied here rather than baked into the .tscn so ui/theme/palette.gd
## stays the single source of truth for every fill in the game.
func _apply_palette() -> void:
	_wordmark_top.add_theme_color_override("font_color", Palette.LOGO_BLUE)
	_wordmark_top.add_theme_color_override("font_outline_color", Palette.INK)
	_wordmark_bottom.add_theme_color_override("font_color", Palette.LOGO_RED)
	_wordmark_bottom.add_theme_color_override("font_outline_color", Palette.INK)
	_subtitle.add_theme_color_override("font_color", Palette.PANEL)
	_footer.add_theme_color_override("font_color", Palette.PANEL)
	_save_info.add_theme_color_override("font_color", Palette.PANEL)
	_status.add_theme_color_override("font_color", Palette.BAD)
	_confirm_dim.color = Color(Palette.INK, 0.72)


## The design size is 1080x1920, but the project stretches with `expand` aspect:
## a device wider than 9:16 hands this screen a WIDER logical viewport, not a
## letterbox. Sizing the logo off raw width would then inflate it into the menu
## below, so the art unit is capped at the portrait width and the wordmark stays
## centred in the extra space.
func _art_width() -> float:
	var portrait := size.y * float(Palette.SCREEN_SIZE.x) / float(Palette.SCREEN_SIZE.y)
	return minf(size.x, portrait)


func _relayout() -> void:
	var w := size.x
	if w <= 0.0:
		return
	_place_wordmark(_wordmark_top, WORDMARK_TOP_DY, WORDMARK_TOP_SIZE)
	_place_wordmark(_wordmark_bottom, WORDMARK_BOTTOM_DY, WORDMARK_BOTTOM_SIZE)
	queue_redraw()


func _place_wordmark(label: Label, dy: float, font_fraction: float) -> void:
	var w := _art_width()
	var centre_y := size.y * LOGO_CY + dy * w
	var half := WORDMARK_BOX * w * 0.5
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_top = centre_y - half
	label.offset_bottom = centre_y + half
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.add_theme_font_size_override("font_size", int(round(w * font_fraction)))
	# The original's lettering is thick-outlined (§10 [C]); the outline is what
	# keeps blue-on-yellow and red-on-yellow legible.
	label.add_theme_constant_override("outline_size", int(round(w * 0.021)))


func _draw() -> void:
	var h := size.y
	if size.x <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Palette.PAPER_WHITE)

	var w := _art_width()
	var centre := Vector2(size.x * 0.5, h * LOGO_CY)
	var outline := w * OUTLINE_W

	# Blob: every circle's outline first, then every fill, so the outlines of
	# overlapping circles never cut across the yellow.
	for c in BLOB:
		draw_circle(centre + Vector2(c.x, c.y) * w, c.z * w + outline, Palette.INK)
	for c in BLOB:
		draw_circle(centre + Vector2(c.x, c.y) * w, c.z * w, Palette.LOGO_BLOB)

	_draw_starburst(
		centre + Vector2(BURST_DX, BURST_DY) * w,
		BURST_OUTER * w, BURST_INNER * w, BURST_POINTS, Palette.ACCENT)
	_draw_glove(centre + Vector2(GLOVE_DX, GLOVE_DY) * w, GLOVE_R * w, outline)
	_draw_checkerboard()


## Drawn as a fan of individual triangles around a filled hub rather than one
## polygon: draw_colored_polygon triangulates as a fan, which renders a concave
## star wrong.
func _draw_starburst(c: Vector2, outer: float, inner: float, points: int, color: Color) -> void:
	draw_circle(c, inner, color)
	var step := TAU / float(points)
	for i in points:
		var mid := step * float(i)
		var a0 := mid - step * 0.5
		var a1 := mid + step * 0.5
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(cos(a0), sin(a0)) * inner,
			c + Vector2(cos(mid), sin(mid)) * outer,
			c + Vector2(cos(a1), sin(a1)) * inner,
		]), color)


## Mitt, thumb and cuff: three shapes, outline pass then fill pass.
func _draw_glove(c: Vector2, r: float, outline: float) -> void:
	var thumb_c := c + Vector2(-r * 0.74, r * 0.52)
	var thumb_r := r * 0.46
	var cuff := Rect2(c.x - r * 0.62, c.y + r * 0.58, r * 1.24, r * 0.74)
	draw_circle(c, r + outline, Palette.INK)
	draw_circle(thumb_c, thumb_r + outline, Palette.INK)
	draw_rect(cuff.grow(outline), Palette.INK)
	draw_circle(c, r, Palette.LOGO_RED)
	draw_circle(thumb_c, thumb_r, Palette.LOGO_RED)
	draw_rect(cuff, Palette.LOGO_RED)


## The chunky checkerboard field, a recurring UI motif in the original (§10 [C]).
func _draw_checkerboard() -> void:
	var cell := _art_width() * CHECKER_CELL
	if cell <= 0.0:
		return
	var top := size.y * CHECKER_TOP
	var cols := int(ceil(size.x / cell))
	for row in CHECKER_ROWS:
		for col in cols:
			if (row + col) % 2 != 0:
				continue
			draw_rect(Rect2(col * cell, top + row * cell, cell, cell), Palette.CHECKER)


# --- save slot -------------------------------------------------------------

func _refresh_save_state() -> void:
	if not GameState.has_save():
		_continue.disabled = true
		_save_info.text = "NO SAVED GAME"
		return
	var info := SaveGame.peek()
	if not bool(info.get("exists", false)):
		_continue.disabled = true
		_save_info.text = "SAVE FILE UNREADABLE"
		return
	_continue.disabled = false
	var monkey_name := String(info.get("monkey_name", ""))
	if monkey_name.is_empty():
		monkey_name = "NO MONKEY"
	# The original's own HUD wording: `[DAYS 2  AM]` and `JSB RANK: 13` (§10 [C]).
	# JSB is left unexpanded on purpose — §14.1 says what it stands for is unknown.
	_save_info.text = "DAYS %d  ·  %s  ·  JSB RANK %d  ·  GEN %d" % [
		int(info.get("day", 1)),
		monkey_name.to_upper(),
		int(info.get("rank", 0)),
		int(info.get("generation", 1)),
	]


# --- actions ---------------------------------------------------------------

func _on_new_game_pressed() -> void:
	Sfx.confirm()
	_status.visible = false
	if GameState.has_save():
		_set_confirm_visible(true)
		return
	_start_new_run()


func _on_confirm_cancelled() -> void:
	Sfx.cancel()
	_set_confirm_visible(false)


func _on_confirm_accepted() -> void:
	Sfx.confirm()
	_start_new_run()


## There is one continuous save (dossier §7 phase 6 [C]: the post-game continues
## on the same file, and there is no New Game+), so a new run simply overwrites
## it — saving immediately means the player can always get back to day 1.
func _start_new_run() -> void:
	_set_confirm_visible(false)
	GameState.new_run(int(DEFAULT_PROTAGONIST))
	if not GameState.has_run():
		# Never route into a null run — the next screen would crash on the first
		# GameState.monkey() call and the player would have no way back.
		push_error("TitleScreen: GameState.new_run left `run` null (RunState.new_run stubbed?)")
		_fail("COULD NOT START A NEW RUN.")
		return
	# Deliberately NOT saved here. Writing on NEW GAME overwrote an existing run
	# before the player had taken a single action, so a mistaken tap destroyed it
	# with no confirmation. The run is committed at the first real milestone: a
	# day boundary, a finished match, or a breeding.
	Router.reset_to(Router.Screen.INTRO, {
		"new_game": true,
		"protagonist": int(DEFAULT_PROTAGONIST),
	})


func _on_continue_pressed() -> void:
	Sfx.confirm()
	_status.visible = false
	if not GameState.load_run():
		_fail("COULD NOT READ THE SAVE FILE.")
		_refresh_save_state()
		return
	_enter_run()


func _on_settings_pressed() -> void:
	Sfx.click()
	Router.push(Router.Screen.SETTINGS)


## Route straight to wherever the loaded run left off. A save taken during the
## intro is unlikely but cheap to honour.
func _enter_run() -> void:
	var phase := int(RunState.Phase.LADDER)
	if GameState.run != null:
		phase = int(GameState.run.phase)
	if phase == int(RunState.Phase.INTRO):
		Router.reset_to(Router.Screen.INTRO, {"resumed": true})
	else:
		Router.reset_to(Router.Screen.HOME)


func _fail(message: String) -> void:
	Sfx.cancel()
	_status.text = message
	_status.visible = true


func _set_confirm_visible(value: bool) -> void:
	_confirm.visible = value
	if value:
		_confirm_cancel.grab_focus()
	elif is_inside_tree():
		_new_game.grab_focus()
