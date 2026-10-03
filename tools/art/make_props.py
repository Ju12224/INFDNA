#!/usr/bin/env python3
"""Cut the owner's NEST PROPS sheet (art_src/nest_props.png) into one transparent PNG per item for the nest decor.

The sheet is an RGBA picture with real transparency: 69 items in 7 rows (wood, building bits, iron, chains and gears, tools, armoury, rope),
every item one connected island of the alpha with a thick near-black ink outline, soft antialiased edges and a haze of nearly invisible
alpha 1-9 dust round it.  So there is no matte to build: the alpha channel is the cut.
  1. clean the alpha: below ALPHA_DUST (10) is dust and becomes 0, ALPHA_OPAQUE (250) and above is opaque (the file's solid pixels are
     250-254); the colour of the antialiased edge pixels is repainted flat ink, so no dark or coloured fringe shows on any background,
  2. split the sheet into islands (8-neighbour pieces of the cleaned alpha) and give every island to the catalogue item whose sheet
     position (row band, x centre) is nearest,
  3. each item is trimmed to its alpha bounding box (2 px clear margin), shrunk to at most MAXSIDE px on the long side (Pillow premultiplies
     RGBA when resizing: no dark fringe) and saved in content/art/props/<name>.png (optimize=True).
content/art/props_manifest.json lists every item with its file, size, base point (bottom centre where it rests, in the item's own pixels),
top point (where it hangs from, for the few things that can hang), category (wood / iron / tool / structure / armory / rope) and a
suggested game size (long side in px at scale 1, for a worker ant drawn about 40 px long; a barrel stands about 30 px tall).

Needs Pillow only:  python3 tools/art/make_props.py [--contact PATH]
  --contact PATH   write a verification contact sheet (every item on dark brown and on grey, labelled, base point marked)
Does not import or touch make_art.py / make_antkit.py / make_fauna.py or their manifests.
"""
import json
import os
import sys
from collections import deque

from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "nest_props.png")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "props")
MANIFEST = os.path.join(ART, "props_manifest.json")
INK = (21, 18, 26)          # the house outline colour (same as the other art scripts)
MAXSIDE = 160               # longest side of any saved item
PAD = 2                     # transparent border kept round every item
ALPHA_DUST = 10             # alpha below this is dust
ALPHA_OPAQUE = 250          # alpha at or above this counts as opaque
MIN_PIECE = 30              # an island with fewer solid pixels than this is dust
MAX_BYTES = int(2.5 * 1024 * 1024)
WORKER_PX = 40.0

# rows of the sheet: (top, bottom) in sheet px
ROWS = [(0, 165), (165, 335), (335, 480), (480, 635), (635, 788), (788, 928), (928, 1086)]

