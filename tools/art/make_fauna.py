#!/usr/bin/env python3
"""Cut the owner's FAUNA + FOOD sheet (art_src/fauna_sheet.png) into one transparent PNG per item for the game.

The sheet is a flat RGB picture on a BLACK background (the artist's cut-out was flattened onto black, not white): a thick near-black ink outline
round every item, a JPEG-block halo hugging the outside of the ink (grey / olive / red blocks; the honeydew has a bright red one), and pure black
beyond that.  Brightness alone cannot tell the ink from the background, so, like make_antkit.py, the matte is built from the inside out:
  1. the bright fill of the drawing (eroded so thin halo dies, grown back inside the lenient bright mask; thin light stripes with ink on both
     sides, the antennae, are kept by a flank test),
  2. the ink outline: grown out from that fill, never farther than the ink is thick, so the halo outside it is left out (touching items share
     the contested ink fairly),
  3. holes: dark pupils, the worm's mouth and the like stay (they are part of the drawing), empty background trapped between legs does not,
  4. a soft edge (about one pixel of alpha ramp) with everything beyond the bright fill repainted flat ink colour, so no halo can show.
Pale interiors (cream eggs, larva, cocoon, mushroom cap, wing membranes, glints) survive because they are part of the bright fill.
Honeydew (no black outline, a red halo) and the aphid heap (olive moss between the bugs) get their own small recipes below.

Then the sheet is split into its items (islands of the fill picked by hand-tuned boxes: honeydew = one item, aphids = one, eggs = one, the
hornet with its wings = one, the earthworm = one, berries = one ...), each trimmed to its alpha bounding box, shrunk to at most MAXSIDE px on the
long side and saved to content/art/fauna/<name>.png.  fauna_manifest.json lists every item with size, facing, ground contact point, length of
the body in the picture, a game size suggestion and notes on how the single picture can be animated.

Needs Pillow only:  python3 tools/art/make_fauna.py [--contact PATH] [--debug DIR] [--only a,b]
  --contact PATH   write a verification contact sheet (every item on grey checker and on dark brown, with its label)
  --debug DIR      write assign.png (which island went to which item) and a matte preview
Does not import or touch make_art.py / make_antkit.py.
"""
import json
import os
import sys
from collections import deque

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "fauna_sheet.png")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "fauna")
MANIFEST = os.path.join(ART, "fauna_manifest.json")
INK = (21, 18, 26)          # the house outline colour (same as make_art.py / make_antkit.py)
MAXSIDE = 320               # longest side of any saved item
PAD = 2                     # transparent border kept round every item
INK_PX = 6                  # how far the ink outline reaches beyond the bright fill on the sheet (px)
CHAIN_PX = 5                # a thin island (antenna stripe, claw tip) counts only if it is this close to something solid; the halo is farther
WORKER_PX = 40.0            # the game's worker ant is drawn about this long (px at scale 1); the size suggestions are relative to it


# ---------------------------------------------------------------------------------------------------------------- helpers

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
    """Connected pieces (8-neighbour) of a mask: [{area, cx, cy, box, pts}], pts as flat (x, y) tuples."""
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


def _mask_of(size, comps):
    m = Image.new("L", size, 0)
    p = m.load()
    for c in comps:
        for (x, y) in c["pts"]:
            p[x, y] = 255
    return m


def _poly_mask(size, poly, offset=(0, 0)):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon([(x - offset[0], y - offset[1]) for (x, y) in poly], fill=255)
    return m


# ---------------------------------------------------------------------------------------------------------------- the sheet

