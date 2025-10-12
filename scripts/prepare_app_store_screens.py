#!/usr/bin/env python3
"""
Prepare App Store screenshots at required sizes from existing PNGs.

Inputs:
  - By default, reads PNGs from one level up: ../IMG_*.png
  - You can pass input files/dirs as arguments.

Outputs:
  - images/appstore/6p5  (1242x2688 portrait or 2688x1242 landscape)
  - images/appstore/6p7  (1284x2778 portrait or 2778x1284 landscape)

Requires Pillow.
"""
from pathlib import Path
from PIL import Image
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT_65 = ROOT / 'images' / 'appstore' / '6p5'
OUT_67 = ROOT / 'images' / 'appstore' / '6p7'

TARGETS = [
    (1242, 2688),  # 6.5" portrait
    (1284, 2778),  # 6.7" portrait
]

def crop_to_aspect(img: Image.Image, w: int, h: int) -> Image.Image:
    tw, th = img.size
    target_ratio = w / h
    src_ratio = tw / th
    if src_ratio > target_ratio:
        # too wide -> crop sides
        new_w = int(th * target_ratio)
        x0 = (tw - new_w) // 2
        return img.crop((x0, 0, x0 + new_w, th))
    else:
        # too tall -> crop top/bottom
        new_h = int(tw / target_ratio)
        y0 = (th - new_h) // 2
        return img.crop((0, y0, tw, y0 + new_h))

def process_image(path: Path):
    img = Image.open(path).convert('RGB')
    w, h = img.size
    portrait = h >= w
    for W, H in TARGETS:
        if not portrait:
            W, H = H, W  # landscape rotated
        cropped = crop_to_aspect(img, W, H)
        resized = cropped.resize((W, H), Image.LANCZOS)
        # output paths
        outdir = OUT_65 if (min(W, H) == 1242) else OUT_67
        outdir.mkdir(parents=True, exist_ok=True)
        out = outdir / f"{path.stem}_{W}x{H}.jpg"
        resized.save(out, format='JPEG', quality=95, optimize=True)
        print(f"Wrote {out}")

def main(argv):
    inputs = []
    if len(argv) > 1:
        for a in argv[1:]:
            p = Path(a)
            if p.is_dir():
                inputs += list(p.glob('*.png')) + list(p.glob('*.jpg'))
            elif p.exists():
                inputs.append(p)
    else:
        # default: pull from one level up
        up = ROOT.parent
        inputs = sorted(list(up.glob('IMG_*.png')))
    if not inputs:
        print('No input screenshots found.', file=sys.stderr)
        sys.exit(1)
    for p in inputs:
        try:
            process_image(p)
        except Exception as e:
            print(f"Failed {p}: {e}", file=sys.stderr)
            continue

if __name__ == '__main__':
    main(sys.argv)

