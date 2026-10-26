import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../state/start_person.dart';
import '../../state/tree_view_providers.dart';
import '../../utils/tab_navigation.dart';
import '../../widgets/start_person_builder.dart';
import 'tree_view_screen.dart';

/// The "Stammbaum" bottom-nav tab: the app's one tree view, starting with
/// the start person (see startXrefProvider). Every "show in the tree"
/// elsewhere switches to this tab (openTreeView).
class MyTreeViewScreen extends ConsumerWidget {
  const MyTreeViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watched, so the tree learns when its tab shows - it stays alive
    // offstage in the bottom bar's IndexedStack (see TreeViewScreen.isVisible).
    final isVisible = ref.watch(selectedTabProvider) == kTreeTabIndex;
    // A tree opened from elsewhere shows even without a start person.
    final active = ref.watch(treeViewControllerProvider.select((state) => state.activeXref));
    final start = ref.watch(startXrefProvider).value;
    if (active != null && start == null) {
      return TreeViewScreen(xref: active, isVisible: isVisible, isEnteringOnlyWhenEmpty: true);
    }
    return StartPersonBuilder(
      builder: (xref) => TreeViewScreen(xref: xref, isVisible: isVisible, isEnteringOnlyWhenEmpty: true),
    );
  }
}
