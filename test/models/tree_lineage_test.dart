import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/models/tree_lineage.dart';
import 'package:webtrees_mobile/state/tree_generations.dart';

import '../fixtures/tree_lineage.dart';

void main() {
  test('kekuleGeneration counts generations above the person', () {
    expect(kekuleGeneration(1), 0);
    expect(kekuleGeneration(3), 1);
    expect(kekuleGeneration(4), 2);
    expect(kekuleGeneration(15), 3);
  });

  test('ancestorsFromPedigreeJson keys the people by Kekulé number with hasParents', () {
    final ancestors = ancestorsFromPedigreeJson(pedigreeJson(3));

    expect(ancestors.keys, [1, 2, 3, 4, 5, 6, 7]);
    expect(ancestors[4]!.firstName, 'Josef');
    expect(ancestors[4]!.hasParents, isTrue);
    expect(ancestors[5]!.hasParents, isFalse);
  });

  test('TreeDescendant counts the children of everyone shown, not of the extra generation', () {
    final root = TreeDescendant.fromJson(descendantsJson(3)['tree'] as Map<String, dynamic>, depth: 1);
    final mia = root.children.first;

    expect(root.node.childrenCount, 2);
    expect(mia.node.childrenCount, 1);
    expect(mia.children.single.node.childrenCount, isNull);
  });

  test('TreeLineage knows whether there are more generations to load', () {
    final ancestors = TreeLineage(ancestors: ancestorsFromPedigreeJson(pedigreeJson(3)), ancestorGenerations: 2);
    final allAncestors = TreeLineage(ancestors: ancestorsFromPedigreeJson(pedigreeJson(4)), ancestorGenerations: 3);
    TreeLineage descendants(int shown) => TreeLineage(
      descendants: TreeDescendant.fromJson(descendantsJson(shown + 2)['tree'] as Map<String, dynamic>, depth: shown),
      descendantGenerations: shown,
    );

    expect(ancestors.hasMoreAncestors, isTrue, reason: 'Josef has parents');
    expect(allAncestors.hasMoreAncestors, isFalse);
    expect(descendants(1).hasMoreDescendants, isTrue, reason: 'Mia has a child');
    expect(descendants(2).hasMoreDescendants, isFalse);
  });
}
