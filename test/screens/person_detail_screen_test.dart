import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;
  setUp(() {
    clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  late MockWebtreesClient client;
  late ProviderContainer container;

  Map<String, dynamic> personJson(String xref, {String name = 'Anna /Muster/', String sex = 'F', bool canEdit = true}) => {
    'ok': true,
    'person': {'xref': xref, 'name': name, 'sex': sex, 'isDead': false, 'lifespan': '* 1980'},
    'facts': [
      {
        'tag': 'BIRT',
        'label': 'Geburt',
        'value': '',
        'date': {'text': '3. Mai 1980', 'gedcom': '3 MAY 1980'},
        'place': {'short': 'Wien'},
      },
      {'tag': 'SEX', 'label': 'Geschlecht', 'value': 'Weiblich'},
      {'tag': 'TITL', 'label': 'Titel', 'value': 'Dr.'},
      {'tag': 'REFN', 'label': 'Referenz', 'value': 'REF-123'},
    ],
    'parentFamilies': [
      {
        'husband': {'xref': 'I2', 'name': 'Franz Muster', 'sex': 'M', 'isDead': false},
        'wife': {'xref': 'I3', 'name': 'Maria Muster', 'sex': 'F', 'isDead': false},
      },
    ],
    'spouseFamilies': [
      {
        'spouse': {'xref': 'I4', 'name': 'Karl Beispiel', 'sex': 'M', 'isDead': false},
        'children': [
          {'xref': 'I5', 'name': 'Lena Beispiel', 'sex': 'F', 'isDead': false},
        ],
      },
    ],
    'siblings': <dynamic>[],
    'media': <dynamic>[],
    'canEdit': canEdit,
  };

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester, {int depth = 0}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: PersonDetailScreen(xref: 'I1', depth: depth)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('shows the name, lifespan, and only the primary facts until expanded', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester);

    // Appears twice: once in the header bar, once as the large name below
    // the avatar.
    expect(find.text('Anna Muster'), findsNWidgets(2));
    expect(find.text('* 1980'), findsOneWidget);
    expect(find.text('Geburt'), findsOneWidget);
    expect(find.text('Geschlecht'), findsOneWidget);
    expect(find.text('Titel'), findsNothing);
    expect(find.text('Referenz'), findsNothing);
    expect(find.text('Mehr anzeigen (2)'), findsOneWidget);

    await tester.tap(find.text('Mehr anzeigen (2)'));
    await tester.pump();

    expect(find.text('Titel'), findsOneWidget);
    expect(find.text('Referenz'), findsOneWidget);
    expect(find.text('Weniger anzeigen'), findsOneWidget);
  });

  testWidgets('tapping a fact copies its date+place text to the clipboard', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester);

    await tester.tap(find.text('Geburt'));
    await tester.pump();

    expect(clipboardText, '3. Mai 1980 · Wien');
  });

  testWidgets('shows the "Fakt hinzufügen" FAB only when canEdit is true', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: true));
    await pumpScreen(tester);
    expect(find.text('Fakt hinzufügen'), findsOneWidget);
  });

  testWidgets('hides the "Fakt hinzufügen" FAB and the edit-mode toggle when canEdit is false', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: false));

    await pumpScreen(tester);

    expect(find.text('Fakt hinzufügen'), findsNothing);
    expect(find.byTooltip('Bearbeiten'), findsNothing);
  });

  testWidgets('the Home shortcut FAB only appears once nested two Person screens deep', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester, depth: 1);
    expect(find.byTooltip('Zum Start'), findsNothing);

    await pumpScreen(tester, depth: 2);
    expect(find.byTooltip('Zum Start'), findsOneWidget);
  });

  testWidgets('shows Eltern, spouse and Kinder sections with the right titles and people', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester);

    expect(find.text('Eltern'), findsOneWidget);
    expect(find.text('Franz Muster', findRichText: true), findsOneWidget);
    expect(find.text('Maria Muster', findRichText: true), findsOneWidget);

    // The rest of the list (spouse/children sections) is below the fold at
    // the test surface's default size, so it isn't built yet - a plain
    // ListView's slivers only inflate children near the viewport, even
    // though its `children:` list is a fully eager Dart List<Widget>.
    // Scroll it into view rather than asserting on unbuilt widgets.
    await tester.scrollUntilVisible(find.text('Ehepartner', findRichText: false), 300);

    expect(find.text('Ehepartner', findRichText: false), findsOneWidget);
    expect(find.text('Karl Beispiel', findRichText: true), findsOneWidget);
    expect(find.text('Kinder (1)'), findsOneWidget);
    expect(find.text('Lena Beispiel', findRichText: true), findsOneWidget);
  });

  testWidgets('tapping a child pushes another PersonDetailScreen one level deeper', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
    when(() => client.individual('Famtree', 'I5')).thenAnswer((_) async => personJson('I5', name: 'Lena Beispiel'));

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Lena Beispiel', findRichText: true), 300);

    await tester.tap(find.text('Lena Beispiel', findRichText: true));
    await tester.pumpAndSettle();

    final screens = tester.widgetList<PersonDetailScreen>(find.byType(PersonDetailScreen));
    expect(screens.map((s) => (s.xref, s.depth)), contains(('I5', 1)));
  });

  testWidgets('shows "Kein Zugriff" when the server denies access', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {'ok': false, 'error': 'privacy'},
    );

    await pumpScreen(tester);

    expect(find.text('Kein Zugriff: privacy'), findsOneWidget);
  });

  testWidgets('shows a load error instead of crashing', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) => Future.error(Exception('offline')));

    await pumpScreen(tester);

    expect(find.textContaining('Konnte nicht laden:'), findsOneWidget);
  });
}
