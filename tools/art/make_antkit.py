#!/usr/bin/env python3
"""Cut the owner's ANT PART KIT sheets (art_src/antkit_*.png) into single transparent PNGs for the game.

The five sheets are 1536x1024 (heads_a 1448x1086) RGBA pictures with real transparency: the owner's cut-outs, a thick near-black outline, flat
colour fill and nothing behind them.  So there is no background to remove and nothing is ever flood-filled: the matte is the sheet's own alpha.
  1. the alpha is cleaned: below DUST (10) is dust of the cut-out (the reddish haze round the parts) and becomes 0, its colour is wiped too;
     FILM (250) and up is solid (the solid pixels are 250-254 in these files) and becomes 255; the soft edge in between is kept as it is,
  2. the sheet is split into islands (8-connected pieces of the cleaned alpha).  A part that is an island of its own is taken whole: every piece
     names a box on its sheet and takes the islands whose middle lies in it.  Where two parts touch (one island holds both: a fore and a hind wing,
     two antennae, a spike clump and a fur tuft) the pieces give seed lines instead, and the island is shared out by a walk from the seeds in which
     a step onto the dark outline costs much more than a step over fill (`partition`), so the border falls in the middle of the outline between
     them; the outline itself is shared out by nearness to each part's fill, so each piece keeps its whole outline and none of its neighbour's,
     and a cut through an outline the two drawings share runs along the smoothed middle line and is anti-aliased (no stair steps, no bumps);
     the haze in a narrow gap between two outlines goes to neither part,
  3. a piece may lose its thin parts inside a box (the heads without antennae: the antenna stalks are cut off along the head's own outline,
     found by a morphological opening, and the cut ends are capped with outline colour) and may be mirrored (the full-sheet wing, so every wing
     has its root on the right),
  4. it is trimmed with a PAD px transparent margin, shrunk (premultiplied LANCZOS, so no dark fringe) so the long side is at most MAXSIDE px,
     the alpha is cleaned again (resampling ringing), the house outline ring goes on (creature_cuts.thicken: a soft RING px dilation in the
     sheet's own outline colour, but only round edges that are already outlined, so soft fur fades and see-through parts keep their look),
     specks are dropped, and fully clear pixels get the colour of the nearest visible pixel (no dark border when Godot filters the texture),
  5. saved as content/art/antkit/<name>.png (optimize=True), listed in content/art/antkit_manifest.json with its size, its hinge in the piece's own
     pixels and, for full bodies, nose, tail, nose-to-tail length and the ground line.

All ants in the kit face RIGHT.  Parts that are on several sheets are cut once, from the sheet with the largest, cleanest drawing.

Needs Pillow, numpy and scipy (like make_fx.py):   python3 tools/art/make_antkit.py [--contact PATH] [--debug DIR] [--only name,name]
  --contact PATH   also write the verification contact sheet (every piece on grey checker and on dark brown, labelled, hinge marked)
  --debug DIR      also write assign_<sheet>.png per sheet: which piece every pixel went to (grey = dropped)
  --only a,b       cut only these pieces (the manifest keeps the others' entries)
Does not import or touch make_art.py or art_manifest.json.
"""
import heapq
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "antkit")
MANIFEST = os.path.join(ART, "antkit_manifest.json")
MAXSIDE = 256        # longest side of a saved piece, margin included
PAD = 3              # transparent margin round every piece (room for the outline ring)
DUST = 10            # alpha below this is dust
FILM = 250           # alpha from this up is solid
MIN_ISLAND = 150     # islands smaller than this are dust (the real parts are all far bigger)
INK_MAX = 70         # a pixel whose brightest channel is under this is outline
INK_COST = 6.0       # walking onto outline costs this much more than walking over fill (partition)
SEAM_SOFT = 1.5      # sheet px: the anti-aliased width of the cut through a fused outline between two split parts
RING = 1             # px of outline ring added round every piece (after shrinking)
BLEED = 3            # px round a piece that get the colour of the nearest visible pixel

SHEETS = {
    "heads_a": "antkit_heads_a.png",
    "heads_b": "antkit_heads_b.png",
    "parts_a": "antkit_parts_a.png",
    "parts_b": "antkit_parts_b.png",
    "full": "antkit_full.png",
}


# ------------------------------------------------------------------------------------------------------------------ sheets

class Sheet:
    """One sheet: cleaned RGBA (numpy), its islands, its outline colour."""

    def __init__(self, key):
        self.key = key
        im = Image.open(os.path.join(SRC, SHEETS[key]))
        if im.mode != "RGBA":
            raise SystemExit("%s must be an RGBA picture with real transparency (it is %s)" % (SHEETS[key], im.mode))
        px = np.array(im)
        a = px[..., 3].astype(np.int32)
        a = np.where(a < DUST, 0, np.where(a >= FILM, 255, a)).astype(np.uint8)
        px[..., 3] = a
        px[a == 0, :3] = 0
        self.px = px
        self.a = a
        self.h, self.w = a.shape
        self.lab, n = ndi.label(a > 0, structure=np.ones((3, 3), bool))
        self.objs = ndi.find_objects(self.lab)
        self.area = ndi.sum(np.ones_like(a), self.lab, index=np.arange(1, n + 1)).astype(int) if n else np.zeros(0, int)
        self.ink_px = (px[..., :3].max(axis=2) < INK_MAX) & (a > 0)
        self.ink = edge_ink(px)

    def island_box(self, i):
        sl = self.objs[i - 1]
        return sl[1].start, sl[0].start, sl[1].stop, sl[0].stop

    def islands_in(self, box):
        """Islands (ids) of real size whose bounding-box middle lies inside box (x0, y0, x1, y1)."""
        out = []
        for i in range(1, len(self.objs) + 1):
            if self.area[i - 1] < MIN_ISLAND:
                continue
            x0, y0, x1, y1 = self.island_box(i)
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            if box[0] <= cx < box[2] and box[1] <= cy < box[3]:
                out.append(i)
        return out

    def island_at(self, x, y):
        """The island under (x, y), or the nearest one within 6 px (a seed point a hair off the drawing)."""
        x, y = int(round(x)), int(round(y))
        best = None
        for r in range(0, 7):
            ys, xs = slice(max(0, y - r), min(self.h, y + r + 1)), slice(max(0, x - r), min(self.w, x + r + 1))
            ids = self.lab[ys, xs]
            ids = ids[ids > 0]
            if ids.size:
                best = int(np.bincount(ids).argmax())
                break
        return best


