extends Control
# Step 1.0 test build: the game opens on its own and runs a colony with no world drawn yet, only its numbers in the owner's
# panel frame. It proves the new engine runs on the player's PC; the real colony screen replaces this from step 1.1.
# A colony that collapses is replaced by a new one. Closing the window writes the report (InfDNA_report.txt on the Desktop).

const Sim = preload("res://core/colony_sim.gd")
const Seasons = preload("res://core/seasons.gd")
const BugReport = preload("res://core/bug_report.gd")

const STEP = 0.1                 # sim seconds per sim step
const MAX_STEPS = 4              # per frame, so a slow frame never snowballs
const REPORT_EVERY = 60.0        # seconds between report saves while running (a crash still leaves the last one)
const FRAME_MARGINS = [30, 26, 30, 26]
const BG = Color("#1b1610")
const INK = Color("#f1e6cf")
const DIM = Color("#b9a98c")

var sim
var colonies := 0
var _acc := 0.0
var _report_t := 0.0
var _values := {}                # name -> Label
var _status: Label


func _ready() -> void:
	get_tree().auto_accept_quit = false
	_build()
	_new_colony()


func _new_colony() -> void:
	colonies += 1
	sim = Sim.new(randi() % 1000000, "well_rounded")
	BugReport.colony_started()


func _process(delta: float) -> void:
	BugReport.frame(delta)
	_acc = min(_acc + delta, STEP * MAX_STEPS)
	var n := 0
	while _acc >= STEP and n < MAX_STEPS:
		sim.step(STEP)
		_acc -= STEP
		n += 1
	if sim.collapsed:
		_new_colony()
	_report_t += delta
	if _report_t >= REPORT_EVERY:
		_report_t = 0.0
		BugReport.write("running")
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not BugReport.closing():
			BugReport.write("game closed", true)
		get_tree().quit()


func _refresh() -> void:
	var t: float = sim.time
	_values["food"].text = str(int(sim.food))
	_values["ants"].text = str(sim.ants.size())
	_values["brood"].text = str(sim.eggs.size())
	_values["season"].text = "%s, year %d" % [Seasons.name_of(t), Seasons.year(t)]
	_values["raids"].text = str(sim.raid_n)
	_status.text = "Colony %d has been running for %d:%02d." % [colonies, int(t) / 60, int(t) % 60]


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := NinePatchRect.new()
	panel.texture = load("res://art/ui/frame_wide.png")
	panel.patch_margin_left = FRAME_MARGINS[0]
	panel.patch_margin_top = FRAME_MARGINS[1]
	panel.patch_margin_right = FRAME_MARGINS[2]
	panel.patch_margin_bottom = FRAME_MARGINS[3]
	panel.custom_minimum_size = Vector2(760, 560)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 64
	box.offset_right = -64
	box.offset_top = 48
	box.offset_bottom = -48
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	box.add_child(_label("InfDNA", 52, INK))
	box.add_child(_label("Test build for step 1.0: the game now runs on its own.", 20, DIM))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	for row in [["food", "Food", "food"], ["ants", "Ants", "soldier"], ["brood", "Brood", "brood"], ["season", "Season", "queen"], ["raids", "Raids", "crown_red"]]:
		var icon := TextureRect.new()
		icon.texture = load("res://art/ui/%s.png" % row[2])
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(40, 40)
		grid.add_child(icon)
		grid.add_child(_label(row[1], 22, DIM))
		var v := _label("", 22, INK)
		_values[row[0]] = v
		grid.add_child(v)

	_status = _label("", 18, DIM)
	box.add_child(_status)
	box.add_child(_label("Close the window when you're done. A report lands on your Desktop.", 16, DIM))


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
