"""The tree half of the art pipeline (called by make_art.py: make_trees / make_oaks / recolor / mist).

What it does with a tree sprite cut from the owner's pictures:
  - works at the picture's own size (no shrinking), so a zoomed-in tree is as sharp as the drawing itself;
  - thins the thick dark outline and keeps what it took away in a separate `ink` layer. The game draws that layer over the tree when the
    camera is far or normal (the owner's outline, as drawn) and fades it out as the camera zooms in (a finer line close up);
  - paints the close-up layers: `shade` (soft light and shadow, a dome of light on every leaf clump, a rounded trunk, the crown's shadow
    on the bark, darkness where the trunk meets the ground; low resolution, it is smooth) and `detail` (twice the resolution: bark grooves
    and cracks, moss, sunlit and shaded leaf tufts along the clump rims). The game fades them in as the camera zooms in;
  - recolours the leaves for the other seasons, makes the hazy far copies, and writes compact PNGs.

Needs Pillow, numpy and scipy; imagequant and pyoxipng are used for smaller files when they are installed (pip install imagequant pyoxipng).
"""
import colorsys
import io
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

LIGHT = np.array([0.62, -0.58, 0.53], np.float32)          # where the sun is: upper right, toward the viewer (image y points down)
LIGHT /= np.linalg.norm(LIGHT)


# ------------------------------------------------------------------ small helpers
def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def to_arrays(im):
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    return a[..., :3], a[..., 3] / 255.0


def from_arrays(rgb, alpha):
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255.0]).round().astype(np.uint8), "RGBA")


def save_png(im, path, colors=256, quant=True):
    """A compact PNG: palette-reduced with libimagequant (the art is flat enough that it cannot be told apart), then squeezed by oxipng;
    both are optional, without them the picture is saved as it is."""
    data = None
    if quant:
        try:
            import imagequant
            q = imagequant.quantize_pil_image(im.convert("RGBA"), dithering_level=0.0, max_colors=colors)
            b = io.BytesIO()
            q.save(b, "PNG", optimize=True)
            data = b.getvalue()
        except Exception:
            data = None
    if data is None:
        b = io.BytesIO()
        im.save(b, "PNG", optimize=True)
        data = b.getvalue()
    try:
        import oxipng
        data = oxipng.optimize_from_memory(data, level=4)
    except Exception:
        pass
    with open(path, "wb") as f:
        f.write(data)
    return len(data)


# ------------------------------------------------------------------ recolour and mist
def _rgb_to_hsv(rgb):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-9
    dd = np.where(nz, d, 1.0)
    h = np.where(nz & (mx == r), ((g - b) / dd) % 6.0, h)
    h = np.where(nz & (mx == g) & (mx != r), (b - r) / dd + 2.0, h)
    h = np.where(nz & (mx == b) & (mx != g) & (mx != r), (r - g) / dd + 4.0, h)
    s = np.where(mx > 1e-9, d / np.where(mx > 1e-9, mx, 1.0), 0.0)
    return (h / 6.0) % 1.0, s, mx


def _hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p = v * (1.0 - s)
    q = v * (1.0 - s * f)
    t = v * (1.0 - s * (1.0 - f))
    i = i.astype(int) % 6
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def green_center(im):
    """The average hue of a sprite's leaves, so the recolour keeps the spread of tones around it whatever green the picture started from."""
    rgb, a = to_arrays(im)
    h, s, v = _rgb_to_hsv(rgb / 255.0)
    m = (a > 200 / 255.0) & (h > 0.18) & (h < 0.5) & (s > 0.25)
    return float(h[m].mean()) if m.any() else 0.37


