import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/auth/login_screen.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Stammbaum',
    packageName: 'at.familiescharf.stammbaum',
    version: '1.2.3',
    buildNumber: '9',
    buildSignature: '',
  );

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

  late MockWebtreesClient client;
  late ProviderContainer container;

  setUp(() {
    client = MockWebtreesClient();
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
          locale: const Locale('de'),
          home: LoginScreen(),
        ),
      ),
    );
  }

  testWidgets('shows the tree title once info() resolves', (tester) async {
    when(() => client.info('Famtree')).thenAnswer(
      (_) async => {
        'trees': [
          {'name': 'Famtree', 'title': 'Familie Muster'},
        ],
      },
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Familie Muster'), findsOneWidget);
  });

  testWidgets('silently ignores a failed info() - no title, no crash', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) => Future.error(Exception('offline')));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Anmelden'), findsWidgets);
  });

  testWidgets('shows the app version once PackageInfo resolves', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => {'trees': <dynamic>[]});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('App-Version 1.2.3'), findsOneWidget);
  });

  testWidgets('the password field starts obscured and the eye icon toggles visibility', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => {'trees': <dynamic>[]});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    final passwordField = find.byType(TextField).at(1);
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();

    expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('submitting wrong credentials shows the error and re-enables the button', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => {'trees': <dynamic>[]});
    when(() => client.login(username: 'alice', password: 'wrong')).thenAnswer((_) async => false);

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'alice');
    await tester.enterText(find.byType(TextField).at(1), 'wrong');
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();

    expect(find.text('Benutzername oder Passwort ist falsch.'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('the username and password fields are present and hold exactly what was typed into them', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => {'trees': <dynamic>[]});

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
    final usernameField = find.byType(TextField).at(0);
    final passwordField = find.byType(TextField).at(1);

    await tester.enterText(usernameField, 'bob');
    await tester.enterText(passwordField, 'hunter2');

    expect(tester.widget<TextField>(usernameField).controller!.text, 'bob');
    expect(tester.widget<TextField>(passwordField).controller!.text, 'hunter2');
  });

  testWidgets('the username is trimmed before being sent to login()', (tester) async {
    // info() is called 3 times end to end: once by LoginScreen's own
    // initState (tree title), then twice inside AuthController.login()
    // (CSRF setup, then the post-login loggedIn check) - only the last of
    // those needs a 'user' object.
    var infoCallCount = 0;
    when(() => client.info('Famtree')).thenAnswer((_) async {
      infoCallCount++;
      if (infoCallCount < 3) return {'trees': <dynamic>[]};
      return {
        'trees': <dynamic>[],
        'user': {'loggedIn': true, 'userName': 'alice', 'realName': 'Alice A.'},
      };
    });
    when(() => client.login(username: 'alice', password: 'secret')).thenAnswer((_) async => true);
    when(() => client.sessionCookie).thenReturn('wtcookie=abc');

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '  alice  ');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.text('Anmelden'));
    await tester.pumpAndSettle();

    verify(() => client.login(username: 'alice', password: 'secret')).called(1);
  });
}
