# Contact sheet of the worm filmstrip: python3 tests/worm_sheet.py out_prefix n [half_w half_h [cols]] -> out_prefix_sheet.png
import sys
from PIL import Image
pre, n = sys.argv[1], int(sys.argv[2])
hw = int(sys.argv[3]) if len(sys.argv) > 3 else 280
hh = int(sys.argv[4]) if len(sys.argv) > 4 else 170
cols = int(sys.argv[5]) if len(sys.argv) > 5 else 3
rows = (n + cols - 1) // cols
sheet = Image.new("RGB", (cols * 2 * hw, rows * 2 * hh), (30, 30, 30))
for i in range(n):
    im = Image.open("%s_%02d.png" % (pre, i)).convert("RGB")
    cx, cy = im.width // 2, im.height // 2
    sheet.paste(im.crop((cx - hw, cy - hh, cx + hw, cy + hh)), ((i % cols) * 2 * hw, (i // cols) * 2 * hh))
sheet.save(pre + "_sheet.png")
print(pre + "_sheet.png", sheet.size)