def edge_ink(px):
    """The colour of the owner's outline: median of the outermost 3 px of the solid pixels (as creature_cuts.edge_ink)."""
    solid = px[..., 3] >= 250
    band = solid & ~ndi.binary_erosion(solid, structure=np.ones((3, 3), bool), iterations=3)
    if not band.any():
        return (21, 18, 26)
    return tuple(int(v) for v in np.median(px[band][:, :3], axis=0))


def disk(r):
    y, x = np.mgrid[-r:r + 1, -r:r + 1]
    return (x * x + y * y) <= r * r + r * 0.6


# ------------------------------------------------------------------------------------------------------------- partition

def partition(sh, island_ids, seeds):
    """Share the pixels of the islands out between parts.  seeds: list (one per part) of polylines [[(x, y), ...], ...] in sheet px.
    Multi-source shortest walk over the islands' own pixels (8-neighbour), a step onto outline costing INK_COST, onto fill 1: a pixel goes to
    the part whose seeds it reaches cheapest, so the border between two touching parts runs along the middle of the outline between them.
    Returns (box, [bool mask per part] in box coordinates)."""
    boxes = [sh.island_box(i) for i in island_ids]
    x0 = min(b[0] for b in boxes) - 1
    y0 = min(b[1] for b in boxes) - 1
    x1 = max(b[2] for b in boxes) + 1
    y1 = max(b[3] for b in boxes) + 1
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(sh.w, x1), min(sh.h, y1)
    isl = np.isin(sh.lab[y0:y1, x0:x1], island_ids)
    ink = sh.ink_px[y0:y1, x0:x1] & isl
    h, w = isl.shape
    W = w + 2
    cost = np.full((h + 2, W), -1.0)
    cost[1:-1, 1:-1] = np.where(isl, np.where(ink, INK_COST, 1.0), -1.0)
    cost = cost.ravel().tolist()
    dist = [1e18] * len(cost)
    label = [-1] * len(cost)
    heap = []
    for k, lines in enumerate(seeds):
        sm = Image.new("L", (w, h), 0)
        d = ImageDraw.Draw(sm)
        for line in lines:
            pts = [(x - x0, y - y0) for (x, y) in line]
            if len(pts) == 1:
                pts = pts * 2
            d.line(pts, fill=255, width=3)
        ys, xs = np.nonzero((np.array(sm) > 0) & isl)
        if len(ys) == 0:
            raise SystemExit("seed of part %d on %s lies on no island pixel: %s" % (k, sh.key, lines))
        for y, x in zip(ys.tolist(), xs.tolist()):
            j = (y + 1) * W + x + 1
            if dist[j] > 0:
                dist[j] = 0.0
                label[j] = k
                heap.append((0.0, j))
    heapq.heapify(heap)
    nb = ((1, 1.0), (-1, 1.0), (W, 1.0), (-W, 1.0), (W + 1, 1.4142), (W - 1, 1.4142), (-W + 1, 1.4142), (-W - 1, 1.4142))
    pop, push = heapq.heappop, heapq.heappush
    while heap:
        dd, i = pop(heap)
        if dd > dist[i]:
            continue
        li = label[i]
        for off, f in nb:
            j = i + off
            c = cost[j]
            if c < 0.0:
                continue
            nd = dd + c * f
            if nd < dist[j]:
                dist[j] = nd
                label[j] = li
                push(heap, (nd, j))
    lab = np.array(label, dtype=np.int32).reshape(h + 2, W)[1:-1, 1:-1]
    # the fill (everything that is not outline) goes by the walk; every outline pixel goes to the part whose fill is nearest, so each part keeps
    # its whole outline and none of its neighbour's (also where two outlines are fused into one band, or only touch through a soft bridge, as
    # the full-sheet wings do).  The cut through a fused outline runs along the smoothed middle line between the two fills and is anti-aliased
    # (a weight that ramps from 1 to 0 over about SEAM_SOFT px), so it has neither stair steps nor bumps of the painted outline.
    fills = [(lab == k) & ~ink for k in range(len(seeds))]
    dist = np.stack([ndi.distance_transform_edt(~f) if f.any() else np.full(isl.shape, 1e9) for f in fills])
    solid = sh.a[y0:y1, x0:x1] >= 128
    anyfill = np.zeros_like(isl)
    for f in fills:
        anyfill |= f
    out = []
    for k in range(len(seeds)):
        other = np.min(np.delete(dist, k, axis=0), axis=0)
        diff = ndi.gaussian_filter(np.clip(other - dist[k], -30, 30), 1.2)
        w = np.clip(diff / SEAM_SOFT + 0.5, 0.0, 1.0)
        w[fills[k]] = 1.0
        w[anyfill & ~fills[k]] = 0.0
        w[~isl] = 0.0
        m = w >= 0.5
        # crumbs: solid bits of the part not joined to its body (keep pieces of at least a twentieth of the biggest)
        cl, n = ndi.label(m & solid, structure=np.ones((3, 3), bool))
        if n > 1:
            sizes = ndi.sum(np.ones_like(cl), cl, index=np.arange(1, n + 1))
            keep = np.isin(cl, [i + 1 for i, s in enumerate(sizes) if s >= 0.05 * sizes.max()])
            w[~ndi.binary_dilation(keep, structure=np.ones((3, 3), bool), iterations=2)] = 0.0
        # soft pixels only as the part's own anti-aliased rim (the haze in a narrow gap between two outlines is nobody's)
        own_solid = (w >= 0.5) & solid
        if own_solid.any():
            w[~solid & (ndi.distance_transform_edt(~own_solid) > 1.5)] = 0.0
        out.append(w.astype(np.float32))
    return (x0, y0, x1, y1), out


# ------------------------------------------------------------------------------------------------------------- catalogue
# P(name, kind, sheet, box, pivot, ...):
#   box     the islands whose middle lies in it are the piece (sheet px); for a piece of a shared island give seeds=[polyline, ...] instead
#           (all pieces whose seeds lie on one island share it out between them)
#   pivot   (x, y) in sheet px, or a rule: "center" (middle of the solid pixels), "top"/"right"/... (middle of that end), "foot_left" (the end of
#           the left arm: base of an elbowed antenna), "base" (bottom edge under the middle of the lower third: a spine row), "neck" (back of a
#           head), "feet"
#   bare    (x0, y0, x1, y1, r): cut the antennae off a head inside this box (see strip_antennae)
#   flip    mirror left-right
#   pair    the other piece of a left/right pair

