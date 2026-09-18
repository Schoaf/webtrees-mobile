import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/add_fact_sheet.dart';
import '../../widgets/person_avatar.dart';
import '../../widgets/person_card.dart';

/// Full "review everything we know" view for one person — priority-2 in the
/// project plan — plus the fast fact-capture entry point (priority-1),
/// since every fact needs a person anyway.
class PersonDetailScreen extends ConsumerStatefulWidget {
  const PersonDetailScreen({super.key, required this.xref});

  final String xref;

  @override
  ConsumerState<PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends ConsumerState<PersonDetailScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<Map<String, dynamic>> _load() {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    return client.individual(tree, widget.xref);
  }

  Future<void> _openAddFact(String name) async {
    final result = await showModalBottomSheet<AddFactResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AddFactSheet(xref: widget.xref, personName: name),
    );
    if (!mounted || result == null) return;

    switch (result) {
      case AddFactResult.posted:
        setState(() => _future = _load());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fakt gespeichert — wartet ggf. auf Freigabe.')),
        );
      case AddFactResult.savedLocally:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Server nicht erreichbar — lokal gespeichert, später synchronisieren.")),
        );
      case AddFactResult.cancelled:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Konnte nicht laden: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          if (data['ok'] == false) {
            return Center(child: Text('Kein Zugriff: ${data['error']}'));
          }

          final person = data['person'] as Map<String, dynamic>;
          final name = person['name'] as String? ?? '(kein Name)';
          final facts = (data['facts'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          final parentFamilies = (data['parentFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
          final spouseFamilies = (data['spouseFamilies'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();

          return Column(
            children: [
              _Header(name: name),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                      child: Column(
                        children: [
                          PersonAvatar(
                            sex: person['sex'] as String? ?? 'U',
                            isDead: person['isDead'] as bool? ?? false,
                            size: 84,
                          ),
                          const SizedBox(height: 10),
                          Text(name, style: const TextStyle(fontSize: 24, color: AppColors.textPrimary)),
                          if ((person['lifespan'] as String? ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                person['lifespan'] as String,
                                style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (facts.isNotEmpty) _FactsCard(facts: facts),
                    for (final family in parentFamilies) ...[
                      if (family['husband'] != null || family['wife'] != null)
                        _Section(
                          title: 'Eltern',
                          people: [
                            if (family['husband'] != null) family['husband'] as Map<String, dynamic>,
                            if (family['wife'] != null) family['wife'] as Map<String, dynamic>,
                          ],
                        ),
                    ],
                    for (final family in spouseFamilies) ...[
                      if (family['spouse'] != null)
                        _Section(
                          title: (family['spouse'] as Map<String, dynamic>)['sex'] == 'F' ? 'Ehepartnerin' : 'Ehepartner',
                          people: [family['spouse'] as Map<String, dynamic>],
                        ),
                    ],
                    if (spouseFamilies.expand((f) => f['children'] as List<dynamic>? ?? []).isNotEmpty)
                      _Section(
                        title: 'Kinder (${spouseFamilies.fold<int>(0, (n, f) => n + (f['children'] as List<dynamic>? ?? []).length)})',
                        people: spouseFamilies
                            .expand((f) => (f['children'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>())
                            .toList(),
                      ),
                    const SizedBox(height: 90),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null || data['ok'] == false || data['canEdit'] != true) return const SizedBox.shrink();
          final name = (data['person'] as Map<String, dynamic>)['name'] as String? ?? '';
          return FloatingActionButton.extended(
            onPressed: () => _openAddFact(name),
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.bolt),
            label: const Text('Fakt hinzufügen'),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(color: AppColors.surface, boxShadow: AppColors.cardShadow),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});

  final List<Map<String, dynamic>> facts;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppColors.cardShadow),
      child: Column(
        children: [
          for (var i = 0; i < facts.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: i < facts.length - 1 ? const Border(bottom: BorderSide(color: AppColors.divider)) : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(facts[i]['label'] as String? ?? facts[i]['tag'] as String,
                      style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                  Flexible(
                    child: Text(
                      _factValueText(facts[i]),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _factValueText(Map<String, dynamic> fact) {
    final parts = <String>[];
    final value = fact['value'] as String? ?? '';
    if (value.isNotEmpty) parts.add(value);
    final date = fact['date'] as Map<String, dynamic>?;
    if (date != null) parts.add(date['text'] as String);
    final place = fact['place'] as Map<String, dynamic>?;
    if (place != null) parts.add(place['short'] as String);
    return parts.isEmpty ? '—' : parts.join(' · ');
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.people});

  final String title;
  final List<Map<String, dynamic>> people;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            children: [
              for (var i = 0; i < people.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                PersonCard(
                  person: people[i],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: people[i]['xref'] as String)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
