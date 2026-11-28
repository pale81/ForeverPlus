#!/usr/bin/env python3
"""Build Guiding Wind textures (Ghost of Tsushima inspired):

1. Media/GuidingWindRibbon.tga (128x64 RGBA):
   Dedicated seamless horizontal silk-ribbon cross-section for SimpleLine segments.
   u runs along each curved ribbon segment (seamless periodic fiber);
   v runs across the ribbon thickness (crisp bright silk core + delicate air halo,
   softly tapering to 0 before the edges to avoid any hard border).

2. Media/GuidingWind.tga (512x256 RGBA, 4x2 grid of 128x128 particle tiles):
   Row 0 (v = 0.00..0.50):
     0 (u = 0.00..0.25): Curved grass blade / reed leaf
     1 (u = 0.25..0.50): Slender hand-shaded forest / maple-style leaf
     2 (u = 0.50..0.75): Delicate crystalline snowflake
     3 (u = 0.75..1.00): Wind-stretched desert sand wisp & fine grains
   Row 1 (v = 0.50..1.00):
     0 (u = 0.00..0.25): Sharp glowing ember with slender spark tail
     1 (u = 0.25..0.50): Soft marsh firefly / wisp spark with trailing glow
     2 (u = 0.50..0.75): Delicate notched blossom / autumn petal
     3 (u = 0.75..1.00): Fine elongated air glint / wind-blown pollen streak
"""
from math import atan2, cos, exp, floor, hypot, pi, sin
from pathlib import Path
from struct import pack

MEDIA_DIR = Path(__file__).resolve().parent.parent / "Media"
RIBBON_TARGET = MEDIA_DIR / "GuidingWindRibbon.tga"
ATLAS_TARGET = MEDIA_DIR / "GuidingWind.tga"

RIBBON_W, RIBBON_H = 128, 64
ATLAS_W, ATLAS_H = 512, 256

# Deterministic value noise table
_PERM = [((i * 1103515245 + 12345) >> 16) & 255 for i in range(512)]
_VAL = [(((i * 2246822519) ^ (i * 3266489917)) & 65535) / 65535.0 for i in range(256)]


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def vnoise(x, y):
    ix = floor(x)
    iy = floor(y)
    fx = x - ix
    fy = y - iy
    ux = fx * fx * (3.0 - 2.0 * fx)
    uy = fy * fy * (3.0 - 2.0 * fy)
    ix0 = ix & 255
    iy0 = iy & 255
    ix1 = (ix0 + 1) & 255
    iy1 = (iy0 + 1) & 255
    p = _PERM
    val = _VAL
    a = val[(p[ix0] + iy0) & 255]
    b = val[(p[ix1] + iy0) & 255]
    c = val[(p[ix0] + iy1) & 255]
    d = val[(p[ix1] + iy1) & 255]
    return (a + (b - a) * ux) + ((c + (d - c) * ux) - (a + (b - a) * ux)) * uy


def fbm(x, y, octaves=3):
    total = 0.0
    amp = 0.5
    norm = 0.0
    freq = 1.0
    for _ in range(octaves):
        total += vnoise(x * freq, y * freq) * amp
        norm += amp
        freq *= 2.03
        amp *= 0.5
    return total / norm


def ribbon_pixel(u, v):
    """Crisp, silky Ghost-of-Tsushima wind-ribbon segment with soft overlap end-feathering."""
    if v <= 0.03 or v >= 0.97 or u <= 0.005 or u >= 0.995:
        return 0.0, 0.0

    # End-feathering tuned to 18% tangent overlap on each side (total 26.5% overlap fraction)
    # so adjacent SimpleLine segments blend seamlessly with zero joint dots or outer-curve gaps.
    ramp = 0.265
    end_fade = min(clamp(u / ramp), clamp((1.0 - u) / ramp)) ** 0.85

    dv = v - 0.50
    # Luminous, crisp inner silk ribbon core
    core = exp(-((dv / 0.135) ** 2))
    # Smooth translucent silk body framing the core
    sheath = exp(-((dv / 0.24) ** 2)) * 0.48
    # Two whisper-fine companion hair filaments
    fil_top = exp(-(((dv + 0.21) / 0.052) ** 2)) * 0.22
    fil_bot = exp(-(((dv - 0.22) / 0.048) ** 2)) * 0.16
    # Delicate soft air halo
    halo = exp(-((dv / 0.34) ** 2)) * 0.16

    edge_mask = smoothstep(0.03, 0.14, v) * smoothstep(0.97, 0.86, v)
    raw = (core + sheath + fil_top + fil_bot + halo) * edge_mask * end_fade
    alpha = clamp(raw)
    bright = clamp(0.88 + 0.12 * core)
    return bright, alpha


