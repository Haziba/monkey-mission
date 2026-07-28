extends GameScreen

## HOME — the screen the player lives in.
##
## Dossier §2 [C]: the game is menu-driven from your home and **there is no
## overworld to walk around**. Shops are menu entries and it is the *monkey*
## that goes shopping, not the player. Two actions per day; every activity
## costs one half-day slot; **feeding is free and costs no slot**.
##
## Layout follows `docs/reference/screens-hg101/menu-2.png` and
## `.../chattering.png`:
##
##     [DAYS 48 PM]                 [PIZZA♪]     <- HudBoxes, dossier §10 [C]
##     +-------------------------------------+
##     |  tatami room, trainer and monkey    |
##     +-------------------------------------+
##     | FREDDY IS CHATTERING                |   <- message box
##     +-------------------------------------+
##     |  stat card                          |
##     +-------------------------------------+
##     |  SKIPPING        SIT-UPS            |   <- the activity menu, in the
##     |  PUNCHBAG        RUNNING            |      original's own order
##     |  SHOPPING        SPARRING           |
##     |  FEED            MATCH              |
##
## The original's menu reads `SKIPPING / SIT-UPS`, `PUNCHBAG / RUNNING`,
## `SPARRING` in two columns (§4 [C]), with shopping reached separately via
## "call monkey -> shopping". Both are on the one grid here because a phone has
## no second menu level worth paying for.
##
## Everything this screen knows about rules, it asks GameState. It computes no
## gain, no purse and no rank move, and it never mutates a Monkey.

## Menu slots, row-major in a 2-column grid.
## BREEDING and ROSTER were appended by the Integration agent: both screens
## existed but nothing routed to either, which left the game's signature system
## (dossier §8) unreachable.
## REST was appended by the Verification agent. Dossier §5 [C]: both hunger
## extremes immobilise the monkey, and everything else on this menu that costs a
## half-day is gated on the monkey being able to act — so a stuffed or starving
## monkey had no way to move the clock, never digested, and never reached the
## day rollover where `Economy.check_bailout()` grants the bailout that
## `bankruptcy_game_over = false` promises.
enum MenuSlot {
	SKIPPING, SIT_UPS, PUNCHBAG, RUNNING, SHOPPING, SPARRING, FEED, MATCH,
	BREEDING, ROSTER, REST,
}

## Idle bob for the monkey, in logical pixels and seconds.
const IDLE_BOB := 14.0
const IDLE_BOB_TIME := 0.9

@onready var _bg: ColorRect = $Bg
@onready var _hud: HudBoxes = $Root/Col/Hud
@onready var _room: Control = $Root/Col/Room
@onready var _monkey_rig: Control = $Root/Col/Room/MonkeyRig
@onready var _mood: Label = $Root/Col/Room/MonkeyRig/Mood
@onready var _message_panel: PanelContainer = $Root/Col/MessageBox
@onready var _message: Label = $Root/Col/MessageBox/Text
@onready var _card: StatCard = $Root/Col/Card
@onready var _menu: GridContainer = $Root/Col/Menu

var _buttons: Array[Button] = []
var _bob: Tween = null
## The day this screen last showed the end-of-day card for. Two half-day slots
## are spent from screens pushed on top of this one, so the rollover has to be
## noticed when control comes back, not when the signal fires.
var _last_seen_day: int = 0


func _ready() -> void:
	super()
	_apply_palette()
	_build_menu()
	_connect_game_state()
	_room.resized.connect(_start_idle_bob)
	_start_idle_bob()
	_arm_day_snapshot()
	_refresh()


func on_enter(params: Dictionary) -> void:
	super(params)
	_arm_day_snapshot()
	_refresh()


