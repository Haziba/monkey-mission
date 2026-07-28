extends GameScreen

## FEED — the larder.
##
## Dossier §2 [C]: "Feeding is free and does not consume a slot." Nothing on
## this screen ever calls `GameState.consume_slot()`, directly or indirectly;
## `GameState.feed()` is deliberately the one player action that does not cost
## a half-day.
##
## Dossier §5 [C], and the two rules the user asked to keep faithful:
##
##  * **Befriending gates everything.** Every new monkey, Freddy included, must
##    be won over with food before it will train; until then it bites. The
##    documented fastest path is two bananas, so the friendship meter is the
##    loudest thing on the screen while the monkey is still a stranger.
##  * **Hunger is two-sided and both extremes paralyse.** Underfed it is
##    immobilised by hunger; overfed it cannot move until it digests. The
##    guides' rule is to feed *only* when it cannot move, never when merely
##    peckish — so the fullness meter is drawn with the danger bands at BOTH
##    ends and a food that would tip the monkey over the edge is labelled as
##    such BEFORE it is tapped. `overfeeding_paralyses` is FAITHFUL; this
##    screen must never present it as "wastes food".
##
## There is no BUY button, and that is deliberate rather than an omission.
## Dossier §2 [C]: "Shops are menu entries, and it is the *monkey* that
## physically goes shopping, not the player." Food comes home from the SHOPPING
## activity on the home menu, which costs a half-day slot the way the original
## charges for it.
##
## LAYERING: reads `GameState` only. Every number shown — restore values, hunger
## cost, the resulting message — comes from `FoodDb` or from the `Care.FeedResult`
## that `GameState.feed()` hands back. This screen computes no rule.

## Height of the two meters.
const METER_HEIGHT := 44


## Friendship / fullness meter. Placeholder shapes: two draw_rect calls plus
## band markers. `fullness` mode paints the danger zones at BOTH ends, because
## both extremes immobilise the monkey (dossier §5 [C]).
class CareMeter extends Control:
	enum Kind { FRIENDSHIP, FULLNESS }

	var kind: Kind = Kind.FRIENDSHIP
	var value: int = 0
	var maximum: int = 100

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, METER_HEIGHT)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func set_value(new_value: int, new_maximum: int) -> void:
		value = new_value
		maximum = maxi(1, new_maximum)
		queue_redraw()

	func _draw() -> void:
		var track := Rect2(Vector2.ZERO, size)
		draw_rect(track, Palette.PANEL_DARK)

		if kind == Kind.FULLNESS:
			# Both ends are lethal to a training session, so both ends are red.
			var starve_w := size.x * float(Monkey.FULLNESS_STARVING) / float(maximum)
			draw_rect(Rect2(Vector2.ZERO, Vector2(starve_w, size.y)),
				Color(Palette.FULLNESS_DANGER, 0.35))
			var stuffed_x := size.x * float(Monkey.FULLNESS_STUFFED) / float(maximum)
			draw_rect(Rect2(Vector2(stuffed_x, 0.0), Vector2(size.x - stuffed_x, size.y)),
				Color(Palette.FULLNESS_DANGER, 0.35))
		else:
			# The line the monkey has to cross before it will train at all.
			var trust_x := size.x * float(Monkey.FRIENDSHIP_TRAIN_MIN) / float(maximum)
			draw_rect(Rect2(Vector2.ZERO, Vector2(trust_x, size.y)),
				Color(Palette.BAD, 0.30))

		var ratio := clampf(float(value) / float(maximum), 0.0, 1.0)
		if ratio > 0.0:
			var fill := Palette.FRIENDSHIP
			if kind == Kind.FULLNESS:
				fill = Palette.fullness_color(value)
			draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * ratio, size.y)), fill)

		if kind == Kind.FRIENDSHIP:
			var obedient_x := size.x * float(Monkey.FRIENDSHIP_OBEDIENT) / float(maximum)
			draw_rect(Rect2(Vector2(obedient_x - 3.0, 0.0), Vector2(6.0, size.y)),
				Palette.SELECTION)

		draw_rect(track, Palette.INK, false, 4.0)


