extends Node2D
# The meadow on top of the soil, in the 2.5D band (band.gd).
#
# - The lawn: Band.LANES lanes, drawn back to front under the soil (z 10), each a short row of the owner's grass (the back strip on the
#   last lane, the middle strip down to lane 6, the front strip in front of that) on the ground, so the meadow floor is grass wherever it
#   shows. The world's landmarks stand in the lanes: trees (art_manifest "trees", in their spring, summer and autumn looks) and boulders
#   (art_manifest "rocks"), from core/world_features.gd (pure: the same seed always gives the same meadow). Cliffs have no picture yet.
# - The thick grass (the owner's "super thick grass", art/grass/grass_thick.png): curtain rows of tall dense blades standing across the
#   band at Band.CURTAINS, each with its flat foot on its own lane's ground. Zoomed out they are closed and hide much of what walks behind
#   them; zooming in parts them (Band.curtain_alpha: they lean apart, bow, slide toward the camera and fade, the farthest in front of the
#   focus first). The back curtain stands behind every tree, in its lane; the middle and front ones have to stand between the ants, so
#   units_view.gd calls rows_hook (pass_rows here) between its lane buckets and they are drawn into its canvas there, with the boulders
#   in front of the middle curtain (without that hook they are drawn just under the ants).
# - The cover row, in front of everything (z COVER_Z): the thick grass on the camera's cut (Band.cover_n()), its foot over the soil's top
#   edge. Zoomed out it is the fringe on the soil's top line. Zoomed in, the camera has moved into the band: the lanes in front of the cut
#   are not drawn, the cover row grows, darkens and blurs a little, and more rows of it fill the screen below, so the dropped lanes and
#   the soil face vanish behind grass close to the camera.
#
# One canvas shader on the lanes and the cover does the distance haze (toward the horizon colour of the hour, Band.fog) and the depth
# of field (a mip bias, Band.blur). Another view can draw into a lane, between its row and the next one in front, with a
# draw_lane(canvas_item, lane_number) function: it is called for every lane that is drawn, back to front.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WF = preload("res://core/world_features.gd")
const WorldGrid = preload("res://core/world_grid.gd")
const Seasons = preload("res://core/seasons.gd")
const FoliageTint = preload("res://scene/foliage_tint.gd")

const C = WorldGrid.CELL
const COVER_Z = 55             # absolute z of the cover row: above units (40), creatures (45) and effects (50)
const CURTAIN_Z = 39           # absolute z of the middle and front curtains when units_view has no rows_hook: just under the ants
const ROW_K = 27.5             # a lawn row is ROW_K * scale^2 high (about 1.9 lane spacings): blades show 0.8 of a spacing above its line
const ROW_SINK = 0.58          # share of a lawn row's height below its lane's line: its solid foot fills down to the row in front
const V0 = 0.025               # strips are sampled between these: no wrapped texels at the top or bottom edge, at any mip level
const V1 = 0.97
const VLINE = 0.9              # share of a thick grass row's height above its lane's line: its flat foot sinks the rest into the ground
const CURTAIN_H = [36.0, 58.0, 51.0]   # height of each curtain's strip at scale 1, world px (an ant stands about 12): the blades reach up
									   # to about the next curtain's foot, so zoomed out the meadow is closed grass
