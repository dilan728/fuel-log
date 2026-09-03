#!/usr/bin/env python3
"""Draws the Plate app icon.

The icon is generated rather than drawn by hand so it stays honest to the design
system: the same paper, the same ember, the same hairline as the app itself, and a
one-line change if any of them move. Everything is laid out on a 1024 grid and
rendered at 4x, then filtered down — the curve of the bowl has to survive being shown
at 40pt, and that only happens with real supersampling.

Usage:  python3 tools/make_icon.py [--preview]
"""

from __future__ import annotations

import argparse
import os
from PIL import Image, ImageDraw

SIDE = 1024
SS = 4                      # supersample factor
S = SIDE * SS

PAPER      = (0xFA, 0xF7, 0xF2, 255)
EMBER      = (0xC8, 0x45, 0x1F, 255)
EMBER_DARK = (0xFF, 0x6B, 0x3D, 255)

# Geometry, in 1024-grid units.
#
# The bowl is a circle cut by its rim line, which is what a bowl actually is when you
# look at one from the side. The lip is a separate flared bar, a touch wider than the
# cut: without it the shape reads as a half-disc, and with it the eye immediately
# supplies the inside of a bowl.
# The rim line cuts the circle *above* its centre, which is what makes this a bowl
# rather than a half-disc: the walls come up and lean in. Cut at the centre and the
# shape is 2.4 times wider than deep, which on a home screen looks like a dish left
# in a drawer.
#
# The lip overhangs by 30 units on each side, which is far more than looks necessary
# at 1024. It is not: at 40pt that overhang is a single pixel of extra width, and it
# is the only thing separating a bowl from a plain half-disc. Sized against a 40pt
# render, not against the artwork.
BOWL_CX, BOWL_CY, BOWL_R = 512, 344, 346
RIM_Y = 330
LIP_HALF_WIDTH = 376
LIP_TOP, LIP_BOTTOM = 306, 354

# The mark sits a little above centre. Its mass is in the round bottom, so centring it
# arithmetically makes it look like it has slipped down the frame.


def _scaled(box):
    return [v * SS for v in box]


def draw_mark(mark_color, background):
    """Renders one appearance. `background` may be None for a transparent field."""
    canvas = Image.new("RGBA", (S, S), background or (0, 0, 0, 0))

    # The bowl, as a mask so the rim cut has the same antialiased edge as the curve.
    mask = Image.new("L", (S, S), 0)
    pen = ImageDraw.Draw(mask)
    pen.ellipse(_scaled([BOWL_CX - BOWL_R, BOWL_CY - BOWL_R,
                         BOWL_CX + BOWL_R, BOWL_CY + BOWL_R]), fill=255)
    pen.rectangle(_scaled([0, 0, SIDE, RIM_Y]), fill=0)
    pen.rounded_rectangle(_scaled([BOWL_CX - LIP_HALF_WIDTH, LIP_TOP,
                                   BOWL_CX + LIP_HALF_WIDTH, LIP_BOTTOM]),
                          radius=(LIP_BOTTOM - LIP_TOP) / 2 * SS, fill=255)

    bowl = Image.new("RGBA", (S, S), mark_color)
    canvas = Image.alpha_composite(canvas, Image.composite(
        bowl, Image.new("RGBA", (S, S), (0, 0, 0, 0)), mask))

    return canvas.resize((SIDE, SIDE), Image.LANCZOS)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default=None)
    parser.add_argument("--preview", action="store_true",
                        help="also write a sheet at real home-screen sizes")
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = args.out or os.path.join(
        root, "Plate", "Plate", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out, exist_ok=True)

    variants = {
        # Light: the printed page. Opaque, because iOS gives a light icon no ground.
        "icon-light.png": draw_mark(EMBER, PAPER),
        # Dark and tinted are composited over the system's own ground, so they carry
        # alpha and no field of their own.
        "icon-dark.png": draw_mark(EMBER_DARK, None),
        "icon-tinted.png": draw_mark((255, 255, 255, 255), None),
    }

    for name, image in variants.items():
        # The light icon ships without an alpha channel — iOS rejects a primary app
        # icon that has one. Dark and tinted are composited over a system-drawn
        # ground, so they keep theirs.
        if name == "icon-light.png":
            image = image.convert("RGB")
        image.save(os.path.join(out, name))
        print(f"wrote {name}")

    if args.preview:
        sheet = Image.new("RGB", (1180, 340), (0x1A, 0x19, 0x18))
        x = 40
        for image in variants.values():
            flat = Image.alpha_composite(
                Image.new("RGBA", image.size, (0x1A, 0x19, 0x18, 255)), image)
            for size in (180, 120, 60, 40):
                sheet.paste(flat.resize((size, size), Image.LANCZOS), (x, 40))
                x += size + 18
            x += 26
        path = os.path.join(root, "tools", "icon-preview.png")
        sheet.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
