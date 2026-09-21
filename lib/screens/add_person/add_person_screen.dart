import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../utils/gedcom_date.dart';
import '../../widgets/place_autocomplete_field.dart';

const _relationLabels = {
  'child': 'als Kind',
  'spouse': 'als Ehepartner:in',
  'father': 'als Vater',
  'mother': 'als Mutter',
};

const _extraFieldTags = {
  'Beruf': 'OCCU',
  'Konfession': 'RELI',
  'Wohnort': 'RESI',
  'Spitzname': 'FACT',
  'Notiz': 'NOTE',
};

class _ExtraField {
  _ExtraField()
    : id =
          DateTime.now().microsecondsSinceEpoch.toString() +
          (_counter++).toString();
  static int _counter = 0;
  final String id;
  String property = _extraFieldTags.keys.first;
  final valueController = TextEditingController();
}

class AddPersonScreen extends ConsumerStatefulWidget {
  const AddPersonScreen({super.key});

  @override
  ConsumerState<AddPersonScreen> createState() => _AddPersonScreenState();
}

class _AddPersonScreenState extends ConsumerState<AddPersonScreen> {
  final _givenController = TextEditingController();
  final _surnameController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _birthPlaceController = TextEditingController();
  final _relativeQueryController = TextEditingController();

  String _sex = 'M';
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  Map<String, dynamic>? _selectedRelative;
  String _relation = 'none';

