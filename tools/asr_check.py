"""Transcribe generated voice files with Fish Audio ASR to verify the words
(and that emotion cues were not read aloud). Usage: python tools/asr_check.py id [id...]"""
import json
import os
import sys
import urllib.request

import msgpack

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
key = os.environ["FISH_API_KEY"]
lines = json.load(open(os.path.join(ROOT, "data", "voice_lines.json"), encoding="utf-8"))
sys.stdout.reconfigure(encoding="utf-8")
for lid in sys.argv[1:]:
    path = os.path.join(ROOT, "assets", "audio", "voice", lid + ".ogg")
    raw = [f for f in os.listdir(os.path.join(ROOT, "tools", "voice_raw")) if f.startswith(lid + ".")]
    src = os.path.join(ROOT, "tools", "voice_raw", raw[0]) if raw else path
    body = msgpack.packb({"audio": open(src, "rb").read(), "language": "ko", "ignore_timestamps": True}, use_bin_type=True)
    req = urllib.request.Request("https://api.fish.audio/v1/asr", data=body, method="POST",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/msgpack", "model": "transcribe-1"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            res = json.loads(r.read().decode("utf-8"))
        print(f"{lid}: expected={lines[lid]['text']!r}\n   heard={res.get('text')!r}")
    except urllib.error.HTTPError as e:
        print(lid, "ASR error", e.code, e.read()[:300])
