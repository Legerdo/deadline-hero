"""Copy Codex image_gen results into tools/art_src/<name>.png.

Codex sometimes reports a saved path without writing into the sandboxed
workspace. The originals always live in ~/.codex/generated_images/<session>/,
so we map each session rollout (which contains our prompt with
"exact file name <name>.png") to its generated image.

Usage: python tools/collect_images.py [--force]
"""
import glob
import os
import re
import shutil
import sys

HOME = os.path.expanduser("~")
SESS = os.path.join(HOME, ".codex", "sessions")
GEN = os.path.join(HOME, ".codex", "generated_images")
ART = os.path.join(os.path.dirname(os.path.abspath(__file__)), "art_src")
force = "--force" in sys.argv

pat = re.compile(r"exact file name ([A-Za-z0-9_\-]+)\.png")
found = {}
for f in glob.glob(os.path.join(SESS, "**", "rollout-*.jsonl"), recursive=True):
    m = re.search(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$", f)
    if not m:
        continue
    sid = m.group(1)
    gdir = os.path.join(GEN, sid)
    if not os.path.isdir(gdir):
        continue
    try:
        with open(f, "r", encoding="utf-8", errors="ignore") as fh:
            head = fh.read(200000)
    except OSError:
        continue
    nm = pat.search(head)
    if not nm:
        continue
    name = nm.group(1)
    pngs = sorted(glob.glob(os.path.join(gdir, "*.png")), key=os.path.getmtime)
    if not pngs:
        continue
    mt = os.path.getmtime(pngs[-1])
    if name not in found or mt > found[name][1]:
        found[name] = (pngs[-1], mt)

os.makedirs(ART, exist_ok=True)
for name, (src, _) in sorted(found.items()):
    dst = os.path.join(ART, name + ".png")
    if os.path.exists(dst) and not force and os.path.getmtime(dst) >= os.path.getmtime(src):
        print("keep", name)
        continue
    shutil.copy2(src, dst)
    print("copied", name, "<-", src)
