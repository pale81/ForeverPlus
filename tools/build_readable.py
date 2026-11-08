#!/usr/bin/env python3
"""Draws the materials of the readable texts (Modules/Readable.lua) as TGA files in Media/Readable.

Everything is generated from noise (no foreign art): parchment sheet, open book, stone plate, metal plate,
soft shadow, screen vignette and the divider under the title. Needs numpy and Pillow:

    python3 -m venv /tmp/venv && /tmp/venv/bin/pip install numpy pillow
    /tmp/venv/bin/python tools/build_readable.py [--preview DIR]

The sizes and used regions must match LOOKS in Modules/Readable.lua.
"""
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Readable")
RNG = np.random.default_rng(1793)


def noise(h, w, scale, octaves=5, persistence=0.55):
    """Fractal value noise in 0..1."""
    total = np.zeros((h, w), np.float32)
    amplitude, weight = 1.0, 0.0
    for octave in range(octaves):
        cells = max(2, int(scale * 2 ** octave))
        grid = RNG.random((cells, cells)).astype(np.float32)
        layer = np.asarray(Image.fromarray(grid, "F").resize((w, h), Image.BICUBIC), np.float32)
        total += layer * amplitude
        weight += amplitude
        amplitude *= persistence
    total /= weight
    return (total - total.min()) / (total.max() - total.min() + 1e-6)


