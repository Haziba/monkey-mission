class_name Breeding
extends RefCounted

## Breeding — the signature system. Dossier §8.
##
## Called "dating" in English, お見合い / 配合 in Japanese. The in-game partner
## menu offers six archetypes: AVG / POWER / SPEED / SMART / STRONG / STM TYPE
## [C], previewed as directional arrows which CAN POINT DOWN [C].
##
## What is inherited is the CEILING, not the current stats [C]. The baby starts
## near zero, must be re-befriended with food, and shops badly because its
## Knowledge is low [C]. Caps can regress per-stat [C].
##
## RULE CHANGE FOR THIS BUILD: GameRules.breeding_destroys_parent = false.
## The original permanently destroys the parent (§8 [C], framed as 引退). Here
## the parent RETIRES to a viewable roster instead. Honour the flag — if it is
## ever set true, the parent must actually be removed.
##
## [X] THE INHERITANCE FORMULA IS UNDOCUMENTED (dossier §8, §14.3, §14.9). No
## datamining exists and the two community estimates conflict (~+100 flat per
## generation vs near-doubling). The observed cap tuples in §8 are the only hard
## data: growth is uneven per stat, individual stats genuinely go down, and
## growth compounds rather than adding a constant. Whatever formula the
## implementing agent picks needs a DIVERGENCE comment citing that table.
## Also [X]: whether type, special moves or food preferences are inherited
## (§14.8) and whether sex matters at all (§14.16).

enum Archetype { AVG, POWER, SPEED, SMART, STRONG, STAMINA }

const ARCHETYPE_LABELS: PackedStringArray = [
	"AVG", "POWER TYPE", "SPEED TYPE", "SMART TYPE", "STRONG TYPE", "STM TYPE",
]

## Arrow directions shown in the partner preview.
enum Arrow { DOWN, FLAT, UP }


# --- the inheritance rule ----------------------------------------------------
#
# DIVERGENCE: the whole block of constants below is invented. Dossier §8 and
# §14.3 mark the inheritance formula [X] — nobody has datamined it and the two
# community estimates flatly conflict ("+100 per generation" vs "mid 300s to
# mid 600s in one generation"). The only hard data is the observed cap table in
# §8, in Pow/Spd/Know/Str/Stm order:
#
#   Chromium0  145/119/116/145/145 -> 204/130/130/185/162   (x1.41 .. x1.09)
#   Cmvyas     159/123/096/151/156 -> 447/405/417/445/449   (x2.81 .. x4.34)
#   lthammy    272/124/136/284/184 -> 205/297/292/169/317   (x0.60 .. x2.40)
#              -> gen3 820/788/760/845/788                  (x2.49 .. x5.00)
#
# Three things fall out of that table and are reproduced here deliberately:
#   1. growth is UNEVEN per stat — hence the per-stat jitter roll;
#   2. individual stats GENUINELY GO DOWN (lthammy Str 284 -> 169 in the same
#      step Spd went 124 -> 297) — hence JITTER_LOW being well below 1.0 and
#      ARCHETYPE_OTHER_MULT being below 1.0;
#   3. growth COMPOUNDS rather than adding a constant — hence a multiplicative
#      blend rather than "+100".
#
# The rule is: blend the parent's ceiling with the partner's, multiply by a
# generational growth factor, an archetype shape and a per-stat jitter roll.
# Both community estimates then come out of the same rule at different price
# points — a cheap, weak partner nets roughly +100 on a gen-1 monkey, an
# expensive one near-doubles, which is exactly the disagreement §8 records.
const PARENT_WEIGHT := 0.45
const PARTNER_WEIGHT := 0.55
const GENERATION_GROWTH := 1.30
const JITTER_LOW := 0.72
const JITTER_HIGH := 1.30
## The expected value of one jitter roll. Used by the arrow preview, which must
## be pure — previewing a partner may never consume RNG or the same partner
## would preview differently each time the player opened the menu.
const JITTER_MEAN := (JITTER_LOW + JITTER_HIGH) * 0.5
const ARCHETYPE_FAVOURED_MULT := 1.30
const ARCHETYPE_OTHER_MULT := 0.94
const ARCHETYPE_AVG_MULT := 1.06

