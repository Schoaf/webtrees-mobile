import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_neighborhood.dart';
import 'app_providers.dart';

/// State for one `TreeViewScreen` instance. `history`/`pos` is a browser-
/// style undo/redo stack of visited xrefs (per the spec: a new click after
/// undo discards the redo entries); `cache` means revisiting an xref via
/// undo/redo never re-fetches.
class TreeViewState {
  const TreeViewState({
    required this.history,
    required this.pos,
    required this.cache,
    required this.loading,
    required this.error,
    required this.selectedPartnerXref,
    required this.childrenExpanded,
  });

  final List<String> history;
  final int pos;
  final Map<String, TreeNeighborhood> cache;
  final bool loading;
  final String? error;
  final String? selectedPartnerXref;
  final bool childrenExpanded;

  String get activeXref => history[pos];
  bool get canUndo => pos > 0;
  bool get canRedo => pos < history.length - 1;
  TreeNeighborhood? get activeNeighborhood => cache[activeXref];
}

/// A Riverpod 3 family [Notifier] receives its argument through the
/// provider's `create` closure (`TreeViewController.new`), not through
/// `build(arg)` — `build()` takes no parameters, so the xref is stored on
/// the instance via the constructor instead.
class TreeViewController extends Notifier<TreeViewState> {
  TreeViewController(this.startXref);

  final String startXref;

  @override
  TreeViewState build() {
    // Deferred so the fetch's state assignment lands after build() returns,
    // not synchronously during it.
    Future.microtask(() => _load(startXref));

    return TreeViewState(
      history: [startXref],
      pos: 0,
      cache: const {},
      loading: true,
      error: null,
      selectedPartnerXref: null,
      childrenExpanded: false,
    );
  }

  Future<void> _load(String xref) async {
    if (state.cache.containsKey(xref)) {
      return;
    }

    state = TreeViewState(
      history: state.history,
      pos: state.pos,
      cache: state.cache,
      loading: true,
      error: null,
      selectedPartnerXref: state.selectedPartnerXref,
      childrenExpanded: state.childrenExpanded,
    );

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      final json = await client.individual(tree, xref);

      if (json['ok'] == false) {
        state = TreeViewState(
          history: state.history,
          pos: state.pos,
          cache: state.cache,
          loading: false,
          // Raw server text, or null if it gave none - kept untranslated
          // here (no BuildContext in a Notifier); TreeViewScreen (which has
          // one) supplies its own localized fallback text when this is null.
          error: json['error'] as String?,
          selectedPartnerXref: state.selectedPartnerXref,
          childrenExpanded: state.childrenExpanded,
        );
        return;
      }

      final neighborhood = TreeNeighborhood.fromJson(json);
      state = TreeViewState(
        history: state.history,
        pos: state.pos,
        cache: {...state.cache, xref: neighborhood},
        loading: false,
        error: null,
        selectedPartnerXref: state.selectedPartnerXref,
        childrenExpanded: state.childrenExpanded,
      );
    } catch (e) {
      // Not `on Exception`: a malformed/unexpected field in TreeNeighborhood
      // .fromJson's parsing throws a TypeError (a dart Error, not an
      // Exception) - `on Exception` alone silently swallows that, leaving
      // the screen stuck on its loading spinner forever with no visible
      // error at all.
      state = TreeViewState(
        history: state.history,
        pos: state.pos,
        cache: state.cache,
        loading: false,
        // Raw exception text (no BuildContext here either) - TreeViewScreen
        // wraps this with its own localized "Couldn't load: ..." prefix.
        error: '$e',
        selectedPartnerXref: state.selectedPartnerXref,
        childrenExpanded: state.childrenExpanded,
      );
    }
  }

  /// Tapping a card: the tapped person becomes the new active person. A tap
  /// after an undo discards the redo entries (browser-history semantics,
  /// per the spec).
  Future<void> selectPerson(String xref) async {
    if (xref == state.activeXref) return;

    final newHistory = state.history.sublist(0, state.pos + 1)..add(xref);
    state = TreeViewState(
      history: newHistory,
      pos: newHistory.length - 1,
      cache: state.cache,
      loading: state.loading,
      error: state.error,
      selectedPartnerXref: null,
      childrenExpanded: false,
    );
    await _load(xref);
  }

  void undo() {
    if (!state.canUndo) return;
    state = TreeViewState(
      history: state.history,
      pos: state.pos - 1,
      cache: state.cache,
      loading: state.loading,
      error: state.error,
      selectedPartnerXref: null,
      childrenExpanded: false,
    );
  }

  void redo() {
    if (!state.canRedo) return;
    state = TreeViewState(
      history: state.history,
      pos: state.pos + 1,
      cache: state.cache,
      loading: state.loading,
      error: state.error,
      selectedPartnerXref: null,
      childrenExpanded: false,
    );
  }

  void selectPartner(String xref) {
    state = TreeViewState(
      history: state.history,
      pos: state.pos,
      cache: state.cache,
      loading: state.loading,
      error: state.error,
      selectedPartnerXref: xref,
      childrenExpanded: false,
    );
  }

  void toggleChildrenExpanded() {
    state = TreeViewState(
      history: state.history,
      pos: state.pos,
      cache: state.cache,
      loading: state.loading,
      error: state.error,
      selectedPartnerXref: state.selectedPartnerXref,
      childrenExpanded: !state.childrenExpanded,
    );
  }
}

final treeViewControllerProvider =
    NotifierProvider.autoDispose.family<TreeViewController, TreeViewState, String>(TreeViewController.new);
