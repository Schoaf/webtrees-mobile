# Releasing

1. Bump `version` in `pubspec.yaml`: the version name **and** the build number after `+` (e.g. `1.2.0+5` → `1.3.0+6`). The build number must increase with every release — F-Droid uses it as the version code.
2. Commit, then tag the release commit: `git tag v1.3.0 && git push origin v1.3.0`. F-Droid builds from these tags.
3. Submit the build from TestFlight / Play internal testing to the stores.

The App Store and Play builds from CI use the GitHub run number as build number instead (`--build-number`), so they always increase on their own; only the version name comes from `pubspec.yaml`. F-Droid signs with its own key, so its builds are independent of the store builds.

The iOS deploy fails early if the version name is already released in the App Store (`tool/check_ios_version_train.py`) — bump it after each App Store release.