def P(name, kind, sheet, box=None, pivot="center", **kw):
    d = {"name": name, "kind": kind, "sheet": sheet, "box": box, "pivot": pivot}
    d.update(kw)
    return d


HINGE = {
    "head": "neck: the back of the head, where it joins the thorax",
    "mandible": "back attachment corner: middle of the blunt base end, opposite the tip",
    "thorax": "centre",
    "abdomen": "front attachment: the narrow capped end that joins the waist",
    "leg": "top joint: where the leg hangs from the body",
    "antenna": "base: the end that goes into the head socket",
    "wing": "root: the narrow end where the veins meet",
    "spine": "base: where it sits on the body",
    "plate": "centre",
    "eye": "centre",
    "fur": "centre",
    "egg": "centre",
    "larva": "centre",
    "pupa": "centre",
    "body": "feet: bottom centre of the ground contact",
}

CATALOGUE = [
    # ---- heads.  heads_a: small closed mandibles drawn on the face, antennae straight up (fit separate mandible pieces for big jaws);
    #      heads_b: open mandibles, antennae forward.  *_bare: the heads_a heads with their antennae cut off along the head outline (sockets kept).
    P("head_round", "head", "heads_a", (0, 150, 395, 720), "neck"),
    P("head_snout", "head", "heads_a", (395, 150, 745, 720), "neck"),
    P("head_beak", "head", "heads_a", (745, 150, 1100, 720), "neck"),
    P("head_armored", "head", "heads_a", (1100, 150, 1448, 720), "neck"),
    P("head_round_bare", "head", "heads_a", (0, 150, 395, 720), "neck", bare=(140, 170, 420, 540, 24)),
    P("head_snout_bare", "head", "heads_a", (395, 150, 745, 720), "neck", bare=(480, 170, 780, 540, 24)),
    P("head_beak_bare", "head", "heads_a", (745, 150, 1100, 720), "neck", bare=(840, 170, 1140, 540, 24)),
    P("head_armored_bare", "head", "heads_a", (1100, 150, 1448, 720), "neck", bare=(1190, 180, 1440, 540, 24)),
    P("head_round_jaws", "head", "heads_b", (0, 150, 399, 600), "neck"),
    P("head_long_jaws", "head", "heads_b", (399, 150, 745, 600), "neck"),
    P("head_bugeye_jaws", "head", "heads_b", (745, 150, 1110, 600), "neck"),
    P("head_horned_jaws", "head", "heads_b", (1110, 100, 1536, 600), "neck"),
    # ---- mandible pairs (_l / _r = left / right drawing of the pair on the sheet; they hang tip-down, the base cap on top)
    P("mandible_hook_l", "mandible", "heads_a", (0, 730, 170, 1050), (138, 822), pair="mandible_hook_r"),
    P("mandible_hook_r", "mandible", "heads_a", (170, 730, 340, 1050), (198, 822), pair="mandible_hook_l"),
    P("mandible_sickle_l", "mandible", "heads_a", (340, 730, 562, 1050), (468, 778), pair="mandible_sickle_r"),
    P("mandible_sickle_r", "mandible", "heads_a", (562, 730, 720, 1050), (606, 786), pair="mandible_sickle_l"),
    P("mandible_fang_l", "mandible", "heads_a", (720, 730, 905, 1050), (792, 772), pair="mandible_fang_r"),
    P("mandible_fang_r", "mandible", "heads_a", (905, 730, 1085, 1050), (945, 776), pair="mandible_fang_l"),
    P("mandible_crusher_l", "mandible", "heads_a", (1085, 730, 1284, 1050), (1190, 786), pair="mandible_crusher_r"),
    P("mandible_crusher_r", "mandible", "heads_a", (1284, 730, 1448, 1050), (1326, 782), pair="mandible_crusher_l"),
    P("mandible_small_l", "mandible", "heads_b", (0, 600, 194, 1000), (106, 712), pair="mandible_small_r"),
    P("mandible_small_r", "mandible", "heads_b", (194, 600, 330, 1000), (222, 706), pair="mandible_small_l"),
    P("mandible_claw_l", "mandible", "heads_b", (330, 600, 560, 1000), (405, 650), pair="mandible_claw_r"),
    P("mandible_claw_r", "mandible", "heads_b", (560, 600, 760, 1000), (566, 642), pair="mandible_claw_l"),
    P("mandible_trap_l", "mandible", "heads_b", (760, 600, 900, 1000), (810, 642), pair="mandible_trap_r"),
    P("mandible_trap_r", "mandible", "heads_b", (900, 600, 1125, 1000), (940, 634), pair="mandible_trap_l"),
    P("mandible_jagged_l", "mandible", "heads_b", (1125, 600, 1300, 1000), (1186, 656), pair="mandible_jagged_r"),
    P("mandible_jagged_r", "mandible", "heads_b", (1300, 600, 1536, 1000), (1336, 646), pair="mandible_jagged_l"),
    # ---- thoraxes: the tufted family (parts_a: big crest, dark leg knob), the lobed family (parts_b: round lobes), the spiked one (full sheet)
    P("thorax_tufted_1", "thorax", "parts_a", (0, 40, 262, 300)),
    P("thorax_tufted_2", "thorax", "parts_a", (262, 40, 500, 300)),
    P("thorax_tufted_3", "thorax", "parts_a", (500, 40, 760, 300)),
    P("thorax_lobed_1", "thorax", "parts_b", (0, 0, 240, 236)),
    P("thorax_lobed_2", "thorax", "parts_b", (240, 0, 442, 236)),
    P("thorax_lobed_3", "thorax", "parts_b", (442, 0, 634, 236)),
    P("thorax_lobed_4", "thorax", "parts_b", (634, 0, 830, 236)),
    P("thorax_spiked", "thorax", "full", seeds=[[(560, 560), (640, 570), (690, 585)], [(610, 520), (655, 520)]]),
    P("_head_spiky", "head", "full", seeds=[[(560, 720), (640, 735), (680, 722)], [(590, 690), (650, 690)]]),     # repeat of head_horned_jaws
    # ---- abdomens (front attachment top right, tail bottom left)
    P("abdomen_plain", "abdomen", "parts_a", (760, 40, 940, 340), (918, 90)),
    P("abdomen_slim", "abdomen", "parts_a", (940, 40, 1062, 340), (1059, 64)),
    P("abdomen_round", "abdomen", "parts_a", (1062, 40, 1214, 340), (1193, 74)),
    P("abdomen_spiked", "abdomen", "parts_a", (1214, 40, 1372, 340), (1322, 98)),
    P("abdomen_eggs", "abdomen", "parts_a", (1372, 30, 1536, 340), (1478, 62)),
    # ---- legs: five kinds (top joint at the apex of the thigh)
    P("leg_plain", "leg", "parts_a", (40, 300, 240, 700), (126, 330)),
    P("leg_spiny", "leg", "parts_a", (240, 300, 430, 700), (285, 330)),
    P("leg_flared", "leg", "parts_a", (430, 300, 626, 700), (470, 332)),
    P("leg_furry", "leg", "parts_a", (626, 300, 840, 700), (688, 332)),
    P("leg_armored", "leg", "parts_a", (840, 300, 1070, 700), (884, 340)),
    # ---- antennae.  Elbowed ones stand as an upside-down V: base at the foot of the left arm, tip at the foot of the right arm (in front of
    #      the face of a right-facing ant).  _l / _r: two drawings of one kind (near and far antenna); the others are single drawings.
    P("antenna_plain_l", "antenna", "parts_a", (1100, 340, 1335, 545), "foot_left", pair="antenna_plain_r"),
    P("antenna_plain_r", "antenna", "parts_a", (1100, 545, 1335, 780), "foot_left", pair="antenna_plain_l"),
    P("antenna_feather_l", "antenna", "parts_a", (1335, 340, 1536, 545), "foot_left", pair="antenna_feather_r"),
    P("antenna_feather_r", "antenna", "parts_a", (1335, 545, 1536, 780), "foot_left", pair="antenna_feather_l"),
    P("antenna_club_l", "antenna", "parts_b", (960, 270, 1140, 400), "foot_left", pair="antenna_club_r"),
    P("antenna_club_r", "antenna", "parts_b", (960, 400, 1115, 600), "foot_left", pair="antenna_club_l"),
    P("antenna_beaded_l", "antenna", "full", seeds=[[(944, 822), (948, 880), (960, 930), (970, 975)]], pivot="top", pair="antenna_beaded_r"),
    P("antenna_beaded_r", "antenna", "full", seeds=[[(968, 830), (995, 880), (1010, 930), (1025, 975)]], pivot="top", pair="antenna_beaded_l"),
    P("antenna_whip", "antenna", "parts_b", seeds=[[(1165, 345), (1250, 292), (1330, 300), (1358, 340), (1368, 395)]], pivot="foot_left"),
    P("antenna_elbow", "antenna", "parts_b", seeds=[[(1387, 395), (1387, 310), (1420, 300), (1480, 340), (1508, 425)]], pivot="foot_left"),
    P("antenna_bigclub", "antenna", "parts_b", seeds=[[(1160, 410), (1195, 368), (1260, 400), (1300, 420), (1325, 440), (1340, 488)]], pivot="foot_left"),
    P("antenna_fern", "antenna", "parts_b", seeds=[[(1356, 560), (1360, 500), (1375, 455), (1398, 435), (1440, 470), (1470, 530), (1468, 580)]], pivot="foot_left"),
    P("antenna_segclub", "antenna", "parts_b", (1115, 445, 1330, 605), "foot_left"),
    # ---- wings (_fore / _hind); root (veins meet) on the right, rounded tip on the left
    P("wing_veined_fore", "wing", "parts_a", (40, 690, 590, 820), "right", pair="wing_veined_hind"),
    P("wing_veined_hind", "wing", "parts_a", (40, 820, 590, 1000), "right", pair="wing_veined_fore"),
    P("wing_cell_fore", "wing", "parts_a", seeds=[[(700, 760), (900, 770), (1090, 790)]], pivot="right", pair="wing_cell_hind"),
    P("wing_cell_hind", "wing", "parts_a", seeds=[[(720, 920), (900, 890), (1090, 850)]], pivot="right", pair="wing_cell_fore"),
    P("wing_long_fore", "wing", "parts_b", seeds=[[(500, 575), (700, 565), (950, 552)]], pivot="right", pair="wing_long_hind"),
    P("wing_long_hind", "wing", "parts_b", seeds=[[(510, 670), (700, 650), (950, 600)]], pivot="right", pair="wing_long_fore"),
    P("wing_short_fore", "wing", "full", seeds=[[(1262, 830), (1380, 815), (1500, 805)]], pivot="right", flip=True, pair="wing_short_hind"),
    P("wing_short_hind", "wing", "full", seeds=[[(1240, 905), (1380, 925), (1500, 940)]], pivot="right", flip=True, pair="wing_short_fore"),
    # ---- spines, horns, sting, frill and plates
    P("sting", "spine", "parts_b", (0, 720, 121, 1010), (60, 745)),
    P("spine_hook", "spine", "parts_b", (121, 720, 220, 1010), (150, 860)),
    P("horn_small", "spine", "parts_b", (220, 740, 300, 893), (238, 840)),
    P("horn_long", "spine", "parts_b", (300, 705, 440, 930), (320, 835)),
    P("horn_curl", "spine", "parts_b", (220, 893, 380, 1010), (262, 905)),
    P("frill", "spine", "parts_b", (345, 835, 545, 1010), "top"),
    P("spine_ridge", "spine", "parts_b", (560, 850, 845, 1015), "base"),
    P("spine_backbone", "spine", "parts_b", (776, 700, 1070, 892), "center"),
    P("spine_crest", "spine", "parts_b", (940, 580, 1140, 782), "base"),
    P("spine_crest_tall", "spine", "parts_b", (1140, 570, 1305, 782), "base"),
    P("spine_trio", "spine", "parts_b", (1075, 770, 1187, 887), "base"),
    P("spine_cluster", "spine", "parts_b", (995, 879, 1187, 1015), "base"),
    P("spine_knob", "spine", "parts_b", seeds=[[(1200, 950), (1260, 960), (1290, 980)], [(1215, 880), (1225, 920)]], pivot="center"),
    P("plate_fringed", "plate", "parts_b", (425, 705, 595, 860)),
    P("plate_spiked", "plate", "parts_b", (595, 720, 776, 900)),
    P("plate_lobes", "plate", "parts_b", (1185, 745, 1316, 845)),
    # ---- eyes and fur tufts
    P("eye_glossy", "eye", "parts_b", (1325, 765, 1426, 875)),
    P("eye_compound", "eye", "parts_b", (1426, 765, 1536, 875)),
    P("fur_puff", "fur", "parts_b", (1300, 595, 1420, 765)),
    P("fur_leaf", "fur", "parts_b", (1420, 595, 1536, 765)),
    P("fur_tuft", "fur", "parts_b", seeds=[[(1340, 950), (1380, 940), (1410, 960)]]),
    P("fur_tuft_small", "fur", "parts_b", seeds=[[(1455, 950), (1490, 945), (1505, 960)]]),
    # ---- full bodies (facing right)
    P("queen_full", "body", "full", (0, 0, 640, 310), "feet", nose=(569, 176), tail=(8, 175)),
    P("alate_full", "body", "full", (640, 0, 1050, 310), "feet", nose=(1024, 180), tail=(740, 230)),
    P("soldier_full", "body", "full", (1050, 0, 1320, 310), "feet", nose=(1290, 196), tail=(1090, 205)),
    P("worker_full", "body", "full", (1320, 150, 1536, 310), "feet", nose=(1494, 225), tail=(1338, 242)),
    P("worker_small_full", "body", "full", (806, 330, 1040, 485), "feet", nose=(975, 415), tail=(818, 436)),
    # ---- eggs, larvae, pupae (cocoons)
    P("egg_cluster", "egg", "full", (0, 300, 236, 485)),
    P("egg_mass", "egg", "parts_b", (815, 815, 995, 1010)),
    P("larva_curled", "larva", "full", (236, 300, 385, 485)),
    P("larva_fat", "larva", "full", (385, 300, 610, 485)),
    P("cocoon_cream", "pupa", "full", (610, 295, 806, 485)),
    P("cocoon_grey", "pupa", "full", (1040, 295, 1250, 485)),
    P("cocoon_winged", "pupa", "full", (1250, 295, 1536, 485)),
]

