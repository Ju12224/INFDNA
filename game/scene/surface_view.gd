extends Node2D
# The meadow on top of the soil, in the 2.5D band (band.gd): the owner's three grass strips as rows at the back, middle and front of
# the band, and the world's landmarks standing between them, all drawn back to front by lane. Landmarks come from
# core/world_features.gd (pure: the same seed always gives the same meadow): trees (the owner's tree pictures, art_manifest "trees",
# in their spring, summer and autumn looks) and boulders (art_manifest "rocks"). Cliffs have no picture yet, so they are left out.
# Every row and landmark follows the ground's height, smoothed so it does not climb the grid's cell steps.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WF = preload("res://core/world_features.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const C = WorldGrid.CELL
# grass rows: [strip, lane, height in world px at the front, brightness, share of its height sunk below its lane's ground line]
# (the front row reaches well down behind the soil's top edge, so no sky shows through where the ground dips)
const ROWS = [["back", 0.04, 100.0, 0.74, 0.08], ["mid", 0.5, 92.0, 0.88, 0.1], ["front", 1.0, 84.0, 1.0, 0.45]]
const RIBBON_STEP = 12.0       # world px between the points of a grass row's outline
const SMOOTH = 2               # columns either side averaged into the ground height
const MARGIN = 500.0           # world px past the screen edges that are still drawn (trees are wide)
# which tree picture a tree landmark gets, by a hash of its seed: [upper bound, name, height share of the landmark's height]
const TREE_PICK = [[0.30, "oak1", 0.88], [0.58, "oak2", 0.88], [0.68, "mossoak", 0.55], [0.76, "acacia", 0.4], [0.82, "grove", 0.5],
	[0.93, "spruce", 0.95], [0.97, "stump", 0.38], [1.0, "log", 0.16]]
const AUTUMN_LOOKS = ["orange", "red", "gold"]
const HAZE = Color(0.88, 0.92, 0.97)   # things at the back of the band are a little cooler and paler

var colony
var _trees := {}               # tree name -> its manifest entry
var _rocks := []
var _rows := []                # [texture, ROWS entry]


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var man = Art.manifest("art_manifest.json")
	for t in man.get("trees", []):
		_trees[t["name"]] = t
	_rocks = man.get("rocks", [])
	var grass = Art.manifest("grass/grass_manifest.json").get("strips", {})
	for r in ROWS:
		if grass.has(r[0]):
			_rows.append([Art.tex(grass[r[0]]["file"]), r])


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var sim = colony.sim
	var view = colony.view_rect(MARGIN)
	var x0 = int(floor(view.position.x / C))
	var x1 = int(ceil(view.end.x / C))
	var items := []            # [lane, kind, data]
	for r in _rows:
		items.append([r[1][1], "row", r])
	for f in WF.in_range(sim.seed_base, x0, x1, int(colony.grid.entrance.x)):
		if f["x"] < x0 or f["x"] > x1:
			continue
		if f["kind"] == "tree" or f["kind"] == "boulder":
			items.append([float(f["lane"]), f["kind"], f])
	items.sort_custom(func(a, b): return a[0] < b[0])
	for it in items:
		match it[1]:
			"row":
				_draw_row(it[2], view)
			"tree":
				_draw_tree(it[2])
			"boulder":
				_draw_rock(it[2])


# The ground's top at world x (px), smoothed over a few columns: the spoil mound counts, dug holes do not.
func ground_y(px: float) -> float:
	var g = colony.grid
	var cx = px / C - 0.5
	var c0 = int(floor(cx))
	var f = cx - c0
	var a := 0.0
	var b := 0.0
	for d in range(-SMOOTH, SMOOTH + 1):
		a += min(g.surf_y(c0 + d), g.base_y(c0 + d))          # a hole (the nest's mouth) does not pull the meadow down; a mound lifts it
		b += min(g.surf_y(c0 + 1 + d), g.base_y(c0 + 1 + d))
	return lerp(a, b, f) / (2 * SMOOTH + 1) * C


func _lane_tint(lane: float, bright: float = 1.0) -> Color:
	var c = HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0)) * bright
	c.a = 1.0
	return c * colony.day.tint


# A grass row: the strip laid along the ground at its lane, repeating, as one textured ribbon.
func _draw_row(r: Array, view: Rect2) -> void:
	var tex: Texture2D = r[0]
	var e = r[1]
	var lane: float = e[1]
	var h = e[2] * Band.persp(lane)
	var w = tex.get_width() * h / tex.get_height()
	var top := PackedVector2Array()
	var bottom := PackedVector2Array()
	var uv_top := PackedVector2Array()
	var uv_bottom := PackedVector2Array()
	var x = floor(view.position.x / RIBBON_STEP) * RIBBON_STEP
	while x <= view.end.x + RIBBON_STEP:
		var by = Band.lane_y(ground_y(x), lane) + e[4] * h       # the strip's solid foot sinks into the ground
		var u = x / w
		top.append(Vector2(x, by - h))
		bottom.append(Vector2(x, by))
		uv_top.append(Vector2(u, 0.0))
		uv_bottom.append(Vector2(u, 1.0))
		x += RIBBON_STEP
	var col = _lane_tint(lane, e[3])
	for i in top.size() - 1:
		draw_polygon(PackedVector2Array([top[i], top[i + 1], bottom[i + 1], bottom[i]]), PackedColorArray([col, col, col, col]),
			PackedVector2Array([uv_top[i], uv_top[i + 1], uv_bottom[i + 1], uv_bottom[i]]), tex)


func _draw_tree(f: Dictionary) -> void:
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
	var col = _lane_tint(lane) * Color(0.94 + 0.12 * _h(sd + 5.0), 0.94 + 0.12 * _h(sd + 6.0), 0.94 + 0.12 * _h(sd + 7.0))
	_draw_flipped(tex, Rect2(pos, size), flip, col)


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


func _draw_rock(f: Dictionary) -> void:
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
	var base = Vector2(px, Band.lane_y(ground_y(px), lane))
	_draw_flipped(tex, Rect2(base - Vector2(size.x * 0.5, size.y * 0.94), size), _h(sd + 3.0) > 0.5, _lane_tint(lane))


func _draw_flipped(tex: Texture2D, rect: Rect2, flip: bool, col: Color) -> void:
	if flip:
		draw_set_transform(Vector2(rect.position.x * 2.0 + rect.size.x, 0.0), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, rect, false, col)
		draw_set_transform(Vector2.ZERO)
	else:
		draw_texture_rect(tex, rect, false, col)


static func _h(a: float) -> float:
	return fmod(abs(sin(a * 12.9898) * 43758.5453), 1.0)
