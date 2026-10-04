extends RefCounted
# Side-view ant-farm world, infinite in both directions along x.
#
# Layers of data:
#  - the surface PROFILE (one int per column) is generated lazily outward from the
#    original playfield and is cheap, so the view can draw terrain anywhere. On top of
#    it sits the MOUND: real dirt the diggers carried up (see deposit()).
#  - the SIM arrays only cover the columns things actually reach. They grow in CHUNK
#    steps when ants or raiders get near an edge.
#  - two tunnel PLANES: 0 = front (the cut face the camera looks at, surface, shafts),
#    1 = back (a second layer of tunnels behind it). A back tunnel can run behind a
#    front one without touching it; the two planes only connect through HOLES (link).
#  - MATERIAL per cell: strata (humus, clay, sand, red clay, bedrock), stones and
#    fossils. Material sets how fast a cell digs; bedrock, stones and fossils do not dig.
# All public functions take WORLD coordinates (x can be negative) and a plane z (0/1).
# Internally cells are indexed z * WH + y * W + (x - ox).
#
# Footing: an ant may stand only on an open cell that touches solid ground in its own
# plane (floor, wall or ceiling), or on the ground-level rim across a shaft mouth.
# The back plane exists only underground.

const UG = preload("res://core/underground.gd")
const CELL = 6.0
const CHUNK = 64          # render + growth step (columns)
const PAD = 2             # render padding so chunk seams filter cleanly
const MARGIN = 24         # keep this many sim columns beyond any unit
const INIT_L = -448       # first sim range (chunk aligned). v0.22: wide enough for foragers ranging
const INIT_R = 704        # ~520 cells either side of the nest, so nothing grows mid-game
const PLANES = 2

# materials (index into DIG_RATE / MAT_NAMES)
const M_HUMUS = 0
const M_CLAY = 1
const M_SAND = 2
const M_RED = 3
const M_BED = 4
const M_STONE = 5
const M_FOSSIL = 6
const M_SPOIL = 7
const M_LIME = 8
const M_SHALE = 9
const MAT_NAMES = ["humus", "clay", "sand", "red clay", "bedrock", "stone", "fossil", "spoil", "limestone", "shale"]
const DIG_RATE = [1.15, 0.8, 1.5, 0.65, 0.0, 0.0, 0.0, 1.6, 0.5, 0.38]
# stratum seams (rows below the original surface, before the per-column wave)
const SEAMS = [10.0, 31.2, 56.5, 86.0, 122.0, 158.0]   # humus|clay|sand|red|limestone|shale|bedrock
const SB = 10             # stone placement block (cells)
const SKY_LIMIT = 12      # the mound never grows above this row

var W: int                # sim columns
var H: int
var WH: int
var ox := 0               # world x of sim column 0
var arena_l := 0          # the v0.9 playfield: food, raids and trees stay inside it
var arena_r := 259
var solid := PackedByteArray()    # PLANES * WH
var walk := PackedByteArray()     # PLANES * WH
var under := PackedByteArray()    # WH: ground (original soil or mound), same for both planes
var mat := PackedByteArray()      # WH
var link := PackedByteArray()     # WH: 1 = hole between the planes at this cell
var pher := PackedFloat32Array()     # surface food trail, one value per sim column
var pher_lo := 1 << 30          # world x range that may hold a nonzero trail value
var pher_hi := -(1 << 30)
var entrance := Vector2()       # surface cell above the main shaft
var entrances: Array = []       # all shaft mouths (main first)
var chamber := Vector2()        # queen chamber center
var chamber_r := Vector2(9, 4.5)
var open_under := 0             # dug cells, both planes (colony living space)
var dug_by_mat := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
var mound_cells := 0            # spoil grains that landed on the surface
var spoil_lost := 0             # grains that rolled away or fell back into a mouth
var chimneys := {}              # mouth column -> true (the mound keeps a hole there)

var dist_home := PackedInt32Array()
var dist_exit := PackedInt32Array()
var nav_dirty := true
var layout := 0                 # bumps whenever the sim arrays are reallocated
var dirty_chunks := {}          # chunk index -> true: the view must refetch chunk_images()
var surf_dirty := {}            # column -> true: the surface height changed (the view rebuilds its cached ground meshes)

var _noise: FastNoiseLite
var _big: FastNoiseLite
var _wave: FastNoiseLite     # strata seam wave (shared with the shader via surf image)
var _seed := 0
var _base := 45
var _prof_r := PackedInt32Array()   # base surface y for x = 0, 1, 2 ...
var _prof_l := PackedInt32Array()   # base surface y for x = -1, -2, ...
var _mound := {}                # x -> rows of spoil piled on the base surface
var _grain_acc := 0.0
var _chunk_img := {}            # k -> [front, aux] images of chunks that overlap the sim range
var _neg := PackedInt32Array()      # all -1, PLANES * WH: copied (COW) as a BFS start
var _air_col: Image
var _nest_x := 130
var _nest_y := 70
var _block_cache := {}
var _smap = null                # stone cells of the chunk being built (outside the sim range)
var ug = null                   # core/underground.gd registry: this world's underground structures

