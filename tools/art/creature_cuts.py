#!/usr/bin/env python3
"""The cutting of the drawn creature art (everything except the trees): spider, Void Maw, bird, rocks.

Used by make_art.py. The pictures in art_src/ are one drawing per layer (a body, two sets of legs ...); this file cuts them into the pieces the game
puts back together (content/art/*.png + art_manifest.json): every leg on its own with a hinge at its top, the jaw or fangs on a pivot, the dark of the
throat behind them. Pillow only (no numpy).

How a piece is cut, in short:
  * `thicken` puts the dark outline round every shape (round, not square) so it still reads small.
  * legs: the drawn legs overlap each other (one set is a tangle of bones), so they cannot be found as separate blobs. Instead each leg gets a few
    seed points / lines (CREATURES[...]["legs"], in the pixels of the art_src picture) and every pixel goes to the leg it is nearest to when walking
    over the picture with the dark outlines costing more to cross than bone does (`partition`): the border between two legs falls in the middle of
    the outline between them. Every leg then also keeps a thin rim of its neighbours' outline, so its own outline stays closed when it swings.
  * fangs: cut out by colour (the cream) together with their own outline ring, never any of the fur round them.
  * jaw of the Void Maw: a hand drawn polygon that follows the dark of the throat, minus the upper teeth.
"""
import heapq
import json
import os
from collections import deque

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageOps

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
INK = (21, 18, 26)