# name, row, x centre on the sheet, category, suggested game size (long side, px), hangs (can hang from a ceiling), note
CATALOGUE = [
    # ---- row 1: wood
    ("palisade", 0, 94, "structure", 46, False, "Wall of five sharpened stakes lashed with rope."),
    ("fence", 0, 259, "structure", 40, False, "Low rail fence: two posts and rope rails."),
    ("post", 0, 383, "wood", 30, False, "Short wooden post with a rope lashing."),
    ("stake", 0, 482, "wood", 32, False, "Single sharpened stake standing upright."),
    ("plank", 0, 604, "wood", 32, False, "One plank lying on its side."),
    ("planks", 0, 733, "wood", 34, False, "Two planks crossed on the floor."),
    ("log", 0, 888, "wood", 38, False, "Cut log lying down, ring end showing."),
    ("branch", 0, 1060, "wood", 38, False, "Forked branch lying on the floor."),
    ("firewood", 0, 1222, "wood", 36, False, "Bundle of sticks tied with rope."),
    ("stump", 0, 1380, "wood", 30, False, "Tree stump with roots."),
    # ---- row 2: building bits
    ("ladder", 1, 71, "structure", 46, False, "Wooden ladder with rope lashings, standing upright."),
    ("crate", 1, 226, "wood", 30, False, "Wooden crate."),
    ("barrel", 1, 376, "wood", 30, False, "Wooden barrel with iron hoops."),
    ("cable_spool", 1, 515, "wood", 30, False, "Wooden cable spool."),
    ("cart", 1, 670, "structure", 42, False, "Small wooden hand cart."),
    ("rope_bridge", 1, 872, "structure", 50, False, "Plank walkway with rope rails."),
    ("ramp", 1, 1058, "structure", 40, False, "Plank ramp."),
    ("scaffold", 1, 1230, "structure", 40, False, "Low plank scaffold / platform."),
    ("signpost", 1, 1384, "structure", 38, False, "Signpost with two arrow boards."),
    # ---- row 3: iron
    ("iron_bar", 2, 83, "iron", 34, False, "Ribbed iron bar lying diagonally."),
    ("pipe", 2, 226, "iron", 34, False, "Straight iron pipe."),
    ("girder", 2, 375, "iron", 38, False, "Short I-beam girder."),
    ("elbow_pipe", 2, 532, "iron", 24, False, "Elbow pipe fitting."),
    ("nail", 2, 659, "iron", 20, False, "Big iron nail."),
    ("screw", 2, 779, "iron", 20, False, "Wood screw."),
    ("bolt", 2, 924, "iron", 22, False, "Hex bolt."),
    ("nut", 2, 1076, "iron", 14, False, "Hex nut."),
    ("washer", 2, 1224, "iron", 14, False, "Washer."),
    ("hinge", 2, 1376, "iron", 20, False, "Door hinge."),
    # ---- row 4: hardware
    ("hook", 3, 58, "iron", 24, True, "Iron hook with an eye (hangs)."),
    ("chain_short", 3, 186, "iron", 22, False, "Three chain links."),
    ("chain", 3, 317, "iron", 36, False, "Length of chain."),
    ("pulley", 3, 470, "iron", 26, True, "Pulley wheel in an iron yoke (hangs)."),
    ("gear", 3, 614, "iron", 24, False, "Cog wheel."),
    ("spring", 3, 744, "iron", 18, False, "Coil spring."),
    ("wire_coil", 3, 877, "iron", 28, False, "Coil of wire tied with twine."),
    ("mesh_grid", 3, 1044, "iron", 30, False, "Square wire mesh."),
    ("grate", 3, 1216, "iron", 28, False, "Slotted iron grate."),
    ("rusty_plate", 3, 1367, "iron", 26, False, "Bent rusty metal plate."),
    # ---- row 5: tools
    ("bucket", 4, 64, "tool", 24, False, "Iron bucket with a handle."),
    ("clamp", 4, 189, "tool", 22, False, "C-clamp."),
    ("pliers", 4, 341, "tool", 28, False, "Pliers."),
    ("crowbar", 4, 458, "tool", 30, False, "Crowbar."),
    ("anvil", 4, 600, "tool", 28, False, "Anvil."),
    ("pickaxe_head", 4, 756, "tool", 26, False, "Pickaxe head without a handle."),
    ("trowel", 4, 886, "tool", 24, False, "Trowel."),
    ("saw_blade", 4, 1013, "tool", 30, False, "Hand saw blade."),
    ("circular_saw", 4, 1190, "tool", 28, False, "Circular saw blade."),
    ("shield", 4, 1364, "armory", 28, False, "Shield / armour plate of wood and iron."),
    # ---- row 6: armoury and brackets
    ("cage", 5, 78, "armory", 34, False, "Iron-barred cage."),
    ("gate", 5, 232, "structure", 38, False, "Barred gate between two sharpened posts."),
    ("helmet", 5, 381, "armory", 20, False, "Plain iron helmet with leather straps."),
    ("helmet_riveted", 5, 524, "armory", 20, False, "Riveted iron helmet with leather straps."),
    ("shackle", 5, 658, "armory", 20, False, "Iron shackle."),
    ("bracket_u", 5, 800, "iron", 22, False, "U-shaped iron bracket."),
    ("bracket_l", 5, 932, "iron", 18, False, "L-shaped iron bracket."),
    ("gusset", 5, 1050, "iron", 20, False, "Triangular iron gusset plate with holes."),
    ("truss", 5, 1208, "structure", 40, False, "Triangular iron truss."),
    ("plate", 5, 1378, "iron", 22, False, "Flat riveted iron plate."),
    # ---- row 7: rope and defences
    ("rope_spool", 6, 80, "rope", 28, False, "Wooden spool wound with rope."),
    ("rope_coil", 6, 220, "rope", 28, False, "Coil of rope."),
    ("block_hook", 6, 337, "rope", 26, True, "Pulley block with a hook (hangs)."),
    ("net", 6, 464, "rope", 30, True, "Rope net hung between two pegs."),
    ("frame", 6, 604, "structure", 32, False, "Lashed square wooden frame."),
    ("spike_barricade", 6, 752, "structure", 40, False, "Row of sharpened stakes (barricade)."),
    ("corrugated", 6, 905, "iron", 36, False, "Corrugated iron sheet."),
    ("fence_net", 6, 1077, "rope", 40, False, "Net fence stretched between two posts."),
    ("lantern_cage", 6, 1226, "structure", 22, True, "Iron lantern cage with a ring on top (hangs)."),
    ("x_stakes", 6, 1364, "structure", 34, False, "Crossed sharpened stakes (anti-raider)."),
]


# ---------------------------------------------------------------------------------------------------------------- helpers

