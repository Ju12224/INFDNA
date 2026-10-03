extends Reference
# The drawn art (content/art/*.png, made by tools/art/make_art.py from the owner's pictures): textures loaded once on first use, and the manifest that says
# where every piece of a creature sits and where it hinges. The PNGs ship inside the mod and carry no import files, so they are read with Image.load,
# not load(). Everything here degrades quietly: a missing file is a missing texture, and the callers fall back to the procedural drawing.

const DIR = "res://mods-unpacked/Judah-InfDNA/content/art/"

var _tex := {}
var _man = null


static func get_lib():
	if Engine.has_meta("infdna_art"):
		return Engine.get_meta("infdna_art")
	var l = load("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd").new()
	Engine.set_meta("infdna_art", l)
	return l


func manifest() -> Dictionary:
	if _man == null:
		_man = {}
		var f = File.new()
		if f.open(DIR + "art_manifest.json", File.READ) == OK:
			var res = JSON.parse(f.get_as_text())
			f.close()
			if res.error == OK and res.result is Dictionary:
				_man = res.result
	return _man


func tex(file: String):
	if _tex.has(file):
		return _tex[file]
	var img = Image.new()
	var t = null
	if img.load(DIR + file) == OK:
		var it = ImageTexture.new()
		it.create_from_image(img, Texture.FLAG_FILTER)
		t = it
	_tex[file] = t
	return t


# A creature entry of the manifest ({} when there is none).
func creature(name: String) -> Dictionary:
	var m = manifest()
	if m.has(name) and m[name] is Dictionary:
		return m[name]
	return {}


func has_creature(name: String) -> bool:
	var e = creature(name)
	return not e.empty() and tex(str(e.get("body", {}).get("file", ""))) != null
