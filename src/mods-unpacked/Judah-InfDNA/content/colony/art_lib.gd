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


# The same picture with mipmaps (smooth when drawn much smaller than it is: a tree seen from afar does not shimmer). For scenery, not creatures.
func tex_mip(file: String):
	var key = "m:" + file
	if _tex.has(key):
		return _tex[key]
	var img = Image.new()
	var t = null
	if img.load(DIR + file) == OK:
		t = _mip_texture(img)
	_tex[key] = t
	return t


func _mip_texture(img: Image):
	var it = ImageTexture.new()
	it.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	return it


func has_tex_mip(file: String) -> bool:
	return _tex.has("m:" + file)


# A big picture with mipmaps (the close-up layers of a tree) read off the main thread, so zooming in never stalls a frame: null until it is ready
# (ask again next frame). One file is read at a time, in the order asked; where threads cannot start it is read at once instead.
var _thread = null
var _job := ""
var _job_img = null
var _queue := []


func tex_mip_async(file: String):
	var key = "m:" + file
	if _tex.has(key):
		return _tex[key]
	if file != _job and not _queue.has(file):
		_queue.append(file)
	_pump()
	return _tex.get(key)


func _pump() -> void:
	if _thread != null:
		if _thread.is_alive():
			return
		_thread.wait_to_finish()
		_thread = null
		var img = _job_img
		_job_img = null
		_tex["m:" + _job] = _mip_texture(img) if img != null else null
		_job = ""
	if _queue.empty():
		return
	_job = _queue.pop_front()
	_thread = Thread.new()
	if _thread.start(self, "_read_job", _job) != OK:
		_thread = null
		_tex["m:" + _job] = tex_mip(_job)
		_job = ""


func _read_job(file: String) -> void:
	var img = Image.new()
	if img.load(DIR + file) == OK:
		img.generate_mipmaps()          # here, not on the main thread when the texture is made
		_job_img = img
	else:
		_job_img = null


# A creature entry of the manifest ({} when there is none).
func creature(name: String) -> Dictionary:
	var m = manifest()
	if m.has(name) and m[name] is Dictionary:
		return m[name]
	return {}


func has_creature(name: String) -> bool:
	var e = creature(name)
	return not e.empty() and tex(str(e.get("body", {}).get("file", ""))) != null


# Before the library is dropped (scene change, quit): finish any background read so no thread outlives it.
func shutdown() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_queue.clear()
