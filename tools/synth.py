"""Minimal chiptune synth: band-limited pulses, 4-bit triangle, LFSR noise,
envelopes, a step sequencer and a few effects. Pure numpy."""
import math
import os
import subprocess
import wave

import numpy as np

SR = 44100
NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def midi(name):
    if isinstance(name, (int, float)):
        return name
    n = NOTE[name[0].upper()]
    i = 1
    while i < len(name) and name[i] in "#b":
        n += 1 if name[i] == "#" else -1
        i += 1
    octave = int(name[i:])
    return n + 12 * (octave + 1)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


# ------------------------------------------------------------------ oscillators
def _phase(freq):
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), freq.shape if hasattr(freq, "shape") else ())
    return np.cumsum(f / SR) % 1.0


def _blep(t, dt):
    y = np.zeros_like(t)
    m1 = t < dt
    x = t[m1] / dt[m1]
    y[m1] = x + x - x * x - 1.0
    m2 = t > 1.0 - dt
    x2 = (t[m2] - 1.0) / dt[m2]
    y[m2] = x2 * x2 + x2 + x2 + 1.0
    return y


def pulse(freq, duty=0.5):
    freq = np.asarray(freq, dtype=np.float64)
    ph = np.cumsum(freq / SR) % 1.0
    dt = np.clip(freq / SR, 1e-6, 0.5)
    y = np.where(ph < duty, 1.0, -1.0)
    y += _blep(ph, dt)
    y -= _blep((ph - duty) % 1.0, dt)
    return y


def tri(freq, steps=16):
    freq = np.asarray(freq, dtype=np.float64)
    ph = np.cumsum(freq / SR) % 1.0
    y = 1.0 - 4.0 * np.abs(ph - 0.5)
    if steps:
        y = np.round((y + 1) * (steps - 1) / 2) / ((steps - 1) / 2) - 1
    return y


def sine(freq):
    freq = np.asarray(freq, dtype=np.float64)
    return np.sin(2 * np.pi * np.cumsum(freq / SR))


def saw(freq):
    freq = np.asarray(freq, dtype=np.float64)
    ph = np.cumsum(freq / SR) % 1.0
    dt = np.clip(freq / SR, 1e-6, 0.5)
    return 2 * ph - 1 - _blep(ph, dt)


_rng = np.random.default_rng(7)


def noise(n, rate=SR, seed=None):
    rng = np.random.default_rng(seed) if seed is not None else _rng
    if rate >= SR:
        return rng.uniform(-1, 1, n)
    hold = max(1, int(SR / rate))
    v = rng.uniform(-1, 1, n // hold + 2)
    return np.repeat(v, hold)[:n]


def noise_sweep(n, rate0, rate1, seed=None):
    rng = np.random.default_rng(seed) if seed is not None else _rng
    rates = np.geomspace(max(rate0, 50), max(rate1, 50), n)
    ph = np.cumsum(rates / SR)
    idx = ph.astype(np.int64)
    vals = rng.uniform(-1, 1, idx[-1] + 2)
    return vals[idx]


# ------------------------------------------------------------------ envelopes & filters
def env_adsr(n, a=0.005, d=0.05, s=0.7, r=0.05, gate=None):
    gate = n if gate is None else min(gate, n)
    t = np.arange(n) / SR
    e = np.zeros(n)
    A, D = max(a, 1e-4), max(d, 1e-4)
    e = np.where(t < A, t / A, np.where(t < A + D, 1 - (1 - s) * (t - A) / D, s))
    gt = gate / SR
    rel = t >= gt
    if rel.any():
        lvl = np.interp(gt, t, e) if gate < n else s
        e[rel] = lvl * np.clip(1 - (t[rel] - gt) / max(r, 1e-4), 0, 1)
    return e


def env_exp(n, decay=0.2, attack=0.002):
    t = np.arange(n) / SR
    e = np.exp(-t / max(decay, 1e-4))
    if attack > 0:
        e *= np.clip(t / attack, 0, 1)
    return e


def lowpass(x, cutoff):
    """one-pole lowpass; cutoff may be an array"""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=np.float64), x.shape)
    a = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a[i] * (x[i] - acc)
        y[i] = acc
    return y


def lowpass_fast(x, cutoff):
    a = 1 - math.exp(-2 * math.pi * cutoff / SR)
    from scipy.signal import lfilter
    return lfilter([a], [1, -(1 - a)], x)


def highpass_fast(x, cutoff):
    return x - lowpass_fast(x, cutoff)


def bandpass_fast(x, lo, hi):
    return lowpass_fast(highpass_fast(x, lo), hi)


def echo(x, delay=0.18, fb=0.35, mix=0.3, lp=4000):
    d = int(delay * SR)
    out = np.concatenate([x, np.zeros(d * 6)])
    wet = np.zeros_like(out)
    buf = out.copy()
    for k in range(1, 7):
        seg = np.zeros_like(out)
        seg[d * k:] = buf[:len(out) - d * k] * (fb ** k)
        wet += seg
    wet = lowpass_fast(wet, lp)
    return out * (1 - mix * 0.3) + wet * mix


def reverb(x, amount=0.25, size=1.0):
    """cheap Schroeder-ish reverb"""
    delays = [int(SR * d * size) for d in (0.0297, 0.0371, 0.0411, 0.0437)]
    tail = int(SR * 1.2 * size)
    y = np.concatenate([x, np.zeros(tail)])
    from scipy.signal import lfilter
    acc = np.zeros_like(y)
    for d in delays:
        b = np.zeros(1)
        a = np.zeros(d + 1)
        a[0] = 1
        a[d] = -0.78
        acc += lfilter([1.0], a, y)
    acc = lowpass_fast(acc / len(delays), 5000)
    for d, g in ((int(SR * 0.005), 0.7), (int(SR * 0.0017), 0.7)):
        a = np.zeros(d + 1)
        a[0] = 1
        a[d] = -g
        bb = np.zeros(d + 1)
        bb[0] = -g
        bb[d] = 1
        acc = lfilter(bb, a, acc)
    return y * (1 - amount * 0.5) + acc * amount


def softclip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) + 1e-9
    return x * (peak / m)


def fade(x, fin=0.002, fout=0.01):
    n = len(x)
    a, b = int(fin * SR), int(fout * SR)
    if a > 0:
        x[:a] *= np.linspace(0, 1, a)
    if b > 0:
        x[-b:] *= np.linspace(1, 0, b)
    return x


def silence(sec):
    return np.zeros(int(sec * SR))


def place(buf, x, at):
    i = int(at * SR)
    if i >= len(buf):
        return buf
    n = min(len(x), len(buf) - i)
    buf[i:i + n] += x[:n]
    return buf


# ------------------------------------------------------------------ io
def write_wav(path, x, stereo=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if stereo is not None:
        data = np.stack([x, stereo], axis=1)
        ch = 2
    else:
        data = x
        ch = 1
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def to_ogg(wav_path, ogg_path, q=5):
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(q), ogg_path], check=True)