const CURTAIN_SHADE = [0.86, 0.93, 1.0]
const SWAY = 0.035             # wind: the tips of a curtain sway this share of its height
const TRAMPLE = [0.0, 0.85, 0.7]       # round a nest mouth the ants have trodden the grass down: curtain heights lose this share there ...
const TRAMPLE_COVER = 0.5              # ... and the cover row's
const CLEAR_IN = 14.0          # cells from a mouth where the clearing is fully trodden (an anthill is 15 to 40 cells wide) ...
const CLEAR_OUT = 28.0         # ... and where the grass stands full again
const COVER_H = 26.0           # the cover row's height at scale 1 on the soil's top line (the fringe) ...
const COVER_FRAC = 0.14        # ... and, once the camera has dollied in, the share of the screen's height it stands (a narrow strip along the bottom)
const COVER_DARK = 0.15        # ... darkened by this much, and blurred by up to COVER_BLUR (mip bias), the further in
const COVER_BLUR = 0.5
const RIM = 3.0                # world px the cover row's foot reaches below the soil's top edge, hiding it
const MOUTH_RIM = 9.0          # ... and this much more round a nest mouth, over the anthill's base
const FILL_FROM = 1.0          # cut (lane number) where the cover row starts to move from the soil's top line to the bottom of the screen ...
const FILL_TO = 2.0            # ... and where it is there
const SKIRT_LANES = 1.5        # while the camera is in the band, the first lanes behind the cut's fade keep their foot stretched down to the cover strip
const COVER_SMOOTH = 1         # the cover row follows the soil's top closely (columns either side averaged)
const HOLE_REACH = 14.0        # grass reaches at most this far down into a hole (the nest's mouth)
const STEP_PX = 20.0           # screen px between ribbon points
const SMOOTH = 2               # columns either side averaged into the ground height
const FAR_FROM = 1.0           # lanes from here back to FAR_TO ease from the ground as dug onto the original ground, smoothed wide: the spoil
const FAR_TO = 2.0             # heap stands in the front plane, and the meadow behind it is not drawn climbing it (an arch over the mouth)
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
var _strips := {}              # "back" / "mid" / "front" / "thick" -> texture
var _shader := Shader.new()
var _lanes := []               # index n (1..LANES) -> {"root", "row", "items", "mat"}
var _cover: Node2D
var _cover_mat: ShaderMaterial
var _curtains: Node2D          # draws the middle and front curtains when units_view has no rows_hook
var _hooked := false
var _feats := []               # this frame's landmarks in the lanes, back to front: [lane number, kind, feature]
var _passed := []              # this frame's things units_view's lane loop draws, back to front: [lane, kind, data]
var _pass_i := 0
var _t := 0.0
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
	if _strips.get("thick") == null:
		_strips["thick"] = _strips.get("front")
	_lanes.resize(Band.LANES + 1)
	for n in range(Band.LANES, 0, -1):          # back to front: later children draw on top
		_lanes[n] = _make_lane(n)
	_curtains = _item(self, false, _draw_curtains)
	_curtains.z_as_relative = false
	_curtains.z_index = CURTAIN_Z
	_cover_mat = _material()
	_cover = _item(self, true, _draw_cover)
	_cover.z_as_relative = false
	_cover.z_index = COVER_Z
	_cover.material = _cover_mat


func _material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader
	return m


# A canvas item under `parent` drawing with `cb`: mipmapped filtering, and repeat only where a lawn row's strip has to repeat.
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


