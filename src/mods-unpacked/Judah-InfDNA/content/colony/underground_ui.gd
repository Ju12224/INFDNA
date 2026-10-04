extends CanvasLayer
# Underground UI (v0.22). Screen-space only; it reads the sim and never changes it.
#   - depth gauge on the right edge: strata bands, the nest levels (filled = dug), the queen,
#     where the ants are, and the camera's depth
#   - a vignette that darkens the screen edges as the camera goes deep
#   - room labels floating over each chamber when zoomed in (larder fullness, eggs in a nursery)
#   - nest panel (U): rooms by kind, larder, farms and rot, ants above/below, active digs
#   - navigation: PageUp / PageDown step through the nest levels, Q to the queen, Home to the surface

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")
const INK = Color("#15121a")
const GOLD = Color("#f2c14e")
const GAUGE_W = 26.0
const BUCKET = 10            # rows per ant-density bucket
const GAUGE_ROWS = 190.0     # depth the gauge covers, in rows below the surface

const STRATA = [
	["Humus", 0.0, 10.0, Color("#6b4a2f")],
	["Clay", 10.0, 31.2, Color("#a9744a")],
	["Sand", 31.2, 56.5, Color("#d8bd77")],
	["Red clay", 56.5, 86.0, Color("#b3513a")],
	["Limestone", 86.0, 122.0, Color("#cfc8b2")],
	["Shale", 122.0, 158.0, Color("#667080")],
	["Bedrock", 158.0, 190.0, Color("#3c3532")],
]
const ROOMS = {
	"food": ["Larder", Color("#f2c14e")],
	"brood": ["Nursery", Color("#ffd6e0")],
	"farm": ["Fungus farm", Color("#9be37a")],
	"midden": ["Midden", Color("#a08a6a")],
	"armory": ["Armory", Color("#bcd6ff")],
	"cistern": ["Cistern", Color("#7fc8ff")],
	"venom": ["Venom Works", Color("#9cff66")],
	"battery": ["Sting Battery", Color("#ff9a73")],
	"architects": ["Architects' Hall", Color("#fff2bd")],
}
const ROOM_ICONS = {"brood": "chamber_brood", "food": "chamber_food", "farm": "chamber_farm", "armory": "chamber_armory", "midden": "chamber_midden"}
const ROOM_ORDER = ["food", "brood", "farm", "midden", "armory", "cistern", "venom", "battery", "architects"]

var scene
var panel_open := false
var _ui: Control
var _f_s: Font
var _f_m: Font
var _slow := 0.0
var _counts := {}
var _under := 0
var _above := 0
var _digging := 0
var _deepest := 0
var _buckets := []
var _dark := 0.0
var _goal = null
var _goal_zoom := 0.0
var bare := false            # view mode: no depth gauge and no room labels (the nest panel, U, still opens)
var _drawn_c := Vector2(INF, INF)   # what the last drawing showed (see _process): no redraw while it holds
var _drawn_p := Vector2(INF, INF)
var _drawn_z := -1.0
var _drawn_food := -1
var _drawn_eggs := -1
var _dark_drawn := -1.0
var _dirty := true


func _ready() -> void:
	layer = 1
	_f_s = Kit.font(15, 2)
	_f_m = Kit.font(19, 2)
	_ui = Control.new()
	_ui.anchor_right = 1.0
	_ui.anchor_bottom = 1.0
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.connect("draw", self, "_paint")
	add_child(_ui)


