# Morning report — Monkey Mission phases 1–4

*Overnight session, 29–30 July 2026. Branch `monkey-mission-phase1-4`. Nothing pushed; no other
branch touched.*

**Read this first:** everything below is on a branch, the suite is green, and the existing boxing
game still boots and still works. Nothing is half-migrated. The one judgement call I want you to
review is in §3 (the mutation is *additive*, so `core/` currently contains two games).

---

## 1. Headline

| | |
|---|---|
| Phases completed | **1, 2, 3, and 4** — all four, plus the phase-4 stretch |
| Suite at start | 538 passed, 0 failed, 3,980 assertions, 0 `SCRIPT ERROR` |
| Suite at end | **see §7** |
| New core | 6 files, ~2,850 lines |
| New tests | 6 files |
| Bugs found and fixed | **13**, listed in §5 and §7 |
| Rules softened | **none.** `disobedience_enabled` and `overfeeding_paralyses` are both still on and still harsh |
| Cost of the art | a few pence (§8) |

---

## 2. What each phase actually delivered

### Phase 1 — reframe, zero behaviour change

`docs/MISSION-ARCHITECTURE.md`: the post-mutation contract, written the way `ARCHITECTURE.md` was —
**signatures frozen before implementation**, so the parallel work below had something fixed to aim
at. It contains the vocabulary, a KEEP/MUTATE/RETIRE fate for every existing module, the 1:1
station↔stat↔activity bridge, frozen signatures for all seven new systems, the test plan, and an
`[X]` register mirroring the design doc's.

No code changed. Suite stayed at 538.

Also added `tests/run.sh`, because "SUITE GREEN" alone is not evidence — `ARCHITECTURE.md` §20 says a
runtime error inside a test body still reports as a pass. The script prints the summary next to the
`SCRIPT ERROR` count and exits non-zero on either.

### Phase 2 — ship + crew

`core/ship.gd` (542 lines) — hull, reactor, five systems, power allocation, damage, fires, breaches,
fuel, missiles. **Hardware only:** it never imports `Crew` and takes no `MpRng` at all. Every
crew-dependent quantity is a method taking a performance `float`. That is what lets the two be
tested independently and what prevents a dependency cycle.

`core/crew.gd` (601 lines) — roster, assignment, availability, two-axis leveling, the food-themed
name pool. Capacity 6, voyage starts with 4.

The two decisions worth your eye:

* **In-run station XP lives on `Crew.Member`, never on `Monkey`.** So permadeath costs you the
  levels while the bloodline keeps its trained stats. That split is what makes both halves of the
  fusion matter, and it meant `Monkey` needed no new fields at all.
* **Availability delegates to `Care`.** `overfeeding_paralyses` therefore reaches the ship intact: an
  overfed monkey is immobilised *at its station*, and the console reads as unmanned while it digests.
  I did not reimplement a single availability rule.

### Phase 3 — the voyage loop

`core/sector_map.gd` (396) — a sector is a graph of beacons in columns. **Every link goes strictly
forward one column**, which is what makes the threat inescapable: no backtracking, so a sector cannot
be farmed while the menace closes. Generation is deterministic from (sector, seed) and all eight
contract invariants are pinned across a sweep of eight seeds.

`core/voyage.gd` (345) — jumps, fuel, the threat, five permadeath conditions. `check_end` is a **pure
report** and `settle` is the mutating version, so a screen can ask "am I about to die?" without
killing the run by asking.

`core/voyage_state.gd` (194) — the disposable half of the eventual `RunState` split.

`Economy` repointed additively: `scrap` is a property over the *same integer* as `money`.

### Phase 4 — ship-vs-ship combat

`core/ship_combat.gd` (764) — a deliberate **structural clone of `MatchResolver`**: same
`advance(delta)` clock accumulating into fixed ticks, same "return only the new events, duplicated"
contract, same `simulate_*` escape hatches. That architecture was already proven and already covered
by 46 tests, and the design doc calls it "a gift here — FTL combat is the same shape."

`MatchResolver` is **untouched, byte for byte**, so it can be re-homed as `BoardingCombat` in phase 6
with its tests intact.

