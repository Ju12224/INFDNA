"""Cuts the owner's armor kit sheet (art_src/armor_kit.png) into one transparent picture per piece under game/art/antkit/armor/,
and writes game/art/antkit/armor_manifest.json (name, file, size, category, tier, the part of the ant it goes over).
The sheet has a flat green background, a black frame and a text label above every piece: pieces are found as blobs, the labels are dropped,
and the background is removed by flood fill from outside each piece (the thick outlines keep the inside)."""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "art_src", "armor_kit.png")
OUT = os.path.join(ROOT, "game", "art", "antkit", "armor")
MAN = os.path.join(ROOT, "game", "art", "antkit", "armor_manifest.json")

ROWS = [
    ["head_helmet_plain", "head_helmet_spiked", "head_helmet_horned", "head_helmet_visored", "head_helmet_crested", "head_helmet_royal", "head_helmet_bone", "head_helmet_resin"],
    ["mandible_blades", "mandible_clamps", "mandible_spiked", "mandible_scissor", "mandible_axe", "cheek_guard", "cheek_spiked", "cheek_ornate"],
    ["thorax_plate_plain", "thorax_plate_layered", "thorax_plate_spiked", "thorax_plate_heavy", "thorax_plate_bone", "thorax_plate_resin", "thorax_plate_saddle", "thorax_plate_royal"],
    ["abdomen_cap_plain", "abdomen_cap_segmented", "abdomen_cap_spiked", "abdomen_cap_heavy", "abdomen_cap_bone", "abdomen_cap_resin", "abdomen_cap_egg_guard", "abdomen_cap_royal"],
    ["leg_greave_plain", "leg_greave_spiked", "leg_greave_blade", "leg_greave_heavy", "leg_greave_bone", "leg_greave_resin", "leg_knee_guard", "leg_knee_spiked", "leg_knee_royal"],
]
# what each piece goes over, and how rare the look is (0 first armor ... 3 rare)
OVER = {"head": "head", "mandible": "mandible", "cheek": "head", "thorax": "thorax", "abdomen": "abdomen", "leg": "leg"}
TIER = {"plain": 0, "layered": 1, "segmented": 1, "guard": 1, "blades": 0, "clamps": 1, "scissor": 1, "visored": 1, "spiked": 2, "horned": 2, "blade": 2, "axe": 2,
        "heavy": 2, "crested": 2, "saddle": 2, "egg_guard": 2, "bone": 3, "resin": 3, "royal": 3, "ornate": 3}

im = Image.open(SRC).convert("RGB")
a = np.asarray(im).astype(np.int32)
H, W = a.shape[:2]
bg = np.array([142, 161, 127])
dist = np.sqrt(((a - bg) ** 2).sum(2))
inner = np.zeros((H, W), bool)
inner[24:H - 24, 24:W - 24] = True
fg = (dist > 28) & inner
# the text label of each row sits at these y; a row's pieces lie between its label and the next one
LABEL_Y = [57, 266, 447, 638, 836]
BANDS = [(LABEL_Y[i] + 9, (LABEL_Y[i + 1] - 4) if i + 1 < len(LABEL_Y) else H - 24) for i in range(len(LABEL_Y))]
os.makedirs(OUT, exist_ok=True)
pieces = []
for r, names in enumerate(ROWS):
    by0, by1 = BANDS[r]
    cols = fg[by0:by1].any(0)
    # runs of occupied columns (a gap of 3 or more empty columns ends a run)
    runs = []
    x = 0
    while x < W:
        if cols[x]:
            x0 = x
            gap = 0
            while x < W and gap < 3:
                gap = 0 if cols[x] else gap + 1
                x += 1
            runs.append((x0, x - gap))
        else:
            x += 1
    runs = [q for q in runs if q[1] - q[0] > 18]
    n = len(names)
    centres = [24 + (W - 48) * (i + 0.5) / n for i in range(n)]
    # pieces that touch share a run: cut it where the picture is thinnest between their centres
    occ = fg[by0:by1].sum(0)
    split = []
    for q in runs:
        inside = [cc for cc in centres if q[0] - 20 <= cc <= q[1] + 20 and q[1] - q[0] > 230]
        if len(inside) >= 2:
            cuts = [q[0]]
            for c1, c2 in zip(inside[:-1], inside[1:]):
                lo, hi = int((c1 + c2) / 2) - 28, int((c1 + c2) / 2) + 28
                cuts.append(lo + int(np.argmin(occ[lo:hi])))
            cuts.append(q[1])
            split += [(cuts[i], cuts[i + 1]) for i in range(len(cuts) - 1)]
        else:
            split.append(q)
    runs = split
    groups = [[] for _ in range(n)]
    for q in runs:
        c = (q[0] + q[1]) / 2
        groups[int(np.argmin([abs(c - cc) for cc in centres]))].append(q)
    print("row", r, "runs", len(runs), "groups", [len(g) for g in groups])
    for names_i, name in enumerate(names):
        g = groups[names_i]
        assert g, (r, name)
        x0 = max(0, min(q[0] for q in g) - 4)
        x1 = min(W, max(q[1] for q in g) + 4)
        y0, y1 = by0, by1
        bgm = (dist[y0:y1, x0:x1] < 34) | ~inner[y0:y1, x0:x1]
        bl, bn = ndimage.label(bgm)
        border = set(np.unique(np.concatenate([bl[0], bl[-1], bl[:, 0], bl[:, -1]]))) - {0}
        outside = np.isin(bl, list(border))
        piece = ~outside
        piece = ndimage.binary_opening(piece, iterations=1)
        pl, pn = ndimage.label(piece)
        if pn > 1:
            sizes = ndimage.sum(piece, pl, range(1, pn + 1))
            big = max(sizes)
            keep = [j + 1 for j, z in enumerate(sizes) if z > max(150, 0.04 * big)]
            piece = np.isin(pl, keep)
        piece = ndimage.binary_fill_holes(piece) | piece
        alpha = ndimage.gaussian_filter(ndimage.binary_erosion(piece, iterations=1).astype(float), 0.8)
        alpha = np.clip(alpha * 1.15, 0, 1)
        rgba = np.zeros((y1 - y0, x1 - x0, 4), np.uint8)
        rgba[:, :, :3] = a[y0:y1, x0:x1]
        rgba[:, :, 3] = (alpha * 255).astype(np.uint8)
        out = Image.fromarray(rgba, "RGBA")
        bb = out.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        out = out.crop(bb)
        fn = name + ".png"
        out.save(os.path.join(OUT, fn))
        kind = name.split("_")[0]
        tier_key = name.split("_", 2)[-1] if kind in ("head", "thorax", "abdomen", "leg") else name.split("_", 1)[-1]
        tier_key = tier_key.replace("helmet_", "").replace("plate_", "").replace("cap_", "").replace("greave_", "").replace("knee_", "")
        pieces.append({"name": name, "file": "antkit/armor/" + fn, "w": out.width, "h": out.height, "over": OVER[kind],
                       "tier": TIER.get(tier_key, 1), "style": tier_key, "row": r})
json.dump({"_about": "The owner's armor kit (tools/art/make_armor.py). All pieces face right like the part kit. over = the part of the ant it goes over.",
           "pieces": pieces}, open(MAN, "w"), indent=1)
print("cut", len(pieces))
