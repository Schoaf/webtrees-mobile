import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/tree_picker/tree_picker_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // TreeNameNotifier.set() persists via flutter_secure_storage - fake the
  // channel so that write actually runs instead of hitting the "storage
  // unavailable" catch branch (same setup as app_providers_test.dart).
  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final secureStore = <String, String>{};

  Future<Object?> handleSecureStorageCall(MethodCall call) async {
    final args = call.arguments as Map;
    switch (call.method) {
      case 'write':
        secureStore[args['key'] as String] = args['value'] as String;
        return null;
      case 'read':
        return secureStore[args['key'] as String];
    }
    return null;
  }

  setUp(() {
    secureStore.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      handleSecureStorageCall,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      null,
    );
  });

  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
    container = ProviderContainer(overrides: [webtreesClientProvider.overrideWithValue(client)]);
    addTearDown(container.dispose);
  });

  Future<void> pumpScreen(WidgetTester tester, {List<Map<String, dynamic>>? trees}) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: TreePickerScreen(trees: trees),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final twoTrees = [
    {'name': 'Famtree', 'title': 'Familie Scharf', 'individuals': 187},
    {'name': 'OtherTree', 'title': 'Familie Muster', 'individuals': 42},
  ];

  testWidgets('with a pre-fetched trees list, shows each tree without calling info()', (tester) async {
    await pumpScreen(tester, trees: twoTrees);

    expect(find.text('Familie Scharf'), findsOneWidget);
    expect(find.text('187 Personen im Stammbaum'), findsOneWidget);
    expect(find.text('Familie Muster'), findsOneWidget);
    expect(find.text('42 Personen im Stammbaum'), findsOneWidget);
    verifyNever(() => client.info(any()));
  });

  testWidgets('marks the currently active tree with a checkmark', (tester) async {
    await pumpScreen(tester, trees: twoTrees); // default active tree is productionTreeName ("Famtree")

    final famtreeTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Familie Scharf'), matching: find.byType(ListTile)),
    );
    final otherTile = tester.widget<ListTile>(
      find.ancestor(of: find.text('Familie Muster'), matching: find.byType(ListTile)),
    );
    expect(famtreeTile.trailing, isNotNull);
    expect(otherTile.trailing, isNull);
  });

  testWidgets('tapping a tree persists the choice and pops the screen', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Navigator(
            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => TreePickerScreen(trees: twoTrees)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Familie Muster'));
    await tester.pumpAndSettle();

    expect(container.read(treeNameProvider), 'OtherTree');
    expect(secureStore['active_tree_name'], 'OtherTree');
    // The screen popped - its own AppBar title is no longer there.
    expect(find.text('Stammbaum wählen'), findsNothing);
  });

  testWidgets('without a pre-fetched list, fetches trees via info() on the current tree', (tester) async {
    when(() => client.info('Famtree')).thenAnswer(
      (_) async => {
        'trees': [
          {'name': 'Famtree', 'title': 'Familie Scharf', 'individuals': 187},
        ],
      },
    );

    await pumpScreen(tester);

    expect(find.text('Familie Scharf'), findsOneWidget);
    verify(() => client.info('Famtree')).called(1);
  });

  testWidgets('a load failure shows a copyable error, not a blank screen', (tester) async {
    when(() => client.info('Famtree')).thenThrow(Exception('server unreachable'));

    await pumpScreen(tester);

    expect(find.textContaining('server unreachable'), findsOneWidget);
  });
}
