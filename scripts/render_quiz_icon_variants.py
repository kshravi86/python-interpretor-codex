#!/usr/bin/env python3
"""
Render three quiz-themed 180x180 icon previews using only the stdlib:
 1) cards  - stacked rounded cards with multiple-choice lines
 2) bubble - chat bubble with a question mark
 3) list   - single card with 4 answer pills, one highlighted

Outputs to branding/preview_quiz_*.png
"""
from pathlib import Path
import struct, zlib, math

PX = 180
OUT = Path("branding")


def png_from_raw(w: int, h: int, raw: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return len(data).to_bytes(4, 'big') + tag + data + (zlib.crc32(tag + data) & 0xffffffff).to_bytes(4, 'big')
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')


def bg(y, H):
    top = (7, 164, 234)
    bot = (37, 99, 235)
    t = y / (H - 1)
    return (
        int(top[0] + (bot[0] - top[0]) * t),
        int(top[1] + (bot[1] - top[1]) * t),
        int(top[2] + (bot[2] - top[2]) * t),
    )


def in_round_rect(x, y, rx, ry, rw, rh, r):
    # Rounded rect hit test: clamp then distance to corner radius
    # Compute nearest point on the rectangle with radius r
    nx = min(max(x, rx + r), rx + rw - r)
    ny = min(max(y, ry + r), ry + rh - r)
    dx, dy = x - nx, y - ny
    return (dx*dx + dy*dy) <= r*r


def draw_cards():
    W = H = PX
    raw = []
    # Card metrics
    back = (36, 38, 140, 92)  # x,y,w,h
    front = (24, 30, 140, 100)
    r = 14
    for y in range(H):
        row = bytearray([0])
        br, bgc, bb = bg(y, H)
        for x in range(W):
            r0, g0, b0 = br, bgc, bb
            # Back card subtle
            if in_round_rect(x, y, *back, r):
                r0, g0, b0 = 255, 255, 255
                # subtle shadow
                if in_round_rect(x+1, y+1, *front, r):
                    r0, g0, b0 = 245, 247, 255
            # Front card
            if in_round_rect(x, y, *front, r):
                r0, g0, b0 = 255, 255, 255
                # Draw three MCQ lines + radio dots
                def line(yc, on=False):
                    nonlocal r0, g0, b0
                    ly = yc
                    # radio dot
                    dx = x - (front[0] + 16)
                    dy = y - ly
                    if dx*dx + dy*dy <= (5 if on else 4)**2:
                        if on:
                            r0, g0, b0 = 52, 199, 89  # green selected
                        else:
                            r0, g0, b0 = 210, 215, 230
                    # option pill line
                    lx0 = front[0] + 30
                    lx1 = front[0] + front[2] - 14
                    if abs(y - ly) <= 3 and lx0 <= x <= lx1:
                        c = 230 if not on else 210
                        r0, g0, b0 = c, c, c
                line(front[1] + 28, on=False)
                line(front[1] + 52, on=True)
                line(front[1] + 76, on=False)
            row += bytes((r0, g0, b0))
        raw.append(bytes(row))
    return b"".join(raw)


def draw_bubble_q():
    W = H = PX
    raw = []
    bx, by, bw, bh, brad = 30, 30, 120, 94, 20
    # tail triangle points
    tx1, ty1 = bx + 50, by + bh
    tx2, ty2 = bx + 70, by + bh
    tx3, ty3 = bx + 58, by + bh + 16

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

    # Question mark parameters
    cx, cy = 90, 70
    cr = 24
    thick = 5

    for y in range(H):
        row = bytearray([0])
        brg, bgg, bbg = bg(y, H)
        for x in range(W):
            r0, g0, b0 = brg, bgg, bbg
            in_rect = in_round_rect(x, y, bx, by, bw, bh, brad)
            in_tail = inside_triangle(x, y, tx1, ty1, tx2, ty2, tx3, ty3)
            if in_rect or in_tail:
                r0, g0, b0 = 255, 255, 255
                # draw ? in blue for contrast
                # circular arc (approx top hook)
                dx = x - cx
                dy = y - cy
                dist = math.hypot(dx, dy)
                ang = (math.degrees(math.atan2(dy, dx)) + 360) % 360
                if abs(dist - cr) <= thick and (210 <= ang <= 360 or 0 <= ang <= 60):
                    r0, g0, b0 = 37, 99, 235
                # stem rectangle
                if (cx + 8 >= x >= cx + 2) and (cy + 8 <= y <= cy + 26):
                    r0, g0, b0 = 37, 99, 235
                # dot
                if (x - (cx + 5))**2 + (y - (cy + 36))**2 <= (thick+1)**2:
                    r0, g0, b0 = 37, 99, 235
            row += bytes((r0, g0, b0))
        raw.append(bytes(row))
    return b"".join(raw)


def draw_list():
    W = H = PX
    raw = []
    card = (24, 30, 132, 120)
    r = 16
    for y in range(H):
        row = bytearray([0])
        br, bgc, bb = bg(y, H)
        for x in range(W):
            r0, g0, b0 = br, bgc, bb
            if in_round_rect(x, y, *card, r):
                r0, g0, b0 = 255, 255, 255
                # four answer pills, one highlighted
                for i in range(4):
                    cy = card[1] + 20 + i*24
                    # radio/selection dot
                    dx = x - (card[0] + 16)
                    dy = y - cy
                    selected = (i == 1)
                    rad = 5 if selected else 4
                    if dx*dx + dy*dy <= rad*rad:
                        if selected:
                            r0, g0, b0 = 52, 199, 89
                        else:
                            r0, g0, b0 = 210, 215, 230
                    # answer pill
                    lx0 = card[0] + 30
                    lx1 = card[0] + card[2] - 12
                    if abs(y - cy) <= 3 and lx0 <= x <= lx1:
                        c = 230 if not selected else 210
                        r0, g0, b0 = c, c, c
            row += bytes((r0, g0, b0))
        raw.append(bytes(row))
    return b"".join(raw)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    png = png_from_raw(PX, PX, draw_cards())
    (OUT / 'preview_quiz_cards_180.png').write_bytes(png)
    png = png_from_raw(PX, PX, draw_bubble_q())
    (OUT / 'preview_quiz_bubble_180.png').write_bytes(png)
    png = png_from_raw(PX, PX, draw_list())
    (OUT / 'preview_quiz_list_180.png').write_bytes(png)
    print('Wrote quiz previews to branding/*.png')


if __name__ == '__main__':
    main()

