extends Node2D
# The ants, drawn with the owner's whole-body pictures (antkit, all facing right): worker_full for foragers, worker_small_full for
# diggers, soldier_full for soldiers, alate_full for any ant with wings, and queen_full on the floor of her chamber. A forager with a
# load holds a food picture (fauna) at its jaws. The walk cycle from the part kit comes later. One _draw a frame: every ant in or near
# the view is one draw_texture under a transform, back to front: the back tunnel plane, the queen, the front plane, then the surface by lane.
#
# Placement, as the Godot 3 view (ant_view.gd) did it: the sim keeps an ant on a cell and tilts it by a.rot so its feet point at the
# ground it walks on (floor, wall or ceiling). The tilted body's down, (-sin rot, cos rot), times half a cell is the edge of that ground,
# and the picture's 'feet' point goes there. a.facing flips the picture (rot is already worked out for the flipped body). Underground
# ants stand flat in the cross-section; ants in the back plane are smaller and dimmer, and ghosted where front dirt hides them. On the
# surface every ant walks in a lane of the meadow band (band.gd): lifted, smaller and hazier toward the back, in the daylight tint.

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const C = WorldGrid.CELL
const CASTE_BODY = ["worker_full", "worker_small_full", "soldier_full"]
const CASTE_SCALE = [0.94, 1.0, 1.12]      # forager, digger, soldier (the old view's)
# Body length, nose to tail, as the old view drew it: its painter laid a body out over T = 2.2 px per unit of phenotype size + 24,
# squeezed big ones by 310 / (T + 120) and drew it at 0.55 * 0.24. An ordinary ant (size 74) came out about 24 px long underground.
const LEN_PER_SIZE = 2.2
const LEN_BASE = 24.0
const LEN_K = 0.132
const QUEEN_LEN = 55.0                     # she was drawn 2.25 times an ordinary ant
const BACK_SCALE = 0.8                     # the back tunnel plane: further away
const BACK_SHADE = 0.5
const HIDDEN_SHADE = 0.7                   # ... and where front dirt stands in front of it, darker still and see-through
const HIDDEN_ALPHA = 0.55
const HAZE = Color(0.88, 0.92, 0.97)       # the back of the meadow band, as surface_view.gd tints it
const ENTRANCE_LANE = 0.62                 # near a nest mouth ants are drawn onto its lane, at a pile onto the pile's
const PILE_LANE = 0.5
const ENTRANCE_REACH = 30.0                # cells
const PILE_REACH = 10.0
const SURF_RATE = 3.0                      # 1/s: climbing out of a mouth into the band takes about a second
const LANE_RATE = 4.0
const TURN_RATE = 9.0                      # facing per second: a turning ant squashes through its middle instead of flipping
const TURN_MIN = 0.35
const FOODS = ["crumb", "seeds", "berries"]
const FOOD_REF = 40.0                      # fauna_manifest sizes food for a worker this long
const JAW_DOWN = 0.12                      # held food sits this far below the nose, in body lengths
const HURT = Color(1.0, 0.45, 0.45)
const HURT_T = 0.12                        # a bite sets a.hurt to this
const QUEEN_HURT_T = 0.6
const FAR_ZOOM = 0.45                      # zoomed out past this, ants grow (up to FAR_MAX) so they stay more than specks
const FAR_MAX = 1.6
const MARGIN = 80.0                        # world px past the view an ant can still reach into it
const LANE_BUCKETS = 16

var colony
var _bodies := {}          # picture name -> {tex, feet, length, jaw, mid (x halfway from tail to nose)} in the picture's pixels
var _foods := []           # [{tex, size}]: size in world px for a FOOD_REF-long worker
var _state := {}           # ant id -> Vector3(surface 0..1, drawn lane, drawn facing), kept only for ants near the view
var _dt := 0.016


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var kit = Art.manifest("antkit_manifest.json").get("pieces", {})
	for name in CASTE_BODY + ["alate_full", "queen_full"]:
		var p = kit.get(name)
		var tex = Art.tex(p["file"]) if p != null else null
		if tex == null:
			continue
		var nose = Vector2(p["nose"][0], p["nose"][1])
		_bodies[name] = {"tex": _mipmapped(tex), "feet": Vector2(p["feet"][0], p["feet"][1]), "length": float(p["length"]),
			"jaw": nose + Vector2(0, JAW_DOWN * float(p["length"])), "mid": (nose.x + float(p["tail"][0])) * 0.5}
	var fauna = Art.manifest("fauna_manifest.json").get("items", {})
	for name in FOODS:
		var f = fauna.get(name)
		var tex = Art.tex(f["file"]) if f != null else null
		if tex != null:
			_foods.append({"tex": _mipmapped(tex), "size": Vector2(f["w"], f["h"]) * float(f["scale"])})


# The pictures are imported without mipmaps; an ant is drawn at a tenth of its picture's size or less, which without them sparkles.
static func _mipmapped(tex: Texture2D) -> Texture2D:
	var img = tex.get_image()
	if img == null or img.is_empty() or img.has_mipmaps():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func reset() -> void:
	_state = {}


func _process(delta: float) -> void:
	_dt = delta
	queue_redraw()


