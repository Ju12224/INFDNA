extends Reference
# Batches coloured triangles into one ArrayMesh, so a whole patch of static scenery (grass, flowers,
# rocks, a giant tree) is built once and then costs a single draw_mesh call per frame instead of
# hundreds of draw_circle / draw_polygon calls re-run in GDScript every frame.

const INK = Color("#15121a")

var v := PoolVector2Array()
var c := PoolColorArray()


func empty() -> bool:
	return v.size() == 0


func tri(a: Vector2, b: Vector2, d: Vector2, col: Color) -> void:
	v.append(a)
	v.append(b)
	v.append(d)
	c.append(col)
	c.append(col)
	c.append(col)


func tri_c(a: Vector2, ca: Color, b: Vector2, cb: Color, d: Vector2, cd: Color) -> void:
	v.append(a)
	v.append(b)
	v.append(d)
	c.append(ca)
	c.append(cb)
	c.append(cd)


# Quad given in order around its edge (a, b, d, e).
func quad(a: Vector2, b: Vector2, d: Vector2, e: Vector2, col: Color) -> void:
	tri(a, b, d, col)
	tri(a, d, e, col)


func quad_c(a: Vector2, ca: Color, b: Vector2, cb: Color, d: Vector2, cd: Color, e: Vector2, ce: Color) -> void:
	tri_c(a, ca, b, cb, d, cd)
	tri_c(a, ca, d, cd, e, ce)


# Star-shaped polygon filled as a fan around `center`.
func fan(center: Vector2, pts: PoolVector2Array, col: Color, col_center: Color = Color(0, 0, 0, -1)) -> void:
	var cc = col if col_center.a < 0.0 else col_center
	var n = pts.size()
	for i in n:
		tri_c(center, cc, pts[i], col, pts[(i + 1) % n], col)


func ellipse(center: Vector2, rx: float, ry: float, col: Color, segs: int = 14, rot: float = 0.0, col_center: Color = Color(0, 0, 0, -1)) -> void:
	var pts := PoolVector2Array()
	var cs = cos(rot)
	var sn = sin(rot)
	for i in segs:
		var a = TAU * i / segs
		var p = Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(center + Vector2(p.x * cs - p.y * sn, p.x * sn + p.y * cs))
	fan(center, pts, col, col_center)


# Ink outline first (slightly bigger), then the fill: the game's chunky look.
func ellipse_ink(center: Vector2, rx: float, ry: float, col: Color, ow: float = 2.5, segs: int = 14, rot: float = 0.0) -> void:
	ellipse(center, rx + ow, ry + ow, INK, segs, rot)
	ellipse(center, rx, ry, col, segs, rot)


# Irregular rounded blob (rock, leaf clump, canopy lobe): radius wobbles per vertex by a hash of `seed_v`.
func blob(center: Vector2, rx: float, ry: float, seed_v: float, jag: float, col: Color, segs: int = 12, col_center: Color = Color(0, 0, 0, -1)) -> void:
	var pts := PoolVector2Array()
	for i in segs:
		var a = TAU * i / segs
		var k = 1.0 - jag + jag * 2.0 * fmod(abs(sin(seed_v * 12.9898 + i * 78.233) * 43758.5453), 1.0)
		pts.append(center + Vector2(cos(a) * rx * k, sin(a) * ry * k))
	fan(center, pts, col, col_center)


func blob_ink(center: Vector2, rx: float, ry: float, seed_v: float, jag: float, col: Color, ow: float = 3.0, segs: int = 12, col_center: Color = Color(0, 0, 0, -1)) -> void:
	blob(center, rx + ow, ry + ow, seed_v, jag, INK, segs)
	blob(center, rx, ry, seed_v, jag, col, segs, col_center)


# Grass-like blade: base width w, curving by `lean` px toward its tip `length` px above the base.
func blade(base: Vector2, lean: float, length: float, w: float, c0: Color, c1: Color) -> void:
	var mid = base + Vector2(lean * 0.35, -length * 0.55)
	var tip = base + Vector2(lean, -length)
	var hw = w * 0.5
	var hm = w * 0.32
	var cm = c0.linear_interpolate(c1, 0.55)
	quad_c(base + Vector2(-hw, 0), c0, base + Vector2(hw, 0), c0, mid + Vector2(hm, 0), cm, mid + Vector2(-hm, 0), cm)
	tri_c(mid + Vector2(-hm, 0), cm, mid + Vector2(hm, 0), cm, tip, c1)


# Soft ground shadow: nested flattened ellipses, each a little fainter than the last.
func shadow(center: Vector2, rx: float, ry: float, col: Color = Color(0.08, 0.12, 0.05, 0.16), rings: int = 3) -> void:
	for i in rings:
		var k = 1.0 - float(i) / rings * 0.55
		ellipse(center, rx * k, ry * k, col, 12)


# Tapered strip along a polyline (branch, root, vine). widths[i] is the full width at pts[i].
func ribbon(pts: PoolVector2Array, widths: PoolRealArray, col: Color, col_end: Color = Color(0, 0, 0, -1)) -> void:
	var n = pts.size()
	if n < 2:
		return
	var ce = col if col_end.a < 0.0 else col_end
	var prev_l = Vector2()
	var prev_r = Vector2()
	var prev_c = col
	for i in n:
		var dir = (pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]).normalized()
		var nrm = Vector2(-dir.y, dir.x)
		var l = pts[i] + nrm * widths[i] * 0.5
		var r = pts[i] - nrm * widths[i] * 0.5
		var cc = col.linear_interpolate(ce, float(i) / (n - 1))
		if i > 0:
			quad_c(prev_l, prev_c, prev_r, prev_c, r, cc, l, cc)
		prev_l = l
		prev_r = r
		prev_c = cc


# One surface per 64998 vertices: a mesh with more silently loses its tail (the leaves of a big tree were drawn as dark discs), so it is cut up instead.
func build() -> ArrayMesh:
	if v.size() == 0:
		return null
	var m = ArrayMesh.new()
	var total = v.size()
	var i = 0
	while i < total:
		var j = min(total, i + 64998)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		if total > 64998:
			var vs := PoolVector2Array()
			var cs := PoolColorArray()
			for k in range(i, j):
				vs.append(v[k])
				cs.append(c[k])
			arrays[Mesh.ARRAY_VERTEX] = vs
			arrays[Mesh.ARRAY_COLOR] = cs
		else:
			arrays[Mesh.ARRAY_VERTEX] = v
			arrays[Mesh.ARRAY_COLOR] = c
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		i = j
	return m


static func hash1(x: float) -> float:
	return fmod(abs(sin(x * 12.9898) * 43758.5453), 1.0)