# name -> working width, extra outline (px at that width), game length (px nose to tail at scale 1), draw order, glow
# "legs": for each legs picture (art_src/<file>.png) the legs from back to front (the order they are drawn in); a leg is a list of lines
#         (each a list of (x, y) points in picture pixels, laid along the bones of that leg); the first point of the first line is the hinge.
CREATURES = {
    "spider": {"width": 724, "outline": 4, "length": 120.0, "order": ["far", "body", "near"], "glow": False,
               # the cream fangs, cut out by colour inside this box (body-picture pixels) and hinged at their tops; `open` is per fang from left to right
               "jaws": {"kind": "color", "box": [420, 305, 581, 452], "open": [0.2, -0.16, -0.2], "cavity": None, "ring": 13},
               "wave": False,
               "legs": {
                   "spider_legs_a": [
                       {"name": "hind", "lines": [[(552, 392), (560, 450), (590, 520), (625, 560), (630, 620), (610, 680)]]},
                       {"name": "front", "lines": [[(266, 548), (205, 610), (175, 650), (130, 740), (115, 820), (80, 960)]]},
                       {"name": "mid", "lines": [[(515, 388), (450, 425), (400, 480), (375, 560), (345, 640), (330, 720), (320, 790), (318, 880), (325, 950)]]},
                       {"name": "rear", "pivot": (1135, 372), "lines": [[(1100, 380), (1070, 450), (1060, 520)], [(1150, 372), (1200, 420), (1200, 500), (1215, 600)],
                                                                    [(1290, 520), (1340, 600), (1380, 690), (1375, 760), (1350, 850)]]},
                   ],
                   "spider_legs_b": [
                       {"name": "hind", "lines": [[(552, 392), (580, 440), (595, 500), (570, 570)], [(650, 545), (690, 600), (700, 680), (730, 760), (790, 860), (850, 960), (880, 1000)],
                                                  [(780, 570), (800, 640), (790, 720)]]},
                       {"name": "front", "lines": [[(266, 548), (205, 610), (175, 650), (130, 740), (115, 820), (80, 960)]]},
                       {"name": "mid", "lines": [[(515, 388), (450, 425), (400, 480), (375, 560), (345, 640), (330, 720), (320, 790), (318, 880), (325, 950)]]},
                       {"name": "rear", "pivot": (1265, 515), "lines": [[(1290, 520), (1310, 620), (1350, 690), (1360, 770), (1370, 850), (1350, 930), (1340, 990)], [(1190, 600), (1210, 640)]]},
                   ]}},
    "void": {"width": 1180, "outline": 5, "length": 420.0, "order": ["far", "near", "body"], "glow": True,
             # the lower jaw: the big claw and the lower teeth, everything under the line of the mouth; it swings on the back corner of the mouth.
             # The teeth that hang from the head (upper teeth and the teeth of the cheek: the cream pieces above `upper_y`) stay with the head.
             "jaws": {"kind": "poly", "poly": [(846, 296), (912, 296), (925, 326), (1056, 326), (1062, 440), (1040, 540), (838, 570), (838, 420), (846, 400), (846, 322), (866, 322)],
                      "pivot": (845, 318), "open": [0.34], "cavity": None, "cavity_lift": 1.7, "ring": 5, "speck": 400,
                      "upper_box": [800, 250, 1075, 352], "upper_y": 322, "lower_box": [846, 300, 1100, 580], "lower_x": 1068,
                      # the dark of the throat, drawn behind the jaw so an open mouth looks into the void (and never spills outside the head)
                      "cavity_poly": [(834, 286), (912, 282), (1040, 284), (1086, 326), (1086, 392), (1030, 398), (1000, 440), (940, 440), (880, 400), (840, 372), (834, 330)]},
             "wave": True,
             "legs": {
                 # (every leg is a chain of bones: a cap at the top, the shin, the claw; the long bones between the caps are the thighs. Thin legs that hide
                 #  behind a fatter one come first so they are drawn first.)
                 "void_legs_a": [
                     {"name": "a3b", "lines": [[(892, 560), (876, 579), (899, 625), (900, 660)]]},
                     {"name": "a1", "lines": [[(545, 335), (522, 453), (505, 546), (488, 641)], [(603, 370), (620, 395), (662, 454), (703, 453)]]},
                     {"name": "a2", "lines": [[(797, 515), (765, 531), (699, 617), (690, 700)]]},
                     {"name": "a3", "lines": [[(907, 410), (903, 439), (868, 482), (850, 540)]]},
                     {"name": "a4", "lines": [[(1039, 384), (1032, 470), (1028, 534), (1059, 585), (1087, 686)], [(987, 423), (953, 451)]]},
                     {"name": "a5", "lines": [[(1104, 471), (1112, 503), (1137, 535), (1149, 566), (1181, 598), (1227, 683)]]},
                     {"name": "a6", "lines": [[(1237, 406), (1229, 460), (1266, 459), (1268, 495)], [(1172, 456), (1203, 460)]]},
                     {"name": "a7", "lines": [[(1318, 448), (1317, 498), (1369, 519), (1372, 554), (1447, 648), (1500, 720)]]},
                     {"name": "a8", "lines": [[(1524, 517), (1527, 553), (1581, 563), (1599, 617), (1635, 641), (1649, 728)], [(1463, 553), (1490, 540)]]},
                 ],
                 "void_legs_b": [
                     {"name": "b7b", "lines": [[(1006, 554), (1037, 615)]]},
                     {"name": "b3", "lines": [[(805, 385), (781, 381), (750, 420), (735, 480), (725, 510)]]},
                     {"name": "b5", "lines": [[(892, 409), (888, 441), (853, 475), (845, 540)]]},
                     {"name": "b7c", "pivot": (1162, 655), "lines": [[(1156, 685), (1150, 720)]]},
                     {"name": "b1", "lines": [[(562, 338), (576, 377), (520, 449), (504, 542), (487, 638)], [(619, 394), (656, 451), (677, 437)]]},
                     {"name": "b2", "lines": [[(663, 508), (633, 530), (597, 607), (590, 700)]]},
                     {"name": "b4", "lines": [[(793, 517), (764, 533), (706, 623), (700, 720)]]},
                     {"name": "b6", "lines": [[(987, 384), (979, 405), (955, 469), (936, 522), (948, 596), (967, 708)]]},
                     {"name": "b7", "lines": [[(1059, 510), (1072, 528), (1128, 581), (1185, 644), (1220, 677), (1271, 776)]]},
                     {"name": "b8", "lines": [[(1311, 457), (1328, 469), (1324, 494), (1377, 560), (1378, 618), (1400, 700), (1440, 750)], [(1282, 518), (1233, 544)], [(1402, 590), (1429, 578)]]},
                     {"name": "b9", "lines": [[(1598, 506), (1573, 511), (1601, 540), (1650, 570), (1690, 584), (1701, 632), (1720, 690)], [(1507, 553)]]},
                 ]}},
}


# ---------------------------------------------------------------- basics
def load(name):
    """An art_src picture with a clean matte: the drawings come with alpha 250-254 on everything (a see-through film) and a dust of alpha 1-9 specks."""
    im = Image.open(os.path.join(SRC, name)).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 0 if v < 10 else (255 if v > 240 else v))
    im.putalpha(a)
    return im


def _disk(r):
    return [(dx, dy) for dy in range(-r, r + 1) for dx in range(-r, r + 1) if dx * dx + dy * dy <= r * r + r * 0.6]


