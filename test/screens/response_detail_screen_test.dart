import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/responses/response_detail_screen.dart';
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

  /// Pushes the screen onto a real Navigator stack (over a placeholder home
  /// route) so pop()/pushReplacement() behavior is observable. The home
  /// route needs its own Scaffold - like every real screen this pushes
  /// from - so that a SnackBar shown right after a pop() still has
  /// somewhere to render once ResponseDetailScreen's own Scaffold is gone.
  Future<void> pumpPushed(WidgetTester tester, {int id = 7}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => ResponseDetailScreen(id: id))),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows a load error instead of crashing', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer((_) => Future.error(Exception('offline')));

    await pumpPushed(tester);

    expect(find.textContaining('Konnte nicht laden:'), findsOneWidget);
  });

  testWidgets('an already-applied request shows the info message, not the compare form', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {'id': 7, 'name': 'Anna Muster', 'applied': true, 'compare': <String, dynamic>{}},
    );

    await pumpPushed(tester);

    expect(find.text('Diese Antwort wurde bereits übernommen.'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('no proposed changes shows the "nothing proposed" message', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {'id': 7, 'name': 'Anna Muster', 'applied': false, 'compare': <String, dynamic>{}},
    );

    await pumpPushed(tester);

    expect(find.text('Es wurden keine Änderungen vorgeschlagen.'), findsOneWidget);
  });

  testWidgets('shows compare fields with labels and before/after text; Apply starts disabled', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {
        'id': 7,
        'name': 'Anna Muster',
        'responder': 'Onkel Franz',
        'applied': false,
        'compare': {
          'BIRT_DATE': {'before': '', 'after': '3 MAY 1980'},
          'SURN': {'before': 'Muster', 'after': 'Mustermann'},
        },
      },
    );

    await pumpPushed(tester);

    expect(find.text('Für: Anna Muster'), findsOneWidget);
    expect(find.text('Von: Onkel Franz'), findsOneWidget);
    expect(find.text('Geburtsdatum'), findsOneWidget);
    expect(find.text('Nachname'), findsOneWidget);
    expect(find.text('Bisher: (leer)'), findsOneWidget);
    expect(find.text('Neu: 3 MAY 1980'), findsOneWidget);
    expect(find.text('Bisher: Muster'), findsOneWidget);
    expect(find.text('Neu: Mustermann'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull, reason: 'nothing is ticked yet, so Apply should be disabled');
  });

  testWidgets('ticking a field enables Apply; applying with a nextId pushes the next request', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {
        'id': 7,
        'name': 'Anna Muster',
        'applied': false,
        'compare': {
          'SURN': {'before': 'Muster', 'after': 'Mustermann'},
        },
      },
    );
    when(() => client.shareRequestDetail('Famtree', 8)).thenAnswer(
      (_) async => {'id': 8, 'name': 'Next Person', 'applied': false, 'compare': <String, dynamic>{}},
    );
    when(() => client.shareRequestApply('Famtree', 7, {'SURN': true})).thenAnswer(
      (_) async => {'ok': true, 'nextId': 8},
    );

    await pumpPushed(tester);

    await tester.tap(find.byType(Checkbox));
    await tester.pump();

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);

    await tester.tap(find.text('Ausgewähltes übernehmen'));
    await tester.pumpAndSettle();

    verify(() => client.shareRequestApply('Famtree', 7, {'SURN': true})).called(1);
    expect(find.text('Für: Next Person'), findsOneWidget);
  });

  testWidgets('applying the last request (nextId null) pops and shows a confirmation', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {
        'id': 7,
        'name': 'Anna Muster',
        'applied': false,
        'compare': {
          'SURN': {'before': 'Muster', 'after': 'Mustermann'},
        },
      },
    );
    when(() => client.shareRequestApply('Famtree', 7, {'SURN': true})).thenAnswer((_) async => {'ok': true});

    await pumpPushed(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Ausgewähltes übernehmen'));
    await tester.pump();
    await tester.pump();
    // Let the pop transition run to completion (default 300ms) while
    // stopping well short of the SnackBar's own 4s auto-dismiss timer.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ResponseDetailScreen), findsNothing);
    expect(find.text('Alle Antworten geprüft.'), findsOneWidget);
  });

  testWidgets('a failed apply shows an error snackbar and re-enables the form', (tester) async {
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {
        'id': 7,
        'name': 'Anna Muster',
        'applied': false,
        'compare': {
          'SURN': {'before': 'Muster', 'after': 'Mustermann'},
        },
      },
    );
    when(() => client.shareRequestApply('Famtree', 7, {'SURN': true})).thenThrow(Exception('server error'));

    await pumpPushed(tester);
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
    await tester.tap(find.text('Ausgewähltes übernehmen'));
    await tester.pumpAndSettle();

    expect(find.byType(ResponseDetailScreen), findsOneWidget);
    expect(find.textContaining('Konnte nicht übernommen werden:'), findsOneWidget);
  });

  group('discarding', () {
    Map<String, dynamic> loaded() => {
      'id': 7,
      'name': 'Anna Muster',
      'applied': false,
      'compare': {
        'SURN': {'before': 'Muster', 'after': 'Mustermann'},
      },
    };

    testWidgets('confirming discard deletes the request and pops the screen', (tester) async {
      when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer((_) async => loaded());
      when(() => client.shareRequestDelete('Famtree', 7)).thenAnswer((_) async => true);

      await pumpPushed(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();

      verify(() => client.shareRequestDelete('Famtree', 7)).called(1);
      expect(find.byType(ResponseDetailScreen), findsNothing);
    });

    testWidgets('cancelling the dialog never calls shareRequestDelete', (tester) async {
      when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer((_) async => loaded());

      await pumpPushed(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      verifyNever(() => client.shareRequestDelete(any(), any()));
      expect(find.byType(ResponseDetailScreen), findsOneWidget);
    });

    testWidgets('the server refusing to delete shows an error instead of popping', (tester) async {
      when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer((_) async => loaded());
      when(() => client.shareRequestDelete('Famtree', 7)).thenAnswer((_) async => false);

      await pumpPushed(tester);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verwerfen'));
      await tester.pumpAndSettle();

      expect(find.byType(ResponseDetailScreen), findsOneWidget);
      expect(find.text('Konnte nicht verworfen werden.'), findsOneWidget);
    });
  });
}
