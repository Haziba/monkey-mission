extends TestCase

## Breeding — dossier §8, the signature system and the worst-documented part of
## the game. These tests pin the three things the dossier is sure about (the
## ceiling is what is inherited, caps can regress, the preview arrows can point
## down), the rule change (breeding_destroys_parent = false, so the parent
## retires to a readable roster), and the determinism the invented inheritance
## formula needs to stay testable.

## Stands in for the Economy so these tests neither depend on that agent's
## implementation nor reach into it. It only has to be an Economy for the
## `breed()` signature; every behaviour under test here is breeding's.
class SpyEconomy extends Economy:
	var charges: Array[int] = []
	var allow := true

	func _init(p_rules: GameRules) -> void:
		super(p_rules)

	func spend(amount: int) -> bool:
		charges.append(amount)
		if not allow:
			return false
		money -= amount
		return true


const SEED := 20000324  # the original's JP release date, as a stable test seed

var rules: GameRules
var rng: MpRng
var breeding: Breeding
var parent: Monkey


func before_each() -> void:
	rules = GameRules.new()
	rules.breeding_destroys_parent = false
	rng = MpRng.new(SEED)
	breeding = Breeding.new(rules, rng)
	parent = make_parent()


# --- helpers -----------------------------------------------------------------

func make_parent(p_name := "Freddy") -> Monkey:
	var m := Monkey.create(p_name, Species.Type.SUNBURST, RunState.starter_caps())
	m.friendship = Monkey.FRIENDSHIP_MAX
	m.fullness = 12
	return m


## A fully-trained parent: every stat sitting on its star.
func make_capped_parent() -> Monkey:
	var m := make_parent()
	for stat in Monkey.STATS:
		m.add_stat(stat, 9999)
	return m


func caps_total(caps: Dictionary) -> int:
	var total := 0
	for stat in Monkey.STATS:
		total += int(caps.get(stat, 0))
	return total


func partner_of(monkey: Monkey, archetype: Breeding.Archetype, day := 1) -> Breeding.Partner:
	var offers := breeding.partners_for(monkey, day)
	for p in offers:
		if p.archetype == archetype:
			return p
	return null


# --- the dating shop menu ----------------------------------------------------

func test_the_shop_offers_exactly_the_six_archetypes() -> void:
	# Dossier §8 [C]: the in-game menu is AVG / POWER / SPEED / SMART / STRONG / STM.
	var offers := breeding.partners_for(parent, 1)
	assert_eq(offers.size(), 6)
	var seen: Array[int] = []
	for i in offers.size():
		assert_eq(offers[i].archetype, i, "archetypes must be offered in enum order")
		seen.append(offers[i].archetype)
		assert_true(offers[i].fee > 0, "a dating fee is charged")
		assert_eq(offers[i].caps.size(), Monkey.STATS.size())
		assert_false(offers[i].display_name.is_empty())
		assert_false(offers[i].id.is_empty())
	for archetype in [Breeding.Archetype.AVG, Breeding.Archetype.POWER, Breeding.Archetype.SPEED,
			Breeding.Archetype.SMART, Breeding.Archetype.STRONG, Breeding.Archetype.STAMINA]:
		assert_has(seen, archetype)


func test_partner_ids_are_unique_within_a_day() -> void:
	var ids: Array[String] = []
	for p in breeding.partners_for(parent, 3):
		assert_not_has(ids, p.id)
		ids.append(p.id)


func test_offers_are_stable_for_the_same_monkey_and_day() -> void:
	# Walking back into the shop on the same day must show the same six faces.
	var first := breeding.partners_for(parent, 4)
	var second := breeding.partners_for(parent, 4)
	for i in first.size():
		assert_eq(second[i].display_name, first[i].display_name)
		assert_eq(second[i].fee, first[i].fee)
		assert_eq(caps_total(second[i].caps), caps_total(first[i].caps))


func test_offers_change_from_day_to_day() -> void:
	var day_one := breeding.partners_for(parent, 1)
	var day_two := breeding.partners_for(parent, 2)
	var any_difference := false
	for i in day_one.size():
		if caps_total(day_two[i].caps) != caps_total(day_one[i].caps):
			any_difference = true
	assert_true(any_difference, "a fresh day should reroll the shop")


