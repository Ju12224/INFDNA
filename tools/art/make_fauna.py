#!/usr/bin/env python3
"""Cut the owner's FAUNA + FOOD sheet (art_src/fauna_sheet.png) into one transparent PNG per item for the game.

The sheet is an RGBA picture with real transparency (a thick near-black ink outline round every item, soft antialiased edges, a haze of
nearly invisible alpha 1-9 dust round them).  So there is no matte to build and nothing to flood-fill: the alpha channel is the cut.
  1. clean the alpha: below ALPHA_DUST (10) is dust and becomes 0, ALPHA_OPAQUE (250) and above is opaque (the file never reaches 255);
     the colour of the antialiased rim pixels (partly transparent, within 2 px of the clear background: a smear of the old black background)
     is repainted flat ink, so no dark or coloured fringe can show on any background (honeydew, which has a brown rim instead of ink, gets
     its own rim colour); partly transparent pixels deeper inside (the moss shade between the aphids) keep their colour,
  2. split the sheet into items: connected pieces of the alpha, picked by hand-tuned boxes on their centre (honeydew = one item although its
     drops are separate islands, the crumb and apple keep their little crumbs, the aphid heap, the eggs, the hornet with its wings, the
     earthworm, the berries are one item each),
  3. each item is trimmed to its alpha bounding box, shrunk to at most MAXSIDE px on the long side (premultiplied LANCZOS) and saved in
     content/art/fauna/<name>.png (optimize=True).
fauna_manifest.json lists every item with size, facing, ground contact point, length of the body in the picture, a game size suggestion
and notes on how the single picture can be animated.

Needs Pillow only:  python3 tools/art/make_fauna.py [--contact PATH] [--debug DIR] [--only a,b]
  --contact PATH   write a verification contact sheet (every item on grey checker and on dark brown, with its label)
  --debug DIR      write assign.png (which piece of the sheet went to which item)
Does not import or touch make_art.py / make_antkit.py.
"""
import json
import os
import sys
from collections import deque

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "fauna_sheet.png")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "fauna")
MANIFEST = os.path.join(ART, "fauna_manifest.json")
INK = (21, 18, 26)          # the house outline colour (same as make_art.py / make_antkit.py)
MAXSIDE = 320               # longest side of any saved item
PAD = 2                     # transparent border kept round every item
ALPHA_DUST = 10            # alpha below this is dust (a haze of alpha 1-9 lies round every item)
ALPHA_OPAQUE = 240          # alpha at or above this counts as opaque (the file's solid pixels are 250-254, the honeydew drops' 247-249)
MIN_PIECE = 30              # a connected piece with fewer opaque pixels than this is dust
WORKER_PX = 40.0            # the game's worker ant is drawn about this long (px at scale 1); the size suggestions are relative to it


# ---------------------------------------------------------------------------------------------------------------- helpers

def label_pixels(mask):
    """Connected pieces (8-neighbour) of a mask: [{area, cx, cy, box, pts}], pts as flat (x, y) tuples."""
    w, h = mask.size
    px = mask.load()
    seen = bytearray(w * h)
    comps = []
    for y0 in range(h):
        for x0 in range(w):
            if px[x0, y0] and not seen[y0 * w + x0]:
                q = deque([(x0, y0)])
                seen[y0 * w + x0] = 1
                pts = []
                while q:
                    cx, cy = q.popleft()
                    pts.append((cx, cy))
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
                        nx, ny = cx + dx, cy + dy
                        if 0 <= nx < w and 0 <= ny < h and px[nx, ny] and not seen[ny * w + nx]:
                            seen[ny * w + nx] = 1
                            q.append((nx, ny))
                xs = [p[0] for p in pts]
                ys = [p[1] for p in pts]
                comps.append({"area": len(pts), "cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys),
                              "box": (min(xs), min(ys), max(xs) + 1, max(ys) + 1), "pts": pts})
    return comps


def mask_of(size, comps):
    m = Image.new("L", size, 0)
    p = m.load()
    for c in comps:
        for (x, y) in c["pts"]:
            p[x, y] = 255
    return m


# ---------------------------------------------------------------------------------------------------------------- the sheet

def load_sheet():
    """The sheet as RGBA with the alpha cleaned (dust gone, solid pixels fully opaque) and the colour of the soft edge repainted ink."""
    im = Image.open(SRC).convert("RGBA")
    a = im.getchannel("A").point(lambda v: 0 if v < ALPHA_DUST else (255 if v >= ALPHA_OPAQUE else v))
    return im, a


