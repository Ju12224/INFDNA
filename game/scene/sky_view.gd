extends Node2D
# The sky behind everything, drawn in screen space on its own canvas layer: the colour of the hour, stars at night, the sun and the
# moon on their arcs, drifting clouds, and the owner's three hill strips (far, middle, near), each scrolling slower and shrinking less
# with the zoom the farther away it is. The horizon is the world's original ground line seen through the camera, so the hills sink
# out of view when the camera goes down into the nest. All pictures come from art/sky (tools/art/make_sky.py).

const Art = preload("res://scene/art.gd")

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

var colony
var _stars := []             # [x 0..1, y 0..1, size px, twinkle phase, picture]
var _clouds := []            # [picture, x (screen px at t = 0), height 0..1 of the sky, scale, speed px/s]
var _hills := []             # [picture, entry of HILLS]
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
			_hills.append([Art.tex(e["file"]), h])


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


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
	# clouds
	var span = vs.x + 900.0 * k
	var shade = Color.WHITE.lerp(Color(0.62, 0.66, 0.72), day.cloud) * day.tint
	for c in _clouds:
		var tex: Texture2D = c[0]
		var size = tex.get_size() * c[3] * k
		var x = fposmod(c[1] * k + _t * c[4] - cpos.x * z * CLOUD_SCROLL, span) - size.x
		draw_texture_rect(tex, Rect2(Vector2(x, c[2] * hz * 0.8), size), false, shade)
	# hills, far to near
	for h in _hills:
		var tex: Texture2D = h[0]
		var e = h[1]
		var s = e[2] * k * pow(z / REF_ZOOM, e[3])
		var size = tex.get_size() * s
		var bottom = hz - e[4] * size.y + 2.0
		var x = -fposmod(cpos.x * z * e[1], size.x)
		while x < vs.x:
			draw_texture_rect(tex, Rect2(Vector2(x, bottom - size.y), size + Vector2(1, 0)), false, day.tint)
			x += size.x


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
