#!/usr/bin/env python3
"""Build Media/GuidingWind.tga: wind wisps and biome particles (256x256 RGBA).

Layout (top-to-bottom in UV space, v = 0 at top, v = 1 at bottom):
  Row 0 (v = 0.00..0.25, 256x64): Primary tapered curved wind wisp (head right).
  Row 1 (v = 0.25..0.50, 256x64): Secondary twin wind filament (head right).
  Row 2 (v = 0.50..0.75, 4 tiles of 64x64):
    0 (u = 0.00..0.25): Forest leaf with central vein.
    1 (u = 0.25..0.50): Six-pointed snowflake crystal.
    2 (u = 0.50..0.75): Soft dust / sand grain cluster.
    3 (u = 0.75..1.00): Glowing ember / ash spark.
  Row 3 (v = 0.75..1.00, 4 tiles of 64x64):
    0 (u = 0.00..0.25): Soft firefly / marsh spore glow.
    1 (u = 0.25..0.50): Autumn / meadow petal.
    2..3 (u = 0.50..1.00, 128x64): Soft curled breeze highlight.
"""
from math import atan2, cos, exp, hypot, pi, sin, sqrt
from pathlib import Path
from struct import pack

SIZE = 256
TARGET = Path(__file__).resolve().parent.parent / "Media/GuidingWind.tga"


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def wisp_primary(u, v):
    """Organic tapered wind ribbon flowing left-to-right (head near u = 0.92)."""
    if u < 0.02 or u > 0.98 or v < 0.04 or v > 0.96:
        return 0.0, 0.0
    # Slight S-curve centerline
    center = 0.50 + 0.11 * sin((u - 0.12) * 2.0 * pi) * smoothstep(0.05, 0.35, u)
    # Tapered half-width: thin tail on left, graceful body, fine pointed tip on right
    body = smoothstep(0.04, 0.55, u) * smoothstep(0.97, 0.78, u)
    half_w = 0.035 + 0.135 * (body ** 0.85)
    dist = abs(v - center) / max(half_w, 1e-4)
    core = exp(-dist * dist * 2.4)
    halo = exp(-dist * dist * 0.75) * 0.42
    # Longitudinal fade: long misty tail, crisp leading edge
    along = smoothstep(0.03, 0.62, u) * smoothstep(0.97, 0.86, u)
    alpha = clamp((core + halo) * along)
    bright = clamp(0.76 + 0.24 * core)
    return bright, alpha


def wisp_twin(u, v):
    """Finer split twin wind stream for visual variety."""
    if u < 0.02 or u > 0.98 or v < 0.04 or v > 0.96:
        return 0.0, 0.0
    along = smoothstep(0.04, 0.58, u) * smoothstep(0.96, 0.84, u)
    c1 = 0.42 + 0.09 * sin(u * 2.3 * pi + 0.4)
    c2 = 0.60 + 0.08 * sin(u * 2.1 * pi - 0.8)
    w1 = 0.028 + 0.075 * smoothstep(0.05, 0.55, u) * smoothstep(0.96, 0.75, u)
    w2 = 0.022 + 0.055 * smoothstep(0.12, 0.65, u) * smoothstep(0.94, 0.72, u)
    d1 = abs(v - c1) / max(w1, 1e-4)
    d2 = abs(v - c2) / max(w2, 1e-4)
    s1 = exp(-d1 * d1 * 2.2)
    s2 = exp(-d2 * d2 * 2.4) * 0.72 * smoothstep(0.10, 0.42, u)
    alpha = clamp((s1 + s2) * along)
    bright = clamp(0.78 + 0.22 * max(s1, s2))
    return bright, alpha


def tile_leaf(u, v):
    """Pointed forest leaf tilted slightly, with subtle central vein."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    # Rotate 28 degrees so it reads cleanly when tumbling
    ca, sa = cos(0.49), sin(0.49)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca
    # Leaf length in [-0.78, 0.78]
    if abs(lx) > 0.82:
        return 0.0, 0.0
    t = (lx + 0.78) / 1.56
    if t <= 0.0 or t >= 1.0:
        return 0.0, 0.0
    # Slight natural bend
    curve = 0.07 * sin(t * pi)
    width = 0.46 * (sin(t * pi) ** 0.78) * (1.0 - 0.18 * t)
    d = abs(ly - curve)
    edge = 1.0 - smoothstep(width - 0.07, width + 0.04, d)
    if edge <= 0.0:
        return 0.0, 0.0
    vein = exp(-((ly - curve) / 0.045) ** 2) * 0.24 * sin(t * pi)
    shade = 0.78 + 0.14 * (1.0 - d / max(width, 0.05)) + vein
    return clamp(shade), clamp(edge * 0.96)


def tile_snowflake(u, v):
    """Delicate six-pointed snow crystal."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.86:
        return 0.0, 0.0
    ang = atan2(y, x)
    # Fold angle into 6-fold symmetry
    sector = pi / 3.0
    a = abs(((ang + pi) % sector) - sector * 0.5)
    # Main arm along a = 0
    arm_dist = r * sin(a)
    arm_len = r * cos(a)
    arm = exp(-((arm_dist / 0.075) ** 2)) * (1.0 - smoothstep(0.64, 0.82, arm_len))
    # Small diagonal branches around r = 0.38..0.58
    bx = arm_len - 0.42
    branch_d = abs(arm_dist - max(0.0, bx) * 0.65)
    branch = exp(-((branch_d / 0.055) ** 2)) * smoothstep(0.26, 0.36, arm_len) * (1.0 - smoothstep(0.55, 0.70, arm_len))
    core = exp(-((r / 0.20) ** 2))
    soft = exp(-((r / 0.55) ** 2)) * 0.28
    alpha = clamp(max(arm, branch * 0.82, core) + soft)
    return 1.0, alpha