func _process(delta: float) -> void:
	if scene == null or scene.sim == null or scene.cam == null:
		return
	_slow -= delta
	if _slow <= 0.0:
		_slow = 0.5
		_refresh()
		_dirty = true
	var target = clamp(_cam_depth() / 120.0, 0.0, 1.0) * 0.42
	_dark = lerp(_dark, target, 1.0 - exp(-3.0 * delta))
	if _goal != null:
		var cam = scene.cam
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) \
				or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_DOWN):
			_goal = null
		else:
			cam.position = cam.position.linear_interpolate(_goal, 1.0 - exp(-6.0 * delta))
			if _goal_zoom > 0.0:
				cam.zoom = cam.zoom.linear_interpolate(Vector2.ONE * _goal_zoom, 1.0 - exp(-5.0 * delta))
			if cam.position.distance_to(_goal) < 4.0:
				_goal = null
	# Redraw only when something on it moved: the camera (labels, gauge marker), the vignette's depth, the twice-a-second counts,
	# the larder or the brood the labels show; the open nest panel shows live numbers and is redrawn every frame.
	var cam2 = scene.cam
	var cc = cam2.get_camera_screen_center()
	var cp = cam2.position
	var cz = cam2.zoom.x
	var redraw = panel_open or _dirty or cc != _drawn_c or cp != _drawn_p or cz != _drawn_z or abs(_dark - _dark_drawn) > 0.002 or (_dark < 0.01) != (_dark_drawn < 0.01)
	if not redraw and cz <= 0.9 and not bare:
		var sim = scene.sim       # the room labels are up: they show the larder's fill and the eggs
		redraw = int(clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0) * 100.0) != _drawn_food or sim.eggs.size() != _drawn_eggs
	if redraw:
		_drawn_c = cc
		_drawn_p = cp
		_drawn_z = cz
		if scene.sim != null:
			_drawn_food = int(clamp(scene.sim.food / max(1.0, scene.sim.food_cap), 0.0, 1.0) * 100.0)
			_drawn_eggs = scene.sim.eggs.size()
		_dark_drawn = _dark
		_dirty = false
		_ui.update()


# Called by the HUD when the screen mode changes.
func update_mode() -> void:
	bare = scene != null and scene.hud != null and scene.hud.mode == 0
	if _ui != null:
		_ui.update()


# Watch mode hides the gauge, labels and panel.
func set_watch(on: bool) -> void:
	_ui.visible = not on


func _unhandled_input(event: InputEvent) -> void:
	if scene == null or not (event is InputEventKey and event.pressed and not event.echo):
		return
	var g = scene.sim.grid
	_dirty = true
	match event.scancode:
		KEY_U:
			panel_open = not panel_open
		KEY_Q:
			_goto(Vector2((g.chamber.x + 0.5) * g.CELL, (g.chamber.y + 0.5) * g.CELL), 0.5)
		KEY_HOME:
			_goto(Vector2((g.entrance.x + 0.5) * g.CELL, (g.entrance.y - 8.0) * g.CELL), 0.9)
		KEY_PAGEDOWN:
			jump_level(1)
		KEY_PAGEUP:
			jump_level(-1)


func _goto(p: Vector2, z: float) -> void:
	_goal = p
	_goal_zoom = clamp(z, scene.cam.min_zoom, scene.cam.max_zoom)


func _cam_depth() -> float:
	var g = scene.sim.grid
	return (scene.cam.position.y - g.surf_y(int(g.entrance.x)) * g.CELL) / g.CELL


func _cur_level() -> int:
	var pl = scene.sim.planner
	var cy = scene.cam.position.y / scene.sim.grid.CELL
	var best = 0
	var bd = 1e9
	for i in pl.levels.size():
		var d = abs(pl.levels[i] - cy)
		if d < bd:
			bd = d
			best = i
	return best


func jump_level(dir: int) -> void:
	var pl = scene.sim.planner
	var g = scene.sim.grid
	if pl.levels.empty():
		return
	var i = int(clamp(_cur_level() + dir, 0, pl.levels.size() - 1))
	var sx = 0.0
	var n = 0
	for c in pl.chambers:
		if c.get("level", -1) == i and c.get("z", 0) == 0:
			sx += c["center"].x
			n += 1
	var cx = sx / n if n > 0 else g.entrance.x
	_goto(Vector2((cx + 0.5) * g.CELL, (pl.levels[i] + 0.5) * g.CELL), 0.55)
	var open = i < pl.level_open.size() and pl.level_open[i]
	scene.sim.toasts.append({"text": "Nest level %d%s" % [i + 1, "" if open else " (not dug yet)"], "t": 2.5})


# Cheap counts, twice a second.
func _refresh() -> void:
	var sim = scene.sim
	var g = sim.grid
	_counts.clear()
	_deepest = 0
	var sy = g.surf_y(int(g.entrance.x))
	for c in sim.planner.chambers:
		_counts[c["purpose"]] = _counts.get(c["purpose"], 0) + 1
		_deepest = int(max(_deepest, c["center"].y - sy))
	_under = 0
	_above = 0
	_digging = 0
	_buckets = []
	for i in 20:
		_buckets.append(0)
	for a in sim.ants:
		if g.is_under(a.x, a.y):
			_under += 1
			var b = int(clamp((a.y - sy) / float(BUCKET), 0.0, 19.0))
			_buckets[b] += 1
		else:
			_above += 1
		if a.task == 2:
			_digging += 1


