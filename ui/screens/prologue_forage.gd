extends GameScreen

## PROLOGUE 1/2 — THE LARDER. The drone runs the canopy collecting fruit.
##
## Design §1.5: the drone spends years after the cold open refitting a hull it
## was never issued. Before any of that it has to solve a simpler problem — it
## needs monkeys, and it has no hands to catch them with. So it does what it is
## actually built for: it goes and gets the bait.
##
## The minigame is a SIDE-SCROLLING flight through parallax jungle. Fruit hangs
## from trees on the right; enemy monkeys leap out from cover trying to steal
## from the trail behind you; branches want to knock you out of the sky.
##   * Touch on the LEFT half of the screen to set the drone's height.
##   * Double-tap on the left half for a boost — dodges monkeys, burns fuel.
##   * Fuel drains constantly. Health drops when you clip a branch.
##   * Collect 10 fruits and you fly home successful.
##   * Run out of health or fuel and you fly home with what you managed.
##
## ART IS STAND-IN ART (ARCHITECTURE §17). Every sprite is a generated component
## from `assets/placeholder/forage/` or `assets/placeholder/prologue/` — the two
## screens deliberately share the drone/canopy/fern set so they read as the same
## world. A missing file degrades to a flat shape rather than crashing.

enum Phase { FLYING, GOING_HOME, DONE }
## Sub-beats of the GOING_HOME phase. Only the success path uses STOP → WAIT →
## JIGGLE → BLAST; failure drifts on FAIL_DRIFT and finishes on a timer.
enum ReturnStep { NONE, STOP, WAIT, JIGGLE, BLAST, FAIL_DRIFT }

## Everything spawns at x = size.x + this margin and scrolls left. Enough to
## keep a big front-tree tile out of frame until it slides on.
const SPAWN_MARGIN := 400.0
## World scroll in pixels/second at reference height. `boost_factor` scales it.
const BASE_SCROLL := 520.0
const BOOST_SCROLL := 900.0
const BOOST_SECONDS := 1.6
const BOOST_COOLDOWN := 0.5
const DOUBLE_TAP_WINDOW := 0.28
## How far ahead of the home column a boost punches the drone, as a fraction
## of screen width, and how sharply it eases back afterwards.
const BOOST_OFFSET := 0.14
const BOOST_EASE := 4.5
## Vertical band the drone may occupy, as fractions of screen height.
const DRONE_MIN_Y := 0.18
const DRONE_MAX_Y := 0.78
const DRONE_X := 0.22
const DRONE_EASE := 8.0                ## higher = snappier
const DRONE_HEIGHT := 0.16
## Fuel and health, in "bar units". Both bars are drawn 0..1.
const FUEL_MAX := 100.0
const HEALTH_MAX := 100.0
const FUEL_DRAIN := 1.5                ## per second, flying normally
const FUEL_DRAIN_BOOST := 12.0         ## per second, while boosting
const BRANCH_DAMAGE := 22.0
const BRANCH_FRUIT_COST := 2
## Hit reaction — the drone flashes red and wobbles briefly so the player sees
## and feels the damage without a full knockback animation.
const HIT_FLASH_TIME := 0.55
const HIT_WOBBLE_TIME := 0.65
const HIT_WOBBLE_HZ := 22.0
const HIT_WOBBLE_AMP := 0.06         ## of screen height, at t=0
## The dangerous end of a branch is the bush of leaves at its tip. This is the
## half-extent of the hitbox in fractions of screen height, and also the drawn
## size of the bush — one number so the hitbox and the sprite can never drift.
const BUSH_HITBOX := 0.045
## The visible bush sits a fraction of a screen higher than the branch's
## anchor point (the sprite's bottom edge lands there, so the leaves are
## drawn above it). The hitbox is pushed up by this amount so it lines up
## with what the player is actually trying to dodge.
const BUSH_HITBOX_Y_OFFSET := -0.045
## Success celebration beats. STOP quickly kills scroll and the drone's boost
## offset; WAIT holds; JIGGLE bounces with an "!"; BLAST accelerates the drone
## off the right edge with the fruit trailing behind. Each in seconds.
const RETURN_STOP := 0.35
const RETURN_WAIT := 0.35
const RETURN_JIGGLE := 0.9
const RETURN_STOP_EASE := 12.0
## Drone acceleration during BLAST, in pixels/second/second of x-offset.
const BLAST_ACCEL := 2400.0
const BLAST_INITIAL := 250.0
## Target haul. Reaching this triggers success; running out of anything triggers
## the sad-return.
const TARGET_FRUIT := 10
## Trail behaviour: sample the drone's position every few frames and space the
## chain along it. Tight chain = a few short samples per fruit.
const TRAIL_SPACING := 30.0            ## pixels between chain segments
const TRAIL_SAMPLE_HZ := 60.0
## Enemy monkeys leap ballistically from cover. They hunt trail fruits.
const ENEMY_LEAP_TIME := 0.9
const ENEMY_REACH_R := 60.0
## Layout constants for the HUD.
const BAR_W := 0.30
const BAR_H := 34.0
const BAR_MARGIN := 42.0
## Seeded so the flight is the same every launch: this is the opening, not a
## roguelike node — a scripted opening that reshuffles feels broken.
const FLIGHT_SEED := 20260812
## Spawn cadences (seconds). Wider gaps make the flight readable; the boost
## pushes new spawns closer together because everything is coming at you faster.
const FRUIT_EVERY := 1.05
const BRANCH_EVERY := 3.6
const ENEMY_EVERY := 3.2
const PEEK_EVERY := 1.4
## AABB collision helper: fruit tap box, drone box, branch box are all pairs of
## (centre, half-extent). Static so a test can pin the rule.

const FRUIT_KINDS: PackedStringArray = ["banana", "mango", "peach"]
const PEEK_KINDS: PackedStringArray = ["peek_monkey", "peek_parrot", "peek_sloth"]

const ART_FORAGE := "res://assets/placeholder/forage/%s.png"
const ART_PROLOGUE := "res://assets/placeholder/prologue/%s.png"

@onready var _count: Label = $Count
@onready var _hint: Label = $Hint
@onready var _banner: Label = $Banner
@onready var _button: Button = $Button

