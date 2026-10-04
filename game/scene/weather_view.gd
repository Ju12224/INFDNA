extends Node2D
# Weather as the owner drew it: rain streaks and the splashes where they land, falling snowflakes, snow lying on the meadow, puddles
# that dry out, and leaves coming off the trees in autumn. All of it is a function of the sim (sim.rain, sim.wet) and the year
# (colony.day: season, snow, autumn, leaf); nothing here feeds back into the sim.
#
# Two parts. _draw() (this node, z 55) is the air: streaks, flakes and falling leaves. Every drop belongs to a depth lane and lands on
# that lane's ground line (band.gd), so the rain stops at the meadow and never falls into the nest. draw_lane(it, n) is called by
# surface_view for every lane, back to front, and puts the ground decals (snow, puddles) at the right depth among the trees and rocks.
# Drops are not nodes: one draw_texture_rect each, about 250 at the very most. A drop's lap is hashed from its index and its lap number
# (a table of fixed random numbers, so it is cheap), so nothing repeats. The ground is sampled once a frame into a table and the lanes'
# scale, rise and fade once a frame into arrays. Pictures: art/weather (rain, splash, flake, snow_cap, puddle) and art/leaves; a picture
# that is missing is left out. `wind` (signed, + = to the right) and `gust` (0..1) are read by ambience.gd so the sound follows the eye.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WF = preload("res://core/world_features.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const RAIN_MAX = 150          # streaks at full rain
const FLAKE_MAX = 150         # flakes at full snowfall
const LEAVES_PER_TREE = 70    # at most, for the biggest crowns
const LEAVES_MAX = 90
const SLANT = 0.45            # radians from straight down: how the owner's streaks lean (they fall toward the lower left)
const FALL = 0.8              # share of a streak's lap spent falling; the rest is its splash
const RAIN_LEN = 80.0         # screen px height of the nearest streak at zoom 1
const SPLASH_W = 30.0         # world px width of the nearest splash, at its widest
const FLAKE_PX = 30.0         # screen px width of the nearest flake (flakes are in screen space: zoom and pan never move them)
const SNOW_W = 90.0           # world px width of a lying-snow piece in the front lane
const SNOW_LIMIT = 8          # pieces per lane at most: zoomed out they grow instead of multiplying
const PUDDLE_W = 120.0
const PUDDLE_SPAN = 340.0     # world px between puddle slots (a lane's x axis)
const LEAF_W = 34.0
const TREE_MARGIN = 420.0     # world px past the screen whose trees still shed leaves into it
const TAB_MARGIN = 700.0      # world px either side of the screen the ground table covers
const FAR_FROM = 7.0          # surface_view bends the back lanes' ground from this lane number on (its FAR_FROM)
const TREES_FALLBACK = [[0.30, "oak1", 0.88], [0.58, "oak2", 0.88], [0.68, "mossoak", 0.55], [0.76, "acacia", 0.4], [0.82, "grove", 0.5],
	[0.93, "spruce", 0.95], [0.97, "stump", 0.38], [1.0, "log", 0.16]]

var colony
var wind := 0.0               # signed, roughly -1 .. 1; + blows to the right
var gust := 0.3               # 0..1 how hard it blows (more in rain and winter)
var sprites := 0              # drawn in the air this frame, on the ground (lane_sprites), and the script time each took (tests look)
var lane_sprites := 0
var air_us := 0
var lane_us := 0
var debug := false            # tests: _t stands still and flake_log gets every flake's screen position
var flake_log := {}                # flake index -> screen position

