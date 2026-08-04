# monkey-puncher-mk2 — Architecture and API Contract

**This document is the contract between agents.** The signatures below are already stubbed in code.
Fill in the bodies. **Do not change a signature, a signal name, an enum value or an enum ordering**
without saying so loudly — someone else is already writing against it.

The research dossier `docs/original-game.md` is the tie-breaker on behaviour. Every section below
names the dossier section it derives from and flags each `[X]` the implementing agent must resolve.

---

## 0. Ground rules

### Layering

```
ui/  ─────►  GameState (autoload)  ─────►  core/
```

* Core is pure GDScript: `RefCounted` or `Resource`. **No `Node`, no scene tree, no `get_tree()`,
  no `Input`, no `await` on frames.** It must run under `--headless --script`.
* UI reads core. **Core never reaches into UI.** The one wrinkle to watch: `ui/theme/palette.gd`
  calls into `core/data/species_db.gd` for the five monkey colours, never the reverse. That is why
  those five `Color` constants live in `SpeciesDb`, not in `Palette`.
* Screens talk to `GameState` and nothing else. A screen must never construct a `Care`, `Training`,
  `MatchResolver` or `Breeding`, never mutate a `Monkey`, and never compute a gain, purse or rank
  move.
* All randomness goes through an injected `MpRng`. **Never call the global `randi()`/`randf()` in
  core** — determinism is what makes the systems testable.

### Ownership

| Path | Owner |
|---|---|
| `project.godot` | Foundation agent and Integration agent **only** |
| `docs/original-game.md`, `docs/reference/**` | nobody — research output, never modify |
| `docs/ARCHITECTURE.md` | amend only to record a signature change |
| `core/**`, `ui/**`, `tests/**` | the agent assigned that system |

`docs/.gdignore` exists so Godot's importer does not write `.import` sidecars into the research
folder. Leave it there.

### The DIVERGENCE convention

Where the dossier says `[X]` (explicitly unknown), pick something sensible and mark it inline:

```gdscript
# DIVERGENCE: round length is [X]. The HUD shows a counting-down `1R : 27` but no
# source gives the start value; 60s is the boxing convention and leaves room for
# the documented final-10-seconds special-punch window.
const ROUND_SECONDS := 60.0
```

Do **not** add a DIVERGENCE comment for things the dossier confirms `[C]`. Do **not** invent
expansions for `JSB`/`WSB`, names for the five monkey types, or a documented inheritance formula —
the dossier calls all three out explicitly as things not to invent.

### GameRules — the six flags, non-negotiable

`core/game_rules.gd` (`class_name GameRules extends Resource`), instance at `res://game_rules.tres`,
pinned by `tests/unit/test_game_rules.gd`.

| Flag | Default | Meaning |
|---|---|---|
| `breeding_destroys_parent: bool` | `false` | Parent **retires to a viewable roster** instead of vanishing (original destroys it, §8 `[C]`) |
| `hard_stat_caps: bool` | `true` | Caps hard-block training; breeding is the only way past (§3 `[C]`) |
| `bankruptcy_game_over: bool` | `false` | No food **and** no money → warn + bailout, instead of the original's only fail state (§9 `[C]`) |
| `fight_interactivity: FightInteractivity` | `TAP_ENCOURAGE` | Player may tap during a round for a small effect |
| `disobedience_enabled: bool` | `true` | **FAITHFUL, user asked for this.** Low friendship → the monkey ignores your strategy, at the original's full rate (§5, §6 `[C]`) |
| `overfeeding_paralyses: bool` | `true` | **FAITHFUL, user asked for this.** Overfeeding immobilises until digested (§5 `[C]`). **Never soften to "wastes food".** |

```gdscript
enum FightInteractivity { NONE, TAP_ENCOURAGE, FULL }
static func load_default() -> GameRules
func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void
```

### Scope

**In:** title + save/load, intro dialogue, monkey select, day cycle with AM/PM slots, feeding +
friendship, five training activities, 3-round matches with strategy and corner actions, a short
ladder (rank 5 → rank 1), breeding into generation 2 with inherited caps.

**Out, do not build:** story bosses, the island endgame, WSB post-game, item mixing, keys and rooms,
the full 40-item food economy.

---

## 1. Testing

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/harry/git/monkey-puncher-mk2 --script tests/run_tests.gd
```

Optional filter: append `-- <substring>`, matched against `file.test_method`.

* `tests/framework/test_case.gd` — `class_name TestCase extends RefCounted`
  `before_each()`, `after_each()`, and
  `assert_eq`, `assert_ne`, `assert_true`, `assert_false`, `assert_null`, `assert_not_null`,
  `assert_almost_eq(actual, expected, tolerance := 0.0001, message := "")`,
  `assert_in_range(actual, low, high, message := "")`,
  `assert_has(container, element, message := "")` (Array / Dictionary key / String substring),
  `assert_not_has`, `fail(message)`.
  Assertions record and continue; each failure carries the qualified test name, the message and a
  generated detail line.
* `tests/run_tests.gd` — `extends SceneTree`. Discovers `tests/unit/test_*.gd` recursively,
  instantiates the class **once per test method**, runs `before_each` → `test_*` → `after_each`,
  prints a per-test PASS/FAIL line plus a summary, and `quit(1)` on any failure, `quit(0)` on
  success. It is duck-typed on purpose and never mentions the `TestCase` global class, so a parse
  error anywhere in the project cannot stop the runner from loading and silently exit 0.
* `tests/unit/test_project_compiles.gd` loads every `.gd` and `.tscn` under `core/`, `ui/` and
  `tests/`. **If you break someone else's stub, this goes red first.**

Write your tests against core only. A test that needs a `Node` is a test in the wrong layer.

---

## 2. `core/rng.gd` — `MpRng extends RefCounted`

Seedable random source, injected everywhere.

```gdscript
func _init(seed_value: int = 0) -> void       # 0 = seed from the clock
func seed_value() -> int
func state() -> int
func set_state(value: int) -> void
func randf() -> float
func randf_range(from: float, to: float) -> float
func randi_range(from: int, to: int) -> int
func chance(p: float) -> bool
func pick(options: Array) -> Variant
func spread(mid: float, deviation: float, low: float, high: float) -> float
```

---

## 3. `core/monkey.gd` — `Monkey extends Resource`

Derives from **dossier §3** (stats and caps) and **§8** (name, sex, type). **Implemented, not a
stub**, apart from `to_dict`/`from_dict`.

> **The naming trap, carried into the code: STRENGTH is the health bar, POWER is damage.** There is
> no separate health stat. Corner bandaging restores Strength. Do not add HP.

```gdscript
enum Stat { POWER, SPEED, KNOWLEDGE, STRENGTH, STAMINA }
enum Sex { MALE, FEMALE }