def tile_blade(u, v):
    """Slender, gracefully arched wind-blown grass blade / reed leaf."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    # Tilt slightly so the diagonal blade uses full tile span cleanly.
    ca, sa = cos(-0.28), sin(-0.28)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca

    t = (lx + 0.86) / 1.72
    if t <= 0.0 or t >= 1.0:
        return 0.0, 0.0

    # Graceful S-arch along the blade
    arch = 0.16 * sin(t * pi) - 0.05 * sin(t * 2.0 * pi)
    # Tapered base, sleek body, razor-fine tip
    width = 0.115 * (sin(t * pi) ** 0.55) * (1.0 - 0.38 * t)
    dy = ly - arch
    d = abs(dy)
    alpha = 1.0 - smoothstep(width - 0.028, width + 0.022, d)
    if alpha <= 0.0:
        return 0.0, 0.0

    ridge = exp(-((dy / max(width * 0.32, 0.01)) ** 2)) * 0.18
    fold = 0.07 if dy < 0 else -0.07
    shade = 0.78 + fold + ridge - 0.10 * t
    return clamp(shade), clamp(alpha * 0.96)


def tile_leaf(u, v):
    """Slender, dynamic hand-shaded wind leaf (clean silhouette, fine stem and midrib)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    ca, sa = cos(0.36), sin(0.36)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca

    # Fine curved petiole stem on the left
    stem_alpha = 0.0
    if -0.88 <= lx <= -0.54:
        st = (lx + 0.88) / 0.34
        sc = -0.055 * (1.0 - st) * (1.0 - st)
        sd = abs(ly - sc)
        stem_alpha = (1.0 - smoothstep(0.018, 0.036, sd)) * smoothstep(0.0, 0.18, st)

    blade_alpha = 0.0
    shade = 0.64
    if -0.58 <= lx <= 0.86:
        t = (lx + 0.58) / 1.44
        if 0.0 < t < 1.0:
            curve = 0.095 * sin(t * pi)
            # Slender lance/willow-maple hybrid silhouette with subtle organic undulation
            ripple = 0.028 * sin(t * 5.0 * pi) * sin(t * pi)
            width = (0.31 * (sin(t * pi) ** 0.78) * (1.0 - 0.28 * t)) + ripple
            dy = ly - curve
            d = abs(dy)
            blade_alpha = 1.0 - smoothstep(width - 0.040, width + 0.024, d)
            if blade_alpha > 0.0:
                fold = 0.10 if dy < 0 else -0.08
                midrib = exp(-((dy / 0.024) ** 2)) * 0.22 * sin(t * pi)
                vein = exp(-((sin((t * 5.0 - d * 2.8) * pi) / 0.24) ** 2)) * 0.07 * sin(t * pi)
                tex = (fbm(u * 9.0 + 2.1, v * 9.0 + 4.3, 2) - 0.5) * 0.08
                rim = -0.10 * smoothstep(0.68, 1.0, d / max(width, 0.04))
                shade = 0.78 + fold + midrib + vein + tex + rim

    alpha = clamp(max(blade_alpha * 0.96, stem_alpha * 0.90))
    if alpha <= 0.0:
        return 0.0, 0.0
    if stem_alpha > blade_alpha:
        shade = 0.56
    return clamp(shade), alpha


