extends RefCounted
# The owner's art: textures and manifests under res://art/, each loaded once and kept for the whole game.
# Anything that is not there comes back null (or an empty manifest): a view leaves out what has no picture.

static var _tex := {}
static var _json := {}


# A picture by its path under res://art/ ("sky/sun.png"), or null if there is none.
static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		var full = "res://art/" + path
		_tex[path] = load(full) if ResourceLoader.exists(full) else null
	return _tex[path]


# A manifest by its path under res://art/ ("sky/sky_manifest.json"); empty if missing or broken.
static func manifest(path: String) -> Dictionary:
	if not _json.has(path):
		var full = "res://art/" + path
		var d = JSON.parse_string(FileAccess.get_file_as_string(full)) if FileAccess.file_exists(full) else null
		_json[path] = d if d is Dictionary else {}
	return _json[path]
