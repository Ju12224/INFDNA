extends Node2D
# Draws ants and raiders together, back-to-front. On the surface every unit
# walks in a depth lane: back lanes sit higher, smaller and darker (2.5D).
# Underground (cross-section) units are drawn flat.

const INK = Color("#15121a")
const ANT_SCALE = 0.24
const WorldView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/world_view.gd")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")
const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")

const CASTE_COLORS = [Color("#6cc644"), Color("#c9863b"), Color("#e8483b")]
const CASTE_ICONS = ["res://items/all/fruit_basket/fruit_basket_icon.png", "res://items/all/improved_tools/improved_tools_icon.png",
	"res://items/all/warrior_helmet/warrior_helmet_icon.png"]

var sim
var baker
var enemy_view
var ground
var perf             # perf.gd (optional): shadow and animation detail
var cam
var show_castes := true
var selected = null
var _caste_tex := []
var _t := 0.0
var _surf_k := {}   # smoothed surface factor per unit (0 underground, 1 surface)
var _back_k := {}   # smoothed tunnel-plane factor (0 front plane, 1 back plane)
var _air_k := {}    # smoothed flight factor of winged ants (0 on the ground, 1 airborne)
var _gait_ph := {}  # walk-cycle phase (cycles) per ant, advanced by the distance it really walked so the feet stay planted
var _last_pos := {}
var _leg_cache := {}
var _face_k := {}   # smoothed facing (-1..1): ants turn around instead of snapping
var _lane_d := {}   # the lane each unit is DRAWN in: smoothed, and pulled toward the nest hole / food pile it is at
var _near_piles := []
var _hid_k := {}    # 1 while a back-plane unit is behind front dirt (crossing under)
const BACK_SCALE = 0.8
const ENTRANCE_LANE = 0.62   # the nest mouth is drawn at this lane (world_view)
const PILE_LANE = 0.5        # so are the food piles
const CASTE_SCALE = [0.94, 1.0, 1.12]   # forager, digger, soldier
const BACK_SHADE = 0.5


var _glow_tex = null


func _ready() -> void:
	if ResourceLoader.exists("res://particles/sprites/particle_28.png"):
		_glow_tex = load("res://particles/sprites/particle_28.png")
	for p in CASTE_ICONS:
		_caste_tex.append(load(p) if ResourceLoader.exists(p) else null)


func _process(delta: float) -> void:
	_t += delta
	_dt = delta
	_prune_t -= delta
	if _prune_t <= 0.0:
		_prune_t = 10.0
		var alive := {}
		for a2 in sim.ants:
			alive[a2.id] = true
		for e2 in sim.enemies:
			alive[-e2.id] = true
		for dct in [_anim, _surf_k, _back_k, _hid_k, _air_k, _gait_ph, _last_pos, _face_k, _lane_d]:
			for kk in dct.keys():
				if not alive.has(kk):
					dct.erase(kk)
	var g = sim.grid
	var k = clamp(delta * 14.0, 0.0, 1.0)
	var vr0 = _view_rect()
	var C1 = g.CELL
	var kl = 1.0 - exp(-delta * 4.0)
	_near_piles = []
	for p in sim.piles:
		var px0 = (p["x"] + 0.5) * C1
		if px0 > vr0.position.x - 300.0 and px0 < vr0.end.x + 300.0:
			_near_piles.append(p["x"])
	for a in sim.ants:
		# ants far off screen (long expeditions) need no animation state; it catches up in a few frames on return
		var ax = (a.x + 0.5) * C1
		var ay = (a.y + 0.5) * C1
		if ax < vr0.position.x - 200.0 or ax > vr0.end.x + 200.0 or ay < vr0.position.y - 200.0 or ay > vr0.end.y + 200.0:
			continue
		var target = 1.0 if g.is_surface_cell(a.tx, a.ty) else 0.0
		_surf_k[a.id] = lerp(_surf_k.get(a.id, target), target, k)
		_track_plane(a.id, a, g, k)
		var goal = _lane_goal(a.x, a.lane, a.carry > 0.0 or a.task == 1)
		_lane_d[a.id] = lerp(_lane_d.get(a.id, goal), goal, kl)
		var p0 = sim.ant_pos(a)
		var moved = p0.distance_to(_last_pos.get(a.id, p0))
		_last_pos[a.id] = p0
		if moved > 0.01 and moved < 90.0:
			var dsc = lerp(1.0, GroundView.persp(lane_of(a, a.id)), _surf_k[a.id]) * lerp(1.0, BACK_SCALE, _back_k.get(a.id, 0.0)) * CASTE_SCALE[a.caste]
			# one cycle covers about 4 stance strokes of the legs; capped so very fast ants do not strobe
			_gait_ph[a.id] = _gait_ph.get(a.id, a.id * 0.37) + min(moved / (_leg_unit(a.genome) * dsc), 0.15)
		# winged ants take off to cross open ground and land again at the pile or the nest
		var fly = 1.0 if (a.ph.get("wings", 0) == 1 and target > 0.5 and (a.tx != a.x or a.ty != a.y) and a.curl_t <= 0.0) else 0.0
		if fly > 0.0 or _air_k.has(a.id):
			_air_k[a.id] = lerp(_air_k.get(a.id, 0.0), fly, clamp(delta * 3.5, 0.0, 1.0))
	for e in sim.enemies:
		var key = -e.id
		var target2 = 1.0 if g.is_surface_cell(e.tx, e.ty) else 0.0
		_surf_k[key] = lerp(_surf_k.get(key, target2), target2, k)
		_track_plane(key, e, g, k)
		_lane_d[key] = lerp(_lane_d.get(key, e.lane), _lane_goal(e.x, e.lane, false), kl)
	update()


