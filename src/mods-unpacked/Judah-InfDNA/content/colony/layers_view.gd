extends Node2D
# Optional view layers, drawn above the ants and raiders so a crowded fight can be read at a glance.
#   fights - a thin ground ring under each raider (colour = class, a soft pulse while it is fighting), a
#            mini health bar on each wounded ant that is fighting or just got hit, and edge arrows
#            toward raiders that are off screen. Deliberately light: nothing is drawn between the
#            bodies, so the fight itself stays readable
#   tasks  - a coloured halo on every ant for what it is doing right now (nurse/forage/dig/home/defend)
#   health - a health bar over every ant
# Sizes that must stay readable are measured in screen pixels (x camera zoom), so they hold when
# zoomed out. Purely visual: nothing here changes the sim.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")
const EnemyDefs = preload("res://mods-unpacked/Judah-InfDNA/core/enemy_defs.gd")

const INK = Color("#15121a")
# task order in the sim: NURSE, FORAGE, DIG, HOME, DEFEND
const TASK_COLORS = [Color("#5aa9e6"), Color("#7ed957"), Color("#c9863b"), Color("#8a8a9a"), Color("#e8483b")]
const TASK_LABELS = ["Nursing", "Foraging", "Digging", "Returning", "Defending"]
const CLASS_COLORS = {"small": Color("#ffb347"), "burrower": Color("#ff7a4a"), "brute": Color("#ff5a4a"),
	"elite": Color("#e05cff"), "boss": Color("#ff2e63"), "prey": Color("#9fe3a8")}
const CLASS_RANK = {"prey": 0, "small": 1, "burrower": 2, "brute": 3, "elite": 4, "boss": 5}
const MAX_LINKS = 8          # links drawn per raider; a swarm on a boss is one blob anyway
const ARROW_BUCKET = 90.0    # off-screen raiders closer than this (screen px) share one arrow
const PAIR_BUCKET = 8.0      # columns per bucket when matching ants to the raiders in view (_rebuild_pairs)

var sim
var cam
var ant_view
var pair_every := 0.08       # who-hits-whom is rebuilt this often, not every frame (perf.gd slows it on weak machines)
var show_fights := true
var show_tasks := false
var show_health := false
var _t := 0.0
var _pair_t := 0.0
var _pairs := []             # [ant, raider]
var _fighting := {}          # ant id -> true while it has a raider in reach
var _font: DynamicFont


func _ready() -> void:
	_font = Kit.font(20, 3)


func set_layer(key: String, on: bool) -> void:
	match key:
		"fights":
			show_fights = on
			_pairs = []
			_fighting = {}
			_pair_t = 0.0
		"tasks":
			show_tasks = on
		"health":
			show_health = on
	update()


func _process(delta: float) -> void:
	_t += delta
	if not (show_fights or show_tasks or show_health):
		return
	if show_fights:
		_pair_t -= delta
		if _pair_t <= 0.0:
			_pair_t = pair_every
			_rebuild_pairs()
	update()


func _zoom() -> float:
	return cam.zoom.x if cam != null else 1.0


# Which ant is hitting which raider: the same reach rule colony_sim._combat uses.
func _rebuild_pairs() -> void:
	_pairs = []
	_fighting = {}
	if sim.enemies.empty():
		return
	var vr = ant_view._view_rect()
	var C = sim.grid.CELL
	# the raiders in view first: with none of them there (the usual case) no ant needs looking at
	var foes := []
	for e in sim.enemies:
		if e.state == 2:
			continue
		var ep = sim.enemy_pos(e)
		if ep.x < vr.position.x or ep.x > vr.end.x or ep.y < vr.position.y or ep.y > vr.end.y:
			continue
		foes.append([e, ep])
	if foes.empty():
		return
	# the ants bucketed once by the column they start from (the meadow's critters make a dozen "raiders" in view at a time, and
	# each used to walk the whole colony); a raider then looks only at the buckets within reach, in the colony's own order
	var ants = sim.ants
	var max_k2 := 1.0
	var span := 0
	var buckets := {}
	for i in ants.size():
		var a = ants[i]
		max_k2 = max(max_k2, a.ph.get("reach2", 1.0))
		var lo = a.x
		var hi = a.tx
		if hi < lo:
			lo = a.tx
			hi = a.x
		span = max(span, hi - lo)
		var bk = int(floor(lo / PAIR_BUCKET))
		if buckets.has(bk):
			buckets[bk].append(i)
		else:
			buckets[bk] = [i]
	for fe in foes:
		var e = fe[0]
		var ep: Vector2 = fe[1]
		var ar = EnemyDefs.REACH[e.cls] * C * sim._r_reach
		var ar2 = ar * ar
		var far = ar * sqrt(max_k2) + 0.01
		# an ant is drawn between the centres of its cell and its next cell: rule out the far ones from the cells alone
		var cx0 = (ep.x - far) / C - 1.0
		var cx1 = (ep.x + far) / C
		var near := []
		for bk in range(int(floor((cx0 - span) / PAIR_BUCKET)), int(floor(cx1 / PAIR_BUCKET)) + 1):
			if buckets.has(bk):
				near += buckets[bk]
		near.sort()
		var ez = e.z
		var links := 0
		for ai in near:
			var a2 = ants[ai]
			if a2.z != ez:
				continue          # a wall of dirt between them
			if (a2.x < cx0 and a2.tx < cx0) or (a2.x > cx1 and a2.tx > cx1):
				continue
			var p = sim.ant_pos(a2)
			if abs(p.x - ep.x) > far:
				continue
			if p.distance_squared_to(ep) <= ar2 * a2.ph.get("reach2", 1.0):
				_fighting[a2.id] = true
				if links < MAX_LINKS:
					_pairs.append([a2, e])
					links += 1


