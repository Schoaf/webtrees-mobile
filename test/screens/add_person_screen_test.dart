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

      await tester.tap(find.text('Weitere Angabe hinzufügen'));
      await tester.pump();

      // Property dropdown defaults to the first extra-field key ("Beruf" /
      // occupation -> OCCU) - just fill its paired value field. Field order:
      // 0 given, 1 surname, 2 birth place, 3 relative search, 4 this row's
      // value field.
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
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
