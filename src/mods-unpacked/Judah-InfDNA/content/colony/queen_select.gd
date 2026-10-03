extends Control
# Queen select: pick the founder of the colony. Each queen is a Brotato
# character reinterpreted as an ant queen: a starting-genome bias plus one rule.

const Kit = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_kit.gd")
const KBtn = preload("res://mods-unpacked/Judah-InfDNA/content/colony/ui_button.gd")
const Queens = preload("res://mods-unpacked/Judah-InfDNA/core/queens.gd")
const RunLog = preload("res://mods-unpacked/Judah-InfDNA/core/run_log.gd")
const Legacy = preload("res://mods-unpacked/Judah-InfDNA/core/legacy.gd")
const Wild = preload("res://mods-unpacked/Judah-InfDNA/core/wild.gd")
const Baker = preload("res://mods-unpacked/Judah-InfDNA/content/colony/sprite_baker.gd")
const COLONY_SCENE = "res://mods-unpacked/Judah-InfDNA/content/colony/colony.tscn"
const TITLE_SCENE = "res://ui/menus/title_screen/title_screen.tscn"
const COLS = 7

# mods key -> [label, icon, unit, good_when_positive]
const MOD_INFO = {
	"hp": ["HP", "hp", "%", true], "attack": ["attack", "attack", "%", true], "speed": ["speed", "speed", "%", true],
	"carry": ["carry", "carry", "%", true], "dig": ["digging", "dig", "%", true], "life": ["lifespan", "tempo", "%", true],
	"upkeep": ["food upkeep", "food", "%", false], "thorns": ["thorns", "fire", "%", true],
	"armor": ["armor", "armor", "pct", true], "sense": ["sense", "sense", "flat", true], "regen": ["regen/s", "regen", "flat", true],
	"defend_attack": ["defender attack", "attack", "%", true], "kill_food": ["kill food", "food", "%", true],
	"pile_rich": ["richer piles", "food", "%", true], "pile_near": ["closer food", "food", "flag", true],
	"interest": ["raid interest", "food", "%", true], "price_disc": ["Lab discount", "luck", "%", true],
	"raid_size": ["raid size", "horde", "%", false], "tunnel_dmg": ["tunnel trap dmg", "fire", "flat", true],
	"siege_dmg": ["siege trap dmg", "fire", "flat", true], "queen_regen": ["queen regen", "regen", "%", true],
	"reroll_disc": ["reroll cost", "luck", "flat", true],
}

