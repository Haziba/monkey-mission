class_name SaveGame
extends RefCounted

## Serialise and restore a whole run to `user://`.
##
## Dossier §14.15: the original's save-system specifics (SRAM size, mapper, ROM
## header) are [X] and irrelevant here — this is a JSON file, not a cartridge
## emulation. The only faithful requirement is that it is a SINGLE continuous
## save: dossier §7 phase 6 [C] notes the post-game continues on the same save,
## and there is no New Game+.
##
## Everything goes through RunState so core never touches the GameState
## autoload. All enum values serialise as ints; all Dictionary keys that are
## enums must be written as their int value and read back with int().
##
## Robustness contract: `load_run()`, `restore()` and `peek()` must never crash
## on a missing, truncated, non-JSON, wrong-version or structurally wrong file.
## They return null / {"exists": false} instead.

const SAVE_PATH := "user://monkey_puncher_mk2.save"
## Scratch file for the write-then-rename dance in `save()`. Never read from,
## and safe to find lying around: a leftover one only means a previous write was
## killed partway, and the next save overwrites it.
const TEMP_PATH := "user://monkey_puncher_mk2.save.tmp"
const SAVE_VERSION := 1


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Write `state` to SAVE_PATH. Returns false on any I/O or encoding failure.
static func save(state: RunState) -> bool:
	if state == null:
		return false
	var data := serialise(state)
	if data.is_empty():
		return false
	# Write to a scratch file and rename it over the real one, rather than opening
	# SAVE_PATH directly.
	#
	# Opening for WRITE truncates immediately, so the old save is destroyed before
	# the new bytes land. Lose power, get force-quit, or — the realistic one on a
	# phone — get killed by the OS while backgrounded, and the window between
	# truncate and write leaves a half-written file. The player does not lose the
	# last few minutes, they lose the whole run.
	#
	# Rename is atomic on every platform we target, so SAVE_PATH only ever holds
	# a complete file: either the previous save or the new one, never a mixture.
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveGame.save could not open %s (error %d)" % [
			TEMP_PATH, FileAccess.get_open_error()])
		return false
	file.store_string(JSON.stringify(data))
	# Push the bytes out before the rename — a rename that beats its own contents
	# to disk would defeat the point of doing this at all.
	file.flush()
	file.close()

	# Globalised, matching `delete_save()` — DirAccess's absolute helpers want a
	# real filesystem path, not a `user://` one.
	var temp_absolute := ProjectSettings.globalize_path(TEMP_PATH)
	var save_absolute := ProjectSettings.globalize_path(SAVE_PATH)
	var renamed := DirAccess.rename_absolute(temp_absolute, save_absolute)
	if renamed != OK:
		# Some filesystems refuse to rename onto an existing file. Removing the
		# target first reopens the very window this method exists to close, so it
		# is a fallback rather than the normal path.
		if FileAccess.file_exists(SAVE_PATH):
			DirAccess.remove_absolute(save_absolute)
			renamed = DirAccess.rename_absolute(temp_absolute, save_absolute)
	if renamed != OK:
		push_error("SaveGame.save could not move %s onto %s (error %d)" % [
			TEMP_PATH, SAVE_PATH, renamed])
		# Leave the scratch file: it holds a complete save, and a human can
		# recover it. The next successful save overwrites it.
		return false
	return true


## Read SAVE_PATH and return a fresh RunState, or null when absent/corrupt.
static func load_run() -> RunState:
	if not has_save():
		return null
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("SaveGame.load_run could not open %s" % SAVE_PATH)
		return null
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveGame.load_run: save file is not a JSON object — treating as corrupt")
		return null
	return restore(parsed as Dictionary)


static func delete_save() -> bool:
	# Clear the scratch file too, or a killed write leaves one behind that
	# outlives the save it was meant to become.
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	if not has_save():
		return false
	var absolute := ProjectSettings.globalize_path(SAVE_PATH)
	return DirAccess.remove_absolute(absolute) == OK


## Round-trippable plain-Variant snapshot. Kept public and pure so tests can
## assert `restore(serialise(a))` equals `a` without touching the filesystem.
static func serialise(state: RunState) -> Dictionary:
	if state == null:
		return {}
	var rules: GameRules = state.rules if state.rules != null else GameRules.load_default()
	var out := {
		"version": SAVE_VERSION,
		"protagonist": int(state.protagonist),
		"phase": int(state.phase),
		"rules": rules.to_dict(),
		# Written as decimal strings on purpose: JSON numbers are doubles, and a
		# 64-bit RNG state silently loses its low bits through one. Losing them
		# would break the "a reloaded run continues the same stream" guarantee.
		"rng_seed": str(state.rng.seed_value()) if state.rng != null else "0",
		"rng_state": str(state.rng.state()) if state.rng != null else "0",
		"active_monkey": _monkey_to_dict(state.active_monkey),
		"roster": [],
		"day_cycle": _day_cycle_to_dict(state.day_cycle),
		"economy": state.economy.to_dict() if state.economy != null else {},
		"ladder": _ladder_to_dict(state.ladder),
		"booked_opponent": _opponent_to_dict(state.booked_opponent),
		"flags": state.flags.duplicate(),
		"play_seconds": state.play_seconds,
	}
	var roster: Array = []
	for parent in state.roster:
		var entry := _monkey_to_dict(parent)
		if not entry.is_empty():
			roster.append(entry)
	out["roster"] = roster
	return out


