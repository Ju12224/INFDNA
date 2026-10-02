extends Node2D
# Background layer stack, drawn behind the terrain. Each layer has a parallax factor f
# (0 = fixed to the screen, 1 = moves with the world) and also scales less with zoom,
# so distance reads both when panning and when zooming. Everything is procedural in x,
# so the backdrop never ends.
#   sky gradient -> sun -> far range -> near range -> hills -> forest -> clouds
# Below the playable depth a bedrock fill closes the world off.

var cam
var grid
var anchor := Vector2()      # world point where every layer lines up (colony entrance)
var _t := 0.0

const LAYERS = [
	# f, base (px above anchor), amp, kind, color
	[0.08, 330.0, 150.0, "peaks", Color("#a3bccb")],
	[0.18, 230.0, 110.0, "peaks", Color("#8eafba")],
	[0.32, 140.0, 60.0, "hills", Color("#8db59c")],
	[0.52, 70.0, 26.0, "forest", Color("#6a9a62")],
	[0.72, 30.0, 14.0, "bushes", Color("#578a4c")],
]


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
	var v = _view()
	_sky(v)
	_sun(v)
	for L in LAYERS:
		_layer(v, L)
	_clouds(v)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_bedrock(v)


func _sky(v: Rect2) -> void:
	var stops = [[-1600.0, Color("#6fa9cf")], [-700.0, Color("#93c6de")], [-250.0, Color("#cfe3dc")], [-60.0, Color("#f3e3c2")]]
	var x0 = v.position.x - 10
	var x1 = v.end.x + 10
	var top = v.position.y - 10
	var prev_y = top
	var prev_c = stops[0][1]
	for st in stops:
		var y = anchor.y + st[0] * 0.8 + (v.position.y + v.size.y * 0.5 - anchor.y) * 0.35
		if y > prev_y:
			draw_polygon(PoolVector2Array([Vector2(x0, prev_y), Vector2(x1, prev_y), Vector2(x1, y), Vector2(x0, y)]),
				PoolColorArray([prev_c, prev_c, st[1], st[1]]))
		prev_y = max(prev_y, y)
		prev_c = st[1]
	if prev_y < v.end.y:
		draw_rect(Rect2(x0, prev_y, x1 - x0, v.end.y - prev_y + 10), prev_c)


