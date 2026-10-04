extends RefCounted
# The year. Spring, summer, autumn and winter follow each other as a pure function of the colony clock, shared by the sim (how much food
# appears, what the colony eats, how fast the queen lays, how fast ants walk on the surface) and by the views (grass, leaves, snow, sky).
# SEASON_LEN sim seconds each, so a year is twenty minutes and a long run lives through two winters. A run starts at the start of spring.
#
# Autumn is the glut (richer, more frequent food: stock up), winter the lean time (almost no food on the surface, everyone eats more).

const SEASON_LEN = 300.0
const YEAR_LEN = SEASON_LEN * 4.0
const NAMES = ["Spring", "Summer", "Autumn", "Winter"]
const NOTES = [
	"Spring: the thaw. Food returns and the queen lays faster.",
	"Summer: steady food. Keep an eye on the sky.",
	"Autumn: a glut of rich food. Fill the larder before winter!",
	"Winter: next to no food outside; the ants huddle and age slowly. Live off your stores.",
]


# 0..1 around the year (0 = the first day of spring).
static func phase(t: float) -> float:
	return fposmod(t / YEAR_LEN, 1.0)


static func index(t: float) -> int:
	return int(floor(phase(t) * 4.0)) % 4


static func year(t: float) -> int:
	return 1 + int(floor(t / YEAR_LEN))


static func name_of(t: float) -> String:
	return NAMES[index(t)]


# Seconds until the next season begins.
static func to_next(t: float) -> float:
	return SEASON_LEN - fposmod(t, SEASON_LEN)


# A value that holds a season's number through the middle of that season and eases to the next one's across the boundary.
static func blend(t: float, v: Array) -> float:
	var p = phase(t) * 4.0 - 0.5
	var i0 = int(floor(p))
	var f = p - float(i0)
	var a = posmod(i0, 4)
	var b = (a + 1) % 4
	return lerp(float(v[a]), float(v[b]), smoothstep(0.3, 0.7, f))


static func blend_color(t: float, v: Array) -> Color:
	var p = phase(t) * 4.0 - 0.5
	var i0 = int(floor(p))
	var f = smoothstep(0.3, 0.7, p - float(i0))
	var a = posmod(i0, 4)
	var b = (a + 1) % 4
	return Color(v[a]).lerp(Color(v[b]), f)


# Winters get colder: the first is a mild one, the third and later bite.
static func severity(t: float) -> float:
	return clamp(0.55 + 0.25 * float(year(t) - 1), 0.55, 1.0)


# How hard winter is gripping the colony right now, 0..1 (the cold itself, scaled by the winter's severity). A winter's cold
# belongs to the year it began in.
static func winter(t: float) -> float:
	var w = blend(t, [0.0, 0.0, 0.0, 1.0])
	if w <= 0.0:
		return 0.0
	# the thaw at the start of a year belongs to the winter before it
	var yt = t - YEAR_LEN * 0.5 if phase(t) < 0.5 else t
	return w * severity(yt)


# ---- the sim's side
static func food_k(t: float) -> float:        # how often wild food piles appear
	return blend(t, [1.25, 1.0, 1.35, 1.0]) * (1.0 - 0.92 * winter(t))


static func rich_k(t: float) -> float:        # how rich they are
	return blend(t, [1.0, 1.0, 1.3, 1.0])


static func fruit_k(t: float) -> float:       # how fast the fruit trees drop
	return blend(t, [0.8, 1.0, 1.8, 1.0]) * (1.0 - 0.9 * winter(t))


static func upkeep_k(t: float) -> float:      # what the colony eats (heating the nest)
	return 1.0 + 0.3 * winter(t)


static func lay_k(t: float) -> float:         # how fast the queen lays
	return blend(t, [1.1, 1.0, 0.95, 1.0]) * (1.0 - 0.2 * winter(t))


static func raid_k(t: float) -> float:        # how often raids come (the raiders are sluggish in the cold)
	return 1.0 - 0.35 * winter(t)


static func walk_k(t: float) -> float:        # how fast ants walk over the open ground (stiff with cold)
	return 1.0 - 0.15 * winter(t)


static func age_k(t: float) -> float:         # how fast ants grow old: they huddle in the cold, so a lean winter is not a cull by old age too
	return 1.0 - 0.5 * winter(t)


# ---- the views' side (all 0..1)
# Snow on the ground: arrives over the first fifth of winter, melts over the first fifth of spring.
static func snow(t: float) -> float:
	var w = phase(t)
	if w >= 0.75:
		return smoothstep(0.75, 0.80, w)
	if w < 0.05:
		return 1.0 - smoothstep(0.0, 0.05, w)
	return 0.0


# How much of its leaves a tree carries: budding in spring, full in summer, shedding through the end of autumn, bare in winter.
static func leaf(t: float) -> float:
	var w = phase(t)
	if w < 0.12:
		return smoothstep(0.0, 0.12, w)
	if w < 0.55:
		return 1.0
	if w < 0.75:
		return 1.0 - smoothstep(0.55, 0.75, w)
	return 0.0


# How far the leaves have turned: green until the middle of autumn's run-up, then gold, orange and red.
static func autumn(t: float) -> float:
	var w = phase(t)
	if w < 0.42 or w >= 0.78:
		return 0.0
	return smoothstep(0.42, 0.60, w)


# Flowers in the meadow.
static func bloom(t: float) -> float:
	return blend(t, [1.0, 0.75, 0.2, 0.0])


# The colour of the light itself: fresh, warm, golden, cold. Multiplied into the day's tint.
static func grade(t: float) -> Color:
	return blend_color(t, [Color(1.0, 1.0, 1.0), Color(1.0, 0.985, 0.94), Color(1.0, 0.92, 0.82), Color(0.86, 0.93, 1.0)])


# A whole number that changes every ~75 s of the year (every ~19 s while the trees bud and shed): the views rebuild their cached scenery when it does.
static func stage(t: float) -> int:
	var w = phase(t)
	if w < 0.12 or (w >= 0.55 and w < 0.75):
		return 1000 + int(floor(w * 64.0))      # the trees bud and shed leaf in finer steps (about 19 s each), so it reads as a slow change
	return int(floor(w * 16.0))
