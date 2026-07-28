extends GameScreen

## TRAINING — the rhythm minigame.
##
## Dossier §4 [C]: "Training is a rhythm/imitation minigame. The player
## character performs the exercise by rhythmic `A` presses and the monkey
## copies. Failure is **two-sided**: press too slowly and the monkey loses
## interest; press too fast and your character cramps."
##
## Both failure directions have to be legible on screen — a minigame that only
## punishes "too slow" is the wrong game. So the target window comes from
## `core/training.gd` (`Training.target_window()` / `Training.classify_interval`)
## and is drawn to scale as three zones: TOO FAST on the left, the window in the
## middle, TOO SLOW on the right, with a marker sweeping across since the last
## tap. Nothing here decides what a tap is worth; the counters go into a
## `RhythmScore` and `Training` does the maths.
##
## HUD follows `docs/reference/screens-kog/060.png` and §10 [C]: three boxes —
## `[0:41]` countdown, `[102]` rep counter, `[TOMATO]` name — and the rep count
## **also floats over the monkey as a large red number**.
##
## Supporting systems from §4 [C], all present:
##  * personal records (自己最高回数) — "watching the number climb is described
##    by Japanese players as the core appeal", so a record gets a fanfare;
##  * praise and scold as explicit inputs after the session;
##  * the hunger interrupt — the monkey stops mid-session, sits down and grabs
##    its stomach, and you feed it in place and it resumes.
##
## §4 also notes the original eventually lets the monkey continue with no input
## at all, which HG101 flags as a design flaw. Not reproduced: input stays
## required for the whole session.

enum Phase { BLOCKED, LEAD_IN, RUNNING, HUNGER_PAUSE, FINISHED }

## DIVERGENCE: dossier §14.10 — session length is [X]. §10 [C] does attest the
## countdown box reading `[0:41]` and a rep counter reading `[102]`, so the real
## sessions run at least a minute. 45s is chosen so the countdown passes through
## the attested `0:41` while keeping a phone session short enough to repeat
## twice a day without tedium.
const SESSION_SECONDS := 45.0
## Beats of lead-in before the clock starts, so the player can find the tempo.
const LEAD_IN_SECONDS := 3.0
## How much time the rhythm track spans, as a multiple of the beat. Anything
## slower than this is off the right-hand end and already a "lost interest".
const TRACK_SPAN_BEATS := 1.9
## DIVERGENCE: [X]. Where in the session the hunger interrupt fires when the
## monkey started out hungry. Dossier §4 [C] confirms the interrupt exists and
## that feeding in place resumes the session, but not its timing.
const HUNGER_INTERRUPT_AT := 0.55
## Foods offered in the interrupt panel, most-stocked first. Enough to act, not
## a shop screen.
const INTERRUPT_FOOD_SLOTS := 4

@onready var _bg: ColorRect = $Bg
@onready var _hud: HudBoxes = $Root/Col/Hud
@onready var _stage: Control = $Root/Col/Stage
@onready var _monkey_rig: Control = $Root/Col/Stage/MonkeyRig
@onready var _rep_float: Label = $Root/Col/Stage/RepFloat
@onready var _record_banner: Label = $Root/Col/Stage/RecordBanner
@onready var _track: Control = $Root/Col/Rhythm/Track
@onready var _early_zone: ColorRect = $Root/Col/Rhythm/Track/EarlyZone
@onready var _band: ColorRect = $Root/Col/Rhythm/Track/Band
@onready var _late_zone: ColorRect = $Root/Col/Rhythm/Track/LateZone
@onready var _marker: ColorRect = $Root/Col/Rhythm/Track/Marker
@onready var _legend_early: Label = $Root/Col/Rhythm/Legend/Early
@onready var _legend_band: Label = $Root/Col/Rhythm/Legend/Band
@onready var _legend_late: Label = $Root/Col/Rhythm/Legend/Late
@onready var _verdict: Label = $Root/Col/Rhythm/Verdict
@onready var _tally: Label = $Root/Col/Rhythm/Tally
@onready var _message_panel: PanelContainer = $Root/Col/MessageBox
@onready var _message: Label = $Root/Col/MessageBox/Text
@onready var _tap_button: Button = $Root/Col/TapButton

