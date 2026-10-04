"""The tree half of the art pipeline (called by make_art.py: make_trees / make_oaks / recolor / mist).

What it does with a tree sprite cut from the owner's pictures (kept at the picture's own size, no shrinking):
  - splits the outline from the colour. The base picture (and every seasonal recolour of it) has its drawn lines painted out with the colours
    next to them; the lines come back as two ink layers: `ink`, the owner's outline exactly as drawn (for the normal and far views), and
    `ink_close`, the same lines thinner and crisp at twice the resolution (for close views, where the drawn line would be a fat blurry band).
    The game fades `ink` out over `ink_close` as the camera zooms in, so the line keeps a sensible width on screen at every zoom;
  - paints the close-up layers: `shade` (half resolution, soft: a dome of light on every leaf clump, rounded bark, the crown's shadow on the trunk,
    darkness where the trunk meets the ground) and `detail` (twice the resolution: bark furrows that follow the grain, cracks, moss on the shaded
    foot, a few sunlit and shaded leaves on the clump rims). The game fades them in as the camera zooms in;
  - writes `sil`, the tree's silhouette in white (the game lays it over far trees in the haze colour: depth fog), the sway grid (how much of the
    picture is canopy, per grid point: the game moves the clumps of a canopy separately), the canopy box and leaf colours (for falling leaves);
  - recolours the leaves for the other seasons, makes the hazy far copies, and writes compact PNGs (one-colour layers as grey+alpha).

Needs Pillow, numpy and scipy; imagequant and pyoxipng are used for smaller files when they are installed (pip install imagequant pyoxipng).
"""
import io
import math
import os

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

LIGHT = np.array([0.62, -0.58, 0.53], np.float32)          # where the sun is: upper right, toward the viewer (image y points down)
LIGHT /= np.linalg.norm(LIGHT)
CLOSE = 2                                                    # resolution of the close-up line and detail layers, x the picture
SWAY_N = 8                                                   # the sway grid has (SWAY_N + 1) x (SWAY_N + 1) points over the picture


# ------------------------------------------------------------------ small helpers
def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def to_arrays(im):
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    return a[..., :3], a[..., 3] / 255.0


def from_arrays(rgb, alpha):
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 1) * 255.0]).round().astype(np.uint8), "RGBA")


def bleed(rgb, alpha, thresh=0.02):
    """The colour of every (nearly) clear pixel set to that of the nearest visible one, so filtering and mipmaps never pull black into the edges."""
    clear = alpha <= thresh
    if not clear.any() or clear.all():
        return rgb
    idx = ndi.distance_transform_edt(clear, return_distances=False, return_indices=True)
    return rgb[idx[0], idx[1]]


def la_image(lum, alpha):
    """A grey+alpha picture (one colour with coverage): half the memory of RGBA in the game, and a small file."""
    l = np.broadcast_to(np.asarray(lum, np.float32), alpha.shape)
    return Image.fromarray(np.dstack([np.clip(l, 0, 255), np.clip(alpha, 0, 1) * 255.0]).round().astype(np.uint8), "LA")


def resize_f(arr, size, resample=Image.BICUBIC):
    """Resize a float array (H x W) to size (w, h)."""
    return np.asarray(Image.fromarray(arr.astype(np.float32), "F").resize(size, resample))


def disk(r):
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r + 0.5


def save_png(im, path, colors=256, quant=True):
    """A compact PNG: palette-reduced with libimagequant (the flat colour art cannot be told apart), then squeezed by oxipng; both are optional,
    without them the picture is saved as it is. Soft overlays and grey+alpha layers are saved unquantized (quant=False)."""
    data = None
    if quant and im.mode == "RGBA":
        try:
            import imagequant
            q = imagequant.quantize_pil_image(im, dithering_level=0.0, max_colors=colors)
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
        # a grey+alpha picture stays one (oxipng would make it a palette, which the game loads as full RGBA: twice the memory)
        data = oxipng.optimize_from_memory(data, level=2, color_type_reduction=im.mode != "LA")
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


