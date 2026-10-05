extends Node2D
# The soil: the cut face of the ground seen side-on, with the nest dug into it. The world is drawn in CHUNK-wide strips
# streamed around the camera, one sprite each, showing the grid's mask images (WorldGrid.chunk_images) through SHADER:
#   front - the owner's dirt (art/terrain/dirt_soil.png) tinted by stratum (humus, clay, sand, red clay, limestone, shale,
#           bedrock; the seams follow the sim's wave), lighter spoil where the mound sits on the original ground, stones
#           and fossils (real obstacles) as the same dirt in grey or bone, the back plane's tunnels showing through as dark
#           channels, bevelled tunnel rims, an ink outline, darker with depth;
#   back  - where the front is dug out: the recessed rear wall (the same dirt, darker, drifting a little with the camera),
#           side walls lit from above, the shadow the front casts into the tunnel, and holes into the back plane.
# Air is transparent. When the colony digs, the grid repaints its images in place and flags the chunk; we re-upload it.

const WorldGrid = preload("res://core/world_grid.gd")
const Art = preload("res://scene/art.gd")

const DIRT = "terrain/dirt_soil.png"
const BUILDS_PER_FRAME = 2    # new chunks per frame at most, so scrolling never hitches...
const BUILD_US = 4000         # ...and none started once a frame has spent this long building (one takes 1-4 ms), so a frame
                              # spends at most about 8 ms here. Spare time builds the grid's images of chunks off screen ahead.
const NEAR = 1.0              # chunks are built this many chunk widths beyond the screen...
const FAR = 3.0               # ...and freed beyond this many

