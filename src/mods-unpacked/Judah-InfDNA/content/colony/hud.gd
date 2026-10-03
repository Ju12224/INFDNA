extends CanvasLayer
# Colony HUD in Brotato's own visual language: ink-outlined panels, lifebar
# textures, stat icons, tweened pops/slides. Built in code.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")
const KBtn = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_button.gd")
const KBar = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_bar.gd")
const KNum = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_num.gd")
const ShopItems = preload("res://mods-unpacked/Judah-InfDNA/core/shop_items.gd")
const Queens = preload("res://mods-unpacked/Judah-InfDNA/core/queens.gd")
const LayersView = preload("res://mods-unpacked/Judah-InfDNA/content/colony/layers_view.gd")
const Sim = preload("res://mods-unpacked/Judah-InfDNA/core/colony_sim.gd")
const RunLog = preload("res://mods-unpacked/Judah-InfDNA/core/run_log.gd")
const Legacy = preload("res://mods-unpacked/Judah-InfDNA/core/legacy.gd")
const Wild = preload("res://mods-unpacked/Judah-InfDNA/core/wild.gd")

const HINT_VIEW = "Drag a box to select ants  ·  Right-click: orders and powers\nWheel: zoom  ·  WASD: pan  ·  Space: pause  ·  Tab: panels\nMouse to the top edge: map  ·  bottom edge: speed, Lab, menu"
const HINT_CLEAN = "Drag: select ants   Right-click: orders and powers   Q: free them   Wheel: zoom   WASD: pan   Space: pause   Tab: more panels"
const HINT_FULL = "WASD / middle-drag pan   Wheel zoom   Drag: select ants   Right-click: orders and powers   Q: free   Space: pause   Tab: view mode   Esc: menu\nLayers P C F T H X K O   Powers R E Z J M Y   L lineage   U nest   N new strain   V watch   I goals"
const VIEW_SHIFT = 44.0          # in view mode the pause chip, banner and toasts sit this much higher (no minimap above them)
const REVEAL_IN = 38.0           # the mouse this near the top or bottom edge (HUD units) slides the minimap or the speed bar in
const REVEAL_OUT = 140.0         # ...and it slides away again once the mouse is this far from the edge

# task order in the sim: NURSE, FORAGE, DIG, HOME, DEFEND (shared with the Tasks layer so the legend matches)
const TASK_COLORS = LayersView.TASK_COLORS
const TASK_LABELS = LayersView.TASK_LABELS

var scene            # colony_scene.gd
var _f_s: Font
var _f_m: Font
var _f_l: Font
var _f_xl: Font
var root: Control

var _portrait_bg: TextureRect
var _portrait_ic: TextureRect
var _name: Label
var _sub: Label
var _food_bar: Control
var _food_note: Label
var _queen_bar: Control
var _chip_nums := {}
var _caste_nums := []
var _task_bar: Control
var _task_txt: Label
var _stat_labels := {}
var _raid_icon: TextureRect
var _raid_title: Label
var _raid_bar: Control
var _raid_note: Label
var _raid_total := 1
var _graph: Control
var _lineage_box: VBoxContainer
var _lineage_sig := ""
var _inspect: PanelContainer
var _insp_tex: TextureRect
var _insp_caste: Label
var _insp_task: Label
var _insp_hp: Control
var _insp_age: Control
var _insp_stats := {}
var _insp_line: Label
var _insp_prev = null
var _banner: PanelContainer
var _banner_label: Label
var _banner_text := ""
var _toasts: VBoxContainer
var _toast_nodes := {}
var _pause_chip: PanelContainer
var _speed_btns := []
var _layers_panel: PanelContainer
var _layer_btns := {}
var _task_legend: HBoxContainer
var _mm: Control
var _mm_panel: Control
var _hint: Label
var _dir_panel: PanelContainer
var _will_bar: Control
var _dir_btns := {}
var _dir_sig := {}
var _caste_btns := []
var _dir_hint: Label
var _watch_chip: Label
var _watch_info: Label
var _watch_t := 0.0
var _watch_hidden := []      # nodes hidden in watch mode, with the visibility to restore
# View mode (the default, Tab cycles): the bare world and a thin status line. The minimap and the speed / Lab / menu bar slide in when
# the mouse touches the top or bottom edge; everything is done with drag-select and the right-click menu (context_menu.gd).
# Standard: the colony card, raid timer, minimap, speed bar. Full: every panel.
var mode := 0
var _strip: Control          # the status line (view mode)
var _tag_panel: PanelContainer
var _tag_label: Label
var _notch_top: Label
var _notch_bot: Label
var _mm_a := 0.0
var _bar_a := 0.0
var _mm_in := false
var _bar_in := false
# The clean screen: by default only the colony card, the raid timer, the minimap, speed, Lab and Menu are up (plus a bar for the selected
# ants). Tab (or the Panels button) brings every panel back.
var compact := true
var _extra_nodes := []       # parts of the colony card and the graph card that only the full screen shows
var _more_box: HBoxContainer # Focus and Brood levers
var _panels_btn: Button
var _squad_panel: PanelContainer
var _squad_label: Label
var _squad_hint: Label
var _squad_sig := ""
var _quality_btn: Button
var _mm_font: Font
const MM_W = 640.0
const MM_H = 44.0
const SPEED_LABELS = ["||", "1x", "2x", "4x", "10x"]
var _vig: Control
var _vig_a := 0.0
var _shop_root: Control
var _shop_dim: ColorRect
var _shop: PanelContainer
var _shop_title_food: Label
var _shop_cards: HBoxContainer
var _shop_owned: GridContainer
var _shop_owned_note: Label
var _reroll_btn: Button
var _reroll_icon: TextureRect
var _collapse_root: Control
var _legacy_box: VBoxContainer
var _legacy_row: VBoxContainer
var _legacy_label: Label
var _wild_label: Label
var _collapse_label: Label
var _collapse_stats: Label
var _collapse_best: Label
var _collapse_shown := false
var _refresh := 0.0
# M4 evolution panel (L key / Lineage button): trait spread over time + ancestry strip
var _evo_root: PanelContainer
var _evo_holder: Control
var _evo_chart: Control
var _evo_title: Label
var _evo_strip: HBoxContainer
var _evo_strip_title: Label
var _evo_sig := ""
const TRAIT_COLORS = {"wings": Color("#9fd8ff"), "stinger": Color("#e8483b"), "acid": Color("#b9e04a"),
	"glow": Color("#f7e26b"), "major": Color("#c9863b"), "replete": Color("#f2a65a"), "camo": Color("#6b8f5a"),
	"armor": Color("#9aa3b5"), "claws": Color("#d46bd4"), "spikes": Color("#ff8a5c"),
	"legform": Color("#7fe0c4"), "antform": Color("#c7a4ff"), "venom": Color("#4fd17a"),
	"sonic": Color("#ffe9a8"), "electric": Color("#7fe9ff"), "shell": Color("#d2a868"), "silk": Color("#f2f2f2"),
	"tongue": Color("#ff8fb1"), "regen": Color("#9dff9a"), "fusion": Color("#ff5cf0")}
var _t := 0.0


func _ready() -> void:
	layer = 10
	_f_s = Kit.font(19, 1)
	_f_m = Kit.font(24, 2)
	_f_l = Kit.font(34, 3)
	_f_xl = Kit.font(52, 4)
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_fit_root()
	get_viewport().connect("size_changed", self, "_fit_root")

	_vig = Control.new()
	_vig.anchor_right = 1.0
	_vig.anchor_bottom = 1.0
	_vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vig.connect("draw", self, "_draw_vignette")
	root.add_child(_vig)

	_build_left()
	_build_lineage()
	_build_bar()
	_build_director()
	_build_squad()
	_build_view()
	_build_inspector()
	_build_overlays()
	_build_shop()
	_build_collapse()
	_build_evolution()
	set_mode(0)

	# scene enters from black
	Kit.fade_rect(root, Color("#0b0910"), 1.0, 0.0, 0.7)
	Kit.slide_in(_left_col, Vector2(-60, 0), 0.15)
	Kit.slide_margins(_lineage_panel, Vector2(60, 0), 0.25)
	Kit.slide_margins(_bar_panel, Vector2(0, 70), 0.3)


# The layout is built for a 1920x1080 view. On a smaller window the whole HUD is scaled down to the same
# proportions instead of overlapping itself (panels, lever bar and layer buttons are fixed-size).
func _fit_root() -> void:
	var vs = get_viewport().get_visible_rect().size
	var k = clamp(vs.y / 1080.0, 0.5, 1.0)
	root.anchor_left = 0.0
	root.anchor_top = 0.0
	root.anchor_right = 0.0
	root.anchor_bottom = 0.0
	root.rect_position = Vector2.ZERO
	root.rect_size = vs / k
	root.rect_scale = Vector2(k, k)


# ================================================================== build: left column
var _left_col: VBoxContainer
var _lineage_panel: PanelContainer
var _bar_panel: PanelContainer


func _card(parent: Node, tint: Color = Color(0.3, 0.28, 0.38)) -> VBoxContainer:
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", Kit.panel(tint, 0.94, 8.0))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 8)
	p.add_child(v)
	return v


func _chip(parent: Node, key: String, col: Color, fmt: String = "%d") -> Label:
	var pc = PanelContainer.new()
	pc.add_stylebox_override("panel", Kit.flat(col.darkened(0.62), col, 8, 2, 3.0, 3))
	parent.add_child(pc)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 5)
	pc.add_child(h)
	Kit.icon_rect(h, key, 26)
	var n = KNum.new()
	n.setup(_f_s, fmt)
	h.add_child(n)
	return n