def dilate(mask, r):
    """Grow a mask (mode L) by r px, round (a MaxFilter is square and fattens the diagonals)."""
    if r <= 0:
        return mask
    w, h = mask.size
    pad = Image.new("L", (w + 2 * r, h + 2 * r), 0)
    pad.paste(mask, (r, r))
    acc = pad
    for dx, dy in _disk(r):
        if dx or dy:
            acc = ImageChops.lighter(acc, ImageChops.offset(pad, dx, dy))
    return acc.crop((r, r, r + w, r + h))


def edge_ink(im):
    """The colour of the outline the artist drew round the picture (median of its outermost 3 px); the ring `thicken` adds must match it, or the
    outline shows two tones."""
    import statistics
    a = im.getchannel("A")
    solid = a.point(lambda v: 255 if v >= 250 else 0)
    band = ImageChops.subtract(solid, solid.filter(ImageFilter.MinFilter(7)))
    px = im.load()
    bd = band.load()
    w, h = im.size
    cols = ([], [], [])
    for y in range(h):
        for x in range(w):
            if bd[x, y]:
                p = px[x, y]
                cols[0].append(p[0])
                cols[1].append(p[1])
                cols[2].append(p[2])
    if not cols[0]:
        return INK
    return tuple(int(statistics.median(c)) for c in cols)


def thicken(im, r, ink=None):
    """A dark ring r px wide round everything that is opaque (round, with a soft edge), in the colour of the artist's own outline."""
    a = im.getchannel("A")
    ink = ink or edge_ink(im)
    grown = dilate(a.point(lambda v: 255 if v > 24 else 0), r).filter(ImageFilter.GaussianBlur(0.7))
    grown = ImageChops.lighter(grown, a)
    ring = Image.new("RGBA", im.size, tuple(ink) + (0,))
    ring.putalpha(grown)
    ring.alpha_composite(im)
    return ring


def bbox_of(im, thr=8):
    return im.getchannel("A").point(lambda v: 255 if v > thr else 0).getbbox()


def trim(im, pad=2):
    bb = bbox_of(im)
    bb = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(im.size[0], bb[2] + pad), min(im.size[1], bb[3] + pad))
    return im.crop(bb)


def labels_of(mask, thr=40, eight=True):
    """Connected pieces of a mask (L). Returns (label bytes-like list of ints per pixel (-1 none), sizes) with a flood fill at full resolution."""
    w, h = mask.size
    data = mask.getdata()
    lab = [-1] * (w * h)
    sizes = []
    nb = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)) if eight else ((1, 0), (-1, 0), (0, 1), (0, -1))
    for s in range(w * h):
        if lab[s] != -1 or data[s] < thr:
            continue
        k = len(sizes)
        lab[s] = k
        q = deque([s])
        n = 0
        while q:
            i = q.popleft()
            n += 1
            x = i % w
            y = i // w
            for dx, dy in nb:
                nx = x + dx
                ny = y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if lab[j] == -1 and data[j] >= thr:
                        lab[j] = k
                        q.append(j)
        sizes.append(n)
    return lab, sizes


def grow_labels(lab, size, allowed, steps):
    """Spread the labels of lab (list, -1 none) over `allowed` pixels (a callable index -> bool), at most `steps` px, nearest first."""
    w, h = size
    q = deque(i for i, v in enumerate(lab) if v >= 0)
    dist = {i: 0 for i in q}
    nb = ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1))
    while q:
        i = q.popleft()
        d = dist[i]
        if d >= steps:
            continue
        x = i % w
        y = i // w
        for dx, dy in nb:
            nx = x + dx
            ny = y + dy
            if 0 <= nx < w and 0 <= ny < h:
                j = ny * w + nx
                if lab[j] == -1 and allowed(j):
                    lab[j] = lab[i]
                    dist[j] = d + 1
                    q.append(j)
    return lab


def mask_from(lab, size, ids):
    """L mask of the pixels whose label is in ids."""
    ids = set(ids)
    m = Image.new("L", size, 0)
    m.putdata([255 if v in ids else 0 for v in lab])
    return m


def grow_in(mask, allowed, steps):
    """Spread a mask over the pixels of `allowed` (L masks), at most `steps` px, never jumping over a gap: only pixels joined to the mask through allowed ones."""
    cur = mask
    for _ in range(steps):
        nxt = ImageChops.multiply(cur.filter(ImageFilter.MaxFilter(3)), allowed)
        cur = ImageChops.lighter(cur, nxt)
    return cur


def drop_specks(im, min_px=40, frac=0.0):
    """Remove little islands of opaque pixels that are not part of the main picture (the bits of outline a cut leaves behind)."""
    a = im.getchannel("A")
    lab, sizes = labels_of(a, 24)
    if len(sizes) <= 1:
        return im
    floor = max(min_px, frac * max(sizes))
    keep = [k for k, n in enumerate(sizes) if n >= floor]
    if len(keep) == len(sizes):
        return im
    keepmask = dilate(mask_from(lab, im.size, keep), 2)
    out = im.copy()
    out.putalpha(ImageChops.multiply(a, keepmask))
    return out


