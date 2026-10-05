extends RefCounted
# The meadow is ONE lane: everything on the surface (ants, creatures, trees, rocks, hives, food piles, weather decals) stands on the
# single ground line, with no depth offset, no scale or haze by depth, no focus lane, no dolly and no cut. What the player sees of the
# meadow's depth is the owner's thick grass standing along the ground line in front of it (surface_view.gd), which fades as the camera
# zooms in.
#
# This file is only what is left of the old 15-lane band, kept so the code that still passes a lane (the sim keeps a `lane` on its ants
# and creatures; effects_view.gd and controls.gd ask for lane_y and persp) keeps working: every lane is the same lane.

const LANES = 1
const DEPTH = 0.0          # how far above the ground line the farthest lane stands
const LANE_K = 1.0


# Lane (0 back .. 1 front) and lane number (1 front .. LANES back): there is one.
static func num(_lane: float) -> float:
	return 1.0


static func lane_of(_n: float) -> float:
	return 1.0


# Scale by depth: none.
static func persp(_lane: float) -> float:
	return 1.0


# How high above the ground line something in the lane stands: not at all.
static func raise(_lane: float) -> float:
	return 0.0


# Screen y (world px) of something in the lane whose cell's top is at world y `sy`: the same.
static func lane_y(sy: float, _lane: float) -> float:
	return sy


# How much of something in the lane to draw: all of it.
static func lane_alpha(_lane: float, _tall: bool = false) -> float:
	return 1.0


# Distance haze and depth of field: none.
static func fog(_lane: float) -> float:
	return 0.0


static func blur(_lane: float) -> float:
	return 0.0
