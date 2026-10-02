extends Control
# Brotato lifebar (bg / fill / frame textures) with a smooth fill, a trailing
# "lag" bar that shows recent loss, an optional icon, and a value label.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")

var value := 0.0
var max_value := 1.0
var color := Color("#7ed957")
var icon_key := ""
var caption := ""
var show_text := true
var flash := 0.0            # 0..1 white-hot flash (damage / gain)
var flash_color := Color(1, 1, 1)
var _shown := 0.0
var _lag := 0.0
var _font: Font
var _bg
var _fill
var _frame
var _icon
var _inited := false


func setup(key: String, col: Color, h: float = 30.0, w: float = 300.0, font_size: int = 20) -> Control:
	icon_key = key
	color = col
	rect_min_size = Vector2(w, h)
	_font = Kit.font(font_size, 2)
	_bg = Kit.tex(Kit.T_BAR_BG)
	_fill = Kit.tex(Kit.T_BAR_FILL)
	_frame = Kit.tex(Kit.T_BAR_FRAME)
	_icon = Kit.icon(key)
	return self


func set_values(v: float, m: float, cap: String = "") -> void:
	value = v
	max_value = max(0.0001, m)
	caption = cap
	if not _inited:
		_shown = v
		_lag = v
		_inited = true


func pulse(col: Color = Color(1, 1, 1)) -> void:
	flash = 1.0
	flash_color = col


func _process(delta: float) -> void:
	var k = 1.0 - exp(-delta * 9.0)
	_shown = lerp(_shown, value, k)
	if _lag > _shown:
		_lag = max(_shown, _lag - max_value * 0.35 * delta)   # loss trails behind, then drains
	else:
		_lag = _shown
	flash = max(0.0, flash - delta * 2.6)
	update()


func _draw() -> void:
	var h = rect_size.y
	var x0 = h * 0.75 if _icon != null else 0.0
	var r = Rect2(x0, h * 0.14, rect_size.x - x0, h * 0.72)
	var frac = clamp(_shown / max_value, 0.0, 1.0)
	var lag = clamp(_lag / max_value, 0.0, 1.0)
	if _bg != null:
		draw_texture_rect(_bg, r, false)
	else:
		draw_rect(r, Color(0, 0, 0, 0.5))
	if lag > frac + 0.002 and _fill != null:
		draw_texture_rect_region(_fill, Rect2(r.position, Vector2(r.size.x * lag, r.size.y)), Rect2(0, 0, 320.0 * lag, 48), Color(1, 1, 1, 0.55))
	if _fill != null and frac > 0.001:
		var c = color.lightened(0.35 * flash)
		draw_texture_rect_region(_fill, Rect2(r.position, Vector2(r.size.x * frac, r.size.y)), Rect2(0, 0, 320.0 * frac, 48), c)
		# glossy strip
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(max(0.0, r.size.x * frac - 6), r.size.y * 0.22)), Color(1, 1, 1, 0.16))
	if _frame != null:
		draw_texture_rect(_frame, r, false)
	if flash > 0.0:
		draw_rect(r, Color(flash_color.r, flash_color.g, flash_color.b, 0.35 * flash))
	if _icon != null:
		var s = h * 1.25
		draw_texture_rect(_icon, Rect2(-2, h * 0.5 - s * 0.5, s, s), false)
	if show_text and _font != null:
		var txt = caption if caption != "" else "%d / %d" % [int(max(0.0, round(_shown))), int(max_value)]
		var sz = _font.get_string_size(txt)
		draw_string(_font, Vector2(r.position.x + (r.size.x - sz.x) * 0.5, r.position.y + (r.size.y + sz.y * 0.62) * 0.5), txt)
