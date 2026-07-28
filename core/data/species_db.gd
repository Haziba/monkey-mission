class_name SpeciesDb
extends RefCounted

## The five monkey types, built in code (placeholder art means there is nothing
## to author in the editor). Dossier §8 [C] for "five types, food preferences
## and drop rates are type-driven"; everything naming-related is [X].
##
## DIVERGENCE: type names, colours, per-type like/dislike lists and cap biases
## are all invented — no source names the types (dossier §14.4) and the dossier
## warns that Japanese "5種類" refers to the five training minigames, not
## species. Only the general rule is documented (§5 [C]): "most monkeys like
## bananas, curry, ice milk and expensive food; some dislike garlic, chicken
## and liver", so every type below likes bananas and no type dislikes them.

## Layering note: these Colors live in core, not in ui/theme/palette.gd, because
## core must never reach into ui. Palette exposes `Palette.monkey_color()` which
## reads THIS table — the dependency only ever points ui -> core.
const COLOR_SUNBURST := Color("f0a02a")
const COLOR_SUNBURST_DARK := Color("a3620f")
const COLOR_MIDNIGHT := Color("4a5ec8")
const COLOR_MIDNIGHT_DARK := Color("232d73")
const COLOR_EMERALD := Color("46b356")
const COLOR_EMERALD_DARK := Color("1f6b2c")
const COLOR_ASHEN := Color("b0b6bd")
const COLOR_ASHEN_DARK := Color("5e666e")
const COLOR_CRIMSON := Color("e0483c")
const COLOR_CRIMSON_DARK := Color("8a1f18")

static var _cache: Dictionary = {}


static func all() -> Array[Species]:
	_ensure()
	var out: Array[Species] = []
	for type in [
			Species.Type.SUNBURST,
			Species.Type.MIDNIGHT,
			Species.Type.EMERALD,
			Species.Type.ASHEN,
			Species.Type.CRIMSON]:
		out.append(_cache[type])
	return out


static func get_species(type: Species.Type) -> Species:
	_ensure()
	return _cache.get(type, _cache[Species.Type.SUNBURST])


## Freddy, the fixed starter, is this type. Dossier §7 [C].
static func default_type() -> Species.Type:
	return Species.Type.SUNBURST


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	_add(Species.Type.SUNBURST, "Sunburst", COLOR_SUNBURST, COLOR_SUNBURST_DARK,
		["banana", "curry", "ice_milk"], ["garlic"],
		{Monkey.Stat.POWER: 1.0, Monkey.Stat.SPEED: 1.0, Monkey.Stat.KNOWLEDGE: 1.0,
		 Monkey.Stat.STRENGTH: 1.0, Monkey.Stat.STAMINA: 1.0})
	_add(Species.Type.MIDNIGHT, "Midnight", COLOR_MIDNIGHT, COLOR_MIDNIGHT_DARK,
		["banana", "curry", "egg"], ["liver"],
		{Monkey.Stat.POWER: 0.9, Monkey.Stat.SPEED: 1.15, Monkey.Stat.KNOWLEDGE: 1.1,
		 Monkey.Stat.STRENGTH: 0.95, Monkey.Stat.STAMINA: 1.0})
	_add(Species.Type.EMERALD, "Emerald", COLOR_EMERALD, COLOR_EMERALD_DARK,
		["banana", "corn", "ice_milk"], ["chicken"],
		{Monkey.Stat.POWER: 0.95, Monkey.Stat.SPEED: 1.0, Monkey.Stat.KNOWLEDGE: 1.2,
		 Monkey.Stat.STRENGTH: 0.95, Monkey.Stat.STAMINA: 1.05})
	_add(Species.Type.ASHEN, "Ashen", COLOR_ASHEN, COLOR_ASHEN_DARK,
		["banana", "bread", "curry"], ["ice_milk"],
		{Monkey.Stat.POWER: 1.0, Monkey.Stat.SPEED: 0.9, Monkey.Stat.KNOWLEDGE: 0.95,
		 Monkey.Stat.STRENGTH: 1.2, Monkey.Stat.STAMINA: 1.05})
	_add(Species.Type.CRIMSON, "Crimson", COLOR_CRIMSON, COLOR_CRIMSON_DARK,
		["banana", "curry", "liver"], ["garlic", "ice_milk"],
		{Monkey.Stat.POWER: 1.2, Monkey.Stat.SPEED: 0.95, Monkey.Stat.KNOWLEDGE: 0.85,
		 Monkey.Stat.STRENGTH: 1.05, Monkey.Stat.STAMINA: 1.0})


static func _add(
		type: Species.Type,
		display_name: String,
		body: Color,
		accent: Color,
		liked: Array,
		disliked: Array,
		bias: Dictionary) -> void:
	var species := Species.new()
	species.type = type
	species.display_name = display_name
	species.body_color = body
	species.accent_color = accent
	species.liked_foods = PackedStringArray(liked)
	species.disliked_foods = PackedStringArray(disliked)
	species.cap_bias = bias
	_cache[type] = species
