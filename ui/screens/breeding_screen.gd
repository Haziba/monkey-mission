extends GameScreen

## THE DATING SHOP — breeding, the game's signature system (dossier §8).
##
## Called "dating" in English, お見合い / 配合 in Japanese, and advertised on the
## box [C]. The original's partner menu offers six archetypes in the same
## two-column layout it uses everywhere else (`AVG / POWER / SPEED / SMART /
## STRONG / STM TYPE`, §8 [C]; column layout per
## `docs/reference/screens-hg101/menu-2.png`), and previews each pairing as
## per-stat directional arrows **which can point down** [C].
##
## What is inherited is the CEILING, not the current stats [C]. The baby starts
## near zero, has to be re-befriended with food, and shops badly because its
## Knowledge is low [C]. Caps can regress per-stat [C]. The confirmation box
## says all of that in plain words before any money changes hands.
##
## RULE CHANGE: `GameRules.breeding_destroys_parent = false`. The original
## destroys the parent outright; here it retires to the roster. The confirm text
## reads the flag rather than assuming either behaviour.
##
## Layering: every number on this screen comes from `GameState` —
## `breeding_partners()`, `preview_partner()`, `breed_with()`. The screen never
## computes an inherited cap, a fee or an arrow.

@onready var _bg: ColorRect = $Bg
@onready var _day_label: Label = $Margin/Root/HeaderRow/DayBox/DayMargin/DayLabel
@onready var _money_label: Label = $Margin/Root/HeaderRow/MoneyBox/MoneyMargin/MoneyLabel
@onready var _title: Label = $Margin/Root/Title
@onready var _advice_panel: PanelContainer = $Margin/Root/AdvicePanel
@onready var _advice: Label = $Margin/Root/AdvicePanel/AdviceMargin/AdviceLabel
@onready var _menu_panel: PanelContainer = $Margin/Root/MenuPanel
@onready var _left_column: VBoxContainer = $Margin/Root/MenuPanel/MenuMargin/Columns/LeftColumn
@onready var _right_column: VBoxContainer = $Margin/Root/MenuPanel/MenuMargin/Columns/RightColumn
@onready var _preview_box: VBoxContainer = $Margin/Root/PreviewScroll/PreviewBox
@onready var _back: Button = $Margin/Root/Actions/BackButton
@onready var _roster_button: Button = $Margin/Root/Actions/RosterButton
@onready var _confirm: Button = $Margin/Root/Actions/ConfirmButton

@onready var _confirm_overlay: Control = $ConfirmOverlay
@onready var _confirm_dim: ColorRect = $ConfirmOverlay/Dim
@onready var _confirm_panel: PanelContainer = $ConfirmOverlay/Centre/ConfirmPanel
@onready var _confirm_title: Label = $ConfirmOverlay/Centre/ConfirmPanel/ConfirmMargin/ConfirmBox/ConfirmTitle
@onready var _confirm_body: Label = $ConfirmOverlay/Centre/ConfirmPanel/ConfirmMargin/ConfirmBox/ConfirmBody
@onready var _confirm_warning: Label = $ConfirmOverlay/Centre/ConfirmPanel/ConfirmMargin/ConfirmBox/ConfirmWarning
@onready var _name_edit: LineEdit = $ConfirmOverlay/Centre/ConfirmPanel/ConfirmMargin/ConfirmBox/NameEdit
@onready var _cancel_button: Button = $ConfirmOverlay/Centre/ConfirmPanel/ConfirmMargin/ConfirmBox/ConfirmButtons/CancelButton
@onready var _pair_button: Button = $ConfirmOverlay/Centre/ConfirmPanel/ConfirmMargin/ConfirmBox/ConfirmButtons/PairButton