def find_pieces(a):
    """Connected pieces of the cleaned alpha (8-neighbour), without dust: [{area, cx, cy, box, pts}]."""
    solid = a.point(lambda v: 255 if v >= 128 else 0)
    comps = label_pixels(a.point(lambda v: 255 if v > 0 else 0))
    sp = solid.load()
    out = []
    for c in comps:
        c["solid"] = sum(1 for (x, y) in c["pts"] if sp[x, y])
        if c["solid"] >= MIN_PIECE:
            out.append(c)
    return out


def pick(pieces, boxes, claimed):
    """The pieces whose centre lies in any of the boxes and that nobody has taken yet."""
    out = []
    for i, c in enumerate(pieces):
        if i in claimed:
            continue
        if any(x0 <= c["cx"] < x1 and y0 <= c["cy"] < y1 for (x0, y0, x1, y1) in boxes):
            out.append(i)
    return out


def item_image(im, a, pieces, idx, opts):
    """RGBA crop of one item: the pixels of its pieces only (neighbours' bits cut away), alpha as cleaned, edge colours repainted ink."""
    m = mask_of(im.size, [pieces[i] for i in idx])
    bb = m.getbbox()
    box = (max(0, bb[0] - 2), max(0, bb[1] - 2), min(im.size[0], bb[2] + 2), min(im.size[1], bb[3] + 2))
    m = m.crop(box)
    alpha = ImageChops.multiply(a.crop(box), m.point(lambda v: 255 if v else 0))
    rgb = im.crop(box).convert("RGB")
    ink = tuple(opts.get("ink_color", INK))
    # the colour of the rim (the antialiased edge pixels) and of the clear pixels is the ink colour: no halo of the old black background, and
    # a filtered (bilinear) texture never blends a coloured fringe in
    clear = alpha.point(lambda v: 255 if v == 0 else 0).filter(ImageFilter.MaxFilter(5))            # within 2 px of the clear background
    edge = ImageChops.darker(clear, alpha.point(lambda v: 255 if v < 255 else 0))        # (the clear pixels themselves included)
    rgb = Image.composite(Image.new("RGB", rgb.size, ink), rgb, edge)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out, box[:2]


def trim(im, pad=PAD):
    bb = im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if bb is None:
        return im
    bb = (max(0, bb[0] - pad), max(0, bb[1] - pad), min(im.size[0], bb[2] + pad), min(im.size[1], bb[3] + pad))
    return im.crop(bb)


def shrink(im, maxside=MAXSIDE):
    w, h = im.size
    k = min(1.0, maxside / float(max(w, h)))
    if k >= 1.0:
        return im, 1.0
    return im.resize((max(1, int(round(w * k))), max(1, int(round(h * k)))), Image.LANCZOS), k


# ---------------------------------------------------------------------------------------------------------------- catalogue
# name -> where the item sits on the sheet (boxes: connected pieces of the alpha whose centre is inside belong to it) and its recipe.
#   kind     creature / brood / food / plant  (the game side)
#   facing   which way the picture looks (right / left / none); the ants and beetles look right
#   len      game length in px at scale 1 for a worker ant drawn 40 px long (the item's body span in the picture is scaled to it)
#   anim     how the single picture can be moved: bob (px up and down at game size), squash (fraction of height; stretch is the same the other
#            way), wiggle (degrees of sway), pulse (grow and shrink)
#   ink_color  colour of the soft edge pixels (default INK; honeydew has a brown rim)

def P(name, kind, boxes, facing, length, anim, note, **opts):
    if boxes and isinstance(boxes[0], (int, float)):
        boxes = [boxes]
    d = {"name": name, "kind": kind, "boxes": list(boxes), "facing": facing, "len": length, "anim": anim, "note": note}
    d.update(opts)
    return d


