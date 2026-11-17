#!/usr/bin/env python3
"""Build the inverse circular mask for the dialogue model's full-size viewport."""
from math import hypot
from pathlib import Path
from struct import pack

SIZE = 128
SAMPLES = 4
RADIUS = SIZE * 64 / 70 / 2  # 64-point face inside its 70-point frame
TARGET = Path(__file__).resolve().parent.parent / "Media/Bubble/portrait-cutout.tga"


def main():
    pixels = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            outside = sum(
                hypot(x + (sx + 0.5) / SAMPLES - SIZE / 2,
                      y + (sy + 0.5) / SAMPLES - SIZE / 2) >= RADIUS
                for sy in range(SAMPLES) for sx in range(SAMPLES)
            )
            pixels.extend((255, 255, 255, round(255 * outside / SAMPLES ** 2)))
    header = pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, SIZE, SIZE, 32, 0x28)
    TARGET.write_bytes(header + pixels)
    print("written to", TARGET)


if __name__ == "__main__":
    main()
