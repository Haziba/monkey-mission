class_name Voyage
extends RefCounted

## One expedition: where you are, how much fuel is left, how close the threat is,
## and whether it is over.
##
## See docs/MISSION-ARCHITECTURE.md §6. This is the mutation of `core/day_cycle.gd`
## — jumps instead of AM/PM slots, fuel instead of free time — and of the
## structural pressure `core/ladder.gd` supplied. Both of those keep working and
## keep their tests until an attended phase retires them (§2).
##
## The threat is what makes this a voyage rather than a sandbox. Monkey Puncher
## used a five-day pro-test window and a ladder that outpaced you; FTL used the
## rebel fleet. Ours advances a column every jump, and since every link in a
## `SectorMap` goes strictly forward, there is no route back into ground it has
## already taken (design §5).

## DIVERGENCE: design §9 #4 — voyage length is [X]. Three sectors is the slice's
## depth: long enough for the two-axis leveling in `Crew` to visibly pay off,
## short enough to finish in a sitting.
const SECTORS := 3

const FUEL_PER_JUMP := 1

## The threat starts behind the entry column, so the first beacon is never
## already lost.
const THREAT_START_COLUMN := -1

## Columns the threat advances per jump. DIVERGENCE: design §9 #4. One per jump
## means it moves exactly as fast as the player does — the pressure comes from
## needing to stop and do things (train, trade, fight) while it does not.
const THREAT_COLUMNS_PER_JUMP := 1

## Jumps of grace before the threat starts moving at all, so a sector opens
## calmly. DIVERGENCE: [X].
const THREAT_GRACE_JUMPS := 2

## DIVERGENCE: [X]. Half a tank per sector cleared — enough to cross the next one
## directly, not enough to wander it exhaustively. Without this, fuel spent deep
## in sector 1 would make sector 3 arithmetically unreachable however well the
## player played, turning a pacing knob into a dead end.
const SECTOR_CLEAR_FUEL := 8

enum EndReason { NONE, VICTORY, HULL_LOST, CREW_LOST, STRANDED, OVERTAKEN }

const END_REASON_TEXT: Dictionary = {
	EndReason.NONE: "",
	EndReason.VICTORY: "THE VOYAGE IS COMPLETE.",
	EndReason.HULL_LOST: "THE SHIP IS TORN OPEN. THE VOYAGE ENDS HERE.",
	EndReason.CREW_LOST: "THE LAST OF THE CREW IS GONE.",
	EndReason.STRANDED: "NO FUEL, AND NOWHERE LEFT TO REACH.",
	EndReason.OVERTAKEN: "IT CAUGHT UP WITH YOU.",
}

signal jumped(beacon_index: int)
signal beacon_arrived(beacon_index: int, kind: int)
signal sector_advanced(sector: int)
signal threat_advanced(column: int)
signal fuel_changed(fuel: int)
signal voyage_ended(reason: int)

var sector: int = 1
var map: SectorMap = null
## Index of the beacon the ship is sitting at.
var at: int = 0
## Jumps made across the whole voyage. Never reset — it is the voyage's odometer.
var jumps_taken: int = 0
## Jumps made since entering the CURRENT sector. Reset by `_enter_sector`.
##
## Separate from `jumps_taken` deliberately. The threat's grace period is
## per-sector ("a sector opens calmly"), and `_enter_sector` resets
## `threat_column` to match. Gating the grace on the voyage total instead spent it
## once in sector 1 and let every later sector open with the threat already
## advancing — which made the back half of a voyage far harder for a bookkeeping
## reason rather than a design one.
var jumps_this_sector: int = 0
## Columns at or behind this are consumed by the threat.
var threat_column: int = THREAT_START_COLUMN
var ended: bool = false
var end_reason: EndReason = EndReason.NONE

## Whether THIS sector's boss has actually been beaten. Reset on entering a
## sector. Arriving at the boss beacon is not the same as clearing it — without
## this flag the final sector would declare VICTORY the moment the ship docked,
## and the boss fight would never happen.
var boss_cleared: bool = false

