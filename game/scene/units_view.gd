extends Node2D
# The ants, built from the owner's ant part kit as the Godot 3 view built them (scene/ant_kit.gd: kit_painter + sprite_baker): every
# strain's body plan picks its own head, jaws, antennae, thoraxes, abdomen, legs, wings, sting, spines and plates from its genome, so
# the colony is seen to evolve; soldiers wear bigger heads and jaws, diggers spiny forelegs. Each look is baked once (six walk frames
# and a standing pose) and an ant is one quad a frame (two for a winged one), tinted by its genome's colour. Until a look is baked, or
# where nothing can be baked (--headless), the ant is drawn with the whole-body picture of its caste (antkit *_full) instead.
#
# Placement, as the Godot 3 view (ant_view.gd) did it: the sim keeps an ant on a cell and tilts it by a.rot so its feet point at the
# ground it walks on; a.facing flips it. Underground the feet go on the dirt as the soil view DRAWS it (its mask is the solid cells
# blurred 1-2-1, drawn over one half): along the body's down to the drawn ground, or, where the sim's footing is a crumb the soil view
# smooths away, down onto the floor below, upright; ants crowding one spot spread out along the ground. Back-plane ants are smaller
# and dimmer, and ghosted where front dirt hides them. On the surface every ant walks in a lane of the meadow band (band.gd): lifted,
# smaller and hazier toward the back, in the daylight tint. The legs walk by the distance really covered (feet stay planted); poses
# as the old view: fight lunges, the dig jackhammer, rearing up on guard, a flinch when bitten, nursing rock, idle breathing and
# grooming, a nod on picking food up and a hop on delivering it, newborns pop out and wobble, winged ants take off over open ground.
# Food is held at the jaws. The queen (queen_full) breathes, paces her chamber floor and squeezes when she lays.
# Hooks: ants in colony.views["controls"].selected are drawn brighter; ant_spot(a) says where an ant is drawn (for picking).

const Art = preload("res://scene/art.gd")
const Band = preload("res://scene/band.gd")
const WorldGrid = preload("res://core/world_grid.gd")
const AntKit = preload("res://scene/ant_kit.gd")

const C = WorldGrid.CELL
const CASTE_BODY = ["worker_full", "worker_small_full", "soldier_full"]
const CASTE_SCALE = [0.94, 1.0, 1.12]      # forager, digger, soldier (the old view's)
# Body length of a whole-body picture (before its look is baked), as the old view drew a body plan: its painter laid a body out over
# T = 2.2 px per unit of phenotype size + 24, squeezed big ones by 310 / (T + 120) and drew it at 0.55 * 0.24 (about 24 px long).
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
const JAW_DOWN = 0.12                      # (whole-body pictures) held food sits this far below the nose, in body lengths
const KIT_BASE = Color(0.60, 0.52, 0.46)  # the kit's drab mean fill: genome colour / this tints a picture, as the old painter did
const CAMO = Color(0.44, 0.42, 0.33)       # a camouflaged line's colour drifts toward this drab
const WING_TINT = 0.25                     # wings take this much of the strain's colour
const HURT = Color(1.0, 0.45, 0.45)
const HURT_T = 0.12                        # a bite sets a.hurt to this
const QUEEN_HURT_T = 0.6
const SELECTED = Color(1.45, 1.45, 1.25)   # ants in the player's selection (controls.gd)
const FAR_ZOOM = 0.45                      # zoomed out past this, ants grow (up to FAR_MAX) so they stay more than specks
const FAR_MAX = 1.6
const MARGIN = 80.0                        # world px past the view an ant can still reach into it
const LANE_BUCKETS = 16
const POSE_ZOOM = 0.6                      # zoomed out below this the poses are too small to see and are skipped
# the drawn ground (underground)
const REACH = 2.2                          # cells: how far along its body's down an ant looks for the drawn ground
const DROP = 10.0                          # cells: with none there, how far below it looks for a floor to stand on
const GROUND_LIFE = 1.5                    # s: a cached answer about the ground is worked out again after this (the colony digs)
const NONE = 1e9
const SNAP_RATE = 14.0                     # 1/s: how fast the drawn feet follow the ground they are put on
const SPREAD_GAP = 0.42                    # body lengths between ants crowding one spot
const SPREAD_MAX = 3.5                     # cells: at most this far from where the sim keeps it
const SPREAD_RATE = 5.0
const SPREAD_STEP = 1.2                    # cells: the drawn ground may step this much between neighbours in a crowd
# flight (winged ants over open ground) and walking
const AIR_RATE = 3.5
const AIR_LIFT = 30.0                      # world px at full height (times the lane's perspective)
const FLAP_HZ = 7.0                        # wing beats per second
const STRIDE_CAP = 0.15                    # walk cycles per frame at most, so very fast ants do not strobe
# the queen
const QUEEN_PACE = 0.3                     # paces this share of her chamber's half-width
const QUEEN_LAY_T = 0.45