# DIVERGENCE: §3 [C] reports late-generation caps of 820-845 and a strongest-
# reported shop monkey of 896 Power, but no source says whether a hard ceiling
# exists at all. 896 is used as the ceiling because it is the largest cap any
# player has been observed holding.
const CAP_CEILING := 896
# DIVERGENCE: [X]. No minimum is documented. A floor stops a run of bad jitter
# rolls producing a baby that can never be trained into anything.
const CAP_FLOOR := 30

# DIVERGENCE: "the baby starts near zero" (§8 [C]) is qualitative — no source
# gives the actual starting values. Flat 5 in every stat reads as "near zero"
# while leaving the monkey able to stand up in the pro test.
const BABY_START_STAT := 5
# DIVERGENCE: [X]. Nothing says how full a newborn is. 10 of Monkey.FULLNESS_MAX
# is comfortably clear of both FULLNESS_STARVING and FULLNESS_STUFFED, so the
# baby is neither paralysed by hunger nor by digestion on its first morning.
const BABY_START_FULLNESS := 10

# --- the dating shop ---------------------------------------------------------
#
# DIVERGENCE: §8 confirms the six-archetype menu [C] but the partners' own caps,
# and the dating fee, are [X] — no source records either. Partner ceilings are
# generated relative to the parent's average ceiling so the shop stays relevant
# across generations, and the fee is a straight function of the ceilings on
# offer so the strong pairing is the expensive one.
const PARTNER_QUALITY_LOW := 0.85
const PARTNER_QUALITY_HIGH := 2.40
const PARTNER_FAVOURED_SHAPE := 1.45
const PARTNER_OTHER_SHAPE := 0.85
const PARTNER_AVG_SHAPE := 1.00
## Tuned so the cheapest pairing is roughly one good purse and the strongest is
## several — the slice has to be able to reach generation 2.
const FEE_BASE := 300
const FEE_PER_CAP_POINT := 2
const FEE_ROUNDING := 50

## Arrow thresholds, as a ratio of the expected new ceiling to the old one.
const ARROW_UP_RATIO := 1.05
const ARROW_DOWN_RATIO := 0.95

# DIVERGENCE: §8 [C] records that default monkey names are food-themed (Freddy,
# Agatha, Lemon, Betty, Dragon, Jimbo, Tomato, Cookie, Pizza) but never names a
# single dating-shop partner. These are the documented default names reused as
# partner names; Freddy is excluded because §8 [C] fixes it to the starter.
const PARTNER_NAMES: PackedStringArray = [
	"Agatha", "Lemon", "Betty", "Dragon", "Jimbo", "Tomato", "Cookie", "Pizza", "Mango",
]


## A prospective partner at the dating shop.
class Partner extends RefCounted:
	var id: String = ""
	var display_name: String = ""
	var archetype: Archetype = Archetype.AVG
	var species_type: Species.Type = Species.Type.SUNBURST
	var sex: Monkey.Sex = Monkey.Sex.FEMALE
	var fee: int = 0
	## Monkey.Stat -> int. The partner's own caps, which feed the inheritance.
	var caps: Dictionary = {}


## What the player sees before committing the fee.
class Preview extends RefCounted:
	var partner_id: String = ""
	## Monkey.Stat -> Arrow. May point DOWN — a poor pairing loses ground [C].
	var arrows: Dictionary = {}
	var fee: int = 0
	## e.g. "This pairing will lower STRG." Shown in the confirm box.
	var warning: String = ""


## The result of one breeding step, so the UI can narrate it.
class BreedResult extends RefCounted:
	var baby: Monkey = null
	var parent: Monkey = null
	var parent_retired: bool = false
	var parent_destroyed: bool = false
	## Monkey.Stat -> [old_cap, new_cap].
	var cap_changes: Dictionary = {}
	var fee_paid: int = 0
	var message: String = ""


signal bred(result: BreedResult)

var _rules: GameRules
var _rng: MpRng


func _init(rules: GameRules, rng: MpRng) -> void:
	_rules = rules
	_rng = rng


