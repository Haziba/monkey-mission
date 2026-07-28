class_name TestCase
extends RefCounted

## Base class for every unit test in `tests/unit/`.
##
## Subclass it, name the file `test_*.gd`, and give it methods named `test_*`.
## The runner (`tests/run_tests.gd`) instantiates the class once per test method,
## calls `before_each()`, the test method, then `after_each()`.
##
## Assertions record a failure and keep going, so one test method can report
## several problems in a single run. Any recorded failure fails the suite.

## Failures recorded during the currently running test method.
## Each entry: { "test": String, "message": String, "detail": String }
var failures: Array[Dictionary] = []

## Name of the test method currently executing. Set by the runner.
var current_test: String = ""

## Number of assertions that were evaluated (passing or failing).
var assertion_count: int = 0


## Hook: run before each `test_*` method.
func before_each() -> void:
	pass


## Hook: run after each `test_*` method.
func after_each() -> void:
	pass


# --- assertions ------------------------------------------------------------

func assert_eq(actual: Variant, expected: Variant, message: String = "") -> bool:
	assertion_count += 1
	if _values_equal(actual, expected):
		return true
	return _fail(message, "expected %s but got %s" % [_fmt(expected), _fmt(actual)])


func assert_ne(actual: Variant, unexpected: Variant, message: String = "") -> bool:
	assertion_count += 1
	if not _values_equal(actual, unexpected):
		return true
	return _fail(message, "expected a value other than %s" % _fmt(unexpected))


func assert_true(value: Variant, message: String = "") -> bool:
	assertion_count += 1
	if value:
		return true
	return _fail(message, "expected true but got %s" % _fmt(value))


func assert_false(value: Variant, message: String = "") -> bool:
	assertion_count += 1
	if not value:
		return true
	return _fail(message, "expected false but got %s" % _fmt(value))


func assert_null(value: Variant, message: String = "") -> bool:
	assertion_count += 1
	if value == null:
		return true
	return _fail(message, "expected null but got %s" % _fmt(value))


func assert_not_null(value: Variant, message: String = "") -> bool:
	assertion_count += 1
	if value != null:
		return true
	return _fail(message, "expected a non-null value")


func assert_almost_eq(actual: float, expected: float, tolerance: float = 0.0001, message: String = "") -> bool:
	assertion_count += 1
	if absf(actual - expected) <= tolerance:
		return true
	return _fail(message, "expected %s (+/- %s) but got %s" % [expected, tolerance, actual])


func assert_in_range(actual: Variant, low: Variant, high: Variant, message: String = "") -> bool:
	assertion_count += 1
	if actual >= low and actual <= high:
		return true
	return _fail(message, "expected a value in [%s, %s] but got %s" % [_fmt(low), _fmt(high), _fmt(actual)])


## Works for Array (contains element), Dictionary (has key), and String (substring).
func assert_has(container: Variant, element: Variant, message: String = "") -> bool:
	assertion_count += 1
	var found := false
	match typeof(container):
		TYPE_DICTIONARY:
			found = (container as Dictionary).has(element)
		TYPE_STRING, TYPE_STRING_NAME:
			found = String(container).contains(String(element))
		_:
			if container is Array or container is PackedStringArray \
					or container is PackedInt32Array or container is PackedInt64Array \
					or container is PackedFloat32Array or container is PackedFloat64Array:
				found = element in container
			else:
				return _fail(message, "assert_has got an uncontainable value: %s" % _fmt(container))
	if found:
		return true
	return _fail(message, "expected %s to contain %s" % [_fmt(container), _fmt(element)])


func assert_not_has(container: Variant, element: Variant, message: String = "") -> bool:
	assertion_count += 1
	var probe := TestCase.new()
	probe.current_test = current_test
	probe.assert_has(container, element)
	if probe.failures.is_empty():
		return _fail(message, "expected %s NOT to contain %s" % [_fmt(container), _fmt(element)])
	return true


## Record an unconditional failure.
func fail(message: String) -> bool:
	assertion_count += 1
	return _fail(message, "")


# --- internals -------------------------------------------------------------

func _fail(message: String, detail: String) -> bool:
	failures.append({
		"test": current_test,
		"message": message,
		"detail": detail,
	})
	return false


func _values_equal(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT or typeof(b) == TYPE_FLOAT:
		if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
			return is_equal_approx(float(a), float(b))
	return a == b


func _fmt(value: Variant) -> String:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return "\"%s\"" % value
		TYPE_NIL:
			return "null"
		_:
			return str(value)
