extends GameScreen

## PROLOGUE 2/2 — THE TRAP. The drone catches its first crew.
##
## Design §1.5: the drone has no hands, so it cannot catch a monkey. What it has
## is a heap of bananas from `prologue_forage.gd` and a salvaged antenna dish
## propped on a stick. That is the whole apparatus, and it is deliberately the
## crudest object in the game — the drone is a surveyor, not a trapper, and this
## is its first attempt at anything outside its job description.
##
## The read is a timing one. A monkey that has settled at the pile drifts in and
## out of the dish's footprint while it eats, and the wave only lingers for so
## long, so the player is picking a moment rather than waiting for a guaranteed
## one. Bananas collected in the flight size the troop that turns up: a bigger
## pile is a bigger crowd, which is the only place the first minigame's score
## goes.
##
## Waves run until the crew is full. There is no fail state — the drone has
## nothing else to do and nowhere else to be, and a prologue that can be lost is
## a prologue that gets replayed instead of played.
##
## ART IS STAND-IN ART (ARCHITECTURE §17): generated components from
## `assets/placeholder/prologue/`, one object per file, missing files degrading
## to flat shapes so the headless suite can still mount this screen.

enum Phase { BAITING, DROPPING, LANDED, RESETTING, DONE }
enum MonkeyState { APPROACH, FEED, FLEE }

## Design §2.5: a voyage starts with four crew. That is what the prologue owes
## the rest of the game, so it is what the waves run until.
const TARGET_CREW := 4
## Crew capacity is 6 (§2.5) — a last-wave overcatch is a nice surprise, not a
## bug, but it stops at the pen's actual capacity.
const MAX_CREW := 6

# --- staging, fractions of the screen --------------------------------------
const GROUND_Y := 0.78
const PILE_X := 0.5
const PILE_HEIGHT := 0.20
## Half the dish's footprint, in fractions of width. A monkey inside this band
## when the dish lands is caught — and the dish is DRAWN from this number rather
## than sized independently, so what the player sees is what the rule uses.
const DISH_HALF := 0.105
const ARM_HEIGHT := 0.13          ## how high the propped rim sits, of height
## Tall enough to visibly reach the lifted rim — a prop the player cannot see is
## a prop they will not miss when it goes.
const STICK_HEIGHT := 0.22
const MONKEY_HEIGHT := 0.22
const DRONE_HEIGHT := 0.16
## The dish art is a three-quarter view with its mouth facing down and left, so
## it needs rolling clockwise to sit as a dome on the ground. Propped, it lifts
## its near rim off the stick.
const TILT_ARMED := 12.0
const TILT_LANDED := 38.0

# --- timing ------------------------------------------------------------------
const DROP_TIME := 0.30
const LAND_SETTLE := 1.1
const RESET_TIME := 0.9
const WALK_SPEED := 0.115         ## screen widths per second
const FLEE_MULTIPLIER := 2.1
## How long a wave feeds before it wanders off. Each wave is warier than the
## last, so a player who fluffs the first drop is not offered the same easy
## second one — the troop learns even though nothing else in the prologue does.
const LINGER_BASE := 6.5
const LINGER_DECAY := 1.1
const LINGER_MIN := 2.2
## While feeding, a monkey drifts around its chosen spot. This is the timing
## read: the footprint fills and empties instead of filling once and staying.
const MILL_AMPLITUDE := 0.055
const MILL_PERIOD := 2.3

const ART := "res://assets/placeholder/prologue/%s.png"
const TRAP_SEED := 20260805

@onready var _caught_label: Label = $Caught
@onready var _hint: Label = $Hint
@onready var _banner: Label = $Banner

var _phase: Phase = Phase.BAITING
var _t := 0.0
var _phase_t := 0.0
var _wave := 0
var _caught := 0
var _last_catch := 0
var _bananas := 0
## Each entry: {"x": float, "dir": float, "stop": float, "state": int,
## "timer": float, "phase": float}. `x` and `stop` are fractions of width.
var _monkeys: Array[Dictionary] = []
var _rng := MpRng.new(TRAP_SEED)
var _tex_cache: Dictionary = {}


func _ready() -> void:
	super()
	for label in [_caught_label, _hint, _banner]:
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)
		label.add_theme_color_override("font_outline_color", Palette.INK)
		label.add_theme_constant_override("outline_size", 10)
	_caught_label.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_hint.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_banner.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_banner.visible = false
	set_process(true)


