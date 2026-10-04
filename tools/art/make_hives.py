#!/usr/bin/env python3
"""Cut the owner's beehive sheet (art_src/beehives.png, RGBA with real transparency) into content/art/hive/*.png (half size).

Hives hang from a branch (whole, dripping, damaged), a cracked one falling, one on a trunk, a fallen one broken open on the ground;
honeycomb pieces and honey puddles (the honey the ants carry off); eight bees. Every small shape (falling flakes, drips) joins the
piece whose nearest pixel is closest to it. hive_view.gd and colony_sim.gd use them (hives grow on the meadow trees).
Needs Pillow, numpy and scipy:  python3 tools/art/make_hives.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "beehives.png")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "hive")
K = 0.5
PIECES = {
    "hive_whole": (9, 16, 374, 470), "hive_drip": (383, 23, 755, 484), "hive_damaged": (747, 13, 1031, 442),
    "hive_cracked": (1032, 197, 1333, 533), "hive_trunk": (18, 450, 483, 806), "hive_fallen": (449, 517, 943, 782),
    "comb_big": (1273, 20, 1458, 198), "comb_one": (1444, 128, 1523, 221), "comb_three": (1342, 210, 1482, 352),
    "comb_cell": (1409, 371, 1498, 477), "comb_drip": (1367, 508, 1515, 675), "comb_chunk": (1116, 557, 1277, 695),
    "comb_bit": (1325, 630, 1471, 736), "puddle_a": (946, 627, 1093, 723), "puddle_b": (1121, 711, 1256, 776),
}
for i, (x0, x1) in enumerate([(12, 235), (239, 431), (436, 654), (670, 854), (852, 1010), (1005, 1175), (1168, 1393), (1396, 1530)]):
    PIECES["bee_%d" % i] = (x0, 778, x1, 1005)


def main():
    im = Image.open(SRC).convert("RGBA")
    rgba = np.asarray(im)
    lab, n = ndimage.label(rgba[..., 3] > 8, structure=np.ones((3, 3), int))
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    cent = ndimage.center_of_mass(np.ones_like(lab), lab, range(1, n + 1))
    body = {}
    for name, (x0, y0, x1, y1) in PIECES.items():
        inside = [i for i, (cy, cx) in enumerate(cent, start=1) if x0 <= cx <= x1 and y0 <= cy <= y1]
        if inside:
            body[name] = max(inside, key=lambda i: sizes[i - 1])
    dist = {k: ndimage.distance_transform_edt(lab != b) for k, b in body.items()}
    owned = {k: [b] for k, b in body.items()}
    bodies = set(body.values())
    for i in range(1, n + 1):
        if i in bodies or sizes[i - 1] < 12:
            continue
        m = lab == i
        k = min(dist, key=lambda kk: dist[kk][m].min())
        if dist[k][m].min() < 45:
            owned[k].append(i)
    os.makedirs(OUT, exist_ok=True)
    man = {}
    for name in PIECES:
        mask = np.isin(lab, owned[name])
        ys, xs = np.nonzero(mask)
        a = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
        a[..., 3] = np.where(mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1], a[..., 3], 0)
        pic = Image.fromarray(a, "RGBA")
        pic = pic.resize((max(1, int(round(pic.width * K))), max(1, int(round(pic.height * K)))), Image.LANCZOS)
        pic.save(os.path.join(OUT, name + ".png"), optimize=True)
        man[name] = {"file": "hive/" + name + ".png", "w": pic.width, "h": pic.height}
    with open(os.path.join(OUT, "hive_manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print(len(man), "pieces")


if __name__ == "__main__":
    main()