func _paint() -> void:
	if scene == null or scene.sim == null or scene.cam == null:
		return
	var sz = _ui.rect_size
	_vignette(sz)
	if not bare:
		_room_labels(sz)
		_gauge(sz)
	if panel_open:
		_panel(sz)


# Darker screen edges the deeper the camera goes: the dirt closes in.
func _vignette(sz: Vector2) -> void:
	if _dark < 0.01:
		return
	var edge = Color(0.03, 0.02, 0.06, _dark)
	var clear = Color(0.03, 0.02, 0.06, 0.0)
	var m = min(sz.x, sz.y) * 0.32
	var cols = PoolColorArray([edge, edge, clear, clear])
	_ui.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(sz.x, 0), Vector2(sz.x - m, m), Vector2(m, m)]), cols)
	_ui.draw_polygon(PoolVector2Array([Vector2(0, sz.y), Vector2(sz.x, sz.y), Vector2(sz.x - m, sz.y - m), Vector2(m, sz.y - m)]), cols)
	_ui.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(0, sz.y), Vector2(m, sz.y - m), Vector2(m, m)]), cols)
	_ui.draw_polygon(PoolVector2Array([Vector2(sz.x, 0), Vector2(sz.x, sz.y), Vector2(sz.x - m, sz.y - m), Vector2(sz.x - m, m)]), cols)


func _label_pill(p: Vector2, txt: String, tint: Color, a: float, icon = null) -> void:
	var tw = _f_s.get_string_size(txt).x
	var iw = 30.0 if icon != null else 0.0
	var r = Rect2(p.x - (tw + iw) * 0.5 - 12.0, p.y - 24.0, tw + iw + 24.0, 24.0)
	_ui.draw_rect(r.grow(2.0), Color(INK.r, INK.g, INK.b, a))
	_ui.draw_rect(r, Color(0.13, 0.11, 0.18, 0.9 * a))
	_ui.draw_rect(Rect2(r.position.x, r.position.y, 5.0, r.size.y), Color(tint.r, tint.g, tint.b, a))
	if icon != null:
		# the owner's chamber icon, a little bigger than the pill so it reads
		_ui.draw_texture_rect(icon, Rect2(r.position.x + 7.0, r.position.y - 7.0, 34.0, 34.0), false, Color(1, 1, 1, a))
	_ui.draw_string(_f_s, Vector2(r.position.x + 12.0 + iw, r.position.y + 18.0), txt, Color(1, 1, 1, a))


# Names over the chambers, fading in as you zoom toward them.
func _room_labels(sz: Vector2) -> void:
	var z = scene.cam.zoom.x
	if z > 0.9:
		return
	var a = clamp((0.9 - z) / 0.25, 0.0, 1.0)
	var sim = scene.sim
	var C = sim.grid.CELL
	var tr = get_viewport().get_canvas_transform()
	for c in sim.planner.chambers:
		if c.get("z", 0) != 0:
			continue
		var wp = (c["center"] + Vector2(0.5, 0.5)) * C + Vector2(0, -c["ry"] * C - 8.0)
		var p = tr.xform(wp)
		if p.x < -100.0 or p.x > sz.x + 100.0 or p.y < -40.0 or p.y > sz.y + 40.0:
			continue
		var info = ROOMS.get(c["purpose"], [str(c["purpose"]).capitalize(), Color(0.9, 0.9, 0.9)])
		var txt = info[0]
		if c["purpose"] == "food":
			txt += "  %d%%" % int(clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0) * 100.0)
		elif c["purpose"] == "brood":
			var eggs = 0
			for e in sim.eggs:
				if abs(e["pos"].x - c["center"].x) <= c["rx"] + 1.0 and abs(e["pos"].y - c["center"].y) <= c["ry"] + 1.5:
					eggs += 1
			txt += "  %d egg%s" % [eggs, "" if eggs == 1 else "s"]
		_label_pill(p, txt, info[1], a, Kit.icon(ROOM_ICONS[c["purpose"]]) if ROOM_ICONS.has(c["purpose"]) else null)