var _phase: Phase = Phase.FLYING
var _return_step: ReturnStep = ReturnStep.NONE
var _return_step_t := 0.0
var _blast_vx := 0.0
var _t := 0.0
var _scroll := 0.0                     ## total pixels scrolled
var _boost_left := 0.0                 ## seconds of boost remaining
var _boost_cool := 0.0                 ## time since last tap (for double-tap)
var _last_tap_t := -10.0
var _fuel := FUEL_MAX
var _health := HEALTH_MAX
var _collected := 0                    ## fruit currently on the chain
var _brought := 0                      ## fruit that made it home
var _drone_y := 0.5
var _drone_target := 0.5
## X offset from DRONE_X, in pixels. Boost punches it forward; it eases back to
## zero afterwards. Kept separate from _drone_y because Y is player-driven and
## X is boost-driven.
var _drone_x_offset := 0.0
var _rng := MpRng.new(FLIGHT_SEED)
var _tex_cache: Dictionary = {}
var _screen_size := Vector2.ZERO

## Each entry: {"x": float, "y": float, "kind": String, "collected": bool, "pop": float}
var _fruit: Array[Dictionary] = []
## Each entry: {"x": float, "y": float}. Branches now hang from off-screen
## canopy with a bush of leaves at the bottom end — that bush IS the hazard;
## the stem itself has no hitbox.
var _branches: Array[Dictionary] = []
## Each entry: {"x0": float, "y0": float, "vx": float, "vy": float, "t": float,
##              "gone": bool, "stole": bool}
var _enemies: Array[Dictionary] = []
## Monkeys still hiding behind a tree, waiting to leap. They drift in with the
## world scroll and convert to a leaping `_enemies` entry once they reach a
## trigger X ahead of the drone.
## Each entry: {"x": float, "y": float, "leap_x": float, "gone": bool}.
var _hidden: Array[Dictionary] = []
## Hit-reaction timers, in seconds remaining. Both count down every step.
var _hit_flash := 0.0
var _hit_wobble := 0.0
## Fruits mid-fall after a monkey knocked them off the chain. They keep the
## world's leftward drift plus an upward kick, and gravity pulls them back.
## Each entry: {"pos": Vector2, "vx": float, "vy": float, "kind": String}.
var _falling: Array[Dictionary] = []
## Each entry: {"x": float, "y": float, "kind": String}. Peek animals are cosmetic.
var _peeks: Array[Dictionary] = []
## Sampled drone positions along the flight, each stamped with the world scroll
## at the sample moment so the trail can be laid out spatially instead of by
## sample index. The drone's X is fixed on-screen; the world moves past it —
## which means past samples have to be projected back through the scroll delta
## since then, or the whole chain clumps on top of the drone.
## Each entry: {"scroll": float, "y": float}.
var _trail_samples: Array[Dictionary] = []
## Which fruits are riding the chain, oldest first. Values are "banana"/"mango"/"peach".
var _chain: Array[String] = []

var _next_fruit := 0.8
var _next_branch := 2.0
var _next_enemy := 2.5
var _next_peek := 0.7
var _sample_accum := 0.0
## Extra spawn suppression right after the finish flag so the "home" phase does
## not throw a last banana at your face.
var _spawn_open := true
## Wall of dense front trees scrolls at 1.0x; use its scroll to phase-shift the
## sprite tiling. Two tile positions, wrapping across the screen.
var _tile_phase := 0.0


func _ready() -> void:
	super()
	for label in [_count, _hint, _banner]:
		label.add_theme_color_override("font_color", Palette.INK_LIGHT)
		label.add_theme_color_override("font_outline_color", Palette.INK)
		label.add_theme_constant_override("outline_size", 10)
	_count.add_theme_font_size_override("font_size", Palette.FONT_TITLE)
	_hint.add_theme_font_size_override("font_size", Palette.FONT_BODY)
	_banner.add_theme_font_size_override("font_size", Palette.FONT_HUGE)
	_banner.visible = false
	_button.visible = false
	_button.focus_mode = Control.FOCUS_NONE
	_button.pressed.connect(_on_button_pressed)
	_hint.text = "TOUCH LEFT SIDE TO STEER  ·  DOUBLE-TAP TO BOOST"
	_refresh_hud()
	set_process(true)
	resized.connect(_on_resized)


func on_enter(params: Dictionary) -> void:
	super(params)
	_reset()


func _on_resized() -> void:
	_screen_size = size


func _reset() -> void:
	_t = 0.0
	_scroll = 0.0
	_boost_left = 0.0
	_boost_cool = 0.0
	_last_tap_t = -10.0
	_fuel = FUEL_MAX
	_health = HEALTH_MAX
	_collected = 0
	_brought = 0
	_drone_y = 0.5
	_drone_target = 0.5
	_rng = MpRng.new(FLIGHT_SEED)
	_fruit.clear()
	_branches.clear()
	_enemies.clear()
	_hidden.clear()
	_peeks.clear()
	_chain.clear()
	_trail_samples.clear()
	_drone_x_offset = 0.0
	_hit_flash = 0.0
	_hit_wobble = 0.0
	_falling.clear()
	_next_fruit = 0.8
	_next_branch = 2.4
	_next_enemy = 3.2
	_next_peek = 0.6
	_spawn_open = true
	_phase = Phase.FLYING
	_return_step = ReturnStep.NONE
	_return_step_t = 0.0
	_blast_vx = 0.0
	_banner.visible = false
	_button.visible = false
	_hint.visible = true
	_refresh_hud()


# --- pure helpers, so a test can pin the rules -------------------------------

## Axis-aligned overlap: rects are (centre, half-extents). Pulled out because a
## drone/fruit/branch collision is the one rule a player can lose to and it
## should hold still under a test.
static func rects_overlap(a_centre: Vector2, a_half: Vector2,
		b_centre: Vector2, b_half: Vector2) -> bool:
	return absf(a_centre.x - b_centre.x) <= (a_half.x + b_half.x) \
		and absf(a_centre.y - b_centre.y) <= (a_half.y + b_half.y)


## Fuel drain per second at the current mode. Boosting is expensive on purpose —
## the boost has to cost more than moving the same distance without it, or the
## optimum play is to hold it down.
static func fuel_drain_for(boosting: bool) -> float:
	return FUEL_DRAIN_BOOST if boosting else FUEL_DRAIN


