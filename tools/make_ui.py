"""UI kit: 9-slice panels, bars and small pixel icons (hand-authored ASCII art).

Usage: python tools/make_ui.py
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from palette import rgb  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "ui")
os.makedirs(OUT, exist_ok=True)

K = {  # colour keys used by the ASCII icons
    ".": None,
    "k": rgb("2e222f"), "n": rgb("3e3546"), "g": rgb("625565"), "s": rgb("9babb2"), "w": rgb("ffffff"),
    "r": rgb("e83b3b"), "R": rgb("ae2334"), "p": rgb("f68181"), "o": rgb("fb6b1d"), "y": rgb("f9c22b"),
    "Y": rgb("fbff86"), "b": rgb("4d9be6"), "B": rgb("4d65b4"), "c": rgb("8fd3ff"), "t": rgb("30e1b9"),
    "T": rgb("0eaf9b"), "G": rgb("1ebc73"), "l": rgb("91db69"), "u": rgb("905ea9"), "v": rgb("a884f3"),
    "m": rgb("966c6c"), "M": rgb("6e2727"), "e": rgb("c7dcd0"), "d": rgb("ab947a"),
}

ICONS = {
    "heart": """
.kk.kk.
krrkprk
krrrrrk
kRrrrrk
.kRrrk.
..kRk..
...k...""",
    "sword": """
......kk
.....kwk
....kwsk
.k.kwsk.
.kkwsk..
..kmk...
.kmkk...
kkk.....""",
    "shield": """
kkkkkkk
kbccbbk
kbcbbbk
kbbbbBk
.kbbBk.
..kBk..
...k...""",
    "coin": """
.kkkk.
kyYYyk
kyYyyk
kyyyok
kyyook
.kkkk.""",
    "clock": """
..kkkk..
.kwwwwk.
kwwkwwwk
kwwkwwwk
kwwkkkwk
kwwwwwwk
.kwwwwk.
..kkkk..""",
    "skull": """
.kkkkk.
kwwwwwk
kwkwkwk
kwwwwwk
.kwkwk.
.kkkkk.""",
    "arrow": """
....k....
...kyk...
..kyyyk..
.kyyyyyk.
kkkyyykkk
..kyyyk..
..kyyyk..
..kkkkk..""",
    "excl": """
.kkk.
kyyyk
kyyyk
.kyk.
.kyk.
.kkk.
kyyyk
.kkk.""",
    "quest": """
.kkkk.
kttttk
kkkktk
..ktk.
..kk..
..kk..
.ktk..
.kk...""",
    "star": """
....k....
...kyk...
kkkyYykkk
kyyYYYyyk
.kyyyyyk.
..kyykyk.
.kyk.kyk.
.kk...kk.""",
    "chest": """
.kkkkkk.
kmdddddmk
kkkkykkkk
kmmmkmmmk
kmmmmmmmk
kkkkkkkkk""",
    "echo": """
..kkkk..
.kttttk.
kttkkttk
ktk..ktk
ktk..ktk
kttkkttk
.kttttk.
..kkkk..""",
    "boss": """
k.k.k.k
kykykyk
kyyyyyk
kyrykyk
kyyyyyk
kkkkkkk""",
    "hero": """
..kkk..
.krrrk.
kryyyrk
.kyyyk.
.kbbbk.
.kbkbk.""",
    "npc": """
..kkk..
.keeek.
.kpppk.
.kGGGk.
.kGGGk.
.kk.kk.""",
    "shop": """
kkkkkkk
krwrwrk
kkkkkkk
.kdddk.
.kdkdk.
.kkkkk.""",
    "cat": """
k.....k
kk...kk
knkkknk
knynynk
knnnnnk
.kkykk.
..kyk..""",
    "lock": """
..kkk..
.kg.gk.
.kg.gk.
kkkkkkk
kyyyyyk
kyykyyk
kkkkkkk""",
    "door": """