const N8 = [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(-1, 0),
	Vector2(1, 0), Vector2(-1, 1), Vector2(0, 1), Vector2(1, 1)]


func _init(w: int, h: int, seed_value: int) -> void:
	H = h
	_seed = seed_value
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.fractal_octaves = 3
	_noise.frequency = 1.0 / 70.0
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_big = FastNoiseLite.new()
	_big.seed = seed_value + 17
	_big.fractal_octaves = 2
	_big.frequency = 1.0 / 420.0
	_big.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_wave = FastNoiseLite.new()
	_wave.seed = seed_value + 31
	_wave.fractal_octaves = 2
	_wave.frequency = 1.0 / 26.0
	_wave.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_base = int(H * 0.30)
	arena_l = 0
	arena_r = w - 1

	# the original playfield, generated exactly like v0.9 so balance stays comparable
	var ex = w / 2
	var s0 := []
	var prev = _base
	for x in w:
		var hgt = _base + int(_noise.get_noise_1d(float(x)) * 14.0)
		if x > 0:
			hgt = int(clamp(hgt, prev - 1, prev + 1))
		s0.append(hgt)
		prev = hgt
	for x in range(ex - 7, ex + 8):
		s0[x] = s0[ex]
	for x in range(ex + 8, w):
		s0[x] = int(clamp(s0[x], s0[x - 1] - 1, s0[x - 1] + 1))
	for x in range(ex - 8, -1, -1):
		s0[x] = int(clamp(s0[x], s0[x + 1] - 1, s0[x + 1] + 1))
	for v in s0:
		_prof_r.append(v)

	_air_col = Image.create_empty(1, H, false, Image.FORMAT_RGBA8)
	_air_col.fill(Color(0, 0, 0, 1))

	_nest_x = ex
	_nest_y = surf_y(ex) + 26
	ox = INIT_L
	W = INIT_R - INIT_L
	_alloc_fresh()

	entrance = Vector2(ex, surf_y(ex) - 1)
	entrances = [entrance]
	chimneys[ex] = true
	chamber = Vector2(ex, surf_y(ex) + 26)
	var sy = surf_y(ex)
	for y in range(sy, int(chamber.y)):
		var wig = 0 if y < sy + 5 else int(round(sin(y * 0.35) * 2.0))
		_carve_raw(ex + wig, y, 1.2 if y < sy + 2 else 1.7, true, 0, true)
	for y in range(int(chamber.y - chamber_r.y) - 1, int(chamber.y + chamber_r.y) + 2):
		for x in range(int(chamber.x - chamber_r.x) - 1, int(chamber.x + chamber_r.x) + 2):
			var dx = (x - chamber.x) / chamber_r.x
			var dy = (y - chamber.y) / chamber_r.y
			if dx * dx + dy * dy <= 1.0:
				_open(x, y, 0, true)
	_refresh_walk(ox, 0, ox + W - 1, H - 1)
	dirty_chunks.clear()
	_chunk_img.clear()
	rebuild_nav()


# ---------- surface profile (infinite) ----------
# Beyond the playfield the land drifts into bigger hills and valleys.
func _gen_h(x: int, prev: int) -> int:
	var d = 0.0
	if x < arena_l:
		d = arena_l - x
	elif x > arena_r:
		d = x - arena_r
	var ramp = clamp(d / 160.0, 0.0, 1.0)
	var hgt = _base + int(_noise.get_noise_1d(float(x)) * 14.0 + _big.get_noise_1d(float(x)) * 30.0 * ramp)
	hgt = int(clamp(hgt, 18, H - 60))
	return int(clamp(hgt, prev - 1, prev + 1))


# Original ground (no mound). Strata are measured from here.
func base_y(x: int) -> int:
	if x >= 0:
		while _prof_r.size() <= x:
			_prof_r.append(_gen_h(_prof_r.size(), _prof_r[_prof_r.size() - 1]))
		return _prof_r[x]
	var i = -x - 1
	while _prof_l.size() <= i:
		var last = _prof_l[_prof_l.size() - 1] if _prof_l.size() > 0 else _prof_r[0]
		_prof_l.append(_gen_h(-_prof_l.size() - 1, last))
	return _prof_l[i]


# Top of the ground, mound included.
func surf_y(x: int) -> int:
	if _mound.is_empty():
		return base_y(x)
	return base_y(x) - _mound.get(x, 0)


# Tilt (radians, + = downhill to the right) of the open ground at column x, averaged over a few cells so
# the 6 px steps of the height map do not make a walker rock back and forth.
func surface_tilt(x: int) -> float:
	var dy = float(surf_y(x + 4) - surf_y(x - 4))
	return clamp(atan2(dy, 8.0), -0.9, 0.9)


func mound_h(x: int) -> int:
	return _mound.get(x, 0)


func _set_surf(x: int, v: int) -> void:
	base_y(x)
	surf_dirty[x] = true
	if x >= 0:
		_prof_r[x] = v
	else:
		_prof_l[-x - 1] = v


# Strata wave: the seams rise and fall along x. Shared with the shader (surf image B).
func strata_off(x: int) -> float:
	return _wave.get_noise_1d(float(x)) * 7.0


