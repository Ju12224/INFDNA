extends SceneTree
# Do the ants animate in the real game? Runs a colony for t sim seconds, then draws it frame by frame (with the sim stepping as in play,
# 0.1 s at a time) and records how the units view drew every ant (units_view.debug_frames): the whole-body fallback picture, the walk
# cell, whether the gait advanced. Needs a display and a fixed frame rate so the numbers repeat:
#   xvfb-run -a -s "-screen 0 1920x1080x24" godot --path game --rendering-driver opengl3 --resolution 1920x1057 --fixed-fps 60 \
#     --script res://tests/ants_anim_test.gd -- t=300 zoom=4 at=surface ph=0.45 speed=1 frames=300 window=120
# frames = frames to draw (the last `window` of them are measured, 120 = 2 s at 60 fps).

var _args := {"scene": "res://scene/colony.tscn", "t": "300", "zoom": "4", "at": "surface", "ph": "0.45", "frames": "300", "window": "120", "speed": "1"}
var _node
var _uv
var _frames := 0
var _stamp := 0
var _series := {}            # ant id -> Array of [baked, cell, walking, moved, mid-step, gait, x, y] (the measured window)
var _fb_at := {}             # frame -> [ants drawn, ants drawn with the fallback picture]
var _sim_t0 := 0.0
var _ant := -1               # shots=<png>: the walking ant followed by the six crops, 3 frames apart, that end up side by side in that png
var _crops := []
var _cells := []


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		var kv = a.split("=", true, 1)
		if kv.size() == 2:
			_args[kv[0]] = kv[1]
	_node = load(_args["scene"]).instantiate()
	root.add_child(_node)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_node.debug_setup(_args)
		_node.speed = float(_args["speed"])
		_uv = _node.views["units"]
		_uv.debug_on = true
		_sim_t0 = _node.sim.time
		return false
	if _uv.debug_stamp == _stamp:
		return false                     # nothing drawn since the last look
	_stamp = _uv.debug_stamp
	var df: Dictionary = _uv.debug_frames
	var nfb := 0
	for id in df:
		if not df[id][0]:
			nfb += 1
	_fb_at[_frames] = [df.size(), nfb]
	var n: int = int(_args["frames"])
	if _args.has("shots") and _frames >= n - 20 and (_frames - (n - 20)) % 3 == 0 and _crops.size() < 6:
		_grab(df)
	if _frames > n - int(_args["window"]):
		for id in df:
			if not _series.has(id):
				_series[id] = []
			_series[id].append(df[id])
	if _frames >= n:
		_report()
		quit()
	return false


func _screen_of(wp: Vector2) -> Vector2:
	var cam: Camera2D = _node.cam
	return (wp - cam.get_screen_center_position()) * cam.zoom + root.get_visible_rect().size * 0.5


func _grab(df: Dictionary) -> void:
	if _ant < 0 or not df.has(_ant):
		var best := 0.0
		var sz = root.get_visible_rect().size
		for id in df:
			var sp0 = _screen_of(Vector2(df[id][8], df[id][9]))
			var ser: Array = _series.get(id, [])
			if df[id][4] and df[id][0] and ser.size() > 20 and sp0.x > 200 and sp0.y > 200 and sp0.x < sz.x - 200 and sp0.y < sz.y - 200:
				var d = Vector2(df[id][6], df[id][7]).distance_to(Vector2(ser[-20][6], ser[-20][7]))     # the ant that went furthest in 20 frames
				if d > best:
					best = d
					_ant = id
	if not df.has(_ant):
		return
	var r = df[_ant]
	var sp: Vector2 = _screen_of(Vector2(r[8], r[9]))
	var img: Image = root.get_texture().get_image()
	sp *= Vector2(img.get_size()) / root.get_visible_rect().size      # the window may be scaled from the project's base size
	print("grab ant ", _ant, " spot ", Vector2(r[8], r[9]), " screen ", sp, " img ", img.get_size(), " cam ", _node.cam_center(), " zoom ", _node.zoom())
	if _crops.size() == 0:
		img.save_png(String(_args["shots"]).replace(".png", "_full.png"))
	var w := 260
	var h := 190
	var x = clampi(int(sp.x) - w / 2, 0, img.get_width() - w)
	var y = clampi(int(sp.y) - h * 2 / 3, 0, img.get_height() - h)
	var c = img.get_region(Rect2i(x, y, w, h))
	c.resize(int(w * 1.1), int(h * 1.1), Image.INTERPOLATE_NEAREST)
	_crops.append(c)
	_cells.append(r[1])


func _save_shots() -> void:
	if _crops.is_empty():
		return
	var w: int = _crops[0].get_width()
	var h: int = _crops[0].get_height()
	var sheet = Image.create(w * 3, h * 2, false, Image.FORMAT_RGBA8)
	for i in _crops.size():
		sheet.blit_rect(_crops[i], Rect2i(0, 0, w, h), Vector2i((i % 3) * w, (i / 3) * h))
	sheet.save_png(_args["shots"])
	print("saved ", _args["shots"], " ant ", _ant, " drawn with cells ", _cells)


