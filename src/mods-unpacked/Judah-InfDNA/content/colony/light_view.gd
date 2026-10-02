extends Node2D
# The colour of the light on the surface. Drawn after the sky, ground, units and effects, it multiplies
# everything above the ground line by the day cycle's tint (blue at night, warm at dusk), so one cheap pass
# lights the whole scene and the tunnels keep their own warm light. (A tint per mesh is not an option: GLES2
# ignores the modulate of draw_mesh for vertex-coloured meshes.) Skipped entirely in full daylight.

var sim
var cam
var ground
var day


func _ready() -> void:
	var m = CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	material = m


func _process(_delta: float) -> void:
	update()


func _draw() -> void:
	if day == null or cam == null or ground == null:
		return
	var t: Color = day.tint
	if t.r > 0.995 and t.g > 0.995 and t.b > 0.995:
		return
	var vp = get_viewport_rect().size
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