func test_offers_are_reproducible_across_two_seeded_runs() -> void:
	var other := Breeding.new(rules, MpRng.new(SEED))
	var mine := breeding.partners_for(parent, 7)
	var theirs := other.partners_for(make_parent(), 7)
	for i in mine.size():
		assert_eq(theirs[i].id, mine[i].id)
		assert_eq(theirs[i].fee, mine[i].fee)
		assert_eq(caps_total(theirs[i].caps), caps_total(mine[i].caps))


func test_a_different_run_seed_gives_a_different_shop() -> void:
	var other := Breeding.new(rules, MpRng.new(SEED + 1))
	var mine := breeding.partners_for(parent, 7)
	var theirs := other.partners_for(make_parent(), 7)
	var any_difference := false
	for i in mine.size():
		if caps_total(theirs[i].caps) != caps_total(mine[i].caps):
			any_difference = true
	assert_true(any_difference)


func test_partners_scale_with_the_parents_ceilings() -> void:
	# Growth compounds (§8 [U]) — the shop has to stay relevant to a gen-2
	# monkey, so partner ceilings are drawn relative to the parent's.
	var strong := Monkey.create("Dragon", Species.Type.CRIMSON, {
		Monkey.Stat.POWER: 600, Monkey.Stat.SPEED: 600, Monkey.Stat.KNOWLEDGE: 600,
		Monkey.Stat.STRENGTH: 600, Monkey.Stat.STAMINA: 600,
	}, 2)
	var weak_total := 0
	var strong_total := 0
	for p in breeding.partners_for(parent, 9):
		weak_total += caps_total(p.caps)
	for p in breeding.partners_for(strong, 9):
		strong_total += caps_total(p.caps)
	assert_true(strong_total > weak_total,
		"a stronger monkey must be offered stronger partners (%d vs %d)" % [strong_total, weak_total])


func test_fees_track_the_ceilings_on_offer() -> void:
	var offers := breeding.partners_for(parent, 5)
	for a in offers:
		for b in offers:
			if caps_total(a.caps) > caps_total(b.caps):
				assert_true(a.fee > b.fee,
					"the better pairing must cost more (%d caps/%d fee vs %d caps/%d fee)"
					% [caps_total(a.caps), a.fee, caps_total(b.caps), b.fee])


# --- the arrow preview -------------------------------------------------------

func test_preview_is_pure_and_repeatable() -> void:
	# Reopening the confirm box may never reroll the arrows.
	var partner := partner_of(parent, Breeding.Archetype.SMART)
	var first := breeding.preview(parent, partner)
	var second := breeding.preview(parent, partner)
	assert_eq(first.partner_id, partner.id)
	assert_eq(first.fee, partner.fee)
	for stat in Monkey.STATS:
		assert_eq(second.arrows[stat], first.arrows[stat])


func test_preview_covers_every_stat() -> void:
	var pv := breeding.preview(parent, partner_of(parent, Breeding.Archetype.AVG))
	assert_eq(pv.arrows.size(), Monkey.STATS.size())
	for stat in Monkey.STATS:
		assert_has(pv.arrows, stat)
		assert_in_range(pv.arrows[stat], Breeding.Arrow.DOWN, Breeding.Arrow.UP)


func test_the_favoured_stat_points_up() -> void:
	var partner := partner_of(parent, Breeding.Archetype.POWER)
	var pv := breeding.preview(parent, partner)
	assert_eq(pv.arrows[Monkey.Stat.POWER], Breeding.Arrow.UP,
		"a POWER TYPE pairing must advertise a rising Power ceiling")


func test_arrows_can_point_down_and_are_warned_about() -> void:
	# Dossier §8 [C]: the preview arrows can point down, and caps genuinely
	# regress. A weak specialist partner is the pairing that does it.
	var weak := Breeding.Partner.new()
	weak.id = "test_weak_power"
	weak.archetype = Breeding.Archetype.POWER
	weak.fee = 500
	for stat in Monkey.STATS:
		weak.caps[stat] = 40
	var pv := breeding.preview(parent, weak)
	var down := 0
	for stat in Monkey.STATS:
		if pv.arrows[stat] == Breeding.Arrow.DOWN:
			down += 1
	assert_true(down > 0, "a poor pairing must show at least one down arrow")
	assert_false(pv.warning.is_empty(), "a falling ceiling must be warned about")
	assert_has(pv.warning, "lower")


