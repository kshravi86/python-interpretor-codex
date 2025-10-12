#!/usr/bin/env python3
"""
Generate and populate AppIcon.appiconset with a quiz-themed icon:
white chat bubble + question mark on a blue gradient.

Cross-platform, stdlib only. Reads Contents.json and writes all sizes.
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
        ">IIBBBBB", w, h, 8, 2, 0, 0, 0  # 8-bit, RGB
    )
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", idat) + _png_chunk(b"IEND", b"")


def _bg_color(y, H):
    top = (7, 164, 234)
    bot = (37, 99, 235)
    t = y / (H - 1)
    return (
        int(top[0] + (bot[0] - top[0]) * t),
        int(top[1] + (bot[1] - top[1]) * t),
        int(top[2] + (bot[2] - top[2]) * t),
    )


def _in_round_rect(x, y, rx, ry, rw, rh, r):
    nx = min(max(x, rx + r), rx + rw - r)
    ny = min(max(y, ry + r), ry + rh - r)
    dx, dy = x - nx, y - ny
    return (dx * dx + dy * dy) <= r * r


def _render_bubble(px: int) -> bytes:
    W = H = float(px)
    raw_rows = []

    # Bubble metrics relative to size
    bx = 0.167 * W
    by = 0.167 * H
    bw = 0.667 * W
    bh = 0.522 * H
    brad = 0.111 * W
    # Tail
    tx1, ty1 = bx + 0.278 * bw, by + bh
    tx2, ty2 = bx + 0.389 * bw, by + bh
    tx3, ty3 = bx + 0.333 * bw, by + bh + 0.111 * H

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

    # Question mark parameters
    cx = 0.50 * W
    cy = 0.389 * H
    cr = 0.133 * W
    thick = max(2.0, 0.028 * W)

    for yi in range(int(H)):
        row = bytearray([0])
        br, bg, bb = _bg_color(yi, int(H))
        for xi in range(int(W)):
            r0, g0, b0 = br, bg, bb
            in_rect = _in_round_rect(xi, yi, bx, by, bw, bh, brad)
            in_tail = inside_triangle(xi, yi, tx1, ty1, tx2, ty2, tx3, ty3)
            if in_rect or in_tail:
                r0, g0, b0 = 255, 255, 255
                # draw ? in brand blue for clarity
                dx = xi - cx
                dy = yi - cy
                dist = (dx * dx + dy * dy) ** 0.5
                ang = (math.degrees(math.atan2(dy, dx)) + 360.0) % 360.0
                if abs(dist - cr) <= thick and (210.0 <= ang <= 360.0 or 0.0 <= ang <= 60.0):
                    r0, g0, b0 = 37, 99, 235
                if (cx + 0.044 * W >= xi >= cx + 0.011 * W) and (
                    cy + 0.044 * H <= yi <= cy + 0.144 * H
                ):
                    r0, g0, b0 = 37, 99, 235
                if (xi - (cx + 0.027 * W)) ** 2 + (yi - (cy + 0.178 * H)) ** 2 <= (
                    (thick + 1.0) ** 2
                ):
                    r0, g0, b0 = 37, 99, 235
            row += bytes((int(r0), int(g0), int(b0)))
        raw_rows.append(bytes(row))
    return b"".join(raw_rows)


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
            filename = item.get("filename") or "AppIcon_quizbubble_1024.png"
            px = 1024
        else:
            scale_tag = "" if scale == "1x" else f"@{scale}"
            filename = item.get("filename") or f"AppIcon_quizbubble_{idiom}_{size}{scale_tag}.png".replace(" ", "")
            px = px_from(size, scale)
        out = APPICON_DIR / filename
        out.parent.mkdir(parents=True, exist_ok=True)
        png = _png_from_raw(px, px, _render_bubble(px))
        out.write_bytes(png)
        if item.get("filename") != filename:
            item["filename"] = filename
            changed = True
    if changed:
        CONTENTS.write_text(json.dumps(data, indent=2))
    print(f"Generated quiz bubble icons in {APPICON_DIR}")


if __name__ == "__main__":
    main()