.kkkkk.
kmmmmmk
kmdddmk
kmdddmk
kmddymk
kmdddmk
kkkkkkk""",
    "cursor": """
k....
kyk..
kyyk.
kyyyk
kyyk.
kyk..
k....""",
    "tomb": """
.kkk.
kgsgk
kgsgk
kgggk
kgggk
kkkkk""",
}


def icon(name, art):
    rows = [r for r in art.strip("\n").split("\n")]
    h, w = len(rows), max(len(r) for r in rows)
    im = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = K.get(ch)
            if c:
                im[y, x, :3] = c
                im[y, x, 3] = 255
    Image.fromarray(im, "RGBA").save(os.path.join(OUT, "icon_" + name + ".png"))


def panel(name, fill, border, hi, shadow, corner, size=24):
    """24x24 9-slice source (margins 6px)."""
    im = np.zeros((size, size, 4), np.uint8)
    f, b, h, s, c = (np.array(rgb(v)) for v in (fill, border, hi, shadow, corner))
    im[..., :3] = f
    im[..., 3] = 255
    im[0, :, :3] = b
    im[-1, :, :3] = b
    im[:, 0, :3] = b
    im[:, -1, :3] = b
    im[1, 1:-1, :3] = h
    im[1:-1, 1, :3] = h
    im[-2, 1:-1, :3] = s
    im[1:-1, -2, :3] = s
    for (x, y) in ((0, 0), (size - 1, 0), (0, size - 1), (size - 1, size - 1)):
        im[y, x, 3] = 0
    for (x, y) in ((1, 1), (size - 2, 1), (1, size - 2), (size - 2, size - 2)):
        im[y, x, :3] = c
    # subtle inner texture dots
    for y in range(4, size - 4, 4):
        for x in range(4 + (y // 4 % 2) * 2, size - 4, 4):
            im[y, x, :3] = np.clip(f.astype(int) + 8, 0, 255)
    Image.fromarray(im, "RGBA").save(os.path.join(OUT, name + ".png"))


def bar(name, col_hi, col, col_lo, w=4, h=6):
    im = np.zeros((h, w, 4), np.uint8)
    im[..., 3] = 255
    im[..., :3] = rgb(col)
    im[0, :, :3] = rgb(col_hi)
    im[1, :, :3] = rgb(col_hi)
    im[-1, :, :3] = rgb(col_lo)
    Image.fromarray(im, "RGBA").save(os.path.join(OUT, name + ".png"))


PROPS = {
    "portal": """
.....kkkkkk.....
...kkttttttkk...
..kttccccccttk..
.kttcwwwwwwcttk.
.ktcwwccccwwctk.
kttcwcttttcwcttk
ktcwccttTtccwctk
ktcwctTkkTtcwctk
ktcwctTkkTtcwctk
ktcwccttTtccwctk
kttcwcttttcwcttk
.ktcwwccccwwctk.
.kttcwwwwwwcttk.
..kttccccccttk..
...kkttttttkk...
.....kkkkkk.....""",
    "planks_site": """
...kkk......kkk.
..kmdmk....kmdmk
..kmdmk....kmdmk
kkkkkkkkkkkkkkkk
kddddddddddddddk
kmmmmmmmmmmmmmmk
kkkkkkkkkkkkkkkk
..kmdmk....kmdmk
..kmdmk....kmdmk
..kkkkk....kkkkk""",
    "gate_closed": """
kkkkkkkkkkkkkkkk
kgsgkkggkkggksgk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kkkkkkkkkkkkkkkk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kgnkskggkskgknsk
kkkkkkkkkkkkkkkk
.nnnnnnnnnnnnnn.""",
    "gate_open": """
kkk..........kkk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kgk..........kgk
kkk..........kkk
.n............n.""",
    "plate_off": """
