import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/utils/tab_navigation.dart';
import 'package:webtrees_mobile/widgets/tab_navigator.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

/// A minimal stand-in for _HomeShell (main.dart): the four tabs, each in
/// its own TabNavigator with a BottomBarObserver, the Person tab with the
/// real person page, and a Search-like tab that opens a person or another
/// page - without the real app's login-gated shell.
class _FakeShell extends ConsumerStatefulWidget {
  const _FakeShell();

  @override
  ConsumerState<_FakeShell> createState() => _FakeShellState();
}

class _FakeShellState extends ConsumerState<_FakeShell> {
  late final _observers = [
    for (var i = 0; i < tabNavigatorKeys.length; i++)
      BottomBarObserver(ProviderScope.containerOf(context, listen: false)),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    final screens = <Widget>[
      const Center(child: Text('home tab root')),
      const PersonDetailScreen(xref: 'I1', isShowingOnlyWhenEmpty: true),
      const Center(child: Text('tree tab root')),
      Builder(
        builder: (context) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('search results'),
            TextButton(onPressed: () => openPerson(context, 'I2'), child: const Text('open person from search')),
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => Scaffold(appBar: AppBar(), body: const Text('other page')),
                ),
              ),
              child: const Text('open other page'),
            ),
          ],
        ),
      ),
    ];
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          for (var i = 0; i < screens.length; i++)
            TabNavigator(navigatorKey: tabNavigatorKeys[i], observers: [_observers[i]], child: screens[i]),
        ],
      ),
      bottomNavigationBar: !ref.watch(bottomBarVisibleProvider)
          ? null
          : NavigationBar(
              selectedIndex: index,
              onDestinationSelected: (i) => ref.read(selectedTabProvider.notifier).select(i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.person), label: 'Person'),
                NavigationDestination(icon: Icon(Icons.account_tree), label: 'Stammbaum'),
                NavigationDestination(icon: Icon(Icons.search), label: 'Suche'),
              ],
            ),
    );
  }
}

Map<String, dynamic> _person(String xref, String name) => {
  'person': {'xref': xref, 'name': name, 'sortName': name, 'sex': 'F', 'isDead': false},
  'canEdit': false,
  'facts': <dynamic>[],
  'parentFamilies': <dynamic>[],
  'spouseFamilies': <dynamic>[],
  'media': <dynamic>[],
};

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.usePrettyUrls).thenReturn(false);
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => _person('I1', 'Anna Muster'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => _person('I2', 'Berta Muster'));
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpShell(WidgetTester tester, {required Size viewSize}) async {
    tester.view.physicalSize = viewSize;
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
          home: _FakeShell(),
        ),
      ),
    );
  }

  testWidgets('openPerson shows the person on the Person tab; the search tab keeps its results (#31)', (tester) async {
    await pumpShell(tester, viewSize: const Size(400, 800));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open person from search'));
    await tester.pumpAndSettle();

    expect(container.read(selectedTabProvider), kPersonTabIndex);
    expect(find.text('Berta Muster'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'a tab page, nothing pushed');
    expect(find.byIcon(Icons.arrow_back), findsNothing, reason: 'nothing to go back to on a tab page');

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('search results'), findsOneWidget);
    expect(find.byType(PersonDetailScreen, skipOffstage: false), findsOneWidget, reason: 'only the Person tab has one');
  });

  testWidgets('a pushed page hides the bottom bar; Back shows it again (#31)', (tester) async {
    await pumpShell(tester, viewSize: const Size(400, 800));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open other page'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('search results'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the Person tab keeps no Back button after a page on top was closed (white screen)', (tester) async {
    await pumpShell(tester, viewSize: const Size(400, 800));
    // An iPhone's home indicator: hiding the bar changes the person page's
    // bottom padding, so it rebuilds while the other page is on top.
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.resetPadding);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_back), findsNothing);

    // Like "Person hinzufügen" from the ⋮ menu: the bar hides, the person page rebuilds below.
    personNavigatorKey.currentState!.push(
      MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(), body: const Text('other page')),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byIcon(Icons.arrow_back, skipOffstage: false),
      findsOneWidget,
      reason: 'only the page on top - a Back on the person page below outlived it and removed the tab\'s only page',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Anna Muster'), findsWidgets);
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('closing a menu or dialog on a page keeps the bottom bar hidden', (tester) async {
    await pumpShell(tester, viewSize: const Size(400, 800));
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open other page'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing);

    showDialog<void>(
      context: tester.element(find.text('other page')),
      // Like a popup menu: on the tab's own navigator.
      useRootNavigator: false,
      builder: (context) => const AlertDialog(content: Text('menu')),
    );
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('menu'))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsNothing, reason: 'still on the page');
  });

  testWidgets('Back to a page that is still open keeps the bar hidden; only the tab page brings it back', (
    tester,
  ) async {
    await pumpShell(tester, viewSize: const Size(400, 800));
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open other page'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('other page'))).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(appBar: AppBar(), body: const Text('editor')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('other page'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing, reason: 'the page below is still open');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