@onready var _bg: ColorRect = $Bg
@onready var _hud: HudBoxes = $Root/Col/Hud
@onready var _title: Label = $Root/Col/Title
@onready var _state_panel: PanelContainer = $Root/Col/StatePanel
@onready var _state_label: Label = $Root/Col/StatePanel/StateText
@onready var _friend_row: HBoxContainer = $Root/Col/Meters/FriendRow
@onready var _friend_caption: Label = $Root/Col/Meters/FriendRow/Caption
@onready var _fullness_row: HBoxContainer = $Root/Col/Meters/FullnessRow
@onready var _fullness_caption: Label = $Root/Col/Meters/FullnessRow/Caption
@onready var _list: VBoxContainer = $Root/Col/Scroll/List
@onready var _message_panel: PanelContainer = $Root/Col/MessageBox
@onready var _message: Label = $Root/Col/MessageBox/Text
@onready var _back: Button = $Root/Col/Back

var _friend_meter: CareMeter = null
var _fullness_meter: CareMeter = null


func _ready() -> void:
	super()
	_bg.color = Palette.BG
	_title.text = "FEED"
	_title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_title.add_theme_color_override("font_color", Palette.SELECTION)

	for label in [_friend_caption, _fullness_caption]:
		label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)
		label.custom_minimum_size = Vector2(300, 0)

	_friend_meter = CareMeter.new()
	_friend_meter.kind = CareMeter.Kind.FRIENDSHIP
	_friend_row.add_child(_friend_meter)

	_fullness_meter = CareMeter.new()
	_fullness_meter.kind = CareMeter.Kind.FULLNESS
	_fullness_row.add_child(_fullness_meter)

	_state_panel.add_theme_stylebox_override("panel", _box(Palette.PANEL))
	_state_label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_state_label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_message_panel.add_theme_stylebox_override("panel", _box(Palette.PANEL_DARK))
	_message.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_message.add_theme_color_override("font_color", Palette.INK_LIGHT)

	_back.text = "DONE"
	_back.pressed.connect(_on_back)

	GameState.monkey_fed.connect(_on_monkey_fed)
	GameState.fullness_changed.connect(_on_meter_changed)
	GameState.friendship_changed.connect(_on_meter_changed)
	_refresh()


func on_enter(params: Dictionary) -> void:
	super(params)
	_refresh()


# --- refresh -----------------------------------------------------------------

func _refresh() -> void:
	if not is_node_ready():
		return
	var monkey := GameState.monkey()
	var slot_label := "AM" if GameState.slot() == int(DayCycle.Slot.AM) else "PM"
	_hud.show_overworld(GameState.day(), slot_label,
		monkey.monkey_name if monkey != null else "---", "")

	if monkey == null:
		_state_label.text = "THERE IS NO MONKEY."
		_build_list()
		return

	_friend_meter.set_value(monkey.friendship, Monkey.FRIENDSHIP_MAX)
	_fullness_meter.set_value(monkey.fullness, Monkey.FULLNESS_MAX)
	_friend_caption.text = "FRIENDSHIP  %d / %d" % [monkey.friendship, Monkey.FRIENDSHIP_MAX]
	_fullness_caption.text = "FULLNESS  %d / %d" % [monkey.fullness, Monkey.FULLNESS_MAX]
	_state_label.text = _state_text(monkey)
	_build_list()


## The advice line. It has to be right about direction, because the guides'
## rule — feed only when it cannot move — is the opposite of what a player's
## instinct says (dossier §5 [C]).
func _state_text(monkey: Monkey) -> String:
	var blocked := GameState.block_reason()
	if not blocked.is_empty():
		return blocked
	if monkey.fullness > Care.FULLNESS_CONTENT_MAX:
		return "%s IS FULL. FEEDING AGAIN RISKS STOPPING IT DEAD." % monkey.monkey_name.to_upper()
	if monkey.fullness <= Care.FULLNESS_HUNGRY_MAX:
		return "%s IS HUNGRY. NOW IS THE TIME TO FEED IT." % monkey.monkey_name.to_upper()
	return "%s IS CONTENT. FEEDING NOW ONLY FILLS IT UP." % monkey.monkey_name.to_upper()


