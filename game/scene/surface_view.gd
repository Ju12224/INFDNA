extends Node2D
# The meadow on top of the soil: ONE lane. Everything on the surface (ants, creatures, trees, rocks, hives, piles, weather decals)
# stands on the single ground line, with no depth offset, scale or haze.
#
# - Behind the ants (this node, z 10, under the soil): the landmarks of the world, trees (art_manifest "trees", in their spring, summer
#   and autumn looks) and boulders (art_manifest "rocks"), from core/world_features.gd (pure: the same seed always gives the same
#   meadow), then a short lawn (the owner's old strips, art/grass) along the ground line, then the weather's ground decals (snow,
#   puddles). Cliffs have no picture yet.
# - In front of the ants and creatures (GRASS_Z, between the creatures at 45 and the effects at 50): the owner's thick grass
#   (art/grass/grass_thick.png), one row standing along the ground line with its foot on the ground as it is (the spoil heap lifts
#   it), hiding the soil's top edge. Zoomed out it is closed, tall against the ants, and hides them. Zooming in it fades: from
#   GRASS_ZOOM_CLOSED the blades lean apart, sink and turn see-through, until at GRASS_ZOOM_OPEN they are gone and the ants walk in
#   the open. Wind sways it. Round each nest mouth the ants have trodden the grass down (a cleared patch as wide as the anthill), so
#   the mound and the ants coming out of it show at every zoom.
#
# Another view can draw ground decals under the grass with a draw_ground(canvas_item) function (called after the lawn).

const Art = preload("res://scene/art.gd")
const WF = preload("res://core/world_features.gd")
const WorldGrid = preload("res://core/world_grid.gd")
const Seasons = preload("res://core/seasons.gd")
const FoliageTint = preload("res://scene/foliage_tint.gd")

const C = WorldGrid.CELL
# --- the thick grass in front
const GRASS_Z = 47             # absolute z of the grass: above units (40) and creatures (45), below effects (50) and weather (55)
const GRASS_ZOOM_CLOSED = 1.2  # at this zoom and below the grass stands closed ...
const GRASS_ZOOM_OPEN = 3.5    # ... and at this one and above it is gone (the fade runs between them, evenly in the zoom's logarithm)
const GRASS_H = 58.0           # the row's height, world px (an ant stands about 12): the solid half of the strip is taller than an ant
const GRASS_SINK = 0.45        # fading, the blades sink to this much shorter ...
const GRASS_LEAN = 0.28        # ... and lean apart (away from the middle of the screen) by this share of their height
const GRASS_KEEP = 0.12        # the share of the grass a nest's cleared patch keeps (a trodden fringe)
const VLINE = 0.9              # share of the strip's height above the ground line: its flat foot sinks the rest into the ground
const RIM = 3.0                # world px the grass's foot reaches below the soil's top edge, at the least
const SWAY = 0.035             # wind: the tips sway this share of the row's height
const CLEAR_IN = 14.0          # cells from a mouth where the clearing is fully trodden: at least this, and this share of ...
const CLEAR_COVER = 0.9        # ... the anthill's half width (nest_view.gd draws it as wide as its heap needs) ...
const CLEAR_FADE = 14.0        # ... and the cells it takes the grass to stand full again
# --- the lawn behind the ants
const LAWN_H = 26.0            # world px, the strip's height; it stands on the ground line, its foot hidden by the soil
const LAWN_SHADE = 0.9
const V0 = 0.025               # strips are sampled between these: no wrapped texels at the top or bottom edge, at any mip level
const V1 = 0.97
const STEP_PX = 20.0           # screen px between ribbon points
const SMOOTH = 2               # columns either side averaged into the ground height
const MARGIN = 500.0           # world px past the screen edges that are still drawn (trees are wide)
const TREE_K = 0.55            # the landmarks are drawn this big next to their size in world_features.gd (the trees and rocks stood in the
const ROCK_K = 0.65            # back of the old band, at half scale: the same size as they were seen)
# which tree picture a tree landmark gets, by a hash of its seed: [upper bound, name, height share of the landmark's height]
# (creatures_view.gd and weather_view.gd read this, and TREE_K, to hang beehives on the trees and shed leaves from them)
const TREE_PICK = [[0.30, "oak1", 0.88], [0.58, "oak2", 0.88], [0.68, "mossoak", 0.55], [0.76, "acacia", 0.4], [0.82, "grove", 0.5],
	[0.93, "spruce", 0.95], [0.97, "stump", 0.38], [1.0, "log", 0.16]]