# --- input -------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	var at: Variant = _tap_position(event)
	if at == null:
		return
	get_viewport().set_input_as_handled()
	if _phase != Phase.FLYING:
		return
	var pos: Vector2 = at
	# The right half of the screen is intentionally not steering — that half is
	# where the world lives; touching it would be a natural miss-tap on a fruit.
	if pos.x > size.x * 0.5:
		return
	_drone_target = clampf(pos.y / size.y, DRONE_MIN_Y, DRONE_MAX_Y)
	if _t - _last_tap_t <= DOUBLE_TAP_WINDOW and _boost_cool <= 0.0 and _fuel > 5.0:
		_boost_left = BOOST_SECONDS
		_boost_cool = BOOST_COOLDOWN
		Sfx.play(Sfx.Cue.PUNCH)
	_last_tap_t = _t


func _tap_position(event: InputEvent) -> Variant:
	if event is InputEventScreenTouch and event.pressed:
		return (event as InputEventScreenTouch).position
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		return (event as InputEventMouseButton).position
	if event.is_action_pressed("mp_tap"):
		# Keyboard fallback: aim at the middle of the left column.
		return Vector2(size.x * 0.25, size.y * 0.5)
	return null


# --- the flight --------------------------------------------------------------

func _process(delta: float) -> void:
	if size != _screen_size:
		_screen_size = size
	_t += delta
	match _phase:
		Phase.FLYING:
			_step_flight(delta)
		Phase.GOING_HOME:
			_step_return(delta)
		Phase.DONE:
			pass
	queue_redraw()


func _step_flight(delta: float) -> void:
	# Boost timers first — the scroll speed and fuel drain both read them.
	if _boost_left > 0.0:
		_boost_left = maxf(_boost_left - delta, 0.0)
	if _boost_cool > 0.0:
		_boost_cool = maxf(_boost_cool - delta, 0.0)
	var boosting := _boost_left > 0.0
	var speed := BOOST_SCROLL if boosting else BASE_SCROLL
	_scroll += speed * delta
	# Fuel and drone motion.
	_fuel = maxf(_fuel - fuel_drain_for(boosting) * delta, 0.0)
	_drone_y = lerpf(_drone_y, _drone_target, clampf(DRONE_EASE * delta, 0.0, 1.0))
	# X-offset: boost punches forward, then eases back to the home column.
	var x_target := size.x * BOOST_OFFSET if boosting else 0.0
	_drone_x_offset = lerpf(_drone_x_offset, x_target, clampf(BOOST_EASE * delta, 0.0, 1.0))
	# Hit reaction timers.
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
	if _hit_wobble > 0.0:
		_hit_wobble = maxf(_hit_wobble - delta, 0.0)
	# Move the world.
	_move_all(speed * delta)
	_sample_trail(delta)
	_spawn(delta, boosting)
	_step_hidden()
	_step_enemies(delta)
	_step_falling(delta)
	_check_pickups()
	_check_branches()
	# End conditions.
	if _collected >= TARGET_FRUIT:
		_begin_return(true)
	elif _fuel <= 0.0 or _health <= 0.0:
		_begin_return(false)
	_refresh_hud()


func _move_all(step: float) -> void:
	for fruit in _fruit:
		fruit["x"] -= step
	for branch in _branches:
		branch["x"] -= step
	for peek in _peeks:
		peek["x"] -= step
	for hidden in _hidden:
		hidden["x"] -= step
	_tile_phase = fposmod(_tile_phase + step, size.x * 2.0)
	# Cull anything past the left edge, with a wide margin so a big tile stays
	# on-screen until its trailing edge is out.
	_fruit = _fruit.filter(func(f: Dictionary) -> bool: return f["x"] > -300.0)
	_branches = _branches.filter(func(b: Dictionary) -> bool: return b["x"] > -400.0)
	_peeks = _peeks.filter(func(p: Dictionary) -> bool: return p["x"] > -300.0)
	_hidden = _hidden.filter(func(h: Dictionary) -> bool:
		return not h["gone"] and h["x"] > -300.0)


func _sample_trail(delta: float) -> void:
	_sample_accum += delta
	var period := 1.0 / TRAIL_SAMPLE_HZ
	while _sample_accum >= period:
		_sample_accum -= period
		_trail_samples.push_front({"scroll": _scroll, "y": size.y * _drone_y})
	# Enough samples to cover the whole visible chain even at boost speed:
	# TARGET_FRUIT + a couple of spares, times how many samples one spacing
	# takes at slowest scroll. Cheap upper bound, fine.
	var cap := (TARGET_FRUIT + 4) * int(ceilf(TRAIL_SPACING / (BASE_SCROLL * period)))
	if _trail_samples.size() > cap:
		_trail_samples.resize(cap)


func _spawn(delta: float, boosting: bool) -> void:
	if not _spawn_open:
		return
	var scale := 0.7 if boosting else 1.0        ## more spawns when boosting
	_next_fruit -= delta
	if _next_fruit <= 0.0:
		_next_fruit = FRUIT_EVERY * _rng.randf_range(0.75, 1.35) * scale
		_fruit.append({
			"x": size.x + SPAWN_MARGIN,
			"y": _rng.randf_range(DRONE_MIN_Y + 0.05, DRONE_MAX_Y - 0.05) * size.y,
			"kind": FRUIT_KINDS[_rng.randi_range(0, FRUIT_KINDS.size() - 1)],
			"collected": false,
			"pop": 0.0,
		})
	_next_branch -= delta
	if _next_branch <= 0.0:
		_next_branch = BRANCH_EVERY * _rng.randf_range(0.6, 1.35)
		_branches.append({
			"x": size.x + SPAWN_MARGIN,
			"y": _rng.randf_range(DRONE_MIN_Y + 0.05, DRONE_MAX_Y - 0.05) * size.y,
		})
	_next_peek -= delta
	if _next_peek <= 0.0:
		_next_peek = PEEK_EVERY * _rng.randf_range(0.5, 1.6)
		_peeks.append({
			"x": size.x + SPAWN_MARGIN + _rng.randf_range(0.0, 200.0),
			# Peek animals sit in the upper canopy zone, where the mid parallax
			# and front trees actually overlap — anywhere lower and they float
			# in mid-air with no visible foliage to peek behind.
			"y": _rng.randf_range(0.22, 0.48) * size.y,
			"kind": PEEK_KINDS[_rng.randi_range(0, PEEK_KINDS.size() - 1)],
		})
	_next_enemy -= delta
	if _next_enemy <= 0.0:
		_next_enemy = ENEMY_EVERY * _rng.randf_range(0.75, 1.5)
		# An enemy only bothers if there's a trail worth stealing from — no chain,
		# no leap, or the first fruit gets stolen before it's even yours to lose.
		if _chain.size() >= 2:
			_spawn_hidden()