# per-ant state, kept only for ants near the view: an Array indexed by these
const S_SURF = 0       # 0 underground .. 1 surface (smoothed)
const S_LANE = 1       # the lane it is drawn in (smoothed)
const S_FACE = 2       # drawn facing -1..1 (a turn squashes through the middle)
const S_GAIT = 3       # walk-cycle phase (cycles)
const S_PX = 4         # where it was last frame (world px)
const S_PY = 5
const S_OX = 6         # drawn feet minus sim position (smoothed)
const S_OY = 7
const S_ROT = 8        # drawn tilt (smoothed)
const S_SPREAD = 9     # sideways offset in a crowd (smoothed), px along the ground
const S_AIR = 10       # 0 on the ground .. 1 flying
const S_CARRY = 11     # carried last frame (a pick-up nods, a delivery hops)
const S_GRAB = 12
const S_HOP = 13
const S_GROOM = 14
const S_NEXT = 15      # seconds to the next groom
const S_SPOT_X = 16    # where it was drawn: body middle and radius (ant_spot)
const S_SPOT_Y = 17
const S_SPOT_R = 18
const S_N = 19

const DIRS = 16

var colony
var kit                     # ant_kit.gd: the baked looks
var _bodies := {}           # picture name -> {tex, feet, length; jaw, mid (x halfway from tail to nose) from the feet} in picture pixels
var _foods := []            # [{tex, size}]: size in world px for a FOOD_REF-long worker (premultiplied textures)
var _state := {}            # ant id -> Array (S_*)
var _dt := 0.016
var _t := 0.0
var _g                      # colony.grid while drawing
var _gc := {}               # (cell, plane, direction) -> Vector2(distance from the cell centre to the drawn ground along it, time)
var _gc_t := 0.0
var _dir := []              # DIRS unit vectors (16 = straight down)
var _foes := PackedVector2Array()
var _q_eggs := 0
var _q_lay := 0.0
var _q_face := 1.0
var _q_x := 0.0
var _lane_alpha := false    # band.gd has lane_alpha(lane) (the depth zoom cuts lanes): surface ants fade with their lane


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# the baked looks are premultiplied (what a transparent viewport holds), so everything here is drawn premultiplied
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = mat
	for m in (Band as Script).get_script_method_list():
		if m["name"] == "lane_alpha":
			_lane_alpha = true
	kit = AntKit.new()
	kit.name = "AntKit"
	add_child(kit)
	for i in DIRS:
		_dir.append(Vector2.from_angle(TAU * i / DIRS))
	_dir.append(Vector2.DOWN)
	var pieces = Art.manifest("antkit_manifest.json").get("pieces", {})
	for name in CASTE_BODY + ["alate_full", "queen_full"]:
		var p = pieces.get(name)
		var tex = Art.tex(p["file"]) if p != null else null
		if tex == null:
			continue
		var feet = Vector2(p["feet"][0], p["feet"][1])
		var nose = Vector2(p["nose"][0], p["nose"][1]) - feet
		_bodies[name] = {"tex": _premul(tex), "feet": feet, "length": float(p["length"]),
			"jaw": nose + Vector2(0, JAW_DOWN * float(p["length"])), "mid": (nose.x + float(p["tail"][0]) - feet.x) * 0.5}
	var fauna = Art.manifest("fauna_manifest.json").get("items", {})
	for name in FOODS:
		var f = fauna.get(name)
		var tex = Art.tex(f["file"]) if f != null else null
		if tex != null:
			_foods.append({"tex": _premul(tex), "size": Vector2(f["w"], f["h"]) * float(f["scale"])})


# A picture premultiplied and mipmapped (they are imported without mipmaps; an ant is drawn at a tenth of its picture's size or less).
static func _premul(tex: Texture2D) -> Texture2D:
	var img = tex.get_image()
	if img == null or img.is_empty():
		return tex
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.premultiply_alpha()
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _pm(c: Color) -> Color:
	return Color(c.r * c.a, c.g * c.a, c.b * c.a, c.a)


func reset() -> void:
	_state = {}
	_gc = {}
	_q_eggs = 0
	if kit != null:
		kit.reset()


