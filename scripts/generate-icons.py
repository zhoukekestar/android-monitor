#!/usr/bin/env python3
"""Generate launcher icons for AndroidReceiver and macOS Host app.

Design: rounded teal square (project accent #37C0A4), white phone outline,
play triangle inside the screen, broadcast arcs above to signal remote view.

Outputs:
  AndroidReceiver/app/src/main/res/
    mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png
    mipmap-{...}/ic_launcher_round.png
    mipmap-anydpi-v26/ic_launcher.xml
    mipmap-anydpi-v26/ic_launcher_round.xml
    drawable/ic_launcher_foreground.png  (432x432, used by adaptive icon)
    values/ic_launcher_background.xml    (background color)
  MacHost/Resources/AppIcon.icns
"""

from __future__ import annotations

import math
import os
import shutil
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = ROOT / "AndroidReceiver" / "app" / "src" / "main" / "res"
MAC_RESOURCES = ROOT / "MacHost" / "Resources"

ACCENT_TOP = (0x55, 0xD8, 0xBC)   # lighter teal (top of gradient)
ACCENT_BOT = (0x1B, 0x8C, 0x73)   # darker teal (bottom of gradient)
ACCENT     = (0x37, 0xC0, 0xA4)   # base accent
WHITE      = (255, 255, 255, 255)


def gradient_bg(size: int) -> Image.Image:
    """Vertical teal gradient at full size."""
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = bg.load()
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(ACCENT_TOP[0] * (1 - t) + ACCENT_BOT[0] * t)
        g = int(ACCENT_TOP[1] * (1 - t) + ACCENT_BOT[1] * t)
        b = int(ACCENT_TOP[2] * (1 - t) + ACCENT_BOT[2] * t)
        for x in range(size):
            px[x, y] = (r, g, b, 255)
    return bg


def draw_mark(canvas: Image.Image, *, scale: float = 1.0) -> None:
    """Draw the white phone-with-play mark, centered on `canvas`.

    `scale` shrinks the mark relative to the canvas (e.g., 0.66 for adaptive
    icon foregrounds where the launcher applies an additional safe-zone crop).
    """
    s = canvas.size[0]
    cx, cy = s / 2, s / 2
    # Phone body — biased downward so the broadcast arcs above stay inside
    # the rounded-square mask.
    pw = s * 0.42 * scale
    ph = s * 0.58 * scale
    line_w = max(2, int(s * 0.030 * scale))
    pr = s * 0.07 * scale
    px0, py0 = cx - pw / 2, cy - ph / 2 + s * 0.09 * scale
    px1, py1 = px0 + pw, py0 + ph

    # Mark layer (so soft glow sits on top of bg without bleeding past mask)
    mark = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    md = ImageDraw.Draw(mark)

    # Phone outline
    md.rounded_rectangle((px0, py0, px1, py1), radius=pr, outline=WHITE, width=line_w)

    # Speaker grill (top bezel detail)
    grill_w = pw * 0.18
    grill_h = max(2, int(s * 0.012 * scale))
    gx = cx - grill_w / 2
    gy = py0 + s * 0.035 * scale
    md.rounded_rectangle((gx, gy, gx + grill_w, gy + grill_h), radius=grill_h / 2, fill=WHITE)

    # Inner screen (white fill)
    inset = line_w + max(2, int(s * 0.005 * scale))
    bezel_top = s * 0.075 * scale
    bezel_bot = s * 0.075 * scale
    sx0 = px0 + inset
    sy0 = py0 + bezel_top
    sx1 = px1 - inset
    sy1 = py1 - bezel_bot
    md.rounded_rectangle((sx0, sy0, sx1, sy1), radius=pr * 0.55, fill=WHITE)

    # Play triangle inside screen
    scx = (sx0 + sx1) / 2
    scy = (sy0 + sy1) / 2
    tw = (sx1 - sx0) * 0.40
    th = (sy1 - sy0) * 0.36
    triangle = [
        (scx - tw * 0.35, scy - th / 2),
        (scx - tw * 0.35, scy + th / 2),
        (scx + tw * 0.55, scy),
    ]
    md.polygon(triangle, fill=ACCENT)

    # Broadcast arcs above the phone (two concentric arcs)
    arc_cx = cx
    arc_cy = py0 - s * 0.01 * scale
    arc_w = max(2, int(s * 0.022 * scale))
    for radius_factor in (0.14, 0.23):
        rad = s * radius_factor * scale
        bbox = (arc_cx - rad, arc_cy - rad, arc_cx + rad, arc_cy + rad)
        md.arc(bbox, start=215, end=325, fill=WHITE, width=arc_w)

    canvas.alpha_composite(mark)


