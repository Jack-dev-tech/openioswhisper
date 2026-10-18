#!/usr/bin/env python3
"""Draws the 1024 px app icon: a microphone over sound bars on an indigo gradient.

Usage: python3 scripts/make-icon.py OpenWhisper/Theme/Assets.xcassets/AppIcon.appiconset/AppIcon.png
Needs Pillow (pip install pillow).
"""
import sys
from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # draw large, then downsample for smooth edges
S = SIZE * SCALE


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def main(path):
    top, bottom = (110, 92, 230), (52, 40, 150)
    img = Image.new("RGB", (S, S))
    draw = ImageDraw.Draw(img)
    for y in range(S):
        draw.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))

    white = (255, 255, 255)
    soft = (205, 198, 255)
    cx = S // 2

    # Sound bars either side of the mic.
    bar_w = 46 * SCALE
    for offset, height in [(-350, 200), (-260, 320), (260, 320), (350, 200)]:
        x = cx + offset * SCALE
        h = height * SCALE
        draw.rounded_rectangle([x - bar_w // 2, S * 0.44 - h // 2, x + bar_w // 2, S * 0.44 + h // 2], radius=bar_w // 2, fill=soft)

    # Mic capsule.
    w, h = 230 * SCALE, 400 * SCALE
    top_y = 210 * SCALE
    draw.rounded_rectangle([cx - w // 2, top_y, cx + w // 2, top_y + h], radius=w // 2, fill=white)

    # Mic holder arc, stem and base.
    stroke = 44 * SCALE
    arc_w = 360 * SCALE
    arc_top = 330 * SCALE
    draw.arc([cx - arc_w // 2, arc_top, cx + arc_w // 2, arc_top + 400 * SCALE], start=0, end=180, fill=white, width=stroke)
    stem_top = arc_top + 400 * SCALE - stroke // 2
    draw.rectangle([cx - stroke // 2, stem_top, cx + stroke // 2, stem_top + 110 * SCALE], fill=white)
    base_y = stem_top + 110 * SCALE
    draw.rounded_rectangle([cx - 150 * SCALE, base_y - stroke // 2, cx + 150 * SCALE, base_y + stroke // 2], radius=stroke // 2, fill=white)

    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "AppIcon.png")
