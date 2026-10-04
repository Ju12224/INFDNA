extends Control
# The colony screen's interface: one top bar, one message line under it, and the pause menu.
#   top bar       food (stored / room), ants, brood, the queen's health, season and day, Will (the Director meter), the raid or
#                 the time to the next one, the arc once it starts, and the pause and speed buttons (Space, 1, 2, 3 still work).
#   message line  one sim event at a time (a new strain, a raid, the queen hurt, a boss, the seasons), read from the sim's
#                 banner and toasts, instead of piles of pop-ups.
#   pause menu    Esc: Resume, Restart (the same queen again), Quit to title. The whole colony screen stops while it is open.
# Only the owner's frames and icons (art/ui) and text; a number with no picture of its own is shown as text.

const Kit = preload("res://scene/menu_kit.gd")
const Seasons = preload("res://core/seasons.gd")
const Art = preload("res://scene/art.gd")
const Arc = preload("res://core/arc.gd")
const Run = preload("res://scene/run.gd")
const BugReport = preload("res://core/bug_report.gd")

const BAR_K = 0.55                     # the frame's size in the bar
const FONT = 18
const SPEED_LABELS = ["1x", "3x", "10x"]
const ARC_ICONS = ["", "ui/dominion.png", "ui/tremors.png", "ui/void.png"]
const RAID_ICON = "ui/raid.png"
const BOSS_ICON = "ui/boss.png"
const SEASON_ICONS = ["ui/season_spring.png", "ui/season_summer.png", "ui/season_autumn.png", "ui/season_winter.png"]
const MSG_MIN = 2.6                    # seconds a message stays at least (when more are waiting)
const MSG_MAX = 6.0                    # ... and at most
const MSG_QUEUE = 4
# words in a message -> its icon (first match wins)
const MSG_ICONS = [
	[["QUEEN", "queen"], "ui/queen.png"],
	[["VOID", "Void", "pit"], "ui/void.png"],
	[["Raid", "raid", "raiders", "attack", "Strike"], "ui/soldier.png"],
	[["anteater", "bird", "Bird", "spider", "Maw"], BOSS_ICON],
	[["shudders", "GROUND", "ground", "Tremor", "boom", "lurches", "earth"], "ui/tremors.png"],
	[["Dominion", "meadow belongs"], "ui/dominion.png"],
	[["strain", "Evolution", "body plan", "First", "evolved", "mutat"], "ui/brood.png"],
	[["food", "windfall", "Harvest", "larder"], "ui/food.png"],
	[["Will", "Recall", "Rally", "Surge", "Breed"], "ui/hivemind.png"],
]

var colony
var _v := {}                 # chip name -> its value label
var _chips := {}             # chip name -> its box (tooltips, hiding)
var _arc_icon: TextureRect
var _pause_btn: Button
var _speed_btns := []
var _paused_note: Label
var _msg_panel: PanelContainer
var _msg_box: HBoxContainer
var _msg_icon: TextureRect
var _msg_label: Label
var _msg_queue := []         # [{"text", "icon", "t"}]
var _msg_cur := {}
var _msg_age := 0.0
var _last_banner := ""
var _last_banner_t := 0.0
var _arc_best := 0
var _menu: Control
var _t := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS       # the pause menu works while the colony screen is stopped
	_build_bar()
	_build_message()
	_build_menu()
	Run.equip(colony.sim)                       # hands over the Lab items (colony.gd may already have done it)


# A new colony started on the same screen.
func reset() -> void:
	Run.equip(colony.sim)
	_msg_queue.clear()
	_msg_cur = {}
	_last_banner = ""
	_arc_best = 0


