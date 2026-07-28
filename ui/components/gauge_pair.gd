class_name GaugePair
extends Control

## The mirrored twin gauge from the original's fight HUD. Dossier §10 [C]:
##
##   FREDDY                                        AGATHA
##   ████████████████  LOSS  ██████████████████
##   ██████████        STM   ████████
##
## "The distinctive touch is the mirrored twin-gauge layout: the label sits in
## the centre and each fighter's bar grows *outward from the centre toward their
## own side*. Row 1 is LOSS (damage/health, red-orange), row 2 is STM (stamina,
## orange-yellow)."
##
## Remember the naming trap (dossier §3 [C]): the LOSS row is the STRENGTH stat.
## Strength IS the health bar; Power is damage. There is no separate HP.
##
## Pure presentation — it is handed four fractions and draws them. It never
## reads a Monkey, never touches GameState and never computes anything.
## `docs/reference/screens-kog/145.png` is the layout this copies.

## Row geometry. The strip is 184 tall, which is what `custom_minimum_size`
## in gauge_pair.tscn is set to.
const NAME_ROW_H := 60.0
const ROW_H := 56.0
const ROW_GAP := 12.0
## The dead zone in the middle that the centred LOSS / STM label sits in. Both
## bars stop here and grow away from it.
const CENTRE_GAP := 220.0
const BAR_INSET := 6.0

## How fast a drawn bar chases its target, in bar-fractions per second. Slow
## enough that a big hit visibly drains rather than snapping.
const FILL_SPEED := 1.35
## A row flashes when the fighter on that side just took damage.
const FLASH_SECONDS := 0.30


var _left_name: String = "PLAYER"
var _right_name: String = "RIVAL"
var _left_color: Color = Palette.INK_LIGHT
var _right_color: Color = Palette.INK_LIGHT

var _target := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var _shown := PackedFloat32Array([1.0, 1.0, 1.0, 1.0])
var _flash_left := 0.0
var _flash_right := 0.0

@onready var _left_label: Label = $LeftName
@onready var _right_label: Label = $RightName
@onready var _loss_label: Label = $LossLabel
@onready var _stm_label: Label = $StmLabel