@onready var _lead_overlay: Control = $LeadOverlay
@onready var _lead_label: Label = $LeadOverlay/Text
@onready var _blocked_overlay: Control = $BlockedOverlay
@onready var _blocked_label: Label = $BlockedOverlay/Box/Text
@onready var _blocked_back: Button = $BlockedOverlay/Box/Back
@onready var _hunger_overlay: Control = $HungerOverlay
@onready var _hunger_label: Label = $HungerOverlay/Box/Text
@onready var _hunger_foods: VBoxContainer = $HungerOverlay/Box/Foods
@onready var _hunger_skip: Button = $HungerOverlay/Box/Skip
@onready var _result_overlay: Control = $ResultOverlay
@onready var _result_title: Label = $ResultOverlay/Box/Title
@onready var _result_reps: Label = $ResultOverlay/Box/Reps
@onready var _result_beat: Label = $ResultOverlay/Box/Beat
@onready var _result_gain: Label = $ResultOverlay/Box/Gain
@onready var _result_message: Label = $ResultOverlay/Box/Message
@onready var _praise_button: Button = $ResultOverlay/Box/Buttons/Praise
@onready var _scold_button: Button = $ResultOverlay/Box/Buttons/Scold
@onready var _done_button: Button = $ResultOverlay/Box/Buttons/Done

var _activity: Training.Activity = Training.Activity.PUNCHBAG
var _phase: Phase = Phase.LEAD_IN

var _elapsed := 0.0
var _lead_left := LEAD_IN_SECONDS
var _last_tap := 0.0
var _reps := 0
var _perfect := 0
var _early := 0
var _late := 0
var _interrupted := false
## Kept so this screen can switch to `RhythmScore.from_taps` the moment that
## static is implemented (it is still a stub in core/rhythm_score.gd).
var _tap_times: PackedFloat32Array = PackedFloat32Array()

var _hunger_pending := false
var _hunger_fired := false
var _judged := false


func _ready() -> void:
	super()
	_apply_palette()
	_tap_button.pressed.connect(_on_tap_pressed)
	_tap_button.focus_mode = Control.FOCUS_NONE
	_blocked_back.pressed.connect(func() -> void: close({}))
	_hunger_skip.pressed.connect(_on_hunger_skipped)
	_praise_button.pressed.connect(_on_praise)
	_scold_button.pressed.connect(_on_scold)
	_done_button.pressed.connect(_on_done)
	_track.resized.connect(_layout_track)
	for overlay in [_lead_overlay, _blocked_overlay, _hunger_overlay, _result_overlay]:
		overlay.visible = false
	set_process(true)


func on_enter(params: Dictionary) -> void:
	super(params)
	_activity = int(params.get("activity", Training.Activity.PUNCHBAG)) as Training.Activity
	# The Router calls on_enter straight after add_child. That is normally after
	# _ready, but a host that adds the screen before its own tree is running can
	# get here first, and every @onready below would still be null.
	if is_node_ready():
		_begin()
	else:
		ready.connect(_begin, CONNECT_ONE_SHOT)


# --- setup -------------------------------------------------------------------