# ================================================================== build
func _build_bar() -> void:
	var bar = Kit.panel("frame_wide", BAR_K, Vector2(4, 0))
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 6
	bar.offset_right = -6
	bar.offset_top = 4
	bar.mouse_filter = Control.MOUSE_FILTER_STOP     # clicks on the bar never reach the world under it
	add_child(bar)
	var row = Kit.hbox(14)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	bar.add_child(row)
	_chip(row, "food", "ui/food.png", "Food in the stores / room in the food chambers")
	_chip(row, "ants", "ui/soldier.png", "Ants in the colony")
	_chip(row, "brood", "ui/brood.png", "Eggs waiting to hatch")
	_chip(row, "queen", "ui/queen.png", "The queen's health. If she falls, the colony falls.")
	_chip(row, "season", SEASON_ICONS[0], "Season and day. A season lasts five minutes at 1x; winter is lean.")
	_chip(row, "will", "ui/hivemind.png", "Will: the Director's meter. It fills over time and pays for the powers (right-click the ground).")
	_chip(row, "raid", RAID_ICON, "Raids: the one under way, or how long until the next")
	_chip(row, "arc", "", "The arc: how far the colony's monsters have taken the meadow")
	_arc_icon = Kit.icon("ui/dominion.png", 30)
	_chips["arc"].add_child(_arc_icon)
	_chips["arc"].move_child(_arc_icon, 0)
	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var speeds = Kit.hbox(4)
	speeds.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(speeds)
	_pause_btn = _bar_button(speeds, "||", "Pause (Space)")
	_pause_btn.pressed.connect(_on_pause)
	for i in SPEED_LABELS.size():
		var b = _bar_button(speeds, SPEED_LABELS[i], "Speed %s (%d)" % [SPEED_LABELS[i], i + 1])
		b.pressed.connect(_on_speed.bind(i))
		_speed_btns.append(b)
	_paused_note = Kit.label("Paused  (Space to go on)", 20, Kit.GOLD)
	_paused_note.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_paused_note.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_paused_note.offset_top = 104
	_paused_note.visible = false
	add_child(_paused_note)


func _chip(parent: Node, key: String, icon_path: String, tip: String) -> void:
	var h = Kit.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_PASS
	h.tooltip_text = tip
	if icon_path != "":
		var ic = Kit.icon(icon_path, 30)
		if ic != null:
			h.add_child(ic)
	var l = Kit.label("", FONT)
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	h.add_child(l)
	parent.add_child(h)
	_v[key] = l
	_chips[key] = h


func _bar_button(parent: Node, text: String, tip: String) -> Button:
	var b = Kit.button(text, 16, 0.42, Vector2(46, 32))
	b.toggle_mode = true
	b.tooltip_text = tip
	parent.add_child(b)
	return b


func _build_message() -> void:
	_msg_panel = Kit.panel("frame_small", 0.6, Vector2(10, 0))
	_msg_panel.position = Vector2(0, 74)
	_msg_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_msg_panel)
	_msg_box = Kit.hbox(8)
	_msg_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_msg_panel.add_child(_msg_box)
	_msg_icon = TextureRect.new()
	_msg_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_msg_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_msg_icon.custom_minimum_size = Vector2(30, 30)
	_msg_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg_box.add_child(_msg_icon)
	_msg_label = Kit.label("", 18, Kit.INK, 4)
	_msg_box.add_child(_msg_label)
	_msg_panel.modulate.a = 0.0


