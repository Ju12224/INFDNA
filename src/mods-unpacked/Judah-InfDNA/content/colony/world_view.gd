extends Node2D
# World layer stack (back to front):
#   SkyLayers (parallax backdrop) -> terrain back wall -> Inner (room contents:
#   food stores, gardens, eggs) -> terrain front dirt -> Band (the walkable top face
#   of the ground, ant hill, entrance holes)
# and, added by colony_scene after this node: Overlay (props, food, queen), ants.

const INK = Color("#15121a")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const NestDecor = preload("res://mods-unpacked/Judah-InfDNA/content/colony/nest_decor.gd")
const DEPTH = GroundView.DEPTH   # thickness of the ground's top face (2.5D surface band, many lanes)
const TREE_TEX = "res://entities/units/neutral/tree.png"
const ROCK_TEX = "res://entities/units/neutral/rock.png"
const FRUIT_TEX = "res://items/consumables/fruit/fruit.png"
const GLOW_TEX = "res://particles/sprites/particle_28.png"     # soft radial light
const MOTE_TEX = "res://particles/sprites/particle_11.png"     # small round mote
const HUSK_TEX = "res://particles/sprites/particle_13.png"     # oval husk for the midden
const SkyLayers = preload("res://mods-unpacked/Judah-InfDNA/content/colony/sky_layers.gd")
const TerrainView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/terrain_view.gd")

const GRASS_BACK = Color("#79a645")
const GRASS_FRONT = Color("#9ccd57")
const GRASS_BLADES = [Color("#5d8f34"), Color("#86bb4a"), Color("#b3df6e")]
const MOUND_BACK = Color("#8a5a34")
const MOUND_FRONT = Color("#a8733f")
const BACK_MOD = Color(0.46, 0.43, 0.42)   # contents of back-plane rooms, seen through the dirt

var sim
var baker
var cam setget _set_cam
var show_trails := true
var _t := 0.0
var _tex := {}
var sky
var terrain
var ground
var nest_decor
var inner: Node2D
var band: Node2D
var snow_node: Node2D        # snow over the turf, faded in and out by how much has fallen
var shade_node: Node2D       # ground shadows, over the snow
var day                      # day_cycle.gd (optional)


func _set_cam(c) -> void:
	cam = c
	if sky != null:
		sky.cam = c
	if terrain != null:
		terrain.cam = c


func _ready() -> void:
	var g = sim.grid
	ground = GroundView.new(sim)
	nest_decor = NestDecor.new(sim)
	sky = SkyLayers.new()
	sky.grid = g
	sky.anchor = Vector2(g.entrance.x * g.CELL, g.surf_y(int(g.entrance.x)) * g.CELL)
	add_child(sky)
	terrain = TerrainView.new()
	terrain.sim = sim
	add_child(terrain)
	inner = Node2D.new()
	inner.connect("draw", self, "_draw_inner")
	terrain.add_child(inner)
	terrain.move_child(inner, 1)
	band = Node2D.new()
	band.connect("draw", self, "_draw_band")
	add_child(band)
	snow_node = Node2D.new()
	snow_node.connect("draw", self, "_draw_snow")
	band.add_child(snow_node)
	shade_node = Node2D.new()
	shade_node.connect("draw", self, "_draw_shade")
	band.add_child(shade_node)
	for k in [TREE_TEX, ROCK_TEX, FRUIT_TEX, GLOW_TEX, MOTE_TEX, HUSK_TEX]:
		if ResourceLoader.exists(k):
			_tex[k] = load(k)
	for kv in [["bar_bg", "res://ui/hud/ui_lifebar_bg.png"], ["bar_fill", "res://ui/hud/ui_lifebar_fill.png"], ["bar_frame", "res://ui/hud/ui_lifebar_frame.png"]]:
		if ResourceLoader.exists(kv[1]):
			_tex[kv[0]] = load(kv[1])
	if cam != null:
		_set_cam(cam)


func _process(delta: float) -> void:
	_t += delta
	_q_lay = max(0.0, _q_lay - delta)
	if cam != null:
		# the world is infinite: make sure the terrain under the camera exists
		var vp = get_viewport_rect().size
		var z = cam.zoom.x
		var c = cam.get_camera_screen_center()
		var g = sim.grid
		g.surf_y(int((c.x - vp.x * z) / g.CELL))
		g.surf_y(int((c.x + vp.x * z) / g.CELL))
		ground.prepare(_view_cols(g), _t)
		if ground.perf == null or ground.perf.scenery > 0:
			nest_decor.prepare(_view_cols(g), _t)
	inner.update()
	band.update()
	shade_node.update()
	var snow = day.snow if day != null else 0.0
	snow_node.visible = snow > 0.01
	if snow_node.visible:
		snow_node.modulate = Color(1.0, 1.0, 1.0, snow)
		snow_node.update()


# Size of the original playfield (camera zoom limits); the world itself never ends.
func world_size() -> Vector2:
	return Vector2(sim.grid.arena_r - sim.grid.arena_l + 1, sim.grid.H) * sim.grid.CELL


func surf_any(g, x: int) -> float:
	return float(g.surf_y(x))


func _smooth_surf(g, x: float) -> float:
	var acc := 0.0
	var xi = int(round(x))
	for k in range(-2, 3):
		acc += g.surf_y(xi + k)
	return acc / 5.0 * g.CELL


