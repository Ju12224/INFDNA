extends SceneTree
# frames, then average ms per frame and draw calls over the last half
var _f := 0
var _node
var _args := {"frames": "240"}
var _t0 := 0
var _calls := 0.0
var _objs := 0.0
var _proc := 0.0
func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	if _args.has("seed"):
		seed(int(_args["seed"]))
	_node = load("res://scene/colony.tscn").instantiate()
	root.add_child(_node)
func _process(_d: float) -> bool:
	_f += 1
	var n = int(_args["frames"])
	if _f == 1:
		_node.debug_setup(_args)
	if _f == n / 2:
		_t0 = Time.get_ticks_usec()
	if _f > n / 2:
		_calls += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		_objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if _f == n:
		var k = n - n / 2
		print("PERF ms/frame=%.2f cpu_process_ms=%.2f draw_calls=%.0f" % [(Time.get_ticks_usec() - _t0) / 1000.0 / k, _proc / k, _calls / k])
		quit()
	return false