func strata_at(x: int, y: int) -> int:
	var d = y - base_y(x) + strata_off(x)
	if d < SEAMS[0]:
		return M_HUMUS
	if d < SEAMS[1]:
		return M_CLAY
	if d < SEAMS[2]:
		return M_SAND
	if d < SEAMS[3]:
		return M_RED
	if d < SEAMS[4]:
		return M_LIME
	if d < SEAMS[5]:
		return M_SHALE
	return M_BED


# ---------- stones and fossils ----------
# One candidate per SB x SB block, from an integer hash of the block, so any column of
# the infinite world gets the same rocks whether it is simulated or only drawn.
func _ih(a: int, b: int, c: int) -> float:
	var h = (a * 374761393 + b * 668265263 + c * 1274126177 + _seed * 97) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / 16777216.0


# [cx, cy, rx, ry, kind] or [] for block (bx, by).
func _block_stone(bx: int, by: int) -> Array:
	var key = bx * 4096 + by
	if _block_cache.has(key):
		return _block_cache[key]
	var out := []
	var cx = bx * SB + 1.5 + _ih(bx, by, 1) * (SB - 3)
	var cy = by * SB + 1.5 + _ih(bx, by, 2) * (SB - 3)
	var ix = int(cx)
	var d = cy - base_y(ix) + strata_off(ix)
	var near_nest = abs(cx - _nest_x) < 17 and cy < _nest_y + 9
	if d > 5.0 and cy < H - 6 and not near_nest:
		var p = 0.0
		var kind = M_STONE
		if d < SEAMS[0]:
			p = 0.05
		elif d < SEAMS[1]:
			p = 0.12
		elif d < SEAMS[2]:
			p = 0.26
		elif d < SEAMS[3]:
			p = 0.14
			if _ih(bx, by, 5) < 0.2:
				kind = M_FOSSIL
				p = 1.0
		elif d < SEAMS[4]:
			p = 0.12   # limestone: ammonites
			if _ih(bx, by, 5) < 0.3:
				kind = M_FOSSIL
				p = 1.0
		elif d < SEAMS[5]:
			p = 0.2
		if _ih(bx, by, 3) < p:
			if kind == M_FOSSIL:
				var r = 1.4 + _ih(bx, by, 4) * 0.8
				out = [cx, cy, r, r, kind]
			else:
				var big = _ih(bx, by, 4)
				out = [cx, cy, 1.4 + big * 2.2, 1.1 + big * 1.4 + _ih(bx, by, 6) * 0.6, kind]
	if _block_cache.size() > 20000:
		_block_cache.clear()
	_block_cache[key] = out
	return out


# Stones overlapping columns xa..xb.
func stones_in(xa: int, xb: int) -> Array:
	var out := []
	for bx in range(int(floor(float(xa - 5) / SB)), int(floor(float(xb + 5) / SB)) + 1):
		for by in range(0, int(H / SB) + 1):
			var s = _block_stone(bx, by)
			if not s.is_empty():
				out.append(s)
	return out


func _stamp_stones(xa: int, xb: int) -> void:
	for s in stones_in(xa, xb):
		for y in range(int(s[1] - s[3]) - 1, int(s[1] + s[3]) + 2):
			for x in range(int(s[0] - s[2]) - 1, int(s[0] + s[2]) + 2):
				if x < xa or x > xb or not inb(x, y):
					continue
				var dx = (x + 0.5 - s[0]) / s[2]
				var dy = (y + 0.5 - s[1]) / s[3]
				if dx * dx + dy * dy <= 1.0:
					var j = y * W + (x - ox)
					if solid[j] == 1 and solid[WH + j] == 1:
						mat[j] = s[4]


# Underground structures (core/underground.gd: roots, caverns, buried things, veins, ruins) written into new sim columns.
func _stamp_features(xa: int, xb: int) -> void:
	if ug == null:
		ug = UG.make()
	ug.stamp_range(self, xa, xb)


# Material anywhere (outside the sim range it is computed from the generators).
func mat_at(x: int, y: int) -> int:
	if inb(x, y):
		return mat[y * W + (x - ox)]
	if y < surf_y(x):
		return M_HUMUS
	if y < base_y(x) + 4:
		return strata_at(x, y)
	if _smap != null:
		return _smap.get(x * 1024 + y, strata_at(x, y))
	for s in stones_in(x, x):
		var dx = (x + 0.5 - s[0]) / s[2]
		var dy = (y + 0.5 - s[1]) / s[3]
		if dx * dx + dy * dy <= 1.0:
			return s[4]
	return strata_at(x, y)


func dig_rate(x: int, y: int) -> float:
	return DIG_RATE[mat_at(x, y)]


# ---------- sim range ----------
func sim_l() -> int:
	return ox


func sim_r() -> int:
	return ox + W - 1


