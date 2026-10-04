extends RefCounted
# Side-view ant-farm world: a fixed WORLD_W columns wide (v1.3: big, not infinite), with the nest in the middle.
#
# Layers of data:
#  - the surface PROFILE (one int per column) is generated outward from the original playfield (it is defined
#    beyond the world too, so the view can pad its chunk edges). On top of it sits the MOUND: real dirt the diggers
#    carried up (see deposit()).
#  - the SIM arrays cover the whole world, built once when the colony starts (_alloc_fresh, with native image fills
#    so it takes a fraction of a second). Nothing grows after that; units cannot step or dig past the edges.
#  - two tunnel PLANES: 0 = front (the cut face the camera looks at, surface, shafts),
#    1 = back (a second layer of tunnels behind it). A back tunnel can run behind a
#    front one without touching it; the two planes only connect through HOLES (link).
#  - MATERIAL per cell: strata (humus, clay, sand, red clay, bedrock), stones and
#    fossils. Material sets how fast a cell digs; bedrock, stones and fossils do not dig.
#  - for the view: one packed int per cell (_cellp: solid front, solid back, stone, fossil, a byte each) kept in step
#    with the arrays, so a chunk's mask images are built from it in a few ms (chunk_images).
# All public functions take WORLD coordinates (x can be negative) and a plane z (0/1).
# Internally cells are indexed z * WH + y * W + (x - ox).
#
# Footing: an ant may stand only on an open cell that touches solid ground in its own
# plane (floor, wall or ceiling), or on the ground-level rim across a shaft mouth.
# The back plane exists only underground.

const UG = preload("res://core/underground.gd")
const CELL = 6.0
const CHUNK = 64          # render step (columns)
const PAD = 2             # render padding so chunk seams filter cleanly
const WORLD_CHUNKS = 48   # the world is this many chunks wide...
const WORLD_W = CHUNK * WORLD_CHUNKS   # ...3072 columns (about 18,400 px), chunk aligned, the nest in the middle
const PM = PAD + 1        # columns of _cellp beyond each world edge (a chunk's padding plus its smoothing ring)
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

var W: int                # sim columns (the whole world)
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
var _chunk_img := {}            # k -> [front, aux] mask images of chunk k, built on first use, repainted in place on digs
var _neg := PackedInt32Array()      # all -1, PLANES * WH: copied (COW) as a BFS start
var _cellp := PackedInt32Array()    # PW * H, columns ox - PM ..: solid front | solid back << 8 | stone << 16 | fossil << 24
var PW := 0                         # W + 2 * PM
var _dug_lo := PackedInt32Array()   # per sim column: first row dug open (either plane), H if none
var _dug_hi := PackedInt32Array()   # per sim column: last row dug open, -1 if none
var _nbm := PackedByteArray()      # PLANES * WH: bit d set = the N8[d] neighbour can be walked (kept with walk, read by _bfs)
var _nb_off := PackedInt32Array()  # bit value (1, 2, 4 .. 128) -> index offset of that neighbour
var _lut_v := PackedByteArray()     # byte that Image.set_pixel stores for v / 16.0 (v = 0..16)
var _lut_a := PackedByteArray()     # ... and for 1.0 - v / 16.0
var _nest_x := 130
var _nest_y := 70
var _block_cache := {}
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

	_nest_x = ex
	_nest_y = surf_y(ex) + 26
	ox = int(round((ex - WORLD_W / 2.0) / CHUNK)) * CHUNK
	W = WORLD_W
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
	# (the shaft carves refreshed their own footing; the chamber's cells were opened directly)
	_refresh_walk(int(chamber.x - chamber_r.x) - 2, int(chamber.y - chamber_r.y) - 2, int(chamber.x + chamber_r.x) + 3, int(chamber.y + chamber_r.y) + 3)
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
		var bits = (1 << 16) | ((1 << 24) if s[4] == M_FOSSIL else 0)
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
						var pj = y * PW + (x - ox + PM)
						_cellp[pj] = (_cellp[pj] & 0xffff) | bits


