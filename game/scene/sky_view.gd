extends Node2D
# The sky behind everything, drawn in screen space on its own canvas layer: the colour of the hour, stars at night, the sun and the
# moon on their arcs, drifting clouds, and the owner's three hill strips (far, middle, near), each scrolling slower and shrinking less
# with the zoom the farther away it is. The horizon is the world's original ground line seen through the camera, so the hills sink
# out of view when the camera goes down into the nest. All pictures come from art/sky (tools/art/make_sky.py).

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const Seasons = preload("res://core/seasons.gd")
const FoliageTint = preload("res://scene/foliage_tint.gd")

# sky colour at the top of the screen and at the horizon: day, sunrise/sunset glow, night, overcast
const DAY_TOP = Color("#4f8fd6")
const DAY_LOW = Color("#b9dcf3")
const WARM_TOP = Color("#4a5d9a")
const WARM_LOW = Color("#f2a66e")
const NIGHT_TOP = Color("#0a1130")
const NIGHT_LOW = Color("#24325e")
const GREY_TOP = Color("#6f7b8c")
const GREY_LOW = Color("#b1b8c0")
const REF_H = 720.0          # screen height the sizes below are tuned for
const REF_ZOOM = 2.5         # the camera's starting zoom
# hill strips, back to front: [name, scroll (share of the ground's screen movement), size (screen px per picture px at REF_ZOOM),
# how strongly the size follows the zoom, lift (share of its height its bottom sits above the horizon)]
const HILLS = [["far", 0.05, 0.62, 0.12, 0.42], ["mid", 0.12, 0.6, 0.25, 0.22], ["near", 0.25, 0.62, 0.4, 0.04]]
const SUN_PX = 110.0
const MOON_PX = 90.0
const STARS = 90
const CLOUDS = 9
const CLOUD_SCROLL = 0.02    # clouds drift with the wind and barely with the camera
const CLOUD_H0 = 0.08        # a cloud's height (_clouds, 0..1 of the sky) runs from this ...
const CLOUD_H1 = 0.5         # ... to this: the top of the free sky to just above the highest hill
const CLOUD_TOP = 0.03       # share of the screen's height kept clear above the highest cloud
const CLOUD_AIR = 6.0        # px between a cloud's lowest edge and the hill behind which it would sink
const CLOUD_FIT_MIN = 0.5    # how far a cloud shrinks to fit a thin strip of sky
const TINTED = ["mid", "near"]                # the hill strips that get the year's colour: the far one is mountains
# The hill strips through the year: the tint the year gives (the vertex colour, foliage_tint.gd) is applied to the green parts of the picture
# only (trees, meadows), so the trunks, rocks and the blue haze of the far hills stay as the owner drew them. day_tint is the hour's colour.
const HILL_SHADER = """
shader_type canvas_item;
uniform vec3 day_tint = vec3(1.0);
varying vec4 vcol;
void vertex() { vcol = COLOR; }
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float green = smoothstep(0.02, 0.12, t.g - max(t.r, t.b));
	COLOR = vec4(t.rgb * mix(vec3(1.0), vcol.rgb, green) * day_tint, t.a);
}
"""
const TILE_SLICES = 48       # slices across a tinted tile, each with its own colour

var colony
var _stars := []             # [x 0..1, y 0..1, size px, twinkle phase, picture]
var _clouds := []            # [picture, x (screen px at t = 0), height 0..1 of the sky, scale, speed px/s]
var _hills := []             # [picture, entry of HILLS, colour of its bottom rows]
var _back: Node2D            # draws the far mountains, the clouds and the nearer strips' ground colour (_draw_back)
var _front: Node2D           # draws the nearer strips' pictures through HILL_SHADER (_draw_front)
var _hill_mat := ShaderMaterial.new()
var _t := 0.0