func _alloc_fresh() -> void:
	WH = W * H
	solid.resize(PLANES * WH)
	walk.resize(PLANES * WH)
	under.resize(WH)
	mat.resize(WH)
	link.resize(WH)
	for x in range(ox, ox + W):
		var s = surf_y(x)
		var c = x - ox
		for y in H:
			var u = 1 if y >= s else 0
			var j = y * W + c
			solid[j] = u
			solid[WH + j] = u
			under[j] = u
			walk[j] = 0
			walk[WH + j] = 0
			link[j] = 0
			mat[j] = strata_at(x, y) if u == 1 else M_HUMUS
	pher.resize(W)
	for i in W:
		pher[i] = 0.0
	_stamp_stones(ox, ox + W - 1)
	_stamp_features(ox, ox + W - 1)
	_make_neg()
	layout += 1


func _make_neg() -> void:
	_neg.resize(PLANES * WH)
	for i in PLANES * WH:
		_neg[i] = -1


# Grow the sim range so [xa, xb] (plus MARGIN) is covered. Returns true if it grew.
func ensure_cols(xa: int, xb: int) -> bool:
	xa -= MARGIN
	xb += MARGIN
	var add_l := 0
	var add_r := 0
	while xa < ox - add_l:
		add_l += CHUNK
	while xb > ox + W - 1 + add_r:
		add_r += CHUNK
	if add_l == 0 and add_r == 0:
		return false
	_extend(add_l, add_r)
	return true


func _fresh_row(xa: int, xb: int, y: int, what: int) -> PackedByteArray:
	var r := PackedByteArray()
	for x in range(xa, xb):
		var s = surf_y(x)
		if what == 0:
			r.append(1 if y >= s else 0)
		elif what == 1:
			r.append(0)
		else:
			r.append(strata_at(x, y) if y >= s else M_HUMUS)
	return r


func _extend(add_l: int, add_r: int) -> void:
	var nw = W + add_l + add_r
	var nox = ox - add_l
	var new_arrays := []
	# solid, walk: per plane. under, mat, link: one plane.
	for spec in [[solid, 0, PLANES], [walk, 1, PLANES], [under, 0, 1], [mat, 2, 1], [link, 1, 1]]:
		var src: PackedByteArray = spec[0]
		var out := PackedByteArray()
		for z in spec[2]:
			for y in H:
				out.append_array(_fresh_row(nox, ox, y, spec[1]))
				if W > 0:
					var r0 = z * WH + y * W
					out.append_array(src.slice(r0, r0 + W))
				out.append_array(_fresh_row(ox + W, nox + nw, y, spec[1]))
		new_arrays.append(out)
	var np := PackedFloat32Array()
	for i in add_l:
		np.append(0.0)
	np.append_array(pher)
	for i in add_r:
		np.append(0.0)
	solid = new_arrays[0]
	walk = new_arrays[1]
	under = new_arrays[2]
	mat = new_arrays[3]
	link = new_arrays[4]
	pher = np
	var old_l = ox
	var old_r = ox + W - 1
	ox = nox
	W = nw
	WH = W * H
	if add_l > 0:
		_stamp_stones(ox, old_l - 1)
		_stamp_features(ox, old_l - 1)
	if add_r > 0:
		_stamp_stones(old_r + 1, ox + W - 1)
		_stamp_features(old_r + 1, ox + W - 1)
	_make_neg()
	layout += 1
	if add_l > 0:
		_refresh_walk(ox, 0, old_l, H - 1)
	if add_r > 0:
		_refresh_walk(old_r, 0, ox + W - 1, H - 1)
	rebuild_nav()


# ---------- queries ----------
func inb(x: int, y: int) -> bool:
	return x >= ox and y >= 0 and x < ox + W and y < H


func _i(x: int, y: int, z: int = 0) -> int:
	return z * WH + y * W + (x - ox)


# Outside the sim range the terrain is pristine: solid below the surface.
# Above the top of the world there is only sky (never a wall to climb).
func is_solid(x: int, y: int, z: int = 0) -> bool:
	if y < 0:
		return false
	if y >= H:
		return true
	if x < ox or x >= ox + W:
		return y >= surf_y(x)
	return solid[z * WH + y * W + (x - ox)] == 1


func is_under(x: int, y: int) -> bool:
	return inb(x, y) and under[y * W + (x - ox)] == 1


func can_walk(x: int, y: int, z: int = 0) -> bool:
	return inb(x, y) and walk[z * WH + y * W + (x - ox)] == 1


# A hole joins the planes here (both open).
func is_link(x: int, y: int) -> bool:
	if not inb(x, y):
		return false
	var j = y * W + (x - ox)
	return link[j] == 1 and solid[j] == 0 and solid[WH + j] == 0


# Surface walkers may use air cells and the top row of the ground (e.g. the
# shaft mouth), but never go deeper.
func is_surface_cell(x: int, y: int) -> bool:
	return inb(x, y) and y <= surf_y(x)


func diggable(x: int, y: int, z: int = 0) -> bool:
	if not inb(x, y) or y >= H - 3 or y < surf_y(x) + 3:
		return false
	var j = y * W + (x - ox)
	return solid[z * WH + j] == 1 and DIG_RATE[mat[j]] > 0.0


func center(x: int, y: int) -> Vector2:
	return Vector2((x + 0.5) * CELL, (y + 0.5) * CELL)