# Underground structures (core/underground.gd: roots, caverns, buried things, veins, ruins) written into the sim columns.
# They write the arrays directly, so the columns they touch are re-read afterwards (footing, view cells, dug rows).
func _stamp_features(xa: int, xb: int) -> void:
	if ug == null:
		ug = UG.make()
	ug.stamp_range(self, xa, xb)
	var mods = ug.modules()
	for n in mods.keys():
		if ug.has_fn(mods[n], "stamp"):
			for f in ug.features(n, self, xa, xb):
				_resync_cols(max(xa, int(f["x0"])), min(xb, int(f["x1"])))


# Material anywhere (outside the sim range it is computed from the generators).
func mat_at(x: int, y: int) -> int:
	if inb(x, y):
		return mat[y * W + (x - ox)]
	if y < surf_y(x):
		return M_HUMUS
	if y < base_y(x) + 4:
		return strata_at(x, y)
	for s in stones_in(x, x):
		var dx = (x + 0.5 - s[0]) / s[2]
		var dy = (y + 0.5 - s[1]) / s[3]
		if dx * dx + dy * dy <= 1.0:
			return s[4]
	return strata_at(x, y)


func dig_rate(x: int, y: int) -> float:
	return DIG_RATE[mat_at(x, y)]


# ---------- the world's columns ----------
func sim_l() -> int:
	return ox


func sim_r() -> int:
	return ox + W - 1


# A colour that Image fills store as exactly these bytes (Image truncates channel * 255).
static func _bytes(r: int, g: int = 0, b: int = 0, a: int = 0) -> Color:
	return Color((r + 0.25) / 255.0, (g + 0.25) / 255.0, (b + 0.25) / 255.0, (a + 0.25) / 255.0)


# Builds every array for the whole world. Each column of pristine ground is a few runs (air, the strata, solid below
# the surface, footing just above it), so it is written with one native fill per run instead of cell by cell.
func _alloc_fresh() -> void:
	WH = W * H
	PW = W + 2 * PM
	var su := PackedInt32Array()       # surface of columns ox - 1 .. ox + W
	su.resize(W + 2)
	for i in W + 2:
		su[i] = surf_y(ox - 1 + i)
	var img_u := Image.create_empty(W, H, false, Image.FORMAT_R8)
	var img_m := Image.create_empty(W, H, false, Image.FORMAT_R8)
	var img_w := Image.create_empty(W, H, false, Image.FORMAT_R8)
	var img_p := Image.create_empty(PW, H, false, Image.FORMAT_RGBA8)
	var one := _bytes(1)
	var both := _bytes(1, 1)
	var mcol := []
	for m in MAT_NAMES.size():
		mcol.append(_bytes(m))
	var run_mat = [M_HUMUS, M_CLAY, M_SAND, M_RED, M_LIME, M_SHALE, M_BED]
	for c in W:
		var x = ox + c
		var s: int = su[c + 1]
		if s < H:
			img_u.fill_rect(Rect2i(c, s, 1, H - s), one)
			img_p.fill_rect(Rect2i(c + PM, s, 1, H - s), both)
		# footing: the open cells that touch the ground (the rule of _walk_rule on untouched columns)
		var ylo = max(1, min(s, min(su[c], su[c + 2])) - 1)
		if s > ylo and c > 0 and c < W - 1:
			img_w.fill_rect(Rect2i(c, ylo, 1, s - ylo), one)
		# strata: the same seams as strata_at, found exactly
		var b = base_y(x)
		var off = strata_off(x)
		var ya = s
		for m in 7:
			var yb = H if m == 6 else clampi(_seam_y(b, off, SEAMS[m]), s, H)
			if yb > ya and run_mat[m] != 0:
				img_m.fill_rect(Rect2i(c, ya, 1, yb - ya), mcol[run_mat[m]])
			ya = max(ya, yb)
	under = img_u.get_data()
	solid = under.duplicate()           # Godot 4 shares packed arrays: each plane needs its own copy
	solid.append_array(under)
	mat = img_m.get_data()
	link = PackedByteArray()
	link.resize(WH)
	link.fill(0)
	walk = img_w.get_data()
	var back := PackedByteArray()
	back.resize(WH)
	back.fill(0)
	walk.append_array(back)
	_nb_off.resize(129)
	for d in 8:
		_nb_off[1 << d] = int(N8[d].y) * W + int(N8[d].x)
	_nbm.resize(PLANES * WH)
	_nbm.fill(0)
	var wi = walk.find(1)
	while wi >= 0:
		_nb_flip(wi, true)
		wi = walk.find(1, wi + 1)
	_cellp = img_p.get_data().to_int32_array()
	for i in PM:
		for x in [ox - PM + i, ox + W + i]:
			var col = _pristine_col(x)
			var ci = x - ox + PM
			for y in H:
				_cellp[y * PW + ci] = col[y]
	pher.resize(W)
	pher.fill(0.0)
	_dug_lo.resize(W)
	_dug_lo.fill(H)
	_dug_hi.resize(W)
	_dug_hi.fill(-1)
	_stamp_stones(ox, ox + W - 1)
	_stamp_features(ox, ox + W - 1)
	_make_neg()
	layout += 1


