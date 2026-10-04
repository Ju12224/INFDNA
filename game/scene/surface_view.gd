extends Node2D
# The meadow on top of the soil, in the 2.5D band (band.gd): Band.LANES lanes, drawn back to front. Each lane is a row of the owner's
# grass (the back strip on the last lane, the middle strip down to lane 6, the front strip in front of that) laid along the ground,
# and the world's landmarks standing in it: trees (the owner's tree pictures, art_manifest "trees", in their spring, summer and autumn
# looks) and boulders (art_manifest "rocks"), from core/world_features.gd (pure: the same seed always gives the same meadow). Cliffs
# have no picture yet, so they are left out.
#
# In front of everything (z COVER_Z, above the ants and creatures) stands the cover row: the owner's front strip on the camera's cut
# (Band.cover_n()). Zoomed out it is simply the front row on the soil's top line. Zoomed in, the camera has moved into the band: the
# lanes in front of the cut are not drawn, the cover row grows, darkens and blurs a little, and more rows of it fill the screen below
# it, so the dropped lanes and the soil face vanish behind grass close to the camera.
#
# One canvas shader on the lanes does the distance haze (toward the horizon colour of the hour, Band.fog) and the depth of field
# (a mip bias, Band.blur). Another view can draw into a lane, between its row and the next one in front, with a
# draw_lane(canvas_item, lane_number) function: it is called for every lane that is drawn, back to front.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WF = preload("res://core/world_features.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const C = WorldGrid.CELL
const COVER_Z = 55             # absolute z of the cover row: above units (40), creatures (45) and effects (50)
const ROW_K = 27.5             # a row is ROW_K * scale^2 high (about 1.9 lane spacings): blades show 0.8 of a spacing above its line
const ROW_SINK = 0.58          # share of a row's height below its lane's line: its solid foot fills down to the row in front
const V0 = 0.025               # rows sample the strip between these: no wrapped texels at the top or bottom edge, at any mip level
const V1 = 0.97
const COVER_GROW = 0.8         # the cover row grows by this much as the cut moves COVER_SPAN lanes into the band ...
const COVER_SPAN = 6.0
const COVER_DARK = 0.22        # ... darkens by this much, and blurs by up to COVER_BLUR (mip bias)
const COVER_BLUR = 0.6
const FILL_FROM = 1.5          # cut (lane number) where the rows below the cover row start to fill the screen down to its bottom ...
const FILL_TO = 3.0            # ... and where they reach it
const COVER_SMOOTH = 1         # the cover row follows the soil's top closely (columns either side averaged), as the front row did
const HOLE_REACH = 14.0        # the cover row reaches at most this far down into a hole (the nest's mouth)
const STEP_PX = 20.0           # screen px between ribbon points
const SMOOTH = 2               # columns either side averaged into the ground height
const FAR_FROM = 7.0           # lanes from here back to FAR_TO ease from the ground as dug onto the original ground, smoothed wide,
const FAR_TO = 11.0            # so the spoil mound is not drawn out into a ridge running into the distance
const FAR_SMOOTH = 12
const MARGIN = 500.0           # world px past the screen edges that are still drawn (trees are wide)
# which tree picture a tree landmark gets, by a hash of its seed: [upper bound, name, height share of the landmark's height]
# (creatures_view.gd reads this to hang beehives on the trees)
const TREE_PICK = [[0.30, "oak1", 0.88], [0.58, "oak2", 0.88], [0.68, "mossoak", 0.55], [0.76, "acacia", 0.4], [0.82, "grove", 0.5],
	[0.93, "spruce", 0.95], [0.97, "stump", 0.38], [1.0, "log", 0.16]]
const AUTUMN_LOOKS = ["orange", "red", "gold"]
const FOG_SKY = Color(0.73, 0.86, 0.95)   # haze colour when there is no sky view

const SHADER = """
shader_type canvas_item;
uniform float blur = 0.0;     // mip bias: depth of field
uniform float fog = 0.0;      // share of the horizon colour
uniform vec4 fog_col : source_color = vec4(0.73, 0.86, 0.95, 1.0);
varying vec4 vcol;
void vertex() { vcol = COLOR; }
void fragment() {
	vec4 c = texture(TEXTURE, UV, blur) * vcol;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, fog_col.rgb * vcol.rgb, clamp(fog * (1.25 - 0.5 * lum), 0.0, 1.0));   // the dark ink lifts the most
	COLOR = c;
}
"""

