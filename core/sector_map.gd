class_name SectorMap
extends RefCounted

## One sector: a procedural graph of beacons connected by jumps.
##
## See docs/MISSION-ARCHITECTURE.md §7. This is the mutation of `core/ladder.gd`
## — rank climbing becomes depth reached — and `Ladder` itself is left intact and
## tested until an attended phase retires it (§2).
##
## THE SHAPE, AND WHY
##
## Beacons sit in columns. Every link goes FORWARD exactly one column, which is
## what makes the advancing threat a threat: there is no backtracking, so you
## cannot farm a sector while the menace closes. Column 0 holds the single entry
## beacon and the last column holds the single BOSS, so a sector always has a
## start and a gate.
##
## Generation is deterministic from (sector, seed) via the injected MpRng —
## `tests/unit/test_sector_map.gd` pins the eight invariants in §7 under several
## fixed seeds.

enum NodeKind { COMBAT, STORE, SAFE, DISTRESS, HAZARD, BOARDING, BOSS }

const KIND_LABELS: PackedStringArray = [
	"COMBAT", "STORE", "SAFE", "DISTRESS", "HAZARD", "BOARDING", "BOSS",
]

## DIVERGENCE: design §9 #4 — sector shape is [X]. Six columns: a single entry, a
## single boss, and four interior columns of 2..4 beacons each. That gives 14..18
## beacons.
##
## CORRECTION: an earlier version of this comment claimed 14..20 and argued that
## `Ship.FUEL_START` made "a greedy detour through every beacon" unaffordable.
## Both halves were wrong. 4 interior columns x MAX_COLUMN_WIDTH 4, plus the two
## terminals, is 18 — 20 was unreachable. And because every link advances exactly
## one column (see `generate`), EVERY route from entry to boss is exactly
## `COLUMNS - 1` jumps, so there is no such thing as a detour and route choice
## costs no fuel at all. See the note on FUEL below and §9 of
## docs/MORNING-REPORT.md.
const COLUMNS := 6
const ROWS := 4
const MIN_BEACONS := 14
const MAX_BEACONS := 18

## Beacons per interior column. Column 0 and the last column are always single.
## Capped by ROWS so a beacon can never be laid outside the declared grid — the
## two were previously equal only by coincidence.
const MIN_COLUMN_WIDTH := 2
const MAX_COLUMN_WIDTH := 4

## How many forward links a beacon tries for. More than one is what makes the map
## a graph rather than a corridor, and what gives the player a choice of WHICH
## beacon to visit next — though not, at present, a choice of route LENGTH.
const MIN_LINKS := 1
const MAX_LINKS := 3

## DIVERGENCE: design §9 #4 — beacon mix is [X]. Weighted so a sector reads as
## mostly danger punctuated by relief: roughly a third combat, with exactly the
## SAFE and STORE beacons a player needs to keep going. SAFE is where beacon
## training happens (design §3), so it must never be rare enough to starve the
## training loop.
const BASE_WEIGHTS: Dictionary = {
	NodeKind.COMBAT: 30.0,
	NodeKind.STORE: 12.0,
	NodeKind.SAFE: 18.0,
	NodeKind.DISTRESS: 16.0,
	NodeKind.HAZARD: 14.0,
	NodeKind.BOARDING: 10.0,
}

## Per-sector drift, added to the base weight per sector beyond the first.
## Deeper sectors get meaner: more combat and boarding, less shelter. Design §5
## says "Sector 1 ... Sector N (increasing danger)".
const DEPTH_DRIFT: Dictionary = {
	NodeKind.COMBAT: 6.0,
	NodeKind.STORE: -1.5,
	NodeKind.SAFE: -3.0,
	NodeKind.DISTRESS: 0.0,
	NodeKind.HAZARD: 1.5,
	NodeKind.BOARDING: 4.0,
}

## No weight ever falls below this, so no beacon type can vanish entirely from a
## deep sector — a sector with no SAFE node at all would silently switch off
## training and healing.
const MIN_WEIGHT := 2.0


class Beacon extends RefCounted:
	var index: int = 0
	var kind: NodeKind = NodeKind.COMBAT
	var column: int = 0
	var row: int = 0
	## Indices of beacons reachable by one jump. Always strictly forward.
	var links: Array[int] = []
	## The player has jumped here.
	var visited: bool = false
	## The player knows what is here (sensors, or having been adjacent).
	var explored: bool = false

	func kind_label() -> String:
		return SectorMap.KIND_LABELS[clampi(int(kind), 0, SectorMap.KIND_LABELS.size() - 1)]

	func to_dict() -> Dictionary:
		return {
			"index": index,
			"kind": int(kind),
			"column": column,
			"row": row,
			"links": links.duplicate(),
			"visited": visited,
			"explored": explored,
		}

	static func from_dict(d: Dictionary) -> Beacon:
		var beacon := Beacon.new()
		beacon.index = int(d.get("index", 0))
		beacon.kind = int(d.get("kind", NodeKind.COMBAT)) as NodeKind
		beacon.column = int(d.get("column", 0))
		beacon.row = int(d.get("row", 0))
		beacon.visited = bool(d.get("visited", false))
		beacon.explored = bool(d.get("explored", false))
		var raw: Variant = d.get("links", [])
		if raw is Array:
			for value in (raw as Array):
				beacon.links.append(int(value))
		return beacon


