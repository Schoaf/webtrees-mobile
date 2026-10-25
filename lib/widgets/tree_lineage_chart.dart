import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/tree_lineage.dart';
import '../models/tree_neighborhood.dart';

const _kCardWidth = 90.0;
// Between partners, and between siblings without shown family of their own.
const _kNarrowGap = 10.0;
// Between branches that show a further generation - so couples and
// families read as groups rather than one evenly spaced row.
const _kWideGap = 24.0;
const _kBandHeight = 28.0;
const _kLineColor = Color(0xFFD1D5DB);

/// The parents and the ancestors above them (#42): one row per generation,
/// the top one first, each couple centred above their child with a fork
/// line between. Generation 1 (the parents) is the bottom row; a band below
/// it, [bottomBandHeight] tall, ends in the line down to the person.
class AncestorChart extends StatelessWidget {
  const AncestorChart({
    super.key,
    required this.ancestors,
    required this.generations,
    required this.cardBuilder,
    required this.bottomBandHeight,
    this.parentsRowKey,
    this.topRowKey,
  });

  /// By Kekulé number; 1 (the person) is not drawn.
  final Map<int, TreeNode> ancestors;

  /// Generations to show above the person.
  final int generations;

  /// [isShowingParents]: the person's own parents are drawn above them.
  final Widget Function(int n, TreeNode node, {required bool isShowingParents}) cardBuilder;
  final double bottomBandHeight;
  final Key? parentsRowKey;

  /// On the top row, to see how far it is from the view (∞).
  final Key? topRowKey;