var _rules: GameRules
var _rng: MpRng


func _init(rules: GameRules, rng: MpRng) -> void:
	_rules = rules
	_rng = rng


## Open sector 1 and put the ship at its entry beacon.
func begin(_ship: Ship = null) -> void:
	sector = 1
	_enter_sector(1)


func _enter_sector(p_sector: int) -> void:
	sector = maxi(1, p_sector)
	map = SectorMap.generate(sector, _rng)
	at = map.entry
	threat_column = THREAT_START_COLUMN
	jumps_this_sector = 0
	boss_cleared = false
	map.mark_visited(at)
	sector_advanced.emit(sector)
	beacon_arrived.emit(at, int(map.kind_of(at)))


func current_beacon() -> SectorMap.Beacon:
	if map == null:
		return null
	return map.beacon(at)


func current_kind() -> SectorMap.NodeKind:
	if map == null:
		return SectorMap.NodeKind.COMBAT
	return map.kind_of(at)


func current_column() -> int:
	var beacon := current_beacon()
	return beacon.column if beacon != null else 0


# --- jumping -----------------------------------------------------------------

## Beacons one jump away. PURE.
func options() -> Array[int]:
	if map == null or ended:
		return []
	return map.neighbours(at)


## PURE — no RNG, safe for a screen to poll while drawing the map.
func can_jump_to(index: int, ship: Ship) -> bool:
	return jump_reason(index, ship) == ""


## Why a jump is illegal, "" when it is legal. Guaranteed empty exactly when
## `can_jump_to` is true.
func jump_reason(index: int, ship: Ship) -> String:
	if ended:
		return "THE VOYAGE IS OVER."
	if map == null:
		return "THERE IS NO CHART."
	if not options().has(index):
		return "THERE IS NO ROUTE THERE FROM HERE."
	if ship == null:
		return "THERE IS NO SHIP."
	if ship.fuel < FUEL_PER_JUMP:
		return "NOT ENOUGH FUEL."
	return ""


## Burn fuel, move, advance the threat, and report arrival. Returns false and
## changes nothing when the jump was illegal.
func jump_to(index: int, ship: Ship) -> bool:
	if not can_jump_to(index, ship):
		return false
	if not ship.burn_fuel(FUEL_PER_JUMP):
		return false
	fuel_changed.emit(ship.fuel)

	at = index
	jumps_taken += 1
	jumps_this_sector += 1
	map.mark_visited(at)
	jumped.emit(at)

	# The threat moves AFTER the player, and only once this SECTOR's grace period
	# is over, so a jump can never be punished by a menace that had not yet
	# started. Gated on `jumps_this_sector`, not the voyage total — see the field's
	# comment for the bug that distinction fixes.
	if jumps_this_sector > THREAT_GRACE_JUMPS:
		advance_threat()

	beacon_arrived.emit(at, int(map.kind_of(at)))
	return true


## Push the threat forward. Returns its new column.
func advance_threat() -> int:
	threat_column += THREAT_COLUMNS_PER_JUMP
	threat_advanced.emit(threat_column)
	return threat_column


## True when the threat has consumed a beacon's column.
func threat_holds(index: int) -> bool:
	if map == null:
		return false
	var beacon := map.beacon(index)
	if beacon == null:
		return false
	return beacon.column <= threat_column


func threat_at_player() -> bool:
	return threat_holds(at)


## How many columns of clear space are left between the threat and the ship.
func threat_distance() -> int:
	return current_column() - threat_column


# --- sector progression ------------------------------------------------------

func at_boss() -> bool:
	return map != null and at == map.boss


func is_final_sector() -> bool:
	return sector >= SECTORS


## Mark this sector's boss beaten. Called by whatever resolved the encounter —
## `Voyage` never decides a fight.
func clear_boss() -> void:
	if at_boss():
		boss_cleared = true


