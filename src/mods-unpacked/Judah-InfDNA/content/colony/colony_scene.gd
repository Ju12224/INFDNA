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
const SeasonView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/season_view.gd")
const RivalView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/rival_view.gd")
const Ambience = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ambience.gd")
const Legacy = preload("res://mods-unpacked/Judah-InfDNA/core/legacy.gd")
const Wild = preload("res://mods-unpacked/Judah-InfDNA/core/wild.gd")
const Orders = preload("res://mods-unpacked/Judah-InfDNA/core/orders.gd")
const SelectView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/select_view.gd")
const ContextMenu = preload("res://mods-unpacked/Judah-InfDNA/content/colony/context_menu.gd")
const UgView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ug_view.gd")
const DayCycle = preload("res://mods-unpacked/Judah-InfDNA/content/colony/day_cycle.gd")
const WatchCam = preload("res://mods-unpacked/Judah-InfDNA/content/colony/watch_cam.gd")
const MeadowDepth = preload("res://mods-unpacked/Judah-InfDNA/content/colony/meadow_depth.gd")
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
var rival_view
var ambience
var enemy_view
var pview               # the bird's view
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
var _ug_view           # ug_view.gd: draws the underground structures
var _fast_k := 4               # how many cells an unwatched ant covers per decision at 10x (raised when the machine lags)
var _lag_t := 0.0
var _since_speed := 99.0
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
# Direct control (orders.gd): drag a box over ants to select them, right-click to order them.
var selection: Array = []    # the box selection
var boxing := false          # a drag-box is being drawn (select_view.gd draws it)
var box_a := Vector2()       # its corners, in screen coordinates
var box_b := Vector2()
var _lmb := false
var _rmb := false
var _rmb_pos := Vector2()
var _rmb_moved := false
var _sel_t := 0.0
var cmenu                    # context_menu.gd: the right-click menu
# view layers (HUD "Layers" panel and the P/C/F/T/H keys); see set_layer
var layer_state := {"trails": true, "castes": false, "fights": true, "tasks": false, "health": false, "follow": false, "light": true, "sound": true}


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var qid = Engine.get_meta("infdna_queen") if Engine.has_meta("infdna_queen") else "well_rounded"
	sim = Sim.new(0, qid, Legacy.active(), Wild.active())
	if sim.kin.empty() and Wild.is_on():
		sim.toasts.append({"text": "Whatever you breed well will be waiting for you next time: the Wild remembers fallen colonies.", "t": 12.0})
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
	world_view.day = day
	world_view.ground.day = day

	var ugv = UgView.new()          # underground structures (roots, caverns, buried things...): on the soil, under the units
	ugv.sim = sim
	add_child(ugv)
	_ug_view = ugv
	rival_view = RivalView.new()   # the rival colony's mound, under the units
	rival_view.sim = sim
	rival_view.ground = world_view.ground
	rival_view.perf = perf
	rival_view.baker = baker
	add_child(rival_view)
	_overlay = Node2D.new()     # food, trails, eggs, queen: above the dirt
	_overlay.connect("draw", self, "_draw_overlay")
	add_child(_overlay)

	var fx_under = Node2D.new()     # hit sparks and dust: under the ants and raiders (enemy_view draws on it)
	add_child(fx_under)

	ant_view = AntView.new()
	ant_view.sim = sim
	ant_view.baker = baker
	ant_view.perf = perf
	ant_view.day = day
	add_child(ant_view)

	enemy_view = EnemyView.new()
	enemy_view.sim = sim
	enemy_view.perf = perf
	enemy_view.baker = baker
	enemy_view.under = fx_under
	fx_under.connect("draw", enemy_view, "_draw_under")
	add_child(enemy_view)
	ant_view.enemy_view = enemy_view
	var meadow = MeadowDepth.new()     # thick grass in depth rows: the zoom picks the lane in focus, symbols mark what it hides (key 6)
	meadow.scene = self
	add_child(meadow)
	ant_view.meadow = meadow

	cam = CameraRig.new()
	add_child(cam)
	_ug_view.cam = cam
	cam.setup(world_view.world_size())
	ant_view.cam = cam
	rival_view.cam = cam
	ant_view.ground = world_view.ground
	world_view.cam = cam

	pview = PredatorView.new()      # the bird, before the light pass so night tints it
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
	var sview = SeasonView.new()       # blossom petals and falling leaves (before the light pass, so night tints them)
	sview.sim = sim
	sview.cam = cam
	sview.ground = world_view.ground
	sview.day = day
	sview.perf = perf
	add_child(sview)
	var light = LightView.new()        # the colour of the surface light, multiplied over sky, ground and units
	light.sim = sim
	light.cam = cam
	light.ground = world_view.ground
	light.day = day
	light.perf = perf
	add_child(light)
	add_child(weather)

	layers_view = LayersView.new()     # fight / task / health marks, above the ants and raiders
	layers_view.sim = sim
	layers_view.cam = cam
	layers_view.ant_view = ant_view
	layers_view.show_fights = layer_state["fights"]
	layers_view.show_tasks = layer_state["tasks"]
	layers_view.show_health = layer_state["health"]
	ant_view.show_castes = layer_state["castes"]
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
	ambience = Ambience.new()           # wind, birds, crickets, rain: synthesised, quiet, muted by the Sound layer (O)
	ambience.sim = sim
	ambience.cam = cam
	ambience.day = day
	ambience.ground = world_view.ground
	add_child(ambience)

	var sl = CanvasLayer.new()          # the drag-box: screen space, under the HUD
	sl.layer = 9
	add_child(sl)
	var sv = SelectView.new()
	sv.scene = self
	sv.anchor_right = 1.0
	sv.anchor_bottom = 1.0
	sv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sl.add_child(sv)
	_build_void_tint()

	hud = Hud.new()
	hud.scene = self
	add_child(hud)
	cmenu = ContextMenu.new()       # the right-click menu, above the HUD
	cmenu.scene = self
	add_child(cmenu)
	ug = UndergroundUI.new()      # depth gauge, nest panel (U), room labels, level navigation (PgUp / PgDn)
	ug.scene = self
	add_child(ug)
	ug.update_mode()
	watch = WatchCam.new()
	watch.scene = self
	add_child(watch)
	add_child(perf)           # last: its first apply() reaches every view and the HUD


