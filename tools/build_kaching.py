#!/usr/bin/env python3
"""Synthesize a crisp, classic antique cash-register 'cha-chiiiing'.

Builds Media/AuctionKaChing.mp3 from physical/modal synthesis:
  1. Snappy steel latch release & quick spring-drawer slide ("cha-") (~0.15 s)
  2. Crisp drawer-stop clack right as the hammer strikes
  3. Heavy antique cast-brass dome bell with long natural ring-out ("-chiiiiiiiiing")
  4. Subtle dry metallic tray/coin clatter and short wooden-shop early reflections
"""
from math import cos, exp, pi, sin, tanh
from pathlib import Path
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
DURATION = 2.55
N_SAMPLES = int(SAMPLE_RATE * DURATION)
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


def biquad_lowpass(samples, freq, q=0.707):
    """Apply a biquad lowpass filter."""
    w0 = 2.0 * pi * freq / SAMPLE_RATE
    alpha = sin(w0) / (2.0 * q)
    cos_w0 = cos(w0)
    b0 = (1.0 - cos_w0) * 0.5
    b1 = 1.0 - cos_w0
    b2 = b0
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


def add_room_reflections(buf):
    """Add subtle wooden-shop early reflections for natural acoustic depth."""
    reflections = [
        (0.0078, 0.13),
        (0.0154, -0.10),
        (0.0249, 0.085),
        (0.0365, -0.065),
        (0.0508, 0.048),
        (0.0679, -0.035),
        (0.0885, 0.024),
        (0.1140, -0.015),
    ]
    wet = [0.0] * len(buf)
    for delay_s, gain in reflections:
        d = int(delay_s * SAMPLE_RATE)
        for i in range(d, len(buf)):
            wet[i] += gain * buf[i - d]
    wet = biquad_lowpass(wet, 3600.0, 0.7)
    return [buf[i] + 0.48 * wet[i] for i in range(len(buf))]


