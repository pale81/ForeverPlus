#!/usr/bin/env python3
"""Build Media/WorldReactions.tga: camera-lens water droplets, wet trails, meniscus runoff, campfire glow & embers (512x512 RGBA).

Layout (top-to-bottom in UV space, v = 0 at top, v = 1 at bottom):
  Row 0 (py = 0..127, v = 0.000..0.250, 512x128):
    Soft domed bottom campfire warmth glow (ADD).
  Row 1 (py = 128..383, v = 0.250..0.750, 512x256, camera-lens water runoff, BLEND):
    Top-left (py = 128..255):
      px =   0.. 63 (64x128): Heavy running lens droplet head (rounded gravity belly + soft concave neck into wet trail).
      px =  64..127 (64x128): Slender fast-running lens droplet head (slightly asymmetric).
      px = 128..191, py = 128..191 (64x64): Large clinging round-oval lens bead.
      px = 192..255, py = 128..191 (64x64): Gravity-slumped oval clinging bead.
      px = 128..191, py = 192..255 (64x64): Compact crisp small lens bead.
      px = 192..255, py = 192..255 (64x64): Paired micro-beads (primary + tiny satellite droplet).
    Bottom-left (py = 256..383, 4 tiles of 64x128):
      Stationary wet lens trails with hairline refractive edges and tiny oval residual micro-beads.
      Each tile's centerline cx(v) matches TRAIL_CURVES in Modules/WorldReactions.lua so the
      running droplet head tracks its revealed wet trail pixel-accurately without sliding seams.
    Right (px = 256..511, py = 128..383, 256x256):
      Soft organic receding water meniscus film gliding down the camera lens on surfacing.
  Row 2 (py = 384..511, v = 0.750..1.000, 4 tiles of 128x128, campfire embers, ADD):
    0 (u = 0.00..0.25): Bright rising ember spark with short tapered tail.
    1 (u = 0.25..0.50): Soft warm glowing ash flake.
    2 (u = 0.50..0.75): Paired twin embers for depth variation.
    3 (u = 0.75..1.00): Soft radial spark halo.
"""
from math import cos, exp, hypot, pi, sin, sqrt
from pathlib import Path
from struct import pack

SIZE = 512
TARGET = Path(__file__).resolve().parent.parent / "Media/WorldReactions.tga"

# Centerline curve definitions for the 4 wet-trail tiles (x in [-1, 1] across the 64px tile).
# Must stay in sync with TRAIL_CURVES in Modules/WorldReactions.lua.
TRAIL_CURVES = (
    # (a1, f1, p1, a2, f2, p2)
    (0.24, 1.35 * pi, 0.30, 0.09, 3.10 * pi, 1.20),
    (-0.26, 1.15 * pi, 0.75, 0.08, 2.85 * pi, 2.40),
    (0.22, 1.65 * pi, 1.60, -0.09, 3.40 * pi, 0.50),
    (-0.23, 1.25 * pi, 2.15, 0.08, 2.60 * pi, 0.90),
)


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def trail_center_x(variant, v):
    a1, f1, p1, a2, f2, p2 = TRAIL_CURVES[variant]
    env = smoothstep(0.0, 0.14, v)
    return env * (a1 * sin(v * f1 + p1) + a2 * sin(v * f2 + p2))


def campfire_glow(u, v):
    """Wide, organic bottom-edge warmth dome without banding or hard top edge."""
    dx = (u - 0.5) * 2.0
    horiz = smoothstep(1.0, 0.14, abs(dx)) ** 1.35
    ripple = 1.0 + 0.07 * sin(u * 5.0 * pi) * sin(v * 3.0 * pi) + 0.04 * cos(u * 9.0 * pi + 0.6)
    height = smoothstep(0.03, 0.96, v) ** 1.65
    arch = exp(-((dx * 0.85) ** 2) * 0.75)
    core = smoothstep(0.45, 1.0, v) * exp(-((dx * 0.7) ** 2) * 1.1)
    alpha = clamp((height * (0.55 + 0.45 * arch) * horiz) * ripple * 0.92)
    r = 1.0
    g = clamp(0.84 + 0.16 * core)
    b = clamp(0.68 + 0.28 * core)
    return r, g, b, alpha