func test_preview_of_nothing_is_safe() -> void:
	var pv := breeding.preview(parent, null)
	assert_eq(pv.arrows.size(), 0)
	assert_false(pv.warning.is_empty())
	var pv2 := breeding.preview(null, partner_of(parent, Breeding.Archetype.AVG))
	assert_eq(pv2.arrows.size(), 0)


# --- the inheritance rule ----------------------------------------------------

func test_generation_two_beats_generation_one_on_average() -> void:
	var starter := RunState.starter_caps()
	var parent_total := caps_total(starter)
	var wins := 0
	var total_ratio := 0.0
	var runs := 300
	for i in runs:
		var seeded := Breeding.new(rules, MpRng.new(SEED + i))
		var partner := seeded.partners_for(make_parent(), 1 + i)[i % 6]
		var baby_caps := Breeding.inherit_caps(starter, partner.caps, partner.archetype, MpRng.new(SEED + i))
		var ratio := float(caps_total(baby_caps)) / float(parent_total)
		total_ratio += ratio
		if caps_total(baby_caps) > parent_total:
			wins += 1
	var mean_ratio := total_ratio / float(runs)
	assert_true(mean_ratio > 1.0,
		"generation 2 must out-ceiling generation 1 on average (mean ratio %f)" % mean_ratio)
	assert_true(wins > runs / 2,
		"most pairings must be an improvement (%d of %d)" % [wins, runs])


func test_individual_stats_can_regress() -> void:
	# lthammy's observed row: Str 284 -> 169 in the same step Spd went 124 -> 297
	# (§8 [U]). Regression has to be reachable.
	var starter := RunState.starter_caps()
	var regressed := 0
	var raised := 0
	for i in 200:
		var seeded := Breeding.new(rules, MpRng.new(SEED + i * 31))
		var partner := seeded.partners_for(make_parent(), 2 + i)[Breeding.Archetype.SPEED]
		var baby_caps := Breeding.inherit_caps(starter, partner.caps, partner.archetype, MpRng.new(SEED + i * 31))
		for stat in Monkey.STATS:
			if int(baby_caps[stat]) < int(starter[stat]):
				regressed += 1
			elif int(baby_caps[stat]) > int(starter[stat]):
				raised += 1
	assert_true(regressed > 0, "a poor pairing must be able to lose a column")
	assert_true(raised > regressed, "regression must be the exception, not the rule")


func test_regression_is_not_guaranteed() -> void:
	var starter := RunState.starter_caps()
	var clean_runs := 0
	for i in 200:
		var seeded := Breeding.new(rules, MpRng.new(SEED + i * 7))
		var partner := seeded.partners_for(make_parent(), 3 + i)[Breeding.Archetype.AVG]
		var baby_caps := Breeding.inherit_caps(starter, partner.caps, partner.archetype, MpRng.new(SEED + i * 7))
		var fell := false
		for stat in Monkey.STATS:
			if int(baby_caps[stat]) < int(starter[stat]):
				fell = true
		if not fell:
			clean_runs += 1
	assert_true(clean_runs > 0, "an even pairing must sometimes raise every column")


func test_inherit_caps_is_seeded_and_deterministic() -> void:
	var starter := RunState.starter_caps()
	var partner_caps := {
		Monkey.Stat.POWER: 200, Monkey.Stat.SPEED: 180, Monkey.Stat.KNOWLEDGE: 160,
		Monkey.Stat.STRENGTH: 190, Monkey.Stat.STAMINA: 210,
	}
	var a := Breeding.inherit_caps(starter, partner_caps, Breeding.Archetype.STRONG, MpRng.new(99))
	var b := Breeding.inherit_caps(starter, partner_caps, Breeding.Archetype.STRONG, MpRng.new(99))
	var c := Breeding.inherit_caps(starter, partner_caps, Breeding.Archetype.STRONG, MpRng.new(100))
	for stat in Monkey.STATS:
		assert_eq(b[stat], a[stat], "the same seed must produce the same ceilings")
	assert_ne(caps_total(c), caps_total(a), "a different seed must produce different ceilings")