func on_enter(params: Dictionary) -> void:
	super(params)
	_bananas = int(params.get("bananas", 0))
	_rng = MpRng.new(TRAP_SEED)
	_refresh_labels()
	_begin_wave()


# --- the catch ---------------------------------------------------------------

## Which monkeys are under a dish centred on `dish_x` with half-width `half`.
## The one rule of this screen, pulled out so a test can hold it still.
static func caught_indices(dish_x: float, half: float, xs: PackedFloat32Array) -> PackedInt32Array:
	var hits := PackedInt32Array()
	for i in xs.size():
		if absf(xs[i] - dish_x) <= half:
			hits.append(i)
	return hits


## How many monkeys a pile this size is worth attracting. More bananas, more
## troop — the only thing the flight's score feeds.
static func wave_size(bananas: int) -> int:
	return clampi(2 + int(bananas / 7.0), 2, 4)


func _begin_wave() -> void:
	_wave += 1
	_phase = Phase.BAITING
	_phase_t = 0.0
	_monkeys.clear()
	var count := mini(wave_size(_bananas), MAX_CREW - _caught)
	for i in count:
		var side := 1.0 if i % 2 == 0 else -1.0
		_monkeys.append({
			# Staggered off both edges so they trickle in rather than march.
			"x": PILE_X + side * (0.62 + 0.18 * float(i)),
			"dir": -side,
			# Spread deliberately narrower than the dish's own half-width, so a
			# patient player can get two or three under it at once. Wider than this
			# and every wave is worth exactly one monkey, which turns a timing read
			# into a queue.
			"stop": PILE_X + side * _rng.randf_range(0.02, 0.14),
			"state": MonkeyState.APPROACH,
			"timer": maxf(LINGER_BASE - LINGER_DECAY * float(_wave - 1), LINGER_MIN),
			"phase": _rng.randf_range(0.0, TAU),
		})
	_hint.text = "TAP TO DROP THE DISH"


func _process(delta: float) -> void:
	_t += delta
	_phase_t += delta
	match _phase:
		Phase.BAITING:
			_step_monkeys(delta)
			if _monkeys.is_empty():
				# The whole troop wandered off un-dropped-on. Re-bait and wait.
				_begin_wave()
		Phase.DROPPING:
			if _phase_t >= DROP_TIME:
				_land()
		Phase.LANDED:
			_step_monkeys(delta)
			if _phase_t >= LAND_SETTLE:
				_after_landing()
		Phase.RESETTING:
			if _phase_t >= RESET_TIME:
				_begin_wave()
		Phase.DONE:
			pass
	queue_redraw()


func _step_monkeys(delta: float) -> void:
	for monkey in _monkeys:
		match int(monkey["state"]):
			MonkeyState.APPROACH:
				monkey["x"] += monkey["dir"] * WALK_SPEED * delta
				# `dir` points at the pile, so "arrived" is having passed the spot
				# it picked, whichever side it came in from.
				if (monkey["x"] - monkey["stop"]) * monkey["dir"] >= 0.0:
					monkey["state"] = MonkeyState.FEED
			MonkeyState.FEED:
				monkey["timer"] -= delta
				if monkey["timer"] <= 0.0:
					monkey["state"] = MonkeyState.FLEE
					monkey["dir"] = -monkey["dir"]
			MonkeyState.FLEE:
				monkey["x"] += monkey["dir"] * WALK_SPEED * FLEE_MULTIPLIER * delta
	_monkeys = _monkeys.filter(func(m: Dictionary) -> bool:
		return int(m["state"]) != MonkeyState.FLEE or absf(m["x"] - PILE_X) < 1.0)


## Where a monkey actually stands this frame — a feeding one mills around the
## spot it picked, which is what makes the drop a timing decision.
func _monkey_x(monkey: Dictionary) -> float:
	if int(monkey["state"]) != MonkeyState.FEED:
		return monkey["x"]
	return monkey["x"] + sin(_t * TAU / MILL_PERIOD + monkey["phase"]) * MILL_AMPLITUDE


