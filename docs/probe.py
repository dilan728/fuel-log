#!/usr/bin/env python3
"""Pixel-level layout audit.

Screenshots are easy to eyeball and hard to judge. This turns one into numbers:
where content actually starts and stops, how big the gaps between things are, and
whether the left edges of stacked elements agree. Misalignment of two or three points
is invisible to the eye at a glance and glaring once it is in a column of integers.
"""
import sys, math
from PIL import Image
import numpy as np

def load(path, scale=3):
    im = Image.open(path).convert("RGB")
    a = np.asarray(im).astype(np.float32)
    return im, a, scale

def bg_color(a):
    # The most common colour in the outer margins is the page ground.
    edges = np.concatenate([a[:, :12].reshape(-1, 3), a[:, -12:].reshape(-1, 3)])
    vals, counts = np.unique(edges.astype(np.uint8).reshape(-1, 3), axis=0, return_counts=True)
    return vals[counts.argmax()].astype(np.float32)

def ink_mask(a, bg, tol=6.0):
    return np.linalg.norm(a - bg, axis=2) > tol

def bands(mask, min_gap=2):
    """Contiguous rows that contain ink, as (top, bottom) pairs."""
    rows = mask.any(axis=1)
    out, start = [], None
    for y, on in enumerate(rows):
        if on and start is None:
            start = y
        elif not on and start is not None:
            if y - start >= min_gap:
                out.append((start, y - 1))
            start = None
    if start is not None:
        out.append((start, len(rows) - 1))
    return out

def report(path, scale=3, top=None, bottom=None):
    im, a, scale = load(path, scale)
    h, w, _ = a.shape
    top = top or 0
    bottom = bottom or h
    a = a[top:bottom]
    bg = bg_color(a)
    mask = ink_mask(a, bg)

    print(f"{path}  {w}x{h}px  ({w/scale:.0f}x{h/scale:.0f}pt @{scale}x)")
    print(f"ground rgb {tuple(int(c) for c in bg)}")
    print()
    print(f"{'band(pt)':>16} {'height':>7} {'gap↑':>6} {'left':>7} {'right':>7}  content")
    print("-" * 78)

    previous_bottom = None
    for (y0, y1) in bands(mask):
        xs = np.where(mask[y0:y1 + 1].any(axis=0))[0]
        left, right = xs.min(), xs.max()
        gap = "" if previous_bottom is None else f"{(y0 - previous_bottom - 1)/scale:.1f}"
        previous_bottom = y1
        # A crude descriptor: how much of the band's width is inked.
        density = mask[y0:y1 + 1].mean()
        kind = "rule" if (y1 - y0) < scale else ("block" if density > 0.35 else "text/art")
        print(f"{(y0+top)/scale:7.1f}–{(y1+top)/scale:6.1f} {(y1-y0+1)/scale:7.1f} {gap:>6} "
              f"{left/scale:7.1f} {right/scale:7.1f}  {kind}")

def columns(path, scale=3, top=0, bottom=None):
    """Left edges of ink for each band — the alignment check."""
    im, a, scale = load(path, scale)
    h = a.shape[0]
    bottom = bottom or h
    a = a[top:bottom]
    bg = bg_color(a)
    mask = ink_mask(a, bg)
    lefts = {}
    for (y0, y1) in bands(mask):
        xs = np.where(mask[y0:y1 + 1].any(axis=0))[0]
        lefts.setdefault(round(xs.min() / scale, 1), []).append(round((y0 + top) / scale, 1))
    print("left edge (pt) -> bands starting there")
    for x in sorted(lefts):
        print(f"  {x:7.1f}  {lefts[x]}")

def zoom(path, x, y, w, h, out, factor=6, scale=3):
    im = Image.open(path).convert("RGB")
    box = (int(x*scale), int(y*scale), int((x+w)*scale), int((y+h)*scale))
    im.crop(box).resize((int(w*scale*factor/3), int(h*scale*factor/3)), Image.NEAREST).save(out)
    print("wrote", out)

def contrast(path, x, y, scale=3):
    """WCAG contrast between the darkest and lightest pixel in a small patch."""
    im, a, scale = load(path, scale)
    patch = a[int(y*scale):int((y+12)*scale), int(x*scale):int((x+120)*scale)] / 255.0
    def lum(c):
        c = np.where(c <= 0.03928, c/12.92, ((c+0.055)/1.055)**2.4)
        return 0.2126*c[...,0] + 0.7152*c[...,1] + 0.0722*c[...,2]
    l = lum(patch)
    hi, lo = l.max(), l.min()
    print(f"contrast {(hi+0.05)/(lo+0.05):.2f}:1")

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "report":
        report(sys.argv[2], top=int(sys.argv[3]) if len(sys.argv) > 3 else None,
               bottom=int(sys.argv[4]) if len(sys.argv) > 4 else None)
    elif cmd == "columns":
        columns(sys.argv[2])
    elif cmd == "zoom":
        zoom(sys.argv[2], *[float(v) for v in sys.argv[3:7]], sys.argv[7])
    elif cmd == "contrast":
        contrast(sys.argv[2], float(sys.argv[3]), float(sys.argv[4]))