func _process(delta: float) -> void:
	_dt = delta
	_t += delta
	queue_redraw()


func _draw() -> void:
	var sim = colony.sim
	var g = colony.grid
	_g = g
	if _t - _gc_t > GROUND_LIFE * 4.0 or _gc.size() > 60000:
		_gc = {}                    # entries expire one by one; this only stops the cache growing
		_gc_t = _t
	var vr = colony.view_rect(MARGIN)
	vr.position.y -= Band.DEPTH * Band.LANE_K + AIR_LIFT    # a surface ant is drawn up to this far above its cell
	vr.size.y += Band.DEPTH * Band.LANE_K + AIR_LIFT
	var zoom = colony.zoom()
	var far = clamp(sqrt(FAR_ZOOM / zoom), 1.0, FAR_MAX)
	var poses = zoom >= POSE_ZOOM
	var ks = 1.0 - exp(-_dt * SURF_RATE)
	var kl = 1.0 - exp(-_dt * LANE_RATE)
	var ctl = colony.views.get("controls")
	var sel = ctl.get("selected") if ctl != null else null
	if not (sel is Dictionary):
		sel = {}
	var piles := []
	for p in sim.piles:
		var px = (p["x"] + 0.5) * C
		if px > vr.position.x - PILE_REACH * C and px < vr.end.x + PILE_REACH * C:
			piles.append(p["x"])
	_foes = PackedVector2Array()
	if poses:
		for e in sim.enemies:
			if e.state != 2:
				var ep = sim.enemy_pos(e)
				if vr.grow(60.0).has_point(ep):
					_foes.append(ep)
	var state := {}
	var back := []
	var front := []
	var lanes := []
	for i in LANE_BUCKETS:
		lanes.append([])
	var crowd := {}            # spot -> [items]: underground ants close together
	for a in sim.ants:
		var p = sim.ant_pos(a)
		if not vr.has_point(p):
			continue
		var surf = 1.0 if g.is_surface_cell(a.tx, a.ty) else 0.0
		var goal = _lane_goal(g, a, piles)
		var st = _state.get(a.id)
		if st == null:
			st = _new_state(a, p, surf, goal)
		st[S_SURF] = lerp(float(st[S_SURF]), surf, ks)
		st[S_LANE] = lerp(float(st[S_LANE]), goal, kl)
		state[a.id] = st
		var it = [a, p, st, 0.0]
		if st[S_SURF] >= 0.5:
			lanes[clampi(int(st[S_LANE] * LANE_BUCKETS), 0, LANE_BUCKETS - 1)].append(it)
		else:
			_place(a, p, st)
			var z = a.tz if a.t > 0.5 else a.z
			var key = ((int(p.x / C) >> 1) * 8192 + (int(p.y / C) >> 1)) * 2 + z
			var c = crowd.get(key)
			if c == null:
				crowd[key] = [it]
			else:
				c.append(it)
			if lerp(float(a.z), float(a.tz), clamp(a.t, 0.0, 1.0)) > 0.5:
				back.append(it)
			else:
				front.append(it)
	_state = state
	for c in crowd.values():
		_spread(c, far)
	for it in back:
		_draw_ant(it[0], it[1], it[2], far, poses, sel)
	_draw_queen(vr, far)
	for it in front:
		_draw_ant(it[0], it[1], it[2], far, poses, sel)
	for bucket in lanes:
		for it in bucket:
			_draw_ant(it[0], it[1], it[2], far, poses, sel)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _new_state(a, p: Vector2, surf: float, lane: float) -> Array:
	var st := []
	st.resize(S_N)
	st.fill(0.0)
	st[S_SURF] = surf
	st[S_LANE] = lane
	st[S_FACE] = float(a.facing)
	st[S_GAIT] = a.id * 0.37
	st[S_PX] = p.x
	st[S_PY] = p.y
	var down = Vector2(-sin(a.rot), cos(a.rot)) * C * 0.5
	st[S_OX] = down.x
	st[S_OY] = down.y
	st[S_ROT] = a.rot
	st[S_CARRY] = a.carry
	st[S_NEXT] = 2.0 + fmod(a.id * 1.37, 8.0)
	return st


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


# ------------------------------------------------------------------------------------------------ the drawn ground

