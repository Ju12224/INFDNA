extends Node2D
# The rival colony's nest out on the meadow: a dark pebbly mound with its own hole and a flag, and a few of its ants going about
# their business around it. Drawn under the units, so a strike party fights over it, not behind it. Broken, it is a slumped heap
# with a stump for a flag and a few wisps of smoke. Purely visual (the rival itself lives in core/rival.gd).

const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const INK = Color("#15121a")

var sim
var cam
var ground
var perf
var _t := 0.0


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _process(delta: float) -> void:
	_t += delta
	update()


func _draw() -> void:
	var r = sim.rival
	if cam == null or ground == null or r == null:
		return
	var C = sim.grid.CELL
	var z = cam.zoom.x
	var half = get_viewport_rect().size.x * z * 0.5
	var px = (r.x + 0.5) * C
	if abs(px - cam.get_camera_screen_center().x) > half + 320.0:
		return
	var sy = ground.smooth_px(int(r.x))
	var lane = 0.5
	var gy = GroundView.lane_y(sy, lane)
	var ps = GroundView.persp(lane)
	var alive = r.alive()
	var W = 290.0 * ps
	var H = (140.0 if alive else 56.0) * ps
	# soft shadow on the ground
	draw_set_transform(Vector2(px - W * 0.1, gy + 3.0), 0.0, Vector2(1.0, 0.18))
	draw_circle(Vector2.ZERO, W * 0.68, Color(0.05, 0.08, 0.03, 0.22))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the heap: a bump of dark soil with an ink edge, a lit upper right and loose pebbles
	var top := PoolVector2Array()
	var steps = 16
	for i in steps + 1:
		var u = float(i) / steps * 2.0 - 1.0
		var prof = pow(max(0.0, 1.0 - u * u), 0.7)
		top.append(Vector2(px + u * W * 0.5, gy - H * prof * (0.94 + 0.12 * _h(i, 3.0))))
	var ink_poly := PoolVector2Array()
	var fill := PoolVector2Array()
	for q in top:
		ink_poly.append(q + Vector2(0, -3.5))
		fill.append(q)
	ink_poly.append(Vector2(px + W * 0.5 + 3.5, gy + 3.5))
	ink_poly.append(Vector2(px - W * 0.5 - 3.5, gy + 3.5))
	fill.append(Vector2(px + W * 0.5, gy + 1.0))
	fill.append(Vector2(px - W * 0.5, gy + 1.0))
	draw_colored_polygon(ink_poly, INK)
	draw_colored_polygon(fill, Color("#4f3b2d") if alive else Color("#5a4a3e"))
	var lit := PoolVector2Array()
	for i in range(steps / 2, steps + 1):
		lit.append(top[i] + Vector2(0, 2.0))
	for i in range(steps, steps / 2 - 1, -1):
		lit.append(top[i] + Vector2(-W * 0.07, H * 0.34 * (1.0 - float(i - steps / 2) / (steps / 2.0)) + 6.0))
	draw_colored_polygon(lit, Color(0.78, 0.6, 0.42, 0.34))
	for k in 34:
		var ux = (_h(k, 5.0) * 2.0 - 1.0) * 0.46
		var pp = Vector2(px + ux * W, gy - _h(k, 6.0) * H * pow(max(0.0, 1.0 - (ux * 2.0) * (ux * 2.0)), 0.7) * 0.9)
		var rr = (1.6 + 2.6 * _h(k, 7.0)) * ps
		draw_circle(pp, rr + 0.8, Color(0.1, 0.07, 0.05, 0.7))
		draw_circle(pp, rr, Color("#8d7358") if _h(k, 8.0) > 0.5 else Color("#6a5543"))
	# its hole
	if alive:
		draw_set_transform(Vector2(px, gy - H * 0.2), 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, 26.0 * ps, INK)
		draw_circle(Vector2.ZERO, 19.0 * ps, Color("#0d0806"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the flag on a pole (a stump and some smoke once it is broken)
	var pole = Vector2(px + W * 0.3, gy - H * 0.55)
	if alive:
		var pt = pole + Vector2(0, -80.0 * ps)
		draw_line(pole, pt, INK, 5.0, true)
		draw_line(pole, pt, Color("#c9b79a"), 2.4, true)
		var wv = sin(_t * 3.2) * 3.0 * ps
		draw_colored_polygon(PoolVector2Array([pt + Vector2(0, -2.0), pt + Vector2(62.0 * ps, 10.0 * ps + wv), pt + Vector2(56.0 * ps, 18.0 * ps - wv * 0.5), pt + Vector2(0, 34.0 * ps)]), INK)
		draw_colored_polygon(PoolVector2Array([pt + Vector2(1.0, 0.0), pt + Vector2(56.0 * ps, 10.0 * ps + wv), pt + Vector2(50.0 * ps, 18.0 * ps - wv * 0.5), pt + Vector2(1.0, 30.0 * ps)]), Color("#b32424"))
	else:
		draw_line(pole, pole + Vector2(0, -14.0 * ps), INK, 5.0, true)
		draw_line(pole, pole + Vector2(0, -14.0 * ps), Color("#8a7a64"), 2.4, true)
		for k in 5:
			var u2 = fposmod(_t * 0.25 + k * 0.2, 1.0)
			draw_circle(Vector2(px + sin(_t + k * 1.7) * 8.0 * ps * u2 - 6.0 * ps, gy - H - u2 * 80.0 * ps), (5.0 + 12.0 * u2) * ps, Color(0.5, 0.48, 0.46, 0.35 * (1.0 - u2)))
	# its ants, wandering in and out of the hole and around the mound
	var n_ants = 8 if alive else 2
	for k in n_ants:
		var ph = _t * (0.28 + 0.12 * _h(k, 11.0)) + k * 1.3
		var ax = px + sin(ph) * W * (0.55 + 0.25 * _h(k, 12.0))
		var al = 0.25 + 0.7 * _h(k, 13.0)
		var ap = GroundView.persp(al)
		var ay = GroundView.lane_y(ground.smooth_px(int(ax / C)), al)
		var face = 1 if cos(ph) >= 0.0 else -1
		CreatureArt.draw("redant", self, Vector2(ax, ay), 0.5 * ap, 1.0, 1.0, _t + k, face, k, true, false, 0.0)
	# during a strike: the mound's health once the guards are down
	if sim.strike_t > 0.0 and r.guards_out and alive:
		var bw = 150.0
		var bp = Vector2(px - bw * 0.5, gy - H - 96.0 * ps)
		draw_rect(Rect2(bp - Vector2(3, 3), Vector2(bw + 6, 16)), INK)
		draw_rect(Rect2(bp, Vector2(bw * clamp(r.hp / r.max_hp, 0.0, 1.0), 10)), Color("#e8483b") if r.hit_t > 0.0 else Color("#f2c14e"))
