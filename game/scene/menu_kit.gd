extends RefCounted
# The pieces every menu and the top bar are built from: the owner's frames (art/ui) as Godot styleboxes, frame buttons, labels with
# a dark outline so text reads over the sky, icons, and the sky backdrop behind the title, end-of-run and Lab screens.
# Nothing here draws shapes of its own; a frame, an icon or plain text is all that goes on screen.

const Art = preload("res://scene/art.gd")
const Day = preload("res://scene/day.gd")
const SkyView = preload("res://scene/sky_view.gd")

const INK = Color("#f1e6cf")        # body text
const DIM = Color("#b9a98c")        # secondary text
const GOLD = Color("#f2c14e")
const GOOD = Color("#a8ec74")
const BAD = Color("#ff8a72")
const OUTLINE = Color("#1a120c")
# frame name -> [left, top, right, bottom] border of the picture, in picture pixels
const FRAMES = {
	"frame_small": [30, 14, 30, 19],
	"frame_wide": [28, 33, 28, 33],
	"stone_small": [16, 16, 16, 16],
	"stone_wide": [26, 28, 26, 28],
	"frame_tall": [26, 44, 26, 44],
}

static var _scaled := {}


# The owner's frame as a stylebox, shrunk to k of its drawn size (borders included) so it fits small controls. `pad` is the room
# between the border and the content. Given a control, the frame is redrawn to that control's exact size whenever it changes
# (fit()), so the border repeats whole and the inside stays clean (Godot's own tiling leaves dark specks where its tiles meet).
static func box(frame: String, k: float = 1.0, pad: Vector2 = Vector2(6, 2), tint: Color = Color.WHITE) -> StyleBox:
	var tex = _tex_scaled(frame, k)
	if tex == null:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(8)
		return empty
	var m = _margins(frame, k)
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = m[0]
	sb.texture_margin_top = m[1]
	sb.texture_margin_right = m[2]
	sb.texture_margin_bottom = m[3]
	sb.content_margin_left = m[0] + pad.x
	sb.content_margin_right = m[2] + pad.x
	sb.content_margin_top = m[1] + pad.y
	sb.content_margin_bottom = m[3] + pad.y
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	sb.modulate_color = tint
	sb.set_meta("frame", [frame, k])
	return sb


static func _margins(frame: String, k: float) -> Array:
	var m: Array = FRAMES.get(frame, [16, 16, 16, 16])
	return [int(round(m[0] * k)), int(round(m[1] * k)), int(round(m[2] * k)), int(round(m[3] * k))]


# Keeps a control's frame styleboxes (box()) drawn at its exact size.
static func fit(c: Control, names: Array) -> void:
	c.resized.connect(_refit.bind(c, names))


static func _refit(c: Control, names: Array) -> void:
	var sz := Vector2i(int(round(c.size.x)), int(round(c.size.y)))
	if sz.x < 4 or sz.y < 4:
		return
	for n in names:
		var sb = c.get_theme_stylebox(n)
		if sb is StyleBoxTexture and sb.has_meta("frame"):
			var f = sb.get_meta("frame")
			var tex = _composed(f[0], f[1], sz)
			if tex != null:
				sb.texture = tex


static var _composed_cache := {}


# The frame drawn at exactly `sz` pixels: corners as they are, each edge its middle piece repeated a whole number of times (squeezed
# or stretched a little to fit), the inside filled with the picture's own middle.
static func _composed(frame: String, k: float, sz: Vector2i) -> Texture2D:
	var key = "%s@%.2f@%dx%d" % [frame, k, sz.x, sz.y]
	if _composed_cache.has(key):
		return _composed_cache[key]
	var src: Texture2D = _tex_scaled(frame, k)
	if src == null:
		return null
	var img: Image = src.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var m = _margins(frame, k)
	var w = img.get_width()
	var h = img.get_height()
	var cw = w - m[0] - m[2]
	var ch = h - m[1] - m[3]
	var tw = sz.x - m[0] - m[2]
	var th = sz.y - m[1] - m[3]
	if cw < 1 or ch < 1 or tw < 1 or th < 1:
		return null
	var out := Image.create(sz.x, sz.y, false, Image.FORMAT_RGBA8)
	var xs = [[0, m[0], 0, m[0]], [m[0], cw, m[0], tw], [w - m[2], m[2], sz.x - m[2], m[2]]]     # [src x, src w, dst x, dst w]
	var ys = [[0, m[1], 0, m[1]], [m[1], ch, m[1], th], [h - m[3], m[3], sz.y - m[3], m[3]]]
	for yi in 3:
		for xi in 3:
			var sx = xs[xi]
			var sy = ys[yi]
			if sx[1] <= 0 or sy[1] <= 0 or sx[3] <= 0 or sy[3] <= 0:
				continue
			var piece = img.get_region(Rect2i(sx[0], sy[0], sx[1], sy[1]))
			_tile_into(out, piece, Rect2i(sx[2], sy[2], sx[3], sy[3]), xi == 1, yi == 1)
	var tex = ImageTexture.create_from_image(out)
	if _composed_cache.size() > 200:
		_composed_cache.clear()
	_composed_cache[key] = tex
	return tex


