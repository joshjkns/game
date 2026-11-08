"""Synthesises the game's music loops and the room-clear chime. Standard library only.

    python3 tools/make_audio.py

Writes assets/audio/music/{title,tundra,dunes,tomb}.wav (seamless loops) and
assets/audio/forward/clear.wav. Every track keeps a clock tick-tock in the percussion.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
TABLE_SIZE = 4096
SINE = [math.sin(2 * math.pi * i / TABLE_SIZE) for i in range(TABLE_SIZE)]
ROOT = Path(__file__).resolve().parent.parent / "assets" / "audio"


def hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


class Track:
    def __init__(self, bpm: float, bars: int, seed: int):
        self.beat = 60.0 / bpm
        self.length = int(bars * 4 * self.beat * RATE)
        self.buf = [0.0] * self.length
        self.rng = random.Random(seed)

    def at(self, beat: float) -> int:
        return int(beat * self.beat * RATE)

    def add(self, start: int, samples) -> None:
        # Tails wrap round to the start, so the loop is seamless.
        n = self.length
        buf = self.buf
        for i, v in enumerate(samples):
            buf[(start + i) % n] += v

    # --- Instruments -------------------------------------------------------------

    def tone(self, freq: float, dur: float, vol: float, partials=((1, 1.0),), attack=0.01,
             decay=None, release=0.08, detune=0.0):
        """Additive voice from a sine table. decay = exponential time constant (plucked)."""
        count = int((dur + release) * RATE)
        steps = [(freq * mult * (1 + detune), amp) for mult, amp in partials]
        phases = [0.0] * len(steps)
        out = []
        for i in range(count):
            t = i / RATE
            env = min(1.0, t / attack) if attack > 0 else 1.0
            if decay:
                env *= math.exp(-t / decay)
            if t > dur:
                env *= max(0.0, 1.0 - (t - dur) / release)
            s = 0.0
            for k, (f, amp) in enumerate(steps):
                s += SINE[int(phases[k]) % TABLE_SIZE] * amp
                phases[k] += f * TABLE_SIZE / RATE
            out.append(s * env * vol)
        return out

    def pad(self, beat, beats, notes, vol=0.05):
        for n in notes:
            for d in (-0.003, 0.003):
                self.add(self.at(beat), self.tone(hz(n), beats * self.beat, vol,
                    ((1, 1.0), (2, 0.35), (3, 0.12)), attack=0.6, release=0.8, detune=d))

    def bell(self, beat, note, vol=0.09, decay=0.9):
        self.add(self.at(beat), self.tone(hz(note), 1.6, vol, ((1, 1.0), (2.76, 0.4), (5.4, 0.15)),
            attack=0.002, decay=decay, release=0.05))

    def pluck(self, beat, note, vol=0.25, damp=0.996):
        """Karplus-Strong string: a burst of noise ringing in a short delay line."""
        period = max(2, int(RATE / hz(note)))
        line = [self.rng.uniform(-1, 1) for _ in range(period)]
        out = []
        for i in range(int(1.2 * RATE)):
            j = i % period
            v = line[j]
            line[j] = damp * 0.5 * (v + line[(j + 1) % period])
            out.append(v * vol)
        self.add(self.at(beat), out)

    def saw(self, beat, beats, note, vol=0.06, cutoff=0.18):
        raw = self.tone(hz(note), beats * self.beat * 0.9, 1.0, [(k, 1.0 / k) for k in range(1, 9)],
            attack=0.005, decay=0.25, release=0.04)
        out, y = [], 0.0
        for v in raw:
            y += cutoff * (v - y)
            out.append(y * vol)
        self.add(self.at(beat), out)

    def bass(self, beat, beats, note, vol=0.16):
        raw = self.tone(hz(note), beats * self.beat * 0.85, 1.0, ((1, 1.0), (2, 0.3)), attack=0.005,
            decay=0.6, release=0.05)
        self.add(self.at(beat), [math.tanh(v * 1.6) * vol for v in raw])

    def kick(self, beat, vol=0.5):
        out, phase = [], 0.0
        for i in range(int(0.28 * RATE)):
            t = i / RATE
            f = 45 + 90 * math.exp(-t / 0.03)
            phase += f / RATE
            out.append(math.sin(2 * math.pi * phase) * math.exp(-t / 0.09) * vol)
        self.add(self.at(beat), out)

    def noise(self, beat, length, vol, decay, bright=0.9):
        out, y = [], 0.0
        for i in range(int(length * RATE)):
            n = self.rng.uniform(-1, 1)
            y = bright * n + (1 - bright) * y
            out.append((n - y if bright > 0.5 else y) * math.exp(-i / RATE / decay) * vol)
        self.add(self.at(beat), out)

    def tick(self, beat, vol=0.12):
        self.noise(beat, 0.02, vol, 0.004)

    def tock(self, beat, vol=0.1):
        self.add(self.at(beat), self.tone(1250, 0.03, vol, ((1, 1.0), (2.1, 0.5)), attack=0.001,
            decay=0.012, release=0.01))

    def hat(self, beat, vol=0.05):
        self.noise(beat, 0.05, vol, 0.012)

    def drum(self, beat, vol=0.22):
        """Hand-drum 'dum': a low thump that bends down."""
        out, phase = [], 0.0
        for i in range(int(0.3 * RATE)):
            t = i / RATE
            phase += (95 + 40 * math.exp(-t / 0.04)) / RATE
            out.append(math.sin(2 * math.pi * phase) * math.exp(-t / 0.12) * vol)
        self.add(self.at(beat), out)

    def clock(self, beats, vol=1.0):
        for b in range(beats):
            (self.tick if b % 2 == 0 else self.tock)(b, 0.1 * vol)

    def save(self, path: Path, gain=1.0) -> None:
        peak = max(1e-6, max(abs(v) for v in self.buf))
        k = 0.89 / peak * gain
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, v * k)) * 32767)) for v in self.buf))
        print("wrote", path.relative_to(ROOT.parent.parent), f"{self.length / RATE:.1f}s")


def arp_line(t: Track, chord, beat, count, step, play, octave=12):
    """Climb the chord's notes `count` times, `step` beats apart, wandering an octave now and then."""
    for i in range(count):
        n = chord[i % len(chord)] + octave * (1 if t.rng.random() < 0.25 else 0)
        play(beat + i * step, n)


