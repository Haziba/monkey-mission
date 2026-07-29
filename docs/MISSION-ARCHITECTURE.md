# Monkey Mission — Architecture and API Contract

**This document is the contract for the mutation.** It stands to Monkey Mission as
`docs/ARCHITECTURE.md` stands to monkey-puncher-mk2, and it is written in the same spirit: the
signatures below are frozen first and implemented afterwards, so that nothing is written against a
moving target.

Three documents, three jobs:

| Document | Job | May be edited |
|---|---|---|
| `docs/original-game.md` | The Monkey Puncher research dossier. Tie-breaker on **inherited** behaviour. | **Never** |
| `docs/monkey-mission-design.md` | The fusion design. Tie-breaker on **new** behaviour. | Only by the user |
| `docs/ARCHITECTURE.md` | The pre-mutation code contract. Still true for every KEEP module. | Amend to record a signature change |
| `docs/MISSION-ARCHITECTURE.md` | **This file.** The post-mutation contract. | Amend to record a signature change |

Where this file and `ARCHITECTURE.md` disagree about a module, **this file wins for the mutated
module and `ARCHITECTURE.md` still wins for everything marked KEEP in §2.**

---

## 0. Ground rules — unchanged, and non-negotiable

Everything in `ARCHITECTURE.md` §0 carries over verbatim. Restated because the mutation is exactly
the moment these get quietly dropped:

### Layering

```
ui/  ─────►  GameState (autoload)  ─────►  core/
```

* Core is pure GDScript: `RefCounted` or `Resource`. **No `Node`, no scene tree, no `get_tree()`,
  no `Input`, no `await` on frames.** It must run under `--headless --script`.
* All randomness goes through an injected `MpRng`. **Never call the global `randi()`/`randf()` in
  core.**
* Screens talk to `GameState` and nothing else. A screen must never construct a `Ship`, `Crew`,
  `Voyage`, `SectorMap` or `ShipCombat`, and never compute a damage number, an evasion roll or a
  jump.
* **The simulation is stepped by the UI, never the reverse.** `ShipCombat.advance(delta)` is the
  only clock. `docs/monkey-mission-design.md` §10 flags this as the rule most at risk: FTL-style
  combat rots into untestable spaghetti faster than boxing ever did.

### Read-only questions must stay free

`tests/unit/test_core_purity.gd` exists because `Training.can_train()` once rolled a die to pick its
flavour text, and seven UI redraws silently desynced an entire run. **Every new predicate — every
`can_*`, `is_*`, `*_reason`, `*_chance`, `performance`, `preview` — must consume zero RNG draws** and
must be added to that test file. A predicate that rolls is a bug even when the number it returns
looks right.

### The DIVERGENCE convention

`docs/monkey-mission-design.md` §9 is an `[X]` register in the dossier's own style. Every value drawn
from it gets an inline comment naming what was unknown and why this number was chosen:

```gdscript
# DIVERGENCE: design §9 #1 — the stat→station coefficients are [X]. 150.0 is
# chosen to match MatchResolver.KNOWLEDGE_REFERENCE, which already treats 150 as
# "a fully trained stat", so a station reads as 100% manned at the same number
# the boxing sim already calls competent.
const REFERENCE_STAT := 150.0
```

