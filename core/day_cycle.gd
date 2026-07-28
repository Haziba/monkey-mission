class_name DayCycle
extends RefCounted

## Day counter and AM/PM half-day slots. Dossier §2 [C]:
## "Two actions per day. Every activity consumes one half-day slot regardless of
## outcome — a training session, a shopping trip, a sparring session, or a
## match. Feeding is free and does not consume a slot."
##
## The overworld HUD shows this as `[DAYS 2  AM]` (dossier §10 [C]).
##
## Story/match events are registered against a (day, slot) and emitted when that
## slot begins — the original fires them via the doorbell at the start of a day
## (dossier §11 [C]).
##
## NOTE ON SLOTS: this class does NOT know what an activity is. It only counts.
## Feeding must never reach it; training, shopping, sparring and matches each
## call advance_slot() exactly once, through GameState.consume_slot().

enum Slot { AM, PM }

## Fired every time the slot pointer moves.
signal slot_advanced(day: int, slot: Slot)
## Fired when the day rolls over, before slot_advanced for the new AM.
signal day_started(day: int)
## Fired after the PM slot is consumed.
signal day_ended(day: int)
## Fired for each event id scheduled on the slot that just began.
signal event_due(event_id: String, day: int, slot: Slot)

var day: int = 1
var slot: Slot = Slot.AM

## "%d:%d" % [day, slot] -> Array[String] of event ids.
var _scheduled: Dictionary = {}


func is_morning() -> bool:
	return slot == Slot.AM


## "AM" / "PM" for the HUD.
func slot_label() -> String:
	return "AM" if slot == Slot.AM else "PM"


## Consume the current half-day slot and move on, rolling the day at PM->AM.
## Emits day_ended / day_started / slot_advanced / event_due as appropriate.
func advance_slot() -> void:
	if slot == Slot.AM:
		slot = Slot.PM
	else:
		# The PM slot has been spent, so the day is over before the counter moves.
		day_ended.emit(day)
		day += 1
		slot = Slot.AM
		day_started.emit(day)
	slot_advanced.emit(day, slot)
	_fire_events_for_current_slot()


## Skip straight to tomorrow morning (used by "sleep" / post-match rest).
## Every slot in between is still consumed one at a time so that nothing
## scheduled on the skipped PM is silently swallowed.
func advance_day() -> void:
	var target_day := day + 1
	# At most two iterations (PM -> AM, or AM -> PM -> AM); the guard is
	# defensive only, so a future change to Slot cannot hang the game.
	var guard := 0
	while guard < 8:
		guard += 1
		advance_slot()
		if day >= target_day and slot == Slot.AM:
			return


## Total half-days elapsed since day 1 AM. Handy for scheduling and for tests.
func total_slots_elapsed() -> int:
	return (day - 1) * 2 + int(slot)


func schedule_event(p_day: int, p_slot: Slot, event_id: String) -> void:
	if event_id.is_empty():
		return
	var key := _key(p_day, p_slot)
	var ids: Array = _scheduled.get(key, [])
	if event_id in ids:
		return
	ids.append(event_id)
	_scheduled[key] = ids


## Event ids scheduled for the CURRENT slot.
func pending_events() -> PackedStringArray:
	return events_on(day, slot)


## Event ids scheduled for an arbitrary slot. Additive helper: the router needs
## to ask "is anything waiting tomorrow morning?" without moving the clock.
func events_on(p_day: int, p_slot: Slot) -> PackedStringArray:
	var out := PackedStringArray()
	for id in _scheduled.get(_key(p_day, p_slot), []):
		out.append(String(id))
	return out


func clear_events(p_day: int, p_slot: Slot) -> void:
	_scheduled.erase(_key(p_day, p_slot))


func to_dict() -> Dictionary:
	var scheduled := {}
	for key in _scheduled:
		var ids: Array = _scheduled[key]
		if ids.is_empty():
			continue
		# Copy as plain Strings so the save file survives a JSON round trip.
		var copy: Array = []
		for id in ids:
			copy.append(String(id))
		scheduled[String(key)] = copy
	return {
		"day": day,
		"slot": int(slot),
		"scheduled": scheduled,
	}


func apply_dict(d: Dictionary) -> void:
	day = maxi(1, int(d.get("day", 1)))
	slot = Slot.PM if int(d.get("slot", Slot.AM)) == int(Slot.PM) else Slot.AM
	_scheduled = {}
	var scheduled: Dictionary = d.get("scheduled", {})
	for key in scheduled:
		var ids: Array = []
		for id in scheduled[key]:
			var text := String(id)
			if not text.is_empty() and not (text in ids):
				ids.append(text)
		if not ids.is_empty():
			_scheduled[String(key)] = ids


func _key(p_day: int, p_slot: Slot) -> String:
	return "%d:%d" % [p_day, int(p_slot)]


## Events are NOT cleared once fired. A (day, slot) pair never comes round
## again, so re-firing is impossible; clear_events() stays explicit so a story
## beat can be cancelled before its slot arrives.
func _fire_events_for_current_slot() -> void:
	for id in pending_events():
		event_due.emit(id, day, slot)
