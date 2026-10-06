"""Sanity report + spectrogram strip for rendered audio (we cannot listen, so we look)."""
import glob
import os
import sys
import wave

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(path):
    with wave.open(path) as w:
        n = w.getnframes()
        ch = w.getnchannels()
        x = np.frombuffer(w.readframes(n), dtype="<i2").astype(np.float32) / 32768
        if ch == 2:
            x = x.reshape(-1, 2).mean(1)
        return x, w.getframerate()


def spec_img(x, sr, w=600, h=120):
    hop = max(1, len(x) // w)
    win = 2048
    cols = []
    for i in range(w):
        seg = x[i * hop:i * hop + win]
        if len(seg) < win:
            seg = np.pad(seg, (0, win - len(seg)))
        mag = np.abs(np.fft.rfft(seg * np.hanning(win)))[:win // 2]
        # log-frequency bins 40Hz..11kHz
        f = np.geomspace(40, 11000, h)
        idx = np.clip((f / (sr / 2) * (win // 2)).astype(int), 0, win // 2 - 1)
        cols.append(20 * np.log10(mag[idx] + 1e-6))
    a = np.array(cols).T[::-1]
    a = np.clip((a + 20) / 60, 0, 1)
    return Image.fromarray((a * 255).astype(np.uint8), "L")


if __name__ == "__main__":
    kind = sys.argv[1] if len(sys.argv) > 1 else "music"
    files = sorted(glob.glob(os.path.join(ROOT, "tools", "_audio_tmp", "*.wav"))) if kind == "music" else \
        sorted(glob.glob(os.path.join(ROOT, "assets", "audio", "sfx", "*.wav")))
    strips = []
    for f in files:
        x, sr = load(f)
        rms = float(np.sqrt(np.mean(x ** 2)))
        peak = float(np.max(np.abs(x)))
        print(f"{os.path.basename(f):22s} {len(x) / sr:6.2f}s rms={rms:.3f} peak={peak:.3f} nan={np.isnan(x).any()}")
        if kind == "music":
            strips.append(spec_img(x, sr))
    if strips:
        W = strips[0].width
        sheet = Image.new("L", (W, sum(s.height + 4 for s in strips)))
        y = 0
        for s in strips:
            sheet.paste(s, (0, y))
            y += s.height + 4
        sheet.save(os.path.join(ROOT, "tools", "_preview", "spectro.png"))
