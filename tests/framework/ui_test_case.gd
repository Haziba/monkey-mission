class_name UiTestCase
extends TestCase

## Base class for tests that instantiate real screens.
##
## Until now the only assertion touching `ui/` was "the file parses", which let a
## button wired to nothing and a menu entry pointing at a scene that does not
## exist both ship. These helpers mount a real scene into the real tree so a test
## can press a real button.
##
## WHAT THIS CAN AND CANNOT SEE
##
## `add_child()` runs `_ready()` synchronously, so `@onready` vars resolve,
## signals connect and handlers work. Wiring, state and behaviour are testable.
##
## Do NOT reach for `is_inside_tree()` as a mounted-successfully check. The
## runner works inside `_initialize()`, before the SceneTree is running, and the
## flag reads false there even though `get_parent()` is the root window and
## `_ready` has already fired. Check `get_parent()` instead.
##
## It does NOT cover layout. Containers sort their children on a deferred call
## that needs an idle frame. Every `size` you read here is therefore the
## pre-layout value. Do not write assertions about where things ended up on
## screen — assert on `custom_minimum_size` and anchors, which are the values
## the author actually chose. Real visual verification still needs eyes on a
## window.

## Nodes mounted by this test, torn down in `after_each`.
var _mounted: Array[Node] = []


func tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


## Instantiate a scene and put it in the tree, so `_ready` runs.
func mount(scene_path: String) -> Node:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		fail("could not load scene %s" % scene_path)
		return null
	var node := packed.instantiate()
	if node == null:
		fail("could not instantiate %s" % scene_path)
		return null
	tree().root.add_child(node)
	_mounted.append(node)
	_force_ready(node)
	return node


## Deliver NOTIFICATION_READY depth-first, children before parents, which is the
## order Godot uses — a parent's `_ready` may reasonably assume its children have
## had theirs already.
##
## The `is_node_ready()` guard is load-bearing, not defensive: without it a node
## that HAS already readied gets `_ready()` a second time, every `connect()` in
## it raises "signal is already connected", and the screen ends up with doubled
## handlers. Skipping the ones already done keeps this idempotent.
func _force_ready(node: Node) -> void:
	for child in node.get_children():
		_force_ready(child)
	if not node.is_node_ready():
		node.notification(Node.NOTIFICATION_READY)


func unmount_all() -> void:
	for node in _mounted:
		if is_instance_valid(node):
			tree().root.remove_child(node)
			node.free()
	_mounted.clear()


func after_each() -> void:
	unmount_all()


## Every node of a given class under `root`, root included.
func descendants_of_type(root: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	if root.is_class(type_name):
		found.append(root)
	for child in root.get_children():
		found.append_array(descendants_of_type(child, type_name))
	return found


func buttons_under(root: Node) -> Array[Node]:
	return descendants_of_type(root, "Button")


## Press a button the way a player would: through its own signal, so whatever is
## connected to `pressed` runs.
func press(button: Button) -> void:
	button.pressed.emit()


## A path from the scene root, for failure messages that say which node is wrong.
func path_of(node: Node, root: Node) -> String:
	var parts: Array[String] = []
	var walk := node
	while walk != null and walk != root:
		parts.push_front(String(walk.name))
		walk = walk.get_parent()
	return "/".join(parts) if not parts.is_empty() else String(root.name)
