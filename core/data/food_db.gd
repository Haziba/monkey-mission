class_name FoodDb
extends RefCounted

## The slice's food list. Numbers are verbatim from the supergus2 FAQ v1.0 table
## in dossier §5 [C] — buy / sell / Strength restored / Stamina restored /
## Hunger / permanent gains.
##
## SCOPE: the brief cuts the full 40-item food economy; "a handful of foods is
## enough". This is a 12-item subset chosen to cover every mechanic the slice
## needs: a cheap befriender (Banana), a stomach-settler (Biscuit), the negative
## -hunger trick (Coffee), a heavy meal (Curry), a dislike-test food (Garlic,
## Liver), and one permanent booster per axis (Eel, Coconuts).
##
## Do NOT add the endgame items (Peanuts, Steak, Melon, Caviar) to the shop
## without a scope change — Peanuts alone trivialise capping (dossier §5 [C]).

static var _cache: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()


static func all() -> Array[Food]:
	_ensure()
	var out: Array[Food] = []
	for id in _order:
		out.append(_cache[id])
	return out


static func get_food(id: String) -> Food:
	_ensure()
	return _cache.get(id, null)


static func has_food(id: String) -> bool:
	_ensure()
	return _cache.has(id)


static func ids() -> PackedStringArray:
	_ensure()
	return _order.duplicate()


## What a new run starts with. Dossier §7 [C]: Fred hands over Freddy and you
## must feed it; the documented fastest befriending is two bananas.
static func starting_inventory() -> Dictionary:
	return {"banana": 4, "biscuit": 2, "corn": 2}


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	# id, name, buy, sell, Str, Stm, Hunger, permanent
	_add(Food.make("biscuit", "Biscuit", 40, 20, 0, 0, 3))
	_add(Food.make("plum", "Plum", 40, 20, 0, 40, 1))
	_add(Food.make("banana", "Banana", 100, 50, 15, 15, 3))
	_add(Food.make("corn", "Corn", 100, 50, 15, 15, 1))
	_add(Food.make("egg", "Egg", 100, 60, 50, 0, 3))
	_add(Food.make("ice_milk", "Ice Milk", 100, 50, 0, 0, 1))
	# Coffee's hunger is -5 on purpose: it makes room for more food. [C]
	_add(Food.make("coffee", "Coffee", 100, 50, 0, 0, -5))
	# DIVERGENCE: the guide's Hunger column for Chicken is "?" ([X]). 2 is
	# chosen to sit between Corn (1) and Liver (3) at a similar price point.
	_add(Food.make("chicken", "Chicken", 110, 55, 20, 0, 2))
	_add(Food.make("liver", "Liver", 120, 60, 20, 0, 3))
	_add(Food.make("bread", "Bread", 150, 75, 30, 30, 7))
	_add(Food.make("garlic", "Garlic", 150, 60, 30, 30, 1))
	_add(Food.make("curry", "Curry", 300, 150, 60, 60, 9))
	_add(Food.make("eel", "Eel", 1200, 600, 100, 200, 12,
		{Monkey.Stat.STRENGTH: 10, Monkey.Stat.STAMINA: 10}))
	_add(Food.make("coconuts", "Coconuts", 1200, 600, 150, 150, 5,
		{Monkey.Stat.POWER: 5, Monkey.Stat.KNOWLEDGE: 5}))


static func _add(food: Food) -> void:
	_cache[food.id] = food
	_order.append(food.id)