## A pushed screen came back. The training screen hands its closing line up so
## the home message box carries on the conversation.
func on_result(result: Dictionary) -> void:
	var text := String(result.get("message", ""))
	if not text.is_empty():
		_say(text)
	_refresh()
	# `day_ended` comes back from the end-of-day card itself (and from the
	# post-match card, which is the same scene), so seeing one never queues
	# another.
	if bool(result.get("day_ended", false)):
		# Re-arm, or the NEXT rollover compares against a day counter that is
		# already stale and raises a second card for a day the player has just
		# been shown. The post-match card reaches us this way — the fight screen
		# REPLACES itself with it, so `_maybe_show_day_end` never ran and
		# `_last_seen_day` was left behind by however many days the fight moved.
		_arm_day_snapshot()
		return
	_maybe_show_day_end()


## Dossier §10 [C] and `docs/reference/screens-hg101/end-of-day.png`: the
## original closes a day on a portrait card over sunburst lines. Two activities
## fill a day, and both are spent inside pushed screens, so the card is raised
## here once control returns and the day counter has moved on.
func _maybe_show_day_end() -> void:
	var today := GameState.day()
	if today <= _last_seen_day:
		return
	# Arm BEFORE pushing: the card pops straight back into on_result, and an
	# un-armed counter would raise it again for ever.
	var closed_day := _last_seen_day
	_arm_day_snapshot()
	Router.push(Router.Screen.DAY_END, {"day": closed_day})


## Remember the day and take the stat/money snapshot the card diffs against.
func _arm_day_snapshot() -> void:
	_last_seen_day = GameState.day()
	DayEndScreen.note_day_start(GameState.monkey(), GameState.money())


# --- wiring ------------------------------------------------------------------

func _connect_game_state() -> void:
	GameState.day_advanced.connect(_on_day_advanced)
	GameState.day_started.connect(_on_day_started)
	GameState.story_event.connect(_on_story_event)
	GameState.active_monkey_changed.connect(_on_monkey_changed)
	GameState.stats_changed.connect(_on_monkey_changed)
	GameState.friendship_changed.connect(_on_meter_changed)
	GameState.fullness_changed.connect(_on_meter_changed)
	GameState.money_changed.connect(_on_meter_changed)
	GameState.rank_changed.connect(_on_rank_changed)
	GameState.monkey_fed.connect(_on_monkey_fed)
	GameState.paralysis_started.connect(_on_paralysis_started)
	GameState.paralysis_ended.connect(_on_paralysis_ended)
	GameState.training_finished.connect(_on_training_finished)
	GameState.destitute_warning.connect(_on_destitute_warning)
	GameState.bailout_granted.connect(_on_bailout_granted)
	GameState.relief_granted.connect(_on_relief_granted)


func _build_menu() -> void:
	_buttons.clear()
	for child in _menu.get_children():
		_buttons.append(child as Button)
	# Labels come from core so the menu can never disagree with the enum.
	_buttons[MenuSlot.SKIPPING].text = Training.display_name(Training.Activity.SKIPPING)
	_buttons[MenuSlot.SIT_UPS].text = Training.display_name(Training.Activity.SIT_UPS)
	_buttons[MenuSlot.PUNCHBAG].text = Training.display_name(Training.Activity.PUNCHBAG)
	_buttons[MenuSlot.RUNNING].text = Training.display_name(Training.Activity.RUNNING)
	_buttons[MenuSlot.SHOPPING].text = Training.display_name(Training.Activity.SHOPPING)
	# §4 [C] and §14: the widely-repeated "five training activities" is wrong —
	# sparring is the sixth, and most summaries drop it. It is in the menu here
	# because the original's menu has it, but docs/ARCHITECTURE.md §8 puts it
	# outside this slice, so it is shown disabled rather than quietly deleted.
	_buttons[MenuSlot.SPARRING].text = "%s (N/A)" % Training.display_name(
		Training.Activity.SPARRING)
	_buttons[MenuSlot.SPARRING].disabled = true
	_buttons[MenuSlot.FEED].text = "FEED"
	_buttons[MenuSlot.MATCH].text = "MATCH"
	# Dossier §8 [C]: the shop is called "dating" in English (お見合い / 配合 in
	# Japanese) and is advertised on the box.
	_buttons[MenuSlot.BREEDING].text = "DATING SHOP"
	_buttons[MenuSlot.ROSTER].text = "ROSTER"
	_buttons[MenuSlot.REST].text = "REST"
	for index in _buttons.size():
		var slot := index
		_buttons[index].focus_mode = Control.FOCUS_NONE
		_buttons[index].pressed.connect(func() -> void: _on_menu_pressed(slot))