def title() -> Track:
    t = Track(72, 8, 1)
    chords = [[50, 53, 57], [46, 50, 53], [48, 52, 55], [45, 49, 52]]
    for bar in range(8):
        c = chords[(bar // 2) % 4]
        if bar % 2 == 0:
            t.pad(bar * 4, 8, c, 0.045)
            t.bass(bar * 4, 4, c[0] - 12, 0.1)
        for i in (0, 1.5, 3):
            t.bell(bar * 4 + i, c[int(i) % 3] + 24, 0.05, 1.4)
    t.clock(32, 0.8)
    return t


def tundra() -> Track:
    """Ice Age: slow A minor, glassy bells over a cold pad, a soft kick in the second half."""
    t = Track(84, 16, 2)
    chords = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
    for bar in range(16):
        c = chords[(bar // 2) % 4]
        b = bar * 4
        if bar % 2 == 0:
            t.pad(b, 8, [n - 12 for n in c], 0.04)
            t.bass(b, 2, c[0] - 24)
            t.bass(b + 4, 2, c[0] - 24)
        arp_line(t, c, b, 8, 0.5, lambda at, n: t.bell(at, n + 12, 0.07, 0.7))
        if bar >= 8:
            t.kick(b)
            t.kick(b + 2.5, 0.35)
    t.clock(64)
    return t


def dunes() -> Track:
    """Egypt: a D drone, plucked strings in a bright eastern mode, hand drums."""
    t = Track(100, 16, 3)
    scale = [62, 63, 66, 67, 69, 70, 72, 74]
    for bar in range(16):
        b = bar * 4
        if bar % 4 == 0:
            t.pad(b, 16, [38, 45, 50], 0.04)
        t.bass(b, 1, 38)
        t.bass(b + 1.5, 1, 38)
        t.bass(b + 3, 1, 45 if bar % 2 else 43)
        for i in range(8):
            if t.rng.random() < (0.55 if bar < 8 else 0.8):
                idx = min(7, max(0, (i + bar) % 8 + t.rng.choice((-1, 0, 1))))
                t.pluck(b + i * 0.5, scale[idx], 0.2)
        for at in (0, 1.5, 2.5):
            t.drum(b + at)
        for at in (1, 3, 3.75):
            t.noise(b + at, 0.06, 0.08, 0.02)
    t.clock(64, 0.8)
    return t


def tomb() -> Track:
    """Far Future: driving E minor, filtered saw arpeggios, pulsing bass, four on the floor."""
    t = Track(118, 16, 4)
    chords = [[52, 55, 59], [48, 52, 55], [50, 54, 57], [47, 50, 54]]
    for bar in range(16):
        c = chords[(bar // 2) % 4]
        b = bar * 4
        if bar % 2 == 0:
            t.pad(b, 8, c, 0.03)
        for i in range(8):
            t.bass(b + i * 0.5, 0.5, c[0] - 24 + (12 if i % 4 == 3 else 0), 0.12)
        arp_line(t, c + [c[0] + 12], b, 16, 0.25, lambda at, n: t.saw(at, 0.25, n + 12, 0.05,
            0.08 + 0.2 * (bar % 8) / 8))
        for i in range(4):
            if bar >= 4:
                t.kick(b + i)
            t.hat(b + i + 0.5)
    t.clock(64, 0.9)
    return t


def chime() -> None:
    """Room clear: tick, tock, then a rising bell triad."""
    t = Track(120, 1, 5)
    t.length = int(2.6 * RATE)
    t.buf = [0.0] * t.length
    t.tick(0, 0.3)
    t.tock(0.25, 0.3)
    for i, n in enumerate((72, 76, 79, 84)):
        t.bell(0.55 + i * 0.18, n, 0.25, 0.5 if i < 3 else 0.9)
    # A one-shot, so trim the wrap-around instead of looping it.
    t.save(ROOT / "forward" / "clear.wav")


if __name__ == "__main__":
    chime()
    for name, make in (("title", title), ("tundra", tundra), ("dunes", dunes), ("tomb", tomb)):
        make().save(ROOT / "music" / f"{name}.wav")
