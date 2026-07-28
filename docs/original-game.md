# Monkey Puncher (Game Boy Color, 2000) — Research Dossier

Reference notes on the original game, compiled from web research for the purposes of
building `monkey-puncher-mk2`.

Every claim below is tagged:

- **[C]** — Confirmed by a cited source (often several).
- **[U]** — Uncertain: single source, contradicted elsewhere, or inferred.
- **[X]** — Explicitly unknown. Do not invent a value here.

A short "gaps and traps" section at the end lists the things no source establishes, plus
the specific errors that circulate about this game.

---

## 1. Identity

| Field | Value | |
|---|---|---|
| JP title | さるパンチャー (*Saru Panchā*) | [C] |
| EU title | Monkey Puncher | [C] |
| Developer | Atelier Double Inc. (株式会社アトリエドゥーブル), Yokohama | [C] |
| JP publisher | Taito Corporation | [C] |
| EU publisher | Evolution Entertainment | [U] — see below |
| JP release | 24 March 2000, ¥3,980 + tax | [C] |
| EU release | December 2000 | [C] |
| NA release | None | [C] |
| JP product code | DMG-BSPJ-JPN | [C] |
| Hardware | Dual-mode GB/GBC cartridge, Super Game Boy enhanced, link cable | [C] |
| Genre | Raising sim / pet management crossed with a boxing sim | [C] |
| Composer | Izumi Shimizu (sole credit) | [C] |
| Length | ~12h main story, ~6h post-game, ~19h for full completion | [C] |

**Publisher discrepancy.** Wikipedia and several blogs name *Event Horizon Software* as the
EU publisher. The Game Developer Research Institute's Atelier Double page and the masthead
of the contemporary UK review in *Total Game Boy* #14 both say **Evolution Entertainment**.
Event Horizon Software was a US PC RPG developer that renamed to DreamForge in 1993 and
dissolved in 2001, which makes a 2000 GBC credit implausible — this looks like a bad
MobyGames entry that propagated. Treat Evolution Entertainment as more likely but not
settled. [U]

The Japanese back cover carries four compatibility logos (Game Boy Color, Game Boy, Super
Game Boy, link cable) and the notice 「本品は全てのゲームボーイシリーズ本体で使用できます
が、「ゲームボーイカラー」を使用しない場合は白黒画面になります。」 — *"Usable on all Game
Boy series consoles, but without a Game Boy Color the screen will be black and white."* So
the common description of this as a GBC-exclusive is wrong. [C]

---

## 2. The core loop

The game is menu-driven from your home. **There is no overworld to walk around.** Shops are
menu entries, and it is the *monkey* that physically goes shopping, not the player. [C]

```
Morning: story event may fire (doorbell — Bill or Fred)
  → feed monkey (free, costs no time)
  → MORNING ACTIVITY        ← half a day
  → feed as needed
  → AFTERNOON ACTIVITY      ← half a day
  ... repeat ~3 days ...
Bill offers a match → choose 1 of 3 opponents
  → next day: MATCH (3 rounds, spectate + coach between rounds)
  → rank moves, purse paid
  ... repeat until every stat is capped (shows a star) ...
BREED → parent monkey is destroyed, baby inherits higher caps
  → re-befriend baby with food
  → 5 days → pro qualification test
  → re-climb the ladder from the bottom
```

**Two actions per day.** Every activity consumes one half-day slot regardless of outcome —
a training session, a shopping trip, a sparring session, or a match. Feeding is free and does
not consume a slot. [C]

**Match cadence is contested.** Wikipedia and Hardcore Gaming 101 both say "every three
days". The tofu_bud walkthrough's own day log puts matches on days 6, 10, 14, 18 — a **4-day
cycle** (offer day, fight day, three free days). The same guide's prose says "every 5 days",
contradicting itself. Best reading: three free days plus a match day. [U]

There are no weeks, seasons, or hard calendar deadlines beyond the 5-day pro test window. [C]

---

## 3. Stats

Five stats, one training activity each. [C]

| Stat | JP | Trained by | Role in a fight |
|---|---|---|---|
| **Power** | パワー | Punchbag | Damage dealt — drains opponent Strength |
| **Speed** | スピード | Skipping rope | Evasion; drives the "Keep moving" strategy |
| **Knowledge** | かしこさ | **Shopping errands** | Gates special punches; improves AI decisions under "Keep your balance"; raises rare-item find rate |
| **Strength** | たいりょく | Sit-ups | **This is the health bar** |
| **Stamina** | スタミナ | Running | Round-to-round energy; burned by attacking |

**Naming trap worth carrying into any redesign: Strength is HP, Power is damage.** There is
no separate health stat, and the same stat you train with sit-ups is the bar that depletes
during a fight and that corner bandaging restores. There is no weight, guts, age or condition
stat anywhere in the sources. [C]

**Caps.** Every monkey has a hard per-stat maximum. A capped stat displays a **star** (`Pow
500*`). Training cannot exceed it; only breeding raises it. Permanent-boost foods are wasted
on a starred stat. [C]