def _shade_lens_droplet_sdf(x, y, sdf_fn, scale_hint=1.0, outline_scale=1.0, tail_blend=0.0):
    """Photorealistic glass-lens water droplet shader driven by a 2D normalized radius field.

    Avoids harsh cartoon outlines by using soft directional refraction, a crystal-clear center,
    focused lower caustic crescent, subtle downward contact shadow and crisp specular catchlight.
    """
    r = sdf_fn(x, y)
    if r > 1.52:
        return 0.0, 0.0, 0.0, 0.0

    eps = 0.012
    rx = (sdf_fn(x + eps, y) - sdf_fn(x - eps, y)) / (2.0 * eps)
    ry = (sdf_fn(x, y + eps) - sdf_fn(x, y - eps)) / (2.0 * eps)
    glen = hypot(rx, ry)
    if glen > 1e-6:
        gx, gy = rx / glen, ry / glen
    else:
        gx, gy = 0.0, 0.0

    # Soft directional contact shadow outside the lower-right meniscus (no uniform dark ring).
    out_dist = r - 1.0
    if out_dist >= 0.0:
        lower_bias = smoothstep(-0.08, 0.90, gy + 0.28 * gx)
        shadow = exp(-((out_dist / 0.22) ** 2)) * (0.06 + 0.36 * lower_bias) * outline_scale * (1.0 - 0.85 * tail_blend)
        outer_caustic = (
            exp(-(((out_dist - 0.11) / 0.10) ** 2))
            * smoothstep(0.46, 0.95, gy)
            * 0.12
            * (1.0 - 0.9 * tail_blend)
        )
        alpha = clamp(shadow + outer_caustic)
        if alpha <= 0.002:
            return 0.0, 0.0, 0.0, 0.0
        mix_l = clamp(outer_caustic / max(shadow + outer_caustic, 1e-5))
        return 0.07 + 0.82 * mix_l, 0.14 + 0.80 * mix_l, 0.22 + 0.75 * mix_l, alpha

    # Inside droplet (r < 1): soft feathered meniscus edge.
    edge_aa = 1.0 - smoothstep(0.86, 1.0, r)
    dome_r = clamp(r, 0.0, 0.999)
    slope = (dome_r / sqrt(max(1.0 - dome_r * dome_r, 0.07))) * 0.90
    nx = gx * slope
    ny = gy * slope
    nz = 1.0
    nlen = sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / nlen, ny / nlen, nz / nlen

    fresnel = (1.0 - nz) ** 1.40

    # Soft directional internal refraction: top inner curve refracts darker ground; sides stay glassy.
    upper_dark = (
        smoothstep(0.20, -0.80, ny)
        * (0.11 + 0.42 * fresnel)
        * outline_scale
        * (1.0 - 0.78 * tail_blend)
    )

    # Subtle bottom-arc refraction border (strong only along the bottom lip, fades out on flanks/neck).
    bottom_arc = smoothstep(0.02, 0.88, gy + 0.20 * gx)
    rim_dark = (
        exp(-(((r - 0.92) / 0.08) ** 2))
        * (0.09 + 0.28 * bottom_arc)
        * outline_scale
        * (1.0 - 0.85 * tail_blend)
    )

    # Crystal-clear glassy body (very low alpha so the world shows sharply through the drop).
    glass_body = (0.030 + 0.055 * fresnel) * edge_aa * (1.0 - 0.35 * tail_blend)

    # Bright focused lower-belly caustic crescent (convex water lens focusing skylight downward).
    caustic_arc = smoothstep(0.14, 0.86, ny) * exp(-(((r - 0.72) / 0.21) ** 2))
    caustic_core = smoothstep(0.40, 0.94, ny) * exp(-(((r - 0.78) / 0.11) ** 2))
    caustic = (caustic_arc * 0.52 + caustic_core * 0.48) * edge_aa * (1.0 - 0.82 * tail_blend)

    # Crisp specular catchlight on upper-left shoulder of the dome.
    lx, ly, lz = -0.42, -0.56, 0.714
    hx, hy, hz = lx, ly, lz + 1.0
    hlen = sqrt(hx * hx + hy * hy + hz * hz)
    hx, hy, hz = hx / hlen, hy / hlen, hz / hlen
    ndoth = max(0.0, nx * hx + ny * hy + nz * hz)
    spec_sharp = (ndoth ** (62.0 * scale_hint)) * 1.00 * (1.0 - 0.75 * tail_blend)
    spec_soft = (ndoth ** 16.0) * 0.20 * (1.0 - 0.65 * tail_blend)

    # Tiny secondary internal reflection along lower-right curve.
    hx2, hy2, hz2 = 0.30, 0.62, 0.725
    ndoth2 = max(0.0, nx * hx2 + ny * hy2 + nz * hz2)
    rim_glint = (ndoth2 ** 36.0) * 0.42 * smoothstep(0.50, 0.90, r) * (1.0 - 0.85 * tail_blend)

    # Soft bright skylight sheen along the left wet flank (also gently visible along the upper neck).
    left_rim = exp(-(((r - 0.82) / 0.11) ** 2)) * smoothstep(0.20, -0.75, gx + 0.20 * gy) * (0.28 - 0.10 * tail_blend)

    light_a = (caustic + spec_sharp + spec_soft + rim_glint + left_rim) * edge_aa
    dark_a = (upper_dark + rim_dark) * edge_aa

    total_a = clamp(glass_body + light_a + dark_a)
    if total_a <= 0.002:
        return 0.0, 0.0, 0.0, 0.0

    light_w = light_a * 1.20 + glass_body * 0.65
    dark_w = dark_a * 1.25
    mix = clamp(light_w / max(light_w + dark_w, 1e-5))
    pure_white = clamp(spec_sharp * 1.1 + caustic_core * 0.42)

    r_col = 0.10 + 0.76 * mix + 0.14 * pure_white
    g_col = 0.18 + 0.73 * mix + 0.09 * pure_white
    b_col = 0.27 + 0.68 * mix + 0.05 * pure_white
    return clamp(r_col), clamp(g_col), clamp(b_col), total_a