func _view_cols(g) -> Array:
	if cam == null:
		return [g.arena_l - 20, g.arena_r + 20]
	var vp = get_viewport_rect().size
	var z = cam.zoom.x
	var c = cam.get_camera_screen_center()
	return [int(floor((c.x - vp.x * z * 0.5) / g.CELL)) - 4, int(ceil((c.x + vp.x * z * 0.5) / g.CELL)) + 4]


static func _hash(x: float) -> float:
	return fmod(abs(sin(x * 12.9898) * 43758.5453), 1.0)


# The walkable top face of the ground: front edge = the dirt outline, back edge
# DEPTH pixels higher. Units walk in lanes across it (see ant_view.gd).
func _draw_band() -> void:
	var g = sim.grid
	var C = g.CELL
	# turf lanes (cached meshes, see ground_view.gd); the snow and the shadows are drawn by the nodes under this one
	ground.draw_turf(band)
	# the mouths: a hole in the top face with a rim of freshly dropped pellets
	for i in g.entrances.size():
		var en = g.entrances[i]
		var cx = (en.x + 0.5) * C
		var cy = _smooth_surf(g, int(en.x)) - DEPTH * 0.34
		band.draw_set_transform(Vector2(cx, cy), 0.0, Vector2(1.0, 0.42))
		band.draw_circle(Vector2.ZERO, 27.0, Color("#7f5130"))
		band.draw_circle(Vector2(-4, -4), 24.0, Color("#a8733f"))
		band.draw_circle(Vector2.ZERO, 20.0, INK)
		band.draw_circle(Vector2.ZERO, 15.5, Color("#1d120d"))
		band.draw_circle(Vector2(0, 6), 9.5, Color("#0e0907"))
		band.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_snow() -> void:
	ground.draw_snow(snow_node)


func _draw_shade() -> void:
	ground.draw_shade(shade_node)


# How bare the ground is at column x: the mound (real spoil, see WorldGrid.deposit) has
# no turf. Smoothed over neighbours so the colour change is soft.
func _mound_f(g, x: int) -> float:
	var m = g.mound_h(x - 1) + 2 * g.mound_h(x) + g.mound_h(x + 1)
	return clamp(m / 3.0, 0.0, 1.0)


# Room contents live between the back wall and the front dirt.
func _draw_inner() -> void:
	if ground.perf == null or ground.perf.scenery > 0:
		nest_decor.draw(inner)
	# warm light pooled in each lived-in room (drawn under the front dirt, so it only
	# shows through the open cells)
	var gt = _tex.get(GLOW_TEX)
	var C = sim.grid.CELL
	if gt != null:
		for c in sim.planner.chambers:
			if c.get("z", 0) != 0:
				continue
			var cc = (c["center"] + Vector2(0.5, 0.5)) * C
			var w = c["rx"] * C * 2.6
			var h = c["ry"] * C * 2.8
			var col = POOL_COLORS.get(c["purpose"], Color(1.0, 0.8, 0.5))
			var fl = 0.16 + 0.03 * sin(_t * 0.7 + c["center"].x)
			inner.draw_texture_rect(gt, Rect2(cc - Vector2(w, h) * 0.5, Vector2(w, h)), false, Color(col.r, col.g, col.b, fl))
	for c in sim.planner.chambers:
		if c.get("z", 0) == 0:
			_draw_chamber(inner, c)
	for e in sim.eggs:
		if e.get("z", 0) == 0:
			_draw_egg(inner, e, Color.white)
	_draw_motes(inner)


const POOL_COLORS = {"food": Color(1.0, 0.82, 0.45), "brood": Color(1.0, 0.72, 0.62), "farm": Color(0.6, 1.0, 0.55), "midden": Color(0.7, 0.8, 0.4),
	"armory": Color(0.75, 0.85, 1.0), "venom": Color(0.6, 1.0, 0.4), "battery": Color(1.0, 0.6, 0.45), "cistern": Color(0.5, 0.8, 1.0), "architects": Color(1.0, 0.95, 0.75)}
# Workshop props: Brotato item icons laid out on the room floor.
const WORKSHOP_PROPS = {
	"armory": ["metal_plate", "helmet", "metal_plate", "helmet"],
	"venom": ["toxic_sludge", "poisonous_tonic", "toxic_sludge"],
	"battery": ["nail", "sharp_bullet", "nail", "sharp_bullet", "nail"],
	"architects": ["pile_of_books", "compass", "pencil", "toolbox"],
}


