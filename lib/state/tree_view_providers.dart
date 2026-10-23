import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/tree_neighborhood.dart';
import 'app_providers.dart';

/// The app's one tree history (#31): every tree view - the Stammbaum tab and
/// any opened from a person's page - shows and moves the same history, so
/// undo always leads back to whoever was in focus before, however the tree
/// was entered. `history`/`pos` is a browser-style undo/redo stack of
/// visited xrefs (a new step after undo discards the redo entries; the same
/// person twice in a row is never a step); `cache` means revisiting an xref
/// via undo/redo never re-fetches.
class TreeViewState {
  const TreeViewState({
    required this.history,
    required this.pos,
    required this.cache,
    required this.loading,
    required this.error,
    required this.selectedPartnerXref,
  });

  final List<String> history;
  final int pos;
  final Map<String, TreeNeighborhood> cache;
  final bool loading;
  final String? error;
  final String? selectedPartnerXref;

  /// Null until the tree has been entered for the first time.
  String? get activeXref => history.isEmpty ? null : history[pos];
  bool get canUndo => pos > 0;
  bool get canRedo => pos < history.length - 1;
  TreeNeighborhood? get activeNeighborhood => activeXref == null ? null : cache[activeXref];
}

class TreeViewController extends Notifier<TreeViewState> {
  @override
  TreeViewState build() {
    // Another tree or server: a history of people from the old one would
    // be meaningless - start fresh.
    ref.watch(treeNameProvider);
    ref.watch(serverUrlProvider);
    return const TreeViewState(
      history: [],
      pos: 0,
      cache: {},
      loading: false,
      error: null,
      selectedPartnerXref: null,
    );
  }

  /// Entering the tree with [xref] (a person's tree button, the Stammbaum
  /// tab): it becomes the active person - a new undo step unless it already
  /// is the active one.
  Future<void> enter(String xref) => selectPerson(xref);

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
      );
    }
  }

  /// Tapping a card: the tapped person becomes the new active person. A tap
  /// after an undo discards the redo entries (browser-history semantics,
  /// per the spec).
  Future<void> selectPerson(String xref) async {
    if (xref == state.activeXref) {
      if (!state.cache.containsKey(xref)) await _load(xref);
      return;
    }

    final newHistory = state.history.isEmpty ? [xref] : (state.history.sublist(0, state.pos + 1)..add(xref));
    state = TreeViewState(
      history: newHistory,
      pos: newHistory.length - 1,
      cache: state.cache,
      loading: state.loading,
      error: state.error,
      selectedPartnerXref: null,
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
    );
  }
}

final treeViewControllerProvider = NotifierProvider<TreeViewController, TreeViewState>(TreeViewController.new);
