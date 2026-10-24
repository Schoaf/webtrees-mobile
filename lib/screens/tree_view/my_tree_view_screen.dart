import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../widgets/start_person_builder.dart';
import 'tree_view_screen.dart';

/// The "Stammbaum" bottom-nav tab: the app's one tree view, starting with
/// the start person (see startXrefProvider). Every "show in the tree"
/// elsewhere switches to this tab (openTreeView).
class MyTreeViewScreen extends ConsumerWidget {
  const MyTreeViewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Drives TreeViewScreen.visibilitySignal - watched (not read) so this
    // widget, and TreeViewScreen below it, rebuild on every tab switch even
    // though both stay alive offstage the rest of the time (this is the
    // Stammbaum tab in an IndexedStack) - see the comment on
    // visibilitySignal for why that rebuild matters.
    final selectedTab = ref.watch(selectedTabProvider);
    return StartPersonBuilder(
      builder: (xref) => TreeViewScreen(xref: xref, visibilitySignal: selectedTab, isEnteringOnlyWhenEmpty: true),
    );
  }
}
