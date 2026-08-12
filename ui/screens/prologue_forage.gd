extends GameScreen

## PROLOGUE 1/2 — THE LARDER. The drone runs the canopy collecting bananas.
##
## Design §1.5: the drone spends years after the cold open refitting a hull it
## was never issued. Before any of that it has to solve a simpler problem — it
## needs monkeys, and it has no hands to catch them with. So it does what it is
## actually built for: it goes and gets the bait.
##
## The minigame is a forward-flight lane runner. Trees rail past on both sides,
## bananas come out of the vanishing point, and you tap them before they blow
## past the camera. What you collect sizes the pile in `prologue_trap.gd`, which
## sizes the troop that comes for it — so the two beats are one sequence, not
## two unrelated toys.
##
## ART IS STAND-IN ART (ARCHITECTURE §17). Every sprite is a generated component
## from `assets/placeholder/prologue/`, deliberately one object per file so this
## screen can move them independently. A missing file degrades to a flat shape
## rather than crashing, which keeps the headless suite honest.
##
## The perspective is a one-line fake: everything has a depth `z` running 1.0
## (spawn) to 0.0 (camera plane), and `depth_scale` turns that into a size and a
## distance from the vanishing point. There is no camera and no 3D.

enum Phase { FLYING, FINISHED }

# --- flight ----------------------------------------------------------------
## Depth units per second. One banana therefore takes 1/SPEED seconds to travel
## from the vanishing point to the camera — long enough to see it, short enough
## that a lazy player misses.
const SPEED := 0.42
## Perspective strength. z=1 draws at 1/(1+K) of camera-plane size.
const DEPTH_K := 7.0
## How many bananas the flight throws at you, and how far apart in seconds.
const BANANA_COUNT := 18
const BANANA_EVERY := 0.72
const TREE_EVERY := 0.22
## Bananas nearer than this are past the camera and gone.
const CULL_Z := -0.05
## Too small to be a fair tap target. Taps at greater depth are ignored so the
## generous touch box below cannot be spammed at the vanishing point.
const TAPPABLE_Z := 0.8
## The tap box is grown to this before hit-testing — a banana at z=0.6 is only a
## few dozen pixels across and fingers are not.
const TAP_PAD := 44.0

# --- staging, all fractions so the art survives an `expand` aspect ----------
const HORIZON := 0.50
const TREE_HEIGHT := 2.6          ## camera-plane height, in screen heights
const TREE_LANE := 1.15
const TREE_BASE_Y := 0.52
const BANANA_HEIGHT := 0.34
const BANANA_LANE := 0.62
const BANANA_BAND := Vector2(-0.24, 0.26)
const FERN_HEIGHT := 0.46
const DRONE_HEIGHT := 0.20
const DRONE_CY := 0.72
const CANOPY_HEIGHT := 0.34
## Where the foliage-to-floor line sits in `forest_floor_bg.png`, as a fraction
## of that image. The backdrop is scaled so that line lands on our horizon,
## which is what makes a still background share a vanishing point with a moving
## foreground. Re-measure it if the art is replaced.
const BACKDROP_HORIZON := 0.72
## Seeded so the flight is the same every launch: this is a scripted opening,
## not a roguelike node, and a scripted opening that reshuffles feels broken.
const FLIGHT_SEED := 20260804

const ART := "res://assets/placeholder/prologue/%s.png"

@onready var _count: Label = $Count
@onready var _hint: Label = $Hint
@onready var _banner: Label = $Banner

var _phase: Phase = Phase.FLYING
var _t := 0.0
var _spawned := 0
var _collected := 0
## Each entry: {"z": float, "lane": float, "y": float, "pop": float}. `pop`
## counts up once collected and is the whole of the pickup animation.
var _bananas: Array[Dictionary] = []
## Each entry: {"z": float, "side": float, "scale": float}.
var _trees: Array[Dictionary] = []
var _next_tree := 0.0
var _tree_side := 1.0
var _rng := MpRng.new(FLIGHT_SEED)
var _tex_cache: Dictionary = {}


