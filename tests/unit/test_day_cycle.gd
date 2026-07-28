extends TestCase

## DayCycle — the AM/PM half-day clock.
##
## Dossier §2 [C]: "Two actions per day. Every activity consumes one half-day
## slot regardless of outcome. Feeding is free and does not consume a slot."
## Everything here is about that counter behaving, and about story beats firing
## when their slot begins (§11 [C], the doorbell at the start of a day).

var cycle: DayCycle


func before_each() -> void:
	cycle = DayCycle.new()


# --- the clock -------------------------------------------------------------

func test_a_run_starts_on_day_one_in_the_morning() -> void:
	assert_eq(cycle.day, 1)
	assert_eq(cycle.slot, DayCycle.Slot.AM)
	assert_true(cycle.is_morning())
	assert_eq(cycle.slot_label(), "AM", "the HUD reads `[DAYS 1  AM]` (§10 [C])")
	assert_eq(cycle.total_slots_elapsed(), 0)


func test_the_first_activity_spends_the_morning_only() -> void:
	cycle.advance_slot()
	assert_eq(cycle.day, 1, "one activity must not roll the day over")
	assert_eq(cycle.slot, DayCycle.Slot.PM)
	assert_false(cycle.is_morning())
	assert_eq(cycle.slot_label(), "PM")
	assert_eq(cycle.total_slots_elapsed(), 1)


func test_two_activities_fill_a_day() -> void:
	cycle.advance_slot()
	cycle.advance_slot()
	assert_eq(cycle.day, 2, "two half-day slots is exactly one day (§2 [C])")
	assert_eq(cycle.slot, DayCycle.Slot.AM)
	assert_eq(cycle.total_slots_elapsed(), 2)


func test_total_slots_elapsed_counts_every_half_day() -> void:
	for i in 7:
		cycle.advance_slot()
	assert_eq(cycle.total_slots_elapsed(), 7)
	assert_eq(cycle.day, 4)
	assert_eq(cycle.slot, DayCycle.Slot.PM)


func test_the_rollover_signals_fire_in_order() -> void:
	var trace: Array[String] = []
	cycle.day_ended.connect(func(d: int) -> void: trace.append("ended:%d" % d))
	cycle.day_started.connect(func(d: int) -> void: trace.append("started:%d" % d))
	cycle.slot_advanced.connect(func(d: int, s: int) -> void:
		trace.append("slot:%d:%d" % [d, s]))

	cycle.advance_slot()   # AM -> PM, no rollover
	cycle.advance_slot()   # PM -> next AM, rollover

	assert_eq(trace, ["slot:1:1", "ended:1", "started:2", "slot:2:0"] as Array[String],
		"day_ended reports the day that just finished; day_started precedes slot_advanced")


func test_advance_day_from_the_morning_burns_both_slots() -> void:
	var ended: Array[int] = []
	cycle.day_ended.connect(func(d: int) -> void: ended.append(d))
	cycle.advance_day()
	assert_eq(cycle.day, 2)
	assert_eq(cycle.slot, DayCycle.Slot.AM)
	assert_eq(cycle.total_slots_elapsed(), 2, "the skipped afternoon is still spent")
	assert_eq(ended, [1] as Array[int])


func test_advance_day_from_the_afternoon_lands_on_tomorrow_morning() -> void:
	cycle.advance_slot()   # now day 1 PM
	cycle.advance_day()
	assert_eq(cycle.day, 2)
	assert_eq(cycle.slot, DayCycle.Slot.AM)
	assert_eq(cycle.total_slots_elapsed(), 2, "only the one remaining slot is spent")


func test_advance_day_repeatedly_never_skips_a_day() -> void:
	var started: Array[int] = []
	cycle.day_started.connect(func(d: int) -> void: started.append(d))
	for i in 5:
		cycle.advance_day()
	assert_eq(cycle.day, 6)
	assert_eq(started, [2, 3, 4, 5, 6] as Array[int])


# --- scheduled events ------------------------------------------------------

func test_nothing_is_pending_on_a_fresh_cycle() -> void:
	assert_eq(cycle.pending_events().size(), 0)


func test_an_event_fires_when_its_slot_begins() -> void:
	var fired: Array[String] = []
	cycle.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	cycle.schedule_event(2, DayCycle.Slot.AM, "bill_doorbell")

	cycle.advance_slot()
	assert_eq(fired.size(), 0, "day 1 PM must not fire a day 2 event")
	cycle.advance_slot()
	assert_eq(fired, ["bill_doorbell"] as Array[String])


func test_an_event_carries_its_day_and_slot() -> void:
	var seen := {}
	cycle.event_due.connect(func(id: String, d: int, s: int) -> void:
		seen[id] = [d, s])
	cycle.schedule_event(3, DayCycle.Slot.PM, "fred_visits")
	while cycle.day < 3 or cycle.slot != DayCycle.Slot.PM:
		cycle.advance_slot()
	assert_eq(seen.get("fred_visits"), [3, int(DayCycle.Slot.PM)])


func test_several_events_on_one_slot_all_fire_in_order() -> void:
	var fired: Array[String] = []
	cycle.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	cycle.schedule_event(2, DayCycle.Slot.AM, "doorbell")
	cycle.schedule_event(2, DayCycle.Slot.AM, "match_offer")
	cycle.advance_day()
	assert_eq(fired, ["doorbell", "match_offer"] as Array[String])


func test_scheduling_the_same_id_twice_does_not_double_fire() -> void:
	var fired: Array[String] = []
	cycle.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	cycle.schedule_event(2, DayCycle.Slot.AM, "doorbell")
	cycle.schedule_event(2, DayCycle.Slot.AM, "doorbell")
	cycle.advance_day()
	assert_eq(fired.size(), 1)


