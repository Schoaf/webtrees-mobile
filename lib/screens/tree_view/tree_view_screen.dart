import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../models/surname_colors.dart';
import '../../models/tree_lineage.dart';
import '../../models/tree_neighborhood.dart';
import '../../state/app_providers.dart';
import '../../state/tree_generations.dart';
import '../../state/tree_view_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/device_size.dart';
import '../../utils/tab_navigation.dart';
import '../../widgets/load_error_view.dart';
import '../../widgets/tablet_bounded_body.dart';
import '../../widgets/tree_icons.dart';
import '../../widgets/tree_lineage_chart.dart';
import '../../widgets/tree_node_card.dart';

const _kCardWidth = 90.0;
const _kActiveZoom = 1.22;
const _kMinScale = 0.5;
const _kMaxScale = 2.5;
// A partner card is drawn at least this tall so it never reads as one of
// the (shorter) sibling cards - the active person's own card matches it,
// so the pair reads as a consistent height even when the active card's
// content is short.
const _kPartnerCardMinHeight = 185.0;
// Roughly one _PartnerChips row's own height (its top spacing + padding +
// content) - subtracted twice from the partner card's min height when the
// switcher chips are showing below it, so partner-card-plus-chips doesn't
// end up taller overall than a lone partner card on its own.
const _kPartnerChipHeight = 22.0;

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
  const TreeViewScreen({super.key, required this.xref, this.isVisible = true, this.isEnteringOnlyWhenEmpty = false});

  /// The person this view was opened for: entered into the app's one tree
  /// history when the view opens (see TreeViewController.enter), and where
  /// the "center" button jumps back to.
  final String xref;

  /// The Stammbaum tab: only enter [xref] if the tree has never been
  /// entered yet - otherwise keep showing wherever the history currently
  /// stands (the tab is expected to look as it was left).
  final bool isEnteringOnlyWhenEmpty;

  /// False while kept alive offstage, as the Stammbaum tab is in the
  /// bottom bar's `IndexedStack` while another tab shows: centering on a
  /// new person waits until the tab shows - measured offstage, it landed
  /// wrong. Switching back to the tab keeps the view exactly as it was
  /// left, zoom and pan included.
  final bool isVisible;

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
  // The parents row and the siblings frame: what the initial fit shows
  // (not the children frame below, which stays reachable by panning down,
  // nor further generations above or below - #42).
  final _parentsRowKey = GlobalKey();
  final _siblingsFrameKey = GlobalKey();
  // The outermost rows of further generations, for ∞ to see when to load
  // the next one.
  final _topRowKey = GlobalKey();
  final _bottomRowKey = GlobalKey();
  String? _centeredForXref;

  // ∞ (#42): the generations up and down loaded so far for this person -
  // one more each time only one is left outside the view.
  static const _kInfiniteStart = 2;
  int _infiniteUp = _kInfiniteStart;
  int _infiniteDown = _kInfiniteStart;
  String? _infiniteForXref;

  // Where the siblings frame was in the content, last frame: when rows are
  // added above it (more generations), the view moves along so it stays put
  // on the screen instead of the new rows pushing it away.
  Offset? _anchor;
  String? _anchorXref;

  // The generations up and down shown last, for this person - to notice
  // when fewer are picked.
  int? _shownUp;
  int? _shownDown;
  String? _shownForXref;

  // Colours by surname (#43): kept for the whole time the tree is open, so
  // a family keeps its colour when moving to another person.
  final _surnameColors = SurnameColors();
  bool _isLegendOpen = false;

  @override
  void initState() {
    super.initState();
    _transformController.addListener(_maybeLoadMoreGenerations);
    // After this frame: changing a provider while widgets build is not allowed.
    Future.microtask(() {
      if (!mounted) return;
      final controller = ref.read(treeViewControllerProvider.notifier);
      if (!widget.isEnteringOnlyWhenEmpty || ref.read(treeViewControllerProvider).history.isEmpty) {
        controller.enter(widget.xref);
      }
    });
  }

  @override
  void dispose() {
    _transformController.removeListener(_maybeLoadMoreGenerations);
    _transformController.dispose();
    super.dispose();
  }

  /// The first time: fits and positions the view on the family group
  /// (parents + siblings frame) - horizontally centered, zoomed so the whole
  /// group is visible, with the parents row near the top rather than the
  /// active card at the canvas's dead center (that wasted space above the
  /// parents row and often cut off siblings on a narrow phone screen).
  /// After that, a new active person keeps the zoom; only their siblings
  /// frame moves to the middle.
  void _maybeCenterOnActivePerson(String activeXref) {
    if (_centeredForXref == activeXref || !widget.isVisible) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final siblingsRect = _rectInContent(_siblingsFrameKey);
      final parentsRect = _rectInContent(_parentsRowKey);
      final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      if (siblingsRect == null || viewportBox == null) return;

      final viewportSize = viewportBox.size;

      // Another person after the first: keep the zoom - with several
      // generations a new fit zoomed far out - and only bring their
      // siblings frame to the middle.
      if (_centeredForXref != null) {
        final scale = _transformController.value.getMaxScaleOnAxis();
        _transformController.value = Matrix4.identity()
          ..translateByDouble(viewportSize.width / 2, viewportSize.height / 2, 0, 1)
          ..scaleByDouble(scale, scale, scale, 1)
          ..translateByDouble(-siblingsRect.center.dx, -siblingsRect.center.dy, 0, 1);
        _centeredForXref = activeXref;
        return;
      }

      final group = parentsRect == null ? siblingsRect : siblingsRect.expandToInclude(parentsRect);
      final groupTopLeft = group.topLeft;
      final groupSize = group.size;
      final scale = _fitScale(groupSize, viewportSize);

      final groupCenterX = groupTopLeft.dx + groupSize.width / 2;
      final groupTopY = groupTopLeft.dy;

      const topPadding = 24.0;
      _transformController.value = Matrix4.identity()
        ..translateByDouble(viewportSize.width / 2, topPadding, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-groupCenterX, -groupTopY, 0, 1);
      _centeredForXref = activeXref;
    });
  }

  /// The zoom that fits [size] into [viewportSize], with some room around it.
  double _fitScale(Size size, Size viewportSize) {
    const padding = 24.0;
    final scaleByWidth = (viewportSize.width - 2 * padding) / size.width;
    final scaleByHeight = (viewportSize.height - 2 * padding) / size.height;
    return math.min(scaleByWidth, scaleByHeight).clamp(_kMinScale, _kMaxScale);
  }

  /// After picking fewer generations (#42): if the view is zoomed out
  /// further than the whole, now smaller tree needs, it is centred and
  /// zoomed in so the tree fills the view - but never closer than the
  /// starting view on parents and siblings. Zoomed in further, it stays.
  void _maybeFitAfterFewerGenerations() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contentBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
      final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
      final siblingsRect = _rectInContent(_siblingsFrameKey);
      final parentsRect = _rectInContent(_parentsRowKey);
      if (contentBox == null || viewportBox == null || siblingsRect == null) return;

      final contentSize = contentBox.size;
      final viewportSize = viewportBox.size;
      final fitScale = _fitScale(contentSize, viewportSize);
      if (_transformController.value.getMaxScaleOnAxis() >= fitScale) return;

      final group = parentsRect == null ? siblingsRect : siblingsRect.expandToInclude(parentsRect);
      final scale = math.min(fitScale, _fitScale(group.size, viewportSize));
      _transformController.value = Matrix4.identity()
        ..translateByDouble(viewportSize.width / 2, viewportSize.height / 2, 0, 1)
        ..scaleByDouble(scale, scale, scale, 1)
        ..translateByDouble(-contentSize.width / 2, -contentSize.height / 2, 0, 1);
    });
  }

  /// Where [key]'s widget is in the content's own (untransformed) space.
  Rect? _rectInContent(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final contentBox = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || contentBox == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: contentBox) & box.size;
  }

  /// Where [key]'s widget is on the screen, relative to the viewport.
  Rect? _rectInViewport(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || viewportBox == null || !box.attached) return null;
    return box.localToGlobal(Offset.zero, ancestor: viewportBox) &
        (box.size * _transformController.value.getMaxScaleOnAxis());
  }

  /// After a frame: keeps the siblings frame where it was on the screen when
  /// the content around it changed (#42), then lets ∞ check for more.
  void _afterFrame(String activeXref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _rectInContent(_siblingsFrameKey)?.topLeft;
      if (anchor == null) return;
      final previous = _anchor;
      if (previous != null && _anchorXref == activeXref && anchor != previous) {
        final shift = anchor - previous;
        _transformController.value = _transformController.value.clone()..translateByDouble(-shift.dx, -shift.dy, 0, 1);
      }
      _anchor = anchor;
      _anchorXref = activeXref;
      _maybeLoadMoreGenerations();
    });
  }

  /// ∞ (#42): one more generation up or down whenever only one more is left
  /// outside the view - also after zooming out, until the view is filled.
  void _maybeLoadMoreGenerations() {
    if (!mounted || ref.read(treeGenerationsProvider) != null) return;
    final xref = ref.read(treeViewControllerProvider).activeXref;
    final viewportBox = _viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (xref == null || xref != _infiniteForXref || viewportBox == null) return;
    final lineage = ref.read(treeLineageProvider(xref));

    final top = _rectInViewport(_topRowKey) ?? _rectInViewport(_parentsRowKey);
    if (top != null &&
        !lineage.isLoadingAncestors &&
        lineage.ancestorGenerations >= _infiniteUp &&
        lineage.hasMoreAncestors &&
        top.top > -top.height * 1.3) {
      setState(() => _infiniteUp++);
    }

    final bottom = _rectInViewport(_bottomRowKey);
    if (bottom != null &&
        !lineage.isLoadingDescendants &&
        lineage.descendantGenerations >= _infiniteDown &&
        lineage.hasMoreDescendants &&
        bottom.bottom < viewportBox.size.height + bottom.height * 1.3) {
      setState(() => _infiniteDown++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final treeState = ref.watch(treeViewControllerProvider);
    final controller = ref.read(treeViewControllerProvider.notifier);
    final neighborhood = treeState.activeNeighborhood;
    final activeXref = treeState.activeXref;

    // Generations up and down (#42): the picked number, or for ∞ as many
    // as loaded so far - starting over for every person.
    final pickedGenerations = ref.watch(treeGenerationsProvider);
    final isShowingSurnames = ref.watch(treeSurnamesProvider);
    final isColouringSurnames = ref.watch(treeSurnameColorsProvider);
    if (activeXref != _infiniteForXref) {
      _infiniteForXref = activeXref;
      _infiniteUp = _kInfiniteStart;
      _infiniteDown = _kInfiniteStart;
    }
    final generationsUp = pickedGenerations ?? _infiniteUp;
    final generationsDown = pickedGenerations ?? _infiniteDown;
    final lineage = activeXref == null || (generationsUp <= 1 && generationsDown <= 1)
        ? const TreeLineage()
        : ref.watch(treeLineageProvider(activeXref));
    if (activeXref != null && (generationsUp > 1 || generationsDown > 1)) {
      // After this frame: changing a provider while widgets build is not allowed.
      Future.microtask(() {
        if (!mounted) return;
        final lineageController = ref.read(treeLineageProvider(activeXref).notifier);
        lineageController.ensureAncestors(generationsUp);
        lineageController.ensureDescendants(generationsDown);
      });
    }

    // Colours by surname (#43): the people in view, counted once each.
    final surnamesInView = isColouringSurnames && neighborhood != null
        ? _surnamesInView(
            neighborhood,
            treeState.selectedPartnerXref,
            lineage,
            generationsUp,
            generationsDown,
            treeState.cache,
          )
        : null;
    final surnameColors = surnamesInView == null ? null : _surnameColors.assign(surnamesInView);

    if (neighborhood != null) {
      // The partners' own names (a married name) come with their own answer.
      Future.microtask(() {
        if (!mounted) return;
        for (final partner in neighborhood.partners) {
          if (partner.partner != null) controller.prefetch(partner.partner!.xref);
        }
      });
      _maybeCenterOnActivePerson(activeXref!);
      _afterFrame(activeXref);
      final isShowingFewer = pickedGenerations != null &&
          _shownForXref == activeXref &&
          (generationsUp < (_shownUp ?? 0) || generationsDown < (_shownDown ?? 0));
      if (isShowingFewer) _maybeFitAfterFewerGenerations();
      _shownUp = generationsUp;
      _shownDown = generationsDown;
      _shownForXref = activeXref;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SafeArea(
        child: Column(
          children: [
            // Matches every other screen's own top-bar width - the canvas
            // below stays full-width, deliberately (see TabletBoundedBody's
            // own doc comment): panning into extra tablet space there is
            // the point, unlike a fixed top bar.
            TabletBoundedBody(
              maxWidth: tabletBoundedMaxWidth(context),
              child: _TopBar(
                canUndo: treeState.canUndo,
                canRedo: treeState.canRedo,
                // Null on the Stammbaum tab, where the tree is the tab's first
                // page: popping there removed the app's whole main page (#32).
                onBack: isFirstPage(context) ? null : () => Navigator.of(context).maybePop(),
                onUndo: controller.undo,
                onRedo: controller.redo,
                // Back to the person this view was opened for - shown only
                // while someone else is in focus.
                onCenter: treeState.activeXref == null || treeState.activeXref == widget.xref
                    ? null
                    : () => controller.enter(widget.xref),
              ),
            ),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (neighborhood == null && treeState.loading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (neighborhood == null && treeState.error != null) {
                    return LoadErrorView(
                      message: l10n.couldNotLoad(
                        treeState.error ?? l10n.genericErrorFallback,
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
                          child: _SurnamesShown(
                            isShowing: isShowingSurnames,
                            child: _SurnameColorsScope(
                              colors: surnameColors,
                              child: _TreeContent(
                              neighborhood: neighborhood,
                              selectedPartnerXref: treeState.selectedPartnerXref,
                              loaded: treeState.cache,
                              activeCardKey: _activeCardKey,
                              parentsRowKey: _parentsRowKey,
                              siblingsFrameKey: _siblingsFrameKey,
                              topRowKey: _topRowKey,
                              bottomRowKey: _bottomRowKey,
                              generationsUp: generationsUp,
                              generationsDown: generationsDown,
                              lineage: lineage,
                              onSelectPerson: controller.selectPerson,
                              onSelectPartner: controller.selectPartner,
                              onOpenProfile: (xref) => openPerson(context, xref),
                            ),
                            ),
                          ),
                        ),
                      ),
                      if (treeState.loading || lineage.isLoadingAncestors || lineage.isLoadingDescendants)
                        const Positioned(
                          top: 12,
                          left: 12,
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        ),
                      if (surnameColors != null && surnameColors.isNotEmpty)
                        Positioned(
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: _SurnameLegend(
                            colors: surnameColors,
                            surnames: surnamesInView!,
                            isOpen: _isLegendOpen,
                            onToggle: () => setState(() => _isLegendOpen = !_isLegendOpen),
                          ),
                        ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: _ViewButton(
                          generations: pickedGenerations,
                          isShowingSurnames: isShowingSurnames,
                          isColouringSurnames: isColouringSurnames,
                          onSelectGenerations: ref.read(treeGenerationsProvider.notifier).set,
                          onToggleSurnames: () => ref.read(treeSurnamesProvider.notifier).set(!isShowingSurnames),
                          onToggleColours: () => ref.read(treeSurnameColorsProvider.notifier).set(!isColouringSurnames),
                        ),
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
    required this.onCenter,
  });

  final VoidCallback? onCenter;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback? onBack;
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
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF6B7280)),
              tooltip: l10n.leaveTreeTooltip,
              onPressed: onBack,
            )
          else
            // Keeps the title centered between left and right.
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              l10n.treeViewTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF111827)),
            ),
          ),
          if (onCenter != null)
            IconButton(
              key: const Key('treeCenterButton'),
              icon: const Icon(Icons.gps_fixed, size: 20),
              color: const Color(0xFF374151),
              tooltip: l10n.treeCenterTooltip,
              onPressed: onCenter,
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
    required this.loaded,
    required this.activeCardKey,
    required this.parentsRowKey,
    required this.siblingsFrameKey,
    required this.topRowKey,
    required this.bottomRowKey,
    required this.generationsUp,
    required this.generationsDown,
    required this.lineage,
    required this.onSelectPerson,
    required this.onSelectPartner,
    required this.onOpenProfile,
  });

  final TreeNeighborhood neighborhood;
  final String? selectedPartnerXref;

  /// Everyone loaded so far by xref - the partner's own names come from here.
  final Map<String, TreeNeighborhood> loaded;
  final GlobalKey activeCardKey;

  /// See _TreeViewScreenState's own doc comments on the fields these are
  /// passed from.
  final GlobalKey parentsRowKey;
  final GlobalKey siblingsFrameKey;
  final GlobalKey topRowKey;
  final GlobalKey bottomRowKey;
  final int generationsUp;
  final int generationsDown;
  final TreeLineage lineage;
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

    final hasParents = neighborhood.father != null || neighborhood.mother != null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasParents && generationsUp > 1)
              _AncestorsSection(
                neighborhood: neighborhood,
                lineage: lineage,
                generations: generationsUp,
                photoHeaders: photoHeaders,
                parentsRowKey: parentsRowKey,
                topRowKey: topRowKey,
                onSelectPerson: onSelectPerson,
              )
            else if (hasParents) ...[
              KeyedSubtree(
                key: parentsRowKey,
                child: _ParentsRow(
                  neighborhood: neighborhood,
                  photoHeaders: photoHeaders,
                  onSelectPerson: onSelectPerson,
                ),
              ),
              // Joined to the parents: from the fork below two of them (see
              // _ParentsRow) or the only parent's card down to the siblings frame.
              Builder(
                builder: (context) {
                  final color = _SurnameColorsScope.lineOf(context, neighborhood.person.surname);
                  if (color == null) return Container(width: 2, height: 34, color: const Color(0xFFD1D5DB));
                  // Wide in the person's colour, with a grey edge on both sides.
                  return Container(
                    width: colouredLineWidth + 2,
                    height: 34,
                    color: treeOutlineColor,
                    alignment: Alignment.center,
                    child: Container(width: colouredLineWidth, color: color),
                  );
                },
              ),
            ],
            _SiblingsFrame(
              key: siblingsFrameKey,
              neighborhood: neighborhood,
              partner: partner,
              partnerDetail: partner?.partner == null ? null : loaded[partner!.partner!.xref]?.personDetail,
              photoHeaders: photoHeaders,
              activeCardKey: activeCardKey,
              onSelectPerson: onSelectPerson,
              onSelectPartner: onSelectPartner,
              onOpenProfile: onOpenProfile,
            ),
          ],
        ),
        if (partner != null && partner.children.isNotEmpty)
          _ChildrenFrameSection(
            partner: partner,
            photoHeaders: photoHeaders,
            // Children with any OTHER partner - "Kinder mit X" only shows
            // this one family, so without this there was no hint at all
            // that the active person has children elsewhere too.
            extraChildrenCount: neighborhood.partners
                .where((p) => p.familyXref != partner.familyXref)
                .fold(0, (n, p) => n + p.children.length),
            // Tapping the "+N weitere Kinder" hint cycles to the next
            // partner in the list, same as the chips above the active
            // card do - a quicker way to flip through partners' children
            // than scrolling back up to tap a chip.
            onTapExtraChildren: () {
              final i = neighborhood.partners.indexWhere((p) => p.familyXref == partner.familyXref);
              final next = neighborhood.partners[(i + 1) % neighborhood.partners.length];
              onSelectPartner(next.familyXref);
            },
            descendants: generationsDown > 1 ? _descendantsOf(partner) : null,
            generations: generationsDown,
            bottomRowKey: bottomRowKey,
            onSelectPerson: onSelectPerson,
          ),
      ],
    );
  }

  /// The children with [partner], with their own descendants as far as
  /// loaded - the cards themselves from the Individual answer, as on
  /// generation 1.
  List<TreeDescendant> _descendantsOf(TreePartnerFamily partner) {
    final family = lineage.descendants?.families.where((f) => f.familyXref == partner.familyXref).firstOrNull;
    return [
      for (final child in partner.children)
        TreeDescendant(
          node: child,
          families: family?.children.where((d) => d.node.xref == child.xref).firstOrNull?.families ?? const [],
        ),
    ];
  }
}

