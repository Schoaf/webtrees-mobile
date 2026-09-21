import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import 'response_detail_screen.dart';

/// Native equivalent of webtrees-share's request-review-list.phtml — every
/// answered/applied "ask a relative" request for this account, tap a row to
/// review it. Reached from the home screen's "Antworten erhalten" card and
/// from the "you got a response" email's deep link.
class ResponsesListScreen extends ConsumerStatefulWidget {
  const ResponsesListScreen({super.key});

  @override
  ConsumerState<ResponsesListScreen> createState() =>
      _ResponsesListScreenState();
}

class _ResponsesListScreenState extends ConsumerState<ResponsesListScreen> {
  late Future<List<Map<String, dynamic>>> _future;
  // A local, mutable copy of whatever _future last resolved to - Dismissible
  // needs a list it can remove an item from directly (as soon as the delete
  // is confirmed) rather than re-fetching and rebuilding from scratch.
  List<Map<String, dynamic>>? _requests;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    return client.shareRequestList(tree);
  }

  void _reload() => setState(() {
    _requests = null;
    _future = _load();
  });

  Future<bool> _confirmDelete(BuildContext context, int id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Anfrage verwerfen?'),
        content: const Text(
          'Die Anfrage und eine eventuell hinterlegte Foto-Vorschau werden endgültig gelöscht.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwerfen'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return false;
    }

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      return await client.shareRequestDelete(tree, id);
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(onBack: () => Navigator.of(context).pop()),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text('Konnte nicht laden: ${snapshot.error}'),
                    );
                  }

                  final requests = _requests ??= List.of(snapshot.data!);

                  if (requests.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Keine Antworten vorhanden.',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: requests.length,
                    itemBuilder: (context, index) {
                      final item = requests[index];
                      final responder = item['responder'] as String? ?? '';

                      return Dismissible(
                        key: ValueKey(item['id']),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            _confirmDelete(context, item['id'] as int),
                        onDismissed: (_) =>
                            setState(() => _requests!.removeAt(index)),
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: Colors.red.shade400,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.delete_outline,
                            color: Colors.white,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            clipBehavior: Clip.antiAlias,
                            elevation: 0,
                            child: InkWell(
                              onTap: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => ResponseDetailScreen(
                                      id: item['id'] as int,
                                    ),
                                  ),
                                );
                                _reload();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  boxShadow: AppColors.cardShadow,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item['name'] as String? ?? '',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          if (responder.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Von $responder',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: AppColors.textTertiary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const Expanded(
            child: Text(
              'Antworten',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}