# Solidity of cell (x, y) in plane z as the soil view's mask holds it: the solid cells blurred 1-2-1, 0..16 (drawn from 8 up).
func _cv(x: int, y: int, z: int) -> int:
	var g = _g
	var w: int = g.W
	var xl = x - g.ox
	if xl < 1 or xl >= w - 1 or y < 1 or y >= g.H - 1:
		return 16 if g.is_solid(x, y, z) else 0
	var s: PackedByteArray = g.solid
	var b = z * g.WH + y * w + xl
	return s[b - w - 1] + 2 * s[b - w] + s[b - w + 1] + 2 * s[b - 1] + 4 * s[b] + 2 * s[b + 1] + s[b + w - 1] + 2 * s[b + w] + s[b + w + 1]


# The mask at a world point (bilinear between cell centres, as the soil view samples it), 0..16.
func _field(px: float, py: float, z: int) -> float:
	var u = px / C - 0.5
	var v = py / C - 0.5
	var i = int(floor(u))
	var j = int(floor(v))
	var fu = u - i
	var fv = v - j
	var top = lerp(float(_cv(i, j, z)), float(_cv(i + 1, j, z)), fu)
	var bot = lerp(float(_cv(i, j + 1, z)), float(_cv(i + 1, j + 1, z)), fu)
	return lerp(top, bot, fv)


# Distance from (cx, cy) along d to where the drawn dirt starts (negative: the point is inside it, back out along -d), or NONE.
func _march(cx: float, cy: float, d: Vector2, z: int, reach: float) -> float:
	var step = C * 0.25
	var prev = _field(cx, cy, z)
	if prev >= 8.0:
		var s0 = 0.0
		while s0 < C:
			s0 += step
			var f0 = _field(cx - d.x * s0, cy - d.y * s0, z)
			if f0 < 8.0:
				return -(s0 - step * (8.0 - f0) / max(0.001, prev - f0))
			prev = f0
		return -C
	var s = 0.0
	while s < reach:
		s += step
		var f = _field(cx + d.x * s, cy + d.y * s, z)
		if f >= 8.0:
			return s - step * (f - 8.0) / max(0.001, f - prev)
		prev = f
	return NONE


# How far from world point p, along direction q (DIRS of them, DIRS = straight down and far), the drawn ground is; NONE if there is
# none within reach. Worked out from the centre of p's cell and cached per cell for GROUND_LIFE.
func _ground(p: Vector2, z: int, q: int) -> float:
	var cx = int(floor(p.x / C))
	var cy = int(floor(p.y / C))
	var key = (((cx + 65536) * 4096 + cy) * 2 + z) * 32 + q
	var e = _gc.get(key)
	var d: Vector2 = _dir[q]
	var c = Vector2((cx + 0.5) * C, (cy + 0.5) * C)
	if e == null or _t - e.y > GROUND_LIFE:
		e = Vector2(_march(c.x, c.y, d, z, (DROP if q == DIRS else REACH) * C), _t)
		_gc[key] = e
	if e.x >= NONE:
		return NONE
	return e.x - (p - c).dot(d)


# Where an underground ant's feet are drawn (S_OX, S_OY: from its sim position) and its tilt (S_ROT): on the drawn ground below its
# feet along its body's down; where there is none (it stands on a crumb the soil view does not draw), upright on the floor below.
func _place(a, p: Vector2, st: Array) -> void:
	var z = a.tz if a.t > 0.5 else a.z
	var rot: float = a.rot
	var down = Vector2(-sin(rot), cos(rot))
	var q = posmod(int(round(down.angle() / TAU * DIRS)), DIRS)
	var d = _ground(p, z, q)
	var off: Vector2
	if d < NONE:
		off = down * d
	else:
		var dd = _ground(p, z, DIRS)
		if dd < NONE:
			off = Vector2(0.0, dd)
			rot = 0.0
		else:
			off = down * C * 0.5
	var k = 1.0 - exp(-_dt * SNAP_RATE)
	st[S_OX] = lerp(float(st[S_OX]), off.x, k)
	st[S_OY] = lerp(float(st[S_OY]), off.y, k)
	st[S_ROT] = lerp_angle(float(st[S_ROT]), rot, k)


