extends SceneTree
# Drives the player controls (scene/controls.gd) with real mouse and key events: a drag-box over some surface ants, a right-click order,
# Shift + right-click for the menu with orders, a plain right-click for the Director's menu, a power key. Prints what happened and,
# with a display, saves a screenshot at each stage (out=prefix: prefix_box.png, prefix_menu_sel.png, prefix_menu.png).
# Run: godot --headless --path game --script res://tests/controls_test.gd -- t=120
#      xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --resolution 1920x1057 \
#          --script res://tests/controls_test.gd -- t=120 out=/tmp/controls

var _f := 0
var _node
var _ctl
var _args := {"scene": "res://scene/colony.tscn", "t": "120", "at": "surface", "out": ""}
var _fails := 0
var _a := Vector2.ZERO
var _b := Vector2.ZERO
var _steps := []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_node = load(_args["scene"]).instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_f += 1
	if _f == 1:
		_node.debug_setup(_args)
		_node.paused = true
		_ctl = _node.views.get("controls")
		if _ctl == null:
			print("FAIL no controls view")
			quit(1)
			return false
	elif _f == 10:
		_pick_box()
		_mouse_button(MOUSE_BUTTON_LEFT, _a, true)
	elif _f == 11:
		_mouse_move((_a + _b) * 0.5)
	elif _f == 12:
		_mouse_move(_b)
	elif _f == 16:
		_shot("box")
	elif _f == 17:
		_mouse_button(MOUSE_BUTTON_LEFT, _b, false)
	elif _f == 19:
		_check(_ctl.selected.size() > 0, "drag-box selects ants (%d)" % _ctl.selected.size())
		# a right-click on open ground away from the box: a guard order (an ant carrying food would be skipped by it: set the loads down)
		for a in _ctl.selection():
			a.carry = 0.0
			a.spoil = 0.0
			a.dig_timer = 0.0
		_node.sim.food = max(_node.sim.food, 40.0)
		var sq0 = _node.sim.squads.size()
		var p = Vector2(_b.x + 120.0, _b.y)
		_mouse_button(MOUSE_BUTTON_RIGHT, p, true)
		_mouse_button(MOUSE_BUTTON_RIGHT, p + Vector2(2, 1), false)
		_steps.append(sq0)
	elif _f == 21:
		_check(_node.sim.squads.size() > int(_steps[0]), "right-click gives the selection an order (%d squads: %s)" % [_node.sim.squads.size(), _ctl._msg])
		_check(not _ctl.is_menu_open(), "a plain right-click with a selection opens no menu")
		# a right-drag pans the camera and gives no order
		var sq1 = _node.sim.squads.size()
		var c0 = _node.cam.position
		_mouse_button(MOUSE_BUTTON_RIGHT, _b, true)
		_mouse_move(_b + Vector2(40, 0))
		_mouse_move(_b + Vector2(90, 0))
		_mouse_button(MOUSE_BUTTON_RIGHT, _b + Vector2(90, 0), false)
		_steps.append([sq1, c0])
	elif _f == 24:
		_check(_node.sim.squads.size() == int(_steps[1][0]), "a right-drag gives no order")
		_check(_node.cam.position.distance_to(_steps[1][1]) > 5.0, "a right-drag still pans the camera")
		_check(not _ctl.is_menu_open(), "a right-drag opens no menu")
		# Shift + right-click: the menu, with the orders on top
		_mouse_button(MOUSE_BUTTON_RIGHT, _a + Vector2(30, -20), true, true)
		_mouse_button(MOUSE_BUTTON_RIGHT, _a + Vector2(30, -20), false, true)
	elif _f == 30:
		_check(_ctl.is_menu_open(), "Shift + right-click opens the menu")
		_shot("menu_sel")
	elif _f == 31:
		_key(KEY_ESCAPE)
	elif _f == 32:
		_check(not _ctl.is_menu_open(), "Esc closes the menu")
		_check(_ctl.selected.size() > 0, "... and keeps the selection")
		_key(KEY_ESCAPE)
	elif _f == 33:
		_check(_ctl.selected.is_empty(), "a second Esc clears the selection")
		_node.sim.will = _node.sim.will_max()
		var p = _node.get_viewport_rect().size * Vector2(0.45, 0.4)
		_mouse_button(MOUSE_BUTTON_RIGHT, p, true)
		_mouse_button(MOUSE_BUTTON_RIGHT, p, false)
	elif _f == 40:
		_check(_ctl.is_menu_open(), "a right-click with nobody selected opens the Director's menu")
		_shot("menu")
	elif _f == 41:
		# a left-click outside the menu closes it and does nothing else
		_mouse_button(MOUSE_BUTTON_LEFT, Vector2(20, 20), true)
		_mouse_button(MOUSE_BUTTON_LEFT, Vector2(20, 20), false)
	elif _f == 43:
		_check(not _ctl.is_menu_open(), "a click outside closes the menu")
		var w0 = _node.sim.will
		_key(KEY_J)                  # Surge
		_steps.append(w0)
	elif _f == 45:
		_check(_node.sim.will < float(_steps[2]) and _node.sim.surge_t > 0.0, "the Surge key casts Surge (Will %d -> %d)" % [int(_steps[2]), int(_node.sim.will)])
		# a left-click on one ant selects only it; on empty sky, nobody
		var one = _ant_screen()
		if one != Vector2.INF:
			_mouse_button(MOUSE_BUTTON_LEFT, one, true)
			_mouse_button(MOUSE_BUTTON_LEFT, one, false)
	elif _f == 47:
		_check(_ctl.selected.size() == 1, "a click on an ant selects that one (%d)" % _ctl.selected.size())
		var sky = _node.get_viewport_rect().size * Vector2(0.6, 0.22)
		_mouse_button(MOUSE_BUTTON_LEFT, sky, true)
		_mouse_button(MOUSE_BUTTON_LEFT, sky, false)
	elif _f == 49:
		_check(_ctl.selected.is_empty(), "a click on empty sky clears the selection")
		print("controls test: %d failed" % _fails)
		quit(1 if _fails > 0 else 0)
	return false


