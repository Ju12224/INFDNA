extends Node2D
# Background layer stack, drawn behind the terrain. Each layer has a parallax factor f
# (0 = fixed to the screen, 1 = moves with the world) and also scales less with zoom,
# so distance reads both when panning and when zooming. Everything is procedural in x,
# so the backdrop never ends.
#   sky gradient -> sun -> clouds -> mountains -> foothills -> farmland -> pines -> forest -> hedge
# Each layer is built once per 1200 px chunk into a cached mesh (mesh_kit.gd) and redrawn with a
# single draw_mesh call; only the clouds and birds move. Below the playable depth a bedrock fill
# closes the world off.

const MK = preload("res://mods-unpacked/Judah-InfDNA/content/colony/mesh_kit.gd")

var cam
var grid
var perf             # perf.gd (optional): backdrop detail level
var day              # day_cycle.gd (optional): sun, moon, stars and the colour of the light
var anchor := Vector2()      # world point where every layer lines up (colony entrance)
var _t := 0.0
var _cache := {}             # "layer:chunk" -> ArrayMesh
var _clouds := []            # prebuilt cloud meshes
var _wisps := []
var _budget := 3

const CW = 1200.0            # layer-space chunk width
const BOTTOM = 700.0         # layers hang this far below the anchor so no sky shows under them
const HAZE = Color("#f0e4c8")
const NIGHT_STOPS = [Color("#060a22"), Color("#0d1744"), Color("#1a2a5e"), Color("#2b3a6c"), Color("#41507d")]
const DUSK_STOPS = [Color("#43478a"), Color("#8a69a2"), Color("#e8957c"), Color("#f6ad79"), Color("#ffc98a")]
const SKY_STOPS = [[-2200.0, Color("#5c9ccb")], [-1100.0, Color("#86bee0")], [-500.0, Color("#bcdbe0")], [-180.0, Color("#e8e6cf")], [-40.0, Color("#f6e6c0")]]

# f = parallax; base = px above the anchor (clear of the 128 px ground band); amp = relief
const LAYERS = [
	{"f": 0.07, "base": 520.0, "amp": 320.0, "kind": "peaks", "col": Color("#b4c8dc"), "hz": 0.50},
	{"f": 0.12, "base": 420.0, "amp": 250.0, "kind": "peaks", "col": Color("#97b3c8"), "hz": 0.40},
	{"f": 0.20, "base": 330.0, "amp": 150.0, "kind": "ridge", "col": Color("#7ba48f"), "hz": 0.32},
	{"f": 0.30, "base": 262.0, "amp": 90.0, "kind": "fields", "col": Color("#9dc27c"), "hz": 0.26},
	{"f": 0.42, "base": 215.0, "amp": 55.0, "kind": "pines", "col": Color("#4b7b57"), "hz": 0.18},
	{"f": 0.56, "base": 178.0, "amp": 30.0, "kind": "forest", "col": Color("#4f8a49"), "hz": 0.11},
	{"f": 0.76, "base": 146.0, "amp": 14.0, "kind": "hedge", "col": Color("#477f3f"), "hz": 0.04},
]


func _ready() -> void:
	for i in 6:
		_clouds.append(_cloud_mesh(i * 3.7 + 1.0, false))
	for i in 4:
		_wisps.append(_cloud_mesh(i * 5.3 + 2.0, true))


func _process(delta: float) -> void:
	_t += delta
	update()


func _view() -> Rect2:
	var vp = get_viewport_rect().size
	var z = cam.zoom.x
	var c = cam.get_camera_screen_center()
	return Rect2(c - vp * z * 0.5, vp * z)


# layer f -> [scale, offset]: world = offset + scale * P
func _xf(f: float) -> Array:
	var z = cam.zoom.x
	var s = pow(z, 1.0 - f)
	var c = cam.get_camera_screen_center()
	return [s, anchor * (1.0 - s) + (c - anchor) * (1.0 - f * s)]


