import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/tree_view/tree_view_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

import '../fixtures/tree_lineage.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  Map<String, dynamic> childJson(String xref, String name, int year) => {
    'xref': xref,
    'name': name,
    'sortName': 'Muster,$name',
    'sex': 'F',
    'isDead': false,
    'birth': {
      'date': {'year': year},
    },
  };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client = MockWebtreesClient();
    when(() => client.usePrettyUrls).thenReturn(false);
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester) async {
    // TreeViewScreen's own centering logic fits the family group to the
    // viewport, but the children frame below it can still land past the
    // default 800x600 test surface - a taller surface keeps everything
    // reachable by find/tap without needing to pan the InteractiveViewer
    // (which isn't a Scrollable, so ensureVisible/scrollUntilVisible don't
    // apply to it).
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('de'),
          home: TreeViewScreen(xref: 'I1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows a "+N weitere Kinder" hint for children with another partner not shown here', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Elisabeth Muster', 'sortName': 'Muster,Elisabeth', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': [
          {
            'xref': 'F1',
            'facts': [
              {'tag': 'MARR'},
            ],
            'husband': {'xref': 'I4', 'isDead': false},
            'wife': {'xref': 'I1', 'isDead': false},
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [childJson('I5', 'Mia', 2013), childJson('I6', 'Paul', 2015)],
          },
          {
            'xref': 'F2',
            // ended: a DIV fact but no MARR - an informal partnership that
            // ended without ever having been a formal marriage.
            'facts': [
              {'tag': 'DIV'},
            ],
            'husband': {'xref': 'I9', 'isDead': false},
            'wife': {'xref': 'I1', 'isDead': false},
            'marriage': {
              'date': {'year': 2005},
            },
            'spouse': {'xref': 'I9', 'name': 'Klaus Berger', 'sortName': 'Berger,Klaus', 'sex': 'M', 'isDead': false},
            'children': [childJson('I8', 'Noah', 2006)],
          },
        ],
        'stepFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    // The ongoing marriage (F1, Thomas) is the default partner shown -
    // Klaus's family (ended) isn't, so its one child should surface as a
    // "+1 weitere Kinder" hint rather than silently vanishing.
    expect(find.textContaining('+1'), findsOneWidget);
    expect(find.text('Noah'), findsNothing);
  });

  testWidgets('tapping the extra-children hint switches to the next partner\'s children', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Elisabeth Muster', 'sortName': 'Muster,Elisabeth', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': [
          {
            'xref': 'F1',
            'facts': [
              {'tag': 'MARR'},
            ],
            'husband': {'xref': 'I4', 'isDead': false},
            'wife': {'xref': 'I1', 'isDead': false},
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [childJson('I5', 'Mia', 2013)],
          },
          {
            'xref': 'F2',
            'facts': [
              {'tag': 'DIV'},
            ],
            'husband': {'xref': 'I9', 'isDead': false},
            'wife': {'xref': 'I1', 'isDead': false},
            'marriage': {
              'date': {'year': 2005},
            },
            'spouse': {'xref': 'I9', 'name': 'Klaus Berger', 'sortName': 'Berger,Klaus', 'sex': 'M', 'isDead': false},
            'children': [childJson('I8', 'Noah', 2006)],
          },
        ],
        'stepFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    expect(find.text('Mia'), findsOneWidget);
    expect(find.text('Noah'), findsNothing);

    await tester.tap(find.textContaining('+1'));
    await tester.pumpAndSettle();

    expect(find.text('Noah'), findsOneWidget);
    expect(find.text('Mia'), findsNothing);
    // Now showing Klaus's family instead - Thomas's one child surfaces as
    // the hint.
    expect(find.textContaining('+1'), findsOneWidget);
  });

  testWidgets('hides the extra-children hint when there is only one partner family', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Elisabeth Muster', 'sortName': 'Muster,Elisabeth', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': [
          {
            'xref': 'F1',
            'facts': [
              {'tag': 'MARR'},
            ],
            'husband': {'xref': 'I4', 'isDead': false},
            'wife': {'xref': 'I1', 'isDead': false},
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [childJson('I5', 'Mia', 2013)],
          },
        ],
        'stepFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    expect(find.textContaining('weitere Kinder'), findsNothing);
  });

  testWidgets('shows every child with no "show more" cutoff, however many there are', (tester) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Elisabeth Muster', 'sortName': 'Muster,Elisabeth', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': [
          {
            'xref': 'F1',
            'facts': [
              {'tag': 'MARR'},
            ],
            'husband': {'xref': 'I4', 'isDead': false},
            'wife': {'xref': 'I1', 'isDead': false},
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [
              for (var i = 0; i < 8; i++) childJson('I${100 + i}', 'Kind$i', 2010 + i),
            ],
          },
        ],
        'stepFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    for (var i = 0; i < 8; i++) {
      expect(find.text('Kind$i'), findsOneWidget, reason: 'Kind$i should be shown without needing to expand anything');
    }
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets(
    'recentering re-runs when visibilitySignal changes - the fix for a bottom-nav tab that never centers',
    (tester) async {
      // Regression test: an IndexedStack bottom-nav tab never rebuilds its
      // offstage children just because the selected index changed - the
      // old one-shot "center once per xref, ever" logic (gated only by
      // activeXref) got exactly one chance, often while still offstage,
      // and never ran again once the tab actually became visible.
      // visibilitySignal is what MyTreeViewScreen drives from the
      // selected-tab index to force a re-check.
      when(() => client.individual('Famtree', 'I1')).thenAnswer(
        (_) async => {
          'person': {'xref': 'I1', 'name': 'Elisabeth Muster', 'sortName': 'Muster,Elisabeth', 'sex': 'F', 'isDead': false},
          'canEdit': false,
          'facts': <dynamic>[],
          'parentFamilies': <dynamic>[],
          'spouseFamilies': <dynamic>[],
          'extraChildrenByParent': {'father': 0, 'mother': 0},
          'media': <dynamic>[],
        },
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var signal = 0;
      late StateSetter setSignal;

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('de'),
            home: StatefulBuilder(
              builder: (context, setter) {
                setSignal = setter;
                return TreeViewScreen(xref: 'I1', visibilitySignal: signal);
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final controller = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
      final centeredValue = controller.value.clone();
      expect(centeredValue, isNot(Matrix4.identity()), reason: 'sanity check: it must have actually centered once');

      // Reset the transform, as if the first centering had landed wrong (or
      // the user had panned away) - without a visibilitySignal change,
      // nothing should touch it again.
      controller.value = Matrix4.identity();
      await tester.pumpAndSettle();
      expect(controller.value, Matrix4.identity());

      // Simulate switching into this tab.
      setSignal(() => signal = 1);
      await tester.pumpAndSettle();

      expect(controller.value, centeredValue);
    },
  );

  testWidgets('the top bar matches every other screen\'s width on a wide landscape tablet, not the full screen', (
    tester,
  ) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Elisabeth Muster', 'sortName': 'Muster,Elisabeth', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    // pumpScreen sets its own tall-phone view size for the centering
    // math's own needs - override it back to a wide landscape tablet
    // size afterward instead.
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();

    final topBarWidth = tester.getSize(find.byType(InteractiveViewer).hitTestable().first).width;
    expect(topBarWidth, greaterThan(1300), reason: 'sanity check: the canvas below stays full-width');

    final topBarContainerWidth = tester
        .getSize(find.ancestor(of: find.byIcon(Icons.undo), matching: find.byType(Container)).first)
        .width;
    expect(topBarContainerWidth, 1100, reason: 'must match tabletBoundedMaxWidth, same as every other screen');
  });

  group('generations (#42)', () {
    setUp(() {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => individualJson());
      when(
        () => client.pedigree('Famtree', 'I1', any()),
      ).thenAnswer((invocation) async => pedigreeJson(invocation.positionalArguments[2] as int));
      when(
        () => client.descendants('Famtree', 'I1', any()),
      ).thenAnswer((invocation) async => descendantsJson(invocation.positionalArguments[2] as int));
    });

    Future<void> pick(WidgetTester tester, String label) async {
      await tester.tap(find.byKey(const Key('treeGenerationsButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('treeGenerations-$label')));
      await tester.pumpAndSettle();
    }

    testWidgets('one generation is the plain view, without loading more', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Anton'), findsOneWidget);
      expect(find.text('Mia'), findsOneWidget);
      expect(find.text('Josef'), findsNothing);
      expect(find.text('Lena'), findsNothing);
      verifyNever(() => client.pedigree(any(), any(), any()));
      verifyNever(() => client.descendants(any(), any(), any()));
    });

    testWidgets('two generations add the grandparents and grandchildren', (tester) async {
      await pumpScreen(tester);
      await pick(tester, '2');

      for (final name in ['Josef', 'Anna', 'Karl', 'Rosa', 'Lena']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Johann'), findsNothing, reason: 'a great-grandparent');
      // The parents and children stay where they were, once each.
      expect(find.text('Anton'), findsOneWidget);
      expect(find.text('Mia'), findsOneWidget);
      verify(() => client.pedigree('Famtree', 'I1', 3)).called(1);
      verify(() => client.descendants('Famtree', 'I1', 4)).called(1);
    });

    testWidgets('the picked number is kept for the next time', (tester) async {
      await pumpScreen(tester);
      await pick(tester, '3');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('tree_generations'), 3);
      expect(find.text('Johann'), findsOneWidget);
    });

    TransformationController transform(WidgetTester tester) =>
        tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;

    testWidgets('fewer generations zoom in to fit when zoomed out further than needed', (tester) async {
      await pumpScreen(tester);
      await pick(tester, '3');
      transform(tester).value = Matrix4.identity()..scaleByDouble(0.5, 0.5, 0.5, 1);
      await tester.pumpAndSettle();

      await pick(tester, '1');

      expect(transform(tester).value.getMaxScaleOnAxis(), greaterThan(0.5));
    });

    testWidgets('fewer generations keep the view when zoomed in closer', (tester) async {
      await pumpScreen(tester);
      await pick(tester, '3');
      final zoomedIn = Matrix4.identity()..scaleByDouble(2, 2, 2, 1);
      transform(tester).value = zoomedIn.clone();
      await tester.pumpAndSettle();

      await pick(tester, '2');

      expect(transform(tester).value.getMaxScaleOnAxis(), 2);
    });

    testWidgets('∞ loads further generations while they come into view, until there are no more', (tester) async {
      await pumpScreen(tester);
      await pick(tester, '∞');

      // The tall test view shows everything: it keeps loading to the end.
      expect(find.text('Johann'), findsOneWidget);
      expect(find.text('Lena'), findsOneWidget);
      verify(() => client.pedigree('Famtree', 'I1', 3)).called(1);
      verify(() => client.pedigree('Famtree', 'I1', 4)).called(1);
      verifyNever(() => client.pedigree('Famtree', 'I1', 5));
      verify(() => client.descendants('Famtree', 'I1', 4)).called(1);
      verifyNever(() => client.descendants('Famtree', 'I1', 5));
    });
  });
}
