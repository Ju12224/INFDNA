extends Reference
# Shared look + motion for every InfDNA screen. The owner's UI art first (content/art/ui, cut by tools/art/make_ui_icons.py): the colony's icons
# and the bone frame round the panels; Brotato's own stat icons, lifebars and particles fill in where there is no picture of ours yet.

const INK = Color("#15121a")
const AL = preload("res://mods-unpacked/Judah-InfDNA/content/colony/art_lib.gd")
const ShopItems = preload("res://mods-unpacked/Judah-InfDNA/core/shop_items.gd")
# short key -> the owner's icon (content/art/...); these win over the Brotato icon of the same key below
const OWN = {
	"food": "ui/food.png",
	"egg": "ui/brood.png",
	"brood": "ui/brood.png",
	"ant": "ui/soldier.png",
	"queen": "ui/queen.png",
	"soldier": "ui/soldier.png",
	"forager": "ui/food_pile.png",
	"food_pile": "ui/food_pile.png",
	"skull": "ui/midden.png",
	"midden": "ui/midden.png",
	"fungus": "ui/fungus.png",
	"power": "ui/will.png",
	"will": "ui/will.png",
	"fire": "ui/acid.png",
	"acid": "ui/acid.png",
	"boss": "ui/void.png",
	"void": "ui/void.png",
	"dominion": "ui/dominion.png",
	"tremors": "ui/tremors.png",
}
const OWN_PANEL = "ui/frame_wide.png"     # nine-patch: the bone-and-claw rim stays its size, the dark middle stretches
const OWN_PANEL_M = [30, 26, 30, 26]       # left, top, right, bottom rim in the picture's px
const FONT_PATH = "res://resources/fonts/raw/Anybody-Medium.ttf"
const T_PANEL = "res://ui/hud/ui_panel_normal.png"
const T_BAR_BG = "res://ui/hud/ui_lifebar_bg.png"
const T_BAR_FILL = "res://ui/hud/ui_lifebar_fill.png"
const T_BAR_FRAME = "res://ui/hud/ui_lifebar_frame.png"
const T_CIRCLE = "res://ui/hud/ui_progress_under.png"
const T_RING = "res://ui/hud/ui_progress_progress.png"
const SND_HOVER = "res://ui/sounds/button_focus.wav"
const SND_CLICK = "res://ui/sounds/button_press.wav"

const GOLD = Color("#f2c14e")
const GREEN = Color("#7ed957")
const RED = Color("#e8483b")
const BLUE = Color("#5aa9e6")
const PURPLE = Color("#b36be0")
const BG = Color("#1f1b26")
const BG_HI = Color("#2b2733")

# short key -> Brotato icon path
const ICONS = {
	"food": "res://items/materials/harvesting_icon.png",
	"hp": "res://items/stats/max_hp.png",
	"attack": "res://items/stats/melee_damage.png",
	"speed": "res://items/stats/speed.png",
	"carry": "res://items/stats/harvesting.png",
	"dig": "res://items/stats/engineering.png",
	"armor": "res://items/stats/armor.png",
	"regen": "res://items/stats/hp_regeneration.png",
	"lifesteal": "res://items/stats/lifesteal.png",
	"sense": "res://items/stats/range.png",
	"luck": "res://items/stats/luck.png",
	"crit": "res://items/stats/crit_chance.png",
	"dodge": "res://items/stats/dodge.png",
	"fire": "res://items/stats/elemental_damage.png",
	"tempo": "res://items/stats/attack_speed.png",
	"power": "res://items/stats/percent_damage.png",
	"ranged": "res://items/stats/ranged_damage.png",
	"boss": "res://ui/icons/misc/boss_icon.png",
	"elite": "res://ui/icons/misc/elite_icon.png",
	"horde": "res://ui/icons/misc/horde_icon.png",
	"enemy": "res://ui/icons/misc/enemy_icon.png",
	"info": "res://items/global/info.png",
	"random": "res://items/global/random_icon.png",
	"locked": "res://items/global/locked_icon.png",
	"exit": "res://ui/menus/global/exit_icon.png",
	"ant": "res://items/all/spider/spider_icon.png",
	"egg": "res://items/all/alien_baby/alien_baby_icon.png",
	"forager": "res://items/all/fruit_basket/fruit_basket_icon.png",
	"digger": "res://items/all/improved_tools/improved_tools_icon.png",
	"soldier": "res://items/all/warrior_helmet/warrior_helmet_icon.png",
	"balanced": "res://items/all/compass/compass_icon.png",
	"skull": "res://items/all/decomposing_flesh/decomposing_flesh_icon.png",
	"arrow_l": "res://ui/menus/global/arrow_left.png",
	"arrow_r": "res://ui/menus/global/arrow_right.png",
}

