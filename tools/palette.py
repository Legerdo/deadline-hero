"""Master palette + pixel helpers shared by every asset tool.

The palette is based on Resurrect 64 (by Kerrie Lake, lospec.com), which
gives long, well balanced ramps. Every generated or AI-derived image is
snapped to it so the whole game shares one colour language.
"""
import numpy as np
from PIL import Image

HEX = """
2e222f 3e3546 625565 966c6c ab947a 694f62 7f708a 9babb2 c7dcd0 ffffff
6e2727 b33831 ea4f36 f57d4a ae2334 e83b3b fb6b1d f79617 f9c22b 7a3045
9e4539 cd683d e6904e fbb954 4c3e24 676633 a2a947 d5e04b fbff86 165a4c
239063 1ebc73 91db69 cddf6c 313638 374e4a 547e64 92a984 b2ba90 0b5e65
0b8a8f 0eaf9b 30e1b9 8ff8e2 323353 484a77 4d65b4 4d9be6 8fd3ff 45293f
6b3e75 905ea9 a884f3 eaaded 753c54 a24b6f cf657f ed8099 831c5d c32454
f04f78 f68181 fca790 fdcbb0
""".split()

PAL = np.array([[int(h[i:i + 2], 16) for i in (0, 2, 4)] for h in HEX], dtype=np.uint8)
OUTLINE = np.array([0x2e, 0x22, 0x2f], dtype=np.uint8)  # darkest entry


def rgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def _srgb_to_lab(c):
    c = c.astype(np.float32) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]], dtype=np.float32)
    xyz = c @ m.T
    xyz /= np.array([0.95047, 1.0, 1.08883], dtype=np.float32)
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    L = 116 * f[..., 1] - 16
    a = 500 * (f[..., 0] - f[..., 1])
    b = 200 * (f[..., 1] - f[..., 2])
    return np.stack([L, a, b], axis=-1)


PAL_LAB = _srgb_to_lab(PAL)


def nearest_index(rgb_arr, pal_lab=PAL_LAB):
    """rgb_arr: (...,3) uint8 -> palette indices (...)"""
    shp = rgb_arr.shape[:-1]
    lab = _srgb_to_lab(rgb_arr.reshape(-1, 3))
    out = np.empty(lab.shape[0], dtype=np.int32)
    step = 65536
    for i in range(0, lab.shape[0], step):
        d = ((lab[i:i + step, None, :] - pal_lab[None, :, :]) ** 2).sum(-1)
        out[i:i + step] = d.argmin(1)
    return out.reshape(shp)


def quantize_rgba(img, alpha_cut=128, pal=PAL):
    """Snap an RGBA PIL image to the palette with hard alpha."""
    a = np.array(img.convert("RGBA"))
    idx = nearest_index(a[..., :3])
    out = np.zeros_like(a)
    out[..., :3] = pal[idx]
    out[..., 3] = np.where(a[..., 3] >= alpha_cut, 255, 0)
    return Image.fromarray(out, "RGBA")


def lum(c):
    c = np.asarray(c, dtype=np.float32)
    return 0.299 * c[..., 0] + 0.587 * c[..., 1] + 0.114 * c[..., 2]


def add_outline(img, color=OUTLINE, mode="outer"):
    """mode='outer' grows a 1px outline outside the silhouette,
    mode='inner' darkens bright boundary pixels inside the silhouette."""
    a = np.array(img.convert("RGBA"))
    op = a[..., 3] > 0
    h, w = op.shape
    pad = np.pad(op, 1)
    n4 = pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]
    if mode == "outer":
        ring = n4 & ~op
        a[ring, :3] = color
        a[ring, 3] = 255
    else:
        e4 = ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        edge = op & e4
        bright = lum(a[..., :3]) > 70
        sel = edge & bright
        a[sel, :3] = color
    return Image.fromarray(a, "RGBA")


def shade(c, k):
    """Move along palette brightness: returns a nearby palette colour darker (k<0) or lighter (k>0)."""
    c = np.array(c, dtype=np.float32)
    target = np.clip(c * (1 + 0.18 * k) + 12 * k, 0, 255).astype(np.uint8)
    return tuple(int(v) for v in PAL[nearest_index(target[None, :])[0]])
