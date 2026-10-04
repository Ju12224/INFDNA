extends Node2D
# Rain: slanted streaks falling across the whole view and little splash rings on the ground. Drawn above the
# light pass so it stays bright; the grey light itself comes from day_cycle.gd. Purely visual (the rain's effect on
# the scent trails is in colony_sim._step_weather).

const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")

var sim
var cam
var ground
var day
var perf
var _t := 0.0
var _was := false


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _active() -> bool:
	return day != null and (day.rain > 0.02 or day.wet > 0.04 or day.snow > 0.05)


func _process(delta: float) -> void:
	_t += delta
	var on = _active()
	# (a canvas keeps its last drawing until update() is called again, so the frame after it goes quiet must be drawn too, or the last bird / flag / leaf / raindrop stays frozen on screen)
	if on or _was:
		update()
	_was = on


# Puddles: shallow shiny pools on the open ground that outlast the rain and slowly dry. Each reflects the sky and gets
# ripple rings while the rain is still falling.
func _puddles(tl: Vector2, vp: Vector2, z: float) -> void:
	if ground == null or z > 2.2:
		return
	var C = sim.grid.CELL
	var wet: float = day.wet
	var span = 150.0
	var i0 = int(floor(tl.x / span)) - 1
	var i1 = int(ceil((tl.x + vp.x * z) / span)) + 1
	var sky = Color(0.62, 0.78, 0.92)
	if day.night > 0.3:
		sky = Color(0.25, 0.32, 0.5)
	for i in range(i0, i1 + 1):
		var h = _h(i * 3.77, 11.0)
		if h < 0.4:
			continue
		var lane = 0.15 + 0.8 * _h(i * 1.9, 12.0)
		var px = i * span + _h(i * 5.1, 13.0) * span
		var col = int(floor(px / C))
		var ps = GroundView.persp(lane)
		var p = Vector2(px, GroundView.lane_y(ground.smooth_px(col), lane))
		# a puddle fills with the first rain, so the smaller ones appear a little later and dry first
		var size = clamp((wet - (h - 0.4) * 0.6) * 2.2, 0.0, 1.0)
		if size <= 0.02:
			continue
		var rx = (24.0 + 42.0 * _h(i * 7.3, 14.0)) * ps * size
		var ry = rx * 0.17
		draw_set_transform(p, 0.0, Vector2(1.0, 1.0))
		_ellipse(Vector2.ZERO, rx * 1.12, ry * 1.25, Color(0.1, 0.08, 0.05, 0.28 * size))
		_ellipse(Vector2.ZERO, rx, ry, Color(sky.r, sky.g, sky.b, 0.55 * size))
		_ellipse(Vector2(-rx * 0.15, -ry * 0.25), rx * 0.55, ry * 0.4, Color(1, 1, 1, 0.3 * size))
		if day.rain > 0.1:
			var ph = fposmod(_t * 1.3 + h * 7.0, 1.0)
			draw_arc(Vector2.ZERO, rx * (0.2 + 0.7 * ph), 0.0, TAU, 20, Color(1, 1, 1, (1.0 - ph) * 0.5 * size), 1.4)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Snowflakes: slow, swaying, soft; they settle out of sight at the ground.
func _snowfall(r: float, tl: Vector2, vp: Vector2, z: float) -> void:
	var lite = perf != null and perf.backdrop < 2
	var n = int((70 if lite else 190) * r)
	var C = sim.grid.CELL
	for k in n:
		var hx = _h(k * 1.71, 3.0)
		var hy = _h(k * 2.33, 4.0)
		var y = fposmod(hy + _t * (0.15 + 0.13 * hx), 1.0)
		var x = fposmod(hx * 1.37 + sin(_t * 0.7 + k * 1.3) * 0.015 + _t * 0.012 * (hx - 0.5), 1.0)
		var p = tl + Vector2(x * vp.x, y * vp.y) * z
		if ground != null and p.y > ground.smooth_px(int(floor(p.x / C))) - 2.0:
			continue
		var sz = (1.3 + 2.0 * hy) * max(1.0, z * 0.8)
		var a = (0.45 + 0.45 * hx) * clamp(r * 1.6, 0.3, 1.0)
		if sz > 2.4:
			draw_circle(p, sz * 2.0, Color(1, 1, 1, a * 0.16))
		draw_circle(p, sz, Color(1, 1, 1, a))


var _unit := PoolVector2Array()     # 18 points round the unit circle, scaled into each ellipse in one call


func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	if _unit.empty():
		for k in 18:
			var a = TAU * k / 18.0
			_unit.append(Vector2(cos(a), sin(a)))
	draw_colored_polygon(Transform2D(Vector2(rx, 0.0), Vector2(0.0, ry), c).xform(_unit), col)


func _draw() -> void:
	if day == null or cam == null or not _active():
		return
	var vp0 = get_viewport_rect().size
	var c0 = cam.get_camera_screen_center()
	if day.snowing:
		# winter: whatever falls is snow, and there are flurries even on a calm day
		var sr = max(day.rain, 0.22 * day.snow)
		if sr >= 0.02:
			_snowfall(sr, c0 - vp0 * cam.zoom.x * 0.5, vp0, cam.zoom.x)
		return
	if day.wet > 0.04:
		_puddles(c0 - vp0 * cam.zoom.x * 0.5, vp0, cam.zoom.x)
	if day.rain < 0.02:
		return
	var r: float = day.rain
	var vp = vp0
	var z = cam.zoom.x
	var c = c0
	var tl = c - vp * z * 0.5
	var lite = perf != null and perf.backdrop < 2
	var n = int((60 if lite else 170) * r)
	var slant = Vector2(-0.2, 1.0).normalized()
	var C0 = sim.grid.CELL
	for k in n:
		var hx = _h(k * 1.71, 3.0)
		var hy = _h(k * 2.33, 4.0)
		var y = fposmod(hy + _t * (1.25 + 0.9 * hx), 1.0)
		var x = fposmod(hx * 1.37 + y * 0.1, 1.0)
		var p = tl + Vector2(x * vp.x, y * vp.y) * z
		var ln = (16.0 + 26.0 * hx) * z
		if ground != null and p.y + ln * slant.y > ground.smooth_px(int(floor(p.x / C0))) + 4.0:
			continue          # the rain stops at the ground
		draw_line(p, p + slant * ln, Color(0.86, 0.93, 1.0, (0.3 + 0.4 * hx) * r), max(1.2, 1.7 * z * (0.6 + 0.6 * hx)), false)
	if ground == null or z > 2.6:
		return
	# splash rings where the drops land, spread over the walking lanes
	var C = sim.grid.CELL
	var m = 26 if lite else 60
	for k in int(m * r):
		var ph = fposmod(_t * (1.4 + 0.8 * _h(k, 7.0)) + _h(k, 8.0), 1.0)
		var wx = tl.x + _h(k * 3.7, 9.0) * vp.x * z
		var sy = ground.smooth_px(int(floor(wx / C)))
		var lane = _h(k * 1.3, 10.0)
		var ps = GroundView.persp(lane)
		var gp = Vector2(wx, GroundView.lane_y(sy, lane))
		if gp.y < tl.y or gp.y > tl.y + vp.y * z:
			continue
		draw_set_transform(gp, 0.0, Vector2(1.0, 0.35))
		draw_arc(Vector2.ZERO, (2.0 + 9.0 * ph) * ps, 0.0, TAU, 12, Color(0.9, 0.96, 1.0, (1.0 - ph) * 0.55 * r), max(1.0, 1.4 * ps), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