func _ready() -> void:
	var man = Art.manifest("sky/sky_manifest.json")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var star_tex := []
	for s in man.get("stars", []):
		star_tex.append(Art.tex(s["file"]))
	for i in STARS:
		if star_tex.is_empty():
			break
		_stars.append([rng.randf(), pow(rng.randf(), 1.4) * 0.8, rng.randf_range(5.0, 13.0), rng.randf() * TAU, star_tex[rng.randi() % star_tex.size()]])
	var cloud_tex := []
	for c in man.get("clouds", []):
		cloud_tex.append(Art.tex(c["file"]))
	for i in CLOUDS:
		if cloud_tex.is_empty():
			break
		_clouds.append([cloud_tex[rng.randi() % cloud_tex.size()], rng.randf_range(0.0, 2400.0), rng.randf_range(0.08, 0.5), rng.randf_range(0.28, 0.5), rng.randf_range(4.0, 11.0)])
	for h in HILLS:
		var e = man.get("hills", {}).get(h[0])
		if e != null:
			var tex = Art.tex(e["file"])
			_hills.append([tex, h, _bottom_colour(tex)])
	var sh = Shader.new()
	sh.code = HILL_SHADER
	_hill_mat.shader = sh
	_back = _item(_draw_back, null)
	_front = _item(_draw_front, _hill_mat)


func _process(delta: float) -> void:
	_t += delta
	var tint: Color = colony.day.tint
	_hill_mat.set_shader_parameter("day_tint", Vector3(tint.r, tint.g, tint.b))
	queue_redraw()
	_back.queue_redraw()
	_front.queue_redraw()


func _draw() -> void:
	var vs = get_viewport_rect().size
	var z = colony.zoom()
	var cpos = colony.cam_center()
	var day = colony.day
	var hz = (colony.ground_y() - cpos.y) * z + vs.y * 0.5       # the horizon on screen
	var k = vs.y / REF_H
	# the colour of the hour
	var top = DAY_TOP.lerp(WARM_TOP, day.warm * 0.7).lerp(NIGHT_TOP, day.night)
	var low = DAY_LOW.lerp(WARM_LOW, day.warm * 0.8).lerp(NIGHT_LOW, day.night)
	top = top.lerp(GREY_TOP * Color(top.v + 0.2, top.v + 0.2, top.v + 0.2), day.cloud * 0.7)
	low = low.lerp(GREY_LOW * Color(low.v + 0.1, low.v + 0.1, low.v + 0.1), day.cloud * 0.7)
	var sky_h = clamp(hz, 1.0, vs.y)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, sky_h), Vector2(0, sky_h)]),
		PackedColorArray([top, top, low, low]))
	if sky_h < vs.y:
		draw_rect(Rect2(0, sky_h, vs.x, vs.y - sky_h), low)
	if hz <= 0.0:
		return                                                   # the camera is deep underground: no sky in view
	# stars
	var star_a = day.night * (1.0 - day.cloud)
	if star_a > 0.02:
		for s in _stars:
			var p = Vector2(fposmod(s[0] * vs.x - cpos.x * z * 0.01, vs.x), s[1] * hz)
			var a = star_a * (0.65 + 0.35 * sin(_t * 1.7 + s[3]))
			_draw_centered(s[4], p, s[2] * k, Color(1, 1, 1, a))
	# sun and moon on their arcs, rising at the left and setting at the right
	var man = Art.manifest("sky/sky_manifest.json")
	var sun_u = (day.ph - 0.25) / 0.5
	if sun_u > -0.05 and sun_u < 1.05 and man.has("sun"):
		_draw_centered(Art.tex(man["sun"]["file"]), _arc(sun_u, vs, hz), SUN_PX * k, Color(1, 1, 1, 1.0 - day.cloud * 0.6))
	var moon_u = fposmod(day.ph - 0.75, 1.0) / 0.5
	if moon_u < 1.05 and man.has("moon_full"):
		var moon = man["moon_full"] if day.day_n % 4 == 0 else man["moon_crescent"]
		_draw_centered(Art.tex(moon["file"]), _arc(moon_u, vs, hz), MOON_PX * k, Color(1, 1, 1, 1.0 - day.cloud * 0.6))


