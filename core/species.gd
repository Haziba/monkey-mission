class_name Species
extends Resource

## One of the five monkey types. Dossier §8: "Five types, excluding bosses ...
## Type is mechanically load-bearing, not cosmetic — it drives food preferences
## and item drop rates." [C]
##
## DIVERGENCE: the dossier is explicit that NONE of the five types is named in
## any source and they are probably not officially named at all (§8 [X], §14.4).
## The names below are therefore invented, and deliberately descriptive of the
## placeholder colour rather than pretending to be original game terms.

enum Type {
	SUNBURST,   ## warm orange — the starter type (Freddy)
	MIDNIGHT,   ## deep blue
	EMERALD,    ## green
	ASHEN,      ## grey
	CRIMSON,    ## red
}

@export var type: Type = Type.SUNBURST
@export var display_name: String = ""

## Placeholder art only: flat fills, no sprites. See ui/theme/palette.gd.
@export var body_color: Color = Color.WHITE
@export var accent_color: Color = Color.BLACK

## Food ids (see core/data/food_db.gd) this type likes / dislikes.
## Dossier §5 [C]: most monkeys like bananas, curry, ice milk and expensive
## food; some dislike garlic, chicken and liver. Per-type detail is [X].
@export var liked_foods: PackedStringArray = PackedStringArray()
@export var disliked_foods: PackedStringArray = PackedStringArray()

## Multiplier applied to each starting cap, keyed by Monkey.Stat.
## DIVERGENCE: the dossier never says type affects caps ([X], §14.8 —
## "whether type ... is inherited by offspring" is unknown). A small bias is
## used here so the five types read as mechanically distinct in a short slice.
@export var cap_bias: Dictionary = {}


func likes(food_id: String) -> bool:
	return food_id in liked_foods


func dislikes(food_id: String) -> bool:
	return food_id in disliked_foods


## Friendship multiplier for feeding this food: >1 liked, <1 disliked, 1 neutral.
func friendship_multiplier_for(food_id: String) -> float:
	if likes(food_id):
		return 2.0
	if dislikes(food_id):
		return -0.5
	return 1.0


## cap_bias lookup with a sane default. `stat` is a Monkey.Stat value.
func cap_bias_for(stat: int) -> float:
	return float(cap_bias.get(stat, 1.0))


## The single stat this type leans towards, or -1 when it is balanced.
## Returned as a Monkey.Stat value; -1 is the "no tendency" sentinel, matching
## Breeding.archetype_stat()'s use of -1 for AVG.
##
## DIVERGENCE: the dossier never gives per-type tendencies — it only confirms
## that type drives food preferences and drop rates (§8 [C]), and §14.4 says the
## types are not even named. This reads the invented cap_bias table so the UI
## has one word to print on the monkey-select screen.
func tendency_stat() -> int:
	var best := -1
	var best_bias := 1.0
	var tied := false
	for stat in Monkey.STATS:
		var bias := cap_bias_for(stat)
		if bias > best_bias + 0.0001:
			best = stat
			best_bias = bias
			tied = false
		elif best >= 0 and is_equal_approx(bias, best_bias):
			tied = true
	return -1 if tied else best


## "BALANCED" or the stat card label of the leaning stat ("POW", "SPD", ...).
func tendency_label() -> String:
	var stat := tendency_stat()
	if stat < 0:
		return "BALANCED"
	return Monkey.stat_label(stat)
