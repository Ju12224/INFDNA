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
const ENTRANCE_LANE = 1.0                  # near a nest mouth ants are drawn onto its lane (the front lip), at a pile onto the pile's
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
const GROUND_ZOOM = 0.5                    # ... and below this a cell is a pixel or two: ants stand where the sim keeps them
const _NO_POSE = [Vector2.ZERO, 0.0, 1.0, 1.0, 1.0]
# the drawn ground (underground)
const REACH = 2.2                          # cells: how far along its body's down an ant looks for the drawn ground
const DROP = 10.0                          # cells: with none there, how far below it looks for a floor to stand on
const GROUND_LIFE = 1.5                    # s: a cached answer about the ground is worked out again after this (the colony digs)
const NONE = 1e9
const SNAP_RATE = 14.0                     # 1/s: how fast the drawn feet follow the ground they are put on
const SPREAD_GAP = 0.6                     # body lengths between ants of one row crowding a spot
const SPREAD_MAX = 5.0                     # cells: at most this far from where the sim keeps it
const SPREAD_RATE = 3.5                    # 1/s: how fast a crowd settles into its places
const CROWD_FROM = 2.0                     # ants in a 4 x 4 cell block from which a crowd is drawn in depth rows ...
const CROWD_SPAN = 3.0                     # ... all the way when there are this many more
const CROWD_RATE = 3.0
const ROW_SCALE = [1.0, 0.93, 0.86]        # a crowd stands in three rows: the back ones are further off, smaller and darker
const ROW_SHADE = [1.0, 0.9, 0.8]
const ROW_LIFT = [0.0, 0.035, 0.07]        # body lengths up the screen, on a floor
const FIT_MIN = 0.7                        # an ant in a passage narrower than itself shrinks to this at most
const FIT_RATE = 6.0
const ROT_PX = 0.09                        # rad of turn per px walked (a quarter turn takes about 17 px, three cells) ...
const ROT_T = 1.6                          # ... and never slower than this (rad/s), so a stopped ant still settles
const ROT_EASE = 9.0
const SPREAD_STEP = 1.2                    # cells: the drawn ground may step this much between neighbours in a crowd
const BODY_MID = 0.36                      # the middle of an ant's body stands this many body lengths above its feet
const SQUEEZE = 1.2                        # cells: in a tight passage its feet may reach this far into the wall
# flight (winged ants over open ground) and walking
const AIR_RATE = 3.5
const AIR_LIFT = 30.0                      # world px at full height (times the lane's perspective)
const FLAP_HZ = 7.0                        # wing beats per second
const NEST_SCALE = 0.62                   # an ant underground is drawn this big next to one on the surface (the owner's size knob)
const TD_BODY = 470.0                     # topdown_worker_*.png: px from the tail to the jaw tips, of the picture's 512 x 310
const TD_PIVOT = Vector2(255.0, 155.0)    # ... and the point it turns about (the middle of the body)
const TD_JAW = Vector2(468.0, 158.0)      # ... where it holds food
const TD_GUTTER = 40                      # transparent border round each frame in the atlas, so mipmaps do not mix the neighbours
const TD_SEQ = [0, 1, 2, 1]               # the walk: passing pose between the two tripod poses
const TD_CYCLE = 0.95                     # body lengths walked per leg cycle (the art has three poses, so this runs brisk, not planted)
const TD_STRIDE_CAP = 0.22                # cycles per frame at most
const TD_EASE = 12.0                      # 1/s: how fast the body turns to its heading
const TD_TURN_MAX = 14.0                  # rad/s at most
const NEST_GAP = 0.62                     # body lengths between the middles of two ants in a nest crowd
const NEST_PUSH_MAX = 2.6                 # cells: how far a crowd may shove an ant off the cell the sim keeps it in
const NEST_PUSH_RATE = 5.0
const NEST_SIDE = 0.45                    # share of a push that goes to the ant's right instead (two-way traffic keeps to its right)
const HEAD_TAU = 0.18                    # s: the velocity the heading follows is averaged over this (a zig-zag step along a shaft does not wag the ant)
const NEST_NEIGHBOURS = [8192, -8190, 2, 8194]   # the crowd grid's keys one bucket on: right, down-left, down, down-right
const NEST_BUCKET = 3                     # cells: the crowd grid
const SNAP = 3.0                          # a sim step longer than this many cells is a jump (a hole, a respawn): drawn there at once
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
const S_LOOK = 19      # its look (ant_kit.gd; "tex" is null until baked), or null without the kit
const S_WLEN = 20      # body length, world px, caste scale included (before depth and zoom)
const S_TINT = 21      # the strain's colour over the drab kit
const S_WINGS = 22     # true: winged
const S_GKEY = 23      # cell, plane and direction the ground answers below are for
const S_GD = 24        # from that cell's centre: drawn ground along its down, along its up, straight down (or NONE)
const S_GD2 = 25
const S_GDROP = 26
const S_GT = 27        # when they were looked up
const S_AX = 28        # the sim's position at its last two steps (world px): the drawn ant slides from the older to the newer
const S_AY = 29        # between steps (see _draw), so it moves every frame, not once every 0.1 s
const S_SX = 30
const S_SY = 31
const S_ROW = 32       # its depth row in a crowd (0 front .. 2 back), from its id
const S_HASH = 33      # 0..1 from its id: the order it takes in a crowd's row
const S_CROWD = 34     # 0..1: how crowded it is, smoothed (a crowd is drawn in depth rows)
const S_FIT = 35       # 0.7..1: how much it shrinks to fit the passage it is in (smoothed)
const S_DX = 36        # drawn feet minus the sim position's ground spot: where the crowd pushed it along the ground this frame
const S_DY = 37
const S_FX = 38        # where its feet were drawn last frame
const S_FY = 39
const S_HEAD = 40      # nest ants: the way it faces (radians, eased toward its heading)
const S_PUX = 41       # nest ants: the push of the ants too close to it, this frame (world px)
const S_PUY = 42
const S_PUS = 43       # ... and the sum of the pushes (the sidestep that makes ants pass instead of walking through each other)
const S_NL = 44        # nest ants: body length this frame, world px
const S_VX = 45        # nest ants: its velocity, smoothed (px/s): the way it heads
const S_VY = 46
const S_N = 47

