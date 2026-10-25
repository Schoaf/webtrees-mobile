import 'tree_neighborhood.dart';

/// The generation of a Kekulé number: 1 = the person, 2-3 = parents (1),
/// 4-7 = grandparents (2) ...
int kekuleGeneration(int n) => n.bitLength - 1;

/// The ancestors of one person from the `Pedigree` route (#42), by Kekulé
/// number. Each [TreeNode] carries `hasParents`.
Map<int, TreeNode> ancestorsFromPedigreeJson(Map<String, dynamic> json) {
  final entries = (json['ancestors'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  return {
    for (final entry in entries)
      entry['n'] as int: TreeNode.fromJson({
        ...entry['person'] as Map<String, dynamic>,
        'hasParents': entry['hasParents'] as bool? ?? false,
      }),
  };
}

/// One person of the `Descendants` route (#42) with the children of all
/// their families, in order.
class TreeDescendant {
  const TreeDescendant({required this.node, required this.families});

  /// [depth] is how many generations below this one are shown; the answer
  /// holds one more, so everyone shown gets a `childrenCount` - the extra
  /// generation below (negative depth) does not.
  factory TreeDescendant.fromJson(Map<String, dynamic> json, {required int depth}) {
    final familiesJson = (json['families'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    final families = [
      for (final family in familiesJson)
        TreeDescendantFamily(
          familyXref: family['xref'] as String,
          children: [
            for (final child in (family['children'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
              TreeDescendant.fromJson(child, depth: depth - 1),
          ],
        ),
    ];
    final childrenCount = families.fold(0, (n, f) => n + f.children.length);
    return TreeDescendant(
      node: TreeNode.fromJson({
        ...json['person'] as Map<String, dynamic>,
        if (depth >= 0) 'childrenCount': childrenCount,
      }),
      families: families,
    );
  }

  final TreeNode node;
  final List<TreeDescendantFamily> families;

  List<TreeDescendant> get children => [for (final f in families) ...f.children];
}

class TreeDescendantFamily {
  const TreeDescendantFamily({required this.familyXref, required this.children});

  final String familyXref;
  final List<TreeDescendant> children;
}
