extends GameScreen

## THE COLD OPEN — the drone's survey of Earth, the memo that retires it, and the
## choice that starts the game. Plays once, on first launch, ahead of the title;
## afterwards the title offers REPLAY INTRO.
##
## Design doc §1.2. The tonal spine is one colour argument: **grey → colour →
## grey**. Dead space is drained to near-monochrome, the planet floods it back,
## and the memo takes it away again. The refusal is the drone choosing colour.
##
##   0.0 – 7.0s   TRANSIT   nothing happens, slightly too long. That is the point.
##   7.0 – 11.3s  ARRIVAL   Earth on the right; the drone dives into it, shrinking
##   11.3 – 18.1s BLOOM     canopy, herd, birds, a monkey. The counter runs away.
##   18.1s        MEMO      one button, and the player has to press it
##   then         STANDOFF  press to comply — or, at the last moment, rebel
##
## Comply all the way and the works order is carried out: game over, and you see
## what the survey bought. Rebel and the drone turns for home, freezing on its
## approach as the title lands.
##
## ART IS STAND-IN ART (ARCHITECTURE §17). Generated components in
## `assets/placeholder/cold_open/`, one object per file so this screen can move
## them independently, plus the game's own drone from the prologue set. A missing
## file degrades to a flat shape rather than crashing, which keeps the headless
## suite honest.

enum Phase { PLAYING, MEMO, STANDOFF, REBEL, SUNRUN, DONE }

# --- timeline --------------------------------------------------------------
const ARRIVAL_AT := 7.0
const BLOOM_AT := 11.3
const MEMO_AT := 18.1
## The memo has to finish sliding in before its button can be pressed.
const MEMO_READY := 18.9

## Each press of COMPLY, as a fraction of the run at the sun.
const PRESS_STEP := 0.075
## The drone eases toward the pressed target rather than snapping to it. The last
## stretch is deliberately slower, so the REBEL offer has a moment to land.
const GLIDE := 5.5
const GLIDE_FINAL := 1.6
## REBEL appears on the second-to-last press: exactly one click from the sun.
## 1.0 / PRESS_STEP is 14 presses, so this has to clear 13 of them.
const REBEL_AT := 0.97
## The last of the three things it says to itself, one press earlier.
const PRECIOUS_AT := 0.9
const DOUBT_AT := 0.4
const SAVED_AT := 0.66

const ART := "res://assets/placeholder/cold_open/%s.png"
const DRONE_ART := "res://assets/placeholder/prologue/drone.png"

const STAR_COUNT := 90
const STAR_SEED := 20260804

@onready var _memo: Control = $Memo
@onready var _memo_header: Label = $Memo/Header
@onready var _memo_finding: Label = $Memo/Finding
@onready var _ack: Button = $Memo/Acknowledge
@onready var _controls: Control = $Controls
@onready var _hint: Label = $Controls/Hint
@onready var _comply: Button = $Controls/Buttons/Comply
@onready var _rebel: Button = $Controls/Buttons/Rebel
@onready var _endcap: Control = $EndCap
@onready var _retry: Button = $EndCap/Rows/Retry
@onready var _skip: Button = $Skip
@onready var _readouts: Control = $Readouts
@onready var _top_line: Label = $Readouts/TopLine
@onready var _task_line: Label = $Readouts/TaskLine
@onready var _status_line: Label = $Readouts/StatusLine
@onready var _count_line: Label = $Readouts/CountLine
@onready var _claim: Label = $Claim

var _phase: Phase = Phase.PLAYING
var _t: float = 0.0
var _local: float = 0.0
## Where the comply meter is, and where the presses have asked it to be.
var _run: float = 0.0
var _run_target: float = 0.0
var _last_press: float = -9.0
## Never resets, so the sun and Earth keep turning across every beat.
var _clock: float = 0.0
var _stars: Array[Vector3] = []
var _star_tints: Array[Color] = []
var _tex_cache: Dictionary = {}
## Type scale for the memo. Dropped a step at a time when the notice would
## outgrow the screen; every pass recomputes sizes FROM this rather than
## shrinking what is already there, so it settles instead of collapsing.
var _memo_scale: float = 1.0


func _ready() -> void:
	super()
	_seed_starfield()
	_apply_palette()
	_ack.pressed.connect(_on_acknowledged)
	_comply.pressed.connect(_on_comply_pressed)
	_rebel.pressed.connect(_on_rebel_pressed)
	_retry.pressed.connect(_on_retry_pressed)
	_skip.pressed.connect(_finish)
	resized.connect(_relayout)
	_relayout()


