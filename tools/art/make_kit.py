#!/usr/bin/env python3
"""Cut the owner's loose "kit" sheets (RGBA with real transparency) into numbered pieces: art_src/<kit>.png -> game/art/<folder>/.

A kit sheet is a scatter of separate small drawings. Every separate shape becomes one piece, numbered in reading order (rows top to
bottom, then left to right); small specks join the piece whose nearest pixel is closest. <folder>_manifest.json lists each piece's
size and its box on the sheet; which piece is what gets named when a view first uses them.
  meadow_kit.png -> art/meadow/m_NNN.png   tufts, flowers, bushes, rocks, mushrooms, logs, leaves, reeds (roadmap step 2.2)
  lab_kit.png    -> art/lab/l_NNN.png      flasks, jars, tools, notes, terrariums, powders, crates (the Lab screen, step 4.4)
Needs Pillow, numpy and scipy:  python3 tools/art/make_kit.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
KITS = [("meadow_kit.png", "meadow", "m"), ("lab_kit.png", "lab", "l")]
SPECK = 120          # shapes smaller than this (pixels) are bits of a bigger piece
MARGIN = 3
ROW = 70             # pieces whose tops are within this many pixels count as one row


def cut(sheet, folder, prefix):
    src = os.path.join(ROOT, "art_src", sheet)
    out = os.path.join(ROOT, "game", "art", folder)
    if not os.path.exists(src):
        return
    rgba = np.asarray(Image.open(src).convert("RGBA"))
    solid = rgba[..., 3] > 8
    lab, n = ndimage.label(solid, structure=np.ones((3, 3), int))
    sizes = ndimage.sum(solid, lab, range(1, n + 1))
    bodies = [i + 1 for i in range(n) if sizes[i] >= SPECK]
    _, near = ndimage.distance_transform_edt(~np.isin(lab, bodies), return_indices=True)
    owner = lab[near[0], near[1]]
    owner[~solid] = 0
    boxes = ndimage.find_objects(owner)
    found = [(b, boxes[b - 1]) for b in bodies if boxes[b - 1] is not None]
    found.sort(key=lambda f: (f[1][0].start // ROW, f[1][1].start))
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.startswith(prefix + "_") and f.endswith(".png"):
            os.remove(os.path.join(out, f))
    pieces = []
    for i, (b, (sy, sx)) in enumerate(found):
        h, w = sy.stop - sy.start, sx.stop - sx.start
        crop = np.zeros((h + 2 * MARGIN, w + 2 * MARGIN, 4), np.uint8)
        mask = owner[sy, sx] == b
        crop[MARGIN:MARGIN + h, MARGIN:MARGIN + w][mask] = rgba[sy, sx][mask]
        name = "%s_%03d" % (prefix, i)
        Image.fromarray(crop).save(os.path.join(out, name + ".png"))
        pieces.append({"name": name, "file": "%s/%s.png" % (folder, name), "w": w + 2 * MARGIN, "h": h + 2 * MARGIN,
            "src": [int(sx.start), int(sy.start), int(sx.stop), int(sy.stop)]})
    json.dump({"_about": "The owner's %s, cut by tools/art/make_kit.py. Sizes in pixels; src is the box on the sheet." % sheet,
        "pieces": pieces}, open(os.path.join(out, "%s_manifest.json" % folder), "w"), indent=1)
    print("%s: %d pieces" % (sheet, len(pieces)))


def main():
    for k in KITS:
        cut(*k)


if __name__ == "__main__":
    main()