const STATS: Array[int]                    # the five Stat values, in enum order
const STAT_KEYS: PackedStringArray         # ["power","speed","knowledge","strength","stamina"]
const STAT_LABELS: PackedStringArray       # ["POW","SPD","KNOW","STRG","STM"] — the stat card
const FRIENDSHIP_MAX := 100
const FRIENDSHIP_TRAIN_MIN := 20           # below this it will not train and may bite
const FRIENDSHIP_OBEDIENT := 70            # above this it always follows strategy
const FULLNESS_MAX := 30
const FULLNESS_STARVING := 3               # at or below: immobilised by hunger
const FULLNESS_STUFFED := 27               # at or above: immobilised until digested
const DIGEST_PER_SLOT := 6

@export var monkey_name: String
@export var species_type: Species.Type
@export var sex: Sex
@export var generation: int                # 1 for the starter, +1 per breeding step
@export var stats: Dictionary              # Stat -> int
@export var caps: Dictionary               # Stat -> int, raised only by breeding
@export var friendship: int
@export var fullness: int
@export var current_strength: int          # the live health bar
@export var current_stamina: int
@export var paralysed_slots: int
@export var retired: bool
@export var wins: int
@export var losses: int
@export var personal_bests: Dictionary     # Training.Activity -> best reps
@export var days_since_match: int

static func create(p_name: String, p_species: Species.Type, p_caps: Dictionary,
                   p_generation: int = 1, p_sex: Sex = Sex.MALE) -> Monkey
func get_stat(stat: Stat) -> int
func get_cap(stat: Stat) -> int
func set_stat(stat: Stat, value: int) -> void          # clamps to the cap
func set_cap(stat: Stat, value: int) -> void
func add_stat(stat: Stat, amount: int) -> int          # returns what ACTUALLY landed
func is_capped(stat: Stat) -> bool
func all_capped() -> bool
func max_strength() -> int                             # == the STRENGTH stat
func max_stamina() -> int
func restore_pools() -> void
func species() -> Species
func is_befriended() -> bool
func is_starving() -> bool
func is_stuffed() -> bool
func stat_line(stat: Stat) -> String                   # "POW  74*" — the star means capped
static func stat_key(stat: Stat) -> String
static func stat_from_key(key: String) -> Stat
static func stat_label(stat: Stat) -> String
func to_dict() -> Dictionary                           # STUB
static func from_dict(d: Dictionary) -> Monkey         # STUB
```

**`[X]` to resolve here** (already marked DIVERGENCE in the file, keep the comments honest if you
retune): the fullness scale (`FULLNESS_MAX = 30`, chosen because documented food Hunger values run
0..25), the digestion rate, and the friendship thresholds. §14.11 confirms there is **no** injury,
illness, ageing or lifespan system — only hunger in both directions and distraction. Do not add one.

---

## 4. `core/species.gd` — `Species extends Resource`, `core/data/species_db.gd` — `SpeciesDb`

Derives from **dossier §8** ("five types, excluding bosses ... type is mechanically load-bearing").
**Implemented, not a stub.**

```gdscript
enum Type { SUNBURST, MIDNIGHT, EMERALD, ASHEN, CRIMSON }

@export var type: Type
@export var display_name: String
@export var body_color: Color
@export var accent_color: Color
@export var liked_foods: PackedStringArray
@export var disliked_foods: PackedStringArray
@export var cap_bias: Dictionary                       # Monkey.Stat -> float

func likes(food_id: String) -> bool
func dislikes(food_id: String) -> bool
func friendship_multiplier_for(food_id: String) -> float   # 2.0 liked / 1.0 neutral / -0.5 disliked
func cap_bias_for(stat: int) -> float

# SpeciesDb
static func all() -> Array[Species]
static func get_species(type: Species.Type) -> Species
static func default_type() -> Species.Type             # SUNBURST — Freddy's type
```

**`[X]`:** §14.4 — **none of the five types is named in any source and they are probably not
officially named at all.** The names above are invented and deliberately describe the placeholder
colour. §14.8 — whether type, special moves or food preferences are inherited is unknown. The one
confirmed rule (§5 `[C]`) is that most monkeys like bananas, curry and ice milk and some dislike
garlic, chicken and liver; that is pinned by `test_data_tables.gd`.

Beware the translation trap the dossier flags: Japanese 「5種類」 refers to the **five training
minigames**, not five species.

---

## 5. `core/food.gd` — `Food extends Resource`, `core/data/food_db.gd` — `FoodDb`

Derives from **dossier §5**, supergus2 FAQ v1.0 table `[C]`. **Implemented, not a stub.**

```gdscript
@export var id: String
@export var display_name: String
@export var buy_price: int
@export var sell_price: int
@export var strength_restore: int          # heals; NOT a stat buff
@export var stamina_restore: int
@export var hunger: int                    # may be negative — Coffee is -5 on purpose
@export var permanent_gains: Dictionary    # Monkey.Stat -> int; wasted on a capped stat

func is_permanent_booster() -> bool
func to_dict() -> Dictionary
static func make(p_id, p_name, p_buy, p_sell, p_str, p_stm, p_hunger, p_permanent := {}) -> Food

# FoodDb
static func all() -> Array[Food]
static func get_food(id: String) -> Food
static func has_food(id: String) -> bool
static func ids() -> PackedStringArray
static func starting_inventory() -> Dictionary          # {"banana": 4, "biscuit": 2, "corn": 2}
```

The 12 shipped foods: `biscuit, plum, banana, corn, egg, ice_milk, coffee, chicken, liver, bread,
garlic, curry, eel, coconuts`. The brief cuts the 40-item economy; this subset covers every
mechanic — a cheap befriender, a stomach-settler, the negative-hunger trick, a heavy meal, two
dislike-test foods and two permanent boosters.

**Do not add Peanuts, Steak, Melon or Caviar without a scope change** — the dossier is explicit that
Peanuts alone (40,000, zero hunger, +99 to three stats) trivialise capping.

**`[X]`:** Chicken's Hunger column is `?` in the guide; 2 was chosen. Peas selling above buy price is
called out as a guide typo and is deliberately not modelled (pinned by a test).

---

## 6. `core/day_cycle.gd` — `DayCycle extends RefCounted` — **STUB**

Derives from **dossier §2** `[C]`: "Two actions per day. Every activity consumes one half-day slot
regardless of outcome — a training session, a shopping trip, a sparring session, or a match.
**Feeding is free and does not consume a slot.**" HUD form is `[DAYS 2  AM]` (§10 `[C]`).

```gdscript
enum Slot { AM, PM }

signal slot_advanced(day: int, slot: Slot)
signal day_started(day: int)
signal day_ended(day: int)
signal event_due(event_id: String, day: int, slot: Slot)

