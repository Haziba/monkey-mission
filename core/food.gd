class_name Food
extends Resource

## One buyable food. Values come straight from the supergus2 FAQ v1.0 table in
## dossier §5 [C], which the dossier prefers over the older tofu_bud numbers.
##
## Naming trap carried from the dossier §3: STRENGTH is the health bar, POWER is
## damage. `strength_restore` therefore heals; it is not a stat buff.

@export var id: String = ""
@export var display_name: String = ""
@export var buy_price: int = 0
@export var sell_price: int = 0

## Strength (health) restored on eating.
@export var strength_restore: int = 0

## Stamina restored on eating.
@export var stamina_restore: int = 0

## Fullness added. Coffee is -5 on purpose (dossier §5 [C]) — it makes room for
## more food. Negative values are legal and must not be clamped away.
@export var hunger: int = 0

## Permanent stat gains, keyed by Monkey.Stat -> int. Empty for ordinary food.
## Wasted entirely if the target stat is already capped (dossier §3 [C]).
@export var permanent_gains: Dictionary = {}


func is_permanent_booster() -> bool:
	return not permanent_gains.is_empty()


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"buy_price": buy_price,
		"sell_price": sell_price,
		"strength_restore": strength_restore,
		"stamina_restore": stamina_restore,
		"hunger": hunger,
		"permanent_gains": permanent_gains.duplicate(),
	}


static func make(
		p_id: String,
		p_name: String,
		p_buy: int,
		p_sell: int,
		p_str: int,
		p_stm: int,
		p_hunger: int,
		p_permanent: Dictionary = {}) -> Food:
	var food := Food.new()
	food.id = p_id
	food.display_name = p_name
	food.buy_price = p_buy
	food.sell_price = p_sell
	food.strength_restore = p_str
	food.stamina_restore = p_stm
	food.hunger = p_hunger
	food.permanent_gains = p_permanent
	return food
