#!/usr/bin/env python3
"""Synthesize a realistic antique mechanical cash-register 'kaaaa-chiiiing'.

Builds Media/AuctionKaChing.mp3 from physical/modal synthesis:
  1. Heavy steel key-press and escapement lever trip ("ka-chak")
  2. Spring-driven mechanical gear ratchet and steel drawer rolling on rails ("-aaaa-")
  3. Solid hardwood/iron drawer-stop slam ("-klunk")
  4. Heavy antique cast-brass dome bell with long natural ring-out ("-chiiiiiiiiing")
  5. Organic wooden-shop early reflections
"""
from math import cos, exp, pi, sin, tanh
from pathlib import Path
import random
import struct
import subprocess
import wave

SAMPLE_RATE = 44100
DURATION = 2.85
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


def add_damped_sine(buf, t_start, freq, amp, decay, attack=0.0007, phase=0.0):
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


def add_modal_hit(buf, t_start, modes, amp, rng):
    """Excite a cluster of narrow metallic/wooden body resonances with a dry click."""
    # Short dry impact burst + narrow damped modal rings (no hissy broadband wash)
    start_i = max(0, int(t_start * SAMPLE_RATE))
    click_len = min(len(buf) - start_i, int(0.012 * SAMPLE_RATE))
    if click_len > 0:
        raw = [rng.uniform(-1.0, 1.0) for _ in range(click_len)]
        click = biquad_bandpass(raw, 1900.0, 1.6)
        inv_sr = 1.0 / SAMPLE_RATE
        for k in range(click_len):
            dt = k * inv_sr
            buf[start_i + k] += amp * 0.24 * exp(-dt / 0.0022) * click[k]
    for freq, rel_amp, decay in modes:
        add_damped_sine(
            buf, t_start, freq, amp * rel_amp, decay,
            attack=0.0004, phase=rng.uniform(0.0, 2.0 * pi),
        )


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
    wet = biquad_lowpass(wet, 3400.0, 0.7)
    return [buf[i] + 0.50 * wet[i] for i in range(len(buf))]