func neighbors(x: int, y: int, z: int = 0) -> Array:
	var out := []
	var xl = x - ox
	if xl < 1 or xl >= W - 1 or y < 1 or y >= H - 1:
		for d in N8:
			var nx = x + int(d.x)
			var ny = y + int(d.y)
			if can_walk(nx, ny, z):
				out.append(Vector2(nx, ny))
		return out
	# interior fast path: same order as N8, no per-cell bounds checks
	var b = z * WH + y * W + xl
	var w = walk
	if w[b - W - 1] == 1:
		out.append(Vector2(x - 1, y - 1))
	if w[b - W] == 1:
		out.append(Vector2(x, y - 1))
	if w[b - W + 1] == 1:
		out.append(Vector2(x + 1, y - 1))
	if w[b - 1] == 1:
		out.append(Vector2(x - 1, y))
	if w[b + 1] == 1:
		out.append(Vector2(x + 1, y))
	if w[b + W - 1] == 1:
		out.append(Vector2(x - 1, y + 1))
	if w[b + W] == 1:
		out.append(Vector2(x, y + 1))
	if w[b + W + 1] == 1:
		out.append(Vector2(x + 1, y + 1))
	return out


func walled(x: int, y: int, z: int = 0) -> bool:
	var xl = x - ox
	if xl >= 1 and xl < W - 1 and y >= 1 and y < H - 1:
		var b = z * WH + y * W + xl
		var s = solid
		return s[b - W - 1] == 1 or s[b - W] == 1 or s[b - W + 1] == 1 or s[b - 1] == 1 or s[b + 1] == 1 \
			or s[b + W - 1] == 1 or s[b + W] == 1 or s[b + W + 1] == 1
	for d in N8:
		if is_solid(x + int(d.x), y + int(d.y), z):
			return true
	return false


# Unit vector pointing from the cell toward nearby solid ground (the "floor").
func ground_normal(x: int, y: int, z: int = 0) -> Vector2:
	var n := Vector2.ZERO
	for d in N8:
		if is_solid(x + int(d.x), y + int(d.y), z):
			n += d
	return n.normalized() if n != Vector2.ZERO else Vector2(0, 1)


func field(f: PackedInt32Array, x: int, y: int, z: int = 0) -> int:
	if f.size() != PLANES * WH or not inb(x, y):
		return -1
	return f[z * WH + y * W + (x - ox)]


func pher_at(x: int) -> float:
	return pher[x - ox] if x >= ox and x < ox + W else 0.0


func pher_add(x: int, v: float, cap: float) -> void:
	if x >= ox and x < ox + W:
		pher[x - ox] = min(pher[x - ox] + v, cap)
		if x < pher_lo:
			pher_lo = x
		if x > pher_hi:
			pher_hi = x


# Trail decay over the active range only (was a full-width loop every tick). Values under
# 0.02 snap to zero and the range shrinks to what is left.
func pher_decay(k: float) -> void:
	if pher_hi < pher_lo:
		return
	var lo = max(pher_lo, ox) - ox
	var hi = min(pher_hi, ox + W - 1) - ox
	var ph = pher
	var nlo = 1 << 30
	var nhi = -(1 << 30)
	for i in range(lo, hi + 1):
		var v = ph[i]
		if v > 0.0:
			v *= k
			if v < 0.02:
				v = 0.0
			else:
				if i < nlo:
					nlo = i
				nhi = i
			ph[i] = v
	pher = ph
	pher_lo = nlo + ox if nlo < (1 << 30) else (1 << 30)
	pher_hi = nhi + ox if nhi > -(1 << 30) else -(1 << 30)


# ---------- digging ----------
func carve(cx: float, cy: float, r: float, z: int = 0) -> int:
	return _carve_raw(cx, cy, r, false, z, false)


# force: ignores material (the founding dig, Lab entrances, tunnel borers).
func _carve_raw(cx: float, cy: float, r: float, allow_roof: bool, z: int = 0, force: bool = false) -> int:
	var x0 = int(floor(cx - r)) - 1
	var x1 = int(ceil(cx + r)) + 1
	var y0 = int(floor(cy - r)) - 1
	var y1 = int(ceil(cy + r)) + 1
	if x0 < ox + 2 or x1 > ox + W - 3:
		ensure_cols(x0, x1)
	var n := 0
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if not inb(x, y) or y > H - 3:
				continue
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) > r * r:
				continue
			if not allow_roof and y < surf_y(x) + 3:
				continue
			if _open(x, y, z, force):
				n += 1
	if n > 0 and walk.size() == PLANES * WH:
		_refresh_walk(x0 - 1, y0 - 1, x1 + 1, y1 + 1)
		_touch(x0 - 1, y0 - 1, x1 + 1, y1 + 1)
		nav_dirty = true
	return n


func _open(x: int, y: int, z: int = 0, force: bool = false) -> bool:
	var j = y * W + (x - ox)
	var i = z * WH + j
	if solid[i] == 1 and under[j] == 1 and (force or DIG_RATE[mat[j]] > 0.0):
		solid[i] = 0
		open_under += 1
		dug_by_mat[mat[j]] += 1
		return true
	return false