## Post a monkey hiding behind a tree that scrolls in from the right. He leaps
## once the world has carried him level with the drone.
func _spawn_hidden() -> void:
	var drone := _drone_pos()
	_hidden.append({
		"x": size.x + SPAWN_MARGIN,
		"y": _rng.randf_range(0.22, 0.38) * size.y,
		# Trigger somewhere ahead of the drone but on-screen, so the player
		# sees him break cover in time to react (boost, alt-tap, whatever).
		"leap_x": drone.x + _rng.randf_range(size.x * 0.30, size.x * 0.50),
		"gone": false,
	})


## Convert a hidden monkey into an in-flight leaper. Position and target are
## whatever the hidden entry was at the moment the trigger fired.
func _launch_leap(x0: float, y0: float) -> void:
	if _chain.is_empty():
		return
	var target_index: int = _rng.randi_range(0, _chain.size() - 1)
	var target := _trail_pos(target_index)
	# Ballistic: solve so the leap lands near target in ENEMY_LEAP_TIME.
	var vx: float = (target.x - x0) / ENEMY_LEAP_TIME
	var vy: float = (target.y - y0) / ENEMY_LEAP_TIME - 0.5 * 900.0 * ENEMY_LEAP_TIME
	_enemies.append({
		"x0": x0,
		"y0": y0,
		"vx": vx,
		"vy": vy,
		"t": 0.0,
		"gone": false,
		"stole": false,
	})


func _step_hidden() -> void:
	for hidden in _hidden:
		if hidden["gone"]:
			continue
		if hidden["x"] <= hidden["leap_x"]:
			_launch_leap(hidden["x"], hidden["y"])
			hidden["gone"] = true


func _step_enemies(delta: float) -> void:
	var speed := BOOST_SCROLL if _boost_left > 0.0 else BASE_SCROLL
	for enemy in _enemies:
		enemy["t"] += delta
		var pos := _enemy_pos(enemy)
		# Knock off EVERY chain fruit the monkey's body currently overlaps —
		# a leap that clips two fruits takes both, not just the closest one.
		# Walked back-to-front so remove_at doesn't shift indices under us.
		if _chain.size() > 0:
			for i in range(_chain.size() - 1, -1, -1):
				var fpos := _trail_pos(i)
				if pos.distance_to(fpos) < ENEMY_REACH_R:
					_knock_off(i, fpos, speed)
					enemy["stole"] = true
		if pos.x < -200.0 or pos.y > size.y + 200.0:
			enemy["gone"] = true
	_enemies = _enemies.filter(func(e: Dictionary) -> bool: return not e["gone"])


## Move fruit `chain_index` out of the chain and into the falling pile with an
## upward kick — it keeps the world's leftward drift and then arcs down under
## gravity, so the loss reads as physical.
func _knock_off(chain_index: int, at: Vector2, world_speed: float) -> void:
	var kind: String = _chain[chain_index]
	_chain.remove_at(chain_index)
	_collected = maxi(_collected - 1, 0)
	_falling.append({
		"pos": at,
		# Drifts with the world, plus a small horizontal jitter so a pair
		# knocked off together don't fall on top of each other.
		"vx": -world_speed + _rng.randf_range(-80.0, 80.0),
		"vy": _rng.randf_range(-560.0, -420.0),
		"kind": kind,
	})
	Sfx.play(Sfx.Cue.BLOCK)


func _step_falling(delta: float) -> void:
	for fruit in _falling:
		fruit["vy"] += 900.0 * delta
		fruit["pos"] += Vector2(fruit["vx"], fruit["vy"]) * delta
	_falling = _falling.filter(func(f: Dictionary) -> bool:
		return f["pos"].x > -120.0 and f["pos"].y < size.y + 120.0)


func _enemy_pos(enemy: Dictionary) -> Vector2:
	var t: float = enemy["t"]
	# Gravity in the ballistic sense — the leap has a peak and comes back down.
	return Vector2(
		enemy["x0"] + enemy["vx"] * t,
		enemy["y0"] + enemy["vy"] * t + 0.5 * 900.0 * t * t)


func _check_pickups() -> void:
	var drone := _drone_pos()
	var drone_half := Vector2(size.y * DRONE_HEIGHT * 0.5, size.y * DRONE_HEIGHT * 0.5)
	for fruit in _fruit:
		if fruit["collected"]:
			# Pop animation runs in place after collection.
			fruit["pop"] += get_process_delta_time()
			continue
		var fx: float = fruit["x"]
		var fy: float = fruit["y"]
		var half := Vector2(size.y * 0.06, size.y * 0.06)
		if rects_overlap(drone, drone_half, Vector2(fx, fy), half):
			fruit["collected"] = true
			fruit["pop"] = 0.001
			_chain.append(fruit["kind"])
			_collected += 1
			Sfx.play(Sfx.Cue.FEED)
	# Popped fruits leave once their animation ends.
	_fruit = _fruit.filter(func(f: Dictionary) -> bool:
		return not f["collected"] or f["pop"] < 0.35)


func _check_branches() -> void:
	var drone := _drone_pos()
	var drone_half := Vector2(size.y * DRONE_HEIGHT * 0.35, size.y * DRONE_HEIGHT * 0.35)
	for branch in _branches:
		if branch.get("hit", false):
			continue
		# Only the bush at the branch's tip is dangerous; the stem is scenery.
		var bush_half := size.y * BUSH_HITBOX
		var centre := Vector2(branch["x"],
			branch["y"] + size.y * BUSH_HITBOX_Y_OFFSET)
		var half := Vector2(bush_half, bush_half)
		if rects_overlap(drone, drone_half, centre, half):
			branch["hit"] = true
			_health = maxf(_health - BRANCH_DAMAGE, 0.0)
			var lose := mini(BRANCH_FRUIT_COST, _chain.size())
			for i in lose:
				_chain.pop_back()
				_collected = maxi(_collected - 1, 0)
			_hit_flash = HIT_FLASH_TIME
			_hit_wobble = HIT_WOBBLE_TIME
			Sfx.play(Sfx.Cue.KNOCKDOWN)