## Move on once the boss beacon has actually been BEATEN. Does nothing on the
## last sector — `check_end` reports VICTORY there instead.
func enter_next_sector(ship: Ship) -> bool:
	if ended or not at_boss() or not boss_cleared or is_final_sector():
		return false
	_enter_sector(sector + 1)
	if ship != null:
		ship.add_fuel(SECTOR_CLEAR_FUEL)
		fuel_changed.emit(ship.fuel)
	return true


# --- ending ------------------------------------------------------------------

## The permadeath check, in priority order. PURE: it reports, it does not end the
## voyage — call `end(reason)` for that, so a caller can decide when to look.
func check_end(ship: Ship, crew: Crew) -> EndReason:
	if ship != null and ship.is_destroyed():
		return EndReason.HULL_LOST
	if crew != null and crew.all_dead():
		return EndReason.CREW_LOST
	# VICTORY outranks OVERTAKEN deliberately: having beaten the final boss, it no
	# longer matters that the menace has arrived. It requires `boss_cleared`, not
	# merely standing on the beacon.
	if at_boss() and is_final_sector() and boss_cleared:
		return EndReason.VICTORY
	if threat_at_player():
		return EndReason.OVERTAKEN
	if _is_stranded(ship):
		return EndReason.STRANDED
	return EndReason.NONE


## Out of fuel with no way to earn any. A STORE or DISTRESS beacon might yield
## fuel, but only if it can still be reached — and with no fuel, nothing can.
## Sitting on a beacon that could supply fuel is therefore the one reprieve.
func _is_stranded(ship: Ship) -> bool:
	if ship == null or map == null:
		return false
	if ship.fuel >= FUEL_PER_JUMP:
		return false
	if options().is_empty():
		# Nowhere to go and no fuel — but the boss beacon is an ending, not a
		# stranding, and VICTORY is checked before this.
		return not at_boss()
	return not _beacon_can_supply_fuel(at)


## DIVERGENCE: [X]. STORE and DISTRESS beacons are the two that plausibly hand
## over fuel, so being parked on one is not yet a dead end.
func _beacon_can_supply_fuel(index: int) -> bool:
	var kind := map.kind_of(index)
	return kind == SectorMap.NodeKind.STORE or kind == SectorMap.NodeKind.DISTRESS


## End the voyage. Idempotent — the first reason recorded is the one that sticks,
## so a caller polling `check_end` in a loop cannot overwrite the real cause.
func end(reason: EndReason) -> void:
	if ended or reason == EndReason.NONE:
		return
	ended = true
	end_reason = reason
	voyage_ended.emit(int(reason))


## Check and end in one step, for a caller that just wants the loop driven.
func settle(ship: Ship, crew: Crew) -> EndReason:
	var reason := check_end(ship, crew)
	if reason != EndReason.NONE:
		end(reason)
	return reason


func is_over() -> bool:
	return ended


func was_won() -> bool:
	return ended and end_reason == EndReason.VICTORY


static func end_reason_text(reason: EndReason) -> String:
	return String(END_REASON_TEXT.get(reason, ""))


# --- serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"sector": sector,
		"at": at,
		"jumps_taken": jumps_taken,
		"jumps_this_sector": jumps_this_sector,
		"threat_column": threat_column,
		"boss_cleared": boss_cleared,
		"ended": ended,
		"end_reason": int(end_reason),
		"map": map.to_dict() if map != null else {},
	}


func apply_dict(d: Dictionary) -> void:
	sector = clampi(int(d.get("sector", 1)), 1, SECTORS)
	at = maxi(0, int(d.get("at", 0)))
	jumps_taken = maxi(0, int(d.get("jumps_taken", 0)))
	jumps_this_sector = maxi(0, int(d.get("jumps_this_sector", 0)))
	threat_column = int(d.get("threat_column", THREAT_START_COLUMN))
	boss_cleared = bool(d.get("boss_cleared", false))
	ended = bool(d.get("ended", false))
	end_reason = int(d.get("end_reason", EndReason.NONE)) as EndReason
	var raw: Variant = d.get("map", {})
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		map = SectorMap.from_dict(raw as Dictionary)
	else:
		map = null