## Six archetype partners offered for this monkey. Fees scale with the caps on
## offer. [X] — no source gives dating fees.
##
## Deterministic for a given (monkey, day): the shop must show the same six
## faces every time the player walks back into it on the same day, so the offers
## come from a sub-RNG seeded off the run seed rather than from `_rng`.
func partners_for(monkey: Monkey, day: int) -> Array[Partner]:
	var out: Array[Partner] = []
	if monkey == null:
		return out
	var offer_rng := MpRng.new(_offer_seed(monkey, day))
	var parent_avg := _average_cap(monkey.caps)
	# DIVERGENCE: §14.16 — the stat card shows a sex marker but no source says
	# whether sex affects breeding at all. Partners are offered as the opposite
	# sex of your monkey (this is an omiai) and sex has no mechanical effect.
	var partner_sex: Monkey.Sex = Monkey.Sex.FEMALE if monkey.sex == Monkey.Sex.MALE else Monkey.Sex.MALE
	var name_offset := offer_rng.randi_range(0, PARTNER_NAMES.size() - 1)
	var species_count := SpeciesDb.all().size()
	for i in ARCHETYPE_LABELS.size():
		var archetype: Archetype = i
		var species_type: Species.Type = offer_rng.randi_range(0, species_count - 1)
		var partner := Partner.new()
		partner.id = _partner_id(day, archetype)
		partner.display_name = PARTNER_NAMES[(name_offset + i) % PARTNER_NAMES.size()]
		partner.archetype = archetype
		partner.species_type = species_type
		partner.sex = partner_sex
		partner.caps = _partner_caps(parent_avg, archetype, offer_rng)
		partner.fee = _fee_for(partner.caps)
		out.append(partner)
	return out


## Directional-arrow preview, per stat. Must be able to point DOWN.
##
## Pure: consumes no RNG, so reopening the menu never changes the arrows. It
## shows the EXPECTED ceiling (jitter at its mean); the actual roll can land on
## either side of it, which is why an UP arrow is not a promise.
func preview(parent: Monkey, partner: Partner) -> Preview:
	var pv := Preview.new()
	if parent == null or partner == null:
		pv.warning = "No pairing selected."
		return pv
	pv.partner_id = partner.id
	pv.fee = partner.fee
	var favoured := archetype_stat(partner.archetype)
	var falling: Array[String] = []
	for stat in Monkey.STATS:
		var old_cap := maxi(0, int(parent.caps.get(stat, 0)))
		var expected := _expected_cap(old_cap, int(partner.caps.get(stat, 0)), stat, favoured)
		var arrow := Arrow.FLAT
		if old_cap <= 0:
			arrow = Arrow.UP if expected > 0 else Arrow.FLAT
		else:
			var ratio := float(expected) / float(old_cap)
			if ratio >= ARROW_UP_RATIO:
				arrow = Arrow.UP
			elif ratio <= ARROW_DOWN_RATIO:
				arrow = Arrow.DOWN
		pv.arrows[stat] = arrow
		if arrow == Arrow.DOWN:
			falling.append(Monkey.stat_label(stat))
	if not falling.is_empty():
		pv.warning = "This pairing will lower %s." % _join_words(falling)
	return pv


## The original gates breeding on nothing in particular, but both FAQ authors
## and the achievement-set author advise breeding only once every stat is
## starred (§8). Return false + reason for a UI hint, never a hard block.
func can_breed(parent: Monkey) -> bool:
	if parent == null or parent.retired:
		return false
	return parent.all_capped()


func breed_advice(parent: Monkey) -> String:
	if parent == null:
		return "There is no monkey to pair."
	if parent.retired:
		return "%s has already retired." % parent.monkey_name
	var starred := 0
	for stat in Monkey.STATS:
		if parent.is_capped(stat):
			starred += 1
	if starred == Monkey.STATS.size():
		return "Every stat is starred. %s has nothing left to learn — pass the ceiling on." % parent.monkey_name
	if starred == 0:
		return "No stat is starred yet. %s still has room to train; breeding now wastes the ceiling you already have." % parent.monkey_name
	# Dossier §8 records two credible schools and does not settle between them,
	# so the advice reports both rather than picking one.
	return "%d of %d stats are starred. Some trainers breed at the first star; the FAQ authors wait for all five." % [starred, Monkey.STATS.size()]