func _build_left() -> void:
	_left_col = VBoxContainer.new()
	_left_col.add_constant_override("separation", 10)
	_left_col.rect_position = Vector2(20, 18)
	_left_col.rect_min_size = Vector2(430, 0)
	root.add_child(_left_col)

	# ---- colony card
	var q = scene.sim.queen_def
	var qcol = Color(q["color"])
	var v = _card(_left_col)
	var head = HBoxContainer.new()
	head.add_constant_override("separation", 12)
	v.add_child(head)
	var pf = Control.new()
	pf.rect_min_size = Vector2(76, 76)
	head.add_child(pf)
	_portrait_bg = TextureRect.new()
	_portrait_bg.texture = Kit.tex(Kit.T_CIRCLE)
	_portrait_bg.modulate = qcol.lightened(0.1)
	_portrait_bg.expand = true
	_portrait_bg.rect_size = Vector2(76, 76)
	_portrait_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf.add_child(_portrait_bg)
	var ring = TextureRect.new()
	ring.texture = Kit.tex(Kit.T_RING)
	ring.modulate = Kit.INK
	ring.expand = true
	ring.rect_size = Vector2(76, 76)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf.add_child(ring)
	_portrait_ic = TextureRect.new()
	_portrait_ic.texture = Kit.tex(Queens.icon_path(q))
	_portrait_ic.expand = true
	_portrait_ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_ic.rect_position = Vector2(8, 8)
	_portrait_ic.rect_size = Vector2(60, 60)
	_portrait_ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf.add_child(_portrait_ic)
	var hv = VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.alignment = BoxContainer.ALIGN_CENTER
	head.add_child(hv)
	_name = Kit.label(hv, q["name"], _f_l)
	_sub = Kit.label(hv, "Day 1", _f_s)
	_sub.modulate = Color(1, 1, 1, 0.7)

	_food_bar = KBar.new().setup("food", Kit.GREEN, 34, 396, 21)
	v.add_child(_food_bar)
	_food_note = Kit.label(v, "", _f_s)
	_food_note.modulate = Color(1, 1, 1, 0.85)
	_queen_bar = KBar.new().setup("hp", Kit.RED, 30, 396, 19)
	v.add_child(_queen_bar)

	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	v.add_child(row)
	_chip_nums["ants"] = _chip(row, "ant", Color("#c9c9d9"))
	_chip_nums["eggs"] = _chip(row, "egg", Color("#f7f1e3"))
	_chip_nums["kills"] = _chip(row, "crit", Kit.GOLD)
	_chip_nums["lost"] = _chip(row, "skull", Color("#8a8a9a"))

	var crow = HBoxContainer.new()
	crow.add_constant_override("separation", 8)
	v.add_child(crow)
	_extra_nodes.append(crow)
	for i in 3:
		_caste_nums.append(_chip(crow, Kit.CASTE_KEYS[i], Kit.CASTE_COLORS[i]))

	_task_bar = Control.new()
	_task_bar.rect_min_size = Vector2(396, 16)
	_task_bar.connect("draw", self, "_draw_tasks")
	v.add_child(_task_bar)
	_task_txt = Kit.label(v, "", _f_s)
	_task_txt.modulate = Color(1, 1, 1, 0.8)
	_extra_nodes.append(_task_bar)
	_extra_nodes.append(_task_txt)

	var srow = HBoxContainer.new()
	srow.add_constant_override("separation", 10)
	v.add_child(srow)
	_extra_nodes.append(srow)
	for k in ["speed", "carry", "attack", "hp"]:
		var b = HBoxContainer.new()
		b.add_constant_override("separation", 3)
		srow.add_child(b)
		Kit.icon_rect(b, k, 24)
		_stat_labels[k] = Kit.label(b, "0", _f_s)

	# ---- raid card
	var rv = _card(_left_col, Color(0.34, 0.26, 0.26))
	var rh = HBoxContainer.new()
	rh.add_constant_override("separation", 10)
	rv.add_child(rh)
	_raid_icon = Kit.icon_rect(rh, "horde", 44)
	var rt = VBoxContainer.new()
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(rt)
	_raid_title = Kit.label(rt, "Next raid", _f_m)
	_raid_note = Kit.label(rt, "", _f_s)
	_raid_note.add_color_override("font_color", Color("#ff8a7a"))
	_raid_bar = KBar.new().setup("", Kit.GOLD, 22, 396, 16)
	_raid_bar.show_text = false
	rv.add_child(_raid_bar)

	# ---- population / food graph
	var gv = _card(_left_col)
	_extra_nodes.append(gv.get_parent())
	_graph = Control.new()
	_graph.rect_min_size = Vector2(396, 74)
	_graph.connect("draw", self, "_draw_graph")
	gv.add_child(_graph)


# ================================================================== build: lineages
func _build_lineage() -> void:
	_lineage_panel = PanelContainer.new()
	_lineage_panel.add_stylebox_override("panel", Kit.panel(Color(0.3, 0.28, 0.38), 0.94, 8.0))
	_lineage_panel.anchor_left = 1.0
	_lineage_panel.anchor_right = 1.0
	_lineage_panel.margin_left = -500
	_lineage_panel.margin_right = -50
	_lineage_panel.margin_top = 18
	root.add_child(_lineage_panel)
	var lv = VBoxContainer.new()
	lv.add_constant_override("separation", 6)
	_lineage_panel.add_child(lv)
	var t = HBoxContainer.new()
	lv.add_child(t)
	Kit.icon_rect(t, "power", 30)
	Kit.label(t, " Dominant body plans", _f_m)
	_lineage_box = VBoxContainer.new()
	_lineage_box.add_constant_override("separation", 6)
	lv.add_child(_lineage_box)


# ================================================================== build: bottom lever bar
func _build_bar() -> void:
	_bar_panel = PanelContainer.new()
	_bar_panel.add_stylebox_override("panel", Kit.panel(Color(0.3, 0.28, 0.38), 0.95, 6.0))
	_bar_panel.anchor_left = 0.5
	_bar_panel.anchor_right = 0.5
	_bar_panel.anchor_top = 1.0
	_bar_panel.anchor_bottom = 1.0
	_bar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bar_panel.margin_bottom = -16
	root.add_child(_bar_panel)
	var bar = HBoxContainer.new()
	bar.add_constant_override("separation", 8)
	_bar_panel.add_child(bar)
	_more_box = HBoxContainer.new()
	_more_box.add_constant_override("separation", 8)
	bar.add_child(_more_box)
	_group(_more_box, "Focus", [["Forage", "food"], ["Balanced", "balanced"], ["Dig", "dig"], ["Defend", "armor"]], 1, "_on_focus",
		["Ants favor foraging", "Even split", "Ants favor digging", "Ants rally to defend"])
	_sep(_more_box)
	_group(_more_box, "Brood", [["Low", ""], ["Normal", ""], ["High", ""]], 1, "_on_brood",
		["Slow, cheap brood", "Standard egg rate", "Fast eggs, drains food"])
	_sep(_more_box)
	_speed_btns = _group(bar, "Speed", [["||", ""], ["1x", ""], ["2x", ""], ["4x", ""], ["10x", ""]], 1, "_on_speed",
		["Pause (Space)", "1x (key 1)", "2x (key 2)", "4x (key 3)", "10x (key 4). If the colony is too big for 10x, the readout shows the speed you actually get."])
	_sep(bar)
	_btn(bar, "Lab", "luck").connect("pressed", scene, "open_shop")
	_btn(bar, "Menu", "exit").connect("pressed", scene, "go_to_menu")
	_panels_btn = _btn(bar, "Panels", "sense")
	_panels_btn.hint_tooltip = "Show more panels, then every panel, then back to the bare view (Tab)"
	_panels_btn.connect("pressed", self, "cycle_mode")

	var hint = Kit.label(root, HINT_CLEAN, _f_s)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.margin_left = 22
	hint.margin_bottom = -96
	hint.modulate = Color(1, 1, 1, 0.55)
	_hint = hint
	_build_layers()
	_build_minimap()


# World strip across the top: the nest in the middle, out to the farthest a trip can reach. Piles, fruit
# trees, ants, raiders and the camera view are marked, so the long expeditions can be followed. Click or
# drag to jump the camera along the world.
func _build_minimap() -> void:
	_mm_font = Kit.font(15, 2)
	var pc = PanelContainer.new()
	pc.add_stylebox_override("panel", Kit.flat(Color(0.12, 0.11, 0.15, 0.9), Kit.INK, 8, 3, 3.0, 3))
	pc.anchor_left = 0.5
	pc.anchor_right = 0.5
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.margin_top = 12
	root.add_child(pc)
	_mm_panel = pc
	_mm = Control.new()
	_mm.rect_min_size = Vector2(MM_W, MM_H)
	_mm.mouse_filter = Control.MOUSE_FILTER_STOP
	_mm.hint_tooltip = "World map: click or drag to jump along the world"
	_mm.connect("draw", self, "_draw_minimap")
	_mm.connect("gui_input", self, "_on_mm_input")
	pc.add_child(_mm)


func _mm_scale() -> float:
	return MM_W / (2.0 * Sim.RANGE_MAX)


func _draw_minimap() -> void:
	var sim = scene.sim
	var g = sim.grid
	var ex = int(g.entrance.x)
	var sc = _mm_scale()
	var cy = MM_H * 0.5
	_mm.draw_rect(Rect2(0, 0, MM_W, MM_H), Color(0.45, 0.62, 0.78, 0.45))
	_mm.draw_rect(Rect2(0, cy + 6.0, MM_W, MM_H - cy - 6.0), Color(0.42, 0.3, 0.2, 0.85))
	_mm.draw_rect(Rect2(0, cy + 4.0, MM_W, 3.0), Color(0.45, 0.7, 0.3))
	for km in [-1500, -1000, -500, 500, 1000, 1500]:
		var tx = MM_W * 0.5 + km * sc
		_mm.draw_line(Vector2(tx, cy + 2.0), Vector2(tx, cy + 9.0), Color(1, 1, 1, 0.5), 1.0)
		_mm.draw_string(_mm_font, Vector2(tx - 12.0, MM_H - 2.0), str(abs(km)), Color(1, 1, 1, 0.55))
	for tr in sim.trees:
		var x = MM_W * 0.5 + (tr["x"] - ex) * sc
		_mm.draw_rect(Rect2(x - 1.5, cy - 9.0, 3.0, 13.0), Color("#3f7a34"))
		_mm.draw_circle(Vector2(x, cy - 10.0), 3.4, Color("#5fa046"))
	for lm in sim.landmarks:
		var xl = MM_W * 0.5 + (lm["x"] - ex) * sc
		if not lm["found"]:
			_mm.draw_circle(Vector2(xl, cy - 5.0), 1.6, Color(1, 1, 1, 0.22))     # something is out there
		elif lm["kind"] == "cave":
			_mm.draw_circle(Vector2(xl, cy + 2.0), 4.2, Kit.INK)
			_mm.draw_circle(Vector2(xl, cy + 2.0), 3.0, Color("#b07a4a"))
		elif lm["kind"] == "vista":
			_mm.draw_colored_polygon(PoolVector2Array([Vector2(xl - 4.0, cy + 4.0), Vector2(xl + 4.0, cy + 4.0), Vector2(xl, cy - 5.0)]), Color("#cfd6da"))
	for p in sim.piles:
		var x2 = MM_W * 0.5 + (p["x"] - ex) * sc
		var k = p.get("kind", "")
		var col = Color("#ffd86b") if k == "jackpot" else (Color("#f0a233") if k == "fruit" else (Color("#a8553a") if k == "carcass" else Color("#9bf06a")))
		_mm.draw_circle(Vector2(x2, cy + 1.0), 3.2 if k == "jackpot" else (2.8 if k == "carcass" else 2.2), col)
	for b in sim.beacons:
		var x3 = MM_W * 0.5 + (b["x"] - ex) * sc
		_mm.draw_line(Vector2(x3, cy + 4.0), Vector2(x3, cy - 12.0), Color("#7ed957"), 2.0)
	var far = 0
	for a in sim.ants:
		var x4 = MM_W * 0.5 + (a.x - ex) * sc
		far = max(far, abs(a.x - ex))
		_mm.draw_rect(Rect2(x4 - 1.0, cy - 1.0 - (3.0 if a.carry > 0.0 else 0.0), 2.0, 2.0), TASK_COLORS[int(clamp(a.task, 0, 4))])
	for e in sim.enemies:
		var x5 = MM_W * 0.5 + (e.x - ex) * sc
		_mm.draw_circle(Vector2(x5, cy - 3.0), 2.8 if e.cls == "prey" else 3.6, Color("#9fe3a8") if e.cls == "prey" else Color("#ff4a3d"))
	# the director's orders and the bird
	if sim.rally_t > 0.0:
		var rx = MM_W * 0.5 + (sim.rally_x - ex) * sc
		_mm.draw_line(Vector2(rx, cy + 8.0), Vector2(rx, cy - 12.0), Color("#ff6a4a"), 2.0)
		_mm.draw_colored_polygon(PoolVector2Array([Vector2(rx, cy - 12.0), Vector2(rx + 9.0, cy - 9.0), Vector2(rx, cy - 5.0)]), Color("#ff6a4a"))
	if sim.harvest_t > 0.0:
		var hx = MM_W * 0.5 + (sim.harvest_x - ex) * sc
		_mm.draw_circle(Vector2(hx, cy - 3.0), 6.0, Color(1.0, 0.85, 0.42, 0.5 + 0.4 * sin(_t * 6.0)))
	if sim.bird != null:
		var bx = MM_W * 0.5 + (sim.bird["x"] - ex) * sc
		var blink = 0.55 + 0.45 * sin(_t * 8.0)
		_mm.draw_colored_polygon(PoolVector2Array([Vector2(bx - 7.0, cy - 12.0), Vector2(bx + 7.0, cy - 12.0), Vector2(bx, cy - 2.0)]), Color(1.0, 0.25, 0.2, blink))
		_mm.draw_string(_mm_font, Vector2(bx - 3.0, cy - 14.0), "!", Color(1, 1, 1, blink))
	# the rival's mound, once found
	if sim.rival.found:
		var rvx = MM_W * 0.5 + (sim.rival.x - ex) * sc
		var rcol = Color("#c63a2a") if sim.rival.alive() else Color(0.5, 0.5, 0.5, 0.8)
		_mm.draw_colored_polygon(PoolVector2Array([Vector2(rvx - 5.0, cy + 6.0), Vector2(rvx + 5.0, cy + 6.0), Vector2(rvx, cy - 7.0)]), Kit.INK)
		_mm.draw_colored_polygon(PoolVector2Array([Vector2(rvx - 3.5, cy + 5.0), Vector2(rvx + 3.5, cy + 5.0), Vector2(rvx, cy - 4.5)]), rcol)
	# nest
	_mm.draw_colored_polygon(PoolVector2Array([Vector2(MM_W * 0.5 - 5.0, cy + 6.0), Vector2(MM_W * 0.5 + 5.0, cy + 6.0), Vector2(MM_W * 0.5, cy - 7.0)]), Kit.GOLD)
	# the camera's view
	if scene.cam != null:
		var vp = get_viewport().size
		var half = vp.x * scene.cam.zoom.x * 0.5 / g.CELL
		var cx = scene.cam.get_camera_screen_center().x / g.CELL
		var x6 = MM_W * 0.5 + (cx - ex - half) * sc
		_mm.draw_rect(Rect2(x6, 1.0, max(3.0, half * 2.0 * sc), MM_H - 2.0), Color(1, 1, 1, 0.9), false, 1.5)
	_mm.draw_string(_mm_font, Vector2(6.0, 14.0), "farthest ant: %d cells" % far, Color(1, 1, 1, 0.85))
	_mm.draw_string(_mm_font, Vector2(MM_W - 96.0, 14.0), "%d fps  Q%d" % [Engine.get_frames_per_second(), scene.perf.tier], Color(1, 1, 1, 0.7))


