#!/usr/bin/env python3
"""Build walking rigs for the fauna from the owner's split drawings: a body without legs (art_src/fauna_bodies.png) and two sets of legs per
creature (art_src/fauna_legs_a.png = the darker FAR side, art_src/fauna_legs_b.png = the lighter NEAR side).

The pictures are RGBA with real transparency, so the alpha channel is the cut (dust below alpha 10 dropped, 250-254 counted as opaque; see
creature_cuts.load).  Each creature gets, in content/art/fauna_rig/:
  <name>_body.png              the body (trimmed), outlined a little thicker in its own outline colour (creature_cuts.thicken)
  <name>_far_<i>.png           the far legs, back to front
  <name>_near_<i>.png          the near legs
  <name>_wing_far / _near.png  wings, where the leg drawing carried wings apart from the body (hornet, moth) so they can flap
and an entry in content/art/fauna_rig_manifest.json in the spider format of art_manifest.json (read by content/colony/rig_art.gd):
  canvas, order (far, body, near), parts [{layer, file, x, y, pivot, phase}], wave, body {file, x, y}, feet, width, height, scale
  plus "wings" [{layer, file, x, y, pivot, phase}] when there are wings (not drawn by rig_art yet: a flap is a swing about `pivot`).

How the legs are made:
  * the leg drawings are not aligned with the bodies and carry bits of body (a red ant gaster, a hornet abdomen, moth fur, a whole stag beetle,
    centipede segments).  Every leg, every body bit and every wing gets seed lines (in leg-sheet pixels) and creature_cuts.partition gives each
    pixel to the nearest seed without crossing an outline; the body bits are thrown away, the legs keep a thin rim of their neighbours' outline.
  * the leg set is scaled to the body (SPEC "s": leg-sheet px -> body-sheet px, set from the outline thickness and the overlapping body bits),
    every leg is hung by its top joint (the pivot, the first seed point) on a hip on the body's underside (SPEC "hips", body-sheet px), and is
    stretched a little (0.8x-1.25x) and if need be turned a little (at most 25 degrees) about its pivot so that its foot stands on the common
    ground line just below the body (SPEC "ground", body-sheet y).
  * phases: neighbouring legs of a side step in turn and the far side is opposite to the near side (a tripod for six legs); rig_art switches to a
    wave from tail to head for more than five legs a side (the centipede).
  * scale = game length / body length (nose to tail of the body picture, antennae excluded), game length for a worker ant drawn ~40 px long.

Needs Pillow (and creature_cuts.py next to this file):
  python3 tools/art/make_fauna_rig.py [--only a,b] [--contact PATH] [--debug DIR]
  --contact PATH  verification sheet: every creature assembled, and with its legs swung +-15 degrees in alternating phase, on grey and dark brown
  --debug DIR     per leg set: which pixel went to which leg / body bit / wing, with the seeds and pivots
Does not touch make_art.py, art_manifest.json or the game code.
"""
import json
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import creature_cuts as cc  # noqa: E402  (shared cutting helpers: load, thicken, partition, grow_in, drop_specks ...)

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
ART = os.path.join(ROOT, "src", "mods-unpacked", "Judah-InfDNA", "content", "art")
OUT = os.path.join(ART, "fauna_rig")
MANIFEST = os.path.join(ART, "fauna_rig_manifest.json")
SHEETS = {"body": "fauna_bodies.png", "a": "fauna_legs_a.png", "b": "fauna_legs_b.png"}
WORKER_PX = 40.0
MARGIN = 3
OUTLINE = 2          # extra outline (px at the working size) round every piece, in the piece's own outline colour
RIM = 4              # px of a neighbour's outline a leg keeps where it was cut from it
FIT_SCALE = (0.8, 1.25)
FIT_ROT = 25.0


def L(name, *lines, **kw):
    """A leg (or a body bit / wing): seed lines in leg-sheet px; the first point is the hinge unless pivot= is given."""
    d = {"name": name, "lines": [list(l) for l in lines]}
    d.update(kw)
    return d


# ------------------------------------------------------------------------------------------------------------------------------- specs
# body:  box on fauna_bodies.png (the pieces of the alpha whose centre lies in it), len_px = body length at the working size (nose to tail)
# far / near: sheet a|b, box on it, s (leg px -> body px, "auto": the median that lets the legs reach the ground), legs back to front (the
#             order they are drawn in), drop (body bits to throw away), wings, hips {leg name: x on the underside or (x, y), body-sheet px},
#             inset (how far up from the underside a hip sits), leg (defaults for every leg); per leg optional rot (preferred turn, degrees,
#             clockwise), max_rot, fit_scale, fit=False (a claw: no stretch, turned by rot only), scale (times the set's size)
# ground: y of the ground line in body-sheet px; game: game length (px at scale 1, worker ant ~40)
def P(*pts):
    """Seed points, one line each (a point in every drawn segment of a leg or body bit)."""
    return [[q] for q in pts]


def LP(name, pts, pivot, **kw):
    d = {"name": name, "lines": P(*pts), "pivot": pivot}
    d.update(kw)
    return d


