#!/usr/bin/env python3
"""Cut the owner's ANT PART KIT sheets (art_src/antkit_*.png) into single transparent PNGs for the game.

The sheets come as RGB pictures on a BLACK background (the artist's cut-out was flattened onto black): thick near-black ink outline, a
grey/red/yellowish JPEG-block halo hugging the outside of the ink, and pure black beyond that.  Brightness alone cannot tell the ink from the
background, so the matte is built from the inside out:
  1. the bright fill of the drawing (eroded so the thin halo dies, then grown back inside the lenient bright mask),
  2. the ink outline: grown out from that fill through dark pixels, never farther than the ink is thick, so the halo outside it is left out,
  3. holes filled (eyes are dark discs inside the head; their glints and facets survive because the whole disc is kept),
  4. a soft edge (about one pixel of alpha ramp) with the outer ring of ink repainted flat ink colour, so no grey halo can show on any background.
Then every sheet is split into its pieces (connected components, merged / clipped by hand-tuned boxes where a piece is several islands or
two pieces touch), each trimmed to its alpha bounding box, shrunk to at most MAXSIDE px on the long side, and saved in content/art/antkit/.
antkit_manifest.json lists each piece with its size and suggested hinge; full-body sprites also get nose-to-tail length and foot point.

Needs Pillow only:  python3 tools/art/make_antkit.py [--contact PATH]   (PATH: write a verification contact sheet there)
Does not import or touch make_art.py (that script owns art_manifest.json and the other creature art).
"""
import json
import os
import sys
from collections import deque

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "antkit")
MANIFEST = os.path.join(ART, "antkit_manifest.json")
INK = (21, 18, 26)          # the house outline colour (same as make_art.py)
MAXSIDE = 256               # longest side of any saved piece
PAD = 2                     # transparent border kept round every piece

# sheet -> {file, ink: how thick the outline is on that sheet (px beyond the bright fill)}
SHEETS = {
    "heads_a": {"file": "antkit_heads_a.png", "ink": 8},
    "heads_b": {"file": "antkit_heads_b.png", "ink": 9},
    "parts_a": {"file": "antkit_parts_a.png", "ink": 7},
    "parts_b": {"file": "antkit_parts_b.png", "ink": 5},
    "full": {"file": "antkit_full.png", "ink": 5},
}


# ---------------------------------------------------------------------------------------------------------------- matte

def _mx(im):
    return ImageChops.lighter(ImageChops.lighter(im.getchannel("R"), im.getchannel("G")), im.getchannel("B"))


def _binary(chan, lo, hi=255):
    return chan.point(lambda v: 255 if lo <= v <= hi else 0)


def reconstruct(seed, mask):
    """Everything in `mask` that is connected to `seed` (geodesic dilation until nothing changes)."""
    cur = seed
    while True:
        nxt = ImageChops.darker(cur.filter(ImageFilter.MaxFilter(3)), mask)
        if ImageChops.difference(nxt, cur).getbbox() is None:
            return cur
        cur = nxt


def _cross(m):
    r = m
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        r = ImageChops.lighter(r, ImageChops.offset(m, dx, dy))
    return r


def _step(m, i):
    """One round-ish growth step (plus-shaped and square steps alternate); on a label image the larger label wins a contested pixel."""
    return _cross(m) if i % 2 == 0 else m.filter(ImageFilter.MaxFilter(3))


def grow_in(seed, allowed, n):
    """Grow `seed` by n px but only through pixels of `allowed`."""
    cur = seed
    allowed = ImageChops.lighter(seed, allowed)
    for i in range(n):
        cur = ImageChops.darker(_step(cur, i), allowed)
    return cur


def fill_holes(mask):
    """Close every hole of a mask (anything not reachable from its (0, 0) corner, which must be background)."""
    inv = ImageChops.invert(mask)
    ImageDraw.floodfill(inv, (0, 0), 128)
    return ImageChops.invert(inv.point(lambda v: 255 if v == 128 else 0))


def _flanked(ink_ok, reach):
    """Pixels with ink on both sides of them (along a row, a column or a diagonal, within `reach` px): the thin light stripe of an antenna."""
    out = Image.new("L", ink_ok.size, 0)
    for dx, dy in ((1, 0), (0, 1), (1, 1), (1, -1)):
        pos = Image.new("L", ink_ok.size, 0)
        neg = Image.new("L", ink_ok.size, 0)
        for k in range(2, reach + 1):
            pos = ImageChops.lighter(pos, ImageChops.offset(ink_ok, -k * dx, -k * dy))
            neg = ImageChops.lighter(neg, ImageChops.offset(ink_ok, k * dx, k * dy))
        out = ImageChops.lighter(out, ImageChops.darker(pos, neg))
    return out


