extends GameScreen

## The match screen. Dossier §6 (the match) and §10 (the fight HUD), and the
## reference shots `docs/reference/screens-kog/145.png` / `150.png` /
## `docs/reference/screens-hg101/boxing-2.png`.
##
## Shape of the original, reproduced as far as portrait allows:
##
##   AT              1R : 30              DF        <- strategy codes + round/clock
##   +-------------------------------------------+
##   |          ring, crowd, corner posts        |
##   +-------------------------------------------+
##   FREDDY                              AGATHA
##   ################ LOSS ####################
##   ##########       STM  ########
##
## The gauge strip is MIRRORED and CENTRE-ANCHORED — see ui/components/gauge_pair.gd.
## When commentary fires, a bordered box REPLACES the whole gauge strip and the
## top bar persists (§10 [C], and 150.png shows exactly that). Between rounds the
## top bar collapses to a single `STRATEGY: NONE` box and the bottom becomes the
## strategy menu (§10 [C], and screens-kog/120.png).
##
## LAYERING. This screen owns no rules. It reads `GameState.current_match` — the
## `MatchResolver` GameState created — and steps it with `advance(delta)`, which
## is exactly what the architecture contract asks the UI to do: "the resolver is
## a simulation stepped by advance(delta); the UI drives the clock and plays back
## MatchEvents. The UI must never compute damage." Every strategy, corner action
## and tap goes through GameState.

## DIVERGENCE: the original animates a round in real time. `ROUND_SECONDS` is 60
## in core, and sixty seconds of watching per round is a poor fit for a phone, so
## the screen exposes a playback multiplier and defaults to 2x (a round in ~30s).
## This only scales the delta fed to `advance()`; it changes no simulation value,
## since the resolver dices the round into fixed 3s exchanges regardless of step
## size. The original has no speed control at all.
const CLOCK_SPEEDS: PackedFloat32Array = [1.0, 2.0, 4.0]
const SPEED_LABELS: PackedStringArray = ["1x", "2x", "4x"]
const DEFAULT_SPEED_INDEX := 1

## DIVERGENCE: how long the commentary box holds is [X] — no source times it.
## Just over a second reads without stalling the fight. The round clock is PAUSED
## while a message shows, because the box hides the gauges and a player cannot
## follow a fight they cannot see.
const COMMENTARY_SECONDS := 1.15
const SHOUT_SECONDS := 0.9
const POSE_SECONDS := 0.30
const DOWN_POSE_SECONDS := 1.30
const TAP_PULSE_SECONDS := 0.22

## Two-letter stance codes for the top corners, in MatchResolver.Strategy order.
## The original prints a stacked two-letter code in each top corner (145.png
## shows `AR`); what its codes abbreviate is [X], so these are ours and are
## keyed to our own labels: ATtack / DeFend / EVade / BaLanced.
const STRATEGY_CODES: PackedStringArray = ["AT", "DF", "EV", "BL"]

enum Pose { IDLE, PUNCH, HURT, BLOCK, DODGE, DOWN }
enum Stage { BROKEN, STRATEGY, ROUND, FINISHED }

## Which events stop the fight and take the gauge strip over with a commentary
## box. Every punch would be unreadable; these are the beats that change the
## story of the round — and DISOBEYED is in here deliberately, because the player
## has to SEE that low trust cost them.
const HEADLINE_EVENTS: Array[int] = [
	MatchResolver.EventKind.ROUND_START,
	MatchResolver.EventKind.DISOBEYED,
	MatchResolver.EventKind.KNOCKDOWN,
	MatchResolver.EventKind.GET_UP,
	MatchResolver.EventKind.SPECIAL_PUNCH,
	MatchResolver.EventKind.KO,
	MatchResolver.EventKind.DECISION,
]

@onready var _bg: ColorRect = $Bg
@onready var _top_bar: PanelContainer = $Root/TopBar
@onready var _left_code: Label = $Root/TopBar/TopRow/LeftCorner/Code
@onready var _left_downs: Label = $Root/TopBar/TopRow/LeftCorner/Downs
@onready var _clock: Label = $Root/TopBar/TopRow/Clock
@onready var _right_code: Label = $Root/TopBar/TopRow/RightCorner/Code
@onready var _right_downs: Label = $Root/TopBar/TopRow/RightCorner/Downs