  @override
  Widget build(BuildContext context) {
    final layout = _AncestorLayout(ancestors, generations);
    final top = layout.topGeneration;

    final children = <Widget>[];
    for (var g = top; g >= 1; g--) {
      final row = layout.generation(g);
      children.add(
        _CardRow(
          // The parents row may be the top one too - the parents key wins,
          // the ∞ check then measures it under that key.
          key: g == 1 ? parentsRowKey : (g == top ? topRowKey : null),
          width: layout.totalWidth,
          centers: [for (final n in row) layout.centers[n]!],
          cards: [for (final n in row) cardBuilder(n, ancestors[n]!, isShowingParents: layout.isShowingParents(n))],
        ),
      );
      children.add(
        SizedBox(
          width: layout.totalWidth,
          height: g == 1 ? bottomBandHeight : _kBandHeight,
          child: CustomPaint(
            painter: _ForkPainter([
              for (final n in [1, ...layout.generation(g - 1)])
                if (kekuleGeneration(n) == g - 1 && layout.isShowingParents(n))
                  _Fork(
                    single: layout.centers[n]!,
                    many: [
                      for (final parent in [2 * n, 2 * n + 1])
                        if (layout.isShown(parent)) layout.centers[parent]!,
                    ],
                  ),
            ], isPointingDown: false),
          ),
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Where each ancestor goes: every person gets a slot as wide as the
/// parents above them need (at least one card), and stands centred in it.
class _AncestorLayout {
  _AncestorLayout(this.ancestors, this.generations) {
    _place(1, 0);
  }

  final Map<int, TreeNode> ancestors;
  final int generations;
  final centers = <int, double>{};
  final _widths = <int, double>{};

  bool isShown(int n) => n > 1 && ancestors.containsKey(n) && kekuleGeneration(n) <= generations;

  bool isShowingParents(int n) => isShown(2 * n) || isShown(2 * n + 1);

  double get totalWidth => _width(1);

  int get topGeneration => centers.keys.where((n) => n > 1).map(kekuleGeneration).fold(0, math.max);

  /// The shown people of generation [g], left to right.
  List<int> generation(int g) => centers.keys.where((n) => n > 1 && kekuleGeneration(n) == g).toList()..sort();

  double _gapAbove(int n) => isShowingParents(2 * n) || isShowingParents(2 * n + 1) ? _kWideGap : _kNarrowGap;

  double _parentsWidth(int n) {
    final hasFather = isShown(2 * n);
    final hasMother = isShown(2 * n + 1);
    return (hasFather ? _width(2 * n) : 0) +
        (hasMother ? _width(2 * n + 1) : 0) +
        (hasFather && hasMother ? _gapAbove(n) : 0);
  }

  double _width(int n) => _widths[n] ??= n == 1 ? _parentsWidth(1) : math.max(_kCardWidth, _parentsWidth(n));

  void _place(int n, double left) {
    centers[n] = left + _width(n) / 2;
    final parentsLeft = left + (_width(n) - _parentsWidth(n)) / 2;
    if (isShown(2 * n)) _place(2 * n, parentsLeft);
    if (isShown(2 * n + 1)) {
      _place(2 * n + 1, parentsLeft + (isShown(2 * n) ? _width(2 * n) + _gapAbove(n) : 0));
    }
  }
}

/// The children and the descendants below them (#42): the children in one
/// row and below each person their own children, centred under them, with
/// a fork line between - [generations] rows in all.
class DescendantChart extends StatelessWidget {
  const DescendantChart({
    super.key,
    required this.children,
    required this.generations,
    required this.cardBuilder,
    this.bottomRowKey,
  });

  final List<TreeDescendant> children;
  final int generations;

  /// [isShowingChildren]: the person's own children are drawn below them.
  final Widget Function(TreeDescendant descendant, {required bool isShowingChildren}) cardBuilder;

  /// On the bottom row, to see how far it is from the view (∞).
  final Key? bottomRowKey;

  @override
  Widget build(BuildContext context) {
    final layout = _DescendantLayout(children, generations);

    final rows = <Widget>[];
    for (var level = 0; level < layout.rows.length; level++) {
      if (level > 0) {
        rows.add(
          SizedBox(
            width: layout.totalWidth,
            height: _kBandHeight,
            child: CustomPaint(
              painter: _ForkPainter([
                for (final parent in layout.rows[level - 1])
                  if (layout.isShowingChildren(parent))
                    _Fork(single: layout.centers[parent]!, many: [for (final c in parent.children) layout.centers[c]!]),
              ], isPointingDown: true),
            ),
          ),
        );
      }
      rows.add(
        _CardRow(
          key: level == layout.rows.length - 1 ? bottomRowKey : null,
          width: layout.totalWidth,
          centers: [for (final d in layout.rows[level]) layout.centers[d]!],
          cards: [for (final d in layout.rows[level]) cardBuilder(d, isShowingChildren: layout.isShowingChildren(d))],
          isAligningTop: true,
        ),
      );
    }
    return Column(mainAxisSize: MainAxisSize.min, children: rows);
  }
}

/// Where each descendant goes: every person gets a slot as wide as their
/// shown children need (at least one card), and stands centred above them.
class _DescendantLayout {
  _DescendantLayout(List<TreeDescendant> children, this.generations) {
    var row = children;
    for (var level = 0; row.isNotEmpty && level < generations; level++) {
      rows.add(row);
      for (final d in row) {
        _levels[d] = level;
      }
      row = [for (final d in row) ...d.children];
    }
    totalWidth = _rowWidth(children);
    _place(children, 0);
  }

  final int generations;

  /// The shown people of each generation, left to right.
  final rows = <List<TreeDescendant>>[];

  // By identity: a person can turn up twice, through both of their parents.
  final centers = Map<TreeDescendant, double>.identity();
  final _levels = Map<TreeDescendant, int>.identity();
  final _widths = Map<TreeDescendant, double>.identity();
  late final double totalWidth;

  bool isShowingChildren(TreeDescendant d) => _levels[d]! < generations - 1 && d.children.isNotEmpty;

  double _gap(List<TreeDescendant> row) => row.any(isShowingChildren) ? _kWideGap : _kNarrowGap;

  double _rowWidth(List<TreeDescendant> row) =>
      row.fold(0.0, (sum, d) => sum + _width(d)) + _gap(row) * math.max(0, row.length - 1);

  double _width(TreeDescendant d) =>
      _widths[d] ??= isShowingChildren(d) ? math.max(_kCardWidth, _rowWidth(d.children)) : _kCardWidth;

  void _place(List<TreeDescendant> row, double left) {
    var x = left;
    for (final d in row) {
      centers[d] = x + _width(d) / 2;
      if (isShowingChildren(d)) _place(d.children, x + (_width(d) - _rowWidth(d.children)) / 2);
      x += _width(d) + _gap(row);
    }
  }
}

/// Cards of one generation at their horizontal centres.
class _CardRow extends StatelessWidget {
  const _CardRow({
    super.key,
    required this.width,
    required this.centers,
    required this.cards,
    this.isAligningTop = false,
  });

  final double width;
  final List<double> centers;
  final List<Widget> cards;

  /// Descendants hang from the top line; ancestors stand on the bottom one.
  final bool isAligningTop;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var x = 0.0;
    for (var i = 0; i < cards.length; i++) {
      final left = centers[i] - _kCardWidth / 2;
      children.add(SizedBox(width: math.max(0, left - x)));
      children.add(SizedBox(width: _kCardWidth, child: cards[i]));
      x = left + _kCardWidth;
    }
    return SizedBox(
      width: width,
      child: Row(
        crossAxisAlignment: isAligningTop ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: children,
      ),
    );
  }
}

/// One person ([single]) and their parents or children ([many]).
class _Fork {
  const _Fork({required this.single, required this.many});

  final double single;
  final List<double> many;
}

/// Fork lines across a band: the [_Fork.many] on one edge joined by a bar,
/// and one line from the bar to the [_Fork.single] on the other edge.
class _ForkPainter extends CustomPainter {
  _ForkPainter(this.forks, {required this.isPointingDown});

  final List<_Fork> forks;

  /// The single person is on top (descendants) - else at the bottom.
  final bool isPointingDown;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kLineColor
      ..strokeWidth = 2;
    // Ancestors: the bar stays near the cards above, in a taller band too.
    final bar = isPointingDown ? size.height / 2 : math.min(14.0, size.height / 2);
    final singleY = isPointingDown ? 0.0 : size.height;
    final manyY = isPointingDown ? size.height : 0.0;
    for (final fork in forks) {
      final xs = [...fork.many, fork.single];
      canvas.drawLine(Offset(xs.reduce(math.min), bar), Offset(xs.reduce(math.max), bar), paint);
      canvas.drawLine(Offset(fork.single, singleY), Offset(fork.single, bar), paint);
      for (final x in fork.many) {
        canvas.drawLine(Offset(x, manyY), Offset(x, bar), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ForkPainter old) => true;
}
