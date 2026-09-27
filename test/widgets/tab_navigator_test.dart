import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/widgets/tab_navigator.dart';

void main() {
  Widget wrap(GlobalKey<NavigatorState> key, Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            const Text('persistent sibling'),
            Expanded(child: TabNavigator(navigatorKey: key, child: child)),
          ],
        ),
      ),
    );
  }

  testWidgets('pushing a route inside the tab does not cover the sibling widget outside it', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      wrap(
        key,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('pushed screen')))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('persistent sibling'), findsOneWidget);
    expect(find.text('pushed screen'), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The push went to TabNavigator's own nested Navigator, not the
    // MaterialApp's outer one - the sibling text, outside TabNavigator
    // entirely, is still there.
    expect(find.text('pushed screen'), findsOneWidget);
    expect(find.text('persistent sibling'), findsOneWidget);
  });

  testWidgets('the system back gesture pops the nested Navigator, not the whole app', (tester) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      wrap(
        key,
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('pushed screen')))),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('pushed screen'), findsOneWidget);

    // Simulates the OS back gesture/button, which NavigatorPopHandler is
    // what makes reach this nested Navigator at all.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('pushed screen'), findsNothing);
    expect(find.text('open'), findsOneWidget);
    expect(find.text('persistent sibling'), findsOneWidget, reason: 'the app itself must not have been popped/exited');
  });
}
