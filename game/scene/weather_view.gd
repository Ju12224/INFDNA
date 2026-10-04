extends Node2D
# Weather as the owner drew it: rain streaks and the splashes where they land, falling snowflakes, snow lying on the meadow, puddles
# that dry out, and leaves coming off the trees in autumn. All of it is a function of the sim (sim.rain, sim.wet) and the year
# (colony.day: season, snow, autumn, leaf); nothing here feeds back into the sim.
#
# Two parts. _draw() (this node, z 55) is the air: streaks, flakes and falling leaves. Every drop belongs to a depth lane and lands on
# that lane's ground line (band.gd), so the rain stops at the meadow and never falls into the nest. draw_lane(it, n) is called by
# surface_view for every lane, back to front, and puts the ground decals (snow, puddles) at the right depth among the trees and rocks.
# Drops are not nodes: one draw_texture_rect each, about 250 at the very most. A drop's cycle is hashed from its index and its lap number,
# so nothing repeats. Pictures: art/weather (rain, splash, flake, snow_cap, puddle) and art/leaves. A picture that is missing is left out.
# `wind` (signed, + = to the right) and `gust` (0..1) are read by ambience.gd so the sound follows what the eye sees.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WF = preload("res://core/world_features.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const RAIN_MAX = 150          # streaks at full rain
const FLAKE_MAX = 110         # flakes at full snowfall
const LEAVES_PER_TREE = 70    # at most, for the biggest crowns
const LEAVES_MAX = 90
const SLANT = 0.45            # radians from straight down: how the owner's streaks lean (they fall toward the lower left)
const FALL = 0.8              # share of a streak's lap spent falling; the rest is its splash
const RAIN_LEN = 80.0         # screen px height of the nearest streak at zoom 1
const SPLASH_W = 30.0         # world px width of the nearest splash, at its widest
const FLAKE_W = 14.0          # world px width of the nearest flake
const SNOW_W = 150.0          # world px width of a lying-snow piece in the front lane
const SNOW_LIMIT = 12         # pieces per lane at most: zoomed out they grow instead of multiplying
const PUDDLE_W = 120.0
const PUDDLE_SPAN = 340.0     # world px between puddle slots (a lane's x axis)
const LEAF_W = 34.0
const TREE_MARGIN = 420.0     # world px past the screen whose trees still shed leaves into it
const TREES_FALLBACK = [[0.30, "oak1", 0.88], [0.58, "oak2", 0.88], [0.68, "mossoak", 0.55], [0.76, "acacia", 0.4], [0.82, "grove", 0.5],
	[0.93, "spruce", 0.95], [0.97, "stump", 0.38], [1.0, "log", 0.16]]

var colony
var wind := 0.0               # signed, roughly -1 .. 1; + blows to the right
var gust := 0.3               # 0..1 how hard it blows (more in rain and winter)

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
var _trees := []              # leafy trees near the screen: {x, lane, gy, canopy (rect relative to the foot), seed}
var _trees_x := -1e9
var _trees_age := 99.0
var _pick := TREES_FALLBACK
var _tree_defs := {}
var sprites := 0              # drawn this frame (tests look at it), and the script time it took, in microseconds
var air_us := 0
var lane_us := 0


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
	_wind_at(0.0)


func _load_list(entries: Array) -> Array:
	var out := []
	for e in entries:
		var t = Art.tex(str(e.get("file", "")))
		if t != null:
			out.append(t)
	return out


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


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
	_t += delta
	_trees_age += delta
	lane_us = 0
	_surf = colony.views.get("surface")
	_has_lane_ground = _surf != null and _surf.has_method("lane_ground")
	_wind_at(_t)
	var d = colony.day
	var rain: float = colony.sim.rain
	_snowing = d.season == 3
	_precip = maxf(rain, 0.22 * d.snow) if _snowing else rain
	if _precip < 0.02:
		_precip = 0.0
	_leaf_rate = clampf(d.autumn * (0.25 * d.leaf + 4.0 * d.leaf * (1.0 - d.leaf)), 0.0, 1.0)
	# (a canvas keeps its last drawing until it is told to redraw, so the frame after the weather goes quiet is drawn too)
	var on = _precip > 0.0 or _leaf_rate > 0.01
	if on or _was:
		queue_redraw()
	_was = on


# The world y of lane `lane`'s ground line at world x.
func _gline(px: float, lane: float) -> float:
	var g: float = _surf.ground_y(px) if _surf != null else colony.ground_y()
	return Band.lane_y(g, lane)


