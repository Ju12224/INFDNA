extends Reference
# Ruins (an underground module, see core/underground.gd): old life under the meadow.
#   nest  one or two abandoned ant nests per world, 60-240 columns from the colony's own: an old shaft plugged with rubble, a
#         gallery, side rooms (a larder, brood rooms) and a dusty queen chamber, partly caved in (loose spoil fills the low part of each
#         room and whole stretches of tunnel). When the Wild remembers past colonies (wild.gd) the nest was one of theirs: it is named
#         after the line and the view tints its relics in the line's colour. Breaking in finds an old larder (40-90 food) and, the first
#         time in a run, a trace of royal jelly in the queen chamber (+1 mutagen while the colony holds fewer than 3).
#   mole  wide round mole tunnels (3-4 cells high) running roughly level for 40-120 columns at mid depth, with crumbly walls and a
#         grass-lined nest chamber or two. Nothing walks them until the colony breaks in; then the nav fields see the whole tunnel
#         (the dig sets grid.nav_dirty): a ready-made highway.
#   worm  thin winding earthworm burrows in the humus and upper clay (some with a worm resting in them; see the view).
#   grub  small oval chambers, each with a curled beetle grub, eaten (food) the first time the colony breaks in.
# Every structure is a pure function of the world seed (grid._ih) and of the original ground (base_y), so the same ruins come out
# whether their columns are generated now or later. Pockets are open cells of the front plane; caved-in parts stay solid but turn to
# spoil (M_SPOIL), which digs fast. What the colony has found is kept on the sim (meta "ug_ruins"), so it lasts exactly one run.

const Wild = preload("res://mods-unpacked/Judah-InfDNA/core/wild.gd")

const OPEN = 1
const RUBBLE = 2
const MOLE_BLOCK = 230          # columns per mole-tunnel candidate
const WORM_BLOCK = 40           # columns per earthworm-burrow candidate
const GRUB_BLOCK = 56           # columns per grub-chamber candidate
const NEST_KEEP_X = 22          # the colony's nest area (wider than the contract's 20, so no wall of the queen chamber is thinned)
const NEST_KEEP_Y = 14
const TOP_GAP = 4               # rows of untouched ground under the surface (the contract asks for at least 3)
const DEFAULT_TINT = Color("#5b4636")


# ------------------------------------------------------------------ features
static func features(grid, xa: int, xb: int) -> Array:
	var out := []
	for f in nests(grid):
		if int(f["x1"]) >= xa and int(f["x0"]) <= xb:
			out.append(f)
	for b in range(int(floor(float(xa - 130) / MOLE_BLOCK)), int(floor(float(xb) / MOLE_BLOCK)) + 1):
		var m = _mole(grid, b)
		if not m.empty() and int(m["x1"]) >= xa and int(m["x0"]) <= xb:
			out.append(m)
	for b in range(int(floor(float(xa - 30) / WORM_BLOCK)), int(floor(float(xb + 30) / WORM_BLOCK)) + 1):
		var w = _worm(grid, b)
		if not w.empty() and int(w["x1"]) >= xa and int(w["x0"]) <= xb:
			out.append(w)
	for b in range(int(floor(float(xa) / GRUB_BLOCK)) - 1, int(floor(float(xb) / GRUB_BLOCK)) + 1):
		var gr = _grub(grid, b)
		if not gr.empty() and int(gr["x1"]) >= xa and int(gr["x0"]) <= xb:
			out.append(gr)
	return out


# The abandoned nests of this world (cached on the grid: they depend on nothing but the seed and the original ground).
static func nests(grid) -> Array:
	if grid.has_meta("ug_ruins_nests"):
		return grid.get_meta("ug_ruins_nests")
	var out := []
	var nx = int(grid._nest_x)
	var side = 1 if grid._ih(17, 3, 9001) < 0.5 else -1
	out.append(_make_nest(grid, 0, nx + side * (62 + int(grid._ih(17, 4, 9001) * 48.0))))
	if grid._ih(17, 5, 9001) < 0.6:
		out.append(_make_nest(grid, 1, nx - side * (140 + int(grid._ih(17, 6, 9001) * 100.0))))
	grid.set_meta("ug_ruins_nests", out)
	return out