func _land() -> void:
	var xs := PackedFloat32Array()
	for monkey in _monkeys:
		xs.append(_monkey_x(monkey))
	var hits := caught_indices(PILE_X, DISH_HALF, xs)
	# Never overfill the pen: the dish lands on whoever is under it, but only the
	# first MAX_CREW - _caught of them are kept.
	_last_catch = mini(hits.size(), MAX_CREW - _caught)
	_caught += _last_catch
	# Caught monkeys leave the list — they are under the dish now, and the dish
	# is drawn over the ground. Everyone still standing bolts.
	var keep: Array[Dictionary] = []
	for i in _monkeys.size():
		if hits.has(i):
			continue
		var monkey := _monkeys[i]
		monkey["state"] = MonkeyState.FLEE
		monkey["dir"] = signf(_monkey_x(monkey) - PILE_X)
		if monkey["dir"] == 0.0:
			monkey["dir"] = 1.0
		keep.append(monkey)
	_monkeys = keep
	_phase = Phase.LANDED
	_phase_t = 0.0
	_refresh_labels()
	Sfx.play(Sfx.Cue.KNOCKDOWN if _last_catch > 0 else Sfx.Cue.CANCEL)


func _after_landing() -> void:
	if _caught >= TARGET_CREW:
		_finish()
		return
	_phase = Phase.RESETTING
	_phase_t = 0.0
	_hint.text = "THEY WILL COME BACK. THEY ALWAYS COME BACK."


func _finish() -> void:
	_phase = Phase.DONE
	_banner.text = "A CREW OF %d" % _caught
	_banner.visible = true
	_hint.text = "TAP TO CONTINUE"
	Sfx.confirm()


func _refresh_labels() -> void:
	_caught_label.text = "CREW  %d / %d" % [_caught, TARGET_CREW]
	if _phase == Phase.LANDED:
		_hint.text = "CAUGHT %d" % _last_catch if _last_catch > 0 else "NOTHING UNDER IT."


# --- input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("mp_tap"):
		return
	get_viewport().set_input_as_handled()
	if _phase == Phase.DONE:
		_leave()
		return
	if _phase != Phase.BAITING:
		return
	_phase = Phase.DROPPING
	_phase_t = 0.0
	Sfx.click()


func _leave() -> void:
	if GameState.has_run() and GameState.run != null:
		GameState.run.set_flag("seen_prologue")
	var params := enter_params.duplicate()
	params["crew"] = _caught
	Router.replace(Router.Screen.INTRO, params)


# --- painting ----------------------------------------------------------------

## 0.0 propped, 1.0 flat on the ground. Everything the dish does is this number.
func _dish_fall() -> float:
	match _phase:
		Phase.DROPPING:
			# Eased in, because a dish held by a stick does not start falling
			# gently — it starts falling and then falls faster.
			var p := clampf(_phase_t / DROP_TIME, 0.0, 1.0)
			return p * p
		Phase.LANDED, Phase.DONE:
			return 1.0
		Phase.RESETTING:
			return 1.0 - clampf(_phase_t / RESET_TIME, 0.0, 1.0)
		_:
			return 0.0


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_backdrop()
	_draw_pile()
	for monkey in _monkeys:
		_draw_monkey(monkey)
	_draw_trap()
	_draw_drone()
	if DebugMenu.show_colliders:
		_draw_colliders()


func _draw_backdrop() -> void:
	var bg := _tex("forest_floor_bg")
	if bg != null:
		draw_texture_rect(bg, Rect2(Vector2.ZERO, size), false)
		return
	var horizon := size.y * GROUND_Y
	_gradient(Rect2(0.0, 0.0, size.x, horizon), Palette.LOC_PARK.darkened(0.5), Palette.LOC_PARK)
	draw_rect(Rect2(0.0, horizon, size.x, size.y - horizon), Palette.LOC_SHOP)


func _draw_pile() -> void:
	# The pile is the bait and the score: a fat haul reads as a fat heap.
	var scale := 0.7 + 0.03 * float(_bananas)
	_blit(_tex("banana_pile"), Vector2(size.x * PILE_X, size.y * GROUND_Y),
		size.y * PILE_HEIGHT * clampf(scale, 0.7, 1.5), Palette.LOGO_BLOB,
		false, Vector2(0.5, 1.0))


