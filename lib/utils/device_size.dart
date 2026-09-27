import 'package:flutter/widgets.dart';

/// A tablet-sized device, in any orientation - Flutter's own common
/// `shortestSide >= 600` heuristic. For layout decisions that depend on
/// having a tablet's screen real estate at all, regardless of which way
/// it's held (e.g. keeping the bottom-nav shell persistent). Distinct from
/// screen-specific checks that also require *landscape* (e.g.
/// `_useTwoColumnLayout` in person_detail_screen.dart), which need the
/// extra width for a particular layout, not just "is this a tablet".
bool isTabletDevice(BuildContext context) =>
    MediaQuery.sizeOf(context).shortestSide >= 600;
