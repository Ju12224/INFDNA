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


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _process(delta: float) -> void:
	_t += delta
	if day != null and day.rain > 0.02:
		update()


func _draw() -> void:
	if day == null or cam == null or day.rain < 0.02:
		return
	var r: float = day.rain
	var vp = get_viewport_rect().size
	var z = cam.zoom.x
	var c = cam.get_camera_screen_center()
	var tl = c - vp * z * 0.5
	var lite = perf != null and perf.backdrop < 2
	var n = int((60 if lite else 170) * r)
	var slant = Vector2(-0.2, 1.0).normalized()
	for k in n:
		var hx = _h(k * 1.71, 3.0)
		var hy = _h(k * 2.33, 4.0)
		var y = fposmod(hy + _t * (1.25 + 0.9 * hx), 1.0)
		var x = fposmod(hx * 1.37 + y * 0.1, 1.0)
		var p = tl + Vector2(x * vp.x, y * vp.y) * z
		var ln = (16.0 + 26.0 * hx) * z
		if ground != null and p.y + ln * slant.y > ground.smooth_px(int(floor(p.x / sim.grid.CELL))) + 4.0:
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
