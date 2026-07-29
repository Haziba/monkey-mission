extends TestCase

## core/sector_map.gd — the beacon graph. MISSION-ARCHITECTURE §7.
##
## §7 lists EIGHT invariants. Every one of them is named by number in the
## assertion messages below, and — apart from the statistical one — every one is
## checked under every seed in `SEEDS`. That looping is the point of this file: a
## procedural generator that satisfies its contract on one seed has satisfied
## nothing, and the failure mode of a map generator is not "wrong" but "wrong
## once in forty".
##
## THE THREE THINGS THIS FILE EXISTS TO PROTECT
##
##  1. **Links go forward exactly one column** (§7 #5). Everything about the
##     advancing threat in `Voyage` rests on this: `Voyage.threat_holds` decides
##     what the menace has eaten purely by comparing a beacon's column against
##     `threat_column`, so a single backward or column-skipping link would let the
##     player step back out of consumed space and the threat would stop being a
##     threat. It is pinned three ways — per link, per reachable pair, and via the
##     entry/boss terminals.
##  2. **No orphans and no dead ends** (§7 #3, #4). Reachability is verified
##     *independently* of `all_reachable_from_entry`, by a BFS written here over
##     `beacons`/`links` directly, so a bug in the helper cannot certify itself.
##     The mirror of it matters just as much: every beacon must still be able to
##     reach the boss, or the player can jump into a cul-de-sac and be stranded by
##     the map rather than by their own fuel spending.
##  3. **Determinism** (§7 #6). `MpRng.new(0)` seeds from the wall clock, so it is
##     never used here — every seed below is an explicit non-zero literal, and the
##     statistical sample derives its seeds arithmetically from a fixed base.
##
## NOTE on `MIN_BEACONS`/`MAX_BEACONS`: only the contract window is asserted, not
## the narrower window the current layout code happens to produce. Pinning the
## tighter range would freeze an implementation detail the contract does not own.

## Fixed, non-zero, arbitrary. Eight of them, so "holds for every seed" means
## something. Never `MpRng.new(0)` — that seeds from the clock and would make this
## whole file flaky.
const SEEDS: Array[int] = [
	1, 7, 4242, 20000324, 99991, 133337, 8675309, 2147483647,
]

## Every sector a voyage can actually reach (`Voyage.SECTORS == 3`).
const SECTORS_UNDER_TEST: Array[int] = [1, 2, 3]

## Invariant 8 is statistical and MUST NOT be asserted on a single seed. The
## sample size is explicit: 48 maps per sector, ~15 rolled beacons each, so ~700
## kind rolls per side. The predicted gaps are large (COMBAT+BOARDING 0.40 ->
## 0.53, SAFE+STORE 0.30 -> 0.18) against a standard error near 0.02, so this is a
## multi-sigma comparison rather than a coin flip.
const STAT_SAMPLE_SEEDS := 48
const STAT_SEED_BASE := 900001
## Prime stride, so consecutive sample seeds are not neighbouring integers.
const STAT_SEED_STRIDE := 7919
## The smallest share gap that counts as the weight table drifting rather than
## sampling noise. Both predicted gaps are over twice this.
const STAT_MIN_GAP := 0.05

## Enough read-only polls that one leaked RNG draw per call cannot coincidentally
## land the stream back where it started. Matches tests/unit/test_ship.gd.
const POLLS := 5


# --- fixtures --------------------------------------------------------------

func _map(seed_value: int, p_sector: int = 1) -> SectorMap:
	return SectorMap.generate(p_sector, MpRng.new(seed_value))


func _where(seed_value: int, p_sector: int) -> String:
	return "seed %d, sector %d" % [seed_value, p_sector]


## Reachability computed HERE, walking `beacons`/`links` directly rather than
## through `neighbours()`, `reachable_from()` or `path_exists()`. Invariant 3 is a
## claim about the generated data and must not be certified by the same code it is
## a claim about.
func _bfs_from(map: SectorMap, start: int) -> Array[int]:
	var found: Array[int] = []
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		if current < 0 or current >= map.beacons.size():
			continue
		var here: SectorMap.Beacon = map.beacons[current]
		for raw in here.links:
			var next_index := int(raw)
			if found.has(next_index):
				continue
			found.append(next_index)
			queue.append(next_index)
	found.sort()
	return found


## How many links point AT each beacon.
func _inbound_counts(map: SectorMap) -> Dictionary:
	var counts: Dictionary = {}
	for b: SectorMap.Beacon in map.beacons:
		counts[b.index] = int(counts.get(b.index, 0))
	for b: SectorMap.Beacon in map.beacons:
		for raw in b.links:
			var target := int(raw)
			counts[target] = int(counts.get(target, 0)) + 1
	return counts


func _stat_seed(i: int) -> int:
	return STAT_SEED_BASE + i * STAT_SEED_STRIDE


## Kind counts across `STAT_SAMPLE_SEEDS` maps of one sector, counting only the
## beacons whose kind was actually ROLLED — entry is forced SAFE and the boss is
## forced BOSS, and including them would drag a constant into a comparison that is
## only about the weight table.
func _rolled_kind_tally(p_sector: int) -> Dictionary:
	var tally: Dictionary = {"_total": 0}
	for kind in SectorMap.BASE_WEIGHTS:
		tally[int(kind)] = 0
	for i in STAT_SAMPLE_SEEDS:
		var map: SectorMap = _map(_stat_seed(i), p_sector)
		for b: SectorMap.Beacon in map.beacons:
			if b.index == map.entry or b.index == map.boss:
				continue
			tally[int(b.kind)] = int(tally.get(int(b.kind), 0)) + 1
			tally["_total"] = int(tally["_total"]) + 1
	return tally


