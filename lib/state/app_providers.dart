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
    this.isManager = false,
  });

  final bool loggedIn;
  final String? userName;
  final String? realName;

  /// True for webtrees' highest per-tree role ('manager') on the active
  /// tree. The API has no separate site-Administrator flag, so this is the
  /// closest available stand-in for "admin" - used to gate admin-only UI
  /// (e.g. the Stammbaum-Ansicht entry point), not as a real security
  /// boundary (the server itself doesn't restrict the underlying endpoints
  /// any further for this).
  final bool isManager;
}

/// Picks out the active tree's role from an `Info` response's `trees` list
/// (see [WebtreesClient.info] / webtreesand-api's `role()` helper - one of
/// 'manager', 'moderator', 'editor', 'member', 'visitor').
bool _isManagerForTree(Map<String, dynamic> info, String tree) {
  final trees = info['trees'] as List<dynamic>?;
  if (trees == null) return false;
  for (final t in trees.cast<Map<String, dynamic>>()) {
    if (t['name'] == tree) return t['role'] == 'manager';
  }
  return false;
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
        isManager: _isManagerForTree(info, tree),
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
          AuthError.serverUnreachable,
        DioExceptionType.badCertificate => AuthError.insecureConnection,
        _ => AuthError.loginFailedGeneric,
      };
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
          isManager: _isManagerForTree(info, tree),
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
