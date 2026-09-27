import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/app_localizations.dart';
import 'screens/add_person/add_person_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/responses/response_detail_screen.dart';
import 'screens/search/person_detail_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/tree_view/my_tree_view_screen.dart';
import 'state/app_providers.dart';
import 'theme/app_theme.dart';
import 'utils/device_size.dart';
import 'utils/person_deep_link.dart';
import 'utils/share_review_deep_link.dart';
import 'widgets/tab_navigator.dart';
import 'widgets/tree_icons.dart';

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

  /// Opens a shared person link or a "you got a response" review-request
  /// link (both plain Universal Links/App Links on stammbaum.familiescharf.at)
  /// directly to the matching screen, whether the app was already running or
  /// just launched by tapping the link. Only acts once logged in — if a link
  /// arrives before that, it's simply dropped and the person opens the login
  /// screen like any other cold start (same as it always has for person
  /// links; there's no "come back here after login" for review links yet).
  void _listenForDeepLinks() {
    void handle(Uri uri) {
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

class _HomeShell extends ConsumerStatefulWidget {
  const _HomeShell();

  @override
  ConsumerState<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<_HomeShell> {
  static const _screens = [
    HomeScreen(),
    MyTreeViewScreen(),
    SearchScreen(),
    AddPersonScreen(),
  ];

  // One per tab, created once and kept for this State's whole lifetime -
  // each tab's nested Navigator (tablet only, see build()) needs the SAME
  // GlobalKey across rebuilds for its own pushed route stack to survive
  // switching tabs and back, not a fresh one every build().
  final _navigatorKeys = List.generate(
    _screens.length,
    (_) => GlobalKey<NavigatorState>(),
  );

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    final l10n = AppLocalizations.of(context)!;
    // Phone: screens render directly, so every push goes to the app's one
    // root Navigator - full-screen, covering this whole shell including
    // the bottom nav bar, exactly as before this existed. Tablet: each tab
    // gets its own nested Navigator instead, so opening a person/tree/etc.
    // pushes within that tab's own content area, and the bottom nav bar -
    // a sibling of that content area, not something any of those pushes
    // can cover - stays on screen the whole time. See TabNavigator for
    // the back-button wiring this needs to keep working correctly.
    final tabbed = isTabletDevice(context);
    final screens = tabbed
        ? [
            for (var i = 0; i < _screens.length; i++)
              TabNavigator(navigatorKey: _navigatorKeys[i], child: _screens[i]),
          ]
        : _screens;
    return Scaffold(
      body: IndexedStack(index: index, children: screens),
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
            // Same colors NavigationBarThemeData.iconTheme resolves for
            // Icon-based destinations - GenealogyTreeIcon is a CustomPaint,
            // not an Icon, so it doesn't pick up the ambient IconTheme
            // NavigationBar injects automatically; set explicitly instead.
            icon: const GenealogyTreeIcon(color: AppColors.textSecondary),
            selectedIcon: const GenealogyTreeIcon(color: AppColors.primary),
            label: l10n.navTree,
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

