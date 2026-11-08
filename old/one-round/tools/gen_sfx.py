#!/usr/bin/env python3
"""Synthesize placeholder SFX for ONE ROUND.

Writes assets/audio/forward/<name>.wav and a time-reversed copy to
assets/audio/reversed/<name>.wav (NOEL's actions play the reversed one).
Pure standard library, so it runs anywhere: python3 tools/gen_sfx.py
"""
import math
import os
import random
import struct
import wave

RATE = 44100
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
rng = random.Random(7)


def n(seconds):
    return int(RATE * seconds)


def noise(seconds):
    return [rng.uniform(-1.0, 1.0) for _ in range(n(seconds))]


def lowpass(sig, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    a = (1.0 / RATE) / (rc + 1.0 / RATE)
    out, y = [], 0.0
    for x in sig:
        y += a * (x - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    lp = lowpass(sig, cutoff)
    return [x - l for x, l in zip(sig, lp)]


def env_exp(sig, decay, attack=0.002):
    out = []
    for i, x in enumerate(sig):
        t = i / RATE
        a = min(1.0, t / attack) if attack > 0 else 1.0
        out.append(x * a * math.exp(-t / decay))
    return out


def sweep(seconds, f0, f1, shape="sine"):
    out, phase = [], 0.0
    total = n(seconds)
    for i in range(total):
        f = f0 + (f1 - f0) * (i / total)
        phase += 2 * math.pi * f / RATE
        s = math.sin(phase)
        if shape == "square":
            s = 1.0 if s >= 0 else -1.0
        elif shape == "saw":
            s = ((phase / (2 * math.pi)) % 1.0) * 2 - 1
        out.append(s)
    return out


def tone(seconds, f, shape="sine"):
    return sweep(seconds, f, f, shape)


def mix(*parts):
    length = max(len(p) for p, _ in parts)
    out = [0.0] * length
    for sig, gain in parts:
        for i, x in enumerate(sig):
            out[i] += x * gain
    return out


def pad(sig, seconds_before):
    return [0.0] * n(seconds_before) + sig


def fade_window(sig, attack, release):
    total = len(sig)
    out = []
    for i, x in enumerate(sig):
        t = i / RATE
        a = min(1.0, t / attack) if attack > 0 else 1.0
        r = min(1.0, (total - i) / max(1, n(release)))
        out.append(x * a * r)
    return out


def normalize(sig, peak=0.9):
    m = max(1e-9, max(abs(x) for x in sig))
    return [x * peak / m for x in sig]


def write(name, sig):
    sig = normalize(sig)
    for folder, data in (("forward", sig), ("reversed", list(reversed(sig)))):
        path = os.path.join(ROOT, folder, name + ".wav")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in data))


def main():
    # Revolver shot: hard crack plus a low body thump and a metallic tail.
    crack = env_exp(highpass(noise(0.7), 900), 0.05)
    body = env_exp(lowpass(noise(0.7), 300), 0.12)
    thump = env_exp(sweep(0.7, 120, 40), 0.15)
    ring = env_exp(tone(0.7, 2300), 0.18)
    write("fire", mix((crack, 1.0), (body, 1.2), (thump, 0.9), (ring, 0.08)))

    # Bullet lodging in a wall.
    write("lodge", mix((env_exp(tone(0.25, 880), 0.04), 0.6),
                       (env_exp(lowpass(noise(0.25), 1500), 0.03), 1.0)))

    # Throw whoosh.
    wh = fade_window(lowpass(highpass(noise(0.4), 300), 2500), 0.15, 0.2)
    write("throw", wh)

    # Catch: a click then a cylinder ratchet slowing down.
    clicks = [0.0] * n(0.5)
    t, gap = 0.0, 0.025
    while t < 0.45:
        click = env_exp(highpass(noise(0.03), 2000), 0.004)
        start = n(t)
        for i, x in enumerate(click):
            if start + i < len(clicks):
                clicks[start + i] += x
        t += gap
        gap *= 1.18
    write("catch", mix((clicks, 1.0), (env_exp(tone(0.5, 1400), 0.05), 0.3)))

    # Punch: low thud.
    write("punch", mix((env_exp(lowpass(noise(0.3), 400), 0.06), 1.0),
                       (env_exp(sweep(0.3, 150, 50), 0.08), 0.8)))

    # Glass shatter: noise burst and bright rings.
    shards = env_exp(highpass(noise(1.0), 3000), 0.15)
    rings = mix(*[(env_exp(tone(1.0, f), 0.25 + rng.random() * 0.3), 0.15)
                  for f in (3100, 4200, 5300, 6100, 7700)])
    write("glass", mix((shards, 1.0), (rings, 1.0), (env_exp(lowpass(noise(1.0), 600), 0.05), 0.6)))

    # Enemy shot: a hard laser pew.
    write("enemy_shot", env_exp(mix((sweep(0.3, 1200, 260, "square"), 0.5),
                                    (highpass(noise(0.3), 4000), 0.2)), 0.08))

    # Enemy bullet reversed by NOEL: rising sweep.
    write("reverse", fade_window(mix((sweep(0.45, 200, 1600, "saw"), 0.4),
                                     (sweep(0.45, 400, 3200), 0.3)), 0.02, 0.1))

    # Enemy death: crunch plus downward zap.
    write("enemy_die", mix((env_exp(lowpass(noise(0.6), 1200), 0.08), 1.0),
                           (env_exp(sweep(0.6, 900, 80, "square"), 0.15), 0.35)))

    # Player death: low boom sliding down.
    write("player_die", mix((env_exp(sweep(1.2, 200, 30), 0.4), 1.0),
                            (env_exp(lowpass(noise(1.2), 250), 0.3), 0.8)))

    # Temporal pincer: a slam with a minor chord stab.
    chord = mix(*[(env_exp(tone(1.4, f, "saw"), 0.5), 0.2) for f in (220, 261.6, 329.6, 440)])
    write("pincer", mix((env_exp(lowpass(noise(1.4), 900), 0.12), 1.0),
                        (env_exp(sweep(1.4, 90, 35), 0.4), 1.0), (lowpass(chord, 3000), 1.0)))

    # Lift door opening: rising hum.
    write("door", fade_window(mix((sweep(1.0, 60, 140, "saw"), 0.4), (sweep(1.0, 120, 280), 0.4)), 0.2, 0.3))

    # UI click and card swoosh-slam.
    write("ui", env_exp(mix((tone(0.06, 1800, "square"), 0.3), (highpass(noise(0.06), 3000), 0.5)), 0.012))
    swoosh = fade_window(lowpass(noise(0.25), 3500), 0.2, 0.02)
    write("card", swoosh + env_exp(mix((lowpass(noise(0.3), 500), 1.0), (sweep(0.3, 110, 50), 0.8)), 0.06))

    # Ping: two-tone beep.
    write("ping", fade_window(tone(0.09, 1320), 0.005, 0.02) + fade_window(tone(0.14, 1760), 0.005, 0.08))

    # Pull / un-throw: a grab whoosh with a low snap at the end.
    write("pull", fade_window(lowpass(highpass(noise(0.35), 500), 3500), 0.25, 0.02)
          + env_exp(lowpass(noise(0.12), 700), 0.03))

    # Restart rewind tape-stop.
    write("rewind", fade_window(sweep(0.6, 900, 60, "saw"), 0.01, 0.2))


if __name__ == "__main__":
    main()
