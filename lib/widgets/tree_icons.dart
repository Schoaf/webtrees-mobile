import 'package:flutter/material.dart';

import '../models/tree_neighborhood.dart';

/// Small status icons for the family-tree view's card corner badges and
/// the relationship bubble between partner cards — hand-painted from the
/// same coordinates as the design boards' inline SVGs, in the style of the
/// existing `CustomPainter`s in `person_avatar.dart`.

/// A small pedigree-chart diagram (one root expanding up into two, then
/// four ancestors) — for the entry-point button into the tree view.
/// Deliberately not a literal tree/plant glyph (a first attempt using
/// Icons.park_outlined read as exactly that and was rejected); this is
/// Andreas-approved "Option C" from three fork-style candidates, chosen
/// over a plain single fork (too generic) and a converging-hourglass shape
/// (visually collapsed into a plain "X").
class GenealogyTreeIcon extends StatelessWidget {
  const GenealogyTreeIcon({super.key, this.color = Colors.black, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: size, height: size, child: CustomPaint(painter: _GenealogyTreeIconPainter(color: color)));
  }
}

class _GenealogyTreeIconPainter extends CustomPainter {
  const _GenealogyTreeIconPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final dotPaint = Paint()..color = color;
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;

    final root = Offset(w * 0.5, h * 0.86);
    final gen1 = [Offset(w * 0.28, h * 0.52), Offset(w * 0.72, h * 0.52)];
    final gen2 = [
      Offset(w * 0.14, h * 0.14),
      Offset(w * 0.42, h * 0.14),
      Offset(w * 0.58, h * 0.14),
      Offset(w * 0.86, h * 0.14),
    ];

    canvas.drawLine(root, gen1[0], linePaint);
    canvas.drawLine(root, gen1[1], linePaint);
    canvas.drawLine(gen1[0], gen2[0], linePaint);
    canvas.drawLine(gen1[0], gen2[1], linePaint);
    canvas.drawLine(gen1[1], gen2[2], linePaint);
    canvas.drawLine(gen1[1], gen2[3], linePaint);

    canvas.drawCircle(root, w * 0.11, dotPaint);
    for (final p in gen1) {
      canvas.drawCircle(p, w * 0.09, dotPaint);
    }
    for (final p in gen2) {
      canvas.drawCircle(p, w * 0.075, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _GenealogyTreeIconPainter oldDelegate) => oldDelegate.color != color;
}

/// A branching tree of three dots — "has known parents" when [pointingUp]
/// (single dot below, two above), "has children" when not (single dot
/// above, two below).
class TreeBranchIcon extends StatelessWidget {
  const TreeBranchIcon({super.key, required this.pointingUp, this.color = Colors.black, this.size = 11});

  final bool pointingUp;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TreeBranchPainter(color: color, pointingUp: pointingUp)),
    );
  }
}

class _TreeBranchPainter extends CustomPainter {
  const _TreeBranchPainter({required this.color, required this.pointingUp});

  final Color color;
  final bool pointingUp;

  @override
  void paint(Canvas canvas, Size size) {
    // Coordinates lifted straight from the design's 16x16 viewBox SVG
    // (ancestors icon); descendants is the same shape flipped vertically.
    final w = size.width;
    final h = size.height;
    double px(double x) => x / 16 * w;
    double py(double y) => pointingUp ? y / 16 * h : h - (y / 16 * h);

    final dotPaint = Paint()..color = color;
    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.1
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(px(8), py(13.5)), w * 0.08, dotPaint);
    canvas.drawCircle(Offset(px(3.5), py(3.5)), w * 0.08, dotPaint);
    canvas.drawCircle(Offset(px(12.5), py(3.5)), w * 0.08, dotPaint);

    canvas.drawLine(Offset(px(8), py(12.2)), Offset(px(8), py(9)), linePaint);
    canvas.drawLine(Offset(px(8), py(9)), Offset(px(3.5), py(4.8)), linePaint);
    canvas.drawLine(Offset(px(8), py(9)), Offset(px(12.5), py(4.8)), linePaint);
  }

  @override
  bool shouldRepaint(covariant _TreeBranchPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pointingUp != pointingUp;
}

/// Two overlapping rings, styled per [status]: plain for married, smaller
/// with a connecting bar for an unmarried partnership, struck through for
/// divorced/ended, one ring dashed for widowed, a bare "?" for unknown.
class RelationshipIcon extends StatelessWidget {
  const RelationshipIcon({super.key, required this.status, this.color = Colors.black, this.size = 14});

  final MaritalStatus status;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (status == MaritalStatus.unknown) {
      return SizedBox(
        width: size,
        height: size * 0.7,
        child: Center(
          child: Text(
            '?',
            style: TextStyle(color: color, fontSize: size * 0.7, fontWeight: FontWeight.bold, height: 1),
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size * 0.65,
      child: CustomPaint(painter: _RingsPainter(color: color, status: status)),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.color, required this.status});

  final Color color;
  final MaritalStatus status;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final small = status == MaritalStatus.partnership || status == MaritalStatus.ended;
    final strike = status == MaritalStatus.divorced || status == MaritalStatus.ended;
    final rightDashed = status == MaritalStatus.widowed;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.09
      ..strokeCap = StrokeCap.round;

    if (small) {
      final r = h * 0.35;
      final leftCenter = Offset(w * 0.28, h * 0.55);
      final rightCenter = Offset(w * 0.72, h * 0.55);
      canvas.drawCircle(leftCenter, r, stroke);
      _drawRing(canvas, rightCenter, r, stroke, dashed: rightDashed);
      canvas.drawLine(Offset(w * 0.44, h * 0.55), Offset(w * 0.56, h * 0.55), stroke);
    } else {
      final r = h * 0.5;
      final leftCenter = Offset(w * 0.38, h * 0.5);
      final rightCenter = Offset(w * 0.62, h * 0.5);
      canvas.drawCircle(leftCenter, r, stroke);
      _drawRing(canvas, rightCenter, r, stroke, dashed: rightDashed);
    }

    if (strike) {
      final strikePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.09
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(w * 0.08, h * 1.0), Offset(w * 0.92, h * 0.0), strikePaint);
    }
  }

  void _drawRing(Canvas canvas, Offset center, double r, Paint paint, {required bool dashed}) {
    if (!dashed) {
      canvas.drawCircle(center, r, paint);
      return;
    }

    // A dashed circle, drawn as short arcs — Canvas has no built-in dashed
    // stroke for drawCircle.
    const dashCount = 10;
    const gapFraction = 0.5;
    final sweep = (2 * 3.14159265 / dashCount) * (1 - gapFraction);
    for (var i = 0; i < dashCount; i++) {
      final start = i * 2 * 3.14159265 / dashCount;
      canvas.drawArc(Rect.fromCircle(center: center, radius: r), start, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.status != status;
}
