# Monkey Mission — Design & Build Overhead

*Version 0.1 — planning lock, 29 July 2026. This document is the overhead map for mutating `monkey-puncher-mk2` into Monkey Mission. It sits alongside `docs/original-game.md` (the MP research dossier) and `docs/ARCHITECTURE.md` (the current code contract).*

---

## 1. The one-sentence pitch

You are a **spirit** voyaging the universe aboard a spaceship crewed by **highly trained monkeys**. Monkey Puncher's training, care, and breeding systems produce and level your crew; *Faster Than Light*'s jump-to-jump roguelike journey and real-time-with-pause combat are the actual game. Only the experience and levels the monkeys gain depend on their training.

## 2. The fusion, decided

Four load-bearing decisions are now locked and everything below flows from them:

1. **Structure — roguelike voyages + a persistent home stable.** Each expedition is an FTL-style run with permadeath for the ship and its crew, but your bred monkey *bloodlines* survive in a home stable between voyages. Training and breeding are the meta-progression you carry forward.
2. **Crew — monkeys man ship stations, plus boarding melee.** Each monkey is a crew member assigned to a station (pilot, weapons, shields, engines, sensors). Their trained stats set that station's performance. Ship-vs-ship combat is real-time-with-pause; boarding fights reuse the existing boxing simulation as monkey melee.
3. **Training — at safe beacons.** The rhythm-training minigames move *into* the voyage, available only at safe stops. Deep breeding happens back at the home stable between runs.
4. **Deliverables — this design doc + a phased build roadmap, plus a visual system map.**
5. **Ship & crew — one ship, five manned stations.** A single ship (no ship-select for now) with five stations: **Pilot, Engines, Weapons, Shields, Sensors**. Crew capacity is **6**; a voyage **starts with 4**, so one station runs unmanned or weak early. The station↔stat mapping is 1:1 (§4).
6. **Monkey naming — player-named, with a "random name" button.** The player names every monkey; a *Random* button draws from the original's food-themed pool (Freddy, Tomato, Pizza, Lemon, Agatha, Betty, Dragon, Jimbo, Cookie…). The gift starter may arrive pre-named but stays renameable.

## 3. What we keep, mutate, and add

The existing project is unusually clean: strict `ui → GameState → core` layering, a purely functional `core/` that runs headless, an injected deterministic RNG, and a real test harness. That discipline is the most valuable thing we inherit, and every phase below preserves it. The table names the current module (see `docs/ARCHITECTURE.md`) and its fate.

### Keep — already built, barely touched

| Module | Why it survives intact |
|---|---|
| `core/monkey.gd` | The five-stat + caps model *is* the crew model. STRENGTH-is-health carries straight over. |
| `core/training.gd`, `core/rhythm_score.gd` | The rhythm minigame becomes beacon training. The sim/UI split (scene reports a `RhythmScore`, core computes the gain) is exactly what we want. |
| `core/care.gd` | Feed / friendship / paralysis / obedience all still apply to crew. Obedience gating a crew order in combat is *better* tension than it was in boxing. |
| `core/breeding.gd` | Generational cap inheritance is the meta-progression. Moves to the home stable. |
| `core/economy.gd` | Money → **scrap**; inventory → food + parts. Purse logic gets repointed to salvage/event rewards. |
| `core/rng.gd`, save system, test harness, palette/theme, router | Infrastructure. Reused as-is; extended, not rewritten. |

### Mutate — same bones, new game