# First row y at which strata_at's depth (y - b) + off reaches the seam (the same float sum, so the same answer).
static func _seam_y(b: int, off: float, seam: float) -> int:
	var y = int(ceil(seam + b - off))
	while (y - 1 - b) + off >= seam:
		y -= 1
	while (y - b) + off < seam:
		y += 1
	return y


# View cells (_cellp values) of an untouched column outside the world: solid below the surface, stones as mat_at has them.
func _pristine_col(x: int) -> PackedInt32Array:
	var col := PackedInt32Array()
	col.resize(H)
	col.fill(0)
	var s = surf_y(x)
	for y in range(max(0, s), H):
		col[y] = 0x101
	var lim = max(s, base_y(x) + 4)
	for st in stones_in(x, x):
		var bits = 0x101 | (1 << 16) | ((1 << 24) if st[4] == M_FOSSIL else 0)
		for y in range(max(lim, int(st[1] - st[3]) - 1), min(H, int(st[1] + st[3]) + 2)):
			var dx = (x + 0.5 - st[0]) / st[2]
			var dy = (y + 0.5 - st[1]) / st[3]
			if dx * dx + dy * dy <= 1.0:
				col[y] = bits
	return col


# Re-read columns xa..xb after something wrote the arrays directly: view cells, dug rows, footing.
func _resync_cols(xa: int, xb: int) -> void:
	xa = max(xa, ox)
	xb = min(xb, ox + W - 1)
	if xa > xb:
		return
	for x in range(xa, xb + 1):
		var c = x - ox
		_dug_lo[c] = H
		_dug_hi[c] = -1
		for y in H:
			var j = y * W + c
			var m = mat[j]
			var p = solid[j] | (solid[WH + j] << 8)
			if m == M_STONE or m == M_FOSSIL:
				p |= (1 << 16) | ((1 << 24) if m == M_FOSSIL else 0)
			_cellp[y * PW + c + PM] = p
			if under[j] == 1 and (solid[j] == 0 or solid[WH + j] == 0):
				_dug_lo[c] = min(_dug_lo[c], y)
				_dug_hi[c] = y
	_refresh_walk(xa - 1, 0, xb + 1, H - 1)


func _make_neg() -> void:
	_neg.resize(PLANES * WH)
	_neg.fill(-1)


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
		var pj = y * PW + (x - ox + PM)
		_cellp[pj] = _cellp[pj] & ~(1 << (8 * z))
		var c = x - ox
		if y < _dug_lo[c]:
			_dug_lo[c] = y
		if y > _dug_hi[c]:
			_dug_hi[c] = y
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
	if x <= ox or x >= ox + W - 1 or y <= 0 or y >= H - 1:
		return 0                           # no footing on the world's border cells (so _bfs never steps off the arrays)
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
			var v = _walk_rule(x, y, 0)
			if walk[j] != v:
				walk[j] = v
				_nb_flip(j, v == 1)
			v = _walk_rule(x, y, 1)
			if walk[WH + j] != v:
				walk[WH + j] = v
				_nb_flip(WH + j, v == 1)