SPEC = {
    # ---- the queen: the light furry legs of sheet b (near) and the same legs darker (sheet b too: the far side; it shows two whole legs and
    #      the claw of a third behind them)
    "queen": {
        "game": 90, "len_px": 360, "ground": 372,
        "body": {"box": (0, 60, 720, 380)},
        "near": {"sheet": "b", "box": (35, 140, 455, 335),
                 "legs": [L("hind", [(232, 212), (183, 168), (150, 215), (110, 280), (55, 325)]),
                          L("mid", [(268, 196), (240, 230), (215, 258), (195, 290), (175, 322)]),
                          L("front", [(330, 192), (350, 165), (372, 152), (392, 200), (405, 250), (420, 325)])],
                 "drop": [L("thorax", [(285, 172), (305, 195)])],
                 "hips": {"hind": (370, 255), "mid": (425, 262), "front": (480, 262)}},
        "far": {"sheet": "b", "box": (470, 160, 840, 325),
                "legs": [L("hind", [(655, 238), (630, 205), (605, 180), (570, 215), (530, 250), (492, 280)]),
                         L("mid", [(785, 222), (795, 250), (812, 290)]),            # only its claw shows: replaced (borrow)
                         L("front", [(683, 228), (700, 200), (718, 180), (745, 220), (765, 255), (788, 300)])],
                "drop": [L("thorax", [(668, 212), (672, 225)])],
                "borrow": {"mid": "near"}, "darken": 0.75,
                "hips": {"hind": (385, 245), "mid": (440, 250), "front": (492, 250)}},
    },
    # ---- stag beetle: the second (cleaner, one piece) body; the near legs come with a whole beetle (thrown away) and the stumps of the far
    #      legs behind them (thrown away); there is no dark far set, so the far side is the near legs, darker
    "stagbeetle": {
        "game": 90, "len_px": 380, "ground": 378,
        "body": {"box": (1200, 90, 1672, 350)},
        "near": {"sheet": "b", "box": (836, 64, 1288, 348), "inset": 9,
                 "legs": [LP("hind", [(932, 261), (906, 295), (888, 311)], (955, 233)),
                          LP("mid", [(1045, 226), (1022, 263), (1004, 295), (986, 314)], (1040, 229)),
                          LP("front", [(1127, 248), (1159, 276), (1189, 306)], (1106, 229))],
                 "drop": [L("beetle", [(900, 215), (951, 191), (1010, 190), (1050, 180)], [(1080, 190), (1119, 190), (1159, 199), (1200, 120)],
                            [(1160, 100), (1230, 110), (1255, 160)], [(1150, 215), (1200, 230), (1260, 200)], [(1101, 206), (1086, 210)],
                            [(978, 226)]),
                          LP("stumps", [(977, 252), (958, 260), (1004, 253), (1056, 248), (1071, 241), (1088, 252)], None)],
                 "hips": {"hind": 1372, "mid": 1442, "front": 1505}},
        "far": {"copy": "near", "darken": 0.7, "inset": 17,
                "hips": {"hind": 1395, "mid": 1465, "front": 1525}},
    },
    # ---- centipede: cream legs; the red ovals over the near legs and the row of segments over the far legs are body (thrown away)
    "centipede": {
        "game": 120, "len_px": 420, "ground": 619,
        "body": {"box": (15, 440, 405, 610)},
        "near": {"sheet": "b", "box": (1280, 176, 1648, 340), "inset": 7, "leg": {"fit_scale": (0.6, 1.4), "max_rot": 12},
                 "legs": [LP("n1", [(1322, 265)], (1323, 257)), LP("n2", [(1360, 268)], (1362, 259)), LP("n3", [(1399, 269)], (1402, 256)),
                          LP("n4", [(1437, 261)], (1440, 250)), LP("n5", [(1474, 272)], (1475, 262)), LP("n6", [(1510, 261)], (1510, 249)),
                          LP("n7", [(1563, 265)], (1563, 258)), LP("n8", [(1614, 254)], (1613, 246))],
                 "drop": [LP("ovals", [(1338, 238), (1371, 238), (1406, 232), (1441, 220), (1472, 237), (1503, 217), (1550, 228), (1573, 221),
                                       (1594, 225)], None)],
                 "hips": {"n1": 52, "n2": 88, "n3": 124, "n4": 160, "n5": 196, "n6": 232, "n7": 266, "n8": 294}},
        "far": {"sheet": "a", "box": (852, 288, 1088, 430), "inset": 13, "leg": {"fit_scale": (0.6, 1.4), "max_rot": 12},
                "legs": [LP("f1", [(884, 361), (871, 374)], (892, 353)), LP("f2", [(917, 352), (911, 365), (901, 382)], (917, 350)),
                         LP("f3", [(938, 371), (935, 388)], (945, 355)), LP("f4", [(967, 372), (965, 390)], (969, 360)),
                         LP("f5", [(992, 374), (989, 388)], (993, 361)), LP("f6", [(1020, 366), (1020, 376), (1018, 393)], (1020, 362)),
                         LP("f7", [(1051, 362), (1051, 375), (1051, 392)], (1051, 359))],
                "drop": [LP("segments", [(894, 342), (916, 331), (944, 327), (969, 332), (994, 335), (1019, 343), (1048, 343), (929, 357)], None)],
                "hips": {"f1": 68, "f2": 107, "f3": 146, "f4": 185, "f5": 224, "f6": 260, "f7": 288}},
    },
    # ---- scorpion: the walking legs and the big claw (a leg that does not reach the ground: it keeps its size and is not turned)
    "scorpion": {
        "game": 110, "len_px": 320, "ground": 648,
        "body": {"box": (420, 375, 735, 615)},
        "near": {"sheet": "b", "box": (52, 440, 432, 652), "inset": 10,
                 "legs": [LP("rear", [(192, 487), (153, 468), (123, 494), (98, 524), (78, 587), (242, 526)], (250, 530)),
                          LP("mid", [(205, 542), (198, 574), (210, 603)], (232, 520)),
                          LP("claw", [(270, 527), (294, 496), (328, 518), (269, 564), (287, 571), (301, 554), (337, 573)], (262, 548), fit=False, scale=1.35, rot=-8)],
                 "hips": {"rear": 570, "mid": 628, "claw": (688, 578)}},
        "far": {"sheet": "a", "box": (1100, 272, 1356, 436), "inset": 16,
                "legs": [LP("rear", [(1222, 308), (1191, 298), (1163, 319), (1140, 351), (1120, 380)], (1228, 322)),
                         LP("mid", [(1196, 326), (1173, 357)], (1220, 334)),
                         LP("front", [(1233, 330), (1245, 342), (1239, 376)], (1236, 327)),
                         LP("claw", [(1251, 325), (1262, 319), (1284, 320), (1303, 325), (1298, 354), (1316, 390)], (1249, 327), fit=False, scale=1.25, rot=-8)],
                "hips": {"rear": 548, "mid": 596, "front": 645, "claw": (698, 570)}},
    },
    # ---- moth: furry legs; both sets carry the flight wings (kept, to flap) and fur of the body (thrown away)
    "moth": {
        "game": 60, "len_px": 300, "ground": 628,
        "body": {"box": (745, 455, 1158, 615)},
        "near": {"sheet": "b", "box": (440, 412, 856, 656), "inset": 9,
                 "legs": [LP("hind", [(547, 551), (518, 581)], (612, 525)),
                          LP("mid", [(702, 554)], (697, 518)),
                          LP("front", [(796, 547), (827, 578), (811, 588), (795, 593)], (772, 518))],
                 "drop": [LP("body", [(746, 524), (606, 571), (587, 600), (632, 535), (656, 539), (647, 559), (672, 569), (675, 527),
                                      (689, 513), (723, 536)], None)],
                 "wings": [LP("wing", [(526, 440), (551, 467), (627, 479), (680, 484), (700, 487)], (708, 488), attach=(1000, 500), flap=0.7, s=0.95)],
                 "hips": {"hind": 965, "mid": 1010, "front": 1052}},
        "far": {"sheet": "a", "box": (1376, 260, 1664, 448), "inset": 15,
                "legs": [LP("hind", [(1438, 376), (1423, 398)], (1462, 346)),
                         LP("mid", [(1526, 346), (1541, 381), (1552, 410)], (1528, 344)),
                         LP("front", [(1594, 373), (1619, 406)], (1582, 346))],
                "drop": [LP("body", [(1613, 329), (1424, 343), (1498, 355), (1552, 344), (1475, 363), (1514, 383), (1498, 375)], None)],
                "wings": [LP("wing", [(1437, 282), (1443, 304), (1483, 328), (1540, 312), (1568, 316)], (1580, 318), attach=(1012, 492), flap=0.7, s=1.15)],
                "hips": {"hind": 980, "mid": 1025, "front": 1062}},
    },
    # ---- hornet: yellow-black legs; both sets carry the pale wings (kept, to flap), the near set also a striped abdomen (thrown away)
    "hornet": {
        "game": 70, "len_px": 300, "ground": 896,
        "body": {"box": (20, 720, 405, 885)},
        "near": {"sheet": "b", "box": (1252, 384, 1640, 664), "inset": 8,
                 "legs": [LP("hind", [(1509, 539), (1496, 517), (1478, 565), (1468, 592)], (1517, 548)),
                          LP("mid", [(1540, 530), (1569, 499), (1555, 552), (1550, 578)], (1530, 548)),
                          LP("front", [(1582, 526), (1597, 547), (1603, 579), (1606, 598)], (1574, 508))],
                 "drop": [LP("body", [(1421, 540), (1390, 600), (1440, 520), (1457, 498), (1477, 521), (1528, 544), (1520, 552)], None)],
                 "wings": [LP("wing", [(1322, 423), (1365, 468), (1450, 470), (1500, 478), (1524, 482)], (1530, 482), attach=(205, 752), flap=0.9, s=0.78)],
                 "hips": {"hind": 178, "mid": 218, "front": 258}},
        "far": {"sheet": "a", "box": (388, 508, 648, 764), "inset": 14,
                "legs": [LP("hind", [(449, 667), (437, 688)], (474, 642)),
                         LP("mid", [(510, 674), (506, 698)], (520, 642)),
                         LP("front", [(598, 632), (601, 656), (603, 689), (609, 709)], (597, 620))],
                "drop": [LP("body", [(569, 641), (561, 676), (562, 706), (550, 631), (527, 636), (585, 640), (501, 645), (488, 652),
                                     (474, 666)], None)],
                "wings": [LP("wing", [(455, 546), (478, 587), (560, 585), (600, 588)], (615, 590), attach=(215, 748), flap=0.9, s=1.05)],
                "hips": {"hind": 192, "mid": 232, "front": 268}},
    },
    # ---- the red ants: both leg sets carry the gaster, the waist and a bit of thorax (thrown away)
    "redant_small": {
        "game": 36, "len_px": 230, "ground": 892,
        "body": {"box": (410, 735, 712, 875)},
        "near": {"sheet": "b", "box": (92, 728, 404, 896), "inset": 7,
                 "legs": [LP("hind", [(173, 827), (159, 848), (137, 870)], (192, 800)),
                          LP("mid", [(274, 822), (282, 846), (297, 868)], (268, 797)),
                          LP("front", [(303, 777), (346, 779), (372, 811)], (296, 792))],
                 "drop": [LP("body", [(154, 807), (120, 840), (200, 770), (235, 802), (264, 778), (284, 776)], None)],
                 "per_leg": {"hind": {"rot": -20}, "front": {"rot": 30}},
                 "hips": {"hind": 535, "mid": 562, "front": 592}},
        "far": {"sheet": "a", "box": (696, 624, 908, 768), "inset": 12,
                "legs": [LP("hind", [(781, 690), (758, 707), (749, 725)], (788, 673)),
                         LP("mid", [(815, 700), (823, 719)], (812, 681)),
                         LP("front", [(831, 667), (855, 672), (868, 701)], (829, 688))],
                "drop": [LP("body", [(736, 685), (720, 700), (760, 660), (789, 680), (806, 660)], None)],
                "per_leg": {"hind": {"rot": -15}, "front": {"rot": 25}},
                "hips": {"hind": 545, "mid": 572, "front": 600}},
    },
    "redant_soldier": {
        "game": 48, "len_px": 260, "ground": 893,
        "body": {"box": (740, 710, 1125, 880)},
        "near": {"sheet": "b", "box": (472, 708, 876, 896), "inset": 8,
                 "legs": [LP("hind", [(685, 770), (678, 799), (631, 802), (610, 833), (578, 867)], (703, 795)),
                          LP("mid", [(713, 816), (724, 841)], (707, 790)),
                          LP("front", [(737, 763), (763, 772), (800, 766), (834, 803)], (716, 790))],
                 "drop": [LP("body", [(551, 796), (520, 820), (600, 760), (617, 782)], None)],
                 "per_leg": {"hind": {"rot": -20}, "front": {"rot": 30}},
                 "hips": {"hind": 878, "mid": 912, "front": 948}},
        "far": {"sheet": "a", "box": (932, 600, 1228, 768), "inset": 13,
                "legs": [LP("hind", [(1044, 668), (1036, 684), (1013, 694), (1000, 717)], (1058, 686)),
                         LP("mid", [(1112, 677), (1151, 697), (1169, 719)], (1100, 688)),
                         LP("front", [(1129, 644), (1171, 663), (1182, 693)], (1108, 683))],
                "drop": [LP("body", [(985, 663), (960, 690), (1010, 640), (1083, 647), (1064, 672), (1094, 674), (1081, 680)], None)],
                "per_leg": {"hind": {"rot": -15}, "front": {"rot": 25}},
                "hips": {"hind": 890, "mid": 924, "front": 958}},
    },
    "redant_major": {
        "game": 80, "len_px": 340, "ground": 900,
        "body": {"box": (1150, 645, 1670, 890)},
        "near": {"sheet": "b", "box": (936, 676, 1432, 908), "inset": 10,
                 "legs": [LP("hind", [(1123, 806), (1099, 838), (1063, 876)], (1222, 768)),
                          LP("mid", [(1244, 748), (1255, 763), (1246, 800), (1262, 834), (1290, 872)], (1236, 742)),
                          LP("front", [(1294, 750), (1355, 769), (1386, 815)], (1262, 782))],
                 "drop": [LP("body", [(1050, 773), (1000, 820), (1100, 730), (1161, 785), (1269, 735)], None)],
                 "per_leg": {"hind": {"rot": -15}, "front": {"rot": 25}},
                 "hips": {"hind": 1385, "mid": 1422, "front": 1458}},
        "far": {"sheet": "a", "box": (1248, 552, 1648, 768), "inset": 17,
                "legs": [LP("hind", [(1416, 633), (1401, 612), (1375, 657), (1355, 682)], (1440, 655)),
                         LP("mid", [(1465, 647), (1477, 620), (1494, 671), (1505, 707)], (1460, 662)),
                         LP("front", [(1518, 645), (1567, 659), (1587, 684)], (1502, 658))],
                "drop": [LP("body", [(1334, 616), (1290, 650), (1370, 600), (1442, 635)], None)],
                "per_leg": {"hind": {"rot": -10}, "front": {"rot": 20}},
                "hips": {"hind": 1398, "mid": 1434, "front": 1470}},
    },
}


