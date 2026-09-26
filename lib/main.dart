import 'package:app_links/app_links.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'screens/add_person/add_person_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/responses/response_detail_screen.dart';
import 'screens/search/person_detail_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/tree_picker/tree_picker_screen.dart';
import 'state/app_providers.dart';
import 'theme/app_theme.dart';
import 'utils/connect_deep_link.dart';
import 'utils/person_deep_link.dart';
import 'utils/share_review_deep_link.dart';
import 'widgets/load_error_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A "Verbinden" link from any previous launch may have repointed this
  // device at a different server/tree than the built-in default - resolved
  // here (before runApp) rather than lazily inside the providers, since
  // Notifier.build() can't be async. See loadActiveConnection.
  final active = await loadActiveConnection();
  runApp(
    ProviderScope(
      overrides: [
        serverUrlProvider.overrideWith(() => ServerUrlNotifier(initial: active.serverUrl)),
        treeNameProvider.overrideWith(() => TreeNameNotifier(initial: active.treeName)),
      ],
      child: const StammbaumApp(),
    ),
  );
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  // A "Verbinden" (Connect) link's pairing flow - see _handleConnectLink.
  // Shown/cleared independently of _restoring/_needsBiometricUnlock since
  // it can happen well after those have already settled (the app was
  // already sitting on the login screen when the link arrived).
  bool _connecting = false;
  String? _connectError;

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
    _listenForDeepLinks();
  }

  /// Opens a shared person link, a "you got a response" review-request
  /// link (both plain Universal Links/App Links on stammbaum.familiescharf.at),
  /// or a "Verbinden" pairing link (webtreesmobile://connect?...) - the
  /// last one unlike the first two: it works *before* login, since pairing
  /// is itself how this device gets logged in in the first place. Person/
  /// review links only act once already logged in - if one arrives before
  /// that, it's simply dropped and the person opens the login screen like
  /// any other cold start.
  void _listenForDeepLinks() {
    void handle(Uri uri) {
      final connectParams = connectParamsFromLink(uri);
      if (connectParams != null) {
        _handleConnectLink(connectParams);
        return;
      }

      if (!ref.read(authControllerProvider).loggedIn) return;

      final xref = personXrefFromLink(uri);
      if (xref != null) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: xref)),
        );
        return;
      }

      final reviewId = shareReviewIdFromLink(uri);
      if (reviewId != null) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => ResponseDetailScreen(id: reviewId),
          ),
        );
      }
    }

    _appLinks.getInitialLink().then((uri) {
      if (uri != null) handle(uri);
    });
    _appLinks.uriLinkStream.listen(handle);
  }

  /// Redeems a "Verbinden" pairing code: repoints this device at the
  /// link's server (WebtreesClient.pair needs a session/CSRF context on
  /// *that* server, not whatever was active before), redeems the code, and
  /// - once actually logged in - either goes straight to the (only) tree
  /// or lets the person pick among several. No password ever typed; see
  /// AppPages::postPairAction on the server for the other half of this.
  Future<void> _handleConnectLink(ConnectParams params) async {
    setState(() {
      _connecting = true;
      _connectError = null;
    });
    final l10n = AppLocalizations.of(context)!;
    // The link always carries the tree the "App" page was opened from, but
    // guard the (should-never-happen) empty-string case the PHP side could
    // technically produce - Info still needs *some* tree name in its own
    // URL, even though its response always covers every tree regardless.
    final fallbackTree = (params.tree?.isNotEmpty ?? false) ? params.tree! : productionTreeName;

    try {
      await ref.read(serverUrlProvider.notifier).set(params.serverUrl);
      final client = ref.read(webtreesClientProvider); // fresh - watches serverUrlProvider
      await client.info(fallbackTree); // establishes a session/CSRF context on the *new* server

      final pairResult = await client.pair(params.code);
      if (pairResult['ok'] != true) {
        setState(() => _connectError = l10n.couldNotLoad('${pairResult['error']}'));
        return;
      }

      final treeFromPair = pairResult['tree'] as String? ?? fallbackTree;
      final authError = await ref.read(authControllerProvider.notifier).adoptPairedSession(treeFromPair);
      if (authError != null) {
        setState(() => _connectError = authError.message(l10n));
        return;
      }

      // Set *before* possibly showing the picker (not just inside it), so
      // the home screen underneath is already correct even while the
      // picker is up, and stays correct if the person just picks the same
      // (first) tree anyway.
      await ref.read(treeNameProvider.notifier).set(treeFromPair);

      final info = await client.info(treeFromPair);
      final trees = (info['trees'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      if (trees.length > 1 && mounted) {
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => TreePickerScreen(trees: trees)),
        );
      }
    } on DioException {
      if (mounted) setState(() => _connectError = l10n.authErrorServerUnreachable);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_connecting) {
      final l10n = AppLocalizations.of(context)!;
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(l10n.connectingMessage),
            ],
          ),
        ),
      );
    }

    if (_connectError != null) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => setState(() => _connectError = null))),
        body: SafeArea(child: LoadErrorView(message: _connectError!)),
      );
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
    final ok = await ref
        .read(biometricAuthProvider)
        .authenticate(
          localizedReason: AppLocalizations.of(context)!.unlockAppReason,
        );
    if (!mounted) return;
    setState(() => _authenticating = false);
    if (ok) widget.onUnlocked();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fingerprint, size: 56),
              const SizedBox(height: 16),
              Text(
                l10n.appLockedTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
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
                    : Text(l10n.unlockButton),
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
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(index: index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).select(i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: l10n.navSearch,
          ),
          NavigationDestination(icon: const Icon(Icons.add), label: l10n.navNew),
        ],
      ),
    );
  }
}