# Cell i (never on the border: _walk_rule) became walkable or stopped being: tell its eight neighbours' masks.
func _nb_flip(i: int, on: bool) -> void:
	for d in 8:
		var n = i + _nb_off[1 << d]
		var b = 1 << (7 - d)          # N8 is symmetric: the way back from neighbour d is 7 - d
		_nbm[n] = (_nbm[n] | b) if on else (_nbm[n] & ~b)


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
		if x == null or x < ox + 3 or x > ox + W - 4:
			spoil_lost += 1          # (or it rolled off the edge of the world)
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
	var y = surf_y(x) - 1
	_mound[x] = _mound.get(x, 0) + 1
	surf_dirty[x] = true
	var j = y * W + (x - ox)
	solid[j] = 1
	solid[WH + j] = 1
	under[j] = 1
	mat[j] = M_SPOIL
	_cellp[y * PW + (x - ox + PM)] = 0x101
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
				_cellp[cy * PW + (c - ox + PM)] = 0x100
				_dug_lo[c - ox] = min(_dug_lo[c - ox], cy)
				_dug_hi[c - ox] = max(_dug_hi[c - ox], cy)
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
# Built from _cellp in a few ms: the image starts as plain ground (air above the surface, solid below) and only the
# pixels that can differ from it are worked out (around the surface line, the stones and whatever the colony dug).
# One packed int holds a cell's four flags a byte each, so one weighted sum smooths all four masks at once.
func has_chunk_images(k: int) -> bool:
	return _chunk_img.has(k)


func chunk_images(k: int) -> Array:
	if _chunk_img.has(k):
		return _chunk_img[k]
	if _lut_v.is_empty():
		_make_lut()
	var cw := CHUNK + 2 * PAD
	var x0 := k * CHUNK - PAD
	var lw := cw + 2
	var P := _cells(x0 - 1, lw)          # lw x H: the chunk's cells and a ring of one column either side
	var front := Image.create_empty(cw, H, false, Image.FORMAT_RGBA8)
	front.fill(Color(1, 1, 0, 1))
	var aux := Image.create_empty(cw, H, false, Image.FORMAT_RGBA8)
	aux.fill(Color(1, 0, 0, 1))
	var need := Image.create_empty(cw, H, false, Image.FORMAT_R8)
	var air := Color(0, 0, 0, 1)
	var on := Color(1, 1, 1, 1)
	var sy := PackedInt32Array()
	sy.resize(cw)
	var gy := PackedInt32Array()
	gy.resize(cw)
	for c in cw:
		var x = x0 + c
		var s = surf_y(x)
		sy[c] = s
		gy[c] = base_y(x)
		if s > 2:
			front.fill_rect(Rect2i(c, 0, 1, s - 2), air)
			aux.fill_rect(Rect2i(c, 0, 1, s - 2), air)
		# the surface line: one smooth transition from air to ground
		var ya = max(0, s - 2)
		var yb = min(H, s + 3)
		if yb > ya:
			need.fill_rect(Rect2i(c, ya, 1, yb - ya), on)
	for st in stones_in(x0 - 2, x0 + cw + 1):
		_need(need, x0, int(st[0] - st[2]) - 2, int(st[1] - st[3]) - 2, int(st[0] + st[2]) + 2, int(st[1] + st[3]) + 2)
	# anything the colony has changed: rows dug open in either plane, and the mound
	for x in range(max(x0 - 1, ox), min(x0 + cw, ox + W - 1) + 1):
		var c = x - ox
		var ymin = _dug_lo[c] if _dug_hi[c] >= 0 else -1
		var ymax = _dug_hi[c]
		var m = _mound.get(x, 0)
		if m > 0:
			var s = surf_y(x)
			ymin = s - 2 if ymin < 0 else min(ymin, s - 2)
			ymax = max(ymax, s + m + 2)
		if ymin >= 0:
			_need(need, x0, x - 2, ymin - 2, x + 2, ymax + 2)
	var fb := front.get_data()
	var ab := aux.get_data()
	var nb := need.get_data()
	var lv := _lut_v
	var la := _lut_a
	var lk_arr := link
	var hm := H - 1
	var w := W
	var xo := ox
	var i := nb.find(255)
	while i >= 0:
		var y := i / cw
		var c := i - y * cw
		var r0 := y * lw + c + 1
		var rm := r0 - lw if y > 0 else r0
		var rp := r0 + lw if y < hm else r0
		var p0: int = P[r0]
		var acc: int = P[rm - 1] + 2 * P[rm] + P[rm + 1] + 2 * P[r0 - 1] + 4 * p0 + 2 * P[r0 + 1] + P[rp - 1] + 2 * P[rp] + P[rp + 1]
		var s: int = sy[c]
		var o := i * 4
		fb[o] = lv[acc & 255]
		fb[o + 1] = 255 if y >= s else 0
		fb[o + 2] = 255 if ((p0 & 1) == 1 and y <= s + 1 and y >= gy[c]) else 0
		ab[o] = lv[(acc >> 8) & 255]
		ab[o + 1] = lv[(acc >> 16) & 255]
		var xl := x0 + c - xo
		ab[o + 2] = 255 if (xl >= 0 and xl < w and (p0 & 0x101) == 0 and lk_arr[y * w + xl] == 1) else 0
		ab[o + 3] = la[(acc >> 24) & 255]
		i = nb.find(255, i + 1)
	front.set_data(cw, H, false, Image.FORMAT_RGBA8, fb)
	aux.set_data(cw, H, false, Image.FORMAT_RGBA8, ab)
	var pair = [front, aux]
	_chunk_img[k] = pair
	return pair