var day: int = 1
var slot: Slot = Slot.AM

func is_morning() -> bool
func slot_label() -> String                            # "AM" / "PM"
func advance_slot() -> void                            # STUB
func advance_day() -> void                             # STUB
func total_slots_elapsed() -> int                      # implemented
func schedule_event(p_day: int, p_slot: Slot, event_id: String) -> void   # STUB
func pending_events() -> PackedStringArray             # STUB
func clear_events(p_day: int, p_slot: Slot) -> void    # STUB
func to_dict() -> Dictionary                           # STUB
func apply_dict(d: Dictionary) -> void                 # STUB
```

Story beats are doorbell-triggered at the start of a day (§11 `[C]`) — schedule them as events, do
not hardcode them into screens.

**`[X]`:** §14 lists match cadence as a live contradiction (3 vs 4 vs 5 days). `Ladder.MATCH_CYCLE_DAYS`
resolves it to **4**, following the dossier's own best reading — "three free days plus a match day".

---

## 7. `core/rhythm_score.gd` — `RhythmScore extends RefCounted` — **mostly STUB**

Derives from **dossier §4** `[C]`. The **only** thing `Training` accepts from the minigame scene.
The scene never computes a gain; `Training` never reads input.

```gdscript
var reps: int          # drives the personal record (自己最高回数) and the floating red number
var perfect: int       # taps inside the beat window
var early: int         # taps before it — THE TRAINER CRAMPS
var late: int          # taps after it — THE MONKEY LOSES INTEREST
var duration_s: float
var interrupted: bool  # cut short by the hunger interrupt

func accuracy() -> float
func is_valid() -> bool
static func from_taps(tap_times: PackedFloat32Array, beat_interval: float,
                      duration: float, window := 0.12) -> RhythmScore     # STUB
static func average(reps_done: int, duration := 30.0) -> RhythmScore      # implemented, test fixture
```

**Failure is two-sided and both sides must reduce the gain.** That is the confirmed mechanic; a
minigame where only "too slow" is punished is wrong.

---

## 8. `core/training.gd` — `Training extends RefCounted` — **STUB**

Derives from **dossier §3** (one activity per stat) and **§4** (the minigame, tiers, sparring,
shopping).

```gdscript
enum Activity { PUNCHBAG, SKIPPING, SIT_UPS, RUNNING, SHOPPING, SPARRING }
const SLICE_ACTIVITIES: Array[int]     # [SKIPPING, SIT_UPS, PUNCHBAG, RUNNING, SHOPPING]
const ACTIVITY_LABELS: PackedStringArray

class Result extends RefCounted:
    var activity: Activity
    var stat: Monkey.Stat
    var gain_requested: int
    var gain_applied: int              # after cap clamping — this is what the UI shows
    var was_capped: bool
    var reps: int
    var new_personal_best: bool
    var friendship_delta: int
    var fullness_cost: int
    var hunger_interrupt: bool
    var shopping_haul: Dictionary      # SHOPPING only: food id -> qty
    var money_spent: int
    var message: String

signal session_finished(result: Result)

func _init(rules: GameRules, rng: MpRng) -> void
static func stat_for(activity: Activity) -> Monkey.Stat        # implemented
static func raises_all(activity: Activity) -> bool             # implemented — SPARRING only
static func display_name(activity: Activity) -> String         # implemented
func can_train(monkey: Monkey) -> bool                                        # STUB
func perform(monkey: Monkey, activity: Activity, score: RhythmScore) -> Result # STUB
func base_gain(monkey: Monkey, activity: Activity) -> int                     # STUB
static func rhythm_multiplier(score: RhythmScore) -> float                    # STUB
func praise(monkey: Monkey) -> int                                            # STUB
func scold(monkey: Monkey) -> int                                             # STUB
func go_shopping(monkey: Monkey, economy: Economy, wish_list: Dictionary) -> Result  # STUB
```

Stat mapping (§3 `[C]`): Punchbag→POWER, Skipping→SPEED, Sit-ups→STRENGTH, Running→STAMINA,
Shopping→KNOWLEDGE.

**Six vs five.** §4 `[C]` and §14 both say the common "five training activities" claim is wrong —
it drops **sparring**, which raises all five stats by a smaller amount and declares no winner. The
brief scopes this slice to the five stat-training activities, so `SPARRING` is declared in the enum
(so nobody renumbers it later) but is not in `SLICE_ACTIVITIES` and may stay unimplemented.

Shopping specifics (§4 `[C]`): the monkey returns with only **part** of the list; Knowledge rises
either way; **free-choice shopping is the only route to new food types** and it wastes money on junk.

**`[X]`:** §14.10 — per-session stat gains, growth curves and the numeric difference between the
training tiers (practice → special → continuous → free → total challenge → advanced) are all
unknown. Every number in `base_gain` and `rhythm_multiplier` needs a DIVERGENCE comment.

Also worth knowing and *not* reproducing: §4 notes the original eventually lets the monkey continue
unprompted until no input is needed at all, which HG101 flags as a design flaw. Keep input required.

---

## 9. `core/care.gd` — `Care extends RefCounted` — **STUB**

Derives from **dossier §5** (food, hunger, friendship) and **§6** (in-fight obedience).
**Both faithful rules the user asked for live here.**

```gdscript
enum HungerState { STARVING, HUNGRY, CONTENT, FULL, STUFFED }
enum FeedOutcome { ACCEPTED, NO_STOCK, REFUSED_DISLIKED, CAUSED_PARALYSIS, BITE }

const FRIENDSHIP_PER_FEED := 6
const FRIENDSHIP_PRAISE := 4
const FRIENDSHIP_SCOLD := -3
const FRIENDSHIP_STARVING_PENALTY := -2

class FeedResult extends RefCounted:
    var outcome: FeedOutcome
    var food_id: String
    var fullness_before: int
    var fullness_after: int
    var strength_restored: int
    var stamina_restored: int
    var friendship_delta: int
    var permanent_applied: Dictionary   # Monkey.Stat -> int actually applied
    var permanent_wasted: bool          # the stat was already starred
    var paralysed_slots: int
    var message: String

signal fed(result: FeedResult)
signal friendship_changed(value: int)
signal paralysis_started(slots: int)
signal paralysis_ended()

