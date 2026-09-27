import 'package:flutter/widgets.dart';

/// A tablet-sized device, in any orientation - Flutter's own common
/// `shortestSide >= 600` heuristic. For layout decisions that depend on
/// having a tablet's screen real estate at all, regardless of which way
/// it's held (e.g. keeping the bottom-nav shell persistent). Distinct from
/// [isWideLandscapeTablet], which also requires landscape - for layouts
/// that need the extra *width* specifically, not just "is this a tablet".
bool isTabletDevice(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;

/// Wide enough, in landscape, for a two-column layout (PersonDetailScreen's
/// parents/spouse/children next to its own facts, "die Verwandten" beside
/// the rest) to be worth switching to - reacts to the real viewport at
/// runtime, not a fixed "is this a tablet" platform flag, so it naturally
/// follows rotation, split-screen/multi-window resizes, and any device
/// whose metrics happen to qualify, rather than only ever firing for a
/// hardcoded device class.
///
/// Both thresholds matter: `shortestSide >= 600` (Flutter's own common
/// tablet heuristic) alone would also fire for a large phone in landscape
/// (e.g. a 6.9" phone's ~930-logical-pixel landscape width easily clears
/// it), and `width >= 900` alone would also fire for `flutter_test`'s
/// stock 800x600 surface at some derived sizes - together they keep this
/// to genuinely tablet-shaped viewports, wide enough that two columns are
/// each still comfortably usable.
bool isWideLandscapeTablet(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height &&
      size.width >= 900 &&
      size.shortestSide >= 600;
}

/// A screen's own top-bar/content max-width, matching whatever
/// PersonDetailScreen's two-column layout uses in the same situation - the
/// two need to agree exactly, not just both be "reasonably wide", so this
/// is the one place both read from.
double tabletBoundedMaxWidth(BuildContext context) =>
    isWideLandscapeTablet(context) ? 1100 : 480;
