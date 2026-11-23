#!/usr/bin/env python3
"""Build the short auction payout sound in Media/AuctionKaChing.mp3."""
from math import cos, exp, pi, sin
from pathlib import Path
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
DURATION = 0.32
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

    # One handful of coins landing. Irregular spacing and short resonances
    # keep the individual impacts audible without forming a tune.
    impacts = [
        (0.010, 2370.0, 0.69),
        (0.032, 3010.0, 0.48),
        (0.056, 1920.0, 1.00),
        (0.081, 3170.0, 0.64),
        (0.105, 2100.0, 0.54),
        (0.139, 2840.0, 0.36),
        (0.177, 2420.0, 0.24),
    ]
    for start, frequency, strength in impacts:
        add_metallic_impulse(buf, start, 0.040, 1300.0, 0.9, strength * 0.70, 0.0004, 0.007, rng)
        add_metallic_impulse(buf, start, 0.024, frequency * 1.48, 1.3, strength * 0.58, 0.0003, 0.004, rng)
        add_damped_sine(buf, start, frequency * 0.44, strength * 0.14, 0.013)
        add_damped_sine(buf, start, frequency, strength * 0.31, 0.019)
        add_damped_sine(buf, start, frequency * 1.57, strength * 0.20, 0.011, phase=0.7)
        add_damped_sine(buf, start, frequency * 2.38, strength * 0.12, 0.007, phase=1.1)

    fade_out = int(0.025 * SAMPLE_RATE)
    for i in range(fade_out):
        buf[-1 - i] *= i / fade_out
    gain = 0.55 / max(abs(sample) for sample in buf)
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
