import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/webtrees_client.dart';
import '../repositories/quick_note_store.dart';

const _secureStorage = FlutterSecureStorage();

/// The webtrees site to talk to. Settings screen lets the user change this;
/// defaults to the local dev instance for now.
///
/// Note for local development: the Android emulator can't reach the host's
/// `localhost` directly — use `10.0.2.2` instead. The iOS simulator can use
/// `localhost` as-is.
class ServerUrlNotifier extends Notifier<String> {
  @override
  String build() => 'http://localhost:8080/';
}

final serverUrlProvider = NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

class TreeNameNotifier extends Notifier<String> {
  @override
  String build() => 'devtree';
}

final treeNameProvider = NotifierProvider<TreeNameNotifier, String>(TreeNameNotifier.new);

final webtreesClientProvider = Provider<WebtreesClient>((ref) {
  final url = ref.watch(serverUrlProvider);
  return WebtreesClient(baseUrl: url);
});

final quickNoteStoreProvider = Provider<QuickNoteStore>((ref) => QuickNoteStore());

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
        return 'The username or password is incorrect.';
      }

      final info = await client.info(tree);
      final user = info['user'] as Map<String, dynamic>;
      if (user['loggedIn'] != true) {
        return 'Login did not take effect. Please try again.';
      }

      await _saveSession(client);
      state = AuthState(
        loggedIn: true,
        userName: user['userName'] as String?,
        realName: user['realName'] as String?,
      );
      return null;
    } on Exception catch (e) {
      return 'Could not reach the server: $e';
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
      cookie = await _secureStorage.read(key: 'wt_session_cookie').timeout(const Duration(seconds: 3));
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

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
