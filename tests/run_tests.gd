extends SceneTree

## Headless unit-test runner for monkey-puncher-mk2. Zero external dependencies.
##
## Run it with:
##   /Applications/Godot.app/Contents/MacOS/Godot --headless \
##     --path /Users/harry/git/monkey-puncher-mk2 --script tests/run_tests.gd
##
## Discovers every `tests/unit/test_*.gd`, instantiates the class once per test
## method, and runs every method whose name starts with `test_`, wrapped in
## `before_each()` / `after_each()`.
##
## Exit code is 0 when everything passes and 1 when anything fails or errors.
##
## Optional filter: pass `-- <substring>` and only matching
## `file.test_method` names run.

const UNIT_DIR := "res://tests/unit"

var _passed: int = 0
var _failed: int = 0
var _assertions: int = 0
var _failure_lines: Array[String] = []
## Every test the runner decided to run, compared against passed+failed at the
## end so a test cannot silently vanish from the tally.
##
## KNOWN LIMITATION, do not mistake this for full protection: a GDScript runtime
## error (a bad index, a call on null) unwinds only the function it happened in
## and there is no way to catch one. An error raised inside a `test_*` method or
## inside `before_each` therefore returns control to `_run_one`, which finds no
## recorded failures and prints PASS. The error text still goes to stderr, so
## grep the run for "SCRIPT ERROR" before trusting a green suite. This counter
## catches the case where the unwind escapes `_run_one` itself.
var _planned: int = 0


func _initialize() -> void:
	var filter := _read_filter()
	var script_paths := _discover(UNIT_DIR)
	script_paths.sort()

	print("")
	print("monkey-puncher-mk2 :: unit suite")
	if filter != "":
		print("filter: \"%s\"" % filter)
	print("%d test script(s) in %s" % [script_paths.size(), UNIT_DIR])
	print("-".repeat(72))

	if script_paths.is_empty():
		print("no test scripts found — that is itself a failure")
		_finish(1)
		return

	for path in script_paths:
		_run_script(path, filter)

	# A test method that raised a GDScript runtime error unwound `_run_one`
	# before it could report anything. Without this the suite would go green
	# having silently skipped it.
	var reported := _passed + _failed
	if reported < _planned:
		_record_hard_failure(UNIT_DIR, "<crashed>",
			"%d test(s) started but never reported — a runtime error unwound them"
				% (_planned - reported))

	print("-".repeat(72))
	print("%d passed, %d failed, %d assertions" % [_passed, _failed, _assertions])
	if _failed > 0:
		print("")
		print("FAILURES")
		for line in _failure_lines:
			print("  " + line)
		print("")
		print("SUITE RED")
		_finish(1)
	else:
		print("SUITE GREEN")
		_finish(0)


func _read_filter() -> String:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		return String(args[0])
	return ""


func _discover(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("cannot open test directory: %s" % dir_path)
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_discover(full))
		elif entry.begins_with("test_") and entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func _run_script(path: String, filter: String) -> void:
	var script: Script = load(path)
	if script == null:
		_record_hard_failure(path, "<load>", "script failed to load / did not compile")
		return
	# A GDScript with a PARSE ERROR still loads as a non-null object — `load()`
	# hands back an uncompiled Script rather than null — and calling `new()` on
	# it raises a runtime error that unwinds this function without recording
	# anything. That made a broken test file exit the suite GREEN. Ask the
	# engine whether the script actually compiled instead of finding out the
	# hard way.
	if not script.can_instantiate():
		_record_hard_failure(path, "<parse>", "script has a parse error and did not compile")
		return

	var probe: Object = script.new()
	if probe == null:
		_record_hard_failure(path, "<new>", "script could not be instantiated")
		return
	# Duck-typed on purpose: this runner must never mention the `TestCase` global
	# class. If it did, a parse error anywhere in the project would stop the
	# runner itself from loading and Godot would exit 0 — a silently green CI.
	if not (probe.has_method("before_each") and probe.has_method("assert_eq")):
		_record_hard_failure(path, "<type>", "script does not extend TestCase")
		return

	var method_names: Array[String] = []
	for method in probe.get_method_list():
		var name: String = method["name"]
		if name.begins_with("test_") and not method_names.has(name):
			method_names.append(name)
	method_names.sort()

	var label := path.get_file().get_basename()
	if method_names.is_empty():
		_record_hard_failure(path, "<empty>", "no test_* methods found")
		return

	for method_name in method_names:
		var qualified := "%s.%s" % [label, method_name]
		if filter != "" and not qualified.contains(filter):
			continue
		_planned += 1
		_run_one(script, label, method_name, qualified)


func _run_one(script: Script, label: String, method_name: String, qualified: String) -> void:
	var instance: Object = script.new()
	instance.current_test = qualified
	instance.before_each()
	instance.call(method_name)
	instance.after_each()

	_assertions += instance.assertion_count
	if instance.failures.is_empty():
		_passed += 1
		print("  PASS  %s" % qualified)
	else:
		_failed += 1
		print("  FAIL  %s" % qualified)
		for failure in instance.failures:
			var message: String = failure.get("message", "")
			var detail: String = failure.get("detail", "")
			var text := "%s: " % qualified
			if message != "" and detail != "":
				text += "%s — %s" % [message, detail]
			elif message != "":
				text += message
			else:
				text += detail
			_failure_lines.append(text)
			print("        %s" % text.substr(qualified.length() + 2))


func _record_hard_failure(path: String, stage: String, reason: String) -> void:
	_failed += 1
	var text := "%s %s: %s" % [path, stage, reason]
	_failure_lines.append(text)
	print("  FAIL  %s" % text)


func _finish(code: int) -> void:
	print("")
	quit(code)