# The gauge: how deep, which soil, which nest level, where the queen and the ants are.
func _gauge(sz: Vector2) -> void:
	var sim = scene.sim
	var g = sim.grid
	var x0 = sz.x - GAUGE_W - 12.0
	var y0 = 150.0
	var y1 = sz.y - 150.0
	if y1 - y0 < 140.0:
		return
	var k = (y1 - y0) / GAUGE_ROWS
	for s in STRATA:
		var ya = y0 + s[1] * k
		var yb = y0 + s[2] * k
		_ui.draw_rect(Rect2(x0, ya, GAUGE_W, yb - ya), s[3])
	# ants below ground by depth
	for i in _buckets.size():
		var n = _buckets[i]
		if n > 0:
			var w = min(GAUGE_W - 6.0, 3.0 + n * 1.3)
			_ui.draw_rect(Rect2(x0 + (GAUGE_W - w) * 0.5, y0 + i * BUCKET * k + 1.0, w, BUCKET * k - 2.0), Color(0.5, 1.0, 0.45, 0.85))
	_ui.draw_rect(Rect2(x0 - 1.0, y0 - 1.0, GAUGE_W + 2.0, y1 - y0 + 2.0), INK, false, 3.0)
	# strata names
	for s in STRATA:
		var ym = y0 + (s[1] + s[2]) * 0.5 * k
		var nm = s[0]
		var tw = _f_s.get_string_size(nm).x
		_ui.draw_string(_f_s, Vector2(x0 - 40.0 - tw, ym + 5.0), nm, Color(1, 1, 1, 0.78))
	# nest levels: tick + number, filled when dug
	var pl = sim.planner
	var sy = g.surf_y(int(g.entrance.x))
	for i in pl.levels.size():
		var d = pl.levels[i] - sy
		var ly = y0 + d * k
		if ly < y0 or ly > y1:
			continue
		var open = i < pl.level_open.size() and pl.level_open[i]
		_ui.draw_line(Vector2(x0 - 7.0, ly), Vector2(x0 + GAUGE_W, ly), INK, 2.0)
		_ui.draw_circle(Vector2(x0 - 12.0, ly), 5.0, INK)
		_ui.draw_circle(Vector2(x0 - 12.0, ly), 3.5, GOLD if open else Color(0.25, 0.22, 0.3))
		var lt = "%d" % (i + 1)
		_ui.draw_string(_f_s, Vector2(x0 - 22.0 - _f_s.get_string_size(lt).x, ly + 5.0), lt, Color(1, 0.92, 0.6, 0.95 if open else 0.45))
	# the queen
	var qy = y0 + (g.chamber.y - sy) * k
	_ui.draw_circle(Vector2(x0 + GAUGE_W * 0.5, qy), 6.0, INK)
	_ui.draw_circle(Vector2(x0 + GAUGE_W * 0.5, qy), 4.0, Color("#ff6b9d"))
	# the camera
	var dep = _cam_depth()
	var cy = clamp(y0 + dep * k, y0 - 12.0, y1)
	_ui.draw_line(Vector2(x0 - 3.0, cy), Vector2(x0 + GAUGE_W + 3.0, cy), Color.white, 2.0)
	_ui.draw_colored_polygon(PoolVector2Array([Vector2(x0 - 4.0, cy), Vector2(x0 - 16.0, cy - 7.0), Vector2(x0 - 16.0, cy + 7.0)]), Color.white)
	# header + reading, under the owner's depth gauge picture
	var gp = Kit.icon("depth_gauge")
	if gp != null:
		var gs = gp.get_size() * (46.0 / max(1.0, gp.get_size().y))
		_ui.draw_texture_rect(gp, Rect2(Vector2(x0 + GAUGE_W - gs.x, y0 - 104.0), gs), false)
	_ui.draw_string(_f_m, Vector2(x0 - 60.0, y0 - 34.0), "DEPTH", GOLD)
	var reading = "surface" if dep < 1.0 else "%d cm" % int(dep * 0.5)
	_ui.draw_string(_f_s, Vector2(x0 - 60.0, y0 - 14.0), reading, Color(1, 1, 1, 0.9))


func _panel_height(rows: Array) -> float:
	var h = 20.0
	for r in rows:
		match r[0]:
			"title":
				h += 30.0
			"gap":
				h += 8.0
			"bar":
				h += 34.0
			_:
				h += 22.0
	return h