# The lane a unit is drawn in: smoothed over time (so the sim's lane jitter never shows), and pulled onto the
# nest mouth's lane near an entrance and onto a pile's lane at the pile, so nobody reaches into the hole or the
# food from a different depth.
func lane_of(u, key: int) -> float:
	return _lane_d.get(key, u.lane)


func _lane_goal(x: int, lane: float, foraging: bool) -> float:
	var t = lane
	for en in sim.grid.entrances:
		var d = abs(x - int(en.x))
		if d < 30:
			t = lerp(t, ENTRANCE_LANE, 1.0 - d / 30.0)
	if foraging:
		for px in _near_piles:
			var d2 = abs(x - px)
			if d2 < 10:
				t = lerp(t, PILE_LANE, 1.0 - d2 / 10.0)
	return t


func _track_plane(key: int, u, g, k: float) -> void:
	var bz = 1.0 if u.tz == 1 else 0.0
	_back_k[key] = lerp(_back_k.get(key, bz), bz, k)
	var hid = 1.0 if (u.tz == 1 and g.is_solid(u.tx, u.ty, 0)) else 0.0
	_hid_k[key] = lerp(_hid_k.get(key, hid), hid, k)


func _depth(key: int, lane: float) -> Array:
	# returns [y_offset, scale_mult, shade]
	var f = _surf_k.get(key, 0.0)
	var bk = _back_k.get(key, 0.0)
	var hk = _hid_k.get(key, 0.0)
	var sc = lerp(1.0, GroundView.persp(lane), f) * lerp(1.0, BACK_SCALE, bk)
	var sh = lerp(1.0, 0.7 + 0.3 * lane, f) * lerp(1.0, BACK_SHADE, bk) * lerp(1.0, 0.7, hk)
	return [-(1.0 - lane) * GroundView.DEPTH * GroundView.LANE_K * f, sc, sh, 1.0 - 0.45 * hk]


const BUCKETS = 48


func _view_rect() -> Rect2:
	if cam == null:
		return Rect2(-1e9, -1e9, 2e9, 2e9)
	var half = get_viewport_rect().size * cam.zoom * 0.5
	var c = cam.get_camera_screen_center()
	var m = Vector2(360.0, 360.0)      # sprites and badges reach well past a unit's cell
	return Rect2(c - half - m, half * 2.0 + m * 2.0)


func _bucket(key: float) -> int:
	return int(clamp((key + 2.0) / 3.2 * BUCKETS, 0.0, BUCKETS - 1.0))


