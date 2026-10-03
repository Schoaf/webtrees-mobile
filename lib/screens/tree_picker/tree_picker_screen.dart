import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../widgets/load_error_view.dart';

/// Lets the user pick which of the account's trees is active on this
/// device - wtAnd's own model (see the project notes this ports): no
/// per-user default tree on the server, the client just remembers the
/// last choice itself ([TreeNameNotifier.set]). Reached two ways: right
/// after a "Verbinden" pairing that found more than one tree (with
/// [trees] already in hand from that same `Info` call, so this doesn't
/// re-fetch), or from "Stammbaum wechseln" in "Mein Konto" (with [trees]
/// omitted, so this screen loads them itself).
class TreePickerScreen extends ConsumerStatefulWidget {
  const TreePickerScreen({super.key, this.trees});

  /// Pre-fetched `Info` `trees[]`, if the caller already has it (right
  /// after pairing). When null, this screen fetches it itself.
  final List<Map<String, dynamic>>? trees;

  @override
  ConsumerState<TreePickerScreen> createState() => _TreePickerScreenState();
}

class _TreePickerScreenState extends ConsumerState<TreePickerScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.trees != null ? Future.value(widget.trees) : _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    final client = ref.read(webtreesClientProvider);
    final currentTree = ref.read(treeNameProvider);
    // Any valid tree name works here - Info's own trees[] always covers
    // every tree the account can see, regardless of which one was asked
    // for (see ReadActions::getInfoAction).
    final info = await client.info(currentTree);
    return (info['trees'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
  }

  Future<void> _choose(String treeName) async {
    await ref.read(treeNameProvider.notifier).set(treeName);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.treePickerTitle)),
      body: SafeArea(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return LoadErrorView(message: l10n.couldNotLoad('${snapshot.error}'));
            }

            final trees = snapshot.data!;
            return ListView.separated(
              itemCount: trees.length,
              separatorBuilder: (context, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final tree = trees[index];
                final name = tree['name'] as String? ?? '';
                final title = tree['title'] as String? ?? name;
                final individuals = tree['individuals'] as int? ?? 0;
                final isActive = name == ref.watch(treeNameProvider);
                return ListTile(
                  title: Text(title),
                  subtitle: Text(l10n.individualsInTree(individuals)),
                  trailing: isActive ? const Icon(Icons.check) : null,
                  onTap: () => _choose(name),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
