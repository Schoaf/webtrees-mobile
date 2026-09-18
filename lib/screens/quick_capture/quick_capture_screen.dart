import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/quick_note_store.dart';
import '../../state/app_providers.dart';

/// Priority-1 screen per the project plan: log a fact against a person in as
/// few taps as possible. Tries to post straight to webtrees; if that fails
/// (offline, slow venue wifi, server hiccup) it falls back to a local
/// quick-note instead of blocking the user, so nothing said out loud gets
/// lost while waiting for a signal.
class QuickCaptureScreen extends ConsumerStatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  ConsumerState<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends ConsumerState<QuickCaptureScreen> {
  final _personController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _status;

  @override
  void dispose() {
    _personController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final person = _personController.text.trim();
    final text = _noteController.text.trim();
    if (person.isEmpty || text.isEmpty) return;

    setState(() {
      _saving = true;
      _status = null;
    });

    // TODO(phase 5): try posting directly as a webtrees Fact once the person
    // picker resolves to a real xref. For now every quick capture is saved
    // as a local note so nothing is lost, and reconciled by hand later.
    final store = ref.read(quickNoteStoreProvider);
    await store.add(QuickNote(personGuess: person, text: text, createdAt: DateTime.now()));

    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = 'Saved locally — sync it into webtrees later.';
      _personController.clear();
      _noteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick capture')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _personController,
              decoration: const InputDecoration(
                labelText: 'Who is this about?',
                hintText: 'e.g. Andrea Testbauer',
              ),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'What did you learn?',
                hintText: "e.g. birthday is 3 May 1980",
              ),
              minLines: 2,
              maxLines: 4,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.bolt),
              label: const Text('Save'),
            ),
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: 24),
            const _UnsyncedNotesList(),
          ],
        ),
      ),
    );
  }
}

class _UnsyncedNotesList extends ConsumerWidget {
  const _UnsyncedNotesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(quickNoteStoreProvider);
    return FutureBuilder<List<QuickNote>>(
      future: store.unsynced(),
      builder: (context, snapshot) {
        final notes = snapshot.data ?? const [];
        if (notes.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Unsynced (${notes.length})', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final note in notes)
              Card(
                child: ListTile(
                  title: Text(note.personGuess),
                  subtitle: Text(note.text),
                  trailing: Text(
                    '${note.createdAt.hour.toString().padLeft(2, '0')}:${note.createdAt.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