# islands that are on the sheets but deliberately not cut (repeats of parts cut from a bigger drawing elsewhere); listed so the run can warn
# about any island that is neither cut nor known
REPEATS = {
    "parts_b": [(0, 230, 965, 535, "legs (the parts_a legs are bigger)"), (842, 0, 1536, 275, "abdomens (parts_a)"),
                (15, 520, 440, 735, "veined wing pair (parts_a)")],
    "full": [(0, 483, 527, 650, "tufted thoraxes (parts_a)"), (730, 483, 1536, 650, "abdomens (parts_a)"), (0, 640, 930, 800, "heads (heads_b)"),
             (930, 640, 1536, 812, "mandibles (heads_a/b)"), (0, 785, 795, 1024, "legs (parts_a)"), (785, 800, 935, 990, "plain antennae (parts_a)"),
             (995, 800, 1180, 990, "feathered antennae (parts_a)")],
}


# ------------------------------------------------------------------------------------------------------------------ pieces

def assign(sh, specs):
    """Masks (sheet-sized bool) per spec of this sheet: whole islands by box, shared islands by partition."""
    masks = {}
    shared = {}                      # island id -> [(spec, seed lines)]
    for sp in sorted(specs, key=lambda s: not s.get("seeds")):        # seeded pieces first: their islands are not up for grabs by boxes
        if sp.get("seeds"):
            # the islands under the seed lines (a line may cross a gap of the drawing; it must not touch a neighbour's island)
            sm = Image.new("L", (sh.w, sh.h), 0)
            d = ImageDraw.Draw(sm)
            for line in sp["seeds"]:
                d.line([tuple(p) for p in (line if len(line) > 1 else line * 2)], fill=255, width=3)
            under = sh.lab[np.array(sm) > 0]
            ids = set(int(i) for i in np.unique(under) if i and sh.area[i - 1] >= MIN_ISLAND)
            if not ids:
                raise SystemExit("%s: its seed lines lie on no island" % sp["name"])
            for i in ids:
                shared.setdefault(i, []).append(sp)
        else:
            ids = [i for i in sh.islands_in(sp["box"]) if i not in shared]
            if not ids:
                print("!! %s: no island in %s" % (sp["name"], sp["box"]))
                continue
            masks[sp["name"]] = np.isin(sh.lab, ids)
    # islands shared by several pieces: one partition per group of pieces (pieces may span several islands)
    groups = []
    for i, sps in shared.items():
        names = tuple(sorted(s["name"] for s in sps))
        for g in groups:
            if set(g["names"]) & set(names):
                g["ids"].add(i)
                g["names"] = tuple(sorted(set(g["names"]) | set(names)))
                break
        else:
            groups.append({"ids": {i}, "names": names})
    byname = {sp["name"]: sp for sp in specs}
    for g in groups:
        sps = [byname[n] for n in g["names"]]
        # an island that only one piece seeds: the piece takes it whole
        if len(sps) == 1:
            masks[sps[0]["name"]] = np.isin(sh.lab, list(g["ids"]))
            continue
        # every part of a shared island needs seeds, also a part that is not saved (a "_" piece: a repeat stuck to a wanted part)
        (x0, y0, x1, y1), pm = partition(sh, sorted(g["ids"]), [s["seeds"] for s in sps])
        for s, m in zip(sps, pm):
            full = np.zeros((sh.h, sh.w), np.float32)      # a weight 0..1 (anti-aliased seam), not a plain mask
            full[y0:y1, x0:x1] = m
            masks[s["name"]] = full
    return masks


