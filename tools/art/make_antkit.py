#!/usr/bin/env python3
"""Cut the owner's ANT PART KIT sheets (art_src/antkit_*.png) into single transparent PNGs for the game.

The sheets are RGBA pictures with real transparency (the owner's cut-outs: thick near-black outline, flat colour fill, nothing behind them).
So there is no background to remove: the matte is the sheet's own alpha channel, cleaned a little --
  * alpha below ~10 is dust of the cut-out and becomes fully transparent (its stray colour is wiped too),
  * alpha of 250 and over (the near-opaque film inside the drawings) becomes fully opaque,
  * what is between (the one-pixel soft edge) is kept, so the outline stays smooth on any background.
Then every sheet is split into its pieces: connected pieces of the alpha, taken whole when they belong to one part, split by hand-placed
boxes / polygons where two parts touch, and joined where one part is several islands (a leg and its claw, an eye and its glint, a wing and its veins).
Each piece is trimmed to its alpha bounding box with a small transparent margin, shrunk to at most MAXSIDE px on the long side (premultiplied,
so no dark fringe), and saved in content/art/antkit/.  content/art/antkit_manifest.json lists every piece with its size, a suggested hinge,
and for full bodies the nose-to-tail length and the foot point.

Needs Pillow only:   python3 tools/art/make_antkit.py [--contact PATH] [--debug DIR] [--sheets a,b] [--only name,name]
  --contact PATH   also write a verification contact sheet (every piece on grey checker and on dark brown, with names and hinges)
  --debug DIR      also write per-sheet pictures showing which piece every island went to
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
MAXSIDE = 256               # longest side of any saved piece
PAD = 2                     # transparent border kept round every piece
DUST = 10                   # alpha below this is dust
FILM = 250                  # alpha from this up is solid

SHEETS = {
    "heads_a": "antkit_heads_a.png",
    "heads_b": "antkit_heads_b.png",
    "parts_a": "antkit_parts_a.png",
    "parts_b": "antkit_parts_b.png",
    "full": "antkit_full.png",
}


# ------------------------------------------------------------------------------------------------------------------ sheet

def clean_alpha(a):
    """Dust (alpha < DUST) -> 0, film (alpha >= FILM) -> 255, the soft edge in between stays."""
    return a.point(lambda v: 0 if v < DUST else (255 if v >= FILM else v))


def load_sheet(name):
    im = Image.open(os.path.join(SRC, name))
    if im.mode != "RGBA":
        raise SystemExit("%s must be an RGBA picture with real transparency (it is %s)" % (name, im.mode))
    a = clean_alpha(im.getchannel("A"))
    rgb = im.convert("RGB")
    # wipe the stray colour under the transparent pixels, so nothing can bleed in when a piece is scaled
    rgb = Image.composite(rgb, Image.new("RGB", im.size, (0, 0, 0)), a.point(lambda v: 255 if v else 0))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def label_pixels(mask):
    """Connected pieces (8-neighbour) of a mask: [{area, cx, cy, box, idx}], idx = flat pixel numbers y * width + x."""
    w, h = mask.size
    data = mask.tobytes()
    seen = bytearray(w * h)
    comps = []
    for start in range(w * h):
        if data[start] and not seen[start]:
            q = deque([start])
            seen[start] = 1
            idx = []
            sx = sy = 0
            x0 = y0 = 1 << 30
            x1 = y1 = -1
            while q:
                p = q.popleft()
                idx.append(p)
                y, x = divmod(p, w)
                sx += x
                sy += y
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
                for dy in (-1, 0, 1):
                    ny = y + dy
                    if ny < 0 or ny >= h:
                        continue
                    for dx in (-1, 0, 1):
                        nx = x + dx
                        if 0 <= nx < w:
                            n = ny * w + nx
                            if data[n] and not seen[n]:
                                seen[n] = 1
                                q.append(n)
            comps.append({"area": len(idx), "cx": sx / len(idx), "cy": sy / len(idx), "box": (x0, y0, x1 + 1, y1 + 1), "idx": idx})
    return comps


def mask_of(size, idx):
    m = bytearray(size[0] * size[1])
    for p in idx:
        m[p] = 255
    return Image.frombytes("L", size, bytes(m))


def region_mask(size, regions):
    """Union of boxes (x0, y0, x1, y1) and polygons [(x, y), ...] as a sheet-sized mask."""
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for r in regions:
        if len(r) == 4 and not isinstance(r[0], (tuple, list)):
            d.rectangle((r[0], r[1], r[2] - 1, r[3] - 1), fill=255)
        else:
            d.polygon([tuple(p) for p in r], fill=255)
    return m


def _step(m, i):
    """One round-ish growth step (plus-shaped and square steps alternate); on a label image the larger label wins a contested pixel."""
    if i % 2 == 0:
        r = m
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            r = ImageChops.lighter(r, ImageChops.offset(m, dx, dy))
        return r
    return m.filter(ImageFilter.MaxFilter(3))


class Sheet:
    """One sheet: its cleaned RGBA picture and its islands (connected pieces of the alpha)."""

    def __init__(self, key):
        self.key = key
        self.im = load_sheet(SHEETS[key])
        self.size = self.im.size
        self.alpha = self.im.getchannel("A")
        self.comps = label_pixels(self.alpha.point(lambda v: 255 if v else 0))

    def assign(self, specs, min_area=30):
        """Give every island to the piece it belongs to.  Returns (label image: piece number 1.. per pixel, groups: per piece the islands it holds).
        A spec says where its piece sits with `regions` (boxes / polygons): an island goes whole to the spec whose region holds its middle (or most of it),
        however far its tips poke out of the box, and one spec may take several islands (a leg and its claw, an eye and its glint).
        Where parts touch (one island is two parts) the specs also carry `cut`, regions that split that island pixel by pixel; its pixels outside every cut
        join the nearest part.  Islands in no region are dropped (dust, a neighbour's edge)."""
        w, h = self.size
        regs = [region_mask(self.size, sp["regions"]) for sp in specs]
        cuts = [region_mask(self.size, sp["cut"]) if sp.get("cut") else None for sp in specs]
        rpx = [m.load() for m in regs]
        cpx = [m.load() if m else None for m in cuts]
        rbox = [m.getbbox() for m in regs]
        lab = bytearray(w * h)
        groups = [[] for _ in specs]
        for ci, c in enumerate(self.comps):
            if c["area"] < min_area:
                continue
            stride = max(1, c["area"] // 3000)
            sample = [(p % w, p // w) for p in c["idx"][::stride]]
            # touching parts: the island is cut where two or more specs with a cut region each hold a real share of it
            cb = c["box"]
            near = [bool(cpx[i]) and rbox[i] is not None and rbox[i][0] < cb[2] and cb[0] < rbox[i][2] and rbox[i][1] < cb[3] and cb[1] < rbox[i][3] for i in range(len(specs))]
            chits = [sum(1 for (x, y) in sample if cpx[i][x, y]) if near[i] else 0 for i in range(len(specs))]
            cowners = [i for i in range(len(specs)) if chits[i] >= max(3, 0.08 * len(sample))]
            if len(cowners) >= 2:
                loose = []
                for p in c["idx"]:
                    y, x = divmod(p, w)
                    for i in cowners:
                        if cpx[i][x, y]:
                            lab[p] = i + 1
                            break
                    else:
                        loose.append(p)
                for i in cowners:
                    groups[i].append(ci)
                if loose:
                    self._attach(lab, c, loose)
                continue
            # one part: the spec whose region holds the middle of the island, else the one holding most of it
            cx, cy = int(c["cx"]), int(c["cy"])
            owner = None
            for i in range(len(specs)):
                if 0 <= cx < w and 0 <= cy < h and rpx[i][cx, cy] and any(rpx[i][x, y] for (x, y) in sample[:: max(1, len(sample) // 40)]):
                    owner = i
                    break
            if owner is None:
                hits = [sum(1 for (x, y) in sample if rpx[i][x, y]) for i in range(len(specs))]
                best = max(range(len(specs)), key=lambda i: hits[i])
                if hits[best] >= 0.5 * len(sample):
                    owner = best
            if owner is None:
                continue
            for p in c["idx"]:
                lab[p] = owner + 1
            groups[owner].append(ci)
        return Image.frombytes("L", self.size, bytes(lab)), groups

    def _attach(self, lab, c, loose):
        """Loose pixels of a split island join whichever claimed part is nearest (growth over the island's own pixels)."""
        li = Image.frombytes("L", self.size, bytes(lab))
        allowed = mask_of(self.size, c["idx"])
        for i in range(120):
            grown = ImageChops.darker(_step(li, i), allowed)
            todo = li.point(lambda v: 255 if v == 0 else 0)
            nxt = Image.composite(grown, li, todo)
            if ImageChops.difference(nxt, li).getbbox() is None:
                break
            li = nxt
        data = li.tobytes()
        for p in loose:
            lab[p] = data[p]


# ------------------------------------------------------------------------------------------------------------- one piece

def piece_image(sh, lab, pid, opts):
    """RGBA crop holding piece number pid and nothing else (no neighbour's pixels, no dust islands).  Returns the image, or None."""
    m = lab.point(lambda v: 255 if v == pid else 0)
    bb = m.getbbox()
    if bb is None:
        return None
    pad = 4
    box = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(sh.size[0], bb[2] + pad), min(sh.size[1], bb[3] + pad))
    m = m.crop(box)
    for (x0, y0, x1, y1) in opts.get("erase", ()):
        ImageDraw.Draw(m).rectangle((x0 - box[0], y0 - box[1], x1 - box[0] - 1, y1 - box[1] - 1), fill=0)
    rgba = sh.im.crop(box)
    a = ImageChops.darker(rgba.getchannel("A"), m)
    # islands of the piece that are only dust (under a hundredth of its biggest island and under 40 px) are dropped, never real parts
    min_island = opts.get("min_island")
    if min_island != 0:
        comps = label_pixels(a.point(lambda v: 255 if v else 0))
        if comps:
            big = max(c["area"] for c in comps)
            thr = min_island if min_island else max(40, 0.01 * big)
            kill = [c for c in comps if c["area"] < thr]
            if kill:
                ap = bytearray(a.tobytes())
                for c in kill:
                    for p in c["idx"]:
                        ap[p] = 0
                a = Image.frombytes("L", a.size, bytes(ap))
    out = rgba.copy()
    out.putalpha(a)
    return out


def trim(im, pad=PAD):
    """Crop to the alpha bounding box and keep a transparent margin of pad px."""
    bb = im.getchannel("A").point(lambda v: 255 if v > 4 else 0).getbbox()
    if bb is None:
        return im
    bb = (bb[0] - pad, bb[1] - pad, bb[2] + pad, bb[3] + pad)
    out = Image.new("RGBA", (bb[2] - bb[0], bb[3] - bb[1]), (0, 0, 0, 0))
    out.paste(im, (-bb[0], -bb[1]))
    return out


def shrink(im, maxside=MAXSIDE):
    """Scale down so the long side is at most maxside (Pillow premultiplies RGBA when resizing, so no dark fringe)."""
    w, h = im.size
    k = min(1.0, maxside / float(max(w, h)))
    if k >= 1.0:
        return im, 1.0
    return im.resize((max(1, int(round(w * k))), max(1, int(round(h * k)))), Image.LANCZOS), k


# --------------------------------------------------------------------------------------------------------------- catalogue
# Every piece: name, kind, `regions` (where it sits on its sheet: an island goes to the piece whose region holds its middle), the hinge rule,
# and options.  Where two parts touch (one island), the pieces carry `cut` regions that split that island.  Parts that appear on several sheets
# are cut once, from the sheet with the cleanest, largest drawing; the repeats are marked dup=True (cut only with --dups, to compare).

def P(name, kind, regions, pivot="center", **opts):
    if regions and isinstance(regions[0], (int, float)):
        regions = [regions]
    d = {"name": name, "kind": kind, "regions": list(regions), "pivot": pivot}
    d.update(opts)
    return d


def pair_cut(box, line):
    """Two polygons that split the box along the polyline `line` (left-to-right): the part above it and the part below it."""
    x0, y0, x1, y1 = box
    top = [(x0, y0), (x1, y0)] + list(reversed(line)) + [(x0, line[0][1])]
    bot = [(x0, line[0][1])] + list(line) + [(x1, line[-1][1]), (x1, y1), (x0, y1)]
    return top, bot


CATALOGUE = {
    # four heads with antennae (little closed mandibles on the face) and four separate mandible pairs
    "heads_a": [
        P("head_1", "head", (0, 150, 395, 720), "neck"),
        P("head_2", "head", (395, 150, 745, 720), "neck"),
        P("head_3", "head", (745, 150, 1100, 720), "neck"),
        P("head_4", "head", (1100, 150, 1448, 720), "neck"),
        P("mandible_1_l", "mandible", (0, 730, 172, 1050), "top"),
        P("mandible_1_r", "mandible", (172, 730, 340, 1050), "top"),
        P("mandible_2_l", "mandible", (340, 730, 562, 1050), "top"),
        P("mandible_2_r", "mandible", (562, 730, 720, 1050), "top"),
        P("mandible_3_l", "mandible", (720, 730, 905, 1050), "top"),
        P("mandible_3_r", "mandible", (905, 730, 1085, 1050), "top"),
        P("mandible_4_l", "mandible", (1085, 730, 1284, 1050), "top"),
        P("mandible_4_r", "mandible", (1284, 730, 1448, 1050), "top"),
    ],
    # four heads with antennae and open mandibles, four mandible sets
    "heads_b": [
        P("head_5", "head", (0, 100, 399, 600), "neck"),
        P("head_6", "head", (399, 100, 745, 600), "neck"),
        P("head_7", "head", (745, 100, 1120, 600), "neck"),
        P("head_8", "head", (1120, 100, 1536, 600), "neck"),
        P("mandible_5_l", "mandible", (0, 600, 196, 1000), "top"),
        P("mandible_5_r", "mandible", (196, 600, 330, 1000), "top"),
        P("mandible_6_l", "mandible", (330, 600, 560, 1000), "top"),
        P("mandible_6_r", "mandible", (560, 600, 760, 1000), "top"),
        P("mandible_7_l", "mandible", (760, 600, 930, 1000), "top"),
        P("mandible_7_r", "mandible", (930, 600, 1125, 1000), "top"),
        P("mandible_8_l", "mandible", (1125, 600, 1320, 1000), "top"),
        P("mandible_8_r", "mandible", (1320, 600, 1536, 1000), "top"),
    ],
    # thoraxes, abdomens, five leg types, antennae and two wing sets
    "parts_a": [
        P("thorax_1", "thorax", (0, 40, 262, 340), "center"),
        P("thorax_2", "thorax", (262, 40, 500, 340), "center"),
        P("thorax_3", "thorax", (500, 40, 760, 340), "center"),
        P("abdomen_1", "abdomen", (760, 40, 940, 340), "top_right"),
        P("abdomen_2", "abdomen", (940, 40, 1060, 340), "top_right"),
        P("abdomen_3", "abdomen", (1060, 40, 1214, 340), "top_right"),
        P("abdomen_4", "abdomen", (1214, 40, 1372, 340), "top_right"),
        P("abdomen_5", "abdomen", (1372, 40, 1536, 340), "top_right"),
        P("leg_1", "leg", (0, 300, 240, 700), "top"),
        P("leg_2", "leg", (240, 300, 430, 700), "top"),
        P("leg_3", "leg", (430, 300, 625, 700), "top"),
        P("leg_4", "leg", (625, 300, 840, 700), "top"),
        P("leg_5", "leg", (840, 300, 1070, 700), "top"),
        P("antenna_1_l", "antenna", (1100, 340, 1335, 545), "bottom_left"),
        P("antenna_1_r", "antenna", (1335, 340, 1536, 545), "bottom_left"),
        P("antenna_2_l", "antenna", (1100, 545, 1335, 780), "bottom_left"),
        P("antenna_2_r", "antenna", (1335, 545, 1536, 780), "bottom_left"),
        P("wing_1_fore", "wing", (30, 680, 600, 812), "left"),
        P("wing_1_hind", "wing", (30, 812, 600, 990), "left"),
    ] + [
        # the second wing pair is one island (fore and hind touch): cut along the gap between them
        P("wing_2_fore", "wing", (620, 680, 1140, 990), "left", cut=[pair_cut((620, 680, 1140, 990), [(620, 858), (700, 858), (800, 852), (900, 838), (1000, 820), (1100, 812), (1140, 800)])[0]]),
        P("wing_2_hind", "wing", (620, 680, 1140, 990), "left", cut=[pair_cut((620, 680, 1140, 990), [(620, 858), (700, 858), (800, 852), (900, 838), (1000, 820), (1100, 812), (1140, 800)])[1]]),
    ],
    # more thoraxes, legs, antennae, horns, spines, plates, eyes and fur
    "parts_b": [
        P("thorax_5", "thorax", (0, 0, 240, 240), "center"),
        P("thorax_6", "thorax", (240, 0, 442, 240), "center"),
        P("thorax_7", "thorax", (442, 0, 636, 240), "center"),
        P("thorax_8", "thorax", (636, 0, 830, 240), "center"),
        P("leg_6", "leg", (0, 230, 158, 535), "top", dup=True),
        P("leg_7", "leg", (158, 230, 308, 535), "top", dup=True),
        P("leg_8", "leg", (308, 230, 470, 535), "top", dup=True),
        P("leg_9", "leg", (470, 230, 632, 535), "top", dup=True),
        P("leg_10", "leg", (632, 230, 796, 535), "top", dup=True),
        P("leg_11", "leg", (796, 230, 965, 535), "top", dup=True),
        P("antenna_3_l", "antenna", (960, 270, 1140, 440), "top_left"),
        P("antenna_3_r", "antenna", (960, 440, 1140, 600), "top_left"),
        P("antenna_4_l", "antenna", (1145, 255, 1372, 440), "bottom_left", cut=[[(1100, 250), (1368, 250), (1378, 440), (1100, 440)]]),
        P("antenna_4_r", "antenna", (1372, 255, 1528, 440), "top_left", cut=[[(1368, 250), (1560, 250), (1560, 440), (1378, 440)]]),
        P("antenna_5_l", "antenna", (1145, 340, 1345, 447), "top_left", cut=[(1100, 340, 1343, 700)]),
        P("antenna_5_r", "antenna", (1100, 450, 1335, 610), "top_right"),
        P("antenna_6", "antenna", (1345, 405, 1530, 615), "top_left", cut=[(1343, 340, 1560, 700)]),
        P("sting_1", "misc", (0, 720, 121, 1010), "top"),
        P("horn_1", "spine", (121, 720, 218, 1010), "bottom"),
        P("horn_2", "spine", (218, 720, 300, 893), "bottom"),
        P("horn_3", "spine", (218, 893, 380, 1010), "left"),
        P("horn_4", "spine", (300, 705, 440, 930), "bottom"),
        P("frill_1", "misc", (345, 835, 545, 1010), "top"),
        P("plate_1", "misc", (425, 705, 600, 860), "center"),
        P("plate_2", "misc", (600, 720, 800, 900), "center"),
        P("spine_1", "spine", (560, 850, 845, 1015), "bottom"),
        P("spine_2", "spine", (775, 705, 1070, 892), "bottom"),
        P("spine_3", "spine", (940, 580, 1140, 782), "bottom"),
        P("spine_4", "spine", (1140, 570, 1305, 782), "bottom"),
        P("spine_5", "spine", (1075, 779, 1195, 887), "bottom"),
        P("spine_6", "spine", (995, 879, 1190, 1015), "bottom"),
        P("plate_3", "misc", (1185, 745, 1316, 845), "center"),
        P("egg_sac_1", "egg", (815, 815, 995, 1010), "center"),
        P("eye_1", "eye", (1325, 765, 1426, 875), "center"),
        P("eye_2", "eye", (1426, 765, 1536, 875), "center"),
        P("fur_1", "fur", (1300, 595, 1420, 760), "bottom"),
        P("fur_2", "fur", (1420, 595, 1536, 760), "bottom"),
        # spine_7 and the two fur tufts under it are one island
        P("spine_7", "spine", (1170, 840, 1316, 1010), "bottom", cut=[(1170, 840, 1316, 1010)]),
        P("fur_3", "fur", (1316, 840, 1436, 1010), "center", cut=[(1316, 840, 1436, 1010)]),
        P("fur_4", "fur", (1436, 840, 1536, 1010), "center", cut=[(1436, 840, 1536, 1010)]),
    ],
    # full-body sprites, brood, one more thorax and the repeats of the kit rows
    "full": [
        P("queen_full", "body", (0, 0, 640, 310), "feet"),
        P("alate_full", "body", (640, 0, 1030, 310), "feet"),
        P("soldier_full", "body", (1030, 30, 1322, 310), "feet"),
        P("worker_full", "body", (1322, 130, 1536, 310), "feet"),
        P("egg_cluster", "egg", (0, 300, 236, 485), "center"),
        P("larva_1", "brood", (236, 300, 385, 485), "center"),
        P("larva_2", "brood", (385, 300, 610, 485), "center"),
        P("pupa_1", "brood", (610, 295, 806, 485), "center"),
        P("worker_small_full", "body", (806, 330, 1040, 485), "feet"),
        P("pupa_2", "brood", (1040, 295, 1250, 485), "center"),
        P("pupa_3", "brood", (1250, 295, 1536, 485), "center"),
        # the spiky thorax and the spiky head under it are one island: cut between them
        P("thorax_4", "thorax", (527, 483, 770, 646), "center", cut=[(527, 483, 770, 646)]),
        P("_head_spiky_full", "head", (527, 646, 770, 800), "neck", cut=[(527, 646, 770, 800)], dup=True),
        P("x_thorax_a", "thorax", (0, 483, 186, 650), "center", dup=True),
        P("x_thorax_b", "thorax", (186, 483, 352, 650), "center", dup=True),
        P("x_thorax_c", "thorax", (352, 483, 527, 650), "center", dup=True),
        P("abdomen_6", "abdomen", (730, 483, 935, 650), "top_left", dup=True),
        P("x_abdomen_b", "abdomen", (935, 483, 1065, 650), "top_left", dup=True),
        P("x_abdomen_c", "abdomen", (1065, 483, 1207, 650), "top_left", dup=True),
        P("x_abdomen_d", "abdomen", (1207, 483, 1372, 650), "top_left", dup=True),
        P("x_abdomen_e", "abdomen", (1372, 483, 1536, 650), "top_left", dup=True),
        P("x_head_a", "head", (0, 650, 183, 800), "neck", dup=True),
        P("x_head_b", "head", (183, 650, 352, 800), "neck", dup=True),
        P("x_head_c", "head", (352, 650, 527, 800), "neck", dup=True),
        P("x_leg_a", "leg", (0, 790, 165, 1024), "top", dup=True),
        P("x_leg_b", "leg", (165, 790, 310, 1024), "top", dup=True),
        P("x_leg_c", "leg", (310, 790, 466, 1024), "top", dup=True),
        P("x_leg_d", "leg", (466, 790, 633, 1024), "top", dup=True),
        P("x_leg_e", "leg", (633, 790, 790, 1024), "top", dup=True),
        P("x_antenna_a", "antenna", (790, 800, 865, 990), "top", dup=True),
        P("x_antenna_b", "antenna", (865, 800, 930, 990), "top", dup=True),
        P("x_antenna_c", "antenna", (930, 800, 1040, 990), "top", dup=True),
        P("x_antenna_d", "antenna", (1040, 800, 1090, 990), "top", dup=True),
        P("x_antenna_e", "antenna", (1090, 800, 1180, 990), "top", dup=True),
        P("wing_3_fore", "wing", (1190, 770, 1536, 1024), "left", dup=True,
          cut=[pair_cut((1190, 770, 1536, 1024), [(1190, 890), (1300, 890), (1400, 880), (1536, 870)])[0]]),
        P("wing_3_hind", "wing", (1190, 770, 1536, 1024), "left", dup=True,
          cut=[pair_cut((1190, 770, 1536, 1024), [(1190, 890), (1300, 890), (1400, 880), (1536, 870)])[1]]),
    ],
}


def assign_debug(sh, lab, specs, path):
    """Debug picture: the sheet with every piece tinted a different colour (untinted dark = dropped)."""
    import colorsys
    base = Image.new("RGBA", sh.size, (30, 30, 30, 255))
    base.alpha_composite(sh.im)
    base = base.convert("RGB").point(lambda v: v // 2)
    lp = lab.load()
    px = base.load()
    cols = []
    for i in range(len(specs)):
        r, g, b = colorsys.hsv_to_rgb((i * 0.137) % 1.0, 0.8, 1.0)
        cols.append((int(r * 255), int(g * 255), int(b * 255)))
    d = ImageDraw.Draw(base)
    w, h = sh.size
    # tint
    tint = Image.new("RGB", sh.size, (0, 0, 0))
    tp = tint.load()
    for y in range(h):
        for x in range(w):
            v = lp[x, y]
            if v:
                tp[x, y] = cols[v - 1]
    base = Image.blend(base, tint, 0.55)
    d = ImageDraw.Draw(base)
    f = ImageFont.load_default()
    for i, sp in enumerate(specs):
        m = lab.point(lambda v, n=i + 1: 255 if v == n else 0).getbbox()
        if m:
            d.text((m[0] + 3, m[1] + 3), sp["name"], fill=(255, 255, 255), font=f)
    # loose islands that went nowhere
    for c in sh.comps:
        if c["area"] >= 200 and lp[min(w - 1, int(c["cx"])), min(h - 1, int(c["cy"]))] == 0:
            d.rectangle(c["box"], outline=(255, 0, 0))
    base.save(path)


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

def build(contact=None, debug=None, only=None, sheets=None, dups=False):
    os.makedirs(OUT, exist_ok=True)
    partial = bool(only or sheets)
    if not partial:
        for fn in os.listdir(OUT):
            if fn.endswith(".png"):
                os.remove(os.path.join(OUT, fn))
    manifest = {"_about": "Ant part kit cut from art_src/antkit_*.png by tools/art/make_antkit.py. Every piece is a trimmed transparent PNG (2 px margin), long side <= %d px. "
                          "'pivot' is a suggested hinge in the piece's own pixels (legs: top joint; mandibles: where they attach; antennae: base; wings: root; "
                          "abdomens: front attachment; thorax/eggs/brood/misc: centre; heads: neck, the back of the head). Ants in the pictures face RIGHT. "
                          "_l/_r name the place on the sheet (a pair is two mirrored shapes: use flip_h for the other side). 'scale' is how much the piece was shrunk "
                          "from the sheet. Full bodies carry 'length' (nose to tail, antennae and leg tips excluded) and 'feet' (ground contact, bottom centre)." % MAXSIDE,
                "pieces": {}}
    if partial and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest["pieces"] = json.load(f).get("pieces", {})
    pieces = {}
    for key in SHEETS:
        if sheets and key not in sheets:
            continue
        specs = [sp for sp in CATALOGUE.get(key, []) if (dups or not sp.get("dup")) and (only is None or sp["name"] in only)]
        if not specs:
            continue
        sh = Sheet(key)
        lab, groups = sh.assign(specs)
        if debug:
            os.makedirs(debug, exist_ok=True)
            assign_debug(sh, lab, specs, os.path.join(debug, "assign_%s.png" % key))
        for i, sp in enumerate(specs):
            if not groups[i]:
                print("!! nothing found for", sp["name"])
                continue
            if sp["name"].startswith("_"):
                continue
            im = piece_image(sh, lab, i + 1, sp)
            if im is None:
                continue
            im = trim(im)
            im, k = shrink(im)
            piv = hinge(im, sp["pivot"])
            fn = sp["name"] + ".png"
            im.save(os.path.join(OUT, fn), optimize=True)
            ent = {"file": "antkit/" + fn, "w": im.size[0], "h": im.size[1], "kind": sp["kind"], "sheet": SHEETS[key],
                   "pivot": piv, "scale": round(k, 4)}
            if sp.get("dup"):
                ent["dup"] = True
            if sp["kind"] == "body":
                bm = body_metrics(im)
                ent["length"] = bm["length"]
                ent["nose_x"] = bm["nose_x"]
                ent["tail_x"] = bm["tail_x"]
                ent["feet"] = [piv[0], float(bm["ground_y"])]
                ent["pivot"] = [piv[0], float(bm["ground_y"])]
            manifest["pieces"][sp["name"]] = ent
            pieces[sp["name"]] = (im, ent)
            print("%-18s %4dx%-4d %s" % (sp["name"], im.size[0], im.size[1], "(x%.2f)" % k if k < 1 else ""))
    order = {sp["name"]: n for n, sp in enumerate(sum(CATALOGUE.values(), []))}
    manifest["pieces"] = dict(sorted(manifest["pieces"].items(), key=lambda kv: order.get(kv[0], 0)))
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT) if fn.endswith(".png"))
    print("%d pieces cut, %.2f MB in %s" % (len(pieces), total / 1048576.0, OUT))
    if contact:
        make_contact(pieces if partial or dups else {n: pieces[n] for n in pieces}, contact)
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
    dups = False
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
        elif a == "--dups":
            dups = True
    build(contact, debug, only, sheets, dups)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