# Dust motes drifting through the tunnels: world-anchored, deterministic per tile, so
# panning doesn't drag them along. The front dirt hides every mote outside open cells.
func _draw_motes(ci: CanvasItem) -> void:
	var mt = _tex.get(GLOW_TEX)
	if mt == null or cam == null:
		return
	var g = sim.grid
	var C = g.CELL
	var vp = get_viewport_rect().size
	var z = cam.zoom.x
	var c = cam.get_camera_screen_center()
	var r = Rect2(c - vp * z * 0.5, vp * z)
	var T = 180.0
	var x0 = int(floor(r.position.x / T))
	var x1 = int(ceil(r.end.x / T))
	var y0 = int(floor(r.position.y / T))
	var y1 = int(ceil(r.end.y / T))
	if (x1 - x0) * (y1 - y0) > 900:
		return
	for tx in range(x0, x1 + 1):
		for ty in range(y0, y1 + 1):
			for k in 3:
				var hs = tx * 73.1 + ty * 19.7 + k * 5.3
				var base = Vector2((tx + _hash(hs)) * T, (ty + _hash(hs + 1.1)) * T)
				var sp = 0.15 + 0.25 * _hash(hs + 2.2)
				var p = base + Vector2(sin(_t * sp + hs) * 34.0, sin(_t * sp * 0.7 + hs * 1.3) * 22.0 - fmod(_t * 3.0 * sp, 40.0))
				if p.y < _smooth_surf(g, p.x / C) + 30.0:
					continue
				var sz = 5.0 + 7.0 * _hash(hs + 3.3)
				var a = (0.18 + 0.2 * _hash(hs + 4.4)) * (0.6 + 0.4 * sin(_t * 1.3 + hs))
				ci.draw_texture_rect(mt, Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1.0, 0.9, 0.72, a))
	# spores rising from the fungus gardens
	for ch in sim.planner.chambers:
		if ch["purpose"] != "farm" or ch.get("z", 0) != 0:
			continue
		var fy = ((ch["floor"] + 0.5) if ch.has("floor") else ch["center"].y + ch["ry"] * 0.6) * C
		for i in 7:
			var h2 = ch["center"].x * 3.1 + i * 7.7
			var life = fmod(_t * (10.0 + 6.0 * _hash(h2)) + i * 23.0, ch["ry"] * C * 1.7)
			var sx = (ch["center"].x + 0.5) * C + (_hash(h2 + 1.0) - 0.5) * ch["rx"] * C * 1.2 + sin(_t + i) * 6.0
			var k2 = life / (ch["ry"] * C * 1.7)
			var s2 = 6.0 + 4.0 * _hash(h2 + 2.0)
			ci.draw_texture_rect(mt, Rect2(Vector2(sx, fy - life) - Vector2(s2, s2) * 0.5, Vector2(s2, s2)), false, Color(0.7, 1.0, 0.55, 0.55 * (1.0 - k2)))


# Back-plane rooms sit behind the front dirt: their contents are drawn over it, dimmed,
# like the back tunnels themselves.
func _draw_back_rooms(ci: CanvasItem) -> void:
	for c in sim.planner.chambers:
		if c.get("z", 0) == 1:
			_draw_chamber(ci, c, BACK_MOD)
	for e in sim.eggs:
		if e.get("z", 0) == 1:
			_draw_egg(ci, e, BACK_MOD)


# The brood goes through its stages in the nursery: an egg, then a wriggling grub, then a silk cocoon that darkens and twitches
# until the ant breaks out. (The sim only counts down to the hatch; the stage is how far along that countdown is.)
func _draw_egg(ci: CanvasItem, e: Dictionary, mod: Color) -> void:
	var C = sim.grid.CELL
	var ep = e["pos"] * C + Vector2(C * 0.5, C * 0.5)
	var prog = clamp(1.0 - e["t"] / max(e.get("t0", 14.0), 0.1), 0.0, 1.0)
	var ph = ep.x * 0.37
	# a small shadow on the floor under it
	ci.draw_set_transform(ep, 0.0, Vector2(1.0, 0.3))
	ci.draw_circle(Vector2(0, 0), 9.0, Color(0.05, 0.03, 0.02, 0.28))
	if prog < 0.34:
		var wob = sin(_t * 3.0 + ph) * 0.6
		ci.draw_set_transform(ep, 0.0, Vector2(1.0, 0.78))
		ci.draw_circle(Vector2(0, -6 + wob), 9.0, INK)
		ci.draw_circle(Vector2(0, -6 + wob), 6.2, Color("#f7f1e3") * mod)
		ci.draw_circle(Vector2(-2, -8 + wob), 2.0, Color.white * mod)
	elif prog < 0.76:
		# the grub: a pale curled body that wriggles, head to the right
		var k = (prog - 0.34) / 0.42
		var grow = 0.8 + 0.5 * k
		ci.draw_set_transform(ep, 0.0, Vector2(grow, grow))
		var pts := []
		for i in 7:
			var u = float(i) / 6.0
			var a = lerp(PI * 0.95, PI * 0.1, u)
			var wig = sin(_t * 3.6 + ph + u * 4.2) * (1.0 + 2.0 * u)
			pts.append(Vector2(cos(a) * 9.5, -sin(a) * 6.5 - 5.0 + wig * 0.5))
		for i in 7:
			var r = 3.2 + 2.0 * sin(PI * (float(i) + 0.5) / 7.0)
			ci.draw_circle(pts[i], r + 1.7, INK)
		for i in 7:
			var r2 = 3.2 + 2.0 * sin(PI * (float(i) + 0.5) / 7.0)
			var shade = 0.0 if i % 2 == 0 else 0.05
			ci.draw_circle(pts[i], r2, Color("#f4ecd2").darkened(shade) * mod)
		ci.draw_circle(pts[6] + Vector2(1.5, -0.5), 2.7, Color("#d8b98a") * mod)       # the head
		ci.draw_circle(pts[6] + Vector2(2.4, 0.2), 0.8, INK)
		ci.draw_circle(pts[1] + Vector2(-1.2, -2.0), 1.6, Color(1, 1, 1, 0.55))
	else:
		# the pupa in its cocoon: ivory silk, the folded ant showing faintly through, darkening and twitching as it nears hatching
		var k2 = (prog - 0.76) / 0.24
		var twitch = clamp((k2 - 0.75) / 0.25, 0.0, 1.0)
		var tilt = sin(_t * 22.0 + ph) * 0.16 * twitch
		ci.draw_set_transform(ep + Vector2(0, -6), tilt, Vector2(1.0, 1.0))
		var silk = Color("#f1e7cc").linear_interpolate(Color("#c9a77a"), k2 * 0.85)
		_oval(ci, Vector2.ZERO, 11.5, 6.8, INK)
		_oval(ci, Vector2.ZERO, 9.6, 5.1, silk * mod)
		var fold = Color(0.35, 0.22, 0.12, 0.2 + 0.4 * k2)
		for q in 3:
			ci.draw_line(Vector2(-4.0 + q * 3.4, -3.0), Vector2(-3.0 + q * 3.4, 3.2), fold, 1.2)
		ci.draw_circle(Vector2(6.0, -0.4), 2.2, Color(0.3, 0.2, 0.12, 0.25 + 0.45 * k2))
		ci.draw_circle(Vector2(-3.0, -2.4), 1.8, Color(1, 1, 1, 0.5))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _oval(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PoolVector2Array()
	for i in 16:
		var a = TAU * i / 16.0
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)