def recolor(im, hue_to, sat_k, val_k, val_add=0.0, center=None, sat_min=0.0):
    """Move the green of the leaves to another colour (the trunk, brown and grey, stays): the autumn and spring versions of a tree. The change is blended in by how
    green a pixel is, so the dark edge where leaves meet shadow shifts smoothly and leaves no speckle."""
    rgb, a = to_arrays(im)
    c = rgb / 255.0
    h, s, v = _rgb_to_hsv(c)
    if center is None:
        center = green_center(im)
    hw = np.clip((h - 0.13) / 0.07, 0, 1) * np.clip((0.56 - h) / 0.08, 0, 1)
    sw = np.clip((s - 0.08) / 0.16, 0, 1)
    w = hw * sw * (a >= 8 / 255.0)
    nh = (hue_to + (h - center) * 0.35) % 1.0
    ns = np.clip(s * sat_k, sat_min, 1.0)                   # (autumn leaves keep some colour even where the drawing's highlights were pale)
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
def split_lines(im, kind):
    """Take the drawn lines out of a picture. Returns a dict:
         base       the picture with its lines painted out by the colours beside them (same size, same silhouette),
         ink        coverage of the lines as drawn (H x W, 0..1): base + ink in the ink colour = the drawing,
         ink_close  coverage of the same lines, thinner, at CLOSE x the resolution, crisp,
         rgb        the ink colour.
    A "line" is ink thin enough to be a stroke; ink areas too thick to be one (deep shadow, knot holes) stay in the base. On the plain oaks every
    stroke is a line; on the textured drawings of the first sheet only the outline round the silhouette is, their inner strokes are their texture."""
    rgb, A = to_arrays(im)
    H, W = A.shape
    # the sheets have hairline see-through slits inside some lines (where two parts of the drawing meet): close them, so no line has a gap
    A = np.maximum(A, ndi.grey_closing(A, footprint=disk(2)))
    lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
    m = (lum < 14) & (A > 0.95)
    ink = rgb[m].mean(0) if m.any() else np.array([7, 5, 10.0], np.float32)
    d = np.sqrt(((rgb - ink) ** 2).sum(-1))
    K = 1.0 - smooth(d, 12.0, 38.0)                          # how much of the pixel's colour is ink
    inkb = (K > 0.5) & (A > 0.5)
    blob = ndi.binary_opening(inkb, structure=disk(6 if kind == "oak" else 5))
    blob = ndi.binary_dilation(blob, structure=disk(1)) & (K > 0.2)
    lineb = inkb & ~blob
    if kind != "oak":
        dout = ndi.distance_transform_edt(A > 0.5)
        lineb &= dout <= 8.0
    near = ndi.binary_dilation(lineb, structure=disk(3)) & ~blob
    if kind != "oak":
        near &= ndi.distance_transform_edt(A > 0.5) <= 11.0
    # the colour under each line: that of the nearest clean pixel beside it (past the anti-aliased fringe), smoothed so the fill has no seams
    clean = (A > 0.9) & (K < 0.2) & ~ndi.binary_dilation(near, iterations=1)
    if clean.any():
        idx = ndi.distance_transform_edt(~clean, return_distances=False, return_indices=True)
        F = rgb[idx[0], idx[1]]
        F = np.stack([ndi.gaussian_filter(F[..., c], 1.1) for c in range(3)], -1)
    else:
        F = rgb
    # how much of each pixel near a line is the line: the pixel is unmixed into ink and the colour under it (an anti-aliased edge pixel is part of both)
    dv = F - ink
    t = ((rgb - ink) * dv).sum(-1) / np.maximum((dv * dv).sum(-1), 400.0)
    Lr = np.where(near, np.clip(1.0 - t, 0.0, 1.0), 0.0)
    Lr = np.where(lineb, np.maximum(Lr, K), Lr)
    Lr = np.where((A < 0.5) & near, 1.0, Lr)                  # the soft outer edge of the outline is all line
    base_rgb = np.where(near[..., None], F, rgb)
    base_rgb = bleed(base_rgb, A)
    ink_full = np.clip(Lr * A, 0, 1)

    # the close-up line, at CLOSE x: the same strokes, each kept to a band round its own middle (the outline round the silhouette to its outer part)
    S = CLOSE
    W2, H2 = W * S, H * S
    L2 = np.clip(resize_f(Lr, (W2, H2)), 0, 1)
    A2 = np.clip(resize_f(A, (W2, H2)), 0, 1)
    line2 = (L2 > 0.5) & (A2 > 0.5)
    colour2 = (L2 <= 0.5) & (A2 > 0.5)
    outside2 = A2 <= 0.5
    d_col = ndi.distance_transform_edt(~colour2)              # how far into the line from the colour beside it
    dl = np.where(line2, d_col, 0.0)
    ridge = line2 & (dl >= ndi.maximum_filter(dl, size=3) - 0.5)
    if ridge.any():
        ridx = ndi.distance_transform_edt(~ridge, return_distances=False, return_indices=True)
        hw = dl[ridx[0], ridx[1]]                              # the half width of the stroke this pixel belongs to (its middle's distance)
    else:
        hw = dl
    d_out = ndi.distance_transform_edt(~outside2)
    sil = d_out <= hw + 1.5                                    # the outline band round the silhouette: no colour beyond it, only the outside
    full_w = np.where(sil, hw, 2.0 * hw)
    # the close line: half the drawn width on the plain oaks (between 1.6 and 3.4 picture px); the textured drawings keep more of their bold outline
    ratio = 0.5 if kind == "oak" else 0.7
    target = np.clip(full_w * ratio, 1.6 * S, 3.4 * S)
    thr = np.where(sil, hw - target, hw - target * 0.5)
    a2 = np.clip(d_col - thr + 0.5, 0.0, 1.0) * line2
    a2 = np.where(sil, np.minimum(a2, smooth(A2, 0.3, 0.7)), a2)
    a2 = np.clip(ndi.gaussian_filter(a2, 0.5), 0, 1) * (A2 > 0.02)
    return {"base": from_arrays(base_rgb, A), "ink": ink_full, "ink_close": a2, "rgb": ink, "K": K, "line": Lr}