func _on_mm_input(ev: InputEvent) -> void:
	var down = (ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT) or (ev is InputEventMouseMotion and (ev.button_mask & BUTTON_MASK_LEFT) != 0)
	if not down:
		return
	var g = scene.sim.grid
	var cell = int(g.entrance.x) + (ev.position.x - MM_W * 0.5) / _mm_scale()
	scene.set_layer("follow", false)
	scene.cam.position.x = cell * g.CELL
	scene.cam.position.y = g.surf_y(int(cell)) * g.CELL - 140.0


# View layers: toggles above the lever bar (same state as the P / C / F / T / H keys), plus a legend
# for the task colours while the Tasks layer is on.
func _build_layers() -> void:
	_layers_panel = PanelContainer.new()
	_layers_panel.add_stylebox_override("panel", Kit.panel(Color(0.3, 0.28, 0.38), 0.92, 4.0))
	_layers_panel.anchor_left = 0.5
	_layers_panel.anchor_right = 0.5
	_layers_panel.anchor_top = 1.0
	_layers_panel.anchor_bottom = 1.0
	_layers_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_layers_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_layers_panel.margin_bottom = -168     # above the lever bar and its two-line key hint
	root.add_child(_layers_panel)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 6)
	_layers_panel.add_child(v)
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	v.add_child(row)
	var l = Kit.label(row, "Layers", _f_s)
	l.valign = Label.VALIGN_CENTER
	l.modulate = Color(1, 1, 1, 0.7)
	for it in [["trails", "Trails (P)", "sense", "Food scent trails on the ground"],
			["castes", "Badges (C)", "soldier", "Caste badge over each ant"],
			["fights", "Fights (F)", "attack", "Rings under raiders, links to the ants hitting them, health on fighters, arrows to off-screen raiders"],
			["tasks", "Tasks (T)", "balanced", "Colour halo on every ant for what it is doing right now"],
			["health", "Health (H)", "hp", "Health bar over every ant"],
			["follow", "Follow (X)", "ant", "The camera follows the selected ant (click an ant first)"],
			["light", "Night (K)", "luck", "Day and night light. Off keeps it midday."],
			["sound", "Sound (O)", "tempo", "Wind, birdsong, crickets, rain and the murmur of the earth: made up as it plays, quiet. Off mutes it."]]:
		var b = _btn(row, it[1], it[2], Color("#f2c14e"), 20)
		b.toggle_mode = true
		b.pressed = scene.layer_state[it[0]]
		b.hint_tooltip = it[3]
		b.connect("toggled", self, "_on_layer_toggled", [it[0]])
		_layer_btns[it[0]] = b
	var lin = _btn(row, "Lineage (L)", "power", Color("#f2c14e"), 20)
	lin.hint_tooltip = "Body plans over time: trait spread and ancestry"
	lin.connect("pressed", self, "toggle_evolution")
	_quality_btn = _btn(row, scene.perf.label(), "luck", Color("#7ed957"), 20)
	_quality_btn.hint_tooltip = "The optimizer. Auto lowers detail when the frame rate dips and restores it when smooth. Click to cycle Auto / High / Medium / Low."
	_quality_btn.connect("pressed", self, "_on_quality")
	_task_legend = HBoxContainer.new()
	_task_legend.add_constant_override("separation", 14)
	_task_legend.alignment = BoxContainer.ALIGN_CENTER
	v.add_child(_task_legend)
	for i in TASK_COLORS.size():
		var sw = PanelContainer.new()
		sw.add_stylebox_override("panel", Kit.flat(TASK_COLORS[i], Kit.INK, 4, 2, 0.0, 0))
		sw.rect_min_size = Vector2(16, 16)
		_task_legend.add_child(sw)
		Kit.label(_task_legend, TASK_LABELS[i], _f_s)
	_task_legend.visible = scene.layer_state["tasks"]


# ================================================================== build: the director's panel
# Will (fills over time) and the commands it buys, plus the brood's caste order. Keys work too (see colony_scene).
const CMD_ICONS = {"rally": "attack", "harvest": "food", "recall": "armor", "surge": "speed", "breed": "power", "strike": "horde"}


func _build_director() -> void:
	_dir_panel = PanelContainer.new()
	_dir_panel.add_stylebox_override("panel", Kit.panel(Color(0.34, 0.26, 0.3), 0.95, 6.0))
	_dir_panel.anchor_left = 1.0
	_dir_panel.anchor_right = 1.0
	_dir_panel.margin_left = -466
	_dir_panel.margin_right = -50
	_dir_panel.margin_top = 420
	root.add_child(_dir_panel)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 5)
	_dir_panel.add_child(v)
	var t = Kit.label(v, "Director", _f_m, Kit.GOLD)
	t.align = Label.ALIGN_CENTER
	_will_bar = KBar.new().setup("luck", Kit.GOLD, 28, 330, 17)
	v.add_child(_will_bar)
	for id in Sim.COMMANDS.keys():
		var c = Sim.COMMANDS[id]
		var b = _btn(v, "", CMD_ICONS.get(id, ""), Color("#f2c14e"), 20)
		b.hint_tooltip = "%s (%s): %s. Costs %d Will, recharges in %d s." % [c["name"], c["key"], c["tip"], int(c["cost"]), int(c["cd"])]
		b.connect("pressed", self, "_on_cmd", [id])
		_dir_btns[id] = b
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	v.add_child(row)
	var cl = Kit.label(row, "Brood", _f_s)
	cl.valign = Label.VALIGN_CENTER
	cl.modulate = Color(1, 1, 1, 0.7)
	var bg = ButtonGroup.new()
	var names = [["Mixed", ""], ["Workers", ""], ["Soldiers", ""]]
	var tips = ["The queen breeds whatever the colony needs", "Lean toward foragers and diggers", "Lean toward soldiers"]
	for i in names.size():
		var cb = _btn(row, names[i][0], "", Color("#f2c14e"), 17)
		cb.toggle_mode = true
		cb.group = bg
		cb.pressed = i == 0
		cb.hint_tooltip = tips[i]
		cb.connect("pressed", self, "_on_caste", [i])
		_caste_btns.append(cb)
	_dir_hint = Kit.label(root, "", _f_m, Kit.GOLD)
	_dir_hint.anchor_left = 0.5
	_dir_hint.anchor_right = 0.5
	_dir_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_dir_hint.margin_top = 150
	_dir_hint.visible = false


# The bar for the ants the player has selected: how many, how many are under orders, what a right-click does, and a button to free them.
func _build_squad() -> void:
	_squad_panel = PanelContainer.new()
	_squad_panel.add_stylebox_override("panel", Kit.panel(Color(0.22, 0.32, 0.44), 0.96, 6.0))
	_squad_panel.anchor_left = 0.5
	_squad_panel.anchor_right = 0.5
	_squad_panel.anchor_top = 1.0
	_squad_panel.anchor_bottom = 1.0
	_squad_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_squad_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_squad_panel.margin_bottom = -134
	_squad_panel.visible = false
	root.add_child(_squad_panel)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 18)
	_squad_panel.add_child(h)
	_squad_label = Kit.label(h, "", _f_m, Color("#bfe6ff"))
	_squad_hint = Kit.label(h, "Right-click: a spot to guard  ·  a food pile to harvest  ·  a raider to attack  ·  soil to dig", _f_s)
	_squad_hint.modulate = Color(1, 1, 1, 0.8)
	_squad_hint.valign = Label.VALIGN_CENTER
	var fb = _btn(h, "Free (Q)", "exit", Color("#f2c14e"), 20)
	fb.hint_tooltip = "Let the selected ants go back to their own work"
	fb.connect("pressed", scene, "release_selection")


func _refresh_squad() -> void:
	var sel = scene.selection
	var vis = not sel.empty() and not scene.watch_mode and not scene.shop_open and not scene.sim.collapsed
	_squad_panel.visible = vis and mode != 0
	_tag_panel.visible = vis and mode == 0
	if not vis:
		return
	var ordered := 0
	for a in sel:
		if a.squad != 0:
			ordered += 1
	var sig = "%d|%d|%d" % [sel.size(), ordered, mode]
	if sig != _squad_sig:
		_squad_sig = sig
		var head = "%d selected%s" % [sel.size(), ("  ·  %d under orders" % ordered) if ordered > 0 else ""]
		_squad_label.text = head
		_tag_label.text = head + "   ·   right-click for orders" + ("   ·   Q frees" if ordered > 0 else "")


# ================================================================== view mode
func _build_view() -> void:
	_strip = Control.new()
	_strip.rect_position = Vector2(20, 14)
	_strip.rect_size = Vector2(900, 36)
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.connect("draw", self, "_draw_strip")
	root.add_child(_strip)

	_tag_panel = PanelContainer.new()
	_tag_panel.add_stylebox_override("panel", Kit.flat(Color(0.1, 0.16, 0.24, 0.85), Kit.INK, 8, 2, 4.0, 0))
	_tag_panel.anchor_left = 0.5
	_tag_panel.anchor_right = 0.5
	_tag_panel.anchor_top = 1.0
	_tag_panel.anchor_bottom = 1.0
	_tag_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tag_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_tag_panel.margin_bottom = -34
	_tag_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag_panel.visible = false
	root.add_child(_tag_panel)
	_tag_label = Kit.label(_tag_panel, "", _f_s, Color("#bfe6ff"))
	_tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# faint hints at the two edges that slide something in; they fade after the first minute
	_notch_top = Kit.label(root, "map", _mm_font)
	_notch_top.anchor_left = 0.5
	_notch_top.anchor_right = 0.5
	_notch_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notch_top.margin_top = 2
	_notch_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_notch_bot = Kit.label(root, "speed  ·  Lab  ·  menu", _mm_font)
	_notch_bot.anchor_left = 0.5
	_notch_bot.anchor_right = 0.5
	_notch_bot.anchor_top = 1.0
	_notch_bot.anchor_bottom = 1.0
	_notch_bot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notch_bot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_notch_bot.margin_bottom = -2
	_notch_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE


