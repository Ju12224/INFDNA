extends CanvasLayer
# The right-click menu. Right-click anywhere (without dragging) and a short list of options opens at the cursor:
#   with ants selected    what they can do about the thing under the cursor (attack it, harvest it, guard here, dig here) and free them
#   always                the director's powers, with their cost (Rally here, Harvest this pile, Recall, Surge, Breed, Strike, scent flag)
# Click an option (or press its number) to use it; click anywhere else or press Esc to close. Shift + right-click skips the menu and does
# the first order on the list. The menu takes every click while it is open, so it never starts a drag-box or a camera move by accident.
#
# The scene owns what the options do (colony_scene.menu_choice); this file builds the list and draws and answers the menu.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")
const Orders = preload("res://mods-unpacked/Judah-InfDNA/core/orders.gd")

const ROW_H = 36.0
const HEAD_H = 32.0
const SEP_H = 12.0
const PAD = 8.0
const MIN_W = 300.0
const MAX_KEYS = 9

var scene
var is_open := false
var items := []             # {"t": "item"|"head"|"sep", "label", "sub", "ok", "act", "col"}
var _rows := []             # a Rect2 per item, in screen coordinates
var _box := Rect2()
var _hover := -1
var _ui: Control
var _f: Font
var _fs: Font
var _fh: Font


func _ready() -> void:
	layer = 12
	_f = Kit.font(22, 2)
	_fs = Kit.font(17, 2)
	_fh = Kit.font(18, 2)
	_ui = Control.new()
	_ui.anchor_right = 1.0
	_ui.anchor_bottom = 1.0
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.connect("draw", self, "_paint")
	add_child(_ui)


# ------------------------------------------------------------------ the list
static func head(txt: String) -> Dictionary:
	return {"t": "head", "label": txt, "sub": "", "ok": false, "act": {}, "col": Color.white}


static func sep() -> Dictionary:
	return {"t": "sep", "label": "", "sub": "", "ok": false, "act": {}, "col": Color.white}


static func item(label: String, act: Dictionary, ok: bool = true, sub: String = "", col: Color = Color(0.9, 0.9, 0.95)) -> Dictionary:
	return {"t": "item", "label": label, "sub": sub, "ok": ok, "act": act, "col": col}


# What is under the cursor (target = colony_scene.menu_target) and what could be done about it.
func build(target: Dictionary) -> Array:
	var sim = scene.sim
	var out := []
	var sel = scene.live_selection()
	var kind: String = target["kind"]
	var col = int(target["col"])
	if sel.empty():
		out.append(head("Drag a box over ants to order them"))
	else:
		var ordered = 0
		for a in sel:
			if a.squad != 0:
				ordered += 1
		out.append(head("%d ant%s selected      Food %d" % [sel.size(), "" if sel.size() == 1 else "s", int(sim.food)]))
		match kind:
			"foe":
				var e = target["foe"]
				out.append(_ord("Attack the %s" % str(e.def["name"]).to_lower(), {"t": "order", "kind": "attack", "x": e.x, "y": e.y, "z": e.z, "ref": e.id}, true, sel.size()))
				out.append(_ord("Guard here", {"t": "order", "kind": "move", "x": e.x, "y": e.y, "z": e.z}, true, sel.size()))
			"pile":
				var p = target["pile"]
				out.append(_ord("Harvest this pile  (%d food)" % int(p["amount"]), {"t": "order", "kind": "harvest", "x": col, "y": int(target["row"])}, true, sel.size()))
				out.append(_ord("Guard here", {"t": "order", "kind": "move", "x": col, "y": int(target["row"])}, true, sel.size()))
			"soil":
				var can = bool(target["diggable"])
				out.append(_ord("Dig here" if can else "Too hard to dig", {"t": "order", "kind": "dig", "x": col, "y": int(target["row"]), "z": int(target["z"])}, can, sel.size()))
			"tunnel":
				out.append(_ord("Go here and guard", {"t": "order", "kind": "move", "x": col, "y": int(target["row"]), "z": int(target["z"])}, true, sel.size()))
			_:
				out.append(_ord("Guard here", {"t": "order", "kind": "move", "x": col, "y": int(target["row"])}, true, sel.size()))
		if ordered > 0:
			out.append(item("Free these ants", {"t": "free"}, true, "Q", Color("#ff9a8a")))
	out.append(sep())
	out.append(head("Powers  (w Will, f food)      Will %d / %d" % [int(sim.will), int(sim.will_max())]))
	out.append(_power("rally", "Rally here", col))
	var hp = target["pile"] if kind == "pile" else null
	var harvest = _power("harvest", "Harvest this pile", col)
	if hp == null:
		harvest["ok"] = false
		harvest["sub"] = "E   no pile here"
	out.append(harvest)
	out.append(_power("recall", "Recall every ant", col))
	out.append(_power("surge", "Surge: sprint", col))
	out.append(_power("breed", "Breed from this ant" if not sel.empty() else "Breed: mutate hard", col))
	if sim.rival.found:
		var st = _power("strike", "Strike the %s" % sim.rival.name, col)
		if not sim.rival.can_strike():
			st["ok"] = false
		out.append(st)
	var bk = sim._beacon_cd
	out.append(item("Scent flag here: scouts search it", {"t": "beacon", "x": col}, bk <= 0.0 and sim.food >= sim.BEACON_FOOD + sim.FOOD_RESERVE, ("B   %df" % int(ceil(sim.BEACON_FOOD))) if bk <= 0.0 else "%ds" % int(ceil(bk)), Color("#7ed957")))
	return out


