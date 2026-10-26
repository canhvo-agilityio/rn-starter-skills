#!/usr/bin/env python3
"""Exact colors from a screenshot, so the theme uses real hex values instead of guesses.

Usage:
  palette.py <image> [--top 12]            dominant colors with share of pixels
  palette.py <image> --at X,Y [--at X,Y]   exact color at pixel coordinates (image pixels)

PNG is read with the standard library only. Other formats (JPG, HEIC, WebP) are converted
to PNG first with `sips` (macOS) or `magick`/`convert` (ImageMagick) when available.
"""
import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from collections import Counter


def to_png(path):
    with open(path, "rb") as f:
        if f.read(8) == b"\x89PNG\r\n\x1a\n":
            return path
    out = os.path.join(tempfile.mkdtemp(), "image.png")
    if shutil.which("sips"):
        subprocess.run(["sips", "-s", "format", "png", path, "--out", out],
                       check=True, capture_output=True)
    elif shutil.which("magick"):
        subprocess.run(["magick", path, out], check=True)
    elif shutil.which("convert"):
        subprocess.run(["convert", path, out], check=True)
    else:
        sys.exit("Not a PNG and no converter found (sips / ImageMagick). Export the image as PNG.")
    return out


def read_png(path):
    """Return (width, height, rows) where rows[y] is a list of (r, g, b) tuples."""
    with open(path, "rb") as f:
        data = f.read()
    pos, idat = 8, b""
    width = height = bit_depth = color_type = interlace = None
    palette = None
    while pos < len(data):
        length, ctype = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if ctype == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"PLTE":
            palette = [tuple(chunk[i:i + 3]) for i in range(0, len(chunk), 3)]
        elif ctype == b"IDAT":
            idat += chunk
        elif ctype == b"IEND":
            break
    if bit_depth != 8 or interlace:
        sys.exit("Only 8-bit, non-interlaced PNGs are supported. Re-export the image "
                 "(e.g. `sips -s format png in.png --out out.png`).")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    stride = width * channels
    raw = zlib.decompress(idat)
    rows, prev = [], bytearray(stride)
    i = 0
    for _ in range(height):
        ftype = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        for x in range(stride):
            a = line[x - channels] if x >= channels else 0
            b = prev[x]
            c = prev[x - channels] if x >= channels else 0
            if ftype == 1:
                line[x] = (line[x] + a) & 0xFF
            elif ftype == 2:
                line[x] = (line[x] + b) & 0xFF
            elif ftype == 3:
                line[x] = (line[x] + ((a + b) >> 1)) & 0xFF
            elif ftype == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 0xFF
        prev = line
        px = []
        for x in range(width):
            o = x * channels
            if color_type == 3:
                px.append(palette[line[o]])
            elif color_type in (0, 4):
                px.append((line[o],) * 3)
            else:
                px.append((line[o], line[o + 1], line[o + 2]))
        rows.append(px)
    return width, height, rows


def hexc(rgb):
    return "#%02X%02X%02X" % rgb


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("--top", type=int, default=12)
    ap.add_argument("--at", action="append", default=[], help="X,Y in image pixels")
    args = ap.parse_args()

    w, h, rows = read_png(to_png(args.image))
    print(f"image {w}x{h}")

    if args.at:
        for spec in args.at:
            x, y = (int(v) for v in spec.split(","))
            if not (0 <= x < w and 0 <= y < h):
                print(f"{spec}: outside image")
                continue
            print(f"{x},{y}: {hexc(rows[y][x])}")
        return

    # Sample a grid (fast on large screenshots) and merge near-identical shades so
    # anti-aliasing doesn't split one brand color into dozens of entries.
    step = max(1, int((w * h / 250_000) ** 0.5))
    counts = Counter()
    for y in range(0, h, step):
        for x in range(0, w, step):
            counts[rows[y][x]] += 1
    total = sum(counts.values())
    # Each cluster is reported by its most common exact color (the first one seen).
    merged = []
    for color, n in counts.most_common(3000):
        for m in merged:
            if sum(abs(color[i] - m[0][i]) for i in range(3)) <= 24:
                m[1] += n
                break
        else:
            merged.append([color, n])
    merged.sort(key=lambda m: -m[1])
    for color, n in merged[:args.top]:
        print(f"{hexc(color)}  {100 * n / total:5.1f}%")


if __name__ == "__main__":
    main()
