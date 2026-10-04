"""The meadow scenery from the owner's sheets (called by make_art.py: make_scenery).

art_src/scenery_bushes.png (three bushes, one with red berries), scenery_ferns.png (three ferns) and scenery_mushrooms.png (a fly agaric pair,
tall pale inkcaps, brown ceps) are RGBA with real transparency, 1448x1086. Every item is cut from the alpha (pixels under alpha 10 are dropped,
250-254 count as opaque), scaled down to a working size that stays crisp at the closest zoom, and written to content/art/scenery/ as one PNG per
look:
  - bushes: as drawn ("summer") and an autumn recolour; the berry bush also without its berries ("summer_nb", "autumn_nb": the game shows the
    berries only from late summer through autumn). The berries are painted out with patches of the bush's own foliage;
  - ferns: as drawn and rust-brown for autumn (the game lays winter ferns flat, darker, or leaves them out);
  - mushroom clusters: as drawn (the game grows them in autumn and after rain).
The manifest entry ("scenery" in art_manifest.json) gives each item's files, size, foot (the point that stands on the ground, in texture px) and
its height in the game at perspective 1 (an ant is ANT_PX long).

Needs Pillow, numpy and scipy (tree_art.py for the recolour and the compact PNGs).
"""
import os

import numpy as np
from PIL import Image
from scipy import ndimage as ndi

import tree_art as T

ANT_PX = 40.0
SHEETS = [("scenery_bushes.png", "bush"), ("scenery_ferns.png", "fern"), ("scenery_mushrooms.png", "shroom")]
# items by place on the sheet: the top row left to right, then the bottom one
NAMES = {"bush": ["bush_round", "bush_wide", "bush_berry"], "fern": ["fern_upright", "fern_arching", "fern_big"],
         "shroom": ["shroom_agaric", "shroom_inkcap", "shroom_cep"]}
GAME_H = {"bush": (1.5, 3.0), "fern": (2.0, 3.0), "shroom": (1.0, 1.5)}     # how tall an item stands in the game, in ant lengths (each one picks its own)
TEX_H = {"bush": 340, "fern": 340, "shroom": 210}                            # texture height of the tallest item of a kind (the others in proportion)
AUTUMN = {"bush": (0.085, 1.05, 1.2, 0.02, 0.38), "fern": (0.072, 1.0, 0.88, 0.0, 0.6)}   # recolour: hue, sat x, value x, value +, least saturation


def clean_alpha(a):
    """The owner's rule for these sheets: under 10 is nothing, 250 and up is solid."""
    a = a.copy()
    a[a < 10] = 0
    a[a >= 250] = 255
    return a


def cut_items(sheet):
    """The big connected pieces of a sheet (specks dropped), as (mask, box) in reading order."""
    a = np.asarray(sheet)[..., 3]
    lab, n = ndi.label(a >= 10)
    sizes = ndi.sum(np.ones_like(a), lab, range(1, n + 1))
    objs = ndi.find_objects(lab)
    items = []
    for i, s in enumerate(sizes):
        if s < 0.05 * max(sizes):
            continue
        sl = objs[i]
        cy = (sl[0].start + sl[0].stop) * 0.5
        cx = (sl[1].start + sl[1].stop) * 0.5
        items.append((lab == i + 1, (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop), cx, cy))
    h = a.shape[0]
    items.sort(key=lambda it: (0 if it[3] < h * 0.5 else 1, it[2]))
    return [(m, b) for m, b, _, _ in items]


def berry_mask(rgb, A):
    """The red berries with their highlights and their own dark outline round them."""
    h, s, v = T._rgb_to_hsv(rgb / 255.0)
    red = (A > 0.5) & ((h > 0.9) | (h < 0.03)) & (s > 0.45) & (v > 0.3)
    red = ndi.binary_opening(red, structure=T.disk(2))
    red = ndi.binary_fill_holes(ndi.binary_closing(red, structure=T.disk(4)))
    return ndi.binary_dilation(red, structure=T.disk(9)) & (A > 0.02)


