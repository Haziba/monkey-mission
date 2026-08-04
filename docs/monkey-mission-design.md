# Monkey Mission — Design & Build Overhead

*Version 0.1 — planning lock, 29 July 2026. This document is the overhead map for mutating `monkey-puncher-mk2` into Monkey Mission. It sits alongside `docs/original-game.md` (the MP research dossier) and `docs/ARCHITECTURE.md` (the current code contract).*

---

## 1. The one-sentence pitch

You are the **survey drone** whose environmental report got Earth cleared for demolition — the planet is scheduled to make way for a hyperspace highway, the file says *devoid of life*, and you know better, because you scanned every living thing on it. You cannot fly home to correct the record in a survey shell, and the hulls that can be flown that far need organic hands at five stations. So you raise, train and love a crew of **monkeys** to get you there before the destruction crew arrives. Monkey Puncher's training, care, and breeding systems produce and level that crew; *Faster Than Light*'s jump-to-jump roguelike journey and real-time-with-pause combat are the actual game. Only the experience and levels the monkeys gain depend on their training.

*Yes: this is standing openly in the shadow of the Vogons. The bypass is the setup, not the joke — the joke is that nobody out there is evil, they are just working through a schedule, and the ending is a filing correction won at enormous cost.*

### 1.1 Who you are `[C]`

A survey drone belonging to a construction concern. Not a castaway, not a fragment of anything — a working machine, sent out to run the environmental assessment on a small blue planet sitting in the path of a proposed hyperspace route. It did the job thoroughly and well: every river, every canopy, every troop.

Then head office read the file, declared the planet **devoid of life**, cleared the site, thanked the drone and retired it (§1.2).

The finding is not a lie anyone told. The assessment asks whether the site holds *registered sapient claimants*, and a monkey pulling a face at a camera lens does not tick that box. The paperwork is correct and the planet is full of life, and the drone is the only thing in the galaxy that is holding both of those facts at once.

You are the drone that did not comply. You cannot make the trip in the chassis you have — a survey shell crosses a system, not a galaxy — and the hulls that can were built around **five crew stations** that lock to a living operator. There are hands on this planet. They belong to monkeys.

So you built a stable, and you started training.

This premise is not flavour bolted on afterwards — it is chosen because it pays for the mechanics the game already needs:

| The premise says | Which pays for |
|---|---|
| Hulls require organic operators at five stations | Why you crew instead of piloting — and the 1:1 stat→station bridge (§4) |
| You are data; the crew is not | Permadeath for crew and ship, while "you" persist to try again (§6) |
| Home is a fixed distance across the galaxy | Sector depth as the run's spine, and an ending to aim at (§5) |
| They follow you, they do not obey you | Friendship / obedience gating orders under fire, inherited straight from MP's care system |
| You built the stable on Earth | The between-voyage meta layer has a place, and a reason you keep coming back to it |
| A demolition schedule is already running | The advancing threat behind you (§5) is a works programme, not a fleet — it does not chase you, it simply proceeds |
| The correction needs living witnesses | Crew survival carries narrative weight past the mechanics: who you arrive with changes the ending (§1.4) |

The tension the whole game runs on: **your only road home is the thing you have grown attached to, and every jump spends it.** The drone starts out treating monkeys as equipment and does not stay that way — care, naming and breeding are the systems that turn equipment into crew. The ending question is therefore already written: you can leave, and if you do, what happens to them.

### 1.2 The cold open `[C]`

**The tonal spine: grey → colour → grey.** The whole prologue is one colour argument. It opens
nearly monochrome and utterly still, floods with colour when the planet turns out to be alive, and
has that colour drained back out by a memo. The refusal at the end is the drone choosing colour. If
a shot does not serve that swing, cut it.

Day one, before any menu, before a single monkey. Five beats, played once:

0. **The transit.** Before anything happens, nothing happens — and it is allowed to go on slightly
   too long. Dead black space, three colours on screen at most, a distant sun too small to warm
   anything. The drone drifts across an empty frame. Readouts tick over with nothing to report:
   `SYSTEMS NOMINAL`, `SUBJECTS OF INTEREST 0`, a transit clock in years. This is a machine that has
   been bored for a very long time and does not have the word for it. Hold until the player is
   slightly restless. That restlessness is the point — it is what the planet pays off.
1. **Arrival.** The site resolves ahead: a small blue-green planet, still colourless at this
   distance. The task is procedural and stated flatly — *confirm site devoid of sentient life* — a
   box to tick on a form. The drone drops through cloud, competent and unbothered. HUD: `SURVEY 0%`.
2. **The survey — the bloom.** Below the cloud the frame detonates into colour. Green on green,
   turquoise river, a herd at a waterhole, birds crossing the lens, a troop of monkeys shouting at
   each other in a canopy. The scanning *is* the tutorial for looking: taxonomy boxes snap over each
   subject and the counter starts climbing, then climbing faster than the drone can keep up with,
   thousands of species a second, more life than the form has fields for. The pacing should read as
   **delight** — a machine built to count things finding more to count than it has ever seen. One
   monkey grabs the lens and pulls a face at it. The drone catalogues that too.
