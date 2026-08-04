extends Control

## The main scene, `run/main_scene` in project.godot. Deliberately almost empty:
## it exists only to hand control to the Router autoload, which owns the screen
## stack and its own CanvasLayer. Nothing else belongs here.
##
## The one visual it owns is the backdrop that shows through in the letterbox
## bars when the device aspect is taller or wider than 1920x880 (the project is
## `canvas_items` stretch with `expand` aspect, so this is rarely visible — but
## a black flash on a notch cutout looks like a bug).

@onready var _backdrop: ColorRect = $Backdrop


func _ready() -> void:
	# Colour set here rather than baked into the .tscn so Palette stays the single
	# source of truth for every fill in the game.
	_backdrop.color = Palette.BG
	Router.reset_to(Router.Screen.SPLASH)
