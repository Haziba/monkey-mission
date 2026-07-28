class_name StatCard
extends PanelContainer

## The stat card, in the original's layout (dossier §10 [C]):
##
##     POW  74      NAME: MAX(ML)
##     SPD  65      JSB RANK: 13
##     KNOW 56      INCOME  ¥8000
##     STRG 61
##     STM  83
##
## Five stat rows on the left, three identity rows on the right. A **star** on a
## capped stat (§3 [C]: `Pow 500*` — training cannot exceed it, only breeding
## raises it).
##
## ADDITIONS to the original's card, because the brief asks for them on the home
## screen: a bar per stat showing how close it is to its own ceiling, the
## friendship and fullness meters, and a status banner that says plainly why the
## monkey will not obey. All three are read-outs of confirmed mechanics — hunger
## paralysis in both directions (§5 [C]) and friendship gating training and
## in-fight obedience (§5, §6 [C]) — which the original only ever expressed as
## animation. On a phone, with no sprite work to lean on, they have to be text.
##
## Dumb component: it never touches GameState. The screen hands it everything,
## including the block reason, which is core's own string from `Care`.

## The rank ladder is written `JSB` in-game. Dossier §14.1 [X]: what JSB stands
## for is unknown — do not invent an expansion.
const RANK_PREFIX := "JSB RANK"
## §10 [C] the card's money row is labelled INCOME, in yen.
const MONEY_PREFIX := "INCOME"

@onready var _stat_rows: VBoxContainer = $Pad/Rows/Columns/Stats
@onready var _name_line: Label = $Pad/Rows/Columns/Info/NameLine
@onready var _rank_line: Label = $Pad/Rows/Columns/Info/RankLine
@onready var _money_line: Label = $Pad/Rows/Columns/Info/MoneyLine
@onready var _gen_line: Label = $Pad/Rows/Columns/Info/GenLine
@onready var _record_line: Label = $Pad/Rows/Columns/Info/RecordLine
@onready var _friend_label: Label = $Pad/Rows/Meters/Friendship/Caption
@onready var _friend_bar: ProgressBar = $Pad/Rows/Meters/Friendship/Bar
@onready var _full_label: Label = $Pad/Rows/Meters/Fullness/Caption
@onready var _full_bar: ProgressBar = $Pad/Rows/Meters/Fullness/Bar
@onready var _status: PanelContainer = $Pad/Rows/Status
@onready var _status_label: Label = $Pad/Rows/Status/Text

var _monkey: Monkey = null
var _rank: int = 0
var _money: int = 0
var _block_reason: String = ""

## Monkey.Stat -> { "label": Label, "value": Label, "bar": ProgressBar }
var _rows: Dictionary = {}


func _ready() -> void:
	_build_rows()
	_style_meters()
	refresh()


## The screen's one entry point. `block_reason` is `GameState.block_reason()`.
func set_monkey(monkey: Monkey, rank: int, money: int, block_reason: String = "") -> void:
	_monkey = monkey
	_rank = rank
	_money = money
	_block_reason = block_reason
	refresh()


func refresh() -> void:
	if not is_node_ready():
		return
	if _monkey == null:
		_show_empty()
		return

	for stat in Monkey.STATS:
		var row: Dictionary = _rows[stat]
		var value: int = _monkey.get_stat(stat)
		var cap: int = _monkey.get_cap(stat)
		var capped: bool = _monkey.is_capped(stat)
		var value_label: Label = row["value"]
		# §3 [C]: a capped stat displays a star.
		value_label.text = "%d%s" % [value, "*" if capped else ""]
		value_label.add_theme_color_override(
			"font_color", Palette.STAT_CAPPED if capped else Palette.INK_LIGHT)
		var bar: ProgressBar = row["bar"]
		bar.max_value = maxf(1.0, float(cap))
		bar.value = float(value)
		_tint_bar(bar, Palette.STAT_CAPPED if capped else Palette.stat_color(stat))

	# §10 [C] shows `NAME: MAX(ML)` — Monkey owns the formatting and the marker.
	_name_line.text = _monkey.name_line()
	_rank_line.text = "%s: %d" % [RANK_PREFIX, _rank]
	_money_line.text = "%s  ¥%d" % [MONEY_PREFIX, _money]
	_gen_line.text = "GEN %d" % _monkey.generation
	_record_line.text = "%dW  %dL" % [_monkey.wins, _monkey.losses]

	_refresh_friendship()
	_refresh_fullness()
	_refresh_status()


func _refresh_friendship() -> void:
	var friendship := _monkey.friendship
	_friend_bar.max_value = float(Monkey.FRIENDSHIP_MAX)
	_friend_bar.value = float(friendship)
	_tint_bar(_friend_bar, Palette.FRIENDSHIP if _monkey.is_befriended() else Palette.BAD)
	_friend_label.text = "FRIENDSHIP %d/%d  %s" % [
		friendship, Monkey.FRIENDSHIP_MAX, _friendship_band(friendship)]


