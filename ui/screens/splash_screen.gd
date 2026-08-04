extends GameScreen

## The Monkey Mission splash — the app's first frame, ahead of the title.
##
## Four beats on one timeline (the storyboard this was built from lives in the
## "Monkey Mission" Figma file, page "Splash — Intro Sequence"):
##
##   0.0 – 1.2s  SPACE   starfield holds, nebula and planet drift (parallax)
##   1.2 – 2.0s  FLYBY   the ship streaks past the camera, left to right
##   2.0 – 2.4s  WIPE    its trail widens into a diagonal wipe
##   2.4s –      TITLE   wordmark, subtitle and a pulsing "TAP TO CONTINUE"
##
## A tap during the sequence skips to TITLE; a tap once it is at rest routes to
## the title screen. That is the whole screen — it owns no run state and calls
## nothing on GameState.
##
## ART IS PLACEHOLDER SHAPES: ellipses, rects, a triangle-fan starburst and a
## checkerboard, all in `_draw`. No image files. Colours come from Palette.

enum Beat { SPACE, FLYBY, WIPE, TITLE }

# --- timeline --------------------------------------------------------------
const FLYBY_AT := 1.2
const WIPE_AT := 2.0
const REST_AT := 2.4

# --- geometry, all fractions so the art survives an `expand` aspect ---------
## Height is the tight axis in landscape, so it is the art unit for anything
## that must not collide vertically; x positions are fractions of width.
const LOGO_CX := 0.37
const LOGO_CY := 0.47
const BURST_OUTER := 0.67
const BURST_INNER := 0.42
const BURST_POINTS := 16
const BLOB_R := Vector2(0.29, 0.27)   ## x of WIDTH, y of HEIGHT
const CHECKER_TOP := 0.886
const CHECKER_CELL := 0.057
const CHECKER_ROWS := 2

const PLANET_C := Vector2(0.047, 0.886)
const PLANET_R := 0.25
const MOON_C := Vector2(0.06, 0.16)
const MASCOT_C := Vector2(0.85, 0.55)
const MASCOT_R := 0.18
const CRUISER_C := Vector2(0.78, 0.21)

## Ship flight path during FLYBY, as fractions of width.
const SHIP_FROM := -0.25
const SHIP_TO := 1.35
const SHIP_Y := 0.5
const SHIP_UNIT := 0.11          ## ship "unit" as a fraction of height
const CRUISER_UNIT := 0.055

const STAR_COUNT := 90
const STAR_SEED := 20260804
## Parallax: nebula creeps, stars drift, in screen widths per second.
const NEBULA_DRIFT := 0.004
const STAR_DRIFT := 0.010

@onready var _wordmark_top: Label = $WordmarkTop
@onready var _wordmark_bottom: Label = $WordmarkBottom
@onready var _subtitle: Label = $Subtitle
@onready var _tap: Label = $TapPrompt

var _t: float = 0.0
## (x, y, radius) as fractions, plus a tint each. Generated once from a fixed
## seed so the starfield is identical on every launch.
var _stars: Array[Vector3] = []
var _star_tints: Array[Color] = []


func _ready() -> void:
	super()
	_seed_starfield()
	_apply_palette()
	resized.connect(_relayout)
	_relayout()


func on_enter(params: Dictionary) -> void:
	super(params)
	_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	var at_rest := beat_at(_t) == Beat.TITLE
	_wordmark_top.visible = at_rest
	_wordmark_bottom.visible = at_rest
	_subtitle.visible = at_rest
	_tap.visible = at_rest
	if at_rest:
		# The prompt pulses rather than blinks — a hard blink reads as a fault.
		_tap.modulate.a = 0.65 + 0.35 * (0.5 + 0.5 * sin((_t - REST_AT) * 3.2))
	queue_redraw()


## The one piece of logic here worth pinning down in a test.
static func beat_at(t: float) -> Beat:
	if t < FLYBY_AT:
		return Beat.SPACE
	if t < WIPE_AT:
		return Beat.FLYBY
	if t < REST_AT:
		return Beat.WIPE
	return Beat.TITLE


## Tap anywhere: skip the sequence, or leave for the title once it has landed.
## Handled in `_input` rather than `_gui_input` so a keyboard press counts too
## without this screen having to hold focus.
func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("mp_tap"):
		return
	get_viewport().set_input_as_handled()
	if beat_at(_t) != Beat.TITLE:
		Sfx.click()
		_t = REST_AT
		return
	Sfx.confirm()
	Router.replace(Router.Screen.TITLE)


# --- layout ----------------------------------------------------------------