Do **not** DIVERGENCE-comment anything the dossier confirms `[C]` or the design doc resolves
outright (§9 #5 and #6 are resolved — cite them, do not re-open them).

### GameRules — still six flags, still non-negotiable

`core/game_rules.gd`, instance at `res://game_rules.tres`, pinned by `tests/unit/test_game_rules.gd`.
The mutation adds **no** flags in phases 1–4 and removes none.

Two of them are load-bearing for the fusion and **must not be softened** (design §10):

| Flag | Why it matters more in space than it did in the ring |
|---|---|
| `disobedience_enabled = true` | A low-friendship monkey ignoring an order **in a firefight** is better tension than it ever was in boxing. `ShipCombat` rolls obedience per order, not per frame (§10). |
| `overfeeding_paralyses = true` | An overfed crew member is **immobilised at their station** — the station reads as unmanned while it digests. Never "wastes food". |

`fight_interactivity` keeps its meaning for boarding melee and additionally gates whether the player
may nudge a charging weapon (§10).

### Scope for phases 1–4

**In:** the station model, the crew model, the voyage/beacon loop, ship-vs-ship combat, and tests for
all four.

**Out, and deliberately not stubbed:** events/`event_db` beyond the contract in §8, boarding melee
beyond keeping `MatchResolver` intact, the home stable beyond the contract in §9, oxygen, medbay,
doors, crew movement between rooms, ship selection, and the spirit's own progression.

---

## 1. Vocabulary

The mutation renames the world. Use these words in code, comments, tests and UI strings; a mixed
vocabulary is how a codebase stops being readable.

| Word | Means | Replaces |
|---|---|---|
| **voyage** | one expedition, ends in permadeath or victory | *run* (partly — see §2) |
| **jump** | moving between two beacons; burns fuel | *half-day slot* |
| **beacon** | one node on the sector map | — |
| **sector** | one procedural beacon graph; voyages cross several | — |
| **crew** | the monkeys aboard | *the active monkey* (now plural) |
| **station** | one of five manned ship systems | — |
| **stable** | the persistent home layer between voyages | — |
| **scrap** | the currency | *money* / ¥ |
| **fuel** | the jump currency | — |
| **the threat** | the advancing menace behind you | *the ladder's pressure* |
| **spirit** | the player | *the trainer* (Kenta / Sumire) |

`Economy.money` is **repointed, not renamed** — see §11.

---

## 2. Every existing module's fate

Derived from `docs/monkey-mission-design.md` §3. **RETIRE means "no longer reachable from a live
voyage", never "delete the file and its tests."**

### KEEP — untouched by phases 1–4

| Module | Why it survives intact |
|---|---|
| `core/monkey.gd` | The five-stat + caps model **is** the crew model. STRENGTH-is-health carries over unchanged. **Phases 1–4 add no field to `Monkey`** — in-run station XP lives on `Crew.Member` (§4), which is what makes permadeath mean something. |
| `core/training.gd`, `core/rhythm_score.gd` | The rhythm minigame becomes beacon training at SAFE nodes. The sim/UI split is already exactly right. |
| `core/care.gd` | Feed / friendship / discipline / paralysis / obedience all still apply. `Crew` **consumes** `Care` rather than reimplementing it (§4). |
| `core/breeding.gd` | Generational cap inheritance is the meta-progression; it moves to the stable in phase 7, unchanged in maths. |
| `core/rng.gd`, `core/save_game.gd`, `core/game_rules.gd`, `core/species.gd`, `core/food.gd`, `core/data/**` | Infrastructure and data. Extended, never rewritten. |
| `ui/router.gd`, `ui/theme/palette.gd`, `ui/sfx.gd`, the test harness | Infrastructure. |

### MUTATE

| Module | Becomes | How, in phases 1–4 |
|---|---|---|
| `core/economy.gd` | scrap + parts purse | **Additive repoint** (§11): `scrap` reads and writes the same integer as `money`. No test changes, no UI changes. |
| `core/ladder.gd` | `core/sector_map.gd` | **New file, additively.** `Ladder` keeps working and keeps its 466 lines of tests; nothing in a voyage calls it. |
| `core/day_cycle.gd` | `core/voyage.gd` | **New file, additively.** Same reasoning. |
| `core/run_state.gd` | `RunState` wraps `VoyageState` + `StableState` | **Additive in phases 1–4:** `RunState` gains an optional `voyage: VoyageState` and loses nothing. See the decision note below. |
| `core/match_resolver.gd` | **two** resolvers | `ShipCombat` is a **new file**. `MatchResolver` is left byte-for-byte alone so it can be re-homed as `BoardingCombat` in phase 6 with its 751 lines of tests intact. |
| `core/game_state.gd` | still the single UI funnel | Grows voyage/ship/crew methods and signals. Removes nothing. |

> **DECISION — the mutation is additive through phase 4.**
>
> The brief says *"never delete coverage without replacing it"* and *"`test_project_compiles.gd`
> must never be red."* A true split of `RunState` into `VoyageState` + `StableState` touches
> `save_game.gd`, `game_state.gd`, every screen and roughly 1,500 lines of green tests at once.
> Done overnight and unattended, that is how you wake up to a red suite and no way to tell which
> of six changes broke it.
>
> So phases 1–4 **add** the new model beside the old one. `VoyageState` is real, tested and owns
> the voyage; `RunState` keeps its boxing-era fields and its tests; the boxing screens keep
> working. Retirement — deleting the ladder path, splitting the save file, repointing the router —
> is a deliberate, attended phase of its own. It is listed as the next step in
> `docs/MORNING-REPORT.md` rather than smuggled in at 3am.
>
> The cost of this choice is honest: for the duration, `core/` contains two games. §12 says which
> tests hold the line between them.

### RETIRE — later, and not tonight

`Ladder`'s rank ladder, `DayCycle`'s AM/PM slots and `Ladder.MATCH_CYCLE_DAYS` have no meaning in a
voyage. They stay compiled, tested and unreachable from voyage code until an attended phase removes
them.

---

## 3. The bridge — monkey stats → ship stations

The single most important new contract, and the equivalent of "STRENGTH is the health bar". From
design §4, where the 1:1 mapping is **resolved, not open**.

```gdscript
# core/ship.gd
enum Station { PILOT, ENGINES, WEAPONS, SHIELDS, SENSORS }
```

| Station | Keyed stat | Trained by | Drives | In boarding melee |
|---|---|---|---|---|
| `PILOT` | `SPEED` | `SKIPPING` | Evasion | Strikes first / dodges |
| `ENGINES` | `STAMINA` | `RUNNING` | Jump charge + sustained evasion | Round-to-round energy |
| `WEAPONS` | `POWER` | `PUNCHBAG` | Weapon damage and charge speed | Melee damage |
| `SHIELDS` | `STRENGTH` | `SIT_UPS` | Shield recharge | **The health bar** |
| `SENSORS` | `KNOWLEDGE` | `SHOPPING` | Targeting, event insight | Reads the enemy |

Five stations, five stats, five training activities — one table, three ways of reading it:

```gdscript
const STATION_STAT: Dictionary = {          # Station -> Monkey.Stat
    Station.PILOT:   Monkey.Stat.SPEED,
    Station.ENGINES: Monkey.Stat.STAMINA,
    Station.WEAPONS: Monkey.Stat.POWER,
    Station.SHIELDS: Monkey.Stat.STRENGTH,
    Station.SENSORS: Monkey.Stat.KNOWLEDGE,
}
const STATION_ACTIVITY: Dictionary          # Station -> Training.Activity
const STATION_LABELS: PackedStringArray     # ["PILOT","ENGINES","WEAPONS","SHIELDS","SENSORS"]

static func station_stat(station: Station) -> Monkey.Stat
static func station_activity(station: Station) -> Training.Activity
static func station_for_stat(stat: Monkey.Stat) -> Station
static func station_label(station: Station) -> String
```

**Stats stay cross-cutting.** A stat's home station is where it is *read from*, not where it is
*confined to*:

* `STRENGTH` is still every monkey's health — against fire, vacuum and boarders. A monkey bred for
  Shields is therefore also your best boarder. This is faithful, not a coincidence.
* `STAMINA` is still general endurance and still drains in melee.
* `KNOWLEDGE` still gates the better choice under `BALANCED`, and now also gates event insight —
  the direct heir to gating special punches.

**Five systems, not eight.** Design §3 lists oxygen, medbay and doors among the ship's systems;
design §9 #5 then resolves the ship to *"five fixed systems/stations"*. The later, explicit
resolution wins: **systems and stations are the same five things, 1:1**, which is what keeps the
stat map clean. Oxygen, medbay and doors are out of scope and are **not** stubbed. Recorded as a
DIVERGENCE in `core/ship.gd`.

### Leveling — two axes

From design §4, and the precise meaning of *"only the experience and levels depend on their
training"*:

```
trained stat  ──►  the CEILING a station level may reach, and the RATE xp accrues
station xp    ──►  the level itself, earned by DOING, in-run, lost with the crew
```

* **Station XP** accrues while a monkey mans a station through combat. It lives on `Crew.Member`,
  resets with the voyage, and dies with the monkey.
* **Trained stats** are raised by beacon training (in-run) and by breeding (permanently, between
  voyages). They set how high and how fast the XP can climb.

So a bloodline bred for POWER produces gunners who *can* reach the top Weapons level; a voyage's
combats are what actually get them there. Both halves of the game stay alive.

---

## 4. `core/crew.gd` — `Crew extends RefCounted`

The monkeys aboard, their station assignments, and their in-run progress. **Phase 2.**

```gdscript
class_name Crew
extends RefCounted

## Design §2.5/§9 #6, RESOLVED: capacity 6, a voyage starts with 4.
const CAPACITY := 6
const VOYAGE_START_SIZE := 4
const UNASSIGNED := -1

const STATION_LEVEL_MAX := 5
const XP_TO_LEVEL: PackedInt32Array      # cumulative XP thresholds, index == level
const STAT_PER_LEVEL := 30               # DIVERGENCE: design §9 #2
const REFERENCE_STAT := 150.0            # DIVERGENCE: design §9 #1
const LEVEL_BONUS := 0.12                # DIVERGENCE: design §9 #2
const XP_RATE_FLOOR := 0.5               # DIVERGENCE: design §9 #2
const XP_RATE_SPAN := 1.0                # DIVERGENCE: design §9 #2

## One monkey aboard, plus everything true of it only for this voyage.
## Deliberately NOT stored on Monkey: permadeath must cost the player the
## station levels, while the bloodline's trained stats survive in the stable.
class Member extends RefCounted:
    var monkey: Monkey
    var station: int                     ## Ship.Station, or UNASSIGNED
    var station_xp: Dictionary           ## Ship.Station -> float
    var alive: bool
    var fatigue: float                   ## 0..1, reserved for phase 5+
    func level_in(station: int) -> int
    func xp_in(station: int) -> float
    func to_dict() -> Dictionary
    static func from_dict(d: Dictionary) -> Member

signal member_added(member: Member)
signal member_died(member: Member)
signal assigned(member: Member, station: int)
signal station_levelled(member: Member, station: int, level: int)

var members: Array[Member] = []

func _init(rules: GameRules, rng: MpRng, care: Care) -> void

# --- roster ---
func size() -> int
func living() -> Array[Member]
func add(monkey: Monkey) -> Member                    ## null when at CAPACITY
func remove(member: Member) -> bool
func member_for(monkey: Monkey) -> Member
func has_room() -> bool

# --- assignment ---
func assign(member: Member, station: int) -> bool     ## displaces any current holder
func unassign(member: Member) -> void
func manning(station: int) -> Member                  ## null when unmanned
func is_manned(station: int) -> bool
func unmanned_stations() -> Array[int]
func floaters() -> Array[Member]                      ## living, UNASSIGNED
func auto_assign() -> void                            ## best-stat-first, deterministic

# --- availability: REUSES Care, never reimplements it ---
func is_available(member: Member) -> bool
func unavailable_reason(member: Member) -> String     ## "" when available
func effective_manning(station: int) -> Member        ## null when the holder cannot act

# --- performance: what ship systems consume ---
func station_performance(station: int) -> float       ## 0.0 when unmanned/unavailable
func performance_of(member: Member, station: int) -> float
func level_ceiling(member: Member, station: int) -> int
func xp_rate(member: Member, station: int) -> float

# --- progress ---
func award_xp(member: Member, station: int, amount: float) -> int   ## returns new level
func award_station_xp(station: int, amount: float) -> int

# --- health, via Monkey's existing pools ---
func hurt(member: Member, amount: int) -> int
func heal(member: Member, amount: int) -> int
func is_incapacitated(member: Member) -> bool
func kill(member: Member) -> void
func all_dead() -> bool

# --- naming ---
const NAME_POOL: PackedStringArray
static func random_name(rng: MpRng, avoid: PackedStringArray = []) -> String

func to_dict() -> Dictionary
func apply_dict(d: Dictionary, roster: Array[Monkey]) -> void
```

### Availability reuses `Care`

`Crew` takes a `Care` by injection — the same pattern `MatchResolver._init(rules, rng, care)` already
uses. A member is unavailable when **any** of:

* not `alive`;
* `Care.is_paralysed(monkey)` — which is where `overfeeding_paralyses` (FAITHFUL) reaches the ship,
  immobilising the monkey **at its station**;
* starving — `Care.can_act` already covers both hunger extremes;
* incapacitated — `current_strength <= 0`.

An unavailable member keeps its assignment. The station simply reads as unmanned until it recovers,
which is the correct texture: you can see who *should* be there.

> **DIVERGENCE — `current_strength <= 0` incapacitates, it does not kill.** Nothing in the dossier
> or the design doc says a monkey dies at zero Strength, and in boxing zero Strength is a KO — the
> monkey gets up afterwards. Death is therefore an explicit `kill()` call reserved for lethal
> events (vacuum, fire, a lost boarding fight), never an automatic consequence of damage. This keeps
> the boxing sim reusable as boarding melee in phase 6 without it quietly becoming lethal, and it
> keeps `Monkey`'s "no injury, illness, ageing or lifespan system" (dossier §14.11) honest.

### Naming

Design §2.6 and dossier §8 `[C]`: names are **player-assigned and food-themed by default**. The
attested pool is `Freddy, Agatha, Lemon, Betty, Dragon, Jimbo, Tomato, Cookie, Pizza`. `NAME_POOL`
starts as exactly those nine; anything added is food-themed and DIVERGENCE-commented. Freddy's name
being fixed for the *starter* (dossier §8 `[C]`) is a `RunState` concern and unaffected.

`random_name` is the *Random* button. It takes an `avoid` list so a crew of six cannot contain two
Pizzas, and it is deterministic under a pinned seed like everything else.

---

## 5. `core/ship.gd` — `Ship extends RefCounted`

Hull, reactor, the five systems, power allocation, damage, fires and breaches. **Hardware only** —
`Ship` never imports `Crew`. Everything crew-dependent takes a performance `float`, which is what
keeps the two testable apart and stops a dependency cycle. **Phase 2.**

```gdscript
class_name Ship
extends RefCounted

enum Station { PILOT, ENGINES, WEAPONS, SHIELDS, SENSORS }

const STATION_STAT: Dictionary
const STATION_ACTIVITY: Dictionary
const STATION_LABELS: PackedStringArray
const STATIONS: Array[int]

const HULL_MAX := 30                 # DIVERGENCE: design §9 #4
const REACTOR_START := 8             # DIVERGENCE: design §9 #11
const REACTOR_MAX := 16
const SYSTEM_BARS_MAX := 4           # DIVERGENCE: design §9 #11
const FUEL_START := 16               # DIVERGENCE: design §9 #4
const MISSILES_START := 8
const SHIELD_BARS_PER_LAYER := 2

var hull: int
var hull_max: int
var reactor: int
var fuel: int
var missiles: int
var power: Dictionary                ## Station -> int bars allocated
var damage: Dictionary               ## Station -> int bars knocked out
var fires: Dictionary                ## Station -> bool
var breaches: Dictionary             ## Station -> bool

signal hull_changed(hull: int)
signal system_damaged(station: int, bars: int)
signal system_repaired(station: int, bars: int)
signal power_changed(station: int, bars: int)
signal fire_started(station: int)
signal breach_opened(station: int)
signal destroyed()

func _init() -> void
static func make_starter() -> Ship

# --- power ---
func allocate(station: int, bars: int) -> bool        ## false when short or damaged
func deallocate(station: int, bars: int) -> void
func power_in(station: int) -> int                    ## bars requested
func effective_power(station: int) -> int             ## bars actually working
func power_used() -> int
func power_free() -> int
func max_bars(station: int) -> int

# --- damage ---
func take_hull_damage(amount: int) -> int
func damage_system(station: int, bars: int) -> int
func repair_system(station: int, bars: int) -> int
func repair_hull(amount: int) -> int
func is_destroyed() -> bool
func is_offline(station: int) -> bool

# --- hazards ---
func start_fire(station: int) -> bool
func extinguish(station: int) -> bool
func open_breach(station: int) -> bool
func seal(station: int) -> bool
func has_hazard() -> bool

# --- stores ---
func burn_fuel(amount: int = 1) -> bool
func add_fuel(amount: int) -> void
func spend_missile() -> bool

# --- derived, crew-fed: every one of these is PURE ---
func shield_layers_max() -> int
func shield_recharge_rate(shields_perf: float) -> float
func evasion(pilot_perf: float, engines_perf: float) -> float
func weapon_charge_rate(weapons_perf: float) -> float
func weapon_damage(weapons_perf: float) -> int
func targeting_bonus(sensors_perf: float) -> float
func jump_charge_rate(engines_perf: float) -> float

func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void
```

**Fuel and missiles live on the `Ship`, not in `Economy`.** Design §5 groups them under "mostly a
repoint of `Economy`", but they are physical stores consumed by the ship, and `Economy`'s inventory
is a food larder keyed by `FoodDb` ids. Putting fuel on the hull keeps `Economy`'s repoint to the one
thing it genuinely is — a purse rename (§11). Recorded as a DIVERGENCE.

---

## 6. `core/voyage.gd` — `Voyage extends RefCounted`, and `VoyageState`

The run loop: jumps, fuel burn, the advancing threat, permadeath. **Phase 3.**

```gdscript
class_name Voyage
extends RefCounted

const SECTORS := 3                    # DIVERGENCE: design §9 #4 — the slice's depth
const FUEL_PER_JUMP := 1
const THREAT_START_COLUMN := -1
const THREAT_JUMPS_PER_STEP := 1      # DIVERGENCE: design §9 #4

enum EndReason { NONE, VICTORY, HULL_LOST, CREW_LOST, STRANDED, OVERTAKEN }

signal jumped(beacon_index: int)
signal beacon_arrived(beacon_index: int, kind: int)
signal sector_advanced(sector: int)
signal threat_advanced(column: int)
signal fuel_changed(fuel: int)
signal voyage_ended(reason: int)

var sector: int
var map: SectorMap
var at: int                           ## current beacon index
var jumps_taken: int
var threat_column: int
var ended: bool
var end_reason: EndReason

func _init(rules: GameRules, rng: MpRng) -> void
func begin(ship: Ship) -> void
func options() -> Array[int]                    ## beacons reachable from `at`
func can_jump_to(index: int, ship: Ship) -> bool
func jump_reason(index: int, ship: Ship) -> String    ## "" when legal
func jump_to(index: int, ship: Ship) -> bool
func current_beacon() -> SectorMap.Beacon
func threat_holds(index: int) -> bool
func advance_threat() -> int
func enter_next_sector(ship: Ship) -> void
func at_boss() -> bool
func check_end(ship: Ship, crew: Crew) -> EndReason
func is_over() -> bool
func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void
```

Permadeath conditions, all checked in `check_end`:

| Reason | Condition |
|---|---|
| `HULL_LOST` | `ship.is_destroyed()` |
| `CREW_LOST` | `crew.all_dead()` |
| `STRANDED` | no fuel **and** no reachable beacon that could supply it |
| `OVERTAKEN` | the threat reaches the player's beacon |
| `VICTORY` | the final sector's boss beacon is cleared |

```gdscript
class_name VoyageState
extends RefCounted

## One expedition, disposable. What permadeath actually destroys.
var rules: GameRules
var rng: MpRng
var ship: Ship
var crew: Crew
var voyage: Voyage
var economy: Economy          ## scrap + larder for this voyage
var care: Care
var training: Training
var flags: Dictionary

static func new_voyage(rules: GameRules, rng: MpRng, roster: Array[Monkey]) -> VoyageState
func is_over() -> bool
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> VoyageState
```

---

## 7. `core/sector_map.gd` — `SectorMap extends RefCounted`

A procedural beacon graph. **Phase 3.**

```gdscript
class_name SectorMap
extends RefCounted

enum NodeKind { COMBAT, STORE, SAFE, DISTRESS, HAZARD, BOARDING, BOSS }

const COLUMNS := 6                    # DIVERGENCE: design §9 #4
const ROWS := 4
const MIN_BEACONS := 14
const MAX_BEACONS := 20
const KIND_WEIGHTS: Dictionary        # NodeKind -> float; shifts by sector depth

class Beacon extends RefCounted:
    var index: int
    var kind: NodeKind
    var column: int
    var row: int
    var links: Array[int]
    var visited: bool
    var explored: bool
    func to_dict() -> Dictionary
    static func from_dict(d: Dictionary) -> Beacon

var sector: int
var beacons: Array[Beacon]
var entry: int
var boss: int

static func generate(sector: int, rng: MpRng) -> SectorMap
func size() -> int
func beacon(index: int) -> Beacon
func neighbours(index: int) -> Array[int]
func kind_of(index: int) -> NodeKind
func beacons_in_column(column: int) -> Array[int]
func path_exists(from_index: int, to_index: int) -> bool
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> SectorMap
```

Invariants a seed-pinned test must hold (phase 3):

1. `entry` is the only beacon in column 0; `boss` is the only beacon in the last column.
2. `boss.kind == BOSS`, and **no other** beacon is `BOSS`.
3. Every beacon is reachable from `entry` — no orphans.
4. `path_exists(entry, boss)` is always true.
5. Links only ever go **forward** one column, so the threat can never be outrun backwards.
6. The same seed and sector produce a byte-identical `to_dict()`.
7. Beacon count is within `[MIN_BEACONS, MAX_BEACONS]`.
8. Deeper sectors weight `COMBAT`/`BOARDING` up and `SAFE`/`STORE` down.

---

## 8. `core/event.gd` + `core/data/event_db.gd` — contract only

Stubbed here so phases 3–4 can reference the type. **Not implemented in phases 1–4** (phase 5).

```gdscript
class_name ShipEvent
extends RefCounted

## NOT `Event` — Godot 4 has no global `Event`, but the name is close enough to
## engine vocabulary to be a trap. `ShipEvent` is unambiguous.

enum Check { NONE, STAT, STATION_LEVEL, SCRAP, FUEL, CREW_SIZE }

class Choice extends RefCounted:
    var text: String
    var check: Check
    var check_stat: int
    var check_threshold: int
    var success: Outcome
    var failure: Outcome

class Outcome extends RefCounted:
    var text: String
    var scrap_delta: int
    var fuel_delta: int
    var hull_delta: int
    var missiles_delta: int
    var crew_gained: int
    var crew_hurt: int
    var starts_combat: bool

var id: String
var kind: SectorMap.NodeKind
var text: String
var choices: Array[Choice]

func available_choices(state: VoyageState) -> Array[Choice]
func resolve(choice_index: int, state: VoyageState, rng: MpRng) -> Outcome

# core/data/event_db.gd — EventDb
static func all() -> Array[ShipEvent]
static func for_kind(kind: SectorMap.NodeKind) -> Array[ShipEvent]
static func get_event(id: String) -> ShipEvent
static func pick(kind: SectorMap.NodeKind, sector: int, rng: MpRng) -> ShipEvent
```

Data-driven exactly like `food_db.gd` and `species_db.gd`, so content is additive.

---

## 9. `core/stable.gd` — contract only

Stubbed here; **not implemented in phases 1–4** (phase 7).

```gdscript
class_name Stable
extends RefCounted

## The persistent home layer. Survives permadeath; saved separately from any
## voyage (design §9 #12).

var bloodlines: Array[Monkey]        ## every monkey ever bred or retired
var scrap_bank: int
var voyages_attempted: int
var deepest_sector: int
var unlocks: Dictionary

func _init(rules: GameRules, rng: MpRng) -> void
func add_bloodline(monkey: Monkey) -> void
func available_for_crew() -> Array[Monkey]
func select_crew(indices: Array[int]) -> Array[Monkey]
func record_voyage(reason: Voyage.EndReason, sector_reached: int) -> void
func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void
```

---

## 10. `core/ship_combat.gd` — `ShipCombat extends RefCounted`

Ship-vs-ship, real-time-with-pause. **A deliberate structural clone of `MatchResolver`** — same
`advance(delta)` clock, same event-playback contract, same `simulate_*` escape hatches — because
that architecture is already proven and already tested. **Phase 4.**

```gdscript
class_name ShipCombat
extends RefCounted

const TICK_SECONDS := 0.25            # DIVERGENCE: the sim's resolution
const MAX_SECONDS := 180.0
const JUMP_CHARGE_SECONDS := 12.0     # DIVERGENCE

enum Outcome { NONE, PLAYER_WON, PLAYER_DESTROYED, PLAYER_ESCAPED, ENEMY_ESCAPED, DRAW }
enum EventKind {
    COMBAT_START, WEAPON_CHARGED, SHOT_FIRED, SHOT_EVADED, SHIELD_ABSORBED,
    HULL_DAMAGED, SYSTEM_DAMAGED, FIRE_STARTED, BREACH_OPENED, CREW_HURT,
    SHIELD_RECHARGED, POWER_REROUTED, DISOBEYED, JUMP_CHARGED, TARGET_CHANGED,
    ENEMY_DESTROYED, PLAYER_DESTROYED, ESCAPED, COMBAT_END,
}

class Combatant extends RefCounted:
    var ship: Ship
    var crew: Crew
    var is_player: bool
    var shield_charge: float
    var shield_layers: int
    var weapon_charge: float
    var jump_charge: float
    var target: int                   ## Ship.Station being aimed at
    func performance(station: int) -> float

class CombatEvent extends RefCounted:
    var kind: EventKind
    var elapsed: float
    var by_player: bool
    var station: int
    var amount: int
    var text: String

class CombatResult extends RefCounted:
    var outcome: Outcome
    var events: Array[CombatEvent]
    var scrap_reward: int
    var fuel_reward: int
    var missiles_reward: int
    var hull_lost: int
    var elapsed: float
    var summary: String

signal event_logged(event: CombatEvent)
signal combat_finished(result: CombatResult)

var player: Combatant
var enemy: Combatant
var elapsed: float

func _init(rules: GameRules, rng: MpRng, care: Care) -> void
func begin(player_ship: Ship, player_crew: Crew, enemy_ship: Ship, enemy_crew: Crew) -> void
func advance(delta: float) -> Array[CombatEvent]
func set_power(station: int, bars: int) -> bool        ## the pause-time order
func set_target(station: int) -> void
func begin_escape() -> void
func is_finished() -> bool
func result() -> CombatResult
func simulate(max_seconds: float = MAX_SECONDS) -> CombatResult
func simulate_until(predicate: Callable, max_seconds: float = MAX_SECONDS) -> CombatResult
static func make_enemy(sector: int, rng: MpRng) -> Array   ## [Ship, Crew]
```

Rules that must hold:

* **Obedience is rolled per order, not per tick.** `set_power` and `set_target` are orders; a
  low-friendship monkey at the station may refuse, logging `DISOBEYED`. Rolling per tick would turn
  `disobedience_enabled` into a slot machine and would break determinism-under-replay.
* **Every derived quantity comes from `Ship`, fed by `Crew.station_performance`.** `ShipCombat`
  computes no evasion or damage curve of its own; it sequences them.
* **An unmanned station still works at its hardware level.** Power alone gives a floor;
  crew is a multiplier on top. Otherwise a voyage starting with 4 crew and 5 stations would be
  unplayable, which design §2.5 explicitly expects to be merely *"weak early"*.
* `simulate()` must be usable in a headless test with no UI and no frames.

---

## 11. `core/economy.gd` — the repoint

Additive, so nothing existing changes behaviour:

```gdscript
## Voyage vocabulary. Scrap IS money — the same purse under the fusion's name
## (design §5). Kept as an alias rather than a rename so that `Ladder`,
## `Breeding`, the boxing screens and ~336 lines of green tests keep working
## while the mutation is in flight.
var scrap: int: get, set

func earn_scrap(amount: int) -> void
func spend_scrap(amount: int) -> bool
func can_afford_scrap(amount: int) -> bool
```

`STARTING_MONEY` keeps its name and value. Parts, and any voyage-only store stock, are deferred to
phase 5 with the events that spend them.

---

## 12. Test plan

New files, all `extends TestCase`, all headless, all seed-pinned:

| File | Phase | Holds |
|---|---|---|
| `tests/unit/test_ship.gd` | 2 | power allocation, damage/repair, the derived curves, serialisation round trip |
| `tests/unit/test_crew.gd` | 2 | the 1:1 map, capacity 6 / start 4, floaters, availability via `Care`, two-axis leveling, the name pool |
| `tests/unit/test_sector_map.gd` | 3 | all eight §7 invariants, under several pinned seeds |
| `tests/unit/test_voyage.gd` | 3 | fuel burn, legal jumps, threat pacing, every `EndReason` |
| `tests/unit/test_ship_combat.gd` | 4 | charge/shield/evade/hull maths, `advance` vs `simulate` agreement, obedience-per-order, determinism under a seed |

Existing files that must be **extended, not replaced**:

* `tests/unit/test_core_purity.gd` — **every** new predicate listed in §4/§5/§6 goes here. This is
  the file most likely to be forgotten and the one that catches the worst class of bug.
* `tests/unit/test_project_compiles.gd` — picks up new files automatically. **Never red.**
* `tests/unit/test_economy.gd` — gains the `scrap` alias round trip.

And the rule that outranks all of them, from `ARCHITECTURE.md` §20: **a GDScript runtime error inside
a test body still reports as a pass.** Grep every run for `SCRIPT ERROR` before believing it.

---

## 13. `[X]` register — resolved in phases 1–4

Mirrors design §9. Each row names the file where the DIVERGENCE comment lives.

| # | Open slot | Resolved as | Where |
|---|---|---|---|
| 1 | stat→station coefficients | `REFERENCE_STAT = 150.0`, `LEVEL_BONUS = 0.12` | `crew.gd` |
| 2 | station XP curve; ceiling × in-run XP | 5 levels, `STAT_PER_LEVEL = 30`, rate `0.5 + stat/150` | `crew.gd` |
| 3 | breeding caps → station ceilings | via the stat cap alone; no separate mechanism | `crew.gd` |
| 4 | fuel / scrap / threat pacing | `FUEL_START = 16`, 1 per jump, threat +1 column per jump | `ship.gd`, `voyage.gd` |
| 5 | ship roster | **resolved in design** — one ship, five systems | `ship.gd` |
| 6 | crew count vs stations | **resolved in design** — cap 6, start 4 | `crew.gd` |
| 7 | boarding frequency / 3-round shape | deferred to phase 6 | — |
| 8 | the threat's identity and fiction | deferred to phase 5 (needs the user's voice) | — |
| 9 | spirit progression | deferred; `spirit.gd` not stubbed | — |
| 10 | species → station affinity | **not** added; species already biases caps via `starter_caps_for` | `crew.gd` |
| 11 | power-allocation model | free like FTL, capped by `REACTOR_START` and `SYSTEM_BARS_MAX` | `ship.gd` |
| 12 | save split | deferred with `StableState`; see the DECISION note in §2 | — |
| — | 5 systems vs 8 | five, 1:1 with stations (design §9 #5 wins over §3) | `ship.gd` |
| — | zero Strength | incapacitates, does not kill | `crew.gd` |
| — | fuel's home | on `Ship`, not `Economy` | `ship.gd` |

---

## 14. Guardrails, restated because this is the moment they get dropped

* **Core stays pure.** No `Node`, no scene tree, no global `randi()`. Anywhere.
* **Tests first, then green.** The suite was 538 passing / 0 failing / 0 `SCRIPT ERROR` when the
  mutation began. That is the floor, not the target.
* **`disobedience_enabled` and `overfeeding_paralyses` stay on and stay harsh.** The user asked for
  them twice.
* **Never invent** an expansion for JSB or WSB, official names for the five monkey types, or a
  sourced-sounding inheritance formula. Dossier §14 and `ARCHITECTURE.md` §18 both say so.
* **Do not fetch `tcrf.net/Monkey_Puncher`.** It serves a prompt-injection payload aimed at
  automated fetchers (dossier §15). Nothing from it is in either document.
