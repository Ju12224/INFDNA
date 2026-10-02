extends Button
# Brotato-styled button: ink outline, drop shadow, hover lift, press squash,
# accent-coloured selected state, optional icon, hover/click sounds.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")

var accent := Color("#f2c14e")
var icon_key := ""
var icon_size := 26.0
var _icon: TextureRect
var _snd_h: AudioStreamPlayer
var _snd_c: AudioStreamPlayer
var _tw: Tween
var _base_h := 46.0
var silent := false


func setup(txt: String, key: String = "", col: Color = Color("#f2c14e"), size: int = 24) -> Button:
	text = txt
	icon_key = key
	accent = col
	add_font_override("font", Kit.font(size, 2))
	return self


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	if rect_min_size.y < _base_h:
		rect_min_size.y = _base_h
	var pad_l = 0.0
	if icon_key != "" and Kit.icon(icon_key) != null:
		pad_l = icon_size + 6.0
		_icon = Kit.icon_rect(self, icon_key, icon_size)
		_icon.rect_position = Vector2(12, 0)
	var n = Kit.flat(Kit.BG_HI, Kit.INK, 10, 3, 8.0)
	var h = Kit.flat(Color("#46404f"), accent.darkened(0.15), 10, 3, 8.0)
	var p = Kit.flat(accent, Kit.INK, 10, 3, 8.0, 2)
	var d = Kit.flat(Color("#231f2a"), Kit.INK, 10, 3, 8.0, 0)
	for s in [n, h, p, d]:
		s.content_margin_left += pad_l
	add_stylebox_override("normal", n)
	add_stylebox_override("hover", h)
	add_stylebox_override("pressed", p)
	add_stylebox_override("hover_pressed", Kit.flat(accent.lightened(0.18), Kit.INK, 10, 3, 8.0, 2))
	add_stylebox_override("disabled", d)
	add_color_override("font_color_pressed", Kit.INK)
	add_color_override("font_color_hover_pressed", Kit.INK)
	add_color_override("font_color_disabled", Color(1, 1, 1, 0.3))
	_tw = Tween.new()
	add_child(_tw)
	_snd_h = _player(Kit.SND_HOVER, -16.0)
	_snd_c = _player(Kit.SND_CLICK, -9.0)
	connect("mouse_entered", self, "_on_enter")
	connect("mouse_exited", self, "_on_exit")
	connect("button_down", self, "_on_down")
	connect("button_up", self, "_on_up")
	connect("resized", self, "_layout")
	connect("toggled", self, "_on_toggled")
	_layout()


func _player(path: String, db: float) -> AudioStreamPlayer:
	var pl = AudioStreamPlayer.new()
	pl.bus = "Sound" if AudioServer.get_bus_index("Sound") != -1 else "Master"
	if ResourceLoader.exists(path):
		pl.stream = load(path)
	pl.volume_db = db
	add_child(pl)
	return pl


func _layout() -> void:
	rect_pivot_offset = rect_size * 0.5
	if _icon != null:
		_icon.rect_position = Vector2(12, (rect_size.y - icon_size) * 0.5)


func _to(scale_to: float, dur: float, trans: int = Tween.TRANS_BACK) -> void:
	_tw.remove_all()
	_tw.interpolate_property(self, "rect_scale", rect_scale, Vector2.ONE * scale_to, dur, trans, Tween.EASE_OUT)
	_tw.start()


func _on_enter() -> void:
	if disabled:
		return
	_to(1.07, 0.14)
	if not silent and _snd_h != null and _snd_h.stream != null:
		_snd_h.pitch_scale = rand_range(0.95, 1.08)
		_snd_h.play()


func _on_exit() -> void:
	_to(1.0, 0.16, Tween.TRANS_SINE)


func _on_down() -> void:
	if not disabled:
		_to(0.93, 0.07, Tween.TRANS_SINE)


func _on_up() -> void:
	_to(1.07 if get_global_rect().has_point(get_global_mouse_position()) else 1.0, 0.16)
	if not disabled and not silent and _snd_c != null and _snd_c.stream != null:
		_snd_c.pitch_scale = rand_range(0.95, 1.05)
		_snd_c.play()


func _on_toggled(on: bool) -> void:
	if on:
		Kit.bump(self, 1.14, 0.24)
