extends RefCounted
# The meadow band: the surface is a strip of ground seen a little from above (2.5D), in front of the cut face of the soil. Everything
# on the surface stands in a depth lane, a float from 0 (the back, highest on screen, smallest) to 1 (the front lip, the soil's top
# line); past 1 is in front of the lip. Players and the roadmap number the lanes 1 (front) to LANES (back): num() and lane_of() convert.
# (The sim keeps one row of surface cells; lanes are only how the views spread things out.)
#
# The lanes are evenly spaced in depth and seen through a pinhole: a lane's scale is 1 / (1 + K * depth) and it stands
# HORIZON * (1 - scale) above the front lip, so the rows crowd together toward the back as real ground does.
#
# Zoom is a dolly: zooming in moves the camera into the band toward the focus lane (the lane that was under the mouse). Lanes nearer
# the camera than `cut` are behind it: not drawn at all. surface_view stands a row of the owner's grass on the cut (the cover row), so
# what is dropped vanishes behind it. Every view fades what it draws on the surface by lane_alpha(lane). colony.gd calls update()
# once a frame, before the views draw.

const LANES = 15
const S_BACK = 0.45                       # scale of the back lane
const K = 1.0 / S_BACK - 1.0
const HORIZON = 170.0                     # world px from the front lip to the horizon, at scale 1
const DEPTH = HORIZON * (1.0 - S_BACK)    # the back lane stands this high above the front lip (93.5 world px)
const LANE_K = 1.0                        # (kept for callers: the highest a thing stands above its cell is DEPTH * LANE_K)
const FRONT_STEP = 39.6                   # past the lip (lane > 1): world px lower per lane, as before
const DOLLY = 39.0                        # lanes from the camera to the focus at zoom 1: 6.5 lanes at zoom 6, nothing cut below 2.6
const Z_ALL = 2.5                         # dolly 0 at this zoom and below ...
const Z_MAX = 6.0                         # ... 1 at this one
const FADE = 1.0                          # lanes behind the cut over which things fade in
const TALL_GAP = 1.5                      # zoomed fully in, tall things (trees) more than this many lanes in front of the focus are gone
# The thick grass curtains (surface_view.gd) stand at these lanes, each on a lane-bucket boundary of units_view.gd (lane * 16), so the
# ants sort cleanly in front of or behind them: back (behind every tree), middle (in front of the food piles and the outgoing trail),
# front (in front of the fight lane). The fourth, the fringe on the soil's top line, is surface_view's cover row.
const CURTAINS = [0.0625, 0.5625, 0.875]
const PART_SPAN = 0.25                    # share of the dolly over which one curtain parts
const TALL_SCREEN = 0.6                   # a tree (tall scenery) never stands taller than this share of the screen: zoomed in, a giant's trunk
										  # would otherwise fill it as one blurry wall (tall_scale(); creatures_view hangs hives by it too)
const FRAME_Y = 0.65                      # fully dollied in, the focus lane's ground line sits this far down the screen (colony.gd frames it)
const LIFT_RANGE = 700.0                  # world px the camera goes below the ground for the band to flatten to LIFT_MIN
const LIFT_MIN = 0.45

static var focus := float(LANES)          # lane number the camera dollies toward
static var cut := -99.0                   # lane number of the camera's near plane (< 1: nothing is cut)
static var dolly := 0.0                   # 0 zoomed out to Z_ALL or further .. 1 fully in
static var lift := 1.0                    # the band flattens as the camera goes down into the nest (vertical parallax)
static var view_h := 1057.0               # the screen's height in world px at this zoom


# Once a frame from colony.gd: camera centre and zoom, the focus lane number, and the ground's y under the camera.
static func update(cam: Vector2, zoom: float, f: float, ground: float, screen_h: float = 1057.0) -> void:
	view_h = screen_h / max(zoom, 0.01)
	focus = f
	cut = f - DOLLY / max(zoom, 0.01)
	dolly = clamp(log(max(zoom, 0.01) / Z_ALL) / log(Z_MAX / Z_ALL), 0.0, 1.0)
	lift = clamp(1.0 - (cam.y - ground) / LIFT_RANGE, LIFT_MIN, 1.0)