def streaks(h, w, length, strength=1.0):
    """Noise stretched along x: fibres, brushed metal, leather grain."""
    base = RNG.random((h, max(4, w // length))).astype(np.float32)
    layer = np.asarray(Image.fromarray(base, "F").resize((w, h), Image.BICUBIC), np.float32)
    layer = (layer - layer.min()) / (layer.max() - layer.min() + 1e-6)
    return 0.5 + (layer - 0.5) * strength


def blur(a, radius):
    """Gaussian blur (separable, edges repeated)."""
    size = max(1, int(radius * 3))
    xs = np.arange(-size, size + 1, dtype=np.float32)
    kernel = np.exp(-(xs ** 2) / (2 * radius * radius))
    kernel /= kernel.sum()
    out = np.pad(a.astype(np.float32), size, mode="edge")
    out = np.apply_along_axis(lambda row: np.convolve(row, kernel, mode="valid"), 1, out)
    out = np.apply_along_axis(lambda col: np.convolve(col, kernel, mode="valid"), 0, out)
    return out


def edge_distance(h, w, x0, y0, x1, y1, radius=0.0):
    """Distance in pixels to the edge of a (rounded) rectangle, negative outside."""
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    cx = np.clip(xs, x0 + radius, x1 - radius)
    cy = np.clip(ys, y0 + radius, y1 - radius)
    corner = radius - np.hypot(xs - cx, ys - cy)
    straight = np.minimum.reduce([xs - x0, x1 - xs, ys - y0, y1 - ys])
    inside_corner = ((xs < x0 + radius) | (xs > x1 - radius)) & ((ys < y0 + radius) | (ys > y1 - radius))
    return np.where(inside_corner, corner, straight)


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = t[..., None] if np.ndim(t) == 2 else t
    return a * (1 - t) + b * t


def save(name, rgb, alpha, preview=None):
    rgba = np.dstack([np.clip(rgb, 0, 255), np.clip(alpha * 255, 0, 255)]).astype(np.uint8)
    image = Image.fromarray(rgba, "RGBA")
    os.makedirs(OUT, exist_ok=True)
    image.save(os.path.join(OUT, name + ".tga"), compression="tga_rle")
    if preview:
        os.makedirs(preview, exist_ok=True)
        board = Image.new("RGBA", image.size, (60, 70, 60, 255))
        board.alpha_composite(image)
        board.save(os.path.join(preview, name + ".png"))


def paper(h, w, tone=(238, 222, 184), stain=1.0):
    """Aged paper: tone, stains, mottling and fibres."""
    stains = noise(h, w, 3, 4)
    mottle = noise(h, w, 18, 4)
    fibres = streaks(h, w, 40, 0.6) * 0.5 + streaks(h, w, 9, 0.6) * 0.5
    grain = RNG.normal(0, 1, (h, w)).astype(np.float32)
    shade = 1 - 0.10 * stain * smoothstep(0.45, 0.95, stains) - 0.05 * (mottle - 0.5) - 0.05 * (fibres - 0.5) - 0.012 * grain
    rgb = np.dstack([np.full((h, w), c, np.float32) for c in tone]) * shade[..., None]
    # tea stains turn the paper warmer
    warm = smoothstep(0.55, 1.0, stains) * 0.35 * stain
    return mix(rgb, rgb * np.array([0.92, 0.80, 0.60], np.float32), warm)


def parchment(preview):
    """Single sheet, 512x512 canvas, used region x 48..464 (416 x 512): deckled, darkened edges."""
    h, w = 512, 512
    x0, x1 = 48, 464
    rgb = paper(h, w)
    wobble = (noise(h, w, 10, 4) - 0.5) * 14 + (noise(h, w, 40, 2) - 0.5) * 4
    d = edge_distance(h, w, x0 + 4, 4, x1 - 4, h - 4, 10) + wobble
    burn = 1 - smoothstep(0, 46, d)
    rgb = mix(rgb, rgb * np.array([0.55, 0.38, 0.22], np.float32), burn ** 1.6 * 0.85)
    rim = 1 - smoothstep(0, 3, d)
    rgb = mix(rgb, np.array([70, 42, 22], np.float32), rim * 0.8)
    alpha = smoothstep(-1.0, 1.0, d)
    save("parchment", rgb, alpha, preview)


def book(preview):
    """Open book, 1024x1024 canvas, used region 1024 x 672: leather cover, two pages, gutter."""
    h, w = 672, 1024
    leather_grain = noise(h, w, 60, 3) * 0.6 + streaks(h, w, 6, 1.0) * 0.4
    leather_big = noise(h, w, 4, 3)
    leather = np.dstack([np.full((h, w), c, np.float32) for c in (92, 40, 26)])
    leather *= (0.75 + 0.35 * leather_grain + 0.2 * (leather_big - 0.5))[..., None]
    cover = edge_distance(h, w, 0, 0, w - 1, h - 1, 26)
    # worn, lighter edges of the cover and a gold tooled line
    leather = mix(leather, leather * 1.45, (1 - smoothstep(0, 10, cover)) * 0.6)
    tool = np.exp(-((cover - 13) ** 2) / 2.0)
    leather = mix(leather, np.array([196, 150, 72], np.float32), tool * 0.55)
    rgb = leather
    alpha = smoothstep(-1, 1, cover)
    # page block: stacked page edges below and at the outer sides
    mid = w // 2
    top, bottom = 30, h - 38
    ys_all, xs_all = np.mgrid[0:h, 0:w].astype(np.float32)
    for side in (0, 1):
        px0, px1 = (40, mid) if side == 0 else (mid, w - 40)
        for layer in range(5, 0, -1):
            off = layer * 2
            lx0, lx1 = (px0 - off, px1) if side == 0 else (px0, px1 + off)
            stack = edge_distance(h, w, lx0, top + off * 0.5, lx1, bottom + off, 6)
            tone = 205 - layer * 12
            rgb = mix(rgb, np.array([tone, tone * 0.93, tone * 0.78], np.float32), smoothstep(-0.8, 0.8, stack))
        sheet = paper(h, w, (242, 228, 192), 0.45)
        # rounded at the outer corners, square at the fold
        if side == 0:
            dist = np.minimum(edge_distance(h, w, px0, top, px1 + 20, bottom, 6), mid + 0.5 - xs_all)
        else:
            dist = np.minimum(edge_distance(h, w, px0 - 20, top, px1, bottom, 6), xs_all - mid + 0.5)
        xs = np.mgrid[0:h, 0:w][1].astype(np.float32)
        to_gutter = (mid - xs) if side == 0 else (xs - mid)
        gutter = np.exp(-np.clip(to_gutter, 0, None) / 46.0)
        curl = np.exp(-np.clip(np.where(side == 0, xs - px0, px1 - xs), 0, None) / 22.0)
        shade = 1 - 0.50 * gutter + 0.04 * curl - 0.10 * (1 - smoothstep(0, 18, dist))
        sheet = sheet * shade[..., None]
        rgb = mix(rgb, sheet, smoothstep(-0.8, 0.8, dist))
    # the fold itself
    xs = np.mgrid[0:h, 0:w][1].astype(np.float32)
    fold = np.exp(-((xs - mid) ** 2) / 6.0) * smoothstep(top - 2, top + 6, np.mgrid[0:h, 0:w][0]) * (
        1 - smoothstep(bottom - 6, bottom + 2, np.mgrid[0:h, 0:w][0]))
    rgb = mix(rgb, np.array([70, 50, 32], np.float32), fold * 0.35)
    canvas = np.zeros((1024, 1024, 3), np.float32)
    canvas_alpha = np.zeros((1024, 1024), np.float32)
    canvas[:h], canvas_alpha[:h] = rgb, alpha
    save("book", canvas, canvas_alpha, preview)


def bevel_light(height, strength):
    """Light from the upper left on a height map: 1 = flat."""
    gy, gx = np.gradient(height)
    return 1 + strength * (gx + gy)


def stone(preview):
    """Stone plate, 512x512 canvas, used region x 48..464: light granite (tinted in the game), bevel, groove."""
    h, w = 512, 512
    x0, x1 = 48, 464
    base = noise(h, w, 6, 6)
    specks = (RNG.random((h, w)) > 0.985).astype(np.float32)
    specks = blur(specks, 0.6)
    strata = streaks(h, w, 3, 1.0)
    tone = 180 + 70 * (base - 0.5) + 16 * (strata - 0.5) - 80 * specks + RNG.normal(0, 5, (h, w))
    rgb = np.dstack([tone * 1.0, tone * 0.98, tone * 0.94])
    chip = (noise(h, w, 14, 3) - 0.5) * 5
    plain = edge_distance(h, w, x0 + 3, 3, x1 - 3, h - 3, 14)
    d = plain + chip
    height = smoothstep(0, 22, d) * 16 + base * 4
    height -= np.exp(-((plain - 32) ** 2) / 3.0) * 3.5
    light = bevel_light(blur(height, 1.0), 0.22)
    rgb = rgb * np.clip(light, 0.45, 1.6)[..., None]
    rgb *= (0.86 + 0.14 * smoothstep(0, 60, d))[..., None]
    alpha = smoothstep(-1, 1, d)
    save("stone", rgb, alpha, preview)


def metal(preview):
    """Metal plate, 512x512 canvas, used region x 48..464: brushed grey (tinted in the game), rivets."""
    h, w = 512, 512
    x0, x1 = 48, 464
    brushed = streaks(h, w, 60, 1.0) * 0.6 + streaks(h, w, 12, 1.0) * 0.4
    cloud = noise(h, w, 3, 3)
    tone = 200 + 30 * (brushed - 0.5) + 30 * (cloud - 0.5)
    rgb = np.dstack([tone, tone, tone])
    d = edge_distance(h, w, x0 + 3, 3, x1 - 3, h - 3, 8)
    height = smoothstep(0, 12, d) * 12
    height -= np.exp(-((d - 24) ** 2) / 3.0) * 2.5
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    for rx, ry in ((x0 + 26, 26), (x1 - 26, 26), (x0 + 26, h - 26), (x1 - 26, h - 26)):
        r = np.hypot(xs - rx, ys - ry)
        height += np.sqrt(np.clip(1 - (r / 10.0) ** 2, 0, None)) * 8
        rgb *= (1 - 0.35 * np.exp(-((r - 10.5) ** 2) / 2.0))[..., None]
    light = bevel_light(blur(height, 0.8), 0.18)
    rgb = rgb * np.clip(light, 0.4, 1.7)[..., None]
    rgb *= (0.8 + 0.2 * smoothstep(0, 80, d))[..., None]
    alpha = smoothstep(-1, 1, d)
    save("metal", rgb, alpha, preview)


def shadow(preview):
    """Soft shadow under the material, 128x128, black with soft alpha."""
    n = 128
    a = np.zeros((n, n), np.float32)
    a[24:104, 24:104] = 1
    a = blur(a, 12)
    save("shadow", np.zeros((n, n, 3), np.float32), a / a.max(), preview)


def vignette(preview):
    """Darkens the screen around the text, 256x256, stronger at the edges."""
    n = 256
    ys, xs = np.mgrid[0:n, 0:n].astype(np.float32)
    r = np.hypot((xs - n / 2) / (n / 2), (ys - n / 2) / (n / 2))
    a = 0.16 + 0.44 * smoothstep(0.25, 1.4, r)
    save("vignette", np.zeros((n, n, 3), np.float32), a, preview)


def divider(preview):
    """Line under the title, 256x32: thin, fading at the ends, a small diamond in the middle (tinted in the game)."""
    h, w = 32, 256
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float32)
    fade = smoothstep(0, 90, np.minimum(xs, w - 1 - xs))
    line = np.exp(-((ys - h / 2 + 0.5) ** 2) / 0.9) * fade
    diamond = 1 - smoothstep(4.5, 5.5, np.abs(xs - w / 2 + 0.5) + np.abs(ys - h / 2 + 0.5))
    a = np.maximum(line, diamond)
    save("divider", np.full((h, w, 3), 255, np.float32), a, preview)


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
    for build in (parchment, book, stone, metal, shadow, vignette, divider):
        build(preview)
    print("written to", OUT)


if __name__ == "__main__":
    main()
