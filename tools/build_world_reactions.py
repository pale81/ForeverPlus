#!/usr/bin/env python3
"""Build Media/WorldReactions.tga: water droplets, campfire warmth glow and embers (256x256 RGBA).

Layout (top-to-bottom in UV space, v = 0 at top, v = 1 at bottom):
  Row 0 (v = 0.000..0.375, 256x96): Soft domed bottom campfire warmth glow (ADD).
  Row 1 (v = 0.375..0.625, 4 tiles of 64x64, water droplets, BLEND):
    0 (u = 0.00..0.25): Running droplet with fine upper streak and specular rim.
    1 (u = 0.25..0.50): Small round clinging droplet with crisp highlight.
    2 (u = 0.50..0.75): Elongated side droplet with subtle trail.
    3 (u = 0.75..1.00): Soft translucent mist / edge dampness puff.
  Row 2 (v = 0.625..0.875, 4 tiles of 64x64, campfire embers, ADD):
    0 (u = 0.00..0.25): Bright rising ember spark with short tapered tail.
    1 (u = 0.25..0.50): Soft warm glowing ash flake.
    2 (u = 0.50..0.75): Paired twin embers for depth variation.
    3 (u = 0.75..1.00): Soft radial spark halo.
  Row 3 (v = 0.875..1.000, 256x32): Reserved transparent padding.
"""
from math import cos, exp, hypot, pi, sin
from pathlib import Path
from struct import pack

SIZE = 256
TARGET = Path(__file__).resolve().parent.parent / "Media/WorldReactions.tga"


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(edge0, edge1, x):
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def campfire_glow(u, v):
    """Wide, organic bottom-edge warmth dome without banding or hard top edge."""
    # u in [0, 1] left-to-right, v in [0, 1] top-to-bottom (bottom of screen is v = 1).
    dx = (u - 0.5) * 2.0  # -1..1
    # Horizontal dome falloff: broad center, fades smoothly to 0 before left/right edges.
    horiz = smoothstep(1.0, 0.14, abs(dx)) ** 1.35
    # Gentle organic undulation so it looks like flickering firelight, not a flat bar.
    ripple = 1.0 + 0.07 * sin(u * 5.0 * pi) * sin(v * 3.0 * pi) + 0.04 * cos(u * 9.0 * pi + 0.6)
    # Vertical rise from bottom (v = 1) fading smoothly to 0 by top (v = 0).
    height = smoothstep(0.03, 0.96, v) ** 1.65
    # Slight arch: higher in center, lower near corners.
    arch = exp(-((dx * 0.85) ** 2) * 0.75)
    core = smoothstep(0.45, 1.0, v) * exp(-((dx * 0.7) ** 2) * 1.1)
    alpha = clamp((height * (0.55 + 0.45 * arch) * horiz) * ripple * 0.92)
    # Soft white-warm tint (tinted further via SetVertexColor in Lua).
    r = 1.0
    g = clamp(0.84 + 0.16 * core)
    b = clamp(0.68 + 0.28 * core)
    return r, g, b, alpha