  final List<_ExtraField> _extraFields = [];

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _givenController.dispose();
    _surnameController.dispose();
    _birthDateController.dispose();
    _birthPlaceController.dispose();
    _relativeQueryController.dispose();
    for (final field in _extraFields) {
      field.valueController.dispose();
    }
    super.dispose();
  }

  void _onRelativeQueryChanged(String query) {
    setState(() {
      _selectedRelative = null;
      _relation = 'none';
    });
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
        setState(
          () => _suggestions = (response['data'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
      } on Exception {
        // best-effort — leave suggestions as-is
      }
    });
  }

  Future<void> _save({required bool addAnother}) async {
    final given = _givenController.text.trim();
    final surname = _surnameController.text.trim();
    if (given.isEmpty && surname.isEmpty) {
      setState(() => _error = 'Bitte Vor- oder Nachname angeben.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);

    try {
      final result = await client.postAddIndividual(
        tree,
        relation: _relation,
        relativeTo: _selectedRelative?['xref'] as String?,
        given: given,
        surname: surname,
        sex: _sex,
        birthDate: _birthDateController.text.trim().isEmpty
            ? null
            : _birthDateController.text.trim(),
        birthPlace: _birthPlaceController.text.trim().isEmpty
            ? null
            : _birthPlaceController.text.trim(),
      );

      if (result['ok'] != true) {
        setState(() {
          _saving = false;
          _error = 'Abgelehnt: ${result['error'] ?? 'unbekannter Fehler'}';
        });
        return;
      }

      final newXref = result['xref'] as String;
      for (final field in _extraFields) {
        final value = field.valueController.text.trim();
        if (value.isEmpty) continue;
        await client.postFact(
          tree,
          newXref,
          tag: _extraFieldTags[field.property]!,
          value: value,
        );
      }

      if (!mounted) return;
      if (addAnother) {
        setState(() {
          _saving = false;
          _givenController.clear();
          _surnameController.clear();
          _birthDateController.clear();
          _birthPlaceController.clear();
          _relativeQueryController.clear();
          _selectedRelative = null;
          _relation = 'none';
          for (final field in _extraFields) {
            field.valueController.dispose();
          }
          _extraFields.clear();
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Person gespeichert.')));
      } else {
        _returnToStart(success: true);
      }
    } on Exception catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Verbindung fehlgeschlagen: $e';
      });
    }
  }

  /// Both "Abbrechen" and a successful save need to leave this screen —
  /// but when it's the embedded "Neu" tab (not pushed via Navigator), there's
  /// nothing to pop, so switch the bottom nav back to Start instead.
  void _returnToStart({bool success = false}) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(success);
    } else {
      ref.read(selectedTabProvider.notifier).select(0);
      if (success) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Person gespeichert.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: AppColors.cardShadow,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 90,
                    child: TextButton(
                      onPressed: _returnToStart,
                      child: const Text('Abbrechen'),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Person hinzufügen',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 90),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _givenController,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Vorname',
                            hintText: 'Max',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _surnameController,
                          decoration: const InputDecoration(
                            labelText: 'Nachname',
                            hintText: 'Scharf',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SexPicker(
                    value: _sex,
                    onChanged: (v) => setState(() => _sex = v),
                  ),
                  const SizedBox(height: 18),
                  _BirthDatePicker(controller: _birthDateController),
                  const SizedBox(height: 18),
                  PlaceAutocompleteField(
                    controller: _birthPlaceController,
                    labelText: 'Geburtsort',
                    hintText: 'z. B. Wien',
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Verknüpft mit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _relativeQueryController,
                    onChanged: _onRelativeQueryChanged,
                    decoration: const InputDecoration(
                      hintText: 'Person suchen (optional)',
                    ),
                  ),
                  for (final person in _suggestions)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(person['name'] as String? ?? ''),
                      subtitle: Text(person['lifespan'] as String? ?? ''),
                      onTap: () => setState(() {
                        _selectedRelative = person;
                        _relativeQueryController.text =
                            person['name'] as String? ?? '';
                        _suggestions = [];
                        _relation = 'child';
                      }),
                    ),
                  if (_selectedRelative != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in _relationLabels.entries)
                          ChoiceChip(
                            label: Text(entry.value),
                            selected: _relation == entry.key,
                            onSelected: (_) =>
                                setState(() => _relation = entry.key),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                  for (final field in _extraFields)
                    _ExtraFieldRow(
                      field: field,
                      onRemove: () =>
                          setState(() => _extraFields.remove(field)),
                    ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _extraFields.add(_ExtraField())),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Weitere Angabe hinzufügen'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                children: [
                  FilledButton(
                    onPressed: _saving ? null : () => _save(addAnother: false),
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
                  TextButton(
                    onPressed: _saving ? null : () => _save(addAnother: true),
                    child: const Text('Speichern & weitere Person hinzufügen'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Same "always a picker, never free-text" convention as the person-detail
/// edit form's [GedcomDateField], but this screen sends the birth date to
/// postAddIndividual as "TT.MM.JJJJ" rather than GEDCOM syntax, so it needs
/// its own converter pair rather than reusing that widget directly.
class _BirthDatePicker extends StatefulWidget {
  const _BirthDatePicker({required this.controller});

  final TextEditingController controller;

  @override
  State<_BirthDatePicker> createState() => _BirthDatePickerState();
}

class _BirthDatePickerState extends State<_BirthDatePicker> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() => setState(() {});

  Future<void> _pickDate() async {
    final parsed = germanDdMmYyyyToDateTime(widget.controller.text);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1500),
      lastDate: DateTime(now.year + 100),
      helpText: 'Geburtsdatum',
      cancelText: 'Abbrechen',
      confirmText: 'Übernehmen',
    );
    if (picked != null) {
      widget.controller.text = dateTimeToGermanDdMmYyyy(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final raw = widget.controller.text;

    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: _pickDate,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Geburtsdatum',
          suffixIcon: raw.isEmpty
              ? const Icon(Icons.calendar_today_outlined)
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Datum entfernen',
                  onPressed: () => setState(() => widget.controller.clear()),
                ),
        ),
        child: Text(
          raw.isEmpty ? 'TT.MM.JJJJ' : raw,
          style: raw.isEmpty
              ? TextStyle(color: Theme.of(context).hintColor)
              : null,
        ),
      ),
    );
  }
}

class _SexPicker extends StatelessWidget {
  const _SexPicker({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [('M', 'männlich'), ('F', 'weiblich'), ('X', 'divers')];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Geschlecht',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.textTertiary),
          ),
          child: Row(
            children: [
              for (var i = 0; i < options.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(options[i].$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: value == options[i].$1
                            ? AppColors.maleAvatarFg.withValues(alpha: 0.16)
                            : Colors.transparent,
                        border: i < options.length - 1
                            ? const Border(
                                right: BorderSide(
                                  color: AppColors.textTertiary,
                                ),
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        options[i].$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: value == options[i].$1
                              ? FontWeight.w500
                              : FontWeight.w400,
                          color: value == options[i].$1
                              ? AppColors.maleAvatarFg
                              : AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExtraFieldRow extends StatefulWidget {
  const _ExtraFieldRow({required this.field, required this.onRemove});

  final _ExtraField field;
  final VoidCallback onRemove;

  @override
  State<_ExtraFieldRow> createState() => _ExtraFieldRowState();
}

class _ExtraFieldRowState extends State<_ExtraFieldRow> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: widget.field.property,
              decoration: const InputDecoration(labelText: 'Eigenschaft'),
              items: [
                for (final key in _extraFieldTags.keys)
                  DropdownMenuItem(value: key, child: Text(key)),
              ],
              onChanged: (v) => setState(() => widget.field.property = v!),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.field.valueController,
              decoration: const InputDecoration(
                labelText: 'Wert',
                hintText: '…',
              ),
            ),
          ),
          IconButton(
            onPressed: widget.onRemove,
            icon: const Icon(Icons.close, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}