func _share(tally: Dictionary, kinds: Array[int]) -> float:
	var total := int(tally["_total"])
	if total <= 0:
		return 0.0
	var sum := 0
	for kind in kinds:
		sum += int(tally.get(kind, 0))
	return float(sum) / float(total)


func _count(tally: Dictionary, kinds: Array[int]) -> int:
	var sum := 0
	for kind in kinds:
		sum += int(tally.get(kind, 0))
	return sum


## `to_dict()` as a string, because "byte-identical" is what §7 #6 asks for and
## because Dictionary equality in GDScript is not a thing to lean on.
func _fingerprint(map: SectorMap) -> String:
	return JSON.stringify(map.to_dict())


## Every read-only question on the map, called `times` times.
func _poll(map: SectorMap, times: int) -> void:
	for _i in times:
		map.size()
		map.last_column()
		map.all_reachable_from_entry()
		map.reachable_from(map.entry)
		map.path_exists(map.entry, map.boss)
		for column in SectorMap.COLUMNS:
			map.beacons_in_column(column)
		for kind in SectorMap.KIND_LABELS.size():
			map.count_of_kind(kind as SectorMap.NodeKind)
		for b: SectorMap.Beacon in map.beacons:
			map.beacon(b.index)
			map.neighbours(b.index)
			map.kind_of(b.index)


# --- invariant 1: one mouth, one gate --------------------------------------

func test_invariant_1_entry_is_the_only_beacon_in_column_zero() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var first: Array[int] = map.beacons_in_column(0)
			assert_eq(first.size(), 1,
				"invariant 1 (%s): column 0 must hold exactly one beacon, or a sector has more than one mouth and `entry` stops meaning anything — held %s" % [
					_where(seed_value, p_sector), first])
			assert_has(first, map.entry,
				"invariant 1 (%s): the single column-0 beacon must be `entry` itself" % _where(seed_value, p_sector))
			var entry_beacon: SectorMap.Beacon = map.beacon(map.entry)
			assert_not_null(entry_beacon,
				"invariant 1 (%s): `entry` must index a real beacon" % _where(seed_value, p_sector))
			assert_eq(entry_beacon.column, 0,
				"invariant 1 (%s): `entry` must sit in column 0 — the threat starts at column %d and would already hold it otherwise" % [
					_where(seed_value, p_sector), Voyage.THREAT_START_COLUMN])


func test_invariant_1_boss_is_the_only_beacon_in_the_last_column() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var last: Array[int] = map.beacons_in_column(map.last_column())
			assert_eq(last.size(), 1,
				"invariant 1 (%s): the last column must hold exactly one beacon, or a sector has two gates and the player can pick the one without the boss — held %s" % [
					_where(seed_value, p_sector), last])
			assert_has(last, map.boss,
				"invariant 1 (%s): the single last-column beacon must be `boss`" % _where(seed_value, p_sector))
			assert_eq(map.beacon(map.boss).column, map.last_column(),
				"invariant 1 (%s): `boss` must sit in the last column, or `enter_next_sector` gates on the wrong beacon" % _where(seed_value, p_sector))
			assert_ne(map.entry, map.boss,
				"invariant 1 (%s): entry and boss must be different beacons, or a sector is over before it starts" % _where(seed_value, p_sector))


func test_invariant_1_the_declared_columns_partition_the_map_and_none_is_empty() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var counted := 0
			for column in SectorMap.COLUMNS:
				var here: Array[int] = map.beacons_in_column(column)
				counted += here.size()
				assert_true(here.size() >= 1,
					"invariant 1 (%s): column %d is empty. An empty interior column severs the graph and makes the boss unreachable" % [
						_where(seed_value, p_sector), column])
			assert_eq(counted, map.size(),
				"invariant 1 (%s): columns 0..%d must account for every beacon — one outside the declared grid is invisible to `beacons_in_column`, so invisible to both the map screen and the threat" % [
					_where(seed_value, p_sector), SectorMap.COLUMNS - 1])
			for column in range(1, SectorMap.COLUMNS - 1):
				var width: int = map.beacons_in_column(column).size()
				assert_in_range(width, SectorMap.MIN_COLUMN_WIDTH, SectorMap.MAX_COLUMN_WIDTH,
					"invariant 7 (%s): interior column %d holds %d beacons, outside [%d, %d] — the passes that trim and pad the count to fit the beacon window must never push a column outside its own band" % [
						_where(seed_value, p_sector), column, width,
						SectorMap.MIN_COLUMN_WIDTH, SectorMap.MAX_COLUMN_WIDTH])


# --- invariant 2: exactly one boss ----------------------------------------

func test_invariant_2_the_boss_beacon_is_the_only_boss_kind() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			assert_eq(int(map.kind_of(map.boss)), int(SectorMap.NodeKind.BOSS),
				"invariant 2 (%s): the beacon at `boss` must be kind BOSS, or the sector's gate is an ordinary stop and nothing ever gates it" % _where(seed_value, p_sector))
			assert_eq(map.count_of_kind(SectorMap.NodeKind.BOSS), 1,
				"invariant 2 (%s): exactly one beacon may be BOSS — a second is a second sector-ending fight, and `Voyage.at_boss` only recognises `map.boss`" % _where(seed_value, p_sector))
			for b: SectorMap.Beacon in map.beacons:
				if b.index == map.boss:
					continue
				assert_ne(int(b.kind), int(SectorMap.NodeKind.BOSS),
					"invariant 2 (%s): beacon %d in column %d is BOSS but is not `map.boss`" % [
						_where(seed_value, p_sector), b.index, b.column])
			var summed := 0
			for kind in SectorMap.KIND_LABELS.size():
				summed += map.count_of_kind(kind as SectorMap.NodeKind)
			assert_eq(summed, map.size(),
				"invariant 2 (%s): every beacon must carry exactly one declared kind — `count_of_kind` summing to %d against %d beacons means a kind outside the enum" % [
					_where(seed_value, p_sector), summed, map.size()])