# One old nest around column ax. Rooms are [cx, cy, rx, ry, fill, tilt, role]: an ellipse whose low part (below the fill line, which
# leans by `tilt`) has caved in. Segs are [ax, ay, bx, by, r, state]: tunnel pieces, open or rubble.
static func _make_nest(grid, idx: int, ax: int) -> Dictionary:
	var s = 9100 + idx * 31
	var nx = int(grid._nest_x)
	var dir = 1.0 if ax >= nx else -1.0              # the big wing points away from the colony's nest
	var sy = float(grid.base_y(ax))
	var gy = sy + 15.0 + floor(grid._ih(s, 2, 0) * 4.0)      # the gallery
	var qy = sy + 33.0 + floor(grid._ih(s, 3, 0) * 7.0)      # the queen chamber
	var rooms := []
	var segs := []
	# the old entrance shaft, caved in at the top
	var shaft := [Vector2(ax, sy + float(TOP_GAP) + 1.0)]
	var y = shaft[0].y
	var k = 0
	while y < gy - 0.1:
		y = min(gy, y + 3.0)
		k += 1
		shaft.append(Vector2(ax + round(sin(k * 1.3 + idx * 2.0) * 1.2), y))
	_path(segs, shaft, 1.3, 0, 2)
	var top = shaft[shaft.size() - 1]
	# the gallery away from the nest, to the larder
	var l1 = 15.0 + floor(grid._ih(s, 4, 0) * 7.0)
	var rxa = 4.6 + grid._ih(s, 5, 0) * 1.0
	var la = Vector2(ax + dir * l1, gy + 0.5)
	var cut = 1 if grid._ih(s, 6, 0) < 0.45 else -1
	_path(segs, _wind(grid, s + 1, top, la, 4, 0.8), 1.3, cut, cut + 1)
	rooms.append([la.x + dir * (rxa - 1.0), la.y, rxa, 2.4 + grid._ih(s, 7, 0) * 0.5, 0.3 + grid._ih(s, 8, 0) * 0.15, (grid._ih(s, 9, 0) - 0.5) * 0.8, "larder"])
	# a short gallery the other way, to a brood room that has mostly caved in
	var l2 = 8.0 + floor(grid._ih(s, 10, 0) * 5.0)
	var rxb = 4.0 + grid._ih(s, 11, 0) * 1.0
	var lb = Vector2(ax - dir * l2, gy + 3.0)
	_path(segs, _wind(grid, s + 2, top, lb, 3, 0.6), 1.25, -1, -1)
	rooms.append([lb.x - dir * (rxb - 1.0), lb.y, rxb, 2.3 + grid._ih(s, 12, 0) * 0.4, 0.5 + grid._ih(s, 13, 0) * 0.2, (grid._ih(s, 14, 0) - 0.5) * 1.0, "brood"])
	# down from the middle of the gallery to the queen chamber
	var rxq = 7.5 + grid._ih(s, 15, 0) * 1.5
	var ryq = 3.7 + grid._ih(s, 16, 0) * 0.6
	var mid = Vector2(ax + dir * round(l1 * 0.5), gy + 1.0)
	var qx = mid.x + dir * (6.0 + floor(grid._ih(s, 17, 0) * 5.0))
	_path(segs, _wind(grid, s + 3, mid, Vector2(qx - dir * 3.0, qy - ryq + 1.0), 5, 1.2), 1.3, -1, -1)
	rooms.append([qx, qy, rxq, ryq, 0.22 + grid._ih(s, 18, 0) * 0.1, (grid._ih(s, 19, 0) - 0.5) * 0.4, "queen"])
	# from the queen chamber back under the shaft to another brood room (a stretch of that tunnel has caved in)
	var rxc = 4.0 + grid._ih(s, 20, 0) * 1.0
	var lc = Vector2(qx - dir * (rxq + 9.0 + floor(grid._ih(s, 21, 0) * 5.0)), qy + 2.5)
	var cut2 = 1 if grid._ih(s, 22, 0) < 0.6 else -1
	_path(segs, _wind(grid, s + 4, Vector2(qx - dir * (rxq - 1.5), qy + 0.5), lc, 3, 0.7), 1.25, cut2, cut2 + 1)
	rooms.append([lc.x - dir * (rxc - 1.0), lc.y, rxc, 2.4 + grid._ih(s, 23, 0) * 0.4, 0.3 + grid._ih(s, 24, 0) * 0.2, (grid._ih(s, 25, 0) - 0.5) * 0.8, "brood"])
	# sometimes a deeper room beyond the queen, its tunnel half buried
	if grid._ih(s, 26, 0) < 0.55:
		var rxd = 3.8 + grid._ih(s, 27, 0) * 0.8
		var ld = Vector2(qx + dir * (rxq + 7.0 + floor(grid._ih(s, 28, 0) * 4.0)), qy + 6.0)
		var cut3 = 2 if grid._ih(s, 29, 0) < 0.5 else -1
		_path(segs, _wind(grid, s + 5, Vector2(qx + dir * (rxq - 1.5), qy + 1.0), ld, 3, 0.6), 1.25, cut3, cut3 + 1)
		rooms.append([ld.x + dir * (rxd - 1.0), ld.y, rxd, 2.3 + grid._ih(s, 30, 0) * 0.3, 0.35 + grid._ih(s, 31, 0) * 0.2, (grid._ih(s, 32, 0) - 0.5) * 0.8, "brood"])
	var bx0 = 1e9
	var bx1 = -1e9
	var by0 = 1e9
	var by1 = -1e9
	for r in rooms:
		bx0 = min(bx0, r[0] - r[2])
		bx1 = max(bx1, r[0] + r[2])
		by0 = min(by0, r[1] - r[3])
		by1 = max(by1, r[1] + r[3])
	for sg in segs:
		bx0 = min(bx0, min(sg[0], sg[2]) - sg[4])
		bx1 = max(bx1, max(sg[0], sg[2]) + sg[4])
		by0 = min(by0, min(sg[1], sg[3]) - sg[4])
		by1 = max(by1, max(sg[1], sg[3]) + sg[4])
	return {"kind": "nest", "id": "nest:%d" % idx, "idx": idx, "x0": int(floor(bx0)) - 1, "x1": int(ceil(bx1)) + 1,
		"y0": int(floor(by0)) - 1, "y1": int(min(ceil(by1) + 1, grid.H - 4)), "y": int(qy), "dir": dir, "rooms": rooms, "segs": segs,
		"pick": grid._ih(s, 40, 0), "food": 40 + int(grid._ih(s, 41, 0) * 51.0)}


