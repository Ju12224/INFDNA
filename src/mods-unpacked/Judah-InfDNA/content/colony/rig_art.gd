extends Reference
# A creature built from the owner's drawn pieces (art_manifest.json): a body, two sets of legs (a darker far set behind, a lighter near set in front),
# a jaw or fangs that hinge, and a pulsing glow. Each piece is drawn where the manifest says and swung about its hinge, so one set of pictures walks, bites
# and breathes without any frame-by-frame art. Used by the spider and the Void Maw (and the critters of critter_manifest.json: a "wings" list beats
# wings about their root, an optional "wave_strip" narrows the strips of a "wave" body).
#   draw(ci, name, feet, scale, facing, t, moving, mouth, tint, flash)   ->  false when the art is not there (the caller draws the procedural creature)
# `mouth` 0..1 is how open the jaw is; `feet` is the world point it stands on; `scale` multiplies the manifest's game size.

const Lib = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")


static func available(name: String) -> bool:
	return Lib.get_lib().has_creature(name)


# Height of the picture in world px at this scale (for the health bar above it).
static func height_px(name: String, scale: float) -> float:
	var e = Lib.get_lib().creature(name)
	return float(e.get("height", 100.0)) * float(e.get("scale", 0.2)) * scale


static func _put(ci: CanvasItem, base: Transform2D, tex, pos: Vector2, pivot: Vector2, ang: float, mod: Color) -> void:
	var m = base
	if ang != 0.0:
		var tp = Transform2D(Vector2(1, 0), Vector2(0, 1), pivot)
		m = base * tp * Transform2D(ang, Vector2.ZERO) * tp.affine_inverse()
	ci.draw_set_transform_matrix(m)
	ci.draw_texture(tex, pos, mod)