var _t := 0.0
var _was := false
var _surf                     # the surface view (ground height, lane ground)
var _has_lane_ground := false
var _rain_tex: Array = []
var _splash_tex: Array = []
var _flake_tex: Array = []
var _leaf_tex: Array = []
var _cap: Texture2D
var _puddle: Texture2D
var _precip := 0.0            # 0..1 how hard it is raining or snowing
var _snowing := false
var _leaf_rate := 0.0         # 0..1 how many leaves are coming down
var _trees := []              # leafy trees near the screen: {x, lane, gy, canopy (rect relative to the foot), sid}
var _trees_x := -1e9
var _trees_age := 99.0
var _pick := TREES_FALLBACK
var _tree_defs := {}
var _ht := PackedFloat32Array()      # 8192 fixed random numbers: _hi() picks from them
var _rk := PackedFloat32Array()      # per streak / flake: seconds a lap takes, and the lap's phase
var _rp := PackedFloat32Array()
var _fk := PackedFloat32Array()
var _fp := PackedFloat32Array()
var _fq := PackedInt32Array()        # a flake's lane number never changes: its speed and size come from it
var _sp := PackedFloat32Array()      # the splashes of this frame, 6 floats each (x, y, w, h, alpha, picture)
var _tab_frame := -1                 # the tables below are built once a frame
var _view := Rect2()
var _tab := PackedFloat32Array()     # the ground's y every _tab_step px from _tab_x0
var _tab_x0 := 0.0
var _tab_step := 32.0
var _lraise := PackedFloat32Array()  # by lane number 1..LANES: how high its ground line stands, its scale, its fade
var _lpers := PackedFloat32Array()
var _lalpha := PackedFloat32Array()


func _ready() -> void:
	var man = Art.manifest("weather/weather_manifest.json")
	_rain_tex = _load_list(man.get("rain", []))
	_splash_tex = _load_list(man.get("splash", []))
	_flake_tex = _load_list(man.get("flake", []))
	var caps = _load_list(man.get("snow_cap", []))
	_cap = caps[0] if caps.size() > 0 else null
	var pud = _load_list(man.get("puddle", []))
	_puddle = pud[0] if pud.size() > 0 else null
	for i in 12:
		var t = Art.tex("leaves/leaf_%d.png" % i)
		if t != null:
			_leaf_tex.append(t)
	for t in Art.manifest("art_manifest.json").get("trees", []):
		_tree_defs[t["name"]] = t
	var rng := RandomNumberGenerator.new()
	rng.seed = 7311
	_ht.resize(8192)
	for i in 8192:
		_ht[i] = rng.randf()
	_rk.resize(RAIN_MAX)
	_rp.resize(RAIN_MAX)
	for k in RAIN_MAX:
		_rk[k] = 0.66 + 0.4 * _ht[(k * 7 + 3) & 8191]
		_rp[k] = _ht[(k * 13 + 5) & 8191]
	_fk.resize(FLAKE_MAX)
	_fp.resize(FLAKE_MAX)
	_fq.resize(FLAKE_MAX)
	for k in FLAKE_MAX:
		var q = 1 + int(pow(_ht[(k * 19 + 41) & 8191], 1.6) * Band.LANES)       # more of them near the camera
		_fq[k] = q
		_fk[k] = (6.0 + 5.0 * _ht[(k * 11 + 17) & 8191]) * (0.75 + 0.6 * (1.0 - Band.persp(Band.lane_of(float(q)))))    # far flakes drift slower
		_fp[k] = _ht[(k * 17 + 29) & 8191]
	_sp.resize(RAIN_MAX * 6)
	for a in [_lraise, _lpers, _lalpha]:
		a.resize(Band.LANES + 1)
	_wind_at(0.0)


func _load_list(entries: Array) -> Array:
	var out := []
	for e in entries:
		var t = Art.tex(str(e.get("file", "")))
		if t != null:
			out.append(t)
	return out


# One of the fixed random numbers, picked by two whole numbers and a salt (0..1).
func _hi(i: int, j: int, s: int) -> float:
	var x = (i * 73856093) ^ (j * 19349663) ^ (s * 83492791)
	return _ht[(x ^ (x >> 13)) & 8191]


func reset() -> void:
	_trees.clear()
	_trees_age = 99.0