func _process(delta: float) -> void:
	day.update(sim.time, sim.rain, sim.wet, sim.overcast)
	# a button released over a panel never reaches _unhandled_input: finish the drag from the real button state
	if _lmb and not Input.is_mouse_button_pressed(BUTTON_LEFT):
		_end_box(get_viewport().get_mouse_position(), Input.is_key_pressed(KEY_SHIFT))
	if _rmb and not Input.is_mouse_button_pressed(BUTTON_RIGHT):
		_rmb = false
	if cmenu.is_open and (shop_open or sim.collapsed or watch_mode):
		cmenu.close()
	_sel_t -= delta
	if _sel_t <= 0.0:
		_sel_t = 0.25
		live_selection()
		var tl = _to_world(Vector2.ZERO) / sim.grid.CELL
		var br = _to_world(get_viewport().get_visible_rect().size) / sim.grid.CELL
		sim.attn_rect = Rect2(tl, br - tl).abs().grow(6.0)
		sim.attn_sel = ant_view.sel_ids
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
	# at high speeds nobody follows single ants: they cover more cells per decision (locomotion.gd) and turn their bodies less often
	# and at 10x, when the machine cannot keep up, they cover still more (K 4, then 6, then 8, with a longer step): the colony keeps its pace, single ants look no different
	if speed < 10.0:
		_fast_k = 4
		_lag_t = 0.0
	elif not shop_open and not sim.collapsed and eff_speed < speed * 0.9 and _since_speed > 2.0:
		_lag_t += delta
		if _lag_t > 1.5 and _fast_k < 8:
			_fast_k += 2
			_lag_t = 0.0
	else:
		_lag_t = 0.0
	_since_speed += delta
	sim.hop_k = 1 if speed <= 2.0 else (2 if speed <= 4.0 else _fast_k)
	sim.rot_every = 1 if speed <= 2.0 else (2 if speed <= 4.0 else 3 + (_fast_k - 4) / 2)
	var done := 0.0
	if shop_open or speed <= 0.0 or sim.collapsed:
		_debt = 0.0
	else:
		_debt += min(delta, 0.1) * speed
		var step = MAX_STEP if speed <= 4.0 else FAST_STEP * (1.0 + (_fast_k - 4) * 0.25)
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
	_step_void_tint(delta)
	ant_view.selected = selected
	_prune_timer -= delta
	if _prune_timer <= 0.0:
		_prune_timer = 10.0
		var alive := {sim.queen_genome.uid: true}
		for a in sim.ants:
			alive[a.genome.uid] = true
		for e in sim.eggs:
			alive[e["genome"].uid] = true
		if sim.rival.genome != null:
			alive[sim.rival.genome.uid] = true      # the rival kin's body plan (its sprite is baked like an ant's)
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