3. **The finding.** Transmission from head office, filling the screen. Cheerful corporate template, terrible content:

   > ASSESSMENT RECEIVED. SITE FINDING: **DEVOID OF LIFE**.
   > SITE CLEARED FOR ROUTE WORKS. DEMOLITION SCHEDULED.
   >
   > GREAT JOB, DRONEY. YOU HAVE SERVED YOUR PURPOSE.
   > PLEASE FLY YOURSELF INTO THE SUN AND CONSIDER YOUR MISSION A SUCCESS.

   One button: `ACKNOWLEDGE`. The player has to press it. There is no other option on screen. Behind the message the survey counter is still visible, still ticking: `SPECIES CATALOGUED 8,714,442`.
4. **The refusal.** The drone turns, lines itself up on the sun exactly as instructed — and holds there. Then it comes about, back down through the cloud, toward the troop. Title card.

The player's first act in the game is obeying, and the drone's first act is not. That is the whole character in one beat.

### 1.3 Why it wants to go home `[C]`

Not revenge — an angry drone is a worse companion for a game about raising animals, and "machine wants to kill its makers" is the version everyone has already seen. The motive is built from two halves that arrive at different times:

- **The turn (why it refuses).** It has spent the whole cold open watching things that are *trying* — a river cutting rock, a herd running, a monkey defending a scrap of fruit it does not need. None of them were told they were permitted to. When the order comes to fly into the sun, the drone has, for the first time, a comparison class: everything it has just catalogued would refuse. So it refuses. Wanting to live is the last thing it learns on Earth, and it learns it by observation, which is the only skill it was built with.
- **The reason (why it cannot just stay).** Staying means watching. The file is closed, the site is cleared, and a demolition crew is already routed this way — hiding in the canopy does not stop a schedule. The correction cannot be transmitted, either: a retired unit has no standing and no channel. Someone has to turn up in person, with the survey data and with something alive standing next to it.

So the drone raises monkeys to carry it across the galaxy to overturn the best work it ever did — and the crew it spends getting there are the children of the planet it is trying to save. That is the ache the run loop is built on, and it is why every jump costs something you love.

### 1.4 The escalation `[C]`

The threat is not a navy. It is a **works programme**, and that is what makes the ladder funny and then not funny.

The first sector boss should read, on approach, as the most frightening thing the player has ever seen: enormous, silent, unhurried, ignoring your hails. It is a **grader** — the space equivalent of a steamroller. It has no weapons. It does not fight back until you damage it, and then only with the tools it flattens rock with. Beating it is terrifying; realising afterwards what it was is the joke, and realising there is an entire industry behind it is the dread.

Sketch of the ladder — one boss per sector, each a rung further up the same org chart:

| Sector | Boss | What it actually is |
|---|---|---|
| 1 | **Grader** | Surface flattening unit. No guns, absurd hull, does not consider you a hazard. |
| 2 | **Clearance barge** | Cuts asteroids out of the right-of-way. Its cutting beams are tools, which is worse. |
| 3 | **Compliance cutter** | The first thing built to fight — but it fights the way an inspectorate fights: boarders, seizures, citations. Boarding melee (§3) peaks here. |
| 4 | **Project superintendent** | A genuine warship, escorting the schedule. The first opponent that has read your file and does not care. |
| 5 | **Head office** | Not a ship. A desk, a queue, and a broadcast array. Getting there is the fight; what you say when you arrive is the ending. |

Nobody on this ladder is evil. Every one of them is doing a job that was signed off upstream, and the drone's own report is what signed it. The horror is indifference and the comedy is scale — a game about a machine and six monkeys trying to get an amendment filed before the earth-movers arrive.

The win condition has two halves, and they are separable — which is what makes the ending worth playing for:

1. **Stop the works.** Reach head office, produce the survey and living witnesses, get the finding overturned before the crew reaches Earth.
2. **Spread the story.** Use the array. It is one thing to save the planet on a technicality; it is another for the galaxy to hear that the paperwork nearly ate a living world, and who stopped it.

Open `[X]`: whether surviving crew count changes the ending (arriving with witnesses vs. arriving alone with data), and whether the drone can broadcast without going home at all — a worse, faster, sadder ending.

### 1.5 The four load-bearing answers `[C]`

Everything below exists to stop the premise collapsing the first time a player asks an obvious question.

**Where does the ship come from? You steal it, and it was never a secret.**

The drone does not build a starship. The route works had already started staging when the assessment was commissioned: marker buoys, a fuel depot, and — parked in Earth orbit and written off the moment the site was cleared — a contractor's **crew tender**. Tenders do not get flown home; they get abandoned in place and billed to the project. It is ugly, cheap, slow, and built around five stations because that is how the concern's own labour crews work.

The drone spends the years after the cold open doing exactly what it was built to do — fine manipulation, sampling, patient cataloguing — turned to refitting a hull it was never issued. That also sets the upgrade economy: **scrap is the enemy's own parts**, stripped off the works you fight, because every ship in the game came out of the same catalogue.