# Scent trails: a soft glowing ribbon that follows the ground (not stair steps), strength shown by brightness and width, and
# little beads of scent drifting toward the nest along it.
func _draw_trails(ci: CanvasItem) -> void:
	var g = sim.grid
	var C = g.CELL
	var cols = _view_cols(g)
	var x0 = int(max(cols[0], g.ox))
	var x1 = int(min(cols[1], g.ox + g.W - 1))
	var z = cam.zoom.x if cam != null else 1.0
	var pts := PoolVector2Array()
	var core := PoolColorArray()
	var halo := PoolColorArray()
	var run_a = x0
	for x in range(x0, x1 + 2):
		var p = g.pher[x - g.ox] if x <= x1 else 0.0
		if p > 0.05:
			if pts.empty():
				run_a = x
			var k = clamp(p / 2.0, 0.0, 1.0)
			pts.append(Vector2((x + 0.5) * C, _smooth_surf(g, x) - DEPTH * 0.5))
			core.append(Color(0.9, 1.0, 0.62, 0.22 + 0.62 * k))
			halo.append(Color(0.55, 0.95, 0.3, 0.05 + 0.2 * k))
		elif not pts.empty():
			if pts.size() >= 2:
				ci.draw_polyline_colors(pts, halo, 10.0 * max(1.0, z * 0.8), true)
				ci.draw_polyline_colors(pts, core, 3.4 * max(1.0, z * 0.8), true)
				_trail_beads(ci, run_a, x - 1, z)
			pts = PoolVector2Array()
			core = PoolColorArray()
			halo = PoolColorArray()


func _trail_beads(ci: CanvasItem, xa: int, xb: int, z: float) -> void:
	var g = sim.grid
	var C = g.CELL
	var ex = int(g.entrance.x)
	var gap = 34.0
	var r = max(2.3, 1.7 * z)
	for side in 2:
		# beads on the west of the nest drift east and vice versa: the food is going home
		var lo = xa if side == 0 else max(xa, ex)
		var hi = min(xb, ex) if side == 0 else xb
		if hi <= lo:
			continue
		var dir = 1.0 if side == 0 else -1.0
		var off = fposmod(-_t * 44.0 * dir, gap)
		var bx = ceil((lo * C - off) / gap) * gap + off
		while bx < hi * C:
			var xi = int(floor(bx / C))
			var f = bx / C - xi
			var k = clamp(g.pher[xi - g.ox] / 2.0, 0.0, 1.0) if xi >= g.ox and xi < g.ox + g.W else 0.0
			if k > 0.03:
				var y = lerp(_smooth_surf(g, xi), _smooth_surf(g, xi + 1), f) - DEPTH * 0.5
				ci.draw_circle(Vector2(bx, y), r * 2.2, Color(0.8, 1.0, 0.5, 0.16 * k))
				ci.draw_circle(Vector2(bx, y), r, Color(1.0, 1.0, 0.86, 0.35 + 0.55 * k))
			bx += gap


# A warning sign above every fungus garden the mould has reached (drawn above the dirt, so it shows even when the room is small).
func _draw_mold_warnings(ci: CanvasItem) -> void:
	if sim.farm_mold.empty():
		return
	var C = sim.grid.CELL
	var pulse = 0.65 + 0.35 * sin(_t * 6.0)
	for c in sim.planner.chambers:
		if c["purpose"] != "farm" or c.get("z", 0) != 0 or sim.mold_of(c) < 0.2:
			continue
		var wp = Vector2((c["center"].x + 0.5) * C, (c["center"].y - c["ry"]) * C - 22.0)
		ci.draw_colored_polygon(PoolVector2Array([wp + Vector2(-13.0, 10.0), wp + Vector2(13.0, 10.0), wp + Vector2(0.0, -15.0)]), Color(INK.r, INK.g, INK.b, pulse))
		ci.draw_colored_polygon(PoolVector2Array([wp + Vector2(-9.5, 7.0), wp + Vector2(9.5, 7.0), wp + Vector2(0.0, -10.0)]), Color(0.96, 0.78, 0.2, pulse))
		ci.draw_rect(Rect2(wp.x - 1.2, wp.y - 5.0, 2.4, 8.0), INK)
		ci.draw_rect(Rect2(wp.x - 1.2, wp.y + 4.0, 2.4, 2.4), INK)


