extends SceneTree
# Contact sheet: every part form (rows = families), plus a stacked worst case.
# Large cells at bake scale with the 170x136 sprite frame outlined; a strip of the
# same ants at in-game size (~40 px) underneath.
const G = preload("res://mods-unpacked/Judah-InfDNA/core/genome.gd")
const P = preload("res://mods-unpacked/Judah-InfDNA/core/body_painter.gd")
const SIZE = Vector2(170, 136)
const FEET = Vector2(85, 126)
const CELL = Vector2(300, 250)

func _ant(col: String):
	var g = G.make_ant(); g.color = Color(col); return g

func _rows() -> Array:
	var rows = []
	var cols = {"sonic": "#c9a13b", "electric": "#2f5f7a", "shell": "#8a4b2e", "silk": "#6b5a8e", "tongue": "#3d6b3a", "regen": "#a8322d"}
	var r = []
	for ln in ["sonic", "electric", "shell"]:
		for t in range(1, 4):
			var g = _ant(cols[ln]); g.organs[ln] = t
			r.append([g, "%s %d: %s" % [ln, t, G.ORGANS[ln][t]]])
		if r.size() >= 6:
			rows.append(r); r = []
	if not r.empty(): rows.append(r)
	r = []
	for ln in ["silk", "tongue", "regen"]:
		for t in range(1, 4):
			var g = _ant(cols[ln]); g.organs[ln] = t
			r.append([g, "%s %d: %s" % [ln, t, G.ORGANS[ln][t]]])
		if r.size() >= 6:
			rows.append(r); r = []
	if not r.empty(): rows.append(r)
	r = []
	for fid in G.FUSIONS.keys():
		var fd = G.FUSIONS[fid]
		var g = _ant("#7a3d6b"); g.organs[fd["a"]] = 3; g.organs[fd["b"]] = 3
		r.append([g, "FUSION " + fd["name"]])
	var w = G.make_queen()
	for q in 2: w.segments.insert(1, {"r": 46.0, "limb": "leg", "n": 4, "len": 90.0, "armor": 3, "spikes": 5})
	w.segments[0]["r"] = 46.0; w.head()["r"] = 46.0; w.head()["antenna"] = 50.0; w.head()["eyes"] = 5
	for k in ["wings", "stinger", "acid", "glow"]: w.morph[k] = 1
	w.morph["major"] = 1.0; w.morph["replete"] = 1.0; w.morph["hair"] = 1.0
	w.forms = {"spike": 3, "acid": 3, "leg": 4, "antenna": 3, "sting": 2}
	for ln in G.ORGANS.keys(): w.organs[ln] = 3
	r.append([w, "worst case (5 seg, all)"])
	var w2 = _ant("#c9a13b"); w2.segments[1]["len"] = 90.0; w2.head()["antenna"] = 50.0; w2.head()["r"] = 40.0; w2.morph["major"] = 1.0
	w2.morph["stinger"] = 1; w2.forms = {"sting": 2, "leg": 4, "antenna": 3}
	for ln in G.ORGANS.keys(): w2.organs[ln] = 3
	r.append([w2, "worst case (tall, all)"])
	rows.append(r)
	return rows

func _init():
	var rows = _rows()
	var vp = Viewport.new(); vp.size = Vector2(CELL.x * 6 + 20, CELL.y * rows.size() + 260); vp.usage = Viewport.USAGE_2D
	vp.render_target_v_flip = true; vp.render_target_update_mode = Viewport.UPDATE_ONCE
	get_root().add_child(vp)
	var bg = ColorRect.new(); bg.rect_size = vp.size; bg.color = Color("#5f8a3f"); vp.add_child(bg)
	var dirt = ColorRect.new(); dirt.rect_position = Vector2(0, CELL.y * rows.size() + 10); dirt.rect_size = Vector2(vp.size.x, 250); dirt.color = Color("#3a2a1f"); vp.add_child(dirt)
	var font = DynamicFont.new(); var fd = DynamicFontData.new(); fd.font_path = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"; font.font_data = fd; font.size = 15
	var m = 1.6
	var small_i = 0
	for ri in rows.size():
		for ci in rows[ri].size():
			var o = Vector2(10 + ci * CELL.x, 8 + ri * CELL.y)
			var fr = ReferenceRect.new(); fr.rect_position = o; fr.rect_size = SIZE * m; fr.border_color = Color(1, 1, 1, 0.35); fr.editor_only = false; vp.add_child(fr)
			var p = P.new(); p.genome = rows[ri][ci][0]; p.paint_scale = 0.55 * m; p.gait = 0.25
			p.position = o + FEET * m; vp.add_child(p)
			var l = Label.new(); l.text = rows[ri][ci][1]; l.rect_position = o + Vector2(4, SIZE.y * m + 2); l.add_font_override("font", font); vp.add_child(l)
			# in-game size: texture scale 0.24 of the logical sprite
			var p2 = P.new(); p2.genome = rows[ri][ci][0]; p2.paint_scale = 0.55 * 0.24; p2.gait = 0.25
			p2.position = Vector2(30 + (small_i % 26) * 70, CELL.y * rows.size() + 90 + int(small_i / 26) * 70); vp.add_child(p2)
			small_i += 1
	yield(VisualServer, "frame_post_draw")
	vp.get_texture().get_data().save_png(OS.get_environment("OUT")); print("saved"); quit()
