import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/webtrees_client.dart';
import '../repositories/quick_note_store.dart';

const _secureStorage = FlutterSecureStorage();

/// The real, migrated webtrees instance. This is the app's default target.
const productionServerUrl = 'https://stammbaum.familiescharf.at';
const productionTreeName = 'Famtree';

/// The local dev webtrees instance, only reachable from this machine.
///
/// The Android emulator can't reach the host's `localhost` directly — its
/// special alias `10.0.2.2` routes to the host instead. The iOS simulator
/// can use `localhost` as-is. This only matters for the dev server; the
/// production URL above is a real public host, reachable identically from
/// both.
String get devServerUrl =>
    Platform.isAndroid ? 'http://10.0.2.2:8080/' : 'http://localhost:8080/';
const devTreeName = 'devtree';

/// The webtrees site to talk to. Settings screen lets the user change this;
/// defaults to production for now.
class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() => productionServerUrl;
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(
  ServerUrlNotifier.new,
);

class TreeNameNotifier extends Notifier<String> {
  @override
  String build() => productionTreeName;
}

final treeNameProvider = NotifierProvider<TreeNameNotifier, String>(
  TreeNameNotifier.new,
);

/// Which bottom-nav tab is showing. A screen embedded as a tab (e.g.
/// AddPersonScreen reached via "Neu") has no route of its own to pop — its
/// "Abbrechen"/success actions switch this back to Start instead.
class SelectedTabNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void select(int index) => state = index;
}

final selectedTabProvider = NotifierProvider<SelectedTabNotifier, int>(
  SelectedTabNotifier.new,
);

final webtreesClientProvider = Provider<WebtreesClient>((ref) {
  final url = ref.watch(serverUrlProvider);
  return WebtreesClient(baseUrl: url);
});

/// The tree's privacy-policy page - the nearest thing to a legal-notice page
/// this site has (see the "Datenschutz" link in the account/login screens'
/// footers). Route format matches webtrees' own module-route convention,
/// same as [WebtreesClient]'s own URL building.
String privacyPolicyUrl(WidgetRef ref) {
  final server = ref.read(serverUrlProvider);
  final base = server.endsWith('/') ? server : '$server/';
  final tree = ref.read(treeNameProvider);
  final route = Uri.encodeComponent('/module/privacy-policy/Page/$tree');
  return '${base}index.php?route=$route';
}

/// The webtrees-share module's "Anfragen" review list - there's no native
/// in-app screen for reviewing answers yet, so the unread-responses card
/// opens this on the website instead, same as [privacyPolicyUrl].
String shareRequestReviewUrl(WidgetRef ref) {
  final server = ref.read(serverUrlProvider);
  final base = server.endsWith('/') ? server : '$server/';
  final tree = ref.read(treeNameProvider);
  final route = Uri.encodeComponent('/module/_webtrees-share_/RequestReview/$tree');
  return '${base}index.php?route=$route';
}

final quickNoteStoreProvider = Provider<QuickNoteStore>(
  (ref) => QuickNoteStore(),
);

class AuthState {
  const AuthState({this.loggedIn = false, this.userName, this.realName});

  final bool loggedIn;
  final String? userName;
  final String? realName;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<String?> login(String username, String password) async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      await client.info(tree); // establishes session cookie + CSRF token
      final ok = await client.login(username: username, password: password);
      if (!ok) {
        return 'Benutzername oder Passwort ist falsch.';
      }

      final info = await client.info(tree);
      final user = info['user'] as Map<String, dynamic>;
      if (user['loggedIn'] != true) {
        return 'Anmeldung hat nicht funktioniert. Bitte erneut versuchen.';
      }

      await _saveSession(client);
      state = AuthState(
        loggedIn: true,
        userName: user['userName'] as String?,
        realName: user['realName'] as String?,
      );
      return null;
    } on DioException catch (e) {
      // A raw exception message (timeouts, TLS, DNS, ...) is meaningless to
      // someone tapping "Anmelden" on their phone — collapse it to one clear
      // message instead of surfacing Dio's internals.
      return switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.connectionError =>
          'Server nicht erreichbar. Bitte Internetverbindung prüfen.',
        DioExceptionType.badCertificate =>
          'Der Server konnte nicht sicher erreicht werden.',
        _ => 'Anmeldung fehlgeschlagen. Bitte später erneut versuchen.',
      };
    } on Exception {
      return 'Anmeldung fehlgeschlagen. Bitte später erneut versuchen.';
    }
  }

  Future<void> _saveSession(WebtreesClient client) async {
    final cookie = client.sessionCookie;
    if (cookie != null) {
      await _secureStorage.write(key: 'wt_session_cookie', value: cookie);
    }
  }

  Future<void> logout() async {
    ref.read(webtreesClientProvider).clearSession();
    await _secureStorage.delete(key: 'wt_session_cookie');
    state = const AuthState();
  }

  /// Try to resume a session saved from a previous launch.
  Future<void> tryRestoreSession() async {
    final String? cookie;
    try {
      cookie = await _secureStorage
          .read(key: 'wt_session_cookie')
          .timeout(const Duration(seconds: 3));
    } on Exception {
      return; // secure storage unavailable — fall back to the login screen
    }
    if (cookie == null) return;

    final client = ref.read(webtreesClientProvider);
    client.restoreSession(cookie: cookie);

    final tree = ref.read(treeNameProvider);
    try {
      final info = await client.info(tree);
      final user = info['user'] as Map<String, dynamic>;
      if (user['loggedIn'] == true) {
        state = AuthState(
          loggedIn: true,
          userName: user['userName'] as String?,
          realName: user['realName'] as String?,
        );
      } else {
        client.clearSession();
        await _secureStorage.delete(key: 'wt_session_cookie');
      }
    } on Exception {
      // Server unreachable — leave state logged-out; user can retry.
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