# Mark cells xa..xb, ya..yb (world) of the chunk starting at column x0 for working out.
func _need(need: Image, x0: int, xa: int, ya: int, xb: int, yb: int) -> void:
	xa = max(xa, x0)
	xb = min(xb, x0 + need.get_width() - 1)
	ya = max(ya, 0)
	yb = min(yb, H - 1)
	if xa <= xb and ya <= yb:
		need.fill_rect(Rect2i(xa - x0, ya, xb - xa + 1, yb - ya + 1), Color(1, 1, 1, 1))


# The bytes Image.set_pixel stores for the smoothed masks (it truncates), so the fast path writes exactly what it would.
func _make_lut() -> void:
	var im = Image.create_empty(17, 1, false, Image.FORMAT_RGBA8)
	for v in 17:
		im.set_pixel(v, 0, Color(v / 16.0, 0, 0, 1.0 - v / 16.0))
	var d = im.get_data()
	_lut_v.resize(17)
	_lut_a.resize(17)
	for v in 17:
		_lut_v[v] = d[v * 4]
		_lut_a[v] = d[v * 4 + 3]


# _cellp values of n columns from world column xa, all rows (n x H). Beyond _cellp the ground is untouched.
func _cells(xa: int, n: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var c0 = xa - (ox - PM)
	if c0 >= 0 and c0 + n <= PW:
		for y in H:
			var b = y * PW + c0
			out.append_array(_cellp.slice(b, b + n))
		return out
	out.resize(n * H)
	for i in n:
		var ci = c0 + i
		if ci >= 0 and ci < PW:
			for y in H:
				out[y * n + i] = _cellp[y * PW + ci]
		else:
			var col = _pristine_col(xa + i)
			for y in H:
				out[y * n + i] = col[y]
	return out


# Per column of chunk k: R = surface y / 255 (mound included), G = original ground y / 255,
# B = strata wave offset ((off + 8) / 16). The shaders use these for strata and the mound.
func chunk_surf_image(k: int) -> Image:
	var cw = CHUNK + 2 * PAD
	var img = Image.create_empty(cw, 1, false, Image.FORMAT_RGBA8)
	for c in cw:
		var x = k * CHUNK - PAD + c
		img.set_pixel(c, 0, Color(surf_y(x) / 255.0, base_y(x) / 255.0, clamp((strata_off(x) + 8.0) / 16.0, 0.0, 1.0), 1))
	return img


# Repaint cells x0..x1, y0..y1 (and a ring of one) of chunk k's images after a dig.
func _paint(pair: Array, k: int, x0: int, y0: int, x1: int, y1: int) -> void:
	var cx0 = k * CHUNK - PAD
	var cw = CHUNK + 2 * PAD
	var xa = max(cx0, x0 - 1)
	var xb = min(cx0 + cw - 1, x1 + 1)
	var ya = max(0, y0 - 1)
	var yb = min(H - 1, y1 + 1)
	if xa > xb or ya > yb:
		return
	var P := _cellp
	var lw := PW
	var lx := ox - PM
	if xa - 1 < lx or xb + 1 >= lx + PW:
		lw = xb - xa + 3
		lx = xa - 1
		P = _cells(lx, lw)
	var front: Image = pair[0]
	var aux: Image = pair[1]
	for x in range(xa, xb + 1):
		var s = surf_y(x)
		var g0 = base_y(x)
		var lc = x - lx
		var inw = x >= ox and x < ox + W
		for y in range(ya, yb + 1):
			var r0 = y * lw + lc
			var rm = r0 - lw if y > 0 else r0
			var rp = r0 + lw if y < H - 1 else r0
			var p0 = P[r0]
			var acc = P[rm - 1] + 2 * P[rm] + P[rm + 1] + 2 * P[r0 - 1] + 4 * p0 + 2 * P[r0 + 1] + P[rp - 1] + 2 * P[rp] + P[rp + 1]
			var u = 1.0 if y >= s else 0.0
			var g = 1.0 if ((p0 & 1) == 1 and y <= s + 1 and y >= g0) else 0.0
			var lk = 1.0 if (inw and (p0 & 0x101) == 0 and link[y * W + (x - ox)] == 1) else 0.0
			front.set_pixel(x - cx0, y, Color((acc & 255) / 16.0, u, g, 1.0))
			aux.set_pixel(x - cx0, y, Color(((acc >> 8) & 255) / 16.0, ((acc >> 16) & 255) / 16.0, lk, 1.0 - ((acc >> 24) & 255) / 16.0))


# New shaft at column x down to chamber depth, then a gallery back toward the
# main shaft until it meets existing tunnels.
func add_entrance(x: int) -> void:
	x = int(clamp(x, arena_l + 12, arena_r - 12))
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
	dist_home = _bfs(home, -1, dist_home)     # rebuilt in place: a fresh 5 MB array each time costs page faults
	dist_exit = _bfs(exits, -1, dist_exit)
	nav_dirty = false


# Breadth-first distance over both planes. Sources are Vector2 (front plane) or
# Vector3 (x, y, plane). Planes connect only through holes (link).
# into: an old field to write over (it is changed for whoever else holds it); empty = a new array.
func _bfs(sources: Array, max_d: int = -1, into: PackedInt32Array = PackedInt32Array()) -> PackedInt32Array:
	var dist: PackedInt32Array
	if into.size() == PLANES * WH:
		dist = into
		dist.fill(-1)
	else:
		dist = _neg.duplicate()     # Godot 4 shares packed arrays on assignment: copy, never write into _neg
	var queue := PackedInt32Array()
	for s in sources:
		var sz = int(s.z) if typeof(s) == TYPE_VECTOR3 else 0
		if not inb(int(s.x), int(s.y)):
			continue
		var si = _i(int(s.x), int(s.y), sz)
		if dist[si] != 0:
			dist[si] = 0
			queue.append(si)
	# Each cell's walkable neighbours are bits of _nbm, so a step looks only at the cells it can enter (on the surface,
	# thousands of cells long on the 3072-column world, that is two of the eight). Typed: this runs every NAV_INTERVAL.
	var nb: PackedByteArray = _nbm
	var ob: PackedInt32Array = _nb_off
	var wk: PackedByteArray = walk
	var lk: PackedByteArray = link
	var wh: int = WH
	var cap: int = max_d if max_d >= 0 else (1 << 30)
	var head: int = 0
	var tail: int = queue.size()
	while head < tail:
		var i: int = queue[head]
		head += 1
		var nd: int = dist[i] + 1
		if nd > cap:
			continue        # depth cap: cells past it stay -1
		var m: int = nb[i]
		while m != 0:
			var b: int = m & -m
			m ^= b
			var j: int = i + ob[b]
			if dist[j] == -1:
				dist[j] = nd
				queue.append(j)
				tail += 1
		var r: int = i - wh if i >= wh else i
		if lk[r] == 1:
			var j3: int = r if i >= wh else wh + r
			if wk[j3] == 1 and dist[j3] == -1:
				dist[j3] = nd
				queue.append(j3)
				tail += 1
	return dist
