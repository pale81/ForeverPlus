#!/usr/bin/env python3
"""Build Media/WorldReactions.tga: camera-lens water runoff, campfire warmth glow and embers (512x512 RGBA).

Layout (top-to-bottom in UV space, v = 0 at top, v = 1 at bottom):
  Row 0 (v = 0.000..0.250, 512x128): Soft domed bottom campfire warmth glow (ADD).
  Row 1 (v = 0.250..0.750, height 256px, camera-lens water runoff, BLEND):
    Col 0 (u = 0.000..0.125, 64x256): Primary vertical water rivulet with slender meniscus head.
    Col 1 (u = 0.125..0.250, 64x256): Fine meandering trickle with glossy wet track.
    Col 2 (u = 0.250..0.375, 64x256): Interrupted rivulet with slender trailing wet beads along its path.
    Col 3 (u = 0.375..0.500, 64x256): Soft translucent water runnel streak for layered lens depth.
    Cols 4..7 (u = 0.500..1.000, 256x256): Smooth receding water film / meniscus sheet for lens runoff.
  Row 2 (v = 0.750..1.000, 4 tiles of 128x128, campfire embers, ADD):
    0 (u = 0.00..0.25): Bright rising ember spark with short tapered tail.
    1 (u = 0.25..0.50): Soft warm glowing ash flake.
    2 (u = 0.50..0.75): Paired twin embers for depth variation.
    3 (u = 0.75..1.00): Soft radial spark halo.
"""
from math import cos, exp, hypot, pi, sin
from pathlib import Path
from struct import pack

SIZE = 512
TARGET = Path(__file__).resolve().parent.parent / "Media/WorldReactions.tga"


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    if edge0 == edge1:
        return 0.0 if x < edge0 else 1.0
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


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


