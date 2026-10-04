#!/usr/bin/env python3
"""Cut the owner's anthill sheet (art_src/anthills.png, RGBA with real transparency) into game/art/anthill/mound_*.png.

Three mounds of loose soil with an entrance hole, small to large from left to right; small specks join the nearest mound.
game/art/anthill/anthill_manifest.json lists each with its size and 'hole' (the entrance's centre, in the picture's pixels, found as
the darkest part of the mound) so the view can put the mound's mouth over the nest's shaft.
Needs Pillow, numpy and scipy:  python3 tools/art/make_anthills.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "anthills.png")
OUT = os.path.join(ROOT, "game", "art", "anthill")
NAMES = ["mound_small", "mound_medium", "mound_large"]
SPECK = 200
MARGIN = 3
EDGE = 14            # pixels in from the mound's edge where the hole is looked for


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
    found = sorted([(boxes[b - 1], b) for b in bodies], key=lambda f: f[0][1].start)
    os.makedirs(OUT, exist_ok=True)
    man = {"_about": "The owner's anthill mounds, cut by tools/art/make_anthills.py. Sizes in pixels; hole = the entrance's centre.", "mounds": []}
    for name, ((sy, sx), b) in zip(NAMES, found):
        h, w = sy.stop - sy.start, sx.stop - sx.start
        crop = np.zeros((h + 2 * MARGIN, w + 2 * MARGIN, 4), np.uint8)
        mask = owner[sy, sx] == b
        crop[MARGIN:MARGIN + h, MARGIN:MARGIN + w][mask] = rgba[sy, sx][mask]
        Image.fromarray(crop).save(os.path.join(OUT, name + ".png"))
        lum = crop[..., :3].astype(float).mean(axis=2)
        inside = ndimage.binary_erosion(crop[..., 3] > 200, iterations=EDGE)      # away from the ink outline round the mound
        dark = inside & (lum < np.percentile(lum[inside], 15))
        dark = ndimage.binary_opening(dark, iterations=3)
        lab2, n2 = ndimage.label(dark)
        if n2:
            biggest = 1 + int(np.argmax(ndimage.sum(dark, lab2, range(1, n2 + 1))))
            cy, cx = ndimage.center_of_mass(lab2 == biggest)
        else:
            cy, cx = crop.shape[0] * 0.7, crop.shape[1] * 0.5
        man["mounds"].append({"name": name, "file": "anthill/%s.png" % name, "w": int(crop.shape[1]), "h": int(crop.shape[0]),
            "hole": [round(float(cx), 1), round(float(cy), 1)]})
    json.dump(man, open(os.path.join(OUT, "anthill_manifest.json"), "w"), indent=1)
    print(", ".join("%s %dx%d hole %s" % (m["name"], m["w"], m["h"], m["hole"]) for m in man["mounds"]))


if __name__ == "__main__":
    main()
