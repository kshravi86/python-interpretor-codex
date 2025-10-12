#!/usr/bin/env python3
"""
Generate and populate AppIcon.appiconset with a quiz-list icon:
single white card with 4 answer lines (one selected) on blue gradient.

Cross-platform, stdlib only. Reads Contents.json and writes all sizes with
filenames AppIcon_quizlist_*.png
"""
import json
from pathlib import Path
import struct, zlib

APPICON_DIR = Path("NotesApp/Assets.xcassets/AppIcon.appiconset")
CONTENTS = APPICON_DIR / "Contents.json"


def px_from(size_str: str, scale_str: str) -> int:
    base = int(float(size_str.split('x')[0]))
    scale = int(scale_str.replace('x', ''))
    return base * scale


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    import zlib as _z
    return len(data).to_bytes(4, 'big') + tag + data + (_z.crc32(tag + data) & 0xffffffff).to_bytes(4, 'big')


def _png_from_raw(w: int, h: int, raw: bytes) -> bytes:
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    idat = zlib.compress(raw, 9)
    return b"\x89PNG\r\n\x1a\n" + _png_chunk(b'IHDR', ihdr) + _png_chunk(b'IDAT', idat) + _png_chunk(b'IEND', b'')


def _bg(y, H):
    top = (7, 164, 234)
    bot = (37, 99, 235)
    t = y / (H - 1)
    return (
        int(top[0] + (bot[0] - top[0]) * t),
        int(top[1] + (bot[1] - top[1]) * t),
        int(top[2] + (bot[2] - top[2]) * t),
    )


def _in_round_rect(x, y, rx, ry, rw, rh, r):
    # Clamp to inner rect and check distance to corner circle
    nx = min(max(x, rx + r), rx + rw - r)
    ny = min(max(y, ry + r), ry + rh - r)
    dx, dy = x - nx, y - ny
    return (dx*dx + dy*dy) <= r*r


def _render_list(px: int) -> bytes:
    W = H = float(px)
    raw_rows = []
    # Card rect normalized from 180px prototype
    rx = 0.133 * W
    ry = 0.167 * H
    rw = 0.733 * W
    rh = 0.667 * H
    rr = 0.089 * W

    # Four options rows
    gap = 0.133 * H  # ~24px at 180
    start = ry + 0.111 * H
    # Thicker answer lines and larger selection dots for better contrast
    pill_half = max(2.0, 0.024 * H)
    dot_r_sel = max(4.0, 0.040 * W)
    dot_r = max(3.5, 0.030 * W)

    for yi in range(int(H)):
        row = bytearray([0])
        br, bg, bb = _bg(yi, int(H))
        for xi in range(int(W)):
            r0, g0, b0 = br, bg, bb
            in_card = _in_round_rect(xi, yi, rx, ry, rw, rh, rr)
            if in_card:
                r0, g0, b0 = 255, 255, 255
                # Subtle 1px border to enhance separation from background
                in_outer = _in_round_rect(xi, yi, rx - 1, ry - 1, rw + 2, rh + 2, rr + 1)
                in_inner = _in_round_rect(xi, yi, rx + 1, ry + 1, rw - 2, rh - 2, rr - 1)
                if in_outer and not in_inner:
                    r0, g0, b0 = 220, 226, 240
                for i in range(4):
                    cy = start + i * gap
                    selected = (i == 1)
                    # radio dot
                    dx = xi - (rx + 0.089 * W)
                    dy = yi - cy
                    rdot = dot_r_sel if selected else dot_r
                    if dx*dx + dy*dy <= rdot*rdot:
                        if selected:
                            r0, g0, b0 = 52, 199, 89
                        else:
                            r0, g0, b0 = 190, 196, 210
                    # answer pill line
                    lx0 = rx + 0.167 * W
                    lx1 = rx + rw - 0.067 * W
                    if abs(yi - cy) <= pill_half and lx0 <= xi <= lx1:
                        if selected:
                            # darker gray for contrast
                            r0, g0, b0 = 190, 196, 210
                        else:
                            r0, g0, b0 = 210, 215, 228
            row += bytes((int(r0), int(g0), int(b0)))
        raw_rows.append(bytes(row))
    return b"".join(raw_rows)


def main():
    if not CONTENTS.exists():
        raise SystemExit(f"AppIcon Contents.json not found at {CONTENTS}")
    data = json.loads(CONTENTS.read_text())
    images = data.get('images', [])
    changed = False
    for item in images:
        size = item.get('size')
        scale = item.get('scale')
        idiom = item.get('idiom', 'iphone')
        if not size or not scale:
            continue
        if idiom == 'ios-marketing':
            filename = 'AppIcon_quizlist_1024.png'
            px = 1024
        else:
            scale_tag = '' if scale == '1x' else f"@{scale}"
            filename = f"AppIcon_quizlist_{idiom}_{size}{scale_tag}.png".replace(' ', '')
            px = px_from(size, scale)
        out = APPICON_DIR / filename
        out.parent.mkdir(parents=True, exist_ok=True)
        png = _png_from_raw(px, px, _render_list(px))
        out.write_bytes(png)
        if item.get('filename') != filename:
            item['filename'] = filename
            changed = True
    if changed:
        CONTENTS.write_text(json.dumps(data, indent=2))
    print(f"Generated quiz list icons in {APPICON_DIR}")


if __name__ == '__main__':
    main()
