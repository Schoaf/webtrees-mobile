import 'package:flutter/material.dart';

import '../models/tree_neighborhood.dart';
import '../theme/app_theme.dart';
import 'person_avatar.dart';
import 'tree_icons.dart';

// The card's own inner padding - deliberately asymmetric (generous bottom
// padding so the descendants-count badge has somewhere to sit without
// covering the birth-year text right above it). _CornerBadge positions
// against the CARD's true edges, not the padded Stack's, so it has to
// subtract this back out per side - sharing this constant is what keeps
// the two in sync.
const _kCardPadding = EdgeInsets.fromLTRB(6, 10, 6, 16);

// Matches _RelationshipBubble's size in tree_view_screen.dart (1.5x the
// original 22px) - shared visual size for the two "circle button"
// affordances that can appear on/around a card.
const _kRelationshipBadgeSize = 33.0;

// A touch off pure white, but distinctly lighter than the page's own
// canvas background (0xFFF4F5F7) - matches _RelationshipBubble's
// background in tree_view_screen.dart.
const _kBadgeBackground = Color(0xFFF8F9FA);

/// One card in the family-tree view (`PersonCardV4d` in the design). Purely
/// presentational — which badges to show is a per-role decision made by
/// whoever builds the tree layout (see `treeCardSuppression` doc in
/// `tree_view_screen.dart`), not logic living in this widget.
class TreeNodeCard extends StatelessWidget {
  const TreeNodeCard({
    super.key,
    required this.firstName,
    required this.sex,
    required this.isDead,
    required this.birthYear,
    this.thumb,
    this.photoHeaders,
    this.selected = false,
    this.detail,
    this.partnerNameRow,
    this.showAncestorsIcon = false,
    this.ancestorsIconOnRight = false,
    this.showPartnerIcon = false,
    this.partnerExtraCount,
    this.showChildrenIcon = false,
    this.childrenCount = 0,
    this.showInfoButton = false,
    this.onTap,
    this.onInfoTap,
    this.width = 90,
    this.minHeight,
  });

  final String firstName;
  final String sex;
  final bool isDead;
  final int? birthYear;
  final String? thumb;
  final Map<String, String>? photoHeaders;
  final bool selected;

  /// Non-null shows the expanded detail block (active person only).
  final TreePersonDetail? detail;

  /// Sibling-only: the partner's first name shown under the person's own
  /// name, with a small rings icon. Pass `''` (not null) to still reserve
  /// the row's height when a sibling has no partner, so sibling cards stay
  /// the same height whether or not they show this row.
  final String? partnerNameRow;

  final bool showAncestorsIcon;

  /// True for a partner card, where the ancestors badge sits on the
  /// outer (top-right) corner instead of top-left.
  final bool ancestorsIconOnRight;

  final bool showPartnerIcon;

  /// Non-null and >0 shows "+N" next to the partner rings icon (a parent
  /// with further, not-shown partnerships).
  final int? partnerExtraCount;

  final bool showChildrenIcon;
  final int childrenCount;
  final bool showInfoButton;
  final VoidCallback? onTap;
  final VoidCallback? onInfoTap;
  final double width;

