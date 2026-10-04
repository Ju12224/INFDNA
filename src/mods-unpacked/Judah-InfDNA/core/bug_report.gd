extends Reference
# The report for the developer: one plain text file, InfDNA_report.txt on the player's Desktop (and a copy in the game's user folder),
# written when the game closes, when the colony mode is left, and once a minute while it runs (so a crash still leaves the last one).
# The player drags that one file into the chat; nothing is sent anywhere by the game.
#
# What it holds: the machine and versions; the session (how long, how many colonies, peaks, frame times); every problem the mod noticed
# itself (note(): broken numbers, things outside the world, lists that grow without end, long frame hitches), each once with a count;
# and the error and warning lines of Godot's own log (user://logs/godot.log), which is where script errors land.
#
# The state lives in Engine metadata as a Dictionary of plain values (no objects: metadata holding objects crashed the game at exit).

const META = "infdna_report"
const FILE_NAME = "InfDNA_report.txt"
const MAX_NOTES = 120
const LOG_LINES = 160
const LOG_PATHS = ["user://logs/godot.log", "user://logs/modloader.log"]


static func _state() -> Dictionary:
	if Engine.has_meta(META):
		return Engine.get_meta(META)
	var st = {"started": OS.get_unix_time(), "started_text": _now(), "notes": {}, "order": [], "stats": {}, "colonies": 0,
		"worst_frame_ms": 0.0, "hitches": 0, "clean": false}
	Engine.set_meta(META, st)
	return st


static func _now() -> String:
	var d = OS.get_datetime()
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
	var d = Directory.new()
	if desk != "" and d.dir_exists(desk):
		_save(desk.plus_file(FILE_NAME), text)
	if not d.dir_exists("user://infdna_reports"):
		d.make_dir_recursive("user://infdna_reports")
	_save("user://infdna_reports/" + FILE_NAME, text)


static func _save(path: String, text: String) -> void:
	var f = File.new()
	if f.open(path, File.WRITE) == OK:
		f.store_string(text)
		f.close()


static func _compose(st: Dictionary, reason: String) -> String:
	var L := PoolStringArray()
	L.append("InfDNA report")
	L.append("written: " + _now() + " (" + reason + ")")
	L.append("game closed normally: " + ("yes" if st["clean"] else "no (if the game crashed, this is the last minute before it)"))
	L.append("")
	L.append("== versions and machine")
	L.append("mod: " + _mod_version())
	L.append("brotato: " + str(ProjectSettings.get_setting("application/config/version")) if ProjectSettings.has_setting("application/config/version") else "brotato: ?")
	L.append("engine: " + str(Engine.get_version_info().get("string", "?")))
	L.append("os: " + OS.get_name() + "  cores: " + str(OS.get_processor_count()) + "  video driver: " + ("GLES3" if OS.get_current_video_driver() == OS.VIDEO_DRIVER_GLES3 else "GLES2"))
	L.append("screen: " + str(OS.get_screen_size()) + "  window: " + str(OS.window_size) + ("  fullscreen" if OS.window_fullscreen else ""))
	L.append("gpu: " + VisualServer.get_video_adapter_vendor() + " " + VisualServer.get_video_adapter_name())
	L.append("")
	L.append("== session")
	var mins = (OS.get_unix_time() - int(st["started"])) / 60.0
	L.append("started: " + str(st["started_text"]) + "  length: %.1f min" % mins)
	L.append("colonies started: " + str(st["colonies"]))
	L.append("worst frame: %.0f ms   frames over 250 ms: %d" % [st["worst_frame_ms"], st["hitches"]])
	var keys = st["stats"].keys()
	keys.sort()
	for k in keys:
		var v = st["stats"][k]
		L.append(str(k) + ": " + (("%.2f" % v) if typeof(v) == TYPE_REAL else str(v)))
	L.append("")
	L.append("== problems the mod noticed (" + str(st["order"].size()) + ")")
	if st["order"].empty():
		L.append("none")
	for key in st["order"]:
		var e = st["notes"][key]
		L.append("[x%d] %s   (first %s, last %s)" % [e["count"], key, e["first"], e["last"]])
	for p in LOG_PATHS:
		L.append("")
		L.append("== errors and warnings in " + p)
		L.append_array(_log_tail(p))
	L.append("")
	return L.join("\n")


static func _mod_version() -> String:
	var f = File.new()
	if f.open("res://mods-unpacked/Judah-InfDNA/manifest.json", File.READ) != OK:
		return "?"
	var r = JSON.parse(f.get_as_text())
	f.close()
	if r.error != OK or typeof(r.result) != TYPE_DICTIONARY:
		return "?"
	return str(r.result.get("version_number", "?"))


# The error and warning lines of a log (with the "At:" line under each), repeats folded into one line with a count, the last LOG_LINES kept.
static func _log_tail(path: String) -> PoolStringArray:
	var out := PoolStringArray()
	var f = File.new()
	if not f.file_exists(path):
		out.append("(no such log: file logging may be off)")
		return out
	if f.open(path, File.READ) != OK:
		out.append("(could not open it)")
		return out
	var lines = f.get_as_text().split("\n")
	f.close()
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
	if picked.empty():
		out.append("none")
		return out
	var start = max(0, picked.size() - LOG_LINES)
	if start > 0:
		out.append("(" + str(start) + " older distinct lines left out)")
	for j in range(start, picked.size()):
		var it = picked[j]
		out.append(("[x%d] " % counts[it] if counts[it] > 1 else "") + it)
	return out