var _roster := []
var _sel := 0
var _baker
var _cards := []
var _card_styles := []
var _card_scales := []
var _f_s: Font
var _records := {}      # queen id -> best run (run_log.gd)
var _f_m: Font
var _f_l: Font
var _f_xl: Font
var _preview: TextureRect
var _name: Label
var _tag: Label
var _rule: Label
var _count: Label
var _chips: GridContainer
var _detail_root: Control
var _preview_genome = null
var _bgfx: Control
var _motes := []
var _mote_tex := {}
var _t := 0.0
var _leaving := false
var _detail: PanelContainer
var _heir_row: HBoxContainer
var _heir_lbl: Label
var _heir_btn: Button
var _wild_row: HBoxContainer
var _wild_lbl: Label
var _wild_btn: Button


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_f_s = Kit.font(19, 1)
	_records = RunLog.load_all()
	_f_m = Kit.font(25, 2)
	_f_l = Kit.font(38, 3)
	_f_xl = Kit.font(60, 4)
	for q in Queens.roster():
		if ResourceLoader.exists(Queens.icon_path(q)):
			_roster.append(q)
	var last = Engine.get_meta("infdna_queen") if Engine.has_meta("infdna_queen") else ""
	for i in _roster.size():
		if _roster[i]["id"] == last:
			_sel = i
	for n in range(1, 9):
		_mote_tex[n] = Kit.tex("res://particles/sprites/particle_%d.png" % n)
	_baker = Baker.new()
	add_child(_baker)
	anchor_right = 1.0
	anchor_bottom = 1.0

	var bg = ColorRect.new()
	bg.color = Color("#1a1620")
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	_bgfx = Control.new()
	_bgfx.anchor_right = 1.0
	_bgfx.anchor_bottom = 1.0
	_bgfx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bgfx.connect("draw", self, "_draw_bg")
	add_child(_bgfx)
	var rng = RandomNumberGenerator.new()
	rng.seed = 5
	for i in 34:
		_motes.append([Vector2(rng.randf(), rng.randf()), rng.randf_range(0.01, 0.035), rng.randf_range(10.0, 30.0), rng.randi_range(1, 8), rng.randf_range(0.08, 0.22), rng.randf() * 6.0])

	var root = HBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.margin_left = 40
	root.margin_right = -40
	root.margin_top = 26
	root.margin_bottom = -70
	root.add_constant_override("separation", 30)
	add_child(root)

	# ---- left: title + grid
	var left = VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_constant_override("separation", 10)
	root.add_child(left)
	var th = HBoxContainer.new()
	th.add_constant_override("separation", 14)
	left.add_child(th)
	Kit.icon_rect(th, "ant", 60)
	var tv = VBoxContainer.new()
	th.add_child(tv)
	Kit.label(tv, "Choose your queen", _f_xl)
	_count = Kit.label(tv, "", _f_s)
	_count.modulate = Color(1, 1, 1, 0.65)
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.scroll_horizontal_enabled = false
	left.add_child(scroll)
	var gpad = MarginContainer.new()
	gpad.add_constant_override("margin_left", 8)
	gpad.add_constant_override("margin_right", 14)
	gpad.add_constant_override("margin_top", 10)
	gpad.add_constant_override("margin_bottom", 10)
	scroll.add_child(gpad)
	var grid = GridContainer.new()
	grid.columns = COLS
	grid.add_constant_override("hseparation", 10)
	grid.add_constant_override("vseparation", 10)
	gpad.add_child(grid)
	for i in _roster.size():
		var c = _make_card(i)
		grid.add_child(c)
		_cards.append(c)

	# ---- right: detail
	_detail = PanelContainer.new()
	_detail.rect_min_size = Vector2(600, 0)
	_detail.add_stylebox_override("panel", Kit.panel(Color(0.3, 0.27, 0.4), 0.97, 14.0))
	root.add_child(_detail)
	var rv = VBoxContainer.new()
	rv.add_constant_override("separation", 10)
	_detail.add_child(rv)
	_detail_root = rv
	var stage = PanelContainer.new()
	stage.add_stylebox_override("panel", Kit.flat(Color("#2c2a3a"), Kit.INK, 14, 3, 4.0, 0))
	rv.add_child(stage)
	_preview = TextureRect.new()
	_preview.rect_min_size = Vector2(540, 330)
	_preview.expand = true
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.add_child(_preview)
	_name = Kit.label(rv, "", _f_xl)
	_name.autowrap = true
	_tag = Kit.label(rv, "", _f_m)
	_tag.autowrap = true
	_tag.modulate = Color(1, 1, 1, 0.72)
	var rh = HBoxContainer.new()
	rh.add_constant_override("separation", 8)
	rv.add_child(rh)
	Kit.icon_rect(rh, "info", 28)
	Kit.label(rh, "COLONY RULE", _f_s, Kit.GOLD)
	_rule = Kit.label(rv, "", _f_m)
	_rule.autowrap = true
	_chips = GridContainer.new()
	_chips.columns = 2
	_chips.add_constant_override("hseparation", 8)
	_chips.add_constant_override("vseparation", 8)
	_chips.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(_chips)
	# the heirloom a past colony handed down (legacy.gd): shown here, switch it off to start plain
	_heir_row = HBoxContainer.new()
	_heir_row.add_constant_override("separation", 10)
	rv.add_child(_heir_row)
	Kit.icon_rect(_heir_row, "luck", 30)
	_heir_lbl = Kit.label(_heir_row, "", _f_s, Kit.GOLD)
	_heir_lbl.autowrap = true
	_heir_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heir_btn = _btn(_heir_row, "On", "")
	_heir_btn.toggle_mode = true
	_heir_btn.rect_min_size = Vector2(90, 44)
	_heir_btn.connect("toggled", self, "_on_heir_toggled")
	_refresh_heirloom()
	# the Wild (wild.gd): the line of an earlier colony of yours that this colony's rival descends from; switch it off for plain red ants
	_wild_row = HBoxContainer.new()
	_wild_row.add_constant_override("separation", 10)
	rv.add_child(_wild_row)
	Kit.icon_rect(_wild_row, "skull", 30)
	_wild_lbl = Kit.label(_wild_row, "", _f_s, Color("#ff9d8a"))
	_wild_lbl.autowrap = true
	_wild_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wild_btn = _btn(_wild_row, "On", "")
	_wild_btn.toggle_mode = true
	_wild_btn.rect_min_size = Vector2(90, 44)
	_wild_btn.connect("toggled", self, "_on_wild_toggled")
	_refresh_wild()
	var br = HBoxContainer.new()
	br.add_constant_override("separation", 12)
	rv.add_child(br)
	var back = _btn(br, "Back", "arrow_l")
	back.connect("pressed", self, "_back")
	var rnd = _btn(br, "Random", "random")
	rnd.connect("pressed", self, "_random")
	var go = _btn(br, "Found colony", "arrow_r", Kit.GREEN)
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.rect_min_size = Vector2(0, 58)
	go.connect("pressed", self, "_start")

	var hint = Kit.label(self, "Arrow keys browse    Enter found colony    Double-click a queen to start    Esc back", _f_s)
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.margin_left = 44
	hint.margin_bottom = -8
	hint.modulate = Color(1, 1, 1, 0.55)
	_select(_sel, false)
	call_deferred("_intro")


