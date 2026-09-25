#!/usr/bin/env python3
"""Stage 2 of the store-screenshot pipeline: composite each raw screen
capture into a polished, store-ready device-framed mockup.

Stage 1 (a `flutter_test` widget test, not this script) renders real app
screens to raw PNGs at exact store pixel dimensions:

    flutter test test/screenshots/store_screenshots_test.dart \
        --dart-define=RENDER_SCREENSHOTS=true

This script then takes every PNG under
screenshots/raw/{ios,ios-ipad13,android,android-tablet7,android-tablet10}/
and writes a composited version to the matching screenshots/store/*/ dir -
a dark device frame (drawn programmatically, no bundled bezel asset, no
network) around a rounded-corner clip of the screenshot, on the app's own
background color, at the exact same pixel dimensions as the raw input (some
stores are strict about upload dimensions even for a "framed" promotional
screenshot, so the frame is drawn *within* that canvas rather than added
on top of it). The device sits low enough in the canvas that its bottom
edge is deliberately cropped off - a common store-screenshot convention
that reads as "there's more below" - which frees up room above it for a
short caption in a clean sans-serif, describing what that screen does.

Two frame styles share the same visual language (dark neutral bezel,
rounded corners) but differ in proportions and top decoration - see
TABLET_PLATFORM_DIRS and `compose()`:

- Phone (`ios`, `android`): thicker bezel, rounder corners, a centered
  pill notch/Dynamic-Island cutout.
- Tablet (`ios-ipad13`, `android-tablet7`, `android-tablet10`): thinner
  bezel (real tablet bezels read as thinner relative to the device's much
  larger size), flatter corners, a small centered camera dot instead of a
  notch - tablets in this size class don't have a notch/Dynamic-Island
  cutout.

Run:
    python3 tool/compose_store_screenshots.py

Re-run any time after stage 1 produces fresh raw screenshots - both steps
are meant to be repeatable whenever the app's UI changes.
"""

from __future__ import annotations

import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_DIR = REPO_ROOT / "screenshots" / "raw"
STORE_DIR = REPO_ROOT / "screenshots" / "store"

# A dark, neutral phone body color - not pure black, reads as a device
# rather than a hole in the image.
PHONE_COLOR = (24, 25, 28)

# lib/theme/app_theme.dart: AppColors.background - keep this in sync if the
# app's background color ever changes. Using the app's own canvas color
# (instead of plain white) makes the framed device look like it's sitting
# on the app itself rather than a generic studio backdrop.
BACKGROUND = (0xF7, 0xF6, 0xFA)

# lib/theme/app_theme.dart: AppColors.textPrimary - the caption is set in
# the app's own dark text color so it reads as part of the same design
# language as the screens below it.
CAPTION_COLOR = (0x1B, 0x1B, 0x1F)

# A clean grotesque (not the app's own UI font, Roboto) for the marketing
# caption above the device. Variable font - optical size and weight below
# are set at render time rather than picking a static-weight file.
CAPTION_FONT_PATH = pathlib.Path(__file__).resolve().parent / "fonts" / "Inter-Variable.ttf"
CAPTION_FONT_VARIATION = [32, 600]  # [optical size, weight] - semibold, tuned for large display text.

# One short, marketing-style line per raw screenshot (keyed by filename
# stem, so it applies across every platform dir that renders that screen).
# "\n" marks a deliberate, hand-picked line break (at a natural phrase
# boundary) rather than leaving it to auto-wrap.
CAPTIONS = {
    "home": "Übersichtlich und aufgeräumt",
    "search": "Schnell Nachschlagen?\nKein Problem!",
    "person_detail": "Detaillierte Einzelansichten",
    "tree_view": "Interaktiver Stammbaum\n> mobile friendly <",
}

# How much of the device's own height is deliberately pushed below the
# canvas's visible bottom edge - enough to read as "the screen continues
# past the frame" without hiding a meaningful chunk of it.
BOTTOM_OVERFLOW_FRAC = 0.07