# Screen-sized things (rain, snow) shrink a little as the camera dollies in, so they stay in proportion at any zoom.
func _zscale(p: float, lo: float, hi: float) -> float:
	return clampf(pow(colony.zoom(), -p), lo, hi)


func _draw() -> void:
	sprites = 0
	var t0 = Time.get_ticks_usec()
	if colony == null or colony.sim == null:
		return
	var view: Rect2 = colony.view_rect(0.0)
	# the weather is bright, but not above the night: it takes most of the scenery's tint
	var col: Color = Color.WHITE.lerp(colony.day.tint, 0.8)
	if _precip > 0.0:
		if _snowing:
			_snowfall(view, col)
		else:
			_rain(view, col)
	if _leaf_rate > 0.01 and not _leaf_tex.is_empty():
		_leaves(view)
	air_us = Time.get_ticks_usec() - t0


# ---- rain ------------------------------------------------------------------------------------------------------------------------

func _rain(view: Rect2, col: Color) -> void:
	if _rain_tex.is_empty():
		return
	var r = _precip
	var n = int(ceil(RAIN_MAX * r))
	var a = SLANT - wind * 0.3
	var tan_a = tan(a)
	var rot = -wind * 0.3
	var top = view.position.y
	var bot = view.end.y
	var span = view.size.x + tan_a * view.size.y
	var show = minf(1.0, r * 2.2)
	var zs = _zscale(0.5, 0.5, 1.2)
	var nr = _rain_tex.size()
	var ns = _splash_tex.size()
	for k in n:
		var tk = 0.66 + 0.4 * _h(k * 3.1, 1.0)
		var ph = _t / tk + _h(k * 1.7, 2.0)
		var cyc = floorf(ph)
		var f = ph - cyc
		var u = _h(k + cyc * 0.37, 3.0)
		var lane = 0.02 + 0.98 * _h(k + cyc * 0.53, 4.0)
		var la = Band.lane_alpha(lane)
		if la <= 0.004:
			continue
		var v = _h(k + cyc * 0.71, 5.0)
		var xs = view.position.x + u * span
		var g = _gline(xs, lane)
		var gx = xs - tan_a * (g - top)
		g = _gline(gx, lane)
		if g < top:
			continue                                   # the ground is above the screen (the camera is underground)
		var landing = g < bot
		var pers = Band.persp(lane)
		if f < FALL:
			var tex: Texture2D = _rain_tex[int(v * 7.77) % nr]
			var sh = RAIN_LEN * pers * zs * (0.8 + 0.4 * v)
			var sw = sh * tex.get_width() / tex.get_height()
			var y_end = g if landing else bot + sh
			var y = top + (y_end - top) * (f / FALL)
			var x = xs - tan_a * (y - top)
			var c = col
			c.a = (0.45 + 0.4 * lane) * show * la * smoothstep(0.0, 0.1, f)
			draw_set_transform(Vector2(x, y), rot, Vector2.ONE)
			draw_texture_rect(tex, Rect2(-0.2 * sw, -sh, sw, sh), false, c)
			sprites += 1
		elif landing and ns > 0:
			var p = (f - FALL) / (1.0 - FALL)
			var tex2: Texture2D = _splash_tex[int(v * 5.31) % ns]
			var w = SPLASH_W * pers * (0.5 + 0.6 * p) * (0.75 + 0.5 * v)
			var h = w * tex2.get_height() / tex2.get_width()
			var c2 = col
			c2.a = pow(1.0 - p, 1.3) * (0.6 + 0.4 * lane) * show * la
			draw_set_transform(Vector2(gx, g), 0.0, Vector2.ONE)
			draw_texture_rect(tex2, Rect2(-0.5 * w, -0.88 * h, w, h), false, c2)
			sprites += 1
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- snowfall --------------------------------------------------------------------------------------------------------------------

