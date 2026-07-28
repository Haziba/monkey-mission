extends GameScreen

## THE HALL OF FAME — retired parents, with their final stats, their ceilings,
## their generation and their record.
##
## This screen only exists because of a rule change. Dossier §8 [C]: in the
## original "the parent is permanently destroyed. It vanishes and is replaced by
## a baby. You cannot go back to it." Japanese sources frame it as 引退
## (retirement) and the game shows a huge RETIRE title card
## (`docs/reference/screens-hg101/retire.png`). This build ships
## `GameRules.breeding_destroys_parent = false`, so the parent retires to a
## roster you can still look at. The screen leans into that: it is a wall of
## honours, not an inventory list.
##
## Layering: reads `GameState.roster()` and `GameState.monkey()`. Mutates
## nothing, computes nothing.

@onready var _bg: ColorRect = $Bg
@onready var _title: Label = $Margin/Root/Header/HeaderMargin/HeaderBox/Title
@onready var _subtitle: Label = $Margin/Root/Header/HeaderMargin/HeaderBox/Subtitle
@onready var _header: PanelContainer = $Margin/Root/Header
@onready var _list: VBoxContainer = $Margin/Root/Scroll/List
@onready var _footer_label: Label = $Margin/Root/Footer/FooterMargin/FooterLabel
@onready var _footer: PanelContainer = $Margin/Root/Footer
@onready var _back: Button = $Margin/Root/BackButton


## Horizontal fill bar showing a retired monkey's final stat against the ceiling
## it died with. Placeholder shapes: two draw_rect calls and a notch.
class CapBar extends Control:
	var value: int = 0
	var cap: int = 0
	var fill: Color = Palette.ACCENT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 28)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var track := Rect2(Vector2.ZERO, size)
		draw_rect(track, Palette.PANEL_DARK)
		var ratio := 0.0
		if cap > 0:
			ratio = clampf(float(value) / float(cap), 0.0, 1.0)
		if ratio > 0.0:
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), fill)
		# The ceiling notch — the star in `POW 500*` made visible.
		draw_rect(Rect2(Vector2(size.x - 6.0, 0.0), Vector2(6.0, size.y)), Palette.STAT_CAPPED)
		draw_rect(track, Palette.INK, false, 3.0)


func _ready() -> void:
	super()
	_bg.color = Palette.BG
	_header.add_theme_stylebox_override("panel", _box(Palette.PANEL_DARK))
	_footer.add_theme_stylebox_override("panel", _box(Palette.PANEL))
	_title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_title.add_theme_color_override("font_color", Palette.SELECTION)
	_subtitle.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_subtitle.add_theme_color_override("font_color", Palette.INK_LIGHT)
	if not _back.pressed.is_connected(_on_back):
		_back.pressed.connect(_on_back)
	if not GameState.monkey_retired.is_connected(_on_monkey_retired):
		GameState.monkey_retired.connect(_on_monkey_retired)
	_refresh()


func on_enter(params: Dictionary) -> void:
	super(params)
	_refresh()


func _on_monkey_retired(_monkey: Monkey) -> void:
	_refresh()


# --- content ---------------------------------------------------------------

func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var roster := GameState.roster()
	_title.text = "HALL OF FAME"
	if roster.is_empty():
		_subtitle.text = "NO ONE HAS RETIRED YET."
		_list.add_child(_empty_card())
	else:
		_subtitle.text = "%d RETIRED %s" % [
			roster.size(), "MONKEY" if roster.size() == 1 else "MONKEYS",
		]
		# Newest retirement first: the most recent parent is the one the player
		# just said goodbye to.
		for i in range(roster.size() - 1, -1, -1):
			_list.add_child(_build_card(roster[i] as Monkey, i + 1))

	var active := GameState.monkey()
	if active == null:
		_footer_label.text = "NO MONKEY IN TRAINING."
	else:
		_footer_label.text = "IN TRAINING:  %s  ·  GEN %d  ·  %d W - %d L" % [
			active.monkey_name.to_upper(), active.generation, active.wins, active.losses,
		]


