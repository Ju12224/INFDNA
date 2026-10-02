#!/usr/bin/env python3
"""Look inside Brotato's .pck (Godot 3.x pack file) without Godot, and pull out the pictures a mod can use.

Run this on the computer that has Brotato. Python 3.6+ only, no extra packages.

  python list_brotato_pck.py Brotato.pck                      # writes brotato_files.txt (every path in the pack) and prints a summary
  python list_brotato_pck.py Brotato.pck --grep fungus        # print the paths containing "fungus" (case-insensitive)
  python list_brotato_pck.py Brotato.pck --images leaf,plant,fruit,mushroom,aphid,seed --out picks.zip
                                                              # export every image whose path contains one of those words as PNG/WebP in a zip
  python list_brotato_pck.py Brotato.pck --sounds                  # list the sound files

Where is Brotato.pck?  Steam: right-click Brotato > Manage > Browse local files; the file is next to Brotato.exe.

What to send back: brotato_files.txt (a text file, small) and, if you like, the zip from --images. The files are only read, never changed.
"""
import argparse, io, os, re, struct, sys, zipfile

MAGIC = 0x43504447  # "GDPC"


def read_index(f):
    f.seek(0)
    head = f.read(4)
    base = 0
    if struct.unpack("<I", head)[0] != MAGIC:
        # the pack may be appended to an .exe: the last 12 bytes say where it starts
        f.seek(-12, 2)
        tail = f.read(12)
        magic, = struct.unpack("<I", tail[8:12])
        if magic != MAGIC:
            raise SystemExit("This does not look like a Godot .pck file.")
        size, = struct.unpack("<Q", tail[:8])
        f.seek(0, 2)
        base = f.tell() - 12 - size
        f.seek(base)
        f.read(4)
    version, vmaj, vmin, vrev = struct.unpack("<4I", f.read(16))
    if version != 1:
        raise SystemExit("Pack format version %d: this script reads the Godot 3 format (version 1)." % version)
    f.read(16 * 4)  # reserved
    count, = struct.unpack("<I", f.read(4))
    files = []
    for _ in range(count):
        plen, = struct.unpack("<I", f.read(4))
        path = f.read(plen).split(b"\0")[0].decode("utf-8", "replace")
        offset, size = struct.unpack("<QQ", f.read(16))
        f.read(16)  # md5
        files.append((path, base + offset, size))
    return (vmaj, vmin, vrev), files


def read_file(f, entry):
    f.seek(entry[1])
    return f.read(entry[2])


def stex_to_image(data):
    """Godot 3 .stex: a small header, then a PNG or WebP (lossless/lossy) or raw data. Returns (ext, bytes) or None."""
    for sig, ext in ((b"\x89PNG\r\n\x1a\n", "png"), (b"RIFF", "webp")):
        i = data.find(sig, 0, 96)
        if i >= 0:
            return ext, data[i:]
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("pck")
    ap.add_argument("--grep", help="print paths containing this text (case-insensitive)")
    ap.add_argument("--images", help="comma-separated words; export images whose path contains any of them")
    ap.add_argument("--sounds", action="store_true", help="list .wav/.ogg/.mp3 files")
    ap.add_argument("--out", default="brotato_picks.zip", help="zip written by --images")
    ap.add_argument("--list-out", default="brotato_files.txt")
    a = ap.parse_args()
    with open(a.pck, "rb") as f:
        engine, files = read_index(f)
        paths = sorted(p for p, _, _ in files)
        by_path = {p: e for e in files for p in [e[0]]}
        if a.grep:
            for p in paths:
                if a.grep.lower() in p.lower():
                    print(p)
        elif a.sounds:
            for p in paths:
                if re.search(r"\.(wav|ogg|mp3)(\.import)?$", p) and not p.startswith("res://.import/"):
                    print(p)
        elif a.images:
            words = [w.strip().lower() for w in a.images.split(",") if w.strip()]
            n = 0
            with zipfile.ZipFile(a.out, "w", zipfile.ZIP_DEFLATED) as z:
                for p in paths:
                    if not p.endswith(".import") or not any(w in p.lower() for w in words):
                        continue
                    text = read_file(f, by_path[p]).decode("utf-8", "replace")
                    m = re.search(r'path="(res://\.import/[^"]+)"', text)
                    if not m or m.group(1) not in by_path:
                        continue
                    img = stex_to_image(read_file(f, by_path[m.group(1)]))
                    if img is None:
                        continue
                    orig = p[len("res://"):-len(".import")]            # e.g. items/materials/leaf.png
                    stem = os.path.splitext(orig)[0]
                    z.writestr("%s.%s" % (stem, img[0]), img[1])
                    n += 1
            print("wrote %d images to %s" % (n, a.out))
        else:
            with open(a.list_out, "w", encoding="utf-8") as out:
                for p in paths:
                    out.write(p + "\n")
            kinds = {}
            for p in paths:
                ext = os.path.splitext(p)[1].lower()
                kinds[ext] = kinds.get(ext, 0) + 1
            top = sorted(kinds.items(), key=lambda kv: -kv[1])[:12]
            print("Godot %d.%d.%d pack, %d files. Most common: %s" % (engine[0], engine[1], engine[2], len(paths), ", ".join("%s x%d" % kv for kv in top)))
            print("Every path is in %s (send that file back)." % a.list_out)


def _selftest():
    """Build a tiny pack in memory and read it back (python list_brotato_pck.py --selftest)."""
    import tempfile
    entries = [("res://items/materials/leaf.png.import", b'[remap]\npath="res://.import/leaf.png-abc.stex"\n'),
               ("res://.import/leaf.png-abc.stex", b"GDST" + b"\0" * 24 + b"\x89PNG\r\n\x1a\nFAKE")]
    buf = io.BytesIO()
    buf.write(struct.pack("<I4I", MAGIC, 1, 3, 5, 3))
    buf.write(b"\0" * 64)
    buf.write(struct.pack("<I", len(entries)))
    table = io.BytesIO()
    data = io.BytesIO()
    hdr_size = buf.tell() + sum(4 + ((len(p) + 3) & ~3) + 8 + 8 + 16 for p, _ in entries)
    for p, d in entries:
        pb = p.encode() + b"\0" * (((len(p) + 3) & ~3) - len(p))
        table.write(struct.pack("<I", len(pb)) + pb + struct.pack("<QQ", hdr_size + data.tell(), len(d)) + b"\0" * 16)
        data.write(d)
    pck = buf.getvalue() + table.getvalue() + data.getvalue()
    with tempfile.NamedTemporaryFile(delete=False, suffix=".pck") as t:
        t.write(pck)
    with open(t.name, "rb") as f:
        engine, files = read_index(f)
        assert engine == (3, 5, 3) and len(files) == 2, (engine, files)
        by = {e[0]: e for e in files}
        assert stex_to_image(read_file(f, by["res://.import/leaf.png-abc.stex"]))[0] == "png"
    os.unlink(t.name)
    print("selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        _selftest()
    else:
        main()