@onready var _reveal_overlay: Control = $RevealOverlay
@onready var _reveal_bg: ColorRect = $RevealOverlay/RevealBg
@onready var _reveal_stage: Control = $RevealOverlay/RevealStage
@onready var _born_label: Label = $RevealOverlay/RevealMargin/RevealBox/BornLabel
@onready var _gen_label: Label = $RevealOverlay/RevealMargin/RevealBox/GenLabel
@onready var _cap_header: Label = $RevealOverlay/RevealMargin/RevealBox/CapHeader
@onready var _cap_list: VBoxContainer = $RevealOverlay/RevealMargin/RevealBox/CapList
@onready var _fate_label: Label = $RevealOverlay/RevealMargin/RevealBox/FateLabel
@onready var _reveal_buttons: HBoxContainer = $RevealOverlay/RevealMargin/RevealBox/RevealButtons
@onready var _reveal_roster: Button = $RevealOverlay/RevealMargin/RevealBox/RevealButtons/RevealRosterButton
@onready var _reveal_continue: Button = $RevealOverlay/RevealMargin/RevealBox/RevealButtons/ContinueButton

## Beat length between one revealed ceiling and the next. Long enough to read.
const REVEAL_BEAT := 0.42

var _partners: Array = []
var _buttons: Array[Button] = []
var _selected: int = -1
var _preview: Breeding.Preview = null
var _skip_reveal: bool = false
var _revealing: bool = false
var _reveal_portrait: Panel = null


## One directional arrow from the partner preview. Dossier §8 [C]: the original
## previews stat tendencies as arrows and they CAN POINT DOWN — that is the
## whole tension of the system, so a down arrow is drawn as loudly as an up one.
class ArrowMark extends Control:
	var direction: int = Breeding.Arrow.FLAT

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(72, 60)

	func _draw() -> void:
		var w := size.x
		var h := size.y
		match direction:
			Breeding.Arrow.UP:
				draw_rect(Rect2(Vector2(w * 0.36, h * 0.52), Vector2(w * 0.28, h * 0.36)), Palette.GOOD)
				draw_colored_polygon(PackedVector2Array([
					Vector2(w * 0.5, h * 0.10),
					Vector2(w * 0.90, h * 0.58),
					Vector2(w * 0.10, h * 0.58),
				]), Palette.GOOD)
			Breeding.Arrow.DOWN:
				draw_rect(Rect2(Vector2(w * 0.36, h * 0.12), Vector2(w * 0.28, h * 0.36)), Palette.BAD)
				draw_colored_polygon(PackedVector2Array([
					Vector2(w * 0.5, h * 0.90),
					Vector2(w * 0.90, h * 0.42),
					Vector2(w * 0.10, h * 0.42),
				]), Palette.BAD)
			_:
				draw_rect(Rect2(Vector2(w * 0.14, h * 0.44), Vector2(w * 0.72, h * 0.12)), Palette.DISABLED)


## Radiating wedge fan behind the birth portrait. Dossier §10 [C] and
## `docs/reference/screens-hg101/new-monkey-2.png`: the original stages "TOMATO
## WAS BORN." on the same sunburst card it uses to close a day. Deliberately a
## twin of the one in `day_end.gd` rather than a shared node — the two screens
## are owned separately and neither should be able to break the other's parse.
class Sunburst extends Control:
	var ray_color: Color = Palette.SELECTION
	var back_color: Color = Palette.ACCENT
	var rays: int = 13
	var spin: float = 0.0
	var spin_speed: float = 0.16

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


func _ready() -> void:
	super()
	_bg.color = Palette.BG
	_title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_title.add_theme_color_override("font_color", Palette.SELECTION)
	_advice_panel.add_theme_stylebox_override("panel", _box(Palette.PANEL_DARK))
	_menu_panel.add_theme_stylebox_override("panel", _box(Palette.PANEL_DARK))
	_confirm_panel.add_theme_stylebox_override("panel", _box(Palette.PAPER))
	_confirm_dim.color = Color(Palette.BG.r, Palette.BG.g, Palette.BG.b, 0.86)
	_confirm_title.add_theme_color_override("font_color", Palette.INK)
	_confirm_title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_confirm_body.add_theme_color_override("font_color", Palette.INK)
	_confirm_warning.add_theme_color_override("font_color", Palette.BAD)
	_reveal_bg.color = Palette.BG
	_born_label.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_born_label.add_theme_color_override("font_color", Palette.INK)
	_gen_label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_gen_label.add_theme_color_override("font_color", Palette.INK)
	_cap_header.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_cap_header.add_theme_color_override("font_color", Palette.SELECTION)
	_fate_label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_fate_label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)

	_confirm_overlay.visible = false
	_reveal_overlay.visible = false
	_build_reveal_stage()

	_back.pressed.connect(_on_back)
	_roster_button.pressed.connect(_open_roster)
	_confirm.pressed.connect(_open_confirm)
	_cancel_button.pressed.connect(_close_confirm)
	_pair_button.pressed.connect(_on_pair)
	_reveal_roster.pressed.connect(_open_roster)
	_reveal_continue.pressed.connect(_on_reveal_done)
	_reveal_overlay.gui_input.connect(_on_reveal_input)

	if not GameState.money_changed.is_connected(_on_money_changed):
		GameState.money_changed.connect(_on_money_changed)

	_refresh()