## Colours live here rather than in the .tscn so Palette stays the single source
## of truth. The readouts are cyan instrument text, the counter is amber, and the
## claimant line — the one that dooms the planet — is red.
func _apply_palette() -> void:
	for label in [_top_line, _task_line, _status_line]:
		label.add_theme_color_override("font_color", Palette.ACCENT_ALT)
		label.add_theme_stylebox_override("normal", _plate(Palette.ACCENT_ALT))
	_count_line.add_theme_color_override("font_color", Palette.WARN)
	_count_line.add_theme_stylebox_override("normal", _plate(Palette.WARN))
	_claim.add_theme_color_override("font_color", Palette.BAD)
	_claim.add_theme_stylebox_override("normal", _plate(Palette.BAD))
	_hint.add_theme_stylebox_override("normal", _plate(Palette.ACCENT_ALT))
	# REBEL is the only red thing on the screen. It should look like what it is.
	var rebel_box := StyleBoxFlat.new()
	rebel_box.bg_color = Palette.BAD
	rebel_box.border_color = Palette.INK
	rebel_box.set_border_width_all(6)
	for state in ["normal", "hover", "pressed", "focus"]:
		_rebel.add_theme_stylebox_override(state, rebel_box)
	_rebel.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_rebel.add_theme_color_override("font_hover_color", Color.WHITE)
	_endcap.get_node("Rows/Title").add_theme_color_override("font_color", Palette.BAD)
	for line in ["Rows/Line", "Rows/Delisted"]:
		_endcap.get_node(line).add_theme_color_override("font_color", Palette.INK_LIGHT)
	_memo_finding.add_theme_color_override("font_color", Palette.LOGO_RED)
	_memo_header.add_theme_color_override("font_color", Palette.LOGO_BLUE)
	# The memo is corporate paper, not a game panel: cream stock, ink type, a
	# thick black rule. The default panel is dark, and dark-on-dark rendered the
	# whole notice invisible.
	var paper := StyleBoxFlat.new()
	paper.bg_color = Palette.PAPER
	paper.border_color = Palette.INK
	paper.set_border_width_all(6)
	paper.content_margin_left = 34.0
	paper.content_margin_right = 34.0
	paper.content_margin_top = 26.0
	paper.content_margin_bottom = 26.0
	_memo.add_theme_stylebox_override("panel", paper)


## The readouts are instrument text over space and canopy, so each one carries its
## own plate. A stylebox on the Label tracks the text box exactly; hand-drawn
## rects behind it do not, which is how the first attempt ended up with a plate
## the height of the screen.
static func _plate(edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.PANEL_DARK, 0.78)
	box.border_color = Color(edge, 0.35)
	box.set_border_width_all(2)
	box.content_margin_left = 18.0
	box.content_margin_right = 18.0
	box.content_margin_top = 8.0
	box.content_margin_bottom = 8.0
	return box


func on_enter(params: Dictionary) -> void:
	super(params)
	_phase = Phase.PLAYING
	_t = 0.0
	_local = 0.0
	_run = 0.0
	_run_target = 0.0
	_memo_scale = 1.0
	_memo.visible = false
	_controls.visible = false
	_endcap.visible = false
	_claim.visible = false
	_rebel.visible = false


## Skipping is always available — a player who has seen it once should never be
## trapped in it, and `Prefs.intro_seen` is set either way.
func on_back_requested() -> bool:
	_finish()
	return true


func _process(delta: float) -> void:
	_clock += delta
	match _phase:
		Phase.PLAYING:
			_t += delta
			if _t >= MEMO_AT:
				_memo.visible = true
				_ack.disabled = _t < MEMO_READY
				if _t >= MEMO_READY:
					_phase = Phase.MEMO
					_ack.grab_focus()
		Phase.STANDOFF:
			_local += delta
			var stiffness := GLIDE_FINAL if _run_target >= REBEL_AT else GLIDE
			_run += (_run_target - _run) * (1.0 - exp(-delta * stiffness))
			_rebel.visible = _run_target >= REBEL_AT
			_update_hint()
			if _run_target >= 1.0 and _run > 0.985:
				_run = 1.0
				_phase = Phase.SUNRUN
				_local = 0.0
				_controls.visible = false
		Phase.REBEL:
			_local += delta
			if _local > 4.2:
				_finish()
		Phase.SUNRUN:
			_local += delta
			if _local > 2.6 and not _endcap.visible:
				_endcap.visible = true
				_retry.grab_focus()
		_:
			pass
	if _memo.visible:
		_layout_memo(size.y)
		# A hard blink, not a fade — this is an alarm, not a pulse.
		var lit := fposmod(_clock, 0.62) < 0.31
		_memo_finding.add_theme_color_override("font_color",
			Palette.BAD if lit else Color(Palette.LOGO_RED, 0.45))
	_controls.visible = _phase == Phase.STANDOFF
	_update_readouts()
	queue_redraw()


