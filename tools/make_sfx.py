"""Synthesises the soft whoosh effects. Standard library only.

    python3 tools/make_sfx.py

Writes assets/audio/forward/{rewind,reverse,door}.wav. These replace the old pure-tone
sweeps, which read as harsh, signal-like "woooo"s: each is now band-passed noise with a
smooth envelope and only a faint tonal layer underneath.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "forward"


def save(name: str, buf: list, peak: float) -> None:
    top = max(abs(v) for v in buf) or 1.0
    k = peak / top
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, v * k)) * 32767)) for v in buf))


def swept_noise(dur: float, f0: float, f1: float, q: float, env, seed: int) -> list:
    """Noise through a state-variable band-pass whose centre glides f0 -> f1 (exponentially)."""
    rng = random.Random(seed)
    n = int(dur * RATE)
    low = band = 0.0
    damp = 1.0 / q
    out = []
    for i in range(n):
        t = i / n
        fc = f0 * (f1 / f0) ** t
        f = 2.0 * math.sin(math.pi * min(fc, RATE / 6) / RATE)
        x = rng.uniform(-1.0, 1.0)
        low += f * band
        high = x - low - damp * band
        band += f * high
        out.append(band * env(t))
    return out


def soft_tone(dur: float, f0: float, f1: float, env) -> list:
    n = int(dur * RATE)
    phase = 0.0
    out = []
    for i in range(n):
        t = i / n
        phase += 2 * math.pi * (f0 * (f1 / f0) ** t) / RATE
        out.append(math.sin(phase) * env(t))
    return out


def mix(*layers) -> list:
    n = max(len(l) for _, l in layers)
    buf = [0.0] * n
    for gain, l in layers:
        for i, v in enumerate(l):
            buf[i] += v * gain
    return buf


def smooth(rise: float, fall_from: float):
    """Envelope: sine-eased rise over [0, rise], hold, sine-eased fall from fall_from to 1."""
    def env(t: float) -> float:
        if t < rise:
            return math.sin(0.5 * math.pi * t / rise) ** 2
        if t > fall_from:
            return math.cos(0.5 * math.pi * (t - fall_from) / (1.0 - fall_from)) ** 2
        return 1.0
    return env


def rewind() -> None:
    """A soft air whoosh falling in pitch, like a tape spooling back."""
    dur = 0.6
    air = swept_noise(dur, 2600, 500, 2.2, smooth(0.15, 0.4), 1)
    hum = soft_tone(dur, 330, 180, smooth(0.25, 0.3))
    save("rewind", mix((1.0, air), (0.05, hum)), 0.7)


def reverse() -> None:
    """A gentle reverse swell rising into a soft cut-off, no shrill top end."""
    dur = 0.45
    def swell(t: float) -> float:
        return (t ** 1.8) * (1.0 if t < 0.88 else math.cos(0.5 * math.pi * (t - 0.88) / 0.12) ** 2)
    air = swept_noise(dur, 500, 1800, 2.0, swell, 2)
    save("reverse", air, 0.65)


def door() -> None:
    """A low stone rumble that swells and settles."""
    dur = 1.0
    rumble = swept_noise(dur, 180, 260, 1.4, smooth(0.25, 0.55), 3)
    grit = swept_noise(dur, 900, 700, 3.0, smooth(0.3, 0.5), 4)
    body = soft_tone(dur, 55, 62, smooth(0.2, 0.5))
    save("door", mix((1.0, rumble), (0.25, grit), (0.18, body)), 0.75)


if __name__ == "__main__":
    rewind()
    reverse()
    door()
