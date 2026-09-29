import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
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
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: PersonDetailScreen(xref: 'I1', depth: depth),
        ),
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

  testWidgets('shows the "Person hinzufügen" FAB only when canEdit is true', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: true));
    await pumpScreen(tester);
    expect(find.text('Person hinzufügen'), findsOneWidget);
  });

  testWidgets('hides the "Person hinzufügen" FAB and the edit-mode toggle when canEdit is false', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: false));

    await pumpScreen(tester);

    expect(find.text('Person hinzufügen'), findsNothing);
    expect(find.byTooltip('Bearbeiten'), findsNothing);
  });

  testWidgets('the "Fakt hinzufügen" chip appears in the facts card once expanded, and is hidden when canEdit is false', (
    tester,
  ) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: true));
    await pumpScreen(tester);
    await tester.tap(find.textContaining('Mehr anzeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Fakt hinzufügen'), findsOneWidget);
  });

  testWidgets('the Home shortcut FAB appears once nested one Person screen deep (after the 2nd navigation)', (
    tester,
  ) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester, depth: 0);
    expect(find.byTooltip('Zum Start'), findsNothing);

    await pumpScreen(tester, depth: 1);
    expect(find.byTooltip('Zum Start'), findsOneWidget);
  });

  testWidgets('shows Eltern and a "Familie mit X" group with the partner and children', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester);

    expect(find.text('Eltern'), findsOneWidget);
    expect(find.text('Franz Muster', findRichText: true), findsOneWidget);
    expect(find.text('Maria Muster', findRichText: true), findsOneWidget);

    // The rest of the list (the family group) is below the fold at the
    // test surface's default size, so it isn't built yet - a plain
    // ListView's slivers only inflate children near the viewport, even
    // though its `children:` list is a fully eager Dart List<Widget>.
    // Scroll it into view rather than asserting on unbuilt widgets.
    await tester.scrollUntilVisible(find.text('Familie mit Karl Beispiel'), 300);

    expect(find.text('Familie mit Karl Beispiel'), findsOneWidget);
    expect(find.text('Karl Beispiel', findRichText: true), findsOneWidget);
    expect(find.text('Lena Beispiel', findRichText: true), findsOneWidget);
  });

  testWidgets('shows a Geschwister section when the person has siblings', (tester) async {
    final json = personJson('I1');
    json['siblings'] = [
      {'xref': 'I6', 'name': 'Peter Muster', 'sex': 'M', 'isDead': false},
    ];
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Geschwister'), 300);

    expect(find.text('Geschwister'), findsOneWidget);
    expect(find.text('Peter Muster', findRichText: true), findsOneWidget);
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

  testWidgets('entering edit mode shows the fact fields and does not overflow the layout', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));

    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();

    // Regression test: the bottomNavigationBar's width-capping Center, when
    // given Scaffold's bounded-but-loose height constraint for that slot,
    // expanded to fill the WHOLE Scaffold height (Align/Center only
    // shrink-wraps when its constraint is unbounded - see
    // RenderPositionedBox.performLayout) instead of just the save button's
    // own height. That starved Scaffold's body of all height, so its outer
    // Column (_Header + the facts/edit list) overflowed - and everything
    // inside the now-zero-height ListView viewport stopped being "onstage"
    // (Flutter's sliver viewport only counts children within its laid-out
    // extent as onstage), so finders like find.text/find.byType found
    // nothing even though debugDumpApp() showed the widgets were still in
    // the tree. takeException() alone doesn't catch this (it's a pure
    // layout miscalculation, nothing throws) - the field assertions below
    // are what actually prove the form is usable, not just "no error".
    expect(tester.takeException(), isNull);

    // SEX sorts first, then BIRT (see kFactDisplayOrder), so both editors
    // are near the top of the form and don't need scrolling into view.
    expect(find.text('Geschlecht'), findsOneWidget);
    expect(find.text('Geburt'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);
    expect(
      tester.getTopLeft(find.text('Geschlecht')).dy,
      lessThan(tester.getTopLeft(find.text('Geburt')).dy),
      reason: 'Geschlecht (SEX) must be the first field in the edit form',
    );
  });

  testWidgets(
    'every edit-mode field type (date picker, place autocomplete, sex segment, plain value fields) can be '
    'filled/selected and the new values reach postFact on save',
    (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
      when(
        () => client.postFact('Famtree', 'I1', factId: null, tag: 'BIRT', value: null, date: '20 MAY 1980', place: 'Berlin'),
      ).thenAnswer((_) async => {'ok': true});
      when(
        () => client.postFact('Famtree', 'I1', factId: null, tag: 'SEX', value: 'M', date: null, place: null),
      ).thenAnswer((_) async => {'ok': true});
      when(
        () => client.postFact('Famtree', 'I1', factId: null, tag: 'TITL', value: 'Prof.', date: null, place: null),
      ).thenAnswer((_) async => {'ok': true});

      // The edit form is a ListView taller than the default 800x600 test
      // surface - a real device scrolls it, but repeatedly scrolling to
      // reach each field in turn here fights with scroll-physics settling
      // (overscroll bounce-back can silently scroll a just-revealed field
      // back offscreen between one interaction and the next). This test is
      // about field presence/fillability, not scroll behavior, so give the
      // surface enough height that every field is simultaneously reachable.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Bearbeiten'));
      await tester.pumpAndSettle();

      // BIRT's date: always picker-driven (GedcomDateField never accepts
      // free-text keyboard entry) - open it via its current formatted
      // display and pick a different day to prove a real value takes.
      expect(find.text('3. Mai 1980'), findsOneWidget);
      await tester.tap(find.text('3. Mai 1980'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('20'));
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.text('20. Mai 1980'), findsOneWidget);

      // BIRT's place (PlaceAutocompleteField) is the first plain TextField
      // in the edit form, followed by TITL's value field. REFN (the record
      // ID - system/bookkeeping data) isn't editable at all: see the
      // findsNothing check below.
      await tester.enterText(find.byType(TextField).at(0), 'Berlin');
      await tester.enterText(find.byType(TextField).at(1), 'Prof.');
      expect(find.text('Referenz'), findsNothing);

      // SEX's segmented picker.
      await tester.tap(find.text('Männlich'));
      await tester.pump();

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      verify(
        () => client.postFact('Famtree', 'I1', factId: null, tag: 'BIRT', value: null, date: '20 MAY 1980', place: 'Berlin'),
      ).called(1);
      verify(
        () => client.postFact('Famtree', 'I1', factId: null, tag: 'SEX', value: 'M', date: null, place: null),
      ).called(1);
      verify(
        () => client.postFact('Famtree', 'I1', factId: null, tag: 'TITL', value: 'Prof.', date: null, place: null),
      ).called(1);
      verifyNever(() => client.postFact('Famtree', 'I1', factId: any(named: 'factId'), tag: 'REFN', value: any(named: 'value'), date: any(named: 'date'), place: any(named: 'place')));
      expect(find.text('Änderungen gespeichert — wartet ggf. auf Freigabe.'), findsOneWidget);
    },
  );

  testWidgets('record-metadata fields (Datensatz-ID, Quellenangabe, ...) are visible read-only but never editable', (
    tester,
  ) async {
    final json = personJson('I1');
    json['facts'] = [
      ...json['facts'] as List<dynamic>,
      {'tag': 'RIN', 'label': 'Datensatz-ID', 'value': '123'},
      {'tag': 'SOUR', 'label': 'Quellenangabe', 'value': 'Kirchenbuch'},
    ];
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

    await pumpScreen(tester);
    await tester.tap(find.textContaining('Mehr anzeigen'));
    await tester.pumpAndSettle();
    expect(find.text('Datensatz-ID'), findsOneWidget, reason: 'still shown read-only');
    expect(find.text('Quellenangabe'), findsOneWidget, reason: 'still shown read-only');

    await tester.tap(find.byTooltip('Bearbeiten'));
    await tester.pumpAndSettle();
    expect(find.text('Datensatz-ID'), findsNothing);
    expect(find.text('Quellenangabe'), findsNothing);
  });

  testWidgets(
    'CHAN ("Aktualisiert am") never appears at all, not even read-only under "Mehr anzeigen" - unlike RIN/SOUR/REFN',
    (tester) async {
      final json = personJson('I1');
      json['facts'] = [
        ...json['facts'] as List<dynamic>,
        {
          'tag': 'CHAN',
          'label': 'Aktualisiert am',
          'value': '',
          'date': {'text': '1. Jan 2026', 'gedcom': '1 JAN 2026'},
        },
      ];
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

      await pumpScreen(tester);
      await tester.tap(find.textContaining('Mehr anzeigen'));
      await tester.pumpAndSettle();
      expect(find.text('Aktualisiert am'), findsNothing, reason: 'not even in the read-only card');

      await tester.tap(find.byTooltip('Bearbeiten'));
      await tester.pumpAndSettle();
      expect(find.text('Aktualisiert am'), findsNothing, reason: 'nor in the edit form');
    },
  );

  testWidgets(
    'regression: opening edit mode pre-selects the sex segment that is actually already set',
    (tester) async {
      // The SEX fact's own `value` is always webtrees' localized display
      // text ("Weiblich"), never the raw 'M'/'F'/'U' code the segmented
      // picker compares against - using it directly left the picker with
      // nothing selected even though the person clearly has a sex set.
      // The raw code has to come from `person['sex']` instead.
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', sex: 'F'));

      await pumpScreen(tester);
      await tester.tap(find.byTooltip('Bearbeiten'));
      await tester.pumpAndSettle();

      final femaleChip = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('Weiblich'), matching: find.byType(ChoiceChip)),
      );
      expect(femaleChip.selected, isTrue, reason: 'Weiblich must already be selected, not left blank');

      final maleChip = tester.widget<ChoiceChip>(
        find.ancestor(of: find.text('Männlich'), matching: find.byType(ChoiceChip)),
      );
      expect(maleChip.selected, isFalse);
    },
  );

  group('AddFactSheet (Fakt hinzufügen)', () {
    testWidgets('the tag picker, value field, and (once a tag is chosen) date field can all be filled and are sent on save', (
      tester,
    ) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
      when(() => client.tags('Famtree', type: 'INDI')).thenAnswer(
        (_) async => {
          'data': [
            {'tag': 'OCCU', 'label': 'Beruf'},
            {'tag': 'RELI', 'label': 'Religion'},
          ],
        },
      );
      when(
        () => client.postFact('Famtree', 'I1', tag: 'OCCU', value: 'Bäcker', date: any(named: 'date')),
      ).thenAnswer((_) async => {'ok': true});

      await pumpScreen(tester);

      // The "Fakt hinzufügen" chip lives inside the facts card, revealed
      // once "Mehr anzeigen" is expanded - not the FAB (that's now "Person
      // hinzufügen").
      await tester.tap(find.textContaining('Mehr anzeigen'));
      await tester.pumpAndSettle();

      // In the small test viewport, the newly-revealed chip ends up right
      // behind the floating "Person hinzufügen" FAB, which sits on top and
      // would otherwise absorb the tap - same as a real (short) screen,
      // where scrolling a bit further clears it.
      await tester.ensureVisible(find.text('Fakt hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fakt hinzufügen'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Beruf'));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Bäcker');

      expect(find.text('Datum wählen'), findsOneWidget);
      await tester.tap(find.text('Datum wählen'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('1'));
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
      await tester.pumpAndSettle();

      verify(() => client.postFact('Famtree', 'I1', tag: 'OCCU', value: 'Bäcker', date: any(named: 'date'))).called(1);
    });

    testWidgets('record-metadata tags (Aktualisiert am, Datensatz-ID, ...) never appear as addable, even if the server sends them', (
      tester,
    ) async {
      // Regression test: the server's own tag list isn't filtered - it
      // sends every GEDCOM tag it knows about, including system ones. The
      // app has to exclude them itself, same as it already does for the
      // inline edit form's own field list.
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
      // Distinct labels from personJson's own REFN fact ("Referenz"),
      // which is legitimately shown read-only elsewhere on this same
      // screen once expanded - that's not what this test is about, so it
      // uses different label text to avoid colliding with it.
      when(() => client.tags('Famtree', type: 'INDI')).thenAnswer(
        (_) async => {
          'data': [
            {'tag': 'OCCU', 'label': 'Beruf'},
            {'tag': 'CHAN', 'label': 'Aktualisiert am'},
            {'tag': 'RIN', 'label': 'Datensatz-ID (Server)'},
            {'tag': 'SOUR', 'label': 'Quellenangabe (Server)'},
          ],
        },
      );

      await pumpScreen(tester);
      await tester.tap(find.textContaining('Mehr anzeigen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fakt hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fakt hinzufügen'));
      await tester.pumpAndSettle();

      expect(find.text('Beruf'), findsOneWidget);
      expect(find.text('Aktualisiert am'), findsNothing);
      expect(find.text('Datensatz-ID (Server)'), findsNothing);
      expect(find.text('Quellenangabe (Server)'), findsNothing);
    });
  });
}
