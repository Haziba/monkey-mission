extends GameScreen

## STABLE — the persistent home layer between voyages (design §9 #12).
##
## A ramshackle stable built of technology parts and jungle salvage. Four
## facilities the monkeys use, and a jungle gym they play on. Which facility
## each monkey drifts to is driven by a local time-of-day clock: sleep at
## night, cafeteria at meal times, barracks or jungle gym in between.
##
## SCOPE: this is the stable *view* — the visual layer for the between-voyage
## home. It does not touch `Stable` core state (which is deferred to phase 7,
## `MISSION-ARCHITECTURE.md` §9). It reads the run's roster + active_monkey if
## present, and otherwise takes a `seed_monkeys: int` param — the debug menu
## uses that route to jump straight in with a stable of five.
##
## ART: a hero backdrop illustration (`assets/placeholder/stable/hero.png`,
## gpt-image-1 generated to match the palette register) is drawn COVERED across
## the viewport, then tinted by the time-of-day clock so the same image reads
## as morning, midday, dusk and night. Sun, moon, stars and the monkeys are
## drawn on top of it. The old code-drawn shacks were retired when the hero
## landed — see git log for the reference frame.

const HERO_TEXTURE: Texture2D = preload("res://assets/placeholder/stable/hero.png")

## Monkey sprite sheets: 2 frames per action, laid out side by side. One
## visual type — every species renders as the same orange monkey. If per-type
## sprites come back, restore the type_key indirection and this becomes nested.
const MONKEY_SPRITES: Dictionary = {
	"walk":  preload("res://assets/placeholder/stable/monkey/orange_walk.png"),
	"sleep": preload("res://assets/placeholder/stable/monkey/orange_sleep.png"),
	"eat":   preload("res://assets/placeholder/stable/monkey/orange_eat.png"),
	"train": preload("res://assets/placeholder/stable/monkey/orange_train.png"),
	"play":  preload("res://assets/placeholder/stable/monkey/orange_play.png"),
}

## Sprite dest height as a fraction of viewport height. Aspect is read per
## texture at draw time because normalise_monkey_sheets.py trims each sheet
## to its own bounding box.
const SPRITE_H := 0.24

## Animation: 2 frames per action, ping-pong at this cadence.
const FRAME_MS := 380

## Three stacked hammock slots at the sleeping quarters, in viewport-y
## fractions. Monkeys assigned to sleep pick a slot by their index mod 3, so
## the fourth and fifth double up in the top and middle hammocks.
const HAMMOCK_YS: Array = [0.58, 0.68, 0.78]
const HAMMOCK_HALF_WIDTH := 0.055    ## fraction of viewport width per hammock

# --- geometry, all fractions of the viewport so it survives an aspect stretch --
## Where a monkey's feet sit — measured against the hero's grass strip. If the
## hero art is swapped, retune this and FACILITY_X to the new composition.
const GROUND_Y := 0.80

## Four facilities, positioned left-to-right along the stable floor.
enum Facility { SLEEP, CAFETERIA, BARRACKS, GYM }

const FACILITY_LABELS: Dictionary = {
	Facility.SLEEP: "SLEEPING QUARTERS",
	Facility.CAFETERIA: "CAFETERIA",
	Facility.BARRACKS: "BARRACKS",
	Facility.GYM: "JUNGLE GYM",
}

## Facility -> centre x (fraction of width). Measured against the hero art:
## sleeping quarters on the left, cafeteria middle-left, barracks middle-right,
## jungle gym on the right. Retune if the backdrop changes.
const FACILITY_X: Dictionary = {
	Facility.SLEEP: 0.16,
	Facility.CAFETERIA: 0.40,
	Facility.BARRACKS: 0.60,
	Facility.GYM: 0.82,
}

const FACILITY_ACTION: Dictionary = {
	Facility.SLEEP:     "sleep",
	Facility.CAFETERIA: "eat",
	Facility.BARRACKS:  "train",
	Facility.GYM:       "play",
}

## Time-of-day runs 0..1 and loops. Real-time cycle length in seconds — long
## enough to enjoy, short enough that the player sees every phase in one sit.
const DAY_SECONDS := 90.0