def load_specs():
    pass


# ---------------------------------------------------------------------------------------------------------------------------- helpers

_SHEET_CACHE = {}


def sheet(key):
    if key not in _SHEET_CACHE:
        _SHEET_CACHE[key] = cc.load(SHEETS[key])
    return _SHEET_CACHE[key]


def crop_items(im, box, min_px=60):
    """The crop of a sheet holding only the islands whose centre lies inside box (neighbours' bits cut away)."""
    x0, y0, x1, y1 = box
    pad = 40
    bx = (max(0, x0 - pad), max(0, y0 - pad), min(im.size[0], x1 + pad), min(im.size[1], y1 + pad))
    c = im.crop(bx)
    a = c.getchannel("A")
    lab, sizes = cc.labels_of(a, 24)
    w = c.size[0]
    acc = {}
    for i, v in enumerate(lab):
        if v >= 0:
            s = acc.setdefault(v, [0, 0, 0])
            s[0] += 1
            s[1] += i % w
            s[2] += i // w
    keep = [v for v, (n, sx, sy) in acc.items()
            if n >= min_px and x0 <= bx[0] + sx / n < x1 and y0 <= bx[1] + sy / n < y1]
    m = cc.dilate(cc.mask_from(lab, c.size, keep), 2)
    c.putalpha(ImageChops.multiply(a, m))
    bb = cc.bbox_of(c)
    pad = 10                                   # room for the extra outline (thicken does not grow the canvas)
    out = Image.new("RGBA", (bb[2] - bb[0] + 2 * pad, bb[3] - bb[1] + 2 * pad), (0, 0, 0, 0))
    out.paste(c.crop(bb), (pad, pad))
    return out, (bx[0] + bb[0] - pad, bx[1] + bb[1] - pad)


