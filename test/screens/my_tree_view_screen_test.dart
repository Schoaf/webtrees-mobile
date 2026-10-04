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

  Map<String, dynamic> infoResponse({String startXref = ''}) => {
    'trees': [
      {'name': 'Famtree', 'startXref': startXref},
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

  testWidgets('starts on the server\'s startXref', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse(startXref: 'I5'));

    await pumpScreen(tester);

    final screen = tester.widget<TreeViewScreen>(find.byType(TreeViewScreen));
    expect(screen.xref, 'I5');
  });

  testWidgets('shows a friendly error without a startXref', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());

    await pumpScreen(tester);

    expect(find.byType(TreeViewScreen), findsNothing);
    expect(find.textContaining('keine Person'), findsOneWidget);
  });
}