func _begin() -> void:
	var monkey := GameState.monkey()
	_stage_colours()
	_layout_track()
	_hud.show_training(SESSION_SECONDS, 0, monkey.monkey_name if monkey != null else "---")
	_rep_float.text = "0"
	_record_banner.visible = false
	_tally.text = ""
	_verdict.text = ""

	# Gate first. Dossier §5 [C]: an unbefriended monkey bites and will not
	# train; both hunger extremes immobilise. Care owns the wording.
	var reason := GameState.block_reason()
	if monkey == null or not reason.is_empty():
		_phase = Phase.BLOCKED
		_blocked_label.text = reason if monkey != null else "THERE IS NO MONKEY."
		_blocked_overlay.visible = true
		_tap_button.disabled = true
		return

	# §4 [C]: the monkey stops mid-session, sits down and grabs its stomach. It
	# only does that when it started the session already hungry.
	_hunger_pending = monkey.fullness <= Care.FULLNESS_HUNGRY_MAX
	_hunger_fired = false

	_message.text = "IT'S IN TRAINING."
	_phase = Phase.LEAD_IN
	_lead_left = LEAD_IN_SECONDS
	_lead_overlay.visible = true
	_lead_label.text = "%d" % int(ceilf(_lead_left))


func _apply_palette() -> void:
	_bg.color = Palette.BG
	_message.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_message.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_message_panel.add_theme_stylebox_override("panel", _dark_box())

	# The floating rep number: the original prints it over the monkey in large
	# red (dossier §10 [C], docs/reference/screens-kog/060.png).
	_rep_float.add_theme_color_override("font_color", Palette.GAUGE_LOSS)
	_rep_float.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_record_banner.add_theme_color_override("font_color", Palette.SELECTION)
	_record_banner.add_theme_font_size_override("font_size", Palette.FONT_TITLE)

	_early_zone.color = Palette.BAD.darkened(0.35)
	_band.color = Palette.GOOD
	_late_zone.color = Palette.WARN.darkened(0.45)
	_marker.color = Palette.INK_LIGHT
	_legend_early.add_theme_color_override("font_color", Palette.BAD)
	_legend_band.add_theme_color_override("font_color", Palette.GOOD)
	_legend_late.add_theme_color_override("font_color", Palette.WARN)
	for label in [_legend_early, _legend_band, _legend_late, _tally]:
		label.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_verdict.add_theme_font_size_override("font_size", Palette.FONT_BODY)

	for overlay_bg in [_lead_overlay, _blocked_overlay, _hunger_overlay, _result_overlay]:
		var shade := overlay_bg.get_node_or_null("Shade") as ColorRect
		if shade != null:
			shade.color = Color(Palette.BG.r, Palette.BG.g, Palette.BG.b, 0.88)
	_lead_label.add_theme_color_override("font_color", Palette.SELECTION)
	_lead_label.add_theme_font_size_override("font_size", 220)


## Location colour per activity. Dossier §10 [C] lists the rooms: the gym has
## the punchbag, running is the city park, sit-ups happen in the pink-walled
## sit-ups room, and skipping is done out on the shopping street (§10 notes the
## HUD hides for "street skipping").
func _stage_colours() -> void:
	var backdrop := Palette.LOC_GYM
	match _activity:
		Training.Activity.PUNCHBAG:
			backdrop = Palette.LOC_GYM
		Training.Activity.SKIPPING:
			backdrop = Palette.LOC_STREET
		Training.Activity.SIT_UPS:
			backdrop = Palette.LOC_SITUPS
		Training.Activity.RUNNING:
			backdrop = Palette.LOC_PARK
		_:
			backdrop = Palette.LOC_HOME
	_paint(_stage, "Backdrop", backdrop)
	_paint(_stage, "Ground", backdrop.darkened(0.35))
	_paint(_stage, "GroundLine", backdrop.darkened(0.55))
	_paint(_stage, "Apparatus", Palette.ACCENT)
	_paint(_stage, "TrainerRig/Legs", Palette.PANEL_DARK)
	_paint(_stage, "TrainerRig/Body", Palette.ACCENT_ALT)
	_paint(_stage, "TrainerRig/Head", Palette.PAPER)
	_paint(_stage, "TrainerRig/Hair", Palette.INK)

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


func _dark_box() -> StyleBoxFlat:
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