func _ready() -> void:
	custom_minimum_size.y = NAME_ROW_H + ROW_H * 2.0 + ROW_GAP
	_loss_label.text = "LOSS"
	_stm_label.text = "STM"
	for label in [_left_label, _right_label, _loss_label, _stm_label]:
		label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_loss_label.add_theme_color_override("font_color", Palette.GAUGE_LOSS)
	_stm_label.add_theme_color_override("font_color", Palette.GAUGE_STM)
	_apply_names()
	_layout()
	set_process(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()


func _process(delta: float) -> void:
	var dirty := false
	for i in 4:
		var to: float = _target[i]
		var from: float = _shown[i]
		if is_equal_approx(from, to):
			continue
		var step := FILL_SPEED * delta
		_shown[i] = to if absf(to - from) <= step else from + signf(to - from) * step
		dirty = true
	if _flash_left > 0.0:
		_flash_left = maxf(0.0, _flash_left - delta)
		dirty = true
	if _flash_right > 0.0:
		_flash_right = maxf(0.0, _flash_right - delta)
		dirty = true
	if dirty:
		queue_redraw()


# --- public API --------------------------------------------------------------

## Name each corner and colour it. Colours come from `Palette.monkey_accent()`
## so the two fighters read apart at a glance.
func configure(left: String, right: String, left_color: Color, right_color: Color) -> void:
	_left_name = left.to_upper()
	_right_name = right.to_upper()
	_left_color = left_color
	_right_color = right_color
	if is_node_ready():
		_apply_names()


## Four fractions in 0..1: left LOSS, left STM, right LOSS, right STM. The bars
## animate toward these.
func set_values(left_loss: float, left_stm: float, right_loss: float, right_stm: float) -> void:
	_target[0] = clampf(left_loss, 0.0, 1.0)
	_target[1] = clampf(left_stm, 0.0, 1.0)
	_target[2] = clampf(right_loss, 0.0, 1.0)
	_target[3] = clampf(right_stm, 0.0, 1.0)


## Jump straight to the current targets — used at the opening bell.
func snap() -> void:
	for i in 4:
		_shown[i] = _target[i]
	queue_redraw()


## Flash the side that just ate a punch.
func flash(left_side: bool) -> void:
	if left_side:
		_flash_left = FLASH_SECONDS
	else:
		_flash_right = FLASH_SECONDS
	queue_redraw()


# --- layout ------------------------------------------------------------------

func _apply_names() -> void:
	_left_label.text = _left_name
	_right_label.text = _right_name
	_left_label.add_theme_color_override("font_color", _left_color)
	_right_label.add_theme_color_override("font_color", _right_color)


func _layout() -> void:
	if not is_node_ready():
		return
	var mid := size.x * 0.5
	var half_gap := CENTRE_GAP * 0.5
	var side := maxf(0.0, mid - half_gap)

	_left_label.position = Vector2(0.0, 0.0)
	_left_label.size = Vector2(side + half_gap, NAME_ROW_H)
	_left_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_left_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_right_label.position = Vector2(mid - half_gap, 0.0)
	_right_label.size = Vector2(side + half_gap, NAME_ROW_H)
	_right_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	_loss_label.position = Vector2(mid - half_gap, NAME_ROW_H)
	_loss_label.size = Vector2(CENTRE_GAP, ROW_H)
	_stm_label.position = Vector2(mid - half_gap, NAME_ROW_H + ROW_H + ROW_GAP)
	_stm_label.size = Vector2(CENTRE_GAP, ROW_H)
	for label in [_loss_label, _stm_label]:
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# --- drawing -----------------------------------------------------------------

func _draw() -> void:
	var mid := size.x * 0.5
	var half_gap := CENTRE_GAP * 0.5
	var side := maxf(0.0, mid - half_gap)
	if side <= 0.0:
		return
	var y_loss := NAME_ROW_H
	var y_stm := NAME_ROW_H + ROW_H + ROW_GAP
	var bar_h := ROW_H - BAR_INSET * 2.0

	_draw_row(y_loss + BAR_INSET, bar_h, side, half_gap, mid,
		_shown[0], _shown[2], Palette.GAUGE_LOSS, Palette.GAUGE_LOSS_BG)
	_draw_row(y_stm + BAR_INSET, bar_h, side, half_gap, mid,
		_shown[1], _shown[3], Palette.GAUGE_STM, Palette.GAUGE_STM_BG)


## One mirrored row. `left_frac` grows LEFT from the centre gap and `right_frac`
## grows RIGHT from it — that outward growth is the whole point of the layout.
func _draw_row(y: float, h: float, side: float, half_gap: float, mid: float,
		left_frac: float, right_frac: float, fill: Color, track: Color) -> void:
	var left_track := Rect2(mid - half_gap - side, y, side, h)
	var right_track := Rect2(mid + half_gap, y, side, h)
	draw_rect(left_track, track)
	draw_rect(right_track, track)

	var left_w := side * left_frac
	if left_w > 0.0:
		draw_rect(Rect2(mid - half_gap - left_w, y, left_w, h), _tint(fill, _flash_left))
	var right_w := side * right_frac
	if right_w > 0.0:
		draw_rect(Rect2(mid + half_gap, y, right_w, h), _tint(fill, _flash_right))

	# The original's chunky black outline (dossier §10 [C]).
	draw_rect(left_track, Palette.INK, false, 4.0)
	draw_rect(right_track, Palette.INK, false, 4.0)


func _tint(base: Color, flash: float) -> Color:
	if flash <= 0.0:
		return base
	return base.lerp(Palette.INK_LIGHT, clampf(flash / FLASH_SECONDS, 0.0, 1.0) * 0.8)
