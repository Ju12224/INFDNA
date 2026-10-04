#!/usr/bin/env python3
"""Cut the owner's anteater parts sheet (art_src/anteater_parts.png, RGBA with real transparency) into the pieces the game animates.

The sheet holds four parts, facing right: the body with the head (no legs, no tail), the shoulder with both clawed front legs, the haunch
with both hind legs, and the bushy tail (its base at the right end). They are assembled as drawn (OFFSETS: where each part's top left sits
relative to the body's, in sheet px) and animated by creature_art.gd: the tail sways from its base, the front and the hind legs step in
turn from the shoulder and the hip, the body bobs with the stride.
Output: content/art/anteater/{tail,hind,front,body}.png at half size and anteater_manifest.json (version 2).

Needs Pillow, numpy and scipy:  python3 tools/art/make_anteater.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "anteater_parts.png")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "anteater")
K = 0.5
# part -> (box on the sheet, offset from the body's top left, pivot as a share of the part, how it moves)
PARTS = [
    ("tail", (786, 576, 1524, 989), (-640, 90), (0.93, 0.42)),
    ("hind", (70, 539, 766, 992), (-40, 250), (0.48, 0.12)),
    ("front", (932, 82, 1518, 558), (470, 230), (0.28, 0.1)),
    ("body", (8, 47, 930, 503), (0, 0), (0.5, 0.85)),
]


def main():
    sheet = Image.open(SRC).convert("RGBA")
    rgba = np.asarray(sheet)
    lab, n = ndimage.label(rgba[..., 3] > 8, structure=np.ones((3, 3), int))
    cent = ndimage.center_of_mass(np.ones_like(lab), lab, range(1, n + 1))
    os.makedirs(OUT, exist_ok=True)
    parts = []
    xs, ys = [], []
    for name, (x0, y0, x1, y1), off, piv in PARTS:
        keep = [i for i, (cy, cx) in enumerate(cent, start=1) if x0 <= cx <= x1 and y0 <= cy <= y1]
        m = np.isin(lab, keep)
        a = rgba[y0:y1, x0:x1].copy()
        a[..., 3] = np.where(m[y0:y1, x0:x1], a[..., 3], 0)
        im = Image.fromarray(a, "RGBA")
        im = im.resize((int(round(im.width * K)), int(round(im.height * K))), Image.LANCZOS)
        im.save(os.path.join(OUT, name + ".png"), optimize=True)
        w, h = x1 - x0, y1 - y0
        parts.append({"name": name, "file": "anteater/" + name + ".png", "w": w, "h": h, "off": list(off), "pivot": list(piv)})
        xs += [off[0], off[0] + w]
        ys += [off[1], off[1] + h]
    man = {"version": 2, "parts": parts, "x0": min(xs), "x1": max(xs), "ground": max(ys) - 4}
    with open(os.path.join(OUT, "anteater_manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print(json.dumps(man))


if __name__ == "__main__":
    main()
