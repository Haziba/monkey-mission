class_name DayEndScreen
extends GameScreen

## The end-of-day beat.
##
## Dossier §10 [C] and `docs/reference/screens-hg101/end-of-day.png`: the
## original closes a day on a large character portrait standing over radiating
## sunburst lines, the monkey beside the trainer with an arm thrown up, and a
## bordered text box across the bottom carrying an encouraging line
## ("TOMORROW I'LL ALSO WORK HARD."). That is the beat this screen keeps.
##
## ART IS STAND-IN ART (ARCHITECTURE §17). The portraits are flat Panels, the
## sunburst is a `draw_colored_polygon` fan — drawn rather than generated because
## it is cheaper here, not because images are forbidden.
##
## Layering: this screen reads `GameState` and nothing else. It computes no
## gains — it only reports numbers that core already produced.
##
## ---------------------------------------------------------------------------
## PARAMS (every key optional; the screen degrades to whatever it can see)
##
##   "day":              int                    — day number to print
##   "gains":            Dictionary             — Monkey.Stat -> int stat delta
##   "money_delta":      int
##   "friendship_delta": int
##   "lines":            Array[String]          — extra event lines
##   "line":             String                 — override the encouraging line
##   "next_screen":      int                    — Router.Screen to replace with
##
## Whoever owns the day loop can instead call
## `DayEndScreen.note_day_start(monkey, money)` at the top of each day and push
## this screen with no params at all — it diffs the snapshot itself. Pressing
## NEXT DAY re-takes the snapshot so the next day starts clean.

# DIVERGENCE: the dossier records exactly one end-of-day line
# ("TOMORROW I'LL ALSO WORK HARD.", §10 / end-of-day.png) and gives no others.
# The rest are written in the same register — the original's localisation is
# blunt, upbeat and all-caps (§10 [C]) — because one line repeated every day
# for a whole slice reads as a bug rather than a beat.
const ENCOURAGING_LINES: PackedStringArray = [
	"TOMORROW I'LL ALSO WORK HARD.",
	"GOOD WORK TODAY!",
	"WE'RE GETTING STRONGER!",
	"REST WELL. TOMORROW WE GO AGAIN.",
	"THAT WAS A GOOD DAY'S TRAINING!",
]

## Snapshot taken at the top of a day, so the screen can diff it at the bottom.
## Static because the screen does not exist while the day is being played.
static var _snapshot: Dictionary = {}


## Radiating wedge fan — the sunburst the original puts behind its end-of-day
## and "X WAS BORN" portraits (§10 [C]; end-of-day.png, new-monkey-2.png).
## Shared with `breeding_screen.gd`, which stages the same beat for the birth
## reveal; it lives here because this is the screen the dossier ties it to.
class Sunburst extends Control:
	var ray_color: Color = Palette.WARN
	var back_color: Color = Palette.ACCENT
	var rays: int = 13
	var spin: float = 0.0
	## DIVERGENCE: the original is a static screen; a slow rotation is a
	## mobile-era addition to stop a still image reading as a frozen game.
	var spin_speed: float = 0.09

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		spin += delta * spin_speed
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), back_color)
		var centre := size * 0.5
		var radius := size.length()
		var step := TAU / float(maxi(1, rays) * 2)
		for i in rays:
			var angle := spin + float(i) * step * 2.0
			draw_colored_polygon(PackedVector2Array([
				centre,
				centre + Vector2(radius, 0.0).rotated(angle),
				centre + Vector2(radius, 0.0).rotated(angle + step),
			]), ray_color)


@onready var _bg: ColorRect = $Bg
@onready var _day_label: Label = $Margin/Root/HeaderRow/DayBox/DayMargin/DayLabel
@onready var _name_label: Label = $Margin/Root/HeaderRow/NameBox/NameMargin/NameLabel
@onready var _stage: PanelContainer = $Margin/Root/Stage
@onready var _stage_inner: Control = $Margin/Root/Stage/StageInner
@onready var _summary_list: VBoxContainer = $Margin/Root/SummaryPanel/SummaryMargin/SummaryList
@onready var _message: Label = $Margin/Root/TextBox/TextMargin/MessageLabel
@onready var _next: Button = $Margin/Root/NextButton

var _trainer_panel: Panel = null
var _monkey_panel: Panel = null
var _monkey_arm: Panel = null
var _monkey_caption: Label = null
var _trainer_caption: Label = null


