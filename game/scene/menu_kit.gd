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
	"frame_small": [22, 16, 22, 16],
	"frame_wide": [34, 30, 34, 30],
	"stone_small": [16, 16, 16, 16],
	"stone_wide": [26, 28, 26, 28],
	"frame_tall": [26, 44, 26, 44],
}

static var _scaled := {}


# The owner's frame as a stylebox, shrunk to k of its drawn size (borders included) so it fits small controls; the inside keeps the
# picture's own fill, tiled rather than smeared. `pad` is the room between the border and the content.
static func box(frame: String, k: float = 1.0, pad: Vector2 = Vector2(6, 2), tint: Color = Color.WHITE) -> StyleBox:
	var tex = _tex_scaled(frame, k)
	if tex == null:
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(8)
		return empty
	var m: Array = FRAMES.get(frame, [16, 16, 16, 16])
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = round(m[0] * k)
	sb.texture_margin_top = round(m[1] * k)
	sb.texture_margin_right = round(m[2] * k)
	sb.texture_margin_bottom = round(m[3] * k)
	sb.content_margin_left = round(m[0] * k) + pad.x
	sb.content_margin_right = round(m[2] * k) + pad.x
	sb.content_margin_top = round(m[1] * k) + pad.y
	sb.content_margin_bottom = round(m[3] * k) + pad.y
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	sb.modulate_color = tint
	return sb


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
