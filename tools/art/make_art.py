#!/usr/bin/env python3
"""Turn the drawn creature parts in art_src/ into the game's art files (src/mods-unpacked/Judah-InfDNA/content/art/).

For each creature (a body plus two sets of legs, a darker far set and a lighter near set):
  - shrink to the working size, then thicken the dark outline so it still reads when the sprite is drawn small,
  - cut each leg set into its separate legs (the drawn legs overlap, so each leg is found from a few seed points laid along its bones and the picture
    is shared out between them with the outlines in between as the border; see creature_cuts.py),
  - write every piece as its own PNG, cropped, and record where it sits and where it hinges in art_manifest.json.
The game draws the pieces back at those places and swings each leg on its hinge to make it walk.

Needs Pillow:  python3 tools/art/make_art.py
"""
import json
import os
import sys
from collections import deque

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
INK = (21, 18, 26)

# The cutting of the spider, the Void Maw, the bird and the rocks lives in creature_cuts.py (the CREATURES table with the seeds of every leg,
# the fangs and jaw, the bird, the rocks). The tree functions below are separate.
import creature_cuts as CC
CREATURES = CC.CREATURES


def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGBA")


def thicken(im, r):
    """A dark ring r px wide round everything that is opaque (round, in the colour of the artist's own outline): see creature_cuts.thicken."""
    return CC.thicken(im, r)


def components(im, step=3, thresh=24):
    """Connected pieces of the picture, as lists of (x, y) on a grid `step` px wide."""
    a = im.getchannel("A")
    w, h = im.size
    gw, gh = w // step, h // step
    small = a.resize((gw, gh), Image.BILINEAR).point(lambda v: 255 if v > thresh else 0)
    px = small.load()
    seen = [[False] * gw for _ in range(gh)]
    comps = []
    for y in range(gh):
        for x in range(gw):
            if px[x, y] and not seen[y][x]:
                q = deque([(x, y)])
                seen[y][x] = True
                pts = []
                while q:
                    cx, cy = q.popleft()
                    pts.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < gw and 0 <= ny < gh and px[nx, ny] and not seen[ny][nx]:
                            seen[ny][nx] = True
                            q.append((nx, ny))
                comps.append(pts)
    return comps, step


def merge_small(comps, keep_frac=0.04):
    """Fold slivers into the nearest big piece so no stray bits walk about on their own."""
    comps = sorted(comps, key=len, reverse=True)
    if not comps:
        return comps
    big_n = len(comps[0])
    bigs = [c for c in comps if len(c) >= big_n * keep_frac]
    for c in comps:
        if c in bigs:
            continue
        cx = sum(p[0] for p in c) / len(c)
        cy = sum(p[1] for p in c) / len(c)
        best, bd = None, 1e18
        for b in bigs:
            for p in b[::7]:
                d = (p[0] - cx) ** 2 + (p[1] - cy) ** 2
                if d < bd:
                    bd, best = d, b
        best.extend(c)
    return bigs


