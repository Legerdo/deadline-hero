"""Turn Codex image_gen sheets (tools/art_src/*.png) into game-ready pixel sprites.

Steps per sheet: magenta key -> components -> grid cell assignment ->
pixel-art aware block-mode downscale -> palette snap -> outline -> PNG.

Usage: python tools/process_sprites.py [sheet ...]
"""
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
from palette import PAL, OUTLINE, nearest_index, lum, add_outline  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "art_src")
ASSETS = os.path.join(ROOT, "assets")

SHEETS = {
    "monsters_a": dict(grid=(4, 2), out="sprites/monsters", items=[
        ("slime", 18), ("mushroom", 20), ("bee", 18), ("wolf", 24),
        ("crab", 22), ("goblin", 24), ("bat", 24), ("ore_beetle", 24)]),
    "monsters_b": dict(grid=(4, 2), out="sprites/monsters", items=[
        ("ghost", 20), ("skeleton", 24), ("candelabra", 24), ("stone_soldier", 28),
        ("wisp", 22), ("salamander", 24), ("tin_soldier", 24), ("time_beetle", 18)]),
    "bosses_a": dict(grid=(2, 2), out="sprites/bosses", items=[
        ("king_slime", 60), ("troll", 64), ("golem", 64), ("countess", 64)]),
    "bosses_b": dict(grid=(2, 2), out="sprites/bosses", slice="grid", items=[
        ("mirror_knight", 60), ("fire_drake", 64), ("zero_alt", 60), ("zero2_alt", 80)]),
    "bosses_zero": dict(grid=(2, 1), out="sprites/bosses", slice="grid", items=[
        ("zero", 60), ("zero2", 84)]),
    "portrait_countess": dict(grid=(1, 1), out="portraits", square=64, items=["countess"]),
    "portraits_a": dict(grid=(3, 2), out="portraits", square=64, items=[
        "hero", "chocho", "elder", "carpenter", "miner", "butler"]),
    "portraits_b": dict(grid=(3, 2), out="portraits", square=64, median=5, items=[
        "zero", "priestess", "smith", "countess_alt", "merchant", "rival"]),
    "items": dict(grid=(4, 4), out="sprites/items", items=[
        ("wood_sword", 16), ("iron_sword", 16), ("flame_sword", 16), ("crystal_sword", 16),
        ("leather_armor", 16), ("iron_armor", 16), ("herb", 16), ("potion", 16),
        ("hourglass", 16), ("key", 16), ("planks", 16), ("pickaxe", 16),
        ("locket", 16), ("hand_bell", 16), ("coin", 12), ("star", 16)]),
    "props": dict(grid=(4, 4), out="sprites/props", items=[
        ("house_red", 56), ("house_blue", 56), ("tree", 34), ("pine", 30),
        ("boulder", 20), ("bush", 16), ("well", 26), ("sign", 14),
        ("chest", 16), ("chest_open", 16), ("pot", 12), ("cat_statue", 24),
        ("bell", 44), ("minecart", 20), ("tomb", 15), ("torch", 12)]),
}

DARK_IDS = [i for i in range(len(PAL)) if lum(PAL[i]) < 60]


def key_background(a):
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    core = (r > 190) & (b > 190) & (g < 110)
    tint = (r - g > 70) & (b - g > 70) & (np.abs(r - b) < 90) & (r > 165) & (b > 165)
    near = ndimage.binary_dilation(core, iterations=3)
    bg = core | (tint & near)
    # grow a little through remaining pink fringe
    for _ in range(2):
        grow = ndimage.binary_dilation(bg) & tint
        bg |= grow
    return bg


def downscale_mode(rgba, tw, th, dark_bias=1.35, alpha_frac=0.42):
    H, W = rgba.shape[:2]
    idx = nearest_index(rgba[..., :3])
    fg = rgba[..., 3] > 127
    out = np.zeros((th, tw, 4), np.uint8)
    xs = np.linspace(0, W, tw + 1)
    ys = np.linspace(0, H, th + 1)
    for j in range(th):
        y0 = int(round(ys[j]))
        y1 = max(int(round(ys[j + 1])), y0 + 1)
        for i in range(tw):
            x0 = int(round(xs[i]))
            x1 = max(int(round(xs[i + 1])), x0 + 1)
            bf = fg[y0:y1, x0:x1]
            if bf.size == 0 or bf.mean() < alpha_frac:
                continue
            ids = idx[y0:y1, x0:x1][bf]
            counts = np.bincount(ids, minlength=len(PAL)).astype(np.float32)
            counts[DARK_IDS] *= dark_bias
            k = int(counts.argmax())
            out[j, i, :3] = PAL[k]
            out[j, i, 3] = 255
    return out


def clean_specks(out, min_size=3):
    op = out[..., 3] > 0
    lab, n = ndimage.label(op)
    if n <= 1:
        return out
    sizes = ndimage.sum(op, lab, range(1, n + 1))
    main = sizes.max()
    for k, s in enumerate(sizes, start=1):
        if s < min_size and s < main:
            out[lab == k, 3] = 0
    return out


