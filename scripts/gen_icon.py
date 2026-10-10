#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 App 图标（1024x1024 PNG），只用 Python 标准库，不依赖 Pillow。

为什么要在 CI 里现生成：PNG 是二进制文件，走代码提交不方便；
脚本是纯文本，随时可改配色，构建前跑一次即可。

用法：  python3 scripts/gen_icon.py [--size 1024]
输出：  OctopIOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png
"""

from __future__ import annotations

import argparse
import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_DIR = os.path.join(ROOT, "OctopIOS", "Assets.xcassets", "AppIcon.appiconset")


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(v: float, lo: float = 0.0, hi: float = 1.0) -> float:
    return lo if v < lo else hi if v > hi else v


def cov_circle(x: float, y: float, cx: float, cy: float, r: float) -> float:
    """圆形覆盖度，1.6px 过渡带做抗锯齿。"""
    d = math.hypot(x - cx, y - cy)
    return clamp((r - d) / 1.6 + 0.5)


def render(size: int = 1024) -> bytes:
    s = float(size)
    c = s / 2.0

    # 背景：左上深蓝 -> 右下紫，叠加左上青蓝高光 + 轻微暗角
    bg_a = (0x1B, 0x1F, 0x4B)   # #1B1F4B
    bg_b = (0x6D, 0x28, 0xD9)   # #6D28D9
    glow = (0x22, 0xD3, 0xEE)   # #22D3EE

    # 前景：白色圆环 + 中心圆点 + 8 个轨道小点（触手端点的意象）
    r_out = 0.283 * s      # 290 @1024
    r_in = 0.217 * s       # 222
    r_core = 0.043 * s     # 44
    r_orbit = 0.357 * s    # 366
    r_dot = 0.022 * s      # 22

    gl_cx, gl_cy, gl_r = 0.30 * s, 0.24 * s, 0.72 * s

    orbits = []
    for i in range(8):
        ang = math.pi * 2 * i / 8 - math.pi / 2
        orbits.append((c + r_orbit * math.cos(ang), c + r_orbit * math.sin(ang)))

    rows = []
    for y in range(size):
        fy = y + 0.5
        row = bytearray()
        for x in range(size):
            fx = x + 0.5

            t = clamp((fx + fy) / (2.0 * s))
            r = lerp(bg_a[0], bg_b[0], t)
            g = lerp(bg_a[1], bg_b[1], t)
            b = lerp(bg_a[2], bg_b[2], t)

            gd = math.hypot(fx - gl_cx, fy - gl_cy)
            if gd < gl_r:
                w = (1.0 - gd / gl_r) ** 2 * 0.30
                r = lerp(r, glow[0], w)
                g = lerp(g, glow[1], w)
                b = lerp(b, glow[2], w)

            # 暗角
            vd = math.hypot(fx - c, fy - c) / (0.72 * s)
            if vd > 0.5:
                v = clamp((vd - 0.5) / 0.5) ** 2 * 0.22
                r *= (1.0 - v)
                g *= (1.0 - v)
                b *= (1.0 - v)

            a = max(
                min(cov_circle(fx, fy, c, c, r_out), 1.0 - cov_circle(fx, fy, c, c, r_in)),
                cov_circle(fx, fy, c, c, r_core) * 0.95,
            )
            for (ox, oy) in orbits:
                av = cov_circle(fx, fy, ox, oy, r_dot) * 0.88
                if av > a:
                    a = av

            if a > 0.0:
                aa = clamp(a) * 0.97
                r = lerp(r, 252.0, aa)
                g = lerp(g, 252.0, aa)
                b = lerp(b, 255.0, aa)

            row += bytes((int(clamp(r, 0, 255)), int(clamp(g, 0, 255)), int(clamp(b, 0, 255))))
        rows.append(bytes(row))
    return b"".join(b"\x00" + r for r in rows)


def write_png(path: str, size: int, raw: bytes) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0)
    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(png)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--size", type=int, default=1024)
    args = ap.parse_args()

    size = args.size
    out = os.path.join(OUT_DIR, "icon-%d.png" % size)
    print("rendering %dx%d ..." % (size, size))
    write_png(out, size, render(size))
    print("wrote", out, os.path.getsize(out), "bytes")


if __name__ == "__main__":
    main()
