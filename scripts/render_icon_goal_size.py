#!/usr/bin/env python3
"""
Render the hydration-goal app icon at an arbitrary square size using only
the Python stdlib. Geometry is proportionally scaled from a 1024 base.

Usage: python3 scripts/render_icon_goal_size.py 180 branding/preview.png
"""
from pathlib import Path
import struct, zlib, sys

def png_from_raw(w: int, h: int, raw: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        import zlib as _z
        return (len(data)).to_bytes(4, 'big') + tag + data + (_z.crc32(tag + data) & 0xffffffff).to_bytes(4, 'big')
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')

def render(px: int) -> bytes:
    W = H = px
    def lerp(a, b, t):
        return int(a + (b - a) * t)
    def bg_color(y):
        top = (7, 164, 234)
        bot = (37, 99, 235)
        t = y / (H - 1)
        return (lerp(top[0], bot[0], t), lerp(top[1], bot[1], t), lerp(top[2], bot[2], t))
    def inside_triangle(px, py, ax, ay, bx, by, cx, cy):
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
    import math
    def dist_to_seg(x, y, x1, y1, x2, y2):
        vx, vy = x2 - x1, y2 - y1
        wx, wy = x - x1, y - y1
        c1 = vx*wx + vy*wy
        if c1 <= 0:
            return math.hypot(x - x1, y - y1)
        c2 = vx*vx + vy*vy
        if c2 <= c1:
            return math.hypot(x - x2, y - y2)
        b = c1 / c2
        bx, by = x1 + b*vx, y1 + b*vy
        return math.hypot(x - bx, y - by)

    # Proportional geometry based on 1024 reference
    cx = W/2.0
    cy_top = 0.420 * H
    r = 0.254 * W
    ax, ay = cx - 0.70*r, cy_top + 0.35*r
    bx, by = cx + 0.70*r, cy_top + 0.35*r
    tx, ty = cx, 0.801 * H
    r2 = r*r

    # Check mark segments (normalized from 1024)
    a1 = (0.381*W, 0.576*H)
    a2 = (0.459*W, 0.654*H)
    b1 = a2
    b2 = (0.635*W, 0.459*H)
    thick = 0.0176 * W

    rows = []
    for y in range(int(H)):
        row = bytearray([0])
        br, bg, bb = bg_color(y)
        for x in range(int(W)):
            r0, g0, b0 = br, bg, bb
            dx = x - cx
            dy = y - cy_top
            in_cap = (dy <= 0.35*r) and (dx*dx + dy*dy <= r2)
            in_tail = inside_triangle(x, y, ax, ay, bx, by, tx, ty)
            in_drop = in_cap or in_tail
            if in_drop:
                r0, g0, b0 = 255, 255, 255
                if in_cap:
                    d = abs((dx*dx + dy*dy) - r2)
                    if d < (0.0215*W*W):
                        shade = max(0, int(40 - d/(0.000078*W*W)))
                        r0 = max(0, r0 - shade)
                        g0 = max(0, g0 - shade)
                        b0 = max(0, b0 - shade)
                if (dist_to_seg(x, y, *a1, *a2) < thick) or (dist_to_seg(x, y, *b1, *b2) < thick):
                    r0, g0, b0 = 52, 199, 89
            row += bytes((int(r0), int(g0), int(b0)))
        rows.append(bytes(row))
    return b"".join(rows)

def main():
    if len(sys.argv) < 3:
        print("Usage: render_icon_goal_size.py <px> <out.png>")
        raise SystemExit(2)
    px = int(sys.argv[1])
    out = Path(sys.argv[2])
    out.parent.mkdir(parents=True, exist_ok=True)
    raw = render(px)
    png = png_from_raw(px, px, raw)
    out.write_bytes(png)
    print(f"Wrote {out}")

if __name__ == "__main__":
    main()