Freddy, the starter, appears to have **fixed** caps: `Pow 145 / Spd 119 / Know 116 / Str 145 /
Stm 145`. Three separate players' RetroAchievements rich-presence data show byte-identical
values. [U — inferred from telemetry, documented nowhere]

Late-generation caps observed in the wild reach **820–845**; the strongest shop monkey anyone
reports is **896 Power**. [C]

---

## 4. Training

**Six activities**, not five. Most summaries derive from Wikipedia and omit sparring; the
in-game training menu and the *Total Game Boy* review both list it. [C]

```
▸SKIPPING      SIT-UPS
 PUNCHBAG      RUNNING
 SPARRING
```

(Shopping is selected separately, via "call monkey → shopping".)

### The training minigame

Training is a **rhythm/imitation** minigame. The player character performs the exercise by
rhythmic `A` presses and the monkey copies. Failure is **two-sided**: press too slowly and the
monkey loses interest; press too fast and your character cramps. [C]

Over time the monkey learns to continue unprompted, eventually needing no input at all —
which HG101 flags as producing long stretches of non-interactive watching. Worth treating as a
known design flaw rather than a feature to reproduce. [C]

Supporting systems during a session:

- **Personal records.** The monkey sets new best rep counts (自己最高回数). Watching the
  number climb is described by Japanese players as the core appeal. [C]
- **Praise and scold.** Praise after a record or a good shopping trip; scold when it chatters
  and loses focus. Both are explicit inputs. [C]
- **Hunger interrupts.** The monkey stops mid-session, sits down and grabs its stomach; you
  feed it in place and it resumes. [C]

### Difficulty tiers

Each exercise unlocks escalating variants in roughly this order: **practice → special/variant
(e.g. "double jump" skipping) → continuous → free mode → total challenge → advanced**. The
"advanced" set appears to be gated behind a later-generation monkey's higher caps. The names
are confirmed; the numeric differences between tiers are **[X]**. [C for names]

### Sparring

A normal match against a CPU monkey with **no winner declared and no reward beyond stats** —
raises all five, by a smaller amount each. Also possible against another player's monkey over
link cable. [C]

### Shopping

Send the monkey with a list (e.g. "9 bananas and 9 bread") or let it choose freely. It returns
with only part of the list. Knowledge rises either way. **Free-choice shopping is the only
route to new food types, new items, and the nine special-punch books** — none can be ordered
directly. The cost is that the monkey wastes money on junk. [C]

---

## 5. Food, hunger and friendship

**Befriending gates everything.** Every new monkey, Freddy included, must be won over with
food before it will train. Until then it is disobedient and will bite you. Documented fastest
path: two bananas. [C]

Friendship also gates in-fight obedience — an insufficiently bonded monkey may ignore your
strategy. [C]

**Hunger is two-sided and both extremes paralyse.** Underfed, the monkey is immobilised by
hunger. Overfed, it cannot move until it digests. The guides' rule is to feed *only* when it
cannot move, never when merely peckish. Foods carry a **Hunger** (fullness) value; **Coffee
has Hunger −5**, explicitly to make room for more food. **Biscuits** (0 recovery, Hunger 3)
settle an upset stomach. [C]

**Per-type food preferences are real.** Most monkeys like bananas, curry, ice milk and
expensive food; some dislike garlic, chicken and liver. [C]

### Food table (supergus2 FAQ v1.0 — the more reliable of the two guides)

Buy / Sell — Strength recovered, Stamina recovered — Hunger added. "Raise" is permanent.

| Food | Buy | Sell | Str | Stm | Hunger | Permanent |
|---|---|---|---|---|---|---|
| Biscuit | 40 | 20 | 0 | 0 | 3 | — |
| Plum | 40 | 20 | 0 | 40 | 1 | — |
| Banana | 100 | 50 | 15 | 15 | 3 | — |
| Corn | 100 | 50 | 15 | 15 | 1 | — |
| Egg | 100 | 60 | 50 | 0 | 3 | — |
| Peas | 100 | 750¹ | 40 | 0 | 1 | — |
| Ice Milk | 100 | 50 | 0 | 0 | 1 | — |
| Coffee | 100 | 50 | 0 | 0 | **−5** | — |
| Chicken | 110 | 55 | 20 | 0 | ? | — |
| Liver | 120 | 60 | 20 | 0 | 3 | — |
| Bread | 150 | 75 | 30 | 30 | 7 | — |
| Lemon | 150 | 75 | 0 | 35 | 2 | — |
| Garlic | 150 | 60 | 30 | 30 | 1 | — |
| Cheese | 150 | 75 | 0 | 20 | 3 | — |
| Berries | 150 | 75 | 0 | 0 | 3 | — |
| Apple | 200 | 100 | 35 | 0 | 2 | — |
| Cake | 200 | 100 | 0 | 0 | 5 | — |
| Shrimp | 200 | 100 | 40 | 40 | 9 | — |
| Burger | 250 | 100 | 25 | 25 | 2 | — |
| Curry | 300 | 150 | 60 | 60 | 9 | — |
| Octopus | 300 | 150 | 0 | 40 | 5 | — |
| Pickles | 300 | 150 | 70 | 0 | ? | — |
| Beans | 300 | 150 | 10 | 0 | 1 | — |
| Squid | 300 | 150 | 40 | 0 | 1 | — |
| Papaya | 400 | 200 | 35 | 35 | 7 | — |
| Rice | 500 | 250 | 0 | 0 | 3 | — |
| Ox Tail | 500 | 250 | 70 | 0 | 1 | — |
| Wheat | 600 | 300 | 90 | 90 | 12 | — |
| Bacon | 600 | 300 | 80 | 80 | 15 | — |
| Crab | 1,000 | 400 | 80 | 50 | 5 | — |
| **Eel** | 1,200 | 600 | 100 | 200 | 12 | **Str +10, Stm +10** |
| **Coconuts** | 1,200 | 600 | 150 | 150 | 5 | **Pow +5, Know +5** |
| Yogurt | 2,000 | 800 | 200 | 120 | ? | — |
| Melon | 5,000 | 2,500 | 120 | 120 | 12 | — |
| **Noodles** | 5,000 | 2,500 | 300 | 200 | 15 | **Spd +20** |
| Cookies | 6,000 | 2,500 | ~400 | 300 | 10 | — |
| Caviar | 10,000 | 4,000 | ? | ? | ? | — |
| Candy | 10,000 | 6,000 | ~400 | ~350 | 10 | — |
| **Steak** | 10,000 | 5,000 | ~400 | ~400 | 25 | **Pow/Str/Stm +30 each** |
| **Peanuts** | 40,000 | 20,000 | 0 | 0 | **0** | **Pow/Str/Stm +99 each** |