# Lane (0 back .. 1 front) to lane number (1 front .. LANES back), and back.
static func num(lane: float) -> float:
	return 1.0 + (1.0 - lane) * (LANES - 1)


static func lane_of(n: float) -> float:
	return 1.0 - (n - 1.0) / (LANES - 1)


# Perspective: things in the back lanes are smaller. Past the front lip (lane > 1) they loom larger.
static func persp(lane: float) -> float:
	return 1.0 / (1.0 + K * (1.0 - lane)) if lane <= 1.0 else 1.0 + (lane - 1.0) * 1.8


# How far above the front lip something in `lane` stands (world px; negative past the lip).
static func raise(lane: float) -> float:
	return HORIZON * (1.0 - persp(lane)) * lift if lane <= 1.0 else -(lane - 1.0) * FRONT_STEP


# Screen-space y (world px) of something in `lane` whose cell's top is at world y `sy`.
static func lane_y(sy: float, lane: float) -> float:
	return sy - raise(lane)


# The lane number whose ground line stands `r` world px above the front lip.
static func num_at_raise(r: float) -> float:
	var s = 1.0 - r / (HORIZON * lift)
	if s >= 1.0:
		return 1.0
	if s <= S_BACK:
		return float(LANES)
	return 1.0 + (1.0 / s - 1.0) / K * (LANES - 1)


# Where the cover row stands (lane number): on the cut, or on the front lip when nothing is cut.
static func cover_n() -> float:
	return max(cut, 1.0)


# The scale (1 or less) for a tree of world height `h` (world px at its lane, persp already in): 1 unless it would stand taller than
# TALL_SCREEN of the screen, then shrunk about its foot to that (smoothly, so zooming never makes it pop).
static func tall_scale(h: float) -> float:
	var cap = TALL_SCREEN * view_h
	return 1.0 if h <= cap else cap / h


# How much of something in `lane` to draw: 0 in front of the camera's cut (do not draw it at all), fading in over FADE lanes behind
# it, 1 everywhere when zoomed out. tall: for things that would fill the screen zoomed in (trees and what hangs on them): when fully
# zoomed in they are gone from TALL_GAP lanes in front of the focus too.
static func lane_alpha(lane: float, tall: bool = false) -> float:
	var n = num(lane)
	var c = cover_n()
	var a = smoothstep(c, c + FADE, n) if c > 1.0 else 1.0
	if tall and dolly > 0.0:
		a *= 1.0 - dolly * (1.0 - smoothstep(focus - TALL_GAP - FADE, focus - TALL_GAP, n))
	elif not tall and lane < CURTAINS[0]:
		a *= 1.0 - curtain_alpha(CURTAINS[0]) * (1.0 - smoothstep(CURTAINS[0] - 0.03, CURTAINS[0], lane))   # behind the closed back curtain
	return a


# How much of the thick grass curtain at `lane` stands (1 closed, 0 parted). Zoomed out every curtain stands. Zooming in parts the
# ones in front of the focus lane, the farthest in front first, so each step in opens one more (and the focus lane is clear when fully
# in); the camera's cut takes the ones it passes, as for everything else.
static func curtain_alpha(lane: float) -> float:
	var a = lane_alpha(lane)
	var dist = focus - num(lane)
	if dist > 0.0 and dolly > 0.0:
		var d0 = clamp(0.75 - 0.06 * dist, 0.0, 0.75)
		a *= 1.0 - smoothstep(d0, d0 + PART_SPAN, dolly)
	return a


# Distance haze, 0..1: how much of the horizon colour a lane takes. Light, growing with depth, and a little more well behind the focus
# when zoomed in (so the focus lane stands out).
static func fog(lane: float) -> float:
	var n = num(lane)
	var d = (n - 1.0) / (LANES - 1)
	return 0.2 * d * d + 0.12 * dolly * clamp((n - focus - 1.0) / 5.0, 0.0, 1.0)


# Depth of field, as a mip bias: none on and near the focus, light well behind it, only when zoomed in.
static func blur(lane: float) -> float:
	return 0.7 * dolly * clamp((num(lane) - focus - 2.0) / 5.0, 0.0, 1.0)
