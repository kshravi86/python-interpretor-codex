#!/usr/bin/env python3
"""
Generate a simple, branded 1024x1024 PNG app icon (blue gradient background
with a white water drop) using only the Python standard library. This avoids
external dependencies and produces a non-placeholder icon for store uploads.

Output: branding/app_icon_1024.png
"""
from pathlib import Path
import struct, zlib, math

W = H = 1024
OUT = Path("branding/app_icon_1024.png")

def lerp(a, b, t):
    return int(a + (b - a) * t)

def bg_color(y):
    # Vertical gradient from cyan (#0EA5E9) to indigo/blue (#2563EB)
    top = (14, 165, 233)
    bot = (37, 99, 235)
    t = y / (H - 1)
    return (lerp(top[0], bot[0], t), lerp(top[1], bot[1], t), lerp(top[2], bot[2], t))

def inside_triangle(px, py, ax, ay, bx, by, cx, cy):
    # Barycentric technique
    v0x, v0y = cx - ax, cy - ay
    v1x, v1y = bx - ax, by - ay
    v2x, v2y = px - ax, py - ay
    dot00 = v0x*v0x + v0y*v0y
    dot01 = v0x*v1x + v0y*v1y
    dot02 = v0x*v2x + v0y*v2y
    dot11 = v1x*v1x + v1y*v1y
    dot12 = v1x*v2x + v1y*v2y
    denom = (dot00 * dot11 - dot01 * dot01)
    if denom == 0:
        return False
    inv = 1.0 / denom
    u = (dot11 * dot02 - dot01 * dot12) * inv
    v = (dot00 * dot12 - dot01 * dot02) * inv
    return (u >= 0) and (v >= 0) and (u + v <= 1)

def draw_icon():
    # Build raw RGB buffer with PNG scanline filter bytes
    rows = []
    cx, cy_top = W//2, 430
    r = 260
    # Triangle base near middle, apex toward bottom
    ax, ay = cx - int(r*0.70), cy_top + int(r*0.35)
    bx, by = cx + int(r*0.70), cy_top + int(r*0.35)
    tx, ty = cx, 820

    # Precompute for speed
    r2 = r*r
    highlight_cx, highlight_cy, highlight_r2 = cx - 130, cy_top - 150, 90*90

    for y in range(H):
        row = bytearray([0])  # filter byte
        br, bg, bb = bg_color(y)
        for x in range(W):
            # Background gradient
            r0, g0, b0 = br, bg, bb

            # Water drop mask: circle cap + triangle tail
            dx = x - cx
            dy = y - cy_top
            in_cap = (dy <= int(r*0.35)) and (dx*dx + dy*dy <= r2)
            in_tail = inside_triangle(x, y, ax, ay, bx, by, tx, ty)
            if in_cap or in_tail:
                r0, g0, b0 = 255, 255, 255
            else:
                # subtle radial highlight on background
                hx = x - highlight_cx
                hy = y - highlight_cy
                if hx*hx + hy*hy <= highlight_r2:
                    r0 = min(255, int(r0*1.10 + 20))
                    g0 = min(255, int(g0*1.10 + 20))
                    b0 = min(255, int(b0*1.10 + 20))
            row += bytes((r0, g0, b0))
        rows.append(bytes(row))
    return b"".join(rows)

def png_from_raw(raw: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    ihdr = struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)  # 8-bit, RGB
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    raw = draw_icon()
    png = png_from_raw(raw)
    OUT.write_bytes(png)
    print(f"Wrote {OUT.resolve()}")

if __name__ == '__main__':
    main()

