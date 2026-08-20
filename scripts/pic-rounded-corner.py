#!/usr/bin/env python3
"""Add rounded corners to an image.

Usage:
    python rounded_corners.py input.jpg [-r 10] [-o output.png]

Options:
    -r, --radius   corner radius as a percentage (0-50) of the shorter side.
                   Default: 10
    -o, --output   output file path. Default: <input>_rounded.<ext>
"""

import argparse
import os
import sys

from PIL import Image, ImageDraw


def add_rounded_corners(img: Image.Image, radius_pct: float) -> Image.Image:
    """Return a copy of `img` with transparent rounded corners.

    `radius_pct` is the corner radius expressed as a percentage of the
    image's shorter side.
    """
    if radius_pct <= 0:
        return img

    w, h = img.size
    radius = int(min(w, h) * radius_pct / 100.0)
    radius = max(1, min(radius, min(w, h) // 2))

    # Work on RGBA so the cut-away corners become transparent.
    img = img.convert("RGBA")

    # White rounded-rect mask; corners outside the rect stay transparent.
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), (w - 1, h - 1)], radius=radius, fill=255)

    img.putalpha(mask)
    return img


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Add rounded corners to an image."
    )
    parser.add_argument("input", help="path to the input image")
    parser.add_argument(
        "-r",
        "--radius",
        type=float,
        default=10,
        help="corner radius as a percentage (0-50) of the shorter side (default: 10)",
    )
    parser.add_argument(
        "-o",
        "--output",
        default=None,
        help="output file path (default: <input>_rounded.<ext>)",
    )
    args = parser.parse_args()

    if not os.path.isfile(args.input):
        print(f"Error: input file not found: {args.input}", file=sys.stderr)
        return 1

    if not 0 <= args.radius <= 50:
        print("Error: radius must be between 0 and 50", file=sys.stderr)
        return 1

    try:
        with Image.open(args.input) as img:
            result = add_rounded_corners(img, args.radius)

            if args.output:
                out_path = args.output
            else:
                base, _ = os.path.splitext(args.input)
                out_path = f"{base}_rounded.png"

            result.save(out_path)
            print(f"Saved: {out_path} (radius {args.radius}% of shorter side)")
    except Exception as exc:  # noqa: BLE001
        print(f"Error processing image: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