# Points from a to b in n steps, bowing to the side a little (a hand-dug tunnel never runs straight).
static func _wind(grid, s: int, a: Vector2, b: Vector2, n: int, amp: float) -> Array:
	var pts := [a]
	var d = b - a
	var nrm = Vector2(-d.y, d.x).normalized()
	var ph = grid._ih(s, 50, 0) * TAU
	for i in range(1, n):
		var t = float(i) / n
		pts.append(a + d * t + nrm * (sin(t * PI) * amp * (1.0 if grid._ih(s, 51, 0) < 0.5 else -1.0) + sin(t * 9.0 + ph) * 0.5))
	pts.append(b)
	return pts


# Tunnel pieces along pts; pieces lo..hi-1 have caved in.
static func _path(segs: Array, pts: Array, r: float, lo: int, hi: int) -> void:
	for i in range(pts.size() - 1):
		segs.append([pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y, r, RUBBLE if (i >= lo and i < hi) else OPEN])


# A mole tunnel for block b ({} when there is none).
static func _mole(grid, b: int) -> Dictionary:
	if grid._ih(b, 11, 7001) > 0.55:
		return {}
	var n = 40 + int(grid._ih(b, 13, 7001) * 81.0)
	var ax = b * MOLE_BLOCK + int(grid._ih(b, 12, 7001) * float(MOLE_BLOCK - n - 6))
	var bx = ax + n
	var d = 21.0 + grid._ih(b, 14, 7001) * 20.0
	var ya = float(grid.base_y(ax)) + d
	var yb = float(grid.base_y(bx)) + d + (grid._ih(b, 15, 7001) - 0.5) * 8.0
	var nx = int(grid._nest_x)
	if bx > nx - NEST_KEEP_X - 8 and ax < nx + NEST_KEEP_X + 8:
		# never through the colony's nest: under it
		ya = max(ya, grid._nest_y + NEST_KEEP_Y + 6)
		yb = max(yb, grid._nest_y + NEST_KEEP_Y + 6)
	var f = {"kind": "mole", "id": "mole:%d" % b, "ax": float(ax), "bx": float(bx), "ya": ya, "yb": yb, "len": n,
		"ph": grid._ih(b, 16, 7001) * TAU, "r": 1.75 + grid._ih(b, 17, 7001) * 0.25, "blobs": []}
	for i in 1 + int(grid._ih(b, 18, 7001) < 0.45):
		var cx = ax + n * (0.22 + 0.56 * grid._ih(b, 20 + i, 7001))
		f["blobs"].append([cx, mole_y(f, cx) + 0.4, 3.6 + grid._ih(b, 22 + i, 7001) * 1.0, 2.7 + grid._ih(b, 24 + i, 7001) * 0.5])
	var y0 = 1e9
	var y1 = -1e9
	for i in range(0, n + 1, 4):
		var cy = mole_y(f, ax + i)
		y0 = min(y0, cy)
		y1 = max(y1, cy)
	y0 = min(y0, mole_y(f, bx))
	y1 = max(y1, mole_y(f, bx))
	f["x0"] = ax - 3
	f["x1"] = bx + 3
	f["y0"] = int(floor(y0 - 4.0))
	f["y1"] = int(ceil(y1 + 4.0))
	f["y"] = int(ya)
	for r in nests(grid):
		if f["x1"] + 4 >= r["x0"] and f["x0"] - 4 <= r["x1"] and f["y1"] + 4 >= r["y0"] and f["y0"] - 4 <= r["y1"]:
			return {}
	return f