static func draw(ci: CanvasItem, name: String, feet: Vector2, scale: float, facing: int, t: float, moving: bool, mouth: float, tint: Color, flash: bool) -> bool:
	var lib = Lib.get_lib()
	var e = lib.creature(name)
	if e.empty():
		return false
	var btex = lib.tex(str(e["body"]["file"]))
	if btex == null:
		return false
	var s = float(e["scale"]) * scale
	var fv = Vector2(float(e["feet"][0]), float(e["feet"][1]))
	var base = Transform2D(Vector2(facing * s, 0), Vector2(0, s), feet)
	var mod = tint
	if flash:
		mod = Color(min(1.0, tint.r + 0.35), tint.g * 0.55, tint.b * 0.55, tint.a)
	var gait = 6.0 if moving else 1.6
	var amp = 0.13 if moving else 0.025
	# a flyer (an entry with "wings": [{file, x, y, pivot, layer, flap, speed, phase}]): its legs hang and sway slowly with the body, its wings beat
	var fly = e.has("wings")
	if fly:
		gait = 2.2
		amp = 0.1
	var bob = sin(t * gait * 2.0) * (3.0 if moving else 1.2)
	var ci_t = ci
	for layer in e["order"]:
		if layer == "body":
			_body(ci, lib, e, base, fv, btex, t, moving, mouth, mod, bob)
		else:
			# many legs a side (a centipede, the Void Maw): they move in a wave that runs from tail to head, not all at once
			var n_side := 0
			for p in e["parts"]:
				if p["layer"] == layer:
					n_side += 1
			var wave = n_side > 5
			var cw = max(1.0, float(e["canvas"][0]))
			for p in e["parts"]:
				if p["layer"] != layer:
					continue
				var tx = lib.tex(str(p["file"]))
				if tx == null:
					continue
				var ph = float(p["phase"]) * PI + (0.0 if layer == "near" else 0.7)
				if wave:
					ph = -float(p["pivot"][0]) / cw * TAU * 1.5 + (0.0 if layer == "near" else PI)
				var sw = sin(t * gait + ph)
				var lift = max(0.0, cos(t * gait + ph)) * (9.0 if moving else 0.0) * (0.6 if wave else 1.0)
				if fly:
					lift = -bob
				var pos = Vector2(float(p["x"]), float(p["y"])) - fv + Vector2(0, -lift)
				var pv = Vector2(float(p["pivot"][0]), float(p["pivot"][1])) - fv + (Vector2(0, -lift) if fly else Vector2.ZERO)
				_put(ci, base, tx, pos, pv, sw * amp * (0.7 if wave else 1.0), mod)
			if fly:
				for w in e["wings"]:
					if str(w.get("layer", "near")) != layer:
						continue
					var wt = lib.tex(str(w["file"]))
					if wt == null:
						continue
					var wa = sin(t * float(w.get("speed", 40.0)) + float(w.get("phase", 0.0))) * float(w.get("flap", 0.4))
					var wo = Vector2(0, bob)
					_put(ci, base, wt, Vector2(float(w["x"]), float(w["y"])) - fv + wo, Vector2(float(w["pivot"][0]), float(w["pivot"][1])) - fv + wo, wa, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


static func _body(ci: CanvasItem, lib, e: Dictionary, base: Transform2D, fv: Vector2, btex, t: float, moving: bool, mouth: float, mod: Color, bob: float) -> void:
	var b = e["body"]
	var bpos = Vector2(float(b["x"]), float(b["y"])) - fv + Vector2(0, bob)
	if e.has("cavity"):
		var ctex = lib.tex(str(e["cavity"]["file"]))
		if ctex != null:
			_put(ci, base, ctex, Vector2(float(e["cavity"]["x"]), float(e["cavity"]["y"])) - fv + Vector2(0, bob), Vector2.ZERO, 0.0, mod)
	if bool(e.get("wave", false)):
		# a rippling crawl: the body is drawn in strips that rise and fall in a wave running from the tail to the head, quiet at the head
		var sz = btex.get_size()
		var sw = float(e.get("wave_strip", 34.0))
		ci.draw_set_transform_matrix(base)
		var x = 0.0
		while x < sz.x:
			var u = x / sz.x
			var dy = sin(t * (3.2 if moving else 1.2) - u * 8.0) * (11.0 if moving else 4.0) * (1.0 - clamp((u - 0.45) / 0.45, 0.0, 1.0))
			ci.draw_texture_rect_region(btex, Rect2(bpos.x + x, bpos.y + dy, min(sw + 1.0, sz.x - x), sz.y), Rect2(x, 0, min(sw + 1.0, sz.x - x), sz.y), mod)
			x += sw
	else:
		_put(ci, base, btex, bpos, Vector2.ZERO, 0.0, mod)
	if e.has("jaws"):
		for j in e["jaws"]:
			var jt = lib.tex(str(j["file"]))
			if jt == null:
				continue
			var jp = Vector2(float(j["pivot"][0]), float(j["pivot"][1])) - fv + Vector2(0, bob)
			_put(ci, base, jt, Vector2(float(j["x"]), float(j["y"])) - fv + Vector2(0, bob), jp, float(j["open"]) * mouth, mod)
	if e.has("glow"):
		var gt = lib.tex(str(e["glow"]["file"]))
		if gt != null:
			var pulse = 0.45 + 0.4 * sin(t * 2.6)
			var gp = Vector2(float(e["glow"]["x"]), float(e["glow"]["y"])) - fv + Vector2(0, bob)
			_put(ci, base, gt, gp, Vector2.ZERO, 0.0, Color(1, 1, 1, mod.a * pulse))


# ---------------------------------------------------------------- the bird
# Five drawn pieces (head, near wing with the shoulder, far wing, two feet) put together and flapped about the shoulder. `fold` 0..1 tucks the wings
# and throws the talons forward for a stoop. Origin = where the neck meets the shoulders; faces +x; about 300 px across at scale 1.
const BIRD_K = 0.5


static func bird_available() -> bool:
	var m = Lib.get_lib().manifest()
	return m.has("bird") and Lib.get_lib().tex("bird_head.png") != null and Lib.get_lib().tex("bird_wing_b.png") != null


static func bird(ci: CanvasItem, pos: Vector2, scale: float, t: float, facing: int, fold: float, alpha: float, hurt: bool = false) -> bool:
	var lib = Lib.get_lib()
	var th = lib.tex("bird_head.png")
	var twb = lib.tex("bird_wing_b.png")
	var twa = lib.tex("bird_wing_a.png")
	var tc1 = lib.tex("bird_claw_1.png")
	var tc2 = lib.tex("bird_claw_2.png")
	if th == null or twb == null or twa == null or tc1 == null or tc2 == null:
		return false
	var s = BIRD_K * scale
	var base = Transform2D(Vector2(facing * s, 0), Vector2(0, s), pos)
	var mod = Color(1, 1, 1, alpha)
	var dim = Color(0.72, 0.72, 0.8, alpha)
	if hurt:
		mod = Color(1, 0.6, 0.6, alpha)
	var flap = 0.5 + 0.5 * sin(t * 9.0)
	var ang_b = lerp(-0.95 * flap, 0.55, fold)
	var ang_a = lerp(-0.95 * (0.5 + 0.5 * sin(t * 9.0 - 0.7)), 0.45, fold)
	var wb = twb.get_size()
	var wa = twa.get_size()
	var org = Vector2(wb.x * 0.88, wb.y * 0.6)                     # the origin, in the near wing's own pixels
	var hinge_b = Vector2(wb.x * 0.72, wb.y * 0.62) - org
	var hinge_a_src = Vector2(wa.x * 0.8, wa.y * 0.75)
	var pos_b = -org
	var pos_a = hinge_b + Vector2(-8, -10) - hinge_a_src
	var bob = sin(t * 9.0) * 5.0
	var up = Vector2(0, -bob)
	# the far foot, the far wing, the shoulder and near wing, the head, the near foot
	var c2 = Vector2(-150, -10)
	_put(ci, base, tc2, c2 + Vector2(0, bob * 0.3), c2 + Vector2(tc2.get_size().x * 0.4, 0), -0.6 * fold, dim)
	_put(ci, base, twa, pos_a + up, hinge_b + Vector2(-8, -10) + up, ang_a, dim)
	_put(ci, base, twb, pos_b + up, hinge_b + up, ang_b, mod)
	ci.draw_set_transform_matrix(base * Transform2D(Vector2(0.9, 0), Vector2(0, 0.9), Vector2(-36, -157) + up))
	ci.draw_texture(th, Vector2.ZERO, mod)
	var c1 = Vector2(-105, -30)
	_put(ci, base, tc1, c1 + Vector2(0, bob * 0.3 + 8.0 * fold), c1 + Vector2(tc1.get_size().x * 0.4, 0), -0.6 * fold, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true
