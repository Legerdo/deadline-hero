"""Original chiptune soundtrack -> assets/audio/music/*.ogg  (python tools/make_music.py [names])

Melody notation: one token per 16th step. NOTE (e.g. F#5) starts a note,
'-' holds the previous note, '.' is a rest. Accompaniment (bass, arps, pads,
drums) is generated from the chord list so every track shares one sound.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import (SR, echo, env_adsr, env_exp, highpass_fast, hz, lowpass_fast, midi, noise, pulse,  # noqa: E402
                   reverb, sine, softclip, to_ogg, tri, write_wav, saw)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "music")
TMP = os.path.join(ROOT, "tools", "_audio_tmp")

PC = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8,
      "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}
QUAL = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11],
        "dim": [0, 3, 6], "sus4": [0, 5, 7], "sus2": [0, 2, 7], "aug": [0, 4, 8], "m6": [0, 3, 7, 9], "add9": [0, 4, 7, 14]}


def chord(name):
    r = name[:2] if len(name) > 1 and name[1] in "#b" else name[:1]
    q = name[len(r):]
    return PC[r], QUAL[q]


def parse(bars):
    """list of bar strings -> [(step, length, midi)]"""
    ev = []
    step = 0
    cur = None
    for b in bars:
        toks = b.split()
        assert len(toks) == 16, (len(toks), b)
        for t in toks:
            if t == "-":
                if cur is not None:
                    cur[1] += 1
            elif t == ".":
                cur = None
            else:
                cur = [step, 1, midi(t)]
                ev.append(cur)
            step += 1
    return [tuple(e) for e in ev]


# ------------------------------------------------------------------ instruments
def v_lead(f, dur, vel, duty=0.25, vib=0.004, a=0.004, d=0.09, s=0.55, r=0.07):
    n = int((dur + r) * SR)
    t = np.arange(n) / SR
    fv = f * (1 + vib * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.12) / 0.15, 0, 1))
    y = pulse(fv, duty) * env_adsr(n, a, d, s, r, gate=int(dur * SR))
    return y * vel


def v_soft(f, dur, vel):
    n = int((dur + 0.12) * SR)
    y = tri(np.full(n, f), 0) * 0.8 + pulse(np.full(n, f), 0.5) * 0.25
    return lowpass_fast(y, 3000) * env_adsr(n, 0.01, 0.15, 0.6, 0.12, gate=int(dur * SR)) * vel


def v_bell(f, dur, vel):
    n = int((dur + 0.6) * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * 6) + 0.2 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t * 9)
    return y * np.exp(-t * 2.2) * np.clip(t / 0.002, 0, 1) * vel


def v_pad(f, dur, vel, duty=0.125):
    n = int((dur + 0.1) * SR)
    y = pulse(np.full(n, f), duty) + pulse(np.full(n, f * 1.003), duty) * 0.6
    return lowpass_fast(y, 2400) * env_adsr(n, 0.03, 0.2, 0.7, 0.1, gate=int(dur * SR)) * vel


def v_bass(f, dur, vel, staccato=0.85):
    g = dur * staccato
    n = int((g + 0.03) * SR)
    y = tri(np.full(n, f))
    return y * env_adsr(n, 0.002, 0.05, 0.9, 0.03, gate=int(g * SR)) * vel


def v_bass_saw(f, dur, vel):
    n = int((dur * 0.9 + 0.03) * SR)
    y = lowpass_fast(saw(np.full(n, f)) * 0.6 + pulse(np.full(n, f), 0.5) * 0.4, 900)
    return y * env_adsr(n, 0.002, 0.08, 0.7, 0.03, gate=int(dur * 0.9 * SR)) * vel


def v_arp(f, dur, vel, duty=0.125):
    n = int((dur + 0.02) * SR)
    return pulse(np.full(n, f), duty) * env_exp(n, dur * 0.8, 0.001) * vel


def d_kick(vel=1.0):
    n = int(0.16 * SR)
    f = np.geomspace(150, 42, n)
    return np.sin(2 * np.pi * np.cumsum(f / SR)) * env_exp(n, 0.07, 0.001) * vel


def d_snare(vel=1.0):
    n = int(0.14 * SR)
    x = highpass_fast(noise(n, SR), 900) * env_exp(n, 0.045, 0.001)
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 35)
    return (x * 0.8 + body * 0.5) * vel


def d_hat(vel=1.0, open_=False):
    n = int((0.12 if open_ else 0.035) * SR)
    x = highpass_fast(noise(n, SR), 6000) * env_exp(n, 0.04 if open_ else 0.01, 0.0005)
    return x * vel


def d_tom(vel=1.0, f0=220):
    n = int(0.2 * SR)
    f = np.geomspace(f0, f0 * 0.5, n)
    return np.sin(2 * np.pi * np.cumsum(f / SR)) * env_exp(n, 0.08) * vel


def d_crash(vel=1.0):
    n = int(0.9 * SR)
    return highpass_fast(noise(n, SR), 3500) * env_exp(n, 0.35, 0.001) * vel


DRUMS = {
    "rock": {"k": "x.......x.x.....", "s": "....x.......x...", "h": "x.x.x.x.x.x.x.x."},
    "drive": {"k": "x.....x.x.....x.", "s": "....x.......x..x", "h": "xxxxxxxxxxxxxxxx"},
    "bounce": {"k": "x.......x.......", "s": "....x.......x...", "h": "..x...x...x...x."},
    "half": {"k": "x...............", "s": "........x.......", "h": "x...x...x...x..."},
    "sparse": {"k": "x.........x.....", "s": "................", "h": "....x.......x..."},
    "march": {"k": "x...x...x...x...", "s": "..x...x...x.x.xx", "h": "x.x.x.x.x.x.x.x."},
    "waltzy": {"k": "x.....x.........", "s": "........x.....x.", "h": "x..x..x..x..x..."},
    "none": {"k": "................", "s": "................", "h": "................"},
    "boss": {"k": "x..x..x.x..x..x.", "s": "....x.......x...", "h": "x.xxx.xxx.xxx.xx"},
}


class Song:
    def __init__(self, name, bpm, chords, melody=None, key_pcs=None, drums="rock", bass="root8", arp="up",
                 lead="lead", duty=0.25, lead_vol=0.30, bass_vol=0.33, arp_vol=0.08, pad_vol=0.0, drum_vol=0.5,
                 oct_bass=36, oct_arp=60, echo_mix=0.18, rev=0.12, harmony=None, fills=True, bass_wave="tri",
                 melody2=None, lead2_vol=0.0, intro_bars=0, swing=0.0, lead_oct=0):
        self.__dict__.update(locals())
        del self.__dict__["self"]


def render(song):
    step = 60.0 / song.bpm / 4.0
    nbars = len(song.chords)
    total = nbars * 16 * step
    N = int(round(total * SR))
    pad = int(3 * SR)
    L = np.zeros(N + pad)
    R = np.zeros(N + pad)

    def put(y, at, pan=0.5, gain=1.0):
        i = int(round(at * SR))
        n = min(len(y), len(L) - i)
        if n <= 0:
            return
        L[i:i + n] += y[:n] * gain * (1 - pan) * 2 ** 0.5
        R[i:i + n] += y[:n] * gain * pan * 2 ** 0.5

    def t_of(s):
        sw = song.swing * step if (s % 2 == 1) else 0.0
        return s * step + sw

    # ------------------------------------------------ melody
    lead_bus_L = np.zeros_like(L)
    lead_bus_R = np.zeros_like(R)

    def put_lead(y, at, pan=0.5):
        i = int(round(at * SR))
        n = min(len(y), len(L) - i)
        if n <= 0:
            return
        lead_bus_L[i:i + n] += y[:n] * (1 - pan) * 2 ** 0.5
        lead_bus_R[i:i + n] += y[:n] * pan * 2 ** 0.5

    if song.melody:
        for (s, ln, m) in parse(song.melody):
            f = hz(m + 12 * song.lead_oct)
            dur = ln * step * 0.97
            if song.lead == "lead":
                y = v_lead(f, dur, song.lead_vol, song.duty)
            elif song.lead == "soft":
                y = v_soft(f, dur, song.lead_vol)
            else:
                y = v_bell(f, dur, song.lead_vol)
            put_lead(y, t_of(s), 0.5)
    if song.melody2:
        for (s, ln, m) in parse(song.melody2):
            y = v_lead(hz(m), ln * step * 0.95, song.lead2_vol, 0.125, vib=0.002)
            put_lead(y, t_of(s) + 0.004, 0.3)
    if song.echo_mix > 0:
        dl = int(step * 3 * SR)
        for k, g in ((1, 0.35), (2, 0.15)):
            lead_bus_L[dl * k:] += lead_bus_R[:-dl * k] * g * song.echo_mix * 2
            lead_bus_R[dl * k:] += lead_bus_L[:-dl * k] * g * song.echo_mix * 1.5
    L += lead_bus_L
    R += lead_bus_R

    # ------------------------------------------------ harmony / bass / arps per bar
    for b, cname in enumerate(song.chords):
        halves = cname.split("|")
        for hi, hc in enumerate(halves):
            root, ivs = chord(hc.strip())
            span = 16 // len(halves)
            base = b * 16 + hi * span
            # bass
            rb = song.oct_bass + root
            if rb > song.oct_bass + 7:
                rb -= 12
            pat = song.bass
            notes = []
            if pat == "root8":
                for k in range(0, span, 2):
                    notes.append((k, 2, rb + (12 if k % 8 == 6 else 0)))
            elif pat == "rootfifth":
                seq = [(0, 2, rb), (4, 2, rb + 7), (8, 2, rb + 12), (12, 2, rb + 7)]
                notes = [n for n in seq if n[0] < span]
            elif pat == "long":
                notes = [(0, span, rb)]
            elif pat == "half":
                notes = [(k, min(8, span - k), rb if k == 0 else rb + 7) for k in range(0, span, 8)]
            elif pat == "gallop":
                for k in range(0, span, 4):
                    notes += [(k, 1, rb), (k + 1, 1, rb), (k + 2, 2, rb + (7 if k % 8 == 4 else 0))]
            elif pat == "walk":
                third = ivs[1]
                seq = [rb, rb + third, rb + 7, rb + 12 if span > 8 else rb + 7]
                notes = [(k * 4, 4, seq[k]) for k in range(span // 4)]
            elif pat == "sync":
                seq = [(0, 3, rb), (3, 3, rb), (6, 2, rb + 12), (8, 3, rb), (11, 3, rb + 7), (14, 2, rb + 10)]
                notes = [n for n in seq if n[0] < span]
            for (k, ln, m) in notes:
                f = hz(m)
                if song.bass_wave == "saw":
                    y = v_bass_saw(f, ln * step, song.bass_vol)
                else:
                    y = v_bass(f, ln * step, song.bass_vol)
                put(y, t_of(base + k), 0.5)
            # arps
            if song.arp != "none" and song.arp_vol > 0:
                tones = [song.oct_arp + root + iv for iv in ivs]
                tones = [t - 12 if t > song.oct_arp + 14 else t for t in tones]
                if song.arp == "up":
                    order = tones + [tones[0] + 12]
                elif song.arp == "updown":
                    order = tones + [tones[0] + 12] + tones[::-1][1:-1]
                else:
                    order = tones
                rate = 1 if song.arp != "slow" else 2
                for k in range(0, span, rate):
                    m = order[(k // rate) % len(order)]
                    put(v_arp(hz(m), step * rate * 0.9, song.arp_vol), t_of(base + k), 0.72)
            if song.pad_vol > 0:
                for iv in ivs[:3]:
                    m = 60 + root + iv
                    if m > 71:
                        m -= 12
                    put(v_pad(hz(m), span * step * 0.98, song.pad_vol / 2), t_of(base), 0.3)
        # drums
        dp = DRUMS[song.drums]
        last_bar = (b % 8 == 7) and song.fills and song.drums not in ("none", "sparse")
        for k in range(16):
            s = b * 16 + k
            if last_bar and k >= 12:
                put(d_snare(0.55 + 0.1 * (k - 12)) * song.drum_vol, t_of(s), 0.5)
                put(d_tom(0.6, 260 - (k - 12) * 30) * song.drum_vol, t_of(s), 0.45)
                continue
            if dp["k"][k] == "x":
                put(d_kick() * song.drum_vol, t_of(s), 0.5)
            if dp["s"][k] == "x":
                put(d_snare(0.8) * song.drum_vol, t_of(s), 0.5)
            if dp["h"][k] == "x":
                put(d_hat(0.35 if k % 4 else 0.5) * song.drum_vol, t_of(s), 0.62)
        if b % 8 == 0 and song.drums not in ("none", "sparse", "half"):
            put(d_crash(0.35) * song.drum_vol, t_of(b * 16), 0.55)

    # ------------------------------------------------ fold the tail for a seamless loop, master
    if getattr(song, "loop", True):
        L[:pad] += L[N:N + pad]
        R[:pad] += R[N:N + pad]
        L, R = L[:N], R[:N]
    else:
        N = len(L)
    if song.rev > 0:
        if getattr(song, "loop", True):
            # circular reverb: run over two periods and keep the second, so the
            # ring-out of the last bar is already sounding when the loop restarts
            wetL = reverb(np.concatenate([L, L]), 1.0, 0.9)[N:2 * N]
            wetR = reverb(np.concatenate([R, R]), 1.0, 1.05)[N:2 * N]
        else:
            wetL = reverb(L, 1.0, 0.9)[:N]
            wetR = reverb(R, 1.0, 1.05)[:N]
        L = L * (1 - song.rev) + wetL * song.rev * 0.9
        R = R * (1 - song.rev) + wetR * song.rev * 0.9
    # loudness-match every track (RMS target), then tame peaks
    rms = float(np.sqrt(np.mean((L * L + R * R) * 0.5))) + 1e-9
    g = 0.22 / rms
    L = softclip(L * g, 1.3) * 0.92
    R = softclip(R * g, 1.3) * 0.92
    return L, R, total


# ================================================================== compositions
MAIN_A = [
    "A4 - - - D5 - - - F#5 - E5 - D5 - - -",
    "E5 - - - A4 - - - C#5 - D5 - E5 - - -",
    "F#5 - - - B4 - - - D5 - E5 - F#5 - G5 -",
    "A5 - - - - - G5 - F#5 - - - E5 - - -",
    "A4 - - - D5 - - - F#5 - E5 - D5 - - -",
    "E5 - - - A5 - - - G5 - F#5 - E5 - - -",
    "D5 - E5 - F#5 - G5 - F#5 - E5 - D5 - C#5 -",
    "E5 - - - - - - - . . . . A4 - C#5 -",
]
MAIN_B = [
    "D5 - - - F#5 - - - B5 - - - A5 - F#5 -",
    "G5 - - - - - B4 - D5 - G5 - F#5 - E5 -",
    "F#5 - - - A5 - - - D6 - - - C#6 - A5 -",
    "B5 - - - A5 - - - E5 - - - . . C#5 -",
    "D5 - F#5 - B5 - - - A5 - G5 - F#5 - D5 -",
    "G5 - - - B5 - - - A5 - G5 - F#5 - E5 -",
    "E5 - F#5 - G5 - - - A5 - - - C#6 - - -",
    "D6 - - - - - - - . . . . . . . .",
]
MAIN_CH_A = ["D", "A", "Bm", "G", "D", "A", "G", "A"]
MAIN_CH_B = ["Bm", "G", "D", "A", "Bm", "G", "Em7|A7", "D"]

FIELD = [
    "D5 . B4 . G4 . B4 . D5 - E5 . D5 - - .",
    "E5 . C5 . G4 . C5 . E5 - G5 . E5 - - .",
    "F#5 . D5 . A4 . D5 . F#5 - A5 . G5 - F#5 -",
    "G5 - - - D5 - - - B4 - - - . . . .",
    "E5 . G5 . B5 - A5 . G5 . E5 . G5 - - .",
    "E5 . G5 . C6 - B5 . A5 . G5 . E5 - - .",
    "C#5 . E5 . G5 - F#5 . E5 . C#5 . A4 - - .",
    "D5 - - - F#5 - - - A5 - - - F#5 - - -",
    "D5 . B4 . G4 . B4 . D5 - E5 . D5 - - .",
    "E5 . C5 . G4 . C5 . E5 - G5 . E5 - - .",
    "F#5 . A5 . D6 - C6 . B5 . A5 . F#5 - D5 .",
    "E5 - G5 - B5 - - - A5 - G5 - E5 - - .",
    "C5 . E5 . G5 . C6 . B5 - A5 - G5 - E5 -",
    "F#5 . A5 . D5 . F#5 . A5 - G5 - F#5 - E5 -",
    "G5 - - - B5 - - - D6 - - - B5 - - -",
    "G5 - - - . . . . D5 . E5 . F#5 . G5 .",
]
FIELD_CH = ["G", "C", "D", "G", "Em", "C", "A7", "D", "G", "C", "D", "Em", "C", "D", "G", "G"]

BOSS = [
    "A4 - A4 . C5 - A4 . E5 - D5 . C5 - B4 .",
    "A4 - A4 . C5 - E5 . A5 - G5 . E5 - D5 .",
    "F5 - - - E5 - - - D5 - C5 - D5 - E5 -",
    "D5 - - - B4 - - - G4 - A4 - B4 - D5 -",
    "A4 - A4 . C5 - A4 . E5 - D5 . C5 - B4 .",
    "A4 - A4 . C5 - E5 . A5 - B5 . C6 - B5 .",
    "A5 - - - G5 - F5 - E5 - F5 - G5 - A5 -",
    "G#5 - - - - - - - E5 - - - B4 - - -",
    "D5 - F5 - A5 - - - G5 - F5 - E5 - D5 -",
    "E5 - G#5 - B5 - - - A5 - G#5 - E5 - - -",
    "C6 - B5 - A5 - E5 - C5 - E5 - A5 - - -",
    "A5 - G5 - E5 - C5 - A4 - C5 - E5 - - -",
    "F5 - - - A5 - - - C6 - - - A5 - - -",
    "G5 - - - B5 - - - D6 - - - B5 - - -",
    "E5 - F5 - G#5 - A5 - B5 - C6 - D6 - E6 -",
    "E6 - - - - - - - . . . . E5 . E5 .",
]
BOSS_CH = ["Am", "Am", "F", "G", "Am", "Am", "F", "E", "Dm", "E", "Am", "Am", "F", "G", "E", "E"]

FINAL = [
    "D5 - F5 - A5 - D6 - C6 - A5 - F5 - A5 -",
    "Bb5 - - - A5 - - - F5 - D5 - F5 - G5 -",
    "E5 - G5 - C6 - - - Bb5 - A5 - G5 - E5 -",
    "C#5 - - - E5 - - - A5 - - - G5 - E5 -",
    "D6 - C6 - A5 - F5 - D5 - F5 - A5 - D6 -",
    "D6 - - - C6 - Bb5 - A5 - G5 - F5 - D5 -",
    "G5 - Bb5 - D6 - - - C6 - Bb5 - A5 - G5 -",
    "A5 - - - - - - - C#6 - - - E6 - - -",
]
FINAL_CH = ["Dm", "Bb", "C", "A", "Dm", "Bb", "Gm", "A"]

VICTORY = [
    "G4 . C5 . E5 . G5 - - - E5 . G5 - - -",
    "A5 - - - F5 - A5 - B5 - - - D6 - - -",
    "C6 - - - - - - - - - - - - - - -",
]


def transpose(bars, semis):
    out = []
    for b in bars:
        toks = []
        for t in b.split():
            if t in "-.":
                toks.append(t)
            else:
                m = midi(t) + semis
                names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
                toks.append(f"{names[m % 12]}{m // 12 - 1}")
        out.append(" ".join(toks))
    return out


def gen_melody(chords, scale, seed, lo=64, hi=81, density=0.55, motif_bars=2, long_end=True):
    """Motif-based procedural melody: chord tones on strong beats, stepwise
    motion elsewhere, repeated rhythmic motif with variations."""
    rng = np.random.default_rng(seed)
    scale_notes = [m for m in range(lo - 12, hi + 13) if (m % 12) in scale]

    def rhythm():
        r = []
        k = 0
        while k < 16:
            if k in (0, 8) or rng.random() < density:
                ln = rng.choice([2, 2, 2, 4, 1, 3] if k % 4 == 0 else [1, 2, 2])
                ln = int(min(ln, 16 - k))
                r.append((k, ln))
                k += ln
            else:
                k += 1
        return r

    motifs = [[rhythm() for _ in range(motif_bars)] for _ in range(2)]
    bars = []
    prev = (lo + hi) // 2
    for b, cname in enumerate(chords):
        root, ivs = chord(cname.split("|")[0].strip())
        ctones = [m for m in scale_notes if (m - root) % 12 in [iv % 12 for iv in ivs] and lo <= m <= hi]
        sect = (b // 4) % 2
        rh = motifs[sect][b % motif_bars]
        phrase_end = long_end and b % 4 == 3
        if phrase_end:
            rh = [(0, 4), (4, 2), (6, 2), (8, 8)]
        toks = ["."] * 16
        for (k, ln) in rh:
            if k % 8 == 0 or phrase_end and k == 8:
                cands = sorted(ctones, key=lambda m: abs(m - prev))[:3]
                m = int(rng.choice(cands)) if cands else prev
            else:
                idx = min(range(len(scale_notes)), key=lambda i: abs(scale_notes[i] - prev))
                step = int(rng.choice([-2, -1, -1, 1, 1, 2, 0]))
                idx = max(0, min(len(scale_notes) - 1, idx + step))
                m = scale_notes[idx]
                if m < lo or m > hi:
                    m = scale_notes[max(0, min(len(scale_notes) - 1, idx - 2 * step))]
            names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
            toks[k] = f"{names[m % 12]}{m // 12 - 1}"
            for j in range(1, ln):
                if k + j < 16:
                    toks[k + j] = "-"
            prev = m
        bars.append(" ".join(toks))
    return bars


def long_form(ch_a, ch_b, scale, seed, lo, hi, dens, mel_a=None):
    """32-bar stage form: A (16) + bridge B (8, new motifs, a bit higher and busier)
    + reprise of A's second half (8), which cadences back into bar 1 for the loop.
    A 60 s stage loop now hears ~1.2 passes instead of 2+ identical ones."""
    a = mel_a if mel_a is not None else gen_melody(ch_a, scale, seed, lo, hi, dens)
    b = gen_melody(ch_b, scale, seed + 500, lo + 2, hi + 2, min(0.85, dens + 0.12))
    return ch_a + ch_b + ch_a[8:], a + b + a[8:]


def songs():
    S = {}
    maj = [0, 2, 4, 5, 7, 9, 11]
    nmin = [0, 2, 3, 5, 7, 8, 10]
    hmin = [0, 2, 3, 5, 7, 8, 11]

    def keyed(scale, root):
        return [(p + root) % 12 for p in scale]

    S["title"] = Song("title", 138, MAIN_CH_A + MAIN_CH_B, MAIN_A + MAIN_B, drums="rock", bass="root8", arp="up",
                      lead_vol=0.3, arp_vol=0.07, pad_vol=0.12, rev=0.18)
    S["worldmap"] = Song("worldmap", 116, MAIN_CH_A + MAIN_CH_B, transpose(MAIN_A + MAIN_B, -2), drums="bounce", bass="rootfifth",
                         arp="updown", lead="soft", lead_vol=0.34, arp_vol=0.06, pad_vol=0.1, rev=0.2)
    S["ending"] = Song("ending", 92, MAIN_CH_A + MAIN_CH_B + MAIN_CH_A, MAIN_A + MAIN_B + transpose(MAIN_A, 12)[:7] + ["D6 - - - - - - - - - - - - - - -"],
                       drums="half", bass="long", arp="slow", lead="soft", lead_vol=0.34, arp_vol=0.07, pad_vol=0.2, rev=0.3, fills=False)
    ch, mel = long_form(FIELD_CH, ["Em", "C", "G", "D", "Em", "C", "Am", "D"], keyed(maj, 7), 11, 67, 84, 0.5, FIELD)
    S["field"] = Song("field", 150, ch, mel, drums="bounce", bass="rootfifth", arp="up", duty=0.5,
                      lead_vol=0.26, arp_vol=0.06, rev=0.1)
    S["boss"] = Song("boss", 166, BOSS_CH, BOSS, drums="boss", bass="root8", arp="up", bass_wave="saw",
                     lead_vol=0.28, arp_vol=0.07, pad_vol=0.08, rev=0.1, echo_mix=0.12)
    S["final2"] = Song("final2", 176, FINAL_CH * 2, FINAL + transpose(FINAL, 12)[:4] + FINAL[4:], drums="drive", bass="gallop", arp="updown",
                       bass_wave="saw", lead_vol=0.27, arp_vol=0.07, pad_vol=0.12, rev=0.12)
    S["victory"] = Song("victory", 150, ["C", "F|G", "C"], VICTORY, drums="none", bass="long", arp="up", lead_vol=0.32,
                        arp_vol=0.08, pad_vol=0.15, rev=0.2, fills=False, echo_mix=0.1)
    S["victory"].loop = False
    # procedural stage themes (32-bar long form: A + bridge + A' reprise) -------------
    # each bridge ends on a chord that resolves into bar 9 of A
    ch, mel = long_form(["F", "C", "Dm", "Bb", "F", "C", "Bb", "C", "Dm", "Bb", "F", "C", "Gm", "Bb", "C", "F"],
                        ["Bb", "F", "Gm", "C", "Bb", "F", "Gm", "A7"], keyed(maj, 5), 21, 65, 84, 0.55)
    S["river"] = Song("river", 144, ch, mel, drums="rock", bass="walk", arp="updown",
                      lead_vol=0.27, arp_vol=0.08, rev=0.15, duty=0.25)
    ch, mel = long_form(["Am", "Am", "F", "E", "Am", "Dm", "E", "E", "F", "G", "Am", "Am", "Dm", "F", "E", "E"],
                        ["Dm", "Am", "Dm", "E", "F", "C", "Dm", "C"], keyed(hmin, 9), 33, 60, 79, 0.35)
    S["cave"] = Song("cave", 112, ch, mel, drums="sparse", bass="half",
                     arp="slow", lead="bell", lead_vol=0.3, arp_vol=0.06, pad_vol=0.12, rev=0.35, echo_mix=0.3)
    ch, mel = long_form(["Dm", "A7", "Dm", "Gm|A7", "Bb", "Gm", "E7|A7", "Dm", "Gm", "Dm", "A7", "Dm", "Bb", "Gm", "A7", "A7"],
                        ["F", "C", "Dm", "A7", "Bb", "F", "Gm|A7", "D7"], keyed(hmin, 2), 45, 62, 81, 0.5)
    S["manor"] = Song("manor", 128, ch, mel, drums="waltzy", bass="walk",
                      arp="updown", lead="lead", duty=0.125, lead_vol=0.26, arp_vol=0.07, pad_vol=0.1, rev=0.25, swing=0.18)
    ch, mel = long_form(["Em", "D", "C", "D", "Em", "D", "C", "B7", "Am", "Em", "C", "D", "Em", "D", "C|D", "Em"],
                        ["C", "G", "D", "Em", "C", "G", "Am|B7", "E7"], keyed([0, 2, 3, 5, 7, 9, 10], 4), 57, 64, 83, 0.45)
    S["temple"] = Song("temple", 124, ch, mel, drums="half", bass="long",
                       arp="updown", lead="bell", lead_vol=0.3, arp_vol=0.08, pad_vol=0.16, rev=0.35, echo_mix=0.25)
    ch, mel = long_form(["Em", "Em", "C", "D", "Em", "Em", "C", "B7", "Am", "C", "D", "Em", "Am", "B7", "Em", "B7"],
                        ["C", "D", "Bm", "Em", "C", "D", "B7", "E7"], keyed(nmin, 4), 69, 62, 81, 0.6)
    S["volcano"] = Song("volcano", 160, ch, mel, drums="drive", bass="gallop",
                        arp="up", bass_wave="saw", lead_vol=0.26, arp_vol=0.07, rev=0.08)
    ch, mel = long_form(["Cm", "Ab", "Bb", "G", "Cm", "Ab", "Fm|G", "Cm", "Ab", "Eb", "Bb", "Cm", "Fm", "Ab", "G", "G"],
                        ["Fm", "Cm", "Ab", "Eb", "Fm", "Bb", "Eb", "Eb"], keyed(hmin, 0), 81, 63, 84, 0.55)
    S["tower"] = Song("tower", 150, ch, mel, drums="march", bass="sync",
                      arp="updown", bass_wave="saw", lead_vol=0.27, arp_vol=0.07, pad_vol=0.1, rev=0.12)
    ch = ["Am", "F", "C", "G", "Am", "F", "E", "E"]
    S["prologue"] = Song("prologue", 84, ch, gen_melody(ch, keyed(nmin, 9), 93, 64, 83, 0.3), drums="none", bass="long",
                         arp="slow", lead="bell", lead_vol=0.32, arp_vol=0.07, pad_vol=0.18, rev=0.35, fills=False)
    return S


def main():
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(TMP, exist_ok=True)
    S = songs()
    names = sys.argv[1:] or list(S.keys())
    for nm in names:
        L, R, total = render(S[nm])
        wav = os.path.join(TMP, nm + ".wav")
        write_wav(wav, L, R)
        to_ogg(wav, os.path.join(OUT, nm + ".ogg"))
        print(f"{nm}: {total:.1f}s")


if __name__ == "__main__":
    main()