func test_inherit_caps_always_returns_all_five_stats() -> void:
	var out := Breeding.inherit_caps({}, {}, Breeding.Archetype.AVG, MpRng.new(5))
	assert_eq(out.size(), Monkey.STATS.size())
	for stat in Monkey.STATS:
		assert_eq(out[stat], Breeding.CAP_FLOOR,
			"two blank parents bottom out on the floor, never below it")


func test_inherit_caps_clamps_negative_and_missing_columns() -> void:
	var broken := {
		Monkey.Stat.POWER: -500, Monkey.Stat.SPEED: 0,
		# KNOWLEDGE, STRENGTH and STAMINA missing entirely
	}
	var out := Breeding.inherit_caps(broken, broken, Breeding.Archetype.SMART, MpRng.new(11))
	for stat in Monkey.STATS:
		assert_in_range(out[stat], Breeding.CAP_FLOOR, Breeding.CAP_CEILING)


func test_a_silent_partner_column_falls_back_to_the_parent() -> void:
	# A partner with no data on a column must not drag that ceiling to zero.
	var starter := RunState.starter_caps()
	var quiet := {Monkey.Stat.POWER: 300}
	var out := Breeding.inherit_caps(starter, quiet, Breeding.Archetype.AVG, null)
	assert_true(int(out[Monkey.Stat.STAMINA]) > 100,
		"the missing column keeps the parent's ceiling as its partner (%d)" % int(out[Monkey.Stat.STAMINA]))


func test_inherit_caps_respects_the_ceiling() -> void:
	var huge := {}
	for stat in Monkey.STATS:
		huge[stat] = 100000
	var out := Breeding.inherit_caps(huge, huge, Breeding.Archetype.POWER, MpRng.new(3))
	for stat in Monkey.STATS:
		assert_eq(out[stat], Breeding.CAP_CEILING)


func test_a_null_rng_takes_the_average_roll() -> void:
	var starter := RunState.starter_caps()
	var a := Breeding.inherit_caps(starter, starter, Breeding.Archetype.AVG, null)
	var b := Breeding.inherit_caps(starter, starter, Breeding.Archetype.AVG, null)
	for stat in Monkey.STATS:
		assert_eq(b[stat], a[stat])


func test_the_favoured_stat_outgrows_the_rest() -> void:
	var flat := {}
	for stat in Monkey.STATS:
		flat[stat] = 200
	var out := Breeding.inherit_caps(flat, flat, Breeding.Archetype.STAMINA, null)
	for stat in Monkey.STATS:
		if stat == Monkey.Stat.STAMINA:
			continue
		assert_true(int(out[Monkey.Stat.STAMINA]) > int(out[stat]),
			"an STM TYPE pairing must push Stamina hardest")


# --- breeding ----------------------------------------------------------------

func test_the_baby_inherits_the_ceiling_not_the_stats() -> void:
	# Dossier §8 [C]: what is inherited is the ceiling. The baby starts near zero.
	var capped := make_capped_parent()
	var partner := partner_of(capped, Breeding.Archetype.AVG)
	var res := breeding.breed(capped, partner, "Tomato", null)
	assert_not_null(res.baby)
	for stat in Monkey.STATS:
		assert_in_range(res.baby.get_stat(stat), 0, Breeding.BABY_START_STAT,
			"%s must start near zero" % Monkey.stat_label(stat))
		assert_true(res.baby.get_cap(stat) >= Breeding.CAP_FLOOR)
		assert_false(res.baby.is_capped(stat), "a newborn is nowhere near its star")
	assert_eq(res.baby.generation, capped.generation + 1)
	assert_eq(res.baby.monkey_name, "Tomato")


func test_the_baby_must_be_won_over_from_scratch() -> void:
	# §8 [C]: the baby must be re-befriended with food and re-take the pro test.
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.SMART), "Cookie", null)
	assert_eq(res.baby.friendship, 0)
	assert_false(res.baby.is_befriended())
	assert_eq(res.baby.wins, 0)
	assert_eq(res.baby.losses, 0)
	assert_eq(res.baby.days_since_match, 0)
	assert_has(res.message, "ladder", "the UI needs telling the baby restarts at the bottom")


