extends Node2D
# InfDNA colony mode: its own scene, no player character. The colony runs
# itself; the player steers through focus, brood, and speed.

const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
const Baker = preload("res://mods-unpacked/Judah-InfDNA/content/colony/sprite_baker.gd")
const WorldView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/world_view.gd")
const AntView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ant_view.gd")
const EnemyView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/enemy_view.gd")
const LayersView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/layers_view.gd")
const Sfx = preload("res://mods-unpacked/Judah-InfDNA/content/colony/sfx.gd")
const CameraRig = preload("res://mods-unpacked/Judah-InfDNA/content/colony/camera_rig.gd")
const Hud = preload("res://mods-unpacked/Judah-InfDNA/content/colony/hud.gd")
const SELECT_SCENE = "res://mods-unpacked/Judah-InfDNA/content/colony/queen_select.tscn"
const TITLE_SCENE = "res://ui/menus/title_screen/title_screen.tscn"
const MAX_STEP = 0.05
const FAST_STEP = 0.1          # sim step above 4x (movement carries its remainder, so the step size is safe)
const BUDGET_US = 9000         # sim time allowed per rendered frame: the frame rate holds, the speed bends
const SPEEDS = [0.0, 1.0, 2.0, 4.0, 10.0]

var sim
var baker
var world_view
var ant_view
var enemy_view
var layers_view
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
# view layers (HUD "Layers" panel and the P/C/F/T/H keys); see set_layer
var layer_state := {"trails": true, "castes": true, "fights": true, "tasks": false, "health": false, "follow": false}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var qid = Engine.get_meta("infdna_queen") if Engine.has_meta("infdna_queen") else "well_rounded"
	sim = Sim.new(0, qid)
	baker = Baker.new()
	add_child(baker)

	world_view = WorldView.new()
	world_view.sim = sim
	world_view.baker = baker
	add_child(world_view)

	_overlay = Node2D.new()     # food, trails, eggs, queen: above the dirt
	_overlay.connect("draw", self, "_draw_overlay")
	add_child(_overlay)

	ant_view = AntView.new()
	ant_view.sim = sim
	ant_view.baker = baker
	add_child(ant_view)

	enemy_view = EnemyView.new()
	enemy_view.sim = sim
	add_child(enemy_view)
	ant_view.enemy_view = enemy_view

	cam = CameraRig.new()
	add_child(cam)
	cam.setup(world_view.world_size())
	ant_view.cam = cam
	ant_view.ground = world_view.ground
	world_view.cam = cam

	layers_view = LayersView.new()     # fight / task / health marks, above the ants and raiders
	layers_view.sim = sim
	layers_view.cam = cam
	layers_view.ant_view = ant_view
	layers_view.show_fights = layer_state["fights"]
	layers_view.show_tasks = layer_state["tasks"]
	layers_view.show_health = layer_state["health"]
	add_child(layers_view)

	sfx = Sfx.new()
	sfx.sim = sim
	add_child(sfx)

	hud = Hud.new()
	hud.scene = self
	add_child(hud)


func _process(delta: float) -> void:
	if sim.shop_pending and not shop_open and not sim.collapsed:
		open_shop()
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
			if OS.get_ticks_usec() - t0 > BUDGET_US:
				break
		_debt = min(_debt, 0.25)     # give up on a backlog instead of chasing it
	eff_speed = lerp(eff_speed, done / max(delta, 0.001), 0.1) if speed > 0.0 else 0.0
	if sim.shake > 0.0:
		cam.kick(sim.shake)
		sim.shake = 0.0
	if layer_state["follow"] and selected != null and sim.ants.has(selected):
		var d = ant_view._depth(selected.id, selected.lane)
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
	if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
		selected = ant_view.pick(get_global_mouse_position(), 30.0)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_ESCAPE:
				if hud.is_evolution_open():
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