# [feet, body centre, bar anchor, depth scale, alpha] of an ant, matching ant_view's placement
func _ant_pts(a) -> Array:
	var C = sim.grid.CELL
	var d = ant_view._depth(a.id, ant_view.lane_of(a, a.id))
	var pos = sim.ant_pos(a) + Vector2(0, d[0])
	var n = Vector2(-sin(a.rot), cos(a.rot))
	var feet = pos + n * C * 0.5
	return [feet, feet - n * 15.0 * d[1], Vector2(feet.x, feet.y - 44.0 * d[1]), d[1], d[3]]


func _raider_pts(e) -> Array:
	var C = sim.grid.CELL
	var d = ant_view._depth(-e.id, ant_view.lane_of(e, -e.id))
	var h = EnemyDefs.height_of(e) * d[1]
	var feet = sim.enemy_pos(e) + Vector2(0, C * 0.5 + d[0])
	return [feet, feet - Vector2(0, h * 0.45), h, d[3]]


func _draw() -> void:
	if not (show_fights or show_tasks or show_health):
		return
	var z = _zoom()
	var vr = ant_view._view_rect()
	if show_fights:
		for e in sim.enemies:
			_draw_ring(e, z, vr)
	if show_tasks or show_health or show_fights:
		_draw_ant_marks(z, vr)
	if show_fights:
		_draw_edge_arrows()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ring(e, z: float, vr: Rect2) -> void:
	var ep = sim.enemy_pos(e)
	if ep.x < vr.position.x or ep.x > vr.end.x or ep.y < vr.position.y or ep.y > vr.end.y:
		return
	var pts = _raider_pts(e)
	var col: Color = CLASS_COLORS.get(e.cls, Color.white)
	var dead = e.state == 2
	var quiet = not e.engaged and CLASS_RANK.get(e.cls, 1) < 3      # a small raider just wandering: faint ring only
	var fade = (0.25 if dead else 1.0) * pts[3]
	var pulse = 0.5 + 0.5 * sin(_t * 7.0 + e.id)
	var rad = max(pts[2] * 0.42, 13.0 * z)
	draw_set_transform(pts[0], 0.0, Vector2(1.0, 0.3))
	if e.engaged and not dead:
		draw_circle(Vector2.ZERO, rad, Color(col.r, col.g, col.b, (0.06 + 0.07 * pulse) * fade))
		draw_arc(Vector2.ZERO, rad * (1.0 + 0.22 * pulse), 0.0, TAU, 36, Color(col.r, col.g, col.b, (1.0 - pulse) * 0.45 * fade), 2.0 * z, true)
	draw_arc(Vector2.ZERO, rad, 0.0, TAU, 36, Color(INK.r, INK.g, INK.b, (0.28 if quiet else 0.4) * fade), 5.0 * z, true)
	draw_arc(Vector2.ZERO, rad, 0.0, TAU, 36, Color(col.r, col.g, col.b, (0.5 if quiet else 0.85) * fade), 2.2 * z, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Halos (tasks) and health bars, one pass over the ants that are on screen.
func _draw_ant_marks(z: float, vr: Rect2) -> void:
	var C = sim.grid.CELL
	var fights_only = not show_tasks and not show_health
	for a in sim.ants:
		# with only the fight marks on, an ant gets one just after a hit or while it has a raider in reach
		if fights_only and a.hurt <= 0.0 and not _fighting.has(a.id):
			continue
		var px = (a.x + 0.5) * C
		var py = (a.y + 0.5) * C
		if px < vr.position.x or px > vr.end.x or py < vr.position.y or py > vr.end.y:
			continue
		var max_hp = a.ph["hp"]
		var wounded = a.hp < max_hp * 0.999
		var bar = show_health or (show_fights and a.hurt > 0.0) or (show_fights and wounded and a.hp < max_hp * 0.85 and _fighting.has(a.id))
		if not show_tasks and not bar:
			continue
		var pts = _ant_pts(a)
		if show_tasks:
			var col: Color = TASK_COLORS[int(clamp(a.task, 0, TASK_COLORS.size() - 1))]
			var r = max(17.0 * pts[3], 9.0 * z)
			draw_circle(pts[1], r, Color(col.r, col.g, col.b, 0.28 * pts[4]))
			draw_arc(pts[1], r, 0.0, TAU, 20, Color(INK.r, INK.g, INK.b, 0.75 * pts[4]), 4.6 * z, true)
			draw_arc(pts[1], r, 0.0, TAU, 20, Color(col.r, col.g, col.b, 0.95 * pts[4]), 2.4 * z, true)
		if bar:
			var frac = clamp(a.hp / max_hp, 0.0, 1.0)
			var w = max(24.0 * pts[3], 14.0 * z)
			var h = max(3.4 * pts[3], 2.4 * z)
			var o: Vector2 = pts[2] - Vector2(w * 0.5, 3.0 * z)
			var bc = Color("#7ed957") if frac > 0.6 else (Color("#f2c14e") if frac > 0.3 else Color("#e8483b"))
			draw_rect(Rect2(o - Vector2(z, z), Vector2(w + 2.0 * z, h + 2.0 * z)), Color(INK.r, INK.g, INK.b, 0.85 * pts[4]))
			draw_rect(Rect2(o, Vector2(w * frac, h)), Color(bc.r, bc.g, bc.b, pts[4]))


# Arrows at the screen edge toward raiders that are out of view; one arrow (with a count) per cluster.
func _draw_edge_arrows() -> void:
	if cam == null:
		return
	var ct = get_canvas_transform()
	var vs = get_viewport_rect().size
	var c = vs * 0.5
	var hx = c.x - 48.0
	var hy = c.y - 130.0       # keep clear of the top cards and the bottom lever bar
	if hx <= 10.0 or hy <= 10.0:
		return
	var screen = Rect2(Vector2.ZERO, vs)
	var groups := {}
	for e in sim.enemies:
		if e.cls == "prey" or e.state == 2:
			continue
		var sp = ct.xform(sim.enemy_pos(e))
		if screen.has_point(sp):
			continue
		var dir = sp - c
		var s = min(hx / max(abs(dir.x), 0.001), hy / max(abs(dir.y), 0.001))
		var ap = c + dir * s
		var key = Vector2(round(ap.x / ARROW_BUCKET), round(ap.y / ARROW_BUCKET))
		var g = groups.get(key)
		if g == null:
			groups[key] = {"pos": ap, "dir": dir.normalized(), "n": 1, "cls": e.cls}
		else:
			g["n"] += 1
			if CLASS_RANK[e.cls] > CLASS_RANK[g["cls"]]:
				g["cls"] = e.cls
	if groups.empty():
		return
	draw_set_transform_matrix(ct.affine_inverse())      # from here on, coordinates are screen pixels
	var pulse = 0.5 + 0.5 * sin(_t * 7.0)
	for g in groups.values():
		var col: Color = CLASS_COLORS.get(g["cls"], Color.white)
		var dn: Vector2 = g["dir"]
		var perp = dn.rotated(PI * 0.5)
		var ap2: Vector2 = g["pos"]
		var k = 1.0 + 0.12 * pulse
		var tip = ap2 + dn * 20.0 * k
		draw_colored_polygon(PoolVector2Array([tip + dn * 4.0, ap2 - dn * 12.0 + perp * 17.0, ap2 - dn * 12.0 - perp * 17.0]), INK)
		draw_colored_polygon(PoolVector2Array([tip, ap2 - dn * 8.0 + perp * 12.0, ap2 - dn * 8.0 - perp * 12.0]), col)
		if g["n"] > 1:
			draw_string(_font, ap2 - dn * 30.0 + Vector2(-6.0, 7.0), str(g["n"]), Color.white)
