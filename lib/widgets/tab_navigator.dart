import 'package:flutter/material.dart';

/// One bottom-nav tab's own nested [Navigator], wrapping [child] as its
/// initial/only starting route. Every ordinary
/// `Navigator.of(context).push(...)` call from within [child]'s subtree
/// (PersonDetailScreen opening a relative, TreeViewScreen's own profile
/// button, ...) resolves to whichever Navigator is nearest in the widget
/// tree, so this needs no changes to any of those call sites to take
/// effect - they just start finding this nested Navigator instead of
/// whichever one used to be nearest, once it's here. Used to keep a
/// persistent bottom-nav bar on screen (a sibling of this, not something
/// any push inside it can cover) while still letting each tab push its
/// own screens - see `_HomeShellState.build` in main.dart.
///
/// [NavigatorPopHandler] is what makes the system back gesture/button
/// still pop the right thing: without it, only the app's outer/root
/// Navigator (whichever one MaterialApp's own `navigatorKey` points to)
/// handles that, with no idea this nested one exists or has its own
/// routes to pop first.
class TabNavigator extends StatelessWidget {
  const TabNavigator({super.key, required this.navigatorKey, required this.child});

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NavigatorPopHandler(
      onPopWithResult: (Object? result) => navigatorKey.currentState?.maybePop(),
      child: Navigator(
        key: navigatorKey,
        onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => child),
      ),
    );
  }
}
