extends TestCase

## Guard rail for parallel work: every script under core/ and ui/ must parse,
## and every scene must load. A stub with a broken signature fails here long
## before it fails in someone else's screen.

const SCANNED_DIRS: PackedStringArray = ["res://core", "res://ui", "res://tests"]


func test_every_script_parses() -> void:
	var scripts := _collect(SCANNED_DIRS, ".gd")
	assert_true(scripts.size() >= 20,
		"expected the foundation's scripts to be discoverable, found %d" % scripts.size())
	for path in scripts:
		var script: Resource = load(path)
		assert_not_null(script, "%s failed to parse" % path)
		# `load()` on a GDScript with a PARSE ERROR hands back a non-null,
		# UNCOMPILED Script — so `assert_not_null` alone passed against a file
		# full of syntax errors. Verified: adding a deliberately broken script
		# to core/ left this test green. `can_instantiate()` is the question
		# that actually asks the engine whether the script compiled.
		# (`tests/run_tests.gd` already learned this the hard way for the test
		# scripts themselves; this is the same check for the whole project.)
		if script is GDScript:
			assert_true((script as GDScript).can_instantiate(),
				"%s did not compile" % path)


func test_every_scene_loads() -> void:
	var scenes := _collect(SCANNED_DIRS, ".tscn")
	for path in scenes:
		var packed: Resource = load(path)
		assert_not_null(packed, "%s failed to load" % path)


func test_shared_theme_exists() -> void:
	var theme: Resource = load("res://ui/theme/main_theme.tres")
	assert_not_null(theme, "the single shared theme must exist")
	assert_true(theme is Theme, "main_theme.tres must be a Theme")


func _collect(roots: PackedStringArray, suffix: String) -> PackedStringArray:
	var found := PackedStringArray()
	for root in roots:
		_walk(root, suffix, found)
	return found


func _walk(dir_path: String, suffix: String, into: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			_walk(full, suffix, into)
		elif entry.ends_with(suffix):
			into.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