# Centre row of a mole tunnel at column x (float cells): level between its ends, with a slow wander.
static func mole_y(f: Dictionary, x: float) -> float:
	var t = clamp((x - f["ax"]) / max(1.0, f["bx"] - f["ax"]), 0.0, 1.0)
	return lerp(f["ya"], f["yb"], t) + 1.6 * sin(t * f["len"] / 22.0 + f["ph"]) + 0.7 * sin(t * f["len"] / 8.0 + f["ph"] * 2.3)


# An earthworm burrow for block b: a winding walk kept in the top rows of the soil.
static func _worm(grid, b: int) -> Dictionary:
	if grid._ih(b, 21, 8001) > 0.5:
		return {}
	var x = b * WORM_BLOCK + grid._ih(b, 22, 8001) * WORM_BLOCK
	var y = float(grid.base_y(int(x))) + 6.0 + grid._ih(b, 23, 8001) * 9.0
	var hd = (grid._ih(b, 24, 8001) - 0.5) * 1.8 + (PI if grid._ih(b, 25, 8001) < 0.5 else 0.0)
	var n = 30 + int(grid._ih(b, 26, 8001) * 40.0)
	var pts := PoolVector2Array([Vector2(x, y)])
	var x0 = x
	var x1 = x
	var y0 = y
	var y1 = y
	for i in n:
		hd += (grid._ih(b, 100 + i, 8002) - 0.5) * 0.9
		var p = pts[pts.size() - 1] + Vector2(cos(hd), sin(hd)) * 0.7
		var by = float(grid.base_y(int(floor(p.x))))
		if p.y < by + TOP_GAP + 1.2:
			p.y = by + TOP_GAP + 1.2
			hd = clamp(abs(atan2(sin(hd), cos(hd))), 0.3, PI - 0.3)       # mirrored to head back down
		elif p.y > by + 20.0:
			p.y = by + 20.0
			hd = -clamp(abs(atan2(sin(hd), cos(hd))), 0.3, PI - 0.3)
		pts.append(p)
		x0 = min(x0, p.x)
		x1 = max(x1, p.x)
		y0 = min(y0, p.y)
		y1 = max(y1, p.y)
	var f = {"kind": "worm", "id": "worm:%d" % b, "pts": pts, "x0": int(floor(x0)) - 1, "x1": int(ceil(x1)) + 1, "y0": int(floor(y0)) - 1,
		"y1": int(ceil(y1)) + 1, "y": int(y)}
	if grid._ih(b, 27, 8001) < 0.4:
		f["rest"] = int(grid._ih(b, 28, 8001) * max(1, pts.size() - 14))      # a worm lies in it from this point on
	return f


