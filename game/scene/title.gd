extends Control
# The title screen, where every run starts: pick the queen who founds the colony (core/queens.gd: her name, her one rule and her
# perks), see your best run with her, switch the heirloom (core/legacy.gd) and the Wild (core/wild.gd) on or off, then Start.
# Start sets scene/run.gd (queen, heirloom, kin, the Lab items) and opens the colony. The sky with its hills is the backdrop.
# There are no queen portraits yet: each queen is her name in the owner's frame, with the owner's queen icon on the detail card.

const Kit = preload("res://scene/menu_kit.gd")
const Run = preload("res://scene/run.gd")
const Queens = preload("res://core/queens.gd")
const RunLog = preload("res://core/run_log.gd")
const Legacy = preload("res://core/legacy.gd")
const Wild = preload("res://core/wild.gd")
const ShopItems = preload("res://core/shop_items.gd")
const BugReport = preload("res://core/bug_report.gd")

const COLS = 3
const DETAIL_W = 500.0
# mods key -> [label, unit, good when positive]   (the old mod's queen_select.gd, without the borrowed icons)
const MOD_INFO = {
	"hp": ["HP", "%", true], "attack": ["attack", "%", true], "speed": ["speed", "%", true],
	"carry": ["carry", "%", true], "dig": ["digging", "%", true], "life": ["lifespan", "%", true],
	"upkeep": ["food upkeep", "%", false], "thorns": ["thorns", "%", true],
	"armor": ["damage ignored", "%", true], "sense": ["sense", "flat", true], "regen": ["HP regen per second", "flat", true],
	"defend_attack": ["defender attack", "%", true], "kill_food": ["food from kills", "%", true],
	"pile_rich": ["richer food piles", "%", true], "pile_near": ["food appears closer", "flag", true],
	"interest": ["interest per repelled raid", "%", true], "price_disc": ["Lab prices", "%", false],
	"raid_size": ["raid size", "%", false], "tunnel_dmg": ["trap damage in tunnels", "flat", true],
	"siege_dmg": ["trap damage at the entrance", "flat", true], "queen_regen": ["queen regen", "%", true],
	"reroll_disc": ["reroll cost", "flat", false],
}

var _roster := []
var _sel := 0
var _btns := []
var _records := {}
var _icon: TextureRect
var _name: Label
var _tag: Label
var _rule: Label
var _perks: VBoxContainer
var _best: Label
var _heir_lbl: Label
var _heir_btn: Button
var _heir_row: HBoxContainer
var _wild_lbl: Label
var _wild_btn: Button
var _wild_row: HBoxContainer
var _lab_lbl: Label
var _leaving := false
var _scroll: ScrollContainer


func _ready() -> void:
	get_tree().paused = false
	get_tree().auto_accept_quit = false             # closing the window goes through _notification (the report is written)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Kit.sky(self, 0.31)
	_roster = Queens.featured()
	_records = RunLog.load_all()
	for i in _roster.size():
		if _roster[i]["id"] == Run.queen_id:
			_sel = i
	var root := MarginContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		root.add_theme_constant_override("margin_" + side, 26)
	add_child(root)
	var cols = Kit.hbox(22)
	root.add_child(cols)
	cols.add_child(_build_left())
	cols.add_child(_build_detail())
	_select(_sel)


