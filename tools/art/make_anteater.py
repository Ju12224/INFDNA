#!/usr/bin/env python3
"""Cut the owner's anteater (art_src/anteater_*.png, RGBA with real transparency) into the pieces the game animates.

body: the whole animal with head and tail and no legs (anteater_body.png), facing right.
legs: the two clawed legs (anteater_leg_b.png, the bigger, for the near side; anteater_leg_a.png for the far side), turned from the
diagonal they are drawn on to hang down with the claws hooked forward. Each leg swings from its top (the pivot, in the manifest).
Output: content/art/anteater/{body,leg_near,leg_far}.png and anteater_manifest.json (sizes, leg pivots, where the legs join the body).

Needs Pillow and numpy:  python3 tools/art/make_anteater.py
"""
import json
import os

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "anteater")
K = 0.5                    # game files at half the drawing's size
TURN = -32.0               # degrees (PIL: negative turns clockwise): from the drawn diagonal to hanging down
# where the legs join the body, as a share of the body picture (x from the tail end, y from the top); far legs a little behind
JOINS = {"front_near": [0.700, 0.80], "front_far": [0.665, 0.77], "hind_near": [0.330, 0.80], "hind_far": [0.295, 0.77]}


def clean(im):
    a = np.asarray(im.convert("RGBA")).copy()
    a[..., 3][a[..., 3] < 10] = 0
    im = Image.fromarray(a, "RGBA")
    return im.crop(im.getchannel("A").point(lambda q: 255 if q > 8 else 0).getbbox())


def half(im):
    return im.resize((max(1, int(round(im.width * K))), max(1, int(round(im.height * K)))), Image.LANCZOS)


def leg(name):
    im = clean(Image.open(os.path.join(SRC, name)))
    im = clean(im.rotate(TURN, resample=Image.BICUBIC, expand=True))
    im = half(im)
    a = np.asarray(im)[..., 3]
    # the pivot: the middle of the top tenth of the leg (the shoulder fur), a little down so the joint hides under the body
    rows = max(1, im.height // 10)
    ys, xs = np.nonzero(a[:rows] > 128)
    px = float(xs.mean()) if xs.size else im.width * 0.3
    return im, [px / im.width, 0.08]


def main():
    os.makedirs(OUT, exist_ok=True)
    body = half(clean(Image.open(os.path.join(SRC, "anteater_body.png"))))
    body.save(os.path.join(OUT, "body.png"), optimize=True)
    man = {"body": {"file": "anteater/body.png", "w": body.width, "h": body.height}, "joins": JOINS}
    for key, src in (("leg_near", "anteater_leg_b.png"), ("leg_far", "anteater_leg_a.png")):
        im, piv = leg(src)
        im.save(os.path.join(OUT, key + ".png"), optimize=True)
        man[key] = {"file": "anteater/" + key + ".png", "w": im.width, "h": im.height, "pivot": piv}
    with open(os.path.join(OUT, "anteater_manifest.json"), "w") as f:
        json.dump(man, f, indent=1)
    print(json.dumps(man))


if __name__ == "__main__":
    main()
