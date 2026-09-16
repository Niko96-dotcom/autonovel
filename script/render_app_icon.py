#!/usr/bin/env python3
"""Write a 1024x1024 RGBA PNG for the AutoNovel Studio app icon."""

from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path


def write_png(path: Path, width: int, height: int, rgba: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(rgba[y * stride : (y + 1) * stride])
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def mix(a: tuple[int, int, int, int], b: tuple[int, int, int, int], t: float) -> tuple[int, int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))  # type: ignore[return-value]


def rounded_rect(px: float, py: float, x: float, y: float, w: float, h: float, r: float) -> float:
    qx = abs(px - (x + w / 2)) - w / 2 + r
    qy = abs(py - (y + h / 2)) - h / 2 + r
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r


def render(size: int = 1024) -> bytes:
    ink = (28, 24, 22, 255)
    coral = (224, 61, 46, 255)
    page = (248, 244, 239, 255)
    line = (198, 186, 176, 255)
    pixels = bytearray(size * size * 4)
    margin = size * 0.08
    board = size - 2 * margin
    radius = board * 0.22
    book_x = size * 0.27
    book_y = size * 0.22
    book_w = size * 0.46
    book_h = size * 0.56
    mark_x = book_x + book_w * 0.62
    mark_w = size * 0.07

    for y in range(size):
        for x in range(size):
            d = rounded_rect(x + 0.5, y + 0.5, margin, margin, board, board, radius)
            if d > 1.2:
                color = (0, 0, 0, 0)
            else:
                t = (x + y) / (2 * size)
                color = mix(ink, (48, 28, 26, 255), t * 0.45)
                cover = rounded_rect(x + 0.5, y + 0.5, book_x, book_y, book_w, book_h, size * 0.04)
                if cover < 0.8:
                    color = page
                    inner = (y - book_y) / book_h
                    if 0.22 < inner < 0.78 and abs(((x - book_x) / book_w) - 0.42) < 0.28:
                        line_y = (inner - 0.22) * 6
                        if abs(line_y - round(line_y)) < 0.08:
                            color = line
                mark = rounded_rect(x + 0.5, y + 0.5, mark_x, book_y - size * 0.02, mark_w, book_h * 0.42, size * 0.02)
                if mark < 0.8:
                    color = coral
                if d > 0:
                    alpha = max(0.0, min(1.0, 1.2 - d))
                    color = (color[0], color[1], color[2], int(color[3] * alpha))
            idx = (y * size + x) * 4
            pixels[idx : idx + 4] = bytes(color)
    return bytes(pixels)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: render_app_icon.py <1024-png-path>")
    dest = Path(sys.argv[1])
    dest.parent.mkdir(parents=True, exist_ok=True)
    write_png(dest, 1024, 1024, render(1024))


if __name__ == "__main__":
    main()