@onready var _ring: Control = $Root/Ring
@onready var _canvas: Control = $Root/Ring/Canvas
@onready var _shout: Label = $Root/Ring/Shout
@onready var _trust_box: PanelContainer = $Root/Ring/TrustWarning
@onready var _trust_label: Label = $Root/Ring/TrustWarning/Text

@onready var _gauge_wrap: MarginContainer = $Root/Strip/GaugeWrap
@onready var _gauges: GaugePair = $Root/Strip/GaugeWrap/Gauges
@onready var _commentary: PanelContainer = $Root/Strip/Commentary
@onready var _commentary_label: Label = $Root/Strip/Commentary/Text

@onready var _bottom: Control = $Root/Bottom
@onready var _strategy_scroll: ScrollContainer = $Root/Bottom/StrategyScroll
@onready var _strategy_title: Label = $Root/Bottom/StrategyScroll/StratBox/StratTitle
@onready var _strategy_grid: GridContainer = $Root/Bottom/StrategyScroll/StratBox/StratGrid
@onready var _corner_title: Label = $Root/Bottom/StrategyScroll/StratBox/CornerTitle
@onready var _corner_grid: GridContainer = $Root/Bottom/StrategyScroll/StratBox/CornerGrid
@onready var _notice: Label = $Root/Bottom/StrategyScroll/StratBox/Notice
@onready var _go: Button = $Root/Bottom/StrategyScroll/StratBox/Go

@onready var _round_box: VBoxContainer = $Root/Bottom/RoundBox
@onready var _tap_info: Label = $Root/Bottom/RoundBox/InfoRow/TapInfo
@onready var _speed_button: Button = $Root/Bottom/RoundBox/InfoRow/Speed
@onready var _tap_button: Button = $Root/Bottom/RoundBox/Tap

@onready var _end_box: VBoxContainer = $Root/Bottom/EndBox
@onready var _summary: Label = $Root/Bottom/EndBox/Summary
@onready var _continue: Button = $Root/Bottom/EndBox/Continue

var _match: MatchResolver = null
var _stage: Stage = Stage.BROKEN
var _speed_index := DEFAULT_SPEED_INDEX
var _chosen_strategy := -1
var _corner_taken := false
var _corner_label := ""
## True for the whole of a round in which the obedience roll failed. The player
## must SEE that low trust cost them the round — dossier §5/§6 [C], and
## GameRules.disobedience_enabled is faithful at the user's explicit request.
var _disobeying := false
var _last_round: MatchResolver.RoundResult = null
var _final: MatchResolver.MatchResult = null
var _rank_before := 0

var _commentary_queue: Array[String] = []
var _commentary_t := 0.0
var _shout_t := 0.0
var _tap_pulse := 0.0
var _tap_credits := 0
var _time := 0.0

var _left_pose: Pose = Pose.IDLE
var _right_pose: Pose = Pose.IDLE
var _left_pose_t := 0.0
var _right_pose_t := 0.0
var _left_body: Color = Palette.ACCENT
var _right_body: Color = Palette.ACCENT_ALT
var _left_accent: Color = Palette.INK_LIGHT
var _right_accent: Color = Palette.INK_LIGHT

var _strategy_buttons: Array[Button] = []
var _corner_buttons: Array[Button] = []
var _connected := false


func _ready() -> void:
	super._ready()
	_collect_buttons()
	_apply_palette()
	_canvas.draw.connect(_paint_ring)
	_ring.gui_input.connect(_on_ring_gui_input)
	_tap_button.pressed.connect(_on_tap)
	_speed_button.pressed.connect(_on_speed_pressed)
	_go.pressed.connect(_on_go_pressed)
	_continue.pressed.connect(_on_continue_pressed)
	set_process(true)


func on_enter(params: Dictionary) -> void:
	super.on_enter(params)
	_connect_game_state()
	_begin()


func on_exit() -> void:
	_disconnect_game_state()


# --- setup -------------------------------------------------------------------

func _collect_buttons() -> void:
	_strategy_buttons.clear()
	for i in MatchResolver.STRATEGY_LABELS.size():
		var button: Button = _strategy_grid.get_child(i)
		button.text = MatchResolver.strategy_label(i as MatchResolver.Strategy)
		button.pressed.connect(_on_strategy_pressed.bind(i))
		_strategy_buttons.append(button)
	_corner_buttons.clear()
	for i in MatchResolver.CORNER_LABELS.size():
		var button: Button = _corner_grid.get_child(i)
		# The full label goes on the face of the button. It used to be trimmed to
		# a single word with the real wording in a tooltip, which a touchscreen
		# never shows — so on the target platform the flavour was invisible.
		button.text = _wrapped_corner_label(i)
		button.pressed.connect(_on_corner_pressed.bind(i))
		_corner_buttons.append(button)