## Phases of the local clock. Each monkey picks its target facility from these
## bands. Wraparound: NIGHT spans 0.78..1.0 and 0.0..0.12.
const PHASE_DAWN := 0.12
const PHASE_MORNING := 0.28
const PHASE_MIDDAY := 0.55
const PHASE_EVENING := 0.68
const PHASE_DUSK := 0.78

## Time-of-day tints applied to the hero backdrop's `modulate`. The image is
## painted in daylight, so DAY is neutral white and the others cool/warm it.
const TINT_NIGHT := Color(0.32, 0.42, 0.72)
const TINT_DAWN := Color(1.05, 0.82, 0.68)
const TINT_DAY := Color(1.0, 1.0, 1.0)
const TINT_DUSK := Color(1.05, 0.62, 0.42)

const MONKEY_SPEED := 0.09   ## fraction of width per second

## Wander radius around a facility target, so five monkeys don't stack.
const WANDER_RADIUS := 0.06

## Chatter above a monkey's head, occasionally.
const CHATTER_CHANCE := 0.004
const CHATTER_SECONDS := 1.6

var _time: float = 0.15   ## start at dawn, so the first frame is legible
var _monkeys: Array = []
## Menu state.
var _menu_open: bool = false
var _menu_root: Control = null
## Rebuilt on resize; cached so we do not rebuild every frame.
var _viewport := Vector2.ZERO

## Names for synthesised monkeys when the debug menu jumps here with no run.
const DEBUG_NAMES := ["Freddy", "Pizza", "Lemon", "Dragon", "Cookie", "Tomato", "Betty", "Jimbo"]


func _ready() -> void:
	super()
	set_process(true)
	set_process_unhandled_input(false)
	_build_menu_button()
	_build_menu_panel()
	resized.connect(_on_resized)


func on_enter(params: Dictionary) -> void:
	super(params)
	_populate_monkeys(int(params.get("seed_monkeys", 0)))
	_on_resized()


func _process(delta: float) -> void:
	_time = fposmod(_time + delta / DAY_SECONDS, 1.0)
	_step_monkeys(delta)
	queue_redraw()


func _on_resized() -> void:
	_viewport = size
	for m in _monkeys:
		# First layout: park monkeys at their starting facility rather than
		# have them all sprint from (0,0) into view.
		if m.get("placed", false):
			continue
		m["pos"] = _pick_wander_point(m["target_facility"], int(m["index"]))
		m["target_pos"] = m["pos"]
		m["placed"] = true


# --- population -----------------------------------------------------------

func _populate_monkeys(_seed_count: int) -> void:
	# Exactly one monkey lives in the stable for now — the active monkey when
	# a run is behind the screen, otherwise a stand-in for the debug jump.
	_monkeys.clear()
	if GameState.has_run() and GameState.monkey() != null:
		var active := GameState.monkey()
		_monkeys.append(_make_visual(active.monkey_name, active.species_type))
	else:
		_monkeys.append(_make_visual(DEBUG_NAMES[0], SpeciesDb.default_type()))


func _make_visual(name: String, _species_type: int) -> Dictionary:
	return {
		"name": name,
		"index": _monkeys.size(),   ## slot for hammock assignment + jitter seed
		"pos": Vector2.ZERO,
		"target_pos": Vector2.ZERO,
		"target_facility": _pick_target_for_phase(current_phase()),
		"chatter_until": 0.0,
		"chatter_text": "",
		"placed": false,
		"target_phase": Phase.NIGHT,
	}


# --- clock ----------------------------------------------------------------

## Rough phase of the local clock, used to drive monkey routing. Not the same
## thing as `DayCycle.Slot` — this is the visible time-of-day.
enum Phase { NIGHT, DAWN, MORNING, MIDDAY, EVENING, DUSK }


func current_phase() -> Phase:
	if _time < PHASE_DAWN or _time >= PHASE_DUSK:
		# 0..PHASE_DAWN is post-dawn but the sky is still dark: bucket dawn.
		if _time < PHASE_DAWN:
			return Phase.DAWN
		if _time >= PHASE_DUSK:
			# Dusk band → sky is orange → after it, sleep.
			return Phase.DUSK if _time < 0.86 else Phase.NIGHT
		return Phase.NIGHT
	if _time < PHASE_MORNING:
		return Phase.MORNING
	if _time < PHASE_MIDDAY:
		return Phase.MIDDAY
	if _time < PHASE_EVENING:
		return Phase.MIDDAY
	return Phase.EVENING


