"""Cuts the owner's aphid mount sheets (art_src/aphids.png = leg pose A, art_src/aphids_b.png = leg pose B, four aphids each, transparent
background) into one picture per aphid under game/art/aphid/, and writes game/art/aphid/aphid_manifest.json.
Layout of each sheet: top-left plain saddle, top-right packed saddle, bottom-left bone armor, bottom-right royal (pink)."""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "game", "art", "aphid")
KINDS = ["plain", "packed", "armored", "royal"]
os.makedirs(OUT, exist_ok=True)
items = []
for pose, src in (("a", "aphids.png"), ("b", "aphids_b.png")):
    im = Image.open(os.path.join(ROOT, "art_src", src)).convert("RGBA")
    W, H = im.size
    alpha = np.asarray(im.getchannel("A")) > 20
    lab, n = ndimage.label(ndimage.binary_dilation(alpha, iterations=6))
    blobs = []
    for i, s in enumerate(ndimage.find_objects(lab)):
        area = int((lab[s] == i + 1).sum())
        if area > 20000:
            blobs.append((i + 1, s))
    assert len(blobs) == 4, (src, len(blobs))
    # reading order: two rows of two
    blobs.sort(key=lambda b: ((b[1][0].start + b[1][0].stop) / 2) // (H / 2) * 10000 + (b[1][1].start + b[1][1].stop) / 2)
    for (lid, s), kind in zip(blobs, KINDS):
        region = ndimage.binary_dilation(lab[s] == lid, iterations=6)
        crop = im.crop((s[1].start, s[0].start, s[1].stop, s[0].stop))
        a = np.asarray(crop).copy()
        a[~region, 3] = 0
        out = Image.fromarray(a, "RGBA")
        bb = out.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
        out = out.crop(bb)
        name = "aphid_%s_%s" % (kind, pose)
        out.save(os.path.join(OUT, name + ".png"))
        items.append({"name": name, "file": "aphid/%s.png" % name, "kind": kind, "pose": pose, "w": out.width, "h": out.height})
json.dump({"_about": "The owner's aphid mounts (tools/art/make_aphids.py): faces right, two honey tubes on the back, the saddle where the rider sits. "
           "pose a and b are two leg poses of the same four aphids.", "aphids": items}, open(os.path.join(OUT, "aphid_manifest.json"), "w"), indent=1)
print("cut", len(items))