func on_enter(params: Dictionary) -> void:
	super(params)
	_refresh()


func on_result(_result: Dictionary) -> void:
	# Coming back from the roster: the shop has not changed, but money might
	# have been spent elsewhere on the way.
	_update_actions()


# --- the shop --------------------------------------------------------------

func _refresh() -> void:
	if _preview_box == null:
		return
	_day_label.text = "DAYS %d" % GameState.day()
	_money_label.text = _yen(GameState.money())
	_title.text = "DATING SHOP"

	var monkey := GameState.monkey()
	_partners = GameState.breeding_partners()
	_advice.text = _advice_text(monkey)
	_build_menu()
	if _selected >= _partners.size():
		_selected = -1
	_show_preview()
	_update_actions()


## Presentational only. Core owns the real wording in `Breeding.breed_advice()`,
## but the GameState facade does not expose it (flagged in the hand-off notes);
## counting stars is a plain read of the monkey, not a rule decision.
##
## Dossier §8 records two credible schools — "max everything first" (both FAQ
## authors and the achievement-set author) and "breed at the first star" — and
## does not settle between them, so the advice reports both instead of picking.
func _advice_text(monkey: Monkey) -> String:
	if monkey == null:
		return "There is no monkey to pair."
	var starred := 0
	for stat in Monkey.STATS:
		if monkey.is_capped(stat):
			starred += 1
	if starred == Monkey.STATS.size():
		return "Every stat is starred. %s has nothing left to learn — pass the ceiling on." % [
			monkey.monkey_name.to_upper(),
		]
	if starred == 0:
		return "No stat is starred yet. %s still has room to train; pairing now throws away a ceiling you have not used." % [
			monkey.monkey_name.to_upper(),
		]
	return "%d of %d stats starred. Some trainers pair at the first star; the FAQ authors wait for all five." % [
		starred, Monkey.STATS.size(),
	]


