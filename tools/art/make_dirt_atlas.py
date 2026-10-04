#!/usr/bin/env python3
"""The soil's texture: the owner's seamless dirt centre tiles (art_src/dirt_tiles.png), their dark rims cut away (the interiors snap
together), laid in a fixed random order on a 5 x 5 grid of 160 x 128 px tiles: one picture that repeats seamlessly (terrain_view.gd lays it
over the whole soil in world space and tints it by soil layer). Never mirrored: mirrored tiles read as a kaleidoscope. One baked picture
rather than a tile picked per patch in the shader, because a per-patch pick breaks the mipmaps at every tile edge (thin lines far out).
Output: content/art/terrain/dirt_soil.png.  Needs Pillow:  python3 tools/art/make_dirt_atlas.py
"""
import os
import random

from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "dirt_tiles.png")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "terrain", "dirt_soil.png")
N = 5
BOXES = [(12, 50, 216, 212), (229, 49, 410, 212), (567, 49, 731, 212), (743, 48, 911, 213), (13, 405, 215, 564), (227, 405, 404, 565)]
INSET = 14
TW, TH = 160, 128


def main():
    im = Image.open(SRC).convert("RGBA")
    tiles = [im.crop((x0 + INSET, y0 + INSET, x1 - INSET, y1 - INSET)).resize((TW, TH), Image.LANCZOS).convert("RGB") for x0, y0, x1, y1 in BOXES]
    rng = random.Random(7)
    soil = Image.new("RGB", (TW * N, TH * N))
    prev_row = [None] * N
    for j in range(N):
        left = None
        for i in range(N):
            choices = [k for k in range(len(tiles)) if k != left and k != prev_row[i]] or list(range(len(tiles)))
            k = rng.choice(choices)       # never the same tile twice side by side or stacked
            soil.paste(tiles[k], (i * TW, j * TH))
            left = k
            prev_row[i] = k
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    soil.save(OUT, optimize=True)
    small = soil.resize((1, 1), Image.BOX).getpixel((0, 0))
    print("wrote", OUT, soil.size, "average colour", ["%.3f" % (v / 255.0) for v in small])


if __name__ == "__main__":
    main()
