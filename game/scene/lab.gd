extends Control
# The Evolution Lab between runs (roadmap 4.4). The food fallen colonies earned (the bank, core/shop_items.gd lab_*) buys items for
# the next colony: a handful of offers drawn from the items that have the owner's icon (art/items), a reroll that costs more each
# time, and the row of what the next colony will carry. scene/run.gd hands those items to the colony when it starts; the colony that
# carried them uses them up when it falls. Continue goes to the title to pick the next queen.

const Kit = preload("res://scene/menu_kit.gd")
const Run = preload("res://scene/run.gd")
const ShopItems = preload("res://core/shop_items.gd")
const BugReport = preload("res://core/bug_report.gd")

const CARD_W = 214.0
const CARD_H = 330.0
# pieces of the owner's lab kit on the bench beside the title (art/lab, art/lab2)
const DECOR = ["lab/l_026.png", "lab2/l2_005.png", "lab/l_010.png"]

var _lab := {}
var _bank: Label
var _cards: HBoxContainer
var _owned: HBoxContainer
var _owned_none: Label
var _reroll: Button
var _note: Label


func _ready() -> void:
	get_tree().paused = false
	get_tree().auto_accept_quit = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Kit.sky(self, 0.52)
	var dim := ColorRect.new()
	dim.color = Color(0.06, 0.04, 0.05, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_lab = ShopItems.lab_load()
	if _lab["offers"].is_empty():
		_roll()
	_build()
	_refresh()


func _roll() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	_lab["offers"] = ShopItems.lab_roll(int(_lab["raids"]), _lab["items"], rng)
	_save()


func _save() -> void:
	ShopItems.lab_save(_lab)
	Run.items = _lab["items"].duplicate()


func _build() -> void:
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cc)
	var p = Kit.panel("frame_wide", 1.0, Vector2(26, 14))
	cc.add_child(p)
	var v = Kit.vbox(12)
	p.add_child(v)
	var top = Kit.hbox(16)
	v.add_child(top)
	var tv = Kit.vbox(0)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(Kit.label("Evolution Lab", 42, Kit.GOLD, 7))
	tv.add_child(Kit.label("Spend what your colonies earned to steer the next one. Strains shift its mutation odds.", 17, Kit.INK, 4))
	for d in DECOR:
		var r = Kit.icon(d, 70)
		if r != null:
			top.add_child(r)
	var bank = Kit.panel("frame_small", 0.7, Vector2(10, 2))
	top.add_child(bank)
	var bh = Kit.hbox(8)
	bank.add_child(bh)
	var fi = Kit.icon("ui/food.png", 40)
	if fi != null:
		bh.add_child(fi)
	_bank = Kit.label("", 30, Kit.GOOD, 5)
	bh.add_child(_bank)
	_cards = Kit.hbox(12)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_cards)
	var oh = Kit.hbox(10)
	v.add_child(oh)
	oh.add_child(Kit.label("Your next colony carries:", 17, Kit.DIM, 3))
	_owned = Kit.hbox(4)
	oh.add_child(_owned)
	_owned_none = Kit.label("nothing yet", 17, Kit.DIM, 3)
	oh.add_child(_owned_none)
	_note = Kit.label("", 16, Kit.GOLD, 3)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_note)
	var br = Kit.hbox(16)
	br.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(br)
	_reroll = Kit.button("Reroll", 20, 0.7, Vector2(200, 54))
	_reroll.pressed.connect(_on_reroll)
	br.add_child(_reroll)
	var go = Kit.button("Choose the next queen", 22, 0.8, Vector2(320, 54))
	go.add_theme_color_override("font_color", Kit.GOLD)
	go.pressed.connect(_continue)
	br.add_child(go)


func _refresh() -> void:
	var bank = int(_lab["bank"])
	_bank.text = "%d" % bank
	for c in _cards.get_children():
		c.queue_free()
	var offers: Array = _lab["offers"]
	for i in offers.size():
		_cards.add_child(_card(i, str(offers[i]), bank))
	for c in _owned.get_children():
		c.queue_free()
	var items: Dictionary = _lab["items"]
	for id in items.keys():
		var h = Kit.hbox(0)
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		h.tooltip_text = "%s: %s" % [ShopItems.ITEMS[id]["name"], ShopItems.ITEMS[id]["desc"]]
		var ic = Kit.icon("items/%s.png" % id, 44)
		if ic != null:
			h.add_child(ic)
		if int(items[id]) > 1:
			h.add_child(Kit.label("x%d" % int(items[id]), 15, Kit.INK, 3))
		_owned.add_child(h)
	_owned_none.visible = items.is_empty()
	var rc = ShopItems.lab_reroll_cost(int(_lab["rerolls"]))
	_reroll.text = "Reroll   %d" % rc
	_reroll.disabled = bank < rc


func _card(slot: int, id: String, bank: int) -> Control:
	var p = Kit.panel("frame_wide", 0.7, Vector2(6, 4))
	p.custom_minimum_size = Vector2(CARD_W, CARD_H)
	var v = Kit.vbox(4)
	p.add_child(v)
	if id == "":
		var gone = Kit.label("Bought", 20, Kit.DIM)
		gone.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		gone.size_flags_vertical = Control.SIZE_EXPAND_FILL
		gone.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.add_child(gone)
		return p
	var it = ShopItems.ITEMS[id]
	var ic = Kit.icon("items/%s.png" % id, 96)
	if ic != null:
		var c := CenterContainer.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(ic)
		v.add_child(c)
	var nm = Kit.label(it["name"], 19, Kit.INK, 4)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(nm)
	var tier = int(it["tier"])
	var tl = Kit.label(ShopItems.TIER_NAMES[tier], 14, ShopItems.TIER_COLORS[tier], 3)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tl)
	var d = Kit.para(it["desc"], 15, CARD_W - 40, Kit.INK)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	var have = int(_lab["items"].get(id, 0))
	var price = ShopItems.lab_price(id, have)
	var b = Kit.button("Buy   %d" % price, 18, 0.55, Vector2(0, 42))
	b.disabled = bank < price
	b.tooltip_text = "Not enough food in the bank" if bank < price else "Your next colony starts with it"
	b.pressed.connect(_on_buy.bind(slot))
	v.add_child(b)
	return p


func _on_buy(slot: int) -> void:
	var id = str(_lab["offers"][slot])
	if id == "":
		return
	var price = ShopItems.lab_price(id, int(_lab["items"].get(id, 0)))
	if int(_lab["bank"]) < price:
		return
	_lab["bank"] = int(_lab["bank"]) - price
	_lab["items"][id] = int(_lab["items"].get(id, 0)) + 1
	_lab["offers"][slot] = ""
	_save()
	_note.text = "%s goes into your next colony." % ShopItems.ITEMS[id]["name"]
	_refresh()


func _on_reroll() -> void:
	var c = ShopItems.lab_reroll_cost(int(_lab["rerolls"]))
	if int(_lab["bank"]) < c:
		return
	_lab["bank"] = int(_lab["bank"]) - c
	_lab["rerolls"] = int(_lab["rerolls"]) + 1
	_roll()
	_note.text = ""
	_refresh()


func _continue() -> void:
	Run.items = _lab["items"].duplicate()
	get_tree().change_scene_to_file(Run.TITLE)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
		_continue()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if not BugReport.closing():
			BugReport.write("game closed", true)
		get_tree().quit()
