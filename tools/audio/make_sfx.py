#!/usr/bin/env python3
"""
make_sfx.py -- the hatch reveal's sound pack, synthesized (numpy + scipy).

Owner, 2026-10-05: "different sounds for different rarities drawn and a more
involved sequence when a legendary or higher is drawn". Everything is made here
from oscillators and noise (no samples, nothing licensed, nothing that can trip
moderation) and written back to back into ONE audio file, so the whole pack is a
single upload. The game plays each sound's own stretch of it with
Sound.PlaybackRegion (src/client/Sfx.luau).

  assets/audio/hatch_sfx.ogg      the pack (Vorbis, stereo, 44.1 kHz)
  assets/audio/preview_sfx.png    waveform of each sound, for a quick look
  src/shared/Config/Sounds.luau   the regions block between its BEGIN/END markers
                                  is rewritten with each sound's start and length

Sounds:
  Common .. Secret, Junk   the reveal stinger for each rarity: more notes, brighter
                           instruments and more space as rarity climbs; brass from
                           Legendary, a choir from Mythic, Junk is a cartoon boing
  Riser                    builds under a Legendary+ reel as it slows
  Heartbeat                the pause between the reel stopping and the reveal
  Impact                   the reveal hit for Legendary+
  Whoosh, Tick             the reel starting, and each card passing the marker
  Mutation, Shine          a mutation's banner, and a finish (Gold and up)

Usage:  python tools/audio/make_sfx.py          (needs: pip install numpy scipy soundfile)
Then upload assets/audio/hatch_sfx.ogg (Creator Hub -> Audio) and paste its id into
Config/Sounds.luau `id`.
"""

import os
import re
import sys

import numpy as np
import soundfile
from scipy import signal

SR = 44100
GAP = 0.35  # silence between sounds, seconds
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
rng = np.random.default_rng(2026)


def secs(dur):
    return np.arange(int(round(dur * SR))) / SR