func _build_list() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()

	var monkey := GameState.monkey()
	var inventory := GameState.inventory()
	if inventory.is_empty():
		var empty := Label.new()
		empty.text = "THE LARDER IS EMPTY.\nSEND THE MONKEY SHOPPING."
		empty.add_theme_font_size_override("font_size", Palette.FONT_BODY)
		empty.add_theme_color_override("font_color", Palette.DISABLED)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
		return

	# Stable order: whatever FoodDb declares, so the list does not reshuffle
	# under the player's thumb as counts change.
	for id in FoodDb.ids():
		var food_id := String(id)
		var count := int(inventory.get(food_id, 0))
		if count <= 0:
			continue
		var food := FoodDb.get_food(food_id)
		if food == null:
			continue
		_list.add_child(_food_row(food, count, monkey))


func _food_row(food: Food, count: int, monkey: Monkey) -> Control:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, Palette.TOUCH_MIN + 40)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_on_feed_pressed.bind(food.id))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_%s" % side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	button.add_child(margin)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(head)

	var name_label := _line("%s  x%d" % [food.display_name.to_upper(), count],
		Palette.FONT_BODY, Palette.INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_label)

	# Dossier §5 [C]: per-type food preferences are real — most monkeys like
	# bananas, curry and ice milk; some dislike garlic, chicken and liver.
	if monkey != null:
		var species := monkey.species()
		if species.likes(food.id):
			head.add_child(_line("LIKES IT", Palette.FONT_SMALL, Palette.GOOD))
		elif species.dislikes(food.id):
			head.add_child(_line("DISLIKES IT", Palette.FONT_SMALL, Palette.BAD))

	var parts: Array[String] = []
	if food.strength_restore != 0:
		parts.append("STRG +%d" % food.strength_restore)
	if food.stamina_restore != 0:
		parts.append("STM +%d" % food.stamina_restore)
	# Coffee is Hunger -5 on purpose: it makes room for more food (§5 [C]).
	parts.append("HUNGER %+d" % food.hunger)
	col.add_child(_line("   ".join(parts), Palette.FONT_SMALL, Palette.INK))

	if food.is_permanent_booster():
		var boosts: Array[String] = []
		var wasted := false
		for stat in food.permanent_gains:
			var stat_id := int(stat)
			boosts.append("%s +%d" % [Monkey.stat_label(stat_id), int(food.permanent_gains[stat])])
			if monkey != null and monkey.is_capped(stat_id):
				wasted = true
		# Dossier §3 [C]: permanent-boost foods are WASTED on a starred stat.
		# Say so before the player spends it, not after.
		var text := "PERMANENT: %s" % ", ".join(boosts)
		if wasted:
			text += "   (ALREADY STARRED — WOULD BE WASTED)"
		col.add_child(_line(text, Palette.FONT_SMALL,
			Palette.STAT_CAPPED if wasted else Palette.ACCENT))

	# The overfeeding warning, computed from the food's own hunger value.
	if monkey != null and monkey.fullness + food.hunger >= Monkey.FULLNESS_STUFFED:
		col.add_child(_line(
			"THIS WOULD STOP IT MOVING UNTIL IT DIGESTS.",
			Palette.FONT_SMALL, Palette.BAD))
	return button


func _line(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	return label


# --- actions -----------------------------------------------------------------

func _on_feed_pressed(food_id: String) -> void:
	Sfx.click()
	var result := GameState.feed(food_id)
	if result == null:
		_message.text = "IT WILL NOT TAKE THAT."
		return
	# Core wrote the sentence; the screen only picks the cue.
	match result.outcome:
		Care.FeedOutcome.BITE:
			Sfx.play(Sfx.Cue.ANGRY)
		Care.FeedOutcome.CAUSED_PARALYSIS:
			Sfx.play(Sfx.Cue.ANGRY)
		Care.FeedOutcome.REFUSED_DISLIKED:
			Sfx.play(Sfx.Cue.ANGRY)
		_:
			Sfx.play(Sfx.Cue.HAPPY)


func _on_monkey_fed(result: Care.FeedResult) -> void:
	if result != null:
		_message.text = result.message
	_refresh()


func _on_meter_changed(_value: int) -> void:
	_refresh()


func _on_back() -> void:
	Sfx.cancel()
	close({"message": _message.text})


static func _box(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = Palette.INK_LIGHT
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style