func _refresh_heirloom() -> void:
	var h = Legacy.saved()
	_heir_row.visible = not h.empty()
	if h.empty():
		return
	_heir_lbl.text = "Heirloom (%s): %s" % [h.get("from", "a past colony"), str(h.get("label", "")).to_lower()]
	_heir_btn.set_pressed_no_signal(Legacy.is_on())
	_heir_btn.text = "On" if Legacy.is_on() else "Off"


func _refresh_wild() -> void:
	var ls = Wild.lines()
	_wild_row.visible = not ls.empty()
	if ls.empty():
		return
	var on = Wild.is_on()
	_wild_btn.set_pressed_no_signal(on)
	_wild_btn.text = "On" if on else "Off"
	var k = Wild.active()
	if on and not k.empty():
		_wild_lbl.text = "The Wild remembers %d line%s. Your rival descends from the %s of colony #%d (raid %d, %d runs on)." % [
			ls.size(), "" if ls.size() == 1 else "s", k.get("title", "Kin"), int(k.get("id", 0)), int(k.get("raids", 0)), int(k.get("runs", 0))]
	else:
		_wild_lbl.text = "The Wild is switched off: your rival will be plain red ants."


func _on_wild_toggled(on: bool) -> void:
	Wild.set_use(on)
	_refresh_wild()


func _on_heir_toggled(on: bool) -> void:
	Legacy.set_use(on)
	_heir_btn.text = "On" if on else "Off"


func _intro() -> void:
	for i in _cards.size():
		Kit.pop_in(_cards[i], 0.012 * i, 0.8, 0.34)
	Kit.slide_in(_detail, Vector2(70, 0), 0.1, 0.45)
	Kit.fade_rect(self, Color("#0b0910"), 1.0, 0.0, 0.5)


func _process(delta: float) -> void:
	_t += delta
	if _preview_genome != null and _preview.texture == null:
		_preview.texture = _baker.get_texture(_preview_genome, 2.0)
	# the queen breathes on the stage
	_preview.rect_pivot_offset = _preview.rect_size * Vector2(0.5, 0.92)
	var br = sin(_t * 1.8)
	_preview.rect_scale = Vector2(1.0 - 0.012 * br, 1.0 + 0.02 * br)
	_preview.rect_rotation = sin(_t * 0.9) * 0.6
	# selected card glows
	if _sel < _card_styles.size():
		var st = _card_styles[_sel]
		var q = Color(_roster[_sel]["color"])
		st.border_color = Kit.GOLD.linear_interpolate(Color.white, 0.35 + 0.3 * sin(_t * 4.0))
	_bgfx.update()


func _draw_bg() -> void:
	var s = _bgfx.rect_size
	var soil_h = 50.0
	# far hills
	var pts = PoolVector2Array()
	pts.append(Vector2(0, s.y))
	var x := 0.0
	while x <= s.x + 40.0:
		pts.append(Vector2(x, s.y - soil_h - 70.0 - sin(x * 0.006 + 1.0) * 34.0 - sin(x * 0.017) * 12.0))
		x += 40.0
	pts.append(Vector2(s.x, s.y))
	_bgfx.draw_colored_polygon(pts, Color(0.18, 0.22, 0.24))
	# drifting Brotato particles
	for m in _motes:
		var p = Vector2(m[0].x * s.x, fposmod(m[0].y - _t * m[1], 1.0) * s.y)
		var tw = 0.5 + 0.5 * sin(_t * 1.6 + m[5])
		var tx = _mote_tex.get(m[3])
		if tx != null:
			_bgfx.draw_set_transform(p, _t * 0.4 + m[5], Vector2.ONE)
			_bgfx.draw_texture_rect(tx, Rect2(-m[2] * 0.5, -m[2] * 0.5, m[2], m[2]), false, Color(1, 1, 1, m[4] * (0.5 + 0.5 * tw)))
	_bgfx.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# soil strip with grass edge and ink line
	_bgfx.draw_rect(Rect2(0, s.y - soil_h, s.x, soil_h), Color("#4a2d1c"))
	_bgfx.draw_rect(Rect2(0, s.y - soil_h, s.x, 12), Color("#7ab34e"))
	_bgfx.draw_rect(Rect2(0, s.y - soil_h - 3, s.x, 3), Kit.INK)
	_bgfx.draw_rect(Rect2(0, s.y - soil_h + 12, s.x, 3), Kit.INK)