func _drone_pos() -> Vector2:
	return Vector2(size.x * DRONE_X + _drone_x_offset, size.y * _drone_y)


## Where chain fruit `i` lands on-screen. The drone stays in a fixed on-screen
## column, so trailing fruit sits at that column minus (i+1) spacings; the Y
## comes from the drone's height when the world was that far behind us.
func _trail_pos(chain_index: int) -> Vector2:
	var drone := _drone_pos()
	var want_ago := TRAIL_SPACING * float(chain_index + 1)
	var x := drone.x - want_ago
	if _trail_samples.is_empty():
		return Vector2(x, drone.y)
	for sample in _trail_samples:
		if _scroll - float(sample["scroll"]) >= want_ago:
			return Vector2(x, float(sample["y"]))
	# Not enough history yet — use the oldest y we've got.
	return Vector2(x, float(_trail_samples.back()["y"]))


func _begin_return(success: bool) -> void:
	_spawn_open = false
	_phase = Phase.GOING_HOME
	_brought = _collected
	_boost_left = 0.0
	_hint.visible = false
	_return_step_t = 0.0
	if success:
		_banner.text = "%d/%d  HEADING HOME" % [TARGET_FRUIT, TARGET_FRUIT]
		_return_step = ReturnStep.STOP
		Sfx.confirm()
	else:
		_banner.text = "LOW %s. HEADING HOME." % ("FUEL" if _fuel <= 0.0 else "HEALTH")
		_return_step = ReturnStep.FAIL_DRIFT
		Sfx.cancel()
	_banner.visible = true


func _step_return(delta: float) -> void:
	# Falling knock-off fruit keeps physics-ing across every return beat so a
	# fruit knocked loose right at the finish still visibly drops away.
	_step_falling(delta)
	_return_step_t += delta
	match _return_step:
		ReturnStep.FAIL_DRIFT:
			_drone_target = clampf(_drone_target - delta * 0.15, DRONE_MIN_Y, DRONE_MAX_Y)
			_drone_y = lerpf(_drone_y, _drone_target, clampf(DRONE_EASE * delta, 0.0, 1.0))
			_scroll_world(BASE_SCROLL * 0.5 * delta)
			if _return_step_t > 2.2:
				_finish()
		ReturnStep.STOP:
			# Everything decelerates to a halt inside RETURN_STOP. The scroll
			# eases with a linear ramp so the world stops in the same beat as
			# the drone's boost-offset does.
			var slow: float = BASE_SCROLL * (1.0 - clampf(_return_step_t / RETURN_STOP, 0.0, 1.0))
			_scroll_world(slow * delta)
			_drone_x_offset = lerpf(_drone_x_offset, 0.0,
				clampf(RETURN_STOP_EASE * delta, 0.0, 1.0))
			if _return_step_t >= RETURN_STOP:
				_return_step = ReturnStep.WAIT
				_return_step_t = 0.0
		ReturnStep.WAIT:
			# Half a beat of stillness — the "!" comes next.
			if _return_step_t >= RETURN_WAIT:
				_return_step = ReturnStep.JIGGLE
				_return_step_t = 0.0
		ReturnStep.JIGGLE:
			# Excited bounce around the drone's current altitude. Reset the
			# target so the ease in _step_flight doesn't fight it — but we're
			# not in flight, so bypass the ease and drive Y directly.
			_drone_y = clampf(_drone_target + sin(_return_step_t * 24.0) * 0.03,
				DRONE_MIN_Y, DRONE_MAX_Y)
			if _return_step_t >= RETURN_JIGGLE:
				_return_step = ReturnStep.BLAST
				_return_step_t = 0.0
				_blast_vx = BLAST_INITIAL
				Sfx.play(Sfx.Cue.PUNCH)
		ReturnStep.BLAST:
			# Drone accelerates rightward off-screen. Keep _boost_left topped
			# up so the jet blast + boost tint stay on the whole flight out.
			_boost_left = BOOST_SECONDS
			_blast_vx += BLAST_ACCEL * delta
			_drone_x_offset += _blast_vx * delta
			# Cut away only once the last chain fruit has also crossed the
			# right edge — the fruit trails behind and has to clear too.
			var chain_tail_x: float = size.x * DRONE_X + _drone_x_offset \
				- TRAIL_SPACING * float(maxi(_chain.size(), 1))
			if chain_tail_x > size.x + 120.0:
				_finish()
		_:
			pass


## Advance every world-space element by `step` pixels. Pulled out so a return
## beat can drive scroll from its own timeline without duplicating the loop.
func _scroll_world(step: float) -> void:
	_scroll += step
	_move_all(step)
	_sample_trail(step / maxf(BASE_SCROLL, 1.0))


func _finish() -> void:
	_phase = Phase.DONE
	_banner.visible = true
	var success := _brought >= TARGET_FRUIT
	_banner.text = "BROUGHT HOME: %d / %d" % [_brought, TARGET_FRUIT]
	_button.text = "NEXT STEP" if success else "RETRY"
	_button.visible = true
	_button.disabled = false
	_button.grab_focus()


func _on_button_pressed() -> void:
	if _brought >= TARGET_FRUIT:
		# Success — carry on to the trap screen with what we caught. Kept the
		# `bananas` param name for backward compatibility with prologue_trap.
		var params := enter_params.duplicate()
		params["bananas"] = _brought
		Router.replace(Router.Screen.PROLOGUE_TRAP, params)
	else:
		_reset()


func _refresh_hud() -> void:
	_count.text = "FRUIT  %d / %d" % [_collected, TARGET_FRUIT]


