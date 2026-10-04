extends RefCounted
# The meadow band: the surface is a strip of ground seen a little from above (2.5D), DEPTH world px deep, in front of the cut face of
# the soil. Everything on the surface stands in a depth lane: lane 0 at the back (highest on screen, smallest), lane 1 on the front
# lip (the soil's top line). The trees, rocks, grass rows and surface ants all place themselves with these, so they agree.
# (The sim keeps one row of surface cells; lanes are only how the views spread things out.)

const DEPTH = 192.0      # depth of the band, world px
const LANE_K = 0.9       # a thing in lane l stands (1 - l) * DEPTH * LANE_K above the front lip


# Screen-space y (world px) of something in `lane` whose cell's top is at world y `sy`.
static func lane_y(sy: float, lane: float) -> float:
	return sy - (1.0 - lane) * DEPTH * LANE_K


# Perspective: things in the back lanes are smaller. Past the front lip (lane > 1) they loom larger.
static func persp(lane: float) -> float:
	return 0.62 + 0.38 * lane if lane <= 1.0 else 1.0 + (lane - 1.0) * 1.8
