extends Node
# Renders each unique genome once into a texture (Viewport -> ImageTexture),
# so hundreds of ants cost one draw_texture each instead of ~150 draw calls.

const Painter = preload("res://mods-unpacked/Judah-InfDNA/core/body_painter.gd")
const SIZE = Vector2(170, 136)
const FEET = Vector2(85, 126)
const BATCH = 4          # one body plan (4 frames) per frame; 16 viewport readbacks at once hitched at high speed
const FRAMES = 4         # walk-cycle frames per body plan
const BAKE = 1.6         # bake resolution over the draw size: crisp when zoomed in

var paint_scale := 0.55
var cache := {}      # uid -> ImageTexture
var _queue := []
var _queued := {}
var _busy := false


# Textures are baked at BAKE x the logical size; draw them into Rect2(-FEET, SIZE)
# (x scale_mult) so every offset stays in logical sprite pixels.
func _key(g, scale_mult: float, frame: int) -> int:
	return g.uid * FRAMES + frame if scale_mult == 1.0 else -(g.uid * FRAMES + frame) - 1


func get_texture(g, scale_mult: float = 1.0, frame: int = 0):
	var key = _key(g, scale_mult, frame)
	if cache.has(key):
		return cache[key]
	if not _queued.has(key):
		for f in FRAMES:   # bake the whole walk cycle together
			var k2 = _key(g, scale_mult, f)
			if not _queued.has(k2) and not cache.has(k2):
				_queued[k2] = true
				_queue.append([g, scale_mult, k2, f])
	var k0 = _key(g, scale_mult, 0)
	if frame != 0 and cache.has(k0):
		return cache[k0]
	return null


func _process(_delta: float) -> void:
	if not _busy and not _queue.empty():
		_bake_batch()


func _bake_batch() -> void:
	_busy = true
	var jobs := []
	var vps := []
	while jobs.size() < BATCH and not _queue.empty():
		jobs.append(_queue.pop_front())
	for job in jobs:
		var m = job[1] * BAKE
		var vp = Viewport.new()
		vp.size = SIZE * m
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.usage = Viewport.USAGE_2D
		vp.render_target_v_flip = true
		vp.render_target_update_mode = Viewport.UPDATE_ONCE
		var p = Painter.new()
		p.genome = job[0]
		p.paint_scale = paint_scale * m
		p.gait = job[3] / float(FRAMES)
		p.anim_t = job[3] * 0.5
		p.position = FEET * m
		vp.add_child(p)
		add_child(vp)
		vps.append(vp)
	yield(VisualServer, "frame_post_draw")
	for i in jobs.size():
		var img: Image = vps[i].get_texture().get_data()
		var tex = ImageTexture.new()
		tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
		cache[jobs[i][2]] = tex
		_queued.erase(jobs[i][2])
		vps[i].queue_free()
	_busy = false


# Drop textures for body plans that no longer exist.
func prune(alive: Dictionary) -> void:
	for key in cache.keys():
		var uid = (-key - 1) / FRAMES if key < 0 else key / FRAMES
		if not alive.has(uid):
			cache.erase(key)
