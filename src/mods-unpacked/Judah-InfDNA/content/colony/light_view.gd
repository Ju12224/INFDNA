extends Node2D
# The colour of the light on the surface. Drawn after the sky, ground, units and effects, it multiplies
# everything above the ground line by the day cycle's tint (blue at night, warm at dusk), so one cheap pass
# lights the whole scene and the tunnels keep their own warm light. (A tint per mesh is not an option: GLES2
# ignores the modulate of draw_mesh for vertex-coloured meshes.) Skipped entirely in full daylight.

var sim
var cam
var ground
var day
var perf
var _t := 0.0


func _ready() -> void:
	var m = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = m


func _process(delta: float) -> void:
	_t += delta
	update()


# Cloud shadows: soft dark patches that drift across the meadow, multiplied over everything on the ground (ants, scenery
# and all). Only in clear daylight; under an overcast sky or at night the light is flat.
func _cloud_shadows(vp: Vector2, z: float, c: Vector2) -> void:
	var C = sim.grid.CELL
	var span = 1500.0
	var x0 = c.x - vp.x * z * 0.5 - 500.0
	var x1 = c.x + vp.x * z * 0.5 + 500.0
	var strength = (1.0 - day.night) * (1.0 - clamp(day.cloud * 2.0, 0.0, 1.0)) * (1.0 - day.warm * 0.6)
	if strength < 0.05:
		return
	for i in range(int(floor(x0 / span)) - 1, int(ceil(x1 / span)) + 1):
		var h = _hh(i * 2.9, 5.0)
		if h < 0.3:
			continue
		var bx = i * span + fposmod(_t * (9.0 + 8.0 * h) + h * span, span)
		var rx = 260.0 + 300.0 * _hh(i * 4.1, 6.0)
		if bx + rx < x0 or bx - rx > x1:
			continue
		var d = Color(1.0 - 0.17 * strength, 1.0 - 0.14 * strength, 1.0 - 0.1 * strength)
		var n = 20
		# a fan of n triangles around the centre (dark in the middle, white at the rim), handed over as ONE triangle list
		# (the same triangles that used to go out as n separate polygons)
		var pts := PoolVector2Array()
		var cols := PoolColorArray()
		pts.resize(n + 1)
		cols.resize(n + 1)
		pts[0] = Vector2(bx, ground.smooth_px(int(floor(bx / C))) - 66.0)
		cols[0] = d
		for k in n:
			var a = TAU * k / n
			var px = bx + cos(a) * rx
			var sy = ground.smooth_px(int(floor(px / C)))
			pts[k + 1] = Vector2(px, sy - 66.0 + sin(a) * 52.0)
			cols[k + 1] = Color.white
		VisualServer.canvas_item_add_triangle_array(get_canvas_item(), _fan_idx(n), pts, cols)


static func _hh(a: float, b: float) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


var _fan := {}      # n -> PoolIntArray: centre 0, rim 1..n, triangle k = (0, k, k+1) wrapping round
var _strip := {}    # n -> PoolIntArray: quads between two rows of n+1 points (row a = 0..n, row b = n+1..2n+1)


func _fan_idx(n: int) -> PoolIntArray:
	if not _fan.has(n):
		var idx := PoolIntArray()
		for k in n:
			idx.append(0)
			idx.append(k + 1)
			idx.append((k + 1) % n + 1)
		_fan[n] = idx
	return _fan[n]


# Quad i is (a[i-1], a[i], b[i], b[i-1]) split along a[i-1]-b[i]; with a colour that only changes from row to row (or not at all)
# the split does not show, so this is what the old one-polygon-per-quad drawing gave.
func _strip_idx(n: int) -> PoolIntArray:
	if not _strip.has(n):
		var idx := PoolIntArray()
		for i in range(1, n + 1):
			var a0 = i - 1
			var a1 = i
			var b1 = n + 1 + i
			var b0 = n + i
			idx.append(a0)
			idx.append(a1)
			idx.append(b1)
			idx.append(a0)
			idx.append(b1)
			idx.append(b0)
		_strip[n] = idx
	return _strip[n]


func _draw() -> void:
	if day == null or cam == null or ground == null:
		return
	var t: Color = day.tint
	var vp = get_viewport_rect().size
	if perf == null or perf.backdrop >= 2:
		_cloud_shadows(vp, cam.zoom.x, cam.get_camera_screen_center())
	if t.r > 0.995 and t.g > 0.995 and t.b > 0.995:
		return
	var z = cam.zoom.x
	var c = cam.get_camera_screen_center()
	var x0 = c.x - vp.x * z * 0.5 - 40.0
	var x1 = c.x + vp.x * z * 0.5 + 40.0
	var top = c.y - vp.y * z * 0.5 - 40.0
	var C = sim.grid.CELL
	var n = 56
	var step = (x1 - x0) / n
	var lip = 9.0                 # the turf lip hangs a little below the height line: tint it too
	var fade = 16.0               # a soft edge where the lit air meets the dirt
	var white = Color.white
	# the same quads as one polygon each used to give, sent as two triangle lists: the tinted air down to the turf lip (a row
	# along the top edge over a row along the lip), then the soft edge under it (lip row over the row `fade` lower)
	var band := PoolVector2Array()
	var edge := PoolVector2Array()
	band.resize(2 * n + 2)
	edge.resize(2 * n + 2)
	var all_low = true
	var ys := []
	ys.resize(n + 1)
	for i in n + 1:
		var x = x0 + step * i
		var y = ground.smooth_px(int(floor(x / C)))
		ys[i] = y
		if y <= top:
			all_low = false
		band[i] = Vector2(x, top)
		band[n + 1 + i] = Vector2(x, y + lip)
		edge[i] = Vector2(x, y + lip)
		edge[n + 1 + i] = Vector2(x, y + lip + fade)
	var tint_cols := PoolColorArray()
	var edge_cols := PoolColorArray()
	tint_cols.resize(2 * n + 2)
	edge_cols.resize(2 * n + 2)
	for i in n + 1:
		tint_cols[i] = t
		tint_cols[n + 1 + i] = t
		edge_cols[i] = t
		edge_cols[n + 1 + i] = white
	var ci = get_canvas_item()
	var idx = _strip_idx(n)
	if not all_low:
		# where the ground rises above the top of the view a quad is left out, as before
		idx = PoolIntArray()
		for i in range(1, n + 1):
			if ys[i - 1] > top and ys[i] > top:
				idx.append(i - 1)
				idx.append(i)
				idx.append(n + 1 + i)
				idx.append(i - 1)
				idx.append(n + 1 + i)
				idx.append(n + i)
	if idx.size() > 0:
		VisualServer.canvas_item_add_triangle_array(ci, idx, band, tint_cols)
	VisualServer.canvas_item_add_triangle_array(ci, _strip_idx(n), edge, edge_cols)
