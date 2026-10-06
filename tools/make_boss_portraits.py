"""Dialogue portraits for bosses without a painted portrait: the boss sprite
bottom-centred in a 64x64 frame (same pixel scale as the field sprite)."""
import glob
import os

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for p in glob.glob(os.path.join(ROOT, "assets", "sprites", "bosses", "*.png")):
    name = os.path.splitext(os.path.basename(p))[0]
    if name.endswith("_alt"):
        continue
    im = Image.open(p).convert("RGBA")
    if im.width > 64 or im.height > 64:
        s = 64 / max(im.width, im.height)
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.NEAREST)
    out = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    out.alpha_composite(im, ((64 - im.width) // 2, 64 - im.height))
    out.save(os.path.join(ROOT, "assets", "portraits", "boss_" + name + ".png"))
    print("portrait boss_" + name)