const SHADER = """
shader_type canvas_item;
// TEXTURE: front mask, aux_tex: aux mask, surf_tex: per-column strip (WorldGrid.chunk_images, one texel per cell)
uniform vec2 origin;      // cell of the masks' first texel
uniform vec2 tsize;       // mask size in cells
uniform vec2 cam;         // camera centre in cells: the rear wall drifts with it
uniform sampler2D aux_tex : filter_linear;
uniform sampler2D surf_tex : filter_nearest;
uniform sampler2D dirt_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 ink : source_color = vec4(0.082, 0.071, 0.102, 1.0);
const vec3 DIRT_AVG = vec3(0.29, 0.235, 0.2);   // the dirt picture's mean colour
const vec2 SOIL = vec2(80.0, 64.0);             // cells the dirt picture covers before it repeats
const vec2 TILES = vec2(5.0, 5.0);              // the picture is 5 x 5 of the owner's tiles (tools/art/make_dirt_atlas.py)
const vec2 SUN = vec2(0.35, 0.94);              // the light falls down and a little to the right
const vec3 STONE = vec3(0.5, 0.49, 0.5);
const vec3 BONE = vec3(0.9, 0.84, 0.7);
const vec3 LUMA = vec3(0.299, 0.587, 0.114);

// the strip blended by hand between the two nearest columns: the sampler alone steps from column to column,
// which shows as a staircase in the strata up close
vec4 surf_at(float ux) {
	float px = ux * tsize.x - 0.5;
	float i0 = floor(px);
	return mix(texture(surf_tex, vec2((i0 + 0.5) / tsize.x, 0.5)), texture(surf_tex, vec2((i0 + 1.5) / tsize.x, 0.5)), px - i0);
}

// The owner's dirt at a cell position, divided by its mean so a stratum's colour can tint it. The tiles in the picture
// do not quite meet at their edges, which showed as a faint grid; near an edge the picture is crossfaded with itself
// shifted half a tile (mid-tile there), so every edge falls where its weight is zero.
vec3 dirt(vec2 wc) {
	vec2 uv = wc / SOIL;
	vec2 q = uv * TILES;
	vec2 w = smoothstep(0.0, 0.08, abs(q - round(q)));
	vec2 h = 0.5 / TILES;
	vec3 c = texture(dirt_tex, uv).rgb * w.x * w.y
		+ texture(dirt_tex, uv + vec2(h.x, 0.0)).rgb * (1.0 - w.x) * w.y
		+ texture(dirt_tex, uv + vec2(0.0, h.y)).rgb * w.x * (1.0 - w.y)
		+ texture(dirt_tex, uv + h).rgb * (1.0 - w.x) * (1.0 - w.y);
	return c / DIRT_AVG;
}

// the stratum's colour at dd cells below the original ground (seams as in WorldGrid.SEAMS)
vec3 strata(float dd) {
	vec3 c = vec3(0.30, 0.24, 0.205);                                   // humus (the owner's dirt as drawn)
	c = mix(c, vec3(0.62, 0.40, 0.22), smoothstep(9.0, 11.0, dd));      // subsoil clay
	c = mix(c, vec3(0.74, 0.57, 0.36), smoothstep(30.0, 32.5, dd));     // sand + gravel
	c = mix(c, vec3(0.55, 0.31, 0.22), smoothstep(55.0, 58.0, dd));     // red clay
	c = mix(c, vec3(0.70, 0.66, 0.55), smoothstep(84.0, 88.0, dd));     // limestone
	c = mix(c, vec3(0.33, 0.33, 0.37), smoothstep(120.0, 124.0, dd));   // shale
	c = mix(c, vec3(0.24, 0.22, 0.24), smoothstep(156.0, 160.0, dd));   // bedrock
	float seam = 0.0;
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 10.0));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 31.2));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 56.5));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 86.0));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 122.0));
	seam += 1.0 - smoothstep(0.0, 0.7, abs(dd - 158.0));
	// thin bedding planes inside limestone and shale
	seam += 0.5 * (1.0 - smoothstep(0.0, 0.25, abs(fract(dd * 0.2) - 0.5) - 0.2)) * smoothstep(88.0, 90.0, dd) * (1.0 - smoothstep(156.0, 158.0, dd));
	return c * (1.0 - 0.22 * clamp(seam, 0.0, 1.0));
}

// ink along a mask's 0.5 contour, w0..w1 wide, but never thinner than a pixel so it holds up zoomed out
float ink_line(float v, float fw, float w0, float w1) {
	float i0 = max(w0, fw * 0.5);
	return 1.0 - smoothstep(i0, max(w1, i0 + fw), abs(v - 0.5));
}

// how much an edge faces the light, from the mask's slope (which points into the solid side)
float facing(vec2 g) {
	return length(g) > 0.01 ? dot(normalize(g), SUN) : 0.0;
}

void fragment() {
	vec2 dx = vec2(TEXTURE_PIXEL_SIZE.x, 0.0);
	vec2 dy = vec2(0.0, TEXTURE_PIXEL_SIZE.y);
	vec4 m = texture(TEXTURE, UV);      // r: solid front plane, g: underground
	vec4 ax = texture(aux_tex, UV);     // r: solid back plane, g: stone or fossil, b: hole between the planes, a: 1 - fossil
	if (m.r + m.g + ax.r + ax.g + ax.b < 0.01) {      // open air (above the ground, or no dirt at all): nothing to shade, skip the ~20 taps below
		discard;
	}
	float s = m.r;
	float lit = facing(vec2(texture(TEXTURE, UV + dx).r - texture(TEXTURE, UV - dx).r, texture(TEXTURE, UV + dy).r - texture(TEXTURE, UV - dy).r));
	vec4 axx = texture(aux_tex, UV + dx) - texture(aux_tex, UV - dx);
	vec4 axy = texture(aux_tex, UV + dy) - texture(aux_tex, UV - dy);
	vec3 fw = fwidth(vec3(s, ax.g, ax.r));
	vec2 wc = origin + UV * tsize;      // cells
	vec4 sv = surf_at(UV.x);
	float d = wc.y - sv.g * 255.0;      // cells below the original ground (< 0: the spoil mound)
	float under = wc.y - sv.r * 255.0;  // cells below the ground as it is now
	vec3 strat = strata(d + sv.b * 16.0 - 8.0);
	// (every dirt lookup up here, outside the branches, so the mipmaps see smooth derivatives)
	vec3 face = dirt(wc);
	vec3 spoil = dirt(wc * 1.35 + 7.0);
	vec3 rear = dirt(wc + cam * 0.24);

	// ---- front: the cut face
	vec3 col = mix(spoil * vec3(0.44, 0.31, 0.2), face * strat, smoothstep(-0.6, 0.4, d));
	// stones and fossils: the dirt's grain in grey or bone, lit on top, shaded below, outlined
	float st = smoothstep(0.42, 0.58, ax.g);
	if (st > 0.0) {
		vec3 stone = dot(face * DIRT_AVG, LUMA) / dot(DIRT_AVG, LUMA) * mix(BONE, STONE, smoothstep(0.4, 0.8, ax.a));
		stone *= 1.0 + 0.3 * facing(vec2(axx.g, axy.g)) * (1.0 - smoothstep(0.6, 0.9, ax.g));
		col = mix(col, stone, st);
	}
	col = mix(col, ink.rgb, ink_line(ax.g, fw.y, 0.03, 0.08) * 0.9);
	// tunnels of the back plane, seen through the dirt: dark ghosted channels (not the surface row, where aux turns to air)
	float deep = smoothstep(0.5, 1.0, m.g);
	float bo = (1.0 - smoothstep(0.32, 0.62, ax.r)) * deep;
	col = mix(col, col * 0.27 + vec3(0.012, 0.008, 0.006), bo * 0.92);
	col = mix(col, ink.rgb, ink_line(ax.r, fw.z, 0.03, 0.08) * 0.4 * deep);
	// bevel: tunnel floors catch light, ceilings fall into shade (not along the ground's top, whose cell stairs would light up)
	if (under > 2.0) {
		float rim = smoothstep(0.5, 0.56, s) * (1.0 - smoothstep(0.6, 0.9, s));
		col = lit > 0.0 ? mix(col, col * 1.45 + 0.05, rim * lit * 0.8) : mix(col, col * 0.55, rim * -lit * 0.8);
		col *= 1.0 - 0.18 * (1.0 - smoothstep(0.55, 0.95, s)) * step(0.5, s);   // soft occlusion around every hole
	}
	col *= 1.0 - 0.3 * smoothstep(25.0, 190.0, d);
	float k = ink_line(s, fw.x, 0.055, 0.1);
	vec3 front = mix(col, ink.rgb, k);
	float fa = max(smoothstep(0.47, 0.5, s), k);

	// ---- back: the rear wall of the tunnels and rooms
	float e = smoothstep(0.12, 0.5, s);     // 0 mid-tunnel, 1 at the side walls
	vec3 back = rear * strat * mix(0.44, 0.6 + 0.25 * lit, e * e);
	float sh = texture(TEXTURE, UV - 1.3 * dx - 1.9 * dy).r;    // the front dirt casts a shadow down-right
	back *= 1.0 - 0.5 * smoothstep(0.35, 0.8, sh) * (1.0 - e);
	back *= 1.0 - 0.32 * smoothstep(20.0, 190.0, d);
	// lit in the middle of a tunnel, falling off toward the walls, with a warm pool down the middle: a rounded tube
	back *= 0.8 + 0.36 * (1.0 - smoothstep(0.0, 0.42, s));
	back = mix(back, back * 1.35 + vec3(0.05, 0.03, 0.008), (1.0 - smoothstep(0.0, 0.3, s)) * 0.45 * (1.0 - smoothstep(30.0, 150.0, d)));
	back *= 1.0 - 0.28 * (1.0 - smoothstep(0.32, 0.62, ax.r)) * (1.0 - e);   // a back-plane tunnel right behind this wall
	// a hole through the rear wall into the back plane, its far rim catching the light (the hole mask is one bare texel
	// per cell: blurred a little more, so a single cell reads as a round opening, not a diamond)
	vec2 hx = 0.5 * (dx + dy);
	vec2 hy = 0.5 * (dx - dy);
	float hb = 0.25 * (texture(aux_tex, UV + hx).b + texture(aux_tex, UV - hx).b + texture(aux_tex, UV + hy).b + texture(aux_tex, UV - hy).b);
	float hole = smoothstep(0.15, 0.4, hb);
	back = mix(back, vec3(0.035, 0.025, 0.02), hole * 0.92);
	back = mix(back, back * 1.9 + 0.08, (1.0 - smoothstep(0.0, 0.12, abs(hb - 0.2))) * max(facing(vec2(axx.b, axy.b)), 0.0) * 0.6);
	float ba = (1.0 - step(0.6, s)) * smoothstep(0.4, 0.6, m.g);

	// front over back
	float a = fa + ba * (1.0 - fa);
	COLOR = vec4((front * fa + back * ba * (1.0 - fa)) / max(a, 0.0001), a);
}
"""

