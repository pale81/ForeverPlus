#!/usr/bin/env python3
"""Synthesize the auction cash register sound in Media/AuctionKaChing.mp3."""
from math import cos, exp, pi, sin
from pathlib import Path
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
DURATION = 1.09
TARGET = Path(__file__).resolve().parent.parent / "Media/AuctionKaChing.mp3"


def biquad_bandpass(samples, freq, q):
    """Apply a constant-skirt-gain biquad bandpass filter."""
    w0 = 2.0 * pi * freq / SAMPLE_RATE
    alpha = sin(w0) / (2.0 * q)
    cos_w0 = cos(w0)
    b0 = alpha
    b2 = -alpha
    a0 = 1.0 + alpha
    a1 = -2.0 * cos_w0
    a2 = 1.0 - alpha
    b0 /= a0
    b2 /= a0
    a1 /= a0
    a2 /= a0

    out = [0.0] * len(samples)
    x1 = x2 = y1 = y2 = 0.0
    for i, x0 in enumerate(samples):
        y0 = b0 * x0 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y0
        x2, x1 = x1, x0
        y2, y1 = y1, y0
    return out


def add_damped_sine(buf, t_start, freq, amp, decay, attack=0.0006, phase=0.0):
    """Add an exponentially decaying resonant mode with a smooth attack."""
    start_i = max(0, int(t_start * SAMPLE_RATE))
    max_len = int((attack + decay * 10.0) * SAMPLE_RATE)
    end_i = min(len(buf), start_i + max_len)
    w = 2.0 * pi * freq / SAMPLE_RATE
    inv_sr = 1.0 / SAMPLE_RATE
    inv_decay = 1.0 / decay
    for i in range(start_i, end_i):
        dt = (i - start_i) * inv_sr
        env = exp(-dt * inv_decay)
        if dt < attack:
            env *= dt / attack
        buf[i] += amp * env * sin(w * (i - start_i) + phase)


def add_metallic_impulse(buf, t_start, duration, freq, q, amp, attack, decay, rng):
    """Add a bandpass-filtered mechanical impulse."""
    start_i = max(0, int(t_start * SAMPLE_RATE))
    n = min(len(buf) - start_i, int(duration * SAMPLE_RATE))
    if n <= 0:
        return
    raw = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    filtered = biquad_bandpass(raw, freq, q)
    inv_sr = 1.0 / SAMPLE_RATE
    inv_decay = 1.0 / decay
    for k in range(n):
        dt = k * inv_sr
        env = exp(-dt * inv_decay)
        if dt < attack:
            env *= dt / attack
        buf[start_i + k] += amp * env * filtered[k]


def synthesize():
    rng = random.Random(16005)
    buf = [0.0] * int(SAMPLE_RATE * DURATION)

    # Key travel followed by a quick metallic ratchet on the way to the strike.
    add_metallic_impulse(buf, 0.010, 0.030, 890.0, 1.1, 0.12, 0.0005, 0.008, rng)
    ratchet = [
        (0.055, 3880.0, 0.14),
        (0.076, 5340.0, 0.26),
        (0.096, 4940.0, 0.55),
        (0.117, 6580.0, 0.40),
        (0.141, 4390.0, 0.46),
        (0.165, 6140.0, 0.38),
    ]
    for start, frequency, strength in ratchet:
        add_metallic_impulse(buf, start, 0.043, frequency, 1.2, strength * 2.30, 0.0011, 0.017, rng)
        add_damped_sine(buf, start, frequency * 0.47, strength * 0.30, 0.010)

    # The striker and the inharmonic partials of a small steel bell.
    strike = 0.192
    add_metallic_impulse(buf, strike - 0.007, 0.037, 5900.0, 1.0, 0.68, 0.0004, 0.010, rng)
    add_damped_sine(buf, strike, 680.0, 0.14, 0.026)
    bell_modes = [
        (2098.0, 0.52, 0.214, 0.0),
        (2104.0, 0.053, 0.183, 1.0),
        (4808.0, 0.26, 0.191, 0.5),
        (7454.0, 0.205, 0.044, 1.2),
        (7726.0, 0.19, 0.092, 2.1),
        (9690.0, 0.060, 0.031, 0.8),
    ]
    for frequency, amp, decay, phase in bell_modes:
        add_damped_sine(buf, strike, frequency, amp, decay, attack=0.004, phase=phase)

    # Two drawer stops and a couple of smaller contacts as the mechanism settles.
    stops = [
        (0.474, 1070.0, 1.13),
        (0.545, 780.0, 1.05),
        (0.677, 620.0, 0.59),
        (0.815, 470.0, 0.23),
        (0.950, 350.0, 0.12),
    ]
    for start, frequency, strength in stops:
        add_metallic_impulse(buf, start, 0.079, frequency, 0.9, strength * 1.78, 0.0005, 0.023, rng)
        add_metallic_impulse(buf, start, 0.043, 4530.0, 1.3, strength * 1.68, 0.0003, 0.011, rng)
        add_damped_sine(buf, start, frequency, strength * 0.32, 0.022)
        add_damped_sine(buf, start, 1.46 * frequency, strength * 0.23, 0.017, phase=0.4)

    fade_out = int(0.045 * SAMPLE_RATE)
    for i in range(fade_out):
        buf[-1 - i] *= i / fade_out
    gain = 0.78 / max(abs(sample) for sample in buf)
    return [sample * gain for sample in buf]


def write_mp3(samples, target_path):
    pcm = struct.pack(f"<{len(samples)}h", *(int(round(s * 32767.0)) for s in samples))
    wav_tmp = target_path.with_suffix(".tmp.wav")
    try:
        with wave.open(str(wav_tmp), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(SAMPLE_RATE)
            wf.writeframes(pcm)
        subprocess.run(
            [
                "ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", str(wav_tmp),
                "-c:a", "libmp3lame", "-q:a", "2",
                str(target_path),
            ],
            check=True,
        )
    finally:
        if wav_tmp.exists():
            wav_tmp.unlink()


def main():
    samples = synthesize()
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    write_mp3(samples, TARGET)
    print(f"written to {TARGET} ({TARGET.stat().st_size} bytes, {DURATION:.2f}s)")


if __name__ == "__main__":
    main()