# Ants close together underground spread out along the ground they stand on (one after another along their bodies' axis), as far as
# the drawn ground goes on without a big step.
func _spread(items: Array, far: float) -> void:
	var n = items.size()
	var k = 1.0 - exp(-_dt * SPREAD_RATE)
	for i in n:
		var it = items[i]
		var a = it[0]
		var st: Array = it[2]
		var want = 0.0
		if n > 1:
			var gap = SPREAD_GAP * _len_of(a) * far
			want = clamp((i - (n - 1) * 0.5) * gap, -SPREAD_MAX * C, SPREAD_MAX * C)
		var cur = lerp(float(st[S_SPREAD]), want, k)
		st[S_SPREAD] = cur
		if abs(cur) < 0.3:
			continue
		var p: Vector2 = it[1]
		var rot: float = st[S_ROT]
		var down = Vector2(-sin(rot), cos(rot))
		var along = Vector2(cos(rot), sin(rot))
		var z = a.tz if a.t > 0.5 else a.z
		var q = posmod(int(round(down.angle() / TAU * DIRS)), DIRS)
		var base = Vector2(st[S_OX], st[S_OY]).dot(down)
		# the furthest the ground carries it toward the spot it wants, in up to three tries
		var off = cur
		for tries in 3:
			var d = _ground(p + along * off, z, q)
			if d < NONE and abs(d - base) < SPREAD_STEP * C:
				st[S_OX] += along.x * off + down.x * (d - base)
				st[S_OY] += along.y * off + down.y * (d - base)
				break
			off *= 0.5
			if tries == 2:
				st[S_SPREAD] = lerp(cur, 0.0, 0.5)


# ------------------------------------------------------------------------------------------------ drawing an ant

# Body length in world px (tail to nose) before depth scaling: the look's (its painter's layout) or, before it is baked, the size's.
func _len_of(a) -> float:
	var wl = kit.world_len(a.genome, a.caste) if kit != null else -1.0
	if wl <= 0.0:
		wl = _length(a.ph.get("size", 74.0))
	return wl * CASTE_SCALE[clampi(a.caste, 0, 2)]


