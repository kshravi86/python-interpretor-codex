#!/usr/bin/env python3
"""
Prepare App Store screenshots by scaling and padding images to exact device sizes.

Default:
  - Reads from: attachments
  - Outputs:
      attachments/export-6p7       -> 1284 x 2778 (iPhone 6.7")
      attachments/export-6p5       -> 1242 x 2688 (iPhone 6.5")
      attachments/export-ipad13a   -> 2064 x 2752 (iPad 13" accepted)
      attachments/export-ipad13b   -> 2048 x 2732 (iPad 13" accepted)

Usage:
  python scripts/prepare_app_store_screenshots.py \
      --source attachments \
      --out67 attachments/export-6p7 \
      --out65 attachments/export-6p5 \
      --outi13a attachments/export-ipad13a \
      --outi13b attachments/export-ipad13b \
      --bg #FFFFFF

Requires:
  pip install Pillow
"""

import argparse
import os
from pathlib import Path
from typing import Tuple

try:
    from PIL import Image, ImageColor
except ImportError:  # pragma: no cover
    raise SystemExit("Pillow not installed. Run: pip install Pillow")


# App Store currently accepts these iPhone sizes:
#  - 6.7" portrait: 1284 x 2778
#  - 6.5" portrait: 1242 x 2688
SIZE_67 = (1284, 2778)
SIZE_65 = (1242, 2688)
SIZE_IPAD13_A = (2064, 2752)
SIZE_IPAD13_B = (2048, 2732)
VALID_EXT = {".png", ".jpg", ".jpeg"}


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Prepare App Store screenshots (scale+pad)")
    p.add_argument("--source", default="attachments", help="Input folder with images (default: attachments)")
    p.add_argument("--out67", default=os.path.join("attachments", "export-6p7"), help="Output folder for 6.7\" (1290x2796)")
    p.add_argument("--out65", default=os.path.join("attachments", "export-6p5"), help="Output folder for 6.5\" (1242x2688)")
    p.add_argument("--outi13a", default=os.path.join("attachments", "export-ipad13a"), help="Output folder for iPad 13\" (2064x2752)")
    p.add_argument("--outi13b", default=os.path.join("attachments", "export-ipad13b"), help="Output folder for iPad 13\" (2048x2732)")
    p.add_argument("--bg", default="#FFFFFF", help="Background hex color for padding, e.g. #FFFFFF")
    return p.parse_args()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def scale_and_pad(img: Image.Image, target: Tuple[int, int], bg_color: Tuple[int, int, int]) -> Image.Image:
    tw, th = target
    iw, ih = img.size
    scale = min(tw / iw, th / ih)
    nw, nh = int(round(iw * scale)), int(round(ih * scale))
    img_r = img.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGB", (tw, th), bg_color)
    x = (tw - nw) // 2
    y = (th - nh) // 2
    canvas.paste(img_r, (x, y))
    return canvas


def main() -> None:
    args = parse_args()
    src = Path(args.source)
    out67 = Path(args.out67)
    out65 = Path(args.out65)
    outi13a = Path(args.outi13a)
    outi13b = Path(args.outi13b)

    # Resolve relative paths from current working directory
    src = src if src.is_absolute() else (Path.cwd() / src)
    out67 = out67 if out67.is_absolute() else (Path.cwd() / out67)
    out65 = out65 if out65.is_absolute() else (Path.cwd() / out65)

    if not src.exists():
        raise SystemExit(f"Source folder not found: {src}")

    try:
        bg = ImageColor.getrgb(args.bg)
    except ValueError as e:
        raise SystemExit(f"Invalid background color '{args.bg}': {e}")

    ensure_dir(out67)
    ensure_dir(out65)
    ensure_dir(outi13a)
    ensure_dir(outi13b)

    print("Preparing App Store screenshots...")
    print(f" Source:    {src}")
    print(f" Output 6.7: {out67} ({SIZE_67[0]}x{SIZE_67[1]})")
    print(f" Output 6.5: {out65} ({SIZE_65[0]}x{SIZE_65[1]})")
    print(f" Output iPad13 A: {outi13a} ({SIZE_IPAD13_A[0]}x{SIZE_IPAD13_A[1]})")
    print(f" Output iPad13 B: {outi13b} ({SIZE_IPAD13_B[0]}x{SIZE_IPAD13_B[1]})")
    print(f" Background: {args.bg}")

    images = [p for p in src.iterdir() if p.is_file() and p.suffix.lower() in VALID_EXT]
    if not images:
        print("No images found (png/jpg/jpeg).")
        return

    processed = 0
    for p in images:
        print(f"Processing {p.name}...")
        try:
            with Image.open(p) as im:
                # Convert to RGB to avoid mode issues
                im = im.convert("RGB")
                out_img_67 = scale_and_pad(im, SIZE_67, bg)
                out_img_65 = scale_and_pad(im, SIZE_65, bg)
                out_img_67.save(out67 / p.name, format="PNG")
                out_img_65.save(out65 / p.name, format="PNG")
                # iPad 13-inch variants
                out_img_i13a = scale_and_pad(im, SIZE_IPAD13_A, bg)
                out_img_i13b = scale_and_pad(im, SIZE_IPAD13_B, bg)
                out_img_i13a.save(outi13a / p.name, format="PNG")
                out_img_i13b.save(outi13b / p.name, format="PNG")
            processed += 1
        except Exception as e:  # pragma: no cover
            print(f"  ! Skipping {p.name}: {e}")

    print(f"Done. Processed {processed} image(s).")
    print(" Outputs:")
    print(f"  - {out67} (6.7-inch)")
    print(f"  - {out65} (6.5-inch)")
    print(f"  - {outi13a} (iPad 13-inch 2064x2752)")
    print(f"  - {outi13b} (iPad 13-inch 2048x2732)")


if __name__ == "__main__":
    main()