/// The parents with the generations above them (#42), on the picked
/// number of generations - one is the plain parents row.
class _AncestorsSection extends StatelessWidget {
  const _AncestorsSection({
    required this.neighborhood,
    required this.lineage,
    required this.generations,
    required this.photoHeaders,
    required this.parentsRowKey,
    required this.topRowKey,
    required this.onSelectPerson,
  });

  final TreeNeighborhood neighborhood;
  final TreeLineage lineage;
  final int generations;
  final Map<String, String> photoHeaders;
  final GlobalKey parentsRowKey;
  final GlobalKey topRowKey;
  final void Function(String xref) onSelectPerson;

  @override
  Widget build(BuildContext context) {
    final father = neighborhood.father;
    final mother = neighborhood.mother;
    // The parents as the Individual answer has them (with their counts);
    // the generations above from the pedigree, only above the same parent.
    final ancestors = <int, TreeNode>{
      for (final entry in lineage.ancestors.entries)
        if (entry.key > 3 && _isAbove(entry.key, father, mother)) entry.key: entry.value,
      2: ?father,
      3: ?mother,
    };

    return AncestorChart(
      ancestors: ancestors,
      generations: generations,
      // Room for the "+N" badges below the parents, as in the plain row.
      bottomBandHeight: 48,
      parentsRowKey: parentsRowKey,
      topRowKey: topRowKey,
      lineColorOf: (node) => _SurnameColorsScope.lineOf(context, node.surname),
      rootLineColor: _SurnameColorsScope.lineOf(context, neighborhood.person.surname),
      cardBuilder: (n, node, {required isShowingParents}) => n <= 3
          ? _ParentCard(
              neighborhood: neighborhood,
              node: node,
              isFather: n == 2,
              isShowingAncestorsIcon: !isShowingParents && (node.hasParents ?? false),
              photoHeaders: photoHeaders,
              onSelectPerson: onSelectPerson,
            )
          : TreeNodeCard(
              firstName: node.firstName,
              surname: _SurnamesShown.of(context) ? node.surname : null,
              backgroundColor: _SurnameColorsScope.of(context, node.surname),
              isSurnameBold: false,
              sex: node.sex,
              isDead: node.isDead,
              birthYear: node.birthYear,
              thumb: node.thumb,
              photoHeaders: photoHeaders,
              showAncestorsIcon: !isShowingParents && (node.hasParents ?? false),
              onTap: () => onSelectPerson(node.xref),
            ),
    );
  }

