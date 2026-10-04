extends Reference
# The creatures: every one is the owner's drawn art, rigged and animated by rig_art.gd, and the anteater (its own picture set: a body
# and two clawed legs, tools/art/make_anteater.py) animated here. Local origin = the feet on the ground; +x is the way it faces, up is -y.

const INK = Color("#15121a")
const Rig = preload("res://mods-unpacked/Judah-InfDNA/content/colony/rig_art.gd")
const AL = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const ANT_LEN = 380.0      # the anteater nose to tail, local px at scale 1 (the size the old drawn one had)
const ANT_LEG = 0.62       # its legs, as a share of the body picture's height
const ANT_SWING = 0.32     # how far a leg swings each way while it walks (radians)


const RIG_NAMES = {"voidmaw": "void", "redant": "redant_small"}


# Entry point used by enemy_view. `lift` raises flyers off the ground (px, before scale).
static func draw(art: String, ci: CanvasItem, feet: Vector2, scale: float, shade: float, alpha: float, t: float, facing: int, id: int, moving: bool, flash: bool, lift: float, mouth: float = -1.0) -> void:
	# the drawn creatures (the owner's art, rigged in rig_art.gd); the procedural ones below are the fallback when the art files are not there
	var key = RIG_NAMES.get(art, art)
	if Rig.available(key):
		var m = mouth if mouth >= 0.0 else 0.18 + 0.12 * sin(t * 1.7 + id)
		Rig.draw(ci, key, feet - Vector2(0.0, lift * scale), scale, facing, t + id * 0.7, moving, m, Color(shade, shade, shade, alpha), flash)
		return
	if art == "anteater":
		_anteater(ci, feet, scale, facing, t + id * 0.3, moving, shade, alpha, flash)
	# anything else without a picture is not drawn (the old drawn creatures are gone)


# A giant anteater, side-on: shaggy grey-brown, a black shoulder stripe edged in white, a long sniffing snout, a bushy tail and big
# foreclaws. About 350 px from tail to snout before `scale`; it ambles on its knuckles. The tongue is a fx beam from the sim.


# The anteater walking: the far legs (darker) behind the body, then the body, which bobs and rocks a little with the stride, then the near
# legs. Each leg swings from its top (the shoulder or hip, under the fur); diagonal pairs move together, as a four-legged walk does.
static func _anteater(ci: CanvasItem, feet: Vector2, scale: float, facing: int, t: float, moving: bool, shade: float, alpha: float, flash: bool) -> void:
	var lib = AL.get_lib()
	var m = lib.manifest().get("anteater_art")
	if m == null:
		return
	var body = lib.tex(str(m["body"]["file"]))
	var near = lib.tex(str(m["leg_near"]["file"]))
	var far = lib.tex(str(m["leg_far"]["file"]))
	if body == null or near == null or far == null:
		return
	var k = ANT_LEN / float(m["body"]["w"])
	var bs = Vector2(float(m["body"]["w"]), float(m["body"]["h"])) * k
	var leg_h = bs.y * ANT_LEG
	var gait = 3.2 if moving else 0.6
	var ph = t * gait
	var bob = (abs(sin(ph)) * -4.0 if moving else sin(t * 1.3) * 1.0)
	var rock = sin(ph * 2.0) * (0.012 if moving else 0.004)
	var top_left = Vector2(-bs.x * 0.55, -leg_h * 0.88 - 0.80 * bs.y + bob)
	var col = Color(shade, shade, shade, alpha)
	if flash:
		col = Color(1.0, 0.45, 0.42, alpha)
	var col_far = Color(col.r * 0.62, col.g * 0.62, col.b * 0.62, alpha)
	var base = Transform2D(Vector2(facing * scale, 0.0), Vector2(0.0, scale), feet)
	var joins = m["joins"]
	var amp = ANT_SWING if moving else 0.03
	# far side first: front leg in step with the near hind leg, hind leg with the near front leg
	for spec in [["front_far", far, m["leg_far"], PI, col_far], ["hind_far", far, m["leg_far"], 0.0, col_far]]:
		_ant_leg(ci, base, top_left, bs, joins[spec[0]], spec[1], spec[2], leg_h, sin(ph + spec[3]) * amp, spec[4])
	ci.draw_set_transform_matrix(base * Transform2D(rock, Vector2(0.0, top_left.y + bs.y * 0.8)))
	ci.draw_texture_rect(body, Rect2(Vector2(top_left.x, -bs.y * 0.8), bs), false, col)
	for spec in [["hind_near", near, m["leg_near"], PI, col], ["front_near", near, m["leg_near"], 0.0, col]]:
		_ant_leg(ci, base, top_left, bs, joins[spec[0]], spec[1], spec[2], leg_h, sin(ph + spec[3]) * amp, spec[4])
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _ant_leg(ci: CanvasItem, base: Transform2D, top_left: Vector2, bs: Vector2, join: Array, tex: Texture, lm: Dictionary, leg_h: float, ang: float, col: Color) -> void:
	var sz = Vector2(float(lm["w"]), float(lm["h"])) * (leg_h / float(lm["h"]))
	var piv = Vector2(float(lm["pivot"][0]) * sz.x, float(lm["pivot"][1]) * sz.y)
	var at = top_left + Vector2(float(join[0]) * bs.x, float(join[1]) * bs.y)
	ci.draw_set_transform_matrix(base * Transform2D(ang, at))
	ci.draw_texture_rect(tex, Rect2(-piv, sz), false, col)