## Outline every hitbox the collision code actually uses. Debug menu switch.
## Colours: green = pickup, yellow = drone body, red = branch bush, magenta =
## enemy reach around a chain fruit.
func _draw_colliders() -> void:
	var drone := _drone_pos()
	var drone_half := size.y * DRONE_HEIGHT * 0.5
	draw_rect(Rect2(drone - Vector2(drone_half, drone_half),
		Vector2(drone_half, drone_half) * 2.0),
		Color(Palette.WARN, 0.9), false, 2.0)
	var pickup_half := size.y * 0.06
	for fruit in _fruit:
		if fruit["collected"]:
			continue
		var c := Vector2(fruit["x"], fruit["y"])
		draw_rect(Rect2(c - Vector2(pickup_half, pickup_half),
			Vector2(pickup_half, pickup_half) * 2.0),
			Color(Palette.GOOD, 0.9), false, 2.0)
	var bush_half := size.y * BUSH_HITBOX
	for branch in _branches:
		if branch.get("hit", false):
			continue
		var c := Vector2(branch["x"], branch["y"] + size.y * BUSH_HITBOX_Y_OFFSET)
		draw_rect(Rect2(c - Vector2(bush_half, bush_half),
			Vector2(bush_half, bush_half) * 2.0),
			Color(Palette.BAD, 0.9), false, 2.0)
	# Reach circle drawn around each chain fruit — a leaping monkey inside
	# this ring is close enough to knock the fruit off.
	for i in _chain.size():
		draw_arc(_trail_pos(i), ENEMY_REACH_R, 0.0, TAU, 24,
			Color(Palette.FRIENDSHIP, 0.85), 2.0)


# --- painting ----------------------------------------------------------------

func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	_draw_sky()
	# Back to front. Parallax speeds are baked in through _scroll and per-layer
	# multipliers, so the same _scroll drives everything. The far layer has sky
	# baked into its top half — running it from the very top covers the gradient
	# so the player never sees a slab of raw sky above the treeline.
	_draw_parallax("parallax_far", 0.10, 0.0, 0.75)
	_draw_parallax("parallax_mid", 0.35, 0.30, 0.55, true)
	# Peeks live between the mid canopy and the near trees so the front trees
	# eat the sides of their heads — which is what makes them read as peeking.
	for peek in _peeks:
		_draw_peek(peek)
	# Hidden monkeys sit BEHIND the front trees too, so the trunk sprite they
	# lug with them plus the front-trees layer both help sell the "hiding".
	for hidden in _hidden:
		_draw_hidden(hidden)
	_draw_parallax("front_trees", 1.0, 0.0, 1.0, true)
	# The fruit and branches physically live in the world at scroll speed 1.0
	# and belong in front of the trees they came off — otherwise a banana that
	# should occlude a trunk looks glued behind it.
	for fruit in _fruit:
		_draw_fruit(fruit)
	for branch in _branches:
		_draw_branch(branch)
	_draw_trail()
	for fruit in _falling:
		_draw_fallen(fruit)
	_draw_drone()
	for enemy in _enemies:
		_draw_enemy(enemy)
	# Foreground undergrowth blurs past — pure speed cue, doesn't hit anything.
	_draw_ferns()
	_draw_hud()
	if DebugMenu.show_colliders:
		_draw_colliders()


func _draw_sky() -> void:
	_gradient(Rect2(0.0, 0.0, size.x, size.y),
		Color(0.72, 0.86, 0.90), Color(0.36, 0.55, 0.44))


## Draw a horizontally-tileable strip along a band of the screen. `speed_mult`
## is how fast this layer scrolls relative to the world; `top` and `height` are
## fractions of the screen height. Two copies are drawn so one always covers the
## seam as the other wraps.
func _draw_parallax(art_name: String, speed_mult: float, top: float,
		height: float, tint_white := false) -> void:
	var tex := _tex(art_name)
	var band_h := size.y * height
	var band_y := size.y * top
	if tex == null:
		# Fallback: a solid band in a palette green so the layout still reads.
		var swatch := Palette.LOC_SHOP.darkened(0.35)
		if art_name == "parallax_far":
			swatch = Palette.LOC_PARK.darkened(0.5)
		elif art_name == "parallax_mid":
			swatch = Palette.LOC_PARK.darkened(0.2)
		draw_rect(Rect2(0.0, band_y, size.x, band_h), swatch)
		return
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var tile_w := band_h * aspect
	if tile_w <= 0.0:
		return
	var offset := fposmod(_scroll * speed_mult, tile_w)
	var tint := Color.WHITE if tint_white else Color(1, 1, 1, 1)
	var x := -offset
	while x < size.x:
		draw_texture_rect(tex, Rect2(x, band_y, tile_w, band_h), false, tint)
		x += tile_w


func _draw_peek(peek: Dictionary) -> void:
	_blit(_tex(peek["kind"]), Vector2(peek["x"], peek["y"]),
		size.y * 0.16, Palette.LOC_SHOP.darkened(0.4))


## A monkey lurking behind a tree, waiting to jump. The tree is a scaled
## `tree_trunk` sprite; the monkey is the leap sprite drawn HALF-visible — the
## side hidden by the tree is clipped, so only his head-and-arm poke out.
func _draw_hidden(hidden: Dictionary) -> void:
	var trunk_tex := _tex("tree_trunk")
	var monkey_tex := _tex("enemy_monkey")
	var trunk_h := size.y * 0.72
	var trunk_x: float = hidden["x"]
	var trunk_y: float = hidden["y"] + size.y * 0.10
	if trunk_tex != null:
		var t_aspect := float(trunk_tex.get_width()) / float(trunk_tex.get_height())
		var trunk_w := trunk_h * t_aspect
		draw_texture_rect(trunk_tex,
			Rect2(Vector2(trunk_x - trunk_w * 0.5, trunk_y - trunk_h),
				Vector2(trunk_w, trunk_h)), false,
			Palette.LOC_SHOP.darkened(0.1))
	else:
		draw_rect(Rect2(trunk_x - size.x * 0.018, trunk_y - trunk_h,
			size.x * 0.036, trunk_h), Palette.LOC_SHOP.darkened(0.3))
	var monkey_h := size.y * 0.18
	if monkey_tex == null:
		draw_circle(Vector2(trunk_x - size.x * 0.02, hidden["y"]),
			monkey_h * 0.3, Palette.BAD)
		return
	# The leap sprite faces right (arms extend right). We flip it to face left
	# and show only the LEFT half of the on-screen rect — the head and lead
	# arm poke out to the left of the trunk; the rest is behind the trunk.
	var m_aspect := float(monkey_tex.get_width()) / float(monkey_tex.get_height())
	var monkey_w := monkey_h * m_aspect
	var src_half := Rect2(0.0, 0.0,
		monkey_tex.get_width() * 0.5, monkey_tex.get_height())
	# Destination: sprite's left half, positioned just left of the trunk.
	var dst := Rect2(
		Vector2(trunk_x - monkey_w * 0.65, hidden["y"] - monkey_h * 0.5),
		Vector2(monkey_w * 0.5, monkey_h))
	# Negative width on the destination flips the drawn image horizontally.
	# Since we only want the head-half of the RIGHT-facing source, flipping
	# turns it into the head-half of a LEFT-facing monkey.
	dst.position.x += dst.size.x
	dst.size.x = -dst.size.x
	draw_texture_rect_region(monkey_tex, dst, src_half)