# A beetle grub's chamber for block b.
static func _grub(grid, b: int) -> Dictionary:
	if grid._ih(b, 31, 8501) > 0.34:
		return {}
	var cx = b * GRUB_BLOCK + 6.0 + grid._ih(b, 32, 8501) * (GRUB_BLOCK - 12.0)
	var cy = float(grid.base_y(int(cx))) + 9.0 + grid._ih(b, 33, 8501) * 19.0
	var rx = 3.8 + grid._ih(b, 34, 8501) * 1.1
	var ry = 2.7 + grid._ih(b, 35, 8501) * 0.5
	if abs(cx - grid._nest_x) < NEST_KEEP_X + rx + 2.0 and cy - ry < grid._nest_y + NEST_KEEP_Y + 2:
		return {}
	var f = {"kind": "grub", "id": "grub:%d" % b, "cx": cx, "cy": cy, "rx": rx, "ry": ry, "x0": int(floor(cx - rx)) - 1,
		"x1": int(ceil(cx + rx)) + 1, "y0": int(floor(cy - ry)) - 1, "y1": int(ceil(cy + ry)) + 1, "y": int(cy),
		"food": 14 + int(grid._ih(b, 36, 8501) * 12.0), "face": 1.0 if grid._ih(b, 37, 8501) < 0.5 else -1.0, "rot": (grid._ih(b, 38, 8501) - 0.5) * 0.6}
	# a stone in the way, a ruin or a mole tunnel: no grub here
	for st in grid.stones_in(f["x0"], f["x1"]):
		if abs(st[0] - cx) < rx + st[2] and abs(st[1] - cy) < ry + st[3]:
			return {}
	for r in nests(grid):
		if f["x1"] + 3 >= r["x0"] and f["x0"] - 3 <= r["x1"] and f["y1"] + 3 >= r["y0"] and f["y0"] - 3 <= r["y1"]:
			return {}
	for mb in range(int(floor(float(f["x0"] - 130) / MOLE_BLOCK)), int(floor(float(f["x1"]) / MOLE_BLOCK)) + 1):
		var m = _mole(grid, mb)
		if not m.empty() and f["x1"] + 2 >= m["x0"] and f["x0"] - 2 <= m["x1"] and f["y1"] + 2 >= m["y0"] and f["y0"] - 2 <= m["y1"]:
			return {}
	return f


# ------------------------------------------------------------------ cells
# What the structure makes of cell (x, y): 0 nothing, OPEN a pocket, RUBBLE caved-in ground (solid spoil). Includes the stamping rules
# that do not change during a run (the rows under the original ground, the bottom rows, the colony's nest area).
static func cell_kind(grid, f: Dictionary, x: int, y: int) -> int:
	if x < int(f["x0"]) or x > int(f["x1"]) or y < int(f["y0"]) or y > int(f["y1"]) or not _clip_ok(grid, x, y):
		return 0
	match str(f["kind"]):
		"nest":
			return _nest_cell(grid, f, x, y)
		"mole":
			return _mole_cell(grid, f, x, y)
		"worm":
			return _worm_cell(f, x, y)
		"grub":
			var dx = (x + 0.5 - f["cx"]) / f["rx"]
			var dy = (y + 0.5 - f["cy"]) / f["ry"]
			return OPEN if dx * dx + dy * dy <= 1.0 + (grid._ih(x, y, 8601) - 0.5) * 0.2 else 0
	return 0


