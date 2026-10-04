extends Reference
# The creatures: every one is the owner's drawn art, rigged and animated by rig_art.gd, and the anteater (its own parts: body with head, front legs,
# hind legs, tail; tools/art/make_anteater.py) animated here. Local origin = the feet on the ground; +x is the way it faces, up is -y.

const INK = Color("#15121a")
const Rig = preload("res://mods-unpacked/Judah-InfDNA/content/colony/rig_art.gd")
const AL = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const ANT_LEN = 380.0      # the anteater nose to tail, local px at scale 1 (the size the old drawn one had)
const ANT_STEP = 0.07      # how far its legs rock each way while it walks (radians)


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


# The anteater walking, from the owner's four parts (tools/art/make_anteater.py; facing right on the sheet): the tail behind, swaying from
# its base; the haunch with the hind legs and the shoulder with the front legs, stepping in turn (each rocks about its top and swings a
# little forward and back, lifting as it comes forward); the body with the head on top, bobbing with the stride. Everything is placed in
# the sheet's own pixels and scaled so the whole animal is ANT_LEN long, its feet on the ground at `feet`.
static func _anteater(ci: CanvasItem, feet: Vector2, scale: float, facing: int, t: float, moving: bool, shade: float, alpha: float, flash: bool) -> void:
	var lib = AL.get_lib()
	var m = lib.manifest().get("anteater_art")
	if m == null or int(m.get("version", 1)) < 2:
		return
	var k = ANT_LEN / float(m["x1"] - m["x0"]) * scale
	var mid = (float(m["x0"]) + float(m["x1"])) * 0.5
	var base = Transform2D(Vector2(facing * k, 0.0), Vector2(0.0, k), feet) * Transform2D(0.0, Vector2(-mid, -float(m["ground"])))
	var col = Color(shade, shade, shade, alpha)
	if flash:
		col = Color(1.0, 0.45, 0.42, alpha)
	var ph = t * (3.0 if moving else 0.6)
	var bob = abs(sin(ph)) * -14.0 if moving else sin(t * 1.3) * 4.0
	for p in m["parts"]:
		var tex = lib.tex(str(p["file"]))
		if tex == null:
			continue
		var sz = Vector2(float(p["w"]), float(p["h"]))
		var piv = Vector2(float(p["pivot"][0]), float(p["pivot"][1])) * sz
		var at = Vector2(float(p["off"][0]), float(p["off"][1])) + piv
		var rot := 0.0
		var d := Vector2.ZERO
		match str(p["name"]):
			"tail":
				rot = sin(t * 1.4) * 0.05 + (sin(ph) * 0.03 if moving else 0.0)
				d.y = bob * 0.6
			"hind", "front":
				var lp = ph + (PI if p["name"] == "hind" else 0.0)
				if moving:
					rot = sin(lp) * ANT_STEP
					d = Vector2(sin(lp) * 18.0, bob * 0.3 - max(0.0, cos(lp)) * 10.0)
				else:
					rot = sin(t * 0.9 + (1.0 if p["name"] == "hind" else 0.0)) * 0.008
			"body":
				rot = sin(ph * 2.0) * (0.012 if moving else 0.004)
				d.y = bob
		ci.draw_set_transform_matrix(base * Transform2D(rot, at + d))
		ci.draw_texture_rect(tex, Rect2(-piv, sz), false, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
