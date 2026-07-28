extends "res://tests/framework/ui_test_case.gd"

## Structural coverage across every screen.
##
## Written after a verification pass found three bugs of a kind no core test
## could ever catch: a REST button sitting in `home_screen.tscn` with no handler
## connected, a SETTINGS button on the title screen routing to a Screen enum
## value with no scene behind it, and the fight screen's corner-action flavour
## text living in `tooltip_text` — which a phone can never show, because there is
## no hover on a touchscreen.
##
## These are cheap, blunt checks. They do not know whether a screen looks right.
## They do know whether a button does anything when you press it.

const SCREEN_DIR := "res://ui/screens"
const COMPONENT_DIR := "res://ui/components"

## Apple's HIG says 44pt, which is 88px at the 2x we author at. Anything
## interactive below this is a thumb-sized problem.
const MIN_TOUCH_PX := 88.0

## Scenes that are deliberately not a full screen and are exempt from the
## screen-level rules.
## Router.Screen entries with no scene behind them. All four are out of this
## slice (docs/ARCHITECTURE.md §8). Listed, not skipped, so a new route to
## nowhere still fails and so this list visibly shrinks as screens land.
const UNBUILT_SCREENS := ["TRAINING_SELECT", "STAT_CARD", "SHOP", "SETTINGS"]


