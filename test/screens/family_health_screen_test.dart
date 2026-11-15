import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/family_health/family_health_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/state/family_health_overlay.dart';
import 'package:webtrees_mobile/utils/tab_navigation.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  const catalog = {
    'categories': [
      {'id': 'cardiovascular', 'name': 'Herz und Kreislauf'},
      {'id': 'cancer', 'name': 'Krebs'},
      {'id': 'other', 'name': 'Sonstiges'},
    ],
  };

  Map<String, dynamic> illness(
    String name,
    String category, {
    bool isEarly = false,
    int? age,
  }) => {
    'xref': 'I2',
    'name': 'Maria Gesund',
    'relationship': 'Mutter',
    'degree': 1,
    'illness': name,
    'category': category,
    'icd': category == 'cancer' ? 'C50' : '',
    'date': '',
    'dateText': 'um 1960',
    'age': age,
    'isEarly': isEarly,
  };

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.usePrettyUrls).thenReturn(false);
    when(() => client.familyHealthCatalog('Famtree'))
        .thenAnswer((_) async => catalog);
    container = ProviderContainer(
      overrides: [webtreesClientProvider.overrideWithValue(client)],
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
          locale: Locale('de'),
          home: FamilyHealthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'groups the illnesses by category, with relationship, degree, age and early onset',
    (tester) async {
      when(() => client.familyHistory('Famtree')).thenAnswer(
        (_) async => {
          'subjects': [
            {'xref': 'I3', 'name': 'Paul Gesund'},
          ],
          'xref': 'I3',
          'earlyAge': 50,
          'illnesses': [
            illness('Brustkrebs', 'cancer', isEarly: true, age: 42),
            illness('Herzinfarkt', 'cardiovascular', age: 70),
          ],
        },
      );

      await pumpScreen(tester);

      expect(
        find.text('Krebs'),
        findsNWidgets(2),
      ); // filter chip and group heading
      expect(find.text('Brustkrebs (C50)'), findsOneWidget);
      expect(find.text('Maria Gesund · Mutter · 1. Grad'), findsNWidgets(2));
      expect(find.text('um 1960 · mit 42 Jahren'), findsOneWidget);
      expect(find.text('früh'), findsOneWidget);
      expect(
        find.text('Früh: Diagnose vor dem Alter von 50 Jahren.'),
        findsOneWidget,
      );
      // Herz und Kreislauf comes before Krebs - the module's order of categories.
      expect(
        tester.getTopLeft(find.text('Herzinfarkt')).dy <
            tester.getTopLeft(find.text('Brustkrebs (C50)')).dy,
        isTrue,
      );
      // Only one individual: no choice to make.
      expect(find.text('Paul Gesund'), findsNothing);
    },
  );

  testWidgets('the filter bar shows one category only', (tester) async {
    when(() => client.familyHistory('Famtree')).thenAnswer(
      (_) async => {
        'subjects': [
          {'xref': 'I3', 'name': 'Paul Gesund'},
        ],
        'xref': 'I3',
        'earlyAge': 50,
        'illnesses': [
          illness('Brustkrebs', 'cancer'),
          illness('Herzinfarkt', 'cardiovascular'),
        ],
      },
    );

    await pumpScreen(tester);
    // Only categories in use get a chip.
    expect(find.text('Sonstiges'), findsNothing);

    // The filter bar scrolls sideways.
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Krebs'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Krebs'));
    await tester.pumpAndSettle();
    expect(find.text('Herzinfarkt'), findsNothing);
    expect(find.text('Brustkrebs (C50)'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Alle'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Alle'));
    await tester.pumpAndSettle();
    expect(find.text('Herzinfarkt'), findsOneWidget);
  });

  testWidgets('switches to a child under 18', (tester) async {
    const subjects = [
      {'xref': 'I3', 'name': 'Paul Gesund'},
      {'xref': 'I6', 'name': 'Kind Gesund'},
    ];
    when(() => client.familyHistory('Famtree')).thenAnswer(
      (_) async => {
        'subjects': subjects,
        'xref': 'I3',
        'earlyAge': 50,
        'illnesses': <dynamic>[],
      },
    );
    when(() => client.familyHistory('Famtree', xref: 'I6')).thenAnswer(
      (_) async => {
        'subjects': subjects,
        'xref': 'I6',
        'earlyAge': 50,
        'illnesses': [illness('Diabetes Typ 2', 'other')],
      },
    );

    await pumpScreen(tester);
    expect(
      find.text('Für die Blutsverwandten sind keine Erkrankungen eingetragen.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Kind Gesund'));
    await tester.pumpAndSettle();
    expect(find.text('Diabetes Typ 2'), findsOneWidget);
    verify(() => client.familyHistory('Famtree', xref: 'I6')).called(1);
  });

  testWidgets('"Im Stammbaum zeigen" turns on family health in the tree, with the picked category', (tester) async {
    when(() => client.familyHistory('Famtree')).thenAnswer(
      (_) async => {
        'subjects': [
          {'xref': 'I3', 'name': 'Paul Gesund'},
        ],
        'xref': 'I3',
        'earlyAge': 50,
        'illnesses': [illness('Brustkrebs', 'cancer')],
      },
    );
    when(() => client.familyHealthIllnesses('Famtree')).thenAnswer(
      (_) async => {
        'illnesses': [
          {'xref': 'I2', 'category': 'cancer'},
          {'xref': 'I3', 'category': 'other'},
        ],
      },
    );

    await pumpScreen(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Krebs'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Im Stammbaum zeigen'));
    await tester.pumpAndSettle();

    final overlay = container.read(familyHealthOverlayProvider)!;
    expect(overlay.category, 'cancer');
    expect(overlay.isFaded('I2'), isFalse);
    expect(overlay.isFaded('I3'), isTrue); // only "Sonstiges", and Krebs is picked
    expect(container.read(selectedTabProvider), kTreeTabIndex);
  });

  testWidgets('without a linked individual: a hint', (tester) async {
    when(() => client.familyHistory('Famtree')).thenAnswer(
      (_) async => {
        'subjects': <dynamic>[],
        'xref': null,
        'earlyAge': 50,
        'illnesses': <dynamic>[],
      },
    );

    await pumpScreen(tester);
    expect(find.textContaining('keiner Person'), findsOneWidget);
  });

  testWidgets('a load error instead of a spinner forever', (tester) async {
    when(() => client.familyHistory('Famtree'))
        .thenAnswer((_) async => throw const UnexpectedResponseException(404));

    await pumpScreen(tester);
    expect(find.textContaining('Konnte nicht laden:'), findsOneWidget);
  });
}