# Drawn above the dirt by the Overlay child (see colony_scene.gd).
func draw_overlay(ci: CanvasItem) -> void:
	var g = sim.grid
	var C = g.CELL
	if show_trails:
		_draw_trails(ci)
	_draw_mold_warnings(ci)
	_draw_back_rooms(ci)
	# food piles
	for pile in sim.piles:
		_draw_pile(ci, pile)
	# queen: paces her chamber, breathes, squeezes when she lays, shuffles her legs
	var qx = _queen_offset()
	var qv = _queen_offset(0.1) - qx
	var qfeet = g.center(int(g.chamber.x), int(g.chamber.y + g.chamber_r.y)) + Vector2(qx, C * 0.5)
	var hurt = clamp(sim.queen_flash / 0.6, 0.0, 1.0)
	if hurt > 0.0:
		qfeet += Vector2(sin(_t * 70.0) * 3.5 * hurt, 0)
	if sim.eggs.size() > _q_eggs:
		_q_lay = 0.45
	_q_eggs = sim.eggs.size()
	var walking = abs(qv) > 0.6
	if abs(qv) > 0.2:
		_q_face = 1 if qv > 0 else -1
	var frame = int(_t * 5.0) % baker.FRAMES if walking else 0
	var qt = baker.get_texture(sim.queen_genome, 2.0, frame)
	if qt != null:
		var qs = 0.27
		var breath = sin(_t * 1.9) * 0.022
		var lay = sin(clamp(_q_lay / 0.45, 0.0, 1.0) * PI) * 0.07
		var tilt = sin(_t * 5.0) * 0.025 if walking else sin(_t * 0.8) * 0.01
		var sx = qs * (1.0 + 0.05 * hurt + lay * 0.6)
		var sy = qs * (1.0 + breath - 0.06 * hurt - lay)
		ci.draw_set_transform(qfeet, tilt, Vector2(sx * _q_face, sy))
		ci.draw_texture_rect(qt, Rect2(-baker.FEET * 2.0, baker.SIZE * 2.0), false, Color(1.0, 1.0 - 0.55 * hurt, 1.0 - 0.55 * hurt))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# queen health: Brotato lifebar, always visible once she is hurt
	if sim.queen_hp < sim.queen_max * 0.999 or sim.queen_flash > 0.0:
		var bw = 150.0
		var bh = 22.0
		var bp = qfeet + Vector2(-bw * 0.5, -96.0)
		if sim.queen_flash > 0.0:
			var pulse = 0.5 + 0.5 * sin(_t * 18.0)
			ci.draw_arc(qfeet + Vector2(0, -34), 64.0 + pulse * 8.0, 0.0, TAU, 40, Color(1, 0.25, 0.2, 0.35 + 0.4 * pulse), 5.0, true)
		var frac = clamp(sim.queen_hp / sim.queen_max, 0.0, 1.0)
		var tb = _tex.get("bar_bg")
		var tf = _tex.get("bar_fill")
		var tr = _tex.get("bar_frame")
		var col = Color("#e8483b") if frac < 0.5 else Color("#f2c14e")
		if tb != null and tf != null and tr != null:
			ci.draw_texture_rect(tb, Rect2(bp, Vector2(bw, bh)), false)
			ci.draw_texture_rect_region(tf, Rect2(bp, Vector2(bw * frac, bh)), Rect2(0, 0, 320.0 * frac, 48), col)
			ci.draw_texture_rect(tr, Rect2(bp, Vector2(bw, bh)), false)
		else:
			ci.draw_rect(Rect2(bp - Vector2(3, 3), Vector2(bw + 6, bh + 6)), INK)
			ci.draw_rect(Rect2(bp, Vector2(bw * frac, bh)), col)


# Brotato-style material gem: ink outline, flat fill, light facet.
static func draw_gem(ci: CanvasItem, p: Vector2, s: float, variant: int, mod: Color = Color.white) -> void:
	var tilt = (variant - 2) * 0.12
	var shape = [Vector2(0, -13), Vector2(10, -4), Vector2(7, 10), Vector2(-7, 10), Vector2(-10, -4)]
	var outer := PoolVector2Array()
	var inner := PoolVector2Array()
	for v in shape:
		var r = v.rotated(tilt)
		outer.append(p + r * s * 1.38)
		inner.append(p + r * s)
	ci.draw_colored_polygon(outer, Color("#15121a"))
	ci.draw_colored_polygon(inner, Color("#6cc644") * mod)
	ci.draw_colored_polygon(PoolVector2Array([p + Vector2(0, -13).rotated(tilt) * s, p + Vector2(10, -4).rotated(tilt) * s,
		p + Vector2(0, 1).rotated(tilt) * s, p + Vector2(-10, -4).rotated(tilt) * s]), Color("#a8ec74") * mod)
	ci.draw_line(p + Vector2(-4, -6).rotated(tilt) * s, p + Vector2(1, -9).rotated(tilt) * s, Color("#e6ffd0") * mod, 2.5 * s, true)


var _q_eggs := 0
var _q_lay := 0.0
var _q_face := 1


# Where the queen stands, as an x offset in the chamber: slow wandering with pauses
# (the sum of two sines rests near its turning points).
func _queen_offset(ahead: float = 0.0) -> float:
	var t = _t + ahead
	var w = sim.grid.chamber_r.x * sim.grid.CELL * 0.42
	return w * (0.7 * sin(t * 0.21) + 0.3 * sin(t * 0.53 + 1.0))