func _draw_ant(a, p: Vector2, st: Array, far: float, poses: bool, sel: Dictionary) -> void:
	var g = colony.grid
	var t = clamp(a.t, 0.0, 1.0)
	var plane = lerp(float(a.z), float(a.tz), t)
	var hidden = lerp(_behind(g, a.x, a.y, a.z), _behind(g, a.tx, a.ty, a.tz), t)
	var surf: float = st[S_SURF]
	var lane: float = st[S_LANE]
	var depth = lerp(1.0, Band.persp(lane), surf) * lerp(1.0, BACK_SCALE, plane)
	var length = _len_of(a) * far * depth * _pop(a.age)
	# where it stands: underground on the drawn ground (_place, _spread), on the surface in its lane
	var down = Vector2(-sin(a.rot), cos(a.rot))
	var feet = p + down * C * 0.5
	feet = feet.lerp(p + Vector2(st[S_OX], st[S_OY]), 1.0 - surf)
	feet.y = lerp(feet.y, Band.lane_y(feet.y, lane), surf)
	var rot = lerp_angle(float(st[S_ROT]), a.rot, surf)
	# walking: the cycle advances by the ground really covered, so the feet stay planted
	var moved = Vector2(st[S_PX], st[S_PY]).distance_to(p)
	st[S_PX] = p.x
	st[S_PY] = p.y
	var walking = (a.tx != a.x or a.ty != a.y) and moved > 0.001
	var lk = kit.look(a.genome, a.caste) if kit != null else null
	if walking and moved < 90.0:
		var cyc = (lk["cycle"] if lk != null else 0.6) * length
		st[S_GAIT] = float(st[S_GAIT]) + min(moved / max(1.0, cyc), STRIDE_CAP)
	# flight: a winged ant crossing open ground takes off, and lands at the pile or the nest
	var fly = 1.0 if (a.ph.get("wings", 0) > 0 and surf > 0.5 and walking and a.curl_t <= 0.0) else 0.0
	var air: float = st[S_AIR]
	if fly > 0.0 or air > 0.0:
		air = move_toward(air, fly, _dt * AIR_RATE * (1.0 if fly > 0.0 else 0.6))
		st[S_AIR] = air
		feet.y -= air * AIR_LIFT * depth * (1.0 + 0.15 * sin(_t * 3.0 + a.id))
	# pose: a transform about the feet (old ant_view._apply_pose)
	var pose = _pose(a, st, p, walking, length) if poses else [Vector2.ZERO, 0.0, 1.0, 1.0, float(a.facing)]
	var tf = move_toward(float(st[S_FACE]), pose[4], _dt * TURN_RATE)
	st[S_FACE] = tf
	var face = tf if abs(tf) > TURN_MIN else (TURN_MIN if tf >= 0.0 else -TURN_MIN)
	rot += pose[1] - air * 0.14 * sign(face)
	var bob = (sin(_t * 16.0 + a.id) * (0.09 if a.carry > 0.0 else 0.06) if walking and air < 0.5 else 0.0) if poses else 0.0
	var hurt = clamp(a.hurt / HURT_T, 0.0, 1.0)
	# colour: shade by depth and haze, the strain's colour over the drab kit, hurt flash, selection
	var shade = lerp(1.0, BACK_SHADE, plane) * lerp(1.0, HIDDEN_SHADE, hidden)
	var alpha = lerp(1.0, HIDDEN_ALPHA, hidden) * (0.55 if a.shelter_t > 0.0 else 1.0)
	if _lane_alpha and surf > 0.0:
		alpha *= lerp(1.0, float(Band.call("lane_alpha", lane)), surf)
		if alpha <= 0.01:
			return
	var light = Color(shade, shade, shade, alpha)
	light *= Color.WHITE.lerp(HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0)) * colony.day.tint, surf)
	if hurt > 0.0:
		light *= Color.WHITE.lerp(HURT, hurt)
	if sel.has(a.id):
		light *= SELECTED
	var tint = _tint(a.genome)
	# the spot it is drawn at (picking)
	var mid = feet - Vector2(-sin(rot), cos(rot)) * length * 0.2
	st[S_SPOT_X] = mid.x
	st[S_SPOT_Y] = mid.y
	st[S_SPOT_R] = length * 0.5
	if lk != null:
		var s = length / lk["len"]
		var sx = face * s * pose[2] * (1.0 + 0.12 * hurt)
		var sy = s * pose[3] * (1.0 + bob - 0.14 * hurt)
		draw_set_transform(feet + pose[0], rot, Vector2(sx, sy))
		var cell: Vector2 = lk["cell"]
		var fr = int(fposmod(float(st[S_GAIT]), 1.0) * AntKit.FRAMES) % AntKit.FRAMES if (walking or air > 0.05) else AntKit.STAND
		var dst = Rect2(-lk["feet"], cell)
		draw_texture_rect_region(lk["tex"], dst, Rect2(cell.x * fr, 0.0, cell.x, cell.y), _pm(light * tint))
		if lk["wings"]:
			var wc = _pm(light * Color.WHITE.lerp(tint, WING_TINT))
			if air > 0.05:
				# beating: the folded wings swing up and down about their root
				var beat = sin(_t * TAU * FLAP_HZ + a.id * 1.3)
				var root = Vector2(lk["mid"].x * 0.2, lk["mid"].y * 1.25)
				var ang = -air * (0.5 + 0.45 * beat)
				draw_set_transform_matrix(Transform2D(rot, Vector2(sx, sy), 0.0, feet + pose[0]) * Transform2D(ang, root) * Transform2D(0.0, -root))
			draw_texture_rect_region(lk["tex"], dst, Rect2(cell.x * fr, cell.y, cell.x, cell.y), wc)
			if air > 0.05:
				draw_set_transform(feet + pose[0], rot, Vector2(sx, sy))
		if a.carry > 0.0 and not _foods.is_empty():
			var food = _foods[a.id % _foods.size()]
			var size: Vector2 = food["size"] * lk["len"] / FOOD_REF
			draw_texture_rect(food["tex"], Rect2(lk["jaw"] - size * 0.5, size), false, _pm(light))
		return
	# not baked yet: the caste's whole-body picture
	var b = _bodies.get("alate_full" if a.ph.get("wings", 0) > 0 else CASTE_BODY[a.caste])
	if b == null:
		b = _bodies.get(CASTE_BODY[a.caste])
		if b == null:
			return
	var s2 = length / b["length"]
	draw_set_transform(feet + pose[0], rot, Vector2(face * s2 * pose[2], s2 * pose[3] * (1.0 + bob)))
	draw_texture(b["tex"], -b["feet"], _pm(light * tint))
	if a.carry > 0.0 and not _foods.is_empty():
		var food2 = _foods[a.id % _foods.size()]
		var size2: Vector2 = food2["size"] * b["length"] / FOOD_REF
		draw_texture_rect(food2["tex"], Rect2(b["jaw"] - size2 * 0.5, size2), false, _pm(light))


