extends Node2D
# The colony screen. It owns the simulation and the camera, steps the sim, and stacks the views in one fixed order, back to front:
#   sky (with the hills) -> surface (trees, rocks) -> soil (the dirt and the tunnels) -> nest -> units (ants) -> creatures
#   -> [the surface view's thick grass, z 47, standing in front of the ants and creatures] -> effects -> weather -> interface
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
const Run = preload("res://scene/run.gd")

const STEP = 0.1          # sim seconds per sim step
const MAX_STEPS = 6       # sim steps per frame at most, so a slow frame never snowballs
const SPEEDS = [1.0, 3.0, 10.0]
const ZOOM_MIN = 0.15
const ZOOM_MAX = 6.0
const ZOOM_START = 2.5
const ZOOM_STEP = 1.18
const ZOOM_EASE = 12.0    # how fast the zoom closes on its target (per second): smooth, never a jump
const ZOOM_MAX_RATE = 2.5  # at most e^2.5 (about 12x) zoom change per second
const PAN_EASE = 14.0     # the same for key panning
const GLIDE_DRAG = 5.0    # how fast a flung drag slows down
const PAN_KEYS = 900.0    # screen pixels per second
const REPORT_EVERY = 60.0
const SKY_ROOM = 2400.0   # world px of sky the camera may show above the ground line
const SKY_LAYER = -10
const UI_LAYER = 10
const SKY_VIEW = "res://scene/sky_view.gd"
const HUD = "res://scene/hud.gd"
const CONTROLS = "res://scene/controls.gd"       # selecting ants, orders and powers (on the interface layer, above the HUD)
const RUN_END = "res://scene/run_end.tscn"       # the end-of-run screen; without it a collapse starts a new colony at once
# the views in the world, back to front: [name, script, z_index]
const WORLD_VIEWS = [
	["surface", "res://scene/surface_view.gd", 10],
	["soil", "res://scene/soil_view.gd", 20],
	["nest", "res://scene/nest_view.gd", 30],
	["units", "res://scene/units_view.gd", 40],
	["creatures", "res://scene/creatures_view.gd", 45],
	["effects", "res://scene/effects_view.gd", 50],
	["weather", "res://scene/weather_view.gd", 55],
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
var _zoom_target := ZOOM_START
var _zoom_anchor := Vector2.ZERO   # screen point the zoom keeps still (the mouse when it was rolled)
var _vel := Vector2.ZERO           # world px per second: key panning and the glide after a drag


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
	_add_view("controls", CONTROLS, ui_layer, 1)
	_add_view("ambience", "res://scene/ambience.gd", self, 0)      # sound; skipped until the script exists
	_add_view("watch", "res://scene/watch_cam.gd", self, 0)        # watch mode (a self-directing camera); skipped until it exists
	_add_view("depth_gauge", "res://scene/depth_gauge.gd", ui_layer, 0)   # depth gauge, room labels, minimap; skipped until it exists


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
	sim = Sim.new(randi() % 1000000, Run.queen_id, Run.heirloom, Run.kin)
	Run.equip(sim)
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
		Run.last_sim = sim
		if ResourceLoader.exists(RUN_END):
			get_tree().change_scene_to_file(RUN_END)
			return
		_new_colony()
	day.update(sim.time, sim.rain, sim.overcast, force_ph)
	_move_camera(delta)
	_clamp_camera()
	_report_t += delta
	if _report_t >= REPORT_EVERY:
		_report_t = 0.0
		BugReport.write("running")


# The camera eases toward where it is told to be: the zoom closes on its target around the point under the mouse, key panning
# speeds up and slows down softly, and a drag let go of keeps gliding for a moment.
func _move_camera(delta: float) -> void:
	var zmin = min_zoom()
	_zoom_target = clamp(_zoom_target, zmin, ZOOM_MAX)           # a taller window raises the floor: never show the void under the bedrock
	if zoom() < zmin:
		cam.zoom = Vector2.ONE * zmin
	var z = zoom()
	if abs(z - _zoom_target) > 0.0005:
		# eased in log space (every doubling takes the same time) and capped, so a long zoom is a steady glide
		var step = (log(_zoom_target) - log(z)) * (1.0 - exp(-ZOOM_EASE * delta))
		var cap = ZOOM_MAX_RATE * delta
		var nz = z * exp(clamp(step, -cap, cap))
		var before = _screen_to_world(_zoom_anchor)
		cam.zoom = Vector2.ONE * nz
		cam.position += before - _screen_to_world(_zoom_anchor)
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
		_vel = _vel.lerp(d.normalized() * PAN_KEYS / zoom(), 1.0 - exp(-PAN_EASE * delta))
	elif not _drag:
		_vel = _vel.lerp(Vector2.ZERO, 1.0 - exp(-GLIDE_DRAG * delta))
	if not _drag:
		cam.position += _vel * delta


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / ZOOM_STEP)
		elif event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag = event.pressed
			if _drag:
				_vel = Vector2.ZERO
	elif event is InputEventMouseMotion and _drag:
		cam.position -= event.relative / zoom()
		_vel = _vel.lerp(-event.relative / zoom() / max(get_process_delta_time(), 0.001), 0.3)
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


# The view never goes below the bottom of the world (nothing is drawn there) nor far up into empty sky, nor past its left
# or right edge (the world is WorldGrid.WORLD_W columns wide); a screen wider than the world is centred on it.
func _clamp_camera() -> void:
	var vs = get_viewport_rect().size * 0.5 / zoom()
	var bottom = grid.H * WorldGrid.CELL
	var top = ground_y() - SKY_ROOM
	cam.position.y = clamp(cam.position.y, top + vs.y, max(top + vs.y, bottom - vs.y))
	var left = grid.sim_l() * WorldGrid.CELL
	var right = (grid.sim_r() + 1) * WorldGrid.CELL
	var x = (left + right) * 0.5 if right - left <= 2.0 * vs.x else clamp(cam.position.x, left + vs.x, right - vs.x)
	if x != cam.position.x:
		cam.position.x = x
		_vel.x = 0.0           # a glide stops at the edge instead of pushing against it


# Zoom by k (eased over the next frames), keeping the world point under the mouse where it is.
func _zoom_at(screen_pos: Vector2, k: float) -> void:
	_zoom_target = clamp(_zoom_target * k, min_zoom(), ZOOM_MAX)
	_zoom_anchor = screen_pos


# Zoomed out no further than the world is tall (sky room included), so nothing empty shows below the bedrock, nor wider
# than the world is wide.
func min_zoom() -> float:
	var vs = get_viewport_rect().size
	return max(ZOOM_MIN, max(vs.y / (grid.H * WorldGrid.CELL - ground_y() + SKY_ROOM), vs.x / (grid.W * WorldGrid.CELL)))


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
		_zoom_target = float(args["zoom"])
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