def recolor(im, hue_to, sat_k, val_k, val_add=0.0):
    """Move the green of the leaves to another colour (the trunk, brown and grey, stays): the autumn and spring versions of a tree. The change is blended in by how
    green a pixel is, so the dark edge where leaves meet shadow shifts smoothly and leaves no speckle."""
    rgb, a = to_arrays(im)
    c = rgb / 255.0
    h, s, v = _rgb_to_hsv(c)
    center = green_center(im)
    hw = np.clip((h - 0.13) / 0.07, 0, 1) * np.clip((0.56 - h) / 0.08, 0, 1)
    sw = np.clip((s - 0.08) / 0.16, 0, 1)
    w = hw * sw * (a >= 8 / 255.0)
    nh = (hue_to + (h - center) * 0.35) % 1.0
    ns = np.minimum(1.0, s * sat_k)
    nv = np.minimum(1.0, v * val_k + val_add * np.minimum(1.0, v * 3.0))
    c2 = _hsv_to_rgb(nh, ns, nv)
    out = c * (1 - w[..., None]) + c2 * w[..., None]
    out = np.floor(out * 255.0)
    return from_arrays(out, a)


def mist(im, k=0.45, height=300):
    """A small, washed-out copy for the far background: the colour pulled toward a pale blue haze."""
    w = max(8, int(im.size[0] * height / im.size[1]))
    sm = im.resize((w, height), Image.LANCZOS)
    rgb, a = to_arrays(sm)
    haze = np.array([206, 222, 230], np.float32)
    return from_arrays(rgb * (1 - k) + haze * k, a)


# ------------------------------------------------------------------ the outline
def thin_outline(im, s_in=1.1, s_out=1.0, th_in=0.84, th_out=0.68):
    """Returns (thin picture, ink layer, ink colour). The ink layer holds exactly what thinning took away (ink colour, alpha = how much), so the picture
    with the ink layer over it is the original again."""
    rgb, A = to_arrays(im)
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    m = (lum < 14) & (A > 0.95)
    ink = rgb[m].mean(0) if m.any() else np.array([7, 16, 21.0], np.float32)
    d = np.sqrt(((rgb - ink) ** 2).sum(-1))
    K = 1.0 - smooth(d, 12.0, 38.0)                         # how much of the pixel is outline ink
    K = np.where(A < 0.02, 1.0, K)                          # outside the picture counts as ink, so the silhouette is only thinned from inside
    Kb = ndi.gaussian_filter(K, s_in)
    K2 = np.minimum(smooth(Kb, th_in - 0.2, th_in + 0.12), K)
    A2 = np.minimum(smooth(ndi.gaussian_filter(A, s_out), th_out - 0.25, th_out + 0.1), A)
    # where thick ink went, the colours are taken from the nearest picture pixel that is not ink (thin dark lines stay as drawn)
    thick = smooth(ndi.maximum_filter(Kb, size=7), 0.75, 0.92)
    gone = smooth(K - K2, 0.0, 0.2) * thick
    W = (1.0 - smooth(K, 0.04, 0.2)) * A
    idx = ndi.distance_transform_edt(W < 0.6, return_distances=False, return_indices=True)
    F = rgb[idx[0], idx[1]]
    clean = rgb * (1 - gone[..., None]) + F * gone[..., None]
    out = clean * (1 - K2[..., None]) + ink * K2[..., None]
    out = np.where((K < 0.02)[..., None], rgb, out)
    o = np.maximum(np.clip(K - K2, 0, 1) * A2, np.clip(A - A2, 0, 1))
    thin = from_arrays(out, A2)
    layer = from_arrays(np.broadcast_to(ink, rgb.shape), o)
    return thin, layer, tuple(int(round(v)) for v in ink)


# ------------------------------------------------------------------ analysing a picture
class Parts:
    """What is where in a tree picture: leaves (and moss), bark, rock, ink."""

    def __init__(self, thin, ink):
        self.rgb, self.A = to_arrays(thin)
        self.h, self.w = self.A.shape
        c = self.rgb / 255.0
        hue, sat, val = _rgb_to_hsv(c)
        d = np.sqrt(((self.rgb - np.asarray(ink, np.float32)) ** 2).sum(-1))
        self.K = 1.0 - smooth(d, 12.0, 38.0)
        solid = self.A > 0.5
        self.green = solid & (hue > 0.17) & (hue < 0.5) & (sat > 0.18) & (self.K < 0.5)
        self.rock = solid & ~self.green & (sat < 0.075) & (val > 0.22) & (self.K < 0.5)
        self.bark = solid & ~self.green & ~self.rock & (self.K < 0.5)
        self.solid = solid
        ys = np.nonzero(solid.any(1))[0]
        self.y0, self.y1 = int(ys[0]), int(ys[-1])


