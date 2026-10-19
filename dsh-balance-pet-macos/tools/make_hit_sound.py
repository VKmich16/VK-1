#!/usr/bin/env python3
"""Generate the hit sound used by the pet (pure stdlib, no assets needed).

A short, punchy "thud": a noise transient that decays fast, layered over a
pitch-dropping sine body, soft-clipped so it stays punchy instead of harsh.
"""
import array
import math
import random
import struct
import sys
import wave

RATE = 44100
DURATION = 0.22


def generate():
    n = int(RATE * DURATION)
    rng = random.Random(20260928)
    samples = array.array("d", [0.0]) * n

    # Pitch sweep for the body: 330 Hz -> 105 Hz, exponential.
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = 330.0 * math.exp(-t * 11.0) + 105.0
        phase += 2.0 * math.pi * f / RATE
        body = math.sin(phase) * math.exp(-t * 15.0)

        # Noise transient (the "smack"), gone within ~25 ms.
        noise = rng.uniform(-1.0, 1.0) * math.exp(-t * 130.0) * 0.85

        # A touch of second harmonic for weight.
        harm = math.sin(phase * 2.0) * math.exp(-t * 26.0) * 0.25

        samples[i] = body * 0.75 + noise + harm

    # Soft clip + short fade-out so the tail never clicks.
    peak = max(abs(v) for v in samples) or 1.0
    out = array.array("h")
    fade = int(RATE * 0.03)
    for i, v in enumerate(samples):
        v = math.tanh(v * 1.35 / peak * 1.6)
        if i > n - fade:
            v *= (n - i) / fade
        out.append(int(max(-1.0, min(1.0, v)) * 32767))
    return out


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "hit.wav"
    data = generate()
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())
    print("wrote %s (%d samples, %.2fs)" % (path, len(data), len(data) / RATE))


if __name__ == "__main__":
    main()