func test_the_baby_is_born_neither_starving_nor_stuffed() -> void:
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.AVG), "Pizza", null)
	assert_false(res.baby.is_starving())
	assert_false(res.baby.is_stuffed())
	assert_eq(res.baby.paralysed_slots, 0)
	assert_eq(res.baby.current_strength, res.baby.max_strength())
	assert_eq(res.baby.current_stamina, res.baby.max_stamina())


func test_cap_changes_report_both_ends() -> void:
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.STRONG), "Betty", null)
	assert_eq(res.cap_changes.size(), Monkey.STATS.size())
	for stat in Monkey.STATS:
		var pair: Array = res.cap_changes[stat]
		assert_eq(pair.size(), 2)
		assert_eq(int(pair[0]), parent.get_cap(stat), "old cap must be the parent's")
		assert_eq(int(pair[1]), res.baby.get_cap(stat), "new cap must be the baby's")


func test_the_retired_parent_is_preserved_and_readable() -> void:
	# RULE CHANGE: breeding_destroys_parent = false. The original destroys the
	# parent (§8 [C]); here it retires to a viewable roster.
	var capped := make_capped_parent()
	capped.wins = 4
	capped.losses = 1
	var caps_before := capped.caps.duplicate()
	var res := breeding.breed(capped, partner_of(capped, Breeding.Archetype.AVG), "Lemon", null)
	assert_true(res.parent_retired)
	assert_false(res.parent_destroyed)
	assert_true(capped.retired, "the parent carries the retired flag for the roster screen")
	assert_eq(res.parent, capped, "the roster gets the very same monkey back")
	assert_eq(capped.monkey_name, "Freddy")
	assert_eq(capped.wins, 4)
	assert_eq(capped.losses, 1)
	assert_eq(capped.generation, 1)
	for stat in Monkey.STATS:
		assert_eq(capped.get_cap(stat), int(caps_before[stat]), "a retired ceiling is not edited")
		assert_eq(capped.get_stat(stat), int(caps_before[stat]), "a retired monkey keeps its stats")
	assert_has(res.message, "retires")


func test_the_destroy_flag_is_honoured_when_it_is_flipped() -> void:
	rules.breeding_destroys_parent = true
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.AVG), "Jimbo", null)
	assert_true(res.parent_destroyed)
	assert_false(res.parent_retired)
	assert_false(parent.retired, "a destroyed parent is gone, not retired to the roster")
	assert_not_null(res.baby)


func test_a_retired_parent_cannot_breed_again() -> void:
	var partner := partner_of(parent, Breeding.Archetype.AVG)
	breeding.breed(parent, partner, "Agatha", null)
	var second := breeding.breed(parent, partner, "Mango", null)
	assert_null(second.baby)
	assert_false(second.parent_retired)
	assert_has(second.message, "retired")


func test_breeding_with_nothing_is_safe() -> void:
	assert_null(breeding.breed(null, partner_of(parent, Breeding.Archetype.AVG), "X", null).baby)
	assert_null(breeding.breed(parent, null, "X", null).baby)
	assert_false(parent.retired)


func test_a_blank_name_still_produces_a_named_monkey() -> void:
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.AVG), "   ", null)
	assert_false(res.baby.monkey_name.strip_edges().is_empty())


func test_breeding_is_reproducible_for_a_seed() -> void:
	var one := Breeding.new(rules, MpRng.new(4242))
	var two := Breeding.new(rules, MpRng.new(4242))
	var parent_one := make_parent()
	var parent_two := make_parent()
	var res_one := one.breed(parent_one, one.partners_for(parent_one, 6)[2], "Dragon", null)
	var res_two := two.breed(parent_two, two.partners_for(parent_two, 6)[2], "Dragon", null)
	for stat in Monkey.STATS:
		assert_eq(res_two.baby.get_cap(stat), res_one.baby.get_cap(stat))
	assert_eq(res_two.baby.species_type, res_one.baby.species_type)
	assert_eq(res_two.baby.sex, res_one.baby.sex)


func test_the_bred_signal_carries_the_result() -> void:
	var seen: Array = []
	breeding.bred.connect(func(result: Breeding.BreedResult) -> void: seen.append(result))
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.AVG), "Corn", null)
	assert_eq(seen.size(), 1)
	assert_eq(seen[0], res)


