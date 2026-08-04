class_name Palette
extends RefCounted

## The colour palette. ART IS STAND-IN ART — shapes drawn in code and generated
## raster assets both, good enough to give an impression of the finished game and
## built to be replaced by an artist later (docs/ARCHITECTURE.md §17). The one
## part of the old "placeholder shapes only" rule that still stands is the legal
## one: absolutely nothing traced, ripped or regenerated from the original.
##
## The hues follow the original's register as the dossier describes it (§10 [C]):
## "bright and high-chroma", with a chunky checkerboard field as a recurring UI
## motif and location-driven palette swaps. The fight gauges keep the original's
## two rows: LOSS in red-orange, STM in orange-yellow.
##
## Every screen must take its colours from here. Do not hardcode a Color in a
## screen script.

# --- base ------------------------------------------------------------------
const BG := Color("1b1420")            ## letterbox / behind everything
const INK := Color("1a1a1a")           ## text and outlines (GBC-thick)
const INK_LIGHT := Color("fdf6e3")     ## text on dark
const PAPER := Color("f4e9cd")         ## message boxes, menu panels
const PAPER_EDGE := Color("c9b48b")

# --- title / wordmark ------------------------------------------------------
## The original's title screen (docs/reference/screens-kog/001.png, §10 [C]) is a
## near-white field, a chunky outlined wordmark sitting on a yellow blob, a red
## boxing glove with an orange starburst, and a checkerboard band across the
## footer. These five are the placeholder stand-ins for that register — they are
## shapes and flat fills, never a traced logo.
const PAPER_WHITE := Color("f7f7f2")
const LOGO_BLOB := Color("f5d020")
const LOGO_BLUE := Color("2f3fd0")
const LOGO_RED := Color("d2281e")
## The chunky checkerboard field the dossier calls a recurring UI motif (§10 [C]).
const CHECKER := Color("8fa8e8")

# --- panels and chrome -----------------------------------------------------
const PANEL := Color("2c4c6b")
const PANEL_LIGHT := Color("4a7ba7")
const PANEL_DARK := Color("16283a")
const HUD_BOX := Color("f4e9cd")
const HUD_BOX_EDGE := Color("1a1a1a")
const SELECTION := Color("ffd447")
const DISABLED := Color("7a7a7a")

# --- accents ---------------------------------------------------------------
const ACCENT := Color("ff8c1a")
const ACCENT_ALT := Color("29b6d8")
const GOOD := Color("46b356")
const BAD := Color("e0483c")
const WARN := Color("ffd447")

# --- fight HUD (dossier §10) ----------------------------------------------
## Row 1 of the mirrored twin gauge: damage / health. Labelled "LOSS".
const GAUGE_LOSS := Color("ff5a36")
const GAUGE_LOSS_BG := Color("5c1c11")
## Row 2: stamina. Labelled "STM".
const GAUGE_STM := Color("ffb02e")
const GAUGE_STM_BG := Color("5c3d0d")
const RING_FLOOR := Color("dbe6f0")
const RING_ROPE := Color("e0483c")
const RING_POST := Color("2c4c6b")
const CROWD := Color("6b5b8a")

# --- stat colours (stat card, training screens) ----------------------------
const STAT_POWER := Color("e0483c")
const STAT_SPEED := Color("29b6d8")
const STAT_KNOWLEDGE := Color("9b6bd8")
const STAT_STRENGTH := Color("46b356")
const STAT_STAMINA := Color("ffb02e")
## Marks a capped stat — the original prints a star (`POW 500*`), dossier §3.
const STAT_CAPPED := Color("ffd447")

# --- care meters -----------------------------------------------------------
const FRIENDSHIP := Color("ff8fb1")
const FULLNESS := Color("8bd44a")
const FULLNESS_DANGER := Color("e0483c")   ## starving OR stuffed: both paralyse

# --- locations (dossier §10 lists eight; the slice needs a few) ------------
const LOC_HOME := Color("d8c48f")          ## tatami room with shoji doors
const LOC_GYM := Color("9aa7b5")           ## statues in alcoves, checkered floor
const LOC_PARK := Color("7fb069")          ## tree trunks, red cobble, orange bench
const LOC_STREET := Color("6b4c9a")        ## violet road, awnings, vending machine
const LOC_SITUPS := Color("e8a0b8")        ## pink walls, red curtains
const LOC_SHOP := Color("b5763f")          ## wooden pen railing, shopkeeper in red

# --- layout constants (1920x880 logical, landscape) ------------------------
## Landscape, roughly 19.5:9 — a phone held sideways. Screens written before the
## flip still lay themselves out for portrait and have not been swept yet.
const SCREEN_SIZE := Vector2i(1920, 880)
const MARGIN := 40
const GUTTER := 24
## Minimum tap target. Everything interactive must be at least this tall.
const TOUCH_MIN := 132
const CORNER_RADIUS := 12
const BORDER_WIDTH := 6

# --- type scale ------------------------------------------------------------
const FONT_HUGE := 96
const FONT_TITLE := 72
const FONT_BODY := 44
const FONT_SMALL := 34


## The five monkey type colours. Reads core/data/species_db.gd — the dependency
## points ui -> core and never the other way.
static func monkey_color(type: Species.Type) -> Color:
	return SpeciesDb.get_species(type).body_color


static func monkey_accent(type: Species.Type) -> Color:
	return SpeciesDb.get_species(type).accent_color


static func stat_color(stat: Monkey.Stat) -> Color:
	match stat:
		Monkey.Stat.POWER:
			return STAT_POWER
		Monkey.Stat.SPEED:
			return STAT_SPEED
		Monkey.Stat.KNOWLEDGE:
			return STAT_KNOWLEDGE
		Monkey.Stat.STRENGTH:
			return STAT_STRENGTH
		_:
			return STAT_STAMINA


## Fullness bar colour: red at BOTH ends, because both extremes paralyse.
static func fullness_color(fullness: int) -> Color:
	if fullness <= Monkey.FULLNESS_STARVING or fullness >= Monkey.FULLNESS_STUFFED:
		return FULLNESS_DANGER
	return FULLNESS
