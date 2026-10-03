extends Node2D
# What the director's orders look like on the ground: the rally flag (pole, waving banner, a ring showing how far its bonus
# reaches, a shrinking arc for the time left) and the harvest marker over a pile (a bobbing gold arrow and a ring).
# Purely visual: the effects themselves live in colony_sim.cast().

const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const INK = Color("#15121a")

var sim
var cam
var ground
var _t := 0.0
var _was := false


func _process(delta: float) -> void:
	_t += delta
	var on = sim != null and (sim.rally_t > 0.0 or sim.harvest_t > 0.0)
	# (a canvas keeps its last drawing until update() is called again, so the frame after it goes quiet must be drawn too, or the last bird / flag / leaf / raindrop stays frozen on screen)
	if on or _was:
		update()
	_was = on


func _draw() -> void:
	if sim == null or ground == null:
		return
	if sim.rally_t > 0.0:
		_rally()
	if sim.harvest_t > 0.0:
		_harvest()


func _anchor(x: int, lane: float) -> Vector2:
	var C = sim.grid.CELL
	return Vector2((x + 0.5) * C, GroundView.lane_y(ground.smooth_px(x), lane))


func _rally() -> void:
	var C = sim.grid.CELL
	var p = _anchor(sim.rally_x, 0.55)
	var ps = GroundView.persp(0.55)
	var left = sim.rally_t
	var fade = clamp(left / 3.0, 0.0, 1.0)
	# the bonus radius on the ground
	draw_set_transform(p, 0.0, Vector2(1.0, 0.32))
	draw_arc(Vector2.ZERO, 16.0 * C * ps, 0.0, TAU, 48, Color(1.0, 0.42, 0.29, 0.35 * fade), 3.0, true)
	draw_arc(Vector2.ZERO, 16.0 * C * ps, -PI * 0.5, -PI * 0.5 + TAU * (left / sim.RALLY_LEN), 48, Color(1.0, 0.7, 0.45, 0.8 * fade), 5.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# the flag: pole, then a banner that waves
	var h = 120.0 * ps
	var top = p + Vector2(0, -h)
	draw_line(p, top, INK, 7.0 * ps, true)
	draw_line(p, top, Color("#d8cdb8"), 3.5 * ps, true)
	var pts := PoolVector2Array()
	var n = 8
	for i in n + 1:
		var u = float(i) / n
		pts.append(top + Vector2(u * 62.0 * ps, sin(_t * 5.0 - u * 3.2) * 6.0 * u * ps))
	var low := PoolVector2Array()
	for i in n + 1:
		var u2 = float(n - i) / n
		low.append(top + Vector2(u2 * 62.0 * ps, 34.0 * ps * (1.0 - 0.25 * u2) + sin(_t * 5.0 - u2 * 3.2) * 6.0 * u2 * ps))
	var poly = pts
	poly.append_array(low)
	draw_colored_polygon(poly, Color(0.94, 0.3, 0.22, fade))
	draw_polyline(poly + PoolVector2Array([poly[0]]), Color(INK.r, INK.g, INK.b, fade), 3.0 * ps, true)
	draw_circle(top, 6.0 * ps, Color("#f2c14e"))


func _harvest() -> void:
	var C = sim.grid.CELL
	var p = _anchor(sim.harvest_x, 0.5)
	var ps = GroundView.persp(0.5)
	var fade = clamp(sim.harvest_t / 4.0, 0.0, 1.0)
	draw_set_transform(p, 0.0, Vector2(1.0, 0.32))
	draw_arc(Vector2.ZERO, 12.0 * C * ps * (0.9 + 0.1 * sin(_t * 3.0)), 0.0, TAU, 40, Color(1.0, 0.85, 0.42, 0.55 * fade), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var bob = sin(_t * 4.0) * 8.0 * ps
	var tip = p + Vector2(0, -52.0 * ps + bob)
	var tri = PoolVector2Array([tip, tip + Vector2(-16.0 * ps, -26.0 * ps), tip + Vector2(16.0 * ps, -26.0 * ps)])
	draw_colored_polygon(tri, Color(1.0, 0.85, 0.42, fade))
	draw_polyline(PoolVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(INK.r, INK.g, INK.b, fade), 3.0 * ps, true)