# Punch holes between the planes around (cx, cy): every cell within r that is open
# in both planes becomes a crossing point.
func make_link(cx: int, cy: int, r: int = 1) -> int:
	var n := 0
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if inb(x, y):
				var j = y * W + (x - ox)
				if solid[j] == 0 and solid[WH + j] == 0 and link[j] == 0:
					link[j] = 1
					n += 1
	if n > 0:
		_touch(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1)
		nav_dirty = true
	return n


func _walk_rule(x: int, y: int, z: int) -> int:
	var j = y * W + (x - ox)
	if solid[z * WH + j] == 1:
		return 0
	if z == 1:
		if under[j] == 0:
			return 0
		for d in N8:
			if is_solid(x + int(d.x), y + int(d.y), 1):
				return 1
		return 0
	for d in N8:
		if is_solid(x + int(d.x), y + int(d.y)):
			return 1
	var s = surf_y(x)
	if under[j] == 1:
		return 1 if y <= s + 1 else 0      # rim across a shaft mouth
	return 1 if y == s - 1 else 0          # ground-level path over a mouth


func _refresh_walk(x0: int, y0: int, x1: int, y1: int) -> void:
	for y in range(max(0, y0), min(H - 1, y1) + 1):
		for x in range(max(ox, x0), min(ox + W - 1, x1) + 1):
			var j = y * W + (x - ox)
			walk[j] = _walk_rule(x, y, 0)
			walk[WH + j] = _walk_rule(x, y, 1)


func solid_count(x: int, y: int, z: int = 0) -> int:
	var c := 0
	for d in N8:
		if is_solid(x + int(d.x), y + int(d.y), z):
			c += 1
	return c


# ---------- spoil: the mound is real dirt ----------
# Diggers carry spoil up and drop it next to a mouth. Each whole cell of it is one
# grain that rolls downhill until it finds a resting spot where no neighbouring column
# is lower (so the pile keeps a walkable 1-step slope), then becomes ground. Grains
# never land in a mouth column; the mouth rises with the pile as a chimney.
# Returns the columns that changed.
func deposit(x0: int, cells: float, rng) -> Array:
	_grain_acc += cells
	var changed := []
	while _grain_acc >= 1.0:
		_grain_acc -= 1.0
		var x = _roll(x0, rng)
		if x == null:
			spoil_lost += 1
			continue
		_raise(x)
		mound_cells += 1
		if not changed.has(x):
			changed.append(x)
	return changed


# A grain may rest where no neighbouring column is lower. Mouth columns do not count:
# they rise with the pile on their own (see _raise).
func _rest_ok(x: int) -> bool:
	var h = surf_y(x)
	for n in [x - 1, x + 1]:
		if not chimneys.has(n) and surf_y(n) > h:
			return false
	return true


func _roll(x: int, rng):
	if chimneys.has(x):
		x += 1 if rng.randf() < 0.5 else -1
	for step in 16:
		if surf_y(x) <= SKY_LIMIT + 1:
			return null
		var ok = _rest_ok(x)
		if ok and rng.randf() < 0.85:
			return x
		var best = null
		for n in [x - 1, x + 1]:
			if chimneys.has(n) or surf_y(n) <= surf_y(x):
				continue
			if best == null or surf_y(n) > surf_y(best) or (surf_y(n) == surf_y(best) and rng.randf() < 0.5):
				best = n
		if best == null:
			if not ok:
				return null
			# flat ground: drift one column, or stop at an edge
			var n2 = x + (1 if rng.randf() < 0.5 else -1)
			if chimneys.has(n2) or surf_y(n2) != surf_y(x):
				return x
			best = n2
		x = best
	return x if _rest_ok(x) and not chimneys.has(x) else null


func _raise(x: int) -> void:
	ensure_cols(x - 2, x + 2)
	var y = surf_y(x) - 1
	_mound[x] = _mound.get(x, 0) + 1
	surf_dirty[x] = true
	var j = y * W + (x - ox)
	solid[j] = 1
	solid[WH + j] = 1
	under[j] = 1
	mat[j] = M_SPOIL
	var y_lo = y
	# a mouth next to this column rises with the pile: its column becomes an open chimney
	for c in [x - 1, x + 1]:
		if chimneys.has(c):
			var target = max(_mound.get(c - 1, 0), _mound.get(c + 1, 0)) - 1
			while _mound.get(c, 0) < target:
				var cy = surf_y(c) - 1
				_mound[c] = _mound.get(c, 0) + 1
				surf_dirty[c] = true
				var jc = cy * W + (c - ox)
				solid[jc] = 0
				solid[WH + jc] = 1
				under[jc] = 1
				mat[jc] = M_SPOIL
				y_lo = min(y_lo, cy)
	for i in entrances.size():
		entrances[i] = Vector2(entrances[i].x, surf_y(int(entrances[i].x)) - 1)
	entrance = entrances[0]
	_refresh_walk(x - 3, y_lo - 3, x + 3, y + 3)
	_touch(x - 2, y_lo - 2, x + 2, y + 2)
	nav_dirty = true


# ---------- render data (read by the view) ----------
static func chunk_of(x: int) -> int:
	return int(floor(float(x) / CHUNK))