def _running_head_sdf(x, y, asym=0.0, slim=1.0):
    """Organic gravity-pulled running water droplet on glass (x in [-1,1], y in [-1,1]).

    Uses a smooth bulb/pear profile (rounded gravity-heavy lower dome + concave pinched wet neck
    trailing smoothly upward into the stationary wet track), never a geometric cone/icicle.
    """
    # Center of the rounded water bulb sits in the lower half of the 64x128 tile.
    cy = 0.42
    cx = asym * sin((y + 0.25) * 2.4)
    dx = (x - cx) / slim

    # Primary rounded dome (bulb) centered at (cx, cy) with organic slight vertical stretch.
    bulb_rx = 0.56
    bulb_ry = 0.44
    dy = y - cy
    # Below center: full rounded gravity belly.
    if dy >= 0.0:
        return hypot(dx / bulb_rx, dy / (bulb_ry * 0.96))

    # Above center: smooth dome up to the upper shoulder, then a concave pinch into a thin wet neck.
    bulb_r = hypot(dx / bulb_rx, dy / (bulb_ry * 1.18))
    # Concave neck profile above the bulb (from y = cy - 0.10 upward to y = -0.88).
    neck_t = clamp((-dy) / 1.28, 0.0, 1.0)
    # Smooth concave bell-curve narrowing from 0.46 down to 0.13 (matches wet trail width!).
    neck_hw = 0.13 + 0.34 * ((1.0 - neck_t) ** 2.6)
    neck_r = abs(dx) / max(neck_hw, 0.08)
    # Cap neck gently near top of tile.
    if y < -0.82:
        cap = (-0.82 - y) / 0.14
        neck_r = hypot(neck_r, cap)
    # Smooth minimum (smin) blends the round upper droplet dome organically into the concave wet neck!
    k = 0.28
    h = clamp(0.5 + 0.5 * (neck_r - bulb_r) / k, 0.0, 1.0)
    return neck_r * (1.0 - h) + bulb_r * h - k * h * (1.0 - h)


