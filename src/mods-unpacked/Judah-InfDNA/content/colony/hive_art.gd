extends Reference
# A beehive on a meadow tree (colony_sim.hives, core/hives.gd; the owner's pictures in content/art/hive): it hangs from the lower edge of
# the canopy, swings a little on its branch and sways with the tree; whole, dripping, then torn open as the ants take its honey; once it
# has fallen it lies broken at the foot of the tree until a new one grows. By day, in good weather, a few bees circle it.
# Drawn by ground_view.gd right after its tree, so it shares the tree's depth slice.

const AL = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const Hives = preload("res://mods-unpacked/Judah-InfDNA/core/hives.gd")
const HANGING = ["hive_whole", "hive_drip", "hive_damaged"]
const BEES = 3


static func draw(ci: CanvasItem, fe: Dictionary, sim, day, t: float, sway: float) -> void:
	var h = sim.hives.get(fe.get("fid"))
	if h == null:
		return
	var spr: Dictionary = fe["spr"]
	var lib = AL.get_lib()
	var st = Hives.stage(h)
	var sd = float(h["seed"])
	var sz: Vector2 = spr["size"]
	var pos: Vector2 = spr["pos"]
	var hang: Vector2
	if spr.has("leaves"):
		var box: Rect2 = spr["leaves"]["box"]
		hang = Vector2(box.position.x + box.size.x * (0.3 + 0.4 * Hives.hash1(sd + 5.1)), box.end.y - box.size.y * 0.18)
	else:
		hang = pos + Vector2(sz.x * (0.38 + 0.24 * Hives.hash1(sd + 5.1)), sz.y * 0.5)
	var hh = clamp(sz.y * 0.09, 50.0, 130.0)     # bigger than an ant, small against a giant tree
	var by: float = fe["by"]
	var mod: Color = spr.get("mod", Color.white)
	var base = Transform2D(Vector2(1, 0), Vector2(sway, 1), Vector2(-sway * by, 0))
	if st < 3:
		var tex = lib.tex("hive/%s.png" % HANGING[st])
		if tex == null:
			return
		var w = hh * tex.get_width() / float(tex.get_height())
		var swing = sin(t * 1.3 + sd) * 0.035
		ci.draw_set_transform_matrix(base * Transform2D(swing, hang))
		ci.draw_texture_rect(tex, Rect2(Vector2(-w * 0.5, -hh * 0.12), Vector2(w, hh)), false, mod)
		var busy = day == null or (day.leaf > 0.3 and day.night < 0.5 and sim.rain < 0.5)
		if busy:
			_bees(ci, lib, base, hang + Vector2(0.0, hh * 0.45), w, hh, sd, t, mod)
	else:
		var tf = lib.tex("hive/hive_fallen.png")
		if tf == null:
			return
		var fw = hh * 1.5
		var fh = fw * tf.get_height() / float(tf.get_width())
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		ci.draw_texture_rect(tf, Rect2(Vector2(hang.x - fw * 0.5, by - fh * 0.82), Vector2(fw, fh)), false, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# A few bees circling the hive on loops of their own, facing the way they fly, wings a-blur (a quick bob).
static func _bees(ci: CanvasItem, lib, base: Transform2D, c: Vector2, w: float, hh: float, sd: float, t: float, mod: Color) -> void:
	var s = hh / 70.0 * 0.32
	for k in BEES:
		var tex = lib.tex("hive/bee_%d.png" % int(Hives.hash1(sd + k * 3.7) * 7.99))
		if tex == null:
			continue
		var sp = 1.5 + 0.35 * k
		var a = t * sp + k * 2.1 + sd
		var p = c + Vector2(cos(a) * w * (0.75 + 0.2 * k), sin(a * 1.3) * hh * 0.4 + sin(t * 31.0 + k) * 1.2)
		var fl = 1.0 if -sin(a) >= 0.0 else -1.0
		var bw = tex.get_width() * s
		var bh = tex.get_height() * s
		ci.draw_set_transform_matrix(base * Transform2D(Vector2(-fl, 0.0), Vector2(0.0, 1.0), p))
		ci.draw_texture_rect(tex, Rect2(Vector2(-bw * 0.5, -bh * 0.5), Vector2(bw, bh)), false, mod)
