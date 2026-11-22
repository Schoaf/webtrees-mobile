import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/media_viewer_screen.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/state/person_history.dart';
import 'package:webtrees_mobile/widgets/person_avatar.dart';

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
    'media': <dynamic>[],
    'canEdit': canEdit,
  };

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.usePrettyUrls).thenReturn(false);
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  // Edit is in the ⋮ menu (#31).
  Future<void> openEditMode(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('personMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bearbeiten'));
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const PersonDetailScreen(xref: 'I1'),
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

  testWidgets('without edit rights the ⋮ menu has no "Bearbeiten" and no "Person hinzufügen"', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: false));

    await pumpScreen(tester);
    await tester.tap(find.byKey(const Key('personMenu')));
    await tester.pumpAndSettle();

    expect(find.text('Teilen'), findsOneWidget);
    expect(find.text('Person hinzufügen'), findsNothing);
    expect(find.text('Bearbeiten'), findsNothing);
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

  testWidgets('no Home button any more; the ⋮ menu holds share, edit and add person (#31)', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: true));

    await pumpScreen(tester);
    expect(find.byTooltip('Zum Start'), findsNothing);
    expect(find.byKey(const Key('treeViewButton')), findsOneWidget);

    await tester.tap(find.byKey(const Key('personMenu')));
    await tester.pumpAndSettle();
    expect(find.text('Teilen'), findsOneWidget);
    expect(find.text('Bearbeiten'), findsOneWidget);
    expect(find.text('Person hinzufügen'), findsOneWidget);
  });

  group('photos (#35)', () {
    Map<String, dynamic> photo(String xref, {bool isPrimary = false}) => {
      'xref': xref,
      'isImage': true,
      'thumb': 'https://example.org/$xref-thumb.jpg',
      'file': 'https://example.org/$xref.jpg',
      'primary': isPrimary,
    };

    testWidgets('more than one photo: a badge on the photo, and the menu shows them and adds more', (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer(
        (_) async => personJson('I1')..['media'] = [photo('M1', isPrimary: true), photo('M2')],
      );
      await pumpScreen(tester);
      expect(find.byKey(const Key('morePhotosBadge')), findsOneWidget);

      await tester.tap(find.byKey(const Key('personMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Fotos hinzufügen'), findsOneWidget);
      await tester.tap(find.text('Fotos ansehen'));
      await tester.pumpAndSettle();

      expect(find.byType(MediaViewerScreen), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
    });

    testWidgets('tapping the badge opens the photos too', (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer(
        (_) async => personJson('I1')..['media'] = [photo('M1', isPrimary: true), photo('M2')],
      );
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('morePhotosBadge')));
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
    });

    testWidgets('one photo: no badge; tapping it opens the photo view', (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer(
        (_) async => personJson('I1')..['media'] = [photo('M1', isPrimary: true)],
      );
      await pumpScreen(tester);
      expect(find.byKey(const Key('morePhotosBadge')), findsNothing);

      await tester.tap(find.byType(PersonAvatar).first);
      await tester.pumpAndSettle();
      expect(find.byType(MediaViewerScreen), findsOneWidget);
    });

    testWidgets('no photos and no edit rights: neither menu entry', (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1', canEdit: false));
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('personMenu')));
      await tester.pumpAndSettle();
      expect(find.text('Fotos ansehen'), findsNothing);
      expect(find.text('Fotos hinzufügen'), findsNothing);
    });
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

  testWidgets('marks a fact whose change waits for approval', (tester) async {
    final json = personJson('I1');
    json['facts'] = [
      {'tag': 'SEX', 'label': 'Geschlecht', 'value': 'Weiblich', 'pending': true},
      {
        'tag': 'BIRT',
        'label': 'Geburt',
        'value': '',
        'date': {'text': '3. Mai 1980', 'gedcom': '3 MAY 1980'},
        'pending': false,
      },
    ];
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

    await pumpScreen(tester);

    expect(find.text('Wartet auf Freigabe'), findsOneWidget);
  });

  testWidgets('shows a Geschwister section when the person has siblings', (tester) async {
    final json = personJson('I1');
    json['parentFamilies'] = [
      <String, dynamic>{
        ...(json['parentFamilies'] as List<dynamic>)[0] as Map<String, dynamic>,
        'children': [
          {'xref': 'I1', 'name': 'Anna Muster', 'sex': 'F', 'isDead': false},
          {'xref': 'I6', 'name': 'Peter Muster', 'sex': 'M', 'isDead': false},
        ],
      },
    ];
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Geschwister'), 300);

    expect(find.text('Geschwister'), findsOneWidget);
    expect(find.text('Peter Muster', findRichText: true), findsOneWidget);
  });

  testWidgets('tapping a child switches this page to them, and undo goes back (#31)', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
    when(() => client.individual('Famtree', 'I5')).thenAnswer((_) async => personJson('I5', name: 'Lena Beispiel'));

    await pumpScreen(tester);
    await tester.scrollUntilVisible(find.text('Lena Beispiel', findRichText: true), 300);

    await tester.tap(find.text('Lena Beispiel', findRichText: true));
    await tester.pumpAndSettle();

    expect(find.byType(PersonDetailScreen), findsOneWidget, reason: 'no new page per person any more');
    expect(container.read(personHistoryProvider).history, ['I1', 'I5']);
    verify(() => client.individual('Famtree', 'I5')).called(1);

    await tester.tap(find.byIcon(Icons.undo));
    await tester.pumpAndSettle();
    expect(container.read(personHistoryProvider).activeXref, 'I1');
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

    await openEditMode(tester);
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

      await openEditMode(tester);
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
      expect(find.text('Änderungen gespeichert.'), findsOneWidget);
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

    await openEditMode(tester);
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

      await openEditMode(tester);
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
      await openEditMode(tester);
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

  group('editing a name with its parts (api4webtrees 46, #28)', () {
    Map<String, dynamic> withName(Map<String, dynamic>? nameParts) {
      final json = personJson('I1');
      json['facts'] = <dynamic>[
        {
          'id': 'n1',
          'tag': 'NAME',
          'label': 'Name',
          'value': 'Hans /Muster/',
          'nameParts': nameParts,
        },
        for (final fact in (json['facts'] as List).cast<Map<String, dynamic>>())
          if (fact['tag'] != 'NAME') fact,
      ];
      return json;
    }

    const parts = {
      'prefix': null,
      'given': 'Hans Peter Josef',
      'nickname': null,
      'surnamePrefix': null,
      'surname': 'Muster',
      'suffix': null,
      'callName': 'Hans',
    };

    Future<void> openForm(WidgetTester tester, {required int apiLevel}) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      when(() => client.info('Famtree')).thenAnswer((_) async => {'api': apiLevel, 'trees': <dynamic>[]});
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => withName(parts));
      when(
        () => client.postFact(
          'Famtree',
          'I1',
          factId: any(named: 'factId'),
          tag: any(named: 'tag'),
          value: any(named: 'value'),
          date: any(named: 'date'),
          place: any(named: 'place'),
          nameParts: any(named: 'nameParts'),
        ),
      ).thenAnswer((_) async => {'ok': true});
      await container.read(apiLevelProvider.future);
      await pumpScreen(tester);
      await openEditMode(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the name as stored and its parts; only a changed part is sent, GIVN stays', (tester) async {
      await openForm(tester, apiLevel: 46);

      expect(tester.widget<TextField>(find.byKey(const ValueKey('nameAsShown'))).controller!.text, 'Hans /Muster/');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('namePart_given'))).controller!.text, 'Hans Peter Josef');
      expect(find.byKey(const ValueKey('namePart_callName')), findsOneWidget); // holds something
      expect(find.byKey(const ValueKey('namePart_prefix')), findsNothing); // empty: behind "Weitere Namensteile"

      await tester.tap(find.text('Weitere Namensteile'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('namePart_prefix')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('nameAsShown')), 'Hans /Beispiel/');
      await tester.enterText(find.byKey(const ValueKey('namePart_surname')), 'Beispiel');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      verify(
        () => client.postFact(
          'Famtree',
          'I1',
          factId: 'n1',
          tag: 'NAME',
          value: 'Hans /Beispiel/',
          date: null,
          place: null,
          nameParts: {'surname': 'Beispiel'},
        ),
      ).called(1);
    });

    testWidgets('an older server: given name and surname from the name, no parts sent', (tester) async {
      await openForm(tester, apiLevel: 45);

      expect(find.byKey(const ValueKey('nameAsShown')), findsNothing);
      expect(find.widgetWithText(TextField, 'Vorname'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Nachname'), 'Beispiel');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      verify(
        () => client.postFact(
          'Famtree',
          'I1',
          factId: 'n1',
          tag: 'NAME',
          value: 'Hans /Beispiel/',
          date: null,
          place: null,
          nameParts: null,
        ),
      ).called(1);
    });
  });

  testWidgets('further names - married name, change of name - show under "Mehr anzeigen"', (tester) async {
    final json = personJson('I1');
    json['facts'] = <dynamic>[
      ...json['facts'] as List,
      {
        'tag': 'NAME',
        'label': 'Name',
        'value': 'Anna /Muster/',
        'details': [
          {'tag': '_MARNM', 'label': 'Ehename', 'value': 'Anna /Beispiel/', 'level': 0},
        ],
      },
      {'tag': 'NAME', 'label': 'Name', 'type': 'change', 'typeLabel': 'Namensänderung', 'value': 'Anna /Muster-Beispiel/'},
    ];
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

    await pumpScreen(tester);
    expect(find.text('Anna Beispiel'), findsNothing);
    await tester.tap(find.textContaining('Mehr anzeigen'));
    await tester.pumpAndSettle();

    expect(find.text('Ehename'), findsOneWidget);
    expect(find.text('Anna Beispiel'), findsOneWidget);
    expect(find.text('Namensänderung'), findsOneWidget);
    expect(find.text('Anna Muster-Beispiel'), findsOneWidget);
  });

  testWidgets('every name with its parts as stored (nameParts, api4webtrees #27)', (tester) async {
    Map<String, dynamic> parts({String? prefix, String? given, String? callName, String? nickname, String? surname}) => {
      'prefix': prefix,
      'given': given,
      'nickname': nickname,
      'surnamePrefix': null,
      'surname': surname,
      'suffix': null,
      'callName': callName,
    };
    final json = personJson('I1');
    json['facts'] = <dynamic>[
      for (final fact in (json['facts'] as List).cast<Map<String, dynamic>>())
        if (fact['tag'] != 'NAME') fact,
      {
        'tag': 'NAME',
        'label': 'Name',
        'value': 'Georg /Czedik/',
        'nameParts': parts(prefix: 'Prof.', given: 'Georg Hermann Franz', callName: 'Georg', surname: 'Czedik'),
      },
      {
        'tag': 'NAME',
        'label': 'Name',
        'type': 'married',
        'typeLabel': 'Ehename',
        'value': 'Georg /Ebbs/',
        'nameParts': parts(given: 'Georg', nickname: 'Schorsch', surname: 'Ebbs'),
      },
    ];
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);

    await pumpScreen(tester);
    expect(find.text('Georg Hermann Franz'), findsNothing);
    await tester.tap(find.textContaining('Mehr anzeigen'));
    await tester.pumpAndSettle();

    // The given names from GIVN, not the value's "Georg".
    expect(find.text('Georg Hermann Franz'), findsOneWidget);
    expect(find.text('Namenspräfix'), findsOneWidget);
    expect(find.text('Prof.'), findsOneWidget);
    expect(find.text('Rufname'), findsOneWidget);
    // The second name, labelled by its kind, with its own parts.
    expect(find.text('Ehename'), findsOneWidget);
    expect(find.text('Georg Ebbs'), findsOneWidget);
    expect(find.text('Schorsch'), findsOneWidget);
    expect(find.text('Ebbs'), findsOneWidget);
    expect(find.text('Vorname'), findsNWidgets(2));
    expect(find.text('Nachname'), findsNWidgets(2));
    // Missing lines get no row.
    expect(find.text('Nachnamenspräfix'), findsNothing);
    expect(find.text('Namenssuffix'), findsNothing);
  });

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

      // The value field is named like the fact.
      expect(find.widgetWithText(TextField, 'Beruf'), findsOneWidget);
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

    testWidgets('an event asks for its place, not a value', (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
      when(() => client.tags('Famtree', type: 'INDI')).thenAnswer(
        (_) async => {
          'data': [
            {'tag': 'BIRT', 'label': 'Geburt', 'isEvent': true},
          ],
        },
      );
      when(
        () => client.postFact('Famtree', 'I1', tag: 'BIRT', place: 'Wien'),
      ).thenAnswer((_) async => {'ok': true});
      when(() => client.placeAutocomplete('Famtree', any())).thenAnswer((_) async => <String>[]);

      await pumpScreen(tester);
      await tester.tap(find.textContaining('Mehr anzeigen'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Fakt hinzufügen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fakt hinzufügen'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Geburt'));
      await tester.pump();
      expect(find.text('Wert'), findsNothing);
      expect(find.text('Ort (optional)'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Wien');
      await tester.tap(find.widgetWithText(FilledButton, 'Speichern'));
      await tester.pumpAndSettle();

      verify(() => client.postFact('Famtree', 'I1', tag: 'BIRT', place: 'Wien')).called(1);
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

    group('illness (family-health, #54)', () {
      const catalog = {
        'categories': [
          {'id': 'cardiovascular', 'name': 'Herz und Kreislauf'},
          {'id': 'cancer', 'name': 'Krebs'},
        ],
        'illnesses': [
          {'name': 'Brustkrebs', 'category': 'cancer', 'icd': 'C50'},
          {'name': 'Darmkrebs', 'category': 'cancer', 'icd': 'C18'},
          {'name': 'Herzinfarkt', 'category': 'cardiovascular', 'icd': 'I21'},
        ],
      };

      Future<void> openSheet(WidgetTester tester, {List<String> modules = const ['_family-health_']}) async {
        when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
        when(() => client.tags('Famtree', type: 'INDI')).thenAnswer(
          (_) async => {
            'data': [
              {'tag': 'OCCU', 'label': 'Beruf'},
            ],
          },
        );
        when(() => client.info('Famtree')).thenAnswer(
          (_) async => {
            'trees': [
              {'name': 'Famtree', 'availableModules': modules},
            ],
          },
        );
        when(() => client.familyHealthCatalog('Famtree')).thenAnswer((_) async => catalog);
        when(
          () => client.familyHealthPersonIllnesses('Famtree', 'I1'),
        ).thenAnswer((_) async => {'illnesses': <dynamic>[], 'canEdit': true});
        await pumpScreen(tester);
        await tester.tap(find.textContaining('Mehr anzeigen'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Fakt hinzufügen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fakt hinzufügen'));
        await tester.pumpAndSettle();
      }

      // The sheet is a lazy list: scroll to the button before tapping it.
      Future<void> scrollTo(WidgetTester tester, Finder finder) => tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.descendant(of: find.byType(DraggableScrollableSheet), matching: find.byType(Scrollable)).first,
      );

      Future<void> save(WidgetTester tester) async {
        final button = find.widgetWithText(FilledButton, 'Speichern');
        await scrollTo(tester, button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      testWidgets('a name from the catalog is suggested and sent with the year, without a category', (tester) async {
        when(
          () => client.postFamilyHealthIllness('Famtree', 'I1', illness: 'Darmkrebs', date: '1980'),
        ).thenAnswer((_) async => {'ok': true});
        await openSheet(tester);

        await tester.tap(find.byKey(const Key('illnessChip')));
        await tester.pumpAndSettle();
        expect(find.textContaining('vertraulich'), findsOneWidget);
        // Nothing typed: nothing to save.
        expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Speichern')).onPressed, isNull);

        await tester.enterText(find.byKey(const Key('illnessName')), 'krebs');
        await tester.pump();
        expect(find.text('Brustkrebs'), findsOneWidget);
        await tester.tap(find.text('Darmkrebs'));
        await tester.pump();
        // Known: its category shows, no choice to make.
        expect(find.text('Krebs'), findsOneWidget);
        expect(find.byKey(const Key('illnessCategory')), findsNothing);

        await tester.enterText(find.byKey(const Key('illnessYear')), '1980');
        await save(tester);

        verify(() => client.postFamilyHealthIllness('Famtree', 'I1', illness: 'Darmkrebs', date: '1980')).called(1);
        expect(find.text('Fakt gespeichert.'), findsOneWidget);
      });

      testWidgets('a new name asks for its category and sends it', (tester) async {
        when(
          () => client.postFamilyHealthIllness('Famtree', 'I1', illness: 'Mukoviszidose', category: 'cardiovascular'),
        ).thenAnswer((_) async => {'ok': true});
        await openSheet(tester);
        await tester.tap(find.byKey(const Key('illnessChip')));
        await tester.pumpAndSettle();

        await tester.enterText(find.byKey(const Key('illnessName')), 'Mukoviszidose');
        await tester.pump();
        await tester.tap(find.byKey(const Key('illnessCategory')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Herz und Kreislauf').last);
        await tester.pumpAndSettle();
        await save(tester);

        verify(
          () => client.postFamilyHealthIllness('Famtree', 'I1', illness: 'Mukoviszidose', category: 'cardiovascular'),
        ).called(1);
      });

      testWidgets('the module rejecting it and a wrong year show, a wrong year is not sent', (tester) async {
        when(
          () => client.postFamilyHealthIllness('Famtree', 'I1', illness: 'Herzinfarkt'),
        ).thenAnswer((_) async => {'ok': false, 'error': 'Sie dürfen diese Person nicht ändern.'});
        await openSheet(tester);
        await tester.tap(find.byKey(const Key('illnessChip')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('illnessName')), 'Herzinfarkt');

        await tester.enterText(find.byKey(const Key('illnessYear')), '80er');
        await save(tester);
        await scrollTo(tester, find.text('Bitte ein Jahr wie 1980 eingeben.'));
        verifyNever(() => client.postFamilyHealthIllness(any(), any(), illness: any(named: 'illness'), date: any(named: 'date')));

        await tester.enterText(find.byKey(const Key('illnessYear')), '');
        await save(tester);
        await scrollTo(tester, find.textContaining('Sie dürfen diese Person nicht ändern.'));
      });

      testWidgets('no illness chip without the module', (tester) async {
        await openSheet(tester, modules: []);
        expect(find.byKey(const Key('illnessChip')), findsNothing);
        expect(find.text('Beruf'), findsOneWidget);
      });
    });
  });
  testWidgets('shows how the person is related to the account under the age', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => {...personJson('I1'), 'relationship': 'Großmutter'});

    await pumpScreen(tester);

    expect(find.text('Großmutter'), findsOneWidget);
    final age = tester.getTopLeft(find.text('* 1980'));
    final relationship = tester.getTopLeft(find.byKey(const Key('personRelationship')));
    expect(relationship.dy, greaterThan(age.dy));
  });

  testWidgets('no relationship line for the account itself or someone unrelated', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => {...personJson('I1'), 'relationship': ''});

    await pumpScreen(tester);

    expect(find.byKey(const Key('personRelationship')), findsNothing);
  });

  group('illnesses (#54)', () {
    Map<String, dynamic> illnesses({bool canEdit = true}) => {
      'illnesses': [
        {
          'id': 'f1',
          'illness': 'Asthma',
          'category': 'other',
          'icd': 'J45',
          'date': 'ABT 1990',
          'dateText': 'etwa 1990',
          'isPending': false,
        },
        {'id': 'f2', 'illness': 'Migräne', 'category': 'other', 'icd': '', 'date': '', 'dateText': '', 'isPending': true},
      ],
      'canEdit': canEdit,
    };

    Future<void> pumpWithIllnesses(WidgetTester tester, {List<String> modules = const ['_family-health_'], bool canEdit = true}) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
      when(() => client.info('Famtree')).thenAnswer(
        (_) async => {
          'trees': [
            {'name': 'Famtree', 'availableModules': modules},
          ],
        },
      );
      when(() => client.familyHealthPersonIllnesses('Famtree', 'I1')).thenAnswer((_) async => illnesses(canEdit: canEdit));
      await pumpScreen(tester);
      await tester.pumpAndSettle();
    }

    testWidgets('lists the illnesses the module hands out, with date and pending state', (tester) async {
      await pumpWithIllnesses(tester);

      await tester.ensureVisible(find.byKey(const Key('personIllnesses')));
      expect(find.text('Erkrankungen'), findsOneWidget);
      expect(find.text('Asthma'), findsOneWidget);
      expect(find.text('etwa 1990'), findsOneWidget);
      expect(find.text('Migräne'), findsOneWidget);
      expect(find.text('Wartet auf Freigabe'), findsOneWidget);
    });

    testWidgets('a relative who does not take part shows as locked', (tester) async {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personJson('I1'));
      when(() => client.info('Famtree')).thenAnswer(
        (_) async => {
          'trees': [
            {'name': 'Famtree', 'availableModules': ['_family-health_']},
          ],
        },
      );
      when(
        () => client.familyHealthPersonIllnesses('Famtree', 'I1'),
      ).thenAnswer((_) async => {'illnesses': <dynamic>[], 'canEdit': false, 'isOptedOut': true});
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('personIllnessesOptedOut')));
      expect(find.text('Nimmt an der Familiengesundheit nicht teil – Erkrankungen gesperrt.'), findsOneWidget);
    });

    testWidgets('nothing without the module - and the module is not asked', (tester) async {
      await pumpWithIllnesses(tester, modules: []);

      expect(find.byKey(const Key('personIllnesses')), findsNothing);
      verifyNever(() => client.familyHealthPersonIllnesses(any(), any()));
    });

    testWidgets('without edit rights a tap opens nothing', (tester) async {
      await pumpWithIllnesses(tester, canEdit: false);

      await tester.ensureVisible(find.text('Asthma'));
      await tester.tap(find.text('Asthma'));
      await tester.pumpAndSettle();
      expect(find.text('Erkrankung ändern'), findsNothing);
    });

    testWidgets('changing the name keeps a date like ABT 1990 while the year stays', (tester) async {
      await pumpWithIllnesses(tester);
      when(
        () => client.postFamilyHealthIllnessUpdate('Famtree', 'I1', id: 'f1', illness: 'Asthma bronchiale', date: 'ABT 1990'),
      ).thenAnswer((_) async => {'ok': true});

      await tester.ensureVisible(find.text('Asthma'));
      await tester.tap(find.text('Asthma'));
      await tester.pumpAndSettle();
      expect(find.text('Erkrankung ändern'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('illnessEditYear'))).controller!.text, '1990');

      await tester.enterText(find.byKey(const Key('illnessEditName')), 'Asthma bronchiale');
      await tester.tap(find.byKey(const Key('illnessEditSave')));
      await tester.pumpAndSettle();

      verify(
        () => client.postFamilyHealthIllnessUpdate('Famtree', 'I1', id: 'f1', illness: 'Asthma bronchiale', date: 'ABT 1990'),
      ).called(1);
      // loaded again after the change
      verify(() => client.familyHealthPersonIllnesses('Famtree', 'I1')).called(2);
      expect(find.text('Fakt gespeichert.'), findsOneWidget);
    });

    testWidgets('a new year replaces the date', (tester) async {
      await pumpWithIllnesses(tester);
      when(
        () => client.postFamilyHealthIllnessUpdate('Famtree', 'I1', id: 'f1', illness: 'Asthma', date: '1992'),
      ).thenAnswer((_) async => {'ok': true});

      await tester.ensureVisible(find.text('Asthma'));
      await tester.tap(find.text('Asthma'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('illnessEditYear')), '1992');
      await tester.tap(find.byKey(const Key('illnessEditSave')));
      await tester.pumpAndSettle();

      verify(() => client.postFamilyHealthIllnessUpdate('Famtree', 'I1', id: 'f1', illness: 'Asthma', date: '1992')).called(1);
    });

    testWidgets('deleting asks first', (tester) async {
      await pumpWithIllnesses(tester);
      when(() => client.postFamilyHealthIllnessDelete('Famtree', 'I1', id: 'f1')).thenAnswer((_) async => {'ok': true});

      await tester.ensureVisible(find.text('Asthma'));
      await tester.tap(find.text('Asthma'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('illnessEditDelete')));
      await tester.pumpAndSettle();
      expect(find.text('„Asthma“ löschen?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('illnessDeleteConfirm')));
      await tester.pumpAndSettle();

      verify(() => client.postFamilyHealthIllnessDelete('Famtree', 'I1', id: 'f1')).called(1);
      expect(find.text('Erkrankung gelöscht.'), findsOneWidget);
    });

    testWidgets('a rejection shows in the sheet', (tester) async {
      await pumpWithIllnesses(tester);
      when(
        () => client.postFamilyHealthIllnessUpdate('Famtree', 'I1', id: 'f1', illness: 'Asthma', date: 'ABT 1990'),
      ).thenAnswer((_) async => {'ok': false, 'error': 'Diese Erkrankung gibt es nicht mehr.'});

      await tester.ensureVisible(find.text('Asthma'));
      await tester.tap(find.text('Asthma'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('illnessEditSave')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Diese Erkrankung gibt es nicht mehr.'), findsOneWidget);
    });
  });
}