var colony
var _trees := {}               # tree name -> its manifest entry
var _rocks := []
var _strips := {}              # "back" / "mid" / "front" -> texture
var _shader := Shader.new()
var _lanes := []               # index n (1..LANES) -> {"root", "row", "items", "mat"}
var _cover: Node2D
var _cover_mat: ShaderMaterial
var _feats := []               # this frame's landmarks: [lane number, kind, feature]
var _gcache := {}              # column -> ground (cells), smoothed, this frame
var _fcache := {}              # column -> original ground (cells), smoothed wide, this frame


func _ready() -> void:
	_shader.code = SHADER
	var man = Art.manifest("art_manifest.json")
	for t in man.get("trees", []):
		_trees[t["name"]] = t
	_rocks = man.get("rocks", [])
	var grass = Art.manifest("grass/grass_manifest.json").get("strips", {})
	for k in grass:
		_strips[k] = Art.tex(grass[k]["file"])
	_lanes.append(null)
	for n in range(Band.LANES, 0, -1):          # back to front: later children draw on top
		_lanes.append(null)
	for n in range(Band.LANES, 0, -1):
		_lanes[n] = _make_lane(n)
	_cover_mat = _material()
	_cover = _item(self, true, _draw_cover)
	_cover.z_as_relative = false
	_cover.z_index = COVER_Z
	_cover.material = _cover_mat


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


# A canvas item under `parent` drawing with `cb`: mipmapped filtering, and repeat only where a row's strip has to repeat.
func _item(parent: Node, repeat: bool, cb: Callable) -> Node2D:
	var it := Node2D.new()
	it.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	it.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED if repeat else CanvasItem.TEXTURE_REPEAT_DISABLED
	it.use_parent_material = true
	it.draw.connect(cb.bind(it))
	parent.add_child(it)
	return it


func _make_lane(n: int) -> Dictionary:
	var root := Node2D.new()
	root.material = _material()
	add_child(root)
	return {"root": root, "mat": root.material, "row": _item(root, true, _draw_row.bind(n)), "items": _item(root, false, _draw_items.bind(n))}


func _process(_delta: float) -> void:
	_gcache.clear()
	_fcache.clear()
	var view = colony.view_rect(MARGIN)
	var x0 = int(floor(view.position.x / C))
	var x1 = int(ceil(view.end.x / C))
	_feats.clear()
	for f in WF.in_range(colony.sim.seed_base, x0, x1, int(colony.grid.entrance.x)):
		if f["x"] < x0 or f["x"] > x1 or not (f["kind"] == "tree" or f["kind"] == "boulder"):
			continue
		if Band.lane_alpha(float(f["lane"]), f["kind"] == "tree") > 0.004:
			_feats.append([Band.num(float(f["lane"])), f["kind"], f])
	var fogc = colony.views["sky"].horizon_colour() if colony.views.has("sky") and colony.views["sky"].has_method("horizon_colour") else FOG_SKY
	var cover = Band.cover_n()
	for n in range(1, Band.LANES + 1):
		var l: Dictionary = _lanes[n]
		var on = n + 1.0 > cover               # anything in this lane can still be behind the cut
		l.root.visible = on
		if on:
			var lane = Band.lane_of(n)
			l.mat.set_shader_parameter("fog", Band.fog(lane))
			l.mat.set_shader_parameter("blur", Band.blur(lane))
			l.mat.set_shader_parameter("fog_col", fogc)
			l.row.queue_redraw()
			l.items.queue_redraw()
	_cover_mat.set_shader_parameter("blur", COVER_BLUR * _cover_k())
	_cover.queue_redraw()


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


# The ground a grass row in lane number n stands on: the front lanes on the ground as it is (the mound on the lip), the back lanes on
# the original ground smoothed wide.
func lane_ground(px: float, n: float) -> float:
	var t = smoothstep(FAR_FROM, FAR_TO, n)
	if t <= 0.0:
		return ground_y(px)
	var cx = px / C - 0.5
	var c0 = int(floor(cx))
	return lerp(ground_y(px), lerp(_far(c0), _far(c0 + 1), cx - c0) * C, t)


func _far(c: int) -> float:
	if not _fcache.has(c):
		var g = colony.grid
		var a := 0.0
		for d in range(-FAR_SMOOTH, FAR_SMOOTH + 1, 3):
			a += g.base_y(c + d)
		_fcache[c] = a / (2 * FAR_SMOOTH / 3 + 1)
	return _fcache[c]


# The soil's top as dug at world x (px): where the cover row has to reach down to, so no sky shows between them.
func _lip(px: float) -> float:
	var g = colony.grid
	var cx = px / C - 0.5
	var c0 = int(floor(cx))
	return lerp(float(g.surf_y(c0)), float(g.surf_y(c0 + 1)), cx - c0) * C