func _draw_prop(ci: CanvasItem, path: String, x: int, lane: float, height: float) -> void:
	var g = sim.grid
	var feet = Vector2((x + 0.5) * g.CELL, _smooth_surf(g, x) - (1.0 - lane) * DEPTH * 0.9)
	var shade = 0.86 + 0.14 * lane
	var t = _tex.get(path)
	if t == null:
		ci.draw_circle(feet + Vector2(0, -height * 0.4), height * 0.4, Color(0.3, 0.5, 0.25))
		return
	var sc = height / t.get_height() * (0.74 + 0.26 * lane)
	ci.draw_set_transform(feet, 0.0, Vector2(sc, sc))
	ci.draw_texture(t, Vector2(-t.get_width() * 0.5, -t.get_height()), Color(shade, shade, shade))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_chamber(ci: CanvasItem, c: Dictionary, mod: Color = Color.white) -> void:
	var C = sim.grid.CELL
	var floor_y = (c["floor"] + 0.5) * C if c.has("floor") else (c["center"].y + c["ry"] * 0.75) * C
	var cx = (c["center"].x + 0.5) * C
	match c["purpose"]:
		"food":
			var share = clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0)
			var n = int(ceil(share * 9))
			for i in n:
				var ox = (i % 5 - 2) * 11.0
				var oy = -(i / 5) * 9.0
				draw_gem(ci, Vector2(cx + ox, floor_y - 6 + oy), 0.55, i % 5, mod)
		"farm":
			_draw_fungus(ci, c, mod, cx, floor_y)
		"brood":
			ci.draw_circle(Vector2(cx, floor_y - 2), 3.0, Color(mod.r, mod.g, mod.b, 0.15))
		"armory", "venom", "battery", "architects":
			var props = WORKSHOP_PROPS[c["purpose"]]
			var n2 = props.size()
			for i in n2:
				var path = "res://items/all/%s/%s_icon.png" % [props[i], props[i]]
				if not _tex.has(path):
					_tex[path] = load(path) if ResourceLoader.exists(path) else null
				var it = _tex[path]
				if it == null:
					continue
				var sz = 26.0 if c["purpose"] != "battery" else 20.0
				var px = cx + (i - (n2 - 1) * 0.5) * min(30.0, c["rx"] * C * 1.4 / n2)
				var bob = sin(_t * 1.5 + i * 1.7) * 1.2 if c["purpose"] == "venom" else 0.0
				var rot = 0.9 if c["purpose"] == "battery" else (_hash(i + cx) - 0.5) * 0.3
				ci.draw_set_transform(Vector2(px, floor_y - sz * 0.45 + bob), rot, Vector2.ONE)
				ci.draw_texture_rect(it, Rect2(Vector2(-sz, -sz) * 0.5, Vector2(sz, sz)), false, mod)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			if c["purpose"] == "venom":
				# a bubbling vat glow
				var gt2 = _tex.get(GLOW_TEX)
				if gt2 != null:
					var gw = 40.0 + 6.0 * sin(_t * 2.0)
					ci.draw_texture_rect(gt2, Rect2(Vector2(cx, floor_y - 10) - Vector2(gw, gw * 0.6) * 0.5, Vector2(gw, gw * 0.6)), false, Color(0.5, 1.0, 0.3, 0.45 * mod.a))
		"cistern":
			# an underground lake: a flat pool on the floor with a moving shimmer
			var w2 = c["rx"] * C * 0.9
			var top = floor_y - c["ry"] * C * 0.45
			var pts := PoolVector2Array()
			for i in 17:
				var fx = -w2 + 2.0 * w2 * i / 16.0
				pts.append(Vector2(cx + fx, top + sin(_t * 1.4 + i * 0.8) * 1.5))
			pts.append(Vector2(cx + w2 * 0.92, floor_y + 2))
			pts.append(Vector2(cx - w2 * 0.92, floor_y + 2))
			ci.draw_colored_polygon(pts, Color(0.18 * mod.r, 0.42 * mod.g, 0.62 * mod.b, 0.85))
			for i in 4:
				var sx2 = cx - w2 * 0.8 + fmod(_t * 9.0 + i * 37.0, w2 * 1.6)
				ci.draw_line(Vector2(sx2, top + 3), Vector2(sx2 + 14, top + 3), Color(0.8, 0.95, 1.0, 0.55 * mod.a), 2.0)
			ci.draw_line(Vector2(cx - w2, top), Vector2(cx + w2, top), Color(0.7, 0.9, 1.0, 0.7 * mod.a), 2.0)
		"midden":
			# the colony's refuse heap: husks of the dead, kept far from the brood
			var ht = _tex.get(HUSK_TEX)
			var n = int(clamp(sim.died / 3, 2, 26))
			for i in n:
				var hx = cx + (_hash(i * 3.7 + cx) - 0.5) * c["rx"] * C * 1.3 * (1.0 - float(i) / (n + 6))
				var hy = floor_y - 4.0 - (float(i) / n) * c["ry"] * C * 0.7
				var ang = _hash(i * 9.1 + cx) * PI
				if ht != null:
					ci.draw_set_transform(Vector2(hx, hy), ang, Vector2(0.28, 0.2))
					ci.draw_texture(ht, Vector2(-32, -32), Color(0.35 * mod.r, 0.25 * mod.g, 0.18 * mod.b))
					ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				else:
					ci.draw_circle(Vector2(hx, hy), 5.0, Color(0.3, 0.22, 0.15))


