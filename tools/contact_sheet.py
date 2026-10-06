"""Tile screenshots into one sheet: python tools/contact_sheet.py out.png shot1.png shot2.png ..."""
import os
import sys

from PIL import Image

out = sys.argv[1]
os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
files = sys.argv[2:]
ims = [Image.open(f).convert("RGB") for f in files]
w, h = ims[0].size
cols = 2
rows = (len(ims) + 1) // 2
sheet = Image.new("RGB", (w * cols + 4, h * rows + 4 * (rows - 1)), (0, 0, 0))
for i, im in enumerate(ims):
    sheet.paste(im, ((i % cols) * (w + 4), (i // cols) * (h + 4)))
sheet.save(out)
print(out, sheet.size)
