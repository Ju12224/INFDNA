extends SceneTree
# Runs the real colony scene headless until a raider is fighting, then drives the view layers (scene API,
# HUD buttons, camera parked away from the raiders) and prints PASS/FAIL lines. Look for SCRIPT ERROR too.
# usage (project dir holding mods-unpacked/ and this file):  godot --no-window --path . -s layers_smoke.gd
# Godot 3.5 headless may segfault inside quit(), after the results have printed; the lines above it count.
const Scene = preload("res://mods-unpacked/Judah-InfDNA/content/colony/colony_scene.gd")
var s
var started := false
var frames := 0
var fails := 0
var max_pairs := 0
var max_fighting := 0


func _init():
	s = Scene.new()
	root.add_child(s)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _idle(_delta):
	var sim = s.sim
	if not started:
		started = true
		s.speed = 0.0
		var hit = false
		while not hit and sim.time < 1500.0 and not sim.collapsed:
			sim.step(0.05)
			for e in sim.enemies:
				if e.engaged and e.cls != "prey":
					hit = true
		_check(hit, "reached a fight (t=%.0f, %d ants, %d raiders)" % [sim.time, sim.ants.size(), sim.hostile_count()])
		_check(s.layer_state["fights"] and not s.layer_state["tasks"], "defaults: fights on, tasks off")
		s.set_layer("tasks", true)
		s.set_layer("health", true)
		_check(s.layers_view.show_tasks and s.layers_view.show_health, "set_layer reaches the layers view")
		_check(s.hud._task_legend.visible, "task legend shows with the Tasks layer")
		return false
	frames += 1
	if frames < 120:
		sim.step(0.05)       # keep fighting; the camera follows the first raider
		for e in sim.enemies:
			if e.cls != "prey":
				s.cam.position = sim.enemy_pos(e)
				break
		max_pairs = max(max_pairs, s.layers_view._pairs.size())
		max_fighting = max(max_fighting, s.layers_view._fighting.size())
	elif frames == 120:
		_check(max_pairs > 0 and max_fighting > 0, "fight links found (%d pairs, %d ants fighting)" % [max_pairs, max_fighting])
		for k in s.layer_state.keys():
			var before = s.layer_state[k]
			s.toggle_layer(k)
			s.toggle_layer(k)
			_check(s.layer_state[k] == before and s.hud._layer_btns[k].pressed == before, "toggle round trip: " + k)
		s.hud._layer_btns["fights"].pressed = false
		_check(not s.layer_state["fights"] and not s.layers_view.show_fights, "HUD button turns Fights off")
		s.hud._layer_btns["fights"].pressed = true
		_check(s.layer_state["fights"] and s.layers_view.show_fights, "HUD button turns Fights on")
		s.cam.position = Vector2(sim.grid.entrance.x * 6.0 + 20000.0, 200.0)   # raiders now off screen: arrows get drawn
	elif frames == 130:
		# watch mode (V): HUD hidden, busy layers off, camera directed; leaving restores everything
		var saved = s.layer_state.duplicate()
		var bar_was = s.hud._bar_panel.visible
		s.set_watch(true)
		_check(s.watch_mode and s.watch.active, "watch mode on")
		_check(not s.hud._bar_panel.visible and not s.hud._mm_panel.visible and not s.hud._left_col.visible, "watch mode hides the HUD panels")
		_check(not s.layer_state["castes"] and not s.layer_state["tasks"] and not s.layer_state["health"], "watch mode switches the busy layers off")
		for i in 40:
			s.watch._process(0.5)
		_check(s.watch._kind != "", "watch camera picked a shot (%s)" % s.watch._kind)
		s.watch.note_input()
		var cam_before = s.cam.position
		s.watch._process(0.5)
		_check(s.cam.position == cam_before, "manual input holds the camera")
		s.set_watch(false)
		var same = true
		for k in saved:
			if s.layer_state[k] != saved[k]:
				same = false
		_check(not s.watch_mode and same and s.hud._bar_panel.visible == bar_was, "leaving watch mode restores the layers and HUD")
	elif frames == 140:
		print("RESULT %d failed" % fails)
		quit(1 if fails > 0 else 0)
	return false