def _shade_rivulet(
    x,
    v,
    cx,
    hw,
    tip_v,
    head_len,
    trail_strength=1.0,
    soft_edge=False,
    extra_pinch=None,
    track_swells=None,
):
    """Shade a vertical camera-lens water rivulet with smooth rounded head, caustic belly and wet track.

    x in [-1, 1] left-to-right across the 64x256 tile; v in [0, 1] top-to-bottom.
    Uses asymmetric specular + dark contact refraction instead of a circular bubble rim.
    """
    cap_len = 0.056
    if v < 0.02 or v > tip_v + cap_len + 0.028:
        return 0.0, 0.0, 0.0, 0.0

    top_fade = smoothstep(0.02, 0.22, v)

    # Smooth continuous profile: visible wet track swelling gently into a gravity-pulled head.
    head_t = smoothstep(tip_v - head_len, tip_v - 0.005, v)
    swell = 0.0
    if track_swells:
        for sv, slen, sboost in track_swells:
            swell = max(swell, exp(-(((v - sv) / slen) ** 2)) * sboost)

    raw_hw = hw * (0.40 + 0.60 * (head_t ** 1.15) + swell)

    below_tip = v - tip_v
    if below_tip > 0.0:
        cap_t = clamp(below_tip / cap_len)
        cap_scale = (max(0.0, 1.0 - cap_t * cap_t)) ** 0.5
    else:
        cap_scale = 1.0

    local_hw = raw_hw * cap_scale
    dx = x - cx

    # Smooth refractive drop-shadow hugging the bottom meniscus curve just outside the nose.
    meniscus_shadow = 0.0
    if below_tip > -0.025 and below_tip < cap_len + 0.024:
        ny = max(0.0, (v - (tip_v - 0.008)) / (cap_len + 0.008))
        nx = dx / max(raw_hw, 0.05)
        nose_r = hypot(nx, ny)
        meniscus_shadow = (
            exp(-(((nose_r - 1.04) / 0.16) ** 2))
            * smoothstep(0.18, 0.85, ny)
            * (0.30 if not soft_edge else 0.16)
        )

    if local_hw < 0.004:
        if meniscus_shadow > 0.003:
            return 0.16, 0.28, 0.40, meniscus_shadow
        return 0.0, 0.0, 0.0, 0.0

    s = dx / local_hw
    ad = abs(s)

    edge_in = 0.46 if soft_edge else 0.66
    edge_out = 1.16 if soft_edge else 1.06
    body_mask = 1.0 - smoothstep(edge_in, edge_out, ad)
    if body_mask <= 0.0005:
        if meniscus_shadow > 0.003:
            return 0.16, 0.28, 0.40, meniscus_shadow
        return 0.0, 0.0, 0.0, 0.0

    # Smoothly blend trail pinching into 1.0 well before the head so there is never a seam.
    pinch = 1.0
    if extra_pinch is not None:
        pinch_mask = 1.0 - smoothstep(tip_v - head_len * 1.35, tip_v - head_len * 0.45, v)
        pinch = 1.0 - pinch_mask * (1.0 - extra_pinch(v))

    swell_boost = clamp(head_t + swell * 1.15)

    # Clear, wet liquid body: translucent wet track, fuller refractive body in the leading head.
    trail_env = (0.38 + 0.62 * swell_boost) * top_fade * pinch
    base_body = body_mask * (0.11 + 0.11 * swell_boost) * trail_env * trail_strength

    # Directional glossy sky-light streak along the left flank of the water stream.
    shimmer = 0.78 + 0.22 * sin(v * 20.0 + cx * 8.0) * cos(v * 8.5)
    spec_line = (
        exp(-(((s + 0.38) / (0.38 if soft_edge else 0.27)) ** 2))
        * body_mask
        * (0.36 + 0.42 * swell_boost)
        * top_fade
        * pinch
        * shimmer
    )

    # Bright refractive caustic focused in the lower belly of the leading water head.
    caustic_y = (v - (tip_v - 0.012)) / max(head_len * 0.36, 0.034)
    caustic = (
        exp(-(((s + 0.04) / 0.52) ** 2 + (caustic_y ** 2)))
        * body_mask
        * (0.62 if not soft_edge else 0.36)
        * smoothstep(cap_len, 0.004, below_tip)
    )

    # Crisp slim catchlight along upper-left shoulder of the leading head.
    glint_y = (v - (tip_v - head_len * 0.44)) / max(head_len * 0.26, 0.028)
    catchlight = (
        exp(-(((s + 0.36) / 0.23) ** 2 + (glint_y ** 2)))
        * body_mask
        * (0.50 if not soft_edge else 0.24)
    )

    # Subtle dark refractive shadow along the right flank and lower nose curve (reads on bright skies/snow).
    right_refract = (
        exp(-(((s - 0.64) / 0.28) ** 2))
        * body_mask
        * (0.22 + 0.24 * swell_boost)
        * top_fade
        * pinch
    )

    light_alpha = spec_line * 0.68 + caustic * 0.74 + catchlight * 0.66
    dark_alpha = right_refract * 0.72 + meniscus_shadow
    total_alpha = clamp(base_body + light_alpha + dark_alpha)
    if total_alpha <= 0.001:
        return 0.0, 0.0, 0.0, 0.0

    light_w = base_body * 0.72 + light_alpha
    dark_w = dark_alpha * 1.15
    mix = clamp(light_w / max(light_w + dark_w, 1e-5))

    r = 0.19 + 0.77 * mix
    g = 0.33 + 0.65 * mix
    b = 0.45 + 0.55 * mix
    return clamp(r), clamp(g), clamp(b), total_alpha


def rivulet_stream(u, v):
    """Primary smooth running water stream with slender gravity-pulled meniscus head."""
    x = (u - 0.5) * 2.0
    cx = 0.12 * sin(v * 2.2 * pi + 0.4) + 0.05 * sin(v * 5.1 * pi + 1.1)
    ripple = 1.0 + 0.07 * sin(v * 11.0 * pi)
    return _shade_rivulet(x, v, cx, hw=0.43 * ripple, tip_v=0.90, head_len=0.24, trail_strength=1.0)


def rivulet_slender(u, v):
    """Extra-slender meandering water trickle running cleanly down the lens."""
    x = (u - 0.5) * 2.0
    cx = -0.15 * sin(v * 1.8 * pi + 0.8) + 0.06 * cos(v * 4.4 * pi + 0.3)
    ripple = 1.0 + 0.08 * cos(v * 14.0 * pi + 0.7)
    return _shade_rivulet(x, v, cx, hw=0.33 * ripple, tip_v=0.91, head_len=0.19, trail_strength=0.95)