def resize(im, k):
    if abs(k - 1.0) < 1e-6:
        return im.copy()
    return im.resize((max(1, int(round(im.size[0] * k))), max(1, int(round(im.size[1] * k)))), Image.LANCZOS)


def affine(img, pivot, scale, deg):
    """Scale img by `scale` and turn it by `deg` (clockwise on screen) about `pivot`; returns (image, pivot in it). Premultiplied, no fringe."""
    if abs(scale - 1.0) < 1e-4 and abs(deg) < 1e-3:
        return img, pivot
    th = math.radians(deg)
    c, s = math.cos(th) * scale, math.sin(th) * scale
    w, h = img.size
    px, py = pivot
    pts = []
    for (x, y) in ((0, 0), (w, 0), (0, h), (w, h)):
        dx, dy = x - px, y - py
        pts.append((c * dx - s * dy, s * dx + c * dy))
    minx = math.floor(min(p[0] for p in pts)) - 2
    miny = math.floor(min(p[1] for p in pts)) - 2
    maxx = math.ceil(max(p[0] for p in pts)) + 2
    maxy = math.ceil(max(p[1] for p in pts)) + 2
    W, H = maxx - minx, maxy - miny
    # output (u, v) -> forward coords (u + minx, v + miny) -> input = R^-1 S^-1 (.) + pivot
    det = c * c + s * s
    ia, ib = c / det, s / det
    # inverse of [[c, -s], [s, c]] is [[c, s], [-s, c]] / det
    coeffs = (ia, ib, ia * minx + ib * miny + px,
              -ib, ia, -ib * minx + ia * miny + py)
    pre = img.convert("RGBa")
    out = pre.transform((W, H), Image.AFFINE, coeffs, resample=Image.BICUBIC).convert("RGBA")
    return out, (-minx, -miny)


def snap_inside(img, pv, inset=2.0, thr=160):
    """A hinge must lie on the piece: a pivot that fell outside it (a hand-placed point) moves to the nearest solid pixel, then `inset` px further in."""
    a = img.getchannel("A")
    w, h = img.size
    px = a.load()
    x0, y0 = int(round(pv[0])), int(round(pv[1]))
    if 0 <= x0 < w and 0 <= y0 < h and px[x0, y0] >= thr:
        return pv
    best = None
    for y in range(h):
        for x in range(w):
            if px[x, y] >= thr:
                d2 = (x - pv[0]) ** 2 + (y - pv[1]) ** 2
                if best is None or d2 < best[0]:
                    best = (d2, x, y)
    if best is None:
        return pv
    d = math.sqrt(best[0]) or 1.0
    return (best[1] + (best[1] - pv[0]) / d * inset, best[2] + (best[2] - pv[1]) / d * inset)


