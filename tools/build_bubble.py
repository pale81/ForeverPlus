#!/usr/bin/env python3
"""Draws the speech bubble of the conversation (Modules/Dialog.lua) as TGA files in Media/Bubble, at twice the
size they show: bubble.tga (128 x 128, a rounded shape for a nine-slice: corners 48 px = 24 points) and
tail.tga (64 x 64, a curved tail pointing down left). Dark fill, bronze rim, soft shadow; no foreign art.

    /tmp/venv/bin/python tools/build_bubble.py [--preview DIR]   (needs numpy and Pillow)
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Media', 'Bubble')
SS = 4  # supersampling
FILL = (14, 13, 17, 255)  # opaque: the tail lies on the bubble without a darker seam
RIM = (214, 168, 104, 255)
RIM_WIDTH = 3.2  # px at twice the size
SHADOW = 0.45
PAD = 12  # room for the shadow around the shape (px)
RADIUS = 44


def compose(shape, size, rim_mask=None):
    """shape: L image (supersampled) of the filled shape; rim_mask: where the rim may show (default all edges)."""
    big = shape.size[0]
    a = np.asarray(shape, np.float32) / 255
    inner = np.asarray(shape.filter(ImageFilter.MinFilter(int(RIM_WIDTH * SS) | 1)), np.float32) / 255
    rim = np.clip(a - inner, 0, 1)
    if rim_mask is not None:
        rim *= rim_mask
        inner = np.clip(a - rim, 0, 1)
    shadow = np.asarray(shape.filter(ImageFilter.GaussianBlur(5 * SS)), np.float32) / 255
    shadow = np.roll(np.roll(shadow, 2 * SS, axis=0), 1 * SS, axis=1) * SHADOW
    rgba = np.zeros((big, big, 4), np.float32)
    # shadow below, then fill, then rim
    rgba[..., 3] = shadow
    for color, mask in ((FILL, inner), (RIM, rim)):
        alpha = mask * color[3] / 255
        out_a = alpha + rgba[..., 3] * (1 - alpha)
        for c in range(3):
            rgba[..., c] = np.where(out_a > 0, (color[c] * alpha + rgba[..., c] * rgba[..., 3] * (1 - alpha)) /
                                    np.maximum(out_a, 1e-6), 0)
        rgba[..., 3] = out_a
    image = Image.fromarray(np.clip(rgba * [1, 1, 1, 255], 0, 255).astype(np.uint8), 'RGBA')
    return image.resize((size, size), Image.LANCZOS)


def bubble():
    size = 128
    shape = Image.new('L', (size * SS, size * SS), 0)
    ImageDraw.Draw(shape).rounded_rectangle(
        (PAD * SS, PAD * SS, (size - PAD) * SS - 1, (size - PAD) * SS - 1), radius=RADIUS * SS, fill=255)
    return compose(shape, size)


def bezier(p0, p1, p2, steps=40):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0],
             (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / steps for i in range(steps + 1))]


def tail():
    """The top 10 px lie on the bubble (fill only, they cover its rim); the sides curve to a tip down left."""
    size = 64
    left = bezier((22, 0), (22, 26), (8, 50))
    right = bezier((8, 50), (34, 34), (46, 0))
    points = [(x * SS, y * SS) for x, y in left + right]
    shape = Image.new('L', (size * SS, size * SS), 0)
    ImageDraw.Draw(shape).polygon(points, fill=255)
    ys = np.arange(size * SS, dtype=np.float32)[:, None] / SS
    rim_mask = np.clip((ys - 9) / 2, 0, 1) * np.ones((1, size * SS), np.float32)
    return compose(shape, size, rim_mask)


def main():
    preview = sys.argv[sys.argv.index('--preview') + 1] if '--preview' in sys.argv else None
    os.makedirs(OUT, exist_ok=True)
    images = {'bubble': bubble(), 'tail': tail()}
    for name, image in images.items():
        image.save(os.path.join(OUT, name + '.tga'), compression='tga_rle')
    if preview:
        os.makedirs(preview, exist_ok=True)
        for name, image in images.items():
            board = Image.new('RGBA', image.size, (90, 110, 90, 255))
            board.alpha_composite(image)
            board.resize((image.size[0] * 3, image.size[1] * 3), Image.NEAREST).save(os.path.join(preview, name + '.png'))
    print('written to', OUT)


if __name__ == '__main__':
    main()