func _process(delta: float) -> void:
	_t += delta
	_gcache.clear()
	_fcache.clear()
	var units = colony.views.get("units")
	_hooked = units != null and "rows_hook" in units
	if _hooked and not (units.rows_hook is Callable and units.rows_hook.is_valid()):
		units.rows_hook = pass_rows
	# landmarks, and what goes into units_view's lane loop instead of the lanes: the middle and front curtains, and the boulders in
	# front of the middle one (both would otherwise stand in front of the ants behind them)
	var view = colony.view_rect(MARGIN)
	var x0 = int(floor(view.position.x / C))
	var x1 = int(ceil(view.end.x / C))
	_feats = [[Band.num(Band.CURTAINS[0]), "curtain", 0]]
	_passed = [[Band.CURTAINS[1], "curtain", 1], [Band.CURTAINS[2], "curtain", 2]]
	for f in WF.in_range(colony.sim.seed_base, x0, x1, int(colony.grid.entrance.x)):
		if f["x"] < x0 or f["x"] > x1 or not (f["kind"] == "tree" or f["kind"] == "boulder"):
			continue
		var lane = float(f["lane"])
		if Band.lane_alpha(lane, f["kind"] == "tree") <= 0.004:
			continue
		if f["kind"] == "boulder" and lane > Band.CURTAINS[1]:
			_passed.append([lane, "boulder", f])
		else:
			_feats.append([Band.num(lane), f["kind"], f])
	_feats.sort_custom(func(a, b): return a[0] > b[0])
	_passed.sort_custom(func(a, b): return a[0] < b[0])
	_pass_i = 0
	var fogc = colony.views["sky"].horizon_colour() if colony.views.has("sky") and colony.views["sky"].has_method("horizon_colour") else FOG_SKY
	var cover = Band.cover_n()
	for n in range(1, Band.LANES + 1):
		var l: Dictionary = _lanes[n]
		var on = n + 1.0 > cover or (n == 1 and cover < FILL_TO)      # anything in this lane can still be behind the cut
		l.root.visible = on
		if on:
			var lane = Band.lane_of(n)
			l.mat.set_shader_parameter("fog", Band.fog(lane))
			l.mat.set_shader_parameter("blur", Band.blur(lane))
			l.mat.set_shader_parameter("fog_col", fogc)
			l.row.queue_redraw()
			l.items.queue_redraw()
	_curtains.visible = not _hooked
	if not _hooked:
		_curtains.queue_redraw()
	_cover_mat.set_shader_parameter("blur", COVER_BLUR * _cover_k())
	_cover.queue_redraw()


# units_view.gd's rows_hook: called from its _draw before each lane bucket (lanes >= t are still to come) and once more at the end. Draws
# into its canvas the curtains and boulders standing behind lane t that are not drawn yet, so the ants in front of them are drawn over
# them and the ones behind are hidden by them.
func pass_rows(cv: CanvasItem, t: float) -> void:
	if _pass_i >= _passed.size() or _passed[_pass_i][0] > t + 0.0001:
		return
	var rid = cv.get_canvas_item()
	RenderingServer.canvas_item_add_set_transform(rid, Transform2D.IDENTITY)
	while _pass_i < _passed.size() and _passed[_pass_i][0] <= t + 0.0001:
		var p = _passed[_pass_i]
		_pass_i += 1
		if p[1] == "curtain":
			_draw_curtain(rid, p[2], false)
		else:
			_draw_rock(rid, p[2])
	RenderingServer.canvas_item_add_set_transform(rid, Transform2D.IDENTITY)


func _draw_curtains(it: Node2D) -> void:
	_pass_i = 0
	pass_rows(it, 99.0)


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


# The ground a row in lane number n stands on: the front lanes on the ground as it is (the mound on the lip), the back lanes on the
# original ground smoothed wide.
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


# 1 in the trodden clearing round a nest mouth, 0 where the grass stands full.
func _clearing(px: float) -> float:
	var c := 0.0
	for en in colony.grid.entrances:
		c = max(c, 1.0 - smoothstep(CLEAR_IN, CLEAR_OUT, abs(px / C - 0.5 - float(en.x))))
	return c


# The soil's top as dug at world x (px).
func _lip(px: float) -> float:
	var g = colony.grid
	var cx = px / C - 0.5
	var c0 = int(floor(cx))
	return lerp(float(g.surf_y(c0)), float(g.surf_y(c0 + 1)), cx - c0) * C


func _strip_for(n: int) -> Texture2D:
	var k = "back" if n >= Band.LANES else ("mid" if n >= 6 else "front")
	return _strips.get(k, _strips.get("front"))


func _step() -> float:
	return max(6.0, STEP_PX / colony.zoom())