static func _clip_ok(grid, x: int, y: int) -> bool:
	if y < grid.base_y(x) + TOP_GAP or y >= grid.H - 4:
		return false
	return not (abs(x - grid._nest_x) < NEST_KEEP_X and y < grid._nest_y + NEST_KEEP_Y)


static func _nest_cell(grid, f: Dictionary, x: int, y: int) -> int:
	var px = x + 0.5
	var py = y + 0.5
	var crumb = (grid._ih(x, y, 9201) - 0.5) * 0.3
	var res := 0
	for r in f["rooms"]:
		if abs(px - r[0]) > r[2] + 0.6 or abs(py - r[1]) > r[3] + 0.6:
			continue
		var dx = (px - r[0]) / r[2]
		var dy = (py - r[1]) / r[3]
		if dx * dx + dy * dy <= 1.0 + crumb:
			if py < fill_y(r, px) + crumb:
				return OPEN
			res = RUBBLE
	for sg in f["segs"]:
		var rr = sg[4] + crumb
		if px < min(sg[0], sg[2]) - rr or px > max(sg[0], sg[2]) + rr or py < min(sg[1], sg[3]) - rr or py > max(sg[1], sg[3]) + rr:
			continue
		var a = Vector2(sg[0], sg[1])
		var ab = Vector2(sg[2], sg[3]) - a
		var t = clamp((Vector2(px, py) - a).dot(ab) / max(0.0001, ab.length_squared()), 0.0, 1.0)
		if (a + ab * t).distance_to(Vector2(px, py)) <= rr:
			if int(sg[5]) == OPEN:
				return OPEN
			res = RUBBLE
	return res


# The top of a room's caved-in floor at column px (float cells).
static func fill_y(r: Array, px: float) -> float:
	return r[1] + r[3] - 2.0 * r[3] * r[4] + r[5] * r[3] * clamp((px - r[0]) / r[2], -1.0, 1.0)


static func _mole_cell(grid, f: Dictionary, x: int, y: int) -> int:
	var px = x + 0.5
	var py = y + 0.5
	var crumb = (grid._ih(x, y, 7101) - 0.5) * 0.9
	for bl in f["blobs"]:
		var dx = (px - bl[0]) / bl[2]
		var dy = (py - bl[1]) / bl[3]
		if dx * dx + dy * dy <= 1.0 + crumb * 0.3:
			return OPEN
	var cy = mole_y(f, clamp(px, f["ax"], f["bx"]))
	var r = f["r"] + 0.22 * sin(px * 0.41 + f["ph"])
	var dy2 = py - cy
	var e = min(px - f["ax"], f["bx"] - px)
	var dist = abs(dy2) if e >= 0.0 else sqrt(e * e + dy2 * dy2)      # round ends
	return OPEN if dist <= r + crumb else 0


static func _worm_cell(f: Dictionary, x: int, y: int) -> int:
	var p = Vector2(x + 0.5, y + 0.5)
	var pts: PoolVector2Array = f["pts"]
	for i in pts.size():
		if pts[i].distance_squared_to(p) <= 0.6:
			return OPEN
	return 0


# The cells of an earthworm burrow (Vector2 keys), straight from its points.
static func _worm_cells(f: Dictionary) -> Dictionary:
	var out := {}
	var pts: PoolVector2Array = f["pts"]
	for p in pts:
		for cy in range(int(floor(p.y - 1.0)), int(floor(p.y + 1.0)) + 1):
			for cx in range(int(floor(p.x - 1.0)), int(floor(p.x + 1.0)) + 1):
				if Vector2(cx + 0.5, cy + 0.5).distance_squared_to(p) <= 0.6:
					out[Vector2(cx, cy)] = true
	return out