# A fungus garden the way leafcutter ants keep one: a bed of chewed leaf pulp with a pale spongy body of fungus growing on it,
# threads of mycelium creeping out at the edges, and the little white food bulbs the ants actually eat on the surface.
func _draw_fungus(ci: CanvasItem, c: Dictionary, mod: Color, cx: float, floor_y: float) -> void:
	var C = sim.grid.CELL
	var W = c["rx"] * C * 1.55
	# the garden grows after its room is dug: spores and white threads, then small fluffy lobes, then the mature sponge
	var grow = 0.28 + 0.72 * smoothstep(0.0, 1.0, clamp(sim.farm_age(c) / 150.0, 0.0, 1.0))
	var mold = sim.mold_of(c)
	var H = clamp(c["ry"] * C * 0.9, 14.0, 64.0) * (0.45 + 0.55 * grow)
	var sd = c["center"].x * 0.37 + c["center"].y * 0.11
	var breathe = 1.0 + 0.012 * sin(_t * 0.9 + sd)
	var bed_d = Color("#3b2a17") * mod
	var bed_l = Color("#6b5a2c") * mod
	var cream = Color("#e8e0cb") * mod
	var shade = Color("#aaa088") * mod
	var lite = Color("#fffcef") * mod
	ci.draw_set_transform(Vector2(cx, floor_y), 0.0, Vector2(1.0, 1.0))
	# the bed: dark chewed pulp with olive leaf chips in it
	_lump(ci, Vector2(0, -H * 0.1), W * 0.54, H * 0.2, INK, sd, 0.05, 20)
	_lump(ci, Vector2(0, -H * 0.1), W * 0.5, H * 0.16, bed_d, sd + 1.0, 0.05, 20)
	for i in 9:
		var cxp = (_hash(sd + i * 3.1) - 0.5) * W * 0.8
		var cyp = -H * 0.1 - _hash(sd + i * 5.3) * H * 0.1
		ci.draw_set_transform(Vector2(cx + cxp, floor_y + cyp), _hash(sd + i) * PI, Vector2.ONE)
		ci.draw_rect(Rect2(-3.2, -1.1, 6.4, 2.2), bed_l)
	ci.draw_set_transform(Vector2(cx, floor_y), 0.0, Vector2(1.0, breathe))
	# the fungus: a lumpy dome of wide soft lobes in two rows (tall behind, low in front), shaded underneath and lit from the upper right
	var lobes := []
	var n = 7
	for i in n:
		if _hash(sd + i * 7.7) > grow + 0.3:
			continue
		var u = (i + 0.5) / n
		var env = pow(sin(PI * u), 0.6)
		var hh = H * (0.42 + 0.58 * env) * (0.8 + 0.2 * _hash(sd + i * 2.3))
		var lrx = W * (0.105 + 0.05 * _hash(sd + i * 4.7))
		lobes.append([Vector2((u - 0.5) * W * 0.86 + (_hash(sd + i * 6.1) - 0.5) * W * 0.05, -H * 0.14 - hh * 0.42), lrx, hh * 0.46, abs(u - 0.5) + 1.0])
	n = 8
	for i in n:
		if _hash(sd + i * 5.9 + 3.0) > grow + 0.3:
			continue
		var u2 = (i + 0.5) / n
		var hh2 = H * (0.22 + 0.26 * pow(sin(PI * u2), 0.7)) * (0.75 + 0.25 * _hash(sd + 30.0 + i))
		var lrx2 = W * (0.07 + 0.045 * _hash(sd + 40.0 + i * 4.7))
		lobes.append([Vector2((u2 - 0.5) * W * 0.9 + (_hash(sd + 50.0 + i) - 0.5) * W * 0.04, -H * 0.1 - hh2 * 0.4), lrx2, hh2 * 0.44, abs(u2 - 0.5)])
	lobes.sort_custom(self, "_lobe_far")
	for L in lobes:
		_lump(ci, L[0], L[1] + 2.2, L[2] + 2.2, INK, sd + L[0].x, 0.06, 18)
	var k = 0
	for L in lobes:
		_lump(ci, L[0], L[1], L[2], shade, sd + k, 0.06, 18)
		_lump(ci, L[0] + Vector2(L[1] * 0.1, -L[2] * 0.08), L[1] * 0.9, L[2] * 0.86, cream, sd + k + 0.5, 0.05, 18)
		_lump(ci, L[0] + Vector2(L[1] * 0.3, -L[2] * 0.38), L[1] * 0.52, L[2] * 0.36, lite, sd + k + 0.9, 0.07, 12)
		for q in 5:
			var pa = TAU * _hash(sd + k * 5.0 + q)
			var pr = _hash(sd + k * 7.0 + q * 3.0) * 0.7
			ci.draw_circle(L[0] + Vector2(cos(pa) * L[1] * pr, sin(pa) * L[2] * pr), 0.8 + 0.8 * _hash(sd + k + q), Color(0.42, 0.37, 0.28, 0.4))
		k += 1
	# dark galleries where the ants work their way into the comb
	for i in 3:
		var gx = (_hash(sd + 70.0 + i) - 0.5) * W * 0.55
		var gy = -H * (0.22 + 0.2 * _hash(sd + 80.0 + i))
		_lump(ci, Vector2(gx, gy), W * 0.035, H * 0.07, Color(0.2, 0.15, 0.1, 0.9 * mod.a), sd + i, 0.1, 10)
		ci.draw_arc(Vector2(gx, gy + H * 0.02), W * 0.035, 0.2, PI - 0.2, 8, Color(1, 1, 0.92, 0.55 * mod.a), 1.0, true)
	# mould: a rival fungus, grey-green and fuzzy, creeping over the lobes
	if mold > 0.0:
		var j = 0
		for L in lobes:
			if _hash(sd + j * 3.3 + 1.0) < mold * 1.4:
				var mr = 0.35 + 0.5 * mold
				_lump(ci, L[0] + Vector2(L[1] * 0.1, -L[2] * 0.15), L[1] * mr, L[2] * mr * 0.8, Color(0.34, 0.5, 0.3, 0.9 * mod.a), sd + j + 5.0, 0.2, 12)
				_lump(ci, L[0] + Vector2(-L[1] * 0.1, -L[2] * 0.05), L[1] * mr * 0.55, L[2] * mr * 0.45, Color(0.2, 0.33, 0.22, 0.85 * mod.a), sd + j + 6.0, 0.25, 10)
				for q in 3:
					ci.draw_circle(L[0] + Vector2((_hash(sd + j + q) - 0.5) * L[1], -L[2] * 0.2 - _hash(sd + j * 2.0 + q) * L[2] * 0.4), 1.2, Color(0.55, 0.75, 0.4, 0.9 * mod.a))
			j += 1
	# the food bulbs: tiny white spheres that gleam on the surface
	for i in (9 if grow > 0.7 else 0):
		var Lb = lobes[int(_hash(sd + i * 9.7) * (lobes.size() - 0.01))]
		var a = PI * (1.1 + 0.8 * _hash(sd + i * 2.9))
		var bp = Lb[0] + Vector2(cos(a) * Lb[1] * 0.95, sin(a) * Lb[2] * 0.95)
		var tw = 0.65 + 0.35 * sin(_t * 1.7 + i * 2.1)
		ci.draw_circle(bp, 2.0, Color(1.0, 1.0, 0.94, 0.9 * mod.a))
		ci.draw_circle(bp + Vector2(-0.5, -0.5), 0.8, Color(1, 1, 1, tw))
	# mycelium threads fanning out over the floor
	ci.draw_set_transform(Vector2(cx, floor_y), 0.0, Vector2.ONE)
	for i in 8:
		var side = -1.0 if i % 2 == 0 else 1.0
		var x0 = side * W * (0.38 + 0.1 * _hash(sd + i))
		var pts := PoolVector2Array()
		for j in 5:
			var uu = float(j) / 4.0
			pts.append(Vector2(x0 + side * uu * W * (0.12 + 0.1 * _hash(sd + i * 2.0)), -H * 0.08 + sin(uu * 5.0 + sd + i) * 1.6 - uu * H * 0.05 * _hash(sd + i * 3.0)))
		ci.draw_polyline(pts, Color(0.96, 0.95, 0.9, 0.55 * mod.a), 1.0, true)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _lobe_far(a, b) -> bool:
	return a[3] > b[3]


