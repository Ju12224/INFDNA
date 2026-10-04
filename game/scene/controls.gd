extends Control
# Player control (roadmap 4.2 and 4.3): picking ants out, giving them orders, and the Director's powers. On the interface layer, above
# the HUD; colony.gd sets `colony` before adding it.
#   left-drag       a box: the ants inside it are selected (Shift adds them to the selection)
#   left-click      on an ant: that one ant (Shift adds it, or takes it out); on empty ground: nobody. Double-click: every ant on
#                   screen of the same caste
#   right-click     (press and release less than CLICK_PX apart) with ants selected: an order, decided by what is under the cursor
#                   (core/orders.gd): a raider -> attack it, a food pile -> harvest it, solid soil -> dig to it, open ground or a
#                   tunnel -> go there and guard it. With nobody selected, or with Shift: the Director's menu at the cursor
#   right-drag      pans the camera (colony.gd): a right press or release is never taken from it
#   keys            the powers, at the cursor (their letters are colony_sim.COMMANDS': R rally, E harvest, Z recall, J surge,
#                   M breed, Y strike), B scent flag, G mutagen on the selected ant, C the brood's caste order, Q frees the selected
#                   ants from their orders, Esc closes the menu or clears the selection
# The sim owns what all of these do (Orders.issue / release, sim.cast, sim.place_beacon, sim.bless, sim.caste_order); this file reads
# the mouse and the keys and shows the menu. The menu and the drag-box are built from the owner's frames in art/ui; a power with no
# picture yet shows no icon. `selected` (ant id -> true) is for the views: units_view brightens the ants in it.