func _ready() -> void:
	super()
	for label in [_count, _hint, _banner]:
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)
		label.add_theme_color_override("font_outline_color", Palette.INK)
		label.add_theme_constant_override("outline_size", 10)
	_count.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_hint.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_banner.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_banner.visible = false
	_hint.text = "TAP THE BANANAS"
	_refresh_count()
	set_process(true)


func on_enter(params: Dictionary) -> void:
	super(params)
	_t = 0.0
	_phase = Phase.FLYING
	_rng = MpRng.new(FLIGHT_SEED)


# --- the fake perspective ----------------------------------------------------

## Size multiplier at depth `z`: 1.0 on the camera plane, falling away with
## depth. The single piece of maths the rest of the screen is built on.
static func depth_scale(z: float) -> float:
	return 1.0 / (1.0 + maxf(z, 0.0) * DEPTH_K)


## Where a point sitting `lane` half-widths off centre and `world_y` half-heights
## below the horizon lands on screen at depth `z`. Everything converges on the
## vanishing point as z grows, which is the entire illusion.
static func project(z: float, lane: float, world_y: float, screen: Vector2) -> Vector2:
	var s := depth_scale(z)
	return Vector2(
		screen.x * 0.5 + lane * screen.x * 0.5 * s,
		screen.y * HORIZON + world_y * screen.y * s)


# --- the flight --------------------------------------------------------------

func _process(delta: float) -> void:
	if _phase == Phase.FLYING:
		_t += delta
		_advance(delta)
		_spawn(delta)
		if _spawned >= BANANA_COUNT and _bananas.is_empty():
			_finish()
	queue_redraw()


func _advance(delta: float) -> void:
	var step := SPEED * delta
	for banana in _bananas:
		banana["z"] -= step
		if banana["pop"] > 0.0:
			banana["pop"] += delta
	for tree in _trees:
		tree["z"] -= step
	# Popped bananas leave on their animation, not on their depth, or a pickup at
	# the camera plane vanishes before the player sees it land.
	_bananas = _bananas.filter(func(b: Dictionary) -> bool:
		return b["pop"] < 0.35 and (b["pop"] > 0.0 or b["z"] > CULL_Z))
	_trees = _trees.filter(func(t: Dictionary) -> bool: return t["z"] > CULL_Z)


func _spawn(delta: float) -> void:
	_next_tree -= delta
	if _next_tree <= 0.0:
		_next_tree = TREE_EVERY
		# Strictly alternating, not random: a coin flip clumps, and three trees in
		# a row down one side stops reading as a corridor and starts reading as a
		# wall with a hole in it.
		_tree_side = -_tree_side
		_trees.append({
			"z": 1.0,
			"side": _tree_side,
			"scale": _rng.randf_range(0.82, 1.25),
		})
	# Bananas are on their own clock rather than the frame clock so the run is
	# the same length whatever the frame rate does.
	while _spawned < BANANA_COUNT and _t >= float(_spawned) * BANANA_EVERY:
		_spawned += 1
		_bananas.append({
			"z": 1.0,
			"lane": _rng.randf_range(-BANANA_LANE, BANANA_LANE),
			"y": _rng.randf_range(BANANA_BAND.x, BANANA_BAND.y),
			"pop": 0.0,
		})


func _finish() -> void:
	_phase = Phase.FINISHED
	_banner.text = "LARDER: %d" % _collected
	_banner.visible = true
	_hint.text = "TAP TO SET THE TRAP"
	Sfx.confirm()


# --- input -------------------------------------------------------------------

## Handled in `_input` rather than `_gui_input` so a tap anywhere counts without
## this screen having to own focus — same reason the splash does it.
func _input(event: InputEvent) -> void:
	var at: Variant = _tap_position(event)
	if at == null:
		return
	get_viewport().set_input_as_handled()
	if _phase == Phase.FINISHED:
		# Forward whatever the title handed us (new_game, protagonist) rather than
		# re-deriving it — the prologue sits in the middle of that route, it does
		# not own it.
		var params := enter_params.duplicate()
		params["bananas"] = _collected
		Router.replace(Router.Screen.PROLOGUE_TRAP, params)
		return
	_try_collect(at)