func _draw() -> void:
	# Units off screen are skipped (ants can now forage 500 cells away), and depth order uses
	# fixed buckets instead of a GDScript comparator sort every frame.
	var vr = _view_rect()
	var C0 = sim.grid.CELL
	var buckets := []
	for i in BUCKETS:
		buckets.append([])
	if ground != null:
		for sl in ground.visible_slices():
			var sk = 1.1 if sl == GroundView.SLICES else float(sl) / GroundView.SLICES
			buckets[_bucket(sk)].append([sk, 2, sl])
	for a in sim.ants:
		var px = (a.x + 0.5) * C0
		var py = (a.y + 0.5) * C0
		if px < vr.position.x or px > vr.end.x or py < vr.position.y or py > vr.end.y:
			continue
		var f = _surf_k.get(a.id, 0.0)
		var k = (-1.0 - _back_k.get(a.id, 0.0) if f < 0.5 else lane_of(a, a.id))
		buckets[_bucket(k)].append([k, 0, a])
	for e in sim.enemies:
		var ex = (e.x + 0.5) * C0
		var ey = (e.y + 0.5) * C0
		if ex < vr.position.x or ex > vr.end.x or ey < vr.position.y or ey > vr.end.y:
			continue
		var f2 = _surf_k.get(-e.id, 0.0)
		var k2 = (-1.0 - _back_k.get(-e.id, 0.0) if f2 < 0.5 else lane_of(e, -e.id)) + 0.001
		buckets[_bucket(k2)].append([k2, 1, e])
	var items := []
	for b in buckets:
		items.append_array(b)
	_foes = PoolVector2Array()
	for e3 in sim.enemies:
		if e3.state != 2:
			_foes.append(sim.enemy_pos(e3))
	_draw_shadows(items)
	for it in items:
		if it[1] == 0:
			_draw_ant(it[2])
		elif it[1] == 2:
			ground.draw_slice(self, it[2])
		elif enemy_view != null:
			var e = it[2]
			var d = _depth(-e.id, lane_of(e, -e.id))
			var feet = sim.enemy_pos(e) + Vector2(0, sim.grid.CELL * 0.5 + d[0])
			var fa = _surf_k.get(-e.id, 0.0) if e.def.get("fly", false) else 0.0
			enemy_view.draw_enemy(self, e, feet, d[1], d[2], d[3], fa)
	_draw_corpses(vr)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var badges_visible = cam == null or cam.zoom.x < 1.08      # they fade out beyond this zoom (see _draw_caste_badge)
	for it in items:
		if it[1] == 0 and show_castes and (badges_visible or it[2] == selected):
			_draw_caste_badge(it[2])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Ground slope (radians) at a world x, from the cached ground heights.
func _slope(wx: float) -> float:
	if ground == null:
		return 0.0
	var C = sim.grid.CELL
	var c = int(floor(wx / C))
	return atan2(ground.smooth_px(c + 2) - ground.smooth_px(c - 2), 4.0 * C)


