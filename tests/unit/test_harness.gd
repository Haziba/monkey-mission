extends TestCase

## Meta-test: proves the harness can both pass and FAIL. A test framework that
## cannot fail is worse than none.
##
## `probe` is a throwaway TestCase whose failures are inspected rather than
## reported, so we can assert that a broken assertion really does record one.

var probe: TestCase
var before_each_ran: bool = false


func before_each() -> void:
	probe = TestCase.new()
	probe.current_test = "probe"
	before_each_ran = true


func test_before_each_runs() -> void:
	assert_true(before_each_ran, "before_each should run before each test method")


func test_passing_assertions_record_nothing() -> void:
	probe.assert_eq(2 + 2, 4)
	probe.assert_ne(1, 2)
	probe.assert_true(true)
	probe.assert_false(false)
	probe.assert_null(null)
	probe.assert_not_null(self)
	probe.assert_almost_eq(0.1 + 0.2, 0.3)
	probe.assert_in_range(5, 1, 10)
	probe.assert_has([1, 2, 3], 2)
	probe.assert_has({"a": 1}, "a")
	probe.assert_has("banana", "nan")
	probe.assert_not_has([1, 2], 9)
	assert_eq(probe.failures.size(), 0, "no assertion above should have failed")
	assert_eq(probe.assertion_count, 12, "every assertion should be counted")


func test_failing_assertions_are_recorded() -> void:
	probe.assert_eq(1, 2, "eq")
	probe.assert_ne(3, 3, "ne")
	probe.assert_true(false, "true")
	probe.assert_false(true, "false")
	probe.assert_null(1, "null")
	probe.assert_not_null(null, "not_null")
	probe.assert_almost_eq(1.0, 2.0, 0.0001, "almost")
	probe.assert_in_range(50, 1, 10, "range")
	probe.assert_has([1, 2], 9, "has")
	probe.assert_not_has([1, 2], 1, "not_has")
	probe.fail("explicit")
	assert_eq(probe.failures.size(), 11, "every broken assertion should be recorded")


func test_failures_carry_the_test_name_and_a_message() -> void:
	probe.assert_eq(7, 9, "seven is not nine")
	assert_eq(probe.failures.size(), 1)
	var failure: Dictionary = probe.failures[0]
	assert_eq(failure["test"], "probe", "the failure knows which test produced it")
	assert_eq(failure["message"], "seven is not nine")
	assert_has(String(failure["detail"]), "expected 9 but got 7",
		"the detail should show both values")


func test_int_and_float_compare_cleanly() -> void:
	probe.assert_eq(1, 1.0)
	assert_eq(probe.failures.size(), 0, "1 and 1.0 should compare equal")