def foot_of(img, thr=128):
    """Lowest point of a piece: (x, y) = middle of the opaque pixels of its bottom 3 rows, bottom edge."""
    a = img.getchannel("A").point(lambda v: 255 if v >= thr else 0)
    bb = a.getbbox()
    if bb is None:
        return (img.size[0] / 2.0, float(img.size[1]))
    y1 = bb[3]
    px = a.load()
    xs = [x for y in range(max(0, y1 - 3), y1) for x in range(img.size[0]) if px[x, y]]
    return (sum(xs) / float(len(xs)), float(y1))


def fit_leg(img, pivot, hip, ground, spec):
    """Stretch (FIT_SCALE) and turn (FIT_ROT) a leg about its pivot so that, hung on `hip`, its foot stands on `ground`."""
    if spec.get("fit") is False:
        if spec.get("rot"):
            out, pv = affine(img, pivot, 1.0, float(spec["rot"]))
            return out, pv, 1.0, float(spec["rot"])
        return img, pivot, 1.0, 0.0
    need = ground - hip[1]
    fx, fy = foot_of(img)
    vx, vy = fx - pivot[0], fy - pivot[1]
    lo, hi = spec.get("fit_scale", FIT_SCALE)
    best = None
    # the turn: the smallest one away from the preferred turn `rot` (0 = as drawn) that lets the leg reach the ground within the stretch
    pref = float(spec.get("rot", 0.0))
    maxr = spec.get("max_rot", FIT_ROT)
    cands = sorted([pref + i * 0.5 for i in range(-int(maxr * 2), int(maxr * 2) + 1)], key=lambda d: abs(d - pref))
    for deg in cands:
        th = math.radians(deg)
        ry = vx * math.sin(th) + vy * math.cos(th)
        if ry <= 1:
            continue
        a = need / ry
        ac = min(hi, max(lo, a))
        err = abs(ac * ry - need)
        if best is None or err < best[0] - 0.5:
            best = (err, ac, deg)
        if err < 0.5:
            break
    err, a, deg = best
    out, pv = affine(img, pivot, a, deg)
    # the lowest pixel may have changed with the turn: one correction of the stretch
    for _ in range(2):
        fx2, fy2 = foot_of(out)
        got = fy2 - pv[1]
        if got > 1 and abs(got - need) > 0.75:
            a2 = min(hi, max(lo, a * need / got))
            if abs(a2 - a) < 1e-3:
                break
            a = a2
            out, pv = affine(img, pivot, a, deg)
    return out, pv, a, deg


