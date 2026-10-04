extends Node2D
# Draws the underground structures (core/underground.gd): each module's view script draws the structures in sight, on top of the
# soil and under the ants. Static structures are redrawn only when the camera moves; animated ones every frame.

const UG = preload("res://mods-unpacked/Judah-InfDNA/core/underground.gd")

var sim
var cam
var _t := 0.0
var _last_rect := Rect2()
var _anim := false
var _was_drawn := false


func _process(delta: float) -> void:
	_t += delta
	if sim == null or cam == null:
		return
	var r = _view_rect()
	if _anim or r != _last_rect:
		_last_rect = r
		update()


func _view_rect() -> Rect2:
	var vs = get_viewport_rect().size * cam.zoom
	var c = cam.get_camera_screen_center()
	return Rect2(c - vs * 0.5, vs).grow(80.0)


func _draw() -> void:
	if sim == null or cam == null:
		return
	var reg = sim.grid.ug
	if reg == null or reg.views().empty():
		return
	var C = sim.grid.CELL
	var r = _last_rect if _last_rect.size != Vector2.ZERO else _view_rect()
	var xa = int(floor(r.position.x / C))
	var xb = int(ceil(r.end.x / C))
	var anim := false
	var views = reg.views()
	for n in views.keys():
		var feats = reg.features(n, sim.grid, xa, xb)
		if feats.empty():
			continue
		var v = views[n]
		v.draw(self, sim, feats, _t, cam.zoom.x)
		if reg.has_fn(v, "animated") and v.animated():
			anim = true
	_anim = anim