static func restore(data: Dictionary) -> RunState:
	if data == null or data.is_empty():
		return null
	if int(data.get("version", 0)) != SAVE_VERSION:
		push_warning("SaveGame.restore: unsupported save version %s" % str(data.get("version", null)))
		return null

	var state := RunState.new()
	state.protagonist = int(data.get("protagonist", RunState.Protagonist.KENTA)) as RunState.Protagonist
	state.phase = int(data.get("phase", RunState.Phase.INTRO)) as RunState.Phase

	state.rules = GameRules.new()
	state.rules.apply_dict(_sub_dict(data, "rules"))

	# Restoring both the seed and the stream position means a reloaded run
	# continues the exact same random sequence it would have done.
	var seed_value := _big_int(data.get("rng_seed", 0))
	state.rng = MpRng.new(seed_value if seed_value != 0 else 1)
	state.rng.set_state(_big_int(data.get("rng_state", 0)))

	state.economy = Economy.new(state.rules)
	state.economy.apply_dict(_sub_dict(data, "economy"))

	state.day_cycle = DayCycle.new()
	_day_cycle_apply(state.day_cycle, _sub_dict(data, "day_cycle"))

	state.ladder = Ladder.new(state.rules, state.rng)
	_ladder_apply(state.ladder, _sub_dict(data, "ladder"))

	state.care = Care.new(state.rules, state.rng)
	state.training = Training.new(state.rules, state.rng)
	state.breeding = Breeding.new(state.rules, state.rng)

	state.active_monkey = _monkey_from_dict(_sub_dict(data, "active_monkey"))

	var roster: Array[Monkey] = []
	var raw_roster: Variant = data.get("roster", [])
	if typeof(raw_roster) == TYPE_ARRAY:
		for entry in (raw_roster as Array):
			if typeof(entry) != TYPE_DICTIONARY:
				continue
			var parent := _monkey_from_dict(entry as Dictionary)
			if parent != null:
				roster.append(parent)
	state.roster = roster

	state.booked_opponent = _opponent_from_dict(_sub_dict(data, "booked_opponent"))

	var flags: Variant = data.get("flags", {})
	state.flags = (flags as Dictionary).duplicate() if typeof(flags) == TYPE_DICTIONARY else {}
	state.play_seconds = float(data.get("play_seconds", 0.0))
	return state


## Enough to draw a "continue" button without loading the whole run:
## { "exists": bool, "day": int, "monkey_name": String, "rank": int,
##   "generation": int, "version": int }
static func peek() -> Dictionary:
	var absent := {"exists": false}
	if not has_save():
		return absent
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return absent
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return absent
	var data := parsed as Dictionary
	var monkey := _sub_dict(data, "active_monkey")
	return {
		"exists": true,
		"day": int(_sub_dict(data, "day_cycle").get("day", 1)),
		"monkey_name": String(monkey.get("monkey_name", "")),
		"rank": int(_sub_dict(data, "ladder").get("rank", Ladder.BOTTOM_RANK)),
		"generation": int(monkey.get("generation", 1)),
		"version": int(data.get("version", 0)),
	}


# --- internals -------------------------------------------------------------
#
# Each helper below prefers the owning class's own to_dict/apply_dict — that is
# the layering the contract asks for. The fallback branches exist because these
# systems are written in parallel: an unimplemented stub returns {} rather than
# the real snapshot, and a save file that silently loses the day counter is a
# far worse failure than a little redundancy here. Each fallback only ever
# touches public fields, and the fallback pair (write + read) is self-consistent.

## Read a 64-bit integer that was written as a decimal string, tolerating a
## plain number for robustness against a hand-edited file.
static func _big_int(value: Variant) -> int:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return String(value).to_int()
		TYPE_INT, TYPE_FLOAT:
			return int(value)
		_:
			return 0


static func _sub_dict(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, null)
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


static func _monkey_to_dict(monkey: Monkey) -> Dictionary:
	if monkey == null:
		return {}
	var d := monkey.to_dict()
	if not d.is_empty():
		return d
	return {
		"monkey_name": monkey.monkey_name,
		"species_type": int(monkey.species_type),
		"sex": int(monkey.sex),
		"generation": monkey.generation,
		"stats": monkey.stats.duplicate(),
		"caps": monkey.caps.duplicate(),
		"friendship": monkey.friendship,
		"fullness": monkey.fullness,
		"current_strength": monkey.current_strength,
		"current_stamina": monkey.current_stamina,
		"paralysed_slots": monkey.paralysed_slots,
		"retired": monkey.retired,
		"wins": monkey.wins,
		"losses": monkey.losses,
		"personal_bests": monkey.personal_bests.duplicate(),
		"days_since_match": monkey.days_since_match,
	}


