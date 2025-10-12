#!/usr/bin/env python3
"""
Generate a 1024x1024 PNG app icon that communicates hydration + goal:
- Blue vertical gradient background
- White water drop
- Subtle green checkmark inside the drop

Output: branding/app_icon_goal_1024.png
Uses only the Python stdlib so it runs anywhere.
"""
from pathlib import Path
import struct, zlib

W = H = 1024
OUT = Path("branding/app_icon_goal_1024.png")

def lerp(a, b, t):
    return int(a + (b - a) * t)

def bg_color(y):
    # Cyan (#07A4EA) to Blue (#2563EB)
    top = (7, 164, 234)
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

def inside_check(px, py):
    """Simple tick mark polygon inside the drop area.
    The checkmark sits within a ~520x380 box centered horizontally.
    """
    # Define two line segments (thick) forming a check.
    # We approximate thickness using distance to a segment.
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

    # Coordinates tuned for the 1024 canvas
    thick = 18.0
    a1 = (390, 590)
    a2 = (470, 670)
    b1 = (470, 670)
    b2 = (650, 470)
    return (dist_to_seg(px, py, *a1, *a2) < thick) or (dist_to_seg(px, py, *b1, *b2) < thick)

def draw_icon():
    rows = []
    cx, cy_top = W//2, 430
    r = 260
    # Rounded triangle tail by blending circle + triangle as before
    ax, ay = cx - int(r*0.70), cy_top + int(r*0.35)
    bx, by = cx + int(r*0.70), cy_top + int(r*0.35)
    tx, ty = cx, 820

    r2 = r*r

    for y in range(H):
        row = bytearray([0])  # filter byte
        br, bg, bb = bg_color(y)
        for x in range(W):
            r0, g0, b0 = br, bg, bb
            # Water drop shape
            dx = x - cx
            dy = y - cy_top
            in_cap = (dy <= int(r*0.35)) and (dx*dx + dy*dy <= r2)
            in_tail = inside_triangle(x, y, ax, ay, bx, by, tx, ty)
            in_drop = in_cap or in_tail
            if in_drop:
                # Fill white drop
                r0, g0, b0 = 255, 255, 255
                # Draw soft inner shadow near edges for depth
                # compute distance to drop boundary roughly via circle edge
                if in_cap:
                    d = abs((dx*dx + dy*dy) - r2)
                    if d < 2200:  # near edge
                        shade = max(0, 40 - d//80)
                        r0 = max(0, r0 - shade)
                        g0 = max(0, g0 - shade)
                        b0 = max(0, b0 - shade)
                # Checkmark overlay inside drop
                if inside_check(x, y):
                    # System green #34C759
                    r0, g0, b0 = 52, 199, 89
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

