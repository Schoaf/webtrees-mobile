import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/tree_neighborhood.dart';
import '../../state/app_providers.dart';
import '../../state/tree_view_providers.dart';
import '../../widgets/tree_icons.dart';
import '../../widgets/tree_node_card.dart';
import '../search/person_detail_screen.dart';

const _kCardWidth = 90.0;
const _kActiveZoom = 1.22;
const _kMinScale = 0.5;
const _kMaxScale = 2.5;

// Shared padding for the "GESCHWISTER"/"KINDER MIT X" frames (siblings and
// children groups): more breathing room to the cards left/right than
// above/below - the frame border already reads as a boundary on its own,
// so a tighter top/bottom didn't need as much air as the sides did. Top and
// bottom stay equal to each other.
const _kFrameHorizontalPadding = 10.0;
const _kFrameTopPadding = 12.0;
const _kFrameBottomPadding = _kFrameTopPadding;
// The floating label's vertical center sits ~8px above the border (so it
// straddles the 1.5px border line like a fieldset legend) - its Positioned
// top is relative to the padded Stack, which itself starts _kFrameTopPadding
// below the border, so this subtracts that back out.
const _kFrameLabelTopOffset = -8.0 - _kFrameTopPadding;

/// The interactive family-tree view: pan-able cards for the current
/// person's parents, full siblings, partner(s) and children. Tapping a
/// card re-centers the whole view on that person; the only other action is
/// the i-button on the active person's own card, which opens the full
/// detail/edit screen. See the spec at
/// `stammbaum-ansicht-spec.md` for the exact layout and suppression rules
/// this implements.
class TreeViewScreen extends ConsumerStatefulWidget {
  const TreeViewScreen({super.key, required this.xref});

  final String xref;

  @override
  ConsumerState<TreeViewScreen> createState() => _TreeViewScreenState();
}

class _TreeViewScreenState extends ConsumerState<TreeViewScreen> {
  final _transformController = TransformationController();
  final _activeCardKey = GlobalKey();
  final _viewportKey = GlobalKey();
  // The InteractiveViewer's direct child - measuring the family group
  // relative to this (not the viewport) gives its position in the child's
  // own untransformed coordinate space, independent of whatever pan/zoom is
  // currently applied - see _maybeCenterOnActivePerson.
  final _contentKey = GlobalKey();
  // Wraps parents + connector + the siblings frame (not the children frame
  // below, which stays reachable by panning down rather than being forced
  // into the initial fit).
  final _familyGroupKey = GlobalKey();
  String? _centeredForXref;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  /// Fits and positions the view on the family group (parents + siblings
  /// frame) whenever the active person changes: horizontally centered,
  /// zoomed so the whole group is visible, with the parents row sitting
  /// near the top rather than the active card just being pushed to the
  /// canvas's dead center - that wasted space above the parents row and
  /// often cut off siblings on a narrow phone screen.
  void _maybeCenterOnActivePerson(String activeXref) {
    if (_centeredForXref == activeXref) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final groupBox = _familyGroupKey.currentContext?.findRenderObject() as RenderBox?;
      final contentBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (groupBox == null || contentBox == null || viewportBox == null) return;

      final groupTopLeft = groupBox.localToGlobal(Offset.zero, ancestor: contentBox);
      final groupSize = groupBox.size;
      final viewportSize = viewportBox.size;

      const horizontalPadding = 24.0;
      const topPadding = 24.0;
      const bottomPadding = 24.0;

      final scaleByWidth = (viewportSize.width - 2 * horizontalPadding) / groupSize.width;
      final scaleByHeight = (viewportSize.height - topPadding - bottomPadding) / groupSize.height;
      final scale = math.min(scaleByWidth, scaleByHeight).clamp(_kMinScale, _kMaxScale);

      final groupCenterX = groupTopLeft.dx + groupSize.width / 2;
      final groupTopY = groupTopLeft.dy;

      _transformController.value = Matrix4.identity()
        ..translateByDouble(viewportSize.width / 2, topPadding, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-groupCenterX, -groupTopY, 0, 1);
      _centeredForXref = activeXref;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final treeState = ref.watch(treeViewControllerProvider(widget.xref));
    final controller = ref.read(treeViewControllerProvider(widget.xref).notifier);
    final neighborhood = treeState.activeNeighborhood;

    if (neighborhood != null) {
      _maybeCenterOnActivePerson(treeState.activeXref);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(
              canUndo: treeState.canUndo,
              canRedo: treeState.canRedo,
              onBack: () => Navigator.of(context).pop(),
              onUndo: controller.undo,
              onRedo: controller.redo,
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (neighborhood == null && treeState.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (neighborhood == null && treeState.error != null) {
                    return Center(
                      child: Text(
                        l10n.couldNotLoad(
                          treeState.error ?? l10n.genericErrorFallback,
                        ),
                      ),
                    );
                  }
                  if (neighborhood == null) {
                    // Shouldn't be reachable (build() always starts loading,
                    // _load() always ends in either data or an error) - but
                    // rendering nothing at all here is exactly how an
                    // unexpected state would look identical to "the button
                    // did nothing", so show something instead of guessing.
                    return Center(child: Text(l10n.unknownStateMessage));
                  }

                  return Stack(
                    key: _viewportKey,
                    children: [
                      InteractiveViewer(
                        transformationController: _transformController,
                        constrained: false,
                        minScale: _kMinScale,
                        maxScale: _kMaxScale,
                        boundaryMargin: const EdgeInsets.all(400),
                        child: Padding(
                          key: _contentKey,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: _TreeContent(
                            neighborhood: neighborhood,
                            selectedPartnerXref: treeState.selectedPartnerXref,
                            activeCardKey: _activeCardKey,
                            familyGroupKey: _familyGroupKey,
                            onSelectPerson: controller.selectPerson,
                            onSelectPartner: controller.selectPartner,
                            onOpenProfile: (xref) => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: xref)),
                            ),
                          ),
                        ),
                      ),
                      if (treeState.loading)
                        const Positioned(
                          top: 12,
                          right: 12,
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.canUndo,
    required this.canRedo,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
  });

  final bool canUndo;
  final bool canRedo;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF6B7280)),
            tooltip: l10n.leaveTreeTooltip,
            onPressed: onBack,
          ),
          Expanded(
            child: Text(
              l10n.treeViewTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            color: canUndo ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
            tooltip: l10n.previousPersonTooltip,
            onPressed: canUndo ? onUndo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            color: canRedo ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
            tooltip: l10n.nextPersonTooltip,
            onPressed: canRedo ? onRedo : null,
          ),
        ],
      ),
    );
  }
}

