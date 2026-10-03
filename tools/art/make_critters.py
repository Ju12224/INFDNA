#!/usr/bin/env python3
"""Rig the owner's five critter sheets (art_src/critter_*.png) into pieces the game puts back together and animates (content/colony/rig_art.gd).

Every sheet is an RGBA picture with real transparency, 1448x1086: one body and the loose parts drawn beside it (legs in rows, wing+leg sets, eye
stalks). The matte is the sheet's own alpha: alpha below 10 is dust (wiped), 250-254 is the near-opaque film of the drawing (made solid), the
one-pixel soft edge in between stays. Each part is then
  * shrunk to the critter's working size (the whole assembled critter is CANVAS_W px wide in the file: about 8 px of file per game px, the same
    density as the fauna sprites, because the game draws these textures without mipmaps and a much bigger file would only shimmer),
  * given a thicker outline in the sheet's own ink colour (creature_cuts.thicken), so it still reads at 30-90 game px,
  * cut where one drawn piece holds several moving parts: a wing+leg set into its wings and its legs, a snail's eye-stalk pair into its stalks.
    That uses the seeded split of creature_cuts.partition: seed lines along every part, every pixel goes to the part it reaches first with the
    dark outlines costing more to cross, so the border falls in the middle of the outline between two parts,
  * placed: every leg / stalk / wing gets a hinge (`pivot`, its top or root) and is moved so that hinge sits where it belongs on the body
    (legs: their feet on one ground line with their tops tucked into the body; wings: their root on the top of the thorax).
The pieces go to content/art/critters/ and content/art/critter_manifest.json gets one entry per critter in the spider format of art_manifest.json
(canvas, order, parts [{layer, file, x, y, pivot, phase}], body, feet, width, height, scale), plus for the two flyers a "wings" list
[{layer, file, x, y, pivot, flap, speed, phase}] that rig_art.gd beats about the root. File names in the manifest are relative to content/art/
("critters/bee_body.png"), as art_lib.tex() expects.

The critters, and how each one moves in rig_art.gd:
  caterpillar  body (rotated 6 degrees so its raised tail comes down onto the same ground line as the head) + 6 near prolegs in front + 6 far ones
               behind, a little higher. Six a side makes rig_art use its wave gait (a ripple of steps from tail to head); "wave": true also
               ripples the body itself in vertical strips (the Void Maw's crawl), still at the head.
  snail        shell+foot body; two eye stalks behind the head, swaying on their base: the near one (light) is the front stalk of the light pair,
               the far one (dark) the back stalk of the dark pair, so the snail has two eyes and not four. The shell is a rigid piece of its own
               (stored as a jaw that never opens) so "wave" ripples only the soft foot under it.
  bee          fuzzy body; per side a pair of wings (fore and hind wing are hooked together in a bee, one piece) beating fast about the root
               on the thorax, and two legs dangling under the thorax.
  ladybug      body + 3 near legs + 3 far legs, all drawn behind the body so the rim of the shell hides where they join.
  dragonfly    long body; per side a fore wing and a hind wing (separate pieces, beating out of step as a dragonfly's do) and two dangling legs.

Needs Pillow, numpy and scipy:   python3 tools/art/make_critters.py [--only bee,snail] [--contact PATH] [--debug DIR]
  --contact PATH  also write a contact sheet: each critter assembled, with every leg / stalk / wing at +max and -max swing, and two walk frames
  --debug DIR     also write the seed lines and the split of every cut sheet
Does not touch art_manifest.json or any other manifest.
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import creature_cuts as CC  # noqa: E402  (thicken, edge_ink, partition, cut_legs, bbox_of)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
SRC = os.path.join(ROOT, "art_src")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "critters")
MANIFEST = os.path.join(ART, "critter_manifest.json")
DUST = 10           # alpha below this is dust
FILM = 250          # alpha from this up is solid
MIN_ISLAND = 150    # pieces of the alpha smaller than this (full-sheet px) are dust, unless they touch a real piece
MARGIN = 60         # transparent border round the working picture (room to rotate a body)
PAD = 4             # transparent border round the assembled critter in the canvas

# ------------------------------------------------------------------------------------------------------------------------------- the critters
# All points are in pixels of the art_src sheet. "to" says where a part's hinge goes, in the same pixels as the body (the body never moves,
# except the caterpillar's, which is rotated first: its numbers are on the drawing before the turn).
# Legs placed with "ground" have their pivot at x (sheet px) and their foot on one ground line: the line is as high as it can be while every leg
# still reaches `tuck` px (sheet) into the body above its pivot; a leg whose body is too high to reach the ground keeps the tuck instead.
CRITTERS = {
    "caterpillar": {
        "sheet": "critter_caterpillar.png", "canvas_w": 560, "length": 70.0, "outline": 2,
        "order": ["far", "body", "near"], "wave": True, "wave_strip": 12,
        "body": (700, 400),
        # the drawing lifts the tail: turn the body this many degrees (counter-clockwise on screen) about this point, so the six segments stand on
        # one line
        "rotate": (6.0, (910, 632)),
        "legs": {
            # islands of the sheet: the light prolegs in the first row are the near side, the dark ones in the second row the far side
            "near": {"rows": (650, 860), "ground": [178, 300, 452, 598, 748, 912], "tuck": 44},
            # the far side stands a little higher (further away) and a little nearer the head, so it shows between the near legs
            "far": {"rows": (880, 1060), "ground": [178, 300, 452, 598, 748, 912], "tuck": 44, "shift": (16, -30)},
        },
    },
    "snail": {
        "sheet": "critter_snail.png", "canvas_w": 440, "length": 55.0, "outline": 2,
        "order": ["far", "near", "body"], "wave": True, "wave_strip": 12,
        "body": (400, 500),
        # the shell, cut from the body by colour (the brown), with its outline: it stays rigid while the foot ripples
        "shell": {"shell": [[(80, 500), (200, 330), (380, 250), (560, 330), (660, 520)], [(150, 650), (300, 770), (480, 770), (520, 720), (640, 640)],
                            [(230, 560), (330, 470), (430, 560), (330, 680)], [(670, 630)]],
                  "foot": [[(60, 840), (250, 860), (450, 870), (650, 860), (780, 800)], [(700, 720), (800, 680), (870, 720)], [(900, 750)]]},
        # each eye-stalk picture is a head with two stalks: the stalks are cut from it and the head is dropped (the body has its own)
        "cuts": {
            "near": {"island": (1070, 600), "keep": ["front"], "cap_w": 5, "cut_y": 690,
                     "seeds": [{"name": "front", "pivot": (995, 644), "lines": [[(995, 640), (1000, 580), (1018, 500), (1045, 430)]]},
                               {"name": "back", "pivot": (1040, 640), "lines": [[(1040, 630), (1060, 600), (1110, 560), (1165, 505)]]},
                               {"name": "head", "lines": [[(990, 690), (1060, 720), (1120, 760)], [(1000, 770), (1040, 790)]]}]},
            "far": {"island": (1330, 600), "keep": ["back"], "cap_w": 5, "cut_y": 690,
                    "seeds": [{"name": "front", "pivot": (1252, 644), "lines": [[(1252, 640), (1258, 580), (1290, 500), (1325, 430)]]},
                              {"name": "back", "pivot": (1298, 640), "lines": [[(1298, 630), (1320, 600), (1370, 560), (1410, 535)]]},
                              {"name": "head", "lines": [[(1250, 690), (1310, 720), (1370, 760)], [(1260, 770), (1300, 790)]]}]},
        },
        # where the base of each stalk goes on the body's head (behind its top outline)
        "place": {"near": {"front": (795, 672)}, "far": {"back": (838, 672)}},
    },
    "bee": {
        "sheet": "critter_bee.png", "canvas_w": 256, "length": 32.0, "outline": 2,
        "order": ["far", "body", "near"], "wave": False,
        "body": (300, 650),
        "cuts": {
            "near": {"island": (850, 450),
                     "ink_cost": 10.0, "cap_w": 3,
                     "seeds": [{"name": "wing", "pivot": (1022, 556),
                                "lines": [[(1018, 556), (900, 450), (740, 310)], [(1000, 552), (850, 482), (670, 420)], [(1000, 554), (900, 550), (800, 552)]]},
                               {"name": "leg_a", "pivot": (822, 586), "lines": [[(822, 602), (815, 625), (790, 700), (760, 770), (737, 832)]]},
                               {"name": "leg_b", "pivot": (866, 590), "lines": [[(870, 604), (900, 630), (935, 660), (915, 730), (882, 792)]]}]},
            "far": {"island": (1250, 450),
                    "ink_cost": 10.0, "cap_w": 3,
                    "seeds": [{"name": "wing", "pivot": (1400, 560),
                               "lines": [[(1395, 558), (1280, 450), (1120, 320)], [(1380, 556), (1250, 500), (1080, 452)], [(1380, 556), (1290, 548), (1190, 540)]]},
                              {"name": "leg_a", "pivot": (1210, 582), "lines": [[(1208, 598), (1200, 620), (1170, 690), (1140, 770), (1122, 842)]]},
                              {"name": "leg_b", "pivot": (1250, 592), "lines": [[(1252, 604), (1290, 635), (1330, 652), (1310, 720), (1272, 788)]]}]},
        },
        # wings: the root on the top of the thorax; legs: their tops tucked under the thorax (the far side a little higher and further back)
        "place": {"near": {"wing": (372, 492), "leg_a": (318, 704), "leg_b": (362, 710)},
                  "far": {"wing": (352, 474), "leg_a": (292, 690), "leg_b": (336, 696)}},
        "wings": {"near": {"flap": 0.42, "speed": 55.0, "phase": 0.0}, "far": {"flap": 0.42, "speed": 55.0, "phase": 0.6}},
    },
    "ladybug": {
        "sheet": "critter_ladybug.png", "canvas_w": 224, "length": 28.0, "outline": 2,
        "order": ["far", "near", "body"], "wave": False,
        "body": (600, 300),
        "legs": {
            "near": {"rows": (660, 875), "ground": [440, 640, 800], "tuck": 60},
            "far": {"rows": (875, 1062), "ground": [440, 640, 800], "tuck": 60, "shift": (48, -34)},
        },
    },
    "dragonfly": {
        "sheet": "critter_dragonfly.png", "canvas_w": 700, "length": 90.0, "outline": 2,
        "order": ["far", "body", "near"], "wave": False,
        "body": (700, 200),
        "cuts": {
            "near": {"island": (700, 450),
                     "ink_cost": 12.0, "cap_w": 3,
                     # the hind wing lies over the fore wing at the root: the seeds run along the hind wing's pale leading edge and the fore wing's
                     # last row of cells, either side of the thick line between them
                     "seeds": [{"name": "fore", "pivot": (978, 512), "lines": [[(975, 510), (800, 470), (600, 440), (420, 370)], [(900, 540), (810, 530), (710, 520), (610, 500)]]},
                               {"name": "hind", "pivot": (950, 546), "lines": [[(945, 546), (800, 580), (620, 580), (470, 565)], [(905, 562), (810, 556), (710, 546), (610, 531)]]},
                               {"name": "leg_a", "pivot": (972, 552), "lines": [[(975, 548), (962, 568), (930, 620), (905, 690), (915, 770)]]},
                               {"name": "leg_b", "pivot": (995, 562), "lines": [[(995, 560), (1005, 600), (1015, 650), (1050, 710), (1095, 785)]]}]},
            "far": {"island": (700, 850), "ink_cost": 12.0, "cap_w": 3,
                    "seeds": [{"name": "fore", "pivot": (930, 878), "lines": [[(925, 878), (800, 845), (600, 785), (400, 725)]]},
                              {"name": "hind", "pivot": (918, 892), "lines": [[(915, 895), (780, 910), (620, 910), (510, 905)], [(610, 886), (680, 890), (760, 897)]]},
                              {"name": "leg_a", "pivot": (966, 860), "lines": [[(966, 860), (945, 895), (915, 940), (920, 1000), (920, 1050)]]},
                              {"name": "leg_b", "pivot": (986, 864), "lines": [[(986, 864), (1010, 895), (1045, 935), (1085, 990), (1100, 1050)]]}]},
        },
        "place": {"near": {"fore": (950, 104), "hind": (922, 138), "leg_a": (948, 214), "leg_b": (972, 224)},
                  "far": {"fore": (930, 88), "hind": (902, 120), "leg_a": (972, 200), "leg_b": (994, 208)}},
        # fore and hind wing beat out of step (the hind wing leads); the far pair a little behind the near pair
        "wings": {"near": {"flap": 0.3, "speed": 34.0, "phase": 0.0, "hind_phase": 1.6},
                  "far": {"flap": 0.3, "speed": 34.0, "phase": 0.5, "hind_phase": 2.1}},
    },
}
WING_ALPHA = 0.78    # the pale membrane of a wing is let see-through to this alpha (outline and veins stay solid)


# ------------------------------------------------------------------------------------------------------------------------------- the sheet
def load_sheet(name):
    im = Image.open(os.path.join(SRC, name))
    if im.mode != "RGBA":
        raise SystemExit("%s must be an RGBA picture with real transparency (it is %s)" % (name, im.mode))
    a = np.array(im.getchannel("A"))
    a = np.where(a < DUST, 0, np.where(a >= FILM, 255, a)).astype(np.uint8)
    rgb = np.array(im.convert("RGB"))
    rgb[a == 0] = 0                      # no stray colour under the transparent pixels (nothing can bleed in when a piece is scaled)
    return np.dstack([rgb, a])


def islands(arr):
    """Label every pixel of the sheet with the piece it belongs to (0 = none). Dust islands are dropped, slivers that touch a piece join it."""
    a = arr[..., 3]
    lab, n = ndi.label(a > 0, structure=np.ones((3, 3), bool))
    sizes = ndi.sum(np.ones_like(a), lab, range(1, n + 1))
    big = [i + 1 for i, s in enumerate(sizes) if s >= MIN_ISLAND]
    keep = np.isin(lab, big)
    # a small island within 3 px of a big one joins it
    near = ndi.grey_dilation(np.where(keep, lab, 0), size=(7, 7))
    out = np.where(keep, lab, 0)
    small = (lab > 0) & ~keep
    out[small & (near > 0)] = near[small & (near > 0)]
    return out


def island_at(lab, pt):
    x, y = pt
    v = lab[y, x]
    if v == 0:
        # nearest labelled pixel
        ys, xs = np.nonzero(lab)
        i = np.argmin((xs - x) ** 2 + (ys - y) ** 2)
        v = lab[ys[i], xs[i]]
    return int(v)


class Work:
    """The working size of one sheet: everything is cut and placed in these pixels (sheet px * k + MARGIN)."""

    def __init__(self, arr, lab, k, outline):
        self.arr = arr
        self.lab = lab
        self.k = k
        self.r = outline
        h, w = lab.shape
        self.sw = int(round(w * k))
        self.sh = int(round(h * k))
        self.size = (self.sw + 2 * MARGIN, self.sh + 2 * MARGIN)
        full = Image.fromarray(arr, "RGBA").resize((self.sw, self.sh), Image.LANCZOS)
        self.ink = CC.edge_ink(full)

    def w(self, p):
        return (p[0] * self.k + MARGIN, p[1] * self.k + MARGIN)

    def picture(self, ids):
        """The pieces `ids` alone, shrunk to the working size, with the thicker outline."""
        m = np.isin(self.lab, list(ids))
        arr = self.arr.copy()
        arr[~m] = 0
        small = Image.fromarray(arr, "RGBA").resize((self.sw, self.sh), Image.LANCZOS)
        im = Image.new("RGBA", self.size, (0, 0, 0, 0))
        im.paste(small, (MARGIN, MARGIN))
        return CC.thicken(im, self.r, self.ink)


def crop_piece(im, pivot=None):
    bb = CC.bbox_of(im)
    return {"img": im.crop(bb), "x": bb[0], "y": bb[1], "pivot": pivot}


def auto_top_pivot(piece, frac=0.2):
    """The hinge of a loose leg: the middle of its top end (centroid of the opaque pixels in the top `frac` of its height), in working px."""
    a = np.array(piece["img"].getchannel("A")) >= 128
    ys, xs = np.nonzero(a)
    top, bot = ys.min(), ys.max()
    band = ys <= top + frac * (bot - top)
    return (piece["x"] + float(xs[band].mean()), piece["y"] + float(ys[band].mean()))


def foot_y(piece):
    a = np.array(piece["img"].getchannel("A")) >= 128
    ys = np.nonzero(a.any(axis=1))[0]
    return piece["y"] + float(ys.max())


def move(piece, to):
    """Move a piece so its pivot lands on `to` (whole pixels, so the PNG sits on the pixel grid)."""
    dx = int(round(to[0] - piece["pivot"][0]))
    dy = int(round(to[1] - piece["pivot"][1]))
    piece["x"] += dx
    piece["y"] += dy
    piece["pivot"] = (piece["pivot"][0] + dx, piece["pivot"][1] + dy)
    return piece


def rot_pt(p, c, deg):
    """A point turned `deg` degrees counter-clockwise on screen (y down) about c, as Image.rotate turns the picture."""
    t = math.radians(deg)
    dx, dy = p[0] - c[0], p[1] - c[1]
    return (c[0] + dx * math.cos(t) + dy * math.sin(t), c[1] - dx * math.sin(t) + dy * math.cos(t))


def body_bottom(body, x):
    """Lowest solid pixel of the body in working column x (searched over +-2 px)."""
    a = np.array(body["img"].getchannel("A")) >= 128
    cx = int(round(x - body["x"]))
    best = None
    for c in range(cx - 2, cx + 3):
        if 0 <= c < a.shape[1]:
            ys = np.nonzero(a[:, c])[0]
            if len(ys):
                v = body["y"] + ys.max()
                best = v if best is None else min(best, v)
    return best


def translucent_wing(img):
    """Let the pale membrane of a wing see-through (to WING_ALPHA), keeping the outline and the veins solid."""
    arr = np.array(img).astype(np.float32)
    lum = arr[..., :3].mean(axis=2)
    f = 1.0 - (1.0 - WING_ALPHA) * np.clip((lum - 120.0) / 50.0, 0.0, 1.0)
    arr[..., 3] *= f
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")


# ------------------------------------------------------------------------------------------------------------------------------- cutting
def split(pic, legs, ink_cost=5.0, rim=3):
    """creature_cuts.cut_legs with a chosen price for crossing an outline: the seeded split of one picture into its parts, each keeping a thin
    rim of its neighbours' outline so its own outline stays closed when it moves. Seed lines are in the picture's own pixels."""
    lab, ink = CC.partition(pic, legs, 1.0, ink_cost=ink_cost)
    a = pic.getchannel("A")
    out = []
    for li, leg in enumerate(legs):
        m = lab.point(lambda v, li=li: 255 if v == li else 0)
        if m.getbbox() is None:
            continue
        piece = pic.copy()
        piece.putalpha(ImageChops.multiply(a, CC.grow_in(m, ink, rim)))
        piece = CC.drop_specks(piece, 40, 0.03)
        bb = CC.bbox_of(piece)
        if bb is None:
            continue
        out.append({"img": piece.crop(bb), "x": bb[0], "y": bb[1], "pivot": leg.get("pivot", leg["lines"][0][0]), "name": leg.get("name", str(li)),
                    "mask": m})
    return out


def cap_edge(pic, own, gone, ink, w):
    """The picture's pixels of `own` (bool mask) with an outline (colour `ink`) along the border with the masks in `gone`: own pixels within
    w px of them are painted ink, and their pixels within 2 px of own are taken in as ink too. Returns (image, x, y) cropped."""
    arr = np.array(pic)
    a = arr[..., 3]
    g = np.zeros_like(own)
    for m in gone:
        g |= m
    d_g = ndi.distance_transform_edt(~g)
    d_o = ndi.distance_transform_edt(~own)
    cap = (own & (d_g <= w)) | (g & (d_o <= 2))
    cap = ndi.gaussian_filter(cap.astype(float), 0.8) > 0.5
    keep = own | cap
    # thin slivers of the neighbour's outline that the split left on this part (spikes a few px wide) are opened away
    disk = np.hypot(*np.mgrid[-3:4, -3:4]) <= 3.2
    solid = ndi.binary_opening(keep & (a >= 128), structure=disk)
    keep = keep & ndi.binary_dilation(solid, iterations=1)
    cap &= keep
    out = arr.copy()
    out[~keep, 3] = 0
    out[cap & (a > 0), :3] = ink
    out[cap & (a > 0), 3] = np.maximum(a[cap & (a > 0)], 230)
    im = Image.fromarray(out, "RGBA")
    bb = CC.bbox_of(im)
    return im.crop(bb), bb[0], bb[1]


def cut_set(wk, spec, debug=None, tag=""):
    """Split one drawn set (a wing+leg set, an eye-stalk pair) along its seed lines. Returns {name: piece} in working px."""
    iid = island_at(wk.lab, spec["island"])
    pic = wk.picture([iid])
    legs = []
    for s in spec["seeds"]:
        d = {"name": s["name"], "lines": [[wk.w(p) for p in line] for line in s["lines"]]}
        if "pivot" in s:
            d["pivot"] = wk.w(s["pivot"])
        legs.append(d)
    if spec.get("cut_y") is not None:
        # the head under the stalks is dropped below this line (it hides behind the body's own head)
        cy = wk.w((0, spec["cut_y"]))[1]
        m = Image.new("L", pic.size, 255)
        ImageDraw.Draw(m).rectangle([0, int(cy), pic.size[0], pic.size[1]], fill=0)
        pic_cut = pic.copy()
        pic_cut.putalpha(ImageChops.multiply(pic.getchannel("A"), m))
    else:
        pic_cut = pic
    pieces = split(pic, legs, spec.get("ink_cost", 5.0))
    out = {}
    masks = {p["name"]: np.array(p["mask"]) > 0 for p in pieces}
    for p in pieces:
        if spec.get("keep") and p["name"] not in spec["keep"]:
            continue
        img = p["img"]
        if spec.get("cap_w"):
            # instead of a rim of the neighbours' outline (loose spikes once the neighbour moves away or is dropped), the edge where every other
            # part of the set touched this one is closed with an outline of its own, about as thick as the drawn one
            others = [m for n, m in masks.items() if n != p["name"]]
            img, p["x"], p["y"] = cap_edge(pic, masks[p["name"]], others, wk.ink, spec["cap_w"])
        if pic_cut is not pic:
            # apply the cut line to this piece
            full = Image.new("RGBA", pic.size, (0, 0, 0, 0))
            full.paste(img, (p["x"], p["y"]))
            full.putalpha(ImageChops.multiply(full.getchannel("A"), pic_cut.getchannel("A").point(lambda v: 255 if v else 0)))
            bb = CC.bbox_of(full)
            img = full.crop(bb)
            p["x"], p["y"] = bb[0], bb[1]
        out[p["name"]] = {"img": img, "x": p["x"], "y": p["y"], "pivot": p["pivot"]}
    if debug:
        dbg = Image.new("RGBA", pic.size, (60, 70, 60, 255))
        cols = [(255, 80, 80), (80, 200, 255), (255, 220, 60), (160, 255, 120), (230, 120, 255)]
        for i, p in enumerate(pieces):
            tint = Image.new("RGBA", p["img"].size, cols[i % len(cols)] + (0,))
            tint.putalpha(p["img"].getchannel("A").point(lambda v: v // 2))
            dbg.alpha_composite(p["img"], (p["x"], p["y"]))
            dbg.alpha_composite(tint, (p["x"], p["y"]))
        d = ImageDraw.Draw(dbg)
        for i, s in enumerate(legs):
            for line in s["lines"]:
                d.line(line, fill=cols[i % len(cols)] + (255,), width=2)
            pv = s.get("pivot", s["lines"][0][0])
            d.ellipse([pv[0] - 3, pv[1] - 3, pv[0] + 3, pv[1] + 3], outline=(255, 255, 255, 255), width=2)
        bb = CC.bbox_of(pic)
        dbg.crop((bb[0] - 10, bb[1] - 10, bb[2] + 10, bb[3] + 10)).save(os.path.join(debug, "%s_cut.png" % tag))
    return out


def cut_shell(wk, body, spec):
    """Split the snail's body into the rigid shell and the soft foot, with the seeded split (seed lines in spec["shell"] / spec["foot"]):
    the border falls on the outline between them and the shell keeps that whole outline. The shell is drawn over the rippling foot. Under the
    shell's lower edge the foot gets a band of its own colour (FILL px tall), so a foot that sinks a little shows more foot under the shell, never
    a hole; the rest of the shell is cut out of the foot picture, so a foot that rises shows no second shell edge round the rigid one."""
    img = body["img"]

    def loc(p):
        q = wk.w(p)
        return (q[0] - body["x"], q[1] - body["y"])
    legs = [{"name": "shell", "lines": [[loc(p) for p in line] for line in spec["shell"]]},
            {"name": "foot", "lines": [[loc(p) for p in line] for line in spec["foot"]]}]
    lab, ink = CC.partition(img, legs, 1.0, ink_cost=spec.get("ink_cost", 8.0))
    sm = CC.grow_in(lab.point(lambda v: 255 if v == 0 else 0), ink, spec.get("rim", 4))
    sm = CC.smooth_mask(sm, 1.0)
    arr = np.array(img)
    a = arr[..., 3]
    S = (np.array(sm) > 0) & (a > 0)
    # the shell's soft edge (the antialiased pixels just outside the solid mask) goes with the shell, or a rising foot would show it as a ghost rim
    S_all = S | (ndi.binary_dilation(S, iterations=3) & (a > 0) & (a < 250))
    F = (a > 0) & ~S_all
    shell = img.copy()
    shell.putalpha(Image.fromarray(np.where(S_all, a, 0).astype(np.uint8), "L"))
    fill = spec.get("fill", 16)
    rise = spec.get("rise", 12)          # the most the foot rises in rig_art's ripple (11 canvas px), plus one
    foot = arr.copy()
    foot[S_all, 3] = 0
    # in every column: the shell's lowest edge with foot right under it, how much shell is above that edge, and the colour of the foot a little
    # way under it (smoothed along the body, so the band reads as more foot in the shell's shadow, not as streaks)
    h, w = S.shape
    edge = np.full(w, -1)
    depth = np.zeros(w, int)
    col = np.zeros((w, 3))
    for x in range(w):
        ys = np.nonzero(S[:-3, x] & ~S[1:-2, x] & (F[1:-2, x] | F[2:-1, x] | F[3:, x]))[0]
        if not len(ys):
            continue
        y = ys.max()
        run = 0
        while y - run >= 0 and S[y - run, x]:
            run += 1
        rows = [r for r in range(y + 6, min(h, y + 16)) if F[r, x] and a[r, x] >= 250]
        if not rows:
            continue
        edge[x], depth[x] = y, run
        col[x] = arr[rows, x, :3].mean(axis=0)
    ok = edge >= 0
    if ok.any():
        wsum = ndi.gaussian_filter1d(ok.astype(float), 5.0)
        for c in range(3):
            col[:, c] = np.where(ok, ndi.gaussian_filter1d(col[:, c] * ok, 5.0) / np.maximum(wsum, 1e-6), 0)
        for x in np.nonzero(ok)[0]:
            # a band no taller than the shell above it can hide when the foot rises
            hb = int(min(fill, depth[x] - rise))
            if hb <= 0:
                continue
            y = edge[x]
            foot[y - hb + 1:y + 1, x, :3] = col[x].astype(np.uint8)
            foot[y - hb + 1:y + 1, x, 3] = 255
    fp = {"img": Image.fromarray(foot, "RGBA"), "x": body["x"], "y": body["y"]}
    sbb = CC.bbox_of(shell)
    sp = {"img": shell.crop(sbb), "x": body["x"] + sbb[0], "y": body["y"] + sbb[1]}
    return fp, sp


# ------------------------------------------------------------------------------------------------------------------------------- one critter
def build(name, spec, out_dir, debug=None):
    arr = load_sheet(spec["sheet"])
    lab = islands(arr)
    bid = island_at(lab, spec["body"])
    ys, xs = np.nonzero(lab == bid)
    # working scale: the whole critter about canvas_w wide. Its width is about the body's (legs and wings stay within it); refined below.
    k = spec["canvas_w"] / float(xs.max() - xs.min() + 1)
    wk = Work(arr, lab, k, spec["outline"])
    body_pic = wk.picture([bid])
    if spec.get("rotate"):
        deg, c = spec["rotate"]
        body_pic = body_pic.convert("RGBa").rotate(deg, resample=Image.BICUBIC, center=wk.w(c)).convert("RGBA")
    body = crop_piece(body_pic)
    parts = []          # (layer, name, piece)
    wings = []          # (layer, name, piece, flap, speed, phase)
    jaws = []

    def to_body(pt):
        """Sheet px on the drawing -> working px on the (possibly rotated) body."""
        q = wk.w(pt)
        if spec.get("rotate"):
            deg, c = spec["rotate"]
            q = rot_pt(q, wk.w(c), deg)
        return q

    # loose legs in rows (caterpillar, ladybug)
    for layer, ls in spec.get("legs", {}).items():
        y0, y1 = ls["rows"]
        ids = []
        for i in np.unique(lab):
            if i == 0 or i == bid:
                continue
            yy, xx = np.nonzero(lab == i)
            if y0 <= yy.mean() < y1:
                ids.append((xx.mean(), int(i)))
        ids.sort()
        if len(ids) != len(ls["ground"]):
            print("  WARNING: %s %s: %d legs on the sheet, %d places" % (name, layer, len(ids), len(ls["ground"])))
        pieces = []
        for _, i in ids:
            p = crop_piece(wk.picture([i]))
            p["pivot"] = auto_top_pivot(p)
            pieces.append(p)
        # the pivot x of every leg, on the body, and the lowest place each may hang from (tucked into the body by `tuck`)
        sx, sy = ls.get("shift", (0, 0))
        tuck = ls["tuck"] * wk.k
        xs_w, limit, reach = [], [], []
        for p, gx in zip(pieces, ls["ground"]):
            # the bottom of the drawing at gx, carried through the body's rotation
            col = np.nonzero(lab[:, gx] == bid)[0]
            q = to_body((gx, col.max()))
            x = q[0] + sx * wk.k
            xs_w.append(x)
            limit.append(body_bottom(body, x) - tuck)
            reach.append(foot_y(p) - p["pivot"][1])
        # one ground line for this side, as high as possible with every leg tucked in; the far side is `shift` higher on top of that
        ground = min(l + r for l, r in zip(limit, reach))
        if layer == "far" and "_near_ground" in spec:
            ground = min(ground, spec["_near_ground"] + sy * wk.k)
        if layer == "near":
            spec["_near_ground"] = ground
        for p, x, l, r in zip(pieces, xs_w, limit, reach):
            pv_y = min(l, ground - r)
            move(p, (x, pv_y))
            gap = (ground - (pv_y + r)) / wk.k
            if gap > 2:
                print("  %s %s leg at x %.0f stands %.0f sheet px above the ground (body too high there)" % (name, layer, x, gap))
            parts.append((layer, "", p))

    # cut sets (snail stalks, wing+leg sets)
    for layer, cs in spec.get("cuts", {}).items():
        got = cut_set(wk, cs, debug, "%s_%s" % (name, layer))
        for pname, p in got.items():
            to = spec["place"][layer][pname]
            move(p, to_body(to))
            is_wing = pname in ("wing", "fore", "hind")
            if is_wing:
                ws = spec["wings"][layer]
                p["img"] = translucent_wing(p["img"])
                ph = ws.get("hind_phase", ws["phase"]) if pname == "hind" else ws["phase"]
                wings.append((layer, pname, p, ws["flap"], ws["speed"], ph))
            else:
                parts.append((layer, pname, p))

    if spec.get("shell"):
        body, shell = cut_shell(wk, body, spec["shell"])
        jaws.append(shell)

    # the canvas: the union of everything at rest, with PAD round it
    boxes = [(body["x"], body["y"], body["x"] + body["img"].size[0], body["y"] + body["img"].size[1])]
    for coll in (parts, wings):
        for it in coll:
            p = it[2]
            boxes.append((p["x"], p["y"], p["x"] + p["img"].size[0], p["y"] + p["img"].size[1]))
    ux0 = min(b[0] for b in boxes)
    uy0 = min(b[1] for b in boxes)
    ux1 = max(b[2] for b in boxes)
    uy1 = max(b[3] for b in boxes)
    ox, oy = PAD - ux0, PAD - uy0
    canvas = [ux1 - ux0 + 2 * PAD, uy1 - uy0 + 2 * PAD]

    def at(p):
        return p["x"] + ox, p["y"] + oy

    def pv(p):
        return [round(p["pivot"][0] + ox, 1), round(p["pivot"][1] + oy, 1)]

    os.makedirs(out_dir, exist_ok=True)
    rel = os.path.basename(out_dir)

    def save(img, fn):
        img.save(os.path.join(out_dir, fn), optimize=True)
        return rel + "/" + fn

    entry = {"canvas": canvas, "order": spec["order"], "parts": [], "wave": bool(spec.get("wave", False))}
    if spec.get("wave_strip"):
        # narrower strips for the rippling body than the Void Maw's 34 px: on a small canvas the ripple is steeper and wide strips show steps
        entry["wave_strip"] = spec["wave_strip"]
    # phases: neighbouring legs of a side step in opposite phase, the far side opposite to the near side (as creature_cuts does)
    for layer in ("far", "near"):
        mine = [it for it in parts if it[0] == layer]
        order_x = sorted(range(len(mine)), key=lambda i: mine[i][2]["pivot"][0])
        for rank, i in enumerate(order_x):
            lyr, pname, p = mine[i]
            fn = save(p["img"], "%s_%s_%d.png" % (name, layer, rank))
            x, y = at(p)
            entry["parts"].append({"layer": layer, "file": fn, "x": x, "y": y, "pivot": pv(p), "phase": (rank + (1 if layer == "far" else 0)) % 2})
    x, y = at(body)
    entry["body"] = {"file": save(body["img"], "%s_body.png" % name), "x": x, "y": y}
    if jaws:
        entry["jaws"] = []
        for i, j in enumerate(jaws):
            x, y = at(j)
            # a rigid piece over the body: a "jaw" that never opens (open 0), so it bobs with the body but does not ripple with it
            entry["jaws"].append({"file": save(j["img"], "%s_shell.png" % name), "x": x, "y": y, "pivot": [x, y], "open": 0.0})
    if wings:
        entry["wings"] = []
        for layer in ("far", "near"):
            for lyr, pname, p, flap, speed, ph in wings:
                if lyr != layer:
                    continue
                fn = save(p["img"], "%s_wing_%s_%s.png" % (name, layer, pname))
                x, y = at(p)
                entry["wings"].append({"layer": layer, "file": fn, "x": x, "y": y, "pivot": pv(p), "flap": flap, "speed": speed, "phase": ph})
    entry["feet"] = [round(canvas[0] / 2.0, 1), float(uy1 - uy0 + PAD)]
    entry["width"] = float(ux1 - ux0)
    entry["height"] = float(uy1 - uy0)
    entry["scale"] = round(spec["length"] / entry["width"], 5)
    entry["game_len"] = spec["length"]
    entry["facing"] = "right"
    print("%s: canvas %s, %d parts, %d wings, game %.0f px (scale %.4f)" % (name, canvas, len(entry["parts"]), len(wings), spec["length"], entry["scale"]))
    return entry


# ------------------------------------------------------------------------------------------------------------------------------- preview
def _put(frame, img, pos, pivot, ang):
    """Draw img at pos, turned `ang` radians about pivot the way Godot turns it (positive = clockwise on screen)."""
    layer = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    layer.paste(img, (int(round(pos[0])), int(round(pos[1]))))
    if ang:
        layer = layer.convert("RGBa").rotate(-math.degrees(ang), resample=Image.BICUBIC, center=pivot).convert("RGBA")
    frame.alpha_composite(layer)


def rig_frame(e, t, moving, force=None, margin=None):
    """One frame of the critter as rig_art.gd draws it (same formulas), at canvas size. force = +1 / -1 puts every leg and wing at its swing."""
    imgs = {}

    def tex(fn):
        if fn not in imgs:
            imgs[fn] = Image.open(os.path.join(ART, fn)).convert("RGBA")
        return imgs[fn]
    W, H = e["canvas"]
    if margin is None:
        margin = int(0.3 * max(W, H)) if "wings" in e else 40      # room for a wing beaten up past the canvas
    frame = Image.new("RGBA", (W + 2 * margin, H + 2 * margin), (0, 0, 0, 0))
    o = (margin, margin)
    gait = 6.0 if moving else 1.6
    amp = 0.13 if moving else 0.025
    fly = "wings" in e
    if fly:
        gait, amp = 2.2, 0.1
    bob = math.sin(t * gait * 2.0) * (3.0 if moving else 1.2)
    if force is not None:
        bob = 0.0
    for layer in e["order"]:
        if layer == "body":
            b = e["body"]
            bt = tex(b["file"])
            bx, by = b["x"] + o[0], b["y"] + o[1] + bob
            if e.get("wave") and force is None:
                sw_ = int(e.get("wave_strip", 34))
                x = 0
                while x < bt.size[0]:
                    u = x / float(bt.size[0])
                    dy = math.sin(t * (3.2 if moving else 1.2) - u * 8.0) * (11.0 if moving else 4.0) * (1.0 - min(1.0, max(0.0, (u - 0.45) / 0.45)))
                    strip = bt.crop((x, 0, min(x + sw_ + 1, bt.size[0]), bt.size[1]))
                    frame.alpha_composite(strip, (int(round(bx + x)), int(round(by + dy))))
                    x += sw_
            else:
                frame.alpha_composite(bt, (int(round(bx)), int(round(by))))
            for j in e.get("jaws", []):
                frame.alpha_composite(tex(j["file"]), (int(round(j["x"] + o[0])), int(round(j["y"] + o[1] + bob))))
            continue
        side = [p for p in e["parts"] if p["layer"] == layer]
        wave = len(side) > 5
        cw = max(1.0, float(e["canvas"][0]))
        for p in side:
            ph = p["phase"] * math.pi + (0.0 if layer == "near" else 0.7)
            if wave:
                ph = -p["pivot"][0] / cw * math.tau * 1.5 + (0.0 if layer == "near" else math.pi)
            sw = math.sin(t * gait + ph) if force is None else float(force)
            lift = max(0.0, math.cos(t * gait + ph)) * (9.0 if moving else 0.0) * (0.6 if wave else 1.0)
            if force is not None:
                lift = 0.0
            if fly:
                lift = -bob
            pos = (p["x"] + o[0], p["y"] + o[1] - lift)
            pvt = (p["pivot"][0] + o[0], p["pivot"][1] + o[1] - (lift if fly else 0.0))
            _put(frame, tex(p["file"]), pos, pvt, sw * amp * (0.7 if wave else 1.0))
        if fly:
            for w in e["wings"]:
                if w["layer"] != layer:
                    continue
                wa = math.sin(t * w["speed"] + w["phase"]) * w["flap"] if force is None else float(force) * w["flap"]
                _put(frame, tex(w["file"]), (w["x"] + o[0], w["y"] + o[1] + bob), (w["pivot"][0] + o[0], w["pivot"][1] + o[1] + bob), wa)
    return frame, (e["feet"][0] + o[0], e["feet"][1] + o[1])


def contact(man, path):
    from PIL import ImageFont
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 15)
    except OSError:
        font = ImageFont.load_default()
    cols = [("assembled", 0.0, False, None), ("+max swing", 0.0, True, 1), ("-max swing", 0.0, True, -1),
            ("walk t=0.30", 0.30, True, None), ("walk t=0.85", 0.85, True, None)]
    names = [n for n in man if not n.startswith("_")]
    cell_w, cell_h = 380, 300
    sheet = Image.new("RGBA", (cell_w * len(cols) + 150, cell_h * len(names) + 40), (40, 44, 40, 255))
    d = ImageDraw.Draw(sheet)
    for ci, (lbl, *_r) in enumerate(cols):
        d.text((150 + ci * cell_w + 10, 10), lbl, fill=(255, 255, 255, 255), font=font)
    for ri, n in enumerate(names):
        e = man[n]
        y0 = 40 + ri * cell_h
        d.text((10, y0 + 10), n, fill=(255, 255, 255, 255), font=font)
        d.text((10, y0 + 30), "%dx%d file" % tuple(e["canvas"]), fill=(200, 200, 200, 255), font=font)
        d.text((10, y0 + 50), "%.0f px in game" % e["game_len"], fill=(200, 200, 200, 255), font=font)
        # the critter at its game size next to a 40 px bar (a worker ant)
        fr, ft = rig_frame(e, 0.0, False)
        g = e["scale"] * 1.4
        small = fr.resize((max(1, int(fr.size[0] * g)), max(1, int(fr.size[1] * g))), Image.LANCZOS)
        bg = Image.new("RGBA", (130, 90), (156, 207, 85, 255))
        bg.alpha_composite(small, (int(65 - ft[0] * g), int(75 - ft[1] * g)))
        ImageDraw.Draw(bg).line([(37, 85), (37 + 56, 85)], fill=(0, 0, 0, 255), width=2)
        sheet.alpha_composite(bg, (10, y0 + 80))
        d.text((10, y0 + 172), "game size x1.4", fill=(200, 200, 200, 255), font=font)
        d.text((10, y0 + 190), "bar: 40 px ant", fill=(200, 200, 200, 255), font=font)
        for ci, (lbl, t, moving, force) in enumerate(cols):
            fr, ft = rig_frame(e, t, moving, force)
            s = min((cell_w - 20) / float(fr.size[0]), (cell_h - 20) / float(fr.size[1]), 1.0)
            fr = fr.resize((int(fr.size[0] * s), int(fr.size[1] * s)), Image.LANCZOS)
            bg = Image.new("RGBA", (cell_w - 10, cell_h - 10), (156, 207, 85, 255))
            gy = int(ft[1] * s) + (cell_h - 10 - fr.size[1]) // 2
            ImageDraw.Draw(bg).rectangle([0, gy, cell_w, cell_h], fill=(120, 90, 60, 255))
            bg.alpha_composite(fr, ((cell_w - 10 - fr.size[0]) // 2, (cell_h - 10 - fr.size[1]) // 2))
            sheet.alpha_composite(bg, (150 + ci * cell_w, y0 + 5))
    sheet.convert("RGB").save(path, optimize=True)
    print("contact sheet: %s" % path)


# ------------------------------------------------------------------------------------------------------------------------------- main
def main(argv):
    only = None
    contact_path = None
    debug = None
    i = 0
    while i < len(argv):
        if argv[i] == "--only":
            only = set(argv[i + 1].split(","))
            i += 2
        elif argv[i] == "--contact":
            contact_path = argv[i + 1]
            i += 2
        elif argv[i] == "--debug":
            debug = argv[i + 1]
            os.makedirs(debug, exist_ok=True)
            i += 2
        else:
            raise SystemExit(__doc__)
    man = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            man = json.load(f)
    man["_about"] = ("Critters rigged from art_src/critter_*.png by tools/art/make_critters.py, one entry each in the spider format of "
                     "art_manifest.json (drawn by content/colony/rig_art.gd draw()); files are relative to content/art/. 'wings' (bee, dragonfly): "
                     "pieces beaten about their pivot (flap = radians either way, speed = radians of the beat per second, phase). 'jaws' of the snail "
                     "is its shell, a rigid piece over the rippling foot (open 0). 'feet' is the ground point (the lowest foot); 'game_len' the length "
                     "in game px at scale 1 (a worker ant is about 40); scale = game_len / width. All face right.")
    for name, spec in CRITTERS.items():
        if only and name not in only:
            continue
        spec = dict(spec)
        man[name] = build(name, spec, OUT, debug)
    with open(MANIFEST, "w") as f:
        json.dump(man, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT))
    print("critters/: %d files, %.0f KB" % (len(os.listdir(OUT)), total / 1024.0))
    if contact_path:
        contact(man, contact_path)


if __name__ == "__main__":
    main(sys.argv[1:])