def droplet_head_heavy(u, v):
    """Heavy running camera-lens droplet head (64x128)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    # Upper concave neck softens smoothly into the delicate wet trail.
    tail_blend = smoothstep(0.18, -0.35, y)
    r, g, b, a = _shade_lens_droplet_sdf(
        x,
        y,
        lambda px, py: _running_head_sdf(px, py, asym=0.04, slim=1.04),
        scale_hint=0.95,
        outline_scale=0.95,
        tail_blend=tail_blend,
    )
    neck_fade = smoothstep(0.06, 0.36, v)
    return r, g, b, a * neck_fade


def droplet_head_slender(u, v):
    """Slender, slightly faster running camera-lens droplet head (64x128)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    tail_blend = smoothstep(0.20, -0.32, y)
    r, g, b, a = _shade_lens_droplet_sdf(
        x,
        y,
        lambda px, py: _running_head_sdf(px, py, asym=-0.05, slim=0.84),
        scale_hint=1.0,
        outline_scale=0.90,
        tail_blend=tail_blend,
    )
    neck_fade = smoothstep(0.06, 0.36, v)
    return r, g, b, a * neck_fade


def bead_round(u, v):
    """Large clear clinging lens bead with subtle gravity sag (64x64)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0

    def sdf(px, py):
        sag = 1.0 + 0.11 * smoothstep(-0.5, 0.6, py)
        wobble = 1.0 + 0.035 * sin(px * 3.2 + 0.5) * cos(py * 2.7)
        return hypot(px / (0.68 * sag * wobble), (py - 0.04) / (0.72 * wobble))

    return _shade_lens_droplet_sdf(x, y, sdf, scale_hint=0.92, outline_scale=0.88)


def bead_oval(u, v):
    """Slightly elongated clinging droplet on the verge of sliding (64x64)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0

    def sdf(px, py):
        cx = 0.05 * py
        sag = 1.0 + 0.17 * smoothstep(-0.6, 0.6, py)
        return hypot((px - cx) / (0.55 * sag), (py - 0.03) / 0.78)

    return _shade_lens_droplet_sdf(x, y, sdf, scale_hint=0.96, outline_scale=0.88)


def bead_compact(u, v):
    """Crisp smaller lens water bead (64x64)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0

    def sdf(px, py):
        sag = 1.0 + 0.08 * smoothstep(-0.4, 0.5, py)
        return hypot(px / (0.58 * sag), py / 0.62)

    return _shade_lens_droplet_sdf(x, y, sdf, scale_hint=0.82, outline_scale=0.82)


def bead_pair(u, v):
    """Natural pair: medium clinging droplet + tiny satellite micro-bead (64x64)."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0

    def sdf1(px, py):
        dx = px + 0.14
        dy = py - 0.10
        sag = 1.0 + 0.10 * smoothstep(-0.4, 0.5, dy)
        return hypot(dx / (0.50 * sag), dy / 0.54)

    def sdf2(px, py):
        dx = px - 0.42
        dy = py + 0.34
        return hypot(dx / 0.25, dy / 0.27)

    r1, g1, b1, a1 = _shade_lens_droplet_sdf(x, y, sdf1, scale_hint=0.88, outline_scale=0.85)
    r2, g2, b2, a2 = _shade_lens_droplet_sdf(x, y, sdf2, scale_hint=0.76, outline_scale=0.72)
    a = clamp(a1 + a2 * (1.0 - a1))
    if a <= 0.002:
        return 0.0, 0.0, 0.0, 0.0
    w1 = a1
    w2 = a2 * (1.0 - a1)
    return (r1 * w1 + r2 * w2) / a, (g1 * w1 + g2 * w2) / a, (b1 * w1 + b2 * w2) / a, a