# The status line: day, food, queen, ants, the next raid (or the raid), Will. Drawn, not laid out, so it costs next to nothing.
func _draw_strip() -> void:
	var sim = scene.sim
	var ops := []
	var x := 12.0
	var txt = "Day %d  ·  %s" % [sim.day, Sim.Seasons.NAMES[scene.day.season]]
	ops.append(["text", x, txt, Color(1, 1, 1, 0.75)])
	x += _f_s.get_string_size(txt).x + 22.0
	var fr = clamp(sim.food / max(1.0, sim.food_cap), 0.0, 1.0)
	ops.append(["icon", x, "food"])
	ops.append(["bar", x + 28.0, fr, Kit.GREEN if fr > 0.15 else Kit.RED, 96.0])
	x += 28.0 + 96.0 + 20.0
	var qf = clamp(sim.queen_hp / max(1.0, sim.queen_max), 0.0, 1.0)
	ops.append(["icon", x, "hp"])
	ops.append(["bar", x + 28.0, qf, Kit.RED if qf < 0.5 else Kit.GREEN, 64.0])
	x += 28.0 + 64.0 + 20.0
	ops.append(["icon", x, "ant"])
	var an = str(sim.ants.size())
	ops.append(["text", x + 28.0, an, Color.white])
	x += 28.0 + _f_s.get_string_size(an).x + 20.0
	var hostile = sim.hostile_count() + sim.raid_queue.size()
	ops.append(["icon", x, "horde"])
	var rt = ("RAID  %d" % hostile) if hostile > 0 else ("%ds" % int(max(0.0, sim.raid_timer)))
	var rc = Color("#ff7a6a") if hostile > 0 else Color(1, 1, 1, 0.85)
	ops.append(["text", x + 28.0, rt, rc])
	x += 28.0 + _f_s.get_string_size(rt).x + 20.0
	ops.append(["icon", x, "luck"])
	ops.append(["bar", x + 28.0, clamp(sim.will / max(1.0, sim.will_max()), 0.0, 1.0), Kit.GOLD, 64.0])
	x += 28.0 + 64.0 + 12.0
	_strip.draw_rect(Rect2(0, 0, x, 34), Color(0.08, 0.07, 0.11, 0.55))
	_strip.draw_rect(Rect2(0, 0, 3, 34), Color(0.95, 0.76, 0.3, 0.8))
	for o in ops:
		match o[0]:
			"text":
				_strip.draw_string(_f_s, Vector2(o[1], 24.0), o[2], o[3])
			"icon":
				var tx = Kit.icon(o[2])
				if tx != null:
					_strip.draw_texture_rect(tx, Rect2(o[1], 5.0, 24, 24), false)
			"bar":
				_strip.draw_rect(Rect2(o[1], 12.0, o[4], 10.0), Kit.INK)
				_strip.draw_rect(Rect2(o[1] + 1.0, 13.0, (o[4] - 2.0) * o[2], 8.0), o[3])


func cycle_mode() -> void:
	set_mode(mode + 1)


# 0 view, 1 standard, 2 full.
func set_mode(m: int) -> void:
	mode = posmod(m, 3)
	set_compact(mode != 2)
	var shift = -VIEW_SHIFT if mode == 0 else 0.0
	_pause_chip.margin_top = 84 + shift
	_banner.margin_top = 110 + shift
	_toasts.margin_top = 196 + shift
	_inspect.margin_bottom = -104
	if scene.ug != null:
		scene.ug.update_mode()
	if not scene.watch_mode:
		_left_col.visible = mode != 0
		_strip.visible = mode == 0
		_notch_top.visible = mode == 0
		_notch_bot.visible = mode == 0
		_strip.modulate.a = 1.0
		_tag_panel.modulate.a = 1.0
		if mode != 0:
			_mm_a = 1.0
			_bar_a = 1.0
			_mm_panel.visible = true
			_bar_panel.visible = true
			_mm_panel.modulate.a = 1.0
			_bar_panel.modulate.a = 1.0
		else:
			_mm_in = false
			_bar_in = false
			_mm_a = 0.0
			_bar_a = 0.0
			_mm_panel.visible = false
			_bar_panel.visible = false
		_hint.visible = true
		_hint.modulate.a = 0.6
	_hint.text = HINT_VIEW if mode == 0 else (HINT_CLEAN if mode == 1 else HINT_FULL)
	_hint.margin_bottom = -22 if mode == 0 else -96
	_panels_btn.text = ["Panels", "All", "Hide"][mode]
	_strip.update()
	_squad_sig = ""


# View mode: the minimap and the bottom bar slide in when the mouse touches their edge (with a little hysteresis so they do not flicker)
# and out again when it moves away. Never while a drag is going on, the menu is up or a screen covers the world.
func _edge_reveal(delta: float) -> void:
	if mode != 0 or scene.watch_mode:
		return
	var vs = get_viewport().get_visible_rect().size
	var k = root.rect_scale.x
	var m = get_viewport().get_mouse_position()
	var busy = scene.shop_open or scene.sim.collapsed or evo_open_now()
	var dragging = scene._lmb or scene._rmb or scene.cmenu.is_open
	var top_d = m.y / k
	var bot_d = (vs.y - m.y) / k
	if busy:
		_mm_in = false
		_bar_in = false
	elif not dragging:
		if _mm_in:
			_mm_in = top_d < REVEAL_OUT
		else:
			_mm_in = top_d < REVEAL_IN
		if _bar_in:
			_bar_in = bot_d < REVEAL_OUT
		else:
			_bar_in = bot_d < REVEAL_IN
	var f = 1.0 - exp(-14.0 * delta)
	_mm_a = lerp(_mm_a, 1.0 if _mm_in else 0.0, f)
	_bar_a = lerp(_bar_a, 1.0 if _bar_in else 0.0, f)
	_mm_panel.visible = _mm_a > 0.03
	_bar_panel.visible = _bar_a > 0.03
	_mm_panel.modulate.a = _mm_a
	_bar_panel.modulate.a = _bar_a
	# the faint edge hints, and the key hints, are for the first minute
	var fade = 1.0 - smoothstep(30.0, 34.0, _t)
	_hint.modulate.a = 0.6 * fade * (1.0 - _bar_a)
	_hint.visible = _hint.modulate.a > 0.01
	var nf = 0.42 * (1.0 - smoothstep(60.0, 66.0, _t))
	_notch_top.modulate.a = nf * (1.0 - _mm_a)
	_notch_bot.modulate.a = nf * (1.0 - _bar_a)
	# what the sliding panels would cover gives way to them
	_strip.modulate.a = 1.0 - _mm_a
	_tag_panel.modulate.a = 1.0 - _bar_a
	# the inspector sits above the bar only while the bar is out
	_inspect.margin_bottom = lerp(-24.0, -104.0, _bar_a)


func evo_open_now() -> bool:
	return _evo_holder != null and _evo_holder.visible


func _on_cmd(id: String) -> void:
	scene.command(id)


func _on_caste(i: int) -> void:
	scene.sim.caste_order = i


func _refresh_director() -> void:
	var sim = scene.sim
	_will_bar.set_values(sim.will, sim.will_max(), "Will  %d" % int(sim.will))
	for id in _dir_btns.keys():
		var c = Sim.COMMANDS[id]
		var cd = sim.cmd_cd.get(id, 0.0)
		var cost = sim.cmd_cost(id)
		var usable = id != "strike" or sim.rival.can_strike()
		var ready = cd <= 0.0 and sim.will >= cost and usable
		var armed = scene.armed == id
		var sig = "%d|%d|%s|%d|%d|%d" % [int(ceil(cd)), int(sim.will >= cost), str(armed), int(ceil(cost)), int(sim.cmd_recharge(id)), int(usable)]
		var b: Button = _dir_btns[id]
		if _dir_sig.get(id, "") != sig:
			_dir_sig[id] = sig
			var tail = ("%ds" % int(ceil(cd))) if cd > 0.0 else ("%d" % int(ceil(cost)))
			b.text = "%s  (%s)    %s" % [c["name"], c["key"], tail]
			b.hint_tooltip = "%s (%s): %s. Costs %d Will, recharges in %d s." % [c["name"], c["key"], c["tip"], int(ceil(cost)), int(round(sim.cmd_recharge(id)))]
			if not usable:
				b.hint_tooltip += "\n" + ("The %s are broken for now." % sim.rival.name if sim.rival.found else "No rival nest found yet: send foragers farther.")
			b.modulate = Color(1, 1, 1, 1.0 if ready else 0.5)
		b.pressed = armed
	_dir_hint.visible = scene.armed != "" and not scene.watch_mode
	if scene.armed != "":
		_dir_hint.text = "Click the ground to use %s   (Esc or right-click cancels)" % Sim.COMMANDS[scene.armed]["name"]
	for i in _caste_btns.size():
		if _caste_btns[i].pressed != (i == sim.caste_order):
			_caste_btns[i].pressed = i == sim.caste_order


# ================================================================== build: inspector
func _build_inspector() -> void:
	_inspect = PanelContainer.new()
	_inspect.anchor_left = 1.0
	_inspect.anchor_right = 1.0
	_inspect.anchor_top = 1.0
	_inspect.anchor_bottom = 1.0
	_inspect.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_inspect.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_inspect.margin_right = -50
	_inspect.margin_bottom = -104
	_inspect.visible = false
	root.add_child(_inspect)
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 14)
	_inspect.add_child(h)
	var left = VBoxContainer.new()
	h.add_child(left)
	_insp_tex = TextureRect.new()
	_insp_tex.rect_min_size = Vector2(190, 150)
	_insp_tex.expand = true
	_insp_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	left.add_child(_insp_tex)
	_insp_task = Kit.label(left, "", _f_s)
	_insp_task.align = Label.ALIGN_CENTER
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 6)
	v.rect_min_size = Vector2(330, 0)
	h.add_child(v)
	_insp_caste = Kit.label(v, "", _f_m)
	_insp_hp = KBar.new().setup("hp", Kit.GREEN, 26, 330, 17)
	v.add_child(_insp_hp)
	_insp_age = KBar.new().setup("tempo", Kit.BLUE, 22, 330, 15)
	v.add_child(_insp_age)
	var g = GridContainer.new()
	g.columns = 4
	g.add_constant_override("hseparation", 8)
	g.add_constant_override("vseparation", 3)
	v.add_child(g)
	for k in [["speed", "speed"], ["carry", "carry"], ["dig", "dig"], ["sense", "sense"], ["attack", "attack"], ["armor", "armor"], ["thorns", "fire"], ["upkeep", "food"]]:
		var cell = HBoxContainer.new()
		cell.add_constant_override("separation", 2)
		g.add_child(cell)
		Kit.icon_rect(cell, k[1], 22)
		_insp_stats[k[0]] = Kit.label(cell, "", _f_s)
	_insp_line = Kit.label(v, "", _f_s)
	_insp_line.modulate = Color(1, 1, 1, 0.75)
	_insp_line.autowrap = true


# ================================================================== build: overlays
func _build_overlays() -> void:
	_pause_chip = PanelContainer.new()
	_pause_chip.add_stylebox_override("panel", Kit.flat(Color("#2b2733"), Kit.GOLD, 10, 3, 5.0, 4))
	_pause_chip.anchor_left = 0.5
	_pause_chip.anchor_right = 0.5
	_pause_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause_chip.margin_top = 84
	root.add_child(_pause_chip)
	Kit.label(_pause_chip, "PAUSED", _f_m, Kit.GOLD)
	_pause_chip.visible = false

	_banner = PanelContainer.new()
	_banner.anchor_left = 0.5
	_banner.anchor_right = 0.5
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.margin_top = 110
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_banner)
	_banner_label = Kit.label(_banner, "", _f_l)
	_banner_label.align = Label.ALIGN_CENTER
	_banner.visible = false

	_watch_chip = Kit.label(root, "WATCH MODE   ·   V to exit   ·   move the camera to take over", _f_s)
	_watch_chip.anchor_left = 0.5
	_watch_chip.anchor_right = 0.5
	_watch_chip.anchor_top = 1.0
	_watch_chip.anchor_bottom = 1.0
	_watch_chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_watch_chip.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_watch_chip.margin_bottom = -18
	_watch_chip.visible = false
	_watch_info = Kit.label(root, "", _f_m)
	_watch_info.anchor_top = 1.0
	_watch_info.anchor_bottom = 1.0
	_watch_info.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_watch_info.margin_left = 24
	_watch_info.margin_bottom = -18
	_watch_info.visible = false

	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.margin_top = 196
	_toasts.add_constant_override("separation", 6)
	_toasts.alignment = BoxContainer.ALIGN_CENTER
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toasts)


