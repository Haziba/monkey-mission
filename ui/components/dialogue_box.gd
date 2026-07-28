class_name DialogueBox
extends Control

## The reusable story-text box. Portrait plate on top, nameplate, paper message
## box with a typewriter reveal and the small blinking continue arrow the
## original shows (docs/reference/screens-hg101/Bill.png, dialogue-7.png).
##
## Layout follows the original (dossier §10 [C]): "Delivery is static portraits
## and text boxes." The portrait is a near-full-screen character plate, the text
## box is pinned to the bottom, and the speaker's name is printed in angle
## brackets — `<BILL>`.
##
## ART IS PLACEHOLDER SHAPES. The portrait is a flat per-speaker fill with the
## chunky checkerboard field the dossier calls a recurring UI motif (§10 [C])
## and a large monogram. No image files.
##
## Input: tap anywhere to advance; tapping while the text is still revealing
## completes the reveal instead of skipping the line.
##
## Usage:
##     var lines := []
##     lines.append(DialogueBox.make_line("FRED", "Well now.", Color.RED))
##     box.play(lines)
##     await box.finished

## The reveal for the current line completed (by timer or by tap).
signal reveal_finished()
## A new line was put on screen. `index` is its position in the played queue.
signal line_shown(index: int)
## The queue drained.
signal finished()

## DIVERGENCE: the original's text speed is [X] — no source measures it. 42 is
## fast enough that a 140-character line lands in about three seconds, which
## keeps a 35-line prologue under two minutes for a player who never taps.
const CHARS_PER_SECOND := 42.0
## Continue-arrow blink period, in seconds.
const ARROW_BLINK := 0.5
## Height of the paper message box. The portrait plate takes whatever is left.
const TEXT_BOX_HEIGHT := 420
const NAMEPLATE_HEIGHT := 88
const NAMEPLATE_WIDTH := 480

## When true the box swallows taps itself. Turn it off if the owning screen
## wants to drive `advance()` from its own input handling.
@export var capture_input: bool = true

@onready var _portrait: Control = $Portrait
@onready var _monogram: Label = $Portrait/Monogram
@onready var _nameplate: PanelContainer = $Nameplate
@onready var _name_label: Label = $Nameplate/NameLabel
@onready var _text_box: PanelContainer = $TextBox
@onready var _text_label: Label = $TextBox/Margin/TextLabel
@onready var _arrow: Label = $Arrow

## Array of Dictionary, see `make_line`.
var _lines: Array = []
var _index: int = -1
var _revealing: bool = false
var _revealed_chars: float = 0.0
var _blink_t: float = 0.0
var _portrait_color: Color = Palette.PANEL


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP if capture_input else Control.MOUSE_FILTER_IGNORE
	_apply_styles()
	_portrait.draw.connect(_draw_portrait)
	_nameplate.visible = false
	_arrow.visible = false
	_text_label.visible_characters = 0
	set_process(true)


func _apply_styles() -> void:
	# Built from Palette rather than baked into the .tscn so there is exactly one
	# source of truth for colour.
	_text_box.add_theme_stylebox_override("panel", _paper_box(Palette.PAPER))
	_nameplate.add_theme_stylebox_override("panel", _paper_box(Palette.SELECTION))
	_text_label.add_theme_color_override("font_color", Palette.INK)
	_text_label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_name_label.add_theme_color_override("font_color", Palette.INK)
	_name_label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_monogram.add_theme_color_override("font_color", Palette.INK)
	_monogram.add_theme_font_size_override("font_size", 240)
	_arrow.add_theme_color_override("font_color", Palette.INK)
	_arrow.add_theme_font_size_override("font_size", Palette.FONT_BODY)