const DIRS = 16

var colony
var kit                     # ant_kit.gd: the baked looks
var _bodies := {}           # picture name -> {tex, feet, length; jaw, mid (x halfway from tail to nose) from the feet} in picture pixels
var _foods := []            # [{tex, size}]: size in world px for a FOOD_REF-long worker (premultiplied textures)
var _state := {}            # ant id -> Array (S_*)
var _dt := 0.016
var _sim_time := -1.0       # the sim's clock at the last draw: it changed, so the sim stepped
var _t := 0.0
var _g                      # colony.grid while drawing
var _gc := {}               # (cell, plane, direction) -> Vector2(distance from the cell centre to the drawn ground along it, time)
var _gc_t := 0.0
var _dir := []              # DIRS unit vectors (16 = straight down)
var _foes := PackedVector2Array()
var _q_eggs := 0
var _q_egg_tex: Texture2D    # the cream eggs in queen_full, cut out at load and drawn untinted over her tinted body
var _q_lay := 0.0
var _q_face := 1.0
var _q_x := 0.0
var _td_tex: Texture2D       # the three top-down worker frames side by side (premultiplied, mipmapped), null: nests are drawn side-on
var _td_size := Vector2(512, 310)
var _td_k := Color.WHITE     # KIT_BASE over the top-down body's own mean colour: the strain's tint is made for the kit
var _glow_tex: Texture2D
var draw_us := 0            # how long the last _draw took (tests read it)
var debug_on := false       # tests (ants_anim_test.gd): fill debug_frames with how each ant was drawn this frame
var debug_frames := {}      # ant id -> [baked, frame cell (-1: whole-body picture), walking, moved px, mid-step, gait, p.x, p.y, drawn spot x, y, task, digging, a.t, drawn tilt, body length px, row, surface 0..1, tilt before the pose]
var debug_stamp := 0        # counts the _draws that filled it
var debug_interp := true    # tests: false draws the ants where the sim has them, as before the step interpolation
var rows_hook := Callable()     # surface_view.gd sets this: draws its grass rows into this canvas between the surface lane buckets
var _lane_alpha := Callable()   # band.gd's lane_alpha(lane), if it has one (the depth zoom cuts lanes): surface ants fade with it


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# the baked looks are premultiplied (what a transparent viewport holds), so everything here is drawn premultiplied
	var mat = CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	material = mat
	var band: Object = Band
	for m in band.get_script_method_list():
		if m["name"] == "lane_alpha":
			_lane_alpha = Callable(band, "lane_alpha")
	kit = AntKit.new()
	kit.name = "AntKit"
	add_child(kit)
	for i in DIRS:
		_dir.append(Vector2.from_angle(TAU * i / DIRS))
	_dir.append(Vector2.DOWN)
	_build_td()
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
	var qp = pieces.get("queen_full")
	if qp != null and Art.tex(qp["file"]) != null:
		_q_egg_tex = _cream(Art.tex(qp["file"]))
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


