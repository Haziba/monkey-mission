extends GameScreen

## Shown by the Router when a screen's scene does not exist yet, so that
## parallel agents never crash each other's builds with a missing dependency.
## Delete nothing here — just add your real scene at the path the Router
## expects and this stops appearing.

@onready var _label: Label = $Margin/Box/Label
@onready var _back: Button = $Margin/Box/Back


func _ready() -> void:
	super()
	var bg := ColorRect.new()
	bg.color = Palette.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)


func on_enter(params: Dictionary) -> void:
	super(params)
	var screen_id: int = int(get_meta("router_screen", -1))
	var expected: String = String(Router.SCENE_PATHS.get(screen_id, "?"))
	_label.text = "NOT BUILT YET\n\nRouter.Screen #%d\n%s\n\nparams: %s" % [
		screen_id, expected, params,
	]
	_back.pressed.connect(func() -> void: Router.pop())
	_back.visible = Router.depth() > 1
