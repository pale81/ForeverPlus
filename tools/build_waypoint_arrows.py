#!/usr/bin/env python3
"""Build Media/WaypointArrows.tga: 4 custom waypoint arrow styles (256x256 RGBA).

Layout (2x2 tiles of 128x128, UV origin top-left, tip pointing straight up at 0 rad):
  Tile (0, 0): classic  - Bold delta arrow with indented V-notch and central ridge.
  Tile (1, 0): compass  - Sleek diamond compass needle with center ring and dimmer tail.
  Tile (0, 1): chevron  - Modern double-chevron pointer, airy and low-occlusion.
  Tile (1, 1): rune     - Warcraft-inspired spearhead pointer with side guards and tail diamond.

Each tile is rendered in bright white-to-silver tones with a crisp dark outline and
soft drop shadow so WoW's SetVertexColor tints cleanly while remaining legible over
snow, sand, grass, and dark terrain.
"""
from math import hypot
from pathlib import Path
from struct import pack

SIZE = 256
TILE = 128
TARGET = Path(__file__).resolve().parent.parent / "Media/WaypointArrows.tga"


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def sd_segment(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    denom = vx * vx + vy * vy
    h = clamp((wx * vx + wy * vy) / denom) if denom > 1e-9 else 0.0
    return hypot(wx - vx * h, wy - vy * h)


def sd_polygon(px, py, pts):
    """Exact signed distance to a simple closed polygon (negative inside)."""
    n = len(pts)
    min_d = 1e9
    inside = False
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        d = sd_segment(px, py, xj, yj, xi, yi)
        if d < min_d:
            min_d = d
        if ((yi > py) != (yj > py)) and (px < (xj - xi) * (py - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return -min_d if inside else min_d


def shade_shape(d, fill_rgb, outline_w=0.055, shadow_d=None, shadow_alpha=0.38):
    """Composite a tinted white/silver fill with dark outline and optional drop shadow.

    Returns (r, g, b, a) in 0..1 (non-premultiplied).
    """
    aa = 0.018
    fill_cov = 1.0 - smoothstep(-aa, aa, d)
    outer_cov = 1.0 - smoothstep(outline_w - aa, outline_w + aa, d)
    outline_cov = clamp(outer_cov - fill_cov)

    sh_cov = 0.0
    if shadow_d is not None:
        sh_cov = (1.0 - smoothstep(outline_w - 0.01, outline_w + 0.09, shadow_d)) * shadow_alpha

    # Composite back-to-front: shadow -> dark outline -> bright fill
    r, g, b, a = 0.0, 0.0, 0.0, 0.0

    def over(sr, sg, sb, sa):
        nonlocal r, g, b, a
        if sa <= 0.0:
            return
        out_a = sa + a * (1.0 - sa)
        if out_a <= 1e-6:
            return
        r = (sr * sa + r * a * (1.0 - sa)) / out_a
        g = (sg * sa + g * a * (1.0 - sa)) / out_a
        b = (sb * sa + b * a * (1.0 - sa)) / out_a
        a = out_a

    over(0.02, 0.02, 0.03, sh_cov)
    over(0.06, 0.06, 0.08, outline_cov * 0.94)
    if fill_cov > 0.0:
        fr, fg, fb, fa = fill_rgb
        over(fr, fg, fb, fill_cov * fa)
    return r, g, b, a


# Tile (0, 0): Classic bold delta arrow
CLASSIC_POLY = (
    (0.0, 0.84),
    (0.64, -0.66),
    (0.0, -0.30),
    (-0.64, -0.66),
)


def tile_classic(x, y):
    d = sd_polygon(x, y, CLASSIC_POLY)
    sd = sd_polygon(x - 0.02, y + 0.04, CLASSIC_POLY)
    # Beveled central ridge: slightly brighter left facet, gentle highlight toward tip
    side = 0.96 if x <= 0.0 else 0.82
    ridge_blend = smoothstep(-0.04, 0.04, x)
    base = 0.97 * (1.0 - ridge_blend) + 0.81 * ridge_blend
    tip_glow = smoothstep(-0.45, 0.80, y) * 0.12
    bevel = smoothstep(-0.18, -0.02, d) * 0.08
    v = clamp(base + tip_glow - bevel * (0.5 if side > 0.9 else 0.9), 0.68, 1.0)
    return shade_shape(d, (v, v, clamp(v + 0.02), 1.0), outline_w=0.056, shadow_d=sd)


# Tile (1, 0): Compass needle
COMPASS_TOP = (
    (0.0, 0.88),
    (0.32, 0.04),
    (0.0, -0.10),
    (-0.32, 0.04),
)
COMPASS_BOT = (
    (0.0, -0.76),
    (0.24, 0.02),
    (0.0, 0.10),
    (-0.24, 0.02),
)


def tile_compass(x, y):
    dt = sd_polygon(x, y, COMPASS_TOP)
    db = sd_polygon(x, y, COMPASS_BOT)
    d = min(dt, db)
    sd = min(sd_polygon(x - 0.02, y + 0.04, COMPASS_TOP), sd_polygon(x - 0.02, y + 0.04, COMPASS_BOT))

    # Front half bright white-silver, rear thorn distinctly cooler/darker so direction reads instantly
    is_front = dt <= db
    ridge_blend = smoothstep(-0.03, 0.03, x)
    if is_front:
        v = 0.98 * (1.0 - ridge_blend) + 0.84 * ridge_blend + smoothstep(0.0, 0.85, y) * 0.08
    else:
        v = 0.72 * (1.0 - ridge_blend) + 0.56 * ridge_blend

    r_center = hypot(x, y - 0.02)
    ring_outer = 0.15
    ring_inner = 0.075
    if r_center < ring_outer + 0.03:
        # Subtle dark ring groove and bright hub
        ring_t = smoothstep(ring_outer + 0.02, ring_outer - 0.02, r_center)
        hole_t = smoothstep(ring_inner + 0.02, ring_inner - 0.02, r_center)
        v = v * (1.0 - ring_t) + 0.94 * ring_t
        v = v * (1.0 - hole_t) + 0.20 * hole_t

    v = clamp(v, 0.18, 1.0)
    return shade_shape(d, (v, v, clamp(v + 0.02), 1.0), outline_w=0.052, shadow_d=sd)


# Tile (0, 1): Modern double chevron
CHEVRON_MAIN = (
    (0.0, 0.82),
    (0.70, -0.14),
    (0.50, -0.28),
    (0.0, 0.42),
    (-0.50, -0.28),
    (-0.70, -0.14),
)
CHEVRON_SUB = (
    (0.0, 0.12),
    (0.48, -0.54),
    (0.32, -0.66),
    (0.0, -0.20),
    (-0.32, -0.66),
    (-0.48, -0.54),
)


def tile_chevron(x, y):
    d1 = sd_polygon(x, y, CHEVRON_MAIN)
    sd1 = sd_polygon(x - 0.02, y + 0.04, CHEVRON_MAIN)
    d2 = sd_polygon(x, y, CHEVRON_SUB)
    sd2 = sd_polygon(x - 0.02, y + 0.04, CHEVRON_SUB)

    ridge_blend = smoothstep(-0.04, 0.04, x)
    v1 = clamp(0.98 * (1.0 - ridge_blend) + 0.84 * ridge_blend + smoothstep(-0.2, 0.8, y) * 0.08, 0.72, 1.0)
    v2 = clamp(0.84 * (1.0 - ridge_blend) + 0.72 * ridge_blend, 0.62, 0.92)

    r1, g1, b1, a1 = shade_shape(d1, (v1, v1, clamp(v1 + 0.02), 1.0), outline_w=0.052, shadow_d=sd1)
    r2, g2, b2, a2 = shade_shape(d2, (v2, v2, clamp(v2 + 0.02), 0.88), outline_w=0.046, shadow_d=sd2, shadow_alpha=0.28)

    # Composite main chevron over secondary chevron
    out_a = a1 + a2 * (1.0 - a1)
    if out_a <= 1e-6:
        return 0.0, 0.0, 0.0, 0.0
    r = (r1 * a1 + r2 * a2 * (1.0 - a1)) / out_a
    g = (g1 * a1 + g2 * a2 * (1.0 - a1)) / out_a
    b = (b1 * a1 + b2 * a2 * (1.0 - a1)) / out_a
    return r, g, b, out_a


# Tile (1, 1): Rune spearhead pointer
RUNE_POLY = (
    (0.0, 0.86),
    (0.46, 0.08),
    (0.58, -0.06),
    (0.16, -0.14),
    (0.11, -0.50),
    (0.20, -0.62),
    (0.0, -0.78),
    (-0.20, -0.62),
    (-0.11, -0.50),
    (-0.16, -0.14),
    (-0.58, -0.06),
    (-0.46, 0.08),
)


def tile_rune(x, y):
    d = sd_polygon(x, y, RUNE_POLY)
    sd = sd_polygon(x - 0.02, y + 0.04, RUNE_POLY)

    ridge_blend = smoothstep(-0.035, 0.035, x)
    v = 0.97 * (1.0 - ridge_blend) + 0.80 * ridge_blend
    v += smoothstep(-0.25, 0.82, y) * 0.10
    # Subtle darker fuller groove along the spear spine, ending in a crisp diamond jewel
    spine = sd_segment(x, y, 0.0, 0.50, 0.0, 0.04)
    if spine < 0.048:
        groove = 1.0 - smoothstep(0.012, 0.048, spine)
        v *= 1.0 - 0.26 * groove
    jewel_d = abs(x) * 1.15 + abs(y + 0.05) * 0.95
    if jewel_d < 0.11:
        ring = smoothstep(0.11, 0.075, jewel_d)
        core = smoothstep(0.070, 0.035, jewel_d)
        v = v * (1.0 - ring) + 0.35 * ring
        v = v * (1.0 - core) + 0.99 * core
    v = clamp(v, 0.50, 1.0)
    return shade_shape(d, (v, v, clamp(v + 0.02), 1.0), outline_w=0.052, shadow_d=sd)


TILES = (
    (tile_classic, tile_compass),
    (tile_chevron, tile_rune),
)


def sample_tile(fn, local_px, local_py):
    """2x2 supersampled pixel evaluation for crisp anti-aliased edges."""
    acc_r = acc_g = acc_b = acc_a = 0.0
    offsets = (-0.25, 0.25)
    for oy in offsets:
        for ox in offsets:
            u = (local_px + 0.5 + ox) / TILE
            v = (local_py + 0.5 + oy) / TILE
            # Map u, v in [0, 1] -> x in [-1, 1], y in [-1, 1] with +y UP
            x = (u - 0.5) * 2.0
            y = (0.5 - v) * 2.0
            r, g, b, a = fn(x, y)
            acc_r += r * a
            acc_g += g * a
            acc_b += b * a
            acc_a += a
    a = acc_a / 4.0
    if a <= 1e-6:
        return 0, 0, 0, 0
    r = clamp(acc_r / acc_a)
    g = clamp(acc_g / acc_a)
    b = clamp(acc_b / acc_a)
    return round(r * 255), round(g * 255), round(b * 255), round(clamp(a) * 255)


def main():
    pixels = bytearray()
    for py in range(SIZE):
        row = py // TILE
        local_py = py % TILE
        for px in range(SIZE):
            col = px // TILE
            local_px = px % TILE
            r, g, b, a = sample_tile(TILES[row][col], local_px, local_py)
            # BGRA order, top-left origin (descriptor 0x28)
            pixels.extend((b, g, r, a))
    header = pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    TARGET.write_bytes(header + pixels)
    print(f"written {len(header) + len(pixels)} bytes to {TARGET}")


if __name__ == "__main__":
    main()
