#!/usr/bin/env python3
"""Build Media/GuidingWind.tga: painterly WoW-style wind wisps and biome particles (512x512 RGBA).

Layout (top-to-bottom in UV space, v = 0 at top, v = 1 at bottom):
  Row 0 (v = 0.00..0.25, 512x128): Painterly streaky wind brush segment (head right).
  Row 1 (v = 0.25..0.50, 512x128): Atmospheric broken air/mist veil (head right).
  Row 2 (v = 0.50..0.75, 4 tiles of 128x128):
    0 (u = 0.00..0.25): Painterly wind curl / spiral eddy.
    1 (u = 0.25..0.50): Hand-shaded forest leaf with stem, serrated edge and veins.
    2 (u = 0.50..0.75): Six-pointed crystalline snowflake with soft frost corona.
    3 (u = 0.75..1.00): Wind-streaked desert sand / dust puff with fine grains.
  Row 3 (v = 0.75..1.00, 4 tiles of 128x128):
    0 (u = 0.00..0.25): Curved glowing ember with trailing ash tail.
    1 (u = 0.25..0.50): Soft marsh spore / wisp glow with subtle halo.
    2 (u = 0.50..0.75): Curved autumn / meadow petal with soft shading.
    3 (u = 0.75..1.00): Fine atmospheric dust / pollen mote cluster.
"""
from math import atan2, cos, exp, floor, hypot, pi, sin, sqrt
from pathlib import Path
from struct import pack

SIZE = 512
TARGET = Path(__file__).resolve().parent.parent / "Media/GuidingWind.tga"

# Precomputed permutation table for fast deterministic value noise.
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


def wisp_brush(u, v):
    """Painterly multi-fiber WoW wind brushstroke flowing left-to-right (head right)."""
    if u < 0.02 or u > 0.98 or v < 0.04 or v > 0.96:
        return 0.0, 0.0
    # Slight natural sweep plus domain-warped turbulence along the flow
    warp = (fbm(u * 4.5 + 1.3, v * 5.0 + 2.7, 3) - 0.5) * 0.14
    center = 0.50 + 0.075 * sin((u - 0.10) * 1.85 * pi) * smoothstep(0.04, 0.35, u) + warp * 0.45

    # Tapered brushstroke profile: wispy trailing tail, expressive belly, refined leading tip
    along = smoothstep(0.03, 0.42, u) * smoothstep(0.97, 0.72, u)
    width = 0.05 + 0.18 * (smoothstep(0.05, 0.48, u) * smoothstep(0.97, 0.68, u)) ** 0.8

    # Primary painted stroke + two fine offset wind filaments
    dv = (v - center) / max(width, 1e-4)
    main_body = exp(-dv * dv * 1.9)

    c_upper = center - width * 0.78 + 0.035 * sin(u * 3.1 * pi + 0.6)
    c_lower = center + width * 0.72 + 0.030 * sin(u * 2.7 * pi - 1.1)
    du = (v - c_upper) / max(width * 0.38, 1e-4)
    dl = (v - c_lower) / max(width * 0.34, 1e-4)
    fil_upper = exp(-du * du * 2.6) * 0.62 * smoothstep(0.08, 0.45, u) * smoothstep(0.92, 0.62, u)
    fil_lower = exp(-dl * dl * 2.8) * 0.52 * smoothstep(0.14, 0.52, u) * smoothstep(0.88, 0.55, u)

    # Stretched brush grain: fine fibers running along u, broken softly at edges
    grain = fbm(u * 5.2 + 7.1, v * 22.0 + warp * 12.0, 3)
    fine = vnoise(u * 14.0 + 3.4, v * 34.0 + 1.9)
    fiber = 0.48 + 0.52 * smoothstep(0.24, 0.76, grain * 0.72 + fine * 0.28)

    # Soft misty outer envelope so segments blend seamlessly along curved tracks
    mist = exp(-dv * dv * 0.55) * 0.28 * (0.55 + 0.45 * grain)
    raw = (main_body * fiber + (fil_upper + fil_lower) * (0.65 + 0.35 * fine) + mist) * along
    alpha = clamp(raw * 0.96)
    # Warm hand-painted luminance variation (brighter core, slightly shaded belly)
    bright = clamp(0.76 + 0.20 * main_body * fiber + 0.06 * smoothstep(0.45, 0.85, u))
    return bright, alpha