## The original's two-column menu (menu-2.png) fills DOWN the left column first,
## then down the right — not row by row. Reproduced here.
func _build_menu() -> void:
	for column in [_left_column, _right_column]:
		for child in column.get_children():
			column.remove_child(child)
			child.queue_free()
	_buttons.clear()

	if _partners.is_empty():
		var empty := Label.new()
		empty.text = "The dating shop is closed."
		empty.add_theme_color_override("font_color", Palette.DISABLED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_left_column.add_child(empty)
		return

	var rows := int(ceil(float(_partners.size()) * 0.5))
	for i in _partners.size():
		var partner: Breeding.Partner = _partners[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, Palette.TOUCH_MIN)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.text = _button_text(partner, false)
		button.pressed.connect(_on_partner_pressed.bind(i))
		var column: VBoxContainer = _left_column if i < rows else _right_column
		column.add_child(button)
		_buttons.append(button)


func _button_text(partner: Breeding.Partner, selected: bool) -> String:
	# ">" stands in for the original's selection triangle; the default font has
	# no guaranteed glyph for one and placeholder art means no image cursor.
	return "%s %s\n%s  %s" % [
		">" if selected else " ",
		Breeding.archetype_label(partner.archetype),
		partner.display_name.to_upper(),
		_yen(partner.fee),
	]


func _on_partner_pressed(index: int) -> void:
	Sfx.click()
	_selected = index
	_show_preview()
	_update_actions()


func _show_preview() -> void:
	for child in _preview_box.get_children():
		_preview_box.remove_child(child)
		child.queue_free()

	for i in mini(_buttons.size(), _partners.size()):
		var partner: Breeding.Partner = _partners[i]
		_buttons[i].set_pressed_no_signal(i == _selected)
		_buttons[i].text = _button_text(partner, i == _selected)

	if _selected < 0 or _selected >= _partners.size():
		_preview = null
		var hint := Label.new()
		hint.text = "Choose a partner to see how the ceilings would move."
		hint.add_theme_color_override("font_color", Palette.DISABLED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preview_box.add_child(hint)
		return

	var chosen: Breeding.Partner = _partners[_selected]
	_preview = GameState.preview_partner(_selected)
	_preview_box.add_child(_partner_head(chosen))

	var monkey := GameState.monkey()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", Palette.GUTTER)
	grid.add_theme_constant_override("v_separation", 12)
	_preview_box.add_child(grid)

	for stat in Monkey.STATS:
		var label := Label.new()
		label.text = Monkey.stat_label(stat)
		label.custom_minimum_size = Vector2(140, 0)
		label.add_theme_color_override("font_color", Palette.stat_color(stat))
		grid.add_child(label)

		var current := Label.new()
		current.text = "CAP %d" % (monkey.get_cap(stat) if monkey != null else 0)
		current.custom_minimum_size = Vector2(200, 0)
		current.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		current.add_theme_color_override("font_color", Palette.INK_LIGHT)
		grid.add_child(current)

		var arrow := ArrowMark.new()
		arrow.direction = int(_preview.arrows.get(stat, Breeding.Arrow.FLAT)) if _preview != null else Breeding.Arrow.FLAT
		grid.add_child(arrow)

		var word := Label.new()
		word.text = _arrow_word(arrow.direction)
		word.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		word.add_theme_color_override("font_color", _arrow_color(arrow.direction))
		word.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(word)

	var caveat := Label.new()
	# The preview shows the EXPECTED ceiling; the roll lands either side of it.
	# Saying so is honest and keeps the birth reveal a genuine reveal.
	caveat.text = "Arrows show the tendency, not a promise — the roll lands either side of it. Ceilings can go down."
	caveat.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	caveat.add_theme_color_override("font_color", Palette.DISABLED)
	caveat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_box.add_child(caveat)

	if _preview != null and not _preview.warning.is_empty():
		var warn := Label.new()
		warn.text = _preview.warning
		warn.add_theme_color_override("font_color", Palette.BAD)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_preview_box.add_child(warn)


func _partner_head(partner: Breeding.Partner) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Palette.GUTTER)

	var portrait := Panel.new()
	portrait.custom_minimum_size = Vector2(132, 132)
	portrait.add_theme_stylebox_override("panel", _box(Palette.monkey_color(partner.species_type)))
	row.add_child(portrait)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)

	var name_label := Label.new()
	name_label.text = "%s(%s)" % [
		partner.display_name.to_upper(),
		Monkey.SEX_MARKERS[clampi(int(partner.sex), 0, Monkey.SEX_MARKERS.size() - 1)],
	]
	name_label.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	text.add_child(name_label)

	var meta := Label.new()
	meta.text = "%s  ·  %s  ·  FEE %s" % [
		Breeding.archetype_label(partner.archetype),
		SpeciesDb.get_species(partner.species_type).display_name.to_upper(),
		_yen(partner.fee),
	]
	meta.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	meta.add_theme_color_override("font_color", Palette.ACCENT_ALT)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(meta)
	return row


func _update_actions() -> void:
	if _confirm == null:
		return
	_money_label.text = _yen(GameState.money())
	var monkey := GameState.monkey()
	if monkey == null or _selected < 0 or _selected >= _partners.size():
		_confirm.disabled = true
		_confirm.text = "CHOOSE A PARTNER"
		return
	var partner: Breeding.Partner = _partners[_selected]
	if GameState.money() < partner.fee:
		_confirm.disabled = true
		_confirm.text = "NOT ENOUGH MONEY"
		return
	_confirm.disabled = false
	_confirm.text = "PAIR THEM  %s" % _yen(partner.fee)


func _on_money_changed(_amount: int) -> void:
	_update_actions()


# --- confirmation ----------------------------------------------------------

