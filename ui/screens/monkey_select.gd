extends GameScreen

## "CHOOSE YOUR MONKEY" — the five types, their food preferences, their stat
## tendency and the caps the starter will be born with.
##
## Layout follows the original's monkey-shop screen
## (docs/reference/screens-hg101/monkey-shop.png): the box at the bottom of that
## shot literally reads "CHOOSE YOUR MONKEY", so the string is kept. Placeholder
## art only — each type is a flat body-colour swatch with an accent bar under it.
##
## DIVERGENCE: the original does not have this screen. Fred hands over one fixed
## monkey, Freddy, of a fixed type (dossier §7 phase 0 [C]); the monkey SHOP,
## where you do pick from a pen, is a mid-game feature. The brief adds the choice
## up front, so the intro frames it as picking from Fred's litter. Freddy's name
## stays fixed, which §8 [C] confirms.
##
## Everything shown here is read from core: `SpeciesDb` for the five types,
## `FoodDb` for the food display names, `RunState.starter_caps()` for Freddy's
## observed cap tuple. This screen computes no rule of its own.

@onready var _bg: ColorRect = $Bg
@onready var _header: PanelContainer = $Margin/Box/Header
@onready var _caps_panel: PanelContainer = $Margin/Box/Caps
@onready var _title: Label = $Margin/Box/Header/Margin/Title
@onready var _sub: Label = $Margin/Box/Sub
@onready var _rows: VBoxContainer = $Margin/Box/List/Rows
@onready var _caps_title: Label = $Margin/Box/Caps/Margin/Body/CapsTitle
@onready var _caps_rows: VBoxContainer = $Margin/Box/Caps/Margin/Body/CapsRows
@onready var _caps_note: Label = $Margin/Box/Caps/Margin/Body/CapsNote
@onready var _confirm: Button = $Margin/Box/Confirm

## Array[Species], in SpeciesDb order.
var _species_list: Array = []
## Index into `_species_list`, or -1.
var _selected: int = -1
var _cards: Array[Button] = []


func _ready() -> void:
	super()
	_bg.color = Palette.BG
	_title.text = "CHOOSE YOUR MONKEY"
	_title.add_theme_color_override("font_color", Palette.INK)
	_title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)

	_sub.text = "Fred brought the whole litter. Take one. He answers to Freddy either way."
	_sub.add_theme_color_override("font_color", Palette.PAPER_EDGE)
	_sub.add_theme_font_size_override("font_size", Palette.FONT_SMALL)

	_caps_title.add_theme_color_override("font_color", Palette.INK)
	_caps_title.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	# Dossier §3 [C]: caps hard-block training and only breeding raises them.
	# GameRules.hard_stat_caps is true in this build, so say so before the player
	# commits to a type.
	_caps_note.text = "Caps are hard. Training stops at the star; only breeding raises them."
	_caps_note.add_theme_color_override("font_color", Palette.INK)
	_caps_note.add_theme_font_size_override("font_size", Palette.FONT_SMALL)

	_confirm.text = "TAKE HIM HOME"
	_confirm.disabled = true
	_confirm.custom_minimum_size = Vector2(0, Palette.TOUCH_MIN)
	_confirm.pressed.connect(_on_confirm_pressed)

	_header.add_theme_stylebox_override("panel", _box_style(Palette.PAPER))
	_caps_panel.add_theme_stylebox_override("panel", _box_style(Palette.PAPER))

	_species_list = SpeciesDb.all()
	_build_cards()
	_select(0)


func on_enter(params: Dictionary) -> void:
	super(params)


# --- the list --------------------------------------------------------------

func _build_cards() -> void:
	for child in _rows.get_children():
		child.queue_free()
	_cards.clear()
	for index in _species_list.size():
		var card := _make_card(_species_list[index])
		card.pressed.connect(_on_card_pressed.bind(index))
		_rows.add_child(card)
		_cards.append(card)


func _make_card(species: Species) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(0, 300)
	card.focus_mode = Control.FOCUS_NONE

	var body := MarginContainer.new()
	body.set_anchors_preset(Control.PRESET_FULL_RECT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("margin_left", 28)
	body.add_theme_constant_override("margin_top", 24)
	body.add_theme_constant_override("margin_right", 28)
	body.add_theme_constant_override("margin_bottom", 24)
	card.add_child(body)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 28)
	body.add_child(row)

	# Placeholder "portrait": body colour over an accent bar. No sprites.
	var swatch := VBoxContainer.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_theme_constant_override("separation", 0)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.color = Palette.monkey_color(species.type)
	fill.custom_minimum_size = Vector2(180, 150)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_child(fill)
	var accent := ColorRect.new()
	accent.color = Palette.monkey_accent(species.type)
	accent.custom_minimum_size = Vector2(180, 40)
	accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.add_child(accent)
	row.add_child(swatch)

	var text := VBoxContainer.new()
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_constant_override("separation", 10)
	row.add_child(text)

	var heading := HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text.add_child(heading)
	heading.add_child(_line(species.display_name.to_upper(), Palette.FONT_BODY, Palette.INK, true))
	# Species.tendency_label() reads the invented cap_bias table — the dossier
	# never gives per-type tendencies (§14.4 [X]).
	var tendency := _line(species.tendency_label(), Palette.FONT_SMALL, Palette.INK)
	tendency.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tendency.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(tendency)

	text.add_child(_line("LIKES: %s" % _food_names(species.liked_foods),
		Palette.FONT_SMALL, Palette.INK))
	text.add_child(_line("DISLIKES: %s" % _food_names(species.disliked_foods),
		Palette.FONT_SMALL, Palette.BAD))
	return card