# ------------------------------------------------------------------ analysing a picture
class Parts:
    """What is where in a tree picture: leaves (and moss), bark, rock, ink. `base` is the picture with its lines painted out, K the ink-ness of the original."""

    def __init__(self, base, K, line):
        self.rgb, self.A = to_arrays(base)
        self.h, self.w = self.A.shape
        c = self.rgb / 255.0
        hue, sat, val = _rgb_to_hsv(c)
        self.K = K
        self.line = line                                    # the drawn lines (painted out of the base): the clumps are still told apart by them
        self.Kb = K * (1.0 - smooth(line, 0.05, 0.4))       # ink that stays in the base (blobs, and the inner strokes of the textured drawings)
        solid = self.A > 0.5
        self.green = solid & (hue > 0.17) & (hue < 0.56) & (sat > 0.15) & (K < 0.5)      # the oaks are drawn in a dark teal
        self.rock = solid & ~self.green & (sat < 0.075) & (val > 0.22) & (K < 0.5)
        self.bark = solid & ~self.green & ~self.rock & (K < 0.5)
        self.solid = solid
        ys = np.nonzero(solid.any(1))[0]
        self.y0, self.y1 = int(ys[0]), int(ys[-1])


def _dome(parts, cap, reach):
    """Pseudo height of every leaf clump (each piece of green between outlines is a dome, highest in the middle): returns the lighting dev (+ lit, - shaded)."""
    mask = parts.green
    lab, n = ndi.label(mask)
    D = ndi.distance_transform_edt(mask)
    idx = np.arange(1, n + 1)
    dmax = np.concatenate([[1.0], ndi.maximum(D, lab, idx)]) if n else np.array([1.0])
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
    """Rounded bark: the light side of a trunk or limb brighter, the far side darker. Returns (dev, distance inside, grain angle)."""
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
    """acc <- colour with alpha a over acc (straight colour kept as a running mix)."""
    col = np.asarray(col, np.float32)
    acc_rgb[:] = acc_rgb * (1 - a[..., None]) + col * a[..., None]
    acc_a[:] = acc_a + a * (1 - acc_a)


def _noise(rng, shape, sigma):
    n = ndi.gaussian_filter(rng.standard_normal(shape).astype(np.float32), sigma)
    return n / (n.std() + 1e-6)


def _lic(theta, valid, noise, steps=18, h=1.4):
    """Line integral convolution: the noise smeared along the grain (theta, an axis, either way along it), only through `valid` pixels: long fibres."""
    H, W = noise.shape
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cx, cy = np.cos(theta).astype(np.float32), np.sin(theta).astype(np.float32)
    acc = noise.copy()
    wsum = np.ones_like(noise)
    for sgn in (1.0, -1.0):
        px, py = xx.copy(), yy.copy()
        dx, dy = cx * sgn, cy * sgn
        alive = valid.copy()
        for s in range(steps):
            ix = np.clip(np.rint(px).astype(np.int32), 0, W - 1)
            iy = np.clip(np.rint(py).astype(np.int32), 0, H - 1)
            nx, ny = cx[iy, ix], cy[iy, ix]
            flip = (nx * dx + ny * dy) < 0
            dx = np.where(flip, -nx, nx)
            dy = np.where(flip, -ny, ny)
            px = px + dx * h
            py = py + dy * h
            ix = np.clip(np.rint(px).astype(np.int32), 0, W - 1)
            iy = np.clip(np.rint(py).astype(np.int32), 0, H - 1)
            alive &= valid[iy, ix]
            w = (1.0 - s / float(steps)) * alive
            acc += ndi.map_coordinates(noise, [py, px], order=1, mode="nearest") * w
            wsum += w
    return acc / wsum