## The tap point, or null when this event is not a tap. Mouse and touch both
## carry a position; the keyboard fallback in `mp_tap` does not, so a space press
## aims at the middle of the screen and hits whatever is closest to it.
func _tap_position(event: InputEvent) -> Variant:
	if event is InputEventScreenTouch and event.pressed:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		return (event as InputEventMouseButton).position
	if event.is_action_pressed("mp_tap"):
		return size * 0.5
	return null


## Nearest banana first, so overlapping targets resolve to the one in front.
func _try_collect(at: Vector2) -> void:
	var best := -1
	for i in _bananas.size():
		var banana := _bananas[i]
		if banana["pop"] > 0.0 or banana["z"] > TAPPABLE_Z:
			continue
		if not _banana_box(banana).has_point(at):
			continue
		if best < 0 or banana["z"] < _bananas[best]["z"]:
			best = i
	if best < 0:
		Sfx.click()
		return
	_bananas[best]["pop"] = 0.001
	_collected += 1
	_refresh_count()
	Sfx.play(Sfx.Cue.FEED)


func _banana_box(banana: Dictionary) -> Rect2:
	var s := depth_scale(banana["z"])
	var centre := project(banana["z"], banana["lane"], banana["y"], size)
	var h := size.y * BANANA_HEIGHT * s
	return Rect2(centre - Vector2(h, h) * 0.5, Vector2(h, h)).grow(TAP_PAD)


## Outline every tap box the hit test would accept. Debug menu switch.
func _draw_colliders() -> void:
	for banana in _bananas:
		if banana["pop"] > 0.0 or banana["z"] > TAPPABLE_Z:
			continue
		draw_rect(_banana_box(banana), Color(Palette.WARN, 0.9), false, 2.0)


func _refresh_count() -> void:
	_count.text = "BANANAS  %d" % _collected


# --- painting ----------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_backdrop()
	_draw_canopy()
	# Far to near, so the near tree occludes the far one.
	for tree in _sorted(_trees):
		_draw_tree(tree)
	for banana in _sorted(_bananas):
		_draw_banana(banana)
	_draw_ferns()
	_draw_drone()
	if DebugMenu.show_colliders:
		_draw_colliders()


## A copy sorted far-to-near. Copied rather than sorted in place because the
## update order above depends on nothing and should stay that way.
func _sorted(items: Array[Dictionary]) -> Array[Dictionary]:
	var out := items.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["z"] > b["z"])
	return out


func _draw_backdrop() -> void:
	var horizon := size.y * HORIZON
	var bg := _tex("forest_floor_bg")
	if bg == null:
		_gradient(Rect2(0.0, 0.0, size.x, horizon),
			Palette.LOC_PARK.darkened(0.55), Palette.LOC_PARK)
	else:
		# Shared with the trap screen on purpose — the two beats happen in the same
		# clearing, so they should not look like two different forests.
		draw_texture_rect(bg, Rect2(0.0, 0.0, size.x, horizon / BACKDROP_HORIZON), false)
	_gradient(Rect2(0.0, horizon, size.x, size.y - horizon),
		Palette.LOC_SHOP.darkened(0.35), Palette.LOC_SHOP)
	# A haze disc on the vanishing point: sunlight coming down through the canopy,
	# and the thing that tells the player where the bananas will come from.
	for i in 10:
		var f := 1.0 - float(i) / 10.0
		draw_circle(Vector2(size.x * 0.5, horizon), size.y * 0.30 * f,
			Color(Palette.WARN, 0.035))


func _draw_canopy() -> void:
	var drift := sin(_t * 0.35) * size.x * 0.02
	_blit(_tex("canopy_leaves"), Vector2(size.x * 0.5 + drift, 0.0),
		size.y * CANOPY_HEIGHT, Palette.LOC_PARK, false, Vector2(0.5, 0.0))


func _draw_tree(tree: Dictionary) -> void:
	var s := depth_scale(tree["z"])
	var lane: float = tree["side"] * TREE_LANE
	var base := project(tree["z"], lane, TREE_BASE_Y, size)
	var h: float = size.y * TREE_HEIGHT * s * float(tree["scale"])
	_blit(_tex("tree_trunk"), base, h, Palette.LOC_SHOP.darkened(0.2),
		tree["side"] < 0.0, Vector2(0.5, 1.0))