func phase_label() -> String:
	match current_phase():
		Phase.NIGHT: return "NIGHT"
		Phase.DAWN: return "DAWN"
		Phase.MORNING: return "MORNING"
		Phase.MIDDAY: return "MIDDAY"
		Phase.EVENING: return "EVENING"
		Phase.DUSK: return "DUSK"
	return ""


# --- monkeys --------------------------------------------------------------

## Where should a monkey be right now? At meal times, the cafeteria. At night,
## bed. During the working day, they split between barracks (training) and
## jungle gym (play) with a per-monkey lean so it doesn't all clump.
func _pick_target_for_phase(phase: Phase) -> Facility:
	match phase:
		Phase.NIGHT, Phase.DAWN:
			return Facility.SLEEP
		Phase.MORNING, Phase.EVENING:
			return Facility.CAFETERIA
		Phase.MIDDAY:
			return Facility.GYM if randi() % 2 == 0 else Facility.BARRACKS
		Phase.DUSK:
			return Facility.CAFETERIA
	return Facility.GYM


func _pick_wander_point(target: Facility, monkey_index: int = -1) -> Vector2:
	# Sleeping is a deterministic bunk assignment, not a wander — every monkey
	# picks the same hammock every night so the stack reads as beds, not chaos.
	if target == Facility.SLEEP and monkey_index >= 0:
		return _hammock_slot(monkey_index)
	# A random offset around the facility centre, so five monkeys spread out
	# instead of clipping into one another.
	var cx: float = FACILITY_X[target]
	var jitter_x := randf_range(-WANDER_RADIUS, WANDER_RADIUS)
	var jitter_y := randf_range(-0.03, 0.03)
	# Jungle gym gets vertical spread so monkeys read as climbing on it.
	if target == Facility.GYM:
		jitter_y = randf_range(-0.10, 0.02)
	return Vector2(cx + jitter_x, GROUND_Y + jitter_y)


func _hammock_slot(monkey_index: int) -> Vector2:
	var cx: float = FACILITY_X[Facility.SLEEP]
	var slot := monkey_index % HAMMOCK_YS.size()
	return Vector2(cx, float(HAMMOCK_YS[slot]))


func _step_monkeys(delta: float) -> void:
	if _viewport.x <= 0.0 or _viewport.y <= 0.0:
		return
	var phase := current_phase()
	for m in _monkeys:
		# Reassign facility only when the phase itself has changed — otherwise
		# `_pick_target_for_phase`'s MIDDAY coin flip would flip every frame and
		# the crew would jitter between barracks and gym instead of arriving.
		if phase != m["target_phase"]:
			m["target_phase"] = phase
			m["target_facility"] = _pick_target_for_phase(phase)
			m["target_pos"] = _pick_wander_point(m["target_facility"], int(m["index"]))
		elif m["pos"].distance_to(m["target_pos"]) < 0.01:
			m["target_pos"] = _pick_wander_point(m["target_facility"], int(m["index"]))
		# Move toward target_pos in fraction-space at MONKEY_SPEED.
		var to: Vector2 = m["target_pos"] - m["pos"]
		var step := MONKEY_SPEED * delta
		if to.length() <= step:
			m["pos"] = m["target_pos"]
		else:
			m["pos"] = (m["pos"] as Vector2) + to.normalized() * step
		# Chatter: pick a random phrase, hold it briefly above the head.
		if _time < 0.78 and randf() < CHATTER_CHANCE:
			m["chatter_until"] = 1.0
			m["chatter_text"] = _random_chatter()
		if m["chatter_until"] > 0.0:
			m["chatter_until"] = maxf(0.0, m["chatter_until"] - delta / CHATTER_SECONDS)


func _random_chatter() -> String:
	# Short, primitive noises. Monkeys don't need a lot to say.
	var options := ["OOK!", "EEE!", "OOH", "AH!", "♪", "!?", "OOK OOK"]
	return options[randi() % options.size()]


# --- menu -----------------------------------------------------------------

