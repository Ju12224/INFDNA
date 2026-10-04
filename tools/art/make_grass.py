#!/usr/bin/env python3
"""Cut the owner's grass strips (art_src/grass_<row>.png, RGBA with real transparency) into game/art/grass/grass_<row>.png.

Each strip is trimmed to its drawing and laid next to a mirrored copy of itself, so it repeats with no seam. Rows, back to front:
back, mid, front, then edge (the short lip on top of the soil). game/art/grass/grass_manifest.json lists what exists.
Needs Pillow and numpy:  python3 tools/art/make_grass.py
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "game", "art", "grass")
ROWS = ["back", "mid", "front", "edge"]
TRIM = {"front": (16, 16, 0)}        # row -> (columns off the left, off the right, rows off the bottom) where a sheet has a frame line drawn round it


def main():
    os.makedirs(OUT, exist_ok=True)
    man = {"_about": "The owner's grass strips, cut by tools/art/make_grass.py; each tiles side by side. Sizes in pixels.", "strips": {}}
    for row in ROWS:
        src = os.path.join(ROOT, "art_src", "grass_%s.png" % row)
        if not os.path.exists(src):
            continue
        rgba = np.asarray(Image.open(src).convert("RGBA"))
        ys, xs = np.nonzero(rgba[..., 3] > 8)
        l, r, b = TRIM.get(row, (0, 0, 0))
        strip = rgba[ys.min():ys.max() + 1 - b, xs.min() + l:xs.max() + 1 - r]
        pair = np.concatenate([strip, strip[:, ::-1]], axis=1)
        Image.fromarray(pair).save(os.path.join(OUT, "grass_%s.png" % row))
        man["strips"][row] = {"file": "grass/grass_%s.png" % row, "w": int(pair.shape[1]), "h": int(pair.shape[0])}
    json.dump(man, open(os.path.join(OUT, "grass_manifest.json"), "w"), indent=1)
    print("grass strips:", ", ".join(man["strips"]))


if __name__ == "__main__":
    main()
