"""Generate cached voice lines with Fish Audio TTS.

- reads data/voice_lines.json + data/voices.json
- raw API audio is cached in tools/voice_raw/<id>.<hash>.mp3 (never re-requested unless text changes)
- ffmpeg applies the character processing -> assets/audio/voice/<id>.ogg
Usage: python tools/gen_voice.py [ids...] [--reprocess]
The game runs fine without these files (text only).
"""
import hashlib
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "tools", "voice_raw")
OUT = os.path.join(ROOT, "assets", "audio", "voice")
MODEL = "s2.1-pro-free"


def load(p):
    with open(os.path.join(ROOT, p), encoding="utf-8") as f:
        return json.load(f)


def tts(text, ref, speed, dst):
    key = os.environ.get("FISH_API_KEY")
    if not key:
        raise SystemExit("FISH_API_KEY not set - voice generation skipped (game still works with text).")
    body = {"text": text, "format": "mp3", "mp3_bitrate": 128, "reference_id": ref, "normalize": True,
            "prosody": {"speed": speed}}
    req = urllib.request.Request("https://api.fish.audio/v1/tts", data=json.dumps(body).encode("utf-8"), method="POST",
                                 headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "model": MODEL})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                data = r.read()
            if data[:1] == b"{" or len(data) < 2000:
                raise RuntimeError("API returned non-audio: " + data[:200].decode("utf-8", "replace"))
            with open(dst, "wb") as f:
                f.write(data)
            return
        except (urllib.error.HTTPError, urllib.error.URLError, RuntimeError) as e:
            msg = e.read().decode("utf-8", "replace")[:200] if isinstance(e, urllib.error.HTTPError) else str(e)
            print("   retry", attempt + 1, msg)
            time.sleep(3 + attempt * 4)
    raise RuntimeError("TTS failed for " + dst)


def process(src, dst, fx):
    chain = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.03,areverse,silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.08,areverse"
    if fx:
        chain += "," + fx
    chain += ",loudnorm=I=-15:TP=-1.5:LRA=11,aresample=44100"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", src, "-af", chain, "-ac", "1", "-c:a", "libvorbis", "-q:a", "5", dst], check=True)


def main():
    lines = {k: v for k, v in load("data/voice_lines.json").items() if not k.startswith("_")}
    voices = load("data/voices.json")
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    reprocess = "--reprocess" in sys.argv
    os.makedirs(RAW, exist_ok=True)
    os.makedirs(OUT, exist_ok=True)
    ids = args or list(lines.keys())
    made = 0
    for lid in ids:
        ln = lines[lid]
        v = voices[ln["who"]]
        text = ln.get("tts", ln["text"])
        h = hashlib.sha1((text + v["ref"] + str(v.get("speed", 1.0))).encode("utf-8")).hexdigest()[:10]
        raw = os.path.join(RAW, f"{lid}.{h}.mp3")
        out = os.path.join(OUT, lid + ".ogg")
        if not os.path.exists(raw):
            print("tts", lid, "(", ln["who"], ")")
            tts(text, v["ref"], float(v.get("speed", 1.0)), raw)
            made += 1
            time.sleep(0.4)
        if reprocess or not os.path.exists(out) or os.path.getmtime(out) < os.path.getmtime(raw):
            process(raw, out, v.get("fx", ""))
    print("done; new requests:", made, "total lines:", len(ids))


if __name__ == "__main__":
    main()