def _dome(parts, cap, reach):
    """Pseudo height of every leaf clump (each piece of green between outlines is a dome, highest in the middle): returns the lighting dev (+ lit, - shaded)."""
    mask = parts.green
    lab, n = ndi.label(mask)
    D = ndi.distance_transform_edt(mask)
    idx = np.arange(1, n + 1)
    dmax = np.concatenate([[1.0], ndi.maximum(D, lab, idx)])
    dm = np.minimum(dmax[lab], cap)
    t = np.clip(D / np.maximum(dm, 1.0), 0, 1)
    hgt = np.sqrt(np.clip(1.0 - (1.0 - t) ** 2, 0, 1))
    hgt = ndi.gaussian_filter(hgt, 2.6)
    gy, gx = np.gradient(hgt)
    nx, ny = -gx * cap * reach, -gy * cap * reach
    nz = np.ones_like(nx)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz)
    s = (nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]) * inv
    dev = (s - LIGHT[2]) * mask
    return dev, D, lab


def _cylinder(parts, reach):
    """Rounded bark: the light side of a trunk or limb brighter, the far side darker. Returns (dev, distance inside, tangent angle)."""
    mask = parts.solid & ~parts.green               # knot holes and the outline count as wood, so the grain does not circle round them
    D = ndi.distance_transform_edt(mask)
    Ds = ndi.gaussian_filter(D, 2.0)
    wloc = ndi.gaussian_filter(ndi.maximum_filter(Ds, size=61), 8.0)
    t = np.clip(Ds / np.maximum(wloc, 4.0), 0, 1)
    gy, gx = np.gradient(ndi.gaussian_filter(D, 3.0))
    gl = np.sqrt(gx * gx + gy * gy) + 1e-6
    ux, uy = -gx / gl, -gy / gl                              # outward
    round_ = (1.0 - t) ** 1.2 * reach
    nx, ny = ux * round_, uy * round_
    nz = np.sqrt(np.clip(1.0 - nx * nx - ny * ny, 0.05, 1))
    s = nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2]
    dev = (s - LIGHT[2]) * (parts.bark | parts.rock)
    # which way the grain runs: along the limb, perpendicular to the way the distance changes
    g2y, g2x = np.gradient(Ds)
    sg = 12.0
    jxx = ndi.gaussian_filter(g2x * g2x, sg)
    jyy = ndi.gaussian_filter(g2y * g2y, sg)
    jxy = ndi.gaussian_filter(g2x * g2y, sg)
    theta = 0.5 * np.arctan2(2 * jxy, jxx - jyy) + math.pi * 0.5
    return dev, D, theta


def _over(acc_rgb, acc_a, col, a):
    """acc (premultiplied) <- colour with alpha a over acc."""
    col = np.asarray(col, np.float32)
    acc_rgb[:] = acc_rgb * (1 - a[..., None]) + col * a[..., None]
    acc_a[:] = acc_a + a * (1 - acc_a)


def _noise(rng, shape, sigma):
    n = ndi.gaussian_filter(rng.standard_normal(shape).astype(np.float32), sigma)
    return n / (n.std() + 1e-6)


def _stroke_canvas(size, ss):
    im = Image.new("L", (size[0] * ss, size[1] * ss), 0)
    return im, ImageDraw.Draw(im)