func _apply_palette() -> void:
	_bg.color = Palette.BG
	# The tatami room with shoji doors (dossier §10 [C], "Locations").
	_paint(_room, "Wall", Palette.LOC_HOME.darkened(0.3))
	_paint(_room, "ShojiL", Palette.PAPER)
	_paint(_room, "ShojiR", Palette.PAPER)
	_paint(_room, "ShojiFrame", Palette.PAPER_EDGE)
	_paint(_room, "Floor", Palette.LOC_HOME)
	_paint(_room, "FloorLine", Palette.LOC_HOME.darkened(0.3))
	# The trainer — Kenta or Sumire. §14 [C]: the male/female choice in this
	# game is the TRAINER, not the monkey.
	_paint(_room, "TrainerRig/Legs", Palette.PANEL_DARK)
	_paint(_room, "TrainerRig/Body", Palette.ACCENT_ALT)
	_paint(_room, "TrainerRig/Head", Palette.PAPER)
	_paint(_room, "TrainerRig/Hair", Palette.INK)

	_mood.add_theme_color_override("font_color", Palette.ACCENT)
	_mood.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_message.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_message.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_message_panel.add_theme_stylebox_override("panel", _message_style())
	_menu.add_theme_constant_override("h_separation", Palette.GUTTER)
	_menu.add_theme_constant_override("v_separation", 20)
	_tint_monkey()


## The message box: black field, thick light border, as in every reference shot
## (e.g. docs/reference/screens-kog/025.png).
func _message_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.PANEL_DARK
	style.border_color = Palette.INK_LIGHT
	style.set_border_width_all(Palette.BORDER_WIDTH)
	style.set_corner_radius_all(Palette.CORNER_RADIUS)
	style.content_margin_left = 24.0
	style.content_margin_right = 24.0
	style.content_margin_top = 16.0
	style.content_margin_bottom = 16.0
	return style


## The five monkey types are colour variants (§8 [C]); colour is the only thing
## distinguishing them here, because art is placeholder shapes.
func _tint_monkey() -> void:
	var monkey := GameState.monkey()
	var type := monkey.species_type if monkey != null else SpeciesDb.default_type()
	var body := Palette.monkey_color(type)
	var accent := Palette.monkey_accent(type)
	_paint(_monkey_rig, "Tail", body.darkened(0.15))
	_paint(_monkey_rig, "Body", body)
	_paint(_monkey_rig, "Head", body)
	_paint(_monkey_rig, "EarL", accent)
	_paint(_monkey_rig, "EarR", accent)
	_paint(_monkey_rig, "Face", accent)
	_paint(_monkey_rig, "EyeL", Palette.INK)
	_paint(_monkey_rig, "EyeR", Palette.INK)


func _paint(root: Node, path: String, color: Color) -> void:
	var rect := root.get_node_or_null(path) as ColorRect
	if rect != null:
		rect.color = color