func _build_menu() -> void:
	_menu = Control.new()
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	_menu.visible = false
	add_child(_menu)
	var dim = ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.05, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(dim)
	var cc = CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(cc)
	var p = Kit.panel("frame_wide", 1.0, Vector2(30, 18))
	cc.add_child(p)
	var v = Kit.vbox(12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var head = Kit.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(head)
	var qi = Kit.icon("ui/queen.png", 44)
	if qi != null:
		head.add_child(qi)
	head.add_child(Kit.label("Paused", 34, Kit.GOLD))
	var sub = Kit.label("", 17, Kit.DIM)
	sub.name = "Sub"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	for e in [["Resume", "_close_menu"], ["Restart", "_restart"], ["Quit to title", "_quit_to_title"]]:
		var b = Kit.button(e[0], 22, 0.8, Vector2(280, 52))
		b.pressed.connect(Callable(self, e[1]))
		v.add_child(b)
	var hint = Kit.label("Esc to resume", 15, Kit.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)


# ================================================================== every frame
func _process(delta: float) -> void:
	_t += delta
	if colony == null or colony.sim == null:
		return
	var sim = colony.sim
	if not get_tree().paused:
		_refresh_bar(sim)
		_read_events(sim)
		_step_message(delta)
	_paused_note.visible = colony.paused and not _menu.visible


func _refresh_bar(sim) -> void:
	_v["food"].text = "%d / %d" % [int(sim.food), int(sim.food_cap)]
	_v["food"].add_theme_color_override("font_color", Kit.BAD if sim.food < sim.egg_cost * 3.0 else Kit.INK)
	_v["ants"].text = "%d" % sim.ants.size()
	_v["brood"].text = "%d" % sim.eggs.size()
	var qf = clamp(sim.queen_hp / max(1.0, sim.queen_max), 0.0, 1.0)
	_v["queen"].text = "%d%%" % int(round(qf * 100.0))
	var hurt = sim.queen_flash > 0.0 or qf < 0.35
	_v["queen"].add_theme_color_override("font_color", Kit.BAD if hurt else (Kit.GOLD if qf < 0.7 else Kit.INK))
	var day = colony.day
	var yr = Seasons.year(sim.time)
	_v["season"].text = "%s, day %d" % [Seasons.NAMES[day.season], day.day_n]
	_chips["season"].tooltip_text = "Year %d. A season lasts five minutes at 1x; winter is lean." % yr
	var season_icon = _chips["season"].get_child(0)
	if season_icon is TextureRect:
		season_icon.texture = Art.tex(SEASON_ICONS[clampi(day.season, 0, 3)])
	_v["will"].text = "%d / %d" % [int(sim.will), int(sim.will_max())]
	var raid_on = sim._raid_active or not sim.raid_queue.is_empty()
	if raid_on:
		var n = sim.hostile_count() + sim.raid_queue.size()
		_v["raid"].text = "Raid %d: %d" % [sim.raid_n, n]
		_v["raid"].add_theme_color_override("font_color", Kit.BAD)
	else:
		var s = int(max(0.0, sim.raid_timer))
		_v["raid"].text = "Next raid %d:%02d" % [s / 60, s % 60]
		_v["raid"].add_theme_color_override("font_color", Kit.INK)
	var st = int(clamp(sim.arc_stage, 0, 3))
	_arc_best = max(_arc_best, st)
	sim.set_meta("arc_best", _arc_best)
	_chips["arc"].visible = st > 0
	if st > 0:
		var txt = Arc.label(sim)
		if st == Arc.TREMORS:
			txt = "Tremors %d/%d" % [sim.arc_tremors, Arc.TREMORS_N]
		elif st == Arc.VOID:
			txt = "The Void"
		_v["arc"].text = txt
		_arc_icon.texture = Kit.Art.tex(ARC_ICONS[st])
		_v["arc"].add_theme_color_override("font_color", Kit.GOLD.lerp(Kit.BAD, 0.5 + 0.5 * sin(_t * 3.0)) if st >= 2 else Kit.GOLD)
	_pause_btn.set_pressed_no_signal(colony.paused)
	for i in _speed_btns.size():
		_speed_btns[i].set_pressed_no_signal(not colony.paused and is_equal_approx(colony.speed, colony.SPEEDS[i]))


func _on_pause() -> void:
	colony.paused = not colony.paused


func _on_speed(i: int) -> void:
	colony.speed = colony.SPEEDS[i]
	colony.paused = false


# ---- the message line
# New sim events: the banner (raids, the queen, bosses, the arc) goes first; the toasts queue behind it.
func _read_events(sim) -> void:
	if sim.banner != "" and sim.banner_t > 0.0 and (sim.banner != _last_banner or sim.banner_t > _last_banner_t + 0.5):
		_last_banner = sim.banner
		_push(sim.banner, sim.banner_t + 1.0, true)
	_last_banner_t = sim.banner_t
	var said = ""                                  # what controls.gd just put on its own line (answers to orders and powers)
	var ctl = colony.views.get("controls") if "views" in colony else null
	if ctl != null and float(ctl.get("_msg_t") if ctl.get("_msg_t") != null else 0.0) > 0.0:
		said = str(ctl.get("_msg"))
	for t in sim.toasts:
		if t.has("_hud"):
			continue
		t["_hud"] = true
		if str(t.get("text", "")) != said:
			_push(str(t.get("text", "")), float(t.get("t", 4.0)), false)


func _push(text: String, t: float, urgent: bool) -> void:
	if text == "" or (not _msg_cur.is_empty() and _msg_cur["text"] == text):
		return
	for m in _msg_queue:
		if m["text"] == text:
			return
	var m = {"text": text, "icon": _icon_for(text), "t": clamp(t, MSG_MIN, MSG_MAX)}
	if urgent:
		_msg_queue.push_front(m)
	else:
		_msg_queue.append(m)
	while _msg_queue.size() > MSG_QUEUE:
		_msg_queue.pop_back()


func _step_message(delta: float) -> void:
	_msg_age += delta
	var due = not _msg_cur.is_empty() and (_msg_age >= _msg_cur["t"] or (not _msg_queue.is_empty() and _msg_age >= MSG_MIN))
	if (_msg_cur.is_empty() or due) and not _msg_queue.is_empty():
		_msg_cur = _msg_queue.pop_front()
		_msg_age = 0.0
		_msg_label.text = _msg_cur["text"]
		_msg_panel.reset_size()
		var tex = Kit.Art.tex(_msg_cur["icon"]) if _msg_cur["icon"] != "" else null
		_msg_icon.texture = tex
		_msg_icon.visible = tex != null
	elif due:
		_msg_cur = {}
	var a := 0.0
	if not _msg_cur.is_empty():
		a = clamp(_msg_age / 0.2, 0.0, 1.0) * clamp((_msg_cur["t"] - _msg_age) / 0.5, 0.0, 1.0) if _msg_queue.is_empty() else clamp(_msg_age / 0.2, 0.0, 1.0)
	_msg_panel.modulate.a = a
	_msg_panel.visible = a > 0.0
	if _msg_panel.visible:
		_msg_panel.position.x = round((size.x - _msg_panel.size.x) * 0.5)


func _icon_for(text: String) -> String:
	for e in MSG_ICONS:
		for w in e[0]:
			if text.find(w) >= 0:
				return e[1]
	return ""


# ================================================================== the pause menu
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _menu.visible:
			_close_menu()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()
	elif _menu.visible and event is InputEventKey:
		get_viewport().set_input_as_handled()      # Space and the speed keys wait until the menu is closed


func _open_menu() -> void:
	var sim = colony.sim
	var sub: Label = _menu.find_child("Sub", true, false)
	if sub != null:
		sub.text = "%s  -  %s, day %d  -  %d ants" % [sim.queen_def.get("name", ""), Seasons.NAMES[colony.day.season], colony.day.day_n, sim.ants.size()]
	_menu.visible = true
	get_tree().paused = true


func _close_menu() -> void:
	_menu.visible = false
	get_tree().paused = false


func is_menu_open() -> bool:
	return _menu.visible


func _restart() -> void:
	get_tree().paused = false
	BugReport.write("colony restarted")
	get_tree().change_scene_to_file(Run.COLONY)


func _quit_to_title() -> void:
	get_tree().paused = false
	BugReport.write("left the colony")
	get_tree().change_scene_to_file(Run.TITLE)
