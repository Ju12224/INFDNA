extends RefCounted
# The report for the developer: one plain text file, InfDNA_report.txt on the player's Desktop (and a copy in the game's user folder),
# written when the game closes, when the colony mode is left, and once a minute while it runs (so a crash still leaves the last one).
# The player drags that one file into the chat; nothing is sent anywhere by the game.
#
# What it holds: the machine and versions; the session (how long, how many colonies, peaks, frame times); every problem the game noticed
# itself (note(): broken numbers, things outside the world, lists that grow without end, long frame hitches), each once with a count;
# and the error and warning lines of Godot's own log (user://logs/godot.log), which is where script errors land.
#
# The state lives in Engine metadata as a Dictionary of plain values (no objects: metadata holding objects crashed the game at exit).

const META = "infdna_report"
const FILE_NAME = "InfDNA_report.txt"
const MAX_NOTES = 120
const LOG_LINES = 160
const LOG_PATHS = ["user://logs/godot.log"]


static func _state() -> Dictionary:
	if Engine.has_meta(META):
		return Engine.get_meta(META)
	var st = {"started": Time.get_unix_time_from_system(), "started_text": _now(), "notes": {}, "order": [], "stats": {}, "colonies": 0,
		"worst_frame_ms": 0.0, "hitches": 0, "clean": false}
	Engine.set_meta(META, st)
	return st


static func _now() -> String:
	var d = Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d %02d:%02d:%02d" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]


# Something looks wrong: remembered once (with how often it happened, and when first and last), so a problem in a loop does not flood the file.
static func note(kind: String, text: String) -> void:
	var st = _state()
	var key = kind + ": " + text
	var n = st["notes"]
	if n.has(key):
		n[key]["count"] += 1
		n[key]["last"] = _now()
		return
	if st["order"].size() >= MAX_NOTES:
		return
	n[key] = {"count": 1, "first": _now(), "last": _now()}
	st["order"].append(key)


# True once the game is closing (the closing report is written; nothing should overwrite it with a lesser reason).
static func closing() -> bool:
	return bool(_state().get("clean", false))


static func stat(key: String, value) -> void:
	_state()["stats"][key] = value


static func stat_max(key: String, value: float) -> void:
	var s = _state()["stats"]
	s[key] = max(float(s.get(key, value)), value)


static func colony_started() -> void:
	var st = _state()
	st["colonies"] += 1


# A frame took this long (seconds): the worst one is kept, and frames over a quarter second count as hitches.
static func frame(dt: float) -> void:
	var st = _state()
	var ms = dt * 1000.0
	if ms > st["worst_frame_ms"]:
		st["worst_frame_ms"] = ms
	if ms > 250.0:
		st["hitches"] += 1


static func write(reason: String, clean: bool = false) -> void:
	var st = _state()
	if clean:
		st["clean"] = true
	var text = _compose(st, reason)
	var desk = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	if desk != "" and DirAccess.dir_exists_absolute(desk):
		_save(desk.path_join(FILE_NAME), text)
	if not DirAccess.dir_exists_absolute("user://reports"):
		DirAccess.make_dir_recursive_absolute("user://reports")
	_save("user://reports/" + FILE_NAME, text)


static func _save(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


static func _compose(st: Dictionary, reason: String) -> String:
	var L := PackedStringArray()
	L.append("InfDNA report")
	L.append("written: " + _now() + " (" + reason + ")")
	L.append("game closed normally: " + ("yes" if st["clean"] else "no (if the game crashed, this is the last minute before it)"))
	L.append("")
	L.append("== versions and machine")
	L.append("game: " + str(ProjectSettings.get_setting("application/config/version", "?")))
	L.append("engine: " + str(Engine.get_version_info().get("string", "?")))
	L.append("os: " + OS.get_name() + " " + OS.get_version() + "  cores: " + str(OS.get_processor_count()))
	L.append("renderer: " + RenderingServer.get_current_rendering_method() + " / " + RenderingServer.get_current_rendering_driver_name())
	L.append("gpu: " + RenderingServer.get_video_adapter_vendor() + " " + RenderingServer.get_video_adapter_name())
	var full = DisplayServer.window_get_mode() >= DisplayServer.WINDOW_MODE_FULLSCREEN
	L.append("screen: " + str(DisplayServer.screen_get_size()) + "  window: " + str(DisplayServer.window_get_size()) + ("  fullscreen" if full else ""))
	L.append("")
	L.append("== session")
	var mins = (Time.get_unix_time_from_system() - float(st["started"])) / 60.0
	L.append("started: " + str(st["started_text"]) + "  length: %.1f min" % mins)
	L.append("colonies started: " + str(st["colonies"]))
	L.append("worst frame: %.0f ms   frames over 250 ms: %d" % [st["worst_frame_ms"], st["hitches"]])
	var keys = st["stats"].keys()
	keys.sort()
	for k in keys:
		var v = st["stats"][k]
		L.append(str(k) + ": " + (("%.2f" % v) if typeof(v) == TYPE_FLOAT else str(v)))
	L.append("")
	L.append("== problems the game noticed (" + str(st["order"].size()) + ")")
	if st["order"].is_empty():
		L.append("none")
	for key in st["order"]:
		var e = st["notes"][key]
		L.append("[x%d] %s   (first %s, last %s)" % [e["count"], key, e["first"], e["last"]])
	for p in LOG_PATHS:
		L.append("")
		L.append("== errors and warnings in " + p)
		L.append_array(_log_tail(p))
	L.append("")
	return "\n".join(L)


# The error and warning lines of a log (with the "At:" line under each), repeats folded into one line with a count, the last LOG_LINES kept.
static func _log_tail(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	if not FileAccess.file_exists(path):
		out.append("(no such log: file logging may be off)")
		return out
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		out.append("(could not open it)")
		return out
	var lines = f.get_as_text().split("\n")
	var picked := []
	var counts := {}
	var i = 0
	while i < lines.size():
		var ln = str(lines[i]).strip_edges()
		var up = ln.to_upper()
		if up.find("ERROR") >= 0 or up.find("WARNING") >= 0 or up.find("INFDNA") >= 0:
			var item = ln
			if i + 1 < lines.size() and str(lines[i + 1]).strip_edges().begins_with("At:"):
				item += "  |  " + str(lines[i + 1]).strip_edges()
				i += 1
			if counts.has(item):
				counts[item] += 1
			else:
				counts[item] = 1
				picked.append(item)
		i += 1
	if picked.is_empty():
		out.append("none")
		return out
	var start = max(0, picked.size() - LOG_LINES)
	if start > 0:
		out.append("(" + str(start) + " older distinct lines left out)")
	for j in range(start, picked.size()):
		var it = picked[j]
		out.append(("[x%d] " % counts[it] if counts[it] > 1 else "") + it)
	return out