def synthesize():
    rng = random.Random(16005)
    buf = [0.0] * N_SAMPLES

    # 1. Crisp, punchy mechanical "CHA-" (0.005 s - 0.142 s) — tight steel mechanics, no slow rattle
    # Sharp steel key-slam + metal latch trip at t = 0.005 s
    add_metallic_impulse(buf, 0.005, 0.036, 195.0, 1.4, 0.72, 0.0004, 0.012, rng)
    add_metallic_impulse(buf, 0.005, 0.028, 1280.0, 2.2, 0.74, 0.0003, 0.008, rng)
    add_metallic_impulse(buf, 0.005, 0.022, 3150.0, 2.6, 0.62, 0.0003, 0.006, rng)
    add_metallic_impulse(buf, 0.006, 0.016, 5600.0, 2.8, 0.34, 0.0002, 0.004, rng)

    # Short, heavy iron/wood drawer slide impulse (0.022 s - 0.130 s, low-mid body, minimal hiss)
    zip_start = int(0.022 * SAMPLE_RATE)
    zip_len = int(0.108 * SAMPLE_RATE)
    zip_raw = [rng.uniform(-1.0, 1.0) for _ in range(zip_len)]
    zip_low = biquad_bandpass(zip_raw, 310.0, 1.5)
    zip_mid = biquad_bandpass(zip_raw, 1380.0, 2.2)
    zip_hi = biquad_bandpass(zip_raw, 3400.0, 2.8)
    for k in range(zip_len):
        u = k / float(zip_len)
        env = min(1.0, u / 0.16) * (1.0 - max(0.0, (u - 0.84) / 0.16))
        env *= 0.65 + 0.45 * u
        buf[zip_start + k] += env * (
            0.38 * zip_low[k] + 0.32 * zip_mid[k] + 0.12 * zip_hi[k]
        )

    # Crisp spring-lever snap mid-stroke at t = 0.068 s ("-CHAK")
    add_metallic_impulse(buf, 0.068, 0.032, 480.0, 1.8, 0.54, 0.0004, 0.010, rng)
    add_metallic_impulse(buf, 0.068, 0.024, 2150.0, 2.8, 0.68, 0.0003, 0.0065, rng)
    add_metallic_impulse(buf, 0.069, 0.018, 4600.0, 3.2, 0.44, 0.0002, 0.0045, rng)

    # 2. Solid drawer-stop impact ("-KLACK") at t = 0.132 s right before the bell hammer
    t_stop = 0.132
    add_metallic_impulse(buf, t_stop, 0.070, 135.0, 1.3, 0.92, 0.0006, 0.024, rng)
    add_metallic_impulse(buf, t_stop, 0.052, 410.0, 1.8, 0.60, 0.0005, 0.016, rng)
    add_metallic_impulse(buf, t_stop, 0.034, 1780.0, 2.4, 0.62, 0.0004, 0.009, rng)
    add_metallic_impulse(buf, t_stop, 0.024, 4100.0, 2.8, 0.40, 0.0003, 0.006, rng)

    # 3. Heavy antique cast-brass register bell ("-CHIIIIIIIIIIING!") at t = 0.145 s
    # Long, clear, authentic antique cast-brass dome bell (~2120 Hz, ~2.4 s ring-out).
    t_bell = 0.145
    f0 = 2120.0

    # Crisp steel-clapper-on-brass strike transient
    add_metallic_impulse(buf, t_bell, 0.024, 5900.0, 2.0, 0.72, 0.0002, 0.0032, rng)
    add_metallic_impulse(buf, t_bell, 0.032, 3150.0, 3.2, 0.40, 0.0003, 0.0065, rng)

    # Thick cast-brass dome shell partials: (ratio, amp, decay_sec, phase)
    bell_modes = [
        (0.5012, 0.048, 1.02, 0.0),   # faint warm brass body hum
        (1.0000, 0.565, 1.00, 0.0),   # main singing brass bell fundamental
        (1.0011, 0.135, 0.92, 0.6),   # slow organic cast-shell shimmer (~2.3 Hz)
        (1.5840, 0.050, 0.46, 1.2),   # subtle inharmonic dome shell tone
        (2.0090, 0.195, 0.52, 0.3),   # bright slightly stretched octave partial
        (2.0122, 0.045, 0.42, 2.0),   # faint upper brass shimmer
        (2.7560, 0.155, 0.27, 0.9),   # signature bell shell overtone
        (3.6680, 0.092, 0.135, 2.4),  # crisp upper metallic ring
        (4.7820, 0.054, 0.062, 0.5),  # metallic attack brilliance
        (6.1100, 0.030, 0.026, 1.5),  # crisp steel-on-brass strike sheen
    ]
    for ratio, amp, decay, phase in bell_modes:
        add_damped_sine(buf, t_bell, f0 * ratio, amp, decay, attack=0.0005, phase=phase)

    # 4. Subtle dry metallic tray/coin clatter right as the drawer pops open (0.17 s - 0.36 s)
    clatter = [
        (0.175, 3850.0, 0.18, 0.011),
        (0.212, 4950.0, 0.14, 0.010),
        (0.258, 3420.0, 0.11, 0.009),
        (0.315, 4480.0, 0.07, 0.008),
    ]
    for t_c, freq_c, amp_c, dec_c in clatter:
        add_metallic_impulse(buf, t_c, 0.032, freq_c, 8.0, amp_c, 0.0003, dec_c, rng)
        add_metallic_impulse(buf, t_c, 0.024, freq_c * 1.47, 9.5, amp_c * 0.6, 0.0003, dec_c * 0.7, rng)

    # Natural wooden-shop early reflections
    buf = add_room_reflections(buf)

    # Clean fade-in (2 ms) and long natural fade-out (180 ms)
    fade_in = int(0.002 * SAMPLE_RATE)
    for i in range(fade_in):
        buf[i] *= i / float(fade_in)
    fade_out = int(0.180 * SAMPLE_RATE)
    for k in range(fade_out):
        buf[N_SAMPLES - 1 - k] *= k / float(fade_out)

    # Gentle warm saturation and peak normalize to -1.5 dBFS (~0.84)
    buf = [tanh(x * 1.06) for x in buf]
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