func _build_menu_button() -> void:
	var btn := Button.new()
	btn.text = "MENU"
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	btn.offset_left = Palette.MARGIN
	btn.offset_top = Palette.MARGIN
	btn.offset_right = Palette.MARGIN + 260.0
	btn.offset_bottom = Palette.MARGIN + Palette.TOUCH_MIN
	btn.pressed.connect(_on_menu_toggle)
	add_child(btn)


func _build_menu_panel() -> void:
	_menu_root = Control.new()
	_menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_root.visible = false
	_menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_menu_root)

	var scrim := ColorRect.new()
	scrim.color = Color(Palette.BG, 0.75)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	scrim.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			_on_menu_toggle())
	_menu_root.add_child(scrim)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _menu_style())
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(720.0, 640.0)
	panel.position = -panel.custom_minimum_size * 0.5
	_menu_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, Palette.MARGIN)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Palette.GUTTER)
	margin.add_child(column)

	var title := Label.new()
	title.text = "STABLE"
	title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	title.add_theme_color_override("font_color", Palette.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	# The four requested actions. Every one is a leaf for now: the destination
	# screens (fruit market, recruit shop, training select, mission launch) are
	# not built, so tapping shows a note in place of a real transition.
	for entry in [
			{"label": "GET MORE FRUIT", "action": "fruit"},
			{"label": "GET MORE MONKEYS", "action": "recruit"},
			{"label": "TRAIN MONKEYS", "action": "train"},
			{"label": "MISSION", "action": "mission"}]:
		var button := Button.new()
		button.text = String(entry["label"])
		button.custom_minimum_size = Vector2(0.0, Palette.TOUCH_MIN)
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", Palette.FONT_BODY)
		var action := String(entry["action"])
		button.pressed.connect(func() -> void: _on_menu_action(action))
		column.add_child(button)

	var close := Button.new()
	close.text = "CLOSE"
	close.custom_minimum_size = Vector2(0.0, Palette.TOUCH_MIN)
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	close.pressed.connect(_on_menu_toggle)
	column.add_child(close)


func _menu_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PAPER
	style.border_color = Palette.INK
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	return style


func _on_menu_toggle() -> void:
	_menu_open = not _menu_open
	_menu_root.visible = _menu_open
	Sfx.click()


## Leaves that route where they can, and otherwise put a chatter bubble on the
## first monkey so the player sees the button did something. Kept in one place
## so wiring a real destination is a one-line change.
func _on_menu_action(action: String) -> void:
	Sfx.click()
	_on_menu_toggle()
	match action:
		"train":
			if GameState.has_run():
				Router.push(Router.Screen.TRAINING_SESSION,
					{"activity": Training.Activity.SKIPPING})
				return
		"mission":
			# Voyage entry has no screen yet (design §12). Note it, don't route.
			pass
	_shout("SOON: %s" % action.to_upper())


func _shout(text: String) -> void:
	if _monkeys.is_empty():
		return
	_monkeys[0]["chatter_until"] = 1.0
	_monkeys[0]["chatter_text"] = text


# --- drawing --------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_backdrop()
	_draw_sun_moon()
	_draw_stars_if_night()
	# Hammocks under the monkeys so a sleeping crew sits IN the rope, not above.
	_draw_hammocks()
	_draw_monkeys()
	_draw_facility_signs()
	_draw_time_hud()


## Sagging rope for each stacked hammock slot at the sleeping quarters. Drawn
## whenever any monkey is sleeping — the empty ones just read as "spare beds".
func _draw_hammocks() -> void:
	if current_phase() != Phase.NIGHT and current_phase() != Phase.DAWN:
		return
	var cx: float = float(FACILITY_X[Facility.SLEEP]) * size.x
	var hw: float = HAMMOCK_HALF_WIDTH * size.x
	for slot_y in HAMMOCK_YS:
		var y := float(slot_y) * size.y
		var pts := PackedVector2Array()
		var steps := 14
		for i in steps + 1:
			var f := float(i) / float(steps)
			var xx := lerpf(cx - hw, cx + hw, f)
			var yy := y + sin(f * PI) * hw * 0.22
			pts.append(Vector2(xx, yy))
		for i in pts.size() - 1:
			draw_line(pts[i], pts[i + 1], Palette.PAPER_EDGE, 6.0)
		# Anchor pegs at each end.
		draw_circle(pts[0], 5.0, Palette.INK)
		draw_circle(pts[-1], 5.0, Palette.INK)


## Paint hero.png across the viewport in COVER mode (crop the axis that would
## letterbox), tinted by the time-of-day so the same image reads as morning,
## midday, dusk and night. If the viewport is taller than the image it crops
## the sides; wider and it crops the top/bottom sky+grass strips.
func _draw_backdrop() -> void:
	if HERO_TEXTURE == null:
		return
	var tex_size := HERO_TEXTURE.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return
	var scale := maxf(size.x / tex_size.x, size.y / tex_size.y)
	var drawn := tex_size * scale
	var origin := (size - drawn) * 0.5
	draw_texture_rect(HERO_TEXTURE, Rect2(origin, drawn), false, _time_tint())


## Time-of-day tint. Interpolates through the four anchor colours the same way
## the phase clock does, so the backdrop reads coherently at every moment.
func _time_tint() -> Color:
	if _time < PHASE_DAWN:
		return TINT_NIGHT.lerp(TINT_DAWN, _time / PHASE_DAWN)
	if _time < PHASE_MORNING:
		return TINT_DAWN.lerp(TINT_DAY, (_time - PHASE_DAWN) / (PHASE_MORNING - PHASE_DAWN))
	if _time < PHASE_EVENING:
		return TINT_DAY
	if _time < PHASE_DUSK:
		return TINT_DAY.lerp(TINT_DUSK, (_time - PHASE_EVENING) / (PHASE_DUSK - PHASE_EVENING))
	return TINT_DUSK.lerp(TINT_NIGHT, (_time - PHASE_DUSK) / (1.0 - PHASE_DUSK))


## Arcs the sun across the daytime sky and the moon across the night sky.
func _draw_sun_moon() -> void:
	var is_day := _time >= PHASE_DAWN and _time < PHASE_DUSK
	# t01 sweeps 0..1 across whichever arc is active.
	var t01 := 0.0
	if is_day:
		t01 = (_time - PHASE_DAWN) / (PHASE_DUSK - PHASE_DAWN)
	else:
		# Night arc wraps: DUSK..1.0 + 0.0..DAWN
		var night_len := (1.0 - PHASE_DUSK) + PHASE_DAWN
		var into_night := _time - PHASE_DUSK if _time >= PHASE_DUSK else (1.0 - PHASE_DUSK) + _time
		t01 = into_night / night_len
	var x := lerpf(0.08, 0.92, t01) * size.x
	# Arc: sits low near the horizon, rises to the top at midday/midnight.
	var y := (0.55 - 0.45 * sin(t01 * PI)) * size.y * 0.55
	var r := size.y * (0.045 if is_day else 0.035)
	if is_day:
		draw_circle(Vector2(x, y), r * 1.3, Color(Palette.WARN, 0.35))
		draw_circle(Vector2(x, y), r, Palette.LOGO_BLOB)
	else:
		draw_circle(Vector2(x, y), r * 1.2, Color(Palette.INK_LIGHT, 0.25))
		draw_circle(Vector2(x, y), r, Palette.INK_LIGHT)
		# Crater: a darker bite offset a hair.
		draw_circle(Vector2(x + r * 0.32, y - r * 0.15), r * 0.25,
			Color(Palette.PANEL_DARK, 0.6))


func _draw_stars_if_night() -> void:
	if _time >= PHASE_DAWN and _time < PHASE_DUSK:
		return
	# Fade in at dusk, out at dawn — cheap to compute inline.
	var alpha := 1.0
	if _time < PHASE_DAWN:
		alpha = 1.0 - _time / PHASE_DAWN
	elif _time >= PHASE_DUSK:
		alpha = (_time - PHASE_DUSK) / (1.0 - PHASE_DUSK)
	# Fixed pseudo-random distribution so the field doesn't shimmer.
	var rng := MpRng.new(20260812)
	for i in 70:
		var sx := rng.randf() * size.x
		var sy := rng.randf() * size.y * 0.55
		var sr := rng.randf_range(1.5, 3.5)
		draw_circle(Vector2(sx, sy), sr, Color(Palette.INK_LIGHT, alpha * rng.randf_range(0.4, 1.0)))


## A small labelled tab above each facility. The hero art shows what each
## place IS, but the labels teach the schedule — a new player sees "the
## cafeteria is where they go for meals" the first time the phase changes.
func _draw_facility_signs() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 22
	var y := (GROUND_Y - 0.30) * size.y
	for facility: int in FACILITY_LABELS.keys():
		var text: String = FACILITY_LABELS[facility]
		var cx: float = float(FACILITY_X[facility]) * size.x
		var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pad := 10.0
		var rect := Rect2(Vector2(cx - text_size.x * 0.5 - pad, y - text_size.y - pad),
			text_size + Vector2(pad * 2.0, pad * 2.0))
		draw_rect(rect.grow(3.0), Palette.INK)
		draw_rect(rect, Palette.PAPER)
		draw_string(font, Vector2(cx - text_size.x * 0.5, y - pad * 0.4),
			text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Palette.INK)


func _draw_monkeys() -> void:
	# Frame index alternates on a monotonic clock — same for every monkey, so
	# the whole crew steps in loose sync (fine for placeholder art; scatter the
	# phase per monkey if it starts reading as a marching band).
	var frame_idx := (Time.get_ticks_msec() / FRAME_MS) % 2
	var sprite_h := size.y * SPRITE_H
	for m in _monkeys:
		var p: Vector2 = Vector2(m["pos"].x * size.x, m["pos"].y * size.y)
		var action := _action_for(m)
		var texture: Texture2D = MONKEY_SPRITES.get(action, MONKEY_SPRITES["walk"])
		if texture != null:
			var tex_size := texture.get_size()
			var frame_w := tex_size.x * 0.5
			# Aspect comes from the texture — sheets are now trimmed per action
			# so each has its own frame dimensions.
			var sprite_w := sprite_h * (frame_w / tex_size.y)
			var src := Rect2(frame_idx * frame_w, 0.0, frame_w, tex_size.y)
			# Anchor by the feet at `p`: bottom of sprite sits on pos.y so a
			# walking monkey stands on the ground line.
			var dest := Rect2(p - Vector2(sprite_w * 0.5, sprite_h),
				Vector2(sprite_w, sprite_h))
			draw_texture_rect_region(texture, dest, src)
		# Chatter bubble above the head.
		if m["chatter_until"] > 0.0:
			_draw_chatter(p - Vector2(0.0, sprite_h * 0.95),
				String(m["chatter_text"]), m["chatter_until"])
		# Name plate — subtle, under the feet so the crowd is readable.
		if action != "sleep":
			_draw_name(p + Vector2(0.0, 6.0), String(m["name"]))


## What is this monkey doing right now? Walking if it hasn't reached its
## target yet, otherwise whatever the facility calls for.
func _action_for(m: Dictionary) -> String:
	var moving: bool = (m["pos"] as Vector2).distance_to(m["target_pos"]) > 0.005
	if moving:
		return "walk"
	return String(FACILITY_ACTION.get(m["target_facility"], "walk"))


func _draw_chatter(at: Vector2, text: String, alpha: float) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 22
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pad := 8.0
	var rect := Rect2(at - Vector2(text_size.x * 0.5 + pad, text_size.y + pad),
		text_size + Vector2(pad * 2.0, pad * 2.0))
	draw_rect(rect, Color(Palette.PAPER, alpha))
	draw_rect(rect, Color(Palette.INK, alpha), false, 2.0)
	draw_string(font, at - Vector2(text_size.x * 0.5, pad),
		text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
		Color(Palette.INK, alpha))


func _draw_name(at: Vector2, name: String) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var font_size := 18
	var text_size := font.get_string_size(name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	draw_string(font, at - Vector2(text_size.x * 0.5, 0.0),
		name, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size,
		Color(Palette.INK_LIGHT, 0.8))


## Corner readout: current phase and a tiny sun-arc dial.
func _draw_time_hud() -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var pad := Palette.MARGIN
	var text := phase_label()
	var font_size := Palette.FONT_SMALL
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_RIGHT, -1, font_size)
	# Box in the top-right corner.
	var box := Rect2(Vector2(size.x - pad - text_size.x - 40.0, pad),
		Vector2(text_size.x + 30.0, text_size.y + 20.0))
	draw_rect(box, Color(Palette.PANEL_DARK, 0.7))
	draw_rect(box, Palette.INK_LIGHT, false, 2.0)
	draw_string(font, box.position + Vector2(15.0, text_size.y + 4.0),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.INK_LIGHT)