def label_pixels(mask):
    """Connected pieces (8-neighbour) of a mask, every pixel: [(area, cx, cy, (x0, y0, x1, y1), pts)], pts as flat (x, y) tuples."""
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    comps = []
    for y0 in range(h):
        for x0 in range(w):
            if px[x0, y0] and not seen[y0 * w + x0]:
                q = deque([(x0, y0)])
                seen[y0 * w + x0] = 1
                pts = []
                while q:
                    cx, cy = q.popleft()
                    pts.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                comps.append({"area": len(pts), "cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys),
                              "box": (min(xs), min(ys), max(xs) + 1, max(ys) + 1), "pts": pts})
    return comps


def _beige(avg):
    """Is this (mean) colour that of the drawing -- warm beige / brown / cream -- rather than halo noise (neutral grey, olive, yellow-green)?"""
    r, g, b = avg
    return 11 <= r - g <= 45 and 0 <= g - b <= 45 and (r - g) >= 0.5 * (g - b)


def _reddish(avg):
    r, g, b = avg
    return (r - g) > 1.8 * (g - b) + 4


def _inside(region, x, y):
    """Is the point in the region: a box (x0, y0, x1, y1) or a polygon [(x, y), ...]?"""
    if len(region) == 4 and not isinstance(region[0], (tuple, list)):
        return region[0] <= x < region[2] and region[1] <= y < region[3]
    n = len(region)
    ins = False
    j = n - 1
    for i in range(n):
        xi, yi = region[i]
        xj, yj = region[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / float(yj - yi) + xi:
            ins = not ins
        j = i
    return ins


class Sheet:
    """One sheet: the drawing's bright fill, its islands, and the ink mask grown round them."""

    def __init__(self, key, fill_lo=100, erode=3, lenient_lo=56, dark_lo=0, dark_erode=9, ink_hi=52, thin_reach=9):
        spec = SHEETS[key]
        self.key = key
        self.ink = spec["ink"]
        self.im = Image.open(os.path.join(SRC, spec["file"])).convert("RGB")
        self.size = self.im.size
        L = self.im.convert("L")
        self.L = L
        ink_ok = _binary(_mx(self.im), 4, ink_hi)
        self.ink_ok = ink_ok
        bright = _binary(L, fill_lo)
        core = bright.filter(ImageFilter.MinFilter(erode))
        if thin_reach:
            # thin light stripes (antennae seen in the ink) are too narrow to survive the erosion: keep the bright pixels that have ink on both sides
            core = ImageChops.lighter(core, ImageChops.darker(bright, _flanked(ink_ok, thin_reach)))
        # the shaded far-side legs and the like are mid-dark brown (above the outline's near-black): thick dark regions are fill too (the erosion
        # is wide enough to kill the 8x8 blocks of JPEG halo, which are about as bright)
        if dark_lo:
            core = ImageChops.lighter(core, _binary(L, dark_lo).filter(ImageFilter.MinFilter(dark_erode)))
        self.fill = reconstruct(core, _binary(L, lenient_lo))
        self.comps = label_pixels(self.fill)
        px = self.im.load()
        for c in self.comps:
            # specks of halo / JPEG noise: small islands that are not the beige-brown-cream of the drawing (olive, red, grey)
            n = len(c["pts"])
            avg = [sum(px[x, y][k] for (x, y) in c["pts"]) / n for k in range(3)]
            c["junk"] = c["area"] < 1500 and (not _beige(avg) or (_reddish(avg) and self._thin(c)))

    @staticmethod
    def _thin(c):
        """Is the island only a few px wide (it vanishes under two 3x3 erosions)?  Edge lines of the halo are; parts of the drawing seldom are."""
        x0, y0, x1, y1 = c["box"]
        m = Image.new("L", (x1 - x0 + 6, y1 - y0 + 6), 0)
        p = m.load()
        for (x, y) in c["pts"]:
            p[x - x0 + 3, y - y0 + 3] = 255
        return m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MinFilter(3)).getbbox() is None

    def pick(self, regions, min_area=60, drop=()):
        """Indices of the real fill islands (not halo specks) whose centre lies in any of the regions (box or polygon) and in none of `drop`."""
        out = []
        for i, c in enumerate(self.comps):
            if c["area"] < min_area or c["junk"]:
                continue
            if any(_inside(r, c["cx"], c["cy"]) for r in drop):
                continue
            if any(_inside(r, c["cx"], c["cy"]) for r in regions):
                out.append(i)
        return out

    def owners(self, groups, min_area=60):
        """Label image: piece number (1..) on every pixel that belongs to a piece (its fill plus `ink` px of outline grown all round it);
        254 = islands that belong to no piece (dust) -- they still take their share of room so they cannot be swallowed by a neighbour.
        groups: list of lists of island indices.  Pieces grow into their outline at the same pace, so touching outlines are shared fairly."""
        lab = Image.new("L", self.size, 0)
        lp = lab.load()
        for c in self.comps:
            if c["area"] >= min_area and not c["junk"]:
                for (x, y) in c["pts"]:
                    lp[x, y] = 254
        for gi, g in enumerate(groups):
            for ci in g:
                for (x, y) in self.comps[ci]["pts"]:
                    lp[x, y] = gi + 1
        for i in range(self.ink):
            grown = _step(lab, i)
            todo = lab.point(lambda v: 255 if v == 0 else 0)
            lab = Image.composite(grown, lab, todo)
        return lab


