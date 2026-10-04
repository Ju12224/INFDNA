extends Node2D
# The colony screen. It owns the simulation and the camera, steps the sim, and stacks the views in one fixed order, back to front:
#   sky (with the hills) -> surface (trees, rocks) -> soil (the dirt and the tunnels) -> nest -> units (ants) -> effects -> interface
# Every view is its own script under scene/, gets `colony` before it is added, and draws itself; anything without the owner's art
# is left out. A view script that does not exist yet is skipped. Coordinates are world pixels: a grid cell is WorldGrid.CELL (6 px)
# square and y grows downward.
#
# What a view may use: colony.sim, colony.grid (= sim.grid), colony.cam, colony.day (scene/day.gd), colony.view_rect(),
# colony.ground_y(), colony.cam_center(), colony.zoom(). A view with a reset() function has it called when a new colony starts.

const Sim = preload("res://core/colony_sim.gd")
const Day = preload("res://scene/day.gd")
const BugReport = preload("res://core/bug_report.gd")
const WorldGrid = preload("res://core/world_grid.gd")

const STEP = 0.1          # sim seconds per sim step
const MAX_STEPS = 6       # sim steps per frame at most, so a slow frame never snowballs
const SPEEDS = [1.0, 3.0, 10.0]
const ZOOM_MIN = 0.15
const ZOOM_MAX = 6.0
const ZOOM_START = 2.5
const ZOOM_STEP = 1.15
const PAN_KEYS = 900.0    # screen pixels per second
const REPORT_EVERY = 60.0
const SKY_LAYER = -10
const UI_LAYER = 10
const SKY_VIEW = "res://scene/sky_view.gd"
const HUD = "res://scene/hud.gd"
# the views in the world, back to front: [name, script, z_index]
const WORLD_VIEWS = [
	["surface", "res://scene/surface_view.gd", 10],
	["soil", "res://scene/soil_view.gd", 20],
	["nest", "res://scene/nest_view.gd", 30],
	["units", "res://scene/units_view.gd", 40],
	["effects", "res://scene/effects_view.gd", 50],
]

var sim
var grid
var day := Day.new()
var cam: Camera2D
var speed := 1.0
var paused := false
var colonies := 0
var views := {}           # name -> view node
var force_ph := -1.0      # >= 0 pins the time of day (screenshots)
var _acc := 0.0
var _report_t := 0.0
var _drag := false


func _ready() -> void:
	get_tree().auto_accept_quit = false
	cam = Camera2D.new()
	cam.zoom = Vector2.ONE * ZOOM_START
	add_child(cam)
	_new_colony()
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = SKY_LAYER
	add_child(sky_layer)
	_add_view("sky", SKY_VIEW, sky_layer, 0)
	for v in WORLD_VIEWS:
		_add_view(v[0], v[1], self, v[2])
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = UI_LAYER
	add_child(ui_layer)
	_add_view("hud", HUD, ui_layer, 0)


func _add_view(view_name: String, path: String, parent: Node, z: int) -> void:
	if not ResourceLoader.exists(path):
		return
	var v = load(path).new()
	v.name = view_name
	v.set("colony", self)
	if v is CanvasItem:
		v.z_index = z
	parent.add_child(v)
	views[view_name] = v


func _new_colony() -> void:
	colonies += 1
	sim = Sim.new(randi() % 1000000, "well_rounded")
	grid = sim.grid
	BugReport.colony_started()
	var e = grid.center(int(grid.entrance.x), int(grid.entrance.y))
	cam.position = e + Vector2(0, 60)
	for v in views.values():
		if v.has_method("reset"):
			v.reset()


func _process(delta: float) -> void:
	BugReport.frame(delta)
	if not paused:
		_acc = min(_acc + delta * speed, STEP * MAX_STEPS)
		var n := 0
		while _acc >= STEP and n < MAX_STEPS:
			sim.step(STEP)
			_acc -= STEP
			n += 1
	if sim.collapsed:
		_new_colony()
	day.update(sim.time, sim.rain, sim.overcast)
	if force_ph >= 0.0:
		day.ph = force_ph
		day.elev = -cos(force_ph * TAU)
		day.night = smoothstep(0.12, -0.28, day.elev)
	_pan_keys(delta)
	_report_t += delta
	if _report_t >= REPORT_EVERY:
		_report_t = 0.0
		BugReport.write("running")


func _pan_keys(delta: float) -> void:
	var d := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		d.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		d.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		d.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		d.y += 1
	if d != Vector2.ZERO:
		cam.position += d * PAN_KEYS * delta / zoom()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag = event.pressed
	elif event is InputEventMouseMotion and _drag:
		cam.position -= event.relative / zoom()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				paused = not paused
			KEY_1:
				speed = SPEEDS[0]
			KEY_2:
				speed = SPEEDS[1]
			KEY_3:
				speed = SPEEDS[2]


# Zoom by k, keeping the world point under the mouse where it is.
func _zoom_at(screen_pos: Vector2, k: float) -> void:
	var before = _screen_to_world(screen_pos)
	cam.zoom = Vector2.ONE * clamp(zoom() * k, ZOOM_MIN, ZOOM_MAX)
	cam.position += before - _screen_to_world(screen_pos)


func _screen_to_world(p: Vector2) -> Vector2:
	return cam.position + (p - get_viewport_rect().size * 0.5) / zoom()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not BugReport.closing():
			BugReport.write("game closed", true)
		get_tree().quit()


# ---- for the views
func zoom() -> float:
	return cam.zoom.x


func cam_center() -> Vector2:
	return cam.position


# The part of the world on screen, grown by `margin` world pixels on every side.
func view_rect(margin: float = 0.0) -> Rect2:
	var size = get_viewport_rect().size / zoom()
	return Rect2(cam.position - size * 0.5, size).grow(margin)


# World y of the original ground line (the horizon the hills stand on).
func ground_y() -> float:
	return grid._base * WorldGrid.CELL


# ---- screenshots and tests (tests/shot.gd): t = sim seconds to run first, zoom, at = nest | surface | x,y (cells), ph = time of day
func debug_setup(args: Dictionary) -> void:
	var t = float(args.get("t", "0"))
	while sim.time < t and not sim.collapsed:
		sim.step(STEP)
	if args.has("zoom"):
		cam.zoom = Vector2.ONE * float(args["zoom"])
	var at = str(args.get("at", ""))
	if at == "nest":
		cam.position = grid.center(int(grid.chamber.x), int(grid.chamber.y))
	elif at == "surface":
		cam.position = grid.center(int(grid.entrance.x), int(grid.entrance.y)) + Vector2(0, -80)
	elif at.find(",") > 0:
		var xy = at.split(",")
		cam.position = grid.center(int(xy[0]), int(xy[1]))
	if args.has("ph"):
		force_ph = float(args["ph"])
	if args.has("paused"):
		paused = true
