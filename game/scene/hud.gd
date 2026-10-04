extends Control
# The interface for now: one small panel in the owner's frame with the colony's numbers, and the speed. Phase 4 replaces it with
# the real top bar and command bar.

const Seasons = preload("res://core/seasons.gd")
const Art = preload("res://scene/art.gd")

const FRAME_MARGINS = [30, 26, 30, 26]
const INK = Color("#f1e6cf")
const DIM = Color("#b9a98c")
const ROWS = [["food", "food"], ["ants", "soldier"], ["brood", "brood"], ["season", "queen"], ["raids", "crown_red"]]

var colony
var _values := {}
var _speed: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := NinePatchRect.new()
	panel.texture = Art.tex("ui/frame_wide.png")
	panel.patch_margin_left = FRAME_MARGINS[0]
	panel.patch_margin_top = FRAME_MARGINS[1]
	panel.patch_margin_right = FRAME_MARGINS[2]
	panel.patch_margin_bottom = FRAME_MARGINS[3]
	panel.position = Vector2(12, 12)
	panel.size = Vector2(300, 250)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.position = Vector2(34, 26)
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	for row in ROWS:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = Art.tex("ui/%s.png" % row[1])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(30, 30)
		line.add_child(icon)
		var v := _label(18, INK)
		_values[row[0]] = v
		line.add_child(v)
		box.add_child(line)
	_speed = _label(15, DIM)
	box.add_child(_speed)


func _process(_delta: float) -> void:
	var sim = colony.sim
	var t: float = sim.time
	_values["food"].text = "%d food" % int(sim.food)
	_values["ants"].text = "%d ants" % sim.ants.size()
	_values["brood"].text = "%d brood" % sim.eggs.size()
	_values["season"].text = "%s, year %d" % [Seasons.name_of(t), Seasons.year(t)]
	_values["raids"].text = "%d raids" % sim.raid_n
	_speed.text = "Paused (Space)" if colony.paused else "Speed %dx (1, 2, 3)" % int(colony.speed)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