# ------------------------------------------------------------------ stamp
static func stamp(grid, f: Dictionary, xa: int, xb: int) -> void:
	var lo = max(max(xa, int(f["x0"])), grid.ox)
	var hi = min(min(xb, int(f["x1"])), grid.ox + grid.W - 1)
	if lo > hi:
		return
	var opens := PoolIntArray()
	var rubble := PoolIntArray()
	var sol = grid.solid
	var mat = grid.mat
	var W = grid.W
	var is_worm = str(f["kind"]) == "worm"
	var worm = _worm_cells(f) if is_worm else {}       # a thin tube: walk its points instead of testing every cell of its box against all of them
	for x in range(lo, hi + 1):
		var top = max(grid.surf_y(x), grid.base_y(x)) + TOP_GAP
		for y in range(max(int(f["y0"]), top), min(int(f["y1"]), grid.H - 4) + 1):
			var k = 0
			if is_worm:
				if worm.has(Vector2(x, y)) and _clip_ok(grid, x, y):
					k = OPEN
			else:
				k = cell_kind(grid, f, x, y)
			if k == 0:
				continue
			var j = y * W + (x - grid.ox)
			if sol[j] == 0:
				continue                    # already open (another structure's pocket)
			var m = mat[j]
			if m == grid.M_STONE or m == grid.M_FOSSIL or m == grid.M_BED:
				continue                    # stones and bedrock stay where they are
			if k == OPEN:
				opens.append(j)
			else:
				rubble.append(j)
	if opens.size() > 0:
		for j in opens:
			sol[j] = 0
		grid.solid = sol
	if rubble.size() > 0:
		for j in rubble:
			mat[j] = grid.M_SPOIL
		grid.mat = mat


# ------------------------------------------------------------------ the colony breaks in
static func on_carve(sim, x: int, y: int, z: int, f: Dictionary) -> void:
	var kind = str(f["kind"])
	if z != 0 or kind == "worm":
		return
	var st = _state(sim)
	var id = str(f["id"])
	if st["done"].has(id):
		return
	var g = sim.grid
	if not _broke_in(g, f, x, y):
		return
	st["done"][id] = sim.time
	var pos = g.center(x, y)
	match kind:
		"nest":
			var amt = float(f["food"])
			sim.food += amt
			sim.ledger["other_in"] += amt
			var extra = ""
			if not st["mut"] and sim.mutagen < 3:
				st["mut"] = true
				sim.mutagen += 1
				extra = " A trace of royal jelly in the dusty queen chamber: +1 mutagen."
			var line = ruin_line(sim, f)
			var txt = ""
			if line.empty():
				txt = "Your diggers broke into an abandoned ant nest, long empty. An old larder: +%d food.%s" % [int(amt), extra]
			else:
				txt = "Your diggers broke into %s (colony #%d), long empty. An old larder: +%d food.%s" % [ruin_name(sim, f), int(line.get("id", 0)), int(amt), extra]
			sim.toasts.append({"text": txt, "t": 9.0})
			sim.banner = "Ruins: %s" % ruin_name(sim, f)
			sim.banner_t = 3.5
			sim.fx.append({"kind": "ring", "pos": pos, "t": 0.0, "color": Color("#ffd86b")})
			sim.fx.append({"kind": "text", "pos": pos + Vector2(0, -26), "t": 0.0, "text": "+%d" % int(amt), "color": Color("#ffd86b")})
			sim._sfx("repelled")
		"mole":
			sim.toasts.append({"text": "Your diggers broke into an old mole tunnel: %d cells of ready-made highway." % int(f["len"]), "t": 6.0})
			sim.fx.append({"kind": "text", "pos": pos + Vector2(0, -26), "t": 0.0, "text": "MOLE TUNNEL", "color": Color("#c9a37a")})
		"grub":
			var amt2 = float(f["food"])
			sim.food += amt2
			sim.ledger["other_in"] += amt2
			sim.toasts.append({"text": "A beetle grub curled up in its chamber: +%d food." % int(amt2), "t": 5.0})
			sim.fx.append({"kind": "text", "pos": g.center(int(f["cx"]), int(f["cy"])) + Vector2(0, -20), "t": 0.0, "text": "+%d" % int(amt2), "color": Color("#ffd86b")})