var sector: int = 1
var beacons: Array[Beacon] = []
var entry: int = 0
var boss: int = 0


## Build a sector. Same (sector, rng seed) always produces the same map.
static func generate(p_sector: int, rng: MpRng) -> SectorMap:
	var map := SectorMap.new()
	map.sector = maxi(1, p_sector)

	# 1. Lay out columns. First and last hold exactly one beacon each, so the
	#    sector has a single mouth and a single gate.
	var columns: Array = []
	for column in COLUMNS:
		var width := 1
		if column > 0 and column < COLUMNS - 1:
			width = rng.randi_range(MIN_COLUMN_WIDTH, mini(MAX_COLUMN_WIDTH, ROWS))
		var rows: Array[int] = []
		for row in width:
			rows.append(row)
		columns.append(rows)

	# 2. Trim or pad the interior until the total lands inside the contract's
	#    [MIN_BEACONS, MAX_BEACONS] window. Done deterministically, walking the
	#    interior columns in order, so no RNG is spent making the count legal.
	var total := _column_total(columns)
	var guard := 0
	while total > MAX_BEACONS and guard < 64:
		for column in range(1, COLUMNS - 1):
			var rows: Array[int] = columns[column]
			if rows.size() > MIN_COLUMN_WIDTH and total > MAX_BEACONS:
				rows.resize(rows.size() - 1)
				total -= 1
		guard += 1
	guard = 0
	while total < MIN_BEACONS and guard < 64:
		for column in range(1, COLUMNS - 1):
			var rows: Array[int] = columns[column]
			if rows.size() < MAX_COLUMN_WIDTH and total < MIN_BEACONS:
				rows.append(rows.size())
				total += 1
		guard += 1

	# 3. Materialise the beacons, column by column, so index order tracks depth.
	var by_column: Array = []
	for column in COLUMNS:
		var rows: Array[int] = columns[column]
		var indices: Array[int] = []
		for row in rows.size():
			var beacon := Beacon.new()
			beacon.index = map.beacons.size()
			beacon.column = column
			beacon.row = row
			map.beacons.append(beacon)
			indices.append(beacon.index)
		by_column.append(indices)

	map.entry = int((by_column[0] as Array[int])[0])
	map.boss = int((by_column[COLUMNS - 1] as Array[int])[0])

	# 4. Link forward. Two passes, because "everyone has an exit" and "everyone
	#    has an entrance" are different guarantees and both are required for the
	#    no-orphans invariant.
	for column in COLUMNS - 1:
		var here: Array[int] = by_column[column]
		var ahead: Array[int] = by_column[column + 1]
		# 4a. Every beacon gets at least one forward link.
		for index in here:
			var want := rng.randi_range(MIN_LINKS, mini(MAX_LINKS, ahead.size()))
			var pool := ahead.duplicate()
			for _i in want:
				if pool.is_empty():
					break
				var pick := int(pool[rng.randi_range(0, pool.size() - 1)])
				pool.erase(pick)
				if not map.beacons[index].links.has(pick):
					map.beacons[index].links.append(pick)
		# 4b. Every beacon in the next column gets at least one way in, or it
		#     would be unreachable — invariant 3.
		#
		#     Prefers a source that is still under MAX_LINKS, so that repairing
		#     reachability cannot push a beacon past the declared cap. Previously
		#     this appended to a source chosen at random regardless, which made
		#     MAX_LINKS not actually a maximum — a beacon could end up with four
		#     outbound links. Falls back to any source when every candidate is
		#     already full, because reachability (invariant 3) outranks the cap.
		for target in ahead:
			if map._has_inbound(target, here):
				continue
			var roomy: Array[int] = []
			for candidate in here:
				if map.beacons[candidate].links.size() < MAX_LINKS:
					roomy.append(candidate)
			var pool := roomy if not roomy.is_empty() else here
			var source := int(pool[rng.randi_range(0, pool.size() - 1)])
			map.beacons[source].links.append(target)

	for beacon in map.beacons:
		beacon.links.sort()

	# 5. Assign kinds. Entry is SAFE so a sector always opens somewhere you can
	#    draw breath; the last column is the BOSS and nothing else ever is.
	for beacon in map.beacons:
		if beacon.index == map.boss:
			beacon.kind = NodeKind.BOSS
		elif beacon.index == map.entry:
			beacon.kind = NodeKind.SAFE
		else:
			beacon.kind = map._roll_kind(rng)

	# Via `mark_visited` rather than by setting the two flags directly, so a freshly
	# generated chart also REVEALS the entry's forward links. Setting them by hand
	# left the player able to see where they were but not where they could go;
	# `Voyage._enter_sector` happened to paper over it by calling `mark_visited` a
	# moment later, which meant any other consumer — a map preview, a `from_dict`
	# path, any future non-Voyage caller — got a chart with no visible first choice.
	map.mark_visited(map.entry)
	return map