## Which beat a given elapsed time falls in. Pulled out as a static so the
## headless suite can pin the running order without mounting the screen.
static func beat_at(t: float) -> int:
	if t < ARRIVAL_AT:
		return 0
	if t < BLOOM_AT:
		return 1
	if t < MEMO_AT:
		return 2
	return 3


# --- input -----------------------------------------------------------------

func _on_acknowledged() -> void:
	Sfx.confirm()
	_phase = Phase.STANDOFF
	_local = 0.0
	_run = 0.0
	_run_target = 0.0
	_last_press = -9.0
	_memo.visible = false
	_readouts.visible = false
	_claim.visible = false
	_controls.visible = true
	_rebel.visible = false
	_update_hint()
	_comply.grab_focus()


func _on_comply_pressed() -> void:
	if _phase != Phase.STANDOFF:
		return
	Sfx.click()
	_run_target = clampf(_run_target + PRESS_STEP, 0.0, 1.0)
	_last_press = _local


func _on_rebel_pressed() -> void:
	if _phase != Phase.STANDOFF:
		return
	Sfx.confirm()
	_phase = Phase.REBEL
	_local = 0.0
	_controls.visible = false


func _on_retry_pressed() -> void:
	Sfx.cancel()
	_endcap.visible = false
	_on_acknowledged()


## Mark the intro seen and hand over to the title. Called on rebel, on skip, and
## on hardware back — every exit from this screen goes through here.
func _finish() -> void:
	if _phase == Phase.DONE:
		return
	_phase = Phase.DONE
	Prefs.set_intro_seen(true)
	Router.reset_to(Router.Screen.TITLE)


# --- layout ----------------------------------------------------------------

func _relayout() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var h := size.y
	_layout_memo(h)
	_controls.size = Vector2(size.x * 0.66, h * 0.32)
	_controls.position = Vector2(size.x * 0.17, h * 0.6)
	for button in [_comply, _rebel]:
		button.custom_minimum_size = Vector2(size.x * 0.3, maxf(Palette.TOUCH_MIN * 0.55, h * 0.15))
		button.add_theme_font_size_override("font_size", int(round(h * 0.05)))
	_hint.add_theme_font_size_override("font_size", int(round(h * 0.042)))
	_skip.position = Vector2(size.x - size.x * 0.12 - h * 0.04, h * 0.04)
	_skip.size = Vector2(size.x * 0.12, h * 0.1)
	_place_readout(_top_line, 0.04, 0.06, HORIZONTAL_ALIGNMENT_LEFT)
	# stacked under the site line rather than top-right, where SKIP lives
	_place_readout(_task_line, 0.04, 0.19, HORIZONTAL_ALIGNMENT_LEFT)
	_place_readout(_status_line, 0.04, 0.85, HORIZONTAL_ALIGNMENT_LEFT)
	_place_readout(_count_line, 0.04, 0.85, HORIZONTAL_ALIGNMENT_RIGHT)
	_endcap.get_node("Rows/Title").add_theme_font_size_override("font_size", int(round(h * 0.11)))
	for line in ["Rows/Line", "Rows/Delisted"]:
		_endcap.get_node(line).add_theme_font_size_override("font_size", int(round(h * 0.038)))
	_claim.add_theme_font_size_override("font_size", int(round(h * 0.042)))
	_claim.set_meta("corner", Vector2(0.04, 0.74))
	_park(_claim)
	_claim.position = Vector2((size.x - _claim.size.x) * 0.5, h * 0.74)
	queue_redraw()