func _make_card(i: int) -> Control:
	var q = _roster[i]
	var col = Color(q["color"])
	var card = PanelContainer.new()
	card.rect_min_size = Vector2(150, 148)
	var st = Kit.flat(Kit.BG, col.darkened(0.35), 12, 3, 6.0, 5)
	card.add_stylebox_override("panel", st)
	_card_styles.append(st)
	var v = VBoxContainer.new()
	v.alignment = BoxContainer.ALIGN_CENTER
	v.add_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var ib = PanelContainer.new()
	ib.add_stylebox_override("panel", Kit.flat(col.darkened(0.55), col.darkened(0.15), 40, 2, 2.0, 0))
	ib.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ibc = CenterContainer.new()
	ibc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(ibc)
	var holder = Control.new()
	holder.rect_min_size = Vector2(88, 84)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ibc.add_child(holder)
	holder.add_child(ib)
	ib.rect_position = Vector2(4, 2)
	if q["rule"].size() > 0:     # gold pip: this queen bends a colony rule
		var pip = Kit.icon_rect(holder, "info", 26)
		pip.rect_position = Vector2(-2, -4)
		pip.rect_size = Vector2(26, 26)
	var ic = TextureRect.new()
	ic.texture = load(Queens.icon_path(q))
	ic.rect_min_size = Vector2(76, 76)
	ic.expand = true
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ib.add_child(ic)
	var nm = Kit.label(v, q["name"], _f_s)
	nm.align = Label.ALIGN_CENTER
	nm.autowrap = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rec = _records.get(q["id"])
	if rec is Dictionary:        # your best run with this queen
		var bl = Kit.label(v, "Best %s" % RunLog.clock(float(rec.get("time", 0.0))), _f_s, Kit.GOLD)
		bl.align = Label.ALIGN_CENTER
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.connect("gui_input", self, "_card_input", [i])
	card.connect("mouse_entered", self, "_card_hover", [i, true])
	card.connect("mouse_exited", self, "_card_hover", [i, false])
	return card