func _apply_palette() -> void:
	for label in [_wordmark_top, _wordmark_bottom]:
		label.add_theme_color_override("font_outline_color", Palette.INK)
	_wordmark_top.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_wordmark_bottom.add_theme_color_override("font_color", Palette.LOGO_RED)
	_subtitle.add_theme_color_override("font_color", Palette.ACCENT_ALT)
	_tap.add_theme_color_override("font_color", Palette.INK_LIGHT)


func _relayout() -> void:
	var h := size.y
	if size.x <= 0.0 or h <= 0.0:
		return
	_place(_wordmark_top, 0.27, 0.150, int(round(h * 0.018)))
	_place(_wordmark_bottom, 0.44, 0.168, int(round(h * 0.020)))
	_place(_subtitle, 0.63, 0.064, 0)
	_place(_tap, 0.80, 0.059, 0)
	queue_redraw()


## Centres a label on the logo column at `cy` (fraction of height) with a font
## sized as a fraction of height, so the wordmark keeps its proportions when the
## viewport is wider or shorter than 1920x880.
func _place(label: Label, cy: float, font_fraction: float, outline: int) -> void:
	var h := size.y
	var box := h * font_fraction * 1.5
	label.anchor_left = 0.0
	label.anchor_right = 0.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = size.x * LOGO_CX - size.x * 0.5
	label.offset_right = size.x * LOGO_CX + size.x * 0.5
	label.offset_top = h * cy - box * 0.5
	label.offset_bottom = h * cy + box * 0.5
	label.add_theme_font_size_override("font_size", int(round(h * font_fraction)))
	label.add_theme_constant_override("outline_size", outline)


func _seed_starfield() -> void:
	var rng := MpRng.new(STAR_SEED)
	var tints: Array[Color] = [
		Palette.INK_LIGHT, Palette.WARN, Palette.ACCENT_ALT, Palette.CHECKER,
	]
	for i in STAR_COUNT:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.003, 0.010)))
		var tint: Color = tints[rng.randi_range(0, tints.size() - 1)]
		_star_tints.append(Color(tint, rng.randf_range(0.35, 1.0)))


# --- painting --------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var beat := beat_at(_t)
	_draw_space()
	if beat == Beat.FLYBY or beat == Beat.WIPE:
		_draw_flyby()
	if beat == Beat.WIPE:
		_draw_wipe((_t - WIPE_AT) / (REST_AT - WIPE_AT))
	if beat == Beat.TITLE:
		# Once the wipe has covered the screen there is nothing left to clip
		# against, so the title background is painted straight over the top.
		_draw_vertical_gradient(Palette.LOGO_BLUE, Palette.STAT_KNOWLEDGE)
		_draw_stars()
		_draw_title_art()


func _draw_space() -> void:
	_draw_vertical_gradient(Color("3b2a6b"), Palette.BG)
	var creep := _t * NEBULA_DRIFT * size.x
	_glow(Vector2(0.24, 0.12) * size + Vector2(creep, 0.0), size.y * 0.62, Palette.STAT_KNOWLEDGE, 0.55)
	_glow(Vector2(0.83, 0.62) * size - Vector2(creep, 0.0), size.y * 0.52, Palette.ACCENT_ALT, 0.40)
	_glow(Vector2(0.52, 0.94) * size, size.y * 0.48, Palette.ACCENT, 0.30)
	_glow(Vector2(0.02, 0.36) * size + Vector2(creep, 0.0), size.y * 0.46, Palette.LOGO_BLUE, 0.45)
	_draw_stars()
	_draw_planet()
	_ellipse(MOON_C * size, Vector2.ONE * size.y * 0.055, Palette.CHECKER)


## Godot's canvas draw calls have no gradient primitive, so this is a stack of
## flat bands. Twenty-four is enough that the seams do not show at phone size.
func _draw_vertical_gradient(top: Color, bottom: Color) -> void:
	var bands := 24
	var band_h := size.y / float(bands)
	for i in bands:
		var c := top.lerp(bottom, float(i) / float(bands - 1))
		draw_rect(Rect2(0.0, i * band_h, size.x, band_h + 1.0), c)


## A nebula: concentric discs of falling alpha, which is the cheap stand-in for
## the blur the storyboard uses.
func _glow(centre: Vector2, radius: float, color: Color, peak: float) -> void:
	# Enough rings that the steps read as a haze rather than as a target.
	var rings := 16
	for i in rings:
		var f := 1.0 - float(i) / float(rings)
		draw_circle(centre, radius * f, Color(color, peak / float(rings)))