def wet_trail(variant, u, v):
    """Stationary translucent wet lens track with hairline refractive edges and tiny oval micro-beads (64x128)."""
    x = (u - 0.5) * 2.0
    cx = trail_center_x(variant, v)
    dx = x - cx

    top_fade = smoothstep(0.015, 0.14, v)
    if top_fade <= 0.001:
        return 0.0, 0.0, 0.0, 0.0

    pinch_phase = variant * 1.7 + 0.4
    pinch = 0.78 + 0.22 * sin(v * 7.5 * pi + pinch_phase)
    half_w = (0.165 + 0.022 * (variant % 2)) * pinch

    s = dx / max(half_w, 0.04)
    ad = abs(s)
    trail_r = trail_g = trail_b = trail_a = 0.0
    if ad < 1.85:
        body = (1.0 - smoothstep(0.48, 1.05, ad)) * 0.055
        left_sheen = exp(-(((s + 0.70) / 0.34) ** 2)) * 0.30
        right_dark = exp(-(((s - 0.76) / 0.36) ** 2)) * 0.24
        shimmer = 0.70 + 0.30 * sin(v * 18.0 + variant * 2.3)
        la = (body + left_sheen * shimmer) * top_fade
        da = right_dark * top_fade
        trail_a = clamp(la + da)
        if trail_a > 0.002:
            mix = clamp(la / max(la + da * 1.20, 1e-5))
            trail_r = 0.09 + 0.82 * mix
            trail_g = 0.18 + 0.77 * mix
            trail_b = 0.27 + 0.71 * mix

    # Tiny slightly elongated oval micro-beads left along the wet track.
    bead_specs = (
        ((0.20, 0.19, 0.052), (0.50, 0.23, 0.062), (0.78, 0.17, 0.048)),
        ((0.17, 0.18, 0.050), (0.44, 0.21, 0.058), (0.69, 0.19, 0.052), (0.89, 0.16, 0.044)),
        ((0.25, 0.22, 0.060), (0.57, 0.18, 0.050), (0.83, 0.21, 0.058)),
        ((0.19, 0.20, 0.054), (0.48, 0.17, 0.048), (0.75, 0.23, 0.062)),
    )[variant]

    br = bg = bb = ba = 0.0
    for bv, bw, bh in bead_specs:
        if abs(v - bv) < bh * 1.6:
            bcx = trail_center_x(variant, bv)

            def micro_sdf(px, py, _bcx=bcx, _bv=bv, _bw=bw, _bh=bh):
                dy = py - _bv
                sag = 1.0 + 0.12 * smoothstep(-_bh, _bh, dy)
                return hypot((px - _bcx) / (_bw * sag), dy / _bh)

            r_m, g_m, b_m, a_m = _shade_lens_droplet_sdf(x, v, micro_sdf, scale_hint=0.70, outline_scale=0.70)
            a_m *= 0.90 * top_fade
            if a_m > ba:
                br, bg, bb, ba = r_m, g_m, b_m, a_m

    out_a = clamp(ba + trail_a * (1.0 - ba))
    if out_a <= 0.002:
        return 0.0, 0.0, 0.0, 0.0
    w_b = ba
    w_t = trail_a * (1.0 - ba)
    return (
        (br * w_b + trail_r * w_t) / out_a,
        (bg * w_b + trail_g * w_t) / out_a,
        (bb * w_b + trail_b * w_t) / out_a,
        out_a,
    )