def synthesize():
    rng = random.Random(16003)
    buf = [0.0] * N_SAMPLES

    # 1. Heavy steel key press & escapement trip ("KA-CHAK") at 0.008 s and 0.068 s
    # Dry, unpitched broadband mechanical impacts (no musical tone!)
    add_metallic_impulse(buf, 0.008, 0.070, 185.0, 1.3, 0.85, 0.0008, 0.022, rng)
    add_metallic_impulse(buf, 0.008, 0.045, 780.0, 1.8, 0.55, 0.0005, 0.012, rng)
    add_metallic_impulse(buf, 0.009, 0.030, 2150.0, 2.0, 0.62, 0.0004, 0.007, rng)
    add_metallic_impulse(buf, 0.009, 0.022, 4200.0, 2.2, 0.36, 0.0003, 0.005, rng)

    # Escapement lever snapping back as the drawer spring releases
    add_metallic_impulse(buf, 0.068, 0.045, 310.0, 1.6, 0.50, 0.0006, 0.014, rng)
    add_metallic_impulse(buf, 0.068, 0.030, 1580.0, 2.2, 0.58, 0.0004, 0.008, rng)
    add_metallic_impulse(buf, 0.069, 0.022, 3450.0, 2.4, 0.40, 0.0003, 0.005, rng)

    # 2. Long heavy iron/wood drawer rolling out on steel tracks ("-AAAAA-") (0.10 s - 0.40 s)
    # Constant-pitch gritty mechanical rolling rumble + dry steel gear ticks (NO rising pitch!)
    roll_start = int(0.098 * SAMPLE_RATE)
    roll_len = int(0.315 * SAMPLE_RATE)
    roll_raw = [rng.uniform(-1.0, 1.0) for _ in range(roll_len)]
    roll_wood = biquad_bandpass(roll_raw, 190.0, 1.5)
    roll_iron = biquad_bandpass(roll_raw, 560.0, 1.8)
    roll_rail = biquad_bandpass(roll_raw, 1420.0, 2.0)
    for k in range(roll_len):
        u = k / float(roll_len)
        # Mechanical bearing grain (gentle uneven texture, not tonal)
        grain = 0.78 + 0.22 * sin(2.0 * pi * (37.0 * u)) * sin(2.0 * pi * (13.0 * u + 0.4))
        env = min(1.0, u / 0.14) * (1.0 - max(0.0, (u - 0.88) / 0.12))
        env *= (0.72 + 0.35 * u) * grain
        buf[roll_start + k] += env * (
            0.52 * roll_wood[k] + 0.34 * roll_iron[k] + 0.24 * roll_rail[k]
        )

    # Dry, unpitched steel gear-pawl ticks along the drawer travel (tight 3-4 ms clicks)
    ratchet_times = [
        0.112, 0.145, 0.176, 0.205, 0.233,
        0.260, 0.288, 0.317, 0.347, 0.378,
    ]
    for idx, t in enumerate(ratchet_times):
        t_j = t + rng.uniform(-0.003, 0.003)
        grow = 0.65 + 0.04 * idx
        f_a = rng.uniform(1150.0, 1850.0)
        f_b = rng.uniform(2600.0, 3900.0)
        add_metallic_impulse(buf, t_j, 0.022, f_a, 2.6, 0.44 * grow, 0.0003, 0.0045, rng)
        add_metallic_impulse(buf, t_j, 0.018, f_b, 2.8, 0.32 * grow, 0.0003, 0.0035, rng)
        add_metallic_impulse(buf, t_j, 0.028, rng.uniform(260.0, 420.0), 1.8, 0.26 * grow, 0.0005, 0.007, rng)

    # 3. Heavy hardwood & cast-iron drawer-stop impact ("-KLUNK!") at t = 0.412 s
    t_stop = 0.412
    add_metallic_impulse(buf, t_stop, 0.110, 115.0, 1.3, 1.05, 0.0010, 0.036, rng)
    add_metallic_impulse(buf, t_stop, 0.085, 275.0, 1.7, 0.72, 0.0008, 0.025, rng)
    add_metallic_impulse(buf, t_stop, 0.065, 860.0, 2.0, 0.56, 0.0005, 0.016, rng)
    add_metallic_impulse(buf, t_stop, 0.045, 2150.0, 2.2, 0.42, 0.0004, 0.010, rng)

    # 4. Heavy antique cast-brass register bell ("-CHIIIIIIIIIIING!") at t = 0.432 s
    # Classic thick cast-brass dome bell (~2120 Hz): bright, authentic, rich, long ~2.4 s ring.
    t_bell = 0.432
    f0 = 2120.0

    # Crisp steel-clapper-on-brass strike transient (short, tight, metallic — zero hiss)
    add_metallic_impulse(buf, t_bell, 0.024, 5800.0, 2.2, 0.68, 0.0002, 0.0030, rng)
    add_metallic_impulse(buf, t_bell, 0.032, 3100.0, 3.4, 0.38, 0.0003, 0.0065, rng)

    # Thick cast-brass dome shell partials: (ratio, amp, decay_sec, phase)
    bell_modes = [
        (0.5012, 0.048, 1.05, 0.0),   # faint warm brass body hum
        (1.0000, 0.560, 1.02, 0.0),   # main singing brass bell fundamental
        (1.0011, 0.135, 0.94, 0.6),   # slow organic cast-shell shimmer (~2.3 Hz)
        (1.5840, 0.050, 0.48, 1.2),   # subtle inharmonic dome shell tone
        (2.0090, 0.190, 0.54, 0.3),   # bright slightly stretched octave partial
        (2.0122, 0.045, 0.44, 2.0),   # faint upper brass shimmer
        (2.7560, 0.155, 0.28, 0.9),   # signature bell shell overtone
        (3.6680, 0.090, 0.14, 2.4),   # crisp upper metallic ring
        (4.7820, 0.052, 0.065, 0.5),  # metallic attack brilliance
        (6.1100, 0.028, 0.028, 1.5),  # crisp steel-on-brass strike sheen
    ]
    for ratio, amp, decay, phase in bell_modes:
        add_damped_sine(buf, t_bell, f0 * ratio, amp, decay, attack=0.0005, phase=phase)

    # 5. Subtle mechanical spring-latch recoil & drawer-tray settle (0.48 s - 0.68 s)
    recoil_modes = [
        (380.0, 0.14, 0.015),
        (1240.0, 0.12, 0.010),
        (2850.0, 0.09, 0.008),
    ]
    add_modal_hit(buf, 0.495, recoil_modes, 0.24, rng)
    add_metallic_impulse(buf, 0.565, 0.036, 3650.0, 9.5, 0.12, 0.0004, 0.014, rng)
    add_metallic_impulse(buf, 0.635, 0.032, 4320.0, 10.5, 0.08, 0.0004, 0.011, rng)

    # Natural wooden-shop early reflections
    buf = add_room_reflections(buf)

    # Clean fade-in (3 ms) and long natural fade-out (200 ms)
    fade_in = int(0.003 * SAMPLE_RATE)
    for i in range(fade_in):
        buf[i] *= i / float(fade_in)
    fade_out = int(0.200 * SAMPLE_RATE)
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