const Sim = preload("res://core/colony_sim.gd")
const Orders = preload("res://core/orders.gd")
const EnemyDefs = preload("res://core/enemy_defs.gd")
const Art = preload("res://scene/art.gd")
const Kit = preload("res://scene/menu_kit.gd")
const Band = preload("res://scene/band.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const C = WorldGrid.CELL
const CLICK_PX = 6.0          # a press and release closer than this (screen px) is a click; farther apart, a drag
const PICK_PX = 12.0          # screen px of slack around an ant's body for a click
const FOE_PX = 18.0           # ... and around a raider's
const PILE_REACH = 5          # a right-click this many columns or fewer from a food pile is on the pile
const ATTN_EVERY = 0.25       # how often the sim is told what the player is looking at (the squads' stand-down: orders.gd)
const MENU_EVERY = 0.2        # how often the open menu's numbers (Will, food, cooldowns) are brought up to date
const MSG_T = 3.5             # seconds a message stays on the status line
const INK = Kit.INK
const DIM = Kit.DIM
const GOLD = Kit.GOLD
const OFF = 0.38              # alpha of a menu row that cannot be used now
const ROW_W = 470.0
const ROW_H = 34.0
const MENU_K = 0.85           # the owner's frames, shrunk to this for the menu (menu_kit.box) ...
const ROW_K = 0.55            # ... for the row under the mouse
const BOX_K = 0.6             # ... for the drag-box
const STATUS_K = 0.8          # ... for the line at the bottom
const WILL_ICON = "ui/hivemind.png"
const FOOD_ICON = "ui/food.png"
const BROOD_ICON = "ui/queen.png"
# The owner's pictures standing for the powers in the menu. A power with none (surge, the scent flag, mutagen) shows a blank: art list.
const ICONS = {"rally": "ui/soldier.png", "harvest": "ui/food_pile.png", "recall": "ui/chamber_queen.png", "breed": "ui/brood.png",
	"strike": "ui/crown_red.png"}
const LABELS = {"rally": "Rally here", "harvest": "Harvest this pile", "recall": "Recall: everyone home", "surge": "Surge: sprint",
	"breed": "Breed: mutate hard", "strike": "Strike the rival nest"}
const KEY_BEACON = KEY_B
const KEY_MUTAGEN = KEY_G
const KEY_CASTE = KEY_C
const KEY_FREE = KEY_Q
const CASTE_NAMES = ["Mixed", "Workers", "Soldiers"]
const CASTE_WORDS = [["forager", "foragers"], ["digger", "diggers"], ["soldier", "soldiers"]]
# The sizes units_view.gd draws ants at (its _length, CASTE_SCALE, FAR_ZOOM, FAR_MAX, BACK_SCALE), so a click lands where an ant is
# drawn. If units_view has ant_spot(a) -> Vector3(x, y, radius) (world px), that is used instead.
const LEN_PER_SIZE = 2.2
const LEN_BASE = 24.0
const LEN_K = 0.132
const CASTE_SCALE = [0.94, 1.0, 1.12]
const FAR_ZOOM = 0.45
const FAR_MAX = 1.6
const BACK_SCALE = 0.8

var colony
var selected := {}            # ant id -> true: the player's selection (dead ants drop out within ATTN_EVERY)

var _lmb := false             # the left button went down in the world and is still down
var _boxing := false          # ... and has moved far enough to be a drag-box
var _box_a := Vector2.ZERO    # the box's corners, screen px
var _box_b := Vector2.ZERO
var _rmb := false             # the right button went down in the world
var _rmb_pos := Vector2.ZERO
var _rmb_moved := false
var _attn_t := 0.0
var _menu_t := 0.0
var _mt := {}                 # what the open menu is about: _target() of the spot it was opened on
var _msg := ""
var _msg_t := 0.0
var _status_text := ""

var _box: Panel
var _menu: PanelContainer
var _rows := {}               # menu row id -> {btn, line, name, key, will, will_i, food, food_i}
var _will_lbl: Label
var _food_lbl: Label
var _sel_lbl: Label
var _gap_orders: Control
var _caste_btns := []
var _status: PanelContainer
var _status_lbl: Label
var _hover_sb: StyleBox
var _tip := ""                # the tip of the menu row under the mouse (shown on the bottom line)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_sb = Kit.box("frame_small", ROW_K, Vector2.ZERO)
	_box = Panel.new()
	var bsb = Kit.box("frame_small", BOX_K, Vector2.ZERO)
	if bsb is StyleBoxTexture:
		bsb.draw_center = false               # only the frame: the ants inside show through
	_box.add_theme_stylebox_override("panel", bsb)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false
	add_child(_box)
	_build_status()
	_build_menu()


func reset() -> void:
	selected = {}
	_lmb = false
	_boxing = false
	_rmb = false
	_box.visible = false
	_close_menu()
	_msg_t = 0.0


# ================================================================== input
# While the menu is open it takes every click outside it (and closes), so the click that closes it never starts a box or an order.
func _input(event: InputEvent) -> void:
	if _menu == null or not _menu.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			_close_menu()                         # the zoom goes on underneath
		elif not _menu.get_global_rect().has_point(event.position):
			_close_menu()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_close_menu()
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if colony == null or colony.sim == null or colony.sim.collapsed:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if event.double_click:
					_lmb = false
					_select_like(_to_world(event.position))
				else:
					_lmb = true
					_boxing = false
					_box_a = event.position
					_box_b = event.position
				get_viewport().set_input_as_handled()
			elif _lmb:
				_end_box(event.position, event.shift_pressed)
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			# never marked handled: colony.gd's camera drag needs both the press and the release
			if event.pressed:
				_rmb = true
				_rmb_moved = false
				_rmb_pos = event.position
			elif _rmb:
				_rmb = false
				if not _rmb_moved and event.position.distance_to(_rmb_pos) < CLICK_PX:
					_right_click(_rmb_pos, event.shift_pressed)
	elif event is InputEventMouseMotion:
		if _lmb:
			_box_b = event.position
			if not _boxing and _box_a.distance_to(_box_b) >= CLICK_PX:
				_boxing = true
			_place_box()
		if _rmb and event.position.distance_to(_rmb_pos) >= CLICK_PX:
			_rmb_moved = true                     # a right-drag pans; only a plain right-click orders
	elif event is InputEventKey and event.pressed and not event.echo:
		if _key(event):
			get_viewport().set_input_as_handled()


func _key(event: InputEventKey) -> bool:
	var k = event.keycode
	if k == KEY_ESCAPE:
		if selected.is_empty():
			return false
		_set_selection([], false)
		return true
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed:
		return false
	var sim = colony.sim
	var wp = _to_world(get_viewport().get_mouse_position())
	var col = int(floor(wp.x / C))
	for id in Sim.COMMANDS:
		if OS.find_keycode_from_string(str(Sim.COMMANDS[id]["key"])) == k:
			_close_menu()
			_cast(id, col, _breed_source(_pick_ant(wp)))
			return true
	match k:
		KEY_BEACON:
			_close_menu()
			_act(func(): return sim.place_beacon(col), "")
			return true
		KEY_MUTAGEN:
			_close_menu()
			_act(func(): return sim.bless(_breed_source(_pick_ant(wp))), "")
			return true
		KEY_CASTE:
			_set_caste((int(sim.caste_order) + 1) % CASTE_NAMES.size())
			return true
		KEY_FREE:
			if selected.is_empty():
				return false
			_close_menu()
			_free_selection()
			return true
	return false


func _process(delta: float) -> void:
	if colony == null or colony.sim == null:
		return
	# a button let go of over a panel never reaches _unhandled_input: finish the drag from the real button state
	if _lmb and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_box(get_viewport().get_mouse_position(), Input.is_key_pressed(KEY_SHIFT))
	if _rmb and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_rmb = false
	_attn_t -= delta
	if _attn_t <= 0.0:
		_attn_t = ATTN_EVERY
		_prune()
		var vr = colony.view_rect()
		colony.sim.attn_rect = Rect2(vr.position / C, vr.size / C).grow(6.0)
		colony.sim.attn_sel = selected
	if _menu.visible:
		if colony.sim.collapsed:
			_close_menu()
		else:
			_menu_t -= delta
			if _menu_t <= 0.0:
				_menu_t = MENU_EVERY
				_refresh_menu()
	_msg_t = max(0.0, _msg_t - delta)
	_update_status()


# ================================================================== selection
func _to_world(p: Vector2) -> Vector2:
	return colony.get_canvas_transform().affine_inverse() * p


func _place_box() -> void:
	_box.visible = _boxing
	if _boxing:
		var r = Rect2(_box_a, _box_b - _box_a).abs()
		var sb = _box.get_theme_stylebox("panel")
		var m = Vector2(sb.content_margin_left + sb.content_margin_right, sb.content_margin_top + sb.content_margin_bottom)
		_box.position = r.position
		_box.size = Vector2(max(r.size.x, m.x), max(r.size.y, m.y))


func _end_box(release_pos: Vector2, add: bool) -> void:
	_lmb = false
	var was_box = _boxing
	_boxing = false
	_box.visible = false
	if was_box:
		var wa = _to_world(_box_a)
		var wb = _to_world(release_pos)
		_set_selection(ants_in(Rect2(wa, wb - wa).abs()), add)
	else:
		var a = _pick_ant(_to_world(release_pos))
		if a != null:
			_set_selection([a], add, true)
		elif not add:
			_set_selection([], false)


# Double-click: every ant on screen of the same caste as the one clicked.
func _select_like(wp: Vector2) -> void:
	var a = _pick_ant(wp)
	if a == null:
		return
	var out := []
	for b in ants_in(colony.view_rect()):
		if b.caste == a.caste:
			out.append(b)
	_set_selection(out, false)


# `toggle`: a Shift-click on one ant that is already selected takes it out.
func _set_selection(list: Array, add: bool, toggle: bool = false) -> void:
	var out = selected.duplicate() if add else {}
	for a in list:
		if toggle and add and selected.has(a.id):
			out.erase(a.id)
		else:
			out[a.id] = true
	selected = out
	colony.sim.attn_sel = selected


# Drop the ants that have died.
func _prune() -> void:
	if selected.is_empty():
		return
	var out := {}
	for a in colony.sim.ants:
		if selected.has(a.id):
			out[a.id] = true
	if out.size() != selected.size():
		selected = out


# The selected ants that are alive.
func selection() -> Array:
	var out := []
	if selected.is_empty():
		return out
	for a in colony.sim.ants:
		if selected.has(a.id):
			out.append(a)
	return out


func is_selected(id: int) -> bool:
	return selected.has(id)


# The ants drawn inside a world rectangle.
func ants_in(r: Rect2) -> Array:
	var out := []
	var ctx = _pick_context()
	var vr = colony.view_rect(80.0).merge(r)
	for a in colony.sim.ants:
		var p = colony.sim.ant_pos(a)
		if not vr.has_point(p):
			continue
		var s = _spot(a, p, ctx)
		if r.has_point(Vector2(s.x, s.y)):
			out.append(a)
	return out


# The ant drawn under a world point (nearest body first), or null.
func _pick_ant(wp: Vector2):
	var ctx = _pick_context()
	var vr = colony.view_rect(80.0)
	var slack = PICK_PX / colony.zoom()
	var best = null
	var bd = INF
	for a in colony.sim.ants:
		var p = colony.sim.ant_pos(a)
		if not vr.has_point(p):
			continue
		var s = _spot(a, p, ctx)
		var d = Vector2(s.x, s.y).distance_to(wp)
		if d < s.z + slack and d < bd:
			bd = d
			best = a
	return best


func _pick_context() -> Dictionary:
	var uv = colony.views.get("units")
	var hook = uv != null and uv.has_method("ant_spot")
	var st = uv.get("_state") if (uv != null and not hook) else null
	return {"uv": uv, "hook": hook, "state": st if st is Dictionary else {}, "far": clamp(sqrt(FAR_ZOOM / colony.zoom()), 1.0, FAR_MAX)}


# Where an ant's body is drawn: Vector3(x, y, radius) in world px. As units_view places it: its feet on the edge of the ground it
# walks on, lifted into its lane of the meadow band on the surface (smaller toward the back), smaller in the back tunnel plane.
func _spot(a, p: Vector2, ctx: Dictionary) -> Vector3:
	if ctx["hook"]:
		return ctx["uv"].ant_spot(a)
	var lane: float = a.lane
	var surf = 1.0 if colony.grid.is_surface_cell(a.tx, a.ty) else 0.0
	var st = ctx["state"].get(a.id)
	if st is Vector3:
		surf = st.x
		lane = st.y
	var down = Vector2(-sin(a.rot), cos(a.rot))
	var feet = p + down * C * 0.5
	feet.y = lerp(feet.y, Band.lane_y(feet.y, lane), surf)
	var plane = lerp(float(a.z), float(a.tz), clamp(a.t, 0.0, 1.0))
	var t = LEN_PER_SIZE * float(a.ph.get("size", 74.0)) + LEN_BASE
	var length = LEN_K * t * min(1.0, 310.0 / (t + 120.0)) * CASTE_SCALE[clampi(a.caste, 0, 2)]
	length *= ctx["far"] * lerp(1.0, Band.persp(lane), surf) * lerp(1.0, BACK_SCALE, plane)
	var mid = feet - down * length * 0.2
	return Vector3(mid.x, mid.y, length * 0.5)


# The raider or prey drawn under a world point, or null.
func _pick_foe(wp: Vector2):
	var sim = colony.sim
	var g = colony.grid
	var best = null
	var bd = INF
	for e in sim.enemies:
		var feet = sim.enemy_pos(e) + Vector2(0, C * 0.5)
		var h = EnemyDefs.height_of(e)
		var mids = [feet - Vector2(0, h * 0.5)]
		if e.z == 0 and g.is_surface_cell(e.x, e.y) and not g.is_under(e.x, e.y):
			var k = Band.persp(e.lane)
			mids.append(Vector2(feet.x, Band.lane_y(feet.y, e.lane)) - Vector2(0, h * k * 0.5))
		var r = max(FOE_PX / colony.zoom(), h * 0.6)
		for m in mids:
			var d = m.distance_to(wp)
			if d < r and d < bd:
				bd = d
				best = e
	return best


# What a right-click lands on: a raider, a food pile, open surface, solid soil, or an open tunnel.
func _target(wp: Vector2) -> Dictionary:
	var g = colony.grid
	var sim = colony.sim
	var col = int(floor(wp.x / C))
	var t = {"kind": "surface", "col": col, "row": g.surf_y(col) - 2, "z": 0, "foe": null, "pile": null, "diggable": false,
		"ant": _pick_ant(wp)}
	var foe = _pick_foe(wp)
	if foe != null:
		t["kind"] = "foe"
		t["foe"] = foe
		t["col"] = foe.x
		t["row"] = foe.y
		t["z"] = foe.z
		return t
	var row = int(floor(wp.y / C))
	var top = g.surf_y(col)
	# the meadow band above the ground line, and the crust under it (too near the top to dig: world_grid.diggable) unless it is a
	# tunnel mouth, are the surface
	if wp.y < top * C + C * 1.5 or (row < top + 3 and g.is_solid(col, row, 0)):
		var best = null
		for p in sim.piles:
			if p["amount"] > 4.0 and abs(p["x"] - col) <= PILE_REACH and (best == null or abs(p["x"] - col) < abs(best["x"] - col)):
				best = p
		if best != null:
			t["kind"] = "pile"
			t["pile"] = best
		return t
	var z = 0 if (g.can_walk(col, row, 0) or not g.can_walk(col, row, 1)) else 1
	t["row"] = row
	t["z"] = z
	if g.is_solid(col, row, z):
		t["kind"] = "soil"
		t["diggable"] = g.diggable(col, row, z)
	else:
		t["kind"] = "tunnel"
	return t


# ================================================================== orders and powers
func _right_click(screen_pos: Vector2, shift: bool) -> void:
	_prune()
	var t = _target(_to_world(screen_pos))
	if selected.is_empty() or shift:
		_open_menu(screen_pos, t)
	else:
		_order(t)


# The order a right-click on `t` gives the selected ants: [kind, x, y, z, ref, label], or [] with the reason in label.
func _order_for(t: Dictionary, sel: Array) -> Array:
	var col = int(t["col"])
	var row = int(t["row"])
	match str(t["kind"]):
		"foe":
			var e = t["foe"]
			var nm = str(e.def.get("name", "foe")).to_lower()
			if e.def.get("fly", false) and e.cls == "prey":
				var winged = false
				for a in sel:
					if a.ph.get("wings", 0) > 0:
						winged = true
						break
				if not winged:
					return ["", 0, 0, 0, 0, "Only winged ants can reach the %s." % nm]
			return ["attack", e.x, e.y, e.z, e.id, "Attack the %s" % nm]
		"pile":
			return ["harvest", int(t["pile"]["x"]), row, 0, 0, "Harvest this pile  (%d food)" % int(t["pile"]["amount"])]
		"soil":
			if not t["diggable"]:
				return ["", 0, 0, 0, 0, "That ground is too hard to dig."]
			return ["dig", col, row, int(t["z"]), 0, "Dig here"]
		"tunnel":
			return ["move", col, row, int(t["z"]), 0, "Go here and guard"]
	return ["move", col, row, 0, 0, "Guard here"]


func _order(t: Dictionary) -> void:
	var sel = selection()
	if sel.is_empty():
		return
	var o = _order_for(t, sel)
	if o[0] == "":
		_say(o[5])
		return
	var res = Orders.issue(colony.sim, sel, o[0], o[1], o[2], o[3], o[4])
	_say(res["msg"])


func _free_selection() -> void:
	var n = Orders.release(colony.sim, selection())
	_say(("%d ant%s let go: back to their own work." % [n, "" if n == 1 else "s"]) if n > 0 else "None of the selected ants are under orders.")


# Breed and mutagen take this ant: the one asked about (under the cursor), else the selection's first.
func _breed_source(under):
	if under != null:
		return under
	var sel = selection()
	return sel[0] if not sel.is_empty() else null


func _cast(id: String, col: int, ant) -> void:
	var sim = colony.sim
	_act(func(): return sim.cast(id, col, ant), "%s: %s." % [Sim.COMMANDS[id]["name"], Sim.COMMANDS[id]["tip"]])


# Run a sim call; whatever it says back (a refusal, a confirmation) goes on the status line, else `ok_text` if it went out.
func _act(f: Callable, ok_text: String) -> bool:
	var sim = colony.sim
	var n0 = sim.toasts.size()
	var ok = bool(f.call())
	if sim.toasts.size() > n0:
		_say(str(sim.toasts[sim.toasts.size() - 1]["text"]))
	elif ok and ok_text != "":
		_say(ok_text)
	if _menu.visible:
		_refresh_menu()
	return ok


func _set_caste(i: int) -> void:
	colony.sim.caste_order = i
	_say("The brood leans toward: %s." % CASTE_NAMES[i].to_lower() if i > 0 else "The brood is mixed again.")
	if _menu.visible:
		_refresh_menu()


func _say(text: String) -> void:
	_msg = text
	_msg_t = MSG_T


# ================================================================== the menu
func _build_menu() -> void:
	_menu = PanelContainer.new()
	_menu.add_theme_stylebox_override("panel", Kit.box("frame_wide", MENU_K, Vector2(0, 0)))
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	add_child(_menu)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	_menu.add_child(box)
	# the head: the hive mind (the Will) and the larder
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head.add_child(_icon(WILL_ICON, 48))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(_label("Director", 15, GOLD))
	_will_lbl = _label("", 19, INK)
	hv.add_child(_will_lbl)
	head.add_child(hv)
	head.add_child(_icon(FOOD_ICON, 30))
	_food_lbl = _label("", 17, INK)
	head.add_child(_food_lbl)
	box.add_child(head)
	box.add_child(_gap(4))
	# with ants selected (Shift + right-click): the order a plain right-click would give, and letting them go
	_sel_lbl = _label("", 14, GOLD)
	box.add_child(_sel_lbl)
	_rows["order"] = _row(box, "order", "")
	_rows["free"] = _row(box, "free", "")
	_gap_orders = _gap(8)
	box.add_child(_gap_orders)
	for id in Sim.COMMANDS:
		_rows[id] = _row(box, id, ICONS.get(id, ""))
	_rows["beacon"] = _row(box, "beacon", "")
	_rows["mutagen"] = _row(box, "mutagen", "")
	box.add_child(_gap(6))
	# the brood's caste order: what the queen's eggs lean toward
	var brood := HBoxContainer.new()
	brood.custom_minimum_size = Vector2(ROW_W, ROW_H)
	brood.add_theme_constant_override("separation", 6)
	var bi = _icon(BROOD_ICON, 28)
	brood.add_child(_pad(10))
	brood.add_child(bi)
	var bl = _label("Brood", 17, INK)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brood.add_child(bl)
	var bk = _label(OS.get_keycode_string(KEY_CASTE), 15, DIM)
	bk.custom_minimum_size.x = 22
	bk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brood.add_child(bk)
	for i in CASTE_NAMES.size():
		var b := Button.new()
		b.text = CASTE_NAMES[i]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, ROW_H)
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", GOLD)
		b.add_theme_color_override("font_hover_pressed_color", GOLD)
		for s in ["normal", "disabled", "focus"]:
			b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
		b.add_theme_stylebox_override("hover", _hover_sb)
		b.add_theme_stylebox_override("pressed", _hover_sb)
		b.add_theme_stylebox_override("hover_pressed", _hover_sb)
		b.tooltip_text = "What the queen's eggs lean toward (%s cycles)." % OS.get_keycode_string(KEY_CASTE)
		b.pressed.connect(_set_caste.bind(i))
		brood.add_child(b)
		_caste_btns.append(b)
	box.add_child(brood)