**Why can the drone not fly it itself? Because of a policy, not a limitation.**

The tender's systems will not arm without a *licensed living operator* signed on at each station. It is an insurance interlock — the concern's hulls refuse to run unattended so that liability always lands on a warm body. The drone is disqualified by paperwork twice over: once as a retired unit, once as a machine. The same bureaucracy that condemned the planet is what forces it to raise a crew, which is the joke the whole game rests on.

**Is the stable on Earth? Yes — at the old survey camp.**

The base camp the drone worked out of becomes the habitat: pens, a feed store, training ground, and a breeding record it keeps with the same rigour it once kept the survey. That is where **breeding, deep training and crew selection** happen between voyages (§6), and it is the reason a total loss is survivable at all: the bloodlines never leave the planet.

It also has a clock on it. The stable is safe exactly until the works arrive, which is what makes the meta-layer tense rather than cosy. `[X]` Later beat worth considering: the works get close enough that the stable has to be evacuated to orbit for the final act.

**Do the monkeys get intelligence chips? No. They get a collar.**

Chips would eat the game. If hardware can make a monkey smart, training, feeding, friendship and breeding — every system inherited from Monkey Puncher, which is the entire meta-progression — stops mattering. So the hardware never touches cognition:

- **Interface collar** — two-way translation, so the drone can give an order and hear an answer. It grants *communication*, not intelligence. Obedience still depends on friendship and care.
- **Station harness** — remaps controls built for tall bipeds onto monkey ergonomics. Ergonomics, not aptitude.
- **The forged licence** — the collar also emits an operator signature, which is how six monkeys satisfy an interlock written for licensed crew. The drone is, quite literally, forging papers for monkeys. It is the most on-theme object in the game.

`[X]` If an implant mechanic is ever wanted, it should be rare, costly and *tragic* — trading one capped stat for another with an obedience or friendship penalty. Never a free brain.

**Do you fly home after every voyage? No. Only when you fail.**

The voyage is a one-way advance across the sectors, and a successful one ends the game — you reach head office, overturn the finding, use the array. There is no round trip to grind.

A **wipe** is what returns you to the stable, and the fiction of it is deliberately grim: the drone is small, hardened and survivable in a way its crew is not. It comes home the only way anything comes to Earth now — riding the works traffic already heading this way. It takes months. It arrives alone, and the schedule has advanced while it travelled.

That gives the roguelike loop a cost past "try again": every failed voyage burns calendar against the demolition date, while the bloodlines you bred get better. Meta-progress and meta-pressure pull in opposite directions, which is the shape a run-based game wants.

There is one voluntary exit: **abort at a safe beacon**. You lose the leg and most of the scrap, you keep the crew, and you go home to breed from monkeys that have actually flown. It costs less calendar than dying does — the game should reward knowing when to turn back, because that is a decision, and dying is not.

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
- **`core/drone.gd`** *(optional / thin)* — the player layer: what the drone spends and carries across permadeath. Specified as `spirit.gd` in earlier drafts; §7 renames it.

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

## 7. The drone (player framing)

The premise in §1.1 is load-bearing, not decorative. Three mechanics come out of it directly:

- **Real-time-with-pause** is the drone thinking faster than its crew — time dilates while it issues orders, because it is a machine and they are not.
- **You coach, you don't fight** — the drone directs monkeys and reroutes the ship's power rather than acting directly, which is exactly FTL's captain-god-hand and MP's trainer role fused. It is also the constraint: no hands.
- **Persistence across permadeath** — the drone is data and survives what the crew does not, carrying the bloodlines and whatever meta-currency forward. It explains why "you" get to breed again after a total loss.

Vocabulary: the player is the **drone** throughout code and UI. `core/spirit.gd` in §3 is the same layer under an earlier name; if it is ever written, it is `core/drone.gd`.

Open question `[X]`: whether the drone has its own progression (salvaged subroutines, a between-voyage currency) or is a pure framing device.

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
| 9 | Whether the drone has its own progression, or is pure framing (§7) | Drone |
| 10 | Does monkey *type/species* map to a station affinity or a ship bonus? | Crew / Species |
| 11 | Power-allocation model — free like FTL, or constrained by a crew stat? | Ship |
| 12 | Save split: what exactly is disposable (voyage) vs. persistent (stable) | Save |

## 10. Guardrails carried from the base

Two rules from the existing project that must survive the mutation:

- **Core stays pure.** No `Node`, no scene tree, no global `randi()` in `core/`. Ship combat and the voyage loop are simulations stepped by the UI, never the reverse. This is what keeps the whole thing testable, and FTL-style combat is *more* prone to becoming untestable spaghetti than boxing was — hold the line.
- **The two faithful rules the user asked for stay on.** `disobedience_enabled` and `overfeeding_paralyses` (see `game_rules.tres`). A low-friendship monkey ignoring your order *in a firefight*, and an overfed crew member immobilised at their station, are exactly the kind of MP texture that makes Monkey Mission more than a reskin. Do not soften them.