func _snowfall(view: Rect2, col: Color) -> void:
	if _flake_tex.is_empty():
		return
	var r = _precip
	var n = int(ceil(FLAKE_MAX * r))
	var top = view.position.y
	var bot = view.end.y
	var sw_ = wind * 0.5                                # x per y: the wind carries the flakes along
	var zs = _zscale(0.35, 0.6, 1.1)
	var show = clampf(r * 1.8, 0.35, 1.0)
	var nf = _flake_tex.size()
	for k in n:
		var tk = 7.0 + 6.0 * _h(k * 2.3, 5.0)
		var ph = _t / tk + _h(k * 1.3, 6.0)
		var cyc = floorf(ph)
		var f = ph - cyc
		var u = _h(k + cyc * 0.37, 7.0)
		var lane = 0.02 + 0.98 * _h(k + cyc * 0.53, 8.0)
		var la = Band.lane_alpha(lane)
		if la <= 0.004:
			continue
		var v = _h(k + cyc * 0.71, 9.0)
		var x0 = view.position.x + u * view.size.x - sw_ * view.size.y * 0.5
		var g = _gline(x0 + sw_ * (view.size.y * 0.5), lane)
		if g < top:
			continue
		var land = minf(g, bot + 40.0)
		var y = top + (land - top) * f
		var sway = sin(f * TAU * (2.0 + 2.0 * v) + k) * 16.0 * Band.persp(lane)
		var x = x0 + sw_ * (y - top) + sway
		var w = FLAKE_W * Band.persp(lane) * zs * (0.7 + 0.6 * v)
		var tex: Texture2D = _flake_tex[int(v * 13.7) % nf]
		var h = w * tex.get_height() / tex.get_width()
		var c = col
		c.a = (0.55 + 0.4 * lane) * show * la * (1.0 - smoothstep(0.9, 1.0, f)) * smoothstep(0.0, 0.05, f)
		draw_set_transform(Vector2(x, y), f * TAU * (0.4 * v - 0.2) + sin(f * 9.0 + k) * 0.3, Vector2.ONE)
		draw_texture_rect(tex, Rect2(-0.5 * w, -0.5 * h, w, h), false, c)
		sprites += 1
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---- falling leaves --------------------------------------------------------------------------------------------------------------

# The leafy trees near the screen, found the way surface_view finds them, with the box of their crown relative to their foot.
func _refresh_trees(view: Rect2) -> void:
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
		_trees.append({"x": px, "lane": lane, "gy": _surf.ground_y(px) if _surf != null else colony.ground_y(), "canopy": rect,
			"seed": sd})


static func _hs(a: float) -> float:
	return fmod(abs(sin(a * 12.9898) * 43758.5453), 1.0)


func _leaves(view: Rect2) -> void:
	if _trees_age > 0.5 or absf(view.get_center().x - _trees_x) > 250.0:
		_refresh_trees(view)
	var vr = view.grow(60.0)
	var drawn = 0
	var nl = _leaf_tex.size()
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
		var sd: float = tr["seed"]
		for k in clampi(int(cr.size.x * 0.06), 10, LEAVES_PER_TREE):
			var key = sd * 1.37 + k * 5.71
			var period = 16.0 + 8.0 * _h(key, 1.0)
			var ph = _t / period + _h(key, 2.0)
			var cyc = floorf(ph)
			var tl = (ph - cyc) * period                    # seconds into this lap
			var q = key + cyc * 0.173
			if _h(q, 3.0) > _leaf_rate:
				continue                                    # this lap no leaf comes off
			var sx = tx + cr.position.x + cr.size.x * (0.1 + 0.8 * _h(q, 4.0))
			var sy = base_y + cr.position.y + cr.size.y * (0.2 + 0.7 * _h(q, 5.0))
			var dist = base_y - sy
			if dist < 4.0:
				continue
			var spd = maxf((60.0 + 40.0 * _h(q, 6.0)) * (0.5 + 0.5 * pers), dist / (period - 3.0))
			var fall_t = dist / spd
			var t0 = period - 3.0 - fall_t                  # it hangs on until here, then lets go
			var tf = tl - maxf(t0, 0.0)
			if tf < 0.0 or tf > fall_t + 3.0:
				continue
			var air = minf(tf, fall_t)
			var x = sx + wind * 55.0 * pers * air + sin(air * 1.3 + k) * 20.0 * pers + cos(air * 2.1 + q) * 6.0 * pers
			var y = sy + spd * air + sin(air * 2.3 + q) * 5.0 * pers
			var landed = tf > fall_t
			if landed:
				y = base_y + 1.0
			if not vr.has_point(Vector2(x, y)):
				continue
			var tex: Texture2D = _leaf_tex[int(_h(q, 7.0) * 9.99) % nl]
			var w = LEAF_W * pers * (0.75 + 0.5 * _h(q, 8.0))
			var h = w * tex.get_height() / tex.get_width()
			var flutter = 0.35 + 0.65 * absf(cos(air * 2.6 + q * 3.0))
			var rot = sin(air * 1.7 + q) * 0.9 + wind * 0.5
			var c = colony.day.tint
			c.a = la * (1.0 - smoothstep(fall_t + 1.0, fall_t + 3.0, tf))
			if landed:
				flutter = 0.45
				rot = q * 6.0
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
	var t0 = Time.get_ticks_usec()
	var d = colony.day
	var lane = Band.lane_of(float(n))
	var la = Band.lane_alpha(lane)
	if la <= 0.004:
		return
	var pw: float = colony.sim.wet
	if d.season == 0:
		pw = maxf(pw, 0.8 * d.snow)                         # the thaw leaves puddles
	if d.snow > 0.03 and n % 2 == 1 and _cap != null:
		_snow_row(it, n, lane, la, d.snow)
	if pw > 0.04 and d.season != 3 and _puddle != null:
		_puddles(it, n, lane, la, pw)
	it.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	lane_us += Time.get_ticks_usec() - t0