  /// Whether the pedigree's ancestor [n] is above the parent shown here -
  /// the pedigree could take another parent family than the Individual
  /// answer.
  bool _isAbove(int n, TreeNode? father, TreeNode? mother) {
    var parent = n;
    while (parent > 3) {
      parent ~/= 2;
    }
    final shown = parent == 2 ? father : mother;
    return shown != null && lineage.ancestors[parent]?.xref == shown.xref;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

// Room below two parents for their "+N" badges - and for the fork joining
// the lines down from them.
const _kParentsRowBottomPadding = 14.0;
const _kParentsGap = 10.0;

/// Lines down from the middle of two same-width parent cards, [gap] apart,
/// joined by a bar along the bottom edge.
class _ParentsForkPainter extends CustomPainter {
  _ParentsForkPainter({required this.gap, this.fatherColor, this.motherColor, this.childColor});

  final double gap;

  /// Each parent's half of the fork in the colour of their surname (#43).
  final Color? fatherColor;
  final Color? motherColor;

  /// The line on down to the child, in theirs.
  final Color? childColor;

  @override
  void paint(Canvas canvas, Size size) {
    final cardWidth = (size.width - gap) / 2;
    final father = cardWidth / 2;
    final mother = size.width - cardWidth / 2;
    final middle = size.width / 2;
    // Halfway down: room for a wide line, and its own short stem on to the
    // line below.
    final bar = size.height / 2;
    canvas.clipRect(Offset.zero & size);
    drawTreeLines(canvas, [
      for (final (x, color) in [(father, fatherColor), (mother, motherColor)]) ...[
        (Offset(x, 0), Offset(x, bar), color),
        (Offset(x, bar), Offset(middle, bar), color),
      ],
      (Offset(middle, bar), Offset(middle, size.height), childColor),
    ]);
  }

  @override
  bool shouldRepaint(_ParentsForkPainter old) =>
      old.gap != gap || old.fatherColor != fatherColor || old.motherColor != motherColor || old.childColor != childColor;
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

    Widget parentCard(TreeNode node, {required bool isFather}) => _ParentCard(
      neighborhood: neighborhood,
      node: node,
      isFather: isFather,
      isShowingAncestorsIcon: node.hasParents ?? false,
      photoHeaders: photoHeaders,
      onSelectPerson: onSelectPerson,
    );

    if (father != null && mother != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: _kParentsRowBottomPadding),
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                parentCard(father, isFather: true),
                const SizedBox(width: _kParentsGap),
                parentCard(mother, isFather: false),
              ],
            ),
            // A line down from each parent, joined below them - the line
            // down to the person goes on from the middle of it.
            Positioned(
              left: 0,
              right: 0,
              bottom: -_kParentsRowBottomPadding,
              height: _kParentsRowBottomPadding,
              child: CustomPaint(
                painter: _ParentsForkPainter(
                  gap: _kParentsGap,
                  fatherColor: _SurnameColorsScope.lineOf(context, father.surname),
                  motherColor: _SurnameColorsScope.lineOf(context, mother.surname),
                  childColor: _SurnameColorsScope.lineOf(context, neighborhood.person.surname),
                ),
              ),
            ),
            // Vertically centered on the cards beside it (Stack already
            // sizes itself to the Row before laying out Positioned
            // children, so filling+centering lands on the actual card
            // height rather than a number tuned for one specific height) -
            // horizontally lands in the gap between the two same-width
            // cards, same as the Stack's topCenter alignment achieved for a
            // plain Positioned(top:...) with no left/right of its own.
            Positioned.fill(
              child: Align(child: _RelationshipBubble(status: MaritalStatus.married)),
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

/// A parent's card, with a "+N" badge below for children with another
/// partner.
class _ParentCard extends StatelessWidget {
  const _ParentCard({
    required this.neighborhood,
    required this.node,
    required this.isFather,
    required this.isShowingAncestorsIcon,
    required this.photoHeaders,
    required this.onSelectPerson,
  });

  final TreeNeighborhood neighborhood;
  final TreeNode node;
  final bool isFather;
  final bool isShowingAncestorsIcon;
  final Map<String, String> photoHeaders;
  final void Function(String xref) onSelectPerson;

  @override
  Widget build(BuildContext context) {
    final extra = isFather ? neighborhood.extraChildrenFather : neighborhood.extraChildrenMother;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        TreeNodeCard(
          firstName: node.firstName,
          surname: _SurnamesShown.of(context) ? node.surname : null,
          backgroundColor: _SurnameColorsScope.of(context, node.surname),
          isSurnameBold: false,
          sex: node.sex,
          isDead: node.isDead,
          birthYear: node.birthYear,
          thumb: node.thumb,
          photoHeaders: photoHeaders,
          showAncestorsIcon: isShowingAncestorsIcon,
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
                    color: _kBadgeBackground,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TreeBranchIcon(pointingUp: false, size: 9, color: const Color(0xFF6B7280)),
                      const SizedBox(width: 1),
                      Text(
                        '+$extra',
                        style: const TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// 1.5x the original 22px/13px - see _kRelationshipBadgeSize in
// tree_node_card.dart, which mirrors this size for the info button.
const _kRelationshipBubbleSize = 33.0;
const _kRelationshipIconSize = 19.5;
// Matches _kBadgeBackground in tree_node_card.dart - a touch off pure
// white, distinctly lighter than the page's own canvas background
// (0xFFF4F5F7).
const _kBadgeBackground = Color(0xFFF8F9FA);

class _RelationshipBubble extends StatelessWidget {
  const _RelationshipBubble({required this.status});

  final MaritalStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _kRelationshipBubbleSize,
      height: _kRelationshipBubbleSize,
      decoration: BoxDecoration(
        color: _kBadgeBackground,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [BoxShadow(color: Color(0x38111827), blurRadius: 6, offset: Offset(0, 2))],
      ),
      alignment: Alignment.center,
      child: RelationshipIcon(status: status, size: _kRelationshipIconSize, color: const Color(0xFF4B5563)),
    );
  }
}

class _SiblingsFrame extends StatelessWidget {
  const _SiblingsFrame({
    super.key,
    required this.neighborhood,
    required this.partner,
    required this.partnerDetail,
    required this.photoHeaders,
    required this.activeCardKey,
    required this.onSelectPerson,
    required this.onSelectPartner,
    required this.onOpenProfile,
  });

  final TreeNeighborhood neighborhood;
  final TreePartnerFamily? partner;

  /// The partner's own names (a married name), once loaded - see
  /// TreeViewController.prefetch.
  final TreePersonDetail? partnerDetail;
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
        surname: _SurnamesShown.of(context) ? node.surname : null,
        backgroundColor: _SurnameColorsScope.of(context, node.surname),
        isSurnameBold: false,
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
        surname: neighborhood.person.surname,
        backgroundColor: _SurnameColorsScope.of(context, neighborhood.person.surname),
        sex: neighborhood.person.sex,
        isDead: neighborhood.person.isDead,
        birthYear: neighborhood.person.birthYear,
        thumb: neighborhood.person.thumb,
        photoHeaders: photoHeaders,
        selected: true,
        width: _kCardWidth * _kActiveZoom,
        // At least as tall as the partner card next to it, so a short
        // active-person card (few facts, no detail overflow) doesn't
        // visually dangle shorter than a taller partner card beside it.
        minHeight: _kPartnerCardMinHeight,
        showInfoButton: true,
        detail: neighborhood.personDetail,
        onInfoTap: () => onOpenProfile(neighborhood.person.xref),
        // A double tap on the selected person opens them too - the info
        // button gets small in a zoomed-out tree. Double, so a stray tap
        // doesn't leave the tree.
        onDoubleTap: () => onOpenProfile(neighborhood.person.xref),
      ),
    );

    final partnerSurname = (partnerDetail?.hasOtherMarriedSurname ?? false)
        ? partnerDetail!.marriedSurname
        : partner?.partner?.surname ?? '';

    Widget centerGroup;
    if (partner == null) {
      centerGroup = activeCard;
    } else {
      final p = partner!;
      const gap = 10.0;
      const activeWidth = _kCardWidth * _kActiveZoom;
      final showChips = neighborhood.partners.length > 1;
      // The partner card gets shorter by two chips' worth of height when
      // the switcher chips are showing below it, so partner-card-plus-
      // chips doesn't end up taller overall than a lone partner card would
      // be on its own.
      final partnerMinHeight = showChips ? _kPartnerCardMinHeight - 2 * _kPartnerChipHeight : _kPartnerCardMinHeight;
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
                // Nudged further down than the active card beside it -
                // was 10.
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  children: [
                    p.partner == null
                        ? UnknownPersonCard(minHeight: partnerMinHeight)
                        : TreeNodeCard(
                            firstName: p.partner!.firstName,
                            // A married name other than the birth name first, the
                            // birth name below it. Bold only when it differs from
                            // the active person's surname.
                            surname: partnerSurname,
                            isSurnameBold: partnerSurname != neighborhood.person.surname,
                            // The colour of the family they come from.
                            backgroundColor: _SurnameColorsScope.of(
                              context,
                              (partnerDetail?.birthSurname.isNotEmpty ?? false)
                                  ? partnerDetail!.birthSurname
                                  : p.partner!.surname,
                            ),
                            birthSurname: (partnerDetail?.hasOtherMarriedSurname ?? false)
                                ? partnerDetail!.birthSurname
                                : null,
                            sex: p.partner!.sex,
                            isDead: p.partner!.isDead,
                            birthYear: p.partner!.birthYear,
                            thumb: p.partner!.thumb,
                            photoHeaders: photoHeaders,
                            showAncestorsIcon: p.partner!.hasParents ?? false,
                            ancestorsIconOnRight: true,
                            minHeight: partnerMinHeight,
                            onTap: () => onSelectPerson(p.partner!.xref),
                          ),
                    if (showChips) ...[
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
            left: activeWidth + gap / 2 - _kRelationshipBubbleSize / 2,
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
            // Matches "KINDER MIT X"'s left:6 in _ChildrenFrame - both
            // frame labels sit at the same distance from their frame's
            // edge now.
            left: 6,
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

/// Wraps the connector line above the children frame AND the frame itself
/// in one Stack, so the "+N weitere Kinder" chip - Positioned on top of
/// that combined Stack, straddling the frame's own top border like the
/// other frame labels - always lands inside a real, hit-testable
/// RenderBox. Nesting the chip inside the frame's OWN inner Stack (as
/// _ChildrenFrame used to) meant any position on the border line landed
/// partly above that inner Stack's box (which starts exactly at the
/// border) - a Column only ever dispatches a tap to whichever child's own
/// allocated box contains that point, so taps in that sliver went to the
/// connector-line gap above instead, an inert sibling. Here that gap is
/// part of the SAME box as the frame, so every point on the chip - above
/// the border or below it - is inside this widget's own hit-testable area.
class _ChildrenFrameSection extends StatelessWidget {
  const _ChildrenFrameSection({
    required this.partner,
    required this.photoHeaders,
    required this.extraChildrenCount,
    required this.onTapExtraChildren,
    required this.descendants,
    required this.generations,
    required this.bottomRowKey,
    required this.onSelectPerson,
  });

  final TreePartnerFamily partner;
  final Map<String, String> photoHeaders;
  final int extraChildrenCount;
  final VoidCallback onTapExtraChildren;

  /// The children with their descendants on more than one generation (#42),
  /// else null.
  final List<TreeDescendant>? descendants;
  final int generations;
  final GlobalKey bottomRowKey;
  final void Function(String xref) onSelectPerson;

  // The line touches both frames - no gaps, so it reads as one link from
  // the person to their children.
  static const _connectorTopGap = 0.0;
  static const _connectorHeight = 38.0;
  static const _connectorBottomGap = 0.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final extraLabelText = extraChildrenCount > 0 ? l10n.moreChildrenWithOtherPartnerLabel(extraChildrenCount) : null;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: _connectorTopGap),
            Container(width: 2, height: _connectorHeight, color: const Color(0xFFD1D5DB)),
            const SizedBox(height: _connectorBottomGap),
            _ChildrenFrame(
              partner: partner,
              photoHeaders: photoHeaders,
              extraLabelText: extraLabelText,
              descendants: descendants,
              generations: generations,
              bottomRowKey: bottomRowKey,
              onSelectPerson: onSelectPerson,
            ),
          ],
        ),
        if (extraLabelText != null)
          Positioned(
            // _kFrameLabelTopOffset positions the plain-text frame labels
            // straddling the border, relative to a frame's OWN padded
            // content (whose origin sits _kFrameTopPadding below the
            // border) - so landing the chip on that same line, relative to
            // THIS Stack instead, needs the connector's full height ABOVE
            // the border (_connectorTopGap+_connectorHeight+
            // _connectorBottomGap) plus that same _kFrameTopPadding back
            // (forgetting it here once put the chip a full 12px too high -
            // not on the line at all). The extra -3 matches the exact
            // pre-hit-test-bug position, the last one visually approved.
            top: _connectorTopGap + _connectorHeight + _connectorBottomGap + _kFrameTopPadding + _kFrameLabelTopOffset - 3,
            // _ChildrenFrame's own chip anchor (right: 6, relative to its
            // padded content) plus its horizontal padding (10) and outer
            // margin (6), to land at the same spot relative to the frame's
            // real right edge now that this Positioned is one level up.
            right: 6 + _kFrameHorizontalPadding + 6,
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              child: InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: onTapExtraChildren,
                child: Container(
                  padding: _ChildrenFrame._chipPadding,
                  decoration: BoxDecoration(
                    color: _ChildrenFrame._kChipBackground,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFE5E7EB), width: _ChildrenFrame._chipBorderWidth),
                  ),
                  child: Text(extraLabelText, style: _ChildrenFrame._chipTextStyle),
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
    required this.extraLabelText,
    required this.descendants,
    required this.generations,
    required this.bottomRowKey,
    required this.onSelectPerson,
  });

  final TreePartnerFamily partner;
  final Map<String, String> photoHeaders;

  /// Precomputed by _ChildrenFrameSection (which also positions the chip
  /// itself, now rendered one level up - see its doc comment) - only used
  /// here to reserve enough width via [minWidth] so the two labels never
  /// overlap.
  final String? extraLabelText;

  /// See _ChildrenFrameSection.
  final List<TreeDescendant>? descendants;
  final int generations;
  final GlobalKey bottomRowKey;
  final void Function(String xref) onSelectPerson;

  static const _mainLabelStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF9CA3AF), letterSpacing: 0.5);
  // Same muted grey as the (non-interactive) main label - a chip's own
  // border/pill shape is what signals it's tappable here, not blue text.
  static const _chipTextStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF6B7280));
  static const _chipPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);
  static const _chipBorderWidth = 1.0;
  // A shade darker than the page's own canvas background (0xFFF4F5F7),
  // not white - it needs to read as its own distinct chip against a frame
  // that already sits on that canvas colour.
  static const _kChipBackground = Color(0xFFEAEBEE);
  // Main label's own horizontal padding (6 + 5.5, see where it's used
  // below) plus its left:6 anchor inset.
  static const _mainLabelChrome = 6 + 5.5 + 6;
  // Chip's padding + border (both sides) plus its right:6 anchor inset.
  static const _chipChrome = 6 + 6 + _chipBorderWidth * 2 + 6;

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
                    _mainLabelChrome +
                    _textWidth(extraLabelText!, _chipTextStyle) +
                    _chipChrome +
                    12, // breathing room between the two labels
              ),
        // Wider with further generations below the children (#42).
        maxWidth: descendants == null ? 378 : double.infinity,
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
        // Stack's default alignment only matters for non-Positioned
        // children (the Wrap below) - without it, the Wrap sits at the
        // Stack's top-LEFT rather than centered, which was invisible while
        // the frame always shrink-wrapped to the Wrap's own width, but
        // became obvious once the minWidth fix above could make the frame
        // wider than its cards: they clumped to the left instead of
        // centering in the extra space.
        alignment: Alignment.topCenter,
        children: [
          // No "show more" cutoff - every child is shown, wrapping onto as
          // many rows as needed. There's plenty of room below to grow into,
          // unlike a fixed-height card row.
          if (descendants != null)
            // One row, so each child's own descendants fit below them.
            DescendantChart(
              children: descendants!,
              generations: generations,
              bottomRowKey: bottomRowKey,
              lineColorOf: (node) => _SurnameColorsScope.lineOf(context, node.surname),
              cardBuilder: (d, {required isShowingChildren}) => TreeNodeCard(
                firstName: d.node.firstName,
                surname: _SurnamesShown.of(context) ? d.node.surname : null,
                backgroundColor: _SurnameColorsScope.of(context, d.node.surname),
                isSurnameBold: false,
                sex: d.node.sex,
                isDead: d.node.isDead,
                birthYear: d.node.birthYear,
                thumb: d.node.thumb,
                photoHeaders: photoHeaders,
                showChildrenIcon: !isShowingChildren && (d.node.childrenCount ?? 0) > 0,
                childrenCount: d.node.childrenCount ?? 0,
                onTap: () => onSelectPerson(d.node.xref),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final child in children)
                  TreeNodeCard(
                    firstName: child.firstName,
                    surname: _SurnamesShown.of(context) ? child.surname : null,
                    backgroundColor: _SurnameColorsScope.of(context, child.surname),
                    isSurnameBold: false,
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
            left: 6,
            right: 16,
            // Positioned with both left AND right set gives its child a
            // TIGHT width, which stretched the label's background across
            // nearly the whole frame - the text itself stayed left-aligned
            // inside it, so the background beyond the text (still the same
            // F4F5F7 as the page) read as a huge gap before the border
            // resumed. Align lets the Container shrink-wrap to its actual
            // (possibly ellipsized) text width while the Positioned's
            // left/right still cap how wide that can get, for a long
            // partner name.
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
        ],
      ),
    );
  }
}