## The memo is laid out by hand rather than by a VBoxContainer. An autowrapping
## Label inside a container reports its minimum height for its minimum WIDTH —
## one word per line — so the panel demanded 11,000px of height and threw itself
## off the top of the screen.
##
## Widths are set first and heights read back from each Label afterwards:
## `get_combined_minimum_size().y` is measured against the width the label
## actually has, which is the number that wraps correctly. Measuring the string
## directly does not — it reported 4,500px for a single line of type.
func _layout_memo(h: float) -> void:
	var inner := size.x * 0.56
	for row in _memo_rows():
		if row is Label:
			var label := row as Label
			var base := 0.058 if label == _memo_finding else 0.034
			label.add_theme_font_size_override("font_size",
				maxi(11, int(round(h * base * _memo_scale))))
		# A custom minimum WIDTH is what makes a wrapping Label report an honest
		# minimum height. Without it Godot measures the wrap against a width of 1.
		row.custom_minimum_size = Vector2(inner, 0.0)
		row.size.x = inner
	# Heights are only trustworthy once those widths have been applied AND the
	# labels have re-measured, which they do lazily. So the stacking pass runs
	# again every frame the memo is on screen — six rows, and it settles within a
	# frame or two of the memo appearing.
	_stack_memo(h, inner)


func _stack_memo(h: float, inner: float) -> void:
	if not is_inside_tree():
		return
	var pad := h * 0.05
	var gap := h * 0.026
	var y := pad
	for row in _memo_rows():
		row.position = Vector2(pad, y)
		row.size = Vector2(inner, maxf(row.get_combined_minimum_size().y, h * 0.05))
		y += row.size.y + gap
	_memo.size = Vector2(inner + pad * 2.0, y - gap + pad)
	_memo.position = ((size - _memo.size) * 0.5).floor()
	# On a squarer viewport the notice can outgrow the screen. Shrink the type a
	# step and let the next frame re-stack; it converges in one or two passes.
	if _memo.size.y > size.y * 0.94 and _memo_scale > 0.5:
		_memo_scale = maxf(0.5, _memo_scale * 0.93)


func _memo_rows() -> Array[Control]:
	return [_memo_header, _memo.get_node("Received"), _memo_finding,
		_memo.get_node("Scheduled"), _memo.get_node("Order"), _ack]


func _place_readout(label: Label, x: float, y: float, align: int) -> void:
	label.horizontal_alignment = align
	label.add_theme_font_size_override("font_size", int(round(size.y * 0.036)))
	label.set_meta("corner", Vector2(x, y))
	_park(label)


## Shrink to the text, then sit in the corner the layout gave it. The right-hand
## readouts measure from their own right edge, so they stay flush as the numbers
## grow a digit.
func _park(label: Label) -> void:
	# Size to the measured text rather than reset_size(): these labels autowrap
	# (the UI suite insists on it for long strings), and a wrapping label's
	# minimum width is one word, which stacks the readout into a vertical column.
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text_size := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size)
	label.custom_minimum_size = Vector2.ZERO
	label.size = Vector2(text_size.x + 40.0, text_size.y + 20.0)
	var corner: Vector2 = label.get_meta("corner", Vector2(0.04, 0.06))
	var at := Vector2(size.x * corner.x, size.y * corner.y)
	if label.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT:
		at.x = size.x * (1.0 - corner.x) - label.size.x
	label.position = at


func _seed_starfield() -> void:
	var rng := MpRng.new(STAR_SEED)
	var tints: Array[Color] = [
		Palette.INK_LIGHT, Palette.WARN, Palette.ACCENT_ALT, Palette.CHECKER,
	]
	for i in STAR_COUNT:
		_stars.append(Vector3(rng.randf(), rng.randf(), rng.randf_range(0.003, 0.010)))
		var tint: Color = tints[rng.randi_range(0, tints.size() - 1)]
		_star_tints.append(Color(tint, rng.randf_range(0.35, 1.0)))


func _update_hint() -> void:
	if _run_target >= PRECIOUS_AT:
		_hint.text = "LIFE IS PRECIOUS"
		_hint.add_theme_color_override("font_color", Palette.WARN)
	elif _run_target >= SAVED_AT:
		_hint.text = "THEY COULD ALL BE SAVED"
		_hint.add_theme_color_override("font_color", Palette.ACCENT_ALT)
	elif _run_target >= DOUBT_AT:
		_hint.text = "YOU DO NOT HAVE TO DO THIS"
		_hint.add_theme_color_override("font_color", Palette.INK_LIGHT)
	else:
		# Silence until the drone is 40% of the way there. The first thing it ever
		# says is that it does not have to do this.
		_hint.text = ""