func _apply_palette() -> void:
	_bg.color = Palette.BG
	_clock.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_clock.add_theme_color_override("font_color", Palette.INK_LIGHT)
	for label in [_left_code, _right_code]:
		label.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
		label.add_theme_color_override("font_color", Palette.ACCENT)
	for label in [_left_downs, _right_downs]:
		label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		label.add_theme_color_override("font_color", Palette.BAD)
	_shout.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_shout.add_theme_color_override("font_color", Palette.GAUGE_LOSS)
	_commentary_label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_trust_label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_trust_label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_notice.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_notice.add_theme_color_override("font_color", Palette.WARN)
	for label in [_strategy_title, _corner_title, _tap_info]:
		label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_shout.visible = false
	_trust_box.visible = false


func _connect_game_state() -> void:
	if _connected:
		return
	GameState.match_event.connect(_on_match_event)
	GameState.match_finished.connect(_on_match_finished)
	_connected = true


func _disconnect_game_state() -> void:
	if not _connected:
		return
	if GameState.match_event.is_connected(_on_match_event):
		GameState.match_event.disconnect(_on_match_event)
	if GameState.match_finished.is_connected(_on_match_finished):
		GameState.match_finished.disconnect(_on_match_finished)
	_connected = false


func _begin() -> void:
	var live: MatchResolver = GameState.current_match
	if live == null:
		# Dossier §5 [C]: both hunger extremes immobilise the monkey, and an
		# unbefriended one obeys nothing. A monkey that cannot move cannot answer
		# the bell either — GameState.start_match() refuses, and the reason has to
		# be shown rather than reported as a missing booking.
		if not GameState.can_fight():
			_fail(GameState.block_reason().to_upper())
			return
		live = GameState.start_match()
	if live == null or live.player == null or live.opponent == null:
		_fail("NO MATCH IS BOOKED.\nSEE BILL FIRST.")
		return
	_match = live
	_rank_before = GameState.rank()

	var mine: Monkey = _match.player.monkey
	var theirs: Monkey = _match.opponent.monkey
	_left_body = Palette.monkey_color(mine.species_type)
	_left_accent = Palette.monkey_accent(mine.species_type)
	_right_body = Palette.monkey_color(theirs.species_type)
	_right_accent = Palette.monkey_accent(theirs.species_type)
	_gauges.configure(mine.monkey_name, theirs.monkey_name, _left_accent, _right_accent)
	_refresh_gauges()
	_gauges.snap()
	_enter_strategy()


func _fail(message: String) -> void:
	_stage = Stage.BROKEN
	_strategy_scroll.visible = false
	_round_box.visible = false
	_end_box.visible = true
	_summary.text = message
	_continue.text = "BACK"
	_clock.text = "--"
	_left_code.text = ""
	_right_code.text = ""


# --- stages ------------------------------------------------------------------

## Between rounds (and before round 1). Dossier §10 [C]: the top bar collapses to
## a single STRATEGY box and the bottom becomes the strategy menu.
func _enter_strategy() -> void:
	_stage = Stage.STRATEGY
	_chosen_strategy = -1
	_corner_taken = false
	_corner_label = ""
	_disobeying = false
	_trust_box.visible = false
	_commentary_queue.clear()
	_hide_commentary()
	_strategy_scroll.visible = true
	_round_box.visible = false
	_end_box.visible = false

	_left_code.text = ""
	_right_code.text = ""
	_left_downs.text = ""
	_right_downs.text = ""
	_update_strategy_banner()

	var is_break := _match.round_index > 1
	_strategy_title.text = "SET YOUR STRATEGY FOR ROUND %d" % _match.round_index
	for i in _strategy_buttons.size():
		_strategy_buttons[i].button_pressed = false
		_strategy_buttons[i].disabled = false
	# Dossier §6 [C]: the corner action belongs to a BREAK. There is no break
	# before round 1, so the corner opens from round 2. One only, irreversible —
	# unlike Strategy, you cannot change your mind.
	_corner_title.text = ("CORNER ACTION - ONE ONLY, NO TAKING IT BACK"
		if is_break else "CORNER ACTION - AVAILABLE AT THE BREAKS")
	for button in _corner_buttons:
		button.disabled = not is_break
	_refresh_notice()
	_go.text = "ANSWER THE BELL"
	_go.disabled = true
	_refresh_gauges()