func _draw_stars() -> void:
	var drift := _t * STAR_DRIFT
	for i in _stars.size():
		var s := _stars[i]
		var x := fposmod(s.x - drift, 1.0) * size.x
		draw_circle(Vector2(x, s.y * size.y), s.z * size.y, _star_tints[i])


func _draw_planet() -> void:
	var c := PLANET_C * size
	var r := PLANET_R * size.y
	draw_circle(c, r, Palette.STAT_POWER)
	draw_circle(c + Vector2(0.0, r * 0.45), r * 0.6, Palette.STAT_KNOWLEDGE)
	# The ring is an arc drawn under a squashed transform, so it reads as tilted.
	draw_set_transform(c, deg_to_rad(14.0), Vector2(r * 1.6, r * 0.42))
	draw_arc(Vector2.ZERO, 1.0, 0.0, TAU, 64, Palette.WARN, 0.09, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_flyby() -> void:
	var f := clampf((_t - FLYBY_AT) / (WIPE_AT - FLYBY_AT), 0.0, 1.6)
	var x := lerpf(SHIP_FROM, SHIP_TO, f) * size.x
	var y := size.y * SHIP_Y - size.y * 0.06 * f
	_draw_streaks(x, y)
	_draw_ship(Vector2(x, y), size.y * SHIP_UNIT)


## Warp trail: bars behind the ship, longest nearest its flight line.
func _draw_streaks(ship_x: float, ship_y: float) -> void:
	var rng := MpRng.new(STAR_SEED + 1)
	for i in 11:
		var offset := rng.randf_range(-0.30, 0.30) * size.y
		var length := rng.randf_range(0.18, 0.62) * size.x
		var thick := rng.randf_range(0.006, 0.016) * size.y
		var tail := ship_x - rng.randf_range(0.10, 0.28) * size.x
		var tint: Color = [Palette.INK_LIGHT, Palette.ACCENT_ALT, Palette.WARN, Palette.CHECKER][i % 4]
		draw_rect(Rect2(tail - length, ship_y + offset, length, thick), Color(tint, 0.55))


## The ship, drawn nose-right around `centre` in units of `u`. Saucer, hull,
## twin nacelles with glowing tips, and the banana emblem it is named for.
func _draw_ship(centre: Vector2, u: float) -> void:
	var outline := u * 0.07
	_pill(centre + Vector2(-4.0, -0.5) * u, centre + Vector2(-0.6, -0.5) * u, u * 0.26, Palette.PANEL_LIGHT, outline)
	_pill(centre + Vector2(-3.6, 1.1) * u, centre + Vector2(-0.2, 1.1) * u, u * 0.26, Palette.LOGO_BLUE, outline)
	draw_circle(centre + Vector2(-0.55, -0.5) * u, u * 0.30, Palette.ACCENT_ALT)
	draw_circle(centre + Vector2(-0.15, 1.1) * u, u * 0.30, Palette.ACCENT_ALT)
	_ellipse(centre + Vector2(-0.2, 0.55) * u, Vector2(1.5, 0.5) * u, Palette.PAPER, outline)
	draw_rect(Rect2(centre.x - 0.35 * u, centre.y - 0.1 * u, 0.5 * u, 0.8 * u), Palette.PAPER_EDGE)
	_ellipse(centre + Vector2(0.6, -0.35) * u, Vector2(2.2, 0.75) * u, Palette.PAPER_WHITE, outline)
	_ellipse(centre + Vector2(1.35, -0.75) * u, Vector2(0.75, 0.3) * u, Palette.LOGO_BLOB, outline * 0.6)
	for i in 3:
		draw_circle(centre + Vector2(0.6 + 0.55 * i, -0.2) * u, u * 0.13, Palette.ACCENT)
	_banana(centre + Vector2(-0.15, -0.45) * u, u * 0.42)


## A crescent: the fill disc, then the backing colour laid over it offset.
func _banana(centre: Vector2, r: float) -> void:
	draw_circle(centre, r, Palette.LOGO_BLOB)
	draw_circle(centre + Vector2(r * 0.42, -r * 0.34), r * 0.95, Palette.PAPER_WHITE)


## The wipe: a leaning quad sweeping left to right, carrying the title
## background in behind it. `p` runs 0 -> 1.
func _draw_wipe(p: float) -> void:
	var lean := size.y * 0.14
	var x := lerpf(-0.2, 1.25, clampf(p, 0.0, 1.0)) * size.x
	# The trailing edge sits off-screen left; both leading corners are held to
	# the right of it, because a quad that crosses itself fails triangulation
	# and Godot drops the whole polygon.
	var left := -lean * 2.0
	var quad := PackedVector2Array([
		Vector2(left, 0.0), Vector2(maxf(x + lean, left + 1.0), 0.0),
		Vector2(maxf(x - lean, left + 1.0), size.y), Vector2(left, size.y),
	])
	draw_colored_polygon(quad, Palette.LOGO_BLUE)
	var edge := PackedVector2Array([
		Vector2(x + lean, 0.0), Vector2(x + lean + size.y * 0.05, 0.0),
		Vector2(x - lean + size.y * 0.05, size.y), Vector2(x - lean, size.y),
	])
	draw_colored_polygon(edge, Palette.LOGO_BLOB)


func _draw_title_art() -> void:
	var centre := Vector2(size.x * LOGO_CX, size.y * LOGO_CY)
	_draw_starburst(centre, BURST_OUTER * size.y, BURST_INNER * size.y, BURST_POINTS, Palette.ACCENT)
	_ellipse(centre, Vector2(BLOB_R.x * size.x, BLOB_R.y * size.y), Palette.LOGO_BLOB, size.y * 0.012)
	_draw_subtitle_pill()
	_draw_ship(CRUISER_C * size, size.y * CRUISER_UNIT)
	_draw_mascot(MASCOT_C * size, MASCOT_R * size.y)
	_draw_checkerboard()


## Drawn as a fan of individual triangles around a filled hub rather than one
## polygon: draw_colored_polygon triangulates as a fan, which renders a concave
## star wrong. Same construction as the title screen's starburst.
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


func _draw_subtitle_pill() -> void:
	var h := size.y * 0.127
	var w := size.x * 0.41
	var c := Vector2(size.x * LOGO_CX, size.y * 0.63)
	_pill(c - Vector2(w * 0.5 - h * 0.5, 0.0), c + Vector2(w * 0.5 - h * 0.5, 0.0),
		h * 0.5, Palette.PANEL_DARK, size.y * 0.009)


## The crew, in one helmet: an astronaut monkey.
func _draw_mascot(c: Vector2, r: float) -> void:
	draw_circle(c, r + r * 0.05, Palette.INK)
	draw_circle(c, r, Palette.PAPER_WHITE)
	draw_circle(c, r * 0.89, Color(Palette.ACCENT_ALT, 0.45))
	for side in [-1.0, 1.0]:
		draw_circle(c + Vector2(side * r * 0.58, r * 0.06), r * 0.26, Palette.LOC_SHOP)
	draw_circle(c + Vector2(0.0, r * 0.02), r * 0.55, Palette.LOC_SHOP)
	_ellipse(c + Vector2(0.0, r * 0.33), Vector2(r * 0.36, r * 0.27), Palette.LOC_HOME)
	for side in [-1.0, 1.0]:
		_ellipse(c + Vector2(side * r * 0.22, -r * 0.12), Vector2(r * 0.08, r * 0.10), Palette.INK)
	_ellipse(c + Vector2(0.0, r * 0.44), Vector2(r * 0.14, r * 0.07), Palette.INK)


## The chunky checkerboard field, a recurring UI motif in the original.
func _draw_checkerboard() -> void:
	var cell := size.y * CHECKER_CELL
	if cell <= 0.0:
		return
	var top := size.y * CHECKER_TOP
	draw_rect(Rect2(0.0, top, size.x, size.y - top), Palette.LOGO_BLUE)
	var cols := int(ceil(size.x / cell))
	for row in CHECKER_ROWS:
		for col in cols:
			if (row + col) % 2 != 0:
				continue
			draw_rect(Rect2(col * cell, top + row * cell, cell, cell), Palette.CHECKER)


# --- shape helpers ---------------------------------------------------------

## An ellipse: a unit circle under a scaling transform, because Godot's canvas
## API only draws true circles.
func _ellipse(c: Vector2, r: Vector2, color: Color, outline: float = 0.0) -> void:
	if outline > 0.0:
		draw_set_transform(c, 0.0, r + Vector2(outline, outline))
		draw_circle(Vector2.ZERO, 1.0, Palette.INK)
	draw_set_transform(c, 0.0, r)
	draw_circle(Vector2.ZERO, 1.0, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A horizontal capsule between two centres — a rect with a disc on each end.
func _pill(from: Vector2, to: Vector2, half: float, color: Color, outline: float = 0.0) -> void:
	if outline > 0.0:
		_pill(from, to, half + outline, Palette.INK)
	draw_rect(Rect2(from.x, from.y - half, to.x - from.x, half * 2.0), color)
	draw_circle(from, half, color)
	draw_circle(to, half, color)
