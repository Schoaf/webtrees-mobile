import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/state/tree_view_providers.dart';
import 'package:webtrees_mobile/utils/tab_navigation.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

Future<ProviderContainer> _pumpPersonDetail(WidgetTester tester, {required bool isDead}) async {
  final client = MockWebtreesClient();
  when(() => client.imageHeaders).thenReturn(<String, String>{});
  when(() => client.individual('Famtree', 'I1')).thenAnswer(
    (_) async => {
      'person': {'xref': 'I1', 'name': 'Anna Muster', 'sortName': 'Muster,Anna', 'sex': 'F', 'isDead': isDead},
      'relationship': '',
      'canEdit': false,
      'facts': <dynamic>[],
      'parentFamilies': <dynamic>[],
      'spouseFamilies': <dynamic>[],
      'stepFamilies': <dynamic>[],
      'media': <dynamic>[],
    },
  );

  // No authControllerProvider override - defaults to the logged-out,
  // non-admin AuthState(). The tree-view button used to require isAdmin
  // (while it was still rough around the edges); reopened to everyone once
  // it had a full polish pass, so this deliberately proves it no longer
  // depends on admin status at all.
  final container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('de'),
        home: PersonDetailScreen(xref: 'I1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return container;
}

void main() {
  testWidgets('tapping the tree-view button shows the person on the Stammbaum tab (no admin required)', (
    tester,
  ) async {
    final container = await _pumpPersonDetail(tester, isDead: false);

    final treeButton = find.byKey(const Key('treeViewButton'));
    expect(treeButton, findsOneWidget, reason: 'the tree-view button must be present and tappable');

    await tester.tap(treeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(selectedTabProvider), kTreeTabIndex);
    expect(container.read(treeViewControllerProvider).activeXref, 'I1');
  });

  testWidgets('tapping the tree-view button still works for a deceased person', (tester) async {
    // Regression test: the DeathBanderole used to sit as a Stack *sibling*
    // of the button (not a descendant of its InkWell), positioned right
    // over the button's corner. A plain CustomPaint's hitTestSelf treats
    // its whole bounding box as opaque by default, and Stack hit-testing
    // stops at the first opaque hit in paint order - so the banderole
    // silently swallowed the tap before it ever reached the button
    // underneath, for deceased people only.
    final container = await _pumpPersonDetail(tester, isDead: true);

    final treeButton = find.byKey(const Key('treeViewButton'));
    expect(treeButton, findsOneWidget, reason: 'the tree-view button must be present and tappable');

    await tester.tap(treeButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(container.read(selectedTabProvider), kTreeTabIndex);
    expect(container.read(treeViewControllerProvider).activeXref, 'I1');
  });
}
