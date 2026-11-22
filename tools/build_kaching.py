#!/usr/bin/env python3
"""Synthesize a vintage mechanical cash-register 'ka-ching' sound effect.

Builds Media/AuctionKaChing.mp3 from deterministic physical synthesis:
  1. Mechanical key release and spring-loaded drawer ratchet ("kaaa-")
  2. Cast-iron drawer stop impact ("-chunk")
  3. Antique brass dome register bell with cast double-mode shimmer ("-chiiing!")
  4. Subtle cascade of coins bouncing inside the metal till
"""
from math import exp, pi, sin, tanh
from pathlib import Path
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
DURATION = 1.55
N_SAMPLES = int(SAMPLE_RATE * DURATION)
TARGET = Path(__file__).resolve().parent.parent / "Media/AuctionKaChing.mp3"


def biquad_bandpass(samples, freq, q):
    """Apply a constant-skirt-gain biquad bandpass filter."""
    w0 = 2.0 * pi * freq / SAMPLE_RATE
    alpha = sin(w0) / (2.0 * q)
    cos_w0 = sin(w0 + pi / 2.0)
    b0 = alpha
    b1 = 0.0
    b2 = -alpha
    a0 = 1.0 + alpha
    a1 = -2.0 * cos_w0
    a2 = 1.0 - alpha

    b0 /= a0
    b1 /= a0
    b2 /= a0
    a1 /= a0
    a2 /= a0

    out = [0.0] * len(samples)
    x1 = x2 = y1 = y2 = 0.0
    for i, x0 in enumerate(samples):
        y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = y0
        x2, x1 = x1, x0
        y2, y1 = y1, y0
    return out


def add_damped_sine(buf, t_start, freq, amp, decay, attack=0.0012, phase=0.0):
    """Add an exponentially decaying sine wave with a smooth attack."""
    start_i = max(0, int(t_start * SAMPLE_RATE))
    # Stop when envelope falls below -90 dB
    max_len = int((attack + decay * 10.5) * SAMPLE_RATE)
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