# ------------------------------------------------------------------------------------------------------------- one piece

def _poly_mask(size, poly, offset=(0, 0)):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([(x - offset[0], y - offset[1]) for (x, y) in poly], fill=255)
    return m


def ellipse_mask(size, cx, cy, rx, ry):
    """A smooth filled ellipse on a sheet-sized mask (drawn 4x and shrunk, so its edge is not stepped)."""
    k = 4
    big = Image.new("L", (size[0], size[1]), 0)
    bb = big.crop((int(cx - rx - 8), int(cy - ry - 8), int(cx + rx + 8), int(cy + ry + 8)))
    bb = bb.resize((bb.size[0] * k, bb.size[1] * k))
    ImageDraw.Draw(bb).ellipse((8 * k, 8 * k, (2 * rx + 8) * k, (2 * ry + 8) * k), fill=255)
    bb = bb.resize((bb.size[0] // k, bb.size[1] // k), Image.LANCZOS).point(lambda v: 255 if v > 127 else 0)
    big.paste(bb, (int(cx - rx - 8), int(cy - ry - 8)))
    return big


def piece_image(sh, lab, pid, opts, mask=None):
    """RGBA crop for piece number pid: the owned pixels, holes closed (eyes etc.), outline smoothed and repainted flat ink at the very edge.
    Returns (RGBA image, (x, y) of its top-left corner on the sheet)."""
    m = mask if mask is not None else lab.point(lambda v: 255 if v == pid else 0)
    bb = m.getbbox()
    if bb is None:
        return None, None
    pad = 14
    box = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(sh.size[0], bb[2] + pad), min(sh.size[1], bb[3] + pad))
    m = m.crop(box)
    rgb = sh.im.crop(box)
    near = sh.fill.crop(box).filter(ImageFilter.MaxFilter(5))             # within 2 px of the bright fill
    for (x0, y0, x1, y1) in opts.get("erase", ()):
        ImageDraw.Draw(m).rectangle((x0 - box[0], y0 - box[1], x1 - box[0], y1 - box[1]), fill=0)
    if opts.get("clip"):
        m = ImageChops.darker(m, _poly_mask(m.size, opts["clip"], box[:2]))
    # a light closing so thin gaps in the outline (between the fill islands of one piece) do not stay open
    if opts.get("close", 1):
        r = opts.get("close", 1)
        m = m.filter(ImageFilter.MaxFilter(2 * r + 1)).filter(ImageFilter.MinFilter(2 * r + 1))
    m0 = m
    # holes: dark pupils and the like stay (they are part of the drawing); empty background trapped between outlines does not
    mode = opts.get("holes", "auto")
    if mode != "none":
        filled = fill_holes(m)
        holes = ImageChops.subtract(filled, m)
        if mode == "all":
            m = filled
        else:
            lum = sh.L.crop(box)
            lp = lum.load()
            for c in label_pixels(holes):
                vals = [lp[x, y] for (x, y) in c["pts"]]
                mean = sum(vals) / len(vals)
                if c["area"] < 120 or mean >= opts.get("hole_mean", 6.0):
                    hm = Image.new("L", m.size, 0)
                    hp = hm.load()
                    for (x, y) in c["pts"]:
                        hp[x, y] = 255
                    m = ImageChops.lighter(m, hm)
    # smooth the outline: blur the hard mask and cut again a little on the generous side (keeps spike tips, drops pixel noise)
    m = m.filter(ImageFilter.GaussianBlur(1.1)).point(lambda v: 255 if v > 105 else 0)
    # leave out dust islands that were never part of the piece's picture
    min_island = opts.get("min_island", 300)
    if min_island:
        keep = Image.new("L", m.size, 0)
        kp = keep.load()
        for c in label_pixels(m):
            if c["area"] >= min_island:
                for (x, y) in c["pts"]:
                    kp[x, y] = 255
        m = keep
    # the outer 3 px ring (away from the bright fill) is repainted flat ink: no grey halo, no JPEG noise on the edge; inside the outline band any
    # pixel brighter than ink (halo, olive / red / grey noise: the bright fill itself is never out here) is repainted too
    inner = m.filter(ImageFilter.MinFilter(7))
    ring = ImageChops.subtract(ImageChops.subtract(m, inner), near)
    noisy = ImageChops.darker(ImageChops.subtract(m0, near), _binary(sh.L.crop(box), 30))
    if not opts.get("noisy", True):
        noisy = Image.new("L", m.size, 0)
    ring = ImageChops.lighter(ring, noisy)
    rgb = Image.composite(Image.new("RGB", rgb.size, INK), rgb, ring)
    a = m.filter(ImageFilter.GaussianBlur(0.8))
    a = a.point(lambda v: 0 if v < 40 else (255 if v > 215 else int((v - 40) * 255 / 175)))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out, box[:2]


def trim(im, pad=PAD):
    bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bb is None:
        return im
    bb = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(im.size[0], bb[2] + pad), min(im.size[1], bb[3] + pad))
    return im.crop(bb)


