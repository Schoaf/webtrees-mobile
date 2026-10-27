import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/tree_view/tree_view_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/utils/tab_navigation.dart';
import 'package:webtrees_mobile/widgets/tree_node_card.dart';

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

  testWidgets('centering waits until the tab shows, and switching back keeps the view as it was left', (
    tester,
  ) async {
    // The Stammbaum tab stays alive offstage in the bottom bar's
    // IndexedStack: measured there, the centering landed wrong.
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

    var isVisible = false;
    late StateSetter setVisible;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: StatefulBuilder(
            builder: (context, setter) {
              setVisible = setter;
              return TreeViewScreen(xref: 'I1', isVisible: isVisible);
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final controller = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).transformationController!;
    expect(controller.value, Matrix4.identity(), reason: 'not centered while offstage');

    setVisible(() => isVisible = true);
    await tester.pumpAndSettle();
    expect(controller.value, isNot(Matrix4.identity()), reason: 'centered once the tab shows');

    // Zoomed and panned by the user, then to another tab and back.
    final panned = Matrix4.identity()
      ..translateByDouble(-120, -80, 0, 1)
      ..scaleByDouble(1.7, 1.7, 1.7, 1);
    controller.value = panned.clone();
    await tester.pumpAndSettle();
    setVisible(() => isVisible = false);
    await tester.pumpAndSettle();
    setVisible(() => isVisible = true);
    await tester.pumpAndSettle();

    expect(controller.value, panned);
  });

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

  testWidgets('the partner card shows a married name with the birth name below it, bold only if not shared', (
    tester,
  ) async {
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': [
          {
            'xref': 'F1',
            'facts': [
              {'tag': 'MARR'},
            ],
            'husband': {'xref': 'I1', 'isDead': false},
            'wife': {'xref': 'I2', 'isDead': false},
            'spouse': {'xref': 'I2', 'name': 'Anna Muster', 'sortName': 'Muster,Anna', 'sex': 'F', 'isDead': false},
            'children': <dynamic>[],
          },
        ],
        'stepFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );
    when(() => client.individual('Famtree', 'I2')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I2', 'name': 'Anna Muster', 'sortName': 'Muster,Anna', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': [
          {'tag': 'NAME', 'value': 'Anna /Muster/', 'type': ''},
          {'tag': 'NAME', 'value': 'Anna /Wagner/', 'type': 'married'},
        ],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': <dynamic>[],
        'stepFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    // Anna took Thomas's name: the same surname, so not bold.
    final married = tester.widget<Text>(find.text('Wagner').last);
    expect(married.style?.fontWeight, FontWeight.w400);
    expect(find.text('(Muster)'), findsOneWidget);
  });

  group('full screen', () {
    setUp(() {
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => individualJson());
    });

    double overlayOpacity(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(const Key('treeViewButton')), matching: find.byType(AnimatedOpacity)),
        )
        .opacity;

    testWidgets('hides the bars, fades the overlays while idle and leaves again', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('treeFullScreenButton')));
      await tester.pumpAndSettle();
      expect(container.read(treeFullScreenProvider), isTrue);
      expect(find.byKey(const Key('treeFullScreenButton')), findsNothing);
      expect(overlayOpacity(tester), 1);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(overlayOpacity(tester), 0);

      // A touch on the tree brings them back.
      await tester.tapAt(const Offset(400, 900));
      await tester.pump();
      expect(overlayOpacity(tester), 1);

      await tester.tap(find.byKey(const Key('treeExitFullScreenButton')));
      await tester.pumpAndSettle();
      expect(container.read(treeFullScreenProvider), isFalse);
      expect(find.byKey(const Key('treeFullScreenButton')), findsOneWidget);
    });

    testWidgets('turning the phone keeps what was in the middle in the middle', (tester) async {
      await pumpScreen(tester);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      Offset offCentre() =>
          tester.getCenter(find.text('Elisabeth')) - tester.getCenter(find.byType(InteractiveViewer));
      final before = offCentre();

      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect((offCentre() - before).distance, lessThan(1));

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect((offCentre() - before).distance, lessThan(1));
    });

    testWidgets('a phone turned to landscape goes full screen, back to portrait leaves it', (tester) async {
      await pumpScreen(tester);
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      expect(container.read(treeFullScreenProvider), isTrue);

      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(container.read(treeFullScreenProvider), isFalse);
    });
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
      await tester.tap(find.byKey(const Key('treeViewButton')));
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

    testWidgets('surnames show on every card once switched on in the view menu, and stay on', (tester) async {
      await pumpScreen(tester);
      // By default only the active person and the partner show a surname.
      expect(find.text('Muster'), findsNWidgets(2));

      await tester.tap(find.byKey(const Key('treeViewButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('treeSurnamesItem')));
      await tester.pumpAndSettle();

      // Parents and children too.
      expect(find.text('Muster'), findsNWidgets(6));
      expect((await SharedPreferences.getInstance()).getBool('tree_show_surnames'), isTrue);
    });

    testWidgets('a double tap on the selected person opens them, like the info button - a single one not', (
      tester,
    ) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Elisabeth'));
      await tester.pumpAndSettle();
      expect(container.read(selectedTabProvider), isNot(kPersonTabIndex));

      await tester.tap(find.text('Elisabeth'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Elisabeth'));
      await tester.pumpAndSettle();

      expect(container.read(selectedTabProvider), kPersonTabIndex);
    });

    testWidgets('selecting another person keeps the zoom and only moves the view', (tester) async {
      when(() => client.individual('Famtree', 'I2')).thenAnswer(
        (_) async => {
          'person': personJson('I2', 'Anton', 'M', year: 1955),
          'facts': <dynamic>[],
          'parentFamilies': <dynamic>[],
          'spouseFamilies': <dynamic>[],
          'stepFamilies': <dynamic>[],
          'media': <dynamic>[],
        },
      );
      await pumpScreen(tester);
      transform(tester).value = Matrix4.identity()..scaleByDouble(0.7, 0.7, 0.7, 1);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Anton'));
      await tester.pumpAndSettle();

      expect(transform(tester).value.getMaxScaleOnAxis(), closeTo(0.7, 0.0001));
    });

    testWidgets('colours by surname show a legend, kept across app starts', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const Key('surnameLegend')), findsNothing);

      await tester.tap(find.byKey(const Key('treeViewButton')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('treeSurnameColorsItem')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('surnameLegend')), findsOneWidget);
      await tester.tap(find.byKey(const Key('surnameLegend')));
      await tester.pumpAndSettle();
      // Everyone in the fixture is a Muster: the person, parents, partner, children.
      expect(find.text('Muster 6'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getBool('tree_surname_colors'), isTrue);
    });

    testWidgets('similar spellings share a colour when set in the profile', (tester) async {
      SharedPreferences.setMockInitialValues({'tree_surname_colors': true, 'tree_surname_grouping': 'spelling'});
      final json = individualJson();
      final spouseFamily = (json['spouseFamilies'] as List).first as Map<String, dynamic>;
      spouseFamily['spouse'] = {
        ...spouseFamily['spouse'] as Map<String, dynamic>,
        'name': 'Thomas Musster',
        'sortName': 'Musster,Thomas',
      };
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);
      await pumpScreen(tester);

      await tester.tap(find.byKey(const Key('surnameLegend')));
      await tester.pumpAndSettle();
      expect(find.text('Muster 6'), findsOneWidget);
    });

    testWidgets('picking surnames in the legend fades everyone else', (tester) async {
      SharedPreferences.setMockInitialValues({'tree_surname_colors': true});
      final json = individualJson();
      final spouseFamily = (json['spouseFamilies'] as List).first as Map<String, dynamic>;
      spouseFamily['spouse'] = {
        ...spouseFamily['spouse'] as Map<String, dynamic>,
        'name': 'Thomas Wagner',
        'sortName': 'Wagner,Thomas',
      };
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => json);
      await pumpScreen(tester);
      bool isFaded(String firstName) =>
          tester.widget<TreeNodeCard>(find.widgetWithText(TreeNodeCard, firstName)).isFaded;

      await tester.tap(find.byKey(const Key('surnameLegend')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('surnameLegend_Muster')));
      await tester.pumpAndSettle();
      expect(isFaded('Thomas'), isTrue);
      expect(isFaded('Elisabeth'), isFalse);

      await tester.tap(find.byKey(const Key('surnameLegend_Muster')));
      await tester.pumpAndSettle();
      expect(isFaded('Thomas'), isFalse);
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