# --- invariant 3: no orphans ----------------------------------------------

func test_invariant_3_every_beacon_is_reachable_from_entry() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			assert_true(map.all_reachable_from_entry(),
				"invariant 3 (%s): `all_reachable_from_entry` must be true — an orphaned beacon is content the player can never spend fuel to see" % _where(seed_value, p_sector))
			var reachable: Array[int] = map.reachable_from(map.entry)
			for b: SectorMap.Beacon in map.beacons:
				if b.index == map.entry:
					continue
				assert_has(reachable, b.index,
					"invariant 3 (%s): beacon %d (column %d) is unreachable from `entry`" % [
						_where(seed_value, p_sector), b.index, b.column])


func test_invariant_3_reachability_holds_under_an_independent_search() -> void:
	# Deliberately does NOT trust `reachable_from` / `all_reachable_from_entry`.
	# The search is written out in `_bfs_from` over `beacons`/`links` and the two
	# answers are compared, so a bug in the helper shows up as a disagreement
	# rather than as a green test.
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var mine: Array[int] = _bfs_from(map, map.entry)
			assert_eq(mine.size(), map.size() - 1,
				"invariant 3 (%s): an independent BFS from `entry` must find every OTHER beacon — found %d of %d" % [
					_where(seed_value, p_sector), mine.size(), map.size() - 1])
			var theirs: Array[int] = map.reachable_from(map.entry)
			assert_eq(mine, theirs,
				"invariant 3 (%s): `reachable_from(entry)` disagrees with an independent BFS, so one of them is lying about the graph (helper %s, BFS %s)" % [
					_where(seed_value, p_sector), theirs, mine])


func test_invariant_3_reachable_from_excludes_itself_and_is_sorted_and_unique() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		assert_not_has(map.reachable_from(map.entry), map.entry,
			"invariant 3 (seed %d): `reachable_from` is documented as excluding its own start; `entry` coming back would mean a cycle exists and invariant 5 is already broken" % seed_value)
		for b: SectorMap.Beacon in map.beacons:
			var found: Array[int] = map.reachable_from(b.index)
			assert_not_has(found, b.index,
				"invariant 3 (seed %d): `reachable_from(%d)` must not contain %d — a beacon reachable from itself is a loop the player could farm inside while the threat closed" % [
					seed_value, b.index, b.index])
			var previous := -1
			for index in found:
				assert_true(index > previous,
					"invariant 3 (seed %d): `reachable_from(%d)` must come back sorted and duplicate-free for a UI to diff it, but %d followed %d in %s" % [
						seed_value, b.index, index, previous, found])
				previous = index


func test_invariant_3_every_beacon_except_the_entry_has_an_inbound_link() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var inbound := _inbound_counts(map)
			for b: SectorMap.Beacon in map.beacons:
				if b.index == map.entry:
					continue
				assert_true(int(inbound.get(b.index, 0)) >= 1,
					"invariant 3 (%s): beacon %d (column %d, %s) has no inbound link, so it is an orphan no amount of fuel can reach" % [
						_where(seed_value, p_sector), b.index, b.column, b.kind_label()])


# --- invariant 4: the boss is always reachable ----------------------------

func test_invariant_4_a_path_from_entry_to_boss_always_exists() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			assert_true(map.path_exists(map.entry, map.boss),
				"invariant 4 (%s): there must always be a route from `entry` to `boss`, or the sector is unwinnable however well the player plays" % _where(seed_value, p_sector))


func test_invariant_4_every_beacon_can_still_reach_the_boss() -> void:
	# The mirror of invariant 4, and the half that actually protects the player: a
	# beacon from which the boss is unreachable is a cul-de-sac they can burn fuel
	# jumping into, after which `Voyage.check_end` can only ever say STRANDED.
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			for b: SectorMap.Beacon in map.beacons:
				assert_true(map.path_exists(b.index, map.boss),
					"invariant 4 (%s): beacon %d (column %d, %s) cannot reach the boss — it is a dead end the player can jump into and be stranded in" % [
						_where(seed_value, p_sector), b.index, b.column, b.kind_label()])


func test_invariant_4_every_beacon_except_the_boss_offers_at_least_one_route() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			for b: SectorMap.Beacon in map.beacons:
				if b.index == map.boss:
					continue
				assert_true(b.links.size() >= SectorMap.MIN_LINKS,
					"invariant 4 (%s): beacon %d (column %d) has no outbound link — the player jumps in and then has nowhere to go, which is a map-authored stranding rather than a chosen one" % [
						_where(seed_value, p_sector), b.index, b.column])
				# `MAX_LINKS` is what a beacon *tries* for, not a cap the generator
				# enforces: the pass that guarantees every beacon an inbound link
				# can push a source past it. The real ceiling is the next column.
				var ahead: int = map.beacons_in_column(b.column + 1).size()
				assert_in_range(b.links.size(), SectorMap.MIN_LINKS, ahead,
					"invariant 5 (%s): beacon %d in column %d offers %d routes but column %d holds only %d beacons, so a link is duplicated or points off the grid" % [
						_where(seed_value, p_sector), b.index, b.column, b.links.size(), b.column + 1, ahead])


