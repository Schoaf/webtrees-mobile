import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:webtrees_mobile/api/webtrees_client.dart';
import 'package:webtrees_mobile/state/app_providers.dart';

class MockWebtreesClient extends Mock implements WebtreesClient {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // AuthController persists the session cookie via flutter_secure_storage,
  // which talks to a real platform channel with no native implementation
  // under `flutter test`. Fake that channel with a tiny in-memory store so
  // the real save/restore/clear code paths run instead of always hitting
  // the "secure storage unavailable" catch branches.
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
      case 'delete':
        secureStore.remove(args['key'] as String);
        return null;
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

  group('SelectedTabNotifier', () {
    test('defaults to 0 and updates on select()', () {
      final notifier = container.read(selectedTabProvider.notifier);
      expect(container.read(selectedTabProvider), 0);
      notifier.select(2);
      expect(container.read(selectedTabProvider), 2);
    });
  });

  group('ServerUrlNotifier / TreeNameNotifier', () {
    test('default to the production server and tree', () {
      expect(container.read(serverUrlProvider), productionServerUrl);
      expect(container.read(treeNameProvider), productionTreeName);
    });
  });

  group('privacyPolicyUrl', () {
    testWidgets('builds the module route for the current tree against the current server', (tester) async {
      late String url;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) {
              url = privacyPolicyUrl(ref);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        url,
        '$productionServerUrl/'
        'index.php?route=%2Fmodule%2Fprivacy-policy%2FPage%2F$productionTreeName',
      );
    });
  });

  group('siteUrl', () {
    test('adds index.php and the mobile flag to a plain server URL', () {
      expect(siteUrl('https://example.org/', mobile: true).toString(), 'https://example.org/index.php?mobile=1');
      expect(siteUrl('https://example.org', mobile: false).toString(), 'https://example.org/index.php?mobile=0');
      expect(siteUrl('https://example.org/webtrees/', mobile: false).toString(), 'https://example.org/webtrees/index.php?mobile=0');
    });

    test('keeps an existing route parameter', () {
      final uri = siteUrl('https://example.org/index.php?route=%2Fmodule%2Fprivacy-policy%2FPage%2Ftree', mobile: true);

      expect(uri.path, '/index.php');
      expect(uri.queryParameters, {'route': '/module/privacy-policy/Page/tree', 'mobile': '1'});
    });
  });

  group('AuthController.login', () {
    test('on success, saves the session and reflects the logged-in user', () async {
      var infoCallCount = 0;
      when(() => client.info('Famtree')).thenAnswer((_) async {
        infoCallCount++;
        if (infoCallCount == 1) return {'csrf': 'tok-1'};
        return {
          'user': {'loggedIn': true, 'userName': 'alice', 'realName': 'Alice A.'},
        };
      });
      when(() => client.login(username: 'alice', password: 's3cret')).thenAnswer((_) async => true);
      when(() => client.sessionCookie).thenReturn('wtcookie=abc');

      final error = await container.read(authControllerProvider.notifier).login('alice', 's3cret');

      expect(error, isNull);
      final state = container.read(authControllerProvider);
      expect(state.loggedIn, isTrue);
      expect(state.userName, 'alice');
      expect(state.realName, 'Alice A.');
      expect(infoCallCount, 2);
      expect(secureStore['wt_session_cookie'], 'wtcookie=abc');
    });

    test('a wrong password returns the German "wrong credentials" message without a second info() call', () async {
      when(() => client.info('Famtree')).thenAnswer((_) async => {'csrf': 'tok-1'});
      when(() => client.login(username: 'alice', password: 'wrong')).thenAnswer((_) async => false);

      final error = await container.read(authControllerProvider.notifier).login('alice', 'wrong');

      expect(error, AuthError.invalidCredentials);
      expect(container.read(authControllerProvider).loggedIn, isFalse);
      verify(() => client.info('Famtree')).called(1);
    });

    test('login() succeeding but the follow-up info() showing loggedIn=false surfaces a retry message', () async {
      var infoCallCount = 0;
      when(() => client.info('Famtree')).thenAnswer((_) async {
        infoCallCount++;
        if (infoCallCount == 1) return {'csrf': 'tok-1'};
        return {
          'user': {'loggedIn': false},
        };
      });
      when(() => client.login(username: 'alice', password: 's3cret')).thenAnswer((_) async => true);

      final error = await container.read(authControllerProvider.notifier).login('alice', 's3cret');

      expect(error, AuthError.loginDidNotWork);
      expect(container.read(authControllerProvider).loggedIn, isFalse);
    });

    test('a connection-error DioException is collapsed to a friendly unreachable-server message', () async {
      when(() => client.info('Famtree')).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.connectionError),
      );

      final error = await container.read(authControllerProvider.notifier).login('alice', 's3cret');

      expect(error, AuthError.serverUnreachable);
    });

    test('a badCertificate DioException gets its own message', () async {
      when(() => client.info('Famtree')).thenThrow(
        DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.badCertificate),
      );

      final error = await container.read(authControllerProvider.notifier).login('alice', 's3cret');

      expect(error, AuthError.insecureConnection);
    });

    test('any other Exception falls back to a generic failure message', () async {
      when(() => client.info('Famtree')).thenThrow(Exception('boom'));

      final error = await container.read(authControllerProvider.notifier).login('alice', 's3cret');

      expect(error, AuthError.loginFailedGeneric);
    });
  });

  group('AuthController.logout', () {
    test('clears the client session, deletes the stored cookie, and resets state', () async {
      secureStore['wt_session_cookie'] = 'wtcookie=abc';
      when(() => client.clearSession()).thenReturn(null);

      await container.read(authControllerProvider.notifier).logout();

      final state = container.read(authControllerProvider);
      expect(state.loggedIn, isFalse);
      expect(state.userName, isNull);
      verify(() => client.clearSession()).called(1);
      expect(secureStore.containsKey('wt_session_cookie'), isFalse);
    });
  });

  group('AuthController.tryRestoreSession', () {
    test('does nothing when no cookie was saved', () async {
      await container.read(authControllerProvider.notifier).tryRestoreSession();

      expect(container.read(authControllerProvider).loggedIn, isFalse);
      verifyNever(() => client.restoreSession(cookie: any(named: 'cookie')));
    });

    test('restores a saved cookie and logs the user in when the session is still valid', () async {
      secureStore['wt_session_cookie'] = 'wtcookie=abc';
      when(() => client.restoreSession(cookie: 'wtcookie=abc')).thenReturn(null);
      when(() => client.info('Famtree')).thenAnswer(
        (_) async => {
          'user': {'loggedIn': true, 'userName': 'bob', 'realName': 'Bob B.'},
        },
      );

      await container.read(authControllerProvider.notifier).tryRestoreSession();

      final state = container.read(authControllerProvider);
      expect(state.loggedIn, isTrue);
      expect(state.userName, 'bob');
      verify(() => client.restoreSession(cookie: 'wtcookie=abc')).called(1);
    });

    test('a no-longer-valid session clears the client and the stored cookie', () async {
      secureStore['wt_session_cookie'] = 'wtcookie=stale';
      when(() => client.restoreSession(cookie: 'wtcookie=stale')).thenReturn(null);
      when(() => client.info('Famtree')).thenAnswer(
        (_) async => {
          'user': {'loggedIn': false},
        },
      );
      when(() => client.clearSession()).thenReturn(null);

      await container.read(authControllerProvider.notifier).tryRestoreSession();

      expect(container.read(authControllerProvider).loggedIn, isFalse);
      verify(() => client.clearSession()).called(1);
      expect(secureStore.containsKey('wt_session_cookie'), isFalse);
    });

    test('an unreachable server during restore leaves state logged-out without throwing', () async {
      secureStore['wt_session_cookie'] = 'wtcookie=abc';
      when(() => client.restoreSession(cookie: 'wtcookie=abc')).thenReturn(null);
      when(() => client.info('Famtree')).thenThrow(Exception('unreachable'));

      await container.read(authControllerProvider.notifier).tryRestoreSession();

      expect(container.read(authControllerProvider).loggedIn, isFalse);
    });
  });
}
