extends Node2D
# InfDNA colony mode: its own scene, no player character. The colony runs
# itself; the player steers through focus, brood, and speed.

const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
const Baker = preload("res://mods-unpacked/Judah-InfDNA/content/colony/sprite_baker.gd")
const WorldView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/world_view.gd")
const AntView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ant_view.gd")
const EnemyView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/enemy_view.gd")
const LayersView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/layers_view.gd")
const Perf = preload("res://mods-unpacked/Judah-InfDNA/content/colony/perf.gd")
const AmbientView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ambient_view.gd")
const UndergroundUI = preload("res://mods-unpacked/Judah-InfDNA/content/colony/underground_ui.gd")
const Sfx = preload("res://mods-unpacked/Judah-InfDNA/content/colony/sfx.gd")
const CameraRig = preload("res://mods-unpacked/Judah-InfDNA/content/colony/camera_rig.gd")
const Hud = preload("res://mods-unpacked/Judah-InfDNA/content/colony/hud.gd")
const PredatorView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/predator_view.gd")
const DirectorView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/director_view.gd")
const WeatherView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/weather_view.gd")
const LightView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/light_view.gd")
const DayCycle = preload("res://mods-unpacked/Judah-InfDNA/content/colony/day_cycle.gd")
const WatchCam = preload("res://mods-unpacked/Judah-InfDNA/content/colony/watch_cam.gd")
const SELECT_SCENE = "res://mods-unpacked/Judah-InfDNA/content/colony/queen_select.tscn"
const TITLE_SCENE = "res://ui/menus/title_screen/title_screen.tscn"
const MAX_STEP = 0.05
const FAST_STEP = 0.1          # sim step above 4x (movement carries its remainder, so the step size is safe)
# sim time allowed per rendered frame: the frame rate holds, the speed bends (perf.budget, lowered by the optimizer)
const SPEEDS = [0.0, 1.0, 2.0, 4.0, 10.0]

var sim
var baker
var world_view
var ant_view
var enemy_view
var layers_view
var perf               # the optimizer (perf.gd): adaptive quality
var _weather
var day                # day_cycle.gd: sun, moon and the colour of the surface light
var cam
var hud
var selected = null
var speed := 1.0
var eff_speed := 1.0           # sim seconds actually simulated per real second (HUD shows it when it falls short)
var _debt := 0.0
var _prune_timer := 10.0
var _overlay: Node2D
var shop_open := false
var sfx
var ug                 # underground_ui.gd: depth gauge, nest panel, room labels
var watch              # watch_cam.gd: the self-directing camera of watch mode (V)
var watch_mode := false
var _watch_saved := {}
var _shop_noted := false
var armed := ""              # a command waiting for a click on the ground (rally, harvest)
# view layers (HUD "Layers" panel and the P/C/F/T/H keys); see set_layer
var layer_state := {"trails": true, "castes": true, "fights": true, "tasks": false, "health": false, "follow": false, "light": true}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var qid = Engine.get_meta("infdna_queen") if Engine.has_meta("infdna_queen") else "well_rounded"
	sim = Sim.new(0, qid)
	perf = Perf.new()
	perf.scene = self
	day = DayCycle.new()
	day.update(sim.time)
	baker = Baker.new()
	add_child(baker)

	world_view = WorldView.new()
	world_view.sim = sim
	world_view.baker = baker
	add_child(world_view)
	world_view.sky.perf = perf
	world_view.ground.perf = perf
	world_view.sky.day = day

	_overlay = Node2D.new()     # food, trails, eggs, queen: above the dirt
	_overlay.connect("draw", self, "_draw_overlay")
	add_child(_overlay)

	ant_view = AntView.new()
	ant_view.sim = sim
	ant_view.baker = baker
	ant_view.perf = perf
	ant_view.day = day
	add_child(ant_view)

	enemy_view = EnemyView.new()
	enemy_view.sim = sim
	enemy_view.perf = perf
	add_child(enemy_view)
	ant_view.enemy_view = enemy_view

	cam = CameraRig.new()
	add_child(cam)
	cam.setup(world_view.world_size())
	ant_view.cam = cam
	ant_view.ground = world_view.ground
	world_view.cam = cam

	var pview = PredatorView.new()      # the bird, before the light pass so night tints it
	pview.sim = sim
	pview.cam = cam
	pview.ground = world_view.ground
	add_child(pview)

	var weather = WeatherView.new()    # rain streaks and splashes (drawn above the light so they stay bright)
	weather.sim = sim
	weather.cam = cam
	weather.ground = world_view.ground
	weather.day = day
	weather.perf = perf
	_weather = weather
	var light = LightView.new()        # the colour of the surface light, multiplied over sky, ground and units
	light.sim = sim
	light.cam = cam
	light.ground = world_view.ground
	light.day = day
	add_child(light)
	add_child(weather)

	layers_view = LayersView.new()     # fight / task / health marks, above the ants and raiders
	layers_view.sim = sim
	layers_view.cam = cam
	layers_view.ant_view = ant_view
	layers_view.show_fights = layer_state["fights"]
	layers_view.show_tasks = layer_state["tasks"]
	layers_view.show_health = layer_state["health"]
	add_child(layers_view)

	var dview = DirectorView.new()      # the rally flag and harvest marker
	dview.sim = sim
	dview.cam = cam
	dview.ground = world_view.ground
	add_child(dview)

	var ambient = AmbientView.new()     # bees and butterflies over the meadow
	ambient.sim = sim
	ambient.cam = cam
	ambient.ground = world_view.ground
	ambient.perf = perf
	ambient.day = day
	add_child(ambient)

	sfx = Sfx.new()
	sfx.sim = sim
	add_child(sfx)

	hud = Hud.new()
	hud.scene = self
	add_child(hud)
	ug = UndergroundUI.new()      # depth gauge, nest panel (U), room labels, level navigation (PgUp / PgDn)
	ug.scene = self
	add_child(ug)
	watch = WatchCam.new()
	watch.scene = self
	add_child(watch)
	add_child(perf)           # last: its first apply() reaches every view and the HUD


