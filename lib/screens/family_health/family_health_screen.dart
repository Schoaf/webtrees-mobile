import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_providers.dart';
import '../../state/family_health_overlay.dart';
import '../../theme/app_theme.dart';
import '../../utils/tab_navigation.dart';
import '../../widgets/tablet_bounded_body.dart';

/// "Familiengesundheit" (#54): the family history from the server's family-health module - for the account's own
/// individual or one of its children under 18, the relatives' illnesses grouped by category, with relationship,
/// degree and age at diagnosis; early onset marked. A filter bar limits it to one category.
///
/// Who appears is decided by the module alone (blood relatives only); the app shows what it gets.
class FamilyHealthScreen extends ConsumerStatefulWidget {
  const FamilyHealthScreen({super.key});

  @override
  ConsumerState<FamilyHealthScreen> createState() => _FamilyHealthScreenState();
}

class _FamilyHealthScreenState extends ConsumerState<FamilyHealthScreen> {
  late Future<_History> _future;

  /// The individual whose history is shown - null for the module's default (your own).
  String? _xref;

  /// The category the filter bar shows - null for all.
  String? _category;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_History> _load() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final (history, catalog) = await (
      client.familyHistory(tree, xref: _xref),
      client.familyHealthCatalog(tree),
    ).wait;
    return _History.fromJson(history, catalog);
  }

  bool _isOpeningTree = false;

  /// The tree with everyone without an illness faded (#54), from [xref] - every illness the account may see, not
  /// only this history's: the person's own too.
  Future<void> _showInTree(String? xref, String? category) async {
    if (xref == null) return;
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isOpeningTree = true);
    try {
      final (illnesses, catalog) = await (client.familyHealthIllnesses(tree), client.familyHealthCatalog(tree)).wait;
      if (!mounted) return;
      ref.read(familyHealthOverlayProvider.notifier).show(FamilyHealthOverlay.fromJson(illnesses, catalog).withCategory(category));
      openTreeView(context, xref);
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.couldNotLoad('$error'))));
    } finally {
      if (mounted) setState(() => _isOpeningTree = false);
    }
  }

  void _showSubject(String xref) => setState(() {
    _xref = xref;
    _future = _load();
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: SafeArea(
        child: TabletBoundedBody(
          child: Column(
            children: [
              _Header(onBack: () => Navigator.of(context).pop()),
              Expanded(
                child: FutureBuilder<_History>(
                  future: _future,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(l10n.couldNotLoad('${snapshot.error}')),
                      );
                    }
                    return _body(context, snapshot.data!);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _History history) {
    final l10n = AppLocalizations.of(context)!;

    if (history.subjects.isEmpty) {
      return _Message(l10n.familyHealthNotLinked);
    }

    final used = [
      for (final id in history.categories.keys)
        if (history.illnesses.any((i) => i.category == id)) id,
    ];
    final category = used.contains(_category) ? _category : null;
    final shown = [
      for (final illness in history.illnesses)
        if (category == null || illness.category == category) illness,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (history.subjects.length > 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final subject in history.subjects)
                ChoiceChip(
                  label: Text(subject.name),
                  selected: subject.xref == history.xref,
                  onSelected: (_) => _showSubject(subject.xref),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (used.isNotEmpty) ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: l10n.allCategories,
                  isSelected: category == null,
                  onTap: () => setState(() => _category = null),
                ),
                for (final id in used)
                  _FilterChip(
                    label: history.categories[id] ?? id,
                    isSelected: category == id,
                    onTap: () => setState(() => _category = id),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _isOpeningTree ? null : () => _showInTree(history.xref, category),
            icon: const Icon(Icons.account_tree_outlined),
            label: Text(l10n.familyHealthShowInTree),
          ),
        ),
        if (shown.isEmpty) _Message(l10n.familyHealthNoIllnesses),
        for (final id in history.categories.keys)
          if (shown.any((i) => i.category == id)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                history.categories[id]!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            _Card(
              children: [
                for (final illness in shown)
                  if (illness.category == id) _IllnessRow(illness: illness),
              ],
            ),
          ],
        if (history.earlyAge > 0 && shown.any((i) => i.isEarly))
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
            child: Text(
              l10n.earlyOnsetExplained(history.earlyAge),
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ),
      ],
    );
  }
}

class _History {
  const _History({
    required this.subjects,
    required this.xref,
    required this.earlyAge,
    required this.illnesses,
    required this.categories,
  });

  factory _History.fromJson(
    Map<String, dynamic> history,
    Map<String, dynamic> catalog,
  ) => _History(
    subjects: [
      for (final s
          in (history['subjects'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>())
        (xref: s['xref'] as String, name: s['name'] as String? ?? ''),
    ],
    xref: history['xref'] as String?,
    earlyAge: history['earlyAge'] as int? ?? 0,
    illnesses: [
      for (final i
          in (history['illnesses'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>())
        _Illness.fromJson(i),
    ],
    // In the module's order - the order of the groups.
    categories: {
      for (final c
          in (catalog['categories'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>())
        c['id'] as String: c['name'] as String? ?? '',
    },
  );

  final List<({String xref, String name})> subjects;
  final String? xref;
  final int earlyAge;
  final List<_Illness> illnesses;
  final Map<String, String> categories;
}

class _Illness {
  const _Illness({
    required this.xref,
    required this.name,
    required this.relationship,
    required this.degree,
    required this.illness,
    required this.category,
    required this.icd,
    required this.dateText,
    required this.age,
    required this.isEarly,
  });

  factory _Illness.fromJson(Map<String, dynamic> json) => _Illness(
    xref: json['xref'] as String,
    name: json['name'] as String? ?? '',
    relationship: json['relationship'] as String? ?? '',
    degree: json['degree'] as int? ?? 0,
    illness: json['illness'] as String? ?? '',
    category: json['category'] as String? ?? 'other',
    icd: json['icd'] as String? ?? '',
    dateText: json['dateText'] as String? ?? '',
    age: json['age'] as int?,
    isEarly: json['isEarly'] == true,
  );

  final String xref;
  final String name;
  final String relationship;
  final int degree;
  final String illness;
  final String category;
  final String icd;
  final String dateText;
  final int? age;
  final bool isEarly;
}

class _IllnessRow extends StatelessWidget {
  const _IllnessRow({required this.illness});

  final _Illness illness;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final who = [
      if (illness.relationship.isNotEmpty) illness.relationship,
      l10n.degreeOfRelationship(illness.degree),
    ];
    final when = [
      if (illness.dateText.isNotEmpty) illness.dateText,
      if (illness.age != null) l10n.ageAtDiagnosis(illness.age!),
    ];

    return InkWell(
      onTap: () => openPerson(context, illness.xref),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    illness.icd.isEmpty
                        ? illness.illness
                        : '${illness.illness} (${illness.icd})',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${illness.name} · ${who.join(' · ')}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (when.isNotEmpty)
                    Text(
                      when.join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
            if (illness.isEarly)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.pending.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l10n.earlyOnset,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.pending,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: AppColors.cardShadow,
    ),
    clipBehavior: Clip.antiAlias,
    child: Material(
      color: Colors.transparent,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.divider),
            children[i],
          ],
        ],
      ),
    ),
  );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textSecondary),
    ),
  );
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
          Expanded(
            child: Text(
              AppLocalizations.of(context)!.familyHealthTitle,
              style: const TextStyle(
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
