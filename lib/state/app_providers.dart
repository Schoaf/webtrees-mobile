import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/webtrees_client.dart';
import '../l10n/app_localizations.dart';
import '../repositories/quick_note_store.dart';
import '../services/biometric_auth_service.dart';

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

/// Secure-storage keys for the currently active server/tree - written
/// whenever a "Verbinden" link pairs the app to a (possibly different)
/// server, or "Stammbaum wechseln" picks a different tree on the same
/// server. Read once at startup, in [loadActiveConnection], before
/// [ServerUrlNotifier]/[TreeNameNotifier] are ever built - Riverpod
/// `Notifier.build()` can't be async, so the persisted value (if any) is
/// resolved ahead of time and injected via `overrideWith` in `main()`
/// rather than loaded lazily from inside the notifier.
const _kServerUrlStorageKey = 'active_server_url';
const _kTreeNameStorageKey = 'active_tree_name';

/// The server+tree this device is currently paired to (production if
/// never paired via a "Verbinden" link) - read in `main()` before
/// `runApp`, see [_kServerUrlStorageKey].
Future<({String serverUrl, String treeName})> loadActiveConnection() async {
  try {
    final serverUrl = await _secureStorage.read(key: _kServerUrlStorageKey).timeout(const Duration(seconds: 3));
    final treeName = await _secureStorage.read(key: _kTreeNameStorageKey).timeout(const Duration(seconds: 3));
    return (serverUrl: serverUrl ?? productionServerUrl, treeName: treeName ?? productionTreeName);
  } on Exception {
    return (serverUrl: productionServerUrl, treeName: productionTreeName); // secure storage unavailable
  }
}

/// The webtrees site to talk to - defaults to production, but a
/// "Verbinden" link can repoint this device at any other webtrees
/// instance running api4webtrees (see connect_deep_link.dart). Persisted
/// via [set] so the choice survives a relaunch; [loadActiveConnection]
/// supplies the initial value via `overrideWith` before this notifier is
/// ever built, so existing installations that never used a connect link
/// see no change in behavior.
class ServerUrlNotifier extends Notifier<String> {
  ServerUrlNotifier({this.initial = productionServerUrl});

  final String initial;

  @override
  String build() => initial;

  Future<void> set(String url) async {
    state = url;
    await _secureStorage.write(key: _kServerUrlStorageKey, value: url);
  }
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(
  ServerUrlNotifier.new,
);

/// The active tree on [serverUrlProvider]'s server - a server can host
/// more than one; see TreePickerScreen and "Stammbaum wechseln" in
/// account_screen.dart. Same persistence story as [ServerUrlNotifier].
class TreeNameNotifier extends Notifier<String> {
  TreeNameNotifier({this.initial = productionTreeName});

  final String initial;

  @override
  String build() => initial;

  Future<void> set(String tree) async {
    state = tree;
    await _secureStorage.write(key: _kTreeNameStorageKey, value: tree);
  }
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

/// A website URL opened from this device. `mobile=1` makes webtrees show its
/// "theme for mobile devices" (small pages like the privacy policy),
/// `mobile=0` its default theme (the full website) - either way for the rest
/// of that browser session, and overriding webtrees' own phone detection.
/// Only for links the app opens itself - links shared with other people
/// (e.g. the person page link) stay plain, the recipient may be on a desktop.
/// A bare folder URL gets `index.php`: webtrees' redirect from `/` mangles
/// any query string (`/?mobile=1` -> `/?mobile=1/index.php?route=0`).
Uri siteUrl(String url, {required bool mobile}) {
  final uri = Uri.parse(url);
  final path = uri.path.isEmpty || uri.path.endsWith('/')
      ? '${uri.path.isEmpty ? '/' : uri.path}index.php'
      : uri.path;
  return uri.replace(
    path: path,
    queryParameters: {...uri.queryParameters, 'mobile': mobile ? '1' : '0'},
  );
}

/// The webtrees "forgot password" page. Same route-building convention as
/// [privacyPolicyUrl].
String passwordRequestUrl(WidgetRef ref) {
  final server = ref.read(serverUrlProvider);
  final base = server.endsWith('/') ? server : '$server/';
  final tree = ref.read(treeNameProvider);
  final route = Uri.encodeComponent('/password-request/$tree');
  return '${base}index.php?route=$route';
}

/// The webtrees "create a new account" page. Same route-building convention
/// as [privacyPolicyUrl].
String registerUrl(WidgetRef ref) {
  final server = ref.read(serverUrlProvider);
  final base = server.endsWith('/') ? server : '$server/';
  final tree = ref.read(treeNameProvider);
  final route = Uri.encodeComponent('/register/$tree');
  return '${base}index.php?route=$route';
}

final quickNoteStoreProvider = Provider<QuickNoteStore>(
  (ref) => QuickNoteStore(),
);

final biometricAuthProvider = Provider<BiometricAuthService>(
  (ref) => BiometricAuthService(),
);

class AuthState {
  const AuthState({
    this.loggedIn = false,
    this.userName,
    this.realName,
    this.isAdmin = false,
  });

