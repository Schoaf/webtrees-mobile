import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/quick_note_store.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';

/// Result of the sheet: whether a fact was actually posted to webtrees, or
/// only saved locally because the server couldn't be reached.
enum AddFactResult { posted, savedLocally, cancelled }

/// The fast fact-capture flow (originally its own "Quick Capture" screen),
/// now reached from a person's own detail page since every fact needs a
/// person anyway — one less step than picking a person first.
class AddFactSheet extends ConsumerStatefulWidget {
  const AddFactSheet({super.key, required this.xref, required this.personName});

  final String xref;
  final String personName;

  @override
  ConsumerState<AddFactSheet> createState() => _AddFactSheetState();
}

class _AddFactSheetState extends ConsumerState<AddFactSheet> {
  final _valueController = TextEditingController();
  final _dateController = TextEditingController();
  List<Map<String, dynamic>> _tags = [];
  String? _selectedTag;
  bool _loadingTags = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final response = await client.tags(tree, type: 'INDI');
      if (!mounted) return;
      setState(() {
        _tags = (response['data'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        _loadingTags = false;
      });
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Konnte Fakt-Typen nicht laden: $e';
        _loadingTags = false;
      });
    }
  }

  Future<void> _save() async {
    final tag = _selectedTag;
    final value = _valueController.text.trim();
    if (tag == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final result = await client.postFact(
        tree,
        widget.xref,
        tag: tag,
        value: value.isEmpty ? null : value,
        date: _dateController.text.trim().isEmpty
            ? null
            : _dateController.text.trim(),
      );
      if (!mounted) return;
      if (result['ok'] == true) {
        Navigator.of(context).pop(AddFactResult.posted);
      } else {
        // A real rejection (permission, bad date, ...) — surface it, don't
        // silently fall back to a local note that would just hide the problem.
        setState(() {
          _saving = false;
          _error = 'Abgelehnt: ${result['error'] ?? 'unbekannter Fehler'}';
        });
      }
    } on DioException catch (_) {
      // Connectivity problem — fall back to a local note so nothing said
      // out loud gets lost while waiting for a signal.
      final store = ref.read(quickNoteStoreProvider);
      await store.add(
        QuickNote(
          personGuess: widget.personName,
          xref: widget.xref,
          text:
              '${_tagLabel(tag)}: $value${_dateController.text.trim().isEmpty ? '' : ' (${_dateController.text.trim()})'}',
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(AddFactResult.savedLocally);
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Verbindung fehlgeschlagen: $e';
      });
    }
  }

  String _tagLabel(String tag) {
    for (final t in _tags) {
      if (t['tag'] == tag) return t['label'] as String? ?? tag;
    }
    return tag;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Fakt hinzufügen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  widget.personName,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (_loadingTags)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final tag in _tags)
                        ChoiceChip(
                          label: Text(
                            tag['label'] as String? ?? tag['tag'] as String,
                          ),
                          selected: _selectedTag == tag['tag'],
                          onSelected: (_) => setState(
                            () => _selectedTag = tag['tag'] as String,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _valueController,
                  decoration: const InputDecoration(
                    labelText: 'Wert',
                    hintText: 'z. B. Bäckerin',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                if (_selectedTag != null) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _dateController,
                    decoration: const InputDecoration(
                      labelText: 'Datum (optional)',
                      hintText: 'z. B. 3 MAI 1980',
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _selectedTag == null || _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Speichern'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