func _draw() -> void:
	var sim = colony.sim
	var g = colony.grid
	var vr = colony.view_rect(MARGIN)
	vr.size.y += Band.DEPTH * Band.LANE_K       # a surface ant is drawn up to this far above its cell
	var far = clamp(sqrt(FAR_ZOOM / colony.zoom()), 1.0, FAR_MAX)
	var ks = 1.0 - exp(-_dt * SURF_RATE)
	var kl = 1.0 - exp(-_dt * LANE_RATE)
	var piles := []
	for p in sim.piles:
		var px = (p["x"] + 0.5) * C
		if px > vr.position.x - PILE_REACH * C and px < vr.end.x + PILE_REACH * C:
			piles.append(p["x"])
	var state := {}
	var back := []
	var front := []
	var lanes := []
	for i in LANE_BUCKETS:
		lanes.append([])
	for a in sim.ants:
		var p = sim.ant_pos(a)
		if not vr.has_point(p):
			continue
		var surf = 1.0 if g.is_surface_cell(a.tx, a.ty) else 0.0
		var goal = _lane_goal(g, a, piles)
		var st: Vector3 = _state.get(a.id, Vector3(surf, goal, a.facing))
		st = Vector3(lerp(st.x, surf, ks), lerp(st.y, goal, kl), move_toward(st.z, a.facing, _dt * TURN_RATE))
		state[a.id] = st
		var it = [a, p, st]
		if st.x >= 0.5:
			lanes[clampi(int(st.y * LANE_BUCKETS), 0, LANE_BUCKETS - 1)].append(it)
		elif lerp(float(a.z), float(a.tz), clamp(a.t, 0.0, 1.0)) > 0.5:
			back.append(it)
		else:
			front.append(it)
	_state = state
	for it in back:
		_draw_ant(it[0], it[1], it[2], far)
	_draw_queen(vr, far)
	for it in front:
		_draw_ant(it[0], it[1], it[2], far)
	for bucket in lanes:
		for it in bucket:
			_draw_ant(it[0], it[1], it[2], far)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# The lane an ant is drawn in on the surface: its own, pulled onto the nest mouth's lane near a mouth and, for a forager, onto the
# pile's lane at a pile, so nobody walks into the hole or reaches for the food from another depth.
func _lane_goal(g, a, piles: Array) -> float:
	var lane: float = a.lane
	for en in g.entrances:
		var d = abs(a.x - en.x)
		if d < ENTRANCE_REACH:
			lane = lerp(lane, ENTRANCE_LANE, 1.0 - d / ENTRANCE_REACH)
	if a.carry > 0.0 or a.task == 1:
		for px in piles:
			var d = abs(a.x - px)
			if d < PILE_REACH:
				lane = lerp(lane, PILE_LANE, 1.0 - d / PILE_REACH)
	return lane


func _draw_ant(a, p: Vector2, st: Vector3, far: float) -> void:
	var b = _bodies.get("alate_full" if a.ph.get("wings", 0) > 0 else CASTE_BODY[a.caste])
	if b == null:
		b = _bodies.get(CASTE_BODY[a.caste])
		if b == null:
			return
	var g = colony.grid
	var t = clamp(a.t, 0.0, 1.0)
	var plane = lerp(float(a.z), float(a.tz), t)
	var hidden = lerp(_behind(g, a.x, a.y, a.z), _behind(g, a.tx, a.ty, a.tz), t)
	var surf = st.x
	var lane = st.y
	var length = _length(a.ph.get("size", 74.0)) * CASTE_SCALE[a.caste]
	var s = length * far * lerp(1.0, Band.persp(lane), surf) * lerp(1.0, BACK_SCALE, plane) / b["length"]
	var feet = p + Vector2(-sin(a.rot), cos(a.rot)) * C * 0.5
	feet.y = lerp(feet.y, Band.lane_y(feet.y, lane), surf)
	var shade = lerp(1.0, BACK_SHADE, plane) * lerp(1.0, HIDDEN_SHADE, hidden)
	var col = Color(shade, shade, shade, lerp(1.0, HIDDEN_ALPHA, hidden))
	col *= Color.WHITE.lerp(HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0)) * colony.day.tint, surf)
	if a.hurt > 0.0:
		col *= Color.WHITE.lerp(HURT, clamp(a.hurt / HURT_T, 0.0, 1.0))
	var face = st.z if abs(st.z) > TURN_MIN else (TURN_MIN if st.z >= 0.0 else -TURN_MIN)
	draw_set_transform(feet, a.rot, Vector2(face * s, s))
	draw_texture(b["tex"], -b["feet"], col)
	if a.carry > 0.0 and not _foods.is_empty():
		var food = _foods[a.id % _foods.size()]
		var size: Vector2 = food["size"] * b["length"] / FOOD_REF
		draw_texture_rect(food["tex"], Rect2(b["jaw"] - size * 0.5, size), false, col)


# 1 where a back-plane ant has front dirt between it and us.
static func _behind(g, x: int, y: int, z: int) -> float:
	return 1.0 if z == 1 and g.is_solid(x, y, 0) else 0.0


static func _length(size: float) -> float:
	var t = LEN_PER_SIZE * size + LEN_BASE
	return LEN_K * t * min(1.0, 310.0 / (t + 120.0))


# The queen, facing right, her body centred on the chamber and her feet on its floor: the first solid cell below the chamber's centre.
func _draw_queen(vr: Rect2, far: float) -> void:
	var b = _bodies.get("queen_full")
	if b == null:
		return
	var sim = colony.sim
	var g = colony.grid
	var cx = int(g.chamber.x)
	var y = int(g.chamber.y)
	var lim = y + int(ceil(g.chamber_r.y)) + 4
	while y < lim and not g.is_solid(cx, y, 0):
		y += 1
	var s = QUEEN_LEN * far / b["length"]
	var feet = Vector2((cx + 0.5) * C + (b["feet"].x - b["mid"]) * s, y * C)
	if not vr.has_point(feet):
		return
	draw_set_transform(feet, 0.0, Vector2(s, s))
	draw_texture(b["tex"], -b["feet"], Color.WHITE.lerp(HURT, clamp(sim.queen_flash / QUEEN_HURT_T, 0.0, 1.0)))
