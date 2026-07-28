extends GameScreen

## Bill's fight card. Dossier §7 phase 2 [C]:
##
##   "Bill rings the doorbell and asks you to pick tomorrow's opponent from
##    THREE candidates, AT LEAST ONE RANKED ABOVE YOU. Stronger opponent =
##    bigger purse."
##
## and §7 [C] on what a result is worth: beat a higher-ranked monkey and you go
## up a rung; beating a lower-ranked one PAYS BUT DOES NOT PROMOTE, which is why
## the card shows what each fight is actually for. Bill books every match free of
## charge (§11 [C]) — there is no entry fee to show.
##
## The prompt string is the original's, from `docs/reference/screens-hg101/choose-opponent.png`.
##
## LAYERING: the three candidates come from `GameState.offered_opponents()` and
## the booking goes back through `GameState.book_opponent(index)`. This screen
## generates no opponent, computes no purse and moves no rank.

const CARD_COUNT := 3

@onready var _bg: ColorRect = $Bg
@onready var _rank_label: Label = $Root/Header/Rank
@onready var _money_label: Label = $Root/Header/Money
@onready var _prompt: Label = $Root/Prompt/Text
@onready var _cards_box: VBoxContainer = $Root/Cards
@onready var _back: Button = $Root/Footer/Back
@onready var _confirm: Button = $Root/Footer/Confirm

var _offers: Array = []
var _selected := -1
var _cards: Array[Button] = []
var _group: ButtonGroup = null


func _ready() -> void:
	super._ready()
	_bg.color = Palette.BG
	_group = ButtonGroup.new()
	for i in CARD_COUNT:
		var card: Button = _cards_box.get_child(i)
		card.button_group = _group
		card.pressed.connect(_on_card_pressed.bind(i))
		_cards.append(card)
	_back.pressed.connect(_on_back_pressed)
	_confirm.pressed.connect(_on_confirm_pressed)
	_prompt.text = "WHO DO YOU WANT TO FIGHT NEXT?"
	_prompt.add_theme_color_override("font_color", Palette.INK)
	for label in [_rank_label, _money_label]:
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)


func on_enter(params: Dictionary) -> void:
	super.on_enter(params)
	_refresh()


# --- population --------------------------------------------------------------

func _refresh() -> void:
	_offers = GameState.offered_opponents()
	_selected = -1
	_confirm.disabled = true
	_rank_label.text = "JSB RANK: %d" % GameState.rank()
	# The original's stat card writes money as `INCOME  ¥8000` (dossier §10 [C]).
	_money_label.text = "¥%d" % GameState.money()

	for i in _cards.size():
		var card := _cards[i]
		if i >= _offers.size():
			card.visible = false
			continue
		card.visible = true
		card.button_pressed = false
		_fill_card(card, _offers[i])

	if _offers.is_empty():
		_prompt.text = "BILL HAS NO CARD FOR YOU TODAY."


func _fill_card(card: Button, opponent: Ladder.Opponent) -> void:
	var monkey: Monkey = opponent.monkey
	var chip: ColorRect = card.get_node("Body/Row/Chip")
	var name_label: Label = card.get_node("Body/Row/Info/Name")
	var trainer_label: Label = card.get_node("Body/Row/Info/Trainer")
	var stats_label: Label = card.get_node("Body/Row/Info/Stats")
	var above_label: Label = card.get_node("Body/Row/Side/Above")
	var purse_label: Label = card.get_node("Body/Row/Side/Purse")

	chip.color = Palette.monkey_color(monkey.species_type)
	# The original's stat card prints the sex marker after the name — `MAX(ML)`
	# (dossier §8 [U] / §10 [C]). `Monkey.name_line()` prefixes "NAME:", which
	# reads wrong next to a rank, so the two parts are composed here instead.
	name_label.text = "RANK %d   %s(%s)" % [
		opponent.rank, monkey.monkey_name.to_upper(), monkey.sex_marker()]
	trainer_label.text = "TRAINER: %s" % opponent.trainer_name

	var parts: Array[String] = []
	for stat in Monkey.STATS:
		parts.append("%s %d" % [Monkey.stat_label(stat), monkey.get_stat(stat)])
	stats_label.text = "  ".join(parts)

	# Dossier §7 [C]: at least one candidate outranks you, and only that one can
	# promote you. Saying so on the card is the whole reason the choice is a
	# choice — the others are cash.
	if opponent.is_above_player:
		above_label.text = "RANKED ABOVE YOU\nWIN = RANK UP"
		above_label.add_theme_color_override("font_color", Palette.WARN)
	else:
		above_label.text = "AT OR BELOW YOU\nPAYS, NO PROMOTION"
		above_label.add_theme_color_override("font_color", Palette.INK)
	purse_label.text = "PURSE ¥%d" % opponent.purse


# --- input -------------------------------------------------------------------

func _on_card_pressed(index: int) -> void:
	if index >= _offers.size():
		return
	Sfx.click()
	_selected = index
	_confirm.disabled = false
	var opponent: Ladder.Opponent = _offers[index]
	_confirm.text = "FIGHT %s TOMORROW" % opponent.monkey.monkey_name.to_upper()


func _on_confirm_pressed() -> void:
	if _selected < 0 or _selected >= _offers.size():
		return
	Sfx.confirm()
	var opponent: Ladder.Opponent = _offers[_selected]
	# Booking sets the run's phase to MATCH_DAY; the fight is TOMORROW (§7 [C]),
	# so this screen hands control back rather than starting a match itself.
	GameState.book_opponent(_selected)
	if bool(enter_params.get("then_fight", false)):
		Router.replace(Router.Screen.MATCH, {})
		return
	close({"booked": true, "index": _selected, "opponent": opponent})


func _on_back_pressed() -> void:
	Sfx.cancel()
	close({"booked": false})
