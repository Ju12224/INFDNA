#!/usr/bin/env python3
"""Cut the owner's weather sheet (art_src/weather.png, RGBA with real transparency) into game/art/weather/*.png.

The sheet has four rain streaks, two splashes, eight snowflakes, a strip of lying snow and a puddle. Each piece is a box on the sheet;
every separate shape belongs to the box its centre falls in (a streak's trailing drops, a splash's flying drops, the puddle's
droplets). game/art/weather/weather_manifest.json lists the pieces by kind. The weather view uses them.
Needs Pillow, numpy and scipy:  python3 tools/art/make_weather.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "weather.png")
OUT = os.path.join(ROOT, "game", "art", "weather")
MARGIN = 3
# kind -> boxes (x0, y0, x1, y1) on the 1536 x 1024 sheet, in order
BOXES = {
    "rain": [(80, 130, 250, 470), (250, 130, 470, 490), (470, 130, 670, 500), (680, 170, 870, 460)],
    "splash": [(895, 320, 1180, 520), (1190, 240, 1520, 530)],
    "flake": [(20 + i * 188, 550, 208 + i * 188, 750) for i in range(8)],
    "snow_cap": [(0, 760, 1015, 940)],
    "puddle": [(1030, 780, 1530, 950)],
}


def main():
    rgba = np.asarray(Image.open(SRC).convert("RGBA"))
    solid = rgba[..., 3] > 8
    lab, n = ndimage.label(solid, structure=np.ones((3, 3), int))
    cents = ndimage.center_of_mass(solid, lab, range(1, n + 1))
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        if f.endswith(".png"):
            os.remove(os.path.join(OUT, f))
    man = {"_about": "The owner's rain and snow, cut by tools/art/make_weather.py. Sizes in pixels."}
    for kind, boxes in BOXES.items():
        man[kind] = []
        for i, (x0, y0, x1, y1) in enumerate(boxes):
            ids = [j + 1 for j, (cy, cx) in enumerate(cents) if x0 <= cx < x1 and y0 <= cy < y1]
            if not ids:
                continue
            m = np.isin(lab, ids)
            ys, xs = np.nonzero(m)
            ya, yb, xa, xb = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            crop = np.zeros((yb - ya + 2 * MARGIN, xb - xa + 2 * MARGIN, 4), np.uint8)
            mk = m[ya:yb, xa:xb]
            crop[MARGIN:MARGIN + yb - ya, MARGIN:MARGIN + xb - xa][mk] = rgba[ya:yb, xa:xb][mk]
            name = "%s_%d" % (kind, i)
            Image.fromarray(crop).save(os.path.join(OUT, name + ".png"))
            man[kind].append({"name": name, "file": "weather/%s.png" % name, "w": int(crop.shape[1]), "h": int(crop.shape[0])})
    json.dump(man, open(os.path.join(OUT, "weather_manifest.json"), "w"), indent=1)
    print(", ".join("%d %s" % (len(man[k]), k) for k in BOXES))


if __name__ == "__main__":
    main()
