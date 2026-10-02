extends Reference
# Natural landmarks along the endless surface: giant trees, boulders, cliffs with cave mouths.
# Pure and deterministic (same seed + same column range -> same list), so the view can draw them
# and the sim can place food at them without sharing any state.
#
# Sizes are in pixels (1 column = WorldGrid.CELL = 6 px; an ant is ~40 px long), so a "tree"
# is several ants wide at the trunk and many hundreds of ants tall.

const SLOT = 64          # columns per generation slot
const CLEAR = 90         # columns around the nest entrance kept free of trees (a short walk is not an expedition)

static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


# Features whose slot lies near [x0, x1] (columns); callers cull by their own extents.
static func in_range(world_seed: int, x0: int, x1: int, ex: int) -> Array:
	var out := []
	for s in range(int(floor(float(x0) / SLOT)) - 4, int(floor(float(x1) / SLOT)) + 5):
		_slot(world_seed, s, ex, out)
	return out


static func _slot(world_seed: int, s: int, ex: int, out: Array) -> void:
	var sd = s * 7.31 + world_seed * 0.173
	var r = _h(sd)
	var x = s * SLOT + int(SLOT * (0.15 + 0.7 * _h(sd, 1.0)))
	var near_nest = abs(x - ex) < CLEAR
	if r < 0.30 and not near_nest:
		out.append({"id": s * 16, "kind": "tree", "x": x, "lane": 0.1 + 0.7 * _h(sd, 2.0), "w": 150.0 + 110.0 * _h(sd, 3.0),
			"h": 1000.0 + 900.0 * _h(sd, 4.0), "seed": sd})
	elif r < 0.62:
		var n = 1 + int(_h(sd, 5.0) * 3.0)
		for k in n:
			var bx = x + int((k - 0.5 * (n - 1)) * 26.0 + (_h(sd, 6.0 + k) - 0.5) * 14.0)
			if abs(bx - ex) < 10:
				continue
			out.append({"id": s * 16 + 1 + k, "kind": "boulder", "x": bx, "lane": 0.05 + 0.9 * _h(sd, 7.0 + k),
				"w": 70.0 + 190.0 * _h(sd, 9.0 + k) * (1.0 if k == 0 else 0.6), "h": 0.0, "seed": sd + k * 3.1})
	elif r < 0.74:
		var cw = 700.0 + 700.0 * _h(sd, 11.0)
		if abs(x - ex) * 6.0 > cw * 0.5 + 520.0:     # a cliff never walls in the starting view
			out.append({"id": s * 16 + 8, "kind": "cliff", "x": x, "lane": 0.0, "w": cw,
				"h": 260.0 + 340.0 * _h(sd, 12.0), "seed": sd, "cave": _h(sd, 13.0) < 0.6, "cave_at": 0.25 + 0.5 * _h(sd, 14.0)})
	# the odd small rock anywhere keeps open ground from looking bare
	if _h(sd, 20.0) < 0.5 and abs(x + 90 - ex) > 12:
		out.append({"id": s * 16 + 12, "kind": "boulder", "x": x + 90 + int(_h(sd, 21.0) * 60.0), "lane": _h(sd, 22.0),
			"w": 36.0 + 50.0 * _h(sd, 23.0), "h": 0.0, "seed": sd + 9.9})


# Convenience for the sim: only trees (fruit sources), ordered by distance from `ex`.
static func trees_near(world_seed: int, ex: int, radius: int) -> Array:
	var out := []
	for f in in_range(world_seed, ex - radius, ex + radius, ex):
		if f["kind"] == "tree" and abs(f["x"] - ex) <= radius:
			out.append(f)
	out.sort_custom(_ByDist.new(ex), "less")
	return out


class _ByDist:
	var ex := 0

	func _init(e: int) -> void:
		ex = e

	func less(a, b) -> bool:
		return abs(a["x"] - ex) < abs(b["x"] - ex)
