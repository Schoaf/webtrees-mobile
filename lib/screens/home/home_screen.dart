import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/quick_note_store.dart';
import '../../state/app_providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/person_card.dart';
import '../add_person/add_person_screen.dart';
import '../search/person_detail_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<_HomeData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HomeData> _load() async {
    final client = ref.read(webtreesClientProvider);
    final tree = ref.read(treeNameProvider);
    final info = await client.info(tree);
    final treeInfo = (info['trees'] as List<dynamic>).cast<Map<String, dynamic>>().firstWhere(
          (t) => t['name'] == tree,
          orElse: () => const {},
        );

    Map<String, dynamic>? startPerson;
    final defaultXref = treeInfo['defaultXref'] as String? ?? '';
    final userXref = treeInfo['userXref'] as String? ?? '';
    final xref = defaultXref.isNotEmpty ? defaultXref : userXref;
    if (xref.isNotEmpty) {
      final individual = await client.individual(tree, xref);
      startPerson = individual['person'] as Map<String, dynamic>?;
    }

    return _HomeData(
      treeTitle: treeInfo['title'] as String? ?? 'Stammbaum',
      individualCount: treeInfo['individuals'] as int? ?? 0,
      startPerson: startPerson,
      realName: (info['user'] as Map<String, dynamic>)['realName'] as String? ?? '',
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<_HomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Konnte nicht laden: ${snapshot.error}'));
          }

          final data = snapshot.data!;
          return Column(
            children: [
              _Header(title: data.treeTitle, initials: _initials(data.realName)),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  children: [
                    _SearchEntryButton(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push(MaterialPageRoute(builder: (_) => const AddPersonScreen()))
                          .then((_) => setState(() => _future = _load())),
                      icon: const Icon(Icons.add),
                      label: const Text('Neue Person hinzufügen'),
                    ),
                    const SizedBox(height: 18),
                    if (data.startPerson != null) ...[
                      const Text(
                        'Startperson',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      PersonCard(
                        person: data.startPerson!,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: data.startPerson!['xref'] as String)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const _UnsyncedNotes(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${data.individualCount} Personen im Stammbaum',
                  style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.initials});

  final String title;
  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      decoration: BoxDecoration(color: AppColors.surface, boxShadow: AppColors.cardShadow),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.14), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchEntryButton extends StatelessWidget {
  const _SearchEntryButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: const SizedBox(
          height: 56,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Icon(Icons.search, size: 20, color: AppColors.textSecondary),
                SizedBox(width: 12),
                Text('Person suchen…', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({
    required this.treeTitle,
    required this.individualCount,
    required this.startPerson,
    required this.realName,
  });

  final String treeTitle;
  final int individualCount;
  final Map<String, dynamic>? startPerson;
  final String realName;
}

class _UnsyncedNotes extends ConsumerWidget {
  const _UnsyncedNotes();

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
            Text(
              'Nicht synchronisiert (${notes.length})',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            for (final note in notes) ...[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: note.xref == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => PersonDetailScreen(xref: note.xref!)),
                          ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(note.personGuess, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                        Text(note.text, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}
