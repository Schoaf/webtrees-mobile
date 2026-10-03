import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/state/app_providers.dart';
import 'package:webtrees_mobile/utils/tab_navigation.dart';
import 'package:webtrees_mobile/widgets/tab_navigator.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

/// A minimal stand-in for _HomeShell (main.dart) - just enough structure
/// (an IndexedStack of a Home tab and a Stammbaum tab, each wrapped in a
/// TabNavigator over the *shared* homeNavigatorKey/treeNavigatorKey, plus
/// an unwrapped "Search"-like tab with a button that calls openPerson/
/// openTreeView) to prove those two functions actually reach the right
/// navigator and select the right tab, without needing the real app's
/// login/auth-gated shell.
class _FakeShell extends ConsumerWidget {
  const _FakeShell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    return Scaffold(
      body: IndexedStack(
        index: index,
        children: [
          TabNavigator(navigatorKey: homeNavigatorKey, child: const Center(child: Text('home tab root'))),
          TabNavigator(navigatorKey: treeNavigatorKey, child: const Center(child: Text('tree tab root'))),
          Builder(
            builder: (context) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => openPerson(context, 'I1'),
                  child: const Text('open person from search'),
                ),
                TextButton(
                  onPressed: () => openTreeView(context, 'I1'),
                  child: const Text('open tree from search'),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => ref.read(selectedTabProvider.notifier).select(i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.account_tree), label: 'Stammbaum'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Suche'),
        ],
      ),
    );
  }
}

void main() {
  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => client.individual('Famtree', 'I1')).thenAnswer(
      (_) async => {
        'person': {'xref': 'I1', 'name': 'Anna Muster', 'sortName': 'Muster,Anna', 'sex': 'F', 'isDead': false},
        'canEdit': false,
        'facts': <dynamic>[],
        'parentFamilies': <dynamic>[],
        'spouseFamilies': <dynamic>[],
        'media': <dynamic>[],
      },
    );
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

  testWidgets('on a wide landscape tablet, openPerson from another tab pushes onto Home\'s navigator and selects Home', (
    tester,
  ) async {
    await pumpShell(tester, viewSize: const Size(1400, 900));

    // Start on the "Search" tab (index 2).
    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    expect(find.text('open person from search'), findsOneWidget);

    await tester.tap(find.text('open person from search'));
    await tester.pumpAndSettle();

    expect(container.read(selectedTabProvider), 0, reason: 'Home must already be the selected tab, without an extra tap');

    // The push landed on Home's own navigator - switching straight back
    // to the Home destination shows it, not Home's root content.
    await tester.tap(find.byIcon(Icons.home));
    await tester.pumpAndSettle();
    expect(find.text('home tab root'), findsNothing);
    expect(find.text('Anna Muster'), findsWidgets);
  });

  testWidgets('on a wide landscape tablet, openTreeView from another tab pushes onto Stammbaum\'s navigator and selects it', (
    tester,
  ) async {
    await pumpShell(tester, viewSize: const Size(1400, 900));

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open tree from search'));
    await tester.pumpAndSettle();

    expect(container.read(selectedTabProvider), 1, reason: 'Stammbaum must already be the selected tab');

    await tester.tap(find.byIcon(Icons.account_tree));
    await tester.pumpAndSettle();
    expect(find.text('tree tab root'), findsNothing, reason: 'the push must be showing, not Stammbaum\'s root content');
  });

  testWidgets('on a phone-sized viewport, openPerson is a plain push on the ambient Navigator, no tab switch', (
    tester,
  ) async {
    await pumpShell(tester, viewSize: const Size(400, 800));

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open person from search'));
    await tester.pumpAndSettle();

    expect(
      container.read(selectedTabProvider),
      2,
      reason: 'still on Search - a phone has no per-tab navigators to redirect through',
    );
    expect(find.text('Anna Muster'), findsWidgets, reason: 'the push still happened, just on the ambient Navigator');
  });
}