Obedience is rolled **once per order, never per tick**. Rolling per tick would turn
`disobedience_enabled` into a slot machine and would make a replay depend on how long the player left
an order standing.

---

## 3. The one decision I want you to review

**The mutation is additive through phase 4.** `core/` currently contains two games.

A true split of `RunState` into `VoyageState` + `StableState` touches `save_game.gd`,
`game_state.gd`, every screen, and roughly 1,500 lines of green tests *simultaneously*. Your brief
said tests must never be left failing and coverage must never be deleted without replacement. Done
overnight and unattended, that surgery is how you wake up to a red suite with no way to tell which of
six changes broke it.

So the new model was built **beside** the old one. `Ladder`, `DayCycle` and `RunState` keep working
and keep their tests; the boxing screens keep working; nothing in a voyage calls them.

**The cost, stated plainly:** there are two games in `core/` until an attended phase retires the
boxing path. If you would rather I had done the surgery and accepted a period of red, say so and
I will do it next session — it is a few hours of mechanical work with you watching.

---

## 4. Every DIVERGENCE decision, and why

All are `[X]` in `docs/monkey-mission-design.md` §9 unless noted. Each is DIVERGENCE-commented at its
constant.

### The bridge (design §9 #1, #2, #3)

| Value | Choice | Reasoning |
|---|---|---|
| `Crew.REFERENCE_STAT` | `150.0` | Matches the existing `MatchResolver.KNOWLEDGE_REFERENCE`, which the boxing sim already treats as a competent stat. "100% manned" now means the same number in both halves of the game. |
| `Crew.STAT_PER_LEVEL` | `30` | **The one I am most confident about.** Freddy's attested POWER cap is 145 (dossier §3), so a perfectly trained *unbred* Freddy tops out at Weapons level 4 — 150 is the wall, and only breeding gets him through it. The meta-progression is visible on the first voyage rather than being an abstract promise. |
| `Crew.STATION_LEVEL_MAX` | `5` | Reads as a 0–5 pip row, matching the five-stat card the original already shows. FTL uses two steps; five gives a longer voyage something to climb. |
| `Crew.LEVEL_BONUS` | `0.12` | Five levels add 60% at most, keeping **trained stats the dominant term** and in-run XP the sweetener. The other way round would make breeding pointless. |
| Breeding → station ceilings (#3) | **no separate mechanism** | The ceiling reads the trained stat, which is bounded by the cap, which is raised only by breeding. The chain falls out of the existing model instead of inventing a second one. |
| Species → station affinity (#10) | **not added** | Species already biases starting caps via `RunState.starter_caps_for`. A second channel would double-count. |

### The ship (design §9 #5, #11)

| Value | Choice | Reasoning |
|---|---|---|
| **Five systems, not eight** | stations *are* systems, 1:1 | Design §3 lists oxygen/medbay/doors; §9 #5 then resolves the ship to "five fixed systems/stations". The later explicit resolution wins, and it is what keeps the stat map 1:1. Oxygen, medbay, doors and crew room movement are **not stubbed**. |
| Power model (#11) | free like FTL, bounded by the reactor | Constraining allocation by a crew stat as well would double-charge the player for a weak crew, who already pay through `station_performance`. |
| `REACTOR_START` = 8 vs 5 systems × 4 bars | deliberately insufficient | Allocation is a decision rather than a formality. `make_starter` spends the whole reactor, so the first real choice in a fight is what to rob. |
| **Damage model** | `min(power_in, max_bars - damage)` | Damage removes **capacity from the top**, so unpowered headroom is a damage buffer and repair restores output instantly. FTL's own rule. See §5 — the first draft of the contract was ambiguous here and it cost a test. |
| Fuel and missiles live on `Ship` | not in `Economy` | They are physical stores; `Economy`'s inventory is a food larder keyed by `FoodDb` ids. Keeps the repoint to the one thing it genuinely is. |

### The voyage (design §9 #4)

| Value | Choice | Reasoning |
|---|---|---|
| `Voyage.SECTORS` = 3 | the slice's depth | Long enough for two-axis leveling to visibly pay off, short enough to finish in a sitting. |
| `Ship.FUEL_START` = 16 vs 14–20 beacons | a real budget, not a leash | A direct line through a sector always makes it; a greedy detour through every beacon does not. That tension is the point of fuel. |
| Threat: +1 column per jump, 2 jumps of grace **per sector** | — | It moves exactly as fast as you do; the pressure comes from needing to *stop* and do things while it does not. See §5 for the bug here. |
| `SECTOR_CLEAR_FUEL` = 8 | half a tank per sector cleared | Without it, fuel spent deep in sector 1 makes sector 3 arithmetically unreachable however well you played — a pacing knob turning into a dead end. |
| Beacon mix | ~⅓ combat, with a floor under every weight | No sector can lose its SAFE beacons entirely, because SAFE is where training happens and a sector without one silently switches off the training loop. |

### Combat

Every coefficient in `ship_combat.gd` is `[X]` and commented. Shape chosen throughout:
`hardware_fraction × BASE × (1 + performance × CREW_GAIN)`, so **power alone gives a floor and crew
is a multiplier on top**. That is required, not stylistic: a voyage starts with 4 crew for 5
stations, so an unmanned station must *degrade* rather than fail. Design §2.5 says the fifth station
runs "unmanned or weak early" — weak, not dead.

### Two rulings not in either design doc

* **Zero Strength incapacitates; it does not kill.** Nothing in the dossier or the design doc makes
  damage lethal, and in boxing zero Strength is a KO the monkey gets up from. Death is an explicit
  `Crew.kill()` reserved for genuinely lethal events. Two things fall out, both wanted: the boxing
  sim can become boarding melee without quietly becoming fatal, and `Monkey` keeps dossier §14.11's
  promise that there is no injury or lifespan system.
* **Names are stored mixed-case.** `RunState.STARTER_NAME` is already `"Freddy"` and
  `Monkey.name_line()` is what shouts it. My first pass stored the pool pre-shouted, which would have
  made the starter the only monkey in the game cased differently from the rest. Caught by a test.

---

## 5. The seven bugs

Five were mine. Two were in tests. All are fixed and all have regression coverage.

1. **`VICTORY` fired on merely *arriving* at the final boss** (`voyage.gd`) — so the boss fight never
   happened. Now requires an explicit `clear_boss()`, and outranks `OVERTAKEN` because having beaten
   the flagship it no longer matters that the menace caught up. *Mine, found by re-reading my own
   code.*

2. **The threat's grace period was per-*voyage*, not per-*sector*** (`voyage.gd`) — gated on
   `jumps_taken`, which never resets, while `_enter_sector` resets `threat_column`. So the grace was
   spent once in sector 1 and every later sector opened with the threat already advancing, making the
   back half of a voyage harder for a bookkeeping reason rather than a design one. Split into
   `jumps_this_sector`. **Found by the agent writing `test_voyage.gd`**, which correctly wrote the
   test for the behaviour the contract described rather than the behaviour the code had.

3. **`boss_cleared` and `jumps_this_sector` were unserialised** (`voyage.gd`) — a save at a boss
   beacon lost the kill; a reload mid-sector handed out a fresh grace period. *Mine.*

4. **The name pool was stored uppercase** (`crew.gd`) — inconsistent with `RunState.STARTER_NAME`.
   *Found by a test.*

5. **The damage model was underspecified in the contract**, and a test was written against the wrong
   reading. The two readings agree at full bars and diverge only when a system runs *below* its
   ceiling — which no other test happened to probe. I ruled for FTL's capacity model, fixed the test,
   **and rewrote the contract to state the formula outright**, because the ambiguity was the actual
   defect. `test_ship.gd` now pins the distinguishing case explicitly.

6. **A duplicate constant in `voyage.gd`** briefly broke the parse, caught by an agent mid-run. Mine,
   transient, from a two-step edit.

7. **See §7** for anything the adversarial audit turned up.

### A process note worth having

Twice, I edited a test file while the agent that owned it was still writing, and my edits were partly
overwritten. Both times the agent's final version was *better* than mine — it absorbed my
single-seed round-trip test into its own eight-seed sweep — but that was luck. **File-mtime
stability is not a reliable completion signal for a background agent**; the completion notification
is. Recorded because the same trap is waiting for phase 5.

---

## 6. What needs your judgement

Nothing below is blocking; all of it is a design call that is yours, not mine.

1. **The additive-mutation decision in §3.** The most important one.
2. **The advancing threat has no identity** (design §9 #8 — "a Saru-style syndicate? a cosmic
   entity?"). I deliberately did not invent one: it is the fiction of the whole game and it needs
   your voice. In code it is a nameless column index. Nothing blocks on it until the UI.
3. **`Shields ← STRENGTH`** is the one debatable pairing (design §4 argues it and wins on the grounds
   that STRENGTH already reads as the defensive stat and is what bandaging restores). Everything is
   in one table, so the swap to STAMINA is a two-line change if it feels wrong in play.
4. **Does the spirit have its own progression** (design §9 #9)? I built no `spirit.gd`. Pure framing
   for now.
5. **Boarding frequency** (#7) — `BOARDING` beacons generate, but nothing resolves them until phase 6
   re-homes the boxing sim.
6. **Balance is untested by a human.** Every coefficient is a first guess with a stated rationale. I
   have proven the maths is *consistent and deterministic*, not that it is *fun*. Design §9 #4 and
   the whole of phase 9 are still open.

### 6a. The one real design hole: fuel is currently decorative

This is the most important thing in this document after §3, and it is worth reading in full because
I got it wrong and the tests caught me.

Every link in a `SectorMap` advances **exactly one column**, and there are 6 columns. Therefore
**every** route from entry to boss is exactly 5 jumps. Consequences:

* Route choice costs **no fuel at all**. You choose *which* beacon to visit, never *how many*.
* A voyage needs 3 × 5 = 15 fuel, against `FUEL_START` of 16 — before either 8-fuel sector-clear
  payout. So fuel never binds.
* `Voyage.EndReason.STRANDED` is **unreachable by play**. Its tests have to empty the tank by hand.
* Two of my own comments asserted the opposite ("a greedy detour through every beacon does not
  [make it]"). There is no such thing as a detour. Both comments are now corrected in place, because
  a confidently wrong rationale is worse than none.

**Lowering the fuel number does not fix this.** With consumption fixed at 5 per sector, fuel can only
ever be a pass/fail threshold, never a decision. I deliberately did not fiddle the constant to look
busy.

**The fix is route-length variation:** allow **lateral links within a column** — never backward, so
the threat still cannot be escaped by doubling back, and lower-row-to-higher-row only, so the graph
stays acyclic and the BFS still terminates. Then diverting sideways to reach a store or a safe beacon
costs a jump of fuel *and* lets the threat close a column. That is exactly FTL's central tension, and
it makes fuel, the threat and route choice into one decision instead of three unrelated numbers.

I did not do it unattended because it changes §7's invariant 5, which roughly 80 tests assert
directly. It is an hour's work with you awake, and it is the first item in §9.

### 6a-ii. The worst bug of the night: combat was completely inert

Worth its own heading because a compiling, fully unit-tested system was **totally non-functional**,
and no unit test would ever have caught it.

I wrote a throwaway probe that simulated 40 fights per sector rather than trusting that "the tests
pass". Result:

```
sector 1 over 40 fights: { "DRAW": 40 } | avg 180.0s | avg hull lost 0.0/30
sector 2 over 40 fights: { "DRAW": 40 } | avg 180.0s | avg hull lost 0.0/30
sector 3 over 40 fights: { "DRAW": 40 } | avg 180.0s | avg hull lost 0.0/30
```

Every fight in the game was a three-minute draw in which **not one point of hull damage was ever
dealt, by either side.**

The cause was a relationship between two constants I had chosen independently and never compared. A
starter ship fires roughly every 12 seconds. A single shield layer regenerates every ~7.5 seconds.
Each shot pops exactly one layer, so **every shot was absorbed by a layer that had always come back**
— in both directions. The ship was invulnerable and so was the enemy.

Fixed by making weapon charge several times faster than shield recharge (`WEAPON_CHARGE_BASE`
0.14 → 0.40, `SHIELD_RECHARGE_BASE` 0.22 → 0.11), which is FTL's actual relationship. Both constants
now carry a comment stating that the ordering between them is load-bearing and what happens if it
inverts, because the failure is silent and total.

**The resulting curve, and why I am pleased with it** — 40 simulated fights per cell:

| crew | Sector 1 | Sector 2 | Sector 3 |
|---|---|---|---|
| untrained (fresh starters) | 80% win | 25% win | **5% win** |
| fully trained to caps | 100% | 83% | 58% |
| trained **and** station-levelled | — | — | **90%** |

That is the fusion working, measured rather than asserted: **training is decisively load-bearing**,
and in-run station levels stack on top of it. An untrained crew is slaughtered in sector 3; a trained
one wins more than half the time; a trained *and* levelled one wins nine times in ten. Both axes of
§4's leveling model pay off, in the right proportion, with trained stats dominant.

**The lesson, which I would apply to the rest of this project:** the unit tests were thorough and
green while the game did not work at all. What found this was 30 lines of throwaway simulation asking
"what actually happens when you play it?" Every future balance-bearing system should get one of these
probes, and none of them belong in the suite — they are exploratory, not regression tests.

### 6b. Smaller things the audit pass turned up, fixed or logged

Fixed tonight: `MAX_LINKS` was not actually a cap (the reachability-repair pass could push a beacon
to four links); `generate()` did not reveal the entry beacon's forward links, so a fresh chart showed
no first choice unless `Voyage` happened to fix it a line later; `MAX_COLUMN_WIDTH` and `ROWS` were
equal only by coincidence; `MAX_BEACONS` claimed 20 when 18 is the true ceiling.

**Logged, not fixed** — your call:

* **Sector depth changes beacon *kinds* but never *topology*.** The same seed produces the same graph
  shape in sector 1 and sector 3; only the rolled contents differ. Deeper sectors are not larger or
  more maze-like. §7 #8 only promises weight drift, so this is not a contract violation — but if
  "increasing danger" was meant to include shape, it is not implemented.
* **`kind_of(bad_index)` returns `COMBAT`**, which is indistinguishable from a real combat beacon. The
  one live consumer is fail-safe, but a stale index silently becoming a fight is a bad default. Left
  as-is because a test now pins the behaviour, so it cannot drift silently.
* **`Voyage.apply_dict` clamps `at` to `>= 0` but not against the restored map's size**, so a corrupt
  save can leave `current_beacon()` null and `current_column()` reading 0 — the entry column — which
  makes the threat look further away than it is.
* **`Voyage.begin()` ignores its `ship` argument** and resets neither `ended` nor `jumps_taken`, so
  calling it on a finished voyage leaves it finished. Everything constructs a fresh `Voyage`, so
  nothing hits this today.
* **`ShipCombat` has no in-combat repair**, which is a genuine death spiral — see §9.

---

## 7. Test count, and what the adversarial audit found

### The numbers

| | Start of session | End |
|---|---|---|
| Tests passing | 538 | **799** |
| Tests failing | 0 | **0** |
| Assertions | 3,980 | **21,976** |
| `SCRIPT ERROR` lines | 0 | **0** |

New test files: `test_ship.gd`, `test_crew.gd`, `test_sector_map.gd`, `test_voyage.gd`,
`test_voyage_state.gd`, `test_ship_combat.gd`. Extended: `test_core_purity.gd` (every new
predicate), `test_economy.gd` (the `scrap` alias).

Every random outcome is swept over 7–8 pinned seeds. `MpRng.new(0)` — which seeds from the wall
clock — appears nowhere in any new test.

### The audit

I ran a dedicated agent whose only job was to try to break the new core, forbidden from writing any
code, and required to separate CONFIRMED (it ran something) from SUSPECTED. It was worth it. Verdict
by category:

* **Purity: clean.** No `Node`, no scene tree, no `get_tree()`, no `Input`, no global
  `randi()`/`randf()` anywhere in the new core.
* **Crashes: clean.** No null-dereference or index path it could reach; the guarded loops in
  `SectorMap.generate` do terminate.
* **Determinism: one real bug**, below.
* **Balance: two real degeneracies**, both below.

It independently confirmed the two bugs I had already found and fixed (combat being inert, and
shield layers not clamping when the shield system is destroyed), reproducing the first with its own
105-run simulation. It then found four more:

**Fixed tonight:**

1. **A redundant order leaked an RNG draw.** `set_power`, `set_target` and `begin_escape` each rolled
   `Care.obeys` *before* checking whether the order changed anything, so asking for the state a
   system was already in still consumed a draw — measured at exactly one per no-op, 45 draws with
   none versus 59 with seven. Because `VoyageState` shares one `MpRng` between combat, `Care` and
   `SectorMap.generate`, **the layout of the next sector depended on how many times the player
   re-clicked a power slider.** This is the same class of bug `test_core_purity.gd` was written for,
   arriving through a different door: there a read-only predicate rolled, here a write that changes
   nothing rolled. Fixed by checking for the no-op first, with a regression test that also pins the
   converse — a *real* order must still be refusable, so the fix cannot have made obedience free.

2. **Hazards were a one-way ratchet, and an engine kill was an unrecoverable death spiral.**
   `Ship.extinguish`, `seal`, `repair_system` and `repair_hull` had **zero callers anywhere**. So a
   fire burned for the rest of the voyage, chewing a bar every ~17s and injuring the monkey sitting
   in it until it was unconscious — carried on the persistent ship and crew into the next sector.
   And since `evasion` and `jump_charge_rate` both return 0.0 with engines offline, losing engines
   removed dodging *and* fleeing at once with no way back.

   Fixed by implementing damage control, which the design already had the mechanism for:
   `Crew.floaters()` — crew with no post — fight fires, seal breaches and patch systems, at a rate
   scaled by STRENGTH (faithfully: STRENGTH is the physical stat and the health bar). **It costs a
   manned station**, which is what makes it a decision rather than a freebie: a voyage starts with 4
   crew for 5 stations and no floaters, so you pull the pilot off the helm and lose your evasion
   while they work. Exactly FTL's trade. Measured: engines recovered in **0 of 20** fights with
   nobody spare, **13 of 20** with one spare hand. Both faithful care rules reach it too — an overfed
   floater cannot be press-ganged into firefighting.

**Confirmed, and logged for you rather than fixed** — see §6a, because they share one root cause:

3. **`STRANDED` is unreachable and fuel is net-positive.** Confirmed over 79 seeds of play: the
   player finishes a whole voyage with **more fuel than they started** (17 versus 16).

4. **`OVERTAKEN` is unreachable too — the threat has no teeth.** The player moves +1 column per jump
   and the threat moves +1 per jump, it starts a column behind, grace buys two more, and
   `_enter_sector` resets it every sector. Confirmed: the **minimum gap ever reached over a full
   voyage is 2**, and `OVERTAKEN` needs 0.

   The audit also caught the tests being complicit: `test_voyage.gd` reached `OVERTAKEN` only by
   calling `advance_threat()` in a bare loop, and `STRANDED` only by hand-assigning `ship.fuel = 0`.
   Both proved the *predicate* while the *reachability* was false — and one of them even said
   "or OVERTAKEN is unreachable" in its own failure message. A sharp catch, and a good reminder that
   a passing test can encode a broken game.

   **These two are the same bug as the fuel problem in §6a**: nothing costs the player anything except
   moving forward. I added `Voyage.spend_time()` — the threat gains a column, the ship does not — as
   the hook phase 5 will call when training, trading or resolving an event at a beacon. It is tested
   (including that loitering *does* get you overtaken), but deliberately **wired to nothing**, because
   there is no beacon content yet and inventing a time cost for actions that do not exist would be
   guessing. One test, `test_the_threat_never_closes_on_a_player_who_only_ever_jumps`, documents the
   gap and **is designed to go red the day it is fixed**.

---

## 8. The placeholder art

Four images in `assets/placeholder/`, generated at `quality: "low"` for a few pence: a title hero,
seven beacon icons in `SectorMap.NodeKind` order, the ship exterior, and a crew portrait.

**This amends a standing rule and I want that on the record.** `ARCHITECTURE.md` §17 forbids image
files outright. That rule had two jobs: a legal one — the original game's sprites are copyrighted and
must never enter this repo — and a practical one, that there was no way to make art. You lifted the
practical half. **The legal half I kept:** no prompt names or imitates Monkey Puncher, and nothing
from `docs/reference/` was fed to the model, because using those screenshots as image input would
launder copyrighted art into generated output — which is exactly what §17 exists to prevent.

`assets/placeholder/README.md` records the provenance, the prompts, and what is wrong with them:
1.3–2.4 MB each and far too heavy for a mobile build, the icon sheet still needs slicing into seven,
the style is not locked across two models, and none of them follow `ui/theme/palette.gd`.

**They are not wired to anything.** Phases 1–4 are core-only and there is no Monkey Mission UI yet.

---

## 9. The exact next step

**Phase 5 — events and beacon content**, which is the first thing that makes a voyage feel like a
game rather than a graph walk.

Concretely, in this order:

1. `core/event.gd` + `core/data/event_db.gd` to the contract already frozen in
   `MISSION-ARCHITECTURE.md` §8. Data-driven like `food_db.gd`, so content is additive. Tests first.
2. Wire beacon arrival to event resolution in `VoyageState`, so `DISTRESS` / `STORE` / `HAZARD`
   beacons do something. `SAFE` should open the existing rhythm-training minigame — that is the
   moment the Monkey Puncher half re-enters the game, and it is the single highest-value thing left.
3. `COMBAT` and `BOSS` beacons already have a resolver; connect them and have `Voyage.clear_boss()`
   be called by a won boss fight.

**Before any of that, the one thing I would do first** — and the only item I would call urgent:

**Give beacons a time cost and routes a length, in the same change.** This single fix repairs *three*
things that currently do nothing: fuel (§6a), the advancing threat (§7 finding 4), and route choice.
They are all one root cause — nothing costs the player anything except moving forward. Concretely:

1. Allow **lateral links within a column** in `SectorMap.generate` — never backward, and
   lower-row-to-higher-row only so the graph stays acyclic. Now routes differ in length, so fuel
   binds and diverting to a store is a real decision.
2. Have every beacon action call the `Voyage.spend_time()` hook that already exists and is tested.
   Now stopping to train costs you ground, which is the threat's entire job.

It changes §7's invariant 5, which roughly 80 tests assert, so it wants you awake — but it is the
difference between a graph walk and a game. `test_the_threat_never_closes_on_a_player_who_only_ever_jumps`
is written to go red the moment it is done.

**Do not** start phase 8 (UI) before phase 5. The screens want something to show.

---

## 10. Things I chose not to fix, and why

So you can overrule me rather than discover them later. All are logged at the code, not just here.

* **`CombatEvent.by_player` means different things for different event kinds** — cause for
  `SHOT_FIRED`, subject for `HULL_DAMAGED`. So damage *you* deal arrives flagged `false`. I documented
  it precisely rather than changing it, because a test pins the behaviour and the flag is genuinely
  wanted both ways. **A HUD must not colour uniformly by it.** If you would rather have two fields,
  say so — it is a small change and better done deliberately.
* **`advance()` never returns order events** (`POWER_REROUTED`, `TARGET_CHANGED`, `DISOBEYED`). I
  initially "fixed" this and then reverted: the agent that wrote the tests had reasoned it out better
  than I had. One source of truth per event, or a UI listening to both the signal and the return
  value double-prints every line. **Orders must be read from the `event_logged` signal.** Same
  contract `MatchResolver` already has.
* **A landed hit awards SENSORS xp, not WEAPONS.** It reads like a copy-paste but is defensible —
  firing already awards WEAPONS, so gunners level by shooting and sensor monkeys level by the shots
  connecting. Left as-is; retune in phase 9 if it feels wrong.
* **Sector depth changes beacon kinds but not topology** (§6b).
* **`kind_of(bad_index)` returns `COMBAT`** rather than a sentinel (§6b).