var colony
var _shader := Shader.new()
var _dirt: Texture2D
var _grid                   # the grid the chunks were built from (a new colony brings a new one)
var _layout := -1
var _chunks := {}           # chunk index -> {"sprite", "front", "aux", "surf"}
var _stale := {}            # chunk index -> true: rebuild when there is time (the grid reallocated its arrays)
var _cam := Vector2(INF, INF)
var _ahead_done := false    # every chunk of the world has its images built


func _ready() -> void:
	_shader.code = SHADER
	_dirt = Art.tex(DIRT)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # the masks are a texel per cell: filtered, the outlines curve


func reset() -> void:
	for k in _chunks.keys():
		_drop(k)
	_stale.clear()
	_grid = null
	_ahead_done = false


func _process(_delta: float) -> void:
	var g = colony.grid
	if g != _grid:
		reset()
		_grid = g
		_layout = g.layout
	elif g.layout != _layout:
		_layout = g.layout
		for k in _chunks:
			_stale[k] = true
	# what the colony dug since last frame: the grid repainted those images in place
	for k in g.dirty_chunks:
		if _chunks.has(k):
			_upload(k)
			_stale.erase(k)
	g.dirty_chunks.clear()
	# stream: free what is far off, build what the view needs (nearest the camera first, a few per frame)
	var span = WorldGrid.CHUNK * WorldGrid.CELL
	var far = colony.view_rect(span * FAR)
	for k in _chunks.keys():
		if (k + 1) * span < far.position.x or k * span > far.end.x:
			_drop(k)
	var near = colony.view_rect(span * NEAR)
	var k_lo = WorldGrid.chunk_of(g.sim_l())       # the world's chunks: there is no ground past its edges
	var k_hi = WorldGrid.chunk_of(g.sim_r())
	var todo := []
	for k in range(max(k_lo, floori(near.position.x / span)), min(k_hi, floori(near.end.x / span)) + 1):
		if not _chunks.has(k) or _stale.has(k):
			todo.append(k)
	var mid = colony.cam_center().x / span - 0.5
	todo.sort_custom(func(a, b): return absf(a - mid) < absf(b - mid))
	var t0 = Time.get_ticks_usec()
	var built := 0
	for k in todo.slice(0, BUILDS_PER_FRAME):
		if Time.get_ticks_usec() - t0 > BUILD_US:
			break
		if _chunks.has(k):
			_upload(k)
		else:
			_make(k)
		_stale.erase(k)
		built += 1
	# nothing left to show: build the grid's images of the next chunks out from the view, so panning finds them ready
	if built == todo.size() and not _ahead_done:
		var c0 = clampi(roundi(mid), k_lo, k_hi)
		var left := 0
		for d in range(0, k_hi - k_lo + 1):
			for k in [c0 + d, c0 - d - 1]:
				if k >= k_lo and k <= k_hi and not g.has_chunk_images(k):
					if Time.get_ticks_usec() - t0 <= BUILD_US:
						g.chunk_images(k)
					else:
						left += 1
		_ahead_done = left == 0
	var c = colony.cam_center() / WorldGrid.CELL
	if c != _cam:
		_cam = c
		for ch in _chunks.values():
			ch.sprite.material.set_shader_parameter("cam", c)