func test_invariant_4_path_exists_is_reflexive_and_agrees_with_reachable_from() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		for b: SectorMap.Beacon in map.beacons:
			assert_true(map.path_exists(b.index, b.index),
				"invariant 4 (seed %d): `path_exists(%d, %d)` must be true — you are already where you are, and `Voyage` leans on that when it checks the boss beacon it is parked on" % [
					seed_value, b.index, b.index])
			var reachable: Array[int] = map.reachable_from(b.index)
			for other: SectorMap.Beacon in map.beacons:
				if other.index == b.index:
					continue
				assert_eq(map.path_exists(b.index, other.index), reachable.has(other.index),
					"invariant 4 (seed %d): `path_exists(%d, %d)` and `reachable_from(%d)` must answer the same question the same way" % [
						seed_value, b.index, other.index, b.index])


# --- invariant 5: forward exactly one column, always ---------------------

func test_invariant_5_every_link_goes_forward_exactly_one_column() -> void:
	# THE most important assertion in this file. `Voyage.threat_holds` decides what
	# the menace has eaten purely by comparing columns, so one sideways or backward
	# link would let the player walk out of consumed space and the threat would
	# stop being inescapable.
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			for b: SectorMap.Beacon in map.beacons:
				for raw in b.links:
					var target := int(raw)
					var ahead: SectorMap.Beacon = map.beacon(target)
					assert_not_null(ahead,
						"invariant 5 (%s): beacon %d links to %d, which is not a beacon at all" % [
							_where(seed_value, p_sector), b.index, target])
					if ahead == null:
						continue
					assert_eq(ahead.column, b.column + 1,
						"invariant 5 (%s): beacon %d (column %d) links to %d (column %d) — every link must go forward EXACTLY one column, or the advancing threat becomes escapable" % [
							_where(seed_value, p_sector), b.index, b.column, target, ahead.column])


func test_invariant_5_no_reachable_pair_ever_goes_backwards_or_sideways() -> void:
	# Per-link forwardness is not quite enough on its own: what `Voyage` needs is
	# that no SEQUENCE of jumps regains ground, so this checks every reachable
	# ordered pair rather than every edge.
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		for from_beacon: SectorMap.Beacon in map.beacons:
			for to_beacon: SectorMap.Beacon in map.beacons:
				if from_beacon.index == to_beacon.index:
					continue
				if not map.path_exists(from_beacon.index, to_beacon.index):
					continue
				assert_true(to_beacon.column > from_beacon.column,
					"invariant 5 (seed %d): a path runs from beacon %d (column %d) to %d (column %d) — reachability must be strictly forward, so no chain of jumps can ever regain ground the threat has taken" % [
						seed_value, from_beacon.index, from_beacon.column, to_beacon.index, to_beacon.column])


func test_invariant_5_the_entry_is_a_source_and_the_boss_is_a_terminus() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var inbound := _inbound_counts(map)
			assert_eq(int(inbound.get(map.entry, -1)), 0,
				"invariant 5 (%s): nothing may link back to `entry` — the mouth of a sector is behind the player forever" % _where(seed_value, p_sector))
			assert_true(map.neighbours(map.boss).is_empty(),
				"invariant 5 (%s): the boss sits in the last column, so it must have no outbound links — anything past it would be a seventh column" % _where(seed_value, p_sector))
			assert_false(map.path_exists(map.boss, map.entry),
				"invariant 5 (%s): there must be no route from the boss back to the entry" % _where(seed_value, p_sector))


func test_invariant_5_links_are_unique_never_self_referential_and_sorted() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			for b: SectorMap.Beacon in map.beacons:
				var previous := -1
				for raw in b.links:
					var target := int(raw)
					assert_ne(target, b.index,
						"invariant 5 (%s): beacon %d links to itself, which is a zero-column jump that burns fuel for nothing" % [
							_where(seed_value, p_sector), b.index])
					assert_true(target > previous,
						"invariant 5/6 (%s): beacon %d's links must be sorted and duplicate-free so `options()` hands the UI a stable order and `to_dict` is reproducible, but got %s" % [
							_where(seed_value, p_sector), b.index, b.links])
					previous = target


# --- invariant 6: determinism --------------------------------------------

func test_invariant_6_same_seed_and_sector_produce_an_identical_map() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var first := _fingerprint(_map(seed_value, p_sector))
			var second := _fingerprint(_map(seed_value, p_sector))
			assert_eq(first, second,
				"invariant 6 (%s): the same seed and sector must produce a byte-identical `to_dict()`, or a save cannot be resumed and no bug in a generated map is ever reproducible" % _where(seed_value, p_sector))


func test_invariant_6_generation_leaves_the_rng_stream_in_a_reproducible_place() -> void:
	# Determinism is not only about the map. `Voyage` keeps generating from the
	# same injected stream, so two identical generations must also consume
	# identically many draws or everything AFTER the first sector diverges.
	for seed_value in SEEDS:
		var left := MpRng.new(seed_value)
		var right := MpRng.new(seed_value)
		SectorMap.generate(2, left)
		SectorMap.generate(2, right)
		assert_eq(left.state(), right.state(),
			"invariant 6 (seed %d): two identical generations must consume the same number of RNG draws, or every later sector of a resumed voyage diverges" % seed_value)
		var untouched := MpRng.new(seed_value)
		assert_ne(left.state(), untouched.state(),
			"invariant 6 (seed %d): `generate` must actually draw from the injected MpRng — an unchanged stream state would mean the map is not random at all" % seed_value)


