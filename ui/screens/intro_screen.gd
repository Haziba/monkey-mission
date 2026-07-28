extends GameScreen

## The prologue. Two phases:
##   1. Pick the protagonist — Kenta or Sumire.
##   2. Play `core/data/intro_script.gd` through the reusable DialogueBox.
##
## Dossier §11 [C]: you play whichever sibling was NOT taken by the Saru Group,
## so the pick is framed as "which of you did they leave behind". §14 corrects a
## claim that circulates about this game: the male/female choice is the TRAINER,
## not the monkey — the labels here say so out loud.
##
## The screen holds no story rules. Text, speakers and beats all come from
## IntroScript; the only thing this file decides is portrait tinting (a UI
## concern, so core never learns Palette exists) and where to go next.
##
## Exit: `Router.replace(MONKEY_SELECT)`, handing the chosen protagonist along.
## The run itself is created by the monkey-select screen, once there is a species
## to create it with.

@onready var _bg: ColorRect = $Bg
@onready var _choose: Control = $Choose
@onready var _title: Label = $Choose/Margin/Box/Title
@onready var _sub: Label = $Choose/Margin/Box/Sub
@onready var _footnote: Label = $Choose/Margin/Box/Footnote
@onready var _kenta: Button = $Choose/Margin/Box/KentaCard
@onready var _sumire: Button = $Choose/Margin/Box/SumireCard
@onready var _dialogue: DialogueBox = $Dialogue
@onready var _skip: Button = $Skip

var _protagonist: int = RunState.Protagonist.KENTA
## True when the title screen routed here with `new_game: true`. The title seeds
## a run with its default protagonist and expects the intro to re-create it once
## the player has actually picked a sibling (`GameState.new_run` is idempotent).
var _new_game: bool = false
## Array[IntroScript.Line] — kept so `line_shown` can fire the per-line Sfx cue.
var _script_lines: Array = []


func _ready() -> void:
	super()
	_bg.color = Palette.BG
	_title.text = "MONKEY PUNCHER"
	_sub.text = "Which of you did they leave behind?"
	_footnote.text = "You play the sibling the Saru Group did not take. This is the trainer, not the monkey."
	for label in [_title, _sub, _footnote]:
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)
	_title.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_sub.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_footnote.add_theme_font_size_override("font_size", Palette.FONT_SMALL)
	_footnote.add_theme_color_override("font_color", Palette.PAPER_EDGE)

	_dress_card(_kenta, RunState.Protagonist.KENTA)
	_dress_card(_sumire, RunState.Protagonist.SUMIRE)
	_kenta.pressed.connect(_on_protagonist_chosen.bind(RunState.Protagonist.KENTA))
	_sumire.pressed.connect(_on_protagonist_chosen.bind(RunState.Protagonist.SUMIRE))

	_skip.text = "SKIP  ▶"
	_skip.pressed.connect(_on_skip_pressed)
	_skip.visible = false

	_dialogue.visible = false
	_dialogue.line_shown.connect(_on_line_shown)
	_dialogue.finished.connect(_on_dialogue_finished)


func on_enter(params: Dictionary) -> void:
	super(params)
	_new_game = bool(params.get("new_game", false))
	var chosen: int = int(params.get("protagonist", -1))
	if _new_game:
		# The protagonist the title passed is only the seed value it used for
		# GameState.new_run(); the actual choice is made here.
		_protagonist = maxi(chosen, 0)
		_choose.visible = true
		return
	# Resuming an unfinished intro: the run already knows who the player is, so
	# don't ask twice.
	if chosen < 0 and GameState.has_run() and GameState.run != null:
		chosen = int(GameState.run.protagonist)
	if chosen >= 0:
		_begin_dialogue(chosen)
	else:
		_choose.visible = true


func _dress_card(card: Button, protagonist: int) -> void:
	var swatch: ColorRect = card.get_node("Body/Row/Swatch")
	var name_label: Label = card.get_node("Body/Row/Text/Name")
	var blurb: Label = card.get_node("Body/Row/Text/Blurb")
	swatch.color = DialogueBox.protagonist_color(protagonist)
	name_label.text = IntroScript.protagonist_name(protagonist)
	blurb.text = "They took your %s, %s — and your father with them." % [
		IntroScript.sibling_relation(protagonist),
		IntroScript.sibling_name(protagonist).capitalize(),
	]
	name_label.add_theme_color_override("font_color", Palette.INK)
	name_label.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	blurb.add_theme_color_override("font_color", Palette.INK)
	blurb.add_theme_font_size_override("font_size", Palette.FONT_SMALL)


func _on_protagonist_chosen(protagonist: int) -> void:
	Sfx.confirm()
	_rebuild_run_for(protagonist)
	_begin_dialogue(protagonist)


## The title screen seeds a run with its default sibling before routing here, so
## the run on disk has to be rebuilt if the player picked the other one.
## `GameState.new_run` is idempotent — it replaces the whole RunState.
func _rebuild_run_for(protagonist: int) -> void:
	if not _new_game:
		return
	if GameState.has_run() and GameState.run != null \
			and int(GameState.run.protagonist) == protagonist:
		return
	GameState.new_run(protagonist)
	if GameState.has_run():
		GameState.save_run()


func _begin_dialogue(protagonist: int) -> void:
	_protagonist = protagonist
	_choose.visible = false
	_dialogue.visible = true
	_skip.visible = true
	_script_lines = IntroScript.lines(_protagonist)
	var queued: Array = []
	for line in _script_lines:
		queued.append(DialogueBox.make_line(
			line.speaker_name,
			line.text,
			DialogueBox.speaker_color(int(line.speaker), _protagonist),
			_monogram_for(line)))
	_dialogue.play(queued)


## The portrait plate's big placeholder glyph. Narration has no speaker, so it
## gets the ellipsis the original uses for scene-setting boxes.
func _monogram_for(line) -> String:
	if line.is_narration():
		return "..."
	if line.speaker_name == "???":
		return "?"
	return line.speaker_name.substr(0, 1)


func _on_line_shown(index: int) -> void:
	if index < 0 or index >= _script_lines.size():
		return
	if String(_script_lines[index].cue) == IntroScript.CUE_DOORBELL:
		# Dossier §11 [C]: story beats are doorbell-triggered.
		Sfx.play(Sfx.Cue.BELL)


func _on_skip_pressed() -> void:
	Sfx.cancel()
	_go_to_monkey_select()


func _on_dialogue_finished() -> void:
	_go_to_monkey_select()


func _go_to_monkey_select() -> void:
	if GameState.has_run() and GameState.run != null:
		GameState.run.set_flag("seen_intro")
	Router.replace(Router.Screen.MONKEY_SELECT, {"protagonist": _protagonist})