func _wind_at(t: float) -> void:
	var s = 0.55 * sin(t * 0.23) + 0.30 * sin(t * 0.61 + 1.7) + 0.15 * sin(t * 1.9 + 0.4)
	var d = colony.day if colony != null else null
	var rain = colony.sim.rain if colony != null and colony.sim != null else 0.0
	var winter = 1.0 if d != null and d.season == 3 else 0.0
	gust = clampf(0.25 + 0.45 * rain + 0.2 * winter + 0.2 * (0.5 + 0.5 * sin(t * 0.31) * sin(t * 0.17 + 1.0)), 0.0, 1.0)
	wind = (-0.3 + 0.75 * s) * (0.4 + 0.9 * gust)


func _process(delta: float) -> void:
	if colony == null or colony.sim == null:
		return
	if not debug:
		_t += delta
	_trees_age += delta
	lane_us = 0
	lane_sprites = 0
	_surf = colony.views.get("surface")
	_has_lane_ground = _surf != null and _surf.has_method("lane_ground")
	_wind_at(_t)
	var d = colony.day
	var rain: float = colony.sim.rain
	_snowing = d.season == 3
	_precip = maxf(rain, 0.5 * d.snow) if _snowing else rain
	if _precip < 0.02:
		_precip = 0.0
	_leaf_rate = clampf(d.autumn * (0.25 * d.leaf + 4.0 * d.leaf * (1.0 - d.leaf)), 0.0, 1.0)
	# (a canvas keeps its last drawing until it is told to redraw, so the frame after the weather goes quiet is drawn too)
	var on = _precip > 0.0 or _leaf_rate > 0.01
	if on or _was:
		queue_redraw()
	_was = on


# Once a frame, when something first needs them: the screen, the ground's height along it, and each lane's rise, scale and fade.
func _ensure_tables() -> void:
	var fr = Engine.get_process_frames()
	if fr == _tab_frame:
		return
	_tab_frame = fr
	_view = colony.view_rect(0.0)
	# the samples stand on a fixed grid in the world (its spacing only ever doubles or halves), so panning never moves them
	var span = _view.size.x + 2.0 * TAB_MARGIN
	_tab_step = 32.0 * pow(2.0, ceil(log(maxf(span / 90.0 / 32.0, 1.0)) / log(2.0)))
	_tab_x0 = floor((_view.position.x - TAB_MARGIN) / _tab_step) * _tab_step
	var n = int(ceil((_view.end.x + TAB_MARGIN - _tab_x0) / _tab_step)) + 2
	_tab.resize(n)
	var flat: float = colony.ground_y()
	for i in n:
		_tab[i] = _surf.ground_y(_tab_x0 + i * _tab_step) if _surf != null else flat
	for q in range(1, Band.LANES + 1):
		var lane = Band.lane_of(float(q))
		_lraise[q] = Band.raise(lane)
		_lpers[q] = Band.persp(lane)
		_lalpha[q] = Band.lane_alpha(lane)


# The ground's y at world x, from the table.
func _gt(x: float) -> float:
	var f = (x - _tab_x0) / _tab_step
	var i = clampi(int(f), 0, _tab.size() - 2)
	return lerpf(_tab[i], _tab[i + 1], clampf(f - i, 0.0, 1.0))


# Screen-sized things (rain, snow) shrink a little as the camera dollies in, so they stay in proportion at any zoom.
func _zscale(p: float, lo: float, hi: float) -> float:
	return clampf(pow(colony.zoom(), -p), lo, hi)


func _draw() -> void:
	sprites = 0
	if colony == null or colony.sim == null:
		return
	var t0 = Time.get_ticks_usec()
	_ensure_tables()
	# the weather is bright, but not above the night: it takes most of the scenery's tint
	var col: Color = Color.WHITE.lerp(colony.day.tint, 0.8)
	if _precip > 0.0:
		if _snowing:
			_snowfall(col)
		else:
			_rain(col)
	if _leaf_rate > 0.01 and not _leaf_tex.is_empty():
		_leaves()
	air_us = Time.get_ticks_usec() - t0