func _draw_banana(banana: Dictionary) -> void:
	var s := depth_scale(banana["z"])
	var centre := project(banana["z"], banana["lane"], banana["y"], size)
	var h := size.y * BANANA_HEIGHT * s
	var tint := Color.WHITE
	if banana["pop"] > 0.0:
		# Collected: swell and fade on the spot. Cheap, and it reads as a pickup.
		var p: float = clampf(banana["pop"] / 0.35, 0.0, 1.0)
		h *= 1.0 + p * 0.9
		tint = Color(1.0, 1.0, 1.0, 1.0 - p)
		centre.y -= size.y * 0.06 * p
	else:
		centre.y += sin(_t * 3.0 + banana["lane"] * 6.0) * size.y * 0.012 * s
	_blit(_tex("banana_bunch"), centre, h, Palette.LOGO_BLOB, false, Vector2(0.5, 0.5), tint)


## Foreground undergrowth blurring past the bottom corners. Purely a speed cue —
## nothing is ever collected down here.
func _draw_ferns() -> void:
	var h := size.y * FERN_HEIGHT
	for i in 4:
		var phase := fposmod(_t * 0.9 + float(i) * 0.25, 1.0)
		var x := lerpf(0.5, 1.9, phase) * size.x * (1.0 if i % 2 == 0 else -1.0)
		if i % 2 != 0:
			x += size.x
		_blit(_tex("fern_bush"), Vector2(x, size.y + h * 0.15), h * (0.6 + phase),
			Palette.LOC_PARK, i % 2 != 0, Vector2(0.5, 1.0))


func _draw_drone() -> void:
	var bob := sin(_t * 2.4) * size.y * 0.015
	_blit(_tex("drone"), Vector2(size.x * 0.5, size.y * DRONE_CY + bob),
		size.y * DRONE_HEIGHT, Palette.PANEL_LIGHT)


# --- drawing helpers ---------------------------------------------------------

## Draw `tex` at `height`, keeping its aspect, anchored by `pivot` (0,0 = the
## centre is the top-left of the box; 0.5,0.5 = centred; 0.5,1.0 = stood on it).
##
## A missing texture falls back to a flat ellipse in `fallback`. That is not
## defensive padding — the headless suite mounts this screen with no imported
## assets, and a screen that cannot be mounted cannot be tested.
func _blit(tex: Texture2D, at: Vector2, height: float, fallback: Color,
		flip := false, pivot := Vector2(0.5, 0.5), tint := Color.WHITE) -> void:
	if height <= 0.0:
		return
	var aspect := 1.0
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var box := Rect2(at - Vector2(height * aspect * pivot.x, height * pivot.y),
		Vector2(height * aspect, height))
	if tex == null:
		draw_set_transform(box.get_center(), 0.0, box.size * 0.5)
		draw_circle(Vector2.ZERO, 1.0, Color(fallback, tint.a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if flip:
		# Negate the width and LEAVE the position alone: draw_texture_rect
		# normalises a negative size by flipping the UVs and taking the absolute
		# width, without moving the rect. Offsetting the position first — the
		# obvious way to write this — shifts every mirrored sprite a full width to
		# the right, which quietly threw the whole left-hand tree rail off screen.
		box.size.x = -box.size.x
	draw_texture_rect(tex, box, false, tint)


func _tex(art_name: String) -> Texture2D:
	if _tex_cache.has(art_name):
		return _tex_cache[art_name]
	var path := ART % art_name
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[art_name] = tex
	return tex


## Godot's canvas API has no gradient primitive, so this is a stack of bands —
## the same trick the splash screen uses.
func _gradient(box: Rect2, top: Color, bottom: Color) -> void:
	var bands := 16
	var band_h := box.size.y / float(bands)
	for i in bands:
		draw_rect(Rect2(box.position.x, box.position.y + i * band_h, box.size.x, band_h + 1.0),
			top.lerp(bottom, float(i) / float(bands - 1)))
