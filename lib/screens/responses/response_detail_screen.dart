import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';

const _fieldLabels = {
  'GIVN': 'Vorname',
  'SURN': 'Nachname',
  'TITL': 'Titel',
  'BIRT_DATE': 'Geburtsdatum',
  'BIRT_PLAC': 'Geburtsort',
  'DEAT_DATE': 'Sterbedatum',
  'DEAT_PLAC': 'Sterbeort',
};

/// Native equivalent of webtrees-share's request-review.phtml — one
/// request's before/after field comparison, with a checkbox per field
/// (and note/photo) to select what to accept. Nothing is pre-selected, same
/// as the web page: ticking is how you say "yes, take this".
class ResponseDetailScreen extends ConsumerStatefulWidget {
  const ResponseDetailScreen({super.key, required this.id});

  final int id;

  @override
  ConsumerState<ResponseDetailScreen> createState() =>
      _ResponseDetailScreenState();
}

class _ResponseDetailScreenState extends ConsumerState<ResponseDetailScreen> {
  late Future<Map<String, dynamic>> _future;
  final Set<String> _accepted = {};
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    return client.shareRequestDetail(tree, widget.id);
  }

  Future<void> _apply() async {
    setState(() => _applying = true);

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final accept = {for (final key in _accepted) key: true};

    try {
      final result = await client.shareRequestApply(tree, widget.id, accept);
      if (!mounted) return;

      final nextId = result['nextId'] as int?;
      if (nextId != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ResponseDetailScreen(id: nextId)),
        );
      } else {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alle Antworten geprüft.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _applying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht übernommen werden: $e')),
      );
    }
  }

  Future<void> _delete() async {
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

    if (confirmed != true || !mounted) return;

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      final ok = await client.shareRequestDelete(tree, widget.id);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konnte nicht verworfen werden.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Konnte nicht verworfen werden: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              onBack: () => Navigator.of(context).pop(),
              onDelete: _delete,
            ),
            Expanded(
              child: FutureBuilder<Map<String, dynamic>>(
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

                  return _Body(
                    data: snapshot.data!,
                    accepted: _accepted,
                    applying: _applying,
                    onToggle: (key, value) => setState(() {
                      if (value) {
                        _accepted.add(key);
                      } else {
                        _accepted.remove(key);
                      }
                    }),
                    onApply: _apply,
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

class _Body extends ConsumerWidget {
  const _Body({
    required this.data,
    required this.accepted,
    required this.applying,
    required this.onToggle,
    required this.onApply,
  });

  final Map<String, dynamic> data;
  final Set<String> accepted;
  final bool applying;
  final void Function(String key, bool value) onToggle;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = data['name'] as String? ?? '';
    final responder = data['responder'] as String? ?? '';
    final appliedAlready = data['applied'] as bool? ?? false;
    // The server always sends an object here, but PHP serializes an empty
    // array as JSON "[]" rather than "{}" - defend against that shape too
    // rather than crashing to a blank screen if that ever slips through again.
    final compareRaw = data['compare'];
    final compare = (compareRaw is Map ? compareRaw : {})
        .cast<String, Map<String, dynamic>>();
    final note = data['note'] as String? ?? '';
    final photoUrl = data['photoUrl'] as String? ?? '';

    if (appliedAlready) {
      return _InfoMessage(
        name: name,
        responder: responder,
        text: 'Diese Antwort wurde bereits übernommen.',
      );
    }

    if (compare.isEmpty && note.isEmpty && photoUrl.isEmpty) {
      return _InfoMessage(
        name: name,
        responder: responder,
        text: 'Es wurden keine Änderungen vorgeschlagen.',
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ForLine(name: name, responder: responder),
        const SizedBox(height: 16),
        if (photoUrl.isNotEmpty)
          _CompareCard(
            title: 'Foto übernehmen',
            checked: accepted.contains('photo'),
            onChanged: (v) => onToggle('photo', v),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                photoUrl,
                headers: ref.read(webtreesClientProvider).imageHeaders,
                fit: BoxFit.cover,
              ),
            ),
          ),
        for (final entry in compare.entries)
          _CompareCard(
            title: _fieldLabels[entry.key] ?? entry.key,
            checked: accepted.contains(entry.key),
            onChanged: (v) => onToggle(entry.key, v),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bisher: ${(entry.value['before'] as String?)?.isEmpty ?? true ? '(leer)' : entry.value['before']}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Neu: ${entry.value['after']}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        if (note.isNotEmpty)
          _CompareCard(
            title: 'Als Notiz übernehmen',
            checked: accepted.contains('note'),
            onChanged: (v) => onToggle('note', v),
            child: Text(
              note,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: (applying || accepted.isEmpty) ? null : onApply,
          child: applying
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Ausgewähltes übernehmen'),
        ),
      ],
    );
  }
}

class _CompareCard extends StatelessWidget {
  const _CompareCard({
    required this.title,
    required this.checked,
    required this.onChanged,
    required this.child,
  });

  final String title;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onChanged(!checked),
            child: Row(
              children: [
                Checkbox(
                  value: checked,
                  onChanged: (v) => onChanged(v ?? false),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(padding: const EdgeInsets.only(left: 4), child: child),
        ],
      ),
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({
    required this.name,
    required this.responder,
    required this.text,
  });

  final String name;
  final String responder;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ForLine(name: name, responder: responder),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: AppColors.cardShadow,
            ),
            child: Text(
              text,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ForLine extends StatelessWidget {
  const _ForLine({required this.name, required this.responder});

  final String name;
  final String responder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Für: $name',
          style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
        ),
        if (responder.isNotEmpty)
          Text(
            'Von: $responder',
            style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onBack, required this.onDelete});

  final VoidCallback onBack;
  final VoidCallback onDelete;

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
              'Antwort prüfen',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.textPrimary,
            ),
            tooltip: 'Anfrage verwerfen',
          ),
        ],
      ),
    );
  }
}