def rivulet_beaded(u, v):
    """Running rivulet whose upper wet track pinches smoothly into slender trailing micro-runs."""
    x = (u - 0.5) * 2.0
    cx = 0.10 * sin(v * 2.7 * pi + 1.5) - 0.05 * sin(v * 5.6 * pi + 0.4)

    def pinch(tv):
        wave = 0.5 + 0.5 * sin(tv * 6.0 * pi + 0.5)
        return 0.24 + 0.76 * (wave ** 1.45)

    swells = [
        (0.40, 0.075, 0.24),
        (0.64, 0.060, 0.20),
    ]
    return _shade_rivulet(
        x,
        v,
        cx,
        hw=0.38,
        tip_v=0.90,
        head_len=0.22,
        trail_strength=0.96,
        extra_pinch=pinch,
        track_swells=swells,
    )


def rivulet_wash(u, v):
    """Softer, slightly broader translucent wet streak for layered lens depth."""
    x = (u - 0.5) * 2.0
    cx = -0.09 * sin(v * 1.5 * pi + 2.1) + 0.04 * sin(v * 3.7 * pi)
    ripple = 1.0 + 0.07 * sin(v * 9.0 * pi + 1.1)
    return _shade_rivulet(
        x, v, cx, hw=0.50 * ripple, tip_v=0.89, head_len=0.30, trail_strength=0.68, soft_edge=True
    )


def water_sheet(u, v):
    """Smooth receding translucent water film / meniscus curtain sliding down the camera lens."""
    # Gentle broad liquid lobes across the lens width (subtle curve, not a jagged wave).
    wave = (
        0.78
        + 0.055 * sin(u * 2.0 * pi * 1.5 + 0.35)
        + 0.036 * cos(u * 2.0 * pi * 3.0 + 1.25)
        + 0.018 * sin(u * 2.0 * pi * 4.5 + 2.10)
    )

    # Clearer through the center of vision, gently fuller toward the outer lens edges.
    dx = abs(u - 0.5) * 2.0
    side_boost = 0.32 + 0.68 * (dx ** 1.35)
    edge_soft = smoothstep(1.0, 0.93, dx)

    dist = v - wave

    # Broad, organic watery flow curtains.
    warp = u + 0.035 * sin(v * 3.5 * pi + u * 5.0)
    flow = (
        0.54
        + 0.23 * sin(warp * 2.0 * pi * 3.5 + 0.4)
        + 0.14 * cos(warp * 2.0 * pi * 6.5 + 1.8)
        + 0.09 * sin(warp * 2.0 * pi * 10.5 + 0.9)
    )

    # Soft translucent wet veil above the curving waterline, fading cleanly to 0 at top.
    top_fade = smoothstep(0.03, 0.58, v)
    below_fade = 1.0 - smoothstep(-0.075, 0.055, dist)
    sheet_body = (
        top_fade
        * below_fade
        * (0.11 + 0.16 * smoothstep(0.28, 0.80, v))
        * flow
        * side_boost
    )

    # Soft diffuse sheen along the receding meniscus edge (broad and watery, never a crisp white wire).
    meniscus_glint = (
        exp(-(((dist + 0.030) / 0.068) ** 2))
        * (0.14 + 0.12 * flow)
        * (0.38 + 0.62 * dx)
    )

    # Gentle dark refractive shadow right beneath the receding water edge.
    meniscus_dark = (
        exp(-(((dist - 0.028) / 0.062) ** 2))
        * 0.14
        * (0.38 + 0.62 * dx)
    )

    light_a = (sheet_body + meniscus_glint) * edge_soft
    dark_a = meniscus_dark * edge_soft
    alpha = clamp(light_a + dark_a)
    if alpha <= 0.001:
        return 0.0, 0.0, 0.0, 0.0

    mix = clamp(light_a / max(light_a + dark_a * 1.2, 1e-5))
    r = 0.24 + 0.70 * mix
    g = 0.38 + 0.59 * mix
    b = 0.50 + 0.50 * mix
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
        tv = ((py - 128) + 0.5) / 256.0
        if px < 256:
            col = px // 64
            tu = ((px % 64) + 0.5) / 64.0
            if col == 0:
                return rivulet_stream(tu, tv)
            if col == 1:
                return rivulet_slender(tu, tv)
            if col == 2:
                return rivulet_beaded(tu, tv)
            return rivulet_wash(tu, tv)
        tu = ((px - 256) + 0.5) / 256.0
        return water_sheet(tu, tv)

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
