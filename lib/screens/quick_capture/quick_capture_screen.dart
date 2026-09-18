import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/quick_note_store.dart';
import '../../state/app_providers.dart';

/// Priority-1 screen per the project plan: log a fact against a person in as
/// few taps as possible. Posts straight to webtrees when a person and fact
/// type are picked; if that fails for a *connectivity* reason (offline,
/// slow venue wifi, timeout) it falls back to a local quick-note instead of
/// blocking the user. A real rejection from the server (no permission, bad
/// date, etc.) is shown as-is — retrying locally wouldn't fix that.
class QuickCaptureScreen extends ConsumerStatefulWidget {
  const QuickCaptureScreen({super.key});

  @override
  ConsumerState<QuickCaptureScreen> createState() => _QuickCaptureScreenState();
}

class _QuickCaptureScreenState extends ConsumerState<QuickCaptureScreen> {
  final _personController = TextEditingController();
  final _valueController = TextEditingController();
  final _dateController = TextEditingController();

  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _selectedPerson; // {xref, name, ...}

  List<Map<String, dynamic>> _tags = [];
  String? _selectedTag;

  bool _saving = false;
  String? _status;
  bool _statusIsError = false;
  int? _reconcilingNoteId;

  @override
  void dispose() {
    _debounce?.cancel();
    _personController.dispose();
    _valueController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  void _onPersonQueryChanged(String query) {
    setState(() => _selectedPerson = null);
    _debounce?.cancel();
    if (query.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final client = ref.read(webtreesClientProvider);
      final tree = ref.read(treeNameProvider);
      try {
        final response = await client.individuals(tree, query: query);
        if (!mounted) return;
        setState(() {
          _suggestions = (response['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        });
      } on Exception {
        // search is best-effort — leave suggestions as-is on failure
      }
    });
  }

  Future<void> _selectPerson(Map<String, dynamic> person) async {
    setState(() {
      _selectedPerson = person;
      _suggestions = [];
      _personController.text = person['name'] as String? ?? '';
      _tags = [];
      _selectedTag = null;
    });

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final response = await client.tags(tree, type: 'INDI');
      if (!mounted) return;
      setState(() {
        _tags = (response['data'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      });
    } on Exception {
      // fact-type list is a convenience — the free-text value field still works without it
    }
  }

  Future<void> _save() async {
    final value = _valueController.text.trim();
    if (value.isEmpty) return;

    setState(() {
      _saving = true;
      _status = null;
    });

    final person = _selectedPerson;
    final tag = _selectedTag;

    if (person != null && tag != null) {
      final client = ref.read(webtreesClientProvider);
      final tree = ref.read(treeNameProvider);
      try {
        final result = await client.postFact(
          tree,
          person['xref'] as String,
          tag: tag,
          value: value,
          date: _dateController.text.trim().isEmpty ? null : _dateController.text.trim(),
        );
        if (!mounted) return;

        if (result['ok'] == true) {
          final pending = result['pending'] == true;
          if (_reconcilingNoteId != null) {
            await ref.read(quickNoteStoreProvider).markSynced(_reconcilingNoteId!);
          }
          setState(() {
            _saving = false;
            _statusIsError = false;
            _status = pending
                ? 'Sent — waiting for a moderator to approve it.'
                : 'Saved to ${person['name']}\'s record.';
          });
          _resetForm();
        } else {
          // A real rejection (permission, bad date, ...) — surface it, don't
          // silently fall back to a local note that would just hide the problem.
          setState(() {
            _saving = false;
            _statusIsError = true;
            _status = 'webtrees rejected this: ${result['error'] ?? 'unknown error'}';
          });
        }
        return;
      } on DioException {
        // Connectivity problem — fall through to the local-note fallback below.
      }
    }

    await _saveLocalNote(person?['name'] as String? ?? _personController.text.trim(), value);
  }

  Future<void> _saveLocalNote(String personGuess, String text) async {
    if (personGuess.isEmpty) {
      setState(() {
        _saving = false;
        _statusIsError = true;
        _status = 'Enter who this is about first.';
      });
      return;
    }

    final store = ref.read(quickNoteStoreProvider);
    await store.add(QuickNote(personGuess: personGuess, text: text, createdAt: DateTime.now()));

    if (!mounted) return;
    setState(() {
      _saving = false;
      _statusIsError = false;
      _status = "Couldn't reach webtrees — saved locally, sync it in later.";
    });
    _resetForm();
    setState(() {}); // refresh the unsynced-notes list below
  }

  void _resetForm() {
    _personController.clear();
    _valueController.clear();
    _dateController.clear();
    _selectedPerson = null;
    _selectedTag = null;
    _tags = [];
    _reconcilingNoteId = null;
  }

  /// Tapping an unsynced note pre-fills the form so the user can pick the
  /// real person/fact type and finish structuring it; the note is marked
  /// synced once it's actually been posted successfully (see [_save]).
  void _reconcile(QuickNote note) {
    setState(() {
      _personController.text = note.personGuess;
      _valueController.text = note.text;
      _selectedPerson = null;
      _suggestions = [];
      _reconcilingNoteId = note.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quick capture')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _personController,
            decoration: const InputDecoration(
              labelText: 'Who is this about?',
              hintText: 'Start typing a name…',
            ),
            onChanged: _onPersonQueryChanged,
          ),
          for (final person in _suggestions)
            ListTile(
              dense: true,
              title: Text(person['name'] as String? ?? ''),
              subtitle: Text(person['lifespan'] as String? ?? ''),
              onTap: () => _selectPerson(person),
            ),
          if (_selectedPerson != null && _tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in _tags)
                  ChoiceChip(
                    label: Text(tag['label'] as String? ?? tag['tag'] as String),
                    selected: _selectedTag == tag['tag'],
                    onSelected: (_) => setState(() => _selectedTag = tag['tag'] as String),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _valueController,
            decoration: const InputDecoration(
              labelText: 'What did you learn?',
              hintText: "e.g. 3 MAY 1980, or a free-text note",
            ),
            minLines: 1,
            maxLines: 3,
          ),
          if (_selectedPerson != null && _selectedTag != null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _dateController,
              decoration: const InputDecoration(
                labelText: 'Date (optional)',
                hintText: 'e.g. 3 MAY 1980',
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.bolt),
            label: const Text('Save'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(
              _status!,
              style: TextStyle(color: _statusIsError ? Theme.of(context).colorScheme.error : null),
            ),
          ],
          const SizedBox(height: 24),
          _UnsyncedNotesList(onTapNote: _reconcile),
        ],
      ),
    );
  }
}

class _UnsyncedNotesList extends ConsumerWidget {
  const _UnsyncedNotesList({required this.onTapNote});

  final void Function(QuickNote note) onTapNote;

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
                  onTap: () => onTapNote(note),
                ),
              ),
          ],
        );
      },
    );
  }
}
