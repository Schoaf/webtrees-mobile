# Releasing

While developing: assign every fixed issue to the milestone of the next version (e.g. `1.4.0`), so it's clear which version brings the fix even though the issue is already closed.

When a version goes to the stores:

1. Submit the build from TestFlight / Play internal testing to the stores.
2. Tag the commit of that build and push the tag: `git tag v1.4.0 <commit> && git push origin v1.4.0`. The release workflow then builds a signed APK, publishes a GitHub release with the milestone's closed issues as notes and the APK as download, and closes the milestone. (For an existing tag: run the workflow manually with the tag.)
3. Bump `version` in `pubspec.yaml` for the next version — the version name **and** the build number after `+` (e.g. `1.4.0+7` → `1.5.0+8`) — and create the next milestone.

The App Store and Play builds from CI use the GitHub run number as build number (`--build-number`), so they always increase on their own; only the version name comes from `pubspec.yaml`. The release APK is signed with the upload key, not Google's app signing key, so it can't be updated into the Play version or vice versa.

The iOS deploy fails early if the version name is already released in the App Store (`tool/check_ios_version_train.py`) — bump it after each App Store release.
