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
          TabNavigator(
            navigatorKey: searchNavigatorKey,
            observers: [BottomBarObserver(ProviderScope.containerOf(context, listen: false))],
            child: Builder(
              builder: (context) => Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: () => openPerson(context, 'I1'),
                    child: const Text('open person from search'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: !ref.watch(bottomBarVisibleProvider) ? null : NavigationBar(
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
    when(() => client.usePrettyUrls).thenReturn(false);
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

  testWidgets('openPerson opens the page within the current tab and hides the bottom bar; Back shows it again (#31)', (
    tester,
  ) async {
    await pumpShell(tester, viewSize: const Size(400, 800));

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open person from search'));
    await tester.pumpAndSettle();

    expect(container.read(selectedTabProvider), 2, reason: 'stays on the tab it was opened from');
    expect(find.text('Anna Muster'), findsWidgets);
    expect(find.byType(NavigationBar), findsNothing, reason: 'hidden while somewhere else');

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('open person from search'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget, reason: 'back after Back');
  });
}