def strip_antennae(sh, mask, sp):
    """Cut the antennae off a head along the head's own outline.  Inside the box sp['bare'] = (x0, y0, x1, y1, r), what does not survive a
    morphological opening with a disk of radius r (the thin antenna stalks; the head itself is far wider) and forms a big piece (area >= 1500:
    not a fur spike) is removed; the stub that lies over the face stays, and the cut ends get a cap of outline colour so they read as closed.
    Returns (mask, cap)."""
    x0, y0, x1, y1, r = sp["bare"]
    sub = mask[y0:y1, x0:x1] & (sh.a[y0:y1, x0:x1] >= 128)
    opened = ndi.binary_opening(sub, structure=disk(r))
    opened = ndi.binary_dilation(opened, structure=disk(2)) & sub
    thin = sub & ~opened
    lab, n = ndi.label(thin, structure=np.ones((3, 3), bool))
    cut = np.zeros_like(sub)
    for i in range(1, n + 1):
        part = lab == i
        if part.sum() >= 1500:
            cut |= part
    # the soft edge round a removed antenna goes too
    cut = ndi.binary_dilation(cut, structure=disk(2)) & mask[y0:y1, x0:x1]
    full_cut = np.zeros_like(mask)
    full_cut[y0:y1, x0:x1] = cut
    kept = mask & ~full_cut
    # only the head itself: the biggest connected piece (antenna tips wide enough to survive the opening go)
    lab, n = ndi.label(kept & (sh.a > 0), structure=np.ones((3, 3), bool))
    if n > 1:
        sizes = ndi.sum(np.ones_like(lab), lab, index=np.arange(1, n + 1))
        kept = lab == (int(np.argmax(sizes)) + 1)
    removed = mask & ~kept
    # where an antenna base hid the head's contour, the contour steps: the removed pixels a closing of the head fills go back, as outline
    sub_kept = kept[y0:y1, x0:x1]
    closed = ndi.binary_closing(np.pad(sub_kept, 40), structure=disk(26))[40:-40, 40:-40]
    fill = np.zeros_like(mask)
    fill[y0:y1, x0:x1] = closed & removed[y0:y1, x0:x1]
    kept = kept | fill
    removed = mask & ~kept
    cap = kept & ((ndi.distance_transform_edt(~removed) <= sp.get("cap", 5)) | fill) & (sh.a > 0)
    return kept, cap