func _empty_card() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Palette.PANEL))
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 20)
	margin.add_child(box)

	var big := Label.new()
	big.text = "RETIRE"
	big.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	big.add_theme_color_override("font_color", Palette.DISABLED)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(big)

	var body := Label.new()
	# The rule change, stated plainly, because that is the whole reason this
	# screen exists (dossier §8 [C] vs GameRules.breeding_destroys_parent).
	body.text = (
		"Breed your monkey and its parent comes here instead of vanishing.\n\n"
		+ "In the original, pairing destroyed the parent for good. This build "
		+ "retires it: it will never fight again, but its record and the "
		+ "ceilings it passed on stay on the wall."
	)
	body.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	body.add_theme_color_override("font_color", Palette.INK_LIGHT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(body)
	return panel


func _build_card(monkey: Monkey, ordinal: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(Palette.PANEL))

	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)

	column.add_child(_card_head(monkey, ordinal))

	var rule := HSeparator.new()
	column.add_child(rule)

	column.add_child(_stat_grid(monkey))

	var starred := 0
	for stat in Monkey.STATS:
		if monkey.is_capped(stat):
			starred += 1
	var footnote := Label.new()
	footnote.text = "%d of %d ceilings reached  ·  bar shows final stat against its cap" % [
		starred, Monkey.STATS.size(),
	]
	footnote.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	footnote.add_theme_color_override("font_color", Palette.DISABLED)
	footnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(footnote)
	return panel


func _card_head(monkey: Monkey, ordinal: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Palette.GUTTER)

	# Placeholder portrait: a flat fill in the monkey's type colour with an
	# accent bar. Dossier §8 [C] — type is load-bearing, so it is worth showing.
	var portrait := Panel.new()
	portrait.custom_minimum_size = Vector2(150, 150)
	portrait.add_theme_stylebox_override("panel", _box(Palette.monkey_color(monkey.species_type)))
	var accent := ColorRect.new()
	accent.color = Palette.monkey_accent(monkey.species_type)
	accent.anchor_left = 0.18
	accent.anchor_top = 0.55
	accent.anchor_right = 0.82
	accent.anchor_bottom = 0.80
	portrait.add_child(accent)
	row.add_child(portrait)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 8)
	row.add_child(text)

	var name_label := Label.new()
	# The original's stat card prints `NAME: MAX(ML)` (dossier §10 [C]).
	name_label.text = monkey.name_line()
	name_label.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	name_label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	text.add_child(name_label)

	var meta := Label.new()
	meta.text = "GEN %d  ·  %s" % [monkey.generation, monkey.species().display_name.to_upper()]
	meta.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	meta.add_theme_color_override("font_color", Palette.ACCENT_ALT)
	text.add_child(meta)

	var record := Label.new()
	record.text = "RECORD  %d W - %d L" % [monkey.wins, monkey.losses]
	record.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	record.add_theme_color_override("font_color",
		Palette.GOOD if monkey.wins >= monkey.losses else Palette.BAD)
	text.add_child(record)

	var badge := VBoxContainer.new()
	badge.alignment = BoxContainer.ALIGNMENT_CENTER
	var badge_label := Label.new()
	badge_label.text = "#%d" % ordinal
	badge_label.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	badge_label.add_theme_color_override("font_color", Palette.SELECTION)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_child(badge_label)
	var badge_note := Label.new()
	badge_note.text = "RETIRED"
	badge_note.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	badge_note.add_theme_color_override("font_color", Palette.DISABLED)
	badge_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.add_child(badge_note)
	row.add_child(badge)
	return row


func _stat_grid(monkey: Monkey) -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Palette.GUTTER)
	grid.add_theme_constant_override("v_separation", 14)

	for stat in Monkey.STATS:
		var label := Label.new()
		label.text = Monkey.stat_label(stat)
		label.custom_minimum_size = Vector2(120, 0)
		label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
		label.add_theme_color_override("font_color", Palette.stat_color(stat))
		grid.add_child(label)

		var value := Label.new()
		# `stat_line` already prints the original's star for a capped stat.
		value.text = "%d%s" % [monkey.get_stat(stat), "*" if monkey.is_capped(stat) else ""]
		value.custom_minimum_size = Vector2(150, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", Palette.FONT_BODY)
		value.add_theme_color_override("font_color",
			Palette.STAT_CAPPED if monkey.is_capped(stat) else Palette.INK_LIGHT)
		grid.add_child(value)

		var bar := CapBar.new()
		bar.value = monkey.get_stat(stat)
		bar.cap = monkey.get_cap(stat)
		bar.fill = Palette.stat_color(stat)
		grid.add_child(bar)

		var cap := Label.new()
		cap.text = "/ %d" % monkey.get_cap(stat)
		cap.custom_minimum_size = Vector2(150, 0)
		cap.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		cap.add_theme_color_override("font_color", Palette.DISABLED)
		grid.add_child(cap)
	return grid


func _on_back() -> void:
	Sfx.cancel()
	close()


static func _box(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Palette.INK
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	return style