CATALOGUE = [
    # ---- top row: the brood and the queen
    P("queen_full", "creature", [(0, 0, 672, 284)], "right", 90, {"bob": 1.2, "squash": 0.03, "wiggle": 0}, "Queen with the egg-laden gaster; walks slowly, no separate legs."),
    P("eggs", "brood", [(672, 60, 912, 280)], "none", 16, {"pulse": 0.04}, "A pile of cream eggs (one picture)."),
    P("larva", "brood", [(912, 40, 1112, 280)], "left", 22, {"squash": 0.10, "wiggle": 4}, "Fat cream larva, head at the lower left; can wriggle by squashing."),
    P("pupa", "brood", [(1112, 40, 1298, 280)], "none", 24, {"pulse": 0.03, "wiggle": 2}, "Pupa wrapped in a silk cocoon with the brown pupa showing in the slit."),
    P("worker_small", "creature", [(1298, 90, 1536, 280)], "right", 34, {"bob": 1.0, "squash": 0.04}, "Small pale worker ant (nest worker)."),
    # ---- second row: food and small things
    P("seeds", "food", [(0, 280, 195, 450)], "none", 16, {}, "Heap of seeds and grains."),
    P("berries", "food", [(195, 280, 370, 450)], "none", 14, {}, "Cluster of red berries with leaves."),
    P("crumb", "food", [(370, 280, 540, 450)], "none", 12, {}, "Bread crumb with three little crumbs beside it."),
    P("apple", "food", [(540, 280, 690, 450)], "none", 22, {}, "Bitten apple with three crumbs."),
    P("beetle", "creature", [(690, 290, 890, 450)], "right", 40, {"bob": 1.0, "squash": 0.04}, "Small dark beetle."),
    P("honeydew", "food", [(890, 290, 1022, 450)], "none", 14, {"pulse": 0.05}, "Honeydew droplets: six golden drops (one item, gaps transparent).",
      ink_color=(64, 38, 12)),
    P("aphids", "creature", [(1022, 270, 1185, 450)], "none", 8, {"squash": 0.05, "wiggle": 3}, "Heap of five green aphids on moss (one item)."),
    P("mushrooms", "food", [(1185, 265, 1375, 450)], "none", 26, {}, "Cluster of white mushrooms on a mound of earth."),
    P("leaf", "plant", [(1375, 265, 1536, 450)], "none", 28, {}, "Green leaf with three holes and a bitten edge."),
    # ---- third row: bigger animals
    P("stagbeetle", "creature", [(0, 445, 405, 662)], "right", 90, {"bob": 1.5, "squash": 0.03}, "Stag beetle with big red jaws."),
    P("centipede", "creature", [(405, 445, 775, 628)], "right", 120, {"bob": 1.0, "wiggle": 3, "squash": 0.03}, "Centipede, head right."),
    P("scorpion", "creature", [(775, 440, 1085, 640)], "right", 110, {"bob": 1.0, "squash": 0.03}, "Scorpion, claws and head to the right, stinger raised."),
    P("moth", "creature", [(1085, 470, 1536, 612), (1370, 600, 1420, 650)], "right", 60, {"bob": 2.0, "squash": 0.03}, "Furry brown moth-like winged insect, flies."),
    P("earthworm", "creature", [(40, 620, 800, 790)], "right", 180, {"squash": 0.12, "wiggle": 2}, "Earthworm; the open mouth is at the right."),
    P("hornet", "creature", [(1100, 615, 1500, 700), (1150, 700, 1500, 862)], "right", 70, {"bob": 2.5, "squash": 0.02}, "Yellow-black hornet with its pale wings (one item)."),
    # ---- bottom row: the red ants, small to big, in profile
    P("redant_small", "creature", [(0, 800, 265, 990)], "right", 36, {"bob": 1.0, "squash": 0.04}, "Small red ant."),
    P("redant_soldier", "creature", [(265, 780, 650, 990)], "right", 48, {"bob": 1.0, "squash": 0.04}, "Red soldier ant."),
    P("redant_major", "creature", [(650, 700, 1215, 990)], "right", 80, {"bob": 1.5, "squash": 0.03}, "Red major ant with horns."),
]


# ---------------------------------------------------------------------------------------------------------------- metrics

