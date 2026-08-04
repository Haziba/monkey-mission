# Stand-in art

Generated key art for Monkey Mission. **Stand-in** — sized and composed to be replaced.

## The rule this used to amend has now been replaced outright

The old §17 read: *"Art is placeholder shapes only: ColorRect, Panel, Label, Line2D, `draw_*`.
**No image files**, no downloaded assets, no sprites ripped from the original."*

That rule had two jobs. One was legal — the original game's sprites are copyrighted and must never
enter this repository. The other was practical: at the time there was no way to make art, so
shapes were the only honest option.

Harry retired the practical half on 4 August 2026. `docs/ARCHITECTURE.md` §17 now states the
**stand-in art policy**: art exists to give an honest impression of the finished game, must be
good enough to sell the idea and no better, and is expected to be handed to an artist and replaced.
Generated images are first-class under that policy, provided they stay swappable and record their
prompts. The legal half is unchanged and does not move.

Harry lifted the second half on 29 July 2026 ("put some placeholder images in where appropriate…
I am OK with a bit of money being spent in tactful places to make it pop"), and supplied an OpenAI
key for it. **The legal half stands and is not negotiable.**

## Provenance, precisely

* Generated with OpenAI `gpt-image-2` (`title_hero`, `beacon_icons`) and `gpt-image-1`
  (`ship_exterior`, `crew_portrait` — `gpt-image-2` rejects `background: transparent`).
* `quality: "low"` throughout, deliberately. The whole set cost a few pence.
* **Every prompt describes an original design.** No prompt names Monkey Puncher, references its
  style, or asks for anything "in the style of" it.
* **Nothing from `docs/reference/` was fed to the model.** Those 56 files are screenshots and
  packaging scans of the original game, held as *layout* reference for humans. Using them as image
  input would launder copyrighted art into generated output, which is exactly what §17 exists to
  prevent.
* The generating script is kept out of the repo (it reads a private API key path). It lived in the
  session scratchpad; regenerate from the prompts recorded below if needed.

## The files

| File | Size | Alpha | Intended use |
|---|---|---|---|
| `title_hero.png` | 1024×1536 | no | Title screen. Four crew on the bridge, one eating a banana. Portrait, matching the project's 1080×1920. |
| `beacon_icons.png` | 1024×1024 | no | Sector-map beacons. Seven icons in `SectorMap.NodeKind` order: COMBAT, STORE, SAFE, DISTRESS, HAZARD, BOARDING, BOSS. Needs slicing into a sheet. |
| `ship_exterior.png` | 1024×1024 | yes | The ship, for the map and the combat HUD. |
| `crew_portrait.png` | 1024×1024 | yes | A generic crew portrait for a station panel. |

## `prologue/` — components, not scenes

The playable prologue (`ui/screens/prologue_forage.gd`, `ui/screens/prologue_trap.gd`) needed art of
a different kind: **one isolated object per file**, so the screens can move, scale, mirror and stack
them independently. Nothing here is a composed picture — the composition is code.

| File | Size | Alpha | Used for |
|---|---|---|---|
| `banana_bunch.png` | 768×768 | yes | The collectible in the flight. Scaled by depth. |
| `tree_trunk.png` | 512×622 | yes | The corridor rails. Spawned alternately left and right. |
| `canopy_leaves.png` | 768×520 | yes | Overhead leaf band, drifting. |
| `fern_bush.png` | 768×595 | yes | Foreground undergrowth blurring past — a pure speed cue. |
| `forest_floor_bg.png` | 768×512 | no | The clearing. Shared by BOTH screens, so they read as one place. |
| `banana_pile.png` | 768×623 | yes | The bait. Drawn larger the more you collected. |
| `trap_dish.png` | 722×768 | yes | The salvaged antenna dish. Rolled from propped to landed. |
| `prop_stick.png` | 603×768 | yes | What holds it up, and what visibly goes when you tap. |
| `monkey_walk_a/b.png` | 768×768 | yes | The two-frame walk cycle. **Cropped to a shared box** — per-frame crops make the cycle jitter. |
| `monkey_caught.png` | 740×768 | yes | Generated for the catch beat; not yet used (they vanish under the dish instead). |
| `drone.png` | 672×768 | yes | The player character. Wanted across the whole game, not just here. |

Post-processed after generation, which is why these are ~50–190 KB rather than the 1.5 MB the model
returns: cropped to their alpha bounding box, capped at 768px on the long edge, and quantised to a
256-colour palette. Cropping is not only about size — a sprite with a fat transparent margin draws
smaller than the code asks for, so the crop is what makes `_blit`'s sizing mean anything.

Two component-specific rules learned the hard way, worth keeping if the set is extended:

* **The generator adds animals unless told not to.** `canopy_leaves` came back with a monkey sitting
  in it and had to be regenerated with "no animals, no monkeys, no creatures of any kind".
* **Ask for no ground shadow, then check.** `tree_trunk` came back with a dark mass under its root
  flare which read as a black block once the sprite was scaled up near the camera; the fix was to
  crop the flare off entirely.

### Prompts

Same shared suffix as the set above. Every component prompt also ends with: *"A single isolated
object, centred, entirely within frame, on a fully transparent background, no ground, no shadow, no
scenery."* — `forest_floor_bg` is the one exception, being a background.

* **banana_bunch** — "A fat bunch of six ripe yellow bananas with a brown stem, seen from the side."
* **tree_trunk** — "The trunk of a tall jungle tree, straight and full height, rough brown bark with
  a couple of green vines curling round it and one flat buttress root at the bottom. No leaves, no
  canopy."
* **canopy_leaves** — "A wide horizontal band of big green jungle leaves hanging downward, as if
  seen from directly beneath a canopy, filling the frame edge to edge along the top and leaving the
  lower half completely empty. Leaves and vines only — no animals, no monkeys, no creatures of any
  kind."
* **fern_bush** — "A low bushy green fern with broad fronds spreading left and right, the kind that
  grows on a forest floor."
* **banana_pile** — "A generous heap of loose yellow bananas piled up on the ground, roughly pyramid
  shaped, irresistible bait."
* **trap_dish** — "A large battered metal dish antenna reflector, shallow bowl shape, seen from the
  side and slightly above, scratched grey plating with a few rivets and a snapped mounting bracket.
  Salvaged industrial equipment."
* **prop_stick** — "A single crooked wooden stick, roughly a forearm long, bark still on it, propped
  diagonally."
* **monkey_walk_a** — "A cartoon monkey walking to the right, full body side-on view, mid-stride
  with the left leg forward and its long tail curled up behind. Cheerful, brown fur, pale muzzle,
  alert expression."
* **monkey_walk_b** — as above, "with the right leg forward and its long tail curled low. Same
  cheerful brown monkey with a pale muzzle, second frame of a two-frame walk cycle."
* **monkey_caught** — "A cartoon brown monkey sitting on the ground with its arms up and a delighted
  surprised expression, looking upward, full body."
* **drone** — "A small hovering survey drone robot, side view: a rounded metal body the size of a
  football with one big glass camera lens for a face, two folded manipulator arms, a stubby antenna
  and a soft blue glow underneath. Curious and likeable, not menacing."
* **forest_floor_bg** — "A jungle clearing background: dappled forest floor of earth and short grass
  across the bottom, a wall of dense green foliage and distant tree trunks behind, warm sunlight
  coming through from above. Empty clearing, no animals, no objects, flat plain background art for a
  game."

`prologue_forage.gd` measures one thing off this art: `BACKDROP_HORIZON` is where the
foliage-to-floor line sits in `forest_floor_bg.png` (0.72 of its height). Re-measure it if that file
is replaced, or the flight's vanishing point will stop lining up with the background's.

## Before any of this ships

1. **Mostly not wired up.** The four images above are ready for phase 8, not in use. Everything in
   `prologue/` IS in use, on the NEW GAME route.
2. **The top four are far too heavy.** 1.3–2.4 MB each. Downscale, crop to content, and pack the
   icons into a sheet before a mobile build — `prologue/` has already had this treatment and is the
   worked example.
3. **`beacon_icons.png` is one image, not seven.** Slice it, or regenerate the icons individually.
4. **Style is not locked.** Four images from two models is not a look. Whoever does phase 8 should
   pick one and regenerate the rest to match it.
5. **Palette is unenforced.** `ui/theme/palette.gd` is still the source of truth for every colour
   drawn in code; these images do not follow it.

## Prompts

Recorded so the set can be regenerated or extended consistently. Shared suffix on all four:

> Bold clean outlines, flat cel shading, bright saturated colours, chunky readable shapes, retro
> handheld video game key art. Original character design, comedic and friendly, not photorealistic,
> no text, no lettering, no watermark.

* **title_hero** — "Key art for a mobile game about monkeys crewing a spaceship. Four cartoon
  monkeys in mismatched astronaut jumpsuits stand together on a cluttered spaceship bridge, looking
  out of a big round window at a purple nebula and distant stars. One monkey grips a control stick,
  one points at a glowing screen, one eats a banana. Heroic group composition, warm interior light
  against cold space outside."
* **ship_exterior** — "A small battered cartoon spaceship seen from the side, three-quarter view,
  shaped like a chunky tugboat with mismatched welded plating, a big round cockpit window, two
  stubby engine pods glowing blue, and a bent antenna. Charming and lived-in rather than sleek.
  Centred, plain flat mid-grey background."
* **crew_portrait** — "A single cartoon monkey crew member portrait, head and shoulders, facing the
  viewer, wearing an orange astronaut jumpsuit with a chunky collar ring and a small round badge.
  Cheerful and alert expression. Centred bust composition, plain flat mid-grey background."
* **beacon_icons** — "A neat grid of seven simple flat icons on a plain dark background, evenly
  spaced, each in its own space: a crossed pair of laser cannons, a shopkeeper's coin purse, a green
  campfire shield, a distress radio wave, a swirling asteroid hazard, a boarding grapple hook, and a
  large menacing skull-marked battleship. Bold simple silhouettes, thick outlines, high contrast,
  icon design, no text."
