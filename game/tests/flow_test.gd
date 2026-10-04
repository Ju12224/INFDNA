extends SceneTree
# Plays the run loop with no screen: title -> Start -> colony -> the queen falls -> end of run -> the Lab (buys one item) -> title ->
# Start -> the new colony carries the item. Also opens and closes the pause menu. Prints PASS or FAIL per step. The save files it
# touches (Lab bank, heirloom, Wild, records) are put back as they were.
# Run: godot --headless --path game --script res://tests/flow_test.gd

const Run = preload("res://scene/run.gd")
const FILES = ["user://infdna_lab.json", "user://infdna_legacy.json", "user://infdna_wild.json", "user://infdna_runs.json"]

var _saved := {}
var _step := 0
var _wait := 0
var _bought := ""
var _bad := 0


func _init() -> void:
	for f in FILES:
		_saved[f] = FileAccess.get_file_as_string(f) if FileAccess.file_exists(f) else null
	change_scene_to_file(Run.TITLE)


func _check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		_bad += 1


func _scene_is(path: String) -> bool:
	return current_scene != null and current_scene.scene_file_path == path


func _process(_delta: float) -> bool:
	_wait += 1
	if _wait < 5:
		return false
	_wait = 0
	match _step:
		0:
			_check(_scene_is(Run.TITLE), "title screen opens")
			current_scene._select(1)
			current_scene._start()
		1:
			_check(_scene_is(Run.COLONY), "Start opens the colony")
			_check(Run.queen_id == "vampire", "the picked queen is passed on (%s)" % Run.queen_id)
			var hud = current_scene.views.get("hud")
			_check(hud != null, "the colony has the top bar")
			hud._open_menu()
			_check(paused, "Esc menu pauses the game")
			hud._close_menu()
			_check(not paused, "Resume unpauses")
			current_scene.sim.queen_hp = 0.0
		2:
			_check(_scene_is(Run.RUN_END), "the fall opens the end-of-run screen")
			var lab = load("res://core/shop_items.gd").lab_load()
			_check(int(lab["bank"]) > 0, "the run paid into the Lab bank (%d)" % int(lab["bank"]))
			current_scene._to_lab()
		3:
			_check(_scene_is(Run.LAB), "To the Lab opens the Lab")
			var lab = current_scene._lab
			_check(not lab["offers"].is_empty(), "the Lab offers items (%s)" % ", ".join(PackedStringArray(lab["offers"])))
			lab["bank"] = 500
			_bought = str(lab["offers"][0])
			current_scene._on_buy(0)
			_check(Run.items.has(_bought), "a bought item is kept for the next colony")
			current_scene._continue()
		4:
			_check(_scene_is(Run.TITLE), "Continue goes back to the title")
			current_scene._start()
		5:
			_check(_scene_is(Run.COLONY), "the next colony starts")
			_check(int(current_scene.sim.owned.get(_bought, 0)) == 1, "the next colony carries %s" % _bought)
			current_scene.views["hud"]._quit_to_title()
		6:
			_check(_scene_is(Run.TITLE), "Quit to title from the pause menu")
			for f in FILES:
				if _saved[f] == null:
					if FileAccess.file_exists(f):
						DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
				else:
					var fa = FileAccess.open(f, FileAccess.WRITE)
					fa.store_string(_saved[f])
			print("flow test: %s" % ("all passed" if _bad == 0 else "%d failed" % _bad))
			quit(1 if _bad > 0 else 0)
	_step += 1
	return false