## Produce the baby. Charges the fee, sets the baby's caps, zeroes its stats and
## friendship, bumps its generation, and marks the parent retired (or destroys
## it when GameRules.breeding_destroys_parent is true).
##
## `economy` may be null, in which case no fee is charged and `fee_paid` is 0 —
## that is the headless/test path, not something the game does.
func breed(parent: Monkey, partner: Partner, baby_name: String, economy: Economy) -> BreedResult:
	var res := BreedResult.new()
	res.parent = parent
	if parent == null or partner == null:
		res.message = "There is nobody to pair."
		return res
	if parent.retired:
		res.message = "%s has already retired." % parent.monkey_name
		return res

	var fee := maxi(0, partner.fee)
	if economy != null and fee > 0:
		if not economy.spend(fee):
			res.message = "The dating shop wants %d — you cannot afford it." % fee
			return res
		res.fee_paid = fee

	var new_caps := inherit_caps(parent.caps, partner.caps, partner.archetype, _rng)
	for stat in Monkey.STATS:
		res.cap_changes[stat] = [int(parent.caps.get(stat, 0)), int(new_caps.get(stat, 0))]

	# DIVERGENCE: §14.8 — whether type (and food preferences with it) is
	# inherited is [X]. A coin flip between the two parents keeps both lines
	# alive and makes the species visibly a consequence of the pairing.
	var baby_species: Species.Type = partner.species_type if _rng.chance(0.5) else parent.species_type
	# DIVERGENCE: §14.16 — sex is [X] and does nothing mechanically here.
	var baby_sex: Monkey.Sex = Monkey.Sex.MALE if _rng.chance(0.5) else Monkey.Sex.FEMALE
	var chosen_name := baby_name.strip_edges()
	if chosen_name.is_empty():
		chosen_name = PARTNER_NAMES[_rng.randi_range(0, PARTNER_NAMES.size() - 1)]

	var baby := Monkey.create(chosen_name, baby_species, new_caps, parent.generation + 1, baby_sex)
	# The ceiling is what was inherited; the stats themselves start near zero [C].
	for stat in Monkey.STATS:
		baby.set_stat(stat, mini(BABY_START_STAT, int(new_caps.get(stat, 0))))
	# Re-befriended from scratch [C]. The baby is disobedient and will bite until
	# it is won over with food (§5 [C]).
	baby.friendship = 0
	baby.fullness = BABY_START_FULLNESS
	baby.paralysed_slots = 0
	baby.days_since_match = 0
	baby.restore_pools()
	res.baby = baby

	if _rules != null and _rules.breeding_destroys_parent:
		# Faithful to the original (§8 [C]): the parent vanishes outright.
		res.parent_destroyed = true
	else:
		# RULE CHANGE: the parent retires to a viewable roster instead. It is
		# left completely intact — name, stats, caps, record — so the roster
		# screen can read it back.
		parent.retired = true
		res.parent_retired = true

	res.message = _breed_message(parent, baby, partner, res)
	bred.emit(res)
	return res


## The inheritance rule itself. Monkey.Stat -> int caps in, Monkey.Stat -> int
## caps out. Kept static and RNG-injected so it can be unit-tested across many
## seeds — regression on individual stats must be possible but not certain.
##
## See the DIVERGENCE block at the top of the file for where the numbers come
## from and which observed rows they are trying to reproduce.
static func inherit_caps(
		parent_caps: Dictionary,
		partner_caps: Dictionary,
		archetype: Archetype,
		rng: MpRng) -> Dictionary:
	var favoured := archetype_stat(archetype)
	var out := {}
	# Iterated in Monkey.STATS order so a given seed always spends its rolls in
	# the same sequence.
	for stat in Monkey.STATS:
		var parent_cap := maxi(0, int(parent_caps.get(stat, 0)))
		var partner_cap := maxi(0, int(partner_caps.get(stat, 0)))
		if partner_cap <= 0:
			# A partner with nothing to say about this column contributes the
			# parent's own ceiling rather than dragging the blend to zero.
			partner_cap = parent_cap
		var blended := float(parent_cap) * PARENT_WEIGHT + float(partner_cap) * PARTNER_WEIGHT
		var jitter := JITTER_MEAN if rng == null else rng.randf_range(JITTER_LOW, JITTER_HIGH)
		var raw := blended * GENERATION_GROWTH * _archetype_mult(stat, favoured) * jitter
		out[stat] = clampi(int(round(raw)), CAP_FLOOR, CAP_CEILING)
	return out


static func archetype_label(archetype: Archetype) -> String:
	return ARCHETYPE_LABELS[archetype]


## Which stat an archetype favours. AVG favours none.
static func archetype_stat(archetype: Archetype) -> int:
	match archetype:
		Archetype.POWER:
			return Monkey.Stat.POWER
		Archetype.SPEED:
			return Monkey.Stat.SPEED
		Archetype.SMART:
			return Monkey.Stat.KNOWLEDGE
		Archetype.STRONG:
			return Monkey.Stat.STRENGTH
		Archetype.STAMINA:
			return Monkey.Stat.STAMINA
		_:
			return -1