func _enter_round() -> void:
	_stage = Stage.ROUND
	_tap_credits = 0
	_strategy_scroll.visible = false
	_end_box.visible = false
	# TAP_ENCOURAGE is this build's addition (§6 [C]: the original is pure
	# spectate). With any other setting the tap panel simply is not offered.
	var tappable := GameState.rules().fight_interactivity \
			== GameRules.FightInteractivity.TAP_ENCOURAGE
	_round_box.visible = true
	_tap_button.visible = tappable
	_tap_info.visible = tappable
	_tap_button.text = "TAP! TAP! TAP!"
	_refresh_tap_info()
	_match.start_round()
	_refresh_hud()


func _end_round() -> void:
	_last_round = _match.end_round()
	if _match.is_finished():
		_enter_finished()
	else:
		_enter_strategy()


func _enter_finished() -> void:
	_stage = Stage.FINISHED
	_strategy_scroll.visible = false
	_round_box.visible = false
	_end_box.visible = true
	_trust_box.visible = false
	_hide_commentary()

	if _final == null:
		_final = _match.result()
	# GameState settles up: purse, rank move, win/loss record, clears the match.
	# The resolver deliberately leaves purse and rank_delta at 0 because it is
	# never told the PLAYER's rank.
	GameState.finish_match(_final)
	var rank_after := GameState.rank()

	var lines: Array[String] = [_final.summary]
	if _final.outcome == MatchResolver.Outcome.WIN_DECISION \
			or _final.outcome == MatchResolver.Outcome.LOSS_DECISION \
			or _final.outcome == MatchResolver.Outcome.DRAW:
		lines.append("JUDGES  %d - %d" % [_final.player_score, _final.opponent_score])
	# The original's stat card prints money as `INCOME  ¥8000` (dossier §10 [C]).
	lines.append("PURSE  ¥%d" % _final.purse)
	if rank_after != _rank_before:
		lines.append("JSB RANK  %d -> %d" % [_rank_before, rank_after])
	else:
		lines.append("JSB RANK  %d (UNCHANGED)" % rank_after)
	_summary.text = "\n".join(lines)
	_continue.text = "CONTINUE"


# --- per-frame ---------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	_tick_poses(delta)
	if _tap_pulse > 0.0:
		_tap_pulse = maxf(0.0, _tap_pulse - delta)
	if _shout_t > 0.0:
		_shout_t = maxf(0.0, _shout_t - delta)
		_shout.modulate.a = clampf(_shout_t / SHOUT_SECONDS, 0.0, 1.0)
		if _shout_t <= 0.0:
			_shout.visible = false
	_canvas.queue_redraw()

	if _stage != Stage.ROUND or _match == null:
		return

	# The commentary box replaces the gauge strip while it shows, so the clock
	# holds. Dossier §10 [C] describes the swap; pausing keeps it readable.
	if _commentary_t > 0.0:
		_commentary_t = maxf(0.0, _commentary_t - delta)
		if _commentary_t <= 0.0:
			_hide_commentary()
		return
	if not _commentary_queue.is_empty():
		_show_commentary(_commentary_queue.pop_front())
		return
	if _match.is_round_over():
		_end_round()
		return

	_match.advance(delta * CLOCK_SPEEDS[_speed_index])
	_refresh_hud()


func _tick_poses(delta: float) -> void:
	if _left_pose_t > 0.0:
		_left_pose_t = maxf(0.0, _left_pose_t - delta)
		if _left_pose_t <= 0.0:
			_left_pose = Pose.IDLE
	if _right_pose_t > 0.0:
		_right_pose_t = maxf(0.0, _right_pose_t - delta)
		if _right_pose_t <= 0.0:
			_right_pose = Pose.IDLE


# --- HUD ---------------------------------------------------------------------