## Record where the day started so the screen can report what it earned. Safe
## to call every morning; safe never to call at all.
static func note_day_start(monkey: Monkey, money: int) -> void:
	if monkey == null:
		_snapshot = {}
		return
	var stats := {}
	for stat in Monkey.STATS:
		stats[stat] = monkey.get_stat(stat)
	_snapshot = {
		"name": monkey.monkey_name,
		"generation": monkey.generation,
		"stats": stats,
		"money": money,
		"friendship": monkey.friendship,
		"wins": monkey.wins,
		"losses": monkey.losses,
	}


static func clear_snapshot() -> void:
	_snapshot = {}


func _ready() -> void:
	super()
	_bg.color = Palette.BG
	_stage.add_theme_stylebox_override("panel", _box(Palette.PANEL_DARK))
	_summary_list.get_parent().get_parent().add_theme_stylebox_override(
		"panel", _box(Palette.PANEL))
	_message.get_parent().get_parent().add_theme_stylebox_override(
		"panel", _box(Palette.PAPER))
	_message.add_theme_color_override("font_color", Palette.INK)
	_build_stage()
	if not _next.pressed.is_connected(_on_next):
		_next.pressed.connect(_on_next)
	_refresh()


func on_enter(params: Dictionary) -> void:
	super(params)
	_refresh()


# --- staging ---------------------------------------------------------------

func _build_stage() -> void:
	var sun := Sunburst.new()
	sun.name = "Sunburst"
	sun.set_anchors_preset(Control.PRESET_FULL_RECT)
	sun.ray_color = Palette.WARN
	sun.back_color = Palette.ACCENT
	_stage_inner.add_child(sun)

	# The monkey, small and to the left with an arm thrown up (end-of-day.png).
	_monkey_panel = Panel.new()
	_monkey_panel.name = "MonkeyPortrait"
	_place(_monkey_panel, 0.05, 0.44, 0.40, 1.0)
	_stage_inner.add_child(_monkey_panel)

	_monkey_arm = Panel.new()
	_monkey_arm.name = "MonkeyArm"
	_place(_monkey_arm, 0.30, 0.26, 0.42, 0.50)
	_stage_inner.add_child(_monkey_arm)

	_monkey_caption = _caption()
	_place(_monkey_caption, 0.05, 0.86, 0.40, 1.0)
	_stage_inner.add_child(_monkey_caption)

	# The trainer, large and to the right — the original's near-full-screen
	# manga portrait register (§10 [C]), here a rectangle.
	_trainer_panel = Panel.new()
	_trainer_panel.name = "TrainerPortrait"
	_trainer_panel.add_theme_stylebox_override("panel", _box(Palette.PANEL_LIGHT))
	_place(_trainer_panel, 0.40, 0.08, 0.95, 1.0)
	_stage_inner.add_child(_trainer_panel)

	_trainer_caption = _caption()
	_place(_trainer_caption, 0.40, 0.86, 0.95, 1.0)
	_stage_inner.add_child(_trainer_caption)


