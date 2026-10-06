"""Procedural 16x16 tilesets (one atlas per theme), all snapped to the master palette.

Atlas layout (16 columns x 7 rows of 16px):
  row 0: floor 0-3 | decor 4-7 | bridge_h 8 | bridge_v 9 | broken 10 | stairs 11 | face 12-15
  row 1: path overlay, dual-grid masks 0-15
  row 2: blob wall (trees / rocks) dual-grid masks 0-15
  row 3: wall top, 4-neighbour masks 0-15 (N=1 E=2 S=4 W=8 are walls)
  rows 4-6: liquid overlay masks 0-15, animation frames 0..2 stacked vertically

Dual-grid mask bits: TL=1 TR=2 BL=4 BR=8 (world cells around a display corner).
Usage: python tools/make_tiles.py  (writes assets/tiles/<theme>.png + preview)
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from palette import PAL, nearest_index  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "tiles")
T = 16


def C(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.uint8)


THEMES = {
    "village": dict(
        floor=["239063", "1ebc73", "165a4c"], floor_style="grass", flowers=["fbff86", "ffffff", "f68181", "eaaded"],
        path=["ab947a", "c7dcd0", "966c6c", "7f708a"], path_style="dirt",
        blob=["165a4c", "239063", "1ebc73", "2e222f", "0b5e65"], blob_style="canopy",
        wall=["3e3546", "625565", "7f708a", "9babb2"], wall_style="stone",
        liquid=["4d9be6", "8fd3ff", "4d65b4", "323353", "ffffff"], liquid_style="water",
        wood=["966c6c", "cd683d", "6e2727", "fbb954"]),
    "forest": dict(
        floor=["547e64", "92a984", "374e4a"], floor_style="grass", flowers=["cddf6c", "ffffff", "fbb954", "a884f3"],
        path=["ab947a", "c7dcd0", "966c6c", "7f708a"], path_style="dirt",
        blob=["374e4a", "547e64", "92a984", "2e222f", "313638"], blob_style="canopy",
        wall=["313638", "625565", "7f708a", "9babb2"], wall_style="stone",
        liquid=["4d65b4", "4d9be6", "484a77", "323353", "8fd3ff"], liquid_style="water",
        wood=["966c6c", "cd683d", "6e2727", "fbb954"]),
    "cave": dict(
        floor=["966c6c", "ab947a", "694f62"], floor_style="rock", flowers=["30e1b9", "8ff8e2", "fbb954", "f79617"],
        path=["4c3e24", "c7dcd0", "694f62", "2e222f"], path_style="rails",
        blob=["3e3546", "625565", "7f708a", "2e222f", "2e222f"], blob_style="rock",
        wall=["2e222f", "45293f", "694f62", "966c6c"], wall_style="rock",
        liquid=["2e222f", "3e3546", "2e222f", "45293f", "625565"], liquid_style="chasm",
        wood=["966c6c", "cd683d", "6e2727", "fbb954"]),
    "manor": dict(
        floor=["694f62", "7f708a", "45293f"], floor_style="wood", flowers=["eaaded", "a884f3", "fbb954", "ffffff"],
        path=["ae2334", "e83b3b", "f9c22b", "6e2727"], path_style="carpet",
        blob=["374e4a", "547e64", "92a984", "2e222f", "313638"], blob_style="canopy",
        wall=["2e222f", "45293f", "6b3e75", "905ea9"], wall_style="brick",
        liquid=["323353", "484a77", "2e222f", "2e222f", "7f708a"], liquid_style="water",
        wood=["694f62", "966c6c", "45293f", "ab947a"]),
    "temple": dict(
        floor=["0b8a8f", "0eaf9b", "0b5e65"], floor_style="tiles", flowers=["30e1b9", "8ff8e2", "ffffff", "8fd3ff"],
        path=["c7dcd0", "ffffff", "9babb2", "7f708a"], path_style="cobble",
        blob=["547e64", "92a984", "b2ba90", "2e222f", "374e4a"], blob_style="rock",
        wall=["0b5e65", "165a4c", "239063", "30e1b9"], wall_style="block",
        liquid=["30e1b9", "8ff8e2", "0eaf9b", "0b5e65", "ffffff"], liquid_style="water",
        wood=["ab947a", "c7dcd0", "7f708a", "ffffff"]),
    "volcano": dict(
        floor=["3e3546", "625565", "2e222f"], floor_style="rock", flowers=["f79617", "fb6b1d", "ea4f36", "f9c22b"],
        path=["7f708a", "9babb2", "625565", "45293f"], path_style="dirt",
        blob=["45293f", "625565", "7f708a", "2e222f", "2e222f"], blob_style="rock",
        wall=["2e222f", "3e3546", "625565", "7f708a"], wall_style="rock",
        liquid=["ea4f36", "f9c22b", "b33831", "6e2727", "fbff86"], liquid_style="lava",
        wood=["45293f", "694f62", "2e222f", "966c6c"]),
    "tower": dict(
        floor=["484a77", "4d65b4", "323353"], floor_style="tiles", flowers=["f9c22b", "fbff86", "a884f3", "ffffff"],
        path=["f9c22b", "fbff86", "f79617", "7a3045"], path_style="carpet",
        blob=["484a77", "4d65b4", "8fd3ff", "2e222f", "323353"], blob_style="rock",
        wall=["2e222f", "323353", "484a77", "a884f3"], wall_style="block",
        liquid=["2e222f", "a884f3", "45293f", "2e222f", "ffffff"], liquid_style="void",
        wood=["676633", "a2a947", "4c3e24", "fbff86"]),
}


def pnoise(seed, X, Y, octaves=5):
    """Smooth noise that is periodic with period 16 in x and y."""
    r = np.random.default_rng(seed)
    n = np.zeros_like(X, dtype=float)
    for k in range(octaves):
        fx, fy = r.integers(-3, 4), r.integers(1, 4)
        ph = r.random() * 2 * np.pi
        n += np.sin(2 * np.pi * (fx * X / T + fy * Y / T) + ph) / (1 + 0.6 * k)
    return n / (np.abs(n).max() + 1e-6)


def hash01(x, y, s=0):
    v = np.sin(x * 127.1 + y * 311.7 + s * 74.7) * 43758.5453
    return v - np.floor(v)


def snap(img):
    idx = nearest_index(img[..., :3])
    out = img.copy()
    out[..., :3] = PAL[idx]
    return out


def blank():
    return np.zeros((T, T, 4), np.uint8)


def put(img, x, y, c, a=255):
    if 0 <= x < T and 0 <= y < T:
        img[y, x, :3] = c
        img[y, x, 3] = a


# ---------------------------------------------------------------- floors
def floor_tile(th, variant, decor=False):
    cols = [C(h) for h in th["floor"]]
    base, light, dark = cols
    img = np.zeros((T, T, 4), np.uint8)
    img[..., :3] = base
    img[..., 3] = 255
    st = th["floor_style"]
    r = np.random.default_rng(100 + variant * 7 + (50 if decor else 0))
    if st == "grass":
        for _ in range(5):  # grass tufts: small 'v' shapes
            x, y = r.integers(1, 15), r.integers(2, 15)
            put(img, x, y, dark)
            put(img, x - 1, y - 1, dark)
            put(img, x + 1, y - 1, dark)
            put(img, x, y - 1, light) if r.random() < 0.5 else None
        for _ in range(4):
            put(img, r.integers(0, 16), r.integers(0, 16), light)
        if decor:
            fl = [C(h) for h in th["flowers"]]
            for _ in range(3):
                x, y = r.integers(2, 14), r.integers(2, 14)
                c = fl[r.integers(0, len(fl))]
                for dx, dy in ((0, -1), (-1, 0), (1, 0), (0, 1)):
                    put(img, x + dx, y + dy, c)
                put(img, x, y, C("f9c22b"))
    elif st == "rock":
        for _ in range(7):
            x, y = r.integers(0, 16), r.integers(0, 16)
            put(img, x, y, dark)
            put(img, x + 1, y, light if r.random() < 0.4 else dark)
        for _ in range(2):  # small crack
            x, y = r.integers(2, 13), r.integers(2, 13)
            for k in range(3):
                put(img, x + k, y + (k % 2), dark)
        if decor:
            fl = [C(h) for h in th["flowers"]]
            for _ in range(2):  # glowing crystals / embers
                x, y = r.integers(3, 13), r.integers(3, 13)
                c = fl[r.integers(0, len(fl))]
                put(img, x, y, c)
                put(img, x, y - 1, c)
                put(img, x + 1, y, C("2e222f"))
    elif st == "wood":
        # two 8px floorboards per tile, staggered joints, faint top highlight
        for row in range(2):
            y0 = row * 8
            img[y0 + 7, :, :3] = dark
            img[y0, :, :3] = np.clip(base.astype(int) + 10, 0, 255)
            jx = (variant * 5 + row * 9 + 3) % 16
            for yy in range(y0, y0 + 7):
                put(img, jx, yy, dark)
            for k in range(2):
                gx = (jx + 4 + k * 5 + variant) % 16
                put(img, gx, y0 + 3 + k, light)
        if decor:
            put(img, 5, 5, C("2e222f"))
            put(img, 12, 12, C("2e222f"))
            put(img, 6, 5, light)
    elif st == "tiles":
        for y in range(T):
            for x in range(T):
                if x % 8 == 0 or y % 8 == 0:
                    img[y, x, :3] = dark
                elif x % 8 == 1 or y % 8 == 1:
                    img[y, x, :3] = light
        if variant % 2:
            put(img, 4, 4, light)
            put(img, 12, 12, light)
        if decor:
            fl = [C(h) for h in th["flowers"]]
            for (x, y) in ((4, 4), (12, 12), (12, 4), (4, 12)):
                put(img, x, y, fl[0])
            put(img, 4, 12, fl[1])
    return img


# ---------------------------------------------------------------- dual grid
EXT = 4
XS = np.arange(-EXT, T + EXT)
GX, GY = np.meshgrid(XS, XS)


def dual_field(mask, amp, seed):
    tl, tr, bl, br = (mask >> 0) & 1, (mask >> 1) & 1, (mask >> 2) & 1, (mask >> 3) & 1
    u = np.clip((GX + 0.5) / T, 0, 1)
    v = np.clip((GY + 0.5) / T, 0, 1)
    f = tl * (1 - u) * (1 - v) + tr * u * (1 - v) + bl * (1 - u) * v + br * u * v
    return f + amp * pnoise(seed, GX, GY)


def inside_of(mask, amp=0.12, seed=3):
    if mask == 0:
        return np.zeros(GX.shape, bool)
    if mask == 15:
        return np.ones(GX.shape, bool)
    return dual_field(mask, amp, seed) > 0.5


def core(a):
    return a[EXT:EXT + T, EXT:EXT + T]


def shifted(a, dx, dy):
    """value of the neighbour at (x+dx, y+dy) for each core pixel"""
    return a[EXT + dy:EXT + dy + T, EXT + dx:EXT + dx + T]


def path_tile(th, mask):
    img = blank()
    ins = inside_of(mask, 0.06, 11)
    c0, c1, c2, c3 = [C(h) for h in th["path"]]
    st = th["path_style"]
    I = core(ins)
    edge = I & ~(shifted(ins, 1, 0) & shifted(ins, -1, 0) & shifted(ins, 0, 1) & shifted(ins, 0, -1))
    yy, xx = np.mgrid[0:T, 0:T]
    img[I, :3] = c0
    img[I, 3] = 255
    if st == "dirt":
        spk = (hash01(xx, yy, 1) > 0.95) & I & ~edge
        img[spk, :3] = c1
        spk2 = (hash01(xx, yy, 2) > 0.95) & I & ~edge
        img[spk2, :3] = c2
        img[edge, :3] = c2
    elif st == "carpet":
        img[edge, :3] = c3
        ring = I & ~edge & ~(shifted(ins, 2, 0) & shifted(ins, -2, 0) & shifted(ins, 0, 2) & shifted(ins, 0, -2))
        img[ring, :3] = c2
        dots = I & ~edge & ~ring & ((xx + yy) % 6 == 0)
        img[dots, :3] = c1
    elif st == "cobble":
        stone = ((xx // 4 + (yy // 4) % 2 * 2) % 2 == 0)
        img[I & stone, :3] = c1
        grout = I & ((xx % 4 == 0) | (yy % 4 == 0))
        img[grout, :3] = c2
        img[edge, :3] = c3
    elif st == "rails":
        # gravel bed with wooden sleepers and two steel rails (reads in both directions)
        img[I, :3] = c2
        grav = I & (hash01(xx, yy, 4) > 0.8)
        img[grav, :3] = c0
        ties = I & ~edge & ((yy % 4 == 1) | (xx % 4 == 1))
        img[ties, :3] = C("966c6c")
        steel = I & ~edge & ((xx % 8 == 3) | (yy % 8 == 3))
        img[steel, :3] = c1
        img[edge, :3] = c3
    return img


def canopy_texture(base, mid, hi, deep):
    """16-periodic texture of overlapping round leaf clumps lit from the top-left."""
    tex = np.zeros((T, T, 3), np.uint8)
    tex[...] = base
    clumps = ((3, 3, 4.5), (11, 2, 4.5), (7, 9, 4.8), (15, 10, 4.5), (1, 13, 4.2), (10, 15, 4.2))
    yy, xx = np.mgrid[0:T, 0:T]
    for (cx, cy, r) in clumps:
        for ox in (-T, 0, T):
            for oy in (-T, 0, T):
                dx = xx - (cx + ox)
                dy = yy - (cy + oy)
                d = np.sqrt(dx * dx + dy * dy)
                inside = d <= r
                if not inside.any():
                    continue
                s = dx + dy
                tex[inside] = base
                tex[inside & (s < r * 0.35)] = mid
                tex[inside & (s < -r * 0.55) & (d < r - 1)] = hi
                rim = inside & (d > r - 1.1) & (s > 0)
                tex[rim] = deep
    return tex


def blob_tile(th, mask):
    img = blank()
    ins = inside_of(mask, 0.14, 21)
    base, mid, hi, outl, deep = [C(h) for h in th["blob"]]
    st = th["blob_style"]
    I = core(ins)
    up_out = I & ~shifted(ins, 0, -1)
    dn_out = I & ~shifted(ins, 0, 1)
    dn_out2 = I & ~shifted(ins, 0, 2)
    lr_out = I & (~shifted(ins, 1, 0) | ~shifted(ins, -1, 0))
    yy, xx = np.mgrid[0:T, 0:T]
    img[I, :3] = base
    img[I, 3] = 255
    if st == "canopy":
        tex = canopy_texture(base, mid, hi, deep)
        img[I, :3] = tex[I]
        img[dn_out2 & ~dn_out, :3] = deep
        img[dn_out, :3] = outl
        img[up_out, :3] = outl
        img[lr_out, :3] = outl
        # little trunks peeking out under the canopy edge
        trunk = C("694f62")
        trunk_d = C("45293f")
        below = ~I & shifted(ins, 0, -1)
        below2 = ~I & shifted(ins, 0, -2) & ~shifted(ins, 0, -1)
        tx_ok = (xx % 8 == 3) | (xx % 8 == 4)
        sel = (below | below2) & tx_ok
        img[sel, :3] = np.where((xx[sel] % 8 == 3)[:, None], trunk, trunk_d)
        img[sel, 3] = 255
    else:  # rock
        n = pnoise(33, xx.astype(float), yy.astype(float))
        img[I & (n > 0.35), :3] = mid
        img[I & (n > 0.75), :3] = hi
        crack = I & (np.abs(pnoise(44, xx.astype(float), yy.astype(float))) < 0.06)
        img[crack, :3] = deep
        # cliff face at the bottom (3/4 view)
        face = I & ~shifted(ins, 0, 4)
        img[face, :3] = deep
        img[face & ((xx + yy // 2) % 5 == 0), :3] = base
        img[dn_out, :3] = outl
        img[up_out, :3] = hi
        img[lr_out & ~face, :3] = outl
    return img


def liquid_tile(th, mask, frame):
    img = blank()
    ins = inside_of(mask, 0.10, 31)
    base, hi, deep, bank, foam = [C(h) for h in th["liquid"]]
    st = th["liquid_style"]
    I = core(ins)
    yy, xx = np.mgrid[0:T, 0:T]
    img[I, :3] = base
    img[I, 3] = 255
    above1 = I & ~shifted(ins, 0, -1)
    above2 = I & ~shifted(ins, 0, -2) & ~above1
    above3 = I & ~shifted(ins, 0, -3) & ~above1 & ~above2
    side = I & (~shifted(ins, 1, 0) | ~shifted(ins, -1, 0) | ~shifted(ins, 0, 1))
    if st in ("water", "lava"):
        # moving highlight dashes (16-periodic so tiles stay seamless)
        ph = frame * 5
        wave = ((xx + ph + (yy // 4) * 6) % 16 < 3) & (yy % 4 == 1)
        img[I & wave, :3] = hi
        dk = (((xx - ph // 2) + (yy // 4) * 9) % 16 < 2) & (yy % 4 == 3)
        img[I & dk, :3] = deep
        if st == "lava":
            bub = I & (hash01(xx, yy, 5 + frame) > 0.96)
            img[bub, :3] = foam
        img[above1 | above2, :3] = bank
        img[above3, :3] = deep
        fo = side & ~above1 & ~above2
        if st == "water":
            flick = (hash01(xx, yy, frame) > 0.25)
            img[fo & flick, :3] = foam
        else:
            img[fo, :3] = hi
    elif st == "chasm":
        img[I, :3] = C("2e222f")
        img[above1, :3] = C("694f62")
        img[above2, :3] = C("45293f")
        img[above3, :3] = C("3e3546")
        img[side & ~above1 & ~above2, :3] = C("3e3546")
    elif st == "void":
        img[I, :3] = base
        stars = I & (hash01(xx, yy, 9) > 0.93)
        tw = hash01(xx, yy, 20 + frame) > 0.5
        img[stars & tw, :3] = foam
        img[stars & ~tw, :3] = hi
        img[above1, :3] = C("a884f3")
        img[above2, :3] = C("6b3e75")
        img[side & ~above1 & ~above2, :3] = C("45293f")
    return img


# ---------------------------------------------------------------- walls
def wall_top(th, nmask):
    top, face, face_hi, rim = [C(h) for h in th["wall"]]
    img = np.zeros((T, T, 4), np.uint8)
    img[..., :3] = top
    img[..., 3] = 255
    n, e, s, w = nmask & 1, (nmask >> 1) & 1, (nmask >> 2) & 1, (nmask >> 3) & 1
    if not n:
        img[0:2, :, :3] = rim
    if not w:
        img[:, 0:2, :3] = rim
    if not e:
        img[:, 14:16, :3] = rim
    if not s:
        img[14:16, :, :3] = face_hi
    yy, xx = np.mgrid[0:T, 0:T]
    spk = (hash01(xx, yy, 13) > 0.9) & (img[..., :3] == top).all(-1)
    img[spk, :3] = face
    return img


def wall_face(th, variant):
    top, face, face_hi, rim = [C(h) for h in th["wall"]]
    st = th["wall_style"]
    img = np.zeros((T, T, 4), np.uint8)
    img[..., :3] = face
    img[..., 3] = 255
    yy, xx = np.mgrid[0:T, 0:T]
    if st in ("brick", "stone", "block"):
        bh = 4 if st == "brick" else (8 if st == "block" else 5)
        row = yy // bh
        off = (row % 2) * (bh + 2)
        mortar = (yy % bh == bh - 1) | (((xx + off + variant * 3) % (bh * 2)) == 0)
        img[mortar, :3] = top
        hi = (yy % bh == 0) & ~mortar
        img[hi, :3] = face_hi
    else:  # rock face
        n = pnoise(55 + variant, xx.astype(float), yy.astype(float))
        img[n > 0.4, :3] = face_hi
        img[np.abs(n) < 0.08, :3] = top
    img[0:1, :, :3] = rim
    img[15:16, :, :3] = top
    return img


def bridge_tile(th, vertical=False, broken=False):
    base, light, dark, rope = [C(h) for h in th["wood"]]
    img = np.zeros((T, T, 4), np.uint8)
    yy, xx = np.mgrid[0:T, 0:T]
    a = xx if not vertical else yy          # along the walking direction
    b = yy if not vertical else xx          # across the bridge
    plank = (a % 4 != 3)
    img[..., :3] = np.where(plank[..., None], base, dark)
    img[(a % 4 == 0) & plank, :3] = light
    img[..., 3] = 255
    rail = (b <= 1) | (b >= 14)
    img[rail, :3] = dark
    img[(b == 1) | (b == 14), :3] = rope
    if broken:
        # most planks are gone (water shows through), the rest hang crooked
        row = a // 4
        keep_row = np.isin(row, [1])
        img[~rail & ~keep_row, 3] = 0
        crooked = keep_row & ~rail & (b > 8)
        img[crooked, 3] = 0
        shifted_mask = keep_row & ~rail & (b <= 8)
        img[shifted_mask, :3] = dark
        # one rail snapped
        snap = ((b <= 1) & (a >= 6) & (a <= 10)) | ((b >= 14) & (a >= 11))
        img[snap, 3] = 0
        # frayed rope ends
        img[(b == 1) & (a == 5), :3] = rope
        img[(b == 14) & (a == 10), :3] = rope
    return img


def stairs_tile(th):
    top, face, face_hi, rim = [C(h) for h in th["wall"]]
    img = np.zeros((T, T, 4), np.uint8)
    img[..., 3] = 255
    for y in range(T):
        img[y, :, :3] = face_hi if y % 4 < 2 else face
        if y % 4 == 3:
            img[y, :, :3] = top
    img[:, 0:2, :3] = top
    img[:, 14:16, :3] = top
    return img


def build(name, th):
    atlas = np.zeros((7 * T, 16 * T, 4), np.uint8)

    def place(col, row, tile):
        atlas[row * T:(row + 1) * T, col * T:(col + 1) * T] = tile

    for v in range(4):
        place(v, 0, floor_tile(th, v))
        place(4 + v, 0, floor_tile(th, v, decor=True))
    place(8, 0, bridge_tile(th))
    place(9, 0, bridge_tile(th, vertical=True))
    place(10, 0, bridge_tile(th, broken=True))
    place(11, 0, bridge_tile(th, vertical=True, broken=True))
    for v in range(4):
        place(12 + v, 0, wall_face(th, v))
    for m in range(16):
        place(m, 1, path_tile(th, m))
        place(m, 2, blob_tile(th, m))
        place(m, 3, wall_top(th, m))
        for f in range(3):
            place(m, 4 + f, liquid_tile(th, m, f))
    atlas = snap(atlas)
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(atlas, "RGBA").save(os.path.join(OUT, name + ".png"))
    return atlas


# ---------------------------------------------------------------- preview
TEST_MAP = [
    "TTTTTTTTTTTTTTTTTTTTTTTT",
    "TTTT......,,......TTTTTT",
    "TT....::::::::.......TTT",
    "T....::....,.::...~~~..T",
    "T...::..##....::.~~~~~.T",
    "T..::...##.....:=~~~~..T",
    "T..:.....,......~~~~...T",
    "T..:..TT.....:::..~....T",
    "T..::.TTT...::.........T",
    "T...::::::::::....,,...T",
    "TT.............####....T",
    "TTTTTT....TTTT.####..TTT",
    "TTTTTTTTTTTTTTTTTTTTTTTT",
]


def render_preview(atlas, name):
    Hm, Wm = len(TEST_MAP), len(TEST_MAP[0])
    img = np.zeros((Hm * T, Wm * T, 4), np.uint8)

    def tile(col, row):
        return atlas[row * T:(row + 1) * T, col * T:(col + 1) * T]

    def blit(t, x, y):
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + T, Wm * T), min(y + T, Hm * T)
        if x1 <= x0 or y1 <= y0:
            return
        src = t[y0 - y:y1 - y, x0 - x:x1 - x]
        dst = img[y0:y1, x0:x1]
        a = src[..., 3:4] > 0
        dst[...] = np.where(a, src, dst)

    def cell(x, y):
        if 0 <= y < Hm and 0 <= x < Wm:
            return TEST_MAP[y][x]
        return "T"

    for y in range(Hm):
        for x in range(Wm):
            v = int(hash01(x, y, 1) * 4)
            blit(tile(4 + v % 4 if cell(x, y) == "," else v, 0), x * T, y * T)
    for kind, row, chars in (("path", 1, ":="), ("liquid", 4, "~="), ("blob", 2, "T")):
        for j in range(Hm + 1):
            for i in range(Wm + 1):
                m = 0
                for bit, (dx, dy) in enumerate(((-1, -1), (0, -1), (-1, 0), (0, 0))):
                    c = cell(i + dx, j + dy)
                    if c in chars and not (kind == "path" and c == "="):
                        m |= 1 << bit
                if m:
                    blit(tile(m, row), i * T - 8, j * T - 8)
    for y in range(Hm):
        for x in range(Wm):
            c = cell(x, y)
            if c == "=":
                blit(tile(8, 0), x * T, y * T)
            if c == "#":
                if cell(x, y + 1) != "#":
                    blit(tile(12 + (x % 4), 0), x * T, y * T)
                else:
                    nm = (cell(x, y - 1) == "#") | ((cell(x + 1, y) == "#") << 1) | ((cell(x, y + 1) == "#") << 2) | ((cell(x - 1, y) == "#") << 3)
                    blit(tile(nm, 3), x * T, y * T)
    return Image.fromarray(img, "RGBA")


if __name__ == "__main__":
    names = sys.argv[1:] or list(THEMES.keys())
    prevs = []
    for nm in names:
        at = build(nm, THEMES[nm])
        prevs.append(render_preview(at, nm))
        print("built", nm)
    cols = 2 if len(prevs) > 1 else 1
    rows = (len(prevs) + cols - 1) // cols
    w, h = prevs[0].size
    sheet = Image.new("RGBA", (w * cols + 4 * (cols - 1), h * rows + 4 * (rows - 1)), (0, 0, 0, 255))
    for i, p in enumerate(prevs):
        sheet.paste(p, ((i % cols) * (w + 4), (i // cols) * (h + 4)))
    if len(prevs) == 1:
        sheet = sheet.resize((w * 2, h * 2), Image.NEAREST)
    prev = os.path.join(ROOT, "tools", "_preview")
    os.makedirs(prev, exist_ok=True)
    sheet.save(os.path.join(prev, "tiles_preview.png"))