# An order: its cost in food rides on the right, and it greys out when the larder cannot pay it.
func _ord(label: String, act: Dictionary, can: bool, n: int) -> Dictionary:
	var sim = scene.sim
	var c = Orders.cost(str(act["kind"]), n)
	var afford = sim.food >= c + sim.FOOD_RESERVE
	return item(label, act, can and afford, ("%df" % int(ceil(c))) if can else "", Orders.COLORS[str(act["kind"])])


func _power(id: String, label: String, col: int) -> Dictionary:
	var sim = scene.sim
	var c = sim.COMMANDS[id]
	var cd = float(sim.cmd_cd.get(id, 0.0))
	var cost = sim.cmd_cost(id)
	var fc = sim.food_cost(id)
	var ok = cd <= 0.0 and sim.will >= cost and sim.food >= fc + sim.FOOD_RESERVE
	var tail = ("%ds" % int(ceil(cd))) if cd > 0.0 else ("%dw %df" % [int(ceil(cost)), int(ceil(fc))])
	return item(label, {"t": "cast", "id": id, "x": col}, ok, "%s   %s" % [c["key"], tail], Color("#f2c14e"))


# The first order on the list that can be given (Shift + right-click).
func quick_act(list: Array) -> Dictionary:
	for it in list:
		if it["t"] == "item" and it["ok"] and it["act"].get("t", "") == "order":
			return it["act"]
	return {}


# ------------------------------------------------------------------ open / close
func open(pos: Vector2, list: Array) -> void:
	items = list
	var vs = get_viewport().get_visible_rect().size
	var w = MIN_W
	for it in items:
		if it["t"] != "sep":
			var fw = _f.get_string_size(it["label"]).x if it["t"] == "item" else _fh.get_string_size(it["label"]).x
			w = max(w, fw + _fs.get_string_size(it["sub"]).x + 100.0)
	var h = PAD * 2.0
	for it in items:
		h += SEP_H if it["t"] == "sep" else (HEAD_H if it["t"] == "head" else ROW_H)
	var x = pos.x + 6.0
	if x + w > vs.x - 8.0:
		x = pos.x - w - 6.0
	var y = pos.y + 6.0
	if y + h > vs.y - 8.0:
		y = pos.y - h - 6.0
	_box = Rect2(Vector2(max(8.0, x), max(8.0, y)), Vector2(w, h))
	_rows = []
	var ry = _box.position.y + PAD
	for it in items:
		var rh = SEP_H if it["t"] == "sep" else (HEAD_H if it["t"] == "head" else ROW_H)
		_rows.append(Rect2(_box.position.x + 4.0, ry, w - 8.0, rh))
		ry += rh
	is_open = true
	_hover = _row_at(get_viewport().get_mouse_position())
	_ui.update()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_hover = -1
	_ui.update()