def droplet_running(u, v):
    """Teardrop with fine upper trail, dark refraction rim and bright specular highlight."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0  # -1 top, +1 bottom

    # Main droplet bulb centered near y = 0.34, slightly vertical oval.
    bx = x / 0.34
    by = (y - 0.34) / 0.44
    # Narrow slightly toward the top of the bulb for a natural gravity sag.
    taper = 1.0 - 0.24 * clamp((-by + 0.2) * 0.7)
    r_bulb = hypot(bx / max(taper, 0.35), by)
    bulb_mask = 1.0 - smoothstep(0.82, 1.04, r_bulb)

    # Fine upper wet streak from y = -0.82 down into the bulb at y = 0.20.
    trail_alpha = 0.0
    if -0.86 < y < 0.32:
        t = (y + 0.86) / (0.32 + 0.86)
        w = 0.045 + 0.105 * (t ** 1.4)
        sway = 0.025 * sin(t * 2.0 * pi)
        dx = abs(x - sway) / w
        along = smoothstep(0.0, 0.28, t) * smoothstep(1.0, 0.78, t)
        trail_alpha = exp(-(dx * dx) * 2.1) * along * 0.42

    # Crisp rim and bright lens highlight so it reads on both bright snow and dark caves.
    rim = exp(-((r_bulb - 0.82) / 0.14) ** 2) * bulb_mask * 0.52
    # Upper-left specular glint
    glint1 = exp(-(((x + 0.11) / 0.11) ** 2 + ((y - 0.18) / 0.14) ** 2)) * bulb_mask
    # Lower-right caustic bounce light
    caustic = exp(-(((x - 0.08) / 0.15) ** 2 + ((y - 0.52) / 0.12) ** 2)) * bulb_mask * 0.65
    body = bulb_mask * (0.28 + 0.22 * (1.0 - clamp(r_bulb)))

    alpha = clamp(max(body + rim + glint1 * 0.55 + caustic * 0.32, trail_alpha))
    bright = clamp(0.76 + 0.24 * max(glint1, caustic) - 0.16 * rim * (1.0 - glint1))
    r = clamp(bright * 0.90)
    g = clamp(bright * 0.96)
    b = clamp(bright * 1.00)
    return r, g, b, alpha


def droplet_round(u, v):
    """Small round clinging water bead with clear specular highlight."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x / 0.54, y / 0.58)
    mask = 1.0 - smoothstep(0.80, 1.03, r)
    if mask <= 0.0:
        return 0.0, 0.0, 0.0, 0.0
    rim = exp(-((r - 0.80) / 0.15) ** 2) * mask * 0.48
    glint = exp(-(((x + 0.17) / 0.14) ** 2 + ((y + 0.16) / 0.14) ** 2)) * mask
    caustic = exp(-(((x - 0.14) / 0.18) ** 2 + ((y - 0.19) / 0.14) ** 2)) * mask * 0.62
    alpha = clamp(mask * 0.26 + rim + glint * 0.58 + caustic * 0.32)
    bright = clamp(0.78 + 0.22 * max(glint, caustic) - 0.12 * rim)
    return clamp(bright * 0.90), clamp(bright * 0.97), clamp(bright), alpha


def droplet_streak(u, v):
    """Elongated side droplet sliding along the outer screen edge."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    bx = x / 0.24
    by = (y - 0.22) / 0.62
    taper = 1.0 - 0.30 * clamp((-by + 0.35) * 0.6)
    r = hypot(bx / max(taper, 0.32), by)
    mask = 1.0 - smoothstep(0.78, 1.04, r)
    rim = exp(-((r - 0.78) / 0.16) ** 2) * mask * 0.46
    glint = exp(-(((x + 0.06) / 0.09) ** 2 + ((y - 0.04) / 0.22) ** 2)) * mask * 0.85
    caustic = exp(-(((x - 0.05) / 0.11) ** 2 + ((y - 0.48) / 0.16) ** 2)) * mask * 0.55
    alpha = clamp(mask * 0.24 + rim + glint * 0.52 + caustic * 0.28)
    bright = clamp(0.78 + 0.22 * max(glint, caustic))
    return clamp(bright * 0.89), clamp(bright * 0.96), clamp(bright), alpha


def water_mist(u, v):
    """Very soft translucent dampness puff for subtle edge condensation."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0
    r = hypot(x, y)
    if r > 0.95:
        return 0.0, 0.0, 0.0, 0.0
    core = exp(-(r / 0.50) ** 2) * 0.55
    soft = (1.0 - smoothstep(0.35, 0.94, r)) * 0.35
    alpha = clamp((core + soft) * 0.75)
    return 0.86, 0.94, 1.0, alpha


def ember_spark(u, v):
    """Rising campfire ember with hot core and delicate trailing glow."""
    x = (u - 0.5) * 2.0
    y = (v - 0.5) * 2.0  # -1 top (head), +1 bottom (tail)
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
    v = (py + 0.5) / SIZE

    if py < 96:
        return campfire_glow(u, (py + 0.5) / 96.0)

    if py < 160:
        col = px // 64
        tu = ((px % 64) + 0.5) / 64.0
        tv = ((py - 96) + 0.5) / 64.0
        if col == 0:
            return droplet_running(tu, tv)
        if col == 1:
            return droplet_round(tu, tv)
        if col == 2:
            return droplet_streak(tu, tv)
        return water_mist(tu, tv)

    if py < 224:
        col = px // 64
        tu = ((px % 64) + 0.5) / 64.0
        tv = ((py - 160) + 0.5) / 64.0
        if col == 0:
            return ember_spark(tu, tv)
        if col == 1:
            return ember_flake(tu, tv)
        if col == 2:
            return ember_twin(tu, tv)
        return ember_halo(tu, tv)

    return 0.0, 0.0, 0.0, 0.0


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