# One row of the menu: a button with the power's picture, name, key, and its Will and food cost (or the seconds until it is ready).
func _row(parent: Control, id: String, icon_path: String) -> Dictionary:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT
	b.custom_minimum_size = Vector2(ROW_W, ROW_H)
	for s in ["normal", "disabled", "focus"]:
		b.add_theme_stylebox_override(s, StyleBoxEmpty.new())
	b.add_theme_stylebox_override("hover", _hover_sb)
	b.add_theme_stylebox_override("pressed", _hover_sb)
	b.pressed.connect(_choose.bind(id))
	parent.add_child(b)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 10
	line.offset_right = -12
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(line)
	line.add_child(_icon(icon_path, 28))
	var nm = _label("", 17, INK)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	line.add_child(nm)
	var key = _label("", 15, DIM)
	key.custom_minimum_size.x = 22
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_child(key)
	var will = _label("", 16, INK)
	will.custom_minimum_size.x = 40
	will.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(will)
	var will_i = _icon(WILL_ICON, 20)
	line.add_child(will_i)
	var food = _label("", 16, INK)
	food.custom_minimum_size.x = 30
	food.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(food)
	var food_i = _icon(FOOD_ICON, 20)
	line.add_child(food_i)
	return {"btn": b, "line": line, "name": nm, "key": key, "will": will, "will_i": will_i, "food": food, "food_i": food_i}


