extends TestCase

## Monkey is the one core class that ships implemented, because every other
## system clamps through it. These tests pin the cap behaviour that
## GameRules.hard_stat_caps depends on.

var monkey: Monkey


func before_each() -> void:
	monkey = Monkey.create("Freddy", Species.Type.SUNBURST, RunState.starter_caps())


func test_starter_caps_match_the_observed_tuple() -> void:
	# Dossier §3 [U]: Pow 145 / Spd 119 / Know 116 / Str 145 / Stm 145, from
	# three players' byte-identical RetroAchievements rich-presence data.
	assert_eq(monkey.get_cap(Monkey.Stat.POWER), 145)
	assert_eq(monkey.get_cap(Monkey.Stat.SPEED), 119)
	assert_eq(monkey.get_cap(Monkey.Stat.KNOWLEDGE), 116)
	assert_eq(monkey.get_cap(Monkey.Stat.STRENGTH), 145)
	assert_eq(monkey.get_cap(Monkey.Stat.STAMINA), 145)


func test_a_new_monkey_starts_at_zero_and_unbefriended() -> void:
	for stat in Monkey.STATS:
		assert_eq(monkey.get_stat(stat), 0)
	assert_false(monkey.is_befriended(),
		"every new monkey must be won over with food first (dossier §5 [C])")
	assert_eq(monkey.generation, 1)


func test_add_stat_reports_what_actually_landed() -> void:
	assert_eq(monkey.add_stat(Monkey.Stat.POWER, 40), 40)
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), 40)


func test_caps_hard_block_and_report_the_shortfall() -> void:
	monkey.add_stat(Monkey.Stat.POWER, 140)
	var applied := monkey.add_stat(Monkey.Stat.POWER, 50)
	assert_eq(applied, 5, "only the gain up to the cap may land")
	assert_eq(monkey.get_stat(Monkey.Stat.POWER), 145)
	assert_true(monkey.is_capped(Monkey.Stat.POWER))


func test_all_capped_drives_the_breeding_prompt() -> void:
	assert_false(monkey.all_capped())
	for stat in Monkey.STATS:
		monkey.add_stat(stat, 9999)
	assert_true(monkey.all_capped())


func test_strength_is_the_health_bar() -> void:
	# Dossier §3 [C]: the naming trap. Strength is HP, Power is damage.
	monkey.add_stat(Monkey.Stat.STRENGTH, 120)
	monkey.add_stat(Monkey.Stat.STAMINA, 90)
	monkey.restore_pools()
	assert_eq(monkey.max_strength(), 120)
	assert_eq(monkey.current_strength, 120)
	assert_eq(monkey.current_stamina, 90)


func test_stat_line_stars_a_capped_stat() -> void:
	monkey.add_stat(Monkey.Stat.SPEED, 60)
	assert_false(monkey.stat_line(Monkey.Stat.SPEED).contains("*"))
	monkey.add_stat(Monkey.Stat.SPEED, 999)
	assert_has(monkey.stat_line(Monkey.Stat.SPEED), "*",
		"a capped stat displays a star (dossier §3 [C])")


func test_hunger_is_dangerous_at_both_ends() -> void:
	monkey.fullness = 0
	assert_true(monkey.is_starving())
	assert_false(monkey.is_stuffed())
	monkey.fullness = Monkey.FULLNESS_MAX
	assert_true(monkey.is_stuffed())
	assert_false(monkey.is_starving())
	monkey.fullness = 15
	assert_false(monkey.is_starving())
	assert_false(monkey.is_stuffed())


func test_stat_keys_round_trip() -> void:
	for stat in Monkey.STATS:
		assert_eq(Monkey.stat_from_key(Monkey.stat_key(stat)), stat)


func test_species_lookup_resolves() -> void:
	assert_not_null(monkey.species())
	assert_eq(monkey.species().type, Species.Type.SUNBURST)