def shrink(im, maxside=MAXSIDE):
    w, h = im.size
    k = min(1.0, maxside / float(max(w, h)))
    if k >= 1.0:
        return im, 1.0
    return im.resize((max(1, int(round(w * k))), max(1, int(round(h * k)))), Image.LANCZOS), k


# --------------------------------------------------------------------------------------------------------------- catalogue
# Every piece: name, kind, where it sits on its sheet (boxes: fill islands whose centre is inside belong to it; earlier entries win), the
# hinge rule, and options (holes / close / min_island / clip / erase / drop).  Pieces that appear on several sheets are taken once, from the
# sheet that has the cleanest, largest drawing (the other sheets hold the same designs smaller or more crowded).

def P(name, kind, boxes, pivot="center", **opts):
    if boxes and isinstance(boxes[0], (int, float)):
        boxes = [boxes]
    boxes = list(boxes)
    d = {"name": name, "kind": kind, "boxes": list(boxes), "pivot": pivot}
    d.update(opts)
    return d


CATALOGUE = {
    # four heads with antennae (closed little mandibles on the face) and four separate mandible pairs
    "heads_a": [
        P("head_1", "head", [(20, 170, 375, 700), (375, 170, 420, 330)], "neck"),
        P("head_2", "head", [(376, 170, 780, 330), (376, 330, 712, 712)], "neck"),
        P("head_3", "head", [(712, 330, 1136, 704), (880, 170, 1136, 330)], "neck"),
        P("head_4", "head", [(1086, 330, 1440, 725), (1200, 185, 1440, 330)], "neck"),
        P("mandible_1_l", "mandible", (30, 790, 172, 985), "top"),
        P("mandible_1_r", "mandible", (172, 790, 310, 985), "top"),
        P("mandible_2_l", "mandible", (360, 730, 550, 1010), "top"),
        P("mandible_2_r", "mandible", (550, 745, 700, 1010), "top"),
        P("mandible_3_l", "mandible", (730, 730, 910, 1020), "top"),
        P("mandible_3_r", "mandible", (910, 730, 1075, 1040), "top"),
        P("mandible_4_l", "mandible", (1085, 740, 1283, 1010), "top"),
        P("mandible_4_r", "mandible", (1283, 740, 1430, 1000), "top"),
    ],
    # four heads with antennae and open mandibles, four mandible sets
    "heads_b": [
        P("head_5", "head", (20, 200, 402, 530), "neck"),
        P("head_6", "head", (402, 200, 760, 565), "neck"),
        P("head_7", "head", (760, 225, 1128, 555), "neck"),
        P("head_8", "head", (1128, 140, 1515, 580), "neck"),
        P("mandible_5_l", "mandible", (60, 685, 190, 870), "top"),
        P("mandible_5_r", "mandible", (200, 685, 305, 855), "top"),
        P("mandible_6_l", "mandible", (340, 600, 560, 910), "top"),
        P("mandible_6_r", "mandible", (560, 600, 760, 900), "top"),
        P("mandible_7_l", "mandible", (780, 610, 950, 945), "top"),
        P("mandible_7_r", "mandible", (950, 610, 1120, 915), "top"),
        P("mandible_8_l", "mandible", (1130, 620, 1330, 900), "top"),
        P("mandible_8_r", "mandible", (1330, 620, 1490, 880), "top"),
    ],
    # abdomens, antennae and wings (the cleanest, largest drawings of them)
    "parts_a": [
        P("abdomen_1", "abdomen", (770, 50, 940, 310), "top_right"),
        P("abdomen_2", "abdomen", (940, 40, 1055, 320), "top_right"),
        P("abdomen_3", "abdomen", (1055, 50, 1214, 316), "top_right"),
        P("abdomen_4", "abdomen", (1214, 46, 1370, 332), "top_right"),
        P("abdomen_5", "abdomen", (1374, 30, 1515, 340), "top_right"),
        P("antenna_1_l", "antenna", (1120, 366, 1325, 540), "bottom_right"),
        P("antenna_1_r", "antenna", (1335, 360, 1518, 545), "bottom_left"),
        P("antenna_2_l", "antenna", (1125, 550, 1336, 770), "bottom_right"),
        P("antenna_2_r", "antenna", (1336, 550, 1518, 770), "bottom_left"),
        P("wing_1_fore", "wing", (50, 690, 580, 812), "left"),
        P("wing_1_hind", "wing", (50, 812, 580, 985), "left"),
        P("wing_2_fore", "wing", (630, 690, 1130, 815), "left"),
        P("wing_2_hind", "wing", (630, 815, 1130, 985), "left"),
    ],
    # thoraxes, legs, spines, horns, eyes, fur tufts and odd small pieces
    "parts_b": [
        P("thorax_1", "thorax", (30, 20, 238, 235), "center"),
        P("thorax_2", "thorax", (238, 20, 440, 235), "center"),
        P("thorax_3", "thorax", (440, 20, 635, 235), "center"),
        P("thorax_4", "thorax", (635, 20, 830, 235), "center"),
        P("leg_1", "leg", (10, 225, 162, 522), "top"),
        P("leg_2", "leg", (162, 225, 312, 522), "top"),
        P("leg_3", "leg", (312, 225, 468, 522), "top"),
        P("leg_4", "leg", (468, 225, 625, 522), "top"),
        P("leg_5", "leg", (625, 225, 800, 522), "top"),
        P("leg_6", "leg", (800, 225, 965, 528), "top"),
        P("antenna_3_l", "antenna", [(970, 275, 1142, 408), (1094, 408, 1142, 470)], "top_left"),
        P("antenna_3_r", "antenna", (970, 408, 1094, 592), "top_left"),
        P("antenna_4_l", "antenna", (1145, 265, 1372, 365), "bottom_right"),
        P("antenna_4_r", "antenna", (1372, 265, 1528, 418), "top_left"),
        P("antenna_5_l", "antenna", [(1140, 350, 1345, 452), (1280, 452, 1345, 520)], "top_left"),
        P("antenna_5_r", "antenna", [(1105, 452, 1280, 592), (1280, 520, 1330, 592)], "top_right"),
        P("antenna_6_r", "antenna", (1345, 400, 1522, 612), "top_left"),
        P("sting_1", "misc", (8, 728, 122, 998), "top"),
        P("horn_1", "spine", (122, 730, 226, 998), "bottom"),
        P("horn_2", "spine", (226, 760, 306, 893), "bottom"),
        P("horn_3", "spine", (226, 893, 372, 1000), "left"),
        P("horn_4", "spine", (306, 715, 435, 925), "bottom"),
        P("frill_1", "misc", (360, 835, 540, 995), "top"),
        P("plate_1", "misc", (430, 712, 604, 862), "center"),
        P("plate_2", "misc", (604, 730, 802, 872), "center"),
        P("spine_1", "spine", (562, 852, 830, 1012), "bottom"),
        P("spine_2", "spine", [[(778, 715), (1062, 715), (1062, 885), (1000, 872), (840, 812), (778, 812)]], "bottom"),
        P("spine_3", "spine", (942, 592, 1146, 782), "bottom"),
        P("spine_4", "spine", (1146, 580, 1302, 778), "bottom"),
        P("spine_5", "spine", (1040, 780, 1185, 895), "bottom"),
        P("spine_6", "spine", (1000, 890, 1182, 995), "bottom"),
        P("spine_7", "spine", (1182, 850, 1312, 968), "bottom"),
        P("plate_3", "misc", (1188, 740, 1312, 835), "center"),
        P("egg_sac_1", "egg", [[(822, 812), (1000, 812), (1000, 995), (822, 995)]], "center"),
        # the two eyes are dark balls on the black sheet (only their glints and facets are bright): cut as ellipses, whole
        P("eye_1", "eye", [], "center", ellipse=(1377.5, 820, 43.5, 49), holes="none", noisy=False, min_island=0),
        P("eye_2", "eye", [], "center", ellipse=(1477, 820, 47, 50), holes="none", noisy=False, min_island=0),
        P("fur_1", "fur", (1290, 595, 1415, 755), "bottom"),
        P("fur_2", "fur", (1415, 605, 1525, 758), "bottom"),
        P("fur_3", "fur", (1312, 878, 1440, 998), "center"),
        P("fur_4", "fur", (1440, 880, 1528, 995), "center"),
    ],
    # full-body sprites, brood, and the pale translucent-looking wings that go with the winged one
    "full": [
        P("queen_full", "body", [(0, 0, 640, 310)], "feet"),
        P("alate_full", "body", [(685, 0, 1100, 235), (685, 235, 1040, 310)], "feet"),
        P("soldier_full", "body", [(1040, 235, 1345, 310), (1100, 60, 1345, 235)], "feet"),
        P("worker_full", "body", (1345, 150, 1520, 300), "feet"),
        P("egg_cluster", "egg", (15, 330, 235, 480), "center"),
        P("larva_1", "brood", (240, 325, 380, 470), "center"),
        P("larva_2", "brood", (390, 320, 615, 475), "center"),
        P("pupa_1", "brood", (615, 295, 805, 475), "center"),
        P("worker_small_full", "body", (805, 340, 1035, 475), "feet"),
        P("pupa_2", "brood", (1045, 315, 1250, 480), "center"),
        P("pupa_3", "brood", (1250, 315, 1515, 480), "center"),
        P("wing_3_fore", "wing", (1200, 775, 1520, 885), "left"),
        P("wing_3_hind", "wing", (1200, 885, 1520, 965), "left"),
    ],
}