func _draw_fruit(fruit: Dictionary) -> void:
	var pos := Vector2(fruit["x"], fruit["y"])
	var h := size.y * 0.12
	var tint := Color.WHITE
	if fruit["collected"]:
		var p := clampf(fruit["pop"] / 0.35, 0.0, 1.0)
		h *= 1.0 + p * 0.9
		tint = Color(1, 1, 1, 1.0 - p)
		pos.y -= size.y * 0.06 * p
	var kind: String = fruit["kind"]
	var art: String = "banana_bunch" if kind == "banana" else kind
	_blit(_tex(art), pos, h, _fruit_colour(kind),
		false, Vector2(0.5, 0.5), tint)


func _fruit_colour(kind: String) -> Color:
	match kind:
		"mango":
			return Palette.ACCENT
		"peach":
			return Palette.FRIENDSHIP
		_:
			return Palette.LOGO_BLOB


func _draw_branch(branch: Dictionary) -> void:
	# The image is a stem tapering DOWN to a bush at the bottom. Anchor the
	# sprite so the bush centres on the branch's (x, y) — that same point IS
	# the hitbox, so what the player sees is what the collision uses.
	var bush := Vector2(branch["x"], branch["y"])
	var bush_r := size.y * BUSH_HITBOX
	var tex := _tex("branch_obstacle")
	if tex != null:
		var aspect := float(tex.get_width()) / float(tex.get_height())
		# Sprite height fills the whole stem: from off-screen canopy down to
		# the bush. Width follows aspect — the regenerated art is narrow-tall.
		var sprite_h := bush.y + bush_r
		var sprite_w := sprite_h * aspect
		# Pivot the sprite so its bottom edge lines up with the bush hitbox.
		draw_texture_rect(tex,
			Rect2(Vector2(bush.x - sprite_w * 0.5, bush.y + bush_r - sprite_h),
				Vector2(sprite_w, sprite_h)), false)
	else:
		# Fallback for a headless mount: a stem line + a green bush circle.
		draw_line(Vector2(bush.x, 0.0), bush,
			Palette.LOC_SHOP.darkened(0.3), 8.0)
		draw_circle(bush, bush_r, Palette.LOC_PARK.darkened(0.2))


func _draw_enemy(enemy: Dictionary) -> void:
	var pos := _enemy_pos(enemy)
	# The generated pose faces right; the leap always travels leftward toward
	# the drone, so flip so his outstretched arms lead the way.
	_blit(_tex("enemy_monkey"), pos, size.y * 0.20, Palette.BAD, true)


func _draw_drone() -> void:
	var bob := sin(_t * 6.0) * size.y * 0.008
	# Wobble on hit: high-frequency sinus that decays as the timer runs out.
	var wobble := 0.0
	if _hit_wobble > 0.0:
		var w_amt: float = _hit_wobble / HIT_WOBBLE_TIME
		wobble = sin(_t * TAU * HIT_WOBBLE_HZ) * size.y * HIT_WOBBLE_AMP * w_amt
	var pos := _drone_pos() + Vector2(0.0, bob + wobble)
	# Jet blast trails from the drone's tail while boost is active or the drone
	# is still catching up to its home column afterwards. Drawn BEFORE the drone
	# so the sprite sits on top of it.
	_draw_jet_blast(pos)
	var tint := Color.WHITE
	if _boost_left > 0.0:
		# A cyan tint over the drone during a boost — a cheap "you're going
		# faster now" without needing a particle system.
		tint = Palette.ACCENT_ALT.lerp(Color.WHITE, 0.4)
	if _hit_flash > 0.0:
		# Red-flash overwrites the boost tint on purpose: damage is louder than
		# speed and the player needs to see it before anything else.
		var f_amt: float = _hit_flash / HIT_FLASH_TIME
		tint = Color.WHITE.lerp(Palette.BAD, f_amt)
	# `flip = true` because the drone sprite faces left by default and the flight
	# travels rightward through the world.
	_blit(_tex("drone"), pos,
		size.y * DRONE_HEIGHT, Palette.PANEL_LIGHT, true, Vector2(0.5, 0.5), tint)
	if _return_step == ReturnStep.JIGGLE:
		_draw_excited(pos)


func _draw_excited(drone_pos: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	# A jaunty tilt on the "!" that flips each half-second so it reads as
	# animated even without a real motion pass.
	var text := "!"
	var glyph := Palette.FONT_HUGE
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph)
	var origin := drone_pos + Vector2(-text_size.x * 0.5,
		-size.y * DRONE_HEIGHT * 0.7 - text_size.y * 0.1)
	# Outline, then fill, so the mark reads over the canopy.
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph,
		8, Palette.INK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_CENTER, -1, glyph,
		Palette.WARN)


func _draw_jet_blast(pos: Vector2) -> void:
	# Only visible while boosting or during the ease-back. Strength scales with
	# how much boost is active, so it fades naturally as the drone settles.
	var strength := clampf(maxf(_boost_left / BOOST_SECONDS,
		_drone_x_offset / (size.x * BOOST_OFFSET + 0.01)), 0.0, 1.0)
	if strength <= 0.05:
		return
	var height := size.y * DRONE_HEIGHT * 0.45
	var length := size.y * DRONE_HEIGHT * (0.8 + 1.6 * strength)
	# Two overlapping triangles, hotter core inside a cooler flare. The tail
	# points LEFT because the drone faces right and thrust exits the rear.
	var tail := pos + Vector2(-size.y * DRONE_HEIGHT * 0.42, 0.0)
	var flare := PackedVector2Array([
		tail + Vector2(0.0, -height * 0.6),
		tail + Vector2(-length, 0.0),
		tail + Vector2(0.0, height * 0.6),
	])
	draw_colored_polygon(flare, Color(Palette.ACCENT, 0.55 * strength))
	var core := PackedVector2Array([
		tail + Vector2(0.0, -height * 0.3),
		tail + Vector2(-length * 0.6, 0.0),
		tail + Vector2(0.0, height * 0.3),
	])
	draw_colored_polygon(core, Color(Palette.WARN, 0.85 * strength))