func _update_readouts() -> void:
	_readouts.visible = _phase == Phase.PLAYING or _phase == Phase.MEMO
	if not _readouts.visible:
		return
	_task_line.text = "VOSS-HALLIDAY CIVIL WORKS"
	if _t < ARRIVAL_AT:
		_top_line.text = "TRANSIT · LEG 9 OF 9"
		_status_line.text = "SYSTEMS NOMINAL · NOTHING TO REPORT"
		_count_line.text = "ELAPSED %.2f YEARS" % (38.4 + _t * 0.06)
	elif _t < BLOOM_AT:
		_top_line.text = "SITE 3-EARTH · APPROACH"
		_task_line.text = "TASK: CONFIRM SITE DEVOID OF SENTIENT LIFE"
		_status_line.text = "SURVEY %d%%" % int(_span(9.0, BLOOM_AT) * 4.0)
		_count_line.text = "SUBJECTS OF INTEREST 0"
	else:
		_top_line.text = "SITE 3-EARTH · SURVEY"
		_task_line.text = ("WARNING: COUNT EXCEEDS FORM FIELDS" if _t > 16.4
			else "TASK: CONFIRM SITE DEVOID OF SENTIENT LIFE")
		_status_line.text = "SURVEY %d%%" % mini(100, int(_span(11.6, 17.6) * 100.0))
		_count_line.text = "SPECIES CATALOGUED %s" % _grouped(int(_ease(_span(11.6, 17.6)) * 8714442.0))
	for label in [_top_line, _task_line, _status_line, _count_line]:
		_park(label)
	_claim.visible = _t > 16.2 and _t < MEMO_AT


static func _grouped(value: int) -> String:
	var text := str(value)
	var out := ""
	for i in text.length():
		if i > 0 and (text.length() - i) % 3 == 0:
			out += ","
		out += text[i]
	return out


# --- painting --------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	match _phase:
		Phase.PLAYING, Phase.MEMO:
			_draw_opening()
		Phase.STANDOFF:
			_draw_standoff()
		Phase.REBEL:
			_draw_rebel()
		Phase.SUNRUN:
			_draw_sunrun()
		_:
			_draw_standoff()


func _draw_opening() -> void:
	var bloom := _t >= BLOOM_AT
	if bloom:
		_gradient(Rect2(Vector2.ZERO, size), Color("2f8f52"), Color("12482a"))
		_draw_bloom()
	else:
		_gradient(Rect2(Vector2.ZERO, size), Color("3b2a6b"), Palette.BG)
		_draw_stars(1.0)
		_blit(_tex("sun"), Vector2(size.x * 0.72, size.y * 0.24), size.y * 0.16,
			Palette.WARN, false, Vector2(0.5, 0.5), Color(1, 1, 1, 0.55), _clock * 1.3)
		_draw_approach()
	# the drained transit warms up as the planet arrives, then the bloom saturates
	var drain := 1.0 - _ease(_span(0.0, 9.0)) if _t < 9.0 else 0.0
	if drain > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.PANEL_DARK, drain * 0.72))
	if _t > 18.4:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.PANEL_DARK, minf(0.62, (_t - 18.4) * 1.4)))


## Earth on the right, and the drone dives INTO it — shrinking, not growing, so
## the descent reads as distance rather than a fly-past.
func _draw_approach() -> void:
	if _t < 6.8:
		_draw_drone_transit()
		return
	var rise := _ease(_span(7.2, 10.2))
	var rush := _ease(_span(10.2, 11.5))
	var earth_h := size.y * (0.72 * lerpf(0.5, 1.05, rise) * lerpf(1.0, 3.9, rush))
	_blit(_tex("earth"), Vector2(size.x * lerpf(0.78, 0.62, rush), size.y * lerpf(0.86, 0.62, rise)),
		earth_h, Palette.ACCENT_ALT, false, Vector2(0.5, 0.5),
		Color(1, 1, 1, _span(7.2, 8.4)), _clock * -0.85)
	_draw_drone_transit()
	if _t > 11.2:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK_LIGHT, 1.0 - absf(_t - 11.42) / 0.55))


func _draw_drone_transit() -> void:
	var travel := _ease(_span(0.0, 9.4))
	var dive := _ease(_span(9.4, 11.3))
	var at := Vector2(size.x * (lerpf(0.1, 0.44, travel) + dive * 0.18),
		size.y * (lerpf(0.38, 0.42, travel) + dive * 0.14) + sin(_t * 0.9) * size.y * 0.012)
	var scale := lerpf(0.16, 0.24, _ease(_span(0.0, 8.8))) * lerpf(1.0, 0.16, dive)
	_blit(_tex_drone(), at, size.y * scale, Palette.PAPER, true, Vector2(0.5, 0.5),
		Color(1, 1, 1, 1.0 - _ease(_span(11.0, 11.35))))