# Fills `dst` with `piece`, repeated a whole number of times along each axis marked to repeat (stretched along the others).
static func _tile_into(out: Image, piece: Image, dst: Rect2i, rep_x: bool, rep_y: bool) -> void:
	var nx = max(1, int(round(float(dst.size.x) / piece.get_width()))) if rep_x else 1
	var ny = max(1, int(round(float(dst.size.y) / piece.get_height()))) if rep_y else 1
	for j in ny:
		for i in nx:
			var x0 = dst.position.x + int(round(float(dst.size.x) * i / nx))
			var x1 = dst.position.x + int(round(float(dst.size.x) * (i + 1) / nx))
			var y0 = dst.position.y + int(round(float(dst.size.y) * j / ny))
			var y1 = dst.position.y + int(round(float(dst.size.y) * (j + 1) / ny))
			if x1 <= x0 or y1 <= y0:
				continue
			var p = piece
			if p.get_width() != x1 - x0 or p.get_height() != y1 - y0:
				p = piece.duplicate()
				p.resize(x1 - x0, y1 - y0, Image.INTERPOLATE_BILINEAR)
			out.blit_rect(p, Rect2i(0, 0, p.get_width(), p.get_height()), Vector2i(x0, y0))


static func _tex_scaled(frame: String, k: float) -> Texture2D:
	var key = "%s@%.2f" % [frame, k]
	if _scaled.has(key):
		return _scaled[key]
	var src: Texture2D = Art.tex("ui/%s.png" % frame)
	var out: Texture2D = src
	if src != null and abs(k - 1.0) > 0.01:
		var img = src.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img = img.duplicate()
			img.resize(max(1, int(round(img.get_width() * k))), max(1, int(round(img.get_height() * k))), Image.INTERPOLATE_LANCZOS)
			out = ImageTexture.create_from_image(img)
	_scaled[key] = out
	return out


# A panel in one of the owner's frames.
static func panel(frame: String = "frame_wide", k: float = 1.0, pad: Vector2 = Vector2(10, 6)) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", box(frame, k, pad))
	fit(p, ["panel"])
	return p


# A button in the small frame: lighter under the mouse, darker when pressed or switched on, faded when it can't be used.
static func button(text: String, font_size: int = 20, k: float = 0.8, min_size: Vector2 = Vector2(0, 0)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", GOLD)
	b.add_theme_color_override("font_hover_pressed_color", GOLD)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.4))
	b.add_theme_color_override("font_outline_color", OUTLINE)
	b.add_theme_constant_override("outline_size", 4)
	var pad = Vector2(8, 2)
	b.add_theme_stylebox_override("normal", box("frame_small", k, pad))
	b.add_theme_stylebox_override("hover", box("frame_small", k, pad, Color(1.25, 1.18, 1.05)))
	b.add_theme_stylebox_override("pressed", box("frame_small", k, pad, Color(0.78, 0.7, 0.6)))
	b.add_theme_stylebox_override("hover_pressed", box("frame_small", k, pad, Color(0.9, 0.8, 0.66)))
	b.add_theme_stylebox_override("disabled", box("frame_small", k, pad, Color(0.6, 0.6, 0.6, 0.7)))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.custom_minimum_size = min_size
	fit(b, ["normal", "hover", "pressed", "hover_pressed", "disabled"])
	return b


static func label(text: String = "", font_size: int = 18, color: Color = INK, outline: int = 4) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", OUTLINE)
		l.add_theme_constant_override("outline_size", outline)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# Wrapping text of a fixed width.
static func para(text: String, font_size: int, width: float, color: Color = INK) -> Label:
	var l = label(text, font_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(width, 0)
	return l


# One of the owner's icons (a path under art/, e.g. "ui/food.png"), px square; null when the picture does not exist.
static func icon(path: String, px: float) -> TextureRect:
	var tex = Art.tex(path)
	if tex == null:
		return null
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


# The colony's sky with its hills behind a menu (scene/sky_view.gd on its own canvas layer), at a fixed hour ph (0.3 morning,
# 0.5 noon, 0.74 sunset, 0.0 midnight). The clouds drift; nothing else moves.
static func sky(parent: Node, ph: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = -10
	parent.add_child(layer)
	var cam := SkyCam.new()
	cam.day.update(Day.DAY_LEN * 2.0, 0.0, 0.0, ph)
	var v = SkyView.new()
	v.colony = cam
	layer.add_child(v)


# Stands in for the colony screen as far as the sky view is concerned: a camera resting just above the ground line.
class SkyCam:
	extends RefCounted
	var day = Day.new()

	func zoom() -> float:
		return 2.5

	func cam_center() -> Vector2:
		return Vector2(0.0, -90.0)

	func ground_y() -> float:
		return 0.0