func test_invariant_6_different_seeds_and_different_sectors_give_different_maps() -> void:
	var fingerprints: Array[String] = []
	for seed_value in SEEDS:
		var mark := _fingerprint(_map(seed_value, 1))
		assert_not_has(fingerprints, mark,
			"invariant 6: seed %d produced a map identical to an earlier seed's. With ~15 beacons of independently rolled kinds and links a genuine collision is astronomically unlikely, so this means the generator is ignoring its MpRng" % seed_value)
		fingerprints.append(mark)
	assert_eq(fingerprints.size(), SEEDS.size(),
		"invariant 6: all %d seeds must give distinct maps, or seeding buys the player nothing" % SEEDS.size())
	for seed_value in SEEDS:
		assert_ne(_fingerprint(_map(seed_value, 1)), _fingerprint(_map(seed_value, 3)),
			"invariant 6/8 (seed %d): sector depth must change the generated map, or `sector` is a label the generator never reads" % seed_value)


# --- invariant 7: beacon count and grid ---------------------------------

func test_invariant_7_beacon_count_is_inside_the_contract_window() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			assert_in_range(map.size(), SectorMap.MIN_BEACONS, SectorMap.MAX_BEACONS,
				"invariant 7 (%s): beacon count %d is outside [%d, %d]. The window is what makes fuel a decision — `Ship.FUEL_START` is %d, so a direct line must fit and a greedy tour must not" % [
					_where(seed_value, p_sector), map.size(), SectorMap.MIN_BEACONS, SectorMap.MAX_BEACONS, Ship.FUEL_START])
			assert_eq(map.beacons.size(), map.size(),
				"invariant 7 (%s): `size()` must report the real beacon array length" % _where(seed_value, p_sector))


func test_invariant_7_grid_coordinates_are_dense_ordered_and_never_collide() -> void:
	# `to_dict` serialises beacons positionally and every link is an index, so
	# index == array position is load-bearing for saves. Columns being
	# non-decreasing in index is what lets "index order tracks depth" be relied on.
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var previous_column := -1
			var occupied: Dictionary = {}
			for i in map.beacons.size():
				var b: SectorMap.Beacon = map.beacons[i]
				assert_eq(b.index, i,
					"invariant 7 (%s): the beacon at array position %d reports index %d — every link, save and query treats the index as the array position" % [
						_where(seed_value, p_sector), i, b.index])
				assert_true(b.column >= previous_column,
					"invariant 7 (%s): beacon %d dropped back to column %d after column %d — index order must track depth" % [
						_where(seed_value, p_sector), i, b.column, previous_column])
				previous_column = b.column
				assert_in_range(b.row, 0, SectorMap.ROWS - 1,
					"invariant 7 (%s): beacon %d has row %d, outside the declared %d rows the map screen lays out on" % [
						_where(seed_value, p_sector), b.index, b.row, SectorMap.ROWS])
				var slot := "%d:%d" % [b.column, b.row]
				assert_false(occupied.has(slot),
					"invariant 7 (%s): beacons %d and %s both claim column %d row %d, so they would be drawn on top of each other and one would be unclickable" % [
						_where(seed_value, p_sector), b.index, occupied.get(slot, "?"), b.column, b.row])
				occupied[slot] = b.index


# --- invariant 8: deeper sectors get meaner (statistical) ----------------

func test_invariant_8_deeper_sectors_weight_combat_and_boarding_up() -> void:
	# STATISTICAL, and deliberately so: a single seed proves nothing about a weight
	# table. Sample size is STAT_SAMPLE_SEEDS (48) maps per sector, counting only
	# rolled kinds — roughly 700 rolls per side.
	var shallow := _rolled_kind_tally(1)
	var deep := _rolled_kind_tally(3)
	var hostile: Array[int] = [int(SectorMap.NodeKind.COMBAT), int(SectorMap.NodeKind.BOARDING)]
	var shallow_share := _share(shallow, hostile)
	var deep_share := _share(deep, hostile)
	assert_true(int(shallow["_total"]) > 0 and int(deep["_total"]) > 0,
		"invariant 8: the sample must actually contain rolled beacons (sector 1 total %d, sector 3 total %d)" % [
			int(shallow["_total"]), int(deep["_total"])])
	assert_true(deep_share > shallow_share,
		"invariant 8: over %d maps per sector, COMBAT+BOARDING must be a LARGER share of sector 3 than of sector 1 — got sector 1 %.3f (%d/%d) vs sector 3 %.3f (%d/%d). Without this, depth is cosmetic and there is no reason to fear going deeper" % [
			STAT_SAMPLE_SEEDS,
			shallow_share, _count(shallow, hostile), int(shallow["_total"]),
			deep_share, _count(deep, hostile), int(deep["_total"])])
	assert_true(deep_share - shallow_share > STAT_MIN_GAP,
		"invariant 8: the COMBAT+BOARDING shift with depth must be a real gap rather than sampling noise — got %.3f -> %.3f over %d maps per sector, needed more than %s" % [
			shallow_share, deep_share, STAT_SAMPLE_SEEDS, STAT_MIN_GAP])


func test_invariant_8_deeper_sectors_weight_safe_and_store_down() -> void:
	var shallow := _rolled_kind_tally(1)
	var deep := _rolled_kind_tally(3)
	var shelter: Array[int] = [int(SectorMap.NodeKind.SAFE), int(SectorMap.NodeKind.STORE)]
	var shallow_share := _share(shallow, shelter)
	var deep_share := _share(deep, shelter)
	assert_true(deep_share < shallow_share,
		"invariant 8: over %d maps per sector, SAFE+STORE must be a SMALLER share of sector 3 than of sector 1 — got sector 1 %.3f (%d/%d) vs sector 3 %.3f (%d/%d). SAFE is where beacon training happens, so the squeeze is what depth costs" % [
			STAT_SAMPLE_SEEDS,
			shallow_share, _count(shallow, shelter), int(shallow["_total"]),
			deep_share, _count(deep, shelter), int(deep["_total"])])
	assert_true(shallow_share - deep_share > STAT_MIN_GAP,
		"invariant 8: the SAFE+STORE squeeze with depth must be a real gap rather than sampling noise — got %.3f -> %.3f over %d maps per sector, needed more than %s" % [
			shallow_share, deep_share, STAT_SAMPLE_SEEDS, STAT_MIN_GAP])