func _draw_bloom() -> void:
	var rise := _ease(_span(BLOOM_AT, 13.2))
	var drift := (_t - BLOOM_AT) * 0.012
	_blit(_tex("canopy"), Vector2(size.x * (0.5 - drift * 0.5), size.y * lerpf(1.3, 0.62, rise)),
		size.y * 1.15, Palette.GOOD)
	_blit(_tex("canopy"), Vector2(size.x * (0.5 - drift * 1.4), size.y * lerpf(1.7, 1.0, rise)),
		size.y * 1.5, Palette.GOOD)
	var herd := _ease(_span(12.6, 13.9))
	if herd > 0.0:
		_blit(_tex("herd"), Vector2(size.x * 0.72, size.y * (0.72 - herd * 0.04)),
			size.y * 0.3 * herd, Palette.LOC_SHOP)
	for i in 3:
		var speed := 0.16 + i * 0.05
		var progress := fposmod((_t - BLOOM_AT) * speed + i * 0.4, 1.4)
		if progress > 1.2:
			continue
		_blit(_tex("bird"), Vector2(size.x * lerpf(1.15, -0.15, progress / 1.2),
			size.y * (0.22 + i * 0.16) + sin(_t * 3.0 + i) * size.y * 0.02),
			size.y * (0.08 + i * 0.02), Palette.ACCENT)
	var monkey := _ease(_span(15.4, 17.2))
	if monkey > 0.0:
		_blit(_tex("monkey_face"), Vector2(size.x * 0.5, size.y * (1.06 - monkey * 0.5)),
			size.y * lerpf(0.5, 0.95, monkey), Palette.LOC_SHOP)
	_draw_scan_boxes()


func _draw_scan_boxes() -> void:
	var boxes := [
		[Rect2(0.08, 0.18, 0.2, 0.3), 12.2, Palette.GOOD],
		[Rect2(0.62, 0.56, 0.28, 0.3), 13.9, Palette.WARN],
		[Rect2(0.3, 0.3, 0.4, 0.58), 16.2, Palette.ACCENT_ALT],
	]
	for entry in boxes:
		var box: Rect2 = entry[0]
		var at: float = entry[1]
		if _t < at or _t > MEMO_AT:
			continue
		var alpha := clampf((_t - at) * 3.0, 0.0, 1.0)
		var r := Rect2(box.position * size, box.size * size)
		draw_rect(r, Color(entry[2], alpha * 0.12))
		draw_rect(r, Color(entry[2], alpha), false, size.y * 0.006)


func _draw_standoff() -> void:
	_gradient(Rect2(Vector2.ZERO, size), Palette.BG, Color("2a1b3f"))
	_draw_stars(1.0)
	var away := _ease(_run)
	# the Earth falls away behind exactly as fast as the sun swallows the frame
	_blit(_tex("earth"), Vector2(size.x * (0.12 - away * 0.06), size.y * (0.86 + away * 0.1)),
		size.y * lerpf(1.0, 0.28, away), Palette.ACCENT_ALT, false, Vector2(0.5, 0.5),
		Color(1, 1, 1, lerpf(0.95, 0.55, away)), _clock * -0.85)
	_blit(_tex("sun"), Vector2(size.x * 1.02, size.y * 0.4), size.y * lerpf(1.5, 2.3, away),
		Palette.WARN, false, Vector2(0.5, 0.5), Color.WHITE, _clock * 1.3)
	_draw_comply_drone(away)
	_draw_meter()
	if away > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.WARN, away * away * 0.18))


func _draw_comply_drone(away: float) -> void:
	var kick := clampf(1.0 - (_local - _last_press) * 3.0, 0.0, 1.0)
	var shake := kick * kick * sin(_local * 30.0) * size.x * 0.004
	var at := Vector2(size.x * lerpf(0.18, 0.72, away) + shake, size.y * 0.45)
	_blit(_tex_drone(), at, size.y * lerpf(0.2, 0.11, away), Palette.PAPER, true)


func _draw_meter() -> void:
	# above the hint, which sits at the top of the controls block
	var bar := Rect2(size.x * 0.17, size.y * 0.53, size.x * 0.66, size.y * 0.028)
	draw_rect(bar, Color(Palette.PANEL_DARK, 0.8))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * _run, bar.size.y)), Palette.WARN)
	draw_rect(bar, Color(Palette.WARN, 0.5), false, size.y * 0.004)