static func _monkey_from_dict(d: Dictionary) -> Monkey:
	if d.is_empty():
		return null
	# JSON stringifies every dictionary key, so the enum-keyed sub-dictionaries
	# come back as {"0": 145}. ARCHITECTURE.md §15 requires them to be read back
	# through int(); do it here so Monkey.from_dict sees the same int keys it
	# would in a pure in-memory round trip.
	var normalised := d.duplicate()
	for key in ["stats", "caps", "personal_bests"]:
		if normalised.has(key):
			normalised[key] = _int_keyed(normalised[key])
	var monkey := Monkey.from_dict(normalised)
	if monkey != null:
		return monkey
	monkey = Monkey.new()
	monkey.monkey_name = String(normalised.get("monkey_name", ""))
	monkey.species_type = int(normalised.get("species_type", SpeciesDb.default_type())) as Species.Type
	monkey.sex = int(normalised.get("sex", Monkey.Sex.MALE)) as Monkey.Sex
	monkey.generation = int(normalised.get("generation", 1))
	monkey.stats = _int_keyed(normalised.get("stats", {}))
	monkey.caps = _int_keyed(normalised.get("caps", {}))
	monkey.friendship = int(normalised.get("friendship", 0))
	monkey.fullness = int(normalised.get("fullness", 0))
	monkey.current_strength = int(normalised.get("current_strength", 0))
	monkey.current_stamina = int(normalised.get("current_stamina", 0))
	monkey.paralysed_slots = int(normalised.get("paralysed_slots", 0))
	monkey.retired = bool(normalised.get("retired", false))
	monkey.wins = int(normalised.get("wins", 0))
	monkey.losses = int(normalised.get("losses", 0))
	monkey.personal_bests = _int_keyed(normalised.get("personal_bests", {}))
	monkey.days_since_match = int(normalised.get("days_since_match", 99))
	return monkey


## Enum-keyed Dictionary -> {int: int}, tolerating the String keys JSON produces.
static func _int_keyed(source: Variant) -> Dictionary:
	var out := {}
	if typeof(source) != TYPE_DICTIONARY:
		return out
	for key in (source as Dictionary):
		out[int(key)] = int((source as Dictionary)[key])
	return out


static func _day_cycle_to_dict(day_cycle: DayCycle) -> Dictionary:
	if day_cycle == null:
		return {}
	var d := day_cycle.to_dict()
	if not d.is_empty():
		return d
	return {"day": day_cycle.day, "slot": int(day_cycle.slot)}


static func _day_cycle_apply(day_cycle: DayCycle, d: Dictionary) -> void:
	if day_cycle == null or d.is_empty():
		return
	day_cycle.apply_dict(d)
	# Belt and braces: if apply_dict is not doing the work yet, restore the two
	# fields the rest of the run genuinely cannot do without.
	if day_cycle.day != int(d.get("day", day_cycle.day)):
		day_cycle.day = int(d.get("day", day_cycle.day))
	if int(day_cycle.slot) != int(d.get("slot", int(day_cycle.slot))):
		day_cycle.slot = int(d.get("slot", int(day_cycle.slot))) as DayCycle.Slot


static func _ladder_to_dict(ladder: Ladder) -> Dictionary:
	if ladder == null:
		return {}
	var d := ladder.to_dict()
	if not d.is_empty():
		return d
	return {"rank": ladder.rank}


static func _ladder_apply(ladder: Ladder, d: Dictionary) -> void:
	if ladder == null or d.is_empty():
		return
	ladder.apply_dict(d)
	if ladder.rank != int(d.get("rank", ladder.rank)):
		ladder.rank = int(d.get("rank", ladder.rank))


static func _opponent_to_dict(opponent: Ladder.Opponent) -> Dictionary:
	if opponent == null:
		return {}
	return {
		"monkey": _monkey_to_dict(opponent.monkey),
		"rank": opponent.rank,
		"trainer_name": opponent.trainer_name,
		"purse": opponent.purse,
		"is_above_player": opponent.is_above_player,
	}


static func _opponent_from_dict(d: Dictionary) -> Ladder.Opponent:
	if d.is_empty():
		return null
	var opponent := Ladder.Opponent.new()
	opponent.monkey = _monkey_from_dict(_sub_dict(d, "monkey"))
	opponent.rank = int(d.get("rank", Ladder.BOTTOM_RANK))
	opponent.trainer_name = String(d.get("trainer_name", ""))
	opponent.purse = int(d.get("purse", 0))
	opponent.is_above_player = bool(d.get("is_above_player", false))
	return opponent