func _panel(sz: Vector2) -> void:
	var sim = scene.sim
	var g = sim.grid
	var rows := []
	rows.append(["title", "UNDERGROUND", ""])
	rows.append(["kv", "Open space", "%d cells" % g.open_under])
	rows.append(["kv", "Deepest room", "%d cm" % int(_deepest * 0.5)])
	rows.append(["kv", "Levels dug", "%d / %d" % [sim.planner.open_levels(), sim.planner.levels.size()]])
	rows.append(["gap", "", ""])
	for p in ROOM_ORDER:
		var n = _counts.get(p, 0)
		if n > 0:
			rows.append(["room", p, "x%d" % n])
	rows.append(["gap", "", ""])
	rows.append(["bar", "Larder  %d / %d" % [int(sim.food), int(sim.food_cap)], ""])
	if sim.farm_rate > 0.005:
		rows.append(["kv", "Fungus farms", "+%.2f / s" % sim.farm_rate])
	if sim.rot_rate > 0.01:
		rows.append(["kv", "Rotting", "-%.2f / s" % sim.rot_rate])
	rows.append(["gap", "", ""])
	rows.append(["kv", "Ants below ground", "%d" % _under])
	rows.append(["kv", "Ants on the surface", "%d" % _above])
	rows.append(["kv", "Diggers at work", "%d" % _digging])
	var kinds := []
	for j in sim.planner.jobs:
		kinds.append(str(j["kind"]))
	rows.append(["text", "Digs: " + (PoolStringArray(kinds).join(", ") if not kinds.empty() else "none"), ""])
	rows.append(["gap", "", ""])
	rows.append(["hint", "U close   Q queen   Home surface", ""])
	rows.append(["hint", "PgUp / PgDn  nest levels", ""])
	var w = 262.0
	var h = _panel_height(rows)
	var x = sz.x - GAUGE_W - 12.0 - 130.0 - w
	var y = 150.0
	_ui.draw_rect(Rect2(x - 3.0, y - 3.0, w + 6.0, h + 6.0), INK)
	_ui.draw_rect(Rect2(x, y, w, h), Color(0.12, 0.1, 0.16, 0.94))
	_ui.draw_rect(Rect2(x, y, w, 5.0), GOLD)
	var cy = y + 14.0
	for r in rows:
		match r[0]:
			"title":
				_ui.draw_string(_f_m, Vector2(x + 14.0, cy + 18.0), r[1], GOLD)
				cy += 30.0
			"gap":
				cy += 8.0
			"kv":
				_ui.draw_string(_f_s, Vector2(x + 14.0, cy + 15.0), r[1], Color(1, 1, 1, 0.75))
				_ui.draw_string(_f_s, Vector2(x + w - 14.0 - _f_s.get_string_size(r[2]).x, cy + 15.0), r[2], Color.white)
				cy += 22.0
			"room":
				var info = ROOMS.get(r[1], [str(r[1]), Color.white])
				_ui.draw_rect(Rect2(x + 14.0, cy + 3.0, 13.0, 13.0), INK)
				_ui.draw_rect(Rect2(x + 16.0, cy + 5.0, 9.0, 9.0), info[1])
				_ui.draw_string(_f_s, Vector2(x + 36.0, cy + 15.0), info[0], Color.white)
				_ui.draw_string(_f_s, Vector2(x + w - 14.0 - _f_s.get_string_size(r[2]).x, cy + 15.0), r[2], Color(1, 1, 1, 0.9))
				cy += 22.0
			"bar":
				var frac = clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0)
				var bc = Color("#7ed957") if frac > 0.5 else (GOLD if frac > 0.25 else Color("#e8483b"))
				_ui.draw_string(_f_s, Vector2(x + 14.0, cy + 14.0), r[1], Color.white)
				_ui.draw_rect(Rect2(x + 12.0, cy + 19.0, w - 24.0, 12.0), INK)
				_ui.draw_rect(Rect2(x + 14.0, cy + 21.0, (w - 28.0) * frac, 8.0), bc)
				cy += 34.0
			"text":
				_ui.draw_string(_f_s, Vector2(x + 14.0, cy + 15.0), r[1], Color(1, 1, 1, 0.8))
				cy += 22.0
			"hint":
				_ui.draw_string(_f_s, Vector2(x + 14.0, cy + 15.0), r[1], Color(1, 1, 1, 0.45))
				cy += 22.0