# The pose on top of the walk cycle, as a transform about the feet: [offset (world px), extra tilt, x scale, y scale, facing].
# (Old ant_view._apply_pose: offsets there were for a 24 px ant, so they scale with the body.)
func _pose(a, st: Array, p: Vector2, walking: bool, length: float) -> Array:
	var off := Vector2.ZERO
	var rot := 0.0
	var sx := 1.0
	var sy := 1.0
	var face := float(a.facing)
	var u = length / 24.0
	var fwd = Vector2(cos(a.rot), sin(a.rot)) * face
	# a pick-up nods twice, a delivery hops
	if a.carry > 0.0 and float(st[S_CARRY]) <= 0.0:
		st[S_GRAB] = 0.4
	elif a.carry <= 0.0 and float(st[S_CARRY]) > 0.0:
		st[S_HOP] = 0.5
	st[S_CARRY] = a.carry
	var foe := Vector2.ZERO
	var foe_d2 := INF
	if not _foes.is_empty() and (a.task == 4 or a.task == 1 or a.hurt > 0.0):
		for fp in _foes:
			var d2 = fp.distance_squared_to(p)
			if d2 < foe_d2:
				foe_d2 = d2
				foe = fp
	if foe_d2 < 900.0 and (a.task == 4 or a.hurt > 0.0):
		# fighting: turn to the raider and lunge at it
		face = 1.0 if foe.x >= p.x else -1.0
		fwd = Vector2(cos(a.rot), sin(a.rot)) * face
		var lunge = max(0.0, sin(_t * 13.0 + a.id * 1.9))
		lunge *= lunge
		off += fwd * (6.0 * lunge * u)
		rot += face * (0.24 * lunge - 0.04)
		sy *= 1.0 - 0.07 * lunge
	elif a.dig_timer > 0.0:
		# digging: jackhammer against the wall it faces
		if int(a.dig_cell.x) != a.x:
			face = 1.0 if a.dig_cell.x > a.x else -1.0
			fwd = Vector2(cos(a.rot), sin(a.rot)) * face
		var jh = sin(_t * 34.0 + a.id)
		off += fwd * (2.2 * jh * u)
		off.y += 0.8 * sin(_t * 61.0) * u
		rot += face * (0.12 + 0.03 * jh)
	elif a.task == 4 and not walking:
		# holding the line with nothing in reach: rear up and show off
		rot -= face * (0.28 + 0.06 * sin(_t * 3.0 + a.id))
	elif a.task == 1 and foe_d2 < 2304.0:
		# a forager near a raider flinches and shivers
		off.x += sin(_t * 50.0 + a.id) * u
		rot -= face * 0.1
	elif a.task == 0 and not walking:
		# nursing: rocking over the brood
		rot += 0.1 * sin(_t * 3.1 + a.id * 1.7)
		sy *= 1.0 + 0.03 * sin(_t * 6.2 + a.id)
	elif not walking:
		# idle: breathing, and now and then a quick groom
		st[S_NEXT] = float(st[S_NEXT]) - _dt
		if float(st[S_GROOM]) > 0.0:
			st[S_GROOM] = max(0.0, float(st[S_GROOM]) - _dt)
			var dip = sin((1.0 - float(st[S_GROOM]) / 1.1) * PI)
			rot += face * 0.3 * dip + 0.05 * sin(_t * 30.0) * dip
			off.y += 1.5 * dip * u
		elif float(st[S_NEXT]) <= 0.0:
			st[S_GROOM] = 1.1
			st[S_NEXT] = 6.0 + fmod(a.id * 2.31 + _t, 9.0)
		sy *= 1.0 + 0.022 * sin(_t * 2.4 + a.id)
		sx *= 1.0 - 0.01 * sin(_t * 2.4 + a.id)
	if float(st[S_GRAB]) > 0.0:
		st[S_GRAB] = max(0.0, float(st[S_GRAB]) - _dt)
		var nod = abs(sin((1.0 - float(st[S_GRAB]) / 0.4) * TAU))
		rot += face * 0.34 * nod
		off.y += 1.5 * nod * u
	if float(st[S_HOP]) > 0.0:
		st[S_HOP] = max(0.0, float(st[S_HOP]) - _dt)
		var hk = 1.0 - float(st[S_HOP]) / 0.5
		var hh = sin(hk * PI)
		off.y -= 9.0 * hh * u
		sy *= 1.0 + 0.1 * hh - (0.08 if hk > 0.88 else 0.0)
	if a.hurt > 0.0:
		var hu = clamp(a.hurt / HURT_T, 0.0, 1.0)
		off -= fwd * (3.0 * hu * u)
		off.x += sin(_t * 70.0 + a.id) * 1.2 * hu * u
	if a.age < 0.5:
		rot += 0.3 * (1.0 - a.age / 0.5) * sin(a.age * 40.0)     # wobbly first steps
	if a.carry > 0.0 and walking:
		rot += face * 0.07                                         # leaning into the load
	return [off, rot, sx, sy, face]


