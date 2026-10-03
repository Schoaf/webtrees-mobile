import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/tree_view/my_tree_view_screen.dart';
import 'package:webtrees_mobile/screens/tree_view/tree_view_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  Map<String, dynamic> infoResponse({String userXref = '', String defaultXref = ''}) => {
    'trees': [
      {'name': 'Famtree', 'userXref': userXref, 'defaultXref': defaultXref},
    ],
  };

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => client.individual(any(), any())).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Anna Muster', 'sex': 'F', 'isDead': false},
        'facts': <dynamic>[],
      },
    );
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('de'),
          home: MyTreeViewScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('prefers the account\'s own linked person over the tree\'s Startperson', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse(userXref: 'I5', defaultXref: 'I1'));

    await pumpScreen(tester);

    final screen = tester.widget<TreeViewScreen>(find.byType(TreeViewScreen));
    expect(screen.xref, 'I5');
  });

  testWidgets('falls back to the tree\'s Startperson when the account has no linked person', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse(userXref: '', defaultXref: 'I1'));

    await pumpScreen(tester);

    final screen = tester.widget<TreeViewScreen>(find.byType(TreeViewScreen));
    expect(screen.xref, 'I1');
  });

  testWidgets('falls back to the tree\'s general start person when the user has neither', (tester) async {
    final info = infoResponse(userXref: '', defaultXref: '');
    ((info['trees'] as List<dynamic>).first as Map<String, dynamic>)['rootXref'] = 'I9';
    when(() => client.info('Famtree')).thenAnswer((_) async => info);

    await pumpScreen(tester);

    final screen = tester.widget<TreeViewScreen>(find.byType(TreeViewScreen));
    expect(screen.xref, 'I9');
  });

  testWidgets('shows a friendly error when neither is set', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());

    await pumpScreen(tester);

    expect(find.byType(TreeViewScreen), findsNothing);
    expect(find.textContaining('keine Person'), findsOneWidget);
  });
}