# Phone vs tablet frame proportions - shared between `compose()` (which
# draws the frame) and `_gap_height()` (which needs to know how tall the
# caption band above the frame will be, before any frame is actually
# drawn, to size the caption font).
_FRAME_STYLE = {
    True: {"margin_frac": 0.06, "body_radius_frac": 0.035, "bezel_frac": 0.014},
    False: {"margin_frac": 0.085, "body_radius_frac": 0.11, "bezel_frac": 0.028},
}

# Must match `_Target.safeAreaFraction` (default `_kNotchSafeAreaFraction`)
# in test/screenshots/store_screenshots_test.dart, per platform dir: stage 1
# renders every raw screenshot with this fraction of its width reserved as
# blank space at the very top (a simulated notch/camera-dot safe-area
# inset, the same way a real device pushes app content down around its own
# cutout), so the decoration drawn below always lands on guaranteed-blank
# pixels instead of overlapping whatever a given screen draws at the top -
# which is exactly what went wrong before this: the notch overlapped
# TreeViewScreen's centered title even though it happened to clear
# HomeScreen's left-aligned one, because it was drawn at a fixed position
# with no dedicated blank area under it. Phones reserve much more (room for
# a notch pill); tablets reserve just enough for a small camera dot.
PHONE_SAFE_AREA_FRAC = 0.09
TABLET_SAFE_AREA_FRAC = 0.025

# Platform dirs (screenshots/raw/<dir>/, screenshots/store/<dir>/) that get
# the tablet frame treatment instead of the phone frame - see the
# module docstring.
TABLET_PLATFORM_DIRS = {"android-tablet7", "android-tablet10", "ios-ipad13"}


def rounded_mask(size: tuple[int, int], radius: float) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255
    )
    return mask


def _caption_font(size: int) -> ImageFont.FreeTypeFont:
    font = ImageFont.truetype(str(CAPTION_FONT_PATH), size)
    try:
        font.set_variation_by_axes(CAPTION_FONT_VARIATION)
    except (AttributeError, OSError):
        pass  # Static (non-variable) font fallback - renders at its default weight.
    return font


_MEASURE_DRAW = ImageDraw.Draw(Image.new("RGBA", (1, 1)))


def _caption_spacing(font: ImageFont.FreeTypeFont) -> float:
    return font.size * 0.3


def _caption_block_size(text: str, font: ImageFont.FreeTypeFont) -> tuple[float, float]:
    """The pixel size of `text` (which may contain manual "\n" breaks) set
    in `font`, exactly as `draw_caption` will lay it out - multiline-aware,
    so a two-line caption's width is its widest LINE, not the whole string
    end to end."""
    left, top, right, bottom = _MEASURE_DRAW.multiline_textbbox(
        (0, 0), text, font=font, align="center", spacing=_caption_spacing(font)
    )
    return right - left, bottom - top


def fit_shared_caption_font(texts: list[str], max_width: float, max_height: float) -> ImageFont.FreeTypeFont:
    """The largest single font size at which EVERY one of `texts` fits
    within `max_width`/`max_height` - so every caption across a platform's
    screenshots renders at the same size (the biggest that still works for
    the longest/tallest one), rather than each shrinking or growing to fit
    its own text independently."""
    size = max(10, round(max_height))
    while size > 10:
        font = _caption_font(size)
        if all(w <= max_width and h <= max_height for text in texts for w, h in [_caption_block_size(text, font)]):
            return font
        size -= max(1, size // 40)
    return _caption_font(10)


def draw_caption(
    canvas: Image.Image, text: str, canvas_size: tuple[int, int], gap_height: float, font: ImageFont.FreeTypeFont
) -> Image.Image:
    """Draws `text` (which may contain manual "\n" breaks) centered in the
    blank band above the device (the gap created by pushing the device
    down via BOTTOM_OVERFLOW_FRAC), in `font` with a soft drop shadow for a
    bit of depth."""
    canvas_w, _ = canvas_size
    cx = canvas_w / 2
    cy = gap_height / 2
    spacing = _caption_spacing(font)
    shadow_offset = font.size * 0.025

    shadow = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).multiline_text(
        (cx, cy + shadow_offset), text, font=font, fill=(0, 0, 0, 55), anchor="mm", align="center", spacing=spacing
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=font.size * 0.02))
    canvas = Image.alpha_composite(canvas, shadow)

    text_layer = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    ImageDraw.Draw(text_layer).multiline_text(
        (cx, cy), text, font=font, fill=(*CAPTION_COLOR, 255), anchor="mm", align="center", spacing=spacing
    )
    return Image.alpha_composite(canvas, text_layer)


