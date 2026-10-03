#!/usr/bin/env python3
"""Straighten the owner's earthworm (art_src/fauna_bodies.png, RGBA) into a strip the game can bend.

The drawing is a wavy worm, tail on the left, round open mouth on the right. The game gives the worm an invisible spine (a chain of
joints that follow the head like links of a rope) and lays the picture along it, so the picture itself must be straight: for every point
of the worm's centre line we sample the drawing across the body (along the normal) and write that slice as one column of the strip.
Output: content/art/worm_strip.png (tail at the left edge, mouth at the right edge, the body centred on the middle row).

Needs Pillow and numpy:  python3 tools/art/make_worm.py
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src", "fauna_bodies.png")
OUT = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art", "worm_strip.png")
BOX = (1140, 440, 1672, 620)        # the worm on the body sheet
LENGTH = 420                        # strip length in the game file (px)


def cut_out(im):
    """The owner's pictures carry real transparency: clean the alpha (no dust, no see-through film) and keep the largest piece."""
    rgba = np.asarray(im.convert("RGBA")).astype(np.float32)
    a = rgba[..., :3]
    h, w, _ = a.shape
    alpha = rgba[..., 3].copy()
    alpha[alpha < 10] = 0.0
    alpha[alpha >= 250] = 255.0
    # keep only the biggest connected piece (drops the stray fleck at the left)
    solid = alpha > 40
    lab = np.zeros((h, w), np.int32)
    best, best_n, cur = 0, 0, 0
    for sy in range(h):
        for sx in range(w):
            if solid[sy, sx] and lab[sy, sx] == 0:
                cur += 1
                n = 0
                st = [(sy, sx)]
                lab[sy, sx] = cur
                while st:
                    y, x = st.pop()
                    n += 1
                    for yy, xx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                        if 0 <= yy < h and 0 <= xx < w and solid[yy, xx] and lab[yy, xx] == 0:
                            lab[yy, xx] = cur
                            st.append((yy, xx))
                if n > best_n:
                    best, best_n = cur, n
    keep = lab == best
    # grow the kept piece by 2 px so its soft rim stays
    grown = keep.copy()
    for _ in range(2):
        g = grown.copy()
        g[1:, :] |= grown[:-1, :]
        g[:-1, :] |= grown[1:, :]
        g[:, 1:] |= grown[:, :-1]
        g[:, :-1] |= grown[:, 1:]
        grown = g
    alpha = np.where(grown, alpha, 0.0)
    rgba = np.dstack([a, alpha]).astype(np.uint8)
    return rgba


def bilinear(img, x, y):
    h, w = img.shape[:2]
    x = np.clip(x, 0, w - 1.001)
    y = np.clip(y, 0, h - 1.001)
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    fx = (x - x0)[..., None]
    fy = (y - y0)[..., None]
    c00 = img[y0, x0]
    c10 = img[y0, x0 + 1]
    c01 = img[y0 + 1, x0]
    c11 = img[y0 + 1, x0 + 1]
    return c00 * (1 - fx) * (1 - fy) + c10 * fx * (1 - fy) + c01 * (1 - fx) * fy + c11 * fx * fy


def main():
    rgba = cut_out(Image.open(SRC).crop(BOX)).astype(np.float32)
    alpha = rgba[..., 3]
    h, w = alpha.shape
    # premultiply so the soft rim does not drag white into the samples
    pm = rgba.copy()
    pm[..., :3] *= (alpha[..., None] / 255.0)
    # centre line: the middle of the body in every column, smoothed
    xs, mids, halves = [], [], []
    for x in range(w):
        col = np.nonzero(alpha[:, x] > 128)[0]
        if col.size >= 6:
            xs.append(x)
            mids.append((col[0] + col[-1]) / 2.0)
            halves.append((col[-1] - col[0]) / 2.0)
    xs = np.array(xs, float)
    mids = np.array(mids, float)
    k = 31
    pad = np.pad(mids, (k // 2, k // 2), mode="edge")
    mids = np.convolve(pad, np.ones(k) / k, mode="valid")
    # the mouth end is a disc seen face on: keep the axis level over its last stretch so the ring is not sheared
    tail_x, head_x = xs[0], xs[-1]
    # resample the centre line by arc length
    pts = np.stack([xs, mids], axis=1)
    seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    total = s[-1]
    n = int(total)
    ss = np.linspace(0.0, total, n)
    cx = np.interp(ss, s, pts[:, 0])
    cy = np.interp(ss, s, pts[:, 1])
    tx = np.gradient(cx)
    ty = np.gradient(cy)
    tl = np.hypot(tx, ty) + 1e-6
    tx, ty = tx / tl, ty / tl
    nx, ny = -ty, tx                      # the normal pointing down the picture
    half = int(np.ceil(max(halves) + 8))
    v = np.arange(-half, half + 1, dtype=float)
    X = cx[None, :] + nx[None, :] * v[:, None]
    Y = cy[None, :] + ny[None, :] * v[:, None]
    strip = bilinear(pm, X, Y)
    a = strip[..., 3:4]
    rgb = np.where(a > 0.5, strip[..., :3] / np.maximum(a, 1e-3) * 255.0, 0.0)
    out = np.concatenate([rgb, a], axis=2).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    bb = im.getchannel("A").point(lambda q: 255 if q > 8 else 0).getbbox()
    im = im.crop((bb[0], 0, bb[2], im.size[1]))
    k2 = LENGTH / float(im.size[0])
    im = im.resize((LENGTH, max(8, int(round(im.size[1] * k2)))), Image.LANCZOS)
    im.save(OUT, optimize=True)
    print("wrote", OUT, im.size, "from a centre line of %.0f px (%d..%d)" % (total, tail_x, head_x))


if __name__ == "__main__":
    sys.exit(main())