| Module | Becomes |
|---|---|
| `core/match_resolver.gd` | **Two** resolvers. A new `ShipCombat` sim (real-time, stepped by `advance(delta)` exactly like the boxing sim already is) for ship-vs-ship; the *existing* boxing resolver survives as `BoardingCombat` for melee. The `advance(delta)` + `MatchEvent` playback architecture is a gift here — FTL combat is the same shape. |
| `core/ladder.gd` | The **sector / beacon map**: a graph of jump nodes, an advancing threat pushing you forward, a sector boss. Rank climbing → depth reached. |
| `core/day_cycle.gd` | The **voyage clock**: jumps instead of AM/PM slots, fuel instead of free time, scheduled events instead of doorbell story beats. |
| `core/run_state.gd` | Splits into **`VoyageState`** (one expedition, permadeath) and a new **`StableState`** (persistent bloodlines + unlocks). `RunState` becomes the wrapper that owns both. |
| `core/game_state.gd` | Stays the single UI funnel; grows ship/voyage/stable methods and signals. |

### Add — genuinely new core systems

- **`core/ship.gd`** — hull, reactor power, systems (shields, weapons, engines, oxygen, medbay, sensors, piloting, doors), power allocation, breaches, fire, oxygen.
- **`core/crew.gd`** — station assignment, per-station XP, the stat→station mapping, fatigue, morale (friendship in space).
- **`core/voyage.gd`** — the run loop: jump, fuel burn, event resolution, the advancing threat, permadeath conditions.
- **`core/sector_map.gd`** — procedural beacon graph per sector, node types, pathing.
- **`core/event.gd` + `core/data/event_db.gd`** — the text-event system (distress calls, hazards, stores, choices with stat checks).
- **`core/stable.gd`** — the home meta: roster of bloodlines, breeding between voyages, crew selection, ship unlocks.
- **`core/spirit.gd`** *(optional / thin)* — the player layer: what the spirit spends and carries across permadeath.

## 4. The bridge: monkey stats → ship stations

This is the single most important new contract, the equivalent of MP's "STRENGTH is the health bar." With **five stations** and **five stats**, we get a clean 1:1 mapping — each of Monkey Puncher's five training activities becomes the way you train a monkey for one ship station. That is the spine of the whole fusion.

| Station | Keyed stat | Trained by (MP activity) | Drives | In boarding melee |
|---|---|---|---|---|
| **Pilot** | SPEED | skipping | Evasion — the reflex to dodge a shot | Chance to strike first / dodge |
| **Engines** | STAMINA | running | FTL/jump charge + sustained evasion | Round-to-round energy |
| **Weapons** | POWER | punchbag | Weapon damage and charge speed | Melee damage |
| **Shields** | STRENGTH | sit-ups | Shield recharge / the defensive bulwark | The health bar |
| **Sensors** | KNOWLEDGE | shopping errands | Targeting, **special weapons**, event insight — the heir to KNOWLEDGE gating special punches | Reads the enemy; picks the better line |

Each stat has a **home station** but stays **cross-cutting**: STRENGTH is still every monkey's health when fighting fire, vacuum, or boarders (faithful — STRENGTH is HP); STAMINA is still general endurance. So a monkey bred and trained for Shields is your toughest boarder too, and a Weapons gunner hits hardest in melee. The boarding sim keeps boxing's whole stat model intact.

All coefficients are `[X]` to tune. The one debatable pairing is **Shields ↔ STRENGTH** (vs STAMINA): STRENGTH wins because it reads as the defensive/toughness stat and MP already restores STRENGTH by bandaging — a defensive act — which leaves STAMINA free for Engines. Swap it in playtest if Shields wants to feel like sustain rather than toughness.

**Leveling** works on two axes, which is what keeps both halves of the game alive:

- **Station XP** accrues from *doing* (FTL-style): a monkey manning Weapons through combats gets better at that station over a voyage. This is in-run, resets with the crew's fate.
- **Trained stats** set the **ceiling and rate** of that XP, and are raised by **beacon training** (in-run, rhythm minigame → stat gain) and, permanently, by **breeding** (between runs → higher caps). A bloodline bred for POWER produces gunners whose Weapons ceiling is high; a SPEED line produces natural pilots.

So training's role — "only the experience/levels depend on their training," as briefed — is precise: **trained stats gate how high and how fast a monkey levels its station**, while the moment-to-moment leveling comes from surviving the voyage.