# ---- rain ------------------------------------------------------------------------------------------------------------------------

func _rain(col: Color) -> void:
	if _rain_tex.is_empty():
		return
	var view = _view
	var r = _precip
	var n = int(ceil(RAIN_MAX * r))
	var a = SLANT - wind * 0.3
	var tan_a = tan(a)
	var rot = -wind * 0.3
	var cs = cos(rot)
	var sn = sin(rot)
	var top = view.position.y
	var bot = view.end.y
	var left = view.position.x
	var span = view.size.x + tan_a * view.size.y
	var show = minf(1.0, r * 2.2)
	var zs = _zscale(0.5, 0.5, 1.2)
	var nr = _rain_tex.size()
	var ns = _splash_tex.size()
	var nsp = 0
	var n_f = RAIN_MAX * r
	draw_set_transform(Vector2.ZERO, rot, Vector2.ONE)       # every streak leans with the wind; positions below are in that turned frame
	for k in n:
		var ph = _t / _rk[k] + _rp[k]
		var cyc = int(ph)
		var f = ph - cyc
		var q = 1 + int(_hi(k, cyc, 2) * Band.LANES)
		var la = _lalpha[q]
		if la <= 0.004:
			continue
		var xs = left + _hi(k, cyc, 1) * span
		var raise = _lraise[q]
		var g = _gt(xs) - raise
		var gx = xs - tan_a * (g - top)
		g = _gt(gx) - raise
		if g < top:
			continue                                   # the ground is above the screen (the camera is underground)
		var landing = g < bot
		var pers = _lpers[q]
		var v = _hi(k, cyc, 3)
		if f < FALL:
			var tex: Texture2D = _rain_tex[int(v * 7.77) % nr]
			var sh = RAIN_LEN * pers * zs * (0.8 + 0.4 * v)
			var sw = sh * tex.get_width() / tex.get_height()
			var y_end = g if landing else bot + sh
			var y = top + (y_end - top) * (f / FALL)
			var x = xs - tan_a * (y - top)
			var c = col
			c.a = (0.45 + 0.027 * (Band.LANES - q)) * show * la * smoothstep(0.0, 0.1, f) * clampf(n_f - k, 0.0, 1.0)
			# the picture's foot (a little in from its left edge) goes at (x, y)
			draw_texture_rect(tex, Rect2(x * cs + y * sn - 0.2 * sw, y * cs - x * sn - sh, sw, sh), false, c)
			sprites += 1
		elif landing and ns > 0:
			var p = (f - FALL) / (1.0 - FALL)
			var w = SPLASH_W * pers * (0.5 + 0.6 * p) * (0.75 + 0.5 * v)
			var o = nsp * 6
			_sp[o] = gx
			_sp[o + 1] = g
			_sp[o + 2] = w
			_sp[o + 3] = pow(1.0 - p, 1.3) * (0.6 + 0.4 * (1.0 - q / float(Band.LANES))) * show * la * clampf(n_f - k, 0.0, 1.0)
			_sp[o + 4] = float(int(v * 5.31) % ns)
			nsp += 1
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for j in nsp:
		var o2 = j * 6
		var tex2: Texture2D = _splash_tex[int(_sp[o2 + 4])]
		var w2 = _sp[o2 + 2]
		var h2 = w2 * tex2.get_height() / tex2.get_width()
		var c2 = col
		c2.a = _sp[o2 + 3]
		draw_texture_rect(tex2, Rect2(_sp[o2] - 0.5 * w2, _sp[o2 + 1] - 0.88 * h2, w2, h2), false, c2)
		sprites += 1


# ---- snowfall --------------------------------------------------------------------------------------------------------------------

