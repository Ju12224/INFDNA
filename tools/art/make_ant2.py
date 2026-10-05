"""Cuts the owner's second ant set (art_src/ant_parts_v2.png: a brown side-view ant, three columns = three walk poses, each with the
whole ant on top and its parts below: head, two antennae, two jaws, thorax, abdomen and nine legs in three rows of three) into one transparent
picture per piece under game/art/antkit2/, and writes game/art/antkit2/antkit2_manifest.json. All pieces face right.
Pieces are found as blobs of the picture's own alpha; pieces that touch are split where the picture is thinnest."""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
SRC = os.path.join(ROOT, "art_src", "ant_parts_v2.png")
OUT = os.path.join(ROOT, "game", "art", "antkit2")
os.makedirs(OUT, exist_ok=True)
for f in os.listdir(OUT):
    if f.endswith(".png"):
        os.remove(os.path.join(OUT, f))
im = Image.open(SRC).convert("RGBA")
A = np.asarray(im)
al = A[:, :, 3] > 20
lab, n = ndimage.label(ndimage.binary_dilation(al, iterations=3))
COLS = [(0, 440), (440, 880), (880, 1254)]


def blob_masks():
    out = []
    for i, s in enumerate(ndimage.find_objects(lab)):
        m = np.zeros(al.shape, bool)
        m[s] = (lab[s] == i + 1) & al[s]
        if m.sum() > 600:
            out.append(m)
    return out


def bbox(m):
    ys, xs = np.where(m)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def split(m, axis, parts):
    """Cut a mask into `parts` pieces along axis (0 = rows, 1 = columns) at the thinnest places."""
    x0, y0, x1, y1 = bbox(m)
    prof = m[y0:y1, x0:x1].sum(1 - axis)
    n = len(prof)
    cuts = [0]
    for k in range(1, parts):
        c = int(n * k / parts)
        lo, hi = max(1, c - n // 6), min(n - 1, c + n // 6)
        cuts.append(lo + int(np.argmin(prof[lo:hi])))
    cuts.append(n)
    out = []
    for a, b in zip(cuts[:-1], cuts[1:]):
        mm = np.zeros_like(m)
        if axis == 0:
            mm[y0 + a:y0 + b, x0:x1] = m[y0 + a:y0 + b, x0:x1]
        else:
            mm[y0:y1, x0 + a:x0 + b] = m[y0:y1, x0 + a:x0 + b]
        out.append(mm)
    return out


def save(name, m, extra):
    x0, y0, x1, y1 = bbox(m)
    sub = A[y0:y1, x0:x1].copy()
    keep = ndimage.binary_dilation(m[y0:y1, x0:x1], iterations=2)
    sub[~keep, 3] = 0
    out = Image.fromarray(sub, "RGBA")
    out.save(os.path.join(OUT, name + ".png"))
    d = {"name": name, "file": "antkit2/%s.png" % name, "w": out.width, "h": out.height}
    d.update(extra)
    return d


masks = blob_masks()
pieces = []
for ci, (cx0, cx1) in enumerate(COLS):
    pose = "abc"[ci]
    mine = [m for m in masks if cx0 <= (bbox(m)[0] + bbox(m)[2]) / 2 < cx1]
    ant = [m for m in mine if (bbox(m)[1] + bbox(m)[3]) / 2 < 300]
    head_zone = sorted([m for m in mine if 330 < (bbox(m)[1] + bbox(m)[3]) / 2 < 470 and bbox(m)[3] < 540], key=lambda m: -m.sum())
    jaws = sorted([m for m in mine if 470 <= (bbox(m)[1] + bbox(m)[3]) / 2 < 545 and m.sum() < 3000], key=lambda m: bbox(m)[0])
    thorax = [m for m in mine if 545 <= (bbox(m)[1] + bbox(m)[3]) / 2 < 640 and m.sum() > 6000]
    abdomen = [m for m in mine if 640 <= (bbox(m)[1] + bbox(m)[3]) / 2 < 770 and m.sum() > 6000]
    legs = [m for m in mine if (bbox(m)[1] + bbox(m)[3]) / 2 >= 770]
    assert len(ant) == 1 and len(thorax) == 1 and len(abdomen) == 1 and head_zone, (pose, len(ant), len(thorax), len(abdomen), len(head_zone))
    pieces.append(save("ant2_full_" + pose, ant[0], {"kind": "full", "pose": pose}))
    pieces.append(save("ant2_head_" + pose, head_zone[0], {"kind": "head", "pose": pose}))
    for k, m in enumerate(sorted(head_zone[1:], key=lambda m: bbox(m)[0])[:2]):
        pieces.append(save("ant2_antenna%d_%s" % (k, pose), m, {"kind": "antenna", "pose": pose}))
    for k, m in enumerate(jaws[:2]):
        pieces.append(save("ant2_jaw%d_%s" % (k, pose), m, {"kind": "jaw", "pose": pose}))
    pieces.append(save("ant2_thorax_" + pose, thorax[0], {"kind": "thorax", "pose": pose}))
    pieces.append(save("ant2_abdomen_" + pose, abdomen[0], {"kind": "abdomen", "pose": pose}))
    # legs: split anything that is two or three legs stuck together, then sort into three rows of three
    flat = []
    for m in legs:
        x0, y0, x1, y1 = bbox(m)
        if y1 - y0 > 215:
            flat += split(m, 0, 2)
        elif x1 - x0 > 200:
            flat += split(m, 1, 2)
        else:
            flat.append(m)
    flat.sort(key=lambda m: (bbox(m)[1] + bbox(m)[3]) / 2)
    assert len(flat) == 9, (pose, len(flat))
    for row in range(3):
        rr = sorted(flat[row * 3:row * 3 + 3], key=lambda m: bbox(m)[0])
        for k, m in enumerate(rr):
            pieces.append(save("ant2_leg%d%d_%s" % (row, k, pose), m, {"kind": "leg", "pose": pose, "row": row, "slot": k}))
json.dump({"_about": "The owner's second, brown ant set (tools/art/make_ant2.py). Faces right. pose a, b, c = the three walk poses (columns of the sheet); "
           "leg rows 0-2 and slots 0-2 follow the sheet (left to right = hind, middle, front).", "pieces": pieces},
          open(os.path.join(OUT, "antkit2_manifest.json"), "w"), indent=1)
print("cut", len(pieces))
