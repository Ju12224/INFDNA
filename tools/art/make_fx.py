#!/usr/bin/env python3
"""Cut the owner's six 4-frame EFFECT sheets (art_src/fx_<name>.png) into one transparent PNG per frame for the game.

Every sheet is a 2000x667 RGBA picture with real transparency: four frames of one effect, left to right, each with a thick ink outline, soft
antialiased edges and a haze of nearly invisible alpha 1-9 dust round it.  The alpha channel is the cut:
  1. clean the alpha: below ALPHA_DUST (10) is dust and becomes 0, ALPHA_OPAQUE (250) and above is opaque (the files never reach 255),
  2. split the sheet into its connected pieces (8-neighbour) and group them into the 4 frames: the pieces are joined by single linkage
     (closest pixel gap first, i.e. the minimum spanning tree of the gaps between pieces) and the tree is cut at its widest gaps until four
     groups that each hold a real share of the picture remain; specks that end up alone go to the nearest frame.  So each frame keeps its
     flying bits (drops, sparks, shards, clods) and nothing of its neighbours.  The four groups, left to right, are frames 0..3,
  3. each frame is cut out (pixels of its own pieces only), trimmed, and shrunk with ONE factor per sheet so the sheet's widest frame is
     about TARGET_W px wide (the frames keep their sizes relative to each other: the growth is part of the animation); premultiplied
     LANCZOS; fully clear pixels get the colour of the nearest visible pixel (a filtered texture never blends a black fringe in);
     saved as content/art/fx/<name>_<0..3>.png,
  4. lightning frames are turned so the bolt runs along +x (one angle for the whole sheet: the mean main axis of the three bolt frames), so
     the game only has to rotate and stretch them from one point to another.
fx_manifest.json lists every frame with its file, size and anchor ("center": the centre of the effect; for acid and dust the bottom centre,
where it touches the ground), plus for lightning the bolt's axis (left and right end).

Needs Pillow, numpy and scipy (like tree_art.py):  python3 tools/art/make_fx.py [--contact PATH] [--debug DIR] [--only web,hit]
  --contact PATH   write a verification contact sheet (every frame on dark brown and on grey checker, anchor marked, with its label)
  --debug DIR      write fxcut_<name>.png per sheet (which piece went to which frame)
Does not import or touch make_art.py or any other manifest.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi
from scipy.spatial import cKDTree

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC_DIR = os.path.join(ROOT, "art_src")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "fx")
MANIFEST = os.path.join(ART, "fx_manifest.json")
ALPHA_DUST = 10        # alpha below this is dust
ALPHA_OPAQUE = 250     # alpha at or above this is opaque (the solid pixels are 250-254)
MIN_SOLID = 6          # a piece with fewer than this many pixels of alpha >= 128 is dust
MIN_SHARE = 0.02       # a frame holds at least this share of the sheet's solid pixels (smaller groups are flying bits)
PAD = 2                # transparent border kept round every frame
TARGET_W = 200         # the widest frame of a sheet is shrunk to about this many px

# name -> anchor ("center" or "ground": bottom centre), target width, what it is, which game effect uses it, and hand-placed anchors in
# SHEET px for frames whose centre is not where the picture's bulk is (the silk ball and the splat: the web's hub is the knot on the right).
SHEETS = {
    "web": {"anchor": "center", "w": TARGET_W, "frames": "silk ball, splat, full web, dripping web",
            "use": "kind 'web' (the spider snare): drawn over the snared raider",
            "fix": {0: (322, 333), 1: (826, 362)}},
    "sonic": {"anchor": "center", "w": 240, "frames": "shock burst, ring, double ring, ring breaking up",
              "use": "kind 'wave' (sonic pulse): grows to the pulse radius"},
    "lightning": {"anchor": "center", "w": TARGET_W, "frames": "small arc, long arc, big burst, fading arc", "align": True,
                  "use": "kind 'arc': rotated and stretched from pos to 'to' along the axis"},
    "acid": {"anchor": "ground", "w": TARGET_W, "frames": "blob, splash, big splash, puddle",
             "use": "none yet (the sim has no acid/venom effect kind); ready for an acid hit"},
    "dust": {"anchor": "ground", "w": TARGET_W, "frames": "small puff, big puff, biggest puff, scattered clods",
             "use": "kind 'puff' (dust kicked up), drawn under the units"},
    "hit": {"anchor": "center", "w": TARGET_W, "frames": "star, big burst, shards, fading sparks",
            "use": "kinds 'spark' (small) and 'burst' (bigger), drawn under the units"},
}
ORDER = ["web", "sonic", "lightning", "acid", "dust", "hit"]


# ---------------------------------------------------------------------------------------------------------------- the sheet

def load_sheet(name):
    """RGBA array (H, W, 4) uint8 with the alpha cleaned: dust gone, solid pixels fully opaque."""
    a = np.array(Image.open(os.path.join(SRC_DIR, "fx_%s.png" % name)).convert("RGBA"))
    al = a[:, :, 3]
    al[al < ALPHA_DUST] = 0
    al[al >= ALPHA_OPAQUE] = 255
    a[:, :, 3] = al
    return a


def pieces_of(alpha):
    """Connected pieces (8-neighbour) of the visible alpha, without dust: label image and [{id, solid, box, pts (boundary, for gaps)}]."""
    lab, n = ndi.label(alpha > 0, structure=np.ones((3, 3), bool))
    solid = alpha >= 128
    counts = ndi.sum(solid, lab, index=np.arange(1, n + 1))
    boxes = ndi.find_objects(lab)
    inner = ndi.binary_erosion(alpha > 0, structure=np.ones((3, 3), bool))
    out = []
    for i in range(n):
        if counts[i] < MIN_SOLID:
            lab[lab == i + 1] = 0
            continue
        sl = boxes[i]
        m = lab[sl] == i + 1
        edge = m & ~inner[sl]
        ys, xs = np.nonzero(edge)
        pts = np.stack([xs + sl[1].start, ys + sl[0].start], axis=1).astype(np.float32)
        out.append({"id": i + 1, "solid": float(counts[i]), "box": (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop), "pts": pts})
    return lab, out


def box_gap(a, b):
    dx = max(0, max(a[0], b[0]) - min(a[2], b[2]))
    dy = max(0, max(a[1], b[1]) - min(a[3], b[3]))
    return math.hypot(dx, dy)


def gaps(pieces):
    """Pixel gap between every pair of pieces that could be neighbours: [(gap, i, j)]."""
    trees = [cKDTree(p["pts"]) for p in pieces]
    out = []
    for i in range(len(pieces)):
        for j in range(i + 1, len(pieces)):
            if box_gap(pieces[i]["box"], pieces[j]["box"]) > 400:
                continue
            small, big = (i, j) if len(pieces[i]["pts"]) < len(pieces[j]["pts"]) else (j, i)
            d, _ = trees[big].query(pieces[small]["pts"], k=1)
            out.append((float(d.min()), i, j))
    return out


class DSU:
    def __init__(self, n):
        self.p = list(range(n))

    def find(self, x):
        while self.p[x] != x:
            self.p[x] = self.p[self.p[x]]
            x = self.p[x]
        return x

    def union(self, a, b):
        a, b = self.find(a), self.find(b)
        if a == b:
            return False
        self.p[b] = a
        return True


def group_frames(pieces, nframes=4):
    """Group the pieces into the frames: cut the minimum spanning tree of the gaps at its widest edges until `nframes` groups with a real share
    of the picture exist; leftover small groups (a lone speck) join the frame they are closest to.  Returns lists of piece indices, left to right."""
    n = len(pieces)
    edges = sorted(gaps(pieces))
    dsu = DSU(n)
    mst = []
    for (d, i, j) in edges:
        if dsu.union(i, j):
            mst.append((d, i, j))
    total = sum(p["solid"] for p in pieces)
    mst_desc = sorted(mst, reverse=True)
    for cut in range(nframes - 1, len(mst_desc) + 1):
        keep = mst_desc[cut:]
        dsu = DSU(n)
        for (d, i, j) in keep:
            dsu.union(i, j)
        groups = {}
        for i in range(n):
            groups.setdefault(dsu.find(i), []).append(i)
        big = [g for g in groups.values() if sum(pieces[i]["solid"] for i in g) >= MIN_SHARE * total]
        if len(big) >= nframes:
            break
    big.sort(key=lambda g: -sum(pieces[i]["solid"] for i in g))
    frames = big[:nframes]
    rest = [i for g in groups.values() if g not in frames for i in g]
    # a leftover piece joins the frame whose pieces come nearest to it
    gmap = {}
    for (d, i, j) in edges:
        gmap.setdefault(i, []).append((d, j))
        gmap.setdefault(j, []).append((d, i))
    owner = {}
    for fi, g in enumerate(frames):
        for i in g:
            owner[i] = fi
    for i in rest:
        best = None
        for (d, j) in sorted(gmap.get(i, [])):
            if j in owner:
                best = owner[j]
                break
        if best is None:          # nothing within reach: the frame whose box centre is closest in x
            cx = (pieces[i]["box"][0] + pieces[i]["box"][2]) / 2.0
            best = min(range(len(frames)), key=lambda fi: min(abs(cx - (pieces[k]["box"][0] + pieces[k]["box"][2]) / 2.0) for k in frames[fi]))
        frames[best].append(i)
    frames.sort(key=lambda g: min(pieces[i]["box"][0] for i in g))
    return frames


# ---------------------------------------------------------------------------------------------------------------- one frame

def frame_mask(lab, pieces, idx):
    ids = [pieces[i]["id"] for i in idx]
    return np.isin(lab, ids)


def main_axis_angle(alpha):
    """Angle (radians, image coords: y down) of the main axis of the solid pixels."""
    ys, xs = np.nonzero(alpha >= 128)
    x = xs - xs.mean()
    y = ys - ys.mean()
    cov = np.cov(np.stack([x, y]))
    w, v = np.linalg.eigh(cov)
    vx, vy = v[:, np.argmax(w)]
    if vx < 0:
        vx, vy = -vx, -vy
    return math.atan2(vy, vx)


def bleed(rgba):
    """Fully clear pixels take the colour of the nearest visible pixel (so bilinear filtering never drags black into the edge)."""
    a = rgba[:, :, 3]
    clear = a == 0
    if not clear.any() or clear.all():
        return rgba
    _, (iy, ix) = ndi.distance_transform_edt(clear, return_indices=True)
    out = rgba.copy()
    out[:, :, :3] = rgba[iy, ix, :3]
    out[:, :, 3] = a
    return out


def anchor_of(alpha, kind, core_box=None):
    """Anchor in the picture's px: 'center' = middle of the effect's body, 'ground' = bottom centre of it.  The body is the largest piece when it
    holds at least half of the frame (a puff's cloud, a splash), else all of the frame (sparks, clods, a broken ring)."""
    vis = alpha >= 128
    lab, n = ndi.label(vis, structure=np.ones((3, 3), bool))
    if n == 0:
        h, w = alpha.shape
        return [w / 2.0, h / 2.0 if kind == "center" else float(h)]
    sizes = ndi.sum(vis, lab, index=np.arange(1, n + 1))
    k = int(np.argmax(sizes))
    body = (lab == k + 1) if sizes[k] >= 0.5 * sizes.sum() else vis
    ys, xs = np.nonzero(body)
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    if kind == "ground":
        return [round((x0 + x1) / 2.0, 1), float(y1)]
    # the middle of the body's box and its centre of mass, averaged (radial effects with lopsided flying bits)
    return [round(((x0 + x1) / 2.0 + xs.mean()) / 2.0, 1), round(((y0 + y1) / 2.0 + ys.mean()) / 2.0, 1)]


def cut_sheet(name, debug_dir=None):
    spec = SHEETS[name]
    sheet = load_sheet(name)
    alpha = sheet[:, :, 3]
    lab, pieces = pieces_of(alpha)
    frames = group_frames(pieces)
    if debug_dir:
        save_debug(sheet, lab, pieces, frames, os.path.join(debug_dir, "fxcut_%s.png" % name))
    # cut out every frame at sheet resolution
    cuts = []
    for fi, idx in enumerate(frames):
        m = frame_mask(lab, pieces, idx)
        ys, xs = np.nonzero(m)
        x0, x1 = max(0, xs.min() - PAD), min(sheet.shape[1], xs.max() + 1 + PAD)
        y0, y1 = max(0, ys.min() - PAD), min(sheet.shape[0], ys.max() + 1 + PAD)
        img = sheet[y0:y1, x0:x1].copy()
        img[:, :, 3] = np.where(m[y0:y1, x0:x1], img[:, :, 3], 0)
        img[img[:, :, 3] == 0, :3] = 0
        fix = spec.get("fix", {}).get(fi)
        cuts.append({"img": Image.fromarray(img, "RGBA"), "origin": (x0, y0), "fix": (fix[0] - x0, fix[1] - y0) if fix else None})
    # lightning: one turn for the whole sheet, so the bolts run along +x
    turn = 0.0
    if spec.get("align"):
        angs = [main_axis_angle(np.array(cuts[i]["img"])[:, :, 3]) for i in (0, 1, 3)]
        turn = sum(angs) / len(angs)
        for c in cuts:
            im = c["img"]
            w, h = im.size
            big = im.rotate(math.degrees(turn), resample=Image.BICUBIC, expand=True)   # PIL turns counter-clockwise for a positive angle (y down: it undoes +turn)
            c["img"] = big
            c["fix"] = None
    # trim, then one shrink factor for the sheet
    for c in cuts:
        bb = c["img"].getchannel("A").point(lambda v: 255 if v >= ALPHA_DUST else 0).getbbox()
        bb = (max(0, bb[0] - PAD), max(0, bb[1] - PAD), min(c["img"].size[0], bb[2] + PAD), min(c["img"].size[1], bb[3] + PAD))
        c["img"] = c["img"].crop(bb)
        if c["fix"]:
            c["fix"] = (c["fix"][0] - bb[0], c["fix"][1] - bb[1])
    k = min(1.0, spec["w"] / float(max(c["img"].size[0] for c in cuts)))
    out = []
    for fi, c in enumerate(cuts):
        w, h = c["img"].size
        nw, nh = max(1, int(round(w * k))), max(1, int(round(h * k)))
        im = c["img"].resize((nw, nh), Image.LANCZOS)        # Pillow resizes RGBA premultiplied
        arr = np.array(im)
        arr[:, :, 3] = np.where(arr[:, :, 3] < 3, 0, arr[:, :, 3])
        arr = bleed(arr)
        im = Image.fromarray(arr, "RGBA")
        if c["fix"]:
            anc = [round(c["fix"][0] * nw / float(w), 1), round(c["fix"][1] * nh / float(h), 1)]
        else:
            anc = anchor_of(arr[:, :, 3], spec["anchor"])
        entry = {"file": "fx/%s_%d.png" % (name, fi), "w": nw, "h": nh, "center": anc}
        if spec.get("align"):
            # the bolt's two ends along x, on the anchor's height: the extent of the bolt itself (its largest piece; loose shards do not count)
            vis = arr[:, :, 3] >= 128
            lab2, n2 = ndi.label(vis, structure=np.ones((3, 3), bool))
            if n2 > 0:
                vis = lab2 == 1 + int(np.argmax(ndi.sum(vis, lab2, index=np.arange(1, n2 + 1))))
            cols = np.nonzero(vis.any(axis=0))[0]
            entry["axis"] = [float(cols.min()), anc[1], float(cols.max() + 1), anc[1]]
        out.append((im, entry))
    return out, k, turn, len(pieces)


# ---------------------------------------------------------------------------------------------------------------- outputs

def save_debug(sheet, lab, pieces, frames, path):
    cols = [(255, 90, 90), (90, 220, 90), (90, 140, 255), (255, 210, 60)]
    img = np.zeros(sheet.shape[:2] + (3,), np.uint8) + 30
    for fi, idx in enumerate(frames):
        m = frame_mask(lab, pieces, idx)
        img[m] = cols[fi % 4]
    Image.fromarray(img, "RGB").save(path)


def checker(w, h, a=(120, 120, 120), b=(150, 150, 150), s=8):
    im = Image.new("RGB", (w, h), a)
    d = ImageDraw.Draw(im)
    for y in range(0, h, s):
        for x in range((y // s) % 2 * s, w, 2 * s):
            d.rectangle([x, y, x + s - 1, y + s - 1], fill=b)
    return im


def contact(results, path):
    cell_w, cell_h, lab_h = 250, 250, 16
    rows = [n for n in ORDER if n in results]
    W = cell_w * 8
    H = (cell_h + lab_h) * len(rows)
    sheet = Image.new("RGB", (W, H), (40, 34, 30))
    d = ImageDraw.Draw(sheet)
    f = ImageFont.load_default()
    for r, name in enumerate(rows):
        y = r * (cell_h + lab_h)
        for fi, (im, e) in enumerate(results[name]["frames"]):
            for half in (0, 1):
                x = (half * 4 + fi) * cell_w
                bg = Image.new("RGB", (cell_w, cell_h), (34, 26, 20)) if half == 0 else checker(cell_w, cell_h)
                ox, oy = (cell_w - im.size[0]) // 2, (cell_h - im.size[1]) // 2
                bg.paste(im, (ox, oy), im)
                bd = ImageDraw.Draw(bg)
                bd.rectangle([ox - 1, oy - 1, ox + im.size[0], oy + im.size[1]], outline=(90, 90, 160))
                cx, cy = ox + e["center"][0], oy + e["center"][1]
                bd.line([cx - 7, cy, cx + 7, cy], fill=(255, 0, 255), width=2)
                bd.line([cx, cy - 7, cx, cy + 7], fill=(255, 0, 255), width=2)
                if "axis" in e:
                    bd.line([ox + e["axis"][0], oy + e["axis"][1], ox + e["axis"][2], oy + e["axis"][3]], fill=(0, 255, 0), width=1)
                sheet.paste(bg, (x, y + lab_h))
                d.text((x + 4, y + 2), "%s_%d  %dx%d" % (name, fi, e["w"], e["h"]), fill=(230, 230, 230), font=f)
    sheet.save(path)


def main(argv):
    contact_path = None
    debug_dir = None
    only = None
    i = 0
    while i < len(argv):
        if argv[i] == "--contact":
            contact_path = argv[i + 1]
            i += 2
        elif argv[i] == "--debug":
            debug_dir = argv[i + 1]
            i += 2
        elif argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 2
        else:
            print("unknown argument", argv[i])
            return 1
    os.makedirs(OUT, exist_ok=True)
    if debug_dir:
        os.makedirs(debug_dir, exist_ok=True)
    man = {"_about": "Effect animations cut from art_src/fx_<name>.png (RGBA, cut from its alpha) by tools/art/make_fx.py. Every effect has 4 frames, "
           "played in order over the effect's life (cross-fade between neighbours). The frames of one effect share ONE scale (they keep their "
           "sizes relative to each other), so draw them all with the same factor: 'ref_w' is the widest frame's width. 'center' is the anchor "
           "in the frame's own px: the centre of the effect, or for anchor 'ground' (acid, dust) the bottom centre where it touches the ground. "
           "Lightning frames are turned so the bolt runs along +x; 'axis' = [x0, y, x1, y] are its two ends (stretch x0..x1 from pos to 'to'). "
           "Thick ink outlines like the rest of the art; clear pixels carry the nearest visible colour (no fringe when filtered).",
           "frames": 4, "anims": {}}
    if os.path.exists(MANIFEST):
        try:
            with open(MANIFEST) as fh:
                old = json.load(fh)
            if only:
                man["anims"] = {k: v for k, v in old.get("anims", {}).items() if k not in only}
        except (OSError, ValueError):
            pass
    results = {}
    for name in ORDER:
        if only and name not in only:
            continue
        frames, k, turn, npieces = cut_sheet(name, debug_dir)
        for im, e in frames:
            im.save(os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", e["file"]), optimize=True)
        spec = SHEETS[name]
        man["anims"][name] = {"anchor": spec["anchor"], "frames_are": spec["frames"], "use": spec["use"], "sheet_scale": round(k, 4),
                              "ref_w": max(e["w"] for _, e in frames), "frames": [e for _, e in frames]}
        if spec.get("align"):
            man["anims"][name]["turned_deg"] = round(-math.degrees(turn), 1)
        results[name] = {"frames": frames}
        print("%-10s pieces %3d  scale %.3f  frames %s" % (name, npieces, k, ", ".join("%dx%d" % (e["w"], e["h"]) for _, e in frames)))
    man["anims"] = {k: man["anims"][k] for k in ORDER if k in man["anims"]}
    with open(MANIFEST, "w") as fh:
        json.dump(man, fh, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("fx/ folder: %d files, %.0f KB" % (len(os.listdir(OUT)), total / 1024.0))
    if contact_path:
        contact(results, contact_path)
        print("contact sheet:", contact_path)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