# Soft shadows for everything standing on the surface, all drawn before any unit so a shadow never
# covers another ant. The sun is up and to the right, so shadows lean left; they tilt with the slope.
func _draw_shadows(items: Array) -> void:
	var q = perf.shadows if perf != null else 2
	if q == 0:
		return
	var C = sim.grid.CELL
	var tiny = cam != null and cam.zoom.x > 2.0
	for it in items:
		if it[1] == 2:
			continue
		var u = it[2]
		var key = u.id if it[1] == 0 else -u.id
		var sk = _surf_k.get(key, 0.0)
		if sk < 0.35:
			continue
		if it[1] == 0 and tiny:
			continue
		var d = _depth(key, lane_of(u, key))
		var pos: Vector2
		var rx: float
		var air := 0.0
		if it[1] == 0:
			pos = sim.ant_pos(u) + Vector2(0, C * 0.5 + d[0])
			rx = (13.0 + u.ph["size"] * 0.14) * d[1] * CASTE_SCALE[u.caste]
			air = _air(u)
		else:
			pos = sim.enemy_pos(u) + Vector2(0, C * 0.5 + d[0])
			rx = EnemyDefs.HEIGHT[u.cls] * 0.36 * d[1]
			air = sk if u.def.get("fly", false) else 0.0
		var a = sk * d[3] * (1.0 - 0.5 * air)
		if q == 1:
			draw_set_transform(pos + Vector2(-rx * 0.3 - air * 14.0, 0), 0.0, Vector2(1.0, 0.3))
			draw_circle(Vector2.ZERO, rx, Color(0.05, 0.1, 0.03, 0.2 * a))
			continue
		draw_set_transform(pos + Vector2(-rx * 0.3 - air * 14.0, 0), _slope(pos.x), Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, rx * 1.15 * (1.0 + 0.2 * air), Color(0.05, 0.1, 0.03, 0.09 * a))
		draw_circle(Vector2.ZERO, rx * 0.85, Color(0.05, 0.1, 0.03, 0.12 * a))
		draw_circle(Vector2(rx * 0.1, 0), rx * 0.5, Color(0.05, 0.1, 0.03, 0.15 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Height above the ground of a flying (winged) ant, 0..1; 0 for everyone else.
func _air(a) -> float:
	return _air_k.get(a.id, 0.0)


# The ant under a click, judged by where it is DRAWN (lanes lift ants off their sim position).
func pick(world_pos: Vector2, radius: float = 30.0):
	var best = null
	var bd = 1e18
	var C = sim.grid.CELL
	for a in sim.ants:
		var d = _depth(a.id, lane_of(a, a.id))
		var n = Vector2(-sin(a.rot), cos(a.rot))
		var mid = sim.ant_pos(a) + Vector2(0, d[0]) + n * C * 0.5 - n * 15.0 * d[1]
		var q = mid.distance_squared_to(world_pos)
		var r = radius * max(d[1], 0.75)
		if q < r * r and q < bd:
			bd = q
			best = a
	return best


# Caste badge above the ant: coloured disc + icon (forager basket, digger tool,
# soldier helm). Sized against camera zoom so it stays readable when zoomed out.
func _draw_caste_badge(a) -> void:
	var C = sim.grid.CELL
	var d = _depth(a.id, lane_of(a, a.id))
	var pos = sim.ant_pos(a) + Vector2(0, d[0])
	var z = cam.zoom.x if cam != null else 1.0
	# badges fade out when zoomed out, where they would cover the colony
	var fade = (1.0 - smoothstep(0.75, 1.05, z)) * (1.0 - 0.6 * _back_k.get(a.id, 0.0))
	if fade <= 0.02 and a != selected:
		return
	if a == selected:
		fade = 1.0
	var r = clamp(5.5 * z, 4.5, 11.0) * (0.85 + 0.15 * d[1]) * _pop(a.age)
	var top = pos + Vector2(0, C * 0.5 - 30.0 * d[1] - r * 0.6)
	var col: Color = CASTE_COLORS[a.caste]
	if sim.fx_caste_pulse(a):
		col = col.lightened(0.35)
		r *= 1.15
	draw_circle(top, r + 2.2, Color(INK.r, INK.g, INK.b, fade))
	draw_circle(top, r, Color(col.r, col.g, col.b, fade))
	var tex = _caste_tex[a.caste]
	if tex != null:
		var sz = r * 1.55
		draw_texture_rect(tex, Rect2(top - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, fade))
	if a == selected:
		draw_arc(top, r + 4.0, 0.0, TAU, 24, Color.white, 2.0, true)


# Dirt pellet held in the mandibles while hauling spoil to the mound.
func _draw_clod(p: Vector2, seed_id: int, amount: float, m: Color) -> void:
	var r = 20.0 + 6.0 * clamp(amount, 0.0, 2.0)
	var base = Color(0.42, 0.29, 0.18)
	var pts := PoolVector2Array()
	for i in 9:
		var ang = TAU * i / 9.0
		var j = 0.82 + 0.18 * fmod(abs(sin(seed_id * 12.9898 + i * 78.233)) * 43758.5453, 1.0)
		pts.append(p + Vector2(cos(ang), sin(ang) * 0.85) * r * j)
	draw_colored_polygon(pts, Color(INK.r, INK.g, INK.b, m.a))
	var inner := PoolVector2Array()
	for q in pts:
		inner.append(p + (q - p) * 0.8)
	draw_colored_polygon(inner, Color(base.r * m.r, base.g * m.g, base.b * m.b, m.a))
	draw_circle(p + Vector2(-r * 0.25, -r * 0.3), r * 0.22, Color(0.62 * m.r, 0.47 * m.g, 0.33 * m.b, m.a))
	draw_circle(p + Vector2(r * 0.3, r * 0.15), r * 0.12, Color(0.3 * m.r, 0.2 * m.g, 0.12 * m.b, m.a))


# ---------------------------------------------------------------- procedural poses (v0.22)
# Whole-body animation layered on the baked walk cycle, all as a transform around the feet so
# every body plan gets it with no re-baking: fight lunges facing the raider, rear-up threat
# display, digging jackhammer, nursing rock, grooming, a grab-nod on pickup and a hop on
# delivery, flinching near raiders, hatch wobble, hurt stagger.
var _p_off := Vector2.ZERO
var _p_rot := 0.0
var _p_sx := 1.0
var _p_sy := 1.0
var _p_face := 1
var _dt := 0.016
var _anim := {}
var _foes := PoolVector2Array()
var _foe_pos := Vector2.ZERO
var _prune_t := 8.0


func _nearest_foe(p: Vector2) -> float:
	var best = 1e18
	var bp = p
	for fp in _foes:
		var d2 = (fp - p).length_squared()
		if d2 < best:
			best = d2
			bp = fp
	_foe_pos = bp
	return best


func _apply_pose(a, raw: Vector2, moving: bool) -> void:
	_p_off = Vector2.ZERO
	_p_rot = 0.0
	_p_sx = 1.0
	_p_sy = 1.0
	_p_face = a.facing
	var an = _anim.get(a.id)
	if an == null:
		an = {"carry": a.carry, "hop": 0.0, "grab": 0.0, "groom": 0.0, "next": rand_range(2.0, 10.0)}
		_anim[a.id] = an
	if a.carry > 0.0 and an["carry"] <= 0.0:
		an["grab"] = 0.4
	elif a.carry <= 0.0 and an["carry"] > 0.0:
		an["hop"] = 0.5
	an["carry"] = a.carry
	var fwd = Vector2(cos(a.rot), sin(a.rot)) * a.facing
	var foe_d2 = 1e18
	if not _foes.empty() and (a.task == 4 or a.task == 1 or a.hurt > 0.0):
		foe_d2 = _nearest_foe(raw)
	if foe_d2 < 900.0 and (a.task == 4 or a.hurt > 0.0):
		# fighting: turn to the raider and lunge at it
		_p_face = 1 if _foe_pos.x >= raw.x else -1
		fwd = Vector2(cos(a.rot), sin(a.rot)) * _p_face
		var lunge = max(0.0, sin(_t * 13.0 + a.id * 1.9))
		lunge *= lunge
		_p_off += fwd * (6.0 * lunge)
		_p_rot += _p_face * (0.24 * lunge - 0.04)
		_p_sy *= 1.0 - 0.07 * lunge
	elif a.dig_timer > 0.0:
		# digging: jackhammer against the wall it is facing
		if a.dig_cell.x != a.x:
			_p_face = 1 if a.dig_cell.x > a.x else -1
			fwd = Vector2(cos(a.rot), sin(a.rot)) * _p_face
		var jh = sin(_t * 34.0 + a.id)
		_p_off += fwd * (2.2 * jh)
		_p_off.y += 0.8 * sin(_t * 61.0)
		_p_rot += _p_face * (0.12 + 0.03 * jh)
	elif a.task == 4 and not moving:
		# holding the line with nothing in reach: rear up and show off
		_p_rot -= a.facing * (0.28 + 0.06 * sin(_t * 3.0 + a.id))
	elif a.task == 1 and foe_d2 < 2304.0:
		# a forager near a raider flinches and shivers
		_p_off.x += sin(_t * 50.0 + a.id)
		_p_rot -= a.facing * 0.1
	elif a.task == 0 and not moving:
		# nursing: rocking over the brood
		_p_rot += 0.1 * sin(_t * 3.1 + a.id * 1.7)
		_p_sy *= 1.0 + 0.03 * sin(_t * 6.2 + a.id)
	elif not moving:
		# idle: breathing, and now and then a quick groom
		an["next"] -= _dt
		if an["groom"] > 0.0:
			an["groom"] = max(0.0, an["groom"] - _dt)
			var dip = sin((1.0 - an["groom"] / 1.1) * PI)
			_p_rot += a.facing * 0.3 * dip + 0.05 * sin(_t * 30.0) * dip
			_p_off.y += 1.5 * dip
		elif an["next"] <= 0.0:
			an["groom"] = 1.1
			an["next"] = rand_range(6.0, 15.0)
		_p_sy *= 1.0 + 0.022 * sin(_t * 2.4 + a.id)
		_p_sx *= 1.0 - 0.01 * sin(_t * 2.4 + a.id)
	# overlays that stack on any pose
	if an["grab"] > 0.0:
		an["grab"] = max(0.0, an["grab"] - _dt)
		var nod = abs(sin((1.0 - an["grab"] / 0.4) * TAU))     # two quick nods at the pile
		_p_rot += a.facing * 0.34 * nod
		_p_off.y += 1.5 * nod
	if an["hop"] > 0.0:
		an["hop"] = max(0.0, an["hop"] - _dt)
		var hk = 1.0 - an["hop"] / 0.5
		var hh = sin(hk * PI)
		_p_off.y -= 9.0 * hh                                   # a hop of joy on delivery
		_p_sy *= 1.0 + 0.1 * hh - (0.08 if hk > 0.88 else 0.0)
	if a.hurt > 0.0:
		var hu = clamp(a.hurt / 0.12, 0.0, 1.0)
		_p_off -= fwd * (3.0 * hu)
		_p_off.x += sin(_t * 70.0 + a.id) * 1.2 * hu
	if a.age < 0.5:
		_p_rot += 0.3 * (1.0 - a.age / 0.5) * sin(a.age * 40.0)   # wobbly first steps
	if a.carry > 0.0 and moving:
		_p_rot += a.facing * 0.07                               # leaning into the load


# World px of ground covered by one walk cycle at scale 1, from this body plan's leg length (matches the
# painter's stride: half-stride = 0.46 L, a cycle is four stance strokes).
func _leg_unit(g) -> float:
	var u = _leg_cache.get(g.uid)
	if u != null:
		return u
	var sum := 0.0
	var n := 0
	var total := 25.0
	for sg in g.segments:
		total += 2.4 * float(sg["r"])
		if sg["limb"] == "leg" and sg["n"] > 0:
			sum += float(sg["len"])
			n += 1
	var L = (sum / n if n > 0 else 55.0) * (1.3 if g.form("leg") == 4 else 1.0)
	var k0 = min(1.0, 310.0 / (total + 120.0)) * 0.55
	u = clamp(1.84 * L * k0 * ANT_SCALE, 5.0, 40.0)
	if _leg_cache.size() > 500:
		_leg_cache.clear()
	_leg_cache[g.uid] = u
	return u


# Beating wings of an airborne alate, in sprite pixels (the ant's own folded wings stay under them).
func _draw_flap(air: float, al: float, id: int) -> void:
	var root = Vector2(6.0, -46.0)
	var beat = sin(_t * 44.0 + id * 1.3)
	for w in 2:
		var ang = lerp(-2.55 + w * 0.5, -1.35 + w * 0.45, 0.5 + 0.5 * beat)
		var ln = 98.0 - w * 18.0
		var tip = root + Vector2(cos(ang), sin(ang)) * ln
		var mid = (root + tip) * 0.5
		var nrm = Vector2(-sin(ang), cos(ang))
		var pts := PoolVector2Array()
		for q in 14:
			var t2 = TAU * q / 14.0
			pts.append(mid + Vector2(cos(ang), sin(ang)) * cos(t2) * ln * 0.5 + nrm * sin(t2) * (13.0 - w * 3.0))
		draw_colored_polygon(pts, Color(0.88, 0.94, 1.0, 0.42 * air * al))
		pts.append(pts[0])
		draw_polyline(pts, Color(INK.r, INK.g, INK.b, 0.55 * air * al), 3.0, true)


# A fallen ant: knocked up, tips over and fades. Old-age deaths just curl and settle.
func _draw_corpses(vr: Rect2) -> void:
	for f in sim.fx:
		if f["kind"] != "corpse":
			continue
		var fp: Vector2 = f["pos"]
		if fp.x < vr.position.x or fp.x > vr.end.x or fp.y < vr.position.y or fp.y > vr.end.y:
			continue
		var tex = baker.get_texture(f["genome"], 1.0, 0)
		if tex == null:
			continue
		var k = clamp(f["t"] / 0.9, 0.0, 1.0)
		var d = _depth(f["id"], f["lane"])
		var old = f.get("old", false)
		var face = f["face"]
		var s = ANT_SCALE * d[1] * CASTE_SCALE[f["caste"]]
		var rise = 0.0 if old else sin(min(1.0, k * 2.2) * PI) * 10.0
		var tip = (0.35 if old else 1.6) * k * k * face
		var sag = (1.0 - 0.3 * k) if old else 1.0
		var shade = d[2] * (0.85 - 0.25 * k)
		var al = (1.0 - k * k) * d[3]
		draw_set_transform(fp + Vector2(0, d[0] - rise + k * k * (3.0 if old else 8.0)), f["rot"] + tip, Vector2(face * s, s * sag))
		draw_texture_rect(tex, Rect2(-baker.FEET, baker.SIZE), false, Color(shade, shade, shade, al))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# easeOutBack: newborn ants pop out of the egg
func _pop(age: float) -> float:
	if age >= 0.5:
		return 1.0
	var k = age / 0.5
	return max(0.05, 1.0 + 2.70158 * pow(k - 1.0, 3.0) + 1.70158 * pow(k - 1.0, 2.0))


func _by_depth(a, b) -> bool:
	return a[0] < b[0]


func _draw_ant(a) -> void:
	var C = sim.grid.CELL
	var d = _depth(a.id, lane_of(a, a.id))
	var raw = sim.ant_pos(a)
	var pos = raw + Vector2(0, d[0])
	var n = Vector2(-sin(a.rot), cos(a.rot))
	var feet = pos + n * C * 0.5
	var air = _air(a)
	if air > 0.01:
		feet += Vector2(0, -air * (30.0 + 5.0 * sin(_t * 3.0 + a.id)) * d[1])      # hover; the shadow stays on the ground
	var moving = a.tx != a.x or a.ty != a.y
	var detail = perf.ants if perf != null else 2
	if detail == 0 or (cam != null and cam.zoom.x > 1.7):
		_p_off = Vector2.ZERO          # too small to see, or the machine is struggling: skip the pose animation
		_p_rot = 0.0
		_p_sx = 1.0
		_p_sy = 1.0
		_p_face = a.facing
	else:
		_apply_pose(a, raw, moving)
	if air > 0.01:
		_p_rot -= air * 0.14 * a.facing                                              # nose up, wings beating
	var bob = sin(_t * 16.0 + a.id) * (0.09 if a.carry > 0.0 else 0.06) if moving else 0.0   # laden ants strain
	# caste reads at a glance even with badges faded: soldiers bulk up, foragers run lean
	var s = ANT_SCALE * d[1] * _pop(a.age) * CASTE_SCALE[a.caste]   # caste is fixed at birth
	var shade = d[2]
	var hurt = clamp(a.hurt / 0.12, 0.0, 1.0)
	if a == selected:
		var pr = 26.0 + sin(_t * 6.0) * 2.5
		draw_circle(feet - n * 10.0, pr, Color(1, 1, 1, 0.18))
		draw_arc(feet - n * 10.0, pr, _t * 1.5, _t * 1.5 + TAU * 0.8, 28, Color.white, 3.0, true)
	var frame = int(fposmod(_gait_ph.get(a.id, 0.0), 1.0) * baker.FRAMES) % baker.FRAMES if moving else 0
	var tex = baker.get_texture(a.genome, 1.0, frame)
	var sk = _surf_k.get(a.id, 0.0)
	if moving and sk > 0.5 and detail >= 2:
		# little dust kicked up behind a running ant
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var back = Vector2(cos(a.rot), sin(a.rot)) * a.facing
		for j in 2:
			var dph = fmod(_t * 3.5 + a.id * 0.37 + j * 0.5, 1.0)
			var dp = feet - back * (8.0 + dph * 16.0) + Vector2(0, -1.0 - dph * 5.0)
			draw_circle(dp, (2.0 + dph * 3.0) * d[1], Color(0.62, 0.52, 0.38, (1.0 - dph) * 0.22 * sk))
	var fk = _face_k.get(a.id, float(_p_face))
	fk = move_toward(fk, float(_p_face), _dt * 9.0)
	_face_k[a.id] = fk
	var fk_draw = fk if abs(fk) > 0.35 else (0.35 if fk >= 0.0 else -0.35)     # a quick squash-turn, never a vanished sprite
	draw_set_transform(feet + _p_off, a.rot + _p_rot, Vector2(fk_draw * s * _p_sx * (1.0 + 0.12 * hurt), s * _p_sy * (1.0 + bob - 0.14 * hurt)))
	var alpha = d[3]
	var tint = Color(shade, shade, shade, alpha)
	if hurt > 0.0:
		tint = Color(shade, shade * (1.0 - 0.6 * hurt), shade * (1.0 - 0.6 * hurt), alpha)
	if tex == null:
		# not baked yet (first frame of a new body plan): founder shape in this ant's color
		tex = baker.get_texture(sim.founder_genome, 1.0, frame)
		var c = a.genome.color.lightened(0.35)
		tint = Color(c.r * shade, c.g * shade, c.b * shade, alpha)
	if _glow_tex != null and "morph" in a.genome and int(a.genome.m("glow")) == 1:
		var gl = 0.3 + 0.12 * sin(_t * 3.0 + a.id)
		draw_texture_rect(_glow_tex, Rect2(Vector2(-130, -170), Vector2(260, 200)), false, Color(0.55, 1.0, 0.5, gl * alpha))
	if a.curl_t > 0.0:
		# armadillo roll: the ant is a banded ball until it uncurls
		var bc = Color("#b8976a")
		var rr = 52.0
		var spin = _t * 2.0 * a.facing
		draw_circle(Vector2(0, -rr), rr + 8.0, INK)
		draw_circle(Vector2(0, -rr), rr, Color(bc.r * shade, bc.g * shade, bc.b * shade, alpha))
		for j in 4:
			var an = spin + j * PI / 4.0
			draw_line(Vector2(0, -rr) + Vector2(cos(an), sin(an)) * rr, Vector2(0, -rr) - Vector2(cos(an), sin(an)) * rr, Color(0.35, 0.26, 0.16, alpha), 5.0, true)
		draw_circle(Vector2(-rr * 0.35, -rr * 1.4), rr * 0.18, Color(1, 1, 1, 0.5 * alpha))
		if a.ph.get("curl_heal", 0.0) > 0.0:
			draw_arc(Vector2(0, -rr), rr + 14.0, 0.0, TAU, 32, Color(0.55, 1.0, 0.6, 0.6 * alpha), 4.0, true)
	elif tex != null:
		draw_texture_rect(tex, Rect2(-baker.FEET, baker.SIZE), false, tint)
	if air > 0.05:
		_draw_flap(air, alpha * shade, a.id)
	var gm = Color(shade, shade, shade, alpha)
	if a.carry > 0.0:
		WorldView.draw_gem(self, Vector2(72, -26), 2.0, a.id % 5, gm)   # held in the mandibles
	elif a.spoil > 0.0:
		_draw_clod(Vector2(76, -18), a.id, a.spoil, gm)
	if a.dig_timer > 0.0:
		# crumbs flung off the mandibles in arcs
		for j in 5:
			var ph2 = fmod(_t * 2.6 + j * 0.2 + a.id * 0.11, 1.0)
			var pp = Vector2(86.0 + (-40.0 + 28.0 * j) * ph2 * 0.8, -14.0 - 70.0 * ph2 + 120.0 * ph2 * ph2)
			draw_circle(pp, 9.0 * (1.0 - ph2 * 0.5), Color(0.5 + 0.03 * j, 0.36, 0.22, 0.9 * (1.0 - ph2)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
