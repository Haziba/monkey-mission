class_name MpRng
extends RefCounted

## Seedable random source. Every core system takes one of these by injection so
## that headless tests can pin a seed and get deterministic results. Core code
## must NEVER call the global `randi()` / `randf()` — always go through MpRng.

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seed: int = 0


func _init(seed_value: int = 0) -> void:
	if seed_value == 0:
		seed_value = int(Time.get_unix_time_from_system() * 1000.0) | 1
	_seed = seed_value
	_rng.seed = seed_value


func seed_value() -> int:
	return _seed


## Full serialisable state, so a save file can resume the same stream.
func state() -> int:
	return int(_rng.state)


func set_state(value: int) -> void:
	_rng.state = value


func randf() -> float:
	return _rng.randf()


func randf_range(from: float, to: float) -> float:
	return _rng.randf_range(from, to)


func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## True with probability `p` (0.0 .. 1.0).
func chance(p: float) -> bool:
	return _rng.randf() < p


func pick(options: Array) -> Variant:
	if options.is_empty():
		return null
	return options[_rng.randi_range(0, options.size() - 1)]


## Gaussian-ish spread around `mid`, clamped to [low, high]. Useful for
## generating opponent stats and inherited caps without hard edges.
func spread(mid: float, deviation: float, low: float, high: float) -> float:
	var value := mid + (_rng.randf() + _rng.randf() + _rng.randf() - 1.5) * deviation
	return clampf(value, low, high)