def cut(im, comps, step, grow=2):
    """One cropped RGBA per piece, with the part of the picture that belongs to it and nothing else."""
    w, h = im.size
    # label map at full resolution, by nearest piece cell
    label = {}
    for i, c in enumerate(comps):
        for (x, y) in c:
            label[(x, y)] = i
    out = []
    a_full = im.getchannel("A")
    for i, c in enumerate(comps):
        mask = Image.new("L", (w // step, h // step), 0)
        mp = mask.load()
        for (x, y) in c:
            mp[x, y] = 255
        mask = mask.filter(ImageFilter.MaxFilter(2 * grow + 1)).resize((w, h), Image.BILINEAR)
        piece = im.copy()
        piece.putalpha(ImageChops.multiply(a_full, mask.point(lambda v: 255 if v > 40 else 0)))
        bb = piece.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if bb is None:
            continue
        crop = piece.crop(bb)
        # the hinge: where the piece meets the body, the middle of the top few rows
        ca = crop.getchannel("A").load()
        cw, chh = crop.size
        top = max(4, chh // 12)
        xs = [x for y in range(top) for x in range(cw) if ca[x, y] > 128]
        px = (sum(xs) / len(xs)) if xs else cw / 2
        out.append({"img": crop, "x": bb[0], "y": bb[1], "pivot": (bb[0] + px, bb[1] + 2.0)})
    out.sort(key=lambda p: p["x"])
    return out


def make_jaws(body, spec):
    """Cut the jaw (or the fangs) out of the body picture: see creature_cuts.make_jaws."""
    return CC.make_jaws(body, spec)


def make_rocks(manifest):
    """The rock sheet, one sprite per rock (7 of them): see creature_cuts.make_rocks."""
    CC.make_rocks(manifest, OUT)


def trim(im, pad=2):
    bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    bb = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(im.size[0], bb[2] + pad), min(im.size[1], bb[3] + pad))
    return im.crop(bb)


def make_trees(manifest):
    """The tree sheet: six sprites cut by hand-placed boxes (some of them touch), kept at the drawing's own size. `leafy` ones carry their leaves all year, so
    the game swaps them for bare trees in winter; the others (dead stump, fallen log, spruce) stand in every season. Each tree comes with a thinned outline
    plus an `ink` layer that gives it back, close-up `shade` and `detail` layers, and hazy far copies (see tree_art.py, which does the work)."""
    import tree_art as T
    sheet = load("trees.png")
    boxes = [("mossoak", True, (0, 0, 925, 670), "moss"), ("stump", False, (900, 50, 1400, 565), "stump"), ("spruce", False, (1395, 0, 1774, 610), "spruce"),
             ("log", False, (20, 625, 940, 887), "log"), ("acacia", True, (825, 568, 1395, 887), "acacia"), ("grove", True, (1395, 585, 1774, 887), "grove")]
    trees = []
    for nm, leafy, box, kind in boxes:
        c = sheet.crop(box)
        # keep only the big connected pieces of this box (another tree's edge can poke into it)
        comps, step = components(c, step=2, thresh=24)
        biggest = max(len(q) for q in comps)
        comps = [q for q in comps if len(q) > 0.12 * biggest]
        parts = cut(c, comps, step, grow=2)
        c2 = Image.new("RGBA", c.size, (0, 0, 0, 0))
        for q in parts:
            c2.alpha_composite(q["img"], (int(q["x"]), int(q["y"])))
        c = trim(c2)
        entry, sizes = T.build_tree(OUT, nm, c, leafy, kind, sum(map(ord, nm)))
        trees.append(entry)
        print("tree %s: %dx%d%s, %d KB" % (nm, c.size[0], c.size[1], " (leafy)" if leafy else "", sum(sizes.values()) // 1024))
    manifest["trees"] = trees


LOOKS = {"summer": (0.31, 1.05, 1.2, 0.03), "spring": (0.22, 1.0, 1.42, 0.06), "orange": (0.07, 1.25, 1.75, 0.1), "red": (0.0, 1.35, 1.55, 0.04), "gold": (0.13, 1.2, 1.85, 0.12)}


def green_center(im):
    """The average hue of a sprite's leaves, so the recolour keeps the spread of tones around it whatever green the picture started from."""
    import tree_art as T
    return T.green_center(im)


def mist(im, k=0.45, height=300):
    """A small, washed-out copy for the far background: the colour pulled toward a pale blue haze."""
    import tree_art as T
    return T.mist(im, k, height)


def recolor(im, hue_to, sat_k, val_k, val_add=0.0):
    """Move the green of the leaves to another colour (the trunk, brown and grey, stays): the autumn and spring versions of a tree."""
    import tree_art as T
    return T.recolor(im, hue_to, sat_k, val_k, val_add)


def make_oaks(manifest):
    """Two full oaks with every season of leaf on them (summer green is the drawing; spring, three autumns); winter uses the game's bare tree. Kept at the
    drawing's own size, with the same thinned outline, ink layer and close-up layers as the other trees."""
    import tree_art as T
    sheet = load("trees2.png")
    comps, step = components(sheet, step=3, thresh=24)
    comps = [c for c in comps if len(c) > 900]
    pieces = cut(sheet, comps, step, grow=3)
    pieces.sort(key=lambda p: p["x"])
    for i, p in enumerate(pieces):
        nm = "oak%d" % (i + 1)
        entry, sizes = T.build_tree(OUT, nm, p["img"], True, "oak", 11 + i)
        manifest["trees"].append(entry)
        print("oak %s: %dx%d, looks %s, %d KB" % (nm, entry["w"], entry["h"], ",".join(entry["looks"].keys()), sum(sizes.values()) // 1024))


def make_bird(manifest):
    """The bird's five parts, each cropped (the open top of the legs closed with an outline); the game assembles and flaps them. See creature_cuts.make_bird."""
    CC.make_bird(manifest, OUT)


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    make_trees(manifest)
    make_oaks(manifest)
    make_bird(manifest)
    make_rocks(manifest)
    CC.make_creatures(manifest, out_dir=OUT)
    with open(os.path.join(OUT, "art_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    sys.exit(main())