func _strip_for(n: int) -> Texture2D:
	var k = "back" if n >= Band.LANES else ("mid" if n >= 6 else "front")
	return _strips.get(k, _strips.get("front"))


func _draw_row(it: Node2D, n: int) -> void:
	if float(n) <= Band.cover_n():
		return                                  # the cover row stands here or in front of it
	var lane = Band.lane_of(n)
	var p = Band.persp(lane)
	var h = ROW_K * p * p
	var col = colony.day.tint
	col.a = 1.0
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var tex = _strip_for(n)
	if tex == null:
		return
	var w = tex.get_width() * h / tex.get_height()
	var step = max(6.0, STEP_PX / colony.zoom())
	var view = colony.view_rect(0.0)
	var x = floor((view.position.x - step) / step) * step
	var u0 = n * 0.37
	while x <= view.end.x + step:
		var line = Band.lane_y(lane_ground(x, n), lane)
		pts.append(Vector2(x, line - (1.0 - ROW_SINK) * h))
		pts.append(Vector2(x, line + ROW_SINK * h))
		uvs.append(Vector2(x / w + u0, V0))
		uvs.append(Vector2(x / w + u0, V1))
		x += step
	_strip(it, tex, pts, uvs, col)


# Landmarks standing in lane number n (in front of its row, behind the next one), then whatever other views draw there.
func _draw_items(it: Node2D, n: int) -> void:
	for f in _feats:
		if ceili(f[0] - 0.0001) != n:
			continue
		if f[1] == "tree":
			_draw_tree(it, f[2])
		else:
			_draw_rock(it, f[2])
	for v in colony.views.values():
		if v != self and v.has_method("draw_lane"):
			v.draw_lane(it, n)
	it.draw_set_transform(Vector2.ZERO)


# How far the camera has moved into the band, 0..1, by where the cut is.
func _cover_k() -> float:
	return clamp((Band.cover_n() - 1.0) / COVER_SPAN, 0.0, 1.0)


# The cover row on the cut; below it, more rows of the same strip, nearer, bigger and darker, down to the bottom of the screen once
# the cut is FILL_TO lanes in (before that only down to the soil's top line, so no sky shows where the cut lanes were).
func _draw_cover(it: Node2D) -> void:
	var tex: Texture2D = _strips.get("front")
	if tex == null:
		return
	var n = Band.cover_n()
	var lane = Band.lane_of(n)
	var p = Band.persp(lane)
	var k = _cover_k()
	var h = ROW_K * p * p * (1.0 + COVER_GROW * k)
	var fill = smoothstep(FILL_FROM, FILL_TO, n)
	var view = colony.view_rect(0.0)
	var step = max(6.0, STEP_PX / colony.zoom())
	var x0 = floor((view.position.x - step) / step) * step
	var w = tex.get_width() * h / tex.get_height()
	var lines := PackedFloat32Array()
	var bottoms := PackedFloat32Array()
	var x = x0
	while x <= view.end.x + step:
		var gy = ground_y(x, COVER_SMOOTH)
		lines.append(Band.lane_y(gy, lane))
		var lip = min(_lip(x), gy + HOLE_REACH) + 2.0
		bottoms.append(lerp(lip, view.end.y + 8.0, fill))
		x += step
	# the cover row, then rows nearer the camera than it (lower, in front of it), while any of them shows above the bottom
	var rows := [[0.0, h, 1.0, 0.11]]
	var gap = 0.5 * h
	var y = 0.0
	for i in range(1, 5):
		y += gap * (1.0 + 0.25 * i)
		var any := false
		for j in lines.size():
			if lines[j] + y - (1.0 - ROW_SINK) * h * (1.0 + 0.2 * i) < bottoms[j]:
				any = true
				break
		if not any:
			break
		rows.append([y, h * (1.0 + 0.2 * i), 1.0 - 0.1 * i, i * 0.29])
	for r in rows:
		var hh: float = r[1]
		var col = colony.day.tint * (1.0 - COVER_DARK * k) * r[2]
		col.a = 1.0
		var ww = tex.get_width() * hh / tex.get_height()
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		var bot := PackedVector2Array()
		var buv := PackedVector2Array()
		for j in lines.size():
			var xx = x0 + j * step
			var line = lines[j] + r[0]
			var b = bottoms[j]
			var foot = min(line + ROW_SINK * hh, b)
			var u = xx / ww + r[3]
			pts.append(Vector2(xx, min(line - (1.0 - ROW_SINK) * hh, foot)))
			pts.append(Vector2(xx, foot))
			uvs.append(Vector2(u, V0))
			uvs.append(Vector2(u, lerp(V0, V1, clamp((foot - (line - (1.0 - ROW_SINK) * hh)) / hh, 0.0, 1.0))))
			# its solid foot, stretched down to the bottom where the row ends above it
			bot.append(Vector2(xx, foot))
			bot.append(Vector2(xx, max(b, foot)))
			buv.append(Vector2(u, 0.72))
			buv.append(Vector2(u, V1))
		_strip(it, tex, bot, buv, col)
		_strip(it, tex, pts, uvs, col)