## 5. The voyage loop (FTL, mutated)

A voyage is a sequence of **sectors**; each sector is a procedural graph of **beacons** connected by jumps.

```
VOYAGE
  ├─ Sector 1 … Sector N  (increasing danger)
  │    └─ beacon graph: jump node → node, each jump burns FUEL
  │         node types:
  │           COMBAT     ship-vs-ship (real-time-with-pause)
  │           STORE      buy/sell scrap, fuel, food, parts, repair
  │           SAFE       ← TRAIN a monkey (rhythm minigame), feed/heal crew
  │           DISTRESS   text event, choice, stat-checked outcomes
  │           HAZARD     nebula / asteroid / solar flare
  │           BOARDING   enemy boards you → boarding melee (boxing sim)
  │           BOSS       sector gate / flagship
  └─ THE THREAT advances behind you each jump — no infinite grinding
```

**Resources** (mostly a repoint of `Economy`): fuel (jump currency), scrap (money), missiles/parts, hull, and the crew themselves. **Permadeath** triggers when hull → 0 or the last crew monkey dies. On permadeath the voyage ends, but bred bloodlines persist in the stable.

The advancing threat is MP's structural pressure translated: MP used a 5-day pro-test window and a ladder that outpaced you; FTL used the rebel fleet. Ours is a single advancing menace (identity `[X]` — see §9) that makes you keep jumping.

## 6. The home stable (meta-progression)

Between voyages you return to the stable — the persistent layer, saved separately from any single voyage. Here you:

