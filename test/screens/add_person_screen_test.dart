import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/add_person/add_person_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    // PlaceAutocompleteField debounces onChanged and calls this - stub it
    // for every test that types into a place field, even ones not
    // specifically asserting on suggestions, so the fire-and-forget Timer
    // doesn't throw a MissingStubError into pumpAndSettle.
    when(() => client.placeAutocomplete(any(), any())).thenAnswer((_) async => <String>[]);
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? linkedXref,
    String? linkedName,
  }) async {
    // This screen's whole form (name, sex, birth date/place, relative
    // search, and any "extra detail" rows) is meant to be scrolled through
    // on a phone - but a ListView only builds/hit-tests items near its
    // current viewport, and repeated programmatic scrolling to reach each
    // field in turn fights with real scroll-physics settling (overscroll
    // bounce-back can silently scroll a just-revealed field back offscreen
    // between one interaction and the next). Since this test cares about
    // field presence/fillability, not scroll behavior, give the surface
    // enough height that every field is simultaneously on-screen and
    // reachable without scrolling at all.
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: AddPersonScreen(linkedXref: linkedXref, linkedName: linkedName),
        ),
      ),
    );
  }

  // Every field on this screen is form-covered here by filling it in, saving,
  // and asserting the exact value the field held reaches postAddIndividual -
  // a black-box way to prove a field is both present AND actually wired to
  // its controller/state, not just visually there. This is the same class of
  // regression as the person-detail edit-mode overflow bug: a field can be
  // "in the tree" per debugDumpApp() yet unreachable/unfillable at runtime.
  testWidgets(
    'given name, surname, sex, birth date, and birth place all reach postAddIndividual with the entered/selected values',
    (tester) async {
      when(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'none',
          relativeTo: null,
          given: 'Max',
          surname: 'Scharf',
          sex: 'F',
          birthDate: any(named: 'birthDate'),
          birthPlace: 'Wien',
        ),
      ).thenAnswer((_) async => {'ok': true, 'xref': 'I99'});

      await pumpScreen(tester);

      // Field order in the tree: 0 given, 1 surname, 2 birth place.
      await tester.enterText(find.byType(TextField).at(0), 'Max');
      await tester.enterText(find.byType(TextField).at(1), 'Scharf');

      // Sex picker: defaults to 'M' (männlich) - switch to 'weiblich' (F).
      expect(find.text('männlich'), findsOneWidget);
      expect(find.text('weiblich'), findsOneWidget);
      await tester.tap(find.text('weiblich'));
      await tester.pump();

      // Birth date: always picker-driven (never free text), same convention
      // as GedcomDateField - open the native date picker and confirm the
      // default date, then assert the placeholder is gone (a real value
      // took).
      expect(find.text('TT.MM.JJJJ'), findsOneWidget);
      await tester.tap(find.text('TT.MM.JJJJ'));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('Übernehmen'));
      await tester.pumpAndSettle();
      expect(find.text('TT.MM.JJJJ'), findsNothing);

      await tester.enterText(find.byType(TextField).at(2), 'Wien');

      await tester.tap(find.text('Speichern'));
      // Not pumpAndSettle(): AddPersonScreen is pumped without a Navigator
      // stack or tab host here, so its "return to start" after a successful
      // save can't actually remove it from the tree - the save button's
      // CircularProgressIndicator would otherwise keep animating forever
      // and pumpAndSettle would time out. A few bounded pumps are enough to
      // let the awaited postAddIndividual call resolve.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      verify(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'none',
          relativeTo: null,
          given: 'Max',
          surname: 'Scharf',
          sex: 'F',
          birthDate: any(named: 'birthDate'),
          birthPlace: 'Wien',
        ),
      ).called(1);
    },
  );

  testWidgets(
    'on a phone, "Weitere Angabe hinzufügen" starts empty - tapping it adds rows one at a time, same as before',
    (tester) async {
      when(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'none',
          relativeTo: null,
          given: 'Max',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).thenAnswer((_) async => {'ok': true, 'xref': 'I99'});

      await pumpScreen(tester);

      // Nothing pre-filled - only the two-column tablet layout has room to
      // show every possible row up front (see the tablet test below).
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);

      await tester.tap(find.text('Weitere Angabe hinzufügen'));
      await tester.pump();
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(1));
      expect(find.text('Beruf'), findsWidgets);

      await tester.enterText(find.byType(TextField).at(0), 'Max');
      await tester.tap(find.text('Speichern'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      // The one row added was left blank - it shouldn't have posted anything.
      verifyNever(() => client.postFact(any(), any(), tag: any(named: 'tag'), value: any(named: 'value')));
    },
  );

  testWidgets(
    'an "extra detail" row (property dropdown + value field) posts as its own fact after the person is created',
    (tester) async {
      when(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'none',
          relativeTo: null,
          given: 'Max',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).thenAnswer((_) async => {'ok': true, 'xref': 'I99'});
      when(
        () => client.postFact('Famtree', 'I99', tag: 'OCCU', value: 'Bäcker'),
      ).thenAnswer((_) async => {'ok': true});

      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Max');

      // On a phone, a row only exists once "+" is tapped - it defaults to
      // "Beruf" (occupation -> OCCU), the first option. Field order: 0
      // given, 1 surname, 2 birth place, 3 relative search, 4 this (newly
      // added) row's value field.
      await tester.tap(find.text('Weitere Angabe hinzufügen'));
      await tester.pump();
      expect(find.text('Beruf'), findsWidgets);
      await tester.enterText(find.byType(TextField).at(4), 'Bäcker');

      await tester.tap(find.text('Speichern'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      verify(() => client.postFact('Famtree', 'I99', tag: 'OCCU', value: 'Bäcker')).called(1);
    },
  );

  testWidgets(
    'the "linked with" relative search field finds and selects a relative, wiring their xref + relation into the save',
    (tester) async {
      when(() => client.individuals('Famtree', query: 'Anna')).thenAnswer(
        (_) async => {
          'data': [
            {'xref': 'I5', 'name': 'Anna Muster', 'lifespan': '* 1950'},
          ],
        },
      );
      when(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'child',
          relativeTo: 'I5',
          given: 'Max',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).thenAnswer((_) async => {'ok': true, 'xref': 'I99'});

      await pumpScreen(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Max');

      // Field order: 0 given, 1 surname, 2 birth place, 3 relative search.
      await tester.enterText(find.byType(TextField).at(3), 'Anna');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.text('Anna Muster'), findsOneWidget);
      await tester.tap(find.text('Anna Muster'));
      await tester.pump();

      // Selecting a relative defaults the relation chip to "als Kind" (child).
      expect(find.text('als Kind'), findsOneWidget);

      await tester.tap(find.text('Speichern'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      verify(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'child',
          relativeTo: 'I5',
          given: 'Max',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).called(1);
    },
  );

  testWidgets(
    'on a wide landscape tablet, "Weitere Angabe hinzufügen" sits in its own right-hand column - and still works',
    (tester) async {
      // Regression coverage for the generic contract: whatever's in the
      // "Weitere Angabe hinzufügen" section (today: the extra-fact rows and
      // its own add button) must land in the right column, not just visual
      // inspection - a real extra field still has to reach
      // postAddIndividual correctly once added there.
      when(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'none',
          relativeTo: null,
          given: 'Max',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).thenAnswer((_) async => {'ok': true, 'xref': 'I99'});
      when(
        () => client.postFact('Famtree', 'I99', tag: 'OCCU', value: 'Tischler'),
      ).thenAnswer((_) async => {'ok': true});

      await pumpScreen(tester);

      // pumpScreen sets its own (800, 2600) view size for the other tests'
      // "everything reachable without scrolling" needs - override it back
      // to a wide landscape tablet size afterward instead.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpAndSettle();

      final buttonWidth = tester.getRect(find.widgetWithText(TextButton, 'Weitere Angabe hinzufügen')).width;
      // The top title bar sits outside the (possibly two-column) ListView
      // entirely, so its own Container always reports the screen's full
      // content width regardless of layout - a reliable reference the
      // button's own width (which, like every ListView/Column child,
      // always reports the full width of whatever tightly constrains it)
      // can be compared against.
      final fullContentWidth = tester
          .getRect(find.ancestor(of: find.text('Person hinzufügen'), matching: find.byType(Container)).first)
          .width;
      expect(
        buttonWidth,
        lessThan(fullContentWidth * 0.6),
        reason: '"Weitere Angabe hinzufügen" must be in its own (narrower) right-hand column',
      );

      await tester.enterText(find.byType(TextField).at(0), 'Max');

      // Every possible "Weitere Angabe" row is already there, empty, from
      // the start (no "+" tap needed) - "Beruf" (occupation -> OCCU) is
      // the first of the 5. Same field order as the single-column layout
      // (Row visits its children depth-first, left column before right, so
      // this ends up the same index either way): 0 given, 1 surname,
      // 2 birth place, 3 relative search, 4 this (first extra) row's value
      // field.
      expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(5));
      await tester.enterText(find.byType(TextField).at(4), 'Tischler');

      await tester.tap(find.text('Speichern'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      verify(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'none',
          relativeTo: null,
          given: 'Max',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).called(1);
      verify(() => client.postFact('Famtree', 'I99', tag: 'OCCU', value: 'Tischler')).called(1);
    },
  );

  testWidgets('the Speichern button stays at its portrait width on a wide landscape tablet, not full-width', (
    tester,
  ) async {
    await pumpScreen(tester);

    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    final saveButtonWidth = tester.getSize(find.widgetWithText(FilledButton, 'Speichern')).width;
    expect(saveButtonWidth, 480);
  });

  group('pre-linked via linkedXref/linkedName (reached from a person\'s own "Person hinzufügen")', () {
    testWidgets('pre-fills "Verknüpft mit" read-only and blocks Save until a relation is chosen', (tester) async {
      await pumpScreen(tester, linkedXref: 'I7', linkedName: 'Anna Muster');

      expect(find.text('Anna Muster'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Anna Muster'), findsOneWidget);
      final field = tester.widget<TextField>(find.widgetWithText(TextField, 'Anna Muster'));
      expect(field.readOnly, isTrue);

      // Relation chips show (a relative is already "selected"), but none
      // pre-chosen - unlike the free-form search flow, which defaults to
      // "child" the instant a relative is picked.
      expect(find.text('als Kind'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(0), 'Lena');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);

      await tester.tap(find.text('als Kind'));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNotNull);
    });

    testWidgets('save sends the pre-linked xref and the chosen relation', (tester) async {
      when(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'father',
          relativeTo: 'I7',
          given: 'Franz',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).thenAnswer((_) async => {'ok': true, 'xref': 'I99'});

      await pumpScreen(tester, linkedXref: 'I7', linkedName: 'Anna Muster');

      await tester.enterText(find.byType(TextField).at(0), 'Franz');
      await tester.tap(find.text('als Vater'));
      await tester.pump();

      await tester.tap(find.text('Speichern'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      verify(
        () => client.postAddIndividual(
          'Famtree',
          relation: 'father',
          relativeTo: 'I7',
          given: 'Franz',
          surname: '',
          sex: 'M',
          birthDate: null,
          birthPlace: null,
        ),
      ).called(1);
    });
  });
}
