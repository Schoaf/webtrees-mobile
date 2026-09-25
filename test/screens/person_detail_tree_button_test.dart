import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/screens/tree_view/tree_view_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  testWidgets(
    'tapping the tree-view button actually navigates to TreeViewScreen (no admin required)',
    (tester) async {
      final client = MockWebtreesClient();
      when(() => client.imageHeaders).thenReturn(<String, String>{});
      when(() => client.individual('Famtree', 'I1')).thenAnswer(
        (_) async => {
          'person': {'xref': 'I1', 'name': 'Anna Muster', 'sortName': 'Muster,Anna', 'sex': 'F', 'isDead': false},
          'relationship': '',
          'canEdit': false,
          'facts': <dynamic>[],
          'parentFamilies': <dynamic>[],
          'spouseFamilies': <dynamic>[],
          'siblings': <dynamic>[],
          'extraChildrenByParent': {'father': 0, 'mother': 0},
          'media': <dynamic>[],
        },
      );

      // No authControllerProvider override - defaults to the logged-out,
      // non-admin AuthState(). The tree-view button used to require
      // isAdmin (while it was still rough around the edges); reopened to
      // everyone once it had a full polish pass, so this deliberately
      // proves it no longer depends on admin status at all.
      final container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: PersonDetailScreen(xref: 'I1'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(TreeViewScreen), findsNothing);

      final treeButton = find.byWidgetPredicate(
        (w) => w is InkWell && w.onTap != null && w.customBorder is CircleBorder,
      );
      expect(treeButton, findsOneWidget, reason: 'the round tree-view button must be present and tappable');

      await tester.tap(treeButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(TreeViewScreen), findsOneWidget);
    },
  );

}