class Sheet:
    """The drawing's bright fill and its islands."""

    def __init__(self, fill_lo=100, lenient_lo=60, erode=3, ink_hi=52, thin_reach=9):
        self.im = Image.open(SRC).convert("RGB")
        self.size = self.im.size
        self.L = self.im.convert("L")
        ink_ok = _binary(_mx(self.im), 4, ink_hi)
        bright = _binary(self.L, fill_lo)
        core = bright.filter(ImageFilter.MinFilter(erode))
        # thin light stripes (antennae seen in the ink) are too narrow to survive the erosion: keep the bright pixels that have ink on both sides
        core = ImageChops.lighter(core, ImageChops.darker(bright, _flanked(ink_ok, thin_reach)))
        self.fill = reconstruct(core, _binary(self.L, lenient_lo))
        self.comps = None

    def override(self, box, mask_fn):
        """Replace the fill inside `box` by what mask_fn(rgb crop) says (for the items whose colours the brightness test cannot handle)."""
        crop = self.im.crop(box)
        self.fill.paste(mask_fn(crop), box[:2])

    def label(self, min_area=40):
        self.comps = label_pixels(self.fill)
        px = self.im.load()
        for c in self.comps:
            c["junk"] = c["area"] < min_area
            if not c["junk"] and c["area"] < 400:
                # specks of halo / JPEG noise: small, neutral grey islands (the drawing's own small bits are coloured)
                ch = 0
                step = max(1, len(c["pts"]) // 60)
                n = 0
                for (x, y) in c["pts"][::step]:
                    r, g, b = px[x, y]
                    ch += max(r, g, b) - min(r, g, b)
                    n += 1
                c["junk"] = (ch / n) < 14
            c["thin"] = False
        self._weed_thin()

    def _weed_thin(self):
        """Thin islands (under about 7 px wide: the bright edge lines and blocks of the JPEG halo) are junk unless they sit inside the outline band
        of something solid (antenna stripes, tiny claws, leg tips: chained to a solid neighbour within an outline's width).  The halo lies
        beyond the ink, so it is farther away than that."""
        thin, solid = [], []
        for i, c in enumerate(self.comps):
            if c["junk"]:
                continue
            x0, y0, x1, y1 = c["box"]
            m = Image.new("L", (x1 - x0 + 8, y1 - y0 + 8), 0)
            p = m.load()
            for (x, y) in c["pts"]:
                p[x - x0 + 4, y - y0 + 4] = 255
            if m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MinFilter(3)).getbbox() is None:
                thin.append(i)
            else:
                solid.append(i)
        reach_n = CHAIN_PX
        for _ in range(8):
            reach = Image.new("L", self.size, 0)
            rp = reach.load()
            for i in solid:
                for (x, y) in self.comps[i]["pts"]:
                    rp[x, y] = 255
            for k in range(reach_n):
                reach = _step(reach, k)
            rp = reach.load()
            moved = []
            for i in thin:
                pts = self.comps[i]["pts"]
                if sum(1 for (x, y) in pts if rp[x, y]) >= 0.35 * len(pts):
                    moved.append(i)
            if not moved:
                break
            solid += moved
            thin = [i for i in thin if i not in moved]
        for i in thin:
            self.comps[i]["junk"] = True

    def pick(self, boxes, drop=(), min_area=40):
        """Indices of the islands whose centre lies in any of the boxes (and in none of the `drop` boxes)."""
        out = []
        for i, c in enumerate(self.comps):
            if c["area"] < min_area or c["junk"]:
                continue
            if any(x0 <= c["cx"] < x1 and y0 <= c["cy"] < y1 for (x0, y0, x1, y1) in drop):
                continue
            for (x0, y0, x1, y1) in boxes:
                if x0 <= c["cx"] < x1 and y0 <= c["cy"] < y1:
                    out.append(i)
                    break
        return out

    def owners(self, groups, reach):
        """Label image: item number (1..) on every pixel that belongs to an item (its fill plus `reach[item]` px of outline grown all round it) and
        a second one with the fills alone.  Islands of nobody (dust, other items' bits) block the growth (label 254).  Items grow at the same
        pace, so touching outlines are shared fairly."""
        core = Image.new("L", self.size, 0)
        cp = core.load()
        for c in self.comps:
            if c["area"] >= 40 and not c["junk"]:
                for (x, y) in c["pts"]:
                    cp[x, y] = 254
        for gi, g in enumerate(groups):
            for ci in g:
                for (x, y) in self.comps[ci]["pts"]:
                    cp[x, y] = gi + 1
        lab = core
        for i in range(max(reach)):
            lut = [0] * 256
            for gi, r in enumerate(reach):
                if r > i:
                    lut[gi + 1] = gi + 1
            active = lab.point(lut)
            grown = _step(active, i)
            todo = lab.point(lambda v: 255 if v == 0 else 0)
            lab = Image.composite(grown, lab, todo)
        return lab, core


# ---------------------------------------------------------------------------------------------------------------- one item

