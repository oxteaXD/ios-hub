#!/usr/bin/env python3
"""生成宿主 App 的图标（1024x1024，无透明通道）：扁平化的一只白文鸟，从斜上方往下看。

图案全部由纯色的几何形状拼成（圆、椭圆、胶囊形、圆角三角形），没有渐变和阴影。
只在想换图标时手动运行一次，生成的 PNG 直接入库；只依赖标准库。

    python3 scripts/make_icon.py            # 写进资源目录
    python3 scripts/make_icon.py 预览.png    # 写到指定的文件，用来先看看效果

画法：每个形状用「有符号距离」描述（点在形状里面为负、外面为正），边缘按距离做一个像素的抗锯齿，
按从后到前的顺序一层层盖上去。

鸟是在它自己的坐标里画的：原点在身体中间，头朝下（离镜头近），尾巴朝上（离镜头远），左右对称；
画完再整体缩放、转一个角度、挪到画布上。「斜俯视」靠两点表现：头压在身体前面、能同时看到脸和背；
眼睛和嘴都画在头的下半边，上面留出一大片头顶。
"""
from __future__ import annotations

import math
import struct
import sys
import zlib
from pathlib import Path

SIZE = 1024
OUTPUT = (
    Path(__file__).resolve().parent.parent
    / "App" / "Resources" / "HubAssets.xcassets" / "HubIcon.appiconset" / "HubIcon-1024.png"
)

# ---------------------------------------------------------------------------
# 配色
# ---------------------------------------------------------------------------
BACKGROUND = (0xE2, 0xC9, 0x9A)  # 米黄的底，往棕色靠了一些，不然衬不出白色的鸟
WHITE = (0xFF, 0xFF, 0xFF)       # 身体和头
SHADE = (0xEC, 0xE5, 0xDA)       # 翅膀和尾巴：比身体深一点的暖灰白，用来分出层次
BEAK = (0xEF, 0x5B, 0x70)        # 嘴：文鸟标志性的红，只用这一种颜色
PUPIL = (0x2A, 0x2A, 0x2E)       # 眼睛：一个黑点

# 整只鸟在画布上的摆法。
BIRD_SCALE = 0.96
BIRD_TILT = -35.0                # 顺时针为正：正数时头偏向左下，负数时偏向右下
BIRD_CENTER = (530.0, 540.0)


# ---------------------------------------------------------------------------
# 有符号距离
# ---------------------------------------------------------------------------
def rotate(dx: float, dy: float, degrees: float) -> tuple[float, float]:
    if not degrees:
        return dx, dy
    angle = math.radians(-degrees)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    return dx * cos_a - dy * sin_a, dx * sin_a + dy * cos_a


def circle(cx: float, cy: float, radius: float):
    def distance(px: float, py: float) -> float:
        return math.hypot(px - cx, py - cy) - radius

    return distance, (cx - radius, cy - radius, cx + radius, cy + radius)


def ellipse(cx: float, cy: float, rx: float, ry: float, degrees: float = 0.0):
    """椭圆的距离没有简单的精确公式，这里用一阶近似，在边缘附近足够准。"""

    def distance(px: float, py: float) -> float:
        dx, dy = rotate(px - cx, py - cy, degrees)
        k = math.hypot(dx / rx, dy / ry)
        if k < 1e-9:
            return -min(rx, ry)
        gradient = math.hypot(dx / (rx * rx), dy / (ry * ry)) / k
        return (k - 1.0) / gradient

    reach = max(rx, ry)
    return distance, (cx - reach, cy - reach, cx + reach, cy + reach)


def capsule(ax: float, ay: float, bx: float, by: float, radius: float):
    """两端是半圆的粗线段。"""
    ex, ey = bx - ax, by - ay
    length_squared = ex * ex + ey * ey

    def distance(px: float, py: float) -> float:
        vx, vy = px - ax, py - ay
        t = 0.0 if length_squared == 0 else min(max((vx * ex + vy * ey) / length_squared, 0.0), 1.0)
        return math.hypot(vx - ex * t, vy - ey * t) - radius

    return distance, (
        min(ax, bx) - radius, min(ay, by) - radius, max(ax, bx) + radius, max(ay, by) + radius,
    )


def tapered_capsule(ax: float, ay: float, radius_a: float, bx: float, by: float, radius_b: float):
    """两头粗细不一样的胶囊形：a 端半径 radius_a，b 端半径 radius_b，中间用切线连起来。"""
    ex, ey = bx - ax, by - ay
    length = math.hypot(ex, ey)
    ux, uy = ex / length, ey / length
    slope = (radius_a - radius_b) / length
    flat = math.sqrt(max(1.0 - slope * slope, 0.0))

    def distance(px: float, py: float) -> float:
        qx, qy = px - ax, py - ay
        along = qx * ux + qy * uy
        across = abs(-qx * uy + qy * ux)
        k = -across * slope + along * flat
        if k < 0.0:
            return math.hypot(across, along) - radius_a
        if k > flat * length:
            return math.hypot(across, along - length) - radius_b
        return across * flat + along * slope - radius_a

    return distance, (
        min(ax - radius_a, bx - radius_b), min(ay - radius_a, by - radius_b),
        max(ax + radius_a, bx + radius_b), max(ay + radius_a, by + radius_b),
    )