def label_pixels(mask):
    """Connected pieces (8-neighbour) of a mask: [{area, cx, cy, box, pts}]."""
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
                comps.append({"area": len(pts), "box": (min(xs), min(ys), max(xs) + 1, max(ys) + 1), "pts": pts,
                              "cx": (min(xs) + max(xs) + 1) / 2.0, "cy": (min(ys) + max(ys) + 1) / 2.0})
    return comps


def load_sheet():
    im = Image.open(SRC)
    if im.mode != "RGBA":
        raise SystemExit("nest_props.png must be RGBA with real transparency (it is %s)" % im.mode)
    a = im.getchannel("A").point(lambda v: 0 if v < ALPHA_DUST else (255 if v >= ALPHA_OPAQUE else v))
    return im, a


def find_pieces(a):
    solid = a.point(lambda v: 255 if v >= 128 else 0).load()
    out = []
    for c in label_pixels(a.point(lambda v: 255 if v > 0 else 0)):
        c["solid"] = sum(1 for (x, y) in c["pts"] if solid[x, y])
        if c["solid"] >= MIN_PIECE:
            out.append(c)
    return out


def assign(pieces):
    """Every island goes to the catalogue item of its row whose x centre is nearest."""
    groups = [[] for _ in CATALOGUE]
    for pi, c in enumerate(pieces):
        row = None
        for ri, (y0, y1) in enumerate(ROWS):
            if y0 <= c["cy"] < y1:
                row = ri
        if row is None:
            print("!! island outside every row:", c["box"])
            continue
        best, bd = None, 1e9
        for i, it in enumerate(CATALOGUE):
            if it[1] == row and abs(it[2] - c["cx"]) < bd:
                best, bd = i, abs(it[2] - c["cx"])
        if best is None or bd > 60:
            print("!! island with no item near it:", c["box"])
            continue
        groups[best].append(pi)
    return groups


def item_image(im, a, pieces, idx):
    """RGBA crop of one item: its islands only, alpha as cleaned, the soft edge repainted ink."""
    m = Image.new("L", im.size, 0)
    mp = m.load()
    for i in idx:
        for (x, y) in pieces[i]["pts"]:
            mp[x, y] = 255
    bb = m.getbbox()
    box = (max(0, bb[0] - PAD), max(0, bb[1] - PAD), min(im.size[0], bb[2] + PAD), min(im.size[1], bb[3] + PAD))
    alpha = ImageChops.multiply(a.crop(box), m.crop(box))
    rgb = im.crop(box).convert("RGB")
    edge = alpha.point(lambda v: 255 if v < 255 else 0)
    rgb = Image.composite(Image.new("RGB", rgb.size, INK), rgb, edge)
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def shrink(im, maxside=MAXSIDE):
    w, h = im.size
    k = min(1.0, maxside / float(max(w, h)))
    if k >= 1.0:
        return im, 1.0
    return im.resize((max(1, int(round(w * k))), max(1, int(round(h * k)))), Image.LANCZOS), k


def base_point(im):
    """Bottom centre where the thing rests: the middle of the footprint of its lowest rows (the bottom 10%), at the bottom of the lowest
    solid pixel.  Things with legs (a stump's roots, a cart's wheels, a gate's posts) rest on the span between their outer feet."""
    a = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    px = a.load()
    w, h = a.size
    ys = [y for y in range(h) if any(px[x, y] for x in range(w))]
    gy = (max(ys) + 1) if ys else h
    lo = max(0, gy - max(3, int(0.10 * h)))
    xs = [x for x in range(w) for y in range(lo, gy) if px[x, y]]
    bx = (min(xs) + max(xs) + 1) / 2.0 if xs else w / 2.0
    return [round(bx, 1), float(gy)]


def top_point(im):
    """Where a hanging thing hangs from: the middle of its topmost rows (the top 12%: a ring, or the two pegs of the net), at the top."""
    a = im.getchannel("A").point(lambda v: 255 if v >= 128 else 0)
    px = a.load()
    w, h = a.size
    ys = [y for y in range(h) if any(px[x, y] for x in range(w))]
    ty = min(ys) if ys else 0
    xs = [x for x in range(w) for y in range(ty, min(h, ty + max(4, int(0.12 * h)))) if px[x, y]]
    tx = (min(xs) + max(xs) + 1) / 2.0 if xs else w / 2.0
    return [round(tx, 1), float(ty)]


# -------------------------------------------------------------------------------------------------------------------- build