func _snowfall(col: Color) -> void:
	if _flake_tex.is_empty():
		return
	# Flakes live in screen space: a flake's place on the screen is a function of the clock, its own numbers and the window's size alone,
	# never of the zoom or where the camera is, so nothing jumps or reshuffles when the player zooms or pans. They are only turned into
	# world coordinates to be drawn, and to stop at the ground (a flake lands, and fades, at its lane's ground line).
	var view = _view
	var z = colony.zoom()
	var vw = view.size.x * z                            # the window in screen px
	var vh = view.size.y * z
	var n_f = FLAKE_MAX * _precip
	var n = int(ceil(n_f))
	var drift = wind * 0.5                              # screen x per screen y: the wind carries the flakes along
	var show = clampf(_precip * 1.8, 0.5, 1.0)
	var nt = _flake_tex.size()
	if debug:
		flake_log.clear()
	for k in n:
		var q = _fq[k]
		var pers = _lpers[q]                            # (no lane fade: flakes are in the air, whatever the dolly has cut from the ground)
		var ph = _t / _fk[k] + _fp[k]
		var cyc = int(ph)
		var f = ph - cyc
		var v = _hi(k, cyc, 9)
		var size = FLAKE_PX * pers * (0.75 + 0.5 * v)   # screen px
		var ys = -size + f * (vh + 2.0 * size)
		var xs = _hi(k, cyc, 7) * vw - drift * vh * 0.5 + drift * ys + sin(f * TAU * (2.0 + 2.0 * v) + k) * 14.0 * pers
		var p = view.position + Vector2(xs, ys) / z
		var above = (_gt(p.x) - _lraise[q] - p.y) * z   # screen px between the flake and its lane's ground
		if above <= 0.0:
			continue
		if debug:
			flake_log[k] = Vector2(xs, ys)
		var tex: Texture2D = _flake_tex[int(v * 13.7) % nt]
		var w = size / z
		var h = w * tex.get_height() / tex.get_width()
		var c = col
		c.a = (0.6 + 0.025 * (Band.LANES - q)) * show * smoothstep(0.0, 40.0, above) * clampf(n_f - k, 0.0, 1.0)
		draw_set_transform(p, f * TAU * (0.4 * v - 0.2) + sin(f * 9.0 + k) * 0.3, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-0.5 * w, -0.5 * h, w, h), false, c)
		sprites += 1
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- falling leaves --------------------------------------------------------------------------------------------------------------

static func _hs(a: float) -> float:
	return fmod(abs(sin(a * 12.9898) * 43758.5453), 1.0)


# The leafy trees near the screen, found the way surface_view finds them, with the box of their crown relative to their foot.
func _refresh_trees() -> void:
	var view = _view
	_trees_age = 0.0
	_trees_x = view.get_center().x
	_trees.clear()
	if _surf != null and _surf.get_script() != null:
		var cm = _surf.get_script().get_script_constant_map()
		if cm.has("TREE_PICK"):
			_pick = cm["TREE_PICK"]
	var C = WorldGrid.CELL
	var x0 = int(floor((view.position.x - TREE_MARGIN - 600.0) / C))
	var x1 = int(ceil((view.end.x + TREE_MARGIN + 600.0) / C))
	for f in WF.in_range(colony.sim.seed_base, x0, x1, int(colony.grid.entrance.x)):
		if f["kind"] != "tree" or f["x"] < x0 or f["x"] > x1:
			continue
		var sd: float = f["seed"]
		var r = _hs(sd + 99.0)
		var pick = _pick[_pick.size() - 1]
		for p in _pick:
			if r < p[0]:
				pick = p
				break
		var def = _tree_defs.get(pick[1])
		if def == null or not def.get("leafy", false):
			continue
		var lane: float = f["lane"]
		var hgt: float = f["h"] * Band.persp(lane) * pick[2]
		var size = Vector2(hgt * float(def["w"]) / float(def["h"]), hgt)
		var foot = def.get("foot", [0.5, 1.0])
		var c = def.get("canopy", [0.1, 0.1, 0.9, 0.7])
		var flip = _hs(sd + 3.0) > 0.5
		var left = -((1.0 - foot[0]) if flip else foot[0]) * size.x          # the picture's left edge, relative to the foot
		var cx0 = (1.0 - c[2]) if flip else c[0]
		var cx1 = (1.0 - c[0]) if flip else c[2]
		var rect = Rect2(left + cx0 * size.x, (c[1] - foot[1]) * size.y, (cx1 - cx0) * size.x, (c[3] - c[1]) * size.y)
		var px = (f["x"] + 0.5) * C
		_trees.append({"x": px, "lane": lane, "num": Band.num(lane), "gy": _surf.ground_y(px) if _surf != null else colony.ground_y(), "canopy": rect,
			"sid": int(sd * 1000.0) & 0xFFFFF})