func test_an_empty_event_id_is_ignored() -> void:
	cycle.schedule_event(1, DayCycle.Slot.AM, "")
	assert_eq(cycle.pending_events().size(), 0)


func test_an_event_scheduled_in_the_past_never_fires() -> void:
	var fired: Array[String] = []
	cycle.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	cycle.advance_day()
	cycle.advance_day()          # now day 3 AM
	cycle.schedule_event(1, DayCycle.Slot.AM, "too_late")
	cycle.advance_day()
	cycle.advance_day()
	assert_eq(fired.size(), 0, "a slot never comes round again")


func test_advance_day_still_fires_an_event_on_the_skipped_afternoon() -> void:
	var fired: Array[String] = []
	cycle.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	cycle.schedule_event(1, DayCycle.Slot.PM, "evening_beat")
	cycle.advance_day()
	assert_eq(fired, ["evening_beat"] as Array[String],
		"sleeping through the afternoon must not swallow a story beat")


func test_clear_events_cancels_a_beat_before_it_lands() -> void:
	var fired: Array[String] = []
	cycle.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	cycle.schedule_event(2, DayCycle.Slot.AM, "doorbell")
	cycle.clear_events(2, DayCycle.Slot.AM)
	cycle.advance_day()
	assert_eq(fired.size(), 0)


func test_clear_events_on_an_empty_slot_is_harmless() -> void:
	cycle.clear_events(99, DayCycle.Slot.PM)
	assert_eq(cycle.pending_events().size(), 0)


func test_clear_events_only_touches_the_slot_it_is_given() -> void:
	cycle.schedule_event(2, DayCycle.Slot.AM, "morning_beat")
	cycle.schedule_event(2, DayCycle.Slot.PM, "evening_beat")
	cycle.clear_events(2, DayCycle.Slot.AM)
	assert_eq(cycle.events_on(2, DayCycle.Slot.AM).size(), 0)
	assert_eq(cycle.events_on(2, DayCycle.Slot.PM), PackedStringArray(["evening_beat"]))


func test_pending_events_reports_the_current_slot() -> void:
	cycle.schedule_event(1, DayCycle.Slot.AM, "intro")
	assert_eq(cycle.pending_events(), PackedStringArray(["intro"]),
		"day 1 AM is never 'begun', so the intro is read rather than emitted")
	cycle.advance_slot()
	assert_eq(cycle.pending_events().size(), 0)


func test_events_on_peeks_without_moving_the_clock() -> void:
	cycle.schedule_event(4, DayCycle.Slot.PM, "match")
	assert_eq(cycle.events_on(4, DayCycle.Slot.PM), PackedStringArray(["match"]))
	assert_eq(cycle.day, 1)
	assert_eq(cycle.slot, DayCycle.Slot.AM)


# --- serialisation ---------------------------------------------------------

func test_dict_round_trip_preserves_the_clock_and_the_schedule() -> void:
	cycle.advance_slot()
	cycle.advance_day()          # day 2 AM
	cycle.schedule_event(5, DayCycle.Slot.PM, "match_day")
	cycle.schedule_event(5, DayCycle.Slot.PM, "bill_visits")
	var data := cycle.to_dict()

	var restored := DayCycle.new()
	restored.apply_dict(data)
	assert_eq(restored.day, cycle.day)
	assert_eq(restored.slot, cycle.slot)
	assert_eq(restored.events_on(5, DayCycle.Slot.PM),
		PackedStringArray(["match_day", "bill_visits"]))
	assert_eq(restored.total_slots_elapsed(), cycle.total_slots_elapsed())


func test_serialised_enums_are_plain_ints() -> void:
	cycle.advance_slot()
	var data := cycle.to_dict()
	assert_eq(typeof(data["slot"]), TYPE_INT)
	assert_eq(data["slot"], int(DayCycle.Slot.PM))


func test_a_restored_cycle_still_fires_its_events() -> void:
	cycle.schedule_event(2, DayCycle.Slot.AM, "doorbell")
	var restored := DayCycle.new()
	restored.apply_dict(cycle.to_dict())
	var fired: Array[String] = []
	restored.event_due.connect(func(id: String, _d: int, _s: int) -> void: fired.append(id))
	restored.advance_day()
	assert_eq(fired, ["doorbell"] as Array[String])


func test_apply_dict_survives_an_empty_dictionary() -> void:
	cycle.advance_slot()
	cycle.apply_dict({})
	assert_eq(cycle.day, 1)
	assert_eq(cycle.slot, DayCycle.Slot.AM)
	assert_eq(cycle.pending_events().size(), 0)


func test_apply_dict_clamps_a_nonsense_day() -> void:
	cycle.apply_dict({"day": -40, "slot": 9})
	assert_eq(cycle.day, 1, "there is no day zero")
	assert_eq(cycle.slot, DayCycle.Slot.AM, "an out-of-range slot falls back to AM")


func test_apply_dict_replaces_rather_than_merges_the_schedule() -> void:
	cycle.schedule_event(2, DayCycle.Slot.AM, "stale")
	cycle.apply_dict({"day": 1, "slot": 0, "scheduled": {"2:0": ["fresh"]}})
	assert_eq(cycle.events_on(2, DayCycle.Slot.AM), PackedStringArray(["fresh"]))


func test_to_dict_drops_slots_that_were_cleared() -> void:
	cycle.schedule_event(2, DayCycle.Slot.AM, "doorbell")
	cycle.clear_events(2, DayCycle.Slot.AM)
	var scheduled: Dictionary = cycle.to_dict()["scheduled"]
	assert_eq(scheduled.size(), 0)