# ================================================================== build: Evolution Lab
func _build_shop() -> void:
	_shop_root = Control.new()
	_shop_root.anchor_right = 1.0
	_shop_root.anchor_bottom = 1.0
	_shop_root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_shop_root)
	_shop_dim = ColorRect.new()
	_shop_dim.color = Color(0.03, 0.02, 0.05, 0.0)
	_shop_dim.anchor_right = 1.0
	_shop_dim.anchor_bottom = 1.0
	_shop_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_root.add_child(_shop_dim)
	var cc = CenterContainer.new()
	cc.anchor_right = 1.0
	cc.anchor_bottom = 1.0
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_root.add_child(cc)
	_shop = PanelContainer.new()
	_shop.add_stylebox_override("panel", Kit.panel(Color(0.3, 0.27, 0.4), 0.98, 18.0))
	cc.add_child(_shop)
	var sv = VBoxContainer.new()
	sv.add_constant_override("separation", 12)
	_shop.add_child(sv)
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 12)
	sv.add_child(top)
	Kit.icon_rect(top, "luck", 48)
	var tv = VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	Kit.label(tv, "Evolution Lab", _f_xl)
	var sub = Kit.label(tv, "Spend food to steer evolution. Strains shift mutation odds; instincts nudge newborns.", _f_s)
	sub.modulate = Color(1, 1, 1, 0.7)
	var fp = PanelContainer.new()
	fp.add_stylebox_override("panel", Kit.flat(Color("#1a3a1a"), Kit.GREEN, 12, 3, 6.0, 4))
	top.add_child(fp)
	var fh = HBoxContainer.new()
	fh.add_constant_override("separation", 8)
	fp.add_child(fh)
	Kit.icon_rect(fh, "food", 34)
	_shop_title_food = KNum.new()
	_shop_title_food.setup(_f_l, "%d")
	fh.add_child(_shop_title_food)
	_shop_cards = HBoxContainer.new()
	_shop_cards.add_constant_override("separation", 14)
	sv.add_child(_shop_cards)
	var ov = HBoxContainer.new()
	ov.add_constant_override("separation", 10)
	sv.add_child(ov)
	var ol = Kit.label(ov, "Owned", _f_s)
	ol.modulate = Color(1, 1, 1, 0.6)
	_shop_owned = GridContainer.new()
	_shop_owned.columns = 14
	_shop_owned.add_constant_override("hseparation", 4)
	ov.add_child(_shop_owned)
	_shop_owned_note = Kit.label(ov, "nothing yet", _f_s)
	_shop_owned_note.modulate = Color(1, 1, 1, 0.5)
	var sb = HBoxContainer.new()
	sb.alignment = BoxContainer.ALIGN_CENTER
	sb.add_constant_override("separation", 16)
	sv.add_child(sb)
	_reroll_btn = _btn(sb, "Reroll", "luck")
	_reroll_btn.connect("pressed", self, "_on_reroll")
	_reroll_btn.rect_min_size = Vector2(190, 54)
	var cont = _btn(sb, "Continue", "arrow_r", Kit.GREEN)
	cont.rect_min_size = Vector2(190, 54)
	cont.connect("pressed", scene, "close_shop")
	_shop_root.visible = false


# ================================================================== build: collapse
func _build_collapse() -> void:
	_collapse_root = Control.new()
	_collapse_root.anchor_right = 1.0
	_collapse_root.anchor_bottom = 1.0
	_collapse_root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_collapse_root)
	var dim = ColorRect.new()
	dim.color = Color(0.1, 0.02, 0.03, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_collapse_root.add_child(dim)
	var cc = CenterContainer.new()
	cc.anchor_right = 1.0
	cc.anchor_bottom = 1.0
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_collapse_root.add_child(cc)
	var p = PanelContainer.new()
	p.add_stylebox_override("panel", Kit.panel(Color(0.42, 0.24, 0.26), 0.98, 22.0))
	cc.add_child(p)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGN_CENTER
	p.add_child(v)
	var ic = Kit.icon_rect(v, "skull", 72)
	ic.rect_min_size = Vector2(72, 72)
	Kit.label(v, "The colony has fallen", _f_xl).align = Label.ALIGN_CENTER
	_collapse_label = Kit.label(v, "", _f_m)
	_collapse_label.align = Label.ALIGN_CENTER
	_collapse_label.modulate = Color(1, 1, 1, 0.8)
	_collapse_stats = Kit.label(v, "", _f_s)
	_collapse_stats.align = Label.ALIGN_CENTER
	_collapse_stats.modulate = Color(1, 1, 1, 0.72)
	_collapse_best = Kit.label(v, "", _f_m, Kit.GOLD)
	_collapse_best.align = Label.ALIGN_CENTER
	_legacy_box = VBoxContainer.new()
	_legacy_box.add_constant_override("separation", 8)
	v.add_child(_legacy_box)
	var lt = Kit.label(_legacy_box, "Pass one trait down to your next queen", _f_s, Kit.GOLD)
	lt.align = Label.ALIGN_CENTER
	_legacy_row = VBoxContainer.new()
	_legacy_row.add_constant_override("separation", 6)
	_legacy_box.add_child(_legacy_row)
	_legacy_label = Kit.label(_legacy_box, "", _f_s)
	_legacy_label.align = Label.ALIGN_CENTER
	_legacy_label.modulate = Color(1, 1, 1, 0.8)
	_wild_label = Kit.label(v, "", _f_s, Color("#ff9d8a"))
	_wild_label.align = Label.ALIGN_CENTER
	_wild_label.autowrap = true
	_wild_label.rect_min_size = Vector2(900, 0)
	var ch = HBoxContainer.new()
	ch.alignment = BoxContainer.ALIGN_CENTER
	ch.add_constant_override("separation", 14)
	v.add_child(ch)
	var nq = _btn(ch, "New queen", "random", Kit.GOLD)
	nq.rect_min_size = Vector2(200, 56)
	nq.connect("pressed", scene, "restart")
	var mn = _btn(ch, "Menu", "exit")
	mn.rect_min_size = Vector2(140, 56)
	mn.connect("pressed", scene, "go_to_menu")
	_collapse_root.visible = false


# ================================================================== per-frame + refresh
func _process(delta: float) -> void:
	_t += delta
	var sim = scene.sim
	# damage vignette follows the queen's pain
	var want = 0.5 if (sim.queen_flash > 0.0 and not scene.shop_open and not sim.collapsed) else 0.0
	_vig_a = lerp(_vig_a, want, 1.0 - exp(-delta * 8.0))
	_vig.update()
	# pause chip pulses
	_pause_chip.visible = scene.speed == 0.0 and not scene.shop_open and not sim.collapsed
	# the active speed button shows the speed actually achieved when the sim cannot keep up
	var sidx = [0.0, 1.0, 2.0, 4.0, 10.0].find(scene.speed)
	if sidx >= 1 and _speed_btns.size() == 5:
		var short = scene.eff_speed < scene.speed * 0.85 and not scene.shop_open
		_speed_btns[sidx].text = ("~%.1fx" % scene.eff_speed) if short else SPEED_LABELS[sidx]
	if _pause_chip.visible:
		_pause_chip.modulate.a = (0.65 + 0.35 * sin(_t * 5.0)) * (1.0 - (_mm_a if mode == 0 else 0.0))
	# banner fade
	if sim.banner_t > 0.0 and sim.banner != "":
		if sim.banner != _banner_text:
			_show_banner(sim.banner)
		_banner.visible = true
		_banner.modulate.a = clamp(sim.banner_t * 1.5, 0.0, 1.0)
	else:
		_banner.visible = false
		_banner_text = ""
	_refresh_director()
	_refresh_squad()
	_edge_reveal(delta)
	if scene.watch_mode:
		_watch_t += delta
		_watch_chip.modulate.a = lerp(0.9, 0.28, smoothstep(5.0, 9.0, _watch_t))
	# toasts
	_sync_toasts(sim)
	# queen bar hurts
	if sim.queen_flash > 0.0:
		_queen_bar.pulse(Color(1, 0.3, 0.25))
	# collapse
	if sim.collapsed and not _collapse_shown:
		_collapse_shown = true
		_collapse_label.text = sim.collapse_reason if sim.collapse_reason != "" else "The colony has fallen."
		_show_run_summary(sim)
		_collapse_root.visible = true
		_collapse_root.modulate.a = 0.0
		var tw = Kit.tween(_collapse_root)
		tw.interpolate_property(_collapse_root, "modulate:a", 0.0, 1.0, 0.6, Tween.TRANS_SINE, Tween.EASE_OUT)
		tw.start()
	if _shop_root.visible:
		_shop_title_food.set_value(sim.food)

	_refresh -= delta
	if _refresh > 0.0:
		return
	_refresh = 0.2
	if scene.watch_mode:
		_refresh_watch_info(sim)
	_refresh_stats(sim)
	_refresh_lineages()
	_refresh_inspector()
	if _evo_holder.visible:
		_refresh_evolution()
	_graph.update()
	_task_bar.update()
	_mm.update()
	_strip.update()


# Closing the run: what the colony achieved, and whether it beat this queen's best.
func _show_run_summary(sim) -> void:
	var tr = sim.top_genomes(1)
	var plan = ""
	if not tr.empty():
		plan = "\nLast dominant body plan: " + tr[0]["genome"].describe()
	var winters = ("  ·  %d winter%s" % [sim.winters, "" if sim.winters == 1 else "s"]) if sim.winters > 0 else ""
	_collapse_stats.text = "Survived %s  ·  %d raid%s%s  ·  peak %d ants  ·  generation %d\nFarthest forager %d cells  ·  %d raiders slain  ·  %d food hauled%s" % [
		RunLog.clock(sim.time), sim.raid_n, "" if sim.raid_n == 1 else "s", winters, sim.peak_ants, sim.max_gen, sim.stat_far, sim.kills, int(sim.delivered_total), plan]
	var qid = Engine.get_meta("infdna_queen") if Engine.has_meta("infdna_queen") else "well_rounded"
	var rec = RunLog.record(str(qid), sim.time, sim.raid_n, sim.peak_ants)
	if rec["new"]:
		_collapse_best.text = "New best for this queen!"
	else:
		var b = rec["best"]
		_collapse_best.text = "Best with this queen: %s  ·  %d raids" % [RunLog.clock(float(b["time"])), int(b["raids"])]
	_offer_heirlooms(sim)
	_write_wild(sim)


# The colony's fall goes into the Wild (wild.gd) once: its champion strain escapes, and the line it met is ended or evolves on.
func _write_wild(sim) -> void:
	_wild_label.text = ""
	if sim.wild_saved:
		return
	sim.wild_saved = true
	_wild_label.text = "\n".join(Wild.finish_run(sim, str(sim.queen_def["name"])))


# The champion strain's best traits, one of which the next queen's founders can be born with.
func _offer_heirlooms(sim) -> void:
	for c in _legacy_row.get_children():
		c.queue_free()
	var from = "%s, %s" % [sim.queen_def["name"], RunLog.clock(sim.time)]
	var cands = Legacy.candidates(sim.champion, sim.founder_genome, from)
	var cur = Legacy.saved()
	var grp = ButtonGroup.new()
	for h in cands:
		var b = _btn(_legacy_row, h["label"], "", Kit.GOLD, 22)
		b.toggle_mode = true
		b.group = grp
		b.rect_min_size = Vector2(520, 48)
		b.pressed = false
		b.connect("pressed", self, "_pick_heirloom", [h])
	if cur.empty():
		_legacy_label.text = "The next queen's founders will carry whatever you choose."
	else:
		_legacy_label.text = "Current heirloom: %s (keep it by choosing nothing)." % str(cur.get("label", "")).to_lower()


func _pick_heirloom(h: Dictionary) -> void:
	Legacy.save(h)
	_legacy_label.text = "Chosen: %s. The next queen's founders will be born with it." % str(h["label"]).to_lower()


func _refresh_stats(sim) -> void:
	var tc = sim.task_counts()
	var av = sim.average_traits()
	_name.text = sim.queen_def["name"]
	_sub.text = "Day %d   ·   %s   ·   Generation %d   ·   %s" % [sim.day, Sim.Seasons.NAMES[scene.day.season], sim.max_gen, scene.day.label().capitalize()]
	_food_bar.set_values(sim.food, sim.food_cap)
	var note := ""
	if sim.rot_rate > 0.05:
		note += "rotting -%.1f/s   " % sim.rot_rate
	if sim.farm_rate > 0.05:
		note += "farms +%.1f/s" % sim.farm_rate
	if not sim.farm_mold.empty():
		note += "   mould!"
	_food_note.text = note
	_food_note.add_color_override("font_color", Color("#ff8a7a") if sim.rot_rate > 0.05 else Kit.GREEN)
	_queen_bar.set_values(sim.queen_hp, sim.queen_max)
	_chip_nums["ants"].set_value(sim.ants.size())
	_chip_nums["eggs"].set_value(sim.eggs.size())
	_chip_nums["kills"].set_value(sim.kills)
	_chip_nums["lost"].set_value(sim.died_combat)
	var cc = sim.caste_counts()
	for i in 3:
		_caste_nums[i].set_value(cc[i])
	var parts := []
	for i in [1, 2, 0, 4]:
		parts.append("%s %d" % [TASK_LABELS[i], tc[i]])
	_task_txt.text = "  ·  ".join(parts)
	_stat_labels["speed"].text = "%.1f" % av["speed"]
	_stat_labels["carry"].text = "%.1f" % av["carry"]
	_stat_labels["attack"].text = "%.1f" % _avg(sim, "attack")
	_stat_labels["hp"].text = "%d" % _avg(sim, "hp")

	# raid card
	var hostile = sim.hostile_count() + sim.raid_queue.size()
	if hostile > 0:
		_raid_total = int(max(_raid_total, hostile))
		_raid_icon.texture = Kit.icon("boss" if sim.raid_n % sim.BOSS_EVERY == 0 else "elite")
		_raid_title.text = "RAID %d  -  %d raiders" % [sim.raid_n, hostile]
		_raid_bar.color = Kit.RED
		_raid_bar.set_values(hostile, _raid_total)
		var b = sim.burrowers_active()
		_raid_note.text = ("%d BORING toward the queen!" % b) if b > 0 else sim.fate.counter_note()
	else:
		_raid_total = 1
		_raid_icon.texture = Kit.icon("horde")
		var interval = 180.0 if sim.raid_n == 0 else max(75.0, 125.0 - sim.raid_n * 4.0)
		_raid_title.text = "Next raid in %ds" % int(max(0.0, sim.raid_timer))
		_raid_bar.color = Kit.GOLD
		_raid_bar.set_values(clamp(1.0 - sim.raid_timer / interval, 0.0, 1.0), 1.0)
		_raid_note.text = "Raids so far: %d" % sim.raid_n if sim.raid_n > 0 else ""


func _avg(sim, key: String) -> float:
	if sim.ants.empty():
		return 0.0
	var t := 0.0
	for a in sim.ants:
		t += a.ph[key]
	return t / sim.ants.size()


func _refresh_lineages() -> void:
	var sim = scene.sim
	var list = sim.top_genomes(3)
	var sig := ""
	for e in list:
		sig += "%d," % e["genome"].uid
	if sig != _lineage_sig:
		_lineage_sig = sig
		for c in _lineage_box.get_children():
			c.queue_free()
		var i = 0
		for e in list:
			var row = _lineage_row(e, i)
			_lineage_box.add_child(row)
			Kit.pop_in(row, 0.06 * i, 0.9, 0.3)
			i += 1
	# live update of counts + textures without rebuilding
	var k = 0
	for row in _lineage_box.get_children():
		if k < list.size() and row.has_meta("cnt"):
			var e = list[k]
			row.get_meta("cnt").text = "x%d" % e["count"]
			row.get_meta("tex").texture = scene.baker.get_texture(e["genome"])
		k += 1


func _lineage_row(e, i: int) -> Control:
	var sim = scene.sim
	var g = e["genome"]
	var caste = sim.genome_caste(g.uid)
	var ci = sim.CASTES.find(caste)
	var col = Kit.CASTE_COLORS[ci if ci >= 0 else 0]
	var pc = PanelContainer.new()
	pc.add_stylebox_override("panel", Kit.flat(Kit.BG, col.darkened(0.2), 10, 3, 4.0, 3))
	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	pc.add_child(h)
	var tr = TextureRect.new()
	tr.rect_min_size = Vector2(110, 84)
	tr.expand = true
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = scene.baker.get_texture(g)
	h.add_child(tr)
	var v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 8)
	v.add_child(top)
	Kit.icon_rect(top, Kit.CASTE_KEYS[ci if ci >= 0 else 0], 24)
	var cnt = Kit.label(top, "x%d" % e["count"], _f_m, col.lightened(0.3))
	Kit.label(top, caste, _f_s).modulate = Color(1, 1, 1, 0.7)
	var d = Kit.label(v, g.describe(), _f_s)
	d.autowrap = true
	d.rect_min_size = Vector2(270, 0)
	d.modulate = Color(1, 1, 1, 0.85)
	pc.set_meta("cnt", cnt)
	pc.set_meta("tex", tr)
	return pc


