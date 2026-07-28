class_name RhythmScore
extends RefCounted

## The training minigame's output, handed from UI to core. Dossier §4 [C]:
## training is a rhythm/imitation minigame — the trainer performs the exercise
## with rhythmic A presses and the monkey copies. **Failure is two-sided**:
## press too slowly and the monkey loses interest; press too fast and the
## trainer cramps. Both directions must be represented here, which is why
## `early` (cramp) and `late` (lost interest) are separate counters.
##
## This is the ONLY thing core/training.gd accepts from the minigame — the
## scene never reaches into Training's maths, and Training never reads input.

## Reps the monkey actually completed. Drives the personal record
## (自己最高回数, dossier §4 [C]) and the floating red number in the HUD.
var reps: int = 0
## Taps inside the beat window.
var perfect: int = 0
## Taps before the window — the trainer cramps.
var early: int = 0
## Taps after the window (or missed entirely) — the monkey loses interest.
var late: int = 0
## Session length in seconds; the HUD shows it as a `[0:41]` countdown.
var duration_s: float = 0.0
## True if the session was cut short by the hunger interrupt (dossier §4 [C]:
## the monkey sits down and grabs its stomach; you feed it in place).
var interrupted: bool = false


## 0.0 .. 1.0. Fraction of taps that landed in the window.
func accuracy() -> float:
	var total := perfect + early + late
	if total <= 0:
		return 0.0
	return float(perfect) / float(total)


## A session with no taps at all is not a valid result.
func is_valid() -> bool:
	return (perfect + early + late) > 0 or reps > 0


## Build a score from raw tap timestamps. `beat_interval` is the seconds between
## prompts; `window` is the half-width of the acceptable window.
##
## Classification matches `Training.classify_interval` exactly — an interval
## shorter than `beat_interval - window` is a cramp (too fast), longer than
## `beat_interval + window` is lost interest (too slow), anything between is a
## rep. Keeping the two in step matters: the training screen draws the window
## from `Training.target_window()` and the player must be aiming at the same
## thing the score is judged against.
##
## The first tap is measured from t=0, and the idle tail after the last tap is
## charged as `late` for every whole missed beat, because sitting still IS the
## documented "too slow" failure (dossier §4 [C]) rather than a neutral pause.
static func from_taps(
		tap_times: PackedFloat32Array,
		beat_interval: float,
		duration: float,
		window: float = 0.12) -> RhythmScore:
	var score := RhythmScore.new()
	score.duration_s = maxf(0.0, duration)
	if beat_interval <= 0.0:
		return score

	var low := beat_interval - window
	var high := beat_interval + window
	var previous := 0.0
	for time in tap_times:
		var at := float(time)
		var interval := at - previous
		previous = at
		if interval < low:
			# Too fast — THE TRAINER CRAMPS. The rep does not land.
			score.early += 1
		elif interval > high:
			# Too slow — THE MONKEY LOSES INTEREST.
			score.late += 1
		else:
			score.perfect += 1
			score.reps += 1

	# Whatever is left between the final tap and the end of the session is dead
	# air; charge one "lost interest" per beat that should have happened in it.
	var tail := score.duration_s - previous
	if tail > high:
		score.late += int(floorf(tail / beat_interval))
	return score


## A neutral, fully-average session. Used by tests and by the "monkey continues
## unprompted" late-game state the dossier flags as a design flaw (§4 [C]) —
## the slice keeps input required, so this is mainly a test fixture.
static func average(reps_done: int, duration: float = 30.0) -> RhythmScore:
	var score := RhythmScore.new()
	score.reps = reps_done
	score.perfect = reps_done
	score.duration_s = duration
	return score
