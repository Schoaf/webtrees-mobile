import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/auth/login_screen.dart';
import 'screens/quick_capture/quick_capture_screen.dart';
import 'screens/search/search_screen.dart';
import 'state/app_providers.dart';

void main() {
  runApp(const ProviderScope(child: StammbaumApp()));
}

class StammbaumApp extends StatelessWidget {
  const StammbaumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Stammbaum',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal), useMaterial3: true),
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
    ref.read(authControllerProvider.notifier).tryRestoreSession().whenComplete(() {
      if (mounted) setState(() => _restoring = false);
    });
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

class _HomeShell extends StatefulWidget {
  const _HomeShell();

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;

  static const _screens = [QuickCaptureScreen(), SearchScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bolt), label: 'Capture'),
          NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
        ],
      ),
    );
  }
}
