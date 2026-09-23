import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/tree_neighborhood.dart';
import '../../state/app_providers.dart';
import '../../state/tree_view_providers.dart';
import '../../widgets/tree_icons.dart';
import '../../widgets/tree_node_card.dart';
import '../search/person_detail_screen.dart';

const _kCardWidth = 90.0;
const _kActiveZoom = 1.22;
const _kChildrenVisibleWithoutExpand = 6;

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
  String? _centeredForXref;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _maybeCenterOnActivePerson(String activeXref) {
    if (_centeredForXref == activeXref) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cardBox = _activeCardKey.currentContext?.findRenderObject() as RenderBox?;
      final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (cardBox == null || viewportBox == null) return;

      final cardCenter = cardBox.localToGlobal(cardBox.size.center(Offset.zero), ancestor: viewportBox);
      final viewportCenter = viewportBox.size.center(Offset.zero);
      final current = _transformController.value;
      final delta = viewportCenter - cardCenter;

      _transformController.value = current.clone()..translateByDouble(delta.dx, delta.dy, 0, 1);
      _centeredForXref = activeXref;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    return Center(child: Text('Konnte nicht laden: ${treeState.error}'));
                  }
                  if (neighborhood == null) {
                    // Shouldn't be reachable (build() always starts loading,
                    // _load() always ends in either data or an error) - but
                    // rendering nothing at all here is exactly how an
                    // unexpected state would look identical to "the button
                    // did nothing", so show something instead of guessing.
                    return const Center(child: Text('Unbekannter Zustand.'));
                  }

                  return Stack(
                    key: _viewportKey,
                    children: [
                      InteractiveViewer(
                        transformationController: _transformController,
                        constrained: false,
                        minScale: 0.5,
                        maxScale: 2.5,
                        boundaryMargin: const EdgeInsets.all(400),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: _TreeContent(
                            neighborhood: neighborhood,
                            selectedPartnerXref: treeState.selectedPartnerXref,
                            childrenExpanded: treeState.childrenExpanded,
                            activeCardKey: _activeCardKey,
                            onSelectPerson: controller.selectPerson,
                            onSelectPartner: controller.selectPartner,
                            onToggleChildren: controller.toggleChildrenExpanded,
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
            tooltip: 'Stammbaum verlassen',
            onPressed: onBack,
          ),
          const Expanded(
            child: Text(
              'Stammbaum',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            color: canUndo ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
            tooltip: 'Zur vorherigen Person',
            onPressed: canUndo ? onUndo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            color: canRedo ? const Color(0xFF374151) : const Color(0xFFD1D5DB),
            tooltip: 'Zur nächsten Person',
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
    required this.childrenExpanded,
    required this.activeCardKey,
    required this.onSelectPerson,
    required this.onSelectPartner,
    required this.onToggleChildren,
    required this.onOpenProfile,
  });

  final TreeNeighborhood neighborhood;
  final String? selectedPartnerXref;
  final bool childrenExpanded;
  final GlobalKey activeCardKey;
  final void Function(String xref) onSelectPerson;
  final void Function(String xref) onSelectPartner;
  final VoidCallback onToggleChildren;
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
        if (partner != null && partner.children.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(width: 2, height: 18, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 10),
          _ChildrenFrame(
            partner: partner,
            photoHeaders: photoHeaders,
            expanded: childrenExpanded,
            onSelectPerson: onSelectPerson,
            onToggleExpand: onToggleChildren,
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
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -8,
            left: 16,
            child: Container(
              color: const Color(0xFFF4F5F7),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: const Text(
                'GESCHWISTER',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
              ),
            ),
          ),
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
    required this.expanded,
    required this.onSelectPerson,
    required this.onToggleExpand,
  });

  final TreePartnerFamily partner;
  final Map<String, String> photoHeaders;
  final bool expanded;
  final void Function(String xref) onSelectPerson;
  final VoidCallback onToggleExpand;

  @override
  Widget build(BuildContext context) {
    final children = partner.children;
    final shown = expanded ? children : children.take(_kChildrenVisibleWithoutExpand).toList();
    final remaining = children.length - shown.length;

    return Container(
      constraints: const BoxConstraints(maxWidth: 378),
      margin: const EdgeInsets.symmetric(horizontal: 6),
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: -8,
            left: 16,
            right: 16,
            child: Container(
              color: const Color(0xFFF4F5F7),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              // A long partner name (compound surnames are common) must not
              // overflow past the frame's own border uncontrolled.
              child: Text(
                partner.partner == null ? 'KINDER, ELTERNTEIL UNBEKANNT' : 'KINDER MIT ${partner.partner!.firstName.toUpperCase()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  for (final child in shown)
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
              if (remaining > 0 || expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    onPressed: onToggleExpand,
                    child: Text(expanded ? 'Weniger anzeigen' : 'Alle ${children.length} anzeigen'),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