# A lawn row, fading in over the lanes behind the camera's cut. While the camera is in the band the first opaque lanes behind the cut
# carry on downward with copies of their own row, a few steps in front of it, to the cover strip, so no sky shows under the front-most
# one however the ground lies (stretching the foot instead drew vertical streaks).
func _draw_row(it: Node2D, n: int) -> void:
	var c = Band.cover_n()
	if n == 1 and c < FILL_TO:
		_cover_rows(it, true)                   # the cover row's own foot, carried on under the soil (see _draw_cover)
		return
	var lane = Band.lane_of(n)
	var a = Band.lane_alpha(lane)
	if a <= 0.004:
		return                                  # the cover row stands here or in front of it
	var tex = _strip_for(n)
	if tex == null:
		return
	var p = Band.persp(lane)
	var h = ROW_K * p * p
	var col = colony.day.tint
	col.a = a
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var w = tex.get_width() * h / tex.get_height()
	var step = _step()
	var view = colony.view_rect(0.0)
	var x = floor((view.position.x - step) / step) * step
	var u0 = n * 0.37
	var gap = 0.0
	var want = view.end.y - 0.4 * COVER_FRAC * view.size.y
	var skirt = c > 1.001 and n >= c + Band.FADE - 0.001 and n < c + Band.FADE + SKIRT_LANES
	while x <= view.end.x + step:
		var line = Band.lane_y(lane_ground(x, n), lane)
		pts.append(Vector2(x, line - (1.0 - ROW_SINK) * h))
		pts.append(Vector2(x, line + ROW_SINK * h))
		uvs.append(Vector2(x / w + u0, V0))
		uvs.append(Vector2(x / w + u0, V1))
		gap = max(gap, want - (line + ROW_SINK * h))
		x += step
	_strip(it, tex, pts, uvs, col)
	if skirt and gap > 0.0:
		var dy = 0.55 * h
		for k in range(1, min(8, int(ceil(gap / dy))) + 1):
			var cp := pts.duplicate()
			var cu := uvs.duplicate()
			for q in cp.size():
				cp[q].y += k * dy
				cu[q].x += k * 0.173
			_strip(it, tex, cp, cu, col)


# Landmarks standing in lane number n (in front of its row, behind the next one; the back curtain among them), then whatever other
# views draw there.
func _draw_items(it: Node2D, n: int) -> void:
	for f in _feats:
		if ceili(f[0] - 0.0001) != n:
			continue
		match f[1]:
			"tree":
				_draw_tree(it, f[2])
			"boulder":
				_draw_rock(it.get_canvas_item(), f[2])
			"curtain":
				it.draw_set_transform(Vector2.ZERO)
				_draw_curtain(it.get_canvas_item(), f[2], true)
	var w = colony.views.get("weather")
	if w != null and w.has_method("draw_lane"):
		w.draw_lane(it, n)                      # ground decals (puddles, lying snow) first, under whatever stands in the lane
	for v in colony.views.values():
		if v != self and v != w and v.has_method("draw_lane"):
			v.draw_lane(it, n)
	it.draw_set_transform(Vector2.ZERO)


