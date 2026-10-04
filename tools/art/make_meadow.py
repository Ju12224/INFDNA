#!/usr/bin/env python3
"""Cut the owner's meadow kit (art_src/meadow_kit.png, RGBA with real transparency) into game/art/meadow/m_NN.png.

The sheet is a loose scatter of small meadow things: grass tufts, flowers, bushes, rocks, mushrooms, logs, stumps, sticks, fallen
leaves, lily pads, reeds and a few critters. Every separate shape becomes one piece, numbered in reading order (rows top to bottom,
then left to right); small specks join the piece whose nearest pixel is closest. game/art/meadow/meadow_manifest.json lists each
piece's size; which piece is what gets named when the meadow is dressed (roadmap step 2.2).
Needs Pillow, numpy and scipy:  python3 tools/art/make_meadow.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "meadow_kit.png")
OUT = os.path.join(ROOT, "game", "art", "meadow")
SPECK = 120          # shapes smaller than this (pixels) are bits of a bigger piece
MARGIN = 3
ROW = 70             # pieces whose tops are within this many pixels count as one row


def main():
    rgba = np.asarray(Image.open(SRC).convert("RGBA"))
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
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith("m_") and f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    pieces = []
    for i, (b, (sy, sx)) in enumerate(found):
        h, w = sy.stop - sy.start, sx.stop - sx.start
        crop = np.zeros((h + 2 * MARGIN, w + 2 * MARGIN, 4), np.uint8)
        mask = owner[sy, sx] == b
        crop[MARGIN:MARGIN + h, MARGIN:MARGIN + w][mask] = rgba[sy, sx][mask]
        name = "m_%03d" % i
        Image.fromarray(crop).save(os.path.join(OUT, name + ".png"))
        pieces.append({"name": name, "file": "meadow/%s.png" % name, "w": w + 2 * MARGIN, "h": h + 2 * MARGIN,
			"src": [int(sx.start), int(sy.start), int(sx.stop), int(sy.stop)]})
    json.dump({"_about": "The owner's meadow kit, cut by tools/art/make_meadow.py. Sizes in pixels; src is the box on the sheet.",
		"pieces": pieces}, open(os.path.join(OUT, "meadow_manifest.json"), "w"), indent=1)
    print("%d meadow pieces" % len(pieces))


if __name__ == "__main__":
    main()
