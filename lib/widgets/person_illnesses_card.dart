import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_localizations.dart';
import '../services/diagnostic_log.dart';
import '../state/app_providers.dart';
import '../theme/app_theme.dart';

/// A person's illnesses on their page (#54). They are confidential facts, so webtrees - and with it the person's
/// facts - leaves them out; the family-health module hands out the ones its own rule lets the account see. Shows
/// nothing without the module, without illnesses, or when loading fails. An editor taps a row to change or delete it.
/// Give it a key with [xref] in it: it loads once.
class PersonIllnessesCard extends ConsumerStatefulWidget {
  const PersonIllnessesCard({super.key, required this.xref});

  final String xref;

  @override
  ConsumerState<PersonIllnessesCard> createState() => _PersonIllnessesCardState();
}

class _PersonIllnessesCardState extends ConsumerState<PersonIllnessesCard> {
  List<Map<String, dynamic>> _illnesses = [];
  bool _canEdit = false;

  /// A relative who does not take part: shown as such, so no illness does not read as healthy.
  bool _isOptedOut = false;

  /// Asked once the server says it has the module - another person gets a new card (see its key on the page).
  bool _hasRequested = false;

  Future<void> _load() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    try {
      final response = await client.familyHealthPersonIllnesses(tree, widget.xref);
      if (!mounted) return;
      setState(() {
        _illnesses = (response['illnesses'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
        _canEdit = response['canEdit'] as bool? ?? false;
        _isOptedOut = response['isOptedOut'] as bool? ?? false;
      });
    } on Exception catch (error, stackTrace) {
      // An older module without PersonIllnesses, or no connection: the card stays away.
      DiagnosticLog.instance.error('person_illnesses_card', error, stackTrace);
      if (mounted) setState(() => _illnesses = []);
    }
  }

  Future<void> _edit(Map<String, dynamic> illness) async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => IllnessEditSheet(xref: widget.xref, illness: illness),
    );
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final hasFamilyHealth = ref.watch(availableModulesProvider).value?.contains(familyHealthModule) == true;
    if (hasFamilyHealth && !_hasRequested) {
      _hasRequested = true;
      _load();
    }
    if (!hasFamilyHealth || (_illnesses.isEmpty && !_isOptedOut)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            children: [
              Text(
                l10n.illnessesTitle,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: l10n.illnessConfidentialHint,
                child: const Icon(Icons.lock_outline, size: 14, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        Container(
          key: const Key('personIllnesses'),
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppColors.cardShadow,
          ),
          child: Column(
            children: [
              if (_isOptedOut)
                Padding(
                  key: const Key('personIllnessesOptedOut'),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 18, color: AppColors.textTertiary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(l10n.familyHealthPersonOptedOut, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
              for (var i = 0; i < _illnesses.length; i++)
                InkWell(
                  onTap: _canEdit ? () => _edit(_illnesses[i]) : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: i == _illnesses.length - 1
                        ? null
                        : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
                    child: _IllnessRow(illness: _illnesses[i], canEdit: _canEdit),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IllnessRow extends StatelessWidget {
  const _IllnessRow({required this.illness, required this.canEdit});

  final Map<String, dynamic> illness;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final name = illness['illness'] as String? ?? '';
    final dateText = illness['dateText'] as String? ?? '';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
              if (illness['isPending'] == true)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.schedule, size: 12, color: AppColors.pending),
                      const SizedBox(width: 4),
                      Text(l10n.pendingApprovalLabel, style: const TextStyle(fontSize: 11, color: AppColors.pending)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (dateText.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(dateText, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ),
        if (canEdit)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textTertiary),
          ),
      ],
    );
  }
}

/// Changes the name and the year of an illness, or deletes it. Pops with the message to show, null when nothing
/// changed.
class IllnessEditSheet extends ConsumerStatefulWidget {
  const IllnessEditSheet({super.key, required this.xref, required this.illness});

  final String xref;
  final Map<String, dynamic> illness;

  @override
  ConsumerState<IllnessEditSheet> createState() => _IllnessEditSheetState();
}

class _IllnessEditSheetState extends ConsumerState<IllnessEditSheet> {
  late final _nameController = TextEditingController(text: widget.illness['illness'] as String? ?? '');

  /// The year as entered when the illness was recorded; a full date or "ABT 1975" stays as it is unless the year
  /// is changed.
  late final String _originalDate = widget.illness['date'] as String? ?? '';
  late final String _originalYear = RegExp(r'\b[0-9]{3,4}\b').firstMatch(_originalDate)?.group(0) ?? '';
  late final _yearController = TextEditingController(text: _originalYear);
  bool _isSaving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  String get _id => widget.illness['id'] as String? ?? '';

  Future<void> _run(Future<Map<String, dynamic>> Function() request, String message) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final result = await request();
      if (!mounted) return;
      if (result['ok'] == true) {
        Navigator.of(context).pop(message);
      } else {
        setState(() {
          _isSaving = false;
          _error = l10n.rejectedError((result['error'] as String?) ?? l10n.unknownError);
        });
      }
    } on Exception catch (error, stackTrace) {
      DiagnosticLog.instance.error('person_illnesses_card', error, stackTrace);
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = l10n.connectionFailedError('$error');
      });
    }
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final year = _yearController.text.trim();
    if (year.isNotEmpty && year != _originalYear && !RegExp(r'^[0-9]{3,4}$').hasMatch(year)) {
      setState(() => _error = l10n.illnessYearInvalid);
      return;
    }
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    await _run(
      () => client.postFamilyHealthIllnessUpdate(
        tree,
        widget.xref,
        id: _id,
        illness: _nameController.text.trim(),
        date: year == _originalYear ? _originalDate : year,
      ),
      l10n.factSaved,
    );
  }

  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteIllnessConfirm(widget.illness['illness'] as String? ?? '')),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
          TextButton(
            key: const Key('illnessDeleteConfirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.deleteIllnessButton),
          ),
        ],
      ),
    );
    if (isConfirmed != true || !mounted) return;
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    await _run(() => client.postFamilyHealthIllnessDelete(tree, widget.xref, id: _id), l10n.illnessDeleted);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canSave = !_isSaving && _nameController.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(l10n.editIllnessTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              key: const Key('illnessEditName'),
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.illnessLabel),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('illnessEditYear'),
              controller: _yearController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              decoration: InputDecoration(
                labelText: l10n.illnessYearLabel,
                counterText: '',
                // "ABT 1975", a full date ...: kept while the year stays the same.
                helperText: _originalDate.isNotEmpty && _originalDate != _originalYear
                    ? widget.illness['dateText'] as String? ?? _originalDate
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('illnessEditSave'),
              onPressed: canSave ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l10n.save),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              key: const Key('illnessEditDelete'),
              onPressed: _isSaving ? null : _delete,
              icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              label: Text(l10n.deleteIllnessButton, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