func _sun(v: Rect2) -> void:
	var xf = _xf(0.03)
	draw_set_transform(xf[1], 0.0, Vector2(xf[0], xf[0]))
	var p = anchor + Vector2(520, -520)
	var pulse = 1.0 + 0.02 * sin(_t * 0.8)
	draw_circle(p, 120.0 * pulse, Color(1.0, 0.95, 0.75, 0.18))
	draw_circle(p, 78.0 * pulse, Color(1.0, 0.93, 0.7, 0.35))
	draw_circle(p, 52.0, Color("#fff4cf"))
	draw_circle(p, 43.0, Color("#ffe08a"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _h(x: float, seed_v: float, kind: String) -> float:
	if kind == "peaks":
		var a = abs(sin(x * 0.0021 + seed_v)) * 0.55 + abs(sin(x * 0.0053 + seed_v * 2.1)) * 0.3 + sin(x * 0.013 + seed_v * 3.7) * 0.08
		return a + 0.07 * sin(x * 0.041 + seed_v)
	if kind == "hills":
		return 0.5 + 0.35 * sin(x * 0.0031 + seed_v) + 0.15 * sin(x * 0.0087 + seed_v * 1.7)
	return 0.5 + 0.3 * sin(x * 0.006 + seed_v) + 0.2 * sin(x * 0.017 + seed_v * 2.3)


func _layer(v: Rect2, L: Array) -> void:
	var f: float = L[0]
	var base: float = L[1]
	var amp: float = L[2]
	var kind: String = L[3]
	var col: Color = L[4]
	var xf = _xf(f)
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	var p0 = (v.position.x - off.x) / s - 60.0
	var p1 = (v.end.x - off.x) / s + 60.0
	var bottom = (v.end.y - off.y) / s + 40.0
	var seed_v = f * 13.7
	var step = 18.0 if kind != "peaks" else 24.0
	# near layers loosely follow the real terrain so they sit behind the ground
	var follow = 0.0 if f < 0.5 else (f - 0.4) * 1.4
	draw_set_transform(off, 0.0, Vector2(s, s))
	var pts := PoolVector2Array()
	var x = floor(p0 / step) * step
	while x <= p1:
		var gy = 0.0
		if follow > 0.0 and grid != null:
			var wx = off.x + s * x
			gy = (_ground_px(wx) - anchor.y) * follow / s
		pts.append(Vector2(x, anchor.y - base - _h(x, seed_v, kind) * amp + gy))
		x += step
	if pts.size() < 2:
		return
	var poly := PoolVector2Array(pts)
	poly.append(Vector2(pts[pts.size() - 1].x, max(bottom, anchor.y + 2000.0)))
	poly.append(Vector2(pts[0].x, max(bottom, anchor.y + 2000.0)))
	draw_colored_polygon(poly, col)
	# light rim on the ridge, darker body lower down (aerial perspective)
	draw_polyline(pts, col.lightened(0.18), 3.0 / s, true)
	if kind == "peaks":
		# snow caps hug the ridge on both sides of each high peak
		for i in range(1, pts.size() - 1):
			if pts[i].y < pts[i - 1].y and pts[i].y <= pts[i + 1].y and _h(pts[i].x, seed_v, kind) > 0.6:
				var tip = pts[i]
				var l = tip.linear_interpolate(pts[i - 1], 0.55)
				var r = tip.linear_interpolate(pts[i + 1], 0.55)
				var mid = tip.linear_interpolate((l + r) * 0.5, 0.7)
				draw_colored_polygon(PoolVector2Array([tip, r, mid, l]),
					Color("#eef4f5") if f < 0.1 else Color("#dde9ec"))
	elif kind == "forest" or kind == "bushes":
		var r0 = 26.0 if kind == "forest" else 15.0
		var shade = col.darkened(0.12)
		var lite = col.lightened(0.1)
		for i in pts.size():
			var p = pts[i]
			var hh = fmod(abs(sin(p.x * 12.9898 + seed_v) * 43758.5453), 1.0)
			var r = r0 * (0.7 + 0.6 * hh)
			draw_circle(p + Vector2(0, r * 0.35), r, shade)
			draw_circle(p + Vector2(-r * 0.15, r * 0.2), r * 0.82, col)
			draw_circle(p + Vector2(-r * 0.3, 0), r * 0.35, lite)
	# haze over the lower part of far layers
	if f < 0.4:
		var hz = Color("#f3e3c2")
		var y0 = anchor.y - base * 0.4
		var y1 = anchor.y + 60.0
		draw_polygon(PoolVector2Array([Vector2(p0, y0), Vector2(p1, y0), Vector2(p1, y1), Vector2(p0, y1)]),
			PoolColorArray([Color(hz.r, hz.g, hz.b, 0.0), Color(hz.r, hz.g, hz.b, 0.0), Color(hz.r, hz.g, hz.b, 0.55), Color(hz.r, hz.g, hz.b, 0.55)]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _ground_px(wx: float) -> float:
	var c = int(floor(wx / grid.CELL))
	var acc := 0.0
	for k in [-60, -30, 0, 30, 60]:
		acc += grid.surf_y(c + k)
	return acc / 5.0 * grid.CELL


func _clouds(v: Rect2) -> void:
	var xf = _xf(0.12)
	var s: float = xf[0]
	var off: Vector2 = xf[1]
	draw_set_transform(off, 0.0, Vector2(s, s))
	var p0 = (v.position.x - off.x) / s - 300.0
	var p1 = (v.end.x - off.x) / s + 300.0
	var span = 520.0
	var i0 = int(floor((p0 - _t * 9.0) / span))
	var i1 = int(ceil((p1 - _t * 9.0) / span))
	for i in range(i0, i1 + 1):
		var hh = fmod(abs(sin(i * 91.7) * 43758.5453), 1.0)
		if hh < 0.35:
			continue
		var p = Vector2(i * span + _t * 9.0 + hh * 200.0, anchor.y - 430.0 - hh * 260.0)
		var sc = 0.7 + 0.8 * fmod(hh * 7.3, 1.0)
		for k in [[Vector2(-26, 4), 20], [Vector2(0, -6), 26], [Vector2(26, 4), 19], [Vector2(8, 8), 20]]:
			draw_circle(p + k[0] * sc, (k[1] + 3) * sc, Color(1, 1, 1, 0.4))
		for k in [[Vector2(-26, 4), 20], [Vector2(0, -6), 26], [Vector2(26, 4), 19], [Vector2(8, 8), 20]]:
			draw_circle(p + k[0] * sc, k[1] * sc, Color(1, 1, 1, 0.88))
		draw_circle(p + Vector2(-8, 10) * sc, 16.0 * sc, Color(0.86, 0.9, 0.95, 0.9))
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
