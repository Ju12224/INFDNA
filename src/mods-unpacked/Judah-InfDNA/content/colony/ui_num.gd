extends Label
# Number label that counts toward its target and pops / flashes on change.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")

var fmt := "%d"
var target := 0.0
var shown := 0.0
var flash_up := Color("#a8ec74")
var flash_down := Color("#ff8a7a")
var _flash := 0.0
var _fc := Color.white
var _base := Color.white
var _first := true


func setup(f: Font, format: String = "%d", col: Color = Color.white) -> Label:
	add_font_override("font", f)
	fmt = format
	_base = col
	add_color_override("font_color", col)
	return self


func set_value(v: float) -> void:
	if _first:
		shown = v
		_first = false
	elif abs(v - target) >= 1.0:
		_flash = 1.0
		_fc = flash_up if v > target else flash_down
		rect_pivot_offset = rect_size * 0.5
		rect_scale = Vector2.ONE * 1.16
	target = v


func _process(delta: float) -> void:
	shown = lerp(shown, target, 1.0 - exp(-delta * 10.0))
	if abs(shown - target) < 0.05:
		shown = target
	text = fmt % shown
	if _flash > 0.0:
		_flash = max(0.0, _flash - delta * 2.4)
		add_color_override("font_color", _base.linear_interpolate(_fc, _flash))
		rect_scale = rect_scale.linear_interpolate(Vector2.ONE, 1.0 - exp(-delta * 12.0))
