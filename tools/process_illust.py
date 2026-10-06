"""Full-screen illustrations (title, world map, ending) -> 640x360 palette-snapped PNGs.

Usage: python tools/process_illust.py
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(__file__))
from palette import PAL, nearest_index  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art_src")
OUT = os.path.join(ROOT, "assets", "ui")

JOBS = {"title_keyart": "title_bg", "world_map": "worldmap_bg", "ending": "ending_bg", "concept_village": "concept_bg"}


def fit_169(im):
    w, h = im.size
    tw = min(w, int(h * 16 / 9))
    th = int(tw * 9 / 16)
    x0 = (w - tw) // 2
    y0 = (h - th) // 2
    return im.crop((x0, y0, x0 + tw, y0 + th))


def process(src, dst, size=(640, 360)):
    p = os.path.join(SRC, src + ".png")
    if not os.path.exists(p):
        print("missing", src)
        return
    im = fit_169(Image.open(p).convert("RGB"))
    im = im.filter(ImageFilter.MedianFilter(3)).resize(size, Image.LANCZOS)
    a = np.array(im)
    idx = nearest_index(a)
    out = PAL[idx]
    Image.fromarray(out.astype(np.uint8), "RGB").save(os.path.join(OUT, dst + ".png"))
    print("ok", dst)


if __name__ == "__main__":
    for s, d in JOBS.items():
        process(s, d)
