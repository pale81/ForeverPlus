#!/usr/bin/env python3
"""Build the bags-full warning as a short descending double tone."""

from math import sin, tau
from pathlib import Path
import struct
import subprocess

SAMPLE_RATE = 44100
TARGET = Path(__file__).resolve().parent.parent / "Media" / "BagsFull.mp3"


def add_pulse(samples, start, duration, start_hz, end_hz, gain):
    offset = round(start * SAMPLE_RATE)
    sweep = (end_hz - start_hz) / duration
    for index in range(round(duration * SAMPLE_RATE)):
        time = index / SAMPLE_RATE
        phase = tau * (start_hz * time + sweep * time ** 2 / 2)
        envelope = min(time / 0.008, 1) * min((duration - time) / 0.045, 1)
        # A detuned partial adds a slight buzz, with most of the energy in the low tone.
        tone = sin(phase) + 0.32 * sin(phase * 1.065) + 0.17 * sin(phase * 2)
        samples[offset + index] += gain * envelope * tone


def main():
    samples = [0.0] * round(0.44 * SAMPLE_RATE)
    add_pulse(samples, 0.01, 0.14, 490, 421, 0.85)
    add_pulse(samples, 0.185, 0.22, 322, 248, 1.0)
    scale = 32767 * 0.46 / max(map(abs, samples))
    pcm = struct.pack(f"<{len(samples)}h", *(round(sample * scale) for sample in samples))
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-f", "s16le",
         "-ar", str(SAMPLE_RATE), "-ac", "1", "-i", "pipe:0", "-c:a", "libmp3lame",
         "-b:a", "96k", str(TARGET)],
        input=pcm,
        check=True,
    )


if __name__ == "__main__":
    main()