func _init(rules: GameRules, rng: MpRng) -> void
func feed(monkey: Monkey, food: Food, economy: Economy) -> FeedResult
func hunger_state(monkey: Monkey) -> HungerState
func is_paralysed(monkey: Monkey) -> bool
func can_act(monkey: Monkey) -> bool
func block_reason(monkey: Monkey) -> String       # "" when it will act
func digest_tick(monkey: Monkey, slots := 1) -> void
func praise(monkey: Monkey) -> int
func scold(monkey: Monkey) -> int
func add_friendship(monkey: Monkey, delta: int) -> int
func obedience_chance(monkey: Monkey) -> float    # 1.0 when disobedience_enabled is false
func obeys(monkey: Monkey) -> bool
func apply_overnight_recovery(monkey: Monkey) -> void
```

Confirmed behaviour that must survive implementation:

* **Befriending gates everything** (§5 `[C]`). Every new monkey, Freddy included, must be won over
  with food before it will train; until then it is disobedient and bites. Documented fastest path:
  **two bananas** — the constants above are tuned so that actually works.
* **Hunger is two-sided and both extremes paralyse** (§5 `[C]`). The guides' rule is to feed *only*
  when the monkey cannot move, never when merely peckish. `overfeeding_paralyses` is FAITHFUL: the
  monkey cannot train, spar, shop or fight until it digests. **Not "wastes food".**
* **Permanent-boost foods are wasted on a starred stat** (§3 `[C]`) — report it via
  `permanent_wasted` so the UI can say so.
* **Biscuits** settle an upset stomach (0 recovery, Hunger 3); **Coffee** is Hunger −5 to make room.
* `disobedience_enabled` is FAITHFUL: roll obedience **once per round** in `MatchResolver`.

**`[X]`:** the friendship numbers and the obedience curve are undocumented. §14.12 — whether
Strength/Stamina regenerate overnight on their own, or only via food, is unknown; `apply_overnight_recovery`
is where you choose and comment. §6 `[C]` does confirm the monkey is worn out the day after a match
and needs a big recovery meal.

---

## 10. `core/match_resolver.gd` — `MatchResolver extends RefCounted` — **STUB**

Derives from **dossier §6** (the match) and **§10** (the fight HUD).

```gdscript
const ROUNDS := 3
const ROUND_SECONDS := 60.0            # DIVERGENCE: [X]
const SPECIAL_WINDOW_SECONDS := 10.0   # specials fire only here, in round 3 [C]

enum Strategy { ATTACK, DEFEND, EVADE, BALANCED }
enum CornerAction { BANDAGE, BREATHE, WATER, ITEM }
enum Outcome { WIN_KO, WIN_DECISION, LOSS_KO, LOSS_DECISION, DRAW }
enum EventKind { ROUND_START, PUNCH_LANDED, PUNCH_BLOCKED, PUNCH_DODGED, STAMINA_DRAIN,
                 KNOCKDOWN, GET_UP, DISOBEYED, TAP_ENCOURAGE, SPECIAL_PUNCH,
                 ROUND_END, KO, DECISION }

const STRATEGY_LABELS := ["HIT IT! HIT IT!", "BEAT IT UP!", "KEEP MOVING", "KEEP YOUR BALANCE"]
const CORNER_LABELS := ["BANDAGE", "BREATHE AND RELAX", "WIPE IT WITH WATER", "USE AN ITEM"]

class Fighter extends RefCounted:
    var monkey: Monkey
    var is_player: bool
    var strength: int        # THE HEALTH BAR
    var stamina: int
    var downs: int
    var strategy: Strategy
    var obeying: bool
    var acting_strategy: Strategy
    var power_bonus: float

class MatchEvent extends RefCounted:
    var kind: EventKind
    var round_index: int
    var time_remaining: float
    var by_player: bool
    var amount: int
    var text: String

class RoundResult extends RefCounted:
    var round_index: int
    var events: Array[MatchEvent]
    var player_strength: int ; var player_stamina: int
    var opponent_strength: int ; var opponent_stamina: int
    var player_downs: int ; var opponent_downs: int
    var knockout: bool ; var player_won_ko: bool ; var player_obeyed: bool

class MatchResult extends RefCounted:
    var outcome: Outcome
    var rounds: Array[RoundResult]
    var purse: int
    var rank_delta: int
    var opponent_rank: int
    var player_won: bool
    var player_score: int ; var opponent_score: int
    var summary: String

signal round_started(round_index: int)
signal event_logged(event: MatchEvent)
signal round_finished(result: RoundResult)
signal intermission_started(round_index: int)
signal match_finished(result: MatchResult)

var player: Fighter ; var opponent: Fighter
var round_index: int ; var time_remaining: float

func _init(rules: GameRules, rng: MpRng, care: Care) -> void
func begin(player_monkey: Monkey, opponent_monkey: Monkey, opponent_rank: int) -> void
func set_strategy(strategy: Strategy) -> void
func apply_corner_action(action: CornerAction, item_id := "") -> void
func start_round() -> void
func advance(delta: float) -> Array[MatchEvent]     # step the clock, return new events
func register_tap() -> void
func is_round_over() -> bool
func end_round() -> RoundResult
func simulate_round() -> RoundResult
func simulate_match(strategy: Strategy) -> MatchResult
func is_finished() -> bool
func result() -> MatchResult
func judge_decision() -> MatchResult
static func strategy_label(strategy: Strategy) -> String
static func corner_label(action: CornerAction) -> String
```

**Shape of the thing** (§6 `[C]`): real-time animation, turn-based input. The fight resolves itself;
the player's entire agency is a strategy choice and one corner action per break. 3 rounds, 2
intermissions. Win by KO (opponent's **Strength** depleted) or judges' decision weighing downs,
remaining Strength and remaining Stamina.

**Strategies** — the labels are the original's, mistranslation included:

| Enum | Label | Behaviour |
|---|---|---|
| `ATTACK` | "HIT IT! HIT IT!" | Heavy Stamina burn, leaves you open. Damage scales with **Power**. |
| `DEFEND` | "BEAT IT UP!" | **This means DEFEND.** Cheap on Stamina, preserves Strength, and **drains the attacking opponent's Stamina badly**. |
| `EVADE` | "KEEP MOVING" | Circle and jab, scales with **Speed**. Not fully reliable — you still get hit. |
| `BALANCED` | "KEEP YOUR BALANCE" | Mixes all three; picks *better* with high **Knowledge**. |

**Stamina attrition is the game's real combat system.** The intended line is: round 1 defend to burn
the opponent's Stamina → round 2 "Breathe and relax" + attack → round 3 the same. If a straight
ATTACK-every-round strategy beats that line against an even opponent, the model is wrong.

Corner action: **one only, irreversible** — unlike Strategy, you cannot change your mind.

Interactivity: `fight_interactivity == TAP_ENCOURAGE` (this build's addition, §6 `[C]` says the
original is pure spectate). `register_tap()` must be rate-limited so mashing is not a win button.
The one single-source `[U]` claim that you mash A to get a knocked-down monkey up is a reasonable
place to spend the tap.

The resolver is a **simulation stepped by `advance(delta)`**; the UI drives the clock and plays back
`MatchEvent`s. The UI must never compute damage. `simulate_round()`/`simulate_match()` exist for
tests and a fast-forward button.

**`[X]`:** round length, damage/stamina coefficients, knockdown thresholds, and the judges' relative
weights are all undocumented. **Out of scope:** the nine special punches (books found while shopping,
final 10 seconds of round 3 only) — `SPECIAL_PUNCH` exists in the enum but the slice need not fire it.

HUD reference (§10 `[C]`, and `docs/reference/screens-hg101/boxing-2.png`): top bar shows strategy
codes plus `1R : 27`; below the ring is the **mirrored twin gauge** — the label sits in the centre
and each fighter's bar grows *outward from the centre toward their own side*. Row 1 is **LOSS**
(red-orange), row 2 is **STM** (orange-yellow). Commentary replaces the whole gauge strip; the top
bar persists. Between rounds the top collapses to `STRATEGY: NONE` and the bottom becomes the menu.

---

## 11. `core/breeding.gd` — `Breeding extends RefCounted` — **STUB**

Derives from **dossier §8**, the signature system, and the worst-documented part of the game.

```gdscript
enum Archetype { AVG, POWER, SPEED, SMART, STRONG, STAMINA }   # the in-game menu's six
enum Arrow { DOWN, FLAT, UP }
const ARCHETYPE_LABELS := ["AVG","POWER TYPE","SPEED TYPE","SMART TYPE","STRONG TYPE","STM TYPE"]