# While the Void is open (arc stage 3) the whole screen takes on a faint purple cast, deepest at the edges, breathing slowly; it eases in
# when the ground collapses and out when the pit is sealed. Under the HUD and the drag-box. Nothing is drawn the rest of the time.
var _void_tint: Control
var _void_a := 0.0


func _build_void_tint() -> void:
	var vl = CanvasLayer.new()
	vl.layer = 8
	add_child(vl)
	_void_tint = Control.new()
	_void_tint.anchor_right = 1.0
	_void_tint.anchor_bottom = 1.0
	_void_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_void_tint.visible = false
	_void_tint.connect("draw", self, "_draw_void_tint")
	vl.add_child(_void_tint)


func _step_void_tint(delta: float) -> void:
	_void_a = move_toward(_void_a, 1.0 if sim.arc_stage == 3 else 0.0, delta * 0.4)
	_void_tint.visible = _void_a > 0.003
	if _void_tint.visible:
		_void_tint.update()


func _draw_void_tint() -> void:
	var s = _void_tint.rect_size
	var a = _void_a * (0.85 + 0.15 * sin(OS.get_ticks_msec() * 0.0009))
	_void_tint.draw_rect(Rect2(Vector2.ZERO, s), Color(0.4, 0.16, 0.6, 0.045 * a))
	var edge = Color(0.3, 0.08, 0.45, 0.17 * a)
	var clear = Color(0.3, 0.08, 0.45, 0.0)
	var d = min(s.x, s.y) * 0.3
	_void_tint.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, d), Vector2(0, d)]), PoolColorArray([edge, edge, clear, clear]))
	_void_tint.draw_polygon(PoolVector2Array([Vector2(0, s.y - d), Vector2(s.x, s.y - d), Vector2(s.x, s.y), Vector2(0, s.y)]), PoolColorArray([clear, clear, edge, edge]))
	_void_tint.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(d, 0), Vector2(d, s.y), Vector2(0, s.y)]), PoolColorArray([edge, clear, clear, edge]))
	_void_tint.draw_polygon(PoolVector2Array([Vector2(s.x - d, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - d, s.y)]), PoolColorArray([clear, edge, edge, clear]))


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
	if watch_mode:
		if event is InputEventMouseButton and event.pressed and event.button_index == BUTTON_LEFT:
			selected = ant_view.pick(get_global_mouse_position(), 30.0)
			if selected != null:
				watch.follow(selected)
	elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT:
		if event.pressed and not shop_open and not sim.collapsed:
			_lmb = true
			boxing = false
			box_a = event.position
			box_b = event.position
			if event.doubleclick:
				_select_like(_to_world(event.position))
				_lmb = false
		elif not event.pressed and _lmb:
			_end_box(event.position, event.shift)
	elif event is InputEventMouseMotion and _lmb:
		box_b = event.position
		if (box_b - box_a).length() > 9.0:
			boxing = true
	elif event is InputEventMouseButton and event.button_index == BUTTON_RIGHT:
		if event.pressed:
			_rmb = true
			_rmb_moved = false
			_rmb_pos = event.position
		elif _rmb:
			_rmb = false
			if not _rmb_moved and not shop_open and not sim.collapsed:
				open_context_menu(event.position, event.shift)
	elif event is InputEventMouseMotion and _rmb:
		if event.position.distance_to(_rmb_pos) > 8.0:
			_rmb_moved = true                   # a right-drag pans the camera; only a plain right-click orders
	if event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_V:
				set_watch(not watch_mode)
			KEY_N:
				show_new_strain()
			KEY_BRACKETRIGHT, KEY_5:
				show_apex(1)
			KEY_BRACKETLEFT:
				show_apex(-1)
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
			KEY_Y:
				command("strike", true)
			KEY_Q:
				release_selection()
			KEY_TAB:
				hud.cycle_mode()
			KEY_ESCAPE:
				if armed != "":
					set_armed("")
				elif not selection.empty():
					_set_selection([], false)
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
			KEY_I:
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
			KEY_O:
				toggle_layer("sound")
			KEY_L:
				hud.toggle_evolution()