/// The view menu in the tree's top right corner: generations 1, 2 or 3 up
/// and down, or ∞ ([generations] null) (#42), and surnames on every card
/// on or off (#43).
class _ViewButton extends StatelessWidget {
  const _ViewButton({
    required this.generations,
    required this.isShowingSurnames,
    required this.isColouringSurnames,
    required this.onSelectGenerations,
    required this.onToggleSurnames,
    required this.onToggleColours,
  });

  final int? generations;
  final bool isShowingSurnames;
  final bool isColouringSurnames;
  final void Function(int? generations) onSelectGenerations;
  final VoidCallback onToggleSurnames;
  final VoidCallback onToggleColours;

  static const _kInfinity = 0;
  static const _kSurnames = -1;
  static const _kColours = -2;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    String label(int? value) => value == null ? '∞' : '$value';
    // The current choice on a light grey - the menu's own selection colour
    // is too dark on its white background.
    return Theme(
      data: Theme.of(context).copyWith(highlightColor: const Color(0xFFF0F1F3)),
      child: PopupMenuButton<int>(
        key: const Key('treeViewButton'),
        tooltip: l10n.treeViewTooltip,
        initialValue: generations ?? _kInfinity,
        onSelected: (value) => switch (value) {
          _kSurnames => onToggleSurnames(),
          _kColours => onToggleColours(),
          _ => onSelectGenerations(value == _kInfinity ? null : value),
        },
        itemBuilder: (_) => [
          for (final value in [1, 2, 3, null])
            PopupMenuItem(
              key: Key('treeGenerations-${label(value)}'),
              value: value ?? _kInfinity,
              // Laid out like the other menus' entries: a 20px "icon", then the text.
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      label(value),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(child: Text(value == null ? l10n.treeGenerationsAll : l10n.treeGenerationsCount(value))),
                ],
              ),
            ),
          const PopupMenuDivider(),
          PopupMenuItem(
            key: const Key('treeSurnamesItem'),
            value: _kSurnames,
            child: Row(
              children: [
                Icon(
                  isShowingSurnames ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(l10n.treeShowSurnames)),
              ],
            ),
          ),
          PopupMenuItem(
            key: const Key('treeSurnameColorsItem'),
            value: _kColours,
            child: Row(
              children: [
                Icon(
                  isColouringSurnames ? Icons.check_box_outlined : Icons.check_box_outline_blank,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(l10n.treeSurnameColors)),
              ],
            ),
          ),
        ],
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [BoxShadow(color: Color(0x1F111827), blurRadius: 4, offset: Offset(0, 1))],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.unfold_more, size: 18, color: Color(0xFF374151)),
              const SizedBox(width: 4),
              Text(
                label(generations),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether every card shows the surname below the first name (#43) - set
/// once around the tree instead of handed to every card's builder.
class _SurnamesShown extends InheritedWidget {
  const _SurnamesShown({required this.isShowing, required super.child});

  final bool isShowing;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SurnamesShown>()?.isShowing ?? false;

  @override
  bool updateShouldNotify(_SurnamesShown old) => old.isShowing != isShowing;
}

/// The colours of the surnames in view (#43), or null when they're off -
/// set once around the tree instead of handed to every card's builder.
class _SurnameColorsScope extends InheritedWidget {
  const _SurnameColorsScope({required this.colors, required super.child});

  final Map<String, Color>? colors;

  /// The card colour for [surname]: its own, or the one for all others.
  static Color? of(BuildContext context, String surname) {
    final colors = context.dependOnInheritedWidgetOfExactType<_SurnameColorsScope>()?.colors;
    if (colors == null) return null;
    return colors[surname] ?? otherSurnameColor;
  }

  /// The colour of the lines to a person with [surname] - null for the
  /// plain grey: colours off, or a surname without a colour of its own.
  static Color? lineOf(BuildContext context, String surname) {
    final color = context.dependOnInheritedWidgetOfExactType<_SurnameColorsScope>()?.colors?[surname];
    return color == null ? null : lineColorFor(color);
  }

  @override
  bool updateShouldNotify(_SurnameColorsScope old) => old.colors != colors;
}

/// The surname of everyone in view - the person, parents, siblings, the
/// shown partner (their birth name, the family they come from), children,
/// and further generations as far as shown.
List<String> _surnamesInView(
  TreeNeighborhood neighborhood,
  String? selectedPartnerXref,
  TreeLineage lineage,
  int generationsUp,
  int generationsDown,
  Map<String, TreeNeighborhood> loaded,
) {
  final partner = selectedPartnerXref == null
      ? neighborhood.defaultPartner
      : neighborhood.partners.where((p) => p.familyXref == selectedPartnerXref).firstOrNull ??
            neighborhood.defaultPartner;
  final partnerBirthName = partner?.partner == null ? '' : loaded[partner!.partner!.xref]?.personDetail.birthSurname ?? '';

  final surnames = [
    neighborhood.person.surname,
    ?neighborhood.father?.surname,
    ?neighborhood.mother?.surname,
    for (final sibling in neighborhood.siblings) sibling.surname,
    if (partner?.partner != null) partnerBirthName.isNotEmpty ? partnerBirthName : partner!.partner!.surname,
    for (final child in partner?.children ?? const <TreeNode>[]) child.surname,
  ];
  if (generationsUp > 1) {
    for (final entry in lineage.ancestors.entries) {
      final generation = kekuleGeneration(entry.key);
      if (generation >= 2 && generation <= generationsUp) surnames.add(entry.value.surname);
    }
  }
  if (generationsDown > 1 && partner != null) {
    final family = lineage.descendants?.families.where((f) => f.familyXref == partner.familyXref).firstOrNull;
    var row = [for (final child in family?.children ?? const <TreeDescendant>[]) ...child.children];
    for (var level = 2; level <= generationsDown && row.isNotEmpty; level++) {
      surnames.addAll(row.map((d) => d.node.surname));
      row = [for (final d in row) ...d.children];
    }
  }
  return surnames;
}

/// The legend of the surname colours (#43): a small pill at the bottom of
/// the tree, opening to the surnames in view with their colours.
class _SurnameLegend extends StatelessWidget {
  const _SurnameLegend({required this.colors, required this.surnames, required this.isOpen, required this.onToggle});

  final Map<String, Color> colors;

  /// One entry per person in view, for the counts.
  final List<String> surnames;
  final bool isOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Pastel on white needs an edge to be seen.
    Widget dot(Color color) => Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFC4C8CF)),
      ),
    );
    return Align(
      alignment: Alignment.bottomLeft,
      child: Container(
        key: const Key('surnameLegend'),
        constraints: const BoxConstraints(maxHeight: 180),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [BoxShadow(color: Color(0x1F111827), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: isOpen
                ? SingleChildScrollView(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        for (final entry in colors.entries)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              dot(entry.value),
                              const SizedBox(width: 6),
                              Text(
                                '${entry.key} ${surnames.where((s) => s == entry.key).length}',
                                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        if (surnames.any((s) => !colors.containsKey(s)))
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            dot(otherSurnameColor),
                            const SizedBox(width: 6),
                            Text(
                              '${l10n.treeOtherSurnames} ${surnames.where((s) => !colors.containsKey(s)).length}',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final color in colors.values.take(5)) ...[dot(color), const SizedBox(width: 3)],
                      const SizedBox(width: 5),
                      Text(
                        l10n.treeSurnameLegend,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