# Did the dig at (x, y) open the way into the structure? A pocket cell close by that now touches ground the colony dug (an open cell
# that is not the structure's), or caved-in ground of the structure dug out.
static func _broke_in(g, f: Dictionary, x: int, y: int) -> bool:
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if dx * dx + dy * dy > 10:
				continue
			var cx = x + dx
			var cy = y + dy
			if not g.inb(cx, cy) or g.is_solid(cx, cy, 0):
				continue
			var k = cell_kind(g, f, cx, cy)
			if k == RUBBLE:
				return true
			if k != OPEN:
				continue
			for d in g.N8:
				var nx = cx + int(d.x)
				var ny = cy + int(d.y)
				if g.is_under(nx, ny) and not g.is_solid(nx, ny, 0) and cell_kind(g, f, nx, ny) == 0:
					return true
	return false


# ------------------------------------------------------------------ run state, names
static func _state(sim) -> Dictionary:
	if sim.has_meta("ug_ruins"):
		return sim.get_meta("ug_ruins")
	var st = {"done": {}, "mut": false, "lines": null}
	sim.set_meta("ug_ruins", st)
	return st


# Has the colony broken into this structure (this run)?
static func is_found(sim, f: Dictionary) -> bool:
	return _state(sim)["done"].has(str(f["id"]))


# The Wild's lines (read once per run). The rival's own line comes last: it still lives on the meadow.
static func _lines(sim) -> Array:
	var st = _state(sim)
	if st["lines"] == null:
		var out := []
		var kin_line = null
		if Wild.is_on():
			for r in Wild.lines():
				if not (r is Dictionary) or not r.has("title"):
					continue
				if not sim.kin.empty() and int(r.get("id", -1)) == int(sim.kin.get("id", -2)):
					kin_line = r
				else:
					out.append(r)
		if out.empty() and kin_line != null:
			out.append(kin_line)
		st["lines"] = out
	return st["lines"]


# The past colony whose nest this was ({} when the Wild has no lines, or for anything but a nest).
static func ruin_line(sim, f: Dictionary) -> Dictionary:
	if str(f.get("kind", "")) != "nest":
		return {}
	var ls = _lines(sim)
	if ls.empty():
		return {}
	return ls[(int(f["pick"] * ls.size()) + int(f["idx"])) % ls.size()]


static func ruin_name(sim, f: Dictionary) -> String:
	var line = ruin_line(sim, f)
	if line.empty():
		return "an abandoned nest"
	return "the old nest of the %s" % str(line.get("title", "Wild"))


# The colour of the line that built the nest (relics are tinted with it).
static func ruin_tint(sim, f: Dictionary) -> Color:
	var line = ruin_line(sim, f)
	var gd = line.get("genome", {})
	if not (gd is Dictionary) or not gd.has("color"):
		return DEFAULT_TINT
	return Color("#" + str(gd["color"]).trim_prefix("#"))


# A cell to look at (tests and the screenshot harness): the queen chamber, the tunnel's middle, the grub.
static func focus(grid, f: Dictionary) -> Vector2:
	match str(f["kind"]):
		"nest":
			for r in f["rooms"]:
				if r[6] == "queen":
					return Vector2(r[0], r[1])
		"mole":
			var mx = (f["ax"] + f["bx"]) * 0.5
			return Vector2(mx, mole_y(f, mx))
		"worm":
			var pts: PoolVector2Array = f["pts"]
			return pts[pts.size() / 2]
		"grub":
			return Vector2(f["cx"], f["cy"])
	return Vector2((f["x0"] + f["x1"]) * 0.5, (f["y0"] + f["y1"]) * 0.5)
