extends Reference
# Best run per queen, kept in user://infdna_runs.json. Everything is optional: if the file cannot be read or
# written the game simply shows no record.

const PATH = "user://infdna_runs.json"


static func load_all() -> Dictionary:
	var f = File.new()
	if not f.file_exists(PATH):
		return {}
	if f.open(PATH, File.READ) != OK:
		return {}
	var txt = f.get_as_text()
	f.close()
	var res = JSON.parse(txt)
	if res.error != OK or not (res.result is Dictionary):
		return {}
	return res.result


# Stores this run if it beat the queen's record. Returns {"new": bool, "best": {time, raids, ants}}.
static func record(queen: String, time: float, raids: int, peak_ants: int) -> Dictionary:
	var all = load_all()
	var best = all.get(queen)
	if not (best is Dictionary):
		best = null
	var is_new = best == null or time > float(best.get("time", 0.0))
	if is_new:
		all[queen] = {"time": time, "raids": raids, "ants": peak_ants}
		var f = File.new()
		if f.open(PATH, File.WRITE) == OK:
			f.store_string(JSON.print(all))
			f.close()
		best = all[queen]
	return {"new": is_new, "best": best}


static func clock(t: float) -> String:
	var s = int(t)
	return "%d:%02d" % [s / 60, s % 60]
