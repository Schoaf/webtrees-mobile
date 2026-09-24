#!/usr/bin/env python3
"""Stage 2 of the store-screenshot pipeline: composite each raw screen
capture into a polished, store-ready phone-framed mockup.

Stage 1 (a `flutter_test` widget test, not this script) renders real app
screens to raw PNGs at exact store pixel dimensions:

    flutter test test/screenshots/store_screenshots_test.dart \
        --dart-define=RENDER_SCREENSHOTS=true

This script then takes every PNG under screenshots/raw/{ios,android}/ and
writes a composited version to screenshots/store/{ios,android}/ - a dark
phone frame (drawn programmatically, no bundled bezel asset, no network)
around a rounded-corner clip of the screenshot, on a soft gradient
background built from the app's own brand color, at the exact same pixel
dimensions as the raw input (some stores are strict about upload
dimensions even for a "framed" promotional screenshot, so the frame and
background are drawn *within* that canvas rather than added on top of it).

Run:
    python3 tool/compose_store_screenshots.py

Re-run any time after stage 1 produces fresh raw screenshots - both steps
are meant to be repeatable whenever the app's UI changes.
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_DIR = REPO_ROOT / "screenshots" / "raw"
STORE_DIR = REPO_ROOT / "screenshots" / "store"

# lib/theme/app_theme.dart: AppColors.primary - keep this in sync if the
# app's brand color ever changes.
PRIMARY = (0x2F, 0x6F, 0xB0)

# A dark, neutral phone body color - not pure black, reads as a device
# rather than a hole in the image.
PHONE_COLOR = (24, 25, 28)


def _tint(color: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    """Blend `color` toward white by `amount` (0-1)."""
    return tuple(int(c + (255 - c) * amount) for c in color)


def _shade(color: tuple[int, int, int], amount: float) -> tuple[int, int, int]:
    """Blend `color` toward black by `amount` (0-1)."""
    return tuple(int(c * (1 - amount)) for c in color)


def make_background(size: tuple[int, int]) -> Image.Image:
    """A soft diagonal gradient built from the app's own brand blue: a
    light tint at the top-left, through the brand color, to a deeper shade
    at the bottom-right. Built from a 2x2 seed image and resized with
    bicubic interpolation - Pillow blends the corners smoothly, no
    per-pixel loop or numpy dependency needed.
    """
    light = _tint(PRIMARY, 0.35)
    deep = _shade(PRIMARY, 0.35)
    seed = Image.new("RGB", (2, 2))
    seed.putpixel((0, 0), light)
    seed.putpixel((1, 0), PRIMARY)
    seed.putpixel((0, 1), PRIMARY)
    seed.putpixel((1, 1), deep)
    return seed.resize(size, Image.BICUBIC)


def rounded_mask(size: tuple[int, int], radius: float) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255
    )
    return mask


def compose(raw_path: pathlib.Path, canvas_size: tuple[int, int]) -> Image.Image:
    """Composite one raw screenshot into a framed mockup at `canvas_size`
    (the same pixel dimensions the store expects for the upload)."""
    raw = Image.open(raw_path).convert("RGBA")
    canvas_w, canvas_h = canvas_size

    canvas = make_background(canvas_size).convert("RGBA")

    # Phone body: centered, with an even margin around it, sized to the
    # same aspect ratio as the raw screenshot so the screen fills the
    # phone edge-to-edge like a real device photo.
    margin_frac = 0.085
    avail_w = canvas_w * (1 - 2 * margin_frac)
    avail_h = canvas_h * (1 - 2 * margin_frac)
    scale = min(avail_w / raw.width, avail_h / raw.height)
    phone_w = raw.width * scale
    phone_h = raw.height * scale
    phone_x = (canvas_w - phone_w) / 2
    phone_y = (canvas_h - phone_h) / 2

    body_radius = phone_w * 0.11
    bezel = phone_w * 0.028

    # Soft drop shadow under the phone for a bit of depth.
    shadow = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    shadow_offset = phone_h * 0.012
    ImageDraw.Draw(shadow).rounded_rectangle(
        [phone_x, phone_y + shadow_offset, phone_x + phone_w, phone_y + phone_h + shadow_offset],
        radius=body_radius,
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=phone_w * 0.02))
    canvas = Image.alpha_composite(canvas, shadow)

    # Phone body: a rounded-rectangle in a dark neutral color.
    body = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [phone_x, phone_y, phone_x + phone_w, phone_y + phone_h],
        radius=body_radius,
        fill=(*PHONE_COLOR, 255),
    )
    canvas = Image.alpha_composite(canvas, body)

    # Screen: the raw screenshot, resized to fit inside a thin bezel
    # margin, clipped to rounded corners.
    screen_x = phone_x + bezel
    screen_y = phone_y + bezel
    screen_w = phone_w - 2 * bezel
    screen_h = phone_h - 2 * bezel
    screen_radius = max(body_radius - bezel, 1)

    resized = raw.resize((round(screen_w), round(screen_h)), Image.LANCZOS)
    mask = rounded_mask(resized.size, screen_radius)
    screen_layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    screen_layer.paste(resized, (round(screen_x), round(screen_y)), mask)
    canvas = Image.alpha_composite(canvas, screen_layer)

    # Notch: a small centered pill at the top of the screen (Dynamic-Island
    # style), drawn in the phone body color so it reads as a cutout in the
    # screen rather than a sticker on top of the content.
    notch_w = phone_w * 0.26
    notch_h = phone_w * 0.042
    notch_x = phone_x + (phone_w - notch_w) / 2
    notch_y = screen_y + bezel * 0.6
    notch = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    ImageDraw.Draw(notch).rounded_rectangle(
        [notch_x, notch_y, notch_x + notch_w, notch_y + notch_h],
        radius=notch_h / 2,
        fill=(*PHONE_COLOR, 255),
    )
    canvas = Image.alpha_composite(canvas, notch)

    # Flatten to no-alpha for the store upload (Google Play in particular
    # rejects screenshots with an alpha channel).
    return canvas.convert("RGB")


def main() -> None:
    if not RAW_DIR.exists():
        raise SystemExit(
            f"{RAW_DIR} not found - run stage 1 first:\n"
            "  flutter test test/screenshots/store_screenshots_test.dart "
            "--dart-define=RENDER_SCREENSHOTS=true"
        )

    count = 0
    for platform_dir in sorted(p for p in RAW_DIR.iterdir() if p.is_dir()):
        out_dir = STORE_DIR / platform_dir.name
        out_dir.mkdir(parents=True, exist_ok=True)
        for raw_path in sorted(platform_dir.glob("*.png")):
            with Image.open(raw_path) as im:
                size = im.size
            composed = compose(raw_path, size)
            out_path = out_dir / raw_path.name
            composed.save(out_path, "PNG")
            print(f"{raw_path.relative_to(REPO_ROOT)} -> {out_path.relative_to(REPO_ROOT)} ({size[0]}x{size[1]})")
            count += 1

    if count == 0:
        raise SystemExit(f"No PNGs found under {RAW_DIR} - run stage 1 first.")
    print(f"Done: {count} store screenshot(s) written to {STORE_DIR}")


if __name__ == "__main__":
    main()