def build(contact=None):
    os.makedirs(OUT, exist_ok=True)
    for fn in os.listdir(OUT):
        if fn.endswith(".png"):
            os.remove(os.path.join(OUT, fn))
    im, a = load_sheet()
    pieces = find_pieces(a)
    groups = assign(pieces)
    taken = set(i for g in groups for i in g)
    left = [pieces[i]["box"] for i in range(len(pieces)) if i not in taken]
    if left:
        print("!! islands no item took:", left)
    manifest = {
        "_about": "Nest props cut from art_src/nest_props.png (RGBA, cut from its alpha) by tools/art/make_props.py. Every item is a trimmed transparent "
                  "PNG, long side <= %d px, outlined in thick ink; the soft edge pixels carry the ink colour (no halo on any background). "
                  "'base': where the item rests on a floor, in its own pixels (bottom centre of its footprint). 'top': where it hangs from (only "
                  "meaningful when 'hangs' is true). 'category': wood / iron / tool / structure / armory / rope. 'game_size': suggested long side in "
                  "game px at scale 1 next to a worker ant drawn about %d px long (a barrel stands about 30 px tall); scale = game_size / max(w, h)."
                  % (MAXSIDE, WORKER_PX),
        "worker_ref_px": WORKER_PX, "items": {}}
    items = {}
    for i, (name, row, x, cat, size, hangs, note) in enumerate(CATALOGUE):
        if len(groups[i]) != 1:
            print("!! %s got %d islands" % (name, len(groups[i])))
        if not groups[i]:
            continue
        img = item_image(im, a, pieces, groups[i])
        img, k = shrink(img)
        fn = name + ".png"
        img.save(os.path.join(OUT, fn), optimize=True)
        ent = {"file": "props/" + fn, "w": img.size[0], "h": img.size[1], "base": base_point(img), "top": top_point(img),
               "category": cat, "game_size": float(size), "hangs": hangs, "note": note, "sheet_scale": round(k, 4)}
        manifest["items"][name] = ent
        items[name] = (img, ent)
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT))
    print("%d items, %.2f MB in %s" % (len(items), total / 1048576.0, OUT))
    if total > MAX_BYTES:
        print("!! props folder is over %.1f MB" % (MAX_BYTES / 1048576.0))
    if contact:
        make_contact(items, contact)
    return items


# ----------------------------------------------------------------------------------------------------------------- contact

def make_contact(items, path, cols=6, cell=200):
    """Every item twice (dark brown nest dirt above, mid grey below) with its name, category and base point, plus a row at game size."""
    f = ImageFont.load_default()
    names = list(items)
    rows = (len(names) + cols - 1) // cols
    ch = cell * 2 + 70
    W = cols * cell
    H = rows * ch
    sheet = Image.new("RGB", (W, H), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        im, ent = items[n]
        x0 = (i % cols) * cell
        y0 = (i // cols) * ch
        for j, bg in enumerate(((66, 44, 30), (128, 128, 128))):
            tile = Image.new("RGBA", (cell - 4, cell - 4), bg + (255,))
            w, h = im.size
            ox = (cell - 4 - w) // 2
            oy = (cell - 4 - h) // 2 + 6
            tile.alpha_composite(im, (ox, oy))
            td = ImageDraw.Draw(tile)
            bx, by = ent["base"]
            td.line((ox + bx - 8, oy + by, ox + bx + 8, oy + by), fill=(255, 40, 40, 255), width=1)
            td.ellipse((ox + bx - 2, oy + by - 2, ox + bx + 2, oy + by + 2), fill=(255, 230, 0, 255))
            if ent["hangs"]:
                tx, ty = ent["top"]
                td.ellipse((ox + tx - 2, oy + ty - 2, ox + tx + 2, oy + ty + 2), fill=(0, 220, 255, 255))
            sheet.paste(tile.convert("RGB"), (x0 + 2, y0 + 2 + j * cell))
        # the item at game size beside a 40 px ant-length bar, on nest brown
        gs = ent["game_size"] / float(max(im.size))
        small = im.resize((max(1, int(im.size[0] * gs * 1.5)), max(1, int(im.size[1] * gs * 1.5))), Image.LANCZOS)
        strip = Image.new("RGBA", (cell - 4, 66), (52, 36, 26, 255))
        sd = ImageDraw.Draw(strip)
        sd.rectangle((6, 58, 6 + int(40 * 1.5), 61), fill=(230, 120, 60, 255))
        strip.alpha_composite(small, (max(0, 80), max(0, 62 - small.size[1])))
        sheet.paste(strip.convert("RGB"), (x0 + 2, y0 + 2 + 2 * cell))
        d.text((x0 + 6, y0 + 5), n, fill=(255, 255, 255), font=f)
        d.text((x0 + 6, y0 + 17), "%s %dx%d" % (ent["category"], im.size[0], im.size[1]), fill=(220, 220, 160), font=f)
    sheet.save(path)
    print("contact sheet:", path, sheet.size)


def main(argv):
    contact = None
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--contact":
            contact = args.pop(0)
    build(contact)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