func _build_left() -> Control:
	var left = Kit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head = Kit.hbox(14)
	left.add_child(head)
	var qi = Kit.icon("ui/queen.png", 84)
	if qi != null:
		head.add_child(qi)
	var tv = Kit.vbox(0)
	head.add_child(tv)
	tv.add_child(Kit.label("InfDNA", 62, Kit.GOLD, 8))
	tv.add_child(Kit.label("An evolving ant colony. Choose the queen who founds it.", 19, Kit.INK, 5))
	var gp = Kit.panel("frame_wide", 0.8, Vector2(6, 4))
	gp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(gp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gp.add_child(scroll)
	_scroll = scroll
	var grid := GridContainer.new()
	grid.columns = COLS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	scroll.add_child(grid)
	var group := ButtonGroup.new()
	for i in _roster.size():
		var q = _roster[i]
		var b = Kit.button(q["name"], 17, 0.5, Vector2(0, 40))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		b.button_group = group
		b.clip_text = true
		var rec = _records.get(q["id"])
		b.tooltip_text = q["tag"] + (("\nBest run: %s, %d raids" % [RunLog.clock(float(rec.get("time", 0.0))), int(rec.get("raids", 0))]) if rec is Dictionary else "")
		b.pressed.connect(_select.bind(i))
		b.gui_input.connect(_on_btn_input.bind(i))
		grid.add_child(b)
		_btns.append(b)
	left.add_child(Kit.label("Arrow keys browse   Enter starts   Double-click a queen to start", 15, Kit.INK, 4))
	return left


func _build_detail() -> Control:
	var p = Kit.panel("frame_wide", 1.0, Vector2(18, 10))
	p.custom_minimum_size = Vector2(DETAIL_W, 0)
	var v = Kit.vbox(8)
	p.add_child(v)
	var head = Kit.hbox(12)
	v.add_child(head)
	_icon = Kit.icon("ui/queen.png", 92)
	if _icon != null:
		head.add_child(_icon)
	var nv = Kit.vbox(2)
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nv)
	_name = Kit.label("", 32, Kit.INK, 6)
	nv.add_child(_name)
	_tag = Kit.para("", 17, DETAIL_W - 160, Kit.DIM)
	nv.add_child(_tag)
	v.add_child(Kit.label("COLONY RULE", 15, Kit.GOLD))
	_rule = Kit.para("", 19, DETAIL_W - 50)
	v.add_child(_rule)
	_perks = Kit.vbox(2)
	v.add_child(_perks)
	var fill = Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(fill)
	_best = Kit.label("", 16, Kit.GOLD)
	v.add_child(_best)
	# what earlier colonies left behind: the heirloom, the Wild, the Lab items
	_heir_row = Kit.hbox(8)
	v.add_child(_heir_row)
	_heir_lbl = Kit.para("", 15, DETAIL_W - 150, Kit.GOLD)
	_heir_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heir_row.add_child(_heir_lbl)
	_heir_btn = Kit.button("On", 15, 0.45, Vector2(70, 34))
	_heir_btn.toggle_mode = true
	_heir_btn.toggled.connect(_on_heir_toggled)
	_heir_row.add_child(_heir_btn)
	_wild_row = Kit.hbox(8)
	v.add_child(_wild_row)
	_wild_lbl = Kit.para("", 15, DETAIL_W - 150, Kit.BAD)
	_wild_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wild_row.add_child(_wild_lbl)
	_wild_btn = Kit.button("On", 15, 0.45, Vector2(70, 34))
	_wild_btn.toggle_mode = true
	_wild_btn.toggled.connect(_on_wild_toggled)
	_wild_row.add_child(_wild_btn)
	_lab_lbl = Kit.para("", 15, DETAIL_W - 50, Kit.GOOD)
	v.add_child(_lab_lbl)
	_refresh_legacy()
	var br = Kit.hbox(10)
	v.add_child(br)
	var quit = Kit.button("Quit", 20, 0.7, Vector2(110, 54))
	quit.pressed.connect(_quit)
	br.add_child(quit)
	var rnd = Kit.button("Random", 20, 0.7, Vector2(130, 54))
	rnd.pressed.connect(_random)
	br.add_child(rnd)
	var go = Kit.button("Start", 24, 0.8, Vector2(0, 54))
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.add_theme_color_override("font_color", Kit.GOLD)
	go.pressed.connect(_start)
	br.add_child(go)
	return p


func _refresh_legacy() -> void:
	var h = Legacy.saved()
	_heir_row.visible = not h.is_empty()
	if not h.is_empty():
		var on = Legacy.is_on()
		_heir_lbl.text = "Heirloom from %s: %s." % [h.get("from", "a past colony"), str(h.get("label", "")).to_lower()]
		_heir_lbl.modulate.a = 1.0 if on else 0.5
		_heir_btn.set_pressed_no_signal(on)
		_heir_btn.text = "On" if on else "Off"
	var ls = Wild.lines()
	_wild_row.visible = not ls.is_empty()
	if not ls.is_empty():
		var on = Wild.is_on()
		var k = Wild.active()
		_wild_btn.set_pressed_no_signal(on)
		_wild_btn.text = "On" if on else "Off"
		if on and not k.is_empty():
			_wild_lbl.text = "The Wild remembers %d line%s. Your rival descends from the %s of colony #%d." % [ls.size(), "" if ls.size() == 1 else "s", k.get("title", "Kin"), int(k.get("id", 0))]
		else:
			_wild_lbl.text = "The Wild is off: your rival will be plain red ants."
		_wild_lbl.modulate.a = 1.0 if on else 0.5
	var lab = ShopItems.lab_load()
	var names := []
	for id in lab["items"].keys():
		names.append(ShopItems.ITEMS[id]["name"] + ("" if int(lab["items"][id]) == 1 else " x%d" % int(lab["items"][id])))
	_lab_lbl.visible = not names.is_empty()
	_lab_lbl.text = "From the Lab: %s." % ", ".join(PackedStringArray(names))


