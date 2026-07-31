#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Convert artwork to the AMI-compatible A720 vendor-splash BMP format."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from PIL import Image

WIDTH = 768
HEIGHT = 432
FILE_SIZE = 1_327_160
PIXEL_OFFSET = 54


def convert(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    image.thumbnail((WIDTH, HEIGHT), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 255))
    x = (WIDTH - image.width) // 2
    y = (HEIGHT - image.height) // 2
    canvas.alpha_composite(image, (x, y))
    rgb = canvas.convert("RGB")

    header = bytearray()
    header += b"BM"
    header += struct.pack("<I", FILE_SIZE)
    header += b"\x00\x00\x00\x00"
    header += struct.pack("<I", PIXEL_OFFSET)
    header += struct.pack("<I", 40)
    header += struct.pack("<i", WIDTH)
    header += struct.pack("<i", HEIGHT)
    header += struct.pack("<H", 1)
    header += struct.pack("<H", 32)
    header += struct.pack("<I", 0)
    header += struct.pack("<I", WIDTH * HEIGHT * 4)
    header += struct.pack("<i", 0)
    header += struct.pack("<i", 0)
    header += struct.pack("<I", 0)
    header += struct.pack("<I", 0)

    pixels = bytearray()
    px = rgb.load()
    for row in range(HEIGHT - 1, -1, -1):
        for column in range(WIDTH):
            red, green, blue = px[column, row]
            pixels += bytes((blue, green, red, 0))

    output = bytes(header) + bytes(pixels) + b"\x00\x00"
    if len(output) != FILE_SIZE:
        raise RuntimeError(f"unexpected BMP size: {len(output)}")

    destination.write_bytes(output)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    convert(args.source, args.destination)


if __name__ == "__main__":
    main()