# Thick grass curtain i on its lane's ground, parting as Band.curtain_alpha says: leaning away from the middle of the screen, bowing,
# sliding down toward the camera and fading. lit: drawn through the lane shader (it hazes); otherwise tinted for depth here.
func _draw_curtain(rid: RID, i: int, lit: bool) -> void:
	var lane: float = Band.CURTAINS[i]
	var a = Band.curtain_alpha(lane)
	if a <= 0.004:
		return
	var pt = Band.curtain_part(lane)
	var tex: Texture2D = _strips["thick"]
	var n = Band.num(lane)
	var p = Band.persp(lane)
	var h = CURTAIN_H[i] * p
	var w = tex.get_width() * h / tex.get_height()
	var view = colony.view_rect(0.0)
	var cx = colony.cam_center().x
	var half = max(1.0, view.size.x * 0.5)
	var s = 1.0 + 0.22 * pt
	var drop = pt * 14.0 * p
	var up = VLINE * h * (1.0 - 0.45 * pt)
	var step = _step()
	var xt := PackedFloat32Array()
	var yt := PackedFloat32Array()
	var xb := PackedFloat32Array()
	var yb := PackedFloat32Array()
	var us := PackedFloat32Array()
	var vt := PackedFloat32Array()
	var vb := PackedFloat32Array()
	var x = floor((view.position.x - step) / step) * step
	while x <= view.end.x + step:
		var line = Band.lane_y(lane_ground(x, n), lane) + drop
		var bx = cx + (x - cx) * s
		var rel = clamp((x - cx) / half, -1.3, 1.3)
		var sway = SWAY * h * (0.6 * sin(_t * 1.1 + x * 0.013 + i * 1.7) + 0.4 * sin(_t * 2.3 - x * 0.029 + i))
		var sunk = TRAMPLE[i] * _clearing(x) * up           # trodden down: only its upper blades show, as drawn
		var tall = up + (1.0 - VLINE) * h
		xt.append(bx + 0.9 * rel * pt * (up - sunk) + sway)
		var top = line - up + sunk
		var nat = line + (1.0 - VLINE) * h
		var bot = clamp(_lip(x) + 2.0, top, nat)             # the spoil heap stands in front of it: grass behind shows only above its outline
		yt.append(top)
		xb.append(bx)
		yb.append(bot)
		us.append(x / w + i * 0.37)
		vt.append(lerp(V0, V1, sunk / tall))                 # trodden down: the strip's bottom part, its bushy foot, not its tips
		vb.append(V1 - (nat - bot) / tall * (V1 - V0))
		x += step
	var col = colony.day.tint * CURTAIN_SHADE[i]
	if not lit:
		col *= Color(1.0, 1.0, 1.0).lerp(Color(0.9, 0.95, 1.0), Band.fog(lane) * 3.0)
	col.a = a
	_ribbon(rid, tex, xt, yt, xb, yb, us, vt, vb, col)


# How far the camera has moved into the band, 0..1, by where the cut is: the cover row's move from the soil's top line to the screen's bottom.
func _cover_k() -> float:
	return smoothstep(FILL_FROM, FILL_TO, Band.cover_n())


func _draw_cover(it: Node2D) -> void:
	_cover_rows(it, false)


# The cover row, the thick grass in front of everything. Zoomed out it is the fringe on the soil's top line, its foot RIM below the
# edge (more round a nest mouth, over the anthill's base, and its blades trodden down there; over a hole only down to the meadow's line,
# so a nest mouth stays open for the ants climbing out). Once the camera has dollied in it is one strip of COVER_FRAC of the screen
# along the bottom, darker and a little blurred, its top edge following the ground a little; the lanes in front of the cut are behind
# it, not drawn. under: the fringe again, in the front lane under the soil, reaching down into any hole a little, so no sky shows
# there; it fades out as the cut passes lane 2.
func _cover_rows(it: Node2D, under: bool) -> void:
	var tex: Texture2D = _strips["thick"]
	if tex == null:
		return
	var n = Band.cover_n()
	var lane = Band.lane_of(n)
	var k = _cover_k()
	var fill = 0.0 if under else k
	var col = colony.day.tint * (1.0 - COVER_DARK * fill)
	col.a = 1.0 - k if under else 1.0
	if col.a <= 0.004:
		return
	var view = colony.view_rect(0.0)
	var h = lerp(COVER_H * Band.persp(lane), COVER_FRAC * view.size.y, fill)
	var step = _step()
	var ground0 = ground_y(colony.cam_center().x, COVER_SMOOTH)
	var xs := PackedFloat32Array()
	var yt := PackedFloat32Array()
	var yb := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var us := PackedFloat32Array()
	var vt := PackedFloat32Array()
	var vb := PackedFloat32Array()
	var v72 := PackedFloat32Array()
	var v1 := PackedFloat32Array()
	var ww = tex.get_width() * h / tex.get_height()
	var x = floor((view.position.x - step) / step) * step
	while x <= view.end.x + step:
		var gy = ground_y(x, COVER_SMOOTH)
		var lip = _lip(x)
		var cl = _clearing(x)
		var line_f = Band.lane_y(gy, lane)
		var line_d = view.end.y - (1.0 - VLINE) * h + clamp(0.3 * (gy - ground0), -0.05 * view.size.y, 0.05 * view.size.y)
		var line = lerp(line_f, line_d, fill)
		var b: float
		if under:
			b = max(min(lip, gy + HOLE_REACH) + 2.0, line + (1.0 - VLINE) * h)
		else:
			b = lerp(min(lip, gy) + RIM + MOUTH_RIM * cl, view.end.y + 8.0, fill)
		var nat = line + (1.0 - VLINE) * h                     # where the strip's own foot would be
		var top = line - VLINE * h * (1.0 - TRAMPLE_COVER * cl * (1.0 - fill))      # trodden down: only its bushy foot and lower blades show
		var foot = min(nat, b)
		xs.append(x)
		yt.append(min(top, foot))
		yb.append(foot)
		ys.append(max(b, foot))                                # its solid foot, stretched down to the bottom where the row ends above it
		us.append(x / ww + 0.11)
		vt.append(V1 - (nat - min(top, foot)) / h * (V1 - V0))
		vb.append(V1 - (nat - foot) / h * (V1 - V0))
		v72.append(0.72)
		v1.append(V1)
		x += step
	var rid = it.get_canvas_item()
	_ribbon(rid, tex, xs, yb, xs, ys, us, v72, v1, col)
	_ribbon(rid, tex, xs, yt, xs, yb, us, vt, vb, col)