func _ensure_trees() -> void:
	if _trees_age > 0.5 or absf(_view.get_center().x - _trees_x) > 250.0:
		_refresh_trees()


func _leaves() -> void:
	var view = _view
	_ensure_trees()
	var vr = view.grow(60.0)
	var drawn = 0
	var nl = _leaf_tex.size()
	var tint: Color = colony.day.tint
	for tr in _trees:
		var lane: float = tr["lane"]
		var la = Band.lane_alpha(lane, true)
		if la <= 0.004:
			continue
		var cr: Rect2 = tr["canopy"]
		var tx: float = tr["x"]
		if tx + cr.end.x < view.position.x - TREE_MARGIN or tx + cr.position.x > view.end.x + TREE_MARGIN:
			continue
		var pers = Band.persp(lane)
		var base_y = Band.lane_y(tr["gy"], lane)
		var sid: int = tr["sid"]
		for k in clampi(int(cr.size.x * 0.06), 10, LEAVES_PER_TREE):
			var s2 = sid + k * 131
			var period = 16.0 + 8.0 * _hi(sid, k, 1)
			var ph = _t / period + _hi(sid, k, 2)
			var cyc = int(ph)
			if _hi(s2, cyc, 3) > _leaf_rate:
				continue                                    # this lap no leaf comes off
			var tl = (ph - cyc) * period                    # seconds into this lap
			var sx = tx + cr.position.x + cr.size.x * (0.1 + 0.8 * _hi(s2, cyc, 4))
			var sy = base_y + cr.position.y + cr.size.y * (0.2 + 0.7 * _hi(s2, cyc, 5))
			var dist = base_y - sy
			if dist < 4.0:
				continue
			var spd = maxf((60.0 + 40.0 * _hi(s2, cyc, 6)) * (0.5 + 0.5 * pers), dist / (period - 3.0))
			var fall_t = dist / spd
			var t0 = period - 3.0 - fall_t                  # it hangs on until here, then lets go
			var tf = tl - maxf(t0, 0.0)
			if tf < 0.0 or tf > fall_t + 3.0:
				continue
			var air = minf(tf, fall_t)
			var qv = _hi(s2, cyc, 7)
			var x = sx + wind * 55.0 * pers * air + sin(air * 1.3 + k) * 20.0 * pers + cos(air * 2.1 + qv * 9.0) * 6.0 * pers
			var y = sy + spd * air + sin(air * 2.3 + qv * 9.0) * 5.0 * pers
			var landed = tf > fall_t
			if landed:
				y = base_y + 1.0
			if not vr.has_point(Vector2(x, y)):
				continue
			var tex: Texture2D = _leaf_tex[int(qv * 9.99) % nl]
			var w = LEAF_W * pers * (0.75 + 0.5 * _hi(s2, cyc, 8))
			var h = w * tex.get_height() / tex.get_width()
			var flutter = 0.35 + 0.65 * absf(cos(air * 2.6 + qv * 20.0))
			var rot = sin(air * 1.7 + qv * 9.0) * 0.9 + wind * 0.5
			var c = tint
			c.a = la * (1.0 - smoothstep(fall_t + 1.0, fall_t + 3.0, tf))
			if landed:
				flutter = 0.45
				rot = qv * 6.0
			draw_set_transform(Vector2(x, y), rot, Vector2(1.0, flutter))
			draw_texture_rect(tex, Rect2(-0.5 * w, -0.5 * h, w, h), false, c)
			sprites += 1
			drawn += 1
			if drawn >= LEAVES_MAX:
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- on the ground: lying snow and puddles (called by surface_view for each lane, back to front) ---------------------------------

