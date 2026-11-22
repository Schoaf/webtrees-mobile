import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../repositories/quick_note_store.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';
import 'gedcom_date_field.dart';
import 'place_autocomplete_field.dart';
import '../services/diagnostic_log.dart';

/// Result of the sheet: whether a fact was actually posted to webtrees, or
/// only saved locally because the server couldn't be reached.
enum AddFactResult { posted, savedLocally, cancelled }

/// Record/bookkeeping tags the server's tag list (client.tags) returns
/// unfiltered along with every real, addable fact type - RIN
/// ("Datensatz-ID"), CHAN ("Aktualisiert am"), SOUR ("Quellenangabe") and
/// REFN aren't something a person adds by hand any more than they're
/// something they edit by hand. This is a different data source from a
/// person's own facts (the server's whole tag catalog, not what that
/// person actually has), so it needs its own copy of the exclusion - see
/// person_detail_screen.dart's build(), which drops CHAN from a person's
/// own facts instead, and _nonEditableFactTags there for RIN/SOUR/REFN.
const _nonAddableFactTags = {'RIN', 'CHAN', 'SOUR', 'REFN'};

/// The chip for an illness (#54) - not a GEDCOM tag: the family-health module writes the fact itself.
const _illnessChip = '_family-health_';

/// How many catalog names are suggested at once while typing an illness.
const _maxIllnessSuggestions = 6;

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
  final _placeController = TextEditingController();
  final _illnessController = TextEditingController();
  final _yearController = TextEditingController();
  List<Map<String, dynamic>> _tags = [];
  String? _selectedTag;
  bool _loadingTags = true;
  bool _saving = false;
  String? _error;

  // Illness (#54): the module's catalog, loaded when the chip is picked.
  List<({String name, String category})> _catalog = [];
  Map<String, String> _categories = {};
  String? _illnessCategory;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _dateController.dispose();
    _placeController.dispose();
    _illnessController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final response = await client.tags(tree, type: 'INDI');
      if (!mounted) return;
      setState(() {
        _tags = (response['data'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>()
            .where((t) => !_nonAddableFactTags.contains(t['tag']))
            .toList();
        _loadingTags = false;
      });
    } on Exception catch (e, stackTrace) {
      DiagnosticLog.instance.error('add_fact_sheet', e, stackTrace);
      if (!mounted) return;
      setState(() {
        _error = AppLocalizations.of(context)!.couldNotLoadFactTypesError('$e');
        _loadingTags = false;
      });
    }
  }

  Future<void> _loadCatalog() async {
    if (_categories.isNotEmpty) return;
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final response = await client.familyHealthCatalog(tree);
      if (!mounted) return;
      setState(() {
        _categories = {
          for (final c in (response['categories'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
            c['id'] as String: c['name'] as String? ?? '',
        };
        _catalog = [
          for (final i in (response['illnesses'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
            (name: i['name'] as String? ?? '', category: i['category'] as String? ?? ''),
        ];
      });
    } on Exception catch (error, stackTrace) {
      DiagnosticLog.instance.error('add_fact_sheet', error, stackTrace);
      // Suggestions are best-effort - a name can still be typed.
    }
  }

  /// The catalog entry for the typed name, ignoring case - null for a new name.
  ({String name, String category})? get _knownIllness {
    final typed = _illnessController.text.trim().toLowerCase();
    return _catalog.where((i) => i.name.toLowerCase() == typed).firstOrNull;
  }

  List<String> get _illnessSuggestions {
    final typed = _illnessController.text.trim().toLowerCase();
    if (typed.isEmpty || _knownIllness != null) return const [];
    return _catalog.where((i) => i.name.toLowerCase().contains(typed)).take(_maxIllnessSuggestions).map((i) => i.name).toList();
  }

  Future<void> _saveIllness() async {
    final l10n = AppLocalizations.of(context)!;
    final year = _yearController.text.trim();
    if (year.isNotEmpty && !RegExp(r'^[0-9]{3,4}$').hasMatch(year)) {
      setState(() => _error = l10n.illnessYearInvalid);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final result = await client.postFamilyHealthIllness(
        tree,
        widget.xref,
        illness: _illnessController.text.trim(),
        date: year.isEmpty ? null : year,
        category: _knownIllness == null ? _illnessCategory : null,
      );
      if (!mounted) return;
      if (result['ok'] == true) {
        Navigator.of(context).pop(AddFactResult.posted);
      } else {
        setState(() {
          _saving = false;
          _error = l10n.rejectedError((result['error'] as String?) ?? l10n.unknownError);
        });
      }
    } on Exception catch (e, stackTrace) {
      DiagnosticLog.instance.error('add_fact_sheet', e, stackTrace);
      // No local note to fall back on: health data stays off the phone.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.connectionFailedError('$e');
      });
    }
  }

  /// An event (birth, death, baptism ...) has a place, an attribute
  /// (occupation, religion ...) a value of its own.
  bool _isEvent(String tag) => _tags.any((t) => t['tag'] == tag && t['isEvent'] == true);

  Future<void> _save() async {
    final tag = _selectedTag;
    if (tag == null) return;
    if (tag == _illnessChip) return _saveIllness();
    final isEvent = _isEvent(tag);
    final value = isEvent ? '' : _valueController.text.trim();
    final place = isEvent ? _placeController.text.trim() : '';
    final l10n = AppLocalizations.of(context)!;

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
        place: place.isEmpty ? null : place,
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
          _error = l10n.rejectedError(
            (result['error'] as String?) ?? l10n.unknownError,
          );
        });
      }
    } on DioException catch (error, stackTrace) {
      DiagnosticLog.instance.error('add_fact_sheet', error, stackTrace);
      // Connectivity problem — fall back to a local note so nothing said
      // out loud gets lost while waiting for a signal.
      final store = ref.read(quickNoteStoreProvider);
      await store.add(
        QuickNote(
          personGuess: widget.personName,
          xref: widget.xref,
          text:
              '${_tagLabel(tag)}: ${isEvent ? place : value}${_dateController.text.trim().isEmpty ? '' : ' (${_dateController.text.trim()})'}',
          createdAt: DateTime.now(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(AddFactResult.savedLocally);
    } on Exception catch (e, stackTrace) {
      DiagnosticLog.instance.error('add_fact_sheet', e, stackTrace);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = l10n.connectionFailedError('$e');
      });
    }
  }

  String _tagLabel(String tag) {
    for (final t in _tags) {
      if (t['tag'] == tag) return t['label'] as String? ?? tag;
    }
    return tag;
  }

  List<Widget> _illnessFields(AppLocalizations l10n) {
    final known = _knownIllness;
    final isNew = _illnessController.text.trim().isNotEmpty && known == null;
    return [
      TextField(
        key: const Key('illnessName'),
        controller: _illnessController,
        onChanged: (_) => setState(() {}),
        maxLength: 120,
        decoration: InputDecoration(labelText: l10n.illnessLabel, counterText: ''),
      ),
      for (final name in _illnessSuggestions)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.healing_outlined, size: 18, color: AppColors.textTertiary),
          title: Text(name),
          onTap: () => setState(() => _illnessController.text = name),
        ),
      if (known != null && _categories[known.category] != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _categories[known.category]!,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ),
      if (isNew && _categories.isNotEmpty) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('illnessCategory'),
          initialValue: _illnessCategory,
          decoration: InputDecoration(labelText: l10n.illnessCategoryLabel, helperText: l10n.illnessCategoryHint, helperMaxLines: 3),
          items: [
            for (final entry in _categories.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          ],
          onChanged: (value) => setState(() => _illnessCategory = value),
        ),
      ],
      const SizedBox(height: 12),
      TextField(
        key: const Key('illnessYear'),
        controller: _yearController,
        keyboardType: TextInputType.number,
        maxLength: 4,
        decoration: InputDecoration(labelText: l10n.illnessYearLabel, counterText: ''),
      ),
      const SizedBox(height: 12),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 16, color: AppColors.textTertiary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(l10n.illnessConfidentialHint, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
        ],
      ),
    ];
  }

  bool get _canSave =>
      _selectedTag != null && !_saving && (_selectedTag != _illnessChip || _illnessController.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Only when the server says it has family-health (#54).
    final hasFamilyHealth = ref.watch(availableModulesProvider).value?.contains(familyHealthModule) == true;
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
                  l10n.addFactLabel,
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
                      if (hasFamilyHealth)
                        ChoiceChip(
                          key: const Key('illnessChip'),
                          avatar: const Icon(Icons.health_and_safety_outlined, size: 18),
                          label: Text(l10n.illnessLabel),
                          selected: _selectedTag == _illnessChip,
                          onSelected: (_) {
                            setState(() => _selectedTag = _illnessChip);
                            _loadCatalog();
                          },
                        ),
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
                if (_selectedTag == _illnessChip) ...[
                  const SizedBox(height: 16),
                  ..._illnessFields(l10n),
                ] else if (_selectedTag != null) ...[
                  const SizedBox(height: 16),
                  if (_isEvent(_selectedTag!))
                    PlaceAutocompleteField(
                      controller: _placeController,
                      labelText: l10n.placeOptionalLabel,
                    )
                  else
                    // Named like the fact: "Beruf", "Religion" ...
                    TextField(
                      controller: _valueController,
                      decoration: InputDecoration(
                        labelText: _tagLabel(_selectedTag!),
                        hintText: _selectedTag == 'OCCU' ? l10n.factValueHint : null,
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  const SizedBox(height: 12),
                  GedcomDateField(
                    controller: _dateController,
                    labelText: l10n.dateOptionalLabel,
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _canSave ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(l10n.save),
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