## The confirm box has to say plainly what is about to happen. Two of the three
## consequences are the ones players of the original found out the hard way.
func _open_confirm() -> void:
	var monkey := GameState.monkey()
	if monkey == null or _selected < 0 or _selected >= _partners.size():
		return
	Sfx.confirm()
	var partner: Breeding.Partner = _partners[_selected]
	var destroys := GameState.rules().breeding_destroys_parent

	_confirm_title.text = "PAIR %s WITH %s?" % [
		monkey.monkey_name.to_upper(), partner.display_name.to_upper(),
	]
	var fate := ""
	if destroys:
		fate = "%s IS GONE FOR GOOD. It will not come back, and you cannot look at it again." % [
			monkey.monkey_name.to_upper(),
		]
	else:
		fate = "%s RETIRES TO THE ROSTER. It will never fight again, but its record stays on the wall." % [
			monkey.monkey_name.to_upper(),
		]
	_confirm_body.text = (
		"%s\n\n"
		+ "THE BABY STARTS FROM ZERO. Every stat, and its friendship too — it "
		+ "will bite you until you win it over with food, and it shops badly "
		+ "until its Knowledge comes up.\n\n"
		+ "WHAT IT INHERITS IS THE CEILING, NOT THE STATS. Some ceilings go up, "
		+ "some go down. It re-enters the ladder at the bottom.\n\n"
		+ "FEE: %s"
	) % [fate, _yen(partner.fee)]

	if _preview != null and not _preview.warning.is_empty():
		_confirm_warning.text = _preview.warning
		_confirm_warning.visible = true
	else:
		_confirm_warning.text = ""
		_confirm_warning.visible = false

	_name_edit.text = ""
	_pair_button.text = "PAIR THEM"
	_confirm_overlay.visible = true


func _close_confirm() -> void:
	Sfx.cancel()
	_confirm_overlay.visible = false


func _on_pair() -> void:
	if _selected < 0 or _selected >= _partners.size():
		return
	_pair_button.disabled = true
	var result := GameState.breed_with(_selected, _name_edit.text)
	_pair_button.disabled = false
	if result == null or result.baby == null:
		_confirm_warning.text = result.message if result != null else "The pairing could not go ahead."
		_confirm_warning.visible = true
		return
	_confirm_overlay.visible = false
	# The parent is spent: this shop visit is over. Tear the menu down behind
	# the reveal so nothing stale is tappable if the player detours to the
	# roster and comes back.
	_selected = -1
	_partners = []
	_build_menu()
	_show_preview()
	_update_actions()
	await _play_reveal(result)


# --- the birth reveal ------------------------------------------------------
#
# The payoff of the whole game. Dossier §8: the Japanese framing of the appeal
# is 「親が倒せなかった強敵を子供が倒す」 — the child defeats the strong enemy the
# parent could not. The original stages it as a sunburst portrait card reading
# "TOMATO WAS BORN." (docs/reference/screens-hg101/new-monkey-2.png), so that is
# the shape here, with the ceilings revealed one row at a time afterwards.

func _build_reveal_stage() -> void:
	var sun := Sunburst.new()
	sun.name = "Sunburst"
	sun.set_anchors_preset(Control.PRESET_FULL_RECT)
	sun.ray_color = Palette.SELECTION
	sun.back_color = Palette.ACCENT
	sun.spin_speed = 0.16
	_reveal_stage.add_child(sun)

	_reveal_portrait = Panel.new()
	_reveal_portrait.name = "BabyPortrait"
	_reveal_portrait.anchor_left = 0.30
	_reveal_portrait.anchor_top = 0.18
	_reveal_portrait.anchor_right = 0.70
	_reveal_portrait.anchor_bottom = 0.92
	_reveal_stage.add_child(_reveal_portrait)