def tile_snowflake(u, v):
    """Delicate, airy six-pointed ice crystal (finer and less blocky)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.88:
        return 0.0, 0.0
    ang = atan2(y, x)
    sector = pi / 3.0
    a = abs(((ang + pi) % sector) - sector * 0.5)
    arm_dist = r * sin(a)
    arm_len = r * cos(a)
    arm = exp(-((arm_dist / 0.038) ** 2)) * (1.0 - smoothstep(0.64, 0.84, arm_len))
    b1 = abs(arm_dist - max(0.0, arm_len - 0.28) * 0.62)
    br1 = exp(-((b1 / 0.030) ** 2)) * smoothstep(0.24, 0.31, arm_len) * (1.0 - smoothstep(0.46, 0.56, arm_len))
    b2 = abs(arm_dist - max(0.0, arm_len - 0.48) * 0.62)
    br2 = exp(-((b2 / 0.026) ** 2)) * smoothstep(0.45, 0.52, arm_len) * (1.0 - smoothstep(0.64, 0.74, arm_len))
    core = exp(-((r / 0.14) ** 2))
    edge_fade = 1.0 - smoothstep(0.50, 0.86, r)
    soft = exp(-((r / 0.42) ** 2)) * 0.24 * edge_fade
    alpha = clamp(max(arm, br1 * 0.82, br2 * 0.72, core) + soft)
    bright = clamp(0.86 + 0.14 * max(arm, core))
    return bright, alpha


def tile_dust(u, v):
    """Wind-drawn desert sand streak with crisp drifting grains."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x * 0.78, y * 1.65)
    if r > 0.94:
        return 0.0, 0.0
    cloud = fbm(u * 4.5 + 3.1, v * 12.0 + 1.4, 3)
    edge_fade = 1.0 - smoothstep(0.42, 0.90, r)
    wisp = exp(-r * r * 3.4) * edge_fade * (0.38 + 0.62 * smoothstep(0.28, 0.76, cloud))
    grains = (
        (-0.42, -0.05, 0.065, 0.78),
        (0.32, 0.08, 0.060, 0.74),
        (0.06, -0.14, 0.055, 0.66),
        (-0.14, 0.16, 0.060, 0.60),
        (0.48, -0.03, 0.050, 0.56),
    )
    val = wisp
    for gx, gy, gr, ga in grains:
        d = hypot(x - gx, y - gy) / gr
        val = max(val, exp(-d * d * 2.8) * ga * edge_fade)
    return clamp(0.78 + 0.20 * cloud), clamp(val)


def tile_ember(u, v):
    """Sharp glowing volcanic ember with a thin curved spark tail."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.92:
        return 0.0, 0.0
    head_d = hypot((x - 0.38) * 1.60, (y - 0.04) * 2.10)
    core = exp(-head_d * head_d * 11.0)
    glow = exp(-head_d * head_d * 3.2) * 0.44
    tail = 0.0
    if -0.84 <= x <= 0.40:
        t = (x + 0.84) / 1.24
        cy = 0.04 - 0.14 * ((1.0 - t) ** 1.9) + 0.03 * sin(t * pi)
        tw = 0.016 + 0.085 * (t ** 1.25)
        td = abs(y - cy) / max(tw, 1e-4)
        noise = fbm(u * 8.5 + 4.2, v * 12.0 + 1.1, 2)
        tail = exp(-td * td * 2.2) * smoothstep(0.02, 0.30, t) * (0.56 + 0.44 * noise) * 0.86
    edge_fade = 1.0 - smoothstep(0.64, 0.90, r)
    alpha = clamp(max(core + glow, tail) * edge_fade)
    bright = clamp(0.76 + 0.24 * core)
    return bright, alpha


def tile_spore(u, v):
    """Delicate marsh firefly / wisp orb with subtle motion tail."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.88:
        return 0.0, 0.0
    hd = hypot(x - 0.16, y)
    core = exp(-((hd / 0.15) ** 2))
    edge_fade = 1.0 - smoothstep(0.52, 0.86, r)
    halo = exp(-((hd / 0.38) ** 2)) * 0.38 * edge_fade
    tail = 0.0
    if -0.72 <= x <= 0.16:
        t = (x + 0.72) / 0.88
        td = abs(y) / max(0.02 + 0.10 * t, 1e-4)
        tail = exp(-td * td * 2.4) * smoothstep(0.0, 0.4, t) * 0.34 * edge_fade
    alpha = clamp(max(core + halo, tail))
    return clamp(0.86 + 0.14 * core), alpha