func _draw_monkey(monkey: Dictionary) -> void:
	var x := _monkey_x(monkey) * size.x
	var y := size.y * GROUND_Y
	var walking := int(monkey["state"]) != MonkeyState.FEED
	# The two generated poses ARE the walk cycle. Feeding monkeys hold one pose
	# and bob instead, which is enough to tell the two states apart at a glance.
	var frame := "monkey_walk_a"
	if walking:
		frame = "monkey_walk_a" if fmod(_t * 6.0, 2.0) < 1.0 else "monkey_walk_b"
	else:
		y -= absf(sin(_t * 4.0 + monkey["phase"])) * size.y * 0.02
	# The art faces right, so a monkey travelling left is drawn mirrored.
	_blit(_tex(frame), Vector2(x, y), size.y * MONKEY_HEIGHT, Palette.LOC_SHOP,
		monkey["dir"] < 0.0, Vector2(0.5, 1.0))


func _draw_trap() -> void:
	var fall := _dish_fall()
	var lift := size.y * ARM_HEIGHT * (1.0 - fall)
	var centre := Vector2(size.x * PILE_X, size.y * GROUND_Y - lift)
	if fall < 1.0:
		# The prop only exists while it is propping, and it stands at the rim the
		# tilt lifts — outside the pile, where the player can see it go.
		_blit(_tex("prop_stick"),
			Vector2(centre.x - size.x * DISH_HALF * 0.95, size.y * GROUND_Y),
			size.y * STICK_HEIGHT, Palette.LOC_SHOP.darkened(0.3), false, Vector2(0.5, 1.0))
	var tex := _tex("trap_dish")
	# Width comes from the catch rule, not from a separate art constant, so the
	# footprint the player reads is the footprint `caught_indices` uses.
	var width := size.x * DISH_HALF * 2.0
	var aspect := 1.0
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var height := width / aspect
	var tilt := deg_to_rad(lerpf(TILT_ARMED, TILT_LANDED, fall))
	if _phase == Phase.LANDED and _phase_t < 0.35:
		# A dish this size does not stop dead. Damped rock on the thud.
		tilt += deg_to_rad(5.0 * sin(_phase_t * 34.0) * (1.0 - _phase_t / 0.35))
	draw_set_transform(centre, tilt, Vector2.ONE)
	var box := Rect2(Vector2(-width * 0.5, -height * 0.86), Vector2(width, height))
	if tex != null:
		draw_texture_rect(tex, box, false)
	else:
		draw_rect(box, Palette.PANEL_LIGHT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The dish's catch band and each monkey's current tap-x. What `caught_indices`
## actually checks, drawn on top of everything so a mistimed drop is legible.
func _draw_colliders() -> void:
	var band_x := (PILE_X - DISH_HALF) * size.x
	var band_w := DISH_HALF * 2.0 * size.x
	var ground := size.y * GROUND_Y
	var band := Rect2(band_x, ground - size.y * 0.04, band_w, size.y * 0.08)
	draw_rect(band, Color(Palette.WARN, 0.25))
	draw_rect(band, Color(Palette.WARN, 0.9), false, 2.0)
	for monkey in _monkeys:
		var mx := _monkey_x(monkey) * size.x
		var caught := absf(_monkey_x(monkey) - PILE_X) <= DISH_HALF
		var tint := Color(Palette.WARN if caught else Palette.INK_LIGHT, 0.9)
		draw_line(Vector2(mx, ground - size.y * MONKEY_HEIGHT), Vector2(mx, ground), tint, 2.0)
		draw_circle(Vector2(mx, ground), 6.0, tint)


## The drone holds the line off to one side of the trap — never over it, or it
## reads as part of the dish — and drifts further out once the dish is down.
func _draw_drone() -> void:
	var aside := size.x * lerpf(0.20, 0.30, _dish_fall())
	var bob := sin(_t * 2.2) * size.y * 0.012
	_blit(_tex("drone"),
		Vector2(size.x * PILE_X - aside, size.y * (GROUND_Y - 0.40) + bob),
		size.y * DRONE_HEIGHT, Palette.PANEL_LIGHT)


# --- drawing helpers ---------------------------------------------------------
# Same pair as prologue_forage.gd. Deliberately duplicated rather than shared:
# it is nine lines, the two screens are the only callers, and a `ui/components/`
# helper for it would be a bigger thing to maintain than the thing it saves.

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


func _gradient(box: Rect2, top: Color, bottom: Color) -> void:
	var bands := 16
	var band_h := box.size.y / float(bands)
	for i in bands:
		draw_rect(Rect2(box.position.x, box.position.y + i * band_h, box.size.x, band_h + 1.0),
			top.lerp(bottom, float(i) / float(bands - 1)))