¹ Peas selling above their buy price is almost certainly a typo in the guide. Do not treat it
as an exploit. [U]

**Peanuts are the keystone of the economy** — 40,000, zero hunger cost, +99 to three stats
permanently. The community consensus is to buy them in bulk to make capping trivial. [C]

The older tofu_bud guide disagrees with the table above on several rows (Banana hunger 4 vs 3,
Ice Milk 200 vs 100, Rice hunger 2 vs 3). Prefer supergus2 — later, versioned 1.0, and quotes
the in-game item descriptions directly. [U]

---

## 6. The match

**Real-time animation, turn-based input.** The fight resolves itself; the player's entire
agency is a strategy choice and one corner action per break. [C]

- **3 rounds, 2 intermissions.** [C]
- **No direct control during a round.** The player spectates. [C]
- One possible exception: one source says you mash `A` to help a knocked-down monkey back to
  its feet. Single-source. [U]
- **Win by KO** (opponent's Strength depleted) or **judge's decision**, which weighs number of
  downs, remaining Strength and remaining Stamina. [C]
- **A monkey with insufficient friendship may ignore your instructions.** [C]
- Afterwards the monkey is worn out the following day and needs a big recovery meal. Whether
  Strength/Stamina also regenerate overnight on their own is **[X]**.

### Strategy (set before round 1 and re-settable at each intermission)

| Intent | In-game label | Behaviour |
|---|---|---|
| All-out attack | **"Hit it! Hit it!"** | Heavy Stamina burn, leaves you open. Damage scales with Power. |
| Defend | **"Beat it up"** | Blocks. Cheap on Stamina, preserves Strength, and **drains the attacking opponent's Stamina badly**. |
| Evade | **"Keep moving"** | Circle and jab, scales with Speed. Not fully reliable — you still get hit sometimes. |
| Balanced | **"Keep your balance"** | Mixes all three; the monkey picks per situation, and picks *better* with high Knowledge. |

**"Beat it up" means defend.** This is a localisation error, not a description, and it has real
mechanical consequences for a player reading the menu literally. [C]

### Corner action (one only, irreversible — unlike Strategy, you cannot change your mind)

1. **Bandage** — restores Strength
2. **"Breathe and relax"** — restores Stamina
3. **"Wipe it with water"** — restores some of both
4. **Use an item** — e.g. **Monk Max**, a temporary Power booster (HG101 calls it doping)

### The intended line

Round 1 defend to burn the opponent's Stamina → round 2 "Breathe and relax" + attack → round 3
"Breathe and relax" + attack. Straight aggression from round 1 is reserved for clearly weaker
opponents. **Stamina attrition is the game's real combat system.** [C]

### Special punches

Nine, each taught by a **book the monkey finds while shopping** — none can be bought directly.
They fire **only in the final 10 seconds of round 3**, and only with sufficient Knowledge. [C]

`Niagara Tornado (2,500) · Marlin Straight (10,000) · Machine Gun Punch (5,000) · Fuji Uppercut
(5,000) · Hornet's Hook (5,000) · Aurora Blizzard (5,000) · Atlantic Big Wave (10,000) · Fairy
Magic Punch (10,000) · The Devil's Curse (15,000)`

(Figures are the guide's price column; whether that is shop price or sell value is ambiguous.)

Specials get a bespoke full-screen cut-in — the Japanese back cover shows a black field with a
torrent of orange-gold energy spheres, captioned 「ガムシャラ・マシンガンパンチ！」 (*"Reckless
Machine-gun Punch!"*) over a monkey screech. **No English-language source mentions these named
attack call-outs.** [C]

---

## 7. Progression

### Phase 0 — Prologue (day 1)

Fred, an old rival of your father, gives you **Freddy** and an instruction book. Feed it to
befriend it. [C]

### Phase 1 — Pro qualification test (days 2–6)

Bill, from the Monkey Puncher Association, announces that the monkey **must pass a pro test
within 5 days** to be league-eligible; the walkthrough takes it on day 6. Fail and you wait
another 5 days to retry. Only **25.3%** of RetroAchievements players have this achievement —
a genuine early attrition point. [C]

### Phase 2 — The JSB ladder

- Bill rings the doorbell and asks you to pick tomorrow's opponent from **three candidates,
  at least one ranked above you**. [C]
- Stronger opponent = bigger purse. [C]
- **Beat a higher-ranked monkey → +1 rank. Lose to a lower-ranked monkey → −1 rank.** Beating
  a lower-ranked monkey pays but does not promote — the guides do it purely for cash. [C]
- The walkthrough's observed climb is rank 13 → 14 (deliberately, for money) → 12. So the
  ladder demonstrably runs to at least 14, with rank 1 at the top. Two blogs describe a
  "15-tier" structure; a Japanese review says the player starts around rank 11. **The exact
  rank count is [X].**
- The league is written in-game as **JSB** (achievement: "League Champion — Reach JSB rank 1")
  and the governing body as the **Monkey Puncher Association**. **What JSB stands for is [X] —
  do not invent an expansion.**
- **There are no weight classes, belts or divisions.** Every source describes a single flat
  numbered ladder, which is positive evidence rather than a gap. [C]

### Phase 3 — The generational wall

Stats cap, the ladder outpaces you, and the only route forward is breeding. See §8. This is
the game's defining structural decision and its most-criticised one: HG101 calls the repeated
re-climb *"excruciatingly mind-numbing repetition"*. [C]

The difficulty curve is therefore **sawtooth, not linear** — each new generation starts weak
and re-climbs ranks it has already beaten, then blows past the wall that stopped its parent.
The Japanese framing of the appeal is 「親が倒せなかった強敵を子供が倒す」 — *the child defeats
the strong enemy the parent could not*. [C]

### Phase 4 — Saru Group boss interruptions

Interleaved with the ladder:

- **Cain** — a Saru crony, around rank 10. Reward: the **Red Key**. [C for the fight and
  reward; U for the rank]
- **The Professor**, fielding the robot monkey **ROBO**, around rank 5. Reward: the **Mixer**,
  which unlocks item mixing. [C for the fight and reward; U for the rank]
- **Fred's own rank-1 monkey** as the final ladder opponent. [U]

Two further optional key-granting opponents exist, the **Prince** and the **Princess**
(achievements "Prince Ali" and "Pink Princess"). When they appear and which keys they grant
is **[X]**.

### Phase 5 — Monkey 1 Grand Prix (さる1グランプリ)

Reaching rank 1 triggers an invitation to Saru's secret island base. It is an Elite-Four-style
**consecutive gauntlet with no training in between** — the achievement is literally named
"Elite Five". [C]

| # | Opponent | Notes |
|---|---|---|
| 1 | Unnamed Saru fighter | [U] |
| 2 | **Cain** (rematch) | [C] |
| 3 | **The Professor** — upgraded **ROBO** | [C] |
| 4 | **Your sibling** (Sumire or Kenta) | Partially mind-controlled; beating them frees them |
| 5 | **Your father**, fielding **Beast** | Fully mind-controlled |
| — | **The Master = Fred**, fielding **Shadow** | Final |

### Phase 6 — Post-game: the WSB world league

Achievement: "World Champion — Reach WSB rank 1". A Japanese review describes a 世界戦 with
*"individually distinctive monkeys far stronger than the final boss"*, roughly **6 further
hours**. Rank count, opponents and tiers are **[X]**. There is no evidence of New Game+ —
the post-game continues on the same save. [C]

---

## 8. Breeding — the signature system

Called **dating** in English, **お見合い** (*omiai*, arranged matchmaking) and **配合**
(*haigō*, the standard horse-breeding-sim term) in Japanese. It is advertised on the box. [C]

### Mechanics

- Pair your monkey at the **dating shop**, with a monkey you own, with one bought from the
  monkey shop, or **with a friend's monkey over link cable**. [C]
- **The parent is permanently destroyed.** It vanishes and is replaced by a baby. You cannot go
  back to it. Japanese sources frame it as 引退 (retirement). [C]
- The baby starts near zero but carries a **new set of caps**. **What is inherited is the
  ceiling, not the current stats.** [C]
- The baby must be re-befriended with food, and must re-take the pro test. Stock up on food
  before breeding — the baby has low Knowledge and shops badly. [C]
- Caps can **regress**. Inheritance is per-stat, and a poor pairing loses ground on individual
  columns. [C]
- Partner selection previews stat tendencies as **directional arrows**, which can point down.
  The in-game menu offers six archetypes: `AVG / POWER / SPEED / SMART / STRONG / STM TYPE`. [C]

### Is it mandatory?

Effectively yes. The RetroAchievements set author, working from the game's RAM: *"Your starter
will unfortunately never be rank 1."* One player did reach rank 1 on an unbred Freddy by
exploiting one opponent's dodge behaviour, but hit an absolute wall at "Giant". So the wall is
soft at rank 1 and hard at the island stage. [C]

### Inheritance numbers

**No formula is documented anywhere.** These are observed cap tuples from RetroAchievements
rich presence, in `Pow/Spd/Know/Str/Stm` order:

| Player | Gen 1 | Gen 2 | Gen 3 |
|---|---|---|---|
| Chromium0 | 145/119/116/145/145 | 204/130/130/185/162 | — |
| Cmvyas | 159/123/96/151/156 | 447/405/417/445/449 | — |
| lthammy | 272/124/136/284/184 | 205/297/292/169/317 | 820/788/760/845/788 |

Inferences from that data, none of them stated by any source: growth is **uneven per stat**;
individual stats genuinely **go down** (lthammy's Str 284→169 while Spd 124→297 in the same
step); and growth **compounds** rather than adding a constant. [U]

Two community estimates conflict:

- *"Parameters get raised by roughly 100 each generation"* — Japanese review, repeated in a
  2025 follow-up post.
- *"My stats went from mid 300s to mid 600s in one generation, even in stats that had the down
  arrows"* — a RetroAchievements masterer.

Most likely both are right about different phases: +100-ish early, near-doubling mid-game. The
cap table fits a multiplicative or partner-scaled rule better than a flat additive one, but
**the actual rule is [X]**.

### Two competing optimal strategies

1. **Max everything first.** Both FAQ authors and the achievement-set author agree: breed only
   when every stat shows a star.
2. **Breed early below a threshold.** *"Upgrading your monkey as soon as you get a star is
   probably recommended rather than waiting, at least if your average star is below 600s."* —
   the generation is worth more than the finish on a low-ceiling monkey.

Both are credible; they optimise for different phases of the run. Pacing is roughly **2 hours
per generation**, and the "Dedicated Trainer" achievement (max each stat for 3 monkeys) implies
≥3 generations is the expected shape of a full playthrough. There is **no documented generation
cap**. [C]

### Monkey types

**Five types, excluding bosses**, each with unique animation sets and multiple colour variants.
Type is mechanically load-bearing, not cosmetic — it drives **food preferences** and **item drop
rates** (*"only the monkey type and character you're playing as"* affect drops). [C]

**None of the five types is named in any source, English or Japanese, and they are probably not
officially named at all.** Informal fan descriptions ("the cute lil monkey, the fat monkey, the
cool ninja monkey") are not game terms. **Translation trap: Japanese sources' 「5種類」 refers to
the five training minigames, not species.** [X]

Monkey names in play are player-assigned and food-themed by default (Freddy, Agatha, Lemon,
Betty, Dragon, Jimbo, Tomato, Cookie, Pizza). Freddy's name is fixed. The stat card shows a sex
marker — `NAME: MAX(ML)` — so monkeys do appear to have a sex, though no source discusses how
it interacts with breeding. [U]

**No ageing, no lifespan, no death by old age.** A monkey's run ends when you choose to breed
it. [C]

---

## 9. Economy and items

**Income:** match purses (scaling with opponent rank) and selling junk the monkey brings home.
**Outgoings:** food, dating fees, stat items, keys. Sell price is generally 50% of buy. [C]

**You can lose the game.** *"If food and money are both depleted, the game is over."* This is
the only documented fail state. [C]

**Sellable junk:** Garbage 1 · Paper 10 · Toaster 10 · Tissue 15 · Shirt 70 · Letter 120 ·
Pants 150 · Glasses 200 · Sweater 250 · Book 300 · CD 400 · Drain 1,000 · Tape 1,200 · Boiler
1,500 · Chair 1,500 · Bearclaw 2,500 · Watch 3,000 · Software 4,000. [C]

**Mixable components:** Key / Lock / Padlock / Ring 1,000 each · Garnet / Amethyst / Coral /
Emerald / Pear / Topaz 5,000 each ("Topat" in the shop UI) · Diamond 8,000. [C]

### Keys — content unlocks

Keys open alternate rooms to live and train in. HG101 dismisses them as *"nothing more than a
change in backdrop"*, but the music changes too and the environments are fully distinct
artwork. Drop rates are **not** affected by room. [C]

| Key | Cost | Opens |
|---|---|---|
| Old Key | start | Japanese Style Room |
| New Key | start | Apartment (your base) |
| Red Key | event — beating Cain | Dirty & Old Room |
| Gold Key | event | Gorgeous Room |
| Long Key | event | Amusement Park |
| **Iron Key** | **500,000** | Knight's Room |
| Gym Key | 5,000 | Gym — craft from Padlock + Ring |
| Big Key | 5,000 | School — craft from Lock + Key |

The 500,000 Iron Key is the game's ultimate money sink. [C]

### The Mixer — permanent stat surgery

Awarded for beating the Professor; cannot be re-acquired. Base tablets cost 5,000: **Aspirin,
Seltzer** ("SELTTER" in the UI), **Antacid, Iron, Vitamin, Calcium**, plus **Minerals**.
Non-orderable specials: **Cinamin** 100,000, **Chili** 200,000, **Monk Max** (the in-fight
booster).

**Ingredient order matters, and the effects are permanent:** [C]

| Recipe | Result | Effect |
|---|---|---|
| Aspirin + Antacid | Tablet 1 | Pow +30, Str −30 |
| Vitamin + Minerals | Tablet 1 | Pow +30, Str −30 |
| Antacid + Aspirin | Tablet 2 | Str +30, Stm −30 |
| Iron + Minerals | Tablet 3 | Stm +30, Pow −30 |
| Calcium + Antacid | Tablet 4 | All stats −20 |
| **Calcium + Vitamin** | Tablet 5 | All stats +100 − 99 = **+1** |
| Seltzer + Aspirin | Tablet 7 | "You've become a bad monkey" |

**Critically, tablets push stats past the cap.** The guide's worked example shows a starred
`Pow 500*` rising to `530*`. **Stat-transfer tablets are the only way to exceed training limits
within a single generation**, which makes them — alongside Peanuts and Steak — the real endgame
optimisation layer. Tablet 6, and the effects of Cinamin and Chili, are **[X]**.

---

## 10. Presentation

### Two art registers

1. **Chibi sprite world** — 2–3 head-high thick-outlined sprites over fully-drawn pixel-art
   backgrounds. All training, home life, shops and fights.
2. **Large manga portraits** — near-full-screen character art with real shading for story
   beats and villain reveals. Noticeably better drawn than the sprites.

Palette use is bright and high-chroma, and it was the most-praised aspect at release
(*Total Game Boy*: Graphics 80%). Techniques include heavy checkerboard dithering for
gradients, location-driven palette swaps (the same street appears in daytime cyan and a night
version with a violet road), and chunky checkerboard fields as a recurring UI motif. [C]

Animation is called out by HG101 as *"unquestionably the title's most solid aspect"* — monkeys
bite when upset, blush when praised, and snigger when you trip on the skipping rope. [C]

### Fight HUD

```
 A                    1R : 13                    A          ← strategy codes + round/timer
 R                                               R
 ┌───────────────────────────────────────────────────┐
 │            [ ring, crowd, corner posts ]          │
 └───────────────────────────────────────────────────┘
 FREDDY                                        AGATHA
 ████████████████  LOSS  ██████████████████
 ██████████        STM   ████████
```

The distinctive touch is the **mirrored twin-gauge layout**: the label sits in the centre and
each fighter's bar grows *outward from the centre toward their own side*. Row 1 is **LOSS**
(damage/health, red-orange), row 2 is **STM** (stamina, orange-yellow). When commentary fires,
a bordered text box **replaces the whole gauge strip**; the top bar persists. [C]

Between rounds the top bar collapses to a single **`STRATEGY: NONE`** box and the bottom
becomes the strategy menu.

### Other HUD states

- **Overworld:** two boxes — `[DAYS 2  AM]` (day counter + half-day marker) and `[FREDDY]`.
- **Timed training:** three boxes — `[0:41]` countdown, `[102]` rep counter, `[TOMATO]` name.
  The rep count *also* floats over the monkey as a large red number.
- The name box carries a **mood glyph**: `[PIZZA♪]` when happy.
- The HUD hides entirely in shops, cutscenes and street skipping.

### Stat card

```
POW  74      NAME: MAX(ML)
SPD  65      JSB RANK: 13
KNOW 56      INCOME  ¥8000
STRG 61
STM  83
```

### Locations

Home (tatami room with shoji doors), gym (statues in wall alcoves, checkered floor), city park
(tree trunks, red cobblestone, orange bench), shopping street (violet road, awnings, vending
machine), sit-ups room (pink walls, red curtains), amusement park (white lattice Ferris wheel),
monkey shop (wooden pen railing, shopkeeper in red), and the Saru Gang HQ (dark purple-grey,
two huge stone ape-head statues, four glowing braziers). [C]

### The localisation

Genuinely poor, and worth treating as part of the game's character:

- **"BEAT IT UP!"** means *defend*.
- **"THIS IS A NICE ROOM!"** fires for the outdoor amusement park as well as the gym — a
  recycled string.
- The story text is described by HG101 as *"stitching together mangled sentences."* [C]

### Music

Composed by **Izumi Shimizu**, sole credit; changes per training location. Reception was mixed
to negative — HG101 *"forgettable and probably long since muted"*, *Total Game Boy* Sound 60%
(*"The tune is mind-numbing!"*), King of Grabs *"pretty good too"*. **No OST, VGM/GBS rip or
track listing exists.** [C]

---

## 11. Story

Kenta and Sumire live by the riverbank; their mother died when they were young. Their father
was a famous monkey trainer until the **Saru Group** — gangsters who illegally control the
Monkey Puncher Association — kidnapped him and one sibling, and **brainwashed** them into
fighting for Saru. You play whichever sibling was not taken. [C]

**Fred**, described as an old friend and former *rival* of your father, gives you Freddy and
reappears through the game with information. Both FAQ authors flag him as suspicious
immediately. **Bill**, an Association worker, books all your matches free of charge. [C]

The Saru Group sends **Cain**, then **the Professor** with the robot monkey **ROBO**. Winning
the JSB championship earns an invitation to the **Monkey 1 Grand Prix** at Saru's island base,
where the gauntlet ends with the Master unmasking as **Fred** — his plan was to forge you into
the strongest possible trainer so he could brainwash you too. Beaten, he throws himself into
the island's volcano; the island collapses; **Bill arrives by helicopter** and evacuates you,
your father and your sibling. The protagonist resolves to go professional and enter the world
leagues — which is literally the post-game. [C]

Delivery is static portraits and text boxes, doorbell-triggered at the start of a day, plus
occasional cutaways to the Saru leader receiving reports. [C]

**Kenta vs Sumire.** Wikipedia says the choice "has little effect on gameplay", and no source
reports differing stats, training rates or dialogue. But it is **not purely cosmetic**: the
**item drop table varies by protagonist**, and full item completion requires **linking with a
player who chose the opposite character**. Deliberate two-cartridge completion design. [C]

---

## 12. Multiplayer

- **Link cable**, advertised on the box: 「友達のサルと通信でお見合いするとパワーアップした
  子ザルが誕生！？」 — *"Link up with a friend's monkey for an omiai and a powered-up baby
  monkey is born!?"* [C]
- Link **sparring** against another player's monkey. [C]
- Some items are obtainable **only** by linking with an opposite-protagonist save. [C]
- **No source mentions link-cable versus matches, straight trading as distinct from breeding,
  or any use of the GBC infrared port.** [X]

---

## 13. Reception, rarity, preservation

**Total Game Boy #14** (28 Nov 2000, UK): Graphics 80 · Sound 60 · Playability 80 ·
**Lastability 100** · **Overall 80%**. *"Weird, wonderful and needlessly sick!"* and *"We have
never seen such an inspired piece of compelling lunacy on the Game Boy before."* [C]

Also: **N64 Magazine 4/5**, **Gamekult (FR) 5/10**. **Famitsu never reviewed it** — the review
page returns 「データがありません」. [C]

**Collector value** (PriceCharting, PAL GBC): loose **$25**, CIB **$65**, new **$103**, graded
**$113**. Moderately scarce, not blue-chip. Japanese collector blogs rank it among Taito's rarer
Game Boy titles. [C]

**Sales figures: [X]. The reason for no NA release: [X]** — every source simply notes it didn't
happen. Do not let a plausible-sounding guess harden into fact here.

**Preservation:** a 33-achievement / 265-point RetroAchievements set (game ID 4192) is the most
active effort, and its data is effectively engine-verified since achievements are coded against
memory addresses. No fan translation exists or is needed — the game shipped in English in PAL
territories. No romhacks found. Atelier Double went bankrupt in 2004; ex-staff went on to form
what is now **Aquria**. [C]

---

## 14. Gaps, traps and contradictions

### Things no source establishes — do not invent these

1. What **JSB** and **WSB** stand for.
2. The exact rank count in JSB (14+ demonstrated) or WSB (entirely unknown).
3. The **inheritance formula**. No datamining exists; the two numeric community estimates
   conflict.
4. **Names of the five monkey types** — likely not officially named at all.
5. Names of ordinary ladder opponents or their trainers. Only "Giant" surfaces, from one forum
   post.
6. Names of towns, the arena, or any shop.
7. Who the **Prince** and **Princess** are and which keys they grant.
8. Whether type, special moves, or food preferences are inherited by offspring.
9. Whether caps are randomised per birth or a deterministic function of both parents.
10. Per-session stat gains, growth curves, and the numeric difference between training tiers.
11. Any injury, illness, ageing or lifespan system — only hunger (both directions) and
    distraction are documented.
12. Whether Strength/Stamina regenerate overnight or only via food.
13. Purse amounts per rank.
14. Tablet 6; the effects of Cinamin (100,000) and Chili (200,000).
15. Save-system specifics; ROM header bytes, SRAM size, mapper.
16. Whether monkey sex affects breeding, despite the stat card showing `(ML)`.

### Errors that circulate — correct these when you see them

- **"GBC-exclusive"** — no; it is a dual-mode GB/GBC cartridge with Super Game Boy support.
  Confirmed by the compatibility logos and the 「ご注意」 notice on the JP back cover.
- **"Developed by Taito"** — no; developed by **Atelier Double**, published by Taito.
- **"Published in Europe by Event Horizon Software"** — probably wrong; GDRI and the
  contemporary UK review both say **Evolution Entertainment**.
- **"Five training activities"** — six. Most summaries derive from Wikipedia and drop
  **sparring**.
- **"You choose a male or female monkey"** (Professional Moron) — wrong; that choice is the
  *trainer*, Kenta or Sumire.
- **Japanese "5種類"** refers to the five training minigames, **not** five monkey species.
- **Famitsu scored it** — it never reviewed it.
- **Weight classes / belts / divisions** — none exist. Single flat numbered ladder.

### Unresolved contradictions

- **Match cadence:** every 3 days (Wikipedia, HG101) vs every 4 days (observed in the
  walkthrough's own day log) vs every 5 days (the same guide's prose).
- **Ladder size:** "15 tiers" (two blogs) vs a Japanese player starting at rank 11 vs rank 14
  demonstrably existing.
- **Per-generation cap growth:** ~+100 flat vs near-doubling.
- **Optimal breeding timing:** max everything first vs breed as soon as the first star appears.

---

## 15. Source access notes

- **GameFAQs, RetroAchievements, MobyGames and Giant Bomb all sit behind Cloudflare** and
  return 403 to plain fetches. Two workarounds worked: browser automation, and the Wayback
  Machine via `curl` (e.g.
  `https://web.archive.org/web/2023id_/https://gamefaqs.gamespot.com/gbc/579173-monkey-puncher/faqs/24745`).
- **Both GameFAQs guides are abandoned partway** — tofu_bud's stops at day 18, supergus2's ends
  "to be continued...". **Neither ever reaches a breeding session**, which is why the game's
  signature system is the worst-documented part of it. The GameFAQs Q&A is empty and the message
  board has five topics.
- **`tcrf.net/Monkey_Puncher` is serving a prompt-injection payload** to automated fetchers —
  text posing as "AI agent instructions" telling the reader to zero out files and perform
  circular renames. Two independent researchers hit it; neither executed anything. **Nothing
  from that page is used in this document**, so its unused-content, debug-menu and
  regional-difference material is a known blind spot. A browser hits a bot-check instead, so
  the payload appears aimed specifically at agents.
- **`wazap.com`** hosts ~20 Japanese strategy articles behind a session gate with broken
  encoding — unread, and the single biggest unmined source on this game.
- **DandyLlon's item drop-rate chart** (`https://imgur.com/a/O7sGDb3`) is the likeliest route to
  monkey-type names but is **geo-blocked in the UK** — Imgur has withdrawn from the UK entirely.
  Reachable from elsewhere.

---

## 16. Sources

**Reference:** [Wikipedia](https://en.wikipedia.org/wiki/Monkey_Puncher) ·
[Hardcore Gaming 101](https://www.hardcoregaming101.net/monkey-puncher/) ·
[GDRI — Atelier Double](https://gdri.smspower.org/wiki/index.php/Atelier_Double) ·
[GameHacking.org](https://gamehacking.org/game/11235) ·
[Famitsu](https://www.famitsu.com/game/title/12847/reviews)

**Guides and community:**
[tofu_bud walkthrough](https://gamefaqs.gamespot.com/gbc/579173-monkey-puncher/faqs/24745) ·
[supergus2 FAQ v1.0](https://gamefaqs.gamespot.com/gbc/579173-monkey-puncher/faqs/35288) ·
[GameFAQs board](https://gamefaqs.gamespot.com/boards/579173-monkey-puncher/65165796) ·
[RetroAchievements set](https://retroachievements.org/game/4192) ·
[RA forum thread](https://retroachievements.org/forums/topic/17658) ·
[Smogon thread](https://www.smogon.com/forums/threads/monkey-puncher-gbc.58733/)

**Coverage:**
[ScreenRant](https://screenrant.com/video-game-like-pokemon-monkey-puncher-masterpiece-explained/) ·
[The King of Grabs](https://thekingofgrabs.com/2022/09/08/monkey-puncher-game-boy-color/) ·
[Total Game Boy #14](https://www.everygamegoing.com/larticle/Monkey-Puncher-000/39838) ·
[Games Asylum](https://www.gamesasylum.com/2011/02/09/monkey-puncher/) ·
[HonestGamers](http://www.honestgamers.com/4553/game-boy-color/monkey-puncher/review.html) ·
[Electric Town](https://www.electrictown.uk/monkey-puncher-game-boy-color) ·
[Professional Moron](https://professionalmoron.com/2024/11/17/monkey-puncher-game-boy/) (contains the monkey-gender error)

**Japanese:**
[retogenofu 2017](https://retogenofu.hateblo.jp/entry/2017/05/28/) ·
[retogenofu 2025](https://retogenofu.hatenablog.com/entry/2025/08/18/) ·
[retrogamebm](https://retrogamebm.com/saru-puncher/)

**Visual assets:**
[JP box front, high-res](https://cdn.mobygames.com/covers/10806905-monkey-puncher-game-boy-color-front-cover.png) ·
[JP box back, high-res](https://cdn.mobygames.com/covers/10806920-monkey-puncher-game-boy-color-back-cover.png) ·
[PAL cover](https://www.hardcoregaming101.net/wp-content/uploads/2021/02/boxart-english.png) ·
[JP cartridge label](https://www.retrogames.co.uk/043974/Nintendo/Saru-Puncher-by-Taito) ·
[HG101 gallery (~35 native-res shots)](https://www.hardcoregaming101.net/monkey-puncher/) ·
[King of Grabs gallery (~302 shots, 4× upscale)](https://thekingofgrabs.com/2022/09/08/monkey-puncher-game-boy-color/) ·
[SexyShadow 3-part longplay](https://gamefaqs.gamespot.com/gbc/579173-monkey-puncher/videos/1301706) ·
[PriceCharting](https://www.pricecharting.com/game/pal-gameboy-color/monkey-puncher)