def rounded_triangle(p0: tuple[float, float], p1: tuple[float, float], p2: tuple[float, float], radius: float):
    """圆角三角形：先算到三角形的精确距离，再向外扩 radius。"""
    points = (p0, p1, p2)
    edges = [(points[(i + 1) % 3][0] - points[i][0], points[(i + 1) % 3][1] - points[i][1]) for i in range(3)]
    winding = 1.0 if edges[0][0] * edges[2][1] - edges[0][1] * edges[2][0] > 0 else -1.0

    def distance(px: float, py: float) -> float:
        best_squared = float("inf")
        inside = float("inf")
        for (qx, qy), (ex, ey) in zip(points, edges):
            vx, vy = px - qx, py - qy
            t = min(max((vx * ex + vy * ey) / (ex * ex + ey * ey), 0.0), 1.0)
            wx, wy = vx - ex * t, vy - ey * t
            best_squared = min(best_squared, wx * wx + wy * wy)
            inside = min(inside, winding * (vx * ey - vy * ex))
        sign = -1.0 if inside > 0 else 1.0
        return sign * math.sqrt(best_squared) - radius

    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return distance, (min(xs) - radius, min(ys) - radius, max(xs) + radius, max(ys) + radius)


def smooth_union(first, second, blend: float):
    """两个形状融成一个，接缝处用圆滑的过渡代替尖锐的凹角。"""
    (d1, b1), (d2, b2) = first, second

    def distance(px: float, py: float) -> float:
        a, b = d1(px, py), d2(px, py)
        h = max(blend - abs(a - b), 0.0) / blend
        return min(a, b) - h * h * blend * 0.25

    return distance, (
        min(b1[0], b2[0]) - blend, min(b1[1], b2[1]) - blend,
        max(b1[2], b2[2]) + blend, max(b1[3], b2[3]) + blend,
    )


def intersect(first, second):
    (d1, b1), (d2, b2) = first, second

    def distance(px: float, py: float) -> float:
        return max(d1(px, py), d2(px, py))

    return distance, (max(b1[0], b2[0]), max(b1[1], b2[1]), min(b1[2], b2[2]), min(b1[3], b2[3]))


def placed(shape, scale: float, degrees: float, center: tuple[float, float]):
    """把一个形状先缩放、再绕原点旋转、最后挪到画布上。距离跟着缩放，所以边缘的抗锯齿仍然是一个像素。"""
    distance, (x0, y0, x1, y1) = shape
    angle = math.radians(degrees)
    cos_a, sin_a = math.cos(angle), math.sin(angle)
    cx, cy = center

    def moved(px: float, py: float) -> float:
        ux, uy = (px - cx) / scale, (py - cy) / scale
        return distance(ux * cos_a + uy * sin_a, -ux * sin_a + uy * cos_a) * scale

    corners = [
        (scale * (x * cos_a - y * sin_a) + cx, scale * (x * sin_a + y * cos_a) + cy)
        for x in (x0, x1)
        for y in (y0, y1)
    ]
    xs = [corner[0] for corner in corners]
    ys = [corner[1] for corner in corners]
    return moved, (min(xs), min(ys), max(xs), max(ys))


# ---------------------------------------------------------------------------
# 图案：从后到前。坐标是鸟自己的：原点在身体中间，头朝下，尾巴朝上。
# ---------------------------------------------------------------------------
def bird_layers():
    body = ellipse(0, -40, 250, 240)   # 身体：离镜头远，所以在上面
    head = circle(0, 150, 172)         # 头：离镜头近，压在身体前面
    outline = smooth_union(body, head, 60)
    beak = rounded_triangle((-60, 268), (60, 268), (0, 338), 28)

    return [
        # 尾巴，从身体后面伸出去，末端略宽
        (tapered_capsule(0, -215, 40, 0, -385, 54), SHADE),
        # 身体和头连成的一整块
        (outline, WHITE),
        # 收在背上的两只翅膀：肩膀那头圆，向尾巴收尖，中间留一条白色的背
        (intersect(tapered_capsule(-150, 24, 108, -40, -212, 24), body), SHADE),
        (intersect(tapered_capsule(150, 24, 108, 40, -212, 24), body), SHADE),
        # 头盖在翅膀前面
        (head, WHITE),
        # 嘴从脸上伸出头的轮廓一点；两只眼睛在嘴根两侧
        (beak, BEAK),
        (circle(-108, 232, 19), PUPIL),
        (circle(108, 232, 19), PUPIL),
    ]


def build_layers():
    return [(placed(shape, BIRD_SCALE, BIRD_TILT, BIRD_CENTER), color) for shape, color in bird_layers()]


def render() -> bytes:
    layers = [(distance, bounds, color) for (distance, bounds), color in build_layers()]

    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)  # 每行开头的滤波类型：不滤波
        py = y + 0.5
        active = [layer for layer in layers if layer[1][1] - 1.0 <= py <= layer[1][3] + 1.0]
        for x in range(SIZE):
            px = x + 0.5
            red, green, blue = BACKGROUND
            for distance, bounds, color in active:
                if px < bounds[0] - 1.0 or px > bounds[2] + 1.0:
                    continue
                coverage = 0.5 - distance(px, py)
                if coverage <= 0.0:
                    continue
                if coverage > 1.0:
                    coverage = 1.0
                red += (color[0] - red) * coverage
                green += (color[1] - green) * coverage
                blue += (color[2] - blue) * coverage
            rows.append(int(red + 0.5))
            rows.append(int(green + 0.5))
            rows.append(int(blue + 0.5))
    return bytes(rows)


def chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else OUTPUT
    # 颜色类型 2：8 位 RGB，不带透明通道（App 图标不允许透明）。
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", header)
        + chunk(b"IDAT", zlib.compress(render(), 9))
        + chunk(b"IEND", b"")
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(png)
    print("已生成 {}（{} 字节）".format(output, len(png)))


if __name__ == "__main__":
    main()