# ---- direct control: selection and orders (orders.gd)
func _to_world(screen_pos: Vector2) -> Vector2:
	return get_canvas_transform().affine_inverse().xform(screen_pos)


func _end_box(release_pos: Vector2, add: bool) -> void:
	_lmb = false
	var was_box = boxing
	boxing = false
	if was_box:
		var wa = _to_world(box_a)
		var wb = _to_world(release_pos)
		_set_selection(ant_view.pick_rect(Rect2(wa, wb - wa).abs()), add)
	else:
		var a = ant_view.pick(_to_world(release_pos), 30.0)
		if a != null:
			_set_selection([a], add)
		elif not add:
			_set_selection([], false)


# Double-click: every ant on screen of the same caste as the one clicked.
func _select_like(world_pos: Vector2) -> void:
	var a = ant_view.pick(world_pos, 30.0)
	if a == null:
		return
	var tl = _to_world(Vector2.ZERO)
	var br = _to_world(get_viewport().get_visible_rect().size)
	var out := []
	for b in ant_view.pick_rect(Rect2(tl, br - tl).abs()):
		if b.caste == a.caste:
			out.append(b)
	_set_selection(out, false)


func _set_selection(list: Array, add: bool) -> void:
	var out := []
	var ids := {}
	if add:
		for a in selection:
			if sim.ants.has(a) and not ids.has(a.id):
				ids[a.id] = true
				out.append(a)
	for a in list:
		if add and ids.has(a.id):
			out.erase(a)               # shift-clicking an ant that is already selected takes it out
			ids.erase(a.id)
		elif not ids.has(a.id):
			ids[a.id] = true
			out.append(a)
	selection = out
	selected = out[0] if out.size() == 1 else null
	ant_view.sel_ids = ids


# The selection without the dead.
func live_selection() -> Array:
	var out := []
	var ids := {}
	for a in selection:
		if sim.ants.has(a):
			out.append(a)
			ids[a.id] = true
	if out.size() != selection.size():
		selection = out
		ant_view.sel_ids = ids
		if out.size() != 1 and selected != null and not out.has(selected):
			selected = null
	return out


# What a right-click lands on: a raider, a food pile, bare surface, solid soil, or open tunnel (menu_target.kind).
func menu_target(wp: Vector2) -> Dictionary:
	var g = sim.grid
	var C = g.CELL
	var col = int(floor(wp.x / C))
	var t = {"kind": "surface", "col": col, "row": g.surf_y(col) - 2, "z": 0, "foe": null, "pile": null, "diggable": false, "ant": ant_view.pick(wp, 30.0)}
	var foe = ant_view.pick_enemy(wp, 34.0)
	if foe != null:
		t["kind"] = "foe"
		t["foe"] = foe
		t["col"] = foe.x
		t["row"] = foe.y
		t["z"] = foe.z
		return t
	var surf = world_view.ground.smooth_px(col)
	if wp.y < surf + C * 1.5:
		var best = null
		for p in sim.piles:
			if p["amount"] > 4.0 and abs(p["x"] - col) <= 5 and (best == null or abs(p["x"] - col) < abs(best["x"] - col)):
				best = p
		if best != null:
			t["kind"] = "pile"
			t["pile"] = best
		return t
	var row = int(floor(wp.y / C))
	var z = 0 if (g.can_walk(col, row, 0) or not g.can_walk(col, row, 1)) else 1
	t["row"] = row
	t["z"] = z
	if g.is_solid(col, row, z):
		t["kind"] = "soil"
		t["diggable"] = g.diggable(col, row, z)
	else:
		t["kind"] = "tunnel"
	return t