# ---------------------------------------------------------------- legs
def partition(im, legs, k, ink_max=70, ink_cost=5.0, seed_r=3):
    """Give every opaque pixel of a legs picture to one leg. `legs` is a list of dicts with "lines" (picture px; scaled by k here). Walks outwards from the
    seeds (all legs together, nearest first); a step onto an outline pixel costs ink_cost, onto anything else 1, so a pixel goes to the leg whose own bones
    it can reach without crossing an outline. Returns (label image: leg index or 255 for none, ink mask)."""
    w, h = im.size
    data = list(im.getdata())
    W = w + 2
    cost = [-1.0] * (W * (h + 2))
    inkm = bytearray(w * h)
    for y in range(h):
        base = (y + 1) * W + 1
        for x in range(w):
            r, g, b, a = data[y * w + x]
            if a >= 8:
                dark = max(r, g, b) < ink_max
                cost[base + x] = ink_cost if dark else 1.0
                if a >= 200 and dark:
                    inkm[y * w + x] = 255
    dist = [1e18] * len(cost)
    label = bytearray([255]) * len(cost)
    heap = []
    for li, leg in enumerate(legs):
        sm = Image.new("L", im.size, 0)
        dr = ImageDraw.Draw(sm)
        for line in leg["lines"]:
            pts = [(x * k, y * k) for x, y in line]
            if len(pts) == 1:
                pts = pts * 2
            dr.line(pts, fill=255, width=2 * seed_r + 1)
            for (x, y) in pts:
                dr.ellipse([x - seed_r, y - seed_r, x + seed_r, y + seed_r], fill=255)
        sd = sm.getdata()
        n = 0
        for i, v in enumerate(sd):
            if v:
                j = (i // w + 1) * W + (i % w) + 1
                if cost[j] >= 0 and dist[j] > 0:
                    dist[j] = 0.0
                    label[j] = li
                    heap.append((0.0, j))
                    n += 1
        if n == 0:
            print("  WARNING: leg %s has no seed pixel on the picture" % leg.get("name", li))
    heapq.heapify(heap)
    nbrs = ((1, 1.0), (-1, 1.0), (W, 1.0), (-W, 1.0), (W + 1, 1.4142), (W - 1, 1.4142), (-W + 1, 1.4142), (-W - 1, 1.4142))
    pop = heapq.heappop
    push = heapq.heappush
    while heap:
        d, i = pop(heap)
        if d > dist[i]:
            continue
        li = label[i]
        for off, f in nbrs:
            j = i + off
            c = cost[j]
            if c < 0.0:
                continue
            nd = d + c * f
            if nd < dist[j]:
                dist[j] = nd
                label[j] = li
                push(heap, (nd, j))
    rows = b"".join(bytes(label[(y + 1) * W + 1:(y + 1) * W + 1 + w]) for y in range(h))
    lab = Image.frombytes("L", (w, h), rows)
    ink = Image.frombytes("L", (w, h), bytes(inkm))
    # opaque pixels nobody reached (a bone with no seed): say so
    unreached = 0
    xs = []
    ys = []
    for y in range(h):
        base = (y + 1) * W + 1
        for x in range(w):
            if cost[base + x] >= 0 and label[base + x] == 255:
                unreached += 1
                xs.append(x)
                ys.append(y)
    if unreached > 30:
        print("  WARNING: %d opaque pixels reached by no leg (bbox %s)" % (unreached, (min(xs), min(ys), max(xs), max(ys))))
    return lab, ink


def cut_legs(im, legs, k, rim=5):
    """The pieces of one legs picture, one per leg, in the order given (back to front). Each: image, x, y (top-left in the picture) and the hinge."""
    lab, ink = partition(im, legs, k)
    a = im.getchannel("A")
    out = []
    for li, leg in enumerate(legs):
        m = lab.point(lambda v, li=li: 255 if v == li else 0)
        if m.getbbox() is None:
            continue
        # the rim: the outline of the neighbouring legs right next to this one, so its own outline is whole where it was cut from them
        piece_mask = grow_in(m, ink, rim)
        piece = im.copy()
        piece.putalpha(ImageChops.multiply(a, piece_mask))
        piece = drop_specks(piece, 60, 0.02)
        bb = bbox_of(piece)
        if bb is None:
            continue
        crop = piece.crop(bb)
        px, py = leg.get("pivot", leg["lines"][0][0])
        out.append({"img": crop, "x": bb[0], "y": bb[1], "pivot": (px * k, py * k), "name": leg.get("name", str(li))})
    return out


# ---------------------------------------------------------------- jaws
def _is_cream(p):
    r, g, b, a = p
    return a > 200 and r > 190 and g > 175 and b > 130 and abs(r - b) < 120


def _is_ink(p, ink_max=70):
    r, g, b, a = p
    return a >= 8 and max(r, g, b) < ink_max


def smooth_mask(m, sigma=1.2):
    """Round off the stair steps of a mask (a binary mask again afterwards, so a piece and the body it was cut from stay exact complements)."""
    return m.filter(ImageFilter.GaussianBlur(sigma)).point(lambda v: 255 if v >= 128 else 0)


def objects_with_rings(body, box, ring, min_px=150, pick=None, ink_max=70):
    """The cream pieces inside `box` (fangs, teeth), each with its own ring of outline round it (the dark pixels within `ring` px, shared between
    neighbouring pieces by who is nearer; never the fur round it). `pick(cx, cy, n)` says which pieces to take. Returns, left to right,
    [{"mask": ring+cream L mask, "cream": cream L mask, "top": (x of the top, y of the top), "c": (cx, cy)}]."""
    x0, y0, x1, y1 = box
    bw, bh = body.size
    px = body.load()
    cream = Image.new("L", body.size, 0)
    cp = cream.load()
    for y in range(max(0, y0), min(y1, bh)):
        for x in range(max(0, x0), min(x1, bw)):
            if _is_cream(px[x, y]):
                cp[x, y] = 255
    lab, sizes = labels_of(cream, 128)
    info = {}
    for j, v in enumerate(lab):
        if v >= 0:
            d = info.setdefault(v, [0, 0, 0, 10 ** 9, []])
            d[0] += 1
            d[1] += j % bw
            d[2] += j // bw
            if j // bw < d[3]:
                d[3] = j // bw
            d[4].append(j)
    ids = []
    for v, (n, sx, sy, top, pts) in info.items():
        if n < min_px:
            continue
        cx, cy = sx / n, sy / n
        if pick is None or pick(cx, cy, n):
            ids.append(v)
    ids.sort(key=lambda v: info[v][1] / info[v][0])
    data = list(body.getdata())
    seedlab = [-1] * (bw * bh)
    for n, v in enumerate(ids):
        for j in info[v][4]:
            seedlab[j] = n
    full = grow_labels(list(seedlab), body.size, lambda j: _is_ink(data[j], ink_max) or _is_cream(data[j]), ring)
    out = []
    for n, v in enumerate(ids):
        nn, sx, sy, top, pts = info[v]
        xs = [j % bw for j in pts if j // bw <= top + 14]
        out.append({"mask": mask_from(full, body.size, [n]), "cream": mask_from(seedlab, body.size, [n]),
                    "top": (sum(xs) / len(xs), top - 2.0), "c": (sx / nn, sy / nn)})
    return out


def make_jaws(body, spec):
    """Cut the jaw (or the fangs) out of the cropped body picture. Returns (body without them, [pieces], cavity image or None)."""
    jw = spec["jaws"]
    pieces = []
    if jw["kind"] == "poly":
        mask = Image.new("L", body.size, 0)
        ImageDraw.Draw(mask).polygon(jw["poly"], fill=255)
        # the upper teeth (and the teeth on the cheek) hang into the polygon: they stay with the head, each with its own outline
        ux0, uy0, ux1, uy1 = jw["upper_box"]
        uy = jw["upper_y"]
        # ... and every tooth that belongs to the jaw is taken whole, with its outline, even where it pokes out of the polygon
        for o in objects_with_rings(body, jw["lower_box"], jw.get("ring", 6), min_px=30, pick=lambda cx, cy, n: cy >= uy and cx < jw["lower_x"]):
            mask = ImageChops.lighter(mask, o["mask"])
        upper = objects_with_rings(body, jw["upper_box"], jw.get("ring", 6), min_px=30, pick=lambda cx, cy, n: cy < uy)
        for o in upper:
            mask = ImageChops.multiply(mask, ImageChops.invert(o["mask"]))
        masks = [(smooth_mask(mask, 1.0), jw["pivot"], jw["open"][0])]
    else:
        masks = []
        for gi, o in enumerate(objects_with_rings(body, jw["box"], jw.get("ring", 12))):
            masks.append((smooth_mask(o["mask"]), o["top"], jw["open"][gi % len(jw["open"])]))
    cut_mask = Image.new("L", body.size, 0)
    a = body.getchannel("A")
    for mk, pivot, ang in masks:
        cut_mask = ImageChops.lighter(cut_mask, mk)
        piece = body.copy()
        piece.putalpha(ImageChops.multiply(a, mk))
        piece = drop_specks(piece, jw.get("speck", 30))
        bb = bbox_of(piece)
        if bb is None:
            continue
        pieces.append({"img": piece.crop(bb), "x": bb[0], "y": bb[1], "pivot": [round(pivot[0], 1), round(pivot[1], 1)], "open": ang})
    rest = body.copy()
    rest.putalpha(ImageChops.multiply(a, ImageChops.invert(cut_mask)))
    rest = drop_specks(rest, jw.get("speck", 30))
    # the hollow the jaw leaves behind, filled with the dark of the mouth so an open mouth looks into the void
    hollow = ImageChops.multiply(a, dilate(cut_mask, 2))
    cavcol = tuple(jw["cavity"]) if jw.get("cavity") else edge_ink(body)
    if jw.get("cavity_poly"):
        # the dark of the throat: the colour the art has there (median of its dark pixels), a touch lighter in the middle
        pm = Image.new("L", body.size, 0)
        ImageDraw.Draw(pm).polygon(jw["cavity_poly"], fill=255)
        px = body.load()
        pp = pm.load()
        dk = ([], [], [])
        for y in range(body.size[1]):
            for x in range(body.size[0]):
                if pp[x, y]:
                    r, g, b, aa = px[x, y]
                    if aa >= 250 and max(r, g, b) < 60:
                        dk[0].append(r)
                        dk[1].append(g)
                        dk[2].append(b)
        if dk[0] and not jw.get("cavity"):
            import statistics
            cavcol = tuple(int(statistics.median(c)) for c in dk)
    cav = Image.new("RGBA", body.size, cavcol + (0,))
    if jw.get("cavity_poly"):
        hollow = Image.new("L", body.size, 0)
        ImageDraw.Draw(hollow).polygon(jw["cavity_poly"], fill=255)
        hollow = ImageChops.multiply(hollow.filter(ImageFilter.GaussianBlur(3)), a)
        xs = [q[0] for q in jw["cavity_poly"]]
        ys = [q[1] for q in jw["cavity_poly"]]
        bx0, by0, bx1, by1 = min(xs), min(ys), max(xs), max(ys)
        rg = ImageOps.invert(Image.radial_gradient("L").resize((int(bx1 - bx0), int(by1 - by0))))
        lite = tuple(min(255, int(c * jw.get("cavity_lift", 1.8) + 6)) for c in cavcol)
        glow = ImageOps.colorize(rg, black=cavcol, white=lite).convert("RGBA")
        cav.paste(glow, (int(bx0), int(by0)))
    else:
        hollow = ImageChops.multiply(dilate(cut_mask, 2).filter(ImageFilter.GaussianBlur(1.2)), a)
    cav.putalpha(hollow)
    cbb = bbox_of(cav)
    cavity = {"img": cav.crop(cbb), "x": cbb[0], "y": cbb[1]} if cbb else None
    return rest, pieces, cavity


# ---------------------------------------------------------------- the creatures
def make_creatures(manifest, only=None, out_dir=None):
    out_dir = out_dir or OUT
    os.makedirs(out_dir, exist_ok=True)
    for name, spec in CREATURES.items():
        if only and name not in only:
            continue
        body = load(name + "_body.png")
        w0, h0 = body.size
        k = spec["width"] / float(w0)
        size = (spec["width"], int(round(h0 * k)))

        def prep(im):
            return thicken(im.resize(size, Image.LANCZOS), spec["outline"])

        body = prep(body)
        la, lb = load(name + "_legs_a.png"), load(name + "_legs_b.png")
        sets = {name + "_legs_a": prep(la), name + "_legs_b": prep(lb)}

        # the darker set of legs is the far side
        def bright(im):
            px = [p for p in im.resize((120, 120)).getdata() if p[3] > 200]
            return sum((p[0] + p[1] + p[2]) / 3 for p in px) / max(1, len(px))
        ka, kb = name + "_legs_a", name + "_legs_b"
        far, near = (ka, kb) if bright(sets[ka]) <= bright(sets[kb]) else (kb, ka)
        entry = {"canvas": list(size), "order": spec["order"], "parts": [], "wave": bool(spec.get("wave", False))}
        union = None
        for layer, key in (("far", far), ("near", near)):
            print("%s %s legs (%s)" % (name, layer, key))
            if not spec["legs"].get(key):
                print("  (no legs described for %s yet)" % key)
                continue
            pieces = cut_legs(sets[key], spec["legs"][key], k)
            # neighbouring legs step in opposite phase; the far set is opposite to the near set
            order_x = sorted(range(len(pieces)), key=lambda i: pieces[i]["pivot"][0])
            phase = {}
            for rank, i in enumerate(order_x):
                phase[i] = (rank + (1 if layer == "far" else 0)) % 2
            for i, p in enumerate(pieces):
                fn = "%s_%s_%d.png" % (name, layer, i)
                p["img"].save(os.path.join(out_dir, fn), optimize=True)
                entry["parts"].append({"layer": layer, "file": fn, "x": p["x"], "y": p["y"], "pivot": [round(p["pivot"][0], 1), round(p["pivot"][1], 1)], "phase": phase[i]})
                bb = (p["x"], p["y"], p["x"] + p["img"].size[0], p["y"] + p["img"].size[1])
                union = bb if union is None else (min(union[0], bb[0]), min(union[1], bb[1]), max(union[2], bb[2]), max(union[3], bb[3]))
        bb = bbox_of(body)
        bodyc = body.crop(bb)
        entry["body"] = {"file": name + "_body.png", "x": bb[0], "y": bb[1]}
        glow_src = bodyc
        if spec.get("jaws"):
            rest, pieces, cavity = make_jaws(bodyc, spec)
            glow_src = rest
            rest.save(os.path.join(out_dir, name + "_body.png"), optimize=True)
            entry["jaws"] = []
            for i, p in enumerate(pieces):
                fn = "%s_jaw_%d.png" % (name, i)
                p["img"].save(os.path.join(out_dir, fn), optimize=True)
                entry["jaws"].append({"file": fn, "x": bb[0] + p["x"], "y": bb[1] + p["y"], "pivot": [bb[0] + p["pivot"][0], bb[1] + p["pivot"][1]], "open": p["open"]})
            if cavity is not None:
                cavity["img"].save(os.path.join(out_dir, name + "_cavity.png"), optimize=True)
                entry["cavity"] = {"file": name + "_cavity.png", "x": bb[0] + cavity["x"], "y": bb[1] + cavity["y"]}
        else:
            bodyc.save(os.path.join(out_dir, name + "_body.png"), optimize=True)
        union = bb if union is None else (min(union[0], bb[0]), min(union[1], bb[1]), max(union[2], bb[2]), max(union[3], bb[3]))
        if spec["glow"]:
            g = glow_src.convert("RGBA")
            gp = g.load()
            gw, gh = g.size
            mask = Image.new("L", g.size, 0)
            mp = mask.load()
            for y in range(gh):
                for x in range(gw):
                    r, gg, b, a = gp[x, y]
                    if a > 200 and b > 120 and b - gg > 70 and r > 60:
                        mp[x, y] = 255
            halo = mask.filter(ImageFilter.GaussianBlur(3.0))
            glow = Image.new("RGBA", g.size, (214, 140, 255, 0))
            glow.putalpha(halo)
            glow.save(os.path.join(out_dir, name + "_glow.png"), optimize=True)
            entry["glow"] = {"file": name + "_glow.png", "x": bb[0], "y": bb[1]}
        entry["feet"] = [round((union[0] + union[2]) / 2.0, 1), float(union[3])]
        entry["width"] = float(union[2] - union[0])
        entry["height"] = float(union[3] - union[1])
        entry["scale"] = round(spec["length"] / entry["width"], 5)
        manifest[name] = entry
        print("%s: %d parts, canvas %s, game scale %.4f" % (name, len(entry["parts"]), size, entry["scale"]))
    return manifest


# ---------------------------------------------------------------- the bird
def cap_open_ends(im, light=90, r=12, min_px=15):
    """Where a drawn part was cut off straight (the top of the bird's legs, which the artist left open) there is no outline: close it with a band of the
    picture's own outline colour, so the end of the leg reads as a stump in front of the feathers instead of a raw cut."""
    a = im.getchannel("A")
    solid = a.point(lambda v: 255 if v >= 200 else 0)
    edge = ImageChops.subtract(solid, solid.filter(ImageFilter.MinFilter(5)))
    px = im.load()
    e = edge.load()
    w, h = im.size
    m = Image.new("L", im.size, 0)
    mp = m.load()
    for y in range(h):
        for x in range(w):
            if e[x, y]:
                p = px[x, y]
                if max(p[0], p[1], p[2]) >= light:
                    mp[x, y] = 255
    lab, sizes = labels_of(m, 128)
    keep = [k for k, n in enumerate(sizes) if n >= min_px]
    if not keep:
        return im
    cap = dilate(mask_from(lab, im.size, keep), r)
    ink = Image.new("RGBA", im.size, edge_ink(im) + (255,))
    ink.putalpha(cap)
    out = im.copy()
    out.alpha_composite(ink)
    return out


def make_bird(manifest, out_dir=None):
    """The bird's five parts, each cropped; the game assembles and flaps them."""
    out_dir = out_dir or OUT
    os.makedirs(out_dir, exist_ok=True)
    parts = {}
    for nm in ["head", "wing_a", "wing_b", "claw_1", "claw_2"]:
        im = load("bird_%s.png" % nm)
        if nm.startswith("claw"):
            im = cap_open_ends(im)
        im = im.resize((int(im.size[0] * 0.4), int(im.size[1] * 0.4)), Image.LANCZOS)
        t = trim(im)
        fn = "bird_%s.png" % nm
        t.save(os.path.join(out_dir, fn), optimize=True)
        parts[nm] = {"file": fn, "w": t.size[0], "h": t.size[1]}
        print("bird %s: %dx%d" % (nm, t.size[0], t.size[1]))
    manifest["bird"] = parts
    return manifest


# ---------------------------------------------------------------- the rocks
def make_rocks(manifest, out_dir=None, merge_gap=3):
    """The rock sheet: every separate rock becomes a sprite for the meadow (a boulder with pebbles round it that touch it is one rock; pebbles of a row
    that are no more than `merge_gap` px apart after the outline went on are one sprite too, as the game expects 7 sprites: spire, dome, cairn, two low
    boulders, a pebble row, a single stone). The pieces are cut by label, pixel by pixel, so nothing of a neighbour's outline comes along."""
    out_dir = out_dir or OUT
    os.makedirs(out_dir, exist_ok=True)
    sheet = load("rocks.png")
    sheet = sheet.resize((int(sheet.size[0] * 0.4), int(sheet.size[1] * 0.4)), Image.LANCZOS)
    sheet = thicken(sheet, 3)
    a = sheet.getchannel("A")
    w, h = a.size
    lab, sizes = labels_of(a, 40)
    bbs = {}
    for j, v in enumerate(lab):
        if v >= 0:
            x, y = j % w, j // w
            b = bbs.setdefault(v, [x, y, x, y])
            b[0] = min(b[0], x)
            b[1] = min(b[1], y)
            b[2] = max(b[2], x)
            b[3] = max(b[3], y)
    ids = [v for v, n in enumerate(sizes) if n >= 150]          # dust is not a rock
    # group pieces that are close: let every piece grow by half the gap; pieces whose grown shapes meet are one rock
    big = [v if v in ids else -1 for v in lab]
    reach = (merge_gap + 1) // 2
    grown = grow_labels(list(big), (w, h), lambda j: True, reach)
    group = {v: v for v in ids}

    def find(v):
        while group[v] != v:
            v = group[v]
        return v
    for j, v in enumerate(grown):
        if v < 0:
            continue
        x = j % w
        for k in ((j + 1) if x + 1 < w else -1, (j + w) if j + w < w * h else -1):
            if k >= 0 and grown[k] >= 0 and grown[k] != v:
                group[find(grown[k])] = find(v)
    groups = {}
    for v in ids:
        groups.setdefault(find(v), []).append(v)
    # the soft edge pixels the label threshold left out go to the nearest rock
    ap = a.load()
    lab = grow_labels(lab, (w, h), lambda j: ap[j % w, j // w] >= 8, 2)
    pieces = []
    for g, members in groups.items():
        m = mask_from(lab, (w, h), members)
        piece = sheet.copy()
        piece.putalpha(ImageChops.multiply(a, m))
        bb = bbox_of(piece)
        pieces.append(piece.crop(bb))
    pieces.sort(key=lambda im: -(im.size[0] * im.size[1]))
    rocks = []
    for i, im in enumerate(pieces):
        fn = "rock_%d.png" % i
        im.save(os.path.join(out_dir, fn), optimize=True)
        rw, rh = im.size
        rocks.append({"file": fn, "w": rw, "h": rh, "tall": rh > 1.25 * rw})
        print("rock %d: %dx%d%s" % (i, rw, rh, " (spire)" if rh > 1.25 * rw else ""))
    if len(rocks) != 7:
        print("  WARNING: %d rock sprites (the game expects 7: see ground_view._rock_sprite)" % len(rocks))
    manifest["rocks"] = rocks
    return manifest