# --- the dating fee ----------------------------------------------------------

func test_the_dating_fee_is_charged() -> void:
	var economy := SpyEconomy.new(rules)
	economy.money = 100000
	var partner := partner_of(parent, Breeding.Archetype.AVG)
	var res := breeding.breed(parent, partner, "Squid", economy)
	assert_not_null(res.baby)
	assert_eq(res.fee_paid, partner.fee)
	assert_eq(economy.charges, [partner.fee] as Array[int])
	assert_eq(economy.money, 100000 - partner.fee)


func test_an_unaffordable_pairing_is_refused_without_side_effects() -> void:
	var economy := SpyEconomy.new(rules)
	economy.allow = false
	var partner := partner_of(parent, Breeding.Archetype.POWER)
	var res := breeding.breed(parent, partner, "Crab", economy)
	assert_null(res.baby)
	assert_eq(res.fee_paid, 0)
	assert_false(res.parent_retired)
	assert_false(parent.retired, "a refused pairing must not retire the parent")
	assert_false(res.message.is_empty())


func test_no_economy_means_no_charge() -> void:
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.AVG), "Rice", null)
	assert_not_null(res.baby)
	assert_eq(res.fee_paid, 0)


# --- advice ------------------------------------------------------------------

func test_can_breed_follows_the_all_starred_advice() -> void:
	# §8: both FAQ authors and the achievement-set author say breed only once
	# every stat is starred. It is advice, not a block — breed() still works.
	assert_false(breeding.can_breed(parent))
	var res := breeding.breed(parent, partner_of(parent, Breeding.Archetype.AVG), "Melon", null)
	assert_not_null(res.baby, "the advice must never hard-block breeding")

	var capped := make_capped_parent()
	assert_true(breeding.can_breed(capped))
	capped.retired = true
	assert_false(breeding.can_breed(capped))
	assert_false(breeding.can_breed(null))


func test_breed_advice_reads_the_star_count() -> void:
	assert_has(breeding.breed_advice(parent), "No stat is starred")
	parent.add_stat(Monkey.Stat.POWER, 9999)
	assert_has(breeding.breed_advice(parent), "1 of 5")
	assert_has(breeding.breed_advice(make_capped_parent()), "Every stat is starred")
	assert_has(breeding.breed_advice(null), "no monkey")
	var retired := make_parent("Ghost")
	retired.retired = true
	assert_has(breeding.breed_advice(retired), "already retired")


# --- static lookups ----------------------------------------------------------

func test_archetype_labels_match_the_in_game_menu() -> void:
	assert_eq(Breeding.archetype_label(Breeding.Archetype.AVG), "AVG")
	assert_eq(Breeding.archetype_label(Breeding.Archetype.POWER), "POWER TYPE")
	assert_eq(Breeding.archetype_label(Breeding.Archetype.SPEED), "SPEED TYPE")
	assert_eq(Breeding.archetype_label(Breeding.Archetype.SMART), "SMART TYPE")
	assert_eq(Breeding.archetype_label(Breeding.Archetype.STRONG), "STRONG TYPE")
	assert_eq(Breeding.archetype_label(Breeding.Archetype.STAMINA), "STM TYPE")


func test_archetype_stat_maps_onto_the_five_stats() -> void:
	assert_eq(Breeding.archetype_stat(Breeding.Archetype.AVG), -1)
	assert_eq(Breeding.archetype_stat(Breeding.Archetype.POWER), Monkey.Stat.POWER)
	assert_eq(Breeding.archetype_stat(Breeding.Archetype.SPEED), Monkey.Stat.SPEED)
	# SMART maps onto KNOWLEDGE, the stat trained by shopping errands (§3 [C]).
	assert_eq(Breeding.archetype_stat(Breeding.Archetype.SMART), Monkey.Stat.KNOWLEDGE)
	# STRONG maps onto STRENGTH, which is the health bar, not damage (§3 [C]).
	assert_eq(Breeding.archetype_stat(Breeding.Archetype.STRONG), Monkey.Stat.STRENGTH)
	assert_eq(Breeding.archetype_stat(Breeding.Archetype.STAMINA), Monkey.Stat.STAMINA)