def wisp_veil(u, v):
    """Wide, soft, wind-torn atmospheric mist veil for subtle BLEND depth layer."""
    if u < 0.02 or u > 0.98 or v < 0.04 or v > 0.96:
        return 0.0, 0.0
    warp_x = (fbm(u * 3.0 + 4.1, v * 4.5 + 0.9, 3) - 0.5) * 0.18
    warp_y = (fbm(u * 3.5 + 9.2, v * 5.0 + 6.4, 3) - 0.5) * 0.16
    center = 0.50 + 0.06 * sin(u * 1.6 * pi) + warp_y * 0.55
    along = smoothstep(0.03, 0.36, u) * smoothstep(0.97, 0.62, u)
    dv = (v - center) / 0.28
    base = exp(-dv * dv * 1.45)
    cloud = fbm((u + warp_x) * 4.8 + 11.3, (v + warp_y) * 9.5 + 2.1, 3)
    wisps = smoothstep(0.26, 0.78, cloud)
    alpha = clamp(base * (0.38 + 0.62 * wisps) * along * 0.88)
    bright = clamp(0.78 + 0.18 * wisps)
    return bright, alpha


def _seg_dist(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    c1 = vx * wx + vy * wy
    if c1 <= 0.0:
        return hypot(px - ax, py - ay), 0.0
    c2 = vx * vx + vy * vy
    if c2 <= c1:
        return hypot(px - bx, py - by), 1.0
    s = c1 / c2
    return hypot(px - (ax + s * vx), py - (ay + s * vy)), s


# Precomputed smooth spiral polyline for tile_curl (tail enters bottom-left, curls inward smoothly).
_CURL_PTS = []
for _i in range(49):
    _t = _i / 48.0
    _ang = -2.45 + _t * 2.40 * pi
    _rad = 0.76 * ((1.0 - 0.78 * _t) ** 1.02)
    _CURL_PTS.append((_rad * cos(_ang) + 0.03 * (1.0 - _t), _rad * sin(_ang) - 0.02 * (1.0 - _t), _t))


def tile_curl(u, v):
    """Painterly WoW wind spiral eddy that unfurls and dissipates gracefully."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.94:
        return 0.0, 0.0

    best = 9.0
    best_t = 0.0
    pts = _CURL_PTS
    for i in range(len(pts) - 1):
        ax, ay, ta = pts[i]
        bx, by, tb = pts[i + 1]
        d, s = _seg_dist(x, y, ax, ay, bx, by)
        t = ta + (tb - ta) * s
        w = 0.026 + 0.072 * (sin(t * pi) ** 0.85) * (1.0 - 0.30 * t)
        nd = d / max(w, 1e-4)
        if nd < best:
            best = nd
            best_t = t

    if best > 2.8:
        return 0.0, 0.0
    grain = fbm(u * 8.5 + 2.1, v * 8.5 + 5.4, 3)
    stroke = exp(-best * best * 2.1) * (0.56 + 0.44 * smoothstep(0.20, 0.78, grain))
    halo = exp(-best * best * 0.60) * 0.24 * (0.6 + 0.4 * grain)
    taper = smoothstep(0.01, 0.20, best_t) * smoothstep(0.99, 0.76, best_t)
    edge_fade = 1.0 - smoothstep(0.72, 0.93, r)
    alpha = clamp((stroke + halo) * taper * edge_fade * 0.95)
    bright = clamp(0.78 + 0.22 * stroke)
    return bright, alpha


def tile_leaf(u, v):
    """Hand-shaded forest leaf with small stem, organic lobed edge, central and side veins."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    # Tilt 26 degrees for natural tumble
    ca, sa = cos(0.45), sin(0.45)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca

    # Small curved stem on left side (lx in [-0.84, -0.56])
    stem_alpha = 0.0
    if -0.86 <= lx <= -0.52:
        st = (lx + 0.86) / 0.34
        sc = -0.05 * (1.0 - st) * (1.0 - st)
        sd = abs(ly - sc)
        stem_alpha = (1.0 - smoothstep(0.024, 0.048, sd)) * smoothstep(0.0, 0.15, st)

    # Leaf blade in [-0.58, 0.82]
    blade_alpha = 0.0
    shade = 0.62
    if -0.60 <= lx <= 0.84:
        t = (lx + 0.58) / 1.40
        if 0.0 < t < 1.0:
            curve = 0.065 * sin(t * pi)
            # Gentle organic edge serration (WoW hand-painted foliage silhouette)
            serrate = 0.045 * sin(t * 7.0 * pi) * sin(t * pi)
            width = (0.44 * (sin(t * pi) ** 0.72) * (1.0 - 0.20 * t)) + serrate
            dy = ly - curve
            d = abs(dy)
            blade_alpha = 1.0 - smoothstep(width - 0.055, width + 0.032, d)
            if blade_alpha > 0.0:
                # Two-tone hand-painted lighting across the midrib fold
                fold = 0.09 if dy < 0 else -0.07
                midrib = exp(-((dy / 0.032) ** 2)) * 0.22 * sin(t * pi)
                # Diagonal side veins branching from midrib
                vein_phase = sin((t * 5.5 - d * 2.4) * pi)
                side_veins = exp(-((vein_phase / 0.22) ** 2)) * 0.08 * smoothstep(0.10, 0.35, t) * smoothstep(0.90, 0.60, t)
                tex = (fbm(u * 10.0 + 1.7, v * 10.0 + 3.2, 2) - 0.5) * 0.10
                rim_dark = -0.10 * smoothstep(0.65, 1.0, d / max(width, 0.05))
                shade = 0.76 + fold + midrib + side_veins + tex + rim_dark

    alpha = clamp(max(blade_alpha * 0.96, stem_alpha * 0.92))
    if alpha <= 0.0:
        return 0.0, 0.0
    if stem_alpha > blade_alpha:
        shade = 0.58
    return clamp(shade), alpha


def tile_snowflake(u, v):
    """Delicate six-pointed ice crystal with double branches and soft frost aura."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.90:
        return 0.0, 0.0
    ang = atan2(y, x)
    sector = pi / 3.0
    a = abs(((ang + pi) % sector) - sector * 0.5)
    arm_dist = r * sin(a)
    arm_len = r * cos(a)
    arm = exp(-((arm_dist / 0.058) ** 2)) * (1.0 - smoothstep(0.68, 0.86, arm_len))
    # Two sets of crystalline diagonal branches
    b1 = abs(arm_dist - max(0.0, arm_len - 0.30) * 0.62)
    br1 = exp(-((b1 / 0.044) ** 2)) * smoothstep(0.24, 0.32, arm_len) * (1.0 - smoothstep(0.48, 0.60, arm_len))
    b2 = abs(arm_dist - max(0.0, arm_len - 0.52) * 0.62)
    br2 = exp(-((b2 / 0.038) ** 2)) * smoothstep(0.48, 0.56, arm_len) * (1.0 - smoothstep(0.66, 0.76, arm_len))
    core = exp(-((r / 0.18) ** 2))
    edge_fade = 1.0 - smoothstep(0.56, 0.88, r)
    soft = exp(-((r / 0.48) ** 2)) * 0.28 * edge_fade * (0.7 + 0.3 * fbm(u * 6.0, v * 6.0, 2))
    alpha = clamp(max(arm, br1 * 0.85, br2 * 0.78, core) + soft)
    bright = clamp(0.84 + 0.16 * max(arm, core))
    return bright, alpha


def tile_dust(u, v):
    """Wind-streaked desert sand puff with FBM wisps and fine drifting grains."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x * 0.86, y * 1.18)
    if r > 0.94:
        return 0.0, 0.0
    cloud = fbm(u * 5.2 + 3.1, v * 9.5 + 1.4, 3)
    edge_fade = 1.0 - smoothstep(0.45, 0.90, r)
    puff = exp(-r * r * 3.0) * edge_fade * (0.42 + 0.58 * smoothstep(0.26, 0.78, cloud))
    grains = (
        (-0.34, -0.08, 0.09, 0.72),
        (0.28, 0.12, 0.08, 0.66),
        (0.08, -0.20, 0.07, 0.62),
        (-0.12, 0.24, 0.08, 0.56),
        (0.40, -0.05, 0.06, 0.52),
    )
    val = puff
    for gx, gy, gr, ga in grains:
        d = hypot(x - gx, y - gy) / gr
        val = max(val, exp(-d * d * 2.6) * ga * edge_fade)
    alpha = clamp(val)
    bright = clamp(0.76 + 0.20 * cloud)
    return bright, alpha


def tile_ember(u, v):
    """Curved glowing ember core with a wispy trailing ash spark tail."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.92:
        return 0.0, 0.0
    # Head near (+0.34, +0.05), tail curving back to (-0.74, -0.10)
    head_d = hypot((x - 0.34) * 1.35, (y - 0.05) * 1.85)
    core = exp(-head_d * head_d * 9.5)
    glow = exp(-head_d * head_d * 2.8) * 0.48
    tail = 0.0
    if -0.80 <= x <= 0.36:
        t = (x + 0.80) / 1.16
        cy = 0.05 - 0.16 * ((1.0 - t) ** 1.8) + 0.04 * sin(t * pi)
        tw = 0.025 + 0.13 * (t ** 1.1)
        td = abs(y - cy) / max(tw, 1e-4)
        noise = fbm(u * 8.5 + 4.2, v * 11.0 + 1.1, 2)
        tail = exp(-td * td * 2.0) * smoothstep(0.02, 0.35, t) * (0.52 + 0.48 * noise) * 0.82
    edge_fade = 1.0 - smoothstep(0.62, 0.90, r)
    alpha = clamp(max(core + glow, tail) * edge_fade)
    bright = clamp(0.72 + 0.28 * core)
    return bright, alpha


def tile_spore(u, v):
    """Soft glowing marsh wisp / firefly orb with delicate organic corona."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.90:
        return 0.0, 0.0
    n = fbm(u * 5.5 + 8.3, v * 5.5 + 2.9, 2)
    core = exp(-((r / 0.19) ** 2))
    edge_fade = 1.0 - smoothstep(0.54, 0.88, r)
    halo = exp(-((r / 0.46) ** 2)) * (0.36 + 0.24 * n) * edge_fade
    alpha = clamp(core + halo)
    return clamp(0.84 + 0.16 * core), alpha


def tile_petal(u, v):
    """Curved hand-shaded autumn / meadow petal with soft rounded tip and fold."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    ca, sa = cos(-0.34), sin(-0.34)
    lx = x * ca + y * sa
    ly = -x * sa + y * ca
    t = (lx + 0.72) / 1.44
    if t <= 0.0 or t >= 1.0:
        return 0.0, 0.0
    curve = 0.08 * sin(t * pi)
    # Tapered base on left, lush rounded tip on right with a subtle natural dimple
    width = 0.44 * (sin(t * pi) ** 0.72) * (0.72 + 0.46 * t) * (1.0 - 0.32 * (t ** 3.2))
    dy = ly - curve
    d = abs(dy)
    edge = 1.0 - smoothstep(width - 0.055, width + 0.032, d)
    if edge <= 0.0:
        return 0.0, 0.0
    fold = 0.08 if dy < 0 else -0.06
    tex = (fbm(u * 8.0 + 5.1, v * 8.0 + 7.2, 2) - 0.5) * 0.10
    shade = 0.78 + fold + 0.14 * (1.0 - d / max(width, 0.05)) + tex
    return clamp(shade), clamp(edge * 0.95)


def tile_mote(u, v):
    """Cluster of 3 tiny wind-blown dust / pollen motes for airy parallax depth."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    motes = (
        (-0.26, 0.16, 0.24, 0.92),
        (0.30, -0.18, 0.19, 0.78),
        (0.06, 0.24, 0.15, 0.68),
    )
    alpha = 0.0
    bright = 0.88
    for mx, my, mr, ma in motes:
        d = hypot(x - mx, y - my) / mr
        c = exp(-d * d * 2.6) * ma
        if c > alpha:
            alpha = c
            bright = 0.84 + 0.16 * exp(-d * d * 6.0)
    return clamp(bright), clamp(alpha)


def sample_pixel(px, py):
    if py < 128:
        return wisp_brush((px + 0.5) / 512.0, (py + 0.5) / 128.0)
    if py < 256:
        return wisp_veil((px + 0.5) / 512.0, (py - 128 + 0.5) / 128.0)
    col = px // 128
    u = (px % 128 + 0.5) / 128.0
    if py < 384:
        v = (py - 256 + 0.5) / 128.0
        if col == 0:
            return tile_curl(u, v)
        if col == 1:
            return tile_leaf(u, v)
        if col == 2:
            return tile_snowflake(u, v)
        return tile_dust(u, v)
    v = (py - 384 + 0.5) / 128.0
    if col == 0:
        return tile_ember(u, v)
    if col == 1:
        return tile_spore(u, v)
    if col == 2:
        return tile_petal(u, v)
    return tile_mote(u, v)


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