static func _column_total(columns: Array) -> int:
	var total := 0
	for rows in columns:
		total += (rows as Array).size()
	return total


func _has_inbound(target: int, sources: Array[int]) -> bool:
	for source in sources:
		if beacons[source].links.has(target):
			return true
	return false


## Weighted pick among the six non-boss kinds, drifting with sector depth.
func _roll_kind(rng: MpRng) -> NodeKind:
	var kinds: Array[int] = []
	var weights: Array[float] = []
	var total := 0.0
	for kind in BASE_WEIGHTS:
		var weight: float = float(BASE_WEIGHTS[kind])
		weight += float(DEPTH_DRIFT.get(kind, 0.0)) * float(sector - 1)
		weight = maxf(MIN_WEIGHT, weight)
		kinds.append(int(kind))
		weights.append(weight)
		total += weight

	var roll := rng.randf() * total
	var running := 0.0
	for index in kinds.size():
		running += weights[index]
		if roll < running:
			return kinds[index] as NodeKind
	return NodeKind.COMBAT


# --- queries: all PURE, no RNG ------------------------------------------------

func size() -> int:
	return beacons.size()


func beacon(index: int) -> Beacon:
	if index < 0 or index >= beacons.size():
		return null
	return beacons[index]


func neighbours(index: int) -> Array[int]:
	var found := beacon(index)
	if found == null:
		return []
	return found.links.duplicate()


func kind_of(index: int) -> NodeKind:
	var found := beacon(index)
	if found == null:
		return NodeKind.COMBAT
	return found.kind


func beacons_in_column(column: int) -> Array[int]:
	var out: Array[int] = []
	for item in beacons:
		if item.column == column:
			out.append(item.index)
	return out


func last_column() -> int:
	return COLUMNS - 1


func count_of_kind(kind: NodeKind) -> int:
	var total := 0
	for item in beacons:
		if item.kind == kind:
			total += 1
	return total


## Breadth-first, following links forward only.
func path_exists(from_index: int, to_index: int) -> bool:
	if beacon(from_index) == null or beacon(to_index) == null:
		return false
	if from_index == to_index:
		return true
	var seen: Array[int] = [from_index]
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next_index in beacons[current].links:
			if next_index == to_index:
				return true
			if seen.has(next_index):
				continue
			seen.append(next_index)
			queue.append(next_index)
	return false


## Every beacon reachable from `from_index`, itself excluded.
func reachable_from(from_index: int) -> Array[int]:
	var out: Array[int] = []
	if beacon(from_index) == null:
		return out
	var queue: Array[int] = [from_index]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next_index in beacons[current].links:
			if out.has(next_index):
				continue
			out.append(next_index)
			queue.append(next_index)
	out.sort()
	return out


## Invariant 3 as a callable check, so a test and a generator assertion can share
## one definition of "no orphans".
func all_reachable_from_entry() -> bool:
	var reachable := reachable_from(entry)
	for item in beacons:
		if item.index == entry:
			continue
		if not reachable.has(item.index):
			return false
	return true


func mark_visited(index: int) -> void:
	var found := beacon(index)
	if found == null:
		return
	found.visited = true
	found.explored = true
	# Arriving reveals where you could go next, which is what makes a route
	# choice a choice rather than a coin flip.
	for next_index in found.links:
		var ahead := beacon(next_index)
		if ahead != null:
			ahead.explored = true


static func kind_label(kind: NodeKind) -> String:
	return KIND_LABELS[clampi(int(kind), 0, KIND_LABELS.size() - 1)]


# --- serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	var out: Array = []
	for item in beacons:
		out.append(item.to_dict())
	return {
		"sector": sector,
		"entry": entry,
		"boss": boss,
		"beacons": out,
	}


static func from_dict(d: Dictionary) -> SectorMap:
	var map := SectorMap.new()
	map.sector = maxi(1, int(d.get("sector", 1)))
	map.entry = int(d.get("entry", 0))
	map.boss = int(d.get("boss", 0))
	var raw: Variant = d.get("beacons", [])
	if raw is Array:
		for entry_data in (raw as Array):
			if entry_data is Dictionary:
				map.beacons.append(Beacon.from_dict(entry_data as Dictionary))
	return map