func draw_lane(it: CanvasItem, n: int) -> void:
	if colony == null or colony.sim == null:
		return
	var d = colony.day
	var pw: float = colony.sim.wet
	if d.season == 0:
		pw = maxf(pw, 0.8 * d.snow)                         # the thaw leaves puddles
	var snow_on = d.snow > 0.03 and _cap != null
	var pud_on = pw > 0.04 and d.season != 3 and _puddle != null
	if not (snow_on or pud_on):
		return
	var t0 = Time.get_ticks_usec()
	_ensure_tables()
	var la = _lalpha[n]
	if la > 0.004 or snow_on:
		var lane = Band.lane_of(float(n))
		if snow_on and la > 0.004 and n % 2 == 1:
			_snow_row(it, n, la, d.snow)
		if snow_on:
			_tree_snow(it, n, d.snow)
		if pud_on and la > 0.004:
			_puddles(it, n, lane, la, pw)
		it.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	lane_us += Time.get_ticks_usec() - t0


# The y of lane n's ground line at world x: the table where the lanes stand on the ground as it is, surface_view's own for the back ones.
func _lane_ground(px: float, n: int) -> float:
	if n > FAR_FROM and _has_lane_ground:
		return _surf.lane_ground(px, float(n)) - _lraise[n]
	return _gt(px) - _lraise[n]


# Snow lying in this lane: rows of the owner's snow pieces that grow as the snow comes (patchy at first) and shrink when it melts. Zoomed
# out the pieces would be too many, so the row is also laid in coarser levels, each twice as wide as the one before and on its own fixed
# grid; while the zoom is between two levels each piece of the next one grows (and each of the last one shrinks) at its own moment, so
# nothing slides, pops or turns see-through as the zoom changes.
func _snow_row(it: CanvasItem, n: int, la: float, sn: float) -> void:
	var wb = SNOW_W * _lpers[n]
	var wmin = _view.size.x / (SNOW_LIMIT * 0.62)
	var lv = maxf(log(wmin / wb) / log(2.0), 0.0)
	var lf = int(floor(lv))
	var s = lv - lf
	_snow_level(it, n, la, sn, wb * (1 << lf), lf, 1.0 - smoothstep(0.55, 1.0, s))
	if s > 0.002:
		_snow_level(it, n, la, sn, wb * (2 << lf), lf + 1, smoothstep(0.0, 0.45, s))


func _snow_level(it: CanvasItem, n: int, la: float, sn: float, w: float, level: int, fade: float) -> void:
	if fade <= 0.004:
		return
	var view: Rect2 = _view.grow(w)
	var step = w * 0.62
	var hh = 0.85 * w * _cap.get_height() / _cap.get_width()
	var col: Color = colony.day.tint
	col.a = la
	var i0 = int(floor(view.position.x / step))
	var i1 = int(ceil(view.end.x / step))
	var key = n + 16 * level
	for i in range(i0, i1 + 1):
		var a = _hi(i, key, 1)
		var m = clampf((fade - _hi(i, key, 3) * 0.75) * 4.0, 0.0, 1.0)      # this piece's own moment in the change of level
		var k = clampf((sn * 1.3 - a * 0.9) * 3.0, 0.0, 1.0)                # how deep the snow lies here
		if m * k < 0.12:
			continue                                      # (a flatter piece would only show its outline: a thin line)
		var b = _hi(i, key, 2)
		var x = (i + 0.5 + (b - 0.5) * 0.7) * step
		var gy = _lane_ground(x, n) + (a - 0.5) * hh * 0.5
		var sw = w * (0.75 + 0.6 * b) * m * (0.5 + 0.5 * k)
		var sh = hh * (0.65 + 0.55 * a) * m * k
		var rect = Rect2(x - 0.5 * sw, gy - 0.82 * sh, sw, sh)
		if a > 0.5:
			it.draw_set_transform(Vector2(x * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))
			it.draw_texture_rect(_cap, rect, false, col)
			it.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			it.draw_texture_rect(_cap, rect, false, col)
		lane_sprites += 1


