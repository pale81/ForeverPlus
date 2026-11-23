#!/usr/bin/env python3
"""Build the cartoon cash register sound in Media/AuctionKaChing.mp3."""
from math import cos, exp, pi, sin, tanh
from pathlib import Path
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
DURATION = 2.35
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

    # "Kaaa": a solid key strike, a rising spring slide and a few ratchet clicks.
    add_damped_sine(buf, 0.006, 154.0, 0.38, 0.039, attack=0.001)
    add_metallic_impulse(buf, 0.006, 0.044, 620.0, 1.4, 0.76, 0.0005, 0.015, rng)
    add_metallic_impulse(buf, 0.008, 0.035, 2600.0, 2.0, 0.52, 0.0003, 0.010, rng)

    slide_start = int(0.027 * SAMPLE_RATE)
    slide_length = int(0.16 * SAMPLE_RATE)
    phase = 0.0
    for i in range(slide_length):
        progress = i / slide_length
        pitch = 188.0 + 280.0 * progress ** 1.7
        phase += 2.0 * pi * pitch / SAMPLE_RATE
        envelope = sin(pi * progress) ** 0.8
        buf[slide_start + i] += envelope * (
            0.20 * sin(phase) + 0.12 * sin(phase * 2) + 0.04 * sin(phase * 5)
        )

    for start, frequency in [(0.052, 1050.0), (0.087, 1420.0), (0.118, 1780.0), (0.142, 2210.0)]:
        add_metallic_impulse(buf, start, 0.030, frequency, 2.5, 0.66, 0.0004, 0.010, rng)

    # The drawer meets its stop, then the bell answers on a separate beat.
    t_stop = 0.188
    add_damped_sine(buf, t_stop, 118.0, 0.44, 0.040, attack=0.0014)
    add_metallic_impulse(buf, t_stop, 0.055, 1040.0, 1.4, 0.80, 0.0005, 0.016, rng)
    add_metallic_impulse(buf, t_stop, 0.031, 3500.0, 2.1, 0.52, 0.0003, 0.010, rng)

    # "Chiiing": bright brass with close partials that beat as they ring out.
    t_bell = 0.228
    add_metallic_impulse(buf, t_bell, 0.043, 4800.0, 2.5, 0.80, 0.0003, 0.010, rng)
    bell_modes = [
        (659.0, 0.20, 0.51, 0.2),
        (1318.5, 0.49, 0.69, 0.0),
        (1322.0, 0.11, 0.58, 0.6),
        (2080.0, 0.10, 0.32, 1.1),
        (2642.0, 0.27, 0.48, 0.3),
        (2649.0, 0.07, 0.35, 1.9),
        (3602.0, 0.20, 0.26, 0.8),
        (4855.0, 0.14, 0.13, 1.3),
        (6350.0, 0.07, 0.068, 0.5),
    ]
    for frequency, amp, decay, phase in bell_modes:
        add_damped_sine(buf, t_bell, frequency, amp, decay, attack=0.001, phase=phase)

    # A short tumble of ringing coins behind the bell.
    coins = [
        (0.274, 3180.0, 0.16),
        (0.324, 4180.0, 0.13),
        (0.373, 3450.0, 0.12),
        (0.421, 5020.0, 0.10),
        (0.479, 3920.0, 0.08),
    ]
    for start, frequency, amp in coins:
        add_damped_sine(buf, start, frequency, amp, 0.053)
        add_damped_sine(buf, start, frequency * 1.48, amp * 0.58, 0.026)
        add_metallic_impulse(buf, start, 0.029, frequency, 5.0, amp * 2.2, 0.0004, 0.010, rng)

    buf = add_room_reflections(buf)
    fade_out = int(0.24 * SAMPLE_RATE)
    for i in range(fade_out):
        buf[-1 - i] *= i / fade_out

    # Soft saturation keeps the transients punchy and leaves encoding headroom.
    buf = [tanh(sample * 1.2) for sample in buf]
    gain = 0.84 / max(abs(sample) for sample in buf)
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