func _line(text: String, size: int, colour: Color, expand := false) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## Food ids -> the display names in core/data/food_db.gd.
func _food_names(ids: PackedStringArray) -> String:
	if ids.is_empty():
		return "nothing in particular"
	var names: PackedStringArray = PackedStringArray()
	for id in ids:
		var food := FoodDb.get_food(id)
		names.append(food.display_name if food != null else id)
	return ", ".join(names)


# --- selection -------------------------------------------------------------

func _on_card_pressed(index: int) -> void:
	Sfx.click()
	_select(index)


func _select(index: int) -> void:
	if index < 0 or index >= _species_list.size():
		return
	_selected = index
	for i in _cards.size():
		var style := _box_style(Palette.SELECTION if i == index else Palette.PAPER)
		_cards[i].add_theme_stylebox_override("normal", style)
		_cards[i].add_theme_stylebox_override("hover", style)
		_cards[i].add_theme_stylebox_override("pressed", _box_style(Palette.ACCENT))
	_confirm.disabled = false
	_refresh_caps()


## Freddy's cap tuple for the chosen type. `RunState.starter_caps()` is the
## observed Pow 145 / Spd 119 / Know 116 / Str 145 / Stm 145 (dossier §3 [U],
## from three players' byte-identical RetroAchievements rich presence);
## `Species.cap_bias` is documented in core as "multiplier applied to each
## starting cap", so the projection shown here applies it.
func _refresh_caps() -> void:
	for child in _caps_rows.get_children():
		child.queue_free()
	if _selected < 0:
		return
	var species: Species = _species_list[_selected]
	_caps_title.text = "FREDDY  ·  %s  ·  STARTER CAPS" % species.display_name.to_upper()
	var base := RunState.starter_caps()
	# The tuple core will actually build, not a projection of it — see
	# RunState.starter_caps_for().
	var shaped := RunState.starter_caps_for(species.type)
	for stat in Monkey.STATS:
		var base_value := int(base.get(stat, 0))
		var bias := species.cap_bias_for(stat)
		var value := int(shaped.get(stat, base_value))
		var arrow := "—"
		if bias > 1.0001:
			arrow = "▲"
		elif bias < 0.9999:
			arrow = "▼"
		var text := "%-5s %4d  %s" % [Monkey.stat_label(stat), value, arrow]
		if value != base_value:
			text += "   (base %d)" % base_value
		_caps_rows.add_child(_line(text, Palette.FONT_BODY, Palette.stat_color(stat)))


static func _box_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = Palette.INK
	sb.set_border_width_all(Palette.BORDER_WIDTH)
	sb.set_corner_radius_all(Palette.CORNER_RADIUS)
	return sb


# --- hand-off --------------------------------------------------------------

func _on_confirm_pressed() -> void:
	if _selected < 0:
		return
	Sfx.confirm()
	var protagonist: int = int(enter_params.get("protagonist", RunState.Protagonist.KENTA))
	if not GameState.has_run():
		GameState.new_run(protagonist)
	_hand_species_to_core()
	# Dossier §5 [C]: "Befriending gates everything" — every new monkey, Freddy
	# included, must be won over with food before it will train. Leaving the
	# phase on INTRO would also send the title screen's CONTINUE back here.
	GameState.set_phase(RunState.Phase.BEFRIEND)
	# Not saved here — see title_screen. Picking a monkey is not yet a run worth
	# overwriting the previous one for.
	Router.reset_to(Router.Screen.HOME)


## RESOLVED. This was written against a gap: `GameState.new_run(protagonist,
## seed)` takes no species (docs/ARCHITECTURE.md §16) and a screen is forbidden
## from mutating a Monkey, so the choice had nowhere to go and was silently
## dropped onto a run flag. The Integration agent added
## `GameState.set_starter_species(int)`, which rebuilds the untouched starter in
## core, so the first branch below is now the live one. The fallback is kept as
## a safety net rather than deleted — it costs nothing and it is what makes this
## screen survive being loaded against an older core.
func _hand_species_to_core() -> void:
	if _selected < 0:
		return
	var type := int((_species_list[_selected] as Species).type)
	if GameState.has_method("set_starter_species"):
		GameState.call("set_starter_species", type)
		return
	if GameState.run != null:
		# `RunState.set_flag` is typed bool; the flags Dictionary itself is the
		# documented place for "flags the UI checks", so the type goes in raw.
		GameState.run.flags["starter_species"] = type
	push_warning(
		"monkey_select: GameState has no set_starter_species(int); "
		+ "the chosen type is recorded on the run flag \"starter_species\" only.")
