extends SceneTree
const Scene = preload("res://mods-unpacked/Judah-InfDNA/content/colony/colony_scene.gd")
var s
var frames := 0
var rng = RandomNumberGenerator.new()
var forced := false
func _init():
	rng.seed = 4242
	s = Scene.new()
	root.add_child(s)
func _idle(delta):
	frames += 1
	var sim = s.sim
	s.speed = 0.0
	if s.shop_open:
		s.close_shop()
	if sim.collapsed:
		print("FUZZ colony collapsed at t=%.0f (not an error)" % sim.time)
		quit()
		return false
	for i in 55:
		sim.step(0.1)
		if sim.shop_pending and sim.hostile_count() == 0 and not s.shop_open:
			sim.shop_pending = false
	if sim.time > 200.0 and not forced:
		forced = true
		sim.rival.found = true
		for k in ["spider", "bee", "hornet", "spider", "bee", "anteater", "redant", "redsoldier", "redmajor"]:
			sim._spawn_enemy(k, 1 if rng.randf() < 0.5 else -1)
		for a in sim.ants:
			if rng.randf() < 0.15:
				var g = a.genome.copy()
				g.morph["wings"] = 1
				sim.register_genome(g)
				a.genome = g
				a.ph = a.ph.duplicate()
				a.ph["wings"] = 1
	var r = rng.randf()
	var keys = s.layer_state.keys()
	if r < 0.25:
		s.toggle_layer(keys[rng.randi() % keys.size()])
	elif r < 0.5:
		var ex = sim.grid.entrance.x
		s.cam.position = Vector2((ex + rng.randf_range(-1700.0, 1700.0)) * 6.0, rng.randf_range(-1200.0, 600.0))
		s.cam.zoom = Vector2.ONE * rng.randf_range(s.cam.min_zoom, s.cam.max_zoom)
	elif r < 0.62 and not sim.ants.empty():
		s.selected = sim.ants[rng.randi() % sim.ants.size()]
	elif r < 0.72:
		var ev = InputEventMouseButton.new()
		ev.button_index = BUTTON_LEFT
		ev.pressed = true
		ev.position = Vector2(rng.randf_range(0.0, 640.0), 20.0)
		s.hud._on_mm_input(ev)
	elif r < 0.8:
		s.set_speed([0.0, 1.0, 2.0, 4.0, 10.0][rng.randi() % 5])
		s.speed = 0.0
	elif r < 0.85:
		sim.place_beacon(int(sim.grid.entrance.x) + rng.randi_range(-800, 800))
	elif r < 0.88 and s.selected != null:
		sim.bless(s.selected)
	elif r < 0.91:
		s.hud.toggle_evolution()
	elif r < 0.94:
		s.perf.cycle_mode()
	elif r < 0.96:
		var ug = null
		for ch in s.get_children():
			if ch.has_method("jump_level"):
				ug = ch
		if ug != null:
			ug.panel_open = not ug.panel_open
			ug.jump_level(1 if rng.randf() < 0.5 else -1)
	elif r < 0.975:
		s.cam.position = Vector2(sim.grid.entrance.x * 6.0 + rng.randf_range(-300.0, 300.0), sim.grid.surf_y(int(sim.grid.entrance.x)) * 6.0 + rng.randf_range(100.0, 900.0))
		s.cam.zoom = Vector2.ONE * rng.randf_range(0.3, 1.2)
	if rng.randf() < 0.18:
		s.set_watch(not s.watch_mode)
	if rng.randf() < 0.3:
		s.day.force = rng.randf() if rng.randf() < 0.7 else -1.0
	if rng.randf() < 0.25:
		s.day.season_force = rng.randf() if rng.randf() < 0.85 else -1.0
	if s.watch_mode:
		for i in 3:
			s.watch._process(rng.randf_range(0.01, 1.2))
		if rng.randf() < 0.2:
			s.watch.note_input(rng.randf_range(0.0, 3.0))
		if rng.randf() < 0.2 and not sim.ants.empty():
			s.watch.follow(sim.ants[rng.randi() % sim.ants.size()])
	if rng.randf() < 0.5:
		sim.will = min(100.0, sim.will + 40.0)
		var ids = sim.COMMANDS.keys()
		var cid = ids[rng.randi() % ids.size()]
		s.command(cid, rng.randf() < 0.5)
		if rng.randf() < 0.3:
			s.set_armed("")
		if rng.randf() < 0.2:
			sim.caste_order = rng.randi() % 3
		if rng.randf() < 0.3:
			s.hud._on_cmd(ids[rng.randi() % ids.size()])
	# direct control: random drag-boxes, right-click orders, releases, the clean/full screen, weather and a bird that comes and goes
	if rng.randf() < 0.35 and not s.watch_mode:
		var c0 = s.cam.get_camera_screen_center()
		var vp2 = s.get_viewport().get_visible_rect().size * s.cam.zoom.x
		var wa = c0 + Vector2(rng.randf_range(-0.5, 0.2) * vp2.x, rng.randf_range(-0.5, 0.2) * vp2.y)
		var wb = wa + Vector2(rng.randf_range(0.1, 0.8) * vp2.x, rng.randf_range(0.1, 0.8) * vp2.y)
		s._set_selection(s.ant_view.pick_rect(Rect2(wa, wb - wa).abs()), rng.randf() < 0.2)
	if rng.randf() < 0.3 and not s.selection.empty():
		var exg = int(sim.grid.entrance.x)
		var wx = (exg + rng.randi_range(-200, 200)) * 6.0
		var wy = rng.randf_range(-100.0, 600.0) + sim.grid.surf_y(exg) * 6.0
		s.open_context_menu(s.get_canvas_transform().xform(Vector2(wx, wy)), rng.randf() < 0.2)
		if s.cmenu.is_open:
			s.cmenu._choose(rng.randi() % s.cmenu.items.size())
			s.cmenu.close()
	if rng.randf() < 0.1:
		s.release_selection()
	if rng.randf() < 0.05:
		s.hud.cycle_mode()
	if rng.randf() < 0.03 and sim.bird == null:
		var exb = int(sim.grid.entrance.x)
		sim.bird = {"x": float(exb + rng.randi_range(-150, 150)), "t": rng.randf_range(0.5, 6.0), "cd": 9.0, "dive": 0.0, "alt": 0.6, "face": 1, "kills": 0}
	if frames % 20 == 0:
		print("FUZZ frame %d t=%.0f ants=%d enemies=%d hostile=%d trees=%d piles=%d" % [frames, sim.time, sim.ants.size(), sim.enemies.size(), sim.hostile_count(), sim.trees.size(), sim.piles.size()])
	if sim.time > 600.0:
		print("FUZZ DONE t=%.0f ants=%d discovered=%d tier=%d mode=%d" % [sim.time, sim.ants.size(), sim.discovered, s.perf.tier, s.perf.mode])
		quit()
	return false