..kkkkkkkkkkkk..
.kggggggggggggk.
kgsssssssssssgnk
kgsnnnnnnnnnsgnk
kgsnggggggggnsnk
kgsnggttttggnsnk
kgsnggttttggnsnk
kgsnggggggggnsnk
kgsnnnnnnnnnsgnk
kgsssssssssssgnk
.knnnnnnnnnnnnk.
..kkkkkkkkkkkk..""",
    "plate_on": """
..kkkkkkkkkkkk..
.kTTTTTTTTTTTTk.
kTttttttttttttTk
kTtccccccccctTTk
kTtcwwwwwwwwctTk
kTtcwwttttwwctTk
kTtcwwttttwwctTk
kTtcwwwwwwwwctTk
kTtccccccccctTTk
kTttttttttttttTk
.kTTTTTTTTTTTTk.
..kkkkkkkkkkkk..""",
    "lever_off": """
.kk.......
kyyk......
kyyk......
.kmk......
..kmk.....
...kmk....
....kmk...
.kkkkkkkk.
kgssssssgk
kgnnnnnngk
kkkkkkkkkk""",
    "lever_on": """
.......kk.
......kyyk
......kyyk
......kmk.
.....kmk..
....kmk...
...kmk....
.kkkkkkkk.
kgssssssgk
kgnnnnnngk
kkkkkkkkkk""",
    "crack": """
kkkkkkkkkkkkkkkk
kgggsgggggsggggk
kgnggggknggggngk
kggggggkggggnggk
kgsgnggkkgggggsk
kggggkkggkggnggk
knggkggggkkggggk
kgggkgggggkggngk
kggkkgnggggkgggk
kgngkggggnggkggk
kggkggsgggggkkgk
kgkggggggnggggkk
kggngggkkggsgggk
knnnnnnnnnnnnnnk
kkkkkkkkkkkkkkkk""",
    "crystal_off": """
....kk....
...kgsk...
..kgssgk..
..kgsngk..
.kgssnngk.
.kgsnnngk.
.kgsnnngk.
..kgnngk..
..kgnnk...
kkkkkkkkkk
kgnnnnnngk
kkkkkkkkkk""",
    "crystal_on": """
....kk....
...kwck...
..kcwwtk..
..kcwttk..
.kcwwtttk.
.kcwttTTk.
.kcwttTTk.
..kcttTk..
..kcTTk...
kkkkkkkkkk
kgnnnnnngk
kkkkkkkkkk""",
}


def prop_png(name, art):
    rows = [r for r in art.strip("\n").split("\n")]
    h, w = len(rows), max(len(r) for r in rows)
    im = np.zeros((h, w, 4), np.uint8)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            c = K.get(ch)
            if c:
                im[y, x, :3] = c
                im[y, x, 3] = 255
    d = os.path.join(ROOT, "assets", "sprites", "props")
    os.makedirs(d, exist_ok=True)
    Image.fromarray(im, "RGBA").save(os.path.join(d, name + ".png"))


if __name__ == "__main__":
    for k, v in PROPS.items():
        prop_png(k, v)
    for k, v in ICONS.items():
        icon(k, v)
    panel("panel", "323353", "2e222f", "484a77", "2e222f", "8fd3ff")
    panel("panel_gold", "45293f", "2e222f", "f9c22b", "7a3045", "fbff86")
    panel("panel_echo", "0b5e65", "2e222f", "30e1b9", "165a4c", "8ff8e2")
    panel("panel_red", "6e2727", "2e222f", "e83b3b", "2e222f", "fca790")
    bar("bar_hp", "f68181", "e83b3b", "ae2334")
    bar("bar_exp", "8ff8e2", "30e1b9", "0b8a8f")
    bar("bar_boss", "f79617", "fb6b1d", "b33831")
    bar("bar_time", "fbff86", "f9c22b", "f79617")
    bar("bar_bg", "3e3546", "2e222f", "2e222f")
    print("ui ok", len(ICONS), "icons")