# The layout of the layers behind the meadow for this frame: [screen size, horizon y, hill strips' places, ridge]. A hill strip's place is
# [its size on screen, y of its bottom]; their foot is tucked behind the back lanes of the meadow band (band.gd), which stand above the
# ground line. ridge is the y of the highest point of the strips in front of the first one (the clouds stay above it).
func _layout() -> Array:
	var vs = get_viewport_rect().size
	var z = colony.zoom()
	var k = vs.y / REF_H
	var hz = (colony.ground_y() - colony.cam_center().y) * z + vs.y * 0.5
	var hh = hz - 0.25 * Band.DEPTH * Band.lift * z
	var geo := []
	for h in _hills:
		var e = h[1]
		var size = h[0].get_size() * (e[2] * k * pow(z / REF_ZOOM, e[3]))
		geo.append([size, hh - e[4] * size.y + 2.0])
	var ridge = hh
	for i in range(1, _hills.size()):
		ridge = minf(ridge, geo[i][1] - geo[i][0].y)
	return [vs, hz, geo, ridge]


func _item(cb: Callable, mat: Material) -> Node2D:
	var n = Node2D.new()
	n.material = mat
	n.draw.connect(cb)
	add_child(n)
	return n


# Behind the hills' green parts: the far mountains, the clouds (in front of the mountains but behind the nearer hills, and kept whole above
# the highest point of those: a cloud that sank behind a hill would show only the arc of its thick outline over the ridge; they shrink to
# fit when the zoom leaves little sky), and the ground the nearer strips' own colours carry on with below them, so a dip in the meadow
# never shows the sky.
func _draw_back() -> void:
	var lay = _layout()
	var vs: Vector2 = lay[0]
	if lay[1] <= 0.0 or _hills.is_empty():
		return                                                   # the camera is deep underground: no sky in view
	var day = colony.day
	var k = vs.y / REF_H
	var geo: Array = lay[2]
	_draw_tiles(_back, 0, lay, false)
	_draw_tiles(_back, 0, lay, true)
	var ridge: float = lay[3]
	var span = vs.x + 900.0 * k
	var shade = Color.WHITE.lerp(Color(0.62, 0.66, 0.72), day.cloud) * day.tint
	var y_lo = CLOUD_TOP * vs.y
	var cpos = colony.cam_center()
	for c in _clouds:
		var tex: Texture2D = c[0]
		var full = tex.get_size() * c[3] * k
		var fit = clampf((ridge - CLOUD_AIR - y_lo) / full.y, CLOUD_FIT_MIN, 1.0)
		var size = full * fit
		var x = fposmod(c[1] * k + _t * c[4] - cpos.x * colony.zoom() * CLOUD_SCROLL, span) - full.x * 0.5 - size.x * 0.5   # (the same centre whatever the fit)
		var y_hi = ridge - CLOUD_AIR - size.y
		var y = lerpf(y_lo, y_hi, clampf((c[2] - CLOUD_H0) / (CLOUD_H1 - CLOUD_H0), 0.0, 1.0)) if y_hi > y_lo else y_hi
		_back.draw_texture_rect(tex, Rect2(Vector2(x, y), size), false, shade)
	for i in range(1, _hills.size()):
		_draw_tiles(_back, i, lay, true)


# The hill strips in front of the clouds: the middle and near ones, the owner's pictures, through the year's colours (see HILL_SHADER).
func _draw_front() -> void:
	var lay = _layout()
	if lay[1] <= 0.0:
		return
	for i in range(1, _hills.size()):
		_draw_tiles(_front, i, lay, false)