func _process(delta: float) -> void:
	day.update(sim.time, sim.rain)
	if sim.shop_pending and not shop_open and not sim.collapsed:
		if not watch_mode:
			open_shop()
		elif not _shop_noted:
			_shop_noted = true        # watch mode never stops the colony for the Lab: it waits until you leave
			sim.toasts.append({"text": "The Lab is open (press V to leave watch mode and shop)", "t": 5.0})
	if not sim.shop_pending:
		_shop_noted = false
	# Fixed-budget stepping: simulate what the speed asks for, but never spend more than BUDGET_US
	# per frame. A slow frame used to make the engine run extra ticks (each running more sim), so
	# 4x snowballed into a stutter. Now the frame rate holds and the effective speed bends instead.
	var done := 0.0
	if shop_open or speed <= 0.0 or sim.collapsed:
		_debt = 0.0
	else:
		_debt += min(delta, 0.1) * speed
		var step = MAX_STEP if speed <= 4.0 else FAST_STEP
		var t0 = OS.get_ticks_usec()
		while _debt > 0.0005:
			var dt = min(_debt, step)
			sim.step(dt)
			_debt -= dt
			done += dt
			if OS.get_ticks_usec() - t0 > perf.budget:
				break
		_debt = min(_debt, 0.25)     # give up on a backlog instead of chasing it
	eff_speed = lerp(eff_speed, done / max(delta, 0.001), 0.1) if speed > 0.0 else 0.0
	if sim.shake > 0.0:
		cam.kick(sim.shake)
		sim.shake = 0.0
	if layer_state["follow"] and selected != null and sim.ants.has(selected):
		var d = ant_view._depth(selected.id, ant_view.lane_of(selected, selected.id))
		cam.position = cam.position.linear_interpolate(sim.ant_pos(selected) + Vector2(0, d[0] - 30.0), clamp(delta * 5.0, 0.0, 1.0))
	_overlay.update()
	ant_view.selected = selected
	_prune_timer -= delta
	if _prune_timer <= 0.0:
		_prune_timer = 10.0
		var alive := {sim.queen_genome.uid: true}
		for a in sim.ants:
			alive[a.genome.uid] = true
		for e in sim.eggs:
			alive[e["genome"].uid] = true
		# keep ancestor thumbnails for the lineage panel
		if hud.is_evolution_open():
			for e in sim.top_genomes(3):
				for n in e["genome"].ancestry():
					alive[n.uid] = true
			if selected != null:
				for n in selected.genome.ancestry():
					alive[n.uid] = true
		baker.prune(alive)


func _draw_overlay() -> void:
	world_view.draw_overlay(_overlay)


func _unhandled_input(event: InputEvent) -> void:
	if watch_mode:
		_watch_input(event)
	if armed != "" and event is InputEventMouseButton and event.pressed:
		if event.button_index == BUTTON_LEFT:
			var ax = int(floor(get_global_mouse_position().x / sim.grid.CELL))
			var aid = armed
			set_armed("")
			sim.cast(aid, ax, selected)
		elif event.button_index == BUTTON_RIGHT:
			set_armed("")
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		selected = ant_view.pick(get_global_mouse_position(), 30.0)
		if watch_mode and selected != null:
			watch.follow(selected)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_V:
				set_watch(not watch_mode)
			KEY_N:
				show_new_strain()
			KEY_R:
				command("rally", true)
			KEY_E:
				command("harvest", true)
			KEY_Z:
				command("recall", true)
			KEY_J:
				command("surge", true)
			KEY_M:
				command("breed", true)
			KEY_ESCAPE:
				if armed != "":
					set_armed("")
				elif watch_mode:
					set_watch(false)
				elif hud.is_evolution_open():
					hud.toggle_evolution()
				elif shop_open:
					close_shop()
				else:
					go_to_menu()
			KEY_SPACE:
				set_speed(0.0 if speed > 0.0 else 1.0)
			KEY_1:
				set_speed(1.0)
			KEY_2:
				set_speed(2.0)
			KEY_3:
				set_speed(4.0)
			KEY_4:
				set_speed(10.0)
			KEY_B:
				sim.place_beacon(int(floor(get_global_mouse_position().x / sim.grid.CELL)))
			KEY_G:
				sim.bless(selected)
			KEY_O:
				var shown := 0
				for g in sim.GOALS:
					if not sim.goals_done.has(g["id"]) and shown < 3:
						shown += 1
						sim.toasts.append({"text": "Goal: %s (+%d food)" % [g["name"], g["food"]], "t": 6.0})
			KEY_P:
				toggle_layer("trails")
			KEY_C:
				toggle_layer("castes")
			KEY_F:
				toggle_layer("fights")
			KEY_T:
				toggle_layer("tasks")
			KEY_H:
				toggle_layer("health")
			KEY_X:
				toggle_layer("follow")
			KEY_K:
				toggle_layer("light")
			KEY_L:
				hud.toggle_evolution()


