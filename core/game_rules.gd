class_name GameRules
extends Resource

## The six tuning flags that define this build's stance on the original game.
##
## The user picked "faithful with softened edges", with two explicit exceptions
## (disobedience and overfeeding paralysis) which stay FAITHFUL. Do not change
## these defaults, and do not add softening behaviour behind them.
##
## The live instance lives at `res://game_rules.tres` and is reached through
## `GameRules.load_default()` (or `GameState.rules`).

const DEFAULT_PATH := "res://game_rules.tres"

## How much the player may do during a live round.
enum FightInteractivity {
	NONE,            ## Pure spectate, as the original. Dossier §6 [C].
	TAP_ENCOURAGE,   ## This build: tapping during a round gives a small effect.
	FULL,            ## Not used by the vertical slice.
}

## Original: the parent is permanently destroyed on breeding (dossier §8 [C]).
## This build: false — the parent RETIRES to a viewable roster instead.
@export var breeding_destroys_parent: bool = false

## Original: per-stat hard caps; training cannot exceed them, only breeding can
## raise them (dossier §3 [C]). This build keeps that: caps hard-block training.
@export var hard_stat_caps: bool = true

## Original: "if food and money are both depleted, the game is over" (dossier §9 [C]).
## This build: false — warn the player and grant a bailout instead.
@export var bankruptcy_game_over: bool = false

## See FightInteractivity. This build: TAP_ENCOURAGE.
@export var fight_interactivity: FightInteractivity = FightInteractivity.TAP_ENCOURAGE

## FAITHFUL TO THE ORIGINAL, REQUESTED EXPLICITLY BY THE USER.
## A monkey with low friendship ignores the strategy you set, at the original's
## full rate (dossier §5, §6 [C]). Do not soften.
@export var disobedience_enabled: bool = true

## FAITHFUL TO THE ORIGINAL, REQUESTED EXPLICITLY BY THE USER.
## Overfeeding immobilises the monkey until it digests (dossier §5 [C]).
## Do NOT reinterpret this as "wastes food".
@export var overfeeding_paralyses: bool = true


## Load the project's shared rules resource. Falls back to defaults if the
## .tres is missing so that headless tests never depend on file layout.
static func load_default() -> GameRules:
	if ResourceLoader.exists(DEFAULT_PATH):
		var res: Resource = load(DEFAULT_PATH)
		if res is GameRules:
			return res as GameRules
	return GameRules.new()


func to_dict() -> Dictionary:
	return {
		"breeding_destroys_parent": breeding_destroys_parent,
		"hard_stat_caps": hard_stat_caps,
		"bankruptcy_game_over": bankruptcy_game_over,
		"fight_interactivity": int(fight_interactivity),
		"disobedience_enabled": disobedience_enabled,
		"overfeeding_paralyses": overfeeding_paralyses,
	}


func apply_dict(d: Dictionary) -> void:
	breeding_destroys_parent = bool(d.get("breeding_destroys_parent", breeding_destroys_parent))
	hard_stat_caps = bool(d.get("hard_stat_caps", hard_stat_caps))
	bankruptcy_game_over = bool(d.get("bankruptcy_game_over", bankruptcy_game_over))
	fight_interactivity = int(d.get("fight_interactivity", int(fight_interactivity))) as FightInteractivity
	disobedience_enabled = bool(d.get("disobedience_enabled", disobedience_enabled))
	overfeeding_paralyses = bool(d.get("overfeeding_paralyses", overfeeding_paralyses))
