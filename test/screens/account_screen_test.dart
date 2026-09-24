import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/l10n/app_localizations.dart';
import 'package:webtrees_mobile/screens/account/account_screen.dart';
import 'package:webtrees_mobile/screens/search/person_detail_screen.dart';
import 'package:webtrees_mobile/screens/search/search_screen.dart';
import 'package:webtrees_mobile/services/biometric_auth_service.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

class MockBiometricAuthService extends Mock implements BiometricAuthService {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  PackageInfo.setMockInitialValues(
    appName: 'Stammbaum',
    packageName: 'at.familiescharf.stammbaum',
    version: '1.2.3',
    buildNumber: '9',
    buildSignature: '',
  );

  // AuthController.logout() writes to flutter_secure_storage - fake that
  // channel (same approach as test/state/app_providers_test.dart) so the
  // real logout path runs instead of throwing MissingPluginException.
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
  late MockBiometricAuthService biometrics;
  late ProviderContainer container;

  Map<String, dynamic> infoResponse({
    String userXref = 'I1',
    String defaultXref = 'I2',
    String role = 'editor',
    String realName = 'Alice A.',
    String userName = 'alice',
  }) => {
    'user': {'userName': userName, 'realName': realName},
    'trees': [
      {'name': 'Famtree', 'role': role, 'userXref': userXref, 'defaultXref': defaultXref},
    ],
  };

  Map<String, dynamic> personResponse(String xref, {String name = 'Some Person'}) => {
    'person': {'xref': xref, 'name': name, 'sex': 'F', 'isDead': false, 'lifespan': '1990-'},
  };

  setUp(() {
    client = MockWebtreesClient();
    biometrics = MockBiometricAuthService();
    when(() => client.imageHeaders).thenReturn(<String, String>{});
    when(() => biometrics.isDeviceSupported()).thenAnswer((_) async => false);
    container = ProviderContainer(
      overrides: [
        webtreesClientProvider.overrideWithValue(client),
        biometricAuthProvider.overrideWithValue(biometrics),
      ],
    );
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
          home: AccountScreen(),
        ),
      ),
    );
  }

  testWidgets('shows username, real name, role, linked person and Startperson once loaded', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1', name: 'Linked One'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2', name: 'Start Two'));

    await pumpScreen(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('alice'), findsOneWidget);
    expect(find.text('Alice A.'), findsOneWidget);
    expect(find.text('Bearbeiter'), findsOneWidget);
    expect(find.text('Linked One', findRichText: true), findsOneWidget);
    expect(find.text('Start Two', findRichText: true), findsOneWidget);
  });

  testWidgets('shows a load error instead of crashing', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) => Future.error(Exception('offline')));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Konnte nicht laden:'), findsOneWidget);
  });

  testWidgets('shows empty-state notes when no person is linked/no Startperson is set', (tester) async {
    when(() => client.info('Famtree')).thenAnswer(
      (_) async => infoResponse(userXref: '', defaultXref: ''),
    );

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    expect(find.text('Keine Person mit diesem Konto verknüpft.'), findsOneWidget);
    expect(find.text('Keine Startperson festgelegt.'), findsOneWidget);
  });

  testWidgets('tapping the linked person opens PersonDetailScreen for their xref', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1', name: 'Linked One'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2', name: 'Start Two'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Linked One', findRichText: true));
    await tester.pumpAndSettle();

    expect(find.byType(PersonDetailScreen), findsOneWidget);
    expect(tester.widget<PersonDetailScreen>(find.byType(PersonDetailScreen)).xref, 'I1');
  });

  testWidgets('tapping a field copies its value to the clipboard', (tester) async {
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2'));

    await pumpScreen(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('alice'));
    await tester.pump();

    expect(clipboardText, 'alice');
  });

  group('editing', () {
    testWidgets('saving a changed name sends only realName, refetches, and shows a confirmation', (tester) async {
      when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
      when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2'));
      when(
        () => client.updateAccount('Famtree', realName: 'Alice B.', defaultXref: null),
      ).thenAnswer((_) async => {'ok': true});

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Alice B.');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      verify(() => client.updateAccount('Famtree', realName: 'Alice B.', defaultXref: null)).called(1);
      verify(() => client.info('Famtree')).called(2);
      expect(find.text('Änderungen gespeichert.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a save failure shows the error and stays in editing mode', (tester) async {
      when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
      when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2'));
      when(
        () => client.updateAccount('Famtree', realName: 'Alice B.', defaultXref: null),
      ).thenAnswer((_) async => {'ok': false, 'error': 'name taken'});

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Alice B.');
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Speichern fehlgeschlagen:'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('cancelling editing discards the typed name without saving', (tester) async {
      when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
      when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2'));

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Discarded Name');

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      verifyNever(() => client.updateAccount(any(), realName: any(named: 'realName'), defaultXref: any(named: 'defaultXref')));
      expect(find.text('Alice A.'), findsOneWidget);
      expect(find.text('Discarded Name'), findsNothing);
    });

    testWidgets('changing the Startperson via the picker sends the new defaultXref', (tester) async {
      when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
      when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
      when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2'));
      when(() => client.individuals('Famtree', query: 'Neu')).thenAnswer(
        (_) async => {
          'data': [
            {'xref': 'I9', 'name': 'Neu Person', 'sex': 'F', 'isDead': false},
          ],
        },
      );
      when(
        () => client.updateAccount('Famtree', realName: null, defaultXref: 'I9'),
      ).thenAnswer((_) async => {'ok': true});

      await pumpScreen(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Startperson ändern'));
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Neu');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Neu Person', findRichText: true));
      await tester.pumpAndSettle();

      expect(find.byType(SearchScreen), findsNothing);
      expect(find.text('Neu Person', findRichText: true), findsOneWidget);

      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();

      verify(() => client.updateAccount('Famtree', realName: null, defaultXref: 'I9')).called(1);
    });
  });

  testWidgets('logging out clears the session and pops back to the app root', (tester) async {
    when(() => client.info('Famtree')).thenAnswer((_) async => infoResponse());
    when(() => client.individual('Famtree', 'I1')).thenAnswer((_) async => personResponse('I1'));
    when(() => client.individual('Famtree', 'I2')).thenAnswer((_) async => personResponse('I2'));
    when(() => client.clearSession()).thenReturn(null);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
              child: const Text('open account'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open account'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Abmelden'));
    await tester.pumpAndSettle();

    verify(() => client.clearSession()).called(1);
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.text('open account'), findsOneWidget);
  });
}