func _refresh_hud() -> void:
	if _match == null:
		return
	# The original's clock reads `1R : 27` (dossier §10 [C], boxing-2.png).
	_clock.text = "%dR : %02d" % [_match.round_index, int(ceilf(_match.time_remaining))]
	_left_code.text = _code_for(_match.player)
	_right_code.text = _code_for(_match.opponent)
	_left_downs.text = _down_pips(_match.player.downs)
	_right_downs.text = _down_pips(_match.opponent.downs)
	_left_code.add_theme_color_override("font_color",
		Palette.BAD if _disobeying else Palette.ACCENT)
	_refresh_gauges()
	_refresh_tap_info()


func _refresh_gauges() -> void:
	if _match == null or _match.player == null or _match.opponent == null:
		return
	var p := _match.player
	var o := _match.opponent
	_gauges.set_values(
		_frac(p.strength, p.monkey.max_strength()),
		_frac(p.stamina, p.monkey.max_stamina()),
		_frac(o.strength, o.monkey.max_strength()),
		_frac(o.stamina, o.monkey.max_stamina()))


func _refresh_tap_info() -> void:
	if not _tap_info.visible:
		return
	_tap_info.text = "ENCOURAGE  %d / %d" % [_tap_credits, MatchResolver.TAP_MAX_PER_ROUND]
	_speed_button.text = "SPEED %s" % SPEED_LABELS[_speed_index]


func _update_strategy_banner() -> void:
	# Dossier §10 [C]: between rounds the top bar collapses to `STRATEGY: NONE`.
	if _chosen_strategy < 0:
		_clock.text = "STRATEGY: NONE"
	else:
		_clock.text = "STRATEGY: %s" % MatchResolver.strategy_label(
			_chosen_strategy as MatchResolver.Strategy)


func _refresh_notice() -> void:
	var parts: Array[String] = []
	if _last_round != null and not _last_round.player_obeyed:
		parts.append("LOW TRUST: %s IGNORED YOU IN ROUND %d. FEED IT MORE." % [
			_match.player.monkey.monkey_name.to_upper(), _last_round.round_index])
	if _corner_taken:
		parts.append("CORNER USED: %s" % _corner_label)
	_notice.text = "\n".join(parts)
	_notice.visible = not parts.is_empty()


func _code_for(fighter: MatchResolver.Fighter) -> String:
	var index := int(fighter.acting_strategy)
	if index < 0 or index >= STRATEGY_CODES.size():
		return "--"
	return STRATEGY_CODES[index]


## Downs shown as pips, the way the original stacks small markers in the top
## corners (145.png / 150.png).
func _down_pips(downs: int) -> String:
	if downs <= 0:
		return ""
	var out := ""
	for _i in downs:
		out += "*"
	return "DOWN " + out


func _frac(value: int, maximum: int) -> float:
	if maximum <= 0:
		return 0.0
	return clampf(float(value) / float(maximum), 0.0, 1.0)


# --- commentary --------------------------------------------------------------

func _show_commentary(text: String) -> void:
	_commentary_label.text = text
	_commentary.visible = true
	_gauge_wrap.visible = false
	_commentary_t = COMMENTARY_SECONDS


func _hide_commentary() -> void:
	_commentary.visible = false
	_gauge_wrap.visible = true
	_commentary_t = 0.0


func _shout_text(text: String) -> void:
	_shout.text = text
	_shout.visible = true
	_shout.modulate.a = 1.0
	_shout_t = SHOUT_SECONDS


# --- match events ------------------------------------------------------------

func _on_match_event(event: MatchResolver.MatchEvent) -> void:
	_animate_event(event)
	if _is_headline(event):
		# A backlog would stall the fight; only the newest few are worth showing.
		if _commentary_queue.size() >= 3:
			_commentary_queue.pop_front()
		_commentary_queue.append(event.text)


