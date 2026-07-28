extends Node

## AUTOLOAD: `Sfx`. Declared up front so no later agent has to edit
## project.godot to add audio.
##
## NO ASSET FILES. Anything audible here must be generated at runtime
## (AudioStreamGenerator, or simply left silent). The original's music has never
## been ripped — the dossier notes no OST, VGM/GBS rip or track listing exists
## (§10 [C]) — and we would not use it if it had.
##
## Every method is a safe no-op until someone implements it, so screens can call
## `Sfx.click()` today without a crash.

enum Cue {
	CLICK,
	CONFIRM,
	CANCEL,
	MENU_MOVE,
	FEED,
	HAPPY,       ## the monkey blushes when praised (dossier §10)
	ANGRY,       ## it bites when upset
	REP,         ## one training rep landed
	RECORD,      ## new personal best
	PUNCH,
	BLOCK,
	KNOCKDOWN,
	BELL,
	VICTORY,
	DEFEAT,
}

var muted: bool = false


func play(_cue: Cue) -> void:
	pass


func click() -> void:
	play(Cue.CLICK)


func confirm() -> void:
	play(Cue.CONFIRM)


func cancel() -> void:
	play(Cue.CANCEL)


func set_muted(value: bool) -> void:
	muted = value