def piece_rgba(sh, mask, sp):
    """Cut, trim, shrink, ring, despeckle, bleed.  Returns (PIL RGBA, transform: sheet (x, y) -> piece (x, y))."""
    px = sh.px.copy()
    if sp.get("bare"):
        mask, cap = strip_antennae(sh, mask, sp)
        px[cap, 0], px[cap, 1], px[cap, 2] = sh.ink
    wgt = mask.astype(np.float32)                 # bool mask, or the 0..1 weight of a split piece
    ys, xs = np.nonzero((wgt > 0) & (sh.a > 0))
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    crop = px[y0:y1, x0:x1].copy()
    crop[..., 3] = np.round(crop[..., 3] * wgt[y0:y1, x0:x1]).astype(np.uint8)
    crop[crop[..., 3] == 0, :3] = 0
    flip = bool(sp.get("flip"))
    if flip:
        crop = crop[:, ::-1].copy()
    w, h = x1 - x0, y1 - y0
    k = min(1.0, (MAXSIDE - 2 * PAD) / float(max(w, h)))
    im = Image.fromarray(crop, "RGBA")
    if k < 1.0:
        nw, nh = max(1, int(round(w * k))), max(1, int(round(h * k)))
        im = im.resize((nw, nh), Image.LANCZOS)      # Pillow premultiplies RGBA for this
    else:
        nw, nh = w, h
    kx, ky = nw / float(w), nh / float(h)
    arr = np.zeros((nh + 2 * PAD, nw + 2 * PAD, 4), np.uint8)
    arr[PAD:PAD + nh, PAD:PAD + nw] = np.array(im)
    arr = finish(arr, sh.ink)

    def xf(x, y):
        lx = (x - x0) if not flip else (x1 - x)
        return [round(lx * kx + PAD, 1), round((y - y0) * ky + PAD, 1)]
    return Image.fromarray(arr, "RGBA"), xf, (int(x0), int(y0), int(x1), int(y1)), k


def finish(arr, ink):
    """Alpha cleanup after resampling, the outline ring, despeckle, colour bleed under clear pixels."""
    a = arr[..., 3].astype(np.float64)
    a[a < DUST] = 0
    a[a >= FILM] = 255
    rgb = arr[..., :3].astype(np.float64)
    # outline ring (creature_cuts.thicken): soft dilation by RING px in the outline colour, only round edges that are outline already
    lum = rgb.max(axis=2)
    dark = (a > 24) & (lum < 110)
    if RING > 0 and dark.any():
        grown = ndi.binary_dilation(dark, structure=disk(RING))
        ring = ndi.gaussian_filter(grown.astype(np.float64) * 255.0, 0.6)
        ring = np.where(grown | (ring > 0), ring, 0)
        ring = np.minimum(255.0, np.maximum(ring, 0))
        af = a / 255.0
        rf = ring / 255.0
        oa = af + rf * (1 - af)
        safe = np.maximum(oa, 1e-6)[..., None]
        rgb = (rgb * af[..., None] + np.array(ink, np.float64) * (rf * (1 - af))[..., None]) / safe
        a = oa * 255.0
    a = np.clip(np.round(a), 0, 255)
    a[a < DUST] = 0
    # specks: tiny islands that are not part of the piece (resampling crumbs)
    lab, n = ndi.label(a > 0, structure=np.ones((3, 3), bool))
    if n > 1:
        sizes = ndi.sum(np.ones_like(a), lab, index=np.arange(1, n + 1))
        big = sizes.max()
        for i, s in enumerate(sizes):
            if s < max(30, 0.003 * big):
                a[lab == i + 1] = 0
    vis = a > 0
    # bleed: clear pixels near the piece take the colour of the nearest visible pixel (so a filtered texture never blends in black)
    if vis.any():
        dist, (iy, ix) = ndi.distance_transform_edt(~vis, return_indices=True)
        near = (~vis) & (dist <= BLEED)
        rgb[near] = rgb[iy[near], ix[near]]
        rgb[(~vis) & ~near] = 0
    out = np.zeros(arr.shape, np.uint8)
    out[..., :3] = np.clip(np.round(rgb), 0, 255)
    out[..., 3] = a
    return out


# ------------------------------------------------------------------------------------------------------------------ hinges

DIRS = {"top": (0, -1), "bottom": (0, 1), "left": (-1, 0), "right": (1, 0), "top_left": (-1, -1), "top_right": (1, -1),
        "bottom_left": (-1, 1), "bottom_right": (1, 1)}


