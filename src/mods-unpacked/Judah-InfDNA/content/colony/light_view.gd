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
		var ring := []
		for k in n:
			var a = TAU * k / n
			var px = bx + cos(a) * rx
			var sy = ground.smooth_px(int(floor(px / C)))
			ring.append(Vector2(px, sy - 66.0 + sin(a) * 52.0))
		var cy = ground.smooth_px(int(floor(bx / C))) - 66.0
		for k in n:
			draw_polygon(PoolVector2Array([Vector2(bx, cy), ring[k], ring[(k + 1) % n]]), PoolColorArray([d, Color.white, Color.white]))


static func _hh(a: float, b: float) -> float:
	return fmod(abs(sin(a * 12.9898 + b * 78.233) * 43758.5453), 1.0)


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
	var px = x0
	var py = ground.smooth_px(int(floor(px / C)))
	for i in range(1, n + 1):
		var x = x0 + step * i
		var y = ground.smooth_px(int(floor(x / C)))
		if py > top and y > top:
			draw_polygon(PoolVector2Array([Vector2(px, top), Vector2(x, top), Vector2(x, y + lip), Vector2(px, py + lip)]), PoolColorArray([t, t, t, t]))
		draw_polygon(PoolVector2Array([Vector2(px, py + lip), Vector2(x, y + lip), Vector2(x, y + lip + fade), Vector2(px, py + lip + fade)]), PoolColorArray([t, t, white, white]))
		px = x
		py = y