func _scene_paths(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tscn"):
			found.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


func _has_child_label_text(root: Node) -> bool:
	for node in descendants_of_type(root, "Label"):
		if (node as Label).text.strip_edges() != "":
			return true
	return false


func _all_scene_paths() -> Array[String]:
	var found := _scene_paths(SCREEN_DIR)
	found.append_array(_scene_paths(COMPONENT_DIR))
	return found


# --- the scenes exist and can actually be built ------------------------------

func test_there_are_screens_to_test() -> void:
	# Guard against the whole suite silently passing because the glob broke.
	assert_true(_scene_paths(SCREEN_DIR).size() >= 8,
		"expected the slice's screens to be discoverable in %s" % SCREEN_DIR)


func test_every_scene_instantiates_and_readies() -> void:
	for path in _all_scene_paths():
		var node := mount(path)
		assert_not_null(node, "%s did not instantiate" % path)
		if node != null:
			assert_not_null(node.get_parent(), "%s was never parented" % path)
		unmount_all()


# --- buttons do something ----------------------------------------------------

func test_every_enabled_button_is_connected_to_something() -> void:
	# The bug this exists for: `Btn10 "REST"` shipped enabled, visible and wired
	# to nothing at all.
	for path in _all_scene_paths():
		var root := mount(path)
		if root == null:
			continue
		for node in buttons_under(root):
			var button := node as Button
			if button.disabled:
				continue
			assert_true(button.pressed.get_connections().size() > 0,
				"%s :: %s is enabled but nothing is connected to pressed" % [
					path, path_of(button, root)])
		unmount_all()


func test_no_button_ships_with_placeholder_or_empty_text() -> void:
	for path in _all_scene_paths():
		var root := mount(path)
		if root == null:
			continue
		for node in buttons_under(root):
			var button := node as Button
			if button.icon != null:
				continue
			var label := button.text.strip_edges()
			# A card-style button composes its own Labels as children rather than
			# using `text` — the character cards and the monkey-select rows both
			# do. Those are still labelled, just not through the property.
			if label == "" and _has_child_label_text(button):
				continue
			assert_true(label != "",
				"%s :: %s has no text and no labelled children" % [
					path, path_of(button, root)])
			assert_false(label.to_upper().contains("TODO"),
				"%s :: %s still says %s" % [path, path_of(button, root), label])
		unmount_all()


func test_buttons_are_thumb_sized() -> void:
	# Asserted against custom_minimum_size, not size: containers lay out on a
	# deferred call and no frame has ticked, so `size` is meaningless here.
	for path in _all_scene_paths():
		var root := mount(path)
		if root == null:
			continue
		for node in buttons_under(root):
			var button := node as Button
			var declared := button.custom_minimum_size.y
			if declared <= 0.0:
				continue
			assert_true(declared >= MIN_TOUCH_PX,
				"%s :: %s declares a %.0fpx tall touch target, under the %.0fpx minimum" % [
					path, path_of(button, root), declared, MIN_TOUCH_PX])
		unmount_all()


# --- the mobile brief --------------------------------------------------------

func test_no_control_hides_information_in_a_tooltip() -> void:
	# There is no hover on a phone, so tooltip-only text is unreachable on the
	# target platform. A tooltip may repeat what is already visible; it may not
	# be the only place something is said.
	for path in _all_scene_paths():
		var root := mount(path)
		if root == null:
			continue
		for node in descendants_of_type(root, "Control"):
			var control := node as Control
			var tip := control.tooltip_text.strip_edges()
			if tip == "":
				continue
			var visible_text := ""
			if control is Button:
				visible_text = (control as Button).text
			elif control is Label:
				visible_text = (control as Label).text
			assert_true(tip.to_upper() == visible_text.strip_edges().to_upper(),
				"%s :: %s says \"%s\" only in a tooltip, which a touchscreen never shows" % [
					path, path_of(control, root), tip])
		unmount_all()


func test_long_labels_can_wrap() -> void:
	# A fixed-height label with no wrapping clips rather than reflowing, and the
	# fight screen's corner grid was flagged for exactly this.
	for path in _all_scene_paths():
		var root := mount(path)
		if root == null:
			continue
		for node in descendants_of_type(root, "Label"):
			var label := node as Label
			if label.text.strip_edges().length() <= 24:
				continue
			assert_true(label.autowrap_mode != TextServer.AUTOWRAP_OFF,
				"%s :: %s holds %d characters with autowrap off" % [
					path, path_of(label, root), label.text.length()])
		unmount_all()


# --- routing -----------------------------------------------------------------

func test_every_router_screen_has_a_scene() -> void:
	# The bug this exists for: the title screen's SETTINGS button pushed an enum
	# value with no scene behind it, so the very first screen in the game had a
	# button that landed on "NOT BUILT YET".
	#
	# Four enum entries are genuinely out of this slice. They are listed rather
	# than skipped so that a NEW route to nowhere still fails here, and so the
	# list shrinks visibly as the screens get built.
	for value in Router.Screen.values():
		var screen_name: String = String(Router.Screen.keys()[value])
		if UNBUILT_SCREENS.has(screen_name):
			continue
		var path: String = Router.SCENE_PATHS.get(value, "")
		assert_true(path != "", "Router.Screen.%s has no path in SCENE_PATHS" % screen_name)
		if path == "":
			continue
		if ResourceLoader.exists(path):
			continue
		# The Router tolerates one known name drift; if that is what is
		# happening, say so precisely rather than just reporting it missing.
		var alias := path.replace("_screen.tscn", ".tscn")
		if alias != path and ResourceLoader.exists(alias):
			fail("Router.Screen.%s resolves only through the alias fallback (%s -> %s); rename the file" % [
				screen_name, path, alias])
		else:
			fail("Router.Screen.%s points at %s, which does not exist" % [screen_name, path])


func test_the_unbuilt_list_is_honest() -> void:
	# If someone builds one of these, this fails and the name comes off the list.
	for screen_name in UNBUILT_SCREENS:
		var value: int = Router.Screen.keys().find(screen_name)
		assert_true(value >= 0, "%s is on the unbuilt list but is not a Screen" % screen_name)
		if value < 0:
			continue
		var path: String = Router.SCENE_PATHS.get(value, "")
		assert_false(path != "" and ResourceLoader.exists(path),
			"%s is on the unbuilt list but %s now exists — take it off the list" % [
				screen_name, path])


func test_nothing_reachable_routes_to_an_unbuilt_screen() -> void:
	# An out-of-slice screen is fine. A visible, enabled button that lands the
	# player on the placeholder is not.
	var title := mount("res://ui/screens/title_screen.tscn")
	assert_not_null(title, "the title screen should mount")
	if title == null:
		return
	var settings := title.get_node_or_null("Menu/Settings") as Button
	assert_not_null(settings, "the title screen should still declare a settings entry")
	if settings != null:
		assert_false(settings.visible and not settings.disabled,
			"SETTINGS is live on the title screen but Router.Screen.SETTINGS has no scene")