# Snow on the crowns of the leafy trees standing in lane n (drawn right after the trees, so it sits on them): a cap on top and one on
# each shoulder, growing with the snow.
func _tree_snow(it: CanvasItem, n: int, sn: float) -> void:
	_ensure_trees()
	var grow = smoothstep(0.05, 0.9, sn)
	if grow <= 0.15:
		return                                             # (flatter caps would only show their outline)
	var aspect = _cap.get_height() / float(_cap.get_width())
	for tr in _trees:
		if ceili(tr["num"] - 0.0001) != n:
			continue
		var la = Band.lane_alpha(tr["lane"], true)
		if la <= 0.004:
			continue
		var cr: Rect2 = tr["canopy"]
		var base = Vector2(tr["x"], Band.lane_y(tr["gy"], tr["lane"]))
		var col: Color = colony.day.tint
		col.a = la
		# [centre across the crown, bottom edge down the crown, width as a share of the crown]
		for cap in [[0.5, 0.2, 0.62], [0.2, 0.4, 0.34], [0.8, 0.4, 0.34]]:
			var w = cr.size.x * cap[2] * (0.6 + 0.4 * grow)
			var h = w * aspect * grow * 1.2
			var x = base.x + cr.position.x + cr.size.x * cap[0]
			var y = base.y + cr.position.y + cr.size.y * cap[1]
			it.draw_texture_rect(_cap, Rect2(x - 0.5 * w, y - 0.85 * h, w, h), false, col)
			lane_sprites += 1


# Puddles: slots along the lane, each with its own chance and size; they fill in the order of their size and dry the other way round.
func _puddles(it: CanvasItem, n: int, lane: float, la: float, pw: float) -> void:
	var view: Rect2 = _view.grow(PUDDLE_W * 2.0)
	var pers = _lpers[n]
	var tier = clampf(colony.zoom() * 1.6, 0.25, 1.0)        # zoomed far out only some of them are drawn
	var i0 = int(floor(view.position.x / PUDDLE_SPAN))
	var i1 = int(ceil(view.end.x / PUDDLE_SPAN))
	var ex = (colony.grid.entrance.x + 0.5) * WorldGrid.CELL
	var col: Color = colony.day.tint
	for i in range(i0, i1 + 1):
		var hc = _hi(i, n, 11)
		if hc < 0.55 or (hc - 0.55) / 0.45 > tier:
			continue
		var x = (i + _hi(i, n, 13)) * PUDDLE_SPAN
		if absf(x - ex) < 14.0 * WorldGrid.CELL:
			continue                                         # not in the nest's mouth
		var size = clampf((pw - (hc - 0.55) * 0.9) * 2.2, 0.0, 1.0)
		if size <= 0.02:
			continue
		var w = PUDDLE_W * (0.55 + 0.7 * _hi(i, n, 14)) * pers * size
		var h = w * _puddle.get_height() / _puddle.get_width()
		col.a = la * clampf(size * 1.6, 0.0, 1.0)
		var gy = _lane_ground(x, n)
		it.draw_texture_rect(_puddle, Rect2(x - 0.5 * w, gy - 0.45 * h, w, h), false, col)
		lane_sprites += 1