def assign_debug(sh, groups, names, path):
    """Debug picture: every fill island coloured by the piece it was given to (red = left over and big enough to matter)."""
    import colorsys
    img = sh.im.convert("RGB").point(lambda v: v // 3)
    px = img.load()
    for gi, g in enumerate(groups):
        r, gg, b = colorsys.hsv_to_rgb((gi * 0.137) % 1.0, 0.8, 1.0)
        col = (int(r * 255), int(gg * 255), int(b * 255))
        for ci in g:
            for (x, y) in sh.comps[ci]["pts"]:
                px[x, y] = col
    taken = set(ci for g in groups for ci in g)
    for ci, c in enumerate(sh.comps):
        if ci not in taken and c["area"] >= 60:
            for (x, y) in c["pts"]:
                px[x, y] = (255, 0, 0)
    d = ImageDraw.Draw(img)
    f = ImageFont.load_default()
    for gi, g in enumerate(groups):
        if g:
            cx = sum(sh.comps[ci]["cx"] for ci in g) / len(g)
            cy = sum(sh.comps[ci]["cy"] for ci in g) / len(g)
            d.text((cx - 20, cy), names[gi], fill=(255, 255, 255), font=f)
    img.save(path)


# ---------------------------------------------------------------------------------------------------------------- hinges

def _opaque_points(im, thr=128):
    a = im.getchannel("A").point(lambda v: 255 if v > thr else 0)
    px = a.load()
    w, h = a.size
    return [(x, y) for y in range(h) for x in range(w) if px[x, y]]


DIRS = {"top": (0, -1), "bottom": (0, 1), "left": (-1, 0), "right": (1, 0), "top_left": (-1, -1), "top_right": (1, -1),
        "bottom_left": (-1, 1), "bottom_right": (1, 1)}


def hinge(im, rule, frac=0.10):
    """Suggested pivot in the piece's own pixels.  Direction rules ('top', 'bottom_left', ...): the middle of the end of the piece that lies that way
    (the points within `frac` of the extent from the extreme); 'center': middle of the opaque pixels; 'neck' (heads): the back of the head, left of
    the skull and below the antennae; 'feet' (bodies): bottom centre of the feet."""
    pts = _opaque_points(im)
    w, h = im.size
    if not pts:
        return [w / 2.0, h / 2.0]
    if rule == "center":
        return [round(sum(p[0] for p in pts) / len(pts), 1), round(sum(p[1] for p in pts) / len(pts), 1)]
    if rule == "neck":
        body = [p for p in pts if p[1] > h * 0.40]
        x0 = min(p[0] for p in body)
        x1 = max(p[0] for p in body)
        rear = [p for p in body if p[0] < x0 + 0.14 * (x1 - x0)]
        return [round(x0 + 0.10 * (x1 - x0), 1), round(sum(p[1] for p in rear) / len(rear), 1)]
    if rule == "feet":
        low = [p for p in pts if p[1] > max(q[1] for q in pts) - 0.05 * h]
        return [round(sum(p[0] for p in low) / len(low), 1), float(max(p[1] for p in pts) + 1)]
    dx, dy = DIRS[rule]
    sc = [p[0] * dx + p[1] * dy for p in pts]
    lo, hi = min(sc), max(sc)
    sel = [p for p, v in zip(pts, sc) if v >= hi - frac * (hi - lo)]
    return [round(sum(p[0] for p in sel) / len(sel), 1), round(sum(p[1] for p in sel) / len(sel), 1)]


def body_metrics(im):
    """Full-body sprites: nose-to-tail length (the span of columns that are at least 14 px tall, so thin antennae and leg tips do not count) and the
    ground line (bottom of the lowest foot)."""
    a = im.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    px = a.load()
    w, h = a.size
    cols = []
    for x in range(w):
        n = sum(1 for y in range(h) if px[x, y])
        if n >= 14:
            cols.append(x)
    x0, x1 = (cols[0], cols[-1] + 1) if cols else (0, w)
    ys = [y for y in range(h) if any(px[x, y] for x in range(0, w, 1))]
    return {"length": x1 - x0, "nose_x": x1, "tail_x": x0, "ground_y": (max(ys) + 1) if ys else h}


# -------------------------------------------------------------------------------------------------------------------- build

def build(contact=None, debug=None, only=None, sheets=None):
    os.makedirs(OUT, exist_ok=True)
    partial = bool(only or sheets)
    if not partial:
        for fn in os.listdir(OUT):
            if fn.endswith(".png"):
                os.remove(os.path.join(OUT, fn))
    manifest = {"_about": "Ant part kit cut from art_src/antkit_*.png by tools/art/make_antkit.py. Every piece is a trimmed transparent PNG, long side <= %d px. "
                          "'pivot' is a suggested hinge in the piece's own pixels (legs: top joint; mandibles: where they attach; antennae: base; wings: root; "
                          "abdomens: front attachment; thorax/misc: centre; heads: neck). Ants in the pictures face RIGHT. _l/_r name the place on the sheet "
                          "(mirror a piece with a flip for the other side). 'scale' is how much the piece was shrunk from the sheet. Full bodies carry "
                          "'length' (nose to tail, antennae and leg tips excluded) and 'feet' (ground contact, bottom centre)." % MAXSIDE, "pieces": {}}
    if partial and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest["pieces"] = json.load(f).get("pieces", {})
    pieces = {}
    for key in SHEETS:
        if sheets and key not in sheets:
            continue
        specs = [sp for sp in CATALOGUE.get(key, []) if only is None or sp["name"] in only]
        if not specs:
            continue
        sh = Sheet(key)
        claimed = set()
        groups = []
        for sp in specs:
            g = [c for c in sh.pick(sp["boxes"], drop=sp.get("drop", ())) if c not in claimed]
            claimed.update(g)
            groups.append(g)
            if not g and not sp.get("ellipse"):
                print("!! nothing found for", sp["name"])
        lab = sh.owners(groups)
        ell = {}
        for i, sp in enumerate(specs):
            if sp.get("ellipse"):
                ell[i] = ellipse_mask(sh.size, *sp["ellipse"])
        if debug:
            assign_debug(sh, groups, [sp["name"] for sp in specs], os.path.join(debug, "assign_%s.png" % key))
        for i, sp in enumerate(specs):
            if not groups[i] and i not in ell:
                continue
            im, pos = piece_image(sh, lab, i + 1, sp, ell.get(i))
            if im is None:
                continue
            im = trim(im)
            im, k = shrink(im)
            if sp.get("pivot_frac"):
                piv = [round(sp["pivot_frac"][0] * im.size[0], 1), round(sp["pivot_frac"][1] * im.size[1], 1)]
            else:
                piv = hinge(im, sp["pivot"])
            fn = sp["name"] + ".png"
            im.save(os.path.join(OUT, fn), optimize=True)
            ent = {"file": "antkit/" + fn, "w": im.size[0], "h": im.size[1], "kind": sp["kind"], "sheet": SHEETS[key]["file"],
                   "pivot": piv, "scale": round(k, 4)}
            if sp["kind"] == "body":
                bm = body_metrics(im)
                ent["length"] = bm["length"]
                ent["feet"] = [piv[0], float(bm["ground_y"])]
                ent["ground_y"] = float(bm["ground_y"])
                ent["nose_x"] = bm["nose_x"]
                ent["tail_x"] = bm["tail_x"]
                ent["pivot"] = [piv[0], float(bm["ground_y"])]
            if sp["kind"] == "wing":
                ent["alpha_hint"] = "membrane is drawn opaque in the source; the game may draw wings at about 0.85 alpha"
            manifest["pieces"][sp["name"]] = ent
            pieces[sp["name"]] = (im, ent)
            print("%-16s %4dx%-4d %s" % (sp["name"], im.size[0], im.size[1], "(x%.2f)" % k if k < 1 else ""))
    order = {n: i for i, sp in enumerate(sum(CATALOGUE.values(), [])) for n in [sp["name"]]}
    manifest["pieces"] = dict(sorted(manifest["pieces"].items(), key=lambda kv: order.get(kv[0], 0)))
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT))
    print("%d pieces, %.2f MB in %s" % (len(pieces), total / 1048576.0, OUT))
    if contact:
        make_contact(pieces, contact)
    return pieces