# A box (screen px) around the surface ants nearest the middle of the screen.
func _pick_box() -> void:
	var vs = _node.get_viewport_rect().size
	var mid = vs * 0.5
	var pts := []
	for a in _node.sim.ants:
		if not _node.grid.is_surface_cell(a.x, a.y):
			continue
		var s = _ctl._spot(a, _node.sim.ant_pos(a), _ctl._pick_context())
		var sp = _to_screen(Vector2(s.x, s.y))
		if Rect2(Vector2.ZERO, vs).grow(-60).has_point(sp):
			pts.append(sp)
	pts.sort_custom(func(p, q): return p.distance_to(mid) < q.distance_to(mid))
	if pts.is_empty():
		_a = mid - Vector2(200, 120)
		_b = mid + Vector2(200, 120)
		return
	var r = Rect2(pts[0], Vector2.ZERO)
	for i in min(6, pts.size()):
		r = r.expand(pts[i])
	r = r.grow(40)
	_a = r.position
	_b = r.end


func _ant_screen() -> Vector2:
	var vs = _node.get_viewport_rect().size
	for a in _node.sim.ants:
		var s = _ctl._spot(a, _node.sim.ant_pos(a), _ctl._pick_context())
		var sp = _to_screen(Vector2(s.x, s.y))
		if Rect2(Vector2.ZERO, vs).grow(-100).has_point(sp) and _ctl._pick_ant(Vector2(s.x, s.y)) == a:
			return sp
	return Vector2.INF


func _to_screen(w: Vector2) -> Vector2:
	return _node.get_canvas_transform() * w


func _win(p: Vector2) -> Vector2:
	return root.get_final_transform() * p


func _mouse_button(b: int, p: Vector2, down: bool, shift: bool = false) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = b
	ev.pressed = down
	ev.position = _win(p)
	ev.global_position = ev.position
	ev.shift_pressed = shift
	ev.button_mask = (MOUSE_BUTTON_MASK_LEFT if b == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
	_last = ev.position
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


var _last := Vector2.ZERO


func _mouse_move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _win(p)
	ev.relative = ev.position - _last
	_last = ev.position
	ev.global_position = ev.position
	ev.button_mask = Input.get_mouse_button_mask()
	Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _key(k: int) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)
	Input.flush_buffered_events()


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _shot(tag: String) -> void:
	if _args["out"] == "" or DisplayServer.get_name() == "headless":
		return
	var img = root.get_texture().get_image()
	var path = "%s_%s.png" % [_args["out"], tag]
	img.save_png(path)
	print("saved ", path)