# --- the rhythm track --------------------------------------------------------

## Draw the window to scale from core's own numbers, so what the player aims at
## is literally what `Training.classify_interval` will accept.
func _layout_track() -> void:
	if not is_node_ready():
		return
	var window: Dictionary = Training.target_window()
	var span: float = float(window["beat_interval"]) * TRACK_SPAN_BEATS
	var width := _track.size.x
	var height := _track.size.y
	if width <= 0.0 or span <= 0.0:
		return
	var low := clampf(float(window["min_interval"]) / span, 0.0, 1.0) * width
	var high := clampf(float(window["max_interval"]) / span, 0.0, 1.0) * width

	_early_zone.position = Vector2.ZERO
	_early_zone.size = Vector2(low, height)
	_band.position = Vector2(low, 0.0)
	_band.size = Vector2(maxf(8.0, high - low), height)
	_late_zone.position = Vector2(high, 0.0)
	_late_zone.size = Vector2(maxf(0.0, width - high), height)
	_marker.size = Vector2(12.0, height)
	_update_marker()


func _update_marker() -> void:
	var window: Dictionary = Training.target_window()
	var span: float = float(window["beat_interval"]) * TRACK_SPAN_BEATS
	var since := _elapsed - _last_tap if _phase == Phase.RUNNING else 0.0
	var width := _track.size.x
	var x := clampf(since / span, 0.0, 1.0) * (width - _marker.size.x)
	_marker.position = Vector2(x, 0.0)


# --- the session -------------------------------------------------------------

func _process(delta: float) -> void:
	match _phase:
		Phase.LEAD_IN:
			_lead_left -= delta
			if _lead_left <= 0.0:
				_start_session()
			else:
				_lead_label.text = "%d" % maxi(1, int(ceilf(_lead_left)))
		Phase.RUNNING:
			_tick(delta)
		_:
			pass


func _start_session() -> void:
	_lead_overlay.visible = false
	_phase = Phase.RUNNING
	_elapsed = 0.0
	_last_tap = 0.0
	_verdict.text = "GO!"
	_verdict.add_theme_color_override("font_color", Palette.SELECTION)


func _tick(delta: float) -> void:
	_elapsed += delta
	var remaining := SESSION_SECONDS - _elapsed
	_hud.set_countdown(remaining)
	_update_marker()

	# Idling is a failure, not a pause. Dossier §4 [C]: press too slowly and the
	# monkey loses interest.
	var window: Dictionary = Training.target_window()
	if _elapsed - _last_tap > float(window["max_interval"]):
		_last_tap = _elapsed
		_late += 1
		_show_verdict(Training.TapVerdict.LATE_BORED)
		_update_tally()

	if _hunger_pending and not _hunger_fired \
			and _elapsed >= SESSION_SECONDS * HUNGER_INTERRUPT_AT:
		_fire_hunger_interrupt()
		return

	if remaining <= 0.0:
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if _phase != Phase.RUNNING:
		return
	if event.is_action_pressed("mp_tap"):
		_register_tap()
		get_viewport().set_input_as_handled()


func _on_tap_pressed() -> void:
	if _phase != Phase.RUNNING:
		return
	_register_tap()


## One tap. The interval since the previous tap is classified by CORE — this
## screen never decides what "too fast" means.
func _register_tap() -> void:
	var interval := _elapsed - _last_tap
	_last_tap = _elapsed
	_tap_times.append(_elapsed)
	var verdict := Training.classify_interval(interval)
	match verdict:
		Training.TapVerdict.IN_WINDOW:
			_perfect += 1
			_reps += 1
			_on_rep()
		Training.TapVerdict.EARLY_CRAMP:
			# The TRAINER cramps — the rep does not land.
			_early += 1
		Training.TapVerdict.LATE_BORED:
			_late += 1
	_show_verdict(verdict)
	_update_tally()
	_update_marker()


