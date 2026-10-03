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
    "void": {"width": 1180, "outline": 5, "length": 520.0, "order": ["far", "near", "body"], "glow": True,
             # the lower jaw: the big claws and the lower teeth, everything under the line of the mouth; it swings on the back corner of the mouth
             "jaws": {"kind": "poly", "poly": [(838, 292), (912, 292), (925, 322), (1070, 322), (1072, 284), (1180, 284), (1180, 570), (838, 570)],
                      "pivot": (845, 318), "open": [0.34], "cavity": (22, 8, 38)},
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
    cav = Image.new("RGBA", body.size, tuple(jw["cavity"]) + (0,))
    cav.putalpha(hollow)
    cbb = cav.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    cavity = {"img": cav.crop(cbb), "x": cbb[0], "y": cbb[1]} if cbb else None
    return rest, pieces, cavity


def main():
    os.makedirs(OUT, exist_ok=True)
    manifest = {}
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
        entry = {"canvas": list(size), "order": spec["order"], "parts": []}
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
        entry["scale"] = round(spec["length"] / entry["width"], 5)
        manifest[name] = entry
        print("%s: %d parts, canvas %s, game scale %.4f" % (name, len(entry["parts"]), size, entry["scale"]))
    with open(os.path.join(OUT, "art_manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    print("wrote", OUT)


if __name__ == "__main__":
    sys.exit(main())