# will < 0: no Will cost; food < 0: no food cost; cd > 0: recharging (the seconds show instead of the costs).
func _set_row(id: String, label: String, key: String, will: float, food: float, cd: float, ok: bool, tip: String) -> void:
	var r = _rows[id]
	r["btn"].visible = true
	r["btn"].disabled = not ok
	r["btn"].tooltip_text = tip
	r["line"].modulate = Color(1, 1, 1, 1.0 if ok else OFF)
	r["name"].text = label
	r["key"].text = key
	if cd > 0.0:
		r["will"].text = "%d s" % int(ceil(cd))
		r["will_i"].modulate.a = 0.0
		r["food"].text = ""
		r["food_i"].modulate.a = 0.0
		return
	r["will"].text = ("%d" % int(ceil(will))) if will >= 0.0 else ""
	r["will_i"].modulate.a = 1.0 if will >= 0.0 else 0.0
	r["food"].text = ("%d" % int(ceil(food))) if food >= 0.0 else ""
	r["food_i"].modulate.a = 1.0 if food >= 0.0 else 0.0


func _open_menu(screen_pos: Vector2, t: Dictionary) -> void:
	_mt = t
	_menu.visible = true
	_refresh_menu()
	_menu.reset_size()
	var size = _menu.get_combined_minimum_size()
	var vs = get_viewport_rect().size
	var x = screen_pos.x + 6.0
	if x + size.x > vs.x - 8.0:
		x = screen_pos.x - size.x - 6.0
	var y = screen_pos.y + 6.0
	if y + size.y > vs.y - 8.0:
		y = screen_pos.y - size.y - 6.0
	_menu.position = Vector2(clamp(x, 8.0, max(8.0, vs.x - size.x - 8.0)), clamp(y, 8.0, max(8.0, vs.y - size.y - 8.0)))
	_menu_t = MENU_EVERY


