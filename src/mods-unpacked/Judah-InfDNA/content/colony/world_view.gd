extends Node2D
# World layer stack (back to front):
#   SkyLayers (parallax backdrop) -> terrain back wall -> Inner (room contents:
#   food stores, gardens, eggs) -> terrain front dirt -> Band (the walkable top face
#   of the ground, ant hill, entrance holes)
# and, added by colony_scene after this node: Overlay (props, food, queen), ants.

const INK = Color("#15121a")
const GroundView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ground_view.gd")
const DEPTH = GroundView.DEPTH   # thickness of the ground's top face (2.5D surface band, many lanes)
const TREE_TEX = "res://entities/units/neutral/tree.png"
const ROCK_TEX = "res://entities/units/neutral/rock.png"
const FRUIT_TEX = "res://items/consumables/fruit/fruit.png"
const GARDEN_TEX = "res://items/all/garden/garden_ingame.png"
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
var inner: Node2D
var band: Node2D


func _set_cam(c) -> void:
	cam = c
	if sky != null:
		sky.cam = c
	if terrain != null:
		terrain.cam = c


func _ready() -> void:
	var g = sim.grid
	ground = GroundView.new(sim)
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
	for k in [TREE_TEX, ROCK_TEX, FRUIT_TEX, GARDEN_TEX, GLOW_TEX, MOTE_TEX, HUSK_TEX]:
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
	inner.update()
	band.update()


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
	# turf lanes, scenery shadows (cached meshes, see ground_view.gd)
	ground.draw_ground(band)
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


# How bare the ground is at column x: the mound (real spoil, see WorldGrid.deposit) has
# no turf. Smoothed over neighbours so the colour change is soft.
func _mound_f(g, x: int) -> float:
	var m = g.mound_h(x - 1) + 2 * g.mound_h(x) + g.mound_h(x + 1)
	return clamp(m / 3.0, 0.0, 1.0)


# Room contents live between the back wall and the front dirt.
func _draw_inner() -> void:
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


func _draw_egg(ci: CanvasItem, e: Dictionary, mod: Color) -> void:
	var C = sim.grid.CELL
	var ep = e["pos"] * C + Vector2(C * 0.5, C * 0.5)
	var near = clamp(1.0 - e["t"] / 3.0, 0.0, 1.0)
	var wob = sin(_t * 3.0 + ep.x) * 0.8
	var tilt = sin(_t * (14.0 + near * 14.0) + ep.x) * 0.32 * near
	ci.draw_set_transform(ep, tilt, Vector2(1.0 + 0.06 * near, 0.72))
	ci.draw_circle(Vector2(0, -6 + wob), 9.0, INK)
	ci.draw_circle(Vector2(0, -6 + wob), 6.0, Color("#f7f1e3").linear_interpolate(Color("#fff4cf"), near) * mod)
	ci.draw_circle(Vector2(-2, -8 + wob), 2.0, Color.white * mod)
	if near > 0.5:
		ci.draw_line(Vector2(-3, -9 + wob), Vector2(0, -6 + wob), INK, 1.5)
		ci.draw_line(Vector2(0, -6 + wob), Vector2(3, -8 + wob), INK, 1.5)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# Drawn above the dirt by the Overlay child (see colony_scene.gd).
func draw_overlay(ci: CanvasItem) -> void:
	var g = sim.grid
	var C = g.CELL
	# trails
	if show_trails:
		var cols = _view_cols(g)
		for x in range(max(cols[0], g.ox), min(cols[1], g.ox + g.W)):
			var p = g.pher[x - g.ox]
			if p > 0.05:
				var y = _smooth_surf(g, x) - DEPTH * 0.5
				ci.draw_rect(Rect2(x * C, y, C, 4.0), Color(0.78, 1.0, 0.5, clamp(p / 2.0, 0.0, 1.0) * 0.7))
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
			var t = _tex.get(GARDEN_TEX)
			if t != null:
				var sc = (c["rx"] * C * 1.1) / t.get_width()
				ci.draw_set_transform(Vector2(cx, floor_y + 4), 0.0, Vector2(sc, sc))
				ci.draw_texture(t, Vector2(-t.get_width() * 0.5, -t.get_height()), mod)
				ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			else:
				for i in 5:
					var mx = cx + (i - 2) * 12.0
					ci.draw_rect(Rect2(mx - 2, floor_y - 10, 4, 10), Color("#e8dcc4"))
					ci.draw_circle(Vector2(mx, floor_y - 12), 7.0, Color("#c96a4a"))
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