func _refresh_inspector() -> void:
	var a = scene.selected
	var sim = scene.sim
	if scene.watch_mode:
		_inspect.visible = false
		_insp_prev = null
		return
	if a == null or not sim.ants.has(a):
		_inspect.visible = false
		scene.selected = null
		_insp_prev = null
		return
	if a != _insp_prev:
		_insp_prev = a
		var col = Kit.CASTE_COLORS[a.caste]
		_inspect.add_stylebox_override("panel", Kit.panel(Color(0.26 + col.r * 0.25, 0.24 + col.g * 0.2, 0.32 + col.b * 0.1), 0.96, 8.0))
		_inspect.visible = true
		Kit.pop_in(_inspect, 0.0, 0.9, 0.28)
	_inspect.visible = true
	var ph = a.ph
	var tr = a.genome.traits
	_insp_tex.texture = scene.baker.get_texture(a.genome)
	_insp_task.text = sim.TASK_NAMES[a.task]
	_insp_caste.text = "%s   ·   Gen %d" % [sim.CASTES[a.caste], a.gen]
	_insp_caste.add_color_override("font_color", Kit.CASTE_COLORS[a.caste].lightened(0.35))
	_insp_hp.color = Kit.GREEN if a.hp > ph["hp"] * 0.5 else Kit.RED
	_insp_hp.set_values(a.hp, ph["hp"], "%d / %d HP" % [int(a.hp), int(ph["hp"])])
	_insp_age.set_values(a.age, a.life, "Age %d / %ds" % [int(a.age), int(a.life)])
	_insp_stats["speed"].text = "%.1f" % ph["speed"]
	_insp_stats["carry"].text = "%.1f" % ph["carry"]
	_insp_stats["dig"].text = "%.1f" % ph["dig"]
	_insp_stats["sense"].text = "%d" % ph["sense"]
	_insp_stats["attack"].text = "%.1f" % ph["attack"]
	_insp_stats["armor"].text = "%d%%" % int(ph["armor_red"] * 100)
	_insp_stats["thorns"].text = "%.1f" % ph["thorns"]
	_insp_stats["upkeep"].text = "%.3f" % ph["upkeep"]
	var ab = _ability_text(ph)
	_insp_line.text = "%s%s\nDelivered %.0f · Dug %d · Fitness %.1f\nGenes  forage %.2f · dig %.2f · defend %.2f · down %.2f · explore %.2f" % [
		a.genome.describe(), ("\nAbilities  " + ab) if ab != "" else "", a.delivered, a.dug, a.fitness,
		tr["forage_t"], tr["dig_t"], tr.get("defend_t", 0.6), tr["dig_down"], tr["explore"]]


# Live organ abilities (v0.21) in one short line for the inspector.
func _ability_text(ph: Dictionary) -> String:
	var parts := []
	if ph.get("rally", 0.0) > 0.0:
		parts.append("rally +%d%%" % int(ph["rally"] * 100))
	if ph.get("pulse", 0.0) > 0.0:
		parts.append("%sshockwave %.0f" % ["thunder " if ph.get("thunder", false) else "", ph["pulse"]])
	if ph.get("arc", 0.0) > 0.0:
		parts.append("chain arc x%d" % ph["arc_n"])
	if ph.get("snipe", 0.0) > 0.0:
		parts.append("tongue shot %.0f%s" % [ph["snipe"], " +stun" if ph.get("snipe_stun", 0.0) > 0.0 else ""])
	if ph.get("snare_r", 0.0) > 0.0:
		parts.append("bolas snare")
	if ph.get("web", 0.0) > 0.0:
		parts.append("web slow")
	if ph.get("reach2", 1.0) > 1.0:
		parts.append("long reach")
	if ph.get("curl", false):
		parts.append("curl%s" % (" + heal" if ph.get("curl_heal", 0.0) > 0.0 else ""))
	if ph.get("regen", 0.0) > 0.0:
		parts.append("regen %.1f/s" % ph["regen"])
	if ph.get("split", 0.0) > 0.0:
		parts.append("split %d%%" % int(ph["split"] * 100))
	if ph.get("sonarweb", false):
		parts.append("sonar web")
	return PoolStringArray(parts).join(" · ")


# ================================================================== banner / toasts / vignette
func _show_banner(txt: String) -> void:
	_banner_text = txt
	_banner_label.text = txt
	var danger = txt.find("QUEEN") >= 0 or txt.find("BORING") >= 0 or txt.begins_with("Raid ")
	var good = txt.find("repelled") >= 0
	var tint = Color(0.46, 0.2, 0.2) if danger else (Color(0.2, 0.4, 0.24) if good else Color(0.42, 0.34, 0.16))
	_banner.add_stylebox_override("panel", Kit.panel(tint, 0.97, 14.0))
	_banner_label.add_color_override("font_color", Color("#ffd166") if not good else Color("#a8ec74"))
	_banner.rect_pivot_offset = _banner.rect_size * 0.5
	_banner.rect_scale = Vector2.ONE * 1.5
	var tw = Kit.tween(_banner)
	tw.interpolate_property(_banner, "rect_scale", Vector2.ONE * 1.5, Vector2.ONE, 0.35, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.start()
	if danger:
		Kit.shake(_banner, 10.0, 0.35)


func _sync_toasts(sim) -> void:
	var live := {}
	for t in sim.toasts:
		live[t["text"]] = t
		if not _toast_nodes.has(t["text"]):
			var pc = PanelContainer.new()
			pc.add_stylebox_override("panel", Kit.flat(Color("#1d2f1d"), Kit.GREEN, 12, 3, 6.0, 5))
			var h = HBoxContainer.new()
			h.add_constant_override("separation", 10)
			pc.add_child(h)
			Kit.icon_rect(h, "info", 30)
			var l = Kit.label(h, t["text"], _f_s, Color("#c8f5a8"))
			l.autowrap = false
			pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_toasts.add_child(pc)
			_toast_nodes[t["text"]] = pc
			Kit.pop_in(pc, 0.0, 0.7, 0.35)
		var node = _toast_nodes[t["text"]]
		if is_instance_valid(node):
			node.self_modulate.a = clamp(t["t"], 0.0, 1.0)
			for c in node.get_children():
				if c is CanvasItem:   # pop_in parks a Tween under the panel
					c.modulate.a = clamp(t["t"], 0.0, 1.0)
	for k in _toast_nodes.keys():
		if not live.has(k):
			if is_instance_valid(_toast_nodes[k]):
				_toast_nodes[k].queue_free()
			_toast_nodes.erase(k)


func _draw_vignette() -> void:
	if _vig_a < 0.01:
		return
	var s = _vig.rect_size
	var edge = Color(0.9, 0.1, 0.1, _vig_a)
	var clear = Color(0.9, 0.1, 0.1, 0.0)
	var d = min(s.x, s.y) * 0.28
	_vig.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, d), Vector2(0, d)]), PoolColorArray([edge, edge, clear, clear]))
	_vig.draw_polygon(PoolVector2Array([Vector2(0, s.y - d), Vector2(s.x, s.y - d), Vector2(s.x, s.y), Vector2(0, s.y)]), PoolColorArray([clear, clear, edge, edge]))
	_vig.draw_polygon(PoolVector2Array([Vector2(0, 0), Vector2(d, 0), Vector2(d, s.y), Vector2(0, s.y)]), PoolColorArray([edge, clear, clear, edge]))
	_vig.draw_polygon(PoolVector2Array([Vector2(s.x - d, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - d, s.y)]), PoolColorArray([clear, edge, edge, clear]))


