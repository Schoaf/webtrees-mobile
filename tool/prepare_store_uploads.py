#!/usr/bin/env python3
"""Copies the composed store screenshots (screenshots/store, see
compose_store_screenshots.py and compose_store_banner.py) and the release
notes into the folders fastlane uploads from (fastlane/Fastfile):

- fastlane/screenshots/ios/<locale>/      iPhone 6.9" and iPad 13"
- fastlane/metadata/android/<locale>/images/  phone, 7" and 10" tablets, feature graphic
- fastlane/metadata/android/<locale>/changelogs/default.txt  from the App Store release notes

Run after both compose scripts; the output isn't committed.
"""

import pathlib
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
STORE = ROOT / "screenshots" / "store"
FASTLANE = ROOT / "fastlane"

# App language -> (App Store locale, Play locale)
LOCALES = {"de": ("de-DE", "de-DE"), "en": ("en-GB", "en-US"), "nl": ("nl-NL", "nl-NL")}

# Store order of the screens.
SCREENS = ["home", "search", "person_detail", "tree_view"]

IOS_DIRS = ["ios-6.9", "ios-ipad13"]
ANDROID_DIRS = {"android": "phoneScreenshots", "android-tablet7": "sevenInchScreenshots", "android-tablet10": "tenInchScreenshots"}


def copy_screens(lang: str, platform_dir: str, target: pathlib.Path, prefix: str = "") -> None:
    target.mkdir(parents=True, exist_ok=True)
    for i, screen in enumerate(SCREENS, start=1):
        source = STORE / lang / platform_dir / f"{lang}_{platform_dir}_{screen}.png"
        shutil.copy(source, target / f"{prefix}{i}_{screen}.png")


def main() -> None:
    shutil.rmtree(FASTLANE / "screenshots", ignore_errors=True)
    for lang, (ios_locale, play_locale) in LOCALES.items():
        for platform_dir in IOS_DIRS:
            # deliver tells the devices apart by size; the prefix keeps the names unique.
            copy_screens(lang, platform_dir, FASTLANE / "screenshots" / "ios" / ios_locale, prefix=f"{platform_dir}_")

        android = FASTLANE / "metadata" / "android" / play_locale
        images = android / "images"
        shutil.rmtree(images, ignore_errors=True)
        for platform_dir, kind in ANDROID_DIRS.items():
            copy_screens(lang, platform_dir, images / kind)
        shutil.copy(STORE / lang / "banner" / f"{lang}_banner_1024x500.png", images / "featureGraphic.png")

        changelogs = android / "changelogs"
        changelogs.mkdir(parents=True, exist_ok=True)
        shutil.copy(FASTLANE / "metadata" / "ios" / ios_locale / "release_notes.txt", changelogs / "default.txt")
    print(f"Prepared store uploads under {FASTLANE}")


if __name__ == "__main__":
    main()