class _TreeContent extends ConsumerWidget {
  const _TreeContent({
    required this.neighborhood,
    required this.selectedPartnerXref,
    required this.activeCardKey,
    required this.familyGroupKey,
    required this.onSelectPerson,
    required this.onSelectPartner,
    required this.onOpenProfile,
  });

  final TreeNeighborhood neighborhood;
  final String? selectedPartnerXref;
  final GlobalKey activeCardKey;
  /// Wraps parents + siblings frame - see _TreeViewScreenState's own doc
  /// comment on the field this is passed from.
  final GlobalKey familyGroupKey;
  final void Function(String xref) onSelectPerson;
  final void Function(String xref) onSelectPartner;
  final void Function(String xref) onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoHeaders = ref.read(webtreesClientProvider).imageHeaders;
    final partner = selectedPartnerXref == null
        ? neighborhood.defaultPartner
        : neighborhood.partners.where((p) => p.familyXref == selectedPartnerXref).firstOrNull ??
              neighborhood.defaultPartner;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          key: familyGroupKey,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (neighborhood.father != null || neighborhood.mother != null) ...[
              _ParentsRow(
                neighborhood: neighborhood,
                photoHeaders: photoHeaders,
                onSelectPerson: onSelectPerson,
              ),
              const SizedBox(height: 10),
              Container(width: 2, height: 24, color: const Color(0xFFD1D5DB)),
            ],
            _SiblingsFrame(
              neighborhood: neighborhood,
              partner: partner,
              photoHeaders: photoHeaders,
              activeCardKey: activeCardKey,
              onSelectPerson: onSelectPerson,
              onSelectPartner: onSelectPartner,
              onOpenProfile: onOpenProfile,
            ),
          ],
        ),
        if (partner != null && partner.children.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(width: 2, height: 18, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 10),
          _ChildrenFrame(
            partner: partner,
            photoHeaders: photoHeaders,
            // Children with any OTHER partner - "Kinder mit X" only shows
            // this one family, so without this there was no hint at all
            // that the active person has children elsewhere too.
            extraChildrenCount: neighborhood.partners
                .where((p) => p.familyXref != partner.familyXref)
                .fold(0, (n, p) => n + p.children.length),
            onSelectPerson: onSelectPerson,
          ),
        ],
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _ParentsRow extends StatelessWidget {
  const _ParentsRow({required this.neighborhood, required this.photoHeaders, required this.onSelectPerson});

  final TreeNeighborhood neighborhood;
  final Map<String, String> photoHeaders;
  final void Function(String xref) onSelectPerson;

  @override
  Widget build(BuildContext context) {
    final father = neighborhood.father;
    final mother = neighborhood.mother;

    Widget parentCard(TreeNode node, {required bool isFather}) {
      final extra = isFather ? neighborhood.extraChildrenFather : neighborhood.extraChildrenMother;
      return Stack(
        clipBehavior: Clip.none,
        children: [
          TreeNodeCard(
            firstName: node.firstName,
            sex: node.sex,
            isDead: node.isDead,
            birthYear: node.birthYear,
            thumb: node.thumb,
            photoHeaders: photoHeaders,
            showAncestorsIcon: node.hasParents ?? false,
            showPartnerIcon: (node.partnersCount ?? 0) > 1,
            partnerExtraCount: (node.partnersCount ?? 0) - 1,
            onTap: () => onSelectPerson(node.xref),
          ),
          if (extra > 0)
            Positioned(
              bottom: -20,
              left: isFather ? 6 : null,
              right: isFather ? null : 6,
              child: Column(
                children: [
                  Container(width: 2, height: 9, color: const Color(0xFFD1D5DB)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TreeBranchIcon(pointingUp: false, size: 9, color: const Color(0xFF6B7280)),
                        const SizedBox(width: 1),
                        Text('+$extra', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF6B7280))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    if (father != null && mother != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                parentCard(father, isFather: true),
                const SizedBox(width: 10),
                parentCard(mother, isFather: false),
              ],
            ),
            Positioned(
              top: 22,
              child: _RelationshipBubble(status: MaritalStatus.married),
            ),
          ],
        ),
      );
    }

    final onlyParent = father ?? mother;
    if (onlyParent == null) return const SizedBox.shrink();
    return parentCard(onlyParent, isFather: father != null);
  }
}

class _RelationshipBubble extends StatelessWidget {
  const _RelationshipBubble({required this.status});

  final MaritalStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x38111827), blurRadius: 6, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: RelationshipIcon(status: status, size: 13, color: const Color(0xFF4B5563)),
    );
  }
}