const CASTE_COLORS = [Color("#6cc644"), Color("#c9863b"), Color("#e8483b")]
const CASTE_KEYS = ["forager", "digger", "soldier"]


static func tex(path: String):
	return load(path) if path != "" and ResourceLoader.exists(path) else null


static func icon(key: String):
	if OWN.has(key):
		var t = AL.get_lib().tex(OWN[key])
		if t != null:
			return t
	return tex(ICONS.get(key, ""))


# A Lab item's icon: the owner's drawing (content/art/items/<id>.png, cut by tools/art/make_item_icons.py) when there is one, else the
# Brotato item icon the item borrowed. Null when neither exists.
static func item_icon(id: String):
	var f = File.new()
	if f.file_exists(AL.DIR + "items/" + id + ".png"):
		var t = AL.get_lib().tex("items/" + id + ".png")
		if t != null:
			return t
	return tex(ShopItems.icon_path(id)) if ShopItems.ITEMS.has(id) else null


# The owner's icon for a key, or null (no Brotato fallback): for places that should show nothing rather than an old icon.
static func own_icon(key: String):
	return AL.get_lib().tex(OWN[key]) if OWN.has(key) else null


static func font(size: int, outline: int = 2) -> DynamicFont:
	var f = DynamicFont.new()
	if ResourceLoader.exists(FONT_PATH):
		f.font_data = load(FONT_PATH)
	f.size = size
	f.outline_size = outline
	f.outline_color = INK
	return f


# Big chunky panel (Brotato's ink-outlined panel, tinted).
static func panel(tint: Color = Color(0.3, 0.28, 0.38), alpha: float = 0.96, pad: float = 12.0) -> StyleBox:
	var own = AL.get_lib().tex(OWN_PANEL)
	if own != null:
		var o = StyleBoxTexture.new()
		o.texture = own
		o.margin_left = OWN_PANEL_M[0]
		o.margin_top = OWN_PANEL_M[1]
		o.margin_right = OWN_PANEL_M[2]
		o.margin_bottom = OWN_PANEL_M[3]
		# the frame is already coloured (bone and dark earth): the panel's tint only leans it a little
		var lean = Color.white.linear_interpolate(tint.lightened(0.45), 0.22)
		o.modulate_color = Color(lean.r, lean.g, lean.b, alpha)
		o.content_margin_left = max(pad + 8, OWN_PANEL_M[0] + 4)
		o.content_margin_right = max(pad + 8, OWN_PANEL_M[2] + 4)
		o.content_margin_top = max(pad + 4, OWN_PANEL_M[1] + 2)
		o.content_margin_bottom = max(pad + 4, OWN_PANEL_M[3] + 2)
		return o
	var t = tex(T_PANEL)
	if t == null:
		return flat(Color(tint.r * 0.4, tint.g * 0.4, tint.b * 0.4, alpha), INK, 12, 3, pad)
	var s = StyleBoxTexture.new()
	s.texture = t
	s.margin_left = 22
	s.margin_right = 22
	s.margin_top = 22
	s.margin_bottom = 22
	s.modulate_color = Color(tint.r, tint.g, tint.b, alpha)
	s.content_margin_left = pad + 8
	s.content_margin_right = pad + 8
	s.content_margin_top = pad + 4
	s.content_margin_bottom = pad + 4
	return s


# Small flat box with an ink outline and a soft drop shadow (chips, buttons, cards).
static func flat(bg: Color, border: Color = INK, radius: int = 9, bw: int = 3, pad: float = 8.0, shadow: int = 5) -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 4
	s.content_margin_right = pad + 4
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = Color(0, 0, 0, 0.38)
		s.shadow_offset = Vector2(0, 3)
	s.anti_aliasing = true
	return s


static func label(parent: Node, text: String, f: Font, col: Color = Color.white) -> Label:
	var l = Label.new()
	l.text = text
	l.add_font_override("font", f)
	if col != Color.white:
		l.add_color_override("font_color", col)
	if parent != null:
		parent.add_child(l)
	return l


