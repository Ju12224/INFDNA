extends SceneTree
# Runs the game screen for a moment, then closes it the way the window's close button does, and prints the report it wrote.
# Run: godot --headless --path game --script res://tests/close_test.gd

var _frames := 0
var _main


func _init() -> void:
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 300:
		_main.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		var p = "user://reports/InfDNA_report.txt"
		print("report exists: ", FileAccess.file_exists(p), " at ", ProjectSettings.globalize_path(p))
		print(FileAccess.get_file_as_string(p))
	return false