class _SiblingsFrame extends StatelessWidget {
  const _SiblingsFrame({
    required this.neighborhood,
    required this.partner,
    required this.photoHeaders,
    required this.activeCardKey,
    required this.onSelectPerson,
    required this.onSelectPartner,
    required this.onOpenProfile,
  });

  final TreeNeighborhood neighborhood;
  final TreePartnerFamily? partner;
  final Map<String, String> photoHeaders;
  final GlobalKey activeCardKey;
  final void Function(String xref) onSelectPerson;
  final void Function(String xref) onSelectPartner;
  final void Function(String xref) onOpenProfile;

  @override
  Widget build(BuildContext context) {
    final siblings = neighborhood.siblings;
    final mid = (siblings.length / 2).ceil();
    final left = siblings.sublist(0, mid);
    final right = siblings.sublist(mid);

    Widget siblingCard(TreeNode node) {
      return TreeNodeCard(
        firstName: node.firstName,
        sex: node.sex,
        isDead: node.isDead,
        birthYear: node.birthYear,
        thumb: node.thumb,
        photoHeaders: photoHeaders,
        // Siblings' own partner isn't in this response (personSummary()
        // doesn't nest a spouse for list entries) - reserve the row's
        // height for consistent card sizing without showing a name.
        partnerNameRow: '',
        showChildrenIcon: (node.childrenCount ?? 0) > 0,
        childrenCount: node.childrenCount ?? 0,
        onTap: () => onSelectPerson(node.xref),
      );
    }

    final activeCard = KeyedSubtree(
      key: activeCardKey,
      child: TreeNodeCard(
        firstName: neighborhood.person.firstName,
        sex: neighborhood.person.sex,
        isDead: neighborhood.person.isDead,
        birthYear: neighborhood.person.birthYear,
        thumb: neighborhood.person.thumb,
        photoHeaders: photoHeaders,
        selected: true,
        width: _kCardWidth * _kActiveZoom,
        showInfoButton: true,
        detail: neighborhood.personDetail,
        onInfoTap: () => onOpenProfile(neighborhood.person.xref),
      ),
    );

    Widget centerGroup;
    if (partner == null) {
      centerGroup = activeCard;
    } else {
      final p = partner!;
      const gap = 10.0;
      const activeWidth = _kCardWidth * _kActiveZoom;
      const bubbleSize = 22.0;
      centerGroup = Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              activeCard,
              const SizedBox(width: gap),
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  children: [
                    p.partner == null
                        ? const UnknownPersonCard(minHeight: 185)
                        : TreeNodeCard(
                            firstName: p.partner!.firstName,
                            sex: p.partner!.sex,
                            isDead: p.partner!.isDead,
                            birthYear: p.partner!.birthYear,
                            thumb: p.partner!.thumb,
                            photoHeaders: photoHeaders,
                            showAncestorsIcon: p.partner!.hasParents ?? false,
                            ancestorsIconOnRight: true,
                            minHeight: 185,
                            onTap: () => onSelectPerson(p.partner!.xref),
                          ),
                    if (neighborhood.partners.length > 1) ...[
                      const SizedBox(height: 5),
                      _PartnerChips(
                        partners: neighborhood.partners,
                        selectedFamilyXref: p.familyXref,
                        onSelect: onSelectPartner,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // Sits in the gap between the two cards (like the parents-row
          // bubble), not overlapping either card's own content - a small
          // badge is fine overlapping a seam; a whole card overlapping
          // another card's content is not.
          Positioned(
            top: 36,
            left: activeWidth + gap / 2 - bubbleSize / 2,
            child: _RelationshipBubble(status: p.maritalStatus),
          ),
        ],
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6),
      // The frame label straddles the border like a fieldset legend (hence
      // painting its background over the border line) - see
      // _kFrameLabelTopOffset for why its Positioned top is what it is.
      // Top padding here is also what stops the row of cards below from
      // starting underneath the label.
      padding: const EdgeInsets.fromLTRB(
        _kFrameHorizontalPadding,
        _kFrameTopPadding,
        _kFrameHorizontalPadding,
        _kFrameBottomPadding,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final s in left) Padding(padding: const EdgeInsets.only(bottom: 10), child: siblingCard(s))],
              ),
              const SizedBox(width: 8),
              centerGroup,
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final s in right) Padding(padding: const EdgeInsets.only(bottom: 10), child: siblingCard(s))],
              ),
            ],
          ),
          // Painted last (on top of the cards above) - a Stack paints in
          // child order, and this label floating above the frame's own top
          // border can overlap the first row of cards depending on their
          // height (e.g. a card showing an extra detail line), which
          // otherwise hid the label text behind them.
          Positioned(
            top: _kFrameLabelTopOffset,
            left: 16,
            child: Container(
              color: const Color(0xFFF4F5F7),
              // letterSpacing adds trailing space after the LAST glyph too,
              // not just between glyphs - a plain symmetric(horizontal: 6)
              // therefore looked visibly wider on the right than the left.
              // Shorting the right side by that same 0.5 cancels it out.
              padding: const EdgeInsets.fromLTRB(6, 0, 5.5, 0),
              child: Text(
                AppLocalizations.of(context)!.siblingsLabel.toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PartnerChips extends StatelessWidget {
  const _PartnerChips({required this.partners, required this.selectedFamilyXref, required this.onSelect});

  final List<TreePartnerFamily> partners;
  final String selectedFamilyXref;
  final void Function(String familyXref) onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final p in partners)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: GestureDetector(
              onTap: () => onSelect(p.familyXref),
              child: Container(
                width: 90,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: p.familyXref == selectedFamilyXref ? const Color(0xFFEEF4FB) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: p.familyXref == selectedFamilyXref ? const Color(0xFF2F6FB0) : const Color(0xFFE5E7EB),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RelationshipIcon(
                      status: p.maritalStatus,
                      size: 11,
                      color: p.familyXref == selectedFamilyXref ? const Color(0xFF2F6FB0) : const Color(0xFF4B5563),
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        p.partner?.firstName ?? '?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: p.familyXref == selectedFamilyXref ? const Color(0xFF2F6FB0) : const Color(0xFF4B5563),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChildrenFrame extends StatelessWidget {
  const _ChildrenFrame({
    required this.partner,
    required this.photoHeaders,
    required this.extraChildrenCount,
    required this.onSelectPerson,
  });

  final TreePartnerFamily partner;
  final Map<String, String> photoHeaders;

  /// Children the active person has with any OTHER partner - shown as a
  /// "+N weitere Kinder" hint on the frame's right edge, since this frame
  /// only ever lists the one currently-selected partner's children.
  final int extraChildrenCount;
  final void Function(String xref) onSelectPerson;

  static const _mainLabelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF), letterSpacing: 0.5);
  static const _extraLabelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6B7280));
  // Both labels' own horizontal padding (6 + 5.5, see where they're used
  // below) plus each one's left:16/right:16 anchor inset.
  static const _labelChromeWidth = 6 + 5.5 + 16;

  double _textWidth(String text, TextStyle style) {
    final painter = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final children = partner.children;
    final mainLabelText = (partner.partner == null
            ? l10n.childrenUnknownParentLabel
            : l10n.childrenWithPartnerLabel(partner.partner!.firstName))
        .toUpperCase();
    final extraLabelText = extraChildrenCount > 0 ? l10n.moreChildrenWithOtherPartnerLabel(extraChildrenCount) : null;

    return Container(
      constraints: BoxConstraints(
        // Both labels float on the same top border, anchored to opposite
        // edges - with only a handful of narrow child cards the frame
        // otherwise shrink-wraps far narrower than the two labels combined
        // need, and they overlap each other. Only enforced when the extra-
        // children label is actually showing; the single-label case never
        // needed it (a lone left-anchored label just ends wherever it ends).
        minWidth: extraLabelText == null
            ? 0
            // Clamped to maxWidth: BoxConstraints throws if min > max, and
            // with a genuinely long partner name plus a long count both
            // labels are already individually ellipsized well before their
            // combined width could get anywhere near this frame's 378 cap.
            : math.min(
                378,
                _textWidth(mainLabelText, _mainLabelStyle) +
                    _textWidth(extraLabelText, _extraLabelStyle) +
                    _labelChromeWidth * 2 +
                    12, // breathing room between the two labels
              ),
        maxWidth: 378,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      // Same label-straddles-the-border treatment as the siblings frame.
      padding: const EdgeInsets.fromLTRB(
        _kFrameHorizontalPadding,
        _kFrameTopPadding,
        _kFrameHorizontalPadding,
        _kFrameBottomPadding,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // No "show more" cutoff - every child is shown, wrapping onto as
          // many rows as needed. There's plenty of room below to grow into,
          // unlike a fixed-height card row.
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              for (final child in children)
                TreeNodeCard(
                  firstName: child.firstName,
                  sex: child.sex,
                  isDead: child.isDead,
                  birthYear: child.birthYear,
                  thumb: child.thumb,
                  photoHeaders: photoHeaders,
                  showChildrenIcon: (child.childrenCount ?? 0) > 0,
                  childrenCount: child.childrenCount ?? 0,
                  onTap: () => onSelectPerson(child.xref),
                ),
            ],
          ),
          // Painted last (on top of the cards above) - same fix as the
          // siblings frame: this label floats above the frame's own top
          // border and can otherwise end up hidden behind the first row of
          // cards.
          Positioned(
            top: _kFrameLabelTopOffset,
            left: 16,
            right: 16,
            // Positioned with both left AND right set gives its child a
            // TIGHT width (frame width - 32), which stretched the label's
            // background across nearly the whole frame - the text itself
            // stayed left-aligned inside it, so the background beyond the
            // text (still the same F4F5F7 as the page) read as a huge gap
            // before the border resumed. Align lets the Container shrink-
            // wrap to its actual (possibly ellipsized) text width while the
            // Positioned's left/right still cap how wide that can get, for
            // a long partner name.
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                color: const Color(0xFFF4F5F7),
                // letterSpacing adds trailing space after the LAST glyph
                // too, not just between glyphs - a plain
                // symmetric(horizontal: 6) therefore looked visibly wider
                // on the right than the left. Shorting the right side by
                // that same 0.5 cancels it out.
                padding: const EdgeInsets.fromLTRB(6, 0, 5.5, 0),
                child: Text(
                  mainLabelText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mainLabelStyle,
                ),
              ),
            ),
          ),
          // Same border-straddling treatment, mirrored to the right edge -
          // a hint that the active person has children with (an)other
          // partner(s) too, not shown in this frame (which only ever lists
          // the one currently-selected partner's children).
          if (extraLabelText != null)
            Positioned(
              top: _kFrameLabelTopOffset,
              right: 16,
              child: Container(
                color: const Color(0xFFF4F5F7),
                padding: const EdgeInsets.fromLTRB(6, 0, 5.5, 0),
                child: Text(extraLabelText, style: _extraLabelStyle),
              ),
            ),
        ],
      ),
    );
  }
}