# A lawn row: a triangle strip through pairs of points (top, bottom, top, bottom, ...) as one draw, on a canvas item that repeats.
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
	var lane: float = f["lane"]
	var sc = Band.persp(lane)
	var size: Vector2
	if pick[1] == "log":
		size = Vector2(f["w"] * sc * 5.5, f["w"] * sc * 5.5 * tex.get_height() / tex.get_width())
	else:
		var hgt = f["h"] * sc * pick[2]
		hgt *= Band.tall_scale(hgt)           # a giant is never taller than TALL_SCREEN of the screen (zoomed in, its trunk was one blurry wall)
		size = Vector2(hgt * tex.get_width() / tex.get_height(), hgt)
	var px = (f["x"] + 0.5) * C
	var base = Vector2(px, Band.lane_y(ground_y(px), lane))
	var foot = def.get("foot", [0.5, 1.0])
	var flip = _h(sd + 3.0) > 0.5
	var pos = base - Vector2((1.0 - foot[0] if flip else foot[0]) * size.x, foot[1] * size.y)
	var col = colony.day.tint * Color(0.94 + 0.12 * _h(sd + 5.0), 0.94 + 0.12 * _h(sd + 6.0), 0.94 + 0.12 * _h(sd + 7.0))
	if pick[1] == "spruce":
		col *= FoliageTint.evergreen(Seasons.phase(colony.sim.time))      # an evergreen: only darker and bluer in winter
	col.a = Band.lane_alpha(lane, true)
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


# A boulder, onto any canvas item (a lane's, or units_view's from pass_rows).
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
	var lane: float = f["lane"]
	var width = w * Band.persp(lane)
	var size = Vector2(width, width * tex.get_height() / tex.get_width())
	var px = (f["x"] + 0.5) * C
	var base = Vector2(px, Band.lane_y(lane_ground(px, Band.num(lane)), lane))
	var rect = Rect2(base - Vector2(size.x * 0.5, size.y * 0.94), size)
	var col = colony.day.tint
	col.a = Band.lane_alpha(lane)
	if _h(sd + 3.0) > 0.5:
		RenderingServer.canvas_item_add_set_transform(rid, Transform2D(Vector2(-1, 0), Vector2(0, 1), Vector2(rect.position.x * 2.0 + rect.size.x, 0.0)))
	RenderingServer.canvas_item_add_texture_rect(rid, rect, tex.get_rid(), false, col)
	RenderingServer.canvas_item_add_set_transform(rid, Transform2D.IDENTITY)


static func _h(a: float) -> float:
	return fmod(abs(sin(a * 12.9898) * 43758.5453), 1.0)