def piece_image(sh, lab, core, pid, opts):
    """RGBA crop for item number pid: the owned pixels, holes decided, outline smoothed and everything beyond the fill repainted flat ink.
    Returns (RGBA image, (x, y) of its top-left corner on the sheet)."""
    m = lab.point(lambda v: 255 if v == pid else 0)
    bb = m.getbbox()
    if bb is None:
        return None, None
    pad = 14
    box = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(sh.size[0], bb[2] + pad), min(sh.size[1], bb[3] + pad))
    m = m.crop(box)
    rgb = sh.im.crop(box)
    cm = core.point(lambda v: 255 if v == pid else 0).crop(box)          # the fill of this item alone
    for (x0, y0, x1, y1) in opts.get("erase", ()):
        ImageDraw.Draw(m).rectangle((x0 - box[0], y0 - box[1], x1 - box[0], y1 - box[1]), fill=0)
    if opts.get("clip"):
        m = ImageChops.darker(m, _poly_mask(m.size, opts["clip"], box[:2]))
    r = opts.get("close", 1)
    if r:
        m = m.filter(ImageFilter.MaxFilter(2 * r + 1)).filter(ImageFilter.MinFilter(2 * r + 1))
    # holes: dark pupils, the worm's throat and the like stay (they are part of the drawing); empty background trapped between legs does not
    keep = Image.new("L", m.size, 0)
    mode = opts.get("holes", "auto")
    if mode != "none":
        filled = fill_holes(m)
        holes = ImageChops.subtract(filled, m)
        if mode == "all":
            keep = holes
        else:
            mxc = _mx(rgb)
            mp = mxc.load()
            kp = keep.load()
            for c in label_pixels(holes):
                vals = sorted(mp[x, y] for (x, y) in c["pts"])
                med = vals[len(vals) // 2]
                if c["area"] < opts.get("hole_small", 260) or med >= opts.get("hole_med", 24) or any(
                        x0 - 4 <= c["cx"] + box[0] <= x1 + 4 and y0 - 4 <= c["cy"] + box[1] <= y1 + 4 for (x0, y0, x1, y1) in opts.get("keep_holes", ())):
                    for (x, y) in c["pts"]:
                        kp[x, y] = 255
        m = ImageChops.lighter(m, keep)
    # smooth the outline: blur the hard mask and cut again a little on the generous side (keeps spike tips, drops pixel noise)
    m = m.filter(ImageFilter.GaussianBlur(1.1)).point(lambda v: 255 if v > 105 else 0)
    # leave out dust islands that were never part of the item's picture
    min_island = opts.get("min_island", 200)
    if min_island:
        keepi = Image.new("L", m.size, 0)
        kp = keepi.load()
        for c in label_pixels(m):
            if c["area"] >= min_island:
                for (x, y) in c["pts"]:
                    kp[x, y] = 255
        m = keepi
    # everything farther than 2 px from the bright fill (and not a kept hole: pupils, throats) is the ink band: repainted flat ink, no halo, no noise
    near = cm.filter(ImageFilter.MaxFilter(5))
    keepd = keep.filter(ImageFilter.MaxFilter(3))
    band = ImageChops.subtract(ImageChops.subtract(m, near), keepd)
    ink = tuple(opts.get("ink_color", INK))
    rgb = Image.composite(Image.new("RGB", rgb.size, ink), rgb, band)
    a = m.filter(ImageFilter.GaussianBlur(0.8))
    a = a.point(lambda v: 0 if v < 40 else (255 if v > 215 else int((v - 40) * 255 / 175)))
    out = rgb.convert("RGBA")
    # clear pixels carry the ink colour, so a filtered (bilinear) texture never blends a white or black fringe in
    out = Image.composite(out, Image.new("RGBA", out.size, ink + (0,)), a.point(lambda v: 255 if v > 0 else 0))
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


# ---------------------------------------------------------------------------------------------------------------- catalogue
# name -> where the item sits on the sheet (boxes: fill islands whose centre is inside belong to it; earlier entries win) and its recipe.
#   kind     creature / brood / food / plant  (the game side)
#   facing   which way the picture looks (right / left / none); the ants and beetles look right
#   len      game length in px at scale 1 for a worker ant drawn 40 px long (the item's body span in the picture is scaled to it)
#   anim     how the single picture can be moved: bob (px up and down at game size), squash (fraction of height; stretch is the same the other
#            way), wiggle (degrees of sway), pulse (grow and shrink)
#   ink      outline reach in px on the sheet (default INK_PX);  holes / close / min_island / clip / erase / drop / ink_color: see piece_image

def P(name, kind, boxes, facing, length, anim, note, **opts):
    if boxes and isinstance(boxes[0], (int, float)):
        boxes = [boxes]
    d = {"name": name, "kind": kind, "boxes": list(boxes), "facing": facing, "len": length, "anim": anim, "note": note}
    d.update(opts)
    return d


CATALOGUE = [
    # ---- top row: the brood and the queen
    P("queen_full", "creature", [(0, 0, 672, 300)], "right", 90, {"bob": 1.2, "squash": 0.03, "wiggle": 0}, "Queen with the egg-laden gaster; walks slowly, no separate legs."),
    P("eggs", "brood", [(672, 60, 912, 280)], "none", 16, {"pulse": 0.04}, "A pile of cream eggs (one picture)."),
    P("larva", "brood", [(912, 40, 1112, 280)], "left", 22, {"squash": 0.10, "wiggle": 4}, "Fat cream larva, head at the lower left; can wriggle by squashing."),
    P("pupa", "brood", [(1112, 40, 1298, 280)], "none", 24, {"pulse": 0.03, "wiggle": 2}, "Pupa wrapped in a silk cocoon with the brown pupa showing in the slit."),
    P("worker_small", "creature", [(1298, 90, 1536, 280)], "right", 34, {"bob": 1.0, "squash": 0.04}, "Small pale worker ant (nest worker)."),
    # ---- second row: food and small things
    P("seeds", "food", [(0, 280, 195, 450)], "none", 16, {}, "Heap of seeds and grains."),
    P("berries", "food", [(195, 280, 370, 450)], "none", 14, {}, "Cluster of red berries with leaves."),
    P("crumb", "food", [(370, 280, 540, 450)], "none", 12, {}, "Bread crumb with three little crumbs beside it."),
    P("apple", "food", [(540, 280, 690, 450)], "none", 22, {}, "Bitten apple with three crumbs."),
    P("beetle", "creature", [(690, 290, 890, 450)], "right", 40, {"bob": 1.0, "squash": 0.04}, "Small dark beetle."),
    P("honeydew", "food", [(890, 290, 1022, 450)], "none", 14, {"pulse": 0.05}, "Honeydew droplets: six golden drops (one item, gaps transparent).",
      ink=5, holes="none", ink_color=(64, 38, 12), fill="gold"),
    P("aphids", "creature", [(1022, 270, 1185, 450)], "none", 8, {"squash": 0.05, "wiggle": 3}, "Heap of five green aphids on moss (one item).",
      ink=6, holes="all"),
    P("mushrooms", "food", [(1185, 265, 1375, 450)], "none", 26, {}, "Cluster of white mushrooms on a mound of earth."),
    P("leaf", "plant", [(1375, 265, 1536, 450)], "none", 28, {}, "Green leaf with three holes and a bitten edge."),
    # ---- third row: bigger animals
    P("stagbeetle", "creature", [(0, 445, 405, 662)], "right", 90, {"bob": 1.5, "squash": 0.03}, "Stag beetle with big red jaws."),
    P("centipede", "creature", [(405, 445, 775, 645)], "right", 120, {"bob": 1.0, "wiggle": 3, "squash": 0.03}, "Centipede, head right."),
    P("scorpion", "creature", [(775, 440, 1085, 640)], "right", 110, {"bob": 1.0, "squash": 0.03}, "Scorpion, claws and head to the right, stinger raised."),
    P("moth", "creature", [(1085, 470, 1536, 612), (1370, 600, 1420, 650)], "right", 60, {"bob": 2.0, "squash": 0.03}, "Furry brown moth-like winged insect, flies."),
    P("earthworm", "creature", [(40, 620, 800, 790)], "right", 180, {"squash": 0.12, "wiggle": 2}, "Earthworm; the open mouth is at the right.",
      holes="all"),
    P("hornet", "creature", [(1100, 615, 1500, 700), (1150, 700, 1500, 862)], "right", 70, {"bob": 2.5, "squash": 0.02}, "Yellow-black hornet with its pale wings (one item).", min_island=60),
    # ---- bottom row: the red ants, small to big, in profile
    P("redant_small", "creature", [(0, 800, 265, 990)], "right", 36, {"bob": 1.0, "squash": 0.04}, "Small red ant."),
    P("redant_soldier", "creature", [(265, 780, 650, 990)], "right", 48, {"bob": 1.0, "squash": 0.04}, "Red soldier ant."),
    P("redant_major", "creature", [(650, 700, 1215, 990)], "right", 80, {"bob": 1.5, "squash": 0.03}, "Red major ant with horns."),
]


def gold_fill(crop):
    """Honeydew: the golden drops by colour (the brightness test would run into the bright red halo round them)."""
    px = crop.load()
    m = Image.new("L", crop.size, 0)
    mp = m.load()
    for y in range(crop.size[1]):
        for x in range(crop.size[0]):
            r, g, b = px[x, y]
            if r >= 140 and g >= 95 and r - b >= 80 and g - b >= 40:
                mp[x, y] = 255
    return m.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))