func _lane_ground(px: float, n: int, lane: float) -> float:
	if _surf == null:
		return Band.lane_y(colony.ground_y(), lane)
	var g: float = _surf.lane_ground(px, float(n)) if _has_lane_ground else _surf.ground_y(px)
	return Band.lane_y(g, lane)


# Snow lying in this lane: a row of the owner's snow pieces that grows as the snow comes (patchy at first), shrinks when it melts.
func _snow_row(it: CanvasItem, n: int, lane: float, la: float, sn: float) -> void:
	var view: Rect2 = colony.view_rect(0.0)
	var pers = Band.persp(lane)
	var w = SNOW_W * pers
	w = maxf(w, view.size.x / (SNOW_LIMIT * 0.62))           # zoomed out the pieces get bigger instead of more
	view = view.grow(w)
	var step = w * 0.62
	var hh = 0.85 * w * _cap.get_height() / _cap.get_width()     # a low drift: the piece is squashed a little
	var col: Color = colony.day.tint
	col.a = la
	var i0 = int(floor(view.position.x / step))
	var i1 = int(ceil(view.end.x / step))
	for i in range(i0, i1 + 1):
		var a = _h(i * 1.7, n * 3.1)
		var b = _h(i * 2.9, n * 5.3 + 1.0)
		var k = clampf((sn * 1.3 - a * 0.9) * 3.0, 0.0, 1.0)
		if k <= 0.02:
			continue
		var x = (i + 0.5 + (b - 0.5) * 0.7) * step
		var gy = _lane_ground(x, n, lane) + (a - 0.5) * hh * 0.5
		var sw = w * (0.75 + 0.6 * b)
		var sh = hh * (0.65 + 0.55 * a) * k
		var rect = Rect2(x - 0.5 * sw, gy - 0.82 * sh, sw, sh)
		if a > 0.5:
			it.draw_set_transform(Vector2(x * 2.0, 0.0), 0.0, Vector2(-1.0, 1.0))
			it.draw_texture_rect(_cap, rect, false, col)
			it.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			it.draw_texture_rect(_cap, rect, false, col)
		sprites += 1


# Puddles: slots along the lane, each with its own chance and size; they fill in the order of their size and dry the other way round.
func _puddles(it: CanvasItem, n: int, lane: float, la: float, pw: float) -> void:
	var view: Rect2 = colony.view_rect(PUDDLE_W * 2.0)
	var pers = Band.persp(lane)
	var tier = clampf(colony.zoom() * 1.6, 0.25, 1.0)        # zoomed far out only some of them are drawn
	var span = PUDDLE_SPAN
	var i0 = int(floor(view.position.x / span))
	var i1 = int(ceil(view.end.x / span))
	var C = WorldGrid.CELL
	var ex = (colony.grid.entrance.x + 0.5) * C
	var col: Color = colony.day.tint
	for i in range(i0, i1 + 1):
		var hc = _h(i * 3.77, n * 1.9 + 11.0)
		if hc < 0.55 or (hc - 0.55) / 0.45 > tier:
			continue
		var x = (i + _h(i * 5.1, n * 2.3 + 13.0)) * span
		if absf(x - ex) < 14.0 * C:
			continue                                         # not in the nest's mouth
		var size = clampf((pw - (hc - 0.55) * 0.9) * 2.2, 0.0, 1.0)
		if size <= 0.02:
			continue
		var w = PUDDLE_W * (0.55 + 0.7 * _h(i * 7.3, n * 4.1 + 14.0)) * pers * size
		var h = w * _puddle.get_height() / _puddle.get_width()
		col.a = la * clampf(size * 1.6, 0.0, 1.0)
		var gy = _lane_ground(x, n, lane)
		it.draw_texture_rect(_puddle, Rect2(x - 0.5 * w, gy - 0.45 * h, w, h), false, col)
		sprites += 1