func _play_reveal(result: Breeding.BreedResult) -> void:
	_revealing = true
	_skip_reveal = false
	_reveal_overlay.visible = true
	_reveal_buttons.visible = false
	_cap_header.visible = false
	_gen_label.visible = false
	_fate_label.visible = false
	for child in _cap_list.get_children():
		_cap_list.remove_child(child)
		child.queue_free()

	var baby: Monkey = result.baby
	_reveal_portrait.add_theme_stylebox_override("panel", _box(Palette.monkey_color(baby.species_type)))
	_born_label.text = "%s WAS BORN." % baby.monkey_name.to_upper()

	await _beat(0.7)
	if not is_inside_tree():
		return
	_gen_label.text = "GENERATION %d  ·  %s  ·  %s" % [
		baby.generation,
		baby.species().display_name.to_upper(),
		baby.sex_marker(),
	]
	_gen_label.visible = true

	await _beat(0.5)
	if not is_inside_tree():
		return
	_cap_header.text = "CEILINGS INHERITED  (PARENT -> %s)" % baby.monkey_name.to_upper()
	_cap_header.visible = true

	for stat in Monkey.STATS:
		await _beat(REVEAL_BEAT)
		if not is_inside_tree():
			return
		_cap_list.add_child(_cap_row(stat, result))

	await _beat(0.5)
	if not is_inside_tree():
		return
	# `result.message` is core's own narration of the step — parent's fate,
	# ceilings up and down, and what the baby has to do next.
	_fate_label.text = result.message
	_fate_label.visible = true
	_reveal_buttons.visible = true
	_reveal_roster.visible = result.parent_retired and not result.parent_destroyed
	_revealing = false


func _cap_row(stat: int, result: Breeding.BreedResult) -> Control:
	var pair: Array = result.cap_changes.get(stat, [0, 0])
	var old_cap := int(pair[0])
	var new_cap := int(pair[1])
	var delta := new_cap - old_cap

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Palette.GUTTER)

	var label := Label.new()
	label.text = Monkey.stat_label(stat)
	label.custom_minimum_size = Vector2(140, 0)
	label.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	label.add_theme_color_override("font_color", Palette.stat_color(stat))
	row.add_child(label)

	var numbers := Label.new()
	numbers.text = "%d  ->  %d" % [old_cap, new_cap]
	numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	numbers.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	numbers.add_theme_color_override("font_color", Palette.INK_LIGHT)
	row.add_child(numbers)

	var arrow := ArrowMark.new()
	if delta > 0:
		arrow.direction = Breeding.Arrow.UP
	elif delta < 0:
		arrow.direction = Breeding.Arrow.DOWN
	else:
		arrow.direction = Breeding.Arrow.FLAT
	row.add_child(arrow)

	var change := Label.new()
	change.text = "%+d" % delta if delta != 0 else "0"
	change.custom_minimum_size = Vector2(160, 0)
	change.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	change.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	change.add_theme_color_override("font_color", _arrow_color(arrow.direction))
	row.add_child(change)
	return row


func _beat(seconds: float) -> void:
	if _skip_reveal:
		return
	if not is_inside_tree():
		return
	await get_tree().create_timer(seconds).timeout


func _on_reveal_input(event: InputEvent) -> void:
	if not _revealing:
		return
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_skip_reveal = true
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_skip_reveal = true


func _on_reveal_done() -> void:
	Sfx.confirm()
	_reveal_overlay.visible = false
	# The parent is on the wall and the baby is the active monkey; hand the
	# result back so the day loop can pick up a brand new generation.
	close({"bred": true})


# --- navigation ------------------------------------------------------------

func _open_roster() -> void:
	Sfx.click()
	Router.push(Router.Screen.ROSTER)


func _on_back() -> void:
	if _confirm_overlay.visible:
		_close_confirm()
		return
	Sfx.cancel()
	close()


# --- shapes ----------------------------------------------------------------

static func _arrow_word(direction: int) -> String:
	match direction:
		Breeding.Arrow.UP:
			return "RISING"
		Breeding.Arrow.DOWN:
			return "FALLING"
		_:
			return "STEADY"


static func _arrow_color(direction: int) -> Color:
	match direction:
		Breeding.Arrow.UP:
			return Palette.GOOD
		Breeding.Arrow.DOWN:
			return Palette.BAD
		_:
			return Palette.DISABLED


static func _box(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Palette.INK
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	return style


static func _yen(amount: int) -> String:
	var digits := str(absi(amount))
	var grouped := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		grouped = digits[i] + grouped
		count += 1
		if count % 3 == 0 and i > 0:
			grouped = "," + grouped
	return "%s¥%s" % ["-" if amount < 0 else "", grouped]