- **View the roster** of bloodlines (the `Breeding` system's retired-parent roster, already flagged `breeding_destroys_parent = false`, is exactly this).
- **Breed** for better caps — MP's generational system, unchanged in math, re-homed here. The sawtooth difficulty MP is known for becomes: each voyage you field a crew, and better bloodlines let you jump deeper before the threat or a boss ends you.
- **Assemble the next crew** and, later, **choose/upgrade the ship**.

This is where "roguelike + persistent stable" resolves the core clash between FTL (fresh every run) and MP (generational progress): the *voyage* is roguelike, the *bloodline* is generational.

## 7. The spirit (player framing)

Framing the player as a spirit is not just flavour — it pays for three mechanics diegetically:

- **Real-time-with-pause** is the spirit stopping time to issue orders.
- **You coach, you don't fight** — the spirit directs monkeys and allocates the ship's power rather than acting directly, which is exactly FTL's captain-god-hand and MP's trainer role fused.
- **Persistence across permadeath** — the spirit endures when a ship and crew are lost, carrying the bloodlines and whatever meta-currency forward. It explains why "you" survive to breed again.

Open question `[X]`: whether the spirit has its own progression (relics, blessings, a between-run currency) or is a pure framing device.

## 8. Build roadmap

Each phase follows the project's proven discipline: **core first, headless tests, then UI.** No phase breaks `tests/unit/test_project_compiles.gd`. Before writing any new system we amend the architecture contract the way §20 of `ARCHITECTURE.md` already models.

**Phase 0 — Design lock (this document).** Agree the fusion, the stat→station bridge, and the roadmap. Decide naming/vocabulary (voyage, beacon, crew, stable, scrap).

**Phase 1 — Reframe scaffold.** No behaviour change. Write `docs/MISSION-ARCHITECTURE.md` as the new contract mirroring the existing one. Mark `ladder.gd`, `day_cycle.gd`, boxing `match_resolver.gd` as *to be mutated*; decide precisely what retires vs. transforms. Introduce the new domain vocabulary. Keep every existing test green.

**Phase 2 — Ship + crew station model.** New core: `ship.gd`, `crew.gd`. Implement the §4 stat→station mapping and station XP. Tests first, headless, deterministic. This is the heart; get it tested before any combat depends on it.

**Phase 3 — The voyage loop.** Mutate `day_cycle.gd`/`ladder.gd`/`run_state.gd` into `voyage.gd` + `sector_map.gd` + `VoyageState`. Jumps, fuel, the beacon graph, the advancing threat, permadeath conditions. Tests pin the graph generation and the threat pacing under a fixed seed.

**Phase 4 — Ship-vs-ship combat.** Mutate the boxing resolver's `advance(delta)`/`MatchEvent` architecture into `ShipCombat`. Power allocation, weapon charge, shields, evasion, hull/breach/fire. `simulate_*` variants for tests and a fast-forward, mirroring what's already there.

**Phase 5 — Events + beacon content.** `event.gd` + `event_db.gd`. Distress calls, stores, hazards, choices with stat checks. Data-driven so content is additive, like `food_db.gd`/`species_db.gd`.

**Phase 6 — Boarding melee.** Re-home the *existing* boxing `MatchResolver` as `BoardingCombat`. Minimal changes — it already works and is tested. Wire obedience/friendship into whether a monkey follows the boarding order.

**Phase 7 — Home stable + breeding integration.** `stable.gd`, `StableState`, separate save. Between-run breeding, crew selection, roster. Connect the two save layers cleanly (voyage save is disposable, stable save persists).

**Phase 8 — UI.** Mutate router screens: title/stable/crew-select, the ship interior + combat HUD (the mirrored-gauge discipline transfers), the beacon map, beacon/event screens, the training minigame (reuse), boarding (reuse). Placeholder art only, all colours from `palette.gd`.

**Phase 9 — Balance + tuning.** Resolve every `[X]` in §9 with a `DIVERGENCE` comment, following the existing convention. Playtest the stat→station coefficients, the fuel/scrap/threat pacing, and the breeding-to-station-ceiling curve.

## 9. Open design slots — the `[X]` register

Following the dossier's own convention: these are the unknowns to resolve deliberately, each with a `DIVERGENCE` comment when coded. None should be guessed silently.

| # | Open slot | Owner |
|---|---|---|
| 1 | Exact stat→station coefficients (§4) | Crew / Ship |
| 2 | Station XP curve; how trained-stat ceiling and in-run XP combine | Crew |
| 3 | How breeding caps translate to station ceilings | Crew / Breeding |
| 4 | Fuel / scrap / threat pacing per sector | Voyage |
| 5 | ~~Ship roster — pick a ship like FTL?~~ **Resolved:** one ship, five fixed systems/stations (Pilot, Engines, Weapons, Shields, Sensors). Ship-select is a later addition. | Ship |
| 6 | ~~Crew count vs. station count~~ **Resolved:** 5 stations, crew cap 6, voyage starts with 4. | Crew / Ship |
| 7 | Boarding-melee frequency and how the boxing sim's 3-round shape maps to a quick fight | Boarding |
| 8 | The advancing threat's identity and fiction (a Saru-style syndicate? a cosmic entity?) | Voyage / story |
| 9 | Whether the spirit has its own progression, or is pure framing (§7) | Spirit |
| 10 | Does monkey *type/species* map to a station affinity or a ship bonus? | Crew / Species |
| 11 | Power-allocation model — free like FTL, or constrained by a crew stat? | Ship |
| 12 | Save split: what exactly is disposable (voyage) vs. persistent (stable) | Save |

## 10. Guardrails carried from the base

Two rules from the existing project that must survive the mutation:

- **Core stays pure.** No `Node`, no scene tree, no global `randi()` in `core/`. Ship combat and the voyage loop are simulations stepped by the UI, never the reverse. This is what keeps the whole thing testable, and FTL-style combat is *more* prone to becoming untestable spaghetti than boxing was — hold the line.
- **The two faithful rules the user asked for stay on.** `disobedience_enabled` and `overfeeding_paralyses` (see `game_rules.tres`). A low-friendship monkey ignoring your order *in a firefight*, and an overfed crew member immobilised at their station, are exactly the kind of MP texture that makes Monkey Mission more than a reskin. Do not soften them.
