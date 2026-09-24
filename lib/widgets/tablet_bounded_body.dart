import 'package:flutter/material.dart';

/// Caps a screen's phone-designed body at a comfortable width and centers
/// it, so on a tablet-sized viewport the content doesn't stretch
/// edge-to-edge into oversized rows/buttons with acres of empty space on
/// either side. This deliberately doesn't change any of the wrapped
/// screen's own layout logic (Rows/Columns/ListViews behave exactly as on
/// a phone) - it only bounds the canvas they're laid out in.
///
/// Not used by [TreeViewScreen] - that screen is an inherently pannable/
/// zoomable canvas (`InteractiveViewer`), where extra tablet space is
/// something to pan into rather than wasted layout space.
class TabletBoundedBody extends StatelessWidget {
  const TabletBoundedBody({
    super.key,
    required this.child,
    this.maxWidth = 480,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
