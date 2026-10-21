#!/usr/bin/env python3
"""Render a 1024px app icon for Mouse Scroll Flip. Standard library only."""

import math
import struct
import sys
import zlib


def write_png(path, width, height, rgba):
    def chunk(tag, data):
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def clamp01(value):
    if value < 0:
        return 0.0
    if value > 1:
        return 1.0
    return value


def smooth(edge):
    edge = clamp01(edge)
    return edge * edge * (3 - 2 * edge)


def rounded_box(x, y, cx, cy, half_w, half_h, radius):
    qx = abs(x - cx) - (half_w - radius)
    qy = abs(y - cy) - (half_h - radius)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - radius


def blend(dst, src, alpha):
    inv = 1.0 - alpha
    return (
        src[0] * alpha + dst[0] * inv,
        src[1] * alpha + dst[1] * inv,
        src[2] * alpha + dst[2] * inv,
        src[3] * alpha + dst[3] * inv,
    )


def cover(distance):
    return smooth(0.5 - distance)


def chevron(x, y, cx, cy, direction, scale):
    """Upward (direction > 0) or downward chevron. Distance is in pixels."""
    px = abs(x - cx) / scale
    py = ((y - cy) / scale) * direction
    arm = abs(py - (px * 0.9))
    if py < -0.15 or py > 0.95 or px > 0.72:
        return 80.0 * scale
    return max(arm - 0.22, -py - 0.02, py - 0.9) * scale


def render(size):
    pixels = bytearray(size * size * 4)
    for y in range(size):
        py = y + 0.5
        for x in range(size):
            px = x + 0.5
            # Background tile.
            tile = rounded_box(px, py, size / 2, size / 2, size * 0.46, size * 0.46, size * 0.22)
            t = py / size
            bg = (
                32 + (11 - 32) * t,
                111 + (58 - 111) * t,
                235 + (140 - 235) * t,
                255.0,
            )
            color = (0.0, 0.0, 0.0, 0.0)
            color = blend(color, bg, cover(tile))

            # Mouse body.
            body = rounded_box(px, py, size * 0.50, size * 0.54, size * 0.16, size * 0.25, size * 0.15)
            color = blend(color, (255, 255, 255, 255), cover(body))

            # Scroll-wheel slot. Wide enough that the arrows survive a 32px icon.
            slot = rounded_box(px, py, size * 0.50, size * 0.44, size * 0.045, size * 0.09, size * 0.04)
            color = blend(color, (27, 79, 168, 255), cover(slot))

            arrow = size * 0.055
            up = chevron(px, py, size * 0.50, size * 0.40, 1, arrow)
            down = chevron(px, py, size * 0.50, size * 0.49, -1, arrow)
            color = blend(color, (255, 255, 255, 255), cover(up))
            color = blend(color, (255, 255, 255, 255), cover(down))

            offset = (y * size + x) * 4
            pixels[offset] = int(clamp01(color[0] / 255.0) * 255)
            pixels[offset + 1] = int(clamp01(color[1] / 255.0) * 255)
            pixels[offset + 2] = int(clamp01(color[2] / 255.0) * 255)
            pixels[offset + 3] = int(clamp01(color[3] / 255.0) * 255)
    return pixels


def main():
    if len(sys.argv) != 2:
        print("usage: render_icon.py OUTPUT.png", file=sys.stderr)
        return 2
    size = 1024
    write_png(sys.argv[1], size, size, render(size))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