PRESETS = {
    # how much of each close-up effect a kind of picture gets: dome = light on the leaf clumps, cyl = rounded bark, bark = furrows and cracks, moss, tufts = leaves
    # on the clump rims, canopy = the crown's shadow on the bark, base = dark where it meets the ground. The oaks are plain and want all of it; the others
    # are already painted with their own bark and leaf texture, so they only get light, shadow and a few leaves.
    "oak": dict(dome=0.8, cyl=0.9, bark=1.0, moss=0.8, tufts=1.0, canopy=1.0, base=1.0),
    "moss": dict(dome=0.3, cyl=0.3, bark=0.0, moss=0.0, tufts=0.3, canopy=0.5, base=1.0),
    "acacia": dict(dome=0.3, cyl=0.35, bark=0.0, moss=0.0, tufts=0.25, canopy=0.45, base=1.0),
    "grove": dict(dome=0.3, cyl=0.35, bark=0.0, moss=0.0, tufts=0.25, canopy=0.45, base=1.0),
    "spruce": dict(dome=0.0, cyl=0.3, bark=0.0, moss=0.0, tufts=0.0, canopy=0.0, base=1.0),
    "stump": dict(dome=0.0, cyl=0.35, bark=0.0, moss=0.0, tufts=0.0, canopy=0.0, base=1.0),
    "log": dict(dome=0.0, cyl=0.3, bark=0.0, moss=0.0, tufts=0.0, canopy=0.0, base=0.8),
}


def shade_layer(parts, P, lo=0.5):
    """Soft light and shadow at `lo` x the picture: the form of the leaf clumps and the bark, the crown's shadow, the dark foot."""
    H, W = parts.h, parts.w
    cap = 0.045 * H
    inside = parts.solid & (parts.K < 0.55)
    ar = np.zeros((H, W, 3), np.float32)
    aa = np.zeros((H, W), np.float32)
    dark = np.array([6, 14, 12], np.float32)
    dev_d, Dleaf, lab = _dome(parts, cap, 1.0)
    dev_c, Dbark, theta = _cylinder(parts, 0.95)
    if P["dome"] > 0:
        sh = np.clip(-dev_d * 0.42, 0, 0.34) * P["dome"]
        li = np.clip(dev_d * 0.6 - 0.05, 0, 0.22) * P["dome"]
        _over(ar, aa, dark, sh * parts.green)
        _over(ar, aa, [214, 232, 150], li * parts.green)
    if P["cyl"] > 0:
        shb = np.clip(-dev_c * 0.75, 0, 0.5) * P["cyl"]
        lib = np.clip(dev_c * 0.9 - 0.05, 0, 0.3) * P["cyl"]
        bm = (parts.bark | parts.rock).astype(np.float32)
        _over(ar, aa, dark, shb * bm)
        _over(ar, aa, [236, 214, 170], lib * bm)
    if P["canopy"] > 0 and parts.green.any():
        # the crown's shadow falls on the bark: down and to the left, soft
        crown = ndi.binary_dilation(parts.green, iterations=2)
        sx, sy = -int(0.045 * H), int(0.06 * H)
        moved = np.roll(np.roll(crown.astype(np.float32), sy, 0), sx, 1)
        cast = ndi.gaussian_filter(moved, 0.02 * H)
        near = np.exp(-ndi.distance_transform_edt(~parts.green) / (0.018 * H))
        bm2 = (parts.bark | parts.rock).astype(np.float32)
        _over(ar, aa, [4, 10, 10], np.clip(cast * 0.42 + near * 0.26, 0, 0.55) * bm2 * P["canopy"])
    if P["base"] > 0:
        # ambient occlusion at the foot: dark where it meets the ground, fading up the trunk
        yb = parts.y1
        row = np.arange(H, dtype=np.float32)[:, None]
        ground = smooth(row, yb - 0.11 * H, yb + 1.0) * 0.6 * P["base"]
        _over(ar, aa, [8, 6, 4], ground * inside)
    # the lines were left out of the masks (they keep the clumps apart); fill their place from beside them, so nothing is missing where a thin close-up line runs
    band = (parts.line > 0.05) & parts.solid
    src = parts.solid & ~band
    if band.any() and src.any():
        idx = ndi.distance_transform_edt(~src, return_distances=False, return_indices=True)
        aa = np.where(band, aa[idx[0], idx[1]], aa)
        ar = np.where(band[..., None], ar[idx[0], idx[1]], ar)
    keep = parts.solid.astype(np.float32) * (1.0 - smooth(parts.Kb, 0.6, 0.9))
    aa *= keep
    rgb = np.where(aa[..., None] > 1e-4, ar / np.maximum(aa, 1e-4)[..., None], 0)
    rgb = bleed(rgb, aa, 1e-3)
    img = from_arrays(rgb, aa)
    return img.resize((max(2, int(W * lo)), max(2, int(H * lo))), Image.BILINEAR), Dleaf, Dbark, theta


