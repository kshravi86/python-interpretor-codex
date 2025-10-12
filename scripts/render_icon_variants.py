#!/usr/bin/env python3
"""
Render 180x180 previews for three minimal app icon variants (std lib only):
 A) Pure white drop on blue gradient
 B) White drop with subtle white progress ring
 C) White drop over subtle concentric target rings

Outputs:
 branding/preview_drop_180.png
 branding/preview_ring_180.png
 branding/preview_target_180.png
"""
from pathlib import Path
import struct, zlib, math

PX = 180
OUT_DIR = Path("branding")


def png_from_raw(w: int, h: int, raw: bytes) -> bytes:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return len(data).to_bytes(4, "big") + tag + data + (zlib.crc32(tag + data) & 0xFFFFFFFF).to_bytes(4, "big")
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')


def grad_bg(y, H):
    top = (7, 164, 234)
    bot = (37, 99, 235)
    t = y / (H - 1)
    return (
        int(top[0] + (bot[0] - top[0]) * t),
        int(top[1] + (bot[1] - top[1]) * t),
        int(top[2] + (bot[2] - top[2]) * t),
    )


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


def render_variant(kind: str, px: int = PX) -> bytes:
    W = H = px
    cx = W / 2.0
    cy_top = 0.415 * H
    r = 0.255 * W
    ax, ay = cx - 0.70 * r, cy_top + 0.35 * r
    bx, by = cx + 0.70 * r, cy_top + 0.35 * r
    tx, ty = cx, 0.80 * H
    r2 = r * r

    rows = []
    for y in range(int(H)):
        row = bytearray([0])
        br, bg, bb = grad_bg(y, H)
        for x in range(int(W)):
            r0, g0, b0 = br, bg, bb

            # Optional subtle target rings for 'target' kind
            if kind == 'target':
                dx0 = x - cx
                dy0 = y - (cy_top + 0.21*r)
                d = (dx0*dx0 + dy0*dy0) ** 0.5
                for rr, strength in ((0.60*r, 0.08), (0.85*r, 0.05)):
                    if abs(d - rr) < 1.0:
                        r0 = min(255, int(r0*(1.0+strength) + 18*strength))
                        g0 = min(255, int(g0*(1.0+strength) + 18*strength))
                        b0 = min(255, int(b0*(1.0+strength) + 18*strength))

            # Drop shape
            dx = x - cx
            dy = y - cy_top
            in_cap = (dy <= 0.35*r) and (dx*dx + dy*dy <= r2)
            in_tail = inside_triangle(x, y, ax, ay, bx, by, tx, ty)
            in_drop = in_cap or in_tail
            if in_drop:
                r0, g0, b0 = 255, 255, 255
                # soft inner edge
                if in_cap:
                    d2 = abs((dx*dx + dy*dy) - r2)
                    if d2 < (0.01 * W * W):
                        shade = max(0, int(30 - d2 / (0.00007 * W * W)))
                        r0 = max(0, r0 - shade)
                        g0 = max(0, g0 - shade)
                        b0 = max(0, b0 - shade)

            # Optional ring around drop for 'ring' kind
            if kind == 'ring':
                dxr = x - cx
                dyr = y - (cy_top + 0.21*r)
                rr = (dxr*dxr + dyr*dyr) ** 0.5
                ring_r = 1.1 * r
                if abs(rr - ring_r) < 1.0:
                    # white ring
                    r0, g0, b0 = 255, 255, 255

            row += bytes((int(r0), int(g0), int(b0)))
        rows.append(bytes(row))
    return b"".join(rows)


def write_png(kind: str, path: Path):
    raw = render_variant(kind, PX)
    png = png_from_raw(PX, PX, raw)
    path.write_bytes(png)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_png('drop', OUT_DIR / 'preview_drop_180.png')
    write_png('ring', OUT_DIR / 'preview_ring_180.png')
    write_png('target', OUT_DIR / 'preview_target_180.png')
    print('Wrote previews to branding/*.png')


if __name__ == '__main__':
    main()