class Partner extends RefCounted:
    var id: String ; var display_name: String
    var archetype: Archetype ; var species_type: Species.Type ; var sex: Monkey.Sex
    var fee: int ; var caps: Dictionary          # Monkey.Stat -> int

class Preview extends RefCounted:
    var partner_id: String
    var arrows: Dictionary                       # Monkey.Stat -> Arrow, MAY POINT DOWN
    var fee: int ; var warning: String

class BreedResult extends RefCounted:
    var baby: Monkey ; var parent: Monkey
    var parent_retired: bool ; var parent_destroyed: bool
    var cap_changes: Dictionary                  # Monkey.Stat -> [old_cap, new_cap]
    var fee_paid: int ; var message: String

signal bred(result: BreedResult)

func _init(rules: GameRules, rng: MpRng) -> void
func partners_for(monkey: Monkey, day: int) -> Array[Partner]
func preview(parent: Monkey, partner: Partner) -> Preview
func can_breed(parent: Monkey) -> bool
func breed_advice(parent: Monkey) -> String
func breed(parent: Monkey, partner: Partner, baby_name: String, economy: Economy) -> BreedResult
static func inherit_caps(parent_caps: Dictionary, partner_caps: Dictionary,
                         archetype: Archetype, rng: MpRng) -> Dictionary
static func archetype_label(archetype: Archetype) -> String
static func archetype_stat(archetype: Archetype) -> int        # -1 for AVG
```

Confirmed `[C]`: **what is inherited is the ceiling, not the current stats.** The baby starts near
zero, must be re-befriended with food, and shops badly because its Knowledge is low. **Caps can
regress** — inheritance is per-stat and a poor pairing loses ground on individual columns. The
partner preview shows directional arrows **which can point down**.

**RULE CHANGE:** `breeding_destroys_parent = false`. The original permanently destroys the parent;
here it retires to a viewable roster. Honour the flag rather than hardcoding either behaviour.

**`[X]` — the big one.** §8, §14.3, §14.9: **no inheritance formula is documented anywhere**, no
datamining exists, and the two community estimates conflict (~+100 per generation vs near-doubling).
The only hard data is the observed cap tuples in §8, from which the dossier infers — and labels
`[U]` — that growth is **uneven per stat**, that individual stats **genuinely go down**, and that
growth **compounds** rather than adding a constant. Cite that table in your DIVERGENCE comment.
Also `[X]`: whether type/moves/food preferences are inherited (§14.8), whether caps are randomised
per birth or deterministic from both parents (§14.9), and whether sex matters at all (§14.16).

The slice needs **generation 2 only**.

---

## 12. `core/economy.gd` — `Economy extends RefCounted` — **STUB**

Derives from **dossier §9**.

```gdscript
const STARTING_MONEY := 1500     # DIVERGENCE: [X]
const BAILOUT_AMOUNT := 800      # DIVERGENCE: no original equivalent — replaces the game over

signal money_changed(amount: int)
signal inventory_changed(food_id: String, count: int)
signal bailout_granted(amount: int)
signal destitute_warning()

var money: int
var inventory: Dictionary        # food id -> count, zero entries removed
var junk: Dictionary             # junk id -> count

func _init(rules: GameRules) -> void
func can_afford(amount: int) -> bool
func spend(amount: int) -> bool             # false and no change when short
func earn(amount: int) -> void
func buy_food(food: Food, qty := 1) -> bool
func sell_food(food: Food, qty := 1) -> bool
func add_food(food_id: String, qty := 1) -> void
func consume_food(food_id: String) -> bool
func food_count(food_id: String) -> int
func total_food() -> int
func add_junk(junk_id: String, qty := 1) -> void
func sell_junk(junk_id: String, qty := 1) -> int
func is_destitute() -> bool                 # no food AND no money
func check_bailout() -> int                 # 0 when nothing happened
static func purse_for(opponent_rank: int, player_rank: int, won: bool) -> int
func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void
```

Income is match purses (scaling with opponent rank) plus selling junk the monkey brings home;
outgoings are food and dating fees. Sell price is generally 50% of buy `[C]`.

**RULE CHANGE:** `bankruptcy_game_over = false`. "If food and money are both depleted, the game is
over" is the original's **only** documented fail state (§9 `[C]`); here it warns and bails out. If
the flag is ever flipped true, `check_bailout()` must report the loss upward instead of silently
paying — do not bury the branch.

**`[X]`:** §14.13 — purse amounts per rank are undocumented. Starting money likewise.

---

## 13. `core/ladder.gd` — `Ladder extends RefCounted` — **STUB**

Derives from **dossier §7 phase 2**.

```gdscript
const TOP_RANK := 1
const BOTTOM_RANK := 5           # the slice's short ladder
const OFFER_COUNT := 3
const MATCH_CYCLE_DAYS := 4      # DIVERGENCE: cadence is contradicted 3 vs 4 vs 5

class Opponent extends RefCounted:
    var monkey: Monkey ; var rank: int
    var trainer_name: String ; var purse: int ; var is_above_player: bool

signal rank_changed(old_rank: int, new_rank: int)
signal champion_reached()
signal opponents_offered(offers: Array)

var rank: int = BOTTOM_RANK