func _animate_event(event: MatchResolver.MatchEvent) -> void:
	match event.kind:
		MatchResolver.EventKind.ROUND_START:
			_shout_text("ROUND %d" % event.round_index)
			Sfx.play(Sfx.Cue.BELL)
		MatchResolver.EventKind.PUNCH_LANDED:
			_set_pose(event.by_player, Pose.PUNCH)
			_set_pose(not event.by_player, Pose.HURT)
			_gauges.flash(not event.by_player)
			Sfx.play(Sfx.Cue.PUNCH)
		MatchResolver.EventKind.PUNCH_BLOCKED:
			_set_pose(event.by_player, Pose.PUNCH)
			_set_pose(not event.by_player, Pose.BLOCK)
			Sfx.play(Sfx.Cue.BLOCK)
		MatchResolver.EventKind.PUNCH_DODGED:
			_set_pose(event.by_player, Pose.PUNCH)
			_set_pose(not event.by_player, Pose.DODGE)
		MatchResolver.EventKind.STAMINA_DRAIN:
			_gauges.flash(event.by_player)
		MatchResolver.EventKind.KNOCKDOWN:
			# `by_player` is the side that THREW the punch, so the fighter on the
			# floor is the other one.
			_set_pose(not event.by_player, Pose.DOWN)
			_shout_text("DOWN!")
			Sfx.play(Sfx.Cue.KNOCKDOWN)
		MatchResolver.EventKind.GET_UP:
			# Here `by_player` IS the fighter getting up.
			_set_pose(event.by_player, Pose.IDLE)
		MatchResolver.EventKind.DISOBEYED:
			_disobeying = true
			_trust_box.visible = true
			_trust_label.text = "LOW TRUST - %s IS FIGHTING ITS OWN FIGHT" % \
				_match.player.monkey.monkey_name.to_upper()
			_shout_text("IGNORES YOU!")
			Sfx.play(Sfx.Cue.ANGRY)
		MatchResolver.EventKind.TAP_ENCOURAGE:
			_tap_credits = event.amount
			_tap_pulse = TAP_PULSE_SECONDS
		MatchResolver.EventKind.SPECIAL_PUNCH:
			_shout_text("SPECIAL!")
		MatchResolver.EventKind.KO:
			_shout_text("K.O.!")
			Sfx.play(Sfx.Cue.KNOCKDOWN)
		_:
			pass


func _is_headline(event: MatchResolver.MatchEvent) -> bool:
	return int(event.kind) in HEADLINE_EVENTS


func _on_match_finished(result: MatchResolver.MatchResult) -> void:
	_final = result


func _set_pose(left_side: bool, pose: Pose) -> void:
	var hold := DOWN_POSE_SECONDS if pose == Pose.DOWN else POSE_SECONDS
	if left_side:
		if _left_pose == Pose.DOWN and pose != Pose.IDLE:
			return
		_left_pose = pose
		_left_pose_t = hold
	else:
		if _right_pose == Pose.DOWN and pose != Pose.IDLE:
			return
		_right_pose = pose
		_right_pose_t = hold


# --- input -------------------------------------------------------------------

func _on_strategy_pressed(index: int) -> void:
	if _stage != Stage.STRATEGY:
		return
	Sfx.click()
	_chosen_strategy = index
	for i in _strategy_buttons.size():
		_strategy_buttons[i].button_pressed = (i == index)
	_update_strategy_banner()
	_go.disabled = false


func _on_corner_pressed(index: int) -> void:
	if _stage != Stage.STRATEGY or _corner_taken:
		return
	Sfx.confirm()
	# One only, irreversible (§6 [C]) — the resolver enforces it too, but the UI
	# must make the finality obvious BEFORE the tap, not after.
	GameState.corner_action(index)
	_corner_taken = true
	_corner_label = MatchResolver.corner_label(index as MatchResolver.CornerAction)
	for button in _corner_buttons:
		button.disabled = true
	_refresh_notice()
	_refresh_gauges()


func _on_go_pressed() -> void:
	if _stage != Stage.STRATEGY or _chosen_strategy < 0:
		return
	Sfx.confirm()
	GameState.set_strategy(_chosen_strategy)
	_enter_round()


func _on_tap() -> void:
	if _stage != Stage.ROUND:
		return
	GameState.tap_encourage()
	_tap_pulse = TAP_PULSE_SECONDS
	_refresh_tap_info()


func _on_speed_pressed() -> void:
	Sfx.click()
	_speed_index = (_speed_index + 1) % CLOCK_SPEEDS.size()
	_refresh_tap_info()


func _on_continue_pressed() -> void:
	Sfx.confirm()
	if _stage != Stage.FINISHED:
		close({"aborted": true})
		return
	Router.replace(Router.Screen.MATCH_RESULT, _result_params())