func _refresh_fullness() -> void:
	var fullness := _monkey.fullness
	_full_bar.max_value = float(Monkey.FULLNESS_MAX)
	_full_bar.value = float(fullness)
	# Red at BOTH ends — Palette owns that rule because both extremes paralyse.
	_tint_bar(_full_bar, Palette.fullness_color(fullness))
	_full_label.text = "FULLNESS %d/%d  %s" % [
		fullness, Monkey.FULLNESS_MAX, _fullness_band(fullness)]


func _refresh_status() -> void:
	var style: StyleBoxFlat = _status.get_theme_stylebox("panel").duplicate()
	if _block_reason.is_empty():
		_status_label.text = "READY."
		style.bg_color = Palette.GOOD
		_status_label.add_theme_color_override("font_color", Palette.INK)
	else:
		_status_label.text = _block_reason
		style.bg_color = Palette.BAD
		_status_label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	style.border_color = Palette.INK
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	_status.add_theme_stylebox_override("panel", style)


## Friendship bands. Both thresholds are Monkey's, so the wording can never
## disagree with the gate that actually fires (§5, §6 [C]).
static func _friendship_band(friendship: int) -> String:
	if friendship < Monkey.FRIENDSHIP_TRAIN_MIN:
		return "(WON'T TRAIN)"
	if friendship < Monkey.FRIENDSHIP_OBEDIENT:
		return "(MAY DISOBEY)"
	return "(LOYAL)"


## Fullness bands, read straight off Care's constants so the label and the
## paralysis gate cannot drift apart. Dossier §5 [C]: the guides' rule is to
## feed only when the monkey cannot move, never when merely peckish — so the
## band names have to make "FULL" read as a warning, not an invitation.
static func _fullness_band(fullness: int) -> String:
	if fullness <= Monkey.FULLNESS_STARVING:
		return "(STARVING - CAN'T MOVE)"
	if fullness >= Monkey.FULLNESS_STUFFED:
		return "(STUFFED - CAN'T MOVE)"
	if fullness <= Care.FULLNESS_HUNGRY_MAX:
		return "(HUNGRY - FEED IT)"
	if fullness <= Care.FULLNESS_CONTENT_MAX:
		return "(CONTENT)"
	return "(FULL - DON'T FEED)"


func _show_empty() -> void:
	for stat in Monkey.STATS:
		var row: Dictionary = _rows[stat]
		var value_label: Label = row["value"]
		value_label.text = "--"
		value_label.add_theme_color_override("font_color", Palette.DISABLED)
		var bar: ProgressBar = row["bar"]
		bar.value = 0.0
	_name_line.text = "NAME: ---"
	_rank_line.text = "%s: -" % RANK_PREFIX
	_money_line.text = "%s  ¥0" % MONEY_PREFIX
	_gen_line.text = ""
	_record_line.text = ""
	_friend_label.text = "FRIENDSHIP -"
	_full_label.text = "FULLNESS -"
	_friend_bar.value = 0.0
	_full_bar.value = 0.0
	_status_label.text = "NO MONKEY."
	_refresh_status()


## Wire the five rows the .tscn declares to their Monkey.Stat, in enum order —
## POW / SPD / KNOW / STRG / STM, exactly the order the original's card prints.
func _build_rows() -> void:
	_rows.clear()
	for index in Monkey.STATS.size():
		var stat: Monkey.Stat = Monkey.STATS[index]
		var row: HBoxContainer = _stat_rows.get_child(index)
		var label: Label = row.get_node("Name")
		var value: Label = row.get_node("Value")
		var bar: ProgressBar = row.get_node("Bar")
		label.text = Monkey.stat_label(stat)
		label.add_theme_color_override("font_color", Palette.stat_color(stat))
		label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		value.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		_tint_bar(bar, Palette.stat_color(stat))
		_rows[stat] = {"label": label, "value": value, "bar": bar}


func _style_meters() -> void:
	for label in [_friend_label, _full_label]:
		label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	for line in [_name_line, _rank_line, _money_line]:
		line.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		line.add_theme_color_override("font_color", Palette.INK_LIGHT)
	for line in [_gen_line, _record_line]:
		line.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		line.add_theme_color_override("font_color", Palette.ACCENT_ALT)
	_status_label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_tint_bar(_friend_bar, Palette.FRIENDSHIP)
	_tint_bar(_full_bar, Palette.FULLNESS)


## Placeholder-shape bar: two flat StyleBoxes, no textures anywhere.
func _tint_bar(bar: ProgressBar, color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Palette.PANEL_DARK
	background.border_color = Palette.INK
	background.set_border_width_all(4)
	background.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(6)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
