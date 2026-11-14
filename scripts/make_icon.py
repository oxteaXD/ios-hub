#!/usr/bin/env python3
"""生成宿主 App 的图标（1024x1024，无透明通道）。

图案是渐变底色上的四个圆角方块，代表「一个 App 里装着几个应用」。
只在想换图标时手动运行一次，生成的 PNG 直接入库；只依赖标准库。

    python3 scripts/make_icon.py
"""
from __future__ import annotations

import struct
import zlib
from pathlib import Path

SIZE = 1024
OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "App" / "Resources" / "HubAssets.xcassets" / "HubIcon.appiconset" / "HubIcon-1024.png"
)

# 底色：左上到右下的渐变。
TOP_LEFT = (0x4F, 0x46, 0xE5)
BOTTOM_RIGHT = (0x06, 0xB6, 0xD4)

# 四个方块：边长、圆角、间距，以及各自的不透明度。
TILE = 300.0
RADIUS = 70.0
GAP = 64.0
ALPHAS = ((1.0, 0.82), (0.82, 0.64))


def rounded_rect_coverage(px: float, py: float, cx: float, cy: float) -> float:
    """像素中心 (px, py) 被以 (cx, cy) 为中心的圆角方块覆盖的比例，边缘做一个像素的抗锯齿。"""
    half = TILE / 2.0 - RADIUS
    dx = max(abs(px - cx) - half, 0.0)
    dy = max(abs(py - cy) - half, 0.0)
    distance = (dx * dx + dy * dy) ** 0.5 - RADIUS
    return min(max(0.5 - distance, 0.0), 1.0)


def render() -> bytes:
    offset = (TILE + GAP) / 2.0
    centers = (SIZE / 2.0 - offset, SIZE / 2.0 + offset)
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # 每行开头的滤波类型：不滤波
        py = y + 0.5
        row_index = 0 if py < SIZE / 2.0 else 1
        for x in range(SIZE):
            px = x + 0.5
            t = (x + y) / (2.0 * (SIZE - 1))
            red = TOP_LEFT[0] + (BOTTOM_RIGHT[0] - TOP_LEFT[0]) * t
            green = TOP_LEFT[1] + (BOTTOM_RIGHT[1] - TOP_LEFT[1]) * t
            blue = TOP_LEFT[2] + (BOTTOM_RIGHT[2] - TOP_LEFT[2]) * t

            column_index = 0 if px < SIZE / 2.0 else 1
            coverage = rounded_rect_coverage(px, py, centers[column_index], centers[row_index])
            if coverage > 0.0:
                alpha = coverage * ALPHAS[row_index][column_index]
                red += (255.0 - red) * alpha
                green += (255.0 - green) * alpha
                blue += (255.0 - blue) * alpha

            rows.append(int(red + 0.5))
            rows.append(int(green + 0.5))
            rows.append(int(blue + 0.5))
    return bytes(rows)


def chunk(kind: bytes, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def main() -> None:
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)  # 8 位、RGB、无透明通道
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(render(), 9)) + chunk(b"IEND", b"")
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(png)
    print("已生成 {}（{} 字节）".format(OUTPUT, len(png)))


if __name__ == "__main__":
    main()
