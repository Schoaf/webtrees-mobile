import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../widgets/load_error_view.dart';
import 'tree_view_screen.dart';

/// The "Stammbaum" bottom-nav tab: resolves which person to center the
/// tree view on (the account's own linked person, falling back to the
/// tree's Startperson - the same fallback order [HomeScreen] uses for its
/// header), then hands off to [TreeViewScreen] for the actual view. A
/// separate screen instead of doing this inline in [TreeViewScreen] itself
/// because that one is also pushed directly with an already-known xref
/// from [PersonDetailScreen]'s tree button, where this resolution step
/// doesn't apply.
class MyTreeViewScreen extends ConsumerStatefulWidget {
  const MyTreeViewScreen({super.key});

  @override
  ConsumerState<MyTreeViewScreen> createState() => _MyTreeViewScreenState();
}

class _MyTreeViewScreenState extends ConsumerState<MyTreeViewScreen> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolveXref();
  }

  Future<String?> _resolveXref() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final info = await client.info(tree);
    final treeInfo = (info['trees'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .firstWhere((t) => t['name'] == tree, orElse: () => const {});

    final userXref = treeInfo['userXref'] as String? ?? '';
    if (userXref.isNotEmpty) return userXref;
    final defaultXref = treeInfo['defaultXref'] as String? ?? '';
    return defaultXref.isNotEmpty ? defaultXref : null;
  }

  @override
  Widget build(BuildContext context) {
    // Drives TreeViewScreen.visibilitySignal - watched (not read) so this
    // widget, and TreeViewScreen below it, rebuild on every tab switch even
    // though both stay alive offstage the rest of the time (this is the
    // Stammbaum tab in an IndexedStack) - see the comment on
    // visibilitySignal for why that rebuild matters.
    final selectedTab = ref.watch(selectedTabProvider);

    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        final l10n = AppLocalizations.of(context)!;
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SafeArea(child: Center(child: CircularProgressIndicator())),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: LoadErrorView(message: l10n.couldNotLoad('${snapshot.error}')),
            ),
          );
        }
        final xref = snapshot.data;
        if (xref == null) {
          return Scaffold(
            body: SafeArea(
              child: LoadErrorView(message: l10n.noLinkedPersonError),
            ),
          );
        }
        return TreeViewScreen(xref: xref, visibilitySignal: selectedTab);
      },
    );
  }
}