def body_span(img):
    """Nose-to-tail span of a body picture: columns at least ~1/8 of the height tall (antennae, spines and thin tips do not count)."""
    a = img.getchannel("A").point(lambda v: 255 if v > 128 else 0)
    w, h = a.size
    px = a.load()
    mincol = max(4, h // 8)
    cols = [x for x in range(w) if sum(1 for y in range(h) if px[x, y]) >= mincol]
    if not cols:
        return 0, w
    return cols[0], cols[-1] + 1


# ------------------------------------------------------------------------------------------------------------------------------- build

def cut_set(name, side, st, k, debug=None):
    """Cut one leg set. Returns ([leg dicts {name, img, pivot}], [wing dicts {name, img, pivot}]) at the working size (body px * k)."""
    src = sheet(st["sheet"])
    crop, org = crop_items(src, st["box"])
    ks = st["s"] * k
    im = cc.thicken(resize(crop, ks), OUTLINE)
    parts = []
    for kind in ("legs", "drop", "wings"):
        for p in st.get(kind, []):
            if kind == "drop":
                # every seed of a body bit is a bit of its own: the partition keeps only one connected piece per part, and the bits of body
                # between the legs are separate islands
                for i, line in enumerate(p["lines"]):
                    parts.append((kind, {"name": "%s%d" % (p["name"], i), "lines": [line]}))
            else:
                parts.append((kind, p))

    def tr(pt):
        return ((pt[0] - org[0]) * ks, (pt[1] - org[1]) * ks)
    seeds = [{"name": p["name"], "lines": [[tr(q) for q in line] for line in p["lines"]]} for kind, p in parts]
    lab, ink = cc.partition(im, seeds, 1.0)
    a = im.getchannel("A")
    # the rim a leg keeps is taken from its neighbouring legs' outline only, never from a body bit that is thrown away (that outline
    # would show as a dark smudge where the leg lies over the body)
    drop_ids = set(i for i, (kind, p) in enumerate(parts) if kind == "drop")
    not_drop = lab.point(lambda v: 0 if v in drop_ids else 255)
    ink_ok = ImageChops.multiply(ink, not_drop)
    legs, wings = [], []
    for li, (kind, p) in enumerate(parts):
        if kind == "drop":
            continue
        m = lab.point(lambda v, li=li: 255 if v == li else 0)
        if m.getbbox() is None:
            print("  !! %s %s %s got no pixels" % (name, side, p["name"]))
            continue
        mask = cc.grow_in(m, ink_ok, p.get("rim", RIM))
        piece = im.copy()
        piece.putalpha(ImageChops.multiply(a, mask))
        piece = cc.drop_specks(piece, 60, 0.04)
        bb = cc.bbox_of(piece)
        crop_p = piece.crop(bb)
        pv = tr(p.get("pivot", p["lines"][0][0]))
        pv = (pv[0] - bb[0], pv[1] - bb[1])
        # a piece with a size of its own: a wing ("s": leg-sheet px -> body-sheet px) or a claw ("scale": times the set's size)
        mult = (p["s"] / st["s"]) if "s" in p else p.get("scale", 1.0)
        if abs(mult - 1.0) > 1e-3:
            crop_p, pv = affine(crop_p, pv, mult, 0.0)
        pv = snap_inside(crop_p, pv)
        spec = dict(st.get("leg", {}))
        spec.update(p)
        spec.update(st.get("per_leg", {}).get(p["name"], {}))
        d = {"name": p["name"], "img": crop_p, "pivot": pv, "spec": spec, "at": (bb[0], bb[1])}
        (wings if kind == "wings" else legs).append(d)
    if debug:
        pivots = [tr(p["pivot"]) if p.get("pivot") else tr(p["lines"][0][0]) for kind, p in parts]
        debug_set(name, side, im, lab, parts, seeds, debug, pivots)
    return legs, wings


def debug_set(name, side, im, lab, parts, seeds, ddir, pivots):
    import colorsys
    w, h = im.size
    bg = Image.new("RGBA", im.size, (150, 165, 150, 255))
    bg.alpha_composite(im)
    over = Image.new("RGBA", im.size, (0, 0, 0, 0))
    op = over.load()
    lp = lab.load()
    ap = im.getchannel("A").load()
    cols = []
    for i, (kind, p) in enumerate(parts):
        if kind == "drop":
            cols.append((60, 60, 60))
        else:
            r, g, b = colorsys.hsv_to_rgb((i * 0.161) % 1.0, 0.9, 1.0)
            cols.append((int(r * 255), int(g * 255), int(b * 255)))
    for y in range(h):
        for x in range(w):
            v = lp[x, y]
            if v != 255 and ap[x, y] > 100:
                op[x, y] = cols[v] + (110,)
    bg.alpha_composite(over)
    z = max(2, int(round(700.0 / max(w, h))))
    bg = bg.resize((w * z, h * z), Image.NEAREST)
    d = ImageDraw.Draw(bg)
    for i, sd in enumerate(seeds):
        for line in sd["lines"]:
            pts = [(x * z, y * z) for x, y in line]
            if len(pts) > 1:
                d.line(pts, fill=cols[i] + (255,), width=2)
            for q in pts:
                d.ellipse([q[0] - 2, q[1] - 2, q[0] + 2, q[1] + 2], fill=(255, 255, 255, 255))
        x, y = pivots[i]
        d.ellipse([x * z - 5, y * z - 5, x * z + 5, y * z + 5], outline=(255, 255, 0, 255), width=2)
        d.text((x * z + 6, y * z - 12), sd["name"], fill=(255, 255, 255, 255))
    bg.convert("RGB").save(os.path.join(ddir, "set_%s_%s.png" % (name, side)))


def underside(img, x, thr=128):
    """Lowest opaque pixel of column x of a picture (None when the column is empty)."""
    a = img.getchannel("A")
    x = int(round(min(max(x, 0), img.size[0] - 1)))
    col = a.crop((x, 0, x + 1, img.size[1])).load()
    for y in range(img.size[1] - 1, -1, -1):
        if col[0, y] >= thr:
            return y
    return None


def darken(img, f):
    r, g, b, a = img.split()
    rgb = Image.merge("RGB", (r, g, b)).point(lambda v: int(v * f))
    out = rgb.convert("RGBA")
    out.putalpha(a)
    return out


def build_one(name, sp, debug=None):
    bsrc = sheet("body")
    bcrop, borg = crop_items(bsrc, sp["body"]["box"])
    x0, x1 = body_span(bcrop)
    k = min(1.0, sp["len_px"] / float(x1 - x0))
    body = cc.thicken(resize(bcrop, k), OUTLINE)

    def B(pt):            # body-sheet px -> working px (body picture's own frame)
        return ((pt[0] - borg[0]) * k, (pt[1] - borg[1]) * k)
    ground = B((0, sp["ground"]))[1]

    def hip_of(st, legname):
        """A hip in working px: (x, y) given in body-sheet px, or only x: then on the body's underside, `inset` body-sheet px up."""
        h = st["hips"][legname]
        if isinstance(h, (int, float)):
            hx = B((h, 0))[0]
            u = underside(body, hx)
            return (hx, (u if u is not None else ground) - st.get("inset", 10) * k)
        return B(h)
    placed = {"far": [], "near": []}
    wings_out = []
    cut_cache = {}
    for side in ("near", "far"):
        st = sp.get(side)
        if not st:
            continue
        if st.get("copy"):
            # no drawing of this side: the other side's legs, darker, on this side's hips
            legs = [dict(lg, img=darken(lg["img"], st.get("darken", 0.72))) for lg in cut_cache[st["copy"]][0]]
            legs = [dict(lg, spec=dict(lg["spec"], **st.get("per_leg", {}).get(lg["name"], {}))) for lg in legs]
            wings = []
        else:
            if st.get("s", "auto") == "auto":
                # the set scale that lets the legs reach the ground from their hips without stretching (median over the legs)
                legs, wings = cut_set(name, side, dict(st, s=1.0), k, None)
                ratios = []
                for lg in legs:
                    if lg["spec"].get("fit") is False:
                        continue
                    hip = hip_of(st, lg["name"])
                    fx, fy = foot_of(lg["img"])
                    th = math.radians(float(lg["spec"].get("rot", 0.0)))
                    ext = (fx - lg["pivot"][0]) * math.sin(th) + (fy - lg["pivot"][1]) * math.cos(th)
                    if ext > 2:
                        ratios.append((ground - hip[1]) / ext)
                ratios.sort()
                sv = ratios[len(ratios) // 2] if ratios else 1.0
                sv = min(2.0, max(0.3, sv * st.get("s_bias", 1.0)))
                print("  %s %s: set scale %.3f (per leg %s)" % (name, side, sv, ", ".join("%.2f" % r for r in ratios)))
                st = dict(st, s=sv)
            legs, wings = cut_set(name, side, st, k, debug)
            cut_cache[side] = (legs, wings)
            # a leg this side's drawing shows badly (only a claw peeking out) is borrowed from the other side, darker
            for lname, other in st.get("borrow", {}).items():
                src_leg = [lg for lg in cut_cache[other][0] if lg["name"] == lname][0]
                legs = [lg for lg in legs if lg["name"] != lname] + [dict(src_leg, img=darken(src_leg["img"], st.get("darken", 0.72)))]
        for lg in legs:
            hip = hip_of(st, lg["name"])
            img, pv, a, deg = fit_leg(lg["img"], lg["pivot"], hip, ground, lg["spec"])
            placed[side].append({"name": lg["name"], "img": img, "x": hip[0] - pv[0], "y": hip[1] - pv[1], "pivot": hip,
                                 "fit": (round(a, 3), deg)})
        for wg in wings:
            att = B(wg["spec"]["attach"])
            img, pv = wg["img"], wg["pivot"]
            if wg["spec"].get("scale", 1.0) != 1.0 or wg["spec"].get("rot", 0.0):
                img, pv = affine(img, pv, wg["spec"].get("scale", 1.0), wg["spec"].get("rot", 0.0))
            wings_out.append({"layer": side, "name": wg["name"], "img": img, "x": att[0] - pv[0], "y": att[1] - pv[1], "pivot": att,
                              "flap": wg["spec"].get("flap", 0.6)})
    # the legs of a side are listed (and drawn) in the order of the spec
    for side in placed:
        names = [lg["name"] for lg in (sp[side].get("legs") or sp[sp[side]["copy"]]["legs"])] if sp.get(side) else []
        placed[side].sort(key=lambda p: names.index(p["name"]) if p["name"] in names else 99)
    # the canvas: everything shifted so the union starts at MARGIN
    boxes = [(0, 0, body.size[0], body.size[1])]
    for side in placed:
        for p in placed[side]:
            boxes.append((p["x"], p["y"], p["x"] + p["img"].size[0], p["y"] + p["img"].size[1]))
    for wg in wings_out:
        boxes.append((wg["x"], wg["y"], wg["x"] + wg["img"].size[0], wg["y"] + wg["img"].size[1]))
    ux0 = min(b[0] for b in boxes)
    uy0 = min(b[1] for b in boxes)
    ux1 = max(b[2] for b in boxes)
    uy1 = max(b[3] for b in boxes)
    ox, oy = MARGIN - math.floor(ux0), MARGIN - math.floor(uy0)
    canvas = (int(math.ceil(ux1 + ox)) + MARGIN, int(math.ceil(uy1 + oy)) + MARGIN)
    os.makedirs(OUT, exist_ok=True)
    entry = {"canvas": list(canvas), "order": ["far", "body", "near"], "parts": [], "wave": False}
    files = {}
    for side in ("far", "near"):
        lst = placed[side]
        order_x = sorted(range(len(lst)), key=lambda i: lst[i]["pivot"][0])
        phase = {i: (rank + (1 if side == "far" else 0)) % 2 for rank, i in enumerate(order_x)}
        for i, p in enumerate(lst):
            fn = "%s_%s_%d.png" % (name, side, i)
            files[fn] = p["img"]
            entry["parts"].append({"layer": side, "file": fn, "x": int(round(p["x"] + ox)), "y": int(round(p["y"] + oy)),
                                   "pivot": [round(p["pivot"][0] + ox, 1), round(p["pivot"][1] + oy, 1)], "phase": phase[i],
                                   "leg": p["name"]})
    bfn = name + "_body.png"
    files[bfn] = body
    entry["body"] = {"file": bfn, "x": ox, "y": oy}
    if wings_out:
        entry["wings"] = []
        for wg in wings_out:
            fn = "%s_wing_%s.png" % (name, wg["layer"] if sum(1 for w in wings_out if w["layer"] == wg["layer"]) == 1 else wg["name"])
            files[fn] = wg["img"]
            entry["wings"].append({"layer": wg["layer"], "file": fn, "x": int(round(wg["x"] + ox)), "y": int(round(wg["y"] + oy)),
                                   "pivot": [round(wg["pivot"][0] + ox, 1), round(wg["pivot"][1] + oy, 1)],
                                   "phase": 0 if wg["layer"] == "near" else 1, "flap": wg["flap"]})
    bx0, bx1 = body_span(body)
    blen = float(bx1 - bx0)
    entry["feet"] = [round(ox + (bx0 + bx1) / 2.0, 1), round(ground + oy, 1)]
    entry["width"] = float(canvas[0] - 2 * MARGIN)
    entry["height"] = float(canvas[1] - 2 * MARGIN)
    entry["length_px"] = blen
    entry["game_len"] = float(sp["game"])
    entry["scale"] = round(sp["game"] / blen, 5)
    if sp.get("note"):
        entry["note"] = sp["note"]
    for fn, img in files.items():
        img.save(os.path.join(OUT, fn), optimize=True)
    fits = ", ".join("%s:%s x%.2f %+.0f" % (s[0], p["name"], p["fit"][0], p["fit"][1]) for s in ("far", "near") for p in placed[s])
    print("%-15s canvas %s  body %dx%d k=%.3f  len %d -> game %d (scale %.4f)\n    %s" % (
        name, canvas, body.size[0], body.size[1], k, blen, sp["game"], entry["scale"], fits))
    return entry


def build(only=None, contact=None, debug=None):
    load_specs()
    if debug:
        os.makedirs(debug, exist_ok=True)
    manifest = {"_about": ABOUT, "worker_ref_px": WORKER_PX}
    if only and os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            manifest.update({k2: v for k2, v in json.load(f).items() if not k2.startswith("_") and k2 != "worker_ref_px"})
    elif os.path.isdir(OUT):
        for fn in os.listdir(OUT):
            if fn.endswith(".png"):
                os.remove(os.path.join(OUT, fn))
    for name, sp in SPEC.items():
        if only and name not in only:
            continue
        manifest[name] = build_one(name, sp, debug)
    order = list(SPEC)
    keys = ["_about", "worker_ref_px"] + [n for n in order if n in manifest]
    manifest = {k2: manifest[k2] for k2 in keys}
    with open(MANIFEST, "w") as f:
        json.dump(manifest, f, indent=1)
    total = sum(os.path.getsize(os.path.join(OUT, fn)) for fn in os.listdir(OUT))
    print("%d rigs, %d files, %.2f MB in %s" % (len(keys) - 2, len(os.listdir(OUT)), total / 1048576.0, OUT))
    if contact:
        make_contact(manifest, contact)


ABOUT = ("Walking rigs for the fauna, cut by tools/art/make_fauna_rig.py from art_src/fauna_bodies.png (bodies without legs) and "
         "fauna_legs_a.png / fauna_legs_b.png (far and near leg sets). Same format as the spider in art_manifest.json, read the same way as "
         "content/colony/rig_art.gd does: draw the layers in 'order'; every part at (x, y) of the canvas, swung about 'pivot' (canvas px) in its "
         "'phase' (0/1; more than five legs a side = a wave from tail to head, by pivot x); 'body' at (x, y); 'feet' = the canvas point that stands "
         "on the world position (middle of the body, on the ground line under the feet); the pictures face RIGHT. 'scale' = game_len / length_px "
         "(length_px = the body's nose-to-tail span in canvas px, antennae excluded; game_len for a worker ant drawn about 40 px long). "
         "'width'/'height' = size of the whole drawing (legs and antennae included). 'leg' names the leg (hind / mid / front ...). "
         "'wings' (hornet, moth): the flight wings, drawn behind the body ('far') or in front of it ('near'), flapped about 'pivot' "
         "(suggested amplitude 'flap' radians, the far wing in the opposite phase); rig_art.gd does not draw them yet. "
         "The single-picture fallbacks are in fauna/ (fauna_manifest.json).")


# ----------------------------------------------------------------------------------------------------------------------------- contact

def _checker(size, a=(150, 150, 150), b=(122, 122, 122), cell=12):
    im = Image.new("RGB", size, a)
    d = ImageDraw.Draw(im)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                d.rectangle((x, y, x + cell - 1, y + cell - 1), fill=b)
    return im


def render(entry, swing=0.0, flip_phase=False, show_pivots=False, wings=True, lift=0.0):
    """The rig drawn like rig_art.gd does (no bob): legs swung by +-swing degrees by phase (wave legs by pivot x)."""
    cw, ch = entry["canvas"]
    pad = 40
    im = Image.new("RGBA", (cw + 2 * pad, ch + 2 * pad), (0, 0, 0, 0))

    def put(fn, x, y, pivot=None, deg=0.0):
        img = Image.open(os.path.join(OUT, fn)).convert("RGBA")
        if pivot is not None and abs(deg) > 1e-3:
            rimg, pv = affine(img, (pivot[0] - x, pivot[1] - y), 1.0, deg)
            im.alpha_composite(rimg, (int(round(pivot[0] - pv[0])) + pad, int(round(pivot[1] - pv[1])) + pad))
        else:
            im.alpha_composite(img, (int(x) + pad, int(y) + pad))
    n_side = {}
    for p in entry["parts"]:
        n_side[p["layer"]] = n_side.get(p["layer"], 0) + 1

    def ang(p):
        if n_side.get(p["layer"], 0) > 5:
            ph = -p["pivot"][0] / float(cw) * math.tau * 1.5 + (0.0 if p["layer"] == "near" else math.pi)
            return swing * math.sin(ph + (math.pi if flip_phase else 0.0))
        s = 1.0 if (p["phase"] == 0) != flip_phase else -1.0
        return swing * s
    if wings:
        for wg in entry.get("wings", []):
            if wg["layer"] == "far":
                put(wg["file"], wg["x"], wg["y"], wg["pivot"], -swing * 1.5 if swing else 0.0)
    for layer in entry["order"]:
        if layer == "body":
            put(entry["body"]["file"], entry["body"]["x"], entry["body"]["y"])
        else:
            for p in entry["parts"]:
                if p["layer"] == layer:
                    put(p["file"], p["x"], p["y"], p["pivot"], ang(p))
    if wings:
        for wg in entry.get("wings", []):
            if wg["layer"] == "near":
                put(wg["file"], wg["x"], wg["y"], wg["pivot"], swing * 1.5 if swing else 0.0)
    if show_pivots:
        d = ImageDraw.Draw(im)
        for p in entry["parts"]:
            x, y = p["pivot"][0] + pad, p["pivot"][1] + pad
            col = (0, 200, 255, 255) if p["layer"] == "near" else (255, 120, 0, 255)
            d.ellipse([x - 3, y - 3, x + 3, y + 3], outline=col, width=2)
        for wg in entry.get("wings", []):
            x, y = wg["pivot"][0] + pad, wg["pivot"][1] + pad
            d.rectangle([x - 3, y - 3, x + 3, y + 3], outline=(255, 0, 255, 255), width=2)
        fx, fy = entry["feet"][0] + pad, entry["feet"][1] + pad
        d.line([(pad, fy), (cw + pad, fy)], fill=(255, 255, 0, 160), width=1)
        d.ellipse([fx - 4, fy - 4, fx + 4, fy + 4], fill=(255, 255, 0, 255), outline=(255, 0, 0, 255))
    return im


def make_contact(manifest, path, cell_h=230):
    f = ImageFont.load_default()
    names = [n for n in manifest if not n.startswith("_") and n != "worker_ref_px"]
    cols = 4
    cw = 300
    rows = []
    for n in names:
        e = manifest[n]
        views = [render(e, 0.0, show_pivots=True), render(e, 0.0), render(e, 15.0), render(e, 15.0, flip_phase=True)]
        rows.append((n, e, views))
    W = cols * cw * 2 + 10
    H = len(rows) * (cell_h + 20) + 10
    sheet_im = Image.new("RGB", (W, H), (36, 36, 36))
    d = ImageDraw.Draw(sheet_im)
    y = 6
    titles = ["pivots, feet, ground", "assembled", "legs +-15 deg", "other phase"]
    for (n, e, views) in rows:
        d.text((6, y), "%s  canvas %dx%d  game %d px (scale %.3f)  legs far %d / near %d%s" % (
            n, e["canvas"][0], e["canvas"][1], e["game_len"], e["scale"], sum(1 for p in e["parts"] if p["layer"] == "far"),
            sum(1 for p in e["parts"] if p["layer"] == "near"), "  wings %d" % len(e["wings"]) if e.get("wings") else ""),
            fill=(255, 255, 255), font=f)
        for vi, v in enumerate(views):
            for bi, bg in enumerate(("check", (66, 44, 30))):
                x = (vi * 2 + bi) * cw + 6
                cell = _checker((cw - 4, cell_h)) if bg == "check" else Image.new("RGB", (cw - 4, cell_h), bg)
                bb = v.getbbox() or (0, 0, 1, 1)
                vv = v.crop(bb)
                sc = min((cw - 12) / float(vv.size[0]), (cell_h - 16) / float(vv.size[1]), 1.0)
                vv = vv.resize((max(1, int(vv.size[0] * sc)), max(1, int(vv.size[1] * sc))), Image.LANCZOS)
                c = cell.convert("RGBA")
                c.alpha_composite(vv, ((cw - 4 - vv.size[0]) // 2, (cell_h - vv.size[1]) // 2 + 6))
                cd = ImageDraw.Draw(c)
                if bi == 0:
                    cd.text((4, 2), titles[vi], fill=(255, 255, 255, 255), font=f)
                sheet_im.paste(c.convert("RGB"), (x, y + 14))
        y += cell_h + 20
    sheet_im.save(path)
    print("contact sheet:", path, sheet_im.size)


def main(argv):
    only = None
    contact = None
    debug = None
    args = list(argv[1:])
    while args:
        a = args.pop(0)
        if a == "--only":
            only = set(args.pop(0).split(","))
        elif a == "--contact":
            contact = args.pop(0)
        elif a == "--debug":
            debug = args.pop(0)
    build(only, contact, debug)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
