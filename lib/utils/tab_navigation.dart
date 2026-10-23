import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/search/person_detail_screen.dart';
import '../screens/tree_view/tree_view_screen.dart';

/// _HomeShell's bottom-nav destination order (main.dart) - shared so
/// nothing else has to hardcode a raw tab index (a previous version of
/// this app did exactly that in two different places, and they drifted
/// out of sync the moment a tab got inserted between them).
const kHomeTabIndex = 0;
const kTreeTabIndex = 1;
const kSearchTabIndex = 2;
const kAddPersonTabIndex = 3;

/// Each bottom-nav tab has its own nested Navigator (see _HomeShellState in
/// main.dart): pages opened from a tab stay in that tab, and the bottom bar
/// is a sibling of all of them - shown or hidden via [bottomBarVisibleProvider].
final homeNavigatorKey = GlobalKey<NavigatorState>();
final treeNavigatorKey = GlobalKey<NavigatorState>();
final searchNavigatorKey = GlobalKey<NavigatorState>();
final addPersonNavigatorKey = GlobalKey<NavigatorState>();

/// In bottom-nav order (kHomeTabIndex ...).
final tabNavigatorKeys = [homeNavigatorKey, treeNavigatorKey, searchNavigatorKey, addPersonNavigatorKey];

/// Whether the bottom bar shows (#31): hidden as soon as a page is opened
/// from a tab, shown again after every Back - even if that lands on an inner
/// page - so someone who got lost always gets it back with one Back.
class BottomBarVisibility extends Notifier<bool> {
  @override
  bool build() => true;

  void set(bool visible) => state = visible;
}

final bottomBarVisibleProvider = NotifierProvider<BottomBarVisibility, bool>(BottomBarVisibility.new);

/// Drives [bottomBarVisibleProvider] from a tab's own Navigator.
class BottomBarObserver extends NavigatorObserver {
  BottomBarObserver(this.container);

  final ProviderContainer container;

  void _set(bool visible) {
    // Navigator callbacks can run while widgets build - defer the change.
    Future.microtask(() => container.read(bottomBarVisibleProvider.notifier).set(visible));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The tab's own first page is pushed too - that one keeps the bar.
    if (previousRoute != null) _set(false);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(true);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _set(true);
}

/// Opens a person's page on top of the current page, within the current tab.
void openPerson(BuildContext context, String xref) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: xref)));
}

/// Opens the tree view for [xref] on top of the current page, within the current tab.
void openTreeView(BuildContext context, String xref) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TreeViewScreen(xref: xref)));
}
