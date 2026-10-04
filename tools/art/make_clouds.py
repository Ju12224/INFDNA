#!/usr/bin/env python3
"""Cut the owner's cloud sheet (art_src/clouds.png, RGBA with real transparency) into game/art/sky/cloud_*.png.

Every separate shape on the sheet is one cloud; small specks join the cloud whose nearest pixel is closest. Clouds are named by
shape: big (puffy cumulus, tall), flat (long stratus, more than 3x wider than tall) and wisp (small). game/art/sky/sky_manifest.json
lists them with their size. The sky layer drifts them across the sky.
Needs Pillow, numpy and scipy:  python3 tools/art/make_clouds.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "clouds.png")
OUT = os.path.join(ROOT, "game", "art", "sky")
SPECK = 400          # shapes smaller than this (pixels) are bits of a bigger cloud
MARGIN = 3
BIG_H = 250          # puffy clouds at least this tall are big; shorter ones wisps


def main():
    im = Image.open(SRC).convert("RGBA")
    rgba = np.asarray(im)
    solid = rgba[..., 3] > 8
    lab, n = ndimage.label(solid, structure=np.ones((3, 3), int))
    sizes = ndimage.sum(solid, lab, range(1, n + 1))
    bodies = [i + 1 for i in range(n) if sizes[i] >= SPECK]
    # each speck joins the body nearest to it
    owner = np.zeros_like(lab)
    dist = np.full(lab.shape, np.inf)
    for b in bodies:
        d = ndimage.distance_transform_edt(lab != b)
        closer = d < dist
        owner[closer] = b
        dist[closer] = d[closer]
    owner[~solid] = 0
    found = []
    for b in bodies:
        ys, xs = np.nonzero(owner == b)
        found.append((ys.min(), xs.min(), ys.max(), xs.max(), b))
    found.sort(key=lambda f: (round(f[0] / 200), f[1]))      # rows top to bottom, then left to right
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.startswith("cloud_") and f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    counts = {"big": 0, "flat": 0, "wisp": 0}
    clouds = []
    for y0, x0, y1, x1, b in found:
        w, h = int(x1 - x0 + 1), int(y1 - y0 + 1)
        kind = "flat" if w > 3 * h else ("big" if h >= BIG_H else "wisp")
        name = "cloud_%s_%d" % (kind, counts[kind])
        counts[kind] += 1
        crop = np.zeros((h + 2 * MARGIN, w + 2 * MARGIN, 4), np.uint8)
        mask = owner[y0:y1 + 1, x0:x1 + 1] == b
        crop[MARGIN:MARGIN + h, MARGIN:MARGIN + w][mask] = rgba[y0:y1 + 1, x0:x1 + 1][mask]
        Image.fromarray(crop).save(os.path.join(OUT, name + ".png"))
        clouds.append({"name": name, "file": "sky/%s.png" % name, "kind": kind, "w": w + 2 * MARGIN, "h": h + 2 * MARGIN})
    path = os.path.join(OUT, "sky_manifest.json")
    man = json.load(open(path)) if os.path.exists(path) else {}
    man["_about"] = "The owner's sky art, cut by tools/art/make_clouds.py (and later sky tools). Sizes in pixels."
    man["clouds"] = clouds
    json.dump(man, open(path, "w"), indent=1)
    print("%d clouds: %s" % (len(clouds), ", ".join(c["name"] for c in clouds)))


if __name__ == "__main__":
    main()