func open_shop() -> void:
	if shop_open or sim.hostile_count() > 0:
		return
	if sim.shop_pending or sim.offers.empty():
		sim.open_shop()
	shop_open = true
	hud.show_shop(true)


func close_shop() -> void:
	shop_open = false
	hud.show_shop(false)


# A director command from a button or key. Commands that need a place arm and wait for a click, unless a key was
# pressed with the cursor already over the spot (`at_cursor`).
func command(id: String, at_cursor: bool = false) -> void:
	if shop_open or sim.collapsed:
		return
	var c = sim.COMMANDS[id]
	if c["target"] and not at_cursor:
		set_armed("" if armed == id else id)
		return
	var x = int(floor(get_global_mouse_position().x / sim.grid.CELL))
	if sim.cast(id, x, selected):
		set_armed("")


func set_armed(id: String) -> void:
	armed = id
	Input.set_default_cursor_shape(Input.CURSOR_CROSS if id != "" else Input.CURSOR_ARROW)


# The first living ant of the newest new body plan (see colony_sim._note_strain), or null.
func newest_strain_ant(newer_than: float = -1.0):
	for i in range(sim.strain_events.size() - 1, -1, -1):
		var ev = sim.strain_events[i]
		if ev["t"] <= newer_than or sim.time - ev["t"] > 150.0:
			break
		for a in sim.ants:
			if a.genome.uid == ev["uid"]:
				return a
	return null


# N: select the newest strain's ant and bring the camera to it.
func show_new_strain() -> void:
	var a = newest_strain_ant()
	if a == null:
		sim.toasts.append({"text": "No new strain to look at right now.", "t": 3.0})
		return
	selected = a
	var d = ant_view._depth(a.id, ant_view.lane_of(a, a.id))
	cam.position = sim.ant_pos(a) + Vector2(0, d[0] - 30.0)
	cam.zoom = Vector2.ONE * clamp(0.5, cam.min_zoom, cam.max_zoom)
	if watch_mode:
		watch.follow(a)


# Watch mode (V): hide the HUD, switch the busy layers off and let the camera direct itself.
func set_watch(on: bool) -> void:
	if on == watch_mode:
		return
	watch_mode = on
	if on:
		if shop_open:
			close_shop()
		_watch_saved = layer_state.duplicate()
		for k in ["castes", "tasks", "health", "follow"]:
			set_layer(k, false)
		selected = null
	else:
		for k in _watch_saved:
			set_layer(k, _watch_saved[k])
	hud.set_watch(on)
	ug.set_watch(on)
	watch.set_active(on)


func _watch_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN, BUTTON_RIGHT, BUTTON_MIDDLE]:
			watch.note_input(2.0 if event.button_index in [BUTTON_WHEEL_UP, BUTTON_WHEEL_DOWN] else 0.0)
	elif event is InputEventMouseMotion and (event.button_mask & (BUTTON_MASK_RIGHT | BUTTON_MASK_MIDDLE)) != 0:
		watch.note_input()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.scancode in [KEY_HOME, KEY_Q, KEY_PAGEUP, KEY_PAGEDOWN]:
			watch.note_input(4.0)


func toggle_layer(key: String) -> void:
	set_layer(key, not layer_state[key])


func set_layer(key: String, on: bool) -> void:
	if not layer_state.has(key) or layer_state[key] == on:
		return
	layer_state[key] = on
	match key:
		"trails":
			world_view.show_trails = on
		"castes":
			ant_view.show_castes = on
		"follow":
			pass          # read in _process
		"light":
			day.locked = not on          # off = always midday
		_:
			layers_view.set_layer(key, on)
	if hud != null:
		hud.sync_layer(key, on)


func set_speed(s: float) -> void:
	speed = s
	if hud != null:
		hud.sync_speed(s)


func restart() -> void:
	var _e = get_tree().change_scene(SELECT_SCENE)


func go_to_menu() -> void:
	if ResourceLoader.exists(TITLE_SCENE):
		var _e = get_tree().change_scene(TITLE_SCENE)
	else:
		get_tree().quit()
