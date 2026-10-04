#!/usr/bin/env python3
"""Cut the owner's thick grass strip (art_src/grass_thick.png, RGBA with real transparency) into game/art/grass/grass_thick.png.

The tall dense blades of the meadow's curtain rows (scene/surface_view.gd). The strip is trimmed to its drawing (empty rows and columns
off; the flat solid foot along the bottom is kept, it is the line the row stands on) and laid next to a mirrored copy of itself, so it
repeats with no seam. The entry "thick" is added to game/art/grass/grass_manifest.json (the other strips are left as they are).
Needs Pillow and numpy:  python3 tools/art/make_grass_thick.py
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "grass_thick.png")
OUT = os.path.join(ROOT, "game", "art", "grass")
MAN = os.path.join(OUT, "grass_manifest.json")


def main():
    rgba = np.asarray(Image.open(SRC).convert("RGBA"))
    ys, xs = np.nonzero(rgba[..., 3] > 8)
    strip = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    pair = np.concatenate([strip, strip[:, ::-1]], axis=1)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(pair).save(os.path.join(OUT, "grass_thick.png"))
    # how far down the strip its blades close into a solid wall (rows at least 97% covered): the views place rows by it
    cover = (pair[..., 3] > 128).mean(axis=1)
    solid = int(np.argmax(cover >= 0.97))
    man = json.load(open(MAN)) if os.path.exists(MAN) else {"strips": {}}
    man.setdefault("strips", {})["thick"] = {"file": "grass/grass_thick.png", "w": int(pair.shape[1]), "h": int(pair.shape[0]),
        "solid": round(solid / pair.shape[0], 3)}
    json.dump(man, open(MAN, "w"), indent=1)
    print("grass_thick.png %dx%d, solid from %.2f of its height" % (pair.shape[1], pair.shape[0], solid / pair.shape[0]))


if __name__ == "__main__":
    main()