const AUTUMN_LOOKS = ["orange", "red", "gold"]

var colony
var _trees := {}               # tree name -> its manifest entry
var _rocks := []
var _strips := {}              # "back" / "mid" / "front" / "thick" -> texture
var _scenery: Node2D           # trees, rocks, the lawn and the decals (z 10)
var _grass: Node2D             # the thick grass in front (z GRASS_Z)
var _t := 0.0
var _open := 0.0               # 0 the grass stands closed .. 1 it is gone (this frame)
var _gcache := {}              # column -> ground (cells), smoothed, this frame
var _mouths := []              # this frame's nest mouths: [x px, fully trodden within px, grown again by px]
var _feats := []               # the landmarks near the view, back to front (rebuilt when the view has moved on)
var _feat_key := ""


func _ready() -> void:
	var man = Art.manifest("art_manifest.json")
	for t in man.get("trees", []):
		_trees[t["name"]] = t
	_rocks = man.get("rocks", [])
	var grass = Art.manifest("grass/grass_manifest.json").get("strips", {})
	for k in grass:
		_strips[k] = Art.tex(grass[k]["file"])
	if _strips.get("thick") == null:
		_strips["thick"] = _strips.get("front")
	_scenery = _item(self, _draw_scenery)
	_grass = _item(self, _draw_grass)
	_grass.z_as_relative = false
	_grass.z_index = GRASS_Z


# A canvas item under `parent` drawing with `cb`, mipmapped filtering (the strips are drawn far smaller than they are).
func _item(parent: Node, cb: Callable) -> Node2D:
	var it := Node2D.new()
	it.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	it.draw.connect(cb.bind(it))
	parent.add_child(it)
	return it


func _process(delta: float) -> void:
	_t += delta
	_gcache.clear()
	_open = grass_open()
	_mouths.clear()
	var g = colony.grid
	var nest = colony.views.get("nest")
	var mound_ws = nest.get("_mound_ws") if nest != null else null
	for i in g.entrances.size():
		var r_in = CLEAR_IN
		if mound_ws != null and i < mound_ws.size():
			r_in = maxf(r_in, CLEAR_COVER * 0.5 * float(mound_ws[i]) / C)          # the anthill (it grows with the heap) stands in the clearing
		_mouths.append([(float(g.entrances[i].x) + 0.5) * C, r_in * C, (r_in + CLEAR_FADE) * C])
	_scenery.queue_redraw()
	_grass.visible = _open < 0.996
	if _grass.visible:
		_grass.queue_redraw()