func test_invariant_8_no_beacon_kind_vanishes_from_the_deepest_sector() -> void:
	# `MIN_WEIGHT` exists so depth drift can never zero a kind out. A sector 3 with
	# no SAFE beacon anywhere would silently switch training and healing off.
	var deepest: int = SECTORS_UNDER_TEST[SECTORS_UNDER_TEST.size() - 1]
	var deep := _rolled_kind_tally(deepest)
	for kind in SectorMap.BASE_WEIGHTS:
		assert_true(int(deep.get(int(kind), 0)) > 0,
			"invariant 8: %s never appeared once in %d maps of sector %d — MIN_WEIGHT (%s) is supposed to stop depth drift deleting a kind outright" % [
				SectorMap.kind_label(int(kind) as SectorMap.NodeKind), STAT_SAMPLE_SEEDS, deepest, SectorMap.MIN_WEIGHT])


func test_invariant_8_generate_clamps_a_nonsense_sector_up_to_one() -> void:
	for seed_value in SEEDS:
		for bad in [0, -1, -999]:
			var map: SectorMap = _map(seed_value, int(bad))
			assert_eq(map.sector, 1,
				"invariant 8 (seed %d): sector %d must clamp to 1 — a sector below 1 makes `sector - 1` negative and inverts every depth drift, handing the player a SAFER deep sector" % [
					seed_value, int(bad)])


# --- the entry beacon and the fog ---------------------------------------

func test_the_entry_starts_safe_and_visited_while_nothing_else_is() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var entry_beacon: SectorMap.Beacon = map.beacon(map.entry)
			assert_eq(int(entry_beacon.kind), int(SectorMap.NodeKind.SAFE),
				"%s: a sector must open on a SAFE beacon — arriving already in a fight would resolve a combat before the player had touched anything" % _where(seed_value, p_sector))
			assert_true(entry_beacon.visited,
				"%s: the entry beacon must start visited — `Voyage._enter_sector` places the ship there without a jump, so nothing else records it" % _where(seed_value, p_sector))
			assert_true(entry_beacon.explored,
				"%s: the entry beacon must start explored, or the player cannot see where they are" % _where(seed_value, p_sector))
			for b: SectorMap.Beacon in map.beacons:
				if b.index == map.entry:
					continue
				assert_false(b.visited,
					"%s: beacon %d is already visited on a fresh map, so both the threat's head start and the fuel budget begin from a lie" % [
						_where(seed_value, p_sector), b.index])
				if b.column >= 2:
					assert_false(b.explored,
						"%s: beacon %d in column %d is explored on a fresh map — generation must never hand over the whole chart, or route choice stops being a gamble" % [
							_where(seed_value, p_sector), b.index, b.column])


# --- mark_visited ------------------------------------------------------

func test_mark_visited_sets_the_beacon_and_reveals_only_its_forward_links() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		var target := int(map.neighbours(map.entry)[0])
		var target_column: int = map.beacon(target).column
		var revealed: Array[int] = map.neighbours(target)

		# `generate` now reveals the ENTRY's forward links, so the whole of column 1
		# is already explored before this call. The property being tested is a
		# DELTA — "mark_visited reveals its own links and nothing else" — so the
		# already-explored set has to be excluded, or this test would be asserting
		# something about generation instead.
		var already_explored: Array[int] = []
		for b: SectorMap.Beacon in map.beacons:
			if b.explored:
				already_explored.append(b.index)

		map.mark_visited(target)

		var arrived: SectorMap.Beacon = map.beacon(target)
		assert_true(arrived.visited,
			"seed %d: `mark_visited(%d)` must set visited — `Voyage.jump_to` relies on it to record where the ship has been" % [seed_value, target])
		assert_true(arrived.explored,
			"seed %d: arriving somewhere must also mark it explored — you cannot be somewhere you have not seen" % seed_value)

		for b: SectorMap.Beacon in map.beacons:
			if b.index == target or b.index == map.entry:
				continue
			if revealed.has(b.index):
				assert_true(b.explored,
					"seed %d: `mark_visited(%d)` must mark its forward links explored, or arriving gives the player no basis on which to choose a route" % [
						seed_value, target])
				assert_false(b.visited,
					"seed %d: revealing beacon %d must NOT also mark it visited — knowing about a beacon is not the same as having burned fuel to get there" % [
						seed_value, b.index])
			elif not already_explored.has(b.index):
				assert_false(b.explored,
					"seed %d: `mark_visited(%d)` newly revealed beacon %d, which is not one of its links — arriving must reveal only the next hop, never the whole map" % [
						seed_value, target, b.index])
			if b.column > target_column + 1:
				assert_false(b.explored,
					"seed %d: after `mark_visited(%d)` (column %d), beacon %d in column %d is explored — sensors are not part of this method and revelation must stay exactly one column deep" % [
						seed_value, target, target_column, b.index, b.column])


func test_mark_visited_on_a_bad_index_changes_nothing() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		var before := _fingerprint(map)
		map.mark_visited(-1)
		map.mark_visited(9999)
		map.mark_visited(map.size())
		assert_eq(_fingerprint(map), before,
			"seed %d: `mark_visited` on an out-of-range index must be a silent no-op, not a crash and not a stray write — the UI can hand it a stale index straight after a load or a sector change" % seed_value)