def hinge(im, rule, frac=0.06):
    a = np.array(im)[..., 3]
    ys, xs = np.nonzero(a > 128)
    h, w = a.shape
    if len(xs) == 0:
        return [w / 2.0, h / 2.0]
    if rule == "center":
        return [round(float(xs.mean()), 1), round(float(ys.mean()), 1)]
    if rule == "neck":
        # back of the head: the left end of the lower half of the head (the antennae are above), at the height of the middle of that end
        sel = ys > ys.min() + 0.45 * (ys.max() - ys.min())
        bx, by = xs[sel], ys[sel]
        x0 = bx.min()
        span = bx.max() - x0
        rear = bx < x0 + 0.10 * span
        return [round(float(x0 + 0.08 * span), 1), round(float(by[rear].mean()), 1)]
    if rule == "feet":
        low = ys >= ys.max() - 3
        return [round(float(xs[low].mean()), 1), float(ys.max() + 1)]
    if rule == "foot_left":
        # the left arm of an upside-down V: the lowest pixels of the left third
        left = xs < xs.min() + 0.33 * (xs.max() - xs.min())
        lx, ly = xs[left], ys[left]
        sel = ly >= ly.max() - 0.06 * (ys.max() - ys.min())
        return [round(float(lx[sel].mean()), 1), round(float(ly[sel].mean()), 1)]
    if rule == "base":
        # the strip a spine row or clump stands on: the middle x of its lower third, at the bottom edge there (inside the outline)
        sel = ys >= ys.max() - 0.33 * (ys.max() - ys.min())
        bx = float(xs[sel].mean())
        col = np.abs(xs - bx) <= 3
        return [round(bx, 1), round(float(ys[col].max()) - 4.0, 1)]
    dx, dy = DIRS[rule]
    sc = xs * dx + ys * dy
    lo, hi = sc.min(), sc.max()
    sel = sc >= hi - frac * (hi - lo)
    return [round(float(xs[sel].mean()), 1), round(float(ys[sel].mean()), 1)]


def body_metrics(im, xf, sp):
    """Nose, tail (hand-placed on the sheet, the ends of the body without antennae, mandible tips or wings), length, ground line and the x of
    every foot on the ground."""
    a = np.array(im)[..., 3]
    ys, xs = np.nonzero(a > 128)
    ground = int(ys.max()) + 1
    nose = xf(*sp["nose"])
    tail = xf(*sp["tail"])
    # feet on the ground: runs of solid pixels in the bottom band (5% of the height, at least 4 px): every foot that touches the ground
    band = max(4, int(round(0.05 * (ground - ys.min()))))
    low = a[ground - band:ground].max(axis=0) > 128
    feet = []
    x = 0
    while x < len(low):
        if low[x]:
            s = x
            while x < len(low) and low[x]:
                x += 1
            feet.append(round((s + x - 1) / 2.0, 1))
        x += 1
    mid = round((feet[0] + feet[-1]) / 2.0, 1) if feet else round(float(xs.mean()), 1)
    return {"nose": nose, "tail": tail, "length": round(abs(nose[0] - tail[0]), 1), "ground_y": float(ground), "feet_x": feet, "feet": [mid, float(ground)]}


# ------------------------------------------------------------------------------------------------------------------ build

def build(contact=None, debug=None, only=None):
    os.makedirs(OUT, exist_ok=True)
    if only is None:
        for fn in os.listdir(OUT):
            if fn.endswith(".png"):
                os.remove(os.path.join(OUT, fn))
    old = {}
    if only is not None and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            old = json.load(f).get("pieces", {})
    pieces = {}
    entries = dict(old)
    for key in SHEETS:
        specs = [sp for sp in CATALOGUE if sp["sheet"] == key]
        if only is not None and not any(sp["name"] in only for sp in specs):
            continue
        sh = Sheet(key)
        masks = assign(sh, specs)          # always all pieces of the sheet: shared islands are shared out the same way every run
        if debug:
            os.makedirs(debug, exist_ok=True)
            assign_debug(sh, masks, specs, os.path.join(debug, "assign_%s.png" % key))
        if only is None:
            check_coverage(sh, masks)
        for sp in specs:
            if only is not None and sp["name"] not in only:
                continue
            if sp["name"] not in masks or sp["name"].startswith("_"):
                continue
            im, xf, src, k = piece_rgba(sh, masks[sp["name"]], sp)
            if isinstance(sp["pivot"], tuple):
                piv = xf(*sp["pivot"])
            else:
                piv = hinge(im, sp["pivot"])
            fn = sp["name"] + ".png"
            im.save(os.path.join(OUT, fn), optimize=True)
            ent = {"file": "antkit/" + fn, "w": im.size[0], "h": im.size[1], "kind": sp["kind"], "pivot": piv,
                   "sheet": SHEETS[key], "src": list(src), "scale": round(k, 4)}
            if sp.get("pair"):
                ent["pair"] = sp["pair"]
            if sp.get("flip"):
                ent["mirrored"] = True
            if sp.get("bare"):
                ent["antennae_removed"] = True
            if sp["kind"] == "body":
                bm = body_metrics(im, xf, sp)
                ent.update(bm)
                ent["pivot"] = list(bm["feet"])
            entries[sp["name"]] = ent
            pieces[sp["name"]] = (im, ent)
            print("%-20s %4dx%-4d %s" % (sp["name"], im.size[0], im.size[1], "(x%.2f)" % k if k < 1 else ""))
    order = {sp["name"]: n for n, sp in enumerate(CATALOGUE)}
    entries = {n: entries[n] for n in sorted(entries, key=lambda n: order.get(n, 10 ** 6)) if n in order}
    kinds = {}
    for n, e in entries.items():
        kinds.setdefault(e["kind"], []).append(n)
    manifest = {
        "_about": "Ant part kit cut from art_src/antkit_*.png by tools/art/make_antkit.py. Every piece is a trimmed transparent PNG with a %d px "
                  "margin, long side <= %d px. All ants face RIGHT. 'pivot' is the suggested hinge in the piece's own pixels (see 'hinges'). "
                  "_l/_r are the two drawings of a pair (mandibles: left and right jaw; antennae: near and far), 'pair' names the other one; flip_h "
                  "a piece for the other side when a kind has one drawing. _fore/_hind: front and back wing. 'scale' is how much the piece was "
                  "shrunk from its sheet, 'src' its box on the sheet. Full bodies also carry nose and tail (ends of the body, antennae, mandible "
                  "tips and wings left out), 'length' (nose to tail, px), 'ground_y' (the ground line: bottom of the lowest foot) and 'feet_x' "
                  "(x of each foot touching the ground); 'feet' = 'pivot' = the middle of the feet on the ground line." % (PAD, MAXSIDE),
        "hinges": HINGE,
        "kinds": kinds,
        "pieces": entries,
    }
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT) if fn.endswith(".png"))
    print("%d pieces cut, folder %.2f MB (%d files)" % (len(pieces), total / 1048576.0, len([f for f in os.listdir(OUT) if f.endswith(".png")])))
    if contact:
        make_contact({n: pieces[n] for n in sorted(pieces, key=lambda n: order.get(n, 10 ** 6))}, contact)
    return pieces