func _draw() -> void:
	if cam == null:
		return
	_budget = 14 if _cache.empty() else 8
	var v = _view()
	var bd = perf.backdrop if perf != null else 3
	var first = [5, 3, 1, 0][bd]            # lower quality drops the far layers first
	var dn = day.night if day != null else 0.0
	_sky(v)
	if dn > 0.04 and bd >= 1:
		_stars(v, dn)
	if bd >= 2:
		if day == null or day.elev > -0.25:
			_sun(v, bd >= 3 and dn < 0.5)
		if dn > 0.04:
			_moon(v, dn)
	if bd >= 3:
		_cloud_layer(v, 0.05, _wisps, 0.55, 900.0, 640.0, 1.6, 4.0)
	if bd >= 2:
		_cloud_layer(v, 0.10, _clouds, 0.95, 640.0, 560.0, 1.0, 9.0)
	for i in LAYERS.size():
		if i < first:
			continue
		_layer(v, i)
		if i == 2 and bd >= 3 and dn < 0.7:
			_birds(v)
		if i == 3 and bd >= 2:
			_cloud_layer(v, 0.26, _clouds, 0.8, 760.0, 250.0, 0.55, 14.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if bd >= 3 and dn < 0.6:
		_pollen(v)
	_bedrock(v)


func _sky(v: Rect2) -> void:
	var x0 = v.position.x - 10
	var x1 = v.end.x + 10
	var top = v.position.y - 10
	var prev_y = top
	var prev_c = _stop_col(0)
	for si in SKY_STOPS.size():
		var st = SKY_STOPS[si]
		var sc = _stop_col(si)
		var y = anchor.y + st[0] * 0.8 + (v.position.y + v.size.y * 0.5 - anchor.y) * 0.35
		if y > prev_y:
			draw_polygon(PoolVector2Array([Vector2(x0, prev_y), Vector2(x1, prev_y), Vector2(x1, y), Vector2(x0, y)]),
				PoolColorArray([prev_c, prev_c, sc, sc]))
		prev_y = max(prev_y, y)
		prev_c = sc
	if prev_y < v.end.y:
		draw_rect(Rect2(x0, prev_y, x1 - x0, v.end.y - prev_y + 10), prev_c)


# Sky colour of one gradient stop: warmed toward dusk colours at sunrise and sunset, then toward night.
func _stop_col(i: int) -> Color:
	var c: Color = SKY_STOPS[i][1]
	if day == null:
		return c
	if day.warm > 0.01:
		c = c.linear_interpolate(DUSK_STOPS[i], day.warm * 0.8)
	if day.night > 0.01:
		c = c.linear_interpolate(NIGHT_STOPS[i], day.night)
	# light_view.gd multiplies everything on screen by the light colour afterwards: pre-divide so the sky lands on its palette
	var t = day.tint
	return Color(min(c.r / max(t.r, 0.2), 1.0), min(c.g / max(t.g, 0.2), 1.0), min(c.b / max(t.b, 0.2), 1.0), 1.0)


func _arc(u: float) -> Vector2:
	return anchor + Vector2(lerp(-720.0, 720.0, u), -140.0 - 640.0 * sin(clamp(u, 0.0, 1.0) * PI))


func _stars(v: Rect2, night: float) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var z = cam.zoom.x
	for k in 90:
		var hx = _hh(k * 1.37, 61.0)
		var hy = _hh(k * 2.11, 62.0)
		var p = Vector2(v.position.x + hx * v.size.x, v.position.y + hy * v.size.y * 0.62)
		var tw = 0.55 + 0.45 * sin(_t * (1.2 + hx * 2.0) + k * 3.1)
		var r = (0.7 + 1.4 * _hh(k * 0.77, 63.0)) * z
		draw_circle(p, r, Color(0.92, 0.95, 1.0, night * tw * 0.9))


func _moon(v: Rect2, night: float) -> void:
	var nt = (day.ph - 0.75 if day.ph >= 0.75 else day.ph + 0.25) / 0.5 if day != null else 0.5
	var xf = _xf(0.03)
	draw_set_transform(xf[1], 0.0, Vector2(xf[0], xf[0]))
	var p = _arc(nt)
	var a = night
	draw_circle(p, 170.0, Color(0.7, 0.8, 1.0, 0.07 * a))
	draw_circle(p, 105.0, Color(0.75, 0.85, 1.0, 0.13 * a))
	draw_circle(p, 56.0, Color(0.93, 0.95, 0.98, a))
	draw_circle(p + Vector2(18, -10), 11.0, Color(0.78, 0.82, 0.9, a))
	draw_circle(p + Vector2(-16, 14), 8.0, Color(0.8, 0.84, 0.92, a))
	draw_circle(p + Vector2(8, 22), 5.0, Color(0.8, 0.84, 0.92, a))
	draw_circle(p + Vector2(-22, -16), 6.0, Color(0.82, 0.86, 0.93, a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _sun(v: Rect2, rays: bool = true) -> void:
	var xf = _xf(0.03)
	draw_set_transform(xf[1], 0.0, Vector2(xf[0], xf[0]))
	var p = anchor + Vector2(560, -640)
	var warm_k = 0.0
	var vis = 1.0
	if day != null:
		p = _arc(clamp((day.ph - 0.25) / 0.5, 0.0, 1.0))
		warm_k = day.warm
		vis = 1.0 - day.night
	var pulse = 1.0 + 0.02 * sin(_t * 0.8)
	# slow rays
	for k in (9 if rays else 0):
		var a = _t * 0.02 + TAU * k / 9.0
		var d = Vector2(cos(a), sin(a))
		var n = Vector2(-d.y, d.x)
		draw_polygon(PoolVector2Array([p + d * 70.0 + n * 12.0, p + d * 560.0 + n * 70.0, p + d * 560.0 - n * 70.0, p + d * 70.0 - n * 12.0]),
			PoolColorArray([Color(1.0, 0.96, 0.78, 0.07 * vis), Color(1.0, 0.96, 0.78, 0.0), Color(1.0, 0.96, 0.78, 0.0), Color(1.0, 0.96, 0.78, 0.07 * vis)]))
	var g1 = Color(1.0, 0.95, 0.75).linear_interpolate(Color(1.0, 0.66, 0.4), warm_k)
	var g2 = Color(1.0, 0.93, 0.7).linear_interpolate(Color(1.0, 0.6, 0.35), warm_k)
	draw_circle(p, 150.0 * pulse * (1.0 + 0.3 * warm_k), Color(g1.r, g1.g, g1.b, 0.14 * vis))
	draw_circle(p, 96.0 * pulse, Color(g2.r, g2.g, g2.b, 0.30 * vis))
	draw_circle(p, 58.0, Color("#fff4cf").linear_interpolate(Color("#ffc58a"), warm_k) * Color(1, 1, 1, vis))
	draw_circle(p, 48.0, Color("#ffe08a").linear_interpolate(Color("#ff9a4a"), warm_k) * Color(1, 1, 1, vis))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ---------------------------------------------------------------- terrain layers
static func _hh(a: float, b: float) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _relief(x: float, sd: float, kind: String) -> float:
	if kind == "peaks":
		var a = abs(sin(x * 0.0021 + sd)) * 0.55 + abs(sin(x * 0.0053 + sd * 2.1)) * 0.3 + sin(x * 0.013 + sd * 3.7) * 0.08
		return a + 0.07 * sin(x * 0.041 + sd)
	if kind == "ridge":
		return 0.5 + 0.35 * sin(x * 0.0031 + sd) + 0.15 * sin(x * 0.0087 + sd * 1.7) + 0.06 * abs(sin(x * 0.019 + sd))
	return 0.5 + 0.3 * sin(x * 0.006 + sd) + 0.2 * sin(x * 0.017 + sd * 2.3)


func _ridge_y(i: int, x: float) -> float:
	var L = LAYERS[i]
	return anchor.y - L["base"] - _relief(x, L["f"] * 13.7, L["kind"]) * L["amp"]


func _layer(v: Rect2, i: int) -> void:
	var L = LAYERS[i]
	var xf = _xf(L["f"])
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	var p0 = (v.position.x - off.x) / s - 60.0
	var p1 = (v.end.x - off.x) / s + 60.0
	# the layer transform goes through draw_set_transform with an identity mesh transform: a scaled transform
	# passed to draw_mesh itself got the far chunks clipped away at large zoom-outs
	draw_set_transform(off, 0.0, Vector2(s, s))
	for ci in range(int(floor(p0 / CW)), int(floor(p1 / CW)) + 1):
		var key = "%d:%d" % [i, ci]
		var m = _cache.get(key)
		if m == null:
			if _budget <= 0:
				continue
			_budget -= 1
			m = _build(i, ci)
			_cache[key] = m
		if m is Mesh:
			draw_mesh(m, null)
	# ambient ants marching along the farmland and hedge ridges (the idea comes from the v0.22 sky)
	if (i == 3 or i == 6) and s > 0.38 and (perf == null or perf.backdrop >= 2):
		_bg_ants(i, s, p0, p1)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if _cache.size() > 160:
		_cache.clear()


func _build(i: int, ci: int):
	var L = LAYERS[i]
	var kind: String = L["kind"]
	var col: Color = L["col"]
	var hz: float = L["hz"]
	var mk = MK.new()
	var x0 = ci * CW
	var step = 24.0 if kind == "peaks" else 16.0
	var n = int(CW / step)
	var bot = anchor.y + BOTTOM
	var c_bot = col.linear_interpolate(HAZE, hz + 0.3)
	var pts := PoolVector2Array()
	for k in n + 1:
		var x = x0 + k * step
		pts.append(Vector2(x, _ridge_y(i, x)))
	var base_c = col.linear_interpolate(HAZE, hz * 0.25)
	var zone = 60.0 + float(L["amp"]) * 0.45       # lighting only reaches this far below the ridge
	# lighting per ridge VERTEX (smooth from one to the next, so the slopes read as planes, not stripes):
	# slopes facing the sun (up and to the right) lighter, the others darker
	var vc := PoolColorArray()
	for k in n + 1:
		var a0 = pts[max(k - 1, 0)]
		var b0 = pts[min(k + 1, n)]
		var sl = (b0.y - a0.y) / max(1.0, b0.x - a0.x)
		var shade = clamp(sl * 0.9, -0.5, 0.5) if kind == "peaks" or kind == "ridge" else 0.0
		var cv = col.lightened(shade * 0.3) if shade > 0.0 else col.darkened(-shade * 0.3)
		vc.append(cv.linear_interpolate(HAZE, hz * 0.25))
	for k in n:
		var za = Vector2(pts[k].x, pts[k].y + zone)
		var zb = Vector2(pts[k + 1].x, pts[k + 1].y + zone)
		mk.quad_c(pts[k], vc[k], pts[k + 1], vc[k + 1], zb, base_c, za, base_c)
		mk.quad_c(za, base_c, zb, base_c, Vector2(pts[k + 1].x, bot), c_bot, Vector2(pts[k].x, bot), c_bot)
	var line = col.lightened(0.16).linear_interpolate(HAZE, hz * 0.3)
	var wk := PoolRealArray()
	for k in n + 1:
		wk.append(3.0)
	mk.ribbon(pts, wk, Color(line.r, line.g, line.b, 0.7))
	match kind:
		"peaks":
			_snow(mk, pts, step, i, x0)
			_strata(mk, pts, col, i, x0)
		"ridge":
			_pines(mk, i, x0, 20.0, 34.0, 62.0, 0.5, col.darkened(0.12))
		"fields":
			_fields(mk, pts, i, x0, step, col)
		"pines":
			_pines(mk, i, x0, 16.0, 52.0, 96.0, 0.9, col)
		"forest":
			_leafy(mk, i, x0, 30.0, 58.0, 100.0, col)
		"hedge":
			_hedge(mk, i, x0, col)
	return mk.build()


# Columns of tiny ants marching along a layer's ridge, some carrying a leaf. Deterministic in x and time,
# so nothing is stored; they fade at the ends of their stretch instead of popping.
func _bg_ants(i: int, s: float, p0: float, p1: float) -> void:
	var L = LAYERS[i]
	var f: float = L["f"]
	var detail = s > 0.62
	var size = 3.2 + f * 3.4
	var span = 340.0 if detail else 520.0
	var gap = size * 7.0
	var ink = Color(L["col"]).darkened(0.6)
	for ci in range(int(floor(p0 / span)) - 1, int(ceil(p1 / span)) + 1):
		var hh = _hh(ci * 57.31, f * 5.1)
		if hh < 0.3:
			continue
		var dir = 1.0 if hh > 0.65 else -1.0
		var n = 3 + int(hh * 4.0)
		var speed = 10.0 + hh * 14.0
		for k in n:
			var u = fmod(_t * speed * dir + (k * gap + hh * 90.0) * dir, span)
			if u < 0.0:
				u += span
			var edge = clamp(min(u, span - u) / 40.0, 0.0, 1.0)
			var rx = ci * span + u
			var ry = _ridge_y(i, rx) + 2.0
			var ang = atan2(_ridge_y(i, rx + 6.0) - _ridge_y(i, rx - 6.0), 12.0)
			var fw = Vector2(cos(ang), sin(ang)) * dir
			var up = Vector2(sin(ang), -cos(ang))
			var foot = Vector2(rx, ry)
			var ac = Color(ink.r, ink.g, ink.b, 0.92 * edge)
			var mid = foot + up * size
			draw_circle(mid - fw * size * 1.7, size * 0.95, ac)
			draw_circle(mid, size * 0.62, ac)
			draw_circle(mid + fw * size * 1.35, size * 0.62, ac)
			if detail:
				var legs := PoolVector2Array()
				for lg in 3:
					var sw = sin(_t * 13.0 + k * 1.3 + lg * 2.1) * size * 0.4
					legs.append(mid + fw * (lg - 1) * size * 0.45)
					legs.append(foot + fw * ((lg - 1) * size * 0.9 + sw))
				draw_multiline(legs, ac, max(1.0, size * 0.22), true)
				var hp = mid + fw * size * 1.35
				draw_line(hp, hp + fw * size + up * size * 0.8, ac, max(1.0, size * 0.18), true)
				if (k + ci) % 2 == 0:
					draw_circle(mid + up * size * 1.7 - fw * size * 0.2, size * 0.95, Color(0.42, 0.75, 0.29, 0.9 * edge))


# A few motes of pollen and seed fluff in the foreground air.
func _pollen(v: Rect2) -> void:
	var xf = _xf(0.9)
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	draw_set_transform(off, 0.0, Vector2(s, s))
	var p0 = (v.position.x - off.x) / s
	var w = (v.end.x - v.position.x) / s
	if w > 0.0:
		for k in 18:
			var px = p0 + fmod(k * 211.3 + _t * (10.0 + (k % 5) * 4.0), w)
			var py = anchor.y - 40.0 - fmod(k * 97.1, 160.0) + sin(_t * 0.9 + k) * 14.0
			draw_circle(Vector2(px, py), 1.6 + (k % 3) * 0.6, Color(1.0, 1.0, 0.8, 0.55))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _snow(mk, pts: PoolVector2Array, step: float, i: int, x0: float) -> void:
	var L = LAYERS[i]
	var thresh = anchor.y - L["base"] - L["amp"] * 0.66
	var white = Color("#f1f6f8").linear_interpolate(HAZE, L["hz"] * 0.35)
	var blue = Color("#cfdde6").linear_interpolate(HAZE, L["hz"] * 0.35)
	for k in range(0, pts.size() - 1):
		var a = pts[k]
		var b = pts[k + 1]
		if a.y > thresh and b.y > thresh:
			continue
		var da = clamp((thresh - a.y) * 0.6 + 6.0, 0.0, 70.0) if a.y < thresh else 0.0
		var db = clamp((thresh - b.y) * 0.6 + 6.0, 0.0, 70.0) if b.y < thresh else 0.0
		var j1 = 0.7 + 0.6 * _hh(x0 + k, 3.0)
		var j2 = 0.7 + 0.6 * _hh(x0 + k + 1, 3.0)
		var lit = b.y > a.y   # descending to the right = facing the sun
		var c = white if lit else blue
		mk.quad(a, b, b + Vector2(0, db * j2), a + Vector2(0, da * j1), c)


func _strata(mk, pts: PoolVector2Array, col: Color, i: int, x0: float) -> void:
	# a few darker gullies running down from the ridge give the slopes some body
	var dark = col.darkened(0.16).linear_interpolate(HAZE, LAYERS[i]["hz"] * 0.3)
	for k in range(2, pts.size() - 2, 3):
		if _hh(x0 + k, 5.0) > 0.55:
			continue
		var a = pts[k]
		var ln = 40.0 + 90.0 * _hh(x0 + k, 6.0)
		mk.tri(a + Vector2(-5, 4), a + Vector2(5, 4), a + Vector2(-8.0 + 16.0 * _hh(x0 + k, 7.0), ln), Color(dark.r, dark.g, dark.b, 0.55))


func _pines(mk, i: int, x0: float, spacing: float, hmin: float, hmax: float, density: float, col: Color) -> void:
	var hz: float = LAYERS[i]["hz"]
	var dark = col.darkened(0.2).linear_interpolate(HAZE, hz * 0.3)
	var lite = col.lightened(0.1).linear_interpolate(HAZE, hz * 0.3)
	var trunk = Color("#4a3a2c").linear_interpolate(HAZE, hz)
	var k = 0
	var x = x0 + 4.0
	while x < x0 + CW:
		var h1 = _hh(x * 0.37, 11.0 + i)
		if h1 < density:
			var hh = hmin + (hmax - hmin) * _hh(x * 0.21, 12.0 + i)
			var b = Vector2(x, _ridge_y(i, x) + 6.0)
			var w = hh * 0.3
			mk.quad(b + Vector2(-hh * 0.025, 0), b + Vector2(hh * 0.025, 0), b + Vector2(hh * 0.02, -hh * 0.2), b + Vector2(-hh * 0.02, -hh * 0.2), trunk)
			for t in 3:
				var y0 = -hh * (0.14 + 0.24 * t)
				var wt = w * (1.0 - 0.27 * t)
				var tip = b + Vector2(0, y0 - hh * 0.34)
				mk.tri(b + Vector2(-wt, y0), b + Vector2(0, y0), tip, dark)
				mk.tri(b + Vector2(0, y0), b + Vector2(wt, y0), tip, lite)
		x += spacing * (0.75 + 0.6 * _hh(x, 13.0))
		k += 1


func _leafy(mk, i: int, x0: float, spacing: float, hmin: float, hmax: float, col: Color) -> void:
	var hz: float = LAYERS[i]["hz"]
	var dark = col.darkened(0.22).linear_interpolate(HAZE, hz * 0.3)
	var mid = col.linear_interpolate(HAZE, hz * 0.3)
	var lite = col.lightened(0.16).linear_interpolate(HAZE, hz * 0.3)
	var trunk = Color("#5a4230").linear_interpolate(HAZE, hz)
	var x = x0 + 6.0
	while x < x0 + CW:
		var hh = hmin + (hmax - hmin) * _hh(x * 0.19, 21.0)
		var b = Vector2(x, _ridge_y(i, x) + 8.0)
		var tw = hh * 0.055
		mk.quad(b + Vector2(-tw, 0), b + Vector2(tw, 0), b + Vector2(tw * 0.6, -hh * 0.5), b + Vector2(-tw * 0.6, -hh * 0.5), trunk)
		var cc = b + Vector2(0, -hh * 0.68)
		var r = hh * 0.34
		mk.blob(cc + Vector2(-r * 0.2, r * 0.2), r * 1.05, r * 0.85, x, 0.1, dark, 10)
		mk.blob(cc + Vector2(r * 0.55, r * 0.1), r * 0.8, r * 0.7, x + 1.0, 0.1, dark, 9)
		mk.blob(cc + Vector2(-r * 0.55, r * 0.1), r * 0.8, r * 0.7, x + 2.0, 0.1, dark, 9)
		mk.blob(cc + Vector2(0, 0), r * 0.92, r * 0.74, x + 3.0, 0.1, mid, 10)
		mk.blob(cc + Vector2(r * 0.25, -r * 0.2), r * 0.52, r * 0.42, x + 4.0, 0.12, lite, 8)
		x += spacing * (0.7 + 0.7 * _hh(x, 22.0))


func _hedge(mk, i: int, x0: float, col: Color) -> void:
	var hz: float = LAYERS[i]["hz"]
	var dark = col.darkened(0.2)
	var lite = col.lightened(0.14)
	var x = x0
	while x < x0 + CW:
		var h1 = _hh(x, 31.0)
		var r = 18.0 + 14.0 * h1
		var b = Vector2(x, _ridge_y(i, x) + 10.0)
		mk.blob(b + Vector2(0, -r * 0.2), r, r * 0.85, x, 0.1, dark, 9)
		mk.blob(b + Vector2(-r * 0.1, -r * 0.35), r * 0.82, r * 0.7, x + 1.0, 0.1, col, 9)
		mk.blob(b + Vector2(-r * 0.3, -r * 0.55), r * 0.36, r * 0.3, x + 2.0, 0.1, lite, 7)
		if _hh(x, 32.0) > 0.78:
			for k in 3:
				mk.ellipse(b + Vector2((k - 1) * r * 0.5, -r * (0.2 + 0.35 * _hh(x, 33.0 + k))), 2.6, 2.6, Color("#d8473b") if _hh(x, 34.0) > 0.5 else Color("#f3d34a"), 6)
		x += 22.0 + 12.0 * _hh(x, 35.0)


func _fields(mk, pts: PoolVector2Array, i: int, x0: float, step: float, col: Color) -> void:
	var hz: float = LAYERS[i]["hz"]
	var tones = [Color("#a9cc7e"), Color("#d6cf7a"), Color("#8fb86a"), Color("#c7b872"), Color("#b4d086")]
	var n = pts.size() - 1
	var k = 0
	while k < n:
		var run = 3 + int(_hh(x0 + k, 41.0) * 5.0)
		var tc = tones[int(_hh(x0 + k, 42.0) * 4.99)].linear_interpolate(HAZE, hz)
		var k2 = min(n, k + run)
		for j in range(k, k2):
			var a = pts[j]
			var b = pts[j + 1]
			var d = 70.0
			mk.quad_c(a, tc.lightened(0.04), b, tc.lightened(0.04), b + Vector2(0, d), tc.darkened(0.06), a + Vector2(0, d), tc.darkened(0.06))
		var mid = pts[(k + k2) / 2]
		var r = _hh(x0 + k, 43.0)
		if r > 0.86:
			# a small red barn with a pitched roof
			var bw = 22.0
			var bh = 15.0
			var bc = Color("#b6483c").linear_interpolate(HAZE, hz)
			mk.quad(mid + Vector2(-bw * 0.5, 4), mid + Vector2(bw * 0.5, 4), mid + Vector2(bw * 0.5, 4 - bh), mid + Vector2(-bw * 0.5, 4 - bh), bc)
			mk.tri(mid + Vector2(-bw * 0.6, 4 - bh), mid + Vector2(bw * 0.6, 4 - bh), mid + Vector2(0, 4 - bh - 11), Color("#6b3a2e").linear_interpolate(HAZE, hz))
		elif r < 0.07:
			# a windmill
			var tc2 = Color("#e9e3d6").linear_interpolate(HAZE, hz)
			mk.quad(mid + Vector2(-5, 4), mid + Vector2(5, 4), mid + Vector2(3, -34), mid + Vector2(-3, -34), tc2)
			var hub = mid + Vector2(0, -34)
			for bl in 4:
				var a2 = PI * 0.25 + PI * 0.5 * bl
				var dir = Vector2(cos(a2), sin(a2))
				var nn = Vector2(-dir.y, dir.x)
				mk.quad(hub + dir * 4.0 + nn * 1.5, hub + dir * 26.0 + nn * 4.0, hub + dir * 26.0 - nn * 1.0, hub + dir * 4.0 - nn * 1.5, Color("#f3efe4").linear_interpolate(HAZE, hz))
		k = k2


# ---------------------------------------------------------------- clouds and birds
func _cloud_mesh(sd: float, wisp: bool) -> ArrayMesh:
	var mk = MK.new()
	var white = Color(1, 1, 1, 0.9)
	var under = Color(0.84, 0.89, 0.95, 0.92)
	if wisp:
		for k in 7:
			var x = (k - 3) * 70.0 + (_hh(sd, k) - 0.5) * 30.0
			mk.ellipse(Vector2(x, (_hh(sd, k + 9.0) - 0.5) * 18.0), 90.0 + 50.0 * _hh(sd, k + 3.0), 7.0 + 4.0 * _hh(sd, k + 5.0), Color(1, 1, 1, 0.32), 12)
		return mk.build()
	var n = 7 + int(_hh(sd, 1.0) * 4.0)
	for k in n:
		var u = float(k) / (n - 1) - 0.5
		var r = 26.0 + 22.0 * (1.0 - abs(u) * 1.6) * (0.6 + 0.6 * _hh(sd, k + 2.0))
		mk.blob(Vector2(u * 190.0, 6.0 - r * 0.5 + (_hh(sd, k + 7.0) - 0.5) * 14.0), r, r * 0.8, sd + k, 0.08, under, 12)
	for k in n:
		var u2 = float(k) / (n - 1) - 0.5
		var r2 = 24.0 + 22.0 * (1.0 - abs(u2) * 1.6) * (0.6 + 0.6 * _hh(sd, k + 2.0))
		mk.blob(Vector2(u2 * 190.0, -r2 * 0.62 + (_hh(sd, k + 7.0) - 0.5) * 14.0), r2, r2 * 0.78, sd + k + 4.0, 0.08, white, 12)
	for k in 4:
		mk.blob(Vector2((k - 1.5) * 52.0, -44.0 - 10.0 * _hh(sd, k)), 22.0, 14.0, sd + k * 2.0, 0.1, Color(1, 1, 1, 0.95), 9)
	return mk.build()


func _cloud_layer(v: Rect2, f: float, meshes: Array, alpha: float, span: float, high: float, size: float, speed: float) -> void:
	var xf = _xf(f)
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	var p0 = (v.position.x - off.x) / s - 300.0
	var p1 = (v.end.x - off.x) / s + 300.0
	var i0 = int(floor((p0 - _t * speed) / span))
	var i1 = int(ceil((p1 - _t * speed) / span))
	for i in range(i0, i1 + 1):
		var hh = _hh(i * 91.7, f * 10.0)
		if hh < 0.3:
			continue
		var sc = size * (0.7 + 0.8 * fmod(hh * 7.3, 1.0))
		var pos = Vector2(i * span + _t * speed + hh * span * 0.4, anchor.y - high - hh * 260.0 * size)
		draw_set_transform(off + pos * s, 0.0, Vector2(s * sc, s * sc))     # layer-space position, own size
		draw_mesh(meshes[int(hh * 97.0) % meshes.size()], null, null, Transform2D(), Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _birds(v: Rect2) -> void:
	var xf = _xf(0.16)
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	draw_set_transform(off, 0.0, Vector2(s, s))
	var span = 2400.0
	var p0 = (v.position.x - off.x) / s - 400.0
	var p1 = (v.end.x - off.x) / s + 400.0
	var i0 = int(floor((p0 - _t * 22.0) / span))
	var i1 = int(ceil((p1 - _t * 22.0) / span))
	for i in range(i0, i1 + 1):
		if _hh(i * 17.3, 5.0) < 0.45:
			continue
		var n = 4 + int(_hh(i * 3.1, 6.0) * 5.0)
		var cx = i * span + _t * 22.0 + _hh(i, 7.0) * span * 0.5
		var cy = anchor.y - 470.0 - _hh(i, 8.0) * 190.0
		for k in n:
			var bx = cx + (k % 3) * 34.0 - (k / 3) * 26.0
			var by = cy + (k % 3) * 9.0 + (k / 3) * 14.0 + sin(_t * 0.7 + k) * 5.0
			var fl = sin(_t * 8.0 + k * 1.9 + i)
			var col = Color(0.16, 0.18, 0.24, 0.8)
			draw_polyline(PoolVector2Array([Vector2(bx - 9, by - 3.5 * fl), Vector2(bx - 3, by - 1), Vector2(bx, by), Vector2(bx + 3, by - 1), Vector2(bx + 9, by - 3.5 * fl)]), col, 2.2, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _bedrock(v: Rect2) -> void:
	if grid == null:
		return
	var y0 = (grid.H - 1) * grid.CELL
	if v.end.y < y0:
		return
	var a = Color("#48413c")
	var b = Color("#1c1715")
	var y1 = max(v.end.y + 10, y0 + 10)
	draw_polygon(PoolVector2Array([Vector2(v.position.x - 10, y0), Vector2(v.end.x + 10, y0), Vector2(v.end.x + 10, y1), Vector2(v.position.x - 10, y1)]),
		PoolColorArray([a, a, b.linear_interpolate(a, 0.3), b.linear_interpolate(a, 0.3)]))