def detail_layer(parts, P, Dleaf, Dbark, theta, rng, line_close):
    """The fine detail at CLOSE x the picture: bark furrows along the grain with sunlit lips, short cross cracks, moss on the shaded foot, leaves on the clump
    rims (lit ones upper right, shaded ones lower left). Drawn in light and dark only, so it suits every seasonal colour under it. None when there is nothing."""
    if P["bark"] <= 0 and P["moss"] <= 0 and P["tufts"] <= 0:
        return None
    H, W = parts.h, parts.w
    S = CLOSE
    HW, HH = W * S, H * S
    scale = H / 897.0 + 0.35
    dark_a = np.zeros((HH, HW), np.float32)
    light_a = np.zeros((HH, HW), np.float32)
    moss_a = np.zeros((HH, HW), np.float32)
    moss_l = np.zeros((HH, HW), np.float32)
    moss_d = np.zeros((HH, HW), np.float32)
    up = lambda arr: np.clip(resize_f(arr.astype(np.float32), (HW, HH), Image.BILINEAR), 0, None)
    yy = (np.arange(HH, dtype=np.float32) / S)[:, None]
    yf = np.clip((yy - parts.y0) / max(1.0, parts.y1 - parts.y0), 0, 1)

    if P["bark"] > 0:
        bark_m = (parts.bark & (Dbark > 2.0)).astype(np.float32)
        bm2 = up(ndi.gaussian_filter(bark_m, 0.8)) > 0.5
        # the grain at CLOSE x (the axis doubled before resizing, so it never averages across the wrap)
        c2, s2 = up(np.cos(2 * theta) + 2.0) - 2.0, up(np.sin(2 * theta) + 2.0) - 2.0
        th2 = 0.5 * np.arctan2(s2, c2)
        # furrows a few picture px apart, long along the grain (coarse noise smeared along it), and a faint fine grain between them
        n0 = _noise(rng, (HH, HW), 1.0 * S)
        fib = _lic(th2, bm2, n0, steps=26, h=1.6)
        fib = fib / (fib[bm2].std() + 1e-6)
        nf = _noise(rng, (HH, HW), 0.35 * S)
        fine = _lic(th2, bm2, nf, steps=8, h=1.2)
        fine = fine / (fine[bm2].std() + 1e-6)
        lo_n = _noise(rng, (HH, HW), 14.0 * S)
        plates = 0.55 + 0.45 * smooth(lo_n, -1.0, 1.0)            # furrows deeper in some places than others
        furrow = smooth(-fib, 0.75, 1.75) * plates
        ridge = smooth(fib, 1.0, 2.1) * plates
        # the sunlit lip of a furrow (its left wall faces the sun on the right): the furrow moved a little to the left, where it is lighter
        lip = np.clip(np.roll(smooth(-fib, 0.9, 1.75), -S, 1) - furrow, 0, 1)
        keep_b = bm2.astype(np.float32)
        dark_a += (furrow * 0.46 + smooth(-fine, 1.1, 2.2) * 0.1) * P["bark"] * keep_b
        light_a += np.clip(ridge * 0.12 + lip * 0.22, 0, 0.3) * P["bark"] * keep_b
        # short cross cracks, across the grain
        crack_im = Image.new("L", (HW, HH), 0)
        cd = ImageDraw.Draw(crack_im)
        ys, xs = np.nonzero(parts.bark & (Dbark > 4.0))
        if len(ys):
            for i in rng.choice(len(ys), size=min(int(len(ys) / 1500.0 * P["bark"]), len(ys)), replace=False):
                x, y = float(xs[i]), float(ys[i])
                L = rng.uniform(6, 16) * scale
                th = theta[int(y), int(x)] + math.pi * 0.5 + rng.uniform(-0.35, 0.35)
                x2, y2 = x + math.cos(th) * L, y + math.sin(th) * L
                mx, my = (x + x2) * 0.5 + rng.uniform(-1.2, 1.2), (y + y2) * 0.5 + rng.uniform(-1.2, 1.2)
                cd.line([(x * S, y * S), (mx * S, my * S), (x2 * S, y2 * S)], fill=int(255 * rng.uniform(0.45, 0.85)), width=max(1, int(round(rng.uniform(0.8, 1.5) * S))))
        cracks = ndi.gaussian_filter(np.asarray(crack_im).astype(np.float32) / 255.0, 0.6) * keep_b
        dark_a = np.maximum(dark_a, cracks * 0.5)

    if P["moss"] > 0:
        # moss: soft cushions low on the trunk and the root flares, more on the shaded left, a few creeping up the furrows; fine speckled texture
        bark_all = ((parts.bark | parts.rock) & (Dbark > 2.5)).astype(np.float32)
        bh = up(ndi.gaussian_filter(bark_all, 1.0))
        xx = (np.arange(HW, dtype=np.float32) / S)[None, :]
        cols = np.nonzero(parts.solid[max(0, parts.y1 - 12):parts.y1].any(0))[0]
        cx0 = float(cols.mean()) if len(cols) else W * 0.5
        left = smooth((cx0 - xx) / max(1.0, W * 0.25), -0.6, 1.0)
        low = smooth(yf, 0.55, 0.98)
        n1 = _noise(rng, (HH, HW), 12.0 * S)
        n2 = _noise(rng, (HH, HW), 3.0 * S)
        n3 = _noise(rng, (HH, HW), 0.7 * S)
        field = n1 * 0.75 + n2 * 0.3 + low * 2.8 + left * 0.5 - 2.85
        patch = smooth(field, 0.0, 0.45) * np.clip(bh, 0, 1) * smooth(yf, 0.42, 0.62) * P["moss"]
        grain = smooth(n3, -0.8, 0.9)
        d = 2 * S
        top = np.clip(patch - np.roll(patch, d, 0), 0, 1)          # the upper edge of a cushion catches the light
        bottom = np.clip(patch - np.roll(patch, -d, 0), 0, 1)      # its lower edge is in shade
        moss_a = np.clip(patch * (0.44 + 0.12 * grain), 0, 0.56)
        moss_l = np.clip(top * 0.55 + patch * smooth(n3 + n2 * 0.3, 0.9, 1.9) * 0.3, 0, 0.5)
        moss_d = np.clip(bottom * 0.4, 0, 0.4)

    if P["tufts"] > 0 and parts.green.any():
        # a few leaves on the rims of the clumps: lit ones where the rim faces the sun, shaded ones on the other side; small and soft
        lt_im = Image.new("L", (HW * 2, HH * 2), 0)
        dk_im = Image.new("L", (HW * 2, HH * 2), 0)
        lt, dk = ImageDraw.Draw(lt_im), ImageDraw.Draw(dk_im)
        k = 2 * S
        D = Dleaf
        rim = parts.green & (D > 1.5) & (D < 0.035 * H)
        ry, rx = np.nonzero(rim)
        gy, gx = np.gradient(ndi.gaussian_filter(D, 2.0))
        n_t = int(len(ry) / 330.0 * P["tufts"])
        if len(ry):
            for i in rng.choice(len(ry), size=min(n_t, len(ry)), replace=False):
                x, y = float(rx[i]), float(ry[i])
                ox, oy = -gx[int(y), int(x)], -gy[int(y), int(x)]          # outward
                gl = math.hypot(ox, oy)
                if gl < 1e-4:
                    continue
                facing = (ox * LIGHT[0] + oy * LIGHT[1]) / gl               # +1 faces the sun
                if -0.25 < facing < 0.2:
                    continue
                ang = math.atan2(oy, ox) + rng.normal(0, 0.6) + (0.5 if facing > 0 else -0.4)
                ln = rng.uniform(3.2, 6.5) * scale
                wd = ln * rng.uniform(0.3, 0.42)
                ca, sa = math.cos(ang), math.sin(ang)
                bx, by = x - ca * ln * 0.55, y - sa * ln * 0.55          # leaves point outward from inside the rim
                poly = []
                for u in np.linspace(0, 1, 7):
                    wv = wd * math.sin(math.pi * u) ** 0.8 * (1 - 0.25 * u)
                    poly.append((bx + ca * ln * u - sa * wv, by + sa * ln * u + ca * wv))
                for u in np.linspace(1, 0, 7):
                    wv = wd * math.sin(math.pi * u) ** 0.8 * (1 - 0.25 * u)
                    poly.append((bx + ca * ln * u + sa * wv, by + sa * ln * u - ca * wv))
                poly = [(px * k, py * k) for px, py in poly]
                val = int(255 * rng.uniform(0.6, 1.0) * min(1.0, abs(facing) * 1.6 + 0.2))
                (lt if facing > 0 else dk).polygon(poly, fill=val)
        lt_a = np.asarray(lt_im.resize((HW, HH), Image.BOX)).astype(np.float32) / 255.0
        dk_a = np.asarray(dk_im.resize((HW, HH), Image.BOX)).astype(np.float32) / 255.0
        light_a = np.maximum(light_a, lt_a * 0.3 * P["tufts"])
        dark_a = np.maximum(dark_a, dk_a * 0.3 * P["tufts"])

    # keep it on the picture and off the blobs of ink and the close-up line
    hm = np.clip(up(parts.A) * 1.2 - 0.2, 0, 1)
    Kh = up(1.0 - smooth(parts.Kb, 0.45, 0.8))
    keep_h = np.clip(hm, 0, 1) * np.clip(Kh, 0, 1) * (1.0 - line_close)
    acc_rgb = np.zeros((HH, HW, 3), np.float32)
    acc_a = np.zeros((HH, HW), np.float32)
    _over(acc_rgb, acc_a, [14, 10, 12], np.clip(dark_a, 0, 0.6) * keep_h)
    if P["moss"] > 0:
        _over(acc_rgb, acc_a, [70, 102, 46], moss_a * keep_h)
        _over(acc_rgb, acc_a, [30, 48, 26], moss_d * keep_h)
        _over(acc_rgb, acc_a, [136, 170, 82], moss_l * keep_h)
    _over(acc_rgb, acc_a, [240, 236, 196], np.clip(light_a, 0, 0.4) * keep_h)
    rgb = np.where(acc_a[..., None] > 1e-4, acc_rgb / np.maximum(acc_a, 1e-4)[..., None], 0)
    rgb = bleed(rgb, acc_a, 1e-3)
    return from_arrays(rgb, acc_a)


