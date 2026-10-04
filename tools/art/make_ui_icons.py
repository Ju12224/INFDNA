#!/usr/bin/env python3
"""Cut the owner's UI sheet (art_src/ui_icons.png, RGBA with real transparency) into the game's icons and frames.

Icons are trimmed to their alpha and scaled so the longer side is ICON px, centred on an ICON x ICON square (they show at 22-72 px on screen, so this keeps them crisp);
the bone frames are kept at half size for nine-patch panels. Output: content/art/ui/<name>.png and content/art/ui/ui_manifest.json.

Every opaque shape on the sheet goes to the piece whose box holds its middle, so a neighbour's antenna tip or claw never comes along.

Needs Pillow, numpy and scipy:  python3 tools/art/make_ui_icons.py
"""
import json
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "ui_icons.png")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "ui")
ICON = 128
FRAME_K = 0.5
# name -> box on the sheet (x0, y0, x1, y1); found by alpha components, the touching crown and cracked rock split at their gap
PIECES = {
    "brood": (36, 200, 260, 392),
    "food_pile": (272, 196, 496, 392),
    "fungus": (504, 160, 728, 396),
    "soldier": (728, 156, 960, 392),
    "queen": (968, 72, 1180, 392),
    "midden": (1192, 196, 1424, 392),
    "food": (392, 444, 600, 640),
    "will": (632, 408, 824, 644),
    "acid": (856, 424, 1068, 676),
    "frame_tall": (32, 564, 216, 1036),
    "frame_wide": (240, 716, 680, 908),
    "frame_small": (312, 912, 608, 1032),
    "dominion": (696, 752, None, 1012),
    "tremors": (None, 752, 1188, 1012),
    "void": (1200, 740, 1428, 1028),
}


def main():
    sheet = Image.open(SRC).convert("RGBA")
    al = np.asarray(sheet)[..., 3]
    # the gap between the crown and the cracked rock: the emptiest column between them
    cols = al[752:1012, 900:960].astype(int).sum(axis=0)
    gap = 900 + int(np.argmin(cols))
    os.makedirs(OUT, exist_ok=True)
    boxes = {}
    for name, (x0, y0, x1, y1) in PIECES.items():
        boxes[name] = (gap if x0 is None else x0, y0, gap if x1 is None else x1, y1)
    lab, n = ndimage.label(al > 8, structure=np.ones((3, 3), int))
    owner = np.zeros(n + 1, dtype=object)
    centres = ndimage.center_of_mass(np.ones_like(lab), lab, range(1, n + 1))
    keep = {name: [] for name in PIECES}
    for i, (cy, cx) in enumerate(centres, start=1):
        for name, (x0, y0, x1, y1) in boxes.items():
            if x0 <= cx <= x1 and y0 <= cy <= y1:
                keep[name].append(i)
                break
    rgba = np.asarray(sheet)
    man = {}
    for name in PIECES:
        mask = np.isin(lab, keep[name])
        ys, xs = np.nonzero(mask)
        a = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
        a[..., 3] = np.where(mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1], a[..., 3], 0)
        im = Image.fromarray(a, "RGBA")
        k = FRAME_K if name.startswith("frame") else ICON / float(max(im.size))
        im = im.resize((max(1, int(round(im.width * k))), max(1, int(round(im.height * k)))), Image.LANCZOS)
        if not name.startswith("frame"):
            sq = Image.new("RGBA", (ICON, ICON), (0, 0, 0, 0))      # icons are drawn into square boxes: pad, never stretch
            sq.alpha_composite(im, ((ICON - im.width) // 2, (ICON - im.height) // 2))
            im = sq
        im.save(os.path.join(OUT, name + ".png"), optimize=True)
        man[name] = {"file": "ui/" + name + ".png", "w": im.width, "h": im.height}
        print(name, im.size, len(keep[name]), "shapes")
    with open(os.path.join(OUT, "ui_manifest.json"), "w") as f:
        json.dump(man, f, indent=1)


if __name__ == "__main__":
    main()