  /// A partner card is drawn at least as tall as the (zoomed) active-person
  /// card, so it never reads as one of the sibling cards.
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final avatar = PersonAvatar(sex: sex, isDead: isDead, size: 32, photoUrl: thumb, photoHeaders: photoHeaders);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
        padding: _kCardPadding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? AppColors.primary : const Color(0xFFE5E7EB), width: selected ? 2.5 : 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          // Stack's default alignment is top-left for non-positioned
          // children, not center - the Column below shrink-wraps to its
          // widest child (usually narrower than the full card width), so
          // without this it sits left-aligned instead of centered.
          alignment: Alignment.topCenter,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(height: 4),
                Text(
                  firstName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
                ),
                if (partnerNameRow != null) _PartnerNameRow(name: partnerNameRow!),
                Text(
                  birthYear?.toString() ?? '',
                  style: const TextStyle(fontSize: 10, color: Color(0xFF6B7280)),
                ),
                if (detail != null) _DetailBlock(detail: detail!),
              ],
            ),
            if (showAncestorsIcon)
              _CornerBadge(
                top: true,
                right: ancestorsIconOnRight,
                // Ancestors/descendants sit a touch inside the true edge
                // (unlike the partner badge, which stays flush) - see
                // _CornerBadge.edgeGap.
                edgeGap: 1,
                child: TreeBranchIcon(pointingUp: true, size: 11, color: const Color(0xFF4B5563)),
              ),
            if (showPartnerIcon)
              _CornerBadge(
                top: true,
                right: true,
                // Not a true circle (icon+count pill, wider than tall) - a
                // mathematically-equal edgeGap on every side still read as
                // sitting a shade closer to the right edge than the top
                // one. 1px more inset both vertically and horizontally
                // lines the two up.
                edgeGap: 1,
                horizontalEdgeGap: 1,
                child: _CountBadgeContent(
                  icon: RelationshipIcon(status: MaritalStatus.married, size: 11, color: const Color(0xFF4B5563)),
                  count: (partnerExtraCount ?? 0) > 0 ? partnerExtraCount : null,
                ),
              ),
            if (showChildrenIcon)
              _CornerBadge(
                top: false,
                right: false,
                edgeGap: 1,
                child: _CountBadgeContent(
                  icon: TreeBranchIcon(pointingUp: false, size: 10, color: const Color(0xFF4B5563)),
                  count: childrenCount,
                ),
              ),
            if (showInfoButton)
              _CornerBadge(
                top: false,
                right: true,
                edgeGap: 1,
                // Sized to match the relationship bubble between partner
                // cards (_RelationshipBubble in tree_view_screen.dart) for
                // visual parity between the two "circle button" affordances
                // on a card.
                size: _kRelationshipBadgeSize,
                child: GestureDetector(
                  onTap: onInfoTap,
                  child: const Icon(Icons.info_outline, size: 20, color: Color(0xFF4B5563)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PartnerNameRow extends StatelessWidget {
  const _PartnerNameRow({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty) {
      return const SizedBox(height: 11);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RelationshipIcon(status: MaritalStatus.married, size: 9, color: const Color(0xFF6B7280)),
          const SizedBox(width: 2),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({required this.detail});

  final TreePersonDetail detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F1F3)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(detail.birthDateText, style: const TextStyle(fontSize: 11, color: Color(0xFF374151)), textAlign: TextAlign.center),
          if (detail.birthPlace.isNotEmpty)
            Text(detail.birthPlace, style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF)), textAlign: TextAlign.center),
          if (detail.occupation.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                detail.occupation,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class _CornerBadge extends StatelessWidget {
  const _CornerBadge({
    required this.top,
    required this.right,
    required this.child,
    this.edgeGap = 0,
    double? horizontalEdgeGap,
    this.size = 18,
  }) : horizontalEdgeGap = horizontalEdgeGap ?? edgeGap;

  final bool top;
  final bool right;
  final Widget child;

  // How far the badge sits from the CARD's own true edge (0 = flush with
  // it, positive = inside the card) - the same on every side, so it reads
  // as tucked evenly into the corner rather than drifting toward whichever
  // side happens to have less padding. Poking past the true edge read as
  // floating well outside the card once it was actually made uniform;
  // flush/slightly inside looks tucked into the corner without the badge
  // visually detaching from the card. Applies to the vertical (top/bottom)
  // edge; horizontalEdgeGap (defaults to this) applies to left/right - the
  // "icon+count" pill badges aren't a true circle, so their visual left/
  // right inset didn't quite read the same as their top/bottom one even
  // with a mathematically-equal offset, and needed its own tuning.
  final double edgeGap;
  final double horizontalEdgeGap;

  /// The badge circle's min width/height - see _kRelationshipBadgeSize for
  /// the larger variant used on the info button.
  final double size;

  @override
  Widget build(BuildContext context) {
    // This Positioned lives inside the padded Stack, not against the
    // card's true edges directly - subtracting the card's own padding
    // back out is what makes edgeGap actually uniform on screen despite
    // the card's padding being asymmetric (see _kCardPadding).
    return Positioned(
      top: top ? edgeGap - _kCardPadding.top : null,
      bottom: top ? null : edgeGap - _kCardPadding.bottom,
      left: right ? null : horizontalEdgeGap - _kCardPadding.left,
      right: right ? horizontalEdgeGap - _kCardPadding.right : null,
      child: _CornerCircle(size: size, child: child),
    );
  }
}

class _CornerCircle extends StatelessWidget {
  const _CornerCircle({required this.child, this.size = 18});

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: _kBadgeBackground,
        // A true circle (BoxShape.circle) inscribes its decoration using
        // the smaller of width/height as the diameter - fine for a lone
        // icon, but a badge with "icon+N" content is wider than tall, so
        // the content visibly spilled past the drawn circle's edge. A pill
        // shape stretches to match the content's actual bounds instead.
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

class _CountBadgeContent extends StatelessWidget {
  const _CountBadgeContent({required this.icon, this.count});

  final Widget icon;
  final int? count;

  @override
  Widget build(BuildContext context) {
    if (count == null) return icon;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 1),
        Text('+$count', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF4B5563))),
      ],
    );
  }
}

/// A dashed-border placeholder for an unrecorded partner/parent — never
/// tappable.
class UnknownPersonCard extends StatelessWidget {
  const UnknownPersonCard({super.key, this.width = 90, this.minHeight});

  final double width;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: minHeight == null ? null : BoxConstraints(minHeight: minHeight!),
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      decoration: const ShapeDecoration(
        color: Color(0xFFF9FAFB),
        shape: _DashedRoundedRectangleBorder(color: Color(0xFFE5E7EB), radius: 12, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(color: Color(0xFFD1D5DB), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const Text('?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const SizedBox(height: 4),
          const Text('Unbekannt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF))),
        ],
      ),
    );
  }
}

/// Flutter's `Border`/`BoxBorder` have no dashed style — this walks the
/// rounded-rect outline with `Path.computeMetrics()` and paints short
/// segments along it, the standard way to get a dashed border.
class _DashedRoundedRectangleBorder extends ShapeBorder {
  const _DashedRoundedRectangleBorder({required this.color, required this.radius, required this.width});

  final Color color;
  final double radius;
  final double width;
  static const double dashLength = 4;
  static const double gapLength = 3;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect.deflate(width), Radius.circular(radius - width)));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    for (final metric in getOuterPath(rect).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + gapLength;
      }
    }
  }

  @override
  ShapeBorder scale(double t) => _DashedRoundedRectangleBorder(color: color, radius: radius * t, width: width * t);
}
