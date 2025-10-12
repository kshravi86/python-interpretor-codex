#!/usr/bin/env python3
"""
Populate AppIcon.appiconset with rendered hydration-goal icons at all sizes
defined in Contents.json. Cross-platform; no external tools.

Usage: python3 scripts/prepare_app_icons_goal.py
"""
import json
from pathlib import Path
import struct, zlib, math

APPICON_DIR = Path("NotesApp/Assets.xcassets/AppIcon.appiconset")
CONTENTS = APPICON_DIR / "Contents.json"


def px_from(size_str: str, scale_str: str) -> int:
    base = int(float(size_str.split('x')[0]))
    scale = int(scale_str.replace('x', ''))
    return base * scale


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return (
        len(data).to_bytes(4, "big")
        + tag
        + data
        + (zlib.crc32(tag + data) & 0xFFFFFFFF).to_bytes(4, "big")
    )


def _png_from_raw(w: int, h: int, raw: bytes) -> bytes:
    ihdr = struct.pack(
        ">IIBBBBB", w, h, 8, 2, 0, 0, 0  # 8-bit, RGB, no alpha
    )
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", idat) + _png_chunk(b"IEND", b"")


def _render_icon(px: int) -> bytes:
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
        dot00 = v0x * v0x + v0y * v0y
        dot01 = v0x * v1x + v0y * v1y
        dot02 = v0x * v2x + v0y * v2y
        dot11 = v1x * v1x + v1y * v1y
        dot12 = v1x * v2x + v1y * v2y
        denom = (dot00 * dot11 - dot01 * dot01)
        if denom == 0:
            return False
        inv = 1.0 / denom
        u = (dot11 * dot02 - dot01 * dot12) * inv
        v = (dot00 * dot12 - dot01 * dot02) * inv
        return (u >= 0) and (v >= 0) and (u + v <= 1)

    def dist_to_seg(x, y, x1, y1, x2, y2):
        vx, vy = x2 - x1, y2 - y1
        wx, wy = x - x1, y - y1
        c1 = vx * wx + vy * wy
        if c1 <= 0:
            return math.hypot(x - x1, y - y1)
        c2 = vx * vx + vy * vy
        if c2 <= c1:
            return math.hypot(x - x2, y - y2)
        b = c1 / c2
        bx, by = x1 + b * vx, y1 + b * vy
        return math.hypot(x - bx, y - by)

    cx = W / 2.0
    cy_top = 0.420 * H
    r = 0.254 * W
    ax, ay = cx - 0.70 * r, cy_top + 0.35 * r
    bx, by = cx + 0.70 * r, cy_top + 0.35 * r
    tx, ty = cx, 0.801 * H
    r2 = r * r

    a1 = (0.381 * W, 0.576 * H)
    a2 = (0.459 * W, 0.654 * H)
    b1 = a2
    b2 = (0.635 * W, 0.459 * H)
    thick = 0.0176 * W

    rows = []
    for y in range(int(H)):
        row = bytearray([0])
        br, bg, bb = bg_color(y)
        for x in range(int(W)):
            r0, g0, b0 = br, bg, bb
            dx = x - cx
            dy = y - cy_top
            in_cap = (dy <= 0.35 * r) and (dx * dx + dy * dy <= r2)
            in_tail = inside_triangle(x, y, ax, ay, bx, by, tx, ty)
            in_drop = in_cap or in_tail
            if in_drop:
                r0, g0, b0 = 255, 255, 255
                if in_cap:
                    d = abs((dx * dx + dy * dy) - r2)
                    if d < (0.0215 * W * W):
                        shade = max(0, int(40 - d / (0.000078 * W * W)))
                        r0 = max(0, r0 - shade)
                        g0 = max(0, g0 - shade)
                        b0 = max(0, b0 - shade)
                if (dist_to_seg(x, y, *a1, *a2) < thick) or (
                    dist_to_seg(x, y, *b1, *b2) < thick
                ):
                    r0, g0, b0 = 52, 199, 89
            row += bytes((int(r0), int(g0), int(b0)))
        rows.append(bytes(row))
    return _png_from_raw(W, H, b"".join(rows))


def main():
    if not CONTENTS.exists():
        raise SystemExit(f"AppIcon Contents.json not found at {CONTENTS}")
    data = json.loads(CONTENTS.read_text())
    images = data.get("images", [])
    changed = False
    for item in images:
        size = item.get("size")
        scale = item.get("scale")
        idiom = item.get("idiom", "iphone")
        if not size or not scale:
            continue
        if idiom == "ios-marketing":
            filename = item.get("filename") or "AppIcon_goal_1024.png"
            px = 1024
        else:
            scale_tag = "" if scale == "1x" else f"@{scale}"
            filename = item.get("filename") or f"AppIcon_goal_{idiom}_{size}{scale_tag}.png".replace(" ", "")
            px = px_from(size, scale)
        out = APPICON_DIR / filename
        out.parent.mkdir(parents=True, exist_ok=True)
        png = _render_icon(px)
        out.write_bytes(png)
        if item.get("filename") != filename:
            item["filename"] = filename
            changed = True
    if changed:
        CONTENTS.write_text(json.dumps(data, indent=2))
    print(f"Wrote/updated icons into {APPICON_DIR}")


if __name__ == "__main__":
    main()

