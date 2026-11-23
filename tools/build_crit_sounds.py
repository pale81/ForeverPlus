#!/usr/bin/env python3
"""Synthesize six soft Solo Party impacts. Requires ffmpeg on PATH."""

import math
from pathlib import Path
import random
import struct
import subprocess
import wave
from tempfile import TemporaryDirectory


RATE = 44100
DURATION = 0.24
PEAK = 10 ** (-8 / 20)
MEDIA = Path(__file__).resolve().parents[1] / "Media"


def render(variant):
    rng = random.Random(1900 + variant)
    body_freq = (132, 112, 144, 105, 121, 116)[variant - 1]
    samples = []
    low_noise = 0
    for i in range(int(RATE * DURATION)):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low_noise += 0.14 * (noise - low_noise)
        body = math.sin(math.tau * (body_freq * t - 130 * t * t)) * math.exp(-t / 0.055)
        crack = (low_noise + 0.22 * noise) * math.exp(-t / 0.028)
        edge = math.sin(math.tau * (580 + 32 * variant) * t) * math.exp(-t / 0.044)
        envelope = min(1, t / 0.002, (DURATION - t) / 0.025)
        samples.append((0.55 * body + 0.65 * crack + 0.36 * edge) * envelope)
    gain = PEAK * 32767 / max(abs(sample) for sample in samples)
    return b"".join(struct.pack("<h", round(gain * sample)) for sample in samples)


def main():
    with TemporaryDirectory() as temp:
        source = Path(temp) / "impact.wav"
        for variant in range(1, 7):
            with wave.open(str(source), "wb") as audio:
                audio.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
                audio.writeframes(render(variant))
            subprocess.run(
                [
                    "ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(source),
                    "-c:a", "libmp3lame", "-q:a", "3", str(MEDIA / f"SoloPartyCrit{variant}.mp3"),
                ],
                check=True,
            )


if __name__ == "__main__":
    main()
