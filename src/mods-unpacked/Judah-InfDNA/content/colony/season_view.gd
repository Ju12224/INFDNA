extends Node2D
# The year's drifting things in the near air: blossom petals in spring, falling leaves in autumn (snow is in weather_view.gd,
# the grass, trees and snow cover in ground_view.gd). Screen-anchored and deterministic, so nothing is stored; they stop at the
# ground like rain does. Purely visual.

const Seasons = preload("res://mods-unpacked/Judah-InfDNA/core/seasons.gd")
const AL = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const LEAF_N = 10             # the owner's falling leaves: content/art/leaves/leaf_<n>.png (tools/art/make_ui_sheet2.py)
const LEAF_COLORS = [Color("#d9822b"), Color("#c8461e"), Color("#e2b632"), Color("#a82f22"), Color("#e8892b")]
const PETAL_COLORS = [Color("#fbd1de"), Color("#ffffff"), Color("#f7b6cb")]

var sim
var cam
var ground
var day
var perf
var _t := 0.0
var _was := false
var _leaf_tex := []           # loaded on first use; empty entries fall back to the drawn leaf


static func _h(a: float, b: float = 0.0) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


func _process(delta: float) -> void:
	_t += delta
	var on = day != null and (_leaf_k() > 0.02 or _petal_k() > 0.02)
	# (a canvas keeps its last drawing until update() is called again, so the frame after it goes quiet must be drawn too, or the last bird / flag / leaf / raindrop stays frozen on screen)
	if on or _was:
		update()
	_was = on


# Leaves come down from the middle of autumn until the trees are bare.
func _leaf_k() -> float:
	return day.autumn * (1.0 if day.leaf > 0.04 else 0.0) * (1.0 - day.snow)


# Petals while the spring blossom is out.
func _petal_k() -> float:
	return (1.0 - smoothstep(0.05, 0.2, Seasons.phase(day.sea_t))) * (1.0 - day.snow)


func _draw() -> void:
	if day == null or cam == null:
		return
	var z = cam.zoom.x
	if z > 2.6 or (perf != null and perf.backdrop < 2):
		return
	var vp = get_viewport_rect().size
	var tl = cam.get_camera_screen_center() - vp * z * 0.5
	var lk = _leaf_k()
	if lk > 0.02:
		_leaves(tl, vp, z, lk)
	var pk = _petal_k()
	if pk > 0.02:
		_petals(tl, vp, z, pk)


func _leaves(tl: Vector2, vp: Vector2, z: float, k: float) -> void:
	var C = sim.grid.CELL
	var n = int(26.0 * k)
	var size = max(1.0, z * 0.9)
	for i in n:
		var hx = _h(i * 1.71, 21.0)
		var hy = _h(i * 2.33, 22.0)
		var fall = 0.05 + 0.07 * hx
		var y = fposmod(hy + _t * fall, 1.0)
		var sway = sin(_t * (0.6 + hx) + i * 1.7) * 0.03
		var x = fposmod(hx * 1.31 + sway + _t * 0.01, 1.0)
		var p = tl + Vector2(x * vp.x, y * vp.y) * z
		if ground != null and p.y > ground.smooth_px(int(floor(p.x / C))) - 4.0:
			continue
		var rot = _t * (0.8 + hx) + i * 2.1
		var w = (6.0 + 5.0 * hy) * size
		var flip = 0.35 + 0.65 * abs(sin(_t * (1.2 + hx * 1.5) + i))      # it tumbles: seen edge-on, then flat
		var tex = _leaf(int(_h(i, 24.0) * (LEAF_N - 0.01)))
		draw_set_transform(p, rot, Vector2(1.0, flip))
		if tex != null:
			var ts = tex.get_size()
			var lw = w * 2.6
			var lh = lw * ts.y / max(1.0, ts.x)
			draw_texture_rect(tex, Rect2(-lw * 0.5, -lh * 0.5, lw, lh), false)
		else:
			var col = LEAF_COLORS[int(_h(i, 23.0) * 4.99)]
			draw_colored_polygon(PoolVector2Array([Vector2(-w, 0), Vector2(-w * 0.3, -w * 0.5), Vector2(w * 0.5, -w * 0.38), Vector2(w, 0), Vector2(w * 0.4, w * 0.4), Vector2(-w * 0.3, w * 0.48)]), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _leaf(n: int):
	if _leaf_tex.empty():
		var lib = AL.get_lib()
		for k in LEAF_N:
			_leaf_tex.append(lib.tex("leaves/leaf_%d.png" % k))
	return _leaf_tex[n]


func _petals(tl: Vector2, vp: Vector2, z: float, k: float) -> void:
	var C = sim.grid.CELL
	var n = int(18.0 * k)
	var size = max(1.0, z * 0.9)
	for i in n:
		var hx = _h(i * 1.93, 31.0)
		var hy = _h(i * 2.71, 32.0)
		var fall = 0.035 + 0.04 * hx
		var y = fposmod(hy + _t * fall, 1.0)
		var x = fposmod(hx * 1.17 + sin(_t * (0.5 + hx) + i * 2.3) * 0.035 + _t * 0.016, 1.0)
		var p = tl + Vector2(x * vp.x, y * vp.y) * z
		if ground != null and p.y > ground.smooth_px(int(floor(p.x / C))) - 4.0:
			continue
		var col = PETAL_COLORS[int(_h(i, 33.0) * 2.99)]
		var r = (2.4 + 1.6 * hy) * size
		draw_set_transform(p, _t * (1.0 + hx) + i, Vector2(1.0, 0.55 + 0.45 * abs(sin(_t * 1.6 + i))))
		draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, 0.9))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
