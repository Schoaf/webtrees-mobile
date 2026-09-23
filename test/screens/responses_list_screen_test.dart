import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/screens/responses/response_detail_screen.dart';
import 'package:webtrees_mobile/screens/responses/responses_list_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ResponsesListScreen()),
      ),
    );
  }

  testWidgets('shows a loading spinner, then the fetched requests', (tester) async {
    when(() => client.shareRequestList('Famtree')).thenAnswer(
      (_) async => [
        {'id': 1, 'xref': 'I1', 'name': 'Anna Muster', 'status': 'pending', 'responder': 'Onkel Franz'},
      ],
    );

    await pumpScreen(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Anna Muster'), findsOneWidget);
    expect(find.text('Von Onkel Franz'), findsOneWidget);
  });

  testWidgets('shows an empty-state message when there are no requests', (tester) async {
    when(() => client.shareRequestList('Famtree')).thenAnswer((_) async => []);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Keine Antworten vorhanden.'), findsOneWidget);
  });

  testWidgets('shows a load error instead of crashing', (tester) async {
    when(() => client.shareRequestList('Famtree')).thenAnswer((_) => Future<List<Map<String, dynamic>>>.error(Exception('offline')));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Konnte nicht laden:'), findsOneWidget);
  });

  testWidgets('tapping a request pushes ResponseDetailScreen for its id', (tester) async {
    when(() => client.shareRequestList('Famtree')).thenAnswer(
      (_) async => [
        {'id': 7, 'xref': 'I1', 'name': 'Anna Muster', 'status': 'pending', 'responder': ''},
      ],
    );
    when(() => client.shareRequestDetail('Famtree', 7)).thenAnswer(
      (_) async => {'id': 7, 'name': 'Anna Muster', 'applied': false, 'compare': <String, dynamic>{}},
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anna Muster'));
    await tester.pumpAndSettle();

    expect(find.byType(ResponseDetailScreen), findsOneWidget);
    final screen = tester.widget<ResponseDetailScreen>(find.byType(ResponseDetailScreen));
    expect(screen.id, 7);
  });

  testWidgets('discarding a request confirms, calls shareRequestDelete, and removes the row', (tester) async {
    when(() => client.shareRequestList('Famtree')).thenAnswer(
      (_) async => [
        {'id': 7, 'xref': 'I1', 'name': 'Anna Muster', 'status': 'pending', 'responder': ''},
      ],
    );
    when(() => client.shareRequestDelete('Famtree', 7)).thenAnswer((_) async => true);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Anna Muster'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    expect(find.text('Anfrage verwerfen?'), findsOneWidget);
    await tester.tap(find.text('Verwerfen'));
    await tester.pumpAndSettle();

    verify(() => client.shareRequestDelete('Famtree', 7)).called(1);
    expect(find.text('Anna Muster'), findsNothing);
    expect(find.text('Keine Antworten vorhanden.'), findsOneWidget);
  });

  testWidgets('cancelling the discard dialog keeps the row and never calls shareRequestDelete', (tester) async {
    when(() => client.shareRequestList('Famtree')).thenAnswer(
      (_) async => [
        {'id': 7, 'xref': 'I1', 'name': 'Anna Muster', 'status': 'pending', 'responder': ''},
      ],
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.drag(find.text('Anna Muster'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();

    verifyNever(() => client.shareRequestDelete(any(), any()));
    expect(find.text('Anna Muster'), findsOneWidget);
  });
}
