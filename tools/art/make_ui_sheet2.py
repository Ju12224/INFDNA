#!/usr/bin/env python3
"""Cut the owner's second UI sheet (art_src/ui_sheet2.png, RGBA with real transparency).

Row 1: the six chamber icons (brood, food store, fungus farm, armory, queen, midden) -> content/art/ui/chamber_<kind>.png
Row 2: food, a blue flame (Will), purple ooze (mutation), a depth gauge, two stone frames, a red crown (Apex), cracked rock, the void
       -> content/art/ui/<name>.png (icons on 128 px squares, the gauge and frames at half size)
Row 3: ten autumn leaves -> content/art/leaves/leaf_<n>.png (96 px on the long side; season_view.gd lets them fall)
Row 4: void ant parts -> content/art/void_parts/<name>.png (half size, for the Void creatures)
Row 5 holds small anteater parts; the big ones on art_src/anteater_parts.png are used instead.

The biggest shape in each box is that piece; every smaller shape (sparks, drips, flakes) joins the piece whose nearest pixel is
closest to it. Needs Pillow, numpy and scipy:  python3 tools/art/make_ui_sheet2.py
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "ui_sheet2.png")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
# name -> (box on the sheet, output folder, mode: "icon" = 128 square, "half" = half size, "leaf" = 96 px long side)
PIECES = [
    ("chamber_brood", (17, 10, 211, 214), "ui", "icon"),
    ("chamber_food", (221, 21, 410, 211), "ui", "icon"),
    ("chamber_farm", (416, 11, 610, 213), "ui", "icon"),
    ("chamber_armory", (618, 13, 813, 213), "ui", "icon"),
    ("chamber_queen", (822, 11, 1036, 210), "ui", "icon"),
    ("chamber_midden", (1046, 25, 1254, 209), "ui", "icon"),
    ("forage", (13, 227, 174, 382), "ui", "icon"),
    ("will_flame", (188, 227, 327, 382), "ui", "icon"),
    ("ooze", (339, 228, 493, 382), "ui", "icon"),
    ("depth_gauge", (516, 217, 677, 398), "ui", "half"),
    ("stone_wide", (709, 226, 921, 380), "ui", "half"),
    ("stone_small", (927, 240, 1031, 354), "ui", "half"),
    ("crown_red", (1048, 221, 1177, 374), "ui", "icon"),
    ("tremors2", (1185, 240, 1343, 379), "ui", "icon"),
    ("void2", (1351, 217, 1523, 389), "ui", "icon"),
] + [("leaf_%d" % i, box, "leaves", "leaf") for i, box in enumerate([
    (11, 389, 139, 531), (140, 392, 281, 536), (293, 393, 390, 531), (394, 403, 526, 525), (553, 418, 765, 516),
    (778, 404, 888, 525), (919, 403, 1108, 530), (1104, 394, 1209, 532), (1223, 440, 1383, 525), (1390, 404, 1527, 518)])] + [
    ("head_a", (11, 542, 208, 708), "void_parts", "half"),
    ("head_b", (211, 555, 368, 703), "void_parts", "half"),
    ("thorax", (378, 536, 559, 708), "void_parts", "half"),
    ("gaster", (572, 535, 787, 705), "void_parts", "half"),
    ("legs", (786, 533, 994, 708), "void_parts", "half"),
    ("mandible", (987, 539, 1194, 706), "void_parts", "half"),
    ("wing", (1207, 549, 1386, 708), "void_parts", "half"),
    ("stinger", (1370, 535, 1523, 713), "void_parts", "half"),
]


def main():
    im = Image.open(SRC).convert("RGBA")
    rgba = np.asarray(im)
    lab, n = ndimage.label(rgba[..., 3] > 8, structure=np.ones((3, 3), int))
    sizes = ndimage.sum(np.ones_like(lab), lab, range(1, n + 1))
    cent = ndimage.center_of_mass(np.ones_like(lab), lab, range(1, n + 1))
    body = {}
    for name, (x0, y0, x1, y1), _f, _m in PIECES:
        inside = [i for i, (cy, cx) in enumerate(cent, start=1) if x0 <= cx <= x1 and y0 <= cy <= y1]
        if inside:
            body[name] = max(inside, key=lambda i: sizes[i - 1])
    dist = {k: ndimage.distance_transform_edt(lab != b) for k, b in body.items()}
    owned = {k: [b] for k, b in body.items()}
    bodies = set(body.values())
    for i in range(1, n + 1):
        if i in bodies or sizes[i - 1] < 12:
            continue
        cy, cx = cent[i - 1]
        if cy > 715:
            continue                     # the small anteater row is not cut
        m = lab == i
        k = min(dist, key=lambda kk: dist[kk][m].min())
        if dist[k][m].min() < 40:
            owned[k].append(i)
    for name, _box, folder, mode in PIECES:
        if name not in owned:
            print("missing", name)
            continue
        mask = np.isin(lab, owned[name])
        ys, xs = np.nonzero(mask)
        a = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1].copy()
        a[..., 3] = np.where(mask[ys.min():ys.max() + 1, xs.min():xs.max() + 1], a[..., 3], 0)
        pic = Image.fromarray(a, "RGBA")
        if mode == "icon":
            s = 116.0 / max(pic.size)
        elif mode == "leaf":
            s = 96.0 / max(pic.size)
        else:
            s = 0.5
        pic = pic.resize((max(1, int(round(pic.width * s))), max(1, int(round(pic.height * s)))), Image.LANCZOS)
        if mode == "icon":
            sq = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
            sq.alpha_composite(pic, ((128 - pic.width) // 2, (128 - pic.height) // 2))
            pic = sq
        os.makedirs(os.path.join(ART, folder), exist_ok=True)
        pic.save(os.path.join(ART, folder, name + ".png"), optimize=True)
        print(name, pic.size, len(owned[name]))


if __name__ == "__main__":
    main()
