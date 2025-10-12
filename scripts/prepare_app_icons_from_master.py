#!/usr/bin/env python3
import json
import os
import subprocess
from pathlib import Path

APPICON_DIR = Path("NotesApp/Assets.xcassets/AppIcon.appiconset")
CONTENTS = APPICON_DIR / "Contents.json"

def px_from(size_str: str, scale_str: str) -> int:
    base = int(float(size_str.split('x')[0]))
    scale = int(scale_str.replace('x', ''))
    return base * scale

def run(cmd: list):
    subprocess.check_call(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def main():
    # Allow custom path via env or default to branding file in repo
    master = os.environ.get("APP_ICON_MASTER", "branding/app_icon_1024.png")
    master_path = Path(master)
    if not master_path.exists():
        raise SystemExit(
            f"App icon master not found at {master_path}. Provide a finalized 1024x1024 PNG file at this path or set APP_ICON_MASTER to your file."
        )
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
            filename = item.get('filename') or 'AppIcon_1024.png'
            px = 1024
        else:
            scale_tag = '' if scale == '1x' else f"@{scale}"
            filename = item.get('filename') or f"AppIcon_{idiom}_{size}{scale_tag}.png".replace(' ', '')
            px = px_from(size, scale)
        out = APPICON_DIR / filename
        out.parent.mkdir(parents=True, exist_ok=True)
        # Use macOS sips to resize the master icon to required size
        run(["sips", "-s", "format", "png", "-z", str(px), str(px), str(master_path), "--out", str(out)])
        if item.get('filename') != filename:
            item['filename'] = filename
            changed = True

    if changed:
        CONTENTS.write_text(json.dumps(data, indent=2))

if __name__ == "__main__":
    main()