def extract_cells(img, cols, rows):
    a = np.array(img.convert("RGBA"))
    bg = key_background(a)
    a[bg, 3] = 0
    fg = ~bg
    fg = ndimage.binary_opening(fg, iterations=1)
    lab, n = ndimage.label(ndimage.binary_dilation(fg, iterations=4))
    H, W = fg.shape
    cells = {}
    objs = ndimage.find_objects(lab)
    for k, sl in enumerate(objs, start=1):
        if sl is None:
            continue
        comp = (lab[sl] == k) & fg[sl]
        area = comp.sum()
        if area < 60:
            continue
        cy, cx = ndimage.center_of_mass(comp)
        cy += sl[0].start
        cx += sl[1].start
        c = min(cols - 1, int(cx / (W / cols)))
        r = min(rows - 1, int(cy / (H / rows)))
        box = [sl[0].start, sl[0].stop, sl[1].start, sl[1].stop]
        if (r, c) in cells:
            b = cells[(r, c)]
            cells[(r, c)] = [min(b[0], box[0]), max(b[1], box[1]), min(b[2], box[2]), max(b[3], box[3])]
        else:
            cells[(r, c)] = box
    return a, cells


def extract_grid(img, cols, rows):
    """Strict grid slicing (for portraits that touch their neighbours)."""
    a = np.array(img.convert("RGBA"))
    bg = key_background(a)
    a[bg, 3] = 0
    fg = ndimage.binary_opening(~bg, iterations=1)
    H, W = fg.shape
    cells = {}
    keep_all = np.zeros_like(fg)
    for r in range(rows):
        for c in range(cols):
            y0, y1 = int(r * H / rows), int((r + 1) * H / rows)
            x0, x1 = int(c * W / cols), int((c + 1) * W / cols)
            sub = fg[y0:y1, x0:x1]
            lab, n = ndimage.label(sub)
            if n == 0:
                continue
            sizes = ndimage.sum(sub, lab, range(1, n + 1))
            keep = np.isin(lab, [i + 1 for i, s in enumerate(sizes) if s >= 0.12 * sizes.max()])
            keep_all[y0:y1, x0:x1] |= keep
            ys, xs = np.nonzero(keep)
            if len(ys) < 50:
                continue
            cells[(r, c)] = [y0 + ys.min(), y0 + ys.max() + 1, x0 + xs.min(), x0 + xs.max() + 1]
    a[~keep_all, 3] = 0
    return a, cells


def median_prefilter(crop, k):
    """Remove AI texture speckle before downscaling (keeps alpha)."""
    rgb = crop[..., :3].copy()
    fg = crop[..., 3] > 127
    rgb[~fg] = OUTLINE
    for ch in range(3):
        rgb[..., ch] = ndimage.median_filter(rgb[..., ch], size=k)
    out = crop.copy()
    out[..., :3] = rgb
    return out


def process(name):
    spec = SHEETS[name]
    path = os.path.join(SRC, name + ".png")
    if not os.path.exists(path):
        print("missing", path)
        return
    cols, rows = spec["grid"]
    if "square" in spec or spec.get("slice") == "grid":
        a, cells = extract_grid(Image.open(path), cols, rows)
    else:
        a, cells = extract_cells(Image.open(path), cols, rows)
    outdir = os.path.join(ASSETS, spec["out"])
    os.makedirs(outdir, exist_ok=True)
    items = spec["items"]
    for n, it in enumerate(items):
        r, c = divmod(n, cols)
        if (r, c) not in cells:
            print("  !! no sprite found in cell", (r, c), it)
            continue
        y0, y1, x0, x1 = cells[(r, c)]
        crop = a[y0:y1, x0:x1].copy()
        h, w = crop.shape[:2]
        med = spec.get("median", 0)
        if med:
            crop = median_prefilter(crop, med)
        if "square" in spec:
            S = spec["square"]
            side = max(w, h)
            sq = np.zeros((side, side, 4), np.uint8)
            oy = side - h  # anchor portraits at the bottom (shoulders)
            ox = (side - w) // 2
            sq[oy:oy + h, ox:ox + w] = crop
            out = downscale_mode(sq, S, S, dark_bias=1.2, alpha_frac=0.5)
            out = clean_specks(out, 4)
            fname = it
        else:
            fname, D = it
            s = D / max(w, h)
            tw, th = max(1, round(w * s)), max(1, round(h * s))
            out = downscale_mode(crop, tw, th)
            out = clean_specks(out, 3)
        im = Image.fromarray(out, "RGBA")
        im = add_outline(im, mode="inner")
        im.save(os.path.join(outdir, fname + ".png"))
        print("  ", spec["out"] + "/" + fname + ".png", im.size)