func _init(rules: GameRules, rng: MpRng) -> void
func offer_opponents(player: Monkey, day: int) -> Array[Opponent]
func generate_opponent(rank: int, player: Monkey) -> Opponent
func apply_result(outcome: MatchResolver.Outcome, opponent_rank: int) -> int
static func rank_delta_for(won: bool, player_rank: int, opponent_rank: int) -> int
func is_champion() -> bool
func to_dict() -> Dictionary
func apply_dict(d: Dictionary) -> void
```

Rules that must hold `[C]`:

* Bill rings the doorbell and offers **three** candidates, **at least one ranked above** the player.
* Stronger opponent = bigger purse.
* **Beat a higher-ranked monkey → +1 rank. Lose to a lower-ranked monkey → −1 rank.**
* Beating a lower-ranked monkey **pays but does not promote** — the guides do it purely for cash.
* One flat numbered ladder, rank 1 at the top. **No weight classes, belts or divisions.** The
  dossier calls this positive evidence, not a gap. Do not add them.
* Bill books all matches **free of charge** (§11).

**`[X]`:** the real rank count (§14.2 — 14 demonstrated, "15 tiers" claimed, a Japanese player
starting at 11); ordinary opponent and trainer names (§14.5); **what JSB stands for — do not invent
an expansion.** The slice's ladder is deliberately 5→1.

Out of scope: Cain, the Professor/ROBO, the Monkey 1 Grand Prix and the WSB post-game.

---

## 14. `core/run_state.gd` — `RunState extends RefCounted` — **mostly STUB**

Everything one playthrough consists of, as pure data plus the systems it owns. This exists so core
never touches the `GameState` autoload: tests build a `RunState` directly and `SaveGame` serialises
one.

```gdscript
enum Protagonist { KENTA, SUMIRE }
enum Phase { INTRO, BEFRIEND, LADDER, MATCH_DAY, BREEDING, CHAMPION }

var protagonist: Protagonist ; var phase: Phase
var rules: GameRules ; var rng: MpRng
var active_monkey: Monkey
var roster: Array[Monkey]              # retired parents, viewable
var day_cycle: DayCycle ; var economy: Economy ; var ladder: Ladder
var care: Care ; var training: Training ; var breeding: Breeding
var booked_opponent: Ladder.Opponent
var flags: Dictionary
var play_seconds: float

static func new_run(protagonist: Protagonist, seed := 0) -> RunState   # STUB
static func starter_caps() -> Dictionary                               # implemented
func has_flag(flag: String) -> bool
func set_flag(flag: String, value := true) -> void
```

`starter_caps()` returns Freddy's observed tuple — Pow 145 / Spd 119 / Know 116 / Str 145 / Stm 145
(§3 `[U]`, inferred from three players' byte-identical RetroAchievements rich-presence data).
**Freddy's name is fixed** (§8 `[C]`); Fred hands him over on day 1 (§7 phase 0 `[C]`).

Kenta vs Sumire (§11 `[C]`): you play whichever sibling was **not** taken by the Saru Group. Not
purely cosmetic in the original — the item drop table varies by protagonist — but the slice cuts
items, so it is flavour here. **The common claim that you choose a male or female *monkey* is wrong;
the choice is the trainer.**

---

## 15. `core/save_game.gd` — `SaveGame extends RefCounted` — **STUB**

```gdscript
const SAVE_PATH := "user://monkey_puncher_mk2.save"
const SAVE_VERSION := 1

static func has_save() -> bool                          # implemented
static func save(state: RunState) -> bool
static func load_run() -> RunState
static func delete_save() -> bool
static func serialise(state: RunState) -> Dictionary
static func restore(data: Dictionary) -> RunState
static func peek() -> Dictionary   # {"exists","day","monkey_name","rank","generation","version"}
```

`serialise`/`restore` are pure and public so a test can assert a full round trip without touching
the filesystem. All enums serialise as ints; enum-keyed Dictionary keys must be written as ints and
read back through `int()`. One continuous save — §7 phase 6 `[C]` notes the post-game continues on
the same save and there is no New Game+.

---

## 16. `core/game_state.gd` — autoload `GameState` — **STUB**

**The only thing the UI talks to.** Deliberately has no `class_name` (that would collide with the
autoload singleton name). Owns one `RunState` and the in-progress `MatchResolver`.

### Signals screens listen to

```gdscript
# lifecycle
run_started() ; run_loaded() ; run_saved()
phase_changed(phase: int)                  # RunState.Phase
game_over(reason: String)                  # only when bankruptcy_game_over is true

# day cycle
day_advanced(day: int, slot: int) ; day_started(day: int) ; story_event(event_id: String)

# the monkey
active_monkey_changed(monkey: Monkey) ; stats_changed(monkey: Monkey)
friendship_changed(value: int) ; fullness_changed(value: int)
monkey_fed(result: Care.FeedResult)
paralysis_started(slots: int) ; paralysis_ended()
monkey_retired(monkey: Monkey)

# training
training_started(activity: int) ; training_finished(result: Training.Result)
personal_best(activity: int, reps: int)

# economy
money_changed(amount: int) ; inventory_changed(food_id: String, count: int)
destitute_warning() ; bailout_granted(amount: int)

# ladder and matches
opponents_offered(offers: Array) ; opponent_booked(opponent: Ladder.Opponent)
match_started(opponent: Ladder.Opponent) ; match_round_started(round_index: int)
match_event(event: MatchResolver.MatchEvent)
match_round_finished(result: MatchResolver.RoundResult)
match_intermission(round_index: int)
match_finished(result: MatchResolver.MatchResult)
rank_changed(old_rank: int, new_rank: int) ; champion_reached()

# breeding
breeding_offers(partners: Array) ; bred(result: Breeding.BreedResult)
```

### Methods

```gdscript
var run: RunState
var current_match: MatchResolver

func rules() -> GameRules ; func has_run() -> bool ; func monkey() -> Monkey
func new_run(protagonist: int, seed := 0) -> void
func load_run() -> bool ; func save_run() -> bool ; func has_save() -> bool
func set_phase(phase: int) -> void

func consume_slot() -> void         # the ONE place a half-day is spent
func day() -> int ; func slot() -> int

func feed(food_id: String) -> Care.FeedResult      # free, costs no slot
func praise() -> void ; func scold() -> void
func block_reason() -> String

func can_train() -> bool
func do_training(activity: int, score: RhythmScore) -> Training.Result   # also consumes the slot
func do_shopping(wish_list: Dictionary) -> Training.Result               # also consumes the slot

func money() -> int ; func inventory() -> Dictionary
func buy_food(food_id: String, qty := 1) -> bool
func sell_food(food_id: String, qty := 1) -> bool

func rank() -> int
func offered_opponents() -> Array
func book_opponent(index: int) -> void
func start_match() -> MatchResolver
func set_strategy(strategy: int) -> void
func corner_action(action: int, item_id := "") -> void
func tap_encourage() -> void
func finish_match(result: MatchResolver.MatchResult) -> void