def water_meniscus_sheet(u, v):
    """Subtle, broad, glass-clear receding water meniscus film gliding down the lens on surfacing (256x256).

    Gentle shallow arch across the lens with broken, organic specular shimmer along the breaking waterline
    and an almost crystal-clear thin water film below (never a harsh wire line or opaque fog).
    """
    dx = abs(u - 0.5) * 2.0
    # Gentle shallow convex arch (edges slightly lower as water drains faster along lens curvature).
    wave = (
        0.34
        + 0.065 * (dx ** 1.6)
        + 0.022 * sin(u * 2.0 * pi * 1.5 + 0.55)
        + 0.014 * cos(u * 2.0 * pi * 3.0 + 1.40)
        + 0.008 * sin(u * 2.0 * pi * 5.0 + 2.10)
    )
    edge_soft = smoothstep(1.0, 0.92, dx)
    # Very gentle in center vision, slightly more legible toward outer lens thirds.
    vision_weight = 0.34 + 0.66 * (dx ** 1.15)

    # Signed distance relative to waterline: negative = above (emerged), positive = below (receding water sheet).
    dist = v - wave

    # Crystal-clear thin glassy water film below the receding edge, smoothly tapering off toward bottom.
    below_mask = smoothstep(-0.015, 0.035, dist) * (1.0 - smoothstep(0.14, 0.58, dist))
    flow_ripples = (
        0.66
        + 0.20 * sin(u * 16.0 + v * 7.5 + 0.5)
        + 0.14 * cos(u * 27.0 - v * 11.0)
    )
    film_a = below_mask * 0.13 * flow_ripples * vision_weight

    # Broken organic refractive shimmer along the waterline (NOT a solid uniform wire).
    glint_patches = (
        0.35
        + 0.40 * (0.5 + 0.5 * sin(u * 2.0 * pi * 3.5 + 0.8))
        + 0.25 * (0.5 + 0.5 * cos(u * 2.0 * pi * 6.5 - 0.3))
    )
    # Soft watery sheen band just below the meniscus lip.
    lip_sheen = exp(-(((dist - 0.018) / 0.034) ** 2)) * (0.14 + 0.14 * glint_patches) * vision_weight
    # Delicate thin caustic highlight broken into shimmering pockets right at the crest.
    lip_glint = (
        exp(-(((dist - 0.006) / 0.012) ** 2))
        * (0.10 + 0.26 * (glint_patches ** 1.8))
        * (0.42 + 0.58 * dx)
    )
    # Soft faint refractive shadow just along the breaking edge for contrast against bright skies.
    lip_dark = exp(-(((dist + 0.010) / 0.022) ** 2)) * (0.10 + 0.12 * glint_patches) * vision_weight

    # Subtle short vertical wet sheen streaks trailing just above the receding line.
    above_mask = smoothstep(0.012, -0.020, dist) * (1.0 - smoothstep(-0.02, -0.24, dist))
    streak_pat = (0.5 + 0.5 * sin(u * 2.0 * pi * 5.0 + 0.9)) * (0.5 + 0.5 * cos(u * 2.0 * pi * 9.0 - 0.5))
    above_a = above_mask * (streak_pat ** 2.0) * 0.08 * vision_weight

    light_a = (film_a + lip_sheen + lip_glint + above_a) * edge_soft
    dark_a = lip_dark * edge_soft
    alpha = clamp(light_a + dark_a)
    if alpha <= 0.002:
        return 0.0, 0.0, 0.0, 0.0

    mix = clamp(light_a / max(light_a + dark_a * 1.30, 1e-5))
    spark_w = clamp(lip_glint * 1.1)
    r = 0.12 + 0.76 * mix + 0.12 * spark_w
    g = 0.22 + 0.71 * mix + 0.07 * spark_w
    b = 0.32 + 0.64 * mix + 0.04 * spark_w
    return clamp(r), clamp(g), clamp(b), alpha


def ember_spark(u, v):
    """Rising campfire ember with hot core and delicate trailing glow."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    head = exp(-(((x / 0.18) ** 2) + (((y + 0.22) / 0.20) ** 2)))
    halo = exp(-(((x / 0.46) ** 2) + (((y + 0.12) / 0.48) ** 2))) * 0.48
    tail = 0.0
    if -0.25 < y < 0.82:
        t = (y + 0.25) / 1.07
        w = 0.15 * (1.0 - 0.65 * t)
        tail = exp(-((x / max(w, 0.03)) ** 2)) * (1.0 - smoothstep(0.05, 0.95, t)) * 0.55
    alpha = clamp(head + halo + tail)
    r = 1.0
    g = clamp(0.55 + 0.45 * head)
    b = clamp(0.18 + 0.68 * (head ** 1.5))
    return r, g, b, alpha


def ember_flake(u, v):
    """Softer, slightly tilted glowing ash flake."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    ca, sa = cos(0.52), sin(0.52)
    rx = x * ca + y * sa
    ry = -x * sa + y * ca
    core = exp(-(((rx / 0.28) ** 2) + ((ry / 0.16) ** 2)))
    halo = exp(-((hypot(x, y) / 0.52) ** 2)) * 0.46
    alpha = clamp(core + halo)
    return 1.0, clamp(0.58 + 0.40 * core), clamp(0.20 + 0.58 * (core ** 1.4)), alpha