# ================================================================== custom draws
func _draw_tasks() -> void:
	var tc = scene.sim.task_counts()
	var total := 0
	for c in tc:
		total += c
	var r = _task_bar.rect_size
	_task_bar.draw_rect(Rect2(Vector2(-2, -2), r + Vector2(4, 4)), Kit.INK)
	_task_bar.draw_rect(Rect2(Vector2.ZERO, r), Color(0.15, 0.14, 0.18))
	if total == 0:
		return
	var x := 0.0
	for i in [1, 2, 0, 3, 4]:
		var w = r.x * float(tc[i]) / total
		if w > 0.5:
			_task_bar.draw_rect(Rect2(x, 0, w, r.y), TASK_COLORS[i])
			_task_bar.draw_rect(Rect2(x, 0, w, r.y * 0.3), Color(1, 1, 1, 0.16))
		x += w


func _draw_graph() -> void:
	var h = scene.sim.history
	var r = _graph.rect_size
	_graph.draw_rect(Rect2(Vector2.ZERO, r), Color(0, 0, 0, 0.3))
	for i in range(1, 4):
		_graph.draw_line(Vector2(0, r.y * i / 4.0), Vector2(r.x, r.y * i / 4.0), Color(1, 1, 1, 0.06), 1.0)
	_graph.draw_string(_f_s, Vector2(8, 20), "ants", Color.white)
	_graph.draw_string(_f_s, Vector2(62, 20), "food", Kit.GREEN)
	if h.size() < 2:
		return
	var max_pop := 10.0
	var max_food := 20.0
	for e in h:
		max_pop = max(max_pop, e["pop"])
		max_food = max(max_food, e["food"])
	var pop_pts := PoolVector2Array()
	var food_pts := PoolVector2Array()
	for i in h.size():
		var x = r.x * i / 119.0
		pop_pts.append(Vector2(x, r.y - 4 - (r.y - 8) * h[i]["pop"] / max_pop))
		food_pts.append(Vector2(x, r.y - 4 - (r.y - 8) * h[i]["food"] / max_food))
	_graph.draw_polyline(food_pts, Kit.GREEN, 2.5, true)
	_graph.draw_polyline(pop_pts, Color.white, 3.5, true)


# ================================================================== M4: evolution panel
func _build_evolution() -> void:
	# modal: a dim backdrop that eats clicks, raised above every other HUD panel on open
	_evo_holder = Control.new()
	_evo_holder.anchor_right = 1.0
	_evo_holder.anchor_bottom = 1.0
	_evo_holder.visible = false
	root.add_child(_evo_holder)
	var dim = ColorRect.new()
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.color = Color(0.03, 0.02, 0.05, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.connect("gui_input", self, "_on_evo_dim_input")
	_evo_holder.add_child(dim)
	_evo_root = PanelContainer.new()
	_evo_root.add_stylebox_override("panel", Kit.panel(Color(0.26, 0.3, 0.36), 0.97, 12.0))
	_evo_root.anchor_left = 0.5
	_evo_root.anchor_right = 0.5
	_evo_root.anchor_top = 0.5
	_evo_root.anchor_bottom = 0.5
	_evo_root.margin_left = -560
	_evo_root.margin_right = 560
	_evo_root.margin_top = -330
	_evo_root.margin_bottom = 280
	_evo_holder.add_child(_evo_root)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 10)
	_evo_root.add_child(v)
	var top = HBoxContainer.new()
	v.add_child(top)
	Kit.icon_rect(top, "power", 34)
	_evo_title = Kit.label(top, " Evolution", _f_l)
	_evo_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn(top, "Close", "exit").connect("pressed", self, "toggle_evolution")
	var sub = Kit.label(v, "Share of the colony carrying each trait, over the run", _f_s)
	sub.modulate = Color(1, 1, 1, 0.7)
	_evo_chart = Control.new()
	_evo_chart.rect_min_size = Vector2(1090, 250)
	_evo_chart.connect("draw", self, "_draw_evo_chart")
	v.add_child(_evo_chart)
	_evo_strip_title = Kit.label(v, "", _f_m)
	var sc = ScrollContainer.new()
	sc.rect_min_size = Vector2(1090, 190)
	sc.scroll_vertical_enabled = false
	v.add_child(sc)
	_evo_strip = HBoxContainer.new()
	_evo_strip.add_constant_override("separation", 6)
	sc.add_child(_evo_strip)


func toggle_evolution() -> void:
	_evo_holder.visible = not _evo_holder.visible
	if _evo_holder.visible:
		root.move_child(_evo_holder, root.get_child_count() - 1)
		_evo_sig = ""
		_refresh_evolution()
		Kit.pop_in(_evo_root, 0.0, 0.94, 0.25)


func is_evolution_open() -> bool:
	return _evo_holder.visible


func _on_evo_dim_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		toggle_evolution()


# The line to trace: the selected ant's plan, else the most common plan.
func _evo_subject():
	var a = scene.selected
	if a != null and scene.sim.ants.has(a):
		return [a.genome, "Selected ant's line"]
	var list = scene.sim.top_genomes(1)
	if list.empty():
		return [null, ""]
	return [list[0]["genome"], "Most common body plan's line (x%d)" % list[0]["count"]]


func _refresh_evolution() -> void:
	var sim = scene.sim
	var plans = sim.evo_log.back()["plans"] if not sim.evo_log.empty() else 0
	_evo_title.text = " Evolution   ·   generation %d   ·   %d body plans alive" % [sim.max_gen, plans]
	_evo_chart.update()
	var subj = _evo_subject()
	var g = subj[0]
	var sig = "%d" % (g.uid if g != null else -1)
	if sig == _evo_sig:
		return
	_evo_sig = sig
	for c in _evo_strip.get_children():
		c.queue_free()
	if g == null:
		_evo_strip_title.text = ""
		return
	var chain = g.ancestry()
	if chain.empty() or chain.back() != g:
		chain.append(g)
	var steps = chain.size() - 1
	_evo_strip_title.text = "%s: %d step%s from the founder" % [subj[1], steps, "" if steps == 1 else "s"]
	var first = max(0, chain.size() - 9)
	if first > 0:
		var more = Kit.label(_evo_strip, "+%d older ..." % first, _f_s)
		more.valign = Label.VALIGN_CENTER
		more.modulate = Color(1, 1, 1, 0.6)
	for i in range(first, chain.size()):
		var n = chain[i]
		if i > first:
			var arr = Kit.label(_evo_strip, ">", _f_l)
			arr.valign = Label.VALIGN_CENTER
			arr.modulate = Color(1, 1, 1, 0.5)
		_evo_strip.add_child(_ancestor_card(n, i == 0, i == chain.size() - 1))


func _ancestor_card(g, is_root: bool, is_now: bool) -> Control:
	var pc = PanelContainer.new()
	var edge = Kit.GOLD if is_now else (Kit.BLUE if is_root else Color(1, 1, 1, 0.25))
	pc.add_stylebox_override("panel", Kit.flat(Kit.BG, edge, 8, 2, 5.0, 2))
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 2)
	pc.add_child(v)
	var tr = TextureRect.new()
	tr.rect_min_size = Vector2(104, 82)
	tr.expand = true
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture = scene.baker.get_texture(g)
	if tr.texture == null:
		# baked next frame; poll a few times
		_retry_tex(tr, g, 6)
	v.add_child(tr)
	var head = "Founder" if is_root else ("Gen %d" % g.born_gen)
	if is_now:
		head = ("Now · since gen %d" % g.born_gen) if not is_root else "Founder (now)"
	var l1 = Kit.label(v, head, _f_s, edge.lightened(0.2) if not is_now else Kit.GOLD)
	l1.align = Label.ALIGN_CENTER
	var txt = g.note if g.note != "" else ("the queen's first brood" if is_root else "same body, retuned genes")
	var l2 = Kit.label(v, txt, _f_s)
	l2.autowrap = true
	l2.rect_min_size = Vector2(124, 0)
	l2.align = Label.ALIGN_CENTER
	l2.modulate = Color(1, 1, 1, 0.85)
	return pc


func _retry_tex(tr: TextureRect, g, tries: int) -> void:
	for i in tries:
		yield(get_tree().create_timer(0.15), "timeout")
		if not is_instance_valid(tr):
			return
		var t = scene.baker.get_texture(g)
		if t != null:
			tr.texture = t
			return


func _draw_evo_chart() -> void:
	var log_ = scene.sim.evo_log
	var r = _evo_chart.rect_size
	var lw = 230.0      # legend column
	var cw = r.x - lw
	_evo_chart.draw_rect(Rect2(Vector2.ZERO, Vector2(cw, r.y)), Color(0, 0, 0, 0.3))
	for i in range(1, 4):
		var y = r.y * i / 4.0
		_evo_chart.draw_line(Vector2(0, y), Vector2(cw, y), Color(1, 1, 1, 0.07), 1.0)
		_evo_chart.draw_string(_f_s, Vector2(4, y - 3), "%d%%" % (100 - 25 * i), Color(1, 1, 1, 0.35))
	if log_.size() < 2:
		_evo_chart.draw_string(_f_m, Vector2(20, r.y * 0.5), "Sampling... (every 15 s)", Color(1, 1, 1, 0.6))
		return
	var t0 = log_[0]["t"]
	var t1 = max(t0 + 1.0, log_.back()["t"])
	var legend := []
	for k in scene.sim.EVO_TRAITS:
		var peak := 0.0
		for e in log_:
			peak = max(peak, e["share"][k])
		if peak < 0.05:
			continue
		var pts := PoolVector2Array()
		for e in log_:
			pts.append(Vector2(cw * (e["t"] - t0) / (t1 - t0), r.y - 3 - (r.y - 6) * e["share"][k]))
		var col = TRAIT_COLORS.get(k, Color.white)
		_evo_chart.draw_polyline(pts, col, 3.0, true)
		legend.append([k, log_.back()["share"][k], col])
	# top-plan share (dominance) as a dashed white guide
	var prev = null
	for i in log_.size():
		var p = Vector2(cw * (log_[i]["t"] - t0) / (t1 - t0), r.y - 3 - (r.y - 6) * log_[i]["top"])
		if prev != null and i % 2 == 0:
			_evo_chart.draw_line(prev, p, Color(1, 1, 1, 0.55), 2.0)
		prev = p
	legend.sort_custom(self, "_by_share")
	var y = 22.0
	for e in legend:
		_evo_chart.draw_rect(Rect2(cw + 12, y - 12, 14, 14), e[2])
		_evo_chart.draw_string(_f_s, Vector2(cw + 32, y), "%s %d%%" % [scene.sim.TRAIT_LABELS[e[0]], int(e[1] * 100)], Color.white)
		y += 24.0
		if y > r.y - 40:
			break
	_evo_chart.draw_string(_f_s, Vector2(cw + 12, y + 4), "- - top plan %d%%" % int(log_.back()["top"] * 100), Color(1, 1, 1, 0.7))
	_evo_chart.draw_string(_f_s, Vector2(8, r.y - 8), "%d:%02d" % [int(t0) / 60, int(t0) % 60], Color(1, 1, 1, 0.45))
	_evo_chart.draw_string(_f_s, Vector2(cw - 52, r.y - 8), "%d:%02d" % [int(t1) / 60, int(t1) % 60], Color(1, 1, 1, 0.45))