# --- internals ---------------------------------------------------------------

## The per-stat multiplier an archetype applies. A specialist pairing pushes one
## column hard and lets the other four slip — that is where cap regression comes
## from, and §8 [C] confirms regression is real.
static func _archetype_mult(stat: int, favoured: int) -> float:
	if favoured < 0:
		return ARCHETYPE_AVG_MULT
	return ARCHETYPE_FAVOURED_MULT if stat == favoured else ARCHETYPE_OTHER_MULT


## What `inherit_caps` would produce with an average jitter roll. Drives the
## preview arrows.
static func _expected_cap(parent_cap: int, partner_cap: int, stat: int, favoured: int) -> int:
	var p := maxi(0, parent_cap)
	var q := maxi(0, partner_cap)
	if q <= 0:
		q = p
	var blended := float(p) * PARENT_WEIGHT + float(q) * PARTNER_WEIGHT
	var raw := blended * GENERATION_GROWTH * _archetype_mult(stat, favoured) * JITTER_MEAN
	return clampi(int(round(raw)), CAP_FLOOR, CAP_CEILING)


static func _average_cap(caps: Dictionary) -> float:
	var total := 0.0
	for stat in Monkey.STATS:
		total += float(maxi(0, int(caps.get(stat, 0))))
	return total / float(Monkey.STATS.size())


static func _partner_caps(parent_avg: float, archetype: Archetype, rng: MpRng) -> Dictionary:
	var favoured := archetype_stat(archetype)
	var quality := PARTNER_QUALITY_LOW if rng == null else rng.randf_range(PARTNER_QUALITY_LOW, PARTNER_QUALITY_HIGH)
	var caps := {}
	for stat in Monkey.STATS:
		var shape := PARTNER_AVG_SHAPE
		if favoured >= 0:
			shape = PARTNER_FAVOURED_SHAPE if stat == favoured else PARTNER_OTHER_SHAPE
		caps[stat] = clampi(int(round(parent_avg * quality * shape)), CAP_FLOOR, CAP_CEILING)
	return caps


static func _fee_for(caps: Dictionary) -> int:
	var total := 0
	for stat in Monkey.STATS:
		total += maxi(0, int(caps.get(stat, 0)))
	var raw := FEE_BASE + total * FEE_PER_CAP_POINT
	return int(round(float(raw) / float(FEE_ROUNDING))) * FEE_ROUNDING


static func _partner_id(day: int, archetype: Archetype) -> String:
	var favoured := archetype_stat(archetype)
	var tag := "avg" if favoured < 0 else Monkey.stat_key(favoured)
	return "d%d_%s" % [day, tag]


func _offer_seed(monkey: Monkey, day: int) -> int:
	var base := 0
	if _rng != null:
		base = _rng.seed_value()
	var key := "%s|%d|%d" % [monkey.monkey_name, monkey.generation, day]
	var mixed := base ^ hash(key)
	# MpRng treats 0 as "seed from the clock", which would destroy determinism.
	return mixed if mixed != 0 else 1


func _breed_message(parent: Monkey, baby: Monkey, partner: Partner, res: BreedResult) -> String:
	var risen := 0
	var fallen := 0
	for stat in Monkey.STATS:
		var pair: Array = res.cap_changes[stat]
		if int(pair[1]) > int(pair[0]):
			risen += 1
		elif int(pair[1]) < int(pair[0]):
			fallen += 1
	var fate := "vanishes" if res.parent_destroyed else "retires to the roster"
	var ceilings := "%d ceilings up" % risen
	if fallen > 0:
		ceilings += ", %d down" % fallen
	return "%s pairs with %s (%s). %s %s. %s is born — generation %d, %s. %s must be won over with food and re-enter the ladder at the bottom." % [
		parent.monkey_name,
		partner.display_name,
		archetype_label(partner.archetype),
		parent.monkey_name,
		fate,
		baby.monkey_name,
		baby.generation,
		ceilings,
		baby.monkey_name,
	]


static func _join_words(words: Array[String]) -> String:
	if words.size() <= 1:
		return "" if words.is_empty() else words[0]
	var head := words.slice(0, words.size() - 1)
	return "%s and %s" % [", ".join(head), words[words.size() - 1]]