func _close_menu() -> void:
	if _menu != null:
		_menu.visible = false


func is_menu_open() -> bool:
	return _menu != null and _menu.visible


func _refresh_menu() -> void:
	var sim = colony.sim
	var t = _mt
	var col = int(t.get("col", 0))
	_will_lbl.text = "Will %d / %d" % [int(sim.will), int(sim.will_max())]
	_food_lbl.text = "%d" % int(sim.food)
	# orders, when ants are selected
	var sel = selection()
	var has_sel = not sel.is_empty()
	_sel_lbl.visible = has_sel
	_gap_orders.visible = has_sel
	_rows["order"]["btn"].visible = has_sel
	_rows["free"]["btn"].visible = has_sel
	if has_sel:
		_sel_lbl.text = "  " + _sel_summary(sel)
		var o = _order_for(t, sel)
		if o[0] == "":
			_set_row("order", o[5].trim_suffix("."), "", -1.0, -1.0, 0.0, false, o[5])
		else:
			var oc = Orders.cost(o[0], sel.size())
			_set_row("order", o[5], "", -1.0, oc, 0.0, sim.food >= oc + sim.FOOD_RESERVE,
				"Right-click without Shift gives this order at once.")
		var ordered = 0
		for a in sel:
			if a.squad != 0:
				ordered += 1
		_set_row("free", "Free these ants  (%d under orders)" % ordered, OS.get_keycode_string(KEY_FREE), -1.0, -1.0, 0.0, ordered > 0,
			"They go home and choose their own work again.")
	# the powers
	var ant = _breed_source(t.get("ant"))
	if ant != null and not sim.ants.has(ant):
		ant = null
	for id in Sim.COMMANDS:
		var c = Sim.COMMANDS[id]
		var cd = float(sim.cmd_cd.get(id, 0.0))
		var cost = sim.cmd_cost(id)
		var fc = sim.food_cost(id)
		var ok = cd <= 0.0 and sim.will >= cost and sim.food >= fc + sim.FOOD_RESERVE
		var label = str(LABELS.get(id, c["name"]))
		var tip = "%s (%s): %s. %d Will and %d food; ready again %d s after use." % [c["name"], c["key"], c["tip"], int(ceil(cost)), int(ceil(fc)), int(round(sim.cmd_recharge(id)))]
		match id:
			"harvest":
				var near = _pile_near(col, 90)
				if near == null:
					ok = false
					label = "Harvest: no pile near here"
				elif t.get("kind") != "pile":
					label = "Harvest the nearest pile"
			"breed":
				if ant != null:
					label = "Breed from this ant  (mutation %d)" % int(sim.ms_of(ant))
			"strike":
				if not sim.rival.found:
					ok = false
					label = "Strike: rival nest not found yet"
				elif not sim.rival.alive():
					ok = false
					label = "Strike: the %s are broken" % sim.rival.name
				else:
					label = "Strike the %s" % sim.rival.name
		_set_row(id, label, str(c["key"]), cost, fc, cd, ok, tip)
	var bcd = float(sim._beacon_cd)
	_set_row("beacon", "Scent flag here: scouts search it", OS.get_keycode_string(KEY_BEACON), -1.0, sim.BEACON_FOOD, bcd,
		bcd <= 0.0 and sim.food >= sim.BEACON_FOOD + sim.FOOD_RESERVE,
		"Foragers leaving the nest are drawn to the flag and search around it. Two at a time, 25 s recharge.")
	var mg = int(sim.mutagen)
	var ml = ("Mutagen this ant  (%d left)" % mg) if ant != null else ("Mutagen  (%d left): pick an ant" % mg)
	_set_row("mutagen", ml, OS.get_keycode_string(KEY_MUTAGEN), -1.0, -1.0, 0.0, mg > 0 and ant != null,
		"The next 8 eggs are bred from this ant, each with a fresh mutation. Earn mutagen by repelling raids and reaching goals.")
	for i in _caste_btns.size():
		_caste_btns[i].set_pressed_no_signal(i == int(sim.caste_order))