func _on_heir_toggled(on: bool) -> void:
	Legacy.set_use(on)
	_refresh_legacy()


func _on_wild_toggled(on: bool) -> void:
	Wild.set_use(on)
	_refresh_legacy()


func _select(i: int) -> void:
	_sel = clamp(i, 0, _roster.size() - 1)
	var q = _roster[_sel]
	for k in _btns.size():
		_btns[k].set_pressed_no_signal(k == _sel)
	_scroll.call_deferred("ensure_control_visible", _btns[_sel])
	_name.text = q["name"]
	_tag.text = q["tag"]
	_rule.text = q["rule_text"]
	if _icon != null:
		_icon.modulate = Color.WHITE
	for c in _perks.get_children():
		c.queue_free()
	for pk in perks(q):
		_perks.add_child(Kit.label(pk[0], 16, Kit.GOOD if pk[1] else Kit.BAD, 3))
	var rec = _records.get(q["id"])
	_best.text = ("Your best with her: %s, %d raids, %d ants" % [RunLog.clock(float(rec.get("time", 0.0))), int(rec.get("raids", 0)), int(rec.get("ants", 0))]) if rec is Dictionary else "No run with her yet."


# Her perks in plain words: [text, good], the stat changes she starts with (the rule itself is on the card above).
static func perks(q: Dictionary) -> Array:
	var out := []
	for k in q["mods"].keys():
		if not MOD_INFO.has(k):
			continue
		var info = MOD_INFO[k]
		var v = float(q["mods"][k])
		var txt := ""
		match info[1]:
			"%":
				txt = "%+d%% %s" % [int(round(v * 100.0)), info[0]]
			"flag":
				txt = info[0]
			_:
				txt = "%+d %s" % [int(round(v)), info[0]]
		out.append([txt, (v > 0.0) == info[2]])
	var c = q["colony"]
	if c.has("queen_hp"):
		out.append(["%+d queen HP" % int(c["queen_hp"]), c["queen_hp"] > 0])
	if c.has("queen_hp_pct"):
		out.append(["%+d%% queen HP" % int(c["queen_hp_pct"] * 100.0), true])
	if c.has("mutation"):
		out.append(["%+d%% mutation chance" % int(round(c["mutation"] * 100.0)), c["mutation"] > 0])
	if c.has("egg_cost"):
		out.append(["%+d food per egg" % int(c["egg_cost"]), c["egg_cost"] < 0])
	if c.has("hatch"):
		out.append(["%+d%% hatch time" % int(round((c["hatch"] - 1.0) * 100.0)), c["hatch"] < 1.0])
	if c.has("double_mut"):
		out.append(["mutations often come in pairs", true])
	if q["body"].size() > 0:
		var parts := []
		for k in q["body"].keys():
			parts.append(str(k))
		out.append(["founders are born with: " + ", ".join(PackedStringArray(parts)), true])
	if q["bias"].size() > 0:
		out.append(["mutations lean toward: " + ", ".join(PackedStringArray(q["bias"].keys())), true])
	return out.slice(0, 6)


func _on_btn_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
		_select(i)
		_start()


func _random() -> void:
	_select(randi() % _roster.size())


func _start() -> void:
	if _leaving:
		return
	_leaving = true
	Run.queen_id = _roster[_sel]["id"]
	Run.heirloom = Legacy.active()
	Run.kin = Wild.active()
	Run.items = ShopItems.lab_load()["items"].duplicate()
	Run.last_sim = null
	get_tree().change_scene_to_file(Run.COLONY)


func _quit() -> void:
	if not BugReport.closing():
		BugReport.write("game closed", true)
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_start()
			KEY_LEFT:
				_select(_sel - 1)
			KEY_RIGHT:
				_select(_sel + 1)
			KEY_UP:
				_select(_sel - COLS)
			KEY_DOWN:
				_select(_sel + COLS)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