def tile_dust(u, v):
    """Soft wind-blown sand / dust puff with a few fine grains."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x * 0.85, y * 1.15)
    puff = exp(-r * r * 3.4) * 0.75
    grains = (
        (-0.28, -0.10, 0.15, 0.70),
        (0.24, 0.14, 0.13, 0.65),
        (0.06, -0.22, 0.11, 0.60),
        (-0.10, 0.26, 0.12, 0.55),
    )
    val = puff
    for gx, gy, gr, ga in grains:
        d = hypot(x - gx, y - gy) / gr
        val = max(val, exp(-d * d * 2.0) * ga)
    alpha = clamp(val * (1.0 - smoothstep(0.62, 0.90, hypot(x, y))))
    return 0.95, alpha


def tile_ember(u, v):
    """Bright stretched ember / ash spark."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x * 0.72, y * 1.45)
    core = exp(-r * r * 6.5)
    glow = exp(-hypot(x, y) ** 2 * 2.6) * 0.55
    alpha = clamp((core + glow) * (1.0 - smoothstep(0.65, 0.90, hypot(x, y))))
    bright = clamp(0.82 + 0.18 * core)
    return bright, alpha


def tile_spore(u, v):
    """Soft glowing firefly / marsh spore orb."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.88:
        return 0.0, 0.0
    core = exp(-((r / 0.22) ** 2))
    halo = exp(-((r / 0.58) ** 2)) * 0.48
    alpha = clamp((core + halo) * (1.0 - smoothstep(0.66, 0.88, r)))
    return clamp(0.85 + 0.15 * core), alpha


def tile_petal(u, v):
    """Small rounded meadow / autumn petal."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    # Heart-like rounded teardrop
    ca, sa = cos(-0.35), sin(-0.35)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca
    # Wider at +lx, tapered at -lx
    t = (lx + 0.65) / 1.30
    if t <= 0.0 or t >= 1.0:
        return 0.0, 0.0
    width = 0.48 * sqrt(t) * (1.0 - 0.45 * (t ** 2.4))
    d = abs(ly)
    edge = 1.0 - smoothstep(width - 0.08, width + 0.05, d)
    shade = 0.82 + 0.18 * (1.0 - d / max(width, 0.05))
    return clamp(shade), clamp(edge * 0.94)


def tile_curl(u, v):
    """Soft curved breeze accent for turning / return gusts."""
    if u < 0.03 or u > 0.97 or v < 0.05 or v > 0.95:
        return 0.0, 0.0
    # Gentle arch peaking near u = 0.55
    arch = 0.68 - 0.38 * sin(u * pi)
    half_w = 0.04 + 0.11 * sin(u * pi)
    d = abs(v - arch) / max(half_w, 1e-4)
    core = exp(-d * d * 2.2)
    along = smoothstep(0.04, 0.30, u) * smoothstep(0.96, 0.70, u)
    return clamp(0.82 + 0.18 * core), clamp(core * along * 0.92)


def sample_pixel(px, py):
    # Top-down coordinates (py = 0 is top of image)
    if py < 64:
        return wisp_primary((px + 0.5) / 256.0, (py + 0.5) / 64.0)
    if py < 128:
        return wisp_twin((px + 0.5) / 256.0, (py - 64 + 0.5) / 64.0)
    if py < 192:
        col = px // 64
        u = (px % 64 + 0.5) / 64.0
        v = (py - 128 + 0.5) / 64.0
        if col == 0:
            return tile_leaf(u, v)
        if col == 1:
            return tile_snowflake(u, v)
        if col == 2:
            return tile_dust(u, v)
        return tile_ember(u, v)
    v = (py - 192 + 0.5) / 64.0
    if px < 64:
        return tile_spore((px + 0.5) / 64.0, v)
    if px < 128:
        return tile_petal((px - 64 + 0.5) / 64.0, v)
    return tile_curl((px - 128 + 0.5) / 128.0, v)


def main():
    pixels = bytearray()
    for py in range(SIZE):
        for px in range(SIZE):
            bright, alpha = sample_pixel(px, py)
            c = round(clamp(bright) * 255)
            a = round(clamp(alpha) * 255)
            # BGRA order, top-left origin (descriptor 0x28)
            pixels.extend((c, c, c, a))
    header = pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    TARGET.write_bytes(header + pixels)
    print(f"written {len(header) + len(pixels)} bytes to {TARGET}")


if __name__ == "__main__":
    main()