func _on_rep() -> void:
	Sfx.play(Sfx.Cue.REP)
	_hud.set_reps(_reps)
	_rep_float.text = str(_reps)
	_rep_float.pivot_offset = _rep_float.size * 0.5
	var punch := create_tween()
	punch.tween_property(_rep_float, "scale", Vector2(1.35, 1.35), 0.06)
	punch.tween_property(_rep_float, "scale", Vector2.ONE, 0.14)
	var rest := _monkey_rig.position
	var hop := create_tween()
	hop.tween_property(_monkey_rig, "position", rest + Vector2(0.0, -22.0), 0.08)
	hop.tween_property(_monkey_rig, "position", rest, 0.16)


func _show_verdict(verdict: Training.TapVerdict) -> void:
	# Both failure directions are named, in the player's words, every time.
	match verdict:
		Training.TapVerdict.IN_WINDOW:
			_verdict.text = "GOOD!"
			_verdict.add_theme_color_override("font_color", Palette.GOOD)
		Training.TapVerdict.EARLY_CRAMP:
			_verdict.text = "TOO FAST - YOU CRAMPED!"
			_verdict.add_theme_color_override("font_color", Palette.BAD)
		Training.TapVerdict.LATE_BORED:
			_verdict.text = "TOO SLOW - IT LOST INTEREST!"
			_verdict.add_theme_color_override("font_color", Palette.WARN)


func _update_tally() -> void:
	_tally.text = "ON THE BEAT %d   TOO FAST %d   TOO SLOW %d" % [_perfect, _early, _late]


# --- the hunger interrupt ----------------------------------------------------

## Dossier §4 [C]: "The monkey stops mid-session, sits down and grabs its
## stomach; you feed it in place and it resumes." Feeding is free and costs no
## slot (§2 [C]), so this is a genuine rescue, not a second cost.
func _fire_hunger_interrupt() -> void:
	_hunger_fired = true
	_phase = Phase.HUNGER_PAUSE
	var monkey := GameState.monkey()
	var who := monkey.monkey_name.to_upper() if monkey != null else "IT"
	_hunger_label.text = "%s SITS DOWN AND HOLDS ITS STOMACH." % who
	_build_food_buttons()
	_hunger_overlay.visible = true


func _build_food_buttons() -> void:
	for child in _hunger_foods.get_children():
		_hunger_foods.remove_child(child)
		child.queue_free()
	var inventory := GameState.inventory()
	var ids := inventory.keys()
	ids.sort()
	var shown := 0
	for key in ids:
		if shown >= INTERRUPT_FOOD_SLOTS:
			break
		var id := String(key)
		var count := int(inventory[key])
		if count <= 0:
			continue
		var food := FoodDb.get_food(id)
		if food == null:
			continue
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, Palette.TOUCH_MIN)
		button.focus_mode = Control.FOCUS_NONE
		button.text = "%s x%d" % [food.display_name.to_upper(), count]
		button.pressed.connect(func() -> void: _feed_in_place(id))
		_hunger_foods.add_child(button)
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = "NOTHING TO FEED IT."
		_hunger_foods.add_child(empty)


func _feed_in_place(food_id: String) -> void:
	var result := GameState.feed(food_id)
	if result != null:
		_message.text = result.message
	# Feeding can itself immobilise the monkey — overfeeding paralyses, and that
	# is FAITHFUL (§5 [C]). If it did, the session cannot go on.
	var reason := GameState.block_reason()
	if not reason.is_empty():
		_message.text = reason
		_interrupted = true
		_hunger_overlay.visible = false
		_finish()
		return
	_hunger_overlay.visible = false
	_phase = Phase.RUNNING
	_last_tap = _elapsed


func _on_hunger_skipped() -> void:
	_interrupted = true
	_hunger_overlay.visible = false
	_finish()


# --- finishing ---------------------------------------------------------------

