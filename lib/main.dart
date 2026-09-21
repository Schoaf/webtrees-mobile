import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/add_person/add_person_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/search/person_detail_screen.dart';
import 'screens/search/search_screen.dart';
import 'state/app_providers.dart';
import 'theme/app_theme.dart';
import 'utils/person_deep_link.dart';

void main() {
  runApp(const ProviderScope(child: StammbaumApp()));
}

/// Lets a shared person link (handled by [_AppRootState], which has no
/// BuildContext of its own to navigate with) push onto the app's one root
/// Navigator from anywhere.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class StammbaumApp extends StatelessWidget {
  const StammbaumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stammbaum',
      theme: buildAppTheme(),
      navigatorKey: rootNavigatorKey,
      home: const _AppRoot(),
    );
  }
}

class _AppRoot extends ConsumerStatefulWidget {
  const _AppRoot();

  @override
  ConsumerState<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends ConsumerState<_AppRoot> {
  bool _restoring = true;
  // Only ever set true right after a *silently restored* session from a
  // previous launch - a fresh interactive login (just typed a password)
  // never needs an extra biometric step on top of that.
  bool _needsBiometricUnlock = false;
  final _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();
    ref
        .read(authControllerProvider.notifier)
        .tryRestoreSession()
        .then((_) async {
          if (ref.read(authControllerProvider).loggedIn) {
            final enabled = await ref.read(biometricAuthProvider).isEnabled();
            if (enabled && mounted) {
              setState(() => _needsBiometricUnlock = true);
            }
          }
        })
        .whenComplete(() {
          if (mounted) setState(() => _restoring = false);
        });
    _listenForSharedPersonLinks();
  }

  /// Opens a shared person link (Universal Link/App Link) directly to that
  /// person's detail screen, whether the app was already running or just
  /// launched by tapping the link. Only acts once logged in — if a link
  /// arrives before that, it's simply dropped and the person opens the
  /// login screen like any other cold start.
  void _listenForSharedPersonLinks() {
    void handle(Uri uri) {
      final xref = personXrefFromLink(uri);
      if (xref == null) return;
      if (!ref.read(authControllerProvider).loggedIn) return;
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: xref)),
      );
    }

    _appLinks.getInitialLink().then((uri) {
      if (uri != null) handle(uri);
    });
    _appLinks.uriLinkStream.listen(handle);
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_needsBiometricUnlock) {
      return _LockScreen(
        onUnlocked: () => setState(() => _needsBiometricUnlock = false),
      );
    }

    final auth = ref.watch(authControllerProvider);
    return auth.loggedIn ? const _HomeShell() : const LoginScreen();
  }
}

/// Shown once, right after a session was silently restored from a previous
/// launch, if the user opted into the biometric app-lock (see
/// [BiometricAuthService]). Prompts automatically on first build so the
/// common case (unlock succeeds) needs no extra tap; a manual retry button
/// covers cancellation or a failed attempt.
class _LockScreen extends ConsumerStatefulWidget {
  const _LockScreen({required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  ConsumerState<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<_LockScreen> {
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    final ok = await ref.read(biometricAuthProvider).authenticate();
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint, size: 56),
              const SizedBox(height: 16),
              const Text(
                'App gesperrt',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _authenticating ? null : _authenticate,
                child: _authenticating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Entsperren'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeShell extends ConsumerWidget {
  const _HomeShell();

  static const _screens = [HomeScreen(), SearchScreen(), AddPersonScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    return Scaffold(
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).select(i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Start',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Suche'),
          NavigationDestination(icon: Icon(Icons.add), label: 'Neu'),
        ],
      ),
    );
  }
}
