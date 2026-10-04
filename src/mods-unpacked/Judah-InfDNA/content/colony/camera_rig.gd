extends Camera2D
# Pan (WASD / arrows / right- or middle-drag), zoom (wheel, toward cursor).
# The world is infinite sideways, so x is never clamped.

var world_size := Vector2(1560, 900)
var min_zoom := 0.07      # far in: the meadow's back rows only open near the bottom of this (meadow_depth.gd), and the view is small there
var max_zoom := 1.0
var _drag := false
var _shake := 0.0


func setup(ws: Vector2) -> void:
	world_size = ws
	var vp = get_viewport_rect().size
	var base_max = max(ws.x / vp.x, (ws.y + 300.0) / vp.y) * 1.25
	max_zoom = base_max * 1.7              # far enough out to see whole giant trees
	zoom = Vector2.ONE * base_max * 0.62
	position = Vector2(ws.x * 0.5, ws.y * 0.42)
	current = true


func kick(amount: float) -> void:
	_shake = clamp(max(_shake, amount), 0.0, 1.0)


func _process(delta: float) -> void:
	_shake = max(0.0, _shake - delta * 1.7)
	offset = Vector2(randf() * 2.0 - 1.0, randf() * 2.0 - 1.0) * _shake * _shake * 26.0
	var dir = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	position += dir * 900.0 * zoom.x * delta
	_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 0.88)
		elif event.button_index == BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 0.88)
		elif event.button_index in [BUTTON_RIGHT, BUTTON_MIDDLE]:
			_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		position -= event.relative * zoom.x
		_clamp()


func _zoom_at(screen_pos: Vector2, f: float) -> void:
	var before = get_canvas_transform().affine_inverse().xform(screen_pos)
	zoom = Vector2.ONE * clamp(zoom.x * f, min_zoom, max_zoom)
	force_update_scroll()
	var after = get_canvas_transform().affine_inverse().xform(screen_pos)
	position += before - after
	_clamp()


func _clamp() -> void:
	position.y = clamp(position.y, -1700.0, world_size.y)