func _touch(x0: int, y0: int, x1: int, y1: int) -> void:
	for k in range(chunk_of(x0 - PAD), chunk_of(x1 + PAD) + 1):
		if _chunk_img.has(k):
			_paint(_chunk_img[k], k, x0, y0, x1, y1)
		dirty_chunks[k] = true


# Mask images of chunk k, each (CHUNK + 2 * PAD) x H:
#  front: R = solid front plane (3x3 smoothed so outlines curve), G = underground, B = turf
#  aux:   R = solid back plane (smoothed), G = stone or fossil (smoothed), B = hole between
#         planes, A = 1 - fossil
func chunk_images(k: int) -> Array:
	if _chunk_img.has(k):
		return _chunk_img[k]
	var cw = CHUNK + 2 * PAD
	var x0 = k * CHUNK - PAD
	var front = Image.create_empty(cw, H, false, Image.FORMAT_RGBA8)
	front.fill(Color(1, 1, 0, 1))
	var aux = Image.create_empty(cw, H, false, Image.FORMAT_RGBA8)
	aux.fill(Color(1, 0, 0, 1))
	# pristine columns: air above, one smooth transition, solid below
	for c in cw:
		var x = x0 + c
		var s = surf_y(x)
		front.blit_rect(_air_col, Rect2(0, 0, 1, max(0, s - 2)), Vector2(c, 0))
		aux.blit_rect(_air_col, Rect2(0, 0, 1, max(0, s - 2)), Vector2(c, 0))
	var pair = [front, aux]
	for c in cw:
		var x = x0 + c
		var s = surf_y(x)
		for y in range(max(0, s - 2), min(H, s + 3)):
			front.set_pixel(c, y, _pix(x, y))
			aux.set_pixel(c, y, _pix_aux(x, y))
	# stones
	var sts = stones_in(x0 - 2, x0 + cw + 1)
	_smap = {}
	for st in sts:
		for y in range(int(st[1] - st[3]) - 1, int(st[1] + st[3]) + 2):
			for x in range(int(st[0] - st[2]) - 1, int(st[0] + st[2]) + 2):
				var dx = (x + 0.5 - st[0]) / st[2]
				var dy = (y + 0.5 - st[1]) / st[3]
				if dx * dx + dy * dy <= 1.0 and y >= surf_y(x):
					_smap[x * 1024 + y] = st[4]
	for st in sts:
		_paint(pair, k, int(st[0] - st[2]) - 1, int(st[1] - st[3]) - 1, int(st[0] + st[2]) + 1, int(st[1] + st[3]) + 1)
	_smap = null
	# anything the colony has changed
	var lo = max(x0, ox)
	var hi = min(x0 + cw - 1, ox + W - 1)
	if lo <= hi:
		_paint_dug(pair, k, lo - 1, hi + 1)
		_chunk_img[k] = pair
	return pair


# Per column of chunk k: R = surface y / 255 (mound included), G = original ground y / 255,
# B = strata wave offset ((off + 8) / 16). The shaders use these for strata and the mound.
func chunk_surf_image(k: int) -> Image:
	var cw = CHUNK + 2 * PAD
	var img = Image.create_empty(cw, 1, false, Image.FORMAT_RGBA8)
	for c in cw:
		var x = k * CHUNK - PAD + c
		img.set_pixel(c, 0, Color(surf_y(x) / 255.0, base_y(x) / 255.0, clamp((strata_off(x) + 8.0) / 16.0, 0.0, 1.0), 1))
	return img


func _paint_dug(pair: Array, k: int, xa: int, xb: int) -> void:
	# rows that differ from pristine: any dug cell (either plane) or mound in the column
	for x in range(xa, xb + 1):
		if x < ox or x >= ox + W:
			continue
		var c = x - ox
		var ymin = -1
		var ymax = -1
		for y in H:
			var j = y * W + c
			if under[j] == 1 and (solid[j] == 0 or solid[WH + j] == 0):
				if ymin < 0:
					ymin = y
				ymax = y
		var m = _mound.get(x, 0)
		if m > 0:
			var s = surf_y(x)
			ymin = s - 2 if ymin < 0 else min(ymin, s - 2)
			ymax = max(ymax, s + m + 2)
		if ymin >= 0:
			_paint(pair, k, x - 1, ymin - 1, x + 1, ymax + 1)


func _paint(pair: Array, k: int, x0: int, y0: int, x1: int, y1: int) -> void:
	var cx0 = k * CHUNK - PAD
	var cw = CHUNK + 2 * PAD
	var front: Image = pair[0]
	var aux: Image = pair[1]
	for y in range(max(0, y0 - 1), min(H - 1, y1 + 1) + 1):
		for x in range(max(cx0, x0 - 1), min(cx0 + cw - 1, x1 + 1) + 1):
			front.set_pixel(x - cx0, y, _pix(x, y))
			aux.set_pixel(x - cx0, y, _pix_aux(x, y))


