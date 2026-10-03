#!/usr/bin/env python3
"""Turn the drawn creature parts in art_src/ into the game's art files (src/mods-unpacked/Judah-InfDNA/content/art/).

For each creature (a body plus two sets of legs, a darker far set and a lighter near set):
  - shrink to the working size, then thicken the dark outline so it still reads when the sprite is drawn small,
  - cut each leg set into its separate legs (connected pieces of the picture; slivers are folded into their neighbour),
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

# name -> working width, extra outline (px at that width), game length (px nose to tail at scale 1), draw order, glow
CREATURES = {
    "spider": {"width": 724, "outline": 4, "length": 120.0, "order": ["far", "body", "near"], "glow": False,
               # the cream fangs, cut out by colour inside this box (body-picture pixels) and hinged at their tops
               "jaws": {"kind": "color", "box": [420, 305, 581, 452], "open": [0.2, -0.16], "cavity": (26, 18, 38)},
               "wave": False},
    "void": {"width": 1180, "outline": 5, "length": 420.0, "order": ["far", "near", "body"], "glow": True,
             # the lower jaw: the big claws and the lower teeth, everything under the line of the mouth; it swings on the back corner of the mouth
             "jaws": {"kind": "poly", "poly": [(838, 296), (912, 296), (925, 326), (1056, 326), (1062, 440), (1040, 540), (838, 570)],
                      "pivot": (845, 318), "open": [0.34], "cavity": (22, 8, 38),
                      # the dark of the throat, drawn behind the jaw so an open mouth looks into the void (and never spills outside the head)
                      "cavity_poly": [(905, 292), (1040, 288), (1068, 330), (1055, 410), (990, 436), (935, 400), (905, 345)]},
             "wave": True},
}


def load(name):
    return Image.open(os.path.join(SRC, name)).convert("RGBA")


def thicken(im, r):
    """A dark ring r px wide round everything that is opaque."""
    a = im.getchannel("A")
    grown = a.filter(ImageFilter.MaxFilter(2 * r + 1))
    ring = Image.new("RGBA", im.size, INK + (0,))
    ring.putalpha(grown)
    ring.alpha_composite(im)
    return ring


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
    """Cut the jaw (or the fangs) out of the body picture. Returns (body without them, [pieces], cavity image or None)."""
    jw = spec["jaws"]
    bw, bh = body.size
    pieces = []
    if jw["kind"] == "poly":
        mask = Image.new("L", body.size, 0)
        ImageDraw.Draw(mask).polygon(jw["poly"], fill=255)
        masks = [(mask, jw["pivot"], jw["open"][0])]
    else:
        x0, y0, x1, y1 = jw["box"]
        px = body.load()
        m = Image.new("L", body.size, 0)
        mp = m.load()
        for y in range(y0, min(y1, bh)):
            for x in range(x0, min(x1, bw)):
                r, g, b, a = px[x, y]
                if a > 200 and r > 190 and g > 175 and b > 130 and abs(r - b) < 120:
                    mp[x, y] = 255
        # the fangs together with the ink round them, as separate pieces
        comps, step = components(m.convert("RGBA").copy().convert("RGBA"), step=2, thresh=40) if False else (None, 2)
        # label by connected pieces of the mask itself
        small = m.resize((bw // 2, bh // 2), Image.BILINEAR).point(lambda v: 255 if v > 60 else 0)
        sp = small.load()
        seen = set()
        groups = []
        for y in range(small.size[1]):
            for x in range(small.size[0]):
                if sp[x, y] and (x, y) not in seen:
                    q = deque([(x, y)])
                    seen.add((x, y))
                    pts = []
                    while q:
                        cx, cy = q.popleft()
                        pts.append((cx, cy))
                        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                            nx, ny = cx + dx, cy + dy
                            if 0 <= nx < small.size[0] and 0 <= ny < small.size[1] and sp[nx, ny] and (nx, ny) not in seen:
                                seen.add((nx, ny))
                                q.append((nx, ny))
                    groups.append(pts)
        groups = [g for g in groups if len(g) > 40]
        groups.sort(key=lambda g: min(p[0] for p in g))
        masks = []
        for gi, g in enumerate(groups):
            gm = Image.new("L", small.size, 0)
            gp = gm.load()
            for (x, y) in g:
                gp[x, y] = 255
            gm = gm.filter(ImageFilter.MaxFilter(9)).resize(body.size, Image.BILINEAR).point(lambda v: 255 if v > 40 else 0)
            ys = [p[1] * 2 for p in g]
            xs = [p[0] * 2 for p in g if p[1] * 2 <= min(ys) + 14]
            pivot = (sum(xs) / max(1, len(xs)), min(ys))
            masks.append((gm, pivot, jw["open"][gi % len(jw["open"])]))
    cut_mask = Image.new("L", body.size, 0)
    for mk, pivot, ang in masks:
        cut_mask = ImageChops.lighter(cut_mask, mk)
        piece = body.copy()
        piece.putalpha(ImageChops.multiply(body.getchannel("A"), mk))
        bb = piece.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        if bb is None:
            continue
        pieces.append({"img": piece.crop(bb), "x": bb[0], "y": bb[1], "pivot": [round(pivot[0], 1), round(pivot[1], 1)], "open": ang})
    rest = body.copy()
    rest.putalpha(ImageChops.multiply(body.getchannel("A"), ImageChops.invert(cut_mask)))
    # the hollow the jaw leaves behind: the shape of what was cut, filled with the dark of the mouth, so an open mouth looks into the void
    hollow = ImageChops.multiply(body.getchannel("A"), cut_mask).filter(ImageFilter.MaxFilter(5))
    if jw.get("cavity_poly"):
        hollow = Image.new("L", body.size, 0)
        ImageDraw.Draw(hollow).polygon(jw["cavity_poly"], fill=255)
        hollow = ImageChops.multiply(hollow.filter(ImageFilter.GaussianBlur(3)), body.getchannel("A"))      # never outside the head's outline
    cav = Image.new("RGBA", body.size, tuple(jw["cavity"]) + (0,))
    if jw.get("cavity_poly"):
        # the void is not flat: darkest at the edges, a violet glow deep in the throat
        from PIL import ImageOps
        xs = [q[0] for q in jw["cavity_poly"]]
        ys = [q[1] for q in jw["cavity_poly"]]
        bx0, by0, bx1, by1 = min(xs), min(ys), max(xs), max(ys)
        rg = Image.radial_gradient("L").resize((int(bx1 - bx0), int(by1 - by0)))
        rg = ImageOps.invert(rg)
        glow = ImageOps.colorize(rg, black=tuple(jw["cavity"]), white=(92, 36, 140)).convert("RGBA")
        cav.paste(glow, (int(bx0), int(by0)))
    cav.putalpha(hollow)
    cbb = cav.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    cavity = {"img": cav.crop(cbb), "x": cbb[0], "y": cbb[1]} if cbb else None
    return rest, pieces, cavity


def make_rocks(manifest):
    """The rock sheet: every separate rock (a boulder with its own pebbles round it counts as one) becomes a sprite for the meadow."""
    sheet = load("rocks.png")
    k = 0.4
    sheet = sheet.resize((int(sheet.size[0] * k), int(sheet.size[1] * k)), Image.LANCZOS)
    sheet = thicken(sheet, 3)
    comps, step = components(sheet, step=3, thresh=24)
    comps = [c for c in comps if len(c) > 12]
    pieces = cut(sheet, comps, step)
    pieces.sort(key=lambda p: -(p["img"].size[0] * p["img"].size[1]))
    rocks = []
    for i, p in enumerate(pieces):
        fn = "rock_%d.png" % i
        p["img"].save(os.path.join(OUT, fn), optimize=True)
        w, h = p["img"].size
        rocks.append({"file": fn, "w": w, "h": h, "tall": h > 1.25 * w})
        print("rock %d: %dx%d%s" % (i, w, h, " (spire)" if h > 1.25 * w else ""))
    manifest["rocks"] = rocks


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
    """The bird's five parts, each cropped; the game assembles and flaps them."""
    parts = {}
    for nm in ["head", "wing_a", "wing_b", "claw_1", "claw_2"]:
        im = load("bird_%s.png" % nm)
        im = im.resize((int(im.size[0] * 0.4), int(im.size[1] * 0.4)), Image.LANCZOS)
        t = trim(im)
        fn = "bird_%s.png" % nm
        t.save(os.path.join(OUT, fn), optimize=True)
        parts[nm] = {"file": fn, "w": t.size[0], "h": t.size[1]}
        print("bird %s: %dx%d" % (nm, t.size[0], t.size[1]))
    manifest["bird"] = parts


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
    make_trees(manifest)
    make_oaks(manifest)
    make_bird(manifest)
    make_rocks(manifest)
    for name, spec in CREATURES.items():
        body = load(name + "_body.png")
        la = load(name + "_legs_a.png")
        lb = load(name + "_legs_b.png")
        w0, h0 = body.size
        k = spec["width"] / float(w0)
        size = (spec["width"], int(round(h0 * k)))

        def prep(im):
            return thicken(im.resize(size, Image.LANCZOS), spec["outline"])

        body, la, lb = prep(body), prep(la), prep(lb)
        # the darker set of legs is the far side
        def bright(im):
            px = [p for p in im.resize((120, 120)).getdata() if p[3] > 200]
            return sum((p[0] + p[1] + p[2]) / 3 for p in px) / max(1, len(px))
        far, near = (la, lb) if bright(la) <= bright(lb) else (lb, la)
        entry = {"canvas": list(size), "order": spec["order"], "parts": [], "wave": bool(spec.get("wave", False))}
        union = None
        for layer, im in (("far", far), ("near", near)):
            comps, step = components(im)
            comps = merge_small(comps)
            pieces = cut(im, comps, step)
            for i, p in enumerate(pieces):
                fn = "%s_%s_%d.png" % (name, layer, i)
                p["img"].save(os.path.join(OUT, fn), optimize=True)
                entry["parts"].append({"layer": layer, "file": fn, "x": p["x"], "y": p["y"], "pivot": [round(p["pivot"][0], 1), round(p["pivot"][1], 1)], "phase": (i % 2)})
                bb = (p["x"], p["y"], p["x"] + p["img"].size[0], p["y"] + p["img"].size[1])
                union = bb if union is None else (min(union[0], bb[0]), min(union[1], bb[1]), max(union[2], bb[2]), max(union[3], bb[3]))
        bb = body.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        bodyc = body.crop(bb)
        entry["body"] = {"file": name + "_body.png", "x": bb[0], "y": bb[1]}
        glow_src = bodyc
        if spec.get("jaws"):
            rest, pieces, cavity = make_jaws(bodyc, spec)
            rest.save(os.path.join(OUT, name + "_body.png"), optimize=True)
            entry["jaws"] = []
            for i, p in enumerate(pieces):
                fn = "%s_jaw_%d.png" % (name, i)
                p["img"].save(os.path.join(OUT, fn), optimize=True)
                entry["jaws"].append({"file": fn, "x": bb[0] + p["x"], "y": bb[1] + p["y"], "pivot": [bb[0] + p["pivot"][0], bb[1] + p["pivot"][1]], "open": p["open"]})
            if cavity is not None:
                cavity["img"].save(os.path.join(OUT, name + "_cavity.png"), optimize=True)
                entry["cavity"] = {"file": name + "_cavity.png", "x": bb[0] + cavity["x"], "y": bb[1] + cavity["y"]}
        else:
            bodyc.save(os.path.join(OUT, name + "_body.png"), optimize=True)
        union = (min(union[0], bb[0]), min(union[1], bb[1]), max(union[2], bb[2]), max(union[3], bb[3]))
        # the glow of the cracks and eyes (violet pixels of the body, brightened and softened)
        if spec["glow"]:
            g = glow_src.convert("RGBA")
            gp = g.load()
            gw, gh = g.size
            mask = Image.new("L", g.size, 0)
            mp = mask.load()
            for y in range(gh):
                for x in range(gw):
                    r, gg, b, a = gp[x, y]
                    if a > 200 and b > 120 and b - gg > 70 and r > 60:
                        mp[x, y] = 255
            halo = mask.filter(ImageFilter.GaussianBlur(3.0))
            glow = Image.new("RGBA", g.size, (214, 140, 255, 0))
            glow.putalpha(halo)
            glow.save(os.path.join(OUT, name + "_glow.png"), optimize=True)
            entry["glow"] = {"file": name + "_glow.png", "x": bb[0], "y": bb[1]}
        # the feet: the middle of everything, on the lowest point of the legs
        entry["feet"] = [round((union[0] + union[2]) / 2.0, 1), float(union[3])]
        entry["width"] = float(union[2] - union[0])
        entry["height"] = float(union[3] - union[1])
        entry["scale"] = round(spec["length"] / entry["width"], 5)
        manifest[name] = entry
        print("%s: %d parts, canvas %s, game scale %.4f" % (name, len(entry["parts"]), size, entry["scale"]))
    with open(os.path.join(OUT, "art_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    sys.exit(main())
