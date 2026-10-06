"""All sound effects -> assets/audio/sfx/*.wav  (python tools/make_sfx.py)"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from synth import (SR, bandpass_fast, echo, env_adsr, env_exp, fade, highpass_fast, hz, lowpass_fast, midi,  # noqa: E402
                   noise, noise_sweep, normalize, place, pulse, reverb, saw, silence, sine, softclip, tri, write_wav)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio", "sfx")


def n_(sec):
    return int(sec * SR)


def sweep(f0, f1, sec, curve="exp"):
    n = n_(sec)
    if curve == "exp":
        return np.geomspace(max(f0, 1), max(f1, 1), n)
    return np.linspace(f0, f1, n)


def tone(note, sec, wave="pulse", duty=0.5, decay=None, a=0.002, s=0.6, r=0.03, vib=0.0):
    n = n_(sec)
    if isinstance(note, np.ndarray):
        f = np.resize(note, n) if len(note) != n else note.astype(np.float64)
        if len(note) < n:
            f = np.concatenate([note, np.full(n - len(note), note[-1])])
    elif isinstance(note, str):
        f = np.full(n, hz(midi(note)))
    elif isinstance(note, int) and note < 128:
        f = np.full(n, hz(note))
    else:
        f = np.full(n, float(note))
    if vib:
        f = f * (1 + vib * np.sin(2 * np.pi * 6 * np.arange(n) / SR))
    if wave == "pulse":
        y = pulse(f, duty)
    elif wave == "tri":
        y = tri(f)
    elif wave == "sine":
        y = sine(f)
    else:
        y = saw(f)
    e = env_exp(n, decay, a) if decay else env_adsr(n, a, 0.04, s, r, gate=n - n_(r))
    return y * e


def seq(notes, step, wave="pulse", duty=0.5, decay=0.12, gap=0.0, vol_curve=None):
    out = silence(step * len(notes) + decay * 3)
    for i, nt in enumerate(notes):
        if nt is None:
            continue
        v = 1.0 if vol_curve is None else vol_curve[i]
        place(out, tone(nt, step + decay * 2, wave, duty, decay=decay) * v, i * (step + gap))
    return out


def bell(f0, sec=2.0, partials=((1, 1.0), (2.0, 0.6), (2.76, 0.45), (5.4, 0.25), (8.93, 0.12)), decay=1.2):
    n = n_(sec)
    t = np.arange(n) / SR
    y = np.zeros(n)
    for r, a in partials:
        y += a * np.sin(2 * np.pi * f0 * r * t) * np.exp(-t / (decay / (0.6 + r * 0.35)))
    return y * np.clip(t / 0.003, 0, 1)


def kick(sec=0.18, f0=160, f1=40):
    n = n_(sec)
    f = np.geomspace(f0, f1, n)
    return sine(f) * env_exp(n, sec * 0.35, 0.001)


def burst(sec, rate=SR, decay=None, lp=None, hp=None, seed=None):
    n = n_(sec)
    x = noise(n, rate, seed)
    if lp:
        x = lowpass_fast(x, lp)
    if hp:
        x = highpass_fast(x, hp)
    return x * env_exp(n, decay or sec * 0.3, 0.001)


def mix(*arrs):
    n = max(len(a) for a in arrs)
    out = np.zeros(n)
    for a in arrs:
        out[:len(a)] += a
    return out


SFX = {}


def sfx(fn):
    SFX[fn.__name__] = fn
    return fn


# ------------------------------------------------------------------ movement / combat
@sfx
def step():
    return burst(0.035, 9000, 0.008, lp=2500) * 0.5


@sfx
def dash():
    n = n_(0.2)
    x = noise_sweep(n, 1500, 9000)
    x = bandpass_fast(x, 600, 5000) * env_adsr(n, 0.01, 0.05, 0.5, 0.12, gate=n_(0.06))
    return mix(x * 0.9, tone(sweep(300, 900, 0.1), 0.1, "pulse", 0.25, decay=0.04) * 0.15)


@sfx
def hit():
    a = pulse(sweep(700, 160, 0.09), 0.5) * env_exp(n_(0.09), 0.03)
    b = burst(0.07, 12000, 0.02)
    k = kick(0.1, 220, 70) * 0.8
    out = silence(0.12)
    place(out, a * 0.5, 0)
    place(out, b * 0.6, 0)
    place(out, k, 0)
    return out


@sfx
def crit():
    out = silence(0.35)
    place(out, hit() * 1.1, 0)
    place(out, tone(sweep(1800, 2600, 0.2), 0.2, "pulse", 0.125, decay=0.07) * 0.35, 0.01)
    place(out, bell(2400, 0.3, decay=0.2) * 0.25, 0.02)
    place(out, kick(0.2, 180, 40) * 0.8, 0)
    return out


@sfx
def hurt():
    out = silence(0.28)
    place(out, pulse(sweep(520, 110, 0.22), 0.25) * env_exp(n_(0.22), 0.08) * 0.5, 0)
    place(out, burst(0.12, 6000, 0.04) * 0.5, 0)
    place(out, kick(0.16, 120, 40) * 0.7, 0)
    return out


@sfx
def enemy_die():
    out = silence(0.45)
    place(out, burst(0.3, 8000, 0.08, lp=6000) * 0.6, 0)
    place(out, seq([88, 83, 79, 76, 71], 0.035, "pulse", 0.25, 0.05), 0.02)
    place(out, kick(0.2, 140, 40) * 0.6, 0)
    return out


@sfx
def coin():
    return seq(["B5", "E6"], 0.055, "pulse", 0.5, 0.12) * 0.6


@sfx
def orb():
    return tone(sweep(900, 1800, 0.06), 0.07, "sine", decay=0.03) * 0.5


@sfx
def levelup():
    out = silence(1.2)
    notes = ["C5", "E5", "G5", "C6", "E6", "G6"]
    place(out, seq(notes, 0.055, "pulse", 0.25, 0.18) * 0.6, 0)
    place(out, seq(["G5", "C6", "E6"], 0.055, "tri", 0.5, 0.3) * 0.5, 0.33)
    for i in range(8):
        place(out, bell(2000 + i * 330, 0.3, decay=0.12) * 0.12, 0.35 + i * 0.05)
    return echo(out, 0.12, 0.3, 0.35)


@sfx
def heal():
    out = silence(0.8)
    place(out, seq(["G5", "B5", "D6", "G6"], 0.07, "sine", 0.5, 0.3) * 0.6, 0)
    return echo(out, 0.1, 0.3, 0.3)


@sfx
def item_get():
    out = silence(0.9)
    place(out, seq(["G5", "A5", "B5", "D6"], 0.07, "pulse", 0.25, 0.1) * 0.55, 0)
    place(out, tone("G6", 0.35, "pulse", 0.125, decay=0.2) * 0.4, 0.28)
    return echo(out, 0.1, 0.3, 0.25)


@sfx
def chest():
    out = silence(0.9)
    cr = bandpass_fast(noise_sweep(n_(0.18), 300, 900), 200, 1500) * env_adsr(n_(0.18), 0.02, 0.05, 0.6, 0.05) * 0.5
    place(out, cr, 0)
    place(out, seq(["E5", "G#5", "B5", "E6"], 0.05, "pulse", 0.5, 0.15) * 0.5, 0.15)
    return echo(out, 0.09, 0.25, 0.25)


# ------------------------------------------------------------------ ui
@sfx
def menu_move():
    return tone("A5", 0.035, "pulse", 0.25, decay=0.012) * 0.45


@sfx
def menu_ok():
    return seq(["E5", "B5"], 0.04, "pulse", 0.25, 0.05) * 0.55


@sfx
def menu_back():
    return seq(["B5", "E5"], 0.04, "pulse", 0.25, 0.05) * 0.45


@sfx
def buzz():
    return pulse(np.full(n_(0.14), 110.0), 0.5) * env_adsr(n_(0.14), 0.002, 0.02, 0.8, 0.03) * 0.35


@sfx
def blip():
    return pulse(np.full(n_(0.03), 880.0), 0.5) * env_exp(n_(0.03), 0.015) * 0.35


@sfx
def talk():
    return tone(sweep(500, 900, 0.05), 0.06, "pulse", 0.5, decay=0.03) * 0.4


@sfx
def deja():
    n = n_(1.0)
    out = silence(1.3)
    sw = sine(np.geomspace(300, 1200, n)) * np.linspace(0, 1, n) ** 2 * 0.3
    place(out, sw, 0)
    for i, f in enumerate([1568, 1976, 2349, 2637]):
        place(out, bell(f, 0.5, decay=0.25) * 0.18, 0.55 + i * 0.07)
    return reverb(out, 0.4)


@sfx
def learn():
    out = silence(1.0)
    place(out, seq(["D6", "A5", "F#6", "D7"], 0.06, "tri", 0.5, 0.25) * 0.5, 0)
    return echo(out, 0.14, 0.4, 0.4)


@sfx
def time_add():
    out = silence(0.9)
    for i in range(3):
        place(out, burst(0.02, SR, 0.005, hp=3000) * 0.5, i * 0.06)
    place(out, seq(["C6", "E6", "G6", "C7"], 0.045, "pulse", 0.125, 0.12) * 0.45, 0.18)
    return echo(out, 0.1, 0.3, 0.3)


@sfx
def tick():
    out = burst(0.025, SR, 0.004, hp=2500) * 0.8
    return mix(out, tone(2200.0, 0.025, "sine", decay=0.006) * 0.3)


@sfx
def heartbeat():
    out = silence(0.45)
    place(out, kick(0.16, 90, 35), 0)
    place(out, kick(0.14, 80, 35) * 0.7, 0.16)
    return out


@sfx
def bell_toll():
    out = silence(4.5)
    place(out, bell(98, 4.2, decay=2.5) * 0.9, 0)
    place(out, bell(196.5, 3.0, decay=1.4) * 0.35, 0)
    place(out, burst(0.05, 5000, 0.02) * 0.3, 0)
    return reverb(out, 0.4, 1.3)


@sfx
def rewind():
    n = n_(1.6)
    t = np.arange(n) / SR
    f = 800 * np.exp(-t * 1.2) + 120 + 60 * np.sin(2 * np.pi * 11 * t)
    x = pulse(f, 0.25) * 0.3 + saw(f * 1.5) * 0.15
    x += noise_sweep(n, 6000, 800) * 0.15
    x *= np.clip(t / 0.05, 0, 1) * np.clip((1.6 - t) / 0.3, 0, 1)
    rev = bell(1200, 1.2, decay=0.6)[::-1] * 0.25
    out = silence(1.8)
    place(out, x, 0)
    place(out, rev, 0.35)
    return reverb(out, 0.3)


@sfx
def stage_start():
    out = silence(1.6)
    n = n_(0.8)
    place(out, bandpass_fast(noise_sweep(n, 800, 10000), 400, 8000) * np.linspace(0, 1, n) ** 2 * 0.5, 0)
    for nt in ["C4", "G4", "C5", "E5"]:
        place(out, tone(nt, 0.7, "pulse", 0.25, decay=0.35) * 0.3, 0.8)
    place(out, kick(0.3, 160, 40), 0.8)
    return reverb(out, 0.3)


@sfx
def go():
    out = silence(0.9)
    for nt in ["D4", "A4", "D5", "F#5", "A5"]:
        place(out, tone(nt, 0.5, "pulse", 0.25, decay=0.25) * 0.28, 0)
    place(out, kick(0.25, 180, 40), 0)
    place(out, burst(0.3, 9000, 0.1) * 0.3, 0)
    return reverb(out, 0.25)


@sfx
def boss_appear():
    out = silence(2.2)
    n = n_(2.0)
    rum = lowpass_fast(noise(n, 4000), 300) * env_adsr(n, 0.4, 0.3, 0.7, 0.8, gate=n_(1.2)) * 1.2
    place(out, rum, 0)
    for nt in ["C3", "F#3", "C4", "C#4"]:
        place(out, tone(nt, 1.3, "saw", decay=0.7) * 0.2, 0.3)
    place(out, kick(0.5, 100, 30) * 1.2, 0.3)
    return reverb(softclip(out, 1.5), 0.3)


@sfx
def boss_die():
    out = silence(3.2)
    for i in range(6):
        place(out, burst(0.5, 5000 - i * 500, 0.2, lp=5000) * 0.7, i * 0.18)
        place(out, kick(0.35, 120, 30) * 0.8, i * 0.18)
    place(out, seq([76, 71, 67, 64, 59, 55, 52, 48], 0.09, "pulse", 0.5, 0.15) * 0.4, 0.4)
    return reverb(softclip(out, 1.3), 0.35, 1.2)


@sfx
def boss_hurt():
    return mix(pulse(sweep(180, 90, 0.18), 0.5) * env_exp(n_(0.18), 0.07) * 0.5, burst(0.1, 3000, 0.04) * 0.3)


@sfx
def slam():
    out = silence(0.6)
    place(out, kick(0.45, 110, 28) * 1.2, 0)
    place(out, burst(0.35, 3000, 0.12, lp=2000) * 0.8, 0)
    return softclip(out, 1.4)


@sfx
def jump():
    return tone(sweep(200, 900, 0.22), 0.24, "pulse", 0.25, decay=0.12) * 0.5


@sfx
def squish():
    n = n_(0.15)
    f = 300 + 250 * np.sin(2 * np.pi * 30 * np.arange(n) / SR)
    return sine(f * np.linspace(1.3, 0.7, n)) * env_exp(n, 0.06) * 0.6


@sfx
def roar():
    n = n_(0.9)
    t = np.arange(n) / SR
    f = 90 + 25 * np.sin(2 * np.pi * 7 * t)
    x = saw(f) * 0.5 + lowpass_fast(noise(n, 3000), 900) * 0.6
    x = softclip(x * env_adsr(n, 0.08, 0.2, 0.7, 0.3, gate=n_(0.6)), 2.0)
    return x * 0.8


@sfx
def throw():
    n = n_(0.25)
    return bandpass_fast(noise_sweep(n, 600, 3000), 300, 2500) * env_adsr(n, 0.05, 0.05, 0.5, 0.12, gate=n_(0.1)) * 0.8


@sfx
def magic():
    n = n_(0.4)
    t = np.arange(n) / SR
    f = 600 + 900 * t / 0.4
    x = sine(f + 300 * np.sin(2 * np.pi * 40 * t)) * env_exp(n, 0.15)
    return echo(x * 0.5, 0.07, 0.35, 0.35)


@sfx
def fire():
    n = n_(0.6)
    x = lowpass_fast(noise(n, 8000), 2500) * env_adsr(n, 0.02, 0.1, 0.6, 0.3, gate=n_(0.3))
    cr = (noise(n, SR) > 0.97).astype(float) * noise(n, SR) * 0.8
    return (x * 0.8 + cr * 0.4) * 0.9


@sfx
def blade():
    n = n_(0.3)
    x = bandpass_fast(noise_sweep(n, 3000, 12000), 2000, 9000) * env_adsr(n, 0.02, 0.05, 0.4, 0.15, gate=n_(0.1))
    return mix(x * 0.8, bell(3200, 0.3, decay=0.15) * 0.15)


@sfx
def warp():
    n = n_(0.45)
    t = np.arange(n) / SR
    f = 400 + 800 * np.sin(np.pi * t / 0.45) + 60 * np.sin(2 * np.pi * 25 * t)
    return pulse(f, 0.25) * env_adsr(n, 0.02, 0.1, 0.6, 0.15, gate=n_(0.3)) * 0.35


@sfx
def stun():
    out = silence(0.7)
    for i in range(4):
        place(out, tone(sweep(2400, 3200, 0.06), 0.07, "sine", decay=0.03) * 0.35, i * 0.12)
    return out


@sfx
def clink():
    return mix(bell(1800, 0.35, ((1, 1), (2.4, 0.5), (4.1, 0.3)), 0.12) * 0.5, burst(0.02, SR, 0.004) * 0.3)


@sfx
def gate():
    n = n_(0.9)
    x = lowpass_fast(noise(n, 2000), 500) * env_adsr(n, 0.05, 0.2, 0.7, 0.3, gate=n_(0.6))
    out = silence(1.0)
    place(out, x * 0.9, 0)
    place(out, kick(0.3, 90, 30), 0.65)
    return out


@sfx
def lever():
    out = silence(0.3)
    place(out, burst(0.03, SR, 0.008, hp=2000) * 0.6, 0)
    place(out, kick(0.12, 200, 80) * 0.6, 0.08)
    place(out, burst(0.03, 6000, 0.01) * 0.5, 0.08)
    return out


@sfx
def plate():
    out = silence(0.5)
    place(out, kick(0.1, 180, 90) * 0.5, 0)
    place(out, bell(1320, 0.4, decay=0.2) * 0.3, 0.03)
    return out


@sfx
def rock_break():
    out = silence(0.8)
    for i in range(4):
        place(out, burst(0.2, 4000 - i * 600, 0.06, lp=4000) * 0.8, i * 0.05)
    place(out, kick(0.35, 120, 30), 0)
    return softclip(out, 1.3)


@sfx
def build():
    out = silence(1.1)
    for i in range(3):
        place(out, kick(0.08, 400, 150) * 0.6, i * 0.15)
        place(out, burst(0.03, SR, 0.01, hp=1500) * 0.5, i * 0.15)
    place(out, seq(["C6", "E6", "G6"], 0.06, "pulse", 0.25, 0.15) * 0.4, 0.5)
    return echo(out, 0.1, 0.25, 0.25)


@sfx
def crystal():
    out = silence(1.2)
    for i, f in enumerate([1760, 2217, 2637, 3520]):
        place(out, bell(f, 0.8, decay=0.4) * 0.2, i * 0.04)
    return reverb(out, 0.4)


@sfx
def cart():
    n = n_(1.4)
    t = np.arange(n) / SR
    x = lowpass_fast(noise(n, 3000), 700) * (0.6 + 0.4 * (np.sin(2 * np.pi * 9 * t) > 0))
    return x * env_adsr(n, 0.1, 0.1, 0.8, 0.4, gate=n_(1.0)) * 0.7


@sfx
def pot():
    out = silence(0.5)
    place(out, burst(0.25, SR, 0.06, hp=1200) * 0.7, 0)
    place(out, bell(900, 0.25, ((1, 1), (2.7, 0.6), (5.1, 0.4)), 0.07) * 0.3, 0)
    return out


@sfx
def door():
    n = n_(0.4)
    x = bandpass_fast(noise_sweep(n, 200, 600), 150, 1200) * env_adsr(n, 0.02, 0.1, 0.5, 0.15, gate=n_(0.25))
    out = silence(0.5)
    place(out, x * 0.8, 0)
    place(out, kick(0.12, 150, 60) * 0.5, 0.3)
    return out


@sfx
def rank():
    out = silence(1.0)
    place(out, kick(0.3, 160, 40) * 1.1, 0)
    place(out, burst(0.1, 8000, 0.03) * 0.4, 0)
    for nt in ["C5", "G5", "C6", "E6"]:
        place(out, tone(nt, 0.6, "pulse", 0.25, decay=0.3) * 0.2, 0.05)
    return reverb(out, 0.3)


@sfx
def unlock():
    out = silence(1.0)
    place(out, seq(["G5", "C6", "E6", "G6", "C7"], 0.06, "pulse", 0.25, 0.15) * 0.4, 0)
    return echo(out, 0.12, 0.3, 0.3)


@sfx
def stage_select():
    out = silence(0.8)
    place(out, seq(["C5", "G5", "C6"], 0.05, "pulse", 0.25, 0.1) * 0.5, 0)
    place(out, bandpass_fast(noise_sweep(n_(0.3), 1000, 8000), 500, 7000) * env_exp(n_(0.3), 0.1) * 0.4, 0.1)
    return out


@sfx
def star():
    out = silence(1.4)
    for i, nt in enumerate(["C6", "E6", "G6", "B6", "D7", "G7"]):
        place(out, tone(nt, 0.25, "pulse", 0.125, decay=0.12) * 0.3, i * 0.06)
        place(out, bell(hz(midi(nt)) * 2, 0.3, decay=0.12) * 0.1, i * 0.06)
    return reverb(out, 0.4)


@sfx
def timestop_charge():
    n = n_(1.1)
    t = np.arange(n) / SR
    f = 200 * np.exp(t * 2.0)
    x = pulse(f, 0.5) * (0.5 + 0.5 * np.sin(2 * np.pi * (4 + 20 * t) * t)) * np.linspace(0.2, 1, n)
    return x * 0.3


@sfx
def timestop():
    n = n_(0.9)
    t = np.arange(n) / SR
    x = mix(sine(900 * np.exp(-t * 4) + 60) * env_exp(n, 0.4) * 0.6, bell(440, 0.9, decay=0.6) * 0.3)
    return reverb(x, 0.5)


@sfx
def dodge():
    out = silence(0.6)
    place(out, dash() * 0.8, 0)
    place(out, bell(2637, 0.4, decay=0.2) * 0.3, 0.08)
    return out


@sfx
def respawn():
    out = silence(1.0)
    place(out, seq(["C5", "G5", "C6", "E6"], 0.08, "sine", 0.5, 0.3) * 0.5, 0)
    return reverb(out, 0.35)


@sfx
def hero_down():
    out = silence(1.3)
    place(out, seq(["E5", "D5", "C5", "A4", "G4", "E4"], 0.1, "pulse", 0.5, 0.2) * 0.45, 0)
    place(out, kick(0.3, 120, 30), 0)
    return reverb(out, 0.3)


@sfx
def rumble():
    n = n_(1.8)
    x = lowpass_fast(noise(n, 1500), 200) * env_adsr(n, 0.3, 0.3, 0.8, 0.6, gate=n_(1.2)) * 1.6
    return softclip(x, 1.5)


@sfx
def lava_flood():
    n = n_(2.0)
    x = lowpass_fast(noise(n, 1200), 250) * env_adsr(n, 0.2, 0.3, 0.8, 0.8, gate=n_(1.2)) * 1.4
    out = silence(2.2)
    place(out, softclip(x, 1.5), 0)
    for i in range(12):
        place(out, squish() * 0.35, 0.1 + i * 0.13)
    return out


@sfx
def buy():
    out = silence(0.6)
    place(out, coin(), 0)
    place(out, bell(2093, 0.4, decay=0.2) * 0.3, 0.1)
    return out


@sfx
def heartbeat_fast():
    return heartbeat()


def main():
    names = sys.argv[1:] or list(SFX.keys())
    for nm in names:
        x = SFX[nm]()
        # loudness match: RMS of the loudest 80 ms window -> target, peaks limited
        w = max(1, int(0.08 * SR))
        if len(x) > w:
            e = np.sqrt(np.convolve(x * x, np.ones(w) / w, mode="valid"))
            loud = float(e.max())
        else:
            loud = float(np.sqrt(np.mean(x * x)))
        x = x * (0.25 / (loud + 1e-9))
        x = np.tanh(x * 1.2) / np.tanh(1.2) * 0.95 if np.max(np.abs(x)) > 0.95 else x
        x = fade(x, 0.001, 0.01)
        write_wav(os.path.join(OUT, nm + ".wav"), x.astype(np.float64))
    print("sfx:", len(names))


if __name__ == "__main__":
    main()