def process_anim(name, cols, rows, target_h, out_rel, out_name):
    """Uniformly scaled animation sheet: every frame keeps its position relative
    to its source cell, so walk cycles do not jitter."""
    path = os.path.join(SRC, name + ".png")
    a, _ = extract_grid(Image.open(path), cols, rows)
    H, W = a.shape[:2]
    cw, ch = W / cols, H / rows
    boxes = []
    for r in range(rows):
        for c in range(cols):
            y0, x0 = int(r * ch), int(c * cw)
            sub = a[y0:int((r + 1) * ch), x0:int((c + 1) * cw), 3] > 0
            ys, xs = np.nonzero(sub)
            boxes.append((ys.min(), ys.max() + 1, xs.min(), xs.max() + 1))
    uy0 = min(b[0] for b in boxes)
    uy1 = max(b[1] for b in boxes)
    ux0 = min(b[2] for b in boxes)
    ux1 = max(b[3] for b in boxes)
    hu, wu = uy1 - uy0, ux1 - ux0
    s = target_h / hu
    fw, fh = int(round(wu * s)), int(round(hu * s))
    fw += fw % 2
    sheet = np.zeros((fh * rows, fw * cols, 4), np.uint8)
    for r in range(rows):
        for c in range(cols):
            y0, x0 = int(r * ch), int(c * cw)
            crop = a[y0 + uy0:y0 + uy1, x0 + ux0:x0 + ux1]
            fr = downscale_mode(crop, fw, fh)
            fr = clean_specks(fr, 3)
            im = add_outline(Image.fromarray(fr, "RGBA"), mode="inner")
            sheet[r * fh:(r + 1) * fh, c * fw:(c + 1) * fw] = np.array(im)
    outdir = os.path.join(ASSETS, out_rel)
    os.makedirs(outdir, exist_ok=True)
    Image.fromarray(sheet, "RGBA").save(os.path.join(outdir, out_name + ".png"))
    print("  anim", out_name, "frame", (fw, fh), "sheet", sheet.shape[1], sheet.shape[0])
    return fw, fh


def process_uniform(name, cols, rows, names, target_h, out_rel):
    """Individual sprites sharing one scale factor (consistent character heights)."""
    path = os.path.join(SRC, name + ".png")
    a, cells = extract_grid(Image.open(path), cols, rows)
    hmax = max(b[1] - b[0] for b in cells.values())
    s = target_h / hmax
    outdir = os.path.join(ASSETS, out_rel)
    os.makedirs(outdir, exist_ok=True)
    for n, nm in enumerate(names):
        r, c = divmod(n, cols)
        if (r, c) not in cells:
            print("  !! missing", nm)
            continue
        y0, y1, x0, x1 = cells[(r, c)]
        crop = a[y0:y1, x0:x1]
        tw, th = max(1, round((x1 - x0) * s)), max(1, round((y1 - y0) * s))
        fr = clean_specks(downscale_mode(crop, tw, th), 3)
        im = add_outline(Image.fromarray(fr, "RGBA"), mode="inner")
        im.save(os.path.join(outdir, nm + ".png"))
        print("  ", nm, im.size)


def contact(names, scale=4, path=None):
    """Build an enlarged preview sheet for visual review."""
    ims = []
    for sub, fn in names:
        p = os.path.join(ASSETS, sub, fn + ".png")
        if os.path.exists(p):
            ims.append(Image.open(p))
    if not ims:
        return
    wmax = sum(i.width for i in ims) + 4 * len(ims)
    hmax = max(i.height for i in ims)
    sheet = Image.new("RGBA", (wmax, hmax), (60, 70, 60, 255))
    x = 0
    for i in ims:
        sheet.alpha_composite(i, (x, hmax - i.height))
        x += i.width + 4
    sheet = sheet.resize((sheet.width * scale, sheet.height * scale), Image.NEAREST)
    sheet.save(path)


NPC_NAMES = ["npc_elder", "npc_carpenter", "npc_miner", "npc_butler", "npc_priestess",
             "npc_smith", "npc_merchant", "npc_rival", "npc_kid", "npc_chocho"]

if __name__ == "__main__":
    args = sys.argv[1:]
    if not args or "hero_sheet" in args:
        process_anim("hero_sheet", 3, 4, 27, "sprites/chars", "hero")
    if not args or "npcs" in args:
        process_uniform("npcs", 5, 2, NPC_NAMES, 27, "sprites/chars")
    names = [n for n in args if n in SHEETS] if args else list(SHEETS.keys())
    for nm in names:
        print(nm)
        process(nm)
    prev = os.path.join(ROOT, "tools", "_preview")
    os.makedirs(prev, exist_ok=True)
    if not args or "npcs" in args:
        contact([("sprites/chars", n) for n in NPC_NAMES] + [("sprites/chars", "hero")], 4, os.path.join(prev, "pp_chars.png"))
    for nm in names:
        spec = SHEETS[nm]
        lst = [(spec["out"], it if isinstance(it, str) else it[0]) for it in spec["items"]]
        contact(lst, 3 if "square" in spec or nm.startswith("boss") else 4, os.path.join(prev, "pp_" + nm + ".png"))
