class_name HudBoxes
extends HBoxContainer

## The original's HUD box row, rebuilt in placeholder shapes.
##
## Dossier §10 [C] documents exactly two shapes for this strip:
##
##   Overworld       two boxes  ->  [DAYS 2  AM]   [FREDDY]
##   Timed training  three boxes ->  [0:41]  [102]  [TOMATO]
##
## and notes that the name box carries a **mood glyph** — `[PIZZA♪]` when happy.
## `docs/reference/screens-kog/060.png` and `.../screens-hg101/menu-2.png` show
## the two layouts: thick-bordered rounded boxes, hard against the top of the
## screen, the two-box form pushed out to the left and right edges with a gap in
## the middle and the three-box form filling the width evenly.
##
## Pure presentation. It never reads GameState — the screen hands it values.

## Which of the two documented layouts to draw.
enum Mode { OVERWORLD, TRAINING }

## Mood glyphs for the name box. Only `♪` (happy) is attested — dossier §10 [C]
## shows `[PIZZA♪]`.
## DIVERGENCE: the glyphs for the other moods are [X]; no source lists a set.
## These are chosen to be readable at a glance and to map onto states the player
## must understand: both hunger extremes paralyse (§5 [C]) and an unbefriended
## monkey will not obey at all.
## The attested one renders flush against the name, exactly as `[PIZZA♪]`. The
## invented ones carry their own leading space where they would otherwise read
## as part of the name.
const GLYPH_HAPPY := "♪"
const GLYPH_NEUTRAL := ""
const GLYPH_ANGRY := "!"           ## it bites when upset (§10 [C] animation note)
const GLYPH_HUNGRY := "…"          ## sitting down, holding its stomach
const GLYPH_STUFFED := " zZ"       ## immobilised until it digests

@onready var _box_a: PanelContainer = $BoxA
@onready var _spacer: Control = $Spacer
@onready var _box_b: PanelContainer = $BoxB
@onready var _box_c: PanelContainer = $BoxC
@onready var _label_a: Label = $BoxA/TextA
@onready var _label_b: Label = $BoxB/TextB
@onready var _label_c: Label = $BoxC/TextC

var _mode: Mode = Mode.OVERWORLD


func _ready() -> void:
	add_theme_constant_override("separation", Palette.GUTTER)
	for box in [_box_a, _box_b, _box_c]:
		box.add_theme_stylebox_override("panel", _box_style())
	for label in [_label_a, _label_b, _label_c]:
		label.add_theme_color_override("font_color", Palette.INK)
		label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	set_mode(_mode)


## The two-box overworld strip: `[DAYS 2  AM]` and `[FREDDY♪]` (dossier §10 [C]).
func show_overworld(day: int, slot_label: String, monkey_name: String, glyph: String = "") -> void:
	set_mode(Mode.OVERWORLD)
	_label_a.text = "DAYS %d  %s" % [day, slot_label]
	_label_c.text = "%s%s" % [monkey_name.to_upper(), glyph]


## The three-box timed-training strip: `[0:41]`, `[102]`, `[TOMATO]` (§10 [C]).
func show_training(seconds_left: float, reps: int, monkey_name: String) -> void:
	set_mode(Mode.TRAINING)
	set_countdown(seconds_left)
	set_reps(reps)
	_label_c.text = monkey_name.to_upper()


func set_countdown(seconds_left: float) -> void:
	_label_a.text = format_clock(seconds_left)


func set_reps(reps: int) -> void:
	_label_b.text = str(reps)


func set_name_box(text: String) -> void:
	_label_c.text = text


## `0:41` — the exact form the dossier quotes for the training countdown.
static func format_clock(seconds_left: float) -> String:
	var whole := maxi(0, int(ceilf(seconds_left)))
	return "%d:%02d" % [whole / 60, whole % 60]


func set_mode(mode: Mode) -> void:
	_mode = mode
	var training := mode == Mode.TRAINING
	# Two-box mode keeps the boxes at the screen edges with a gap between them,
	# as in docs/reference/screens-hg101/menu-2.png; three-box mode fills the
	# width evenly, as in docs/reference/screens-kog/060.png.
	_box_b.visible = training
	_spacer.visible = not training
	for box in [_box_a, _box_b, _box_c]:
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL if training else Control.SIZE_FILL


func _box_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.HUD_BOX
	style.border_color = Palette.HUD_BOX_EDGE
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	return style
