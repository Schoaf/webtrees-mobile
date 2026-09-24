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
            'maritalStatus': 'married',
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [childJson('I5', 'Mia', 2013), childJson('I6', 'Paul', 2015)],
          },
          {
            'xref': 'F2',
            'maritalStatus': 'ended',
            'marriage': {
              'date': {'year': 2005},
            },
            'spouse': {'xref': 'I9', 'name': 'Klaus Berger', 'sortName': 'Berger,Klaus', 'sex': 'M', 'isDead': false},
            'children': [childJson('I8', 'Noah', 2006)],
          },
        ],
        'siblings': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
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
            'maritalStatus': 'married',
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [childJson('I5', 'Mia', 2013)],
          },
        ],
        'siblings': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
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
            'maritalStatus': 'married',
            'marriage': {
              'date': {'year': 2011},
            },
            'spouse': {'xref': 'I4', 'name': 'Thomas Wagner', 'sortName': 'Wagner,Thomas', 'sex': 'M', 'isDead': false},
            'children': [
              for (var i = 0; i < 8; i++) childJson('I${100 + i}', 'Kind$i', 2010 + i),
            ],
          },
        ],
        'siblings': <dynamic>[],
        'extraChildrenByParent': {'father': 0, 'mother': 0},
        'media': <dynamic>[],
      },
    );

    await pumpScreen(tester);

    for (var i = 0; i < 8; i++) {
      expect(find.text('Kind$i'), findsOneWidget, reason: 'Kind$i should be shown without needing to expand anything');
    }
    expect(find.byType(TextButton), findsNothing);
  });
}
