import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/auth/server_screen.dart';
import 'package:webtrees_mobile/screens/tree_picker/tree_picker_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

void main() {
  const secureStorageChannel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      (call) async => null,
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      secureStorageChannel,
      null,
    );
  });

  final probedUrls = <String>[];

  Future<ProviderContainer> pumpScreen(
    WidgetTester tester,
    Future<Map<String, dynamic>> Function(String) probe, {
    bool isWebtrees = false,
  }) async {
    probedUrls.clear();
    final container = ProviderContainer(
      overrides: [
        serverProbeProvider.overrideWithValue((url) {
          probedUrls.add(url);
          return probe(url);
        }),
        webtreesPingProvider.overrideWithValue((_) async => isWebtrees),
      ],
    );
    addTearDown(container.dispose);

    // Pushed on top of a placeholder, like from the login screen, so a
    // successful pop is observable.
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServerScreen()),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> enterAndSubmit(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.ensureVisible(find.text('Weiter'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
  }

  testWidgets('switches to a server with one tree and goes back', (tester) async {
    final container = await pumpScreen(
      tester,
      (_) async => {
        'api': minApiLevel,
        'trees': [
          {'name': 'Ahnen', 'title': 'Unsere Ahnen', 'individuals': 12},
        ],
      },
    );

    await enterAndSubmit(tester, 'ahnen.example.org/webtrees/');

    expect(probedUrls, ['https://ahnen.example.org/webtrees']);
    expect(container.read(serverUrlProvider), 'https://ahnen.example.org/webtrees');
    expect(container.read(treeNameProvider), 'Ahnen');
    expect(find.byType(ServerScreen), findsNothing);
  });

  testWidgets('with several trees, continues to the tree picker', (tester) async {
    final container = await pumpScreen(
      tester,
      (_) async => {
        'api': minApiLevel,
        'trees': [
          {'name': 'A', 'title': 'Baum A', 'individuals': 1},
          {'name': 'B', 'title': 'Baum B', 'individuals': 2},
        ],
      },
    );

    await enterAndSubmit(tester, 'example.org');

    expect(find.byType(TreePickerScreen), findsOneWidget);
    expect(container.read(treeNameProvider), 'A');
    await tester.tap(find.text('Baum B'));
    await tester.pumpAndSettle();
    expect(container.read(treeNameProvider), 'B');
  });

  testWidgets('rejects an invalid address without probing', (tester) async {
    await pumpScreen(tester, (_) async => {});

    await enterAndSubmit(tester, 'ftp://example.org');

    expect(probedUrls, isEmpty);
    expect(find.text('Bitte eine gültige Adresse eingeben.'), findsOneWidget);
  });

  testWidgets('a website that isn\'t webtrees stays on the screen with an error', (tester) async {
    final container = await pumpScreen(tester, (_) async => throw TypeError());

    await enterAndSubmit(tester, 'example.org');

    expect(find.byType(ServerScreen), findsOneWidget);
    expect(find.textContaining('keine webtrees-Seite gefunden', findRichText: true), findsOneWidget);
    expect(container.read(serverUrlProvider), productionServerUrl);
  });

  testWidgets('webtrees without api4webtrees says the module is missing', (tester) async {
    await pumpScreen(
      tester,
      (_) async => throw DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 404),
      ),
      isWebtrees: true,
    );

    await enterAndSubmit(tester, 'example.org');

    expect(find.textContaining('api4webtrees nicht installiert', findRichText: true), findsOneWidget);
  });

  testWidgets('an unreachable server shows the connection error', (tester) async {
    await pumpScreen(
      tester,
      (_) async => throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.connectionError,
      ),
    );

    await enterAndSubmit(tester, 'example.org');

    expect(find.textContaining('Server nicht erreichbar'), findsOneWidget);
  });

  testWidgets('an api4webtrees older than the app supports is refused with a hint', (tester) async {
    final container = await pumpScreen(
      tester,
      (_) async => {
        'api': minApiLevel - 1,
        'trees': [
          {'name': 'Ahnen'},
        ],
      },
    );

    await enterAndSubmit(tester, 'example.org');

    expect(find.textContaining('zu alt', findRichText: true), findsOneWidget);
    expect(container.read(serverUrlProvider), productionServerUrl);
  });

  testWidgets('a server without trees for the app is rejected', (tester) async {
    final container = await pumpScreen(tester, (_) async => {'api': minApiLevel, 'trees': <dynamic>[]});

    await enterAndSubmit(tester, 'example.org');

    expect(find.text('Dieser Server stellt keinen Stammbaum für die App bereit.'), findsOneWidget);
    expect(container.read(serverUrlProvider), productionServerUrl);
  });

  testWidgets('as the first screen: shows the welcome text, then gives way to login', (tester) async {
    final container = ProviderContainer(
      overrides: [
        serverUrlProvider.overrideWith(() => ServerUrlNotifier(initial: '')),
        webtreesPingProvider.overrideWithValue((_) async => false),
        serverProbeProvider.overrideWithValue(
          (_) async => {
            'api': minApiLevel,
            'trees': [
              {'name': 'Ahnen', 'title': 'Unsere Ahnen', 'individuals': 12},
            ],
          },
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Consumer(
            builder: (context, ref, _) =>
                ref.watch(serverUrlProvider).isEmpty ? const ServerScreen() : const Text('login'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Willkommen'), findsOneWidget);
    expect(find.text('So verbindest du die App'), findsOneWidget);

    await enterAndSubmit(tester, 'ahnen.example.org');

    expect(find.text('login'), findsOneWidget);
    expect(container.read(treeNameProvider), 'Ahnen');
  });
}