func _draw_fallen(fruit: Dictionary) -> void:
	var kind: String = fruit["kind"]
	var art: String = "banana_bunch" if kind == "banana" else kind
	_blit(_tex(art), fruit["pos"], size.y * 0.075, _fruit_colour(kind))


func _draw_trail() -> void:
	# Rotate each fruit to follow the local slope of the chain — when the
	# drone dips or rises the whole string tilts, and the fruit swing with it.
	# Angle is taken from the segment behind this fruit (previous sample to
	# this one) rather than through it, so the chain looks pulled from ahead.
	var h := size.y * 0.075
	for i in _chain.size():
		var here := _trail_pos(i)
		var ahead := _drone_pos() if i == 0 else _trail_pos(i - 1)
		# Segment points from ahead to here. Since ahead is to the right (the
		# drone's column plus lower-index fruit), the natural resting angle is
		# 180°; subtract that so a flat chain draws sprite-upright.
		var angle := (here - ahead).angle() - PI
		_draw_rotated_fruit(_chain[i], here, h, angle)


func _draw_rotated_fruit(kind: String, at: Vector2, height: float, angle: float) -> void:
	var art: String = "banana_bunch" if kind == "banana" else kind
	var tex := _tex(art)
	if tex == null:
		draw_circle(at, height * 0.5, _fruit_colour(kind))
		return
	var aspect := float(tex.get_width()) / float(tex.get_height())
	var w := height * aspect
	draw_set_transform(at, angle, Vector2.ONE)
	draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, -height * 0.5),
		Vector2(w, height)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ferns() -> void:
	var tex := _tex("fern_bush")
	var h := size.y * 0.38
	# Four repeating ferns, offset by the world scroll to blur past the corners.
	for i in 5:
		var stride := size.x * 0.35
		# Foreground bushes streak past LEFT-to-right in the opposite direction
		# to the world, so the scroll term is subtracted. Previously added it,
		# which had them travelling backwards against everything else.
		var x := fposmod(-_scroll * 1.4 + float(i) * stride, size.x + stride * 2.0) - stride
		var flip := i % 2 != 0
		if tex != null:
			_blit(tex, Vector2(x, size.y + h * 0.10), h, Palette.LOC_PARK,
				flip, Vector2(0.5, 1.0))
		else:
			draw_rect(Rect2(x - h * 0.5, size.y - h * 0.6, h, h * 0.6),
				Palette.LOC_PARK.darkened(0.2))


func _draw_hud() -> void:
	var bar_w := size.x * BAR_W
	# Health bottom-left, fuel bottom-right.
	var h_pos := Vector2(BAR_MARGIN, size.y - BAR_MARGIN - BAR_H)
	_draw_bar(h_pos, bar_w, _health / HEALTH_MAX, Palette.GOOD, "HEALTH")
	var f_pos := Vector2(size.x - BAR_MARGIN - bar_w, size.y - BAR_MARGIN - BAR_H)
	_draw_bar(f_pos, bar_w, _fuel / FUEL_MAX, Palette.WARN, "FUEL")


func _draw_bar(pos: Vector2, w: float, frac: float, fill: Color, label: String) -> void:
	var bg_col := Palette.PANEL_DARK
	var bg := Rect2(pos, Vector2(w, BAR_H))
	draw_rect(bg, bg_col)
	draw_rect(bg, Palette.INK_LIGHT, false, 3.0)
	var fill_col := fill
	if frac < 0.25:
		fill_col = Palette.BAD
	draw_rect(Rect2(pos + Vector2(3.0, 3.0),
		Vector2((w - 6.0) * clampf(frac, 0.0, 1.0), BAR_H - 6.0)), fill_col)
	# The label is drawn as a text rect inside the bar so the HUD survives a
	# missing font — Font is set by the theme, so the default one is fine.
	var font := ThemeDB.fallback_font
	if font != null:
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			Palette.FONT_SMALL)
		draw_string(font, pos + Vector2(10.0, BAR_H * 0.5 + text_size.y * 0.25),
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, Palette.FONT_SMALL,
			Palette.INK_LIGHT)


# --- drawing helpers ---------------------------------------------------------
# Same pair as prologue_forage's original head-on version. Deliberately kept in
# the file rather than shared: the two prologue screens are the only callers.

func _blit(tex: Texture2D, at: Vector2, height: float, fallback: Color,
		flip := false, pivot := Vector2(0.5, 0.5), tint := Color.WHITE) -> void:
	if height <= 0.0:
		return
	var aspect := 1.0
	if tex != null and tex.get_height() > 0:
		aspect = float(tex.get_width()) / float(tex.get_height())
	var box := Rect2(at - Vector2(height * aspect * pivot.x, height * pivot.y),
		Vector2(height * aspect, height))
	if tex == null:
		draw_set_transform(box.get_center(), 0.0, box.size * 0.5)
		draw_circle(Vector2.ZERO, 1.0, Color(fallback, tint.a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	if flip:
		box.size.x = -box.size.x
	draw_texture_rect(tex, box, false, tint)


func _tex(art_name: String) -> Texture2D:
	if _tex_cache.has(art_name):
		return _tex_cache[art_name]
	# Prefer the forage set; fall back to the shared prologue set so drone/ferns
	# etc. resolve without duplicating art.
	for path in [ART_FORAGE % art_name, ART_PROLOGUE % art_name]:
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			_tex_cache[art_name] = tex
			return tex
	_tex_cache[art_name] = null
	return null


func _gradient(box: Rect2, top: Color, bottom: Color) -> void:
	var bands := 16
	var band_h := box.size.y / float(bands)
	for i in bands:
		draw_rect(Rect2(box.position.x, box.position.y + i * band_h,
			box.size.x, band_h + 1.0),
			top.lerp(bottom, float(i) / float(bands - 1)))