def ember_twin(u, v):
    """Two small staggered sparks for depth."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    s1 = exp(-((((x + 0.22) / 0.17) ** 2) + (((y + 0.18) / 0.20) ** 2)))
    s2 = exp(-((((x - 0.24) / 0.13) ** 2) + (((y - 0.24) / 0.15) ** 2))) * 0.82
    h1 = exp(-((((x + 0.22) / 0.40) ** 2) + (((y + 0.18) / 0.40) ** 2))) * 0.36
    h2 = exp(-((((x - 0.24) / 0.34) ** 2) + (((y - 0.24) / 0.34) ** 2))) * 0.30
    core = max(s1, s2)
    alpha = clamp(s1 + s2 + h1 + h2)
    return 1.0, clamp(0.54 + 0.44 * core), clamp(0.16 + 0.62 * (core ** 1.5)), alpha


def ember_halo(u, v):
    """Soft radial warm spark dot."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    core = exp(-((r / 0.20) ** 2))
    soft = exp(-((r / 0.56) ** 2)) * 0.55
    alpha = clamp(core + soft)
    return 1.0, clamp(0.62 + 0.36 * core), clamp(0.24 + 0.62 * (core ** 1.6)), alpha


def sample(px, py):
    """Return (r, g, b, a) in 0..1 for pixel (px, py) with py = 0 at top."""
    u = (px + 0.5) / SIZE

    if py < 128:
        return campfire_glow(u, (py + 0.5) / 128.0)

    if py < 384:
        if px >= 256:
            tu = ((px - 256) + 0.5) / 256.0
            tv = ((py - 128) + 0.5) / 256.0
            return water_meniscus_sheet(tu, tv)

        if py < 256:
            if px < 64:
                return droplet_head_heavy((px + 0.5) / 64.0, ((py - 128) + 0.5) / 128.0)
            if px < 128:
                return droplet_head_slender(((px - 64) + 0.5) / 64.0, ((py - 128) + 0.5) / 128.0)
            bx = (px - 128) // 64
            by = (py - 128) // 64
            tu = (((px - 128) % 64) + 0.5) / 64.0
            tv = (((py - 128) % 64) + 0.5) / 64.0
            if by == 0 and bx == 0:
                return bead_round(tu, tv)
            if by == 0 and bx == 1:
                return bead_oval(tu, tv)
            if by == 1 and bx == 0:
                return bead_compact(tu, tv)
            return bead_pair(tu, tv)

        col = px // 64
        tu = ((px % 64) + 0.5) / 64.0
        tv = ((py - 256) + 0.5) / 128.0
        return wet_trail(col, tu, tv)

    col = px // 128
    tu = ((px % 128) + 0.5) / 128.0
    tv = ((py - 384) + 0.5) / 128.0
    if col == 0:
        return ember_spark(tu, tv)
    if col == 1:
        return ember_flake(tu, tv)
    if col == 2:
        return ember_twin(tu, tv)
    return ember_halo(tu, tv)


def write_tga(path):
    # Uncompressed 32-bit BGRA TGA with top-left origin (descriptor 0x28 = 8-bit alpha + top-left).
    header = pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    data = bytearray(SIZE * SIZE * 4)
    idx = 0
    for py in range(SIZE):
        for px in range(SIZE):
            r, g, b, a = sample(px, py)
            ai = int(round(clamp(a) * 255))
            if ai == 0:
                ri = gi = bi = 0
            else:
                ri = int(round(clamp(r) * 255))
                gi = int(round(clamp(g) * 255))
                bi = int(round(clamp(b) * 255))
            data[idx] = bi
            data[idx + 1] = gi
            data[idx + 2] = ri
            data[idx + 3] = ai
            idx += 4
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + bytes(data))


if __name__ == "__main__":
    write_tga(TARGET)
    print(f"Wrote {TARGET} ({TARGET.stat().st_size} bytes)")