func _finish() -> void:
	if _judged:
		return
	_judged = true
	_phase = Phase.FINISHED
	_hud.set_countdown(0.0)
	_tap_button.disabled = true

	# The one thing core accepts from this scene. It computes the gain; this
	# screen only reports what happened.
	var score := RhythmScore.new()
	score.reps = _reps
	score.perfect = _perfect
	score.early = _early
	score.late = _late
	score.duration_s = _elapsed
	score.interrupted = _interrupted

	var result := GameState.do_training(int(_activity), score)
	_show_result(result)


func _show_result(result: Training.Result) -> void:
	var monkey := GameState.monkey()
	_result_overlay.visible = true

	if result == null:
		_result_title.text = "NO SESSION"
		_result_reps.text = ""
		_result_beat.text = ""
		_result_gain.text = ""
		_result_message.text = GameState.block_reason()
		_praise_button.disabled = true
		_scold_button.disabled = true
		return

	_result_title.text = Training.display_name(_activity)

	var best := 0
	if monkey != null:
		best = int(monkey.personal_bests.get(int(_activity), 0))
	_result_reps.text = "REPS %d      BEST %d" % [result.reps, best]
	_result_beat.text = "ON THE BEAT %d   TOO FAST %d   TOO SLOW %d" % [_perfect, _early, _late]

	# Dossier §3 [C]: a capped stat shows a star and training cannot pass it —
	# only breeding raises the ceiling. Say so rather than showing a silent +0.
	var stat_label := Monkey.stat_label(result.stat)
	if result.gain_applied > 0:
		_result_gain.text = "%s +%d%s" % [
			stat_label, result.gain_applied, "  (CAPPED)" if result.was_capped else ""]
		_result_gain.add_theme_color_override(
			"font_color", Palette.STAT_CAPPED if result.was_capped else Palette.GOOD)
	elif result.was_capped:
		_result_gain.text = "%s IS STARRED. ONLY BREEDING RAISES IT." % stat_label
		_result_gain.add_theme_color_override("font_color", Palette.STAT_CAPPED)
	else:
		_result_gain.text = "%s +0" % stat_label
		_result_gain.add_theme_color_override("font_color", Palette.DISABLED)

	_result_message.text = result.message

	# §4 [C]: the personal record is the thing Japanese players describe as the
	# core appeal. Celebrate it.
	if result.new_personal_best:
		Sfx.play(Sfx.Cue.RECORD)
		_celebrate_record(result.reps)

	# §4 [C]: praise after a record, scold when it chatters and loses focus.
	var accuracy := 0.0
	var taps := _perfect + _early + _late
	if taps > 0:
		accuracy = float(_perfect) / float(taps)
	_praise_button.disabled = false
	_scold_button.disabled = false
	if result.new_personal_best or accuracy >= Training.GOOD_SESSION_ACCURACY:
		_praise_button.text = "PRAISE IT *"
	elif accuracy < Training.POOR_SESSION_ACCURACY:
		_scold_button.text = "SCOLD IT *"


func _celebrate_record(reps: int) -> void:
	_record_banner.text = "NEW RECORD!  %d" % reps
	_record_banner.visible = true
	_record_banner.pivot_offset = _record_banner.size * 0.5
	var flourish := create_tween()
	flourish.tween_property(_record_banner, "scale", Vector2(1.2, 1.2), 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	flourish.tween_property(_record_banner, "scale", Vector2.ONE, 0.22)


func _on_praise() -> void:
	GameState.praise()
	Sfx.play(Sfx.Cue.HAPPY)
	_praise_button.disabled = true
	_scold_button.disabled = true
	_result_message.text = "IT BLUSHES."


func _on_scold() -> void:
	GameState.scold()
	Sfx.play(Sfx.Cue.ANGRY)
	_praise_button.disabled = true
	_scold_button.disabled = true
	_result_message.text = "IT SULKS."


func _on_done() -> void:
	Sfx.confirm()
	close({"message": _result_message.text})