# A soft lump: an ellipse whose edge wobbles a little, so nothing looks stamped.
func _lump(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, seed_v: float, jag: float, segs: int) -> void:
	var pts := PoolVector2Array()
	for i in segs:
		var a = TAU * i / segs
		var k = 1.0 - jag + jag * 2.0 * _hash(seed_v * 12.9898 + i * 7.233)
		pts.append(c + Vector2(cos(a) * rx * k, sin(a) * ry * k))
	ci.draw_colored_polygon(pts, col)


func _draw_pile(ci: CanvasItem, pile: Dictionary) -> void:
	var g = sim.grid
	var C = g.CELL
	var base = Vector2((pile["x"] + 0.5) * C, _smooth_surf(g, pile["x"]) - DEPTH * 0.45)
	if pile.get("kind", "") == "jackpot":
		var gl = 0.2 + 0.08 * sin(_t * 3.0)
		ci.draw_circle(base + Vector2(0, -16), 52.0, Color(1.0, 0.85, 0.3, gl * 0.6))
		ci.draw_circle(base + Vector2(0, -16), 30.0, Color(1.0, 0.92, 0.55, gl))
	if pile.get("kind", "") == "fruit":
		var ft = _tex.get(FRUIT_TEX)
		var nf = int(clamp(ceil(pile["amount"] / 10.0), 1, 5))
		for i in nf:
			var fp = base + Vector2((i - nf * 0.5) * 12.0, -(i % 2) * 8.0 - 8.0)
			if ft != null:
				ci.draw_texture_rect(ft, Rect2(fp - Vector2(13, 13), Vector2(26, 26)), false)
			else:
				ci.draw_circle(fp, 9.0, INK)
				ci.draw_circle(fp, 6.5, Color("#e04a3a"))
		return
	var n = int(clamp(ceil(pile["amount"] / 7.0), 1, 10))
	var rows = [[0, 0], [-1, 0], [1, 0], [-2, 0], [2, 0], [-0.5, 1], [0.5, 1], [-1.5, 1], [1.5, 1], [0, 2]]
	for i in n:
		var o = rows[i]
		var p = base + Vector2(o[0] * 11.0, -o[1] * 9.0 - 9.0)
		draw_gem(ci, p, 0.68, (pile["x"] * 7 + i * 3) % 5)