  final bool loggedIn;
  final String? userName;
  final String? realName;

  /// webtrees' real, site-wide Administrator flag (`Auth::isAdmin()`,
  /// already exposed as `user.isAdmin` in the Info response) - used to gate
  /// admin-only UI (e.g. the Stammbaum-Ansicht entry point). UI gate only,
  /// nothing further enforced server-side for this.
  final bool isAdmin;
}

/// Error codes for [AuthController.login]. Kept as codes rather than
/// pre-formatted strings so this state layer doesn't depend on
/// [AppLocalizations] (there's no BuildContext down here) —
/// [AuthErrorL10n.message] below maps a code to display text at the call
/// site, which does have one.
enum AuthError {
  invalidCredentials,
  loginDidNotWork,
  serverUnreachable,
  insecureConnection,
  loginFailedGeneric,
}

extension AuthErrorL10n on AuthError {
  String message(AppLocalizations l10n) => switch (this) {
    AuthError.invalidCredentials => l10n.authErrorInvalidCredentials,
    AuthError.loginDidNotWork => l10n.authErrorLoginDidNotWork,
    AuthError.serverUnreachable => l10n.authErrorServerUnreachable,
    AuthError.insecureConnection => l10n.authErrorInsecureConnection,
    AuthError.loginFailedGeneric => l10n.authErrorLoginFailedGeneric,
  };
}

/// A raw exception message (timeouts, TLS, DNS, ...) is meaningless to
/// someone tapping "Anmelden" (or waiting on a "Verbinden" link to
/// resolve) on their phone — collapse it to one clear message instead of
/// surfacing Dio's internals. Shared by [AuthController.login] and
/// [AuthController.adoptPairedSession].
AuthError _authErrorFromDioException(DioException e) => switch (e.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout ||
  DioExceptionType.connectionError =>
    AuthError.serverUnreachable,
  DioExceptionType.badCertificate => AuthError.insecureConnection,
  _ => AuthError.loginFailedGeneric,
};

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<AuthError?> login(String username, String password) async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      await client.info(tree); // establishes session cookie + CSRF token
      final ok = await client.login(username: username, password: password);
      if (!ok) {
        return AuthError.invalidCredentials;
      }

      final info = await client.info(tree);
      final user = info['user'] as Map<String, dynamic>;
      if (user['loggedIn'] != true) {
        return AuthError.loginDidNotWork;
      }

      await _saveSession(client);
      state = AuthState(
        loggedIn: true,
        userName: user['userName'] as String?,
        realName: user['realName'] as String?,
        isAdmin: user['isAdmin'] as bool? ?? false,
      );
      return null;
    } on DioException catch (e) {
      return _authErrorFromDioException(e);
    } on Exception {
      return AuthError.loginFailedGeneric;
    }
  }

  /// Completes a "Verbinden" pairing (see connect_deep_link.dart): the
  /// server has already authenticated this device via a one-time code
  /// (`WebtreesClient.pair`, called on `ref.read(webtreesClientProvider)`
  /// beforehand so it's talking to the *new* server/session already) - no
  /// password involved, unlike [login]. This just confirms the resulting
  /// session actually is logged in, then saves it the same way [login]
  /// does.
  Future<AuthError?> adoptPairedSession(String tree) async {
    final client = ref.read(webtreesClientProvider);

    try {
      final info = await client.info(tree);
      final user = info['user'] as Map<String, dynamic>;
      if (user['loggedIn'] != true) {
        return AuthError.loginDidNotWork;
      }

      await _saveSession(client);
      state = AuthState(
        loggedIn: true,
        userName: user['userName'] as String?,
        realName: user['realName'] as String?,
        isAdmin: user['isAdmin'] as bool? ?? false,
      );
      return null;
    } on DioException catch (e) {
      return _authErrorFromDioException(e);
    } on Exception {
      return AuthError.loginFailedGeneric;
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
          isAdmin: user['isAdmin'] as bool? ?? false,
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