func _report() -> void:
	_save_shots()
	var out := PackedStringArray()
	out.append("sim seconds run in the draw phase: %.1f (speed %s)" % [_node.sim.time - _sim_t0, _args["speed"]])
	for f in [5, 30, 60, 120, 180, 300, 600]:
		var k = _fb_at.keys().filter(func(x): return x >= f)
		if not k.is_empty():
			var e = _fb_at[k[0]]
			out.append("frame %d: %d ants drawn, %d with the whole-body fallback picture" % [k[0], e[0], e[1]])
	var win := int(_args["window"])
	# ants drawn in at least a third of the window; a sample of 20 of them, nearest the screen centre first
	var full := []
	for id in _series:
		if _series[id].size() >= win / 3:
			full.append(id)
	var cx = _node.cam_center()
	full.sort_custom(func(a, b):
		return Vector2(_series[a][0][6], _series[a][0][7]).distance_to(cx) < Vector2(_series[b][0][6], _series[b][0][7]).distance_to(cx))
	var sample = full.slice(0, 20)
	var tot := {"frames": 0, "fallback": 0, "mid": 0, "mid_stand": 0, "mid_still": 0, "moved_nogait": 0, "flips": 0, "static_ants": 0, "mid_ants": 0, "cells": 0, "gait_n": 0, "gait_sum": 0.0, "gait_cap": 0, "jumps": 0, "disp": [], "jit": 0.0, "jit_n": 0}
	var rows := []
	for id in sample:
		var s: Array = _series[id]
		var cells := {}
		var mid := 0
		var mid_stand := 0
		var mid_still := 0
		var fb := 0
		var nogait := 0
		var flips := 0
		for i in s.size():
			var r = s[i]
			if not r[0]:
				fb += 1
			if r[4]:
				mid += 1
				cells[r[1]] = true
				if r[1] == 6:
					mid_stand += 1
				if r[3] <= 0.001:
					mid_still += 1
			if i > 0:
				var q = s[i - 1]
				if r[2]:
					var dg = r[5] - q[5]
					tot["gait_n"] += 1
					tot["gait_sum"] += dg
					if dg >= 0.1499:
						tot["gait_cap"] += 1                          # strobing: the walk cycle is capped per frame
				var dd = Vector2(r[6], r[7]).distance_to(Vector2(q[6], q[7]))
				if r[4] and q[4]:
					tot["disp"].append(dd)
					tot["jit"] += abs(dd - float(q[3]))                # change of the per-frame displacement: 0 = steady glide
					tot["jit_n"] += 1
				if dd > 12.0:
					tot["jumps"] += 1                                 # drawn spot moved over 12 px in one frame
				if (r[6] != q[6] or r[7] != q[7]) and r[5] == q[5]:
					nogait += 1                                   # it moved on screen, the gait did not
				if r[4] and q[4] and (r[1] == 6) != (q[1] == 6):
					flips += 1                                    # stand <-> walk cell while mid-step
		tot["frames"] += s.size()
		tot["fallback"] += fb
		tot["mid"] += mid
		tot["mid_stand"] += mid_stand
		tot["mid_still"] += mid_still
		tot["moved_nogait"] += nogait
		tot["flips"] += flips
		if mid >= 20:
			tot["mid_ants"] += 1
			if cells.size() <= 1:
				tot["static_ants"] += 1
		rows.append("  ant %-5d frames %3d fallback %3d mid-step %3d (drawn standing %3d, drawn still %3d, distinct cells %d) moved-no-gait %3d stand/walk flips %3d" % [id, s.size(), fb, mid, mid_stand, mid_still, cells.size(), nogait, flips])
	out.append("sample of %d ants over %d frames (%.1f s at 60 fps):" % [sample.size(), win, win / 60.0])
	out.append_array(rows)
	var pct = func(a, b): return 100.0 * a / max(1, b)
	out.append("TOTAL ant-frames %d" % tot["frames"])
	out.append("  fallback picture      : %d (%.1f%%)" % [tot["fallback"], pct.call(tot["fallback"], tot["frames"])])
	out.append("  mid-step ant-frames   : %d" % tot["mid"])
	out.append("  ... drawn standing    : %d (%.1f%%)" % [tot["mid_stand"], pct.call(tot["mid_stand"], tot["mid"])])
	out.append("  ... drawn at rest (no screen movement since last frame): %d (%.1f%%)" % [tot["mid_still"], pct.call(tot["mid_still"], tot["mid"])])
	out.append("  moved on screen but gait did not advance: %d" % tot["moved_nogait"])
	out.append("  stand<->walk cell flips while mid-step: %d (%.1f per ant-second)" % [tot["flips"], tot["flips"] / max(0.01, tot["mid"] / 60.0)])
	out.append("  walking frames: mean gait %.3f cycles/frame (cap 0.15), at the cap %d, spot jumps > 12 px: %d" % [tot["gait_sum"] / max(1, tot["gait_n"]), tot["gait_cap"], tot["jumps"]])
	var dsp: Array = tot["disp"]
	dsp.sort()
	if not dsp.is_empty():
		var mean := 0.0
		for d in dsp:
			mean += d
		mean /= dsp.size()
		out.append("  drawn px per frame while mid-step: mean %.2f, median %.2f, p95 %.2f, max %.2f; jerk (mean change frame to frame / mean) %.2f" % [mean, dsp[dsp.size() / 2], dsp[int(dsp.size() * 0.95)], dsp[-1], tot["jit"] / max(1, tot["jit_n"]) / max(0.001, mean)])
	out.append("  ants mid-step >= 20 frames: %d, of them with one cell all along: %d" % [tot["mid_ants"], tot["static_ants"]])
	for l in out:
		print(l)
