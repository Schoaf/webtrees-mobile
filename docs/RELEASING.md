# Releasing

While developing: assign every fixed issue to the milestone of the next version (e.g. `1.4.0`), so it's clear which version brings the fix even though the issue is already closed.

When a version goes to the stores:

1. Update the store texts in `fastlane/metadata` if needed - at least the release notes ("What's New") in `fastlane/metadata/ios/<locale>/release_notes.txt`; Google Play gets the same text.
2. Tag the commit whose TestFlight / Play internal-testing build should go out, and push the tag: `git tag v1.4.0 <commit> && git push origin v1.4.0`. Two workflows then run:
   - **Store** renders the store screenshots, uploads them with the texts, places the header and search results artwork (`tool/upload_app_store_artwork.py` - deliver can't do that yet; if it fails, the release goes on and the images from `screenshots/store/<lang>/banner/` can be set by hand), submits that commit's TestFlight build for App Store review and promotes its internal-testing build to production on Google Play.
   - **Release** builds a signed APK, publishes a GitHub release with the milestone's closed issues as notes and the APK as download, and closes the milestone. (For an existing tag: run it manually with the tag.)
3. Once the Store workflow is through, bump `version` in `pubspec.yaml` for the next version — the version name **and** the build number after `+` (e.g. `1.4.0+7` → `1.5.0+8`) — and create the next milestone. Not earlier: every push to master uploads a new internal-testing build, and the Store workflow can only promote the tagged one while it is still there.

The App Store review contact and demo account stay as they are in App Store Connect; they never go into `fastlane/metadata` (public repo). To try the store screenshots locally: the screenshot test, both `tool/compose_store_*.py` scripts and `tool/prepare_store_uploads.py`.

The App Store and Play builds from CI use the GitHub run number as build number (`--build-number`), so they always increase on their own; only the version name comes from `pubspec.yaml`. The release APK is signed with the upload key, not Google's app signing key, so it can't be updated into the Play version or vice versa.

The iOS deploy fails early if the version name is already released in the App Store (`tool/check_ios_version_train.py`) — bump it after each App Store release.