def tile_petal(u, v):
    """Graceful notched blossom / autumn petal (classic Tsushima silhouette)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    ca, sa = cos(-0.30), sin(-0.30)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca

    t = (lx + 0.74) / 1.48
    if t <= 0.0 or t >= 1.0:
        return 0.0, 0.0

    curve = 0.09 * sin(t * pi)
    # Tapered base on left, full gently cupped body, subtle sakura notch on right tip
    width = 0.39 * (sin(t * pi) ** 0.72) * (0.68 + 0.54 * t) * (1.0 - 0.30 * (t ** 3.0))
    dy = ly - curve
    d = abs(dy)
    edge = 1.0 - smoothstep(width - 0.048, width + 0.026, d)
    # Crisp sakura notch at the right tip (cuts cleanly to transparent)
    if t > 0.74:
        notch_d = hypot((t - 1.00) * 4.2, dy * 5.0)
        notch = smoothstep(0.42, 0.72, notch_d)
        edge *= notch
    if edge <= 0.0:
        return 0.0, 0.0

    fold = 0.09 if dy < 0 else -0.06
    tex = (fbm(u * 8.0 + 5.1, v * 8.0 + 7.2, 2) - 0.5) * 0.08
    shade = 0.80 + fold + 0.14 * (1.0 - d / max(width, 0.05)) + tex
    return clamp(shade), clamp(edge * 0.95)


def tile_mote(u, v):
    """Slender, directional wind-glint / silk spark streak (aligned along +u)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    if abs(x) > 0.94 or abs(y) > 0.40:
        return 0.0, 0.0
    t = (x + 0.90) / 1.80
    if t <= 0.0 or t >= 1.0:
        return 0.0, 0.0
    # Very thin elongated needle streak peaking near the leading right third
    along = smoothstep(0.0, 0.58, t) * smoothstep(1.0, 0.74, t)
    thick = 0.024 + 0.055 * along
    dy = abs(y) / max(thick, 1e-4)
    core = exp(-dy * dy * 2.2) * along
    halo = exp(-dy * dy * 0.65) * 0.28 * along
    alpha = clamp((core + halo) * 0.92)
    bright = clamp(0.88 + 0.12 * core)
    return bright, alpha


def write_tga(path, width, height, sampler):
    pixels = bytearray()
    for py in range(height):
        for px in range(width):
            bright, alpha = sampler(px, py)
            c = round(clamp(bright) * 255)
            a = round(clamp(alpha) * 255)
            # BGRA, top-left origin (descriptor 0x28)
            pixels.extend((c, c, c, a))
    header = pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
    path.write_bytes(header + pixels)
    print(f"written {len(header) + len(pixels)} bytes to {path} ({width}x{height})")


def sample_ribbon(px, py):
    return ribbon_pixel((px + 0.5) / RIBBON_W, (py + 0.5) / RIBBON_H)


def sample_atlas(px, py):
    col = px // 128
    u = (px % 128 + 0.5) / 128.0
    if py < 128:
        v = (py + 0.5) / 128.0
        if col == 0:
            return tile_blade(u, v)
        if col == 1:
            return tile_leaf(u, v)
        if col == 2:
            return tile_snowflake(u, v)
        return tile_dust(u, v)
    v = (py - 128 + 0.5) / 128.0
    if col == 0:
        return tile_ember(u, v)
    if col == 1:
        return tile_spore(u, v)
    if col == 2:
        return tile_petal(u, v)
    return tile_mote(u, v)


def main():
    write_tga(RIBBON_TARGET, RIBBON_W, RIBBON_H, sample_ribbon)
    write_tga(ATLAS_TARGET, ATLAS_W, ATLAS_H, sample_atlas)


if __name__ == "__main__":
    main()