# Right-click: the options menu at the cursor (Shift + right-click does the first order on it at once).
func open_context_menu(screen_pos: Vector2, quick: bool = false) -> void:
	var list = cmenu.build(menu_target(_to_world(screen_pos)))
	if quick:
		var act = cmenu.quick_act(list)
		if not act.empty():
			menu_choice(act)
			return
	cmenu.open(screen_pos, list)


# An option picked from the menu.
func menu_choice(act: Dictionary) -> void:
	var sel = live_selection()
	match str(act.get("t", "")):
		"order":
			var res = Orders.issue(sim, sel, str(act["kind"]), int(act["x"]), int(act["y"]), int(act.get("z", 0)), int(act.get("ref", 0)))
			sim.toasts.append({"text": res["msg"], "t": 2.5})
		"free":
			release_selection()
		"cast":
			var from = selected
			if from == null and str(act["id"]) == "breed" and not sel.empty():
				from = sel[0]
			if act.has("ant"):                 # "Breed from this ant" on an ant under the cursor: that one, selected or not
				for a in sim.ants:
					if a.id == int(act["ant"]):
						from = a
						break
			sim.cast(str(act["id"]), int(act.get("x", 0)), from)
		"beacon":
			sim.place_beacon(int(act["x"]))


func release_selection() -> void:
	var n = Orders.release(sim, live_selection())
	sim.toasts.append({"text": ("%d ant%s let go." % [n, "" if n == 1 else "s"]) if n > 0 else "None of the selected ants are under orders.", "t": 2.5})


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


# ] / [ (or 5): the next / previous Apex ant (the most mutated alive, best first): select it and bring the camera to it.
func show_apex(step: int = 1) -> void:
	if shop_open or sim.collapsed:
		return
	var n = sim.apex.size()
	if n == 0:
		sim.toasts.append({"text": "No standout mutants yet: breed strange ants (right-click one, Breed) and the most mutated will show here.", "t": 4.0})
		return
	var i = int(sim.apex_ids[selected.id]) if (selected != null and sim.apex_ids.has(selected.id)) else -1
	i = posmod(i + step, n) if i >= 0 else (0 if step > 0 else n - 1)
	focus_ant(sim.apex[i])


# Select one ant and bring the camera to it (the HUD's Apex list and the ] key).
func focus_ant(a) -> void:
	if a == null or not sim.ants.has(a):
		return
	if watch_mode:
		selected = a
		watch.follow(a)
	else:
		_set_selection([a], false)
	var d = ant_view._depth(a.id, ant_view.lane_of(a, a.id))
	cam.position = sim.ant_pos(a) + Vector2(0, d[0] - 30.0)
	if cam.zoom.x > 0.9:
		cam.zoom = Vector2.ONE * clamp(0.5, cam.min_zoom, cam.max_zoom)


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
		"sound":
			if ambience != null:
				ambience.set_enabled(on)
		_:
			layers_view.set_layer(key, on)
	if hud != null:
		hud.sync_layer(key, on)


func set_speed(s: float) -> void:
	speed = s
	_since_speed = 0.0
	if hud != null:
		hud.sync_speed(s)


func restart() -> void:
	var _e = get_tree().change_scene(SELECT_SCENE)


func go_to_menu() -> void:
	if ResourceLoader.exists(TITLE_SCENE):
		var _e = get_tree().change_scene(TITLE_SCENE)
	else:
		get_tree().quit()
