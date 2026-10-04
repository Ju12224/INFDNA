extends RefCounted
# Beehives on the meadow trees (the owner's art, content/art/hive; tools/art/make_hives.py). Some trees carry one, decided from the tree's
# seed so the sim and the view agree without talking. A hive tree drops honeycomb instead of fruit (richer). Every load the ants carry
# off scars the hive: whole, then dripping, then torn open, then it falls and breaks on the ground (a big honey pile), and after a while a
# new one grows. Bees defend it: taking honey brings a few out to fight now and then (they guard the tree, then go back in).

const CHANCE = 0.45           # share of the trees that can carry a hive (not stumps or logs)
const DRIP_AT = 60.0          # honey taken before it drips ...
const TORN_AT = 140.0         # ... is torn open ...
const FALL_AT = 220.0         # ... and falls
const REGROW = 360.0          # seconds before a fallen hive is replaced by a new one
const DROP = 14.0             # honey per drop (a fruit tree drops 9)
const DROP_MAX = 48.0
const FALLEN_HONEY = 160.0
const BEE_COOLDOWN = 30.0     # seconds between two sorties of the guard bees
const BEE_LIFE = 45.0         # a guard bee goes back into the hive after this long


static func hash1(x: float) -> float:
	return fmod(abs(sin(x * 12.9898) * 43758.5453), 1.0)


# Whether the tree grown from this feature seed carries a hive. ground_view.gd picks the tree's picture by hash1(seed + 99): above 0.93 it
# is a stump or a log, which carry none.
static func has_hive(sd: float) -> bool:
	return hash1(sd + 99.0) < 0.93 and hash1(sd + 311.7) < CHANCE


# 0 whole, 1 dripping, 2 torn open, 3 fallen
static func stage(h: Dictionary) -> int:
	if h.get("fallen", false):
		return 3
	var tk = float(h.get("taken", 0.0))
	return 0 if tk < DRIP_AT else (1 if tk < TORN_AT else 2)