def check_coverage(sh, masks):
    """Warn about real islands that no piece took and that are not known repeats."""
    taken = np.zeros((sh.h, sh.w), bool)
    for m in masks.values():
        taken |= m > 0.5
    for i in range(1, len(sh.objs) + 1):
        if sh.area[i - 1] < MIN_ISLAND:
            continue
        isl = (sh.lab == i) & (sh.a >= 128)          # solid pixels: the soft haze in a gap between two parts belongs to neither
        share = (isl & taken).sum() / float(max(1, isl.sum()))
        x0, y0, x1, y1 = sh.island_box(i)
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        if share < 0.98:
            known = [r[4] for r in REPEATS.get(sh.key, []) if r[0] <= cx < r[2] and r[1] <= cy < r[3]]
            if share == 0 and known:
                continue
            print("  ?? %s island %d %s: %.0f%% cut%s" % (sh.key, i, (x0, y0, x1, y1), share * 100, " (repeat: %s)" % known[0] if known else ""))


def assign_debug(sh, masks, specs, path):
    import colorsys
    base = np.full((sh.h, sh.w, 3), 235, np.float64)
    af = (sh.a / 255.0)[..., None]
    grey = sh.px[..., :3].mean(axis=2, keepdims=True) * 0.6 + 60
    base = base * (1 - af) + grey * af
    img = Image.fromarray(base.astype(np.uint8))
    d = ImageDraw.Draw(img)
    over = np.zeros((sh.h, sh.w, 3), np.float64)
    cover = np.zeros((sh.h, sh.w), bool)
    for n, sp in enumerate(specs):
        m = masks.get(sp["name"])
        if m is None:
            continue
        m = m > 0.5
        r, g, b = colorsys.hsv_to_rgb((n * 0.137) % 1.0, 0.75, 1.0)
        over[m & ~cover] = (r * 255, g * 255, b * 255)
        over[m & cover] = (255, 0, 0)          # pixel in two pieces (a shared rim)
        cover |= m
    arr = np.array(img).astype(np.float64)
    sel = cover & (sh.a > 0)
    arr[sel] = arr[sel] * 0.45 + over[sel] * 0.55
    img = Image.fromarray(arr.astype(np.uint8))
    d = ImageDraw.Draw(img)
    for sp in specs:
        m = masks.get(sp["name"])
        if m is None:
            continue
        ys, xs = np.nonzero(m > 0.5)
        d.text((int(xs.min()) + 2, int(ys.min()) + 2), sp["name"], fill=(0, 0, 0))
    img.save(path)


# ------------------------------------------------------------------------------------------------------------------ contact

def _checker(w, h, a=(170, 170, 170), b=(130, 130, 130), cell=10):
    y, x = np.mgrid[0:h, 0:w]
    m = ((x // cell + y // cell) % 2).astype(bool)
    out = np.empty((h, w, 3), np.uint8)
    out[~m] = a
    out[m] = b
    return Image.fromarray(out)


def make_contact(pieces, path, cols=4):
    """Every piece at 1:1, twice: on grey checker (hinge marked: red ring with a yellow dot; bodies: nose/tail ticks and the ground line) and
    on dark brown (clean, to look for halos and fringes), with its name and size."""
    f = ImageFont.load_default()
    names = list(pieces)
    cw = 2 * (MAXSIDE + 8) + 12
    rows = []
    for r in range(0, len(names), cols):
        grp = names[r:r + cols]
        rows.append((grp, max(pieces[n][0].size[1] for n in grp) + 26))
    W = cols * cw
    H = sum(h for _, h in rows) + 4
    sheet = Image.new("RGB", (W, H), (34, 34, 38))
    d = ImageDraw.Draw(sheet)
    y = 2
    for grp, rh in rows:
        for c, n in enumerate(grp):
            im, ent = pieces[n]
            x0 = c * cw + 4
            for j in range(2):
                bw, bh = MAXSIDE + 8, rh - 20
                bg = _checker(bw, bh) if j == 0 else Image.new("RGB", (bw, bh), (66, 44, 30))
                bg = bg.convert("RGBA")
                ox, oy = (bw - im.size[0]) // 2, 4
                bg.alpha_composite(im, (ox, oy))
                dd = ImageDraw.Draw(bg)
                if j == 0:
                    px, py = ent["pivot"]
                    cx, cy = ox + px, oy + py
                    dd.ellipse((cx - 4, cy - 4, cx + 4, cy + 4), outline=(255, 0, 0, 255))
                    dd.ellipse((cx - 1, cy - 1, cx + 1, cy + 1), fill=(255, 255, 0, 255))
                    if ent["kind"] == "body":
                        gy = oy + ent["ground_y"]
                        dd.line((ox, gy, ox + im.size[0], gy), fill=(0, 200, 255, 255))
                        for key in ("nose", "tail"):
                            nx, ny = ent[key]
                            dd.line((ox + nx, oy + ny - 8, ox + nx, oy + ny + 8), fill=(255, 0, 255, 255), width=2)
                sheet.paste(bg.convert("RGB"), (x0 + j * (bw + 4), y + 16))
            d.text((x0, y + 3), "%s  %dx%d" % (n, im.size[0], im.size[1]), fill=(255, 255, 255), font=f)
        y += rh
    sheet.save(path)
    print("contact sheet:", path, sheet.size)


def main(argv):
    contact = debug = only = None
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--contact":
            contact = args.pop(0)
        elif a == "--debug":
            debug = args.pop(0)
        elif a == "--only":
            only = set(args.pop(0).split(","))
        else:
            raise SystemExit(__doc__)
    build(contact, debug, only)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