def foot_of(parts):
    """Where the tree stands: left and right end of its lowest rows, as fractions of the picture's width."""
    rows = slice(max(0, parts.y1 - 10), parts.y1 - 1)
    cols = np.nonzero(parts.solid[rows].any(0))[0]
    if len(cols) == 0:
        return [0.25, 0.75]
    return [round(float(cols[0]) / parts.w, 4), round(float(cols[-1] + 1) / parts.w, 4)]


def sway_grid(parts, sways):
    """How much each point of a (SWAY_N + 1)^2 grid over the picture moves with its leaf clump (0 the trunk and the foot, 1 the middle of the canopy)."""
    H, W = parts.h, parts.w
    n = SWAY_N
    if not sways:
        return None
    leaf = parts.green.astype(np.float32)
    if not parts.green.any():
        leaf = parts.solid.astype(np.float32) * 0.6
    blur = ndi.uniform_filter(leaf, size=(max(3, H // n), max(3, W // n)))
    rows = []
    for j in range(n + 1):
        y = min(H - 1, int(round(j * (H - 1) / float(n))))
        hk = float(smooth(np.float32(1.0 - y / float(H)), 0.22, 0.6))
        row = []
        for i in range(n + 1):
            x = min(W - 1, int(round(i * (W - 1) / float(n))))
            row.append(round(min(1.0, float(blur[y, x]) * 1.6) * hk, 2))
        rows.append(row)
    return rows


def canopy_box(parts):
    ys, xs = np.nonzero(parts.green)
    if len(ys) < 50:
        return None
    return [round(float(np.percentile(xs, 4)) / parts.w, 3), round(float(np.percentile(ys, 4)) / parts.h, 3),
            round(float(np.percentile(xs, 96)) / parts.w, 3), round(float(np.percentile(ys, 92)) / parts.h, 3)]


def leaf_rgb(im):
    rgb, a = to_arrays(im)
    h, s, v = _rgb_to_hsv(rgb / 255.0)
    m = (a > 0.9) & (s > 0.2) & (v > 0.15)
    hm = m & (((h > 0.17) & (h < 0.5)) | (h < 0.16) | (h > 0.93))
    sel = rgb[hm] if hm.sum() > 50 else rgb[m]
    return [int(round(c)) for c in np.median(sel, 0)] if len(sel) else [90, 140, 60]


# ------------------------------------------------------------------ one tree, all its files
LOOKS = {"summer": (0.31, 1.05, 1.2, 0.03), "spring": (0.22, 1.0, 1.42, 0.06), "orange": (0.07, 1.25, 1.75, 0.1), "red": (0.0, 1.35, 1.55, 0.04), "gold": (0.13, 1.2, 1.85, 0.12)}
SAT_MIN = {"orange": 0.55, "red": 0.55, "gold": 0.5}
MIST_HEIGHT = 300


def build_tree(out_dir, nm, img, leafy, kind, seed, sways=True):
    """Everything the game draws for one tree picture (already cut and trimmed, at the picture's own size): the base in each leaf look with its lines painted out,
    the two ink layers, the close-up layers, the silhouette, the sway grid, the hazy far copies. Returns (manifest entry, {file: bytes})."""
    split = split_lines(img, kind)
    base = split["base"]
    w, h = base.size
    entry = {"name": nm, "w": w, "h": h, "leafy": leafy, "looks": {}, "mist": {}}
    sizes = {}

    def put(fn, im, colors=256, quant=True):
        sizes[fn] = save_png(im, os.path.join(out_dir, fn), colors, quant)
        return fn

    # the far copies come from the picture as drawn (outline and all): they are small and hazy, and look as they always did
    small = img.resize((max(8, int(round(w * MIST_HEIGHT / float(h)))), MIST_HEIGHT), Image.LANCZOS)
    center = green_center(img)
    leaf_cols = {}
    if leafy:
        for lk, args in LOOKS.items():
            rc = recolor(base, *args, center=center, sat_min=SAT_MIN.get(lk, 0.0))
            entry["looks"][lk] = put("tree_%s_%s.png" % (nm, lk), rc)
            leaf_cols[lk] = leaf_rgb(rc)
            entry["mist"][lk] = put("mist_%s_%s.png" % (nm, lk), mist(recolor(small, *args, center=center, sat_min=SAT_MIN.get(lk, 0.0)), height=MIST_HEIGHT), 128)
        entry["file"] = entry["looks"]["summer"]
    else:
        entry["file"] = entry["looks"]["summer"] = put("tree_%s.png" % nm, base)
        leaf_cols["summer"] = leaf_rgb(base)
        entry["mist"]["summer"] = put("mist_%s.png" % nm, mist(small, height=MIST_HEIGHT), 128)
    ink_l = float(0.299 * split["rgb"][0] + 0.587 * split["rgb"][1] + 0.114 * split["rgb"][2])
    entry["ink"] = put("tree_%s_ink.png" % nm, la_image(ink_l, split["ink"]), quant=False)
    entry["ink_close"] = put("tree_%s_inkc.png" % nm, la_image(ink_l, split["ink_close"]), quant=False)
    entry["sil"] = put("tree_%s_sil.png" % nm, la_image(255.0, to_arrays(base)[1]), quant=False)
    P = dict(PRESETS.get(kind, PRESETS["oak"]))
    rng = np.random.RandomState(seed)
    parts = Parts(base, split["K"], split["line"])
    shade, Dleaf, Dbark, theta = shade_layer(parts, P)
    entry["shade"] = put("tree_%s_shade.png" % nm, shade, quant=False)
    detail = detail_layer(parts, P, Dleaf, Dbark, theta, rng, split["ink_close"])
    if detail is not None:
        entry["detail"] = put("tree_%s_detail.png" % nm, detail, quant=False)
    entry["foot"] = foot_of(parts)
    sg = sway_grid(parts, sways)
    if sg is not None:
        entry["sway"] = sg
    cb = canopy_box(parts)
    if cb is not None:
        entry["canopy"] = cb
    entry["leaf_rgb"] = leaf_cols
    entry["ink_rgb"] = [int(round(v)) for v in split["rgb"]]
    return entry, sizes