# Strip i tiled across the screen: its picture (fill = false) or the ground colour below it (fill = true), on node n. The autumn colour
# slides along the picture (foliage_tint.gd), so its trees and meadows are not one colour; its tint is the vertex colour (the shader
# applies it to the green parts only).
func _draw_tiles(n: Node2D, i: int, lay: Array, fill: bool) -> void:
	var h: Array = _hills[i]
	var vs: Vector2 = lay[0]
	var size: Vector2 = lay[2][i][0]
	var bottom: float = lay[2][i][1]
	var w = Seasons.phase(colony.sim.time)
	var tinted = TINTED.has(h[1][0]) and FoliageTint.weights(w)[1] <= 0.999
	var day_tint: Color = colony.day.tint
	var x = -fposmod(colony.cam_center().x * colony.zoom() * h[1][1], size.x)
	while x < vs.x:
		var r = Rect2(Vector2(x, bottom - size.y), size + Vector2(1, 0))
		if not fill and not tinted:
			n.draw_texture_rect(h[0], r, false, Color.WHITE if n == _front else day_tint)
		elif fill and bottom < vs.y:
			_slices(n, r, h[0], w, tinted, h[2] * day_tint, vs.y)
		elif not fill:
			_slices(n, r, h[0], w, true, Color.WHITE, 0.0)
		x += size.x


# A quad strip across rect r: the picture (tex != null and bottom_y == 0), or the ground below it down to bottom_y, one colour per slice.
func _slices(n: Node2D, r: Rect2, tex: Texture2D, w: float, tinted: bool, col: Color, bottom_y: float) -> void:
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var ground = bottom_y > 0.0
	for i in TILE_SLICES + 1:
		var u = float(i) / TILE_SLICES
		var c = col
		if tinted:
			c = col * FoliageTint.tint(w, FoliageTint.autumn_at(u))
		var px = r.position.x + u * r.size.x
		pts.append(Vector2(px, r.end.y - 1.0 if ground else r.position.y))
		pts.append(Vector2(px, bottom_y if ground else r.end.y))
		uvs.append(Vector2(u, 0.0))
		uvs.append(Vector2(u, 1.0))
		cols.append(c)
		cols.append(c)
		if i < TILE_SLICES:
			var b = i * 2
			idx.append_array([b, b + 2, b + 3, b, b + 3, b + 1])
	RenderingServer.canvas_item_add_triangle_array(n.get_canvas_item(), idx, pts, cols, PackedVector2Array() if ground else uvs,
		PackedInt32Array(), PackedFloat32Array(), RID() if ground else tex.get_rid())


# The average colour of a picture's bottom rows (where a hill strip meets the ground).
static func _bottom_colour(tex: Texture2D) -> Color:
	var img = tex.get_image()
	if img == null:
		return Color(0.2, 0.3, 0.22)
	if img.is_compressed():
		img.decompress()
	var r := Color(0, 0, 0, 0)
	var n := 0
	for y in range(img.get_height() - 4, img.get_height()):
		for x in range(0, img.get_width(), 7):
			var c = img.get_pixel(x, y)
			if c.a > 0.5:
				r += c
				n += 1
	return Color(r.r / n, r.g / n, r.b / n, 1.0) if n > 0 else Color(0.2, 0.3, 0.22)


# Where something on the sky arc is when it is u of the way across (0 = rising at the left, 1 = setting at the right).
func _arc(u: float, vs: Vector2, hz: float) -> Vector2:
	var h = min(hz, vs.y) * 0.8
	return Vector2(vs.x * (0.08 + 0.84 * u), min(hz, vs.y) - h * sin(clamp(u, 0.0, 1.0) * PI) + 30.0)


func _draw_centered(tex: Texture2D, p: Vector2, px: float, mod: Color) -> void:
	if tex == null:
		return
	var sz = tex.get_size()
	var s = px / max(sz.x, sz.y)
	draw_texture_rect(tex, Rect2(p - sz * s * 0.5, sz * s), false, mod)


# The sky's colour at the horizon right now: what the meadow's distance haze blends toward (surface_view.gd).
func horizon_colour() -> Color:
	var day = colony.day
	var low = DAY_LOW.lerp(WARM_LOW, day.warm * 0.8).lerp(NIGHT_LOW, day.night)
	return low.lerp(GREY_LOW * Color(low.v + 0.1, low.v + 0.1, low.v + 0.1), day.cloud * 0.7)