# ----------------------------------------------------------------------------------------------------------------- contact

def _checker(size, a=(150, 150, 150), b=(120, 120, 120), cell=12):
    im = Image.new("RGB", size, a)
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=b)
    return im


def make_contact(pieces, path, cols=6, cell=280):
    """Every piece twice (mid-grey checker and dark brown) with its name, size and pivot, to check the cuts by eye."""
    f = ImageFont.load_default()
    names = list(pieces)
    rows = (len(names) + cols - 1) // cols
    cw, ch = cell, 0
    heights = []
    for r in range(rows):
        hh = max(pieces[n][0].size[1] for n in names[r * cols:(r + 1) * cols])
        heights.append(hh + 22)
    W = cols * cw
    H = sum(heights) + 8
    sheet = Image.new("RGB", (W, H), (40, 40, 40))
    y = 4
    for r in range(rows):
        for c in range(cols):
            i = r * cols + c
            if i >= len(names):
                break
            n = names[i]
            im, ent = pieces[n]
            x0 = c * cw
            half = cw // 2
            for j, bgc in enumerate(("check", (66, 44, 30))):
                cell_im = _checker((half - 2, heights[r] - 4)) if bgc == "check" else Image.new("RGB", (half - 2, heights[r] - 4), bgc)
                w, h = im.size
                sc = min(1.0, (half - 6) / float(w))
                pim = im if sc >= 1.0 else im.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)
                ox = (half - 2 - pim.size[0]) // 2
                cell_rgba = cell_im.convert("RGBA")
                cell_rgba.alpha_composite(pim, (ox, 16))
                d = ImageDraw.Draw(cell_rgba)
                px, py = ent["pivot"]
                cx, cy = ox + px * sc, 16 + py * sc
                d.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), outline=(255, 0, 0, 255), fill=(255, 255, 0, 255))
                sheet.paste(cell_rgba.convert("RGB"), (x0 + j * half, y))
            d = ImageDraw.Draw(sheet)
            d.text((x0 + 4, y + 2), "%s %dx%d" % (n, im.size[0], im.size[1]), fill=(255, 255, 255), font=f)
        y += heights[r]
    sheet.save(path)
    print("contact sheet:", path, sheet.size)


def main(argv):
    contact = None
    debug = None
    only = None
    sheets = None
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--contact":
            contact = args.pop(0)
        elif a == "--debug":
            debug = args.pop(0)
        elif a == "--only":
            only = set(args.pop(0).split(","))
        elif a == "--sheets":
            sheets = set(args.pop(0).split(","))
    build(contact, debug, only, sheets)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