func _row_at(p: Vector2) -> int:
	for i in _rows.size():
		if items[i]["t"] == "item" and _rows[i].has_point(p):
			return i
	return -1


func _key_row(n: int) -> int:     # the row of the nth (1-based) numbered option
	var k := 0
	for i in items.size():
		if items[i]["t"] == "item":
			k += 1
			if k == n:
				return i
	return -1


func _choose(i: int) -> void:
	if i < 0 or i >= items.size() or items[i]["t"] != "item":
		return
	if not items[i]["ok"]:
		return
	var act = items[i]["act"]
	close()
	scene.menu_choice(act)


# ------------------------------------------------------------------ input (before the GUI and the world see it)
func _input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		var h = _row_at(event.position)
		if h != _hover:
			_hover = h
			_ui.update()
	elif event is InputEventMouseButton:
		if event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN]:
			close()                                   # zoom goes on underneath
			return
		get_tree().set_input_as_handled()
		if event.pressed and event.button_index in [BUTTON_LEFT, BUTTON_RIGHT, BUTTON_MIDDLE]:
			var i = _row_at(event.position)
			if i >= 0 and event.button_index != BUTTON_MIDDLE:
				_choose(i)
			elif not _box.has_point(event.position):
				close()
	elif event is InputEventKey and event.pressed and not event.echo:
		var sc = event.scancode
		if sc == KEY_ESCAPE:
			get_tree().set_input_as_handled()
			close()
		elif sc >= KEY_1 and sc <= KEY_1 + MAX_KEYS - 1:
			get_tree().set_input_as_handled()
			_choose(_key_row(sc - KEY_1 + 1))
		elif not (sc in [KEY_SHIFT, KEY_CONTROL, KEY_ALT, KEY_META, KEY_CAPSLOCK]):
			close()                                   # any other key: the menu goes away and the key does its job


# ------------------------------------------------------------------ drawing
func _paint() -> void:
	if not is_open:
		return
	_ui.draw_style_box(Kit.flat(Color(0.13, 0.11, 0.17, 0.97), Kit.INK, 10, 3, 0.0, 8), _box)
	var n := 0
	for i in items.size():
		var it = items[i]
		var r: Rect2 = _rows[i]
		match it["t"]:
			"sep":
				_ui.draw_rect(Rect2(r.position.x + 6.0, r.position.y + r.size.y * 0.5 - 1.0, r.size.x - 12.0, 2.0), Color(1, 1, 1, 0.12))
			"head":
				_ui.draw_string(_fh, Vector2(r.position.x + 12.0, r.position.y + 23.0), it["label"], Color(0.95, 0.76, 0.3, 0.9))
			_:
				n += 1
				var on = bool(it["ok"])
				var a = 1.0 if on else 0.4
				if i == _hover and on:
					_ui.draw_rect(r, Color(1.0, 0.85, 0.35, 0.2))
					_ui.draw_rect(Rect2(r.position.x, r.position.y, 4.0, r.size.y), Color(1.0, 0.85, 0.35, 0.95))
				if n <= MAX_KEYS:
					_ui.draw_string(_fs, Vector2(r.position.x + 12.0, r.position.y + 24.0), str(n), Color(1, 1, 1, 0.45 * a))
				var c: Color = it["col"]
				_ui.draw_rect(Rect2(r.position.x + 34.0, r.position.y + 12.0, 12.0, 12.0), Kit.INK)
				_ui.draw_rect(Rect2(r.position.x + 35.0, r.position.y + 13.0, 10.0, 10.0), Color(c.r, c.g, c.b, a))
				_ui.draw_string(_f, Vector2(r.position.x + 56.0, r.position.y + 26.0), it["label"], Color(1, 1, 1, a))
				if it["sub"] != "":
					var sw = _fs.get_string_size(it["sub"]).x
					_ui.draw_string(_fs, Vector2(r.end.x - sw - 12.0, r.position.y + 25.0), it["sub"], Color(1, 1, 1, 0.6 * a))
