import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tree_lineage.dart';
import '../models/tree_neighborhood.dart';
import 'app_providers.dart';

const _kTreeGenerationsPrefKey = 'tree_generations';

/// Generations the API can send beyond the person: `Pedigree` counts the
/// person in its 12, `Descendants` in its 10 - and one more generation down
/// is always fetched to know whether there are children below.
const maxAncestorGenerations = 11;
const maxDescendantGenerations = 8;

/// How many generations the tree shows up and down (#42): 1, 2 or 3, or
/// null for "∞" - more are loaded while scrolling. Kept across app starts.
class TreeGenerationsNotifier extends Notifier<int?> {
  @override
  int? build() {
    Future.microtask(_load);
    return 1;
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!prefs.containsKey(_kTreeGenerationsPrefKey)) return;
      final stored = prefs.getInt(_kTreeGenerationsPrefKey) ?? 1;
      state = stored == 0 ? null : stored;
    } on Exception {
      // Storage unavailable - stay at the default.
    }
  }

  Future<void> set(int? generations) async {
    state = generations;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kTreeGenerationsPrefKey, generations ?? 0);
    } on Exception {
      // Storage unavailable - the choice still applies until the app restarts.
    }
  }
}

final treeGenerationsProvider = NotifierProvider<TreeGenerationsNotifier, int?>(TreeGenerationsNotifier.new);

/// The direct line of one person beyond their parents and children (#42):
/// ancestors by Kekulé number and the descendants tree, each loaded as deep
/// as asked so far.
class TreeLineage {
  const TreeLineage({
    this.ancestors = const {},
    this.ancestorGenerations = 0,
    this.isLoadingAncestors = false,
    this.hasAncestorsError = false,
    this.descendants,
    this.descendantGenerations = 0,
    this.isLoadingDescendants = false,
    this.hasDescendantsError = false,
  });

  final Map<int, TreeNode> ancestors;

  /// Generations above the person that [ancestors] holds.
  final int ancestorGenerations;
  final bool isLoadingAncestors;
  final bool hasAncestorsError;

  /// The person with their descendants, [descendantGenerations] deep plus
  /// one generation more (only to know who has children).
  final TreeDescendant? descendants;
  final int descendantGenerations;
  final bool isLoadingDescendants;
  final bool hasDescendantsError;

  /// Someone in the top generation has parents of their own.
  bool get hasMoreAncestors =>
      ancestorGenerations < maxAncestorGenerations &&
      ancestors.entries.any((e) => kekuleGeneration(e.key) == ancestorGenerations && (e.value.hasParents ?? false));

  /// Someone in the bottom generation has children of their own.
  bool get hasMoreDescendants {
    if (descendants == null || descendantGenerations >= maxDescendantGenerations) return false;
    var generation = [descendants!];
    for (var i = 0; i < descendantGenerations; i++) {
      generation = [for (final d in generation) ...d.children];
    }
    return generation.any((d) => d.children.isNotEmpty);
  }

  TreeLineage copyWith({
    Map<int, TreeNode>? ancestors,
    int? ancestorGenerations,
    bool? isLoadingAncestors,
    bool? hasAncestorsError,
    TreeDescendant? descendants,
    int? descendantGenerations,
    bool? isLoadingDescendants,
    bool? hasDescendantsError,
  }) {
    return TreeLineage(
      ancestors: ancestors ?? this.ancestors,
      ancestorGenerations: ancestorGenerations ?? this.ancestorGenerations,
      isLoadingAncestors: isLoadingAncestors ?? this.isLoadingAncestors,
      hasAncestorsError: hasAncestorsError ?? this.hasAncestorsError,
      descendants: descendants ?? this.descendants,
      descendantGenerations: descendantGenerations ?? this.descendantGenerations,
      isLoadingDescendants: isLoadingDescendants ?? this.isLoadingDescendants,
      hasDescendantsError: hasDescendantsError ?? this.hasDescendantsError,
    );
  }
}

class TreeLineageController extends Notifier<TreeLineage> {
  TreeLineageController(this.xref);

  final String xref;

  @override
  TreeLineage build() {
    ref.watch(treeNameProvider);
    ref.watch(serverUrlProvider);
    return const TreeLineage();
  }

  /// Loads [generations] above the person, unless already there - one
  /// request for all of them, like webtrees' own pedigree chart.
  Future<void> ensureAncestors(int generations) async {
    final wanted = generations.clamp(0, maxAncestorGenerations);
    if (wanted <= state.ancestorGenerations || state.isLoadingAncestors || state.hasAncestorsError) return;

    state = state.copyWith(isLoadingAncestors: true);
    try {
      final json = await ref.read(webtreesClientProvider).pedigree(ref.read(treeNameProvider), xref, wanted + 1);
      if (json['ok'] == false) throw Exception(json['error']);
      state = state.copyWith(
        ancestors: ancestorsFromPedigreeJson(json),
        ancestorGenerations: wanted,
        isLoadingAncestors: false,
      );
    } catch (_) {
      // Not `on Exception`: a malformed answer throws a TypeError. The tree
      // keeps what it has; no retry loop while scrolling.
      state = state.copyWith(isLoadingAncestors: false, hasAncestorsError: true);
    }
  }

  /// Loads [generations] below the person (and one more), unless already there.
  Future<void> ensureDescendants(int generations) async {
    final wanted = generations.clamp(0, maxDescendantGenerations);
    if (wanted <= state.descendantGenerations || state.isLoadingDescendants || state.hasDescendantsError) return;

    state = state.copyWith(isLoadingDescendants: true);
    try {
      final json = await ref.read(webtreesClientProvider).descendants(ref.read(treeNameProvider), xref, wanted + 2);
      if (json['ok'] == false) throw Exception(json['error']);
      state = state.copyWith(
        descendants: TreeDescendant.fromJson(json['tree'] as Map<String, dynamic>, depth: wanted),
        descendantGenerations: wanted,
        isLoadingDescendants: false,
      );
    } catch (_) {
      state = state.copyWith(isLoadingDescendants: false, hasDescendantsError: true);
    }
  }
}

final treeLineageProvider = NotifierProvider.family<TreeLineageController, TreeLineage, String>(
  TreeLineageController.new,
);