func _choose(id: String) -> void:
	var sim = colony.sim
	var col = int(_mt.get("col", 0))
	var ant = _breed_source(_mt.get("ant"))
	if ant != null and not sim.ants.has(ant):
		ant = null
	_close_menu()
	match id:
		"order":
			_order(_mt)
		"free":
			_free_selection()
		"beacon":
			_act(func(): return sim.place_beacon(col), "")
		"mutagen":
			_act(func(): return sim.bless(ant), "")
		_:
			_cast(id, col, ant)


func _pile_near(col: int, reach: int):
	var best = null
	for p in colony.sim.piles:
		if p["amount"] > 8.0 and abs(p["x"] - col) < reach and (best == null or abs(p["x"] - col) < abs(best["x"] - col)):
			best = p
	return best


func _sel_summary(sel: Array) -> String:
	var n = [0, 0, 0]
	var ordered = 0
	for a in sel:
		n[clampi(a.caste, 0, 2)] += 1
		if a.squad != 0:
			ordered += 1
	var parts := []
	for i in 3:
		if n[i] > 0:
			parts.append("%d %s" % [n[i], CASTE_WORDS[i][0 if n[i] == 1 else 1]])
	var s = "%d ant%s selected: %s" % [sel.size(), "" if sel.size() == 1 else "s", ", ".join(parts)]
	if ordered > 0:
		s += "  (%d under orders)" % ordered
	return s