func _make(k: int) -> void:
	var g = colony.grid
	var imgs = g.chunk_images(k)
	var ch = {
		"front": ImageTexture.create_from_image(imgs[0]),
		"aux": ImageTexture.create_from_image(imgs[1]),
		"surf": ImageTexture.create_from_image(g.chunk_surf_image(k)),
	}
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("origin", Vector2(k * WorldGrid.CHUNK - WorldGrid.PAD, 0))
	mat.set_shader_parameter("tsize", Vector2(imgs[0].get_size()))
	mat.set_shader_parameter("cam", colony.cam_center() / WorldGrid.CELL)
	mat.set_shader_parameter("aux_tex", ch.aux)
	mat.set_shader_parameter("surf_tex", ch.surf)
	mat.set_shader_parameter("dirt_tex", _dirt)
	var sp := Sprite2D.new()
	sp.texture = ch.front
	sp.centered = false
	sp.region_enabled = true
	sp.region_rect = Rect2(WorldGrid.PAD, 0, WorldGrid.CHUNK, g.H)
	sp.scale = Vector2.ONE * WorldGrid.CELL
	sp.position = Vector2(k * WorldGrid.CHUNK * WorldGrid.CELL, 0)
	sp.material = mat
	add_child(sp)
	ch.sprite = sp
	_chunks[k] = ch


# Same sizes, so the textures are updated in place.
func _upload(k: int) -> void:
	var ch = _chunks[k]
	var imgs = colony.grid.chunk_images(k)
	ch.front.update(imgs[0])
	ch.aux.update(imgs[1])
	ch.surf.update(colony.grid.chunk_surf_image(k))


func _drop(k: int) -> void:
	_chunks[k].sprite.queue_free()
	_chunks.erase(k)