FILLS = {"gold": gold_fill}


# ---------------------------------------------------------------------------------------------------------------- metrics

def body_metrics(im):
    """Nose-to-tail span (columns that are at least 14 px tall, so thin antennae and leg tips do not count), the horizontal middle of that span and
    the ground line (bottom of the lowest foot)."""
    a = im.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    px = a.load()
    w, h = a.size
    mincol = max(4, min(14, h // 8))
    cols = [x for x in range(w) if sum(1 for y in range(h) if px[x, y]) >= mincol]
    x0, x1 = (cols[0], cols[-1] + 1) if cols else (0, w)
    ys = [y for y in range(h) if any(px[x, y] for x in range(w))]
    return {"length": x1 - x0, "x0": x0, "x1": x1, "ground_y": (max(ys) + 1) if ys else h}


def ground_point(im, bm):
    """Where the thing touches the ground: the middle of the body span, bottom of the lowest foot.  Feet below the middle of the body (legs
    that reach farther down) are what the game should stand on, so the point's x is the middle of the footprint of the lowest 12% rows if that
    stays inside the body span, else the middle of the span."""
    a = im.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    px = a.load()
    w, h = a.size
    gy = bm["ground_y"]
    lo = max(0, gy - max(3, int(0.12 * h)))
    xs = [x for x in range(w) for y in range(lo, gy) if px[x, y]]
    mid = (bm["x0"] + bm["x1"]) / 2.0
    if xs:
        foot = (min(xs) + max(xs)) / 2.0
        if bm["x0"] <= foot <= bm["x1"]:
            return [round(foot, 1), float(gy)]
    return [round(mid, 1), float(gy)]


# -------------------------------------------------------------------------------------------------------------------- build

def assign_debug(sh, groups, names, path):
    """Debug picture: every fill island coloured by the item it was given to (red = left over and big enough to matter, dim grey = junk)."""
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
        if ci not in taken and c["area"] >= 60 and not c["junk"]:
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


def build(contact=None, debug=None, only=None):
    os.makedirs(OUT, exist_ok=True)
    partial = bool(only)
    if not partial:
        for fn in os.listdir(OUT):
            if fn.endswith(".png"):
                os.remove(os.path.join(OUT, fn))
    sh = Sheet()
    for sp in CATALOGUE:
        if sp.get("fill"):
            b = sp["boxes"][0]
            sh.override(b, FILLS[sp["fill"]])
    sh.label()
    claimed = set()
    groups = []
    for sp in CATALOGUE:
        g = [c for c in sh.pick(sp["boxes"], drop=sp.get("drop", ())) if c not in claimed]
        claimed.update(g)
        groups.append(g)
        if not g:
            print("!! nothing found for", sp["name"])
    lab, core = sh.owners(groups, [sp.get("ink", INK_PX) for sp in CATALOGUE])
    if debug:
        os.makedirs(debug, exist_ok=True)
        assign_debug(sh, groups, [sp["name"] for sp in CATALOGUE], os.path.join(debug, "assign.png"))
    manifest = {
        "_about": "Fauna and food cut from art_src/fauna_sheet.png by tools/art/make_fauna.py. Every item is a trimmed transparent PNG, long side <= %d px, "
                  "outlined in thick ink like the rest of the art. The sheet was drawn on black; the matte was rebuilt from the inside out (no halo). "
                  "'facing': the way the picture looks (the ants and beetles look RIGHT; 'none' = symmetric or not a creature; flip to turn). "
                  "'ground': suggested ground contact point in the item's own pixels (middle of the body span, bottom of the lowest foot). "
                  "'length_px': nose-to-tail span in the picture (antennae and leg tips excluded; wings included). 'game_len': suggested length in game px at "
                  "scale 1 for a worker ant drawn about %d px long. 'scale' = game_len / length_px: multiply the picture by it. 'anim': how the single "
                  "picture can be moved (bob = px up and down at game size, squash = fraction of height squeezed (stretch the width by the same), "
                  "wiggle = degrees of sway, pulse = grow and shrink). The creatures are single pictures, no separate legs." % (MAXSIDE, WORKER_PX),
        "worker_ref_px": WORKER_PX, "items": {}}
    if partial and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest["items"] = json.load(f).get("items", {})
    pieces = {}
    for i, sp in enumerate(CATALOGUE):
        if only and sp["name"] not in only:
            continue
        if not groups[i]:
            continue
        im, pos = piece_image(sh, lab, core, i + 1, sp)
        if im is None:
            continue
        im = trim(im)
        im, k = shrink(im)
        fn = sp["name"] + ".png"
        im.save(os.path.join(OUT, fn), optimize=True)
        bm = body_metrics(im)
        ground = ground_point(im, bm)
        ent = {"file": "fauna/" + fn, "w": im.size[0], "h": im.size[1], "kind": sp["kind"], "facing": sp["facing"],
               "ground": ground, "length_px": bm["length"], "game_len": float(sp["len"]),
               "scale": round(sp["len"] / float(bm["length"]), 4), "anim": sp["anim"], "single_picture": True,
               "note": sp["note"], "sheet_scale": round(k, 4)}
        manifest["items"][sp["name"]] = ent
        pieces[sp["name"]] = (im, ent)
        print("%-15s %4dx%-4d %s ground %s span %d" % (sp["name"], im.size[0], im.size[1], "(x%.2f)" % k if k < 1 else "        ", ground, bm["length"]))
    order = {sp["name"]: i for i, sp in enumerate(CATALOGUE)}
    manifest["items"] = dict(sorted(manifest["items"].items(), key=lambda kv: order.get(kv[0], 0)))
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT))
    print("%d items, %.2f MB in %s" % (len(pieces), total / 1048576.0, OUT))
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


