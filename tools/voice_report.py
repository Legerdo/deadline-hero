"""Duration vs text-length report for voice lines (flags suspicious takes)."""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
lines = json.load(open(os.path.join(ROOT, "data", "voice_lines.json"), encoding="utf-8"))
sys.stdout.reconfigure(encoding="utf-8")
rows = []
for lid, ln in lines.items():
    if lid.startswith("_"):
        continue
    p = os.path.join(ROOT, "assets", "audio", "voice", lid + ".ogg")
    if not os.path.exists(p):
        print("MISSING", lid)
        continue
    d = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                             capture_output=True, text=True).stdout.strip() or 0)
    syll = sum(1 for ch in ln["text"] if "\uac00" <= ch <= "\ud7a3" or ch.isdigit())
    rate = syll / d if d > 0 else 0
    rows.append((rate, lid, d, syll, ln["who"]))
rows.sort()
for rate, lid, d, syll, who in rows:
    flag = "  <-- slow?" if rate < 3.2 and syll > 3 else ("  <-- fast?" if rate > 9 else "")
    print(f"{lid:18s} {who:10s} {d:5.2f}s  {syll:3d}syl  {rate:4.1f}/s{flag}")
