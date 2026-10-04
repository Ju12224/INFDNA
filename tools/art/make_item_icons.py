#!/usr/bin/env python3
"""Cut the owner's Lab item icon sheets into one icon per item: content/art/items/<item id>.png (128 x 128, transparent, the drawing
centred and fitted), named by the item ids in core/shop_items.gd. The game prefers these over the Brotato icons (ui_kit.item_icon).

Each sheet is a grid; every opaque shape (motion lines, sparks and drips included) goes to the grid cell that holds its middle.
Add a sheet: its file, its grid (columns, rows) and the item ids row by row ("" for a cell to skip).

Needs Pillow, numpy and scipy:  python3 tools/art/make_item_icons.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "items")
SIZE = 128
PAD = 6
SHEETS = [
    ("trait_icons.png", 5, 4, [
        "swift", "pincer", "tendril", "keen", "spider",
        "chitin", "thorn", "giant", "octopus", "hox",
        "alate", "sting", "formic", "major", "replete",
        "glow", "camo", "trail", "fuzz", "cricket",
    ]),
]


def cut(sheet_file, cols, rows, names):
    im = Image.open(os.path.join(ROOT, "art_src", sheet_file)).convert("RGBA")
    rgba = np.asarray(im)
    al = rgba[..., 3]
    lab, n = ndimage.label(al > 8, structure=np.ones((3, 3), int))
    centres = ndimage.center_of_mass(np.ones_like(lab), lab, range(1, n + 1))
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    cw, chh = im.width / float(cols), im.height / float(rows)
    # the biggest shape in each cell is that icon's body; a small shape (a drip, a spark, a speed line) joins the body whose nearest pixel
    # is closest to it, which may be in the next cell (a drip hanging below the line between two rows)
    body = {}
    for i, (cy, cx) in enumerate(centres, start=1):
        k = min(rows - 1, int(cy // chh)) * cols + min(cols - 1, int(cx // cw))
        if k not in body or sizes[i - 1] > sizes[body[k] - 1]:
            body[k] = i
    dist = {k: ndimage.distance_transform_edt(lab != b) for k, b in body.items()}
    cells = {k: [b] for k, b in body.items()}
    bodies = set(body.values())
    for i in range(1, n + 1):
        if i in bodies or sizes[i - 1] < 12:
            continue                       # bodies are placed; dust is dropped
        m = lab == i
        best = min(dist, key=lambda k: dist[k][m].min())
        cells[best].append(i)
    for k, name in enumerate(names):
        if not name or k not in cells:
            continue
        mask = np.isin(lab, cells[k])
        ys, xs = np.nonzero(mask)
        a = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
        a[..., 3] = np.where(mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1], a[..., 3], 0)
        pic = Image.fromarray(a, "RGBA")
        s = (SIZE - 2 * PAD) / float(max(pic.size))
        pic = pic.resize((max(1, int(round(pic.width * s))), max(1, int(round(pic.height * s)))), Image.LANCZOS)
        sq = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        sq.alpha_composite(pic, ((SIZE - pic.width) // 2, (SIZE - pic.height) // 2))
        sq.save(os.path.join(OUT, name + ".png"), optimize=True)
        print(name, len(cells[k]), "shapes")


def main():
    os.makedirs(OUT, exist_ok=True)
    for sheet in SHEETS:
        cut(*sheet)


if __name__ == "__main__":
    main()
