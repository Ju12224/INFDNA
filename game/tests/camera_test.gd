extends SceneTree
# Rolls the zoom from the closest view out to the whole colony and back, and reports the biggest change in one frame
# (a jump would show as a big ratio). Run: godot --headless --path game --script res://tests/camera_test.gd

var _c
var _f := 0
var _last := 0.0
var _worst := 1.0


func _init() -> void:
	_c = load("res://scene/colony.tscn").instantiate()
	root.add_child(_c)


func _process(_d: float) -> bool:
	_f += 1
	var vs = _c.get_viewport_rect().size
	if _f == 5:
		for i in 30:
			_c._zoom_at(vs * 0.5, 1.0 / _c.ZOOM_STEP)     # all the way out
	if _f == 200:
		for i in 40:
			_c._zoom_at(vs * 0.3, _c.ZOOM_STEP)           # all the way in, toward a point off centre
	var z = _c.zoom()
	if _last > 0.0:
		_worst = max(_worst, max(z / _last, _last / z))
	_last = z
	if _f == 190:
		print("zoomed out to %.3f (min %.3f)" % [z, _c.min_zoom()])
	if _f == 420:
		print("zoomed in to %.3f; biggest change in one frame x%.3f" % [z, _worst])
		quit()
	return false
