# Placeholder art

Generated key art for Monkey Mission. **Placeholder** — sized and composed to be replaced.

## This is an amendment to a standing rule

`docs/ARCHITECTURE.md` §17 says, in bold: *"Art is placeholder shapes only: ColorRect, Panel,
Label, Line2D, `draw_*`. **No image files**, no downloaded assets, no sprites ripped from the
original."*

That rule had two jobs. One was legal — the original game's sprites are copyrighted and must never
enter this repository. The other was practical: at the time there was no way to make art, so
shapes were the only honest option.

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

## Before any of this ships

1. **Not wired up.** Phases 1–4 are core-only; there is no Monkey Mission UI yet. These are ready
   for phase 8, not in use.
2. **Far too heavy.** 1.3–2.4 MB each. Downscale, crop to content, and pack the icons into a sheet
   before a mobile build.
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