def add_filtered_noise_burst(buf, t_start, duration, freq, q, amp, attack, decay, rng):
    """Add a short bandpass-filtered metallic noise burst."""
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
    rng = random.Random(16001)
    buf = [0.0] * N_SAMPLES

    # 1. Mechanical key press & latch release ("KA-") at t = 0.005 s
    add_filtered_noise_burst(buf, 0.004, 0.055, 2100.0, 2.0, 0.85, 0.001, 0.013, rng)
    add_filtered_noise_burst(buf, 0.005, 0.045, 4200.0, 2.6, 0.48, 0.0008, 0.009, rng)
    add_damped_sine(buf, 0.005, 340.0, 0.28, 0.022, 0.0008)
    add_damped_sine(buf, 0.005, 890.0, 0.20, 0.018, 0.0008)
    add_damped_sine(buf, 0.005, 1740.0, 0.14, 0.014, 0.0006)

    # 2. Spring-loaded gear ratchet & metal drawer sliding out ("-aaa-ratch")
    # 7 accelerating ratchet teeth clicks from 0.028 s to 0.145 s
    ratchet_times = [0.028, 0.049, 0.069, 0.088, 0.106, 0.123, 0.140]
    for idx, t in enumerate(ratchet_times):
        grow = 0.72 + 0.10 * idx
        center = 2300.0 + 280.0 * idx
        add_filtered_noise_burst(buf, t, 0.036, center, 2.8, 0.68 * grow, 0.0006, 0.0085, rng)
        add_damped_sine(buf, t, 1380.0 + 140.0 * idx, 0.12 * grow, 0.011, 0.0005)
        add_damped_sine(buf, t, 3050.0 + 180.0 * idx, 0.095 * grow, 0.009, 0.0005)

    # Continuous metallic bearing/slide swoosh under the ratchet
    slide_start = int(0.018 * SAMPLE_RATE)
    slide_len = int(0.165 * SAMPLE_RATE)
    slide_raw = [rng.uniform(-1.0, 1.0) for _ in range(slide_len)]
    slide_mid = biquad_bandpass(slide_raw, 1350.0, 1.5)
    slide_hi = biquad_bandpass(slide_raw, 3600.0, 2.0)
    for k in range(slide_len):
        u = k / float(slide_len)
        # Swell up toward the drawer stop, then cut cleanly
        env = (0.35 + 0.65 * (u ** 0.7)) * (1.0 - max(0.0, (u - 0.85) / 0.15))
        buf[slide_start + k] += env * (0.34 * slide_mid[k] + 0.26 * slide_hi[k])

    # 3. Heavy cast-iron/wood cash drawer stop ("-CHUNK") at t = 0.166 s
    t_stop = 0.166
    add_damped_sine(buf, t_stop, 155.0, 0.36, 0.038, 0.0012)
    add_damped_sine(buf, t_stop, 285.0, 0.25, 0.030, 0.0010)
    add_damped_sine(buf, t_stop, 620.0, 0.16, 0.022, 0.0008)
    add_filtered_noise_burst(buf, t_stop, 0.065, 1150.0, 1.6, 0.72, 0.001, 0.018, rng)

    # 4. Antique cast-brass cash register dome bell ("-CHIIIING!") at t = 0.178 s
    # Classic vintage NCR register bell pitch (~2637 Hz, E7) with subtle
    # cast-brass shimmer and inharmonic shell partials.
    t_bell = 0.178
    f0 = 2637.0

    # Steel hammer strike transient on the brass dome
    add_filtered_noise_burst(buf, t_bell, 0.035, 6200.0, 2.0, 0.62, 0.0003, 0.0045, rng)
    add_filtered_noise_burst(buf, t_bell, 0.045, 3100.0, 3.0, 0.36, 0.0004, 0.009, rng)

    # Modal partials: (freq_ratio, amplitude, decay_sec, phase)
    bell_modes = [
        (0.5000, 0.13, 0.44, 0.0),    # warm sub-octave hum
        (1.0000, 0.56, 0.42, 0.0),    # primary ringing mode
        (1.0018, 0.15, 0.38, 0.5),    # subtle cast-shell shimmer (~4.7 Hz)
        (1.4980, 0.06, 0.25, 1.1),    # subtle fifth coloration
        (1.9970, 0.22, 0.22, 0.2),    # bright octave partial
        (2.0025, 0.07, 0.19, 1.7),    # octave shimmer
        (2.7560, 0.16, 0.135, 0.8),   # classic bell shell mode (inharmonic ring)
        (3.8150, 0.085, 0.070, 2.3),  # crystalline upper brass shimmer
        (4.9200, 0.045, 0.040, 0.5),  # crisp attack sparkle
    ]
    for ratio, amp, decay, phase in bell_modes:
        add_damped_sine(buf, t_bell, f0 * ratio, amp, decay, attack=0.0008, phase=phase)

    # 5. Silver/gold coins bouncing in the till (0.195 s - 0.56 s)
    coin_events = [
        (0.196, 0.130, 0.048),
        (0.228, 0.115, 0.044),
        (0.264, 0.105, 0.046),
        (0.304, 0.090, 0.042),
        (0.349, 0.075, 0.038),
        (0.402, 0.058, 0.036),
        (0.464, 0.042, 0.032),
        (0.535, 0.026, 0.028),
    ]
    for t_coin, amp, decay in coin_events:
        base = rng.uniform(4100.0, 5600.0)
        # Metallic coin disc modes (bright, thin, inharmonic)
        add_damped_sine(buf, t_coin, base, amp * 0.65, decay, 0.0005, rng.uniform(0, 6.28))
        add_damped_sine(buf, t_coin, base * 1.48, amp * 0.48, decay * 0.72, 0.0004, rng.uniform(0, 6.28))
        add_damped_sine(buf, t_coin, base * 2.13, amp * 0.30, decay * 0.45, 0.0003, rng.uniform(0, 6.28))
        add_filtered_noise_burst(buf, t_coin, 0.018, base * 1.3, 4.0, amp * 0.75, 0.0003, 0.003, rng)

    # Clean fade-in (2 ms) and fade-out (65 ms)
    fade_in = int(0.002 * SAMPLE_RATE)
    for i in range(fade_in):
        buf[i] *= i / float(fade_in)
    fade_out = int(0.065 * SAMPLE_RATE)
    for k in range(fade_out):
        buf[N_SAMPLES - 1 - k] *= k / float(fade_out)

    # Gentle warm saturation and peak normalize to -1.5 dBFS (~0.84)
    buf = [tanh(x * 1.15) for x in buf]
    peak = max(abs(x) for x in buf) or 1.0
    scale = 0.84 / peak
    return [max(-1.0, min(1.0, x * scale)) for x in buf]


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
