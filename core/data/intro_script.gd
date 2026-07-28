class_name IntroScript
extends RefCounted

## The prologue dialogue, as pure data. Read by `ui/screens/intro_screen.gd` and
## played back through `ui/components/dialogue_box.gd`. No Node, no scene tree —
## this file must load under `--headless --script`.
##
## Story beats are the original's, from dossier §11 [C]:
##   * Kenta and Sumire live by the riverbank; their mother died when they were
##     young.
##   * Their father was a famous monkey trainer.
##   * The Saru Group — gangsters who illegally control the Monkey Puncher
##     Association — kidnapped him and one sibling and BRAINWASHED them.
##   * You play whichever sibling was NOT taken.
##   * Fred, "an old friend and former rival" of your father, hands over Freddy
##     and an instruction book. Both FAQ authors flag him as suspicious
##     immediately, so the script lets him be transparently shady without
##     spoiling that he is the Master (§7 phase 5 [C]) — that reveal is out of
##     scope for this slice.
##   * Bill, an Association worker, books every match free of charge.
##
## DIVERGENCE — the wording. The original's English is, in HG101's phrase,
## "stitching together mangled sentences". The brief is explicit: keep the beats
## and the characters, write the prose properly. The one place the original's
## localisation is preserved verbatim is the fight menu ("BEAT IT UP!" means
## defend), which lives in core/match_resolver.gd, not here.
##
## DIVERGENCE — the litter. In the original Fred hands you one fixed monkey,
## Freddy, of a fixed type (§7 phase 0 [C]). This build's brief adds a
## species-selection screen, so Fred arrives with a litter and you pick which of
## the five types Freddy is. Freddy's NAME stays fixed, which §8 [C] confirms.

## Who is speaking. NARRATOR lines have no nameplate.
enum Speaker {
	NARRATOR,
	PLAYER,     ## Kenta or Sumire, whichever the player chose
	SIBLING,    ## the other one — taken by the Saru Group
	FATHER,
	FRED,
	BILL,
	SARU,       ## an unnamed Saru Group voice; the group is never a person
}

## Indexed by RunState.Protagonist (KENTA = 0, SUMIRE = 1).
const PROTAGONIST_NAMES: PackedStringArray = ["KENTA", "SUMIRE"]
## How the protagonist refers to the sibling who was taken. Index by protagonist:
## Kenta's sibling is Sumire (a sister), Sumire's is Kenta (a brother).
const SIBLING_RELATIONS: PackedStringArray = ["sister", "brother"]

## Optional per-line audio hint the screen may forward to `Sfx`. Kept as a plain
## String so core never mentions a UI enum.
const CUE_DOORBELL := "doorbell"


## One line of dialogue. The screen turns this into a nameplate, a portrait tint
## and a typewriter reveal; it never edits the text.
class Line extends RefCounted:
	var speaker: Speaker = Speaker.NARRATOR
	## Already resolved for the chosen protagonist — "" for the narrator.
	var speaker_name: String = ""
	var text: String = ""
	## "" or one of the CUE_* constants.
	var cue: String = ""

	func is_narration() -> bool:
		return speaker == Speaker.NARRATOR


## The whole prologue, with {PLAYER}, {SIBLING} and {SIB_REL} resolved.
## `protagonist` is a RunState.Protagonist value.
static func lines(protagonist: int) -> Array:
	var out: Array = []
	for raw in _raw():
		var line := Line.new()
		line.speaker = raw["speaker"] as Speaker
		line.speaker_name = speaker_name_for(line.speaker, protagonist)
		line.text = _substitute(String(raw["text"]), protagonist)
		line.cue = String(raw.get("cue", ""))
		out.append(line)
	return out


static func length() -> int:
	return _raw().size()


static func protagonist_name(protagonist: int) -> String:
	return PROTAGONIST_NAMES[clampi(protagonist, 0, PROTAGONIST_NAMES.size() - 1)]


## The sibling the Saru Group took: whichever name the player did not pick.
static func sibling_name(protagonist: int) -> String:
	var index := clampi(protagonist, 0, PROTAGONIST_NAMES.size() - 1)
	return PROTAGONIST_NAMES[1 - index]


static func sibling_relation(protagonist: int) -> String:
	return SIBLING_RELATIONS[clampi(protagonist, 0, SIBLING_RELATIONS.size() - 1)]


## Nameplate text, "" for the narrator. The original prints the speaker in angle
## brackets on the first line of the box (`<BILL>`, see
## docs/reference/screens-hg101/Bill.png); the brackets are added by the UI.
static func speaker_name_for(speaker: int, protagonist: int) -> String:
	match speaker:
		Speaker.NARRATOR:
			return ""
		Speaker.PLAYER:
			return protagonist_name(protagonist)
		Speaker.SIBLING:
			return sibling_name(protagonist)
		Speaker.FATHER:
			return "FATHER"
		Speaker.FRED:
			return "FRED"
		Speaker.BILL:
			return "BILL"
		Speaker.SARU:
			return "???"
	return ""