func _pix(x: int, y: int) -> Color:
	var acc := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var w = 4.0 if dx == 0 and dy == 0 else (2.0 if dx == 0 or dy == 0 else 1.0)
			if is_solid(x + dx, int(clamp(y + dy, 0, H - 1))):
				acc += w
	var s = surf_y(x)
	var sol = is_solid(x, y)
	var u = 1.0 if y >= s else 0.0
	var g = 1.0 if (sol and y <= s + 1 and y >= base_y(x)) else 0.0
	return Color(acc / 16.0, u, g, 1.0)


func _pix_aux(x: int, y: int) -> Color:
	var accb := 0.0
	var accs := 0.0
	var accf := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var w = 4.0 if dx == 0 and dy == 0 else (2.0 if dx == 0 or dy == 0 else 1.0)
			var yy = int(clamp(y + dy, 0, H - 1))
			if is_solid(x + dx, yy, 1):
				accb += w
			var m = mat_at(x + dx, yy)
			if m == M_STONE or m == M_FOSSIL:
				accs += w
				if m == M_FOSSIL:
					accf += w
	var lk = 1.0 if is_link(x, y) else 0.0
	return Color(accb / 16.0, accs / 16.0, lk, 1.0 - accf / 16.0)


# New shaft at column x down to chamber depth, then a gallery back toward the
# main shaft until it meets existing tunnels.
func add_entrance(x: int) -> void:
	x = int(clamp(x, arena_l + 12, arena_r - 12))
	ensure_cols(x - 8, x + 8)
	var flat = true
	for xx in range(x - 4, x + 5):
		if _mound.get(xx, 0) > 0:
			flat = false
	var sx = surf_y(x)
	if flat:
		for xx in range(x - 3, x + 4):
			_set_surf(xx, sx)
	var depth = int(chamber.y)
	for y in range(sx, depth + 1):
		_carve_raw(x, y, 1.2 if y < sx + 2 else 1.6, true, 0, true)
	var dir = 1 if chamber.x > x else -1
	var cx = x
	while cx != int(chamber.x):
		cx += dir
		var hit = not is_solid(cx + dir * 2, depth)
		_carve_raw(cx, depth, 1.6, false, 0, true)
		if hit:
			break
	entrances.append(Vector2(x, sx - 1))
	chimneys[x] = true
	_refresh_walk(x - 5, sx - 3, x + 5, sx + 3)
	_touch(x - 5, 0, x + 5, H - 1)
	nav_dirty = true


func nearest_entrance_x(x: int) -> int:
	var best = int(entrance.x)
	for en in entrances:
		if abs(int(en.x) - x) < abs(best - x):
			best = int(en.x)
	return best


# ---------- navigation fields ----------
func rebuild_nav() -> void:
	var home := []
	var exits := []
	for y in range(int(chamber.y - chamber_r.y) - 1, int(chamber.y + chamber_r.y) + 2):
		for x in range(int(chamber.x - chamber_r.x) - 1, int(chamber.x + chamber_r.x) + 2):
			if can_walk(x, y):
				home.append(Vector2(x, y))
	for en in entrances:
		for x in range(int(en.x) - 2, int(en.x) + 3):
			var s = surf_y(x)
			for y in range(s - 2, s + 1):
				if can_walk(x, y) and not is_under(x, y):
					exits.append(Vector2(x, y))
	dist_home = _bfs(home)
	dist_exit = _bfs(exits)
	nav_dirty = false


# Breadth-first distance over both planes. Sources are Vector2 (front plane) or
# Vector3 (x, y, plane). Planes connect only through holes (link).
func _bfs(sources: Array, max_d: int = -1) -> PackedInt32Array:
	var dist: PackedInt32Array = _neg.duplicate()     # Godot 4 shares packed arrays on assignment: copy, never write into _neg
	var queue := PackedInt32Array()
	for s in sources:
		var sz = int(s.z) if typeof(s) == TYPE_VECTOR3 else 0
		if not inb(int(s.x), int(s.y)):
			continue
		var si = _i(int(s.x), int(s.y), sz)
		if dist[si] != 0:
			dist[si] = 0
			queue.append(si)
	var wk = walk
	var lk = link
	var w = W
	var wh = WH
	var h = H
	var offs = [-w - 1, -w, -w + 1, -1, 1, w - 1, w, w + 1]
	var head := 0
	while head < queue.size():
		var i = queue[head]
		head += 1
		var nd = dist[i] + 1
		if max_d >= 0 and nd > max_d:
			continue        # depth cap: cells past it stay -1
		var z = 1 if i >= wh else 0
		var r = i - z * wh
		var x = r % w
		var y = r / w
		if x > 0 and x < w - 1 and y > 0 and y < h - 1:
			for o in offs:
				var j = i + o
				if wk[j] == 1 and dist[j] == -1:
					dist[j] = nd
					queue.append(j)
		else:
			var base = z * wh
			for d in N8:
				var nx = x + int(d.x)
				var ny = y + int(d.y)
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var j2 = base + ny * w + nx
				if wk[j2] == 1 and dist[j2] == -1:
					dist[j2] = nd
					queue.append(j2)
		if lk[r] == 1:
			var j3 = (1 - z) * wh + r
			if wk[j3] == 1 and dist[j3] == -1:
				dist[j3] = nd
				queue.append(j3)
	return dist
