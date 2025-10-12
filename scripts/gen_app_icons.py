#!/usr/bin/env python3
import json
from pathlib import Path

import struct, zlib

APPICON_DIR = Path("NotesApp/Assets.xcassets/AppIcon.appiconset")
CONTENTS = APPICON_DIR / "Contents.json"

BG = (46, 125, 246)  # blue
FG = (255, 255, 255)

def px_from(size_str: str, scale_str: str) -> int:
    base = int(float(size_str.split('x')[0]))
    scale = int(scale_str.replace('x', ''))
    return base * scale

def _png_chunk(tag: bytes, data: bytes) -> bytes:
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)

def _solid_png_bytes(w: int, h: int, rgb=(46,125,246)) -> bytes:
    # Create raw scanlines with filter 0
    r, g, b = rgb
    row = bytes([0] + [r, g, b]*w)
    raw = row * h
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)  # 8-bit, truecolor
    idat = zlib.compress(raw, 9)
    png = b"\x89PNG\r\n\x1a\n" + _png_chunk(b'IHDR', ihdr) + _png_chunk(b'IDAT', idat) + _png_chunk(b'IEND', b'')
    return png

def gen_icon(path: Path, px: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(_solid_png_bytes(px, px, BG))

def main():
    if not CONTENTS.exists():
        raise SystemExit(f"AppIcon Contents.json not found at {CONTENTS}")
    data = json.loads(CONTENTS.read_text())
    images = data.get('images', [])
    changed = False
    for item in images:
        idiom = item.get('idiom')
        size = item.get('size')
        scale = item.get('scale')
        if not size or not scale:
            continue
        # decide filename and pixel size
        if idiom == "ios-marketing":
            filename = item.get('filename') or "icon_marketing_1024.png"
            px = 1024
        else:
            scale_tag = '' if scale == '1x' else f"@{scale}"
            # include idiom in filename for clarity and uniqueness
            filename = item.get('filename') or f"icon_{idiom}_{size}{scale_tag}.png".replace(' ', '')
            px = px_from(size, scale)
        out = APPICON_DIR / filename
        if not out.exists():
            gen_icon(out, px)
        if item.get('filename') != filename:
            item['filename'] = filename
            changed = True
    if changed:
        CONTENTS.write_text(json.dumps(data, indent=2))

if __name__ == "__main__":
    main()