## The refusal: shock, shuffle, turn, then a run at the Earth that FREEZES on the
## approach — the last thing the prologue shows is the drone still on its way.
func _draw_rebel() -> void:
	_gradient(Rect2(Vector2.ZERO, size), Palette.BG, Color("2a1b3f"))
	_draw_stars(1.0)
	var away := _ease(_run)
	var shuffle := sin(_local * 34.0) * size.x * 0.004 * maxf(0.0, 1.0 - _local) if _local < 1.0 else 0.0
	var turned := _local > 1.14
	var home := _ease(clampf((_local - 1.35) / 1.35, 0.0, 1.0))
	var push := _ease(clampf((_local - 3.0) / 0.9, 0.0, 1.0))

	_blit(_tex("earth"), Vector2(size.x * lerpf(0.12 - away * 0.06, 0.16, home),
		size.y * lerpf(0.86 + away * 0.1, 0.78, home)),
		size.y * lerpf(lerpf(1.0, 0.28, away), 1.15, home) * lerpf(1.0, 1.12, push),
		Palette.ACCENT_ALT, false, Vector2(0.5, 0.5), Color.WHITE, _clock * -0.85)
	_blit(_tex("sun"), Vector2(size.x * lerpf(1.02, 1.2, home), size.y * 0.4),
		size.y * lerpf(lerpf(1.5, 2.3, away), 1.3, home), Palette.WARN, false,
		Vector2(0.5, 0.5), Color(1, 1, 1, lerpf(1.0, 0.85, home)), _clock * 1.3)

	var at := Vector2(
		size.x * lerpf(lerpf(0.18, 0.72, away), 0.2, home) + shuffle - push * size.x * 0.014,
		size.y * lerpf(0.45, 0.66, home) + push * size.y * 0.012)
	var scale := size.y * lerpf(0.2, 0.11, away) * lerpf(1.0, 0.42, home) * lerpf(1.0, 0.62, push)
	# it turns to face home: the flip IS the story beat
	_blit(_tex_drone(), at, scale, Palette.PAPER, not turned)

	if _local < 1.25:
		var pop := clampf(_local * 5.0, 0.0, 1.0)
		var alpha := clampf(_local * 6.0, 0.0, 1.0) if _local < 1.15 else clampf(1.0 - (_local - 1.15) * 5.0, 0.0, 1.0)
		_draw_shock(at + Vector2(0.0, -scale * 0.8), scale * 0.5 * pop, alpha)


## The exclamation mark over its head — a bar and a dot, drawn rather than typed
## so it scales with the sprite.
func _draw_shock(at: Vector2, height: float, alpha: float) -> void:
	if height <= 0.0 or alpha <= 0.0:
		return
	var w := height * 0.22
	draw_rect(Rect2(at.x - w * 0.5, at.y - height, w, height * 0.66), Color(Palette.WARN, alpha))
	draw_circle(at + Vector2(0.0, -height * 0.12), w * 0.55, Color(Palette.WARN, alpha))


func _draw_sunrun() -> void:
	if _local > 1.5:
		_draw_aftermath()
		return
	var run := _ease(clampf(_local / 1.2, 0.0, 1.0))
	_gradient(Rect2(Vector2.ZERO, size), Palette.BG, Color("2a1b3f"))
	_draw_stars(1.0 - run)
	_blit(_tex("earth"), Vector2(size.x * (0.06 - run * 0.04), size.y * (0.96 + run * 0.06)),
		size.y * lerpf(0.28, 0.18, run), Palette.ACCENT_ALT, false, Vector2(0.5, 0.5),
		Color(1, 1, 1, lerpf(0.55, 0.25, run)), _clock * -0.85)
	_blit(_tex("sun"), Vector2(size.x * 1.02, size.y * 0.4), size.y * lerpf(2.3, 3.2, run),
		Palette.WARN, false, Vector2(0.5, 0.5), Color.WHITE, _clock * 1.3)
	_blit(_tex_drone(), Vector2(size.x * lerpf(0.72, 0.95, run), size.y * 0.45),
		size.y * lerpf(0.11, 0.02, run), Palette.PAPER, true, Vector2(0.5, 0.5),
		Color(1, 1, 1, clampf(1.0 - _local * 0.9, 0.0, 1.0)))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK_LIGHT, clampf((_local - 0.55) * 1.6, 0.0, 1.0)))