# --- serialisation -----------------------------------------------------

func test_to_dict_from_dict_round_trip_preserves_the_whole_graph() -> void:
	for seed_value in SEEDS:
		for p_sector in SECTORS_UNDER_TEST:
			var map: SectorMap = _map(seed_value, p_sector)
			var restored: SectorMap = SectorMap.from_dict(map.to_dict())
			assert_eq(restored.sector, map.sector,
				"invariant 6 (%s): a round trip must preserve `sector`, or the resumed sector rolls its kinds at the wrong depth" % _where(seed_value, p_sector))
			assert_eq(restored.entry, map.entry,
				"invariant 6 (%s): a round trip must preserve `entry`" % _where(seed_value, p_sector))
			assert_eq(restored.boss, map.boss,
				"invariant 6 (%s): a round trip must preserve `boss`, or a loaded voyage can never end its sector" % _where(seed_value, p_sector))
			assert_eq(restored.size(), map.size(),
				"invariant 6 (%s): a round trip must preserve the beacon count" % _where(seed_value, p_sector))
			assert_eq(_fingerprint(restored), _fingerprint(map),
				"invariant 6 (%s): `from_dict(to_dict())` must fingerprint identically — a save that reloads as a different map changes the chart under the player mid-voyage" % _where(seed_value, p_sector))


func test_round_trip_preserves_every_field_of_every_beacon() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		var restored: SectorMap = SectorMap.from_dict(map.to_dict())
		for i in map.beacons.size():
			var original: SectorMap.Beacon = map.beacons[i]
			var copy: SectorMap.Beacon = restored.beacon(original.index)
			assert_not_null(copy,
				"invariant 6 (seed %d): beacon %d did not survive the round trip at all" % [seed_value, original.index])
			if copy == null:
				continue
			assert_eq(int(copy.kind), int(original.kind),
				"invariant 6 (seed %d): beacon %d changed kind across a save (%s -> %s), which swaps the encounter waiting there" % [
					seed_value, original.index, original.kind_label(), copy.kind_label()])
			assert_eq(copy.column, original.column,
				"invariant 6 (seed %d): beacon %d changed column across a save, which moves it relative to the threat" % [seed_value, original.index])
			assert_eq(copy.row, original.row,
				"invariant 6 (seed %d): beacon %d changed row across a save, so the map would redraw in a different shape" % [seed_value, original.index])
			assert_eq(copy.links, original.links,
				"invariant 6 (seed %d): beacon %d's links changed across a save (%s -> %s), which rewrites the player's route options" % [
					seed_value, original.index, original.links, copy.links])


func test_round_trip_preserves_visited_and_explored_progress() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		# Walk two hops, so the map carries a real mix of visited, explored and
		# untouched. A round trip of an all-default map proves nothing.
		var first := int(map.neighbours(map.entry)[0])
		map.mark_visited(first)
		var second := int(map.neighbours(first)[0])
		map.mark_visited(second)
		var visited_before := 0
		var explored_before := 0
		for b: SectorMap.Beacon in map.beacons:
			visited_before += 1 if b.visited else 0
			explored_before += 1 if b.explored else 0
		assert_true(visited_before >= 3,
			"seed %d: the fixture must have visited the entry plus two hops before the round trip is worth testing" % seed_value)
		assert_true(explored_before > visited_before,
			"seed %d: exploring must outrun visiting, or the fixture is not exercising the explored flag independently at all" % seed_value)

		var restored: SectorMap = SectorMap.from_dict(map.to_dict())
		for b: SectorMap.Beacon in map.beacons:
			var copy: SectorMap.Beacon = restored.beacon(b.index)
			assert_eq(copy.visited, b.visited,
				"invariant 6 (seed %d): beacon %d lost its `visited` flag across a save — a reloaded voyage would forget where it had been" % [seed_value, b.index])
			assert_eq(copy.explored, b.explored,
				"invariant 6 (seed %d): beacon %d lost its `explored` flag across a save — a reload would re-fog chart the player already paid fuel for" % [seed_value, b.index])


func test_to_dict_hands_out_copies_rather_than_the_live_graph() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		var snapshot: Dictionary = map.to_dict()
		var rows: Array = snapshot["beacons"] as Array
		var first: Dictionary = rows[0] as Dictionary
		(first["links"] as Array).clear()
		first["column"] = 99
		assert_false(map.beacon(0).links.is_empty(),
			"seed %d: `to_dict` must duplicate the links array rather than alias it — a save writer holding the dict must not be able to erase the graph" % seed_value)
		assert_eq(map.beacon(0).column, 0,
			"seed %d: `to_dict` must be a snapshot, not a live view of the beacon" % seed_value)


func test_from_dict_survives_a_junk_dictionary_without_inventing_a_map() -> void:
	var empty: SectorMap = SectorMap.from_dict({})
	assert_eq(empty.size(), 0,
		"a `from_dict` of nothing must produce an empty map, not a fabricated one — `Voyage.apply_dict` uses the empty case to mean 'no chart yet'")
	assert_eq(empty.sector, 1,
		"`from_dict` must clamp a missing sector to 1, so depth drift is never computed from 0")
	var junk: SectorMap = SectorMap.from_dict({"sector": -4, "beacons": "not an array"})
	assert_eq(junk.sector, 1,
		"`from_dict` must clamp a negative sector to 1, or a corrupted save inverts every depth weight")
	assert_eq(junk.size(), 0,
		"`from_dict` must ignore a `beacons` value that is not an array rather than half-building a graph")


