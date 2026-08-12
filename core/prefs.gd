class_name Prefs
extends RefCounted

## Player preferences that outlive a run: things the save file must NOT own,
## because deleting a save or starting a new game should not forget them.
##
## Deliberately tiny — a `ConfigFile` at `user://prefs.cfg` and nothing else. The
## save system (`core/save_game.gd`) stays the place a *run* is stored; this is
## the place the app remembers the player.

const PREFS_PATH := "user://prefs.cfg"
const SECTION := "player"


## True once the cold open has played to the end at least once. The intro is a
## first-launch beat: after that the app opens on the title, and the player gets
## a REPLAY INTRO button instead.
static func intro_seen() -> bool:
	return bool(_read().get_value(SECTION, "intro_seen", false))


static func set_intro_seen(value: bool) -> void:
	var cfg := _read()
	cfg.set_value(SECTION, "intro_seen", value)
	var err := cfg.save(PREFS_PATH)
	if err != OK:
		# Not fatal: the player sees the intro again next launch, which is a far
		# better failure than refusing to start.
		push_warning("Prefs: could not write %s (error %d)" % [PREFS_PATH, err])


## Wipes every preference. Used by the debug menu and by tests.
static func clear() -> void:
	if FileAccess.file_exists(PREFS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS_PATH))
	var cfg := ConfigFile.new()
	cfg.save(PREFS_PATH)


static func _read() -> ConfigFile:
	var cfg := ConfigFile.new()
	# A missing or corrupt file is normal on first launch — an empty ConfigFile
	# then answers every get_value with its default.
	cfg.load(PREFS_PATH)
	return cfg