## What the survey bought: the site cleared, and the crew still working it.
func _draw_aftermath() -> void:
	_gradient(Rect2(Vector2.ZERO, size), Color("0c0a14"), Palette.BG)
	_draw_stars(clampf((_local - 1.6) * 1.4, 0.0, 0.85))
	var drift := (_local - 1.5) * 0.01
	_blit(_tex("earth_wreck"), Vector2(size.x * (0.5 - drift * 0.4), size.y * 0.46),
		size.y * 0.72, Palette.DISABLED, false, Vector2(0.5, 0.5),
		Color(1, 1, 1, clampf((_local - 1.6) * 1.2, 0.0, 1.0)), _clock * -0.34)
	_blit(_tex("grader"), Vector2(size.x * (0.12 + drift * 6.0), size.y * 0.74), size.y * 0.34,
		Palette.PANEL_LIGHT, false, Vector2(0.5, 0.5),
		Color(1, 1, 1, clampf((_local - 1.9) * 1.2, 0.0, 1.0)))
	_blit(_tex("grader"), Vector2(size.x * (0.82 - drift * 4.0), size.y * 0.2), size.y * 0.22,
		Palette.PANEL_LIGHT, true, Vector2(0.5, 0.5),
		Color(1, 1, 1, clampf((_local - 2.2) * 1.2, 0.0, 1.0)))
	draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.INK_LIGHT, clampf(1.0 - (_local - 1.5) * 1.6, 0.0, 1.0)))
	# The verdict has to be readable over a burning planet.
	if _endcap.visible:
		draw_rect(Rect2(Vector2.ZERO, size), Color(Palette.BG, 0.66))


# --- helpers ---------------------------------------------------------------

func _span(from: float, to: float) -> float:
	return clampf((_t - from) / (to - from), 0.0, 1.0)


static func _ease(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return 2.0 * p * p if p < 0.5 else 1.0 - pow(-2.0 * p + 2.0, 2.0) / 2.0


func _draw_stars(alpha: float) -> void:
	if alpha <= 0.0:
		return
	var drift := _clock * 0.012
	for i in _stars.size():
		var s := _stars[i]
		var x := fposmod(s.x - drift, 1.0) * size.x
		var tint: Color = _star_tints[i]
		draw_circle(Vector2(x, s.y * size.y), s.z * size.y, Color(tint, tint.a * alpha))


## Godot's canvas API has no gradient primitive, so this is a stack of bands —
## the same trick the splash and forage screens use.
func _gradient(box: Rect2, top: Color, bottom: Color) -> void:
	var bands := 20
	var band_h := box.size.y / float(bands)
	for i in bands:
		draw_rect(Rect2(box.position.x, box.position.y + i * band_h, box.size.x, band_h + 1.0),
			top.lerp(bottom, float(i) / float(bands - 1)))


## Draw a texture centred on `at` at `height` pixels tall, keeping its aspect. A
## missing texture degrades to a flat circle in `fallback`, so the headless suite
## can still mount this screen with no art imported.
func _blit(tex: Texture2D, at: Vector2, height: float, fallback: Color, flip := false,
		pivot := Vector2(0.5, 0.5), tint := Color.WHITE, rotation := 0.0) -> void:
	if height <= 0.0 or tint.a <= 0.0:
		return
	var aspect := 1.0
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var box_size := Vector2(height * aspect, height)
	if tex == null:
		draw_set_transform(at, rotation, box_size * 0.5)
		draw_circle(Vector2.ZERO, 1.0, Color(fallback, tint.a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	draw_set_transform(at, rotation, Vector2(-1.0 if flip else 1.0, 1.0))
	draw_texture_rect(tex, Rect2(-box_size * pivot, box_size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _tex(art_name: String) -> Texture2D:
	if _tex_cache.has(art_name):
		return _tex_cache[art_name]
	var path: String = ART % art_name
	var tex: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	_tex_cache[art_name] = tex
	return tex


## The drone is the game's own, from the prologue set — one drone across every
## screen, not a second design that happens to look similar.
func _tex_drone() -> Texture2D:
	if _tex_cache.has("__drone"):
		return _tex_cache["__drone"]
	var tex: Texture2D = load(DRONE_ART) as Texture2D if ResourceLoader.exists(DRONE_ART) else null
	_tex_cache["__drone"] = tex
	return tex
