import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/repositories/quick_note_store.dart';
import 'package:webtrees_mobile/screens/home/home_screen.dart';
import 'package:webtrees_mobile/screens/responses/responses_list_screen.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

class MockQuickNoteStore extends Mock implements QuickNoteStore {}

void main() {
  late MockWebtreesClient client;
  late MockQuickNoteStore noteStore;
  late ProviderContainer container;

  Map<String, dynamic> infoResponse({
    String userXref = '',
    String defaultXref = 'I1',
    String title = 'Familie Muster',
    int individuals = 42,
    String realName = 'Alice A.',
  }) => {
    'user': {'realName': realName},
    'trees': [
      {
        'name': 'Famtree',
        'title': title,
        'individuals': individuals,
        'userXref': userXref,
        'defaultXref': defaultXref,
      },
    ],
  };

  Map<String, dynamic> personResponse(String xref, {String name = 'Startperson Muster'}) => {
    'person': {'xref': xref, 'name': name, 'sex': 'F', 'isDead': false, 'lifespan': '1990-'},
  };

  setUp(() {
    client = MockWebtreesClient();
    noteStore = MockQuickNoteStore();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => noteStore.unsynced()).thenAnswer((_) async => <QuickNote>[]);
    container = ProviderContainer(
      overrides: [
        webtreesClientProvider.overrideWithValue(client),
        quickNoteStoreProvider.overrideWithValue(noteStore),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: HomeScreen(),
        ),
      ),
    );
  }

  testWidgets('shows a loading spinner, then the tree title, Startperson and individual count', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
    when(() => client.anniversaries('Famtree', days: 7)).thenAnswer((_) async => {'data': <dynamic>[]});
    when(() => client.shareRequestUnreadCount('Famtree')).thenAnswer((_) async => 0);

    await pumpScreen(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Familie Muster'), findsOneWidget);
    expect(find.text('Startperson Muster', findRichText: true), findsOneWidget);
    expect(find.text('42 Personen im Stammbaum'), findsOneWidget);
  });

  testWidgets('surfaces a load error instead of crashing', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) => Future.error(Exception('offline')));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Konnte nicht laden:'), findsOneWidget);
  });

  testWidgets('an unreadable share-request count (module disabled) falls back to 0, no card shown', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
    when(() => client.anniversaries('Famtree', days: 7)).thenAnswer((_) async => {'data': <dynamic>[]});
    when(() => client.shareRequestUnreadCount('Famtree')).thenThrow(Exception('module not installed'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Antworten erhalten'), findsNothing);
  });

  testWidgets('shows the unread-responses card with correct singular/plural text and navigates on tap', (
    tester,
  ) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
    when(() => client.anniversaries('Famtree', days: 7)).thenAnswer((_) async => {'data': <dynamic>[]});
    when(() => client.shareRequestUnreadCount('Famtree')).thenAnswer((_) async => 1);
    when(() => client.shareRequestList('Famtree')).thenAnswer((_) async => <Map<String, dynamic>>[]);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Eine Anfrage wartet auf Prüfung'), findsOneWidget);

    await tester.tap(find.text('Antworten erhalten'));
    await tester.pumpAndSettle();

    expect(find.byType(ResponsesListScreen), findsOneWidget);
  });

  testWidgets('birthdays this week: filters to living BIRT events, and tapping one opens PersonDetailScreen', (
    tester,
  ) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2', name: 'Birthday Kid'));
    when(() => client.shareRequestUnreadCount('Famtree')).thenAnswer((_) async => 0);
    when(() => client.anniversaries('Famtree', days: 7)).thenAnswer(
      (_) async => {
        'data': [
          // Kept: living person, BIRT event, today.
          {
            'tag': 'BIRT',
            'inDays': 0,
            'years': 10,
            'person': {'xref': 'I2', 'name': 'Birthday Kid', 'isDead': false},
          },
          // Dropped: a MARR anniversary, not a birthday.
          {
            'tag': 'MARR',
            'inDays': 1,
            'person': {'xref': 'I3', 'name': 'Married Couple', 'isDead': false},
          },
          // Dropped: the person is deceased (a death-date anniversary, not
          // a birthday to congratulate).
          {
            'tag': 'BIRT',
            'inDays': 2,
            'person': {'xref': 'I4', 'name': 'Deceased Person', 'isDead': true},
          },
        ],
      },
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Birthday Kid'), findsOneWidget);
    expect(find.text('wird 10 · heute'), findsOneWidget);
    expect(find.text('Married Couple'), findsNothing);
    expect(find.text('Deceased Person'), findsNothing);

    await tester.tap(find.text('Birthday Kid'));
    await tester.pumpAndSettle();

    expect(find.byType(PersonDetailScreen), findsOneWidget);
    final screen = tester.widget<PersonDetailScreen>(find.byType(PersonDetailScreen));
    expect(screen.xref, 'I2');
  });

  testWidgets('falls back to userXref for the Startperson when the tree has no defaultXref', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse(defaultXref: '', userXref: 'I9'));
    when(() => client.individual('Famtree', 'I9')).thenAnswer((_) async => personResponse('I9', name: 'Linked User'));
    when(() => client.anniversaries('Famtree', days: 7)).thenAnswer((_) async => {'data': <dynamic>[]});
    when(() => client.shareRequestUnreadCount('Famtree')).thenAnswer((_) async => 0);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Linked User', findRichText: true), findsOneWidget);
    // individual() must only have been called once - the linked person and
    // the Startperson are the same record here, so it should be reused
    // rather than fetched twice.
    verify(() => client.individual('Famtree', 'I9')).called(1);
  });
}
