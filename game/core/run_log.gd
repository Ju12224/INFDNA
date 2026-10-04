extends RefCounted
# Best run per queen, kept in user://infdna_runs.json. Everything is optional: if the file cannot be read or
# written the game simply shows no record.

const PATH = "user://infdna_runs.json"


static func load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var res = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return res if res is Dictionary else {}


# Stores this run if it beat the queen's record. Returns {"new": bool, "best": {time, raids, ants}}.
static func record(queen: String, time: float, raids: int, peak_ants: int) -> Dictionary:
	var all = load_all()
	var best = all.get(queen)
	if not (best is Dictionary):
		best = null
	var is_new = best == null or time > float(best.get("time", 0.0))
	if is_new:
		all[queen] = {"time": time, "raids": raids, "ants": peak_ants}
		var f = FileAccess.open(PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(all))
		best = all[queen]
	return {"new": is_new, "best": best}


static func clock(t: float) -> String:
	var s = int(t)
	return "%d:%02d" % [s / 60, s % 60]