def body_metrics(im):
    """Nose-to-tail span (columns that are at least 14 px tall, so thin antennae and leg tips do not count), the horizontal middle of that span and
    the ground line (bottom of the lowest foot)."""
    a = im.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    px = a.load()
    w, h = a.size
    mincol = max(4, min(14, h // 8))
    cols = [x for x in range(w) if sum(1 for y in range(h) if px[x, y]) >= mincol]
    x0, x1 = (cols[0], cols[-1] + 1) if cols else (0, w)
    ys = [y for y in range(h) if any(px[x, y] for x in range(w))]
    return {"length": x1 - x0, "x0": x0, "x1": x1, "ground_y": (max(ys) + 1) if ys else h}


def ground_point(im, bm):
    """Where the thing touches the ground: the middle of the body span, bottom of the lowest foot.  Feet below the middle of the body (legs
    that reach farther down) are what the game should stand on, so the point's x is the middle of the footprint of the lowest 12% rows if that
    stays inside the body span, else the middle of the span."""
    a = im.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    px = a.load()
    w, h = a.size
    gy = bm["ground_y"]
    lo = max(0, gy - max(3, int(0.12 * h)))
    xs = [x for x in range(w) for y in range(lo, gy) if px[x, y]]
    mid = (bm["x0"] + bm["x1"]) / 2.0
    if xs:
        foot = (min(xs) + max(xs)) / 2.0
        if bm["x0"] <= foot <= bm["x1"]:
            return [round(foot, 1), float(gy)]
    return [round(mid, 1), float(gy)]


# -------------------------------------------------------------------------------------------------------------------- build

def assign_debug(im, a, pieces, groups, names, path):
    """Debug picture: every piece of the sheet coloured by the item it was given to (red = left over and big enough to matter)."""
    import colorsys
    img = Image.new("RGB", im.size, (30, 30, 30))
    img.paste(im.convert("RGB").point(lambda v: v // 3), mask=a.point(lambda v: 255 if v else 0))
    px = img.load()
    for gi, g in enumerate(groups):
        r, gg, b = colorsys.hsv_to_rgb((gi * 0.137) % 1.0, 0.8, 1.0)
        col = (int(r * 255), int(gg * 255), int(b * 255))
        for ci in g:
            for (x, y) in pieces[ci]["pts"]:
                px[x, y] = col
    taken = set(ci for g in groups for ci in g)
    for ci, c in enumerate(pieces):
        if ci not in taken:
            for (x, y) in c["pts"]:
                px[x, y] = (255, 0, 0)
    d = ImageDraw.Draw(img)
    f = ImageFont.load_default()
    for gi, g in enumerate(groups):
        if g:
            cx = sum(pieces[ci]["cx"] for ci in g) / len(g)
            cy = sum(pieces[ci]["cy"] for ci in g) / len(g)
            d.text((cx - 20, cy), names[gi], fill=(255, 255, 255), font=f)
    img.save(path)


def build(contact=None, debug=None, only=None):
    os.makedirs(OUT, exist_ok=True)
    if not only:
        for fn in os.listdir(OUT):
            if fn.endswith(".png"):
                os.remove(os.path.join(OUT, fn))
    im, a = load_sheet()
    sheet_pieces = find_pieces(a)
    claimed = set()
    groups = []
    for sp in CATALOGUE:
        g = pick(sheet_pieces, sp["boxes"], claimed)
        claimed.update(g)
        groups.append(g)
        if not g:
            print("!! nothing found for", sp["name"])
    left = [i for i in range(len(sheet_pieces)) if i not in claimed]
    if left:
        print("!! pieces of the sheet that no item took:", [tuple(sheet_pieces[i]["box"]) for i in left])
    if debug:
        os.makedirs(debug, exist_ok=True)
        assign_debug(im, a, sheet_pieces, groups, [sp["name"] for sp in CATALOGUE], os.path.join(debug, "assign.png"))
    manifest = {
        "_about": "Fauna and food cut from art_src/fauna_sheet.png (RGBA, cut from its alpha) by tools/art/make_fauna.py. Every item is a trimmed transparent PNG, "
                  "long side <= %d px, outlined in thick ink like the rest of the art; the soft edge pixels carry the ink colour (no halo on any background). "
                  "'facing': the way the picture looks (the ants and beetles look RIGHT; 'none' = symmetric or not a creature; flip to turn). "
                  "'ground': suggested ground contact point in the item's own pixels (middle of the body span, bottom of the lowest foot). "
                  "'length_px': nose-to-tail span in the picture (antennae and leg tips excluded; wings included). 'game_len': suggested length in game px at "
                  "scale 1 for a worker ant drawn about %d px long. 'scale' = game_len / length_px: multiply the picture by it. 'anim': how the single "
                  "picture can be moved (bob = px up and down at game size, squash = fraction of height squeezed (stretch the width by the same), "
                  "wiggle = degrees of sway, pulse = grow and shrink). The creatures are single pictures, no separate legs (the rig is in fauna_rig/)."
                  % (MAXSIDE, WORKER_PX),
        "worker_ref_px": WORKER_PX, "items": {}}
    if only and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest["items"] = json.load(f).get("items", {})
    items = {}
    for i, sp in enumerate(CATALOGUE):
        if only and sp["name"] not in only:
            continue
        if not groups[i]:
            continue
        img, pos = item_image(im, a, sheet_pieces, groups[i], sp)
        img = trim(img)
        img, k = shrink(img)
        fn = sp["name"] + ".png"
        img.save(os.path.join(OUT, fn), optimize=True)
        bm = body_metrics(img)
        ground = ground_point(img, bm)
        ent = {"file": "fauna/" + fn, "w": img.size[0], "h": img.size[1], "kind": sp["kind"], "facing": sp["facing"],
               "ground": ground, "length_px": bm["length"], "game_len": float(sp["len"]),
               "scale": round(sp["len"] / float(bm["length"]), 4), "anim": sp["anim"], "single_picture": True,
               "note": sp["note"], "sheet_scale": round(k, 4)}
        manifest["items"][sp["name"]] = ent
        items[sp["name"]] = (img, ent)
        print("%-15s %4dx%-4d %s ground %s span %d" % (sp["name"], img.size[0], img.size[1], "(x%.2f)" % k if k < 1 else "        ", ground, bm["length"]))
    order = {sp["name"]: i for i, sp in enumerate(CATALOGUE)}
    manifest["items"] = dict(sorted(manifest["items"].items(), key=lambda kv: order.get(kv[0], 0)))
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT))
    print("%d items, %.2f MB in %s" % (len(items), total / 1048576.0, OUT))
    if contact:
        make_contact(items, contact)
    return items


# ----------------------------------------------------------------------------------------------------------------- contact

def _checker(size, a=(150, 150, 150), b=(120, 120, 120), cell=12):
    im = Image.new("RGB", size, a)
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=b)
    return im


def make_contact(pieces, path, cols=2, half=340):
    """Every item twice (mid-grey checker and dark brown) with its name, size and ground point, to check the cuts by eye."""
    f = ImageFont.load_default()
    names = list(pieces)
    rows = (len(names) + cols - 1) // cols
    heights = []
    for r in range(rows):
        hh = max(pieces[n][0].size[1] for n in names[r * cols:(r + 1) * cols])
        heights.append(min(hh, 330) + 26)
    cw = half * 2
    W = cols * cw
    H = sum(heights) + 8
    sheet = Image.new("RGB", (W, H), (40, 40, 40))
    y = 4
    for r in range(rows):
        for c in range(cols):
            i = r * cols + c
            if i >= len(names):
                break
            n = names[i]
            im, ent = pieces[n]
            x0 = c * cw
            for j, bgc in enumerate(("check", (66, 44, 30))):
                cell_im = _checker((half - 2, heights[r] - 4)) if bgc == "check" else Image.new("RGB", (half - 2, heights[r] - 4), bgc)
                w, h = im.size
                sc = min(1.0, (half - 8) / float(w), (heights[r] - 30) / float(h))
                pim = im if sc >= 1.0 else im.resize((max(1, int(w * sc)), max(1, int(h * sc))), Image.LANCZOS)
                ox = (half - 2 - pim.size[0]) // 2
                cell_rgba = cell_im.convert("RGBA")
                cell_rgba.alpha_composite(pim, (ox, 18))
                d = ImageDraw.Draw(cell_rgba)
                gx, gy = ent["ground"]
                cx, cy = ox + gx * sc, 18 + gy * sc
                d.ellipse((cx - 3, cy - 3, cx + 3, cy + 3), outline=(255, 0, 0, 255), fill=(255, 255, 0, 255))
                sheet.paste(cell_rgba.convert("RGB"), (x0 + j * half, y))
            d = ImageDraw.Draw(sheet)
            d.text((x0 + 4, y + 3), "%s %dx%d  facing %s  game %d px" % (n, im.size[0], im.size[1], ent["facing"], ent["game_len"]), fill=(255, 255, 255), font=f)
        y += heights[r]
    sheet.save(path)
    print("contact sheet:", path, sheet.size)


def main(argv):
    contact = None
    debug = None
    only = None
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--contact":
            contact = args.pop(0)
        elif a == "--debug":
            debug = args.pop(0)
        elif a == "--only":
            only = set(args.pop(0).split(","))
    build(contact, debug, only)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