# --- out-of-range queries ---------------------------------------------

func test_beacon_returns_null_for_every_out_of_range_index() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		for bad in [-1, -999, map.size(), 9999]:
			assert_null(map.beacon(int(bad)),
				"seed %d: `beacon(%d)` must return null rather than crash — the map screen polls this on every redraw and can hold a stale index across a sector change" % [
					seed_value, int(bad)])
		for b: SectorMap.Beacon in map.beacons:
			assert_not_null(map.beacon(b.index),
				"seed %d: `beacon(%d)` must return the beacon for every in-range index" % [seed_value, b.index])


func test_neighbours_of_a_bad_index_is_empty_and_never_aliases_the_map() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		for bad in [-1, map.size(), 9999]:
			assert_true(map.neighbours(int(bad)).is_empty(),
				"seed %d: `neighbours(%d)` must be empty, or `Voyage.options()` would offer jumps to beacons that do not exist" % [
					seed_value, int(bad)])
		var live: Array[int] = map.neighbours(map.entry)
		var count := live.size()
		live.clear()
		assert_eq(map.neighbours(map.entry).size(), count,
			"seed %d: `neighbours` must return a copy — a screen that filters the list it was handed must not be able to delete the player's routes" % seed_value)


func test_path_exists_and_reachable_from_are_empty_for_bad_indices() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		for bad in [-1, map.size(), 9999]:
			assert_false(map.path_exists(int(bad), map.boss),
				"seed %d: `path_exists(%d, boss)` must be false, not a crash — a bad index is not a route" % [seed_value, int(bad)])
			assert_false(map.path_exists(map.entry, int(bad)),
				"seed %d: `path_exists(entry, %d)` must be false, not a crash" % [seed_value, int(bad)])
			assert_true(map.reachable_from(int(bad)).is_empty(),
				"seed %d: `reachable_from(%d)` must be empty for an index that is not a beacon" % [seed_value, int(bad)])


func test_column_and_kind_queries_are_safe_outside_the_grid() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		for bad in [-1, SectorMap.COLUMNS, 999]:
			assert_true(map.beacons_in_column(int(bad)).is_empty(),
				"seed %d: `beacons_in_column(%d)` must be empty — the column past the boss does not exist and nothing may be found there" % [
					seed_value, int(bad)])
		assert_eq(map.last_column(), SectorMap.COLUMNS - 1,
			"seed %d: `last_column` must be the final index of the declared grid, since `Voyage` measures the threat against it" % seed_value)
		for bad in [-1, map.size(), 9999]:
			assert_eq(int(map.kind_of(int(bad))), int(SectorMap.NodeKind.COMBAT),
				"seed %d: `kind_of(%d)` must not crash. It falls back to COMBAT, which is indistinguishable from a real combat beacon — pinned here so the fallback cannot change silently under `Voyage._beacon_can_supply_fuel`" % [
					seed_value, int(bad)])


func test_every_node_kind_has_exactly_one_label() -> void:
	assert_eq(SectorMap.KIND_LABELS.size(), int(SectorMap.NodeKind.BOSS) + 1,
		"KIND_LABELS must be total over NodeKind — a missing entry means a beacon draws under another kind's name because `kind_label` clamps")
	assert_eq(SectorMap.kind_label(SectorMap.NodeKind.COMBAT), "COMBAT",
		"the first enum value must map to the first label")
	assert_eq(SectorMap.kind_label(SectorMap.NodeKind.BOSS), "BOSS",
		"the last enum value must map to the last label, or the whole table is off by one")
	var seen: Array[String] = []
	for i in SectorMap.KIND_LABELS.size():
		var label := SectorMap.kind_label(i as SectorMap.NodeKind)
		assert_not_has(seen, label,
			"kind label \"%s\" is used twice, so two beacon types read as the same thing on screen" % label)
		seen.append(label)
	# Kinds are serialised as ints and used to index the label table, so
	# renumbering the enum would silently rewrite every saved beacon's type.
	assert_eq(int(SectorMap.NodeKind.COMBAT), 0, "COMBAT is kind 0 and every save depends on it")
	assert_eq(int(SectorMap.NodeKind.BOSS), 6, "BOSS is kind 6 and every save depends on it")


# --- purity ------------------------------------------------------------

func test_no_map_query_consumes_randomness() -> void:
	# §0: every read-only question must roll nothing. The map screen polls these on
	# every redraw, and a query that draws would desync the voyage's stream exactly
	# as `Training.can_train()` once did.
	var reference := MpRng.new(SEEDS[0])
	var live := MpRng.new(SEEDS[0])
	var expected := reference.randf()
	_poll(_map(SEEDS[1]), POLLS)
	assert_almost_eq(live.randf(), expected, 0.0000001,
		"polling the map's queries must leave a voyage's MpRng stream exactly where it was")
	# And nothing reached for the global generator behind core's back, which no
	# injected seed can protect against.
	seed(SEEDS[0])
	var baseline := randi()
	seed(SEEDS[0])
	_poll(_map(SEEDS[1]), POLLS)
	assert_eq(randi(), baseline,
		"a map query called the global randi() — core randomness must go through MpRng, and read-only questions must roll nothing at all")


func test_asking_the_map_questions_never_changes_the_map() -> void:
	for seed_value in SEEDS:
		var map: SectorMap = _map(seed_value)
		var before := _fingerprint(map)
		_poll(map, POLLS)
		assert_eq(_fingerprint(map), before,
			"seed %d: every beacon/neighbours/path_exists/reachable_from call must be read-only — the map screen polls them on every redraw and `Voyage.can_jump_to` polls them per frame" % seed_value)
