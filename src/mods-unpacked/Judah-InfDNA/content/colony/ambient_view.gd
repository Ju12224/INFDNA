extends Node2D
# Ambient wildlife over the meadow: bees working the flower patches, butterflies drifting through. Purely
# visual and deterministic (no state): each 300 px stretch of ground may host a flyer that loops over it. They
# are drawn above the units, cast a soft shadow on the ground, and are skipped when zoomed far out or when the
# optimizer wants the frames. After dark the nest mouths glow and fireflies drift over the grass instead.

const CreatureArt = preload("res://mods-unpacked/Judah-InfDNA/content/colony/creature_art.gd")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const SPAN = 300.0
const WINGS = [Color("#f08fb0"), Color("#f7d046"), Color("#9a7be0"), Color("#f08a3c"), Color("#7fd0f0"), Color("#f5f0e6")]

var sim
var cam
var ground
var perf
var day              # day_cycle.gd (optional): at night fireflies replace the bees and butterflies
var _t := 0.0


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _process(delta: float) -> void:
	_t += delta
	update()


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
	if night > 0.45:
		return          # the bees and butterflies are asleep
	for s in range(s0, s1 + 1):
		var h = _h(s * 7.77)
		if h < 0.4:
			continue
		var kind_bee = _h(s * 3.1, 2.0) > 0.45
		var bx = s * SPAN + _h(s, 5.0) * 200.0
		var col = int(floor(bx / C))
		var sy = ground.smooth_px(col)
		var lane = 0.15 + 0.8 * _h(s * 1.7, 9.0)
		var gy = GroundView.lane_y(sy, lane)
		var ps = GroundView.persp(lane)
		var w = 0.55 + 0.5 * _h(s * 2.3, 3.0)
		var ph = _h(s * 5.9, 4.0) * TAU
		var R = 70.0 + 90.0 * _h(s * 4.1, 6.0)
		var tt = _t * w + ph
		var p = Vector2(bx + cos(tt) * R, 0.0)
		var lift = 40.0 + 70.0 * _h(s * 6.3, 8.0) + sin(tt * 2.0) * 22.0
		var gp = Vector2(p.x, gy)
		var vx = -sin(tt) * R * w
		var face = 1 if vx >= 0.0 else -1
		# soft shadow on the ground under it
		draw_set_transform(gp + Vector2(-6.0, 0.0), 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, (8.0 + 5.0 * ps) * (1.0 - lift * 0.003), Color(0.05, 0.1, 0.03, 0.14))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if kind_bee:
			CreatureArt.draw("bee", self, gp, 0.75 * ps, 1.0, 1.0, _t + s, face, s, true, false, lift)
		else:
			var wc: Color = WINGS[int(_h(s, 1.0) * 5.99)]
			CreatureArt.butterfly(self, gp + Vector2(0.0, -lift - 10.0 + sin(tt * 3.0) * 12.0), 1.3 * ps, _t * 1.0 + s, face, wc, 1.0)


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
