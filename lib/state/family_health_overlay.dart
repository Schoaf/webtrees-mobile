import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_providers.dart';

/// "Familiengesundheit" in the tree (#54): who has which illness category, so the tree can fade everyone without
/// one and show the category large on the others. Null while the tree shows normally.
class FamilyHealthOverlay {
  const FamilyHealthOverlay({required this.categoriesByXref, required this.categoryNames, this.category});

  /// The categories of each individual with an illness the account may see.
  final Map<String, Set<String>> categoriesByXref;

  /// Category id -> name in the user's language, in the module's order.
  final Map<String, String> categoryNames;

  /// The category the filter bar picked - null for all.
  final String? category;

  /// The categories of the people [inView], in the module's order - the filter bar's chips. The picked one stays,
  /// so it can be taken back after fewer generations are shown.
  List<String> usedCategories(Iterable<String> inView) {
    final used = {for (final xref in inView) ...?categoriesByXref[xref]};
    return [
      for (final id in categoryNames.keys)
        if (used.contains(id) || id == category) id,
    ];
  }

  /// Whether [xref] is drawn pale: no illness, or none in the picked category.
  bool isFaded(String xref) {
    final categories = categoriesByXref[xref];
    if (categories == null || categories.isEmpty) return true;
    return category != null && !categories.contains(category);
  }

  /// What the card of [xref] shows large: the picked category, or all of theirs - null when faded.
  String? labelOf(String xref) {
    if (isFaded(xref)) return null;
    final ids = category != null ? [category!] : [for (final id in categoryNames.keys) if (categoriesByXref[xref]!.contains(id)) id];
    return ids.map((id) => categoryNames[id] ?? id).join(' · ');
  }

  FamilyHealthOverlay withCategory(String? category) =>
      FamilyHealthOverlay(categoriesByXref: categoriesByXref, categoryNames: categoryNames, category: category);

  /// From the module's `Illnesses` and `Catalog` answers.
  factory FamilyHealthOverlay.fromJson(Map<String, dynamic> illnesses, Map<String, dynamic> catalog) {
    final byXref = <String, Set<String>>{};
    for (final entry in (illnesses['illnesses'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>()) {
      final xref = entry['xref'];
      if (xref is String) (byXref[xref] ??= {}).add(entry['category'] as String? ?? 'other');
    }
    return FamilyHealthOverlay(
      categoriesByXref: byXref,
      categoryNames: {
        for (final c in (catalog['categories'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
          c['id'] as String: c['name'] as String? ?? '',
      },
    );
  }
}

class FamilyHealthOverlayNotifier extends Notifier<FamilyHealthOverlay?> {
  @override
  FamilyHealthOverlay? build() {
    // Another server, tree or account: someone else's illnesses.
    ref.watch(serverUrlProvider);
    ref.watch(treeNameProvider);
    ref.watch(authControllerProvider.select((auth) => auth.loggedIn));
    return null;
  }

  void show(FamilyHealthOverlay overlay) => state = overlay;

  void pickCategory(String? category) => state = state?.withCategory(category);

  void hide() => state = null;
}

final familyHealthOverlayProvider = NotifierProvider<FamilyHealthOverlayNotifier, FamilyHealthOverlay?>(
  FamilyHealthOverlayNotifier.new,
);
