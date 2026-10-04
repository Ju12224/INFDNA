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
const FADE = 1.5                          # lanes behind the cut over which things fade in
const TALL_GAP = 1.5                      # zoomed fully in, tall things (trees) more than this many lanes in front of the focus are gone
const LIFT_RANGE = 700.0                  # world px the camera goes below the ground for the band to flatten to LIFT_MIN
const LIFT_MIN = 0.45

static var focus := float(LANES)          # lane number the camera dollies toward
static var cut := -99.0                   # lane number of the camera's near plane (< 1: nothing is cut)
static var dolly := 0.0                   # 0 zoomed out to Z_ALL or further .. 1 fully in
static var lift := 1.0                    # the band flattens as the camera goes down into the nest (vertical parallax)


# Once a frame from colony.gd: camera centre and zoom, the focus lane number, and the ground's y under the camera.
static func update(cam: Vector2, zoom: float, f: float, ground: float) -> void:
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


# How much of something in `lane` to draw: 0 in front of the camera's cut (do not draw it at all), fading in over FADE lanes behind
# it, 1 everywhere when zoomed out. tall: for things that would fill the screen zoomed in (trees and what hangs on them): when fully
# zoomed in they are gone from TALL_GAP lanes in front of the focus too.
static func lane_alpha(lane: float, tall: bool = false) -> float:
	var n = num(lane)
	var c = cover_n()
	var a = smoothstep(c, c + FADE, n) if c > 1.0 else 1.0
	if tall and dolly > 0.0:
		a *= 1.0 - dolly * (1.0 - smoothstep(focus - TALL_GAP - FADE, focus - TALL_GAP, n))
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