# A triangle strip through pairs of points (top, bottom, top, bottom, ...) as one draw.
func _strip(it: CanvasItem, tex: Texture2D, pts: PackedVector2Array, uvs: PackedVector2Array, col: Color) -> void:
	var m = pts.size() / 2
	if m < 2:
		return
	var idx := PackedInt32Array()
	for i in m - 1:
		var b = i * 2
		idx.append_array([b, b + 2, b + 3, b, b + 3, b + 1])
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(col)
	RenderingServer.canvas_item_add_triangle_array(it.get_canvas_item(), idx, pts, cols, uvs, PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


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
	var tex = Art.tex(_look(def, sd))
	if tex == null:
		return
	var lane: float = f["lane"]
	var sc = Band.persp(lane)
	var size: Vector2
	if pick[1] == "log":
		size = Vector2(f["w"] * sc * 5.5, f["w"] * sc * 5.5 * tex.get_height() / tex.get_width())
	else:
		var hgt = f["h"] * sc * pick[2]
		size = Vector2(hgt * tex.get_width() / tex.get_height(), hgt)
	var px = (f["x"] + 0.5) * C
	var base = Vector2(px, Band.lane_y(ground_y(px), lane))
	var foot = def.get("foot", [0.5, 1.0])
	var flip = _h(sd + 3.0) > 0.5
	var pos = base - Vector2((1.0 - foot[0] if flip else foot[0]) * size.x, foot[1] * size.y)
	var col = colony.day.tint * Color(0.94 + 0.12 * _h(sd + 5.0), 0.94 + 0.12 * _h(sd + 6.0), 0.94 + 0.12 * _h(sd + 7.0))
	col.a = Band.lane_alpha(lane, true)
	_draw_flipped(it, tex, Rect2(pos, size), flip, col)


# The tree's look for the time of year: spring and summer as drawn, autumn in one of three colours (chosen per tree). Winter keeps the
# autumn look until the bare winter trees arrive (roadmap step 2.3).
func _look(def: Dictionary, sd: float) -> String:
	var looks = def.get("looks", {})
	var day = colony.day
	var name = "summer"
	if day.season == 0:
		name = "spring"
	elif day.season == 3 or (day.season == 2 and day.autumn > 0.5):
		name = AUTUMN_LOOKS[int(_h(sd + 55.0) * 2.99)]
	return str(looks.get(name, looks.get("summer", def.get("file", ""))))


func _draw_rock(it: Node2D, f: Dictionary) -> void:
	if _rocks.is_empty():
		return
	var sd: float = f["seed"]
	var w: float = f["w"]
	var choices = [0, 1, 2] if w > 120.0 else ([2, 3, 4] if w > 70.0 else [4, 5, 6])
	var def = _rocks[min(choices[int(_h(sd + 7.0) * 2.99)], _rocks.size() - 1)]
	var tex = Art.tex(def["file"])
	if tex == null:
		return
	var lane: float = f["lane"]
	var width = w * Band.persp(lane)
	var size = Vector2(width, width * tex.get_height() / tex.get_width())
	var px = (f["x"] + 0.5) * C
	var base = Vector2(px, Band.lane_y(lane_ground(px, Band.num(lane)), lane))
	var col = colony.day.tint
	col.a = Band.lane_alpha(lane)
	_draw_flipped(it, tex, Rect2(base - Vector2(size.x * 0.5, size.y * 0.94), size), _h(sd + 3.0) > 0.5, col)


func _draw_flipped(it: Node2D, tex: Texture2D, rect: Rect2, flip: bool, col: Color) -> void:
	if flip:
		it.draw_set_transform(Vector2(rect.position.x * 2.0 + rect.size.x, 0.0), 0.0, Vector2(-1, 1))
		it.draw_texture_rect(tex, rect, false, col)
		it.draw_set_transform(Vector2.ZERO)
	else:
		it.draw_texture_rect(tex, rect, false, col)


static func _h(a: float) -> float:
	return fmod(abs(sin(a * 12.9898) * 43758.5453), 1.0)