## RECONCILED BY THE INTEGRATION AGENT. This screen used to hand the result
## screen `{"result", "rank_before", "rank_after"}`, but the screen that
## actually renders that beat — `ui/screens/day_end.gd` — reads a different
## vocabulary (`day` / `lines` / `money_delta` / `friendship_delta` / `line`).
## The two were written in parallel and never met. Translating here rather than
## widening day_end keeps that screen usable for a plain end-of-day too.
func _result_params() -> Dictionary:
	var rank_after := GameState.rank()
	var lines: Array[String] = []
	if _final != null:
		lines.append(_final.summary)
		if _final.outcome == MatchResolver.Outcome.WIN_DECISION \
				or _final.outcome == MatchResolver.Outcome.LOSS_DECISION \
				or _final.outcome == MatchResolver.Outcome.DRAW:
			lines.append("JUDGES  %d - %d" % [_final.player_score, _final.opponent_score])
	if rank_after < _rank_before:
		# Rank 1 is the top, so a FALLING number is a promotion (see the sign
		# convention on Ladder.apply_result).
		lines.append("JSB RANK  %d -> %d   RANK UP!" % [_rank_before, rank_after])
	elif rank_after > _rank_before:
		lines.append("JSB RANK  %d -> %d   RANK DOWN." % [_rank_before, rank_after])
	else:
		lines.append("JSB RANK  %d (UNCHANGED)" % rank_after)

	var won := _final != null and _final.player_won
	return {
		"day": GameState.day(),
		"lines": lines,
		# The purse is the only money the fight moved; day_end prints it as
		# `PURSE +¥n`, which is the original's `INCOME ¥8000` register (§10 [C]).
		"money_delta": _final.purse if _final != null else 0,
		"line": "A GOOD FIGHT!" if won else "TOMORROW I'LL ALSO WORK HARD.",
	}


func _on_ring_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		_on_tap()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_tap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mp_tap"):
		_on_tap()
		accept_event()


# --- the ring ----------------------------------------------------------------
#
# Placeholder shapes only: draw_rect / draw_circle / draw_line / draw_polygon.
# Nothing ripped or traced from the original. The composition follows 145.png — crowd
# band across the top, a lit apron behind, ring floor in front, a corner post at
# each side, and the two fighters facing each other on the near rope.

func _paint_ring() -> void:
	var w := _canvas.size.x
	var h := _canvas.size.y
	if w <= 1.0 or h <= 1.0:
		return

	var crowd_h := h * 0.34
	_canvas.draw_rect(Rect2(0.0, 0.0, w, crowd_h), Palette.PANEL_DARK)
	_paint_crowd(w, crowd_h)

	# The lit apron behind the ring — the original's big yellow-green wedge.
	var apron := PackedVector2Array([
		Vector2(w * 0.42, crowd_h * 0.20),
		Vector2(w * 0.58, crowd_h * 0.20),
		Vector2(w * 0.78, crowd_h),
		Vector2(w * 0.22, crowd_h),
	])
	_canvas.draw_colored_polygon(apron, Palette.PANEL)

	# Ring floor, in perspective.
	var floor_poly := PackedVector2Array([
		Vector2(w * 0.10, crowd_h),
		Vector2(w * 0.90, crowd_h),
		Vector2(w * 1.02, h),
		Vector2(w * -0.02, h),
	])
	_canvas.draw_colored_polygon(floor_poly, Palette.RING_FLOOR)

	# Ropes across the back, then the two corner posts over them.
	for i in 3:
		var t := (float(i) + 1.0) / 4.0
		var y := crowd_h * (0.36 + 0.52 * t)
		_canvas.draw_line(Vector2(w * 0.09, y), Vector2(w * 0.91, y), Palette.RING_ROPE, 8.0)
	_canvas.draw_rect(Rect2(w * 0.06, crowd_h * 0.28, 34.0, crowd_h * 0.86), Palette.RING_ROPE)
	_canvas.draw_rect(Rect2(w * 0.91, crowd_h * 0.28, 34.0, crowd_h * 0.86), Palette.RING_POST)

	var base_y := crowd_h + (h - crowd_h) * 0.62
	_paint_fighter(Vector2(w * 0.30, base_y), _left_body, _left_accent,
		_left_pose, _left_pose_t, 1.0)
	_paint_fighter(Vector2(w * 0.70, base_y), _right_body, _right_accent,
		_right_pose, _right_pose_t, -1.0)

	if _tap_pulse > 0.0:
		var alpha := clampf(_tap_pulse / TAP_PULSE_SECONDS, 0.0, 1.0)
		var ring_color := Color(Palette.SELECTION, alpha * 0.9)
		_canvas.draw_arc(Vector2(w * 0.30, base_y - 40.0),
			120.0 + (1.0 - alpha) * 90.0, 0.0, TAU, 48, ring_color, 8.0)


