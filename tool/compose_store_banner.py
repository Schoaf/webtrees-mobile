#!/usr/bin/env python3
"""Store banners: App Store header / search-result artwork (5244x2950 and
3840x1646, the two sizes App Store Connect accepts) and the Google Play
feature graphic (1024x500): app icon, name and a one-line pitch on the left, three phones
with real app screens on the right - per store language.

Uses the raw iPhone screenshots from stage 1 of the screenshot pipeline:

    flutter test test/screenshots/store_screenshots_test.dart --dart-define=RENDER_SCREENSHOTS=true
    python3 tool/compose_store_banner.py

Writes screenshots/store/<lang>/banner/<lang>_banner_<w>x<h>.png.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from compose_store_screenshots import (
    BACKGROUND,
    CAPTION_COLOR,
    CAPTION_FONT_PATH,
    CAPTION_FONT_VARIATION,
    PHONE_COLOR,
    RAW_DIR,
    REPO_ROOT,
    STORE_DIR,
    rounded_mask,
)

SIZES = [(5244, 2950), (3840, 1646), (1024, 500)]  # App Store header x2, Google Play feature graphic
ICON = REPO_ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset" / "Icon-App-1024x1024@1x.png"
SCREENS = ["home", "person_detail", "tree_view"]  # left to right, the middle one in front
TEXT = {
    "de": ("webtrees mobile", "Dein Stammbaum\nfür unterwegs"),
    "en": ("webtrees mobile", "Your family tree\non the go"),
}
PRIMARY = (0x2F, 0x6F, 0xB0)  # AppColors.primary


def font(size: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(CAPTION_FONT_PATH), size)
    f.set_variation_by_axes([CAPTION_FONT_VARIATION[0], weight])
    return f


def phone(screen: Image.Image, height: int) -> Image.Image:
    """A screen in a simple dark phone frame, with a soft shadow, `height` px tall."""
    bezel = round(height * 0.018)
    inner_h = height - 2 * bezel
    inner_w = round(inner_h * screen.width / screen.height)
    w = inner_w + 2 * bezel
    shadow_pad = round(height * 0.05)
    out = Image.new("RGBA", (w + 2 * shadow_pad, height + 2 * shadow_pad), (0, 0, 0, 0))

    shadow = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (shadow_pad, shadow_pad + bezel, shadow_pad + w, shadow_pad + height), radius=height * 0.07, fill=(0, 0, 0, 70))
    out = Image.alpha_composite(out, shadow.filter(ImageFilter.GaussianBlur(height * 0.02)))

    body = Image.new("RGBA", (w, height), PHONE_COLOR + (255,))
    out.paste(body, (shadow_pad, shadow_pad), rounded_mask((w, height), height * 0.07))
    scr = screen.convert("RGBA").resize((inner_w, inner_h), Image.LANCZOS)
    out.paste(scr, (shadow_pad + bezel, shadow_pad + bezel), rounded_mask((inner_w, inner_h), height * 0.06))
    return out


def banner(lang: str, size: tuple[int, int]) -> Image.Image:
    w, h = size
    canvas = Image.new("RGBA", size, BACKGROUND + (255,))
    draw = ImageDraw.Draw(canvas)

    # Phones on the right half, the middle one larger and in front.
    raw = RAW_DIR / lang / "ios"
    screens = [Image.open(raw / f"{name}.png") for name in SCREENS]
    big = round(min(h * 0.86, w * 0.38))
    small = round(big * 0.86)
    right_center = round(w * 0.70)
    spread = round(big * 0.40)
    for screen, height, dx in ((screens[0], small, -spread), (screens[2], small, spread), (screens[1], big, 0)):
        p = phone(screen, height)
        canvas.alpha_composite(p, (right_center + dx - p.width // 2, (h - p.height) // 2 + round(h * 0.04)))

    # Icon, name and pitch on the left.
    left = round(w * 0.07)
    # Text scales with the narrower of height and width, so it never runs into the phones.
    unit = min(h, w * 0.43)
    icon_size = round(unit * 0.20)
    icon = Image.open(ICON).convert("RGBA").resize((icon_size, icon_size), Image.LANCZOS)
    title, pitch = TEXT[lang]
    title_font = font(round(unit * 0.075), 700)
    pitch_font = font(round(unit * 0.085), 600)
    pitch_box = draw.multiline_textbbox((0, 0), pitch, font=pitch_font, spacing=round(unit * 0.02))
    block_h = icon_size + round(unit * 0.05) + pitch_box[3]
    top = (h - block_h) // 2
    canvas.paste(icon, (left, top), rounded_mask((icon_size, icon_size), icon_size * 0.22))
    draw.text((left + icon_size + round(unit * 0.04), top + icon_size // 2), title, font=title_font, fill=PRIMARY, anchor="lm")
    draw.multiline_text((left, top + icon_size + round(unit * 0.05)), pitch, font=pitch_font, fill=CAPTION_COLOR,
                        spacing=round(unit * 0.02))
    return canvas.convert("RGB")


def main() -> None:
    for lang in TEXT:
        if not (RAW_DIR / lang / "ios").exists():
            raise SystemExit(f"{RAW_DIR / lang / 'ios'} missing - run stage 1 of the screenshot pipeline first")
        out_dir = STORE_DIR / lang / "banner"
        out_dir.mkdir(parents=True, exist_ok=True)
        for size in SIZES:
            path = out_dir / f"{lang}_banner_{size[0]}x{size[1]}.png"
            banner(lang, size).save(path, "PNG")
            print(path.relative_to(REPO_ROOT))


if __name__ == "__main__":
    main()