def render_icon(size: int, *, rounded: bool = True, full_bleed: bool = False,
                mark_scale: float = 1.0) -> Image.Image:
    """Render a complete icon at `size`x`size`.

    rounded: apply rounded-square mask (for legacy launcher / mac).
    full_bleed: skip rounded mask (used by adaptive-icon background fills).
    mark_scale: shrink the foreground mark (e.g., 0.66 for adaptive foregrounds).
    """
    img = gradient_bg(size)
    if rounded and not full_bleed:
        radius = int(size * 0.22)
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), radius=radius, fill=255)
        img.putalpha(mask)
    elif full_bleed:
        # Keep alpha=255 everywhere
        pass
    draw_mark(img, scale=mark_scale)
    return img


def render_round(size: int, *, mark_scale: float = 1.0) -> Image.Image:
    img = gradient_bg(size)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size, size), fill=255)
    img.putalpha(mask)
    draw_mark(img, scale=mark_scale)
    return img


def render_adaptive_foreground(size: int = 432) -> Image.Image:
    """Foreground layer for adaptive icon. The launcher only guarantees the
    inner ~66% (264/432) is visible after masking, so the mark is shrunk to fit.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw_mark(img, scale=0.66)
    return img


# ---------------- Android ----------------

ANDROID_DENSITIES = {
    "mdpi":    48,
    "hdpi":    72,
    "xhdpi":   96,
    "xxhdpi":  144,
    "xxxhdpi": 192,
}

def write_android() -> None:
    print("==> Generating Android launcher icons")
    for density, size in ANDROID_DENSITIES.items():
        out_dir = ANDROID_RES / f"mipmap-{density}"
        out_dir.mkdir(parents=True, exist_ok=True)
        render_icon(size).save(out_dir / "ic_launcher.png", "PNG")
        render_round(size).save(out_dir / "ic_launcher_round.png", "PNG")
        print(f"   {density}: {size}px")

    # Adaptive icon: full-bleed background (gradient teal) + foreground mark.
    # We render the background as a PNG so the gradient is preserved (an
    # adaptive-icon <background> can only be a color or drawable, and using a
    # gradient drawable is heavier than just shipping the bitmap).
    adaptive_bg_dir = ANDROID_RES / "drawable"
    adaptive_bg_dir.mkdir(parents=True, exist_ok=True)
    bg = gradient_bg(432)  # 108dp @ xxxhdpi
    bg.save(adaptive_bg_dir / "ic_launcher_background.png", "PNG")
    fg = render_adaptive_foreground(432)
    fg.save(adaptive_bg_dir / "ic_launcher_foreground.png", "PNG")
    print("   drawable/ic_launcher_{background,foreground}.png: 432px")

    # Adaptive icon XMLs (API 26+)
    anydpi_dir = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi_dir.mkdir(parents=True, exist_ok=True)
    adaptive_xml = (
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@drawable/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '</adaptive-icon>\n'
    )
    (anydpi_dir / "ic_launcher.xml").write_text(adaptive_xml)
    (anydpi_dir / "ic_launcher_round.xml").write_text(adaptive_xml)
    print("   mipmap-anydpi-v26/ic_launcher{,_round}.xml")


# ---------------- Mac ----------------

MAC_ICONSET_SPECS = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

def _macos_canvas(master: Image.Image, size: int) -> Image.Image:
    """Inset the rendered icon and add a soft contact shadow, mac-style."""
    inner = max(8, int(size * 0.82))
    offset = (size - inner) // 2
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if size >= 64:
        shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        sd = ImageDraw.Draw(shadow)
        radius = int(inner * 0.22)
        drop = max(1, size // 64)
        sd.rounded_rectangle(
            (offset, offset + drop, offset + inner, offset + inner + drop),
            radius=radius,
            fill=(0, 0, 0, 90),
        )
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, size / 80)))
        canvas.alpha_composite(shadow)
    icon = master.resize((inner, inner), Image.LANCZOS)
    canvas.alpha_composite(icon, dest=(offset, offset))
    return canvas


def write_mac() -> None:
    print("==> Generating macOS app icon")
    MAC_RESOURCES.mkdir(parents=True, exist_ok=True)
    iconset_dir = MAC_RESOURCES / "AppIcon.iconset"
    if iconset_dir.exists():
        shutil.rmtree(iconset_dir)
    iconset_dir.mkdir(parents=True)

    # Render once at high resolution; downscale per-size via LANCZOS so small
    # icons (16/32) don't break the mark's geometry.
    master = render_icon(1024)
    for name, size in MAC_ICONSET_SPECS:
        canvas = _macos_canvas(master, size)
        canvas.save(iconset_dir / name, "PNG")
        print(f"   {name}: {size}px")

    icns_path = MAC_RESOURCES / "AppIcon.icns"
    print(f"==> Compiling {icns_path.name} via iconutil")
    subprocess.run(
        ["iconutil", "--convert", "icns", str(iconset_dir), "--output", str(icns_path)],
        check=True,
    )
    # iconset folder is intermediate; remove to keep the repo tidy.
    shutil.rmtree(iconset_dir)


def main() -> None:
    write_android()
    write_mac()
    print("[OK] icons generated")


if __name__ == "__main__":
    main()