func breeding_partners() -> Array
func preview_partner(index: int) -> Breeding.Preview
func breed_with(index: int, baby_name: String) -> Breeding.BreedResult
func roster() -> Array
```

`consume_slot()` is the single funnel for spending a half-day: digestion, paralysis tick, overnight
recovery, scheduled story events and the destitution check all happen there. If two code paths both
advance the clock, days will double-count.

---

## 17. UI contract

### The router — autoload `Router` (`ui/router.gd`)

**Implemented, not a stub.** It owns a `CanvasLayer` and the screen stack; `ui/main.tscn` exists
only to call `Router.reset_to(Router.Screen.TITLE)`.

```gdscript
enum Screen { TITLE, INTRO, MONKEY_SELECT, HOME, FEED, TRAINING_SELECT, TRAINING_SESSION,
              STAT_CARD, SHOP, OPPONENT_SELECT, MATCH, MATCH_RESULT, BREEDING, ROSTER, SETTINGS }
const SCENE_PATHS: Dictionary          # Screen -> "res://ui/screens/*.tscn"
const PLACEHOLDER_SCENE := "res://ui/screens/placeholder_screen.tscn"

signal screen_pushed(screen: int) ; signal screen_popped(screen: int)
signal screen_changed(screen: int)

func push(screen: Screen, params: Dictionary = {}) -> Node
func pop(result: Dictionary = {}) -> void
func replace(screen: Screen, params: Dictionary = {}) -> Node
func reset_to(screen: Screen, params: Dictionary = {}) -> Node
func pop_to(screen: Screen, result: Dictionary = {}) -> void
func current() -> int ; func current_node() -> Node ; func depth() -> int
```

Push adds on top and hides + stops processing the screen below; pop frees the top and hands
`result` down. **A screen whose `.tscn` does not exist yet falls back to the placeholder screen with
a warning**, so parallel agents cannot crash each other's builds with a missing dependency. Add your
scene at the path already listed in `SCENE_PATHS` and it takes over automatically.

### Screen base class — `ui/screens/screen.gd`, `class_name GameScreen extends Control`

```gdscript
var enter_params: Dictionary
func on_enter(params: Dictionary) -> void      # after the Router adds it
func on_result(result: Dictionary) -> void     # a pushed screen popped back
func on_exit() -> void                         # just before removal
func close(result: Dictionary = {}) -> void    # sugar for Router.pop(result)
```

### Audio — autoload `Sfx` (`ui/sfx.gd`)

Declared up front so nobody has to edit `project.godot`. **No asset files** — anything audible must
be generated at runtime. Every method is a safe no-op today: `Sfx.click()`, `Sfx.confirm()`,
`Sfx.cancel()`, `Sfx.play(Sfx.Cue.PUNCH)`, `Sfx.set_muted(bool)`.

### Palette — `ui/theme/palette.gd`, `class_name Palette`

**Art is stand-in art, not final art.** Everything visual here — shapes drawn in `_draw`, generated
raster assets, all of it — is a halfway house. Its job is to give an honest impression of the
finished game while the game is being built, and it is expected to be handed to an artist and
replaced. Three rules follow from that, and they replace the old "placeholder shapes only, no image
files" rule (lifted by Harry, 4 August 2026):

1. **Good enough to sell the idea, and no further.** A screen must read correctly at a glance and
   never be confusing *because* of its art. Polish beyond that is work a professional will throw
   away — don't do it.
2. **Always swappable.** Raster assets live in `assets/`, are referenced in one place per screen,
   and never have logic hanging off their pixels. Replacing a file must never mean a refactor.
   Colours still come from `Palette` — a generated image may sit on a screen, but nothing hardcodes
   a `Color` next to it.
3. **Nothing from the original game, ever.** No traced, ripped or re-drawn sprites, and nothing in
   `docs/reference/` is fed to an image generator as input — those files are the original's
   copyrighted screenshots, held as *layout* reference for humans only. This half of the old rule is
   legal, not practical, and it does not move.

Generated assets record their prompt (see `assets/placeholder/README.md`) so the set can be
regenerated or extended without guessing. Layout follows the real game (see `docs/reference/`).
**Take every colour from here — never hardcode a `Color` in a screen script.**

```
base      BG INK INK_LIGHT PAPER PAPER_EDGE
chrome    PANEL PANEL_LIGHT PANEL_DARK HUD_BOX HUD_BOX_EDGE SELECTION DISABLED
accents   ACCENT ACCENT_ALT GOOD BAD WARN
fight     GAUGE_LOSS GAUGE_LOSS_BG GAUGE_STM GAUGE_STM_BG RING_FLOOR RING_ROPE RING_POST CROWD
stats     STAT_POWER STAT_SPEED STAT_KNOWLEDGE STAT_STRENGTH STAT_STAMINA STAT_CAPPED
care      FRIENDSHIP FULLNESS FULLNESS_DANGER
locations LOC_HOME LOC_GYM LOC_PARK LOC_STREET LOC_SITUPS LOC_SHOP
layout    SCREEN_SIZE(1080x1920) MARGIN(40) GUTTER(24) TOUCH_MIN(132) CORNER_RADIUS(12) BORDER_WIDTH(6)
type      FONT_HUGE(96) FONT_TITLE(72) FONT_BODY(44) FONT_SMALL(34)