# easeOutBack: a newborn pops out of its cocoon
static func _pop(age: float) -> float:
	if age >= 0.5:
		return 1.0
	var k = age / 0.5
	return max(0.05, 1.0 + 2.70158 * pow(k - 1.0, 3.0) + 1.70158 * pow(k - 1.0, 2.0))


# The strain's colour over the drab kit (a camouflaged line drifts toward drab), as the old painter tinted its pieces.
static func _tint(gn) -> Color:
	var c: Color = gn.color
	var camo = float(gn.morph.get("camo", 0.0)) if gn.get("morph") is Dictionary else 0.0
	if camo > 0.0:
		c = c.lerp(CAMO, 0.55 * camo)
	return _tint_c(c)


static func _tint_c(c: Color) -> Color:
	if c.v < 0.3:
		c = Color.from_hsv(c.h, c.s, 0.3)      # near-black lines still show their shading against the ink
	return Color(c.r / KIT_BASE.r, c.g / KIT_BASE.g, c.b / KIT_BASE.b)


# 1 where a back-plane ant has front dirt between it and us.
static func _behind(g, x: int, y: int, z: int) -> float:
	return 1.0 if z == 1 and g.is_solid(x, y, 0) else 0.0


static func _length(size: float) -> float:
	var t = LEN_PER_SIZE * size + LEN_BASE
	return LEN_K * t * min(1.0, 310.0 / (t + 120.0))


# Where an ant is drawn: Vector3(x, y, radius) in world px, the middle of its body (controls.gd picks with it). An ant not drawn this
# frame (off screen) is placed the plain way.
func ant_spot(a) -> Vector3:
	var st = _state.get(a.id)
	if st != null and float(st[S_SPOT_R]) > 0.0:
		return Vector3(st[S_SPOT_X], st[S_SPOT_Y], st[S_SPOT_R])
	var p = colony.sim.ant_pos(a)
	var down = Vector2(-sin(a.rot), cos(a.rot))
	var length = _len_of(a) * clamp(sqrt(FAR_ZOOM / colony.zoom()), 1.0, FAR_MAX)
	var mid = p + down * C * 0.5 - down * length * 0.2
	return Vector3(mid.x, mid.y, length * 0.5)


# The queen, her body centred on the chamber and her feet on its drawn floor; she paces a little, breathes, and squeezes as she lays.
func _draw_queen(vr: Rect2, far: float) -> void:
	var b = _bodies.get("queen_full")
	if b == null:
		return
	var sim = colony.sim
	var g = colony.grid
	var w = g.chamber_r.x * C * QUEEN_PACE
	var qx = w * (0.7 * sin(_t * 0.21) + 0.3 * sin(_t * 0.53 + 1.0))
	var qv = qx - _q_x
	_q_x = qx
	var walking = abs(qv) > _dt * 0.6
	if abs(qv) > _dt * 0.2:
		_q_face = move_toward(_q_face, sign(qv), _dt * 3.0)
	var s = QUEEN_LEN * far / b["length"]
	var cx = (g.chamber.x + 0.5) * C + qx
	var cy = (g.chamber.y + 0.5) * C
	var d = _ground(Vector2(cx, cy), 0, DIRS)
	var fy = cy + d if d < NONE else (g.chamber.y + g.chamber_r.y + 0.5) * C
	var feet = Vector2(cx - b["mid"] * s * sign(_q_face), fy)
	if not vr.has_point(feet):
		return
	if sim.eggs.size() > _q_eggs:
		_q_lay = QUEEN_LAY_T
	_q_eggs = sim.eggs.size()
	_q_lay = max(0.0, _q_lay - _dt)
	var hurt = clamp(sim.queen_flash / QUEEN_HURT_T, 0.0, 1.0)
	if hurt > 0.0:
		feet.x += sin(_t * 70.0) * 2.0 * hurt
	var breath = sin(_t * 1.9) * 0.022
	var lay = sin(clamp(_q_lay / QUEEN_LAY_T, 0.0, 1.0) * PI) * 0.07
	var tilt = sin(_t * 5.0) * 0.025 if walking else sin(_t * 0.8) * 0.01
	var face = _q_face if abs(_q_face) > TURN_MIN else TURN_MIN * (1.0 if _q_face >= 0.0 else -1.0)
	draw_set_transform(feet, tilt, Vector2(s * face * (1.0 + 0.05 * hurt + lay * 0.6), s * (1.0 + breath - 0.06 * hurt - lay)))
	draw_texture(b["tex"], -b["feet"], _pm(_tint(sim.queen_genome) * Color.WHITE.lerp(HURT, hurt)))