def hz(note):
    """'C5' / 'F#4' / 'Bb3' -> frequency."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    m = re.fullmatch(r"([A-G])([#b]?)(-?\d)", note)
    semis = names[m.group(1)] + {"#": 1, "b": -1, "": 0}[m.group(2)] + 12 * (int(m.group(3)) + 1)
    return 440.0 * 2 ** ((semis - 69) / 12)


class Track:
    """A stereo buffer that sounds are mixed into at given times."""

    def __init__(self, dur):
        self.buf = np.zeros((int(round(dur * SR)), 2))

    def add(self, mono, at=0.0, gain=1.0, pan=0.0):
        start = int(round(at * SR))
        end = min(len(self.buf), start + len(mono))
        if end <= start:
            return
        piece = mono[: end - start] * gain
        left = np.cos((pan + 1) * np.pi / 4)
        right = np.sin((pan + 1) * np.pi / 4)
        self.buf[start:end, 0] += piece * left * 1.41
        self.buf[start:end, 1] += piece * right * 1.41

    def add_stereo(self, stereo, at=0.0, gain=1.0):
        start = int(round(at * SR))
        end = min(len(self.buf), start + len(stereo))
        self.buf[start:end] += stereo[: end - start] * gain


# ---------------------------------------------------------------------------
# Instruments
# ---------------------------------------------------------------------------


def envelope(n, attack=0.005, release=0.05):
    env = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    env[:a] = np.linspace(0, 1, a)
    env[-r:] *= np.linspace(1, 0, r)
    return env


def marimba(f, dur=1.0):
    t = secs(dur)
    out = np.zeros_like(t)
    for ratio, amp, decay in ((1, 1.0, 0.45), (3.93, 0.35, 0.09), (9.2, 0.12, 0.03)):
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / decay)
    click = rng.standard_normal(int(0.004 * SR)) * np.linspace(1, 0, int(0.004 * SR)) * 0.15
    out[: len(click)] += click
    return out * envelope(len(t), 0.001, 0.03)


def glock(f, dur=1.6):
    t = secs(dur)
    out = np.zeros_like(t)
    for ratio, amp, decay in ((1, 1.0, 0.9), (2.76, 0.45, 0.35), (5.40, 0.22, 0.14), (8.93, 0.1, 0.06)):
        out += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / decay)
    return out * envelope(len(t), 0.001, 0.05)


def bell(f, dur=2.5, index=5.0, ratio=3.5, decay=1.1):
    """FM bell: a carrier modulated at an inharmonic ratio, the brightness dying away."""
    t = secs(dur)
    mod_index = index * np.exp(-t / (decay * 0.5))
    mod = np.sin(2 * np.pi * f * ratio * t) * mod_index
    out = np.sin(2 * np.pi * f * t + mod) * np.exp(-t / decay)
    return out * envelope(len(t), 0.002, 0.1)


def saw(f, t, phase=0.0):
    return 2 * ((f * t + phase) % 1.0) - 1


def lowpass(x, cutoff, order=2):
    sos = signal.butter(order, min(cutoff, SR * 0.45), "low", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def highpass(x, cutoff, order=2):
    sos = signal.butter(order, cutoff, "high", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def bandpass(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR * 0.45)], "band", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def brass(f, dur, attack=0.04, bright=1.0):
    """Three detuned saws; a bright copy fades in on the attack and settles (a filter swell)."""
    t = secs(dur)
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    raw = sum(saw(f * vib * 2 ** (cents / 1200), t, rng.random()) for cents in (-7, 0, 6)) / 3
    dark = lowpass(raw, f * 2.5)
    lit = lowpass(raw, min(f * 9 * bright, 7000))
    swell = np.clip(t / attack, 0, 1) * (0.55 + 0.45 * np.exp(-t / 0.35))
    out = dark * (1 - swell) + lit * swell
    amp = np.clip(t / attack, 0, 1) * (0.8 + 0.2 * np.exp(-t / 0.2))
    return out * amp * envelope(len(t), 0.01, min(0.25, dur * 0.4))


def pad(notes, dur, attack=0.35, cutoff=2200, choir=0.0):
    """Detuned saws per note, soft and wide; `choir` adds an "ah" from two formant bands."""
    t = secs(dur)
    out = np.zeros_like(t)
    for note in notes:
        f = hz(note) if isinstance(note, str) else note
        for cents in (-10, -4, 3, 9):
            out += saw(f * 2 ** (cents / 1200), t, rng.random())
    out /= 4 * len(notes)
    soft = lowpass(out, cutoff)
    if choir > 0:
        ah = bandpass(out, 600, 900) * 2.2 + bandpass(out, 1000, 1300) * 1.4 + bandpass(out, 2400, 2800) * 0.6
        soft = soft * (1 - choir) + ah * choir
    return soft * envelope(len(t), attack, min(0.9, dur * 0.45))


def noise_sweep(dur, f0, f1, width=0.35, curve=1.0):
    """Noise through a band that slides from f0 to f1 (log scale): whooshes and risers."""
    n = int(dur * SR)
    noise = rng.standard_normal(n + 4096)
    f, frames, spec = signal.stft(noise, SR, nperseg=2048, noverlap=1536)
    progress = np.clip(frames / dur, 0, 1) ** curve
    centers = np.exp(np.log(f0) + (np.log(f1) - np.log(f0)) * progress)
    logf = np.log(np.maximum(f, 1))[:, None]
    mask = np.exp(-0.5 * ((logf - np.log(centers)[None, :]) / width) ** 2)
    _, out = signal.istft(spec * mask, SR, nperseg=2048, noverlap=1536)
    out = out[:n]
    return out / (np.abs(out).max() + 1e-9)


def boom(dur=1.6, f0=95, f1=32, drive=2.5):
    t = secs(dur)
    freq = f1 + (f0 - f1) * np.exp(-t / 0.18)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    body = np.tanh(np.sin(phase) * drive) * np.exp(-t / 0.55)
    crack = lowpass(rng.standard_normal(len(t)), 1800) * np.exp(-t / 0.05) * 0.8
    return (body + crack) * envelope(len(t), 0.001, 0.2)


def thump(f=58, dur=0.35):
    t = secs(dur)
    freq = f * (1 + 0.6 * np.exp(-t / 0.03))
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t / 0.09) * envelope(len(t), 0.002, 0.05)


def shimmer(track, at, dur, density=14, low="C6", high="E7", gain=0.12):
    """A scatter of tiny high glock notes from a pentatonic set, spread across the stereo field."""
    scale = [0, 2, 4, 7, 9]
    lo, hi = hz(low), hz(high)
    notes = [f for octave in range(3, 9) for s in scale if lo <= (f := 440 * 2 ** ((octave * 12 + s - 57) / 12)) <= hi]
    for _ in range(int(density * dur)):
        when = at + rng.random() * dur
        fade = 1 - (when - at) / dur
        track.add(glock(rng.choice(notes), 0.6), when, gain * (0.4 + 0.6 * fade), rng.uniform(-0.8, 0.8))


def reverb(stereo, wet=0.25, decay=1.6, predelay=0.012):
    """Convolution with decorrelated, exponentially decaying noise (a soft hall)."""
    n = int(decay * 2.2 * SR)
    t = np.arange(n) / SR
    ir = []
    for _ in range(2):
        tail = rng.standard_normal(n) * np.exp(-t * 6.9 / decay)
        tail = lowpass(tail, 6500) + 0.0
        tail = np.concatenate([np.zeros(int(predelay * SR)), tail])
        ir.append(tail / np.sqrt(np.sum(tail**2)))
    out = stereo.copy()
    for ch in range(2):
        out[:, ch] += wet * signal.fftconvolve(stereo[:, ch], ir[ch])[: len(stereo)]
    return out


def finish(track, peak=0.89, wet=0.22, decay=1.5):
    out = reverb(track.buf, wet, decay)
    # gentle limiter, then normalize
    out = np.tanh(out * 1.1) / np.tanh(1.1)
    out *= peak / (np.abs(out).max() + 1e-9)
    tail = int(0.03 * SR)
    out[-tail:] *= np.linspace(1, 0, tail)[:, None]
    return out


# ---------------------------------------------------------------------------
# The sounds
# ---------------------------------------------------------------------------


def common():
    tr = Track(1.0)
    tr.add(marimba(hz("C5"), 0.9), 0.0, 0.8)
    tr.add(marimba(hz("C6"), 0.5), 0.0, 0.15)
    return finish(tr, peak=0.6, wet=0.15, decay=0.9)


def uncommon():
    tr = Track(1.2)
    tr.add(marimba(hz("C5"), 0.9), 0.0, 0.7, -0.15)
    tr.add(marimba(hz("G5"), 0.9), 0.11, 0.7, 0.15)
    tr.add(glock(hz("G6"), 0.8), 0.11, 0.12)
    return finish(tr, peak=0.66, wet=0.17, decay=1.0)


def rare():
    tr = Track(1.7)
    for i, note in enumerate(("C5", "E5", "G5")):
        tr.add(glock(hz(note), 1.2), i * 0.09, 0.55, -0.3 + 0.3 * i)
        tr.add(marimba(hz(note), 0.8), i * 0.09, 0.35)
    shimmer(tr, 0.3, 1.0, density=10, gain=0.08)
    return finish(tr, peak=0.72, wet=0.22, decay=1.3)


def epic():
    tr = Track(2.4)
    tr.add(noise_sweep(0.35, 400, 5000, curve=1.6) * np.linspace(0, 1, int(0.35 * SR)), 0.0, 0.16)
    for i, note in enumerate(("C5", "E5", "G5", "C6")):
        tr.add(bell(hz(note), 1.8, index=3.5, ratio=3.0, decay=0.8), 0.32 + i * 0.08, 0.32, -0.45 + 0.3 * i)
        tr.add(glock(hz(note) * 2, 0.8), 0.32 + i * 0.08, 0.12)
    tr.add(pad(["C4", "E4", "G4", "C5"], 1.8, attack=0.15, cutoff=2600), 0.32, 0.4)
    shimmer(tr, 0.55, 1.5, density=14, gain=0.09)
    return finish(tr, peak=0.78, wet=0.26, decay=1.6)


def fanfare(tr, at, pickup, chord, gain=1.0, bright=1.0):
    """da-da-DAAA: three short pickup notes, then the chord held."""
    for i in range(3):
        tr.add(brass(hz(pickup), 0.11, attack=0.02, bright=bright), at + i * 0.12, 0.42 * gain)
    for j, note in enumerate(chord):
        tr.add(brass(hz(note), 2.0, attack=0.05, bright=bright), at + 0.38, 0.32 * gain, -0.4 + 0.8 * j / max(1, len(chord) - 1))


def legendary():
    tr = Track(3.8)
    tr.add(boom(1.2, f0=80, f1=40, drive=1.6), 0.0, 0.55)
    fanfare(tr, 0.05, "G4", ["C4", "E4", "G4", "C5"])
    tr.add(noise_sweep(1.6, 3000, 9000, width=0.5) * np.exp(-secs(1.6) / 0.6), 0.43, 0.12)  # cymbal
    for i, note in enumerate(("G6", "E6", "C6", "G5", "C6", "E6", "G6", "C7")):
        tr.add(bell(hz(note), 1.4, index=2.5, ratio=3.5, decay=0.7), 0.5 + i * 0.07, 0.13, -0.6 + 0.15 * i)
    shimmer(tr, 0.9, 2.4, density=16, gain=0.1)
    return finish(tr, peak=0.86, wet=0.3, decay=2.0)


def mythic():
    tr = Track(4.3)
    tr.add(boom(1.4, f0=85, f1=36, drive=2.0), 0.0, 0.6)
    fanfare(tr, 0.05, "A4", ["D4", "F#4", "A4", "D5"], gain=1.05, bright=1.2)
    tr.add(pad(["D4", "F#4", "A4", "D5", "A5"], 3.4, attack=0.4, cutoff=3000, choir=0.75), 0.4, 0.55)
    for i, note in enumerate(("A5", "D6", "F#6", "A6", "D7")):
        tr.add(bell(hz(note), 1.8, index=3, ratio=3.5, decay=0.9), 0.45 + i * 0.09, 0.14, -0.5 + 0.25 * i)
    tr.add(noise_sweep(2.0, 4000, 10000, width=0.5) * np.exp(-secs(2.0) / 0.8), 0.43, 0.13)
    shimmer(tr, 0.9, 3.0, density=18, gain=0.11)
    return finish(tr, peak=0.88, wet=0.34, decay=2.4)


def celestial():
    tr = Track(4.7)
    cascade = ("E7", "D7", "B6", "A6", "G6", "E6", "D6", "E6", "G6", "B6", "E7")
    for i, note in enumerate(cascade):
        tr.add(bell(hz(note), 2.0, index=2.0, ratio=2.0, decay=1.2), i * 0.085, 0.16, np.sin(i * 0.9) * 0.7)
    tr.add(pad(["E4", "B4", "E5", "F#5", "G#5"], 4.2, attack=0.6, cutoff=3800, choir=0.85), 0.15, 0.6)
    tr.add(thump(70, 0.5), 0.0, 0.35)
    shimmer(tr, 0.2, 4.0, density=22, low="E6", high="E7", gain=0.11)
    return finish(tr, peak=0.84, wet=0.42, decay=3.0)


def cosmic():
    tr = Track(5.1)
    tr.add(boom(2.0, f0=70, f1=26, drive=3.0), 0.0, 0.85)
    tr.add(noise_sweep(1.6, 9000, 300, width=0.45, curve=0.7) * np.exp(-secs(1.6) / 0.7), 0.05, 0.22)
    tr.add(pad(["C3", "G3", "C4", "Eb4"], 1.3, attack=0.3, cutoff=1600, choir=0.4), 0.2, 0.55)
    tr.add(pad(["C3", "G3", "C4", "E4", "G4", "C5"], 3.4, attack=0.25, cutoff=3200, choir=0.6), 1.35, 0.6)
    for i, note in enumerate(("C6", "G6", "C7", "E7")):
        tr.add(bell(hz(note), 2.2, index=4, ratio=1.41, decay=1.1), 1.35 + i * 0.12, 0.15, -0.6 + 0.4 * i)
    tr.add(brass(hz("C4"), 2.5, attack=0.12, bright=0.8), 1.35, 0.3)
    shimmer(tr, 1.4, 3.4, density=20, gain=0.1)
    return finish(tr, peak=0.9, wet=0.4, decay=3.0)


def secret():
    tr = Track(5.2)
    t = secs(1.6)
    drone = (np.sin(2 * np.pi * hz("A2") * t) + 0.4 * np.sin(2 * np.pi * hz("E3") * t)) * envelope(len(t), 0.3, 0.4)
    tr.add(lowpass(drone, 600), 0.0, 0.5)
    for i, note in enumerate(("A4", "C5", "E5", "C5")):
        tr.add(bell(hz(note), 1.4, index=2, ratio=2.0, decay=0.8), 0.1 + i * 0.3, 0.2, -0.3 + 0.2 * i)
    # the resolve: A major, everything at once
    tr.add(boom(1.8, f0=90, f1=30, drive=2.6), 1.55, 0.75)
    fanfare(tr, 1.2, "E4", ["A3", "C#4", "E4", "A4"], gain=1.0, bright=1.1)
    tr.add(pad(["A3", "C#4", "E4", "A4", "C#5"], 3.4, attack=0.2, cutoff=3200, choir=0.7), 1.58, 0.55)
    shimmer(tr, 1.7, 3.3, density=20, gain=0.11)
    return finish(tr, peak=0.9, wet=0.36, decay=2.6)


def junk():
    tr = Track(1.7)
    t = secs(0.7)
    f = 190 * (1 + 0.5 * np.exp(-t / 0.18) * np.sin(2 * np.pi * 13 * t)) * (1 + 0.25 * t)
    boing = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.3)
    tr.add(boing * envelope(len(t), 0.003, 0.05), 0.0, 0.7)
    t2 = secs(0.55)
    slide = 520 * 2 ** (1.4 * t2 / 0.55) * (1 + 0.012 * np.sin(2 * np.pi * 7 * t2))
    whistle = np.sin(2 * np.pi * np.cumsum(slide) / SR) * envelope(len(t2), 0.05, 0.08)
    tr.add(whistle, 0.55, 0.32)
    tr.add(marimba(hz("C6"), 0.4), 1.12, 0.4)  # pop
    return finish(tr, peak=0.7, wet=0.12, decay=0.8)


def riser():
    dur = 3.0
    tr = Track(dur)
    t = secs(dur)
    swell = (t / dur) ** 2.2
    tr.add(noise_sweep(dur, 250, 7000, width=0.3, curve=1.4) * swell, 0.0, 0.5)
    freq = 110 * 2 ** (3 * (t / dur) ** 1.3)
    tone = sum(saw(freq * k, t) / k for k in (1, 2.01)) * swell
    trem = 0.6 + 0.4 * np.sin(2 * np.pi * np.cumsum(4 + 18 * (t / dur) ** 2) / SR)
    tr.add(lowpass(tone * trem, 2500), 0.0, 0.28)
    out = finish(tr, peak=0.8, wet=0.12, decay=1.0)
    out[-int(0.01 * SR) :] *= np.linspace(1, 0, int(0.01 * SR))[:, None]
    return out


def impact():
    tr = Track(1.9)
    tr.add(boom(1.8, f0=110, f1=30, drive=3.2), 0.0, 0.95)
    tr.add(noise_sweep(1.2, 6000, 1500, width=0.6) * np.exp(-secs(1.2) / 0.25), 0.0, 0.35)
    return finish(tr, peak=0.92, wet=0.3, decay=1.8)


def heartbeat():
    tr = Track(1.35)
    for beat in (0.0, 0.7):
        tr.add(thump(55, 0.35), beat, 1.0)
        tr.add(thump(50, 0.3), beat + 0.22, 0.7)
    return finish(tr, peak=0.85, wet=0.08, decay=0.7)


def whoosh():
    dur = 0.6
    tr = Track(dur)
    body = noise_sweep(dur, 300, 3500, width=0.4, curve=0.8) * np.sin(np.pi * secs(dur) / dur) ** 1.5
    tr.add(body, 0.0, 0.6, -0.5)
    tr.add(body, 0.04, 0.6, 0.5)
    return finish(tr, peak=0.6, wet=0.1, decay=0.6)


def tick():
    tr = Track(0.06)
    n = int(0.006 * SR)
    tr.add(bandpass(rng.standard_normal(n), 2200, 5200) * np.linspace(1, 0, n), 0.0, 0.8)
    t = secs(0.04)
    tr.add(np.sin(2 * np.pi * 1700 * t) * np.exp(-t / 0.008), 0.0, 0.6)
    return finish(tr, peak=0.55, wet=0.0, decay=0.3)


def mutation():
    tr = Track(2.4)
    for i, note in enumerate(("C5", "D5", "E5", "F#5", "G#5", "A#5", "C6", "D6")):
        tr.add(bell(hz(note), 1.4, index=3, ratio=1.41, decay=0.7), i * 0.055, 0.18, -0.6 + 0.17 * i)
    tr.add(pad(["C4", "E4", "G#4", "D5"], 2.0, attack=0.25, cutoff=3000, choir=0.8), 0.25, 0.45)
    shimmer(tr, 0.3, 1.9, density=20, gain=0.1)
    return finish(tr, peak=0.82, wet=0.35, decay=2.0)


def shine():
    tr = Track(1.1)
    tr.add(noise_sweep(0.5, 5000, 11000, width=0.4) * np.exp(-secs(0.5) / 0.15), 0.0, 0.25)
    tr.add(glock(hz("E7"), 0.9), 0.0, 0.3, -0.3)
    tr.add(glock(hz("B7"), 0.9), 0.06, 0.25, 0.3)
    shimmer(tr, 0.1, 0.8, density=16, low="E6", high="E7", gain=0.08)
    return finish(tr, peak=0.6, wet=0.25, decay=1.2)


# (name, maker, loudness in dB RMS): the stingers get louder as rarity climbs
SOUNDS = [
    ("Common", common, -18),
    ("Uncommon", uncommon, -17),
    ("Rare", rare, -16),
    ("Epic", epic, -15),
    ("Legendary", legendary, -13.5),
    ("Mythic", mythic, -13),
    ("Celestial", celestial, -13),
    ("Cosmic", cosmic, -12.5),
    ("Secret", secret, -12.5),
    ("Junk", junk, -15),
    ("Riser", riser, -19),
    ("Impact", impact, -11.5),
    ("Heartbeat", heartbeat, -14),
    ("Whoosh", whoosh, -20),
    ("Tick", tick, -23),
    ("Mutation", mutation, -14.5),
    ("Shine", shine, -18),
]


def loudness(audio, target_db):
    rms = np.sqrt(np.mean(audio**2)) + 1e-9
    audio = audio * (10 ** (target_db / 20) / rms)
    peak = np.abs(audio).max()
    if peak > 0.95:  # a soft knee rather than clipping
        audio = np.tanh(audio / peak * 1.5) / np.tanh(1.5) * 0.95
    return audio


def write_regions(regions):
    path = os.path.join(ROOT, "src/shared/Config/Sounds.luau")
    text = open(path, encoding="utf-8").read()
    lines = [f"\t\t{name} = {{ {start:.3f}, {length:.3f} }}," for name, start, length in regions]
    block = "\n".join(lines)
    new, count = re.subn(
        r"(-- BEGIN REGIONS[^\n]*\n).*?(\t*-- END REGIONS)",
        lambda m: m.group(1) + block + "\n" + m.group(2),
        text,
        flags=re.S,
    )
    if count != 1:
        sys.exit("Config/Sounds.luau: BEGIN/END REGIONS markers not found")
    open(path, "w", encoding="utf-8").write(new)


def preview(pieces, path):
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        return
    rows = len(pieces)
    width, height = 1400, 54
    im = Image.new("RGB", (width, rows * height), (22, 22, 30))
    draw = ImageDraw.Draw(im)
    longest = max(len(p) for _, p in pieces)
    for row, (name, audio) in enumerate(pieces):
        mono = audio.mean(axis=1)
        cols = max(1, int(len(mono) / longest * (width - 120)))
        chunks = np.array_split(np.abs(mono), cols)
        y0 = row * height + height // 2
        for x, chunk in enumerate(chunks):
            h = float(chunk.max()) * (height / 2 - 4)
            draw.line([(120 + x, y0 - h), (120 + x, y0 + h)], fill=(120, 200, 255))
        draw.text((8, y0 - 6), name, fill=(255, 220, 120))
    im.save(path)


def main():
    out_dir = os.path.join(ROOT, "assets/audio")
    os.makedirs(out_dir, exist_ok=True)
    pieces = []
    regions = []
    cursor = 0.0
    chunks = [np.zeros((int(0.1 * SR), 2))]
    cursor = 0.1
    for name, make, target in SOUNDS:
        audio = loudness(make(), target)
        pieces.append((name, audio))
        length = len(audio) / SR
        regions.append((name, cursor, length))
        chunks.append(audio)
        chunks.append(np.zeros((int(GAP * SR), 2)))
        cursor += length + GAP
        print(f"{name:10s} {length:5.2f} s  peak {np.abs(audio).max():.2f}")
    # Vorbis overshoots the peaks a little; leave it headroom
    pack = (np.concatenate(chunks) * 0.9).astype(np.float32)
    path = os.path.join(out_dir, "hatch_sfx.ogg")
    # libsndfile's Vorbis encoder crashes on one big write; feed it in blocks
    with soundfile.SoundFile(path, "w", SR, 2, format="OGG", subtype="VORBIS") as f:
        for start in range(0, len(pack), 8192):
            f.write(pack[start : start + 8192])
    preview(pieces, os.path.join(out_dir, "preview_sfx.png"))
    write_regions(regions)
    print(f"wrote {path} ({len(pack) / SR:.1f} s, {os.path.getsize(path) // 1024} KB) and Config/Sounds.luau regions")


if __name__ == "__main__":
    main()