# Only the cream pixels of a picture (the eggs in the queen's gaster), premultiplied and mipmapped; null if there are none.
static func _cream(tex: Texture2D) -> Texture2D:
	var img = tex.get_image()
	if img == null or img.is_empty():
		return null
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()
	var d = img.get_data()
	var n := 0
	for i in range(0, d.size(), 4):
		var r = d[i]
		var gg = d[i + 1]
		var b = d[i + 2]
		if not (r > 175 and gg > 150 and b > 105 and r - b < 110 and r >= gg):
			d[i + 3] = 0
		elif d[i + 3] > 0:
			n += 1
	if n < 20:
		return null
	img.set_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGBA8, d)
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
	var t0 = Time.get_ticks_usec()
	if debug_on:
		debug_frames = {}
		debug_stamp += 1
	var sim = colony.sim
	var g = colony.grid
	_g = g
	if _t - _gc_t > GROUND_LIFE * 4.0 or _gc.size() > 60000:
		_gc = {}                    # entries expire one by one; this only stops the cache growing
		_gc_t = _t
	var vr: Rect2 = colony.view_rect(MARGIN)
	vr.position.y -= Band.DEPTH * Band.LANE_K + AIR_LIFT    # a surface ant is drawn up to this far above its cell
	vr.size.y += Band.DEPTH * Band.LANE_K + AIR_LIFT
	var zoom: float = colony.zoom()
	var far: float = clamp(sqrt(FAR_ZOOM / zoom), 1.0, FAR_MAX)
	var poses = zoom >= POSE_ZOOM
	var ground = zoom >= GROUND_ZOOM
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
		var fr = vr.grow(60.0)
		for e in sim.enemies:
			if e.state != 2:
				var ep = sim.enemy_pos(e)
				if fr.has_point(ep):
					_foes.append(ep)
	var day_tint: Color = colony.day.tint
	var state := {}
	var back := [[], [], []]          # underground ants by depth row (the back rows are drawn first)
	var front := [[], [], []]
	var lanes := []
	for i in LANE_BUCKETS:
		lanes.append([])
	var crowd := {}            # spot -> [items]: underground ants close together
	# The sim moves an ant in steps of 0.1 s, so its position only changes every sixth frame or so. An ant is drawn between its last two
	# sim positions, by how far into the next step the colony's clock is: it moves (and walks) on every frame, one step behind the sim.
	var stepped: bool = sim.time != _sim_time
	var snap: float = SNAP * C * max(1.0, round((sim.time - _sim_time) / colony.STEP))      # (a frame can hold several steps at 3x and 10x)
	if not debug_interp:
		snap = -1.0
	_sim_time = sim.time
	var acc = colony.get("_acc")
	var alpha: float = clamp(float(acc) / colony.STEP, 0.0, 1.0) if acc != null else 1.0
	for a in sim.ants:
		var t: float = a.t
		var ps := Vector2((a.x + 0.5 + (a.tx - a.x) * t) * C, (a.y + 0.5 + (a.ty - a.y) * t) * C)
		if not vr.has_point(ps):
			continue
		var st = _state.get(a.id)
		if st == null:
			st = _new_state(a, ps, g)
		elif stepped:
			st[S_AX] = st[S_SX]
			st[S_AY] = st[S_SY]
			st[S_SX] = ps.x
			st[S_SY] = ps.y
		var p := ps
		var ax: float = st[S_AX]
		var ay: float = st[S_AY]
		if ax != ps.x or ay != ps.y:
			var dx: float = float(st[S_SX]) - ax
			var dy: float = float(st[S_SY]) - ay
			if abs(dx) + abs(dy) < snap:
				p = Vector2(ax + dx * alpha, ay + dy * alpha)
		state[a.id] = st
		var surf = 1.0 if g.is_surface_cell(a.tx, a.ty) else 0.0
		var sk: float = lerp(float(st[S_SURF]), surf, ks)
		st[S_SURF] = sk
		if sk > 0.001 or surf > 0.0:
			st[S_LANE] = lerp(float(st[S_LANE]), _lane_goal(g, a, piles), kl)
		var it = [a, p, st]
		if sk >= 0.5:
			lanes[clampi(int(float(st[S_LANE]) * LANE_BUCKETS), 0, LANE_BUCKETS - 1)].append(it)
			continue
		var z: int = a.tz if t > 0.5 else a.z
		if _td_tex != null:
			# seen from above: no ground to stand on, and a crowd is pushed apart on the wall (see _push_pairs)
			var plane0: float = a.z + (a.tz - a.z) * t
			st[S_NL] = float(st[S_WLEN]) * far * (lerp(1.0, BACK_SCALE, plane0) if plane0 > 0.0 else 1.0) * lerp(NEST_SCALE, 1.0, clamp(sk, 0.0, 1.0))
			st[S_PUX] = 0.0
			st[S_PUY] = 0.0
			st[S_PUS] = 0.0
			if ground:
				var tkey = (((int(p.x / (C * NEST_BUCKET)) + 1024) * 4096 + int(p.y / (C * NEST_BUCKET))) * 2 + z)
				var tc = crowd.get(tkey)
				if tc == null:
					crowd[tkey] = [it]
				else:
					tc.append(it)
		elif ground:
			_place(a, p, st, float(st[S_WLEN]) * far * (BACK_SCALE if z == 1 else 1.0), z)
			var key = ((int(p.x / C) >> 2) * 8192 + (int(p.y / C) >> 2)) * 2 + z
			var c = crowd.get(key)
			if c == null:
				crowd[key] = [it]
			else:
				c.append(it)
		else:
			st[S_DX] = 0.0
			st[S_DY] = 0.0
			st[S_CROWD] = 0.0
		if (a.z + (a.tz - a.z) * t) > 0.5:
			back[int(st[S_ROW])].append(it)
		else:
			front[int(st[S_ROW])].append(it)
	_state = state
	if _td_tex != null:
		for key in crowd:
			var c: Array = crowd[key]
			if c.size() > 1:
				_push_pairs(c, c, true)
			for nb in NEST_NEIGHBOURS:
				var c2 = crowd.get(key + nb)
				if c2 != null:
					_push_pairs(c, c2, false)
	else:
		for c in crowd.values():
			if c.size() > 1 or abs(float(c[0][2][S_SPREAD])) > 0.3 or float(c[0][2][S_CROWD]) > 0.01:
				_spread(c, far)
	var kf: int = kit._frame if kit != null else 0
	var td: bool = _td_tex != null
	for r in [2, 1, 0]:
		for it in back[r]:
			if td:
				_draw_nest_ant(it[0], it[1], it[2], far, poses, sel)
			else:
				_draw_ant(it[0], it[1], it[2], far, poses, sel, day_tint, kf)
	_draw_queen(vr, far)
	for r in [2, 1, 0]:
		for it in front[r]:
			if td:
				_draw_nest_ant(it[0], it[1], it[2], far, poses, sel)
			else:
				_draw_ant(it[0], it[1], it[2], far, poses, sel, day_tint, kf)
	for i in lanes.size():
		if rows_hook.is_valid():
			rows_hook.call(self, float(i) / LANE_BUCKETS)    # the meadow's grass rows standing behind this bucket (surface_view.gd)
		for it in lanes[i]:
			_draw_ant(it[0], it[1], it[2], far, poses, sel, day_tint, kf)
	if rows_hook.is_valid():
		rows_hook.call(self, 99.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_us = Time.get_ticks_usec() - t0


# The three top-down worker frames (art/antkit/topdown_worker_0..2.png) side by side in one texture, so every nest ant is one quad of one
# texture (a batch), with a transparent border so the mipmaps of one frame do not bleed into the next. Also the strain's tint, made for the
# kit's drab body, is scaled to this body's own colour; and a soft dot for glowing strains.
func _build_td() -> void:
	var imgs := []
	for i in 3:
		var tex = Art.tex("antkit/topdown_worker_%d.png" % i)
		if tex == null:
			return
		var img = tex.get_image()
		if img == null or img.is_empty():
			return
		img = img.duplicate()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		img.clear_mipmaps()
		imgs.append(img)
	_td_size = Vector2(imgs[0].get_width(), imgs[0].get_height())
	var cw: int = imgs[0].get_width() + 2 * TD_GUTTER
	var atlas = Image.create(cw * 3, imgs[0].get_height() + 2 * TD_GUTTER, false, Image.FORMAT_RGBA8)
	for i in 3:
		atlas.blit_rect(imgs[i], Rect2i(0, 0, imgs[i].get_width(), imgs[i].get_height()), Vector2i(i * cw + TD_GUTTER, TD_GUTTER))
	# the body's mean colour, leaving out the dark outline and the soft edge
	var sum := Vector3.ZERO
	var n := 0
	var im1: Image = imgs[1]
	for y in range(0, im1.get_height(), 3):
		for x in range(0, im1.get_width(), 3):
			var c = im1.get_pixel(x, y)
			if c.a > 0.98 and c.v > 0.35:
				sum += Vector3(c.r, c.g, c.b)
				n += 1
	if n > 50:
		sum /= n
		_td_k = Color(KIT_BASE.r / sum.x, KIT_BASE.g / sum.y, KIT_BASE.b / sum.z)
	atlas.premultiply_alpha()
	atlas.generate_mipmaps()
	_td_tex = ImageTexture.create_from_image(atlas)
	var gi = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for y in 64:
		for x in 64:
			var d = Vector2(x - 31.5, y - 31.5).length() / 32.0
			var al = clamp(1.0 - d, 0.0, 1.0)
			gi.set_pixel(x, y, Color(1, 1, 1, al * al))
	gi.premultiply_alpha()
	_glow_tex = ImageTexture.create_from_image(gi)


# Nest ants too close to each other push each other apart (world px, from the sim's positions, so the push is a smooth function of where
# they walk: no slots to change, no jitter). `same`: c is one bucket of the crowd grid, else its pairs with the bucket c2 next to it.
func _push_pairs(c: Array, c2: Array, same: bool) -> void:
	var n: int = c.size()
	var m: int = c2.size()
	for i in n:
		var si: Array = c[i][2]
		var pi: Vector2 = c[i][1]
		var li: float = si[S_NL]
		for j in range(i + 1 if same else 0, m):
			var sj: Array = c2[j][2]
			var pj: Vector2 = c2[j][1]
			var d0: float = NEST_GAP * (li + float(sj[S_NL])) * 0.5
			var dx: float = pi.x - pj.x
			var dy: float = pi.y - pj.y
			var d2: float = dx * dx + dy * dy
			if d2 >= d0 * d0:
				continue
			var dist: float = sqrt(d2)
			var ux: float
			var uy: float
			if dist < 0.05:
				var ang: float = float(c[i][0].id * 7 + c2[j][0].id * 13)
				ux = cos(ang)
				uy = sin(ang)
			else:
				ux = dx / dist
				uy = dy / dist
			var push: float = (d0 - dist) * 0.5
			si[S_PUX] += ux * push
			si[S_PUY] += uy * push
			si[S_PUS] += push
			sj[S_PUX] -= ux * push
			sj[S_PUY] -= uy * push
			sj[S_PUS] += push


# An ant inside the nest, seen from above on the glass: one quad of the top-down worker, centred on the ant and turned to the way it
# heads. The legs walk the cycle 0, 1, 2, 1 by the ground covered; standing, it rests on frame 1 and sways and breathes a little.
func _draw_nest_ant(a, p: Vector2, st: Array, far: float, poses: bool, sel: Dictionary) -> void:
	var t: float = clamp(a.t, 0.0, 1.0)
	var plane: float = a.z + (a.tz - a.z) * t
	var hidden := 0.0
	if a.z == 1 or a.tz == 1:
		hidden = lerp(_behind(_g, a.x, a.y, a.z), _behind(_g, a.tx, a.ty, a.tz), t)
	var sk: float = st[S_SURF]
	var length: float = float(st[S_NL]) * (_pop(a.age) if a.age < 0.5 else 1.0)
	# the way it heads: the velocity of the ant itself (not of the crowd's shoving), averaged a little, then eased
	var kv: float = 1.0 - exp(-_dt / HEAD_TAU)
	var vx: float = (p.x - float(st[S_PX])) / max(_dt, 0.001)
	var vy: float = (p.y - float(st[S_PY])) / max(_dt, 0.001)
	st[S_PX] = p.x
	st[S_PY] = p.y
	if abs(vx) + abs(vy) < 2000.0:
		st[S_VX] = lerp(float(st[S_VX]), vx, kv)
		st[S_VY] = lerp(float(st[S_VY]), vy, kv)
	var head: float = st[S_HEAD]
	var svx: float = st[S_VX]
	var svy: float = st[S_VY]
	if svx * svx + svy * svy > 36.0:
		var lim: float = TD_TURN_MAX * _dt
		head = wrapf(head + clamp(wrapf(atan2(svy, svx) - head, -PI, PI) * (1.0 - exp(-_dt * TD_EASE)), -lim, lim), -PI, PI)
		st[S_HEAD] = head
	# the crowd's push, with a share of it to the ant's right so two ants meeting in a tunnel pass instead of walking through each other
	var z: int = a.tz if a.t > 0.5 else a.z
	var kp: float = 1.0 - exp(-_dt * NEST_PUSH_RATE)
	var px: float = st[S_PUX]
	var py: float = st[S_PUY]
	var ps: float = st[S_PUS]
	var gx: float = px - sin(head) * ps * NEST_SIDE
	var gy: float = py + cos(head) * ps * NEST_SIDE
	var gm: float = sqrt(gx * gx + gy * gy)
	var gmax: float = NEST_PUSH_MAX * C
	if gm > gmax:
		gx *= gmax / gm
		gy *= gmax / gm
	var dx: float = lerp(float(st[S_DX]), gx, kp)
	var dy: float = lerp(float(st[S_DY]), gy, kp)
	if abs(dx) + abs(dy) > 1.0 and _field(p.x + dx, p.y + dy, z) >= 8.0 and _field(p.x, p.y, z) < 8.0:
		dx *= 0.6                              # pushed into the rock: back toward the open
		dy *= 0.6
	st[S_DX] = dx
	st[S_DY] = dy
	var c := Vector2(p.x + dx, p.y + dy)
	# walking: the legs go by the ground really covered
	var cmx: float = c.x - float(st[S_FX])
	var cmy: float = c.y - float(st[S_FY])
	var moved: float = sqrt(cmx * cmx + cmy * cmy)
	st[S_FX] = c.x
	st[S_FY] = c.y
	var walking: bool = moved / max(_dt, 0.001) > 3.0
	if walking and moved < 90.0:
		st[S_GAIT] = float(st[S_GAIT]) + min(moved / max(2.0, TD_CYCLE * length), TD_STRIDE_CAP)
	var fr: int = TD_SEQ[int(fposmod(float(st[S_GAIT]), 1.0) * 4.0) % 4] if walking else 1
	var pose = _pose(a, st, p, walking, length) if poses else _NO_POSE
	var hurt: float = clamp(a.hurt / HURT_T, 0.0, 1.0)
	var ang: float = head + pose[1] * 0.6 + (0.0 if walking else 0.05 * sin(_t * 2.1 + a.id * 1.7))
	var pos: Vector2 = c + pose[0]
	var s: float = length / TD_BODY
	var sx: float = s * pose[2] * (1.0 + 0.12 * hurt)
	var sy: float = s * pose[3] * (1.0 - 0.14 * hurt)
	# colour: shade by depth, the strain's colour over the drab body, hurt flash, selection
	var shade = (lerp(1.0, BACK_SHADE, plane) if plane > 0.0 else 1.0) * (lerp(1.0, HIDDEN_SHADE, hidden) if hidden > 0.0 else 1.0)
	var alpha = (lerp(1.0, HIDDEN_ALPHA, hidden) if hidden > 0.0 else 1.0) * (0.55 if a.shelter_t > 0.0 else 1.0)
	var light = Color(shade, shade, shade, alpha)
	if hurt > 0.0:
		light *= Color.WHITE.lerp(HURT, hurt)
	if sel.has(a.id):
		light *= SELECTED
	var tint: Color = Color(st[S_TINT]) * _td_k
	st[S_SPOT_X] = pos.x
	st[S_SPOT_Y] = pos.y
	st[S_SPOT_R] = length * 0.5
	# turning over at the nest mouth: the top view squashes flat (on the screen's horizontal) as the ant goes out; _draw_ant opens the side view
	var fy: float = clamp(1.0 - sk * 2.0, 0.0, 1.0)
	if fy < 0.999:
		draw_set_transform_matrix(Transform2D(0.0, Vector2(1.0, max(fy, 0.02)), 0.0, pos) * Transform2D(ang, Vector2(sx, sy), 0.0, Vector2.ZERO))
	else:
		draw_set_transform(pos, ang, Vector2(sx, sy))
	var cw: float = _td_size.x + 2.0 * TD_GUTTER
	draw_texture_rect_region(_td_tex, Rect2(-TD_PIVOT, _td_size), Rect2(cw * fr + TD_GUTTER, TD_GUTTER, _td_size.x, _td_size.y), _pm(light * tint))
	if a.carry > 0.0 and not _foods.is_empty():
		var food = _foods[a.id % _foods.size()]
		var size: Vector2 = food["size"] * length / FOOD_REF
		var jaw: Vector2 = pos + (TD_JAW - TD_PIVOT).rotated(ang) * s
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_texture_rect(food["tex"], Rect2(jaw - size * 0.5, size), false, _pm(light))
	if debug_on:
		debug_frames[a.id] = [true, fr, walking, moved, a.tx != a.x or a.ty != a.y, st[S_GAIT], p.x, p.y, pos.x, pos.y, a.task, a.dig_timer > 0.0, a.t, ang, length, 0, sk, head]


func _new_state(a, p: Vector2, g) -> Array:
	var st := []
	st.resize(S_N)
	st.fill(0.0)
	var surf = 1.0 if g.is_surface_cell(a.tx, a.ty) else 0.0
	st[S_SURF] = surf
	st[S_LANE] = a.lane
	st[S_FACE] = float(a.facing)
	st[S_GAIT] = a.id * 0.37
	st[S_PX] = p.x
	st[S_PY] = p.y
	st[S_AX] = p.x
	st[S_AY] = p.y
	st[S_SX] = p.x
	st[S_SY] = p.y
	var down = Vector2(-sin(a.rot), cos(a.rot)) * C * 0.5
	st[S_OX] = down.x
	st[S_OY] = down.y
	st[S_ROT] = a.rot
	st[S_CARRY] = a.carry
	st[S_NEXT] = 2.0 + fmod(a.id * 1.37, 8.0)
	st[S_LOOK] = kit.request(a.genome, a.caste) if kit != null else null
	var wl = kit.world_len(a.genome, a.caste) if kit != null else -1.0
	if wl <= 0.0:
		wl = _length(a.ph.get("size", 74.0))
	st[S_WLEN] = wl * CASTE_SCALE[clampi(a.caste, 0, 2)]
	st[S_TINT] = _tint(a.genome)
	st[S_WINGS] = a.ph.get("wings", 0) > 0
	st[S_GKEY] = -1
	st[S_ROW] = a.id % 3
	st[S_HEAD] = 0.0 if a.facing > 0 else PI
	st[S_FX] = p.x + down.x
	st[S_FY] = p.y + down.y
	st[S_HASH] = fmod(a.id * 0.6180339887, 1.0)
	st[S_FIT] = 1.0
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
	var xl: int = x - g.ox
	if xl < 1 or xl >= w - 1 or y < 1 or y >= g.H - 1:
		return 16 if g.is_solid(x, y, z) else 0
	var s: PackedByteArray = g.solid
	var b: int = z * g.WH + y * w + xl
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


# From the centre of cell (cx, cy), how far along direction q (DIRS of them; DIRS = straight down, further) the drawn ground is, or
# NONE. Cached per cell for GROUND_LIFE.
func _ground_raw(cx: int, cy: int, z: int, q: int) -> float:
	var key = (((cx + 65536) * 4096 + cy) * 2 + z) * 32 + q
	var e = _gc.get(key)
	if e == null or _t - e.y > GROUND_LIFE:
		e = Vector2(_march((cx + 0.5) * C, (cy + 0.5) * C, _dir[q], z, (DROP if q == DIRS else REACH) * C), _t)
		_gc[key] = e
	return e.x


# The same from world point p (corrected from its cell's centre along the direction).
func _ground(p: Vector2, z: int, q: int) -> float:
	var cx = int(floor(p.x / C))
	var cy = int(floor(p.y / C))
	var r = _ground_raw(cx, cy, z, q)
	if r >= NONE:
		return NONE
	var d: Vector2 = _dir[q]
	return r - (p.x - (cx + 0.5) * C) * d.x - (p.y - (cy + 0.5) * C) * d.y


# Where an underground ant's feet are drawn (S_OX, S_OY: from its sim position) and its tilt (S_ROT): on the drawn ground below its
# feet along its body's down; in a passage narrower than the ant, its body in the middle of it (the legs reach into the walls rather
# than its back sticking through the far one); where there is no drawn ground (it stands on a crumb the soil view does not draw),
# upright on the floor below. `length`: its drawn body length. The answers for its cell are kept in its state.
func _place(a, p: Vector2, st: Array, length: float, z: int) -> void:
	st[S_DX] = 0.0
	st[S_DY] = 0.0
	var rot: float = a.rot
	var down = Vector2(-sin(rot), cos(rot))
	var q: int = posmod(int(round(atan2(down.y, down.x) * (DIRS / TAU))), DIRS)
	var cx = int(floor(p.x / C))
	var cy = int(floor(p.y / C))
	var key: int = (((cx + 65536) * 4096 + cy) * 2 + z) * 32 + q
	if key != int(st[S_GKEY]) or _t - float(st[S_GT]) > GROUND_LIFE:
		st[S_GKEY] = key
		st[S_GT] = _t
		st[S_GD] = _ground_raw(cx, cy, z, q)
		st[S_GD2] = _ground_raw(cx, cy, z, (q + DIRS / 2) % DIRS) if float(st[S_GD]) < NONE else NONE
		st[S_GDROP] = _ground_raw(cx, cy, z, DIRS) if float(st[S_GD]) >= NONE else NONE
	var ex = p.x - (cx + 0.5) * C
	var ey = p.y - (cy + 0.5) * C
	var dq: Vector2 = _dir[q]
	var off: Vector2
	var d: float = st[S_GD]
	var fit := 1.0
	if d < NONE:
		d -= ex * dq.x + ey * dq.y
		var d2: float = st[S_GD2]
		var hc = BODY_MID * length * float(st[S_FIT])
		if d2 < NONE:
			d2 += ex * dq.x + ey * dq.y
			# a passage thinner than the ant: it shrinks (down to FIT_MIN) and, if that is not enough, stands in the middle of it
			fit = clamp((d + d2) / max(1.0, 2.0 * BODY_MID * length * 1.04), FIT_MIN, 1.0)
			if d + d2 < 2.0 * hc:
				d = min((d - d2) * 0.5 + hc, d + SQUEEZE * C)
		off = down * d
	elif float(st[S_GDROP]) < NONE:
		off = Vector2(0.0, float(st[S_GDROP]) - ey)
		rot = 0.0
	else:
		off = down * C * 0.5
	var k = 1.0 - exp(-_dt * SNAP_RATE)
	st[S_OX] = lerp(float(st[S_OX]), off.x, k)
	st[S_OY] = lerp(float(st[S_OY]), off.y, k)
	st[S_FIT] = lerp(float(st[S_FIT]), fit, 1.0 - exp(-_dt * FIT_RATE))
	# the tilt turns toward the ground's, by how far it has walked (a corner is rounded over a few cells, never snapped), and not far
	# faster than that whatever the sim does (it swings a quarter turn in a quarter second)
	if rot == a.rot and (a.tx != a.x or a.ty != a.y):
		rot = a.trot
	var cur: float = st[S_ROT]
	var mv = sqrt((p.x - float(st[S_PX])) * (p.x - float(st[S_PX])) + (p.y - float(st[S_PY])) * (p.y - float(st[S_PY])))
	var lim = ROT_PX * min(mv, 4.0) + ROT_T * _dt
	st[S_ROT] = wrapf(cur + clamp(wrapf(rot - cur, -PI, PI) * (1.0 - exp(-_dt * ROT_EASE)), -lim, lim), -PI, PI)


# Ants close together underground (a 4 x 4 cell block, one tunnel plane) stand in three depth rows (their id picks the row; a lone ant
# is in none) and, within a row, spread out along the ground they stand on, one after another along their bodies' axis, as far as the
# drawn ground goes on without a big step. Their order is a hash of their id, so it does not change as the crowd moves.
func _spread(items: Array, far: float) -> void:
	var n = items.size()
	var k = 1.0 - exp(-_dt * SPREAD_RATE)
	var kc = 1.0 - exp(-_dt * CROWD_RATE)
	var goal: float = clamp((n - CROWD_FROM) / CROWD_SPAN, 0.0, 1.0)
	var rows := []
	if n > 1:
		rows = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
		for it in items:
			var s0: Array = it[2]
			rows[int(s0[S_ROW])].append(float(s0[S_HASH]))
		for r in rows:
			r.sort()
	for it in items:
		var a = it[0]
		var st: Array = it[2]
		st[S_CROWD] = lerp(float(st[S_CROWD]), goal, kc)
		var want = 0.0
		if n > 1:
			var rr: PackedFloat32Array = rows[int(st[S_ROW])]
			if rr.size() > 1:
				var gap = SPREAD_GAP * float(st[S_WLEN]) * far * float(st[S_FIT]) * lerp(1.0, ROW_SCALE[int(st[S_ROW])], float(st[S_CROWD]))
				want = clamp((rr.bsearch(float(st[S_HASH])) - (rr.size() - 1) * 0.5) * gap, -SPREAD_MAX * C, SPREAD_MAX * C)
		var cur = lerp(float(st[S_SPREAD]), want, k)
		st[S_SPREAD] = cur
		if abs(cur) < 0.3:
			continue
		var p: Vector2 = it[1]
		var rot: float = st[S_ROT]
		var down = Vector2(-sin(rot), cos(rot))
		var along = Vector2(cos(rot), sin(rot))
		var z: int = a.tz if a.t > 0.5 else a.z
		var q: int = posmod(int(round(atan2(down.y, down.x) * (DIRS / TAU))), DIRS)
		var base = _ground(p, z, q)
		if base >= NONE:
			continue
		# the furthest the ground carries it toward the spot it wants, in up to three tries
		var off = cur
		for tries in 3:
			var d = _ground(p + along * off, z, q)
			if d < NONE and abs(d - base) < SPREAD_STEP * C:
				st[S_DX] = along.x * off + down.x * (d - base)
				st[S_DY] = along.y * off + down.y * (d - base)
				break
			off *= 0.5
			if tries == 2:
				st[S_SPREAD] = lerp(cur, 0.0, 0.5)


# ------------------------------------------------------------------------------------------------ drawing an ant

func _draw_ant(a, p: Vector2, st: Array, far: float, poses: bool, sel: Dictionary, day_tint: Color, kf: int) -> void:
	var t: float = clamp(a.t, 0.0, 1.0)
	var plane: float = a.z + (a.tz - a.z) * t
	var hidden := 0.0
	if a.z == 1 or a.tz == 1:
		var g = colony.grid
		hidden = lerp(_behind(g, a.x, a.y, a.z), _behind(g, a.tx, a.ty, a.tz), t)
	var surf: float = st[S_SURF]
	var lane: float = st[S_LANE]
	var depth: float = (lerp(1.0, Band.persp(lane), surf) if surf > 0.0 else 1.0) * (lerp(1.0, BACK_SCALE, plane) if plane > 0.0 else 1.0)
	var length: float = float(st[S_WLEN]) * far * depth * (_pop(a.age) if a.age < 0.5 else 1.0) * float(st[S_FIT])
	var flipk := 1.0
	if _td_tex != null and surf < 1.0:
		length *= lerp(NEST_SCALE, 1.0, clamp(surf, 0.0, 1.0))        # coming out of the nest it grows to the size of the ants outside
		flipk = clamp((surf - 0.5) * 4.0, 0.02, 1.0)                  # ... turning over from the top view (see _draw_nest_ant)
	var cr: float = st[S_CROWD]
	var row: int = int(st[S_ROW])
	if cr > 0.001:
		length *= lerp(1.0, ROW_SCALE[row], cr)                      # in a crowd the back rows are smaller ...
	# where it stands: underground on the drawn ground (_place, _spread), on the surface in its lane
	var rot: float = a.rot
	var feet: Vector2
	if surf >= 1.0:
		feet = p + Vector2(-sin(rot), cos(rot)) * (C * 0.5)
	else:
		feet = p + Vector2(float(st[S_OX]) + float(st[S_DX]), float(st[S_OY]) + float(st[S_DY]))
		if cr > 0.001 and abs(float(st[S_ROT])) < 0.8:
			feet.y -= ROW_LIFT[row] * cr * length                    # ... and stand a little higher up the screen on a floor
		if surf > 0.0:
			feet = feet.lerp(p + Vector2(-sin(rot), cos(rot)) * (C * 0.5), surf)
		rot = lerp_angle(float(st[S_ROT]), rot, surf)
	if surf > 0.0:
		feet.y = lerp(feet.y, Band.lane_y(feet.y, lane), surf)
	# walking: the cycle advances by the ground really covered, so the feet stay planted
	var mx: float = p.x - float(st[S_PX])
	var my: float = p.y - float(st[S_PY])
	var moved = sqrt(mx * mx + my * my)
	st[S_PX] = p.x
	st[S_PY] = p.y
	var walking: bool = moved > 0.001
	var lk = st[S_LOOK]
	if lk != null:
		lk["used"] = kf
		if lk["tex"] == null:
			lk = null
	if walking and moved < 90.0:
		var cyc = (float(lk["cycle"]) if lk != null else 0.6) * length
		st[S_GAIT] = float(st[S_GAIT]) + min(moved / max(1.0, cyc), STRIDE_CAP)
	# flight: a winged ant crossing open ground takes off, and lands at the pile or the nest
	var air: float = st[S_AIR]
	if st[S_WINGS]:
		var fly = 1.0 if (surf > 0.5 and walking and a.curl_t <= 0.0) else 0.0
		if fly > 0.0 or air > 0.0:
			air = move_toward(air, fly, _dt * AIR_RATE * (1.0 if fly > 0.0 else 0.6))
			st[S_AIR] = air
			feet.y -= air * AIR_LIFT * depth * (1.0 + 0.15 * sin(_t * 3.0 + a.id))
	# pose: a transform about the feet (old ant_view._apply_pose)
	var pose = _pose(a, st, p, walking, length) if poses else _NO_POSE
	var pf: float = a.facing if not poses else pose[4]
	var tf = move_toward(float(st[S_FACE]), pf, _dt * TURN_RATE)
	st[S_FACE] = tf
	var face = tf if abs(tf) > TURN_MIN else (TURN_MIN if tf >= 0.0 else -TURN_MIN)
	rot += pose[1]
	if air > 0.0:
		rot -= air * 0.14 * sign(face)
	var bob = sin(_t * 16.0 + a.id) * (0.09 if a.carry > 0.0 else 0.06) if (poses and walking and air < 0.5) else 0.0
	var hurt: float = clamp(a.hurt / HURT_T, 0.0, 1.0)
	# colour: shade by depth and haze, the strain's colour over the drab kit, hurt flash, selection
	var shade = (lerp(1.0, BACK_SHADE, plane) if plane > 0.0 else 1.0) * (lerp(1.0, HIDDEN_SHADE, hidden) if hidden > 0.0 else 1.0)
	if cr > 0.001:
		shade *= lerp(1.0, ROW_SHADE[row], cr)
	var alpha = (lerp(1.0, HIDDEN_ALPHA, hidden) if hidden > 0.0 else 1.0) * (0.55 if a.shelter_t > 0.0 else 1.0)
	var light = Color(shade, shade, shade, alpha)
	if surf > 0.0:
		light *= Color.WHITE.lerp(HAZE.lerp(Color.WHITE, clamp(lane, 0.0, 1.0)) * day_tint, surf)
		if _lane_alpha.is_valid():
			light.a *= lerp(1.0, float(_lane_alpha.call(lane)), surf)
			if light.a <= 0.01:
				return
	if hurt > 0.0:
		light *= Color.WHITE.lerp(HURT, hurt)
	if sel.has(a.id):
		light *= SELECTED
	var tint: Color = st[S_TINT]
	# the spot it is drawn at (picking)
	var up = Vector2(sin(rot), -cos(rot))
	st[S_SPOT_X] = feet.x + up.x * length * 0.2
	st[S_SPOT_Y] = feet.y + up.y * length * 0.2
	st[S_SPOT_R] = length * 0.5
	var at: Vector2 = feet + pose[0]
	if lk != null:
		var s = length / float(lk["len"])
		var sx = face * s * pose[2] * (1.0 + 0.12 * hurt)
		var sy = s * pose[3] * (1.0 + bob - 0.14 * hurt) * flipk
		draw_set_transform(at, rot, Vector2(sx, sy))
		var cell: Vector2 = lk["cell"]
		var fr = int(fposmod(float(st[S_GAIT]), 1.0) * AntKit.FRAMES) % AntKit.FRAMES if (walking or air > 0.05) else AntKit.STAND
		var dst = Rect2(-lk["feet"], cell)
		if debug_on:
			debug_frames[a.id] = [true, fr, walking, moved, a.tx != a.x or a.ty != a.y, st[S_GAIT], p.x, p.y, st[S_SPOT_X], st[S_SPOT_Y], a.task, a.dig_timer > 0.0, a.t, rot, length, int(st[S_ROW]), st[S_SURF], st[S_ROT]]
		draw_texture_rect_region(lk["tex"], dst, Rect2(cell.x * fr, 0.0, cell.x, cell.y), _pm(light * tint))
		if lk["wings"]:
			var wc = _pm(light * Color.WHITE.lerp(tint, WING_TINT))
			if air > 0.05:
				# beating: the folded wings swing up and down about their root
				var beat = sin(_t * TAU * FLAP_HZ + a.id * 1.3)
				var root = Vector2(lk["mid"].x * 0.2, lk["mid"].y * 1.25)
				var ang = -air * (0.5 + 0.45 * beat)
				draw_set_transform_matrix(Transform2D(rot, Vector2(sx, sy), 0.0, at) * Transform2D(ang, root) * Transform2D(0.0, -root))
			draw_texture_rect_region(lk["tex"], dst, Rect2(cell.x * fr, cell.y, cell.x, cell.y), wc)
			if air > 0.05:
				draw_set_transform(at, rot, Vector2(sx, sy))
		if a.carry > 0.0 and not _foods.is_empty():
			var food = _foods[a.id % _foods.size()]
			var size: Vector2 = food["size"] * float(lk["len"]) / FOOD_REF
			draw_texture_rect(food["tex"], Rect2(lk["jaw"] - size * 0.5, size), false, _pm(light))
		return
	# not baked yet: the caste's whole-body picture
	var b = _bodies.get("alate_full" if st[S_WINGS] else CASTE_BODY[a.caste])
	if b == null:
		b = _bodies.get(CASTE_BODY[a.caste])
		if b == null:
			return
	if debug_on:
		debug_frames[a.id] = [false, -1, walking, moved, a.tx != a.x or a.ty != a.y, st[S_GAIT], p.x, p.y, st[S_SPOT_X], st[S_SPOT_Y], a.task, a.dig_timer > 0.0, a.t, rot, length, int(st[S_ROW]), st[S_SURF], st[S_ROT]]
	var s2 = length / b["length"]
	draw_set_transform(at, rot, Vector2(face * s2 * pose[2], s2 * pose[3] * (1.0 + bob) * flipk))
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
	var wl = kit.world_len(a.genome, a.caste) if kit != null else -1.0
	if wl <= 0.0:
		wl = _length(a.ph.get("size", 74.0))
	var length = wl * CASTE_SCALE[clampi(a.caste, 0, 2)] * clamp(sqrt(FAR_ZOOM / colony.zoom()), 1.0, FAR_MAX)
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
	if _q_egg_tex != null:
		draw_texture(_q_egg_tex, -b["feet"], _pm(Color.WHITE.lerp(HURT, hurt)))