func _by_share(a, b) -> bool:
	return a[1] > b[1]


# ================================================================== callbacks
func _on_focus(i: int) -> void:
	scene.sim.focus = i


func _on_brood(i: int) -> void:
	scene.sim.brood = i


func _on_speed(i: int) -> void:
	scene.set_speed([0.0, 1.0, 2.0, 4.0, 10.0][i])


# Keep the buttons in step with the 1-4 / Space hotkeys.
func sync_speed(s: float) -> void:
	var idx = [0.0, 1.0, 2.0, 4.0, 10.0].find(s)
	if idx < 0:
		return
	for i in _speed_btns.size():
		_speed_btns[i].pressed = i == idx


func _on_quality() -> void:
	scene.perf.cycle_mode()


func sync_quality() -> void:
	if _quality_btn != null:
		_quality_btn.text = scene.perf.label()


# Watch mode: only the world, the banners and a one-line status stay. The rest is hidden and restored on exit.
func set_watch(on: bool) -> void:
	if on:
		_watch_hidden = []
		for n in [_left_col, _lineage_panel, _bar_panel, _mm_panel, _hint, _layers_panel, _inspect, _dir_panel, _dir_hint, _squad_panel, _strip, _tag_panel, _notch_top, _notch_bot]:
			if n != null:
				_watch_hidden.append([n, n.visible])
				n.visible = false
		_watch_t = 0.0
		_watch_chip.modulate.a = 0.9
		_refresh_watch_info(scene.sim)
	else:
		for it in _watch_hidden:
			it[0].visible = it[1]
		_watch_hidden = []
		_insp_prev = null
	_watch_chip.visible = on
	_watch_info.visible = on


func _refresh_watch_info(sim) -> void:
	var gen := 0
	for a in sim.ants:
		gen = int(max(gen, a.gen))
	_watch_info.text = "%d ants   ·   gen %d   ·   %s %s   ·   %s" % [sim.ants.size(), gen, Sim.Seasons.NAMES[scene.day.season].to_lower(), scene.day.label(),
		("raid %d" % sim.raid_n) if sim.raid_n > 0 else "calm"]


func toggle_compact() -> void:
	cycle_mode()


# Standard (compact) or full panels. View mode is the standard set of panels with the status line instead (see set_mode).
func set_compact(on: bool) -> void:
	compact = on
	for n in _extra_nodes:
		n.visible = not on
	_more_box.visible = not on
	if not scene.watch_mode:
		_lineage_panel.visible = not on
		_dir_panel.visible = not on
		_layers_panel.visible = not on


func _on_layer_toggled(on: bool, key: String) -> void:
	scene.set_layer(key, on)


# Keep the buttons in step with the P / C / F / T / H hotkeys.
func sync_layer(key: String, on: bool) -> void:
	if _layer_btns.has(key):
		_layer_btns[key].pressed = on
	if key == "tasks":
		_task_legend.visible = on


# ================================================================== builders
func _btn(parent: Node, text: String, key: String, col: Color = Color("#f2c14e"), size: int = 24) -> Button:
	var b = KBtn.new()
	b.setup(text, key, col, size)
	parent.add_child(b)
	return b


func _group(parent: Node, title: String, names: Array, default_i: int, cb: String, tips: Array) -> Array:
	var l = Kit.label(parent, title, _f_s)
	l.valign = Label.VALIGN_CENTER
	l.modulate = Color(1, 1, 1, 0.7)
	var bg = ButtonGroup.new()
	var out := []
	for i in names.size():
		var b = _btn(parent, names[i][0], names[i][1])
		b.toggle_mode = true
		b.group = bg
		b.pressed = i == default_i
		if i < tips.size():
			b.hint_tooltip = tips[i]
		b.connect("pressed", self, cb, [i])
		out.append(b)
	return out


func _sep(parent: Node) -> void:
	var s = VSeparator.new()
	s.rect_min_size = Vector2(10, 0)
	parent.add_child(s)


# ================================================================== Evolution Lab
func show_shop(on: bool) -> void:
	if on:
		_shop_root.visible = true
		_shop_dim.color.a = 0.0
		var tw = Kit.tween(_shop_dim)
		tw.interpolate_property(_shop_dim, "color:a", 0.0, 0.62, 0.3, Tween.TRANS_SINE, Tween.EASE_OUT)
		tw.start()
		refresh_shop(true)
		_shop_title_food.set_value(scene.sim.food)
		Kit.pop_in(_shop, 0.0, 0.92, 0.35)
	else:
		_shop_root.visible = false


func refresh_shop(animate: bool = false, sold_slot: int = -1) -> void:
	var sim = scene.sim
	for c in _shop_cards.get_children():
		c.queue_free()
	var cw = 262.0 if sim.offers.size() <= 4 else 232.0
	for i in sim.offers.size():
		var card = _make_card(i, sim.offers[i], cw)
		_shop_cards.add_child(card)
		if animate:
			Kit.pop_in(card, 0.08 * i, 0.82, 0.38)
		elif i == sold_slot:
			card.modulate = Color(2.4, 2.4, 2.4)
			var tw = Kit.tween(card)
			tw.interpolate_property(card, "modulate", Color(2.4, 2.4, 2.4), Color.white, 0.4, Tween.TRANS_SINE, Tween.EASE_OUT)
			tw.start()
	_reroll_btn.text = "Reroll  (%s)" % ("FREE" if sim.reroll_cost() == 0 else str(sim.reroll_cost()))
	_reroll_btn.disabled = sim.food < sim.reroll_cost()
	for c in _shop_owned.get_children():
		c.queue_free()
	var n := 0
	for id in sim.owned.keys():
		n += 1
		var it = ShopItems.ITEMS[id]
		var box = PanelContainer.new()
		box.add_stylebox_override("panel", Kit.flat(Kit.BG, ShopItems.TIER_COLORS[it["tier"]].darkened(0.2), 7, 2, 2.0, 0))
		box.hint_tooltip = "%s x%d\n%s" % [it["name"], sim.owned[id], sim.fate.item_desc(sim, id)]
		_shop_owned.add_child(box)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 1)
		box.add_child(h)
		var ip = ShopItems.icon_path(id)
		if ip != "" and ResourceLoader.exists(ip):
			var tr = TextureRect.new()
			tr.texture = load(ip)
			tr.rect_min_size = Vector2(34, 34)
			tr.expand = true
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(tr)
		if sim.owned[id] > 1:
			var xl = Kit.label(h, "x%d" % sim.owned[id], _f_s)
			xl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_owned_note.visible = n == 0


func _make_card(slot: int, id: String, cw: float) -> Control:
	var sim = scene.sim
	var card = PanelContainer.new()
	card.rect_min_size = Vector2(cw, 300)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	if id == "":
		card.add_stylebox_override("panel", Kit.flat(Color("#17141c"), Color(1, 1, 1, 0.1), 14, 3, 12.0, 0))
		var sold = Kit.label(card, "SOLD", _f_l)
		sold.align = Label.ALIGN_CENTER
		sold.valign = Label.VALIGN_CENTER
		sold.modulate = Color(1, 1, 1, 0.3)
		return card
	var it = ShopItems.ITEMS[id]
	var col: Color = ShopItems.TIER_COLORS[it["tier"]]
	var st = Kit.flat(Kit.BG, col, 14, 4, 12.0, 8)
	card.add_stylebox_override("panel", st)
	var v = VBoxContainer.new()
	v.add_constant_override("separation", 8)
	card.add_child(v)
	var top = HBoxContainer.new()
	top.add_constant_override("separation", 10)
	v.add_child(top)
	var icon_bg = PanelContainer.new()
	icon_bg.add_stylebox_override("panel", Kit.flat(col.darkened(0.6), col, 12, 3, 4.0, 3))
	top.add_child(icon_bg)
	var ip = ShopItems.icon_path(id)
	var icon = TextureRect.new()
	icon.rect_min_size = Vector2(68, 68)
	icon.expand = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if ip != "" and ResourceLoader.exists(ip):
		icon.texture = load(ip)
	icon_bg.add_child(icon)
	var tv = VBoxContainer.new()
	tv.alignment = BoxContainer.ALIGN_CENTER
	top.add_child(tv)
	var tier = Kit.label(tv, ShopItems.TIER_NAMES[it["tier"]].to_upper(), _f_s, col.lightened(0.15))
	var have = sim.owned.get(id, 0)
	if have > 0:
		Kit.label(tv, "Owned x%d" % have, _f_s).modulate = Color(1, 1, 1, 0.55)
	var nm = Kit.label(v, it["name"], _f_m)
	nm.autowrap = true
	nm.rect_min_size = Vector2(cw - 34.0, 0)
	var d = Kit.label(v, sim.fate.item_desc(sim, id), _f_s)
	d.autowrap = true
	d.rect_min_size = Vector2(cw - 34.0, 0)
	d.modulate = Color(1, 1, 1, 0.82)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var price = sim.price(id)
	var b = _btn(v, "Buy  %d" % price, "food", Kit.GREEN)
	b.disabled = sim.food < price
	b.connect("pressed", self, "_on_buy", [slot])
	# hover: card lifts and its rim brightens
	card.connect("mouse_entered", self, "_card_hover", [card, st, col, true, it["tier"]])
	card.connect("mouse_exited", self, "_card_hover", [card, st, col, false, it["tier"]])
	if it["tier"] >= 4:    # legendary: rim pulses
		var tw = Tween.new()
		card.add_child(tw)
		tw.repeat = true
		tw.interpolate_property(st, "border_color", col, col.lightened(0.5), 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
		tw.interpolate_property(st, "border_color", col.lightened(0.5), col, 0.8, Tween.TRANS_SINE, Tween.EASE_IN_OUT, 0.8)
		tw.start()
	return card


func _card_hover(card: Control, st: StyleBoxFlat, col: Color, on: bool, tier: int) -> void:
	if not is_instance_valid(card):
		return
	card.rect_pivot_offset = card.rect_size * 0.5
	var tw = Kit.tween(card)
	tw.interpolate_property(card, "rect_scale", card.rect_scale, Vector2.ONE * (1.04 if on else 1.0), 0.16, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.start()
	if tier < 4:
		st.border_color = col.lightened(0.35) if on else col


func _on_buy(slot: int) -> void:
	var id = scene.sim.offers[slot] if slot < scene.sim.offers.size() else ""
	if scene.sim.buy(slot):
		scene.sfx.play("legendary" if id != "" and ShopItems.ITEMS[id]["tier"] == 4 else "buy")
		refresh_shop(false, slot)
	else:
		scene.sfx.play("cant_buy")
		Kit.shake(_shop, 8.0, 0.3)


func _on_reroll() -> void:
	if scene.sim.reroll():
		scene.sfx.play("reroll")
		refresh_shop(true)
		var tw = Kit.tween(_reroll_btn)
		tw.interpolate_property(_reroll_btn, "rect_rotation", -6.0, 0.0, 0.3, Tween.TRANS_BACK, Tween.EASE_OUT)
		tw.start()
	else:
		scene.sfx.play("cant_buy")
		Kit.shake(_reroll_btn, 6.0, 0.25)