# ================================================================== the status line (bottom middle): messages and the selection
func _build_status() -> void:
	_status = PanelContainer.new()
	_status.add_theme_stylebox_override("panel", Kit.box("frame_small", STATUS_K, Vector2(10, 2)))
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_lbl = _label("", 15, INK)
	_status.add_child(_status_lbl)
	_status.visible = false
	add_child(_status)


func _update_status() -> void:
	var text := ""
	if _msg_t > 0.0:
		text = _msg
	elif not selected.is_empty():
		var sel = selection()
		if not sel.is_empty():
			text = "%s.   Right-click: order   Shift+right-click: menu   %s: free   Esc: clear" % [_sel_summary(sel), OS.get_keycode_string(KEY_FREE)]
	if text != _status_text:
		_status_text = text
		_status_lbl.text = text
		_status.visible = text != ""
		_status.reset_size()
	if _status.visible:
		var vs = get_viewport_rect().size
		var size = _status.get_combined_minimum_size()
		_status.position = Vector2(round((vs.x - size.x) * 0.5), vs.y - size.y - 14.0)


# ================================================================== building blocks (the owner's frames come from menu_kit.gd)
# A picture at `px` tall (aspect kept); with no picture, a blank of the same size so the columns still line up.
static func _icon(path: String, px: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = Art.tex(path) if path != "" else null
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func _label(text: String, size: int, color: Color) -> Label:
	var l = Kit.label(text, size, color)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


static func _pad(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c
