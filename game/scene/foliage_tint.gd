extends RefCounted
# The colour of the year for the owner's tree and hill pictures. Every picture here is multiplied by a tint that follows the year's phase
# (Seasons.phase, 0 = the first day of spring), and every change is eased (smoothstep between keyframes), so nothing ever pops:
#   spring  a little fresh, yellow-green        summer  none, as drawn
#   autumn  orange, red or gold                 winter  a muted brown-olive (never summer green)
# surface_view.gd uses it for its trees: the leafy ones have their own spring, summer and autumn pictures and cross-fade between them with
# weights(); the spruce is an evergreen (only a little darker and bluer in winter). sky_view.gd tints the green hill strips with tint(),
# the autumn colour sliding along the strip, so a row of trees on it is not one colour.

const SPRING = Color(1.12, 1.10, 0.80)
const AUTUMN = [Color(2.3, 0.97, 0.95), Color(2.0, 0.44, 0.76), Color(2.4, 1.38, 1.04)]     # orange, red, gold (x the owner's green)
const WINTER = Color(1.25, 0.80, 0.80)
const EVERGREEN_WINTER = Color(0.80, 0.88, 1.0)
# [year phase, state] where state is 0 spring, 1 summer, 2 autumn, 3 winter: the thaw turns winter into spring over 0.06..0.14 (the snow is
# gone by 0.05), spring into summer over 0.24..0.34, the leaves turn over 0.42..0.60 (Seasons.autumn) and the cold takes them over 0.70..0.82
const KEYS = [[0.0, 3], [0.06, 3], [0.14, 0], [0.24, 0], [0.34, 1], [0.42, 1], [0.60, 2], [0.70, 2], [0.82, 3], [1.0, 3]]


# How much of each state the year is in at phase w: [spring, summer, autumn, winter], summing to 1.
static func weights(w: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	for i in range(KEYS.size() - 1):
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if w <= b[0]:
			var f = smoothstep(a[0], b[0], w)
			out[a[1]] += 1.0 - f
			out[b[1]] += f
			return out
	out[3] = 1.0
	return out


# The autumn colour at u (a picture's own x, 0..1, repeating): the three colours run into each other along it.
static func autumn_at(u: float) -> Color:
	var c := Color(0, 0, 0, 0)
	var sum := 0.0
	for i in 3:
		var k = pow(0.5 + 0.5 * cos(TAU * (u * 5.0 + i / 3.0)), 3.0) + 0.02
		c += AUTUMN[i] * k
		sum += k
	return Color(c.r / sum, c.g / sum, c.b / sum, 1.0)


# The multiplier for a picture of green foliage at phase w, with its autumn colour autumn (one of AUTUMN, or autumn_at()).
static func tint(w: float, autumn: Color, strength: float = 1.0) -> Color:
	var k = weights(w)
	var c = SPRING * k[0] + Color.WHITE * k[1] + autumn * k[2] + WINTER * k[3]
	return Color(lerpf(1.0, c.r, strength), lerpf(1.0, c.g, strength), lerpf(1.0, c.b, strength), 1.0)


# The same for an evergreen: nothing but a little darker and bluer through the winter.
static func evergreen(w: float) -> Color:
	var c = Color.WHITE.lerp(EVERGREEN_WINTER, weights(w)[3])
	c.a = 1.0
	return c