def _gap_height(canvas_h: float, is_tablet: bool) -> float:
    """How tall the blank caption band above the device will be for a
    canvas of this height - computable without drawing anything, since (as
    in `compose()`) it depends only on canvas_h, the frame style's
    margin_frac, and BOTTOM_OVERFLOW_FRAC. Used to size the shared caption
    font before any image is actually composed."""
    margin_frac = _FRAME_STYLE[is_tablet]["margin_frac"]
    phone_h = canvas_h * (1 - 2 * margin_frac)
    return canvas_h - phone_h * (1 - BOTTOM_OVERFLOW_FRAC)


def compose(
    raw_path: pathlib.Path, canvas_size: tuple[int, int], is_tablet: bool, caption_font: ImageFont.FreeTypeFont
) -> Image.Image:
    """Composite one raw screenshot into a framed mockup at `canvas_size`
    (the same pixel dimensions the store expects for the upload). Draws the
    tablet frame (thinner bezel, flatter corners, camera dot) when
    `is_tablet`, otherwise the original phone frame (thicker bezel, rounder
    corners, notch pill) - see the module docstring. `caption_font` is
    shared across every screenshot in this platform dir - see
    fit_shared_caption_font."""
    raw = Image.open(raw_path).convert("RGBA")
    canvas_w, canvas_h = canvas_size

    canvas = Image.new("RGBA", canvas_size, (*BACKGROUND, 255))

    # Device body: horizontally centered with an even margin, sized to the
    # same aspect ratio as the raw screenshot so the screen fills the
    # device edge-to-edge like a real device photo. Scaled to the
    # available width only (not height) - the device is meant to run past
    # the bottom of the canvas, so vertical space isn't a sizing
    # constraint, just a positioning one (see BOTTOM_OVERFLOW_FRAC below).
    style = _FRAME_STYLE[is_tablet]
    margin_frac, body_radius_frac, bezel_frac = style["margin_frac"], style["body_radius_frac"], style["bezel_frac"]

    avail_w = canvas_w * (1 - 2 * margin_frac)
    scale = avail_w / raw.width
    phone_w = raw.width * scale
    phone_h = raw.height * scale
    phone_x = (canvas_w - phone_w) / 2
    # Positioned so exactly BOTTOM_OVERFLOW_FRAC of the device's own height
    # sits below the canvas's visible bottom edge, whatever the scale
    # worked out to - the rest of the canvas above it is the caption band.
    phone_y = canvas_h - phone_h * (1 - BOTTOM_OVERFLOW_FRAC)

    body_radius = phone_w * body_radius_frac
    bezel = phone_w * bezel_frac

    # Soft drop shadow under the device for a bit of depth.
    shadow = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    shadow_offset = phone_h * 0.012
    ImageDraw.Draw(shadow).rounded_rectangle(
        [phone_x, phone_y + shadow_offset, phone_x + phone_w, phone_y + phone_h + shadow_offset],
        radius=body_radius,
        fill=(0, 0, 0, 110),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=phone_w * 0.02))
    canvas = Image.alpha_composite(canvas, shadow)

    # Device body: a rounded-rectangle in a dark neutral color.
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

    # Top decoration, drawn in the device body color so it reads as a
    # cutout in the screen rather than a sticker on top of the content.
    # Positioned and sized to stay within the blank safe-area band stage 1
    # reserved at the top of the raw screenshot (see PHONE_SAFE_AREA_FRAC /
    # TABLET_SAFE_AREA_FRAC) - guaranteed to fit with room to spare below
    # it, whatever the band's exact height works out to for this image.
    safe_area_frac = TABLET_SAFE_AREA_FRAC if is_tablet else PHONE_SAFE_AREA_FRAC
    safe_band_h = screen_w * safe_area_frac
    decoration = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(decoration)
    if is_tablet:
        # A small centered camera dot - tablets in this size class don't
        # have a notch/Dynamic-Island cutout, just a front camera in the
        # bezel itself, so a plain circle reads truer than a phone-style
        # pill.
        dot_r = min(phone_w * 0.0055, safe_band_h * 0.4)
        dot_cx = phone_x + phone_w / 2
        dot_cy = screen_y + safe_band_h * 0.5
        draw.ellipse(
            [dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r],
            fill=(*PHONE_COLOR, 255),
        )
    else:
        # A pill at the top of the screen (Dynamic-Island style).
        notch_w = phone_w * 0.26
        notch_h = min(phone_w * 0.04, safe_band_h * 0.55)
        notch_x = phone_x + (phone_w - notch_w) / 2
        notch_y = screen_y + (safe_band_h - notch_h) * 0.35
        draw.rounded_rectangle(
            [notch_x, notch_y, notch_x + notch_w, notch_y + notch_h],
            radius=notch_h / 2,
            fill=(*PHONE_COLOR, 255),
        )
    canvas = Image.alpha_composite(canvas, decoration)

    caption = CAPTIONS.get(raw_path.stem)
    if caption:
        canvas = draw_caption(canvas, caption, canvas_size, gap_height=phone_y, font=caption_font)

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
        is_tablet = platform_dir.name in TABLET_PLATFORM_DIRS
        out_dir = STORE_DIR / platform_dir.name
        out_dir.mkdir(parents=True, exist_ok=True)

        raw_paths = sorted(platform_dir.glob("*.png"))
        if not raw_paths:
            continue
        # Every raw screenshot in a platform dir shares the same canvas
        # size (stage 1 renders them all to the exact store target
        # dimensions), so the caption band is the same height for all of
        # them too - one shared, maximized font size fits them all.
        with Image.open(raw_paths[0]) as im:
            canvas_size = im.size
        gap_height = _gap_height(canvas_size[1], is_tablet)
        caption_font = fit_shared_caption_font(list(CAPTIONS.values()), max_width=canvas_size[0] * 0.86, max_height=gap_height * 0.5)

        for raw_path in raw_paths:
            with Image.open(raw_path) as im:
                size = im.size
            composed = compose(raw_path, size, is_tablet=is_tablet, caption_font=caption_font)
            # Prefixed with the platform dir name (e.g. "ios-6.9_home.png"):
            # every store's upload picker shows only the bare filename, not
            # which folder it came from, and "home.png" repeated across
            # five differently-sized platform dirs is impossible to tell
            # apart once they're all sitting in one flat OS file picker.
            out_path = out_dir / f"{platform_dir.name}_{raw_path.name}"
            composed.save(out_path, "PNG")
            print(f"{raw_path.relative_to(REPO_ROOT)} -> {out_path.relative_to(REPO_ROOT)} ({size[0]}x{size[1]})")
            count += 1

    if count == 0:
        raise SystemExit(f"No PNGs found under {RAW_DIR} - run stage 1 first.")
    print(f"Done: {count} store screenshot(s) written to {STORE_DIR}")


if __name__ == "__main__":
    main()