def make_contact(pieces, path, cols=2, half=340):
    """Every item twice (mid-grey checker and dark brown) with its name, size and ground point, to check the cuts by eye."""
    f = ImageFont.load_default()
    names = list(pieces)
    rows = (len(names) + cols - 1) // cols
    heights = []
    for r in range(rows):
        hh = max(pieces[n][0].size[1] for n in names[r * cols:(r + 1) * cols])
        heights.append(min(hh, 330) + 26)
    cw = half * 2
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
            for j, bgc in enumerate(("check", (66, 44, 30))):
                cell_im = _checker((half - 2, heights[r] - 4)) if bgc == "check" else Image.new("RGB", (half - 2, heights[r] - 4), bgc)
                w, h = im.size
                sc = min(1.0, (half - 8) / float(w), (heights[r] - 30) / float(h))
                pim = im if sc >= 1.0 else im.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)
                ox = (half - 2 - pim.size[0]) // 2
                cell_rgba = cell_im.convert("RGBA")
                cell_rgba.alpha_composite(pim, (ox, 18))
                d = ImageDraw.Draw(cell_rgba)
                gx, gy = ent["ground"]
                cx, cy = ox + gx * sc, 18 + gy * sc
                d.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), outline=(255, 0, 0, 255), fill=(255, 255, 0, 255))
                sheet.paste(cell_rgba.convert("RGB"), (x0 + j * half, y))
            d = ImageDraw.Draw(sheet)
            d.text((x0 + 4, y + 3), "%s %dx%d  facing %s  game %d px" % (n, im.size[0], im.size[1], ent["facing"], ent["game_len"]), fill=(255, 255, 255), font=f)
        y += heights[r]
    sheet.save(path)
    print("contact sheet:", path, sheet.size)


def main(argv):
    contact = None
    debug = None
    only = None
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--contact":
            contact = args.pop(0)
        elif a == "--debug":
            debug = args.pop(0)
        elif a == "--only":
            only = set(args.pop(0).split(","))
    build(contact, debug, only)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
