import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/search/person_detail_screen.dart';
import '../screens/tree_view/tree_view_screen.dart';
import '../state/app_providers.dart';
import 'device_size.dart';

/// _HomeShell's bottom-nav destination order (main.dart) - shared so
/// nothing else has to hardcode a raw tab index (a previous version of
/// this app did exactly that in two different places, and they drifted
/// out of sync the moment a tab got inserted between them).
const kHomeTabIndex = 0;
const kTreeTabIndex = 1;
const kSearchTabIndex = 2;
const kAddPersonTabIndex = 3;

/// Home's own nested Navigator (tablet only - see _HomeShellState.build in
/// main.dart), shared so [openPerson] can push onto it from *outside* that
/// tab's own subtree (Search, TreeView, ...), not just from within it.
final homeNavigatorKey = GlobalKey<NavigatorState>();

/// Stammbaum's own nested Navigator (tablet only), shared for the same
/// reason - [openTreeView] pushing onto it from outside the Stammbaum
/// tab's own subtree (a Person screen's tree button).
final treeNavigatorKey = GlobalKey<NavigatorState>();

/// Opens a person, always ending up on the Home tab regardless of which
/// tab you actually tapped it from (Search, a Home entry, a relative
/// within another Person screen, ...) - on a wide landscape tablet, that
/// means the push goes onto Home's own nested Navigator (via
/// [homeNavigatorKey]) and Home's bottom-nav destination becomes selected/
/// highlighted, so the two always agree on what's showing instead of the
/// tab bar getting stuck on whichever tab you happened to push from. On
/// phone (no nested navigators at all - see _HomeShellState.build), this
/// is a plain push on the app's one root Navigator, same as always.
///
/// Takes a plain [BuildContext] (via ProviderScope.containerOf), not a
/// WidgetRef, so call sites that are plain StatelessWidgets - not every
/// screen/row that opens a person is a ConsumerWidget - don't need
/// converting just to call this.
void openPerson(BuildContext context, String xref, {int depth = 0}) {
  final route = MaterialPageRoute(
    builder: (_) => PersonDetailScreen(xref: xref, depth: depth),
  );
  if (isTabletDevice(context) && homeNavigatorKey.currentState != null) {
    ProviderScope.containerOf(
      context,
    ).read(selectedTabProvider.notifier).select(kHomeTabIndex);
    homeNavigatorKey.currentState!.push(route);
  } else {
    Navigator.of(context).push(route);
  }
}

/// Same idea as [openPerson], but for the Stammbaum tab and
/// [treeNavigatorKey] - opening the tree view from anywhere (a Person
/// screen's tree button) always makes Stammbaum the active tab too.
void openTreeView(BuildContext context, String xref) {
  final route = MaterialPageRoute(builder: (_) => TreeViewScreen(xref: xref));
  if (isTabletDevice(context) && treeNavigatorKey.currentState != null) {
    ProviderScope.containerOf(
      context,
    ).read(selectedTabProvider.notifier).select(kTreeTabIndex);
    treeNavigatorKey.currentState!.push(route);
  } else {
    Navigator.of(context).push(route);
  }
}
