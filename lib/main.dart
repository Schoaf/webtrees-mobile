import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/add_person/add_person_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/search/search_screen.dart';
import 'state/app_providers.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: StammbaumApp()));
}

class StammbaumApp extends StatelessWidget {
  const StammbaumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stammbaum',
      theme: buildAppTheme(),
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

  @override
  void initState() {
    super.initState();
    ref.read(authControllerProvider.notifier).tryRestoreSession().whenComplete(
      () {
        if (mounted) setState(() => _restoring = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_restoring) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final auth = ref.watch(authControllerProvider);
    return auth.loggedIn ? const _HomeShell() : const LoginScreen();
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