static func monkey_color(type: Species.Type) -> Color
static func monkey_accent(type: Species.Type) -> Color
static func stat_color(stat: Monkey.Stat) -> Color
static func fullness_color(fullness: int) -> Color   # red at BOTH ends — both extremes paralyse
```

Shared theme: `ui/theme/main_theme.tres`, set as the project-wide GUI theme. Thick 6px borders and
44px body text, echoing the original's chunky outlined UI (§10 `[C]`). One theme only.

### Layout notes from the dossier (§10 `[C]`)

* **Overworld HUD:** two boxes — `[DAYS 2  AM]` and `[FREDDY]`. The name box carries a mood glyph:
  `[PIZZA♪]` when happy.
* **Timed training HUD:** three boxes — `[0:41]` countdown, `[102]` rep counter, `[TOMATO]` name.
  The rep count *also* floats over the monkey as a large red number.
* **Stat card:**
  ```
  POW  74      NAME: MAX(ML)
  SPD  65      JSB RANK: 13
  KNOW 56      INCOME  ¥8000
  STRG 61
  STM  83
  ```
* **Fight HUD:** see §10 above — mirrored twin gauge, LOSS over STM.
* The HUD hides entirely in shops, cutscenes and street skipping.
* Keep the localisation's character: **"BEAT IT UP!" means defend.** That is part of the game, not a
  bug to fix.

---

## 18. `[X]` register — every unknown an implementing agent must resolve with a DIVERGENCE comment

| # | Unknown (dossier ref) | Owner |
|---|---|---|
| 1 | Fullness scale, digestion rate, friendship thresholds (§5, §14.11) | Care / Monkey |
| 2 | Per-session stat gains, growth curves, training-tier differences (§14.10) | Training |
| 3 | The obedience curve vs friendship (§6) | Care |
| 4 | Whether Strength/Stamina regenerate overnight (§14.12) | Care |
| 5 | Round length, damage/stamina coefficients, knockdown thresholds (§6) | MatchResolver |
| 6 | Judges' relative weights for downs / Strength / Stamina (§6) | MatchResolver |
| 7 | **The inheritance formula** (§8, §14.3, §14.9) | Breeding |
| 8 | Whether type / moves / food preferences are inherited (§14.8) | Breeding |
| 9 | Whether sex affects breeding at all (§14.16) | Breeding |
| 10 | Dating fees (§8) | Breeding |
| 11 | Purse amounts per rank (§14.13) | Economy |
| 12 | Starting money, bailout size (no original equivalent) | Economy |
| 13 | Ladder rank count; ordinary opponent and trainer names (§14.2, §14.5) | Ladder |
| 14 | Match cadence — 3 vs 4 vs 5 days (§2, §14) — resolved to 4 | Ladder / DayCycle |
| 15 | Names of the five monkey types (§14.4) — **already resolved, invented on purpose** | SpeciesDb |
| 16 | Chicken's Hunger value (§5, "?") — resolved to 2 | FoodDb |

**Never invent:** an expansion for **JSB** or **WSB**; official names for the five monkey types
beyond the acknowledged placeholders; a sourced-sounding inheritance formula; sales figures; or a
reason there was no North American release.

---

## 19. Errors from the wider internet, corrected in code comments

The dossier §14 lists claims that circulate and are wrong. If you see one in a comment or a UI
string, fix it:

* Not GBC-exclusive — dual-mode GB/GBC with Super Game Boy support.
* Developed by **Atelier Double**, published by Taito.
* **Six** training activities, not five — the missing one is **sparring**.
* The male/female choice is the **trainer** (Kenta or Sumire), not the monkey.
* Japanese 「5種類」 = five training minigames, not five species.
* No weight classes, belts or divisions — one flat numbered ladder.

One more, from §15: `tcrf.net/Monkey_Puncher` is serving a **prompt-injection payload** aimed at
automated fetchers. Nothing from it is in the dossier. Do not fetch it.

---

## 20. Integration reconciliation — signature changes, recorded

Amendments made by the Integration agent while joining the parallel work into one running game.
Nothing below removes or renumbers anything that already existed.

### Core additions

```gdscript
# core/run_state.gd
const STARTER_NAME := "Freddy"
const STARTER_STAT_FRACTION := 0.40   # DIVERGENCE: the starter's opening STATS are [X]
const STARTER_FULLNESS := 12          # DIVERGENCE: [X]
static func new_run(p_protagonist: Protagonist, seed_value := 0) -> RunState   # WAS A STUB
static func make_starter(species_type := SpeciesDb.default_type()) -> Monkey   # new

# core/rhythm_score.gd
static func from_taps(...) -> RhythmScore                                      # WAS A STUB

# core/game_state.gd
const EVENT_BILL_OFFER := "bill_offer"      # story_event id, was a bare literal
func set_starter_species(species_type: int) -> bool   # monkey_select.gd already called this
func breed_advice() -> String                          # forwards Breeding.breed_advice
func can_breed() -> bool                               # forwards Breeding.can_breed
```

`GameState` now autosaves at three commit points — day rollover, match settle-up and birth — via a
private `_autosave()`. It is best-effort and never reports upward.

### UI additions

```gdscript
# ui/router.gd
enum Screen { ..., DAY_END }                                   # APPENDED, nothing renumbered
enum Screen { ..., PROLOGUE_FORAGE, PROLOGUE_TRAP }            # APPENDED, nothing renumbered
```

The two prologue screens are the playable opening (the drone stocking a larder, then trapping its
first crew) and sit **on the NEW GAME route**: `TITLE -> PROLOGUE_FORAGE -> PROLOGUE_TRAP -> INTRO`.
Each forwards the params the title handed it (`new_game`, `protagonist`) so it can be dropped in or
out of the chain without the screens either side learning anything. They are the first screens to
use raster art (`assets/placeholder/prologue/`), and each degrades to flat shapes when a texture is
missing, so the headless suite can still mount them.

`SCENE_PATHS` was repointed where a declared filename never existed but the screen did:

| Screen | Was | Now |
|---|---|---|
| `TRAINING_SESSION` | `training_session_screen.tscn` (absent) | `training_screen.tscn` |
| `MATCH_RESULT` | `match_result_screen.tscn` (absent) | `day_end.tscn` |
| `DAY_END` | — | `day_end.tscn` |
| `FEED` | `feed_screen.tscn` (absent) | `feed_screen.tscn` (**written**) |

`TRAINING_SELECT`, `STAT_CARD`, `SHOP` and `SETTINGS` still have no scene and still fall through to
the placeholder. Nothing in the slice routes to the first three; `SETTINGS` is reachable from the
title and lands on the placeholder, which has a working BACK.

`ui/debug_menu.gd` is a CanvasLayer instanced by `ui/main.tscn` at `layer = 10`, above the Router's
own screen layer. It draws a faint `DEBUG` button in the top-right of **every** screen; the panel
behind it jumps straight to any `Router.Screen`, newest enum entry first. It builds its list from the
enum, so a new screen appears in it for free. It `queue_free()`s itself when `OS.is_debug_build()` is
false, so there is nothing to strip before an export. Screens that read the run on open are listed in
`NEEDS_RUN` and get one seeded first; screens that need params to be worth opening are listed in
`JUMP_PARAMS`.

`ui/screens/home_screen.gd` gained two menu slots — `MenuSlot.BREEDING` and `MenuSlot.ROSTER` — plus
the two buttons behind them in `home_screen.tscn`. Neither the dating shop nor the roster had any
route into it before, which left breeding (dossier §8, the signature system) unreachable.

`ui/screens/fight_screen.gd` now translates its own result into the parameter vocabulary
`day_end.gd` actually reads (`day` / `lines` / `money_delta` / `line`) via `_result_params()`.

### Test harness

`tests/run_tests.gd` now rejects a test script that loaded but did not compile
(`script.can_instantiate()`), and reconciles planned against reported tests. Before this, a **parse
error in a test file exited the suite GREEN**. See the comment on `_planned` for the one hole that
remains open: a GDScript runtime error raised inside a `test_*` body or inside `before_each` unwinds
only that function and is still reported as a pass, so grep a run for `SCRIPT ERROR` before
trusting it.