func _start_idle_bob() -> void:
	if _bob != null and _bob.is_valid():
		_bob.kill()
	if not is_inside_tree():
		return
	var rest := _monkey_rig.position
	_bob = create_tween().set_loops()
	_bob.tween_property(_monkey_rig, "position", rest + Vector2(0.0, -IDLE_BOB), IDLE_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob.tween_property(_monkey_rig, "position", rest, IDLE_BOB_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# --- refresh -----------------------------------------------------------------

func _refresh() -> void:
	if not is_node_ready():
		return
	var monkey := GameState.monkey()
	if monkey == null:
		_hud.show_overworld(GameState.day(), "AM", "---", "")
		_card.set_monkey(null, 0, 0, "NO RUN IN PROGRESS.")
		_set_menu_blocked(true)
		return

	var slot_label := "AM" if GameState.slot() == int(DayCycle.Slot.AM) else "PM"
	var glyph := _mood_glyph(monkey)
	_hud.show_overworld(GameState.day(), slot_label, monkey.monkey_name, glyph)
	_mood.text = glyph

	var reason := GameState.block_reason()
	_card.set_monkey(monkey, GameState.rank(), GameState.money(), reason)
	_tint_monkey()
	_set_menu_blocked(not reason.is_empty())

	# A monkey that cannot move should not be bobbing about happily.
	if reason.is_empty():
		if _bob == null or not _bob.is_valid():
			_start_idle_bob()
	elif _bob != null and _bob.is_valid():
		_bob.kill()


## The name box's mood glyph. §10 [C] attests `[PIZZA♪]` for happy; the rest are
## chosen (see HudBoxes) to surface the states that stop the monkey obeying.
func _mood_glyph(monkey: Monkey) -> String:
	if not monkey.is_befriended():
		return HudBoxes.GLYPH_ANGRY
	if monkey.is_starving():
		return HudBoxes.GLYPH_HUNGRY
	if monkey.is_stuffed():
		return HudBoxes.GLYPH_STUFFED
	if monkey.friendship >= Monkey.FRIENDSHIP_OBEDIENT:
		return HudBoxes.GLYPH_HAPPY
	return HudBoxes.GLYPH_NEUTRAL


## Everything that costs the monkey effort is gated on Care's block reason —
## unbefriended, starving, or stuffed (§5 [C]: both hunger extremes paralyse).
## FEED is never gated: feeding is free, costs no slot, and is the way out of
## two of the three states.
func _set_menu_blocked(blocked: bool) -> void:
	for slot in [MenuSlot.SKIPPING, MenuSlot.SIT_UPS, MenuSlot.PUNCHBAG,
			MenuSlot.RUNNING, MenuSlot.SHOPPING, MenuSlot.MATCH]:
		_buttons[slot].disabled = blocked
	_buttons[MenuSlot.FEED].disabled = false


func _say(text: String) -> void:
	_message.text = text.to_upper()


# --- menu --------------------------------------------------------------------

func _on_menu_pressed(slot: int) -> void:
	Sfx.click()
	match slot:
		MenuSlot.SKIPPING:
			_start_training(Training.Activity.SKIPPING)
		MenuSlot.SIT_UPS:
			_start_training(Training.Activity.SIT_UPS)
		MenuSlot.PUNCHBAG:
			_start_training(Training.Activity.PUNCHBAG)
		MenuSlot.RUNNING:
			_start_training(Training.Activity.RUNNING)
		MenuSlot.SHOPPING:
			_send_shopping()
		MenuSlot.FEED:
			Router.push(Router.Screen.FEED)
		MenuSlot.MATCH:
			_go_to_match()
		MenuSlot.BREEDING:
			_go_to_dating_shop()
		MenuSlot.ROSTER:
			Router.push(Router.Screen.ROSTER)
		MenuSlot.REST:
			_rest()


## Spend the half-day waiting. Dossier §2 [C]: every activity costs one half-day
## slot; §5 [C]: an overfed monkey "cannot move until it digests" and an underfed
## one is "immobilised by hunger". Resting is how the clock moves while either is
## true — it is the price of overfeeding, not a way round it, so it trains
## nothing, earns nothing and is never the efficient choice.
func _rest() -> void:
	var monkey := GameState.monkey()
	var who := monkey.monkey_name.to_upper() if monkey != null else "THE MONKEY"
	if not GameState.rest():
		return
	_say("%s TAKES IT EASY. HALF THE DAY IS GONE." % who)
	_refresh()
	_maybe_show_day_end()


## Dossier §8 [C]: breeding is the only way past a hard cap, and the only route
## forward once the ladder outpaces you (§7 phase 3). The shop is always open —
## core's `Breeding.can_breed()` is what refuses an uncapped monkey — but the
## message box repeats core's own advice on the way in, because the dossier
## records two credible schools of when to pair and settles neither.
func _go_to_dating_shop() -> void:
	_say(GameState.breed_advice())
	Router.push(Router.Screen.BREEDING)


func _start_training(activity: Training.Activity) -> void:
	var reason := GameState.block_reason()
	if not reason.is_empty():
		_say(reason)
		return
	Router.push(Router.Screen.TRAINING_SESSION, {"activity": int(activity)})


## Dossier §4 [C]: you send the MONKEY shopping. An empty wish list is
## free-choice shopping — the only route to new food types, at the cost of the
## monkey wasting money on junk. It costs a half-day slot like any activity, so
## it goes through GameState and never touches Economy directly.
func _send_shopping() -> void:
	var result := GameState.do_shopping({})
	if result == null:
		_say(GameState.block_reason())
		return
	var line := result.message
	if not result.shopping_haul.is_empty():
		var parts: Array[String] = []
		for id in result.shopping_haul:
			var food := FoodDb.get_food(String(id))
			var label := food.display_name if food != null else String(id)
			parts.append("%s x%d" % [label, int(result.shopping_haul[id])])
		line += "  (%s)" % ", ".join(parts)
	_say(line)
	_refresh()
	# Shopping is the one slot-consuming activity resolved inline rather than in
	# a pushed screen, so nothing else would raise the end-of-day card for it.
	_maybe_show_day_end()


## Bill books the fights, free of charge (§7, §11 [C]); this only routes to
## whichever screen owns that conversation right now.
func _go_to_match() -> void:
	if GameState.run != null and GameState.run.phase == RunState.Phase.MATCH_DAY:
		Router.push(Router.Screen.MATCH)
		return
	Router.push(Router.Screen.OPPONENT_SELECT)


# --- GameState signals -------------------------------------------------------

func _on_day_advanced(_day: int, _slot: int) -> void:
	_refresh()


func _on_day_started(day: int) -> void:
	_say("DAY %d BEGINS." % day)
	_refresh()


## Doorbell beats at the start of a day (dossier §11 [C]).
func _on_story_event(event_id: String) -> void:
	_say("DING DONG! (%s)" % event_id.to_upper())


func _on_monkey_changed(_monkey: Monkey) -> void:
	_refresh()


func _on_meter_changed(_value: int) -> void:
	_refresh()


func _on_rank_changed(_old_rank: int, new_rank: int) -> void:
	_say("JSB RANK IS NOW %d." % new_rank)
	_refresh()


func _on_monkey_fed(result: Care.FeedResult) -> void:
	if result != null:
		_say(result.message)
	_refresh()


func _on_paralysis_started(slots: int) -> void:
	# FAITHFUL, requested explicitly: overfeeding immobilises until it digests
	# (§5 [C]). Say so in as many words — the player must understand why the
	# menu just went dead. This is NOT "wasted food".
	_say("IT CANNOT MOVE. WAIT %d HALF-DAY%s." % [slots, "" if slots == 1 else "S"])
	_refresh()


func _on_paralysis_ended() -> void:
	_say("IT CAN MOVE AGAIN.")
	_refresh()


func _on_training_finished(result: Training.Result) -> void:
	if result != null:
		_say(result.message)
	_refresh()


func _on_destitute_warning() -> void:
	_say("NO FOOD AND NO MONEY!")


## bankruptcy_game_over = false: the original's only fail state (§9 [C]) becomes
## a warning and a hand-out here. See docs/ARCHITECTURE.md §12.
func _on_bailout_granted(amount: int) -> void:
	_say("BILL LENDS YOU ¥%d. DON'T LET IT HAPPEN AGAIN." % amount)
	_refresh()


## The larder ran dry while the monkey was too hungry (or too wary) to go and
## fill it. Money cannot fix that on its own — the MONKEY does the shopping
## (§2 [C]) — so core sends a parcel. Say who it came from and what is in it,
## because the player has to know to go and FEED it.
func _on_relief_granted(parcel: Dictionary) -> void:
	var parts: Array[String] = []
	for id in parcel:
		var food := FoodDb.get_food(String(id))
		var label := food.display_name if food != null else String(id)
		parts.append("%s x%d" % [label, int(parcel[id])])
	_say("BILL LEAVES FOOD ON THE STEP: %s. FEED IT!" % ", ".join(parts))
	_refresh()
