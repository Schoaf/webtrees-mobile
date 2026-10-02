import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/tree_view/tree_view_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

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
    client = MockWebtreesClient();
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
          'siblings': <dynamic>[],
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
        'siblings': <dynamic>[],
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
        .getSize(find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(Container)).first)
        .width;
    expect(topBarContainerWidth, 1100, reason: 'must match tabletBoundedMaxWidth, same as every other screen');
  });
}