# How far the grass has faded away at the current zoom: 0 closed (GRASS_ZOOM_CLOSED and below) .. 1 gone (GRASS_ZOOM_OPEN and above),
# eased at both ends, even in the logarithm of the zoom (every doubling takes as much).
func grass_open() -> float:
	var t = clampf(log(colony.zoom() / GRASS_ZOOM_CLOSED) / log(GRASS_ZOOM_OPEN / GRASS_ZOOM_CLOSED), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# The ground's top at world x (px), smoothed over a few columns: the spoil mound counts, dug holes do not.
func ground_y(px: float, smooth: int = SMOOTH) -> float:
	var cx = px / C - 0.5
	var c0 = int(floor(cx))
	if smooth != SMOOTH:
		return lerp(_col(c0, smooth), _col(c0 + 1, smooth), cx - c0) * C
	if not _gcache.has(c0):
		_gcache[c0] = _col(c0, SMOOTH)
	if not _gcache.has(c0 + 1):
		_gcache[c0 + 1] = _col(c0 + 1, SMOOTH)
	return lerp(_gcache[c0], _gcache[c0 + 1], cx - c0) * C


func _col(c: int, smooth: int) -> float:
	var g = colony.grid
	var a := 0.0
	for d in range(-smooth, smooth + 1):
		a += min(g.surf_y(c + d), g.base_y(c + d))          # a hole (the nest's mouth) does not pull the meadow down; a mound lifts it
	return a / (2 * smooth + 1)


# 1 in the trodden clearing round a nest mouth, 0 where the grass stands full.
func _clearing(px: float) -> float:
	var c := 0.0
	for m in _mouths:
		c = maxf(c, 1.0 - smoothstep(m[1], m[2], absf(px - m[0])))
	return c


func _step() -> float:
	return max(6.0, STEP_PX / colony.zoom())


# ---- behind the ants -------------------------------------------------------------------------------------------------------------

# The landmarks of the world near the view, back to front by the lane the world gave each (only their order: they all stand on the ground
# line). Rebuilt when the view has moved a little, not every frame.
func _landmarks(x0: int, x1: int) -> Array:
	var key = "%d %d %d" % [x0 >> 5, x1 >> 5, colony.sim.seed_base]
	if key != _feat_key:
		_feat_key = key
		_feats.clear()
		for f in WF.in_range(colony.sim.seed_base, (x0 >> 5) * 32 - 32, (x1 >> 5) * 32 + 64, int(colony.grid.entrance.x)):
			if f["kind"] == "tree" or f["kind"] == "boulder":
				_feats.append(f)
		_feats.sort_custom(func(a, b): return a["lane"] > b["lane"])
	return _feats


func _draw_scenery(it: Node2D) -> void:
	var view = colony.view_rect(MARGIN)
	var x0 = int(floor(view.position.x / C))
	var x1 = int(ceil(view.end.x / C))
	for f in _landmarks(x0, x1):
		if f["x"] < x0 or f["x"] > x1:
			continue
		if f["kind"] == "tree":
			_draw_tree(it, f)
		else:
			_draw_rock(it.get_canvas_item(), f)
	_draw_lawn(it)
	var w = colony.views.get("weather")
	if w != null and w.has_method("draw_ground"):
		w.draw_ground(it)                       # lying snow, puddles and the snow on the crowns, on the lawn
	for v in colony.views.values():
		if v != self and v != w and v.has_method("draw_ground"):
			v.draw_ground(it)
	it.draw_set_transform(Vector2.ZERO)


# The short lawn: one row of the owner's strip on the ground line (its foot sunk into the soil, which is drawn over it).
func _draw_lawn(it: Node2D) -> void:
	var tex: Texture2D = _strips.get("front")
	if tex == null:
		return
	var h = LAWN_H
	var w = tex.get_width() * h / tex.get_height()
	var view = colony.view_rect(0.0)
	var step = _step()
	var xt := PackedFloat32Array()
	var yt := PackedFloat32Array()
	var yb := PackedFloat32Array()
	var us := PackedFloat32Array()
	var vt := PackedFloat32Array()
	var vb := PackedFloat32Array()
	var x = floor((view.position.x - step) / step) * step
	while x <= view.end.x + step:
		var line = ground_y(x)
		xt.append(x)
		yt.append(line - VLINE * h)
		yb.append(line + (1.0 - VLINE) * h)
		us.append(x / w)
		vt.append(V0)
		vb.append(V1)
		x += step
	var col = colony.day.tint * LAWN_SHADE
	col.a = 1.0
	_ribbon(it.get_canvas_item(), tex, xt, yt, xt, yb, us, vt, vb, col)


# ---- in front of the ants --------------------------------------------------------------------------------------------------------

# The thick grass: one row standing on the ground line. How much of it shows is 1 - _open (see grass_open): fading it leans the blades
# apart, sinks them and makes them see-through together, so nothing pops. Over the clearing round a nest mouth it is trodden down to a
# fringe (the whole strip squashed shorter, blades whole).
func _draw_grass(it: Node2D) -> void:
	var tex: Texture2D = _strips.get("thick")
	if tex == null:
		return
	var open = _open
	var a = 1.0 - smoothstep(0.0, 1.0, open)
	if a <= 0.004:
		return
	var h = GRASS_H * (1.0 - GRASS_SINK * open)
	var w = tex.get_width() * GRASS_H / tex.get_height()          # (the blades keep their width as the row sinks: it only gets shorter)
	var view = colony.view_rect(0.0)
	var cx = colony.cam_center().x
	var half = maxf(1.0, view.size.x * 0.5)
	var step = _step()
	var xt := PackedFloat32Array()
	var xb := PackedFloat32Array()
	var yt := PackedFloat32Array()
	var yb := PackedFloat32Array()
	var us := PackedFloat32Array()
	var vt := PackedFloat32Array()
	var vb := PackedFloat32Array()
	var x = floor((view.position.x - step) / step) * step
	while x <= view.end.x + step:
		var line = ground_y(x)
		var hs = 1.0 - (1.0 - GRASS_KEEP) * _clearing(x)           # trodden down: the strip's height here
		var hh = h * hs
		var rel = clampf((x - cx) / half, -1.3, 1.3)
		var sway = SWAY * hh * (0.6 * sin(_t * 1.1 + x * 0.013) + 0.4 * sin(_t * 2.3 - x * 0.029 + 1.0))
		xt.append(x + GRASS_LEAN * open * rel * hh + sway)
		xb.append(x)                                                  # the foot stays where it stands; the tips lean
		yt.append(line - VLINE * hh)
		yb.append(line + maxf(RIM, (1.0 - VLINE) * hh))
		us.append(x / w)
		vt.append(V0)
		vb.append(V1)
		x += step
	var col = colony.day.tint
	col.a = a
	_ribbon(it.get_canvas_item(), tex, xt, yt, xb, yb, us, vt, vb, col)


# A strip of grass as one draw on any canvas item (it needs no texture repeat): quads between consecutive points, top (xt, yt) at vt
# and bottom (xb, yb) at vb, u along the row, split wherever u passes a whole number.
func _ribbon(rid: RID, tex: Texture2D, xt: PackedFloat32Array, yt: PackedFloat32Array, xb: PackedFloat32Array, yb: PackedFloat32Array,
		us: PackedFloat32Array, vt: PackedFloat32Array, vb: PackedFloat32Array, col: Color) -> void:
	var m = us.size()
	if m < 2 or tex == null:
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in m - 1:
		var ua = us[i]
		var ub = us[i + 1]
		var k = floor(ua)
		var cut = (k + 1.0 - ua) / (ub - ua) if floor(ub) > k and ub > ua else -1.0
		var spans = [[0.0, 1.0, k]] if cut < 0.0 else [[0.0, cut, k], [cut, 1.0, k + 1.0]]
		for sp in spans:
			var b = pts.size()
			for f in [sp[0], sp[1]]:
				var u = clamp(lerp(ua, ub, f) - sp[2], 0.0, 1.0)
				pts.append(Vector2(lerp(xt[i], xt[i + 1], f), lerp(yt[i], yt[i + 1], f)))
				pts.append(Vector2(lerp(xb[i], xb[i + 1], f), lerp(yb[i], yb[i + 1], f)))
				uvs.append(Vector2(u, lerp(vt[i], vt[i + 1], f)))
				uvs.append(Vector2(u, lerp(vb[i], vb[i + 1], f)))
			idx.append_array([b, b + 2, b + 3, b, b + 3, b + 1])
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(rid, idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


# A tree, where creatures_view.gd's _tree_rect() expects it (same pick, size and foot).
func _draw_tree(it: Node2D, f: Dictionary) -> void:
	var sd: float = f["seed"]
	var pick = TREE_PICK[TREE_PICK.size() - 1]
	var r = _h(sd + 99.0)
	for p in TREE_PICK:
		if r < p[0]:
			pick = p
			break
	var def = _trees.get(pick[1])
	if def == null:
		return
	var looks = _looks(def, sd)           # [[picture, weight]]: one picture, or two while the leaves change colour
	var tex = Art.tex(looks[0][0])
	if tex == null:
		return
	var size: Vector2
	if pick[1] == "log":
		size = Vector2(f["w"] * TREE_K * 5.5, f["w"] * TREE_K * 5.5 * tex.get_height() / tex.get_width())
	else:
		var hgt = f["h"] * TREE_K * pick[2]
		size = Vector2(hgt * tex.get_width() / tex.get_height(), hgt)
	var px = (f["x"] + 0.5) * C
	var base = Vector2(px, ground_y(px))
	var foot = def.get("foot", [0.5, 1.0])
	var flip = _h(sd + 3.0) > 0.5
	var pos = base - Vector2((1.0 - foot[0] if flip else foot[0]) * size.x, foot[1] * size.y)
	var col = colony.day.tint * Color(0.94 + 0.12 * _h(sd + 5.0), 0.94 + 0.12 * _h(sd + 6.0), 0.94 + 0.12 * _h(sd + 7.0))
	if pick[1] == "spruce":
		col *= FoliageTint.evergreen(Seasons.phase(colony.sim.time))      # an evergreen: only darker and bluer in winter
	if flip:
		it.draw_set_transform(Vector2(pos.x * 2.0 + size.x, 0.0), 0.0, Vector2(-1, 1))
	var a_sum := 0.0
	for lk in looks:
		var t2 = Art.tex(lk[0])
		if t2 == null:
			continue
		a_sum += lk[1]
		var c2 = col
		c2.a *= lk[1] / a_sum              # painted over each other: the sum of the weights is the picture's own opacity
		it.draw_texture_rect(t2, Rect2(pos, size), false, c2)
	it.draw_set_transform(Vector2.ZERO)


# The tree's pictures for the time of year, [[file, weight]] with the weights adding up to 1: its spring, summer or autumn look (the
# autumn one in orange, red or gold, chosen per tree), cross-faded while the year moves from one to the next (foliage_tint.gd has the
# calendar). Winter keeps the autumn look until the bare winter trees arrive (roadmap step 2.3). A tree with no looks of its own (the
# spruce, a stump, a log) has its one picture.
func _looks(def: Dictionary, sd: float) -> Array:
	var looks = def.get("looks", {})
	var summer = str(looks.get("summer", def.get("file", "")))
	if not looks.has("orange"):
		return [[summer, 1.0]]
	var k = FoliageTint.weights(Seasons.phase(colony.sim.time))
	var autumn = str(looks.get(AUTUMN_LOOKS[int(_h(sd + 55.0) * 2.99)], summer))
	var out := []
	for e in [[str(looks.get("spring", summer)), k[0]], [summer, k[1]], [autumn, k[2] + k[3]]]:
		if e[1] <= 0.004:
			continue
		if not out.is_empty() and out[out.size() - 1][0] == e[0]:
			out[out.size() - 1][1] += e[1]
		else:
			out.append(e)
	if out.is_empty():
		return [[summer, 1.0]]
	var sum := 0.0
	for e in out:
		sum += e[1]
	for e in out:
		e[1] /= sum
	return out


# A boulder, onto any canvas item.
func _draw_rock(rid: RID, f: Dictionary) -> void:
	if _rocks.is_empty():
		return
	var sd: float = f["seed"]
	var w: float = f["w"]
	var choices = [0, 1, 2] if w > 120.0 else ([2, 3, 4] if w > 70.0 else [4, 5, 6])
	var def = _rocks[min(choices[int(_h(sd + 7.0) * 2.99)], _rocks.size() - 1)]
	var tex = Art.tex(def["file"])
	if tex == null:
		return
	var width = w * ROCK_K
	var size = Vector2(width, width * tex.get_height() / tex.get_width())
	var px = (f["x"] + 0.5) * C + (_h(sd + 11.0) - 0.5) * 30.0          # (a little variety along the line: they have no depth to spread in)
	var base = Vector2(px, ground_y(px))
	var rect = Rect2(base - Vector2(size.x * 0.5, size.y * 0.94), size)
	var col = colony.day.tint
	if _h(sd + 3.0) > 0.5:
		RenderingServer.canvas_item_add_set_transform(rid, Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(rect.position.x * 2.0 + rect.size.x, 0.0)))
	RenderingServer.canvas_item_add_texture_rect(rid, rect, tex.get_rid(), false, col)
	RenderingServer.canvas_item_add_set_transform(rid, Transform2D.IDENTITY)


static func _h(a: float) -> float:
	return fmod(abs(sin(a * 12.9898) * 43758.5453), 1.0)