func _card_hover(i: int, on: bool) -> void:
	var c = _cards[i]
	c.rect_pivot_offset = c.rect_size * 0.5
	var tw = Kit.tween(c)
	tw.interpolate_property(c, "rect_scale", c.rect_scale, Vector2.ONE * (1.07 if on else (1.04 if i == _sel else 1.0)), 0.14, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.start()
	if on and i != _sel:
		var st = _card_styles[i]
		st.border_color = Color(_roster[i]["color"]).lightened(0.15)
	elif not on and i != _sel:
		_card_styles[i].border_color = Color(_roster[i]["color"]).darkened(0.35)


func _card_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		if ev.doubleclick:
			_select(i)
			_start()
		else:
			_select(i)


func _select(i: int, animate: bool = true) -> void:
	var prev = _sel
	_sel = i
	for k in _cards.size():
		var on = k == i
		var col = Color(_roster[k]["color"])
		_card_styles[k].border_color = Kit.GOLD if on else col.darkened(0.35)
		_card_styles[k].set_border_width_all(5 if on else 3)
		_card_styles[k].bg_color = Kit.BG_HI if on else Kit.BG
		_cards[k].rect_pivot_offset = _cards[k].rect_size * 0.5
		if k == prev or on:
			var tw = Kit.tween(_cards[k])
			tw.interpolate_property(_cards[k], "rect_scale", _cards[k].rect_scale, Vector2.ONE * (1.04 if on else 1.0), 0.16, Tween.TRANS_BACK, Tween.EASE_OUT)
			tw.start()
	var q = _roster[i]
	_name.text = q["name"]
	_tag.text = q["tag"]
	_rule.text = q["rule_text"]
	_count.text = "%d queens  ·  the info pip marks queens that bend a colony rule" % _roster.size()
	_preview_genome = Queens.make_queen_genome(q)
	_preview_genome.uid = 900000 + i     # cache key, never collides with a colony genome
	_preview.texture = _baker.get_texture(_preview_genome, 2.0)
	_fill_chips(q)
	if animate:
		_detail_root.modulate.a = 0.25
		var tw2 = Kit.tween(_detail_root)
		tw2.interpolate_property(_detail_root, "modulate:a", 0.25, 1.0, 0.22, Tween.TRANS_SINE, Tween.EASE_OUT)
		tw2.start()
		Kit.bump(_preview, 1.06, 0.3)


func _fill_chips(q: Dictionary) -> void:
	for c in _chips.get_children():
		c.queue_free()
	var items := []
	for k in q["mods"].keys():
		if not MOD_INFO.has(k):
			continue
		var info = MOD_INFO[k]
		var v = float(q["mods"][k])
		var txt := ""
		match info[2]:
			"%":
				txt = "%+d%% %s" % [int(round(v * 100.0)), info[0]]
			"pct":
				txt = "%+d%% %s" % [int(round(v * 100.0)), info[0]]
			"flag":
				txt = info[0]
			_:
				txt = "%+d %s" % [int(round(v)), info[0]]
		var good = (v > 0.0) == info[3]
		if k == "price_disc":
			good = v > 0.0
		if k == "reroll_disc":
			good = v > 0.0
		items.append([info[1], txt, good])
	var c2 = q["colony"]
	if c2.has("queen_hp"):
		items.append(["hp", "%+d queen HP" % int(c2["queen_hp"]), c2["queen_hp"] > 0])
	if c2.has("queen_hp_pct"):
		items.append(["hp", "%+d%% queen HP" % int(c2["queen_hp_pct"] * 100.0), true])
	if c2.has("mutation"):
		items.append(["power", "%+d%% mutation" % int(round(c2["mutation"] * 100.0)), c2["mutation"] > 0])
	if c2.has("egg_cost"):
		items.append(["food", "%+d egg cost" % int(c2["egg_cost"]), c2["egg_cost"] < 0])
	if c2.has("hatch"):
		items.append(["tempo", "%+d%% hatch time" % int(round((c2["hatch"] - 1.0) * 100.0)), c2["hatch"] < 1.0])
	if c2.has("base_armor"):
		items.append(["armor", "newborn armor +%d" % int(c2["base_armor"]), true])
	if c2.has("tournament"):
		items.append(["crit", "elite parents +%d" % int(c2["tournament"]), true])
	if c2.has("double_mut"):
		items.append(["power", "double mutations", true])
	var body = q["body"]
	if body.size() > 0:
		var parts := []
		for k in body.keys():
			parts.append(str(k))
		items.append(["ant", "founders: " + ", ".join(parts), true])
	if q["bias"].size() > 0:
		items.append(["power", "mutation bias: " + ", ".join(PoolStringArray(q["bias"].keys())), true])
	var n = 0
	for it in items:
		if n >= 10:
			break
		var col = Kit.GREEN if it[2] else Kit.RED
		var pc = PanelContainer.new()
		pc.add_stylebox_override("panel", Kit.flat(col.darkened(0.7), col.darkened(0.1), 9, 2, 3.0, 2))
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_chips.add_child(pc)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 6)
		pc.add_child(h)
		Kit.icon_rect(h, it[0], 24)
		var l = Kit.label(h, it[1], _f_s, col.lightened(0.45))
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Kit.pop_in(pc, 0.03 * n, 0.85, 0.26)
		n += 1


func _random() -> void:
	_select(randi() % _roster.size())
	_start()


func _start() -> void:
	if _leaving:
		return
	_leaving = true
	Engine.set_meta("infdna_queen", _roster[_sel]["id"])
	var r = Kit.fade_rect(self, Color("#0b0910"), 0.0, 1.0, 0.28, false)
	var tw = Kit.tween(r)
	tw.interpolate_callback(self, 0.3, "_go_colony")
	tw.start()


func _go_colony() -> void:
	var _e = get_tree().change_scene(COLONY_SCENE)


func _back() -> void:
	if ResourceLoader.exists(TITLE_SCENE):
		var _e = get_tree().change_scene(TITLE_SCENE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.scancode:
			KEY_ESCAPE:
				_back()
			KEY_ENTER, KEY_KP_ENTER:
				_start()
			KEY_LEFT:
				_select(int(max(0, _sel - 1)))
			KEY_RIGHT:
				_select(int(min(_roster.size() - 1, _sel + 1)))
			KEY_UP:
				_select(int(max(0, _sel - COLS)))
			KEY_DOWN:
				_select(int(min(_roster.size() - 1, _sel + COLS)))


func _btn(parent: Node, text: String, key: String, col: Color = Color("#f2c14e")) -> Button:
	var b = KBtn.new()
	b.setup(text, key, col, 26)
	b.rect_min_size = Vector2(130, 58)
	parent.add_child(b)
	return b