static func _substitute(text: String, protagonist: int) -> String:
	return (text
		.replace("{PLAYER}", protagonist_name(protagonist))
		.replace("{SIBLING}", sibling_name(protagonist))
		.replace("{SIB_REL}", sibling_relation(protagonist)))


## The script itself. Written as a function rather than a `const` so the Line
## objects are freshly built per playthrough and nothing can mutate the source.
static func _raw() -> Array:
	return [
		# --- the riverbank, and what happened there (§11 [C]) ------------------
		{"speaker": Speaker.NARRATOR,
		 "text": "A small house on the riverbank, at the edge of town."},
		{"speaker": Speaker.NARRATOR,
		 "text": "You grew up here, the two of you. Your mother died when you were both very small."},
		{"speaker": Speaker.NARRATOR,
		 "text": "Your father raised you alone — and in the ring he was the finest monkey trainer the league had ever seen."},
		{"speaker": Speaker.NARRATOR,
		 "text": "Then, one night last winter, the Saru Group came to the door."},
		{"speaker": Speaker.SARU,
		 "text": "The Association answers to us now. So does every trainer in it."},
		{"speaker": Speaker.FATHER,
		 "text": "Get behind me, {PLAYER}. Both of you, get behind me."},
		{"speaker": Speaker.NARRATOR,
		 "text": "They took him. They took your {SIB_REL} {SIBLING} as well."},
		{"speaker": Speaker.NARRATOR,
		 "text": "By morning the house was quiet and the neighbours swore they had heard nothing at all."},
		{"speaker": Speaker.NARRATOR,
		 "text": "Word came back months later. Your father was fighting again — for Saru. And so was {SIBLING}."},
		{"speaker": Speaker.NARRATOR,
		 "text": "Someone had got inside their heads. Neither of them remembered your name."},
		{"speaker": Speaker.PLAYER,
		 "text": "Then I'll make them remember. I'm bringing them both home."},

		# --- Fred at the door (§7 phase 0 [C], §11 [C]) -----------------------
		{"speaker": Speaker.NARRATOR, "text": "*ding-dong*", "cue": CUE_DOORBELL},
		{"speaker": Speaker.FRED,
		 "text": "Well now. Look how you've grown, {PLAYER}."},
		{"speaker": Speaker.FRED,
		 "text": "Fred. I fought your father across a ring for twenty years. Rivals, friends — same thing in this business."},
		{"speaker": Speaker.FRED,
		 "text": "Terrible news about him. Terrible. I did everything I could, of course."},
		{"speaker": Speaker.PLAYER,
		 "text": "Did you?"},
		{"speaker": Speaker.FRED,
		 "text": "...Anyway. I've brought you something."},
		{"speaker": Speaker.NARRATOR,
		 "text": "Fred sets a crate down on the tatami. Something inside it is already chewing through the lid."},
		{"speaker": Speaker.FRED,
		 "text": "Last of a litter. Five of them, and only one is coming home with you — so choose carefully."},
		{"speaker": Speaker.FRED,
		 "text": "Whichever you pick, he's called Freddy. That part isn't up for discussion."},
		{"speaker": Speaker.FRED,
		 "text": "The instruction book's in the crate too, not that he can read it."},
		{"speaker": Speaker.FRED,
		 "text": "Feed him first. He won't listen to a word you say until he trusts you. They never do."},
		{"speaker": Speaker.FRED,
		 "text": "Then train him. Win. Climb the JSB ladder high enough and the people who took your father will come looking for you."},
		{"speaker": Speaker.PLAYER,
		 "text": "Why are you helping me?"},
		{"speaker": Speaker.FRED,
		 "text": "Let's say I'm curious how far you can take him."},
		{"speaker": Speaker.NARRATOR,
		 "text": "He holds the smile a moment longer than he needs to, and lets himself out."},

		# --- Bill from the Association (§11 [C]) ------------------------------
		{"speaker": Speaker.NARRATOR, "text": "*ding-dong*", "cue": CUE_DOORBELL},
		{"speaker": Speaker.BILL,
		 "text": "Morning! Bill — Monkey Puncher Association. Paperwork, mostly."},
		{"speaker": Speaker.BILL,
		 "text": "I book the matches. You never pay me a yen for it; that's the Association's side of the arrangement."},
		{"speaker": Speaker.BILL,
		 "text": "You start at JSB rank 5. Rank 1 is the champion. Beat someone ranked above you and you take their place."},
		{"speaker": Speaker.BILL,
		 "text": "Beat someone below you and you'll get paid, but you won't move. Lose to them and you drop."},
		{"speaker": Speaker.BILL,
		 "text": "I'll ring the bell when I've got fights for you. Three at a time — you pick one, it happens the next day."},
		{"speaker": Speaker.BILL,
		 "text": "And {PLAYER}? Look after that monkey. Fed, trained, happy. In that order."},
		{"speaker": Speaker.PLAYER,
		 "text": "I will."},
		{"speaker": Speaker.NARRATOR,
		 "text": "The crate rattles. Something in there is waiting to be let out."},
	]