static func icon_rect(parent: Node, key: String, size: float) -> TextureRect:
	var r = TextureRect.new()
	r.texture = icon(key)
	r.rect_min_size = Vector2(size, size)
	r.expand = true
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent != null:
		parent.add_child(r)
	return r


# ------------------------------------------------------------------ motion
static func tween(node: Node) -> Tween:
	var tw = Tween.new()
	node.add_child(tw)
	tw.connect("tween_all_completed", tw, "queue_free")
	return tw


static func center_pivot(c: Control) -> void:
	c.rect_pivot_offset = c.rect_size * 0.5


# Fade + scale in with a little overshoot.
static func pop_in(c: Control, delay: float = 0.0, from_scale: float = 0.88, dur: float = 0.32) -> void:
	c.modulate.a = 0.0
	c.rect_scale = Vector2.ONE * from_scale
	c.rect_pivot_offset = c.rect_size * 0.5
	var tw = tween(c)
	tw.interpolate_property(c, "modulate:a", 0.0, 1.0, dur * 0.7, Tween.TRANS_SINE, Tween.EASE_OUT, delay)
	tw.interpolate_property(c, "rect_scale", Vector2.ONE * from_scale, Vector2.ONE, dur, Tween.TRANS_BACK, Tween.EASE_OUT, delay)
	tw.start()


# Slide a root-level control in from an offset (px) while fading.
static func slide_in(c: Control, from_offset: Vector2, delay: float = 0.0, dur: float = 0.38) -> void:
	var end = c.rect_position
	c.rect_position = end + from_offset
	c.modulate.a = 0.0
	var tw = tween(c)
	tw.interpolate_property(c, "rect_position", end + from_offset, end, dur, Tween.TRANS_BACK, Tween.EASE_OUT, delay)
	tw.interpolate_property(c, "modulate:a", 0.0, 1.0, dur * 0.6, Tween.TRANS_SINE, Tween.EASE_OUT, delay)
	tw.start()


# Slide an anchored control by animating its margins (its final margins are kept).
static func slide_margins(c: Control, from_offset: Vector2, delay: float = 0.0, dur: float = 0.38) -> void:
	var m = [c.margin_left, c.margin_right, c.margin_top, c.margin_bottom]
	var off = [from_offset.x, from_offset.x, from_offset.y, from_offset.y]
	var names = ["margin_left", "margin_right", "margin_top", "margin_bottom"]
	c.modulate.a = 0.0
	var tw = tween(c)
	for i in 4:
		c.set(names[i], m[i] + off[i])
		tw.interpolate_property(c, names[i], m[i] + off[i], m[i], dur, Tween.TRANS_BACK, Tween.EASE_OUT, delay)
	tw.interpolate_property(c, "modulate:a", 0.0, 1.0, dur * 0.6, Tween.TRANS_SINE, Tween.EASE_OUT, delay)
	tw.start()


static func bump(c: Control, amount: float = 1.12, dur: float = 0.22) -> void:
	c.rect_pivot_offset = c.rect_size * 0.5
	var tw = tween(c)
	tw.interpolate_property(c, "rect_scale", Vector2.ONE * amount, Vector2.ONE, dur, Tween.TRANS_BACK, Tween.EASE_OUT)
	tw.start()


static func shake(c: Control, amount: float = 8.0, dur: float = 0.3) -> void:
	var base = c.rect_position
	var tw = tween(c)
	for i in 6:
		var k = 1.0 - float(i) / 6.0
		tw.interpolate_property(c, "rect_position", base + Vector2((amount if i % 2 == 0 else -amount) * k, 0), base, dur / 6.0, Tween.TRANS_SINE, Tween.EASE_OUT, dur / 6.0 * i)
	tw.start()


# Full-screen colour fade (0 -> a). Returns the rect so the caller can tween it out.
static func fade_rect(parent: Node, col: Color, from_a: float, to_a: float, dur: float, free_after: bool = true) -> ColorRect:
	var r = ColorRect.new()
	r.color = Color(col.r, col.g, col.b, from_a)
	r.anchor_right = 1.0
	r.anchor_bottom = 1.0
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE if to_a < 0.5 else Control.MOUSE_FILTER_STOP
	parent.add_child(r)
	var tw = tween(r)
	tw.interpolate_property(r, "color:a", from_a, to_a, dur, Tween.TRANS_SINE, Tween.EASE_IN_OUT)
	tw.start()
	if free_after:
		tw.connect("tween_all_completed", r, "queue_free")
	return r
