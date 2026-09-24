import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/screens/search/search_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpSearchScreen(WidgetTester tester, {String? pickerTitle}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: SearchScreen(pickerTitle: pickerTitle),
        ),
      ),
    );
  }

  testWidgets('shows a prompt before any search has been made', (tester) async {
    await pumpSearchScreen(tester);
    expect(find.text('Suche nach einem Namen.'), findsOneWidget);
  });

  testWidgets('debounces input: no request until 300ms after typing stops', (tester) async {
    when(() => client.individuals('Famtree', query: 'Anna')).thenAnswer((_) async => {'data': <dynamic>[]});

    await pumpSearchScreen(tester);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump(const Duration(milliseconds: 100));

    verifyNever(() => client.individuals('Famtree', query: 'Anna'));

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    verify(() => client.individuals('Famtree', query: 'Anna')).called(1);
  });

  testWidgets('shows results and the hit count once the search resolves', (tester) async {
    when(() => client.individuals('Famtree', query: 'Anna')).thenAnswer(
      (_) async => {
        'data': [
          {'xref': 'I1', 'name': 'Anna Muster', 'sex': 'F', 'isDead': false},
        ],
      },
    );

    await pumpSearchScreen(tester);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.text('Anna Muster', findRichText: true), findsOneWidget);
    expect(find.text('1 Treffer'), findsOneWidget);
  });

  testWidgets('shows "Keine Treffer." when the search comes back empty', (tester) async {
    when(() => client.individuals('Famtree', query: 'Zzz')).thenAnswer((_) async => {'data': <dynamic>[]});

    await pumpSearchScreen(tester);
    await tester.enterText(find.byType(TextField), 'Zzz');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.text('Keine Treffer.'), findsOneWidget);
  });

  testWidgets('clearing the query resets to the initial prompt without searching', (tester) async {
    when(() => client.individuals('Famtree', query: 'Anna')).thenAnswer((_) async => {'data': <dynamic>[]});

    await pumpSearchScreen(tester);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    expect(find.text('Suche nach einem Namen.'), findsOneWidget);
  });

  testWidgets('a failed search shows the error message instead of results', (tester) async {
    when(() => client.individuals('Famtree', query: 'Anna')).thenThrow(Exception('server down'));

    await pumpSearchScreen(tester);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Suche fehlgeschlagen:'), findsOneWidget);
  });

  testWidgets('in picker mode, tapping a result pops the screen with the chosen person', (tester) async {
    when(() => client.individuals('Famtree', query: 'Anna')).thenAnswer(
      (_) async => {
        'data': [
          {'xref': 'I1', 'name': 'Anna Muster', 'sex': 'F', 'isDead': false},
        ],
      },
    );

    Map<String, dynamic>? picked;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await Navigator.of(context).push<Map<String, dynamic>>(
                  MaterialPageRoute(builder: (_) => const SearchScreen(pickerTitle: 'Startperson wählen')),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Anna Muster', findRichText: true));
    await tester.pumpAndSettle();

    expect(find.byType(SearchScreen), findsNothing);
    expect(picked, {'xref': 'I1', 'name': 'Anna Muster', 'sex': 'F', 'isDead': false});
  });

  testWidgets('outside picker mode, tapping a result pushes PersonDetailScreen', (tester) async {
    when(() => client.individuals('Famtree', query: 'Anna')).thenAnswer(
      (_) async => {
        'data': [
          {'xref': 'I1', 'name': 'Anna Muster', 'sex': 'F', 'isDead': false},
        ],
      },
    );
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

    await pumpSearchScreen(tester);
    await tester.enterText(find.byType(TextField), 'Anna');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Anna Muster', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(PersonDetailScreen), findsOneWidget);
  });
}