def paint_out(rgb, A, region, rng_step=3):
    """Paint `region` over with patches of the picture's own texture: for every connected part, the offset whose ring of pixels round it matches best
    (colour and coverage) is copied in, feathered at the seam. Returns (rgb, A)."""
    rgb = rgb.copy()
    A = A.copy()
    H, W = A.shape
    lab, n = ndi.label(region)
    forbid = ndi.binary_dilation(region, structure=T.disk(4))
    feat = np.dstack([rgb / 255.0, A[..., None] * 1.5])
    for i in range(1, n + 1):
        R = lab == i
        ring = ndi.binary_dilation(R, structure=T.disk(8)) & ~R
        ys, xs = np.nonzero(R | ring)
        y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
        Rb, ringb = R[y0:y1, x0:x1], ring[y0:y1, x0:x1]
        tgt = feat[y0:y1, x0:x1]
        best, bo = None, None
        for dy in range(-y0, H - y1, rng_step):
            for dx in range(-x0, W - x1, rng_step):
                if abs(dx) < (x1 - x0) * 0.6 and abs(dy) < (y1 - y0) * 0.6:
                    continue
                sy0, sx0 = y0 + dy, x0 + dx
                src_A = A[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)]
                if (src_A[Rb] < 0.95).mean() > 0.02 and (A[y0:y1, x0:x1][ringb] > 0.5).mean() > 0.97:
                    continue                                    # an inside region wants a fully opaque source
                if forbid[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)][Rb | ringb].any():
                    continue
                src = feat[sy0:sy0 + (y1 - y0), sx0:sx0 + (x1 - x0)]
                d = ((src[ringb] - tgt[ringb]) ** 2).sum()
                if best is None or d < best:
                    best, bo = d, (dy, dx)
        if bo is None:
            continue
        dy, dx = bo
        inside = ndi.distance_transform_edt(Rb)
        w = T.smooth(inside, 0.0, 4.0)
        src_rgb = rgb[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
        src_A = A[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
        sub = rgb[y0:y1, x0:x1]
        subA = A[y0:y1, x0:x1]
        ww = np.where(Rb, w, 0.0)
        rgb[y0:y1, x0:x1] = sub * (1 - ww[..., None]) + src_rgb * ww[..., None]
        A[y0:y1, x0:x1] = subA * (1 - ww) + src_A * ww
    return rgb, A


def resize_rgba(im, size):
    """Resize with premultiplied alpha (no dark fringes), then the alpha cleaned again."""
    out = im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")
    rgb, A = T.to_arrays(out)
    a = clean_alpha(np.round(A * 255).astype(np.int32)) / 255.0
    return T.from_arrays(T.bleed(rgb, a), a)


def foot_of(A):
    """The point that stands on the ground: the middle of the lowest rows, at the bottom."""
    rows = np.nonzero((A > 0.5).any(1))[0]
    yb = int(rows[-1])
    band = A[max(0, yb - max(3, int(A.shape[0] * 0.06))):yb + 1] > 0.5
    xs = np.nonzero(band.any(0))[0]
    return [round(float(xs.mean()), 1), float(yb)]


def make_scenery(manifest, out_dir, src_dir):
    """Cut every item of the three sheets, write its looks to out_dir/scenery/ and record them in manifest["scenery"]. Returns {file: bytes}."""
    sub = os.path.join(out_dir, "scenery")
    os.makedirs(sub, exist_ok=True)
    sizes = {}
    items = {}
    for fname, kind in SHEETS:
        sheet = Image.open(os.path.join(src_dir, fname)).convert("RGBA")
        arr = np.asarray(sheet).copy()
        arr[..., 3] = clean_alpha(arr[..., 3].astype(np.int32)).astype(np.uint8)
        sheet = Image.fromarray(arr, "RGBA")
        cuts = cut_items(sheet)
        names = NAMES[kind]
        if len(cuts) != len(names):
            raise RuntimeError("%s: expected %d items, found %d" % (fname, len(names), len(cuts)))
        hmax = max(b[3] - b[1] for _, b in cuts)
        k = TEX_H[kind] / float(hmax)
        for (mask, box), nm in zip(cuts, names):
            pad = 6
            x0, y0, x1, y1 = max(0, box[0] - pad), max(0, box[1] - pad), min(sheet.size[0], box[2] + pad), min(sheet.size[1], box[3] + pad)
            rgb, A = T.to_arrays(sheet.crop((x0, y0, x1, y1)))
            A = A * mask[y0:y1, x0:x1]
            size = (max(4, int(round((x1 - x0) * k))), max(4, int(round((y1 - y0) * k))))
            looks = {"summer": T.from_arrays(T.bleed(rgb, A), A)}
            if nm == "bush_berry":
                rgb2, A2 = paint_out(rgb, A, berry_mask(rgb, A))
                looks["summer_nb"] = T.from_arrays(T.bleed(rgb2, A2), A2)
            files = {}
            for lk, im in list(looks.items()):
                small = resize_rgba(im, size)
                looks[lk] = small
                if kind in AUTUMN:
                    hue, sk, vk, va, smin = AUTUMN[kind]
                    looks[lk.replace("summer", "autumn")] = T.recolor(small, hue, sk, vk, va, sat_min=smin)
            for lk, im in looks.items():
                fn = "scenery/%s_%s.png" % (nm, lk)
                sizes[fn] = T.save_png(im, os.path.join(out_dir, fn))
                files[lk] = fn
            _, Af = T.to_arrays(looks["summer"])
            lo, hi = GAME_H[kind]
            items[nm] = {"kind": kind, "files": files, "w": size[0], "h": size[1], "foot": foot_of(Af),
                         "game_h": [round(lo * ANT_PX, 1), round(hi * ANT_PX, 1)]}
            print("scenery %s: %dx%d, looks %s, game height %s px" % (nm, size[0], size[1], ",".join(sorted(files)), items[nm]["game_h"]))
    manifest["scenery"] = {"_about": "Meadow scenery cut from art_src/scenery_*.png by tools/art/scenery_art.py; game_h is the height in px at perspective 1, "
                                     "foot the texture px that stands on the ground.", "ant_px": ANT_PX, "items": items}
    return sizes