def _finish(im, ss, hi):
    """Supersampled mask -> float array at the hi-res size."""
    im = im.resize((im.size[0] // ss, im.size[1] // ss), Image.BOX) if ss > 1 else im
    return np.asarray(im).astype(np.float32) / 255.0


PRESETS = {
    # how much of each close-up effect a kind of picture gets: dome = light on the leaf clumps, cyl = rounded bark, bark = grooves and cracks, moss, tufts = leaf
    # tufts on the clump rims, canopy = the crown's shadow on the bark, base = dark where it meets the ground. The oaks are plain and want all of it; the others
    # are already painted with their own bark and leaf texture, so they only get light, shadow and a few tufts.
    "oak": dict(dome=1.0, cyl=1.0, bark=1.0, moss=0.7, tufts=1.0, canopy=1.0, base=1.0),
    "moss": dict(dome=0.55, cyl=0.35, bark=0.0, moss=0.0, tufts=0.45, canopy=0.8, base=1.0),
    "acacia": dict(dome=0.5, cyl=0.4, bark=0.0, moss=0.0, tufts=0.4, canopy=0.7, base=1.0),
    "grove": dict(dome=0.5, cyl=0.4, bark=0.0, moss=0.0, tufts=0.4, canopy=0.7, base=1.0),
    "spruce": dict(dome=0.0, cyl=0.3, bark=0.0, moss=0.0, tufts=0.0, canopy=0.0, base=1.0),
    "stump": dict(dome=0.0, cyl=0.35, bark=0.0, moss=0.0, tufts=0.0, canopy=0.0, base=1.0),
    "log": dict(dome=0.0, cyl=0.3, bark=0.0, moss=0.0, tufts=0.0, canopy=0.0, base=0.8),
}


def close_up_layers(thin, ink, kind, seed=1, ss=2, hi=2, lo=0.5):
    """The two close-up layers of one tree picture. Returns (shade at `lo` x the picture, detail at `hi` x the picture, foot).
    shade and detail are RGBA with the picture's own outline (and everything outside it) left clear."""
    P = dict(PRESETS.get(kind, PRESETS["oak"]))
    rng = np.random.RandomState(seed)
    parts = Parts(thin, ink)
    H, W = parts.h, parts.w
    area_scale = (H * W) / (746.0 * 897.0)
    cap = 0.045 * H
    inside = parts.solid & (parts.K < 0.55)

    # ---- low-resolution shade: the form of the leaves and the bark
    ar = np.zeros((H, W, 3), np.float32)
    aa = np.zeros((H, W), np.float32)
    dark = np.array([6, 14, 12], np.float32)
    warm = np.array([255, 236, 168], np.float32)
    dev_d, Dleaf, lab = _dome(parts, cap, 1.0)
    dev_c, Dbark, theta = _cylinder(parts, 0.95)
    # leaf clumps
    if P["dome"] > 0:
        sh = np.clip(-dev_d * 0.62, 0, 0.5) * P["dome"]
        li = np.clip(dev_d * 0.9 - 0.06, 0, 0.36) * P["dome"]
        _over(ar, aa, dark, sh * parts.green)
        _over(ar, aa, [214, 232, 150], li * parts.green)
    # bark: rounded
    if P["cyl"] > 0:
        shb = np.clip(-dev_c * 0.75, 0, 0.5) * P["cyl"]
        lib = np.clip(dev_c * 0.9 - 0.05, 0, 0.3) * P["cyl"]
        bm = (parts.bark | parts.rock).astype(np.float32)
        _over(ar, aa, dark, shb * bm)
        _over(ar, aa, [236, 214, 170], lib * bm)
    # the crown's shadow falls on the bark: down and to the left, soft
    if P["canopy"] > 0:
        crown = ndi.binary_dilation(parts.green | (parts.K > 0.5) & (ndi.distance_transform_edt(~parts.green) < 6), iterations=1)
        ys, xs = np.nonzero(parts.green)
        if len(ys):
            sx, sy = -int(0.045 * H), int(0.06 * H)
            moved = np.roll(np.roll(crown.astype(np.float32), sy, 0), sx, 1)
            cast = ndi.gaussian_filter(moved, 0.02 * H)
            near = np.exp(-ndi.distance_transform_edt(~parts.green) / (0.018 * H))
            bm2 = (parts.bark | parts.rock).astype(np.float32)
            _over(ar, aa, [4, 10, 10], np.clip(cast * 0.42 + near * 0.26, 0, 0.55) * bm2 * P["canopy"])
    # the foot: dark where it meets the ground
    if P["base"] > 0:
        yb = parts.y1
        row = np.arange(H, dtype=np.float32)[:, None]
        ground = smooth(row, yb - 0.11 * H, yb + 1.0) * 0.6 * P["base"]
        _over(ar, aa, [8, 6, 4], ground * inside)
    # keep off the outline and outside the picture
    keep = parts.solid.astype(np.float32) * (1.0 - smooth(parts.K, 0.2, 0.7))
    aa *= keep
    shade_full = from_arrays(np.where(aa[..., None] > 1e-4, ar / np.maximum(aa, 1e-4)[..., None], 0), aa)
    shade = shade_full.resize((max(2, int(W * lo)), max(2, int(H * lo))), Image.BILINEAR)

    # ---- high-resolution detail: grooves, cracks, moss, leaf tufts
    HW, HH = W * hi, H * hi
    S = ss
    dk_im, dk = _stroke_canvas((HW, HH), S)
    lt_im, lt = _stroke_canvas((HW, HH), S)
    mo_im, mo = _stroke_canvas((HW, HH), S)
    k = hi * S                                              # picture px -> drawing px

    if P["bark"] > 0:
        bark_m = parts.bark & (Dbark > 3)
        pts_y, pts_x = np.nonzero(bark_m)
        n_str = int(len(pts_y) / 800.0 * P["bark"])
        sel = rng.choice(len(pts_y), size=min(n_str, len(pts_y)), replace=False) if len(pts_y) else []
        for i in sel:
            x, y = float(pts_x[i]), float(pts_y[i])
            L = rng.uniform(40, 150) * (H / 897.0 + 0.4)
            wd = rng.uniform(0.7, 1.7)
            sgn = 1.0 if rng.rand() < 0.5 else -1.0
            seg = []
            px, py = x, y
            dxp, dyp = 0.0, 0.0
            ang_w = rng.uniform(-0.3, 0.3)
            steps = int(L / 2.5)
            for st in range(steps):
                ix, iy = int(px), int(py)
                if ix < 1 or iy < 1 or ix >= W - 1 or iy >= H - 1 or not bark_m[iy, ix]:
                    break
                th = theta[iy, ix]
                dx, dy = math.cos(th), math.sin(th)
                if dxp * dx + dyp * dy < 0:
                    dx, dy = -dx, -dy
                elif dxp == 0 and dyp == 0:
                    dx, dy = dx * sgn, dy * sgn
                ang_w += rng.normal(0, 0.022)
                ang_w *= 0.97
                ca, sa = math.cos(ang_w), math.sin(ang_w)
                dx, dy = dx * ca - dy * sa, dx * sa + dy * ca
                dxp, dyp = dx, dy
                seg.append((px, py))
                px += dx * 2.5
                py += dy * 2.5
            if len(seg) < 4:
                continue
            for j in range(len(seg) - 1):
                u = j / max(1, len(seg) - 2)
                wj = wd * (math.sin(math.pi * u) ** 0.6 + 0.15)
                dk.line([(seg[j][0] * k, seg[j][1] * k), (seg[j + 1][0] * k, seg[j + 1][1] * k)], fill=int(255 * rng.uniform(0.5, 0.95)), width=max(1, int(round(wj * k))))
                if rng.rand() < 0.9:
                    off = wj * 1.1 + 0.6
                    # the sunlit lip of the groove, on its right
                    lt.line([(seg[j][0] * k + off * k, seg[j][1] * k), (seg[j + 1][0] * k + off * k, seg[j + 1][1] * k)], fill=int(255 * rng.uniform(0.25, 0.6)), width=max(1, int(round(wj * 0.6 * k))))
        # short cross cracks
        for i in rng.choice(len(pts_y), size=min(int(len(pts_y) / 900.0 * P["bark"]), len(pts_y)), replace=False) if len(pts_y) else []:
            x, y = float(pts_x[i]), float(pts_y[i])
            L = rng.uniform(8, 22)
            th = theta[int(y), int(x)] + math.pi * 0.5 + rng.uniform(-0.3, 0.3)
            x2, y2 = x + math.cos(th) * L, y + math.sin(th) * L
            dk.line([(x * k, y * k), ((x + x2) / 2 * k, ((y + y2) / 2 + rng.uniform(-1.5, 1.5)) * k), (x2 * k, y2 * k)], fill=int(255 * rng.uniform(0.4, 0.8)), width=max(1, int(round(rng.uniform(0.7, 1.5) * k))))

    if P["tufts"] > 0:
        # leaf tufts: small pointed leaves along the rims of the clumps, sunlit on the upper right and shaded on the lower left, and a few inside
        D = Dleaf
        rim = parts.green & (D > 2) & (D < 0.05 * H)
        ry, rx = np.nonzero(rim)
        n_t = int(len(ry) / 210.0 * P["tufts"])
        if len(ry):
            gy, gx = np.gradient(ndi.gaussian_filter(D, 2.0))
            for i in rng.choice(len(ry), size=min(n_t, len(ry)), replace=False):
                x, y = float(rx[i]), float(ry[i])
                ox, oy = -gx[int(y), int(x)], -gy[int(y), int(x)]          # outward
                gl = math.hypot(ox, oy)
                if gl < 1e-4:
                    ang = rng.uniform(0, 2 * math.pi)
                else:
                    ang = math.atan2(oy, ox) + rng.normal(0, 0.55)
                lit = math.cos(ang) * LIGHT[0] + math.sin(ang) * LIGHT[1]
                ln = rng.uniform(4.5, 9.5) * (H / 897.0 + 0.35)
                wd = ln * rng.uniform(0.28, 0.4)
                # a pointed leaf: two arcs
                ca, sa = math.cos(ang), math.sin(ang)
                poly = []
                for u in np.linspace(0, 1, 7):
                    wv = wd * math.sin(math.pi * u) ** 0.8 * (1 - 0.2 * u)
                    poly.append((x + ca * ln * u - sa * wv, y + sa * ln * u + ca * wv))
                for u in np.linspace(1, 0, 7):
                    wv = wd * math.sin(math.pi * u) ** 0.8 * (1 - 0.2 * u)
                    poly.append((x + ca * ln * u + sa * wv, y + sa * ln * u - ca * wv))
                poly = [(px * k, py * k) for px, py in poly]
                val = int(255 * rng.uniform(0.55, 1.0))
                if lit > 0.12:
                    lt.polygon(poly, fill=val)
                elif lit < -0.3:
                    dk.polygon(poly, fill=int(val * 0.7))
        # a few bright flecks inside the clumps, like the drawn ones
        iy, ix = np.nonzero(parts.green & (D > 0.035 * H))
        if len(iy):
            for i in rng.choice(len(iy), size=min(int(len(iy) / 4200.0 * P["tufts"]), len(iy)), replace=False):
                x, y = float(ix[i]), float(iy[i])
                ln = rng.uniform(4, 8)
                ang = rng.uniform(0, math.pi)
                dx, dy = math.cos(ang) * ln * 0.5, math.sin(ang) * ln * 0.5
                lt.line([((x - dx) * k, (y - dy) * k), ((x + dx) * k, (y + dy) * k)], fill=int(255 * rng.uniform(0.35, 0.7)), width=max(1, int(round(rng.uniform(1.2, 2.2) * k))))

    dark_a = ndi.gaussian_filter(_finish(dk_im, S, hi), 0.6) * 0.5
    light_a = ndi.gaussian_filter(_finish(lt_im, S, hi), 0.6) * 0.34
    moss_a = np.zeros((HH, HW), np.float32)
    if P["moss"] > 0:
        bark_all = (parts.bark | parts.rock) & (Dbark > 2.5)
        bh = ndi.zoom(bark_all.astype(np.float32), hi, order=1)[:HH, :HW]
        yy = (np.arange(HH, dtype=np.float32) / hi)[:, None]
        xx = (np.arange(HW, dtype=np.float32) / hi)[None, :]
        yf = np.clip((yy - parts.y0) / max(1.0, parts.y1 - parts.y0), 0, 1)
        low = smooth(yf, 0.5, 0.97)
        # the shaded left side of a trunk gets more
        n1 = _noise(rng, (HH, HW), 8.0 * hi)
        n2 = _noise(rng, (HH, HW), 1.8 * hi)
        field = n1 * 0.8 + n2 * 0.16 + (low * 1.9 - 1.6) * 1.0
        patch = smooth(field, 0.1, 1.0) * bh * P["moss"]
        grain = smooth(n2 + 0.25, -0.4, 0.5)
        moss_a = np.clip(patch * (0.45 + 0.25 * grain), 0, 0.55)
        moss_lit = patch * smooth(_noise(rng, (HH, HW), 1.1 * hi) + n1 * 0.2, 0.7, 1.6) * 0.6
    ink_keep = None
    # mask by the picture: nothing on the outline or outside it
    hm = np.asarray(thin.resize((HW, HH), Image.BICUBIC).getchannel("A")).astype(np.float32) / 255.0
    Kh = ndi.zoom(1.0 - smooth(parts.K, 0.2, 0.7), hi, order=1)[:HH, :HW]
    keep_h = np.clip(hm * 1.2 - 0.2, 0, 1) * Kh
    acc_rgb = np.zeros((HH, HW, 3), np.float32)
    acc_a = np.zeros((HH, HW), np.float32)
    _over(acc_rgb, acc_a, [10, 8, 12], dark_a * keep_h)
    if P["moss"] > 0:
        # moss in two greens
        mcol = np.array([64, 92, 46], np.float32)
        _over(acc_rgb, acc_a, mcol, moss_a * keep_h)
        _over(acc_rgb, acc_a, [98, 132, 66], np.clip(moss_lit, 0, 0.4) * keep_h)
    _over(acc_rgb, acc_a, [236, 236, 176], light_a * keep_h)
    detail = from_arrays(np.where(acc_a[..., None] > 1e-4, acc_rgb / np.maximum(acc_a, 1e-4)[..., None], 0), acc_a)

    foot = foot_of(parts)
    if P["bark"] <= 0 and P["moss"] <= 0 and P["tufts"] <= 0:
        detail = None                       # nothing to add to the picture's own texture
    return shade, detail, foot


def foot_of(parts):
    """Where the tree stands: left and right end of its lowest rows, as fractions of the picture's width, and how high the lowest row is."""
    rows = slice(max(0, parts.y1 - 10), parts.y1 - 1)
    cols = np.nonzero(parts.solid[rows].any(0))[0]
    if len(cols) == 0:
        return [0.25, 0.75]
    return [round(float(cols[0]) / parts.w, 4), round(float(cols[-1] + 1) / parts.w, 4)]


# ------------------------------------------------------------------ one tree, all its files
LOOKS = {"summer": (0.31, 1.05, 1.2, 0.03), "spring": (0.22, 1.0, 1.42, 0.06), "orange": (0.07, 1.25, 1.75, 0.1), "red": (0.0, 1.35, 1.55, 0.04), "gold": (0.13, 1.2, 1.85, 0.12)}
MIST_HEIGHT = 300


def build_tree(out_dir, nm, img, leafy, kind, seed):
    """Everything the game draws for one tree picture (already cut and trimmed, at the picture's own size): the sprite in each leaf look with the thinned
    outline, the ink layer that gives the outline back, the two close-up layers, the hazy far copies. Returns the manifest entry."""
    thin, ink_layer, ink = thin_outline(img)
    w, h = thin.size
    entry = {"name": nm, "w": w, "h": h, "leafy": leafy, "looks": {}, "mist": {}}
    sizes = {}

    def put(fn, im, colors=256):
        sizes[fn] = save_png(im, os.path.join(out_dir, fn), colors)
        return fn

    # the far copies come from the picture as drawn (outline and all): they are small and hazy, and look as they always did
    small_h = MIST_HEIGHT
    small = img.resize((max(8, int(round(w * small_h / float(h)))), small_h), Image.LANCZOS)
    if leafy:
        for lk, args in LOOKS.items():
            entry["looks"][lk] = put("tree_%s_%s.png" % (nm, lk), recolor(thin, *args))
            entry["mist"][lk] = put("mist_%s_%s.png" % (nm, lk), mist(recolor(small, *args), height=small_h), 128)
        entry["file"] = entry["looks"]["summer"]
    else:
        entry["file"] = entry["looks"]["summer"] = put("tree_%s.png" % nm, thin)
        entry["mist"]["summer"] = put("mist_%s.png" % nm, mist(small, height=small_h), 128)
    entry["ink"] = put("tree_%s_ink.png" % nm, ink_layer, 64)
    shade, detail, foot = close_up_layers(thin, ink, kind, seed=seed)
    entry["shade"] = put("tree_%s_shade.png" % nm, shade)
    if detail is not None:
        entry["detail"] = put("tree_%s_detail.png" % nm, detail)
    entry["foot"] = foot
    entry["ink_rgb"] = list(ink)
    return entry, sizes