static func _paper_box(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Palette.INK
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(Palette.CORNER_RADIUS)
	return sb


# --- the queue -------------------------------------------------------------

## Build one entry for `play()`. `speaker_name` "" means narration: no nameplate.
static func make_line(speaker_name: String, text: String, portrait_color: Color,
		monogram: String = "") -> Dictionary:
	var mark := monogram
	if mark == "":
		mark = speaker_name.substr(0, 1) if speaker_name != "" else "..."
	return {
		"name": speaker_name,
		"text": text,
		"color": portrait_color,
		"monogram": mark,
	}


## Replace the queue and show the first line.
func play(lines: Array) -> void:
	_lines = lines.duplicate()
	_index = -1
	if _lines.is_empty():
		finished.emit()
		return
	_next()


## Show a single line, outside any queue.
func show_line(line: Dictionary) -> void:
	_portrait_color = line.get("color", Palette.PANEL)
	_portrait.queue_redraw()
	var speaker_name := String(line.get("name", ""))
	_nameplate.visible = speaker_name != ""
	_name_label.text = "<%s>" % speaker_name.to_upper()
	_monogram.text = String(line.get("monogram", "..."))
	_text_label.text = String(line.get("text", ""))
	_text_label.visible_characters = 0
	_revealed_chars = 0.0
	_revealing = _text_label.text.length() > 0
	_show_arrow(not _revealing)


func is_revealing() -> bool:
	return _revealing


func is_last_line() -> bool:
	return _index >= _lines.size() - 1


## Tap handling: finish the reveal if it is still running, otherwise step on.
func advance() -> void:
	if _revealing:
		skip_reveal()
		return
	_next()


## Complete the current line's reveal immediately.
func skip_reveal() -> void:
	if not _revealing:
		return
	_revealing = false
	_text_label.visible_characters = -1
	_revealed_chars = float(_text_label.text.length())
	_show_arrow(true)
	reveal_finished.emit()


func _show_arrow(shown: bool) -> void:
	_arrow.visible = shown
	_arrow.modulate.a = 1.0
	_blink_t = 0.0


func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_show_arrow(false)
		finished.emit()
		return
	show_line(_lines[_index])
	line_shown.emit(_index)


# --- reveal + blink --------------------------------------------------------

func _process(delta: float) -> void:
	if _revealing:
		_revealed_chars += CHARS_PER_SECOND * delta
		var total := _text_label.text.length()
		if int(_revealed_chars) >= total:
			_revealing = false
			_text_label.visible_characters = -1
			_show_arrow(true)
			reveal_finished.emit()
		else:
			_text_label.visible_characters = int(_revealed_chars)
		return
	if _arrow.visible:
		_blink_t += delta
		if _blink_t >= ARROW_BLINK:
			_blink_t -= ARROW_BLINK
			_arrow.modulate.a = 1.0 if _arrow.modulate.a < 0.5 else 0.0


func _gui_input(event: InputEvent) -> void:
	if not capture_input:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		accept_event()
		advance()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		accept_event()
		advance()


func _unhandled_input(event: InputEvent) -> void:
	if not capture_input or not is_visible_in_tree():
		return
	if event.is_action_pressed("mp_tap"):
		get_viewport().set_input_as_handled()
		advance()


# --- the placeholder portrait ---------------------------------------------

## Flat fill plus the chunky checkerboard field the original uses as a recurring
## UI motif (dossier §10 [C]). Placeholder shapes only — no sprites.
func _draw_portrait() -> void:
	var rect := Rect2(Vector2.ZERO, _portrait.size)
	_portrait.draw_rect(rect, _portrait_color)

	var dark := _portrait_color.darkened(0.28)
	var cell := 60.0
	var rows := int(ceil(rect.size.y / cell))
	var cols := int(ceil(rect.size.x / cell))
	for row in rows:
		for col in cols:
			if (row + col) % 2 == 1:
				continue
			# Fade the checkerboard out towards the middle so the monogram reads.
			var band := float(row) / maxf(1.0, float(rows))
			if band > 0.25 and band < 0.75:
				continue
			_portrait.draw_rect(
				Rect2(col * cell, row * cell, cell, cell).intersection(rect), dark)

	# A "shoulders" band, so the plate reads as a character card rather than a
	# flat colour swatch.
	var shoulder_h := rect.size.y * 0.22
	_portrait.draw_rect(
		Rect2(rect.size.x * 0.16, rect.size.y - shoulder_h,
			rect.size.x * 0.68, shoulder_h),
		_portrait_color.darkened(0.45))
	_portrait.draw_rect(
		Rect2(0.0, rect.size.y - Palette.BORDER_WIDTH, rect.size.x,
			float(Palette.BORDER_WIDTH)),
		Palette.INK)


# --- speaker tinting -------------------------------------------------------

## `IntroScript.Speaker` -> portrait colour. Lives in the UI layer on purpose:
## `core/data/intro_script.gd` must not know Palette exists.
##
## `protagonist` is a RunState.Protagonist value, so Kenta and Sumire get their
## own plate colours and the sibling gets the other one.
static func speaker_color(speaker: int, protagonist: int) -> Color:
	match speaker:
		IntroScript.Speaker.NARRATOR:
			return Palette.PANEL_DARK
		IntroScript.Speaker.PLAYER:
			return protagonist_color(protagonist)
		IntroScript.Speaker.SIBLING:
			return protagonist_color(1 - protagonist)
		IntroScript.Speaker.FATHER:
			return Palette.PANEL
		IntroScript.Speaker.FRED:
			return Palette.ACCENT
		IntroScript.Speaker.BILL:
			return Palette.PANEL_LIGHT
		IntroScript.Speaker.SARU:
			return Palette.LOC_STREET
	return Palette.PANEL


## Kenta and Sumire's plate colours. Dossier §11 [C]: the choice is the TRAINER,
## not the monkey — the widely repeated "choose a male or female monkey" claim
## is wrong (§14).
static func protagonist_color(protagonist: int) -> Color:
	return Palette.ACCENT_ALT if protagonist == 0 else Palette.FRIENDSHIP
