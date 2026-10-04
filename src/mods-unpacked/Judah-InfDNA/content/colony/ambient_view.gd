extends Node2D
# After dark: the nest mouths glow and fireflies drift over the grass. Purely visual and deterministic (no state). The meadow's critters
# by day are real prey in the sim, drawn with the raiders (the old drawn-only bees, butterflies and crawlers are gone).

const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const SPAN = 300.0

var sim
var cam
var ground
var perf
var live_critters := true   # the sim spawns the meadow's critters as prey (colony_sim._step_critters); the old drawn-only ones stay off
var day              # day_cycle.gd (optional): at night fireflies replace the bees and butterflies
var _t := 0.0
var _was := true


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _process(delta: float) -> void:
	_t += delta
	# by day, with the meadow's critters living in the sim, there is nothing to draw here: no redraw (but the frame after the
	# last glow or firefly goes is drawn once more, empty, or it would stay frozen on screen)
	var on = not live_critters or (day != null and day.night > 0.05)
	if on or _was:
		update()
	_was = on


func _draw() -> void:
	if cam == null or ground == null:
		return
	var z = cam.zoom.x
	var night = day.night if day != null else 0.0
	if night > 0.05:
		_glow(night)
	if z > 2.5 or (perf != null and perf.backdrop < 2):
		return
	var C = sim.grid.CELL
	var half = get_viewport_rect().size.x * z * 0.5
	var cx = cam.get_camera_screen_center().x
	var s0 = int(floor((cx - half - 150.0) / SPAN))
	var s1 = int(ceil((cx + half + 150.0) / SPAN))
	if night > 0.15:
		_fireflies(s0, s1, night)


# The nest mouths glow warm after dark: the colony's light spilling out of the hole.
func _glow(night: float) -> void:
	var C = sim.grid.CELL
	var vr = Rect2(cam.get_camera_screen_center() - get_viewport_rect().size * cam.zoom * 0.5 - Vector2(300, 300), get_viewport_rect().size * cam.zoom + Vector2(600, 600))
	for en in sim.grid.entrances:
		var p = Vector2((en.x + 0.5) * C, ground.smooth_px(int(en.x)) - GroundView.DEPTH * 0.34)
		if not vr.has_point(p):
			continue
		var fl = 0.9 + 0.1 * sin(_t * 3.1 + en.x)
		draw_set_transform(p, 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 120.0, Color(1.0, 0.7, 0.35, 0.06 * night * fl))
		draw_circle(Vector2.ZERO, 74.0, Color(1.0, 0.72, 0.38, 0.10 * night * fl))
		draw_circle(Vector2.ZERO, 40.0, Color(1.0, 0.78, 0.45, 0.16 * night * fl))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Fireflies: a few per 300 px of meadow, blinking on their own rhythm.
func _fireflies(s0: int, s1: int, night: float) -> void:
	var C = sim.grid.CELL
	for s in range(s0, s1 + 1):
		if _h(s * 4.4, 1.0) < 0.3:
			continue
		for k in 3:
			var kk = s * 3 + k
			var bx = s * SPAN + _h(kk, 2.0) * SPAN
			var sy = ground.smooth_px(int(floor(bx / C)))
			var lane = 0.1 + 0.85 * _h(kk, 3.0)
			var ps = GroundView.persp(lane)
			var gy = GroundView.lane_y(sy, lane)
			var tt = _t * (0.3 + 0.4 * _h(kk, 4.0)) + _h(kk, 5.0) * TAU
			var pos = Vector2(bx + cos(tt) * 40.0, gy - (24.0 + 50.0 * _h(kk, 6.0) + sin(tt * 1.7) * 18.0) * ps)
			var blink = max(0.0, sin(_t * 1.6 + _h(kk, 7.0) * TAU))
			var a = night * (0.25 + 0.75 * blink * blink)
			draw_circle(pos, 9.0 * ps, Color(0.8, 1.0, 0.4, 0.10 * a))
			draw_circle(pos, 4.5 * ps, Color(0.85, 1.0, 0.5, 0.35 * a))
			draw_circle(pos, 2.0 * ps, Color(1.0, 1.0, 0.8, 0.9 * a))
