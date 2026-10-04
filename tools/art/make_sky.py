#!/usr/bin/env python3
"""Cut the owner's sky sheets (RGBA with real transparency) into game/art/sky/*.png and list them in sky_manifest.json.

art_src/clouds.png: every separate shape is one cloud, named by shape: big (puffy cumulus, tall), flat (long stratus, more than
3x wider than tall) and wisp (small). art_src/sun_moon_stars.png: the three biggest shapes are the sun (the yellow one), the full
moon and the crescent (the one that fills least of its box); the rest are stars, biggest first. On both sheets small specks join
the shape whose nearest pixel is closest. The sky layer uses them.
Needs Pillow, numpy and scipy:  python3 tools/art/make_sky.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "clouds.png")
SRC_SUN = os.path.join(ROOT, "art_src", "sun_moon_stars.png")
OUT = os.path.join(ROOT, "game", "art", "sky")
SPECK = 400          # shapes smaller than this (pixels) are bits of a bigger cloud
MARGIN = 3
BIG_H = 250          # puffy clouds at least this tall are big; shorter ones wisps


def shapes(path):
    """The separate shapes on a sheet: [(y0, x0, y1, x1, mask of the shape in the sheet)], specks joined to their nearest shape."""
    rgba = np.asarray(Image.open(path).convert("RGBA"))
    solid = rgba[..., 3] > 8
    lab, n = ndimage.label(solid, structure=np.ones((3, 3), int))
    sizes = ndimage.sum(solid, lab, range(1, n + 1))
    bodies = [i + 1 for i in range(n) if sizes[i] >= SPECK]
    owner = np.zeros_like(lab)
    dist = np.full(lab.shape, np.inf)
    for b in bodies:
        d = ndimage.distance_transform_edt(lab != b)
        closer = d < dist
        owner[closer] = b
        dist[closer] = d[closer]
    owner[~solid] = 0
    out = []
    for b in bodies:
        ys, xs = np.nonzero(owner == b)
        out.append((int(ys.min()), int(xs.min()), int(ys.max()), int(xs.max()), owner == b))
    return rgba, out


def save(rgba, shape, name):
    y0, x0, y1, x1, m = shape
    w, h = x1 - x0 + 1, y1 - y0 + 1
    crop = np.zeros((h + 2 * MARGIN, w + 2 * MARGIN, 4), np.uint8)
    mask = m[y0:y1 + 1, x0:x1 + 1]
    crop[MARGIN:MARGIN + h, MARGIN:MARGIN + w][mask] = rgba[y0:y1 + 1, x0:x1 + 1][mask]
    Image.fromarray(crop).save(os.path.join(OUT, name + ".png"))
    return {"name": name, "file": "sky/%s.png" % name, "w": w + 2 * MARGIN, "h": h + 2 * MARGIN}


def cut_clouds():
    rgba, found = shapes(SRC)
    found.sort(key=lambda f: (round(f[0] / 200), f[1]))      # rows top to bottom, then left to right
    counts = {"big": 0, "flat": 0, "wisp": 0}
    clouds = []
    for f in found:
        w, h = f[3] - f[1] + 1, f[2] - f[0] + 1
        kind = "flat" if w > 3 * h else ("big" if h >= BIG_H else "wisp")
        e = save(rgba, f, "cloud_%s_%d" % (kind, counts[kind]))
        counts[kind] += 1
        e["kind"] = kind
        clouds.append(e)
    return clouds


def cut_sun_moon_stars():
    rgba, found = shapes(SRC_SUN)
    found.sort(key=lambda f: -int(f[4].sum()))                # biggest first
    big, stars = found[:3], found[3:]
    def yellow(f):
        px = rgba[f[4]][:, :3].astype(float)
        return float((px[:, 0] - px[:, 2]).mean())             # red minus blue: high for the warm sun
    def fill(f):
        return float(f[4].sum()) / ((f[2] - f[0] + 1) * (f[3] - f[1] + 1))
    sun = max(big, key=yellow)
    moons = [f for f in big if f is not sun]
    crescent = min(moons, key=fill)
    full = [f for f in moons if f is not crescent][0]
    out = {"sun": save(rgba, sun, "sun"), "moon_full": save(rgba, full, "moon_full"), "moon_crescent": save(rgba, crescent, "moon_crescent")}
    out["stars"] = [save(rgba, f, "star_%d" % i) for i, f in enumerate(stars)]
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    man = {"_about": "The owner's sky art, cut by tools/art/make_sky.py. Sizes in pixels."}
    man["clouds"] = cut_clouds()
    man.update(cut_sun_moon_stars())
    json.dump(man, open(os.path.join(OUT, "sky_manifest.json"), "w"), indent=1)
    print("%d clouds, sun, two moons, %d stars" % (len(man["clouds"]), len(man["stars"])))


if __name__ == "__main__":
    main()