func _paint_crowd(w: float, crowd_h: float) -> void:
	var cols := 12
	var rows := 3
	var step_x := w / float(cols)
	var step_y := crowd_h / float(rows + 1)
	for r in rows:
		var offset := step_x * 0.5 if r % 2 == 1 else 0.0
		for i in cols:
			var cx := step_x * (float(i) + 0.5) + offset
			var cy := step_y * (float(r) + 0.9)
			_canvas.draw_circle(Vector2(cx, cy), step_y * 0.32, Palette.CROWD)


## One fighter: shadow, body, head, gloves. `facing` is +1 when it faces right
## (the left corner) and -1 when it faces left.
func _paint_fighter(base: Vector2, body: Color, accent: Color,
		pose: Pose, pose_t: float, facing: float) -> void:
	var pos := base
	var down := pose == Pose.DOWN
	var lean := 0.0
	match pose:
		Pose.PUNCH:
			lean = 52.0 * clampf(pose_t / POSE_SECONDS, 0.0, 1.0)
		Pose.HURT:
			lean = -40.0 * clampf(pose_t / POSE_SECONDS, 0.0, 1.0)
		Pose.DODGE:
			lean = -30.0
		Pose.BLOCK:
			lean = -8.0
		_:
			lean = 0.0
	pos.x += facing * lean
	if not down:
		pos.y += sin(_time * 3.4 + (0.0 if facing > 0.0 else 1.7)) * 7.0

	# Shadow — a squashed circle via the draw transform.
	_canvas.draw_set_transform(Vector2(pos.x, base.y + 66.0), 0.0, Vector2(1.0, 0.26))
	_canvas.draw_circle(Vector2.ZERO, 78.0, Color(Palette.INK, 0.35))
	_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if down:
		# Flat on the canvas: body and head laid out sideways.
		var lie_y := base.y + 34.0
		_canvas.draw_set_transform(Vector2(pos.x, lie_y), 0.0, Vector2(1.35, 0.62))
		_canvas.draw_circle(Vector2.ZERO, 62.0, Palette.INK)
		_canvas.draw_circle(Vector2.ZERO, 55.0, body)
		_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		_canvas.draw_circle(Vector2(pos.x - facing * 78.0, lie_y - 6.0), 42.0, Palette.INK)
		_canvas.draw_circle(Vector2(pos.x - facing * 78.0, lie_y - 6.0), 35.0, accent)
		return

	var body_c := pos
	var head_c := pos + Vector2(0.0, -78.0)
	_canvas.draw_circle(body_c, 68.0, Palette.INK)
	_canvas.draw_circle(body_c, 60.0, body)
	_canvas.draw_circle(head_c, 52.0, Palette.INK)
	_canvas.draw_circle(head_c, 45.0, body)
	_canvas.draw_circle(head_c + Vector2(facing * 12.0, 6.0), 26.0, accent)

	# Gloves. A blocking monkey brings both up in front of its face.
	var glove := Palette.RING_ROPE
	if pose == Pose.BLOCK:
		_canvas.draw_circle(head_c + Vector2(facing * 34.0, 6.0), 26.0, glove)
		_canvas.draw_circle(head_c + Vector2(facing * 4.0, 34.0), 26.0, glove)
	elif pose == Pose.PUNCH:
		_canvas.draw_circle(body_c + Vector2(facing * 96.0, -34.0), 28.0, glove)
		_canvas.draw_circle(body_c + Vector2(-facing * 20.0, 6.0), 24.0, glove)
	else:
		_canvas.draw_circle(body_c + Vector2(facing * 58.0, -18.0), 26.0, glove)
		_canvas.draw_circle(body_c + Vector2(-facing * 44.0, 4.0), 26.0, glove)


## The original's wording, broken across two lines so it fits a half-width
## button. Breaking at the last space keeps the first line the longer one, which
## reads better than splitting in the middle of the phrase.
func _wrapped_corner_label(index: int) -> String:
	var label := MatchResolver.corner_label(index as MatchResolver.CornerAction)
	if label.length() <= 10 or not label.contains(" "):
		return label
	var split := label.rfind(" ")
	return "%s\n%s" % [label.substr(0, split), label.substr(split + 1)]