func _caption() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	label.add_theme_color_override("font_color", Palette.INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _place(control: Control, left: float, top: float, right: float, bottom: float) -> void:
	control.anchor_left = left
	control.anchor_top = top
	control.anchor_right = right
	control.anchor_bottom = bottom
	control.offset_left = 0.0
	control.offset_top = 0.0
	control.offset_right = 0.0
	control.offset_bottom = 0.0


# --- content ---------------------------------------------------------------

func _refresh() -> void:
	if _summary_list == null:
		return
	var monkey := GameState.monkey()
	var day := int(enter_params.get("day", GameState.day()))
	_day_label.text = "DAYS %d  PM" % day
	_name_label.text = "[%s]" % (monkey.monkey_name.to_upper() if monkey != null else "—")

	var body := Palette.monkey_color(monkey.species_type) if monkey != null else Palette.DISABLED
	var accent := Palette.monkey_accent(monkey.species_type) if monkey != null else Palette.PANEL_DARK
	_monkey_panel.add_theme_stylebox_override("panel", _box(body))
	_monkey_arm.add_theme_stylebox_override("panel", _box(accent))
	_monkey_caption.text = monkey.monkey_name.to_upper() if monkey != null else ""
	_trainer_caption.text = _trainer_name()

	var summary := _collect_summary(monkey)
	_fill_summary(summary)
	_message.text = String(enter_params.get("line", _encouraging_line(day)))


## Gathers what the day produced. Params always win over the snapshot diff, so
## a caller that tracked its own numbers can hand them straight in.
func _collect_summary(monkey: Monkey) -> Dictionary:
	var gains := {}
	var money_delta := 0
	var friendship_delta := 0
	var lines: Array[String] = []

	var snapshot_matches := (
		monkey != null
		and not _snapshot.is_empty()
		and String(_snapshot.get("name", "")) == monkey.monkey_name
		and int(_snapshot.get("generation", -1)) == monkey.generation
	)
	if snapshot_matches:
		var before: Dictionary = _snapshot.get("stats", {})
		for stat in Monkey.STATS:
			var delta := monkey.get_stat(stat) - int(before.get(stat, monkey.get_stat(stat)))
			if delta != 0:
				gains[stat] = delta
		money_delta = GameState.money() - int(_snapshot.get("money", GameState.money()))
		friendship_delta = monkey.friendship - int(_snapshot.get("friendship", monkey.friendship))
		var wins := monkey.wins - int(_snapshot.get("wins", monkey.wins))
		var losses := monkey.losses - int(_snapshot.get("losses", monkey.losses))
		if wins > 0:
			lines.append("WON IN THE RING.")
		if losses > 0:
			lines.append("LOST IN THE RING. TOMORROW IS ANOTHER DAY.")

	if enter_params.has("gains") and enter_params["gains"] is Dictionary:
		gains = enter_params["gains"]
	if enter_params.has("money_delta"):
		money_delta = int(enter_params["money_delta"])
	if enter_params.has("friendship_delta"):
		friendship_delta = int(enter_params["friendship_delta"])
	for extra in enter_params.get("lines", []):
		lines.append(String(extra))

	return {
		"gains": gains,
		"money_delta": money_delta,
		"friendship_delta": friendship_delta,
		"lines": lines,
	}


func _fill_summary(summary: Dictionary) -> void:
	for child in _summary_list.get_children():
		_summary_list.remove_child(child)
		child.queue_free()

	var heading := Label.new()
	heading.text = "TODAY'S WORK"
	heading.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	heading.add_theme_color_override("font_color", Palette.SELECTION)
	_summary_list.add_child(heading)

	var monkey := GameState.monkey()
	var printed := 0
	var gains: Dictionary = summary["gains"]
	for stat in Monkey.STATS:
		if not gains.has(stat):
			continue
		var delta := int(gains[stat])
		if delta == 0:
			continue
		var starred := monkey != null and monkey.is_capped(stat)
		var value := monkey.get_stat(stat) if monkey != null else 0
		var text := "%-4s  %+d   ->  %d%s" % [
			Monkey.stat_label(stat), delta, value, "*" if starred else "",
		]
		if starred:
			text += "   CEILING REACHED"
		_summary_list.add_child(_row(text, Palette.stat_color(stat)))
		printed += 1

	var friendship_delta := int(summary["friendship_delta"])
	if friendship_delta != 0:
		_summary_list.add_child(_row(
			"FRIENDSHIP  %+d" % friendship_delta,
			Palette.FRIENDSHIP if friendship_delta > 0 else Palette.BAD))
		printed += 1

	var money_delta := int(summary["money_delta"])
	if money_delta != 0:
		_summary_list.add_child(_row(
			"PURSE  %s" % _yen(money_delta),
			Palette.GOOD if money_delta > 0 else Palette.BAD))
		printed += 1

	for line in summary["lines"]:
		_summary_list.add_child(_row(String(line), Palette.INK_LIGHT))
		printed += 1

	if printed == 0:
		_summary_list.add_child(_row("A QUIET DAY. NOTHING GAINED, NOTHING LOST.", Palette.DISABLED))


func _row(text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _encouraging_line(day: int) -> String:
	# Deterministic on the day so the same evening always reads the same way.
	return ENCOURAGING_LINES[posmod(day, ENCOURAGING_LINES.size())]


func _trainer_name() -> String:
	# Dossier §11 [C]: you play whichever sibling was NOT taken by the Saru
	# Group. The common claim that the choice is a male or female MONKEY is
	# wrong (§14) — the choice is the trainer.
	if GameState.run == null:
		return "TRAINER"
	return "SUMIRE" if GameState.run.protagonist == RunState.Protagonist.SUMIRE else "KENTA"


func _on_next() -> void:
	Sfx.confirm()
	# Re-arm the snapshot so tomorrow diffs from tonight.
	note_day_start(GameState.monkey(), GameState.money())
	if enter_params.has("next_screen"):
		Router.replace(int(enter_params["next_screen"]) as Router.Screen)
		return
	close({"day_ended": true})


# --- shapes ----------------------------------------------------------------

static func _box(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Palette.INK
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	return style


static func _yen(amount: int) -> String:
	var sign_text := "+" if amount > 0 else ("-" if amount < 0 else "")
	var digits := str(absi(amount))
	var grouped := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "," + grouped
	return "%s¥%s" % [sign_text, grouped]
